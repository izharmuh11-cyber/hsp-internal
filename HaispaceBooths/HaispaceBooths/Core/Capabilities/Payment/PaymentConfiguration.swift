// PaymentConfiguration.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Model Konfigurasi Murni Domain Pembayaran (Business Level).

import Foundation

public struct PaymentConfiguration: Codable, Sendable, Equatable {
    public let defaultMethod: PaymentMethod
    public let timeoutSeconds: Double
    public let allowOperatorOverride: Bool
    
    public init(
        defaultMethod: PaymentMethod = .localQRIS,
        timeoutSeconds: Double = 180.0,
        allowOperatorOverride: Bool = true
    ) {
        self.defaultMethod = defaultMethod
        self.timeoutSeconds = timeoutSeconds
        self.allowOperatorOverride = allowOperatorOverride
    }
}
