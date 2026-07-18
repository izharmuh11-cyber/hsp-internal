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
    // Inisialisasi CIContext berulang-ulang di dalam thread background/callback pemotretan
    // bisa memicu driver GPU hang/crash seketika. Reusable context ini sangat efisien dan aman.
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpaceCreateDeviceRGB() as Any
    ])
    
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
            let bokehResult: Data? = autoreleasepool {
                guard let ciImage = CIImage(data: rawData),
                      let filter = CIFilter(name: "CIDepthBlurEffect") else {
                    HaispaceLogger.warning("Gagal inisialisasi CIDepthBlurEffect - foto asli digunakan", category: "camera")
                    return nil
                }
                
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
                
                // Render menggunakan shared ciContext yang dijamin thread-safe
                guard let cgImage = self.ciContext.createCGImage(outputCIImage, from: outputCIImage.extent) else {
                    HaispaceLogger.warning("Gagal render bokeh CGImage - foto asli digunakan", category: "camera")
                    return nil
                }
                
                let uiImage = UIImage(cgImage: cgImage)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
                    HaispaceLogger.warning("Gagal konversi bokeh ke JPEG - foto asli digunakan", category: "camera")
                    return nil
                }
                
                HaispaceLogger.info("Bokeh Portrait berhasil diterapkan: \(jpegData.count / 1024)KB", category: "camera")
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
