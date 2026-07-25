// WorkflowOrchestrator.swift
// HaispaceBooths — Core/Workflow
//
// Business State Machine Orchestrator Haispace Kiosk.
// Menghubungkan Intent dari SwiftUI View Layer ke 5 Business Capabilities.
//
// Ref: docs/design/03_user_flow.md, docs/design/46_event_contracts.md

import Foundation

public actor WorkflowOrchestrator: @preconcurrency WorkflowOrchestratorProtocol {
    
    // MARK: - State Properties
    private(set) public var currentStage: WorkflowStage = .landing
    private var activeSessionId: SessionID?
    private var currentCorrelationId: CorrelationID?
    private var activePhotoId: PhotoID?
    private var activeOutputReference: String?
    
    // Capabilities Injected via Protocols
    public let camera: CameraCapabilityProtocol
    public let editing: EditingCapabilityProtocol
    public let payment: PaymentCapabilityProtocol
    public let delivery: DeliveryCapabilityProtocol
    public let p2p: P2PCapabilityProtocol
    
    // Health Monitor
    private var health: WorkflowHealth = WorkflowHealth()
    
    public var healthSnapshot: WorkflowHealth {
        return WorkflowHealth(
            currentStage: self.currentStage,
            activeSessionCount: activeSessionId != nil ? 1 : 0,
            averageCompletionTimeMs: health.averageCompletionTimeMs,
            stalledSessionsCount: health.stalledSessionsCount,
            recoveryCount: health.recoveryCount
        )
    }

    /// Apakah sesi ini pernah mencapai paymentConfirmed?
    /// Dipakai untuk menentukan recovery strategy saat cancel atau crash.
    private var hasFinancialTransaction: Bool {
        guard let sessionId = activeSessionId else { return false }
        let record = SessionAuditTrail.read(sessionId: sessionId.rawValue)
        return record?.hasFinancialTransaction ?? false
    }

    // MARK: - Initializer (Dependency Injection)
    public init(
        camera: CameraCapabilityProtocol,
        editing: EditingCapabilityProtocol,
        payment: PaymentCapabilityProtocol,
        delivery: DeliveryCapabilityProtocol,
        p2p: P2PCapabilityProtocol
    ) {
        self.camera = camera
        self.editing = editing
        self.payment = payment
        self.delivery = delivery
        self.p2p = p2p
    }
    
    // MARK: - Intent Handling (From SwiftUI UI Layer)
    
    public func handleIntent(_ intent: WorkflowIntent) async throws {
        switch intent {
        case .startGuestRegistration:
            let newSession = SessionID()
            self.activeSessionId = newSession

            // Invariant 19: AuditTrail dibuat SEBELUM stage berubah
            SessionAuditTrail.create(sessionId: newSession.rawValue)
            SessionAuditTrail.append(
                sessionId: newSession.rawValue,
                stage: .guestRegistration,
                eventType: .sessionStarted
            )
            self.currentStage = .guestRegistration
            
        case .guestSubmittedInfo(let name, let email):
            let sessionId = getOrCreateActiveSession()
            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .packageSelection,
                eventType: .infoSubmitted,
                metadata: ["guestName": name, "email": email]
            )
            self.currentStage = .packageSelection
            
        case .selectPackage(let packageId):
            let sessionId = getOrCreateActiveSession()
            
            // Prepare Camera Capabilities right away for photo capture
            try await camera.prepare(configuration: CameraConfiguration())
            try await camera.startSession(sessionId: sessionId)

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .capturing,
                eventType: .packageSelected,
                metadata: ["packageId": packageId]
            )
            self.currentStage = .capturing
            
        case .selectTemplate(let frameId):
            guard let sessionId = activeSessionId else { throw WorkflowError.sessionNotActive }

            let editingConfig = EditingConfiguration(frame: FrameReference(frameId: frameId, assetPath: "frames/\(frameId).png"))
            try await editing.prepare(sessionId: sessionId, configuration: editingConfig)

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .exporting,
                eventType: .templateSelected,
                metadata: ["frameId": frameId]
            )
            
            self.currentStage = .exporting

            let correlationId = currentCorrelationId ?? CorrelationID()
            let exportResult = try await editing.requestExport(photoInput: "captured_photo.jpg", correlationId: correlationId)
            self.activePhotoId = exportResult.photoId
            self.activeOutputReference = exportResult.outputReference

            // Transition to Payment
            do {
                try await payment.prepare(configuration: PaymentConfiguration())
                _ = try await payment.requestPayment(
                    sessionId: sessionId,
                    correlationId: correlationId,
                    amount: PaymentAmount(amountValue: 35000, method: .localQRIS),
                    method: .localQRIS
                )
            } catch {
                SessionAuditTrail.append(
                    sessionId: sessionId.rawValue,
                    stage: .exporting,
                    eventType: .paymentFailed,
                    metadata: ["error": error.localizedDescription]
                )
                throw error
            }

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .paymentRequested,
                eventType: .paymentRequested
            )
            self.currentStage = .paymentRequested
            
        case .triggerShutter:
            guard currentStage == .capturing, let sessionId = activeSessionId else { throw WorkflowError.invalidTransition }
            let correlationId = CorrelationID()
            self.currentCorrelationId = correlationId

            do {
                try await camera.requestCapture(correlationId: correlationId)
            } catch {
                SessionAuditTrail.append(
                    sessionId: sessionId.rawValue,
                    stage: .capturing,
                    eventType: .cameraFailure,
                    metadata: ["error": error.localizedDescription]
                )
                throw error  // re-throw — error type harus preserved (Failure Injection Test)
            }

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .editingPreview,
                eventType: .photoCaptured
            )
            self.currentStage = .editingPreview
            
        case .selectFilter(let filterId):
            guard currentStage == .editingPreview, let correlationId = currentCorrelationId else { return }
            let filterRef = FilterReference(filterId: filterId, lutFileName: "luts/\(filterId).cube")
            _ = EditingConfiguration(filter: filterRef)
            
            // Re-render Preview
            _ = try await editing.requestPreview(photoInput: "captured_photo.jpg", correlationId: correlationId)
            
        case .acceptPreview:
            guard currentStage == .editingPreview,
                  let sessionId = activeSessionId,
                  let correlationId = currentCorrelationId else { return }
            self.currentStage = .exporting

            // Render Export Full Resolution
            let exportResult = try await editing.requestExport(photoInput: "captured_photo.jpg", correlationId: correlationId)
            self.activePhotoId = exportResult.photoId
            self.activeOutputReference = exportResult.outputReference

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .exporting,
                eventType: .exportCompleted
            )

            // Transition to Payment
            do {
                try await payment.prepare(configuration: PaymentConfiguration())
                _ = try await payment.requestPayment(
                    sessionId: sessionId,
                    correlationId: correlationId,
                    amount: PaymentAmount(amountValue: 35000, method: .localQRIS),
                    method: .localQRIS
                )
            } catch {
                SessionAuditTrail.append(
                    sessionId: sessionId.rawValue,
                    stage: .exporting,
                    eventType: .paymentFailed,
                    metadata: ["error": error.localizedDescription]
                )
                throw error
            }

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .paymentRequested,
                eventType: .paymentRequested
            )
            self.currentStage = .paymentRequested
            
        case .confirmPaymentSuccess:
            guard currentStage == .paymentRequested,
                  let sessionId = activeSessionId,
                  let correlationId = currentCorrelationId,
                  let photoId = activePhotoId,
                  let outputRef = activeOutputReference else { return }

            // POIN KRITIS: Payment confirmed — tulis audit SEBELUM delivery dimulai
            // Invariant 20: trail ini yang dipakai untuk recovery jika crash terjadi setelah ini
            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .paymentConfirmed,
                eventType: .paymentConfirmed,
                metadata: [
                    "photoId": photoId.rawValue,
                    "outputRef": outputRef
                ]
            )
            self.currentStage = .paymentConfirmed

            // Transition to Delivery
            do {
                try await delivery.prepare(configuration: DeliveryConfiguration())
                _ = try await delivery.requestDelivery(
                    sessionId: sessionId,
                    correlationId: correlationId,
                    photoId: photoId,
                    assetPath: outputRef,
                    channel: .localBonjourWiFiServer
                )
            } catch {
                SessionAuditTrail.append(
                    sessionId: sessionId.rawValue,
                    stage: .paymentConfirmed,
                    eventType: .deliveryFailure,
                    metadata: ["error": error.localizedDescription]
                )
                // TIDAK reset ke landing — customer sudah bayar! (Failure Injection Test)
                throw error
            }

            SessionAuditTrail.append(
                sessionId: sessionId.rawValue,
                stage: .deliveryDispatch,
                eventType: .deliveryStarted
            )
            self.currentStage = .deliveryDispatch
            
        case .finishSession:
            if let sessionId = activeSessionId {
                SessionAuditTrail.append(
                    sessionId: sessionId.rawValue,
                    stage: .sessionCompleted,
                    eventType: .sessionCompleted
                )
                SessionAuditTrail.close(sessionId: sessionId.rawValue, status: .completed)
            }
            await resetToLanding()
            
        case .cancelSessionByOperator:
            if let sessionId = activeSessionId {
                SessionAuditTrail.append(
                    sessionId: sessionId.rawValue,
                    stage: currentStage,
                    eventType: .operatorCancel
                )
                let finalStatus: AuditTrailFooter.FinalStatus = hasFinancialTransaction
                    ? .completed  // payment pernah confirmed — tidak di-abandon
                    : .cancelledByOperator
                SessionAuditTrail.close(sessionId: sessionId.rawValue, status: finalStatus)
            }
            await resetToLanding()
        }
    }
    
    // MARK: - Generic Event Bus Handler (Event-to-Command Table)
    
    public func processEvent(_ envelope: EventEnvelope<Data>) async throws {
        // Event Contract Mapping: Event -> Stage Transition
        switch envelope.eventName {
        case "Payment.Confirmed":
            try await handleIntent(.confirmPaymentSuccess)
        case "Delivery.Completed":
            self.currentStage = .sessionCompleted
        default:
            break
        }
    }
    
    // MARK: - Reset State
    
    public func resetToLanding() async {
        await camera.stopSession()
        await editing.stopSession()
        await payment.stopSession()
        await delivery.stopSession()
        
        self.activeSessionId = nil
        self.currentCorrelationId = nil
        self.activePhotoId = nil
        self.activeOutputReference = nil
        self.currentStage = .landing
    }

    private func getOrCreateActiveSession() -> SessionID {
        if let existing = activeSessionId {
            return existing
        }
        let newSession = SessionID()
        self.activeSessionId = newSession
        SessionAuditTrail.create(sessionId: newSession.rawValue)
        SessionAuditTrail.append(
            sessionId: newSession.rawValue,
            stage: currentStage,
            eventType: .sessionStarted
        )
        return newSession
    }
}

// MARK: - Workflow Errors
public enum WorkflowError: Error, LocalizedError, Equatable {
    case sessionNotActive
    case invalidTransition
    
    public var errorDescription: String? {
        switch self {
        case .sessionNotActive: return "Sesi workflow belum diinisialisasi."
        case .invalidTransition: return "Transisi stage workflow tidak valid."
        }
    }
}
