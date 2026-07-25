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
    
    private var onConnectionStateChange: (@Sendable (P2PConnectionState) -> Void)?
    private var onDataReceived: (@Sendable (Data) -> Void)?
    
    func registerConnectionStateCallback(_ callback: @escaping @Sendable (P2PConnectionState) -> Void) {
        self.onConnectionStateChange = callback
    }
    
    func registerDataCallback(_ callback: @escaping @Sendable (Data) -> Void) {
        self.onDataReceived = callback
    }
    
    // Port TCP statis untuk listener — sama dengan nilai di PairingSetupView
    let defaultPort: NWEndpoint.Port = 55123
    
    private var currentListeningPort: UInt16 = 0
    
    private init() {}
    
    /// Memulai TCP Listener di iPad.
    /// Idempotent: tidak me-restart listener jika port yang sama sudah aktif.
    func startHosting(port: Int? = nil) {
        let listenPort: NWEndpoint.Port
        if let portVal = port, let p = NWEndpoint.Port(rawValue: UInt16(portVal)) {
            listenPort = p
        } else {
            listenPort = defaultPort
        }
        
        // Jika listener sudah aktif di port yang sama, tidak perlu restart
        if listener != nil && currentListeningPort == listenPort.rawValue {
            HaispaceLogger.info("TCP Listener sudah aktif di port \(listenPort.rawValue) — skip restart", category: "p2p")
            return
        }
        
        // Jika ada listener di port berbeda, hentikan dulu
        if listener != nil {
            listener?.cancel()
            listener = nil
        }
        
        currentListeningPort = listenPort.rawValue
        
        do {
            listener = try NWListener(using: .tcp, on: listenPort)
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task {
                    switch state {
                    case .ready:
                        HaispaceLogger.info("TCP Listener ready pada port \(listenPort.rawValue)", category: "p2p")
                    case .failed(let error):
                        HaispaceLogger.error(error)
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
            HaispaceLogger.error(error)
        }
    }
    
    func stopHosting() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        onConnectionStateChange?(.disconnected)
    }
    
    private func clearConnection(ifMatches connection: NWConnection) {
        if self.activeConnection === connection {
            self.activeConnection = nil
        }
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
                    await self?.startReading(from: connection)
                case .failed(let error):
                    HaispaceLogger.warning("Koneksi TCP gagal: \(error)", category: "p2p")
                    await self?.onConnectionStateChange?(.disconnected)
                    await self?.clearConnection(ifMatches: connection)
                case .cancelled:
                    HaispaceLogger.warning("Koneksi TCP dibatalkan", category: "p2p")
                    await self?.onConnectionStateChange?(.disconnected)
                    await self?.clearConnection(ifMatches: connection)
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .global(qos: .userInteractive))
    }
    
    private func startReading(from connection: NWConnection) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                while true {
                    // 1. Baca 4 byte header
                    let headerData = try await self.readExactBytes(connection: connection, count: 4)
                    guard headerData.count == 4 else { break }
                    
                    // Convert 4 bytes to UInt32 (big-endian) — Safe from unaligned memory access crash
                    let length = headerData.reduce(0) { ($0 << 8) + UInt32($1) }
                    guard length > 0 else { continue }
                    
                    // 2. Baca exact body
                    let bodyData = try await self.readExactBytes(connection: connection, count: Int(length))
                    guard bodyData.count == Int(length) else { break }
                    
                    // 3. Proses data
                    await self.onDataReceived?(bodyData)
                    if bodyData.count > 4 && bodyData[0] == 0 && bodyData[1] == 0 && bodyData[2] == 0 && bodyData[3] == 1 {
                        await StreamingDecoderService.shared.enqueue(nalu: bodyData)
                    } else if let message = try? P2PMessage.decode(from: bodyData) {
                        await P2PMessageRouter.shared.route(message)
                    }
                }
            } catch {
                HaispaceLogger.warning("TCP Stream terhenti atau error: \(error)", category: "p2p")
            }
            
            await self.onConnectionStateChange?(.disconnected)
            await self.clearConnection(ifMatches: connection)
        }
    }
    
    private func readExactBytes(connection: NWConnection, count: Int) async throws -> Data {
        var accumulated = Data()
        while accumulated.count < count {
            let needed = count - accumulated.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let content = content {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(throwing: NSError(domain: "LocalTCPRouterService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection closed"]))
                    } else {
                        continuation.resume(throwing: NSError(domain: "LocalTCPRouterService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                    }
                }
            }
            accumulated.append(chunk)
        }
        return accumulated
    }
    
    func sendData(_ data: Data) throws {
        guard let connection = activeConnection, connection.state == .ready else {
            throw HaispaceError.p2pConnectionLost
        }
        
        // Tambah header panjang data 4-byte (big-endian) — Safe from stack-escaping pointer issue
        var length = UInt32(data.count).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        let payload = header + data
        
        connection.send(content: payload, completion: .contentProcessed({ error in
            if let error = error {
                HaispaceLogger.error(error)
            }
        }))
    }
}
