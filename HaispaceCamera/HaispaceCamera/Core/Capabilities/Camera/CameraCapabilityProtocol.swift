// CameraCapabilityProtocol.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Murni Kontrak Kemampuan Bisnis (Business Capability Contract).
// BEBAS dari tipe data AVFoundation (AVCaptureSession, CMSampleBuffer, UIImage).
//
// Ref: docs/design/47_runtime_capabilities.md, docs/design/49_architecture_compliance.md

import Foundation

/// Kontrak Kemampuan Bisnis Kamera Haispace Platform.
public protocol CameraCapabilityProtocol: Sendable {
    
    /// Snapshot kesehatan capability saat ini (Read-Only O(1))
    var healthSnapshot: CameraHealth { get }
    
    /// Snapshot metrik performa capability saat ini (Read-Only O(1))
    var metricsSnapshot: CameraMetrics { get }
    
    /// Menyiapkan modul kamera dengan konfigurasi bisnis tertentu
    func prepare(configuration: CameraConfiguration) async throws
    
    /// Memulai sesi kamera aktif untuk SessionID tertentu
    func startSession(sessionId: SessionID) async throws
    
    /// Menghentikan sesi kamera aktif
    func stopSession() async
    
    /// Mengirim instruksi pengoperasian jepretan foto still image berbasis CorrelationID
    func requestCapture(correlationId: CorrelationID) async throws
}
