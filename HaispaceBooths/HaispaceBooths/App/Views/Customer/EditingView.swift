// EditingView.swift
// HaispaceBooths — App/Views/Customer/Editing
//
// Layar Editing (Quick & Intuitive).
// Refactor: Menggunakan DesignSystem (Tokens, Components, Motion)
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

public struct EditingView: View {

    @Environment(AppState.self) private var appState

    public struct FrameOption: Identifiable {
        public let id: String
        public let name: String
        public let colorHex: String
    }

    public struct FilterOption: Identifiable {
        public let id: String
        public let name: String
    }

    private let frames: [FrameOption] = [
        FrameOption(id: "classic_white", name: "Classic White", colorHex: "#FFFFFF"),
        FrameOption(id: "noir_black", name: "Noir Black", colorHex: "#111111"),
        FrameOption(id: "warm_amber", name: "Warm Amber", colorHex: "#F5A623"),
        FrameOption(id: "soft_cream", name: "Soft Cream", colorHex: "#F4EBD9")
    ]

    private let filters: [FilterOption] = [
        FilterOption(id: "original", name: "Original"),
        FilterOption(id: "warm_vibe", name: "Warm Vibe"),
        FilterOption(id: "vintage_bw", name: "B&W Film"),
        FilterOption(id: "soft_glow", name: "Soft Glow")
    ]

    @State private var selectedFrameId: String = "classic_white"
    @State private var selectedFilterId: String = "original"
    @State private var selectedSegment: Int = 0 // 0: Frame, 1: Filter

    public var body: some View {
        ZStack {
            AppTheme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (DesignSystem ScreenHeader)
                ScreenHeader(title: "Sentuhan Akhir")
                    .padding(.top, Spacing.section)

                Spacer()

                // Live Preview Area
                previewArea
                    .padding(.horizontal, Spacing.xxl)

                Spacer()

                // Segment Picker (Frame vs Filter)
                segmentPicker
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.bottom, Spacing.lg)

                // Option Selector (Frame colors / Filter list)
                optionsCarousel
                    .frame(height: 70)
                    .padding(.bottom, Spacing.xl)

                // Finish Button (DesignSystem PrimaryButton)
                PrimaryButton(title: "Selesai") {
                    Task { try? await appState.send(.acceptPreview) }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.section)
            }
        }
    }

    private var previewArea: some View {
        let frameColor = Color(hex: frames.first(where: { $0.id == selectedFrameId })?.colorHex ?? "#FFFFFF")

        return RoundedRectangle(cornerRadius: 18)
            .fill(frameColor)
            .overlay(
                VStack(spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.Surface.secondary)
                        .overlay(
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppTheme.Brand.textPrimary.opacity(0.15))
                        )
                        .frame(height: 140)

                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.Surface.secondary)
                        .overlay(
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppTheme.Brand.textPrimary.opacity(0.15))
                        )
                        .frame(height: 140)

                    HStack {
                        Text("HAISPACE")
                            .font(AppFont.caption)
                            .foregroundStyle(frameColor == .white ? Color.black.opacity(0.6) : AppTheme.Brand.textPrimary.opacity(0.6))
                            .tracking(2)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(Spacing.lg)
            )
            .frame(width: 210, height: 360)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(Motion.screen) { selectedSegment = 0 }
            } label: {
                Text("Frame")
                    .font(AppFont.footnote)
                    .foregroundStyle(selectedSegment == 0 ? AppTheme.Brand.textPrimary : AppTheme.Brand.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(selectedSegment == 0 ? AppTheme.Brand.textPrimary.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
            }

            Button {
                withAnimation(Motion.screen) { selectedSegment = 1 }
            } label: {
                Text("Filter")
                    .font(AppFont.footnote)
                    .foregroundStyle(selectedSegment == 1 ? AppTheme.Brand.textPrimary : AppTheme.Brand.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(selectedSegment == 1 ? AppTheme.Brand.textPrimary.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
            }
        }
        .padding(Spacing.xs)
        .background(AppTheme.Brand.textPrimary.opacity(0.08))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var optionsCarousel: some View {
        if selectedSegment == 0 {
            HStack(spacing: Spacing.xl) {
                ForEach(frames) { frame in
                    Button {
                        withAnimation(Motion.screen) { selectedFrameId = frame.id }
                    } label: {
                        Circle()
                            .fill(Color(hex: frame.colorHex))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(selectedFrameId == frame.id ? AppTheme.Brand.gold : AppTheme.Brand.textPrimary.opacity(0.2), lineWidth: selectedFrameId == frame.id ? 3 : 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame \(frame.name)")
                }
            }
        } else {
            HStack(spacing: Spacing.md) {
                ForEach(filters) { filter in
                    Button {
                        withAnimation(Motion.screen) { selectedFilterId = filter.id }
                    } label: {
                        Text(filter.name)
                            .font(AppFont.footnote)
                            .foregroundStyle(selectedFilterId == filter.id ? AppTheme.Brand.textDark : AppTheme.Brand.textPrimary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedFilterId == filter.id ? AppTheme.Brand.textPrimary : AppTheme.Brand.textPrimary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter \(filter.name)")
                }
            }
        }
    }
}
