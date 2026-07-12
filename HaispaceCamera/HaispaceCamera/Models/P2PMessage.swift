// P2PMessage.swift
// HaispaceCamera — Models
//
// Definisi semua tipe pesan yang dikirim via P2P antara iPad dan iPhone.
// Mirror dari HaispaceBooths/Models/P2PMessage.swift
//
// Ref: docs/design/08_p2p_communication.md — Protokol Pesan P2P

import Foundation

// MARK: - P2PMessage

/// Semua pesan yang bisa dikirim via P2P antara HaiBooth (iPad) ↔ HaiCamera (iPhone)
enum P2PMessage: Codable, Equatable {

    // MARK: Control Messages (iPad → iPhone)
    case ping(boothBatteryLevel: Float, isBoothReady: Bool)
    case sessionStart(config: SessionConfig)
    case triggerCapture(poseId: String?, captureIndex: Int)
    case sessionPause
    case sessionResume
    case sessionEnd(summary: SessionSummary)
    case focusPoint(normalizedX: Float, normalizedY: Float)
    case gestureDetected

    // MARK: Photo Transfer Messages (iPhone → iPad)
    case photoMetadata(photoId: String, fileSize: Int, capturedAt: Date, sortOrder: Int)
    case photoPreview(id: String, thumbnailData: Data)
    case photoFull(id: String, fullData: Data)
    case photoAck(photoId: String, checksum: String)

    // MARK: Status Messages (iPhone → iPad)
    case cameraStatus(batteryLevel: Float, thermalState: Int, latencyMs: Int)
    case cameraReady
    case cameraError(reason: String)

    // MARK: Pairing Messages (Both directions)
    case pairingRequest(peerUUID: String, eventId: String, timestamp: Int64)
    case pairingAcknowledge(sessionToken: String)
    case setZoom(factor: Double)
}

// MARK: - P2PMessageType (untuk filtering)

enum P2PMessageType: String, CaseIterable {
    case ping, sessionStart, triggerCapture, sessionPause, sessionResume, sessionEnd, focusPoint
    case photoMetadata, photoPreview, photoFull, photoAck
    case cameraStatus, cameraReady, cameraError
    case pairingRequest, pairingAcknowledge, gestureDetected
    case setZoom

    static func type(of message: P2PMessage) -> P2PMessageType {
        switch message {
        case .ping: return .ping
        case .sessionStart: return .sessionStart
        case .triggerCapture: return .triggerCapture
        case .sessionPause: return .sessionPause
        case .sessionResume: return .sessionResume
        case .sessionEnd: return .sessionEnd
        case .focusPoint: return .focusPoint
        case .gestureDetected: return .gestureDetected
        case .photoMetadata: return .photoMetadata
        case .photoPreview: return .photoPreview
        case .photoFull: return .photoFull
        case .photoAck: return .photoAck
        case .cameraStatus: return .cameraStatus
        case .cameraReady: return .cameraReady
        case .cameraError: return .cameraError
        case .pairingRequest: return .pairingRequest
        case .pairingAcknowledge: return .pairingAcknowledge
        case .setZoom: return .setZoom
        }
    }
}

// MARK: - SessionConfig & Summary

struct SessionConfig: Codable, Equatable {
    let sessionId: String
    let totalDurationSeconds: Int
    let intervalSeconds: Int
    let maxPhotoCount: Int
    let guestName: String
}

struct SessionSummary: Codable, Equatable {
    let sessionId: String
    let totalPhotosCaptured: Int
    let totalPhotosSelected: Int
    let durationActualSeconds: Int
}

// MARK: - P2PMessage Serialization

extension P2PMessage {
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> P2PMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(P2PMessage.self, from: data)
    }
}
