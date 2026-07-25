// PaymentSharedTypes.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Value Objects & Structs Domain Pembayaran Haispace Platform.

import Foundation

/// Value Object Identifikasi Transaksi Pembayaran
public struct PaymentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Jenis Metode Pembayaran Bisnis
public enum PaymentCapabilityMethod: String, Codable, Sendable {
    case localQRIS
    case midtransGateway
    case cash
    case offlineVoucher
}

/// Jumlah Nominal Pembayaran
public struct PaymentAmount: Codable, Sendable, Equatable {
    public let amountValue: Double
    public let currencyCode: String
    public let method: PaymentCapabilityMethod
    
    public init(amountValue: Double, currencyCode: String = "IDR", method: PaymentCapabilityMethod) {
        self.amountValue = amountValue
        self.currencyCode = currencyCode
        self.method = method
    }
}

/// Hasil Akhir Transaksi Pembayaran
public struct PaymentResult: Codable, Sendable {
    public let paymentId: PaymentID
    public let sessionId: SessionID
    public let amount: PaymentAmount
    public let method: PaymentCapabilityMethod
    public let payloadString: String // String QRIS / Link / Ref Token
    public let confirmedAt: Date?
    
    public init(
        paymentId: PaymentID,
        sessionId: SessionID,
        amount: PaymentAmount,
        method: PaymentCapabilityMethod,
        payloadString: String,
        confirmedAt: Date? = nil
    ) {
        self.paymentId = paymentId
        self.sessionId = sessionId
        self.amount = amount
        self.method = method
        self.payloadString = payloadString
        self.confirmedAt = confirmedAt
    }
}
