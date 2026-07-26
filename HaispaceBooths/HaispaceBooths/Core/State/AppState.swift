// AppState.swift
// HaispaceBooths — Core/State
//
// Root Observable — di-inject ke seluruh app via .environment.
//
// TANGGUNG JAWAB (tepat tiga — tidak boleh lebih):
//   1. UI Navigation  — currentRoute, KioskRoute
//   2. App Lifecycle  — setup(), handleAppBecomeActive()
//   3. Runtime Bridge — meneruskan intent ke RuntimeContainer.orchestrator
//
// YANG TIDAK BOLEH ADA DI SINI (GPT Architecture Review):
//   - Business logic (itu urusan Session Aggregate)
//   - Dependency creation (itu urusan RuntimeContainer)
//   - PaymentStore, SessionStore, DeliveryStore, PhotoStore reference
//   - Keputusan tentang "apakah payment valid" atau "berapa foto yang boleh dipilih"
//
// AppState hanya meneruskan intent dan memantulkan state.
//
// Ref: haispace-platform/constitution/PLATFORM_RUNTIME_V1.md
// Ref: haispace-platform/adr/ADR-011-platform-runtime-freeze.md

import Foundation
import Observation
import UIKit

// MARK: - AppState

@Observable
@MainActor
final class AppState {

    // MARK: - Runtime (single source of truth)

    /// RuntimeContainer adalah satu-satunya komponen yang AppState ketahui.
    /// AppState tidak pernah menyentuh dependency di dalam container secara langsung.
    let runtime: RuntimeContainer

    // MARK: - Non-Runtime Stores (belum dimigrasikan ke Runtime)
    //
    // CATATAN MIGRASI:
    //   Auth, License, P2P, BoothConfig, OperatorState bukan bagian dari Session Aggregate.
    //   Mereka adalah platform-level state yang saat ini masih di-hold oleh AppState.
    //   PR-13 (Session Root) akan menentukan apakah ini perlu masuk ke RuntimeModule baru.
    //
    let auth = AuthStore()
    let license = LicenseStore()
    let p2p = P2PStore()
    let boothConfig = BoothConfigStore()
    let operatorState = OperatorStore()

    // MARK: - Pending Guest (UI-level transient state)

    /// Tamu yang sedang registrasi tapi belum memilih paket.
    /// Ini adalah UI transient state — bukan Session state.
    var pendingGuest: GuestInfo?

    // MARK: - App-Level State

    var isAppReady: Bool = false
    var isOnline: Bool = false
    var isKioskModeActive: Bool = false

    /// Orphaned sessions yang ditemukan saat launch — ditangani oleh Recovery Engine (Phase C).
    var orphanedSessionDecisions: [OrphanedSessionDecision] = []

    // MARK: - Computed

    var isBoothReady: Bool {
        p2p.isConnected &&
        license.isValid &&
        boothConfig.isConfigured
    }

    var isOperatorActive: Bool {
        auth.isLoggedIn && operatorState.isOperatorActive
    }

    // MARK: - Navigation State (tanggung jawab 1 dari 3)

    enum KioskRoute: Hashable {
        case landing
        case guestRegistration
        case packageSelection
        case activeSession
        case photoSelection
        case frameSelection
        case payment
        case processing
        case delivery
    }

    /// Route saat ini untuk SwiftUI View — di-sync dari WorkflowOrchestrator via send().
    /// TIDAK boleh di-set langsung dari View. Gunakan send(_ intent:).
    private(set) var currentRoute: KioskRoute = .landing

    // MARK: - Initializer (tanggung jawab 2 dari 3)

    /// AppState menerima RuntimeContainer dari luar — tidak pernah membuatnya sendiri.
    /// Di-inject dari HaispaceBoothsApp setelah RuntimeContainer.build() selesai.
    init(runtime: RuntimeContainer) {
        self.runtime = runtime
    }

    // MARK: - Intent Dispatch (tanggung jawab 3 dari 3)

    /// Satu-satunya cara yang benar untuk mengubah workflow dari View.
    /// AppState meneruskan ke Runtime — tidak membuat keputusan sendiri.
    func send(_ intent: WorkflowIntent) async throws {
        try await runtime.orchestrator.handleIntent(intent)
        let newStage = await runtime.orchestrator.currentStage
        currentRoute = WorkflowRouteMapper.route(for: newStage)

        // Flush domain events ke Publisher setelah setiap intent
        await runtime.flushSessionEvents()
    }

    // MARK: - App Lifecycle (tanggung jawab 2 dari 3)

