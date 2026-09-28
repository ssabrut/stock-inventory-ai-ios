//
//  ChatModel.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 28/09/26.
//

import Foundation
import FoundationModels
import Observation
import CoreAILanguageModels

@Observable
final class ChatModel {
    enum LoadState: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }
    
    private(set) var loadState: LoadState = .idle
    private(set) var isGenerating = false
    
    private var session: LanguageModelSession?
    private let modelURL: URL

    /// Qwen3 "thinks" before answering by default, and that reasoning is hidden
    /// from `snapshot.content` — the user just sees nothing for a long time.
    /// CoreAI maps the "none" level to `enable_thinking: false` in the chat template.
    private static let contextOptions = ContextOptions(reasoningLevel: .custom("none"))

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func loadIfNeeded() async {
        guard loadState == .idle else { return }
        loadState = .preparing
        do {
            let start = ContinuousClock.now
            // Eager: load the engine now (while "Menyiapkan AI…" shows)
            // instead of on the first message.
            let model = try await CoreAILanguageModel(resourcesAt: modelURL, mode: .eager)
            print("[ChatModel] Model loaded in", ContinuousClock.now - start)
            session = LanguageModelSession(model: model)
            loadState = .ready
        } catch {
            print("[ChatModel] Load failed:", error)
            loadState = .failed(error.localizedDescription)
        }
    }
    
    func respond(to prompt: String) async throws -> String {
        guard let session else {
            throw ChatModelError.notReady
        }
        isGenerating = true
        defer { isGenerating = false }
        let response = try await session.respond(to: prompt, contextOptions: Self.contextOptions)
        return response.content
    }
    
    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let session else {
                    continuation.finish(throwing: ChatModelError.notReady)
                    return
                }
                
                isGenerating = true
                defer { isGenerating = false }
                do {
                    let start = ContinuousClock.now
                    var sawFirstText = false
                    let stream = session.streamResponse(to: prompt, contextOptions: Self.contextOptions)
                    for try await snapshot in stream {
                        if !sawFirstText && !snapshot.content.isEmpty {
                            sawFirstText = true
                            print("[ChatModel] First text after", ContinuousClock.now - start)
                        }
                        continuation.yield(snapshot.content)
                    }
                    print("[ChatModel] Finished after", ContinuousClock.now - start)
                    continuation.finish()
                } catch {
                    print("[ChatModel] Generation failed:", error)
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum ChatModelError: LocalizedError {
    case notReady
    var errorDescription: String? {
        "The AI model isn't ready yet!"
    }
}
