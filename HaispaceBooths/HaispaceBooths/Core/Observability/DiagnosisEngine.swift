// DiagnosisEngine.swift
// HaispaceBooths — Core/Observability
//
// Pure engine: PlatformHealthSnapshot → DiagnosisReport
//
// PRINSIP (Principal Engineer):
// - DiagnosisEngine tidak membaca UI — interface-agnostic
// - Bisa dipakai oleh: Mission Control, CLI, REST API, remote monitoring
// - Pure function: analyze(snapshot:) → DiagnosisReport
//
// PIPELINE:
//   Capability → HealthSnapshot → HealthAggregator.collect()
//   → PlatformHealthSnapshot → DiagnosisEngine.analyze()
//   → DiagnosisReport → Mission Control (atau interface lain)
//
// Ref: docs/design/ADR-003_mission_control_boundary.md
// Ref: docs/design/ADR-002_operational_resilience.md — Pilar 3

import Foundation

// MARK: - DiagnosisSeverity

public enum DiagnosisSeverity: Int, Comparable, Sendable {
    case info     = 0
    case warning  = 1
    case critical = 2

    public static func < (lhs: DiagnosisSeverity, rhs: DiagnosisSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - OperatorAction

/// Aksi yang bisa dieksekusi operator dari Mission Control.
/// Dikirim ke WorkflowOrchestrator via send(intent:) — konsisten ADR-001.
public enum OperatorAction: Sendable {
    case retryDelivery(sessionId: String)
    case reconnectCamera
    case reconnectP2P
    case clearUploadQueue
    case exportDiagnosticLog
    case refreshLicense
    case forceResetToLanding
    case acknowledgeAndDismiss
}

// MARK: - DiagnosisEntry

/// Satu diagnosis yang bisa dibaca operator — bukan metrik mentah.
public struct DiagnosisEntry: Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let severity: DiagnosisSeverity
    public let domain: String           // "camera", "p2p", "payment", "delivery", "session"
    public let title: String
    public let description: String
    public let recommendedAction: String
    public let operatorAction: OperatorAction?
    public let relatedSessionId: String?
    public let relatedCorrelationId: String?

    public init(
        severity: DiagnosisSeverity,
        domain: String,
        title: String,
        description: String,
        recommendedAction: String,
        operatorAction: OperatorAction? = nil,
        relatedSessionId: String? = nil,
        relatedCorrelationId: String? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.severity = severity
        self.domain = domain
        self.title = title
        self.description = description
        self.recommendedAction = recommendedAction
        self.operatorAction = operatorAction
        self.relatedSessionId = relatedSessionId
        self.relatedCorrelationId = relatedCorrelationId
    }
}

// MARK: - CameraHealth (Booths domain representation)

public enum CameraHealthLevel: String, Codable, Sendable {
    case ready
    case healthy
    case degraded
    case error
    case unavailable

    public var displayLabel: String {
        switch self {
        case .ready, .healthy: return "Sehat"
        case .degraded: return "Degradasi"
        case .error, .unavailable: return "Error"
        }
    }
}

public struct CameraHealth: Codable, Sendable {
    public let status: CameraHealthLevel
    public let fps: Double
    public let isConnected: Bool

    public init(status: CameraHealthLevel = .ready, fps: Double = 30.0, isConnected: Bool = true) {
        self.status = status
        self.fps = fps
        self.isConnected = isConnected
    }
}

// MARK: - PlatformHealthSnapshot

/// Data bag murni dari HealthAggregator.collect().
/// Tidak ada logic — hanya kumpulan data.
public struct PlatformHealthSnapshot: Sendable {
    public let timestamp: Date
    public let cameraHealth: CameraHealth
    public let editingHealth: EditingHealth
    public let paymentHealth: PaymentHealth
    public let deliveryHealth: DeliveryHealth
    public let p2pHealth: P2PHealth
    public let activeSessionRecord: AuditTrailRecord?
    public let orphanedSessionCount: Int
    public let supervisorHealth: SupervisorHealth  // Supervisor layer data

