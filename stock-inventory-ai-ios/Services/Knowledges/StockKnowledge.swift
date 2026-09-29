//
//  StockKnowledge.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 29/09/26.
//

import Foundation
import SwiftData

enum StockKnowledge {
    static let maxRows = 15
    
    /// Fuzzy name search: case/diacritic-insensitive, matches any word of 3+ chars
    static func search(_ query: String, in context: ModelContext) throws -> String {
        let items = try context.fetch(FetchDescriptor<StockItem>(sortBy: [SortDescriptor(\.name)]))
        guard !items.isEmpty else { return "Belum ada stok bahan yang tercatat." }
        
        let words = normalize(query).split(separator: " ").map(String.init).filter { $0.count >= 3 }
        let matches = items.filter { item in
            let name = normalize(item.name)
            return words.contains { name.contains($0) }
        }
        
        guard !matches.isEmpty else {
            let names = items.prefix(maxRows).map(\.name).joined(separator: ", ")
            return "Tidak ada bahan yang cocok dengan \"\(query)\". Bahan yang tercatat: \(names)."
        }
        
        return matches.prefix(maxRows).map(describe).joined(separator: "\n")
    }

    /// Pre-retrieval for every chat message: facts about items the message
    /// mentions, or nil when it mentions none (so greetings stay untouched).
    static func relevantFacts(for message: String, in context: ModelContext) -> String? {
        guard let items = try? context.fetch(FetchDescriptor<StockItem>()) else { return nil }
        let words = normalize(message).split(separator: " ").map(String.init).filter { $0.count >= 3 }
        let matches = items.filter { item in
            let name = normalize(item.name)
            return words.contains { name.contains($0) }
        }
        guard !matches.isEmpty else { return nil }
        return matches.prefix(maxRows).map(describe).joined(separator: "\n")
    }

    
    /// All items, lowest quantity first, plus total stock value.
    static func list(onlyEmpty: Bool, in context: ModelContext) throws -> String {
        let items = try context.fetch(FetchDescriptor<StockItem>(sortBy: [SortDescriptor(\.quantity)]))
        let rows = onlyEmpty ? items.filter { $0.quantity <= 0 } : items
        guard !rows.isEmpty else {
            return onlyEmpty ? "Tidak ada bahan yang habis." : "Belum ada stok bahan yang tercatat."
        }

        var lines = rows.prefix(maxRows).map(describe)
        if rows.count > maxRows { lines.append("…dan \(rows.count - maxRows) bahan lain.") }
        let totalValue = items.reduce(0) { $0 + $1.quantity * $1.costPerUnit }
        lines.append("Total nilai stok: \(rupiah(totalValue)) dari \(items.count) bahan.")
        return lines.joined(separator: "\n")
    }

    /// In/out/COGS per item over the last `days` days. Empty name = all items.
    static func history(itemName: String, days: Int, in context: ModelContext) throws -> String {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let descriptor = FetchDescriptor<StockTransaction>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let target = normalize(itemName)
        let rows = try context.fetch(descriptor)
            .filter { target.isEmpty || normalize($0.itemName).contains(target) }
        guard !rows.isEmpty else { return "Tidak ada transaksi dalam \(days) hari terakhir." }

        let byItem = Dictionary(grouping: rows, by: \.itemName)
        var lines = byItem.keys.sorted().prefix(maxRows).map { name in
            let txs = byItem[name] ?? []
            let unit = txs.first?.unit ?? ""
            let added = txs.filter { $0.kind == .add }.reduce(0) { $0 + $1.quantity }
            let used = txs.filter { $0.kind == .use }.reduce(0) { $0 + abs($1.quantity) }
            let cogs = txs.filter { $0.kind == .use }.reduce(0) { $0 + $1.totalCost }
            return "- \(name): masuk \(formatQuantity(added)) \(unit), terpakai \(formatQuantity(used)) \(unit), HPP \(rupiah(cogs))"
        }
        let totalCogs = rows.filter { $0.kind == .use }.reduce(0) { $0 + $1.totalCost }
        lines.append("Total HPP \(days) hari: \(rupiah(totalCogs)).")
        return lines.joined(separator: "\n")
    }
    
    private static func describe(_ item: StockItem) -> String {
        let status = item.quantity <= 0 ? " (HABIS)" : ""
        return "- \(item.name): \(formatQuantity(item.quantity)) \(item.unit)\(status), rata-rata \(rupiah(item.costPerUnit))/\(item.unit)"
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rupiah(_ value: Double) -> String {
        value.formatted(.currency(code: "IDR").precision(.fractionLength(0)))
    }

}
