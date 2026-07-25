// PaymentCapability.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Sprint 4 Implementation — Business Capability Orchestrator Domain Pembayaran.
// Mengadopsi Pola Golden Reference Doc #50 (91% Structural Reuse).
//
// Ref: docs/design/09_payment.md, docs/design/33_local_qris.md, docs/design/50_golden_reference.md

import Foundation

public actor PaymentCapability: @preconcurrency PaymentCapabilityProtocol {
    
    // MARK: - Associated Value State Machine (Single Source of Truth)
    private enum InternalState: Sendable {
        case idle
        case prepared(PConfiguration: PaymentConfiguration)
        case requested(sessionId: SessionID, paymentId: PaymentID, amount: PaymentAmount, method: PaymentCapabilityMethod, config: PaymentConfiguration)
        case processing(sessionId: SessionID, paymentId: PaymentID, amount: PaymentAmount, method: PaymentCapabilityMethod, config: PaymentConfiguration)
        case confirmed(sessionId: SessionID, paymentId: PaymentID, result: PaymentResult)
        case failed(sessionId: SessionID, paymentId: PaymentID, reason: String)
        case stopped
        
        var name: String {
            switch self {
            case .idle: return "idle"
            case .prepared: return "prepared"
            case .requested: return "requested"
            case .confirmed: return "confirmed"
            case .stopped: return "stopped"
            case .processing: return "processing"
            case .failed: return "failed"
            }
        }
    }
    
    // MARK: - Private State Properties
    private var state: InternalState = .idle
    
    // Dependencies Injected via Protocol Interface
    private let runtime: PaymentRuntimeProtocol
    
    // State Snapshot Buffers (O(1) Access)
    private var health: PaymentHealth = PaymentHealth(status: .healthy)
    private var metrics: PaymentMetrics = PaymentMetrics()
    
    // MARK: - Public Read-Only Properties (PaymentCapabilityProtocol)
    
    public var healthSnapshot: PaymentHealth { health }
    public var metricsSnapshot: PaymentMetrics { metrics }
    
    // MARK: - Initializer (Dependency Injection)
    public init(runtime: PaymentRuntimeProtocol) {
        self.runtime = runtime
    }
    
    // MARK: - Business Capability Protocol Methods
    
    /// Menyiapkan modul pembayaran dengan konfigurasi tertentu
    public func prepare(configuration: PaymentConfiguration) async throws {
        switch state {
        case .idle, .stopped:
            do {
                try await runtime.setupRuntime(configuration: configuration)
                self.state = .prepared(PConfiguration: configuration)
                self.health = health.updated(status: .healthy, error: nil)
            } catch {
                self.health = health.updated(status: .unavailable, error: error.localizedDescription)
                throw PaymentCapabilityError.payloadGenerationFailed(reason: error.localizedDescription)
            }
        default:
            throw PaymentCapabilityError.payloadGenerationFailed(reason: "State invalid: \(state.name)")
        }
    }
    
    /// Meminta transaksi pembayaran baru (Returns PaymentResult dengan payload String)
    public func requestPayment(
        sessionId: SessionID,
        correlationId: CorrelationID,
        amount: PaymentAmount,
        method: PaymentCapabilityMethod
    ) async throws -> PaymentResult {
        guard case .prepared(let config) = state else {
            throw PaymentCapabilityError.sessionNotActive
        }
        
        let paymentId = PaymentID()
        let startTime = Date()
        
        do {
            let payloadStr = try await runtime.generatePayload(
                paymentId: paymentId,
                amount: amount,
                method: method
            )
            
            let result = PaymentResult(
                paymentId: paymentId,
                sessionId: sessionId,
                amount: amount,
                method: method,
                payloadString: payloadStr
            )
            
            self.state = .requested(
                sessionId: sessionId,
                paymentId: paymentId,
                amount: amount,
                method: method,
                config: config
            )
            
            let durationMs = Date().timeIntervalSince(startTime) * 1000.0
            self.metrics = metrics.recordSuccess(durationMs: durationMs)
            return result
            
        } catch {
            self.health = health.updated(status: .degraded, error: error.localizedDescription)
            throw PaymentCapabilityError.payloadGenerationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Mengonfirmasi otorisasi pembayaran (Idempotent - Invariant #12)
    public func confirmPayment(paymentId: PaymentID) async throws -> PaymentResult {
        switch state {
        case .confirmed(let sessionId, let pid) where pid == paymentId:
            // Idempotent duplicate call protection: Return previous confirmed state without side-effects
            return PaymentResult(
                paymentId: paymentId,
                sessionId: sessionId,
                amount: PaymentAmount(amountValue: 0),
                method: .localQRIS,
                payloadString: "IDEMPOTENT_CONFIRMED",
                confirmedAt: Date()
            )
            
        case .requested(let sessionId, let pid, let amount, let method, _):
            guard pid == paymentId else {
                throw PaymentCapabilityError.verificationFailed(reason: "PaymentID Mismatch")
            }
            
            self.state = .confirmed(sessionId: sessionId, paymentId: paymentId)
            self.health = health.updated(status: .healthy, error: nil)
            
            return PaymentResult(
                paymentId: paymentId,
                sessionId: sessionId,
                amount: amount,
                method: method,
                payloadString: "CONFIRMED",
                confirmedAt: Date()
            )
            
        default:
            throw PaymentCapabilityError.sessionNotActive
        }
    }
    
    /// Membatalkan transaksi pembayaran
    public func cancelPayment(paymentId: PaymentID) async throws {
        await runtime.cancelTransaction(paymentId: paymentId)
        self.health = health.updated(status: .healthy, error: nil)
    }
    
    /// Menghentikan sesi pembayaran
    public func stopSession() async {
        self.state = .stopped
        self.health = health.updated(status: .healthy, error: nil)
    }
}
