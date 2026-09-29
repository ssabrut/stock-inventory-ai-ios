//
//  Order.swift
//  stock-inventory-ai-ios
//

import Foundation
import SwiftData

/// One checkout from the POS.
@Model
final class Order {
    @Attribute(.unique) var id: UUID
    var date: Date
    var total: Double
    var shift: Shift?
    @Relationship(deleteRule: .cascade, inverse: \OrderLine.order)
    var items: [OrderLine] = []

    init(id: UUID = UUID(), date: Date = .now, total: Double) {
        self.id = id
        self.date = date
        self.total = total
    }
}

/// Snapshot of a menu item at checkout time — name and price are copied, so
/// later menu edits don't change past revenue.
@Model
final class OrderLine {
    var menuItemId: UUID
    var name: String
    var price: Double
    var quantity: Int
    var order: Order?

    var subtotal: Double { price * Double(quantity) }

    init(menuItemId: UUID, name: String, price: Double, quantity: Int) {
        self.menuItemId = menuItemId
        self.name = name
        self.price = price
        self.quantity = quantity
    }
}
