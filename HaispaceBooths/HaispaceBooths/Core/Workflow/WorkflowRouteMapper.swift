// WorkflowRouteMapper.swift
// HaispaceBooths — Core/Workflow
//
// Adapter tunggal antara WorkflowStage (domain Orchestrator)
// dan KioskRoute (domain UI/AppState).
//
// ATURAN:
// - Satu-satunya tempat yang boleh tahu tentang KEDUA domain
// - Tidak boleh ada mapping stage→route di tempat lain
// - Setiap WorkflowStage WAJIB punya KioskRoute — exhaustive switch
//
// Ref: docs/design/ADR-001_workflow_ownership.md — Bridge Pattern
// Ref: docs/design/44_architecture_invariants.md — Invariant 18

import Foundation

// MARK: - WorkflowRouteMapper

/// Adapter stateless yang mengkonversi WorkflowStage → KioskRoute.
/// Sengaja dibuat struct (tidak ada state) — pure mapping function.
struct WorkflowRouteMapper {

    /// Konversi WorkflowStage ke KioskRoute yang sesuai untuk SwiftUI routing.
    ///
    /// Switch ini HARUS exhaustive — compiler akan error jika ada WorkflowStage
    /// baru yang belum di-mapping. Ini adalah Architecture Regression Guard.
    static func route(for stage: WorkflowStage) -> AppState.KioskRoute {
        switch stage {
        case .landing:
            return .landing

        case .guestRegistration:
            return .guestRegistration

        case .packageSelection:
            return .packageSelection

        case .templateSelection:
            // Template selection adalah bagian dari setup sebelum capture
            // Mapped ke frameSelection karena tidak ada route terpisah
            return .frameSelection

        case .capturing:
            return .activeSession

        case .editingPreview:
            // Filter selection adalah bagian dari editing preview
            return .photoSelection

        case .exporting:
            // Saat exporting, tampilkan processing screen
            return .processing

        case .paymentRequested, .paymentConfirmed:
            return .payment

        case .deliveryDispatch:
            return .delivery

        case .sessionCompleted:
            // Setelah selesai, kembali ke landing untuk tamu berikutnya
            return .landing

        case .recoveryMode:
            // Recovery mode — tampilkan landing sebagai safe default
            // Operator akan menggunakan Mission Control untuk intervensi
            return .landing
        }
    }

    /// Validasi bahwa semua KioskRoute memiliki setidaknya satu WorkflowStage.
    /// Digunakan oleh Architecture Regression Tests.
    static func allRoutes() -> Set<AppState.KioskRoute> {
        let allStages = WorkflowStage.allCases
        return Set(allStages.map { route(for: $0) })
    }
}

// MARK: - WorkflowStage + CaseIterable
// Diperlukan agar allRoutes() bisa iterasi semua stage
// dan Architecture Regression Test bisa memverifikasi exhaustiveness

extension WorkflowStage: CaseIterable {
    public static var allCases: [WorkflowStage] {
        [
            .landing,
            .guestRegistration,
            .packageSelection,
            .templateSelection,
            .capturing,
            .editingPreview,
            .exporting,
            .paymentRequested,
            .paymentConfirmed,
            .deliveryDispatch,
            .sessionCompleted,
            .recoveryMode
        ]
    }
}
