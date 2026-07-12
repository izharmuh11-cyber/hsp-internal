// ErrorPresenter.swift
// HaispaceBooths — Core/Error
//
// Presenter yang menerjemahkan ErrorRecoveryStrategy ke UI actions.
// Semua presentasi UI dari error harus melalui sini.
//
// Ref: docs/design/41_error_handling.md — Layer 3: UI Presentation

import Foundation
import SwiftUI

// MARK: - Error Presenter

/// @MainActor: semua UI actions harus di main thread
@MainActor
struct ErrorPresenter {

    // MARK: - Operator-Facing Presentation

    /// Tampilkan error di Mission Control (tidak terlihat oleh tamu)
    static func presentToOperator(_ error: HaispaceError) {
        // TODO: Fase 2 — implementasi MissionControlOverlay
        // MissionControlOverlay.showError(
        //     title: error.errorDescription ?? "Error",
        //     suggestion: error.recoverySuggestion,
        //     level: .warning
        // )
        HaispaceLogger.warning(
            "OPERATOR ALERT: \(error.errorDescription ?? error.localizedDescription)",
            category: "operator_ui"
        )
    }

    // MARK: - Guest-Facing Presentation

    /// Tampilkan error fullscreen untuk tamu
    static func presentToGuest(_ error: HaispaceError, canDismiss: Bool) {
        // TODO: Fase 2 — implementasi KioskAlertView
        // KioskAlertView.show(
        //     message: error.errorDescription ?? "Terjadi kesalahan",
        //     canDismiss: canDismiss
        // )
        HaispaceLogger.warning(
            "GUEST UI: \(error.errorDescription ?? error.localizedDescription) (canDismiss: \(canDismiss))",
            category: "guest_ui"
        )
    }

    // MARK: - Degraded Mode Banner

    /// Tampilkan banner diskret — app tetap jalan tapi fitur dikurangi
    static func presentDegradedMode(message: String) {
        // TODO: Fase 2 — implementasi ToastBanner
        // ToastBanner.show(message: message, style: .warning, duration: 5)
        HaispaceLogger.warning("DEGRADED MODE: \(message)", category: "degraded")
    }

    // MARK: - Fatal Error

    /// Tampilkan layar error permanen — app tidak bisa lanjut
    /// ⚠️ ATURAN: Tidak boleh dipanggil saat sesi tamu sedang aktif!
    static func presentFatal(_ error: HaispaceError) {
        // TODO: Fase 2 — implementasi FatalErrorScreen
        // FatalErrorScreen.show(error: error)
        HaispaceLogger.critical(
            "FATAL: \(error.errorDescription ?? error.localizedDescription)",
            category: "fatal"
        )
    }
}

// MARK: - Toast Banner Configuration (Placeholder Types)

/// Tipe style untuk toast banner
enum ToastStyle {
    case info
    case warning
    case error
    case success
}

/// Level severity untuk Mission Control alert card
enum AlertLevel {
    case info
    case warning
    case error
    case critical
}
