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
    
    // FIX #4: Gunakan 'let' bukan 'lazy var' untuk CIContext.
    // 'lazy var' di Swift TIDAK thread-safe — jika dua thread mengaksesnya pertama kali
    // secara bersamaan (videoQueue & syncQueue), bisa terjadi double-init atau crash.
    // 'let' diinisialisasi sekali di init() dan dijamin aman dari semua thread.
    // PENTING: Gunakan default CIContext() agar menggunakan Metal GPU renderer dengan
    // working color space standard (linear sRGB) yang kompatibel dengan CIDepthBlurEffect.
    private let ciContext = CIContext()
    
    // FIX #2: Ganti nonisolated(unsafe) dengan NSLock-protected storage.
    // lastDepthImage dibaca dari videoQueue (processVideoFrame) dan ditulis
    // dari syncQueue (depthDataOutput delegate) secara concurrent — ini adalah
    // race condition nyata yang dapat menyebabkan EXC_BAD_ACCESS di device fisik.
    // NSLock adalah solusi lightweight dan zero-overhead untuk kasus ini.
    private let depthLock = NSLock()
    private var _lastDepthImage: CIImage? = nil
    private var _isCapturingPhoto = false
    private var lastDepthImage: CIImage? {
        get {
            depthLock.lock()
            defer { depthLock.unlock() }
            return _lastDepthImage
        }
        set {
            depthLock.lock()
            defer { depthLock.unlock() }
            _lastDepthImage = newValue
        }
    }
    
    // Dedicated queues untuk penanganan frame output
    private let videoQueue = DispatchQueue(label: "id.haispaceproject.camera.videoQueue")
    private let syncQueue = DispatchQueue(label: "id.haispaceproject.camera.syncQueue", qos: .userInteractive)
    
    // Simpan target zoom yang diinginkan agar bisa dikembalikan saat beralih mode
    nonisolated(unsafe) private(set) var lastRequestedZoomFactor: CGFloat = 1.0
    
    // Pro Preset Color Filter & Aperture State
    nonisolated(unsafe) private(set) var currentColorPreset: String = "original"
    nonisolated(unsafe) private(set) var currentAperture: Double = 2.8
    
    func setColorPreset(presetId: String) {
        currentColorPreset = presetId
        HaispaceLogger.info("[Filter] Color preset diubah ke: \(presetId)", category: "camera")
    }
    
    func setAperture(fNumber: Double) {
        currentAperture = fNumber
        HaispaceLogger.info("[Aperture] Aperture diubah ke: f/\(fNumber)", category: "camera")
    }
    
    // Cache virtualDeviceSwitchOverVideoZoomFactors dari format normal (sebelum portrait mode).
    // Nilai ini BERUBAH saat portrait mode mengaktifkan format depth — yang menyebabkan
    // pemetaan 2x → internal zoom yang salah. Dengan cache dari session awal,
    // zoom mapping selalu konsisten terlepas dari apakah portrait mode ON atau OFF.
    nonisolated(unsafe) private var cachedSwitchOverFactors: [CGFloat] = []
    
    // FIX #6: Simpan titik fokus terakhir dari operator (normalized 0.0-1.0).
    // Digunakan untuk blend mask di PhotoTransferService sehingga area fokus
    // mengikuti titik yang dipilih operator, bukan selalu di tengah.
    nonisolated(unsafe) var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
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
        
        // Cache switchOver factors dari format normal SETELAH session berjalan.
        // Harus dilakukan SEBELUM portrait mode pernah aktif dan SEBELUM applyZoomInternal
        // agar nilai yang tersimpan mencerminkan mapping zoom yang benar (UW → Wide → 2x digital).
        if let input = captureSession.inputs.first as? AVCaptureDeviceInput {
            let raw = input.device.virtualDeviceSwitchOverVideoZoomFactors
            cachedSwitchOverFactors = raw.map { CGFloat($0.doubleValue) }
            HaispaceLogger.info("[Zoom] Cached switchOver factors: \(cachedSwitchOverFactors)", category: "camera")
        }
        
        // Atur default zoom awal ke 1.0x (Wide Angle Utama) secara INSTAN (tanpa ramp)
        // Ini memastikan kamera langsung terkunci di 1.0x Wide Angle sejak detik pertama diluncurkan.
        self.applyZoomInternal(factor: 1.0, animated: false)
        
        isConfigured = true
    }
    
    /// Trigger pemotretan kualitas tinggi (dipanggil saat menerima instruksi dari iPad)
    func captureHighQualityPhoto() {
        // Dijalankan di sessionQueue agar serialized — capturePhoto selalu terjadi
        // setelah setPortraitMode selesai mengubah konfigurasi session
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Tandai sedang mengambil foto untuk menunda rendering bokeh preview
            self.depthLock.lock()
            self._isCapturingPhoto = true
            self.depthLock.unlock()
            
            // Inisialisasi photo settings dengan container format yang mendukung depth data (HEVC / JPEG)
            // Default AVCapturePhotoSettings() tanpa format dapat memilih format TIFF/RAW yang tidak mendukung depth metadata, menyebabkan crash instan.
            let photoSettings: AVCapturePhotoSettings
            let availableCodecs = self.photoOutput.availablePhotoCodecTypes
            
            if availableCodecs.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc.rawValue])
            } else if availableCodecs.contains(.jpeg) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg.rawValue])
            } else {
                photoSettings = AVCapturePhotoSettings()
            }
            
            photoSettings.flashMode = .off
            
            // Aktifkan depth data hanya jika portrait mode aktif DAN output level depth delivery sudah aktif
            // ini mencegah crash akibat format mismatch jika dipanggil sebelum commit selesai sepenuhnya
            if self.isPortraitModeActive && self.photoOutput.isDepthDataDeliveryEnabled {
                photoSettings.isDepthDataDeliveryEnabled = true
                photoSettings.embedsDepthDataInPhoto = true
                
                // Aktifkan portrait effects matte delivery (prasyarat: depth delivery harus aktif)
                // Ini memastikan capture.portraitEffectsMatte tersedia di PhotoTransferService
                if self.photoOutput.isPortraitEffectsMatteDeliveryEnabled {
                    photoSettings.isPortraitEffectsMatteDeliveryEnabled = true
                    HaispaceLogger.info("Portrait effects matte delivery diaktifkan untuk jepretan", category: "camera")
                }
                HaispaceLogger.info("Depth + matte delivery aktif untuk jepretan Portrait", category: "camera")
            } else {
                photoSettings.isDepthDataDeliveryEnabled = false
                photoSettings.embedsDepthDataInPhoto = false
            }
            
            // Pilih prioritization terbaik yang didukung oleh format aktif saat ini
            // Caranya: photoSettings.photoQualityPrioritization TIDAK boleh melebihi maxPhotoQualityPrioritization milik output saat ini.
            // Maka langsung gunakan maxPhotoQualityPrioritization dari photoOutput (yang sudah disesuaikan saat toggle portrait).
            let targetPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            photoSettings.photoQualityPrioritization = targetPrioritization
            
            HaispaceLogger.info("Mengambil foto dengan prioritization: \(photoSettings.photoQualityPrioritization.rawValue)", category: "camera")
            
            // Matikan sementara koneksi depthOutput sebelum jepret untuk membebaskan 100% bandwidth hardware
            if self.isPortraitModeActive {
                for connection in self.depthOutput.connections {
                    connection.isEnabled = false
                }
                HaispaceLogger.info("[PortraitMode] Koneksi depthOutput dinonaktifkan sementara untuk membebaskan bandwidth saat capture", category: "camera")
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
            
            // FIX #6: Simpan titik fokus untuk dipakai CIDepthBlurEffect pada foto final
            lastFocusPoint = CGPoint(x: CGFloat(x), y: CGFloat(y))
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
    /// cachedSwitchOverFactors — di-cache saat session awal agar stabil saat portrait ON/OFF.
    ///
    /// ATURAN: 0.5x (Ultra Wide) TIDAK kompatibel saat portrait mode aktif.
    /// Jika portrait ON dan iPad mengirim 0.5x, di-clamp ke 1.0x secara otomatis.
    func setZoom(factor: CGFloat) {
        // Clamp 0.5x ke 1.0x saat portrait mode aktif.
        // UltraWide tidak menghasilkan depth map yang reliable di iPhone 14 DualWide.
        let effectiveFactor: CGFloat
        if isPortraitModeActive && factor < 1.0 {
            effectiveFactor = 1.0
            HaispaceLogger.info("[Zoom] 0.5x dikembalikan ke 1.0x — portrait mode aktif, UltraWide tidak kompatibel dengan depth", category: "camera")
        } else {
            effectiveFactor = factor
        }
        lastRequestedZoomFactor = effectiveFactor
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.applyZoomInternal(factor: effectiveFactor)
        }
    }
    
    /// Fungsi helper internal untuk mengubah zoom factor. Harus dipanggil dalam sessionQueue.
    private func applyZoomInternal(factor: CGFloat, animated: Bool = true) {
        guard let currentInput = self.captureSession.inputs.first as? AVCaptureDeviceInput else {
            HaispaceLogger.warning("[Zoom] Tidak ada active camera input", category: "camera")
            return
        }
        let device = currentInput.device
        
        do {
            try device.lockForConfiguration()
            
            let maxZ = min(device.maxAvailableVideoZoomFactor, 8.0)
            let minZ = device.minAvailableVideoZoomFactor
            
            let targetInternalZoom: CGFloat
            
            if isPortraitModeActive {
                // =========================================================================
                // MODE PORTRAIT (Format Kedalaman / Depth Active):
                // AVFoundation membatasi activeFormat pada kamera utama Wide Angle saja (0.5x UltraWide dikeluarkan).
                // Pada format kedalaman ini:
                //   - minZ (1.0) = Kamera Utama 1.0x (26mm Optical)
                //   - minZ * 2.0 (2.0) = Crop 2.0x Kamera Utama (52mm Digital Crop)
                // =========================================================================
                if factor <= 1.2 {
                    // 1x Portrait → Kamera Utama 1.0x (internal minZ = 1.0)
                    targetInternalZoom = minZ
                    HaispaceLogger.info("[Zoom Portrait] 1.0x → Kamera Utama 1.0x (internal: \(targetInternalZoom)x)", category: "camera")
                } else {
                    // 2x Portrait → Crop 2.0x Kamera Utama (internal minZ * 2.0 = 2.0)
                    let zoom2x = min(minZ * 2.0, maxZ)
                    targetInternalZoom = zoom2x
                    HaispaceLogger.info("[Zoom Portrait] 2.0x → Digital Crop 2x (internal: \(targetInternalZoom)x)", category: "camera")
                }
            } else {
                // =========================================================================
                // MODE NORMAL (Format Stream Standard hd1280x720):
                // Perangkat virtual dual-wide aktif (0.5x UltraWide + 1.0x Wide Angle).
                // Pada format normal ini:
                //   - factor 0.5x -> minZ = 1.0x internal (Lensa UltraWide 0.5x)
                //   - factor 1.0x -> switchOver = 2.0x internal (Kamera Utama 1.0x)
                //   - factor 2.0x -> switchOver * 2.0 = 4.0x internal (Crop 2x Kamera Utama 2.0x)
                // =========================================================================
                let liveSwitchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
                let wideSwitchOver = liveSwitchOvers.first ?? cachedSwitchOverFactors.first ?? 2.0
                
                if factor < 0.8 {
                    // 0.5x → Ultra Wide (lensa 0.5x)
                    targetInternalZoom = minZ
                    HaispaceLogger.info("[Zoom Normal] 0.5x → Ultra Wide (internal: \(targetInternalZoom)x)", category: "camera")
                } else if factor <= 1.2 {
                    // 1x → Kamera Utama Wide Angle (internal 2.0x)
                    targetInternalZoom = max(wideSwitchOver, minZ)
                    HaispaceLogger.info("[Zoom Normal] 1.0x → Kamera Utama Wide Angle (internal: \(targetInternalZoom)x)", category: "camera")
                } else {
                    // 2x → Digital Crop 2x dari Kamera Utama (internal 4.0x)
                    let zoom2x = min(wideSwitchOver * 2.0, maxZ)
                    targetInternalZoom = max(zoom2x, minZ)
                    HaispaceLogger.info("[Zoom Normal] 2.0x → Digital Crop Kamera Utama (internal: \(targetInternalZoom)x)", category: "camera")
                }
            }
            
            let finalZoom = max(min(targetInternalZoom, maxZ), minZ)
            if animated {
                device.ramp(toVideoZoomFactor: finalZoom, withRate: 8.0) // Smooth ramp
            } else {
                device.videoZoomFactor = finalZoom // Instant hardware lock
            }
            device.unlockForConfiguration()
            
        } catch {
            HaispaceLogger.error("[Zoom] Gagal set zoom: \(error.localizedDescription)", category: "camera")
        }
    }
    
    /// Mengaktifkan atau mematikan mode Portrait (Depth-Based Live Bokeh) secara dinamis.
    func setPortraitMode(enabled: Bool) {
        isPortraitModeActive = enabled
        if !enabled { lastDepthImage = nil }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let deviceInput = self.captureSession.inputs.first as? AVCaptureDeviceInput else { return }
            let videoDevice = deviceInput.device
            
            if enabled {
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .photo
                
                self.depthOutput.isFilteringEnabled = true
                if self.captureSession.canAddOutput(self.depthOutput) {
                    self.captureSession.addOutput(self.depthOutput)
                    HaispaceLogger.info("[PortraitMode] depth output ditambahkan", category: "camera")
                }
                
                self.depthOutput.setDelegate(self, callbackQueue: self.syncQueue)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                
                self.captureSession.commitConfiguration()
                HaispaceLogger.info("[PortraitMode] session committed — preset:.photo + depthOutput aktif", category: "camera")
                
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                    
                    if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                        self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                        HaispaceLogger.info("[PortraitMode] Portrait effects matte delivery: ENABLED", category: "camera")
                    }
                }
                
                self.photoOutput.maxPhotoQualityPrioritization = .balanced
                
                // Jika sebelumnya di 0.5x, paksa naik ke 1.0x karena UltraWide tidak kompatibel dengan depth.
                // Jika 1.0x atau 2.0x, pertahankan pilihan user!
                let targetZoom = self.lastRequestedZoomFactor < 1.0 ? 1.0 : self.lastRequestedZoomFactor
                self.applyZoomInternal(factor: targetZoom, animated: false)
                HaispaceLogger.info("[PortraitMode] Zoom dikunci di \(targetZoom)x", category: "camera")
                
            } else {
                self.depthOutput.setDelegate(nil, callbackQueue: nil)
                
                self.captureSession.beginConfiguration()
                self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = false
                self.photoOutput.isDepthDataDeliveryEnabled = false
                
                self.captureSession.removeOutput(self.depthOutput)
                self.captureSession.sessionPreset = .hd1280x720
                self.captureSession.commitConfiguration()
                HaispaceLogger.info("[PortraitMode] dinonaktifkan, preset kembali ke hd1280x720", category: "camera")
                
                if videoDevice.activeFormat.isHighPhotoQualitySupported {
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                } else {
                    self.photoOutput.maxPhotoQualityPrioritization = .balanced
                }
                
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                
                // WAJIB: Kunci kembali zoom setelah sessionPreset dikembalikan ke hd1280x720!
                self.applyZoomInternal(factor: self.lastRequestedZoomFactor, animated: false)
                HaispaceLogger.info("[PortraitMode OFF] Zoom dikembalikan ke \(self.lastRequestedZoomFactor)x", category: "camera")
            }
        }
    }
}

