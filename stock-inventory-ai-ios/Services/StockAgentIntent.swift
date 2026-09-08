//
//  StockAgentIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents

/// Which action the user wants — its own `AppEnum` (rather than a free-text
/// parameter) specifically so it can bind directly into an `AppShortcut`
/// phrase: Siri's phrase matching only supports inline parameter capture
/// for a finite, enumerable set of values (enums, `AppEntity` lookups), not
/// arbitrary free text. That's what makes "Check stock in Invent" resolve
/// in one turn — the phrase itself carries the enum case, no follow-up ask
/// needed for *which* action.
enum StockAction: String, AppEnum {
    /// No pinned action — the generic "Ask Invent" entry point. Detail
    /// phrase is asked for and routed through the LLM to pick a tool, same
    /// as the earlier free-text-only design, for anything not covered by
    /// one of the specific pinned actions below.
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

/// Single Siri entry point into Tanya AI's whole agent (see LLMService,
/// ToolRegistry). `action` (see `StockAction`) is resolved directly from the
/// triggering phrase, so "Check stock in Invent" is one turn end-to-end —
/// check-stock needs no further detail and runs immediately against
/// StockStore with no LLM call at all. `addStock`/`updateStock`/
/// `deleteStock` still need free-text detail (item name, quantity, price —
/// inherently not enumerable), so those ask one follow-up phrase and route
/// it through `LLMService.agenticReply`/`ToolRegistry` the same way chat
/// does, shrinking the LLM's job from "pick a tool" (now done by Siri's own
/// phrase match) to "extract fields from a follow-up phrase."
///
/// `openAppWhenRun` is true: MLX's on-device inference runs on the GPU via
/// Metal, which a background (openAppWhenRun = false) App Intent execution
/// context can't reliably host — iOS reclaims GPU access from a
/// non-foreground process mid-inference, which crashed here
/// (IOGPUCommandQueueSubmitCommandBuffers / iokit_user_client_trap, a
/// Metal command buffer submitted from a thread that no longer had GPU
/// access). Foregrounding the app gives the same LLMService/ToolRegistry
/// call a normal process to run in — the same as ChatScreen already does —
/// so no tool logic is duplicated, only the execution context changes.
/// checkStock's direct StockStore path needs no GPU at all, so it stays
/// fast even though the intent as a whole opens the app.
struct StockAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Invent"
    static var description = IntentDescription("Check, add, update, or delete stock by voice.")
    static var openAppWhenRun = true

    @Parameter(title: "Action")
    var action: StockAction

    /// Free-text detail for addStock/updateStock/deleteStock — unused for
    /// checkStock, which needs no further detail to run.
    @Parameter(title: "Details")
    var detailPhrase: String?

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

    /// Backing parameter for the mutating-tool yes/no confirm, resolved via
    /// requestDisambiguation rather than requestConfirmation for the same
    /// reason as the old flow: rejection needs to end the intent gracefully
    /// with a spoken cancellation, not throw past a point that still needs
    /// to speak a reply.
    @Parameter(title: "Confirm")
    var confirmChoice: String?

    /// Bare-number reply to "what's the price?" when a tool call is missing
    /// one (see LLMService.resolvePriceReply) — a separate turn since the
    /// model has no memory of the original call across it.
    @Parameter(title: "What's the price?")
    var priceReply: String?

    private static let yesChoice = "Yes, go ahead"
    private static let noChoice = "No, cancel"

    private let llm = LLMService()

