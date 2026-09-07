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

    var body: some View {
        Group {
            if hasLoadedOnce || didSkipModelLoad {
                ZStack {
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

                    StockSessionOverlay(llm: llm)
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
    }
}

#Preview {
    ContentView()
}
