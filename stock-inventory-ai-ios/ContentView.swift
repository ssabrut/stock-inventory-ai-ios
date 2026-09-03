//
//  ContentView.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppScreen = .home

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)

            Group {
                switch selection {
                case .home:
                    HomeScreen()
                case .chat:
                    ChatScreen()
                case .recap:
                    RecapScreen()
                case .restock:
                    RestockScreen()
                case .receipt:
                    ReceiptScreen()
                case .posEditor:
                    POSEditorScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
