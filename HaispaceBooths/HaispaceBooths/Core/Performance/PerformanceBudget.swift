// PerformanceBudget.swift
// HaispaceBooths — Core/Performance
//
// Performance budget constants & monitoring untuk kiosk premium.
//
// TARGET (sesuai rekomendasi reviewer):
//   Launch          < 2.0 detik
//   Screen Transition < 0.4 detik (400ms)
//   Camera Ready    < 1.0 detik
//   Preview         < 16.67ms per frame (60fps, no frame drop)
//   Memory Stable   < 200MB RSS setelah 100 sesi
//
// PENGGUNAAN:
//   // Measure launch time
//   let token = PerformanceMonitor.shared.begin(.appLaunch)
//   // ... app setup ...
//   PerformanceMonitor.shared.end(token)
//
//   // Measure screen transition
//   withPerformanceMeasured(.screenTransition) {
//       // transition code
//   }
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar 5: Performance

import Foundation
import QuartzCore // Untuk CACurrentMediaTime (lebih akurat dari Date())

// MARK: - PerformanceBudget (Constants)

public enum PerformanceBudget {
    /// App launch ke layar pertama yang interaktif (detik)
    public static let appLaunch: TimeInterval = 2.0

    /// Transisi antar screen (detik)
    public static let screenTransition: TimeInterval = 0.4

    /// Kamera siap setelah AVCaptureSession.startRunning() (detik)
    public static let cameraReady: TimeInterval = 1.0

    /// Target render frame time untuk 60fps (detik)
    public static let frameRender: TimeInterval = 1.0 / 60.0 // ~16.67ms

    /// Maximum memory footprint (bytes) — 200MB
    public static let memoryLimit: UInt64 = 200 * 1024 * 1024

    /// Nama metric yang dipakai di AnalyticsEngine
    public enum MetricName: String, Sendable {
        case appLaunch          = "app_launch"
        case screenTransition   = "screen_transition"
        case cameraReady        = "camera_ready"
        case frameRender        = "frame_render"
        case memoryFootprint    = "memory_footprint"
    }
}

// MARK: - MeasurementToken

public struct MeasurementToken: Sendable {
    let metricName: PerformanceBudget.MetricName
    let startTime: Double   // CACurrentMediaTime()

    fileprivate init(metric: PerformanceBudget.MetricName) {
        self.metricName = metric
        self.startTime = CACurrentMediaTime()
    }
}

// MARK: - PerformanceViolation

public struct PerformanceViolation: Sendable {
    public let metric: PerformanceBudget.MetricName
    public let actualMs: Double
    public let budgetMs: Double
    public let recordedAt: Date

    public var overageMs: Double { actualMs - budgetMs }
    public var overagePercent: Double { (overageMs / budgetMs) * 100 }

    public var formattedActual: String { String(format: "%.0fms", actualMs) }
    public var formattedBudget: String { String(format: "%.0fms", budgetMs) }
    public var severity: Severity {
        if overagePercent < 25 { return .minor }
        if overagePercent < 100 { return .moderate }
        return .critical
    }

    public enum Severity: String, Sendable {
        case minor = "Minor"
        case moderate = "Moderate"
        case critical = "Critical"

        public var color: String {
            switch self {
            case .minor: return "yellow"
            case .moderate: return "orange"
            case .critical: return "red"
            }
        }
    }
}

// MARK: - PerformanceMonitor

@MainActor
public final class PerformanceMonitor: ObservableObject {

    public static let shared = PerformanceMonitor()

    // MARK: - State

    @Published public private(set) var violations: [PerformanceViolation] = []
    @Published public private(set) var recentMetrics: [String: Double] = [:] // metric → latest ms

    // Callback ke AnalyticsEngine (injected)
    public var analyticsEngine: (any AnalyticsEngineProtocol)?

    private init() {}

    // MARK: - Public API

    /// Mulai mengukur sebuah metric
    public func begin(_ metric: PerformanceBudget.MetricName) -> MeasurementToken {
        return MeasurementToken(metric: metric)
    }

