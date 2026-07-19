// OperatorDashboardView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar Utama Operator Dashboard dengan desain Light Bento Grid Glassmorphism.
// Berdasarkan konsep visual Apple Home / Apple Wallet yang disetujui.
// Mengelola Event, Pairing Kamera P2P, dan Peluncuran Kiosk Mode.

import SwiftUI

struct OperatorDashboardView: View {
    @Environment(AppState.self) private var appState
    
    @State private var isShowingPairingModal = false
    @State private var isShowingNewEventSheet = false
    @State private var isShowingEventManagerSheet = false
    @State private var isShowingDeleteConfirm = false
    @State private var eventToDeleteId: String? = nil
    
    // Form State untuk Tambah Event Baru
    @State private var newEventName: String = ""
    @State private var newEventLocation: String = ""
    @State private var newEventPrice: String = "25000"
    @State private var newEventIsPayPerSession: Bool = true
    @State private var selectedIconIndex = 0
    @State private var selectedColorIndex = 0
    
    private let iconOptions = [
        ("academiccap.fill", "Wisuda"),
        ("sun.max.fill", "Pantai"),
        ("building.2.fill", "Kota / Mall"),
        ("gift.fill", "Ulang Tahun"),
        ("music.note.house.fill", "Konser / Music"),
        ("camera.macro", "Studio")
    ]
    
    private let colorOptions = [
        ("#4F46E5", "Indigo"),
        ("#3B82F6", "Blue"),
        ("#10B981", "Emerald"),
        ("#F59E0B", "Amber"),
        ("#EC4899", "Pink"),
        ("#8B5CF6", "Purple")
    ]
    
    private var activeEvent: EventModel? {
        appState.operatorState.activeEvent
    }
    
