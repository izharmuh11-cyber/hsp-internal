// FilterSelectionView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar untuk memilih filter LUT dengan live preview berbasis Metal.
// Menampilkan slider intensity untuk mengatur opacity filter.
//
// Ref: docs/design/34_filter_system.md

import SwiftUI
import CoreImage

struct FilterSelectionView: View {
    @Environment(AppState.self) private var appState
    
    // Asumsi: FilterService diinjeksi atau singleton (untuk MVP bisa buat instan lokal)
    private let filterService = FilterService()
    
    // Mock Data Filters
    let availableFilters = [
        FilterOption(id: "original", name: "Original", icon: "circle", lutURL: nil),
        FilterOption(id: "warm", name: "Warm ☀️", icon: "sun.max.fill", lutURL: Bundle.main.url(forResource: "warm", withExtension: "cube")),
        FilterOption(id: "mono", name: "Mono ⬛", icon: "camera.filters", lutURL: Bundle.main.url(forResource: "mono", withExtension: "cube")),
        FilterOption(id: "film", name: "Filmic 🎬", icon: "film.fill", lutURL: Bundle.main.url(forResource: "film", withExtension: "cube"))
    ]
    
    @State private var selectedFilterId: String = "original"
    @State private var intensity: Float = 0.8
    
    @State private var previewImage: Image?
    private let baseCIImage: CIImage? = {
        // Mock image untuk preview
        if let cgImage = UIImage(named: "MockPhoto")?.cgImage {
            return CIImage(cgImage: cgImage)
        }
        return CIImage(color: CIColor.gray)
    }()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Live Preview Area
                ZStack {
                    if let image = previewImage {
                        image
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(24)
                            .padding()
                            .animation(.easeInOut(duration: 0.2), value: selectedFilterId)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .cornerRadius(24)
                            .padding()
                            .overlay(ProgressView().tint(.white))
                    }
                }
                .frame(maxHeight: .infinity)
                
                // 2. Control Panel
                VStack(spacing: 24) {
                    // Slider
                    if selectedFilterId != "original" {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Intensitas")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                                Spacer()
                                Text("\(Int(intensity * 100))%")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                            
                            Slider(value: $intensity, in: 0...1, step: 0.05)
                                .tint(Color(hex: "#F5A623"))
                                .onChange(of: intensity) { _, _ in
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    renderPreview()
                                }
                        }
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Filter Grid
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(availableFilters) { filter in
                                FilterThumbnail(
                                    filter: filter,
                                    isSelected: selectedFilterId == filter.id,
                                    action: {
                                        withAnimation {
                                            selectedFilterId = filter.id
                                            // Reset intensity untuk filter baru kecuali jika "original"
                                            if filter.id != "original" {
                                                intensity = 0.8
                                            }
                                        }
                                        renderPreview()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    .frame(height: 120)
                    
                    // Lanjut Button
                    Button(action: {
                        // Terapkan filter id dan intensity ke AppState jika perlu, lalu lanjut
                        appState.navigateTo(.delivery)
                    }) {
                        HStack {
                            Text("Terapkan Filter")
                                .font(.headline)
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#F5A623"))
                        .foregroundStyle(.black)
                        .cornerRadius(16)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                    }
                }
                .padding(.top, 24)
                .background(
                    Rectangle()
                        .fill(Color(hex: "#1A1A24").opacity(0.95))
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .onAppear {
            renderPreview()
        }
    }
    
    // MARK: - Logic
    
    private func renderPreview() {
        guard let base = baseCIImage else { return }
        
        guard let filterOption = availableFilters.first(where: { $0.id == selectedFilterId }) else { return }
        
        // Render in background
        Task.detached {
            let filteredCI = await filterService.applyLUT(to: base, lutURL: filterOption.lutURL, intensity: intensity)
            if let cgImage = filterService.render(filteredCI) {
                let uiImage = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.previewImage = Image(uiImage: uiImage)
                }
            }
        }
    }
}

// MARK: - Subviews

struct FilterOption: Identifiable {
    let id: String
    let name: String
    let icon: String
    let lutURL: URL?
}

private struct FilterThumbnail: View {
    let filter: FilterOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    
                    Image(systemName: filter.icon)
                        .font(.title)
                        .foregroundStyle(isSelected ? Color(hex: "#F5A623") : .white)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color(hex: "#F5A623") : Color.clear, lineWidth: 3)
                )
                
                Text(filter.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color(hex: "#F5A623") : .gray)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FilterSelectionView()
        .environment(AppState.preview)
}
