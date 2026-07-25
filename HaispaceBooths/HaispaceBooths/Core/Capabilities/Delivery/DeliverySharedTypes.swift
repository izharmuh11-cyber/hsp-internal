// DeliverySharedTypes.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Value Objects & Structs Domain Distribusi Foto Haispace Platform.

import Foundation

/// Value Object Identifikasi Transaksi Pengiriman Foto
public struct DeliveryID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Saluran/Channel Distribusi Foto Bisnis
public enum DeliveryChannel: String, Codable, Sendable {
    case airDrop
    case localBonjourWiFiServer
    case cloudR2URL
    case nearbyShare
}

/// Hasil Akhir Pengiriman Distribusi
public struct DeliveryResult: Codable, Sendable {
    public let deliveryId: DeliveryID
    public let sessionId: SessionID
    public let photoId: PhotoID
    public let channel: DeliveryChannel
    public let deliveryReference: String // URL / QR Code Link / Token Akses Download
    public let deliveredAt: Date
    
    public init(
        deliveryId: DeliveryID,
        sessionId: SessionID,
        photoId: PhotoID,
        channel: DeliveryChannel,
        deliveryReference: String,
        deliveredAt: Date = Date()
    ) {
        self.deliveryId = deliveryId
        self.sessionId = sessionId
        self.photoId = photoId
        self.channel = channel
        self.deliveryReference = deliveryReference
        self.deliveredAt = deliveredAt
    }
}
