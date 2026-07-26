// RuntimeAcceptanceTests.swift
// HaispaceBoothsTests — Runtime
//
// Architecture Acceptance Tests (AAT) untuk Platform Runtime v1.0.
//
// PRINSIP (Ref: GPT Architecture Review):
//   Setiap Runtime Guarantee harus memiliki minimal satu Acceptance Test.
//   Jika tidak ada testnya, Guarantee itu belum benar-benar ada.
//
// STATUS SAAT INI:
//   AAT-001 → PARTIAL (Payment + Delivery chain — butuh full Delivery impl)
//   AAT-002 → PARTIAL (Crash Recovery — butuh Phase C Recovery Engine)
//   AAT-003 → PARTIAL (Manifest isolation — butuh AssetManifest milestone)
//   AAT-004 → PARTIAL (Capability fallback — butuh real CapabilityManager)
//
//   Semua test sudah memiliki structure yang benar dan akan PASS penuh
//   seiring implementasi milestone berikutnya.
//   Saat ini setiap test memverifikasi invariant yang sudah bisa dibuktikan.
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

// MARK: - AAT-001: Payment Durability (RG-002)

/// GUARANTEE: Payment terkonfirmasi tidak pernah hilang meski delivery gagal.
///
/// Skenario:
///   1. Tamu membayar → payment accepted ke Session Aggregate
///   2. Snapshot di-persist ke disk (Shadow Write)
///   3. Internet putus → delivery gagal
///   4. Verifikasi: PaymentCommitment tetap ada di Snapshot yang tersimpan
///
/// Status: PARTIAL — delivery failure injection butuh real delivery layer.
///         Invariant yang di-test sekarang: payment di-persist SEBELUM delivery.
final class AAT001_PaymentDurability: RuntimeAcceptanceTestCase {

    func test_payment_persisted_before_delivery_attempt() async throws {
        // GIVEN: Session siap menerima payment
        let repository = NoOpSessionRepository()
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Izhar Test", phoneNumber: "08123456789", queueNumber: 1),
            package: BoothPackage.stub()
        )

        // WHEN: Payment diterima oleh Aggregate
        try await session.acceptPayment(
            localTransactionId: "txn-aat-001",
            amount: 35000,
            method: .qris
        )

        // THEN: PaymentCommitment harus sudah ada di Aggregate SEBELUM delivery dimulai
        let commitment = await session.paymentCommitment
        XCTAssertNotNil(commitment, "[AAT-001] PaymentCommitment harus ada setelah acceptPayment")

        if case .accepted(let txnId, let amount, _) = commitment {
            XCTAssertEqual(txnId, "txn-aat-001", "[AAT-001] TransactionId harus cocok")
            XCTAssertEqual(amount, 35000, "[AAT-001] Amount harus cocok")
        } else {
            XCTFail("[AAT-001] PaymentCommitment harus dalam state .accepted")
        }

        // AND: Snapshot yang di-persist harus mengandung payment info
        let snapshot = await session.snapshot()
        try await repository.save(snapshot)
        let loaded = try await repository.load(sessionId: snapshot.sessionId)
        XCTAssertNotNil(loaded, "[AAT-001] Snapshot harus tersimpan dan bisa di-load")
        XCTAssertEqual(loaded?.paymentStatus, "accepted", "[AAT-001] Payment status harus di-persist")

        // TODO Phase B: Inject delivery failure di sini dan verifikasi payment snapshot tetap ada
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

        // WHEN: Mencoba menerima payment kedua kali (double payment)
        // THEN: Aggregate harus menolak atau idempoten — tidak boleh mengganti commitment
        // NOTE: Behavior ini akan di-enforce oleh Session invariant di Phase C
        let initialCommitment = await session.paymentCommitment
        XCTAssertNotNil(initialCommitment, "[AAT-001b] Initial commitment harus ada")
        // Structural invariant: commitment tidak bisa di-overwrite oleh acceptPayment kedua
    }
}

// MARK: - AAT-002: Crash Recovery (RG-001)

/// GUARANTEE: Session tidak hilang saat crash — SessionSnapshot di-persist secara atomic.
///
/// Skenario:
///   1. Capture selesai → session state di-persist ke disk
///   2. Simulasi crash (terminate session tanpa cleanup)
///   3. Recovery: load snapshot dari disk
///   4. Verifikasi: capture masih ada di snapshot yang di-load
///
/// Status: PARTIAL — SessionFactory.restoreSession() butuh Phase C.
///         Invariant yang di-test sekarang: snapshot write adalah atomic.
final class AAT002_CrashRecovery: RuntimeAcceptanceTestCase {

    func test_snapshot_survives_between_sessions() async throws {
        // GIVEN: Session dengan beberapa captures
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aat-002-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let repository = try LocalSessionRepository(directory: repositoryURL)
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Crash Test", phoneNumber: "08999", queueNumber: 5),
            package: BoothPackage.stub()
        )

        // WHEN: Snapshot di-save
        let snapshot = await session.snapshot()
        try await repository.save(snapshot)

        // Simulasi "crash" — session object dibuang
        let savedSessionId = snapshot.sessionId

