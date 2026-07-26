// RuntimeContainer.swift
// HaispaceBooths — Core/Runtime
//
// COMPOSITION ROOT untuk seluruh Platform Runtime Haispace.
//
// PRINSIP (Ref: GPT Architecture Review):
//   RuntimeContainer hanya menyusun Module (RuntimeModules).
//   RuntimeContainer tidak pernah mengetahui detail implementasi dependency.
//
// TANGGUNG JAWAB:
//   - Membangun SessionModule, CapabilityModule, InfrastructureModule, ObservabilityModule
//   - Membangun WorkflowOrchestrator dari gabungan module tersebut
//   - Menjaga lifecycle semua komponen runtime
//   - Menjadi satu-satunya entry point ke seluruh Platform Runtime
//
// YANG TIDAK BOLEH ADA DI SINI:
//   - Inisialisasi dependency spesifik (itu urusan masing-masing Module)
//   - SwiftUI / @Observable concern
//   - UI routing (itu urusan AppState/RootView)
//
// Ref: GPT Architecture Review — RuntimeModules sebelum AppState integration

import Foundation

// MARK: - RuntimeContainer

/// Composition Root untuk seluruh Platform Runtime Haispace.
/// Dibuat satu kali saat aplikasi launch, diserahkan ke SwiftUI environment.
@MainActor
public final class RuntimeContainer: ObservableObject {

    // MARK: - Public Interfaces (read-only untuk UI)

    /// Workflow Orchestrator — satu-satunya cara UI memicu Workflow action.
    public let orchestrator: WorkflowOrchestrator

    // MARK: - Modules

    public let session: SessionModule
    public let capabilities: CapabilityModule
    public let infrastructure: InfrastructureModule
    public let observability: ObservabilityModule
    
    // Nanti CapabilityManager akan di-expose di sini (Milestone 3)

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
                session: try SessionModule.production(),
                capabilities: CapabilityModule.noOp(), // TODO Phase 3: Real capabilities
                infrastructure: InfrastructureModule.production(),
                observability: ObservabilityModule()
            )
        case .development, .testing:
            return try RuntimeContainer(
                session: SessionModule.testing(),
                capabilities: CapabilityModule.noOp(),
                infrastructure: InfrastructureModule.testing(),
                observability: ObservabilityModule()
            )
        }
    }

    // MARK: - Init (private — use build() factory method)

    private init(
        session: SessionModule,
        capabilities: CapabilityModule,
        infrastructure: InfrastructureModule,
        observability: ObservabilityModule
    ) throws {
        self.session = session
        self.capabilities = capabilities
        self.infrastructure = infrastructure
        self.observability = observability

        // Build WorkflowOrchestrator dengan dependencies dari modules
        // NOTE: Di Milestone 3, ini akan menggunakan CapabilityManager
        self.orchestrator = WorkflowOrchestrator(
            camera: capabilities.camera,
            editing: capabilities.editing,
            payment: capabilities.payment,
            delivery: capabilities.delivery,
            p2p: capabilities.p2p,
            sessionRepository: session.repository
        )

        // Register subscribers ke Publisher
        let obs = self.observability
        Task { @MainActor in
            await obs.registerSubscribers()
            HaispaceLogger.info(
                "RuntimeContainer: Platform Runtime assembled from 4 Modules",
                category: "runtime"
            )
        }
    }

    // MARK: - Runtime Services

    /// Recovery check saat launch — baca semua incomplete sessions dari disk.
    public func performLaunchRecovery() async {
        guard let localRepo = session.repository as? LocalSessionRepository else { return }
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
        guard let activeSession = await orchestrator.activeSession else { return }
        await observability.publisher.flush(from: activeSession)
    }

    // MARK: - Convenience Accessors for Migration Dashboard

    /// Mismatch rate saat ini untuk Payment bounded context.
    public var paymentMismatchReport: (matched: Int, mismatch: Int, mismatchRate: Double) {
        observability.compatibilityMonitor.report
    }

    public var isPaymentReadyForReadSwitch: Bool {
        observability.compatibilityMonitor.isReadyForSwitch
    }
}
