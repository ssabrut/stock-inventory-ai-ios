//
//  PersistenceController.swift
//  stock-inventory-ai-ios
//

import CoreData

/// Owns the Core Data stack. Store lives in the App Group shared container so
/// the Siri AppIntent (which runs out-of-process) reads/writes the same data
/// as the main app.
final class PersistenceController {
    static let shared = PersistenceController()

    static let appGroupID = "group.stock-inventory-ai-ios"

    let container: NSPersistentContainer
    private var remoteChangeObserver: NSObjectProtocol?
    private var lastHistoryToken: NSPersistentHistoryToken?

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

        // Needed so this process picks up writes made by the Siri AppIntent,
        // which runs in a separate process against the same App Group store.
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error {
                assertionFailure("Core Data failed to load store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        observeRemoteChanges()
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    /// The Siri AppIntent writes from a separate process. Core Data's
    /// automatic parent-merge only covers contexts within this process, so
    /// on a remote-change notification we merge just the new persistent
    /// history into the view context. This updates/inserts objects in place
    /// instead of faulting everything out (which `reset()` did, and which
    /// briefly showed blank rows in InventoryScreen's @FetchRequest until
    /// the next refetch completed).
    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.mergeNewHistory()
        }
    }

    private func mergeNewHistory() {
        let context = newBackgroundContext()
        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastHistoryToken)
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction]
            else { return }

            for transaction in transactions {
                container.viewContext.perform {
                    self.container.viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                }
            }

            if let newToken = transactions.last?.token {
                lastHistoryToken = newToken
            }
        }
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
