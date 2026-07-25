// SessionAuditTrail.swift
// HaispaceBooths — Core/Audit
//
// Persistent append-only event log per-sesi.
//
// FORMAT — JSONL (JSON Lines): satu baris per entry
// ─────────────────────────────────────────────────
// Baris 1:   AuditTrailHeader  → metadata sesi (sessionId, startedAt)
// Baris 2+:  AuditEvent        → setiap event ditulis sebagai baris baru
// Baris N:   AuditTrailFooter  → finalStatus (saat close) — SELALU di akhir
//
// PRINSIP APPEND-ONLY (Principal Engineer Review):
// - Tidak ada rewrite(), replace(), atau overwrite()
// - Setiap perubahan adalah event baru yang di-append
// - File hanya tumbuh, tidak pernah berkurang selama sesi aktif
// - Operasi write adalah FileHandle.seekToEndOfFile() + write()
// - Crash-safe: partial write di baris terakhir dibuang saat read
//
// LIFECYCLE:
// - Dibuat saat WorkflowOrchestrator.handleIntent(.startGuestRegistration)
// - Di-close saat .finishSession atau .cancelSessionByOperator
// - File tanpa Footer = orphaned session (indikasi crash)
//
// Ref: docs/design/ADR-002_operational_resilience.md — Pilar 1: Auditability
// Ref: docs/design/44_architecture_invariants.md — Invariant 19

import Foundation

// MARK: - AuditEventType

public enum AuditEventType: String, Codable, Sendable {
    // Stage transitions
    case sessionStarted
    case infoSubmitted
    case packageSelected
    case templateSelected
    case photoCaptured
    case previewAccepted
    case exportCompleted
    case paymentRequested
    case paymentConfirmed       // POIN KRITIS — dipakai Invariant 20
    case deliveryStarted
    case deliveryRetry
    case deliveryCompleted
    case sessionCompleted

    // Failure events
    case cameraFailure
    case paymentTimeout
    case paymentFailed
    case deliveryFailure
    case uploadFailure

    // Recovery events
    case crashRecoveryDetected
    case sessionResumed
    case sessionAbandoned

    // Operator events
    case operatorCancel
    case operatorRetry
    case operatorReset
}

// MARK: - JSONL Line Types

/// Baris pertama setiap file JSONL — metadata sesi
public struct AuditTrailHeader: Codable, Sendable {
    public let lineType: String     // selalu "header"
    public let sessionId: String
    public let startedAt: Date
    public let schemaVersion: Int   // untuk forward compatibility

    public init(sessionId: String) {
        self.lineType = "header"
        self.sessionId = sessionId
        self.startedAt = Date()
        self.schemaVersion = 1
    }
}

/// Setiap event dalam audit trail — satu baris per event
public struct AuditEvent: Codable, Sendable {
    public let lineType: String     // selalu "event"
    public let id: String
    public let sequence: Int        // monotonic, tidak pernah sama dalam satu sesi
    public let timestamp: Date
    public let stage: WorkflowStage
    public let eventType: AuditEventType
    public let correlationId: String?   // untuk menelusuri event lintas domain
    public let actor: String            // komponen yang memicu event: "workflow", "operator", "system"
    public let metadata: [String: String]

    public init(
        sequence: Int,
        stage: WorkflowStage,
        eventType: AuditEventType,
        correlationId: String? = nil,
        actor: String = "workflow",
        metadata: [String: String] = [:]
    ) {
        self.lineType = "event"
        self.id = UUID().uuidString
        self.sequence = sequence
        self.timestamp = Date()
        self.stage = stage
        self.eventType = eventType
        self.correlationId = correlationId
        self.actor = actor
        self.metadata = metadata
    }
}

/// Baris terakhir — keberadaannya berarti SATU hal:
/// **Workflow selesai dengan sukses.** (bukan hanya "file selesai ditulis")
///
/// Recovery rule:
///   footer ada   → sesi selesai normal, tidak perlu aksi
///   footer tidak ada → unexpected termination, cek apakah ada transaksi finansial
public struct AuditTrailFooter: Codable, Sendable {
    public let lineType: String     // selalu "footer"
    public let sequence: Int        // sequence terakhir + 1
    public let closedAt: Date
    public let finalStatus: FinalStatus
    public let totalEvents: Int     // jumlah events untuk verifikasi integritas