    public init(
        cameraHealth: CameraHealth,
        editingHealth: EditingHealth,
        paymentHealth: PaymentHealth,
        deliveryHealth: DeliveryHealth,
        p2pHealth: P2PHealth,
        activeSessionRecord: AuditTrailRecord? = nil,
        orphanedSessionCount: Int = 0,
        supervisorHealth: SupervisorHealth = .unavailable
    ) {
        self.timestamp = Date()
        self.cameraHealth = cameraHealth
        self.editingHealth = editingHealth
        self.paymentHealth = paymentHealth
        self.deliveryHealth = deliveryHealth
        self.p2pHealth = p2pHealth
        self.activeSessionRecord = activeSessionRecord
        self.orphanedSessionCount = orphanedSessionCount
        self.supervisorHealth = supervisorHealth
    }
}

// MARK: - SupervisorHealth

/// Data dari Supervisor Layer — hanya tersedia jika supervisor sudah diinisialisasi.
public struct SupervisorHealth: Sendable {
    public let printerState: PrinterState?
    public let printerUptimePercent: Double?
    public let printerLatencyMs: Double?
    public let cameraState: CameraState?
    public let cameraUptimePercent: Double?
    public let cameraLatencyMs: Double?

    /// Apakah printer saat ini bisa mencetak?
    public var printerCanPrint: Bool { printerState?.canPrint ?? false }

    /// Apakah kamera saat ini bisa memulai sesi?
    public var cameraCanStartSession: Bool { cameraState?.canStartSession ?? false }

    /// Default saat supervisor belum di-inject
    public static let unavailable = SupervisorHealth(
        printerState: nil, printerUptimePercent: nil, printerLatencyMs: nil,
        cameraState: nil, cameraUptimePercent: nil, cameraLatencyMs: nil
    )
}

// MARK: - DiagnosisReport

/// Output dari DiagnosisEngine.analyze() — diteruskan ke Mission Control dan IncidentEngine.
public struct DiagnosisReport: Sendable {
    public let generatedAt: Date
    public let entries: [DiagnosisEntry]    // sudah diurutkan: critical → warning → info
    public let snapshotTimestamp: Date
    public let overallHealth: BoothHealth

    public var hasCritical: Bool { entries.contains { $0.severity == .critical } }
    public var criticalCount: Int { entries.filter { $0.severity == .critical }.count }
    public var warningCount: Int { entries.filter { $0.severity == .warning }.count }

    public init(entries: [DiagnosisEntry], snapshotTimestamp: Date, overallHealth: BoothHealth) {
        self.generatedAt = Date()
        self.entries = entries.sorted { $0.severity > $1.severity }
        self.snapshotTimestamp = snapshotTimestamp
        self.overallHealth = overallHealth
    }
}

// MARK: - DiagnosisEngine

/// Pure function engine. Sama input → sama output. Tidak ada state, tidak ada side effect.
/// Interface-agnostic: tidak tahu apakah outputnya ditampilkan di SwiftUI, CLI, atau REST.
public enum DiagnosisEngine {

    /// Analisis PlatformHealthSnapshot dan hasilkan DiagnosisReport.
    public static func analyze(snapshot: PlatformHealthSnapshot) -> DiagnosisReport {
        var entries: [DiagnosisEntry] = []

        entries += analyzeCamera(snapshot.cameraHealth)
        entries += analyzeP2P(snapshot.p2pHealth)
        entries += analyzePayment(snapshot.paymentHealth)
        entries += analyzeDelivery(snapshot.deliveryHealth)
        entries += analyzeOrphanedSessions(count: snapshot.orphanedSessionCount)
        entries += analyzeActiveSession(snapshot.activeSessionRecord)
        entries += analyzeSupervisors(snapshot.supervisorHealth)

        let overallHealth = computeOverallHealth(snapshot: snapshot, entries: entries)

        return DiagnosisReport(entries: entries, snapshotTimestamp: snapshot.timestamp, overallHealth: overallHealth)
    }

    private static func computeOverallHealth(snapshot: PlatformHealthSnapshot, entries: [DiagnosisEntry]) -> BoothHealth {
        // Jika ada komponen yang statusnya belum jelas
        // (Bisa ditambahkan pengecekan spesifik dari snapshot jika perlu)
        
        if entries.contains(where: { $0.severity == .critical && $0.domain == "session" }) {
            return BoothHealth(state: .unhealthy, summary: "Sesi macet. Intervensi operator diperlukan.")
        }
        
        if entries.contains(where: { $0.severity == .critical }) {
            return BoothHealth(state: .unhealthy, summary: "Komponen kritis gagal. Booth tidak bisa melayani tamu berikutnya.")
        }
        
        if entries.contains(where: { $0.severity == .warning }) {
            return BoothHealth(state: .degraded, summary: "Booth berjalan dengan fallback atau performa menurun.")
        }
        
        return BoothHealth(state: .healthy, summary: "Booth siap menerima tamu berikutnya.")
    }

    // MARK: - Domain Analyzers (pure functions)

