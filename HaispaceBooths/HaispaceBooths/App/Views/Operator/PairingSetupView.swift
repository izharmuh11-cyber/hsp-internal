// PairingSetupView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Setup P2P Pairing untuk memindai QR Code dari iPhone.
// Menampilkan QR Code dinamis dan countdown timer regenerasi.
// Menggunakan desain premium bertema "Apple Watch/Device Setup Card".

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    // Timer state untuk visualisasi (max 5 menit / 300 detik)
    @State private var remainingSeconds: Int = 290
    @State private var timer: Timer?
    
    @State private var isAnimating = false
    @State private var isShowingLogViewer = false
    
    var body: some View {
        ZStack {
            // 1. Premium Animated Background
            Color(hex: "#05050C").ignoresSafeArea()
            
            // Soft shifting background glows
            Circle()
                .fill(Color(hex: "#7C5CFC").opacity(0.12))
                .blur(radius: 120)
                .frame(width: 500, height: 500)
                .offset(x: isAnimating ? 200 : -200, y: isAnimating ? -200 : 200)
            
            Circle()
                .fill(Color(hex: "#00D9A0").opacity(0.08))
                .blur(radius: 120)
                .frame(width: 400, height: 400)
                .offset(x: isAnimating ? -300 : 300, y: isAnimating ? 300 : -300)
            
            VStack(spacing: 40) {
                // Header
                VStack(spacing: 12) {
                    Text("Hubungkan Kamera")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Pindai QR Code di bawah menggunakan HaiCamera untuk pairing.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 40)
                
                // QR Code Card (Apple Watch Setup Style)
                VStack(spacing: 24) {
                    if appState.p2p.isConnected {
                        // Connected State
                        VStack(spacing: 24) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "#00D9A0").opacity(0.1))
                                    .frame(width: 140, height: 140)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 56, weight: .bold))
                                    .foregroundStyle(Color(hex: "#00D9A0"))
                            }
                            
                            VStack(spacing: 8) {
                                Text("Berhasil Terhubung")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                
                                if let name = appState.p2p.connectedPeerName {
                                    Text(name)
                                        .font(.headline)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        .frame(height: 380)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Scanning State
                        VStack(spacing: 24) {
                            if let payload = appState.p2p.currentQRPayload,
                               let qrImage = generateQRCode(from: payload) {
                                
                                ZStack {
                                    // Animated scan effect ring
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .stroke(Color(hex: "#7C5CFC").opacity(0.3), lineWidth: 2)
                                        .frame(width: 280, height: 280)
                                        .scaleEffect(isAnimating ? 1.05 : 0.95)
                                        .opacity(isAnimating ? 0.2 : 0.8)
                                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                                    
                                    Image(uiImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 240, height: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                        .shadow(color: .black.opacity(0.3), radius: 15)
                                }
                                .transition(.opacity)
                            } else {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                                    .frame(width: 280, height: 280)
                            }
                            
                            // Timer Pill
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(formatTime(remainingSeconds))
                                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(remainingSeconds < 30 ? Color.red : .white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(32)
                .frame(width: 420, height: 460)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: appState.p2p.isConnected ? Color(hex: "#00D9A0").opacity(0.15) : Color.black.opacity(0.3), radius: 30, y: 15)
                
                Spacer()
                
                // Bottom Bar Controls
                VStack(spacing: 20) {
                    // Status Badge
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appState.p2p.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                            .shadow(color: appState.p2p.isConnected ? Color.green : Color.orange, radius: 4)
                        
                        Text(appState.p2p.connectionState.displayText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                    
                    // Native Action Buttons
                    HStack(spacing: 16) {
                        Button(action: { dismiss() }) {
                            Text("Batal")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .frame(width: 160, height: 50)
                                .foregroundStyle(.white)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        Button(action: { dismiss() }) {
                            Text("Selesai")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .frame(width: 160, height: 50)
                                .foregroundStyle(appState.p2p.isConnected ? .black : .white.opacity(0.3))
                                .background(appState.p2p.isConnected ? Color(hex: "#00D9A0") : Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .disabled(!appState.p2p.isConnected)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingLogViewer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Log Sistem")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.top, 24)
            .padding(.trailing, 28)
        }
        .sheet(isPresented: $isShowingLogViewer) {
            LogViewerSheet()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            setupQRGeneration()
        }
        .onChange(of: appState.p2p.isConnected) { _, isConnected in
            if isConnected {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Auto dismiss setelah 2 detik
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            }
        }
        .onDisappear {
            teardownQRGeneration()
        }
        .onChange(of: appState.p2p.currentQRPayload?.ts) { _, _ in
            remainingSeconds = 290
        }
    }
    
    // MARK: - QR Generation Logic
    private func setupQRGeneration() {
        let eventId = appState.currentSession?.sessionId ?? "TEST-EVENT-\(Int.random(in: 1000...9999))"
        let localIp = NetworkUtility.getWiFiAddress() ?? "127.0.0.1"
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
