//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents
import SwiftUI

/// Adds stock entirely through Siri's own conversational UI, without opening
/// the app — `openAppWhenRun` is false, so this runs in the background and
/// every step happens as a Siri voice turn.
///
/// Flow: ask how many items, then for each item resolve its phrase + cost
/// and show a running-list snippet asking "is that right?" (reject re-asks
/// that same item). Once every item is confirmed, show a full-list review
/// snippet asking "is this correct?" — reject asks which item number is
/// wrong, re-resolves just that item, and reviews again. Only a final "yes"
/// commits to StockStore.
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

    /// Which item number the user says is wrong during the final review —
    /// a plain @Parameter so it can be re-asked via requestValue each time
    /// review is rejected, then reset to nil so a later rejection re-prompts
    /// instead of silently reusing a stale index.
    @Parameter(title: "Which item is wrong?")
    var correctionIndex: Int?

    /// Backing parameter for every yes/no confirm point (per-item and final
    /// review), resolved via requestDisambiguation rather than
    /// requestConfirmation: requestConfirmation's rejection path is a thrown
    /// cancellation Apple's own guidance says to let propagate and end
    /// perform() outright, which doesn't fit a flow that needs to loop back
    /// and ask a follow-up on rejection. Disambiguation instead hands back
    /// the chosen string directly, so "no" can be branched on normally.
    @Parameter(title: "Confirm")
    var confirmChoice: String?

    private static let yesChoice = "Yes, that's correct"
    private static let noChoice = "No, something's wrong"

    func perform() async throws -> some IntentResult & ShowsSnippetView & ProvidesDialog {
        let count = min(max(itemCount, 1), Self.maxItems)
        var items: [PendingItem] = []

        for index in 1...count {
            let item = try await resolveItem(at: index, forceReask: false)
            items.append(item)

            var isCorrect = try await confirmYesNo(
                dialog: "\(item.bulletLine) — is that right?",
                items: items,
                highlightLast: true
            )
            while !isCorrect {
                let corrected = try await resolveItem(at: index, forceReask: true)
                items[items.count - 1] = corrected
                isCorrect = try await confirmYesNo(
                    dialog: "\(corrected.bulletLine) — is that right?",
                    items: items,
                    highlightLast: true
                )
            }

            // Show the running list before asking for the next item — skipped
            // after the last item since reviewUntilConfirmed shows the same
            // list again right away.
            if index < count {
                try? await requestConfirmation(
                    actionName: .continue,
                    snippetIntent: StockListSnippetIntent(items: items, dialog: "Got it. Ready for the next item?")
                )
            }
        }

        try await reviewUntilConfirmed(items: &items)

        StockStore.add(items.map { (itemName: $0.itemName, quantity: $0.quantity, unit: $0.unit, totalCost: $0.totalCost) })

        let summary = items.map(\.summary).joined(separator: ", ")
        return .result(
            dialog: "Added \(summary) to stock.",
            view: AddedStockSnippetView(items: items, highlightLast: false)
        )
    }

    /// Shows the full list as a snippet and asks "is this correct?" via
    /// `requestConfirmation(actionName:snippetIntent:)` — the only API that
    /// pairs a visible snippet with a yes/no gate (`requestDisambiguation`
    /// used elsewhere in this flow has no `view:` parameter). Apple's
    /// guidance is to let that call's rejection (a thrown cancellation)
    /// propagate and end `perform()`, but that doesn't fit needing to loop
    /// back and ask a follow-up, so it's caught here instead: on rejection,
    /// ask which item number is wrong, re-resolve just that one, and review
    /// the full list again until confirmed.
    private func reviewUntilConfirmed(items: inout [PendingItem]) async throws {
        while true {
            do {
                try await requestConfirmation(
                    actionName: .continue,
                    snippetIntent: StockListSnippetIntent(items: items, dialog: "Here's everything — is this correct?")
                )
                return
            } catch is CancellationError {
                correctionIndex = nil
                let rawIndex = try await $correctionIndex.requestValue(
                    IntentDialog(stringLiteral: "Which item number is wrong?")
                )
                let index = min(max(rawIndex, 1), items.count)
                let corrected = try await resolveItem(at: index, forceReask: true)
                items[index - 1] = corrected
            }
        }
    }

    /// Asks a yes/no question via disambiguation (see `confirmChoice`),
    /// showing the current item list as a snippet alongside it, and returns
    /// whether the user picked "yes". Resets `confirmChoice` first so a
    /// stale prior answer can't be reused instead of asking again.
    private func confirmYesNo(dialog: String, items: [PendingItem], highlightLast: Bool) async throws -> Bool {
        confirmChoice = nil
        let choice = try await $confirmChoice.requestDisambiguation(
            among: [Self.yesChoice, Self.noChoice],
            dialog: IntentDialog(stringLiteral: dialog)
        )
        return choice == Self.yesChoice
    }

    /// Resolves a single item's phrase + cost. With `forceReask`, ignores
    /// any already-resolved value and re-prompts — used both for a rejected
    /// per-item confirm and for a targeted correction from the final review.
    ///
    /// Item name comes straight from Siri's own transcription (via
    /// StockPhraseParser's deterministic qty/unit extraction) rather than an
    /// LLM cleanup pass — the on-device LLM was hallucinating item names
    /// here, and Siri's STT + the existing unit dictionary is enough to get
    /// a usable name without it.
    private func resolveItem(at index: Int, forceReask: Bool) async throws -> PendingItem {
        let phrase = try await resolvePhrase(at: index, forceReask: forceReask)
        let parsed = StockPhraseParser.parse(phrase)
        let itemName = Self.itemName(from: parsed.remainingText)
        let cost = try await resolveCost(at: index, itemName: itemName, forceReask: forceReask)
        return PendingItem(itemName: itemName, quantity: parsed.quantity, unit: parsed.unit, totalCost: cost)
    }

    /// Strips common leading filler words ("of", "for", "the", "a", "an")
    /// left over after StockPhraseParser removes the quantity+unit span,
    /// e.g. "of chicken wings" -> "chicken wings". Falls back to the
    /// untrimmed text if stripping would leave nothing.
    private static let leadingFillerWords: Set<String> = ["of", "for", "the", "a", "an"]

    private static func itemName(from remainingText: String) -> String {
        var words = remainingText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        while let first = words.first, leadingFillerWords.contains(first.lowercased()) {
            words.removeFirst()
        }

        let cleaned = words.joined(separator: " ")
        return cleaned.isEmpty ? remainingText.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    /// Resolves the free-text phrase parameter at `index`, prompting via
    /// Siri for exactly that slot. Each case is written out (rather than a
    /// shared keyed helper) since `@Parameter`'s projected value is an
    /// `IntentParameter<Value>`, not a settable keypath-addressable
    /// property, so there's no generic way to pick one by index.
    private func resolvePhrase(at index: Int, forceReask: Bool) async throws -> String {
        let prompt = forceReask
            ? "Say the correct item."
            : (index == 1 ? "What's the first item?" : "What's the next item?")
        let dialog = IntentDialog(stringLiteral: prompt)

        switch index {
        case 1:
            if !forceReask, let existing = item1Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item1Phrase.requestValue(dialog)
        case 2:
            if !forceReask, let existing = item2Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item2Phrase.requestValue(dialog)
        case 3:
            if !forceReask, let existing = item3Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item3Phrase.requestValue(dialog)
        case 4:
            if !forceReask, let existing = item4Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item4Phrase.requestValue(dialog)
        default:
            if !forceReask, let existing = item5Phrase, !existing.trimmingCharacters(in: .whitespaces).isEmpty { return existing }
            return try await $item5Phrase.requestValue(dialog)
        }
    }

    private func resolveCost(at index: Int, itemName: String, forceReask: Bool) async throws -> Double {
        let dialog = IntentDialog(stringLiteral: "What's the total cost for the \(itemName)?")
        switch index {
        case 1:
            if !forceReask, let existing = item1Cost, existing > 0 { return existing }
            return try await $item1Cost.requestValue(dialog)
        case 2:
            if !forceReask, let existing = item2Cost, existing > 0 { return existing }
            return try await $item2Cost.requestValue(dialog)
        case 3:
            if !forceReask, let existing = item3Cost, existing > 0 { return existing }
            return try await $item3Cost.requestValue(dialog)
        case 4:
            if !forceReask, let existing = item4Cost, existing > 0 { return existing }
            return try await $item4Cost.requestValue(dialog)
        default:
            if !forceReask, let existing = item5Cost, existing > 0 { return existing }
            return try await $item5Cost.requestValue(dialog)
        }
    }
}

