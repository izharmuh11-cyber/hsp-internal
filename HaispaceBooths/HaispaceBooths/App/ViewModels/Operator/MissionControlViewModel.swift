// MissionControlViewModel.swift
// HaispaceBooths — App/ViewModels/Operator
//
// Thin ViewModel untuk Mission Control.
// Kontrak yang sangat terbatas — sesuai peringatan principal engineer
// tentang "God Object".
//
// YANG BOLEH ADA DI SINI:
//   - refresh() → panggil HealthAggregator + DiagnosisEngine + IncidentEngine
//   - acknowledgeIncident(id:) → update state incident
//   - retryIncident(id:) → kirim OperatorAction ke AppState
//   - dismissDiagnosis(id:) → tandai diagnosis sebagai dismissed
//
// YANG TIDAK BOLEH ADA DI SINI (ADR-003):
//   - Menghitung severity
//   - Menentukan apakah sesuatu adalah insiden
//   - Memformat pesan diagnosis
//   - Mengakses capability health langsung
//
// Ref: docs/design/ADR-003_mission_control_boundary.md
// Ref: docs/design/ADR-004_operational_data_ownership.md

import Foundation
import SwiftUI

@MainActor
@Observable
public final class MissionControlViewModel {

    // MARK: - Public State (dibaca View via @Environment)

    /// Snapshot terkini — satu-satunya sumber data untuk Mission Control View
    private(set) var snapshot: MissionControlSnapshot = .loading()

    /// True saat refresh sedang berlangsung
    private(set) var isRefreshing: Bool = false

    /// Error terakhir (jika refresh gagal)
    private(set) var lastRefreshError: String?

    /// Incidents yang sudah di-dismiss manual oleh operator (dalam session ini)
    private var dismissedDiagnosisIds: Set<String> = []

    // MARK: - Dependencies

    private let healthAggregator: HealthAggregator
    private weak var appState: AppState?

    // MARK: - Init

    public init(healthAggregator: HealthAggregator, appState: AppState) {
        self.healthAggregator = healthAggregator
        self.appState = appState
    }

    // MARK: - Public API (4 method, tidak lebih)

    /// Kumpulkan semua data dan update snapshot.
    /// Dipanggil saat Mission Control dibuka atau saat auto-refresh timer berdetak.
    public func refresh() async {
        isRefreshing = true
        lastRefreshError = nil
        defer { isRefreshing = false }

        // 1. Kumpulkan health data (HealthAggregator mengumpulkan, bukan menghitung)
        let healthSnapshot = await healthAggregator.collect()

        // 2. Analisis → DiagnosisReport (DiagnosisEngine menghitung, ViewModel tidak)
        let diagnosisReport = DiagnosisEngine.analyze(snapshot: healthSnapshot)

        // 3. Evaluasi → IncidentReport (IncidentEngine menghitung, ViewModel tidak)
        let incidentReport = IncidentEngine.evaluate(
            diagnosisReport: diagnosisReport,
            snapshot: healthSnapshot
        )

        // 4. Ringkasan audit
        let auditSummary = AuditSummary.generate()

        // 5. Rakit menjadi satu snapshot
        let newSnapshot = MissionControlSnapshot(
            generatedAt: Date(),
            platformHealth: healthSnapshot,
            diagnosis: filterDismissed(diagnosisReport),
            incidents: incidentReport,
            auditSummary: auditSummary,
            kpis: .empty     // TODO: KPICollector.collect() — Sprint berikutnya
        )

        self.snapshot = newSnapshot

        HaispaceLogger.debug(
            "MissionControlViewModel refreshed — incidents: \(incidentReport.activeIncidents.count) — diagnoses: \(diagnosisReport.entries.count)",
            category: "missioncontrol"
        )
    }

    /// Operator mengakui sebuah insiden.
    /// State transition: .detected → .acknowledged
    public func acknowledgeIncident(id: String) {
        // Update state di snapshot secara lokal
        // (dalam production: bisa juga persist ke IncidentStore)
        var updatedIncidents = snapshot.incidents.incidents
        if let index = updatedIncidents.firstIndex(where: { $0.id == id }) {
            guard updatedIncidents[index].state == .detected else { return }
            updatedIncidents[index].state = .acknowledged
            updatedIncidents[index].acknowledgedAt = Date()
        }

        rebuildSnapshotWithIncidents(updatedIncidents)

        HaispaceLogger.info("Incident acknowledged: \(id)", category: "missioncontrol")
    }

    /// Operator mengeksekusi aksi retry untuk sebuah insiden.
    /// State transition: .acknowledged/.detected → .mitigating
    public func retryIncident(id: String) async {
        var updatedIncidents = snapshot.incidents.incidents
        if let index = updatedIncidents.firstIndex(where: { $0.id == id }) {
            let incident = updatedIncidents[index]
            guard let action = incident.suggestedAction else { return }

            // Kirim aksi ke AppState — konsisten ADR-001 (View tidak langsung ke Orchestrator)
            await executeOperatorAction(action)

            updatedIncidents[index].state = .mitigating
        }

        rebuildSnapshotWithIncidents(updatedIncidents)
    }

    /// Operator dismiss satu diagnosis (tidak relevan atau sudah ditangani manual).
    public func dismissDiagnosis(id: String) {
        dismissedDiagnosisIds.insert(id)
        // Rebuild snapshot dengan diagnosis yang sudah di-filter
        let filtered = filterDismissed(snapshot.diagnosis)
        snapshot = MissionControlSnapshot(
            generatedAt: snapshot.generatedAt,
            platformHealth: snapshot.platformHealth,
            diagnosis: filtered,
            incidents: snapshot.incidents,
            auditSummary: snapshot.auditSummary,
            kpis: snapshot.kpis
        )
        HaispaceLogger.info("Diagnosis dismissed: \(id)", category: "missioncontrol")
    }

    // MARK: - Private Helpers

    private func filterDismissed(_ report: DiagnosisReport) -> DiagnosisReport {
        guard !dismissedDiagnosisIds.isEmpty else { return report }
        let filtered = report.entries.filter { !dismissedDiagnosisIds.contains($0.id) }
        return DiagnosisReport(entries: filtered, snapshotTimestamp: report.snapshotTimestamp)
    }

    private func rebuildSnapshotWithIncidents(_ incidents: [Incident]) {
        snapshot = MissionControlSnapshot(
            generatedAt: snapshot.generatedAt,
            platformHealth: snapshot.platformHealth,
            diagnosis: snapshot.diagnosis,
            incidents: IncidentReport(incidents: incidents),
            auditSummary: snapshot.auditSummary,
            kpis: snapshot.kpis
        )
    }

    private func executeOperatorAction(_ action: OperatorAction) async {
        guard let appState = appState else { return }
        // Mapping OperatorAction → WorkflowIntent sesuai ADR-001
        switch action {
        case .retryDelivery(let sessionId):
            try? await appState.send(.retryDelivery(sessionId: sessionId))
        case .reconnectCamera:
            try? await appState.send(.reconnectCamera)
        case .reconnectP2P:
            try? await appState.send(.reconnectP2P)
        case .forceResetToLanding:
            try? await appState.send(.cancelSessionByOperator)
        case .exportDiagnosticLog:
            // TODO: implement log export
            HaispaceLogger.info("Export diagnostic log requested", category: "missioncontrol")
        case .refreshLicense:
            try? await appState.send(.refreshLicense)
        case .clearUploadQueue, .acknowledgeAndDismiss:
            break
        }
    }
}
