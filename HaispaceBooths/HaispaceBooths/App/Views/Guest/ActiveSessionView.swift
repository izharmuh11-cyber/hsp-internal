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
        // Transformasi Cermin Horizontal (Mirroring cermin alami: miring ke kiri bergerak ke kiri)
        displayLayer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0)
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
    @State private var activeFilter: String = "original"
    @State private var activeAperture: Double = 2.8
    @State private var showCameraControls: Bool = false
    
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
                
                // Full Screen Live Video Preview (Full Layar 100% Memenuhi iPad)
                fullScreenVideoFeed(geometry: screenGeo)
                
                // Panel Kontrol Melayang di Atas Video Full
                HStack {
                    // Control Dock Melayang di Kiri (Zoom 0.5x, 1x, 2x & Bokeh 'f')
                    leftControlDock(ipadLandscape: ipadLandscape)
                        .padding(.leading, 24)
                    
                    Spacer()
                    
                    // Galeri Polaroid Filmstrip Melayang di Kanan
                    filmStripGallery(ipadLandscape: ipadLandscape)
                        .padding(.trailing, 24)
                }
                
                // Header Sesi Melayang di Atas (Dynamic Island Top)
                timerAndQuotaHeader
                
                // Shutter Button, Filters & AI Pose Hint Melayang di Bawah
                VStack(spacing: 12) {
                    Spacer()
                    poseHintBanner
                    colorFilterSelectorGroup
                    shutterOnlyOverlay
                }
                
                poseOverlaySelection(ipadLandscape: ipadLandscape)
                doneButtonOverlay
            }
            
            // Briefing Overlay (Tampil sesaat sebelum sesi dimulai)
            briefingOverlayHelper
            
            // Selective Retake Premium Modal Overlay
            retakePremiumModal
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
            activeZoom = "1x"
            Task {
                await P2PMessageRouter.shared.route(.setZoom(factor: 1.0))
            }
            
            startSessionSequence()
            startGestureListener()
            
            // Set Vision AI callback
            StreamingDecoderService.shared.onFrameAnalyzed = { count, category, zoom, _ in
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
        gestureListenerTask = Task {
            for await _ in await P2PMessageRouter.shared.messageStream(for: .gestureDetected) {
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
                .font(.system(size: 160, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .zIndex(25)
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
    private func fullScreenVideoFeed(geometry: GeometryProxy) -> some View {
        ZStack {
            videoFeedView(geometry: geometry)
                .ignoresSafeArea()
            

            focusIndicatorOverlay
            
            // Overlay Flash (Saat jepretan dipicu)
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(10)
            }
            
            countdownOverlay
        }
    }
    
    @ViewBuilder
    private func leftControlDock(ipadLandscape: Bool) -> some View {
        if localCountdown == 0 && !showFlash && !isBriefing {
            VStack(spacing: 16) {
                if !isPortraitModeActive {
                    zoomSelectorGroup
                }
                portraitBokehButton
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 20, y: 10)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var zoomSelectorGroup: some View {
        let availableLenses = isPortraitModeActive ? ["1x"] : ["0.5x", "1x", "2x"]
        VStack(spacing: 6) {
            ForEach(availableLenses, id: \.self) { lens in
                Button(action: {
                    activeZoom = lens
                    let factor = lens == "0.5x" ? 0.5 : (lens == "2x" ? 2.0 : 1.0)
                    Task {
                        await P2PMessageRouter.shared.route(.setZoom(factor: factor))
                    }
                    lastActivityTime = Date()
                }) {
                    Text(lens)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(activeZoom == lens ? Color.black : Color.white)
                        .frame(width: 48, height: 38)
                        .background(activeZoom == lens ? Color.white : Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var portraitBokehButton: some View {
        Button(action: {
            isPortraitModeActive.toggle()
            if isPortraitModeActive {
                activeZoom = "1x"
                Task {
                    await P2PMessageRouter.shared.route(.setZoom(factor: 1.0))
                }
            }
            Task {
                await P2PMessageRouter.shared.route(.setPortraitMode(enabled: isPortraitModeActive))
            }
            lastActivityTime = Date()
        }) {
            VStack(spacing: 2) {
                Image(systemName: isPortraitModeActive ? "f.circle.fill" : "f.circle")
                    .font(.system(size: 18, weight: .bold))
                Text("Bokeh")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isPortraitModeActive ? Color.black : Color.white)
            .frame(width: 52, height: 50)
            .background(isPortraitModeActive ? Color(red: 255/255, green: 215/255, blue: 0/255) : Color.white.opacity(0.12))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isPortraitModeActive ? Color(red: 255/255, green: 215/255, blue: 0/255).opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private var apertureSelectorGroup: some View {
        let apertures: [(label: String, val: Double)] = [("f/1.4", 1.4), ("f/2.8", 2.8), ("f/5.6", 5.6)]
        VStack(spacing: 4) {
            ForEach(apertures, id: \.label) { ap in
                Button(action: {
                    activeAperture = ap.val
                    Task {
                        await P2PMessageRouter.shared.route(.setAperture(fNumber: ap.val))
                    }
                    lastActivityTime = Date()
                }) {
                    Text(ap.label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(activeAperture == ap.val ? Color.black : Color.white.opacity(0.85))
                        .frame(width: 46, height: 26)
                        .background(activeAperture == ap.val ? Color(red: 255/255, green: 215/255, blue: 0/255) : Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(3)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    @ViewBuilder
    private var colorFilterSelectorGroup: some View {
        let filters: [(id: String, name: String)] = [
            ("original", "Clean"),
            ("warm", "Warm"),
            ("clean", "Vogue"),
            ("vintage", "Retro"),
            ("bw_noir", "B&W")
        ]
        
        // Fixed Equal-Width Segment Bar (Pixel-Perfect Centered)
        HStack(spacing: 4) {
            ForEach(filters, id: \.id) { flt in
                let isSelected = activeFilter == flt.id
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activeFilter = flt.id
                    }
                    Task {
                        await P2PMessageRouter.shared.route(.setColorPreset(presetId: flt.id))
                    }
                    lastActivityTime = Date()
                }) {
                    Text(flt.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                        .frame(width: 66, height: 34)
                        .background(
                            ZStack {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: Color.white.opacity(0.3), radius: 6, y: 1)
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
    
    @ViewBuilder
    private var shutterOnlyOverlay: some View {
        if localCountdown == 0 && !showFlash && !isBriefing {
            Button(action: {
                startManualCaptureSequence()
            }) {
                ZStack {
                    // Outer Pulsing Glow Ring
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 110, height: 110)
                        .scaleEffect(isPulsing ? 1.08 : 0.98)
                        .opacity(isPulsing ? 0.3 : 0.8)
                    
                    // Main Outer Ring
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 96, height: 96)
                        .shadow(color: .white.opacity(0.5), radius: 8, y: 0)
                    
                    // Shutter Core
                    Circle()
                        .fill(LinearGradient(colors: [.white, Color(hex: "#E0E0E0")], startPoint: .top, endPoint: .bottom))
                        .frame(width: 80, height: 80)
                }
                .scaleEffect(isCapturing ? 0.88 : 1.0)
                .shadow(color: Color.black.opacity(0.5), radius: 18, y: 8)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturing)
            }
            .disabled(isCapturing)
            .padding(.bottom, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var poseHintBanner: some View {
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
    }
    
    @ViewBuilder
    private func poseOverlaySelection(ipadLandscape: Bool) -> some View {
        if showPoseOverlay && localCountdown == 0 && !showFlash && !isBriefing {
            let poseImages = getPoseImagesForCount(detectedFaceCount)
            if !poseImages.isEmpty {
                let assetName = poseImages[currentPoseIndex % poseImages.count]
                
                ZStack {
                    // Full-Screen Ghost Stencil Overlay (Translucent 100% Canvas Fit)
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .opacity(0.30) // Ghost overlay opacity so live camera is 100% visible underneath
                        .shadow(color: .white.opacity(0.5), radius: 2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    
                    // Full-Screen Swipe Gesture Receiver
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { gesture in
                                    let horizontalDrag = gesture.translation.width
                                    if horizontalDrag > 40 {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            currentPoseIndex = (currentPoseIndex - 1 + poseImages.count) % poseImages.count
                                        }
                                    } else if horizontalDrag < -40 {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            currentPoseIndex = (currentPoseIndex + 1) % poseImages.count
                                        }
                                    }
                                    lastActivityTime = Date()
                                }
                        )
                    
                    // Floating Ghost Control Pill (Atas Tengah, di bawah Header)
                    VStack {
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    currentPoseIndex = (currentPoseIndex - 1 + poseImages.count) % poseImages.count
                                }
                            }) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(red: 255/255, green: 215/255, blue: 0/255))
                                Text("GHOST POSE #\(currentPoseIndex % poseImages.count + 1)")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    currentPoseIndex = (currentPoseIndex + 1) % poseImages.count
                                }
                            }) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            Divider()
                                .frame(height: 14)
                                .background(Color.white.opacity(0.3))
                            
                            // Close Ghost Overlay
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showPoseOverlay = false
                                    lastActivityTime = Date()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Tutup")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 15, y: 6)
                        .padding(.top, 80)
                        
                        Spacer()
                    }
                }
                .zIndex(30)
                .transition(.opacity)
            }
        }
    }
    
    @ViewBuilder
    private func filmStripGallery(ipadLandscape: Bool) -> some View {
        if localCountdown == 0 && !showFlash && !isBriefing {
            VStack(spacing: 12) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        if let s = session {
                            ForEach(Array(s.photos.capturedPhotos.enumerated()), id: \.element.id) { index, photo in
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        activeSelectedPhotoForPreview = photo
                                    }
                                }) {
                                    if let uiImage = UIImage(data: photo.thumbnailData) {
                                        let isLandscape = uiImage.size.width > uiImage.size.height
                                        let thumbWidth: CGFloat = isLandscape ? 104 : 80
                                        let thumbHeight: CGFloat = isLandscape ? 78 : 104
                                        
                                        ZStack(alignment: .topLeading) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: thumbWidth, height: thumbHeight)
                                                .cornerRadius(14)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .stroke(LinearGradient(colors: [.white, .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                                                )
                                                .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                                                .rotationEffect(.degrees(index % 2 == 0 ? 2.5 : -2.5))
                                                .clipped()
                                            
                                            // Photo Index Badge
                                            Text("#\(index + 1)")
                                                .font(.system(size: 10, weight: .black, design: .rounded))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(.ultraThinMaterial)
                                                .background(Color.black.opacity(0.5))
                                                .clipShape(Capsule())
                                                .padding(6)
                                                .offset(x: index % 2 == 0 ? 4 : -4)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 120, height: ipadLandscape ? 480 : 360)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(14)
        }
    }
    
    @ViewBuilder
    private var timerAndQuotaHeader: some View {
        if localCountdown == 0 && !showFlash && !isBriefing {
            VStack {
                HStack {
                    // Unified iOS 18 Style Dynamic Island Pill
                    if let s = session {
                        HStack(spacing: 18) {
                            // Antrian
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.cyan)
                                Text("#\(String(format: "%03d", s.guest.queueNumber))")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            
                            Divider()
                                .frame(height: 14)
                                .background(Color.white.opacity(0.3))
                            
                            // Timer Status
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(s.remainingSeconds <= 30 ? Color.red : Color.green)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .stroke(s.remainingSeconds <= 30 ? Color.red : Color.green, lineWidth: 1.5)
                                            .scaleEffect(isPulsing ? 2.2 : 1.0)
                                            .opacity(isPulsing ? 0.0 : 1.0)
                                    )
                                    .onAppear {
                                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                            isPulsing = true
                                        }
                                    }
                                
                                Text("\(formatTime(s.remainingSeconds))")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(s.remainingSeconds <= 30 ? Color.red : Color.white)
                            }
                            
                            Divider()
                                .frame(height: 14)
                                .background(Color.white.opacity(0.3))
                            
                            // Quota
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "#7C5CFC"))
                                Text("\(s.photos.capturedCount)/\(s.package_.maxPhotoCount)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    }
                }
                .padding(.top, 24)
                
                Spacer()
            }
            .zIndex(18)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var retakePremiumModal: some View {
        if let selectedPhoto = activeSelectedPhotoForPreview {
            ZStack {
                // Deep Blur Glass Backdrop
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                Color.black.opacity(0.70)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeSelectedPhotoForPreview = nil
                        }
                    }
                
                // Apple QuickLook Style Floating Photo Preview
                VStack(spacing: 20) {
                    // Header Badge
                    Text("POSE #\(selectedPhoto.sortOrder + 1)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    
                    // Main Photo Display
                    if let uiImage = UIImage(data: selectedPhoto.thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 520)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.75), radius: 35, y: 15)
                    }
                    
                    // Clean Action Bar
                    HStack(spacing: 16) {
                        // Button Batal (Glass Pill)
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                activeSelectedPhotoForPreview = nil
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Tutup")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 120, height: 46)
                            .background(.ultraThinMaterial)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        
                        // Button Foto Ulang (Solid White Pill)
                        Button(action: {
                            let targetId = selectedPhoto.id
                            let targetOrder = selectedPhoto.sortOrder
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                activeSelectedPhotoForPreview = nil
                            }
                            startManualCaptureSequence(replacePhotoId: targetId, sortOrder: targetOrder)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Foto Ulang")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .frame(width: 150, height: 46)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .shadow(color: .white.opacity(0.3), radius: 10, y: 2)
                        }
                    }
                    .padding(.top, 4)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .zIndex(100)
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
