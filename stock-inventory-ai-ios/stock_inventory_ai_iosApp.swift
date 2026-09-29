//
//  stock_inventory_ai_iosApp.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 01/09/26.
//

import SwiftUI
import SwiftData

@main
struct stock_inventory_ai_iosApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppData.container)
    }
}
