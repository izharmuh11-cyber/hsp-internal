// CameraCapability.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Golden Reference Implementation untuk Haispace Platform Capabilities.
// Berfungsi sebagai Orchestrator yang mengoordinasikan Runtime, Events, Telemetry, Health, & Metrics.
//
// Ref: docs/design/47_runtime_capabilities.md, docs/design/49_architecture_compliance.md

import Foundation

public actor CameraCapability: CameraCapabilityProtocol {
    
    // MARK: - Internal Associated Value State Machine (Single Source of Truth)
    private enum InternalState: Sendable {
        case idle
        case prepared(CameraConfiguration)
        case running(sessionId: SessionID, config: CameraConfiguration)
        case capturing(sessionId: SessionID, correlationId: CorrelationID, config: CameraConfiguration)
        case stopping
        case stopped
        
        var name: String {
            switch self {
            case .idle: return "idle"
            case .prepared: return "prepared"
            case .running: return "running"
            case .capturing: return "capturing"
            case .stopping: return "stopping"
            case .stopped: return "stopped"
            }
        }
    }
    
    // MARK: - Private State Properties
    private var state: InternalState = .idle
    
    // Dependencies Injected via Protocol Interface
    private let runtime: CameraRuntimeProtocol
    
    // State Snapshot Buffers (O(1) Access)
    private var health: CameraHealth = CameraHealth(status: .healthy)
    private var metrics: CameraMetrics = CameraMetrics()
    
    // MARK: - Public Read-Only Properties (CameraCapabilityProtocol)
    
    public var healthSnapshot: CameraHealth { health }
    public var metricsSnapshot: CameraMetrics { metrics }
    
    // MARK: - Initializer (Dependency Injection)
    public init(runtime: CameraRuntimeProtocol) {
        self.runtime = runtime
    }
    
    // MARK: - Business Capability Protocol Methods
    
    /// Menyiapkan modul kamera dengan konfigurasi bisnis
    public func prepare(configuration: CameraConfiguration) async throws {
        switch state {
        case .idle, .stopped:
            do {
                try await runtime.setupHardware(configuration: configuration)
                self.state = .prepared(configuration)
                self.health = health.updated(status: .healthy, error: nil)
            } catch {
                self.health = health.updated(status: .unavailable, error: error.localizedDescription)
                throw CameraCapabilityError.hardwareFailure(reason: error.localizedDescription)
            }
        default:
            throw CameraCapabilityError.invalidConfiguration(reason: "State invalid: \(state.name)")
        }
    }
    
    /// Memulai sesi kamera aktif untuk SessionID tertentu
    public func startSession(sessionId: SessionID) async throws {
        guard case .prepared(let config) = state else {
            throw CameraCapabilityError.invalidConfiguration(reason: "Harus prepare() terlebih dahulu sebelum startSession()")
        }
        
        do {
            try await runtime.startHardwareSession()
            self.state = .running(sessionId: sessionId, config: config)
            self.health = health.updated(status: .healthy, error: nil)
        } catch {
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw CameraCapabilityError.runtimeFailure(reason: error.localizedDescription)
        }
    }
    
    /// Menghentikan sesi kamera aktif
    public func stopSession() async {
        switch state {
        case .running, .capturing:
            self.state = .stopping
            await runtime.stopHardwareSession()
            self.state = .stopped
            self.health = health.updated(status: .healthy, error: nil)
        default:
            return
        }
    }
    
    /// Mengirim instruksi pengoperasian jepretan foto berbasis CorrelationID
    public func requestCapture(correlationId: CorrelationID) async throws {
        guard case .running(let sessionId, let config) = state else {
            throw CameraCapabilityError.sessionNotStarted
        }
        
        // Prevents concurrent capturing via state machine transition
        self.state = .capturing(sessionId: sessionId, correlationId: correlationId, config: config)
        let startTime = Date()
        
        do {
            // 1. Runtime Execute Capture & Commit to Storage
            let captureResult = try await runtime.captureStillImage(correlationId: correlationId)
            
            // 2. Metrics & Health Functional Append Update
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            self.metrics = metrics.recordCapture(durationMs: durationMs)
            self.health = health.updated(status: .healthy, lastCaptureTime: Date(), error: nil)
            
            // 3. State Restore to Running
            self.state = .running(sessionId: sessionId, config: config)
            
        } catch {
            self.state = .running(sessionId: sessionId, config: config)
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw CameraCapabilityError.runtimeFailure(reason: error.localizedDescription)
        }
    }
}
