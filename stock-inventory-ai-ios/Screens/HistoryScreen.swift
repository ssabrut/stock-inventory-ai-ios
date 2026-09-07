//
//  HistoryScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Shows every stock transaction (add + use/sell) and the resulting cost of
/// goods sold — unlike Stok Bahan, which only shows the current merged
/// quantity per item, this is the permanent event log StockStore.add/use
/// write to, so nothing here changes when entries merge.
struct HistoryScreen: View {
    private enum PeriodFilter: String, CaseIterable, Identifiable {
        case all, month, week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Semua"
            case .month: return "30 Hari"
            case .week: return "7 Hari"
            }
        }

        var startDate: Date? {
            switch self {
            case .all: return nil
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: .now)
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: .now)
            }
        }
    }

    @State private var transactions: [StockTransaction] = []
    @State private var period: PeriodFilter = .month

    private var filteredTransactions: [StockTransaction] {
        guard let start = period.startDate else { return transactions }
        return transactions.filter { $0.date >= start }
    }

    private var cogs: Double {
        filteredTransactions
            .filter { $0.type == .remove }
            .reduce(0) { $0 + $1.totalCost }
    }

    private var purchaseTotal: Double {
        filteredTransactions
            .filter { $0.type == .add }
            .reduce(0) { $0 + $1.totalCost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Riwayat & HPP")
                    .font(.title2.bold())
                Spacer()
                Picker("Periode", selection: $period) {
                    ForEach(PeriodFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            summaryCards

            if filteredTransactions.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Riwayat",
                    systemImage: "clock",
                    description: Text("Transaksi stok akan muncul di sini.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredTransactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
                .listStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refresh)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "HPP (Terpakai)", value: cogs, tint: .orange)
            SummaryCard(title: "Total Pembelian", value: purchaseTotal, tint: .green)
        }
    }

    private func refresh() {
        transactions = StockStore.allTransactions()
    }
}

private struct SummaryCard: View {
    let title: String
    let value: Double
    let tint: Color

    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSNumber) ?? "Rp0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formattedValue)
                .font(.title3.bold())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.1))
        )
    }
}

private struct TransactionRow: View {
    let transaction: StockTransaction

    private var isAdd: Bool { transaction.type == .add }

    private var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: transaction.totalCost as NSNumber) ?? "Rp0"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isAdd ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(isAdd ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.itemName)
                    .font(.headline)
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(isAdd ? "+" : "-")\(formatQuantity(transaction.quantity)) \(transaction.unit)")
                    .font(.subheadline.bold())
                if transaction.costPerUnit > 0 {
                    Text(formattedCost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    HistoryScreen()
}
