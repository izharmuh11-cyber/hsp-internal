import SwiftUI

@main
struct HaispaceBoothsApp: App {
    // Cegah layar iPad mati saat app berjalan
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
