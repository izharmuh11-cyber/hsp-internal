// LocalTCPRouterService.swift
// HaispaceBooths — Services/P2P
//
// Layanan Fallback P2P berbasis NWListener untuk mode Router Lokal.
// Sangat stabil di crowd ekstrem, memerlukan travel router khusus.
//
// Ref: docs/design/08_p2p_communication.md

import Foundation
import Network

actor LocalTCPRouterService {
    static let shared = LocalTCPRouterService()
    
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    
    var onConnectionStateChange: ((P2PConnectionState) -> Void)?
    var onDataReceived: ((Data) -> Void)?
    
    // Default TCP Port untuk listener
    let defaultPort: NWEndpoint.Port = 55123
    
    private init() {}
    
    /// Memulai TCP Listener di iPad
    func startHosting() {
        guard listener == nil else { return }
        
        do {
            listener = try NWListener(using: .tcp, on: defaultPort)
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task {
                    switch state {
                    case .ready:
                        HaispaceLogger.info("TCP Listener ready pada port 55123", category: "p2p")
                    case .failed(let error):
                        HaispaceLogger.error("TCP Listener gagal: \(error)", category: "p2p")
                        await self?.stopHosting()
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                Task {
                    await self?.acceptConnection(newConnection)
                }
            }
            
            listener?.start(queue: .global(qos: .userInteractive))
            
        } catch {
            HaispaceLogger.error("Gagal inisialisasi TCP Listener: \(error)", category: "p2p")
        }
    }
    
    func stopHosting() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        onConnectionStateChange?(.disconnected)
    }
    
    private func acceptConnection(_ connection: NWConnection) {
        // Jika sudah ada koneksi, batalkan yang lama
        activeConnection?.cancel()
        activeConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            Task {
                switch state {
                case .ready:
                    await self?.onConnectionStateChange?(.connected)
                    HaispaceLogger.info("Koneksi TCP klien diterima", category: "p2p")
                    await self?.receiveNextMessage(from: connection)
                case .failed(let error):
                    HaispaceLogger.warning("Koneksi TCP gagal: \(error)", category: "p2p")
                    await self?.onConnectionStateChange?(.disconnected)
                    if self?.activeConnection === connection {
                        self?.activeConnection = nil
                    }
                case .cancelled:
                    HaispaceLogger.warning("Koneksi TCP dibatalkan", category: "p2p")
                    await self?.onConnectionStateChange?(.disconnected)
                    if self?.activeConnection === connection {
                        self?.activeConnection = nil
                    }
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .global(qos: .userInteractive))
    }
    
    private func receiveNextMessage(from connection: NWConnection) {
        // Membaca framing data. 
        // Implementasi sederhana: baca frame (karena TCP bersifat stream, idealnya pakai prefix panjang frame)
        // Untuk MVP Fase 1, asumsikan payload terbungkus rapi (atau gunakan NWProtocolFramer di fase lanjut)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 10 * 1024 * 1024) { [weak self] content, _, isComplete, error in
            Task {
                if let data = content, !data.isEmpty {
                    await self?.onDataReceived?(data)
                    
                    if let message = try? P2PMessage.decode(from: data) {
                        await P2PMessageRouter.shared.route(message)
                    }
                }
                
                if error == nil && !isComplete {
                    // Lanjut baca loop
                    await self?.receiveNextMessage(from: connection)
                } else {
                    HaispaceLogger.warning("TCP Stream terhenti atau error.", category: "p2p")
                }
            }
        }
    }
    
    func sendData(_ data: Data) throws {
        guard let connection = activeConnection, connection.state == .ready else {
            throw HaispaceError.p2pConnectionLost
        }
        
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                HaispaceLogger.error("Gagal kirim TCP data: \(error)", category: "p2p")
            }
        }))
    }
}
