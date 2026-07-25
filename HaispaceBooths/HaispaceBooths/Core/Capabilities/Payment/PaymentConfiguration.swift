// PaymentConfiguration.swift
// HaispaceBooths — Core/Capabilities/Payment
//
// Model Konfigurasi Murni Domain Pembayaran (Business Level).

import Foundation

public struct PaymentConfiguration: Codable, Sendable, Equatable {
    public let defaultMethod: PaymentCapabilityMethod
    public let timeoutSeconds: Int
    public let allowOperatorOverride: Bool
    
    public init(
        defaultMethod: PaymentCapabilityMethod = .localQRIS,
        timeoutSeconds: Int = 300,
        allowOperatorOverride: Bool = true
    ) {
        self.defaultMethod = defaultMethod
        self.timeoutSeconds = timeoutSeconds
        self.allowOperatorOverride = allowOperatorOverride
    }
}
