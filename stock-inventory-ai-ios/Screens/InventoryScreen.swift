//
//  InventoryScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct InventoryScreen: View {
    @State private var entries: [StockEntry] = StockStore.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Stok Bahan")
                    .font(.title2.bold())
                Spacer()
                Button {
                    entries = StockStore.all()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Stok",
                    systemImage: "shippingbox",
                    description: Text("Tambahkan stok lewat Siri atau chat AI.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    InventoryRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            entries = StockStore.all()
        }
    }
}

private struct InventoryRow: View {
    let entry: StockEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.itemName)
                    .font(.headline)
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(entry.quantity) \(entry.unit)")
                .font(.subheadline.bold())
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    InventoryScreen()
}
