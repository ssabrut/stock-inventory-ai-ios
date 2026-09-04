//
//  SidebarView.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppScreen

    var body: some View {
        VStack(spacing: 16) {
            ForEach(AppScreen.allCases) { screen in
                Button {
                    selection = screen
                } label: {
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
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 24)
        .frame(width: 80)
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

#Preview {
    SidebarView(selection: .constant(.inventory))
}
