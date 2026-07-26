// CapabilityRegistry.swift
// HaispaceBooths — Core/Runtime
//
// Kontrak Capability Registry untuk Platform Haispace.
//
// PRINSIP (Ref: GPT Architecture Review):
//   WorkflowOrchestrator tidak boleh tahu "bagaimana" capability dibangun.
//   Orchestrator cukup meminta capability yang dibutuhkan lewat Registry.
//   Capability baru (AI Enhancement, Cloud Rendering, Printer 2, dll.)
//   ditambahkan ke Registry — tidak mengubah Workflow.
//
// HIRARKI:
//   RuntimeContainer
//     └── CapabilityRegistry
//           ├── CameraCapability   (register via provider)
//           ├── PrinterCapability  (dapat banyak instance)
//           ├── PaymentCapability  (QRIS, Cash, Midtrans via policy)
//           ├── EditingCapability  (Local, Cloud, future AI)
//           ├── DeliveryCapability (AirDrop, Bonjour, WhatsApp)
//           └── P2PCapability      (Bonjour, future WebRTC)
//
// NOTE: Ini adalah kontrak saja.
//       Implementasi CapabilityRegistry akan dibangun pada Milestone 3
//       (sebelum Cloud Contract). Saat ini WorkflowOrchestrator masih
//       menerima capabilities via initializer injection langsung.
//
// Ref: GPT Architecture Review — Capability Registry sebagai milestone
//      setelah RuntimeContainer dan sebelum Cloud Contract.

import Foundation

// MARK: - CapabilityKind

/// Jenis capability yang dapat diregistrasikan ke CapabilityRegistry.
public enum CapabilityKind: String, CaseIterable, Sendable {
    case camera     // Image/video capture
    case printer    // Physical print (dapat lebih dari satu)
    case payment    // Payment processing (QRIS, Cash, Gateway)
    case editing    // Frame/filter/composite rendering
    case delivery   // File delivery to guest (AirDrop, Bonjour, Cloud)
    case p2p        // Peer-to-peer device communication (Bonjour, future WebRTC)
    case ai         // AI enhancement (future — cloud rendering, auto-framing)
}

// MARK: - CapabilityMetadata

/// Metadata deskriptif untuk sebuah capability.
/// Digunakan Registry untuk logging, health check, dan policy resolution.
public struct CapabilityMetadata: Sendable {
    public let kind: CapabilityKind
    public let providerId: String    // Contoh: "haicamera.local", "epson.tm20", "qris.emvco"
    public let version: String       // Versi implementasi
    public let isOnline: Bool        // Apakah capability ini bisa berjalan offline?
    public let priority: Int         // Jika ada lebih dari satu capability yang sama kind-nya

    public init(
        kind: CapabilityKind,
        providerId: String,
        version: String = "1.0",
        isOnline: Bool = false,
        priority: Int = 0
    ) {
        self.kind = kind
        self.providerId = providerId
        self.version = version
        self.isOnline = isOnline
        self.priority = priority
    }
}

// MARK: - CapabilityRegistryProtocol

/// Kontrak Capability Registry.
/// WorkflowOrchestrator menggunakan protokol ini — tidak tahu implementasinya.
///
/// NOTE: Ini adalah kontrak masa depan.
///       Saat ini belum diimplementasikan — WorkflowOrchestrator masih
///       menerima capabilities secara langsung melalui initializer injection.
public protocol CapabilityRegistryProtocol: Sendable {

    /// Kembalikan Camera Capability yang aktif.
    /// Throws jika tidak ada camera yang terdaftar.
    func camera() throws -> CameraCapabilityProtocol

    /// Kembalikan Payment Capability berdasarkan metode.
    func payment(for method: CapabilityPaymentMethod) throws -> PaymentCapabilityProtocol

    /// Kembalikan Editing Capability yang aktif.
    func editing() throws -> EditingCapabilityProtocol

    /// Kembalikan semua Delivery Capabilities yang tersedia.
    func deliveries() -> [DeliveryCapabilityProtocol]

    /// Kembalikan P2P Capability yang aktif.
    func p2p() throws -> P2PCapabilityProtocol

    /// Kembalikan metadata semua capability yang terdaftar.
    func allMetadata() -> [CapabilityMetadata]

    /// Kembalikan apakah capability jenis tertentu tersedia.
    func isAvailable(_ kind: CapabilityKind) -> Bool
}

// MARK: - CapabilityPaymentMethod

public enum CapabilityPaymentMethod: Sendable {
    case qris
    case cash
    case gateway(String)  // "midtrans", "xendit", dll.
}

// MARK: - CapabilityRegistryError

public enum CapabilityRegistryError: Error, Sendable {
    case capabilityNotFound(CapabilityKind)
    case ambiguousCapability(CapabilityKind, count: Int)
    case capabilityUnavailable(CapabilityKind, reason: String)
}
