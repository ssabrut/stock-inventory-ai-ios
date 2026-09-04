//
//  AppScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable {
    case startShift
    case chat
    case restock

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .startShift: return "clock.badge.checkmark"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .restock: return "arrow.triangle.2.circlepath"
        }
    }

    var title: String {
        switch self {
        case .startShift: return "Mulai Shift"
        case .chat: return "Tanya AI"
        case .restock: return "Saran Restock"
        }
    }
}
