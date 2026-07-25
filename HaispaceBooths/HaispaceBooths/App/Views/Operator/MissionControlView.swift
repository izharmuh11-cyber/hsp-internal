// MissionControlView.swift
// HaispaceBooths — App/Views/Operator
//
// Layar utama operator. Menampilkan status platform secara real-time.
//
// ATURAN (ADR-003): View ini HANYA merender MissionControlSnapshot.
// Tidak ada kalkulasi, tidak ada logic bisnis di sini.
// Semua angka dan teks sudah disiapkan oleh layer di bawahnya.
//
// Ref: docs/design/ADR-003_mission_control_boundary.md

import SwiftUI

// MARK: - MissionControlView

public struct MissionControlView: View {

    @Environment(MissionControlViewModel.self) private var vm
    @State private var selectedTab: Tab = .incidents

    enum Tab: String, CaseIterable {
        case incidents = "Insiden"
        case diagnosis = "Diagnosis"
        case health    = "Kesehatan"
        case kpis      = "KPI"
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlatformStatusHeaderView(snapshot: vm.snapshot)
                tabSelector
                tabContent
            }
            .navigationTitle("Mission Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.refresh() }
            .refreshable { await vm.refresh() }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                            if tab == .incidents {
                                let count = vm.snapshot.activeIncidentCount
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(vm.snapshot.incidents.criticalCount > 0 ? Color.red : Color.orange)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                let w = geo.size.width / CGFloat(Tab.allCases.count)
                let idx = CGFloat(Tab.allCases.firstIndex(of: selectedTab) ?? 0)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: w * 0.5, height: 3)
                    .offset(x: w * idx + w * 0.25)
                    .animation(.spring(response: 0.3), value: selectedTab)
            }
            .frame(height: 3)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .incidents:
            IncidentListView(
                report: vm.snapshot.incidents,
                onAcknowledge: { vm.acknowledgeIncident(id: $0) },
                onRetry: { id in Task { await vm.retryIncident(id: id) } }
            )
        case .diagnosis:
            DiagnosisListView(
                report: vm.snapshot.diagnosis,
                onDismiss: { vm.dismissDiagnosis(id: $0) }
            )
        case .health:
            HealthOverviewView(snapshot: vm.snapshot.platformHealth)
        case .kpis:
            KPIDashboardView(kpis: vm.snapshot.kpis, auditSummary: vm.snapshot.auditSummary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(vm.snapshot.overallStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.isRefreshing {
                ProgressView().scaleEffect(0.8)
            } else {
                Button { Task { await vm.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private var statusColor: Color {
        switch vm.snapshot.overallStatusColor {
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        }
    }
}

// MARK: - PlatformStatusHeaderView

struct PlatformStatusHeaderView: View {
    let snapshot: MissionControlSnapshot

    var body: some View {
        HStack(spacing: 10) {
            if snapshot.incidents.criticalCount > 0 {
                StatusChip(label: "\(snapshot.incidents.criticalCount) Kritis", color: .red, icon: "exclamationmark.triangle.fill")
            }
            if snapshot.incidents.highCount > 0 {
                StatusChip(label: "\(snapshot.incidents.highCount) Tinggi", color: .orange, icon: "exclamationmark.circle.fill")
            }
            if !snapshot.incidents.hasActiveIncidents {
                StatusChip(label: "Semua Normal", color: .green, icon: "checkmark.circle.fill")
            }
            Spacer()
            Text(snapshot.generatedAt, style: .time)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - IncidentListView

struct IncidentListView: View {
    let report: IncidentReport
    let onAcknowledge: (String) -> Void
    let onRetry: (String) -> Void

    var body: some View {
        if report.activeIncidents.isEmpty {
            ContentUnavailableView(
                "Tidak Ada Insiden Aktif",
                systemImage: "checkmark.shield.fill",
                description: Text("Semua sistem berjalan normal")
            )
        } else {
            List {
                Section("Aktif (\(report.activeIncidents.count))") {
                    ForEach(report.activeIncidents) { incident in
                        IncidentRowView(
                            incident: incident,
                            onAcknowledge: { onAcknowledge(incident.id) },
                            onRetry: { onRetry(incident.id) }
                        )
                    }
                }

                let resolved = report.incidents.filter { !$0.state.isActive }
                if !resolved.isEmpty {
                    Section("Selesai") {
                        ForEach(resolved) { incident in
                            IncidentRowView(incident: incident, onAcknowledge: nil, onRetry: nil)
                                .opacity(0.5)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - IncidentRowView

struct IncidentRowView: View {
    let incident: Incident
    let onAcknowledge: (() -> Void)?
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(incident.severity.displayLabel)
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(severityColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())

                Spacer()

                Text(incident.state.displayLabel)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(incident.detectedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Text(incident.title)
                .font(.subheadline).fontWeight(.medium)

            Text(incident.summary)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)

            if incident.state.isActive {
                HStack(spacing: 8) {
                    if let onAcknowledge, incident.state == .detected {
                        Button("Akui", action: onAcknowledge)
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                    if let onRetry, incident.suggestedAction != nil {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.borderedProminent).controlSize(.mini)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var severityColor: Color {
        switch incident.severity {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .yellow
        case .low:      return .blue
        case .info:     return .gray
        }
    }
}

// MARK: - DiagnosisListView

struct DiagnosisListView: View {
    let report: DiagnosisReport
    let onDismiss: (String) -> Void

    var body: some View {
        if report.entries.isEmpty {
            ContentUnavailableView("Tidak Ada Masalah", systemImage: "checkmark.circle.fill")
        } else {
            List {
                let criticals = report.entries.filter { $0.severity == .critical }
                let warnings  = report.entries.filter { $0.severity == .warning }
                let infos     = report.entries.filter { $0.severity == .info }

                if !criticals.isEmpty {
                    Section("Kritis") {
                        ForEach(criticals) { e in DiagnosisRowView(entry: e) { onDismiss(e.id) } }
                    }
                }
                if !warnings.isEmpty {
                    Section("Peringatan") {
                        ForEach(warnings) { e in DiagnosisRowView(entry: e) { onDismiss(e.id) } }
                    }
                }
                if !infos.isEmpty {
                    Section("Info") {
                        ForEach(infos) { e in DiagnosisRowView(entry: e) { onDismiss(e.id) } }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

struct DiagnosisRowView: View {
    let entry: DiagnosisEntry
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title).font(.subheadline).fontWeight(.medium)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            Text(entry.description).font(.caption).foregroundStyle(.secondary)
            Label(entry.recommendedAction, systemImage: "arrow.right.circle")
                .font(.caption).foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HealthOverviewView

struct HealthOverviewView: View {
    let snapshot: PlatformHealthSnapshot

    var body: some View {
        List {
            Section(header: Text("Perangkat")) {
                VStack(spacing: 0) {
                    HealthRow(label: "Kamera",      status: snapshot.cameraHealth.status.displayLabel,  isHealthy: snapshot.cameraHealth.status == .ready || snapshot.cameraHealth.status == .healthy,   icon: "camera.fill")
                    HealthRow(label: "Koneksi P2P", status: snapshot.p2pHealth.status.displayLabel,     isHealthy: snapshot.p2pHealth.status == .connected,  icon: "wifi")
                }
            }
            Section(header: Text("Layanan")) {
                VStack(spacing: 0) {
                    HealthRow(label: "Pembayaran",      status: snapshot.paymentHealth.status.displayLabel,  isHealthy: snapshot.paymentHealth.status == .healthy || snapshot.paymentHealth.status == .ready,  icon: "creditcard.fill")
                    HealthRow(label: "Pengiriman Foto", status: snapshot.deliveryHealth.status.displayLabel, isHealthy: snapshot.deliveryHealth.status == .healthy, icon: "photo.fill")
                }
            }
            Section(header: Text("Sesi Aktif")) {
                VStack(spacing: 0) {
                    if let record = snapshot.activeSessionRecord {
                        LabeledContent("Session ID", value: String(record.sessionId.prefix(8)) + "...")
                        LabeledContent("Tahap",      value: record.lastStage.rawValue)
                        LabeledContent("Event",      value: "\(record.events.count)")
                    } else {
                        Text("Tidak ada sesi aktif").foregroundStyle(.secondary).font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct HealthRow: View {
    let label: String; let status: String; let isHealthy: Bool; let icon: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(isHealthy ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - KPIDashboardView

struct KPIDashboardView: View {
    let kpis: OperationalKPIs
    let auditSummary: AuditSummary

    var body: some View {
        List {
            Section("Workflow Hari Ini") {
                LabeledContent("Sesi Selesai",    value: "\(auditSummary.completedSessions)")
                LabeledContent("Sesi Terhenti",   value: "\(auditSummary.orphanedSessions)")
                LabeledContent("Completion Rate", value: String(format: "%.0f%%", auditSummary.completionRate * 100))
            }
            Section("Operasional") {
                LabeledContent("Insiden Aktif",    value: "\(kpis.activeIncidentCount)")
                LabeledContent("Insiden Hari Ini", value: "\(kpis.incidentsToday)")
                LabeledContent("Rata-rata Tangani",
                    value: kpis.meanTimeToResolveSeconds.map { String(format: "%.0f menit", $0 / 60) } ?? "—")
            }
            Section("Uptime") {
                KPIProgressRow(label: "Kamera", value: kpis.cameraUptimePercent)
                KPIProgressRow(label: "P2P",    value: kpis.p2pUptimePercent)
                KPIProgressRow(label: "Printer",value: kpis.printerUptimePercent)
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct KPIProgressRow: View {
    let label: String; let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .font(.caption)
                    .foregroundStyle(value >= 95 ? .green : value >= 80 ? .orange : .red)
            }
            ProgressView(value: value / 100)
                .tint(value >= 95 ? .green : value >= 80 ? .orange : .red)
        }
    }
}

// MARK: - StatusChip

struct StatusChip: View {
    let label: String; let color: Color; let icon: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
