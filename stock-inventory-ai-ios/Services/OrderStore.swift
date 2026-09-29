//
//  OrderStore.swift
//  stock-inventory-ai-ios
//

import Foundation
import SwiftData

/// Single write path for POS shifts and orders, mirroring `StockStore`.
struct OrderStore {
    let context: ModelContext

    func activeShift() throws -> Shift? {
        var descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.shiftEnd == nil },
            sortBy: [SortDescriptor(\.shiftStart, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Reuses the open shift if there is one, so a double tap (or a shift
    /// left open before a relaunch) never creates two active shifts.
    @discardableResult
    func startShift() throws -> Shift {
        if let open = try activeShift() { return open }
        let shift = Shift()
        context.insert(shift)
        try context.save()
        return shift
    }

    func endShift(_ shift: Shift) throws {
        shift.shiftEnd = .now
        try context.save()
    }

    @discardableResult
    func checkout(_ cart: [CartItem], in shift: Shift, date: Date = .now) throws -> Order {
        let order = Order(date: date, total: cart.reduce(0) { $0 + $1.subtotal })
        context.insert(order)
        order.shift = shift
        order.items = cart.map {
            OrderLine(menuItemId: $0.menuItem.id, name: $0.menuItem.name, price: $0.menuItem.price, quantity: $0.quantity)
        }
        try context.save()
        return order
    }
}
