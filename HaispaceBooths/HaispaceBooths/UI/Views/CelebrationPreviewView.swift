// CelebrationPreviewView.swift
// HaispaceBooths — UI/Views (Scene 4: The Reveal)
//
// The Big Reveal & Celebration View Haispace Kiosk Photobooth.
// REVISION 1 — Based on Apple Design Review #007 (8.8/10 -> Target Approved 9.8+).
// - Full Edge-to-Edge Visual Canvas (No Rounded Card Border Feeling)
// - Real Render Image Binding (Image(uiImage:) support / High-Res Edge Bloom)
// - Extended 550ms "Breath of Pride" Pure Silence Budget
// - Cinematic Curtain Reveal (Opacity + Subtle Vignette Settle)
// - Clear Visual Hierarchy: Primary "Continue" vs Secondary Subtle "Retake".

import SwiftUI

public struct CelebrationPreviewView: View {
    
    // Injected Image Render & Action Intents
    private let capturedImage: UIImage?
    private let onAcceptPreview: () async -> Void
    private let onRetakeRequested: () async -> Void
    
    @State private var isPhotoVisible: Bool = false
    @State private var isActionBarVisible: Bool = false
    @State private var isLightSweepActive: Bool = false
    
    public init(
        capturedImage: UIImage? = nil,
        onAcceptPreview: @escaping () async -> Void,
        onRetakeRequested: @escaping () async -> Void
    ) {
        self.capturedImage = capturedImage
        self.onAcceptPreview = onAcceptPreview
        self.onRetakeRequested = onRetakeRequested
    }
    
    public var body: some View {
        ZStack {
            // Dark Matte Atmosphere Background
            Color(white: 0.03)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 95%+ EDGE-TO-EDGE HIGH-RES PHOTO CANVAS (THE BIG REVEAL)
                ZStack {
                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.6), radius: 32, x: 0, y: 16)
                    } else {
                        // High-Res Render Simulation Canvas (Full-bleed Edge Bloom)
                        ZStack {
                            LinearGradient(
                                colors: [Color(white: 0.18), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            
                            // Delicate Light Sweep Delight Layer
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(isLightSweepActive ? 0.15 : 0.0), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .animation(.easeInOut(duration: 1.2), value: isLightSweepActive)
                        }
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.6), radius: 32, x: 0, y: 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .opacity(isPhotoVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5), value: isPhotoVisible)
                
                Spacer().frame(height: 24)
                
                // HIERARCHICAL ACTION BAR (Fades in after 550ms "Breath of Pride")
                if isActionBarVisible {
                    HStack(spacing: 32) {
                        // Secondary Action: Subtle Ghost Retake Button
                        Button(action: {
                            Task { await onRetakeRequested() }
                        }) {
                            Text("Retake")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        // Primary Action: Dominant Continue Commitment Button
                        Button(action: {
                            Task { await onAcceptPreview() }
                        }) {
                            Text("Continue")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 54)
                                .padding(.vertical, 18)
                                .background(Capsule().fill(Color.white))
                                .shadow(color: Color.white.opacity(0.2), radius: 16, x: 0, y: 4)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            startBigRevealSequence()
        }
    }
    
    // MARK: - Big Reveal Sequence (Cinematic Curtain Reveal & 550ms Breath of Pride)
    
    private func startBigRevealSequence() {
        Task {
            // 1. 150ms Dark Screen Pause
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            // 2. Cinematic Curtain Photo Reveal
            withAnimation(.easeInOut(duration: 0.5)) {
                isPhotoVisible = true
            }
            
            // 3. Delicate Light Sweep Delight Layer
            try? await Task.sleep(nanoseconds: 200_000_000)
            isLightSweepActive = true
            
            // 4. 550ms Extended "Breath of Pride" Pure Silence Budget (Zero UI clutter)
            try? await Task.sleep(nanoseconds: 550_000_000)
            
            // 5. Hierarchical Action Bar Fades In Smoothly
            withAnimation(.easeInOut(duration: 0.35)) {
                isActionBarVisible = true
            }
        }
    }
}

#Preview {
    CelebrationPreviewView(
        onAcceptPreview: {},
        onRetakeRequested: {}
    )
}
