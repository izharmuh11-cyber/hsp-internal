// PackageSelectionView.swift
// HaispaceBooths — App/Views/Guest
//
// The Stage: Layar interaktif untuk tamu memilih paket dan add-ons.
// Animasi polaroid jatuh sesuai durasi sesi.
//
// Ref: docs/design/04_ui_design.md — The Stage

import SwiftUI

struct PackageSelectionView: View {
    @Environment(AppState.self) private var appState
    
    @State private var selectedPackage: BoothPackage?
    @State private var selectedAddons: Set<AddonType> = []
    
    // Animasi polaroid
    @State private var displayedPolaroids: Int = 0
    
    var body: some View {
        ZStack {
            Color(hex: "#080810").ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation { appState.navigateTo(.guestRegistration) }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    
                    Spacer()
                    
                    Text("Pilih Sesi Kamu")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Circle().fill(Color.clear).frame(width: 56, height: 56)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                // LIVE STAGE PREVIEW (Polaroid Animation)
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(white: 1.0, opacity: 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color(white: 1.0, opacity: 0.08), lineWidth: 1)
                        )
                    
                    VStack {
                        Spacer()
                        HStack(spacing: -20) {
                            ForEach(0..<displayedPolaroids, id: \.self) { index in
                                PolaroidMockView()
                                    .rotationEffect(.degrees(Double.random(in: -15...15)))
                                    .offset(y: Double.random(in: -20...20))
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .scale.combined(with: .opacity)
                                    ))
                                    .zIndex(Double(index))
                            }
                        }
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: displayedPolaroids)
                        
                        Spacer()
                        
                        // Active Add-ons indicator
                        HStack(spacing: 20) {
                            if selectedAddons.contains(.boomerang) {
                                Label("Boomerang Active", systemImage: "infinity")
                                    .font(.callout.bold())
                                    .foregroundStyle(Color(hex: "#F5A623"))
                                    .transition(.scale.combined(with: .opacity))
                            }
                            if selectedAddons.contains(.timelapse) {
                                Label("Timelapse Active", systemImage: "clock.arrow.2.circlepath")
                                    .font(.callout.bold())
                                    .foregroundStyle(Color(hex: "#7C5CFC"))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .frame(height: 320)
                .padding(.horizontal, 40)
                
                // DURASI SESI (Packages)
                VStack(alignment: .leading, spacing: 16) {
                    Text("DURASI SESI")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 40)
                    
                    HStack(spacing: 20) {
                        ForEach(appState.boothConfig.activePackages) { package in
                            PackageCard(
                                package: package,
                                isSelected: selectedPackage?.id == package.id
                            ) {
                                selectPackage(package)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
                
                // Sementata Fase 2: Add-ons di-mock
                
                Spacer()
                
                // Footer: Total & Start Button
                HStack {
                    VStack(alignment: .leading) {
                        Text("Total")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(formatCurrency(calculateTotal()))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        startSession()
                    }) {
                        Text("Mulai Sesi ✦")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 48)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedPackage == nil ? Color.white.opacity(0.1) : Color(hex: "#F5A623"))
                            )
                            .shadow(color: selectedPackage == nil ? .clear : Color(hex: "#F5A623").opacity(0.4), radius: 10)
                    }
                    .disabled(selectedPackage == nil)
                }
                .padding(40)
                .background(Color(hex: "#080810").ignoresSafeArea())
                .shadow(color: .black.opacity(0.5), radius: 20, y: -10)
            }
        }
        .onAppear {
            if let first = appState.boothConfig.activePackages.first {
                selectPackage(first)
            }
        }
    }
    
    private func selectPackage(_ package: BoothPackage) {
        withAnimation {
            selectedPackage = package
        }
        // Update stage
        displayedPolaroids = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring) {
                // Mock jumlah foto berdasarkan durasi
                displayedPolaroids = package.durationSeconds / 60 + 2
            }
        }
    }
    
    private func calculateTotal() -> Int {
        var total = selectedPackage?.price ?? 0
        // Tambah harga addons nantinya
        return total
    }
    
    private func formatCurrency(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp "
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "Rp \(value)"
    }
    
    private func startSession() {
        guard let package = selectedPackage, let guest = appState.pendingGuest else { return }
        
        let session = appState.startNewSession(package: package, guest: guest)
        
        // Pindah layar ke Active Session
        withAnimation(.easeInOut) {
            appState.navigateTo(.activeSession)
        }
        
        // Kirim sinyal sessionStart ke iPhone via P2PMessageRouter
        let configMsg = SessionConfig(
            sessionId: session.sessionId,
            totalDurationSeconds: package.durationSeconds,
            intervalSeconds: 8, // Auto-mode interval
            maxPhotoCount: 999, // Unlimited within time
            guestName: guest.displayName
        )
        Task {
            await P2PMessageRouter.shared.route(.sessionStart(config: configMsg))
        }
    }
}

private struct PackageCard: View {
    let package: BoothPackage
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(package.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? Color(hex: "#F5A623") : .white)
                
                Text("\(package.durationSeconds / 60) Menit")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color(hex: "#F5A623").opacity(0.1) : Color(white: 1.0, opacity: 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color(hex: "#F5A623") : Color(white: 1.0, opacity: 0.1), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PolaroidMockView: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(white: 0.2))
                .aspectRatio(3/4, contentMode: .fit)
                .padding(8)
            Spacer()
        }
        .frame(width: 80, height: 100)
        .background(Color.white)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
}

// Enum Addon placeholder removed (defined in BoothPackage.swift)

#Preview {
    PackageSelectionView()
        .environment(AppState.preview)
}
