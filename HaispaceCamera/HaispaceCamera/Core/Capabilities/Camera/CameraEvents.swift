// CameraEvents.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Payload Event Murni (Lightweight Value-Type Structs).
// DILARANG membawa UIImage, Data JPEG besar, atau Class Reference.

import Foundation

// MARK: - Event Payloads

/// Payload saat capture dimulai
public struct CaptureStartedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let timestamp: Date
    
    public init(sessionId: SessionID, correlationId: CorrelationID, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.timestamp = timestamp
    }
}

/// Payload saat capture selesai
public struct CaptureCompletedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let photoId: PhotoID
    public let capturedAt: Date
    public let captureDurationMs: Double
    public let outputReference: String // Path/URI/Key referensi foto (Bukan Buffer Gambar)
    
    public init(
        sessionId: SessionID,
        correlationId: CorrelationID,
        photoId: PhotoID,
        capturedAt: Date = Date(),
        captureDurationMs: Double,
        outputReference: String
    ) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.photoId = photoId
        self.capturedAt = capturedAt
        self.captureDurationMs = captureDurationMs
        self.outputReference = outputReference
    }
}

/// Payload saat capture gagal
public struct CaptureFailedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let reason: String
    public let timestamp: Date
    
    public init(sessionId: SessionID, correlationId: CorrelationID, reason: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.reason = reason
        self.timestamp = timestamp
    }
}

// MARK: - Health & Metrics Models

public enum CameraHealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case unavailable
}

/// Snapshot Kesehatan Camera Capability (Read-Only Immutable Struct)
public struct CameraHealth: Codable, Sendable {
    public let status: CameraHealthLevel
    public let lastCaptureTime: Date?
    public let droppedFramesCount: Int
    public let averageLatencyMs: Double
    public let lastErrorMessage: String?
    
    public init(
        status: CameraHealthLevel = .healthy,
        lastCaptureTime: Date? = nil,
        droppedFramesCount: Int = 0,
        averageLatencyMs: Double = 0.0,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.lastCaptureTime = lastCaptureTime
        self.droppedFramesCount = droppedFramesCount
        self.averageLatencyMs = averageLatencyMs
        self.lastErrorMessage = lastErrorMessage
    }
    
    /// Functional Immutable Health Update
    public func updated(status: CameraHealthLevel, lastCaptureTime: Date? = nil, error: String? = nil) -> CameraHealth {
        return CameraHealth(
            status: status,
            lastCaptureTime: lastCaptureTime ?? self.lastCaptureTime,
            droppedFramesCount: self.droppedFramesCount,
            averageLatencyMs: self.averageLatencyMs,
            lastErrorMessage: error
        )
    }
}

/// Snapshot Metrik Performa Camera Capability (Read-Only Immutable Struct)
public struct CameraMetrics: Codable, Sendable {
    public let captureCount: Int
    public let averageCaptureTimeMs: Double
    public let droppedFrameRatePercentage: Double
    public let peakMemoryUsageMB: Double
    
    public init(
        captureCount: Int = 0,
        averageCaptureTimeMs: Double = 0.0,
        droppedFrameRatePercentage: Double = 0.0,
        peakMemoryUsageMB: Double = 0.0
    ) {
        self.captureCount = captureCount
        self.averageCaptureTimeMs = averageCaptureTimeMs
        self.droppedFrameRatePercentage = droppedFrameRatePercentage
        self.peakMemoryUsageMB = peakMemoryUsageMB
    }
    
    /// Functional Immutable Record Capture Append-Only Update
    public func recordCapture(durationMs: Double) -> CameraMetrics {
        let newCount = self.captureCount + 1
        let newAvgTime = ((self.averageCaptureTimeMs * Double(self.captureCount)) + durationMs) / Double(newCount)
        return CameraMetrics(
            captureCount: newCount,
            averageCaptureTimeMs: newAvgTime,
            droppedFrameRatePercentage: self.droppedFrameRatePercentage,
            peakMemoryUsageMB: self.peakMemoryUsageMB
        )
    }
}
