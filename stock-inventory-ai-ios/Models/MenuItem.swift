//
//  MenuItem.swift
//  stock-inventory-ai-ios
//

import Foundation

struct MenuItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var price: Double
    var category: String
    var icon: String

    init(
        id: UUID = UUID(),
        name: String,
        price: Double,
        category: String,
        icon: String = "fork.knife"
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.category = category
        self.icon = icon
    }
}

extension MenuItem {
    static let mockItems: [MenuItem] = [
        MenuItem(name: "Nasi Goreng", price: 25000, category: "Makanan", icon: "fork.knife"),
        MenuItem(name: "Es Teh Manis", price: 8000, category: "Minuman", icon: "cup.and.saucer.fill"),
        MenuItem(name: "Ayam Bakar", price: 30000, category: "Makanan", icon: "flame.fill"),
        MenuItem(name: "Kopi Susu", price: 15000, category: "Minuman", icon: "cup.and.saucer.fill")
    ]
}
