//
//  StockStore.swift
//  stock-inventory-ai-ios
//

import Foundation

struct StockEntry: Identifiable, Codable {
    let id: UUID
    let itemName: String
    let quantity: Int
    let unit: String
    let date: Date

    init(itemName: String, quantity: Int, unit: String, date: Date = .now) {
        self.id = UUID()
        self.itemName = itemName
        self.quantity = quantity
        self.unit = unit
        self.date = date
    }
}

/// Minimal UserDefaults-backed store so both the app UI and the Siri AppIntent
/// (which runs out-of-process) can read/write the same stock data.
enum StockStore {
    private static let defaultsKey = "stockEntries"
    private static let suiteName = "group.stock-inventory-ai-ios"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func all() -> [StockEntry] {
        guard let data = defaults.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([StockEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.date > $1.date }
    }

    @discardableResult
    static func add(itemName: String, quantity: Int, unit: String) -> StockEntry {
        let entry = StockEntry(itemName: itemName, quantity: quantity, unit: unit)
        var entries = all()
        entries.append(entry)
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: defaultsKey)
        }
        return entry
    }
}
