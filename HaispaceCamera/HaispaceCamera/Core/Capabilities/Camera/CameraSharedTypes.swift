// CameraSharedTypes.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Strongly-typed Identifiers (Value Objects) untuk Haispace Platform.
// Menjamin Compile-Time Type Safety dan mencegah pertukaran ID secara acak.

import Foundation

/// Value Object untuk Identitas Sesi Tamu
public struct SessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Value Object untuk Identitas Rantai Operasi (Correlation Trace)
public struct CorrelationID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Value Object untuk Identitas Foto
public struct PhotoID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Value Object untuk Identitas Transfer P2P
public struct TransferID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Hasil Tangkapan Still Image dari Runtime Layer
public struct CaptureResult: Codable, Sendable {
    public let photoId: PhotoID
    public let outputReference: String // Path / Key / URI file foto di storage
    public let captureDurationMs: Double
    public let resolution: String
    public let fileSizeBytes: Int64
    
    public init(
        photoId: PhotoID = PhotoID(),
        outputReference: String,
        captureDurationMs: Double,
        resolution: String = "4032x3024",
        fileSizeBytes: Int64 = 0
    ) {
        self.photoId = photoId
        self.outputReference = outputReference
        self.captureDurationMs = captureDurationMs
        self.resolution = resolution
        self.fileSizeBytes = fileSizeBytes
    }
}
