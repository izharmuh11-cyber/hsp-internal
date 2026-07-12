// ActiveSessionView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar sesi aktif pemotretan. Menampilkan live view dari iPhone
// dengan countdown timer sinkron dan animasi flash shutter.

import SwiftUI
import AVFoundation

// MARK: - Streaming Video View (UIViewRepresentable)

class StreamingDecoderView: UIView {
    private let displayLayer: AVSampleBufferDisplayLayer
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        self.backgroundColor = .black
        self.layer.addSublayer(displayLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = self.bounds
    }
}

struct StreamingVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> StreamingDecoderView {
        return StreamingDecoderView(displayLayer: StreamingDecoderService.shared.displayLayer)
    }
    
    func updateUIView(_ uiView: StreamingDecoderView, context: Context) {
        // Layout disesuaikan oleh layoutSubviews
    }
}

// MARK: - Active Session View

// MARK: - Active Session View

struct ActiveSessionView: View {
    @Environment(AppState.self) private var appState
    
    // Status visual
    @State private var localCountdown: Int = 0 // 3.. 2.. 1.. 0
    @State private var showFlash: Bool = false
    @State private var isBriefing: Bool = true
    @State private var isCapturing: Bool = false
    @State private var activeSelectedPhotoForPreview: CapturedPhoto? = nil
    @State private var gestureListenerTask: Task<Void, Never>? = nil
    
    // Vision AI Pose Guide States
    @State private var showPoseGuide: Bool = true
    @State private var detectedFaceCount: Int = 0
    @State private var currentPoseCategory: PoseCategory = .waiting
    @State private var recommendedZoom: ZoomRecommendation? = nil
    @State private var isStreamLandscape: Bool = true
    
