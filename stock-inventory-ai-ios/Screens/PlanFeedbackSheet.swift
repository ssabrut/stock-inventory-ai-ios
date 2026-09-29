//
//  PlanFeedbackSheet.swift
//  stock-inventory-ai-ios
//

import SwiftUI
import SwiftData
import FoundationModels

/// Opened by 👎 on a chat reply. The user writes what went wrong and fills in
/// the plan the AI *should* have made — stored as `correctedPlanJSON`, which
/// becomes training data (SFT) and a chosen/rejected pair (preference tuning).
struct PlanFeedbackSheet: View {
    let log: PlanLog

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var note = ""
    @State private var intent: StockIntent = .other
    @State private var itemsText = ""
    @State private var quantityText = ""
    @State private var unit = ""
    @State private var totalCostText = ""
    @State private var dateText = ""
    @State private var daysText = "7"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apa yang salah?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Catatan")
                } footer: {
                    Text("Pesan: \(log.message)")
                }

                Section {
                    Picker("Maksud", selection: $intent) {
                        ForEach(StockIntent.allCases, id: \.self) { intent in
                            Text(String(describing: intent)).tag(intent)
                        }
                    }
                    TextField("Bahan (pisahkan dengan koma)", text: $itemsText)
                    TextField("Jumlah", text: $quantityText)
                        .keyboardType(.decimalPad)
                    TextField("Satuan", text: $unit)
                    TextField("Total harga (mis. 70rb)", text: $totalCostText)
                    TextField("Tanggal beli, seperti yang ditulis (mis. kemarin)", text: $dateText)
                    TextField("Hari ke belakang (riwayat)", text: $daysText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Rencana yang benar")
                } footer: {
                    Text("Isi hanya yang benar-benar ditulis di pesan. Kosongkan jika tidak disebut.")
                }

                Section("Rencana AI") {
                    Text(log.planJSON)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Koreksi AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                }
            }
        }
        .onAppear(perform: prefill)
    }

    /// Starts from an earlier correction if there is one, else from the AI's
    /// own plan — usually only one or two fields need changing.
    private func prefill() {
        note = log.feedbackNote ?? ""
        guard let content = try? GeneratedContent(json: log.correctedPlanJSON ?? log.planJSON),
              let plan = try? StockPlan(content)
        else { return }
        intent = plan.intent
        itemsText = plan.items.joined(separator: ", ")
        quantityText = plan.quantity > 0 ? formatQuantity(plan.quantity) : ""
        unit = plan.unit
        totalCostText = plan.totalCost > 0 ? formatQuantity(plan.totalCost) : ""
        dateText = plan.dateText
        daysText = String(plan.days)
    }

    private func save() {
        let items = itemsText
            .split(separator: ",")
            .map { StockKnowledge.normalize(String($0)) }
            .filter { !$0.isEmpty }
        // Same keys, same order as `StockPlan` — this JSON is a training target.
        let corrected = GeneratedContent(properties: [
            "intent": intent,
            "items": items,
            "quantity": MessageFacts.numbers(in: quantityText).first ?? 0,
            "unit": StockKnowledge.normalizeUnit(unit),
            "totalCost": MessageFacts.numbers(in: totalCostText).first ?? 0,
            "dateText": dateText.trimmingCharacters(in: .whitespacesAndNewlines),
            "days": min(max(Int(daysText) ?? 7, 1), 365),
        ])

        log.correctedPlanJSON = corrected.jsonString
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        log.feedbackNote = trimmedNote.isEmpty ? nil : trimmedNote
        log.verdict = .bad
        try? modelContext.save()
        dismiss()
    }
}
