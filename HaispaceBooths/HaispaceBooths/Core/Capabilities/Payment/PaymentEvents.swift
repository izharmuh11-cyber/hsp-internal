// PaymentEvents.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Payload Event Domain Pembayaran, Health, dan Metrics.

import Foundation

// MARK: - Granular Event Payloads

public struct PaymentRequestedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let paymentId: PaymentID
    public let amount: PaymentAmount
    
    public init(sessionId: SessionID, correlationId: CorrelationID, paymentId: PaymentID, amount: PaymentAmount) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.paymentId = paymentId
        self.amount = amount
    }
}

public struct PaymentConfirmedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let paymentId: PaymentID
    public let confirmedAt: Date
    
    public init(sessionId: SessionID, correlationId: CorrelationID, paymentId: PaymentID, confirmedAt: Date = Date()) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.paymentId = paymentId
        self.confirmedAt = confirmedAt
    }
}

public struct PaymentExpiredPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let paymentId: PaymentID
    
    public init(sessionId: SessionID, correlationId: CorrelationID, paymentId: PaymentID) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.paymentId = paymentId
    }
}

// MARK: - Health & Metrics Models

public enum PaymentHealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case unavailable

    public var displayLabel: String {
        switch self {
        case .healthy: return "Sehat"
        case .degraded: return "Degradasi"
        case .unavailable: return "Error"
        }
    }
}

/// Snapshot Kesehatan Domain Pembayaran
public struct PaymentHealth: Codable, Sendable {
    public let status: PaymentHealthLevel
    public let activeMethod: PaymentCapabilityMethod
    public let timestamp: Date
    public let lastErrorMessage: String?
    
    public init(
        status: PaymentHealthLevel = .healthy,
        activeMethod: PaymentCapabilityMethod = .localQRIS,
        timestamp: Date = Date(),
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.activeMethod = activeMethod
        self.timestamp = timestamp
        self.lastErrorMessage = lastErrorMessage
    }
    
    public func updated(status: PaymentHealthLevel, error: String? = nil) -> PaymentHealth {
        return PaymentHealth(
            status: status,
            activeMethod: self.activeMethod,
            lastErrorMessage: error
        )
    }
}

/// Snapshot Metrik Performa Domain Pembayaran
public struct PaymentMetrics: Codable, Sendable {
    public let totalTransactionsCount: Int
    public let successfulPaymentCount: Int
    public let averageAuthorizationTimeMs: Double
    public let paymentAbandonmentCount: Int
    
    public init(
        totalTransactionsCount: Int = 0,
        successfulPaymentCount: Int = 0,
        averageAuthorizationTimeMs: Double = 0.0,
        paymentAbandonmentCount: Int = 0
    ) {
        self.totalTransactionsCount = totalTransactionsCount
        self.successfulPaymentCount = successfulPaymentCount
        self.averageAuthorizationTimeMs = averageAuthorizationTimeMs
        self.paymentAbandonmentCount = paymentAbandonmentCount
    }
    
    public func recordSuccess(durationMs: Double) -> PaymentMetrics {
        let newSuccess = self.successfulPaymentCount + 1
        let newTotal = self.totalTransactionsCount + 1
        let newAvg = ((self.averageAuthorizationTimeMs * Double(self.successfulPaymentCount)) + durationMs) / Double(newSuccess)
        
        return PaymentMetrics(
            totalTransactionsCount: newTotal,
            successfulPaymentCount: newSuccess,
            averageAuthorizationTimeMs: newAvg,
            paymentAbandonmentCount: self.paymentAbandonmentCount
        )
    }
}
