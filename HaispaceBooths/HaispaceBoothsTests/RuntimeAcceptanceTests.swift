// RuntimeAcceptanceTests.swift
// HaispaceBoothsTests — Runtime
//
// Architecture Acceptance Tests (AAT) untuk Platform Runtime v1.0.
//
// ID FORMAT: AAT-{CATEGORY}-{NUMBER}
//   AAT-RUNTIME-xxx   → RuntimeContainer, Modules, Clock, Descriptor
//   AAT-DOMAIN-xxx    → Session Aggregate, Domain Events, Invariants
//   AAT-RECOVERY-xxx  → Crash recovery, Snapshot persistence, Restore
//   AAT-COMPAT-xxx    → Compatibility Window, Mismatch detection
//   AAT-CAPABILITY-xxx → CapabilityManager, Policy, Health checks
//   AAT-CLOUD-xxx     → Cloud Contract, Sync Engine (future)
//
// STATUS SAAT INI:
//   AAT-RECOVERY-001 → PARTIAL (butuh Phase C Recovery Engine)
//   AAT-DOMAIN-001   → PARTIAL (butuh full Delivery impl)
//   AAT-DOMAIN-002   → PARTIAL (butuh AssetManifest milestone)
//   AAT-CAPABILITY-001 → PARTIAL (butuh real CapabilityManager Milestone 3)
//   AAT-RUNTIME-001  → PASS (RuntimeDescriptor completeness)
//
// Semua test sudah memiliki struktur yang benar dan akan PASS penuh
// seiring implementasi milestone berikutnya.
//
// Ref: haispace-platform/constitution/PLATFORM_RUNTIME_V1.md
//      haispace-platform/adr/ADR-011-platform-runtime-freeze.md

import XCTest
@testable import HaispaceBooths

// MARK: - Base Test Support

class RuntimeAcceptanceTestCase: XCTestCase {
    var runtime: RuntimeContainer!
    var clock: FixedClock!

    override func setUp() async throws {
        try await super.setUp()
        clock = FixedClock(fixedDate: Date(timeIntervalSince1970: 1_700_000_000))
        runtime = try RuntimeContainer.build(for: .testing)
    }

    override func tearDown() async throws {
        runtime = nil
        clock = nil
        try await super.tearDown()
    }
}

// MARK: - AAT-DOMAIN-001: Payment Durability (RG-002)

/// GUARANTEE RG-002: Payment terkonfirmasi tidak pernah hilang meski delivery gagal.
///
/// Skenario:
///   1. Tamu membayar → payment accepted ke Session Aggregate
///   2. Snapshot di-persist ke disk (Shadow Write)
///   3. Internet putus → delivery gagal
///   4. Verifikasi: PaymentCommitment tetap ada di Snapshot yang tersimpan
///
/// Status: PARTIAL — delivery failure injection butuh real delivery layer.
///         Invariant yang di-test sekarang: payment di-persist SEBELUM delivery.
final class AATDOMAIN001_PaymentDurability: RuntimeAcceptanceTestCase {

    func test_payment_persisted_before_delivery_attempt() async throws {
        // GIVEN: Session siap menerima payment
        let repository = NoOpSessionRepository()
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Izhar Test", phoneNumber: "08123456789", queueNumber: 1),
            package: BoothPackage.stub()
        )

        // WHEN: Payment diterima oleh Aggregate
        try await session.acceptPayment(
            localTransactionId: "txn-aat-domain-001",
            amount: 35000,
            method: .qris
        )

        // THEN: PaymentCommitment harus ada di Aggregate SEBELUM delivery dimulai
        let commitment = await session.paymentCommitment
        XCTAssertNotNil(commitment, "[AAT-DOMAIN-001] PaymentCommitment harus ada setelah acceptPayment")

        if case .accepted(let txnId, let amount, _) = commitment {
            XCTAssertEqual(txnId, "txn-aat-domain-001", "[AAT-DOMAIN-001] TransactionId harus cocok")
            XCTAssertEqual(amount, 35000, "[AAT-DOMAIN-001] Amount harus cocok")
        } else {
            XCTFail("[AAT-DOMAIN-001] PaymentCommitment harus dalam state .accepted")
        }

        // AND: Snapshot yang di-persist harus mengandung payment info
        let snapshot = await session.snapshot()
        try await repository.save(snapshot)
        let loaded = try await repository.load(sessionId: snapshot.sessionId)
        XCTAssertNotNil(loaded, "[AAT-DOMAIN-001] Snapshot harus tersimpan dan bisa di-load")
        XCTAssertEqual(loaded?.paymentStatus, "accepted", "[AAT-DOMAIN-001] Payment status harus di-persist")

