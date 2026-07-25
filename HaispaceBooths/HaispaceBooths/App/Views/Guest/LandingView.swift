// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar Standby Kiosk Tamu (Ultra-Minimalist Idle Screen).
// Bertema VisionOS Ambient Dark & Floating Photo Strip Background.
// Menampilkan Logo Haispace Project, Subtle Camera Accent, & Full Screen Tap.

import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    
    // State Animasi Standby
    @State private var isBreathe = false
    @State private var isPhantomActive = false
    
    // State Secret Operator PIN
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
                colors: [.clear, Color(hex: "#030303").opacity(0.55), Color(hex: "#030303").opacity(0.94)],
                center: .center,
                startRadius: 160,
                endRadius: 650
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // 5. ULTRA-MINIMALIST HERO CONTENT (Logo, Camera Accent & Touch Prompt)
            VStack {
                Spacer()
                
                VStack(spacing: 32) {
                    // Logo Minimalis Haispace Project
                    HaispaceOfficialLogoView()
                    
                    // Camera Circle Accent
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#7C5CFC").opacity(0.22), Color(hex: "#00D9A0").opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: Color(hex: "#7C5CFC").opacity(0.35), radius: 20)
                        
                        Image(systemName: "camera")
                            .font(.system(size: 38, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .scaleEffect(isBreathe ? 1.06 : 0.94)
                    
                    // Typography Prompt
                    VStack(spacing: 10) {
                        Text("Sentuh Layar")
                            .font(.system(size: 56, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: Color.white.opacity(0.2), radius: 15)
                        
                        HStack(spacing: 6) {
                            Text("✨")
                            Text("UNTUK MEMULAI SESI FOTO")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#00D9A0"))
                                .tracking(4)
                            Text("✨")
                        }
                    }
                }
                
                Spacer()
                
                // FOOTER: Active Event Badge (Terpaku di Bawah)
                if let eventName = appState.operatorState.activeEvent?.name, !eventName.isEmpty {
                    eventBadgeView(name: eventName)
                } else {
                    eventBadgeView(name: "WISUDA UNG 2026")
                }
            }
            .padding(.vertical, 48)
            .contentShape(Rectangle())
            .onTapGesture {
                handleStartSession()
            }
            
            // 6. TOP RIGHT SECRET TAP AREA (Khusus PIN Operator)
            VStack {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 140, height: 140)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleSecretTap()
                        }
                }
                Spacer()
            }
            
            // 7. ADMIN TOAST NOTIFICATION OVERLAY
            VStack {
                if showAdminToast {
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
                    .padding(.top, 90)
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                isBreathe = true
            }
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                isPhantomActive = true
            }
        }
    }
    
    // ADR-001: View hanya mengirim intent — tidak menentukan route secara langsung
    // Migration commit: LandingView ✅ (Step 2 dari 8 migration steps)
    private func handleStartSession() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            try await appState.send(.startGuestRegistration)
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
                    .fill(Color(hex: "#00D9A0"))
                    .frame(width: 8, height: 8)
            }
            
            Text(name.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .tracking(2.5)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
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
    
    // MARK: - Secret Operator Tap Handler
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

// MARK: - Logo Resmi Haispace Project (Ultra-Minimalist Typography)
struct HaispaceOfficialLogoView: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Haispace")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color(hex: "#7C5CFC").opacity(0.5), radius: 18)
            
            Text("Project")
                .font(.system(size: 38, weight: .ultraLight, design: .rounded))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.75))
        }
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

