// IncidentEngine.swift
// HaispaceBooths — Core/Observability
//
// Mengevaluasi kombinasi diagnosis untuk menentukan apakah kondisi
// menjadi sebuah INSIDEN yang memerlukan perhatian khusus operator.
//
// PERBEDAAN DIAGNOSIS vs INSIDEN (Principal Engineer):
//
//   Diagnosis: "Printer offline"
//   → bisa terjadi 10 detik saat operator sedang reboot printer
//
//   Insiden: Printer offline + payment confirmed + retry > 3
//   → ada customer yang sudah bayar, fotonya tidak terkirim, sudah dicoba 3x
//   → ini baru menjadi insiden
//
// Mission Control menampilkan:
//   Diagnosis  47    ← banyak, operator akan filter mental
//   Incident    2    ← sedikit, operator langsung fokus
//
// PIPELINE LENGKAP:
//   HealthAggregator.collect() → PlatformHealthSnapshot
//       ↓
//   DiagnosisEngine.analyze()  → DiagnosisReport
//       ↓
//   IncidentEngine.evaluate()  → IncidentReport
//       ↓
//   Mission Control (ADR-003: hanya memvisualisasikan)
//
// Ref: docs/design/ADR-002_operational_resilience.md
// Ref: docs/design/ADR-003_mission_control_boundary.md

import Foundation

// MARK: - IncidentSeverity

public enum IncidentSeverity: Int, Comparable, Sendable {
    case info     = 0
    case low      = 1
    case medium   = 2
    case high     = 3
    case critical = 4

    public static func < (lhs: IncidentSeverity, rhs: IncidentSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayLabel: String {
        switch self {
        case .critical: return "🔴 KRITIS"
        case .high:     return "🟠 TINGGI"
        case .medium:   return "🟡 SEDANG"
        case .low:      return "🔵 RENDAH"
        case .info:     return "⚪️ INFO"
        }
    }
}

// MARK: - IncidentState

/// Lifecycle sebuah insiden dari terdeteksi hingga selesai.
/// Operator mengelola state ini dari Mission Control.
public enum IncidentState: String, Codable, Sendable, CaseIterable {
    case detected       // baru terdeteksi oleh IncidentEngine
    case acknowledged   // operator sudah melihat dan mengakui
    case mitigating     // operator sedang menangani
    case resolved       // masalah sudah selesai
    case archived       // disimpan untuk referensi historis

    public var displayLabel: String {
        switch self {
        case .detected:     return "Baru"
        case .acknowledged: return "Diakui"
        case .mitigating:   return "Ditangani"
        case .resolved:     return "Selesai"
        case .archived:     return "Diarsipkan"
        }
    }

    /// Apakah insiden ini masih aktif (perlu perhatian operator)?
    public var isActive: Bool {
        switch self {
        case .detected, .acknowledged, .mitigating: return true
        case .resolved, .archived: return false
        }
    }

    /// Transisi yang valid dari state ini
    public var validTransitions: [IncidentState] {
        switch self {
        case .detected:     return [.acknowledged, .resolved]
        case .acknowledged: return [.mitigating, .resolved]
        case .mitigating:   return [.resolved]
        case .resolved:     return [.archived]
        case .archived:     return []
        }
    }
}

// MARK: - Incident

/// Sebuah insiden yang memerlukan perhatian operator.
/// Berisi referensi ke diagnoses yang membentuknya untuk full traceability.
public struct Incident: Identifiable, Sendable {
    public let id: String
    public let detectedAt: Date
    public let severity: IncidentSeverity
    public var state: IncidentState           // mutable — dikelola operator
    public var acknowledgedAt: Date?
    public var resolvedAt: Date?
    public let title: String
    public let summary: String
    public let relatedDiagnosisIds: [String]
    public let relatedSessionId: String?
    public let relatedCorrelationId: String?
    public let suggestedAction: OperatorAction?
    public let context: [String: String]

