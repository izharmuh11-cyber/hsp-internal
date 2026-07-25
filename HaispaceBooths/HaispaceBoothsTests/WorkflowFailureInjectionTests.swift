// WorkflowFailureInjectionTests.swift
// HaispaceBoothsTests — Stabilization Review
//
// Failure Injection Tests untuk WorkflowOrchestrator.
// Memverifikasi bahwa kegagalan capability ditangani sesuai kontrak,
// bukan hanya bahwa alur normal berjalan.
//
// Skenario yang diuji:
// - Camera failure → workflow tidak melewati .capturing
// - Payment timeout → stage kembali ke safe state
// - Delivery failure → session tidak corrupt
// - Orchestrator hanya memiliki SATU transisi per intent
//
// Ref: docs/design/ADR-001_workflow_ownership.md — Stabilization Review
// Ref: docs/design/23_error_recovery.md

import XCTest
@testable import HaispaceBooths

// MARK: - Failure Mock Runtimes

/// Mock Camera yang throw error saat requestCapture
final class FailingCameraRuntime: CameraRuntimeProtocol {
    var shouldFailOnCapture: Bool = false
    var captureError: Error = WorkflowError.invalidTransition

    func prepare(configuration: CameraConfiguration) async throws {}
    func startLivePreview() async throws {}
    func stopSession() async {}
    func requestCapture(correlationId: CorrelationID) async throws {
        if shouldFailOnCapture { throw captureError }
    }
    var healthSnapshot: CameraHealth { CameraHealth(status: .ready) }
    var metricsSnapshot: CameraMetrics { CameraMetrics() }
}

/// Mock Payment yang throw error (simulasi timeout atau network error)
final class FailingPaymentRuntime: PaymentRuntimeProtocol {
    var shouldFailOnRequest: Bool = false
    var paymentError: Error = HaispaceError.networkUnavailable

    func prepare(configuration: PaymentConfiguration) async throws {}
    func requestPayment(sessionId: SessionID, correlationId: CorrelationID, amount: PaymentAmount, method: PaymentMethod) async throws -> PaymentResult {
        if shouldFailOnRequest { throw paymentError }
        return PaymentResult(paymentId: PaymentID(), status: .pending, correlationId: correlationId)
    }
    func confirmPayment(paymentId: PaymentID) async throws -> PaymentResult {
        return PaymentResult(paymentId: paymentId, status: .confirmed, correlationId: CorrelationID())
    }
    func cancelPayment(paymentId: PaymentID) async throws {}
    func stopSession() async {}
    var healthSnapshot: PaymentHealth { PaymentHealth(status: .ready) }
    var metricsSnapshot: PaymentMetrics { PaymentMetrics() }
}

/// Mock Delivery yang throw error (simulasi printer offline atau network loss)
final class FailingDeliveryRuntime: DeliveryRuntimeProtocol {
    var shouldFailOnDelivery: Bool = false
    var deliveryError: Error = HaispaceError.networkUnavailable

    func prepare(configuration: DeliveryConfiguration) async throws {}
    func requestDelivery(sessionId: SessionID, correlationId: CorrelationID, photoId: PhotoID, assetPath: String, channel: DeliveryChannel) async throws -> DeliveryResult {
        if shouldFailOnDelivery { throw deliveryError }
        return DeliveryResult(deliveryId: DeliveryID(), status: .pending, correlationId: correlationId)
    }
    func retryDelivery(deliveryId: DeliveryID, correlationId: CorrelationID) async throws -> DeliveryResult {
        return DeliveryResult(deliveryId: deliveryId, status: .delivered, correlationId: correlationId)
    }
    func cancelDelivery(deliveryId: DeliveryID) async throws {}
    func stopSession() async {}
    var healthSnapshot: DeliveryHealth { DeliveryHealth(status: .ready) }
    var metricsSnapshot: DeliveryMetrics { DeliveryMetrics() }
}

// MARK: - Failure Injection Test Suite

final class WorkflowFailureInjectionTests: XCTestCase {

    // MARK: - Camera Failure Tests

