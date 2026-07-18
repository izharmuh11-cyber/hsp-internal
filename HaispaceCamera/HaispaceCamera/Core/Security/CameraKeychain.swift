// CameraKeychain.swift
// HaispaceCamera — Core/Security
//
// Keychain helper untuk HaispaceCamera target.
// Mirror dari HaispaceBooths/Core/Security/KeychainHelper.swift
// dengan key yang berbeda untuk isolasi antar app.
//
// Ref: docs/design/30_authentication.md

import Foundation
import Security
import CommonCrypto

// MARK: - Camera Keychain Keys

enum CameraKeychainKey: String, CaseIterable {
    case authToken     = "id.haispaceproject.camera.auth_token"
    case licenseToken  = "id.haispaceproject.camera.license_token"
    case deviceUUID    = "id.haispaceproject.camera.device_uuid"
    case operatorPIN   = "id.haispaceproject.camera.operator_pin"
    // Token GitHub PAT untuk auto-upload log.
    // Disimpan di Keychain (bukan UserDefaults) agar aman dan tidak perlu input ulang.
    case githubPAT     = "id.haispaceproject.camera.github_pat"
}

// MARK: - KeychainHelper (Camera)

struct KeychainHelper {

    @discardableResult
    static func save(_ value: String, for key: CameraKeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, for: key)
    }

    @discardableResult
    static func save(_ data: Data, for key: CameraKeychainKey) -> Bool {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(for key: CameraKeychainKey) -> String? {
        guard let data = readData(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func readData(for key: CameraKeychainKey) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(_ key: CameraKeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func deleteAll() {
        CameraKeychainKey.allCases.forEach { delete($0) }
    }

    // Convenience
    static func getAuthToken() -> String? { read(for: .authToken) }
    @discardableResult
    static func saveAuthToken(_ token: String) -> Bool { save(token, for: .authToken) }
    @discardableResult
    static func deleteAuthToken() -> Bool { delete(.authToken) }

    // MARK: GitHub PAT (Log Uploader)
    static func getGitHubPAT() -> String? { read(for: .githubPAT) }
    @discardableResult
    static func saveGitHubPAT(_ token: String) -> Bool { save(token, for: .githubPAT) }
    @discardableResult
    static func deleteGitHubPAT() -> Bool { delete(.githubPAT) }

    static func getOrCreateDeviceUUID() -> String {
        if let existing = read(for: .deviceUUID) { return existing }
        let uuid = UUID().uuidString
        save(uuid, for: .deviceUUID)
        return uuid
    }
}

// MARK: - SHA256 (Camera)

struct SHA256Hash {
    static func hash(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return input }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
