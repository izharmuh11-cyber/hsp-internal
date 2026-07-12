// MissionControlView.swift
// HaispaceBooths — App/Views/Operator
//
// Sidebar panel kontrol utama untuk operator booth.
// Menggunakan desain premium "Apple Control Center" dengan visual kelas dunia.

import SwiftUI

struct MissionControlView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var offset: CGFloat = 400
    @State private var isShowingPairingSetup = false
    @State private var isShowingLogViewer = false
    
    var body: some View {
        ZStack {
            // Background overlay (frosted glass behind sidebar)
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }
            
            HStack {
                Spacer()
                
                // Sidebar Content (macOS Control Center Style)
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3.bold())
                            .foregroundStyle(Color(hex: "#7C5CFC"))
                        
                        Text("MISSION CONTROL")
                            .font(.system(.headline, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Button(action: close) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .padding(.bottom, 8)
                    
                    ScrollView(showsIndicators: false) {
                        scrollContent
                    }
                    
                    Spacer()
                    
                    // Logout Shift Button
                    Button(action: {
                        appState.operatorState.swapOperator()
                    }) {
                        HStack {
                            Image(systemName: "arrow.rectangle.portrait.and.arrow.right")
                                .font(.headline)
                            Text("Logout Shift")
                                .font(.system(.headline, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                    }
                }
                .padding(24)
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .background(
                    Color(hex: "#0A0A10")
                        .opacity(0.95)
                        .ignoresSafeArea()
                )
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 1)
                        Spacer()
                    }
                    .ignoresSafeArea()
                )
                .offset(x: offset)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        offset = 0
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingPairingSetup) {
            PairingSetupView()
        }
        .sheet(isPresented: $isShowingLogViewer) {
            LogViewerSheet()
        }
    }
    
    private func close() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            offset = 400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appState.operatorState.dismissMissionControl()
        }
    }
    
    @ViewBuilder
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            
            // 1. STATUS PERANGKAT
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "STATUS PERANGKAT", icon: "antenna.radiowaves.left.and.right")
                
                HStack(spacing: 12) {
                    StatusCard(
                        title: "HaiCamera",
                        value: "\(Int((appState.p2p.connectedPeerBatteryLevel ?? 0) * 100))%",
                        icon: (appState.p2p.connectedPeerBatteryLevel ?? 0) > 0.2 ? "battery.100" : "battery.25",
                        color: (appState.p2p.connectedPeerBatteryLevel ?? 0) > 0.2 ? .green : .red
                    )
                    
                    StatusCard(
                        title: "P2P Link",
                        value: appState.p2p.isConnected ? "Bagus" : "Terputus",
                        icon: appState.p2p.signalQuality.sfSymbol,
                        color: appState.p2p.isConnected ? .green : .red
                    )
                }
            }
            
            // 2. QUICK ACTIONS
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "QUICK ACTIONS", icon: "bolt.fill")
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ActionButton(title: "Reset Sesi", icon: "arrow.counterclockwise", color: .red) {
                        appState.currentSession?.reset()
                        appState.navigateTo(.landing)
                        close()
                    }
                    
                    ActionButton(title: "Pairing QR", icon: "qrcode.viewfinder", color: .purple) {
                        isShowingPairingSetup = true
                    }
                    
                    ActionButton(title: "Pause", icon: "pause.fill", color: .orange) {
                        Task {
                            await P2PMessageRouter.shared.route(.sessionPause)
                        }
                    }
                    
                    ActionButton(title: "+5 Menit", icon: "timer", color: .blue) {
                        appState.currentSession?.addTime(minutes: 5)
                    }
                }
            }
            
            // 3. FRAME AKTIF
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "FRAME AKTIF", icon: "photo.on.rectangle")
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FrameThumbnail(name: "Classic", isSelected: true)
                        FrameThumbnail(name: "Floral", isSelected: false)
                        
                        // Import Button
                        Button(action: {}) {
                            VStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.headline)
                                Text("Impor")
                                    .font(.caption.bold())
                            }
                            .frame(width: 80, height: 100)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(16)
                            .foregroundStyle(.white.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // 4. KONTROL KAMERA
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "KONTROL KAMERA", icon: "camera.aperture")
                
                VStack(spacing: 16) {
                    HStack {
                        Text("Lock AE/AF")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Button("Kunci") {
                            // P2P trigger lock
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#7C5CFC"))
                        .clipShape(Capsule())
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    HStack {
                        Text("Zoom")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Picker("Zoom", selection: .constant(1)) {
                            Text("1x").tag(1)
                            Text("2x").tag(2)
                            Text("3x").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            
            // 5. DIAGNOSTIK & LOGS
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "DIAGNOSTIK & LOGS", icon: "doc.text.magnifyingglass")
                
                HStack(spacing: 12) {
                    Button(action: {
                        isShowingLogViewer = true
                    }) {
                        HStack {
                            Image(systemName: "doc.plaintext")
                            Text("Lihat Log")
                        }
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(12)
                    }
                    
                    ShareLink(item: LocalLogWriter.readLogContent()) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Bagikan Log")
                        }
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color(hex: "#7C5CFC"))
            Text(title)
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.5)
        }
        .padding(.leading, 4)
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                
                Text(value)
                    .font(.system(.title3, design: .rounded))
                    .bold()
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 52)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(16)
        }
    }
}

private struct FrameThumbnail: View {
    let name: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 80, height: 100)
                .overlay(
                    isSelected ? RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#00D9A0"), lineWidth: 2.5) : nil
                )
                .cornerRadius(16)
                .shadow(color: isSelected ? Color(hex: "#00D9A0").opacity(0.2) : .clear, radius: 8)
            
            Text(name)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? Color(hex: "#00D9A0") : .white.opacity(0.5))
        }
    }
}

#Preview {
    MissionControlView()
        .environment(AppState.preview)
}
