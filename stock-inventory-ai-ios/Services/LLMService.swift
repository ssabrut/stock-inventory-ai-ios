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
    private let modelId = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
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
        "ribu": 1_000, "rb": 1_000,
        "juta": 1_000_000, "jt": 1_000_000
    ]

    private static func firstPriceNumber(in text: String) -> Double? {
        let words = text.lowercased().split(separator: " ").map(String.init)

        guard let numberIndex = words.firstIndex(where: { Double($0) != nil }),
              let number = Double(words[numberIndex])
        else { return nil }

        if words.indices.contains(numberIndex + 1),
           let multiplier = priceMultiplierAliases[words[numberIndex + 1]] {
            return number * multiplier
        }
        return number
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
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: temperature),
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

    struct ParsedStockEntry: Decodable {
        let itemName: String
        let quantity: Double
        let unit: String
    }

    /// Classifies whether a spoken segment signals the end of an add-stock
    /// session (e.g. "selesai", "okay done", "udah segitu aja", "that's all")
    /// rather than another item to add. Used by StockSessionOverlay's
    /// continuous-listening flow so the done-signal isn't limited to a fixed
    /// word list — free-form phrasing works the way Siri's own "no more
    /// items" gate would.
    func isDoneIntent(_ text: String) async throws -> Bool {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        You detect whether the user's utterance means they are DONE adding stock \
        (e.g. "done", "that's all", "okay I'm finished", "no more"), rather than \
        naming another item. Reply with ONLY "yes" if it's a done-signal, or "no" \
        if it's still naming a stock item (e.g. "50 grams of chicken").
        """

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(text)
        ]

        let raw = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        return raw.lowercased().contains("yes")
    }

    /// Classifies a spoken reply to a yes/no question as affirmative or not,
    /// for free-form phrasing ("iya", "betul", "yoi", "nggak", "salah itu")
    /// rather than a fixed word list. `question` is included so the model
    /// judges the reply in context (e.g. "benar?" vs "mau tambah lagi?") —
    /// used by StockSessionOverlay's per-item confirm and continue-session
    /// prompts.
    func classifyYesNo(reply: String, question: String) async throws -> Bool {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        The user was just asked: "\(question)". Reply with ONLY "yes" if their answer \
        is affirmative/agreeing (e.g. "yes", "yeah", "correct", "right"), or "no" if \
        their answer is negative/disagreeing (e.g. "no", "nope", "that's wrong", "not that").
        """

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(reply)
        ]

        let raw = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        return raw.lowercased().contains("yes")
    }

    /// Extracts item name/quantity/unit from a free-text stock phrase, e.g.
    /// "50gr of chicken" -> {itemName: "chicken", quantity: 50, unit: "gr"}.
    /// Used by AddStockIntent so Siri can take one free-text parameter
    /// instead of relying on its own quantity/unit slot-filling, which
    /// tends to default to "1 pcs" on fused phrases like "50gr".
    ///
    /// Quantity/unit come from StockPhraseParser (deterministic, dictionary
    /// based) rather than the LLM — the LLM was unreliable at extracting
    /// units, e.g. it would drop an explicit "gram" and default to "pcs"
    /// despite being told not to. The LLM here only cleans up the
    /// leftover text into an item name, a task it's better suited for.
    func parseStockPhrase(_ text: String) async throws -> ParsedStockEntry {
        let parsed = StockPhraseParser.parse(text)

        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        Clean up this text into a tidy inventory item name. \
        Reply with ONLY the item name, no quotes, no other explanation.
        """

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(parsed.remainingText)
        ]

        let raw = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        let itemName = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        guard !itemName.isEmpty else {
            throw NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse item name"])
        }

        return ParsedStockEntry(itemName: itemName, quantity: parsed.quantity, unit: parsed.unit)
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
