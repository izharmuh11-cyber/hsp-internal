// PrinterSupervisor.swift
// HaispaceBooths — Core/Supervisors
//
// State machine supervisor untuk printer fisik (Epson L8050 / generic dye-sub).
//
// STATE MACHINE:
//
//   UNKNOWN ──────────────────────────────────────────────► OFFLINE
//      │                                                       ▲
//      ▼                                                       │
//   READY ◄──────────────────────────────────────────────────►│
//      │                                                       │
//      ├──► PRINTING ──► READY (selesai)                      │
//      │         └─────► JAM ──────────────────────────────────┤
//      │                                                       │
//      ├──► PAPER_LOW ──► READY (kertas diisi ulang)          │
//      └──► PAPER_EMPTY ──► READY (kertas diisi ulang)        │
//
// KONTRAK OPERASIONAL:
//   - Saat PAPER_LOW  → warning ke MissionControl (masih bisa cetak)
//   - Saat PAPER_EMPTY/JAM/OFFLINE → block payment + alert operator
//   - Saat kembali ke READY → MissionControl incident auto-resolved
//
// PROTOKOL:
//   PrinterSupervisor berkomunikasi via PrinterRuntimeProtocol (abstrak).
//   Implementasi konkret (Epson WiFi, USB, Bluetooth) berada di Services/Printer/.
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar 4: Supervisor Layer

import Foundation

// MARK: - PrinterState

public enum PrinterState: String, Codable, Sendable, CaseIterable {
    case unknown        = "unknown"       // Belum pernah di-probe
    case ready          = "ready"         // Siap cetak
    case printing       = "printing"      // Sedang mencetak
    case paperLow       = "paper_low"     // Kertas < 20 lembar (estimasi)
    case paperEmpty     = "paper_empty"   // Kertas habis, tidak bisa cetak
    case jam            = "jam"           // Paper jam, perlu intervensi manual
    case offline        = "offline"       // Tidak terkoneksi / power off

    /// Apakah booth bisa menerima pembayaran & mencetak?
    public var canPrint: Bool {
        switch self {
        case .ready, .paperLow: return true
        case .printing, .unknown, .paperEmpty, .jam, .offline: return false
        }
    }

    /// Apakah operator harus segera bertindak?
    public var requiresOperatorAction: Bool {
        switch self {
        case .paperEmpty, .jam, .offline: return true
        default: return false
        }
    }

    /// Label untuk MissionControl dashboard
    public var displayLabel: String {
        switch self {
        case .unknown:      return "Memeriksa..."
        case .ready:        return "Siap"
        case .printing:     return "Mencetak"
        case .paperLow:     return "Kertas Hampir Habis"
        case .paperEmpty:   return "Kertas Habis"
        case .jam:          return "Kertas Macet"
        case .offline:      return "Tidak Terhubung"
        }
    }

    /// Warna status untuk dashboard
    public var statusColor: StatusColor {
        switch self {
        case .ready:        return .green
        case .printing:     return .blue
        case .paperLow:     return .yellow
        case .unknown:      return .gray
        case .paperEmpty, .jam, .offline: return .red
        }
    }

    public enum StatusColor: String, Sendable {
        case green, yellow, blue, red, gray
    }
}

// MARK: - PrinterEvent

public enum PrinterEvent: Sendable {
    case stateChanged(from: PrinterState, to: PrinterState)
    case printJobStarted(sessionId: String)
    case printJobCompleted(sessionId: String, durationMs: Int)
    case printJobFailed(sessionId: String, reason: String)
    case paperLevelWarning(estimatedSheetsRemaining: Int)
    case connectionRestored
    case connectionLost
}

// MARK: - PrinterRuntimeProtocol (Abstrak)

/// Abstraksi komunikasi dengan hardware printer.
/// Implementasi konkret (Epson, Canon, Generic) berada di Services/Printer/.
public protocol PrinterRuntimeProtocol: Sendable {
    /// Probe printer dan dapatkan state terkini
    func probe() async -> PrinterProbeResult

    /// Kirim print job
    func print(data: Data, sessionId: String) async throws

    /// Cancel print job yang sedang berjalan
    func cancelCurrentJob() async
}

public struct PrinterProbeResult: Sendable {
    public let state: PrinterState
    public let estimatedSheetsRemaining: Int?
    public let firmwareVersion: String?
    public let modelName: String?
    public let ipAddress: String?
    public let latencyMs: Double?   // Waktu probe — metrik performa

    public init(
        state: PrinterState,
        estimatedSheetsRemaining: Int? = nil,
        firmwareVersion: String? = nil,
        modelName: String? = nil,
        ipAddress: String? = nil,
        latencyMs: Double? = nil
    ) {
        self.state = state
        self.estimatedSheetsRemaining = estimatedSheetsRemaining
        self.firmwareVersion = firmwareVersion
        self.modelName = modelName
        self.ipAddress = ipAddress
        self.latencyMs = latencyMs
    }
}