/// One resolved item awaiting confirmation/commit — mutable stand-in for
/// StockStore's add() tuple so a correction can overwrite a single slot in
/// the in-progress `items` array by index.
struct PendingItem: Sendable {
    let itemName: String
    let quantity: Double
    let unit: String
    let totalCost: Double

    var summary: String {
        let quantityText = quantity == quantity.rounded() ? String(Int(quantity)) : String(quantity)
        return "\(quantityText) \(unit) of \(itemName)"
    }

    /// Matches the "Rp"-prefixed currency formatting used elsewhere in the
    /// app (see HistoryScreen) rather than a bare number.
    var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: totalCost as NSNumber) ?? "Rp0"
    }

    /// e.g. "50 gr of chicken wings - Rp150,000" — the bullet-point line
    /// shown in the running-list snippet between items.
    var bulletLine: String {
        totalCost > 0 ? "\(summary) - \(formattedCost)" : summary
    }
}

/// Glanceable confirmation card shown alongside each confirm/review dialog,
/// per Apple's HIG for App Intents snippets: reinforce what's being spoken
/// with a short, non-scrolling list — not a mini app screen. `highlightLast`
/// marks the item currently being confirmed (true during the per-item loop,
/// false once reviewing/finalizing the whole list).
struct AddedStockSnippetView: View {
    let items: [PendingItem]
    let highlightLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stock Items", systemImage: "shippingbox.fill")
                .font(.headline)

            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack {
                    Text("\(offset + 1). \(item.summary)")
                        .font(.subheadline)
                        .fontWeight(highlightLast && offset == items.count - 1 ? .semibold : .regular)
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

/// Shown by `requestConfirmation(actionName:snippetIntent:)` both between
/// items (running list so far) and at the final review — a `SnippetIntent`
/// refines `AppIntent`, so it needs a plain `init()` and its data-carrying
/// properties must be `@Parameter` (only String/Int/Double/AppEntity-ish
/// types qualify, not an arbitrary array of a custom struct — a raw
/// `[PendingItem]` property failed AppIntent conformance). The item list is
/// pre-formatted into one newline-joined, bullet-point `summaryText` string
/// instead, set right after construction, so the snippet view just renders
/// it as text lines rather than styled per-row rows. The spoken dialog is
/// carried on the snippet intent itself (not the outer requestConfirmation
/// call) since that's where `ShowsSnippetView`'s `.result(dialog:view:)`
/// lives.
struct StockListSnippetIntent: SnippetIntent {
    static var title: LocalizedStringResource = "Stock Items"

    @Parameter(title: "Summary")
    var summaryText: String
    @Parameter(title: "Dialog")
    var dialogText: String

    init() {}

    init(items: [PendingItem], dialog: String) {
        self.summaryText = items.map { "• \($0.bulletLine)" }.joined(separator: "\n")
        self.dialogText = dialog
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: dialogText), view: ReviewStockSnippetView(summaryText: summaryText))
    }
}

/// Renders `StockListSnippetIntent`'s pre-formatted, newline-joined bullet
/// list as plain text lines — a `SnippetIntent`'s data must travel through
/// an `@Parameter` String rather than a typed array (see
/// `StockListSnippetIntent`), so this view has no per-row styling to work
/// with, just the text.
struct ReviewStockSnippetView: View {
    let summaryText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stock Items", systemImage: "shippingbox.fill")
                .font(.headline)

            Text(summaryText)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
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
