// CompatibilityCheck.swift
// HaispaceBooths — Core/Infrastructure/Compatibility
//
// Domain model untuk hasil perbandingan Aggregate vs Legacy Store.
//
// TUJUAN (Ref: GPT Architecture Review — PR-02):
//   Bukan sekadar logging. Setiap mismatch menghasilkan Domain Event yang
//   dapat dijumlah oleh Dashboard Engineering selama periode migrasi.
//
//   Target: "Selama 2 minggu terakhir terdapat 0 mismatch."
//   Jika angka nol, Legacy Store aman dihapus dengan percaya diri.
//
// PRINSIP:
//   - Compare status, amount, timestamps — bukan hanya nilai
//   - Bug sinkronisasi sering tersembunyi pada urutan waktu, bukan nilai
//   - Immutable result — tidak ada side effect di sini

import Foundation

// MARK: - CompatibilityCheckField

/// Field spesifik yang dibandingkan dalam satu comparison.
public enum CompatibilityCheckField: String, Codable, Sendable {
    case status          // Status payment (paid, pending, rejected)
    case amount          // Nilai transaksi
    case localReference  // Transaction ID lokal
    case acceptedAt      // Timestamp Accepted
    case method          // Metode pembayaran
}

// MARK: - CompatibilityFieldStatus

/// Status perbandingan satu field.
///
/// PENTING: Unknown berbeda dari Mismatch.
/// Unknown berarti Legacy tidak memiliki field tersebut (field baru di Aggregate).
/// Ini bukan error — ini adalah sinyal bahwa Legacy masih tertinggal.
/// Contoh: PaymentMetadata.providerReference tidak ada di PaymentStore.
public enum CompatibilityFieldStatus: String, Codable, Sendable {
    case matched      // Kedua nilai cocok
    case mismatched   // Kedua nilai ada, tapi berbeda
    case unknown      // Legacy tidak memiliki field ini (field baru di Aggregate)
}

// MARK: - CompatibilityFieldResult

/// Hasil perbandingan satu field antara Aggregate dan Legacy.
public struct CompatibilityFieldResult: Codable, Sendable {
    public let field: CompatibilityCheckField
    public let aggregateValue: String    // String representation untuk logging
    public let legacyValue: String       // "<unknown>" jika field tidak ada di Legacy
    public let status: CompatibilityFieldStatus
    public let checkedAt: Date

    /// Shorthand untuk backward compat
    public var matched: Bool { status == .matched }
    public var isUnknown: Bool { status == .unknown }

    public var delta: String? {
        switch status {
        case .matched: return nil
        case .mismatched: return "aggregate=\(aggregateValue) legacy=\(legacyValue)"
        case .unknown: return "aggregate=\(aggregateValue) legacy=<not available in legacy>"
        }
    }
}

// MARK: - CompatibilityCheckResult

/// Hasil lengkap perbandingan Aggregate vs Legacy Store untuk satu bounded context.
/// Ini yang dipublikasikan sebagai Domain Event.
public struct CompatibilityCheckResult: Codable, Sendable {
    public let checkId: String               // UUID unik per check
    public let sessionId: String
    public let context: String               // "payment", "capture", "delivery"
    public let checkedAt: Date

    public let fieldResults: [CompatibilityFieldResult]
    public let overallMatched: Bool          // True hanya jika SEMUA field matched

    public var mismatchedFields: [CompatibilityFieldResult] {
        fieldResults.filter { $0.status == .mismatched }
    }

    public var unknownFields: [CompatibilityFieldResult] {
        fieldResults.filter { $0.status == .unknown }
    }

    public var mismatchCount: Int { mismatchedFields.count }
    public var unknownCount: Int { unknownFields.count }

    /// True hanya jika semua field matched (tidak ada mismatch, unknown dikecualikan).
    public var hasAnyMismatch: Bool { !mismatchedFields.isEmpty }

    // MARK: - Factory

    public static func build(
        sessionId: String,
        context: String,
        fields: [CompatibilityFieldResult]
    ) -> CompatibilityCheckResult {
        CompatibilityCheckResult(
            checkId: UUID().uuidString,
            sessionId: sessionId,
            context: context,
            checkedAt: Date(),
            fieldResults: fields,
            overallMatched: fields.allSatisfy { $0.status == .matched || $0.status == .unknown }
        )
    }
}

// MARK: - CompatibilityEvent

/// Domain Events yang dihasilkan dari Compatibility Check.
/// Consumers: Dashboard Engineering, SessionAuditTrail, Telemetry.
public enum CompatibilityEvent: Sendable {

    /// Perbandingan berhasil, semua nilai cocok.
    case matched(CompatibilityCheckResult)

    /// Ditemukan perbedaan antara Aggregate dan Legacy Store.
    /// Ini adalah sinyal untuk investigasi — bukan kegagalan runtime.
    case mismatched(CompatibilityCheckResult)

    // MARK: - Metadata

    public var name: String {
        switch self {
        case .matched: return "Compatibility.Matched"
        case .mismatched: return "Compatibility.Mismatched"
        }
    }

    public var result: CompatibilityCheckResult {
        switch self {
        case .matched(let r): return r
        case .mismatched(let r): return r
        }
    }

    public var sessionId: String { result.sessionId }
    public var isMatched: Bool {
        if case .matched = self { return true }
        return false
    }
}
