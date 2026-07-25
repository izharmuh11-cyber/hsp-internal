// CameraSupervisor.swift
// HaispaceBooths — Core/Supervisors
//
// State machine supervisor untuk kamera (fisik atau remote via P2P).
//
// STATE MACHINE:
//
//   WARMING_UP ──────────────────────────────────────────────► DISCONNECTED
//       │                                                            ▲
//       ▼                                                            │
//     READY ◄───────────────────────────────────────────────────────┤
//       │                                                            │
//       ├──► CAPTURING ──► READY (foto selesai)                     │
//       │                                                            │
//       ├──► EXPOSURE_UNSTABLE ──► READY (auto-corrected)           │
//       │                                                            │
//       ├──► FOCUS_TIMEOUT ──► READY (auto-retry)                   │
//       │                                                            │
//       └──► ERROR ─────────────────────────────────────────────────┘
//
// KONTRAK OPERASIONAL:
//   - DISCONNECTED: booth masuk safe mode, tidak bisa mulai sesi baru
//   - EXPOSURE_UNSTABLE: tampil warm hint ke tamu, masih bisa capture
//   - FOCUS_TIMEOUT: auto-retry 2x, setelah itu eskalasi ke ERROR
//   - ERROR: operator diberitahu, sesi aktif di-suspend
//
// INTEGRASI:
//   - Konsumsi data dari P2PCapability (koneksi)
//   - Konsumsi frame quality data dari StreamingDecoderService
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar 4: Supervisor Layer

import Foundation

// MARK: - CameraState

public enum CameraState: String, Codable, Sendable, CaseIterable {
    case warmingUp          = "warming_up"          // Inisialisasi / reconnect
    case ready              = "ready"               // Siap, live preview aktif
    case capturing          = "capturing"           // Sedang mengambil foto
    case exposureUnstable   = "exposure_unstable"   // Pencahayaan berfluktuasi
    case focusTimeout       = "focus_timeout"       // Fokus gagal terkunci
    case disconnected       = "disconnected"        // Koneksi P2P/USB terputus
    case error              = "error"               // Error fatal, butuh intervensi

    /// Apakah bisa memulai sesi foto baru?
    public var canStartSession: Bool {
        switch self {
        case .ready, .exposureUnstable: return true
        default: return false
        }
    }

    /// Apakah capture foto dimungkinkan?
    public var canCapture: Bool {
        self == .ready
    }

    /// Apakah perlu menampilkan hint ke tamu?
    public var guestHint: String? {
        switch self {
        case .exposureUnstable:
            return "Kamera sedang menyesuaikan pencahayaan. Mohon tunggu sebentar."
        case .focusTimeout:
            return "Kamera sedang mengunci fokus. Harap tetap di posisi."
        default:
            return nil
        }
    }

    /// Label untuk MissionControl
    public var displayLabel: String {
        switch self {
        case .warmingUp:        return "Menyalakan"
        case .ready:            return "Siap"
        case .capturing:        return "Mengambil Foto"
        case .exposureUnstable: return "Pencahayaan Tidak Stabil"
        case .focusTimeout:     return "Fokus Timeout"
        case .disconnected:     return "Terputus"
        case .error:            return "Error"
        }
    }

    public var statusColor: StatusColor {
        switch self {
        case .ready:            return .green
        case .capturing:        return .blue
        case .warmingUp:        return .gray
        case .exposureUnstable, .focusTimeout: return .yellow
        case .disconnected, .error: return .red
        }
    }

    public enum StatusColor: String, Sendable {
        case green, yellow, blue, red, gray
    }
}

// MARK: - CameraEvent

public enum CameraEvent: Sendable {
    case stateChanged(from: CameraState, to: CameraState)
    case frameQualityDegraded(metric: FrameQualityMetric)
    case frameQualityRestored
    case captureStarted(sessionId: String, photoIndex: Int)
    case captureCompleted(sessionId: String, photoIndex: Int, latencyMs: Double)
    case captureFailed(sessionId: String, photoIndex: Int, reason: String)
    case reconnectAttempted(attempt: Int)
    case reconnectSucceeded
    case reconnectFailed(totalAttempts: Int)
}

public struct FrameQualityMetric: Sendable {
    public let exposureVariance: Double  // 0.0 (stable) → 1.0 (highly variable)
    public let focusScore: Double        // 0.0 (blurry) → 1.0 (sharp)
    public let fps: Double
}

// MARK: - CameraRuntimeProtocol (Abstrak)

public protocol CameraRuntimeProtocol: Sendable {
    /// Ambil frame quality metric terkini
    func currentFrameQuality() async -> FrameQualityMetric?

    /// Trigger capture — return data foto
    func capturePhoto() async throws -> Data

    /// Status koneksi fisik kamera
    var isConnected: Bool { get async }

    /// Trigger reconnect
    func attemptReconnect() async throws
}

// MARK: - CameraSupervisor

