//
//  stock_inventory_ai_iosApp.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI

@main
struct stock_inventory_ai_iosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Warm the on-device model at launch so it's ready by the
                // time the user opens "Tanya AI".
                .task {
                    await ChatModel.shared.loadIfNeeded()
                }
        }
    }
}
