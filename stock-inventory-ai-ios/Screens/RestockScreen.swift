//
//  RestockScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct RestockSuggestion: Identifiable {
    let id = UUID()
    let itemPlaceholderWidth: CGFloat
    let qtyPlaceholderWidth: CGFloat
}

struct RestockScreen: View {
    private let suggestions: [RestockSuggestion] = [
        RestockSuggestion(itemPlaceholderWidth: 140, qtyPlaceholderWidth: 220),
        RestockSuggestion(itemPlaceholderWidth: 110, qtyPlaceholderWidth: 180),
        RestockSuggestion(itemPlaceholderWidth: 160, qtyPlaceholderWidth: 200),
        RestockSuggestion(itemPlaceholderWidth: 120, qtyPlaceholderWidth: 160)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Saran Restock")
                .font(.title2.bold())

            VStack(spacing: 12) {
                ForEach(suggestions) { suggestion in
                    RestockRow(suggestion: suggestion)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RestockRow: View {
    let suggestion: RestockSuggestion

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.35))
                .frame(width: suggestion.itemPlaceholderWidth, height: 8)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.2))
                .frame(width: suggestion.qtyPlaceholderWidth, height: 8)

            Spacer()

            Button("Setuju") {}
                .buttonStyle(.bordered)

            Button("Edit") {}
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    RestockScreen()
}
