// DomainEventEnvelope.swift
// HaispaceBooths — Core/Runtime
//
// Metadata envelope untuk seluruh Domain Event.
//
// PRINSIP (Ref: GPT Architecture Review):
//   Event payload (SessionDomainEvent) tetap bersih — hanya fakta domain.
//   Metadata teknis (routing, tracing, versioning) ditambahkan oleh Envelope.
//
// KEMAMPUAN yang dibuka oleh Envelope:
//   tracing       — correlationId + causationId untuk distributed tracing
//   replay        — sequenceNumber + timestamp untuk event replay (Recovery)
//   debugging     — runtimeVersion + manifestVersion untuk diagnosis
//   distributed   — eventId unik untuk idempotency di Cloud Sync
//
// POLA PENGGUNAAN:
//   DomainEventEnvelope.wrap(event, clock: clock, session: sessionId, ...)
//
// Ref: GPT Architecture Review — Envelope sebelum Cloud Contract

import Foundation

// MARK: - DomainEventEnvelope

/// Pembungkus metadata untuk SessionDomainEvent.
/// Dipublikasikan oleh DomainEventPublisher — bukan oleh Session Aggregate.
public struct DomainEventEnvelope: Codable, Sendable {

    // MARK: - Identity

    /// ID unik event ini (UUID). Digunakan untuk idempotency di Cloud Sync.
    public let eventId: String

    /// ID Session yang menghasilkan event ini.
    public let sessionId: String

    // MARK: - Timing

    /// Waktu event terjadi (dari RuntimeClock — bukan Date() langsung).
    public let timestamp: Date

    /// Urutan event dalam session ini — monotonically increasing.
    /// Digunakan untuk replay dan ordering saat recovery.
    public let sequenceNumber: Int

    // MARK: - Versioning

    /// Versi Runtime saat event ini diproduksi.
    /// Berguna untuk diagnosis saat ada behavior regression antar versi.
    public let runtimeVersion: String

    /// Versi Manifest Booth saat event ini diproduksi.
    public let manifestVersion: Int

    // MARK: - Distributed Tracing

    /// ID operasi top-level yang memulai chain event ini.
    /// Contoh: intentId dari WorkflowOrchestrator.handleIntent()
    public let correlationId: String?

    /// ID event yang menjadi penyebab langsung event ini.
    /// Digunakan untuk membangun causal graph.
    public let causationId: String?

    // MARK: - Payload

    /// Event domain yang sebenarnya.
    public let payload: SessionDomainEvent

    // MARK: - Factory

    public static func wrap(
        _ event: SessionDomainEvent,
        clock: RuntimeClockProtocol,
        sessionId: String,
        sequenceNumber: Int,
        runtimeVersion: String = "1.0.0",
        manifestVersion: Int = 1,
        correlationId: String? = nil,
        causationId: String? = nil
    ) -> DomainEventEnvelope {
        DomainEventEnvelope(
            eventId: UUID().uuidString,
            sessionId: sessionId,
            timestamp: clock.now,
            sequenceNumber: sequenceNumber,
            runtimeVersion: runtimeVersion,
            manifestVersion: manifestVersion,
            correlationId: correlationId,
            causationId: causationId,
            payload: event
        )
    }
}

// MARK: - EventSequenceCounter

/// Thread-safe monotonic counter untuk sequenceNumber per session.
/// Digunakan oleh DomainEventPublisher saat membungkus events.
public actor EventSequenceCounter {
    private var counter: Int = 0

    public init() {}

    public func next() -> Int {
        counter += 1
        return counter
    }

    public func reset() {
        counter = 0
    }
}
