// ProductAcceptanceTests.swift
// HaispaceBoothsTests — End-to-End Product Acceptance Suite
//
// Acceptance Tests tingkat tinggi (Given-When-Then BDD style)
// memverifikasi janji produk Haispace Kiosk Photobooth Platform.

import XCTest
@testable import HaispaceBooths

final class ProductAcceptanceTests: XCTestCase {
    
    var orchestrator: WorkflowOrchestrator!
    var mockCameraRuntime: MockCameraRuntime!
    var mockEditingRuntime: MockEditingRuntime!
    var mockPaymentRuntime: MockPaymentRuntime!
    var mockDeliveryRuntime: MockDeliveryRuntime!
    var mockP2PRuntime: MockP2PRuntime!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockCameraRuntime = MockCameraRuntime()
        mockEditingRuntime = MockEditingRuntime()
        mockPaymentRuntime = MockPaymentRuntime()
        mockDeliveryRuntime = MockDeliveryRuntime()
        mockP2PRuntime = MockP2PRuntime()
        
        let camera = CameraCapability(runtime: mockCameraRuntime)
        let editing = EditingCapability(runtime: mockEditingRuntime)
        let payment = PaymentCapability(runtime: mockPaymentRuntime)
        let delivery = DeliveryCapability(runtime: mockDeliveryRuntime)
        let p2p = P2PCapability(runtime: mockP2PRuntime)
        
        orchestrator = WorkflowOrchestrator(
            camera: camera,
            editing: editing,
            payment: payment,
            delivery: delivery,
            p2p: p2p
        )
    }
    
    // MARK: - Product Acceptance Test (Given - When - Then)
    
    func testEndToEndPhotoboothProductAcceptancePromise() async throws {
        // -------------------------------------------------------------------
        // GIVEN: Tamu mendaftar di Kiosk dan memilih Paket Premium Graduation
        // -------------------------------------------------------------------
        var stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .landing)
        
        try await orchestrator.handleIntent(.startGuestRegistration)
        try await orchestrator.handleIntent(.guestSubmittedInfo(name: "Adelia Wisudawati", email: "adelia@academics.ac.id"))
        try await orchestrator.handleIntent(.selectPackage(packageId: "GRADUATION_PREMIUM"))
        try await orchestrator.handleIntent(.selectTemplate(frameId: "FRAME_GRADUATION_2026"))
        
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .capturing)
        
        // -------------------------------------------------------------------
        // WHEN: Tamu mengambil foto, memilih filter, dan menyetujui preview
        // -------------------------------------------------------------------
        try await orchestrator.handleIntent(.triggerShutter)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .editingPreview)
        
        try await orchestrator.handleIntent(.selectFilter(filterId: "LUT_VINTAGE_WARM"))
        try await orchestrator.handleIntent(.acceptPreview)
        
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .paymentRequested)
        
        // -------------------------------------------------------------------
        // AND WHEN: Pembayaran QRIS lokal dikonfirmasi oleh operator/sistem
        // -------------------------------------------------------------------
        try await orchestrator.handleIntent(.confirmPaymentSuccess)
        
        // -------------------------------------------------------------------
        // THEN: Foto ber-frame & LUT ter-export, terdistribusi via WiFi server,
        //       dan Kiosk Photobooth kembali ke mode Standby Landing.
        // -------------------------------------------------------------------
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .deliveryDispatch)
        
        // Final Reset
        try await orchestrator.handleIntent(.finishSession)
        stage = await orchestrator.currentStage
        XCTAssertEqual(stage, .landing)
        
        // VERIFY HEALTH: Seluruh 5 Capability kembali ke status Healthy
        let health = await orchestrator.healthSnapshot
        XCTAssertEqual(health.currentStage, .landing)
        XCTAssertEqual(health.activeSessionCount, 0)
    }
}