    var body: some View {
        ZStack {
            // MARK: - Background Light Soft Pastel Aura (Apple Home / Wallet Style)
            LinearGradient(
                colors: [Color(hex: "#F8FAFC"), Color(hex: "#F1F5F9"), Color(hex: "#E2E8F0")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Ambient soft glowing color meshes
            Circle()
                .fill(Color(hex: "#C7D2FE").opacity(0.40))
                .blur(radius: 110)
                .frame(width: 520, height: 520)
                .offset(x: -260, y: -220)
            
            Circle()
                .fill(Color(hex: "#A7F3D0").opacity(0.35))
                .blur(radius: 110)
                .frame(width: 480, height: 480)
                .offset(x: 320, y: 260)
            
            Circle()
                .fill(Color(hex: "#FDE68A").opacity(0.25))
                .blur(radius: 120)
                .frame(width: 400, height: 400)
                .offset(x: -150, y: 200)
            
            VStack(spacing: 20) {
                // MARK: - Header Bar
                headerBar
                
                // MARK: - Bento Grid Main Area
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if appState.operatorState.availableEvents.isEmpty || activeEvent == nil {
                            // Layar Kosong jika belum ada Event yang dibuat
                            emptyEventStateTile
                        } else if let currentEvent = activeEvent {
                            // Top Row: Active Event Hero + Camera Hardware Card
                            HStack(spacing: 20) {
                                activeEventHeroTile(event: currentEvent)
                                    .frame(maxWidth: .infinity)
                                
                                cameraHardwareTile
                                    .frame(width: 340)
                            }
                            
                            // Bottom Row: Analytics & Presets
                            HStack(spacing: 20) {
                                revenueAnalyticsTile(event: currentEvent)
                                    .frame(maxWidth: .infinity)
                                
                                presetsAndFramesTile
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - Bottom Action Bar (Launch Kiosk)
                bottomLaunchBar
            }
            .padding(28)
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
    
    // MARK: - Header Bar Component
    private var headerBar: some View {
        HStack(spacing: 16) {
            // App Title & Operator Profile
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#6366F1"), Color(hex: "#4F46E5")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color(hex: "#4F46E5").opacity(0.3), radius: 8, y: 4)
                    
                    Image(systemName: "camera.aperture")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("HAISPACE BOOTH")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(hex: "#0F172A"))
                    
                    Text("Halo, \(appState.operatorState.currentOperator?.name ?? "Operator")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: "#64748B"))
                }
            }
            
            Spacer()
            
            // Event Pill Selector Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.operatorState.availableEvents) { event in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                appState.operatorState.activeEvent = event
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: event.iconName)
                                    .font(.caption.bold())
                                Text(event.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                activeEvent?.id == event.id
                                ? Color(hex: event.themeColorHex)
                                : Color.white.opacity(0.85)
                            )
                            .foregroundStyle(
                                activeEvent?.id == event.id ? .white : Color(hex: "#334155")
                            )
                            .clipShape(Capsule())
                            .shadow(
                                color: activeEvent?.id == event.id
                                ? Color(hex: event.themeColorHex).opacity(0.3)
                                : Color.black.opacity(0.04),
                                radius: 8, y: 4
                            )
                        }
                    }
                    
                    // Tombol Tambah Event (+)
                    Button(action: { isShowingNewEventSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.subheadline.bold())
                            Text("Event Baru")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .foregroundStyle(Color(hex: "#4F46E5"))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: "#6366F1").opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Kelola Event Drawer Toggle
            if !appState.operatorState.availableEvents.isEmpty {
                Button(action: { isShowingEventManagerSheet = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "#475569"))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 3)
                }
            }
            
            // Camera Connection Status Badge
            Button(action: { isShowingPairingModal = true }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(appState.p2p.isConnected ? "HaiCamera 🟢 \(Int((appState.p2p.connectedPeerBatteryLevel ?? 0.85) * 100))%" : "Pairing Kamera")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: "#1E293B"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.9))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
            }
        }
    }
    
    // MARK: - Tile 0: Empty Event State Tile (Tampilan saat belum ada event)
    private var emptyEventStateTile: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#EEF2FF"), Color(hex: "#E0E7FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color(hex: "#4F46E5"))
            }
            
            VStack(spacing: 10) {
                Text("Belum Ada Event Aktif")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
                
                Text("Buat event pertama kamu untuk menentukan lokasi photobooth, tarif per sesi, dan kustomisasi tampilan landing page.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: "#64748B"))
                    .frame(maxWidth: 520)
            }
            
            HStack(spacing: 16) {
                Button(action: { isShowingNewEventSheet = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3.bold())
                        Text("Buat Event Pertama Baru")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#6366F1"), Color(hex: "#4F46E5")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#4F46E5").opacity(0.35), radius: 14, y: 6)
                }
                
                Button(action: {
                    withAnimation(.spring) {
                        appState.operatorState.loadPresetEvents()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Muat 4 Preset Event Contoh")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .background(Color.white)
                    .foregroundStyle(Color(hex: "#475569"))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(hex: "#CBD5E1"), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
                }
            }
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.05), radius: 24, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    StrokeStyle(lineWidth: 2, dash: [8, 6]),
                    fill: Color(hex: "#CBD5E1")
                )
        )
    }
    
    // MARK: - Tile 1: Active Event Hero Tile
    private func activeEventHeroTile(event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: event.themeColorHex))
                            .frame(width: 38, height: 38)
                            .shadow(color: Color(hex: event.themeColorHex).opacity(0.35), radius: 6, y: 3)
                        
                        Image(systemName: event.iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EVENT AKTIF SEKARANG")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(Color(hex: "#64748B"))
                        
                        Text(event.isPayPerSession ? "Sistem Berbayar per Sesi" : "Sewa / Free Sessions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hex: "#94A3B8"))
                    }
                }
                
                Spacer()
                
                // Action menu kelola event ini
                Menu {
                    Button(action: { editEvent(event) }) {
                        Label("Edit Detail Event", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: { confirmDeleteEvent(event.id) }) {
                        Label("Hapus Event Ini", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: "#94A3B8"))
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(event.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
                
                HStack(spacing: 16) {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "#475569"))
                    
                    if event.isPayPerSession {
                        Text("•")
                            .foregroundStyle(Color(hex: "#CBD5E1"))
                        
                        Text("Rp \(Int(event.pricePerSession).formatted()) / sesi")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                }
            }
            
            Divider()
                .background(Color(hex: "#E2E8F0"))
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL SESI SELESAI")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    
                    Text("\(event.totalSessions) Sesi Foto")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL OMSET TERCATAT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    
                    Text("Rp \(Int(event.totalRevenue).formatted())")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Tile 2: Camera Hardware Tile
    private var cameraHardwareTile: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#FB923C"), Color(hex: "#F97316")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color(hex: "#F97316").opacity(0.3), radius: 6, y: 3)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("KAMERA PERANGKAT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Text(appState.p2p.connectedPeerName ?? "iPhone (Belum Paired)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                Spacer()
            }
            
            VStack(spacing: 10) {
                HStack {
                    Text("Status P2P")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Spacer()
                    Text(appState.p2p.isConnected ? "Terhubung" : "Terputus")
                        .font(.subheadline.bold())
                        .foregroundStyle(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.orange)
                }
                
                HStack {
                    Text("Baterai Kamera")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Spacer()
                    Text("\(Int((appState.p2p.connectedPeerBatteryLevel ?? 0.85) * 100))%")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                HStack {
                    Text("Kualitas Sinyal")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Spacer()
                    Text(appState.p2p.isConnected ? "Sangat Baik (12ms)" : "-")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#3B82F6"))
                }
            }
            .padding(14)
            .background(Color(hex: "#F8FAFC"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            Button(action: { isShowingPairingModal = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                    Text(appState.p2p.isConnected ? "Re-Pairing Kamera" : "Scan QR Pairing Kamera")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: "#F97316").opacity(0.12))
                .foregroundStyle(Color(hex: "#EA580C"))
                .clipShape(Capsule())
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Tile 3: Revenue Analytics Tile
    private func revenueAnalyticsTile(event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#34D399"), Color(hex: "#10B981")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color(hex: "#10B981").opacity(0.3), radius: 6, y: 3)
                    
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Text("REKAP SINKRONISASI EVENT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: "#64748B"))
                
                Spacer()
            }
            
            HStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "#E2E8F0"), lineWidth: 10)
                        .frame(width: 72, height: 72)
                    
                    Circle()
                        .trim(from: 0, to: event.totalSessions > 0 ? 0.75 : 0.0)
                        .stroke(Color(hex: "#10B981"), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                    
                    Text(event.totalSessions > 0 ? "75%" : "0%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: "#10B981")).frame(width: 8, height: 8)
                        Text("QRIS Auto Payment:")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#64748B"))
                        Text("\(Int(Double(event.totalSessions) * 0.75)) Sesi")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                    
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: "#CBD5E1")).frame(width: 8, height: 8)
                        Text("Voucher / Manual:")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#64748B"))
                        Text("\(Int(Double(event.totalSessions) * 0.25)) Sesi")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Tile 4: Presets & Frames Tile
    private var presetsAndFramesTile: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#A78BFA"), Color(hex: "#8B5CF6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color(hex: "#8B5CF6").opacity(0.3), radius: 6, y: 3)
                    
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Text("BINGKAI & TONE COLOR")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: "#64748B"))
                
                Spacer()
            }
            
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layout Frame")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Text("4 Ready")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#8B5CF6"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(hex: "#8B5CF6").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filter Warna")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Text("Cinematic Soft")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(hex: "#10B981").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Bottom Launch Bar Button
    private var bottomLaunchBar: some View {
        Group {
            if let currentEvent = activeEvent {
                Button(action: launchKioskSession) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2.bold())
                        
                        Text("🚀 MULAI SESI EVENT (\(currentEvent.name.uppercased()))")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#10B981"), Color(hex: "#059669")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#10B981").opacity(0.35), radius: 16, y: 6)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                    Text("Buat atau Pilih Event Terlebih Dahulu untuk Membuka Sesi Photobooth")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white.opacity(0.8))
                .foregroundStyle(Color(hex: "#64748B"))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: "#CBD5E1"), lineWidth: 1))
            }
        }
    }
    
    // MARK: - New Event Modal Sheet
    private var newEventModalSheet: some View {
        NavigationStack {
            Form {
                Section("INFORMASI NAMA & LOKASI") {
                    TextField("Nama Event (contoh: Wisuda UNG 2026)", text: $newEventName)
                    TextField("Lokasi Venue (contoh: Auditorium UNG)", text: $newEventLocation)
                }
                
                Section("TIPE TRANSAKSI & HARGA SESI") {
                    Toggle("Berbayar per Sesi Foto", isOn: $newEventIsPayPerSession)
                        .tint(Color(hex: "#4F46E5"))
                    
                    if newEventIsPayPerSession {
                        HStack {
                            Text("Tarif per Sesi")
                            Spacer()
                            Text("Rp")
                                .foregroundStyle(.secondary)
                            TextField("25000", text: $newEventPrice)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .bold()
                        }
                    }
                }
                
                Section("IKON EVENT") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(0..<iconOptions.count, id: \.self) { index in
                            let item = iconOptions[index]
                            Button(action: { selectedIconIndex = index }) {
                                HStack(spacing: 8) {
                                    Image(systemName: item.0)
                                    Text(item.1)
                                        .font(.caption.bold())
                                }
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(selectedIconIndex == index ? Color(hex: colorOptions[selectedColorIndex].0) : Color(hex: "#F1F5F9"))
                                .foregroundStyle(selectedIconIndex == index ? .white : Color(hex: "#334155"))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section("TEMA WARNA TAMPILAN") {
                    HStack(spacing: 16) {
                        ForEach(0..<colorOptions.count, id: \.self) { index in
                            let colorHex = colorOptions[index].0
                            Circle()
                                .fill(Color(hex: colorHex))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColorIndex == index ? 3 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(hex: colorHex), lineWidth: selectedColorIndex == index ? 2 : 0)
                                        .scaleEffect(1.2)
                                )
                                .onTapGesture {
                                    selectedColorIndex = index
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Buat Event Baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { isShowingNewEventSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan & Aktifkan") {
                        saveNewEvent()
                    }
                    .bold()
                    .disabled(newEventName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    // MARK: - Event Manager Drawer Modal
    private var eventManagerModalSheet: some View {
        NavigationStack {
            List {
                ForEach(appState.operatorState.availableEvents) { event in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: event.themeColorHex).opacity(0.15))
                                .frame(width: 42, height: 42)
                            
                            Image(systemName: event.iconName)
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(hex: event.themeColorHex))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#0F172A"))
                            
                            Text("\(event.location) • \(event.totalSessions) Sesi")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#64748B"))
                        }
                        
                        Spacer()
                        
                        if activeEvent?.id == event.id {
                            Text("AKTIF")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#10B981").opacity(0.15))
                                .foregroundStyle(Color(hex: "#10B981"))
                                .clipShape(Capsule())
                        } else {
                            Button("Pilih") {
                                appState.operatorState.activeEvent = event
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            appState.operatorState.deleteEvent(id: event.id)
                        } label: {
                            Label("Hapus", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Kelola Daftar Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { isShowingEventManagerSheet = false }
                }
            }
        }
    }
    
    // MARK: - Actions & Helpers
    private func saveNewEvent() {
        let price = Double(newEventPrice) ?? 25000
        let iconName = iconOptions[selectedIconIndex].0
        let colorHex = colorOptions[selectedColorIndex].0
        
        let newEvt = EventModel(
            name: newEventName,
            location: newEventLocation.isEmpty ? "Lokasi Booth" : newEventLocation,
            pricePerSession: price,
            isPayPerSession: newEventIsPayPerSession,
            totalSessions: 0,
            totalRevenue: 0,
            iconName: iconName,
            themeColorHex: colorHex
        )
        
        withAnimation(.spring) {
            appState.operatorState.addEvent(newEvt)
        }
        
        // Reset form
        newEventName = ""
        newEventLocation = ""
        newEventPrice = "25000"
        isShowingNewEventSheet = false
    }
    
    private func editEvent(_ event: EventModel) {
        newEventName = event.name
        newEventLocation = event.location
        newEventPrice = String(Int(event.pricePerSession))
        newEventIsPayPerSession = event.isPayPerSession
        isShowingNewEventSheet = true
    }
    
    private func confirmDeleteEvent(_ eventId: String) {
        withAnimation(.spring) {
            appState.operatorState.deleteEvent(id: eventId)
        }
    }
    
    private func launchKioskSession() {
        withAnimation(.spring) {
            appState.isKioskModeActive = true
            appState.navigateTo(.landing)
        }
    }
}

#Preview {
    OperatorDashboardView()
        .environment(AppState.preview)
}
