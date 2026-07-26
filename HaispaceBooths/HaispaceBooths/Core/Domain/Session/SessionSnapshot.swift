// SessionSnapshot.swift
// HaispaceBooths — Core/Domain/Session
//
// Kontrak penyimpanan yang stabil untuk HaispaceSession.
//
// PRINSIP (Ref: GPT Architecture Decision — Q10):
//   SessionSnapshot adalah kontrak penyimpanan, bukan cerminan class internal.
//   Perubahan implementasi enum di Swift tidak boleh merusak data recovery.
//   Semua field menggunakan tipe primitif yang stabil (String, Int, Date, Bool).
//
// ATURAN:
//   - Tidak ada tipe Swift-spesifik di sini (bukan enum langsung, bukan struct internal)
//   - Semua state dikodekan sebagai primitif + workflowStageId (String)
//   - Versi snapshot memungkinkan forward migration
//
// Ref: haispace-platform/architecture/ARP-004 — Q10 answer

import Foundation

// MARK: - SessionSnapshot

/// Value Object yang stabil untuk persistence Session ke disk.
/// Dibuat via HaispaceSession.snapshot() — hanya Session yang boleh membuat ini.
public struct SessionSnapshot: Codable, Sendable {

    // MARK: Schema
    /// Versi schema snapshot — berbeda dari Runtime Version dan Manifest Version.
    /// Diincrement setiap kali struktur SessionSnapshot berubah secara breaking.
    /// Digunakan oleh SessionRepository untuk memutuskan apakah perlu migration.
    public let snapshotSchemaVersion: Int  // Saat ini: 1

    // MARK: Identity
    public let sessionId: String
    public let boothId: String
    public let eventId: String
    public let packageId: String
    public let packageVersion: Int
    public let manifestVersion: Int
    public let startedAt: Date
    public let guestName: String
    public let guestPhone: String?
    public let guestQueueNumber: Int

    // MARK: Workflow State (stable string, not Swift enum)
    public let workflowStageId: String       // WorkflowStage.rawValue
    public let lifecycleStatus: String       // SessionLifecycleStatus.codableRepresentation

    // MARK: Capture State
    public let captureIds: [String]          // Ordered list of CaptureRecord IDs
    public let captureFilePaths: [String: String]  // CaptureID → file path
    public let selectedCaptureIds: [String]
    public let selectedFrameId: String?
    public let selectedFilterId: String?

    // MARK: Payment State
    public let paymentCommitment: PaymentCommitment?

    // MARK: Delivery State
    public let deliveryState: SessionDeliveryState

    // MARK: Output
    public let outputReference: String?      // Path ke file komposit final

    // MARK: Timer
    public let remainingSeconds: Int

    // MARK: Completion
    public let completedAt: Date?
    public let abortedAt: Date?
    public let abortReason: String?

    // MARK: Snapshot metadata
    public let snapshotAt: Date              // Kapan snapshot ini dibuat

    // MARK: - Convenience Queries

    /// Apakah snapshot ini merepresentasikan session yang punya komitmen finansial?
    public var hasFinancialCommitment: Bool {
        paymentCommitment?.isWorkflowAllowed ?? false
    }

    /// Apakah session ini perlu di-restore ke delivery?
    public var requiresDeliveryRestore: Bool {
        hasFinancialCommitment && outputReference != nil && !deliveryState.isAllDelivered
    }

    /// Apakah session ini aman untuk dihapus?
    public var isSafeToArchive: Bool {
        lifecycleStatus == "completed" || lifecycleStatus == "aborted"
    }
}

// MARK: - SessionSnapshot + Migration

extension SessionSnapshot {

    /// Migrate snapshot dari versi lama ke versi terbaru.
    /// Dipanggil oleh SessionRepository saat load dari disk.
    public func migrated() -> SessionSnapshot {
        // Version 1 adalah versi pertama — tidak ada migration yang diperlukan.
        // Saat version 2 tersedia, logic migration ditambahkan di sini.
        return self
    }
}
