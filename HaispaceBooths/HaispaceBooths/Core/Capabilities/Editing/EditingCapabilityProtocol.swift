// EditingCapabilityProtocol.swift
// HaispaceBooths — Core/Capabilities/Editing
//
// Kontrak Kemampuan Bisnis Domain Editing Haispace Platform.
// BEBAS dari tipe data CoreImage, CIContext, CIFilter, UIImage, Metal.

import Foundation

public protocol EditingCapabilityProtocol: Sendable {
    
    /// Snapshot kesehatan domain editing saat ini (Read-Only O(1))
    var healthSnapshot: EditingHealth { get }
    
    /// Snapshot metrik performa domain editing saat ini (Read-Only O(1))
    var metricsSnapshot: EditingMetrics { get }
    
    /// Menyiapkan pipeline editing untuk SessionID tertentu
    func prepare(sessionId: SessionID, configuration: EditingConfiguration) async throws
    
    /// Meminta render Preview cepat (Low Latency)
    func requestPreview(
        photoInput: String,
        correlationId: CorrelationID
    ) async throws -> PreviewResult
    
    /// Meminta render Export Full Quality (High Accuracy)
    func requestExport(
        photoInput: String,
        correlationId: CorrelationID
    ) async throws -> ExportResult
    
    /// Menghentikan sesi editing
    func stopSession() async
}
