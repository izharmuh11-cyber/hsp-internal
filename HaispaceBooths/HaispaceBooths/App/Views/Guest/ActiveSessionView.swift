// ActiveSessionView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar sesi aktif pemotretan. Menampilkan live view dari iPhone
// dengan countdown timer sinkron dan animasi flash shutter.

import SwiftUI
import AVFoundation

// MARK: - Streaming Video View (UIViewRepresentable)

struct StreamingVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let layer = StreamingDecoderService.shared.displayLayer
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Force layer frame update jika terjadi rotasi/resize
        if let layer = uiView.layer.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Active Session View

struct ActiveSessionView: View {
    @Environment(AppState.self) private var appState
    
    // Status visual
    @State private var localCountdown: Int = 0 // 3.. 2.. 1.. 0
    @State private var showFlash: Bool = false
    @State private var isBriefing: Bool = true
    
    // Timer sesi dari SessionStore
    private var session: SessionStore? {
        appState.currentSession
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Background Live View (Dari P2P)
            StreamingVideoView()
                .ignoresSafeArea()
            
            // Overlay Flash (Saat shutter dipicu)
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .zIndex(10)
            }
            
            // Briefing Overlay (Tampil sesaat sebelum sesi dimulai)
            if isBriefing {
                VStack(spacing: 24) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)
                    Text("Bersiaplah!")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Lihat ke kamera dan berikan senyum terbaikmu.")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(40)
                .background(.black.opacity(0.6))
                .cornerRadius(24)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(20)
            }
            
            // UI Chrome (Hanya tampil jika tidak ada flash dan bukan briefing)
            if !showFlash && !isBriefing {
                VStack {
                    // Top Bar (Sisa Waktu)
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("SISA WAKTU")
                                .font(.caption.bold())
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(color: .black, radius: 2)
                            
                            if let s = session {
                                Text(formatTime(s.remainingSeconds))
                                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                                    .foregroundStyle(s.remainingSeconds <= 30 ? Color.red : Color.white)
                                    .shadow(color: .black, radius: 4)
                            }
                        }
                    }
                    .padding(32)
                    
                    Spacer()
                    
                    // Center Countdown (3.. 2.. 1)
                    if localCountdown > 0 {
                        Text("\(localCountdown)")
                            .font(.system(size: 180, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                            .transition(.scale.combined(with: .opacity))
                            .id("countdown-\(localCountdown)") // Force animation re-trigger
                    }
                    
                    Spacer()
                    
                    // Bottom Bar (Progress Foto)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FOTO TERAMBIL")
                                .font(.caption.bold())
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(color: .black, radius: 2)
                            
                            if let s = session {
                                Text("\(s.photos.capturedCount)")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 4)
                            }
                        }
                        
                        Spacer()
                        
                        // Small pip thumbnail foto terakhir (Opsional)
                        if let lastPhotoId = session?.photos.capturedPhotos.last?.id {
                            // Dummy PIP indicator
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 60, height: 80)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.white.opacity(0.5))
                                )
                        }
                    }
                    .padding(32)
                }
            }
        }
        .onAppear {
            startSessionSequence()
        }
    }
    
    // MARK: - Logic
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func startSessionSequence() {
        guard let session = session else { return }
        
        // Mulai briefing 3 detik
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.spring) {
                isBriefing = false
            }
            session.start()
            startIntervalCaptureLoop()
        }
    }
    
    private func startIntervalCaptureLoop() {
        guard let session = session, session.isActive else { return }
        let interval = 8 // Sesuai config SessionConfig
        
        Task {
            while session.remainingSeconds > 0 && session.isActive {
                // Countdown loop: 3, 2, 1
                for i in (1...3).reversed() {
                    guard session.isActive else { return }
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            localCountdown = i
                        }
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
                
                guard session.isActive else { return }
                
                // Jepret!
                await MainActor.run {
                    localCountdown = 0
                    triggerCapture()
                }
                
                // Tunggu sisa interval sebelum mulai hitung mundur lagi
                let waitTime = max(0, interval - 3)
                if waitTime > 0 {
                    try? await Task.sleep(for: .seconds(waitTime))
                }
            }
            
            // Loop berhenti karena waktu habis
            await MainActor.run {
                if appState.currentRoute == .activeSession {
                    appState.navigateTo(.photoSelection)
                }
            }
        }
    }
    
    @MainActor
    private func triggerCapture() {
        // 1. Tampilkan flash putih
        withAnimation(.easeIn(duration: 0.05)) {
            showFlash = true
        }
        
        // Hilangkan flash cepat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                self.showFlash = false
            }
        }
        
        // 2. Kirim perintah trigger ke iPhone via P2P
        Task {
            await P2PMessageRouter.shared.route(.triggerCapture)
        }
    }
}

#Preview {
    ActiveSessionView()
        .environment(AppState.previewWithActiveSession)
}
