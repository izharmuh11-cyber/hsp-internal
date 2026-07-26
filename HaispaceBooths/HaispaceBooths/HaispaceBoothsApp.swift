// HaispaceBoothsApp.swift
// HaispaceBooths — App
//
// Entry point aplikasi HaiBooth (iPad).
//
// URUTAN ASSEMBLY (Platform Runtime v1.0):
//   1. RuntimeContainer.build(.production) → merakit semua Module
//   2. AppState(runtime: container)        → thin bridge ke SwiftUI
//   3. .environment(appState)              → inject ke seluruh view hierarchy
//
// AppState TIDAK membuat dependency apapun.
// RuntimeContainer adalah satu-satunya Composition Root.
//
// Ref: haispace-platform/constitution/PLATFORM_RUNTIME_V1.md

import SwiftUI
import BackgroundTasks
import UIKit

// MARK: - App Entry Point

@main
struct HaispaceBoothsApp: App {

    // MARK: State
    @State private var appState: AppState = {
        // RuntimeContainer dibangun pertama — SEBELUM AppState.
        // Jika build gagal (hanya bisa terjadi di konfigurasi tidak valid),
        // fallback ke .development agar app tidak crash saat launch.
        let container: RuntimeContainer
        do {
            container = try RuntimeContainer.build(for: .production)
        } catch {
            HaispaceLogger.warning(
                "RuntimeContainer.build(.production) failed: \(error.localizedDescription) — falling back to .development",
                category: "runtime"
            )
            container = (try? RuntimeContainer.build(for: .development)) ?? {
                fatalError("RuntimeContainer: tidak dapat dibuat bahkan untuk .development — periksa environment konfigurasi.")
            }()
        }
        return AppState(runtime: container)
    }()

    // MARK: UIKit Delegate for Background Tasks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .onAppear {
                    AppDelegate.appState = appState
                }
                .task {
                    await appState.setup()
                    R2LogUploader.uploadLatestLog(eventName: "app_launch")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    appState.handleAppBecomeActive()
                    R2LogUploader.uploadLatestLog(eventName: "app_active")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    R2LogUploader.uploadLatestLog(eventName: "app_background")
                }
        }
    }
}

// MARK: - AppDelegate (untuk Background Tasks)

class AppDelegate: NSObject, UIApplicationDelegate {

    /// Reference ke AppState (di-set dari HaispaceBoothsApp)
    static weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupBackgroundTasks()
        setupAppearance()
        UIDevice.current.isBatteryMonitoringEnabled = true
        return true
    }

    // MARK: - Background Tasks Registration

    private func setupBackgroundTasks() {
        // BGProcessingTask untuk license heartbeat (prioritas lebih tinggi dari BGAppRefreshTask)
        // Ref: 40_concurrency_strategy.md — ⚠️ Catatan BGProcessingTask
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "id.haispaceproject.booth.license-check",
            using: nil
        ) { task in
            task.expirationHandler = {
                task.setTaskCompleted(success: false)
                HaispaceLogger.warning("BGTask expired: license-check", category: "bg")
            }

            Task {
                await AppDelegate.appState?.license.performHeartbeat()
                task.setTaskCompleted(success: true)
                self.scheduleLicenseCheckTask() // Schedule ulang untuk 7 hari berikutnya
            }
        }

        // BGProcessingTask untuk photo upload (saat app di-background)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "id.haispaceproject.booth.photo-upload",
            using: nil
        ) { task in
            task.expirationHandler = {
                task.setTaskCompleted(success: false)
            }

            Task {
                // TODO: Fase 3 — implementasi pending upload processing
                task.setTaskCompleted(success: true)
            }
        }

        // Schedule initial task
        scheduleLicenseCheckTask()
    }

    /// Schedule BGProcessingTask untuk 7 hari ke depan
    func scheduleLicenseCheckTask() {
        let request = BGProcessingTaskRequest(identifier: "id.haispaceproject.booth.license-check")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 7 * 24 * 3600) // 7 hari

        do {
            try BGTaskScheduler.shared.submit(request)
            HaispaceLogger.info("BGTask license-check scheduled untuk 7 hari ke depan", category: "bg")
        } catch {
            HaispaceLogger.warning("BGTask schedule gagal: \(error.localizedDescription)", category: "bg")
        }
    }

    // MARK: - Global App Appearance

    private func setupAppearance() {
        // Kiosk mode: nonaktifkan status bar (layar penuh untuk tamu)
        // Dikonfigurasi via Info.plist: UIStatusBarHidden = YES jika diperlukan

        // Nonaktifkan auto-lock saat event berlangsung
        UIApplication.shared.isIdleTimerDisabled = true

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        HaispaceLogger.info("HaiBooth launched — build: #\(build) (\(version)) — device: \(UIDevice.current.model)", category: "app")
    }

    // MARK: - Background URL Session Handler

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Handle background URL session completion (untuk photo upload)
        // TODO: Fase 3 — implementasi CloudUploadService background session handler
        HaispaceLogger.info("Background URL session event: \(identifier)", category: "upload")
        completionHandler()
    }
}
