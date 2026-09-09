//
//  PosEditorScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct PosEditorScreen: View {
    @State private var activeShift: Shift?
    @State private var didCheckActiveShift = false

    var body: some View {
        NavigationStack {
            Group {
                if let shift = activeShift {
                    PosSaleScreen(shift: shift) {
                        activeShift = nil
                    }
                } else if didCheckActiveShift {
                    landingView
                } else {
                    Color.clear
                }
            }
            .toolbar(activeShift == nil ? .visible : .hidden, for: .navigationBar)
        }
        .task {
            activeShift = ShiftStore.active()
            didCheckActiveShift = true
        }
    }

    private var landingView: some View {
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
                    Button {
                        activeShift = ShiftStore.start()
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

private struct EditPosScreen: View {
    @State private var menuItems: [MenuItem] = []
    @State private var itemToEdit: MenuItem?
    @State private var itemToDelete: MenuItem?
    @State private var isPresentingNewItem = false

    var body: some View {
        Group {
            if menuItems.isEmpty {
                emptyState
            } else {
                menuList
            }
        }
        .navigationTitle("Edit POS")
        .task { reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNewItem = true
                } label: {
                    Label("Tambah Menu", systemImage: "plus")
                }
            }
        }
        .sheet(item: $itemToEdit) { item in
            MenuItemEditorSheet(item: item) { updated in
                MenuStore.update(updated)
                reload()
            }
        }
        .sheet(isPresented: $isPresentingNewItem) {
            MenuItemEditorSheet(item: nil) { newItem in
                MenuStore.add(name: newItem.name, price: newItem.price, category: newItem.category, icon: newItem.icon)
                reload()
            }
        }
        .alert("Hapus menu ini?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Batal", role: .cancel) { itemToDelete = nil }
            Button("Hapus", role: .destructive) {
                if let item = itemToDelete {
                    MenuStore.delete(id: item.id)
                    reload()
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("\(item.name) akan dihapus dari menu.")
            }
        }
    }

    private func reload() {
        menuItems = MenuStore.all()
    }

    private var menuList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(menuItems) { item in
                    Button {
                        itemToEdit = item
                    } label: {
                        MenuItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            itemToDelete = item
                        } label: {
                            Label("Hapus", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Belum ada menu")
                .font(.title3.bold())
            Text("Tambahkan menu pertama untuk mulai mengatur POS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MenuItemCard: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(item.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
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

private struct MenuItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: MenuItem?
    let onSave: (MenuItem) -> Void

    @State private var name: String
    @State private var priceText: String
    @State private var category: MenuCategory
    @State private var icon: String

    init(item: MenuItem?, onSave: @escaping (MenuItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _priceText = State(initialValue: item.map { String(Int($0.price)) } ?? "")
        _category = State(initialValue: item.flatMap { MenuCategory(looselyMatching: $0.category) } ?? .makanan)
        _icon = State(initialValue: item?.icon ?? "fork.knife")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detail Menu") {
                    TextField("Nama menu", text: $name)
                    TextField("Harga", text: $priceText)
                        .keyboardType(.numberPad)
                    Picker("Kategori", selection: $category) {
                        ForEach(MenuCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "Tambah Menu" : "Edit Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        let price = Double(priceText) ?? 0
                        let saved = MenuItem(
                            id: item?.id ?? UUID(),
                            name: name,
                            price: price,
                            category: category.rawValue,
                            icon: icon
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    PosEditorScreen()
}
