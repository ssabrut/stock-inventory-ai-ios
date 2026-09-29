//
//  PlanDataset.swift
//  stock-inventory-ai-ios
//

import Foundation
import FoundationModels
import SwiftData

/// Turns rated `PlanLog`s into JSONL for fine-tuning.
///
/// - `plan-train.jsonl` (SFT, mlx-lm chat format `{"messages":[system,user,assistant]}`):
///   👍 plans as-is, plus 👎 plans that were corrected in the app (corrected JSON).
/// - `plan-review.jsonl`: 👎 plans *not* corrected yet, same shape plus a
///   `feedback` note — fix the assistant JSON by hand, drop `feedback`, then merge.
/// - Preference pairs (DPO/RLHF) from corrected 👎 plans, in two formats:
///   - `plan-preference.jsonl` — TRL conversational:
///     `{"prompt":[system,user],"chosen":[assistant],"rejected":[assistant]}`
///   - `plan-preference-mlx.jsonl` — mlx-lm-lora (`--train-mode dpo`):
///     `{"system":…,"prompt":…,"chosen":…,"rejected":…}` as plain strings.
///
/// Logs whose JSON no longer fits the current schema (e.g. made before a
/// field was added) are skipped, so old data never trains a stale shape.
enum PlanDataset {
    struct Export: Identifiable {
        let id = UUID()
        let trainURL: URL
        let reviewURL: URL
        let preferenceURL: URL
        let preferenceMLXURL: URL
        let trainCount: Int
        let reviewCount: Int
        let preferenceCount: Int
        let skippedCount: Int

        var urls: [URL] { [trainURL, reviewURL, preferenceURL, preferenceMLXURL] }
    }

    private struct PlanSpec {
        let instructions: String
        let isValid: (String) -> Bool
    }

    /// Per plan type: the *current* planner prompt (training should match what
    /// ships) and a check that a JSON string still decodes into the schema.
    private static let specs: [String: PlanSpec] = [
        String(describing: StockPlan.self): PlanSpec(
            instructions: StockPlan.instructions,
            isValid: { json in (try? GeneratedContent(json: json)).flatMap { try? StockPlan($0) } != nil }
        ),
    ]

    static func export(from context: ModelContext) throws -> Export {
        let logs = try context.fetch(FetchDescriptor<PlanLog>(sortBy: [SortDescriptor(\.date)]))
        var train: [String] = []
        var review: [String] = []
        var preference: [String] = []
        var preferenceMLX: [String] = []
        var skipped = 0

        for log in logs where log.verdict != .unrated {
            guard let spec = specs[log.planType] else { skipped += 1; continue }
            let userPrompt = ChatModel.plannerPrompt(text: log.message, previous: log.previousMessage)
            let prompt: [[String: String]] = [
                ["role": "system", "content": spec.instructions],
                ["role": "user", "content": userPrompt],
            ]

            switch (log.verdict, log.correctedPlanJSON) {
            case (.good, _):
                guard spec.isValid(log.planJSON) else { skipped += 1; continue }
                train.append(try line(["messages": prompt + [assistant(log.planJSON)]]))

            case (.bad, let corrected?):
                guard spec.isValid(corrected) else { skipped += 1; continue }
                train.append(try line(["messages": prompt + [assistant(corrected)]]))
                // A rejected plan of an older shape is still a valid "don't do this".
                preference.append(try line([
                    "prompt": prompt,
                    "chosen": [assistant(corrected)],
                    "rejected": [assistant(log.planJSON)],
                ]))
                preferenceMLX.append(try line([
                    "system": spec.instructions,
                    "prompt": userPrompt,
                    "chosen": corrected,
                    "rejected": log.planJSON,
                ]))

            case (.bad, nil):
                var record: [String: Any] = ["messages": prompt + [assistant(log.planJSON)]]
                if let note = log.feedbackNote { record["feedback"] = note }
                review.append(try line(record))

            default:
                break
            }
        }

        let directory = FileManager.default.temporaryDirectory
        let trainURL = directory.appending(path: "plan-train.jsonl")
        let reviewURL = directory.appending(path: "plan-review.jsonl")
        let preferenceURL = directory.appending(path: "plan-preference.jsonl")
        let preferenceMLXURL = directory.appending(path: "plan-preference-mlx.jsonl")
        try train.joined(separator: "\n").write(to: trainURL, atomically: true, encoding: .utf8)
        try review.joined(separator: "\n").write(to: reviewURL, atomically: true, encoding: .utf8)
        try preference.joined(separator: "\n").write(to: preferenceURL, atomically: true, encoding: .utf8)
        try preferenceMLX.joined(separator: "\n").write(to: preferenceMLXURL, atomically: true, encoding: .utf8)

        return Export(
            trainURL: trainURL, reviewURL: reviewURL,
            preferenceURL: preferenceURL, preferenceMLXURL: preferenceMLXURL,
            trainCount: train.count, reviewCount: review.count,
            preferenceCount: preference.count, skippedCount: skipped
        )
    }

    private static func assistant(_ content: String) -> [String: String] {
        ["role": "assistant", "content": content]
    }

    private static func line(_ record: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
