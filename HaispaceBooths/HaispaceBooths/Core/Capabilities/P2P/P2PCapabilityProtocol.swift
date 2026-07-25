// P2PCapabilityProtocol.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Kontrak Kemampuan Bisnis Domain P2P Communication Haispace Platform.
// BEBAS dari tipe data MultipeerConnectivity, MCPeerID, NWConnection, atau Socket.

import Foundation

public protocol P2PCapabilityProtocol: Sendable {
    
    /// Snapshot kesehatan domain P2P saat ini (Read-Only O(1))
    var healthSnapshot: P2PHealth { get }
    
    /// Snapshot metrik performa domain P2P saat ini (Read-Only O(1))
    var metricsSnapshot: P2PMetrics { get }
    
    /// Menyiapkan P2P Mesh dengan konfigurasi tertentu
    func prepare(configuration: P2PConfiguration) async throws
    
    /// Memulai sesi P2P aktif untuk SessionID tertentu
    func startSession(sessionId: SessionID) async throws -> P2PPeerInfo
    
    /// Menghentikan sesi P2P aktif
    func stopSession() async
    
    /// Meminta pengiriman data/foto via P2P (Reliable Transfer)
    func requestTransfer(
        transferId: TransferID,
        payloadPath: String
    ) async throws -> P2PTransferResult
    
    /// Meminta kelanjutan pengiriman yang terputus (Resume Transfer)
    func requestResume(
        transferId: TransferID,
        fromChunkIndex: UInt32
    ) async throws -> P2PTransferResult
}
