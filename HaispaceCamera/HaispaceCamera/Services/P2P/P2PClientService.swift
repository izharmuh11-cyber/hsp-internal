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
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }
    
    /// Mulai mencari iPad host berdasarkan QR Code Payload
    func connect(using payload: QRPairingPayload) {
        // Validasi Payload
        guard !payload.isExpired else {
            HaispaceLogger.warning("QR Code sudah expired", category: "p2p")
            Task { await onConnectionStateChange?(.failed(reason: "QR Expired")) }
            return
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
            Task { await onConnectionStateChange?(.failed(reason: "Invalid Signature")) }
            return
        }
        
        Task { await onConnectionStateChange?(.scanning) }
        
        // Setup Session
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        let safeEventId = String(payload.eventId.prefix(8))
        let serviceType = "hs-\(safeEventId)"
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        
        HaispaceLogger.info("Mulai browse P2P untuk service: \(serviceType)", category: "p2p")
    }
    
    func disconnect() {
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        browser = nil
        session = nil
        isBrowsing = false
        Task { await onConnectionStateChange?(.disconnected) }
    }
    
    func sendData(_ data: Data) throws {
        guard let session = session, !session.connectedPeers.isEmpty else {
            throw HaispaceError.p2pConnectionLost
        }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate
extension P2PClientService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task {
            switch state {
            case .connected:
                await self.onConnectionStateChange?(.connected)
                HaispaceLogger.info("MPC terhubung ke: \(peerID.displayName)", category: "p2p")
            case .connecting:
                await self.onConnectionStateChange?(.connecting)
            case .notConnected:
                await self.onConnectionStateChange?(.disconnected)
                HaispaceLogger.warning("MPC terputus dari: \(peerID.displayName)", category: "p2p")
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task {
            await self.onDataReceived?(data)
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
            browser.invitePeer(peerID, to: self.session!, withContext: nil, timeout: 30)
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        HaispaceLogger.warning("Kehilangan sinyal host: \(peerID.displayName)", category: "p2p")
    }
}
