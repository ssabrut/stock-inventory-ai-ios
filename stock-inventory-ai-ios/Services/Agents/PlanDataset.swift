//
//  PlanDataset.swift
//  stock-inventory-ai-ios
//

import Foundation
import SwiftData

/// Turns rated `PlanLog`s into mlx-lm chat-format JSONL for LoRA fine-tuning:
/// `{"messages":[system, user, assistant]}` per line.
///
/// - `plan-train.jsonl`: 👍 plans, ready to train on.
/// - `plan-review.jsonl`: 👎 plans, same shape — fix the assistant JSON by
///   hand on the Mac, then append the lines to the training file.
enum PlanDataset {
    struct Export: Identifiable {
        let id = UUID()
        let trainURL: URL
        let reviewURL: URL
        let goodCount: Int
        let badCount: Int
    }

    /// Planner instructions per plan type. Uses the *current* prompt, not the
    /// one at logging time — the label (correct plan) doesn't depend on it,
    /// and training should match what ships.
    private static let instructions: [String: String] = [
        String(describing: StockPlan.self): StockPlan.instructions,
    ]

    static func export(from context: ModelContext) throws -> Export {
        let logs = try context.fetch(FetchDescriptor<PlanLog>(sortBy: [SortDescriptor(\.date)]))
        let good = logs.filter { $0.verdict == .good }
        let bad = logs.filter { $0.verdict == .bad }

        let directory = FileManager.default.temporaryDirectory
        let trainURL = directory.appending(path: "plan-train.jsonl")
        let reviewURL = directory.appending(path: "plan-review.jsonl")
        try jsonl(for: good).write(to: trainURL, atomically: true, encoding: .utf8)
        try jsonl(for: bad).write(to: reviewURL, atomically: true, encoding: .utf8)

        return Export(trainURL: trainURL, reviewURL: reviewURL, goodCount: good.count, badCount: bad.count)
    }

    private static func jsonl(for logs: [PlanLog]) throws -> String {
        try logs.compactMap { log -> String? in
            guard let system = instructions[log.planType] else { return nil }
            let record: [String: Any] = [
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": ChatModel.plannerPrompt(text: log.message, previous: log.previousMessage)],
                    ["role": "assistant", "content": log.planJSON],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
        .joined(separator: "\n")
    }
}
