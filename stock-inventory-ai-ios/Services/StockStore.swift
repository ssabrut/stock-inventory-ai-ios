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
    /// Weighted-average cost per unit across every "add" that fed this entry.
    let costPerUnit: Double

    init(id: UUID = UUID(), itemName: String, quantity: Double, unit: String, date: Date = .now, costPerUnit: Double = 0) {
        self.id = id
        self.itemName = itemName
        self.quantity = quantity
        self.unit = unit
        self.date = date
        self.costPerUnit = costPerUnit
    }
}

/// One add or use/sell event, kept forever (independent of StockEntryEntity,
/// which only holds the current merged quantity) so History/COGS can look
/// back at what happened over time.
struct StockTransaction: Identifiable, Codable {
    enum Kind: String, Codable {
        case add
        case remove
    }

    let id: UUID
    let itemName: String
    let quantity: Double
    let unit: String
    let costPerUnit: Double
    let type: Kind
    let date: Date
    /// Optional label for what generated this transaction, e.g. "Opname" for
    /// a stock-count adjustment — shown in History to distinguish it from a
    /// regular purchase/use. Nil for ordinary add/use transactions.
    let note: String?

    init(id: UUID, itemName: String, quantity: Double, unit: String, costPerUnit: Double, type: Kind, date: Date, note: String? = nil) {
        self.id = id
        self.itemName = itemName
        self.quantity = quantity
        self.unit = unit
        self.costPerUnit = costPerUnit
        self.type = type
        self.date = date
        self.note = note
    }

    /// Total cost of this transaction — for a `.remove` this is its
    /// contribution to COGS.
    var totalCost: Double { quantity * costPerUnit }
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

