// DeliveryCapabilityTests.swift
// HaispaceBoothsTests — Capabilities/Delivery
//
// Unit & Architecture Compliance Tests untuk DeliveryCapability.
// Memverifikasi Distribution Orchestrator, Channel Retry, & State Machine.

import XCTest
@testable import HaispaceBooths

// MARK: - Mock Delivery Runtime (Test Double)
final class MockDeliveryRuntime: DeliveryRuntimeProtocol, @unchecked Sendable {
    var isChannelPrepared = false
    var shouldFailDelivery = false
    
    func prepareChannel(configuration: DeliveryConfiguration) async throws {
        isChannelPrepared = true
    }
    
    func dispatchAsset(
        deliveryId: DeliveryID,
        photoId: PhotoID,
        assetPath: String,
        channel: DeliveryChannel
    ) async throws -> DeliveryResult {
        guard isChannelPrepared else { throw DeliveryCapabilityError.sessionNotActive }
        if shouldFailDelivery { throw DeliveryCapabilityError.deliveryFailed(reason: "Mock Distribution Drop") }
        return DeliveryResult(
            deliveryId: deliveryId,
            sessionId: SessionID(rawValue: "SESS-DELIVERY-001"),
            photoId: photoId,
            channel: channel,
            deliveryReference: "http://192.168.1.100:8080/download/photo_001.jpg"
        )
    }
    
    func cancelDelivery(deliveryId: DeliveryID) async {}
}

// MARK: - DeliveryCapabilityTests
final class DeliveryCapabilityTests: XCTestCase {
    
    var mockRuntime: MockDeliveryRuntime!
    var capability: DeliveryCapability!
    
    override func setUp() async throws {
        try await super.setUp()
        mockRuntime = MockDeliveryRuntime()
        capability = DeliveryCapability(runtime: mockRuntime)
    }
    
    func testRequestDeliverySuccess() async throws {
        let sessionId = SessionID(rawValue: "SESS-DELIVERY-001")
        let correlationId = CorrelationID(rawValue: "CORR-DELIVERY-001")
        let photoId = PhotoID(rawValue: "PHOTO-DELIVERY-001")
        
        // 1. Prepare
        try await capability.prepare(configuration: DeliveryConfiguration())
        
        // 2. Request Delivery
        let result = try await capability.requestDelivery(
            sessionId: sessionId,
            correlationId: correlationId,
            photoId: photoId,
            assetPath: "/storage/photo_001.jpg",
            channel: .localBonjourWiFiServer
        )
        
        XCTAssertEqual(result.photoId, photoId)
        XCTAssertEqual(result.channel, .localBonjourWiFiServer)
        XCTAssertTrue(result.deliveryReference.contains("8080"))
        
        // 3. Verify Health & Metrics
        let health = await capability.healthSnapshot
        XCTAssertEqual(health.status, .healthy)
        
        let metrics = await capability.metricsSnapshot
        XCTAssertEqual(metrics.successfulDeliveriesCount, 1)
    }
    
    func testDeliveryFailureAndSuccessfulRetry() async throws {
        let sessionId = SessionID(rawValue: "SESS-DELIVERY-002")
        let correlationId = CorrelationID(rawValue: "CORR-DELIVERY-002")
        let photoId = PhotoID(rawValue: "PHOTO-DELIVERY-002")
        
        try await capability.prepare(configuration: DeliveryConfiguration())
        mockRuntime.shouldFailDelivery = true
        
        do {
            _ = try await capability.requestDelivery(
                sessionId: sessionId,
                correlationId: correlationId,
                photoId: photoId,
                assetPath: "/storage/photo_002.jpg",
                channel: .localBonjourWiFiServer
            )
            XCTFail("Harus melempar DeliveryCapabilityError.deliveryFailed")
        } catch {
            let health = await capability.healthSnapshot
            XCTAssertEqual(health.status, .degraded)
            
            // Execute Successful Retry
            mockRuntime.shouldFailDelivery = false
            let retryResult = try await capability.retryDelivery(
                deliveryId: DeliveryID(rawValue: "RETRY-001"),
                correlationId: correlationId
            )
            
            XCTAssertEqual(retryResult.deliveryId.rawValue, "RETRY-001")
        }
    }
}
