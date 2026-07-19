// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar Standby Kiosk Tamu (Idle Screen) & Form Registrasi Infinite Canvas.
// Bertema Ultra-Minimalist Cinematic Dark & VisionOS Ambient Glass.
// Menampilkan Logo Resmi Haispace Project (Ikon Spatial Prism + Comfortaa), Concentric Ripple Camera, dan Seamless Full-Page Infinite Canvas Transition.

import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    
    // State Animasi Standby
    @State private var isRippling = false
    @State private var isBreathe = false
    @State private var isPhantomActive = false
    
    // State Secret Operator PIN
    @State private var secretTapCount = 0
    @State private var secretTapTimer: Timer? = nil
    @State private var showAdminToast = false
    
    // State Transisi Registrasi Tamu (Infinite Canvas)
    @State private var isRegistering = false
    @State private var guestName: String = ""
    @State private var instagramHandle: String = ""
    @State private var activeField: FieldType = .name
    
    enum FieldType {
        case name
        case instagram
    }
    
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
            
            // 5. Layer Konten Utama (Header Logo, Infinite Canvas Switching, Footer)
            VStack(spacing: 0) {
                // HEADER LOGO RESMI HAISPACE PROJECT (Prominent Glowing Spatial Logo)
                HaispaceOfficialLogoView()
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                
                Spacer()
                
                // CENTER CONTENT: Infinite Canvas Transition (Standby Mode Hero vs Full-Page Registration)
                ZStack {
                    if !isRegistering {
                        // MODE 1: STANDBY HERO CTA (Full Touch Target)
                        standbyHeroCTA
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                                    removal: .scale(scale: 1.08).combined(with: .opacity)
                                )
                            )
                    } else {
                        // MODE 2: FULL-PAGE INFINITE CANVAS REGISTRATION
                        fullPageRegistrationCanvas
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .scale(scale: 0.92).combined(with: .opacity)
                                )
                            )
                    }
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
                .padding(.bottom, 36)
            }
            
            // 6. TOP RIGHT SECRET TAP AREA (Diatur zIndex Paling Atas untuk PIN Operator)
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
            .zIndex(100)
            
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
    
    // MARK: - Standby Mode Hero CTA
    private var standbyHeroCTA: some View {
        VStack(spacing: 32) {
            ZStack {
                // Expanding Ripple Ring 3
                Circle()
                    .stroke(Color.white.opacity(isRippling ? 0.0 : 0.2), lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(isRippling ? 2.1 : 1.0)
                
                // Expanding Ripple Ring 2
                Circle()
                    .stroke(Color.white.opacity(isRippling ? 0.0 : 0.35), lineWidth: 1.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(isRippling ? 1.55 : 1.0)
                
                // Inner Glass Circle Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#7C5CFC").opacity(0.25), Color(hex: "#00D9A0").opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 130)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                        )
                        .shadow(color: Color(hex: "#7C5CFC").opacity(0.45), radius: 25)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.white.opacity(0.6), radius: 12)
                }
            }
            
            // Hero Typography
            VStack(spacing: 12) {
                Text("Sentuh Layar")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.white.opacity(0.3), radius: 20)
                
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#00D9A0"))
                    
                    Text("UNTUK MEMULAI SESI FOTO")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .tracking(6)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#00D9A0"))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                isRegistering = true
            }
        }
    }
    
    // MARK: - Full-Page Infinite Canvas Registration
    private var fullPageRegistrationCanvas: some View {
        VStack(spacing: 28) {
            // Title Header Canvas
            VStack(spacing: 8) {
                Text("Selamat Datang!")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color.white.opacity(0.2), radius: 15)
                
                Text("Masukkan nama & instagram kamu untuk memulai foto")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            
            // Form Inputs (Wide Canvas Fields)
            HStack(spacing: 24) {
                // Input Nama Panggilan
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nama Panggilan")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(activeField == .name ? Color(hex: "#00D9A0") : .white.opacity(0.55))
                    
                    HStack {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(activeField == .name ? Color(hex: "#00D9A0") : .white.opacity(0.35))
                        
                        Text(guestName.isEmpty ? "Cth: Budi" : guestName)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(guestName.isEmpty ? .white.opacity(0.35) : .white)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                activeField == .name ? Color(hex: "#00D9A0") : Color.white.opacity(0.15),
                                lineWidth: activeField == .name ? 2 : 1
                            )
                    )
                    .onTapGesture {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation { activeField = .name }
                    }
                }
                
                // Input Instagram Handle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instagram Handle (Opsional)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(activeField == .instagram ? Color(hex: "#7C5CFC") : .white.opacity(0.55))
                    
                    HStack {
                        Text("@")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(activeField == .instagram ? Color(hex: "#7C5CFC") : .white.opacity(0.35))
                        
                        Text(instagramHandle.isEmpty ? "username" : instagramHandle)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(instagramHandle.isEmpty ? .white.opacity(0.35) : .white)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                activeField == .instagram ? Color(hex: "#7C5CFC") : Color.white.opacity(0.15),
                                lineWidth: activeField == .instagram ? 2 : 1
                            )
                    )
                    .onTapGesture {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation { activeField = .instagram }
                    }
                }
            }
            .frame(maxWidth: 720)
            
            // Custom In-App Virtual Keyboard Dropdown
            CustomInAppKeyboard(
                text: Binding(
                    get: { activeField == .name ? guestName : instagramHandle },
                    set: { newValue in
                        if activeField == .name {
                            guestName = newValue
                        } else {
                            instagramHandle = newValue
                        }
                    }
                ),
                onDone: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            )
            .frame(maxWidth: 740)
            
            // Action Buttons (Kembali & Mulai Sesi Foto)
            HStack(spacing: 20) {
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        isRegistering = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Kembali")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.vertical, 16)
                    .padding(.horizontal, 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                
                Button(action: handleProceedToPhoto) {
                    HStack(spacing: 10) {
                        Text("Lanjutkan Ke Sesi Foto 📸")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 42)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#7C5CFC"), Color(hex: "#00D9A0")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#7C5CFC").opacity(0.45), radius: 20, y: 5)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }
    
    private func handleProceedToPhoto() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        let finalName = guestName.trimmingCharacters(in: .whitespaces).isEmpty ? "Tamu Haispace" : guestName.trimmingCharacters(in: .whitespaces)
        let finalIg = instagramHandle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : instagramHandle.trimmingCharacters(in: .whitespaces)
        
        // Simpan data tamu & navigasi ke paket / sesi foto
        withAnimation(.spring) {
            appState.navigateTo(.packageSelection)
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
                .fill(Color(hex: "#7C5CFC").opacity(0.18))
                .blur(radius: 110)
                .frame(width: 550, height: 550)
                .scaleEffect(isBreathe ? 1.15 : 0.85)
            
            Circle()
                .fill(Color(hex: "#00D9A0").opacity(0.12))
                .blur(radius: 120)
                .frame(width: 480, height: 480)
                .offset(x: isBreathe ? 160 : -160, y: isBreathe ? -110 : 110)
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

// MARK: - Logo Resmi Haispace Project (Glowing Spatial Prism Emblem + Text Header)
struct HaispaceOfficialLogoView: View {
    var body: some View {
        HStack(spacing: 14) {
            // Spatial Glowing Emblem
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#7C5CFC"), Color(hex: "#00D9A0")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: Color(hex: "#7C5CFC").opacity(0.6), radius: 15)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            // Brand Typography Stack
            VStack(alignment: .leading, spacing: -4) {
                Text("Haispace")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(hex: "#F1F5F9")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(hex: "#7C5CFC").opacity(0.5), radius: 15)
                
                Text("PROJECT")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Color(hex: "#00D9A0"))
                    .shadow(color: Color(hex: "#00D9A0").opacity(0.5), radius: 10)
            }
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

#Preview {
    LandingView()
        .environment(AppState.preview)
}
