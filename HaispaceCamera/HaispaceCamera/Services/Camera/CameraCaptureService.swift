// CameraCaptureService.swift
// HaispaceCamera — Services/Camera
//
// Mengelola sesi AVCapture, video stream ke VideoEncoder, 
// dan pengambilan foto kualitas tinggi.
//
// Ref: docs/design/20_haicamera_iphone.md

import Foundation
import AVFoundation
import UIKit

final class CameraCaptureService: NSObject {
    static let shared = CameraCaptureService()
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    // FIX #1 & #3: Serial queue khusus untuk semua operasi AVCaptureSession.
    // AVCaptureSession bukan Sendable — dilarang diakses dari Task.detached atau thread sembarang.
    // Queue ini menjadi single owner untuk captureSession dan isConfigured flag.
    private let sessionQueue = DispatchQueue(label: "id.haispaceproject.camera.sessionQueue", qos: .userInitiated)
    
    // Delegate untuk distribusi frame
    nonisolated(unsafe) var onVideoFrameCaptured: ((CMSampleBuffer) -> Void)?
    nonisolated(unsafe) var onPhotoCaptured: ((AVCapturePhoto) -> Void)?
    
    // FIX #3: isConfigured hanya boleh dibaca/ditulis dari dalam sessionQueue
    private var isConfigured = false
    
    // Status Portrait Mode
    nonisolated(unsafe) var isPortraitModeActive = false
    nonisolated(unsafe) var isSessionActive = false
    
    private override init() {
        super.init()
    }
    
