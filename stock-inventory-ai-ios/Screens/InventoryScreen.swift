//
//  InventoryScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI
import SwiftData

/// What the create/edit form hands back — `StockStore` decides how to apply it.
struct StockDraft {
    var name: String
    var quantity: Double
    var unit: String
    var totalCost: Double
    var date: Date
}

/// Canonical unit options shown in the stock entry form's picker.
enum StockUnits {
    static let canonical = ["kg", "gram", "liter", "ml", "pcs", "box", "ikat"]
}

struct InventoryScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StockItem.name) private var items: [StockItem]
    @State private var editingItem: StockItem?
    @State private var isAddingNew = false
    @State private var usingItem: StockItem?
    @State private var isOpnameActive = false

    private var store: StockStore { StockStore(context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Stok Bahan")
                    .font(.title2.bold())
                Spacer()
                Text("\(items.count) item")
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

            if items.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Stok",
                    systemImage: "shippingbox",
                    description: Text("Tambahkan stok lewat Siri, chat AI, atau tombol +.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                InventoryTableHeader()
                List {
                    ForEach(items) { item in
                        InventoryRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingItem = item
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    try? store.delete(item)
                                } label: {
                                    Label("Hapus", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    usingItem = item
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
        .sheet(item: $editingItem) { item in
            StockEntryFormSheet(mode: .edit(item)) { draft in
                try store.update(item, name: draft.name, quantity: draft.quantity, unit: draft.unit)
            }
        }
        .sheet(isPresented: $isAddingNew) {
            StockEntryFormSheet(mode: .create) { draft in
                try store.addStock(name: draft.name, quantity: draft.quantity, unit: draft.unit, totalCost: draft.totalCost, date: draft.date)
            }
        }
        .sheet(item: $usingItem) { item in
            UseStockSheet(item: item) { quantity in
                try store.use(item, quantity: quantity)
            }
        }
        .sheet(isPresented: $isOpnameActive) {
            OpnameScreen()
        }
    }
}

/// "Pakai" (use/sell) sheet — records stock going out. Kept separate from the
/// edit form since this is a usage event, not a data correction.
private struct UseStockSheet: View {
    let item: StockItem
    let onUse: (Double) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String = ""
    @State private var errorMessage: String?

    private var availableQuantity: Double { item.quantity }

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
                    LabeledContent("Stok saat ini", value: "\(formatQuantity(availableQuantity)) \(item.unit)")
                    TextField("Jumlah terpakai", text: $quantityText)
                        .keyboardType(.decimalPad)
                } footer: {
                    if let value = parsedQuantity, value > availableQuantity {
                        Text("Jumlah melebihi stok yang tersedia.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Dicatat sebagai stok keluar seharga \(formatQuantity((parsedQuantity ?? 0) * item.costPerUnit)).")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Pakai \(item.name)")
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
        do {
            try onUse(quantity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
    let item: StockItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(item.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatQuantity(item.quantity))
                .font(.subheadline)
                .frame(width: InventoryColumn.quantity, alignment: .trailing)

            Text(item.unit)
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
        case edit(StockItem)
    }

    let mode: Mode
    let onSave: (StockDraft) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName: String = ""
    @State private var quantityText: String = ""
    @State private var unit: String = StockUnits.canonical.first ?? "pcs"
    @State private var totalCostText: String = ""
    @State private var date: Date = .now
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Total cost is required when adding new stock (it's what feeds COGS).
    /// Editing never touches cost — `StockStore.update` keeps the item's
    /// existing average cost.
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
                    if !isEditing {
                        DatePicker("Tanggal", selection: $date, displayedComponents: .date)
                    }
                }

                if !isEditing {
                    Section {
                        TextField("Total harga", text: $totalCostText)
                            .keyboardType(.decimalPad)
                    } footer: {
                        Text("Total biaya untuk jumlah stok ini, mis. Rp150.000 untuk 5kg. Dipakai untuk menghitung rata-rata biaya dan HPP (COGS).")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
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
                    Button("Simpan") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard case .edit(let item) = mode else { return }
        itemName = item.name
        quantityText = formatQuantity(item.quantity)
        if StockUnits.canonical.contains(item.unit) {
            unit = item.unit
        }
        date = item.updatedAt
    }

    private func save() {
        guard let quantity = Double(quantityText) else { return }
        let draft = StockDraft(
            name: itemName.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantity,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            totalCost: Double(totalCostText) ?? 0,
            date: date
        )
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    InventoryScreen()
        .modelContainer(for: [StockItem.self, StockTransaction.self], inMemory: true)
}
