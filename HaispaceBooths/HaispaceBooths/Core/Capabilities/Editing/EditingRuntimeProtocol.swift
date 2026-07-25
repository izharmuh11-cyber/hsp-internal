// EditingRuntimeProtocol.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Protocol Adapter antara EditingCapability (Orchestrator) 
// dan Pipeline Rendering Native (CoreImage, Metal, FrameCompositorService).

import Foundation

/// Kontrak Adapter Pipeline Rendering Native
public protocol EditingRuntimeProtocol: Sendable {
    
    /// Menyiapkan context GPU Metal & memicu preload assets
    func preparePipeline() async throws
    
    /// Merender preview cepat (res terpotong / downsampled)
    func renderPreview(
        photoInput: String,
        configuration: EditingConfiguration,
        correlationId: CorrelationID
    ) async throws -> PreviewResult
    
    /// Merender export full quality (12MP/48MP full render + frame + LUT)
    func renderExport(
        photoInput: String,
        configuration: EditingConfiguration,
        correlationId: CorrelationID
    ) async throws -> ExportResult
}
