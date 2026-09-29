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
    
    enum ItemMatch {
        case found(StockItem)
        case ambiguous([String])
        case notFound(suggestions: [String])
    }
    
    /// Word match → typo (edit distance ≤ 2). Model only has to get close.
    ///
    /// An exact name does *not* win on its own: with "Gula" and "Gula Halus"
    /// both stocked, "gula" is ambiguous and the user is asked. Pass
    /// `preferExact` once the user has picked, so the same name resolves.
    static func resolve(_ name: String, in context: ModelContext, preferExact: Bool = false) throws -> ItemMatch {
        let items = try context.fetch(FetchDescriptor<StockItem>(sortBy: [SortDescriptor(\.name)]))
        let target = normalize(name)
        let exact = items.first { normalize($0.name) == target }
        if preferExact, let exact { return .found(exact) }

        // Every typed word appears as a whole word in the name — "gula"
        // matches "Gula Halus" but not "Gulai Ayam".
        let targetWords = Set(words(target))
        let candidates = items.filter { !targetWords.isEmpty && targetWords.isSubset(of: words(normalize($0.name))) }
        if candidates.count == 1 { return .found(candidates[0]) }
        if candidates.count > 1 {
            // Exact match listed first — it's the likeliest pick.
            let ordered = (exact.map { [$0] } ?? []) + candidates.filter { $0 !== exact }
            return .ambiguous(ordered.map(\.name))
        }

        let close = items
            .map { (item: $0, distance: editDistance(normalize($0.name), target)) }
            .filter { $0.distance <= 2 }
            .sorted { $0.distance < $1.distance }
        if let best = close.first, close.count == 1 || close[1].distance > best.distance {
            return .found(best.item)
        }
        return .notFound(suggestions: close.prefix(3).map(\.item.name))
    }

    /// Maps what people type to the canonical units in `StockUnits`.
    static func normalizeUnit(_ unit: String) -> String {
        let aliases = ["kilo": "kg", "kilogram": "kg", "gr": "gram", "g": "gram",
                       "l": "liter", "ltr": "liter", "biji": "pcs", "buah": "pcs", "pc": "pcs"]
        let key = normalize(unit)
        return aliases[key] ?? key
    }

    static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
    
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
    /// `exactName` for a resolved item, so "Gula" doesn't pull in "Gula Halus".
    static func history(itemName: String, days: Int, exactName: Bool = false, in context: ModelContext) throws -> String {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let descriptor = FetchDescriptor<StockTransaction>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let target = normalize(itemName)
        let rows = try context.fetch(descriptor).filter { transaction in
            let name = normalize(transaction.itemName)
            return target.isEmpty || (exactName ? name == target : name.contains(target))
        }
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
    
    static func describe(_ item: StockItem) -> String {
        let status = item.quantity <= 0 ? " (HABIS)" : ""
        return "- \(item.name): \(formatQuantity(item.quantity)) \(item.unit)\(status), rata-rata \(rupiah(item.costPerUnit))/\(item.unit)"
    }

    /// Case/diacritic-insensitive form used for all name matching. Shared
    /// with `SalesKnowledge`.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rupiah(_ value: Double) -> String {
        value.formatted(.currency(code: "IDR").precision(.fractionLength(0)))
    }

}
