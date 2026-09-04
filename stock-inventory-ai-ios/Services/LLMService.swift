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

    /// Persists downloaded model weights to Documents instead of Caches, so the
    /// ~1GB download survives Xcode debug reinstalls (which can purge Caches).
    /// HF token is baked in from Secrets.xcconfig (gitignored) at build time via
    /// INFOPLIST_KEY_HFToken, never a scheme env var, so it can't leak into git.
    private let hub = HubApi(
        downloadBase: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appending(path: "huggingface"),
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

    func reply(to prompt: String, stockContext: String? = nil) async throws -> String {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        var systemPrompt = "Kamu adalah asisten AI untuk aplikasi manajemen stok inventori. Jawab singkat, jelas, dan dalam Bahasa Indonesia."
        if let stockContext {
            systemPrompt += "\n\nData stok saat ini:\n\(stockContext)"
        }

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(prompt)
        ]

        let result = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.6),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        return result
    }

    struct ParsedStockEntry: Decodable {
        let itemName: String
        let quantity: Int
        let unit: String
    }

    /// Extracts item name/quantity/unit from a free-text stock phrase, e.g.
    /// "50gr of chicken" -> {itemName: "chicken", quantity: 50, unit: "gr"}.
    /// Used by AddStockIntent so Siri can take one free-text parameter
    /// instead of relying on its own quantity/unit slot-filling, which
    /// tends to default to "1 pcs" on fused phrases like "50gr".
    func parseStockPhrase(_ text: String) async throws -> ParsedStockEntry {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        Ekstrak nama barang, jumlah, dan satuan dari teks stok gudang. \
        Balas HANYA dengan JSON valid tanpa teks lain, format: \
        {"itemName": string, "quantity": integer, "unit": string}. \
        Jika satuan tidak disebutkan, gunakan "pcs". Jika jumlah tidak disebutkan, gunakan 1.
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

        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}")
        else {
            throw NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse stock phrase"])
        }

        let jsonSubstring = raw[jsonStart...jsonEnd]
        let data = Data(jsonSubstring.utf8)
        return try JSONDecoder().decode(ParsedStockEntry.self, from: data)
    }
}
