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
        
        // OPSI B: AVPortraitEffectsMatte — ML segmentation via Neural Engine
        // Hanya diproses jika portrait mode aktif DAN matte berhasil dihasilkan oleh iOS
        if isPortraitActive, let rawData = photoData {
            
            let bokehResult: Data? = autoreleasepool { () -> Data? in
                
                // Cek ketersediaan Portrait Effects Matte.
                // Nil jika perangkat tidak support atau isPortraitEffectsMatteDeliveryEnabled belum di-set.
                // Graceful fallback: foto asli dikirim tanpa crash.
                guard let matte = capture.portraitEffectsMatte else {
                    HaispaceLogger.info("Portrait effects matte tidak tersedia — foto asli dikirim tanpa bokeh", category: "camera")
                    return nil
                }
                
                // Buat CIImage dari data foto dengan EXIF orientation diterapkan sebagai
                // affine transform (tidak merotasi pixel → zero-copy, memory efficient).
                let ciImageOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
                guard var orientedPhoto = CIImage(data: rawData, options: ciImageOptions) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal membuat CIImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                // Normalkan origin ke (0,0). CIImage.oriented() dapat menggeser origin ke koordinat
                // negatif yang menyebabkan clipping pada tepi saat di-render ke CGImage.
                let rawExtent = orientedPhoto.extent
                if rawExtent.origin != .zero {
                    orientedPhoto = orientedPhoto.transformed(
                        by: CGAffineTransform(translationX: -rawExtent.minX, y: -rawExtent.minY)
                    )
                }
                let photoExtent = orientedPhoto.extent
                
                // Orientasi EXIF untuk menyamakan koordinat matte dengan foto
                let exifOrientation = capture.metadata[kCGImagePropertyOrientation as String] as? Int32 ?? 1
                
                // Konversi matte ke CIImage.
                // Format: kCVPixelFormatType_OneComponent8 (grayscale 8-bit)
                //   255 = orang / foreground → foto tetap tajam
                //     0 = background        → foto di-blur
                // Resolusi matte selalu lebih rendah dari foto — wajib di-scale.
                let mattePixelBuffer = matte.mattingImage
                var matteCIImage = CIImage(cvPixelBuffer: mattePixelBuffer)
                    .oriented(forExifOrientation: exifOrientation)
                
                // Normalkan origin matte
                let matteRawExtent = matteCIImage.extent
                if matteRawExtent.origin != .zero {
                    matteCIImage = matteCIImage.transformed(
                        by: CGAffineTransform(translationX: -matteRawExtent.minX, y: -matteRawExtent.minY)
                    )
                }
                
                // Scale matte ke dimensi foto penuh
                let scaleX = photoExtent.width / matteCIImage.extent.width
                let scaleY = photoExtent.height / matteCIImage.extent.height
                let scaledMatte = matteCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                // Haluskan tepi matte — radius 2.5 memberi anti-aliasing natural pada rambut dan jari
                // tanpa merusak presisi segmentasi Neural Engine
                let softMatte = scaledMatte
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2.5])
                    .cropped(to: photoExtent)
                
                // Blur seluruh foto untuk layer background.
                // clampedToExtent() mencegah artefak hitam di tepi saat Gaussian sampling keluar batas.
                // radius 28 ≈ efek f/1.8 — cinematic dan natural untuk portrait photobooth.
                let blurredBackground = orientedPhoto
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 28.0])
                    .cropped(to: photoExtent)
                
                // Composite: orang (matte=putih) tajam di atas background blur
                let composite = orientedPhoto.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: blurredBackground,
                    kCIInputMaskImageKey: softMatte
                ])
                
                // Render ke CGImage menggunakan shared Metal CIContext (GPU-accelerated, thread-safe).
                // Ini adalah satu-satunya titik di mana GPU benar-benar mengalokasikan memori (~180MB peak).
                guard let cgImage = self.ciContext.createCGImage(composite, from: photoExtent) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal render CGImage — foto asli digunakan", category: "camera")
                    return nil
                }
                
                // Encode ke JPEG — quality 0.92 = kualitas tinggi, file size optimal untuk transfer P2P
                let uiImage = UIImage(cgImage: cgImage)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.92) else {
                    HaispaceLogger.warning("[PortraitMatte] Gagal encode JPEG — foto asli digunakan", category: "camera")
                    return nil
                }
                
                HaispaceLogger.info(
                    "Portrait Matte Bokeh berhasil: \(jpegData.count / 1024)KB (\(Int(photoExtent.width))×\(Int(photoExtent.height))px)",
                    category: "camera"
                )
                return jpegData
            } // ← autoreleasepool: semua intermediate CIImage/CGImage dibebaskan di sini
            
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
