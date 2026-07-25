// AppState.swift
// HaispaceBooths — Core/State
//
// Root Singleton — satu-satunya object yang di-inject ke seluruh app via .environment.
// Semua sub-stores diakses melalui AppState ini.
//
// ATURAN KRITIS (ADR-001):
// - Hanya ada SATU AppState di seluruh app
// - Di-inject dari HaispaceBoothsApp ke RootView via .environment(appState)
// - Sub-store tidak boleh di-inject terpisah lebih dari 2 level ke bawah
// - currentRoute adalah COMPUTED dari WorkflowOrchestrator — tidak boleh di-set langsung
// - Gunakan send(_ intent:) untuk mengubah workflow, bukan navigateTo()
//
// Ref: docs/design/39_state_architecture.md — AppState Root Singleton
// Ref: docs/design/ADR-001_workflow_ownership.md — Workflow Ownership

import Foundation
import Observation
import UIKit

// MARK: - AppState

@Observable
@MainActor
final class AppState {

    // MARK: - Sub-Stores
    let auth = AuthStore()
    let license = LicenseStore()
    let p2p = P2PStore()
    let boothConfig = BoothConfigStore()
    let operatorState = OperatorStore()    // `operator` adalah reserved keyword

    // MARK: - WorkflowOrchestrator (ADR-001: Source of Truth untuk business workflow)
    //
    // Orchestrator adalah satu-satunya komponen yang boleh mengubah workflow stage.
    // Di-inject dengan NoOp capabilities sebagai safe default sebelum setup() selesai.
    let orchestrator: WorkflowOrchestrator

    // MARK: - Session State
    /// Sesi foto yang sedang aktif — nil jika tidak ada sesi
    /// ATURAN: ini adalah SATU-SATUNYA sumber kebenaran sesi aktif
    var currentSession: SessionStore?

    /// Tamu yang sedang registrasi tapi belum memilih paket
    var pendingGuest: GuestInfo?

    // MARK: - App-Level State
    var isAppReady: Bool = false
    var isOnline: Bool = false
    var isKioskModeActive: Bool = false

    /// Orphaned sessions yang ditemukan saat launch — RootView akan handle routing-nya
    /// Invariant 20: sesi dengan paymentConfirmed WAJIB di-resume
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

    var hasActiveSession: Bool {
        currentSession != nil
    }

    // MARK: - Navigation State (ADR-001)

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
    /// Ref: ADR-001 — currentRoute adalah projected state, bukan source of truth.
    private(set) var currentRoute: KioskRoute = .landing

    // MARK: - Initializer

    init() {
        // Orchestrator di-init dengan NoOp capabilities sebagai safe default.
        // Akan di-wire dengan real capabilities di masa mendatang saat platform matang.
        self.orchestrator = WorkflowOrchestrator(
            camera: NoOpCameraCapability(),
            editing: NoOpEditingCapability(),
            payment: NoOpPaymentCapability(),
            delivery: NoOpDeliveryCapability(),
            p2p: NoOpP2PCapability()
        )
    }

    // MARK: - Intent Dispatch (ADR-001)

    /// Satu-satunya cara yang benar untuk mengubah workflow dari View.
    /// View hanya memanggil ini — tidak pernah memodifikasi currentRoute langsung.
    /// Ref: ADR-001 — "View hanya mengirim intent"
    func send(_ intent: WorkflowIntent) async throws {
        try await orchestrator.handleIntent(intent)
        // Sync currentRoute dari Orchestrator setelah intent diproses
        let newStage = await orchestrator.currentStage
        currentRoute = WorkflowRouteMapper.route(for: newStage)
    }

    // MARK: - Navigation (Deprecated Bridge)
    // Dipertahankan sementara agar View lama tidak langsung break selama migrasi.
    // AKAN DIHAPUS setelah semua View dimigrasikan ke send(intent:).
    // Ref: ADR-001 — Migration Progress Tracker