    // Timer sesi dari SessionStore
    private var session: SessionStore? {
        appState.currentSession
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Main camera preview area
                ZStack {
                    // Background Blur Aurora (Menghindari area hitam kosong di samping saat portrait)
                    StreamingVideoView()
                        .blur(radius: 30)
                        .opacity(0.5)
                        .ignoresSafeArea()
                    
                    // Aliran video utama dengan aspek rasio dinamis (16:9 / 9:16)
                    StreamingVideoView()
                        .aspectRatio(isStreamLandscape ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fit)
                        .ignoresSafeArea()
                    
                    // Corner Brackets Alignment Guide (Tampil tipis membantu tamu memposisikan diri)
                    CornerBracketsShape()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .padding(EdgeInsets(top: 80, leading: 100, bottom: 80, trailing: 100))
                        .allowsHitTesting(false)
                        .opacity(isBriefing ? 0 : 1)
                        .animation(.easeInOut, value: isBriefing)
                    
                    // Overlay Flash (Saat jepretan dipicu)
                    if showFlash {
                        Color.white
                            .ignoresSafeArea()
                            .zIndex(10)
                    }
                    
                    // Center Countdown (3.. 2.. 1)
                    if localCountdown > 0 {
                        Text("\(localCountdown)")
                            .font(.system(size: 180, weight: .heavy, design: .rounded))
                            .foregroundStyle(localCountdown == 1 ? Color(red: 255/255, green: 215/255, blue: 0/255) : .white) // Emas untuk detik 1
                            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(15)
                            .id("countdown-\(localCountdown)") // Force animation re-trigger
                    }
                    
                    // Toggle Pose Guide Button
                    if localCountdown == 0 && !showFlash && !isBriefing {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showPoseGuide.toggle()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: showPoseGuide ? "person.crop.rectangle.stack.fill" : "person.crop.rectangle.stack")
                                        Text(showPoseGuide ? "Sembunyikan Panduan" : "Panduan Pose")
                                            .font(.subheadline.bold())
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(.white)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                                }
                                .padding(.top, 24)
                                .padding(.trailing, 24)
                            }
                            Spacer()
                        }
                    }
                    
                    // Auto-Zoom Recommendation Toast
                    if let recommendedZoom = recommendedZoom, localCountdown == 0 && !showFlash && !isBriefing {
                        VStack {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Color(red: 255/255, green: 215/255, blue: 0/255))
                                Text("AI menyarankan zoom: \(recommendedZoom.description)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.75))
                            .cornerRadius(16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 24)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                    
                    // UI Chrome (Hanya tampil jika tidak ada flash dan bukan briefing)
                    if !showFlash && !isBriefing {
                        // Floating Shutter Button
                        if localCountdown == 0 {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        startManualCaptureSequence()
                                    }) {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 80, height: 80)
                                            .overlay(
                                                Circle()
                                                    .stroke(.black.opacity(0.2), lineWidth: 4)
                                                    .padding(4)
                                            )
                                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                                    }
                                    .disabled(isCapturing)
                                    .opacity(isCapturing ? 0.5 : 1.0)
                                    Spacer()
                                }
                                .padding(.bottom, 40)
                            }
                        }
                    }
                }
                
                // Sidebar Pose Guide Panel
                if showPoseGuide && localCountdown == 0 {
                    PoseGuidePanel(category: currentPoseCategory, faceCount: detectedFaceCount)
                        .frame(width: 240)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                
                // Sidebar Photo Grid (Right)
                if localCountdown == 0 {
                    VStack(spacing: 16) {
                    Text("HASIL FOTO")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 24)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            if let s = session {
                                ForEach(s.photos.capturedPhotos) { photo in
                                    Button(action: {
                                        activeSelectedPhotoForPreview = photo
                                    }) {
                                        VStack(spacing: 4) {
                                            if let uiImage = UIImage(data: photo.thumbnailData) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 130)
                                                    .cornerRadius(8)
                                                    .clipped()
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                                    )
                                            } else {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(width: 100, height: 130)
                                                    .overlay(
                                                        Image(systemName: "photo")
                                                            .foregroundStyle(.white.opacity(0.3))
                                                    )
                                            }
                                            
                                            Text("Pose \(photo.sortOrder + 1)")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                        .padding(4)
                                        .background(.white.opacity(0.05))
                                        .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    
                    Spacer()
                    
                    // Sisa Waktu
                    if let s = session {
                        VStack(spacing: 4) {
                            Text("SISA WAKTU")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(formatTime(s.remainingSeconds))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(s.remainingSeconds <= 30 ? Color.red : Color.white)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    // Finish Button
                    Button(action: {
                        appState.navigateTo(.photoSelection)
                    }) {
                        Text("Selesai")
                            .font(.subheadline.bold())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white)
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    }
                }
                .frame(width: 140)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .vertical)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
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
            
            // Selective Retake Premium Modal Overlay
            if let selectedPhoto = activeSelectedPhotoForPreview {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                        .onTapGesture {
                            activeSelectedPhotoForPreview = nil
                        }
                    
                    VStack(spacing: 24) {
                        if let uiImage = UIImage(data: selectedPhoto.thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(16)
                                .frame(maxHeight: 500)
                                .shadow(color: .black.opacity(0.4), radius: 20)
                        }
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                activeSelectedPhotoForPreview = nil
                            }) {
                                Text("Batal")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(.white.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            
                            Button(action: {
                                let targetId = selectedPhoto.id
                                let targetOrder = selectedPhoto.sortOrder
                                activeSelectedPhotoForPreview = nil
                                startManualCaptureSequence(replacePhotoId: targetId, sortOrder: targetOrder)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    Text("Foto Ulang (Retake)")
                                }
                                .font(.headline)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(.white)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(24)
                    .padding(40)
                }
                .zIndex(30)
            }
        }
        .onAppear {
            startSessionSequence()
            startGestureListener()
            
            // Set Vision AI callback
            StreamingDecoderService.shared.onFrameAnalyzed = { count, category, zoom in
                Task { @MainActor in
                    self.detectedFaceCount = count
                    self.currentPoseCategory = category
                    self.recommendedZoom = zoom
                }
            }
            
            // Set callback untuk deteksi aspek rasio aliran video
            StreamingDecoderService.shared.onVideoDimensionsChanged = { isLandscape in
                Task { @MainActor in
                    if self.isStreamLandscape != isLandscape {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isStreamLandscape = isLandscape
                        }
                    }
                }
            }
        }
        .onDisappear {
            gestureListenerTask?.cancel()
            gestureListenerTask = nil
            
            // Clear Vision AI callbacks
            StreamingDecoderService.shared.onFrameAnalyzed = nil
            StreamingDecoderService.shared.onVideoDimensionsChanged = nil
        }
        .onChange(of: session?.status) { oldStatus, newStatus in
            if newStatus == .photoSelection {
                appState.navigateTo(.photoSelection)
            }
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
        }
    }
    
    private func startGestureListener() {
        gestureListenerTask?.cancel()
        gestureListenerTask = Task { [weak appState] in
            for await message in await P2PMessageRouter.shared.messageStream(for: .gestureDetected) {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.startManualCaptureSequence()
                }
            }
        }
    }
    
    @MainActor
    private func startManualCaptureSequence(replacePhotoId: String? = nil, sortOrder: Int? = nil) {
        guard !isCapturing && localCountdown == 0 else { return }
        
        isCapturing = true
        
        // Timer countdown manual: 3, 2, 1
        Task {
            for i in (1...3).reversed() {
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        localCountdown = i
                    }
                    
                    // Audio & Haptic feedback per detik countdown
                    if i == 1 {
                        SessionFeedbackService.shared.triggerHaptic(style: .heavy)
                        SessionFeedbackService.shared.playCountdownTick()
                    } else {
                        SessionFeedbackService.shared.triggerHaptic(style: .medium)
                        SessionFeedbackService.shared.playCountdownTick()
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    localCountdown = 0
                }
                
                // Suara Shutter & Heavy haptic saat memotret
                SessionFeedbackService.shared.playShutterClick()
                SessionFeedbackService.shared.triggerHaptic(style: .heavy)
                
                triggerCapture(replacePhotoId: replacePhotoId, sortOrder: sortOrder)
                isCapturing = false
            }
        }
    }
    
    @MainActor
    private func triggerCapture(replacePhotoId: String? = nil, sortOrder: Int? = nil) {
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
            let index = sortOrder ?? (appState.currentSession?.photos.capturedCount ?? 0)
            await P2PMessageRouter.shared.route(.triggerCapture(poseId: replacePhotoId, captureIndex: index))
        }
    }
}

// MARK: - Corner Brackets Shape
struct CornerBracketsShape: Shape {
    let length: CGFloat = 30
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Top Left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        
        // Top Right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        
        // Bottom Left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        
        // Bottom Right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        
        return path
    }
}

#Preview {
    ActiveSessionView()
        .environment(AppState.previewWithActiveSession)
}
