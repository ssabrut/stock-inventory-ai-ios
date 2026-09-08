//
//  AppNavigationState.swift
//  stock-inventory-ai-ios
//

import Foundation

/// Shared navigation target `ContentView` observes to pick its selected
/// `AppScreen` — a singleton rather than view-local `@State` specifically so
/// `StockAgentIntent` (which runs in its own AppIntent execution context,
/// outside `ContentView`'s hierarchy) can steer the UI to a particular
/// screen before/while `openAppWhenRun` foregrounds the app, e.g. landing on
/// "Stok Bahan" after a Siri "check stock"/"add stock" request. `ContentView`
/// still owns its own default (`.posEditor`) for a normal cold launch; this
/// only overrides that when an intent explicitly asks for a screen.
@Observable
final class AppNavigationState {
    static let shared = AppNavigationState()

    private init() {}

    var pendingScreen: AppScreen?
}
