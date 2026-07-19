// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar Standby Kiosk Tamu (Idle Screen).
// Bertema Ultra-Minimalist Cinematic Dark & VisionOS Ambient Glass.
// Menampilkan Phantom Pattern Masking, Concentric Ripple Camera, Logo Comfortaa, dan Secret Admin Toast.

import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isRippling = false
    @State private var isBreathe = false
    @State private var isPhantomActive = false
    @State private var secretTapCount = 0
    @State private var secretTapTimer: Timer? = nil
    @State private var showAdminToast = false
    
    var body: some View {
        ZStack {
            // Background Pitch Black Terdalam
            Color(hex: "#030303").ignoresSafeArea()
            
            // Phantom Background & Center Ambient Glow
            phantomBackgroundGrid
            
            // Vignette Radial Mask (Memastikan Bagian Tengah Layar Tetap Clean Pitch Black)
            RadialGradient(
                colors: [.clear, Color(hex: "#030303").opacity(0.85), Color(hex: "#030303")],
                center: .center,
                startRadius: 120,
                endRadius: 600
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // Layer Konten Utama (Sentuh Layar di Mana Saja untuk Mulai)
            VStack {
                Spacer().frame(height: 36)
                
                // HEADER: Logo Minimalis (Comfortaa Style)
                HStack(spacing: 4) {
                    Text("Haispace")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                    
                    Text("Project")
                        .font(.system(size: 26, weight: .light, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .tracking(3)
                }
                .shadow(color: Color.white.opacity(0.15), radius: 10)
                
                Spacer()
                
                // CENTER: Call to Action Utama (Concentric Ripple & Hero Typography)
                VStack(spacing: 36) {
                    // Concentric Ripple Camera Icon
                    ZStack {
                        // Expanding Ripple Ring 2
                        Circle()
                            .stroke(Color.white.opacity(isRippling ? 0.0 : 0.25), lineWidth: 1.5)
                            .frame(width: 112, height: 112)
                            .scaleEffect(isRippling ? 1.75 : 1.0)
                        
                        // Expanding Ripple Ring 1
                        Circle()
                            .stroke(Color.white.opacity(isRippling ? 0.0 : 0.35), lineWidth: 1.5)
                            .frame(width: 112, height: 112)
                            .scaleEffect(isRippling ? 1.4 : 1.0)
                        
                        // Inner Glass Circle Icon
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.06))
                                .frame(width: 112, height: 112)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: Color.white.opacity(0.1), radius: 15)
                            
                            Image(systemName: "camera")
                                .font(.system(size: 42, weight: .thin))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .shadow(color: Color.white.opacity(0.3), radius: 10)
                        }
                    }
                    
                    // Hero Typography
                    VStack(spacing: 12) {
                        Text("Sentuh Layar")
                            .font(.system(size: 56, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.white.opacity(0.2), radius: 15)
                        
                        Text("UNTUK MEMULAI SESI FOTO")
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .tracking(6)
                    }
                }
                
                Spacer()
                
                // FOOTER: Detail Event Active (Clean Glass Badge dengan Indicator Pulsing Green)
                VStack {
                    if let eventName = appState.operatorState.activeEvent?.name, !eventName.isEmpty {
                        eventBadgeView(name: eventName)
                    } else {
                        eventBadgeView(name: "WISUDA UNG 2026")
                    }
                }
                .padding(.bottom, 36)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleStartSession()
            }
            
            // Hidden Secret Area (Top Right Secret Tap for Operator Admin Area)
            VStack {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 120, height: 120)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleSecretTap()
                        }
                }
                Spacer()
            }
            
            // Admin Toast Notification Overlay
            if showAdminToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "#00D9A0"))
                        
                        Text("Mengarahkan ke Verifikasi PIN...")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 20, y: 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 24)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                isRippling = true
            }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                isBreathe = true
            }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                isPhantomActive = true
            }
        }
    }
    
    // MARK: - Event Badge View
    private func eventBadgeView(name: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isBreathe ? 1.6 : 1.0)
                    .opacity(isBreathe ? 0.2 : 0.8)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            
            Text(name.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
                .tracking(2.5)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .backdropBlur()
    }
    
    // MARK: - Tap & Secret Gesture Handlers
    private func handleStartSession() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            appState.navigateTo(.guestRegistration)
        }
    }
    
    private func handleSecretTap() {
        secretTapCount += 1
        secretTapTimer?.invalidate()
        secretTapTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
            secretTapCount = 0
        }
        
        if secretTapCount >= 3 {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            secretTapCount = 0
            
            withAnimation(.spring) {
                showAdminToast = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring) {
                    showAdminToast = false
                    appState.operatorState.isVerifyingPIN = true
                }
            }
        }
    }
    
    // MARK: - Phantom Background Grid & Photo Strips
    private var phantomBackgroundGrid: some View {
        ZStack {
            // Center Soft Ambient Glow
            Circle()
                .fill(Color.white.opacity(0.03))
                .blur(radius: 90)
                .frame(width: 500, height: 500)
                .scaleEffect(isBreathe ? 1.08 : 0.92)
            
            // Staggered Floating Photo Strip Columns (Phantom Pattern)
            HStack(spacing: 28) {
                ForEach(0..<6, id: \.self) { col in
                    VStack(spacing: 20) {
                        photoStripMockup
                        photoStripMockup
                        photoStripMockup
                    }
                    .offset(y: col % 2 == 0 ? (isPhantomActive ? -25 : 25) : (isPhantomActive ? 25 : -25))
                    .opacity(isPhantomActive ? 0.35 : 0.15)
                }
            }
            .rotationEffect(.degrees(-6))
            .scaleEffect(1.15)
            .blur(radius: 1.5)
        }
        .allowsHitTesting(false)
    }
    
    private var photoStripMockup: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .frame(width: 80, height: 100)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .frame(width: 80, height: 100)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .frame(width: 80, height: 100)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - View Helper Extension for Backdrop Blur
extension View {
    func backdropBlur() -> some View {
        self.background(.ultraThinMaterial)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    LandingView()
        .environment(AppState.preview)
}