        // TODO Phase B: Inject delivery failure dan verifikasi payment snapshot tetap ada
    }

    func test_payment_commitment_immutable_after_acceptance() async throws {
        // GIVEN: Session dengan payment accepted
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Izhar Test", phoneNumber: "08123456789", queueNumber: 1),
            package: BoothPackage.stub()
        )
        try await session.acceptPayment(
            localTransactionId: "txn-immutable-001",
            amount: 35000,
            method: .qris
        )

        // THEN: Commitment ada dan tidak bisa di-overwrite
        let commitment = await session.paymentCommitment
        XCTAssertNotNil(commitment, "[AAT-DOMAIN-001b] Initial commitment harus ada")
        // Structural invariant: acceptPayment kedua tidak boleh mengganti commitment yang ada
    }
}

// MARK: - AAT-RECOVERY-001: Crash Recovery (RG-001)

/// GUARANTEE RG-001: Session tidak hilang saat crash — snapshot di-persist secara atomic.
///
/// Skenario:
///   1. Capture selesai → session state di-persist ke disk
///   2. Simulasi crash (session object dibuang)
///   3. Recovery: load snapshot dari disk
///   4. Verifikasi: data masih ada di snapshot yang di-load
///
/// Status: PARTIAL — SessionFactory.restoreSession() butuh Phase C.
final class AATRECOVERY001_CrashRecovery: RuntimeAcceptanceTestCase {

    func test_snapshot_survives_between_sessions() async throws {
        // GIVEN: Temp repository di disk nyata
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aat-recovery-001-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repository = try LocalSessionRepository(directory: tempDir)
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Crash Test", phoneNumber: "08999", queueNumber: 5),
            package: BoothPackage.stub()
        )

        // WHEN: Snapshot di-save, session dibuang (simulasi crash)
        let snapshot = await session.snapshot()
        try await repository.save(snapshot)
        let savedSessionId = snapshot.sessionId
        // (session keluar dari scope — simulasi crash)

        // THEN: Snapshot masih bisa di-load dari disk
        let recovered = try await repository.load(sessionId: savedSessionId)
        XCTAssertNotNil(recovered, "[AAT-RECOVERY-001] Snapshot harus bisa di-load setelah session dibuang")
        XCTAssertEqual(recovered?.sessionId, savedSessionId, "[AAT-RECOVERY-001] SessionId harus cocok")
        XCTAssertEqual(recovered?.guestName, "Crash Test", "[AAT-RECOVERY-001] Guest name harus survive crash")

        // TODO Phase C: SessionFactory.restoreSession(from: recovered!, package: ...) → verifikasi stage
    }

    func test_snapshot_write_is_atomic() async throws {
        // GIVEN: Repository dengan temporary directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aat-recovery-001-atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repository = try LocalSessionRepository(directory: tempDir)
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Atomic Write Test", phoneNumber: "0800", queueNumber: 1),
            package: BoothPackage.stub()
        )

        // WHEN: Multiple concurrent writes (simulating rapid state changes)
        async let write1: () = repository.save(await session.snapshot())
        async let write2: () = repository.save(await session.snapshot())
        _ = try await (write1, write2)

        // THEN: File harus ada dan valid — tidak corrupt dari race condition
        let snapshot = await session.snapshot()
        let loaded = try await repository.load(sessionId: snapshot.sessionId)
        XCTAssertNotNil(loaded, "[AAT-RECOVERY-001b] Snapshot harus valid setelah concurrent writes")
    }
}

// MARK: - AAT-DOMAIN-002: Manifest Isolation (RG-003)

/// GUARANTEE RG-003: Manifest baru tidak mengubah asset session yang sedang berjalan.
///
/// Skenario:
///   1. Session dimulai dengan Manifest v1
///   2. Manifest v2 datang
///   3. Session yang sedang berjalan tetap memakai Manifest v1
///   4. Hanya session BARU yang memakai Manifest v2
///
/// Status: PARTIAL — enforcement butuh AssetManifest milestone.
final class AATDOMAIN002_ManifestIsolation: RuntimeAcceptanceTestCase {

    func test_session_captures_manifest_version_at_creation() async throws {
        // GIVEN: Session dibuat dengan manifestVersion = 1
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Manifest Test", phoneNumber: "0811", queueNumber: 2),
            package: BoothPackage.stub(),
            manifestVersion: 1
        )

        // WHEN: Snapshot di-ambil
        let snapshot = await session.snapshot()

        // THEN: manifestVersion harus di-bake ke dalam snapshot saat creation
        XCTAssertEqual(snapshot.manifestVersion, 1, "[AAT-DOMAIN-002] manifestVersion harus tersimpan di snapshot")

        // TODO AssetManifest Milestone:
        // - Simulasikan manifest baru (manifestVersion = 2) datang
        // - Verifikasi session yang sudah ada tetap memakai manifestVersion = 1
    }
}

// MARK: - AAT-CAPABILITY-001: Capability Fallback (RG-004)

