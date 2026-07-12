// OperatorStore.swift
// HaispaceBooths — Core/State
//
// Store untuk operator yang sedang aktif di lapangan.
// Mengelola Mission Control visibility, Personal App PIN, dan operator shift swap.
//
// Ref: docs/design/39_state_architecture.md — OperatorStore
// Ref: docs/design/30_authentication.md — Personal App PIN
// Ref: docs/design/15_operator_panel.md — Mission Control

import Foundation
import Observation

// MARK: - OperatorStore

@Observable
final class OperatorStore {

    // MARK: State

    /// Operator yang sedang aktif di shift ini
    var currentOperator: HaispaceUser?

    /// Apakah Mission Control overlay sedang ditampilkan?
    var isMissionControlVisible: Bool = false
    
    /// Shortcut untuk menampilkan UI Pairing langsung (misal saat terputus di LandingView)
    var isPairingSetupVisible: Bool = false

    /// Status PIN verification untuk Mission Control
    var pinStatus: PINStatus = .notSet

    /// Apakah PIN sedang diverifikasi (menampilkan PIN entry screen)?
    var isVerifyingPIN: Bool = false

    /// Pesan status untuk Mission Control
    var operatorAlerts: [OperatorAlert] = []

    // MARK: Computed

    var isOperatorActive: Bool { currentOperator != nil }
    var hasPINSet: Bool { KeychainHelper.readData(for: .operatorPIN) != nil }

    var hasUnacknowledgedAlerts: Bool { !operatorAlerts.isEmpty }
    var criticalAlertCount: Int {
        operatorAlerts.filter { $0.level == .critical }.count
    }

    // MARK: - PIN Management

    /// Set Personal App PIN (setelah login pertama kali)
    @MainActor
    func setupPIN(_ pin: String) -> Bool {
        guard pin.count == 4 || pin.count == 6 else {
            HaispaceLogger.warning("PIN harus 4 atau 6 digit", category: "operator")
            return false
        }
        let success = KeychainHelper.saveOperatorPIN(pin)
        if success {
            pinStatus = .set
            HaispaceLogger.info("Operator PIN berhasil di-set", category: "operator")
        }
        return success
    }

    /// Verifikasi PIN untuk membuka Mission Control
    @MainActor
    func verifyPIN(_ inputPIN: String) -> Bool {
        let isValid = KeychainHelper.verifyOperatorPIN(inputPIN)
        if isValid {
            pinStatus = .verified
            isMissionControlVisible = true
            isVerifyingPIN = false
            HaispaceLogger.info("Mission Control dibuka via PIN", category: "operator")
        } else {
            HaispaceLogger.warning("PIN salah — akses Mission Control ditolak", category: "operator")
        }
        return isValid
    }

    // MARK: - Mission Control

    /// Tampilkan Mission Control (membutuhkan PIN verification)
    @MainActor
    func requestMissionControl() {
        if hasPINSet {
            isVerifyingPIN = true
        } else {
            // PIN belum di-set — langsung buka (akan diminta set PIN setelahnya)
            isMissionControlVisible = true
        }
    }

    /// Tutup Mission Control
    @MainActor
    func dismissMissionControl() {
        isMissionControlVisible = false
        isVerifyingPIN = false
        pinStatus = .set // Reset ke set state setelah dismiss
    }

    // MARK: - Alerts

    /// Tambahkan alert untuk operator di Mission Control
    @MainActor
    func addAlert(_ alert: OperatorAlert) {
        // Hindari duplikasi
        if !operatorAlerts.contains(where: { $0.id == alert.id }) {
            operatorAlerts.append(alert)
            HaispaceLogger.warning("Operator alert: \(alert.title)", category: "operator")
        }
    }

    /// Dismiss alert yang sudah diakui operator
    @MainActor
    func dismissAlert(_ alert: OperatorAlert) {
        operatorAlerts.removeAll { $0.id == alert.id }
    }

    // MARK: - Shift Management

    /// Operator logout (tanpa menghentikan background upload)
    @MainActor
    func swapOperator() {
        HaispaceLogger.info("Shift swap — operator logout: \(currentOperator?.email ?? "?")", category: "operator")
        currentOperator = nil
        isMissionControlVisible = false
        isVerifyingPIN = false
        pinStatus = .notSet
        operatorAlerts.removeAll()
        KeychainHelper.deleteOperatorPIN()
        // ⚠️ TIDAK menghapus auth token — background upload tetap berjalan
    }
}

// MARK: - PINStatus

enum PINStatus {
    case notSet
    case set
    case verified
}

// MARK: - OperatorAlert

/// Alert yang ditampilkan di Mission Control
struct OperatorAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let level: AlertLevel
    let createdAt: Date

    init(title: String, message: String, level: AlertLevel) {
        self.id = UUID().uuidString
        self.title = title
        self.message = message
        self.level = level
        self.createdAt = Date()
    }

    /// Buat dari HaispaceError
    static func from(_ error: HaispaceError) -> OperatorAlert {
        OperatorAlert(
            title: error.errorDescription ?? "Error",
            message: error.recoverySuggestion ?? "Periksa status perangkat",
            level: .warning
        )
    }
}
