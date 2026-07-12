// ContentView.swift
// HaispaceBooths
//
// Placeholder view untuk melengkapi file target Xcode project.
// Menampilkan RootView yang merupakan navigasi utama aplikasi.

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environment(AppState.preview)
}
