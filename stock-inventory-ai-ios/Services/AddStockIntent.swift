//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents

struct AddStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Tambah Stok"
    static var description = IntentDescription("Menambahkan stok barang secara verbal lewat Siri.")

    @Parameter(title: "Detail Stok")
    var rawText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Tambah stok: \(\.$rawText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Siri's own quantity/unit slot-filling tends to default to "1 pcs"
        // on fused phrases like "50gr". Instead we take the whole utterance
        // as free text and let the on-device LLM extract the structured
        // fields, then confirm with the user before writing.
        let parsed: LLMService.ParsedStockEntry
        do {
            parsed = try await LLMService().parseStockPhrase(rawText)
        } catch {
            return .result(dialog: IntentDialog("Maaf, tidak bisa memahami itu. Coba ulangi, misal: tambah 50 gram ayam."))
        }

        let confirmDialog = IntentDialog("Tambah \(parsed.quantity) \(parsed.unit) \(parsed.itemName) ke stok, benar?")

        do {
            try await requestConfirmation(
                actionName: .do,
                dialog: confirmDialog
            )
        } catch {
            return .result(dialog: IntentDialog("Baik, dibatalkan. Silakan ulangi dengan data yang benar."))
        }

        let entry = StockStore.add(itemName: parsed.itemName, quantity: parsed.quantity, unit: parsed.unit)
        let dialog = IntentDialog("Berhasil menambahkan \(entry.quantity) \(entry.unit) \(entry.itemName) ke stok.")
        return .result(dialog: dialog)
    }
}

struct StockAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddStockIntent(),
            phrases: [
                "Tambah stok di \(.applicationName)",
                "Tambah stok pakai \(.applicationName)",
                "Add stock in \(.applicationName)"
            ],
            shortTitle: "Tambah Stok",
            systemImageName: "shippingbox.fill"
        )
    }
}
