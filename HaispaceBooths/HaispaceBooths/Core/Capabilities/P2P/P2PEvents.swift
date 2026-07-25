// P2PEvents.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Payload Event Granular Domain P2P, Health, dan Metrics.

import Foundation

// MARK: - Granular Event Payloads

public struct P2PPeerConnectedPayload: Codable, Sendable {
    public let peer: P2PPeerInfo
    public let timestamp: Date
    
    public init(peer: P2PPeerInfo, timestamp: Date = Date()) {
        self.peer = peer
        self.timestamp = timestamp
    }
}

public struct TransferStartedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let transferId: TransferID
    public let totalBytes: Int64
    public let totalChunks: UInt32
    
    public init(sessionId: SessionID, transferId: TransferID, totalBytes: Int64, totalChunks: UInt32) {
        self.sessionId = sessionId
        self.transferId = transferId
        self.totalBytes = totalBytes
        self.totalChunks = totalChunks
    }
}

public struct TransferProgressPayload: Codable, Sendable {
    public let progress: P2PTransferProgress
    
    public init(progress: P2PTransferProgress) {
        self.progress = progress
    }
}

public struct TransferCompletedPayload: Codable, Sendable {
    public let result: P2PTransferResult
    
    public init(result: P2PTransferResult) {
        self.result = result
    }
}

public struct TransferResumedPayload: Codable, Sendable {
    public let transferId: TransferID
    public let resumedFromChunk: UInt32
    
    public init(transferId: TransferID, resumedFromChunk: UInt32) {
        self.transferId = transferId
        self.resumedFromChunk = resumedFromChunk
    }
}

// MARK: - Health & Metrics Models

public enum P2PHealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case unavailable
}

/// Snapshot Kesehatan Domain P2P Communication
public struct P2PHealth: Codable, Sendable {
    public let status: P2PHealthLevel
    public let isNetworkConnected: Bool
    public let isPeerPaired: Bool
    public let activeTransportType: P2PTransportType
    public let receiveWindowAvailable: UInt16
    public let lastErrorMessage: String?
    
    public init(
        status: P2PHealthLevel = .healthy,
        isNetworkConnected: Bool = true,
        isPeerPaired: Bool = true,
        activeTransportType: P2PTransportType = .multipeerConnectivity,
        receiveWindowAvailable: UInt16 = 32,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.isNetworkConnected = isNetworkConnected
        self.isPeerPaired = isPeerPaired
        self.activeTransportType = activeTransportType
        self.receiveWindowAvailable = receiveWindowAvailable
        self.lastErrorMessage = lastErrorMessage
    }
    
    public func updated(status: P2PHealthLevel, transport: P2PTransportType? = nil, error: String? = nil) -> P2PHealth {
        return P2PHealth(
            status: status,
            isNetworkConnected: self.isNetworkConnected,
            isPeerPaired: self.isPeerPaired,
            activeTransportType: transport ?? self.activeTransportType,
            receiveWindowAvailable: self.receiveWindowAvailable,
            lastErrorMessage: error
        )
    }
}

/// Snapshot Metrik Performa Domain P2P Communication
public struct P2PMetrics: Codable, Sendable {
    public let averageRTTMs: Double
    public let packetLossPercentage: Double
    public let reconnectCount: Int
    public let activeThroughputKBps: Double
    public let transferredBytesCount: Int64
    public let failedTransferCount: Int
    
    public init(
        averageRTTMs: Double = 12.0,
        packetLossPercentage: Double = 0.0,
        reconnectCount: Int = 0,
        activeThroughputKBps: Double = 1500.0,
        transferredBytesCount: Int64 = 0,
        failedTransferCount: Int = 0
    ) {
        self.averageRTTMs = averageRTTMs
        self.packetLossPercentage = packetLossPercentage
        self.reconnectCount = reconnectCount
        self.activeThroughputKBps = activeThroughputKBps
        self.transferredBytesCount = transferredBytesCount
        self.failedTransferCount = failedTransferCount
    }
    
    public func recordTransfer(bytes: Int64, durationMs: Double) -> P2PMetrics {
        let newTotalBytes = self.transferredBytesCount + bytes
        let throughput = durationMs > 0 ? (Double(bytes) / 1024.0) / (durationMs / 1000.0) : self.activeThroughputKBps
        return P2PMetrics(
            averageRTTMs: self.averageRTTMs,
            packetLossPercentage: self.packetLossPercentage,
            reconnectCount: self.reconnectCount,
            activeThroughputKBps: throughput,
            transferredBytesCount: newTotalBytes,
            failedTransferCount: self.failedTransferCount
        )
    }
}
