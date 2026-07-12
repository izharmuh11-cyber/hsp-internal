// CameraP2PStore.swift
// HaispaceCamera — Core/State
//
// Store untuk koneksi P2P dari sisi iPhone ke iPad.
// Versi lebih sederhana dari P2PStore di HaiBooth.
//
// Ref: docs/design/39_state_architecture.md — HaiCamera State

import Foundation
import Observation

// MARK: - CameraP2PStore

@Observable
final class CameraP2PStore {

    // MARK: State
    var connectionState: P2PConnectionState = .disconnected
    var connectionMode: P2PMode = .multipeerConnectivity
    var latencyMs: Int = 0
    var lastPingTimestamp: Date?
    var pairedBoothName: String?    // Nama iPad yang terhubung

    // QR Pairing state
    var isScanning: Bool = false    // Apakah sedang scan QR?
    var lastPairingPayload: QRPairingPayload? {
        didSet {
            saveLastPayload()
        }
    }

    // Auto-reconnect
    private let payloadKey = "hs_last_qr_payload"

    init() {
        loadLastPayload()
    }

    // MARK: Computed

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
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

    // MARK: - Actions

    @MainActor
    func updateConnectionState(_ state: P2PConnectionState) {
        connectionState = state
        if case .disconnected = state {
            latencyMs = 0
            pairedBoothName = nil
        }
    }

    @MainActor
    func updateLatency(_ ms: Int) {
        latencyMs = ms
        lastPingTimestamp = Date()
    }

    @MainActor
    func startScanning() {
        isScanning = true
        connectionState = .scanning
    }

    @MainActor
    func stopScanning() {
        isScanning = false
    }

    // MARK: - Auto-Reconnect Persistence

    private func saveLastPayload() {
        guard let payload = lastPairingPayload else {
            UserDefaults.standard.removeObject(forKey: payloadKey)
            return
        }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: payloadKey)
        }
    }

    private func loadLastPayload() {
        guard let data = UserDefaults.standard.data(forKey: payloadKey),
              let payload = try? JSONDecoder().decode(QRPairingPayload.self, from: data) else {
            return
        }
        self.lastPairingPayload = payload
    }
}

// MARK: - Shared Types (re-exported for HaispaceCamera target)
// Types below mirror those in HaispaceBooths — separate targets need separate definitions.

// P2PConnectionState, P2PMode, SignalQuality — defined in CameraSharedTypes.swift
// QRPairingPayload — defined in CameraSharedTypes.swift
