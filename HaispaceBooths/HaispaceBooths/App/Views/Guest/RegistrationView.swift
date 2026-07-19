// RegistrationView.swift
// HaispaceBooths — App/Views/Guest
//
// Form pendaftaran nama dan instagram tamu bertema VisionOS Liquid Glass & Cinematic Dark.

import SwiftUI

struct RegistrationView: View {
    @Environment(AppState.self) private var appState
    
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
            
            // 2. Ambient Light Orbs
            ZStack {
                Circle()
                    .fill(Color(hex: "#7C5CFC").opacity(0.18))
                    .blur(radius: 120)
                    .frame(width: 550, height: 550)
                
                Circle()
                    .fill(Color(hex: "#00D9A0").opacity(0.12))
                    .blur(radius: 130)
                    .frame(width: 480, height: 480)
                    .offset(x: 200, y: -150)
            }
            .allowsHitTesting(false)
            
            // 3. MAIN CONTENT LAYOUT
            VStack(spacing: 24) {
                // TOP HEADER: Back Button & Haispace Project Logo
                HStack {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            appState.navigateTo(.landing)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                            Text("Kembali")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    
                    Spacer()
                    
                    HaispaceOfficialLogoView()
                    
                    Spacer()
                    
                    // Balancing Spacer Placeholder
                    Color.clear.frame(width: 100, height: 40)
                }
                .padding(.horizontal, 36)
                .padding(.top, 28)
                
                Spacer()
                
                // GLASS REGISTRATION CARD
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("Siapa Namamu?")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Isi nama & instagram kamu untuk memulai foto")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    // INPUT FIELDS
                    HStack(spacing: 20) {
                        // Input Nama
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nama Panggilan")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(activeField == .name ? Color(hex: "#00D9A0") : .white.opacity(0.5))
                            
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(activeField == .name ? Color(hex: "#00D9A0") : .white.opacity(0.3))
                                
                                Text(guestName.isEmpty ? "Cth: Budi" : guestName)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(guestName.isEmpty ? .white.opacity(0.3) : .white)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(activeField == .name ? Color(hex: "#00D9A0") : Color.white.opacity(0.12), lineWidth: activeField == .name ? 2 : 1)
                            )
                            .onTapGesture {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation { activeField = .name }
                            }
                        }
                        
                        // Input Instagram
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instagram (Opsional)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(activeField == .instagram ? Color(hex: "#7C5CFC") : .white.opacity(0.5))
                            
                            HStack {
                                Text("@")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(activeField == .instagram ? Color(hex: "#7C5CFC") : .white.opacity(0.3))
                                
                                Text(instagramHandle.isEmpty ? "username" : instagramHandle)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(instagramHandle.isEmpty ? .white.opacity(0.3) : .white)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(activeField == .instagram ? Color(hex: "#7C5CFC") : Color.white.opacity(0.12), lineWidth: activeField == .instagram ? 2 : 1)
                            )
                            .onTapGesture {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                withAnimation { activeField = .instagram }
                            }
                        }
                    }
                    .frame(width: 580)
                    
                    // CUSTOM IN-APP KEYBOARD
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
                    .frame(width: 640)
                    
                    // ACTION BUTTON
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            Text("Lanjutkan Ke Sesi Foto 📸")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 15)
                        .padding(.horizontal, 42)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#7C5CFC"), Color(hex: "#00D9A0")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "#7C5CFC").opacity(0.4), radius: 18)
                    }
                    .padding(.top, 4)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.black.opacity(0.5), radius: 30, y: 15)
                
                Spacer()
            }
        }
    }
    
    private func submit() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        let finalName = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.pendingGuest = GuestInfo(
            name: finalName.isEmpty ? "Guest" : finalName,
            instagram: instagramHandle.isEmpty ? nil : instagramHandle,
            phoneNumber: nil,
            queueNumber: Int.random(in: 100...999)
        )
        
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            appState.navigateTo(.packageSelection)
        }
    }
}

#Preview {
    RegistrationView()
        .environment(AppState.preview)
}
