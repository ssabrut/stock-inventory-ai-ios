//
//  StockPlan.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 29/09/26.
//

import FoundationModels

@Generable
nonisolated enum StockIntent {
    case checkStock
    case listStock
    case outOfStock
    case history
    case addStock
    case useStock
    case other
}

@Generable
nonisolated struct StockPlan {
    var intent: StockIntent
    @Guide(description: "Ingredient names mentioned, lowercase, e.g. [\"gula\", \"kopi\"]. Empty if none.", .maximumCount(5))
    var items: [String]
    @Guide(description: "Amount for addStock/useStock, else 0")
    var quantity: Double
    @Guide(description: "Unit for addStock/useStock (kg, gram, liter, ml, pcs, box, ikat), else empty")
    var unit: String
    @Guide(description: "Total price in rupiah for addStock (\"70rb\" = 70000), else 0")
    var totalCost: Double
    @Guide(description: "Days back for history: hari ini = 1, minggu ini = 7, bulan ini = 30. Default 7", .range(1...365))
    var days: Int
}
