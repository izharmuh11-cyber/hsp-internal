// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar standby awal (idle). Menampilkan branding Haispace dan instruksi tap.
// Menggunakan desain "Cinematic Luxury Dark" dengan standar visual premium Apple.

import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isAnimating = false
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Background Terdalam
            Color(hex: "#05050C").ignoresSafeArea()
            
            // Premium Moving Ambient Glows (Apple TV Style)
            Circle()
                .fill(Color(hex: "#7C5CFC").opacity(0.18))
                .blur(radius: 90)
                .frame(width: 450, height: 450)
                .offset(x: isAnimating ? 250 : -250, y: isAnimating ? -200 : 200)
            
            Circle()
                .fill(Color(hex: "#00D9A0").opacity(0.12))
                .blur(radius: 95)
                .frame(width: 350, height: 350)
                .offset(x: isAnimating ? -250 : 250, y: isAnimating ? 200 : -200)
            
            Circle()
                .fill(Color(hex: "#4F46E5").opacity(0.15))
                .blur(radius: 80)
                .frame(width: 400, height: 400)
                .offset(x: isAnimating ? 150 : -150, y: isAnimating ? 150 : -150)
            
            VStack(spacing: 50) {
                Spacer()
                
                // Branding Header
                VStack(spacing: 20) {
                    if let event = appState.operatorState.activeEvent {
                        HStack(spacing: 12) {
                            Text("HAISPACE")
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .tracking(6)
                                .foregroundStyle(.white)
                            
                            Text("×")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(Color(hex: "#7C5CFC"))
                            
                            Text(event.name.uppercased())
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .tracking(4)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#7C5CFC"), Color(hex: "#00D9A0")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .shadow(color: Color(hex: "#7C5CFC").opacity(0.4), radius: 30)
                        
                        Text("\(event.location) • \(event.isPayPerSession ? "Rp \(Int(event.pricePerSession).formatted()) / Sesi" : "Free Event")")
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(.white.opacity(0.7))
                            .tracking(2)
                    } else {
                        Text("H A I S P A C E")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .tracking(10)
                            .foregroundStyle(.white)
                            .shadow(color: Color(hex: "#7C5CFC").opacity(0.4), radius: 30)
                        
                        Text("The Premium Photobooth Experience")
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundStyle(.white.opacity(0.5))
                            .tracking(4)
                    }
                }
                
                Spacer()
                
                // Call to Action (Glassmorphism Buttons)
                if appState.p2p.isConnected {
                    Button(action: {
                        withAnimation(.spring) {
                            appState.navigateTo(.guestRegistration)
                        }
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(LinearGradient(colors: [Color(hex: "#7C5CFC"), Color(hex: "#00D9A0")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            
                            Text("Sentuh untuk Mulai")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 28)
                        .padding(.horizontal, 64)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color(hex: "#7C5CFC").opacity(isPulsing ? 0.35 : 0.15), radius: isPulsing ? 25 : 15, y: 10)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                } else {
                    Button(action: {
                        appState.operatorState.isPairingSetupVisible = true
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.orange)
                            
                            Text("Hubungkan Kamera")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 28)
                        .padding(.horizontal, 64)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [Color.orange.opacity(0.4), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.orange.opacity(0.2), radius: 20, y: 10)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                // Status Indikator (Dynamic Island style pill at the bottom)
                HStack(spacing: 10) {
                    Circle()
                        .fill(appState.p2p.connectionState == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: appState.p2p.connectionState == .connected ? Color.green : Color.orange, radius: 4)
                    
                    Text(appState.p2p.connectionState == .connected ? "Kamera Terhubung" : "Menunggu Sambungan Kamera")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
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
            (a, r, g, b) = (1, 1, 1, 0)
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
