// HaispaceUser.swift
// HaispaceBooths — Models
//
// Model data pengguna (admin/operator) yang diterima dari server setelah login.
//
// Ref: docs/design/30_authentication.md, docs/design/31_database_schema.md

import Foundation

// MARK: - UserRole

/// Peran pengguna yang menentukan hak akses
enum UserRole: String, Codable, Equatable {
    case admin      = "ADMIN"
    case `operator` = "OPERATOR"

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .operator: return "Operator"
        }
    }

    /// Apakah role ini punya akses ke data finansial global?
    var hasFinancialAccess: Bool {
        self == .admin
    }

    /// Apakah role ini bisa membuat event baru?
    var canCreateEvents: Bool {
        self == .admin
    }
}

// MARK: - HaispaceUser

/// Model pengguna yang diterima dari API setelah login sukses.
/// Disimpan sementara di memori (tidak persisten) — token di Keychain.
struct HaispaceUser: Codable, Equatable, Identifiable {
    let id: String           // UUID dari database
    let name: String
    let email: String
    let role: UserRole
    let assignedEventIds: [String] // Event yang ditugaskan ke operator ini

    // Tidak ada password_hash — TIDAK PERNAH dikirim dari server ke client

    var isAdmin: Bool { role == .admin }
    var isOperator: Bool { role == .operator }
}

// MARK: - Mock Data (SwiftUI Preview)

extension HaispaceUser {

    static var mockAdmin: HaispaceUser {
        HaispaceUser(
            id: "admin-uuid-001",
            name: "Izhar",
            email: "izhar@haispace.id",
            role: .admin,
            assignedEventIds: []
        )
    }

    static var mockOperator: HaispaceUser {
        HaispaceUser(
            id: "operator-uuid-001",
            name: "Budi Santoso",
            email: "budi@haispace.id",
            role: .operator,
            assignedEventIds: ["event-uuid-001", "event-uuid-002"]
        )
    }
}
