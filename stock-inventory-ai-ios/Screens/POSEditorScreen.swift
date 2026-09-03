//
//  POSEditorScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct POSEditorScreen: View {
    @State private var productName: String = ""
    @State private var price: String = ""
    @State private var promoEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Menu")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nama produk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $productName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Harga")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $price)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktifkan promo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: $promoEnabled)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                } label: {
                    Text("Simpan")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary, lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    POSEditorScreen()
}
