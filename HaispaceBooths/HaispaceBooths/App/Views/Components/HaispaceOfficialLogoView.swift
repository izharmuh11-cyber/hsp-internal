// HaispaceOfficialLogoView.swift
// HaispaceBooths — App/Views/Components

import SwiftUI

public struct HaispaceOfficialLogoView: View {
    public init() {}
    
    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "camera.macro.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.Brand.gold)

            Text("HAISPACE")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(AppTheme.Brand.textPrimary)
        }
    }
}
