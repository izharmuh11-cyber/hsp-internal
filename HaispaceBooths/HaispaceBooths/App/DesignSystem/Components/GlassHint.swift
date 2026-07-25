// GlassHint.swift
// HaispaceBooths — App/DesignSystem/Components
//
// Petunjuk visual berbasis Glassmorphism (.ultraThinMaterial) gaya Apple.
// Ref: Lead Apple UI/UX Review

import SwiftUI

public struct GlassHint: View {
    let iconName: String
    let message: String

    public init(iconName: String, message: String) {
        self.iconName = iconName
        self.message = message
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: iconName)
                .font(AppFont.body)
                .foregroundStyle(AppTheme.Brand.gold)

            Text(message)
                .font(AppFont.footnote)
                .foregroundStyle(AppTheme.Brand.textPrimary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8)
        .accessibilityLabel(message)
    }
}
