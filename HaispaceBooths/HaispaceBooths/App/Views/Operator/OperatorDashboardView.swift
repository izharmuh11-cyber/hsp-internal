// OperatorDashboardView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Utama Operator Dashboard dengan desain Apple Wallet Card & Bento 2.0.
// Murni diterjemahkan dari komponen React UI terbaik untuk iPadOS Native SwiftUI.

import SwiftUI
import CoreImage.CIFilterBuiltins

enum KeyboardField {
    case name
    case location
}

struct OperatorDashboardView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isShowingPairingModal = false
    @State private var isShowingNewEventSheet = false
    @State private var isShowingEventManagerSheet = false
    
    // State Form Tambah/Edit Event
    @State private var editingEventId: String? = nil
    @State private var formName: String = ""
    @State private var formLocation: String = ""
    @State private var selectedPackageIds: Set<String> = ["pkg-std", "pkg-prem"]
    @State private var eventModalTab: Int = 0 // 0: Identitas & Tema, 1: Paket Harga (Multi-Select)
    @State private var formIconIndex: Int = 0
    @State private var formColorIndex: Int = 0
    
    // Keyboard & Feedback States
    @State private var activeKeyboardField: KeyboardField? = nil
    @State private var isBreathing = false
    @State private var kioskCountdown: Int? = nil
    @State private var countdownTimer: Timer? = nil
    
    private let iconOptions: [(icon: String, name: String, id: String)] = [
        ("academiccap.fill", "Wisuda", "academiccap"),
        ("sun.max.fill", "Pantai", "sun"),
        ("building.2.fill", "Kota", "building"),
        ("gift.fill", "Ultah", "gift"),
        ("music.note.house.fill", "Konser", "music"),
        ("camera.macro", "Studio", "camera")
    ]
    
    private let colorOptions: [(hex: String, name: String, startHex: String, endHex: String)] = [
        ("#4F46E5", "Indigo", "#6366F1", "#4F46E5"),
        ("#3B82F6", "Ocean Blue", "#3B82F6", "#1E40AF"),
        ("#10B981", "Emerald", "#34D399", "#059669"),
        ("#F59E0B", "Amber Gold", "#FBBF24", "#D97706"),
        ("#EC4899", "Rose Pink", "#F472B6", "#BE185D"),
        ("#8B5CF6", "Purple Glass", "#A78BFA", "#6D28D9"),
        ("#0F172A", "Midnight Dark", "#334155", "#0F172A")
    ]
    
    private var events: [EventModel] {
        appState.operatorState.availableEvents
    }
    
    private var activeEvent: EventModel? {
        appState.operatorState.activeEvent
    }
    
    private var activeTheme: (hex: String, name: String, startHex: String, endHex: String) {
        if let event = activeEvent,
           let theme = colorOptions.first(where: { $0.hex == event.themeColorHex }) {
            return theme
        }
        return colorOptions[0]
    }
    
    var body: some View {
        ZStack {
            // MARK: - Refined Apple Soft Ambient Background
            Color(hex: "#F4F4F5")
                .ignoresSafeArea()
            
            // Soft Blurred Color Meshes
            Circle()
                .fill(Color(hex: "#C7D2FE").opacity(0.40))
                .blur(radius: 120)
                .frame(width: 600, height: 600)
                .offset(x: -280, y: -240)
            
            Circle()
                .fill(Color(hex: "#BAE6FD").opacity(0.35))
                .blur(radius: 120)
                .frame(width: 550, height: 550)
                .offset(x: 340, y: 200)
            
            Circle()
                .fill(Color(hex: "#FEF3C7").opacity(0.30))
                .blur(radius: 130)
                .frame(width: 500, height: 500)
                .offset(x: -180, y: 280)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // MARK: - 1. Top Navbar
                    topNavbar
                        .padding(.top, 20)
                    
                    // MARK: - 2. Event Tabs Scroller
                    eventTabsScroller
                    
                    // MARK: - 3. Main Dashboard Grid (Wallet Card + Bento 2.0)
                    if events.isEmpty || activeEvent == nil {
                        emptyStateDropzone
                    } else if let currentEvent = activeEvent {
                        HStack(alignment: .top, spacing: 20) {
                            // Left Column: The Physical Wallet Card (Hero)
                            walletCardHero(event: currentEvent)
                                .frame(maxWidth: .infinity)
                            
                            // Right Column: Dashboard Widgets
                            rightColumnWidgets(event: currentEvent)
                                .frame(width: 420)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            
            // MARK: - Kiosk Countdown Overlay
            if let countdown = kioskCountdown {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            Text("\(countdown)")
                                .font(.system(size: 140, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .id("countdown-\(countdown)")
                            
                            Text("Bersiap Masuk Layar Pelanggan...")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    )
                    .zIndex(100)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $isShowingPairingModal) {
            PairingSetupView()
        }
        .sheet(isPresented: $isShowingNewEventSheet) {
            newEventModalSheet
        }
        .sheet(isPresented: $isShowingEventManagerSheet) {
            eventManagerModalSheet
        }
        .onAppear {
            setupQRPairingIfNeeded()
        }
    }
    
    // MARK: - 1. Top Navbar
    private var topNavbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                // Operator Avatar Box
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(hex: "#E2E8F0"), lineWidth: 1)
                        )
                        .frame(width: 48, height: 48)
                    
                    Text(String((appState.operatorState.currentOperator?.name ?? "Alex").prefix(1)))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#334155"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("HAISPACE BOOTH")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.5)
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    
                    Text("Dashboard")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
            }
            
            Spacer()
            
            // Hardware Quick Status Pill
            Button(action: { isShowingPairingModal = true }) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.orange)
                            .frame(width: 10, height: 10)
                        
                        Text(appState.p2p.isConnected ? "Kamera Aktif" : "Terputus")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: "#334155"))
                    }
                    
                    Divider()
                        .frame(height: 16)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100")
                            .foregroundStyle(Color(hex: "#10B981"))
                        Text("\(Int((appState.p2p.connectedPeerBatteryLevel ?? 0.85) * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#334155"))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.75))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
            }
            
            // Settings Button
            Button(action: { isShowingEventManagerSheet = true }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
                        .overlay(Circle().stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
                    
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: "#475569"))
                }
            }
        }
    }
    
    // MARK: - 2. Event Tabs Scroller
    private var eventTabsScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Tombol Baru (+ Baru)
                Button(action: {
                    playHaptic(style: .light)
                    openCreateEventSheet()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Baru")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#0F172A"))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color(hex: "#0F172A").opacity(0.2), radius: 8, y: 4)
                }
                .buttonStyle(BentoButtonStyle())
                
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                
                // Active Events Pills
                ForEach(events) { event in
                    let isActive = activeEvent?.id == event.id
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            appState.operatorState.activeEvent = event
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: event.iconName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(isActive ? Color(hex: event.themeColorHex) : Color(hex: "#64748B"))
                            
                            Text(event.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(isActive ? Color(hex: "#0F172A") : Color(hex: "#64748B"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            isActive
                            ? Color.white
                            : Color.white.opacity(0.45)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(
                            color: isActive ? Color.black.opacity(0.06) : Color.clear,
                            radius: 10, y: 4
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isActive ? Color(hex: event.themeColorHex) : Color(hex: "#E2E8F0").opacity(0.5), lineWidth: isActive ? 2 : 1)
                        )
                    }
                }
                
                if events.isEmpty {
                    Text("Belum ada event...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "#94A3B8"))
                        .italic()
                        .padding(.leading, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 3. Empty State Dropzone
    private var emptyStateDropzone: some View {
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.black.opacity(isBreathing ? 0.15 : 0.06), radius: isBreathing ? 24 : 16, y: isBreathing ? 12 : 8)
                
                Image(systemName: "plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6366F1"))
            }
            .scaleEffect(isBreathing ? 1.05 : 0.95)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
            
            VStack(spacing: 8) {
                Text("Mulai Haispace Booth")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
                
                Text("Buat event untuk mengatur sesi photobooth, integrasi harga QRIS, dan kustomisasi frame.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: "#64748B"))
                    .frame(maxWidth: 420)
            }
            
            Button(action: {
                playHaptic(style: .medium)
                withAnimation(.spring) {
                    appState.operatorState.loadPresetEvents()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(hex: "#F59E0B"))
                    Text("Muat Preset Dummy")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 24)
                .frame(height: 48)
                .background(Color.white)
                .foregroundStyle(Color(hex: "#334155"))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
                .overlay(Capsule().stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
            }
            .buttonStyle(BentoButtonStyle())
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(Color(hex: "#CBD5E1"), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
    }
    
    // MARK: - 4. The Wallet Card (Hero Card Kiri)
    private func walletCardHero(event: EventModel) -> some View {
        ZStack(alignment: .bottom) {
            // Radar Proximity Background Overlay
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 2)
                    .frame(width: 380, height: 380)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 260, height: 260)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: 140, height: 140)
            }
            .offset(x: 120, y: -60)
            
            // Physical Card Body
            VStack(alignment: .leading, spacing: 0) {
                // Top Row (Badge + Proximity Radar Pill + Edit Icon)
                HStack {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 46, height: 46)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1))
                            
                            Image(systemName: event.iconName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EVENT AKTIF")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(2)
                                .foregroundStyle(Color.white.opacity(0.7))
                            
                            Text(event.packageName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                    }
                    
                    Spacer()
                    
                    // Live Radar Proximity Indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(appState.p2p.isConnected ? "Radar Active" : "Scanning")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    
                    Button(action: { openEditEventSheet(event) }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                
                Spacer()
                
                // Event Title & Meta Badges
                VStack(alignment: .leading, spacing: 14) {
                    Text(event.name)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
                        .lineLimit(2)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption.bold())
                            Text(event.location)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        
                        Text("\(event.totalSessions) Sesi Berjalan")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }
                }
                
                Spacer()
                
                // Embedded CTA inside Card: MULAI KIOSK
                Button(action: startKioskCountdown) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MULAI KIOSK")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Color(hex: "#0F172A"))
                            
                            Text("Tap untuk Buka Layar Pelanggan")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#64748B"))
                        }
                        
                        Spacer()
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: "#0F172A"))
                                .frame(width: 56, height: 56)
                                .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 10)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
                }
                .buttonStyle(HeroCardButtonStyle())
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 410)
            .background(
                LinearGradient(
                    colors: [Color(hex: activeTheme.startHex), Color(hex: activeTheme.endHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .shadow(color: Color(hex: activeTheme.hex).opacity(0.35), radius: 24, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
            )
        }
    }
    
    // MARK: - 5. Right Column Widgets (Bento 2.0)
    private func rightColumnWidgets(event: EventModel) -> some View {
        VStack(spacing: 20) {
            topRowWidgets(event: event)
            cameraHardwareWidget
            liveSessionLogWidget(event: event)
        }
    }
    
    private func topRowWidgets(event: EventModel) -> some View {
        HStack(spacing: 20) {
            revenueWidget(event: event)
            sessionsWidget(event: event)
        }
    }
    
    private func revenueWidget(event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TOTAL OMSET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#94A3B8"))
                Spacer()
                Text("Realtime")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#10B981").opacity(0.12))
                    .foregroundStyle(Color(hex: "#10B981"))
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rp")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#94A3B8"))
                
                Text(formatRevenue(event.totalRevenue))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
            }
            
            // Mini Activity Spark Bars
            HStack(alignment: .bottom, spacing: 4) {
                ForEach([40, 65, 30, 85, 55, 95, 70], id: \.self) { val in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#4F46E5").opacity(Double(val) / 100.0))
                        .frame(height: CGFloat(val) * 0.25)
                }
            }
            .frame(height: 22)
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
    }
    
    private func sessionsWidget(event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SESI FOTO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#94A3B8"))
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            HStack(alignment: .bottom) {
                Text("\(event.totalSessions)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
            }
            
            // Mini Session Activity Bars
            HStack(alignment: .bottom, spacing: 4) {
                ForEach([50, 80, 45, 90, 60, 100, 75], id: \.self) { val in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(Double(val) / 100.0))
                        .frame(height: CGFloat(val) * 0.25)
                }
            }
            .frame(height: 22)
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .background(Color(hex: "#0F172A"))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color(hex: "#0F172A").opacity(0.2), radius: 14, y: 6)
    }
    
    private var cameraHardwareWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(appState.p2p.isConnected ? "KAMERA TERHUBUNG" : "PAIRING SECOND SHOOTER")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#94A3B8"))
                }
                
                Spacer()
                
                if appState.p2p.isConnected {
                    Button(action: {
                        playHaptic(style: .medium)
                        appState.p2p.disconnect()
                    }) {
                        Text("Putuskan")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            if appState.p2p.isConnected {
                cameraHardwareDeviceRow
            } else {
                embeddedQRPairingView
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
    }
    
    private var embeddedQRPairingView: some View {
        HStack(spacing: 16) {
            // Left: QR Code Thumbnail Button (Tap to Enlarge Modal)
            Button(action: {
                playHaptic(style: .light)
                isShowingPairingModal = true
            }) {
                ZStack {
                    if let payload = appState.p2p.currentQRPayload,
                       let qrImage = generateQRCodeImage(from: payload) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                    } else {
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("QR...")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: "#94A3B8"))
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .background(Color(hex: "#F8FAFC"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
            }
            .buttonStyle(BentoButtonStyle())
            
            // Right: Instructions & Quick Actions
            VStack(alignment: .leading, spacing: 6) {
                Text("Pindai via App HaiCamera")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
                
                Text("Scan QR di samping atau perbesar untuk pairing P2P")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "#64748B"))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // Perbesar Button
                    Button(action: {
                        playHaptic(style: .medium)
                        isShowingPairingModal = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 11, weight: .bold))
                            Text("Perbesar QR")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#EEF2FF"))
                        .foregroundStyle(Color(hex: "#4F46E5"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(BentoButtonStyle())
                    
                    // Refresh Button
                    Button(action: setupQRPairingIfNeeded) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#64748B"))
                            .padding(7)
                            .background(Color(hex: "#F1F5F9"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(BentoButtonStyle())
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func generateQRCodeImage(from payload: QRPairingPayload) -> UIImage? {
        guard let jsonData = try? JSONEncoder().encode(payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "H"
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 8, y: 8)
            let scaledImage = outputImage.transformed(by: transform)
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
    
    private func setupQRPairingIfNeeded() {
        let eventId = activeEvent?.id ?? "evt-default"
        let localIp = NetworkUtility.getWiFiAddress() ?? "127.0.0.1"
        appState.p2p.startGeneratingQRPayload(eventId: eventId, ip: localIp, port: 55123)
    }
    
    private var cameraHardwareDeviceRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "#FFEDD5"))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: "#EA580C"))
                }
                
                cameraHardwareDeviceDetails
                
                Spacer()
                
                cameraHardwareBatteryDetails
            }
            
            // Test Trigger Button
            Button(action: {
                playHaptic(style: .heavy)
            }) {
                HStack {
                    Image(systemName: "sparkles.tv")
                    Text("Tes Jepret / Flash Kamera")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(hex: "#EEF2FF"))
                .foregroundStyle(Color(hex: "#4F46E5"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(BentoButtonStyle())
        }
        .padding(14)
        .background(Color(hex: "#F8FAFC"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private var cameraHardwareDeviceDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appState.p2p.connectedPeerName ?? "iPhone 15 Pro Max")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "#0F172A"))
            
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.red)
                    .frame(width: 6, height: 6)
                
                Text(appState.p2p.isConnected ? "Online • Ping 12ms" : "Offline")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "#64748B"))
            }
        }
    }
    
    private func batteryColor(for level: Double) -> Color {
        if level > 0.5 { return Color(hex: "#10B981") }
        if level > 0.2 { return Color.orange }
        return Color.red
    }
    
    private var cameraHardwareBatteryDetails: some View {
        VStack(alignment: .trailing, spacing: 4) {
            let level = appState.p2p.connectedPeerBatteryLevel ?? 0.85
            let bColor = batteryColor(for: Double(level))
            
            Text("\(Int(level * 100))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "#94A3B8"))
            
            // Custom Battery Bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "#CBD5E1"), lineWidth: 1.5)
                    .frame(width: 32, height: 14)
                
                let batteryWidth = 26.0 * CGFloat(level)
                RoundedRectangle(cornerRadius: 2)
                    .fill(bColor)
                    .frame(width: batteryWidth, height: 9)
                    .padding(.leading, 2.5)
            }
        }
    }
    
    private func liveSessionLogWidget(event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack.fill")
                        .foregroundStyle(Color(hex: "#4F46E5"))
                    Text("AKTIVITAS & LOG SESI")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#94A3B8"))
                }
                Spacer()
                Text("Live Stream")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#4F46E5"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#EEF2FF"))
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: "#10B981"))
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sesi #\(max(1, event.totalSessions)) — Selesai & Dicetak")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#0F172A"))
                        Text("3 foto ditransfer via P2P • 2x Strip Print")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "#64748B"))
                    }
                    Spacer()
                    Text("Aktif")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#94A3B8"))
                }
                .padding(12)
                .background(Color(hex: "#F8FAFC"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
    }
    
    // MARK: - Modal: New / Edit Event Sheet (Authentic Apple System Sheet)
    private var newEventModalSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Segmented Control Header
                    Picker("Modal Tab", selection: $eventModalTab) {
                        Text("1. Identitas & Tema").tag(0)
                        Text("2. Paket Harga (\(selectedPackageIds.count) Aktif)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                    
                    if eventModalTab == 0 {
                        // Tab 1: Identitas & Tema Event
                        VStack(spacing: 20) {
                            // Header Banner Preview (Live Wallet Card Preview)
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(editingEventId == nil ? "BUAT EVENT BARU" : "EDIT EVENT")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .tracking(2)
                                        .foregroundStyle(Color(hex: "#4F46E5"))
                                    
                                    Text(formName.isEmpty ? "Nama Event Photobooth" : formName)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(hex: "#0F172A"))
                                    
                                    Text(formLocation.isEmpty ? "Lokasi Booth" : formLocation)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(hex: "#64748B"))
                                }
                                
                                Spacer()
                                
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color(hex: colorOptions[formColorIndex].startHex), Color(hex: colorOptions[formColorIndex].endHex)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 52, height: 52)
                                    
                                    Image(systemName: iconOptions[formIconIndex].icon)
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
                            
                            // Group 1: Informasi Utama (Nama Event & Lokasi with Direct Dropdown Keyboard)
                            VStack(alignment: .leading, spacing: 14) {
                                Text("INFORMASI UTAMA")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(1.5)
                                    .foregroundStyle(Color(hex: "#94A3B8"))
                                
                                VStack(spacing: 12) {
                                    // Field Nama Event
                                    VStack(spacing: 8) {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: "#EEF2FF"))
                                                    .frame(width: 38, height: 38)
                                                Image(systemName: "pencil.line")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(Color(hex: "#4F46E5"))
                                            }
                                            
                                            Text(formName.isEmpty ? "Nama Event (mis. Wisuda UNG 2026)" : formName)
                                                .font(.system(size: 16, weight: formName.isEmpty ? .regular : .bold, design: .rounded))
                                                .foregroundStyle(formName.isEmpty ? Color(hex: "#94A3B8") : Color(hex: "#0F172A"))
                                            
                                            Spacer()
                                            
                                            if activeKeyboardField == .name {
                                                Text("Sedang Mengetik")
                                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                                    .foregroundStyle(Color(hex: "#4F46E5"))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color(hex: "#EEF2FF"))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(14)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(activeKeyboardField == .name ? Color(hex: "#4F46E5") : Color(hex: "#E2E8F0"), lineWidth: activeKeyboardField == .name ? 2 : 1))
                                        .shadow(color: activeKeyboardField == .name ? Color(hex: "#4F46E5").opacity(0.12) : Color.black.opacity(0.02), radius: 8, y: 2)
                                        .onTapGesture {
                                            playHaptic(style: .light)
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                activeKeyboardField = activeKeyboardField == .name ? nil : .name
                                            }
                                        }
                                        
                                        // Inline Keyboard DIRECTLY UNDERNEATH Nama Event
                                        if activeKeyboardField == .name {
                                            CustomInAppKeyboard(text: $formName, onDone: {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                    activeKeyboardField = .location
                                                }
                                            })
                                            .transition(.move(edge: .top).combined(with: .opacity))
                                        }
                                    }
                                    
                                    // Field Lokasi Booth
                                    VStack(spacing: 8) {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: "#FEF3C7"))
                                                    .frame(width: 38, height: 38)
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(Color(hex: "#D97706"))
                                            }
                                            
                                            Text(formLocation.isEmpty ? "Lokasi Booth (mis. Auditorium UNG)" : formLocation)
                                                .font(.system(size: 16, weight: formLocation.isEmpty ? .regular : .bold, design: .rounded))
                                                .foregroundStyle(formLocation.isEmpty ? Color(hex: "#94A3B8") : Color(hex: "#0F172A"))
                                            
                                            Spacer()
                                            
                                            if activeKeyboardField == .location {
                                                Text("Sedang Mengetik")
                                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                                    .foregroundStyle(Color(hex: "#D97706"))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color(hex: "#FEF3C7"))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(14)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(activeKeyboardField == .location ? Color(hex: "#D97706") : Color(hex: "#E2E8F0"), lineWidth: activeKeyboardField == .location ? 2 : 1))
                                        .shadow(color: activeKeyboardField == .location ? Color(hex: "#D97706").opacity(0.12) : Color.black.opacity(0.02), radius: 8, y: 2)
                                        .onTapGesture {
                                            playHaptic(style: .light)
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                activeKeyboardField = activeKeyboardField == .location ? nil : .location
                                            }
                                        }
                                        
                                        // Inline Keyboard DIRECTLY UNDERNEATH Lokasi Booth
                                        if activeKeyboardField == .location {
                                            CustomInAppKeyboard(text: $formLocation, onDone: {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                    activeKeyboardField = nil
                                                }
                                            })
                                            .transition(.move(edge: .top).combined(with: .opacity))
                                        }
                                    }
                                }
                            }
                            
                            // Group 2: Tema & Ikon Card
                            newEventIconAndColorPickers
                        }
                    } else {
                        // Tab 2: Manajemen Paket Harga (Multi-Select)
                        newEventPackageSelectorCard
                    }
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(hex: "#F8FAFC"))
            .navigationTitle(editingEventId == nil ? "Event Baru" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { isShowingNewEventSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan & Buka Sesi") {
                        saveEvent()
                    }
                    .bold()
                    .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty || selectedPackageIds.isEmpty)
                }
            }
        }
    }
    
    private var newEventPackageSelectorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAKET HARGA AKTIF UNTUK EVENT INI")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    
                    Text("Centang paket mana saja yang akan ditawarkan di Kiosk Pelanggan")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "#64748B"))
                }
                
                Spacer()
                
                Text("\(selectedPackageIds.count) Paket Terpilih")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#4F46E5"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#EEF2FF"))
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 12) {
                ForEach(PricingPackage.presetPackages) { pkg in
                    let isSelected = selectedPackageIds.contains(pkg.id)
                    Button(action: {
                        playHaptic(style: .medium)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if isSelected {
                                if selectedPackageIds.count > 1 {
                                    selectedPackageIds.remove(pkg.id)
                                }
                            } else {
                                selectedPackageIds.insert(pkg.id)
                            }
                        }
                    }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? Color(hex: pkg.badgeColorHex) : Color(hex: "#F1F5F9"))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: isSelected ? "checkmark" : "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : Color(hex: "#94A3B8"))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(pkg.name)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(hex: "#0F172A"))
                                    
                                    Text(pkg.badgeText)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(hex: pkg.badgeColorHex).opacity(0.15))
                                        .foregroundStyle(Color(hex: pkg.badgeColorHex))
                                        .clipShape(Capsule())
                                }
                                
                                Text(pkg.description)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(hex: "#64748B"))
                            }
                            
                            Spacer()
                            
                            Text(pkg.price == 0 ? "GRATIS" : "Rp \(Int(pkg.price).formatted())")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(isSelected ? Color(hex: "#0F172A") : Color(hex: "#94A3B8"))
                        }
                        .padding(16)
                        .background(isSelected ? Color.white : Color.white.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 10, y: 4)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isSelected ? Color(hex: pkg.badgeColorHex) : Color(hex: "#E2E8F0"), lineWidth: isSelected ? 2 : 1))
                    }
                    .buttonStyle(BentoButtonStyle())
                }
            }
        }
    }
    
    private var newEventIconAndColorPickers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TEMA & IKON CARD")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#94A3B8"))
            
            VStack(alignment: .leading, spacing: 16) {
                // Ikon Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(0..<iconOptions.count, id: \.self) { idx in
                        let item = iconOptions[idx]
                        let isSel = formIconIndex == idx
                        Button(action: {
                            playHaptic(style: .light)
                            formIconIndex = idx
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                Text(item.name)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(isSel ? Color(hex: "#0F172A") : Color.white)
                            .foregroundStyle(isSel ? .white : Color(hex: "#334155"))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: isSel ? Color(hex: "#0F172A").opacity(0.15) : Color.black.opacity(0.02), radius: 6, y: 2)
                        }
                        .buttonStyle(BentoButtonStyle())
                    }
                }
                
                // Color Theme Circles
                HStack(spacing: 14) {
                    ForEach(0..<colorOptions.count, id: \.self) { idx in
                        let c = colorOptions[idx]
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color(hex: c.startHex), Color(hex: c.endHex)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: formColorIndex == idx ? 3 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: c.hex), lineWidth: formColorIndex == idx ? 2 : 0)
                                    .scaleEffect(1.2)
                            )
                            .onTapGesture {
                                playHaptic(style: .light)
                                formColorIndex = idx
                            }
                    }
                }
                .padding(.top, 6)
            }
            .padding(18)
            .background(Color.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
        }
    }
    
    // MARK: - Modal: Event Manager Modal
    private var eventManagerModalSheet: some View {
        NavigationStack {
            List {
                ForEach(events) { event in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#0F172A"))
                            
                            Text("\(event.location) • \(event.totalSessions) Sesi • \(event.packageName)")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#64748B"))
                        }
                        
                        Spacer()
                        
                        Button(role: .destructive, action: { deleteCurrentEvent(event.id) }) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("Pengaturan & Daftar Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { isShowingEventManagerSheet = false }
                }
            }
        }
    }
    
    // MARK: - Helpers & Actions
    private func openCreateEventSheet() {
        editingEventId = nil
        formName = ""
        formLocation = ""
        selectedPackageIds = ["pkg-std", "pkg-prem"]
        eventModalTab = 0
        formIconIndex = 0
        formColorIndex = 0
        activeKeyboardField = nil
        isShowingNewEventSheet = true
    }
    
    private func openEditEventSheet(_ event: EventModel) {
        editingEventId = event.id
        formName = event.name
        formLocation = event.location
        eventModalTab = 0
        activeKeyboardField = nil
        
        selectedPackageIds = Set(event.packageIds)
        if selectedPackageIds.isEmpty {
            selectedPackageIds = ["pkg-std"]
        }
        
        if let iconIdx = iconOptions.firstIndex(where: { $0.id == event.iconName }) {
            formIconIndex = iconIdx
        }
        if let colorIdx = colorOptions.firstIndex(where: { $0.hex == event.themeColorHex }) {
            formColorIndex = colorIdx
        }
        
        isShowingNewEventSheet = true
    }
    
    private func saveEvent() {
        let pkgIds = Array(selectedPackageIds)
        let primaryPkg = PricingPackage.presetPackages.first(where: { pkgIds.contains($0.id) }) ?? PricingPackage.presetPackages[0]
        let iconName = iconOptions[formIconIndex].id
        let colorHex = colorOptions[formColorIndex].hex
        
        if let editId = editingEventId, let index = events.firstIndex(where: { $0.id == editId }) {
            appState.operatorState.availableEvents[index].name = formName
            appState.operatorState.availableEvents[index].location = formLocation.isEmpty ? "Lokasi Booth" : formLocation
            appState.operatorState.availableEvents[index].pricePerSession = primaryPkg.price
            appState.operatorState.availableEvents[index].isPayPerSession = primaryPkg.isPayPerSession
            appState.operatorState.availableEvents[index].packageName = "\(pkgIds.count) Paket Aktif"
            appState.operatorState.availableEvents[index].packageIds = pkgIds
            appState.operatorState.availableEvents[index].iconName = iconName
            appState.operatorState.availableEvents[index].themeColorHex = colorHex
            
            if appState.operatorState.activeEvent?.id == editId {
                appState.operatorState.activeEvent = appState.operatorState.availableEvents[index]
            }
        } else {
            let newEvt = EventModel(
                name: formName,
                location: formLocation.isEmpty ? "Lokasi Booth" : formLocation,
                pricePerSession: primaryPkg.price,
                isPayPerSession: primaryPkg.isPayPerSession,
                packageName: "\(pkgIds.count) Paket Aktif",
                packageIds: pkgIds,
                totalSessions: 0,
                totalRevenue: 0,
                iconName: iconName,
                themeColorHex: colorHex
            )
            
            withAnimation(.spring) {
                appState.operatorState.addEvent(newEvt)
            }
        }
        
        isShowingNewEventSheet = false
    }
    
    private func deleteCurrentEvent(_ id: String) {
        withAnimation(.spring) {
            appState.operatorState.deleteEvent(id: id)
        }
    }
    
    private func launchKioskSession() {
        withAnimation(.spring) {
            appState.isKioskModeActive = true
            appState.navigateTo(.landing)
        }
    }
    
    private func startKioskCountdown() {
        playHaptic(style: .heavy)
        withAnimation { kioskCountdown = 3 }
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if let current = kioskCountdown {
                if current > 1 {
                    playHaptic(style: .medium)
                    withAnimation { kioskCountdown = current - 1 }
                } else {
                    timer.invalidate()
                    withAnimation { kioskCountdown = nil }
                    launchKioskSession()
                }
            }
        }
    }
    
    private func formatRevenue(_ val: Double) -> String {
        if val >= 1_000_000 {
            let jt = val / 1_000_000
            return String(format: "%.1f Jt", jt).replacingOccurrences(of: ".0", with: "")
        } else {
            return Int(val).formatted()
        }
    }
}

// MARK: - UI Utilities

struct BentoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct HeroCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .rotation3DEffect(
                .degrees(configuration.isPressed ? 2 : 0),
                axis: (x: 1.0, y: 0.0, z: 0.0)
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

func playHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.prepare()
    generator.impactOccurred()
}

#Preview {
    OperatorDashboardView()
        .environment(AppState.preview)
}
