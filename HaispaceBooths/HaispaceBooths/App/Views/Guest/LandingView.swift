// LandingView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar standby awal (idle). Menampilkan branding Haispace dan instruksi tap.
// Menggunakan desain "Cinematic Luxury Dark".

import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isPulsing = false
    @State private var gradientRotation: Double = 0
    
    var body: some View {
        ZStack {
            // Background Terdalam
            Color(hex: "#080810").ignoresSafeArea()
            
            // Aurora / Gradient Mesh Animation
            AngularGradient(
                gradient: Gradient(colors: [Color(hex: "#F5A623"), Color(hex: "#7C5CFC"), Color(hex: "#4F46E5"), Color(hex: "#F5A623")]),
                center: .center,
                angle: .degrees(gradientRotation)
            )
            .opacity(0.15)
            .blur(radius: 80)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    gradientRotation = 360
                }
            }
            
            VStack(spacing: 60) {
                Spacer()
                
                // Branding Header
                VStack(spacing: 16) {
                    Text("H A I S P A C E")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .shadow(color: Color(hex: "#7C5CFC").opacity(0.5), radius: 20, x: 0, y: 0)
                    
                    Text("The Premium Photobooth Experience")
                        .font(.system(size: 20, weight: .regular, design: .default))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(2)
                }
                
                Spacer()
                
                // Call to Action
                if appState.p2p.isConnected {
                    Button(action: {
                        withAnimation(.spring) {
                            appState.navigateTo(.guestRegistration)
                        }
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 32))
                            
                            Text("Sentuh untuk Mulai")
                                .font(.system(size: 24, weight: .bold))
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 48)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color(white: 1.0, opacity: 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 30)
                                .stroke(
                                    LinearGradient(colors: [Color(hex: "#F5A623"), Color(hex: "#7C5CFC")], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 2
                                )
                                .opacity(isPulsing ? 1.0 : 0.3)
                        )
                        .foregroundColor(.white)
                        .shadow(color: Color(hex: "#7C5CFC").opacity(isPulsing ? 0.6 : 0.2), radius: isPulsing ? 20 : 10)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                } else {
                    Button(action: {
                        appState.operatorState.isPairingSetupVisible = true
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(.system(size: 32))
                            
                            Text("Hubungkan Kamera")
                                .font(.system(size: 24, weight: .bold))
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 48)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.orange.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 30)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                        .foregroundColor(.orange)
                        .shadow(color: Color.orange.opacity(0.4), radius: 15)
                    }
                    .transition(.scale)
                }
                
                Spacer().frame(height: 40)
                
                // Status Indikator (untuk operator)
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.p2p.connectionState == .connected ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(appState.p2p.connectionState == .connected ? "Kamera Siap" : "Menunggu Kamera...")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 20)
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
