// NoOpCapabilities.swift
// HaispaceBooths — Core/Capabilities
//
// Implementasi NoOp (safe no-operation) untuk semua capability protocols.
// Digunakan sebagai safe default di WorkflowOrchestrator sebelum real capabilities di-wire.
//
// PRINSIP: Lebih baik operasi yang tidak melakukan apa-apa daripada crash atau nil crash.
// Semua method log peringatan agar mudah dideteksi saat testing.
//
// Ref: docs/design/ADR-001_workflow_ownership.md — Orchestrator Init

import Foundation

// MARK: - NoOpCameraCapability

public actor NoOpCameraCapability: @preconcurrency CameraCapabilityProtocol {
    public var healthSnapshot: CameraHealth { CameraHealth(status: .healthy) }
    public var metricsSnapshot: CameraMetrics { CameraMetrics() }

    public func prepare(configuration: CameraConfiguration) async throws {
        HaispaceLogger.warning("NoOpCameraCapability.prepare() dipanggil — belum di-wire ke real capability", category: "capability")
    }
    public func startSession(sessionId: SessionID) async throws {
        HaispaceLogger.warning("NoOpCameraCapability.startSession() dipanggil", category: "capability")
    }
    public func stopSession() async {
        HaispaceLogger.debug("NoOpCameraCapability.stopSession()", category: "capability")
    }
    public func requestCapture(correlationId: CorrelationID) async throws {
        HaispaceLogger.warning("NoOpCameraCapability.requestCapture() dipanggil", category: "capability")
    }
}

// MARK: - NoOpEditingCapability

public actor NoOpEditingCapability: @preconcurrency EditingCapabilityProtocol {
    public var healthSnapshot: EditingHealth { EditingHealth(status: .healthy) }
    public var metricsSnapshot: EditingMetrics { EditingMetrics() }

    public func prepare(sessionId: SessionID, configuration: EditingConfiguration) async throws {
        HaispaceLogger.warning("NoOpEditingCapability.prepare() dipanggil", category: "capability")
    }
    public func requestPreview(photoInput: String, correlationId: CorrelationID) async throws -> PreviewResult {
        HaispaceLogger.warning("NoOpEditingCapability.requestPreview() dipanggil", category: "capability")
        return PreviewResult(photoId: PhotoID(), outputReference: "", renderDurationMs: 0.0)
    }
    public func requestExport(photoInput: String, correlationId: CorrelationID) async throws -> ExportResult {
        HaispaceLogger.warning("NoOpEditingCapability.requestExport() dipanggil", category: "capability")
        return ExportResult(photoId: PhotoID(), outputReference: "", renderDurationMs: 0.0, fileSizeBytes: 0, exportFormat: .jpeg)
    }
    public func stopSession() async {
        HaispaceLogger.debug("NoOpEditingCapability.stopSession()", category: "capability")
    }
}

// MARK: - NoOpPaymentCapability

public actor NoOpPaymentCapability: @preconcurrency PaymentCapabilityProtocol {
    public var healthSnapshot: PaymentHealth { PaymentHealth(status: .healthy) }
    public var metricsSnapshot: PaymentMetrics { PaymentMetrics() }

    public func prepare(configuration: PaymentConfiguration) async throws {
        HaispaceLogger.warning("NoOpPaymentCapability.prepare() dipanggil", category: "capability")
    }
    public func requestPayment(
        sessionId: SessionID,
        correlationId: CorrelationID,
        amount: PaymentAmount,
        method: PaymentCapabilityMethod
    ) async throws -> PaymentResult {
        HaispaceLogger.warning("NoOpPaymentCapability.requestPayment() dipanggil", category: "capability")
        return PaymentResult(paymentId: PaymentID(), sessionId: sessionId, amount: amount, method: method, payloadString: "")
    }
    public func confirmPayment(paymentId: PaymentID) async throws -> PaymentResult {
        HaispaceLogger.warning("NoOpPaymentCapability.confirmPayment() dipanggil", category: "capability")
        let dummyAmount = PaymentAmount(amountValue: 0, method: .localQRIS)
        return PaymentResult(paymentId: paymentId, sessionId: SessionID(), amount: dummyAmount, method: .localQRIS, payloadString: "", confirmedAt: Date())
    }
    public func cancelPayment(paymentId: PaymentID) async throws {
        HaispaceLogger.warning("NoOpPaymentCapability.cancelPayment() dipanggil", category: "capability")
    }
    public func stopSession() async {
        HaispaceLogger.debug("NoOpPaymentCapability.stopSession()", category: "capability")
    }
}

