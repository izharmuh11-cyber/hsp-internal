// PairingSetupView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Setup P2P Pairing untuk memindai QR Code dari iPhone.
// Menampilkan QR Code dinamis dan countdown timer regenerasi.

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    // Timer state untuk visualisasi (max 5 menit / 300 detik)
    // Di P2PStore regenerasi di set ke 290 detik
    @State private var remainingSeconds: Int = 290
    @State private var timer: Timer?
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // 1. Premium Animated Background
            Color(hex: "#05050A").ignoresSafeArea()
            
            // Subtle ambient glows
            Circle()
                .fill(Color.blue.opacity(0.15))
                .blur(radius: 120)
                .frame(width: 500, height: 500)
                .offset(x: isAnimating ? 200 : -200, y: isAnimating ? -200 : 200)
            
            Circle()
                .fill(Color.purple.opacity(0.15))
                .blur(radius: 120)
                .frame(width: 400, height: 400)
                .offset(x: isAnimating ? -300 : 300, y: isAnimating ? 300 : -300)
            
            VStack(spacing: 50) {
                // Header
                VStack(spacing: 16) {
                    Text("Hubungkan Kamera")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .white.opacity(0.1), radius: 10, y: 5)
                    
                    Text("Arahkan HaiCamera ke kode di bawah ini untuk memulai.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 60)
                
                // QR Code / Success Container
                ZStack {
                    // Glassmorphism Card
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 440, height: 520)
                        .shadow(color: appState.p2p.isConnected ? Color.green.opacity(0.3) : Color.black.opacity(0.5), radius: 40, y: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 48, style: .continuous)
                                .stroke(LinearGradient(
                                    colors: [.white.opacity(0.2), .white.opacity(0.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), lineWidth: 1)
                        )
                    
                    VStack(spacing: 32) {
                        if appState.p2p.isConnected {
                            // Connected State
                            VStack(spacing: 24) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.1))
                                        .frame(width: 160, height: 160)
                                    
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 64, weight: .bold))
                                        .foregroundStyle(.green)
                                }
                                .scaleEffect(appState.p2p.isConnected ? 1 : 0.5)
                                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: appState.p2p.isConnected)
                                
                                VStack(spacing: 8) {
                                    Text("Berhasil Terhubung")
                                        .font(.title.bold())
                                        .foregroundStyle(.primary)
                                    
                                    if let name = appState.p2p.connectedPeerName {
                                        Text(name)
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                            
                        } else {
                            // Scanning State
                            VStack(spacing: 32) {
                                if let payload = appState.p2p.currentQRPayload,
                                   let qrImage = generateQRCode(from: payload) {
                                    
                                    ZStack {
                                        // Pulse rings
                                        Circle()
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                            .frame(width: 320, height: 320)
                                            .scaleEffect(isAnimating ? 1.2 : 0.8)
                                            .opacity(isAnimating ? 0 : 1)
                                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: isAnimating)
                                        
                                        Image(uiImage: qrImage)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 260, height: 260)
                                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                                    }
                                    .id(payload.ts)
                                    .transition(.opacity.animation(.easeInOut))
                                    
                                } else {
                                    ProgressView()
                                        .controlSize(.large)
                                        .tint(.white)
                                        .frame(width: 260, height: 260)
                                }
                                
                                // Beautiful Timer Pill
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.subheadline.weight(.semibold))
                                    Text(formatTime(remainingSeconds))
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                }
                                .foregroundStyle(remainingSeconds < 30 ? Color.red : Color.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.systemBackground).opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Status Bar & Action
                VStack(spacing: 24) {
                    // Status Badge
                    HStack(spacing: 12) {
                        Circle()
                            .fill(appState.p2p.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                            .shadow(color: appState.p2p.isConnected ? Color.green : Color.orange, radius: 4)
                        
                        Text(appState.p2p.connectionState.displayText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    
                    // Buttons
                    HStack(spacing: 20) {
                        Button(action: { dismiss() }) {
                            Text("Batal")
                                .font(.title3.weight(.semibold))
                                .frame(width: 180, height: 56)
                                .foregroundStyle(.white)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                        
                        Button(action: { dismiss() }) {
                            Text("Selesai")
                                .font(.title3.weight(.semibold))
                                .frame(width: 180, height: 56)
                                .foregroundStyle(appState.p2p.isConnected ? .black : .white.opacity(0.3))
                                .background(appState.p2p.isConnected ? Color(hex: "#00D9A0") : Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .disabled(!appState.p2p.isConnected)
                        .animation(.easeInOut, value: appState.p2p.isConnected)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            isAnimating = true
            setupQRGeneration()
        }
        .onDisappear {
            teardownQRGeneration()
        }
        // Dengarkan perubahan Payload TS untuk mereset timer UI
        .onChange(of: appState.p2p.currentQRPayload?.ts) { _, _ in
            remainingSeconds = 290
        }
    }
    
    // MARK: - Logika Lifecycle
    
    private func setupQRGeneration() {
        // Buat dummy eventId jika tidak ada session, atau gunakan ID session aktif
        let eventId = appState.currentSession?.sessionId ?? "TEST-EVENT-\(Int.random(in: 1000...9999))"
        // Ambil Local IP iPad. (Dalam environment riil, gunakan logic get IP, di sini fallback dummy / 0.0.0.0)
        let localIp = "0.0.0.0"
        let randomPort = Int.random(in: 50000...60000)
        
        appState.p2p.startGeneratingQRPayload(eventId: eventId, ip: localIp, port: randomPort)
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            }
        }
    }
    
    private func teardownQRGeneration() {
        timer?.invalidate()
        timer = nil
        appState.p2p.stopGeneratingQRPayload()
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func generateQRCode(from payload: QRPairingPayload) -> UIImage? {
        guard let jsonData = try? JSONEncoder().encode(payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        let data = Data(jsonString.utf8)
        filter.message = data
        filter.correctionLevel = "H" // High error correction
        
        if let outputImage = filter.outputImage {
            // Scale up
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}

#Preview {
    PairingSetupView()
        .environment(AppState.preview)
}
