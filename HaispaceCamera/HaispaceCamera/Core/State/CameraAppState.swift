// CameraAppState.swift
// HaispaceCamera — Core/State
//
// Root state untuk HaiCamera (iPhone app).
// Jauh lebih sederhana dari HaiBooth karena peran iPhone hanya sebagai kamera.
//
// Ref: docs/design/39_state_architecture.md — HaiCamera State Architecture
// Ref: docs/design/22_haicamera_ux.md — iPhone Black Screen Mode

import Foundation
import Observation
import UIKit
import CoreMedia

// MARK: - CameraStatus

/// Status kamera iPhone
enum CameraStatus: Equatable {
    case standby        // Layar minimal, kamera off, menunggu pairing
    case paired         // Terhubung ke iPad, siap menerima perintah sesi
    case sessionActive  // Sesi foto berlangsung, layar HITAM (brightness = 0)
    case sessionEnded   // Sesi selesai, kembali ke paired mode
    case error(String)  // Error dengan deskripsi

    var displayText: String {
        switch self {
        case .standby: return "Standby"
        case .paired: return "Terhubung"
        case .sessionActive: return "Sesi Aktif"
        case .sessionEnded: return "Sesi Selesai"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isActive: Bool {
        if case .sessionActive = self { return true }
        return false
    }
}

// MARK: - ThermalState

/// State termal perangkat (dari ProcessInfo)
enum CameraThermalState: Int {
    case nominal = 0    // Normal
    case fair = 1       // Agak hangat
    case serious = 2    // Panas — mulai throttle
    case critical = 3   // Sangat panas — throttle agresif

    var displayText: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Hangat"
        case .serious: return "Panas"
        case .critical: return "Sangat Panas"
        }
    }

    static func from(_ processInfoState: ProcessInfo.ThermalState) -> CameraThermalState {
        switch processInfoState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}

// MARK: - CameraAppState

@Observable
@MainActor
final class CameraAppState {

    // MARK: State
    var cameraStatus: CameraStatus = .standby
    var p2p = CameraP2PStore()
    var batteryLevel: Float = 1.0
    var thermalState: CameraThermalState = .nominal

    // Sesi yang aktif — diterima dari iPad via P2P
    var activeSession: CameraSessionInfo?

    // Menyimpan status retake sementara saat pemicu jepret aktif
    var activeRetakePhotoId: String? = nil
    var activeCaptureIndex: Int? = nil

    // Screen brightness management
    private var originalBrightness: CGFloat = UIScreen.main.brightness

    // MARK: Computed

    var isSessionActive: Bool {
        if case .sessionActive = cameraStatus { return true }
        return false
    }

    /// Apakah kondisi aman untuk memulai sesi? (thermal & battery OK)
    var isSafeForSession: Bool {
        thermalState == .nominal || thermalState == .fair
    }

    /// Notifikasi battery level ke iPad
    var batteryWarningLevel: BatteryWarningLevel {
        switch batteryLevel {
        case 0.0..<0.05: return .critical   // < 5%
        case 0.05..<0.20: return .warning   // 5-20%
        default: return .normal
        }
    }

    // MARK: - Session Management

    /// Mulai sesi — terima config dari iPad, set layar jadi HITAM
    @MainActor
    func startSession(_ config: CameraSessionInfo) {
        activeSession = config
        cameraStatus = .sessionActive
        updateStreamingState()
        setScreenBlack(true)
        HaispaceLogger.info("Sesi dimulai di HaiCamera: \(config.sessionId)", category: "session")
    }

