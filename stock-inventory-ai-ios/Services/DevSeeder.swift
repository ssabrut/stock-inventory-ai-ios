//
//  DevSeeder.swift
//  stock-inventory-ai-ios
//

import Foundation

/// Debug-only helper that fills the Core Data store with dummy stock and POS
/// menu data, so the app has something to look at without manual data entry.
/// Not compiled into release builds.
#if DEBUG
enum DevSeeder {
    /// Wipes existing stock/menu data, then inserts a fixed set of dummy
    /// entries covering both StockStore and MenuStore.
    static func seed() {
        StockStore.deleteAll()
        MenuStore.deleteAll()

        for entry in dummyStockEntries {
            StockStore.add(itemName: entry.itemName, quantity: entry.quantity, unit: entry.unit, totalCost: entry.totalCost, date: entry.date)
        }

        for item in dummyMenuItems {
            MenuStore.add(name: item.name, price: item.price, category: item.category, icon: item.icon)
        }
    }

    private static let dummyStockEntries: [(itemName: String, quantity: Double, unit: String, totalCost: Double, date: Date)] = [
        (itemName: "Ayam", quantity: 5, unit: "kg", totalCost: 150000, date: .now.addingTimeInterval(-86400 * 1)),
        (itemName: "Beras", quantity: 25, unit: "kg", totalCost: 325000, date: .now.addingTimeInterval(-86400 * 2)),
        (itemName: "Telur", quantity: 10, unit: "kg", totalCost: 280000, date: .now.addingTimeInterval(-86400 * 3)),
        (itemName: "Minyak Goreng", quantity: 5, unit: "liter", totalCost: 90000, date: .now.addingTimeInterval(-86400 * 4)),
        (itemName: "Gula Pasir", quantity: 8, unit: "kg", totalCost: 120000, date: .now.addingTimeInterval(-86400 * 5)),
        (itemName: "Kopi Bubuk", quantity: 2, unit: "kg", totalCost: 80000, date: .now.addingTimeInterval(-86400 * 6)),
        (itemName: "Susu Kental Manis", quantity: 24, unit: "pcs", totalCost: 96000, date: .now.addingTimeInterval(-86400 * 7)),
        (itemName: "Teh Celup", quantity: 3, unit: "box", totalCost: 45000, date: .now.addingTimeInterval(-86400 * 8)),
        (itemName: "Bawang Merah", quantity: 3, unit: "kg", totalCost: 90000, date: .now.addingTimeInterval(-86400 * 9)),
        (itemName: "Cabai Rawit", quantity: 2, unit: "kg", totalCost: 70000, date: .now.addingTimeInterval(-86400 * 10))
    ]

    private static let dummyMenuItems: [(name: String, price: Double, category: String, icon: String)] = [
        (name: "Nasi Goreng", price: 25000, category: MenuCategory.makanan.rawValue, icon: "fork.knife"),
        (name: "Ayam Bakar", price: 30000, category: MenuCategory.makanan.rawValue, icon: "flame.fill"),
        (name: "Mie Goreng", price: 22000, category: MenuCategory.makanan.rawValue, icon: "fork.knife"),
        (name: "Sate Ayam", price: 28000, category: MenuCategory.makanan.rawValue, icon: "flame.fill"),
        (name: "Soto Ayam", price: 20000, category: MenuCategory.makanan.rawValue, icon: "fork.knife"),
        (name: "Es Teh Manis", price: 8000, category: MenuCategory.minuman.rawValue, icon: "cup.and.saucer.fill"),
        (name: "Kopi Susu", price: 15000, category: MenuCategory.minuman.rawValue, icon: "cup.and.saucer.fill"),
        (name: "Es Jeruk", price: 10000, category: MenuCategory.minuman.rawValue, icon: "cup.and.saucer.fill"),
        (name: "Teh Tawar Hangat", price: 5000, category: MenuCategory.minuman.rawValue, icon: "cup.and.saucer.fill"),
        (name: "Jus Alpukat", price: 18000, category: MenuCategory.minuman.rawValue, icon: "cup.and.saucer.fill")
    ]
}
#endif
