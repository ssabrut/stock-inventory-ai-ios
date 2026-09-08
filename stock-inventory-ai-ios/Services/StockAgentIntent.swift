//
//  StockAgentIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents
import SwiftUI

/// Which action the user wants — its own `AppEnum` (rather than a free-text
/// parameter) specifically so it can bind directly into an `AppShortcut`
/// phrase: Siri's phrase matching only supports inline parameter capture
/// for a finite, enumerable set of values (enums, `AppEntity` lookups), not
/// arbitrary free text. That's what makes "Check stock in Invent" resolve
/// in one turn — the phrase itself carries the enum case, no follow-up ask
/// needed for *which* action.
enum StockAction: String, AppEnum {
    /// No pinned action — the generic "Ask Invent" entry point. Currently
    /// disabled (see `StockAgentIntent`'s doc comment) along with
    /// updateStock/deleteStock, since all LLM-routed handling has been
    /// removed.
    case ask
    case checkStock
    case addStock
    case updateStock
    case deleteStock

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stock Action"

    static var caseDisplayRepresentations: [StockAction: DisplayRepresentation] = [
        .ask: "Ask",
        .checkStock: "Check Stock",
        .addStock: "Add Stock",
        .updateStock: "Update Stock",
        .deleteStock: "Delete Stock"
    ]
}

