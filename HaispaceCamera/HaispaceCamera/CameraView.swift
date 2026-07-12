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
    }
}

// MARK: - Standby View (Belum Paired)

private struct CameraStandbyView: View {
    @Environment(CameraAppState.self) private var cameraState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                // Logo minimal
                VStack(spacing: 8) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.8))
                        .symbolEffect(.pulse, options: .repeating)

                    Text("HaiCamera")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Status
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Text("Menunggu pairing dengan HaiBooth (iPad)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("Buka HaiBooth → Setup → Scan QR")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                // Battery & Thermal status (untuk operator)
                HStack(spacing: 24) {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(cameraState.batteryLevel))
                            .foregroundStyle(batteryColor(cameraState.batteryLevel))
                        Text("\(Int(cameraState.batteryLevel * 100))%")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if cameraState.thermalState != .nominal {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .foregroundStyle(.orange)
                            Text(cameraState.thermalState.displayText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Spacer().frame(height: 20)
                
                // Scan QR Button
                Button {
                    cameraState.p2p.startScanning()
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan QR Pairing")
                    }
                    .font(.title2.bold())
                    .frame(width: 250, height: 60)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                
                if cameraState.p2p.connectionState == .connecting || cameraState.p2p.connectionState == .scanning {
                    ProgressView("Menghubungkan...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .padding(40)
        }
        .preferredColorScheme(.dark)
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
        // Coba decode JSON dari QR string
        guard let data = codeString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPairingPayload.self, from: data) else {
            cameraState.p2p.updateConnectionState(.failed(reason: "Format QR Tidak Valid"))
            return
        }
        
        // Mulai koneksi via P2PClientService
        cameraState.p2p.lastPairingPayload = payload
        P2PClientService.shared.connect(using: payload)
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
        default: return .white.opacity(0.5)
        }
    }
}

// MARK: - Paired View (Terhubung, Menunggu Sesi)

private struct CameraPairedView: View {
    @Environment(CameraAppState.self) private var cameraState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .shadow(color: .green, radius: 4)
                    Text("Terhubung ke HaiBooth")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.6))

                Text("Siap")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Menunggu sesi dimulai dari iPad")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))

                // Signal quality
                HStack(spacing: 6) {
                    Image(systemName: cameraState.p2p.signalQuality.sfSymbol)
                    Text("\(cameraState.p2p.latencyMs)ms")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
            }
        }
        .preferredColorScheme(.dark)
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
