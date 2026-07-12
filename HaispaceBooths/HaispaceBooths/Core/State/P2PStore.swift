// P2PStore.swift
// HaispaceBooths — Core/State
//
// Store untuk status koneksi P2P antara iPad dan iPhone.
// Mengelola connection state, latency tracking, dan signal quality.
//
// Ref: docs/design/39_state_architecture.md — P2PStore
// Ref: docs/design/08_p2p_communication.md — Arsitektur Komunikasi Dua Mode

import Foundation
import Observation

// MARK: - P2PConnectionState

/// State koneksi P2P saat ini
enum P2PConnectionState: Equatable {
    case disconnected
    case scanning           // Sedang mencari iPhone via QR/MPC
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)

    var displayText: String {
        switch self {
        case .disconnected: return "Tidak Terhubung"
        case .scanning: return "Mencari Kamera..."
        case .connecting: return "Menghubungkan..."
        case .connected: return "Terhubung"
        case .reconnecting(let n): return "Menghubungkan ulang... (\(n))"
        case .failed: return "Koneksi Gagal"
        }
    }
}

// MARK: - P2PMode

/// Mode koneksi P2P yang digunakan
enum P2PMode {
    case multipeerConnectivity  // Direct P2P via MPC (tanpa router)
    case localRouter            // Via router WiFi lokal (TCP/IP socket)

    var displayName: String {
        switch self {
        case .multipeerConnectivity: return "Direct P2P"
        case .localRouter: return "Local Router"
        }
    }
}

// MARK: - SignalQuality

/// Kualitas sinyal berdasarkan latency
enum SignalQuality {
    case excellent  // < 10ms
    case good       // 10–50ms
    case fair       // 50–150ms
    case poor       // > 150ms
    case unknown    // Belum ada data

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "systemGreen"
        case .fair: return "orange"
        case .poor: return "red"
        case .unknown: return "gray"
        }
    }

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

// MARK: - P2PStore

@Observable
final class P2PStore {

    // MARK: State
    var connectionState: P2PConnectionState = .disconnected
    var connectionMode: P2PMode = .multipeerConnectivity
    var latencyMs: Int = 0
    var lastPingTimestamp: Date?
    var connectedPeerName: String?          // Display name iPhone yang terhubung
    var connectedPeerBatteryLevel: Float?   // Battery level iPhone

    // MPC service type — event-scoped untuk isolasi multi-booth
    // Format: "hs-{8 chars of eventId}" (max 15 chars, alfanumerik + dash)
    var mpcServiceType: String = "hs-default"

    // TCP Socket info (saat mode localRouter)
    var tcpLocalPort: Int?
    var tcpRemoteIP: String?

    // MARK: Computed

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var isConnecting: Bool {
        switch connectionState {
        case .connecting, .scanning, .reconnecting: return true
        default: return false
        }
    }

    var signalQuality: SignalQuality {
        guard isConnected, latencyMs > 0 else { return .unknown }
        switch latencyMs {
        case 0..<10: return .excellent
        case 10..<50: return .good
        case 50..<150: return .fair
        default: return .poor
        }
    }

    /// Apakah latency terlalu tinggi untuk mulai sesi foto?
    var isSafeForSession: Bool {
        isConnected && latencyMs < 150
    }

    // MARK: - Actions

    /// Update latency dari ping response
    @MainActor
    func updateLatency(_ ms: Int) {
        latencyMs = ms
        lastPingTimestamp = Date()
    }

    /// Update state koneksi
    @MainActor
    func updateConnectionState(_ state: P2PConnectionState) {
        connectionState = state
        if case .disconnected = state {
            latencyMs = 0
            connectedPeerBatteryLevel = nil
        }
    }

    /// Update info peer yang terhubung dari PING message
    @MainActor
    func updatePeerStatus(batteryLevel: Float) {
        connectedPeerBatteryLevel = batteryLevel
        lastPingTimestamp = Date()
    }

    /// Setup MPC service type berdasarkan event ID (untuk isolasi multi-booth)
    func configureMPCServiceType(eventId: String) {
        // MPC max 15 chars, alfanumerik + dash saja
        let prefix = "hs-"
        let maxEventIdLength = 15 - prefix.count
        let shortEventId = String(eventId.replacingOccurrences(of: "-", with: "").prefix(maxEventIdLength))
        mpcServiceType = "\(prefix)\(shortEventId)"
        HaispaceLogger.info("MPC service type set: \(mpcServiceType)", category: "p2p")
    }
}
