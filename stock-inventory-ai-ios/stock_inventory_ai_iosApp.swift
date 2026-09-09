//
//  stock_inventory_ai_iosApp.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

@main
struct stock_inventory_ai_iosApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .onOpenURL { url in
                    // Handles "invent://inventory" from the checkStock Siri
                    // snippet's "Lihat Semua" link — same pendingScreen path
                    // StockAgentIntent uses to land on a screen after a voice
                    // action, just triggered by a URL instead of an intent.
                    guard url.scheme == "invent", url.host == "inventory" else { return }
                    AppNavigationState.shared.pendingScreen = .inventory
                }
        }
    }
}
