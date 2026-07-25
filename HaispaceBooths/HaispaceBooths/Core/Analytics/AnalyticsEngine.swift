// AnalyticsEngine.swift
// HaispaceBooths — Core/Analytics
//
// Local-first analytics engine untuk kiosk.
//
// STRATEGI: Local-first + Batch Upload
//   1. Setiap event LANGSUNG disimpan ke file JSONL lokal (crash-safe)
//   2. Saat koneksi tersedia, file di-upload secara batch ke server
//   3. Setelah upload berhasil, file lama diarsipkan (bukan dihapus)
//
// FORMAT FILE:
//   analytics/2025-07-25.jsonl   → events hari ini
//   analytics/2025-07-24.jsonl   → events kemarin (pending upload atau sudah)
//
// PENGGUNAAN di WorkflowOrchestrator:
//   await analytics.track(.sessionStarted, sessionId: id, properties: [...])
//
// Ref: docs/design/ADR-003_platform_reliability.md

import Foundation
import Network

// MARK: - AnalyticsEngineProtocol

public protocol AnalyticsEngineProtocol: Sendable {
    func track(
        _ event: AnalyticsEventName,
        sessionId: String?,
        properties: [String: AnyCodable]
    ) async
}

// MARK: - AnalyticsEngine

public actor AnalyticsEngine: AnalyticsEngineProtocol {

    // MARK: - Properties

    private let boothId: String
    private let analyticsDir: URL
    private let encoder: JSONEncoder

    // Batch upload — max 50 events atau flush setiap 5 menit
    private var pendingBatch: [AnalyticsEvent] = []
    private static let batchSizeLimit = 50
    private static let flushIntervalSeconds: TimeInterval = 300

    private var isOnline: Bool = false
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "hsp.analytics.monitor")

    // MARK: - Init

    public init(boothId: String) {
        self.boothId = boothId

        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.analyticsDir = baseDir.appendingPathComponent("analytics", isDirectory: true)

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = .withoutEscapingSlashes
    }

    // MARK: - Lifecycle

    public func start() {
        // Buat direktori jika belum ada
        try? FileManager.default.createDirectory(
            at: analyticsDir,
            withIntermediateDirectories: true
        )

        // Monitor koneksi jaringan
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handleNetworkChange(path.status == .satisfied)
            }
        }
        pathMonitor.start(queue: monitorQueue)

        // Schedule periodic flush
        schedulePeriodicFlush()
    }

    // MARK: - Track (Public API)

    public func track(
        _ name: AnalyticsEventName,
        sessionId: String? = nil,
        properties: [String: AnyCodable] = [:]
    ) async {
        let event = AnalyticsEvent(
            name: name,
            sessionId: sessionId,
            boothId: boothId,
            properties: properties
        )

        // 1. Simpan ke file JSONL lokal (append, crash-safe)
        appendToFile(event)

        // 2. Tambah ke batch untuk upload
        pendingBatch.append(event)

        // 3. Flush jika batch sudah penuh
        if pendingBatch.count >= Self.batchSizeLimit && isOnline {
            await flushBatch()
        }
    }

    // MARK: - Convenience Track Methods

    /// Track session dimulai
    public func trackSessionStarted(sessionId: String) async {
        await track(.sessionStarted, sessionId: sessionId)
    }

    /// Track paket dipilih
    public func trackPackageSelected(sessionId: String, packageId: String, packageName: String, price: Double) async {
        await track(.packageSelected, sessionId: sessionId, properties: [
            AnalyticsProp.packageId: AnyCodable(packageId),
            AnalyticsProp.packageName: AnyCodable(packageName),
            AnalyticsProp.packagePrice: AnyCodable(price)
        ])
    }

    /// Track pembayaran selesai
    public func trackPaymentCompleted(sessionId: String, method: String, durationMs: Int) async {
        await track(.paymentCompleted, sessionId: sessionId, properties: [
            AnalyticsProp.paymentMethod: AnyCodable(method),
            AnalyticsProp.paymentDurationMs: AnyCodable(durationMs)
        ])
    }

    /// Track foto diambil
    public func trackPhotoTaken(sessionId: String, photoCount: Int, attempts: Int) async {
        await track(.photoTaken, sessionId: sessionId, properties: [
            AnalyticsProp.photoCount: AnyCodable(photoCount),
            AnalyticsProp.captureAttempts: AnyCodable(attempts)
        ])
    }

    /// Track sesi selesai penuh
    public func trackSessionCompleted(sessionId: String, totalMs: Int) async {
        await track(.sessionCompleted, sessionId: sessionId, properties: [
            AnalyticsProp.totalDurationMs: AnyCodable(totalMs)
        ])
    }

    /// Track sesi ditinggal
    public func trackSessionAbandoned(sessionId: String, atStage: String) async {
        await track(.sessionAbandoned, sessionId: sessionId, properties: [
            AnalyticsProp.abandonedAtStage: AnyCodable(atStage)
        ])
    }

    /// Track error terjadi
    public func trackError(_ error: HaispaceError, sessionId: String? = nil) async {
        await track(.errorOccurred, sessionId: sessionId, properties: [
            AnalyticsProp.errorType: AnyCodable(String(describing: error)),
            AnalyticsProp.errorCode: AnyCodable(error.operatorNote)
        ])
    }

    /// Track pelanggaran performance budget
    public func trackPerformanceViolation(metric: String, actualMs: Double, budgetMs: Double) async {
        await track(.performanceViolation, properties: [
            AnalyticsProp.metricName: AnyCodable(metric),
            AnalyticsProp.actualMs: AnyCodable(actualMs),
            AnalyticsProp.budgetMs: AnyCodable(budgetMs)
        ])
    }

    // MARK: - Daily KPI Aggregation (Read Path)

    /// Hitung KPI untuk hari ini dari file lokal
    public func dailyKPIs(for date: Date = Date()) -> DailyKPIs {
        let events = readEventsFromFile(for: date)
        return DailyKPIs(from: events)
    }

    // MARK: - Private: File I/O

    private func appendToFile(_ event: AnalyticsEvent) {
        guard let data = try? encoder.encode(event),
              let line = String(data: data, encoding: .utf8) else { return }

        let fileURL = dailyFileURL(for: event.timestamp)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }

    private func readEventsFromFile(for date: Date) -> [AnalyticsEvent] {
        let fileURL = dailyFileURL(for: date)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? decoder.decode(AnalyticsEvent.self, from: Data(line.utf8))
            }
    }

    private func dailyFileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: date)).jsonl"
        return analyticsDir.appendingPathComponent(filename)
    }

    // MARK: - Private: Network & Batch Upload

    private func handleNetworkChange(_ online: Bool) {
        self.isOnline = online
        if online && !pendingBatch.isEmpty {
            Task { await flushBatch() }
        }
    }

    private func flushBatch() async {
        guard isOnline, !pendingBatch.isEmpty else { return }
        // TODO: Implementasi upload ke endpoint analytics server
        // Untuk sekarang: clear batch (data sudah aman di file lokal)
        // await uploadToServer(pendingBatch)
        pendingBatch.removeAll()
    }

    private func schedulePeriodicFlush() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(Self.flushIntervalSeconds * 1_000_000_000))
                if isOnline { await flushBatch() }
            }
        }
    }
}

