import SwiftUI

struct BoothDashboardView: View {
    @State private var isCameraConnected = false
    @State private var selectedPhotos: [UIImage] = []
    @State private var activeStep: ActiveStep = .standby
    
    enum ActiveStep {
        case standby
        case register
        case captureInProgress
        case selectPhotos
        case selectFrame
        case payment
        case download
    }
    
    var body: some View {
        ZStack {
            // Elegant dark premium background
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()
            
            // Subtle glowing blobs
            RadialGradient(colors: [Color.purple.opacity(0.15), Color.clear], center: .topLeading, startRadius: 100, endRadius: 600)
                .ignoresSafeArea()
            RadialGradient(colors: [Color.blue.opacity(0.15), Color.clear], center: .bottomTrailing, startRadius: 100, endRadius: 600)
                .ignoresSafeArea()
            
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Left panel: Status & Quick Controls
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HAISPACE")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .tracking(6)
                            Text("BOOTH STATION")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .tracking(3)
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        // Device Connection Status Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("STATUS KONEKSI")
                                .font(.caption2.bold())
                                .foregroundColor(.gray)
                                .tracking(2)
                            
                            HStack {
                                Image(systemName: "iphone")
                                    .font(.title2)
                                    .foregroundColor(isCameraConnected ? .green : .orange)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(isCameraConnected ? "iPhone 14 Connected" : "Mencari Kamera...")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text(isCameraConnected ? "Signal: Excellent" : "Pastikan App Haispace Camera Terbuka")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Button(action: {
                                isCameraConnected.toggle()
                            }) {
                                Text(isCameraConnected ? "Putuskan" : "Simulasi Sambung")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(isCameraConnected ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        
                        Spacer()
                    }
                    .frame(width: geo.size.width * 0.3)
                    .padding(32)
                    
                    VerticalDivider()
                    
                    // Right panel: Main Action Canvas
                    VStack(spacing: 24) {
                        Spacer()
                        
                        if activeStep == .standby {
                            VStack(spacing: 24) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 64))
                                    .foregroundColor(.purple)
                                
                                Text("Siap Untuk Memulai?")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Daftarkan nama & Instagram kamu pada stasiun foto")
                                    .font(.body)
                                    .foregroundColor(.gray)
                                
                                Button(action: {
                                    activeStep = .selectPhotos
                                }) {
                                    Text("Simulasi Pilih Foto")
                                        .font(.headline.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 40)
                                        .padding(.vertical, 16)
                                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                        .cornerRadius(30)
                                }
                            }
                        } else if activeStep == .selectPhotos {
                            VStack(spacing: 16) {
                                Text("Pilih Foto Terbaikmu")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                
                                // Placeholder grid for photo selection
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(0..<4) { index in
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.05))
                                            .frame(height: 140)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.gray)
                                            )
                                    }
                                }
                                .padding()
                                
                                Button(action: {
                                    activeStep = .standby
                                }) {
                                    Text("Kembali")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(width: geo.size.width * 0.7)
                    .padding(32)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(width: 1)
            .ignoresSafeArea()
    }
}

#Preview {
    BoothDashboardView()
}