/// Single Siri entry point for stock actions. `action` (see `StockAction`)
/// is resolved directly from the triggering phrase, so "Check stock in
/// Invent" is one turn end-to-end — checkStock needs no further detail and
/// runs immediately against StockStore.
///
/// All LLM-based parsing/tool-calling (LLMService, ToolRegistry,
/// AddStockTool, StockPhraseParser) has been removed from this intent.
/// `addStock` is now a pure transcript collector: it loops asking for the
/// next item, confirms each raw Siri transcription with a spoken "Is that
/// correct?" yes/no (see `confirmTranscript` — a "No" lets the user
/// re-speak the item rather than losing it), then shows the whole
/// accumulated list in a final snippet. No parsing into name/quantity/price
/// and no StockStore write yet — a placeholder for whatever replaces the
/// LLM parse step. `updateStock`/`deleteStock`/`ask` remain disabled, since
/// they had no non-LLM path.
///
/// `openAppWhenRun` is false: with the LLM gone there's no GPU-bound work
/// left in this intent (that was the only reason it used to force the app
/// to the foreground — MLX/Metal inference can't reliably run in a
/// background App Intent context), so it can run like checkStock does.
struct StockAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Invent"
    static var description = IntentDescription("Check or add stock by voice.")
    static var openAppWhenRun = false

    @Parameter(title: "Action")
    var action: StockAction

    /// Free-text detail for addStock — unused for checkStock, which needs
    /// no further detail to run.
    @Parameter(title: "Details")
    var detailPhrase: String?

    /// Backing parameter for the per-item "Is that correct?" yes/no in
    /// `confirmTranscript` — kept separate from `detailPhrase` since both
    /// are live across the same loop iteration (the disambiguation answer
    /// and the free-text item phrase are conceptually different things).
    @Parameter(title: "Confirm")
    var confirmChoice: String?

    init() {
        self.action = .ask
    }

    /// Used by `StockAppShortcuts` to pin a specific action per `AppShortcut`
    /// entry — Siri's phrase matching can't bind a free-text parameter
    /// inline, but a fixed enum value baked into the shortcut itself lets
    /// each phrase group ("Check stock in Invent" vs "Add stock in Invent")
    /// resolve straight to its action with no follow-up ask for *which* one.
    init(action: StockAction) {
        self.action = action
    }

    /// Required for `requestValue` to actually present its prompt on
    /// iOS 18+: a parameter not listed here fails silently (throws a
    /// connection-interrupted error instead of prompting) even though it's
    /// declared with `@Parameter` — this is a known AppIntents regression,
    /// not specific to this intent.
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) in Invent") {
            \.$detailPhrase
            \.$confirmChoice
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        if action == .checkStock {
            let entries = StockStore.all()
            return .result(
                dialog: IntentDialog(stringLiteral: checkStockResult(entries: entries)),
                view: StockSnippetView(entries: entries)
            )
        }

        if action == .addStock {
            let transcripts = try await collectTranscripts()
            return .result(
                dialog: IntentDialog(stringLiteral: "Got \(transcripts.count) item\(transcripts.count == 1 ? "" : "s")."),
                view: TranscriptSnippetView(transcripts: transcripts)
            )
        }

        return .result(
            dialog: IntentDialog(stringLiteral: "That's not available right now — try \"Check stock in Invent\" or \"Add stock in Invent\"."),
            view: StockSnippetView(entries: [])
        )
    }

    /// Stop words that end the transcript-collection loop — checked as a
    /// case-insensitive whole-utterance match (not a substring) so an item
    /// name that happens to contain one of these words (unlikely, but e.g.
    /// "stop sign") doesn't accidentally end the loop early.
    private static let doneWords: Set<String> = ["done", "stop", "that's all", "that is all", "selesai", "sudah", "cukup"]

    private static func isDoneWord(_ phrase: String) -> Bool {
        doneWords.contains(phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Free-N transcript-collection loop: keep asking "next item, or say
    /// done" and appending each raw Siri transcription to the list until the
    /// user's reply matches a stop word (see `isDoneWord`) — no LLM parsing,
    /// no StockStore write, just the transcribed text collected for display.
    /// Each item goes through `confirmTranscript` before being added, so a
    /// misheard item gets corrected on the spot rather than carried through
    /// to the final list.
    private func collectTranscripts() async throws -> [String] {
        var transcripts: [String] = []
        var askPrompt = "What's the first item? Say the name and quantity, or say \"done\" if you're finished."

        while true {
            let phrase = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: askPrompt))
            detailPhrase = nil
            #if DEBUG
            print("[StockAgentIntent] Siri transcription: \"\(phrase)\"")
            #endif

            if Self.isDoneWord(phrase) {
                #if DEBUG
                print("[StockAgentIntent] collectTranscripts finished — total items collected: \(transcripts.count)")
                #endif
                break
            }

            guard let confirmed = try await confirmTranscript(phrase, itemNumber: transcripts.count + 1) else {
                #if DEBUG
                print("[StockAgentIntent] collectTranscripts finished (done said during correction) — total items collected: \(transcripts.count)")
                #endif
                break
            }
            transcripts.append(confirmed)
            #if DEBUG
            print("[StockAgentIntent] collectTranscripts collected item \(transcripts.count): \"\(confirmed)\"")
            #endif

            askPrompt = "Got it. What's the next item, or say \"done\"?"
        }

        return transcripts
    }

    private static let yesChoice = "Yes, that's correct"
    private static let noChoice = "No, let me fix it"

    /// Asks "<transcript>. Is that correct?" with an explicit Yes/No choice
    /// via `requestDisambiguation` — deliberately *not*
    /// `requestConfirmation`, which was tried here first: its decline path
    /// throws an error that Apple's own docs say "shouldn't be caught," and
    /// in practice that throw tears down the whole intent rather than
    /// something `do/catch` inside `perform()` gets a chance to intercept,
    /// so a "No" ended the entire add session instead of letting the user
    /// correct one item. `requestDisambiguation` returns the chosen string
    /// as a normal value with no special throw/cancel semantics, so "No"
    /// here reliably loops back to re-asking instead.
    ///
    /// Returns `nil` if the user says a stop word (see `isDoneWord`) while
    /// re-speaking after a "No" — `collectTranscripts`'s outer loop only
    /// checks for that on its own initial ask, so this step needs its own
    /// check to let "done" end the session mid-correction too, rather than
    /// being swallowed as a literal item name.
    private func confirmTranscript(_ phrase: String, itemNumber: Int) async throws -> String? {
        confirmChoice = nil
        let choice = try await $confirmChoice.requestDisambiguation(
            among: [Self.yesChoice, Self.noChoice],
            dialog: IntentDialog(stringLiteral: "Item \(itemNumber): \(phrase). Is that correct?")
        )

        guard choice == Self.noChoice else {
            return phrase
        }

        #if DEBUG
        print("[StockAgentIntent] item \(itemNumber) rejected: \"\(phrase)\" — asking user to re-speak")
        #endif
        let corrected = try await $detailPhrase.requestValue(
            IntentDialog(stringLiteral: "Sorry — please say the correct item name and quantity, or say \"done\" to stop.")
        )
        detailPhrase = nil

        if Self.isDoneWord(corrected) {
            return nil
        }
        return try await confirmTranscript(corrected, itemNumber: itemNumber)
    }

    /// Spoken summary for checkStock, built from the same `entries` snapshot
    /// passed to `StockSnippetView` — one `StockStore.all()` fetch covers
    /// both the dialog and the visual snippet.
    private func checkStockResult(entries: [StockEntry]) -> String {
        guard !entries.isEmpty else { return "Inventory is empty." }
        return entries
            .map { "\($0.itemName): \(formatQuantity($0.quantity)) \($0.unit)" }
            .joined(separator: "\n")
    }
}

