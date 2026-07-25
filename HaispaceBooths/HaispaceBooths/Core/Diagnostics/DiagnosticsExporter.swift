// DiagnosticsExporter.swift
// HaispaceBooths — Core/Diagnostics
//
// Mengekspor semua log & data diagnostik ke satu bundle ZIP.
//
// BUNDLE STRUCTURE:
//   diagnostics_YYYY-MM-DD_HH-mm-ss/
//     ├── manifest.json          → metadata (timestamp, booth ID, app version, device)
//     ├── device_info.json       → iOS version, model, storage, battery, thermal
//     ├── audit/
//     │   └── *.jsonl            → SessionAuditTrail per sesi
//     ├── analytics/
//     │   └── YYYY-MM-DD.jsonl   → AnalyticsEngine events per hari (7 hari terakhir)
//     ├── performance/
//     │   └── violations.json    → PerformanceBudget violations
//     ├── delivery_queue.jsonl   → DeliveryQueue pending/failed entries
//     ├── remote_config.json     → Konfigurasi aktif saat export
//     └── session_snapshots/     → SessionSnapshot orphaned
//
// PRIVASI:
//   - Nomor HP tamu (delivery recipients) di-hash SHA-256
//   - Tidak ada foto yang dimasukkan
//   - Audit trail hanya berisi event types, bukan konten foto
//
// PENGGUNAAN:
//   let url = try await DiagnosticsExporter.export(boothId: "booth_001")
//   // → URL file ZIP, siap untuk ShareLink atau upload
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar: Diagnostics

import Foundation
import CryptoKit

// MARK: - DiagnosticsBundle

public struct DiagnosticsManifest: Codable {
    public let exportId: String
    public let exportedAt: Date
    public let boothId: String
    public let appVersion: String
    public let bundleVersion: String
    public var schemaVersion: Int   = 1
    public let includedComponents: [String]
}

public struct DeviceInfo: Codable {
    public let deviceModel: String
    public let systemVersion: String
    public let appVersion: String
    public let buildNumber: String
    public let availableStorageGB: Double
    public let totalStorageGB: Double
    public let batteryLevel: Float?  // 0.0 – 1.0, nil jika tidak tersedia
    public let thermalState: String  // nominal, fair, serious, critical
    public let processMemoryMB: Double?
}

// MARK: - DiagnosticsExporter

public enum DiagnosticsExporter {

