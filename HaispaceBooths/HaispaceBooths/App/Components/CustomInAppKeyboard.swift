// CustomInAppKeyboard.swift
// HaispaceBooths — App/Components
//
// Keypad & Keyboard sentuh internal berbasis Liquid Glass & Haptic Feedback.
// Menghindari virtual keyboard bawaan iOS yang menutupi antarmuka aplikasi.

import SwiftUI

struct CustomInAppKeyboard: View {
    @Binding var text: String
    var onDone: (() -> Void)? = nil
    
    private let row1 = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
    private let row2 = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
    private let row3 = ["Z", "X", "C", "V", "B", "N", "M"]
    
    var body: some View {
        VStack(spacing: 10) {
            // Row 1
            HStack(spacing: 6) {
                ForEach(row1, id: \.self) { char in
                    keyButton(char) { appendChar(char) }
                }
            }
            
            // Row 2
            HStack(spacing: 6) {
                Spacer().frame(width: 14)
                ForEach(row2, id: \.self) { char in
                    keyButton(char) { appendChar(char) }
                }
                Spacer().frame(width: 14)
            }
            
            // Row 3
            HStack(spacing: 8) {
                // Backspace Key
                Button(action: backspace) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                            .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                        
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color(hex: "#64748B"))
                    }
                    .frame(height: 48)
                }
                .buttonStyle(BentoButtonStyle())
                
                ForEach(row3, id: \.self) { char in
                    keyButton(char) { appendChar(char) }
                }
                
                // Space Key
                Button(action: { appendChar(" ") }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                            .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                        
                        Text("Spasi")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#475569"))
                    }
                    .frame(height: 48)
                }
                .buttonStyle(BentoButtonStyle())
            }
            
            // Row 4 (Done / Submit)
            if let onDone = onDone {
                Button(action: {
                    playHaptic(style: .medium)
                    onDone()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Selesai Ketik")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: "#0F172A"))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color(hex: "#0F172A").opacity(0.2), radius: 6, y: 3)
                }
                .buttonStyle(BentoButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(hex: "#F1F5F9").opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1.5))
    }
    
    private func keyButton(_ char: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            playHaptic(style: .light)
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                
                Text(char)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
            }
            .frame(height: 48)
        }
        .buttonStyle(BentoButtonStyle())
    }
    
    private func appendChar(_ char: String) {
        text.append(char)
    }
    
    private func backspace() {
        playHaptic(style: .light)
        if !text.isEmpty {
            text.removeLast()
        }
    }
}
