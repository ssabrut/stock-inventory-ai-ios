//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents

/// Triggered by Siri to start an add-stock session. Foregrounds the app
/// (openAppWhenRun) and marks the session active in SiriSessionState;
/// StockSessionOverlay observes that, auto-expands its floating card, and
/// starts listening via VoiceStockService — all the parsing/multi-item/
/// confirm UX now lives in-app instead of Siri's own conversation loop, so
/// this intent has no parameters and no dialog of its own.
struct AddStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Stock"
    static var description = IntentDescription("Opens Invent and starts a voice add-stock session.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SiriSessionState.begin(source: .siri)
        return .result()
    }
}

struct StockAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddStockIntent(),
            phrases: [
                "Add stock in \(.applicationName)",
                "Add stock using \(.applicationName)",
                "Add stock in grams in \(.applicationName)",
                "Add stock in kilograms in \(.applicationName)",
                "Add stock in liters in \(.applicationName)",
                "Add stock in pieces in \(.applicationName)",
                "Add stock in boxes in \(.applicationName)",
                "I want to add stock in \(.applicationName)",
                "I'd like to add stock to \(.applicationName)",
                "Help me add stock in \(.applicationName)",
                "Please add stock in \(.applicationName)"
            ],
            shortTitle: "Add Stock",
            systemImageName: "shippingbox.fill"
        )
    }
}
