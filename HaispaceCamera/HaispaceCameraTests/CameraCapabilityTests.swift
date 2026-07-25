// CameraCapabilityTests.swift
// HaispaceCameraTests — Capabilities/Camera
//
// Unit & Architecture Compliance Tests untuk CameraCapability Golden Reference.
// Menguji State Machine, Error Handling, Immutable Health/Metrics, & Async Preconditions.

import XCTest
@testable import HaispaceCamera

// MARK: - Mock Camera Runtime (Test Double)
final class MockCameraRuntime: CameraRuntimeProtocol, @unchecked Sendable {
    var isHardwareSetup = false
    var isHardwareSessionRunning = false
    var shouldFailCapture = false
    var mockOutputRef = "local_storage://photo_001.jpg"
    
    func setupHardware(configuration: CameraConfiguration) async throws {
        isHardwareSetup = true
    }
    
    func startHardwareSession() async throws {
        guard isHardwareSetup else { throw CameraCapabilityError.sessionNotStarted }
        isHardwareSessionRunning = true
    }
    
    func stopHardwareSession() async {
        isHardwareSessionRunning = false
    }
    
    func captureStillImage(correlationId: CorrelationID) async throws -> CaptureResult {
        guard isHardwareSessionRunning else {
            throw CameraCapabilityError.sessionNotStarted
        }
        if shouldFailCapture {
            throw CameraCapabilityError.hardwareFailure(reason: "Mock Sensor Error")
        }
        return CaptureResult(
            photoId: PhotoID(rawValue: "PHOTO-001"),
            outputReference: mockOutputRef,
            captureDurationMs: 150.0,
            resolution: "4032x3024",
            fileSizeBytes: 12000000
        )
    }
}

// MARK: - CameraCapabilityTests
final class CameraCapabilityTests: XCTestCase {
    
    var mockRuntime: MockCameraRuntime!
    var capability: CameraCapability!
    
    override func setUp() async throws {
        try await super.setUp()
        mockRuntime = MockCameraRuntime()
        capability = CameraCapability(runtime: mockRuntime)
    }
    
    func testPrepareAndStartSessionSuccess() async throws {
        let config = CameraConfiguration(captureMode: .singlePhoto)
        let sessionId = SessionID(rawValue: "SESS-100")
        
        // Initial Health
        let initialHealth = await capability.healthSnapshot
        XCTAssertEqual(initialHealth.status, .healthy)
        
        // 1. Prepare
        try await capability.prepare(configuration: config)
        XCTAssertTrue(mockRuntime.isHardwareSetup)
        
        // 2. Start Session
        try await capability.startSession(sessionId: sessionId)
        XCTAssertTrue(mockRuntime.isHardwareSessionRunning)
    }
    
    func testRequestCaptureSuccessUpdatesMetrics() async throws {
        let config = CameraConfiguration(captureMode: .singlePhoto)
        let sessionId = SessionID(rawValue: "SESS-100")
        let correlationId = CorrelationID(rawValue: "CORR-200")
        
        try await capability.prepare(configuration: config)
        try await capability.startSession(sessionId: sessionId)
        
        // Request Capture
        try await capability.requestCapture(correlationId: correlationId)
        
        // Verify Metrics & Health
        let metrics = await capability.metricsSnapshot
        XCTAssertEqual(metrics.captureCount, 1)
        XCTAssertGreaterThan(metrics.averageCaptureTimeMs, 0)
        
        let health = await capability.healthSnapshot
        XCTAssertEqual(health.status, .healthy)
        XCTAssertNotNil(health.lastCaptureTime)
    }
    
    func testRequestCaptureWithoutStartSessionFails() async {
        let correlationId = CorrelationID(rawValue: "CORR-200")
        
        do {
            try await capability.requestCapture(correlationId: correlationId)
            XCTFail("Harus melempar CameraCapabilityError.sessionNotStarted")
        } catch let error as CameraCapabilityError {
            XCTAssertEqual(error, CameraCapabilityError.sessionNotStarted)
        } catch {
            XCTFail("Error tidak sesuai")
        }
    }
}
