//
//  PosSaleScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Active-shift POS screen: product grid on the left, running cart/checkout
/// on the right. Shown after a shift is started from PosEditorScreen.
struct PosSaleScreen: View {
    let shift: Shift
    let onEndShift: () -> Void

    @State private var menuItems: [MenuItem] = []
    @State private var selectedCategory: MenuCategory = .makanan
    @State private var cartItems: [CartItem] = []
    @State private var showEndShiftConfirm = false

    private var filteredItems: [MenuItem] {
        menuItems.filter { $0.category.caseInsensitiveCompare(selectedCategory.rawValue) == .orderedSame }
    }

    private var total: Double {
        cartItems.reduce(0) { $0 + $1.subtotal }
    }

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                productColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                checkoutColumn
                    .frame(maxWidth: 340, maxHeight: .infinity)
            }
        }
        .task { reload() }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Akhiri shift ini?", isPresented: $showEndShiftConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Akhiri", role: .destructive) {
                ShiftStore.end(id: shift.id)
                onEndShift()
            }
        } message: {
            Text("Keranjang yang belum dibayar akan hilang.")
        }
    }

    private func reload() {
        menuItems = MenuStore.all()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shift Aktif")
                    .font(.title2.bold())
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date.formatted(date: .abbreviated, time: .standard))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            Button("Akhiri Shift", role: .destructive) {
                showEndShiftConfirm = true
            }
        }
        .padding(24)
    }

    // MARK: - Left column: products

    private var productColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Kategori", selection: $selectedCategory) {
                ForEach(MenuCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 16)

            if filteredItems.isEmpty {
                emptyProductState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredItems) { item in
                            Button {
                                addToCart(item)
                            } label: {
                                ProductCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyProductState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Belum ada menu di kategori ini")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addToCart(_ item: MenuItem) {
        if let index = cartItems.firstIndex(where: { $0.menuItem.id == item.id }) {
            cartItems[index].quantity += 1
        } else {
            cartItems.append(CartItem(menuItem: item, quantity: 1))
        }
    }

    // MARK: - Right column: checkout

    private var checkoutColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pesanan")
                    .font(.headline)
                Spacer()
                if !cartItems.isEmpty {
                    Button("Kosongkan") {
                        cartItems.removeAll()
                    }
                    .font(.caption)
                }
            }
            .padding(16)

            Divider()

            if cartItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cart")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Keranjang kosong")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(cartItems) { item in
                            CartRow(
                                item: item,
                                onIncrement: { increment(item) },
                                onDecrement: { decrement(item) }
                            )
                            Divider()
                        }
                    }
                }
            }

            Divider()

            VStack(spacing: 12) {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(total.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                        .font(.title3.bold())
                }

                Button {
                    cartItems.removeAll()
                } label: {
                    Text("Bayar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(cartItems.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(cartItems.isEmpty)
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func increment(_ item: CartItem) {
        guard let index = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        cartItems[index].quantity += 1
    }

    private func decrement(_ item: CartItem) {
        guard let index = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        cartItems[index].quantity -= 1
        if cartItems[index].quantity <= 0 {
            cartItems.remove(at: index)
        }
    }
}

private struct ProductCard: View {
    let item: MenuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 64)
                Image(systemName: item.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Text(item.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct CartRow: View {
    let item: CartItem
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.menuItem.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.menuItem.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onDecrement) {
                    Image(systemName: "minus.circle.fill")
                }
                Text("\(item.quantity)")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 18)
                Button(action: onIncrement) {
                    Image(systemName: "plus.circle.fill")
                }
            }
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)

            Text(item.subtotal.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        PosSaleScreen(shift: Shift(id: UUID(), shiftStart: .now, shiftEnd: nil), onEndShift: {})
    }
}