    public enum FinalStatus: String, Codable, Sendable {
        case completed              // workflow selesai normal sampai customer menerima foto
        case cancelledByOperator    // dibatalkan operator sebelum ada transaksi finansial
        case abandoned              // sistem menentukan sesi ini aman untuk diabaikan
    }

    public init(sequence: Int, status: FinalStatus, totalEvents: Int) {
        self.lineType = "footer"
        self.sequence = sequence
        self.closedAt = Date()
        self.finalStatus = status
        self.totalEvents = totalEvents
    }
}

// MARK: - AuditTrailRecord (Reconstructed View)

/// Hasil rekonstruksi dari membaca file JSONL
public struct AuditTrailRecord: Sendable {
    public let sessionId: String
    public let startedAt: Date
    public let schemaVersion: Int
    public let events: [AuditEvent]         // read-only, sudah diurutkan by sequence
    public let footer: AuditTrailFooter?    // nil = unexpected termination

    /// Footer tidak ada = unexpected termination (crash, force-quit, listrik mati)
    /// Footer ada = workflow selesai sukses
    public var isOrphaned: Bool { footer == nil }

    /// Stage terakhir yang tercatat
    public var lastStage: WorkflowStage {
        events.last?.stage ?? .landing
    }

    /// Apakah sesi ini pernah mencapai paymentConfirmed?
    public var hasFinancialTransaction: Bool {
        events.contains { $0.eventType == .paymentConfirmed }
    }

    /// Output reference untuk delivery recovery
    public var deliveryOutputReference: String? {
        events.first { $0.eventType == .paymentConfirmed }?.metadata["outputRef"]
    }

    /// Jumlah retry delivery yang tercatat
    public var deliveryRetryCount: Int {
        events.filter { $0.eventType == .deliveryRetry || $0.eventType == .deliveryFailure }.count
    }

    /// Sequence terakhir dalam trail ini
    public var lastSequence: Int {
        events.last?.sequence ?? 0
    }
}

// MARK: - SessionAuditTrail

/// Append-only writer dan reader untuk SessionAuditTrail per-sesi.
/// Semua write SYNCHRONOUS via FileHandle — tidak ada rewrite, tidak ada overwrite.
public enum SessionAuditTrail {

    // MARK: - Storage

    private static let auditDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("haispace/audit", isDirectory: true)
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // Tidak pakai .prettyPrinted — JSONL butuh satu baris per entry
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Sequence Counter (per-session, monotonic)
    // Disimpan di memori — reset untuk setiap file baru.
    // Thread-safety: seluruh SessionAuditTrail dipanggil dari actor context Orchestrator.
    private static var sequenceCounters: [String: Int] = [:]

    private static func nextSequence(for sessionId: String) -> Int {
        let next = (sequenceCounters[sessionId] ?? 0) + 1
        sequenceCounters[sessionId] = next
        return next
    }

    // MARK: - Write — Append-Only (Invariant 19)

    /// Buat file JSONL baru dengan header.
    public static func create(sessionId: String) {
        ensureAuditDirectoryExists()
        sequenceCounters[sessionId] = 0  // reset counter untuk sesi baru
        let header = AuditTrailHeader(sessionId: sessionId)
        appendLine(encoded: encode(header), to: sessionId)
        HaispaceLogger.info("AuditTrail CREATED: \(sessionId)", category: "audit")
    }

    /// Append satu AuditEvent sebagai baris baru. Sequence otomatis diincrement.
    public static func append(
        sessionId: String,
        stage: WorkflowStage,
        eventType: AuditEventType,
        correlationId: String? = nil,
        actor: String = "workflow",
        metadata: [String: String] = [:]
    ) {
        let seq = nextSequence(for: sessionId)
        let event = AuditEvent(
            sequence: seq,
            stage: stage,
            eventType: eventType,
            correlationId: correlationId,
            actor: actor,
            metadata: metadata
        )
        appendLine(encoded: encode(event), to: sessionId)
    }

