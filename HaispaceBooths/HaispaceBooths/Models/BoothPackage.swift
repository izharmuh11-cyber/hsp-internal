// BoothPackage.swift
// HaispaceBooths — Models
//
// Model paket foto yang tersedia di setiap event.
// Dikonfigurasi admin via Web Dashboard, di-download ke iPad saat sinkronisasi.
//
// Ref: docs/design/06_features.md, docs/design/11_booth_modes.md

import Foundation

// MARK: - BoothPackage

/// Paket foto yang ditawarkan kepada tamu.
/// Harga dalam Rupiah (Integer, bukan Double — menghindari floating point issues).
struct BoothPackage: Codable, Equatable, Identifiable {
    let id: String
    let name: String            // Contoh: "The Stage", "The Mini", "The VIP"
    let price: Int              // Dalam Rupiah, contoh: 50000
    let durationSeconds: Int    // Total durasi sesi foto, contoh: 300 (5 menit)
    let maxPhotoCount: Int      // Jumlah maksimal foto yang bisa diambil dalam sesi
    let minPhotoCount: Int      // Jumlah minimum foto yang harus dipilih tamu
    let intervalSeconds: Int    // Jeda antar jepretan otomatis, contoh: 8
    let description: String     // Deskripsi singkat untuk tamu
    let isPopular: Bool         // Apakah ini paket yang paling sering dipilih?

    // Add-ons yang termasuk dalam paket ini (opsional)
    let includedAddonIds: [String]

    // Computed
    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "Rp \(price)"
    }

    var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if seconds == 0 {
            return "\(minutes) menit"
        }
        return "\(minutes) menit \(seconds) detik"
    }
}

// MARK: - AddonType

/// Jenis add-on yang bisa ditambahkan ke paket
enum AddonType: String, Codable, CaseIterable {
    case filter         // LUT filter premium
    case poseGuide      // AI pose guide
    case memoryBook     // Memory book collage
    case print          // Cetak foto fisik (Epson L8050)
    case extraTime      // Tambahan waktu sesi
    case extraPrints    // Tambahan cetakan

    var displayName: String {
        switch self {
        case .filter: return "Filter Premium"
        case .poseGuide: return "Panduan Pose AI"
        case .memoryBook: return "Memory Book"
        case .print: return "Cetak Foto"
        case .extraTime: return "Waktu Tambahan"
        case .extraPrints: return "Cetakan Tambahan"
        }
    }

    var iconName: String {
        switch self {
        case .filter: return "sparkles"
        case .poseGuide: return "figure.stand"
        case .memoryBook: return "book.closed"
        case .print: return "printer"
        case .extraTime: return "clock.badge.plus"
        case .extraPrints: return "photo.stack"
        }
    }
}

// MARK: - Mock Data (SwiftUI Preview)

extension BoothPackage {

    static var mockStandard: BoothPackage {
        BoothPackage(
            id: "pkg-001",
            name: "The Stage",
            price: 50_000,
            durationSeconds: 300,
            maxPhotoCount: 20,
            minPhotoCount: 3,
            intervalSeconds: 8,
            description: "Paket standar — 5 menit foto, pilih 3 foto terbaik",
            isPopular: true,
            includedAddonIds: []
        )
    }

    static var mockMini: BoothPackage {
        BoothPackage(
            id: "pkg-002",
            name: "The Mini",
            price: 30_000,
            durationSeconds: 180,
            maxPhotoCount: 12,
            minPhotoCount: 2,
            intervalSeconds: 10,
            description: "Paket mini — 3 menit foto, pilih 2 foto",
            isPopular: false,
            includedAddonIds: []
        )
    }

    static var mockVIP: BoothPackage {
        BoothPackage(
            id: "pkg-003",
            name: "The VIP",
            price: 100_000,
            durationSeconds: 600,
            maxPhotoCount: 40,
            minPhotoCount: 5,
            intervalSeconds: 8,
            description: "Paket premium — 10 menit, pilih 5 foto + cetak 1 foto",
            isPopular: false,
            includedAddonIds: ["addon-print"]
        )
    }

    static var mockPackages: [BoothPackage] {
        [mockMini, mockStandard, mockVIP]
    }
}
