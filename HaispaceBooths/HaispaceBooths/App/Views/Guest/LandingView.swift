// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar Standby Kiosk Tamu (Idle Screen).
// Ultra-Minimalist Cinematic Dark & VisionOS Ambient Glass.
// Diperbaiki: Header Logo, Footer Event Badge, Background Visibility, dan Secret 3-Tap Handler.

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
            // 1. Background Pitch Black Terdalam
            Color(hex: "#030303").ignoresSafeArea()
            
            // 2. Ambient Light Orbs (Visual Ambient Apple VisionOS)
            ambientGlowsLayer
            
            // 3. Phantom Background Grid (Photo Strips Melayang)
            phantomBackgroundGrid
            
            // 4. Vignette Radial Masking (Masking Halus Supaya Tengah Tetap Fokus)
            RadialGradient(
                colors: [.clear, Color(hex: "#030303").opacity(0.55), Color(hex: "#030303").opacity(0.92)],
                center: .center,
                startRadius: 180,
                endRadius: 650
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // 5. Layer Konten Utama (Header, Hero CTA, Footer)
            VStack {
                // HEADER: Logo Resmi (Comfortaa Style) — Diatur Aman di Bawah Status Bar iPad
                HStack(spacing: 6) {
                    Text("Haispace")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                    
                    Text("Project")
                        .font(.system(size: 32, weight: .light, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .tracking(4)
                }
                .padding(.top, 54)
                .shadow(color: Color(hex: "#7C5CFC").opacity(0.4), radius: 15)
                
                Spacer()
                
                // CENTER: Hero Call to Action Utama (Ripple Rings & Camera Icon)
                VStack(spacing: 32) {
                    ZStack {
                        // Expanding Ripple Ring 3
                        Circle()
                            .stroke(Color.white.opacity(isRippling ? 0.0 : 0.2), lineWidth: 1.5)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isRippling ? 2.0 : 1.0)
                        
                        // Expanding Ripple Ring 2
                        Circle()
                            .stroke(Color.white.opacity(isRippling ? 0.0 : 0.35), lineWidth: 1.5)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isRippling ? 1.5 : 1.0)
                        
                        // Inner Glass Circle Icon
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                                )
                                .shadow(color: Color(hex: "#7C5CFC").opacity(0.3), radius: 20)
                            
                            Image(systemName: "camera")
                                .font(.system(size: 46, weight: .thin))
                                .foregroundStyle(Color.white)
                                .shadow(color: Color.white.opacity(0.5), radius: 10)
                        }
                    }
                    
                    // Hero Typography
                    VStack(spacing: 12) {
                        Text("Sentuh Layar")
                            .font(.system(size: 60, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.white.opacity(0.25), radius: 20)
                        
                        Text("UNTUK MEMULAI SESI FOTO")
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .tracking(6)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleStartSession()
                }
                
                Spacer()
                
                // FOOTER: Detail Event Active (Pulsing Green Indicator Badge)
                VStack {
                    if let eventName = appState.operatorState.activeEvent?.name, !eventName.isEmpty {
                        eventBadgeView(name: eventName)
                    } else {
                        eventBadgeView(name: "WISUDA UNG 2026")
                    }
                }
                .padding(.bottom, 50)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                handleStartSession()
            }
            
            // 6. TOP RIGHT SECRET TAP AREA (Diatur zIndex Paling Atas agar Tidak Terhalang)
            VStack {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.001)) // Transparent Hit Area
                        .frame(width: 140, height: 140)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleSecretTap()
                        }
                }
                Spacer()
            }
            .zIndex(100) // Memastikan area rahasia menerima tap pertama kali!
            
            // 7. ADMIN TOAST NOTIFICATION OVERLAY
            if showAdminToast {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: "#00D9A0"))
                        
                        Text("🔒 Mengarahkan ke Verifikasi PIN...")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.5), radius: 25, y: 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 40)
                    
                    Spacer()
                }
                .zIndex(101)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                isRippling = true
            }
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                isBreathe = true
            }
            withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                isPhantomActive = true
            }
        }
    }
    
    // MARK: - Event Badge View
    private func eventBadgeView(name: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: 12, height: 12)
                    .scaleEffect(isBreathe ? 1.8 : 1.0)
                    .opacity(isBreathe ? 0.2 : 0.8)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            
            Text(name.uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .tracking(2.5)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .backdropBlur()
    }
    
    // MARK: - Ambient Glows
    private var ambientGlowsLayer: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#7C5CFC").opacity(0.15))
                .blur(radius: 110)
                .frame(width: 500, height: 500)
                .scaleEffect(isBreathe ? 1.15 : 0.85)
            
            Circle()
                .fill(Color(hex: "#00D9A0").opacity(0.1))
                .blur(radius: 120)
                .frame(width: 450, height: 450)
                .offset(x: isBreathe ? 150 : -150, y: isBreathe ? -100 : 100)
        }
        .allowsHitTesting(false)
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
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        secretTapTimer?.invalidate()
        secretTapTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
            secretTapCount = 0
        }
        
        if secretTapCount >= 3 {
            let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
            heavyGenerator.impactOccurred()
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
        HStack(spacing: 24) {
            ForEach(0..<6, id: \.self) { col in
                VStack(spacing: 24) {
                    photoStripMockup
                    photoStripMockup
                    photoStripMockup
                }
                .offset(y: col % 2 == 0 ? (isPhantomActive ? -30 : 30) : (isPhantomActive ? 30 : -30))
                .opacity(isPhantomActive ? 0.45 : 0.25)
            }
        }
        .rotationEffect(.degrees(-6))
        .scaleEffect(1.15)
        .blur(radius: 1.0)
        .allowsHitTesting(false)
    }
    
    private var photoStripMockup: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 86, height: 110)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.25))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
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
