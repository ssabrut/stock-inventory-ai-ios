//
//  StockItem.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 28/09/26.
//

import Foundation
import SwiftData

@Model
final class StockItem {
    @Attribute(.unique) var name: String
    var unit: String
    var quantity: Double
    var costPerUnit: Double
    var updatedAt: Date
    
    init(name: String, unit: String, quantity: Double, costPerUnit: Double, updatedAt: Date = .now) {
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.costPerUnit = costPerUnit
        self.updatedAt = updatedAt
    }
}