    public init(
        severity: IncidentSeverity,
        title: String,
        summary: String,
        relatedDiagnosisIds: [String] = [],
        relatedSessionId: String? = nil,
        relatedCorrelationId: String? = nil,
        suggestedAction: OperatorAction? = nil,
        context: [String: String] = [:]
    ) {
        self.id = UUID().uuidString
        self.detectedAt = Date()
        self.severity = severity
        self.state = .detected              // selalu mulai dari .detected
        self.acknowledgedAt = nil
        self.resolvedAt = nil
        self.title = title
        self.summary = summary
        self.relatedDiagnosisIds = relatedDiagnosisIds
        self.relatedSessionId = relatedSessionId
        self.relatedCorrelationId = relatedCorrelationId
        self.suggestedAction = suggestedAction
        self.context = context
    }
}

// MARK: - IncidentReport

/// Output dari IncidentEngine.evaluate() — diteruskan langsung ke Mission Control.
public struct IncidentReport: Sendable {
    public let generatedAt: Date
    public let incidents: [Incident]

    /// Hanya insiden yang masih aktif (belum resolved/archived)
    public var activeIncidents: [Incident] { incidents.filter { $0.state.isActive } }
    public var hasActiveIncidents: Bool { !activeIncidents.isEmpty }
    public var criticalCount: Int { activeIncidents.filter { $0.severity == .critical }.count }
    public var highCount: Int { activeIncidents.filter { $0.severity == .high }.count }

    public init(incidents: [Incident]) {
        self.generatedAt = Date()
        // Urutkan: critical → high → medium → low → info, kemudian by detectedAt
        self.incidents = incidents.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.detectedAt < $1.detectedAt
        }
    }

    public static let empty = IncidentReport(incidents: [])
}

// MARK: - IncidentEngine

/// Pure engine yang mengevaluasi kombinasi diagnosis.
/// Satu diagnosis saja belum tentu insiden.
/// Insiden adalah diagnosis + konteks (retry count, financial transaction, dll.)
public enum IncidentEngine {

    /// Evaluasi DiagnosisReport + konteks audit trail → IncidentReport.
    /// Pure function: tidak ada state, tidak ada side effect.
    public static func evaluate(
        diagnosisReport: DiagnosisReport,
        snapshot: PlatformHealthSnapshot
    ) -> IncidentReport {
        var incidents: [Incident] = []

        // Evaluasi setiap rule secara independen
        incidents += evaluatePaidButNotDelivered(diagnosisReport, snapshot)
        incidents += evaluateDeliveryStuck(diagnosisReport, snapshot)
        incidents += evaluateCameraDownDuringSesion(diagnosisReport, snapshot)
        incidents += evaluateP2PDownDuringCapture(diagnosisReport, snapshot)
        incidents += evaluateOrphanedWithPayment(diagnosisReport, snapshot)
        incidents += evaluateSessionStuck(diagnosisReport, snapshot)

        return IncidentReport(incidents: incidents)
    }

    // MARK: - Incident Rules (setiap rule adalah pure function)

    /// Rule: Delivery gagal + payment sudah confirmed + retry > N = P0
    private static func evaluatePaidButNotDelivered(
        _ report: DiagnosisReport,
        _ snapshot: PlatformHealthSnapshot
    ) -> [Incident] {
        guard let record = snapshot.activeSessionRecord,
              record.hasFinancialTransaction else { return [] }

        let deliveryDiagnoses = report.entries.filter { $0.domain == "delivery" && $0.severity == .critical }
        guard !deliveryDiagnoses.isEmpty else { return [] }

        let retryCount = record.deliveryRetryCount
        guard retryCount > 0 else { return [] }

        return [Incident(
            severity: .critical,
            title: "Customer Sudah Bayar — Foto Tidak Terkirim",
            summary: "Delivery gagal \(retryCount)x setelah pembayaran dikonfirmasi.",
            relatedDiagnosisIds: deliveryDiagnoses.map { $0.id },
            relatedSessionId: record.sessionId,
            suggestedAction: .retryDelivery(sessionId: record.sessionId),
            context: ["retryCount": "\(retryCount)", "lastStage": record.lastStage.rawValue]
        )]
    }

