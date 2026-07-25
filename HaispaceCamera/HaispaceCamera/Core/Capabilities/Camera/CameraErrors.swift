// CameraErrors.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Enum Error Independen milik Camera Capability.
// Dipetakan ke HaispaceError di layer integrasi.

import Foundation

public enum CameraCapabilityError: Error, LocalizedError, Equatable, Sendable {
    case runtimeFailure(reason: String)
    case hardwareFailure(reason: String)
    case permissionDenied
    case invalidConfiguration(reason: String)
    case sessionNotStarted
    case captureInProgress
    
    public var errorDescription: String? {
        switch self {
        case .runtimeFailure(let reason):
            return "Kegagalan Runtime Kamera: \(reason)"
        case .hardwareFailure(let reason):
            return "Kegagalan Hardware Kamera: \(reason)"
        case .permissionDenied:
            return "Akses kamera ditolak oleh pengguna."
        case .invalidConfiguration(let reason):
            return "Konfigurasi kamera tidak valid: \(reason)"
        case .sessionNotStarted:
            return "Sesi kamera belum dimulai."
        case .captureInProgress:
            return "Pengambilan foto sedang berlangsung."
        }
    }
}
