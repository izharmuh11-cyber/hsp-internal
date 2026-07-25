// DeliveryQueue.swift
// HaispaceBooths — Core/Delivery
//
// Offline-first persistent queue untuk pengiriman softcopy (WhatsApp/link).
//
// ARSITEKTUR:
//   ┌──────────────┐     enqueue()      ┌─────────────┐
//   │  Workflow    │ ─────────────────► │  Queue JSONL │
//   │  Orchestrator│                    │  (Disk)      │
//   └──────────────┘                    └──────┬──────┘
//                                              │ NWPathMonitor
//                                              ▼
//                                     ┌─────────────────┐
//                                     │  Delivery Worker │
//                                     │  (async retry)   │
//                                     └──────────────────┘
//
// LIFECYCLE ENTRY:
//   pending → sending → delivered  ✅
//                    → failed      (retry 1–3)
//                    → permanentlyFailed  → MissionControl alert
//
// FILE FORMAT:
//   Documents/delivery_queue.jsonl  → satu baris per entry (append-only)
//   Entries yang completed/failed disweep harian
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar 3: Offline-First

import Foundation
import Network

// MARK: - DeliveryEntry

public struct DeliveryEntry: Codable, Identifiable, Sendable {

    public let id: String               // UUID
    public let sessionId: String
    public let recipientPhone: String   // Format: +62XXXXXXXXXX
    public let photoURL: String         // URL foto di cloud storage
    public let softcopyType: SoftcopyType
    public let enqueuedAt: Date

    public var status: DeliveryStatus
    public var attemptCount: Int
    public var lastAttemptAt: Date?
    public var lastError: String?       // Error message (tidak tampil ke tamu)
    public var deliveredAt: Date?

    public enum SoftcopyType: String, Codable, Sendable {
        case whatsapp   = "whatsapp"
        case link       = "link"        // Link download via SMS/email
    }

    public enum DeliveryStatus: String, Codable, Sendable {
        case pending            // Menunggu koneksi
        case sending            // Sedang dikirim
        case delivered          // Berhasil terkirim
        case failed             // Gagal, tapi masih bisa retry
        case permanentlyFailed  // Gagal 3x — eskalasi ke operator
    }

    public init(
        sessionId: String,
        recipientPhone: String,
        photoURL: String,
        softcopyType: SoftcopyType = .whatsapp
    ) {
        self.id = UUID().uuidString
        self.sessionId = sessionId
        self.recipientPhone = recipientPhone
        self.photoURL = photoURL
        self.softcopyType = softcopyType
        self.enqueuedAt = Date()
        self.status = .pending
        self.attemptCount = 0
    }
}

// MARK: - DeliveryQueue

