// LicenseStore.swift
// HaispaceBooths — Core/State
//
// Store untuk status lisensi perangkat.
// Mengelola validasi, heartbeat 7 hari, jailbreak detection, dan demo mode.
//
// Ref: docs/design/20_license_system.md — 5 Lapis Anti-Bajak
// Ref: docs/design/40_concurrency_strategy.md — BGProcessingTask + foreground check

import Foundation
import Observation

// MARK: - LicenseStatus

enum LicenseStatus: Equatable {
    case unknown            // Belum dicek
    case checking           // Sedang memvalidasi
    case valid              // Lisensi aktif dan valid
    case demo               // Demo mode — fitur terbatas, watermark di foto
    case expired(daysOverdue: Int)
    case invalid(reason: LicenseInvalidReason)
    case suspended          // Di-suspend admin via remote revocation
}

// MARK: - LicenseStore

@Observable
final class LicenseStore {

    // MARK: Dependency
    private let validator: any LicenseValidatorProtocol

    init(validator: (any LicenseValidatorProtocol)? = nil) {
        self.validator = validator ?? LicenseValidatorFactory.make()
    }

    // MARK: State
    var status: LicenseStatus = .unknown
    var expiresAt: Date?
    var lastHeartbeatAt: Date?
    var activationKey: String?   // Key yang terdaftar (bukan secret — aman di memori)

    // MARK: Computed

    /// Apakah lisensi valid untuk operasional penuh?
    var isValid: Bool {
        if case .valid = status { return true }
        return false
    }

    /// Apakah app dalam demo mode?
    var isDemoMode: Bool {
        if case .demo = status { return true }
        return false
    }

    /// Jumlah hari sampai lisensi expired (nil jika tidak ada expiry)
    var daysUntilExpiry: Int? {
        guard let expiry = expiresAt else { return nil }
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: expiry)
        return diff.day
    }

    /// Apakah perlu verifikasi internet sekarang? (>7 hari sejak heartbeat terakhir)
    var needsHeartbeat: Bool {
        guard let lastCheck = lastHeartbeatAt else { return true }
        let daysSinceCheck = Calendar.current.dateComponents([.day], from: lastCheck, to: Date()).day ?? 0
        return daysSinceCheck >= 7
    }

    /// Level notifikasi berdasarkan waktu kadaluarsa
    var expiryWarningLevel: ExpiryWarningLevel {
        guard let days = daysUntilExpiry else { return .none }
        switch days {
        case ...0: return .expired
        case 1: return .critical       // Banner merah
        case 2...7: return .warning    // Banner kuning
        case 8...30: return .notice    // Notifikasi diskret
        default: return .none
        }
    }

    // MARK: - Actions

    /// Validasi awal saat app launch — gunakan token dari Keychain
    @MainActor
    func validateOnLaunch() async {
        // 1. Cek jailbreak dulu (keamanan tertinggi)
        if JailbreakDetector.isJailbroken() {
            status = .invalid(reason: .checksumMismatch) // Gunakan sebagai proxy
            ErrorHandler.shared.handle(HaispaceError.jailbreakDetected, context: .duringSetup)
            return
        }

        // 2. Ambil token dari Keychain — fallback ke mock token jika belum terdaftar
        let token = KeychainHelper.getLicenseToken() ?? "HAISPACE-MOCK-LICENSE-TOKEN"

        // 3. Validasi token lokal (offline) via LicenseValidatorProtocol
        status = .checking
        do {
            let licenseInfo = try validator.validateOffline(token: token)
            expiresAt = licenseInfo.expiresAt
            activationKey = licenseInfo.activationKey
            status = licenseInfo.isExpired ? .expired(daysOverdue: licenseInfo.daysOverdue) : .valid

            // 4. Jika perlu heartbeat dan ada internet — lakukan di background
            if needsHeartbeat {
                Task {
                    await performHeartbeat()
                }
            }

            HaispaceLogger.info("License valid — expires: \(String(describing: expiresAt))", category: "license")
        } catch {
            HaispaceLogger.warning("License validation gagal: \(error.localizedDescription)", category: "license")
            status = .invalid(reason: .checksumMismatch)
        }
    }

    /// Heartbeat online ke server — perpanjang token 7 hari lagi
    @MainActor
    func performHeartbeat() async {
        guard let token = KeychainHelper.getLicenseToken() else { return }

        do {
            let renewedToken = try await withRetry(policy: .licenseCheck) {
                try await self.validator.heartbeat(token: token)
            }
            KeychainHelper.saveLicenseToken(renewedToken)
            lastHeartbeatAt = Date()
            HaispaceLogger.info("License heartbeat sukses", category: "license")
        } catch {
            HaispaceLogger.warning("License heartbeat gagal: \(error.localizedDescription)", category: "license")
            ErrorHandler.shared.handle(HaispaceError.licenseHeartbeatFailed, context: .background)
        }
    }

    /// Validasi hanya jika diperlukan (dipanggil saat app becomes active)
    @MainActor
    func validateIfNeeded() async {
        guard needsHeartbeat else { return }
        await performHeartbeat()
    }

    /// Aktivasi lisensi baru dengan activation key
    @MainActor
    func activate(key: String) async throws {
        status = .checking

        do {
            let token = try await validator.activate(
                key: key,
                deviceUUID: KeychainHelper.getOrCreateDeviceUUID()
            )
            KeychainHelper.saveLicenseToken(token)
            activationKey = key
            lastHeartbeatAt = Date()

            // Parse expiry dari token via validator
            let licenseInfo = try validator.validateOffline(token: token)
            expiresAt = licenseInfo.expiresAt
            status = .valid

            HaispaceLogger.info("License aktivasi berhasil: \(key)", category: "license")
        } catch {
            status = .invalid(reason: .keyNotFound)
            throw error
        }
    }
}

// MARK: - Expiry Warning Level

enum ExpiryWarningLevel {
    case none
    case notice     // 30 hari
    case warning    // 7 hari
    case critical   // 1 hari
    case expired
}

// MARK: - Jailbreak Detector

/// Deteksi tanda-tanda jailbreak
struct JailbreakDetector {
    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false // Selalu false di simulator
        #else
        // Cek keberadaan file sistem yang tidak normal
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]

        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }

        // Cek kemampuan menulis ke direktori terproteksi
        let testPath = "/private/haispace_jailbreak_test"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true // Berhasil menulis = jailbroken
        } catch {
            return false // Tidak bisa menulis = normal
        }
        #endif
    }
}

// MARK: - LicenseInfo
// Model ini dipakai oleh LicenseValidatorProtocol (lihat Services/LicenseValidatorProtocol.swift)

struct LicenseInfo {
    let activationKey: String
    let expiresAt: Date
    let isExpired: Bool
    let daysOverdue: Int
}
// LicenseValidator dan LicenseAPIClient (struct lama) telah dihapus.
// Gunakan LicenseValidatorProtocol + LicenseValidatorFactory sebagai penggantinya.
// Ref: Services/LicenseValidatorProtocol.swift
