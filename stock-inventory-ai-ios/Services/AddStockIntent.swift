//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents

struct AddStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Tambah Stok"
    static var description = IntentDescription("Menambahkan stok barang secara verbal lewat Siri.")

    @Parameter(title: "Nama Barang")
    var itemName: String

    @Parameter(title: "Jumlah", default: 1)
    var quantity: Int

    @Parameter(title: "Satuan", default: "pcs")
    var unit: String

    static var parameterSummary: some ParameterSummary {
        Summary("Tambah \(\.$quantity) \(\.$unit) \(\.$itemName) ke stok")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let confirmDialog = IntentDialog("Tambah \(quantity) \(unit) \(itemName) ke stok, benar?")

        do {
            try await requestConfirmation(
                actionName: .do,
                dialog: confirmDialog
            )
        } catch {
            return .result(dialog: IntentDialog("Baik, dibatalkan. Silakan ulangi dengan data yang benar."))
        }

        let entry = StockStore.add(itemName: itemName, quantity: quantity, unit: unit)
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
