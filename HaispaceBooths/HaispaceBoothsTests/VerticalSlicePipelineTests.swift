// VerticalSlicePipelineTests.swift
// HaispaceBoothsTests — Pipeline Integration
//
// End-to-End Vertical Slice Test (Capture -> Edit -> P2P Transfer).
// Membuktikan integrasi 3 Capability acuan emas (Camera, Editing, P2P) 
// dan ketahanan alur kegagalan (Failure-Path & Resiliency Testing).

import XCTest
@testable import HaispaceBooths

final class VerticalSlicePipelineTests: XCTestCase {
    
    var mockCameraRuntime: MockCameraRuntime!
    var cameraCapability: CameraCapability!
    
    var mockEditingRuntime: MockEditingRuntime!
    var editingCapability: EditingCapability!
    
    var mockP2PRuntime: MockP2PRuntime!
    var p2pCapability: P2PCapability!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 1. Setup Camera Capability
        mockCameraRuntime = MockCameraRuntime()
        cameraCapability = CameraCapability(runtime: mockCameraRuntime)
        
        // 2. Setup Editing Capability
        mockEditingRuntime = MockEditingRuntime()
        editingCapability = EditingCapability(runtime: mockEditingRuntime)
        
        // 3. Setup P2P Capability
        mockP2PRuntime = MockP2PRuntime()
        p2pCapability = P2PCapability(runtime: mockP2PRuntime)
    }
    
    // MARK: - Happy Path End-to-End Test
    
    func testEndToEndVerticalSlicePipelineSuccess() async throws {
        let sessionId = SessionID(rawValue: "SESS-VERTICAL-001")
        let correlationId = CorrelationID(rawValue: "CORR-VERTICAL-001")
        
        // STAGE 1: CAMERA CAPABILITY
        let cameraConfig = CameraConfiguration(captureMode: .singlePhoto)
        try await cameraCapability.prepare(configuration: cameraConfig)
        try await cameraCapability.startSession(sessionId: sessionId)
        try await cameraCapability.requestCapture(correlationId: correlationId)
        
        // STAGE 2: EDITING CAPABILITY
        let editingConfig = EditingConfiguration(exportFormat: .jpeg)
        try await editingCapability.prepare(sessionId: sessionId, configuration: editingConfig)
        let exportResult = try await editingCapability.requestExport(
            photoInput: "raw_captured_photo.jpg",
            correlationId: correlationId
        )
        
        // STAGE 3: P2P CAPABILITY
        let p2pConfig = P2PConfiguration()
        try await p2pCapability.prepare(configuration: p2pConfig)
        let peer = try await p2pCapability.startSession(sessionId: sessionId)
        XCTAssertEqual(peer.role, "iPhoneCamera")
        
        let transferId = TransferID(rawValue: "XFER-VERTICAL-001")
        let transferResult = try await p2pCapability.requestTransfer(
            transferId: transferId,
            payloadPath: exportResult.outputReference
        )
        
        // VERIFICATION
        XCTAssertEqual(transferResult.transferId, transferId)
        XCTAssertEqual(transferResult.sessionId, sessionId)
        XCTAssertGreaterThan(transferResult.totalBytes, 0)
    }
    
    // MARK: - Failure Path & Resiliency Tests
    
    func testPipelineFailureInEditingStateResetsCleanly() async throws {
        let sessionId = SessionID(rawValue: "SESS-FAIL-001")
        let correlationId = CorrelationID(rawValue: "CORR-FAIL-001")
        
        // Stage 1: Camera Succeeds
        try await cameraCapability.prepare(configuration: CameraConfiguration())
        try await cameraCapability.startSession(sessionId: sessionId)
        try await cameraCapability.requestCapture(correlationId: correlationId)
        
        // Stage 2: Editing Runtime Fails
        mockEditingRuntime.shouldFailRender = true
        try await editingCapability.prepare(sessionId: sessionId, configuration: EditingConfiguration())
        
        do {
            _ = try await editingCapability.requestExport(photoInput: "raw_photo.jpg", correlationId: correlationId)
            XCTFail("Harus melempar EditingCapabilityError.exportFailed")
        } catch let error as EditingCapabilityError {
            // Verify Error Handling & Traceability
            XCTAssertNotNil(error.errorDescription)
            
            // Verify Health Snapshot transitions to Degraded
            let health = await editingCapability.healthSnapshot
            XCTAssertEqual(health.status, .degraded)
            XCTAssertNotNil(health.lastErrorMessage)
            
            // Verify Capability can Recover & Retry without Recapturing Photo
            mockEditingRuntime.shouldFailRender = false
            let retryResult = try await editingCapability.requestExport(photoInput: "raw_photo.jpg", correlationId: correlationId)
            XCTAssertEqual(retryResult.exportFormat, .jpeg)
        }
    }
    
    func testPipelineP2PDisconnectAndSuccessfulResume() async throws {
        let sessionId = SessionID(rawValue: "SESS-RESUME-001")
        let transferId = TransferID(rawValue: "XFER-RESUME-001")
        
        // Stage 3: P2P Transport Drops Mid-Transfer
        try await p2pCapability.prepare(configuration: P2PConfiguration())
        _ = try await p2pCapability.startSession(sessionId: sessionId)
        
        mockP2PRuntime.shouldFailTransfer = true
        
        do {
            _ = try await p2pCapability.requestTransfer(transferId: transferId, payloadPath: "export.jpg")
            XCTFail("Harus melempar P2PCapabilityError.transportFailed")
        } catch {
            let p2pHealth = await p2pCapability.healthSnapshot
            XCTAssertEqual(p2pHealth.status, .degraded)
            
            // Execute Successful Resume Action
            mockP2PRuntime.shouldFailTransfer = false
            let resumeResult = try await p2pCapability.requestResume(transferId: transferId, fromChunkIndex: 128)
            
            XCTAssertTrue(resumeResult.isResumed)
            XCTAssertEqual(resumeResult.transferId, transferId)
        }
    }
}
