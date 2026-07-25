// DeliveryErrors.swift
// HaispaceBooths — Core/Capabilities/Delivery
//
// Enum Error Independen Domain Delivery Capability.

import Foundation

public enum DeliveryCapabilityError: Error, LocalizedError, Equatable, Sendable {
    case channelUnavailable(channel: String)
    case assetNotFound(photoId: String)
    case deliveryFailed(reason: String)
    case sessionNotActive
    
    public var errorDescription: String? {
        switch self {
        case .channelUnavailable(let channel):
            return "Saluran distribusi '\(channel)' tidak tersedia saat ini."
        case .assetNotFound(let photoId):
            return "Asset foto '\(photoId)' tidak ditemukan untuk dikirim."
        case .deliveryFailed(let reason):
            return "Gagal melakukan distribusi foto: \(reason)"
        case .sessionNotActive:
            return "Sesi distribusi belum aktif."
        }
    }
}
