// AppState.swift
// HaispaceBooths — Core/State
//
// Root Singleton — satu-satunya object yang di-inject ke seluruh app via .environment.
// Semua sub-stores diakses melalui AppState ini.
//
// ATURAN KRITIS:
// - Hanya ada SATU AppState di seluruh app
// - Di-inject dari HaispaceBoothsApp ke RootView via .environment(appState)
// - Sub-store tidak boleh di-inject terpisah lebih dari 2 level ke bawah
//
// Ref: docs/design/39_state_architecture.md — AppState Root Singleton

import Foundation
import Observation
import UIKit

// MARK: - AppState

@Observable
final class AppState {

    // MARK: - Sub-Stores (semua diinisialisasi di sini)
    let auth = AuthStore()
    let license = LicenseStore()
    let p2p = P2PStore()
    let boothConfig = BoothConfigStore()
    let operatorState = OperatorStore()    // `operator` adalah reserved keyword

    // MARK: - Session State
    /// Sesi foto yang sedang aktif — nil jika tidak ada sesi
    /// ATURAN: ini adalah SATU-SATUNYA sumber kebenaran sesi aktif
    var currentSession: SessionStore?
    
    /// Tamu yang sedang registrasi tapi belum memilih paket
    var pendingGuest: GuestInfo?

    // MARK: - App-Level State
    var isAppReady: Bool = false    // True setelah setup awal selesai
    var isOnline: Bool = false      // Status internet connection

    // MARK: - Computed

    /// Apakah booth siap menerima tamu?
    var isBoothReady: Bool {
        p2p.isConnected &&
        license.isValid &&
        boothConfig.isConfigured
    }

    /// Apakah operator sudah login dan aktif?
    var isOperatorActive: Bool {
        auth.isLoggedIn && operatorState.isOperatorActive
    }

    /// Apakah ada sesi yang sedang berlangsung?
    var hasActiveSession: Bool {
        currentSession != nil
    }

    // MARK: - Navigation State
    enum KioskRoute {
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
    
    /// Rute Kiosk saat ini
    var currentRoute: KioskRoute = .landing
    
    // MARK: - Session Factory

    /// Navigasi antar layar Kiosk
    @MainActor
    func navigateTo(_ route: KioskRoute) {
        currentRoute = route
    }

    /// Buat sesi baru — SATU-SATUNYA cara membuat session baru
    @MainActor
    @discardableResult
    func startNewSession(package: BoothPackage, guest: GuestInfo) -> SessionStore {
        // Finalize sesi lama jika ada
        if let existing = currentSession {
            HaispaceLogger.warning("Sesi baru dimulai sebelum sesi lama selesai — memfinalisasi sesi: \(existing.sessionId)", category: "session")
            existing.finalize()
        }

        let session = SessionStore(package: package, guest: guest)
        currentSession = session

        // Configure P2P MPC service type berdasarkan event ID
        if let eventId = boothConfig.activeEventId {
            p2p.configureMPCServiceType(eventId: eventId)
        }

        HaispaceLogger.info("Sesi baru dibuat: \(session.sessionId) — \(guest.displayName) — \(package.name)", category: "session")
        return session
    }

    /// Selesaikan dan hapus sesi aktif
    @MainActor
    func endCurrentSession() {
        guard let session = currentSession else { return }
        session.finalize()
        HaispaceLogger.info("Sesi diakhiri: \(session.sessionId)", category: "session")
        currentSession = nil
    }

    // MARK: - App Lifecycle

    /// Setup awal saat app launch — validasi license, restore session
    @MainActor
    func setup() async {
        HaispaceLogger.info("AppState setup dimulai", category: "app")

        // 1. Validasi lisensi (offline pertama, lalu online jika perlu)
        await license.validateOnLaunch()

        // 2. Restore auth session dari Keychain jika ada
        await auth.restoreSession()

        // 3. Load booth config dari lokal CoreData
        await boothConfig.loadFromLocal()

        // --- DEVELOPMENT BYPASS (Fase 2) ---
        // Karena UI License, Login, dan Booth Setup baru akan dibuat di Fase 3,
        // kita paksa (bypass) state-nya menjadi valid agar KioskRouterView bisa di-test.
        license.status = .valid
        auth.authStatus = .authenticated
        boothConfig.activeEventId = "event-test-001"
        boothConfig.activeEventName = "Test Event"
        boothConfig.activePackages = BoothPackage.mockPackages
        // -----------------------------------

        isAppReady = true
        HaispaceLogger.info("AppState setup selesai — boothReady: \(isBoothReady)", category: "app")
    }

    /// App menjadi aktif (dari background) — validasi lisensi jika diperlukan
    @MainActor
    func handleAppBecomeActive() {
        Task {
            await license.validateIfNeeded()
        }
    }
}

// MARK: - AppState Preview Mock

extension AppState {

    /// Mock AppState untuk SwiftUI Previews
    @MainActor
    static var preview: AppState {
        let state = AppState()

        // Auth
        state.auth.currentUser = .mockOperator
        state.auth.authStatus = .authenticated

        // License
        state.license.status = .valid
        state.license.expiresAt = Date().addingTimeInterval(30 * 24 * 3600)

        // P2P
        state.p2p.connectionState = .connected
        state.p2p.latencyMs = 12
        state.p2p.connectedPeerName = "iPhone 14 Haispace"
        state.p2p.connectedPeerBatteryLevel = 0.85

        // Booth Config
        state.boothConfig.activeEventId = "event-preview-001"
        state.boothConfig.activeEventName = "Wisuda BINUS 2026"
        state.boothConfig.activeEventVenue = "Jakarta Convention Center"
        state.boothConfig.activeEventDate = Date()
        state.boothConfig.activePackages = BoothPackage.mockPackages
        state.boothConfig.availableFrames = PhotoFrame.mockFrames

        // Operator
        state.operatorState.currentOperator = .mockOperator

        return state
    }

    /// Mock AppState dengan sesi aktif — untuk preview halaman dalam sesi
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
        // Pilih 3 foto pertama
        session.photos.selectedPhotoIds = Set(mockPhotos.prefix(3).map { $0.id })

        return state
    }
}


