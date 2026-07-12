// PairingSetupView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Setup P2P Pairing untuk memindai QR Code dari iPhone.
// Menampilkan QR Code dinamis dan countdown timer regenerasi.

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingSetupView: View {
    @Environment(AppState.self) private var appState
    
    // Timer state untuk visualisasi (max 5 menit / 300 detik)
    // Di P2PStore regenerasi di set ke 290 detik
    @State private var remainingSeconds: Int = 290
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            Color(hex: "#080810").ignoresSafeArea()
            
            VStack(spacing: 40) {
                
                // Header
                VStack(spacing: 12) {
                    Text("Setup Kamera (HaiCamera)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Buka aplikasi HaiCamera di iPhone dan scan QR Code di bawah ini.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 40)
                
                // QR Code Container
                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color.white)
                        .frame(width: 400, height: 480)
                        .shadow(color: Color(hex: "#00D9A0").opacity(appState.p2p.isConnected ? 0.6 : 0), radius: 30)
                    
                    VStack(spacing: 24) {
                        if appState.p2p.isConnected {
                            // Tampilan Sukses Terhubung
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.green)
                                    .symbolEffect(.bounce, value: true)
                                
                                Text("Terhubung!")
                                    .font(.title.bold())
                                    .foregroundStyle(.black)
                                
                                if let name = appState.p2p.connectedPeerName {
                                    Text(name)
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                            
                        } else {
                            // Tampilan QR Code
                            if let payload = appState.p2p.currentQRPayload,
                               let qrImage = generateQRCode(from: payload) {
                                
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 280, height: 280)
                                    .id(payload.ts) // Memicu re-render otomatis saat ts berubah
                                    .transition(.opacity)
                                
                            } else {
                                ProgressView()
                                    .controlSize(.large)
                                    .frame(width: 280, height: 280)
                            }
                            
                            // Visual Countdown
                            VStack(spacing: 8) {
                                Text("Kode QR akan diperbarui dalam:")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(remainingSeconds < 30 ? .red : .orange)
                                    Text(formatTime(remainingSeconds))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(remainingSeconds < 30 ? .red : .black)
                                }
                            }
                        }
                    }
                }
                .animation(.spring, value: appState.p2p.isConnected)
                
                // Status Bar
                HStack(spacing: 12) {
                    Circle()
                        .fill(appState.p2p.isConnected ? .green : .orange)
                        .frame(width: 12, height: 12)
                    
                    Text(appState.p2p.connectionState.displayText)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Navigation Actions
                HStack(spacing: 24) {
                    Button(role: .cancel) {
                        appState.navigateTo(.missionControl)
                    } label: {
                        Text("Kembali")
                            .font(.title3.bold())
                            .frame(width: 200, height: 60)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    
                    Button {
                        appState.navigateTo(.missionControl)
                    } label: {
                        Text("Lanjutkan")
                            .font(.title3.bold())
                            .frame(width: 200, height: 60)
                            .foregroundStyle(.black)
                            .background(appState.p2p.isConnected ? Color(hex: "#00D9A0") : Color.gray)
                            .clipShape(Capsule())
                    }
                    .disabled(!appState.p2p.isConnected)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
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
        let eventId = appState.currentSession?.id ?? "TEST-EVENT-\(Int.random(in: 1000...9999))"
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
