// FrameSelectionView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar di mana tamu memilih bingkai kustom untuk menghiasi foto mereka.
// Menggunakan desain tata letak landscape-optimized (split-screen) untuk iPad.
//
// Ref: docs/design/13_frame_system.md — Spesifikasi Frame
// Ref: docs/design/04_ui_design.md — Layout Seleksi

import SwiftUI

struct FrameSelectionView: View {
    @Environment(AppState.self) private var appState

    private var session: SessionStore? {
        appState.currentSession
    }

    // ID bingkai yang sedang dipilih
    @State private var selectedFrameId: String?

    // Grid layout untuk pilihan bingkai di sebelah kanan (2 kolom)
    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            // Background Gelap Premium
            Color(hex: "#080810").ignoresSafeArea()

            // Ornamen Glow Ambient
            Circle()
                .fill(Color(hex: "#7C5CFC").opacity(0.12))
                .blur(radius: 120)
                .frame(width: 400, height: 400)
                .offset(x: -250, y: -150)

            Circle()
                .fill(Color(hex: "#00D9A0").opacity(0.08))
                .blur(radius: 120)
                .frame(width: 350, height: 350)
                .offset(x: 300, y: 200)

            if let session = session {
                HStack(spacing: 48) {
                    
                    // ==========================================
                    // PANEL KIRI: Live Preview Frame + Photo
                    // ==========================================
                    VStack(spacing: 20) {
                        Text("Live Preview")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ZStack {
                            // Container Background
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(hex: "#12121A"))
                                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                            
                            if let selectedFrame = appState.boothConfig.offlineReadyFrames.first(where: { $0.id == selectedFrameId }) {
                                ZStack {
                                    // 1. Foto Tamu (Foto pertama yang dipilih)
                                    if let firstPhoto = session.photos.selectedPhotos.first {
                                        if let image = firstPhoto.displayImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } else {
                                            ProgressView()
                                                .tint(.white)
                                        }
                                    } else {
                                        // Fallback jika tidak ada foto terpilih
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.on.rectangle")
                                                .font(.largeTitle)
                                                .foregroundStyle(.gray)
                                            Text("Tidak ada foto")
                                                .font(.caption)
                                                .foregroundStyle(.gray)
                                        }
                                    }
                                    
                                    // 2. Overlay Bingkai (Frame)
                                    if let path = selectedFrame.localPath, let uiImage = UIImage(contentsOfFile: path) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    } else {
                                        // Mock Frame Render (Jika localPath nil / SwiftUI Preview)
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white, lineWidth: 16)
                                            .overlay(
                                                VStack {
                                                    Spacer()
                                                    HStack {
                                                        Text(selectedFrame.name)
                                                            .font(.system(.title3, design: .serif))
                                                            .italic()
                                                            .fontWeight(.bold)
                                                            .foregroundStyle(.white)
                                                        Spacer()
                                                        Text("HAISPACE")
                                                            .font(.caption2.weight(.black))
                                                            .foregroundStyle(.white.opacity(0.8))
                                                    }
                                                    .padding(24)
                                                }
                                            )
                                    }
                                }
                                .aspectRatio(selectedFrame.isPortrait ? 3/4 : 4/3, contentMode: .fit)
                                .cornerRadius(16)
                                .padding(12)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "square.dashed")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.gray)
                                    Text("Pilih bingkai di panel kanan")
                                        .font(.callout)
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 440)
                    
                    // ==========================================
                    // PANEL KANAN: Informasi & Grid Pemilihan
                    // ==========================================
                    VStack(alignment: .leading, spacing: 28) {
                        // Header Kanan
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pilih Bingkai Foto")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text("Personalisasi fotomu dengan pilihan bingkai eksklusif event ini.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        
                        // Scrollable Grid Bingkai
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(appState.boothConfig.offlineReadyFrames) { frame in
                                    FrameGridItem(
                                        frame: frame,
                                        isSelected: selectedFrameId == frame.id,
                                        action: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedFrameId = frame.id
                                            }
                                            UISelectionFeedbackGenerator().selectionChanged()
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Spacer(minLength: 16)
                        
                        // Tombol Navigasi Lanjut
                        Button(action: {
                            if let frameId = selectedFrameId {
                                session.photos.selectedFrameId = frameId
                                Task {
                                    try? await appState.send(.selectTemplate(frameId: frameId))
                                }
                            }
                        }) {
                            HStack {
                                Text("Lanjut ke Pembayaran 💳")
                                    .font(.system(size: 20, weight: .bold))
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 18))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(selectedFrameId != nil ? Color(hex: "#7C5CFC") : Color.white.opacity(0.08))
                            )
                            .shadow(color: selectedFrameId != nil ? Color(hex: "#7C5CFC").opacity(0.35) : .clear, radius: 15, y: 5)
                        }
                        .disabled(selectedFrameId == nil)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 40)
                .onAppear {
                    // Pre-select bingkai pertama jika belum ada yang terpilih
                    if let current = session.photos.selectedFrameId {
                        selectedFrameId = current
                    } else if let firstFrame = appState.boothConfig.offlineReadyFrames.first {
                        selectedFrameId = firstFrame.id
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Error: Sesi aktif tidak terdeteksi")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Frame Grid Item Component

private struct FrameGridItem: View {
    let frame: PhotoFrame
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Miniature Frame Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#181822"))
                        .aspectRatio(frame.isPortrait ? 3/4 : 4/3, contentMode: .fit)
                    
                    if let path = frame.localPath, let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    } else {
                        // Mock Miniature Border
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.6), lineWidth: 8)
                            .overlay(
                                Text("A")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white.opacity(0.4))
                            )
                            .padding(8)
                    }
                    
                    // Selected Checkmark Overlay
                    if isSelected {
                        Color.black.opacity(0.4)
                            .cornerRadius(12)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "#00D9A0"))
                            .shadow(radius: 5)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color(hex: "#7C5CFC") : Color.white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                )
                .scaleEffect(isSelected ? 0.98 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
                
                // Info Bingkai
                VStack(alignment: .leading, spacing: 4) {
                    Text(frame.name)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color(hex: "#7C5CFC") : .white)
                        .lineLimit(1)
                    
                    Text(frame.isPortrait ? "Portrait 3:4" : "Landscape 4:3")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    FrameSelectionView()
        .environment(AppState.previewWithActiveSession)
}
