//
//  MenuAgentIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents
import SwiftUI

/// Which action the user wants — its own `AppEnum` (rather than a free-text
/// parameter) specifically so it can bind directly into an `AppShortcut`
/// phrase, same reasoning as `StockAction`.
enum MenuAction: String, AppEnum {
    /// No pinned action — the generic "Ask Invent Menu" entry point.
    /// Currently disabled (see `MenuAgentIntent`'s doc comment) along with
    /// updateMenu/deleteMenu — only addMenu/checkMenu have a working flow
    /// right now.
    case ask
    case checkMenu
    case addMenu
    case updateMenu
    case deleteMenu

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Menu Action"

    static var caseDisplayRepresentations: [MenuAction: DisplayRepresentation] = [
        .ask: "Ask",
        .checkMenu: "Check Menu",
        .addMenu: "Add Menu",
        .updateMenu: "Update Menu",
        .deleteMenu: "Delete Menu"
    ]
}

/// Single Siri entry point for POS menu actions — the menu-editor analog of
/// `StockAgentIntent`. `action` (see `MenuAction`) is resolved directly from
/// the triggering phrase, so "Check menu in Invent" is one turn end-to-end —
/// checkMenu needs no further detail and runs immediately against
/// `MenuStore`.
///
/// `addMenu` collects items transcript-first, with no LLM involved until the
/// user has confirmed the whole batch — same three-step shape as
/// `StockAgentIntent.addStock`:
/// 1. `collectTranscripts` loops asking for the next item, confirming each
///    raw Siri transcription with a spoken "Is that correct?" yes/no (see
///    `confirmTranscript` — a "No" lets the user re-speak the item rather
///    than losing it, "done" ends the loop).
/// 2. The whole accumulated list is shown in a summary snippet
///    (`TranscriptSnippetView`, reused from `StockAgentIntent.swift`) with
///    one final "Add all these?" yes/no gate (see `confirmBatch`) —
///    declining cancels the entire session with nothing written.
/// 3. Only on "yes" does `parseAndAddItems` run each transcript through
///    `LLMService.agenticReply` (same JSON tool-call contract ChatScreen
///    uses) to extract name/price/category, fill in whatever the parse left
///    missing with a targeted follow-up, then write via `AddMenuTool`
///    (MenuStore/Core Data).
///
/// Unlike `AddStockTool`, `AddMenuTool` does not override `needsPrice` — a
/// missing price surfaces only as a thrown `AgentToolError` from `call`, not
/// through the `.needsPrice` `AgentResponse` case. So this intent checks
/// `call.arguments["price"]` itself (mirroring how it already checks
/// itemName/category) and asks a direct follow-up, merging the reply into
/// the call's "price" key — `LLMService.resolvePriceReply` isn't reusable
/// here since it's hardcoded to merge into "totalCost" for the stock flow.
///
/// `updateMenu`/`deleteMenu`/`ask` remain disabled — they had no
/// transcript-first equivalent built yet.
///
/// `openAppWhenRun` is true for the same reason as `StockAgentIntent`: MLX's
/// on-device inference runs on the GPU via Metal, which a background App
/// Intent execution context can't reliably host.
struct MenuAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Invent Menu"
    static var description = IntentDescription("Check or add POS menu items by voice.")
    static var openAppWhenRun = true

    @Parameter(title: "Action")
    var action: MenuAction

    /// Free-text detail for addMenu — unused for checkMenu, which needs no
    /// further detail to run. Also carries the per-item "Is that correct?"
    /// reply in `confirmTranscript`, classified as yes/no by
    /// `YesNoClassifier` rather than a dedicated disambiguation parameter —
    /// see `StockAgentIntent.confirmTranscript`'s doc comment for why.
    @Parameter(title: "Details")
    var detailPhrase: String?

    /// Bare-number reply to "what's the price?" when `AddMenuTool` is
    /// missing one — a separate turn since the model has no memory of the
    /// original call across it.
    @Parameter(title: "What's the price?")
    var priceReply: String?

    /// Reply to "Makanan or Minuman?" when the parsed transcript didn't
    /// carry a resolvable category.
    @Parameter(title: "Makanan or Minuman?")
    var categoryReply: String?

    private let llm = LLMService()

    init() {
        self.action = .ask
    }

    /// Used by `MenuAppShortcuts` to pin a specific action per `AppShortcut`
    /// entry, same reasoning as `StockAgentIntent.init(action:)`.
    init(action: MenuAction) {
        self.action = action
    }

    /// Required for `requestValue` to actually present its prompt on
    /// iOS 18+ — see `StockAgentIntent.parameterSummary`'s doc comment.
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) in Invent Menu") {
            \.$detailPhrase
            \.$priceReply
            \.$categoryReply
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        if action == .checkMenu || action == .addMenu {
            // Lands the foregrounded app on "POS" (PosEditorScreen) so the
            // user sees the menu editor entry point, not whatever screen was
            // showing before Siri opened the app — ContentView applies this
            // via AppNavigationState.shared the next time it appears. Same
            // one-hop-short landing StockAgentIntent settles for with
            // .inventory: PosEditorScreen's "Edit POS" link is one tap away
            // rather than a direct drill-down, since EditPosScreen has no
            // AppScreen case of its own.
            AppNavigationState.shared.pendingScreen = .posEditor
        }

        if action == .checkMenu {
            let allItems = MenuStore.all()
            let filterName = detailPhrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let items = filterName.isEmpty
                ? allItems
                : allItems.filter { $0.name.range(of: filterName, options: .caseInsensitive) != nil }

            return .result(
                dialog: IntentDialog(stringLiteral: checkMenuResult(items: items, filterName: filterName)),
                view: MenuSnippetView(items: items)
            )
        }

        if action == .addMenu {
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
            dialog: IntentDialog(stringLiteral: "That's not available right now — try \"Check menu in Invent\" or \"Add menu in Invent\"."),
            view: MenuSnippetView(items: [])
        )
    }

    /// Stop words that end the transcript-collection loop — same set as
    /// `StockAgentIntent.doneWords`.
    private static let doneWords: Set<String> = ["done", "stop", "that's all", "that is all", "selesai", "sudah", "cukup"]

    private static func isDoneWord(_ phrase: String) -> Bool {
        doneWords.contains(phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Free-N transcript-collection loop — identical shape to
    /// `StockAgentIntent.collectTranscripts`, but asks for "at <price>"
    /// (`askPrice`) with no unit/quantity step, since a menu item is just
    /// name + price + category.
    private func collectTranscripts() async throws -> [String] {
        var transcripts: [String] = []
        var askPrompt = "What's the first menu item? Say the name and price, or say \"done\" if you're finished."

        while true {
            let phrase = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: askPrompt))
            detailPhrase = nil
            #if DEBUG
            print("[MenuAgentIntent] Siri transcription: \"\(phrase)\"")
            #endif

            if Self.isDoneWord(phrase) {
                #if DEBUG
                print("[MenuAgentIntent] collectTranscripts finished — total items collected: \(transcripts.count)")
                #endif
                break
            }

            guard let confirmed = try await confirmTranscript(phrase, itemNumber: transcripts.count + 1) else {
                #if DEBUG
                print("[MenuAgentIntent] collectTranscripts finished (done said during correction) — total items collected: \(transcripts.count)")
                #endif
                break
            }

            let withPrice = try await askPrice(for: confirmed, itemNumber: transcripts.count + 1)
            transcripts.append(withPrice)
            #if DEBUG
            print("[MenuAgentIntent] collectTranscripts collected item \(transcripts.count): \"\(withPrice)\"")
            #endif

            askPrompt = "Got it. What's the next menu item, or say \"done\"?"
        }

        return transcripts
    }

    /// Asks "What's the price for <item>?" and appends the reply to
    /// `transcript` as "at <price>" — same shape as
    /// `StockAgentIntent.askPrice`. A bare non-numeric reply is appended
    /// as-is rather than dropped, since `parseAndAddItems`'s own missing-
    /// price follow-up still gets a chance to make sense of it or ask again.
    private func askPrice(for transcript: String, itemNumber: Int) async throws -> String {
        let reply = try await $priceReply.requestValue(IntentDialog(stringLiteral: "What's the price for item \(itemNumber): \(transcript)?"))
        priceReply = nil
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return transcript }
        return "\(transcript) at \(trimmed)"
    }

    /// Asks "<transcript>. Is that correct?" and classifies the free-text
    /// reply as yes/no via `YesNoClassifier` — identical to
    /// `StockAgentIntent.confirmTranscript`, see its doc comment for why
    /// `requestDisambiguation` isn't used here.
    private func confirmTranscript(_ phrase: String, itemNumber: Int) async throws -> String? {
        let reply = try await $detailPhrase.requestValue(
            IntentDialog(stringLiteral: "Item \(itemNumber): \(phrase). Is that correct?")
        )
        detailPhrase = nil
        let classification = YesNoClassifier.classify(reply)
        #if DEBUG
        print("[MenuAgentIntent] confirm reply: \"\(reply)\" — classified as \(classification)")
        #endif

        guard classification != .yes else {
            return phrase
        }

        #if DEBUG
        print("[MenuAgentIntent] item \(itemNumber) rejected: \"\(phrase)\" (reply classified \(classification)) — asking user to re-speak")
        #endif
        let corrected = try await $detailPhrase.requestValue(
            IntentDialog(stringLiteral: "Sorry — please say the correct item name and price, or say \"done\" to stop.")
        )
        detailPhrase = nil

        if Self.isDoneWord(corrected) {
            return nil
        }
        return try await confirmTranscript(corrected, itemNumber: itemNumber)
    }

    /// Final batch-wide gate shown alongside the summary snippet — identical
    /// to `StockAgentIntent.confirmBatch`.
    private func confirmBatch(_ transcripts: [String]) async throws -> Bool {
        let listText = transcripts.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: ", ")
        let reply = try await $detailPhrase.requestValue(
            IntentDialog(stringLiteral: "Here's what I heard: \(listText). Add all \(transcripts.count) of these to the menu?")
        )
        detailPhrase = nil
        let classification = YesNoClassifier.classify(reply)
        #if DEBUG
        print("[MenuAgentIntent] confirmBatch reply: \"\(reply)\" — classified as \(classification)")
        #endif
        return classification == .yes
    }

    /// Runs each confirmed transcript through `LLMService.agenticReply` to
    /// parse it into an add_menu call, fills in whatever the parse left
    /// missing (name, price, category) with a targeted follow-up, then
    /// writes via `AddMenuTool` — this is the only point in the whole
    /// addMenu flow that touches the LLM or MenuStore, since the batch has
    /// already been confirmed once as a whole in `confirmBatch`.
    private func parseAndAddItems(_ transcripts: [String]) async throws -> String {
        var results: [String] = []

        for (index, transcript) in transcripts.enumerated() {
            let ordinal = index + 1
            #if DEBUG
            print("[MenuAgentIntent] parseAndAddItems parsing item \(ordinal): \"\(transcript)\"")
            #endif

            // Framing it explicitly as an add request makes the intent
            // unambiguous to the small model, same reasoning as
            // StockAgentIntent.parseAndAddItems.
            let response = try await llm.agenticReply(to: "Add \(transcript) to the POS menu.")

            guard var call = Self.addMenuCall(from: response) else {
                results.append("Sorry, I couldn't understand \"\(transcript)\" — it wasn't added.")
                continue
            }

            if (call.arguments["name"] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                let name = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: "What's the name of item \(ordinal)?"))
                detailPhrase = nil
                call = call.addingArgument(name, forKey: "name")
            }

            if (call.arguments["price"] as? NSNumber)?.doubleValue == nil {
                let reply = try await $priceReply.requestValue(IntentDialog(stringLiteral: "What's the price for item \(ordinal)?"))
                priceReply = nil
                guard let price = Self.firstNumber(in: reply) else {
                    results.append("Sorry, I didn't catch a price for \"\(transcript)\" — it wasn't added.")
                    continue
                }
                call = call.addingArgument(price, forKey: "price")
            }

            if MenuCategory(looselyMatching: (call.arguments["category"] as? String) ?? "") == nil {
                let categoryText = try await $categoryReply.requestValue(IntentDialog(stringLiteral: "Is item \(ordinal) Makanan or Minuman?"))
                categoryReply = nil
                guard let category = MenuCategory(looselyMatching: categoryText) else {
                    results.append("Sorry, I didn't catch a category for \"\(transcript)\" — it wasn't added.")
                    continue
                }
                call = call.addingArgument(category.rawValue, forKey: "category")
            }

            let tool = AddMenuTool()
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
    /// case the model produced — `.needsConfirmation` already carries one;
    /// `.answer` (the model didn't call add_menu at all, e.g. an empty or
    /// nonsense transcript) has none, so the caller reports that item as
    /// unparseable rather than guessing. `add_menu` never triggers
    /// `.needsPrice` since `AddMenuTool` doesn't override `needsPrice`.
    private static func addMenuCall(from response: LLMService.AgentResponse) -> ToolCall? {
        switch response {
        case .answer:
            return nil
        case .needsPrice(let call, _), .needsConfirmation(let call, _, _):
            return call
        }
    }

    /// Bare-number parse for the price/re-ask follow-ups above — deliberately
    /// simpler than `LLMService`'s private `firstPriceNumber(in:)` (no
    /// "50rb"/"50k" multiplier aliases), since that parser isn't exposed
    /// outside `LLMService` and duplicating its regex here isn't worth it
    /// for a fallback path the LLM parse is expected to cover first.
    private static func firstNumber(in text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let digitsAndDot = cleaned.filter { $0.isNumber || $0 == "." }
        return Double(digitsAndDot)
    }

    /// Spoken summary for checkMenu, built from the same `items` snapshot
    /// passed to `MenuSnippetView` — one `MenuStore.all()` fetch covers both
    /// the dialog and the visual snippet. Kept short since iOS echoes this
    /// dialog text as an on-screen caption above the snippet view.
    private func checkMenuResult(items: [MenuItem], filterName: String) -> String {
        guard !filterName.isEmpty else {
            guard !items.isEmpty else { return "Menu is empty." }
            return "You have \(items.count) item\(items.count == 1 ? "" : "s") on the menu."
        }

        guard !items.isEmpty else {
            return "No menu item found for \(filterName)."
        }
        if items.count == 1, let item = items.first {
            return "\(item.name): \(item.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))."
        }
        return items
            .map { "\($0.name): \($0.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))" }
            .joined(separator: ". ")
    }
}

