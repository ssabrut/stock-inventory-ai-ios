//
//  RootView.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 28/09/26.
//

import SwiftUI

struct RootView: View {
    private enum Phase { case checking, splash, main }
    private var chatModel = ChatModel.shared
    @State private var phase: Phase = .checking
    
    var body: some View {
        Group {
            switch phase {
            case .checking:
                Color(.systemBackground)          // brief; match your launch screen
            case .splash:
                SplashScreen(loadState: chatModel.loadState) {
                    phase = .main                 // "continue" after a failure
                }
            case .main:
                ContentView()
            }
        }
        .task {
            let cached = await Task.detached { ChatModel.isModelCached() }.value
            phase = (cached || chatModel.loadState == .ready) ? .main : .splash
            await chatModel.loadIfNeeded()
        }
        .onChange(of: chatModel.loadState) {
            if phase == .splash, chatModel.loadState == .ready {
                withAnimation { phase = .main }
            }
        }
    }
}

#Preview {
    RootView()
}
