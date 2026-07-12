// CapturedPhoto.swift
// HaispaceBooths — Models
//
// Model foto yang diterima dari iPhone via P2P.
// Lifecycle: thumbnail diterima dulu (cepat), lalu full quality replace thumbnail.
//
// Ref: docs/design/40_concurrency_strategy.md — AIC Dual-Channel
// Ref: docs/design/08_p2p_communication.md — Channel 1 & 2

import Foundation
import UIKit
import Observation

// MARK: - PhotoQuality

/// Status kualitas foto yang tersimpan saat ini
enum PhotoQuality {
    case thumbnail      // 300KB compressed — sudah ada, tampil di grid
    case fullQuality    // 2-3MB original — masih dalam transfer atau sudah ada
}

// MARK: - CapturedPhoto

/// Foto yang diambil iPhone dan diterima iPad via P2P.
/// Bersifat mutable — di-upgrade dari thumbnail ke full quality saat transfer selesai.
@Observable
final class CapturedPhoto: Identifiable {

    // MARK: Identity
    let id: String              // UUID yang dibuat iPhone saat capture
    let capturedAt: Date        // Timestamp capture di iPhone
    let sortOrder: Int          // Urutan dalam sesi (foto ke-1, ke-2, dst)

    // MARK: Image Data
    var thumbnailData: Data        // Selalu ada
    var fullQualityData: Data?     // Nil sampai Channel 2 selesai

    // MARK: State
    var quality: PhotoQuality = .thumbnail
    var isSelected: Bool = false

    // MARK: Computed

    /// Image untuk ditampilkan — full quality jika ada, fallback ke thumbnail
    var displayImage: UIImage? {
        if let fullData = fullQualityData {
            return UIImage(data: fullData)
        }
        return UIImage(data: thumbnailData)
    }

    /// Thumbnail untuk grid view (selalu cepat)
    var thumbnailImage: UIImage? {
        UIImage(data: thumbnailData)
    }

    /// Apakah foto sudah dalam kualitas penuh?
    var isFullQuality: Bool {
        quality == .fullQuality
    }

    // MARK: - Init

    init(id: String, thumbnailData: Data, capturedAt: Date, sortOrder: Int) {
        self.id = id
        self.thumbnailData = thumbnailData
        self.capturedAt = capturedAt
        self.sortOrder = sortOrder
    }

    // MARK: - Upgrade

    /// Dipanggil saat Channel 2 (full quality) transfer selesai
    func upgradeToFull(data: Data) {
        self.fullQualityData = data
        self.quality = .fullQuality
    }
}

// MARK: - CapturedPhoto Equatable

extension CapturedPhoto: Equatable {
    static func == (lhs: CapturedPhoto, rhs: CapturedPhoto) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - PhotoThumbnail (dari P2P Transfer)

/// Payload thumbnail yang diterima via P2P Channel 1
struct PhotoThumbnail: Codable {
    let photoId: String
    let data: Data
    let capturedAt: Date
    let sortOrder: Int
}

// MARK: - Mock Data (SwiftUI Preview)

extension CapturedPhoto {

    /// Buat mock foto dengan warna solid untuk Preview
    static func mockPhoto(sortOrder: Int) -> CapturedPhoto {
        // Buat placeholder image 100x100 dengan warna berbeda per foto
        let colors: [UIColor] = [.systemBlue, .systemPink, .systemGreen, .systemOrange, .systemPurple]
        let color = colors[sortOrder % colors.count]

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400))
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))

            // Nomor foto di tengah
            let text = "Foto \(sortOrder + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.white
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (300 - size.width) / 2, y: (400 - size.height) / 2), withAttributes: attrs)
        }

        let data = image.jpegData(compressionQuality: 0.6) ?? Data()
        return CapturedPhoto(
            id: "mock-photo-\(sortOrder)",
            thumbnailData: data,
            capturedAt: Date().addingTimeInterval(TimeInterval(-sortOrder * 8)),
            sortOrder: sortOrder
        )
    }

    /// Array mock photos untuk Preview
    static func mockPhotos(count: Int) -> [CapturedPhoto] {
        (0..<count).map { CapturedPhoto.mockPhoto(sortOrder: $0) }
    }
}
