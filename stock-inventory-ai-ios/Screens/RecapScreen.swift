//
//  RecapScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct RecapScreen: View {
    private let bars: [CGFloat] = [0.45, 0.75, 0.6, 0.95, 0.68]

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Rekap Bulanan")
                    .font(.title2.bold())

                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 16) {
                        ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.4))
                                .frame(height: geo.size.height * height)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(spacing: 16) {
                SummaryCard(lines: 2)
                SummaryCard(lines: 2)

                Button {
                } label: {
                    Text("Bagikan PDF")
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
            .frame(width: 220)
            .padding(.top, 24)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SummaryCard: View {
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 100, height: 8)
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    RecapScreen()
}
