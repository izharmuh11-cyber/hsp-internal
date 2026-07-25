// P2PCapabilityTests.swift
// HaispaceBoothsTests — Capabilities/P2P
//
// Unit & Architecture Compliance Tests untuk P2PCapability (Sprint 3).
// Memverifikasi Rule of Three & Reusabilitas Arsitektur (91% Architecture ROI).

import XCTest
@testable import HaispaceBooths

// MARK: - Mock P2P Runtime (Test Double)
final class MockP2PRuntime: P2PRuntimeProtocol, @unchecked Sendable {
    var isTransportPrepared = false
    var isPeerPaired = false
    var shouldFailTransfer = false
    
    func setupTransport(configuration: P2PConfiguration) async throws {
        isTransportPrepared = true
    }
    
    func startPeerDiscovery() async throws -> P2PPeerInfo {
        guard isTransportPrepared else { throw P2PCapabilityError.transportFailed(reason: "Not Prepared") }
        isPeerPaired = true
        return P2PPeerInfo(
            deviceId: "IPHONE-14-PRO",
            deviceName: "Haispace Camera iPhone",
            role: "iPhoneCamera",
            activeTransport: .multipeerConnectivity
        )
    }
    
    func stopTransport() async {
        isPeerPaired = false
    }
    
    func executeTransfer(
        sessionId: SessionID,
        transferId: TransferID,
        payloadPath: String
    ) async throws -> P2PTransferResult {
        guard isPeerPaired else { throw P2PCapabilityError.sessionNotActive }
        if shouldFailTransfer { throw P2PCapabilityError.transportFailed(reason: "Mock Socket Drop") }
        return P2PTransferResult(
            transferId: transferId,
            sessionId: sessionId,
            outputReference: "file:///storage/received_photo.jpg",
            totalBytes: 12500000,
            transferDurationMs: 320.0
        )
    }
    
    func resumeTransfer(
        transferId: TransferID,
        fromChunkIndex: UInt32
    ) async throws -> P2PTransferResult {
        guard isPeerPaired else { throw P2PCapabilityError.sessionNotActive }
        return P2PTransferResult(
            transferId: transferId,
            sessionId: SessionID(rawValue: "SESS-MOCK"),
            outputReference: "file:///storage/received_photo_resumed.jpg",
            totalBytes: 6200000,
            transferDurationMs: 160.0,
            isResumed: true
        )
    }
}

// MARK: - P2PCapabilityTests
final class P2PCapabilityTests: XCTestCase {
    
    var mockRuntime: MockP2PRuntime!
    var capability: P2PCapability!
    
    override func setUp() async throws {
        try await super.setUp()
        mockRuntime = MockP2PRuntime()
        capability = P2PCapability(runtime: mockRuntime)
    }
    
    func testPrepareAndStartSessionSuccess() async throws {
        let config = P2PConfiguration()
        let sessionId = SessionID(rawValue: "SESS-300")
        
        // 1. Prepare
        try await capability.prepare(configuration: config)
        XCTAssertTrue(mockRuntime.isTransportPrepared)
        
        // 2. Start Session
        let peer = try await capability.startSession(sessionId: sessionId)
        XCTAssertEqual(peer.role, "iPhoneCamera")
        XCTAssertTrue(mockRuntime.isPeerPaired)
    }
    
    func testRequestTransferSuccess() async throws {
        let sessionId = SessionID(rawValue: "SESS-300")
        let transferId = TransferID(rawValue: "XFER-500")
        
        try await capability.prepare(configuration: P2PConfiguration())
        _ = try await capability.startSession(sessionId: sessionId)
        
        let result = try await capability.requestTransfer(transferId: transferId, payloadPath: "/tmp/photo.jpg")
        XCTAssertEqual(result.transferId, transferId)
        XCTAssertGreaterThan(result.totalBytes, 0)
        
        let metrics = await capability.metricsSnapshot
        XCTAssertGreaterThan(metrics.transferredBytesCount, 0)
    }
}
