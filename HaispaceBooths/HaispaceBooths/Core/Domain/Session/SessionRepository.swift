// SessionRepository.swift
// HaispaceBooths — Core/Domain/Session
//
// Kontrak akses persistence untuk Session Aggregate.
//
// PRINSIP (Ref: GPT Architecture Decision — Phase B, Definition of Done):
//   - Repository hanya memiliki 4 operasi: load, save, delete, exists
//   - Repository tidak tahu tentang WorkflowOrchestrator atau UI
//   - Repository menerima dan mengembalikan SessionSnapshot (bukan HaispaceSession langsung)
//   - HaispaceSession dibuat ulang dari SessionSnapshot oleh SessionFactory
//
// UNIT OF WORK PATTERN:
//   save() dipanggil oleh WorkflowOrchestrator (atau Unit of Work) setelah flush events.
//   Repository tidak pernah memanggil Domain Event Publisher.
//   Urutan yang benar:
//     1. Session.mutate()
//     2. session.flushEvents() → kumpulkan events
//     3. repository.save(snapshot) → persist ke disk
//     4. publisher.publish(events) → broadcast ke subscribers
//
// Ref: haispace-platform/adr/ADR-009-session-repository.md (segera dibuat)
// Ref: haispace-platform/architecture/ARP-004 — Repository Layer design

import Foundation

// MARK: - SessionRepositoryProtocol

/// Kontrak persistence untuk Session Aggregate.
/// Hanya 4 operasi — tidak lebih.
public protocol SessionRepositoryProtocol: Sendable {

    /// Simpan snapshot Session ke disk.
    /// Dipanggil setelah setiap mutasi penting pada HaispaceSession.
    func save(_ snapshot: SessionSnapshot) async throws

    /// Muat SessionSnapshot dari disk berdasarkan sessionId.
    /// Mengembalikan nil jika session tidak ditemukan.
    func load(sessionId: String) async -> SessionSnapshot?

    /// Hapus Session dari disk (setelah archive selesai).
    /// Hanya dipanggil oleh RetentionManager setelah SessionArchived event.
    func delete(sessionId: String) async throws

    /// Cek apakah session dengan ID tersebut ada di disk.
    func exists(sessionId: String) async -> Bool
}

// MARK: - NoOpSessionRepository (Testing & Fallback)

public actor NoOpSessionRepository: SessionRepositoryProtocol {
    public init() {}
    public func save(_ snapshot: SessionSnapshot) async throws {}
    public func load(sessionId: String) async -> SessionSnapshot? { nil }
    public func delete(sessionId: String) async throws {}
    public func exists(sessionId: String) async -> Bool { false }
}

// MARK: - SessionRepositoryError

public enum SessionRepositoryError: Error, Sendable {
    case encodingFailed(String)
    case decodingFailed(String, sessionId: String)
    case writeFailed(String)
    case deleteFailed(String)
    case schemaMigrationRequired(from: Int, to: Int, sessionId: String)
}
