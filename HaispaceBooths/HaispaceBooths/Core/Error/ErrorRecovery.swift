// ErrorRecovery.swift
// HaispaceBooths — Core/Error
//
// Strategy recovery untuk setiap jenis error.
// Jangan handle semua error dengan alert — setiap error punya strategy berbeda.
//
// Ref: docs/design/41_error_handling.md — Layer 2

import Foundation

// MARK: - Recovery Strategy Enum

enum ErrorRecoveryStrategy {
    /// Sistem coba lagi otomatis tanpa gangguan user
    case autoRetry(maxAttempts: Int, delay: Duration)
    /// Sistem coba reconnect P2P otomatis
    case reconnect(maxAttempts: Int, delay: Duration)
    /// Tampilkan di Mission Control, bukan di layar tamu
    case requireOperatorAction
    /// Tampilkan di layar tamu dengan instruksi jelas
    case requireUserAction(canDismiss: Bool)
    /// App tetap jalan, fitur tertentu dinonaktifkan
    case degradedMode(message: String)
    /// Catat di log, jangan ganggu user
    case silentLog
    /// App tidak bisa lanjut — harus restart atau kontak admin
    case fatal
}

// MARK: - ErrorRecoveryStrategy Equatable

extension ErrorRecoveryStrategy: Equatable {
    static func == (lhs: ErrorRecoveryStrategy, rhs: ErrorRecoveryStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.autoRetry(let a1, _), .autoRetry(let b1, _)): return a1 == b1
        case (.reconnect(let a1, _), .reconnect(let b1, _)): return a1 == b1
        case (.requireOperatorAction, .requireOperatorAction): return true
        case (.requireUserAction(let a), .requireUserAction(let b)): return a == b
        case (.degradedMode(let a), .degradedMode(let b)): return a == b
        case (.silentLog, .silentLog): return true
        case (.fatal, .fatal): return true
        default: return false
        }
    }
}

// MARK: - HaispaceError Recovery Strategy

extension HaispaceError {

    /// Strategy yang menentukan bagaimana error ini ditangani.
    /// Dipanggil oleh ErrorHandler untuk menentukan tindakan selanjutnya.
    var recoveryStrategy: ErrorRecoveryStrategy {
        switch self {

        // ── AUTO RETRY ─────────────────────────────────────────────────────────
        // Sistem coba lagi tanpa ganggu user
        case .p2pMessageSendFailed,
             .thumbnailCompressionFailed,
             .fullQualityTransferFailed,
             .uploadFailed:
            return .autoRetry(maxAttempts: 3, delay: .seconds(2))

        // ── RECONNECT ──────────────────────────────────────────────────────────
        // Sistem coba reconnect P2P otomatis (lebih agresif dari autoRetry)
        case .p2pConnectionLost:
            return .reconnect(maxAttempts: 5, delay: .seconds(3))

        case .p2pConnectionFailed:
            return .reconnect(maxAttempts: 3, delay: .seconds(5))

        // ── OPERATOR ACTION ────────────────────────────────────────────────────
        // Tampilkan di Mission Control — operator yang harus tindak lanjuti
        case .p2pReconnectExhausted,
             .printerNotFound,
             .printerJobFailed,
             .storageInsufficient,
             .licenseDeviceLimitReached:
            return .requireOperatorAction

        // ── USER ACTION ────────────────────────────────────────────────────────
        // Tampilkan di layar tamu — tamu yang harus tindak lanjuti
        case .paymentTimeout:
            return .requireUserAction(canDismiss: true)

        case .qrisGenerationFailed:
            return .requireUserAction(canDismiss: true)

        // ── DEGRADED MODE ──────────────────────────────────────────────────────
        // App tetap jalan, fitur dikurangi
        case .thermalThrottling:
            return .degradedMode(message: "Preview diturunkan ke 30fps karena suhu perangkat tinggi")

        case .networkUnavailable:
            return .degradedMode(message: "Mode offline aktif — upload akan dilakukan saat internet tersedia")

        // ── FATAL ──────────────────────────────────────────────────────────────
        // App tidak bisa lanjut — jangan tampilkan saat sesi tamu aktif
        case .licenseInvalid,
             .jailbreakDetected,
             .licenseExpired,
             .authTokenInvalid:
            return .fatal

        // ── SILENT LOG ─────────────────────────────────────────────────────────
        // Catat ke log, jangan ganggu siapapun
        case .licenseHeartbeatFailed,
             .apiResponseInvalid,
             .authTokenExpired:
            return .silentLog

        // Default — catat tapi jangan ganggu
        default:
            return .silentLog
        }
    }
}

// MARK: - Error Context

/// Konteks di mana error terjadi — untuk logging dan analytics
enum ErrorContext {
    case duringSession(sessionId: String)
    case duringSetup
    case duringPayment
    case duringDelivery
    case background
}
