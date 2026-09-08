//
//  SettingsScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct SettingsScreen: View {
    let llm: LLMService

    @State private var cachedModels: [LLMService.CachedModel] = []
    @State private var modelPendingDelete: LLMService.CachedModel?
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteAllDataConfirm = false
    @State private var showDeleteAllMenuConfirm = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private var totalSizeBytes: Int64 {
        cachedModels.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        List {
            Section {
                if cachedModels.isEmpty {
                    Text("Tidak ada model tersimpan di cache.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cachedModels) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(model.id)
                                        .font(.subheadline)
                                    if model.isActive {
                                        Text("Aktif")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundStyle(Color.accentColor)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(Self.formatBytes(model.sizeBytes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                modelPendingDelete = model
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isActive)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Model Tersimpan")
            } footer: {
                if !cachedModels.isEmpty {
                    Text("Total: \(Self.formatBytes(totalSizeBytes))")
                }
            }

            Section {
                if !cachedModels.isEmpty {
                    Button("Hapus Semua Cache Model", role: .destructive) {
                        showDeleteAllConfirm = true
                    }
                    .disabled(cachedModels.allSatisfy(\.isActive))
                }

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
        .task { reload() }
        .refreshable { reload() }
        .alert("Hapus model ini?", isPresented: .init(
            get: { modelPendingDelete != nil },
            set: { if !$0 { modelPendingDelete = nil } }
        )) {
            Button("Batal", role: .cancel) { modelPendingDelete = nil }
            Button("Hapus", role: .destructive) {
                if let model = modelPendingDelete {
                    delete(model)
                }
                modelPendingDelete = nil
            }
        } message: {
            if let model = modelPendingDelete {
                Text("\(model.id) (\(Self.formatBytes(model.sizeBytes))) akan dihapus dari perangkat.")
            }
        }
        .alert("Hapus semua cache model?", isPresented: $showDeleteAllConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Hapus Semua", role: .destructive) { deleteAll() }
        } message: {
            Text("Semua model yang tidak sedang aktif akan dihapus dari perangkat.")
        }
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
        .alert("Gagal menghapus", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        cachedModels = llm.cachedModels()
    }

    private func delete(_ model: LLMService.CachedModel) {
        do {
            try llm.deleteCachedModel(model)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAll() {
        do {
            try llm.deleteAllCachedModels()
            reload()
            successMessage = "Semua cache model berhasil dihapus."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllData() {
        StockStore.deleteAll()
        successMessage = "Semua data inventaris berhasil dihapus."
    }

    private func deleteAllMenu() {
        MenuStore.deleteAll()
        successMessage = "Semua data menu POS berhasil dihapus."
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    SettingsScreen(llm: LLMService())
}