    /// Setup awal saat app launch — validasi license, restore session, launch recovery.
    func setup() async {
        HaispaceLogger.info("AppState setup dimulai", category: "app")

        // 0. Runtime launch recovery — cek apakah ada session in-progress di disk
        await runtime.performLaunchRecovery()

        // 1. Orphaned session detection (Legacy — akan digantikan Recovery Engine Phase C)
        let orphans = OrphanedSessionDetector.detect()
        if !orphans.isEmpty {
            HaispaceLogger.warning(
                "AppState: \(orphans.count) orphaned session(s) — pending Phase C Recovery Engine",
                category: "app"
            )
            orphanedSessionDecisions = orphans
        }

        // 2. Validasi lisensi
        await license.validateOnLaunch()

        // 3. Restore auth session dari Keychain
        await auth.restoreSession()

        // 4. Load booth config dari lokal
        await boothConfig.loadFromLocal()

        #if DEBUG
        HaispaceLogger.warning("⚠️ DEBUG MODE: License & config di-override dengan mock data", category: "app")
        license.status = .valid
        boothConfig.activeEventId = "event-test-001"
        boothConfig.activeEventName = "Test Event"
        boothConfig.activePackages = BoothPackage.mockPackages
        #endif

        // 5. Housekeeping
        SessionAuditTrail.purgeOldCompleted(olderThan: 30)

        isAppReady = true
        HaispaceLogger.info(
            "AppState setup selesai — boothReady: \(isBoothReady) — runtime: \(RuntimeDescriptor.current.runtimeId)",
            category: "app"
        )
    }

    /// App menjadi aktif (dari background) — validasi lisensi jika diperlukan.
    func handleAppBecomeActive() {
        Task {
            await license.validateIfNeeded()
        }
    }

    // MARK: - Legacy Bridge (COMPATIBILITY WINDOW — akan dihapus setelah migrasi selesai)
    //
    // startNewSession() masih ada untuk mendukung View yang belum dimigrasikan ke send(intent:).
    // Akan dihapus pada PR-13 (Session Root Integration).
    //
    // Runtime Adoption: AppState = 30% (orchestrator via Runtime, session via Legacy SessionStore)

    @available(*, deprecated, message: "Gunakan send(.startSession(guest:package:)) setelah PR-13. AppState tidak boleh membuat Session langsung.")
    var currentSession: SessionStore? {
        get { _legacyCurrentSession }
        set { _legacyCurrentSession = newValue }
    }

    private var _legacyCurrentSession: SessionStore?

    var hasActiveSession: Bool {
        _legacyCurrentSession != nil
    }

    @available(*, deprecated, message: "Gunakan send(.startSession) setelah PR-13.")
    @discardableResult
    func startNewSession(package: BoothPackage, guest: GuestInfo) -> SessionStore {
        if let existing = _legacyCurrentSession {
            HaispaceLogger.warning(
                "[Legacy] Sesi baru dimulai sebelum sesi lama selesai: \(existing.sessionId)",
                category: "session"
            )
            existing.finalize()
        }
        let session = SessionStore(package: package, guest: guest)
        _legacyCurrentSession = session

        if let eventId = boothConfig.activeEventId {
            p2p.configureMPCServiceType(eventId: eventId)
        }

        HaispaceLogger.info(
            "[Legacy] SessionStore dibuat: \(session.sessionId) — migrasi ke Runtime pending PR-13",
            category: "session"
        )
        return session
    }

    @available(*, deprecated, message: "Gunakan send(.endSession) setelah PR-13.")
    func endCurrentSession() {
        guard let session = _legacyCurrentSession else { return }
        session.finalize()
        _legacyCurrentSession = nil
    }

    @available(*, deprecated, message: "Gunakan send(_ intent: WorkflowIntent) sesuai ADR-001.")
    func navigateTo(_ route: KioskRoute) {
        currentRoute = route
        if route != .landing && _legacyCurrentSession == nil {
            let pkg = BoothPackage.mockStandard
            let guest = pendingGuest ?? GuestInfo(name: "Guest", instagram: nil, phoneNumber: nil, queueNumber: 1)
            startNewSession(package: pkg, guest: guest)
        }
        HaispaceLogger.warning("[DEPRECATED] navigateTo(\(route))", category: "workflow")
    }
}

// MARK: - AppState Preview Mock

extension AppState {

    @MainActor
    static var preview: AppState {
        let runtime = try! RuntimeContainer.build(for: .development)
        let state = AppState(runtime: runtime)

        #if DEBUG
        state.auth.currentUser = .mockOperator
        state.auth.authStatus = .authenticated
        state.license.status = .valid
        state.license.expiresAt = Date().addingTimeInterval(30 * 24 * 3600)
        state.p2p.connectionState = .connected
        state.p2p.latencyMs = 12
        state.p2p.connectedPeerName = "iPhone 14 Haispace"
        #endif
        state.p2p.connectedPeerBatteryLevel = 0.85
        state.boothConfig.activeEventId = "event-preview-001"
        state.boothConfig.activeEventName = "Wisuda BINUS 2026"
        state.boothConfig.activeEventVenue = "Jakarta Convention Center"
        state.boothConfig.activeEventDate = Date()
        state.boothConfig.activePackages = BoothPackage.mockPackages
        state.boothConfig.availableFrames = PhotoFrame.mockFrames
        state.boothConfig.downloadedFrameIds = Set(PhotoFrame.mockFrames.map { $0.id })
        state.operatorState.currentOperator = .mockOperator

        return state
    }

    @MainActor
    static var previewWithActiveSession: AppState {
        let state = preview
        let session = state.startNewSession(
            package: .mockStandard,
            guest: .mockSarah
        )
        session.status = .photoSelection
        let mockPhotos = CapturedPhoto.mockPhotos(count: 5)
        for photo in mockPhotos { session.photos.addPhotoForPreview(photo) }
        session.photos.selectedPhotoIds = Set(mockPhotos.prefix(3).map { $0.id })
        return state
    }
}