    /// The cost-per-unit already on file for this item (any unit — unlike
    /// `existingEntry`, this doesn't require unit compatibility), used to
    /// default a new entry's cost when the caller doesn't know it, e.g. the
    /// voice-add flow which doesn't ask for cost. Returns 0 if the item has
    /// never been added with a known cost.
    static func lastKnownCost(itemName: String) -> Double {
        context.performAndWait {
            let request = StockEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "itemName ==[c] %@ AND costPerUnit > 0", itemName)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \StockEntryEntity.date, ascending: false)]
            request.fetchLimit = 1

            return (try? context.fetch(request).first?.costPerUnit) ?? 0
        }
    }

    static func all() -> [StockEntry] {
        context.performAndWait {
            let request = StockEntryEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \StockEntryEntity.date, ascending: false)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.map { $0.asStockEntry }
        }
    }

    /// Finds an existing entry to merge into: same item name — exact
    /// case-insensitive match preferred, falling back to a fuzzy match (see
    /// `fuzzyNameMatches`) so e.g. chat's LLM-transcribed "ayem" still finds
    /// "Ayam" — and a unit compatible for merging (see `mergeUnit`).
    private static func mergeCandidate(itemName: String, unit: String) -> StockEntryEntity? {
        context.performAndWait {
            let request = StockEntryEntity.fetchRequest()
            guard let allEntries = try? context.fetch(request) else { return nil }

            func unitCompatible(_ entry: StockEntryEntity) -> Bool {
                guard let existingUnit = entry.unit else { return false }
                return mergeUnit(existingUnit, unit) != nil
            }

            if let exact = allEntries.first(where: { $0.itemName?.caseInsensitiveCompare(itemName) == .orderedSame && unitCompatible($0) }) {
                return exact
            }
            return allEntries
                .filter(unitCompatible)
                .compactMap { entry -> (StockEntryEntity, Int)? in
                    guard let existingName = entry.itemName, fuzzyNameMatches(existingName, itemName) else { return nil }
                    return (entry, levenshteinDistance(existingName.lowercased(), itemName.lowercased()))
                }
                .min { $0.1 < $1.1 }?.0
        }
    }

    /// Whether two item names are close enough to treat as the same item —
    /// used so a slightly mistyped/mistranscribed name (e.g. "ayem" for
    /// "Ayam") still merges instead of silently creating a duplicate entry.
    /// Tolerance scales with name length so short names still require a
    /// near-exact match.
    private static func fuzzyNameMatches(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        let maxDistance = max(1, min(a.count, b.count) / 4)
        return levenshteinDistance(a, b) <= maxDistance
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...Swift.max(a.count, 1) where a.count > 0 {
            current[0] = i
            for j in 1...Swift.max(b.count, 1) where b.count > 0 {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return b.isEmpty ? a.count : previous[b.count]
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
    /// than always inserting a new row. `totalCost` is what this whole batch
    /// cost (e.g. Rp150,000 for 5kg of chicken) — callers ask for a total
    /// rather than a per-unit price since that's what a receipt actually
    /// shows. Internally divided into cost-per-unit, which blends into the
    /// entry's running weighted-average cost. Logs a `.add` transaction so
    /// History/COGS has a permanent record.
    @discardableResult
    static func add(itemName: String, quantity: Double, unit: String, totalCost: Double = 0, date: Date = .now, note: String? = nil) -> StockEntry {
        context.performAndWait {
            let costPerUnit = quantity > 0 ? totalCost / quantity : 0
            logTransaction(itemName: itemName, quantity: quantity, unit: unit, costPerUnit: costPerUnit, type: .add, date: date, note: note)

            if let existing = mergeCandidate(itemName: itemName, unit: unit),
               let existingUnit = existing.unit,
               let base = mergeUnit(existingUnit, unit) {
                let existingBaseQty = amount(existing.quantity, in: existingUnit, asBase: base)
                let addedBaseQty = amount(quantity, in: unit, asBase: base)
                let combined = existingBaseQty + addedBaseQty

                // Weighted-average cost, converted into cost-per-base-unit so
                // blending stays correct across a unit conversion (e.g. existing
                // "5 kg @ Rp30k/kg" + new "500 gram @ Rp32/gram" both normalize
                // to cost-per-kg before averaging).
                let existingCostPerBase = costPerBase(existing.costPerUnit, unit: existingUnit, base: base)
                let addedCostPerBase = costPerBase(costPerUnit, unit: unit, base: base)
                let blendedCost = combined > 0
                    ? (existingBaseQty * existingCostPerBase + addedBaseQty * addedCostPerBase) / combined
                    : 0

                existing.quantity = combined
                existing.unit = base
                existing.costPerUnit = blendedCost
                existing.date = date

                try? context.save()
                return existing.asStockEntry
            }

            let entry = StockEntry(itemName: itemName, quantity: quantity, unit: unit, date: date, costPerUnit: costPerUnit)

            let entity = StockEntryEntity(context: context)
            entity.id = entry.id
            entity.itemName = entry.itemName
            entity.quantity = entry.quantity
            entity.unit = entry.unit
            entity.date = entry.date
            entity.costPerUnit = entry.costPerUnit

            try? context.save()
            return entry
        }
    }

    /// Writes several entries in one Core Data save, used by AddStockIntent
    /// after the user confirms the full pending list from a Siri session.
    /// Each item merges with an existing entry the same way the single-item
    /// `add` does, so a Siri session adding "ayam" twice doesn't duplicate it.
    @discardableResult
    static func add(_ entries: [(itemName: String, quantity: Double, unit: String, totalCost: Double)]) -> [StockEntry] {
        let results = entries.map { item in
            add(itemName: item.itemName, quantity: item.quantity, unit: item.unit, totalCost: item.totalCost)
        }
        return results
    }

    /// Converts a cost-per-`unit` figure into cost-per-`base`-unit (e.g. Rp
    /// per gram -> Rp per kg is `costPerUnit / 0.001`, since 1 base unit
    /// equals `toBase` of `unit`).
    private static func costPerBase(_ costPerUnit: Double, unit: String, base: String) -> Double {
        guard let conversion = unitConversion[unit], conversion.base == base, conversion.toBase != 0 else { return costPerUnit }
        return costPerUnit / conversion.toBase
    }

    /// Corrects an existing entry directly, including a raw override of its
    /// costPerUnit — unlike `add`, this doesn't log a transaction or blend
    /// into a weighted average, since it's a data-entry fix, not a purchase.
    static func update(id: UUID, itemName: String, quantity: Double, unit: String, costPerUnit: Double, date: Date) {
        context.performAndWait {
            let request = StockEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return }
            entity.itemName = itemName
            entity.quantity = quantity
            entity.unit = unit
            entity.costPerUnit = costPerUnit
            entity.date = date

            try? context.save()
        }
    }

    static func delete(id: UUID) {
        context.performAndWait {
            let request = StockEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return }
            context.delete(entity)

            try? context.save()
        }
    }

    /// Records stock going out (used/sold), charged at the entry's current
    /// weighted-average cost — this is what feeds COGS. Distinct from
    /// `delete`, which is a data correction and logs no transaction. Returns
    /// false (no-op) if `quantity` exceeds what's on hand.
    @discardableResult
    static func use(id: UUID, quantity: Double, date: Date = .now, note: String? = nil) -> Bool {
        context.performAndWait {
            let request = StockEntryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first,
                  quantity > 0, quantity <= entity.quantity,
                  let itemName = entity.itemName, let unit = entity.unit
            else { return false }

            logTransaction(itemName: itemName, quantity: quantity, unit: unit, costPerUnit: entity.costPerUnit, type: .remove, date: date, note: note)

            entity.quantity -= quantity
            if entity.quantity <= 0 {
                context.delete(entity)
            }

            try? context.save()
            return true
        }
    }

    /// Callers must already be running inside `context.performAndWait`.
    @discardableResult
    private static func logTransaction(itemName: String, quantity: Double, unit: String, costPerUnit: Double, type: StockTransaction.Kind, date: Date, note: String? = nil) -> StockTransaction {
        let transaction = StockTransaction(id: UUID(), itemName: itemName, quantity: quantity, unit: unit, costPerUnit: costPerUnit, type: type, date: date, note: note)

        let entity = StockTransactionEntity(context: context)
        entity.id = transaction.id
        entity.itemName = transaction.itemName
        entity.quantity = transaction.quantity
        entity.unit = transaction.unit
        entity.costPerUnit = transaction.costPerUnit
        entity.type = transaction.type.rawValue
        entity.date = transaction.date
        entity.note = transaction.note

        try? context.save()
        return transaction
    }

    /// All transactions (add + remove), most recent first — the History
    /// screen's data source.
    static func allTransactions() -> [StockTransaction] {
        context.performAndWait {
            let request = StockTransactionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \StockTransactionEntity.date, ascending: false)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { $0.asStockTransaction }
        }
    }

    /// Wipes the transaction log — used by tests to reset the in-memory store
    /// between cases (StockStore.all()/delete only clears StockEntryEntity,
    /// leaving transactions to accumulate across every add() call).
    static func deleteAllTransactions() {
        context.performAndWait {
            let request = StockTransactionEntity.fetchRequest()
            guard let results = try? context.fetch(request) else { return }
            for entity in results {
                context.delete(entity)
            }
            try? context.save()
        }
    }

    /// Wipes every stock entry and transaction — full reset of the app's
    /// Core Data store, e.g. for a "clear all data" settings action.
    static func deleteAll() {
        context.performAndWait {
            let entryRequest = StockEntryEntity.fetchRequest()
            if let entries = try? context.fetch(entryRequest) {
                for entity in entries {
                    context.delete(entity)
                }
            }

            let transactionRequest = StockTransactionEntity.fetchRequest()
            if let transactions = try? context.fetch(transactionRequest) {
                for entity in transactions {
                    context.delete(entity)
                }
            }

            try? context.save()
        }
    }

    /// Total cost of goods sold (sum of every `.remove` transaction's
    /// quantity * costPerUnit) within an optional date range.
    static func cogs(from startDate: Date? = nil, to endDate: Date? = nil) -> Double {
        allTransactions()
            .filter { transaction in
                guard transaction.type == .remove else { return false }
                if let startDate, transaction.date < startDate { return false }
                if let endDate, transaction.date > endDate { return false }
                return true
            }
            .reduce(0) { $0 + $1.totalCost }
    }
}

private extension StockEntryEntity {
    var asStockEntry: StockEntry {
        StockEntry(
            id: id ?? UUID(),
            itemName: itemName ?? "",
            quantity: quantity,
            unit: unit ?? "",
            date: date ?? .now,
            costPerUnit: costPerUnit
        )
    }
}

private extension StockTransactionEntity {
    var asStockTransaction: StockTransaction? {
        guard let id, let itemName, let unit, let type = type.flatMap(StockTransaction.Kind.init) else { return nil }
        return StockTransaction(
            id: id,
            itemName: itemName,
            quantity: quantity,
            unit: unit,
            costPerUnit: costPerUnit,
            type: type,
            date: date ?? .now,
            note: note
        )
    }
}
