//
//  ContentView.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppScreen = .posEditor
    private var navigationState = AppNavigationState.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)

            Group {
                switch selection {
                case .posEditor:
                    PosEditorScreen()
                case .orderHistory:
                    OrderHistoryScreen()
                case .inventory:
                    InventoryScreen()
                case .chat:
                    ChatScreen()
                case .history:
                    HistoryScreen()
                case .settings:
                    SettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Picks up a screen `StockAgentIntent` requested (e.g. landing on
        // Stok Bahan after a Siri check/add-stock request) — checked on
        // every appearance/foreground, not just cold launch, since
        // `openAppWhenRun` re-foregrounds this same already-running
        // ContentView instance rather than relaunching it.
        .onChange(of: navigationState.pendingScreen, initial: true) {
            if let pending = navigationState.pendingScreen {
                selection = pending
                navigationState.pendingScreen = nil
            }
        }
    }
}

#Preview {
    ContentView()
}
