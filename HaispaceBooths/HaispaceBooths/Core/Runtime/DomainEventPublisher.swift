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
// POLA SUBSCRIBER:
//   DomainEventPublisher
//     ├── AuditSubscriber       (SessionAuditTrail)
//     ├── CompatibilitySubscriber (Compatibility Window tracking)
//     ├── MissionControlSubscriber (operator dashboard)
//     ├── AnalyticsSubscriber   (heatmap, conversion)
//     ├── LiveTimelineSubscriber (real-time session view)
//     └── CloudSyncSubscriber   (future — Sync Engine trigger)
//
// AI Assistant, Printer Monitor, atau capability baru cukup menambah subscriber.
// Tidak perlu mengubah Workflow.
//
// Ref: haispace-platform/adr/ADR-008-domain-event-publisher.md

import Foundation

// MARK: - DomainEventSubscriber Protocol

/// Kontrak untuk semua subscriber di DomainEventPublisher.
/// Implementasikan protokol ini untuk menerima event dari Session Aggregate.
public protocol DomainEventSubscriber: Sendable, AnyObject {
    /// Nama unik subscriber — dipakai untuk logging dan unsubscribe.
    var subscriberId: String { get }

    /// Receive domain event dari Session Aggregate.
    /// Dipanggil secara asinkron setelah Session.flushEvents().
    func receive(_ event: SessionDomainEvent) async
}

// MARK: - CompatibilityEventSubscriber Protocol

/// Subscriber khusus untuk CompatibilityEvent (migration monitoring).
public protocol CompatibilityEventSubscriber: Sendable, AnyObject {
    var subscriberId: String { get }
    func receive(_ event: CompatibilityEvent) async
}

// MARK: - DomainEventPublisher

/// Platform-level event bus.
/// Menerima events dari Session Aggregate (via flushEvents) dan
/// mendistribusikannya ke semua subscriber yang terdaftar.
///
/// Ini adalah satu-satunya titik distribusi event.
/// Publisher tidak tahu siapa subscribernya.
public actor DomainEventPublisher {

    // MARK: - State

    private var sessionSubscribers: [String: any DomainEventSubscriber] = [:]
    private var compatibilitySubscribers: [String: any CompatibilityEventSubscriber] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Subscriber Registration

    public func subscribe(_ subscriber: any DomainEventSubscriber) {
        sessionSubscribers[subscriber.subscriberId] = subscriber
        HaispaceLogger.info(
            "EventPublisher: \(subscriber.subscriberId) subscribed (total: \(sessionSubscribers.count))",
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

    // MARK: - Publish

    /// Publikasikan semua pending events dari satu Session Aggregate.
    /// Dipanggil oleh RuntimeContainer atau WorkflowOrchestrator setelah mutasi.
    public func publish(events: [SessionDomainEvent]) async {
        guard !events.isEmpty else { return }
        for event in events {
            for subscriber in sessionSubscribers.values {
                await subscriber.receive(event)
            }
        }
    }

    /// Publikasikan hasil Compatibility Check.
    /// Dipanggil oleh WorkflowOrchestrator setelah setiap compatibility check.
    public func publishCompatibility(_ event: CompatibilityEvent) async {
        for subscriber in compatibilitySubscribers.values {
            await subscriber.receive(event)
        }
    }

    // MARK: - Convenience flush

    /// Ambil events dari Session dan publikasikan sekaligus.
    /// Pattern yang dianjurkan di Unit of Work.
    public func flush(from session: HaispaceSession) async {
        let events = await session.flushEvents()
        await publish(events: events)
    }
}
