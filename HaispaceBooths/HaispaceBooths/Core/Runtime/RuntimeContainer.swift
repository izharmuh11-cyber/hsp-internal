// RuntimeContainer.swift
// HaispaceBooths — Core/Runtime
//
// COMPOSITION ROOT untuk seluruh Platform Runtime Haispace.
//
// PRINSIP (Ref: GPT Architecture Review):
//   RuntimeContainer adalah satu-satunya tempat dependency dirakit.
//   Tidak ada inisialisasi dependency di AppState, SwiftUI, atau Workflow.
//
//   UI hanya menerima satu instance dari RuntimeContainer.
//   UI tidak tahu cara membangunnya.
//
// TANGGUNG JAWAB:
//   - Membangun SessionRepository
//   - Membangun DomainEventPublisher + mendaftarkan semua subscriber
//   - Membangun WorkflowOrchestrator
//   - Menjaga lifecycle semua komponen runtime
//   - Menjadi satu-satunya entry point ke seluruh Platform Runtime
//
// YANG TIDAK BOLEH ADA DI SINI:
//   - SwiftUI / @Observable concern
//   - Business logic (itu urusan Session Aggregate)
//   - UI routing (itu urusan AppState/RootView)
//
// Ref: GPT Architecture Review — RuntimeContainer before PR-03 Read Switch

import Foundation

// MARK: - RuntimeContainer

/// Composition Root untuk seluruh Platform Runtime Haispace.
/// Dibuat satu kali saat aplikasi launch, diserahkan ke SwiftUI environment.
@MainActor
public final class RuntimeContainer: ObservableObject {

    // MARK: - Public Interfaces (read-only untuk UI)

    /// Workflow Orchestrator — satu-satunya cara UI memicu Workflow action.
    public let orchestrator: WorkflowOrchestrator

    /// Domain Event Publisher — UI/Admin layer bisa subscribe untuk observability.
    public let eventPublisher: DomainEventPublisher

    // MARK: - Built-in Subscribers (managed lifecycle)

    public let auditSubscriber: AuditSubscriber
    public let compatibilityMonitor: CompatibilityMonitorSubscriber
    public let missionControlSubscriber: MissionControlSubscriber
    public let analyticsSubscriber: AnalyticsSubscriber

    // MARK: - Private Infrastructure

    private let sessionRepository: SessionRepositoryProtocol

    // MARK: - Capability Registry (contract, future implementation)
    // public let capabilityRegistry: CapabilityRegistryProtocol
    // Akan diaktifkan setelah Milestone 3 — Capability Registry.

    // MARK: - Build Configurations

    public enum Environment {
        case production     // iPad runtime dengan capabilities nyata
        case development    // Mac / Simulator dengan NoOp capabilities
        case testing        // Unit test — semua NoOp
    }

    // MARK: - Factory (static entry point)

    /// Buat RuntimeContainer untuk satu lingkungan.
    /// Ini adalah satu-satunya cara yang benar untuk memulai Platform Runtime.
    public static func build(for environment: Environment = .production) throws -> RuntimeContainer {
        switch environment {
        case .production:
            return try RuntimeContainer(
                camera: NoOpCameraCapability(),      // TODO Phase 3: RealCameraCapability
                editing: NoOpEditingCapability(),
                payment: NoOpPaymentCapability(),
                delivery: NoOpDeliveryCapability(),
                p2p: NoOpP2PCapability(),
                repository: LocalSessionRepository()
            )
        case .development, .testing:
            return try RuntimeContainer(
                camera: NoOpCameraCapability(),
                editing: NoOpEditingCapability(),
                payment: NoOpPaymentCapability(),
                delivery: NoOpDeliveryCapability(),
                p2p: NoOpP2PCapability(),
                repository: NoOpSessionRepository()
            )
        }
    }

    // MARK: - Init (private — use build() factory method)

    private init(
        camera: CameraCapabilityProtocol,
        editing: EditingCapabilityProtocol,
        payment: PaymentCapabilityProtocol,
        delivery: DeliveryCapabilityProtocol,
        p2p: P2PCapabilityProtocol,
        repository: SessionRepositoryProtocol
    ) throws {
        self.sessionRepository = repository

        // 1. Build Event Publisher (no dependencies)
        let publisher = DomainEventPublisher()
        self.eventPublisher = publisher

        // 2. Build Built-in Subscribers
        let audit = AuditSubscriber()
        let compatibility = CompatibilityMonitorSubscriber()
        let missionControl = MissionControlSubscriber()
        let analytics = AnalyticsSubscriber()
        self.auditSubscriber = audit
        self.compatibilityMonitor = compatibility
        self.missionControlSubscriber = missionControl
        self.analyticsSubscriber = analytics

        // 3. Build WorkflowOrchestrator dengan semua dependencies lengkap
        self.orchestrator = WorkflowOrchestrator(
            camera: camera,
            editing: editing,
            payment: payment,
            delivery: delivery,
            p2p: p2p,
            sessionRepository: repository
        )

        // 4. Register subscribers ke Publisher (async setup — will complete shortly)
        Task { @MainActor in
            await publisher.subscribe(audit)
            await publisher.subscribe(missionControl)
            await publisher.subscribe(analytics)
            await publisher.subscribeCompatibility(compatibility)

            HaispaceLogger.info(
                "RuntimeContainer: Platform Runtime assembled — 4 subscribers registered",
                category: "runtime"
            )
        }
    }

    // MARK: - Runtime Services

    /// Recovery check saat launch — baca semua incomplete sessions dari disk.
    public func performLaunchRecovery() async {
        guard let localRepo = sessionRepository as? LocalSessionRepository else { return }
        let pending = await localRepo.fetchRequiringRecovery()
        if pending.isEmpty {
            HaispaceLogger.info("RuntimeContainer: No sessions requiring recovery.", category: "runtime")
        } else {
            HaispaceLogger.warning(
                "RuntimeContainer: \(pending.count) session(s) require recovery — pending Phase C Recovery Engine.",
                category: "runtime"
            )
            // Phase C: Akan memanggil SessionFactory.restoreSession(from: snapshot, package: ...)
            // dan mengarahkan WorkflowOrchestrator ke stage yang tepat.
        }
    }

    /// Flush pending events dari Session Aggregate saat ini ke Publisher.
    /// Dipanggil oleh WorkflowOrchestrator setelah setiap intent.
    public func flushSessionEvents() async {
        guard let session = await orchestrator.activeSession else { return }
        await eventPublisher.flush(from: session)
    }

    /// Mismatch rate saat ini untuk Payment bounded context.
    /// Digunakan oleh Migration Dashboard.
    public var paymentMismatchReport: (matched: Int, mismatch: Int, mismatchRate: Double) {
        compatibilityMonitor.report
    }

    public var isPaymentReadyForReadSwitch: Bool {
        compatibilityMonitor.isReadyForSwitch
    }
}
