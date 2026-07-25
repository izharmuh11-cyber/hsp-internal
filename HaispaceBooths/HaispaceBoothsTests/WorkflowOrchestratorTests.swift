// WorkflowOrchestratorTests.swift
// HaispaceBoothsTests — Workflow Integration + Architecture Regression
//
// Integration Tests untuk WorkflowOrchestrator Business State Machine.
// Termasuk Architecture Regression Tests yang menjaga kontrak ADR-001.
//
// Ref: docs/design/ADR-001_workflow_ownership.md

import XCTest
@testable import HaispaceBooths

final class WorkflowOrchestratorTests: XCTestCase {

    var orchestrator: WorkflowOrchestrator!

    override func setUp() async throws {
        try await super.setUp()

        let mockCamera = CameraCapability(runtime: MockCameraRuntime())
        let mockEditing = EditingCapability(runtime: MockEditingRuntime())
        let mockPayment = PaymentCapability(runtime: MockPaymentRuntime())
        let mockDelivery = DeliveryCapability(runtime: MockDeliveryRuntime())
        let mockP2P = P2PCapability(runtime: MockP2PRuntime())

        orchestrator = WorkflowOrchestrator(
            camera: mockCamera,
            editing: mockEditing,
            payment: mockPayment,
            delivery: mockDelivery,
            p2p: mockP2P
        )
    }

    // MARK: - Happy Path Test

    func testCompleteGuestJourneyWorkflow() async throws {
        var stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .landing)

        try await orchestrator.handleIntent(.startGuestRegistration)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .guestRegistration)

        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "Tamu Haispace", email: "tamu@haispace.id"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "THE_STAGE_PREMIUM"))
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .templateSelection)

        try await orchestrator.handleIntent(.selectTemplate(frameId: "GRADUATION_2026"))
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .capturing)

        try await orchestrator.handleIntent(.triggerShutter)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .editingPreview)

        try await orchestrator.handleIntent(.acceptPreview)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .paymentRequested)

        try await orchestrator.handleIntent(.confirmPaymentSuccess)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .deliveryDispatch)

        try await orchestrator.handleIntent(.finishSession)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .landing)
    }

    // MARK: - Architecture Regression Tests (ADR-001)
    // Menjaga kontrak: setiap WorkflowStage harus punya KioskRoute mapping.
    // Test-test ini akan FAIL otomatis jika ada WorkflowStage baru yang belum di-mapping.

    func testAllWorkflowStagesHaveKioskRouteMapping() {
        // REGRESSION GUARD: setiap stage harus bisa di-map ke KioskRoute
        // Jika WorkflowStage baru ditambahkan tanpa update WorkflowRouteMapper,
        // test ini fail — compiler exhaustiveness check sebagai safety net kedua
        for stage in WorkflowStage.allCases {
            let route = WorkflowRouteMapper.route(for: stage)
            XCTAssertNotNil(
                route,
                "WorkflowStage.\(stage) tidak memiliki KioskRoute mapping di WorkflowRouteMapper!"
            )
        }
    }

    func testAllWorkflowStagesMappingIsExhaustive() {
        let stageCount = WorkflowStage.allCases.count
        XCTAssertGreaterThan(stageCount, 0, "WorkflowStage.allCases tidak boleh kosong")

        // Setiap stage harus bisa di-map tanpa crash/throw
        XCTAssertNoThrow(
            WorkflowStage.allCases.forEach { _ = WorkflowRouteMapper.route(for: $0) },
            "WorkflowRouteMapper.route() gagal untuk salah satu WorkflowStage"
        )
    }

    func testInvalidTransitionFromLandingToDelivery() async {
        // REGRESSION GUARD: triggerShutter dari landing harus throw
        let stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .landing)

        do {
            try await orchestrator.handleIntent(.triggerShutter)
            XCTFail("Seharusnya throw WorkflowError.invalidTransition dari stage .landing")
        } catch WorkflowError.invalidTransition {
            // ✅ Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPaymentWithoutSessionThrows() async {
        // REGRESSION GUARD: confirmPaymentSuccess tanpa sesi aktif harus throw
        let stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .landing)

        do {
            try await orchestrator.handleIntent(.confirmPaymentSuccess)
            XCTFail("Seharusnya throw karena sesi belum aktif")
        } catch WorkflowError.sessionNotActive {
            // ✅ Expected
        } catch WorkflowError.invalidTransition {
            // ✅ Expected alternative
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCancelSessionAlwaysResetsToLanding() async throws {
        // Mulai workflow sampai capturing
        try await orchestrator.handleIntent(.startGuestRegistration)
        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "Test", email: "t@t.com"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "pkg-001"))
        try await orchestrator.handleIntent(.selectTemplate(frameId: "frame-001"))

        let stageBefore = await orchestrator.currentStage
        XCTAssertEqual(stageBefore, .capturing)

        // Operator cancel → SELALU kembali ke landing
        try await orchestrator.handleIntent(.cancelSessionByOperator)
        let stageAfter = await orchestrator.currentStage
        XCTAssertEqual(stageAfter, .landing, "cancelSessionByOperator harus selalu reset ke .landing")
    }

    // MARK: - WorkflowRouteMapper Contract Tests

    func testLandingMapsToLandingRoute() {
        XCTAssertEqual(WorkflowRouteMapper.route(for: .landing), AppState.KioskRoute.landing)
    }

    func testCapturingMapsToActiveSessionRoute() {
        XCTAssertEqual(WorkflowRouteMapper.route(for: .capturing), AppState.KioskRoute.activeSession)
    }

    func testPaymentStagesMapsToPaymentRoute() {
        XCTAssertEqual(WorkflowRouteMapper.route(for: .paymentRequested), AppState.KioskRoute.payment)
        XCTAssertEqual(WorkflowRouteMapper.route(for: .paymentConfirmed), AppState.KioskRoute.payment)
    }

    func testDeliveryMapsToDeliveryRoute() {
        XCTAssertEqual(WorkflowRouteMapper.route(for: .deliveryDispatch), AppState.KioskRoute.delivery)
    }

    func testSessionCompletedResetsToLandingRoute() {
        // Setelah selesai, harus kembali ke landing untuk tamu berikutnya
        XCTAssertEqual(
            WorkflowRouteMapper.route(for: .sessionCompleted),
            AppState.KioskRoute.landing,
            "sessionCompleted harus mapped ke .landing agar kiosk siap untuk tamu berikutnya"
        )
    }

    func testRecoveryModeMapsToSafeLandingRoute() {
        // RecoveryMode harus mapped ke .landing sebagai safe default
        XCTAssertEqual(
            WorkflowRouteMapper.route(for: .recoveryMode),
            AppState.KioskRoute.landing,
            "recoveryMode harus mapped ke .landing sebagai safe state"
        )
    }
}