/// Final snippet for the whole addStock session — every raw transcription
/// collected in `StockAgentIntent.collectTranscripts`, listed in the order
/// they were heard.
struct TranscriptSnippetView: View {
    let transcripts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Items Heard", systemImage: "waveform")
                .font(.headline)

            if transcripts.isEmpty {
                Text("No items heard.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(transcripts.enumerated()), id: \.offset) { index, transcript in
                    Text("\(index + 1). \(transcript)")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

/// Visual snippet shown alongside checkStock's spoken dialog in the Siri /
/// Shortcuts UI — the spoken reply already covers the numbers, this gives
/// the user something to glance at (and scroll, if there are many items)
/// instead of only hearing them. Kept intentionally simple: no images,
/// icons only, since a Siri snippet has limited real estate.
struct StockSnippetView: View {
    let entries: [StockEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current Stock", systemImage: "shippingbox.fill")
                .font(.headline)

            if entries.isEmpty {
                Text("No stock entries yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries.prefix(5)) { entry in
                    HStack {
                        Text(entry.itemName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(entry.quantity.formatted()) \(entry.unit)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if entries.count > 5 {
                    Text("+ \(entries.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

struct StockAppShortcuts: AppShortcutsProvider {
    /// Each pinned-action shortcut bakes its `action` into the intent
    /// itself (via `StockAgentIntent(action:)`) rather than relying on
    /// phrase-parameter binding — Siri can't bind a free-text parameter
    /// inline, and a 5-case enum reads more naturally as separate literal
    /// phrase groups than as `\(\.$action)` substitution. That's what lets
    /// "Check stock in Invent" resolve in one turn straight to checkStock,
    /// no follow-up ask for *which* action. The final entry (default
    /// `init()`, action = .ask) is the open-ended fallback for any phrasing
    /// not covered by the pinned ones — currently disabled, see
    /// `StockAgentIntent.perform`.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StockAgentIntent(action: .checkStock),
            phrases: [
                "\(.applicationName) check stock",
                "Check stock in \(.applicationName)",
                "Check stock on \(.applicationName)",
                "Check my stock in \(.applicationName)",
                "Check my stock on \(.applicationName)",
                "How much stock do I have in \(.applicationName)",
                "How much stock do I have on \(.applicationName)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "shippingbox.fill"
        )
        AppShortcut(
            intent: StockAgentIntent(action: .addStock),
            phrases: [
                "\(.applicationName) add stock",
                "Add stock in \(.applicationName)",
                "Add stock on \(.applicationName)",
                "Add stock using \(.applicationName)",
                "I want to add stock in \(.applicationName)",
                "I want to add stock on \(.applicationName)"
            ],
            shortTitle: "Add Stock",
            systemImageName: "shippingbox.fill"
        )
        AppShortcut(
            intent: StockAgentIntent(action: .updateStock),
            phrases: [
                "\(.applicationName) update stock",
                "Update stock in \(.applicationName)",
                "Update stock on \(.applicationName)"
            ],
            shortTitle: "Update Stock",
            systemImageName: "shippingbox.fill"
        )
        AppShortcut(
            intent: StockAgentIntent(action: .deleteStock),
            phrases: [
                "\(.applicationName) delete stock",
                "Delete stock in \(.applicationName)",
                "Delete stock on \(.applicationName)"
            ],
            shortTitle: "Delete Stock",
            systemImageName: "shippingbox.fill"
        )
        AppShortcut(
            intent: StockAgentIntent(),
            phrases: [
                "Ask \(.applicationName)"
            ],
            shortTitle: "Ask Invent",
            systemImageName: "shippingbox.fill"
        )
    }
}