    private static func analyzeCamera(_ health: CameraHealth) -> [DiagnosisEntry] {
        switch health.status {
        case .ready, .healthy: return []

        case .unavailable:
            return [DiagnosisEntry(
                severity: .critical, domain: "camera",
                title: "Kamera Tidak Terdeteksi",
                description: "iPhone tidak terhubung atau HaispaceCamera tidak berjalan.",
                recommendedAction: "Sambungkan iPhone via USB-C dan buka HaispaceCamera.",
                operatorAction: .reconnectCamera
            )]

        case .error:
            return [DiagnosisEntry(
                severity: .critical, domain: "camera",
                title: "Error Kamera",
                description: "Terjadi kesalahan pada modul kamera.",
                recommendedAction: "Restart HaispaceCamera di iPhone, lalu reconnect.",
                operatorAction: .reconnectCamera
            )]

        case .degraded:
            return [DiagnosisEntry(
                severity: .warning, domain: "camera",
                title: "Kualitas Kamera Menurun",
                description: "Kemungkinan thermal throttling. Performa kamera di bawah optimal.",
                recommendedAction: "Dinginkan iPhone sebelum sesi berikutnya.",
                operatorAction: nil
            )]
        }
    }

    private static func analyzeP2P(_ health: P2PHealth) -> [DiagnosisEntry] {
        switch health.status {
        case .healthy:
            return []

        case .degraded:
            return [DiagnosisEntry(
                severity: .warning, domain: "p2p",
                title: "Koneksi P2P Degradasi",
                description: "Latensi tinggi atau performa jaringan di bawah normal.",
                recommendedAction: "Dekatkan iPhone ke iPad atau cek interferensi WiFi.",
                operatorAction: .reconnectP2P
            )]

        case .unavailable:
            return [DiagnosisEntry(
                severity: .critical, domain: "p2p",
                title: "P2P Tidak Tersedia",
                description: "Multipeer Connectivity gagal diinisialisasi.",
                recommendedAction: "Cek pengaturan WiFi dan Bluetooth di kedua perangkat.",
                operatorAction: .reconnectP2P
            )]
        }
    }

    private static func analyzePayment(_ health: PaymentHealth) -> [DiagnosisEntry] {
        switch health.status {
        case .healthy: return []

        case .degraded:
            return [DiagnosisEntry(
                severity: .warning, domain: "payment",
                title: "Sistem Pembayaran Menurun",
                description: "Terjadi gangguan parsial pada gateway pembayaran.",
                recommendedAction: "Cek koneksi internet dan konfigurasi payment gateway."
            )]

        case .unavailable:
            return [DiagnosisEntry(
                severity: .critical, domain: "payment",
                title: "Error Pembayaran",
                description: "Modul pembayaran tidak tersedia.",
                recommendedAction: "Hubungi tim teknis. Gunakan pembayaran manual sementara."
            )]
        }
    }

    private static func analyzeDelivery(_ health: DeliveryHealth) -> [DiagnosisEntry] {
        switch health.status {
        case .healthy: return []

        case .degraded:
            return [DiagnosisEntry(
                severity: .warning, domain: "delivery",
                title: "Antrian Pengiriman Terhambat",
                description: "Performa pengiriman mengalami degradasi.",
                recommendedAction: "Cek koneksi internet atau hubungkan printer, lalu retry.",
                operatorAction: .retryDelivery(sessionId: "")
            )]

        case .unavailable:
            return [DiagnosisEntry(
                severity: .critical, domain: "delivery",
                title: "Sistem Pengiriman Tidak Tersedia",
                description: "Modul delivery gagal diinisialisasi.",
                recommendedAction: "Restart aplikasi. Jika berlanjut, hubungi tim teknis.",
                operatorAction: .clearUploadQueue
            )]
        }
    }

    private static func analyzeOrphanedSessions(count: Int) -> [DiagnosisEntry] {
        guard count > 0 else { return [] }
        return [DiagnosisEntry(
            severity: .critical, domain: "session",
            title: "\(count) Sesi Tidak Selesai",
            description: "Ada \(count) sesi yang terhenti. Mungkin ada customer yang sudah bayar tapi belum terima foto.",
            recommendedAction: "Buka Recovery Panel di Mission Control untuk meninjau sesi-sesi tersebut."
        )]
    }

