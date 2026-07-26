// LocalSessionRepository.swift
// HaispaceBooths — Core/Infrastructure/Repository
//
// Implementasi pertama SessionRepositoryProtocol.
// Menyimpan SessionSnapshot sebagai JSON ke Documents directory.
//
// DESAIN:
//   - Satu file JSON per session: Documents/sessions/{sessionId}.snapshot.json
//   - JSON (bukan binary) untuk human-readable dan debuggable
//   - Atomic write via write-to-temp-then-rename untuk crash safety
//   - Schema migration via snapshotSchemaVersion field
//
// THREAD SAFETY:
//   Menggunakan actor internal untuk serialisasi akses ke FileManager.
//
// Ref: haispace-platform/adr/ADR-009-session-repository.md
// Ref: haispace-platform/architecture/ARP-004 — CaptureRepository design

import Foundation

// MARK: - LocalSessionRepository

/// Implementasi SessionRepositoryProtocol yang menyimpan ke Documents/sessions/.
/// Ini adalah implementasi default untuk runtime iPad.
/// Di masa depan dapat diganti dengan CloudSessionRepository tanpa mengubah Domain.
public actor LocalSessionRepository: SessionRepositoryProtocol {

    // MARK: - Configuration

    private static let currentSchemaVersion = 1
    private static let directoryName = "sessions"
    private static let fileExtension = "snapshot.json"

    // MARK: - Dependencies

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseDirectory: URL

    // MARK: - Init

    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SessionRepositoryError.writeFailed("Cannot locate Documents directory")
        }

        self.baseDirectory = documentsURL.appendingPathComponent(Self.directoryName)

        // Pastikan direktori ada
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        HaispaceLogger.info(
            "LocalSessionRepository initialized at: \(baseDirectory.path)",
            category: "repository"
        )
    }

    // MARK: - SessionRepositoryProtocol

    public func save(_ snapshot: SessionSnapshot) async throws {
        let fileURL = snapshotURL(for: snapshot.sessionId)
        let tempURL = fileURL.appendingPathExtension("tmp")

        do {
            let data = try encoder.encode(snapshot)

            // Atomic write: tulis ke .tmp dulu, lalu rename
            try data.write(to: tempURL, options: .atomic)
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)

            HaispaceLogger.info(
                "Session snapshot saved: \(snapshot.sessionId) (schema v\(snapshot.snapshotSchemaVersion))",
                category: "repository"
            )
        } catch let error as SessionRepositoryError {
            throw error
        } catch {
            // Cleanup temp file jika gagal
            try? fileManager.removeItem(at: tempURL)
            throw SessionRepositoryError.writeFailed(error.localizedDescription)
        }
    }

    public func load(sessionId: String) async -> SessionSnapshot? {
        let fileURL = snapshotURL(for: sessionId)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var snapshot = try decoder.decode(SessionSnapshot.self, from: data)

            // Schema migration jika diperlukan
            if snapshot.snapshotSchemaVersion < Self.currentSchemaVersion {
                HaispaceLogger.warning(
                    "Session \(sessionId) schema v\(snapshot.snapshotSchemaVersion) < current v\(Self.currentSchemaVersion) — migrating",
                    category: "repository"
                )
                snapshot = snapshot.migrated()
            }

            HaispaceLogger.info("Session snapshot loaded: \(sessionId)", category: "repository")
            return snapshot

        } catch {
            HaispaceLogger.error(error)
            // Snapshot corrupt — return nil (Recovery Engine akan handle sebagai orphan)
            return nil
        }
    }

    public func delete(sessionId: String) async throws {
        let fileURL = snapshotURL(for: sessionId)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Tidak ada yang dihapus — ini bukan error
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            HaispaceLogger.info("Session snapshot deleted: \(sessionId)", category: "repository")
        } catch {
            throw SessionRepositoryError.deleteFailed(error.localizedDescription)
        }
    }

    public func exists(sessionId: String) async -> Bool {
        fileManager.fileExists(atPath: snapshotURL(for: sessionId).path)
    }

    // MARK: - Internal Utilities

    /// URL untuk snapshot file. Format: Documents/sessions/{sessionId}.snapshot.json
    private func snapshotURL(for sessionId: String) -> URL {
        baseDirectory.appendingPathComponent("\(sessionId).\(Self.fileExtension)")
    }
}

// MARK: - LocalSessionRepository + Recovery Support

extension LocalSessionRepository {

    /// Ambil semua snapshot yang ada di disk.
    /// Digunakan oleh Recovery Engine saat launch untuk mendeteksi in-progress sessions.
    public func fetchAll() async -> [SessionSnapshot] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let snapshots = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionSnapshot? in
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? decoder.decode(SessionSnapshot.self, from: data)
                else { return nil }
                return snapshot
            }

        return snapshots
    }

    /// Ambil semua snapshot yang membutuhkan recovery (belum completed/aborted).
    public func fetchRequiringRecovery() async -> [SessionSnapshot] {
        let all = await fetchAll()
        return all.filter { !$0.isSafeToArchive }
    }
}
