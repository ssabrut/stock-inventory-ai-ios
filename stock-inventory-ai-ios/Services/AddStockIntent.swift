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
    static var title: LocalizedStringResource = "Tambah Stok"
    static var description = IntentDescription("Membuka Invent dan mulai sesi tambah stok lewat suara.")
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
                "Tambah stok di \(.applicationName)",
                "Tambah stok pakai \(.applicationName)",
                "Tambah stok gram di \(.applicationName)",
                "Tambah stok kilogram di \(.applicationName)",
                "Tambah stok liter di \(.applicationName)",
                "Tambah stok pcs di \(.applicationName)",
                "Tambah stok box di \(.applicationName)",
                "Saya mau tambah stok di \(.applicationName)",
                "Saya ingin menambahkan stok di \(.applicationName)",
                "Tolong tambah stok di \(.applicationName)",
                "Add stock in \(.applicationName)",
                "I want to add stock in \(.applicationName)",
                "I'd like to add stock to \(.applicationName)",
                "Help me add stock in \(.applicationName)"
            ],
            shortTitle: "Tambah Stok",
            systemImageName: "shippingbox.fill"
        )
    }
}
