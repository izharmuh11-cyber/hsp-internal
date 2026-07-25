// DeliveryCapability.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Business Capability Orchestrator Domain Distribusi Foto (Distribution Orchestrator).
// Mengadopsi Pola Golden Reference Doc #50 (94% Structural Reuse).
//
// Ref: docs/design/10_photo_delivery.md, docs/design/50_golden_reference.md

import Foundation

public actor DeliveryCapability: @preconcurrency DeliveryCapabilityProtocol {
    
    // MARK: - Associated Value State Machine (Single Source of Truth)
    private enum InternalState: Sendable {
        case idle
        case prepared(config: DeliveryConfiguration)
        case dispatching(sessionId: SessionID, deliveryId: DeliveryID, config: DeliveryConfiguration)
        case delivered(sessionId: SessionID, deliveryId: DeliveryID)
        case stopped
        
        var name: String {
            switch self {
            case .idle: return "idle"
            case .prepared: return "prepared"
            case .dispatching: return "dispatching"
            case .delivered: return "delivered"
            case .stopped: return "stopped"
            }
        }
    }
    
    // MARK: - Private State Properties
    private var state: InternalState = .idle
    
    // Dependencies Injected via Protocol Interface
    private let runtime: DeliveryRuntimeProtocol
    
    // State Snapshot Buffers (O(1) Access)
    private var health: DeliveryHealth = DeliveryHealth(status: .healthy)
    private var metrics: DeliveryMetrics = DeliveryMetrics()
    
    // MARK: - Public Read-Only Properties (DeliveryCapabilityProtocol)
    
    public var healthSnapshot: DeliveryHealth { health }
    public var metricsSnapshot: DeliveryMetrics { metrics }
    
    // MARK: - Initializer (Dependency Injection)
    public init(runtime: DeliveryRuntimeProtocol) {
        self.runtime = runtime
    }
    
    // MARK: - Business Capability Protocol Methods
    
    /// Menyiapkan modul distribusi dengan konfigurasi tertentu
    public func prepare(configuration: DeliveryConfiguration) async throws {
        switch state {
        case .idle, .stopped:
            do {
                try await runtime.prepareChannel(configuration: configuration)
                self.state = .prepared(config: configuration)
                self.health = health.updated(status: .healthy, error: nil)
            } catch {
                self.health = health.updated(status: .unavailable, error: error.localizedDescription)
                throw DeliveryCapabilityError.channelUnavailable(channel: configuration.primaryChannel.rawValue)
            }
        default:
            throw DeliveryCapabilityError.channelUnavailable(channel: "State invalid: \(state.name)")
        }
    }
    
    /// Meminta distribusi pengiriman foto (Returns DeliveryResult)
    public func requestDelivery(
        sessionId: SessionID,
        correlationId: CorrelationID,
        photoId: PhotoID,
        assetPath: String,
        channel: DeliveryChannel
    ) async throws -> DeliveryResult {
        guard case .prepared(let config) = state else {
            throw DeliveryCapabilityError.sessionNotActive
        }
        
        let deliveryId = DeliveryID()
        let startTime = Date()
        self.state = .dispatching(sessionId: sessionId, deliveryId: deliveryId, config: config)
        
        do {
            let result = try await runtime.dispatchAsset(
                deliveryId: deliveryId,
                photoId: photoId,
                assetPath: assetPath,
                channel: channel
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            self.metrics = metrics.recordDelivery(durationMs: durationMs)
            self.state = .delivered(sessionId: sessionId, deliveryId: deliveryId)
            self.health = health.updated(status: .healthy, error: nil)
            return result
            
        } catch {
            self.state = .prepared(config: config)
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw DeliveryCapabilityError.deliveryFailed(reason: error.localizedDescription)
        }
    }
    
    /// Mengulang pengiriman yang gagal (Retry Delivery)
    public func retryDelivery(
        deliveryId: DeliveryID,
        correlationId: CorrelationID
    ) async throws -> DeliveryResult {
        guard case .prepared(let config) = state else {
            throw DeliveryCapabilityError.sessionNotActive
        }
        
        let startTime = Date()
        let mockSession = SessionID(rawValue: "SESS-RETRY")
        self.state = .dispatching(sessionId: mockSession, deliveryId: deliveryId, config: config)
        
        do {
            let result = try await runtime.dispatchAsset(
                deliveryId: deliveryId,
                photoId: PhotoID(rawValue: "PHOTO-RETRY"),
                assetPath: "retry_photo.jpg",
                channel: config.fallbackChannel
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            self.metrics = metrics.recordDelivery(durationMs: durationMs)
            self.state = .delivered(sessionId: mockSession, deliveryId: deliveryId)
            return result
            
        } catch {
            self.state = .prepared(config: config)
            throw DeliveryCapabilityError.deliveryFailed(reason: error.localizedDescription)
        }
    }
    
    /// Membatalkan transaksi pengiriman
    public func cancelDelivery(deliveryId: DeliveryID) async throws {
        await runtime.cancelDelivery(deliveryId: deliveryId)
        self.health = health.updated(status: .healthy, error: nil)
    }
    
    /// Menghentikan sesi distribusi
    public func stopSession() async {
        self.state = .stopped
        self.health = health.updated(status: .healthy, error: nil)
    }
}
