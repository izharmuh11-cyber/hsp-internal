// RemoteConfigService.swift
// HaispaceBooths — Core/Config
//
// Layanan konfigurasi remote untuk mengubah behavior booth tanpa rebuild app.
//
// STRATEGI: Local-first + Optional Cloud Sync
//   1. Selalu baca dari local cache (Documents/remote_config.json) → cepat, offline-safe
//   2. Background sync dari cloud endpoint (jika tersedia)
//   3. Jika cloud sync gagal → lanjut pakai cache terakhir (tidak error)
//   4. Jika tidak ada cache → pakai DefaultConfig (bundled di app, compile-time safe)
//
// YANG BISA DIUBAH TANPA REBUILD:
//   - Harga & paket foto
//   - Idle timeout, countdown duration, auto-reset duration
//   - Frame & filter yang tersedia
//   - Promo banner & diskon
//   - Logo URL & nama booth
//   - Minimum transfer threshold
//
// PENGGUNAAN:
//   let config = RemoteConfigService.shared.current
//   let price = config.packages.first?.price ?? 20000
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar: Remote Operability

import Foundation

// MARK: - RemoteConfig (Model)

public struct RemoteConfig: Codable, Sendable {

    // MARK: - Booth Identity
    public var boothName: String
    public var boothLogoURL: String?
    public var boothLocation: String?

    // MARK: - Packages
    public var packages: [PackageConfig]

    // MARK: - Kiosk Behavior
    public var idleTimeoutSeconds: TimeInterval     // Timeout sebelum idle hint muncul
    public var attractLoopIntervalSeconds: TimeInterval  // Interval auto-slide foto
    public var countdownSeconds: Int               // Countdown sebelum capture
    public var autoResetAfterDeliverySeconds: TimeInterval  // Auto-reset setelah delivery

    // MARK: - Media Options
    public var availableFrameIds: [String]
    public var availableFilterIds: [String]
    public var defaultFrameId: String?
    public var defaultFilterId: String?

    // MARK: - Promo
    public var activeBanner: PromoBannerConfig?
    public var activeDiscount: DiscountConfig?

    // MARK: - Operational
    public var minimumStorageGB: Double            // Minimum disk space untuk operasi
    public var paperLowThreshold: Int              // Override PrinterSupervisor threshold
    public var maxDeliveryRetries: Int             // Override DeliveryQueue retry count

    // MARK: - Default Config (Bundled — compile-time safe values)
    public static let `default` = RemoteConfig(
        boothName: "Haispace Photo Booth",
        boothLogoURL: nil,
        boothLocation: nil,
        packages: [
            PackageConfig(
                id: "basic",
                name: "Basic",
                description: "Paket foto standar",
                printCount: 2,
                price: 20000,
                isPopular: false,
                features: ["2 Strips Cetak", "Softcopy Digital"]
            ),
            PackageConfig(
                id: "popular",
                name: "Popular",
                description: "Paket foto lengkap",
                printCount: 4,
                price: 35000,
                isPopular: true,
                features: ["4 Strips Cetak", "Frame Exclusive", "Softcopy Digital", "GIF Animation"]
            )
        ],
        idleTimeoutSeconds: 300,
        attractLoopIntervalSeconds: 5.5,
        countdownSeconds: 3,
        autoResetAfterDeliverySeconds: 15,
        availableFrameIds: ["frame_basic", "frame_gold", "frame_minimal"],
        availableFilterIds: ["filter_none", "filter_warm", "filter_cool", "filter_bw"],
        defaultFrameId: "frame_basic",
        defaultFilterId: "filter_none",
        activeBanner: nil,
        activeDiscount: nil,
        minimumStorageGB: 2.0,
        paperLowThreshold: 20,
        maxDeliveryRetries: 3
    )
}

// MARK: - Supporting Config Models

public struct PackageConfig: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var description: String
    public var printCount: Int
    public var price: Double
    public var isPopular: Bool
    public var features: [String]

    public var formattedPrice: String {
        "Rp \(Int(price).formatted())"
    }
}

public struct PromoBannerConfig: Codable, Sendable {
    public var title: String
    public var subtitle: String?
    public var imageURL: String?
    public var validUntil: Date?
}

public struct DiscountConfig: Codable, Sendable {
    public var code: String
    public var percentOff: Double   // 0.0 – 1.0
    public var validUntil: Date?
    public var maxUsesPerDay: Int?
}

// MARK: - RemoteConfigService

@MainActor
public final class RemoteConfigService: ObservableObject {

    public static let shared = RemoteConfigService()

    // MARK: - State

    @Published public private(set) var current: RemoteConfig = .default
    @Published public private(set) var lastSyncedAt: Date?
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var syncError: String?

    // MARK: - Config

    /// Cloud endpoint untuk sync — nil = cloud sync disabled
    public var cloudEndpoint: URL? = nil

    private static let localCacheURL: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("remote_config.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        loadFromLocalCache()
    }

    // MARK: - Lifecycle

    /// Panggil saat app launch — load cache + trigger background sync
    public func start() {
        loadFromLocalCache()
        Task { await syncFromCloud() }
    }

    // MARK: - Manual Override (Operator)

    /// Update config lokal secara manual — berguna untuk testing atau override sementara
    public func applyLocalOverride(_ config: RemoteConfig) {
        self.current = config
        saveToLocalCache(config)
    }

    /// Reset ke default bundled config
    public func resetToDefault() {
        self.current = .default
        saveToLocalCache(.default)
    }

    // MARK: - Cloud Sync

    public func syncFromCloud() async {
        guard let endpoint = cloudEndpoint else { return }
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                syncError = "Server returned non-200 response"
                isSyncing = false
                return
            }

            let newConfig = try decoder.decode(RemoteConfig.self, from: data)
            current = newConfig
            lastSyncedAt = Date()
            saveToLocalCache(newConfig)

        } catch {
            // Gagal sync → tidak error, tetap pakai cache/default
            syncError = "Sync gagal: \(error.localizedDescription). Menggunakan konfigurasi terakhir."
        }

        isSyncing = false
    }

    // MARK: - Private: Persistence

    private func loadFromLocalCache() {
        guard let data = try? Data(contentsOf: Self.localCacheURL),
              let config = try? decoder.decode(RemoteConfig.self, from: data) else {
            // Tidak ada cache → pakai default
            current = .default
            return
        }
        current = config
    }

    private func saveToLocalCache(_ config: RemoteConfig) {
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.localCacheURL, options: .atomic)
    }
}
