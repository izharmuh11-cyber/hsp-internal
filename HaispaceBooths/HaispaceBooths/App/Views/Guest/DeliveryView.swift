// DeliveryView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar akhir di mana tamu dapat mengunduh foto individual 
// atau Memory Card (kolase) menggunakan Bonjour Local Server (QR Code).
//
// Ref: docs/design/10_photo_delivery.md
// Ref: docs/design/38_memory_book.md

import SwiftUI

struct DeliveryView: View {
    @Environment(AppState.self) private var appState
    
    @State private var memoryCardImage: UIImage?
    @State private var isGenerating: Bool = true
    @State private var showQRCode: Bool = false
    @State private var qrCodeURL: String = ""
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            HStack(spacing: 40) {
                // Left Column: Preview Memory Card
                VStack {
                    if isGenerating {
                        VStack(spacing: 16) {
                            ProgressView().tint(.white)
                            Text("Merangkai Memory Card...")
                                .font(.headline)
                                .foregroundStyle(.gray)
                        }
                        .frame(width: 400, height: 711) // 9:16 aspect ratio
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(24)
                    } else if let img = memoryCardImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 400)
                            .cornerRadius(24)
                            .shadow(color: .white.opacity(0.2), radius: 20)
                    }
                    
                    Text("PREVIEW MEMORY CARD")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                        .tracking(2)
                        .padding(.top, 16)
                }
                .padding(.leading, 60)
                
                // Right Column: Download Options
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📸 Foto Kamu Sudah Siap!")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        
                        Text("Pilih format yang ingin diunduh ke HP kamu.")
                            .font(.title3)
                            .foregroundStyle(.gray)
                    }
                    
                    VStack(spacing: 16) {
                        DownloadOptionButton(
                            icon: "photo.stack",
                            title: "Unduh Foto Individual",
                            subtitle: "Foto resolusi tinggi satu per satu",
                            color: Color(hex: "#1A1A24")
                        ) {
                            triggerQR("http://192.168.1.100:8080/download/photos")
                        }
                        
                        DownloadOptionButton(
                            icon: "square.grid.2x2.fill",
                            title: "Unduh Memory Card",
                            subtitle: "1 Kolase cantik untuk IG Story",
                            color: Color(hex: "#1A1A24")
                        ) {
                            triggerQR("http://192.168.1.100:8080/download/memory-card")
                        }
                        
                        DownloadOptionButton(
                            icon: "archivebox.fill",
                            title: "Unduh Semua (ZIP)",
                            subtitle: "Semua foto + Memory Card",
                            color: Color(hex: "#F5A623"),
                            textColor: .black
                        ) {
                            triggerQR("http://192.168.1.100:8080/download/all")
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        appState.currentSession?.reset()
                        appState.navigateTo(.landing)
                    }) {
                        Text("Selesai")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
                .padding(.trailing, 60)
                .padding(.vertical, 80)
            }
            
            // QR Code Overlay
            if showQRCode {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { showQRCode = false }
                    }
                
                VStack(spacing: 24) {
                    Text("Scan untuk Unduh")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    // Mock QR Code Image
                    Image(systemName: "qrcode")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding(32)
                        .background(Color.white)
                        .cornerRadius(24)
                    
                    Text("Pastikan terhubung ke WiFi: HAISPACE_BOOTH")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                    
                    Button("Tutup") {
                        withAnimation { showQRCode = false }
                    }
                    .padding(.top, 16)
                }
                .padding(40)
                .background(Color(hex: "#1A1A24"))
                .cornerRadius(32)
                .shadow(radius: 30)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            generateMemoryCard()
        }
    }
    
    private func triggerQR(_ url: String) {
        qrCodeURL = url
        withAnimation(.spring) {
            showQRCode = true
        }
    }
    
    private func generateMemoryCard() {
        // Mock Images
        let mockPhotos = [
            UIImage(named: "MockPhoto1") ?? UIImage(),
            UIImage(named: "MockPhoto2") ?? UIImage(),
            UIImage(named: "MockPhoto3") ?? UIImage()
        ]
        
        MemoryBookGenerator.shared.generateMemoryCard(
            photos: mockPhotos,
            eventName: "Wisuda 2026",
            guestName: "Tamu HaiBooth"
        ) { image in
            self.memoryCardImage = image
            self.isGenerating = false
        }
    }
}

private struct DownloadOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var textColor: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(textColor.opacity(0.8))
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(textColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(textColor.opacity(0.5))
            }
            .padding()
            .background(color)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

#Preview {
    DeliveryView()
        .environment(AppState.preview)
}