    /// Required for `requestValue`/`requestDisambiguation` to actually
    /// present their prompt on iOS 18+: a parameter not listed here fails
    /// silently (throws a connection-interrupted error instead of prompting)
    /// even though it's declared with `@Parameter` — this is a known
    /// AppIntents regression, not specific to this intent.
    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) in Invent") {
            \.$detailPhrase
            \.$confirmChoice
            \.$priceReply
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if action == .checkStock {
            return .result(dialog: IntentDialog(stringLiteral: checkStockResult()))
        }

        if action == .addStock {
            return .result(dialog: IntentDialog(stringLiteral: try await performAddLoop()))
        }

        let phrase = try await resolveDetailPhrase()
        let response = try await llm.agenticReply(to: phrase)
        return .result(dialog: IntentDialog(stringLiteral: try await resolve(response, originalPrompt: phrase)))
    }

    /// Drives the full multi-item add flow: ask how many items up front,
    /// collect + confirm each one individually (re-asking the same slot on
    /// "No"), then ask one final yes/no over the whole batch before any
    /// StockStore write happens — a "No" at that last step cancels the
    /// entire batch, not just the last item. Nothing is committed until
    /// that final confirmation, unlike the old per-item flow which wrote
    /// immediately on each item's own "Yes, go ahead".
    private func performAddLoop() async throws -> String {
        confirmChoice = nil
        let countChoice = try await $confirmChoice.requestDisambiguation(
            among: ["1", "2", "3"],
            dialog: IntentDialog(stringLiteral: "How many items do you want to add?")
        )
        let itemCount = Int(countChoice) ?? 1

        var pendingCalls: [(call: ToolCall, summary: String)] = []

        for itemIndex in 0..<itemCount {
            let ordinal = itemIndex + 1
            let pending = try await collectAddItem(ordinal: ordinal, total: itemCount)
            pendingCalls.append(pending)
        }

        let batchSummary = pendingCalls.map(\.summary).joined(separator: " ")
        confirmChoice = nil
        let finalChoice = try await $confirmChoice.requestDisambiguation(
            among: [Self.yesChoice, Self.noChoice],
            dialog: IntentDialog(stringLiteral: "\(batchSummary) Add all of these?")
        )
        guard finalChoice == Self.yesChoice else {
            return "Okay, cancelled. Nothing was added."
        }

        let results = pendingCalls.map { pending -> String in
            do {
                return try AddStockTool().call(arguments: pending.call.arguments)
            } catch let error as AgentToolError {
                return error.message
            } catch {
                return "Sorry, something went wrong adding \(pending.summary)"
            }
        }
        return results.joined(separator: " ")
    }

    /// Asks for one item's detail phrase, fills in whichever of item name /
    /// quantity+unit / price the model's parse left missing with its own
    /// targeted follow-up (rather than discarding the whole phrase over one
    /// missing field), then speaks the item's summary back for a yes/no —
    /// "No" re-asks this same slot from scratch rather than advancing, so a
    /// misheard item can be redone without restarting the whole batch.
    /// Returns the approved `ToolCall` un-executed; `performAddLoop` only
    /// runs it after the final batch-wide confirmation.
    private func collectAddItem(ordinal: Int, total: Int) async throws -> (call: ToolCall, summary: String) {
        let itemLabel = total > 1 ? "item \(ordinal) of \(total)" : "the item"
        var askPrompt = "What's \(itemLabel)? Say the name and quantity."

        while true {
            let phrase = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: askPrompt))
            detailPhrase = nil

            // The bare utterance alone ("5kg of white pepper") reads as
            // ambiguous to the 1.5B model without a verb — it would often
            // answer conversationally instead of calling add_stock. Framing
            // it explicitly as an add request makes the intent unambiguous.
            let response = try await llm.agenticReply(to: "Add \(phrase) to inventory.")

            guard var call = Self.addStockCall(from: response) else {
                askPrompt = "Sorry, I didn't catch an item and quantity — try again. What's \(itemLabel)?"
                continue
            }

            if (call.arguments["itemName"] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                let name = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: "What's the item's name?"))
                detailPhrase = nil
                call = call.addingArgument(name, forKey: "itemName")
            }

            if (call.arguments["quantity"] as? NSNumber)?.doubleValue == nil {
                let amountPhrase = try await $detailPhrase.requestValue(IntentDialog(stringLiteral: "How much, and what unit?"))
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
                let reply = try await $priceReply.requestValue(IntentDialog(stringLiteral: "What's the price?"))
                priceReply = nil
                guard case .needsConfirmation(let priced, _) = llm.resolvePriceReply(reply, call: call) else {
                    askPrompt = "Sorry, I didn't catch a price — let's try \(itemLabel) again."
                    continue
                }
                call = priced
            }

            let summary = tool.confirmationSummary(arguments: call.arguments)
            confirmChoice = nil
            let choice = try await $confirmChoice.requestDisambiguation(
                among: [Self.yesChoice, Self.noChoice],
                dialog: IntentDialog(stringLiteral: "\(summary) Is that correct?")
            )
            if choice == Self.yesChoice {
                return (call, summary)
            }
            askPrompt = "Let's try \(itemLabel) again. Say the name and quantity."
        }
    }

    /// Extracts a `ToolCall` to work with regardless of which `AgentResponse`
    /// case the model produced — `.needsConfirmation`/`.needsPrice` already
    /// carry one; `.answer` (the model didn't call add_stock at all, e.g. an
    /// empty or nonsense phrase) has none, so the caller re-prompts from
    /// scratch. Price is deliberately left for `collectAddItem`'s own
    /// `needsPrice` check rather than resolved here, since a bare `.needsPrice`
    /// call from `agenticReply` still needs the same field-completeness pass.
    private static func addStockCall(from response: LLMService.AgentResponse) -> ToolCall? {
        switch response {
        case .answer:
            return nil
        case .needsPrice(let call), .needsConfirmation(let call, _):
            return call
        }
    }

    /// Walks an `AgentResponse` to a final spoken string, looping through a
    /// price follow-up and/or a confirm turn exactly like ChatScreen does
    /// for the same enum, just via Siri turns instead of chat bubbles. Used
    /// by updateStock/deleteStock/ask, which each target one call per
    /// invocation and commit immediately on confirm — addStock no longer
    /// goes through here (see `performAddLoop`/`collectAddItem`), since it
    /// needs to hold every item's approved call until one final batch-wide
    /// confirmation before anything is written.
    private func resolve(_ response: LLMService.AgentResponse, originalPrompt: String) async throws -> String {
        switch response {
        case .answer(let text):
            return text

        case .needsPrice(let call):
            let reply = try await $priceReply.requestValue(IntentDialog(stringLiteral: "What's the price?"))
            guard let updated = llm.resolvePriceReply(reply, call: call) else {
                return "Sorry, I didn't catch a price — try again."
            }
            priceReply = nil
            return try await resolve(updated, originalPrompt: originalPrompt)

        case .needsConfirmation(let call, let summary):
            confirmChoice = nil
            let choice = try await $confirmChoice.requestDisambiguation(
                among: [Self.yesChoice, Self.noChoice],
                dialog: IntentDialog(stringLiteral: summary)
            )
            guard choice == Self.yesChoice else {
                return "Okay, cancelled."
            }
            return try await llm.resolveConfirmedToolCall(call, originalPrompt: originalPrompt)
        }
    }

    private func resolveDetailPhrase() async throws -> String {
        if let detailPhrase, !detailPhrase.trimmingCharacters(in: .whitespaces).isEmpty { return detailPhrase }

        let prompt: String = switch action {
        case .addStock: "What do you want to add?"
        case .updateStock: "What do you want to update?"
        case .deleteStock: "What do you want to delete?"
        case .ask, .checkStock: "What do you want to do?"
        }
        return try await $detailPhrase.requestValue(IntentDialog(stringLiteral: prompt))
    }

    /// Runs get_stock directly against StockStore — no LLM call at all, so
    /// checkStock stays instant even though the intent as a whole opens the
    /// app for the other actions' GPU-bound LLM step. `AgentToolError` (e.g.
    /// "no entries found matching X") is a normal spoken outcome here, not a
    /// crash, so its message is what gets spoken instead of a generic answer.
    private func checkStockResult() -> String {
        do {
            return try GetStockTool().call(arguments: [:])
        } catch let error as AgentToolError {
            return error.message
        } catch {
            return "Sorry, something went wrong checking stock."
        }
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
    /// not covered by the pinned ones, and still needs its own follow-up
    /// ask + LLM routing, same as the original free-text-only design.
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