public actor CameraSupervisor {

    // MARK: - Configuration
    private static let healthCheckIntervalSeconds: TimeInterval = 5
    private static let exposureVarianceThreshold: Double = 0.35   // > ini = unstable
    private static let focusScoreThreshold: Double = 0.4          // < ini = timeout risk
    private static let maxFocusRetries = 2
    private static let maxReconnectAttempts = 3

    // MARK: - State
    private(set) public var currentState: CameraState = .warmingUp
    private(set) public var lastFrameQuality: FrameQualityMetric?
    private(set) public var lastStateChangeAt: Date = Date()
    private(set) public var uptimePercent: Double = 0
    private(set) public var lastCapturLatencyMs: Double?

    private var totalHealthChecks: Int = 0
    private var readyChecks: Int = 0
    private var focusRetryCount: Int = 0
    private var reconnectAttempts: Int = 0
    private var isMonitoring = false

    private let runtime: CameraRuntimeProtocol

    // Callbacks
    public var onEvent: ((CameraEvent) -> Void)?
    public var onStateChanged: ((CameraState) -> Void)?

    // MARK: - Init

    public init(runtime: CameraRuntimeProtocol) {
        self.runtime = runtime
    }

    // MARK: - Lifecycle

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        scheduleNextHealthCheck()
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    // MARK: - Capture Delegation

    public func capturePhoto(sessionId: String, photoIndex: Int) async throws -> Data {
        guard currentState.canCapture else {
            throw CameraSupervisorError.cannotCapture(currentState: currentState)
        }

        transition(to: .capturing)
        onEvent?(.captureStarted(sessionId: sessionId, photoIndex: photoIndex))

        let start = Date()
        do {
            let photoData = try await runtime.capturePhoto()
            let latencyMs = Date().timeIntervalSince(start) * 1000
            lastCapturLatencyMs = latencyMs

            onEvent?(.captureCompleted(
                sessionId: sessionId,
                photoIndex: photoIndex,
                latencyMs: latencyMs
            ))

            // Kembali ke ready setelah capture
            transition(to: .ready)
            return photoData
        } catch {
            onEvent?(.captureFailed(
                sessionId: sessionId,
                photoIndex: photoIndex,
                reason: error.localizedDescription
            ))
            transition(to: .ready) // Recovery: kembali ke ready, bukan error
            throw error
        }
    }

    // MARK: - Private: Health Check Loop

    private func scheduleNextHealthCheck() {
        Task {
            try? await Task.sleep(
                nanoseconds: UInt64(Self.healthCheckIntervalSeconds * 1_000_000_000)
            )
            if isMonitoring {
                await performHealthCheck()
                scheduleNextHealthCheck()
            }
        }
    }

    private func performHealthCheck() async {
        totalHealthChecks += 1

        // 1. Cek koneksi fisik
        let connected = await runtime.isConnected
        if !connected {
            if currentState != .disconnected {
                transition(to: .disconnected)
                await attemptReconnect()
            }
            return
        }

        // 2. Jika sebelumnya disconnected, kini terhubung kembali
        if currentState == .disconnected {
            transition(to: .warmingUp)
            reconnectAttempts = 0
        }

        // 3. Cek frame quality (hanya saat bukan sedang capture)
        if currentState != .capturing {
            await evaluateFrameQuality()
        }

        // 4. Update uptime
        let isHealthy = currentState == .ready || currentState == .capturing
        if isHealthy { readyChecks += 1 }
        uptimePercent = Double(readyChecks) / Double(totalHealthChecks) * 100

        // 5. Transisi ke READY jika warming up selesai
        if currentState == .warmingUp && connected {
            transition(to: .ready)
        }
    }

    private func evaluateFrameQuality() async {
        guard let quality = await runtime.currentFrameQuality() else { return }
        lastFrameQuality = quality

        let exposureUnstable = quality.exposureVariance > Self.exposureVarianceThreshold
        let focusWeak = quality.focusScore < Self.focusScoreThreshold

        if exposureUnstable && currentState == .ready {
            transition(to: .exposureUnstable)
            onEvent?(.frameQualityDegraded(metric: quality))
        } else if focusWeak && currentState == .ready {
            focusRetryCount += 1
            if focusRetryCount >= Self.maxFocusRetries {
                transition(to: .focusTimeout)
                focusRetryCount = 0
            }
        } else if !exposureUnstable && !focusWeak {
            // Quality restored
            if currentState == .exposureUnstable || currentState == .focusTimeout {
                transition(to: .ready)
                onEvent?(.frameQualityRestored)
            }
            focusRetryCount = 0
        }
    }

    private func attemptReconnect() async {
        guard reconnectAttempts < Self.maxReconnectAttempts else {
            // Exhaust reconnect — eskalasi ke ERROR
            transition(to: .error)
            onEvent?(.reconnectFailed(totalAttempts: reconnectAttempts))
            return
        }

        reconnectAttempts += 1
        onEvent?(.reconnectAttempted(attempt: reconnectAttempts))

        do {
            try await runtime.attemptReconnect()
            reconnectAttempts = 0
            onEvent?(.reconnectSucceeded)
            transition(to: .warmingUp)
        } catch {
            // Coba lagi di health check berikutnya
        }
    }

    private func transition(to newState: CameraState) {
        guard newState != currentState else { return }
        let old = currentState
        currentState = newState
        lastStateChangeAt = Date()
        onEvent?(.stateChanged(from: old, to: newState))
        onStateChanged?(newState)
    }
}

// MARK: - CameraSupervisorError

public enum CameraSupervisorError: LocalizedError {
    case cannotCapture(currentState: CameraState)

    public var errorDescription: String? {
        switch self {
        case .cannotCapture(let state):
            return "Kamera tidak dapat mengambil foto saat ini. Status: \(state.displayLabel)"
        }
    }
}

// MARK: - NoOp Camera Runtime (Preview / Testing)

public actor NoOpCameraRuntime: CameraRuntimeProtocol {
    private let simulatedState: CameraState

    public init(simulatedState: CameraState = .ready) {
        self.simulatedState = simulatedState
    }

    public var isConnected: Bool {
        simulatedState != .disconnected && simulatedState != .error
    }

    public func currentFrameQuality() async -> FrameQualityMetric? {
        FrameQualityMetric(exposureVariance: 0.1, focusScore: 0.9, fps: 30)
    }

    public func capturePhoto() async throws -> Data {
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms simulasi
        return Data() // Placeholder
    }

    public func attemptReconnect() async throws {}
}
