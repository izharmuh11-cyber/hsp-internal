// PaymentCapabilityProtocol.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Kontrak Kemampuan Bisnis Domain Pembayaran Haispace Platform.
// BEBAS dari istilah EMVCo, CRC16, HTTP, atau Gateway spesifik.

import Foundation

public protocol PaymentCapabilityProtocol: Sendable {
    
    /// Snapshot kesehatan domain pembayaran saat ini (Read-Only O(1))
    var healthSnapshot: PaymentHealth { get }
    
    /// Snapshot metrik performa domain pembayaran saat ini (Read-Only O(1))
    var metricsSnapshot: PaymentMetrics { get }
    
    /// Menyiapkan modul pembayaran dengan konfigurasi tertentu
    func prepare(configuration: PaymentConfiguration) async throws
    
    /// Meminta transaksi pembayaran baru (Returns PaymentResult dengan payload String)
    func requestPayment(
        sessionId: SessionID,
        correlationId: CorrelationID,
        amount: PaymentAmount,
        method: PaymentCapabilityMethod
    ) async throws -> PaymentResult
    
    /// Mengonfirmasi otorisasi pembayaran (Idempotent)
    func confirmPayment(paymentId: PaymentID) async throws -> PaymentResult
    
    /// Membatalkan transaksi pembayaran
    func cancelPayment(paymentId: PaymentID) async throws
    
    /// Menghentikan sesi pembayaran
    func stopSession() async
}
