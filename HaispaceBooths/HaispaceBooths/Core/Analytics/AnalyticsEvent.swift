// AnalyticsEvent.swift
// HaispaceBooths — Core/Analytics
//
// Business analytics events untuk mengukur KPI operasional kiosk.
//
// BERBEDA DARI SessionAuditTrail:
//   AuditTrail  → per-sesi, untuk crash recovery & debugging teknis
//   Analytics   → agregat cross-sesi, untuk business intelligence & KPIs
//
// Events yang dicatat:
//   session_started         → berapa sesi per hari
//   package_selected        → paket mana yang paling diminati
//   payment_started         → berapa yang sampai ke payment
//   payment_completed       → payment success rate
//   payment_abandoned       → berapa yang keluar saat bayar
//   capture_started         → berapa sesi yang capture
//   photo_taken             → berapa foto per sesi rata-rata
//   editing_completed       → berapa yang pakai editing
//   printing_started        → berapa yang cetak
//   printing_completed      → printer success rate
//   delivery_completed      → berapa yang ambil softcopy
//   session_completed       → full funnel completion rate
//   session_abandoned       → abandonment rate & stage mana yang sering ditinggal
//   error_occurred          → error rate per type
//   performance_violation   → berapa kali melebihi performance budget
//
// Ref: docs/design/ADR-003_platform_reliability.md

import Foundation

// MARK: - AnalyticsEventName

public enum AnalyticsEventName: String, Codable, Sendable {
    // Session lifecycle
    case sessionStarted         = "session_started"
    case sessionCompleted       = "session_completed"
    case sessionAbandoned       = "session_abandoned"

    // Funnel stages
    case packageSelected        = "package_selected"
    case paymentStarted         = "payment_started"
    case paymentCompleted       = "payment_completed"
    case paymentAbandoned       = "payment_abandoned"
    case captureStarted         = "capture_started"
    case photoTaken             = "photo_taken"
    case editingCompleted       = "editing_completed"
    case printingStarted        = "printing_started"
    case printingCompleted      = "printing_completed"
    case deliveryCompleted      = "delivery_completed"

    // Reliability
    case errorOccurred          = "error_occurred"
    case performanceViolation   = "performance_violation"
    case watchdogTriggered      = "watchdog_triggered"
    case crashRecovery          = "crash_recovery"
}

// MARK: - AnalyticsEvent

public struct AnalyticsEvent: Codable, Sendable {
    // Core identity
    public let eventId: String          // UUID per event
    public let sessionId: String?       // UUID sesi (nil untuk event global)
    public let name: AnalyticsEventName
    public let timestamp: Date

    // Optional properties per event
    public let properties: [String: AnyCodable]

    // Device context
    public let boothId: String
    public let appVersion: String

    public init(
        name: AnalyticsEventName,
        sessionId: String? = nil,
        boothId: String,
        properties: [String: AnyCodable] = [:]
    ) {
        self.eventId = UUID().uuidString
        self.name = name
        self.sessionId = sessionId
        self.timestamp = Date()
        self.boothId = boothId
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.properties = properties
    }
}

// MARK: - AnyCodable (lightweight, tidak perlu library)

/// Wrapper agar [String: Any] bisa di-Codable
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: some Sendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { self.value = int }
        else if let double = try? container.decode(Double.self) { self.value = double }
        else if let bool = try? container.decode(Bool.self) { self.value = bool }
        else if let string = try? container.decode(String.self) { self.value = string }
        else { self.value = "" }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let string as String: try container.encode(string)
        default: try container.encode(String(describing: value))
        }
    }
}

// MARK: - AnalyticsProperty Keys (Constants)

/// Key constants untuk properties — hindari typo
public enum AnalyticsProp {
    // Package
    public static let packageId         = "package_id"
    public static let packageName       = "package_name"
    public static let packagePrice      = "package_price"

    // Payment
    public static let paymentMethod     = "payment_method"
    public static let paymentDurationMs = "payment_duration_ms"

    // Capture
    public static let photoCount        = "photo_count"
    public static let captureAttempts   = "capture_attempts"

    // Printing
    public static let printDurationMs   = "print_duration_ms"

    // Session
    public static let totalDurationMs   = "total_duration_ms"
    public static let abandonedAtStage  = "abandoned_at_stage"
    public static let completedStages   = "completed_stages"

    // Error
    public static let errorType         = "error_type"
    public static let errorCode         = "error_code"

    // Performance
    public static let metricName        = "metric_name"
    public static let actualMs          = "actual_ms"
    public static let budgetMs          = "budget_ms"
}
