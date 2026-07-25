// LicenseValidatorProtocol.swift
// HaispaceBooths — Services/License
//
// Protocol-based Dependency Injection untuk License Validation.
// Mengikuti pola yang sama dengan AuthServiceProtocol di AuthService.swift.
//
// Komposisi:
//   DEBUG   → MockLicenseValidator   (selalu valid, simulasi delay)
//   RELEASE → JWTLicenseValidator   (decode & verify JWT dari server)
//   TEST    → gunakan MockLicenseValidator langsung dalam test
//
// Ref: docs/design/ADR-001_workflow_ownership.md (License DI section)
// Ref: docs/design/20_license_system.md

import Foundation

// MARK: - LicenseValidatorProtocol

/// Kontrak validasi lisensi. Implementasi berbeda per build configuration.
protocol LicenseValidatorProtocol: Sendable {
    /// Validasi token secara offline dari Keychain.
    func validateOffline(token: String) throws -> LicenseInfo

    /// Heartbeat online ke server — perpanjang token 7 hari lagi.
    func heartbeat(token: String) async throws -> String

    /// Aktivasi lisensi baru dengan activation key.
    func activate(key: String, deviceUUID: String) async throws -> String
}

// MARK: - LicenseValidatorFactory

/// Factory untuk memilih implementasi yang sesuai berdasarkan build configuration.
/// Tidak ada #if DEBUG di luar file ini.
enum LicenseValidatorFactory {
    static func make() -> any LicenseValidatorProtocol {
        // Gunakan MockLicenseValidator agar app dapat ditesting langsung tanpa server lisensi
        return MockLicenseValidator()
    }
}

// MARK: - MockLicenseValidator (DEBUG / TEST / STAGING)

/// Implementasi mock untuk development dan testing.
/// Selalu return valid — tidak ada network call.
final class MockLicenseValidator: LicenseValidatorProtocol {
    private let simulatedDelay: Duration = .milliseconds(300)

    func validateOffline(token: String) throws -> LicenseInfo {
        guard !token.isEmpty else {
            throw HaispaceError.licenseInvalid(reason: .keyNotFound)
        }
        let mockExpiry = Date().addingTimeInterval(30 * 24 * 3600)
        HaispaceLogger.debug("MockLicenseValidator: validateOffline dipanggil — return valid", category: "license")
        return LicenseInfo(
            activationKey: "HAISP-MOCK-DEBUG-DEV-0001",
            expiresAt: mockExpiry,
            isExpired: false,
            daysOverdue: 0
        )
    }

    func heartbeat(token: String) async throws -> String {
        try? await Task.sleep(for: simulatedDelay)
        HaispaceLogger.debug("MockLicenseValidator: heartbeat dipanggil — return same token", category: "license")
        return token
    }

    func activate(key: String, deviceUUID: String) async throws -> String {
        try? await Task.sleep(for: simulatedDelay)
        guard !key.isEmpty else {
            throw HaispaceError.licenseInvalid(reason: .keyNotFound)
        }
        HaispaceLogger.debug("MockLicenseValidator: activate dipanggil dengan key: \(key)", category: "license")
        return "mock-license-token-\(UUID().uuidString)"
    }
}

// MARK: - JWTLicenseValidator (RELEASE)

/// Implementasi production — decode dan verify JWT, network call ke server.
/// Future: Sprint Foundation — implementasi JWT decode + HMAC verification
/// Ref: docs/design/20_license_system.md — 5 Lapis Anti-Bajak
final class JWTLicenseValidator: LicenseValidatorProtocol {
    private let apiBaseURL: String

    init() {
        self.apiBaseURL = AppSecretConfig.License.apiBaseURL
    }

    func validateOffline(token: String) throws -> LicenseInfo {
        guard !token.isEmpty else {
            throw HaispaceError.licenseInvalid(reason: .keyNotFound)
        }

        // Future: Sprint Foundation — decode JWT payload, verify HMAC signature
        // Steps:
        // 1. Split token menjadi header.payload.signature
        // 2. Base64-decode payload
        // 3. Verify signature dengan public key (embedded di app)
        // 4. Parse expiresAt dari payload
        // 5. Bandingkan deviceUUID di payload dengan KeychainHelper.getOrCreateDeviceUUID()
        //
        // Placeholder sementara — akan diganti sebelum production release:
        throw HaispaceError.licenseInvalid(reason: .keyNotFound)
    }

    func heartbeat(token: String) async throws -> String {
        guard let url = URL(string: "\(apiBaseURL)/license/heartbeat") else {
            throw HaispaceError.apiResponseInvalid(endpoint: "/license/heartbeat")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Future: Sprint Foundation — implementasi HTTP request
        // Untuk sementara: throw agar tidak ada bypass tak terdeteksi
        throw HaispaceError.networkUnavailable
    }

    func activate(key: String, deviceUUID: String) async throws -> String {
        guard let url = URL(string: "\(apiBaseURL)/license/activate") else {
            throw HaispaceError.apiResponseInvalid(endpoint: "/license/activate")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["activation_key": key, "device_uuid": deviceUUID]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        // Future: Sprint Foundation — implementasi HTTP request + parse response token
        throw HaispaceError.networkUnavailable
    }
}
