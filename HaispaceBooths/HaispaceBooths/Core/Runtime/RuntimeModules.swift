// RuntimeModules.swift
// HaispaceBooths — Core/Runtime
//
// Module Protocol dan implementasi untuk RuntimeContainer.
//
// PRINSIP (Ref: GPT Architecture Review):
//   RuntimeContainer tidak membuat dependency langsung.
//   RuntimeContainer hanya merakit Module.
//   Setiap Module bertanggung jawab atas domain-nya sendiri.
//
// STRUKTUR:
//   RuntimeContainer
//     ├── SessionModule       → HaispaceSession, SessionFactory, SessionRepository
//     ├── CapabilityModule    → Camera, Printer, Payment, Editing, Delivery, P2P
//     ├── InfrastructureModule → Persistence, Recovery, Compatibility, Clock
//     └── ObservabilityModule → EventPublisher, Subscribers, Analytics
//
// ANTI-PATTERN YANG DICEGAH:
//   - RuntimeContainer sebagai God Object
//   - Dependency tersebar di AppState, SwiftUI, Workflow
//
// Ref: GPT Architecture Review — RuntimeModules sebelum AppState integration

import Foundation

// MARK: - RuntimeModule Protocol

/// Kontrak dasar untuk semua Runtime Module.
/// Module bertanggung jawab membangun dan mengelola dependensinya sendiri.
public protocol RuntimeModule: Sendable {
    /// Nama module untuk logging dan diagnostics.
    var moduleId: String { get }

    /// Apakah module ini sudah siap digunakan?
    var isReady: Bool { get }
}

// MARK: - SessionModule

/// Module yang bertanggung jawab atas seluruh Session lifecycle.
///
/// Memiliki: SessionRepository, SessionFactory (contract)
/// Tidak tahu: Workflow, UI, Capabilities, Cloud
public final class SessionModule: RuntimeModule, @unchecked Sendable {
    public let moduleId = "session"
    public var isReady: Bool { true }

    public let repository: SessionRepositoryProtocol
    public let clock: RuntimeClockProtocol

    public init(
        repository: SessionRepositoryProtocol,
        clock: RuntimeClockProtocol = SystemClock()
    ) {
        self.repository = repository
        self.clock = clock
    }

    /// Shorthand factory untuk production.
    public static func production() throws -> SessionModule {
        SessionModule(
            repository: try LocalSessionRepository(),
            clock: SystemClock()
        )
    }

    /// Shorthand factory untuk testing.
    public static func testing(clock: RuntimeClockProtocol = FixedClock()) -> SessionModule {
        SessionModule(
            repository: NoOpSessionRepository(),
            clock: clock
        )
    }
}

// MARK: - CapabilityModule

/// Module yang bertanggung jawab atas seluruh device capability.
///
/// Memiliki: semua Capability instances
/// Tidak tahu: Session, Repository, UI, Sync
public final class CapabilityModule: RuntimeModule, @unchecked Sendable {
    public let moduleId = "capability"
    public var isReady: Bool { true }

    public let camera: CameraCapabilityProtocol
    public let editing: EditingCapabilityProtocol
    public let payment: PaymentCapabilityProtocol
    public let delivery: DeliveryCapabilityProtocol
    public let p2p: P2PCapabilityProtocol

    public init(
        camera: CameraCapabilityProtocol,
        editing: EditingCapabilityProtocol,
        payment: PaymentCapabilityProtocol,
        delivery: DeliveryCapabilityProtocol,
        p2p: P2PCapabilityProtocol
    ) {
        self.camera = camera
        self.editing = editing
        self.payment = payment
        self.delivery = delivery
        self.p2p = p2p
    }

    /// Semua NoOp (development/testing).
    public static func noOp() -> CapabilityModule {
        CapabilityModule(
            camera: NoOpCameraCapability(),
            editing: NoOpEditingCapability(),
            payment: NoOpPaymentCapability(),
            delivery: NoOpDeliveryCapability(),
            p2p: NoOpP2PCapability()
        )
    }
}

// MARK: - InfrastructureModule

/// Module yang bertanggung jawab atas persistence, recovery, dan compatibility.
///
/// Memiliki: RuntimeClock, CompatibilityChecker references
/// Tidak tahu: Workflow, UI, Cloud
public final class InfrastructureModule: RuntimeModule, @unchecked Sendable {
    public let moduleId = "infrastructure"
    public var isReady: Bool { true }

    public let clock: RuntimeClockProtocol
    public let sequenceCounter: EventSequenceCounter

    public init(clock: RuntimeClockProtocol = SystemClock()) {
        self.clock = clock
        self.sequenceCounter = EventSequenceCounter()
    }

    public static func production() -> InfrastructureModule {
        InfrastructureModule(clock: SystemClock())
    }

    public static func testing(clock: RuntimeClockProtocol = FixedClock()) -> InfrastructureModule {
        InfrastructureModule(clock: clock)
    }
}

// MARK: - ObservabilityModule

/// Module yang bertanggung jawab atas event publishing dan monitoring.
///
/// Memiliki: DomainEventPublisher, Subscribers (dengan priority ordering)
/// Tidak tahu: Session internals, Capabilities, Repository detail
public final class ObservabilityModule: RuntimeModule, @unchecked Sendable {
    public let moduleId = "observability"
    public var isReady: Bool { true }

    public let publisher: DomainEventPublisher

    // Subscribers tersusun berdasarkan priority (critical → normal → low)
    public let auditSubscriber: AuditSubscriber         // Critical
    public let compatibilityMonitor: CompatibilityMonitorSubscriber // Critical
    public let missionControl: MissionControlSubscriber  // Normal
    public let analytics: AnalyticsSubscriber            // Low

    public init() {
        self.publisher = DomainEventPublisher()

        self.auditSubscriber = AuditSubscriber()
        self.compatibilityMonitor = CompatibilityMonitorSubscriber()
        self.missionControl = MissionControlSubscriber()
        self.analytics = AnalyticsSubscriber()
    }

    /// Register semua built-in subscribers setelah module dibuat.
    /// Dipanggil oleh RuntimeContainer setelah semua module assembled.
    public func registerSubscribers() async {
        // Critical (harus diproses pertama)
        await publisher.subscribe(auditSubscriber, priority: .critical)
        await publisher.subscribeCompatibility(compatibilityMonitor)

        // Normal
        await publisher.subscribe(missionControl, priority: .normal)

        // Low
        await publisher.subscribe(analytics, priority: .low)

        HaispaceLogger.info(
            "ObservabilityModule: 4 subscribers registered",
            category: "runtime"
        )
    }
}
