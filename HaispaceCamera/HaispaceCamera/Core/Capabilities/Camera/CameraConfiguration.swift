// CameraConfiguration.swift
// HaispaceCamera — Core/Capabilities/Camera
//
// Struct Konfigurasi Tingkat Bisnis (Capability Level).
// BEBAS dari tipe data AVFoundation (AVCaptureDevice, PixelFormat, dll).

import Foundation

/// Modus Tangkapan Kamera
public enum CameraCaptureMode: String, Codable, Sendable {
    case singlePhoto
    case burstMode
    case portraitMode
}

/// Kualitas Preview Stream
public enum CameraPreviewQuality: String, Codable, Sendable {
    case low        // 480p - Hemat Baterai & Bandwidth
    case medium     // 720p - Keseimbangan Optimal (Default)
    case high       // 1080p - Kualitas Maksimal
}

/// Resolusi Foto Hasil Tangkapan
public enum CameraPreferredResolution: String, Codable, Sendable {
    case standard12MP // 4032 x 3024
    case high48MP     // 8064 x 6048 (iPhone 14 Pro+)
}

/// Model Konfigurasi Murni Camera Capability
public struct CameraConfiguration: Codable, Sendable, Equatable {
    public let captureMode: CameraCaptureMode
    public let preferredResolution: CameraPreferredResolution
    public let enableRAW: Bool
    public let enableHDR: Bool
    public let previewQuality: CameraPreviewQuality
    
    public init(
        captureMode: CameraCaptureMode = .singlePhoto,
        preferredResolution: CameraPreferredResolution = .standard12MP,
        enableRAW: Bool = false,
        enableHDR: Bool = true,
        previewQuality: CameraPreviewQuality = .medium
    ) {
        self.captureMode = captureMode
        self.preferredResolution = preferredResolution
        self.enableRAW = enableRAW
        self.enableHDR = enableHDR
        self.previewQuality = previewQuality
    }
}