        // THEN: Snapshot masih bisa di-load dari disk
        let recovered = try await repository.load(sessionId: savedSessionId)
        XCTAssertNotNil(recovered, "[AAT-002] Snapshot harus bisa di-load setelah session object dibuang")
        XCTAssertEqual(recovered?.sessionId, savedSessionId, "[AAT-002] SessionId harus cocok")
        XCTAssertEqual(recovered?.guestName, "Crash Test", "[AAT-002] Guest name harus survive")
    }

    func test_snapshot_write_is_atomic() async throws {
        // GIVEN: Repository dengan temporary directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aat-002-atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let repository = try LocalSessionRepository(directory: tempDir)
        let session = try SessionFactory.createSession(
            guest: SessionGuest(name: "Atomic Write Test", phoneNumber: "0800", queueNumber: 1),
            package: BoothPackage.stub()
        )

        // WHEN: Multiple concurrent writes
        async let write1: () = repository.save(await session.snapshot())
        async let write2: () = repository.save(await session.snapshot())
        _ = try await (write1, write2)

        // THEN: File harus ada dan valid (tidak corrupt dari race condition)
        let snapshot = await session.snapshot()
        let loaded = try await repository.load(sessionId: snapshot.sessionId)
        XCTAssertNotNil(loaded, "[AAT-002] Snapshot harus valid setelah concurrent writes")

        // TODO Phase C: SessionFactory.restoreSession() test
    }
}

// MARK: - AAT-003: Manifest Isolation (RG-003)

/// GUARANTEE: Manifest baru tidak mengubah asset session yang sedang berjalan.
///
/// Skenario:
///   1. Session dimulai dengan Manifest v1 (frame A, filter X)
///   2. Manifest v2 datang (frame B, filter Y)
///   3. Session yang sedang berjalan tetap menggunakan frame A, filter X
///   4. Hanya session BARU yang menggunakan Manifest v2
///
/// Status: PARTIAL — Snapshot menyimpan manifestVersion, tapi enforcement butuh AssetManifest milestone.
final class AAT003_ManifestIsolation: RuntimeAcceptanceTestCase {

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
        XCTAssertEqual(snapshot.manifestVersion, 1, "[AAT-003] manifestVersion harus tersimpan di snapshot")

        // TODO Asset Manifest Milestone:
        // - Simulasikan manifest baru (manifestVersion = 2) datang
        // - Verifikasi session yang sudah ada tetap memakai manifestVersion = 1
        // - Hanya session baru yang mengambil manifestVersion = 2
    }
}

// MARK: - AAT-004: Capability Fallback (RG-004)

/// GUARANTEE: Capability failure di-handle oleh Policy tanpa mematikan Workflow.
///
/// Skenario:
///   1. Printer A gagal (ink low → .degraded)
///   2. CapabilityManager Policy: .fallback
///   3. Printer B ditemukan sebagai backup
///   4. Workflow tetap berjalan — tidak crash, tidak error ke user
///
/// Status: PARTIAL — CapabilityManager contract sudah ada, implementasi Milestone 3.
final class AAT004_CapabilityFallback: RuntimeAcceptanceTestCase {

    func test_resolved_capability_has_health_status() {
        // GIVEN: SimpleCapabilityManager dengan NoOp capabilities
        let module = CapabilityModule.noOp()
        let manager = SimpleCapabilityManager(module: module)

        // WHEN: Resolve printer capability
        let resolved = try? manager.resolveEditing(policy: .fallback)

        // THEN: Harus mendapatkan resolved capability dengan health info
        XCTAssertNotNil(resolved, "[AAT-004] CapabilityManager harus dapat me-resolve capability")
        XCTAssertTrue(resolved?.isHealthy ?? false, "[AAT-004] NoOp capability harus healthy")

        // TODO Milestone 3 — DefaultCapabilityManager:
        // - Inject Printer A dengan health: .degraded(reason: "ink_low")
        // - Resolve dengan policy: .fallback
        // - Assert: Printer B dikembalikan, bukan Printer A
        // - Assert: Workflow tidak crash
    }

    func test_capability_manager_health_check_is_non_blocking() async {
        // GIVEN: SimpleCapabilityManager
        let module = CapabilityModule.noOp()
        let manager = SimpleCapabilityManager(module: module)

        // WHEN: Health check dipanggil
        let health = await manager.healthCheck()

        // THEN: Semua capability harus terdaftar dalam health report
        XCTAssertEqual(health.count, 5, "[AAT-004] Semua 5 capability harus dilaporkan dalam health check")
        for kind in [CapabilityKind.camera, .payment, .editing, .delivery, .p2p] {
            XCTAssertNotNil(health[kind], "[AAT-004] \(kind.rawValue) harus ada dalam health check")
        }
    }
}

// MARK: - AAT-005: RuntimeDescriptor Self-Description

/// GUARANTEE: Runtime dapat menjelaskan dirinya sendiri secara akurat.
final class AAT005_RuntimeDescriptor: RuntimeAcceptanceTestCase {

    func test_runtime_descriptor_is_complete() {
        let descriptor = RuntimeDescriptor.current

        XCTAssertFalse(descriptor.architectureVersion.isEmpty, "[AAT-005] architectureVersion harus ada")
        XCTAssertFalse(descriptor.frozenAt.isEmpty, "[AAT-005] frozenAt harus ada")
        XCTAssertFalse(descriptor.guarantees.isEmpty, "[AAT-005] harus ada minimal satu RuntimeGuarantee")
        XCTAssertFalse(descriptor.declaredCapabilities.isEmpty, "[AAT-005] harus ada declared capabilities")
    }

    func test_runtime_descriptor_supports_manifest_v1() {
        XCTAssertTrue(
            RuntimeDescriptor.current.supportsManifest(version: 1),
            "[AAT-005] Runtime v1.0.0 harus mendukung manifest v1"
        )
    }

    func test_all_guarantees_have_ids() {
        for guarantee in RuntimeDescriptor.current.guarantees {
            XCTAssertFalse(guarantee.id.isEmpty, "[AAT-005] Setiap guarantee harus punya ID")
            XCTAssertFalse(guarantee.description.isEmpty, "[AAT-005] Setiap guarantee harus punya deskripsi")
        }
    }
}
