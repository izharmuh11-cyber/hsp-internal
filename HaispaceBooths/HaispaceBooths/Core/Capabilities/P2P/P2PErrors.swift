// P2PErrors.swift
// HaispaceBooths — Core/Capabilities/P2P
//
// Enum Error Independen Domain P2P Communication Capability.

import Foundation

public enum P2PCapabilityError: Error, LocalizedError, Equatable, Sendable {
    case peerDisconnected
    case transportFailed(reason: String)
    case checksumMismatch(chunkIndex: UInt32)
    case transferTimeout
    case maxRetryExceeded
    case sessionNotActive
    case resumeFailed(transferId: String)
    
    public var errorDescription: String? {
        switch self {
        case .peerDisconnected:
            return "Koneksi P2P perangkat terputus."
        case .transportFailed(let reason):
            return "Kegagalan pada Transport Layer P2P: \(reason)"
        case .checksumMismatch(let chunkIndex):
            return "Checksum CRC32 mismatch pada Chunk \(chunkIndex)."
        case .transferTimeout:
            return "Waktu pengiriman data P2P telah habis (Timeout)."
        case .maxRetryExceeded:
            return "Batas pengulangan pengiriman (Max Retry) terlampaui."
        case .sessionNotActive:
            return "Sesi P2P belum diinisialisasi atau dihentikan."
        case .resumeFailed(let transferId):
            return "Gagal melakukan resume transfer untuk TransferID '\(transferId)'."
        }
    }
}
