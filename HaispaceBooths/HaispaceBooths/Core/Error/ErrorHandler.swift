// ErrorHandler.swift
// HaispaceBooths — Core/Error
//
// Satu-satunya titik masuk untuk semua error handling.
// Semua error HARUS melalui ErrorHandler.shared.handle() — jangan handle sendiri.
//
// Ref: docs/design/41_error_handling.md — ErrorHandler Orchestrator

import Foundation
import Observation

// MARK: - ErrorHandler

/// Orchestrator utama penanganan error.
/// @MainActor karena semua UI state changes harus di main thread.
@MainActor
@Observable
final class ErrorHandler {

    // MARK: Singleton
    static let shared = ErrorHandler()
    private init() {}

    // MARK: State

    /// Semua error aktif yang perlu direview operator di Mission Control
    private(set) var activeErrors: [HaispaceError] = []

    /// Error terakhir yang perlu ditampilkan di layar tamu
    private(set) var guestFacingError: HaispaceError?

    // MARK: - Handle

    /// Entry point utama untuk semua error.
    /// 1. Log ke OSLog + local file
    /// 2. Kirim ke crash reporter (background)
    /// 3. Execute recovery strategy
    func handle(
        _ error: Error,
        context: ErrorContext = .background,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Wrap ke HaispaceError jika belum
        let haispaceError: HaispaceError
        if let he = error as? HaispaceError {
            haispaceError = he
        } else {
            haispaceError = .unknown(underlying: error)
        }

        // 1. Selalu log dulu
        HaispaceLogger.error(haispaceError, file: file, function: function, line: line)

        // 2. Kirim ke crash reporter di background (fire-and-forget)
        Task.detached(priority: .background) {
            await CrashReporter.report(haispaceError, context: context)
        }

        // 3. Execute recovery strategy
        executeRecovery(for: haispaceError, context: context)
    }

    // MARK: - Dismiss

    /// Dismiss error dari daftar aktif (setelah operator acknowledge)
    func dismiss(_ error: HaispaceError) {
        activeErrors.removeAll { $0 == error }
        if guestFacingError == error {
            guestFacingError = nil
        }
    }

    /// Dismiss semua error (misalnya setelah sesi selesai)
    func dismissAll() {
        activeErrors.removeAll()
        guestFacingError = nil
    }

    // MARK: - Private

    private func executeRecovery(for error: HaispaceError, context: ErrorContext) {
        switch error.recoveryStrategy {

        case .autoRetry:
            // Retry logic dihandle di call site via withRetry()
            // ErrorHandler hanya mencatat — tidak ada UI
            HaispaceLogger.debug("Auto retry akan dihandle di call site untuk: \(error)")

        case .reconnect:
            // Trigger P2P reconnect
            Task {
                await P2PReconnectOrchestrator.shared.attemptReconnect()
            }

        case .requireOperatorAction:
            // Tambahkan ke daftar error aktif (tampil di Mission Control)
            if !activeErrors.contains(error) {
                activeErrors.append(error)
            }
            ErrorPresenter.presentToOperator(error)

        case .requireUserAction(let canDismiss):
            // Tampilkan ke tamu
            guestFacingError = error
            ErrorPresenter.presentToGuest(error, canDismiss: canDismiss)

        case .degradedMode(let message):
            // Tampilkan banner diskret, app tetap jalan
            ErrorPresenter.presentDegradedMode(message: message)

        case .fatal:
            // Tampilkan layar error permanen
            // ⚠️ ATURAN: Fatal error TIDAK BOLEH muncul saat sesi tamu aktif
            activeErrors.append(error)
            ErrorPresenter.presentFatal(error)

        case .silentLog:
            // Sudah di-log di atas — tidak ada UI
            break
        }
    }
}

// MARK: - P2P Reconnect Orchestrator (Placeholder)

/// Placeholder untuk Fase 1 — akan diimplementasikan saat P2PManager dibuat
actor P2PReconnectOrchestrator {
    static let shared = P2PReconnectOrchestrator()
    private init() {}

    func attemptReconnect() async {
        HaispaceLogger.info("P2P reconnect attempt triggered", category: "p2p")
        // TODO: Fase 1 — implementasi reconnect via P2PManager
    }
}

// MARK: - Crash Reporter (Placeholder)

/// Placeholder untuk reporting ke crash analytics service
struct CrashReporter {
    static func report(_ error: HaispaceError, context: ErrorContext) async {
        // TODO: Fase 3 — implementasi pengiriman ke Sentry/Crashlytics/custom backend
        HaispaceLogger.debug("Crash report queued: \(error) — context: \(context)")
    }
}
