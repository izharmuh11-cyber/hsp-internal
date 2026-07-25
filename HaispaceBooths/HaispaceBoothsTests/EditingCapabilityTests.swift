// EditingCapabilityTests.swift
// HaispaceBoothsTests — Capabilities/Editing
//
// Unit & Architecture Compliance Tests untuk EditingCapability (Sprint 2).
// Memverifikasi Reusabilitas Arsitektur (Architecture ROI), Determinisasi, & Separation of Preview vs Export.

import XCTest
@testable import HaispaceBooths

// MARK: - Mock Editing Runtime (Test Double)
final class MockEditingRuntime: EditingRuntimeProtocol, @unchecked Sendable {
    var isPipelinePrepared = false
    var shouldFailRender = false
    
    func preparePipeline() async throws {
        isPipelinePrepared = true
    }
    
    func renderPreview(
        photoInput: String,
        configuration: EditingConfiguration,
        correlationId: CorrelationID
    ) async throws -> PreviewResult {
        guard isPipelinePrepared else { throw EditingCapabilityError.sessionNotActive }
        if shouldFailRender { throw EditingCapabilityError.renderPipelineFailed(reason: "Mock GPU Error") }
        return PreviewResult(
            photoId: PhotoID(rawValue: "PHOTO-PREVIEW-001"),
            outputReference: "file:///tmp/preview_001.jpg",
            renderDurationMs: 45.0
        )
    }
    
    func renderExport(
        photoInput: String,
        configuration: EditingConfiguration,
        correlationId: CorrelationID
    ) async throws -> ExportResult {
        guard isPipelinePrepared else { throw EditingCapabilityError.sessionNotActive }
        if shouldFailRender { throw EditingCapabilityError.exportFailed(reason: "Mock Export Error") }
        return ExportResult(
            photoId: PhotoID(rawValue: "PHOTO-EXPORT-001"),
            outputReference: "file:///storage/export_001.jpg",
            renderDurationMs: 180.0,
            fileSizeBytes: 8500000,
            exportFormat: configuration.exportFormat
        )
    }
}

// MARK: - EditingCapabilityTests
final class EditingCapabilityTests: XCTestCase {
    
    var mockRuntime: MockEditingRuntime!
    var capability: EditingCapability!
    
    override func setUp() async throws {
        try await super.setUp()
        mockRuntime = MockEditingRuntime()
        capability = EditingCapability(runtime: mockRuntime)
    }
    
    func testPrepareAndRequestPreviewSuccess() async throws {
        let sessionId = SessionID(rawValue: "SESS-200")
        let correlationId = CorrelationID(rawValue: "CORR-300")
        let config = EditingConfiguration(exportFormat: .jpeg)
        
        // 1. Prepare
        try await capability.prepare(sessionId: sessionId, configuration: config)
        XCTAssertTrue(mockRuntime.isPipelinePrepared)
        
        // 2. Request Preview (Fast, Downsampled)
        let result = try await capability.requestPreview(photoInput: "photo_raw_001.jpg", correlationId: correlationId)
        XCTAssertEqual(result.outputReference, "file:///tmp/preview_001.jpg")
        XCTAssertGreaterThan(result.renderDurationMs, 0)
        
        // 3. Verify Health & Metrics
        let health = await capability.healthSnapshot
        XCTAssertEqual(health.status, .healthy)
        XCTAssertTrue(health.rendererReady)
        
        let metrics = await capability.metricsSnapshot
        XCTAssertEqual(metrics.renderCount, 1)
        XCTAssertGreaterThan(metrics.exportTimeMs, 0)
    }
    
    func testRequestExportSuccess() async throws {
        let sessionId = SessionID(rawValue: "SESS-200")
        let correlationId = CorrelationID(rawValue: "CORR-301")
        let config = EditingConfiguration(exportFormat: .jpeg)
        
        try await capability.prepare(sessionId: sessionId, configuration: config)
        let result = try await capability.requestExport(photoInput: "photo_raw_001.jpg", correlationId: correlationId)
        
        XCTAssertEqual(result.outputReference, "file:///storage/export_001.jpg")
        XCTAssertEqual(result.exportFormat, .jpeg)
        XCTAssertGreaterThan(result.fileSizeBytes, 0)
    }
    
    func testRequestPreviewWithoutPrepareFails() async {
        let correlationId = CorrelationID(rawValue: "CORR-300")
        
        do {
            _ = try await capability.requestPreview(photoInput: "photo_raw_001.jpg", correlationId: correlationId)
            XCTFail("Harus melempar EditingCapabilityError.sessionNotActive")
        } catch let error as EditingCapabilityError {
            XCTAssertEqual(error, EditingCapabilityError.sessionNotActive)
        } catch {
            XCTFail("Error tidak sesuai")
        }
    }
}
