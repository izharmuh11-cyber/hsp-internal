// CoreDataSchema.swift
// HaispaceBooths — Services/Database
//
// Definisi skema CoreData yang dibangun secara terprogram (In-Code).
// Menghindari konflik merge di file XML `.xcdatamodeld`.

import Foundation
import CoreData

struct CoreDataSchema {
    static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // 1. Entity: PaymentTransaction
        let paymentEntity = NSEntityDescription()
        paymentEntity.name = "PaymentTransaction"
        paymentEntity.managedObjectClassName = NSStringFromClass(PaymentTransactionEntity.self)
        
        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .stringAttributeType
        idAttr.isOptional = false
        
        let amountAttr = NSAttributeDescription()
        amountAttr.name = "amount"
        amountAttr.attributeType = .integer64AttributeType
        amountAttr.isOptional = false
        
        let methodAttr = NSAttributeDescription()
        methodAttr.name = "method"
        methodAttr.attributeType = .stringAttributeType
        methodAttr.isOptional = false
        
        let statusAttr = NSAttributeDescription()
        statusAttr.name = "status"
        statusAttr.attributeType = .stringAttributeType
        statusAttr.isOptional = false
        
        let sessionAttr = NSAttributeDescription()
        sessionAttr.name = "sessionId"
        sessionAttr.attributeType = .stringAttributeType
        sessionAttr.isOptional = false
        
        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false
        
        let isSyncedAttr = NSAttributeDescription()
        isSyncedAttr.name = "isSynced"
        isSyncedAttr.attributeType = .booleanAttributeType
        isSyncedAttr.isOptional = false
        isSyncedAttr.defaultValue = false
        
        let syncedAtAttr = NSAttributeDescription()
        syncedAtAttr.name = "syncedAt"
        syncedAtAttr.attributeType = .dateAttributeType
        syncedAtAttr.isOptional = true
        
        paymentEntity.properties = [idAttr, amountAttr, methodAttr, statusAttr, sessionAttr, createdAtAttr, isSyncedAttr, syncedAtAttr]
        
        // 2. Entity: SessionLog
        let sessionEntity = NSEntityDescription()
        sessionEntity.name = "SessionLog"
        sessionEntity.managedObjectClassName = NSStringFromClass(SessionLogEntity.self)
        
        let sidAttr = NSAttributeDescription()
        sidAttr.name = "id"
        sidAttr.attributeType = .stringAttributeType
        sidAttr.isOptional = false
        
        let eidAttr = NSAttributeDescription()
        eidAttr.name = "eventId"
        eidAttr.attributeType = .stringAttributeType
        eidAttr.isOptional = false
        
        let totalPhotosAttr = NSAttributeDescription()
        totalPhotosAttr.name = "totalPhotos"
        totalPhotosAttr.attributeType = .integer16AttributeType
        totalPhotosAttr.isOptional = false
        
        let durationAttr = NSAttributeDescription()
        durationAttr.name = "durationSeconds"
        durationAttr.attributeType = .integer16AttributeType
        durationAttr.isOptional = false
        
        sessionEntity.properties = [sidAttr, eidAttr, totalPhotosAttr, durationAttr, createdAtAttr.copy() as! NSAttributeDescription, isSyncedAttr.copy() as! NSAttributeDescription, syncedAtAttr.copy() as! NSAttributeDescription]
        
        model.entities = [paymentEntity, sessionEntity]
        return model
    }
}

// MARK: - Managed Object Classes

@objc(PaymentTransactionEntity)
public class PaymentTransactionEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var amount: Int64
    @NSManaged public var method: String
    @NSManaged public var status: String
    @NSManaged public var sessionId: String
    @NSManaged public var createdAt: Date
    @NSManaged public var isSynced: Bool
    @NSManaged public var syncedAt: Date?
}

@objc(SessionLogEntity)
public class SessionLogEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var eventId: String
    @NSManaged public var totalPhotos: Int16
    @NSManaged public var durationSeconds: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var isSynced: Bool
    @NSManaged public var syncedAt: Date?
}
