//
//  AppScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable {
    case inventory
    case chat
    case restock

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inventory: return "shippingbox.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .restock: return "arrow.triangle.2.circlepath"
        }
    }

    var title: String {
        switch self {
        case .inventory: return "Stok Bahan"
        case .chat: return "Tanya AI"
        case .restock: return "Saran Restock"
        }
    }
}
