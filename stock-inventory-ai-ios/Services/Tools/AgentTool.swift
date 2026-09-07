//
//  AgentTool.swift
//  stock-inventory-ai-ios
//

import Foundation

/// One parameter of an `AgentTool`, described in plain language rather than
/// full JSON Schema — the prompt embeds this as text for a 1.5B on-device
/// model, which follows a short natural-language spec more reliably than
/// nested schema objects.
struct AgentToolParameter {
    let name: String
    let type: String
    let description: String
    let isRequired: Bool

    init(name: String, type: String, description: String, isRequired: Bool = true) {
        self.name = name
        self.type = type
        self.description = description
        self.isRequired = isRequired
    }
}

/// Error surfaced back to the LLM (not thrown to the caller) so the model can
/// explain the failure to the user in its own words, e.g. "item not found".
struct AgentToolError: Error {
    let message: String
}

/// A capability Tanya AI can invoke. Tools operate on `StockStore` and return
/// a plain-text result the LLM folds into its final reply — there is no
/// structured result type, since the only consumer is the LLM's next
/// generation pass.
protocol AgentTool {
    /// Stable identifier the LLM emits in its tool-call JSON, e.g. "get_stock".
    var name: String { get }

    /// One-line description shown to the LLM when deciding which tool fits.
    var description: String { get }

    var parameters: [AgentToolParameter] { get }

    /// Runs the tool with the LLM-provided arguments (raw JSON values keyed
    /// by parameter name) and returns a plain-text result to feed back to
    /// the model. Throws `AgentToolError` for user-facing failures (e.g.
    /// "no item named X") the model should relay, not treat as a crash.
    func call(arguments: [String: Any]) throws -> String
}

extension AgentTool {
    /// Rendered for the system prompt's tool listing, e.g.:
    /// "- get_stock(itemName: string, optional): Look up quantity of one item."
    var promptDescription: String {
        let params = parameters
            .map { "\($0.name): \($0.type)\($0.isRequired ? "" : ", optional")" }
            .joined(separator: ", ")
        return "- \(name)(\(params)): \(description)"
    }
}
