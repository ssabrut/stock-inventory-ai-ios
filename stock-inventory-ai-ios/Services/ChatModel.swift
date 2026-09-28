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

/// App-wide singleton rather than view-local `@State`: `ContentView` swaps
/// screens with a `switch`, which destroys `ChatScreen` (and anything it owns)
/// on every navigation. Owning the model here keeps the loaded engine alive
/// for the whole app run, and lets loading start at launch instead of when
/// the chat screen first opens.
@Observable
final class ChatModel {
    static let shared = ChatModel(modelURL: ChatModel.bundledModelURL())

    enum LoadState: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var isGenerating = false

    private var model: CoreAILanguageModel?
    private var session: LanguageModelSession?
    private let modelURL: URL

    /// Qwen3 "thinks" before answering by default, and that reasoning is hidden
    /// from `snapshot.content` — the user just sees nothing for a long time.
    /// CoreAI maps the "none" level to `enable_thinking: false` in the chat template.
    private static let contextOptions = ContextOptions(reasoningLevel: .custom("none"))

    private init(modelURL: URL) {
        self.modelURL = modelURL
    }

    private static func bundledModelURL() -> URL {
        let name = "qwen3_0_6b_mixed_4bit_8bit_static"
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            fatalError("Model resource '\(name)' not found in bundle.")
        }
        return url
    }

    /// Slow only the first time after install (or after an iOS update): Core AI
    /// specializes the model for this device and caches the result in the app's
    /// Caches directory. Later launches reuse that cache, leaving just the
    /// weight load + warmup.
    func loadIfNeeded() async {
        guard loadState == .idle else { return }
        loadState = .preparing
        do {
            let start = ContinuousClock.now
            // Eager: load the engine now instead of on the first message.
            let model = try await CoreAILanguageModel(resourcesAt: modelURL, mode: .eager)
            print("[ChatModel] Model loaded in", ContinuousClock.now - start)
            self.model = model
            session = LanguageModelSession(model: model)
            loadState = .ready
        } catch {
            print("[ChatModel] Load failed:", error)
            loadState = .failed(error.localizedDescription)
        }
    }
    
    nonisolated static func isModelCached() -> Bool {
        let aimodel = bundledModelURL()
            .appending(path: "qwen3_0_6b_mixed_4bit_8bit_static.aimodel")
        return PreparedModel.isCached(at: aimodel)
    }

    /// Drops the conversation history but keeps the loaded model, so a fresh
    /// chat costs nothing. No-op until loading finishes (which already starts
    /// with a fresh session).
    func startNewConversation() {
        guard let model else { return }
        session = LanguageModelSession(model: model)
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
