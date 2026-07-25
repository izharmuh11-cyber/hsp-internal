// PrimaryButton.swift
// HaispaceBooths — App/DesignSystem/Components
//
// Tombol Utama Reusable bergaya Apple (Clean White, Dark Text, Press Scale & Shadow).
// Ref: Lead Apple UI/UX Review

import SwiftUI

public struct PrimaryButton: View {
    let title: String
    let iconName: String?
    let isDisabled: Bool
    let action: () -> Void

    public init(
        title: String,
        iconName: String? = "arrow.right",
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Text(title)
                    .font(AppFont.headline)

                if let iconName {
                    Image(systemName: iconName)
                        .font(AppFont.headline)
                }
            }
            .foregroundStyle(AppTheme.Brand.textDark)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background(isDisabled ? AppTheme.Brand.textPrimary.opacity(0.3) : AppTheme.Brand.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
        .disabled(isDisabled)
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Sentuh untuk melanjutkan")
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Motion.button, value: configuration.isPressed)
    }
}
