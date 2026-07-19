// OperatorDashboardView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Utama Operator Dashboard dengan desain Apple Wallet Card & Bento 2.0.
// Murni diterjemahkan dari komponen React UI terbaik untuk iPadOS Native SwiftUI.

import SwiftUI

struct OperatorDashboardView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isShowingPairingModal = false
    @State private var isShowingNewEventSheet = false
    @State private var isShowingEventManagerSheet = false
    
    // State Form Tambah/Edit Event
    @State private var editingEventId: String? = nil
    @State private var formName: String = ""
    @State private var formLocation: String = ""
    @State private var formPrice: String = "25000"
    @State private var formIsPaid: Bool = true
    @State private var formIconIndex: Int = 0
    @State private var formColorIndex: Int = 0
    
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
            
            VStack(spacing: 20) {
                // MARK: - 1. Top Navbar
                topNavbar
                
                // MARK: - 2. Event Tabs Scroller
                eventTabsScroller
                
                // MARK: - 3. Main Dashboard Grid (Wallet Card + Bento 2.0)
                if events.isEmpty || activeEvent == nil {
                    emptyStateDropzone
                } else if let currentEvent = activeEvent {
                    HStack(alignment: .top, spacing: 24) {
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
            .padding(.top, 24)
            .padding(.bottom, 28)
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
                Button(action: openCreateEventSheet) {
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
                                .stroke(isActive ? Color.white : Color(hex: "#E2E8F0").opacity(0.5), lineWidth: 1.5)
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
                    .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
                
                Image(systemName: "plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6366F1"))
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
            // Physical Card Body
            VStack(alignment: .leading, spacing: 0) {
                // Top Row (Badge + Edit Icon)
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
                            
                            Text(event.isPayPerSession ? "Mode Pembayaran Sesi" : "Mode Sewa Bebas")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                    }
                    
                    Spacer()
                    
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
                        
                        if event.isPayPerSession {
                            Text("Rp \(Int(event.pricePerSession).formatted())")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.25))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                        }
                    }
                }
                
                Spacer()
                
                // Embedded CTA inside Card: MULAI KIOSK
                Button(action: launchKioskSession) {
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
            }
            .padding(32)
            .frame(maxWidth: .infinity, minHeight: 460)
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
            bingkaiFilterWidget(event: event)
        }
    }
    
    private func topRowWidgets(event: EventModel) -> some View {
        HStack(spacing: 20) {
            // WIDGET 1: Revenue (Squircle White)
            VStack(alignment: .leading, spacing: 12) {
                Text("TOTAL OMSET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#94A3B8"))
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rp")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    
                    Text(formatRevenue(event.totalRevenue))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
            
            // WIDGET 2: Sessions (Dark Slate Card)
            VStack(alignment: .leading, spacing: 12) {
                Text("SESI FOTO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#94A3B8"))
                
                Spacer()
                
                HStack(alignment: .bottom) {
                    Text("\(event.totalSessions)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(Color(hex: "#0F172A"))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color(hex: "#0F172A").opacity(0.2), radius: 14, y: 6)
        }
    }
    
    private var cameraHardwareWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PERANGKAT P2P")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#94A3B8"))
                
                Spacer()
                
                Button(action: { isShowingPairingModal = true }) {
                    Text("Pairing QR")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#EEF2FF"))
                        .foregroundStyle(Color(hex: "#4F46E5"))
                        .clipShape(Capsule())
                }
            }
            
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "#FFEDD5"))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: "#EA580C"))
                }
                
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
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((appState.p2p.connectedPeerBatteryLevel ?? 0.85) * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    
                    // Custom Battery Bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "#CBD5E1"), lineWidth: 1.5)
                            .frame(width: 32, height: 14)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#10B981"))
                            .frame(width: 26 * (appState.p2p.connectedPeerBatteryLevel ?? 0.85), height: 9)
                            .padding(.leading, 2.5)
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "#F8FAFC"))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
    }
    
    private func bingkaiFilterWidget(event: EventModel) -> some View {
        Button(action: { openEditEventSheet(event) }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "#F3E8FF"))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "#9333EA"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bingkai & Filter Tone")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                    
                    Text("\(event.selectedFrameName) • \(event.selectedFilterName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "#64748B"))
                        .lineLimit(1)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color(hex: "#F1F5F9"))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#64748B"))
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color(hex: "#E2E8F0"), lineWidth: 1))
        }
    }
    
    // MARK: - Modal: New / Edit Event Sheet
    private var newEventModalSheet: some View {
        NavigationStack {
            Form {
                Section("DETAIL UTAMA") {
                    TextField("Nama Event (mis. Wisuda UNG 2026)", text: $formName)
                    TextField("Lokasi Booth", text: $formLocation)
                }
                
                Section("PENGATURAN HARGA") {
                    Toggle("Berbayar per Sesi (Tampilkan QRIS)", isOn: $formIsPaid)
                        .tint(Color(hex: "#4F46E5"))
                    
                    if formIsPaid {
                        HStack {
                            Text("Tarif per Sesi")
                            Spacer()
                            Text("Rp")
                                .foregroundStyle(.secondary)
                            TextField("25000", text: $formPrice)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .bold()
                        }
                    }
                }
                
                Section("IKON EVENT") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(0..<iconOptions.count, id: \.self) { idx in
                            let item = iconOptions[idx]
                            Button(action: { formIconIndex = idx }) {
                                HStack(spacing: 8) {
                                    Image(systemName: item.icon)
                                    Text(item.name)
                                        .font(.caption.bold())
                                }
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(formIconIndex == idx ? Color(hex: "#0F172A") : Color(hex: "#F1F5F9"))
                                .foregroundStyle(formIconIndex == idx ? .white : Color(hex: "#334155"))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section("TEMA WARNA KARTU") {
                    HStack(spacing: 14) {
                        ForEach(0..<colorOptions.count, id: \.self) { idx in
                            let c = colorOptions[idx]
                            Circle()
                                .fill(
                                    LinearGradient(colors: [Color(hex: c.startHex), Color(hex: c.endHex)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 36, height: 36)
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
                                    formColorIndex = idx
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
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
                    .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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
                            
                            Text("\(event.location) • \(event.totalSessions) Sesi")
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
        formPrice = "25000"
        formIsPaid = true
        formIconIndex = 0
        formColorIndex = 0
        isShowingNewEventSheet = true
    }
    
    private func openEditEventSheet(_ event: EventModel) {
        editingEventId = event.id
        formName = event.name
        formLocation = event.location
        formPrice = String(Int(event.pricePerSession))
        formIsPaid = event.isPayPerSession
        
        if let iconIdx = iconOptions.firstIndex(where: { $0.id == event.iconName }) {
            formIconIndex = iconIdx
        }
        if let colorIdx = colorOptions.firstIndex(where: { $0.hex == event.themeColorHex }) {
            formColorIndex = colorIdx
        }
        
        isShowingNewEventSheet = true
    }
    
    private func saveEvent() {
        let price = Double(formPrice) ?? 25000
        let iconName = iconOptions[formIconIndex].id
        let colorHex = colorOptions[formColorIndex].hex
        
        if let editId = editingEventId, let index = events.firstIndex(where: { $0.id == editId }) {
            appState.operatorState.availableEvents[index].name = formName
            appState.operatorState.availableEvents[index].location = formLocation.isEmpty ? "Lokasi Booth" : formLocation
            appState.operatorState.availableEvents[index].pricePerSession = price
            appState.operatorState.availableEvents[index].isPayPerSession = formIsPaid
            appState.operatorState.availableEvents[index].iconName = iconName
            appState.operatorState.availableEvents[index].themeColorHex = colorHex
            
            if appState.operatorState.activeEvent?.id == editId {
                appState.operatorState.activeEvent = appState.operatorState.availableEvents[index]
            }
        } else {
            let newEvt = EventModel(
                name: formName,
                location: formLocation.isEmpty ? "Lokasi Booth" : formLocation,
                pricePerSession: price,
                isPayPerSession: formIsPaid,
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
    
    private func formatRevenue(_ val: Double) -> String {
        if val >= 1_000_000 {
            let jt = val / 1_000_000
            return String(format: "%.1f Jt", jt).replacingOccurrences(of: ".0", with: "")
        } else {
            return Int(val).formatted()
        }
    }
}

#Preview {
    OperatorDashboardView()
        .environment(AppState.preview)
}
