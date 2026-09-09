//
//  OrderHistoryScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Every POS order ever rung up, grouped by the shift it was rung up under,
/// most recent shift first. Refreshes on every appearance so it reflects
/// orders placed during the current (or a past) shift without needing a
/// manual reload.
struct OrderHistoryScreen: View {
    fileprivate struct ShiftGroup: Identifiable {
        let shift: Shift
        let orders: [Order]

        var id: UUID { shift.id }
        var total: Double { orders.reduce(0) { $0 + $1.total } }
    }

    @State private var shiftGroups: [ShiftGroup] = []
    @State private var expandedShiftIds: Set<UUID> = []

    private var totalRevenue: Double {
        shiftGroups.reduce(0) { $0 + $1.total }
    }

    private var orderCount: Int {
        shiftGroups.reduce(0) { $0 + $1.orders.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Riwayat Pesanan")
                    .font(.title2.bold())
                Spacer()
                Text("\(orderCount) pesanan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if shiftGroups.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Pesanan",
                    systemImage: "receipt",
                    description: Text("Pesanan yang diproses di POS akan muncul di sini.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summaryCard

                List {
                    ForEach(shiftGroups) { group in
                        DisclosureGroup(isExpanded: binding(for: group.id)) {
                            ForEach(group.orders) { order in
                                OrderRow(order: order)
                            }
                        } label: {
                            ShiftSectionHeader(group: group)
                        }
                    }
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
            Text("Total Pendapatan Semua Shift")
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
        let orders = OrderStore.all()
        let ordersByShift = Dictionary(grouping: orders, by: \.shiftId)

        shiftGroups = ShiftStore.all()
            .compactMap { shift in
                guard let ordersForShift = ordersByShift[shift.id], !ordersForShift.isEmpty else { return nil }
                return ShiftGroup(shift: shift, orders: ordersForShift)
            }
            .sorted { $0.shift.shiftStart > $1.shift.shiftStart }

        if expandedShiftIds.isEmpty, let mostRecent = shiftGroups.first {
            expandedShiftIds.insert(mostRecent.id)
        }
    }

    private func binding(for shiftId: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedShiftIds.contains(shiftId) },
            set: { isExpanded in
                if isExpanded {
                    expandedShiftIds.insert(shiftId)
                } else {
                    expandedShiftIds.remove(shiftId)
                }
            }
        )
    }
}

private struct ShiftSectionHeader: View {
    let group: OrderHistoryScreen.ShiftGroup

    private var dateRangeText: String {
        let start = group.shift.shiftStart.formatted(date: .abbreviated, time: .shortened)
        guard let end = group.shift.shiftEnd else { return "\(start) – berlangsung" }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateRangeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text("\(group.orders.count) pesanan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(group.total.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                .font(.subheadline.bold())
                .foregroundStyle(.green)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

private struct OrderRow: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(order.date.formatted(date: .abbreviated, time: .shortened), systemImage: "receipt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(order.total.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                    .font(.subheadline.bold())
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(order.items) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(line.name)
                        Text("(\(line.quantity)x \(line.price.formatted(.currency(code: "IDR").precision(.fractionLength(0)))))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(line.subtotal.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                    }
                    .font(.caption)
                }
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    OrderHistoryScreen()
}
