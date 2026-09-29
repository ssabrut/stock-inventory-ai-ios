//
//  MessageFacts.swift
//  stock-inventory-ai-ios
//

import Foundation

/// Deterministic reads of what the user actually typed. The planner can
/// invent values (e.g. copy a price from its own few-shot examples), so any
/// number or date it returns must be traceable back to the text.
enum MessageFacts {
    /// Every number written in the text, with Indonesian shorthand applied:
    /// "70rb" → 70000, "1,5jt" → 1500000, "70.000" → 70000, "1,5" → 1.5.
    static func numbers(in text: String) -> [Double] {
        text.lowercased().matches(of: #/(\d+(?:[.,]\d+)*)\s*(?:(rb|ribu|k|jt|juta)\b)?/#).compactMap { match in
            guard var value = parseNumber(String(match.1)) else { return nil }
            switch match.2.map(String.init) {
            case "rb", "ribu", "k": value *= 1_000
            case "jt", "juta": value *= 1_000_000
            default: break
            }
            return value
        }
    }

    static func mentions(_ value: Double, in text: String) -> Bool {
        numbers(in: text).contains { abs($0 - value) < 0.001 }
    }

    /// Dot followed by 3-digit groups is a thousands separator ("70.000");
    /// otherwise a comma or dot is the decimal mark.
    private static func parseNumber(_ raw: String) -> Double? {
        let groups = raw.split(separator: ".")
        if groups.count > 1, groups.dropFirst().allSatisfy({ $0.count == 3 }) {
            return Double(groups.joined())
        }
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    private static let months: [String: Int] = [
        "januari": 1, "jan": 1, "februari": 2, "feb": 2, "maret": 3, "mar": 3,
        "april": 4, "apr": 4, "mei": 5, "juni": 6, "jun": 6, "juli": 7, "jul": 7,
        "agustus": 8, "agu": 8, "agt": 8, "september": 9, "sep": 9, "sept": 9,
        "oktober": 10, "okt": 10, "november": 11, "nov": 11, "desember": 12, "des": 12,
    ]

    /// Purchase date from phrases like "hari ini", "kemarin", "3 hari lalu",
    /// "28/9", "28-9-2026" or "28 september". Nil when none is found.
    static func purchaseDate(from text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let text = StockKnowledge.normalize(text)
        guard !text.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        func daysAgo(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: -days, to: today) }

        if text.contains("kemarin lusa") { return daysAgo(2) }
        if text.contains("kemarin") || text.contains("kmrn") { return daysAgo(1) }
        if text.contains("hari ini") || text.contains("tadi") || text.contains("barusan") { return today }
        if let match = text.firstMatch(of: #/(\d+)\s*hari\s*(?:yang\s*)?lalu/#), let days = Int(match.1) {
            return daysAgo(days)
        }

        let currentYear = calendar.component(.year, from: today)
        func makeDate(day: Int, month: Int, year: Int?) -> Date? {
            guard (1...31).contains(day), (1...12).contains(month) else { return nil }
            let fullYear = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? currentYear
            guard let date = calendar.date(from: DateComponents(year: fullYear, month: month, day: day)) else { return nil }
            // "28/12" typed in January means last December.
            if year == nil, date > today { return calendar.date(byAdding: .year, value: -1, to: date) }
            return date
        }

        if let match = text.firstMatch(of: #/(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{2,4}))?/#),
           let day = Int(match.1), let month = Int(match.2) {
            return makeDate(day: day, month: month, year: match.3.flatMap { Int($0) })
        }
        for match in text.matches(of: #/(\d{1,2})\s+([a-z]+)(?:\s+(\d{4}))?/#) {
            if let day = Int(match.1), let month = months[String(match.2)] {
                return makeDate(day: day, month: month, year: match.3.flatMap { Int($0) })
            }
        }
        return nil
    }
}
