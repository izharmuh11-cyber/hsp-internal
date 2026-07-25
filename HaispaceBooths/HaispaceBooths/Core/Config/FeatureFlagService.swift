// FeatureFlagService.swift
// HaispaceBooths — Core/Config
//
// Feature flags untuk mengontrol fitur tanpa rebuild app.
// Dibangun di atas RemoteConfigService — flags disimpan dalam remote_config.json.
//
// PENGGUNAAN:
//   // Cek flag secara inline
//   if FeatureFlags.isEnabled(.gifAnimation) {
//       showGifOption()
//   }
//
//   // Di SwiftUI
//   @Environment(\.featureFlags) var flags
//   if flags.isEnabled(.aiEnhance) { ... }
//
// FLAG STATES:
//   enabled      → Fitur aktif untuk semua pengguna
//   disabled     → Fitur nonaktif
//   experimental → Aktif hanya untuk booth dengan `experimentalMode = true`
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar: Feature Rollout

import Foundation
import SwiftUI

// MARK: - FeatureFlag Enum

public enum FeatureFlag: String, CaseIterable, Sendable {

    // Output format
    case gifAnimation       = "gif_animation"       // GIF output setelah sesi
    case boomerang          = "boomerang"            // Boomerang video loop
    case videoMode          = "video_booth"          // Video recording mode (experimental)

    // AI Features
    case aiEnhance          = "ai_enhance"           // AI beautification / skin smoothing
    case aiBackground       = "ai_background"        // AI background replacement
    case aiColorPop         = "ai_color_pop"         // AI selective color effect

    // UX Features
    case multiLanguage      = "multi_language"       // Bahasa selain Indonesia
    case voiceGuide         = "voice_guide"          // Audio instructions
    case printDuplex        = "print_duplex"         // Double-sided printing

    // Operator Features
    case advancedMissionControl = "advanced_mission_control"  // Extended MissionControl tabs
    case diagnosticsExport  = "diagnostics_export"   // Export diagnostics bundle
    case remoteRestart      = "remote_restart"       // Remote reboot dari dashboard

    // Business Features
    case digitalOnlyMode    = "digital_only"         // Softcopy saja, tanpa cetak
    case subscriptionModel  = "subscription_model"   // Langganan per bulan vs per-sesi

    // Developer / Debug
    case simulatedHardware  = "simulated_hardware"   // Gunakan NoOp printer/camera
    case performanceHUD     = "performance_hud"      // Tampilkan overlay metrik performa
}

// MARK: - FlagState

public enum FlagState: String, Codable, Sendable {
    case enabled        = "enabled"
    case disabled       = "disabled"
    case experimental   = "experimental"   // Hanya untuk experimentalMode booth
}

// MARK: - FeatureFlagConfig (bagian dari RemoteConfig)

public struct FeatureFlagConfig: Codable, Sendable {
    public var flags: [String: FlagState]
    public var experimentalMode: Bool   // true untuk booth tertentu saja

    /// Default: semua disabled kecuali yang sudah production-ready
    public static let `default` = FeatureFlagConfig(
        flags: [
            FeatureFlag.gifAnimation.rawValue: .enabled,
            FeatureFlag.diagnosticsExport.rawValue: .enabled,
            FeatureFlag.advancedMissionControl.rawValue: .enabled,
            FeatureFlag.boomerang.rawValue: .disabled,
            FeatureFlag.videoMode.rawValue: .experimental,
            FeatureFlag.aiEnhance.rawValue: .disabled,
            FeatureFlag.aiBackground.rawValue: .experimental,
            FeatureFlag.aiColorPop.rawValue: .disabled,
            FeatureFlag.multiLanguage.rawValue: .disabled,
            FeatureFlag.voiceGuide.rawValue: .disabled,
            FeatureFlag.printDuplex.rawValue: .disabled,
            FeatureFlag.remoteRestart.rawValue: .disabled,
            FeatureFlag.digitalOnlyMode.rawValue: .disabled,
            FeatureFlag.subscriptionModel.rawValue: .disabled,
            FeatureFlag.simulatedHardware.rawValue: .disabled,
            FeatureFlag.performanceHUD.rawValue: .disabled,
        ],
        experimentalMode: false
    )
}

// MARK: - FeatureFlagService

@MainActor
public final class FeatureFlagService: ObservableObject {

    public static let shared = FeatureFlagService()

    @Published private var config: FeatureFlagConfig = .default

    private init() {}

    // MARK: - Update from RemoteConfig

    func update(from flagConfig: FeatureFlagConfig) {
        self.config = flagConfig
    }

    // MARK: - Public API

    /// Cek apakah sebuah flag aktif
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        switch config.flags[flag.rawValue] {
        case .enabled:
            return true
        case .experimental:
            return config.experimentalMode
        case .disabled, .none:
            return false
        }
    }

    /// State flag mentah (untuk MissionControl display)
    public func state(of flag: FeatureFlag) -> FlagState {
        config.flags[flag.rawValue] ?? .disabled
    }

    /// Semua flags dengan statenya — untuk operator dashboard
    public var allFlags: [(flag: FeatureFlag, state: FlagState)] {
        FeatureFlag.allCases.map { flag in
            (flag: flag, state: state(of: flag))
        }
    }

    /// Override satu flag lokal (untuk testing / operator override)
    public func setLocal(_ flag: FeatureFlag, state: FlagState) {
        config.flags[flag.rawValue] = state
    }
}

// MARK: - Global Convenience API

/// `FeatureFlags.isEnabled(.gifAnimation)` — static shortcut
public enum FeatureFlags {
    @MainActor
    public static func isEnabled(_ flag: FeatureFlag) -> Bool {
        FeatureFlagService.shared.isEnabled(flag)
    }
}

// MARK: - SwiftUI Environment Key

@MainActor
private struct FeatureFlagServiceKey: EnvironmentKey {
    static let defaultValue = FeatureFlagService.shared
}

extension EnvironmentValues {
    public var featureFlags: FeatureFlagService {
        get { self[FeatureFlagServiceKey.self] }
        set { self[FeatureFlagServiceKey.self] = newValue }
    }
}
