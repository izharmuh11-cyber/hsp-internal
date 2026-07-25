// P2PSharedTypes.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Value Objects & Data Structs khusus untuk Domain Komunikasi P2P.
// Mendukung dual-transport mesh, sliding window, & resume capability.

import Foundation

/// Tipe Transport Jaringan Aktif
public enum P2PTransportType: String, Codable, Sendable {
    case multipeerConnectivity  // Primary Apple Mesh
    case localTCPSocket         // Fallback Local Wi-Fi Router
    case unknown
}

/// Identifikasi Peer Perangkat Terhubung
public struct P2PPeerInfo: Hashable, Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let role: String // "iPhoneCamera" | "iPadBooth"
    public let activeTransport: P2PTransportType
    
    public init(deviceId: String, deviceName: String, role: String, activeTransport: P2PTransportType) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.role = role
        self.activeTransport = activeTransport
    }
}

/// Progress Transfer Real-Time
public struct P2PTransferProgress: Codable, Sendable {
    public let transferId: TransferID
    public let sessionId: SessionID
    public let currentChunkIndex: UInt32
    public let totalChunkCount: UInt32
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let progressPercentage: Double
    
    public init(
        transferId: TransferID,
        sessionId: SessionID,
        currentChunkIndex: UInt32,
        totalChunkCount: UInt32,
        bytesTransferred: Int64,
        totalBytes: Int64
    ) {
        self.transferId = transferId
        self.sessionId = sessionId
        self.currentChunkIndex = currentChunkIndex
        self.totalChunkCount = totalChunkCount
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.progressPercentage = totalBytes > 0 ? Double(bytesTransferred) / Double(totalBytes) : 0.0
    }
}

/// Hasil Akhir Transfer Data P2P
public struct P2PTransferResult: Codable, Sendable {
    public let transferId: TransferID
    public let sessionId: SessionID
    public let outputReference: String
    public let totalBytes: Int64
    public let transferDurationMs: Double
    public let isResumed: Bool
    
    public init(
        transferId: TransferID,
        sessionId: SessionID,
        outputReference: String,
        totalBytes: Int64,
        transferDurationMs: Double,
        isResumed: Bool = false
    ) {
        self.transferId = transferId
        self.sessionId = sessionId
        self.outputReference = outputReference
        self.totalBytes = totalBytes
        self.transferDurationMs = transferDurationMs
        self.isResumed = isResumed
    }
}