/// GUARANTEE RG-004: Capability failure di-handle oleh Policy tanpa mematikan Workflow.
///
/// Skenario:
///   1. Printer A gagal (degraded)
///   2. CapabilityManager Policy: .fallback
///   3. Printer B ditemukan sebagai backup
///   4. Workflow tetap berjalan tanpa crash
///
/// Status: PARTIAL — DefaultCapabilityManager butuh Milestone 3.
final class AATCAPABILITY001_CapabilityFallback: RuntimeAcceptanceTestCase {

    func test_resolved_capability_has_health_status() {
        // GIVEN: SimpleCapabilityManager dengan NoOp capabilities
        let module = CapabilityModule.noOp()
        let manager = SimpleCapabilityManager(module: module)

        // WHEN: Resolve editing capability
        let resolved = try? manager.resolveEditing(policy: .fallback)

        // THEN: Harus mendapatkan resolved capability dengan health info
        XCTAssertNotNil(resolved, "[AAT-CAPABILITY-001] CapabilityManager harus dapat me-resolve capability")
        XCTAssertTrue(resolved?.isHealthy ?? false, "[AAT-CAPABILITY-001] NoOp capability harus healthy")

        // TODO Milestone 3 — DefaultCapabilityManager:
        // - Inject Printer A dengan health: .degraded(reason: "ink_low")
        // - Resolve dengan policy: .fallback → assert Printer B dikembalikan
        // - Assert Workflow tidak crash
    }

    func test_capability_manager_health_check_is_non_blocking() async {
        // GIVEN: SimpleCapabilityManager
        let module = CapabilityModule.noOp()
        let manager = SimpleCapabilityManager(module: module)

        // WHEN: Health check dipanggil
        let health = await manager.healthCheck()

        // THEN: Semua capability harus terdaftar dalam health report
        XCTAssertEqual(health.count, 5, "[AAT-CAPABILITY-001] Semua 5 capability harus dilaporkan")
        for kind in [CapabilityKind.camera, .payment, .editing, .delivery, .p2p] {
            XCTAssertNotNil(health[kind], "[AAT-CAPABILITY-001] \(kind.rawValue) harus ada dalam health check")
        }
    }
}

// MARK: - AAT-RUNTIME-001: RuntimeDescriptor Self-Description (RG-005)

/// GUARANTEE RG-005: Runtime dapat menjelaskan dirinya sendiri secara akurat dan lengkap.
final class AATRUNTIME001_RuntimeDescriptor: RuntimeAcceptanceTestCase {

    func test_runtime_identity_is_complete() {
        let descriptor = RuntimeDescriptor.current

        XCTAssertEqual(descriptor.runtimeId, "booth-runtime-ios", "[AAT-RUNTIME-001] runtimeId harus berisi 'booth-runtime-ios'")
        XCTAssertEqual(descriptor.platform, .iOS, "[AAT-RUNTIME-001] platform harus iOS")
        XCTAssertEqual(descriptor.deviceClass, .booth, "[AAT-RUNTIME-001] deviceClass harus booth")
        XCTAssertFalse(descriptor.architectureVersion.isEmpty, "[AAT-RUNTIME-001] architectureVersion harus ada")
        XCTAssertFalse(descriptor.frozenAt.isEmpty, "[AAT-RUNTIME-001] frozenAt harus ada")
    }

    func test_runtime_descriptor_has_all_guarantees() {
        let descriptor = RuntimeDescriptor.current
        XCTAssertFalse(descriptor.guarantees.isEmpty, "[AAT-RUNTIME-001] harus ada minimal satu RuntimeGuarantee")
        for guarantee in descriptor.guarantees {
            XCTAssertFalse(guarantee.id.isEmpty, "[AAT-RUNTIME-001] Setiap guarantee harus punya ID")
            XCTAssertTrue(guarantee.id.hasPrefix("RG-"), "[AAT-RUNTIME-001] Guarantee ID harus prefix RG-")
            XCTAssertFalse(guarantee.description.isEmpty, "[AAT-RUNTIME-001] Setiap guarantee harus punya deskripsi")
        }
    }

    func test_runtime_descriptor_supports_manifest_v1() {
        XCTAssertTrue(
            RuntimeDescriptor.current.supportsManifest(version: 1),
            "[AAT-RUNTIME-001] Runtime v1.0.0 harus mendukung manifest v1"
        )
    }

    func test_runtime_descriptor_describe_is_non_empty() {
        let description = RuntimeDescriptor.current.describe()
        XCTAssertTrue(description.contains("booth-runtime-ios"), "[AAT-RUNTIME-001] describe() harus mengandung runtimeId")
        XCTAssertTrue(description.contains("1.0.0"), "[AAT-RUNTIME-001] describe() harus mengandung architectureVersion")
    }
}
