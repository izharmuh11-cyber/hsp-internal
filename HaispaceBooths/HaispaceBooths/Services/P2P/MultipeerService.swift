// MultipeerService.swift
// HaispaceBooths — Services/P2P
//
// Layanan Apple Multipeer Connectivity (MPC) untuk Direct P2P.
// Digunakan sebagai metode komunikasi utama tanpa router eksternal.
//
// Ref: docs/design/08_p2p_communication.md

import Foundation
import MultipeerConnectivity
import OSLog

actor MultipeerService: NSObject {
    static let shared = MultipeerService()

    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var isAdvertising = false

    // State callback
    private var onConnectionStateChange: (@Sendable (P2PConnectionState) -> Void)?
    private var onDataReceived: (@Sendable (Data) -> Void)?

    func registerConnectionStateCallback(_ callback: @escaping @Sendable (P2PConnectionState) -> Void) {
        self.onConnectionStateChange = callback
    }

    func registerDataCallback(_ callback: @escaping @Sendable (Data) -> Void) {
        self.onDataReceived = callback
    }

    private override init() {
        self.peerID = MCPeerID(displayName: "HaiBooth iPad")
        super.init()
    }

    /// Mulai advertising sebagai host iPad
    func startHosting(eventId: String, boothId: String) {
        guard !isAdvertising else { return }

        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self

        // Gunakan serviceType statik "haibooth" yang didaftarkan di Info.plist
        // Gunakan discoveryInfo untuk mengirim eventId secara dinamis
        let serviceType = "haibooth"
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["booth": boothId, "eventId": eventId],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        
        onConnectionStateChange?(.scanning)
        HaispaceLogger.info("Memulai MPC advertising dengan serviceType: \(serviceType) (eventId: \(eventId))", category: "p2p")
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        advertiser = nil
        session = nil
        isAdvertising = false
        onConnectionStateChange?(.disconnected)
        HaispaceLogger.info("MPC hosting dihentikan", category: "p2p")
    }

    func sendData(_ data: Data) throws {
        guard let session = session, !session.connectedPeers.isEmpty else {
            throw HaispaceError.p2pConnectionLost
        }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
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
            
            if data.count > 4 && data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1 {
                await StreamingDecoderService.shared.enqueue(nalu: data)
            } else if let message = try? P2PMessage.decode(from: data) {
                await P2PMessageRouter.shared.route(message)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Digunakan untuk stream file/video berukuran sangat besar (bila tidak memakai chunk)
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil, let localURL = localURL else {
            if let error = error {
                HaispaceLogger.error(error)
            } else {
                HaispaceLogger.error(HaispaceError.unknown(underlying: NSError(domain: "MultipeerService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to receive resource"])))
            }
            return
        }
        
        do {
            let data = try Data(contentsOf: localURL)
            Task {
                await P2PMessageRouter.shared.route(.photoFull(id: resourceName, fullData: data))
                HaispaceLogger.info("MPC sukses menerima resource foto penuh: \(resourceName)", category: "p2p")
            }
        } catch {
            HaispaceLogger.error(error)
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task {
            HaispaceLogger.info("Menerima MPC invitation dari: \(peerID.displayName)", category: "p2p")
            // Otomatis accept koneksi dari aplikasi HaispaceCamera (Validasi tambahan bisa via token)
            await invitationHandler(true, self.session)
        }
    }
}
