//
//  YesNoClassifier.swift
//  stock-inventory-ai-ios
//

import Foundation
import NaturalLanguage

/// Classifies a free-text reply as yes/no/unclear using on-device sentence
/// embeddings (`NLEmbedding.sentenceEmbedding`) instead of exact/fuzzy
/// string matching against a fixed choice list. Built for
/// `StockAgentIntent.confirmTranscript`, whose confirm step used to route
/// through `requestDisambiguation(among: ["Yes correct", "No fix it"])` —
/// that only resolves when the spoken reply matches the literal choice
/// text closely enough, and hung indefinitely on a natural phrase like
/// "yes, that's correct". Sentence embeddings measure semantic similarity
/// instead, so "yep that's right", "correct", "nah try again", etc. all
/// classify without needing to anticipate every phrasing up front.
///
/// Ships as part of the OS (Natural Language framework) — no model
/// download, no GPU, no dependency beyond the framework import.
enum YesNoClassifier {
    enum Result {
        case yes
        case no
        /// Neither anchor set was clearly closer — callers should treat
        /// this the same as `.no` (re-ask) rather than guess.
        case unclear
    }

    /// Anchor phrases for each side — a handful of natural variants rather
    /// than a single word, since sentence embeddings are more reliable
    /// comparing whole phrases than single tokens, and this averages out
    /// any one anchor's quirks.
    private static let yesAnchors = ["yes", "yes that's correct", "yeah that's right", "correct", "that's right", "yep"]
    private static let noAnchors = ["no", "no that's wrong", "that's not right", "incorrect", "let me fix it", "nope"]

    private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    /// Distance threshold beyond which neither side counts as a confident
    /// match — `NLEmbedding.distance` is a cosine distance where 0 means
    /// identical and 2 means unrelated/out-of-vocabulary; 1.0 is the
    /// midpoint and works as a practical "too far to call" cutoff.
    private static let unclearThreshold = 1.0

    static func classify(_ reply: String) -> Result {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .unclear }

        guard let embedding else {
            // No embedding model available on this OS/locale (shouldn't
            // happen on any iOS 26 device, but degrade gracefully rather
            // than crash) — fall back to a simple prefix check.
            if text.hasPrefix("yes") || text.hasPrefix("yeah") || text.hasPrefix("yep") { return .yes }
            if text.hasPrefix("no") || text.hasPrefix("nope") { return .no }
            return .unclear
        }

        let yesDistance = averageDistance(from: text, to: yesAnchors, using: embedding)
        let noDistance = averageDistance(from: text, to: noAnchors, using: embedding)

        guard min(yesDistance, noDistance) <= unclearThreshold else { return .unclear }
        return yesDistance < noDistance ? .yes : .no
    }

    private static func averageDistance(from text: String, to anchors: [String], using embedding: NLEmbedding) -> Double {
        let distances = anchors.map { embedding.distance(between: text, and: $0) }
        return distances.reduce(0, +) / Double(distances.count)
    }
}
