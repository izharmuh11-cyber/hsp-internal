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
    
    // Fallback connection via Network framework
    private var tcpConnection: NWConnection?
    
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
        
        // Timer timeout 3 detik
        var fallbackTriggered = false
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                if !fallbackTriggered {
                    fallbackTriggered = true
                    HaispaceLogger.warning("Koneksi TCP timeout (3s). Fallback ke MPC.", category: "p2p")
                    await self.cancelTCPConnection()
                    await self.startMPCFallback(payload: payload)
                }
            }
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                guard let self = self else { return }
                switch state {
                case .ready:
                    timeoutTimer.invalidate()
                    if let callback = self.onConnectionStateChange { callback(.connected) }
                    HaispaceLogger.info("Koneksi TCP Client terhubung ke iPad: \(ip):\(port)", category: "p2p")
                    self.receiveTCPData(connection)
                case .failed(let error):
                    timeoutTimer.invalidate()
                    if !fallbackTriggered {
                        fallbackTriggered = true
                        HaispaceLogger.warning("Koneksi TCP Client gagal: \(error). Fallback ke MPC.", category: "p2p")
                        await self.cancelTCPConnection()
                        await self.startMPCFallback(payload: payload)
                    }
                case .cancelled:
                    timeoutTimer.invalidate()
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .global(qos: .userInteractive))
    }
    
    private func cancelTCPConnection() {
        tcpConnection?.cancel()
        tcpConnection = nil
    }
    
    private func receiveTCPData(_ connection: NWConnection) {
        Task { [weak self] in
            do {
                while true {
                    // 1. Baca header 4 byte
                    let headerData = try await readExactBytes(connection: connection, count: 4)
                    guard headerData.count == 4 else { break }
                    
                    // Convert to UInt32 (big-endian)
                    let length = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    guard length > 0 else { continue }
                    
                    // 2. Baca body data
                    let bodyData = try await readExactBytes(connection: connection, count: Int(length))
                    guard bodyData.count == Int(length) else { break }
                    
                    // 3. Callback
                    if let self = self {
                        if let callback = await self.onConnectionStateChange { // Wait, is connectionState callback or data callback? It's data callback!
                            // Wait, let's call the data callback
                        }
                        if let callback = await self.onDataReceived {
                            callback(bodyData)
                        }
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
        
        let safeEventId = String(payload.eventId.prefix(8))
        let serviceType = "hs-\(safeEventId)"
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        
        HaispaceLogger.info("Mulai browse P2P (MPC Fallback) untuk service: \(serviceType)", category: "p2p")
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
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
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
            HaispaceLogger.info("Ditemukan iPad host: \(peerID.displayName)", category: "p2p")
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
