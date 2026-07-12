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
    @State private var detectedFaceCount: Int = 0
    @State private var currentPoseCategory: PoseCategory = .waiting
    @State private var recommendedZoom: ZoomRecommendation? = nil
    @State private var isStreamLandscape: Bool = true
    @State private var activeZoom: String = "1x"
    @State private var isPortraitModeActive: Bool = false
    
    @State private var focusTapPoint: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var focusScale: CGFloat = 1.0
    @State private var focusOpacity: Double = 1.0
    @State private var animateAurora: Bool = false
    @State private var isPulsing: Bool = false
    
    // Contextual Ghost Pose & Idle Detector States
    @State private var lastActivityTime = Date()
    @State private var showPoseHint: Bool = false
    @State private var showPoseOverlay: Bool = false
    @State private var currentPoseIndex: Int = 0
    private let activityTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // Timer sesi dari SessionStore
    private var session: SessionStore? {
        appState.currentSession
    }
    
    var body: some View {
        GeometryReader { screenGeo in
            let ipadLandscape = screenGeo.size.width > screenGeo.size.height
            
            ZStack {
                // Dynamic moving aurora background
                Color.black.ignoresSafeArea()
                
                auroraBackgroundView
                
                ZStack {
                    // Aliran video utama dengan aspek rasio dinamis (16:9 / 9:16) dan deteksi ketukan fokus (tap-to-focus)
                    GeometryReader { geometry in
                        videoFeedView(geometry: geometry)
                    }
                    .aspectRatio(isStreamLandscape ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fill)
                    .ignoresSafeArea()
                    
                    focusIndicatorOverlay
                    
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
                    
                    countdownOverlay
                }
                    
                    // Butuh Inspirasi Gaya? Floating Hint Banner
                    if showPoseHint && localCountdown == 0 && !showPoseOverlay && !showFlash && !isBriefing {
                        VStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    showPoseHint = false
                                    showPoseOverlay = true
                                    currentPoseIndex = 0
                                }
                                lastActivityTime = Date()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(Color(red: 255/255, green: 215/255, blue: 0/255))
                                    Text("Butuh referensi gaya?")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .cornerRadius(24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                            }
                            .padding(.top, 90) // Safely below top widgets
                            Spacer()
                        }
                        .zIndex(22)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Contextual Ghost Pose Image Overlay
                    if showPoseOverlay && localCountdown == 0 && !showFlash && !isBriefing {
                        ZStack {
                            // Tap outside to dismiss
                            Color.black.opacity(0.15)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        showPoseOverlay = false
                                        lastActivityTime = Date()
                                    }
                                }
                            
                            let poseImages = getPoseImagesForCount(detectedFaceCount)
                            if !poseImages.isEmpty {
                                let assetName = poseImages[currentPoseIndex % poseImages.count]
                                
                                VStack(spacing: 16) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(assetName)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: ipadLandscape ? 500 : 380, maxHeight: ipadLandscape ? 400 : 520)
                                            .opacity(0.35) // Semi-transparent stencil/ghost overlay!
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(.white.opacity(0.3), lineWidth: 2)
                                            )
                                            .gesture(
                                                DragGesture(minimumDistance: 20)
                                                    .onEnded { gesture in
                                                        let horizontalDrag = gesture.translation.width
                                                        if horizontalDrag > 30 {
                                                            // Swipe Right -> Prev Pose
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                                currentPoseIndex = (currentPoseIndex - 1 + poseImages.count) % poseImages.count
                                                            }
                                                        } else if horizontalDrag < -30 {
                                                            // Swipe Left -> Next Pose
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                                currentPoseIndex = (currentPoseIndex + 1) % poseImages.count
                                                            }
                                                        }
                                                        lastActivityTime = Date()
                                                    }
                                            )
                                        
                                        // Close Button
                                        Button(action: {
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                showPoseOverlay = false
                                                lastActivityTime = Date()
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 28))
                                                .foregroundStyle(.white.opacity(0.8), .black.opacity(0.6))
                                                .padding(12)
                                        }
                                    }
                                    
                                    // Dots Pagination
                                    HStack(spacing: 6) {
                                        ForEach(0..<poseImages.count, id: \.self) { idx in
                                            Circle()
                                                .fill(idx == currentPoseIndex % poseImages.count ? Color.white : Color.white.opacity(0.3))
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    
                                    Text("Geser (Swipe) untuk pose lain • \(detectedFaceCount) Wajah")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        .zIndex(25)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                    // Left Floating Sidebar (Galeri Foto)
                    if localCountdown == 0 && !showFlash && !isBriefing {
                        VStack(spacing: 12) {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: 14) {
                                    if let s = session {
                                        ForEach(Array(s.photos.capturedPhotos.enumerated()), id: \.element.id) { index, photo in
                                            Button(action: {
                                                activeSelectedPhotoForPreview = photo
                                            }) {
                                                if let uiImage = UIImage(data: photo.thumbnailData) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 60, height: 78)
                                                        .cornerRadius(10)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 10)
                                                                .stroke(Color.white, lineWidth: 2) // Polaroid-style white border
                                                        )
                                                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                                                        .rotationEffect(.degrees(index % 2 == 0 ? 1.5 : -1.5)) // Polaroid-style alternate rotation
                                                        .clipped()
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            }
                        }
                        .frame(width: 80, height: ipadLandscape ? 420 : 320)
                        .padding(.leading, 24)
                        .padding(.bottom, ipadLandscape ? 120 : 160) // Shift safely above shutter
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(14)
                    }
                    
                    // Symmetrical Top Header Pill Bar
                    if localCountdown == 0 && !showFlash && !isBriefing {
                        VStack {
                            HStack {
                                // Top Left: Queue Number
                                if let s = session {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Antrian #\(String(format: "%03d", s.queueNumber ?? 1))")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                
                                Spacer()
                                
                                // Top Center: iOS Live Activity Timer
                                if let s = session {
                                    HStack(spacing: 8) {
                                        Text("LIVE PREVIEW • \(formatTime(s.remainingSeconds))")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                        
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 8, height: 8)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.green, lineWidth: 1.5)
                                                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                                                    .opacity(isPulsing ? 0.0 : 1.0)
                                            )
                                            .onAppear {
                                                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                                    isPulsing = true
                                                }
                                            }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(s.remainingSeconds <= 30 ? Color.red : Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                
                                Spacer()
                                
                                // Top Right: Photo Count
                                if let s = session {
                                    HStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 11))
                                        Text("\(s.photos.capturedCount) / \(s.config.maxShots ?? 9)")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            
                            Spacer()
                        }
                        .zIndex(18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    shutterAndControlsOverlay
                    doneButtonOverlay
                
                // Briefing Overlay (Tampil sesaat sebelum sesi dimulai)
                briefingOverlayHelper
                
                // Selective Retake Premium Modal Overlay
                if let selectedPhoto = activeSelectedPhotoForPreview {
                    ZStack {
                        // Deep Blur Glass Background
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    activeSelectedPhotoForPreview = nil
                                }
                            }
                        
                        VStack(spacing: 28) {
                            // Modal Header
                            VStack(spacing: 6) {
                                Text("TINJAU POSE \(selectedPhoto.sortOrder + 1)")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .tracking(3)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "#7C5CFC"), Color(hex: "#9D85FF")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                
                                Text("Apakah pose ini sudah sesuai, atau Anda ingin mengambil foto ulang?")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 12)
                            
                            // Photo Frame with Glowing Border
                            if let uiImage = UIImage(data: selectedPhoto.thumbnailData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 460)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                    )
                                    .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                            }
                            
                            // Action Buttons
                            HStack(spacing: 20) {
                                // Button Cancel / Close
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        activeSelectedPhotoForPreview = nil
                                    }
                                }) {
                                    Text("Batal")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(width: 140, height: 48)
                                        .background(.white.opacity(0.12))
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                }
                                
                                // Button Retake
                                Button(action: {
                                    let targetId = selectedPhoto.id
                                    let targetOrder = selectedPhoto.sortOrder
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        activeSelectedPhotoForPreview = nil
                                    }
                                    startManualCaptureSequence(replacePhotoId: targetId, sortOrder: targetOrder)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                                        Text("Foto Ulang (Retake)")
                                    }
                                    .font(.system(.headline, design: .rounded).bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 220, height: 48)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: "#7C5CFC"), Color(hex: "#9D85FF")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(Capsule())
                                    .shadow(color: Color(hex: "#7C5CFC").opacity(0.35), radius: 12, y: 6)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color(hex: "#0A0A10").opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                        .padding(32)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }
                    .zIndex(30)
                }
            }
        }
        .onReceive(activityTimer) { _ in
            guard localCountdown == 0 && !showPoseOverlay && !isBriefing && !showFlash else { return }
            if Date().timeIntervalSince(lastActivityTime) >= 10.0 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showPoseHint = true
                }
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
            
            // Mulai animasi aurora latar belakang
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                self.animateAurora = true
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
        
        // Reset activity timer and dismiss hint banner / overlays
        lastActivityTime = Date()
        showPoseHint = false
        showPoseOverlay = false
        
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
    
    private func getPoseImagesForCount(_ count: Int) -> [String] {
        if count <= 1 {
            return ["pose_solo_1", "pose_solo_2", "pose_solo_3"]
        } else if count == 2 {
            return ["pose_duo_1", "pose_duo_2", "pose_duo_3"]
        } else {
            return ["pose_group_1", "pose_group_2", "pose_group_3"]
        }
    }
    
    // MARK: - Sub-Views for Body Decoupling (Prevents type-checking timeout)
    
    @ViewBuilder
    private var auroraBackgroundView: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: "#7C5CFC").opacity(0.12), .clear], center: .center, startRadius: 10, endRadius: 350)
                .scaleEffect(animateAurora ? 1.25 : 0.8)
                .offset(x: animateAurora ? -100 : 100, y: animateAurora ? -50 : 50)
            
            RadialGradient(colors: [Color(hex: "#00D9A0").opacity(0.08), .clear], center: .center, startRadius: 10, endRadius: 300)
                .scaleEffect(animateAurora ? 0.8 : 1.25)
                .offset(x: animateAurora ? 120 : -120, y: animateAurora ? 80 : -80)
        }
        .ignoresSafeArea()
        .blur(radius: 40)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func videoFeedView(geometry: GeometryProxy) -> some View {
        ZStack {
            StreamingVideoView()
                .blur(radius: 30)
                .opacity(0.5)
                .ignoresSafeArea()
            
            StreamingVideoView()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard localCountdown == 0 else { return }
                            
                            let width = geometry.size.width
                            let height = geometry.size.height
                            guard width > 0 && height > 0 else { return }
                            
                            let x = Float(value.location.x / width)
                            let y = Float(value.location.y / height)
                            
                            let cleanX = max(0.0, min(1.0, x))
                            let cleanY = max(0.0, min(1.0, y))
                            
                            Task {
                                await P2PMessageRouter.shared.route(.focusPoint(normalizedX: cleanX, normalizedY: cleanY))
                            }
                            
                            self.focusTapPoint = value.location
                            self.focusScale = 1.6
                            self.focusOpacity = 1.0
                            self.showFocusIndicator = true
                            
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                self.focusScale = 1.0
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    self.focusOpacity = 0.0
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                self.showFocusIndicator = false
                            }
                            
                            SessionFeedbackService.shared.triggerHaptic(style: .light)
                            
                            lastActivityTime = Date()
                            showPoseHint = false
                        }
                )
        }
    }
    
    @ViewBuilder
    private var focusIndicatorOverlay: some View {
        if let focusPoint = focusTapPoint, showFocusIndicator {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(red: 255/255, green: 215/255, blue: 0/255), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                
                Circle()
                    .fill(Color(red: 255/255, green: 215/255, blue: 0/255))
                    .frame(width: 3, height: 3)
                
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 255/255, green: 215/255, blue: 0/255))
                    .offset(x: 38, y: 0)
            }
            .position(focusPoint)
            .scaleEffect(focusScale)
            .opacity(focusOpacity)
            .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var countdownOverlay: some View {
        if localCountdown > 0 {
            Text("\(localCountdown)")
                .font(.system(size: 180, weight: .heavy, design: .rounded))
                .foregroundStyle(localCountdown == 1 ? Color(red: 255/255, green: 215/255, blue: 0/255) : .white)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(15)
                .id("countdown-\(localCountdown)")
        }
    }
    
    @ViewBuilder
    private var briefingOverlayHelper: some View {
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
    }
    
    @ViewBuilder
    private var shutterAndControlsOverlay: some View {
        if localCountdown == 0 && !showFlash && !isBriefing {
            VStack(spacing: 20) {
                Spacer()
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(["0.5x", "1x", "2x"], id: \.self) { lens in
                            Button(action: {
                                activeZoom = lens
                                let factor = lens == "0.5x" ? 0.5 : (lens == "2x" ? 2.0 : 1.0)
                                Task {
                                    await P2PMessageRouter.shared.route(.setZoom(factor: factor))
                                }
                                lastActivityTime = Date()
                            }) {
                                Text(lens.replacingOccurrences(of: "x", with: ""))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(activeZoom == lens ? Color.black : Color.white)
                                    .frame(width: 32, height: 32)
                                    .background(activeZoom == lens ? Color.white : Color.clear)
                                    .clipShape(Circle())
                                    .shadow(color: activeZoom == lens ? .black.opacity(0.15) : .clear, radius: 2)
                            }
                        }
                    }
                    .padding(3)
                    .background(.black.opacity(0.35))
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    
                    Button(action: {
                        isPortraitModeActive.toggle()
                        Task {
                            await P2PMessageRouter.shared.route(.setPortraitMode(enabled: isPortraitModeActive))
                        }
                        lastActivityTime = Date()
                    }) {
                        Image(systemName: isPortraitModeActive ? "f.circle.fill" : "f.circle")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isPortraitModeActive ? Color.black : Color.white)
                            .frame(width: 38, height: 38)
                            .background(isPortraitModeActive ? Color.yellow : Color.black.opacity(0.35))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(isPortraitModeActive ? Color.yellow.opacity(0.4) : .white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                }
                
                Button(action: {
                    startManualCaptureSequence()
                }) {
                    Circle()
                        .fill(.white)
                        .frame(width: 78, height: 78)
                        .overlay(
                            Circle()
                                .stroke(.black.opacity(0.15), lineWidth: 5)
                                .padding(4)
                        )
                        .scaleEffect(isCapturing ? 0.90 : 1.0)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isCapturing)
                }
                .disabled(isCapturing)
                .padding(.bottom, 32)
            }
            .zIndex(15)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var doneButtonOverlay: some View {
        if localCountdown == 0 && !showFlash && !isBriefing {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        appState.navigateTo(.photoSelection)
                    }) {
                        HStack(spacing: 6) {
                            Text("Selesai")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 32)
            }
            .zIndex(16)
            .transition(.move(edge: .trailing).combined(with: .opacity))
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
