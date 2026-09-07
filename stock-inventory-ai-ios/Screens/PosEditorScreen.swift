//
//  PosEditorScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct PosEditorScreen: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("POS")
                        .font(.title2.bold())
                    Spacer()
                }

                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)

                    Text("Mulai shift baru atau ubah pengaturan POS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()

                    VStack(spacing: 12) {
                        NavigationLink {
                            StartShiftScreen()
                        } label: {
                            Text("Mulai Shift")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        NavigationLink {
                            EditPosScreen()
                        } label: {
                            Text("Edit POS")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.15))
                                .foregroundStyle(Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct StartShiftScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Mulai Shift")
                .font(.title3.bold())
            Text("Halaman ini belum diimplementasikan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Mulai Shift")
    }
}

private struct EditPosScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Edit POS")
                .font(.title3.bold())
            Text("Halaman ini belum diimplementasikan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Edit POS")
    }
}

#Preview {
    PosEditorScreen()
}
