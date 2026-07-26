// CaptureCollection.swift
// HaispaceBooths — Core/Domain/Session
//
// Domain model untuk koleksi Capture dalam sebuah Session.
//
// GLOSSARY definition:
//   Capture — proses memperoleh media (foto, video, burst).
//   CaptureCollection — seluruh media yang diperoleh dalam satu Session.
//
// ATURAN:
//   - Hanya Session yang boleh memanggil append/remove
//   - Selected = subset dari captured, dibatasi oleh CapturePolicy
//   - Final = hasil komposit yang siap dikirim ke tamu
//
// Ref: haispace-platform/docs/GLOSSARY.md — Capture
// Ref: haispace-platform/docs/PLATFORM_PRINCIPLES.md — Principle 11 (Immutable Session)

import Foundation

// MARK: - CaptureRecord

/// Satu unit Capture yang berhasil diterima dan di-persist.
/// Immutable setelah dibuat.
public struct CaptureRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: String              // CaptureID (UUID)
    public let sessionId: String
    public let sortOrder: Int          // Urutan pengambilan (0-based)
    public let capturedAt: Date
    public let filePath: String        // Path relatif dari Documents/ — persisted
    public var thumbnailPath: String?  // Thumbnail sementara — bisa nil
    public let isFullQuality: Bool
    public let captureType: CaptureType

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        sortOrder: Int,
        capturedAt: Date = Date(),
        filePath: String,
        thumbnailPath: String? = nil,
        isFullQuality: Bool = false,
        captureType: CaptureType = .photo
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sortOrder = sortOrder
        self.capturedAt = capturedAt
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.isFullQuality = isFullQuality
        self.captureType = captureType
    }

    /// Kembalikan CaptureRecord dengan isFullQuality = true
    public func markingAsFullQuality(filePath: String) -> CaptureRecord {
        CaptureRecord(
            id: self.id,
            sessionId: self.sessionId,
            sortOrder: self.sortOrder,
            capturedAt: self.capturedAt,
            filePath: filePath,
            thumbnailPath: self.thumbnailPath,
            isFullQuality: true,
            captureType: self.captureType
        )
    }
}

// MARK: - CaptureType

public enum CaptureType: String, Codable, Sendable {
    case photo    // Still image
    case video    // Video recording
    case burst    // Serial photos
}

// MARK: - FinalCapture

/// Hasil komposit — setelah frame/filter diterapkan.
/// Ini yang dikirim ke tamu via Delivery.
public struct FinalCapture: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let sessionId: String
    public let sourceCaptures: [String]  // CaptureRecord IDs yang digunakan
    public let filePath: String          // Hasil komposit di Documents/
    public let createdAt: Date
    public let frameId: String?
    public let filterId: String?
}

// MARK: - CapturePolicy

/// Policy pengambilan foto dari Package.
/// Memisahkan business rules dari Workflow logic.
public struct CapturePolicy: Codable, Sendable {
    public let maxCount: Int         // Maksimal foto yang bisa diambil
    public let minSelectionCount: Int // Minimum foto yang harus dipilih
    public let maxSelectionCount: Int // Maksimum foto yang bisa dipilih
    public let countdownSeconds: Int  // Hitungan mundur per foto
    public let intervalSeconds: Int   // Jeda antar foto otomatis
    public let durationSeconds: Int   // Total durasi sesi (timer)
    public let allowRetake: Bool      // Boleh mengulang foto?

    public init(
        maxCount: Int,
        minSelectionCount: Int,
        maxSelectionCount: Int,
        countdownSeconds: Int = 3,
        intervalSeconds: Int = 8,
        durationSeconds: Int = 300,
        allowRetake: Bool = true
    ) {
        self.maxCount = maxCount
        self.minSelectionCount = minSelectionCount
        self.maxSelectionCount = maxSelectionCount
        self.countdownSeconds = countdownSeconds
        self.intervalSeconds = intervalSeconds
        self.durationSeconds = durationSeconds
        self.allowRetake = allowRetake
    }

    // MARK: - Derived from BoothPackage (bridge)
    public static func from(package: BoothPackage) -> CapturePolicy {
        CapturePolicy(
            maxCount: package.maxPhotoCount,
            minSelectionCount: package.minPhotoCount,
            maxSelectionCount: package.minPhotoCount, // sama dengan min untuk sekarang
            countdownSeconds: 3,
            intervalSeconds: package.intervalSeconds,
            durationSeconds: package.durationSeconds,
            allowRetake: true
        )
    }
}

// MARK: - CaptureCollection

/// Koleksi semua Capture dalam satu Session.
///
/// PRINSIP: CaptureCollection hanya menjaga data.
/// Keputusan (apakah boleh pilih, apakah boleh retake) ada di HaispaceSession.
/// Collection tidak memiliki business logic.
public struct CaptureCollection: Codable, Sendable {

    // MARK: State
    private(set) var records: [CaptureRecord] = []
    private(set) var selectedIds: Set<String> = []
    private(set) var finalCaptures: [FinalCapture] = []
    private(set) var selectedFrameId: String? = nil
    private(set) var selectedFilterId: String? = nil

    public init() {}

    // MARK: - Queries (pure, no side effects)

    public var capturedCount: Int { records.count }
    public var selectedCount: Int { selectedIds.count }

    public var selectedRecords: [CaptureRecord] {
        records
            .filter { selectedIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public var hasPendingTransfers: Bool {
        records.contains { !$0.isFullQuality }
    }

    public func record(id: String) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    public func isSelected(_ id: String) -> Bool {
        selectedIds.contains(id)
    }

    // MARK: - Mutations (internal — only HaispaceSession calls these)

    mutating func append(_ record: CaptureRecord) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record // retake replaces
        } else {
            records.append(record)
            records.sort { $0.sortOrder < $1.sortOrder }
        }
    }

    mutating func upgradeToFullQuality(id: String, filePath: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx] = records[idx].markingAsFullQuality(filePath: filePath)
    }

    /// Dipanggil oleh Session setelah memvalidasi business rules.
    mutating func addToSelection(_ id: String) {
        selectedIds.insert(id)
    }

    /// Dipanggil oleh Session setelah memvalidasi business rules.
    mutating func removeFromSelection(_ id: String) {
        selectedIds.remove(id)
    }

    mutating func setFrame(_ frameId: String?) {
        selectedFrameId = frameId
    }

    mutating func setFilter(_ filterId: String?) {
        selectedFilterId = filterId
    }

    mutating func addFinalCapture(_ final: FinalCapture) {
        finalCaptures.append(final)
    }

    mutating func reset() {
        records.removeAll()
        selectedIds.removeAll()
        finalCaptures.removeAll()
        selectedFrameId = nil
        selectedFilterId = nil
    }
}
