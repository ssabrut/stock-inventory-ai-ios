//
//  StockPhraseParser.swift
//  stock-inventory-ai-ios
//

import Foundation
import NaturalLanguage

/// Deterministically extracts quantity + unit from a free-text stock phrase
/// using NLTagger for word/number tokenization plus a known-units lookup,
/// instead of asking the LLM to guess them. The LLM (see LLMService) was
/// unreliable at this — it would drop an explicitly stated unit like "gram"
/// and default to "pcs" despite being told not to. Quantity/unit is a small,
/// closed vocabulary domain, so a dictionary match is a better fit than an
/// open-ended generative guess.
enum StockPhraseParser {
    struct Parsed {
        let quantity: Int
        let unit: String
        /// Original text with the matched quantity+unit span removed, left
        /// for the caller (LLM or otherwise) to turn into an item name.
        let remainingText: String
    }

    /// Maps a recognized unit token (lowercased) to its canonical display form.
    private static let unitAliases: [String: String] = [
        "gram": "gram", "gr": "gram", "g": "gram",
        "kilogram": "kg", "kg": "kg",
        "liter": "liter", "litre": "liter", "l": "liter",
        "mililiter": "ml", "milliliter": "ml", "ml": "ml",
        "pcs": "pcs", "pc": "pcs", "piece": "pcs", "pieces": "pcs",
        "box": "box", "dus": "box",
        "ikat": "ikat", "bunch": "ikat",
        "butir": "butir",
        "ekor": "ekor",
        "kaleng": "kaleng", "can": "kaleng",
        "sachet": "sachet", "saset": "sachet",
        "pak": "pak", "pack": "pak"
    ]

    static func parse(_ text: String) -> Parsed {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [(range: Range<String.Index>, text: String)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append((range, String(text[range])))
            return true
        }

        // Find the first purely-numeric token (handles "150" in "150 gram"
        // and "50" in the fused "50gr" — NLTokenizer splits digits from
        // trailing letters as separate word tokens).
        guard let numberIndex = tokens.firstIndex(where: { Int($0.text) != nil }),
              let quantity = Int(tokens[numberIndex].text)
        else {
            return Parsed(quantity: 1, unit: "pcs", remainingText: text)
        }

        // Unit is expected immediately after the number (allowing the fused
        // "50gr" case where NLTokenizer still splits "50" and "gr" adjacently).
        var unit = "pcs"
        var consumedIndices: Set<Int> = [numberIndex]
        if tokens.indices.contains(numberIndex + 1) {
            let candidate = tokens[numberIndex + 1].text.lowercased()
            if let canonical = unitAliases[candidate] {
                unit = canonical
                consumedIndices.insert(numberIndex + 1)
            }
        }

        var remaining = ""
        for (index, token) in tokens.enumerated() where !consumedIndices.contains(index) {
            if !remaining.isEmpty { remaining += " " }
            remaining += token.text
        }

        return Parsed(quantity: quantity, unit: unit, remainingText: remaining)
    }
}
