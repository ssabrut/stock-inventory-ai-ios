//
//  AppScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable {
    case inventory
    case chat
    case history
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inventory: return "shippingbox.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .history: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .inventory: return "Stok Bahan"
        case .chat: return "Tanya AI"
        case .history: return "Riwayat & HPP"
        case .settings: return "Pengaturan"
        }
    }
}
