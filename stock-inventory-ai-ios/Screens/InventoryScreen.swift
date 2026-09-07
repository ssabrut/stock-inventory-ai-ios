//
//  InventoryScreen.swift
//  stock-inventory-ai-ios
//

import CoreData
import SwiftUI

struct InventoryScreen: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \StockEntryEntity.date, ascending: false)]
    )
    private var entries: FetchedResults<StockEntryEntity>

    @State private var editingEntry: StockEntryEntity?
    @State private var isAddingNew = false

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
    }

    private func delete(_ entry: StockEntryEntity) {
        guard let id = entry.id else { return }
        StockStore.delete(id: id)
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

            Text("\(entry.quantity) \(entry.unit ?? "")")
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

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Int(quantityText) != nil
            && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detail Stok") {
                    TextField("Nama barang", text: $itemName)
                    TextField("Jumlah", text: $quantityText)
                        .keyboardType(.numberPad)
                    Picker("Satuan", selection: $unit) {
                        ForEach(StockPhraseParser.canonicalUnits, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
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
        quantityText = String(entry.quantity)
        // Falls back to the first canonical unit if the stored value isn't
        // one of them (e.g. a legacy entry from before the picker existed),
        // so the Picker always shows a selected row instead of appearing
        // blank for an unmatched selection.
        if let storedUnit = entry.unit, StockPhraseParser.canonicalUnits.contains(storedUnit) {
            unit = storedUnit
        }
    }

    private func save() {
        guard let quantity = Int(quantityText) else { return }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            StockStore.add(itemName: trimmedName, quantity: quantity, unit: trimmedUnit)
        case .edit(let entry):
            guard let id = entry.id else { return }
            StockStore.update(id: id, itemName: trimmedName, quantity: quantity, unit: trimmedUnit)
        }
    }
}

#Preview {
    InventoryScreen()
        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
}
