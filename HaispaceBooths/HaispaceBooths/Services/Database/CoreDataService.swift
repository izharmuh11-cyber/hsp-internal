// CoreDataService.swift
// HaispaceBooths — Services/Database
//
// Layanan CoreData terisolasi menggunakan Actor untuk memastikan thread-safety.
// Menyimpan riwayat event, transaksi pembayaran (ledger), dan log sesi secara offline.
// Skema dibuat secara terprogram (In-Code NSManagedObjectModel) untuk menghindari konflik XML.
//
// Ref: docs/design/40_concurrency_strategy.md — CoreData Actor-Isolated Service

import Foundation
import CoreData
import OSLog

@globalActor
actor CoreDataActor {
    static let shared = CoreDataActor()
}

@CoreDataActor
final class CoreDataService {
    
    static let shared = CoreDataService()
    
    private let container: NSPersistentContainer
    
    // Background context yang terikat ke CoreDataActor
    private let context: NSManagedObjectContext
    
    private init() {
        // Buat model secara terprogram
        let model = CoreDataSchema.createModel()
        
        container = NSPersistentContainer(name: "HaispaceDataModel", managedObjectModel: model)
        
        // Simpan ke local SQLite
        guard let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not found")
        }
        let storeURL = docURL.appendingPathComponent("HaispaceOfflineLedger.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = true
        // Aktifkan WAL (Write-Ahead Logging) untuk performa concurrency
        description.setOption(true as NSNumber, forKey: NSPersistentStoreOSCompatibility)
        
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { desc, error in
            if let error = error {
                HaispaceLogger.error("Gagal load CoreData: \(error.localizedDescription)", category: "database")
            } else {
                HaispaceLogger.info("CoreData berhasil di-load: \(desc.url?.lastPathComponent ?? "")", category: "database")
            }
        }
        
        // Setup background context
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - API
    
    /// Menyimpan transaksi pembayaran baru ke Ledger
    func savePaymentTransaction(id: String, amount: Int, method: String, status: String, sessionId: String) async throws {
        let transaction = PaymentTransactionEntity(context: context)
        transaction.id = id
        transaction.amount = Int64(amount)
        transaction.method = method
        transaction.status = status
        transaction.sessionId = sessionId
        transaction.createdAt = Date()
        transaction.isSynced = false // Tandai belum di-sync ke cloud
        
        try saveContext()
        HaispaceLogger.info("Ledger disimpan: \(id) (\(method) - \(amount))", category: "database")
    }
    
    /// Menyimpan sesi baru
    func saveSessionLog(sessionId: String, eventId: String, totalPhotos: Int, durationSeconds: Int) async throws {
        let session = SessionLogEntity(context: context)
        session.id = sessionId
        session.eventId = eventId
        session.totalPhotos = Int16(totalPhotos)
        session.durationSeconds = Int16(durationSeconds)
        session.createdAt = Date()
        session.isSynced = false
        
        try saveContext()
    }
    
    /// Mengambil transaksi yang belum di-sync
    func fetchUnsyncedTransactions() async throws -> [PaymentTransactionEntity] {
        let request = NSFetchRequest<PaymentTransactionEntity>(entityName: "PaymentTransaction")
        request.predicate = NSPredicate(format: "isSynced == NO")
        return try context.fetch(request)
    }
    
    /// Menandai transaksi sudah tersync
    func markTransactionSynced(id: String) async throws {
        let request = NSFetchRequest<PaymentTransactionEntity>(entityName: "PaymentTransaction")
        request.predicate = NSPredicate(format: "id == %@", id)
        
        if let transaction = try context.fetch(request).first {
            transaction.isSynced = true
            transaction.syncedAt = Date()
            try saveContext()
        }
    }
    
    // MARK: - Private Helper
    
    private func saveContext() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
