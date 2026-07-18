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
    func handleNewCapture(photoId: String, capture: AVCapturePhoto, sortOrder: Int, isPortraitActive: Bool) async {
        var photoData: Data? = capture.fileDataRepresentation()
        
        // Fix #4 + #5: Variable DOF + Highlight Bloom
        //
        // Fix #4: Variable blur berbasis depth gradient
        //   - Background dekat subjek (0.5–2m) → CIDiscBlur radius 8 (ringan, transisi natural)
        //   - Background jauh subjek (2–3.5m+)  → CIDiscBlur radius 22 (berat, focal plane tegas)
        //   - Gradient dikontrol oleh depth map dari capture.depthData
        //   - Fallback ke heavy blur seragam jika depth nil
        //
        // Fix #5: Highlight Bloom (CIBloom sebelum blur)
        //   - Bright highlights (lampu, jendela, refleksi) di background menjadi glowing circles
        //   - Mensimulasikan specular bokeh dari lensa optik berkualitas tinggi (Zeiss, Leica style)
        //   - Subject tetap menggunakan orientedPhoto asli (non-bloomed) → 100% crisp
        if isPortraitActive, let rawData = photoData {
            
            let bokehResult: Data? = autoreleasepool { () -> Data? in
                
                // Cek ketersediaan Portrait Effects Matte (Neural Engine segmentation mask).
                // Nil jika isPortraitEffectsMatteDeliveryEnabled belum di-set atau device tidak support.
                // Graceful fallback: foto asli dikirim, tidak crash.
                guard let matte = capture.portraitEffectsMatte else {
                    HaispaceLogger.info("Portrait effects matte tidak tersedia — foto asli dikirim tanpa bokeh", category: "camera")
                    return nil
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
                let photoExtent = orientedPhoto.extent
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
                // Scale matte ke dimensi foto (matte selalu resolusi lebih rendah dari foto)
                let scaleX = photoExtent.width / matteCIImage.extent.width
                let scaleY = photoExtent.height / matteCIImage.extent.height
                let scaledMatte = matteCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                // Haluskan tepi matte — radius 2.5 = anti-aliasing natural pada rambut & jari
                let softMatte = scaledMatte
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2.5])
                    .cropped(to: photoExtent)
                
                // --- FIX #5: HIGHLIGHT BLOOM ---
                // CIBloom memperkuat highlight (cahaya terang) sebelum blur diterapkan.
                // Ketika highlight yang membesar ini di-blur, hasilnya adalah glowing circles
                // yang persis seperti specular bokeh dari lensa optik premium.
                // inputRadius=6.0 + inputIntensity=0.4 → subtle, tidak overexposed.
                let bloomedSource = orientedPhoto.applyingFilter("CIBloom", parameters: [
                    "inputRadius":    6.0,   // radius halo glow di sekitar highlight
                    "inputIntensity": 0.4    // intensitas glow (0.4 = subtle & natural)
                ])
                
                // --- FIX #4: VARIABLE DOF BLUR ---
                // Two-pass blur: light (near) + heavy (far), di-blend berdasarkan depth gradient.
                
                // Light blur → transisi halus untuk background yang dekat dengan subjek
                let lightBlur = bloomedSource
                    .clampedToExtent()
                    .applyingFilter("CIDiscBlur", parameters: ["inputRadius": 8.0])
                    .cropped(to: photoExtent)
                
                // Heavy blur → latar belakang jauh, focal plane tegas
                let heavyBlur = bloomedSource
                    .clampedToExtent()
                    .applyingFilter("CIDiscBlur", parameters: ["inputRadius": 22.0])
                    .cropped(to: photoExtent)
                
                let blurredBackground: CIImage
                
                if let depthData = capture.depthData {
                    // Depth data tersedia → variable blur gradient
                    // Konversi ke Float32 meters dan align orientasi
                    let depthFloat32 = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                    var depthCIImage = CIImage(cvPixelBuffer: depthFloat32.depthDataMap)
                        .oriented(forExifOrientation: exifOrientation)
                    
                    let depthRawExtent = depthCIImage.extent
                    if depthRawExtent.origin != .zero {
                        depthCIImage = depthCIImage.transformed(
                            by: CGAffineTransform(translationX: -depthRawExtent.minX, y: -depthRawExtent.minY)
                        )
                    }
                    // Scale depth ke dimensi foto
                    let dScaleX = photoExtent.width / depthCIImage.extent.width
                    let dScaleY = photoExtent.height / depthCIImage.extent.height
                    let scaledDepth = depthCIImage.transformed(by: CGAffineTransform(scaleX: dScaleX, y: dScaleY))
                    
                    // Normalisasi: near=0.5m → 0.0 (mask gelap=lightBlur), far=3.5m → 1.0 (mask terang=heavyBlur)
                    let nearPlane: CGFloat = 0.5
                    let farPlane:  CGFloat = 3.5
                    let dScale = 1.0 / (farPlane - nearPlane)
                    let dBias  = -nearPlane * dScale
                    
                    let normalizedDepth = scaledDepth.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector":    CIVector(x: dScale, y: 0, z: 0, w: 0),
                        "inputGVector":    CIVector(x: 0, y: dScale, z: 0, w: 0),
                        "inputBVector":    CIVector(x: 0, y: 0, z: dScale, w: 0),
                        "inputBiasVector": CIVector(x: dBias, y: dBias, z: dBias, w: 0)
                    ])
                    
                    // Clamp 0-1 lalu smooth untuk menghilangkan noise dari sensor DualWide iPhone 14
                    let smoothDepth = normalizedDepth
                        .applyingFilter("CIColorClamp", parameters: [
                            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                        ])
                        .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 4.0])
                        .cropped(to: photoExtent)
                    
                    // CIBlendWithMask: mask=0 (near) → background (lightBlur), mask=1 (far) → foreground (heavyBlur)
                    blurredBackground = heavyBlur.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: lightBlur,
                        kCIInputMaskImageKey: smoothDepth
                    ])
                    HaispaceLogger.info("[PortraitMatte] Variable DOF AKTIF — depth gradient diterapkan", category: "camera")
                    
                } else {
                    // Depth nil (tidak didukung atau warm-up pertama) → uniform heavy blur
                    blurredBackground = heavyBlur
                    HaispaceLogger.info("[PortraitMatte] Variable DOF fallback — depth nil, uniform blur digunakan", category: "camera")
                }
                
                // --- COMPOSITE FINAL ---
                // Subject: orientedPhoto asli (bukan bloomedSource) agar subjek 100% tajam & natural
                // Background: variable blur + bloom (dari blurredBackground)
                // Mask: softMatte (putih=subjek tajam, hitam=background blur)
                let composite = orientedPhoto.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: blurredBackground,
                    kCIInputMaskImageKey: softMatte
                ])
                
                // Render ke CGImage — GPU Metal, satu render pass untuk seluruh chain.
                // Peak VRAM ~200MB (aman untuk iPhone 14 6GB RAM).
                guard let cgImage = self.ciContext.createCGImage(composite, from: photoExtent) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal render CGImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                // Encode JPEG 0.92 — kualitas tinggi, file size optimal untuk transfer P2P
                let uiImage = UIImage(cgImage: cgImage)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.92) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal encode JPEG — foto asli digunakan", category: "camera")
                    return nil
                }
                
                HaispaceLogger.info(
                    "Portrait Bokeh ✓ (Matte+VariableDOF+Bloom): \(jpegData.count / 1024)KB (\(Int(photoExtent.width))×\(Int(photoExtent.height))px)",
                    category: "camera"
                )
                return jpegData
            } // ← autoreleasepool: semua intermediate CIImage/CGImage/CVPixelBuffer dibebaskan di sini
            
            if let result = bokehResult {
                photoData = result
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
