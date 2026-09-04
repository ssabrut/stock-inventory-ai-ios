//
//  StockStore.swift
//  stock-inventory-ai-ios
//

import CoreData
import Foundation

struct StockEntry: Identifiable, Codable {
    let id: UUID
    let itemName: String
    let quantity: Int
    let unit: String
    let date: Date

    init(id: UUID = UUID(), itemName: String, quantity: Int, unit: String, date: Date = .now) {
        self.id = id
        self.itemName = itemName
        self.quantity = quantity
        self.unit = unit
        self.date = date
    }
}

/// Core Data-backed store so both the app UI and the Siri AppIntent (which
/// runs out-of-process) can read/write the same stock data via the shared
/// App Group persistent store. See PersistenceController.
enum StockStore {
    private static var context: NSManagedObjectContext {
        PersistenceController.shared.viewContext
    }

    static func all() -> [StockEntry] {
        let request = StockEntryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StockEntryEntity.date, ascending: false)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.map { $0.asStockEntry }
    }

    @discardableResult
    static func add(itemName: String, quantity: Int, unit: String) -> StockEntry {
        let entry = StockEntry(itemName: itemName, quantity: quantity, unit: unit)

        let entity = StockEntryEntity(context: context)
        entity.id = entry.id
        entity.itemName = entry.itemName
        entity.quantity = Int32(entry.quantity)
        entity.unit = entry.unit
        entity.date = entry.date

        try? context.save()
        return entry
    }

    /// Writes several entries in one Core Data save, used by AddStockIntent
    /// after the user confirms the full pending list from a Siri session.
    @discardableResult
    static func add(_ entries: [(itemName: String, quantity: Int, unit: String)]) -> [StockEntry] {
        let results = entries.map { item -> StockEntry in
            let entry = StockEntry(itemName: item.itemName, quantity: item.quantity, unit: item.unit)

            let entity = StockEntryEntity(context: context)
            entity.id = entry.id
            entity.itemName = entry.itemName
            entity.quantity = Int32(entry.quantity)
            entity.unit = entry.unit
            entity.date = entry.date

            return entry
        }

        try? context.save()
        return results
    }
}

private extension StockEntryEntity {
    var asStockEntry: StockEntry {
        StockEntry(
            id: id ?? UUID(),
            itemName: itemName ?? "",
            quantity: Int(quantity),
            unit: unit ?? "",
            date: date ?? .now
        )
    }
}
