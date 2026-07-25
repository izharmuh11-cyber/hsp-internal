// DeliveryCapabilityProtocol.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Kontrak Kemampuan Bisnis Domain Distribusi Foto Haispace Platform.
// BEBAS dari istilah AirDrop, Bonjour, HTTP Server, atau SDK spesifik.

import Foundation

public protocol DeliveryCapabilityProtocol: Sendable {
    
    /// Snapshot kesehatan domain distribusi saat ini (Read-Only O(1))
    var healthSnapshot: DeliveryHealth { get }
    
    /// Snapshot metrik performa domain distribusi saat ini (Read-Only O(1))
    var metricsSnapshot: DeliveryMetrics { get }
    
    /// Menyiapkan modul distribusi dengan konfigurasi tertentu
    func prepare(configuration: DeliveryConfiguration) async throws
    
    /// Meminta distribusi pengiriman foto (Returns DeliveryResult)
    func requestDelivery(
        sessionId: SessionID,
        correlationId: CorrelationID,
        photoId: PhotoID,
        assetPath: String,
        channel: DeliveryChannel
    ) async throws -> DeliveryResult
    
    /// Mengulang pengiriman yang gagal (Retry Delivery)
    func retryDelivery(
        deliveryId: DeliveryID,
        correlationId: CorrelationID
    ) async throws -> DeliveryResult
    
    /// Membatalkan transaksi pengiriman
    func cancelDelivery(deliveryId: DeliveryID) async throws
    
    /// Menghentikan sesi distribusi
    func stopSession() async
}
