//
//  ContentView.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppScreen = .posEditor
    @State private var llm = LLMService()
    @State private var didSkipModelLoad = false
    @State private var hasLoadedOnce = false
    private var navigationState = AppNavigationState.shared

    var body: some View {
        Group {
            if hasLoadedOnce || didSkipModelLoad {
                HStack(spacing: 0) {
                    SidebarView(selection: $selection)

                    Group {
                        switch selection {
                        case .posEditor:
                            PosEditorScreen()
                        case .inventory:
                            InventoryScreen()
                        case .chat:
                            ChatScreen(llm: llm)
                        case .history:
                            HistoryScreen()
                        case .settings:
                            SettingsScreen(llm: llm)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                SplashScreen(state: llm.state) {
                    didSkipModelLoad = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await llm.loadIfNeeded()
            if llm.state == .ready {
                hasLoadedOnce = true
            }
        }
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
