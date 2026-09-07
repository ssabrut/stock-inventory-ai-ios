//
//  AppScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable {
    case inventory
    case chat
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inventory: return "shippingbox.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .inventory: return "Stok Bahan"
        case .chat: return "Tanya AI"
        case .settings: return "Pengaturan"
        }
    }
}
