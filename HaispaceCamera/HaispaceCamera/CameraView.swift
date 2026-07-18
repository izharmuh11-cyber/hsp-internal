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
                
                switch cameraState.p2p.connectionState {
                case .connecting, .scanning:
                    ProgressView("Menghubungkan...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 20)
                case .reconnecting(let attempt):
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.orange)
                        Text("Koneksi Terputus. Menghubungkan Kembali... (\(attempt))")
                            .font(.system(.caption, design: .rounded))
                            .bold()
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.bottom, 20)
                default:
                    EmptyView()
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
    @State private var isShowingToast = false
    
    // Token dibaca/ditulis dari Keychain — input sekali, tidak perlu ulangi
    @State private var githubPAT = ""
    @State private var isTokenSaved = false
    @State private var isUploading = false
    @State private var lastUploadURL: String? = nil   // URL raw file setelah upload sukses
    @State private var uploadMessage = ""
    @State private var showUploadAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if logContent.isEmpty {
                    Spacer()
                    Text("Log kosong atau tidak dapat dimuat.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Panel Token + Upload
                    VStack(alignment: .leading, spacing: 10) {
                        Text("KIRIM LOG OTOMATIS KE GITHUB")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.5))
                        
                        // Input token (hanya perlu diisi sekali)
                        HStack(spacing: 8) {
                            SecureField("GitHub Personal Access Token (PAT)", text: $githubPAT)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .foregroundStyle(.white)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            
                            Button {
                                // Simpan ke Keychain — tidak perlu input ulang setelah ini
                                GitHubLogUploader.saveToken(githubPAT)
                                withAnimation { isTokenSaved = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { isTokenSaved = false }
                                }
                            } label: {
                                Label(isTokenSaved ? "Tersimpan" : "Simpan",
                                      systemImage: isTokenSaved ? "checkmark.circle.fill" : "key.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(isTokenSaved ? Color.green : Color.blue)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(githubPAT.count < 10)
                        }
                        
                        if isTokenSaved {
                            Text("✅ Token disimpan di Keychain — tidak perlu input ulang")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else if KeychainHelper.getGitHubPAT() != nil {
                            Text("🔑 Token sudah tersimpan di Keychain")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        // Tombol Upload + URL hasil upload
                        HStack(spacing: 8) {
                            Button {
                                uploadLog()
                            } label: {
                                if isUploading {
                                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                                } else {
                                    Label("Unggah Log ke GitHub", systemImage: "arrow.up.circle.fill")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 10)
                            .background(GitHubLogUploader.resolvedToken() == nil ? Color.gray.opacity(0.3) : Color.indigo)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                            .disabled(GitHubLogUploader.resolvedToken() == nil || isUploading)
                        }
                        
                        // URL hasil upload — bisa langsung dikopi dan dikirim ke AI
                        if let url = lastUploadURL {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("📎 URL Log (bagikan ke AI untuk dibaca langsung):")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white.opacity(0.6))
                                HStack {
                                    Text(url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                        .lineLimit(2)
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = url
                                    } label: {
                                        Image(systemName: "doc.on.doc.fill")
                                            .foregroundStyle(.cyan)
                                    }
                                }
                                .padding(8)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                            withAnimation(.spring) { isShowingToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { isShowingToast = false }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Salin Log")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(12)
                        }
                        
                        ShareLink(item: logContent) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text("Bagikan Log")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Log Kamera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hapus Log", role: .destructive) {
                        LocalLogWriter.clearLog(subsystem: "camera")
                        logContent = ""
                        lastUploadURL = nil
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
            .onAppear {
                logContent = LocalLogWriter.readLogContent(subsystem: "camera")
                // Load token dari Keychain jika ada (tampilkan sebagai masked)
                if let stored = KeychainHelper.getGitHubPAT() {
                    githubPAT = stored
                }
            }
            .overlay {
                if isShowingToast {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("Log Berhasil Disalin")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .alert("Unggah Log", isPresented: $showUploadAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadMessage)
            }
        }
    }
    
    private func uploadLog() {
        isUploading = true
        lastUploadURL = nil
        GitHubLogUploader.uploadLatestLog(eventName: "manual_upload") { url in
            isUploading = false
            if let url = url {
                lastUploadURL = url
                // Otomatis copy URL ke clipboard
                UIPasteboard.general.string = url
            } else {
                uploadMessage = "Gagal upload. Pastikan token valid dan koneksi internet tersedia."
                showUploadAlert = true
            }
        }
    }
}

