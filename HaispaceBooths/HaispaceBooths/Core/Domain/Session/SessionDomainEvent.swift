// SessionDomainEvent.swift
// HaispaceBooths — Core/Domain/Session
//
// Domain Events yang dihasilkan oleh HaispaceSession Aggregate.
//
// PRINSIP (Ref: Platform Principles #12 — Everything is Observable):
//   Setiap keputusan penting Runtime menghasilkan Domain Event.
//   Jika sesuatu terjadi tanpa event, bagi platform kejadian itu dianggap tidak ada.
//
// CONSUMERS yang diharapkan:
//   - SessionAuditTrail (subscriber)
//   - MissionControlViewModel (subscriber)
//   - AnalyticsService (subscriber)
//   - RetentionManager (subscriber untuk SessionArchived)
//   - CloudSyncEngine (subscriber, future)
//
// Ref: haispace-platform/runtime/DOMAIN_EVENTS.md
// Ref: haispace-platform/adr/ADR-008-domain-event-publisher.md

import Foundation

// MARK: - SessionDomainEvent

/// Domain Events yang dihasilkan oleh HaispaceSession.
/// Typed, ordered, dan sesuai dengan katalog di DOMAIN_EVENTS.md.
public enum SessionDomainEvent: Sendable {

    // Session lifecycle
    case sessionCreated(sessionId: String, packageId: String, guestName: String)
    case sessionPaused(sessionId: String)
    case sessionResumed(sessionId: String)
    case sessionRecovering(sessionId: String)
    case sessionCompleted(sessionId: String, completedAt: Date)
    case sessionAborted(sessionId: String, reason: String, byOperatorId: String)
    case sessionArchived(sessionId: String)

    // Capture lifecycle
    case capturingBegan(sessionId: String)
    case capturePersisted(sessionId: String, captureId: String, sortOrder: Int)
    case captureUpgraded(sessionId: String, captureId: String)
    case photoSelectionBegan(sessionId: String, totalCaptures: Int)
    case captureSelectionChanged(sessionId: String, selectedCount: Int)
    case processingCompleted(sessionId: String, outputReference: String)

    // Payment lifecycle
    case paymentRequested(sessionId: String, method: PaymentCommitmentMethod)
    case paymentAccepted(sessionId: String, localTransactionId: String, amount: Int, method: PaymentCommitmentMethod)
    case paymentVerified(sessionId: String, serverId: String)
    case paymentFailed(sessionId: String, reason: String)

    // Delivery lifecycle
    case deliveryQueued(sessionId: String, channel: String, priority: Int)
    case deliveryCompleted(sessionId: String, itemId: String, channel: String)
    case allDeliveryCompleted(sessionId: String)
    case deliveryFailed(sessionId: String, itemId: String)

    // MARK: - Metadata

    /// Nama event sesuai konvensi DOMAIN_EVENTS.md (domain.EntityVerb)
    public var name: String {
        switch self {
        case .sessionCreated: return "Session.Created"
        case .sessionPaused: return "Session.Paused"
        case .sessionResumed: return "Session.Resumed"
        case .sessionRecovering: return "Session.Recovering"
        case .sessionCompleted: return "Session.Completed"
        case .sessionAborted: return "Session.Aborted"
        case .sessionArchived: return "Session.Archived"
        case .capturingBegan: return "Capture.Started"
        case .capturePersisted: return "Capture.Persisted"
        case .captureUpgraded: return "Capture.Upgraded"
        case .photoSelectionBegan: return "Capture.SelectionBegan"
        case .captureSelectionChanged: return "Capture.SelectionChanged"
        case .processingCompleted: return "MediaProcessing.ExportCompleted"
        case .paymentRequested: return "Payment.Pending"
        case .paymentAccepted: return "Payment.CommitmentAccepted"
        case .paymentVerified: return "Payment.CommitmentVerified"
        case .paymentFailed: return "Payment.Failed"
        case .deliveryQueued: return "Delivery.Queued"
        case .deliveryCompleted: return "Delivery.Completed"
        case .allDeliveryCompleted: return "Delivery.AllCompleted"
        case .deliveryFailed: return "Delivery.Failed"
        }
    }

    public var sessionId: String {
        switch self {
        case .sessionCreated(let id, _, _): return id
        case .sessionPaused(let id): return id
        case .sessionResumed(let id): return id
        case .sessionRecovering(let id): return id
        case .sessionCompleted(let id, _): return id
        case .sessionAborted(let id, _, _): return id
        case .sessionArchived(let id): return id
        case .capturingBegan(let id): return id
        case .capturePersisted(let id, _, _): return id
        case .captureUpgraded(let id, _): return id
        case .photoSelectionBegan(let id, _): return id
        case .captureSelectionChanged(let id, _): return id
        case .processingCompleted(let id, _): return id
        case .paymentRequested(let id, _): return id
        case .paymentAccepted(let id, _, _, _): return id
        case .paymentVerified(let id, _): return id
        case .paymentFailed(let id, _): return id
        case .deliveryQueued(let id, _, _): return id
        case .deliveryCompleted(let id, _, _): return id
        case .allDeliveryCompleted(let id): return id
        case .deliveryFailed(let id, _): return id
        }
    }
}
