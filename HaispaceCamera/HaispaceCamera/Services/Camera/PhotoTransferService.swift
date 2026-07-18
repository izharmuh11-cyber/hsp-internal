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
    
    /// Dipanggil setiap kali iPhone selesai mengambil foto resolusi tinggi
    func handleNewCapture(photoId: String, capture: AVCapturePhoto, sortOrder: Int, isPortraitActive: Bool) async {
        var photoData: Data? = capture.fileDataRepresentation()
        
        if isPortraitActive,
           let depthData = capture.depthData,
           let rawData = photoData {
            
            // Gunakan autoreleasepool untuk membebaskan intermediate bitmaps Core Image
            // segera setelah selesai. Tanpa ini, iOS bisa akumulasi 200-400MB RAM dari
            // CIImage pipeline pada foto 12MP sebelum ARC sempat membebaskannya.
            let bokehResult: Data? = autoreleasepool { () -> Data? in
                guard let ciImage = CIImage(data: rawData),
                      let filter = CIFilter(name: "CIDepthBlurEffect") else {
                    HaispaceLogger.warning("Gagal inisialisasi CIDepthBlurEffect - foto asli digunakan", category: "camera")
                    return nil
                }
                
                // PENTING: Gunakan gambar asli 12MP untuk input filter agar cocok dengan metadata
                // kalibrasi di depthData. Jika inputImage di-scale sebelum filter, koordinat kalibrasi
                // akan tidak sinkron dan menyebabkan crash instan pada GPU driver.
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(depthData, forKey: "inputDepthData")
                
                // Titik fokus dari operator (tap-to-focus dari iPad)
                let fp = CameraCaptureService.shared.lastFocusPoint
                let focusX = max(0.05, min(0.95, fp.x)) - 0.05
                let focusY = max(0.05, min(0.95, fp.y)) - 0.05
                filter.setValue(CIVector(cgRect: CGRect(x: focusX, y: focusY, width: 0.1, height: 0.1)),
                                forKey: "inputFocusRect")
                // f/4.5 - natural untuk group portrait 2-4 orang di photobooth
                filter.setValue(4.5, forKey: "inputAperture")
                
                guard let outputCIImage = filter.outputImage else {
                    HaispaceLogger.warning("CIDepthBlurEffect tidak menghasilkan output - foto asli digunakan", category: "camera")
                    return nil
                }
                
                // Crop output ke original extent agar terhindar dari crash infinite extent
                let croppedOutput = outputCIImage.cropped(to: ciImage.extent)
                
                // DOWNSCALING SETELAH FILTER (Post-Filter Downscaling):
                // Kita menata skala transformasi di akhir rantai filter. Core Image adalah pull-model renderer,
                // sehingga penataan skala di akhir ini membuat GPU hanya merender bokeh pada resolusi target
                // 5.4MP (2688x2016), yang menghemat VRAM dan mencegah OOM crash dengan sangat stabil.
                let targetWidth: CGFloat = 2688.0
                let scale = targetWidth / ciImage.extent.width
                var finalCIImage = croppedOutput
                
                if scale < 1.0 {
                    finalCIImage = croppedOutput.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                }
                
                // Render menggunakan shared ciContext terakselerasi GPU (Metal) ke CGImage
                guard let cgImage = self.ciContext.createCGImage(finalCIImage, from: finalCIImage.extent) else {
                    HaispaceLogger.warning("Gagal render bokeh CGImage - foto asli digunakan", category: "camera")
                    return nil
                }
                
                let uiImage = UIImage(cgImage: cgImage)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
                    HaispaceLogger.warning("Gagal konversi bokeh ke JPEG - foto asli digunakan", category: "camera")
                    return nil
                }
                
                HaispaceLogger.info("Bokeh Portrait berhasil diterapkan: \(jpegData.count / 1024)KB (Resolusi: \(Int(finalCIImage.extent.width))x\(Int(finalCIImage.extent.height)))", category: "camera")
                return jpegData
            }
            
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