// MARK: - AVCaptureDepthDataOutputDelegate
extension CameraCaptureService: AVCaptureDepthDataOutputDelegate {
    @objc nonisolated func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        let depthFloat32 = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        self.lastDepthImage = CIImage(cvPixelBuffer: depthFloat32.depthDataMap)
    }
}

extension CameraCaptureService {
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // PENTING: Bungkus dengan autoreleasepool karena method ini terpanggil 24-30 kali per detik.
        // Tanpa autoreleasepool, objek temporal Core Image (CIImage, CGAffineTransform)
        // akan menumpuk di memori heap background thread sebelum sempat dideallokasi oleh ARC,
        // mengakibatkan slow memory leak (OOM) setelah beberapa menit live preview.
        autoreleasepool {
            // Periksa apakah sedang mengambil foto
            self.depthLock.lock()
            let isCapturing = self._isCapturingPhoto
            self.depthLock.unlock()
            
            // Jika portrait mode aktif DAN tidak sedang memotret, proses bokeh.
            // Menangguhkan bokeh preview selama memotret membebaskan 100% kapasitas GPU/Metal
            // untuk memproses file 12MP high-res, mencegah crash tabrakan resource GPU.
            if self.isPortraitModeActive && !isCapturing, let depthCI = lastDepthImage {
                // Terapkan depth bokeh menggunakan depth map terakhir (di-scale ke resolusi video)
                let videoCI = CIImage(cvPixelBuffer: pixelBuffer)
                let scaleX = videoCI.extent.width / depthCI.extent.width
                let scaleY = videoCI.extent.height / depthCI.extent.height
                let scaledDepthCI = depthCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                if let processedBuffer = applyDepthBokeh(to: pixelBuffer, depthMap: scaledDepthCI) {
                    // Buat CMSampleBuffer baru yang membungkus processedBuffer
                    var newSampleBuffer: CMSampleBuffer?
                    var timingInfo = CMSampleTimingInfo()
                    CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
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
                    self.onVideoFrameCaptured?(newSampleBuffer ?? sampleBuffer)
                } else {
                    self.onVideoFrameCaptured?(sampleBuffer)
                }
            } else if self.currentColorPreset != "original" && !isCapturing {
                // Terapkan Pro Studio Color Filter pada mode normal
                let videoCI = CIImage(cvPixelBuffer: pixelBuffer)
                let filteredCI = self.applyColorFilter(to: videoCI, presetId: self.currentColorPreset)
                
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
                
                var outputBuffer: CVPixelBuffer?
                let attrs: [String: Any] = [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                if CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, attrs as CFDictionary, &outputBuffer) == kCVReturnSuccess,
                   let outBuf = outputBuffer {
                    self.ciContext.render(filteredCI, to: outBuf)
                    
                    var newSampleBuffer: CMSampleBuffer?
                    var timingInfo = CMSampleTimingInfo()
                    CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
                    var formatDesc: CMFormatDescription?
                    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: outBuf, formatDescriptionOut: &formatDesc)
                    if let formatDesc = formatDesc {
                        CMSampleBufferCreateForImageBuffer(
                            allocator: kCFAllocatorDefault,
                            imageBuffer: outBuf,
                            dataReady: true,
                            makeDataReadyCallback: nil,
                            refcon: nil,
                            formatDescription: formatDesc,
                            sampleTiming: &timingInfo,
                            sampleBufferOut: &newSampleBuffer
                        )
                    }
                    self.onVideoFrameCaptured?(newSampleBuffer ?? sampleBuffer)
                } else {
                    self.onVideoFrameCaptured?(sampleBuffer)
                }
            } else {
                // Jika portrait mode & filter tidak aktif, kirim buffer asli langsung
                self.onVideoFrameCaptured?(sampleBuffer)
            }
        }
    }
    
    /// Menerapkan natural depth-of-field bokeh berdasarkan peta kedalaman fisik.
    /// PENTING: Tidak melakukan in-place render ke pixelBuffer dari synchronizer
    /// (menyebabkan EXC_BAD_ACCESS crash karena buffer masih dipegang AVFoundation).
    /// Render ke pixel buffer TERPISAH lalu kirim sebagai sampleBuffer baru.
    nonisolated private func applyDepthBokeh(to pixelBuffer: CVPixelBuffer, depthMap: CIImage) -> CVPixelBuffer? {
        var original = CIImage(cvPixelBuffer: pixelBuffer)
        var depth = depthMap
        
        // PENTING: Jika Portrait mode di-set ke 2x (lastRequestedZoomFactor >= 1.8),
        // lakukan 2x center crop pada buffer preview & depth map karena AVFoundation
        // mengunci hardware videoZoomFactor di format depth DualWide.
        if lastRequestedZoomFactor >= 1.8 {
            let origW = original.extent.width
            let origH = original.extent.height
            let cropRect = CGRect(x: origW * 0.25, y: origH * 0.25, width: origW * 0.5, height: origH * 0.5)
            
            original = original.cropped(to: cropRect)
                .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
                .transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
            
            let depthW = depth.extent.width
            let depthH = depth.extent.height
            let depthCropRect = CGRect(x: depthW * 0.25, y: depthH * 0.25, width: depthW * 0.5, height: depthH * 0.5)
            
            depth = depth.cropped(to: depthCropRect)
                .transformed(by: CGAffineTransform(translationX: -depthCropRect.minX, y: -depthCropRect.minY))
                .transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
        }
        
        // Step 1: Blur background menggunakan CIDiscBlur sesuai fNumber aperture (f/1.4 - f/8.0).
        let blurRadius: Double
        if currentAperture < 1.8 {
            blurRadius = 24.0 // f/1.4 Ultra Heavy Bokeh
        } else if currentAperture < 3.5 {
            blurRadius = 14.0 // f/2.8 Balanced Default Bokeh
        } else if currentAperture < 6.5 {
            blurRadius = 6.0  // f/5.6 Gentle Blur
        } else {
            blurRadius = 0.0  // f/8.0 Sharp Background
        }
        
        let blurred: CIImage
        if blurRadius > 0 {
            blurred = original
                .clampedToExtent()
                .applyingFilter("CIDiscBlur", parameters: ["inputRadius": blurRadius])
                .cropped(to: original.extent)
        } else {
            blurred = original
        }
        
        // Step 2: Normalisasi depth Float32 (meter) ke mask 0.0–1.0
        let nearPlane: CGFloat = 0.5
        let farPlane:  CGFloat = 4.0
        let scale = 1.0 / (farPlane - nearPlane)
        let bias  = -nearPlane * scale
        
        let normalizedDepth = depth.applyingFilter("CIColorMatrix", parameters: [
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
        
        // Terapkan Pro Studio Color Filter pada frame hasil komposit
        let finalImage = applyColorFilter(to: bokehComposite, presetId: currentColorPreset)
        
        // Step 3: Buat pixel buffer BARU (bukan in-place) untuk menghindari EXC_BAD_ACCESS
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        var outputBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, attrs as CFDictionary, &outputBuffer) == kCVReturnSuccess,
              let outBuf = outputBuffer else {
            HaispaceLogger.warning("[Bokeh] Gagal buat output pixel buffer", category: "camera")
            return nil
        }
        
        ciContext.render(finalImage, to: outBuf)
        return outBuf
    }
    
    /// Helper internal untuk menerapkan Pro Studio Color Preset Filter.
    nonisolated func applyColorFilter(to image: CIImage, presetId: String) -> CIImage {
        switch presetId {
        case "warm":
            // Warm Studio (Kodak Portra Style)
            let controls = image.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 1.05,
                "inputContrast": 1.03
            ])
            return controls.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6800, y: 0),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        case "clean":
            // Clean Portrait (Vogue Editorial Style)
            return image.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 1.08,
                "inputBrightness": 0.02,
                "inputContrast": 1.05
            ])
        case "vintage":
            // Vintage Film (Retro Pastel Style)
            let controls = image.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 0.88,
                "inputContrast": 0.95
            ])
            return controls.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.95, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.95, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.95, w: 0),
                "inputBiasVector": CIVector(x: 0.05, y: 0.04, z: 0.03, w: 0)
            ])
        case "bw_noir":
            // Noir B&W (Leica Monochrome Style)
            return image.applyingFilter("CIPhotoEffectNoir")
        default:
            // Original (Tanpa Filter)
            return image
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// Menerima frame video secara berkala
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        self.processVideoFrame(sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            HaispaceLogger.error("Gagal capture foto: \(error.localizedDescription)", category: "camera")
        } else {
            self.onPhotoCaptured?(photo)
        }
        
        // Aktifkan kembali koneksi depthOutput dan matikan flag capture
        self.sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.depthLock.lock()
            self._isCapturingPhoto = false
            self.depthLock.unlock()
            
            if self.isPortraitModeActive {
                for connection in self.depthOutput.connections {
                    connection.isEnabled = true
                }
                HaispaceLogger.info("[PortraitMode] Koneksi depthOutput diaktifkan kembali setelah capture selesai", category: "camera")
            }
        }
    }
}
