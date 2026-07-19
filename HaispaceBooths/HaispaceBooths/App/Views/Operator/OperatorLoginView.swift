// OperatorLoginView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Login Operator bertema Light Glass & Clean Apple UI.
// Memungkinkan operator masuk menggunakan Username & Password.
// Pre-filled dengan kredensial uji coba (User: 123, Pass: 123) untuk mempercepat dev.

import SwiftUI

struct OperatorLoginView: View {
    @Environment(AppState.self) private var appState
    
    @State private var emailInput: String = "123"
    @State private var passwordInput: String = "123"
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
            
            VStack(spacing: 36) {
                // Header Branding
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 88, height: 88)
                            .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
                        
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#4F46E5"), Color(hex: "#10B981")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("H A I S P A C E")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(Color(hex: "#0F172A"))
                    
                    Text("Operator Command Studio")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "#64748B"))
                        .tracking(2)
                }
                
                // Login Card (Floating Glass)
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOGIN OPERATOR")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "#475569"))
                            .tracking(1.5)
                        
                        Text("Masukkan akun untuk membuka booth")
                            .font(.subheadline)
                            .foregroundStyle(Color(hex: "#64748B"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 16) {
                        // Username Field
                        HStack(spacing: 14) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color(hex: "#6366F1"))
                                .frame(width: 20)
                            
                            TextField("Username / ID", text: $emailInput)
                                .textInputAutocapitalization(.none)
                                .autocorrectionDisabled()
                                .font(.system(size: 16, weight: .medium))
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                        
                        // Password Field
                        HStack(spacing: 14) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Color(hex: "#6366F1"))
                                .frame(width: 20)
                            
                            SecureField("Password", text: $passwordInput)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                    }
                    
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Login Button
                    Button(action: handleLogin) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Masuk ke Dashboard")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#4F46E5"), Color(hex: "#6366F1")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "#4F46E5").opacity(0.3), radius: 15, y: 8)
                    }
                    .disabled(isLoading)
                    
                    // Quick dev credentials helper
                    HStack(spacing: 4) {
                        Text("Dev Test Credentials:")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#94A3B8"))
                        Text("User 123 • Pass 123")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "#6366F1"))
                    }
                    .padding(.top, 4)
                }
                .padding(32)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                        .shadow(color: Color.black.opacity(0.08), radius: 30, y: 15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white, lineWidth: 1.5)
                )
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
                    appState.boothConfig.isConfigured = true // Bypass initial booth config placeholder
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
