// WorkflowSharedTypes.swift
// HaispaceBooths — Core/Workflow
//
// Value Objects & Structs Domain Workflow State Machine.

import Foundation

/// Tahapan Alur Tamu Kiosk Photobooth
public enum WorkflowStage: String, Codable, Sendable {
    case landing            // Standby / Welcome
    case guestRegistration  // Registrasi Nama/Email Tamu
    case packageSelection   // Pemilihan Paket Foto
    case templateSelection  // Pemilihan Template & Bingkai Frame
    case capturing          // Pengambilan Foto Still Image
    case editingPreview     // Tamu Pilih Filter & Preview
    case exporting          // Render High Resolution
    case paymentRequested   // Pembayaran QRIS / Cash
    case paymentConfirmed   // Otorisasi Sukses
    case deliveryDispatch   // Pengiriman Foto via Bonjour/AirDrop
    case sessionCompleted   // Selesai -> Siap Reset
    case recoveryMode       // Mode Pemulihan Operator
}

/// User Intent dari SwiftUI View
public enum WorkflowIntent: Sendable {
    case startGuestRegistration
    case guestSubmittedInfo(name: String, email: String)
    case selectPackage(packageId: String)
    case selectTemplate(frameId: String)
    case selectFilter(filterId: String)
    case triggerShutter
    case acceptPreview
    case confirmPaymentSuccess
    case finishSession
    case cancelSessionByOperator
}

/// Snapshot Kesehatan Workflow Engine
public struct WorkflowHealth: Codable, Sendable {
    public let currentStage: WorkflowStage
    public let activeSessionCount: Int
    public let averageCompletionTimeMs: Double
    public let stalledSessionsCount: Int
    public let recoveryCount: Int
    
    public init(
        currentStage: WorkflowStage = .landing,
        activeSessionCount: Int = 0,
        averageCompletionTimeMs: Double = 0.0,
        stalledSessionsCount: Int = 0,
        recoveryCount: Int = 0
    ) {
        self.currentStage = currentStage
        self.activeSessionCount = activeSessionCount
        self.averageCompletionTimeMs = averageCompletionTimeMs
        self.stalledSessionsCount = stalledSessionsCount
        self.recoveryCount = recoveryCount
    }
}
