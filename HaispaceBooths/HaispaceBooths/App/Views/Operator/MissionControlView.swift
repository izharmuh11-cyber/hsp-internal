// MissionControlView.swift
// HaispaceBooths — App/Views/Operator
//
// Sidebar rahasia untuk operator (Mission Control).
// Menampilkan status P2P, baterai, dan kontrol operasional.
// Data finansial tidak ditampilkan di sini.
//
// Ref: docs/design/15_operator_panel.md

import SwiftUI

struct MissionControlView: View {
    @Environment(AppState.self) private var appState
    
    // Animate slide in/out
    @State private var offset: CGFloat = 400
    
    // Pairing setup presentation
    @State private var isShowingPairingSetup = false
    
    // Log viewer presentation
    @State private var isShowingLogViewer = false
    
    var body: some View {
        ZStack {
            // Invisible background to close when tapped outside
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }
            
            HStack {
                Spacer()
                
                // Sidebar Content
                VStack(alignment: .leading, spacing: 32) {
                    // Header
                    HStack {
                        Text("MISSION CONTROL")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                            .tracking(2)
                        
                        Spacer()
                        
                        Button(action: close) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    
                    ScrollView(showsIndicators: false) {
                        scrollContent
                    }
                    
                    Spacer()
                    
                    // Logout
                    Button(action: {
                        appState.operatorState.swapOperator()
                    }) {
                        HStack {
                            Image(systemName: "arrow.rectangle.portrait.and.arrow.right")
                            Text("Logout Shift")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.2))
                        .foregroundStyle(.red)
                        .cornerRadius(12)
                    }
                }
                .padding(24)
                .frame(width: 400)
                .background(
                    Rectangle()
                        .fill(Color(hex: "#1A1A24").opacity(0.95))
                        .ignoresSafeArea()
                )
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 32) {
            
            // 1. STATUS PERANGKAT
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "STATUS PERANGKAT", icon: "antenna.radiowaves.left.and.right")
                
                HStack {
                    StatusCard(
                        title: "HaiCamera",
                        value: "\(Int((appState.p2p.connectedPeerBatteryLevel ?? 0) * 100))%",
                        icon: "iphone",
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
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "QUICK ACTIONS", icon: "bolt.fill")
                
                HStack(spacing: 12) {
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
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "FRAME AKTIF", icon: "photo.on.rectangle")
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FrameThumbnail(name: "Classic", isSelected: true)
                        FrameThumbnail(name: "Floral", isSelected: false)
                        
                        // Tombol Impor
                        Button(action: {}) {
                            VStack {
                                Image(systemName: "plus")
                                Text("Impor")
                                    .font(.caption)
                            }
                            .frame(width: 80, height: 100)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
            
            // 4. KONTROL KAMERA
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "KONTROL KAMERA", icon: "camera.aperture")
                
                HStack(spacing: 16) {
                    Button("Lock AE/AF") {
                        // P2P trigger lock
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)
                    
                    Spacer()
                    
                    HStack(spacing: 0) {
                        Text("Zoom:")
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 8)
                        
                        Picker("Zoom", selection: .constant(1)) {
                            Text("1x").tag(1)
                            Text("2x").tag(2)
                            Text("3x").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
            }
            
            // 5. DIAGNOSTIK & LOGS
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "DIAGNOSTIK & LOGS", icon: "doc.text.magnifyingglass")
                
                HStack(spacing: 12) {
                    Button(action: {
                        isShowingLogViewer = true
                    }) {
                        HStack {
                            Image(systemName: "doc.plaintext")
                            Text("Lihat Log")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(12)
                    }
                    
                    ShareLink(item: LocalLogWriter.readLogContent()) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Bagikan Log")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
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
        HStack {
            Image(systemName: icon)
            Text(title)
        }
        .font(.subheadline.bold())
        .foregroundStyle(Color(hex: "#F5A623"))
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(12)
        }
    }
}

private struct FrameThumbnail: View {
    let name: String
    let isSelected: Bool
    
    var body: some View {
        VStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 80, height: 100)
                .overlay(
                    isSelected ? RoundedRectangle(cornerRadius: 12).stroke(Color.green, lineWidth: 2) : nil
                )
                .cornerRadius(12)
            Text(name)
                .font(.caption)
                .foregroundStyle(isSelected ? .green : .white.opacity(0.6))
        }
    }
}

#Preview {
    MissionControlView()
        .environment(AppState.preview)
}

private struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                if logContent.isEmpty {
                    Text("Log kosong atau tidak dapat dimuat.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle("Log Sistem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hapus Log", role: .destructive) {
                        LocalLogWriter.clearLog()
                        logContent = ""
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        
                        ShareLink(item: logContent) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                logContent = LocalLogWriter.readLogContent()
            }
        }
    }
}
