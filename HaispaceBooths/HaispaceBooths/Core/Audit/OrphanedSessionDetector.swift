// OrphanedSessionDetector.swift
// HaispaceBooths — Core/Audit
//
// Deteksi sesi yang tidak selesai (orphaned) dan menghasilkan rekomendasi recovery.
//
// PRINSIP (Principal Engineer Review):
// Detector hanya melakukan DUA hal:
//   1. Mendeteksi kondisi dari audit trail
//   2. Menghasilkan rekomendasi (OrphanedSessionDecision)
//
// Keputusan akhir dan eksekusi tetap di WorkflowOrchestrator.
// Detector TIDAK boleh memodifikasi audit trail, mengubah state, atau
// memanggil capability apapun.
//
// Ref: docs/design/ADR-002_operational_resilience.md — Pilar 2: Recoverability
// Ref: docs/design/44_architecture_invariants.md — Invariant 20

import Foundation

// MARK: - OrphanedSessionDecision

/// Rekomendasi recovery untuk satu orphaned session.
/// Keputusan akhir ada di WorkflowOrchestrator — bukan di Detector.
public enum OrphanedSessionDecision: Sendable {

    /// Sesi memiliki paymentConfirmed — foto sudah dibayar, WAJIB resume ke delivery.
    /// Membawa output reference dari audit trail untuk melanjutkan pengiriman.
    case resumeToDelivery(sessionId: String, outputReference: String, startedAt: Date)

    /// Sesi dalam state payment menunggu konfirmasi.
    /// Tidak tahu apakah customer sudah bayar — operator harus verifikasi manual.
    case awaitOperatorVerification(sessionId: String, waitingSince: Date)

    /// Sesi belum ada transaksi finansial — aman untuk ditutup dan diabaikan.
    /// Tidak ada aksi yang diperlukan dari operator.
    case safeToAbandon(sessionId: String, lastStage: WorkflowStage)

    // MARK: - Convenience

    public var sessionId: String {
        switch self {
        case .resumeToDelivery(let id, _, _): return id
        case .awaitOperatorVerification(let id, _): return id
        case .safeToAbandon(let id, _): return id
        }
    }

    public var requiresOperatorAttention: Bool {
        switch self {
        case .resumeToDelivery, .awaitOperatorVerification: return true
        case .safeToAbandon: return false
        }
    }
}

// MARK: - OrphanedSessionDetector

/// Pure detector — hanya membaca audit trail dan menghasilkan keputusan.
/// Tidak menulis ke disk, tidak mengubah state, tidak memanggil capability.
public enum OrphanedSessionDetector {

    /// Deteksi semua orphaned sessions dan kembalikan rekomendasi.
    /// Dipanggil dari AppState.setup() — sebelum isAppReady = true.
    public static func detect() -> [OrphanedSessionDecision] {
        let orphans = SessionAuditTrail.findOrphanedSessions()

        guard !orphans.isEmpty else {
            HaispaceLogger.info("OrphanedSessionDetector: tidak ada orphaned session", category: "recovery")
            return []
        }

        HaispaceLogger.warning(
            "OrphanedSessionDetector: \(orphans.count) orphaned session(s) ditemukan",
            category: "recovery"
        )

        return orphans.map { analyze(record: $0) }
    }

    // MARK: - Analysis (Pure Function — no side effects)

    /// Analisis satu record dan kembalikan rekomendasi.
    /// Ini adalah pure function: sama input → sama output, tidak ada efek samping.
    static func analyze(record: AuditTrailRecord) -> OrphanedSessionDecision {
        let sessionId = record.sessionId

        HaispaceLogger.warning(
            "Analyzing orphan: \(sessionId) — lastStage: \(record.lastStage) — hasPayment: \(record.hasFinancialTransaction)",
            category: "recovery"
        )

        // CASE 1: Payment sudah dikonfirmasi — foto sudah dibayar
        // Invariant 20: WAJIB resume, tidak boleh abandon
        if record.hasFinancialTransaction {
            let outputRef = record.deliveryOutputReference ?? ""
            return .resumeToDelivery(
                sessionId: sessionId,
                outputReference: outputRef,
                startedAt: record.startedAt
            )
        }

        // CASE 2: Sesi berada di state payment/exporting — status pembayaran tidak pasti
        switch record.lastStage {
        case .paymentRequested, .exporting:
            return .awaitOperatorVerification(
                sessionId: sessionId,
                waitingSince: record.startedAt
            )

        // CASE 3: Belum ada transaksi finansial — aman untuk diabaikan
        case .landing, .guestRegistration, .packageSelection,
             .templateSelection, .capturing, .editingPreview,
             .paymentConfirmed, .deliveryDispatch,
             .sessionCompleted, .recoveryMode:
            return .safeToAbandon(
                sessionId: sessionId,
                lastStage: record.lastStage
            )
        }
    }
}
