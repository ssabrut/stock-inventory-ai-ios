//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents
import SwiftUI

struct AddStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Tambah Stok"
    static var description = IntentDescription("Menambahkan stok barang secara verbal lewat Siri.")

    /// Hard cap on items per Siri session so the loop below can't run
    /// forever if a done-word is never spoken.
    private static let maxItemsPerSession = 10

    /// Words that end the add-items loop when spoken in place of a new item.
    /// Saying "no" to a requestConfirmation(snippetIntent:) turns out to
    /// hard-terminate perform() at the Siri level — any code after it (even
    /// inside a catch) never runs — so the mid-session "add another?" gate
    /// can't be a confirmation at all. A spoken done-word checked against a
    /// requestValue reply sidesteps that entirely: only one confirmation
    /// exists in this flow (the final review), where decline-cancels-all is
    /// the correct behavior anyway.
    private static let doneWords: Set<String> = ["selesai", "cukup", "sudah", "done", "stop"]

    @Parameter(title: "Detail Stok")
    var rawText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Tambah stok: \(\.$rawText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var pending: [LLMService.ParsedStockEntry] = []

        do {
            pending.append(try await LLMService().parseStockPhrase(rawText))
        } catch {
            return .result(dialog: IntentDialog("Maaf, tidak bisa memahami itu. Coba ulangi, misal: tambah 50 gram ayam."))
        }

        // Keep asking for one more item at a time until the user says a
        // done-word or we hit the cap. No confirmation dialog in this loop
        // — see doneWords doc comment for why.
        while pending.count < Self.maxItemsPerSession {
            let dialog = IntentDialog(
                """
                Sudah ditambahkan ke sesi:
                \(Self.formatSummary(pending))

                Sebutkan item berikutnya, atau ucapkan 'selesai' jika sudah.
                """
            )
            let phrase: String
            do {
                phrase = try await $rawText.requestValue(dialog)
            } catch {
                break
            }

            if Self.doneWords.contains(phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                break
            }

            do {
                pending.append(try await LLMService().parseStockPhrase(phrase))
            } catch {
                // Skip an unparseable item rather than aborting the whole session.
                continue
            }
        }

        do {
            try await requestConfirmation(
                actionName: .add,
                dialog: IntentDialog("Tambah \(pending.count) item ke stok, benar?"),
                snippetIntent: ReviewPendingStockSnippet(summary: Self.formatSummary(pending))
            )
        } catch {
            return .result(dialog: IntentDialog("Baik, dibatalkan. Tidak ada stok yang ditambahkan."))
        }

        StockStore.add(pending.map { (itemName: $0.itemName, quantity: $0.quantity, unit: $0.unit) })

        let dialog = IntentDialog("Berhasil menambahkan \(pending.count) item ke stok.")
        return .result(dialog: dialog)
    }

    /// Snippet views only receive @Parameter-wrapped properties across the
    /// confirmation-UI process boundary, and custom-struct arrays would need
    /// AppEntity conformance for that — overkill for this transient session
    /// list, so the list is flattened to one formatted String instead.
    private static func formatSummary(_ pending: [LLMService.ParsedStockEntry]) -> String {
        guard !pending.isEmpty else { return "Belum ada item." }
        return pending
            .map { "• \($0.quantity) \($0.unit) \($0.itemName)" }
            .joined(separator: "\n")
    }
}

/// Final review step before committing: shows every pending item and, via
/// requestConfirmation(snippetIntent:), asks the user to accept or decline
/// the whole batch. This is the only confirmation in the flow.
struct ReviewPendingStockSnippet: SnippetIntent {
    static var title: LocalizedStringResource = "Konfirmasi Stok"

    @Parameter var summary: String

    init() {
        summary = ""
    }

    init(summary: String) {
        self.summary = summary
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: PendingStockSummaryView(title: "Konfirmasi Stok", summary: summary))
    }
}

private struct PendingStockSummaryView: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(summary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
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