    private static func analyzeActiveSession(_ record: AuditTrailRecord?) -> [DiagnosisEntry] {
        guard let record = record, let lastEvent = record.events.last else { return [] }

        let ageSeconds = Date().timeIntervalSince(lastEvent.timestamp)
        guard ageSeconds > 30 else { return [] } // Sesi dianggap macet jika > 30 detik tanpa progres

        return [DiagnosisEntry(
            severity: .critical, domain: "session",
            title: "Sesi Aktif Macet (\(Int(ageSeconds)) detik)",
            description: "Sesi tertahan di tahap '\(record.lastStage.rawValue)' tanpa progres. Tamu berikutnya terblokir.",
            recommendedAction: "Tanyakan ke tamu atau gunakan Force Reset.",
            operatorAction: .forceResetToLanding,
            relatedSessionId: record.sessionId
        )]
    }

    private static func analyzeSupervisors(_ health: SupervisorHealth) -> [DiagnosisEntry] {
        var entries: [DiagnosisEntry] = []

        // Printer analysis
        if let printerState = health.printerState {
            switch printerState {
            case .paperLow:
                entries.append(DiagnosisEntry(
                    severity: .warning, domain: "printer",
                    title: "Kertas Printer Hampir Habis",
                    description: "Sisa kertas mendekati batas minimum. Segera isi ulang sebelum antrian panjang.",
                    recommendedAction: "Isi ulang kertas printer sekarang. Booth masih bisa beroperasi.",
                    operatorAction: .acknowledgeAndDismiss
                ))
            case .paperEmpty:
                entries.append(DiagnosisEntry(
                    severity: .critical, domain: "printer",
                    title: "Kertas Printer Habis",
                    description: "Printer tidak dapat mencetak. Pembayaran baru diblokir otomatis.",
                    recommendedAction: "Isi ulang kertas printer segera. Booth dalam mode standby.",
                    operatorAction: .acknowledgeAndDismiss
                ))
            case .jam:
                entries.append(DiagnosisEntry(
                    severity: .critical, domain: "printer",
                    title: "Kertas Printer Macet (Jam)",
                    description: "Paper jam terdeteksi. Pembayaran baru diblokir otomatis.",
                    recommendedAction: "Buka penutup printer, lepas kertas yang macet, tutup kembali. Jangan paksa.",
                    operatorAction: .acknowledgeAndDismiss
                ))
            case .offline:
                entries.append(DiagnosisEntry(
                    severity: .critical, domain: "printer",
                    title: "Printer Tidak Terhubung",
                    description: "Printer tidak terdeteksi di jaringan. Pembayaran baru diblokir otomatis.",
                    recommendedAction: "Pastikan printer menyala dan terhubung ke WiFi yang sama dengan booth.",
                    operatorAction: .acknowledgeAndDismiss
                ))
            case .ready, .printing, .unknown:
                break
            }
        }

        // Camera analysis
        if let cameraState = health.cameraState {
            switch cameraState {
            case .exposureUnstable:
                entries.append(DiagnosisEntry(
                    severity: .warning, domain: "camera",
                    title: "Pencahayaan Kamera Tidak Stabil",
                    description: "Variance pencahayaan tinggi. Foto mungkin kurang optimal.",
                    recommendedAction: "Pastikan pencahayaan booth merata. Hindari cahaya langsung ke lensa.",
                    operatorAction: .reconnectCamera
                ))
            case .focusTimeout:
                entries.append(DiagnosisEntry(
                    severity: .warning, domain: "camera",
                    title: "Fokus Kamera Timeout",
                    description: "Kamera kesulitan mengunci fokus. Auto-retry sedang berjalan.",
                    recommendedAction: "Pastikan area di depan kamera tidak terlalu gelap atau terlalu terang.",
                    operatorAction: .reconnectCamera
                ))
            case .disconnected:
                entries.append(DiagnosisEntry(
                    severity: .critical, domain: "camera",
                    title: "Kamera Terputus",
                    description: "Koneksi ke kamera terputus. Sesi baru tidak bisa dimulai.",
                    recommendedAction: "Pastikan HaiCamera menyala dan WiFi/Bluetooth aktif. Auto-reconnect sedang berjalan.",
                    operatorAction: .reconnectCamera
                ))
            case .error:
                entries.append(DiagnosisEntry(
                    severity: .critical, domain: "camera",
                    title: "Kamera Error",
                    description: "Kamera mengalami error fatal setelah beberapa kali retry.",
                    recommendedAction: "Restart HaiCamera app, lalu tekan Reconnect di Mission Control.",
                    operatorAction: .reconnectCamera
                ))
            case .ready, .capturing, .warmingUp:
                break
            }
        }

        return entries
    }
}


