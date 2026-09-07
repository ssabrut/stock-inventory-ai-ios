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
        let quantity: Double
        let unit: String
        /// Original text with the matched quantity+unit span removed, left
        /// for the caller (LLM or otherwise) to turn into an item name.
        let remainingText: String
    }

    /// Maps a recognized unit token (lowercased) to its canonical display form.
    /// Includes common Siri STT misrecognitions/homophones alongside the
    /// canonical spellings (e.g. "kilo" for "kilogram", "liternya" for
    /// "liter") since on-device dictation frequently mangles short unit
    /// words or appends Indonesian suffixes like "-nya".
    private static let unitAliases: [String: String] = [
        "gram": "gram", "gr": "gram", "g": "gram", "gramnya": "gram",
        "kilogram": "kg", "kilo": "kg", "kg": "kg", "kilonya": "kg", "kgnya": "kg",
        "liter": "liter", "litre": "liter", "l": "liter", "liternya": "liter",
        "mililiter": "ml", "milliliter": "ml", "ml": "ml", "mililiternya": "ml",
        "pcs": "pcs", "pc": "pcs", "piece": "pcs", "pieces": "pcs", "piecenya": "pcs",
        "box": "box", "dus": "box", "boks": "box", "dusnya": "box",
        "ikat": "ikat", "bunch": "ikat", "ikatnya": "ikat",
        "butir": "butir", "butirnya": "butir",
        "ekor": "ekor", "ekornya": "ekor",
        "kaleng": "kaleng", "can": "kaleng", "kalengnya": "kaleng",
        "sachet": "sachet", "saset": "sachet", "sachetnya": "sachet",
        "pak": "pak", "pack": "pak", "paknya": "pak"
    ]

    /// Canonical unit values (the alias map's output side), for UI that
    /// needs a fixed picker list rather than free-form text — e.g.
    /// InventoryScreen's add/edit form — instead of duplicating this set.
    static let canonicalUnits: [String] = Array(Set(unitAliases.values)).sorted()

    /// Maps a standalone unit token (already split from its quantity, e.g.
    /// chat's LLM-supplied "gr" or "kilo") to its canonical spelling, or
    /// returns it unchanged if it's not a known alias. Callers that already
    /// have an isolated unit string use this instead of `parse`, which
    /// expects a full quantity+unit phrase — without it, chat's add_stock
    /// merges by whatever raw unit string the LLM happened to emit, so
    /// "500 gr" and "500 gram" land as separate entries instead of merging.
    static func canonicalUnit(_ unit: String) -> String {
        unitAliases[unit.lowercased()] ?? unit
    }

    static func parse(_ text: String) -> Parsed {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [(range: Range<String.Index>, text: String)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append((range, String(text[range])))
            return true
        }

        // Find the first purely-numeric token (handles "150" in "150 gram",
        // "50" in the fused "50gr", and "5.5" in "5.5 kg" — NLTokenizer keeps
        // a decimal point joined to its digits, and splits digits from
        // trailing letters as separate word tokens).
        guard let numberIndex = tokens.firstIndex(where: { Double($0.text) != nil }),
              let quantity = Double(tokens[numberIndex].text)
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
            } else if let canonical = fuzzyUnitMatch(candidate) {
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

    /// Falls back to edit-distance matching when a unit token isn't an exact
    /// alias hit — catches STT mangling (e.g. "graam", "kilogeram") that a
    /// fixed alias list can't enumerate in advance. Only applied to
    /// candidates of length >= 3: shorter unit tokens ("g", "l") sit within
    /// distance 1 of unrelated units ("kg", "ml"), so fuzzy matching them
    /// would misfire more often than it helps.
    private static func fuzzyUnitMatch(_ candidate: String) -> String? {
        guard candidate.count >= 3 else { return nil }

        var best: (unit: String, distance: Int)?
        for known in Set(unitAliases.keys) where known.count >= 3 {
            let distance = levenshteinDistance(candidate, known)
            if distance <= 1, best == nil || distance < best!.distance {
                best = (unitAliases[known]!, distance)
            }
        }
        return best?.unit
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...max(a.count, 1) where a.count > 0 {
            current[0] = i
            for j in 1...max(b.count, 1) where b.count > 0 {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return b.isEmpty ? a.count : previous[b.count]
    }
}
