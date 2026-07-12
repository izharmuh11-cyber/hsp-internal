// DeliveryStore.swift
// HaispaceBooths — Core/State
//
// Store untuk status pengiriman foto ke tamu setelah pembayaran.
// Mendukung: AirDrop, Local Network (Bonjour HTTP), Cloud Link.
//
// Ref: docs/design/10_photo_delivery.md
// Ref: docs/design/40_concurrency_strategy.md — URLSession Background

import Foundation
import Observation

// MARK: - DeliveryMethod

enum DeliveryMethod: CaseIterable {
    case airdrop        // AirDrop ke iPhone tamu (iPhone saja)
    case localNetwork   // QR Code → HTTP server Bonjour lokal (semua HP)
    case cloudLink      // Link download dari cloud (perlu internet, 7-hari TTL)

    var displayName: String {
        switch self {
        case .airdrop: return "AirDrop"
        case .localNetwork: return "Scan QR"
        case .cloudLink: return "Link Cloud"
        }
    }

    var iconName: String {
        switch self {
        case .airdrop: return "airplayaudio"
        case .localNetwork: return "wifi"
        case .cloudLink: return "cloud.fill"
        }
    }

    var description: String {
        switch self {
        case .airdrop: return "Kirim langsung ke iPhone tamu via AirDrop"
        case .localNetwork: return "Scan QR → download tanpa internet"
        case .cloudLink: return "Link tersedia 7 hari via internet"
        }
    }
}

// MARK: - DeliveryStatus

enum DeliveryStatus: Equatable {
    case idle
    case preparingFiles     // Render final files untuk delivery
    case delivering         // Sedang mengirim (AirDrop / HTTP)
    case delivered          // Berhasil diterima tamu
    case uploading          // Upload ke cloud (background)
    case cloudReady(url: String) // Cloud link siap
    case failed(String)

    var isComplete: Bool {
        switch self {
        case .delivered, .cloudReady: return true
        default: return false
        }
    }
}

// MARK: - DeliveryStore

@Observable
final class DeliveryStore {

    // MARK: State
    var status: DeliveryStatus = .idle
    var selectedMethod: DeliveryMethod?
    var availableMethods: [DeliveryMethod] = DeliveryMethod.allCases

    // Local Network Server state
    var localServerURL: String?     // URL yang di-encode ke QR code (misal: http://192.168.1.x:PORT/session)
    var localServerPort: Int?

    // Cloud upload state
    var uploadProgress: Double = 0.0    // 0.0 – 1.0
    var cloudDownloadURL: String?       // URL final setelah upload selesai

    // AirDrop state
    var airdropDeclined: Bool = false   // Tamu decline AirDrop

    // Retry tracking
    var deliveryAttempts: Int = 0

    // MARK: Computed

    var isUploading: Bool {
        if case .uploading = status { return true }
        return false
    }

    var isCloudReady: Bool {
        if case .cloudReady = status { return true }
        return false
    }

    var uploadProgressPercentage: Int {
        Int(uploadProgress * 100)
    }

    // MARK: - Actions

    /// Mulai proses delivery setelah pembayaran sukses
    @MainActor
    func beginDelivery(photos: [RenderedPhoto], method: DeliveryMethod) {
        selectedMethod = method
        deliveryAttempts = 0
        status = .preparingFiles

        Task {
            switch method {
            case .airdrop:
                await sendViaAirDrop(photos: photos)
            case .localNetwork:
                await startLocalServer(photos: photos)
            case .cloudLink:
                await beginCloudUpload(photos: photos)
            }
        }
    }

    /// Upload foto ke cloud storage (background, setelah sesi selesai)
    @MainActor
    func beginCloudUpload(photos: [RenderedPhoto]) async {
        status = .uploading
        uploadProgress = 0.0

        // TODO: Fase 3 — implementasi CloudUploadService dengan URLSession.background
        HaispaceLogger.info("Cloud upload dimulai untuk \(photos.count) foto", category: "delivery")

        // Simulasi upload progress untuk development
        for i in 1...photos.count {
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                self.uploadProgress = Double(i) / Double(photos.count)
            }
        }

        await MainActor.run {
            self.cloudDownloadURL = "https://photos.haispace.id/session/PLACEHOLDER"
            self.status = .cloudReady(url: self.cloudDownloadURL ?? "")
        }
    }

    private func sendViaAirDrop(photos: [RenderedPhoto]) async {
        // TODO: Fase 2 — implementasi UIActivityViewController untuk AirDrop
        HaispaceLogger.info("AirDrop delivery dimulai", category: "delivery")
        await MainActor.run { status = .delivering }
    }

    private func startLocalServer(photos: [RenderedPhoto]) async {
        HaispaceLogger.info("Local network server dimulai", category: "delivery")
        
        do {
            try await BonjourDownloadServer.shared.start()
        } catch {
            HaispaceLogger.error(error)
        }
        
        var hostedURLs: [String] = []
        for photo in photos {
            let url = await BonjourDownloadServer.shared.hostPhoto(id: photo.id, data: photo.data)
            HaispaceLogger.info("Foto di-host di local server: \(url)", category: "delivery")
            hostedURLs.append(url)
        }
        
        let serverPort = await BonjourDownloadServer.shared.port.rawValue
        let finalHostedURLs = hostedURLs
        await MainActor.run {
            self.localServerPort = Int(serverPort)
            self.localServerURL = finalHostedURLs.first
            self.status = .delivering
        }
    }

    /// Reset state delivery (untuk sesi baru)
    @MainActor
    func reset() {
        BonjourDownloadServer.shared.stop()
        
        status = .idle
        selectedMethod = nil
        localServerURL = nil
        localServerPort = nil
        uploadProgress = 0.0
        cloudDownloadURL = nil
        airdropDeclined = false
        deliveryAttempts = 0
    }
}
