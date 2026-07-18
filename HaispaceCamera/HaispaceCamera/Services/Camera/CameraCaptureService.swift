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
    
    // Dedicated queues untuk penanganan frame output
    private let videoQueue = DispatchQueue(label: "id.haispaceproject.camera.videoQueue")
    private let syncQueue = DispatchQueue(label: "id.haispaceproject.camera.syncQueue", qos: .userInteractive)
    
    // Simpan target zoom yang diinginkan agar bisa dikembalikan saat beralih mode
    nonisolated(unsafe) private var lastRequestedZoomFactor: CGFloat = 1.0
    
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
        
        // Preset 720p untuk live stream yang ringan dan hemat bandwidth
        captureSession.sessionPreset = .hd1280x720
        
        // Cari kamera belakang (Utamakan virtual multi-cam agar zoom 0.5x-2x seamless)
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
            
            if videoDevice.activeFormat.isVideoHDRSupported {
                if videoDevice.automaticallyAdjustsVideoHDREnabled {
                    videoDevice.automaticallyAdjustsVideoHDREnabled = true
                }
                HaispaceLogger.info("Video HDR diaktifkan", category: "camera")
            }
            if videoDevice.isLowLightBoostSupported {
                videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
                HaispaceLogger.info("Low Light Boost diaktifkan", category: "camera")
            }
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            videoDevice.unlockForConfiguration()
        } catch {
            HaispaceLogger.error("Gagal mengonfigurasi kamera: \(error.localizedDescription)", category: "camera")
        }
        
        // Setup Video Output untuk live stream P2P
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
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
        
        // depthOutput TIDAK ditambahkan di sini.
        // depth output akan ditambahkan secara dinamis HANYA saat portrait mode aktif,
        // bersamaan dengan penggantian preset ke .photo yang kompatibel dengan depth.
        
        captureSession.commitConfiguration()
        HaispaceLogger.info("[setupSession] Langkah 5: commitConfiguration selesai", category: "camera")
        
        // Set photo quality setelah commit
        if videoDevice.activeFormat.isHighPhotoQualitySupported {
            photoOutput.maxPhotoQualityPrioritization = .quality
            HaispaceLogger.info("[setupSession] maxPhotoQualityPrioritization: quality", category: "camera")
        } else {
            photoOutput.maxPhotoQualityPrioritization = .balanced
            HaispaceLogger.info("[setupSession] maxPhotoQualityPrioritization: balanced", category: "camera")
        }
        
        captureSession.startRunning()
        HaispaceLogger.info("Camera capture session started", category: "camera")
        
        // Atur default zoom awal ke 1.0x (Wide Angle Utama)
        self.applyZoomInternal(factor: 1.0)
        
        isConfigured = true
    }
    
    /// Trigger pemotretan kualitas tinggi (dipanggil saat menerima instruksi dari iPad)
    func captureHighQualityPhoto() {
        // Dijalankan di sessionQueue agar serialized — capturePhoto selalu terjadi
        // setelah setPortraitMode selesai mengubah konfigurasi session
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let photoSettings = AVCapturePhotoSettings()
            photoSettings.flashMode = .off
            
            // Aktifkan depth data hanya jika portrait mode aktif dan hardware mendukung
            if self.isPortraitModeActive && self.photoOutput.isDepthDataDeliverySupported {
                photoSettings.isDepthDataDeliveryEnabled = true
                photoSettings.embedsDepthDataInPhoto = true
                HaispaceLogger.info("Depth data delivery diaktifkan untuk jepretan Portrait", category: "camera")
            }
            
            // Gunakan .balanced saat portrait aktif (depth format tidak selalu support .quality)
            // Gunakan .quality saat normal (preset 720p mendukung .quality)
            if self.isPortraitModeActive {
                photoSettings.photoQualityPrioritization = .balanced
            } else if self.photoOutput.maxPhotoQualityPrioritization == .quality {
                photoSettings.photoQualityPrioritization = .quality
            } else {
                photoSettings.photoQualityPrioritization = .balanced
            }
            
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
            HaispaceLogger.info("Memicu jepretan foto kualitas tinggi (Smart HDR/Deep Fusion)", category: "camera")
        }
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
    ///
    /// CATATAN: Saat depthOutput aktif, format DualWide berubah sehingga minZ menjadi ~2.0.
    /// 0.5x (Ultra Wide) harus menggunakan nilai TEPAT DI BAWAH switchOver, bukan minZ.
    func setZoom(factor: CGFloat) {
        lastRequestedZoomFactor = factor
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.applyZoomInternal(factor: factor)
        }
    }
    
    /// Fungsi helper internal untuk mengubah zoom factor. Harus dipanggil dalam sessionQueue.
    private func applyZoomInternal(factor: CGFloat) {
        guard let currentInput = self.captureSession.inputs.first as? AVCaptureDeviceInput else {
            HaispaceLogger.warning("[Zoom] Tidak ada active camera input", category: "camera")
            return
        }
        let device = currentInput.device
        
        do {
            try device.lockForConfiguration()
            
            let maxZ = min(device.maxAvailableVideoZoomFactor, 8.0)
            let minZ = device.minAvailableVideoZoomFactor
            
            // Baca switch-over points dari virtual device (DualWide / Triple)
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
            
            let targetInternalZoom: CGFloat
            
            if let wideZoom = switchOvers.first {
                if factor < 0.8 {
                    // 0.5x → Ultra Wide: gunakan nilai minimum perangkat (minZ)
                    // Pada mode normal (non-depth), minZ bernilai 1.0 (Ultra Wide super lebar).
                    // Pada mode portrait (depth aktif), minZ menjadi 2.0 (Wide utama) secara otomatis oleh iOS.
                    targetInternalZoom = minZ
                    HaispaceLogger.info("[Zoom] 0.5x → Ultra Wide (internal: \(minZ)x, switchOver: \(wideZoom)x)", category: "camera")
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
    
    /// Mengaktifkan atau mematikan mode Portrait (Depth-Based Live Bokeh) secara dinamis.
    ///
    /// Cara kerja (persis seperti Apple Camera App):
    /// - Portrait ON  → ganti preset ke .photo (kompatibel depth) + tambahkan depthOutput + buat synchronizer
    /// - Portrait OFF → hapus depthOutput + kembali ke preset .hd1280x720 + kembalikan video delegate
    ///
    /// Preset .hd1280x720 TIDAK kompatibel dengan depthOutput.
    /// Preset .photo mendukung depth dan digunakan Apple Camera App saat portrait aktif.
    func setPortraitMode(enabled: Bool) {
        isPortraitModeActive = enabled
        if !enabled { lastDepthImage = nil }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if enabled {
                // LANGKAH 1: Ganti preset ke .photo yang mendukung depth data
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .photo
                HaispaceLogger.info("[PortraitMode] preset diganti ke .photo (depth-kompatibel)", category: "camera")
                
                // LANGKAH 2: Tambahkan depthOutput ke session
                self.depthOutput.isFilteringEnabled = true
                if self.captureSession.canAddOutput(self.depthOutput) {
                    self.captureSession.addOutput(self.depthOutput)
                    HaispaceLogger.info("[PortraitMode] depth output ditambahkan", category: "camera")
                } else {
                    HaispaceLogger.warning("[PortraitMode] depth output sudah ada atau tidak bisa ditambahkan", category: "camera")
                }
                
                // Lepaskan video delegate biasa agar tidak konflik dengan synchronizer
                self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
                
                // LANGKAH 3: Commit — depthOutput sekarang terdaftar di session
                self.captureSession.commitConfiguration()
                HaispaceLogger.info("[PortraitMode] session committed dengan depthOutput", category: "camera")
                
                // LANGKAH 4: Buat synchronizer SETELAH commit (wajib, output harus sudah terdaftar)
                self.outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                self.outputSynchronizer?.setDelegate(self, queue: self.syncQueue)
                HaispaceLogger.info("[PortraitMode] depth+video synchronizer dikonfigurasi", category: "camera")
                
                // Paksa zoom ke 1.0x agar depth map sinkron dengan lensa Wide Angle
                self.applyZoomInternal(factor: 1.0)
                HaispaceLogger.info("[PortraitMode] Depth-Based Bokeh AKTIF", category: "camera")
                
            } else {
                // LANGKAH 1: Matikan synchronizer dahulu
                self.outputSynchronizer?.setDelegate(nil, queue: nil)
                self.outputSynchronizer = nil
                HaispaceLogger.info("[PortraitMode] synchronizer dilepas", category: "camera")
                
                // LANGKAH 2: Hapus depthOutput + kembalikan preset ke 720p
                self.captureSession.beginConfiguration()
                self.captureSession.removeOutput(self.depthOutput)
                self.captureSession.sessionPreset = .hd1280x720
                HaispaceLogger.info("[PortraitMode] depth output dilepas, preset kembali ke hd1280x720", category: "camera")
                self.captureSession.commitConfiguration()
                
                // LANGKAH 3: Kembalikan video delegate ke normal
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                HaispaceLogger.info("[PortraitMode] videoOutput delegate dikembalikan ke normal", category: "camera")
                
                // Kembalikan ke zoom terakhir yang dipilih pengguna
                self.applyZoomInternal(factor: self.lastRequestedZoomFactor)
                HaispaceLogger.info("[PortraitMode] Depth-Based Bokeh NONAKTIF", category: "camera")
            }
        }
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
            if let depthCI = lastDepthImage,
               let processedBuffer = applyDepthBokeh(to: pixelBuffer, depthMap: depthCI) {
                // Buat CMSampleBuffer baru yang membungkus processedBuffer (aman, tidak crash)
                var newSampleBuffer: CMSampleBuffer?
                var timingInfo = CMSampleTimingInfo()
                CMSampleBufferGetSampleTimingInfo(syncedVideo.sampleBuffer, at: 0, timingInfoOut: &timingInfo)
                var formatDesc: CMFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                            imageBuffer: processedBuffer,
                                                            formatDescriptionOut: &formatDesc)
                if let formatDesc = formatDesc {
                    CMSampleBufferCreateForImageBuffer(
                        allocator: kCFAllocatorDefault,
                        imageBuffer: processedBuffer,
                        dataReady: true,
                        makeDataReadyCallback: nil,
                        refcon: nil,
                        formatDescription: formatDesc,
                        sampleTiming: &timingInfo,
                        sampleBufferOut: &newSampleBuffer
                    )
                }
                self.onVideoFrameCaptured?(newSampleBuffer ?? syncedVideo.sampleBuffer)
            } else {
                self.onVideoFrameCaptured?(syncedVideo.sampleBuffer)
            }
        } else {
            // Jika portrait mode tidak aktif, kirim buffer asli langsung
            self.onVideoFrameCaptured?(syncedVideo.sampleBuffer)
        }
    }
    
    /// Menerapkan natural depth-of-field bokeh berdasarkan peta kedalaman fisik.
    /// PENTING: Tidak melakukan in-place render ke pixelBuffer dari synchronizer
    /// (menyebabkan EXC_BAD_ACCESS crash karena buffer masih dipegang AVFoundation).
    /// Render ke pixel buffer TERPISAH lalu kirim sebagai sampleBuffer baru.
    nonisolated private func applyDepthBokeh(to pixelBuffer: CVPixelBuffer, depthMap: CIImage) -> CVPixelBuffer? {
        let original = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Step 1: Blur background
        let blurred = original
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18.0])
            .cropped(to: original.extent)
        
        // Step 2: Normalisasi depth Float32 (meter) ke mask 0.0–1.0
        // near=0.3m → 1.0 (putih=tajam), far=3.0m → 0.0 (hitam=blur)
        let nearPlane: CGFloat = 0.3
        let farPlane:  CGFloat = 3.0
        let scale = 1.0 / (farPlane - nearPlane)
        let bias  = -nearPlane * scale
        
        let normalizedDepth = depthMap.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ])
        
        let invertedDepth = normalizedDepth.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        
        let clampedMask = invertedDepth.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        
        let softMask = clampedMask
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 8.0])
            .cropped(to: original.extent)
        
        let bokehComposite = original.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: softMask
        ])
        
        // Step 3: Buat pixel buffer BARU (bukan in-place) untuk menghindari EXC_BAD_ACCESS
        // Buffer dari synchronizer masih dipegang AVFoundation — tidak bisa di-write!
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        var outputBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] // PENTING: Wajib ada agar kompatibel dengan Hardware Video Encoder!
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, attrs as CFDictionary, &outputBuffer) == kCVReturnSuccess,
              let outBuf = outputBuffer else {
            HaispaceLogger.warning("[Bokeh] Gagal buat output pixel buffer", category: "camera")
            return nil
        }
        
        ciContext.render(bokehComposite, to: outBuf)
        return outBuf
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// Fallback delegate — tidak aktif saat synchronizer digunakan
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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
