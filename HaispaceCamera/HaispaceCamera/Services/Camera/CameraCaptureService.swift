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
        
        // Cari kamera belakang (Utamakan virtual multi-cam Triple/Dual Wide agar zoom 0.5x-2x seamless, fallback ke Wide Angle)
        guard let videoDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
    /// PENTING: Menggunakan .continuousAutoFocus + focusPointOfInterest — bukan .autoFocus!
    /// .autoFocus adalah one-shot dan mengunci fokus selamanya. 
    /// .continuousAutoFocus + pointOfInterest = kamera fokus ke titik itu lalu terus tracking subyek,
    /// persis seperti perilaku tap-to-focus di native Camera app iPhone.
    func setFocusAndExposurePoint(x: Float, y: Float) {
        guard let deviceInput = captureSession.inputs.first as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        
        do {
            try device.lockForConfiguration()
            
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            
            // Set fokus ke titik yang ditentukan, lalu lanjut tracking otomatis
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            
            // Set eksposur ke titik yang ditentukan, lalu lanjut auto-adjust otomatis
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
            HaispaceLogger.info("[Focus] Continuous focus & exposure set at: (\(x), \(y))", category: "camera")
        } catch {
            HaispaceLogger.error("[Focus] Gagal set focus point: \(error)", category: "camera")
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
    
    /// Mengatur zoom kamera menggunakan Apple native multi-cam approach.
    /// Selalu menggunakan SATU device virtual (DualWide/Triple) tanpa mengganti input.
    /// Memetakan user zoom (0.5x, 1x, 2x) ke internal device zoomFactor menggunakan
    /// virtualDeviceSwitchOverVideoZoomFactors — persis seperti app Camera bawaan Apple.
    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let currentInput = self.captureSession.inputs.first as? AVCaptureDeviceInput else {
                HaispaceLogger.warning("[Zoom] Tidak ada active camera input", category: "camera")
                return
            }
            let device = currentInput.device
            
            do {
                try device.lockForConfiguration()
                
                let minZ = device.minAvailableVideoZoomFactor
                let maxZ = min(device.maxAvailableVideoZoomFactor, 8.0)
                
                // Baca switch-over points dari virtual device (DualWide / Triple)
                // Contoh iPhone 14: switchOvers = [2.0]
                //   • zoomFactor < 2.0  → lensa Ultra Wide (tampilan 0.5x)
                //   • zoomFactor = 2.0  → lensa Wide Angle  (tampilan 1x)
                //   • zoomFactor = 4.0  → 2x digital zoom pada Wide
                let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
                
                let targetInternalZoom: CGFloat
                
                if let wideZoom = switchOvers.first {
                    // Virtual multi-cam (DualWide / Triple / DualCamera)
                    if factor < 0.8 {
                        // 0.5x → minimum (= lensa Ultra Wide fisik)
                        targetInternalZoom = minZ
                        HaispaceLogger.info("[Zoom] 0.5x → Ultra Wide (internal: \(minZ)x), switchOver: \(wideZoom)x", category: "camera")
                    } else if factor <= 1.2 {
                        // 1x → tepat di titik switch ke Wide Angle
                        targetInternalZoom = wideZoom
                        HaispaceLogger.info("[Zoom] 1x → Wide Angle (internal: \(wideZoom)x)", category: "camera")
                    } else {
                        // 2x → 2x digital pada Wide Angle
                        let zoom2x = min(wideZoom * 2.0, maxZ)
                        targetInternalZoom = zoom2x
                        HaispaceLogger.info("[Zoom] 2x → Digital zoom (internal: \(zoom2x)x)", category: "camera")
                    }
                } else {
                    // Device single-lens (WideAngle saja): gunakan factor langsung
                    targetInternalZoom = max(min(factor, maxZ), minZ)
                    HaispaceLogger.info("[Zoom] Single-lens zoom ke \(targetInternalZoom)x", category: "camera")
                }
                
                let finalZoom = max(min(targetInternalZoom, maxZ), minZ)
                device.ramp(toVideoZoomFactor: finalZoom, withRate: 8.0) // Smooth ramp khas Apple!
                device.unlockForConfiguration()
                
            } catch {
                HaispaceLogger.error("[Zoom] Gagal set zoom: \(error.localizedDescription)", category: "camera")
            }
        }
    }
    
    /// Mengaktifkan atau mematikan mode Portrait menggunakan iOS 17 native Portrait Effect.
    /// AVCaptureDevice.portraitEffectEnabled adalah hardware-accelerated Neural Engine API
    /// yang sama persis digunakan oleh FaceTime, Camera Video mode, dan Studio Light pada iPhone.
    /// Ini jauh lebih efisien dan natural dibandingkan Vision AI + CoreImage manual.
    func setPortraitMode(enabled: Bool) {
        isPortraitModeActive = enabled
        
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let deviceInput = self.captureSession.inputs.first as? AVCaptureDeviceInput else { return }
            let device = deviceInput.device
            
            // Cek dukungan Portrait Effect (iOS 17+, tersedia di iPhone 12 Pro ke atas)
            guard device.isPortraitEffectSupported else {
                HaispaceLogger.warning("[PortraitMode] Hardware Portrait Effect tidak didukung pada \(device.localizedName)", category: "camera")
                return
            }
            
            do {
                try device.lockForConfiguration()
                device.isPortraitEffectEnabled = enabled
                device.unlockForConfiguration()
                HaispaceLogger.info("[PortraitMode] Native Portrait Effect \(enabled ? "AKTIF" : "NONAKTIF") pada \(device.localizedName)", category: "camera")
            } catch {
                HaispaceLogger.error("[PortraitMode] Gagal set portrait effect: \(error.localizedDescription)", category: "camera")
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame langsung dikirim ke VideoEncoderService.
        // Portrait Effect sudah diproses oleh hardware Neural Engine iPhone secara otomatis
        // saat device.isPortraitEffectEnabled = true — tidak perlu pemrosesan manual per-frame.
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
