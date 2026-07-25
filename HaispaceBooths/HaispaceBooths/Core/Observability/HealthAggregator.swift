// HealthAggregator.swift
// HaispaceBooths — Core/Observability
//
// Mengumpulkan health snapshots — hanya mengumpulkan, tidak menganalisis.
//
// TANGGUNG JAWAB YANG DIPISAHKAN (Principal Engineer Review):
//   HealthAggregator → mengumpulkan data → PlatformHealthSnapshot
//   DiagnosisEngine  → menganalisis     → DiagnosisReport
//   IncidentEngine   → mengevaluasi     → [Incident]
//   Mission Control  → memvisualisasikan (ADR-003: tidak menghitung apapun)
//
// SUPERVISOR INTEGRATION (Operational Hardening Sprint):
//   PrinterSupervisor dan CameraSupervisor di-inject opsional.
//   Jika nil: data hardware tidak tersedia (tidak error, hanya tidak tampil).
//
// Ref: docs/design/ADR-002_operational_resilience.md — Pilar 3
// Ref: docs/design/ADR-003_mission_control_boundary.md

import Foundation

// MARK: - HealthAggregator

/// Actor yang mengumpulkan health data dari semua capability.
/// Hanya bertugas mengumpulkan — tidak menganalisis, tidak mendiagnosa.
public actor HealthAggregator {

    private let camera: CameraCapabilityProtocol
    private let editing: EditingCapabilityProtocol
    private let payment: PaymentCapabilityProtocol
    private let delivery: DeliveryCapabilityProtocol
    private let p2p: P2PCapabilityProtocol

    // Supervisor layer — opsional, inject setelah supervisor diinisialisasi
    private var printerSupervisor: PrinterSupervisor?
    private var cameraSupervisor: CameraSupervisor?

    private var activeSessionId: String?
    private var lastSnapshot: PlatformHealthSnapshot?

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

    public convenience init() {
        self.init(
            camera: NoOpCameraCapability(),
            editing: NoOpEditingCapability(),
            payment: NoOpPaymentCapability(),
            delivery: NoOpDeliveryCapability(),
            p2p: NoOpP2PCapability()
        )
    }

    // MARK: - Supervisor Injection (post-init)

    public func injectPrinterSupervisor(_ supervisor: PrinterSupervisor) {
        self.printerSupervisor = supervisor
    }

    public func injectCameraSupervisor(_ supervisor: CameraSupervisor) {
        self.cameraSupervisor = supervisor
    }

    // MARK: - Session Tracking

    public func setActiveSession(id: String?) {
        self.activeSessionId = id
    }

    // MARK: - Collection

    /// Kumpulkan semua health data dan hasilkan PlatformHealthSnapshot.
    /// Aggregator hanya mengumpulkan — DiagnosisEngine yang menganalisis.
    public func collect() async -> PlatformHealthSnapshot {
        // Kumpulkan supervisor state secara concurrent
        async let printerState = printerSupervisor?.currentState
        async let printerUptime = printerSupervisor?.uptimePercent
        async let printerLatency = printerSupervisor?.lastLatencyMs
        async let cameraState = cameraSupervisor?.currentState
        async let cameraUptime = cameraSupervisor?.uptimePercent
        async let cameraLatency = cameraSupervisor?.lastCapturLatencyMs

        let snapshot = PlatformHealthSnapshot(
            cameraHealth: await camera.healthSnapshot,
            editingHealth: editing.healthSnapshot,
            paymentHealth: payment.healthSnapshot,
            deliveryHealth: delivery.healthSnapshot,
            p2pHealth: p2p.healthSnapshot,
            activeSessionRecord: activeSessionId.flatMap {
                SessionAuditTrail.read(sessionId: $0)
            },
            orphanedSessionCount: SessionAuditTrail.findOrphanedSessions().count,
            supervisorHealth: SupervisorHealth(
                printerState: await printerState,
                printerUptimePercent: await printerUptime,
                printerLatencyMs: await printerLatency,
                cameraState: await cameraState,
                cameraUptimePercent: await cameraUptime,
                cameraLatencyMs: await cameraLatency
            )
        )

        self.lastSnapshot = snapshot

        HaispaceLogger.debug(
            "HealthAggregator.collect() — printer: \(await printerState?.rawValue ?? "n/a") camera: \(await cameraState?.rawValue ?? "n/a") orphans: \(snapshot.orphanedSessionCount)",
            category: "observability"
        )

        return snapshot
    }

    /// Snapshot terakhir yang sudah dikumpulkan (untuk caching).
    public var cachedSnapshot: PlatformHealthSnapshot? { lastSnapshot }
}
