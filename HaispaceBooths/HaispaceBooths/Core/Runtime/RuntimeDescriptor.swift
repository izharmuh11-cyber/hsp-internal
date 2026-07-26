// RuntimeDescriptor.swift
// HaispaceBooths — Core/Runtime
//
// Self-description object untuk seluruh Platform Runtime Haispace.
//
// PRINSIP (Ref: GPT Architecture Review — Platform Runtime v1.0):
//   Runtime harus mampu menjelaskan dirinya sendiri.
//   Mission Control, Cloud Sync, dan Debug Tools cukup bertanya:
//   "Describe yourself." — tanpa perlu membaca puluhan file.
//
// PENGGUNAAN:
//   let descriptor = RuntimeDescriptor.current
//   print(descriptor.architectureVersion)   // "1.0.0"
//   print(descriptor.isCompatible(with: "cloud-contract-v1")) // true
//
// Ref: haispace-platform/constitution/PLATFORM_RUNTIME_V1.md

import Foundation

// MARK: - RuntimeDescriptor

/// Deskripsi lengkap dari Platform Runtime Haispace yang sedang berjalan.
/// Dibuat sekali saat RuntimeContainer diinisialisasi.
/// Dikirimkan ke Mission Control dan Cloud saat handshake.
public struct RuntimeDescriptor: Codable, Sendable {

    // MARK: - Identity

    /// Versi arsitektur (semver) — dibekukan pada v1.0.0.
    /// Hanya berubah setelah ADR baru disetujui oleh Architecture Review.
    public let architectureVersion: String

    /// Versi runtime build (bisa berubah setiap rilis).
    public let runtimeVersion: String

    /// Build number dari sistem CI.
    public let buildNumber: String

    /// Tanggal freeze arsitektur ini.
    public let frozenAt: String

    // MARK: - Compatibility Matrix

    /// Versi minimum manifest yang didukung runtime ini.
    public let minimumManifestVersion: Int

    /// Versi maximum manifest yang didukung runtime ini.
    public let maximumManifestVersion: Int

    /// Versi SessionSnapshot schema yang didukung.
    public let supportedSnapshotVersion: Int

    /// Versi DomainEvent envelope schema yang didukung.
    public let domainEventVersion: String

    /// Cloud Contract version yang kompatibel dengan runtime ini.
    public let compatibleCloudContracts: [String]

    // MARK: - Capability Declarations

    /// Daftar CapabilityKind yang disupport oleh runtime ini.
    public let declaredCapabilities: [String]

    // MARK: - Runtime Guarantees

    /// Daftar runtime guarantees yang disepakati dalam Platform Constitution v1.0.
    public let guarantees: [RuntimeGuarantee]

    // MARK: - Self Description

    /// Apakah runtime ini kompatibel dengan cloud contract tertentu?
    public func isCompatible(with cloudContractVersion: String) -> Bool {
        compatibleCloudContracts.contains(cloudContractVersion)
    }

    /// Apakah manifest version tertentu didukung?
    public func supportsManifest(version: Int) -> Bool {
        version >= minimumManifestVersion && version <= maximumManifestVersion
    }

    public func describe() -> String {
        """
        === Haispace Platform Runtime ===
        Architecture : v\(architectureVersion) (Frozen \(frozenAt))
        Runtime      : v\(runtimeVersion) [\(buildNumber)]
        Snapshot     : schema v\(supportedSnapshotVersion)
        Events       : envelope v\(domainEventVersion)
        Manifest     : v\(minimumManifestVersion)–v\(maximumManifestVersion)
        Capabilities : \(declaredCapabilities.joined(separator: ", "))
        Guarantees   : \(guarantees.count) runtime guarantees declared
        Cloud Compat : \(compatibleCloudContracts.isEmpty ? "none declared" : compatibleCloudContracts.joined(separator: ", "))
        =================================
        """
    }
}

// MARK: - RuntimeGuarantee

/// Satu Runtime Guarantee yang dijanjikan oleh Platform Runtime.
/// Setiap guarantee harus memiliki minimal satu Architecture Acceptance Test.
public struct RuntimeGuarantee: Codable, Sendable {
    /// Kode guarantee (contoh: "RG-001")
    public let id: String

    /// Deskripsi singkat guarantee
    public let description: String

    /// Status implementasi guarantee
    public let status: GuaranteeStatus

    /// Referensi ke Acceptance Test yang membuktikan guarantee ini
    public let acceptanceTestId: String?
}

public enum GuaranteeStatus: String, Codable, Sendable {
    case guaranteed   // Implemented + tested
    case partial      // Sebagian diimplementasikan
    case planned      // Belum diimplementasikan (Phase C/D/E)
}

// MARK: - RuntimeDescriptor.current (v1.0.0)

public extension RuntimeDescriptor {

    /// Descriptor Platform Runtime v1.0.0 yang dibekukan.
    static let current = RuntimeDescriptor(
        architectureVersion: "1.0.0",
        runtimeVersion: "0.1.0",
        buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev",
        frozenAt: "2026-07-26",
        minimumManifestVersion: 1,
        maximumManifestVersion: 1,
        supportedSnapshotVersion: 1,
        domainEventVersion: "1.0",
        compatibleCloudContracts: [], // Cloud Contract v1 akan ditambahkan saat Cloud milestone
        declaredCapabilities: ["camera", "printer", "payment", "editing", "delivery", "p2p"],
        guarantees: RuntimeDescriptor.v1Guarantees
    )

    static let v1Guarantees: [RuntimeGuarantee] = [
        RuntimeGuarantee(
            id: "RG-001",
            description: "Session tidak hilang saat crash — SessionSnapshot di-persist secara atomic ke disk",
            status: .guaranteed,
            acceptanceTestId: "AAT-002"
        ),
        RuntimeGuarantee(
            id: "RG-002",
            description: "Payment terkonfirmasi tidak pernah hilang meski delivery gagal",
            status: .guaranteed,
            acceptanceTestId: "AAT-001"
        ),
        RuntimeGuarantee(
            id: "RG-003",
            description: "Manifest baru tidak mengubah asset session yang sedang berjalan",
            status: .partial,
            acceptanceTestId: "AAT-003"
        ),
        RuntimeGuarantee(
            id: "RG-004",
            description: "Capability failure di-handle oleh Policy tanpa mematikan Workflow",
            status: .partial,
            acceptanceTestId: "AAT-004"
        ),
        RuntimeGuarantee(
            id: "RG-005",
            description: "WorkflowOrchestrator tidak mengetahui detail implementasi dependency",
            status: .guaranteed,
            acceptanceTestId: nil // Structural — enforced by Swift protocol boundaries
        ),
        RuntimeGuarantee(
            id: "RG-006",
            description: "AppState tidak mengandung business logic — hanya meneruskan intent dan memantulkan state",
            status: .planned,
            acceptanceTestId: nil // Enforced saat AppState Integration milestone
        ),
        RuntimeGuarantee(
            id: "RG-007",
            description: "DomainEvent subscriber Critical selalu dieksekusi sebelum subscriber Low",
            status: .guaranteed,
            acceptanceTestId: nil // Structural — enforced by SubscriberPriority ordering
        ),
        RuntimeGuarantee(
            id: "RG-008",
            description: "Semua timestamp berasal dari RuntimeClock — tidak ada Date() langsung di Domain",
            status: .partial,
            acceptanceTestId: nil // Enforcement Phase: bertahap seiring refactor
        )
    ]
}
