//
//  StockTransaction.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 28/09/26.
//

import Foundation
import SwiftData

enum StockTransactionKind: String, CaseIterable {
    case add
    case use
    case adjust
}

@Model
final class StockTransaction {
    var itemName: String
    var unit: String
    var quantity: Double
    var costPerUnit: Double
    var kindRaw: String
    var date: Date
    var note: String?
    
    var kind: StockTransactionKind {
        get {
            StockTransactionKind(rawValue: kindRaw) ?? .adjust
        }
        set { kindRaw = newValue.rawValue }
    }
    
    var totalCost: Double { abs(quantity) * costPerUnit }
    
    init(itemName: String, unit: String, quantity: Double, costPerUnit: Double, kind: StockTransactionKind, date: Date = .now, note: String? = nil) {
        self.itemName = itemName
        self.unit = unit
        self.quantity = quantity
        self.costPerUnit = costPerUnit
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
    }
}
