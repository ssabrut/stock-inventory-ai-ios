//
//  ToolRegistry.swift
//  stock-inventory-ai-ios
//

import Foundation

/// A tool call the LLM asked to make, decoded from its JSON reply.
struct ToolCall {
    let name: String
    let arguments: [String: Any]

    /// Returns this call with `key` set in its arguments — used to merge a
    /// price the user supplied in a follow-up chat message (in reply to
    /// `.needsPrice`) into the original call before resubmitting it, since
    /// `arguments` is otherwise immutable once the model produced it.
    func addingArgument(_ value: Any, forKey key: String) -> ToolCall {
        var merged = arguments
        merged[key] = value
        return ToolCall(name: name, arguments: merged)
    }
}

/// Holds the tools available to Tanya AI's agent loop and handles the
/// JSON-directive protocol between the LLM and Swift: the system prompt
/// tells the model to reply with either `{"tool": name, "args": {...}}` or
/// `{"answer": text}`, and this type parses that reply and dispatches the
/// matching tool. A 1.5B on-device model has no native tool-calling head,
/// so a small fixed JSON envelope is far more reliable to parse than
/// free-form ReAct-style text.
final class ToolRegistry {
    private(set) var tools: [AgentTool]

    init(tools: [AgentTool] = [
        GetStockTool(), AddStockTool(), UpdateStockTool(), DeleteStockTool(),
        GetMenuTool(), AddMenuTool(), UpdateMenuTool(), DeleteMenuTool()
    ]) {
        self.tools = tools
    }

    func tool(named name: String) -> AgentTool? {
        tools.first { $0.name == name }
    }

    /// System prompt fragment listing every tool and the exact reply
    /// contract, appended after the assistant's persona/role text.
    var systemPromptFragment: String {
        let toolList = tools.map(\.promptDescription).joined(separator: "\n")
        return """
        You can use these tools:
        \(toolList)

        To call a tool, reply with ONLY a JSON object on one line: \
        {"tool": "<tool_name>", "args": {...}}

        If no tool is needed, reply with ONLY: {"answer": "<your reply>"}

        Never reply with anything other than one of these two JSON forms.
        """
    }

    /// Extracts and decodes a `{"tool": ...}` or `{"answer": ...}` object
    /// from the model's raw output. Scans for the first balanced `{...}`
    /// span rather than requiring the whole string to be JSON, since small
    /// models sometimes wrap their reply in stray text or code fences.
    enum ParsedReply {
        case toolCall(ToolCall)
        case answer(String)
    }

    func parseReply(_ raw: String) -> ParsedReply {
        guard let jsonString = Self.extractJSONObject(from: raw),
              let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .answer(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let answer = object["answer"] as? String {
            return .answer(answer)
        }

        if let toolName = object["tool"] as? String {
            let args = object["args"] as? [String: Any] ?? [:]
            return .toolCall(ToolCall(name: toolName, arguments: args))
        }

        return .answer(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs the named tool, returning either its plain-text result or the
    /// user-facing message from an `AgentToolError`, so the caller can feed
    /// either straight back to the LLM as the tool's outcome.
    func execute(_ call: ToolCall) -> String {
        guard let tool = tool(named: call.name) else {
            return "Error: unknown tool \"\(call.name)\"."
        }
        do {
            return try tool.call(arguments: call.arguments)
        } catch let error as AgentToolError {
            return "Error: \(error.message)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