public actor DeliveryQueue {

    // MARK: - Properties

    private static let maxRetryAttempts = 3
    private static let retryDelaySeconds: [TimeInterval] = [30, 120, 300] // 30s, 2m, 5m

    private let queueFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var entries: [DeliveryEntry] = []
    private var isProcessing = false

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "hsp.delivery.monitor")
    private var isOnline = false

    // Callback: dipanggil saat ada entry permanentlyFailed (untuk MissionControl)
    public var onPermanentFailure: ((DeliveryEntry) -> Void)?

    // MARK: - Init

    public init() {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.queueFileURL = baseDir.appendingPathComponent("delivery_queue.jsonl")

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Lifecycle

    public func start() {
        loadFromDisk()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handleNetworkChange(path.status == .satisfied)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Public API

    /// Tambah pengiriman baru ke antrean
    public func enqueue(
        sessionId: String,
        recipientPhone: String,
        photoURL: String,
        type: DeliveryEntry.SoftcopyType = .whatsapp
    ) {
        let entry = DeliveryEntry(
            sessionId: sessionId,
            recipientPhone: recipientPhone,
            photoURL: photoURL,
            softcopyType: type
        )
        entries.append(entry)
        saveToDisk()

        if isOnline {
            Task { await processQueue() }
        }
    }

    /// Jumlah entry yang pending (untuk MissionControl badge)
    public var pendingCount: Int {
        entries.filter { $0.status == .pending || $0.status == .failed }.count
    }

    /// Semua entry yang permanently failed (untuk MissionControl alert)
    public var permanentlyFailedEntries: [DeliveryEntry] {
        entries.filter { $0.status == .permanentlyFailed }
    }

    /// Retry entry yang permanently failed secara manual (dari operator)
    public func manualRetry(entryId: String) async {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[index].status = .pending
        entries[index].attemptCount = 0
        entries[index].lastError = nil
        saveToDisk()
        await processQueue()
    }

    // MARK: - Private: Queue Processing

    private func handleNetworkChange(_ online: Bool) {
        self.isOnline = online
        if online && pendingCount > 0 {
            Task { await processQueue() }
        }
    }

    private func processQueue() async {
        guard isOnline, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let pending = entries
            .filter { $0.status == .pending || $0.status == .failed }
            .filter { entry in
                // Respek retry delay
                guard let lastAttempt = entry.lastAttemptAt else { return true }
                let delayIndex = min(entry.attemptCount, Self.retryDelaySeconds.count - 1)
                let delay = Self.retryDelaySeconds[delayIndex]
                return Date().timeIntervalSince(lastAttempt) >= delay
            }

        for entry in pending {
            await attemptDelivery(entry)
        }
    }

    private func attemptDelivery(_ entry: DeliveryEntry) async {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }

        entries[index].status = .sending
        entries[index].lastAttemptAt = Date()
        entries[index].attemptCount += 1

        do {
            try await performDelivery(entry)
            entries[index].status = .delivered
            entries[index].deliveredAt = Date()
        } catch {
            entries[index].lastError = error.localizedDescription

            if entries[index].attemptCount >= Self.maxRetryAttempts {
                entries[index].status = .permanentlyFailed
                let failedEntry = entries[index]
                // Eskalasi ke MissionControl
                if let callback = self.onPermanentFailure {
                    Task { @MainActor in
                        callback(failedEntry)
                    }
                }
            } else {
                entries[index].status = .failed
            }
        }

        saveToDisk()
    }

    /// Actual delivery implementation — override/inject untuk testing
    private func performDelivery(_ entry: DeliveryEntry) async throws {
        // TODO: Integrate dengan WhatsApp Business API atau link generation service
        // Untuk sekarang: simulasi network call
        guard isOnline else {
            throw DeliveryError.networkUnavailable
        }

        // Placeholder: akan diganti dengan actual API call
        // try await WhatsAppService.send(to: entry.recipientPhone, photoURL: entry.photoURL)
        try await Task.sleep(nanoseconds: 500_000_000) // Simulasi 0.5s

        if entry.recipientPhone.isEmpty {
            throw DeliveryError.invalidRecipient
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let content = try? String(contentsOf: queueFileURL, encoding: .utf8) else { return }
        entries = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? decoder.decode(DeliveryEntry.self, from: Data(line.utf8))
            }
            // Filter delivered & permanently failed yang sudah lebih dari 7 hari
            .filter { entry in
                let isOld = Date().timeIntervalSince(entry.enqueuedAt) > 7 * 86400
                let isTerminal = entry.status == .delivered || entry.status == .permanentlyFailed
                return !(isOld && isTerminal)
            }
    }

    private func saveToDisk() {
        let lines = entries.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry),
                  let line = String(data: data, encoding: .utf8) else { return nil }
            return line
        }.joined(separator: "\n")

        try? lines.write(to: queueFileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - DeliveryError

private enum DeliveryError: LocalizedError {
    case networkUnavailable
    case invalidRecipient
    case apiFailure(Int)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable: return "Tidak ada koneksi internet"
        case .invalidRecipient: return "Nomor penerima tidak valid"
        case .apiFailure(let code): return "API Error: HTTP \(code)"
        }
    }
}
