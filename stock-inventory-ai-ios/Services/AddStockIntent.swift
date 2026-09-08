//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents
import SwiftUI

/// Adds stock entirely through Siri's own conversational UI, without opening
/// the app — `openAppWhenRun` is false, so this runs in the background and
/// every step (asking how many items, each item's phrase, each item's cost)
/// happens as a Siri voice turn via `requestValue`, with a small snippet
/// card shown alongside the final confirmation per Apple's HIG guidance for
/// App Intents snippets (a glanceable visual reinforcing what the dialog
/// says, not a mini in-app UI).
///
/// Bounded to `maxItems` per invocation since AppIntents has no supported
/// API for an open-ended "keep asking until the user says done" loop:
/// `@Parameter` turns are resolved one at a time, not repeatably for an
/// unknown count, so the intent asks up front how many items there are and
/// resolves exactly that many phrase/cost pairs. Saying "Add Stock" again
/// starts a fresh batch.
struct AddStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Stock"
    static var description = IntentDescription("Adds stock items by voice, without opening Invent.")
    static var openAppWhenRun = false

    static let maxItems = 5

    @Parameter(title: "How many items?", requestValueDialog: "How many items are you adding?")
    var itemCount: Int

    @Parameter(title: "Item 1")
    var item1Phrase: String?
    @Parameter(title: "Item 1 cost")
    var item1Cost: Double?

    @Parameter(title: "Item 2")
    var item2Phrase: String?
    @Parameter(title: "Item 2 cost")
    var item2Cost: Double?

    @Parameter(title: "Item 3")
    var item3Phrase: String?
    @Parameter(title: "Item 3 cost")
    var item3Cost: Double?

    @Parameter(title: "Item 4")
    var item4Phrase: String?
    @Parameter(title: "Item 4 cost")
    var item4Cost: Double?

    @Parameter(title: "Item 5")
    var item5Phrase: String?
    @Parameter(title: "Item 5 cost")
    var item5Cost: Double?

    private let llm = LLMService()

    func perform() async throws -> some IntentResult & ShowsSnippetView & ProvidesDialog {
        let count = min(max(itemCount, 1), Self.maxItems)
        var added: [(itemName: String, quantity: Double, unit: String, totalCost: Double)] = []

        for index in 1...count {
            let phrase = try await resolvePhrase(at: index)
            let parsed = try await llm.parseStockPhrase(phrase)
            let cost = try await resolveCost(at: index, itemName: parsed.itemName)
            added.append((itemName: parsed.itemName, quantity: parsed.quantity, unit: parsed.unit, totalCost: cost))
        }

        StockStore.add(added)

        let summary = added
            .map { "\(formatQuantity($0.quantity)) \($0.unit) \($0.itemName)" }
            .joined(separator: ", ")

        return .result(
            dialog: "Added \(summary) to stock.",
            view: AddedStockSnippetView(items: added)
        )
    }

    /// Resolves the free-text phrase parameter at `index`, prompting via
    /// Siri for exactly that slot rather than relying on pre-perform
    /// resolution — `perform()` only knows how many slots are actually
    /// needed once `itemCount` itself has been resolved. Each case is
    /// written out (rather than a shared keyed helper) since `@Parameter`'s
    /// projected value is an `IntentParameter<Value>`, not a settable
    /// keypath-addressable property, so there's no generic way to pick one
    /// by index.
    private func resolvePhrase(at index: Int) async throws -> String {
        let nextPrompt = index == 1 ? "What's the first item?" : "What's the next item?"
        switch index {
        case 1:
            if let existing = item1Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item1Phrase.requestValue(IntentDialog(stringLiteral: nextPrompt))
        case 2:
            if let existing = item2Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item2Phrase.requestValue(IntentDialog(stringLiteral: nextPrompt))
        case 3:
            if let existing = item3Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item3Phrase.requestValue(IntentDialog(stringLiteral: nextPrompt))
        case 4:
            if let existing = item4Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item4Phrase.requestValue(IntentDialog(stringLiteral: nextPrompt))
        default:
            if let existing = item5Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item5Phrase.requestValue(IntentDialog(stringLiteral: nextPrompt))
        }
    }

    private func resolveCost(at index: Int, itemName: String) async throws -> Double {
        let dialog = IntentDialog(stringLiteral: "What's the total cost for the \(itemName)?")
        switch index {
        case 1:
            if let existing = item1Cost, existing > 0 { return existing }
            return try await $item1Cost.requestValue(dialog)
        case 2:
            if let existing = item2Cost, existing > 0 { return existing }
            return try await $item2Cost.requestValue(dialog)
        case 3:
            if let existing = item3Cost, existing > 0 { return existing }
            return try await $item3Cost.requestValue(dialog)
        case 4:
            if let existing = item4Cost, existing > 0 { return existing }
            return try await $item4Cost.requestValue(dialog)
        default:
            if let existing = item5Cost, existing > 0 { return existing }
            return try await $item5Cost.requestValue(dialog)
        }
    }

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Glanceable confirmation card shown alongside the final result dialog, per
/// Apple's HIG for App Intents snippets: reinforce what the spoken dialog
/// already says with a short, non-scrolling list — not a mini app screen.
struct AddedStockSnippetView: View {
    let items: [(itemName: String, quantity: Double, unit: String, totalCost: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Added to Stock", systemImage: "shippingbox.fill")
                .font(.headline)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text("\(formatQuantity(item.quantity)) \(item.unit) \(item.itemName)")
                        .font(.subheadline)
                    Spacer()
                    if item.totalCost > 0 {
                        Text(formatQuantity(item.totalCost))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

struct StockAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddStockIntent(),
            phrases: [
                "Add stock in \(.applicationName)",
                "Add stock using \(.applicationName)",
                "Add stock in grams in \(.applicationName)",
                "Add stock in kilograms in \(.applicationName)",
                "Add stock in liters in \(.applicationName)",
                "Add stock in pieces in \(.applicationName)",
                "Add stock in boxes in \(.applicationName)",
                "I want to add stock in \(.applicationName)",
                "I'd like to add stock to \(.applicationName)",
                "Help me add stock in \(.applicationName)",
                "Please add stock in \(.applicationName)"
            ],
            shortTitle: "Add Stock",
            systemImageName: "shippingbox.fill"
        )
    }
}
