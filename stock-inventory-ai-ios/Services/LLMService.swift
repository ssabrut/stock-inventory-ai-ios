//
//  LLMService.swift
//  stock-inventory-ai-ios
//

import Foundation
import Hub
import MLXLLM
@preconcurrency import MLXLMCommon

@Observable
final class LLMService {
    enum LoadPhase: Equatable {
        case checkingCache
        case downloading(fraction: Double, speedMBps: Double?)
        case loadingWeights
    }

    enum State: Equatable {
        case idle
        case loading(LoadPhase)
        case ready
        case generating
        case failed(String)
    }

    private(set) var state: State = .idle

    private var modelContainer: ModelContainer?
    private let modelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    private let toolRegistry = ToolRegistry()

    /// Persists downloaded model weights to Documents instead of Caches, so the
    /// ~1GB download survives Xcode debug reinstalls (which can purge Caches).
    /// HF token is baked in from Secrets.xcconfig (gitignored) at build time via
    /// INFOPLIST_KEY_HFToken, never a scheme env var, so it can't leak into git.
    static let downloadBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appending(path: "huggingface")

    private let hub = HubApi(
        downloadBase: downloadBase,
        hfToken: {
            let token = Bundle.main.infoDictionary?["HFToken"] as? String
            return (token?.isEmpty == false && token != "$(HF_TOKEN)") ? token : nil
        }()
    )

