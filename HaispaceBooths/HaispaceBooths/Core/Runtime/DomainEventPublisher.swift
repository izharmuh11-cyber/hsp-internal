// DomainEventPublisher.swift
// HaispaceBooths — Core/Runtime
//
// Platform-level Event Bus untuk seluruh Domain Events dari Session Aggregate.
//
// PRINSIP (Ref: ADR-008, GPT Architecture Review):
//   Setiap keputusan penting Runtime menghasilkan Domain Event.
//   Siapapun yang perlu tahu, cukup menjadi Subscriber.
//   WorkflowOrchestrator tidak perlu diubah saat subscriber baru ditambahkan.
//
// SUBSCRIBER PRIORITY:
//   .critical  → Audit, Recovery, Compatibility (diproses pertama, tidak boleh gagal)
//   .normal    → Mission Control, Operator Dashboard
//   .low       → Analytics, AI Metrics, Cloud Sync
//
//   Jika subscriber Low gagal, subscriber Critical tidak terdampak.
//
// POLA SUBSCRIBER:
//   DomainEventPublisher
//     ├── [.critical] AuditSubscriber
//     ├── [.critical] CompatibilitySubscriber
//     ├── [.normal]   MissionControlSubscriber
//     ├── [.normal]   LiveTimelineSubscriber
//     └── [.low]      AnalyticsSubscriber
//
// Ref: haispace-platform/adr/ADR-008-domain-event-publisher.md

import Foundation

// MARK: - SubscriberPriority

/// Priority level untuk subscriber.
/// Subscriber dieksekusi dalam urutan priority: critical → normal → low.
/// Kegagalan subscriber low priority tidak mempengaruhi subscriber critical.
public enum SubscriberPriority: Int, Sendable, Comparable {
    case critical = 0   // Audit, Recovery, Compatibility
    case normal   = 1   // Mission Control, Operator Dashboard
    case low      = 2   // Analytics, Cloud Metrics, AI

    public static func < (lhs: SubscriberPriority, rhs: SubscriberPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DomainEventSubscriber Protocol

/// Kontrak untuk semua subscriber di DomainEventPublisher.
public protocol DomainEventSubscriber: Sendable, AnyObject {
    var subscriberId: String { get }
    func receive(_ event: SessionDomainEvent) async
}

// MARK: - CompatibilityEventSubscriber Protocol

/// Subscriber khusus untuk CompatibilityEvent (migration monitoring).
public protocol CompatibilityEventSubscriber: Sendable, AnyObject {
    var subscriberId: String { get }
    func receive(_ event: CompatibilityEvent) async
}

// MARK: - Subscriber Wrapper (internal)

private struct SubscriberEntry: @unchecked Sendable {
    let subscriber: any DomainEventSubscriber
    let priority: SubscriberPriority
}

// MARK: - DomainEventPublisher

/// Platform-level event bus dengan priority-ordered delivery.
/// Events dikirimkan ke subscribers dalam urutan: critical → normal → low.
public actor DomainEventPublisher {

    // MARK: - State

    private var sessionSubscribers: [String: SubscriberEntry] = [:]
    private var compatibilitySubscribers: [String: any CompatibilityEventSubscriber] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Subscriber Registration

    /// Subscribe dengan priority. Default: .normal.
    public func subscribe(_ subscriber: any DomainEventSubscriber, priority: SubscriberPriority = .normal) {
        sessionSubscribers[subscriber.subscriberId] = SubscriberEntry(subscriber: subscriber, priority: priority)
        HaispaceLogger.info(
            "EventPublisher: [\(priority)] \(subscriber.subscriberId) subscribed",
            category: "events"
        )
    }

    public func unsubscribe(id: String) {
        sessionSubscribers.removeValue(forKey: id)
    }

    public func subscribeCompatibility(_ subscriber: any CompatibilityEventSubscriber) {
        compatibilitySubscribers[subscriber.subscriberId] = subscriber
    }

    public func unsubscribeCompatibility(id: String) {
        compatibilitySubscribers.removeValue(forKey: id)
    }

    // MARK: - Publish (priority-ordered)

    /// Publikasikan events ke semua subscribers dalam urutan priority.
    /// Critical subscribers dieksekusi terlebih dahulu.
    public func publish(events: [SessionDomainEvent]) async {
        guard !events.isEmpty else { return }

        // Sort by priority: critical first
        let ordered = sessionSubscribers.values
            .sorted { $0.priority < $1.priority }

        for event in events {
            for entry in ordered {
                await entry.subscriber.receive(event)
            }
        }
    }

    /// Publikasikan hasil Compatibility Check.
    public func publishCompatibility(_ event: CompatibilityEvent) async {
        for subscriber in compatibilitySubscribers.values {
            await subscriber.receive(event)
        }
    }

    // MARK: - Convenience flush

    /// Ambil events dari Session dan publikasikan sekaligus.
    public func flush(from session: HaispaceSession) async {
        let events = await session.flushEvents()
        await publish(events: events)
    }

    // MARK: - Diagnostics

    public var subscriberCount: Int {
        sessionSubscribers.count
    }

    public var subscriberIds: [String] {
        sessionSubscribers.keys.map { $0 }
    }
}
