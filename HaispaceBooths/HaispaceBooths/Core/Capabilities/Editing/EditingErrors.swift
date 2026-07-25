// EditingErrors.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Enum Error Independen Domain Editing Capability.

import Foundation

public enum EditingCapabilityError: Error, LocalizedError, Equatable, Sendable {
    case frameNotFound(frameId: String)
    case filterNotFound(filterId: String)
    case invalidSourcePhotoData
    case renderPipelineFailed(reason: String)
    case metalGPUUnavailable
    case exportFailed(reason: String)
    case sessionNotActive
    
    public var errorDescription: String? {
        switch self {
        case .frameNotFound(let frameId):
            return "Frame overlay '\(frameId)' tidak ditemukan."
        case .filterNotFound(let filterId):
            return "Metal LUT Filter '\(filterId)' tidak ditemukan."
        case .invalidSourcePhotoData:
            return "Data foto mentah tidak valid atau rusak."
        case .renderPipelineFailed(let reason):
            return "Kegagalan pada Rendering Pipeline: \(reason)"
        case .metalGPUUnavailable:
            return "Akselerasi Metal GPU tidak tersedia di perangkat ini."
        case .exportFailed(let reason):
            return "Gagal melakukan export foto final: \(reason)"
        case .sessionNotActive:
            return "Sesi editing belum diinisialisasi atau dihentikan."
        }
    }
}
