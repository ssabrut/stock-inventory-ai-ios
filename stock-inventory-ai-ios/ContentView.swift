//
//  ContentView.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppScreen = .startShift
    @State private var llm = LLMService()
    @State private var didSkipModelLoad = false
    @State private var hasLoadedOnce = false

    var body: some View {
        Group {
            if hasLoadedOnce || didSkipModelLoad {
                HStack(spacing: 0) {
                    SidebarView(selection: $selection)

                    Group {
                        switch selection {
                        case .startShift:
                            StartShiftScreen()
                        case .chat:
                            ChatScreen(llm: llm)
                        case .restock:
                            RestockScreen()
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
    }
}

#Preview {
    ContentView()
}
