// CameraRuntimeProtocol.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Protocol Adapter antara CameraCapability (Orchestrator) 
// dan Hardware Runtime Layer (AVFoundation / CameraCaptureService).

import Foundation

public enum CameraRuntimeState: String, Codable, Sendable {
    case idle
    case prepared
    case running
    case capturing
    case stopped
}

/// Kontrak Adapter Runtime Kamera Native (AVFoundation Wrapper)
public protocol CameraRuntimeProtocol: Sendable {
    
    /// Menyiapkan perangkat fisik (AVCaptureSession, inputs, outputs)
    func setupHardware(configuration: CameraConfiguration) async throws
    
    /// Memulai capture session fisik
    func startHardwareSession() async throws
    
    /// Menghentikan capture session fisik
    func stopHardwareSession() async
    
    /// Mengeksekusi jepretan foto still image di hardware
    /// Mengembalikan CaptureResult lengkap (PhotoID, reference, duration, resolution, size)
    func captureStillImage(correlationId: CorrelationID) async throws -> CaptureResult
}
