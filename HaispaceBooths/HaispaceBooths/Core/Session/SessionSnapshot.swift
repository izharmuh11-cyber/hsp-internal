// SessionSnapshot.swift
// HaispaceBooths — Core/Session
//
// Snapshot atomik dari seluruh state sesi yang aktif.
//
// BERBEDA DARI SessionAuditTrail:
//   AuditTrail    → append-only event log (TIDAK pernah diedit)
//   SessionSnapshot → current state snapshot (di-OVERWRITE setiap perubahan)
//
// LIFECYCLE:
//   1. Dibuat saat WorkflowOrchestrator.handleIntent(.startGuestRegistration)
//   2. Di-update (overwrite) setiap kali state sesi berubah
//   3. Dihapus saat sessionCompleted atau sessionAbandoned
//   4. Jika masih ada saat launch → orphaned session → SessionRestoreEngine membaca ini
//
// FORMAT: JSON tunggal per sesi (bukan JSONL)
//   Documents/session_snapshots/<sessionId>.json
//
// ATOMICITY:
//   Tulis ke file tmp dulu, lalu rename (atomic move) ke path final.
//   Ini mencegah partial-write yang terbaca saat crash recovery.
//
// Ref: docs/design/ADR-003_platform_reliability.md — Pilar: Atomic Recovery
// Ref: docs/design/44_architecture_invariants.md — Invariant 20

import Foundation

// MARK: - SessionSnapshot

public struct SessionSnapshot: Codable, Sendable {

    // MARK: - Identity
    public let sessionId: String
    public let savedAt: Date
    public let schemaVersion: Int   // Untuk migrasi di masa depan

    // MARK: - Workflow State
    public let currentStage: WorkflowStage

    // MARK: - Package
    public let selectedPackageId: String?
    public let selectedPackageName: String?
    public let selectedPackagePrice: Double?

    // MARK: - Payment
    public let paymentId: String?
    public let paymentStatus: SnapshotPaymentStatus?
    public let amountPaid: Double?

    // MARK: - Capture
    public let capturedPhotoIds: [String]
    public let totalPhotosRequired: Int

    // MARK: - Editing
    public let selectedFrameId: String?
    public let selectedFilterId: String?
    public let editingCompleted: Bool

    // MARK: - Delivery
    public let deliveryState: SnapshotDeliveryState
    public let recipientPhone: String?   // Disimpan (tamu tidak perlu input ulang saat recovery)

    // MARK: - Hardware (untuk recovery context)
    public let printerStateAtSave: String?   // PrinterState.rawValue
    public let sessionStartedAt: Date

    // MARK: - Schema Version
    public static let currentSchemaVersion = 1

    public init(
        sessionId: String,
        currentStage: WorkflowStage,
        selectedPackageId: String? = nil,
        selectedPackageName: String? = nil,
        selectedPackagePrice: Double? = nil,
        paymentId: String? = nil,
        paymentStatus: SnapshotPaymentStatus? = nil,
        amountPaid: Double? = nil,
        capturedPhotoIds: [String] = [],
        totalPhotosRequired: Int = 0,
        selectedFrameId: String? = nil,
        selectedFilterId: String? = nil,
        editingCompleted: Bool = false,
        deliveryState: SnapshotDeliveryState = .pending,
        recipientPhone: String? = nil,
        printerStateAtSave: String? = nil,
        sessionStartedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.savedAt = Date()
        self.schemaVersion = Self.currentSchemaVersion
        self.currentStage = currentStage
        self.selectedPackageId = selectedPackageId
        self.selectedPackageName = selectedPackageName
        self.selectedPackagePrice = selectedPackagePrice
        self.paymentId = paymentId
        self.paymentStatus = paymentStatus
        self.amountPaid = amountPaid
        self.capturedPhotoIds = capturedPhotoIds
        self.totalPhotosRequired = totalPhotosRequired
        self.selectedFrameId = selectedFrameId
        self.selectedFilterId = selectedFilterId
        self.editingCompleted = editingCompleted
        self.deliveryState = deliveryState
        self.recipientPhone = recipientPhone
        self.printerStateAtSave = printerStateAtSave
        self.sessionStartedAt = sessionStartedAt
    }

    // MARK: - Computed Recovery Helpers

    /// Apakah sesi ini perlu di-resume ke delivery? (Invariant 20)
    public var requiresDeliveryResume: Bool {
        paymentStatus == .confirmed && deliveryState != .completed
    }

    /// Apakah semua foto sudah diambil?
    public var isCaptureComplete: Bool {
        capturedPhotoIds.count >= totalPhotosRequired && totalPhotosRequired > 0
    }
}

// MARK: - Supporting Enums

public enum SnapshotPaymentStatus: String, Codable, Sendable {
    case pending    = "pending"
    case confirmed  = "confirmed"
    case failed     = "failed"
}

public enum SnapshotDeliveryState: String, Codable, Sendable {
    case pending    = "pending"     // Belum dimulai
    case inProgress = "in_progress" // Sedang kirim
    case completed  = "completed"   // Selesai
    case failed     = "failed"      // Gagal (ada di DeliveryQueue)
}

// MARK: - SessionSnapshotStore

/// Simpan dan load SessionSnapshot ke/dari disk secara atomik.
public enum SessionSnapshotStore {

    private static let snapshotDir: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("session_snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Write (Atomic)

    /// Simpan snapshot secara atomik (tmp → rename).
    /// Thread-safe: tulis ke file tmp dulu, lalu atomic rename ke path final.
    public static func save(_ snapshot: SessionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }

        let finalURL = snapshotURL(for: snapshot.sessionId)
        let tmpURL = finalURL.appendingPathExtension("tmp")

        do {
            try data.write(to: tmpURL, options: .atomic)
            // Atomic rename — jika crash di sini, tmp file tidak dibaca
            _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tmpURL)
        } catch {
            // Fallback: direct write
            try? data.write(to: finalURL, options: .atomic)
        }
    }

    // MARK: - Read

    public static func load(sessionId: String) -> SessionSnapshot? {
        let url = snapshotURL(for: sessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    // MARK: - Delete (setelah session complete)

    public static func delete(sessionId: String) {
        let url = snapshotURL(for: sessionId)
        try? FileManager.default.removeItem(at: url)
        // Juga hapus tmp jika ada
        try? FileManager.default.removeItem(at: url.appendingPathExtension("tmp"))
    }

    // MARK: - Find All Orphans

    /// Semua snapshot yang masih ada = sesi yang belum selesai (orphaned jika app direstart)
    public static func allOrphanedSnapshots() -> [SessionSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: snapshotDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionSnapshot? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SessionSnapshot.self, from: data)
            }
            .sorted { $0.sessionStartedAt < $1.sessionStartedAt }
    }

    // MARK: - Private

    private static func snapshotURL(for sessionId: String) -> URL {
        snapshotDir.appendingPathComponent("\(sessionId).json")
    }
}
