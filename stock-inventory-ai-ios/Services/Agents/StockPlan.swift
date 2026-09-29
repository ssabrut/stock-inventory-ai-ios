//
//  StockPlan.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 29/09/26.
//

import FoundationModels

@Generable
nonisolated enum StockIntent: CaseIterable {
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
    /// Planner prompt for this schema — lives next to the schema so each
    /// future plan type (sales, …) carries its own.
    static let instructions = """
    Extract the user's intent from an Indonesian stock-keeping message.
    Examples:
    "stok gula berapa?" -> checkStock, items [gula]
    "bahan apa aja yang ada?" -> listStock
    "apa yang habis?" -> outOfStock
    "pemakaian kopi minggu ini" -> history, items [kopi], days 7
    "HPP bulan ini" -> history, items [], days 30
    "beli gula 5 kg 70rb kemarin" -> addStock, items [gula], quantity 5, unit kg, totalCost 70000, dateText "kemarin"
    "tambah stok garam 3 kg" -> addStock, items [garam], quantity 3, unit kg, totalCost 0, dateText ""
    "pakai susu 2 liter" -> useStock, items [susu], quantity 2, unit liter
    "halo" -> other
    Only fill quantity, totalCost and dateText with values the user actually wrote. Never guess them; use 0 or "".
    If the message only answers a previous question (e.g. "70rb", "kemarin"), merge it with the previous messages.
    """

    var intent: StockIntent
    @Guide(description: "Ingredient names mentioned, lowercase, e.g. [\"gula\", \"kopi\"]. Empty if none.", .maximumCount(5))
    var items: [String]
    @Guide(description: "Amount for addStock/useStock, else 0")
    var quantity: Double
    @Guide(description: "Unit for addStock/useStock (kg, gram, liter, ml, pcs, box, ikat), else empty")
    var unit: String
    @Guide(description: "Total price in rupiah for addStock (\"70rb\" = 70000), else 0")
    var totalCost: Double
    @Guide(description: "Purchase date for addStock exactly as the user wrote it, e.g. \"kemarin\", \"hari ini\", \"28/9\". Empty if not written")
    var dateText: String
    @Guide(description: "Days back for history: hari ini = 1, minggu ini = 7, bulan ini = 30. Default 7", .range(1...365))
    var days: Int
}
