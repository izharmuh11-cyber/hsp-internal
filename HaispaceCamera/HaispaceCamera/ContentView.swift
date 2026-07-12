// ContentView.swift
// HaispaceCamera
//
// Placeholder view untuk melengkapi file target Xcode project.
// Menampilkan CameraView yang merupakan navigasi utama aplikasi.

import SwiftUI

struct ContentView: View {
    @Environment(CameraAppState.self) private var cameraState

    var body: some View {
        CameraView()
    }
}

#Preview {
    ContentView()
        .environment(CameraAppState.preview)
}
