// PhotoTransferService.swift
// HaispaceCamera — Services/Camera
//
// Mengelola antrian transfer AIC (Adaptive Image Compression)
// dengan Dual-Channel transfer (Thumbnail cepat + Full Quality lambat).
//
// Ref: docs/design/40_concurrency_strategy.md

import Foundation
import AVFoundation
import UIKit
import ImageIO
import CoreImage
import Vision

actor PhotoTransferService {
    static let shared = PhotoTransferService()
    
    private struct PendingTransfer {
        let photoId: String
        let photoData: Data
        let sortOrder: Int
    }
    
    private var fullQualityQueue: [PendingTransfer] = []
    private var isProcessingQueue = false
    
    // REUSE CICONTEXT: CIContext adalah objek yang sangat berat karena menginisialisasi
    // pipeline Metal, shader compilation, dan command queue GPU.
    // Default initializer CIContext() otomatis menggunakan Metal GPU di iOS secara optimal.
    private let ciContext = CIContext()
    
    private init() {}
    
    /// Dipanggil setiap kali iPhone selesai mengambil foto resolusi tinggi.
    ///
    /// Jika portrait mode aktif, efek bokeh diterapkan menggunakan AVPortraitEffectsMatte —
    /// segmentation mask pixel-perfect dari Neural Engine iPhone (public API Apple, stable, memory-safe).
    /// Tidak menggunakan CIDepthBlurEffect (undocumented internal API, OOM risk 400-800MB).
    ///
    /// Pipeline memori: ~180MB peak (aman di iPhone 14 dengan 6GB RAM).
    func handleNewCapture(photoId: String, capture: AVCapturePhoto, sortOrder: Int, isPortraitActive: Bool, requestedZoom: CGFloat = 1.0) async {
        var photoData: Data? = capture.fileDataRepresentation()
        
        if isPortraitActive, let rawData = photoData {
            
            let bokehResult: Data? = autoreleasepool { () -> Data? in
                
                // Cek ketersediaan Portrait Effects Matte (Neural Engine segmentation mask).
                // Nil jika isPortraitEffectsMatteDeliveryEnabled belum di-set atau device tidak support.
                // Jika nil: tetap terapkan Smart Grading tanpa bokeh (tidak crash, masih berguna).
                guard let matte = capture.portraitEffectsMatte else {
                    HaispaceLogger.info("Portrait effects matte tidak tersedia — Smart Grading tanpa bokeh diterapkan", category: "camera")
                    
                    // Terapkan Smart Grading saja (tanpa segmentation mask / bokeh)
                    let presetId = CameraCaptureService.shared.currentColorPreset
                    // Selalu jalankan grading untuk Portrait Mode
                    
                    let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
                    guard var flatPhoto = CIImage(data: rawData, options: ciImageOptions) else { return nil }
                    let rawExtF = flatPhoto.extent
                    if rawExtF.origin != .zero {
                        flatPhoto = flatPhoto.transformed(by: CGAffineTransform(translationX: -rawExtF.minX, y: -rawExtF.minY))
                    }
                    let photoExtF = flatPhoto.extent
                    
                    // Layer 2-like: warm lift langsung ke seluruh foto
                    let warmed = flatPhoto.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 1.01, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0.97, w: 0),
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ])
                    
                    // Vignette sinematik ringan
                    let vignetted = warmed.clampedToExtent()
                        .applyingFilter("CIVignette", parameters: ["inputRadius": 1.6, "inputIntensity": 0.45])
                        .cropped(to: photoExtF)
                    
                    let finalPhoto = CameraCaptureService.shared.applyColorFilter(to: vignetted, presetId: presetId)
                    
                    guard let cgF = self.ciContext.createCGImage(finalPhoto, from: photoExtF),
                          let jpegF = UIImage(cgImage: cgF).jpegData(compressionQuality: 0.92) else { return nil }
                    HaispaceLogger.info("[SmartGrading] No-Bokeh mode: grading+grain applied (Preset: \(presetId))", category: "camera")
                    return jpegF
                }
                
                // Load foto dengan EXIF orientation sebagai affine transform (zero-copy, memory efficient)
                let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
                guard var orientedPhoto = CIImage(data: rawData, options: ciImageOptions) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal membuat CIImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                // Normalkan origin ke (0,0) — oriented() dapat menggeser origin ke nilai negatif
                let rawExtent = orientedPhoto.extent
                if rawExtent.origin != .zero {
                    orientedPhoto = orientedPhoto.transformed(
                        by: CGAffineTransform(translationX: -rawExtent.minX, y: -rawExtent.minY)
                    )
                }
                let exifOrientation = capture.metadata[kCGImagePropertyOrientation as String] as? Int32 ?? 1
                
                // --- MATTE PROCESSING ---
                // Format: kCVPixelFormatType_OneComponent8 (grayscale 8-bit)
                //   255 = orang/foreground → foto tetap tajam
                //     0 = background      → foto di-blur
                let mattePixelBuffer = matte.mattingImage
                var matteCIImage = CIImage(cvPixelBuffer: mattePixelBuffer)
                    .oriented(forExifOrientation: exifOrientation)
                
                let matteRawExtent = matteCIImage.extent
                if matteRawExtent.origin != .zero {
                    matteCIImage = matteCIImage.transformed(
                        by: CGAffineTransform(translationX: -matteRawExtent.minX, y: -matteRawExtent.minY)
                    )
                }
                
                // PENTING: Jika Portrait mode di-set ke 2x (requestedZoom >= 1.8),
                // lakukan 2x center crop pada foto & matte mask agar hasil akhir foto 2x Portrait presisi!
                if requestedZoom >= 1.8 {
                    let pW = orientedPhoto.extent.width
                    let pH = orientedPhoto.extent.height
                    let cropRect = CGRect(x: pW * 0.25, y: pH * 0.25, width: pW * 0.5, height: pH * 0.5)
                    orientedPhoto = orientedPhoto.cropped(to: cropRect)
                        .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
                        .transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
                    
                    let mW = matteCIImage.extent.width
                    let mH = matteCIImage.extent.height
                    let mCropRect = CGRect(x: mW * 0.25, y: mH * 0.25, width: mW * 0.5, height: mH * 0.5)
                    matteCIImage = matteCIImage.cropped(to: mCropRect)
                        .transformed(by: CGAffineTransform(translationX: -mCropRect.minX, y: -mCropRect.minY))
                        .transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
                }
                
                let photoExtent = orientedPhoto.extent
                
                // Scale matte ke dimensi foto (matte selalu resolusi lebih rendah dari foto)
                let scaleX = photoExtent.width / matteCIImage.extent.width
                let scaleY = photoExtent.height / matteCIImage.extent.height
                let scaledMatte = matteCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                // Haluskan tepi matte — radius 1.5 cukup untuk anti-aliasing tanpa merusak detail rambut
                let softMatte = scaledMatte
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.5])
                    .cropped(to: photoExtent)
                
                // --- FIX #5: HIGHLIGHT BLOOM ---
                // --- BOKEH GENERATION (Edge-Preserving Variable Blur) ---
                let currentAperture = CameraCaptureService.shared.currentAperture
                let blurRadius: Double = currentAperture < 1.8 ? 24.0 : (currentAperture < 3.5 ? 16.0 : (currentAperture < 6.5 ? 8.0 : 0.0))
                
                let composite: CIImage
                if blurRadius > 0 {
                    // Invert matte: Putih (1.0) = Background (Blur), Hitam (0.0) = Subject (Sharp)
                    let invertedMatte = softMatte.applyingFilter("CIColorInvert")
                    var finalMask = invertedMatte
                    
                    // Jika ada depth map, kombinasikan dengan invertedMatte agar blur bergradasi sesuai jarak
                    if let depthData = capture.depthData {
                        let depthFloat32 = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                        var depthCI = CIImage(cvPixelBuffer: depthFloat32.depthDataMap).oriented(forExifOrientation: exifOrientation)
                        
                        if depthCI.extent.origin != .zero {
                            depthCI = depthCI.transformed(by: CGAffineTransform(translationX: -depthCI.extent.minX, y: -depthCI.extent.minY))
                        }
                        let dScaleX = photoExtent.width / depthCI.extent.width
                        let dScaleY = photoExtent.height / depthCI.extent.height
                        let scaledDepth = depthCI.transformed(by: CGAffineTransform(scaleX: dScaleX, y: dScaleY))
                        
                        let nearPlane: CGFloat = 0.5
                        let farPlane:  CGFloat = 3.5
                        let dScale = 1.0 / (farPlane - nearPlane)
                        let dBias  = -nearPlane * dScale
                        
                        let smoothDepth = scaledDepth.applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector": CIVector(x: dScale, y: 0, z: 0, w: 0),
                            "inputGVector": CIVector(x: 0, y: dScale, z: 0, w: 0),
                            "inputBVector": CIVector(x: 0, y: 0, z: dScale, w: 0),
                            "inputBiasVector": CIVector(x: dBias, y: dBias, z: dBias, w: 0)
                        ]).applyingFilter("CIColorClamp", parameters: [
                            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                        ]).applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 4.0]).cropped(to: photoExtent)
                        
                        // Multiply invertedMatte dengan smoothDepth:
                        // Subject (0.0) * Depth (x) = 0.0 (Selalu Sharp)
                        // Background (1.0) * Depth (x) = x (Blur bertahap)
                        finalMask = invertedMatte.applyingFilter("CIMultiplyCompositing", parameters: [
                            kCIInputBackgroundImageKey: smoothDepth
                        ])
                        HaispaceLogger.info("[PortraitMatte] Variable Depth Blur mask AKTIF", category: "camera")
                    }
                    
                    // CIMaskedVariableBlur: Filter native Apple yang secara khusus menangani edge-bleed!
                    // Mencegah wajah yang sharp bocor ke background blur (menghilangkan halo/wajah blur).
                    composite = orientedPhoto.applyingFilter("CIMaskedVariableBlur", parameters: [
                        "inputMask": finalMask,
                        "inputRadius": blurRadius
                    ])
                } else {
                    composite = orientedPhoto
                }
                
                // --- HAISPACE CINEMATIC SMART GRADING (Portrait Mode Only) ---
                // Menggunakan softMatte yang sudah tersedia (zero-cost reuse) untuk membedakan
                // grading antara subject (orang) dan background secara per-pixel.
                let presetId = CameraCaptureService.shared.currentColorPreset
                let finalPhoto: CIImage
                
                // Selalu aktifkan smart grading saat Portrait Mode (walau preset original)
                do {
                    
                    // ── LAYER 1: Background Cinematic Grade ──
                    // Cool tone shift pada background: R--, B++ → cinematic background
                    let coolBackground = composite.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0.88, y: 0, z: 0, w: 0),   // sedikit kurangi Red
                        "inputGVector": CIVector(x: 0, y: 0.93, z: 0, w: 0),   // sedikit kurangi Green
                        "inputBVector": CIVector(x: 0, y: 0, z: 1.06, w: 0),   // sedikit tambah Blue
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ])
                    
                    // Desaturasi ringan pada background → tidak bersaing dengan subject
                    let desatBackground = coolBackground.applyingFilter("CIColorControls", parameters: [
                        "inputSaturation": 0.72,  // 28% desaturasi
                        "inputBrightness": -0.015, // slight darken
                        "inputContrast":   1.04
                    ])
                    
                    // Vignette ringan pada seluruh foto (bingkai sinematik)
                    let vignetted = desatBackground
                        .clampedToExtent()
                        .applyingFilter("CIVignette", parameters: [
                            "inputRadius":    1.8,
                            "inputIntensity": 0.55
                        ])
                        .cropped(to: photoExtent)
                    
                    // Blend: background → graded, subject → original composite
                    let gradedBackground = composite.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: vignetted,
                        kCIInputMaskImageKey: softMatte      // subject area dipertahankan
                    ])
                    
                    // ── LAYER 2: Subject Skin Enhancement ──
                    // Warm lift pada subject: skin lebih flatter
                    let enhancedSubject = composite.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0),   // sedikit tambah Red (warm)
                        "inputGVector": CIVector(x: 0, y: 1.01, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: 0.97, w: 0),   // sedikit kurangi Blue
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ])
                    
                    // Blend graded background dengan enhanced subject menggunakan softMatte
                    let subjectEnhanced = gradedBackground.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: gradedBackground,
                        kCIInputImageKey: enhancedSubject,
                        kCIInputMaskImageKey: softMatte
                    ])
                    
                    // ── GLOBAL PRESET TONE (Haispace Signature) ──
                    // Terapkan tone preset pilihan user sebagai finishing layer
                    finalPhoto = CameraCaptureService.shared.applyColorFilter(to: subjectEnhanced, presetId: presetId)
                    
                    HaispaceLogger.info("[SmartGrading] Haispace Cinematic Grading AKTIF (Preset: \(presetId))", category: "camera")
                }
                
                guard let cgImage = self.ciContext.createCGImage(finalPhoto, from: photoExtent) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal render CGImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                let uiImage = UIImage(cgImage: cgImage)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.92) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal encode JPEG — foto asli digunakan", category: "camera")
                    return nil
                }
                
                HaispaceLogger.info(
                    "Portrait Bokeh ✓ (Preset: \(presetId), f/\(currentAperture)): \(jpegData.count / 1024)KB (\(Int(photoExtent.width))×\(Int(photoExtent.height))px)",
                    category: "camera"
                )
                return jpegData
            } // ← autoreleasepool
            
            if let result = bokehResult {
                photoData = result
            }
        } else if !isPortraitActive, let rawData = photoData, CameraCaptureService.shared.currentColorPreset != "original" {
            // Mode normal tetapi menggunakan Pro Studio Color Preset Filter
            let presetId = CameraCaptureService.shared.currentColorPreset
            let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
            if var orientedPhoto = CIImage(data: rawData, options: ciImageOptions) {
                let rawExtent = orientedPhoto.extent
                if rawExtent.origin != .zero {
                    orientedPhoto = orientedPhoto.transformed(
                        by: CGAffineTransform(translationX: -rawExtent.minX, y: -rawExtent.minY)
                    )
                }
                let filteredPhoto = CameraCaptureService.shared.applyColorFilter(to: orientedPhoto, presetId: presetId)
                if let cgImage = self.ciContext.createCGImage(filteredPhoto, from: filteredPhoto.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    if let jpegData = uiImage.jpegData(compressionQuality: 0.92) {
                        photoData = jpegData
                        HaispaceLogger.info("Normal Photo Color Filter ✓ (Preset: \(presetId)): \(jpegData.count / 1024)KB", category: "camera")
                    }
                }
            }
        }
        
        guard let data = photoData else {
            HaispaceLogger.error("Gagal mendapatkan data gambar dari jepretan", category: "camera")
            return
        }
        
        HaispaceLogger.info("Mulai dual-channel transfer untuk \(photoId) (order: \(sortOrder))", category: "p2p")
        
        async let thumbnailTask: Void = sendThumbnailImmediately(photoId: photoId, data: data)
        async let queueTask: Void = enqueueFullQuality(photoId: photoId, data: data, sortOrder: sortOrder)
        
        _ = await (thumbnailTask, queueTask)
    }
    
    // CHANNEL 1: Fast Preview Stream (< 100ms)
    private func sendThumbnailImmediately(photoId: String, data: Data) async {
        // Kompres ke ~300KB
        let thumbnailData = await compressImage(data: data, quality: 0.6, maxBytes: 300_000)
        
        let message = P2PMessage.photoPreview(id: photoId, thumbnailData: thumbnailData)
        
        do {
            let encodedMessage = try message.encode()
            try await P2PClientService.shared.sendData(encodedMessage)
            HaispaceLogger.info("Thumbnail terkirim: \(photoId) (\(thumbnailData.count) bytes)", category: "p2p")
        } catch {
            HaispaceLogger.error("Gagal mengirim thumbnail \(photoId): \(error)", category: "p2p")
        }
    }
    
    // CHANNEL 2: Background Full Quality Queue
    private func enqueueFullQuality(photoId: String, data: Data, sortOrder: Int) async {
        let pending = PendingTransfer(photoId: photoId, photoData: data, sortOrder: sortOrder)
        fullQualityQueue.append(pending)
        
        if !isProcessingQueue {
            await processFullQualityQueue()
        }
    }
    
    /// Memulai kembali antrean pengiriman foto yang tertunda
    func resumeTransferQueue() async {
        guard !isProcessingQueue else { return }
        await processFullQualityQueue()
    }
    
    private func processFullQualityQueue() async {
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        while !fullQualityQueue.isEmpty {
            // Cek status koneksi. Jika terputus, jeda pemrosesan antrean.
            let isConnected = await P2PClientService.shared.isConnected()
            guard isConnected else {
                HaispaceLogger.warning("Menunda pengiriman full quality - P2P terputus", category: "p2p")
                break
            }
            
            let nextTransfer = fullQualityQueue.removeFirst()
            
            // Kirim metadata terlebih dahulu
            let metadataMsg = P2PMessage.photoMetadata(
                photoId: nextTransfer.photoId,
                fileSize: nextTransfer.photoData.count,
                capturedAt: Date(),
                sortOrder: nextTransfer.sortOrder
            )
            
            do {
                try await P2PClientService.shared.sendData(metadataMsg.encode())
                
                // Beri jeda kecil agar iPad siap
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                // Kirim data penuh secara aman (TCP/MPC dual-mode send)
                try await P2PClientService.shared.sendPhotoFull(id: nextTransfer.photoId, data: nextTransfer.photoData)
                
                HaispaceLogger.info("Full quality terkirim: \(nextTransfer.photoId)", category: "p2p")
            } catch {
                HaispaceLogger.error("Gagal mengirim full quality \(nextTransfer.photoId): \(error)", category: "p2p")
                
                // Re-enqueue jika gagal (bisa diberi limit retry di masa depan)
                fullQualityQueue.insert(nextTransfer, at: 0)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // tunggu 1 detik sebelum retry
            }
        }
    }
    
    private func compressImage(data: Data, quality: CGFloat, maxBytes: Int) async -> Data {
        // Implementasi optimasi memori menggunakan ImageIO
        return await Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                return data
            }
            
            // Definisikan opsi pembuatan thumbnail
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
            ]
            
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                return data
            }
            
            let resultData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(resultData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
                return data
            }
            
            let compressionOptions: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            
            CGImageDestinationAddImage(destination, thumbnail, compressionOptions as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                return data
            }
            
            return resultData as Data
        }.value
    }
}
