// P2PClientService.swift
// HaispaceCamera — Services/P2P
//
// MCNearbyServiceBrowser untuk menemukan iPad berdasarkan event ID.
// Serta mengelola koneksi fallback ke Local TCP jika dipilih.

import Foundation
import MultipeerConnectivity
import Network

actor P2PClientService: NSObject {
    static let shared = P2PClientService()
    
    private let peerID: MCPeerID
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var isBrowsing = false
    private var activeEventId: String?
    
    // Fallback connection via Network framework
    private var tcpConnection: NWConnection?
    private var tcpTimeoutTask: Task<Void, Never>?
    private var fallbackTriggered = false
    
    private var onConnectionStateChange: (@Sendable (P2PConnectionState) -> Void)?
    private var onDataReceived: (@Sendable (Data) -> Void)?
    
    func registerConnectionStateCallback(_ callback: @escaping @Sendable (P2PConnectionState) -> Void) {
        self.onConnectionStateChange = callback
    }
    
    func registerDataCallback(_ callback: @escaping @Sendable (Data) -> Void) {
        self.onDataReceived = callback
    }
    
    private override init() {
        self.peerID = MCPeerID(displayName: "HaispaceCamera-\(UUID().uuidString.prefix(4))")
        super.init()
    }
    
    /// Mulai mencari iPad host berdasarkan QR Code Payload
    func connect(using payload: QRPairingPayload, isAutoReconnect: Bool = false) {
        // Validasi Payload (Skip jika auto-reconnect karena payload lama pasti expired)
        if !isAutoReconnect {
            guard !payload.isExpired else {
                HaispaceLogger.warning("QR Code sudah expired", category: "p2p")
                Task {
                    if let callback = self.onConnectionStateChange { callback(.failed(reason: "QR Expired")) }
                }
                return
            }
        }
        
        self.activeEventId = payload.eventId
        
        let signature = QRPairingPayload.generateSignature(
            peerId: payload.peerId,
            ip: payload.ip,
            port: payload.port,
            eventId: payload.eventId,
            ts: payload.ts
        )
        
        guard signature == payload.sig else {
            HaispaceLogger.error("Signature QR Payload tidak valid", category: "p2p")
            Task {
                if let callback = self.onConnectionStateChange { callback(.failed(reason: "Invalid Signature")) }
            }
            return
        }
        
        Task {
            if let callback = self.onConnectionStateChange { callback(.scanning) }
        }
        
        HaispaceLogger.info("Mencoba koneksi P2P (Prioritas: TCP -> MPC fallback)", category: "p2p")
        
        // Coba koneksi TCP Client ke iPad
        connectTCP(ip: payload.ip, port: payload.port, payload: payload)
    }
    
    private func connectTCP(ip: String, port: Int, payload: QRPairingPayload) {
        let host = NWEndpoint.Host(ip)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            HaispaceLogger.error("Port TCP tidak valid: \(port)", category: "p2p")
            startMPCFallback(payload: payload)
            return
        }
        
        let connection = NWConnection(host: host, port: endpointPort, using: .tcp)
        self.tcpConnection = connection
        self.fallbackTriggered = false
        
        self.cancelTimeoutTask()
        
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard let self = self else { return }
                await self.triggerFallback(payload: payload)
            } catch {
                // Task was cancelled, do nothing
            }
        }
        self.tcpTimeoutTask = timeoutTask
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    await self.cancelTimeoutTask()
                    await self.handleTCPReady(connection: connection, ip: ip, port: port)
                case .failed(let error):
                    await self.cancelTimeoutTask()
                    HaispaceLogger.warning("Koneksi TCP Client gagal: \(error)", category: "p2p")
                    await self.triggerFallback(payload: payload)
                case .cancelled:
                    await self.cancelTimeoutTask()
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .global(qos: .userInteractive))
    }
    
    private func cancelTimeoutTask() {
        self.tcpTimeoutTask?.cancel()
        self.tcpTimeoutTask = nil
    }
    
    private func triggerFallback(payload: QRPairingPayload) {
        if !self.fallbackTriggered {
            self.fallbackTriggered = true
            HaispaceLogger.warning("Koneksi TCP gagal atau timeout. Fallback ke MPC.", category: "p2p")
            self.cancelTCPConnection()
            self.startMPCFallback(payload: payload)
        }
    }
    
    private func handleTCPReady(connection: NWConnection, ip: String, port: Int) {
        if let callback = self.onConnectionStateChange { callback(.connected) }
        HaispaceLogger.info("Koneksi TCP Client terhubung ke iPad: \(ip):\(port)", category: "p2p")
        self.receiveTCPData(connection)
    }
    
    private func cancelTCPConnection() {
        tcpConnection?.cancel()
        tcpConnection = nil
    }
    
    private func receiveTCPData(_ connection: NWConnection) {
        Task { [weak self] in
            do {
                while true {
                    guard let self = self else { break }
                    // 1. Baca header 4 byte
                    let headerData = try await self.readExactBytes(connection: connection, count: 4)
                    guard headerData.count == 4 else { break }
                    
                    // Convert to UInt32 (big-endian)
                    let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    guard length > 0 else { continue }
                    
                    // 2. Baca body data
                    let bodyData = try await self.readExactBytes(connection: connection, count: Int(length))
                    guard bodyData.count == Int(length) else { break }
                    
                    // 3. Callback
                    if let callback = await self.onDataReceived {
                        callback(bodyData)
                    }
                }
            } catch {
                HaispaceLogger.warning("TCP Stream terhenti dari iPad atau error: \(error)", category: "p2p")
            }
            
            if let self = self {
                await self.cancelTCPConnection()
                if let callback = await self.onConnectionStateChange {
                    callback(.disconnected)
                }
            }
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
                        continuation.resume(throwing: NSError(domain: "P2PClientService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection closed"]))
                    } else {
                        continuation.resume(throwing: NSError(domain: "P2PClientService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                    }
                }
            }
            accumulated.append(chunk)
        }
        return accumulated
    }
    
    private func startMPCFallback(payload: QRPairingPayload) {
        // Pastikan session bersih sebelum memulai MPC
        session?.disconnect()
        
        // Setup Session
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        self.activeEventId = payload.eventId
        let serviceType = "haibooth"
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        
        HaispaceLogger.info("Mulai browse P2P (MPC Fallback) untuk service: \(serviceType) dengan eventId: \(payload.eventId)", category: "p2p")
    }
    
    func disconnect() {
        cancelTCPConnection()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        browser = nil
        session = nil
        isBrowsing = false
        Task {
            if let callback = self.onConnectionStateChange { callback(.disconnected) }
        }
    }
    
    func sendData(_ data: Data) throws {
        if let tcpConnection = tcpConnection, tcpConnection.state == .ready {
            // Tambah header panjang data 4-byte (big-endian)
            var length = UInt32(data.count).bigEndian
            let header = Data(bytes: &length, count: 4)
            let payload = header + data
            
            tcpConnection.send(content: payload, completion: .contentProcessed({ error in
                if let error = error {
                    HaispaceLogger.error("Gagal mengirim data via TCP: \(error)", category: "p2p")
                }
            }))
        } else {
            guard let session = session, !session.connectedPeers.isEmpty else {
                throw NSError(domain: "P2PClientService", code: -1, userInfo: [NSLocalizedDescriptionKey: "P2P Connection Lost"])
            }
            
            // Cek apakah data adalah video frame (dimulai dengan start code 0x00000001)
            let isVideoFrame = data.count > 4 && data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1
            let mode: MCSessionSendDataMode = isVideoFrame ? .unreliable : .reliable
            try session.send(data, toPeers: session.connectedPeers, with: mode)
        }
    }
    
    /// Mengirim foto resolusi tinggi secara aman. Menggunakan TCP jika siap, atau fallbacks ke MPC sendResource untuk file besar.
    func sendPhotoFull(id: String, data: Data) async throws {
        if let tcpConnection = tcpConnection, tcpConnection.state == .ready {
            let fullMsg = P2PMessage.photoFull(id: id, fullData: data)
            try sendData(fullMsg.encode())
        } else {
            guard let session = session, !session.connectedPeers.isEmpty else {
                throw NSError(domain: "P2PClientService", code: -1, userInfo: [NSLocalizedDescriptionKey: "P2P Connection Lost"])
            }
            
            // Tulis data ke file temporer agar bisa dikirim via sendResource
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("\(id).jpg")
            try data.write(to: fileURL)
            
            for peer in session.connectedPeers {
                session.sendResource(at: fileURL, withName: id, toPeer: peer) { error in
                    // Bersihkan file temporer
                    try? FileManager.default.removeItem(at: fileURL)
                    if let error = error {
                        HaispaceLogger.error("Gagal mengirim resource MPC \(id): \(error.localizedDescription)", category: "p2p")
                    } else {
                        HaispaceLogger.info("Resource MPC terkirim: \(id)", category: "p2p")
                    }
                }
            }
        }
    }
    
    func isConnected() -> Bool {
        if let tcpConnection = tcpConnection, tcpConnection.state == .ready {
            return true
        }
        if let session = session, !session.connectedPeers.isEmpty {
            return true
        }
        return false
    }
}

