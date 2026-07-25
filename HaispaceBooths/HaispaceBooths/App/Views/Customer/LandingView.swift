// LandingView.swift
// HaispaceBooths — App/Views/Customer/Landing
//
// Screen pertama yang dilihat customer.
// Refactor: Menggunakan DesignSystem (Tokens, Components, Unified Motion)
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

public struct LandingView: View {

    @Environment(AppState.self) private var appState

    private let samplePhotos: [String] = [
        "sample_booth_1", "sample_booth_2", "sample_booth_3"
    ]
    @State private var currentPhoto: Int = 0
    @State private var isIdle: Bool = false
    @State private var idleTimer: Timer? = nil

    public var body: some View {
        ZStack {
            AppTheme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo Header
                logoSection
                    .padding(.top, Spacing.section)

                // Photo Collage (attract loop)
                photoCollageSection
                    .padding(.top, Spacing.xxl)

                Spacer()

                // Tagline & Price
                taglineSection
                    .padding(.horizontal, Spacing.xxl)

                // CTA Button (Design System PrimaryButton)
                PrimaryButton(title: "Mulai", iconName: "arrow.right") {
                    resetIdleTimer()
                    Task { try? await appState.send(.startGuestRegistration) }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.section)
                .accessibilityIdentifier("landing.startButton")
            }

            // Subtle Idle Hint Overlay (Design System GlassHint)
            if isIdle {
                VStack {
                    Spacer()
                    GlassHint(iconName: "hand.tap.fill", message: "Sentuh layar untuk memulai")
                        .padding(.bottom, 116)
                        .accessibilityIdentifier("landing.idleHint")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Motion.screen, value: isIdle)
            }
        }
        .onAppear { startIdleTimer() }
        .onDisappear { cancelIdleTimer() }
        .onTapGesture { resetIdleTimer() }
    }

    private var logoSection: some View {
        VStack(spacing: Spacing.xs) {
            Text("HAISPACE")
                .font(AppFont.title)
                .foregroundStyle(AppTheme.Brand.textPrimary)
                .tracking(4)

            Text("PHOTO EXPERIENCE")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.Brand.gold)
                .tracking(3)
        }
    }

    private var photoCollageSection: some View {
        TabView(selection: $currentPhoto) {
            ForEach(0..<samplePhotos.count, id: \.self) { index in
                samplePhotoCard(named: samplePhotos[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 380)
        .onAppear { startAttractLoop() }
        .accessibilityIdentifier("landing.photoCarousel")
    }

    private func samplePhotoCard(named name: String) -> some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(AppTheme.Surface.primary)
            .overlay(
                VStack(spacing: Spacing.md) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.Brand.gold.opacity(0.85))
                    Text("Abadikan Senyummu")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.Brand.textSecondary)
                }
            )
            .padding(.horizontal, 44)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }

    private var taglineSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("Abadikan Momen Terbaik")
                .font(AppFont.largeTitle)
                .foregroundStyle(AppTheme.Brand.textPrimary)
                .multilineTextAlignment(.center)

            Text("Mulai dari Rp 20.000  ·  Selesai dalam 5 menit")
                .font(AppFont.body)
                .foregroundStyle(AppTheme.Brand.gold)
        }
        .padding(.bottom, Spacing.xl)
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation(Motion.screen) { isIdle = true }
        }
    }

    private func resetIdleTimer() {
        withAnimation(Motion.screen) { isIdle = false }
        cancelIdleTimer()
        startIdleTimer()
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func startAttractLoop() {
        Timer.scheduledTimer(withTimeInterval: 5.5, repeats: true) { _ in
            withAnimation(Motion.screen) {
                currentPhoto = (currentPhoto + 1) % samplePhotos.count
            }
        }
    }
}



