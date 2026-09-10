//
//  OpnameStore.swift
//  stock-inventory-ai-ios
//

import CoreData
import Foundation

/// One counted item within an opname session — the system's recorded
/// quantity at count time vs. what was physically counted. `diffQty` is
/// signed: positive means a surplus (found more than recorded), negative a
/// shortage.
struct OpnameSessionItem: Identifiable, Codable {
    let id: UUID
    let itemName: String
    let unit: String
    let systemQty: Double
    var countedQty: Double
    let costPerUnit: Double

    init(id: UUID = UUID(), itemName: String, unit: String, systemQty: Double, countedQty: Double, costPerUnit: Double) {
        self.id = id
        self.itemName = itemName
        self.unit = unit
        self.systemQty = systemQty
        self.countedQty = countedQty
        self.costPerUnit = costPerUnit
    }

    var diffQty: Double { countedQty - systemQty }
}

/// A completed stock-count session: the counted items and their diffs vs.
/// system quantity at the time. Kept as its own record (separate from the
/// StockTransaction log it produces) so the app can show "what happened in
/// this count" as one unit instead of reconstructing it from scattered
/// add/remove transactions.
struct OpnameSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let note: String?
    let items: [OpnameSessionItem]

    init(id: UUID = UUID(), date: Date = .now, note: String? = nil, items: [OpnameSessionItem]) {
        self.id = id
        self.date = date
        self.note = note
        self.items = items
    }

    /// Only the items whose count actually differs from system stock —
    /// what the confirmation screen and StockStore adjustment loop over.
    var discrepancies: [OpnameSessionItem] { items.filter { $0.diffQty != 0 } }
}

/// Core Data-backed store for stock opname (physical count) sessions. Reuses
/// StockStore.add/use to apply each item's diff — a surplus logs as an
/// `.add`, a shortage as a `.remove` — tagged with the "Opname" note so
/// History can label these apart from ordinary purchases/usage. See
/// StockStore for the shared App Group context this reads/writes through.
enum OpnameStore {
    static let noteLabel = "Opname"

    static var context: NSManagedObjectContext { StockStore.context }

    /// Snapshot of every current stock entry as a starting point for a new
    /// count session — the screen fills in `countedQty` as the user counts.
    static func startSession() -> [OpnameSessionItem] {
        StockStore.all().map { entry in
            OpnameSessionItem(itemName: entry.itemName, unit: entry.unit, systemQty: entry.quantity, countedQty: entry.quantity, costPerUnit: entry.costPerUnit)
        }
    }

    /// Applies every discrepancy in `items` as a stock adjustment, then
    /// persists the session record. Items whose count matches system stock
    /// are stored in the session for reference but produce no transaction.
    @discardableResult
    static func commitSession(items: [OpnameSessionItem], date: Date = .now, note: String? = nil) -> OpnameSession {
        let session = OpnameSession(date: date, note: note, items: items)

        for item in session.discrepancies {
            if item.diffQty > 0 {
                StockStore.add(itemName: item.itemName, quantity: item.diffQty, unit: item.unit, totalCost: item.diffQty * item.costPerUnit, date: date, note: noteLabel)
            } else if let entry = StockStore.existingEntry(itemName: item.itemName, unit: item.unit) {
                StockStore.use(id: entry.id, quantity: min(-item.diffQty, entry.quantity), date: date, note: noteLabel)
            }
        }

        context.performAndWait {
            let sessionEntity = OpnameSessionEntity(context: context)
            sessionEntity.id = session.id
            sessionEntity.date = session.date
            sessionEntity.note = session.note

            for item in session.items {
                let itemEntity = OpnameSessionItemEntity(context: context)
                itemEntity.id = item.id
                itemEntity.sessionId = session.id
                itemEntity.itemName = item.itemName
                itemEntity.unit = item.unit
                itemEntity.systemQty = item.systemQty
                itemEntity.countedQty = item.countedQty
                itemEntity.costPerUnit = item.costPerUnit
            }

            try? context.save()
        }

        return session
    }

    /// Every past opname session, most recent first, with its items
    /// attached.
    static func allSessions() -> [OpnameSession] {
        context.performAndWait {
            let sessionRequest = OpnameSessionEntity.fetchRequest()
            sessionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \OpnameSessionEntity.date, ascending: false)]
            guard let sessionEntities = try? context.fetch(sessionRequest) else { return [] }

            let itemRequest = OpnameSessionItemEntity.fetchRequest()
            guard let itemEntities = try? context.fetch(itemRequest) else { return [] }
            let itemsBySession = Dictionary(grouping: itemEntities, by: { $0.sessionId })

            return sessionEntities.compactMap { sessionEntity -> OpnameSession? in
                guard let id = sessionEntity.id, let date = sessionEntity.date else { return nil }
                let items = (itemsBySession[id] ?? []).compactMap { $0.asOpnameSessionItem }
                return OpnameSession(id: id, date: date, note: sessionEntity.note, items: items)
            }
        }
    }
}

private extension OpnameSessionItemEntity {
    var asOpnameSessionItem: OpnameSessionItem? {
        guard let id, let itemName, let unit else { return nil }
        return OpnameSessionItem(id: id, itemName: itemName, unit: unit, systemQty: systemQty, countedQty: countedQty, costPerUnit: costPerUnit)
    }
}
