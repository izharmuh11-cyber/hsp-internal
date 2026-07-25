// ErrorPresenterView.swift
// HaispaceBooths — Core/Error
//
// Komponen SwiftUI untuk menampilkan error ke tamu & operator.
// Tiga varian tersedia sesuai konteks:
//
//   1. GuestErrorScreen  — Full screen, warm tone, tampil ke tamu
//   2. OperatorErrorAlert — Sheet modal, detail teknis, tampil ke operator
//   3. ErrorToast         — Non-blocking overlay kecil di pojok atas
//
// Penggunaan:
//   .guestErrorScreen(error: $guestError)
//   .operatorErrorAlert(error: $operatorError)
//   .errorToast(error: $toastError)
//
// Ref: docs/design/ADR-003_platform_reliability.md

import SwiftUI

// MARK: - 1. GuestErrorScreen (Full Screen, Warm Tone)

/// Tampil ke tamu saat terjadi error yang membutuhkan perhatian mereka.
/// Tone: Tenang, tidak menakutkan, berikan info yang relevan saja.
struct GuestErrorScreen: View {

    let error: HaispaceError
    let onRetry: (() -> Void)?
    let onCallOperator: (() -> Void)?

    @State private var pulse = false

    var body: some View {
        ZStack {
            AppTheme.Surface.background
                .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                // Icon — calm, tidak mengancam
                ZStack {
                    Circle()
                        .fill(AppTheme.Brand.gold.opacity(0.12))
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                            value: pulse
                        )

                    Image(systemName: iconName)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(AppTheme.Brand.gold)
                }
                .onAppear { pulse = true }

                // Pesan utama
                VStack(spacing: Spacing.sm) {
                    Text(error.errorDescription ?? "Terjadi kendala kecil.")
                        .font(AppFont.title)
                        .foregroundStyle(AppTheme.Brand.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel(error.errorDescription ?? "Error")

                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(AppFont.body)
                            .foregroundStyle(AppTheme.Brand.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityHint(suggestion)
                    }
                }
                .padding(.horizontal, Spacing.xl)

                Spacer()

                // Aksi
                VStack(spacing: Spacing.md) {
                    if let onRetry {
                        PrimaryButton(title: "Coba Lagi") {
                            onRetry()
                        }
                        .accessibilityIdentifier("error.retryButton")
                    }

                    if let onCallOperator {
                        Button("Panggil Operator") {
                            onCallOperator()
                        }
                        .font(AppFont.footnote)
                        .foregroundStyle(AppTheme.Brand.textMuted)
                        .accessibilityIdentifier("error.callOperatorButton")
                    }
                }
                .padding(.bottom, Spacing.section)
            }
        }
    }

    private var iconName: String {
        switch error {
        case .paymentTimeout, .qrisGenerationFailed:
            return "qrcode"
        case .printerNotFound, .printerJobFailed:
            return "printer"
        case .p2pConnectionLost, .p2pConnectionFailed, .p2pReconnectExhausted:
            return "camera.on.rectangle"
        case .networkUnavailable:
            return "wifi.slash"
        case .thermalThrottling:
            return "thermometer.medium"
        case .storageInsufficient:
            return "externaldrive"
        default:
            return "exclamationmark.circle"
        }
    }
}

// MARK: - 2. OperatorErrorAlert (Sheet, Detail Teknis)

/// Tampil ke operator di MissionControl / sheet.
/// Mengandung detail teknis via `operatorNote`.
struct OperatorErrorAlert: View {

    let error: HaispaceError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Operator Alert")
                    .font(AppFont.headline)
                    .foregroundStyle(AppTheme.Brand.textPrimary)
                Spacer()
            }

            Divider()
                .background(AppTheme.Surface.tertiary)

            // Guest message (apa yang dilihat tamu)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Pesan ke Tamu", systemImage: "person.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.Brand.textMuted)
                Text(error.errorDescription ?? "—")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.Brand.textPrimary)
            }

            // Technical note (hanya operator)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Detail Teknis", systemImage: "terminal.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.Brand.textMuted)
                Text(error.operatorNote)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(Spacing.sm)
                    .background(AppTheme.Surface.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("Saran Tindakan", systemImage: "lightbulb.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.Brand.textMuted)
                    Text(suggestion)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppTheme.Brand.textSecondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: Spacing.md) {
                if let onRetry {
                    Button("Coba Lagi") { onRetry() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .accessibilityIdentifier("operatorError.retryButton")
                }

                Button("Tutup") { onDismiss() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("operatorError.dismissButton")
            }
        }
        .padding(Spacing.lg)
        .background(AppTheme.Surface.primary)
    }
}

// MARK: - 3. ErrorToast (Non-blocking Overlay)

/// Pesan kecil di pojok atas — untuk error ringan yang tidak menghentikan flow.
struct ErrorToast: View {

    let message: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppTheme.Brand.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(Motion.button) { isVisible = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Brand.textMuted)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))

                Spacer()
            }
        }
        .animation(Motion.screen, value: isVisible)
    }
}

// MARK: - View Modifiers (Convenience API)

extension View {

    /// Tampilkan GuestErrorScreen saat ada error
    func guestErrorScreen(
        error: Binding<HaispaceError?>,
        onRetry: (() -> Void)? = nil,
        onCallOperator: (() -> Void)? = nil
    ) -> some View {
        self.fullScreenCover(item: Binding(
            get: { error.wrappedValue.map { IdentifiableError($0) } },
            set: { _ in error.wrappedValue = nil }
        )) { identifiable in
            GuestErrorScreen(
                error: identifiable.error,
                onRetry: onRetry,
                onCallOperator: onCallOperator
            )
        }
    }

    /// Tampilkan ErrorToast overlay non-blocking
    func errorToast(message: String, isVisible: Binding<Bool>) -> some View {
        self.overlay(alignment: .top) {
            ErrorToast(message: message, isVisible: isVisible)
        }
    }
}

// MARK: - IdentifiableError (Helper untuk fullScreenCover)

private struct IdentifiableError: Identifiable {
    let id = UUID()
    let error: HaispaceError

    init(_ error: HaispaceError) {
        self.error = error
    }
}