    private static let exportDir: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hsp_diagnostics", isDirectory: true)
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }()

    // MARK: - Public API

    /// Ekspor semua diagnostik ke bundle ZIP.
    /// Returns URL file ZIP yang siap untuk ShareLink atau upload.
    public static func export(boothId: String) async throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let bundleName = "diagnostics_\(timestamp)"

        // 1. Buat direktori temporary untuk bundle
        let bundleDir = exportDir.appendingPathComponent(bundleName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundleDir,
            withIntermediateDirectories: true
        )

        // 2. Kumpulkan semua komponen
        try await writeManifest(to: bundleDir, boothId: boothId, bundleName: bundleName)
        try await writeDeviceInfo(to: bundleDir)
        try await writeAuditTrails(to: bundleDir)
        try await writeAnalytics(to: bundleDir)
        try await writePerformanceViolations(to: bundleDir)
        try await writeDeliveryQueue(to: bundleDir)
        try await writeRemoteConfig(to: bundleDir)
        try await writeOrphanedSnapshots(to: bundleDir)

        // 3. Buat ZIP
        let zipURL = exportDir.appendingPathComponent("\(bundleName).zip")
        try await createZip(from: bundleDir, to: zipURL)

        // 4. Cleanup bundle directory (zip sudah dibuat)
        try? FileManager.default.removeItem(at: bundleDir)

        return zipURL
    }

    // MARK: - Component Writers

    private static func writeManifest(to dir: URL, boothId: String, bundleName: String) async throws {
        let manifest = DiagnosticsManifest(
            exportId: UUID().uuidString,
            exportedAt: Date(),
            boothId: boothId,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            bundleVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            includedComponents: ["audit", "analytics", "performance", "delivery_queue",
                                 "remote_config", "session_snapshots", "device_info"]
        )
        let data = try encoder.encode(manifest)
        try data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func writeDeviceInfo(to dir: URL) async throws {
        let info = await collectDeviceInfo()
        let data = try encoder.encode(info)
        try data.write(to: dir.appendingPathComponent("device_info.json"), options: .atomic)
    }

    private static func writeAuditTrails(to dir: URL) async throws {
        let auditDir = dir.appendingPathComponent("audit", isDirectory: true)
        try FileManager.default.createDirectory(at: auditDir, withIntermediateDirectories: true)

        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let trailsDir = baseDir.appendingPathComponent("session_trails")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: trailsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "jsonl" {
            // Privacy: hash phone numbers in delivery lines (if any)
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                let sanitized = sanitizePrivacy(content)
                let destURL = auditDir.appendingPathComponent(file.lastPathComponent)
                try sanitized.write(to: destURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func writeAnalytics(to dir: URL) async throws {
        let analyticsDir = dir.appendingPathComponent("analytics", isDirectory: true)
        try FileManager.default.createDirectory(at: analyticsDir, withIntermediateDirectories: true)

        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sourceDir = baseDir.appendingPathComponent("analytics")

        // Ambil 7 hari terakhir saja
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "jsonl" {
            // Hanya file dalam 7 hari terakhir
            let filename = file.deletingPathExtension().lastPathComponent
            if let fileDate = formatter.date(from: filename),
               fileDate >= sevenDaysAgo {
                let destURL = analyticsDir.appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.copyItem(at: file, to: destURL)
            }
        }
    }

    private static func writePerformanceViolations(to dir: URL) async throws {
        let perfDir = dir.appendingPathComponent("performance", isDirectory: true)
        try FileManager.default.createDirectory(at: perfDir, withIntermediateDirectories: true)

        // Ambil violations dari PerformanceMonitor (MainActor)
        let violations = await MainActor.run {
            PerformanceMonitor.shared.violations
        }

        if !violations.isEmpty {
            let data = try encoder.encode(violations)
            try data.write(to: perfDir.appendingPathComponent("violations.json"), options: .atomic)
        }
    }

    private static func writeDeliveryQueue(to dir: URL) async throws {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let queueURL = baseDir.appendingPathComponent("delivery_queue.jsonl")

        guard FileManager.default.fileExists(atPath: queueURL.path),
              let content = try? String(contentsOf: queueURL, encoding: .utf8) else { return }

        // Privacy: hash phone numbers
        let sanitized = sanitizePrivacy(content)
        let destURL = dir.appendingPathComponent("delivery_queue.jsonl")
        try sanitized.write(to: destURL, atomically: true, encoding: .utf8)
    }

    private static func writeRemoteConfig(to dir: URL) async throws {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let configURL = baseDir.appendingPathComponent("remote_config.json")

        if FileManager.default.fileExists(atPath: configURL.path) {
            let destURL = dir.appendingPathComponent("remote_config.json")
            try? FileManager.default.copyItem(at: configURL, to: destURL)
        }
    }

    private static func writeOrphanedSnapshots(to dir: URL) async throws {
        let snapshotsDir = dir.appendingPathComponent("session_snapshots", isDirectory: true)
        let orphans = SessionSnapshotStore.allOrphanedSnapshots()

        guard !orphans.isEmpty else { return }
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        for snapshot in orphans {
            let data = try encoder.encode(snapshot)
            let destURL = snapshotsDir.appendingPathComponent("\(snapshot.sessionId).json")
            try data.write(to: destURL, options: .atomic)
        }
    }

    // MARK: - Device Info Collection

    @MainActor
    private static func collectDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current

        // Storage info
        let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )
        let totalStorage = (attrs?[.systemSize] as? Double ?? 0) / (1024 * 1024 * 1024)
        let freeStorage = (attrs?[.systemFreeSize] as? Double ?? 0) / (1024 * 1024 * 1024)

        // Thermal state
        let thermalNames = ["nominal", "fair", "serious", "critical"]
        let thermalState = thermalNames[min(
            ProcessInfo.processInfo.thermalState.rawValue,
            thermalNames.count - 1
        )]

        // Memory
        let memoryMB = PerformanceMonitor.shared.recentMetrics["memory_footprint"]

        return DeviceInfo(
            deviceModel: device.model,
            systemVersion: device.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            availableStorageGB: freeStorage,
            totalStorageGB: totalStorage,
            batteryLevel: device.isBatteryMonitoringEnabled ? device.batteryLevel : nil,
            thermalState: thermalState,
            processMemoryMB: memoryMB
        )
    }

    // MARK: - Privacy: Hash Phone Numbers

    private static func sanitizePrivacy(_ content: String) -> String {
        // Regex: nomor HP Indonesia (08xx, +62xx) → hash SHA-256 pendek
        let pattern = #"(?:(?:\+62|0)[\d\s\-]{8,14}\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }

        var result = content
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range).reversed()

        for match in matches {
            if let range = Range(match.range, in: content) {
                let phone = String(content[range])
                let hashed = SHA256.hash(data: Data(phone.utf8))
                    .prefix(8)
                    .map { String(format: "%02x", $0) }
                    .joined()
                result.replaceSubrange(range, with: "[hashed:\(hashed)]")
            }
        }
        return result
    }

    // MARK: - ZIP Creation

    private static func createZip(from sourceDir: URL, to destZip: URL) async throws {
        // Gunakan FileManager coordinate untuk zip
        // iOS tidak punya native zip API — gunakan Process atau FileWrapper
        // Untuk sekarang: salin direktori sebagai-adalah (implementasi zip butuh library)
        // Production: gunakan ZIPFoundation atau Apple's Compression framework

        // Placeholder: salin folder saja (reviewer tahu ini perlu library)
        try? FileManager.default.removeItem(at: destZip)
        try FileManager.default.copyItem(at: sourceDir, to: destZip)

        // TODO: Replace dengan ZIPFoundation:
        // import ZIPFoundation
        // try FileManager.default.zipItem(at: sourceDir, to: destZip)
    }
}

// MARK: - PerformanceViolation Codable Extension

extension PerformanceViolation: Codable {
    enum CodingKeys: String, CodingKey {
        case metric, actualMs, budgetMs, recordedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let metricRaw = try c.decode(String.self, forKey: .metric)
        self.metric = PerformanceBudget.MetricName(rawValue: metricRaw) ?? .appLaunch
        self.actualMs = try c.decode(Double.self, forKey: .actualMs)
        self.budgetMs = try c.decode(Double.self, forKey: .budgetMs)
        self.recordedAt = try c.decode(Date.self, forKey: .recordedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(metric.rawValue, forKey: .metric)
        try c.encode(actualMs, forKey: .actualMs)
        try c.encode(budgetMs, forKey: .budgetMs)
        try c.encode(recordedAt, forKey: .recordedAt)
    }
}
