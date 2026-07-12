// BackgroundSyncClient.swift
// HaispaceBooths — Services/Cloud
//
// Layanan asinkron yang berjalan di latar belakang untuk mensinkronkan 
// data ledger lokal (CoreData) dan file gambar (R2) ke Cloud.
// Dirancang dengan sistem antrean dan retry otomatis jika internet putus.
//
// Ref: docs/design/40_concurrency_strategy.md

import Foundation
import Network

@MainActor
final class BackgroundSyncClient {
    
    static let shared = BackgroundSyncClient()
    
    private var syncTask: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    
    // Status konektivitas
    private(set) var isOnline: Bool = false
    private(set) var isSyncing: Bool = false
    
    private init() {
        startNetworkMonitoring()
    }
    
    // MARK: - Lifecycle
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                
                if !(self?.isOnline ?? false) {
                    HaispaceLogger.warning("Koneksi terputus. Sync ditunda.", category: "cloud")
                } else if !wasOnline {
                    HaispaceLogger.info("Koneksi pulih. Memulai antrean sync...", category: "cloud")
                    self?.triggerSync()
                }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    /// Dipanggil manual setiap akhir sesi untuk memicu sync secepat mungkin
    func triggerSync() {
        guard isOnline, !isSyncing else { return }
        
        syncTask = Task {
            isSyncing = true
            
            do {
                // 1. Sinkronisasi Transaksi Finansial (Ledger)
                try await syncTransactions()
                
                // 2. TODO: Sinkronisasi Gambar ke Cloudflare R2
                
            } catch {
                HaispaceLogger.error("Sync gagal: \(error)", category: "cloud")
            }
            
            isSyncing = false
        }
    }
    
    // MARK: - Handlers
    
    private func syncTransactions() async throws {
        // Karena CoreDataService adalah @globalActor (CoreDataActor), kita harus `await`
        let unsynced = try await CoreDataService.shared.fetchUnsyncedTransactions()
        
        guard !unsynced.isEmpty else { return }
        HaispaceLogger.info("Ditemukan \(unsynced.count) transaksi tertunda. Memulai upload...", category: "cloud")
        
        for transaction in unsynced {
            // Mock API Request
            let success = await uploadToPostgresMock(transaction)
            
            if success {
                try await CoreDataService.shared.markTransactionSynced(id: transaction.id)
            } else {
                HaispaceLogger.warning("Gagal upload transaksi \(transaction.id). Akan dicoba lagi nanti.", category: "cloud")
                break // Stop loop jika API gagal, coba lagi nanti
            }
        }
    }
    
    // MARK: - Mocks
    
    private func uploadToPostgresMock(_ transaction: PaymentTransactionEntity) async -> Bool {
        // Simulasi network delay
        try? await Task.sleep(for: .milliseconds(500))
        HaispaceLogger.info("Berhasil upload transaksi: \(transaction.id)", category: "cloud")
        return true
    }
}
