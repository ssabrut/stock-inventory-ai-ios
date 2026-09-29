//
//  AppData.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 29/09/26.
//

import SwiftData

enum AppData {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: StockItem.self, StockTransaction.self, MenuItem.self, Shift.self, Order.self, OrderLine.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
