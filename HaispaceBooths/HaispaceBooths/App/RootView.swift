// RootView.swift
// HaispaceBooths — App
//
// Root routing view — menentukan layar apa yang ditampilkan berdasarkan app state.
// Tidak ada business logic di sini — hanya routing berdasarkan state.
//
// Flow:
//   [License Invalid] → LicenseActivationView
//   [Not Logged In]   → LoginView
//   [Logged In, Not Configured] → BoothSetupView
//   [Ready]           → KioskRouterView (layar utama tamu)
//
// Ref: docs/design/03_user_flow.md — Alur Operator
// Ref: docs/design/21_onboarding.md

import SwiftUI

// MARK: - RootView

struct RootView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            mainContent
            operatorOverlay
            
            #if DEBUG
            if appState.isKioskModeActive || appState.isOperatorActive {
                VStack {
                    HStack {
                        Spacer()
                        LiveEventTimelineView()
                            .padding(.top, 40)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .zIndex(100) // Always visible in debug mode
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.3), value: appState.auth.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appState.isAppReady)
        .animation(.spring, value: appState.operatorState.isVerifyingPIN)
        .animation(.spring, value: appState.operatorState.isMissionControlVisible)
        .fullScreenCover(isPresented: Bindable(appState.operatorState).isPairingSetupVisible) {
            PairingSetupView()
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if !appState.isAppReady {
            // App masih loading (setup belum selesai)
            SplashView()

        } else if appState.license.status == .suspended || appState.license.status == .invalid(reason: .checksumMismatch) {
            // Jailbreak terdeteksi atau lisensi dicabut (fatal)
            FatalErrorPlaceholderView()

        } else if case .invalid = appState.license.status {
            // Lisensi tidak valid — perlu aktivasi
            LicensePlaceholderView()

        } else if !appState.auth.isLoggedIn {
            // Operator belum login → Layar Login (User: 123, Pass: 123)
            OperatorLoginView()

        } else if !appState.isKioskModeActive {
            // Operator sudah login → Full Page Bento Dashboard (Pilih Event & Pairing)
            OperatorDashboardView()

        } else {
            // Kiosk aktif — tampilkan layar tamu
            KioskRouterView()
        }
    }
    
    @ViewBuilder
    private var operatorOverlay: some View {
        if appState.operatorState.isVerifyingPIN {
            PINEntryView()
                .zIndex(100) // Paling atas
        } else if appState.operatorState.isMissionControlVisible {
            MissionControlView()
                .environment(MissionControlViewModel(
                    healthAggregator: HealthAggregator(
                        camera: appState.orchestrator.camera,
                        editing: appState.orchestrator.editing,
                        payment: appState.orchestrator.payment,
                        delivery: appState.orchestrator.delivery,
                        p2p: appState.orchestrator.p2p
                    ),
                    appState: appState
                ))
                .zIndex(99)
        }
    }
}

// MARK: - Placeholder Views

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)
                Text("HaiBooth")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Mempersiapkan sistem...")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct LicensePlaceholderView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "key.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                Text("Lisensi Tidak Valid")
                    .font(.title.bold())
                Text("Masukkan Activation Key untuk menggunakan HaiBooth")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
    }
}

private struct FatalErrorPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                Text("Perangkat Tidak Kompatibel")
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            .padding(40)
        }
    }
}

private struct LoginPlaceholderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("Login Operator")
                    .font(.largeTitle.bold())
            }
            .padding(40)
        }
    }
}

private struct BoothSetupPlaceholderView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("Setup Booth")
                    .font(.largeTitle.bold())
            }
            .padding(40)
        }
    }
}

private struct KioskRouterView: View {
    @Environment(AppState.self) private var appState

    @ViewBuilder
    private var routedView: some View {
        switch appState.currentRoute {
        case .landing:
            LandingView()
        case .guestRegistration:
            RegistrationView()
        case .packageSelection:
            PackageSelectionView()
        case .activeSession:
            ActiveSessionView()
        case .photoSelection:
            PhotoSelectionView()
        case .frameSelection:
            FrameSelectionView()
        case .payment:
            PaymentView()
        case .processing:
            FilterSelectionView()
        case .delivery:
            DeliveryView()
        }
    }

    var body: some View {
        routedView
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.03)),
                removal: .opacity.combined(with: .scale(scale: 0.97))
            ))
            .animation(.spring(response: 0.52, dampingFraction: 0.82), value: appState.currentRoute)
        // Gesture untuk membuka Mission Control (3 finger tap di pojok kanan atas)
        .overlay(alignment: .topTrailing) {
            Color.clear
                .frame(width: 80, height: 80)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    appState.operatorState.requestMissionControl()
                }
        }
    }
}

// MARK: - Preview

#Preview("Root — Loaded & Ready") {
    RootView()
        .environment(AppState.previewWithActiveSession)
}

#Preview("Root — App Loading") {
    RootView()
        .environment({
            let state = AppState()
            state.isAppReady = false
            return state
        }())
}
