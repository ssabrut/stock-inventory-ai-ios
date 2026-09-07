//
//  InventoryScreen.swift
//  stock-inventory-ai-ios
//

import CoreData
import SwiftUI

struct InventoryScreen: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \StockEntryEntity.itemName, ascending: true)]
    )
    private var entries: FetchedResults<StockEntryEntity>

    @State private var editingEntry: StockEntryEntity?
    @State private var isAddingNew = false
    @State private var usingEntry: StockEntryEntity?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Stok Bahan")
                    .font(.title2.bold())
                Spacer()
                Text("\(entries.count) item")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    isAddingNew = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Stok",
                    systemImage: "shippingbox",
                    description: Text("Tambahkan stok lewat Siri, chat AI, atau tombol +.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        InventoryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingEntry = entry
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Hapus", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    usingEntry = entry
                                } label: {
                                    Label("Pakai", systemImage: "minus.circle")
                                }
                                .tint(.orange)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editingEntry) { entry in
            StockEntryFormSheet(mode: .edit(entry))
        }
        .sheet(isPresented: $isAddingNew) {
            StockEntryFormSheet(mode: .create)
        }
        .sheet(item: $usingEntry) { entry in
            UseStockSheet(entry: entry)
        }
    }

    private func delete(_ entry: StockEntryEntity) {
        guard let id = entry.id else { return }
        StockStore.delete(id: id)
    }
}

/// "Pakai" (use/sell) sheet — records stock going out at its current
/// weighted-average cost, logging a `.remove` transaction that feeds COGS.
/// Kept separate from the edit form since this is a usage event, not a data
/// correction (see StockStore.use vs StockStore.update/delete).
private struct UseStockSheet: View {
    let entry: StockEntryEntity

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String = ""
    @State private var errorMessage: String?

    private var availableQuantity: Double { entry.quantity }

    private var parsedQuantity: Double? {
        guard let value = Double(quantityText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard let value = parsedQuantity else { return false }
        return value <= availableQuantity
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Stok saat ini", value: "\(formatQuantity(availableQuantity)) \(entry.unit ?? "")")
                    TextField("Jumlah terpakai", text: $quantityText)
                        .keyboardType(.decimalPad)
                } footer: {
                    if let value = parsedQuantity, value > availableQuantity {
                        Text("Jumlah melebihi stok yang tersedia.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Dicatat sebagai stok keluar seharga \(formatQuantity(entry.costPerUnit)) per \(entry.unit ?? "").")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Pakai \(entry.itemName ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let id = entry.id, let quantity = parsedQuantity else { return }
        guard StockStore.use(id: id, quantity: quantity) else {
            errorMessage = "Gagal menyimpan. Coba lagi."
            return
        }
        dismiss()
    }
}

private struct InventoryRow: View {
    let entry: StockEntryEntity

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.itemName ?? "")
                    .font(.headline)
                if let date = entry.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(formatQuantity(entry.quantity)) \(entry.unit ?? "")")
                .font(.subheadline.bold())
        }
        .padding(.vertical, 6)
    }
}

/// Shared create/edit form. StockEntryEntity is a live Core Data object, not
/// a value type, so .edit holds it just for its id/prefill values — all
/// writes go through StockStore rather than mutating the entity directly, to
/// stay consistent with how the Siri/voice flow writes (and to keep this
/// screen's Core Data usage limited to reads via @FetchRequest).
private struct StockEntryFormSheet: View {
    enum Mode {
        case create
        case edit(StockEntryEntity)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var itemName: String = ""
    @State private var quantityText: String = ""
    @State private var unit: String = StockPhraseParser.canonicalUnits.first ?? "pcs"
    @State private var totalCostText: String = ""
    @State private var date: Date = .now

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Total cost is required when adding new stock (it's what feeds COGS),
    /// but stays an optional raw override when editing — see `save()`.
    private var canSave: Bool {
        guard !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Double(quantityText) != nil,
              !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        if isEditing {
            return totalCostText.isEmpty || Double(totalCostText) != nil
        }
        guard let totalCost = Double(totalCostText) else { return false }
        return totalCost > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detail Stok") {
                    TextField("Nama barang", text: $itemName)
                    TextField("Jumlah", text: $quantityText)
                        .keyboardType(.decimalPad)
                    Picker("Satuan", selection: $unit) {
                        ForEach(StockPhraseParser.canonicalUnits, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    DatePicker("Tanggal", selection: $date, displayedComponents: .date)
                }

                Section {
                    TextField(isEditing ? "Harga per satuan (opsional)" : "Total harga", text: $totalCostText)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text(isEditing
                        ? "Mengubah nilai ini langsung menimpa rata-rata biaya per satuan, tanpa dicatat sebagai transaksi baru."
                        : "Total biaya untuk jumlah stok ini, mis. Rp150.000 untuk 5kg. Dipakai untuk menghitung rata-rata biaya dan HPP (COGS).")
                }

                if case .edit(let entry) = mode {
                    Section {
                        Button("Hapus Item", role: .destructive) {
                            if let id = entry.id {
                                StockStore.delete(id: id)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Stok" : "Tambah Stok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard case .edit(let entry) = mode else { return }
        itemName = entry.itemName ?? ""
        quantityText = formatQuantity(entry.quantity)
        // Falls back to the first canonical unit if the stored value isn't
        // one of them (e.g. a legacy entry from before the picker existed),
        // so the Picker always shows a selected row instead of appearing
        // blank for an unmatched selection.
        if let storedUnit = entry.unit, StockPhraseParser.canonicalUnits.contains(storedUnit) {
            unit = storedUnit
        }
        // Edit mode shows/overrides per-unit cost directly (not a batch
        // total — see the field's label/footer above).
        if entry.costPerUnit > 0 {
            totalCostText = formatQuantity(entry.costPerUnit)
        }
        if let storedDate = entry.date {
            date = storedDate
        }
    }

    private func save() {
        guard let quantity = Double(quantityText) else { return }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredValue = Double(totalCostText) ?? 0

        switch mode {
        case .create:
            // Field holds a batch total here; StockStore.add divides by
            // quantity internally to get cost-per-unit.
            StockStore.add(itemName: trimmedName, quantity: quantity, unit: trimmedUnit, totalCost: enteredValue, date: date)
        case .edit(let entry):
            guard let id = entry.id else { return }
            // Field holds a direct per-unit override here, not a total.
            StockStore.update(id: id, itemName: trimmedName, quantity: quantity, unit: trimmedUnit, costPerUnit: enteredValue, date: date)
        }
    }
}

#Preview {
    InventoryScreen()
        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
}
