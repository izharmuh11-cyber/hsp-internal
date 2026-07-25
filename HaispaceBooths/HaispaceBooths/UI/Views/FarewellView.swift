// FarewellView.swift
// HaispaceBooths — UI/Views (Scene 6: The Goodbye)
//
// Warm Farewell & Seamless Attract Reset View Haispace Kiosk Photobooth.
// Scene Intent: "Leave people wanting to return".
// Fulfills 10-Point Design Checklist (Doc #56) & Doc #55 Rhythm Architecture:
// - 2-3s Warm Heartfelt Closure ("See you next time!")
// - Smooth Auto-Fade Reset back to Scene 1 Attract Mode (Zero technical glitch/flash)
// - Complete 6-Act Experience Journey.

import SwiftUI

public struct FarewellView: View {
    
    // Injected Reset Action Handler
    private let onResetToAttractMode: () async -> Void
    
    @State private var isFadingOut: Bool = false
    
    public init(onResetToAttractMode: @escaping () async -> Void) {
        self.onResetToAttractMode = onResetToAttractMode
    }
    
    public var body: some View {
        ZStack {
            // Dark Matte Atmosphere Background
            Color(white: 0.04)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                // Warm Heartfelt Farewell Icon & Typography
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.pink.opacity(0.9))
                    .shadow(color: .pink.opacity(0.3), radius: 20, x: 0, y: 0)
                
                Text("See You Next Time!")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                
                Text("Thank you for capturing your special memories with Haispace.")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                
                Spacer()
            }
            .opacity(isFadingOut ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.8), value: isFadingOut)
        }
        .onAppear {
            startFarewellTimer()
        }
    }
    
    // MARK: - 3s Warm Farewell & Smooth Reset Engine
    
    private func startFarewellTimer() {
        Task {
            // 1. 2.5s Warm Display Hold
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            
            // 2. 800ms Smooth Fade-Out
            withAnimation(.easeInOut(duration: 0.8)) {
                isFadingOut = true
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            // 3. Complete Reset to Scene 1 Attract Mode
            await onResetToAttractMode()
        }
    }
}

#Preview {
    FarewellView(onResetToAttractMode: {})
}
