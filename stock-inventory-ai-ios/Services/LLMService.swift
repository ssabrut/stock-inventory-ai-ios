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
    enum State: Equatable {
        case idle
        case loading(progress: Double)
        case ready
        case generating
        case failed(String)
    }

    private(set) var state: State = .idle

    private var modelContainer: ModelContainer?
    private let modelId = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    /// Persists downloaded model weights to Documents instead of Caches, so the
    /// ~1GB download survives Xcode debug reinstalls (which can purge Caches).
    private let hub = HubApi(
        downloadBase: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appending(path: "huggingface")
    )

    func loadIfNeeded() async {
        guard modelContainer == nil else { return }
        state = .loading(progress: 0)
        do {
            let factory = LLMModelFactory.shared
            let configuration = ModelConfiguration(id: modelId)
            modelContainer = try await factory.loadContainer(hub: hub, configuration: configuration) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .loading(progress: progress.fractionCompleted)
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
}
