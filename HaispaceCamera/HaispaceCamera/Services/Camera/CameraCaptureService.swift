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
import CoreImage

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
    
    // MARK: - Depth-Based Bokeh (AVCaptureDepthDataOutput)
    // Menggunakan depth data dari hardware stereo lensa Dual Wide iPhone 14 —
    // jauh lebih natural dibanding Vision AI segmentation karena menggunakan
    // jarak fisik objek nyata (bukan binary mask) untuk menentukan intensitas blur.
    private let depthOutput = AVCaptureDepthDataOutput()
    // Sinkronisasi depth data + video frame agar keduanya dari momen yang sama
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    // CIContext Metal-accelerated untuk rendering bokeh composite
    private lazy var ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpaceCreateDeviceRGB() as Any
    ])
    // Cache depth CIImage terakhir untuk efisiensi (reuse antar frame)
    nonisolated(unsafe) private var lastDepthImage: CIImage? = nil
    
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
        
        // Setup Depth Output untuk live bokeh (dual-cam depth dari hardware stereo iPhone 14)
        // isFilteringEnabled: smoothing temporal untuk depth map yang lebih stabil
        depthOutput.isFilteringEnabled = true
        if captureSession.canAddOutput(depthOutput) {
            captureSession.addOutput(depthOutput)
            HaispaceLogger.info("[setupSession] Langkah 4b: depth output ditambahkan (hardware depth bokeh aktif)", category: "camera")
        } else {
            HaispaceLogger.warning("[setupSession] Depth output tidak bisa ditambahkan — bokeh akan dinonaktifkan", category: "camera")
        }
        
        captureSession.commitConfiguration()
        HaispaceLogger.info("[setupSession] Langkah 5: commitConfiguration selesai", category: "camera")
        
        // Setup AVCaptureDataOutputSynchronizer: sinkronkan video + depth data
        // Ini memastikan setiap frame video memiliki depth map yang tepat waktu
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        outputSynchronizer?.setDelegate(self, queue: DispatchQueue(label: "id.haispaceproject.camera.syncQueue", qos: .userInteractive))
        HaispaceLogger.info("[setupSession] Langkah 5b: depth+video synchronizer dikonfigurasi", category: "camera")
        
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
    
    /// Mengaktifkan atau mematikan mode Portrait (Depth-Based Live Bokeh)
    /// Menggunakan AVCaptureDepthDataOutput — hardware stereo depth dari Dual Wide camera
    /// untuk menghasilkan bokeh natural berdasarkan jarak fisik objek, bukan flat mask.
    func setPortraitMode(enabled: Bool) {
        isPortraitModeActive = enabled
        if !enabled { lastDepthImage = nil }
        HaispaceLogger.info("[PortraitMode] Depth-Based Bokeh \(enabled ? "AKTIF" : "NONAKTIF")", category: "camera")
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate
// Menerima frame video + depth data yang tersinkronisasi secara hardware
extension CameraCaptureService: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput collection: AVCaptureSynchronizedDataCollection
    ) {
        // Ambil video frame
        guard let syncedVideo = collection.synchronizedData(for: videoOutput)
                as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideo.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideo.sampleBuffer)
        else { return }
        
        // Jika portrait mode aktif, proses depth-based bokeh sebelum encode
        if self.isPortraitModeActive {
            // Ambil depth data jika tersedia di frame ini
            if let syncedDepth = collection.synchronizedData(for: depthOutput)
                    as? AVCaptureSynchronizedDepthData,
               !syncedDepth.depthDataWasDropped {
                
                // Konversi depth map ke Float32 (jarak dalam meter per pixel)
                let depthData = syncedDepth.depthData
                    .converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                let depthCI = CIImage(cvPixelBuffer: depthData.depthDataMap)
                
                // Normalize + scale depth map ke resolusi video
                let videoCI = CIImage(cvPixelBuffer: pixelBuffer)
                let scaleX = videoCI.extent.width / depthCI.extent.width
                let scaleY = videoCI.extent.height / depthCI.extent.height
                lastDepthImage = depthCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            }
            
            // Terapkan depth bokeh menggunakan depth map terakhir
            if let depthCI = lastDepthImage {
                applyDepthBokeh(to: pixelBuffer, depthMap: depthCI)
            }
        }
        
        self.onVideoFrameCaptured?(syncedVideo.sampleBuffer)
    }
    
    /// Menerapkan natural depth-of-field bokeh berdasarkan peta kedalaman fisik.
    /// Orang di depth dekat = tajam, background di depth jauh = blur natural.
    ///
    /// Depth Float32 dari iPhone 14 Dual Wide Camera:
    ///   - Nilai kecil (0.2–1.5m) = dekat kamera = orang = TAJAM
    ///   - Nilai besar (1.5–5.0m+) = jauh dari kamera = background = BLUR
    ///
    /// Kita perlu: mask putih (1.0) = tajam, mask hitam (0.0) = blur
    /// Jadi: mask = 1 - clamp(depth / maxDepth, 0, 1)
    nonisolated private func applyDepthBokeh(to pixelBuffer: CVPixelBuffer, depthMap: CIImage) {
        let original = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Step 1: Blur seluruh frame untuk latar belakang
        let blurred = original
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18.0])
            .cropped(to: original.extent)
        
        // Step 2: Normalisasi depth map ke range 0.0–1.0
        // Depth Float32 dari dual-cam ~= 0.0 (sangat dekat) hingga 5.0+ (sangat jauh)
        // Kita clamp ke range fokus yang relevan: 0.3m–3.0m
        // Setelah normalisasi: dekat = 0.0 (hitam), jauh = 1.0 (putih)
        // Lalu inversi agar: dekat = 1.0 (putih = tajam), jauh = 0.0 (hitam = blur)
        let nearPlane: CGFloat = 0.3   // meter — titik terdekat yang masih tajam
        let farPlane:  CGFloat = 3.0   // meter — titik terjauh yang masih relevan
        
        // Normalisasi: (depth - nearPlane) / (farPlane - nearPlane)
        //              = depth * scale + bias
        // scale = 1 / (farPlane - nearPlane) = 1 / 2.7 ≈ 0.37
        // bias  = -nearPlane * scale         = -0.3 * 0.37 ≈ -0.111
        let scale = 1.0 / (farPlane - nearPlane)    // ~0.370
        let bias  = -nearPlane * scale               // ~-0.111
        
        // Terapkan normalisasi via CIColorMatrix
        let normalizedDepth = depthMap.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ])
        
        // Clamp ke 0.0–1.0 dan INVERSI: dekat (kecil) → putih (tajam)
        let invertedDepth = normalizedDepth.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        
        // Clamp ke range valid 0.0–1.0
        let clampedMask = invertedDepth.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        
        // Softening tepi mask agar transisi bokeh terlihat natural (bukan garis keras)
        let softMask = clampedMask
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 8.0])
            .cropped(to: original.extent)
        
        // Step 3: CIBlendWithMask:
        //   mask putih (dekat/orang) → tampilkan original (tajam)
        //   mask hitam (jauh/background) → tampilkan blurred
        let bokehComposite = original.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: softMask
        ])
        
        // Step 4: Render in-place ke pixelBuffer (Metal GPU, zero extra allocation)
        ciContext.render(bokehComposite, to: pixelBuffer)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// Delegate ini hanya dipakai saat TIDAK ada synchronizer aktif (fallback)
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Fallback: jika depth output tidak tersedia, kirim frame langsung tanpa bokeh
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
