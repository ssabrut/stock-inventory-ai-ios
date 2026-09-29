//
//  StockAgent.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 29/09/26.
//

import Foundation
import SwiftData

enum AgentOutcome {
    case facts(String)                  // hand to the responder model
    case reply(String)                  // fixed reply, no model call
    case confirm(PendingStockAction)    // needs user tap before writing
}

struct PendingStockAction: Identifiable {
    enum Kind { case add, use }

    let id = UUID()
    let kind: Kind
    let itemName: String
    let isNewItem: Bool
    let quantity: Double
    let unit: String
    let totalCost: Double

    var summary: String {
        switch kind {
        case .add:
            let cost = totalCost.formatted(.currency(code: "IDR").precision(.fractionLength(0)))
            return "Tambah \(formatQuantity(quantity)) \(unit) \(itemName) seharga \(cost)" + (isNewItem ? " (bahan baru)" : "")
        case .use:
            return "Pakai \(formatQuantity(quantity)) \(unit) \(itemName)"
        }
    }
}

extension StockPlan {
    /// Words small models tend to copy into `items` that aren't ingredients.
    private static let nonItemWords: Set<String> = [
        "stok", "stock", "bahan", "barang", "semua", "apa", "aja", "saja", "yang", "sisa", "hpp",
    ]

    /// Guided generation guarantees the plan's *shape*, not its *meaning* — a
    /// small model can still emit "stok" as an item or a negative amount.
    /// Clean those up in code before anything acts on the plan.
    func sanitized() -> StockPlan {
        var plan = self
        var seen = Set<String>()
        plan.items = items
            .map { StockKnowledge.normalize($0) }
            .filter { !$0.isEmpty && !Self.nonItemWords.contains($0) && seen.insert($0).inserted }
        plan.quantity = max(0, quantity)
        plan.totalCost = max(0, totalCost)
        plan.days = min(max(days, 1), 365)
        return plan
    }
}

/// Code-driven agent: the model only extracts a `StockPlan`; everything
/// that has to be correct — lookups, validation, writes — happens here.
struct StockAgent {
    let context: ModelContext

    func execute(_ rawPlan: StockPlan) throws -> AgentOutcome {
        let plan = rawPlan.sanitized()
        switch plan.intent {
        case .checkStock:
            guard !plan.items.isEmpty else { return .facts(try StockKnowledge.list(onlyEmpty: false, in: context)) }
            return .facts(try plan.items.map { try StockKnowledge.search($0, in: context) }.joined(separator: "\n"))
        case .listStock:
            return .facts(try StockKnowledge.list(onlyEmpty: false, in: context))
        case .outOfStock:
            return .facts(try StockKnowledge.list(onlyEmpty: true, in: context))
        case .history:
            let names = plan.items.isEmpty ? [""] : plan.items
            return .facts(try names.map { try StockKnowledge.history(itemName: $0, days: plan.days, in: context) }.joined(separator: "\n"))
        case .addStock:
            return try propose(plan, kind: .add)
        case .useStock:
            return try propose(plan, kind: .use)
        case .other:
            return .facts("")
        }
    }

    private func propose(_ plan: StockPlan, kind: PendingStockAction.Kind) throws -> AgentOutcome {
        guard let rawName = plan.items.first else { return .reply("Bahan apa yang mau dicatat?") }
        guard plan.quantity > 0 else { return .reply("Berapa jumlah \(rawName) yang mau dicatat?") }
        let unit = StockKnowledge.normalizeUnit(plan.unit)

        switch try StockKnowledge.resolve(rawName, in: context) {
        case .ambiguous(let names):
            return .reply("Maksudnya yang mana: \(names.joined(separator: ", "))?")

        case .found(let item):
            if !unit.isEmpty, unit != item.unit {
                return .reply("\(item.name) tercatat dalam \(item.unit). Sebutkan jumlahnya dalam \(item.unit) ya.")
            }
            if kind == .use, plan.quantity > item.quantity {
                return .reply("Stok \(item.name) cuma \(formatQuantity(item.quantity)) \(item.unit).")
            }
            if kind == .add, plan.totalCost <= 0 {
                return .reply("Berapa total harga \(formatQuantity(plan.quantity)) \(item.unit) \(item.name)?")
            }
            return .confirm(PendingStockAction(kind: kind, itemName: item.name, isNewItem: false,
                                               quantity: plan.quantity, unit: item.unit, totalCost: plan.totalCost))

        case .notFound(let suggestions):
            if kind == .use {
                let hint = suggestions.isEmpty ? "" : " Mungkin maksudnya: \(suggestions.joined(separator: ", "))?"
                return .reply("Bahan \"\(rawName)\" belum tercatat.\(hint)")
            }
            guard !unit.isEmpty else { return .reply("Satuan \(rawName) apa? (kg, gram, liter, ml, pcs, box, ikat)") }
            guard plan.totalCost > 0 else { return .reply("Berapa total harga \(formatQuantity(plan.quantity)) \(unit) \(rawName)?") }
            return .confirm(PendingStockAction(kind: .add, itemName: rawName.capitalized, isNewItem: true,
                                               quantity: plan.quantity, unit: unit, totalCost: plan.totalCost))
        }
    }

    /// Runs only after the user taps Simpan.
    func commit(_ action: PendingStockAction) -> String {
        let store = StockStore(context: context)
        do {
            switch action.kind {
            case .add:
                try store.addStock(name: action.itemName, quantity: action.quantity, unit: action.unit, totalCost: action.totalCost)
            case .use:
                guard let item = try store.findItem(named: action.itemName) else { return "Gagal: \(action.itemName) tidak ditemukan." }
                try store.use(item, quantity: action.quantity, note: "Lewat Tanya AI")
            }
            return "Tercatat: \(action.summary)."
        } catch {
            return "Gagal: \(error.localizedDescription)"
        }
    }
}

