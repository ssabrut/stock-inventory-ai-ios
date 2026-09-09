//
//  OrderHistoryScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Every POS order ever rung up, most recent first. Refreshes on every
/// appearance so it reflects orders placed during the current (or a past)
/// shift without needing a manual reload.
struct OrderHistoryScreen: View {
    @State private var orders: [Order] = []

    private var totalRevenue: Double {
        orders.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Riwayat Pesanan")
                    .font(.title2.bold())
                Spacer()
                Text("\(orders.count) pesanan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if orders.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Pesanan",
                    systemImage: "receipt",
                    description: Text("Pesanan yang diproses di POS akan muncul di sini.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summaryCard

                List(orders) { order in
                    OrderRow(order: order)
                }
                .listStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refresh)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total Pendapatan")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(totalRevenue.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                .font(.title3.bold())
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
    }

    private func refresh() {
        orders = OrderStore.all()
    }
}

private struct OrderRow: View {
    let order: Order

    private var itemsSummary: String {
        order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "receipt.fill")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(itemsSummary)
                    .font(.headline)
                    .lineLimit(2)
                Text(order.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(order.total.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                .font(.subheadline.bold())
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    OrderHistoryScreen()
}