    func configureAndStart() {
        // FIX #2: startOrientationTracking() memanggil UIKit — harus dari main thread
        if Thread.isMainThread {
            startOrientationTracking()
        } else {
            DispatchQueue.main.async { self.startOrientationTracking() }
        }
        
        // FIX #1 & #3: Semua akses ke captureSession dan isConfigured melalui sessionQueue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isConfigured {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning() // Dipanggil di sessionQueue, aman
                    HaispaceLogger.info("Camera capture session started (re-use)", category: "camera")
                }
                return
            }
            
            // Membutuhkan izin kamera
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self, granted else {
                    HaispaceLogger.error("Akses kamera ditolak", category: "camera")
                    return
                }
                // setupSession() langsung di sessionQueue (bukan Task baru)
                self.sessionQueue.async {
                    self.setupSession()
                }
            }
        }
    }
    
    private func setupSession() {
        HaispaceLogger.info("[setupSession] Langkah 1: beginConfiguration", category: "camera")
        captureSession.beginConfiguration()
        
        // Atur preset 720p untuk preview yang ringan, cepat, dan hemat bandwidth
        captureSession.sessionPreset = .hd1280x720
        
        // Cari kamera utama (Wide Angle)
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            HaispaceLogger.error("Tidak bisa menemukan kamera belakang", category: "camera")
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
            HaispaceLogger.info("[setupSession] Langkah 2: video input ditambahkan", category: "camera")
        }
        
        // Konfigurasi fitur kamera bawaan iPhone (HDR, Low Light, Autofokus)
        do {
            try videoDevice.lockForConfiguration()
            
            // 1. Aktifkan Video HDR secara aman tanpa memicu exception
            if videoDevice.activeFormat.isVideoHDRSupported {
                if videoDevice.automaticallyAdjustsVideoHDREnabled {
                    videoDevice.automaticallyAdjustsVideoHDREnabled = true
                }
                HaispaceLogger.info("Video HDR diaktifkan", category: "camera")
            }
            
            // 2. Aktifkan Low Light Boost otomatis untuk ruangan redup
            if videoDevice.isLowLightBoostSupported {
                videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
                HaispaceLogger.info("Low Light Boost diaktifkan", category: "camera")
            }
            
            // 3. Set Continuous Auto Focus & Exposure agar selalu stabil dan terang
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            
            videoDevice.unlockForConfiguration()
        } catch {
            HaispaceLogger.error("Gagal mengonfigurasi fitur kamera bawaan iPhone: \(error.localizedDescription)", category: "camera")
        }
        
        // Setup Video Output untuk live stream P2P
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "id.haispaceproject.camera.videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            HaispaceLogger.info("[setupSession] Langkah 3: video output ditambahkan", category: "camera")
        }
        
        // Setup Photo Output untuk jepretan full quality
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            HaispaceLogger.info("[setupSession] Langkah 4: photo output ditambahkan", category: "camera")
        }
        
        captureSession.commitConfiguration()
        HaispaceLogger.info("[setupSession] Langkah 5: commitConfiguration selesai", category: "camera")
        
        // FIX: maxPhotoQualityPrioritization HANYA boleh di-set SETELAH commitConfiguration
        // dan di-gate dengan videoDevice.activeFormat.isHighPhotoQualitySupported untuk mencegah NSInvalidArgumentException.
        if videoDevice.activeFormat.isHighPhotoQualitySupported {
            photoOutput.maxPhotoQualityPrioritization = .quality
            HaispaceLogger.info("[setupSession] maxPhotoQualityPrioritization set to quality", category: "camera")
        } else {
            photoOutput.maxPhotoQualityPrioritization = .balanced
            HaispaceLogger.info("[setupSession] maxPhotoQualityPrioritization set to balanced", category: "camera")
        }
        
        captureSession.startRunning()
        HaispaceLogger.info("Camera capture session started", category: "camera")
        
        isConfigured = true
    }
    
    /// Trigger pemotretan kualitas tinggi (dipanggil saat menerima instruksi dari iPad)
    func captureHighQualityPhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = .off // Flash menggunakan layar iPad, iPhone flash dimatikan
        
        // Aktifkan data kedalaman (depth map) jika mode Portrait aktif dan didukung hardware
        if isPortraitModeActive && photoOutput.isDepthDataDeliverySupported {
            photoSettings.isDepthDataDeliveryEnabled = true
            photoSettings.embedsDepthDataInPhoto = true
            HaispaceLogger.info("Depth data delivery diaktifkan untuk jepretan Portrait", category: "camera")
        }
        
        // Aktifkan pemrosesan gambar penuh Apple (Smart HDR, Deep Fusion, Neural Engine ISP)
        if photoOutput.maxPhotoQualityPrioritization == .quality {
            photoSettings.photoQualityPrioritization = .quality
        } else {
            photoSettings.photoQualityPrioritization = .balanced
        }
        
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        HaispaceLogger.info("Memicu jepretan foto kualitas tinggi (Smart HDR/Deep Fusion)", category: "camera")
    }
    
    /// Kunci Fokus dan Eksposur dari jarak jauh pada titik tertentu (0.0 - 1.0)
    func setFocusAndExposurePoint(x: Float, y: Float) {
        guard let deviceInput = captureSession.inputs.first as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        
        do {
            try device.lockForConfiguration()
            
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
            HaispaceLogger.info("Remote focus & exposure lock set at: (\(x), \(y))", category: "camera")
        } catch {
            HaispaceLogger.error("Gagal melakukan remote focus & exposure: \(error)", category: "camera")
        }
    }
    
    func stop() {
        stopOrientationTracking()
        if captureSession.isRunning {
            captureSession.stopRunning()
            HaispaceLogger.info("Camera capture session stopped", category: "camera")
        }
    }
    
    // MARK: - Orientation Tracking
    
    // FIX #2: Semua method ini harus dipanggil dari main thread.
    // configureAndStart() sudah menjamin ini.
    private func startOrientationTracking() {
        assert(Thread.isMainThread, "startOrientationTracking() harus dipanggil dari main thread")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        // Pemicu awal — sudah di main thread, aman
        handleOrientationChange()
    }
    
    private func stopOrientationTracking() {
        // stopOrientationTracking() dipanggil dari stop() — pastikan di main thread
        if Thread.isMainThread {
            _stopOrientationTrackingOnMain()
        } else {
            DispatchQueue.main.async { self._stopOrientationTrackingOnMain() }
        }
    }
    
    private func _stopOrientationTrackingOnMain() {
        assert(Thread.isMainThread)
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    @objc private func handleOrientationChange() {
        let deviceOrientation = UIDevice.current.orientation
        let avOrientation: AVCaptureVideoOrientation
        
        switch deviceOrientation {
        case .portrait:
            avOrientation = .portrait
        case .landscapeLeft:
            avOrientation = .landscapeRight // Kamera belakang mirror-mapping
        case .landscapeRight:
            avOrientation = .landscapeLeft  // Kamera belakang mirror-mapping
        case .portraitUpsideDown:
            avOrientation = .portraitUpsideDown
        default:
            return // Tetap gunakan orientasi sebelumnya jika posisi datar (flat)
        }
        
        // FIX #2: Perubahan orientasi pada AVCaptureConnection harus di sessionQueue
        // (AVCaptureConnection bukan thread-safe)
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if let videoConnection = self.videoOutput.connection(with: .video),
               videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = avOrientation
            }
            if let photoConnection = self.photoOutput.connection(with: .video),
               photoConnection.isVideoOrientationSupported {
                photoConnection.videoOrientation = avOrientation
            }
        }
    }
    
    /// Mengatur faktor perbesaran (zoom) kamera secara dinamis (mendukung 0.5x Ultra Wide, 1x Wide, 2x Zoom)
    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let currentInput = self.captureSession.inputs.first as? AVCaptureDeviceInput
            let currentDevice = currentInput?.device
            
            // 1. Cek apakah device saat ini sudah mendukung faktor zoom target secara langsung (misal Triple/Dual Wide Camera)
            if let device = currentDevice {
                let minZ = device.minAvailableVideoZoomFactor
                let maxZ = min(device.maxAvailableVideoZoomFactor, 5.0)
                if factor >= minZ && factor <= maxZ {
                    do {
                        try device.lockForConfiguration()
                        device.videoZoomFactor = factor
                        device.unlockForConfiguration()
                        HaispaceLogger.info("[Zoom] Zoom factor diubah menjadi \(factor)x pada \(device.localizedName)", category: "camera")
                        return
                    } catch {
                        HaispaceLogger.error("[Zoom] Gagal set zoom factor: \(error.localizedDescription)", category: "camera")
                    }
                }
            }
            
            // 2. Jika < 0.8x, beralih ke Ultra Wide Camera jika tersedia
            let targetDeviceType: AVCaptureDevice.DeviceType = (factor < 0.8) ? .builtInUltraWideCamera : .builtInWideAngleCamera
            let targetZoom: CGFloat = (factor < 0.8) ? 1.0 : min(max(factor, 1.0), 5.0)
            
            guard let newDevice = AVCaptureDevice.default(targetDeviceType, for: .video, position: .back),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                HaispaceLogger.warning("[Zoom] Device kamera type \(targetDeviceType) tidak tersedia pada perangkat ini", category: "camera")
                return
            }
            
            // Jangan ganti input jika sudah menggunakan device yang sama
            if currentDevice?.deviceType == newDevice.deviceType {
                do {
                    try newDevice.lockForConfiguration()
                    newDevice.videoZoomFactor = targetZoom
                    newDevice.unlockForConfiguration()
                    HaispaceLogger.info("[Zoom] Zoom diubah menjadi \(targetZoom)x pada \(newDevice.localizedName)", category: "camera")
                } catch {
                    HaispaceLogger.error("[Zoom] Gagal set zoom: \(error.localizedDescription)", category: "camera")
                }
                return
            }
            
            // Ganti input kamera
            self.captureSession.beginConfiguration()
            if let oldInput = currentInput {
                self.captureSession.removeInput(oldInput)
            }
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
            }
            self.captureSession.commitConfiguration()
            
            do {
                try newDevice.lockForConfiguration()
                newDevice.videoZoomFactor = targetZoom
                newDevice.unlockForConfiguration()
                HaispaceLogger.info("[Zoom] Berhasil beralih ke kamera \(newDevice.localizedName) (Zoom target: \(factor)x)", category: "camera")
            } catch {
                HaispaceLogger.error("[Zoom] Gagal set zoom setelah ganti input: \(error.localizedDescription)", category: "camera")
            }
        }
    }
    
    /// Mengaktifkan atau mematikan mode Portrait
    func setPortraitMode(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isPortraitModeActive = enabled
            HaispaceLogger.info("[PortraitMode] Mode Portrait diset ke \(enabled ? "AKTIF (Depth/Bokeh)" : "NONAKTIF")", category: "camera")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Teruskan ke VideoEncoderService secara langsung dan sinkron
        self.onVideoFrameCaptured?(sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            HaispaceLogger.error("Gagal capture foto: \(error.localizedDescription)", category: "camera")
            return
        }
        self.onPhotoCaptured?(photo)
    }
}
