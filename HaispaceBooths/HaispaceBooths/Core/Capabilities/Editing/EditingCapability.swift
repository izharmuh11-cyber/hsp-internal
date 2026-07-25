// EditingCapability.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Sprint 2 Implementation — Business Capability Orchestrator Domain Editing.
// Mengadopsi Pola Golden Reference Doc #50 (85-90% Structural Reuse dari CameraCapability).
//
// Ref: docs/design/47_runtime_capabilities.md, docs/design/50_golden_reference.md

import Foundation

public actor EditingCapability: @preconcurrency EditingCapabilityProtocol {
    
    // MARK: - Associated Value State Machine (Single Source of Truth)
    private enum InternalState: Sendable {
        case idle
        case prepared(sessionId: SessionID, config: EditingConfiguration)
        case editing(sessionId: SessionID, config: EditingConfiguration)
        case stopped
        
        var name: String {
            switch self {
            case .idle: return "idle"
            case .prepared: return "prepared"
            case .editing: return "editing"
            case .stopped: return "stopped"
            }
        }
    }
    
    // MARK: - Private State Properties
    private var state: InternalState = .idle
    
    // Dependencies Injected via Protocol Interface
    private let runtime: EditingRuntimeProtocol
    
    // State Snapshot Buffers (O(1) Access)
    private var health: EditingHealth = EditingHealth(status: .healthy)
    private var metrics: EditingMetrics = EditingMetrics()
    
    // MARK: - Public Read-Only Properties (EditingCapabilityProtocol)
    
    public var healthSnapshot: EditingHealth { health }
    public var metricsSnapshot: EditingMetrics { metrics }
    
    // MARK: - Initializer (Dependency Injection)
    public init(runtime: EditingRuntimeProtocol) {
        self.runtime = runtime
    }
    
    // MARK: - Business Capability Protocol Methods
    
    /// Menyiapkan pipeline editing untuk SessionID tertentu
    public func prepare(sessionId: SessionID, configuration: EditingConfiguration) async throws {
        switch state {
        case .idle, .stopped:
            do {
                try await runtime.preparePipeline()
                self.state = .prepared(sessionId: sessionId, config: configuration)
                self.health = health.updated(status: .healthy, error: nil)
            } catch {
                self.health = health.updated(status: .unavailable, error: error.localizedDescription)
                throw EditingCapabilityError.renderPipelineFailed(reason: error.localizedDescription)
            }
        default:
            throw EditingCapabilityError.renderPipelineFailed(reason: "State invalid: \(state.name)")
        }
    }
    
    /// Meminta render Preview cepat (Low Latency, Downsampled)
    public func requestPreview(
        photoInput: String,
        correlationId: CorrelationID
    ) async throws -> PreviewResult {
        guard case .prepared(let sessionId, let config) = state else {
            throw EditingCapabilityError.sessionNotActive
        }
        
        self.state = .editing(sessionId: sessionId, config: config)
        let startTime = Date()
        
        do {
            let result = try await runtime.renderPreview(
                photoInput: photoInput,
                configuration: config,
                correlationId: correlationId
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            recordRenderMetrics(compositionMs: durationMs * 0.4, filterMs: durationMs * 0.6, totalMs: durationMs)
            self.state = .prepared(sessionId: sessionId, config: config)
            return result
            
        } catch {
            self.state = .prepared(sessionId: sessionId, config: config)
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw EditingCapabilityError.renderPipelineFailed(reason: error.localizedDescription)
        }
    }
    
    /// Meminta render Export Full Quality (High Accuracy 12MP/48MP)
    public func requestExport(
        photoInput: String,
        correlationId: CorrelationID
    ) async throws -> ExportResult {
        guard case .prepared(let sessionId, let config) = state else {
            throw EditingCapabilityError.sessionNotActive
        }
        
        self.state = .editing(sessionId: sessionId, config: config)
        let startTime = Date()
        
        do {
            let result = try await runtime.renderExport(
                photoInput: photoInput,
                configuration: config,
                correlationId: correlationId
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            recordRenderMetrics(compositionMs: durationMs * 0.4, filterMs: durationMs * 0.6, totalMs: durationMs)
            self.state = .prepared(sessionId: sessionId, config: config)
            return result
            
        } catch {
            self.state = .prepared(sessionId: sessionId, config: config)
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw EditingCapabilityError.exportFailed(reason: error.localizedDescription)
        }
    }
    
    /// Menghentikan sesi editing
    public func stopSession() async {
        self.state = .stopped
        self.health = health.updated(status: .healthy, error: nil)
    }
    
    // MARK: - Private Metrics & Health Helpers
    
    private func recordRenderMetrics(compositionMs: Double, filterMs: Double, totalMs: Double) {
        self.metrics = metrics.recordRender(
            compositionMs: compositionMs,
            filterMs: filterMs,
            totalExportMs: totalMs
        )
        self.health = health.updated(status: .healthy, error: nil)
    }
}