    func loadIfNeeded() async {
        guard modelContainer == nil else { return }
        state = .loading(.checkingCache)
        do {
            let factory = LLMModelFactory.shared
            let configuration = ModelConfiguration(id: modelId)
            var didSeeRealProgress = false

            modelContainer = try await factory.loadContainer(hub: hub, configuration: configuration) { [weak self] progress in
                let fraction = progress.fractionCompleted
                let speed = progress.userInfo[.throughputKey] as? Double
                Task { @MainActor in
                    guard let self else { return }
                    // A cache hit resolves near-instantly with no meaningful fraction
                    // reported; only treat this as an active download once we see
                    // real forward progress on it.
                    if fraction > 0 { didSeeRealProgress = true }
                    if didSeeRealProgress {
                        if fraction < 1 {
                            self.state = .loading(.downloading(fraction: fraction, speedMBps: speed.map { $0 / 1_000_000 }))
                        } else {
                            self.state = .loading(.loadingWeights)
                        }
                    }
                }
            }
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Result of a Tanya AI chat turn. `.needsConfirmation` is returned
    /// instead of running a mutating tool outright — this is a human-
    /// centered AI project, so Tanya never writes a stock change without
    /// the user explicitly approving it first. The caller (ChatScreen) shows
    /// `summary` to the user and, on approval, passes `call` back into
    /// `resolveConfirmedToolCall`.
    ///
    /// `.needsPrice` is returned when a tool (e.g. add_stock) is missing a
    /// price it has no fallback for. The model has no chat memory across
    /// turns (see `agenticReply`'s doc comment), so the caller can't just
    /// re-ask the model — it holds `call` itself, reads the next user
    /// message as a bare price number, and merges it into `call.arguments`
    /// before resubmitting, the same way `.needsConfirmation` holds a call
    /// across the confirm step.
    enum AgentResponse {
        case answer(String)
        case needsConfirmation(call: ToolCall, summary: String)
        case needsPrice(call: ToolCall)
    }

    private var systemPrompt: String {
        """
        Kamu adalah asisten AI untuk aplikasi manajemen stok inventori. Jawab singkat, jelas, dan dalam Bahasa Indonesia.

        \(toolRegistry.systemPromptFragment)
        """
    }

    /// Tanya AI's chat entry point: lets the model call one of ToolRegistry's
    /// stock tools when it needs live inventory data instead of always
    /// injecting the full stock list as context (the old `reply(to:
    /// stockContext:)` approach). Capped at one tool-call round — a 1.5B
    /// on-device model is reliable enough to pick and use a single tool, but
    /// chaining several compounds the chance of it hallucinating a bad call
    /// or looping, so after one tool result it must produce a final answer.
    ///
    /// Read-only tools (e.g. get_stock) run immediately since they have no
    /// side effect to confirm. Mutating tools stop short of `.execute` and
    /// return `.needsConfirmation` instead.
    func agenticReply(to prompt: String) async throws -> AgentResponse {
        let firstRaw = try await generate(
            chat: [.system(systemPrompt), .user(prompt)],
            temperature: 0.6
        )
        #if DEBUG
        print("[LLMService] prompt: \(prompt)\n[LLMService] raw: \(firstRaw)")
        #endif

        switch toolRegistry.parseReply(firstRaw) {
        case .answer(let text):
            return .answer(text)

        case .toolCall(let call):
            guard let tool = toolRegistry.tool(named: call.name) else {
                return .answer(toolRegistry.execute(call))
            }

            if tool.needsPrice(arguments: call.arguments) {
                return .needsPrice(call: call)
            }

            if tool.isMutating {
                return .needsConfirmation(call: call, summary: tool.confirmationSummary(arguments: call.arguments))
            }

            return .answer(try await finalAnswer(prompt: prompt, firstRaw: firstRaw, call: call))
        }
    }

    /// Runs a mutating tool call the user has just approved via the
    /// `.needsConfirmation` prompt, then asks the model to phrase the result
    /// as a final reply. There is no re-parsing of a fresh model turn for
    /// tool selection here — the call itself already came from the model
    /// and was only gated on user approval, not re-decided.
    func resolveConfirmedToolCall(_ call: ToolCall, originalPrompt: String) async throws -> String {
        let rawCallJSON = "{\"tool\": \"\(call.name)\", \"args\": \(jsonString(from: call.arguments))}"
        return try await finalAnswer(prompt: originalPrompt, firstRaw: rawCallJSON, call: call)
    }

    /// Parses `reply` as a bare price number (e.g. "20000", "150 ribu") and
    /// merges it into `call`'s arguments as the pending tool's price
    /// parameter, then routes it through the normal confirm step exactly
    /// like a model-produced call — the caller (ChatScreen) got here from
    /// `.needsPrice` and is holding `call` across this one extra turn since
    /// the model itself has no memory of it. Returns nil (instead of
    /// throwing) when `reply` has no parseable number, so the caller can
    /// re-prompt rather than crash on a stray chat message.
    func resolvePriceReply(_ reply: String, call: ToolCall) -> AgentResponse? {
        guard let price = Self.firstPriceNumber(in: reply) else { return nil }
        guard let tool = toolRegistry.tool(named: call.name) else { return nil }

        let updatedCall = call.addingArgument(price, forKey: "totalCost")
        return .needsConfirmation(call: updatedCall, summary: tool.confirmationSummary(arguments: updatedCall.arguments))
    }

    private static let priceMultiplierAliases: [String: Double] = [
        "ribu": 1_000, "rb": 1_000, "k": 1_000,
        "juta": 1_000_000, "jt": 1_000_000
    ]

    /// Matches a number immediately followed by an optional multiplier
    /// suffix — fused with no space ("50k", "50rb", "50jt") or as a
    /// separate word ("50 k", "150 ribu") — in one pass, so both forms
    /// parse the same way instead of the fused case needing to be split
    /// off before the old whitespace-based word scan could see it.
    private static let priceRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*([a-zA-Z]+)?"#
    )

    private static func firstPriceNumber(in text: String) -> Double? {
        let lowercased = text.lowercased()
        let range = NSRange(lowercased.startIndex..., in: lowercased)

        guard let match = priceRegex.firstMatch(in: lowercased, range: range),
              let numberRange = Range(match.range(at: 1), in: lowercased),
              let number = Double(lowercased[numberRange].replacingOccurrences(of: ",", with: "."))
        else { return nil }

        guard let suffixRange = Range(match.range(at: 2), in: lowercased),
              let multiplier = priceMultiplierAliases[String(lowercased[suffixRange])]
        else { return number }

        return number * multiplier
    }

    private func finalAnswer(prompt: String, firstRaw: String, call: ToolCall) async throws -> String {
        let toolResult = toolRegistry.execute(call)

        let finalPrompt = """
        Tool "\(call.name)" returned:
        \(toolResult)

        Reply with ONLY {"answer": "<your reply to the user in Bahasa Indonesia, using the tool result above>"}
        """

        let finalRaw = try await generate(
            chat: [.system(systemPrompt), .user(prompt), .assistant(firstRaw), .user(finalPrompt)],
            temperature: 0.6
        )

        switch toolRegistry.parseReply(finalRaw) {
        case .answer(let text):
            return text
        case .toolCall:
            // Model tried to chain a second tool call past the one-round
            // cap; fall back to its raw text rather than executing it.
            return finalRaw
        }
    }

    /// Single-call variant of `agenticReply` for the free-N add-stock voice
    /// loop: `prompt` (built by the caller) tells the model it may reply
    /// `{"done": true}` when the user's utterance means they're finished
    /// adding items, in addition to the normal add_stock tool-call/answer
    /// forms. Folding the done-check into the same generate call that
    /// parses the item — instead of a separate dedicated classify call
    /// before it — halves the number of on-device generations per loop
    /// turn, which matters because MLX keeps the model weights and KV cache
    /// resident for the whole Siri session: more generate calls per turn
    /// means more peak memory held for longer, and this app was hitting
    /// iOS's memory limit on multi-item add sessions before this merge.
    ///
    /// Returns `nil` for the "done" case (distinct from `AgentResponse`,
    /// which has no case for it) so the caller can end its loop without
    /// threading a done flag through every `AgentResponse` case elsewhere
    /// (`resolveConfirmedToolCall`, `resolvePriceReply`, ...) that never
    /// needs it.
    func agenticReplyOrDone(to prompt: String) async throws -> AgentResponse? {
        let firstRaw = try await generate(
            chat: [.system(systemPrompt), .user(prompt)],
            temperature: 0.6
        )
        #if DEBUG
        print("[LLMService] agenticReplyOrDone prompt: \(prompt)\n[LLMService] raw: \(firstRaw)")
        #endif

        if Self.isDoneSignal(firstRaw) {
            return nil
        }

        switch toolRegistry.parseReply(firstRaw) {
        case .answer(let text):
            return .answer(text)

        case .toolCall(let call):
            guard let tool = toolRegistry.tool(named: call.name) else {
                return .answer(toolRegistry.execute(call))
            }

            if tool.needsPrice(arguments: call.arguments) {
                return .needsPrice(call: call)
            }

            if tool.isMutating {
                return .needsConfirmation(call: call, summary: tool.confirmationSummary(arguments: call.arguments))
            }

            return .answer(try await finalAnswer(prompt: prompt, firstRaw: firstRaw, call: call))
        }
    }

    /// `{"done": true}` reads as neither `answer` nor `tool` to
    /// `ToolRegistry.parseReply`, so it already falls through to
    /// `.answer(raw trimmed)` — this just recognizes that specific shape
    /// before `agenticReplyOrDone` hands the rest off to the normal parse.
    private static func isDoneSignal(_ raw: String) -> Bool {
        guard let jsonString = extractJSONObject(from: raw),
              let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (object["done"] as? Bool) == true
    }

    /// Scans for the first balanced `{...}` span, same approach as
    /// `ToolRegistry.extractJSONObject` — small models sometimes wrap a
    /// reply in stray text or code fences instead of bare JSON.
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

    private func jsonString(from arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func generate(chat: [Chat.Message], temperature: Float) async throws -> String {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        return try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            // maxTokens/maxKVSize bound how much memory one generation can
            // grow to — every reply here is meant to be short (a JSON tool
            // call or a brief spoken/chat answer, per the system prompt), so
            // there's no normal case that needs more than this, and leaving
            // both unbounded let memory climb enough under Siri's tighter
            // per-invocation ceiling to crash on repeated use.
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: 512, maxKVSize: 1024, temperature: temperature),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }
    }

