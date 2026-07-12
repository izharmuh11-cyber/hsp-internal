// RetryPolicy.swift
// HaispaceBooths — Core/Retry
//
// Pattern retry yang konsisten untuk semua operasi yang bisa di-retry.
// Gunakan withRetry() — jangan tulis retry loop sendiri.
//
// Ref: docs/design/41_error_handling.md — RetryPolicy

import Foundation

// MARK: - RetryPolicy

/// Konfigurasi policy retry untuk operasi async yang bisa gagal.
struct RetryPolicy {
    let maxAttempts: Int
    let delay: Duration
    let backoff: BackoffStrategy

    enum BackoffStrategy {
        case constant       // Delay sama tiap retry
        case exponential    // Delay berlipat ganda tiap retry (2x, 4x, 8x...)
    }

    // MARK: - Preset Policies

    /// Pengiriman pesan P2P — 3 percobaan, delay konstan 1 detik
    static let p2pSend = RetryPolicy(
        maxAttempts: 3,
        delay: .seconds(1),
        backoff: .constant
    )

    /// Upload foto ke cloud — 5 percobaan, backoff exponential
    static let cloudUpload = RetryPolicy(
        maxAttempts: 5,
        delay: .seconds(2),
        backoff: .exponential
    )

    /// Validasi lisensi ke server — 3 percobaan, backoff exponential
    static let licenseCheck = RetryPolicy(
        maxAttempts: 3,
        delay: .seconds(10),
        backoff: .exponential
    )

    /// Login API — 2 percobaan, delay konstan 2 detik
    static let apiLogin = RetryPolicy(
        maxAttempts: 2,
        delay: .seconds(2),
        backoff: .constant
    )

    /// Transfer foto full quality — 3 percobaan, delay konstan 2 detik
    static let photoTransfer = RetryPolicy(
        maxAttempts: 3,
        delay: .seconds(2),
        backoff: .constant
    )
}

// MARK: - Generic Retry Function

/// Fungsi retry generik yang digunakan untuk semua operasi yang bisa di-retry.
/// Jangan tulis retry loop sendiri — gunakan ini.
///
/// Contoh penggunaan:
/// ```swift
/// func sendThumbnail(data: Data) async throws {
///     try await withRetry(policy: .p2pSend) {
///         try await transport.send(.photoPreview(data))
///     }
/// }
/// ```
func withRetry<T>(
    policy: RetryPolicy,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    var currentDelay = policy.delay

    for attempt in 1...policy.maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            guard attempt < policy.maxAttempts else { break }

            // Log percobaan gagal (DEBUG only)
            HaispaceLogger.debug("Retry attempt \(attempt)/\(policy.maxAttempts) failed: \(error.localizedDescription)")

            // Tunggu sebelum percobaan berikutnya
            try? await Task.sleep(for: currentDelay)

            // Update delay jika exponential backoff
            if policy.backoff == .exponential {
                let currentSeconds = currentDelay.components.seconds
                currentDelay = .seconds(currentSeconds * 2)
            }
        }
    }

    // Semua percobaan habis — throw error terakhir
    throw lastError ?? HaispaceError.unknown(
        underlying: NSError(
            domain: "id.haispaceproject.booth.retry",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Semua percobaan retry habis"]
        )
    )
}

// MARK: - Duration Extension Helper

extension Duration {
    /// Komponen detik dari Duration (untuk exponential backoff calculation)
    var totalSeconds: Int64 {
        let (seconds, _) = components
        return seconds
    }
}
