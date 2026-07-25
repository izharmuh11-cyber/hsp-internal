// P2PRuntimeProtocol.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Protocol Adapter antara P2PCapability (Orchestrator) 
// dan Hardware Transport Layer (MultipeerConnectivity / Network.framework).

import Foundation

public protocol P2PRuntimeProtocol: Sendable {
    
    /// Menyiapkan socket transport & listener
    func setupTransport(configuration: P2PConfiguration) async throws
    
    /// Memulai pencarian / pairing peer perangkat
    func startPeerDiscovery() async throws -> P2PPeerInfo
    
    /// Menghentikan transport session
    func stopTransport() async
    
    /// Mengeksekusi reliable binary transfer (Sliding Window & Hash Check)
    func executeTransfer(
        sessionId: SessionID,
        transferId: TransferID,
        payloadPath: String
    ) async throws -> P2PTransferResult
    
    /// Meminta kelanjutan transfer (Resume Chunk N) pasca reconnect
    func resumeTransfer(
        transferId: TransferID,
        fromChunkIndex: UInt32
    ) async throws -> P2PTransferResult
}
