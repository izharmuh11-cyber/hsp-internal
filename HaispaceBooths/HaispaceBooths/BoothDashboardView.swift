// BoothDashboardView.swift
// HaispaceBooths
//
// Placeholder view untuk melengkapi file target Xcode project.
// Akan diimplementasikan lebih lanjut sebagai bagian dari Mission Control di Fase 3.

import SwiftUI

struct BoothDashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Operator Dashboard")
                    .font(.largeTitle.bold())
                
                Text("Bagian dari Mission Control panel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    BoothDashboardView()
        .environment(AppState.preview)
}
