// GuestInfo.swift
// HaispaceBooths — Models
//
// Informasi tamu yang diisi saat registrasi di awal sesi.
// Data ini dipersist ke CoreData lokal dan di-sync ke cloud setelah sesi.
//
// Ref: docs/design/03_user_flow.md, docs/design/31_database_schema.md

import Foundation

// MARK: - GuestInfo

/// Informasi identitas tamu yang mendaftar di kiosk iPad.
/// Data ini tidak sensitif — hanya nama dan Instagram/nomor HP untuk pengiriman foto.
struct GuestInfo: Codable, Equatable {
    let name: String
    let instagram: String?      // Opsional — untuk tag foto di social media
    let phoneNumber: String?    // Opsional — untuk kirim download link via WA
    let queueNumber: Int        // Nomor antrian yang ditampilkan di SmartQueue PWA

    /// Validasi: minimal nama harus diisi
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Display name yang bersih (trimmed)
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    /// Instagram handle tanpa @ (untuk display)
    var instagramHandle: String? {
        guard let ig = instagram, !ig.isEmpty else { return nil }
        return ig.hasPrefix("@") ? String(ig.dropFirst()) : ig
    }
}

// MARK: - GuestInfo Factory

extension GuestInfo {
    /// Buat GuestInfo dengan validasi input
    static func create(
        name: String,
        instagram: String?,
        phoneNumber: String?,
        queueNumber: Int
    ) -> GuestInfo? {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return nil }
        return GuestInfo(
            name: cleanName,
            instagram: instagram?.trimmingCharacters(in: .whitespaces),
            phoneNumber: phoneNumber?.trimmingCharacters(in: .whitespaces),
            queueNumber: queueNumber
        )
    }
}

// MARK: - Mock Data (SwiftUI Preview)

extension GuestInfo {
    static var mockSarah: GuestInfo {
        GuestInfo(
            name: "Sarah Amalia",
            instagram: "@sarahamalia",
            phoneNumber: "08123456789",
            queueNumber: 1
        )
    }

    static var mockBudi: GuestInfo {
        GuestInfo(
            name: "Budi Santoso",
            instagram: nil,
            phoneNumber: "08987654321",
            queueNumber: 2
        )
    }

    static var mockAnonymous: GuestInfo {
        GuestInfo(
            name: "Tamu",
            instagram: nil,
            phoneNumber: nil,
            queueNumber: 3
        )
    }
}
