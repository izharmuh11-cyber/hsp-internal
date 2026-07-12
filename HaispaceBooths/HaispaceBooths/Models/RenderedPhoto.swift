// RenderedPhoto.swift
// HaispaceBooths — Models
//
// Foto final yang sudah dikomposit dengan frame (CoreImage).
// Ini yang dikirim ke tamu, dicetak, dan di-upload ke cloud.
//
// Ref: docs/design/13_frame_system.md, docs/design/14_photo_editing.md

import Foundation
import UIKit

// MARK: - RenderedPhoto

/// Foto final setelah:
/// 1. Tamu memilih foto dari grid
/// 2. Tamu memilih frame overlay
/// 3. CoreImage compositor menggabungkan foto + filter + frame
struct RenderedPhoto: Identifiable, Equatable {
    let id: String              // UUID baru untuk foto yang sudah dirender
    let sourcePhotoId: String   // ID foto original dari CapturedPhoto
    let sessionId: String       // ID sesi untuk tracking
    let data: Data              // JPEG data foto final (2-3MB)
    let renderedAt: Date

    // Metadata komposisi
    let frameId: String?        // ID frame yang digunakan (nil jika no frame)
    let filterName: String?     // Nama LUT filter yang digunakan (nil jika no filter)

    // Cloud sync status
    var cloudKey: String?       // Path di Cloudflare R2 setelah upload
    var isUploaded: Bool = false

    // MARK: Computed

    var image: UIImage? {
        UIImage(data: data)
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    // MARK: Init

    init(
        sourcePhotoId: String,
        sessionId: String,
        data: Data,
        frameId: String? = nil,
        filterName: String? = nil
    ) {
        self.id = UUID().uuidString
        self.sourcePhotoId = sourcePhotoId
        self.sessionId = sessionId
        self.data = data
        self.renderedAt = Date()
        self.frameId = frameId
        self.filterName = filterName
    }
}

// MARK: - PhotoFrame

/// Frame overlay yang bisa dipilih tamu untuk menghiasi foto
struct PhotoFrame: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let localPath: String?      // Path file PNG di local storage iPad
    let cloudURL: String?       // URL CDN jika belum di-download
    let aspectRatio: FrameAspectRatio
    let isPortrait: Bool        // Apakah frame ini untuk foto portrait?

    var isAvailableOffline: Bool {
        localPath != nil
    }
}

// MARK: - FrameAspectRatio

enum FrameAspectRatio: String, Codable {
    case fourByThree = "4:3"        // Standar foto iPhone landscape
    case threeByFour = "3:4"        // Standar foto iPhone portrait
    case oneByOne    = "1:1"        // Square (Instagram format)
    case nineBySixteen = "9:16"     // Story format

    var cgSize: CGSize {
        switch self {
        case .fourByThree: return CGSize(width: 4, height: 3)
        case .threeByFour: return CGSize(width: 3, height: 4)
        case .oneByOne: return CGSize(width: 1, height: 1)
        case .nineBySixteen: return CGSize(width: 9, height: 16)
        }
    }
}

// MARK: - Mock Data (SwiftUI Preview)

extension RenderedPhoto {
    static func mockRendered(sessionId: String, index: Int) -> RenderedPhoto {
        // Buat placeholder image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1440))
        let image = renderer.image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1440))
        }
        let data = image.jpegData(compressionQuality: 0.85) ?? Data()

        return RenderedPhoto(
            sourcePhotoId: "mock-photo-\(index)",
            sessionId: sessionId,
            data: data,
            frameId: "frame-001",
            filterName: "Cinematic"
        )
    }
}

extension PhotoFrame {
    static var mockFrames: [PhotoFrame] {
        [
            PhotoFrame(
                id: "frame-001",
                name: "Classic White",
                localPath: nil,
                cloudURL: "https://cdn.haispace.id/frames/classic-white.png",
                aspectRatio: .threeByFour,
                isPortrait: true
            ),
            PhotoFrame(
                id: "frame-002",
                name: "Floral Garden",
                localPath: nil,
                cloudURL: "https://cdn.haispace.id/frames/floral-garden.png",
                aspectRatio: .threeByFour,
                isPortrait: true
            ),
            PhotoFrame(
                id: "frame-003",
                name: "Minimalis",
                localPath: nil,
                cloudURL: "https://cdn.haispace.id/frames/minimalis.png",
                aspectRatio: .fourByThree,
                isPortrait: false
            )
        ]
    }
}
