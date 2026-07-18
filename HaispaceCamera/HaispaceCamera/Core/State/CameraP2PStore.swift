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

    // Auto-reconnect states
    var reconnectAttempt = 0
    private var reconnectTimer: Timer?
    private var isReconnecting = false

    // Auto-reconnect persistence key
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
        if case .connected = state {
            stopReconnection()
        }
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
        stopReconnection() // Hentikan auto-reconnect jika user scan ulang secara manual
        isScanning = true
        connectionState = .scanning
    }

    @MainActor
    func stopScanning() {
        isScanning = false
    }

    // MARK: - Auto-Reconnect Logic

    @MainActor
    func startReconnection(payload: QRPairingPayload) {
        guard !isConnected, !isReconnecting else { return }
        
        // Jika payload sudah expired sejak awal, langsung minta scan ulang
        if payload.isExpired {
            HaispaceLogger.warning("Auto-reconnect dibatalkan: QR Payload sudah expired. Perlu scan ulang.", category: "p2p")
            connectionState = .failed(reason: "QR Expired")
            lastPairingPayload = nil   // Hapus payload lama agar tidak dipakai lagi
            return
        }
        
        isReconnecting = true
        reconnectAttempt = 1
        connectionState = .reconnecting(attempt: reconnectAttempt)
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isConnected {
                    self.stopReconnection()
                    return
                }
                
                // Cek lagi apakah payload sudah expired saat timer berjalan
                if payload.isExpired {
                    HaispaceLogger.warning("QR Payload expired saat auto-reconnect. Hentikan dan minta scan ulang.", category: "p2p")
                    self.stopReconnection()
                    self.connectionState = .failed(reason: "QR Expired")
                    self.lastPairingPayload = nil
                    return
                }
                
                self.reconnectAttempt += 1
                self.connectionState = .reconnecting(attempt: self.reconnectAttempt)
                HaispaceLogger.info("Auto reconnect attempt \(self.reconnectAttempt) ke iPad...", category: "p2p")
                await P2PClientService.shared.connect(using: payload, isAutoReconnect: true)
            }
        }
        
        // Coba koneksi pertama kali langsung
        Task {
            HaispaceLogger.info("Mencoba auto-reconnect pertama kali...", category: "p2p")
            await P2PClientService.shared.connect(using: payload, isAutoReconnect: true)
        }
    }

    @MainActor
    func stopReconnection() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isReconnecting = false
        reconnectAttempt = 0
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
