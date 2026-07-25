// CameraCaptureView.swift
// HaispaceBooths — UI/Views (Scene 3: The Moment)
//
// Camera Live Capture & Automatic Pose Countdown View Haispace Kiosk Photobooth.
// REVISION 1 — Based on Apple Design Review #005 (8.8/10 -> Target Approved).
// - ZERO SHUTTER BUTTON: The System Moves First (Automatic 0.8s Orientation -> Countdown)
// - State Machine Engine: enum CaptureStage (ready, guiding, countdown, flashing, reveal)
// - Visual AR Silhouette Pose Guide (No verbal text)
// - Non-blocking Upper Eye-Line Countdown Typography
// - Deep Reveal Sequence: Shutter Flash -> 150ms Dark -> 200ms Silence -> Scene 4 Reveal.

import SwiftUI

public struct CameraCaptureView: View {
    
    // Injected Action Intent
    private let onCaptureCompleted: (String) async -> Void
    
    // Explicit FSM Stage Engine
    private enum CaptureStage: Equatable {
        case ready
        case guiding
        case countdown(Int)
        case flashing
        case reveal
    }
    
    @State private var stage: CaptureStage = .ready
    @State private var sequenceTask: Task<Void, Never>? = nil
    
    public init(onCaptureCompleted: @escaping (String) async -> Void) {
        self.onCaptureCompleted = onCaptureCompleted
    }
    
    public var body: some View {
        ZStack {
            // Background Canvas: Deep Matte Dark
            Color.black
                .ignoresSafeArea()
            
            // 90% LIVE AVCAPTURE CAMERA STAGE (The Human Moment Stage)
            ZStack {
                // Live Camera Stream Canvas Placeholder
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(white: 0.14), Color(white: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                // CAMERA FOCUS & EXPOSURE LOCK VIGNETTE EFFECT (200ms Camera Ready Indicator)
                RadialGradient(
                    gradient: Gradient(colors: [.clear, Color.black.opacity(stage == .ready ? 0.4 : 0.15)]),
                    center: .center,
                    startRadius: 100,
                    endRadius: 500
                )
                .animation(.easeInOut(duration: 0.3), value: stage)
                
                // VISUAL AR ORGANIC HUMAN SILHOUETTE OVERLAY (No SF Symbol / No Verbal Text)
                if stage == .guiding || isCountdownActive {
                    VStack {
                        Spacer()
                        
                        // Elegant Organic Skeleton/Silhouette Body Outline
                        ZStack {
                            // Head Circle
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                .frame(width: 80, height: 80)
                                .offset(y: -50)
                            
                            // Shoulder Capsule Outline
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 2)
                                .frame(width: 220, height: 90)
                                .offset(y: 30)
                        }
                        .shadow(color: .white.opacity(0.25), radius: 16, x: 0, y: 0)
                        .padding(.bottom, 80)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                
                // EYE-LINE COUNTDOWN OVERLAY (Living Motion Pulse - Shifted Upwards)
                if case .countdown(let val) = stage {
                    VStack {
                        Text("\(val)")
                            .font(.system(size: 110, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
                            .scaleEffect(1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: val)
                            .padding(.top, 40) // Upper Eye-Line Placement
                        
                        Spacer()
                    }
                }
                
                // DEEP REVEAL SHUTTER FLASH OVERLAY
                if stage == .flashing {
                    Color.white
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.all, 24)
        }
        .onAppear {
            startAutomaticCaptureSequence()
        }
        .onDisappear {
            sequenceTask?.cancel()
        }
    }
    
    // MARK: - Automatic System Sequence Engine (Zero Shutter Button)
    
    private var isCountdownActive: Bool {
        if case .countdown(_) = stage { return true }
        return false
    }
    
    private func startAutomaticCaptureSequence() {
        sequenceTask?.cancel()
        sequenceTask = Task {
            // 1. Stage: Ready -> Camera Hardware Stabilization (800ms Orientation & Focus Lock)
            stage = .ready
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            
            // 2. Stage: Guiding -> AR Organic Silhouette Fade-in
            stage = .guiding
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            
            // 3. Stage: Countdown Sequence (3... 2... 1...)
            stage = .countdown(3)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            stage = .countdown(2)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            stage = .countdown(1)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            // 3b. Micro-Anticipation Pause (100ms silence hold after "1" disappears)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            
            // 4. Stage: Flashing -> Shutter Bloom Flash
            withAnimation(.easeOut(duration: 0.15)) {
                stage = .flashing
            }
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms dark hold
            guard !Task.isCancelled else { return }
            
            // 5. Stage: Reveal -> 300ms Deep Breath Silence & Complete Capture Intent
            stage = .reveal
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            await onCaptureCompleted("captured_photo_001.jpg")
        }
    }
}

#Preview {
    CameraCaptureView(onCaptureCompleted: { _ in })
}
