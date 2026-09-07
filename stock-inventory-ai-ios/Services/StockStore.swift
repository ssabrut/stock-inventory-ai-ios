//
//  StockStore.swift
//  stock-inventory-ai-ios
//

import CoreData
import Foundation

struct StockEntry: Identifiable, Codable {
    let id: UUID
    let itemName: String
    let quantity: Double
    let unit: String
    let date: Date

    init(id: UUID = UUID(), itemName: String, quantity: Double, unit: String, date: Date = .now) {
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
    /// Defaults to the shared App Group store; tests override this with an
    /// in-memory PersistenceController's viewContext so they never touch
    /// real inventory data.
    static var context: NSManagedObjectContext = PersistenceController.shared.viewContext

    /// Units that measure the same physical quantity, keyed to their common
    /// base unit and a multiplier to reach it. Merge-on-add converts into the
    /// base unit so e.g. "5 kg" + "500 gram" combines into one entry instead
    /// of two incompatible numbers. Base is the larger unit (kg, liter) so a
    /// merged entry displays as "5.5 kg" rather than "5500 gram". Units
    /// outside these families (pcs, box, ikat, ...) count discrete things
    /// rather than measuring an amount, so they only merge against an
    /// identical unit — see `mergeUnit`.
    private static let unitConversion: [String: (base: String, toBase: Double)] = [
        "kg": ("kg", 1), "gram": ("kg", 0.001),
        "liter": ("liter", 1), "ml": ("liter", 0.001)
    ]

    static func all() -> [StockEntry] {
        let request = StockEntryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \StockEntryEntity.date, ascending: false)]

        guard let results = try? context.fetch(request) else { return [] }
        return results.map { $0.asStockEntry }
    }

    /// Finds an existing entry to merge into: same item name (exact,
    /// case-insensitive — matching update/delete's primary lookup) and a
    /// unit compatible for merging (see `mergeUnit`).
    private static func mergeCandidate(itemName: String, unit: String) -> StockEntryEntity? {
        let request = StockEntryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "itemName ==[c] %@", itemName)

        guard let matches = try? context.fetch(request) else { return nil }
        return matches.first { entry in
            guard let existingUnit = entry.unit else { return false }
            return mergeUnit(existingUnit, unit) != nil
        }
    }

    /// Read-only lookup for callers that need to preview a merge before it
    /// happens (e.g. chat's add_stock confirmation showing current stock).
    static func existingEntry(itemName: String, unit: String) -> StockEntry? {
        mergeCandidate(itemName: itemName, unit: unit)?.asStockEntry
    }

    /// Returns the base unit both units should be summed in, or nil if they
    /// can't be merged (different families, e.g. "kg" and "pcs").
    private static func mergeUnit(_ a: String, _ b: String) -> String? {
        if a == b { return unitConversion[a]?.base ?? a }
        guard let ca = unitConversion[a], let cb = unitConversion[b], ca.base == cb.base else { return nil }
        return ca.base
    }

    private static func amount(_ quantity: Double, in unit: String, asBase base: String) -> Double {
        guard let conversion = unitConversion[unit], conversion.base == base else { return quantity }
        return quantity * conversion.toBase
    }

    /// Adds stock, merging into an existing entry with the same item name and
    /// a compatible unit (converting both into their common base unit) rather
    /// than always inserting a new row.
    @discardableResult
    static func add(itemName: String, quantity: Double, unit: String, date: Date = .now) -> StockEntry {
        if let existing = mergeCandidate(itemName: itemName, unit: unit),
           let existingUnit = existing.unit,
           let base = mergeUnit(existingUnit, unit) {
            let combined = amount(existing.quantity, in: existingUnit, asBase: base) + amount(quantity, in: unit, asBase: base)
            existing.quantity = combined
            existing.unit = base
            existing.date = date

            try? context.save()
            return existing.asStockEntry
        }

        let entry = StockEntry(itemName: itemName, quantity: quantity, unit: unit, date: date)

        let entity = StockEntryEntity(context: context)
        entity.id = entry.id
        entity.itemName = entry.itemName
        entity.quantity = entry.quantity
        entity.unit = entry.unit
        entity.date = entry.date

        try? context.save()
        return entry
    }

    /// Writes several entries in one Core Data save, used by AddStockIntent
    /// after the user confirms the full pending list from a Siri session.
    /// Each item merges with an existing entry the same way the single-item
    /// `add` does, so a Siri session adding "ayam" twice doesn't duplicate it.
    @discardableResult
    static func add(_ entries: [(itemName: String, quantity: Double, unit: String)]) -> [StockEntry] {
        let results = entries.map { item in
            add(itemName: item.itemName, quantity: item.quantity, unit: item.unit)
        }
        return results
    }

    static func update(id: UUID, itemName: String, quantity: Double, unit: String, date: Date) {
        let request = StockEntryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        entity.itemName = itemName
        entity.quantity = quantity
        entity.unit = unit
        entity.date = date

        try? context.save()
    }

    static func delete(id: UUID) {
        let request = StockEntryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        context.delete(entity)

        try? context.save()
    }
}

private extension StockEntryEntity {
    var asStockEntry: StockEntry {
        StockEntry(
            id: id ?? UUID(),
            itemName: itemName ?? "",
            quantity: quantity,
            unit: unit ?? "",
            date: date ?? .now
        )
    }
}
