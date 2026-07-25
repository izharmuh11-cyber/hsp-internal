// EditingEvents.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Payload Event Granular Domain Editing, Health, dan Metrics.

import Foundation

// MARK: - Granular Event Payloads

public struct EditingStartedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let timestamp: Date
    
    public init(sessionId: SessionID, correlationId: CorrelationID, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.timestamp = timestamp
    }
}

public struct CompositionCompletedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let frameId: String?
    public let durationMs: Double
    
    public init(sessionId: SessionID, correlationId: CorrelationID, frameId: String?, durationMs: Double) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.frameId = frameId
        self.durationMs = durationMs
    }
}

public struct FilterAppliedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let filterId: String?
    public let durationMs: Double
    
    public init(sessionId: SessionID, correlationId: CorrelationID, filterId: String?, durationMs: Double) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.filterId = filterId
        self.durationMs = durationMs
    }
}

public struct PreviewGeneratedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let outputReference: String
    public let renderDurationMs: Double
    
    public init(sessionId: SessionID, correlationId: CorrelationID, outputReference: String, renderDurationMs: Double) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.outputReference = outputReference
        self.renderDurationMs = renderDurationMs
    }
}

public struct ExportCompletedPayload: Codable, Sendable {
    public let sessionId: SessionID
    public let correlationId: CorrelationID
    public let photoId: PhotoID
    public let outputReference: String
    public let fileSizeBytes: Int64
    public let renderDurationMs: Double
    
    public init(
        sessionId: SessionID,
        correlationId: CorrelationID,
        photoId: PhotoID,
        outputReference: String,
        fileSizeBytes: Int64,
        renderDurationMs: Double
    ) {
        self.sessionId = sessionId
        self.correlationId = correlationId
        self.photoId = photoId
        self.outputReference = outputReference
        self.fileSizeBytes = fileSizeBytes
        self.renderDurationMs = renderDurationMs
    }
}

// MARK: - Health & Metrics Models

public enum EditingHealthLevel: String, Codable, Sendable {
    case healthy
    case degraded
    case unavailable
}

/// Snapshot Kesehatan Domain Editing
public struct EditingHealth: Codable, Sendable {
    public let status: EditingHealthLevel
    public let rendererReady: Bool
    public let metalAvailable: Bool
    public let coreImageContextHealthy: Bool
    public let frameAssetsLoaded: Bool
    public let lutCacheHealthy: Bool
    public let lastErrorMessage: String?
    
    public init(
        status: EditingHealthLevel = .healthy,
        rendererReady: Bool = true,
        metalAvailable: Bool = true,
        coreImageContextHealthy: Bool = true,
        frameAssetsLoaded: Bool = true,
        lutCacheHealthy: Bool = true,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.rendererReady = rendererReady
        self.metalAvailable = metalAvailable
        self.coreImageContextHealthy = coreImageContextHealthy
        self.frameAssetsLoaded = frameAssetsLoaded
        self.lutCacheHealthy = lutCacheHealthy
        self.lastErrorMessage = lastErrorMessage
    }
    
    public func updated(status: EditingHealthLevel, error: String? = nil) -> EditingHealth {
        return EditingHealth(
            status: status,
            rendererReady: self.rendererReady,
            metalAvailable: self.metalAvailable,
            coreImageContextHealthy: self.coreImageContextHealthy,
            frameAssetsLoaded: self.frameAssetsLoaded,
            lutCacheHealthy: self.lutCacheHealthy,
            lastErrorMessage: error
        )
    }
}

/// Snapshot Metrik Performa Domain Editing
public struct EditingMetrics: Codable, Sendable {
    public let renderCount: Int
    public let averageCompositionTimeMs: Double
    public let averageFilterTimeMs: Double
    public let previewRenderTimeMs: Double
    public let exportTimeMs: Double
    public let peakGPUMemoryMB: Double
    public let failedExportCount: Int
    
    public init(
        renderCount: Int = 0,
        averageCompositionTimeMs: Double = 0.0,
        averageFilterTimeMs: Double = 0.0,
        previewRenderTimeMs: Double = 0.0,
        exportTimeMs: Double = 0.0,
        peakGPUMemoryMB: Double = 0.0,
        failedExportCount: Int = 0
    ) {
        self.renderCount = renderCount
        self.averageCompositionTimeMs = averageCompositionTimeMs
        self.averageFilterTimeMs = averageFilterTimeMs
        self.previewRenderTimeMs = previewRenderTimeMs
        self.exportTimeMs = exportTimeMs
        self.peakGPUMemoryMB = peakGPUMemoryMB
        self.failedExportCount = failedExportCount
    }
    
    public func recordRender(compositionMs: Double, filterMs: Double, totalExportMs: Double) -> EditingMetrics {
        let newCount = self.renderCount + 1
        let newAvgComp = ((self.averageCompositionTimeMs * Double(self.renderCount)) + compositionMs) / Double(newCount)
        let newAvgFilter = ((self.averageFilterTimeMs * Double(self.renderCount)) + filterMs) / Double(newCount)
        let newAvgExport = ((self.exportTimeMs * Double(self.renderCount)) + totalExportMs) / Double(newCount)
        
        return EditingMetrics(
            renderCount: newCount,
            averageCompositionTimeMs: newAvgComp,
            averageFilterTimeMs: newAvgFilter,
            previewRenderTimeMs: self.previewRenderTimeMs,
            exportTimeMs: newAvgExport,
            peakGPUMemoryMB: self.peakGPUMemoryMB,
            failedExportCount: self.failedExportCount
        )
    }
}