    @available(*, deprecated, message: "Gunakan send(_ intent: WorkflowIntent) sesuai ADR-001. navigateTo akan dihapus setelah migrasi selesai.")
    func navigateTo(_ route: KioskRoute) {
        currentRoute = route
        HaispaceLogger.warning("[DEPRECATED] navigateTo(\(route)) — migrasi ke send(intent) sesuai ADR-001", category: "workflow")
    }

    // MARK: - Session Factory

    /// Buat sesi baru — SATU-SATUNYA cara membuat session baru
    @discardableResult
    func startNewSession(package: BoothPackage, guest: GuestInfo) -> SessionStore {
        if let existing = currentSession {
            HaispaceLogger.warning("Sesi baru dimulai sebelum sesi lama selesai — memfinalisasi sesi: \(existing.sessionId)", category: "session")
            existing.finalize()
        }

        let session = SessionStore(package: package, guest: guest)
        currentSession = session

        if let eventId = boothConfig.activeEventId {
            p2p.configureMPCServiceType(eventId: eventId)
        }

        HaispaceLogger.info("Sesi baru dibuat: \(session.sessionId) — \(guest.displayName) — \(package.name)", category: "session")
        return session
    }

    /// Selesaikan dan hapus sesi aktif
    func endCurrentSession() {
        guard let session = currentSession else { return }
        session.finalize()
        HaispaceLogger.info("Sesi diakhiri: \(session.sessionId)", category: "session")
        currentSession = nil
    }

    // MARK: - App Lifecycle

    /// Setup awal saat app launch — validasi license, restore session
    func setup() async {
        HaispaceLogger.info("AppState setup dimulai", category: "app")

        // 0. Deteksi orphaned sessions dari sesi sebelumnya (Invariant 20)
        // HARUS dijalankan sebelum isAppReady = true
        let orphans = OrphanedSessionDetector.detect()
        if !orphans.isEmpty {
            HaispaceLogger.warning("AppState: ditemukan \(orphans.count) orphaned session(s) — menunggu recovery", category: "app")
            orphanedSessionDecisions = orphans
        }

        // 1. Validasi lisensi (offline pertama, lalu online jika perlu)
        await license.validateOnLaunch()

        // 2. Restore auth session dari Keychain jika ada
        await auth.restoreSession()

        // 3. Load booth config dari lokal CoreData
        await boothConfig.loadFromLocal()

        #if DEBUG
        // ⚠️ DEBUG ONLY — bypass untuk development tanpa server
        HaispaceLogger.warning("⚠️ DEBUG MODE: License & config di-override dengan mock data", category: "app")
        license.status = .valid
        boothConfig.activeEventId = "event-test-001"
        boothConfig.activeEventName = "Test Event"
        boothConfig.activePackages = BoothPackage.mockPackages
        #endif

        // 4. Housekeeping: purge audit trails lama (>30 hari, sudah completed)
        SessionAuditTrail.purgeOldCompleted(olderThan: 30)

        isAppReady = true
        HaispaceLogger.info("AppState setup selesai — boothReady: \(isBoothReady) — orphans: \(orphanedSessionDecisions.count)", category: "app")
    }

    /// App menjadi aktif (dari background) — validasi lisensi jika diperlukan
    func handleAppBecomeActive() {
        Task {
            await license.validateIfNeeded()
        }
    }
}

#if DEBUG
// MARK: - AppState Preview Mock

extension AppState {

    @MainActor
    static var preview: AppState {
        let state = AppState()

        state.auth.currentUser = .mockOperator
        state.auth.authStatus = .authenticated
        state.license.status = .valid
        state.license.expiresAt = Date().addingTimeInterval(30 * 24 * 3600)
        state.p2p.connectionState = .connected
        state.p2p.latencyMs = 12
        state.p2p.connectedPeerName = "iPhone 14 Haispace"
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
        for photo in mockPhotos {
            session.photos.addPhotoForPreview(photo)
        }
        session.photos.selectedPhotoIds = Set(mockPhotos.prefix(3).map { $0.id })

        return state
    }
}
#endif

