// PaymentView.swift
// HaispaceBooths — App/Views/Customer/Payment
//
// Layar Pembayaran (QRIS / Instant Pay).
// Refactor: Menggunakan DesignSystem (Tokens, Components, Motion)
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

public struct PaymentView: View {

    @Environment(AppState.self) private var appState

    let amountText: String
    let isPaymentConfirmed: Bool

    public init(amountText: String = "Rp 50.000", isPaymentConfirmed: Bool = false) {
        self.amountText = amountText
        self.isPaymentConfirmed = isPaymentConfirmed
    }

    public var body: some View {
        ZStack {
            AppTheme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (DesignSystem ScreenHeader)
                ScreenHeader(title: "Pembayaran")
                    .padding(.top, Spacing.section)

                Spacer()

                if isPaymentConfirmed {
                    paymentSuccessView
                } else {
                    qrPaymentStateView
                }

                Spacer()
            }
        }
    }

    private var qrPaymentStateView: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.xs) {
                Text("Total Pembayaran")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.Brand.textSecondary)

                Text(amountText)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Brand.gold)
                    .accessibilityIdentifier("payment.amountLabel")
                    .accessibilityLabel("Total pembayaran \(amountText)")
            }

            VStack(spacing: Spacing.lg) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .overlay(
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 160))
                                .foregroundStyle(AppTheme.Brand.textDark)

                            Text("SCAN QRIS")
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.Brand.textDark.opacity(0.6))
                                .tracking(2)
                        }
                    )
                    .frame(width: 240, height: 240)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    .accessibilityIdentifier("payment.qrisContainer")
                    .accessibilityLabel("Kode QR pembayaran")

                Text("Gunakan GoPay, OVO, DANA, ShopeePay, atau Mobile Banking")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppTheme.Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            HStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(AppTheme.Brand.gold)

                Text("Menunggu pembayaran...")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.Brand.textPrimary)
            }
            .padding(.top, Spacing.md)
        }
    }

    private var paymentSuccessView: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.green)
                .symbolEffect(.pulse) // .bounce with nonRepeating is iOS 18+ only in Swift 6
                .accessibilityIdentifier("payment.successIcon")

            Text("Pembayaran Berhasil")
                .font(AppFont.largeTitle)
                .foregroundStyle(AppTheme.Brand.textPrimary)
                .accessibilityIdentifier("payment.successTitle")

            Text("Sedang mencetak dan menyiapkan fotomu...\nHanya butuh beberapa detik.")
                .font(AppFont.body)
                .foregroundStyle(AppTheme.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)
        }
        .transition(.scale.combined(with: .opacity))
        .animation(Motion.screen, value: isPaymentConfirmed)
    }
}

