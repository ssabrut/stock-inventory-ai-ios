//
//  StockTools.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 29/09/26.
//

import Foundation
import FoundationModels
import SwiftData

nonisolated struct SearchStockTool: Tool {
    let name = "search_stock"
    let description = "Get current quantity, unit and average cost of specific ingredients by name."
    let container: ModelContainer
    
    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Ingredient name only, e.g. \"gula\" or \"kopi\". Not a full sentence.")
        var query: String
    }
    
    @concurrent func call(arguments: Arguments) async throws -> String {
        try await MainActor.run {
            try StockKnowledge.search(arguments.query, in: container.mainContext)
        }
    }
}

nonisolated struct ListStockTool: Tool {
    let name = "list_stock"
    let description = "List all ingredients in stock (lowest quantity first) and total stock value. Use for 'what is running low', 'what do we have', 'what is out of stock'"
    let container: ModelContainer
    
    @Generable
    nonisolated struct Arguments {
        @Guide(description: "true to list only ingredients that are out of stock")
        var onlyEmpty: Bool
    }
    
    @concurrent func call(arguments: Arguments) async throws -> String {
        try await MainActor.run {
            try StockKnowledge.list(onlyEmpty: arguments.onlyEmpty, in: container.mainContext)
        }
    }
}

nonisolated struct StockHistoryTool: Tool {
    let name = "stock_history"
    let description = "Get stock added, stock used and cost of goods used (HPP/COGS) over the last N days"
    let container: ModelContainer
    
    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Ingredient name, or empty string for all ingredients")
        var itemName: String
        
        @Guide(description: "How many days back to look", .range(1...365))
        var days: Int
    }
    
    @concurrent func call(arguments: Arguments) async throws -> String {
        try await MainActor.run {
            try StockKnowledge.history(itemName: arguments.itemName, days: arguments.days, in: container.mainContext)
        }
    }
}

/// Write tool — goes through `StockStore`, so the same validation and
/// transaction logging apply as in the UI. Errors are returned as text
/// (not thrown) so the model can explain them instead of the chat failing.
nonisolated struct RecordStockTool: Tool {
    let name = "record_stock"
    let description = "Record stock coming in (action add, e.g. bought 5kg gula for 70000) or stock used (action use). Only call when the user clearly ask to add or use stock"
    let container: ModelContainer
    
    @Generable
    nonisolated enum Action {
        case add
        case use
    }
    
    @Generable
    nonisolated struct Arguments {
        var action: Action
        
        @Guide(description: "Ingredient name")
        var itemName: String
        
        @Guide(description: "Amount, must be greater than 0")
        var quantity: Double
        
        @Guide(description: "unit: kg, gram, liter, ml, pcs, box or ikat. Empty string to keep existing unit")
        var unit: String
        
        @Guide(description: "Total price paid in rupiah for action add. 0 for action use")
        var totalCost: Double
    }
    
    @concurrent func call(arguments: Arguments) async throws -> String {
        await MainActor.run { () -> String in
            let store = StockStore(context: container.mainContext)
            guard arguments.quantity > 0 else { return "Gagal: jumlah harus lebih dari 0" }
            do {
                let existing = try store.findItem(named: arguments.itemName)
                switch arguments.action {
                case .add:
                    let unit = arguments.unit.isEmpty ? (existing?.unit ?? "pcs") : arguments.unit
                    try store.addStock(name: existing?.name ?? arguments.itemName, quantity: arguments.quantity, unit: unit, totalCost: arguments.totalCost)
                    return "Berhasil menambah \(formatQuantity(arguments.quantity)) \(unit) \(arguments.itemName)."
                case .use:
                    guard let item = existing else { return "Gagal: bahan \"\(arguments.itemName)\" tidak ditemukan." }
                    try store.use(item, quantity: arguments.quantity, note: "Lewat Tanya AI")
                    return "Berhasil mencatat pemakaian \(formatQuantity(arguments.quantity)) \(item.unit) \(item.name). Sisa \(formatQuantity(item.quantity)) \(item.unit)."
                }
            } catch {
                return "Gagal: \(error.localizedDescription)"
            }
        }
    }
}
