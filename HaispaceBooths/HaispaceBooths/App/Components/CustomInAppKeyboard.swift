// CustomInAppKeyboard.swift
// HaispaceBooths — App/Components
//
// Keypad & Keyboard sentuh internal berbasis Liquid Glass & Haptic Feedback.
// Ergonomis: Layout QWERTY standar dengan Spasi di tengah bawah, Backspace di kanan atas/row 3,
// serta toggle mode angka (123).

import SwiftUI

enum KeyboardMode {
    case qwerty
    case numeric
}

struct CustomInAppKeyboard: View {
    @Binding var text: String
    var onDone: (() -> Void)? = nil
    
    @State private var isUppercase: Bool = true
    @State private var mode: KeyboardMode = .qwerty
    
    private let qwertyRow1 = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
    private let qwertyRow2 = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
    private let qwertyRow3 = ["Z", "X", "C", "V", "B", "N", "M"]
    
    var body: some View {
        VStack(spacing: 8) {
            if mode == .qwerty {
                qwertyView
            } else {
                numericView
            }
        }
        .padding(14)
        .background(Color(hex: "#F1F5F9").opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(hex: "#CBD5E1"), lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
    }
    
    // MARK: - QWERTY Layout
    private var qwertyView: some View {
        VStack(spacing: 8) {
            // Row 1
            HStack(spacing: 6) {
                ForEach(qwertyRow1, id: \.self) { char in
                    let letter = isUppercase ? char : char.lowercased()
                    keyButton(letter) { appendChar(letter) }
                }
            }
            
            // Row 2
            HStack(spacing: 6) {
                Spacer().frame(width: 12)
                ForEach(qwertyRow2, id: \.self) { char in
                    let letter = isUppercase ? char : char.lowercased()
                    keyButton(letter) { appendChar(letter) }
                }
                Spacer().frame(width: 12)
            }
            
            // Row 3 (Shift - Keys - Backspace)
            HStack(spacing: 6) {
                // Shift Key
                Button(action: {
                    playHaptic(style: .light)
                    isUppercase.toggle()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isUppercase ? Color(hex: "#4F46E5") : Color.white)
                            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1.5)
                        
                        Image(systemName: isUppercase ? "shift.fill" : "shift")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isUppercase ? .white : Color(hex: "#475569"))
                    }
                    .frame(width: 52, height: 46)
                }
                .buttonStyle(BentoButtonStyle())
                
                ForEach(qwertyRow3, id: \.self) { char in
                    let letter = isUppercase ? char : char.lowercased()
                    keyButton(letter) { appendChar(letter) }
                }
                
                // Backspace Key (Right Side)
                Button(action: backspace) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#E2E8F0"))
                            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1.5)
                        
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                    .frame(width: 56, height: 46)
                }
                .buttonStyle(BentoButtonStyle())
            }
            
            // Row 4 (Mode Toggle - Space - Done/Hide)
            HStack(spacing: 8) {
                // Mode Toggle Button (123)
                Button(action: {
                    playHaptic(style: .light)
                    mode = .numeric
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#E2E8F0"))
                        
                        Text("123")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                    .frame(width: 64, height: 46)
                }
                .buttonStyle(BentoButtonStyle())
                
                // Centered Space Key
                Button(action: { appendChar(" ") }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1.5)
                        
                        Text("spasi")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: "#64748B"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(BentoButtonStyle())
                
                // Done / Hide Key
                Button(action: {
                    playHaptic(style: .medium)
                    onDone?()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#0F172A"))
                        
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(width: 64, height: 46)
                }
                .buttonStyle(BentoButtonStyle())
            }
        }
    }
    
    // MARK: - Numeric Layout
    private var numericView: some View {
        VStack(spacing: 8) {
            let numRows = [
                ["1", "2", "3"],
                ["4", "5", "6"],
                ["7", "8", "9"]
            ]
            
            ForEach(numRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { num in
                        keyButton(num) { appendChar(num) }
                    }
                }
            }
            
            HStack(spacing: 8) {
                // Return to ABC
                Button(action: {
                    playHaptic(style: .light)
                    mode = .qwerty
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#E2E8F0"))
                        
                        Text("ABC")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                    .frame(height: 46)
                }
                .buttonStyle(BentoButtonStyle())
                
                keyButton("0") { appendChar("0") }
                
                // Backspace
                Button(action: backspace) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#E2E8F0"))
                        
                        Image(systemName: "delete.left.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                    .frame(height: 46)
                }
                .buttonStyle(BentoButtonStyle())
            }
            
            // Done Button
            Button(action: {
                playHaptic(style: .medium)
                onDone?()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Selesai")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: "#0F172A"))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(BentoButtonStyle())
            .padding(.top, 2)
        }
    }
    
    private func keyButton(_ char: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            playHaptic(style: .light)
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1.5)
                
                Text(char)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
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
