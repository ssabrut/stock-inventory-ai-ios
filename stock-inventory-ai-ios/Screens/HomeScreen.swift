//
//  HomeScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct CartItem: Identifiable {
    let id = UUID()
    let name: String
    var quantity: Int
}

struct HomeScreen: View {
    private let products = ["Ayam", "Bawang", "Minyak", "Tepung", "Telur", "Cabai"]
    @State private var cart: [String: Int] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var cartItems: [CartItem] {
        cart.compactMap { name, qty in
            qty > 0 ? CartItem(name: name, quantity: qty) : nil
        }.sorted { $0.name < $1.name }
    }

    private var totalCount: Int {
        cart.values.reduce(0, +)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Tambah Pembelian")
                        .font(.title2.bold())
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            .frame(width: 26, height: 26)
                        Text("\(totalCount)")
                            .font(.caption.bold())
                    }
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(products, id: \.self) { product in
                        ProductTile(
                            name: product,
                            isSelected: (cart[product] ?? 0) > 0
                        ) {
                            cart[product, default: 0] += 1
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)

            CartPanel(items: cartItems, onSave: {
                cart.removeAll()
            })
            .frame(width: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProductTile: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(name)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CartPanel: View {
    let items: [CartItem]
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keranjang")
                    .font(.headline)
                Spacer()
                Text("\(items.reduce(0) { $0 + $1.quantity })")
                    .font(.headline)
            }

            if items.isEmpty {
                Text("Belum ada item")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            Text("x\(item.quantity)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onSave) {
                Text("Simpan")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary, lineWidth: 1)
            )
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .padding(.top, 24)
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }
}

#Preview {
    HomeScreen()
}
