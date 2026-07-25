// ProgressDots.swift
// HaispaceBooths — App/DesignSystem/Components
//
// Indikator Kemajuan Sesi Foto (Dot Indicators konsisten).
// Ref: Lead Apple UI/UX Review

import SwiftUI

public struct ProgressDots: View {
    let total: Int
    let current: Int // 0-based

    public init(total: Int, current: Int) {
        self.total = total
        self.current = current
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index <= current ? AppTheme.Brand.gold : AppTheme.Brand.textPrimary.opacity(0.2))
                    .frame(width: 10, height: 10)
                    .scaleEffect(index == current ? 1.3 : 1.0)
                    .animation(Motion.thumbnail, value: current)
            }
        }
        .accessibilityLabel("Foto \(current + 1) dari \(total)")
    }
}
