//
//  OrderStore.swift
//  stock-inventory-ai-ios
//

import CoreData
import Foundation

struct OrderLine: Identifiable {
    let id: UUID
    let menuItemId: UUID
    let name: String
    let price: Double
    let quantity: Int

    var subtotal: Double { price * Double(quantity) }
}

struct Order: Identifiable {
    let id: UUID
    let shiftId: UUID
    let date: Date
    let total: Double
    let items: [OrderLine]
}

/// Core Data-backed store for completed POS sales, mirroring
/// StockStore/ShiftStore's shape. See PersistenceController for the shared
/// App Group store.
enum OrderStore {
    static var context: NSManagedObjectContext = PersistenceController.shared.viewContext

    /// Saves a completed sale as one OrderEntity plus one OrderItemEntity per
    /// cart line, tagged with the shift it was rung up under.
    @discardableResult
    static func checkout(shiftId: UUID, items: [CartItem], date: Date = .now) -> Order {
        context.performAndWait {
            let total = items.reduce(0) { $0 + $1.subtotal }
            let orderId = UUID()

            let orderEntity = OrderEntity(context: context)
            orderEntity.id = orderId
            orderEntity.shiftId = shiftId
            orderEntity.date = date
            orderEntity.total = total

            let lines = items.map { item -> OrderLine in
                let lineId = UUID()

                let itemEntity = OrderItemEntity(context: context)
                itemEntity.id = lineId
                itemEntity.orderId = orderId
                itemEntity.menuItemId = item.menuItem.id
                itemEntity.name = item.menuItem.name
                itemEntity.price = item.menuItem.price
                itemEntity.quantity = Int32(item.quantity)

                return OrderLine(id: lineId, menuItemId: item.menuItem.id, name: item.menuItem.name, price: item.menuItem.price, quantity: item.quantity)
            }

            try? context.save()
            return Order(id: orderId, shiftId: shiftId, date: date, total: total, items: lines)
        }
    }

    /// All orders rung up during a given shift, most recent first.
    static func forShift(_ shiftId: UUID) -> [Order] {
        context.performAndWait {
            let request = OrderEntity.fetchRequest()
            request.predicate = NSPredicate(format: "shiftId == %@", shiftId as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \OrderEntity.date, ascending: false)]

            guard let orderEntities = try? context.fetch(request) else { return [] }
            return orderEntities.map { $0.asOrder(items: items(forOrder: $0.id ?? UUID())) }
        }
    }

    private static func items(forOrder orderId: UUID) -> [OrderLine] {
        let request = OrderItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "orderId == %@", orderId as CVarArg)

        guard let results = try? context.fetch(request) else { return [] }
        return results.map { $0.asOrderLine }
    }

    static func deleteAll() {
        context.performAndWait {
            let orderRequest = OrderEntity.fetchRequest()
            if let orders = try? context.fetch(orderRequest) {
                for entity in orders {
                    context.delete(entity)
                }
            }

            let itemRequest = OrderItemEntity.fetchRequest()
            if let items = try? context.fetch(itemRequest) {
                for entity in items {
                    context.delete(entity)
                }
            }

            try? context.save()
        }
    }
}

private extension OrderEntity {
    func asOrder(items: [OrderLine]) -> Order {
        Order(id: id ?? UUID(), shiftId: shiftId ?? UUID(), date: date ?? .now, total: total, items: items)
    }
}

private extension OrderItemEntity {
    var asOrderLine: OrderLine {
        OrderLine(id: id ?? UUID(), menuItemId: menuItemId ?? UUID(), name: name ?? "", price: price, quantity: Int(quantity))
    }
}
