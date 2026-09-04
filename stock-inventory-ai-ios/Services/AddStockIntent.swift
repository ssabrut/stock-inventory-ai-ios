//
//  AddStockIntent.swift
//  stock-inventory-ai-ios
//

import AppIntents
import SwiftUI

struct AddStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Tambah Stok"
    static var description = IntentDescription("Menambahkan stok barang secara verbal lewat Siri.")

    /// Hard cap on items per Siri session so the confirm/continue chain
    /// below can't run forever if something upstream misbehaves.
    private static let maxItemsPerSession = 10

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

        // Keep asking for one more item at a time, showing the running
        // pending list each turn, until the user declines (requestConfirmation
        // throws on decline) or we hit the cap.
        while pending.count < Self.maxItemsPerSession {
            do {
                try await requestConfirmation(
                    actionName: .add,
                    dialog: IntentDialog("Ditambahkan ke sesi: \(pending.count) item. Tambah item lagi?"),
                    snippetIntent: AddAnotherItemSnippet(summary: Self.formatSummary(pending))
                )
            } catch {
                break
            }

            let dialog = IntentDialog("Sebutkan item berikutnya.")
            let phrase: String
            do {
                phrase = try await $rawText.requestValue(dialog)
            } catch {
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

/// Confirmation step shown between items: displays the running pending list.
/// requestConfirmation(snippetIntent:) renders this view with system
/// accept/decline chrome — accepting resumes AddStockIntent's loop,
/// declining throws (caught by the loop, which then moves to final review).
struct AddAnotherItemSnippet: SnippetIntent {
    static var title: LocalizedStringResource = "Item Berikutnya"

    @Parameter var summary: String

    init() {
        summary = ""
    }

    init(summary: String) {
        self.summary = summary
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: PendingStockSummaryView(title: "Stok Sesi Ini", summary: summary))
    }
}

/// Final review step before committing: shows every pending item and, via
/// requestConfirmation(snippetIntent:), asks the user to accept or decline
/// the whole batch.
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
