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

@MainActor
final class CameraCaptureService: NSObject {
    static let shared = CameraCaptureService()
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    // Delegate untuk distribusi frame
    var onVideoFrameCaptured: ((CMSampleBuffer) -> Void)?
    var onPhotoCaptured: ((AVCapturePhoto) -> Void)?
    private var isConfigured = false
    
    // Status Portrait Mode
    var isPortraitModeActive = false
    
    private override init() {
        super.init()
    }
    
    func configureAndStart() {
        startOrientationTracking()
        
        if isConfigured {
            if !captureSession.isRunning {
                Task.detached(priority: .userInitiated) {
                    await self.captureSession.startRunning()
                    HaispaceLogger.info("Camera capture session started (re-use)", category: "camera")
                }
            }
            return
        }
        
        // Membutuhkan izin kamera
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                HaispaceLogger.error("Akses kamera ditolak", category: "camera")
                return
            }
            Task { @MainActor in
                self?.setupSession()
            }
        }
    }
    
    private func setupSession() {
        captureSession.beginConfiguration()
        
        // Atur preset untuk mendapatkan balance antara preview cepat dan foto yang bagus
        captureSession.sessionPreset = .photo
        
        // Cari kamera utama (Wide Angle)
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            HaispaceLogger.error("Tidak bisa menemukan kamera belakang", category: "camera")
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
        }
        
        // Konfigurasi fitur kamera bawaan iPhone (HDR, Low Light, Autofokus)
        do {
            try videoDevice.lockForConfiguration()
            
            // 1. Aktifkan Video HDR (Anti-Backlight & High Dynamic Range) untuk live preview
            if videoDevice.activeFormat.isVideoHDRSupported {
                videoDevice.isVideoHDREnabled = true
                HaispaceLogger.info("Video HDR (Anti-Backlight) diaktifkan", category: "camera")
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
        }
        
        // Setup Photo Output untuk jepretan full quality
        // Note: isHighResolutionCaptureEnabled is deprecated in iOS 16+, using default maxPhotoDimensions
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        
        captureSession.commitConfiguration()
        
        Task.detached(priority: .userInitiated) {
            await self.captureSession.startRunning()
            HaispaceLogger.info("Camera capture session started", category: "camera")
        }
        
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
    
    private func startOrientationTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        // Pemicu awal
        handleOrientationChange()
    }
    
    private func stopOrientationTracking() {
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
        
        // Perbarui orientasi koneksi video (preview stream)
        if let videoConnection = videoOutput.connection(with: .video), videoConnection.isVideoOrientationSupported {
            videoConnection.videoOrientation = avOrientation
        }
        
        // Perbarui orientasi koneksi foto (jepretan resolusi tinggi)
        if let photoConnection = photoOutput.connection(with: .video), photoConnection.isVideoOrientationSupported {
            photoConnection.videoOrientation = avOrientation
        }
    }
    
    /// Mengatur faktor perbesaran (zoom) kamera utama belakang
    func setZoom(factor: CGFloat) {
        // Ambil device back camera default
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            
            let minZoom = device.minAvailableVideoZoomFactor
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 5.0) // Batasi maksimal 5x untuk kestabilan kualitas
            let targetZoom = max(min(factor, maxZoom), minZoom)
            
            device.videoZoomFactor = targetZoom
            HaispaceLogger.info("Zoom factor diubah menjadi \(targetZoom)x", category: "camera")
        } catch {
            HaispaceLogger.error("Gagal mengunci konfigurasi kamera untuk zoom: \(error.localizedDescription)", category: "camera")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Teruskan ke VideoEncoderService
        Task { @MainActor in
            self.onVideoFrameCaptured?(sampleBuffer)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            HaispaceLogger.error("Gagal capture foto: \(error.localizedDescription)", category: "camera")
            return
        }
        Task { @MainActor in
            self.onPhotoCaptured?(photo)
        }
    }
}
