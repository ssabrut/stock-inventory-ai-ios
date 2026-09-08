//
//  StockAgentIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents

/// Single Siri entry point into Tanya AI's whole agent (see LLMService,
/// ToolRegistry) — one free-text phrase routes to whichever tool the LLM
/// picks (get_stock, add_stock, update_stock, delete_stock), rather than a
/// separate AppIntent per action.
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
///
/// This replaces the earlier deterministic, multi-turn add-stock-only flow
/// (fixed item/cost slots + StockPhraseParser, no LLM) — that design existed
/// specifically because the LLM was hallucinating structured fields when
/// driven by voice. Routing everything back through the LLM here trades
/// that reliability for one flexible entry point covering every action
/// (including read-only check-stock, which has no write to get wrong), the
/// same way chat already works — mutating tools still require a spoken
/// yes/no confirm before `call` runs (see `AgentTool.isMutating`), so a bad
/// parse can be caught before it touches StockStore.
struct StockAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Invent"
    static var description = IntentDescription("Ask Invent to check, add, update, or delete stock by voice.")
    static var openAppWhenRun = true

    @Parameter(title: "What do you want to do?", requestValueDialog: "What do you want to do?")
    var requestPhrase: String

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
    /// AppIntents regression, not specific to this intent. `confirmChoice`
    /// and `priceReply` are only ever used as ephemeral mid-flow turns (never
    /// shown in the Shortcuts summary sentence itself), but still have to be
    /// listed here for their own `requestValue`/`requestDisambiguation` calls
    /// to work. This is also what lets "Hey Siri, Ask Invent" go straight
    /// into asking "What do you want to do?" without the user needing to say
    /// the app name again — Siri already has `requestPhrase` as the next
    /// thing it's listening for.
    static var parameterSummary: some ParameterSummary {
        Summary("Ask Invent to \(\.$requestPhrase)") {
            \.$confirmChoice
            \.$priceReply
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let phrase = try await resolveRequestPhrase()
        let response = try await llm.agenticReply(to: phrase)
        return .result(dialog: IntentDialog(stringLiteral: try await resolve(response, originalPrompt: phrase)))
    }

    /// Walks an `AgentResponse` to a final spoken string, looping through a
    /// price follow-up and/or a confirm turn exactly like ChatScreen does
    /// for the same enum, just via Siri turns instead of chat bubbles.
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

    private func resolveRequestPhrase() async throws -> String {
        if !requestPhrase.trimmingCharacters(in: .whitespaces).isEmpty { return requestPhrase }
        return try await $requestPhrase.requestValue(IntentDialog(stringLiteral: "What do you want to do?"))
    }
}

struct StockAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StockAgentIntent(),
            phrases: [
                "Add stock in \(.applicationName)",
                "Add stock using \(.applicationName)",
                "Check stock in \(.applicationName)",
                "Check my stock in \(.applicationName)",
                "How much stock do I have in \(.applicationName)",
                "Ask \(.applicationName)",
                "I want to add stock in \(.applicationName)",
                "I'd like to add stock to \(.applicationName)",
                "Help me manage stock in \(.applicationName)",
                "Please add stock in \(.applicationName)"
            ],
            shortTitle: "Ask Invent",
            systemImageName: "shippingbox.fill"
        )
    }
}
