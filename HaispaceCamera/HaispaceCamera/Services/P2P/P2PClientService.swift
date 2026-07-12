// P2PClientService.swift
// HaispaceCamera — Services/P2P
//
// MCNearbyServiceBrowser untuk menemukan iPad berdasarkan event ID.
// Serta mengelola koneksi fallback ke Local TCP jika dipilih.

import Foundation
import MultipeerConnectivity

actor P2PClientService: NSObject {
    static let shared = P2PClientService()
    
    private let peerID: MCPeerID
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var isBrowsing = false
    
    // Fallback connection via Network framework bisa diimplementasi di sini
    
    var onConnectionStateChange: ((P2PConnectionState) -> Void)?
    var onDataReceived: ((Data) -> Void)?
    
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
                    if let callback = await self.onConnectionStateChange { callback(.failed(reason: "QR Expired")) }
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
                if let callback = await self.onConnectionStateChange { callback(.failed(reason: "Invalid Signature")) }
            }
            return
        }
        
        Task {
            if let callback = await self.onConnectionStateChange { callback(.scanning) }
        }
        
        // TODO: Coba TCP Socket terlebih dahulu menggunakan payload.ip dan payload.port.
        // Jika TCP gagal dalam 3 detik, fallback ke MultipeerConnectivity di bawah ini.
        HaispaceLogger.info("Mencoba koneksi P2P (Prioritas: TCP -> MPC fallback)", category: "p2p")
        
        startMPCFallback(payload: payload)
    }
    
    private func startMPCFallback(payload: QRPairingPayload) {
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
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        browser = nil
        session = nil
        isBrowsing = false
        Task {
            if let callback = await self.onConnectionStateChange { callback(.disconnected) }
        }
    }
    
    func sendData(_ data: Data) throws {
        guard let session = session, !session.connectedPeers.isEmpty else {
            throw NSError(domain: "P2PClientService", code: -1, userInfo: [NSLocalizedDescriptionKey: "P2P Connection Lost"])
        }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
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
