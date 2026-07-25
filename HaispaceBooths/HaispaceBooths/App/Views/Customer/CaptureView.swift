// CaptureView.swift
// HaispaceBooths — App/Views/Customer/Capture
//
// Layar pengambilan foto (Cinematic & Automated).
// Refactor: Menggunakan DesignSystem (Tokens, Components, Motion)
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

public struct CaptureView: View {

    @Environment(AppState.self) private var appState

    let totalPhotos: Int
    let currentPhotoIndex: Int  // 0-based
    let countdownValue: Int?    // nil = belum mulai countdown
    let lastCapturedThumbnail: UIImage?
    let isFlashing: Bool        // true sesaat setelah klik

    @State private var showIdleHint: Bool = false
    @State private var idleTimer: Timer? = nil

    @State private var thumbnailScale: CGFloat = 1.0

    public var body: some View {
        ZStack {
            AppTheme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress Header (DesignSystem ProgressDots)
                progressHeader
                    .padding(.top, Spacing.section)
                    .padding(.horizontal, Spacing.xxl)

                // Camera Live View
                cameraArea
                    .padding(.top, Spacing.lg)

                // Thumbnail strip foto sebelumnya
                if let thumbnail = lastCapturedThumbnail {
                    previousPhotoStrip(image: thumbnail)
                        .padding(.top, Spacing.lg)
                }

                // Warm Micro-copy
                instructionText
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.section)
            }

            // Natural Flash Overlay
            if isFlashing {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Floating Cinematic Countdown Overlay
            if let countdown = countdownValue {
                cinematicCountdown(value: countdown)
            }

            // Idle Hint (DesignSystem GlassHint)
            if showIdleHint {
                VStack {
                    Spacer()
                    GlassHint(iconName: "camera.circle.fill", message: "Lihat ke kamera. Foto akan diambil otomatis.")
                        .padding(.bottom, 80)
                }
                .transition(.opacity.animation(Motion.screen))
            }
        }
        .onAppear { startIdleTimer() }
        .onDisappear { idleTimer?.invalidate() }
        .onChange(of: lastCapturedThumbnail) { _, _ in
            thumbnailScale = 1.2
            withAnimation(Motion.thumbnail) {
                thumbnailScale = 1.0
            }
        }
    }

    private var progressHeader: some View {
        HStack {
            Text("Foto \(currentPhotoIndex + 1) dari \(totalPhotos)")
                .font(AppFont.headline)
                .foregroundStyle(AppTheme.Brand.textPrimary)
                .accessibilityIdentifier("capture.photoCounter")

            Spacer()

            ProgressDots(total: totalPhotos, current: currentPhotoIndex)
                .accessibilityIdentifier("capture.progressDots")
        }
    }

    private var cameraArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.Surface.secondary)
                .overlay(
                    ZStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.Brand.textPrimary.opacity(0.08))

                        CornerGuideView()
                    }
                )

            Image(systemName: "person.fill")
                .font(.system(size: 90))
                .foregroundStyle(AppTheme.Brand.textPrimary.opacity(0.03))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .padding(.horizontal, Spacing.xl)
        .shadow(color: .black.opacity(0.4), radius: 16)
        .accessibilityIdentifier("capture.cameraFeed")
    }

    private func cinematicCountdown(value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 130, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Brand.textPrimary)
            .shadow(color: .black.opacity(0.6), radius: 10)
            .shadow(color: AppTheme.Brand.gold.opacity(0.6), radius: 30)
            .scaleEffect(value == 1 ? 1.15 : 1.0)
            .contentTransition(.numericText(countsDown: true))
            .animation(Motion.thumbnail, value: value)
            .accessibilityIdentifier("capture.countdown")
            .accessibilityLabel("Hitung mundur \(value) detik")
    }

    private func previousPhotoStrip(image: UIImage) -> some View {
        HStack(spacing: Spacing.md) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.Brand.gold, lineWidth: 2)
                )
                .scaleEffect(thumbnailScale)
                .shadow(color: .black.opacity(0.35), radius: 8)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Foto \(currentPhotoIndex)")
                    .font(AppFont.headline)
                    .foregroundStyle(AppTheme.Brand.gold)

                Text("Tersimpan")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppTheme.Brand.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionText: some View {
        Group {
            if let countdown = countdownValue {
                switch countdown {
                case 3: Text("Senyum").foregroundStyle(AppTheme.Brand.textPrimary.opacity(0.85))
                case 2: Text("Tahan pose").foregroundStyle(AppTheme.Brand.textPrimary.opacity(0.95))
                case 1: Text("1...").foregroundStyle(AppTheme.Brand.gold)
                default: Text("Siapkan pose terbaikmu").foregroundStyle(AppTheme.Brand.textSecondary)
                }
            } else {
                Text("Siapkan pose terbaikmu")
                    .foregroundStyle(AppTheme.Brand.textSecondary)
            }
        }
        .font(AppFont.headline)
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation(Motion.screen) { showIdleHint = true }
        }
    }
}

private struct CornerGuideView: View {
    private let length: CGFloat = 26
    private let thickness: CGFloat = 3.0

    var body: some View {
        ZStack {
            let alignments: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
            ForEach(0..<4, id: \.self) { i in
                CornerMark(alignment: alignments[i], length: length, thickness: thickness)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CornerMark: View {
    let alignment: Alignment
    let length: CGFloat
    let thickness: CGFloat

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear
            HStack(spacing: 0) {
                if alignment == .topTrailing || alignment == .bottomTrailing { Spacer() }
                VStack(spacing: 0) {
                    if alignment == .bottomLeading || alignment == .bottomTrailing { Spacer() }
                    cornerShape
                    if alignment == .topLeading || alignment == .topTrailing { Spacer() }
                }
                if alignment == .topLeading || alignment == .bottomLeading { Spacer() }
            }
        }
    }

    private var cornerShape: some View {
        let isLeft = alignment == .topLeading || alignment == .bottomLeading
        let isTop  = alignment == .topLeading  || alignment == .topTrailing
        return ZStack(alignment: .init(horizontal: isLeft ? .leading : .trailing,
                                       vertical:   isTop  ? .top    : .bottom)) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.4))
                .frame(width: length, height: thickness)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.4))
                .frame(width: thickness, height: length)
        }
        .frame(width: length, height: length)
    }
}