// MARK: - MCSessionDelegate
extension P2PClientService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task {
            let callback = await self.onConnectionStateChange
            switch state {
            case .connected:
                callback?(.connected)
                HaispaceLogger.info("MPC terhubung ke: \(peerID.displayName)", category: "p2p")
            case .connecting:
                callback?(.connecting)
            case .notConnected:
                callback?(.disconnected)
                HaispaceLogger.warning("MPC terputus dari: \(peerID.displayName)", category: "p2p")
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task {
            let callback = await self.onDataReceived
            callback?(data)
            // Di iPhone, sebagian pesan bisa ditangkap dan diroute
            // P2PMessageRouter untuk Camera bisa diimplementasikan atau langsung handle
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate
extension P2PClientService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task {
            let activeEventId = await self.activeEventId
            HaispaceLogger.info("Ditemukan iPad host: \(peerID.displayName), discoveryInfo: \(String(describing: info))", category: "p2p")
            
            // Verifikasi eventId sebelum melakukan invitation
            guard let info = info, info["eventId"] == activeEventId else {
                HaispaceLogger.warning("Abaikan iPad host karena eventId tidak cocok (Info: \(info?["eventId"] ?? "nil"), Target: \(activeEventId ?? "nil"))", category: "p2p")
                return
            }
            
            // Otomatis invite host
            if let activeSession = await self.session {
                browser.invitePeer(peerID, to: activeSession, withContext: nil, timeout: 30)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        HaispaceLogger.warning("Kehilangan sinyal host: \(peerID.displayName)", category: "p2p")
    }
}
