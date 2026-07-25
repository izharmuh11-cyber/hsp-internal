// BoothHealth.swift
// HaispaceBooths — Core/Observability
//
// Mengimplementasikan "Booth Healthy Contract v1":
// Booth dianggap sehat jika dapat menyelesaikan sesi tamu yang sedang berjalan
// dan menerima tamu berikutnya secara otonom, menggunakan jalur utama atau
// fallback yang tersedia, tanpa intervensi operator.

import Foundation

public enum HealthState: String, Codable, Sendable, Comparable {
    case healthy
    case degraded
    case unhealthy
    case unknown
    case observeOnly

    public static func < (lhs: HealthState, rhs: HealthState) -> Bool {
        // Urutan prioritas keparahan (yang paling parah menang jika diagregasi)
        // unknown < observeOnly < healthy < degraded < unhealthy
        let order: [HealthState: Int] = [
            .unknown: 0,
            .observeOnly: 1,
            .healthy: 2,
            .degraded: 3,
            .unhealthy: 4
        ]
        return (order[lhs] ?? 0) < (order[rhs] ?? 0)
    }
}

public struct BoothHealth: Codable, Sendable {
    public let state: HealthState
    public let summary: String
    
    public init(state: HealthState, summary: String) {
        self.state = state
        self.summary = summary
    }
}
