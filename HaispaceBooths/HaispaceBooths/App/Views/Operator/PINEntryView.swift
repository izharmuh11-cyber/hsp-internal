// PINEntryView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar/popup transparan untuk input PIN Operator.
// Mencegah tamu masuk ke Mission Control.
//
// Ref: docs/design/30_authentication.md

import SwiftUI

struct PINEntryView: View {
    @Environment(AppState.self) private var appState
    
    @State private var pinInput: String = ""
    @State private var isError: Bool = false
    
    // Status apakah kita sedang mode "Set PIN" atau "Verify PIN"
    private var isSetupMode: Bool {
        !appState.operatorState.hasPINSet
    }
    
    let pinLength = 6 // Rekomendasi 6 digit
    
    var body: some View {
        ZStack {
            // Latar belakang sedikit gelap agar popup menonjol
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .blur(radius: 10)
            
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(isError ? .red : Color(hex: "#F5A623"))
                        .symbolEffect(.bounce, value: isError)
                    
                    Text(isSetupMode ? "Buat PIN Operator" : "Masukkan PIN Operator")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    Text(isSetupMode ? "PIN ini digunakan untuk membuka Mission Control" : "Akses terbatas Mission Control")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                // PIN Indicators (Titik-titik)
                HStack(spacing: 20) {
                    ForEach(0..<pinLength, id: \.self) { index in
                        Circle()
                            .fill(index < pinInput.count ? Color.white : Color.white.opacity(0.1))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pinInput.count)
                    }
                }
                .padding(.vertical, 20)
                .modifier(ShakeEffect(shakes: isError ? 2 : 0))
                
                // Numpad Custom
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                    ForEach(1...9, id: \.self) { number in
                        NumpadButton(text: "\(number)") {
                            appendNumber("\(number)")
                        }
                    }
                    
                    // Empty bottom left
                    Color.clear
                    
                    NumpadButton(text: "0") {
                        appendNumber("0")
                    }
                    
                    // Delete Button
                    Button(action: {
                        if !pinInput.isEmpty {
                            pinInput.removeLast()
                            isError = false
                        }
                    }) {
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 80, height: 80)
                    }
                }
                .frame(width: 320)
                
                // Cancel / Logout
                Button(action: {
                    withAnimation {
                        appState.operatorState.dismissMissionControl()
                    }
                }) {
                    Text("Batal")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 20)
                }
            }
            .padding(40)
            .background(Color(white: 1.0, opacity: 0.05))
            .cornerRadius(32)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Logic
    
    private func appendNumber(_ num: String) {
        guard pinInput.count < pinLength else { return }
        pinInput.append(num)
        isError = false
        
        if pinInput.count == pinLength {
            verifyPIN()
        }
    }
    
    private func verifyPIN() {
        if isSetupMode {
            // Setup PIN Baru
            let success = appState.operatorState.setupPIN(pinInput)
            if success {
                withAnimation {
                    // Masuk langsung ke mission control
                    appState.operatorState.requestMissionControl()
                }
            } else {
                triggerError()
            }
        } else {
            // Verifikasi
            let isValid = appState.operatorState.verifyPIN(pinInput)
            if isValid {
                // Mission control overlay akan tampil otomatis (isMissionControlVisible = true)
                pinInput = ""
            } else {
                triggerError()
            }
        }
    }
    
    private func triggerError() {
        withAnimation {
            isError = true
        }
        // Haptic feedback (UINotificationFeedbackGenerator)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pinInput = ""
        }
    }
}

// MARK: - Subviews & Modifiers

private struct NumpadButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 36, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
    }
}

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat
    
    init(shakes: Int) {
        animatableData = CGFloat(shakes)
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = amount * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

#Preview {
    PINEntryView()
        .environment(AppState.preview)
}
