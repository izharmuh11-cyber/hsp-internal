// KeychainHelper.swift
// HaispaceBooths — Core/Security
//
// Penyimpanan aman JWT token di iOS Keychain menggunakan Secure Enclave.
// Token TIDAK BOLEH disimpan di UserDefaults — sangat tidak aman.
//
// Ref: docs/design/30_authentication.md, docs/design/20_license_system.md

import Foundation
import Security

// MARK: - Keychain Keys

/// Semua key Keychain yang digunakan di HaiBooth
enum KeychainKey: String {
    case authToken          = "id.haispaceproject.booth.auth_token"
    case licenseToken       = "id.haispaceproject.booth.license_token"
    case operatorPIN        = "id.haispaceproject.booth.operator_pin"
    case deviceUUID         = "id.haispaceproject.booth.device_uuid"
}

// MARK: - KeychainHelper

/// Helper untuk read/write/delete dari iOS Keychain.
/// Menggunakan `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` untuk keamanan maksimal:
/// - Data hanya bisa diakses saat device unlocked
/// - Data tidak bisa dipindahkan ke device lain (ThisDeviceOnly)
/// - Data tidak di-backup ke iCloud
struct KeychainHelper {

    // MARK: - Write

    /// Simpan string ke Keychain
    @discardableResult
    static func save(_ value: String, for key: KeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, for: key)
    }

    /// Simpan Data ke Keychain
    @discardableResult
    static func save(_ data: Data, for key: KeychainKey) -> Bool {
        // Hapus dulu jika sudah ada (update)
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            // Hanya bisa diakses saat unlocked, tidak bisa dipindahkan ke device lain
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            HaispaceLogger.warning("Keychain save gagal untuk key '\(key.rawValue)': OSStatus \(status)")
        }

        return status == errSecSuccess
    }

    // MARK: - Read

    /// Baca string dari Keychain
    static func read(for key: KeychainKey) -> String? {
        guard let data = readData(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Baca Data dari Keychain
    static func readData(for key: KeychainKey) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                HaispaceLogger.warning("Keychain read gagal untuk key '\(key.rawValue)': OSStatus \(status)")
            }
            return nil
        }

        return result as? Data
    }

    // MARK: - Delete

    /// Hapus satu item dari Keychain
    @discardableResult
    static func delete(_ key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Hapus semua Keychain data milik app (digunakan saat logout total)
    static func deleteAll() {
        KeychainKey.allCases.forEach { delete($0) }
        HaispaceLogger.info("Semua Keychain data telah dihapus", category: "security")
    }

    // MARK: - Convenience: Auth Token

    /// Simpan JWT auth token
    @discardableResult
    static func saveAuthToken(_ token: String) -> Bool {
        save(token, for: .authToken)
    }

    /// Baca JWT auth token yang tersimpan
    static func getAuthToken() -> String? {
        read(for: .authToken)
    }

    /// Hapus JWT auth token (logout)
    @discardableResult
    static func deleteAuthToken() -> Bool {
        delete(.authToken)
    }

    // MARK: - Convenience: License Token

    @discardableResult
    static func saveLicenseToken(_ token: String) -> Bool {
        save(token, for: .licenseToken)
    }

    static func getLicenseToken() -> String? {
        read(for: .licenseToken)
    }

    @discardableResult
    static func deleteLicenseToken() -> Bool {
        delete(.licenseToken)
    }

    // MARK: - Convenience: Operator PIN

    @discardableResult
    static func saveOperatorPIN(_ pin: String) -> Bool {
        // PIN di-hash sebelum disimpan (SHA-256)
        let hashedPIN = SHA256Hash.hash(pin)
        return save(hashedPIN, for: .operatorPIN)
    }

    /// Verifikasi PIN yang dimasukkan operator
    static func verifyOperatorPIN(_ inputPIN: String) -> Bool {
        guard let storedHash = read(for: .operatorPIN) else { return false }
        let inputHash = SHA256Hash.hash(inputPIN)
        return storedHash == inputHash
    }

    @discardableResult
    static func deleteOperatorPIN() -> Bool {
        delete(.operatorPIN)
    }

    // MARK: - Convenience: Device UUID

    /// Dapatkan atau buat UUID unik perangkat (persisten di Keychain)
    static func getOrCreateDeviceUUID() -> String {
        if let existing = read(for: .deviceUUID) {
            return existing
        }
        // Buat UUID baru dan simpan permanent
        let newUUID = UUID().uuidString
        save(newUUID, for: .deviceUUID)
        HaispaceLogger.info("Device UUID baru dibuat: \(newUUID)", category: "security")
        return newUUID
    }
}

// MARK: - KeychainKey CaseIterable

extension KeychainKey: CaseIterable {}

// MARK: - SHA256 Helper (minimal, tanpa CryptoKit untuk kompatibilitas)

import CommonCrypto

struct SHA256Hash {
    static func hash(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return input }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
