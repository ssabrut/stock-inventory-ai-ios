//
//  PersistenceController.swift
//  stock-inventory-ai-ios
//

import CoreData

/// Owns the Core Data stack. Store lives in the App Group shared container so
/// the Siri AppIntent (which runs out-of-process) reads/writes the same data
/// as the main app.
struct PersistenceController {
    static let shared = PersistenceController()

    static let appGroupID = "group.stock-inventory-ai-ios"

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Inventory")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(filePath: "/dev/null")
        } else if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            let storeURL = groupURL.appending(path: "Inventory.sqlite")
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true

        container.loadPersistentStores { _, error in
            if let error {
                assertionFailure("Core Data failed to load store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}