// MARK: - NoOpDeliveryCapability

public actor NoOpDeliveryCapability: @preconcurrency DeliveryCapabilityProtocol {
    public var healthSnapshot: DeliveryHealth { DeliveryHealth(status: .healthy) }
    public var metricsSnapshot: DeliveryMetrics { DeliveryMetrics() }

    public func prepare(configuration: DeliveryConfiguration) async throws {
        HaispaceLogger.warning("NoOpDeliveryCapability.prepare() dipanggil", category: "capability")
    }
    public func requestDelivery(
        sessionId: SessionID,
        correlationId: CorrelationID,
        photoId: PhotoID,
        assetPath: String,
        channel: DeliveryChannel
    ) async throws -> DeliveryResult {
        HaispaceLogger.warning("NoOpDeliveryCapability.requestDelivery() dipanggil", category: "capability")
        return DeliveryResult(deliveryId: DeliveryID(), sessionId: sessionId, photoId: photoId, channel: channel, deliveryReference: "")
    }
    public func retryDelivery(deliveryId: DeliveryID, correlationId: CorrelationID) async throws -> DeliveryResult {
        HaispaceLogger.warning("NoOpDeliveryCapability.retryDelivery() dipanggil", category: "capability")
        return DeliveryResult(deliveryId: deliveryId, sessionId: SessionID(), photoId: PhotoID(), channel: .localBonjourWiFiServer, deliveryReference: "")
    }
    public func cancelDelivery(deliveryId: DeliveryID) async throws {
        HaispaceLogger.warning("NoOpDeliveryCapability.cancelDelivery() dipanggil", category: "capability")
    }
    public func stopSession() async {
        HaispaceLogger.debug("NoOpDeliveryCapability.stopSession()", category: "capability")
    }
}

// MARK: - NoOpP2PCapability

public actor NoOpP2PCapability: @preconcurrency P2PCapabilityProtocol {
    public var healthSnapshot: P2PHealth { P2PHealth(status: .healthy) }
    public var metricsSnapshot: P2PMetrics { P2PMetrics() }

    public func prepare(configuration: P2PConfiguration) async throws {
        HaispaceLogger.warning("NoOpP2PCapability.prepare() dipanggil", category: "capability")
    }
    public func startSession(sessionId: SessionID) async throws -> P2PPeerInfo {
        HaispaceLogger.warning("NoOpP2PCapability.startSession() dipanggil", category: "capability")
        return P2PPeerInfo(deviceId: "noop", deviceName: "NoOp Peer", role: "iPhoneCamera", activeTransport: .multipeerConnectivity)
    }
    public func stopSession() async {
        HaispaceLogger.debug("NoOpP2PCapability.stopSession()", category: "capability")
    }
    public func requestTransfer(transferId: TransferID, payloadPath: String) async throws -> P2PTransferResult {
        HaispaceLogger.warning("NoOpP2PCapability.requestTransfer() dipanggil", category: "capability")
        return P2PTransferResult(transferId: transferId, sessionId: SessionID(), outputReference: "", totalBytes: 0, transferDurationMs: 0)
    }
    public func requestResume(transferId: TransferID, fromChunkIndex: UInt32) async throws -> P2PTransferResult {
        HaispaceLogger.warning("NoOpP2PCapability.requestResume() dipanggil", category: "capability")
        return P2PTransferResult(transferId: transferId, sessionId: SessionID(), outputReference: "", totalBytes: 0, transferDurationMs: 0)
    }
}
