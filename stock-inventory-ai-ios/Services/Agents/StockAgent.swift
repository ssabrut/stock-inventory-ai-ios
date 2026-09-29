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
    case clarify(Clarification)         // name matches several items — user picks
}

/// Asked when a name matches several stock items ("gula" → Gula, Gula Halus).
/// Holds the plan so the pick resumes it in code; the model never has to
/// re-read the conversation to work out what the answer referred to.
struct Clarification {
    let question: String
    let options: [String]
    /// The request to resume — pass back to `StockAgent.execute` with the
    /// updated `picks(choosing:)`.
    let plan: StockPlan
    let userText: String
    fileprivate let itemIndex: Int
    fileprivate let picks: [String: String]

    /// Picks made so far in this request plus this one, keyed by the name as
    /// the plan wrote it ("gula" → "gula halus").
    func picks(choosing choice: String) -> [String: String] {
        var picks = picks
        picks[plan.items[itemIndex]] = StockKnowledge.normalize(choice)
        return picks
    }

    /// Maps a typed reply to one option: its number ("2"), its full name
    /// ("gula halus"), or a word only that option has ("yang halus").
    /// Nil when unclear — the text is then treated as a new request.
    func match(_ text: String) -> String? {
        let typed = StockKnowledge.normalize(text)
        if let number = Int(typed), options.indices.contains(number - 1) { return options[number - 1] }
        if let exact = options.first(where: { StockKnowledge.normalize($0) == typed }) { return exact }

        let typedWords = Set(StockKnowledge.words(typed))
        let optionWords = options.map { Set(StockKnowledge.words(StockKnowledge.normalize($0))) }
        let hits = options.indices.filter { index in
            let othersWords = optionWords.indices.filter { $0 != index }.reduce(into: Set<String>()) { $0.formUnion(optionWords[$1]) }
            return !optionWords[index].subtracting(othersWords).isDisjoint(with: typedWords)
        }
        return hits.count == 1 ? options[hits[0]] : nil
    }
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
    let date: Date

