// FrameCompositorService.swift
// HaispaceBooths — Services/Processing
//
// Melakukan render CoreImage untuk menggabungkan foto mentah tamu
// dengan frame overlay transparan (PNG).
//
// Ref: docs/design/13_frame_system.md, docs/design/14_photo_editing.md

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class FrameCompositorService: @unchecked Sendable {
    
    static let shared = FrameCompositorService()
    
    // Gunakan CIContext statis untuk efisiensi
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    private init() {}
    
    /// Merender foto mentah (CapturedPhoto) dengan frame overlay (PhotoFrame)
    func render(photo: CapturedPhoto, frame: PhotoFrame?, sessionId: String) async throws -> RenderedPhoto {
        // Karena ini operasi berat, kita lepas dari MainActor
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { throw CompositorError.serviceUnavailable }
            
            // 1. Dapatkan full quality image
            let photoData = photo.fullQualityData ?? photo.thumbnailData
            guard let originalImage = CIImage(data: photoData) else {
                throw CompositorError.invalidPhotoData
            }
            
            // 2. Jika tidak ada frame, langsung kembalikan raw data
            guard let frame = frame else {
                let data = self.exportJPEG(ciImage: originalImage) ?? photoData
                return RenderedPhoto(
                    sourcePhotoId: photo.id,
                    sessionId: sessionId,
                    data: data,
                    frameId: nil,
                    filterName: nil
                )
            }
            
            // 3. Load Frame Image (CIImage)
            guard let frameImage = self.loadFrameImage(frame: frame) else {
                throw CompositorError.frameNotFound
            }
            
            // 4. Transformasi (Crop / Scale) Foto Original ke Aspect Ratio Frame
            // Opsi: Aspect Fill (memotong sisi yang lebih)
            let targetSize = frameImage.extent.size
            let scaledPhoto = self.aspectFill(image: originalImage, targetSize: targetSize)
            
            // 5. Compositing (Frame Over Photo)
            let compositeFilter = CIFilter.sourceOverCompositing()
            compositeFilter.inputImage = frameImage
            compositeFilter.backgroundImage = scaledPhoto
            
            guard let finalCIImage = compositeFilter.outputImage else {
                throw CompositorError.compositingFailed
            }
            
            // 6. Render ke JPEG
            guard let finalData = self.exportJPEG(ciImage: finalCIImage) else {
                throw CompositorError.renderFailed
            }
            
            // 7. Kembalikan RenderedPhoto
            return RenderedPhoto(
                sourcePhotoId: photo.id,
                sessionId: sessionId,
                data: finalData,
                frameId: frame.id,
                filterName: nil // Filter implementasi nanti
            )
        }.value
    }
    
    // MARK: - CoreImage Helpers
    
    /// Mengubah ukuran CIImage menjadi Aspect Fill pada ukuran target
    private func aspectFill(image: CIImage, targetSize: CGSize) -> CIImage {
        let imageSize = image.extent.size
        
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let scale = max(widthRatio, heightRatio)
        
        // Scale
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Crop ke tengah
        let scaledSize = scaledImage.extent.size
        let dx = (scaledSize.width - targetSize.width) / 2.0
        let dy = (scaledSize.height - targetSize.height) / 2.0
        
        let cropRect = CGRect(
            x: dx,
            y: dy,
            width: targetSize.width,
            height: targetSize.height
        )
        
        return scaledImage.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
    }
    
    private func loadFrameImage(frame: PhotoFrame) -> CIImage? {
        // TODO: Fase 2 - Load dari local storage. 
        // Sementara untuk MVP, kita buat dummy frame image CIImage
        // berwarna transparan dengan border jika localPath nil.
        
        if let path = frame.localPath, let image = UIImage(contentsOfFile: path) {
            return CIImage(image: image)
        } else {
            // Mock Frame (Border Putih)
            let size = CGSize(width: 1080, height: 1440)
            let renderer = UIGraphicsImageRenderer(size: size)
            let mockImage = renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                
                // Border Putih Tebal
                let borderRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(100)
                ctx.cgContext.stroke(borderRect)
                
                // Text/Branding Frame
                let text = "H A I S P A C E   \(frame.name)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 48),
                    .foregroundColor: UIColor.white
                ]
                text.draw(at: CGPoint(x: 100, y: size.height - 150), withAttributes: attrs)
            }
            return CIImage(image: mockImage)
        }
    }
    
    private func exportJPEG(ciImage: CIImage) -> Data? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Errors

enum CompositorError: Error {
    case serviceUnavailable
    case invalidPhotoData
    case frameNotFound
    case compositingFailed
    case renderFailed
}