    /// Akhiri pengukuran dan cek terhadap budget
    @discardableResult
    public func end(_ token: MeasurementToken) -> Double {
        let elapsed = CACurrentMediaTime() - token.startTime
        let elapsedMs = elapsed * 1000

        let budgetSeconds = budget(for: token.metricName)
        let budgetMs = budgetSeconds * 1000

        // Update latest metric
        recentMetrics[token.metricName.rawValue] = elapsedMs

        // Cek budget
        if elapsed > budgetSeconds {
            let violation = PerformanceViolation(
                metric: token.metricName,
                actualMs: elapsedMs,
                budgetMs: budgetMs,
                recordedAt: Date()
            )
            violations.append(violation)

            // Trim ke 50 violations terbaru
            if violations.count > 50 {
                violations.removeFirst()
            }

            // Log ke analytics
            Task {
                await analyticsEngine?.track(
                    .performanceViolation,
                    sessionId: nil,
                    properties: [
                        AnalyticsProp.metricName: AnyCodable(token.metricName.rawValue),
                        AnalyticsProp.actualMs: AnyCodable(elapsedMs),
                        AnalyticsProp.budgetMs: AnyCodable(budgetMs)
                    ]
                )
            }
        }

        return elapsedMs
    }

    /// Measure sebuah synchronous block
    @discardableResult
    public func measure<T>(_ metric: PerformanceBudget.MetricName, block: () throws -> T) rethrows -> T {
        let token = begin(metric)
        let result = try block()
        end(token)
        return result
    }

    /// Measure sebuah async block
    @discardableResult
    public func measureAsync<T>(_ metric: PerformanceBudget.MetricName, block: () async throws -> T) async rethrows -> T {
        let token = begin(metric)
        let result = try await block()
        end(token)
        return result
    }

    /// Cek memory footprint sekarang
    public func checkMemoryFootprint() {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }
        let usedBytes = UInt64(taskInfo.phys_footprint)
        let usedMB = Double(usedBytes) / (1024 * 1024)
        recentMetrics[PerformanceBudget.MetricName.memoryFootprint.rawValue] = usedMB

        if usedBytes > PerformanceBudget.memoryLimit {
            let violation = PerformanceViolation(
                metric: .memoryFootprint,
                actualMs: Double(usedMB),       // MB (bukan ms, tapi reuse struct)
                budgetMs: Double(PerformanceBudget.memoryLimit) / (1024 * 1024),
                recordedAt: Date()
            )
            violations.append(violation)
        }
    }

    /// Summary untuk MissionControlView
    public var summary: PerformanceSummary {
        PerformanceSummary(
            violationCount: violations.count,
            criticalViolations: violations.filter { $0.severity == .critical }.count,
            latestLaunchMs: recentMetrics[PerformanceBudget.MetricName.appLaunch.rawValue],
            latestTransitionMs: recentMetrics[PerformanceBudget.MetricName.screenTransition.rawValue],
            latestCameraReadyMs: recentMetrics[PerformanceBudget.MetricName.cameraReady.rawValue],
            memoryMB: recentMetrics[PerformanceBudget.MetricName.memoryFootprint.rawValue]
        )
    }

    // MARK: - Private

    private func budget(for metric: PerformanceBudget.MetricName) -> TimeInterval {
        switch metric {
        case .appLaunch:        return PerformanceBudget.appLaunch
        case .screenTransition: return PerformanceBudget.screenTransition
        case .cameraReady:      return PerformanceBudget.cameraReady
        case .frameRender:      return PerformanceBudget.frameRender
        case .memoryFootprint:  return 0 // Memory uses bytes, handled separately
        }
    }
}

// MARK: - PerformanceSummary (untuk MissionControlView)

public struct PerformanceSummary: Sendable {
    public let violationCount: Int
    public let criticalViolations: Int
    public let latestLaunchMs: Double?
    public let latestTransitionMs: Double?
    public let latestCameraReadyMs: Double?
    public let memoryMB: Double?

    public var isHealthy: Bool { criticalViolations == 0 }

    public var formattedLaunch: String {
        latestLaunchMs.map { String(format: "%.0fms", $0) } ?? "—"
    }
    public var formattedTransition: String {
        latestTransitionMs.map { String(format: "%.0fms", $0) } ?? "—"
    }
    public var formattedCamera: String {
        latestCameraReadyMs.map { String(format: "%.0fms", $0) } ?? "—"
    }
    public var formattedMemory: String {
        memoryMB.map { String(format: "%.1f MB", $0) } ?? "—"
    }
}
