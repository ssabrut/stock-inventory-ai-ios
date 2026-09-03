//
//  StartShiftScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

enum ShiftRole: String, CaseIterable, Identifiable {
    case admin
    case dapur

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: return "Admin"
        case .dapur: return "Dapur"
        }
    }
}

struct ReviewQueueItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

struct StartShiftScreen: View {
    @State private var selectedRole: ShiftRole? = nil

    private let queue: [ReviewQueueItem] = [
        ReviewQueueItem(label: "Saran Restock", count: 3),
        ReviewQueueItem(label: "Anomali Terdeteksi", count: 2),
        ReviewQueueItem(label: "Rekap Siap Direview", count: 1)
    ]

    private var totalPending: Int {
        queue.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Mulai Shift")
                        .font(.title2.bold())
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            .frame(width: 26, height: 26)
                        Text("\(totalPending)")
                            .font(.caption.bold())
                    }
                }

                Text("Siapa yang bertugas?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    ForEach(ShiftRole.allCases) { role in
                        RoleCard(
                            role: role,
                            isSelected: selectedRole == role
                        ) {
                            selectedRole = role
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ReviewQueuePanel(items: queue, onStart: {
            })
            .frame(width: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RoleCard: View {
    let role: ShiftRole
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(role.title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
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

private struct ReviewQueuePanel: View {
    let items: [ReviewQueueItem]
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menunggu Direview")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack {
                        Text(item.label)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)

                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }

            Spacer()

            Button(action: onStart) {
                Text("Mulai Shift")
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
    StartShiftScreen()
}
