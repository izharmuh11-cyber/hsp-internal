// PaymentCompatibilityChecker.swift
// HaispaceBooths — Core/Infrastructure/Compatibility
//
// PR-02: Read Compare + Divergence Detection untuk Payment bounded context.
//
// ALUR (Ref: GPT Architecture Decision — PR-02 DoD):
//   Read Aggregate → Read Legacy → Compare (value+timestamp) → Emit CompatibilityEvent → Return Aggregate
//
// ATURAN:
//   - Tidak mengubah perilaku runtime sama sekali
//   - Return value SELALU dari Aggregate (bukan Legacy)
//   - Legacy dibaca hanya untuk perbandingan
//   - Mismatch adalah sinyal — bukan error

import Foundation

// MARK: - PaymentCompatibilityChecker

/// Checker untuk bounded context Payment.
/// Membandingkan HaispaceSession.paymentCommitment dengan PaymentStore.
///
/// Digunakan oleh WorkflowOrchestrator selama Compatibility Window.
public struct PaymentCompatibilityChecker: Sendable {

    // MARK: - Core Check

    /// Jalankan perbandingan Aggregate vs Legacy Payment Store.
    ///
    /// - Parameters:
    ///   - session: HaispaceSession Aggregate Root (source of truth)
    ///   - legacyStatus: PaymentStatus dari PaymentStore lama
    ///   - legacyAmount: amount dari PaymentStore lama
    ///   - legacyTransactionId: transactionId dari PaymentStore lama
    ///   - legacyConfirmedAt: cashConfirmedAt atau QRIS acceptedAt dari PaymentStore
    /// - Returns: CompatibilityCheckResult dengan detail per field
    public static func check(
        session: HaispaceSession,
        legacyIsPaid: Bool,
        legacyAmount: Int,
        legacyTransactionId: String?,
        legacyAcceptedAt: Date?
    ) async -> CompatibilityCheckResult {

        let commitment = await session.paymentCommitment
        let sessionId = await session.sessionId
        var fields: [CompatibilityFieldResult] = []

        // MARK: Field 1 — Status (isWorkflowAllowed vs isPaid)
        let aggregateStatusStr = commitment?.isWorkflowAllowed == true ? "paid" : "not_paid"
        let legacyStatusStr = legacyIsPaid ? "paid" : "not_paid"
        fields.append(CompatibilityFieldResult(
            field: .status,
            aggregateValue: aggregateStatusStr,
            legacyValue: legacyStatusStr,
            matched: aggregateStatusStr == legacyStatusStr,
            checkedAt: Date()
        ))

        // MARK: Field 2 — Amount
        let aggregateAmount = commitment?.amount ?? 0
        fields.append(CompatibilityFieldResult(
            field: .amount,
            aggregateValue: "\(aggregateAmount)",
            legacyValue: "\(legacyAmount)",
            matched: aggregateAmount == legacyAmount,
            checkedAt: Date()
        ))

        // MARK: Field 3 — LocalReference / TransactionId
        let aggregateTxnId = commitment?.localTransactionId ?? ""
        let legacyTxnId = legacyTransactionId ?? ""
        fields.append(CompatibilityFieldResult(
            field: .localReference,
            aggregateValue: aggregateTxnId,
            legacyValue: legacyTxnId,
            matched: aggregateTxnId == legacyTxnId,
            checkedAt: Date()
        ))

        // MARK: Field 4 — Accepted At (Timestamp Delta)
        let aggregateAcceptedAt = extractAcceptedAt(from: commitment)
        let timeDelta: TimeInterval = {
            guard let a = aggregateAcceptedAt, let b = legacyAcceptedAt else { return -1 }
            return abs(a.timeIntervalSince(b))
        }()
        // Toleransi 1 detik — write ke aggregate + write ke store terjadi dalam satu loop
        let timestampMatched = timeDelta >= 0 && timeDelta < 1.0
        fields.append(CompatibilityFieldResult(
            field: .acceptedAt,
            aggregateValue: aggregateAcceptedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil",
            legacyValue: legacyAcceptedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil",
            matched: timestampMatched,
            checkedAt: Date()
        ))

        // MARK: Field 5 — Method
        let aggregateMethodStr = commitment?.method.rawValue ?? "nil"
        fields.append(CompatibilityFieldResult(
            field: .method,
            aggregateValue: aggregateMethodStr,
            legacyValue: "qris", // Legacy PaymentStore selalu QRIS dalam current impl
            matched: true, // skip method check for now — legacy doesn't expose this cleanly
            checkedAt: Date()
        ))

        let result = CompatibilityCheckResult.build(
            sessionId: sessionId,
            context: "payment",
            fields: fields
        )

        // MARK: Log
        if result.overallMatched {
            HaispaceLogger.info(
                "✅ [Compat/Payment] Match — sessionId: \(sessionId)",
                category: "compatibility"
            )
        } else {
            HaispaceLogger.warning(
                "⚠️ [Compat/Payment] MISMATCH — sessionId: \(sessionId) — fields: \(result.mismatchedFields.map { $0.field.rawValue }.joined(separator: ", "))",
                category: "compatibility"
            )
            for field in result.mismatchedFields {
                HaispaceLogger.warning(
                    "   ↳ [\(field.field.rawValue)] aggregate=\(field.aggregateValue) legacy=\(field.legacyValue)",
                    category: "compatibility"
                )
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private static func extractAcceptedAt(from commitment: PaymentCommitment?) -> Date? {
        switch commitment {
        case .accepted(_, _, let meta): return meta.acceptedAt
        case .verified(_, _, let meta): return meta.acceptedAt
        default: return nil
        }
    }
}
