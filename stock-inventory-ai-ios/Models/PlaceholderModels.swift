//
//  PlaceholderModels.swift
//  stock-inventory-ai-ios
//

import Foundation

/// Placeholder value types standing in for the data layer being rebuilt from
/// scratch — same shapes the UI screens expect, with no persistence behind
/// them yet.

struct Shift: Identifiable, Codable {
    let id: UUID
    let shiftStart: Date
    var shiftEnd: Date?

    var isActive: Bool { shiftEnd == nil }
}

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
