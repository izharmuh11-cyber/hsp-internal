// PaymentCapabilityTests.swift
// HaispaceBoothsTests — Capabilities/Payment
//
// Unit & Idempotency Compliance Tests untuk PaymentCapability (Sprint 4).
// Memverifikasi Invariant #12 (Idempotency) & Decoupled Domain Lifecycle.

import XCTest
@testable import HaispaceBooths

// MARK: - Mock Payment Runtime (Test Double)
final class MockPaymentRuntime: PaymentRuntimeProtocol, @unchecked Sendable {
    var isRuntimeSetup = false
    var mockQRISPayload = "00020101021226670016ID.CO.QRIS.WWW01189360091100000000005204581253033605802ID5914HAISPACE BOOTH6007JAKARTA6304A1B2"
    
    func setupRuntime(configuration: PaymentConfiguration) async throws {
        isRuntimeSetup = true
    }
    
    func generatePayload(
        paymentId: PaymentID,
        amount: PaymentAmount,
        method: PaymentMethod
    ) async throws -> String {
        guard isRuntimeSetup else { throw PaymentCapabilityError.sessionNotActive }
        return mockQRISPayload
    }
    
    func checkAuthorizationStatus(paymentId: PaymentID) async throws -> Bool {
        return true
    }
    
    func cancelTransaction(paymentId: PaymentID) async {}
}

// MARK: - PaymentCapabilityTests
final class PaymentCapabilityTests: XCTestCase {
    
    var mockRuntime: MockPaymentRuntime!
    var capability: PaymentCapability!
    
    override func setUp() async throws {
        try await super.setUp()
        mockRuntime = MockPaymentRuntime()
        capability = PaymentCapability(runtime: mockRuntime)
    }
    
    func testRequestPaymentAndConfirmSuccess() async throws {
        let sessionId = SessionID(rawValue: "SESS-PAY-001")
        let correlationId = CorrelationID(rawValue: "CORR-PAY-001")
        let amount = PaymentAmount(amountValue: 35000) // Rp 35.000
        
        // 1. Prepare
        try await capability.prepare(configuration: PaymentConfiguration())
        
        // 2. Request Payment
        let result = try await capability.requestPayment(
            sessionId: sessionId,
            correlationId: correlationId,
            amount: amount,
            method: .localQRIS
        )
        
        XCTAssertEqual(result.sessionId, sessionId)
        XCTAssertEqual(result.payloadString, mockRuntime.mockQRISPayload)
        
        // 3. Confirm Payment
        let confirmResult = try await capability.confirmPayment(paymentId: result.paymentId)
        XCTAssertEqual(confirmResult.paymentId, result.paymentId)
        XCTAssertNotNil(confirmResult.confirmedAt)
    }
    
    func testDuplicateConfirmPaymentIsIdempotent() async throws {
        let sessionId = SessionID(rawValue: "SESS-PAY-002")
        let correlationId = CorrelationID(rawValue: "CORR-PAY-002")
        let amount = PaymentAmount(amountValue: 50000)
        
        try await capability.prepare(configuration: PaymentConfiguration())
        let result = try await capability.requestPayment(
            sessionId: sessionId,
            correlationId: correlationId,
            amount: amount,
            method: .localQRIS
        )
        
        // First Confirmation
        let confirm1 = try await capability.confirmPayment(paymentId: result.paymentId)
        XCTAssertEqual(confirm1.paymentId, result.paymentId)
        
        // Second Confirmation (Idempotent duplicate call - Invariant #12)
        let confirm2 = try await capability.confirmPayment(paymentId: result.paymentId)
        XCTAssertEqual(confirm2.paymentId, result.paymentId)
        XCTAssertEqual(confirm2.payloadString, "IDEMPOTENT_CONFIRMED")
    }
}
