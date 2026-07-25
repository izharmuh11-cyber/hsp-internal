// MissionControlSnapshot.swift
// HaispaceBooths — Core/Observability
//
// Satu objek agregat stabil yang membawa semua data yang dibutuhkan
// Mission Control untuk dirender. ViewModel hanya membungkus ini.
//
// PRINSIP (Principal Engineer):
// Daripada 20 publisher yang terpisah, Mission Control menerima
// satu snapshot yang koheren dan di-generate pada satu titik waktu.
//
//   MissionControlViewModel.refresh()
//       ↓
//   MissionControlSnapshot
//       ↓
//   SwiftUI View (hanya render, sesuai ADR-003)
//
// Ref: docs/design/ADR-003_mission_control_boundary.md
// Ref: docs/design/ADR-004_operational_data_ownership.md

import Foundation

// MARK: - AuditSummary

/// Ringkasan aktivitas audit untuk hari ini — tidak mengekspos raw trail ke View.
public struct AuditSummary: Sendable {
    public let generatedAt: Date
    public let totalSessionsToday: Int
    public let completedSessions: Int
    public let abandonedSessions: Int
    public let orphanedSessions: Int        // sesi yang crash/terhenti
    public let lastSessionCompletedAt: Date?
    public let averageSessionDurationMinutes: Double?

    public var completionRate: Double {
        guard totalSessionsToday > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessionsToday)
    }

    /// Hasilkan AuditSummary dari semua trail yang ada di disk.
    public static func generate() -> AuditSummary {
        let orphans = SessionAuditTrail.findOrphanedSessions()

        // Kumpulkan semua trail (simplified — production implementation bisa query by date)
        // Untuk sekarang: hitung dari orphan count sebagai proxy
        return AuditSummary(
            generatedAt: Date(),
            totalSessionsToday: 0,      // TODO: implement full session store query
            completedSessions: 0,
            abandonedSessions: 0,
            orphanedSessions: orphans.count,
            lastSessionCompletedAt: nil,
            averageSessionDurationMinutes: nil
        )
    }
}

// MARK: - OperationalKPIs

/// Key Performance Indicators untuk platform operasional.
/// Diisi oleh KPICollector dan dibawa dalam MissionControlSnapshot.
public struct OperationalKPIs: Sendable {

    // Workflow
    public let workflowSuccessRate: Double          // 0.0 - 1.0
    public let abandonedSessionCount: Int
    public let averageWorkflowDurationSeconds: TimeInterval?

    // Recovery
    public let orphanRecoverySuccessRate: Double    // berapa % orphan berhasil di-resume
    public let uploadRetrySuccessRate: Double
    public let paymentRecoverySuccessRate: Double

    // Hardware Uptime (rolling, sejak app start atau N jam terakhir)
    public let printerUptimePercent: Double         // 0.0 - 100.0
    public let cameraUptimePercent: Double
    public let p2pUptimePercent: Double

    // Operations
    public let incidentsToday: Int
    public let activeIncidentCount: Int
    public let meanTimeToResolveSeconds: TimeInterval?  // rata-rata waktu dari detected → resolved
    public let acknowledgementLatencySeconds: TimeInterval?

    /// KPI kosong saat belum ada data
    public static let empty = OperationalKPIs(
        workflowSuccessRate: 0,
        abandonedSessionCount: 0,
        averageWorkflowDurationSeconds: nil,
        orphanRecoverySuccessRate: 0,
        uploadRetrySuccessRate: 0,
        paymentRecoverySuccessRate: 0,
        printerUptimePercent: 0,
        cameraUptimePercent: 0,
        p2pUptimePercent: 0,
        incidentsToday: 0,
        activeIncidentCount: 0,
        meanTimeToResolveSeconds: nil,
        acknowledgementLatencySeconds: nil
    )
}

// MARK: - MissionControlSnapshot

/// Satu objek agregat stabil — kontrak antara ViewModel dan SwiftUI.
/// Di-generate sekali per refresh cycle, di-pass ke View sebagai satu unit.
///
/// View tidak perlu tahu siapa yang menghasilkan tiap bagian data ini.
/// View hanya tahu: "Saya punya snapshot, saya render."
public struct MissionControlSnapshot: Sendable {
    public let generatedAt: Date
    public let platformHealth: PlatformHealthSnapshot
    public let diagnosis: DiagnosisReport
    public let incidents: IncidentReport
    public let auditSummary: AuditSummary
    public let kpis: OperationalKPIs

    // MARK: - Convenience computed properties untuk View binding

    /// Jumlah insiden aktif yang perlu perhatian operator segera
    public var activeIncidentCount: Int { incidents.activeIncidents.count }

    /// Apakah ada insiden critical atau high yang belum di-acknowledge?
    public var requiresImmediateAttention: Bool {
        incidents.activeIncidents.contains {
            ($0.severity == .critical || $0.severity == .high) && $0.state == .detected
        }
    }

    /// Label singkat untuk status keseluruhan platform
    public var overallStatusLabel: String {
        if incidents.criticalCount > 0 { return "Kritis" }
        if incidents.highCount > 0 { return "Perhatian" }
        if diagnosis.hasCritical { return "Waspada" }
        return "Normal"
    }

    /// Warna status untuk indicator di header Mission Control
    public var overallStatusColor: StatusColor {
        if incidents.criticalCount > 0 { return .red }
        if incidents.highCount > 0 { return .orange }
        if diagnosis.hasCritical { return .yellow }
        return .green
    }

    public enum StatusColor: String, Sendable {
        case green, yellow, orange, red
    }

    // MARK: - Empty snapshot untuk loading state

    public static func loading() -> MissionControlSnapshot {
        MissionControlSnapshot(
            generatedAt: Date(),
            platformHealth: PlatformHealthSnapshot(
                cameraHealth: CameraHealth(status: .unavailable),
                editingHealth: EditingHealth(status: .unavailable),
                paymentHealth: PaymentHealth(status: .unavailable),
                deliveryHealth: DeliveryHealth(status: .unavailable),
                p2pHealth: P2PHealth(status: .unavailable)
            ),
            diagnosis: DiagnosisReport(entries: [], snapshotTimestamp: Date(), overallHealth: .unknown),
            incidents: .empty,
            auditSummary: AuditSummary(
                generatedAt: Date(),
                totalSessionsToday: 0, completedSessions: 0,
                abandonedSessions: 0, orphanedSessions: 0,
                lastSessionCompletedAt: nil, averageSessionDurationMinutes: nil
            ),
            kpis: .empty
        )
    }
}
