// CameraCaptureService.swift
// HaispaceCamera — Services/Camera
//
// Mengelola sesi AVCapture, video stream ke VideoEncoder, 
// dan pengambilan foto kualitas tinggi.
//
// Ref: docs/design/20_haicamera_iphone.md

import Foundation
import AVFoundation
import UIKit

@MainActor
final class CameraCaptureService: NSObject {
    static let shared = CameraCaptureService()
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    // Delegate untuk distribusi frame
    var onVideoFrameCaptured: ((CMSampleBuffer) -> Void)?
    var onPhotoCaptured: ((AVCapturePhoto) -> Void)?
    
    private var isConfigured = false
    
    private override init() {
        super.init()
    }
    
    func configureAndStart() {
        guard !isConfigured else { return }
        
        // Membutuhkan izin kamera
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                HaispaceLogger.error("Akses kamera ditolak", category: "camera")
                return
            }
            Task { @MainActor in
                self?.setupSession()
            }
        }
    }
    
    private func setupSession() {
        captureSession.beginConfiguration()
        
        // Atur preset untuk mendapatkan balance antara preview cepat dan foto yang bagus
        captureSession.sessionPreset = .photo
        
        // Cari kamera utama (Wide Angle)
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            HaispaceLogger.error("Tidak bisa menemukan kamera belakang", category: "camera")
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(videoDeviceInput) {
            captureSession.addInput(videoDeviceInput)
        }
        
        // Setup Video Output untuk live stream P2P
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "id.haispaceproject.camera.videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Setup Photo Output untuk jepretan full quality
        photoOutput.isHighResolutionCaptureEnabled = true
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        captureSession.commitConfiguration()
        
        Task.detached(priority: .userInitiated) {
            self.captureSession.startRunning()
            HaispaceLogger.info("Camera capture session started", category: "camera")
        }
        
        isConfigured = true
    }
    
    /// Trigger pemotretan kualitas tinggi (dipanggil saat menerima instruksi dari iPad)
    func captureHighQualityPhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.flashMode = .off // Flash menggunakan layar iPad, iPhone flash dimatikan
        
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        HaispaceLogger.info("Memicu jepretan foto resolusi tinggi", category: "camera")
    }
    
    func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
            isConfigured = false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Teruskan ke VideoEncoderService
        Task { @MainActor in
            self.onVideoFrameCaptured?(sampleBuffer)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            HaispaceLogger.error("Gagal capture foto: \(error.localizedDescription)", category: "camera")
            return
        }
        Task { @MainActor in
            self.onPhotoCaptured?(photo)
        }
    }
}
