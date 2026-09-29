//
//  Shift.swift
//  stock-inventory-ai-ios
//

import Foundation
import SwiftData

/// A cashier session. At most one shift is open (`shiftEnd == nil`) at a
/// time; `OrderStore` enforces that.
@Model
final class Shift {
    @Attribute(.unique) var id: UUID
    var shiftStart: Date
    var shiftEnd: Date?
    @Relationship(deleteRule: .cascade, inverse: \Order.shift)
    var orders: [Order] = []

    var isActive: Bool { shiftEnd == nil }

    init(id: UUID = UUID(), shiftStart: Date = .now, shiftEnd: Date? = nil) {
        self.id = id
        self.shiftStart = shiftStart
        self.shiftEnd = shiftEnd
    }
}