/// Visual snippet shown alongside checkMenu's spoken dialog in the Siri /
/// Shortcuts UI — the menu-editor analog of `StockSnippetView`.
struct MenuSnippetView: View {
    let items: [MenuItem]

    /// Rows shown before falling back to the "+N more" line — same cap as
    /// `StockSnippetView.visibleLimit`.
    private static let visibleLimit = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("POS Menu", systemImage: "fork.knife")
                .font(.headline)

            if items.isEmpty {
                Text("No menu items yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(Self.visibleLimit)) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(item.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if items.count > Self.visibleLimit {
                    Text("+ \(items.count - Self.visibleLimit) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct MenuAppShortcuts: AppShortcutsProvider {
    /// Each pinned-action shortcut bakes its `action` into the intent itself
    /// (via `MenuAgentIntent(action:)`) rather than relying on phrase-
    /// parameter binding — same reasoning as `StockAppShortcuts`.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MenuAgentIntent(action: .checkMenu),
            phrases: [
                "\(.applicationName) check menu",
                "Check menu in \(.applicationName)",
                "Check menu on \(.applicationName)",
                "Check my menu in \(.applicationName)",
                "Check my menu on \(.applicationName)",
                "What's on the menu in \(.applicationName)",
                "What's on the menu on \(.applicationName)",
                // Inline free-text capture into `detailPhrase` — same
                // reasoning as StockAppShortcuts' equivalent phrases.
                "Check \(\.$detailPhrase) menu in \(.applicationName)",
                "Check \(\.$detailPhrase) menu on \(.applicationName)",
                "How much is \(\.$detailPhrase) in \(.applicationName)",
                "How much is \(\.$detailPhrase) on \(.applicationName)"
            ],
            shortTitle: "Check Menu",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: MenuAgentIntent(action: .addMenu),
            phrases: [
                "\(.applicationName) add menu",
                "Add menu in \(.applicationName)",
                "Add menu on \(.applicationName)",
                "Add menu item in \(.applicationName)",
                "Add menu item on \(.applicationName)",
                "I want to add a menu item in \(.applicationName)",
                "I want to add a menu item on \(.applicationName)"
            ],
            shortTitle: "Add Menu",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: MenuAgentIntent(action: .updateMenu),
            phrases: [
                "\(.applicationName) update menu",
                "Update menu in \(.applicationName)",
                "Update menu on \(.applicationName)"
            ],
            shortTitle: "Update Menu",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: MenuAgentIntent(action: .deleteMenu),
            phrases: [
                "\(.applicationName) delete menu",
                "Delete menu in \(.applicationName)",
                "Delete menu on \(.applicationName)"
            ],
            shortTitle: "Delete Menu",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: MenuAgentIntent(),
            phrases: [
                "Ask \(.applicationName) about menu"
            ],
            shortTitle: "Ask Invent Menu",
            systemImageName: "fork.knife"
        )
    }
}
