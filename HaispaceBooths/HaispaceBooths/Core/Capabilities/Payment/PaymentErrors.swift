// PaymentErrors.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Enum Error Independen Domain Payment Capability.

import Foundation

public enum PaymentCapabilityError: Error, LocalizedError, Equatable, Sendable {
    case payloadGenerationFailed(reason: String)
    case transactionExpired
    case transactionCancelledByOperator
    case verificationFailed(reason: String)
    case duplicateConfirmationIgnored
    case sessionNotActive
    
    public var errorDescription: String? {
        switch self {
        case .payloadGenerationFailed(let reason):
            return "Gagal membangkitkan payload pembayaran: \(reason)"
        case .transactionExpired:
            return "Waktu transaksi pembayaran telah habis (Expired)."
        case .transactionCancelledByOperator:
            return "Transaksi dibatalkan oleh operator."
        case .verificationFailed(let reason):
            return "Gagal memverifikasi pembatalan/otorisasi: \(reason)"
        case .duplicateConfirmationIgnored:
            return "Konfirmasi pembayaran duplikat diabaikan (Idempotent)."
        case .sessionNotActive:
            return "Sesi pembayaran belum aktif."
        }
    }
}
