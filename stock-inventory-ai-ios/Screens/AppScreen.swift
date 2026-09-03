//
//  AppScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable {
    case home
    case chat
    case recap
    case restock
    case receipt
    case posEditor

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "cart.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .recap: return "chart.bar.fill"
        case .restock: return "arrow.triangle.2.circlepath"
        case .receipt: return "camera.fill"
        case .posEditor: return "square.and.pencil"
        }
    }

    var title: String {
        switch self {
        case .home: return "Tambah Pembelian"
        case .chat: return "Tanya AI"
        case .recap: return "Rekap Bulanan"
        case .restock: return "Saran Restock"
        case .receipt: return "Scan Nota"
        case .posEditor: return "Edit Menu"
        }
    }
}