    var summary: String {
        switch kind {
        case .add:
            let cost = totalCost.formatted(.currency(code: "IDR").precision(.fractionLength(0)))
            let day = date.formatted(date: .abbreviated, time: .omitted)
            return "Tambah \(formatQuantity(quantity)) \(unit) \(itemName) seharga \(cost), dibeli \(day)" + (isNewItem ? " (bahan baru)" : "")
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
    /// small model can still emit "stok" as an item, a negative amount, or a
    /// price copied from its few-shot examples. Clean those up in code, and
    /// keep only numbers that actually appear in what the user typed.
    func sanitized(userText: String) -> StockPlan {
        var plan = self
        var seen = Set<String>()
        plan.items = items
            .map { StockKnowledge.normalize($0) }
            .filter { !$0.isEmpty && !Self.nonItemWords.contains($0) && seen.insert($0).inserted }
        plan.quantity = quantity > 0 && MessageFacts.mentions(quantity, in: userText) ? quantity : 0
        plan.totalCost = totalCost > 0 && MessageFacts.mentions(totalCost, in: userText) ? totalCost : 0
        plan.days = min(max(days, 1), 365)
        return plan
    }
}

/// Code-driven agent: the model only extracts a `StockPlan`; everything
/// that has to be correct — lookups, validation, writes — happens here.
struct StockAgent {
    let context: ModelContext

    /// `userText` is everything the user wrote for this request (earlier
    /// answers included) — the ground truth the plan is checked against.
    /// `picks` maps names the user already disambiguated in this request to
    /// the item they chose, so follow-up turns don't ask again.
    func execute(_ rawPlan: StockPlan, userText: String, picks: [String: String] = [:]) throws -> AgentOutcome {
        var plan = rawPlan.sanitized(userText: userText)
        var seen = Set<String>()
        plan.items = plan.items.map { picks[$0] ?? $0 }.filter { seen.insert($0).inserted }

        switch plan.intent {
        case .checkStock:
            guard !plan.items.isEmpty else { return .facts(try StockKnowledge.list(onlyEmpty: false, in: context)) }
            var lines: [String] = []
            for index in plan.items.indices {
                switch try lookup(plan, at: index, userText: userText, picks: picks) {
                case .item(let item): lines.append(StockKnowledge.describe(item))
                case .missing: lines.append(try StockKnowledge.search(plan.items[index], in: context))
                case .ask(let clarification): return .clarify(clarification)
                }
            }
            return .facts(lines.joined(separator: "\n"))
        case .listStock:
            return .facts(try StockKnowledge.list(onlyEmpty: false, in: context))
        case .outOfStock:
            return .facts(try StockKnowledge.list(onlyEmpty: true, in: context))
        case .history:
            guard !plan.items.isEmpty else {
                return .facts(try StockKnowledge.history(itemName: "", days: plan.days, in: context))
            }
            var parts: [String] = []
            for index in plan.items.indices {
                switch try lookup(plan, at: index, userText: userText, picks: picks) {
                case .item(let item):
                    parts.append(try StockKnowledge.history(itemName: item.name, days: plan.days, exactName: true, in: context))
                case .missing:
                    // May be a deleted item — its transactions outlive it.
                    parts.append(try StockKnowledge.history(itemName: plan.items[index], days: plan.days, in: context))
                case .ask(let clarification):
                    return .clarify(clarification)
                }
            }
            return .facts(parts.joined(separator: "\n"))
        case .addStock:
            return try propose(plan, kind: .add, userText: userText, picks: picks)
        case .useStock:
            return try propose(plan, kind: .use, userText: userText, picks: picks)
        case .other:
            return .facts("")
        }
    }

    private enum Lookup {
        case item(StockItem)
        case missing(suggestions: [String])
        case ask(Clarification)
    }

    /// Resolves `plan.items[index]`; several matches become a clarification
    /// that resumes this same plan once the user picks.
    private func lookup(_ plan: StockPlan, at index: Int, userText: String, picks: [String: String]) throws -> Lookup {
        let name = plan.items[index]
        let alreadyPicked = picks.values.contains(name)
        switch try StockKnowledge.resolve(name, in: context, preferExact: alreadyPicked) {
        case .found(let item):
            return .item(item)
        case .notFound(let suggestions):
            return .missing(suggestions: suggestions)
        case .ambiguous(let names):
            let numbered = names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            return .ask(Clarification(
                question: "Ada beberapa bahan \"\(name)\". Maksudnya yang mana?\n\(numbered)",
                options: names, plan: plan, userText: userText, itemIndex: index, picks: picks
            ))
        }
    }

    private func propose(_ plan: StockPlan, kind: PendingStockAction.Kind, userText: String, picks: [String: String]) throws -> AgentOutcome {
        guard let rawName = plan.items.first else { return .reply("Bahan apa yang mau dicatat?") }
        guard plan.quantity > 0 else { return .reply("Berapa jumlah \(rawName) yang mau dicatat?") }
        let unit = StockKnowledge.normalizeUnit(plan.unit)
        // Planner's date phrase first; fall back to scanning the raw text in
        // case it missed one the user did write.
        let date = MessageFacts.purchaseDate(from: plan.dateText) ?? MessageFacts.purchaseDate(from: userText)

        switch try lookup(plan, at: 0, userText: userText, picks: picks) {
        case .ask(let clarification):
            return .clarify(clarification)

        case .item(let item):
            if !unit.isEmpty, unit != item.unit {
                return .reply("\(item.name) tercatat dalam \(item.unit). Sebutkan jumlahnya dalam \(item.unit) ya.")
            }
            if kind == .use {
                guard plan.quantity <= item.quantity else {
                    return .reply("Stok \(item.name) cuma \(formatQuantity(item.quantity)) \(item.unit).")
                }
                return .confirm(PendingStockAction(kind: .use, itemName: item.name, isNewItem: false,
                                                   quantity: plan.quantity, unit: item.unit, totalCost: 0, date: .now))
            }
            if let question = askMissing(plan, needsUnit: false, date: date, name: item.name, unit: item.unit) {
                return .reply(question)
            }
            return .confirm(PendingStockAction(kind: .add, itemName: item.name, isNewItem: false,
                                               quantity: plan.quantity, unit: item.unit, totalCost: plan.totalCost, date: date ?? .now))

        case .missing(let suggestions):
            if kind == .use {
                let hint = suggestions.isEmpty ? "" : " Mungkin maksudnya: \(suggestions.joined(separator: ", "))?"
                return .reply("Bahan \"\(rawName)\" belum tercatat.\(hint)")
            }
            if let question = askMissing(plan, needsUnit: unit.isEmpty, date: date, name: rawName, unit: unit) {
                return .reply(question)
            }
            return .confirm(PendingStockAction(kind: .add, itemName: rawName.capitalized, isNewItem: true,
                                               quantity: plan.quantity, unit: unit, totalCost: plan.totalCost, date: date ?? .now))
        }
    }

    /// Every purchase needs name, quantity, unit, total price and purchase
    /// date. Asks for everything still missing in one message, so the user
    /// isn't walked through one question per turn.
    private func askMissing(_ plan: StockPlan, needsUnit: Bool, date: Date?, name: String, unit: String) -> String? {
        var missing: [String] = []
        if needsUnit { missing.append("satuan (kg, gram, liter, ml, pcs, box, ikat)") }
        if plan.totalCost <= 0 { missing.append("total harga") }
        if date == nil { missing.append("tanggal beli (mis. hari ini, kemarin, 28/9)") }
        guard !missing.isEmpty else { return nil }
        let amount = [formatQuantity(plan.quantity), unit].filter { !$0.isEmpty }.joined(separator: " ")
        return "Untuk \(amount) \(name), sebutkan \(missing.joined(separator: " dan "))."
    }

    /// Runs only after the user taps Simpan.
    func commit(_ action: PendingStockAction) -> String {
        let store = StockStore(context: context)
        do {
            switch action.kind {
            case .add:
                try store.addStock(name: action.itemName, quantity: action.quantity, unit: action.unit, totalCost: action.totalCost, date: action.date)
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
