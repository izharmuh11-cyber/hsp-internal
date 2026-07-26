// Subscribers.swift
// HaispaceBooths — Core/Runtime
//
// Built-in Subscriber implementations untuk DomainEventPublisher.
//
// Setiap subscriber bertanggung jawab atas satu concern saja.
// Menambah subscriber baru tidak membutuhkan perubahan di Workflow.
//
// Ref: GPT Architecture Review — EventPublisher sebagai pusat observability

import Foundation

// MARK: - AuditSubscriber

/// Menulis setiap Domain Event ke SessionAuditTrail.
/// Menggantikan penulisan audit yang tersebar di WorkflowOrchestrator.
public final class AuditSubscriber: DomainEventSubscriber, @unchecked Sendable {
    public let subscriberId = "audit.session"

    public init() {}

    public func receive(_ event: SessionDomainEvent) async {
        // Audit domain events secara structured — tanpa logika khusus per-event
        // AuditTrail terima event.name + sessionId sebagai minimum signal
        HaispaceLogger.info(
            "[Audit] \(event.name) — sessionId: \(event.sessionId)",
            category: "audit"
        )
        // Phase C: Akan menggantikan SessionAuditTrail.append() yang tersebar di Workflow
    }
}

// MARK: - CompatibilityMonitorSubscriber

/// Mengumpulkan CompatibilityEvent untuk tracking mismatch rate.
/// Menjawab: "Berapa mismatch dalam 7 hari terakhir?"
public final class CompatibilityMonitorSubscriber: CompatibilityEventSubscriber, @unchecked Sendable {
    public let subscriberId = "compatibility.monitor"

    /// In-memory counter untuk runtime — persisted via nightly flush (future)
    private var matchCount: Int = 0
    private var mismatchCount: Int = 0
    private var unknownCount: Int = 0

    public init() {}

    public func receive(_ event: CompatibilityEvent) async {
        switch event {
        case .matched:
            matchCount += 1
        case .mismatched(let result):
            mismatchCount += 1
            HaispaceLogger.warning(
                "[CompatMonitor] Mismatch #\(mismatchCount) — sessionId: \(result.sessionId), fields: \(result.mismatchedFields.map { $0.field.rawValue })",
                category: "compatibility"
            )
        }
    }

    /// Laporan untuk Migration Dashboard.
    /// Format: (matched, mismatch, unknown, mismatchRate)
    public var report: (matched: Int, mismatch: Int, mismatchRate: Double) {
        let total = matchCount + mismatchCount
        let rate = total > 0 ? Double(mismatchCount) / Double(total) * 100 : 0
        return (matchCount, mismatchCount, rate)
    }

    public var isReadyForSwitch: Bool {
        // Siap untuk Read Switch hanya jika: ada cukup data dan rate < 0.1%
        let total = matchCount + mismatchCount
        return total >= 10 && report.mismatchRate < 0.1
    }
}

// MARK: - MissionControlSubscriber

/// Meneruskan Domain Event ke Mission Control (operator dashboard).
/// MissionControl hanya menerima event — tidak perlu polling.
public final class MissionControlSubscriber: DomainEventSubscriber, @unchecked Sendable {
    public let subscriberId = "missioncontrol"
    public var onEvent: (@Sendable (SessionDomainEvent) -> Void)?

    public init(onEvent: (@Sendable (SessionDomainEvent) -> Void)? = nil) {
        self.onEvent = onEvent
    }

    public func receive(_ event: SessionDomainEvent) async {
        onEvent?(event)
        // Phase C: Akan meng-update MissionControlViewModel via @MainActor callback
    }
}

// MARK: - AnalyticsSubscriber

/// Mengumpulkan session analytics (konversi, durasi, pilihan frame/filter).
/// Best-effort — kegagalan Analytics tidak mempengaruhi runtime.
public final class AnalyticsSubscriber: DomainEventSubscriber, @unchecked Sendable {
    public let subscriberId = "analytics"

    public init() {}

    public func receive(_ event: SessionDomainEvent) async {
        // Hanya event tertentu yang relevan untuk analytics
        switch event {
        case .sessionCompleted(let sessionId, _):
            HaispaceLogger.info("[Analytics] Session completed: \(sessionId)", category: "analytics")
        case .paymentAccepted(let sessionId, _, let amount, let method):
            HaispaceLogger.info("[Analytics] Payment accepted: \(sessionId) — \(method) Rp\(amount)", category: "analytics")
        case .captureSelectionChanged(let sessionId, let count):
            HaispaceLogger.info("[Analytics] Selection: \(sessionId) — \(count) photos", category: "analytics")
        default:
            break // Events lain diabaikan oleh analytics
        }
        // Phase E (Sync Engine): akan batch dan upload ke Cloud Analytics
    }
}
