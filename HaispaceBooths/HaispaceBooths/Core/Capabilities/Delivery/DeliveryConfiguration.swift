// DeliveryConfiguration.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Model Konfigurasi Murni Domain Distribusi Foto (Business Level).

import Foundation

public struct DeliveryConfiguration: Codable, Sendable, Equatable {
    public let primaryChannel: DeliveryChannel
    public let fallbackChannel: DeliveryChannel
    public let linkExpirationMinutes: Int
    
    public init(
        primaryChannel: DeliveryChannel = .localBonjourWiFiServer,
        fallbackChannel: DeliveryChannel = .cloudR2URL,
        linkExpirationMinutes: Int = 1440 // 24 Jam
    ) {
        self.primaryChannel = primaryChannel
        self.fallbackChannel = fallbackChannel
        self.linkExpirationMinutes = linkExpirationMinutes
    }
}
