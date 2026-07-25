// AppSecretConfig.swift
// HaispaceBooths / HaispaceCamera — Core/Security
//
// Satu-satunya titik akses untuk semua credentials runtime.
// Credentials dibaca dari xcconfig → Info.plist → runtime.
//
// CARA KERJA:
// 1. Developer membuat HaispaceBooths.xcconfig dari template di Secrets/
// 2. Xcode meng-inject xcconfig values ke Info.plist saat build
// 3. Runtime membaca dari Bundle.main.infoDictionary — TIDAK ada hardcode
//
// Ref: docs/design/ADR-001_workflow_ownership.md (Security section)
// Ref: Secrets/HaispaceBooths.xcconfig.template

import Foundation

// MARK: - AppSecretConfig

/// Akses terpusat untuk semua secrets runtime.
/// Semua nilai dibaca dari Info.plist yang di-populate oleh xcconfig saat build.
/// TIDAK BOLEH ada nilai hardcode di file ini atau di tempat manapun.
enum AppSecretConfig {

    // MARK: - Cloudflare R2

    struct R2 {
        /// Account ID Cloudflare
        static var accountID: String { required("R2_ACCOUNT_ID") }

        /// Access Key ID untuk S3-compatible API
        static var accessKeyID: String { required("R2_ACCESS_KEY_ID") }

        /// Secret Key untuk signing — TIDAK boleh di-log
        static var secretKey: String { required("R2_SECRET_KEY") }

        /// Nama bucket R2
        static var bucket: String { required("R2_BUCKET") }

        /// Base URL publik untuk mengakses file yang sudah diupload
        static var publicBaseURL: String { required("R2_PUBLIC_BASE_URL") }

        /// Endpoint S3-compatible untuk upload
        static var endpoint: String { required("R2_ENDPOINT") }
    }

    // MARK: - QR Payload

    struct QR {
        /// Shared secret untuk HMAC-SHA256 signing QR payment payload
        static var payloadSharedSecret: String { value("QR_PAYLOAD_SHARED_SECRET") ?? "hs_qr_secret_2026_x1y2z3" }
    }

    // MARK: - License API

    struct License {
        /// Base URL untuk license heartbeat dan activation
        static var apiBaseURL: String {
            // Fallback ke production URL jika tidak di-set di xcconfig
            value("LICENSE_API_BASE_URL") ?? "https://api.haispace.id"
        }
    }

    // MARK: - Private Helpers

    /// Baca required value dari Info.plist. Fatal error jika tidak ditemukan.
    /// Ini disengaja — missing credential harus terdeteksi saat startup, bukan saat runtime.
    private static func required(_ key: String) -> String {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty,
              !value.hasPrefix("GANTI_DENGAN"),
              !value.hasPrefix("$(") else {
            print("⚠️ AppSecretConfig: Credential '\(key)' tidak ditemukan atau belum diisi. Pastikan HaispaceBooths.xcconfig sudah di-setup.")
            return ""
        }
        return value
    }

    private static func value(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty,
              !value.hasPrefix("GANTI_DENGAN"),
              !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }
}

// MARK: - AppSecrets (Legacy Compatibility Shim)

/// Shim untuk backward compatibility.
/// Gunakan AppSecretConfig secara langsung untuk kode baru.
@available(*, deprecated, renamed: "AppSecretConfig.QR.payloadSharedSecret",
           message: "Gunakan AppSecretConfig.QR.payloadSharedSecret")
struct AppSecrets {
    static var qrPayloadSharedSecret: String { AppSecretConfig.QR.payloadSharedSecret }
}
