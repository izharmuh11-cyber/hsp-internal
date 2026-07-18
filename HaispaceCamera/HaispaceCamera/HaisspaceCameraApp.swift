// HaisspaceCameraApp.swift
// HaispaceCamera
//
// Entry point aplikasi HaiCamera (iPhone).
// Layar minimal — sebagian besar waktu layar adalah HITAM (brightness = 0).
//
// Ref: docs/design/22_haicamera_ux.md — iPhone Black Screen Mode
// Ref: docs/design/39_state_architecture.md — HaiCamera State

import SwiftUI
import UIKit

@main
struct HaisspaceCameraApp: App {

    @State private var cameraState = CameraAppState()
    @UIApplicationDelegateAdaptor(CameraAppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            CameraView()
                .environment(cameraState)
                .task {
                    await cameraState.setup()
                    R2LogUploader.uploadLatestLog(eventName: "app_launch")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    R2LogUploader.uploadLatestLog(eventName: "app_background")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    R2LogUploader.uploadLatestLog(eventName: "app_active")
                }
        }
    }
}

// MARK: - Camera App Delegate

class CameraAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Aktifkan battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Nonaktifkan auto-lock — iPhone harus selalu on selama event
        UIApplication.shared.isIdleTimerDisabled = true

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        HaispaceLogger.info("HaiCamera launched — build: #\(build) (\(version)) — model: \(UIDevice.current.model)", category: "app")
        return true
    }
}
