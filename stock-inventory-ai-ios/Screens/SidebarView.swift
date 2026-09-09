//
//  SidebarView.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppScreen
    @State private var isExpanded = false

    private var width: CGFloat { isExpanded ? 200 : 80 }

    var body: some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 48, height: 48)
                    if isExpanded {
                        Text("Ciutkan")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                        Spacer()
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, isExpanded ? 8 : 0)

            ForEach(AppScreen.allCases) { screen in
                Button {
                    selection = screen
                } label: {
                    row(for: screen)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    @ViewBuilder
    private func row(for screen: AppScreen) -> some View {
        if isExpanded {
            HStack(spacing: 12) {
                Image(systemName: screen.icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                Text(screen.title)
                    .font(.subheadline.weight(selection == screen ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selection == screen ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selection == screen ? Color.gray.opacity(0.15) : Color.clear)
            )
            .padding(.horizontal, 8)
        } else {
            Image(systemName: screen.icon)
                .font(.system(size: 20))
                .foregroundStyle(selection == screen ? Color.primary : Color.secondary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selection == screen ? Color.gray.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.inventory))
}
