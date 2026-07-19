// OperatorLoginView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Login Operator bertema Light Glass & Clean Apple UI.
// Dilengkapi In-App Keyboard internal dan tipografi kontras tinggi.

import SwiftUI

enum LoginField {
    case username
    case password
}

struct OperatorLoginView: View {
    @Environment(AppState.self) private var appState
    
    @State private var emailInput: String = "123"
    @State private var passwordInput: String = "123"
    @State private var activeField: LoginField? = nil
    @State private var isPasswordVisible: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            // Background Gradasi Pastel / Warm Glass
            LinearGradient(
                colors: [Color(hex: "#F8FAFC"), Color(hex: "#EEF2FF"), Color(hex: "#E0E7FF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    activeField = nil
                }
            }
            
            // Soft ambient light aura
            Circle()
                .fill(Color(hex: "#C7D2FE").opacity(0.5))
                .blur(radius: 90)
                .frame(width: 500, height: 500)
                .offset(x: -200, y: -200)
            
            Circle()
                .fill(Color(hex: "#A7F3D0").opacity(0.4))
                .blur(radius: 90)
                .frame(width: 450, height: 450)
                .offset(x: 200, y: 200)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer().frame(height: 20)
                    
                    // Header Branding
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 88, height: 88)
                                .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
                            
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 46, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#4F46E5"), Color(hex: "#10B981")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text("H A I S P A C E")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .tracking(6)
                            .foregroundStyle(Color(hex: "#0F172A"))
                        
                        Text("OPERATOR COMMAND STUDIO")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#4F46E5"))
                            .tracking(3)
                    }
                    
                    // Login Card (Floating Glass)
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LOGIN OPERATOR")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#4F46E5"))
                                .tracking(2)
                            
                            Text("Masukkan akun untuk membuka booth")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "#475569"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(spacing: 16) {
                            // Username Input Card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("USERNAME / ID OPERATOR")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(activeField == .username ? Color(hex: "#4F46E5") : Color(hex: "#475569"))
                                    .tracking(1)
                                
                                Button(action: {
                                    playHaptic(style: .light)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        activeField = .username
                                    }
                                }) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(activeField == .username ? Color(hex: "#4F46E5") : Color(hex: "#64748B"))
                                            .frame(width: 20)
                                        
                                        Text(emailInput.isEmpty ? "Masukkan Username / ID" : emailInput)
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundStyle(emailInput.isEmpty ? Color(hex: "#94A3B8") : Color(hex: "#0F172A"))
                                        
                                        Spacer()
                                        
                                        if !emailInput.isEmpty {
                                            Button(action: { emailInput = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(Color(hex: "#94A3B8"))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(activeField == .username ? Color(hex: "#4F46E5") : Color(hex: "#CBD5E1"), lineWidth: activeField == .username ? 2.5 : 1)
                                    )
                                    .shadow(color: activeField == .username ? Color(hex: "#4F46E5").opacity(0.12) : Color.black.opacity(0.03), radius: 8, y: 3)
                                }
                                .buttonStyle(BentoButtonStyle())
                                
                                // Inline In-App Keyboard Dropdown for Username
                                if activeField == .username {
                                    CustomInAppKeyboard(
                                        text: $emailInput,
                                        onDone: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                activeField = .password
                                            }
                                        }
                                    )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .padding(.top, 4)
                                }
                            }
                            
                            // Password Input Card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PASSWORD OPERATOR")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(activeField == .password ? Color(hex: "#4F46E5") : Color(hex: "#475569"))
                                    .tracking(1)
                                
                                Button(action: {
                                    playHaptic(style: .light)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        activeField = .password
                                    }
                                }) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(activeField == .password ? Color(hex: "#4F46E5") : Color(hex: "#64748B"))
                                            .frame(width: 20)
                                        
                                        if isPasswordVisible {
                                            Text(passwordInput.isEmpty ? "Masukkan Password" : passwordInput)
                                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                                .foregroundStyle(passwordInput.isEmpty ? Color(hex: "#94A3B8") : Color(hex: "#0F172A"))
                                        } else {
                                            Text(passwordInput.isEmpty ? "Masukkan Password" : String(repeating: "•", count: passwordInput.count))
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                                .foregroundStyle(passwordInput.isEmpty ? Color(hex: "#94A3B8") : Color(hex: "#0F172A"))
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            isPasswordVisible.toggle()
                                        }) {
                                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(Color(hex: "#64748B"))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(activeField == .password ? Color(hex: "#4F46E5") : Color(hex: "#CBD5E1"), lineWidth: activeField == .password ? 2.5 : 1)
                                    )
                                    .shadow(color: activeField == .password ? Color(hex: "#4F46E5").opacity(0.12) : Color.black.opacity(0.03), radius: 8, y: 3)
                                }
                                .buttonStyle(BentoButtonStyle())
                                
                                // Inline In-App Keyboard Dropdown for Password
                                if activeField == .password {
                                    CustomInAppKeyboard(
                                        text: $passwordInput,
                                        onDone: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                activeField = nil
                                                handleLogin()
                                            }
                                        }
                                    )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .padding(.top, 4)
                                }
                            }
                        }
                        
                        if let err = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(err)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        
                        // Login Button
                        Button(action: {
                            playHaptic(style: .heavy)
                            activeField = nil
                            handleLogin()
                        }) {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Masuk ke Dashboard")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 20, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#4F46E5"), Color(hex: "#3730A3")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(color: Color(hex: "#4F46E5").opacity(0.35), radius: 15, y: 8)
                        }
                        .buttonStyle(BentoButtonStyle())
                        .disabled(isLoading)
                        
                        // Quick dev credentials helper
                        HStack(spacing: 6) {
                            Text("Kredensial Uji Coba:")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "#64748B"))
                            Text("User: 123  •  Pass: 123")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#4F46E5"))
                        }
                        .padding(.top, 2)
                    }
                    .padding(32)
                    .frame(width: 480)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color.white.opacity(0.92))
                            .shadow(color: Color.black.opacity(0.08), radius: 30, y: 15)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.white, lineWidth: 2)
                    )
                    
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private func handleLogin() {
        guard !emailInput.isEmpty && !passwordInput.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let user = try await AuthService.shared.login(email: emailInput, password: passwordInput)
                await MainActor.run {
                    appState.operatorState.currentOperator = user
                    appState.auth.currentUser = user
                    appState.auth.authStatus = .authenticated
                    appState.boothConfig.setActiveEvent(id: "dummy", name: "Dummy Event", date: Date(), venue: "Dummy Venue")
                    appState.boothConfig.activePackages = [
                        BoothPackage(id: "dummy", name: "Dummy Package", price: 50000, durationSeconds: 300, maxPhotoCount: 10, minPhotoCount: 2, intervalSeconds: 5, description: "Dummy", isPopular: true, includedAddonIds: [])
                    ]
                    appState.isAppReady = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Login gagal. Periksa username (123) & password (123)."
                }
            }
        }
    }
}

#Preview {
    OperatorLoginView()
        .environment(AppState.preview)
}
