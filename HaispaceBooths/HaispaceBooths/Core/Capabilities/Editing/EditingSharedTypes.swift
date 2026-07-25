// EditingSharedTypes.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Value Objects & Data Structs khusus untuk Editing Domain.
// Mendukung operasi deterministik f(Input, Config) -> Output.

import Foundation

/// Value Object Identifikasi Frame Overlay
public struct FrameReference: Hashable, Codable, Sendable {
    public let frameId: String
    public let assetPath: String
    
    public init(frameId: String, assetPath: String) {
        self.frameId = frameId
        self.assetPath = assetPath
    }
}

/// Value Object Identifikasi Metal LUT Filter
public struct FilterReference: Hashable, Codable, Sendable {
    public let filterId: String
    public let lutFileName: String
    public let intensity: Double // 0.0 s/d 1.0
    
    public init(filterId: String, lutFileName: String, intensity: Double = 1.0) {
        self.filterId = filterId
        self.lutFileName = lutFileName
        self.intensity = intensity
    }
}

/// Format Export Final
public enum ExportFormat: String, Codable, Sendable {
    case jpeg
    case heic
    case png
}

/// Hasil Render Preview Cepat
public struct PreviewResult: Codable, Sendable {
    public let photoId: PhotoID
    public let outputReference: String
    public let renderDurationMs: Double
    
    public init(photoId: PhotoID, outputReference: String, renderDurationMs: Double) {
        self.photoId = photoId
        self.outputReference = outputReference
        self.renderDurationMs = renderDurationMs
    }
}

/// Hasil Render Export Full Quality
public struct ExportResult: Codable, Sendable {
    public let photoId: PhotoID
    public let outputReference: String
    public let renderDurationMs: Double
    public let fileSizeBytes: Int64
    public let exportFormat: ExportFormat
    
    public init(
        photoId: PhotoID,
        outputReference: String,
        renderDurationMs: Double,
        fileSizeBytes: Int64,
        exportFormat: ExportFormat
    ) {
        self.photoId = photoId
        self.outputReference = outputReference
        self.renderDurationMs = renderDurationMs
        self.fileSizeBytes = fileSizeBytes
        self.exportFormat = exportFormat
    }
}
