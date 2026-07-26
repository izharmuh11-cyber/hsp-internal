// CapabilityManager.swift
// HaispaceBooths — Core/Runtime
//
// Kontrak untuk Capability Manager — Registry + Resolver + Policy.
//
// MENGAPA BUKAN SEKADAR REGISTRY:
//   Registry hanya register/resolve.
//   CapabilityManager juga memiliki:
//   - Resolver: memilih capability yang paling sesuai jika ada lebih dari satu
//   - Policy: mengambil keputusan saat capability degraded atau unavailable
//
// CONTOH POLICY:
//   resolve(.printer)
//     → Printer A unhealthy (ink low)
//     → Policy: cek CapabilityPolicy
//     → return Printer B (backup) atau throw CapabilityUnavailable
//
//   resolve(.payment, for: .qris)
//     → QRIS capability offline (no network)
//     → Policy: fall back to .cash? Throw? Notify operator?
//     → Policy menentukan, bukan Workflow
//
// WORKFLOW tidak pernah tahu printer mana, QRIS instance mana.
// Workflow hanya memanggil: manager.resolve(.printer)
//
// NOTE: Ini adalah kontrak (Milestone 3).
//       Implementasi konkret: DefaultCapabilityManager.
//
// Ref: GPT Architecture Review — CapabilityManager sebelum Cloud Contract

import Foundation

// MARK: - CapabilityHealth

/// Status kesehatan sebuah capability instance.
public enum CapabilityHealth: Sendable {
    case healthy
    case degraded(reason: String)  // Masih bisa dipakai, tapi ada masalah
    case unavailable(reason: String) // Tidak bisa dipakai sama sekali
}

// MARK: - CapabilityPolicy

/// Policy untuk menentukan behavior saat capability degraded atau unavailable.
public enum CapabilityPolicy: Sendable {
    case failFast         // Langsung throw — tidak ada fallback
    case fallback         // Coba capability lain (jika ada)
    case degradedAllowed  // Pakai yang degraded jika tidak ada yang healthy
    case operatorPrompt   // Minta intervensi operator (future — Mission Control)
}

// MARK: - ResolvedCapability

/// Hasil resolve capability — wrapper untuk komunikasi status ke Workflow.
public struct ResolvedCapability<T: Sendable>: Sendable {
    public let capability: T
    public let health: CapabilityHealth
    public let resolvedFrom: String  // providerId yang dipilih

    public var isHealthy: Bool {
        if case .healthy = health { return true }
        return false
    }
}

// MARK: - CapabilityManagerProtocol

/// Kontrak Capability Manager.
/// Workflow menggunakan ini — tidak tahu detail implementasi.
public protocol CapabilityManagerProtocol: Sendable {

    // MARK: Resolution

    /// Resolve Camera Capability yang paling sesuai.
    func resolveCamera(policy: CapabilityPolicy) throws -> ResolvedCapability<CameraCapabilityProtocol>

    /// Resolve Payment Capability berdasarkan metode.
    func resolvePayment(method: CapabilityPaymentMethod, policy: CapabilityPolicy) throws -> ResolvedCapability<PaymentCapabilityProtocol>

    /// Resolve Editing Capability.
    func resolveEditing(policy: CapabilityPolicy) throws -> ResolvedCapability<EditingCapabilityProtocol>

    /// Resolve semua available Delivery Capabilities (bisa lebih dari satu).
    func resolveDeliveries() -> [ResolvedCapability<DeliveryCapabilityProtocol>]

    /// Resolve P2P Capability.
    func resolveP2P(policy: CapabilityPolicy) throws -> ResolvedCapability<P2PCapabilityProtocol>

    // MARK: Health Check

    /// Cek health semua capabilities yang terdaftar.
    func healthCheck() async -> [CapabilityKind: CapabilityHealth]

    /// Apakah capability jenis tertentu tersedia dengan health minimal tertentu?
    func isAvailable(_ kind: CapabilityKind, minimumHealth: CapabilityHealth) -> Bool
}

// MARK: - CapabilityManagerError

public enum CapabilityManagerError: Error, Sendable {
    case notRegistered(CapabilityKind)
    case allUnavailable(CapabilityKind)
    case policyViolation(CapabilityKind, reason: String)
    case ambiguous(CapabilityKind, count: Int)
}

// MARK: - SimpleCapabilityManager (Milestone 3 Placeholder)

/// Implementasi minimal CapabilityManagerProtocol.
/// Saat ini hanya meneruskan langsung dari CapabilityModule.
/// Milestone 3 akan menggantinya dengan DefaultCapabilityManager yang punya
/// health check, policy resolution, dan fallback logic.
public struct SimpleCapabilityManager: CapabilityManagerProtocol, @unchecked Sendable {

    private let module: CapabilityModule

    public init(module: CapabilityModule) {
        self.module = module
    }

    public func resolveCamera(policy: CapabilityPolicy) throws -> ResolvedCapability<CameraCapabilityProtocol> {
        ResolvedCapability(capability: module.camera, health: .healthy, resolvedFrom: "default")
    }

    public func resolvePayment(method: CapabilityPaymentMethod, policy: CapabilityPolicy) throws -> ResolvedCapability<PaymentCapabilityProtocol> {
        ResolvedCapability(capability: module.payment, health: .healthy, resolvedFrom: "default")
    }

    public func resolveEditing(policy: CapabilityPolicy) throws -> ResolvedCapability<EditingCapabilityProtocol> {
        ResolvedCapability(capability: module.editing, health: .healthy, resolvedFrom: "default")
    }

    public func resolveDeliveries() -> [ResolvedCapability<DeliveryCapabilityProtocol>] {
        [ResolvedCapability(capability: module.delivery, health: .healthy, resolvedFrom: "default")]
    }

    public func resolveP2P(policy: CapabilityPolicy) throws -> ResolvedCapability<P2PCapabilityProtocol> {
        ResolvedCapability(capability: module.p2p, health: .healthy, resolvedFrom: "default")
    }

    public func healthCheck() async -> [CapabilityKind: CapabilityHealth] {
        // Milestone 3: real health checks untuk each capability
        [
            .camera: .healthy,
            .payment: .healthy,
            .editing: .healthy,
            .delivery: .healthy,
            .p2p: .healthy
        ]
    }

    public func isAvailable(_ kind: CapabilityKind, minimumHealth: CapabilityHealth) -> Bool {
        true // Simplified — Milestone 3 akan implementasikan secara nyata
    }
}
