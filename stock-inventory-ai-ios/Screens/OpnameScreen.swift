//
//  OpnameScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Stock opname (physical count) sheet, launched from Stok Bahan. Lists
/// every current entry with its recorded quantity next to an editable
/// "counted" field; on save, any item whose count differs from system stock
/// is applied as an adjustment via OpnameStore, which logs it as a tagged
/// StockTransaction so History can tell it apart from a normal
/// purchase/use.
struct OpnameScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [OpnameSessionItem] = []
    @State private var noteText: String = ""

    private var discrepancyCount: Int {
        items.filter { $0.diffQty != 0 }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Belum Ada Stok",
                        systemImage: "shippingbox",
                        description: Text("Tambahkan stok dulu sebelum melakukan opname.")
                    )
                } else {
                    Form {
                        Section {
                            TextField("Catatan (opsional)", text: $noteText)
                        }

                        Section {
                            OpnameTableHeader()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)

                            ForEach($items) { $item in
                                OpnameItemRow(item: $item)
                            }
                        } footer: {
                            if discrepancyCount > 0 {
                                Text("\(discrepancyCount) item berbeda dari catatan sistem. Simpan untuk menyesuaikan stok.")
                            } else {
                                Text("Masukkan jumlah hasil hitung fisik untuk tiap item.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stock Opname")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(items.isEmpty)
                }
            }
        }
        .onAppear {
            items = OpnameStore.startSession()
        }
    }

    private func save() {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        OpnameStore.commitSession(items: items, note: trimmedNote.isEmpty ? nil : trimmedNote)
        dismiss()
    }
}

private enum OpnameColumn {
    static let quantity: CGFloat = 70
    static let diff: CGFloat = 70
}

private struct OpnameTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Nama")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Sistem")
                .frame(width: OpnameColumn.quantity, alignment: .trailing)
            Text("Fisik")
                .frame(width: OpnameColumn.quantity, alignment: .trailing)
            Text("Selisih")
                .frame(width: OpnameColumn.diff, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
}

private struct OpnameItemRow: View {
    @Binding var item: OpnameSessionItem

    @State private var countedText: String = ""

    private var diff: Double { item.diffQty }

    private var diffColor: Color {
        if diff > 0 { return .green }
        if diff < 0 { return .red }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.itemName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(item.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatQuantity(item.systemQty))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: OpnameColumn.quantity, alignment: .trailing)

            TextField("0", text: $countedText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: OpnameColumn.quantity)
                .onChange(of: countedText) {
                    item.countedQty = Double(countedText) ?? 0
                }

            Text(diff == 0 ? "-" : "\(diff > 0 ? "+" : "")\(formatQuantity(diff))")
                .font(.subheadline.bold())
                .foregroundStyle(diffColor)
                .frame(width: OpnameColumn.diff, alignment: .trailing)
        }
        .onAppear {
            countedText = formatQuantity(item.countedQty)
        }
    }
}

#Preview {
    OpnameScreen()
        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
}