    /// Akhiri sesi — kembali ke paired mode, restore brightness
    @MainActor
    func endSession() {
        activeSession = nil
        cameraStatus = .sessionEnded
        updateStreamingState()
        setScreenBlack(false)
        HaispaceLogger.info("Sesi diakhiri di HaiCamera", category: "session")

        // Kembali ke paired setelah 2 detik
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if case .sessionEnded = self.cameraStatus {
                    self.cameraStatus = .paired
                    self.updateStreamingState()
                }
            }
        }
    }

    // MARK: - Screen Control

    /// Layar hitam saat sesi aktif (iPhone tidak visible ke tamu)
    @MainActor
    func setScreenBlack(_ black: Bool) {
        if black {
            originalBrightness = getCurrentBrightness()
            setBrightness(0.0)
        } else {
            setBrightness(originalBrightness)
        }
    }

    @MainActor
    private func getCurrentBrightness() -> CGFloat {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.brightness ?? 0.5
    }

    @MainActor
    private func setBrightness(_ value: CGFloat) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.brightness = value
    }

    // MARK: - Hardware Monitoring

    @MainActor
    func updateBatteryLevel(_ level: Float) {
        batteryLevel = level

        // Kirim warning ke iPad jika battery kritis
        switch batteryWarningLevel {
        case .critical:
            // TODO: Fase 1 — kirim P2PMessage.cameraStatus ke iPad
            HaispaceLogger.critical("Battery KRITIS: \(Int(level * 100))%", category: "battery")
        case .warning:
            HaispaceLogger.warning("Battery low: \(Int(level * 100))%", category: "battery")
        case .normal:
            break
        }
    }

    @MainActor
    func updateThermalState(_ state: ProcessInfo.ThermalState) {
        let mapped = CameraThermalState.from(state)
        thermalState = mapped

        if mapped == .serious || mapped == .critical {
            HaispaceLogger.warning("Thermal state: \(mapped.displayText)", category: "thermal")
            // TODO: Fase 1 — kirim notifikasi ke iPad via P2P
        }
    }

    // MARK: - App Lifecycle

    @MainActor
    func setup() async {
        HaispaceLogger.info("[setup] Langkah 1: battery monitoring", category: "app")
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        thermalState = CameraThermalState.from(ProcessInfo.processInfo.thermalState)
        
        HaispaceLogger.info("[setup] Langkah 2: setupCameraPipeline", category: "app")
        setupCameraPipeline()
        
        HaispaceLogger.info("[setup] Langkah 3: register connection callback", category: "app")
        // Setup connection callbacks
        await P2PClientService.shared.registerConnectionStateCallback { [weak self] state in
            Task { @MainActor in
                self?.p2p.updateConnectionState(state)
                switch state {
                case .connected:
                    HaispaceLogger.info("P2P connected — switching to paired state", category: "app")
                    self?.cameraStatus = .paired
                    self?.updateStreamingState()
                    // Haptic feedback sukses
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    // Resume transfer queue!
                    Task {
                        await PhotoTransferService.shared.resumeTransferQueue()
                    }
                case .disconnected:
                    self?.cameraStatus = .standby
                    self?.updateStreamingState()
                    R2LogUploader.uploadLatestLog(eventName: "iphone_disconnected")
                    // Mulai proses menghubungkan kembali (auto-reconnect)
                    if let payload = self?.p2p.lastPairingPayload {
                        self?.p2p.startReconnection(payload: payload)
                    }
                case .failed(let reason):
                    self?.cameraStatus = .standby
                    self?.updateStreamingState()
                    let cleanErr = reason.replacingOccurrences(of: " ", with: "_")
                    R2LogUploader.uploadLatestLog(eventName: "iphone_failed_\(cleanErr)")
                    // Haptic feedback error
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    
                    // Lakukan auto-reconnect hanya jika bukan kesalahan payload kedaluwarsa atau tanda tangan salah
                    if reason != "QR Expired" && reason != "Invalid Signature" {
                        if let payload = self?.p2p.lastPairingPayload {
                            self?.p2p.startReconnection(payload: payload)
                        }
                    }
                default:
                    break
                }
            }
        }
        
        HaispaceLogger.info("[setup] Langkah 4: register data callback", category: "app")
        // Setup data message callback
        await P2PClientService.shared.registerDataCallback { [weak self] data in
            guard let message = try? P2PMessage.decode(from: data) else { return }
            Task { @MainActor in
                self?.handleIncomingMessage(message)
            }
        }
        
        HaispaceLogger.info("HaiCamera setup selesai", category: "app")
    }
    
    @MainActor
    private func setupCameraPipeline() {
        // Setup capture service callbacks
        HaispaceLogger.info("[setupPipeline] Configuring capture callbacks", category: "app")
        CameraCaptureService.shared.onVideoFrameCaptured = { [weak self] sampleBuffer in
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
                VideoEncoderService.shared.configure(width: dimensions.width, height: dimensions.height)
            }
            VideoEncoderService.shared.encode(sampleBuffer: sampleBuffer)
            
            guard let self = self else { return }
            if CameraCaptureService.shared.isSessionActive {
                HandGestureDetector.shared.processFrame(sampleBuffer) {
                    // FIX: Gunakan isConnectedSync() dan sendDataSync() — tidak ada actor hop per frame
                    if P2PClientService.shared.isConnectedSync(),
                       let gestureMsg = try? P2PMessage.gestureDetected.encode() {
                        P2PClientService.shared.sendDataSync(gestureMsg)
                        HaispaceLogger.info("Gesture 'Hai' terdeteksi! Mengirim sinyal pemicu ke iPad.", category: "camera")
                        
                        // Feedback haptic pada iPhone saat gesture berhasil dibaca
                        DispatchQueue.main.async {
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                    }
                }
            }
        }
        
        CameraCaptureService.shared.onPhotoCaptured = { [weak self] photo in
            Task { @MainActor in
                guard let self = self else { return }
                let photoId = self.activeRetakePhotoId ?? UUID().uuidString
                let sortOrder = self.activeCaptureIndex ?? 0
                
                // Feedback haptic pada iPhone saat berhasil mengambil foto (shutter)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                // Reset state setelah terpakai
                self.activeRetakePhotoId = nil
                self.activeCaptureIndex = nil
                
                await PhotoTransferService.shared.handleNewCapture(photoId: photoId, capture: photo, sortOrder: sortOrder)
            }
        }
        
        // Setup encoder callback
        // FIX: Gunakan sendDataSync() — tidak ada actor hop untuk setiap NALU (30-60 kali per detik!)
        // Sebelumnya: Task { if await isConnected() { try? await sendData(nalu) } } — ini menyebabkan
        // ratusan Task mengantre di P2PClientService actor dalam hitungan detik → watchdog kill.
        VideoEncoderService.shared.setOnNALUReady { nalu in
            if P2PClientService.shared.isConnectedSync() {
                P2PClientService.shared.sendDataSync(nalu)
            }
        }
    }
    
    @MainActor
    func updateStreamingState() {
        CameraCaptureService.shared.isSessionActive = (cameraStatus == .sessionActive)
        
        switch cameraStatus {
        case .paired, .sessionActive:
            CameraCaptureService.shared.configureAndStart()
        default:
            CameraCaptureService.shared.stop()
        }
    }
    
    @MainActor
    private func handleIncomingMessage(_ message: P2PMessage) {
        switch message {
        case .sessionStart(let config):
            let cameraSession = CameraSessionInfo(
                sessionId: config.sessionId,
                packageDuration: config.totalDurationSeconds,
                intervalSeconds: config.intervalSeconds,
                photoCapturedCount: 0,
                remainingSeconds: config.totalDurationSeconds
            )
            self.startSession(cameraSession)
            
        case .triggerCapture(let poseId, let index):
            HaispaceLogger.info("Menerima trigger jepret dari iPad (indeks: \(index), replace ID: \(String(describing: poseId)))", category: "camera")
            self.activeRetakePhotoId = poseId
            self.activeCaptureIndex = index
            CameraCaptureService.shared.captureHighQualityPhoto()
            
        case .sessionEnd:
            self.endSession()
            
        case .focusPoint(let x, let y):
            CameraCaptureService.shared.setFocusAndExposurePoint(x: x, y: y)
            
        case .setZoom(let factor):
            CameraCaptureService.shared.setZoom(factor: CGFloat(factor))
            
        case .setPortraitMode(let enabled):
            CameraCaptureService.shared.setPortraitMode(enabled: enabled)
            
        default:
            break
        }
    }
}

