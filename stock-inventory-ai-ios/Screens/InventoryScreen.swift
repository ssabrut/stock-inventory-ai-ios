//
//  InventoryScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Placeholder value type standing in for a real data-layer stock entry
/// until the backend is rebuilt.
struct StockEntryRecord: Identifiable {
    let id: UUID
    var itemName: String
    var quantity: Double
    var unit: String
    var date: Date
    var costPerUnit: Double

    init(id: UUID = UUID(), itemName: String, quantity: Double, unit: String, date: Date = .now, costPerUnit: Double = 0) {
        self.id = id
        self.itemName = itemName
        self.quantity = quantity
        self.unit = unit
        self.date = date
        self.costPerUnit = costPerUnit
    }
}

/// Canonical unit options shown in the stock entry form's picker.
enum StockUnits {
    static let canonical = ["kg", "gram", "liter", "ml", "pcs", "box", "ikat"]
}

struct InventoryScreen: View {
    @State private var entries: [StockEntryRecord] = []
    @State private var editingEntry: StockEntryRecord?
    @State private var isAddingNew = false
    @State private var usingEntry: StockEntryRecord?
    @State private var isOpnameActive = false

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
                    isOpnameActive = true
                } label: {
                    Label("Stock Opname", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
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
                InventoryTableHeader()
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editingEntry) { entry in
            StockEntryFormSheet(mode: .edit(entry)) { updated in
                if let index = entries.firstIndex(where: { $0.id == updated.id }) {
                    entries[index] = updated
                }
            }
        }
        .sheet(isPresented: $isAddingNew) {
            StockEntryFormSheet(mode: .create) { created in
                entries.append(created)
            }
        }
        .sheet(item: $usingEntry) { entry in
            UseStockSheet(entry: entry) { used, quantity in
                if let index = entries.firstIndex(where: { $0.id == used.id }) {
                    entries[index].quantity -= quantity
                    if entries[index].quantity <= 0 {
                        entries.remove(at: index)
                    }
                }
            }
        }
        .sheet(isPresented: $isOpnameActive) {
            OpnameScreen()
        }
    }

    private func delete(_ entry: StockEntryRecord) {
        entries.removeAll { $0.id == entry.id }
    }
}

/// "Pakai" (use/sell) sheet — records stock going out. Kept separate from the
/// edit form since this is a usage event, not a data correction.
private struct UseStockSheet: View {
    let entry: StockEntryRecord
    let onUse: (StockEntryRecord, Double) -> Void

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
                    LabeledContent("Stok saat ini", value: "\(formatQuantity(availableQuantity)) \(entry.unit)")
                    TextField("Jumlah terpakai", text: $quantityText)
                        .keyboardType(.decimalPad)
                } footer: {
                    if let value = parsedQuantity, value > availableQuantity {
                        Text("Jumlah melebihi stok yang tersedia.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Dicatat sebagai stok keluar seharga \(formatQuantity((parsedQuantity ?? 0) * entry.costPerUnit)).")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Pakai \(entry.itemName)")
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
        guard let quantity = parsedQuantity else { return }
        onUse(entry, quantity)
        dismiss()
    }
}

/// Column widths shared between the header and each row so values line up —
/// SwiftUI's `List` has no built-in table/grid layout, so alignment has to be
/// enforced manually via matching fixed-width frames.
private enum InventoryColumn {
    static let quantity: CGFloat = 60
    static let unit: CGFloat = 56
}

private struct InventoryTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Nama")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Qty")
                .frame(width: InventoryColumn.quantity, alignment: .trailing)
            Text("Satuan")
                .frame(width: InventoryColumn.unit, alignment: .leading)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private struct InventoryRow: View {
    let entry: StockEntryRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.itemName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatQuantity(entry.quantity))
                .font(.subheadline)
                .frame(width: InventoryColumn.quantity, alignment: .trailing)

            Text(entry.unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: InventoryColumn.unit, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

/// Shared create/edit form.
private struct StockEntryFormSheet: View {
    enum Mode {
        case create
        case edit(StockEntryRecord)
    }

    let mode: Mode
    let onSave: (StockEntryRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName: String = ""
    @State private var quantityText: String = ""
    @State private var unit: String = StockUnits.canonical.first ?? "pcs"
    @State private var totalCostText: String = ""
    @State private var date: Date = .now

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Total cost is required when adding new stock (it's what feeds COGS).
    /// Editing no longer touches cost at all — see `save()`, which passes
    /// the entry's existing costPerUnit straight through unchanged.
    private var canSave: Bool {
        guard !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Double(quantityText) != nil,
              !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        if isEditing { return true }
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
                        ForEach(StockUnits.canonical, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    DatePicker("Tanggal", selection: $date, displayedComponents: .date)
                }

                if !isEditing {
                    Section {
                        TextField("Total harga", text: $totalCostText)
                            .keyboardType(.decimalPad)
                    } footer: {
                        Text("Total biaya untuk jumlah stok ini, mis. Rp150.000 untuk 5kg. Dipakai untuk menghitung rata-rata biaya dan HPP (COGS).")
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
        itemName = entry.itemName
        quantityText = formatQuantity(entry.quantity)
        if StockUnits.canonical.contains(entry.unit) {
            unit = entry.unit
        }
        date = entry.date
    }

    private func save() {
        guard let quantity = Double(quantityText) else { return }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let totalCost = Double(totalCostText) ?? 0
            let costPerUnit = quantity > 0 ? totalCost / quantity : 0
            onSave(StockEntryRecord(itemName: trimmedName, quantity: quantity, unit: trimmedUnit, date: date, costPerUnit: costPerUnit))
        case .edit(let entry):
            var updated = entry
            updated.itemName = trimmedName
            updated.quantity = quantity
            updated.unit = trimmedUnit
            updated.date = date
            onSave(updated)
        }
    }
}

#Preview {
    InventoryScreen()
}
