// DeliveryEvents.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Payload Event Domain Distribusi, Health, dan Metrics.

import Foundation

// MARK: - Granular Event Payloads

public struct DeliveryRequestedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let deliveryId: DeliveryID
    public let photoId: PhotoID
    
    public init(sessionId: SessionID, correlationId: CorrelationID, deliveryId: DeliveryID, photoId: PhotoID) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.deliveryId = deliveryId
        self.photoId = photoId
    }
}

public struct DeliveryCompletedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let deliveryId: DeliveryID
    public let channel: DeliveryChannel
    public let deliveryReference: String
    public let deliveredAt: Date
    
    public init(
        sessionId: SessionID,
        correlationId: CorrelationID,
        deliveryId: DeliveryID,
        channel: DeliveryChannel,
        deliveryReference: String,
        deliveredAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.deliveryId = deliveryId
        self.channel = channel
        self.deliveryReference = deliveryReference
        self.deliveredAt = deliveredAt
    }
}

public struct DeliveryFailedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let deliveryId: DeliveryID
    public let reason: String
    
    public init(sessionId: SessionID, correlationId: CorrelationID, deliveryId: DeliveryID, reason: String) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.deliveryId = deliveryId
        self.reason = reason
    }
}

// MARK: - Health & Metrics Models

public enum DeliveryHealthLevel: String, Codable, Sendable {
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

/// Snapshot Kesehatan Domain Distribusi
public struct DeliveryHealth: Codable, Sendable {
    public let status: DeliveryHealthLevel
    public let activeChannel: DeliveryChannel
    public let isLocalServerRunning: Bool
    public let lastErrorMessage: String?
    
    public init(
        status: DeliveryHealthLevel = .healthy,
        activeChannel: DeliveryChannel = .localBonjourWiFiServer,
        isLocalServerRunning: Bool = true,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.activeChannel = activeChannel
        self.isLocalServerRunning = isLocalServerRunning
        self.lastErrorMessage = lastErrorMessage
    }
    
    public func updated(status: DeliveryHealthLevel, error: String? = nil) -> DeliveryHealth {
        return DeliveryHealth(
            status: status,
            activeChannel: self.activeChannel,
            isLocalServerRunning: self.isLocalServerRunning,
            lastErrorMessage: error
        )
    }
}

/// Snapshot Metrik Performa Domain Distribusi
public struct DeliveryMetrics: Codable, Sendable {
    public let totalDeliveriesCount: Int
    public let successfulDeliveriesCount: Int
    public let averageDeliveryCompletionTimeMs: Double
    public let failedDeliveriesCount: Int
    
    public init(
        totalDeliveriesCount: Int = 0,
        successfulDeliveriesCount: Int = 0,
        averageDeliveryCompletionTimeMs: Double = 0.0,
        failedDeliveriesCount: Int = 0
    ) {
        self.totalDeliveriesCount = totalDeliveriesCount
        self.successfulDeliveriesCount = successfulDeliveriesCount
        self.averageDeliveryCompletionTimeMs = averageDeliveryCompletionTimeMs
        self.failedDeliveriesCount = failedDeliveriesCount
    }
    
    public func recordDelivery(durationMs: Double) -> DeliveryMetrics {
        let newSuccess = self.successfulDeliveriesCount + 1
        let newTotal = self.totalDeliveriesCount + 1
        let newAvg = ((self.averageDeliveryCompletionTimeMs * Double(self.successfulDeliveriesCount)) + durationMs) / Double(newSuccess)
        
        return DeliveryMetrics(
            totalDeliveriesCount: newTotal,
            successfulDeliveriesCount: newSuccess,
            averageDeliveryCompletionTimeMs: newAvg,
            failedDeliveriesCount: self.failedDeliveriesCount
        )
    }
}