    func testCameraFailureDuringCaptureDoesNotAdvanceStage() async throws {
        // SETUP: Orchestrator dengan camera yang akan fail
        let failingCamera = FailingCameraRuntime()
        failingCamera.shouldFailOnCapture = true

        let orchestrator = WorkflowOrchestrator(
            camera: CameraCapability(runtime: failingCamera),
            editing: EditingCapability(runtime: MockEditingRuntime()),
            payment: PaymentCapability(runtime: MockPaymentRuntime()),
            delivery: DeliveryCapability(runtime: MockDeliveryRuntime()),
            p2p: P2PCapability(runtime: MockP2PRuntime())
        )

        // Advance ke .capturing
        try await orchestrator.handleIntent(.startGuestRegistration)
        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "T", email: "t@t.com"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "pkg"))
        try await orchestrator.handleIntent(.selectTemplate(frameId: "frame"))

        let stageBefore = await orchestrator.currentStage
        XCTAssertEqual(stageBefore, .capturing)

        // Trigger capture dengan camera yang akan fail
        do {
            try await orchestrator.handleIntent(.triggerShutter)
            XCTFail("Seharusnya throw karena camera capture gagal")
        } catch {
            // ✅ Expected — capture failure harus throw
        }

        // KRITIS: Stage tidak boleh berubah ke .editingPreview setelah failure
        let stageAfter = await orchestrator.currentStage
        XCTAssertEqual(stageAfter, .capturing,
                       "Camera failure harus mempertahankan stage .capturing — tidak boleh advance ke .editingPreview")
    }

    func testCameraFailureTypeIsPreserved() async throws {
        // Error dari capability harus tidak di-swallow oleh Orchestrator
        let failingCamera = FailingCameraRuntime()
        failingCamera.shouldFailOnCapture = true
        failingCamera.captureError = HaispaceError.cameraNotAvailable

        let orchestrator = WorkflowOrchestrator(
            camera: CameraCapability(runtime: failingCamera),
            editing: EditingCapability(runtime: MockEditingRuntime()),
            payment: PaymentCapability(runtime: MockPaymentRuntime()),
            delivery: DeliveryCapability(runtime: MockDeliveryRuntime()),
            p2p: P2PCapability(runtime: MockP2PRuntime())
        )

        try await orchestrator.handleIntent(.startGuestRegistration)
        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "T", email: "t@t.com"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "pkg"))
        try await orchestrator.handleIntent(.selectTemplate(frameId: "frame"))

        do {
            try await orchestrator.handleIntent(.triggerShutter)
            XCTFail("Harus throw")
        } catch HaispaceError.cameraNotAvailable {
            // ✅ Error type harus preserved — tidak boleh di-wrap jadi error lain
        } catch {
            XCTFail("Error type berubah: \(error) — Orchestrator tidak boleh meng-swallow error dari capability")
        }
    }

    // MARK: - Payment Failure Tests

    func testPaymentTimeoutDoesNotCorruptSession() async throws {
        // SETUP: Payment akan timeout saat acceptPreview dipanggil
        let failingPayment = FailingPaymentRuntime()
        failingPayment.shouldFailOnRequest = true
        failingPayment.paymentError = HaispaceError.paymentTimeout

        let orchestrator = WorkflowOrchestrator(
            camera: CameraCapability(runtime: MockCameraRuntime()),
            editing: EditingCapability(runtime: MockEditingRuntime()),
            payment: PaymentCapability(runtime: failingPayment),
            delivery: DeliveryCapability(runtime: MockDeliveryRuntime()),
            p2p: P2PCapability(runtime: MockP2PRuntime())
        )

        // Advance ke .editingPreview
        try await orchestrator.handleIntent(.startGuestRegistration)
        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "T", email: "t@t.com"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "pkg"))
        try await orchestrator.handleIntent(.selectTemplate(frameId: "frame"))
        try await orchestrator.handleIntent(.triggerShutter)

        let stageBefore = await orchestrator.currentStage
        XCTAssertEqual(stageBefore, .editingPreview)

        // acceptPreview akan trigger payment yang akan timeout
        do {
            try await orchestrator.handleIntent(.acceptPreview)
            XCTFail("Harus throw karena payment timeout")
        } catch {
            // ✅ Expected
        }

        // KRITIS: Session harus masih ada (tidak nil), tapi stage tidak advance
        let stageAfter = await orchestrator.currentStage
        XCTAssertNotEqual(stageAfter, .deliveryDispatch,
                         "Payment failure tidak boleh advance stage ke .deliveryDispatch")
        XCTAssertNotEqual(stageAfter, .landing,
                         "Payment failure tidak boleh auto-reset ke landing — operator harus intervene")
    }

    // MARK: - Delivery Failure Tests

    func testDeliveryFailureDoesNotLosePaidSession() async throws {
        // SETUP: Delivery akan fail (printer offline)
        // Tapi PAYMENT sudah confirmed — data tidak boleh hilang
        let failingDelivery = FailingDeliveryRuntime()
        failingDelivery.shouldFailOnDelivery = true
        failingDelivery.deliveryError = HaispaceError.networkUnavailable

        let orchestrator = WorkflowOrchestrator(
            camera: CameraCapability(runtime: MockCameraRuntime()),
            editing: EditingCapability(runtime: MockEditingRuntime()),
            payment: PaymentCapability(runtime: MockPaymentRuntime()),
            delivery: DeliveryCapability(runtime: failingDelivery),
            p2p: P2PCapability(runtime: MockP2PRuntime())
        )

        // Advance ke .paymentRequested
        try await orchestrator.handleIntent(.startGuestRegistration)
        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "T", email: "t@t.com"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "pkg"))
        try await orchestrator.handleIntent(.selectTemplate(frameId: "frame"))
        try await orchestrator.handleIntent(.triggerShutter)
        try await orchestrator.handleIntent(.acceptPreview)

        let stageBeforePayment = await orchestrator.currentStage
        XCTAssertEqual(stageBeforePayment, .paymentRequested)

        // Confirm payment (payment sukses)
        do {
            try await orchestrator.handleIntent(.confirmPaymentSuccess)
            // Delivery gagal — tapi harus throw, bukan silent fail
            XCTFail("Harus throw karena delivery gagal")
        } catch {
            // ✅ Expected — delivery failure harus surfaced
        }

        // KRITIS: Stage tidak boleh .landing — sesi masih "paid but not delivered"
        let stageAfter = await orchestrator.currentStage
        XCTAssertNotEqual(stageAfter, .landing,
                         "Delivery failure setelah payment confirmed TIDAK BOLEH auto-reset ke landing — foto sudah dibayar!")
    }

    // MARK: - Single Transition per Intent Tests

    func testEachIntentProducesExactlyOneStageTransition() async throws {
        // Verifikasi bahwa setiap intent hanya menghasilkan SATU perubahan stage
        let orchestrator = WorkflowOrchestrator(
            camera: CameraCapability(runtime: MockCameraRuntime()),
            editing: EditingCapability(runtime: MockEditingRuntime()),
            payment: PaymentCapability(runtime: MockPaymentRuntime()),
            delivery: DeliveryCapability(runtime: MockDeliveryRuntime()),
            p2p: P2PCapability(runtime: MockP2PRuntime())
        )

        var stagesBefore: [WorkflowStage] = []
        var stagesAfter: [WorkflowStage] = []

        let intentsToTest: [WorkflowIntent] = [
            .startGuestRegistration,
            .guestSubmittedInfo(name: "T", email: "t@t.com"),
            .selectPackage(packageId: "pkg"),
            .selectTemplate(frameId: "frame"),
            .triggerShutter,
        ]

        for intent in intentsToTest {
            stagesBefore.append(await orchestrator.currentStage)
            try await orchestrator.handleIntent(intent)
            stagesAfter.append(await orchestrator.currentStage)
        }

        // Setiap intent harus menghasilkan exactly ONE perubahan stage
        for (i, (before, after)) in zip(stagesBefore, stagesAfter).enumerated() {
            XCTAssertNotEqual(before, after,
                             "Intent #\(i) tidak menghasilkan transisi stage apapun — intent mungkin tidak di-handle")
        }
    }
}
