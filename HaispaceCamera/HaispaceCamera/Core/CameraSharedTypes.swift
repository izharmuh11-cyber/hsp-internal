// CameraSharedTypes.swift
// HaispaceCamera — Core
//
// Tipe-tipe yang diperlukan oleh HaispaceCamera yang di-mirror dari HaispaceBooths.
// Karena dua target terpisah, definisi ini perlu ada di masing-masing target.
//
// ⚠️ PENTING: Jika ada perubahan di HaispaceBooths, update juga file ini.
// Ref: docs/design/08_p2p_communication.md
// Ref: docs/design/39_state_architecture.md

import Foundation

// MARK: - P2PConnectionState (Mirror dari HaispaceBooths)

enum P2PConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)

    var displayText: String {
        switch self {
        case .disconnected: return "Tidak Terhubung"
        case .scanning: return "Mencari Booth..."
        case .connecting: return "Menghubungkan..."
        case .connected: return "Terhubung ke iPad"
        case .reconnecting(let n): return "Menghubungkan ulang... (\(n))"
        case .failed: return "Koneksi Gagal"
        }
    }
}

// MARK: - P2PMode (Mirror)

enum P2PMode {
    case multipeerConnectivity
    case localRouter

    var displayName: String {
        switch self {
        case .multipeerConnectivity: return "Direct P2P"
        case .localRouter: return "Local Router"
        }
    }
}

// MARK: - SignalQuality (Mirror)

enum SignalQuality {
    case excellent
    case good
    case fair
    case poor
    case unknown

    var sfSymbol: String {
        switch self {
        case .excellent: return "wifi"
        case .good: return "wifi"
        case .fair: return "wifi.exclamationmark"
        case .poor: return "wifi.slash"
        case .unknown: return "wifi.slash"
        }
    }
}

// MARK: - QRPairingPayload (Mirror dari HaispaceBooths)

struct QRPairingPayload: Codable {
    let v: Int
    let peerId: String
    let ip: String
    let port: Int
    let eventId: String
    let ts: Int64
    let sig: String

    var isExpired: Bool {
        let expirySeconds: Int64 = 5 * 60
        let now = Int64(Date().timeIntervalSince1970)
        return (now - ts) > expirySeconds
    }

    static func generateSignature(peerId: String, ip: String, port: Int, eventId: String, ts: Int64) -> String {
        let payload = "\(peerId)|\(ip)|\(port)|\(eventId)|\(ts)"
        let secret = AppSecrets.qrPayloadSharedSecret
        return HMACSHA256.sign(message: payload, key: secret)
    }
}

// MARK: - AlertLevel (Mirror)

enum AlertLevel {
    case info
    case warning
    case error
    case critical
}
