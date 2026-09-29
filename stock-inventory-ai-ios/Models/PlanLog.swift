//
//  PlanLog.swift
//  stock-inventory-ai-ios
//

import Foundation
import FoundationModels
import SwiftData

enum PlanVerdict: String {
    case unrated
    case good
    case bad
}

/// One planner run, kept on-device as fine-tuning data. Rated in the chat
/// (👍/👎) and exported by `PlanDataset` as chat-format JSONL.
@Model
final class PlanLog {
    var date: Date
    /// Which schema produced it (e.g. "StockPlan") — picks the planner
    /// instructions at export time.
    var planType: String
    var message: String
    var previousMessage: String?
    var planJSON: String
    var verdictRaw: String
    /// What the plan *should* have been, filled in from the 👎 correction
    /// sheet. Together with `planJSON` it forms a chosen/rejected pair.
    var correctedPlanJSON: String?
    /// Free-text "what went wrong" from the user — for reviewing, not training.
    var feedbackNote: String?

    var verdict: PlanVerdict {
        get { PlanVerdict(rawValue: verdictRaw) ?? .unrated }
        set { verdictRaw = newValue.rawValue }
    }

    init(date: Date = .now, planType: String, message: String, previousMessage: String?, planJSON: String, verdict: PlanVerdict = .unrated) {
        self.date = date
        self.planType = planType
        self.message = message
        self.previousMessage = previousMessage
        self.planJSON = planJSON
        self.verdictRaw = verdict.rawValue
        self.correctedPlanJSON = nil
        self.feedbackNote = nil
    }
}

extension PlanLog {
    /// Collect only in debug builds — these are the store owner's raw chat
    /// messages, so release builds never keep them.
    static var isCollectionEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Saves one planner run and returns its ID for rating, or nil when
    /// collection is off or the save fails.
    static func record<P: Generable>(_ plan: P, message: String, previous: String?, in context: ModelContext) -> PersistentIdentifier? {
        guard isCollectionEnabled else { return nil }
        let log = PlanLog(
            planType: String(describing: P.self),
            message: message,
            previousMessage: previous,
            planJSON: plan.generatedContent.jsonString
        )
        context.insert(log)
        do {
            try context.save()
            return log.persistentModelID
        } catch {
            print("[PlanLog] Save failed:", error)
            return nil
        }
    }
}
