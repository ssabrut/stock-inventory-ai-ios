//
//  ShiftStore.swift
//  stock-inventory-ai-ios
//

import CoreData
import Foundation

struct Shift: Identifiable, Codable {
    let id: UUID
    let shiftStart: Date
    var shiftEnd: Date?

    var isActive: Bool { shiftEnd == nil }
}

/// Core Data-backed store for POS shifts, mirroring StockStore/MenuStore's
/// shape. See PersistenceController for the shared App Group store.
enum ShiftStore {
    static var context: NSManagedObjectContext = PersistenceController.shared.viewContext

    /// The currently open shift (shiftEnd == nil), if any. A device should
    /// only ever have one shift open at a time.
    static func active() -> Shift? {
        context.performAndWait {
            let request = ShiftEntity.fetchRequest()
            request.predicate = NSPredicate(format: "shiftEnd == nil")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ShiftEntity.shiftStart, ascending: false)]
            request.fetchLimit = 1

            return try? context.fetch(request).first?.asShift
        }
    }

    @discardableResult
    static func start(date: Date = .now) -> Shift {
        context.performAndWait {
            let shift = Shift(id: UUID(), shiftStart: date, shiftEnd: nil)

            let entity = ShiftEntity(context: context)
            entity.id = shift.id
            entity.shiftStart = shift.shiftStart
            entity.shiftEnd = nil

            try? context.save()
            return shift
        }
    }

    static func end(id: UUID, date: Date = .now) {
        context.performAndWait {
            let request = ShiftEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return }
            entity.shiftEnd = date

            try? context.save()
        }
    }

    static func all() -> [Shift] {
        context.performAndWait {
            let request = ShiftEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ShiftEntity.shiftStart, ascending: false)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.map { $0.asShift }
        }
    }

    static func deleteAll() {
        context.performAndWait {
            let request = ShiftEntity.fetchRequest()
            guard let results = try? context.fetch(request) else { return }
            for entity in results {
                context.delete(entity)
            }
            try? context.save()
        }
    }
}

private extension ShiftEntity {
    var asShift: Shift {
        Shift(id: id ?? UUID(), shiftStart: shiftStart ?? .now, shiftEnd: shiftEnd)
    }
}
