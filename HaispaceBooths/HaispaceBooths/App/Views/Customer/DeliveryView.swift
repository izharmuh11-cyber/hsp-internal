// DeliveryView.swift
// HaispaceBooths — App/Views/Customer/Delivery
//
// Layar Pengiriman & Penutup Sesi.
// Refactor: Menggunakan DesignSystem (Tokens, Components, Motion)
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

public struct DeliveryView: View {

    @Environment(AppState.self) private var appState

    @State private var phoneNumber: String = ""
    @State private var isSent: Bool = false
    @State private var autoResetSeconds: Int = 15

    public var body: some View {
        ZStack {
            AppTheme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (DesignSystem ScreenHeader)
                ScreenHeader(title: "Terima Kasih", subtitle: "Foto cetakmu sedang dikeluarkan oleh printer")
                    .padding(.top, Spacing.section)

                Spacer()

                if isSent {
                    completedSection
                } else {
                    whatsappInputSection
                }

                Spacer()

                // Auto-reset indicator
                Text("Layar akan kembali otomatis dalam \(autoResetSeconds) detik")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppTheme.Brand.textMuted)
                    .padding(.bottom, Spacing.section)
                    .accessibilityIdentifier("delivery.autoResetCountdown")
            }
        }
        .onAppear { startAutoResetTimer() }
    }

    private var whatsappInputSection: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Kirim Softcopy ke WhatsApp")
                    .font(AppFont.headline)
                    .foregroundStyle(AppTheme.Brand.textPrimary)

                Text("Masukkan nomor WhatsApp aktif untuk menerima foto digital & GIF")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppTheme.Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Input Field
            HStack(spacing: Spacing.md) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(AppTheme.Brand.gold)

                TextField("08123456789", text: $phoneNumber)
                    .keyboardType(.numberPad)
                    .font(AppFont.headline)
                    .foregroundStyle(AppTheme.Brand.textPrimary)
                    .accessibilityIdentifier("delivery.phoneInput")
                    .accessibilityLabel("Nomor WhatsApp")
                    .accessibilityHint("Masukkan nomor WhatsApp untuk menerima softcopy")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(AppTheme.Surface.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.Brand.textPrimary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, Spacing.xxl)

            // Submit Button (DesignSystem PrimaryButton)
            PrimaryButton(
                title: "Kirim Softcopy",
                iconName: "paperplane.fill",
                isDisabled: phoneNumber.count < 9
            ) {
                withAnimation(Motion.screen) {
                    isSent = true
                }
                Task {
                    try? await appState.send(.submitDeliveryInfo(whatsapp: phoneNumber))
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .accessibilityIdentifier("delivery.submitButton")
        }
    }

    private var completedSection: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.Brand.gold)
                .symbolEffect(.bounce, options: .repeating)

            Text("Softcopy Berhasil Dikirim!")
                .font(AppFont.largeTitle)
                .foregroundStyle(AppTheme.Brand.textPrimary)

            Text("Silakan cek pesan WhatsApp kamu.\nSampai jumpa di momen seru berikutnya!")
                .font(AppFont.body)
                .foregroundStyle(AppTheme.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)
        }
        .transition(.scale.combined(with: .opacity))
        .animation(Motion.screen, value: isSent)
    }

    private func startAutoResetTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if autoResetSeconds > 1 {
                autoResetSeconds -= 1
            } else {
                timer.invalidate()
                Task {
                    try? await appState.send(.finishSession)
                }
            }
        }
    }
}