// MARK: - DailyKPIs (Agregat Harian)

public struct DailyKPIs: Sendable {
    public let totalSessions: Int
    public let completedSessions: Int
    public let abandonedSessions: Int
    public let paymentSuccessRate: Double    // 0.0 – 1.0
    public let averageSessionDurationMs: Double
    public let errorCount: Int
    public let printingSuccessRate: Double

    /// Conversion rate: sesi yang selesai / sesi yang dimulai
    public var conversionRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }

    public init(from events: [AnalyticsEvent]) {
        let started = events.filter { $0.name == .sessionStarted }.count
        let completed = events.filter { $0.name == .sessionCompleted }.count
        let abandoned = events.filter { $0.name == .sessionAbandoned }.count
        let paymentStarted = events.filter { $0.name == .paymentStarted }.count
        let paymentCompleted = events.filter { $0.name == .paymentCompleted }.count
        let printingStarted = events.filter { $0.name == .printingStarted }.count
        let printingCompleted = events.filter { $0.name == .printingCompleted }.count
        let errors = events.filter { $0.name == .errorOccurred }.count

        let completedDurations = events
            .filter { $0.name == .sessionCompleted }
            .compactMap { $0.properties[AnalyticsProp.totalDurationMs]?.value as? Int }

        self.totalSessions = started
        self.completedSessions = completed
        self.abandonedSessions = abandoned
        self.paymentSuccessRate = paymentStarted > 0
            ? Double(paymentCompleted) / Double(paymentStarted) : 0
        self.averageSessionDurationMs = completedDurations.isEmpty
            ? 0 : Double(completedDurations.reduce(0, +)) / Double(completedDurations.count)
        self.errorCount = errors
        self.printingSuccessRate = printingStarted > 0
            ? Double(printingCompleted) / Double(printingStarted) : 0
    }

    // Display helpers
    public var conversionRateFormatted: String {
        String(format: "%.1f%%", conversionRate * 100)
    }
    public var paymentSuccessFormatted: String {
        String(format: "%.1f%%", paymentSuccessRate * 100)
    }
    public var avgDurationFormatted: String {
        let seconds = Int(averageSessionDurationMs / 1000)
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

// MARK: - NoOp Analytics (untuk testing / preview)

public actor NoOpAnalyticsEngine: AnalyticsEngineProtocol {
    public init() {}
    public func track(_ event: AnalyticsEventName, sessionId: String?, properties: [String: AnyCodable]) async {}
}
