// RegistrationView.swift
// HaispaceBooths — App/Views/Guest
//
// Form pendaftaran nama dan instagram tamu.
// Dilengkapi dengan custom virtual keyboard besar.

import SwiftUI

struct RegistrationView: View {
    @Environment(AppState.self) private var appState
    
    @State private var guestName: String = ""
    @State private var instagramHandle: String = ""
    @State private var isNameFocused: Bool = true
    
    // Custom Keyboard State
    private let keyboardRows = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    
    var body: some View {
        ZStack {
            Color(hex: "#080810").ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation { appState.navigateTo(.landing) }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    
                    Spacer()
                    
                    Text("Siapa namamu?")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    // Invisible view for symmetry
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 56, height: 56)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                
                // Form Fields
                HStack(spacing: 32) {
                    // Name Field
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nama Panggilan")
                            .font(.callout)
                            .foregroundStyle(isNameFocused ? Color(hex: "#F5A623") : .white.opacity(0.5))
                        
                        Text(guestName.isEmpty ? "Cth: Budi" : guestName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(guestName.isEmpty ? .white.opacity(0.2) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 24)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isNameFocused ? Color(hex: "#F5A623") : Color.white.opacity(0.1), lineWidth: 2)
                            )
                            .onTapGesture {
                                isNameFocused = true
                            }
                    }
                    
                    // Instagram Field
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instagram (Opsional)")
                            .font(.callout)
                            .foregroundStyle(!isNameFocused ? Color(hex: "#7C5CFC") : .white.opacity(0.5))
                        
                        HStack {
                            Text("@")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.3))
                            
                            Text(instagramHandle.isEmpty ? "username" : instagramHandle)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(instagramHandle.isEmpty ? .white.opacity(0.2) : .white)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(!isNameFocused ? Color(hex: "#7C5CFC") : Color.white.opacity(0.1), lineWidth: 2)
                        )
                        .onTapGesture {
                            isNameFocused = false
                        }
                    }
                }
                .padding(.horizontal, 60)
                
                Spacer()
                
                // Custom Virtual Keyboard
                VStack(spacing: 12) {
                    ForEach(keyboardRows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 12) {
                            ForEach(keyboardRows[rowIndex], id: \.self) { key in
                                KeyboardButton(text: key) {
                                    type(key)
                                }
                            }
                            
                            if rowIndex == 2 {
                                // Delete button at the end of bottom row
                                KeyboardButton(text: "⌫", width: 80, isSpecial: true) {
                                    delete()
                                }
                            }
                        }
                    }
                    
                    // Space and Next
                    HStack(spacing: 12) {
                        if !isNameFocused {
                            KeyboardButton(text: "_", width: 60) { type("_") }
                            KeyboardButton(text: ".", width: 60) { type(".") }
                        }
                        
                        KeyboardButton(text: "SPASI", width: 400) {
                            type(" ")
                        }
                        
                        Button(action: {
                            submit()
                        }) {
                            Text(guestName.isEmpty ? "Lewati" : "Lanjut →")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 160, height: 65)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(LinearGradient(colors: [Color(hex: "#F5A623"), Color(hex: "#E8721A")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: Color(hex: "#F5A623").opacity(0.4), radius: 10)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private func type(_ char: String) {
        if isNameFocused {
            if guestName.count < 20 { guestName += char }
        } else {
            if instagramHandle.count < 30 { instagramHandle += char.lowercased() }
        }
    }
    
    private func delete() {
        if isNameFocused {
            if !guestName.isEmpty { guestName.removeLast() }
        } else {
            if !instagramHandle.isEmpty { instagramHandle.removeLast() }
        }
    }
    
    private func submit() {
        let finalName = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.pendingGuest = GuestInfo(
            name: finalName.isEmpty ? "Guest" : finalName,
            instagram: instagramHandle.isEmpty ? nil : instagramHandle,
            phoneNumber: nil,
            queueNumber: Int.random(in: 100...999)
        )
        
        withAnimation(.spring) {
            appState.navigateTo(.packageSelection)
        }
    }
}

// MARK: - Keyboard Button

private struct KeyboardButton: View {
    let text: String
    var width: CGFloat = 65
    var isSpecial: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 24, weight: isSpecial ? .semibold : .medium))
                .foregroundStyle(.white)
                .frame(width: width, height: 65)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(isSpecial ? 0.2 : 0.1))
                )
        }
        // Minimalize visual feedback for fast typing
        .buttonStyle(.plain)
    }
}

#Preview {
    RegistrationView()
        .environment(AppState.preview)
}
