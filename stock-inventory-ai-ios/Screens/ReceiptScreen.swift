//
//  ReceiptScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct ReceiptScreen: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Scan Nota")
                    .font(.title2.bold())

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .overlay(
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 120, height: 8)

                ExtractedFieldCard(lines: 2)
                ExtractedFieldCard(lines: 2)

                Spacer()

                Button {
                } label: {
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
            .frame(width: 220)
            .padding(.top, 24)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ExtractedFieldCard: View {
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<lines, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ReceiptScreen()
}
