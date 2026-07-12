// BoothConfigStore.swift
// HaispaceBooths — Core/State
//
// Store untuk konfigurasi booth yang aktif:
// paket yang tersedia, frame yang di-download, add-on status.
// Di-load dari CoreData lokal saat app launch, di-sync dari cloud saat online.
//
// Ref: docs/design/39_state_architecture.md — BoothConfigStore
// Ref: docs/design/11_booth_modes.md, docs/design/06_features.md

import Foundation
import Observation

// MARK: - BoothConfigStore

@Observable
final class BoothConfigStore {

    // MARK: State

    /// Event yang sedang aktif (dipilih operator saat setup)
    var activeEventId: String?
    var activeEventName: String?
    var activeEventDate: Date?
    var activeEventVenue: String?

    /// Paket yang tersedia untuk tamu pilih
    var activePackages: [BoothPackage] = []

    /// Frame overlay yang tersedia untuk sesi ini
    var availableFrames: [PhotoFrame] = []

    /// Frame yang sudah di-download ke lokal (siap digunakan offline)
    var downloadedFrameIds: Set<String> = []

    /// Konfigurasi umum booth
    var boothMode: BoothMode = .standard
    var maxQueueSize: Int = 50
    var sessionTimeoutSeconds: Int = 1800   // 30 menit sebelum session auto-expired

    // MARK: Computed

    /// Apakah booth sudah dikonfigurasi dan siap menerima tamu?
    var isConfigured: Bool {
        !activePackages.isEmpty && activeEventId != nil
    }

    /// Frame yang siap digunakan offline
    var offlineReadyFrames: [PhotoFrame] {
        availableFrames.filter { downloadedFrameIds.contains($0.id) }
    }

    /// Apakah semua frame sudah di-download?
    var allFramesDownloaded: Bool {
        !availableFrames.isEmpty &&
        availableFrames.allSatisfy { downloadedFrameIds.contains($0.id) }
    }

    // MARK: - Actions

    /// Load konfigurasi dari CoreData lokal (untuk startup offline)
    @MainActor
    func loadFromLocal() async {
        // TODO: Fase 3 — implementasi CoreDataService.fetchBoothConfig()
        HaispaceLogger.info("BoothConfig: load from local CoreData", category: "config")
    }

    /// Sync konfigurasi dari cloud (saat ada internet)
    @MainActor
    func syncFromCloud(eventId: String) async throws {
        // TODO: Fase 3 — implementasi API call ke https://api.haispace.id/events/{eventId}/config
        HaispaceLogger.info("BoothConfig: sync from cloud — event: \(eventId)", category: "config")
    }

    /// Set event yang aktif
    @MainActor
    func setActiveEvent(id: String, name: String, date: Date, venue: String) {
        activeEventId = id
        activeEventName = name
        activeEventDate = date
        activeEventVenue = venue
        HaispaceLogger.info("Active event set: \(name) @ \(venue)", category: "config")
    }

    /// Tandai frame sebagai sudah di-download
    @MainActor
    func markFrameDownloaded(frameId: String) {
        downloadedFrameIds.insert(frameId)
    }

    /// Reset konfigurasi (saat operator logout atau event berakhir)
    @MainActor
    func reset() {
        activeEventId = nil
        activeEventName = nil
        activeEventDate = nil
        activeEventVenue = nil
        activePackages = []
        availableFrames = []
        downloadedFrameIds = []
    }
}

// MARK: - BoothMode

/// Mode operasi booth — menentukan berapa iPad yang digunakan
enum BoothMode: String, Codable {
    case standard   // Mode A: 1 iPhone + 1 iPad (paling umum)
    case dual       // Mode B: 1 iPhone + 2 iPad (Shooting + Selection terpisah)
    case headless   // Mode C: Hanya iPhone (tanpa iPad display, untuk event internal)

    var displayName: String {
        switch self {
        case .standard: return "Standard (1 iPad)"
        case .dual: return "Dual Station (2 iPad)"
        case .headless: return "Headless (iPhone only)"
        }
    }
}
