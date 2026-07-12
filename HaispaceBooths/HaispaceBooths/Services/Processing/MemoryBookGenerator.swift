// MemoryBookGenerator.swift
// HaispaceBooths — Services/Processing
//
// Layanan yang merangkai beberapa foto (beserta frame-nya) 
// menjadi satu gambar kolase 9:16 (Memory Card) untuk Story tamu.
// Diproses asinkron tanpa nge-blok main thread.
//
// Ref: docs/design/38_memory_book.md

import UIKit
import CoreImage

final class MemoryBookGenerator: @unchecked Sendable {
    
    static let shared = MemoryBookGenerator()
    
    private init() {}
    
    /// Membuat Memory Card 9:16 dari kumpulan foto
    func generateMemoryCard(photos: [UIImage], eventName: String, guestName: String, completion: @escaping (UIImage?) -> Void) {
        
        Task.detached(priority: .userInitiated) {
            let outputSize = CGSize(width: 1080, height: 1920)
            let renderer = UIGraphicsImageRenderer(size: outputSize)
            
            let result = renderer.image { ctx in
                let context = ctx.cgContext
                
                // 1. Background Gradient (Dark Theme)
                let colors = [
                    UIColor(hex: "#1A1A24").cgColor,
                    UIColor(hex: "#0D0D14").cgColor
                ] as CFArray
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: outputSize.width / 2, y: 0),
                        end: CGPoint(x: outputSize.width / 2, y: outputSize.height),
                        options: []
                    )
                }
                
                // 2. Teks Header
                let headerText = "✨ HAISPACE — \(eventName.uppercased())"
                let headerAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let headerSize = headerText.size(withAttributes: headerAttr)
                let headerRect = CGRect(x: (outputSize.width - headerSize.width) / 2, y: 120, width: headerSize.width, height: headerSize.height)
                headerText.draw(in: headerRect, withAttributes: headerAttr)
                
                // 3. Hitung Layout Foto
                let layoutFrames = self.calculateLayout(for: photos.count, in: outputSize)
                
                // Gambar setiap foto
                for (index, photo) in photos.enumerated() {
                    if index < layoutFrames.count {
                        let rect = layoutFrames[index]
                        
                        // Gambar bayangan/shadow di belakang foto
                        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                        
                        // Gambar foto (aspect fill)
                        photo.draw(in: rect)
                        
                        // Hapus shadow untuk elemen berikutnya
                        context.setShadow(offset: .zero, blur: 0, color: nil)
                    }
                }
                
                // 4. Footer Teks
                let footerText = "\(guestName) · Haispace.id"
                let footerAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 32, weight: .medium),
                    .foregroundColor: UIColor.lightGray
                ]
                let footerSize = footerText.size(withAttributes: footerAttr)
                let footerRect = CGRect(x: (outputSize.width - footerSize.width) / 2, y: outputSize.height - 180, width: footerSize.width, height: footerSize.height)
                footerText.draw(in: footerRect, withAttributes: footerAttr)
            }
            
            await MainActor.run {
                completion(result)
            }
        }
    }
    
    // MARK: - Layout Engine
    
    private func calculateLayout(for count: Int, in size: CGSize) -> [CGRect] {
        var frames: [CGRect] = []
        let padding: CGFloat = 60
        let topOffset: CGFloat = 250 // Di bawah header
        let bottomOffset: CGFloat = 250 // Di atas footer
        let availableHeight = size.height - topOffset - bottomOffset
        
        if count == 2 {
            // Landscape Layout: 2 foto berdampingan secara vertikal (seperti photostrip 2 foto)
            let photoWidth = size.width - (padding * 2)
            let photoHeight = (availableHeight - padding) / 2
            
            frames.append(CGRect(x: padding, y: topOffset, width: photoWidth, height: photoHeight))
            frames.append(CGRect(x: padding, y: topOffset + photoHeight + padding, width: photoWidth, height: photoHeight))
            
        } else if count == 3 {
            // Classic Photostrip: 3 foto tumpuk vertikal
            let photoWidth = size.width - (padding * 2)
            let photoHeight = (availableHeight - (padding * 2)) / 3
            
            for i in 0..<3 {
                let y = topOffset + (CGFloat(i) * (photoHeight + padding))
                frames.append(CGRect(x: padding, y: y, width: photoWidth, height: photoHeight))
            }
            
        } else if count >= 4 {
            // Magazine Grid (2x2)
            let gridSpacing: CGFloat = 40
            let cols = 2
            let photoWidth = (size.width - (padding * 2) - gridSpacing) / 2
            let photoHeight = (availableHeight - gridSpacing) / 2
            
            for i in 0..<4 { // Maksimal 4 untuk grid ini
                let row = i / cols
                let col = i % cols
                let x = padding + (CGFloat(col) * (photoWidth + gridSpacing))
                let y = topOffset + (CGFloat(row) * (photoHeight + gridSpacing))
                frames.append(CGRect(x: x, y: y, width: photoWidth, height: photoHeight))
            }
        }
        
        return frames
    }
}