// MARK: - CameraSessionInfo

/// Informasi sesi yang diterima dari iPad via P2P
struct CameraSessionInfo {
    let sessionId: String
    let packageDuration: Int        // Durasi total sesi dalam detik
    let intervalSeconds: Int        // Jeda antar foto otomatis
    var photoCapturedCount: Int     // Sudah berapa foto diambil
    var remainingSeconds: Int       // Sisa waktu sesi
}

// MARK: - Battery Warning Level

enum BatteryWarningLevel {
    case normal
    case warning    // 5-20%
    case critical   // < 5%
}

// MARK: - Preview Mock

extension CameraAppState {
    static var preview: CameraAppState {
        let state = CameraAppState()
        state.cameraStatus = .paired
        state.batteryLevel = 0.85
        state.thermalState = .nominal
        state.p2p.connectionState = .connected
        return state
    }

    static var previewActive: CameraAppState {
        let state = CameraAppState()
        state.cameraStatus = .sessionActive
        state.activeSession = CameraSessionInfo(
            sessionId: "preview-session",
            packageDuration: 300,
            intervalSeconds: 8,
            photoCapturedCount: 3,
            remainingSeconds: 247
        )
        state.batteryLevel = 0.72
        state.thermalState = .nominal
        return state
    }
}

// MARK: - HaispaceLogger for Camera (same struct, different subsystem)
// Camera uses the same Logger struct defined in HaispaceBooths's Logger.swift
// Since these are separate targets, HaispaceCamera needs its own copy.
// See Core/Logging/Logger.swift in HaispaceCamera target.
