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
    private static let instructions = """
    You are the stock assistant for a small Indonesian food business.
    Always answer in Bahasa Indonesia, short and clear.
    For ANY question about ingredients, stock, cost or usage, call a tool first. Never guess numbers.
    Only call record_stock when the user clearly asks to add or use stock.
    If a tool finds nothing, say so. Never invent ingredients.
    """
    
    private static let responderInstructions = """
    You are the stock assistant for a small Indonesian food business.
    Answer in Bahasa Indonesia, 1-3 short sentences.
    Use ONLY numbers from "Data stok". If the data does not answer the question, say you don't have that data.
    If there is no data and the message is small talk, reply briefly and offer help with stock.
    """

    enum LoadState: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }
    
    private static let plannerContext = ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .custom("none"))

    private(set) var lastTrace: [String] = []


    private(set) var loadState: LoadState = .idle
    private(set) var isGenerating = false
    private(set) var lastToolCalls: [String] = []

    private var model: CoreAILanguageModel?
    private let modelURL: URL

    /// Qwen3 "thinks" before answering by default, and that reasoning is hidden
    /// from `snapshot.content` — the user just sees nothing for a long time.
    /// CoreAI maps the "none" level to `enable_thinking: false` in the chat template.
    private static let contextOptions = ContextOptions(reasoningLevel: .custom("none"))

    private init(modelURL: URL) {
        self.modelURL = modelURL
    }

    private static func bundledModelURL() -> URL {
        let name = "qwen3_1_7b_6bit_static"
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            fatalError("Model resource '\(name)' not found in bundle.")
        }
        return url
    }
    
    func plan<P: Generable>(_ type: P.Type, instructions: String, text: String, previous: String?) async throws -> P {
        guard let model else { throw ChatModelError.notReady }
        isGenerating = true
        defer { isGenerating = false }

        let planner = LanguageModelSession(model: model, instructions: instructions)
        var prompt = ""
        if let previous { prompt += "Previous message: \(previous)\n" }
        prompt += "Message: \(text)"

        let plan = try await planner.respond(
            to: prompt, generating: P.self,
            options: GenerationOptions(sampling: .greedy),
            contextOptions: Self.plannerContext
        ).content
        lastTrace = ["plan: \(plan.generatedContent.jsonString)"]
        print("[ChatModel]", lastTrace[0])
        return plan
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
            loadState = .ready
        } catch {
            print("[ChatModel] Load failed:", error)
            loadState = .failed(error.localizedDescription)
        }
    }
    
    nonisolated static func isModelCached() -> Bool {
        let aimodel = bundledModelURL()
            .appending(path: "qwen3_1_7b_6bit_static.aimodel")
        return PreparedModel.isCached(at: aimodel)
    }
    
    func streamAnswer(question: String, facts: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let model else {
                    continuation.finish(throwing: ChatModelError.notReady)
                    return
                }
                // Fresh every turn: facts never pile up in a transcript, so no
                // context-window overflow and no stale numbers from earlier turns.
                let responder = LanguageModelSession(model: model, instructions: Self.responderInstructions)
                let prompt = facts.isEmpty ? question : "Data stok:\n\(facts)\n\nPertanyaan: \(question)"
                if !facts.isEmpty { lastTrace.append(facts) }

                isGenerating = true
                defer { isGenerating = false }
                do {
                    let stream = responder.streamResponse(to: prompt, contextOptions: Self.contextOptions)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
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
