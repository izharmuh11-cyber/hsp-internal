// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar Standby Kiosk Tamu (Idle Screen).
// Bertema VisionOS Liquid Glass & Cinematic Dark.
// Menampilkan Logo Resmi Haispace Project, Kartu Sampel Melayang, dan Sentuhan Layar Penuh.

import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isAnimating = false
    @State private var isPulsing = false
    @State private var secretTapCount = 0
    @State private var secretTapTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            // Background Terdalam
            Color(hex: "#05050C").ignoresSafeArea()
            
            // Premium Moving Ambient Glows (Apple TV / VisionOS Style)
            Circle()
                .fill(Color(hex: "#7C5CFC").opacity(0.22))
                .blur(radius: 100)
                .frame(width: 500, height: 500)
                .offset(x: isAnimating ? 280 : -280, y: isAnimating ? -220 : 220)
            
            Circle()
                .fill(Color(hex: "#00D9A0").opacity(0.16))
                .blur(radius: 105)
                .frame(width: 420, height: 420)
                .offset(x: isAnimating ? -280 : 280, y: isAnimating ? 220 : -220)
            
            Circle()
                .fill(Color(hex: "#4F46E5").opacity(0.18))
                .blur(radius: 90)
                .frame(width: 460, height: 460)
                .offset(x: isAnimating ? 180 : -180, y: isAnimating ? 180 : -180)
            
            // Kartu Sampel Foto Melayang Latar Belakang (Visual Hook)
            floatingPhotoCardsOverlay
            
            // Konten Utama Landing Page
            VStack(spacing: 40) {
                Spacer().frame(height: 20)
                
                // Header Branding — LOGO HAISPACE PROJECT (Font Comfortaa Style)
                VStack(spacing: 16) {
                    HaispaceLandingLogoView()
                    
                    if let event = appState.operatorState.activeEvent {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: "#00D9A0"))
                            
                            Text(event.name.uppercased())
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .tracking(3)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.white, Color.white.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        
                        Text("\(event.location) • \(event.isPayPerSession ? "Rp \(Int(event.pricePerSession).formatted()) / Sesi" : "Free Event")")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(1.5)
                    } else {
                        Text("The Premium Photobooth Experience")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(3)
                    }
                }
                
                Spacer()
                
                // Call to Action — Pulsing Glass Capsule CTA ("Sentuh Layar Untuk Mulai")
                Button(action: handleStartSession) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#7C5CFC"), Color(hex: "#00D9A0")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: Color(hex: "#7C5CFC").opacity(0.6), radius: 20)
                            
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(isPulsing ? 1.08 : 0.96)
                        
                        VStack(spacing: 4) {
                            Text("Sentuh Layar Untuk Mulai")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .tracking(1)
                            
                            Text("Abadikan Momen Manismu di Haispace Booth")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 36)
                    .padding(.horizontal, 72)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color(hex: "#7C5CFC").opacity(isPulsing ? 0.4 : 0.18), radius: isPulsing ? 30 : 16, y: 10)
                }
                .buttonStyle(BentoButtonStyle())
                
                Spacer()
                
                // Status Badge & Footer
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: "#00D9A0"))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color(hex: "#00D9A0"), radius: 4)
                        
                        Text("Kiosk Standby Active")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .padding(.bottom, 36)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleStartSession()
            }
            
            // Hidden Corner Shortcut (Top Right Secret Tap for Operator PIN Entry)
            VStack {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 80, height: 80)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            secretTapCount += 1
                            secretTapTimer?.invalidate()
                            secretTapTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
                                secretTapCount = 0
                            }
                            if secretTapCount >= 3 {
                                playHaptic(style: .heavy)
                                secretTapCount = 0
                                withAnimation(.spring) {
                                    appState.operatorState.isVerifyingPIN = true
                                }
                            }
                        }
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    private func handleStartSession() {
        playHaptic(style: .medium)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            appState.navigateTo(.guestRegistration)
        }
    }
    
    // MARK: - Floating Photo Strip Sample Overlay
    private var floatingPhotoCardsOverlay: some View {
        HStack {
            // Left Floating Card
            VStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 140, height: 260)
                        .rotationEffect(.degrees(-8))
                        .overlay(
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)).frame(height: 70)
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)).frame(height: 70)
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)).frame(height: 70)
                            }
                            .padding(10)
                            .rotationEffect(.degrees(-8))
                        )
                        .blur(radius: 0.5)
                        .opacity(0.45)
                }
                .offset(x: -20, y: isAnimating ? -30 : 20)
                Spacer()
            }
            
            Spacer()
            
            // Right Floating Card
            VStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 140, height: 260)
                        .rotationEffect(.degrees(10))
                        .overlay(
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)).frame(height: 70)
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)).frame(height: 70)
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)).frame(height: 70)
                            }
                            .padding(10)
                            .rotationEffect(.degrees(10))
                        )
                        .blur(radius: 0.5)
                        .opacity(0.45)
                }
                .offset(x: 20, y: isAnimating ? 25 : -25)
                Spacer()
            }
        }
        .padding(.horizontal, 40)
        .ignoresSafeArea()
    }
}

// MARK: - Logo Resmi Haispace Project (Gaya Font Comfortaa untuk Dark Background)
struct HaispaceLandingLogoView: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: -10) {
            Text("Haispace")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(Color.white)
                .shadow(color: Color(hex: "#7C5CFC").opacity(0.5), radius: 25)
            
            Text("Project")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.trailing, 2)
                .shadow(color: Color(hex: "#7C5CFC").opacity(0.3), radius: 15)
        }
    }
}

#Preview {
    LandingView()
        .environment(AppState.preview)
}
