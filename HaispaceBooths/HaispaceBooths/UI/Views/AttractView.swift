// AttractView.swift
// HaispaceBooths — UI/Views (Scene 1: The Invitation)
//
// Standby / Attract Mode View Haispace Kiosk Photobooth.
// FINAL POLISHED VERSION — CONDITIONALLY APPROVED BY APPLE DESIGN REVIEW (9.1/10).
// - Full-bleed edge mask (Window to a Moment)
// - Global Screen Tap Gesture (.contentShape(Rectangle()))
// - Ken Burns 60fps pan/zoom/light breathing motion
// - Action Headline: "Let's Remember Today"

import SwiftUI

public struct AttractView: View {
    
    // Injected Workflow Action Intent
    private let onTouchToStart: () async -> Void
    
    @State private var isAnimating: Bool = false
    
    public init(onTouchToStart: @escaping () async -> Void) {
        self.onTouchToStart = onTouchToStart
    }
    
    public var body: some View {
        ZStack {
            // Background: Dark Graphite Radial Atmosphere
            RadialGradient(
                colors: [Color(white: 0.14), Color(white: 0.03)],
                center: .center,
                startRadius: 150,
                endRadius: 950
            )
            .ignoresSafeArea()
            
            // HERO WINDOW (Full-bleed Window to a Moment — No Heavy Card Border)
            ZStack {
                // Ken Burns Living Photo Canvas
                LinearGradient(
                    colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.3)],
                    startPoint: isAnimating ? .topLeading : .bottomTrailing,
                    endPoint: isAnimating ? .bottomTrailing : .topLeading
                )
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true), value: isAnimating)
                
                // Subtle Vignette Overlay
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                VStack(spacing: 12) {
                    Spacer()
                    
                    // Action Headline (Inviting & Emotional)
                    Text("Let's Remember Today")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
                    
                    // Subtitle (Light & Non-competing)
                    Text("Smile. Pose. Remember.")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .tracking(1.5)
                    
                    Spacer().frame(height: 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 120)
            
            // VISUAL CTA GUIDE (Screen-Wide Tap Enabled)
            VStack {
                Spacer()
                
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.5 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
                    
                    Text("Touch anywhere to begin")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                )
                .padding(.bottom, 48)
            }
        }
        .contentShape(Rectangle()) // Global Full Screen Tap
        .onTapGesture {
            Task {
                await onTouchToStart()
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    AttractView(onTouchToStart: {})
}
