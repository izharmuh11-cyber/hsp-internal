// PaymentCommitment.swift
// HaispaceBooths — Core/Domain/Session
//
// Domain model untuk komitmen pembayaran sesuai Platform GLOSSARY.
//
// GLOSSARY definition:
//   Pending  — proses pembayaran sedang berlangsung
//   Accepted — Booth memiliki alasan cukup untuk melanjutkan Workflow (lokal)
//   Verified — Cloud sudah mengkonfirmasi pembayaran (async, tidak memblokir)
//
// INVARIANT: Workflow hanya membutuhkan Accepted.
//            Verified diurus SyncEngine secara asinkron.
//
// Ref: haispace-platform/docs/GLOSSARY.md — PaymentCommitment
// Ref: haispace-platform/runtime/RUNTIME_GUARANTEES.md — Guarantee #4

import Foundation

// MARK: - PaymentMetadata

/// Metadata domain lengkap transaksi pembayaran.
/// Bebas dari nama vendor/gateway spesifik.
public struct PaymentMetadata: Codable, Sendable, Equatable {
    public let currency: String           // Default "IDR"
    public let localReference: String      // Identifikasi unik di Booth (misal: UUID)
    public let providerReference: String?  // Identifikasi dari provider/cloud (misal: Ref QRIS/Bank)
    public let requestedAt: Date
    public let acceptedAt: Date?
    public let verifiedAt: Date?

    public init(
        currency: String = "IDR",
        localReference: String,
        providerReference: String? = nil,
        requestedAt: Date = Date(),
        acceptedAt: Date? = nil,
        verifiedAt: Date? = nil
    ) {
        self.currency = currency
        self.localReference = localReference
        self.providerReference = providerReference
        self.requestedAt = requestedAt
        self.acceptedAt = acceptedAt
        self.verifiedAt = verifiedAt
    }
}

// MARK: - PaymentCommitment

/// Komitmen pembayaran dalam sebuah Session.
/// Ini adalah domain model, bukan UI state.
public enum PaymentCommitment: Codable, Sendable, Equatable {

    /// Proses pembayaran sedang berlangsung — belum ada konfirmasi.
    case pending(
        method: PaymentCommitmentMethod,
        metadata: PaymentMetadata
    )

    /// Booth memiliki alasan cukup untuk melanjutkan Workflow.
    /// Ini adalah point-of-no-return — Workflow tidak dapat dibatalkan
    /// oleh network failure atau Cloud timeout setelah state ini.
    case accepted(
        method: PaymentCommitmentMethod,
        amount: Int,           // dalam Rupiah (Int, bukan Double)
        metadata: PaymentMetadata
    )

    /// Cloud sudah mengkonfirmasi pembayaran (async — tidak memblokir Workflow).
    case verified(
        method: PaymentCommitmentMethod,
        amount: Int,
        metadata: PaymentMetadata
    )

    /// Pembayaran ditolak — bukan Abort Session.
    /// Session tetap ada. Tamu bisa mencoba lagi atau operator intervensi.
    ///
    /// Contoh: QR expired, user cancel, payment timeout.
    case rejected(
        method: PaymentCommitmentMethod,
        reason: PaymentRejectionReason,
        rejectedAt: Date
    )

    // MARK: - Convenience Accessors

    /// Apakah Workflow boleh dilanjutkan?
    /// Hanya perlu Accepted — tidak perlu menunggu Verified.
    public var isWorkflowAllowed: Bool {
        switch self {
        case .pending, .rejected: return false
        case .accepted, .verified: return true
        }
    }

    /// Apakah tamu bisa mencoba bayar lagi?
    public var canRetry: Bool {
        switch self {
        case .rejected(_, let reason, _):
            return reason.isRetryable
        default: return false
        }
    }

    public var amount: Int {
        switch self {
        case .pending, .rejected: return 0
        case .accepted(_, let amount, _): return amount
        case .verified(_, let amount, _): return amount
        }
    }

    public var localTransactionId: String? {
        switch self {
        case .pending(_, let meta): return meta.localReference
        case .accepted(_, _, let meta): return meta.localReference
        case .verified(_, _, let meta): return meta.localReference
        case .rejected: return nil
        }
    }

    public var providerReference: String? {
        switch self {
        case .pending(_, let meta): return meta.providerReference
        case .accepted(_, _, let meta): return meta.providerReference
        case .verified(_, _, let meta): return meta.providerReference
        case .rejected: return nil
        }
    }

    public var method: PaymentCommitmentMethod {
        switch self {
        case .pending(let method, _): return method
        case .accepted(let method, _, _): return method
        case .verified(let method, _, _): return method
        case .rejected(let method, _, _): return method
        }
    }
}

// MARK: - PaymentCommitmentMethod

/// Metode pembayaran — platform-agnostic.
/// Tidak mengacu pada implementasi capability spesifik.
public enum PaymentCommitmentMethod: String, Codable, Sendable, Equatable {
    case qris         // QRIS offline (EMVCo)
    case cash         // Tunai — dikonfirmasi operator
    case voucher      // Voucher/kode promo
    case midtrans     // Gateway online (future)
}

// MARK: - PaymentRejectionReason

public enum PaymentRejectionReason: String, Codable, Sendable {
    case qrExpired          // QR Code sudah melewati TTL 3 menit
    case userCancelled      // Tamu membatalkan secara eksplisit
    case timeout            // Operator timeout (tidak ada aksi dalam batas waktu)
    case insufficientFunds  // Saldo tidak cukup (dari gateway)
    case gatewayError       // Error dari payment gateway
    case operatorVoid       // Operator membatalkan transaksi

    /// Apakah tamu boleh mencoba membayar lagi setelah rejection ini?
    public var isRetryable: Bool {
        switch self {
        case .qrExpired, .timeout: return true
        case .userCancelled, .operatorVoid: return false
        case .insufficientFunds, .gatewayError: return true
        }
    }
}

// MARK: - PaymentCommitmentError

public enum PaymentCommitmentError: Error, Sendable {
    case alreadyAccepted
    case alreadyVerified
    case cannotVerifyWithoutAcceptance
    case transactionIdMismatch(expected: String, got: String)
    case cannotRejectAfterAcceptance  // Session sudah lewat point-of-no-return
}
