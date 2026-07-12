// CameraView.swift
// HaispaceCamera
//
// Root view iPhone — menampilkan layar yang sesuai berdasarkan camera state.
// Saat sesi aktif: LAYAR HITAM PENUH (tidak ada UI yang terlihat).
// Saat standby: Tampilkan status minimal untuk operator.
//
// Ref: docs/design/22_haicamera_ux.md — Zero Chrome Camera Mode

import SwiftUI

// MARK: - Camera View

struct CameraView: View {

    @Environment(CameraAppState.self) private var cameraState

    var body: some View {
        Group {
            switch cameraState.cameraStatus {

            case .standby:
                // Layar minimal — menunggu pairing
                CameraStandbyView()

            case .paired:
                // Terhubung ke iPad — menunggu perintah sesi
                CameraPairedView()

            case .sessionActive:
                // LAYAR HITAM — kamera mengambil foto di background
                CameraBlackScreenView()

            case .sessionEnded:
                // Layar selesai — transisi kembali ke paired
                CameraSessionEndedView()

            case .error(let msg):
                CameraErrorView(message: msg)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: cameraState.isSessionActive)
        .onChange(of: cameraState.cameraStatus) { _, newStatus in
            if case .paired = newStatus {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Standby View (Belum Paired)

private struct CameraStandbyView: View {
    @Environment(CameraAppState.self) private var cameraState
    @State private var isAnimating = false
    @State private var isShowingLogViewer = false

    var body: some View {
        ZStack {
            // 1. Premium Animated Background
            Color(red: 5/255, green: 5/255, blue: 10/255).ignoresSafeArea()
            
            // Subtle ambient glows for iPhone
            Circle()
                .fill(Color.blue.opacity(0.15))
                .blur(radius: 80)
                .frame(width: 300, height: 300)
                .offset(x: isAnimating ? 100 : -100, y: isAnimating ? -150 : 150)
            
            Circle()
                .fill(Color.purple.opacity(0.15))
                .blur(radius: 80)
                .frame(width: 250, height: 250)
                .offset(x: isAnimating ? -100 : 100, y: isAnimating ? 150 : -150)

            VStack(spacing: 40) {
                Spacer()
                
                // Logo & Status minimal
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 120, height: 120)
                            .shadow(color: .white.opacity(0.1), radius: 20)
                        
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 60, weight: .light))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("HaiCamera")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Menunggu pairing dengan HaiBooth...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Hardware Status (Battery & Thermal)
                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Image(systemName: batteryIcon(cameraState.batteryLevel))
                            .foregroundStyle(batteryColor(cameraState.batteryLevel))
                        Text("\(Int(cameraState.batteryLevel * 100))%")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    if cameraState.thermalState != .nominal {
                        HStack(spacing: 6) {
                            Image(systemName: "thermometer.medium")
                                .foregroundStyle(.orange)
                            Text(cameraState.thermalState.displayText)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
                
                // Scan QR Button
                Button {
                    cameraState.p2p.startScanning()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3.weight(.semibold))
                        Text("Scan QR Pairing")
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(
                        LinearGradient(colors: [Color(red: 0, green: 82/255, blue: 212/255), Color(red: 67/255, green: 100/255, blue: 247/255), Color(red: 111/255, green: 177/255, blue: 252/255)], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 67/255, green: 100/255, blue: 247/255).opacity(0.5), radius: 20, y: 10)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                
                if cameraState.p2p.connectionState == .connecting || cameraState.p2p.connectionState == .scanning {
                    ProgressView("Menghubungkan...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button {
                isShowingLogViewer = true
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 24)
        }
        .sheet(isPresented: $isShowingLogViewer) {
            CameraLogViewerSheet()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .fullScreenCover(isPresented: Bindable(cameraState.p2p).isScanning) {
            QRScannerView { codeString in
                cameraState.p2p.stopScanning()
                handleScannedCode(codeString)
            } onCancel: {
                cameraState.p2p.stopScanning()
            }
            .ignoresSafeArea()
        }
    }
    
    private func handleScannedCode(_ codeString: String) {
        guard let data = codeString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPairingPayload.self, from: data) else {
            cameraState.p2p.updateConnectionState(.failed(reason: "Format QR Tidak Valid"))
            return
        }
        
        cameraState.p2p.lastPairingPayload = payload
        Task {
            await P2PClientService.shared.connect(using: payload)
        }
    }

    private func batteryIcon(_ level: Float) -> String {
        switch level {
        case 0.0..<0.1: return "battery.0"
        case 0.1..<0.3: return "battery.25"
        case 0.3..<0.6: return "battery.50"
        case 0.6..<0.9: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(_ level: Float) -> Color {
        switch level {
        case 0.0..<0.15: return .red
        case 0.15..<0.30: return .orange
        default: return .white.opacity(0.8)
        }
    }
}

// MARK: - Paired View (Terhubung, Menunggu Sesi)

private struct CameraPairedView: View {
    @Environment(CameraAppState.self) private var cameraState
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color(red: 5/255, green: 5/255, blue: 10/255).ignoresSafeArea()
            
            // Green glow background indicating ready
            Circle()
                .fill(Color.green.opacity(0.15))
                .blur(radius: 100)
                .frame(width: 300, height: 300)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isPulsing)

            VStack(spacing: 32) {
                // Status indicator
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(red: 0, green: 217/255, blue: 160/255))
                        .frame(width: 12, height: 12)
                        .shadow(color: Color(red: 0, green: 217/255, blue: 160/255), radius: 8)
                    Text("Terhubung")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 160, height: 160)
                        .shadow(color: .green.opacity(0.1), radius: 30)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .white.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        )
                }
                .padding(.vertical, 20)

                VStack(spacing: 8) {
                    Text("Kamera Siap")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Menunggu sesi foto dari iPad...")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Signal quality
                HStack(spacing: 8) {
                    Image(systemName: cameraState.p2p.signalQuality.sfSymbol)
                        .foregroundStyle(cameraState.p2p.signalQuality == .excellent ? .green : .orange)
                    Text("\(cameraState.p2p.latencyMs)ms")
                        .font(.headline.monospacedDigit())
                }
                .padding(.top, 20)
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Black Screen (Sesi Aktif — TIDAK ADA UI)

private struct CameraBlackScreenView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
    }
}

// MARK: - Session Ended View

private struct CameraSessionEndedView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: true)
                Text("Sesi Selesai")
                    .font(.title2.bold())
                    .foregroundStyle(.white.opacity(0.8))
                Text("Kembali ke mode standby...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Error View

private struct CameraErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Terjadi Kesalahan")
                    .font(.title2.bold())
                    .foregroundStyle(.white.opacity(0.8))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}

// MARK: - Previews

#Preview("Standby") {
    CameraView()
        .environment(CameraAppState.preview)
}

#Preview("Black Screen — Sesi Aktif") {
    CameraView()
        .environment(CameraAppState.previewActive)
}

private struct CameraLogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                if logContent.isEmpty {
                    Text("Log kosong atau tidak dapat dimuat.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle("Log Kamera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hapus Log", role: .destructive) {
                        LocalLogWriter.clearLog(subsystem: "camera")
                        logContent = ""
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        
                        ShareLink(item: logContent) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                logContent = LocalLogWriter.readLogContent(subsystem: "camera")
            }
        }
    }
}
