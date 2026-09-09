//
//  CartItem.swift
//  stock-inventory-ai-ios
//

import Foundation

/// One line in an in-progress POS sale. Not persisted — the cart lives only
/// for the duration of building up a checkout in PosSaleScreen.
struct CartItem: Identifiable {
    let menuItem: MenuItem
    var quantity: Int

    var id: UUID { menuItem.id }
    var subtotal: Double { menuItem.price * Double(quantity) }
}
