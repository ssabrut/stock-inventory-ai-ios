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
    /// updateStock/deleteStock — only addStock/checkStock have a working
    /// flow right now.
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
/// `addStock` collects items transcript-first, with no LLM involved until
/// the user has confirmed the whole batch:
/// 1. `collectTranscripts` loops asking for the next item, confirming each
///    raw Siri transcription with a spoken "Is that correct?" yes/no (see
///    `confirmTranscript` — a "No" lets the user re-speak the item rather
///    than losing it, "done" ends the loop).
/// 2. The whole accumulated list is shown in a summary snippet
///    (`TranscriptSnippetView`) with one final "Add all these?" yes/no gate
///    (see `confirmBatch`) — declining cancels the entire session with
///    nothing written.
/// 3. Only on "yes" does `parseAndAddItems` run each transcript through
///    `LLMService.agenticReply` (same JSON tool-call contract ChatScreen
///    uses) to extract name/quantity/unit/price, fill in whatever the
///    parse left missing with a targeted follow-up, then write via
///    `AddStockTool` (StockStore/Core Data).
///
/// `updateStock`/`deleteStock`/`ask` remain disabled — they had no
/// transcript-first equivalent built yet.
///
/// `openAppWhenRun` is true: MLX's on-device inference runs on the GPU via
/// Metal, which a background App Intent execution context can't reliably
/// host — iOS reclaims GPU access from a non-foreground process
/// mid-inference, which crashed here previously
/// (IOGPUCommandQueueSubmitCommandBuffers / iokit_user_client_trap).
/// Foregrounding the app gives `agenticReply` a normal process to run in,
/// same as ChatScreen. checkStock has no LLM step, so it stays fast even
/// though the intent as a whole opens the app for addStock's parse step.
struct StockAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Invent"
    static var description = IntentDescription("Check or add stock by voice.")
    static var openAppWhenRun = true

    @Parameter(title: "Action")
    var action: StockAction

    /// Free-text detail for addStock — unused for checkStock, which needs
    /// no further detail to run. Also carries the per-item "Is that
    /// correct?" reply in `confirmTranscript`, classified as yes/no by
    /// `YesNoClassifier` rather than a dedicated disambiguation parameter —
    /// see that method's doc comment for why.
    @Parameter(title: "Details")
    var detailPhrase: String?

    /// Bare-number reply to "what's the price?" when `AddStockTool` is
    /// missing one and has no fallback (see LLMService.resolvePriceReply)
    /// — a separate turn since the model has no memory of the original
    /// call across it.
    @Parameter(title: "What's the price?")
    var priceReply: String?

    private let llm = LLMService()

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
            \.$priceReply
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
            guard !transcripts.isEmpty else {
                return .result(
                    dialog: IntentDialog(stringLiteral: "Okay, no items added."),
                    view: TranscriptSnippetView(transcripts: [])
                )
            }

            guard try await confirmBatch(transcripts) else {
                return .result(
                    dialog: IntentDialog(stringLiteral: "Okay, cancelled. Nothing was added."),
                    view: TranscriptSnippetView(transcripts: transcripts)
                )
            }

            let resultText = try await parseAndAddItems(transcripts)
            return .result(
                dialog: IntentDialog(stringLiteral: resultText),
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

    /// Asks "<transcript>. Is that correct?" and classifies the free-text
    /// reply as yes/no via `YesNoClassifier` (on-device sentence embeddings,
    /// no LLM) instead of `requestDisambiguation`'s exact/fuzzy string
    /// matching — that approach was tried first and reliably hung on
    /// `requestDisambiguation`'s await when the user spoke a full natural
    /// phrase ("yes, that's correct") instead of the literal choice text;
    /// `requestValue` (free text) always resolves regardless of phrasing,
    /// so classification moves into our own code where we control the
    /// matching. An ambiguous reply (neither classified confidently) is
    /// treated as "no" and re-asked, rather than silently guessing.
    ///
    /// Returns `nil` if the user says a stop word (see `isDoneWord`) while
    /// re-speaking after a "No" — `collectTranscripts`'s outer loop only
    /// checks for that on its own initial ask, so this step needs its own
    /// check to let "done" end the session mid-correction too, rather than
    /// being swallowed as a literal item name.
    private func confirmTranscript(_ phrase: String, itemNumber: Int) async throws -> String? {
        let reply = try await $detailPhrase.requestValue(
            IntentDialog(stringLiteral: "Item \(itemNumber): \(phrase). Is that correct?")
        )
        detailPhrase = nil
        let classification = YesNoClassifier.classify(reply)
        #if DEBUG
        print("[StockAgentIntent] confirm reply: \"\(reply)\" — classified as \(classification)")
        #endif

        // Accept only on a confident .yes — .no and .unclear both fall
        // through to re-ask, since an unclassifiable reply shouldn't
        // silently accept a possibly-misheard item.
        guard classification != .yes else {
            return phrase
        }

        #if DEBUG
        print("[StockAgentIntent] item \(itemNumber) rejected: \"\(phrase)\" (reply classified \(classification)) — asking user to re-speak")
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

    /// Final batch-wide gate shown alongside the summary snippet: "here's
    /// everything I heard — add all these?" A "No"/unclear reply cancels
    /// the whole session with nothing written, matching the "no = cancel
    /// all" requirement — this runs before any LLM call, so declining here
    /// costs nothing beyond the transcript-collection turns already spent.
    /// Classification uses the same `YesNoClassifier` + `requestValue`
    /// pattern as `confirmTranscript`, for the same reason: a
    /// `requestDisambiguation` yes/no reliably hung on natural phrasing.
    private func confirmBatch(_ transcripts: [String]) async throws -> Bool {
        let listText = transcripts.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: ", ")
        let reply = try await $detailPhrase.requestValue(
            IntentDialog(stringLiteral: "Here's what I heard: \(listText). Add all \(transcripts.count) of these?")
        )
        detailPhrase = nil
        let classification = YesNoClassifier.classify(reply)
        #if DEBUG
        print("[StockAgentIntent] confirmBatch reply: \"\(reply)\" — classified as \(classification)")
        #endif
        return classification == .yes
    }

    /// Runs each confirmed transcript through `LLMService.agenticReply`
    /// (same JSON tool-call contract ChatScreen uses) to parse it into an
    /// add_stock call, fills in whatever the parse left missing with a
    /// targeted follow-up (mirrors the old pre-transcript-collector
    /// addStock flow), then writes via `AddStockTool` — this is the only
    /// point in the whole addStock flow that touches the LLM or
    /// StockStore, since the batch has already been confirmed once as a
    /// whole in `confirmBatch`.
    private func parseAndAddItems(_ transcripts: [String]) async throws -> String {
        var results: [String] = []

        for (index, transcript) in transcripts.enumerated() {
            let ordinal = index + 1
            #if DEBUG
            print("[StockAgentIntent] parseAndAddItems parsing item \(ordinal): \"\(transcript)\"")
            #endif

            // Framing it explicitly as an add request makes the intent
            // unambiguous — the bare utterance alone ("5kg of white
            // pepper") reads as ambiguous to a small model without a verb.
            let response = try await llm.agenticReply(to: "Add \(transcript) to inventory.")

            guard var call = Self.addStockCall(from: response) else {
                results.append("Sorry, I couldn't understand \"\(transcript)\" — it wasn't added.")
                continue
            }

            if (call.arguments["itemName"] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                let name = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: "What's the name of item \(ordinal)?"))
                detailPhrase = nil
                call = call.addingArgument(name, forKey: "itemName")
            }

            if (call.arguments["quantity"] as? NSNumber)?.doubleValue == nil {
                let amountPhrase = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: "How much, and what unit, for item \(ordinal)?"))
                detailPhrase = nil
                let parsed = StockPhraseParser.parse(amountPhrase)
                call = call.addingArgument(parsed.quantity, forKey: "quantity")
                call = call.addingArgument(parsed.unit, forKey: "unit")
            } else if (call.arguments["unit"] as? String)?.isEmpty ?? true {
                let unitPhrase = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: "What unit — kilograms, grams, pieces?"))
                detailPhrase = nil
                call = call.addingArgument(StockPhraseParser.canonicalUnit(unitPhrase), forKey: "unit")
            }

            let tool = AddStockTool()
            if tool.needsPrice(arguments: call.arguments) {
                let reply = try await $priceReply.requestValue(IntentDialog(stringLiteral: "What's the price for item \(ordinal)?"))
                priceReply = nil
                guard case .needsConfirmation(let priced, _) = llm.resolvePriceReply(reply, call: call) else {
                    results.append("Sorry, I didn't catch a price for \"\(transcript)\" — it wasn't added.")
                    continue
                }
                call = priced
            }

            do {
                results.append(try tool.call(arguments: call.arguments))
            } catch let error as AgentToolError {
                results.append(error.message)
            } catch {
                results.append("Sorry, something went wrong adding \"\(transcript)\".")
            }
        }

        return results.joined(separator: " ")
    }

    /// Extracts a `ToolCall` to work with regardless of which `AgentResponse`
    /// case the model produced — `.needsConfirmation`/`.needsPrice` already
    /// carry one; `.answer` (the model didn't call add_stock at all, e.g. an
    /// empty or nonsense transcript) has none, so the caller reports that
    /// item as unparseable rather than guessing.
    private static func addStockCall(from response: LLMService.AgentResponse) -> ToolCall? {
        switch response {
        case .answer:
            return nil
        case .needsPrice(let call), .needsConfirmation(let call, _):
            return call
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