    private static func evaluateDeliveryStuck(
        _ report: DiagnosisReport,
        _ snapshot: PlatformHealthSnapshot
    ) -> [Incident] {
        guard snapshot.deliveryHealth.status == .degraded || snapshot.deliveryHealth.status == .unavailable else { return [] }
        let relatedIds = report.entries.filter { $0.domain == "delivery" }.map { $0.id }
        return [Incident(
            severity: .high,
            title: "Antrian Pengiriman Tersumbat",
            summary: "Pengiriman foto mengalami masalah.",
            relatedDiagnosisIds: relatedIds,
            suggestedAction: .retryDelivery(sessionId: ""),
            context: [:]
        )]
    }

    private static func evaluateCameraDownDuringSesion(
        _ report: DiagnosisReport,
        _ snapshot: PlatformHealthSnapshot
    ) -> [Incident] {
        guard snapshot.cameraHealth.status == .unavailable,
              snapshot.activeSessionRecord != nil else { return [] }
        let relatedIds = report.entries.filter { $0.domain == "camera" }.map { $0.id }
        return [Incident(
            severity: .high,
            title: "Kamera Mati Saat Sesi Aktif",
            summary: "Ada tamu di sesi aktif tapi kamera tidak terdeteksi.",
            relatedDiagnosisIds: relatedIds,
            relatedSessionId: snapshot.activeSessionRecord?.sessionId,
            suggestedAction: .reconnectCamera
        )]
    }

    private static func evaluateP2PDownDuringCapture(
        _ report: DiagnosisReport,
        _ snapshot: PlatformHealthSnapshot
    ) -> [Incident] {
        guard snapshot.p2pHealth.status == .unavailable || snapshot.p2pHealth.status == .degraded,
              let record = snapshot.activeSessionRecord,
              record.lastStage == .capturing else { return [] }
        let relatedIds = report.entries.filter { $0.domain == "p2p" }.map { $0.id }
        return [Incident(
            severity: .high,
            title: "Koneksi Terputus Saat Pengambilan Foto",
            summary: "P2P terputus saat tamu di tahap capture.",
            relatedDiagnosisIds: relatedIds,
            relatedSessionId: record.sessionId,
            suggestedAction: .reconnectP2P
        )]
    }

    private static func evaluateOrphanedWithPayment(
        _ report: DiagnosisReport,
        _ snapshot: PlatformHealthSnapshot
    ) -> [Incident] {
        guard snapshot.orphanedSessionCount > 0 else { return [] }
        let orphans = SessionAuditTrail.findOrphanedSessions()
        let paidOrphans = orphans.filter { $0.hasFinancialTransaction }
        guard !paidOrphans.isEmpty else { return [] }
        let relatedIds = report.entries.filter { $0.domain == "session" }.map { $0.id }
        return [Incident(
            severity: .critical,
            title: "\(paidOrphans.count) Customer Sudah Bayar — Sesi Terhenti",
            summary: "\(paidOrphans.count) sesi crash setelah pembayaran. Customer mungkin tidak menerima foto.",
            relatedDiagnosisIds: relatedIds,
            context: ["paidOrphanCount": "\(paidOrphans.count)"]
        )]
    }

    private static func evaluateSessionStuck(
        _ report: DiagnosisReport,
        _ snapshot: PlatformHealthSnapshot
    ) -> [Incident] {
        guard let record = snapshot.activeSessionRecord,
              let lastEvent = record.events.last else { return [] }
        let ageMinutes = Date().timeIntervalSince(lastEvent.timestamp) / 60
        guard ageMinutes > 10 else { return [] }
        let relatedIds = report.entries.filter { $0.domain == "session" }.map { $0.id }
        return [Incident(
            severity: .medium,
            title: "Sesi Tampak Terbengkalai (\(Int(ageMinutes)) menit)",
            summary: "Tidak ada aktivitas selama \(Int(ageMinutes)) menit.",
            relatedDiagnosisIds: relatedIds,
            relatedSessionId: record.sessionId,
            suggestedAction: .forceResetToLanding,
            context: ["idleMinutes": "\(Int(ageMinutes))", "lastStage": record.lastStage.rawValue]
        )]
    }
}
