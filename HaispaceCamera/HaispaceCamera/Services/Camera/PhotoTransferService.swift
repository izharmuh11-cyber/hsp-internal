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

actor PhotoTransferService {
    static let shared = PhotoTransferService()
    
    private struct PendingTransfer {
        let photoId: String
        let photoData: Data
    }
    
    private var fullQualityQueue: [PendingTransfer] = []
    private var isProcessingQueue = false
    
    private init() {}
    
    /// Dipanggil setiap kali iPhone selesai mengambil foto resolusi tinggi
    func handleNewCapture(photoId: String, capture: AVCapturePhoto) async {
        guard let data = capture.fileDataRepresentation() else {
            HaispaceLogger.error("Gagal mendapatkan raw data foto dari jepretan", category: "camera")
            return
        }
        
        HaispaceLogger.info("Mulai dual-channel transfer untuk \(photoId)", category: "p2p")
        
        async let thumbnailTask: Void = sendThumbnailImmediately(photoId: photoId, data: data)
        async let queueTask: Void = enqueueFullQuality(photoId: photoId, data: data)
        
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
    private func enqueueFullQuality(photoId: String, data: Data) async {
        let pending = PendingTransfer(photoId: photoId, photoData: data)
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
                sortOrder: 0
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
