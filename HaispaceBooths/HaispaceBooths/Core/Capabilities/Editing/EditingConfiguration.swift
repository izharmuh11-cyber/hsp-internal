// EditingConfiguration.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Model Konfigurasi Murni Editing Capability (Deterministik).

import Foundation

public struct EditingConfiguration: Codable, Sendable, Equatable {
    public let frame: FrameReference?
    public let filter: FilterReference?
    public let exportFormat: ExportFormat
    public let jpegQuality: Double // 0.8 s/d 1.0
    
    public init(
        frame: FrameReference? = nil,
        filter: FilterReference? = nil,
        exportFormat: ExportFormat = .jpeg,
        jpegQuality: Double = 0.9
    ) {
        self.frame = frame
        self.filter = filter
        self.exportFormat = exportFormat
        self.jpegQuality = jpegQuality
    }
}
