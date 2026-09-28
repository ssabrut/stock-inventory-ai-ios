//
//  SettingsScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct SettingsScreen: View {
    @State private var showDeleteAllDataConfirm = false
    @State private var showDeleteAllMenuConfirm = false
    @State private var successMessage: String?

    var body: some View {
        List {
            Section {
                Button("Hapus Semua Data Inventaris", role: .destructive) {
                    showDeleteAllDataConfirm = true
                }

                Button("Hapus Semua Data Menu POS", role: .destructive) {
                    showDeleteAllMenuConfirm = true
                }
            } header: {
                Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } footer: {
                Text("Tindakan di atas bersifat permanen dan tidak dapat dibatalkan.")
            }
        }
        .navigationTitle("Pengaturan")
        .alert("Hapus semua data inventaris?", isPresented: $showDeleteAllDataConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Hapus Semua", role: .destructive) { deleteAllData() }
        } message: {
            Text("Semua stok dan riwayat transaksi akan dihapus permanen dan tidak dapat dikembalikan.")
        }
        .alert("Hapus semua data menu POS?", isPresented: $showDeleteAllMenuConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Hapus Semua", role: .destructive) { deleteAllMenu() }
        } message: {
            Text("Semua menu POS akan dihapus permanen dan tidak dapat dikembalikan.")
        }
        .alert("Berhasil", isPresented: .init(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) {
            Button("OK") { successMessage = nil }
        } message: {
            Text(successMessage ?? "")
        }
    }

    private func deleteAllData() {
        successMessage = "Semua data inventaris berhasil dihapus."
    }

    private func deleteAllMenu() {
        successMessage = "Semua data menu POS berhasil dihapus."
    }
}

#Preview {
    SettingsScreen()
}
