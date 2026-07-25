// DeliveryRuntimeProtocol.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Protocol Adapter antara DeliveryCapability (Orchestrator) 
// dan Hardware/Transport Layer (AirDrop / Bonjour Local Server / Cloud R2).

import Foundation

public protocol DeliveryRuntimeProtocol: Sendable {
    
    /// Menyiapkan channel distribusi
    func prepareChannel(configuration: DeliveryConfiguration) async throws
    
    /// Mengeksekusi pengiriman asset foto
    func dispatchAsset(
        deliveryId: DeliveryID,
        photoId: PhotoID,
        assetPath: String,
        channel: DeliveryChannel
    ) async throws -> DeliveryResult
    
    /// Membatalkan pengiriman aktif
    func cancelDelivery(deliveryId: DeliveryID) async
}
