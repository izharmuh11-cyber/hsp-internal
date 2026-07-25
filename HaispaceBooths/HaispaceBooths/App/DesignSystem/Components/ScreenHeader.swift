// ScreenHeader.swift
// HaispaceBooths — App/DesignSystem/Components
//
// Component Judul Layar & Subtitle konsisten di seluruh aplikasi.
// Ref: Lead Apple UI/UX Review

import SwiftUI

public struct ScreenHeader: View {
    let title: String
    let subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(title)
                .font(AppFont.largeTitle)
                .foregroundStyle(AppTheme.Brand.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.Brand.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
