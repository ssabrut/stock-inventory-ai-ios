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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Stok Bahan")
                    .font(.title2.bold())
                Spacer()
                Text("\(entries.count) item")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

#Preview {
    InventoryScreen()
        .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
}
