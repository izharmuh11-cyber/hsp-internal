// KioskWatchdog.swift
// HaispaceBooths — Core/Recovery
//
// In-process Watchdog untuk mendeteksi & memulihkan kondisi abnormal kiosk.
//
// STRATEGI: In-process reset (bukan OS-level relaunch)
//   Alasan: Tidak perlu entitlement khusus Apple, lebih aman untuk kiosk public,
//           cukup untuk 99% skenario failure di lapangan.
//
// KONDISI YANG DIDETEKSI:
//   1. Stalled Session   → sesi aktif tanpa aktivitas > 10 menit
//   2. Orphaned Session  → file audit tanpa footer (indikasi crash sebelumnya)
//   3. Payment Confirmed → crash setelah bayar → WAJIB resume ke delivery
//
// TINDAKAN:
//   - Stalled tanpa payment  → reset ke landing (tidak ada kerugian finansial)
//   - Stalled dengan payment → log warning, tunggu operator atau beri opsi retry
//   - Orphaned post-payment  → auto-restore ke delivery screen
//   - Orphaned pre-payment   → reset ke landing
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar 2: Resilience
// Ref: docs/design/44_architecture_invariants.md — Invariant 20 (payment recovery)

import Foundation

// MARK: - WatchdogEvent

public enum WatchdogEvent: Sendable {
    case stalledSessionDetected(sessionId: String, inactiveMinutes: Double)
    case orphanedSessionFound(sessionId: String, hadPayment: Bool)
    case stalledSessionReset(sessionId: String)
    case sessionRestoredAfterCrash(sessionId: String)
}

// MARK: - WatchdogAction

public enum WatchdogAction: Sendable {
    case resetToLanding                     // Hapus sesi, kembali ke landing
    case restoreToDelivery(sessionId: String) // Resume sesi ke delivery screen
    case alertOperator(message: String)     // Eskalasi ke operator
}

// MARK: - KioskWatchdog

public actor KioskWatchdog {

    // MARK: - Configuration

    /// Batas waktu inaktif sebelum watchdog trigger (default: 10 menit)
    public static let stallThresholdMinutes: Double = 10

    /// Interval pengecekan watchdog (default: 60 detik)
    private static let checkIntervalSeconds: TimeInterval = 60

    // MARK: - State

    private var lastActivityTimestamp: Date = Date()
    private var currentSessionId: String?
    private var currentSessionHasPayment: Bool = false
    private var isRunning = false

    // MARK: - Callbacks (dipanggil di MainActor)

    /// Dipanggil saat watchdog membutuhkan aksi dari AppState / RootView
    public var onActionRequired: ((WatchdogAction) -> Void)?

    /// Log setiap event watchdog untuk audit
    public var onEvent: ((WatchdogEvent) -> Void)?

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNextCheck()
    }

    public func stop() {
        isRunning = false
    }

    // MARK: - Activity Tracking (dipanggil dari WorkflowOrchestrator)

    /// Reset timer inaktivitas — panggil setiap kali ada aktivitas pengguna
    public func recordActivity() {
        lastActivityTimestamp = Date()
    }

    /// Update session context
    public func sessionStarted(id: String) {
        currentSessionId = id
        currentSessionHasPayment = false
        lastActivityTimestamp = Date()
    }

    public func sessionEnded() {
        currentSessionId = nil
        currentSessionHasPayment = false
        lastActivityTimestamp = Date()
    }

    public func paymentConfirmed() {
        currentSessionHasPayment = true
    }

    // MARK: - Orphaned Session Check (dipanggil saat launch)

    /// Cek sesi orphaned dari run sebelumnya — panggil dari HaispaceBoothsApp.onAppear
    public func checkForOrphanedSessions(decisions: [OrphanedSessionDecision]) {
        for decision in decisions {
            let sessionId = decision.sessionId

            // Invariant 20: session dengan payment WAJIB direstore
            if decision.requiresResume {
                onEvent?(.orphanedSessionFound(sessionId: sessionId, hadPayment: true))
                Task { @MainActor [weak self] in
                    self?.onActionRequired?(.restoreToDelivery(sessionId: sessionId))
                }
            } else {
                onEvent?(.orphanedSessionFound(sessionId: sessionId, hadPayment: false))
                // Pre-payment crash → reset (tidak ada kerugian finansial)
                // AppState sudah handle ini via orphanedSessionDecisions
            }
        }
    }

    // MARK: - Private: Periodic Check

    private func scheduleNextCheck() {
        Task {
            try? await Task.sleep(
                nanoseconds: UInt64(Self.checkIntervalSeconds * 1_000_000_000)
            )
            await performCheck()
            if isRunning { scheduleNextCheck() }
        }
    }

    private func performCheck() async {
        guard let sessionId = currentSessionId else { return }

        let inactiveMinutes = Date().timeIntervalSince(lastActivityTimestamp) / 60

        guard inactiveMinutes >= Self.stallThresholdMinutes else { return }

        onEvent?(.stalledSessionDetected(
            sessionId: sessionId,
            inactiveMinutes: inactiveMinutes
        ))

        if currentSessionHasPayment {
            // Sesi dengan payment — jangan reset otomatis, alert operator
            let message = "Sesi \(sessionId.prefix(8)) idle \(Int(inactiveMinutes)) menit setelah pembayaran. Tinjau segera."
            Task { @MainActor [weak self] in
                self?.onActionRequired?(.alertOperator(message: message))
            }
        } else {
            // Tidak ada payment — aman untuk reset ke landing
            onEvent?(.stalledSessionReset(sessionId: sessionId))
            sessionEnded()
            Task { @MainActor [weak self] in
                self?.onActionRequired?(.resetToLanding)
            }
        }
    }
}

// MARK: - WatchdogMetrics (untuk MissionControlView)

public struct WatchdogMetrics: Sendable {
    public let totalResetsToday: Int
    public let totalCrashRecoveriesThisWeek: Int
    public let lastResetAt: Date?
    public let isCurrentSessionStalled: Bool

    public static let empty = WatchdogMetrics(
        totalResetsToday: 0,
        totalCrashRecoveriesThisWeek: 0,
        lastResetAt: nil,
        isCurrentSessionStalled: false
    )
}
