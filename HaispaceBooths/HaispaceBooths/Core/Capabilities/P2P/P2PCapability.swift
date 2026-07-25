// P2PCapability.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Sprint 3 Implementation — Business Capability Orchestrator Domain P2P Networking.
// Mengadopsi Pola Golden Reference Doc #50 (90% Structural Reuse dari Camera & Editing Capabilities).
//
// Ref: docs/design/45_p2p_reliable_transfer_protocol.md, docs/design/50_golden_reference.md

import Foundation

public actor P2PCapability: @preconcurrency P2PCapabilityProtocol {
    
    // MARK: - Associated Value State Machine (Single Source of Truth)
    private enum InternalState: Sendable {
        case idle
        case prepared(P2PConfiguration)
        case running(sessionId: SessionID, peer: P2PPeerInfo, config: P2PConfiguration)
        case transferring(sessionId: SessionID, peer: P2PPeerInfo, config: P2PConfiguration)
        case stopped
        
        var name: String {
            switch self {
            case .idle: return "idle"
            case .prepared: return "prepared"
            case .running: return "running"
            case .transferring: return "transferring"
            case .stopped: return "stopped"
            }
        }
    }
    
    // MARK: - Private State Properties
    private var state: InternalState = .idle
    
    // Dependencies Injected via Protocol Interface
    private let runtime: P2PRuntimeProtocol
    
    // State Snapshot Buffers (O(1) Access)
    private var health: P2PHealth = P2PHealth(status: .healthy)
    private var metrics: P2PMetrics = P2PMetrics()
    
    // MARK: - Public Read-Only Properties (P2PCapabilityProtocol)
    
    public var healthSnapshot: P2PHealth { health }
    public var metricsSnapshot: P2PMetrics { metrics }
    
    // MARK: - Initializer (Dependency Injection)
    public init(runtime: P2PRuntimeProtocol) {
        self.runtime = runtime
    }
    
    // MARK: - Business Capability Protocol Methods
    
    /// Menyiapkan P2P Mesh dengan konfigurasi tertentu
    public func prepare(configuration: P2PConfiguration) async throws {
        switch state {
        case .idle, .stopped:
            do {
                try await runtime.setupTransport(configuration: configuration)
                self.state = .prepared(configuration)
                self.health = health.updated(status: .healthy, error: nil)
            } catch {
                self.health = health.updated(status: .unavailable, error: error.localizedDescription)
                throw P2PCapabilityError.transportFailed(reason: error.localizedDescription)
            }
        default:
            throw P2PCapabilityError.transportFailed(reason: "State invalid: \(state.name)")
        }
    }
    
    /// Memulai sesi P2P aktif untuk SessionID tertentu
    public func startSession(sessionId: SessionID) async throws -> P2PPeerInfo {
        guard case .prepared(let config) = state else {
            throw P2PCapabilityError.transportFailed(reason: "Harus prepare() terlebih dahulu")
        }
        
        do {
            let peer = try await runtime.startPeerDiscovery()
            self.state = .running(sessionId: sessionId, peer: peer, config: config)
            self.health = health.updated(status: .healthy, transport: peer.activeTransport, error: nil)
            return peer
        } catch {
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw P2PCapabilityError.peerDisconnected
        }
    }
    
    /// Menghentikan sesi P2P aktif
    public func stopSession() async {
        self.state = .stopped
        await runtime.stopTransport()
        self.health = health.updated(status: .healthy, error: nil)
    }
    
    /// Meminta pengiriman data/foto via P2P (Reliable Transfer)
    public func requestTransfer(
        transferId: TransferID,
        payloadPath: String
    ) async throws -> P2PTransferResult {
        guard case .running(let sessionId, let peer, let config) = state else {
            throw P2PCapabilityError.sessionNotActive
        }
        
        self.state = .transferring(sessionId: sessionId, peer: peer, config: config)
        let startTime = Date()
        
        do {
            let result = try await runtime.executeTransfer(
                sessionId: sessionId,
                transferId: transferId,
                payloadPath: payloadPath
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            self.metrics = metrics.recordTransfer(bytes: result.totalBytes, durationMs: durationMs)
            self.state = .running(sessionId: sessionId, peer: peer, config: config)
            return result
            
        } catch {
            self.state = .running(sessionId: sessionId, peer: peer, config: config)
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw P2PCapabilityError.transportFailed(reason: error.localizedDescription)
        }
    }
    
    /// Meminta kelanjutan pengiriman yang terputus (Resume Transfer)
    public func requestResume(
        transferId: TransferID,
        fromChunkIndex: UInt32
    ) async throws -> P2PTransferResult {
        guard case .running(let sessionId, let peer, let config) = state else {
            throw P2PCapabilityError.sessionNotActive
        }
        
        self.state = .transferring(sessionId: sessionId, peer: peer, config: config)
        let startTime = Date()
        
        do {
            let result = try await runtime.resumeTransfer(
                transferId: transferId,
                fromChunkIndex: fromChunkIndex
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            self.metrics = metrics.recordTransfer(bytes: result.totalBytes, durationMs: durationMs)
            self.state = .running(sessionId: sessionId, peer: peer, config: config)
            return result
            
        } catch {
            self.state = .running(sessionId: sessionId, peer: peer, config: config)
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw P2PCapabilityError.resumeFailed(transferId: transferId.rawValue)
        }
    }
}
