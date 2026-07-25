// PaymentRuntimeProtocol.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Protocol Adapter antara PaymentCapability (Orchestrator) 
// dan Hardware/Gateway Payment Layer (Local QRIS EMVCo CRC16 / Midtrans / Cash).

import Foundation

public protocol PaymentRuntimeProtocol: Sendable {
    
    /// Menyiapkan runtime pembayaran
    func setupRuntime(configuration: PaymentConfiguration) async throws
    
    func generatePayload(
        paymentId: PaymentID,
        amount: PaymentAmount,
        method: PaymentCapabilityMethod
    ) async throws -> String
    
    /// Memeriksa otorisasi pembayaran
    func checkAuthorizationStatus(paymentId: PaymentID) async throws -> Bool
    
    /// Membatalkan transaksi di level runtime
    func cancelTransaction(paymentId: PaymentID) async
}
