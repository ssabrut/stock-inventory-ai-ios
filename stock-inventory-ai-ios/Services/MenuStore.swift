//
//  MenuStore.swift
//  stock-inventory-ai-ios
//

import CoreData
import Foundation

/// Core Data-backed store for POS menu items, mirroring StockStore's shape.
/// See PersistenceController for the shared App Group store.
enum MenuStore {
    static var context: NSManagedObjectContext = PersistenceController.shared.viewContext

    static func all() -> [MenuItem] {
        context.performAndWait {
            let request = MenuItemEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \MenuItemEntity.name, ascending: true)]

            guard let results = try? context.fetch(request) else { return [] }
            return results.map { $0.asMenuItem }
        }
    }

    @discardableResult
    static func add(name: String, price: Double, category: String, icon: String) -> MenuItem {
        context.performAndWait {
            let item = MenuItem(name: name, price: price, category: category, icon: icon)

            let entity = MenuItemEntity(context: context)
            entity.id = item.id
            entity.name = item.name
            entity.price = item.price
            entity.category = item.category
            entity.icon = item.icon

            try? context.save()
            return item
        }
    }

    static func update(_ item: MenuItem) {
        context.performAndWait {
            let request = MenuItemEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return }
            entity.name = item.name
            entity.price = item.price
            entity.category = item.category
            entity.icon = item.icon

            try? context.save()
        }
    }

    static func delete(id: UUID) {
        context.performAndWait {
            let request = MenuItemEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return }
            context.delete(entity)

            try? context.save()
        }
    }

    static func deleteAll() {
        context.performAndWait {
            let request = MenuItemEntity.fetchRequest()
            guard let results = try? context.fetch(request) else { return }
            for entity in results {
                context.delete(entity)
            }
            try? context.save()
        }
    }
}

private extension MenuItemEntity {
    var asMenuItem: MenuItem {
        MenuItem(
            id: id ?? UUID(),
            name: name ?? "",
            price: price,
            category: category ?? "",
            icon: icon ?? "fork.knife"
        )
    }
}