    /// Tutup trail. Footer berarti: **workflow selesai dengan sukses.**
    /// Tidak ada footer = unexpected termination — heuristic sederhana untuk recovery.
    public static func close(sessionId: String, status: AuditTrailFooter.FinalStatus) {
        let totalEvents = sequenceCounters[sessionId] ?? 0
        let footerSeq = totalEvents + 1
        let footer = AuditTrailFooter(sequence: footerSeq, status: status, totalEvents: totalEvents)
        appendLine(encoded: encode(footer), to: sessionId)
        sequenceCounters.removeValue(forKey: sessionId)  // cleanup
        HaispaceLogger.info("AuditTrail CLOSED: \(sessionId) — \(status.rawValue) — \(totalEvents) events", category: "audit")
    }

    // MARK: - Read

    /// Rekonstruksi AuditTrailRecord dari file JSONL.
    /// Baris yang tidak bisa di-parse (misal partial write saat crash) dilewati.
    public static func read(sessionId: String) -> AuditTrailRecord? {
        let url = fileURL(for: sessionId)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var header: AuditTrailHeader?
        var events: [AuditEvent] = []
        var footer: AuditTrailFooter?

        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }

            if let typeHint = try? decoder.decode(LineTypeHint.self, from: data) {
                switch typeHint.lineType {
                case "header":
                    header = try? decoder.decode(AuditTrailHeader.self, from: data)
                case "event":
                    if let event = try? decoder.decode(AuditEvent.self, from: data) {
                        events.append(event)
                    }
                    // Baris yang gagal di-decode (partial write saat crash) dilewati
                case "footer":
                    footer = try? decoder.decode(AuditTrailFooter.self, from: data)
                default:
                    break
                }
            }
        }

        guard let h = header else { return nil }

        // Urutkan by sequence — bukan by timestamp — sesuai rekomendasi principal engineer
        let sortedEvents = events.sorted { $0.sequence < $1.sequence }

        return AuditTrailRecord(
            sessionId: h.sessionId,
            startedAt: h.startedAt,
            schemaVersion: h.schemaVersion,
            events: sortedEvents,
            footer: footer
        )
    }

    /// Temukan semua orphaned sessions — dipakai oleh OrphanedSessionDetector.
    public static func findOrphanedSessions() -> [AuditTrailRecord] {
        ensureAuditDirectoryExists()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: auditDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> AuditTrailRecord? in
                let sessionId = url.deletingPathExtension().lastPathComponent
                guard let record = read(sessionId: sessionId),
                      record.isOrphaned else { return nil }
                return record
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Hapus trail yang sudah selesai dan lebih dari N hari.
    public static func purgeOldCompleted(olderThan days: Int = 30) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: auditDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var purgedCount = 0

        for url in files where url.pathExtension == "jsonl" {
            let sessionId = url.deletingPathExtension().lastPathComponent
            guard let record = read(sessionId: sessionId),
                  !record.isOrphaned,
                  record.startedAt < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
            purgedCount += 1
        }

        if purgedCount > 0 {
            HaispaceLogger.info("AuditTrail PURGED \(purgedCount) sessions older than \(days) days", category: "audit")
        }
    }

    // MARK: - Private — Core Append Primitive

    private static func fileURL(for sessionId: String) -> URL {
        auditDirectory.appendingPathComponent("\(sessionId).jsonl")
    }

    private static func ensureAuditDirectoryExists() {
        try? FileManager.default.createDirectory(at: auditDirectory, withIntermediateDirectories: true)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder.encode(value)
    }

    /// Core primitive: append satu baris ke ujung file via FileHandle.
    /// Tidak membaca file, tidak menulis ulang — hanya seekToEnd() + write().
    private static func appendLine(encoded data: Data?, to sessionId: String) {
        guard let data = data else {
            HaispaceLogger.warning("AuditTrail ENCODE FAILED: \(sessionId)", category: "audit")
            return
        }

        let url = fileURL(for: sessionId)

        // Buat file jika belum ada
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))  // newline separator
        } catch {
            HaispaceLogger.warning(
                "AuditTrail APPEND FAILED: \(sessionId) — \(error.localizedDescription)",
                category: "audit"
            )
        }
    }
}

// MARK: - LineTypeHint (Internal)

/// Minimal struct untuk deteksi lineType tanpa full decode
private struct LineTypeHint: Decodable {
    let lineType: String
}