    struct CachedModel: Identifiable {
        let id: String
        let url: URL
        let sizeBytes: Int64
        let isActive: Bool
    }

    /// Lists every downloaded model repo under Documents/huggingface/models,
    /// e.g. after switching modelId this surfaces the previous model's now-
    /// orphaned weights so the user can reclaim the disk space manually.
    func cachedModels() -> [CachedModel] {
        let modelsRoot = LLMService.downloadBase.appending(component: "models")
        let fm = FileManager.default

        guard let orgDirs = try? fm.contentsOfDirectory(at: modelsRoot, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [CachedModel] = []
        for orgDir in orgDirs {
            guard let repoDirs = try? fm.contentsOfDirectory(at: orgDir, includingPropertiesForKeys: nil) else { continue }
            for repoDir in repoDirs {
                let id = "\(orgDir.lastPathComponent)/\(repoDir.lastPathComponent)"
                results.append(
                    CachedModel(
                        id: id,
                        url: repoDir,
                        sizeBytes: Self.directorySize(repoDir),
                        isActive: id == modelId
                    )
                )
            }
        }
        return results.sorted { $0.id < $1.id }
    }

    /// Deletes one cached model's weights from disk. Throws if it's the
    /// currently loaded model — that would corrupt the live ModelContainer
    /// mid-session; the caller should have the user switch away first, or
    /// this app relaunch after.
    func deleteCachedModel(_ model: CachedModel) throws {
        guard !model.isActive || modelContainer == nil else {
            throw NSError(
                domain: "LLMService", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Tidak bisa menghapus model yang sedang aktif digunakan."]
            )
        }
        try FileManager.default.removeItem(at: model.url)
    }

    func deleteAllCachedModels() throws {
        for model in cachedModels() {
            try deleteCachedModel(model)
        }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
