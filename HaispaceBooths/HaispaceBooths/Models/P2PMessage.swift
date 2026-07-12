// P2PMessage.swift
// HaispaceBooths — Models
//
// Definisi semua tipe pesan yang dikirim via P2P antara iPad dan iPhone.
// SEMUA komunikasi P2P harus menggunakan enum ini — jangan kirim raw Data tanpa type.
//
// Ref: docs/design/08_p2p_communication.md — Protokol Pesan P2P
// Ref: docs/design/40_concurrency_strategy.md — P2PMessageRouter

import Foundation

// MARK: - P2PMessage

/// Semua pesan yang bisa dikirim via P2P antara HaiBooth (iPad) ↔ HaiCamera (iPhone)
enum P2PMessage: Codable, Equatable {

    // MARK: Control Messages (iPad → iPhone)

    /// Heartbeat untuk menjaga koneksi tetap hidup
    /// Payload: status baterai iPad, status booth
    case ping(boothBatteryLevel: Float, isBoothReady: Bool)

    /// Mulai sesi foto — kirim konfigurasi dari iPad ke iPhone
    case sessionStart(config: SessionConfig)

    /// Perintah ambil foto — dikirim iPad saat countdown habis
    case triggerCapture(poseId: String?, captureIndex: Int)

    /// Pause sesi — iPhone stop countdown, kamera tetap on
    case sessionPause

    /// Resume sesi setelah pause
    case sessionResume

    /// Akhiri sesi — iPhone kembali ke standby mode
    case sessionEnd(summary: SessionSummary)

    /// Kirim koordinat untuk AE/AF lock (dari tap tamu di layar iPad)
    case focusPoint(normalizedX: Float, normalizedY: Float)

    /// Sinyal deteksi gesture "Hai" (5 jari) dari iPhone
    case gestureDetected

    // MARK: Photo Transfer Messages (iPhone → iPad)

    /// Metadata foto sebelum data dikirim — iPad bersiap menerima
    case photoMetadata(photoId: String, fileSize: Int, capturedAt: Date, sortOrder: Int)

    /// Preview thumbnail foto (Channel 1 — cepat, ~300KB)
    case photoPreview(id: String, thumbnailData: Data)

    /// Full quality foto (Channel 2 — background, ~2-3MB)
    case photoFull(id: String, fullData: Data)

    /// Konfirmasi foto sudah diterima iPad (ACK)
    case photoAck(photoId: String, checksum: String)

    // MARK: Status Messages (iPhone → iPad)

    /// Status kamera iPhone — battery, thermal, connection quality
    case cameraStatus(batteryLevel: Float, thermalState: Int, latencyMs: Int)

    /// iPhone siap menerima sesi baru
    case cameraReady

    /// iPhone tidak bisa capture — alasan tertentu
    case cameraError(reason: String)

    // MARK: Pairing Messages (Both directions)

    /// QR Code pairing — dari iPhone ke iPad setelah scan QR
    case pairingRequest(peerUUID: String, eventId: String, timestamp: Int64)

    /// Konfirmasi pairing berhasil — dari iPad ke iPhone
    case pairingAcknowledge(sessionToken: String)
    
    /// Set zoom factor kamera iPhone secara remote
    case setZoom(factor: Double)
    
    /// Set portrait mode (bokeh) kamera secara remote
    case setPortraitMode(enabled: Bool)
}

// MARK: - P2PMessageType (untuk filtering)

/// Tipe pesan untuk subscribe ke stream tertentu via P2PMessageRouter
enum P2PMessageType: String, CaseIterable {
    case ping
    case sessionStart
    case triggerCapture
    case sessionPause
    case sessionResume
    case sessionEnd
    case focusPoint
    case photoMetadata
    case photoPreview
    case photoFull
    case photoAck
    case cameraStatus
    case cameraReady
    case cameraError
    case pairingRequest
    case pairingAcknowledge
    case gestureDetected
    case setZoom
    case setPortraitMode

    /// Tipe pesan dari P2PMessage
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
        case .setPortraitMode: return .setPortraitMode
        }
    }
}

// MARK: - SessionConfig (Payload untuk sessionStart)

/// Konfigurasi sesi yang dikirim iPad ke iPhone saat sesi dimulai
struct SessionConfig: Codable, Equatable {
    let sessionId: String
    let totalDurationSeconds: Int
    let intervalSeconds: Int
    let maxPhotoCount: Int
    let guestName: String
}

// MARK: - SessionSummary (Payload untuk sessionEnd)

/// Ringkasan sesi yang dikirim iPad ke iPhone saat sesi selesai
struct SessionSummary: Codable, Equatable {
    let sessionId: String
    let totalPhotosCaptured: Int
    let totalPhotosSelected: Int
    let durationActualSeconds: Int
}

// MARK: - P2PMessage Serialization

extension P2PMessage {

    /// Encode ke Data untuk dikirim via P2P transport
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    /// Decode dari Data yang diterima via P2P transport
    static func decode(from data: Data) throws -> P2PMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(P2PMessage.self, from: data)
    }
}

// MARK: - QR Pairing Payload Schema

/// Schema JSON untuk QR Code pairing — sesuai definisi di 08_p2p_communication.md
/// Dibuat oleh iPad, di-scan oleh iPhone
struct QRPairingPayload: Codable {
    let v: Int              // Versi schema (saat ini: 1)
    let peerId: String      // UUID custom (stabil per-app install)
    let ip: String          // IPv4 dari interface WiFi aktif iPad
    let port: Int           // TCP socket port (range: 50000–60000, random per sesi)
    let eventId: String     // Untuk isolasi multi-booth di venue yang sama
    let ts: Int64           // Unix timestamp — QR valid selama 5 menit
    let sig: String         // HMAC-SHA256 untuk validasi integritas

    // MARK: Validation

    /// Apakah QR masih valid? (belum lebih dari 5 menit)
    var isExpired: Bool {
        let expirySeconds: Int64 = 5 * 60 // 5 menit
        let now = Int64(Date().timeIntervalSince1970)
        return (now - ts) > expirySeconds
    }

    /// Generate HMAC-SHA256 signature untuk field utama
    /// Shared secret di-embed di app (tidak hardcoded String — gunakan konstanta terenkompilasi)
    static func generateSignature(peerId: String, ip: String, port: Int, eventId: String, ts: Int64) -> String {
        let payload = "\(peerId)|\(ip)|\(port)|\(eventId)|\(ts)"
        let secret = AppSecrets.qrPayloadSharedSecret
        return HMACSHA256.sign(message: payload, key: secret)
    }
}
