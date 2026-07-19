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
    @State private var newEventName: String = ""
    @State private var newEventLocation: String = ""
    @State private var newEventPrice: String = "25000"
    
    private var activeEvent: EventModel {
        appState.operatorState.activeEvent ?? EventModel.samples[0]
    }
    
    var body: some View {
        ZStack {
            // Background Light Soft Pastel Aura (Apple Home Style)
            LinearGradient(
                colors: [Color(hex: "#F8FAFC"), Color(hex: "#F1F5F9"), Color(hex: "#E2E8F0")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Ambient soft glowing color meshes
            Circle()
                .fill(Color(hex: "#C7D2FE").opacity(0.45))
                .blur(radius: 100)
                .frame(width: 500, height: 500)
                .offset(x: -250, y: -200)
            
            Circle()
                .fill(Color(hex: "#A7F3D0").opacity(0.35))
                .blur(radius: 100)
                .frame(width: 450, height: 450)
                .offset(x: 300, y: 250)
            
            VStack(spacing: 24) {
                // MARK: - Header Bar
                headerBar
                
                // MARK: - Bento Grid Main Area
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Top Row: Active Event Hero + Camera Hardware Card
                        HStack(spacing: 20) {
                            activeEventHeroTile
                                .frame(maxWidth: .infinity)
                            
                            cameraHardwareTile
                                .frame(width: 340)
                        }
                        
                        // Bottom Row: Analytics & Quick Presets
                        HStack(spacing: 20) {
                            revenueAnalyticsTile
                                .frame(maxWidth: .infinity)
                            
                            presetsAndFramesTile
                                .frame(maxWidth: .infinity)
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
    }
    
    // MARK: - Header Bar Component
    private var headerBar: some View {
        HStack(spacing: 16) {
            // App Title & Operator Name
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#4F46E5"))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "camera.aperture")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("H A I S P A C E")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color(hex: "#0F172A"))
                    
                    Text("Halo, \(appState.operatorState.currentOperator?.name ?? "Operator")")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                }
            }
            
            Spacer()
            
            // Event Pill Selector Tabs
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
                                event.id == activeEvent.id
                                ? Color(hex: "#4F46E5")
                                : Color.white.opacity(0.8)
                            )
                            .foregroundStyle(
                                event.id == activeEvent.id ? .white : Color(hex: "#334155")
                            )
                            .clipShape(Capsule())
                            .shadow(
                                color: event.id == activeEvent.id
                                ? Color(hex: "#4F46E5").opacity(0.25)
                                : Color.black.opacity(0.04),
                                radius: 8, y: 4
                            )
                        }
                    }
                    
                    // Button tambah event baru
                    Button(action: { isShowingNewEventSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Event Baru")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.9))
                        .foregroundStyle(Color(hex: "#4F46E5"))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(hex: "#818CF8").opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Camera Connection Pill Badge
            Button(action: { isShowingPairingModal = true }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.p2p.isConnected ? Color(hex: "#10B981") : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(appState.p2p.isConnected ? "HaiCamera 🟢 \(Int((appState.p2p.connectedPeerBatteryLevel ?? 0.85) * 100))%" : "Kamera Belum Terhubung")
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
    
    // MARK: - Tile 1: Active Event Hero
    private var activeEventHeroTile: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: activeEvent.themeColorHex))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: activeEvent.iconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    Text("EVENT AKTIF SEKARANG")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#64748B"))
                }
                
                Spacer()
                
                Text(activeEvent.isPayPerSession ? "BERBAYAR" : "GRATIS / SEWA")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: activeEvent.themeColorHex).opacity(0.12))
                    .foregroundStyle(Color(hex: activeEvent.themeColorHex))
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(activeEvent.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0F172A"))
                
                HStack(spacing: 16) {
                    Label(activeEvent.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: "#475569"))
                    
                    if activeEvent.isPayPerSession {
                        Text("•")
                            .foregroundStyle(Color(hex: "#94A3B8"))
                        Text("Rp \(Int(activeEvent.pricePerSession).formatted()) / sesi")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                }
            }
            
            Divider()
                .background(Color.black.opacity(0.06))
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL SESI")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    Text("\(activeEvent.totalSessions) Foto")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#1E293B"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("ESTIMASI OMSET")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#94A3B8"))
                    Text("Rp \(Int(activeEvent.totalRevenue).formatted())")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#10B981"))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Tile 2: Camera & Hardware Tile
    private var cameraHardwareTile: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#F97316"))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("KAMERA PERANGKAT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Text(appState.p2p.connectedPeerName ?? "iPhone 14 Pro")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Status Koneksi")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Spacer()
                    Text(appState.p2p.isConnected ? "Terhubung P2P" : "Terputus")
                        .font(.subheadline.bold())
                        .foregroundStyle(appState.p2p.isConnected ? Color(hex: "#10B981") : .orange)
                }
                
                HStack {
                    Text("Daya Baterai")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Spacer()
                    Text("\(Int((appState.p2p.connectedPeerBatteryLevel ?? 0.85) * 100))%")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                HStack {
                    Text("Latensi P2P")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Spacer()
                    Text("12 ms (Lancar)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#3B82F6"))
                }
            }
            .padding(14)
            .background(Color(hex: "#F8FAFC"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            Button(action: { isShowingPairingModal = true }) {
                HStack {
                    Image(systemName: "qrcode")
                    Text(appState.p2p.isConnected ? "Re-Pairing Kamera" : "Scan QR Pairing Kamera")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: "#F97316").opacity(0.12))
                .foregroundStyle(Color(hex: "#F97316"))
                .clipShape(Capsule())
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Tile 3: Revenue Analytics Tile
    private var revenueAnalyticsTile: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#10B981"))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Text("REKAP PEMBAYARAN EVENT")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: "#64748B"))
                
                Spacer()
            }
            
            HStack(spacing: 24) {
                // Simple ring gauge illustration
                ZStack {
                    Circle()
                        .stroke(Color(hex: "#E2E8F0"), lineWidth: 10)
                        .frame(width: 72, height: 72)
                    
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color(hex: "#10B981"), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                    
                    Text("75%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0F172A"))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: "#10B981")).frame(width: 8, height: 8)
                        Text("QRIS Digital:")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#64748B"))
                        Text("75% (36 Sesi)")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: "#0F172A"))
                    }
                    
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: "#CBD5E1")).frame(width: 8, height: 8)
                        Text("Tunai / Manual:")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#64748B"))
                        Text("25% (12 Sesi)")
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
                .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
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
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#8B5CF6"))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Text("FRAME & TONE PRESET")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: "#64748B"))
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame Bingkai")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Text("4 Ready")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#8B5CF6"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(hex: "#8B5CF6").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cinematic Tone")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#64748B"))
                    Text("Portrait Active")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
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
                .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
        )
    }
    
    // MARK: - Bottom Launch Bar Button
    private var bottomLaunchBar: some View {
        Button(action: launchKioskSession) {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2.bold())
                
                Text("🚀 LAUNCH KIOSK SESSION (\(activeEvent.name))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#10B981"), Color(hex: "#059669")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: Color(hex: "#10B981").opacity(0.35), radius: 18, y: 8)
        }
    }
    
    // MARK: - New Event Sheet Modal
    private var newEventModalSheet: some View {
        NavigationStack {
            Form {
                Section("Detail Event Baru") {
                    TextField("Nama Event (misal: Wisuda UNG)", text: $newEventName)
                    TextField("Lokasi (misal: Auditorium UNG)", text: $newEventLocation)
                    TextField("Harga per Sesi (Rp)", text: $newEventPrice)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Buat Event Baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { isShowingNewEventSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        let price = Double(newEventPrice) ?? 25000
                        let newEvt = EventModel(
                            name: newEventName.isEmpty ? "Event Baru" : newEventName,
                            location: newEventLocation.isEmpty ? "Lokasi Booth" : newEventLocation,
                            pricePerSession: price
                        )
                        appState.operatorState.availableEvents.append(newEvt)
                        appState.operatorState.activeEvent = newEvt
                        isShowingNewEventSheet = false
                        newEventName = ""
                        newEventLocation = ""
                    }
                    .bold()
                }
            }
        }
    }
    
    // MARK: - Actions
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
