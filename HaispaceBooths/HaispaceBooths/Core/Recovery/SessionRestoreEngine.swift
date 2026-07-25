// SessionRestoreEngine.swift
// HaispaceBooths — Core/Recovery
//
// Menentukan tindakan recovery yang tepat untuk setiap orphaned session.
//
// KONTRAK (Pure Function — tidak ada side effects):
//   Input:  [OrphanedSessionDecision] dari OrphanedSessionDetector
//   Output: [SessionRestoreDecision] berisi action & alasan
//
// DECISION TREE:
//
//   Orphaned Session
//       │
//       ├── hasFinancialTransaction == true (paymentConfirmed di audit trail)
//       │       │
//       │       ├── deliveryCompleted ada → mark complete, reset to landing
//       │       └── deliveryCompleted tidak ada → RESTORE to delivery screen ⚠️
//       │
//       └── hasFinancialTransaction == false
//               │
//               └── Reset to landing (aman, tidak ada kerugian finansial)
//
// Ref: docs/design/44_architecture_invariants.md — Invariant 20
// Ref: docs/design/ADR-002_operational_resilience.md

import Foundation

// MARK: - SessionRestoreDecision

public struct SessionRestoreDecision: Sendable {
    public let sessionId: String
    public let action: RestoreAction
    public let reason: String
    public let auditSummary: AuditSummary?

    public enum RestoreAction: Sendable {
        case restoreToDelivery      // Lanjutkan ke delivery (Invariant 20)
        case resetToLanding         // Reset bersih ke landing
        case markCompleteAndReset   // Delivery sudah selesai — cleanup & reset
    }
}

// MARK: - AuditSummary (simplified read result)

public struct AuditSummary: Sendable {
    public let sessionId: String
    public let hasFinancialTransaction: Bool
    public let hasDeliveryCompleted: Bool
    public let lastStage: String?
}

// MARK: - SessionRestoreEngine

public struct SessionRestoreEngine {

    // MARK: - Public API

    /// Analisis orphaned sessions dan tentukan action yang tepat (pure function)
    public func decide(for decisions: [OrphanedSessionDecision]) -> [SessionRestoreDecision] {
        decisions.map { orphan in
            let auditSummary = readAuditSummary(sessionId: orphan.sessionId)
            return decideAction(for: orphan, auditSummary: auditSummary)
        }
    }

    // MARK: - Private: Decision Logic

    private func decideAction(
        for orphan: OrphanedSessionDecision,
        auditSummary: AuditSummary?
    ) -> SessionRestoreDecision {

        let sessionId = orphan.sessionId

        // Tidak ada audit trail sama sekali → reset bersih
        guard let summary = auditSummary else {
            return SessionRestoreDecision(
                sessionId: sessionId,
                action: .resetToLanding,
                reason: "No audit trail found — safe to reset",
                auditSummary: nil
            )
        }

        // Ada transaksi finansial (paymentConfirmed)
        if summary.hasFinancialTransaction {
            if summary.hasDeliveryCompleted {
                // Delivery sudah selesai sebelum crash — cleanup aman
                return SessionRestoreDecision(
                    sessionId: sessionId,
                    action: .markCompleteAndReset,
                    reason: "Payment confirmed & delivery completed — cleanup and reset",
                    auditSummary: summary
                )
            } else {
                // INVARIANT 20: Wajib restore ke delivery
                return SessionRestoreDecision(
                    sessionId: sessionId,
                    action: .restoreToDelivery,
                    reason: "Payment confirmed but delivery not completed — MUST restore",
                    auditSummary: summary
                )
            }
        }

        // Tidak ada transaksi finansial → reset bersih
        return SessionRestoreDecision(
            sessionId: sessionId,
            action: .resetToLanding,
            reason: "No financial transaction — safe to reset to landing",
            auditSummary: summary
        )
    }

    // MARK: - Private: Audit Read

    private func readAuditSummary(sessionId: String) -> AuditSummary? {
        guard let record = SessionAuditTrail.read(sessionId: sessionId) else {
            return nil
        }

        return AuditSummary(
            sessionId: sessionId,
            hasFinancialTransaction: record.hasFinancialTransaction,
            hasDeliveryCompleted: record.events.contains(where: { $0.eventType == .deliveryCompleted }),
            lastStage: record.events.last?.stage.rawValue
        )
    }
}

// MARK: - OrphanedSessionDecision Extension

extension OrphanedSessionDecision {
    /// Apakah sesi ini harus di-resume (Invariant 20)
    var requiresResume: Bool {
        // Delegasikan ke SessionRestoreEngine untuk keputusan yang konsisten
        let engine = SessionRestoreEngine()
        let decisions = engine.decide(for: [self])
        return decisions.first?.action == .restoreToDelivery
    }
}