// MARK: - PrinterSupervisor

public actor PrinterSupervisor {

    // MARK: - Configuration

    /// Interval polling state printer (default: 30 detik)
    public static let pollingIntervalSeconds: TimeInterval = 30

    /// Batas kertas untuk trigger PAPER_LOW warning
    public static let paperLowThreshold: Int = 20

    // MARK: - State

    private(set) public var currentState: PrinterState = .unknown
    private(set) public var lastProbeResult: PrinterProbeResult?
    private(set) public var lastStateChangeAt: Date = Date()
    private(set) public var uptimePercent: Double = 0
    private(set) public var lastLatencyMs: Double?

    private var totalPollCount: Int = 0
    private var readyPollCount: Int = 0
    private var isMonitoring = false

    private let runtime: PrinterRuntimeProtocol

    // Callbacks (MainActor-isolated untuk SwiftUI)
    public var onEvent: ((PrinterEvent) -> Void)?
    public var onStateChanged: ((PrinterState) -> Void)?

    // MARK: - Init

    public init(runtime: PrinterRuntimeProtocol) {
        self.runtime = runtime
    }

    // MARK: - Lifecycle

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Probe segera saat start
        Task { await performProbe() }

        // Lanjut polling periodik
        scheduleNextPoll()
    }

    public func stopMonitoring() {
        isMonitoring = false
    }

    // MARK: - Print Job Delegation

    /// Cetak foto — hanya bisa jika state memungkinkan
    public func printPhoto(data: Data, sessionId: String) async throws {
        guard currentState.canPrint else {
            throw PrinterSupervisorError.cannotPrint(currentState: currentState)
        }

        let previousState = currentState
        transition(to: .printing)
        onEvent?(.printJobStarted(sessionId: sessionId))

        let start = Date()
        do {
            try await runtime.print(data: data, sessionId: sessionId)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            onEvent?(.printJobCompleted(sessionId: sessionId, durationMs: durationMs))

            // Probe setelah selesai untuk update state
            await performProbe()
        } catch {
            onEvent?(.printJobFailed(sessionId: sessionId, reason: error.localizedDescription))
            transition(to: previousState)
            throw error
        }
    }

    // MARK: - Manual Probe (dari operator)

    public func manualProbe() async {
        await performProbe()
    }

    // MARK: - Private: State Machine

    private func transition(to newState: PrinterState) {
        guard newState != currentState else { return }

        let oldState = currentState
        currentState = newState
        lastStateChangeAt = Date()

        onEvent?(.stateChanged(from: oldState, to: newState))
        onStateChanged?(newState)
    }

    private func performProbe() async {
        let result = await runtime.probe()
        lastProbeResult = result
        lastLatencyMs = result.latencyMs

        totalPollCount += 1

        // Update state dari probe result
        let newState = result.state
        transition(to: newState)

        // Track uptime (READY = available)
        if newState == .ready || newState == .printing {
            readyPollCount += 1
        }
        uptimePercent = totalPollCount > 0
            ? Double(readyPollCount) / Double(totalPollCount) * 100
            : 0

        // Paper low warning
        if let sheets = result.estimatedSheetsRemaining,
           sheets <= Self.paperLowThreshold,
           newState == .ready {
            onEvent?(.paperLevelWarning(estimatedSheetsRemaining: sheets))
        }

        // Connectivity events
        if newState == .offline && currentState != .offline {
            onEvent?(.connectionLost)
        } else if newState != .offline && currentState == .offline {
            onEvent?(.connectionRestored)
        }
    }

    private func scheduleNextPoll() {
        Task {
            try? await Task.sleep(
                nanoseconds: UInt64(Self.pollingIntervalSeconds * 1_000_000_000)
            )
            if isMonitoring {
                await performProbe()
                scheduleNextPoll()
            }
        }
    }
}

// MARK: - PrinterSupervisor Error

public enum PrinterSupervisorError: LocalizedError {
    case cannotPrint(currentState: PrinterState)

    public var errorDescription: String? {
        switch self {
        case .cannotPrint(let state):
            return "Printer tidak dapat mencetak saat ini. Status: \(state.displayLabel)"
        }
    }
}

// MARK: - NoOp Printer Runtime (untuk Preview / Testing)

public actor NoOpPrinterRuntime: PrinterRuntimeProtocol {
    private let simulatedState: PrinterState

    public init(simulatedState: PrinterState = .ready) {
        self.simulatedState = simulatedState
    }

    public func probe() async -> PrinterProbeResult {
        PrinterProbeResult(
            state: simulatedState,
            estimatedSheetsRemaining: 45,
            modelName: "Epson L8050 (Simulated)",
            latencyMs: 12.5
        )
    }

    public func print(data: Data, sessionId: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s simulasi
    }

    public func cancelCurrentJob() async {}
}
