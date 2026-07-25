// P2PConfiguration.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Struct Konfigurasi Murni Domain P2P Communication.

import Foundation

public struct P2PConfiguration: Codable, Sendable, Equatable {
    public let receiveWindowSize: UInt16 // Default: 32 Chunks (TCP-like Receiver Window)
    public let chunkSizeBytes: Int       // Default: 32768 Bytes (32KB)
    public let heartbeatIntervalSeconds: Double
    public let maxRetryAttempts: Int
    
    public init(
        receiveWindowSize: UInt16 = 32,
        chunkSizeBytes: Int = 32768,
        heartbeatIntervalSeconds: Double = 2.0,
        maxRetryAttempts: Int = 5
    ) {
        self.receiveWindowSize = receiveWindowSize
        self.chunkSizeBytes = chunkSizeBytes
        self.heartbeatIntervalSeconds = heartbeatIntervalSeconds
        self.maxRetryAttempts = maxRetryAttempts
    }
}
