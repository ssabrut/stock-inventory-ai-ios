//
//  ContentView.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppScreen = .startShift

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)

            Group {
                switch selection {
                case .startShift:
                    StartShiftScreen()
                case .chat:
                    ChatScreen()
                case .restock:
                    RestockScreen()
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
