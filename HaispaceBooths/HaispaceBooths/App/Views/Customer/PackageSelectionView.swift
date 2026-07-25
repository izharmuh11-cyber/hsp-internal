// PackageSelectionView.swift
// HaispaceBooths — App/Views/Customer/Package
//
// Layar Pemilihan Paket (Visual, Minim Teks, High Clarity).
// Refactor: Menggunakan DesignSystem (Tokens, Components, Motion)
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

public struct PackageSelectionView: View {

    @Environment(AppState.self) private var appState

    public struct PackageItem: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let printCount: String
        public let price: String
        public let isPopular: Bool
        public let features: [String]
    }

    private let packages: [PackageItem] = [
        PackageItem(
            id: "basic",
            name: "Basic",
            printCount: "2 Cetak",
            price: "Rp 20.000",
            isPopular: false,
            features: ["2 Strips Cetak", "Softcopy Digital QR"]
        ),
        PackageItem(
            id: "popular",
            name: "Popular",
            printCount: "4 Cetak",
            price: "Rp 35.000",
            isPopular: true,
            features: ["4 Strips Cetak", "Frame Exclusive", "Softcopy Digital QR", "GIF Animation"]
        )
    ]

    @State private var selectedPackageId: String = "popular"

    public var body: some View {
        ZStack {
            AppTheme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (DesignSystem ScreenHeader)
                ScreenHeader(title: "Pilih Paket Foto", subtitle: "Sesuaikan dengan kebutuhan cetakmu")
                    .padding(.top, Spacing.section)

                Spacer()

                // Package Cards
                packageCardsSection
                    .padding(.horizontal, Spacing.xl)

                Spacer()

                // Confirm Button (DesignSystem PrimaryButton)
                PrimaryButton(title: "Lanjut ke Pembayaran") {
                    Task { try? await appState.send(.selectPackage(packageId: selectedPackageId)) }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.section)
                .accessibilityIdentifier("package.confirmButton")
            }
        }
    }

    private var packageCardsSection: some View {
        HStack(spacing: Spacing.lg) {
            ForEach(packages) { pkg in
                packageCard(pkg)
            }
        }
    }

    private func packageCard(_ pkg: PackageItem) -> some View {
        let isSelected = selectedPackageId == pkg.id

        return Button {
            withAnimation(Motion.screen) {
                selectedPackageId = pkg.id
            }
        } label: {
            VStack(spacing: Spacing.lg) {
                if pkg.isPopular {
                    Text("PALING POPULER")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.Brand.textDark)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(AppTheme.Brand.gold)
                        .clipShape(Capsule())
                } else {
                    Spacer().frame(height: 22)
                }

                Text(pkg.name)
                    .font(AppFont.title)
                    .foregroundStyle(AppTheme.Brand.textPrimary)

                Text(pkg.printCount)
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.Brand.gold)

                Divider()
                    .background(AppTheme.Brand.textPrimary.opacity(0.1))

                VStack(spacing: Spacing.sm) {
                    ForEach(pkg.features, id: \.self) { feature in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(AppFont.footnote)
                                .foregroundStyle(AppTheme.Brand.gold)
                            Text(feature)
                                .font(AppFont.footnote)
                                .foregroundStyle(AppTheme.Brand.textSecondary)
                        }
                    }
                }

                Spacer()

                Text(pkg.price)
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppTheme.Brand.textPrimary)
            }
            .padding(.vertical, Spacing.xl)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .background(isSelected ? AppTheme.Surface.tertiary : AppTheme.Surface.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isSelected ? AppTheme.Brand.gold : AppTheme.Brand.textPrimary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: isSelected ? AppTheme.Brand.gold.opacity(0.2) : .black.opacity(0.3), radius: 16)
        }
        .buttonStyle(AppleScaleButtonStyle())
        .accessibilityLabel("\(pkg.name), \(pkg.printCount), harga \(pkg.price)")
        .accessibilityIdentifier("package.card.\(pkg.id)")
        .accessibilityHint(pkg.isPopular ? "Paket paling populer" : "Paket dasar")
    }
}

private struct AppleScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Motion.button, value: configuration.isPressed)
    }
}

