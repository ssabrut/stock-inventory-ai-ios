//
//  StockTools.swift
//  stock-inventory-ai-ios
//

import Foundation

/// The LLM's JSON tool-call arguments decode numbers as NSNumber (via
/// JSONSerialization), which bridges to `Int` only when the value happens to
/// have no fractional part — "5.5" or even "50" typed as a JSON float would
/// fail `as? Int`. Reading through NSNumber's own doubleValue accepts either.
private func doubleArgument(_ arguments: [String: Any], _ key: String) -> Double? {
    (arguments[key] as? NSNumber)?.doubleValue
}

/// Whole numbers print without a decimal ("5 kg"); merged fractional amounts
/// (e.g. 5kg + 500gram converted to 5.5kg) keep up to 2 decimal places.
func formatQuantity(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(value))
        : String(format: "%.2f", value)
}

/// Lists all stock, or filters by item name (substring, case-insensitive)
/// when the LLM is answering a question about one specific item — e.g.
/// "how much chicken do we have?" -> itemName: "chicken".
struct GetStockTool: AgentTool {
    let name = "get_stock"
    let description = "Look up current inventory. Omit itemName to list everything, or pass it to filter to matching items."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Item name to filter by (substring match)", isRequired: false)
    ]

    func call(arguments: [String: Any]) throws -> String {
        var entries = StockStore.all()

        if let itemName = arguments["itemName"] as? String, !itemName.isEmpty {
            entries = entries.filter { $0.itemName.localizedCaseInsensitiveContains(itemName) }
            guard !entries.isEmpty else {
                throw AgentToolError(message: "No stock entries found matching \"\(itemName)\".")
            }
        }

        guard !entries.isEmpty else {
            return "Inventory is empty."
        }

        return entries
            .map { "\($0.itemName): \(formatQuantity($0.quantity)) \($0.unit)" }
            .joined(separator: "\n")
    }
}

/// Adds a new stock entry. Quantity/unit are taken as structured arguments
/// from the LLM directly rather than routed through StockPhraseParser —
/// unlike the voice flow's free-text utterance, the LLM already separates
/// these fields itself when it decides to call this tool.
struct AddStockTool: AgentTool {
    let name = "add_stock"
    let description = "Add a new stock entry to inventory."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Name of the item"),
        AgentToolParameter(name: "quantity", type: "number", description: "Amount to add"),
        AgentToolParameter(name: "unit", type: "string", description: "Unit of measure, e.g. gram, kg, pcs"),
        AgentToolParameter(name: "totalCost", type: "number", description: "Total price paid for this quantity. Required if the item has never been added with a known price before.", isRequired: false)
    ]
    let isMutating = true

    /// True when the item has no price to fall back on — neither supplied in
    /// this call nor on file from a previous add — meaning `call` would have
    /// to guess. Checked before confirmation is even shown, so the model
    /// asks the user for a price instead of confirming a silent Rp0 add.
    func needsPrice(arguments: [String: Any]) -> Bool {
        guard doubleArgument(arguments, "totalCost") == nil else { return false }
        let itemName = arguments["itemName"] as? String ?? ""
        return StockStore.lastKnownCost(itemName: itemName) == 0
    }

    func confirmationSummary(arguments: [String: Any]) -> String {
        let itemName = arguments["itemName"] as? String ?? "item"
        let quantity = doubleArgument(arguments, "quantity") ?? 0
        // The LLM emits whatever unit spelling it picked up from the
        // utterance (e.g. "gr" instead of "gram") — canonicalize before
        // matching/merging so it lines up with however this item is already
        // stored, the same vocabulary the voice flow's StockPhraseParser uses.
        let unit = StockPhraseParser.canonicalUnit(arguments["unit"] as? String ?? "")

        if let existing = StockStore.existingEntry(itemName: itemName, unit: unit) {
            return "\(existing.itemName) currently has \(formatQuantity(existing.quantity)) \(existing.unit). Add \(formatQuantity(quantity)) \(unit)?"
        }
        return "Add \(formatQuantity(quantity)) \(unit) of \(itemName) to inventory?"
    }

    func call(arguments: [String: Any]) throws -> String {
        guard let itemName = arguments["itemName"] as? String, !itemName.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let quantity = doubleArgument(arguments, "quantity"), quantity > 0 else {
            throw AgentToolError(message: "Missing or invalid quantity.")
        }
        guard let rawUnit = arguments["unit"] as? String, !rawUnit.isEmpty else {
            throw AgentToolError(message: "Missing unit.")
        }
        let unit = StockPhraseParser.canonicalUnit(rawUnit)

        // A supplied price wins; otherwise fall back to whatever this item
        // last cost (needsPrice already gated the case where neither exists).
        let totalCost = doubleArgument(arguments, "totalCost") ?? (StockStore.lastKnownCost(itemName: itemName) * quantity)
        let entry = StockStore.add(itemName: itemName, quantity: quantity, unit: unit, totalCost: totalCost)
        return "Added \(formatQuantity(entry.quantity)) \(entry.unit) of \(entry.itemName)."
    }
}

/// Updates an existing entry, matched by name (first case-insensitive match).
/// Only the fields the LLM supplies are changed; omitted fields keep their
/// current value.
struct UpdateStockTool: AgentTool {
    let name = "update_stock"
    let description = "Update an existing stock entry's quantity, unit, and/or name. Matches the item by its current name."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Current name of the item to update"),
        AgentToolParameter(name: "newItemName", type: "string", description: "New name for the item", isRequired: false),
        AgentToolParameter(name: "quantity", type: "number", description: "New quantity", isRequired: false),
        AgentToolParameter(name: "unit", type: "string", description: "New unit of measure", isRequired: false)
    ]
    let isMutating = true

    func confirmationSummary(arguments: [String: Any]) -> String {
        let itemName = arguments["itemName"] as? String ?? "item"
        var changes: [String] = []
        if let newItemName = arguments["newItemName"] as? String, !newItemName.isEmpty {
            changes.append("rename to \(newItemName)")
        }
        if let quantity = doubleArgument(arguments, "quantity") {
            changes.append("quantity to \(formatQuantity(quantity))")
        }
        if let unit = arguments["unit"] as? String, !unit.isEmpty {
            changes.append("unit to \(unit)")
        }
        let changeText = changes.isEmpty ? "update" : changes.joined(separator: ", ")
        return "Update \(itemName): \(changeText)?"
    }

    func call(arguments: [String: Any]) throws -> String {
        guard let itemName = arguments["itemName"] as? String, !itemName.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let match = StockStore.all().first(where: { $0.itemName.localizedCaseInsensitiveCompare(itemName) == .orderedSame })
                ?? StockStore.all().first(where: { $0.itemName.localizedCaseInsensitiveContains(itemName) })
        else {
            throw AgentToolError(message: "No stock entry named \"\(itemName)\".")
        }

        let newItemName = (arguments["newItemName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? match.itemName
        let newQuantity = doubleArgument(arguments, "quantity") ?? match.quantity
        let newUnit = (arguments["unit"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? match.unit

        StockStore.update(id: match.id, itemName: newItemName, quantity: newQuantity, unit: newUnit, costPerUnit: match.costPerUnit, date: match.date)
        return "Updated \(match.itemName) to \(formatQuantity(newQuantity)) \(newUnit)\(newItemName != match.itemName ? " (renamed to \(newItemName))" : "")."
    }
}

/// Deletes an entry matched by name (first case-insensitive match, exact
/// preferred over substring).
struct DeleteStockTool: AgentTool {
    let name = "delete_stock"
    let description = "Delete a stock entry by item name."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Name of the item to delete")
    ]
    let isMutating = true

    func confirmationSummary(arguments: [String: Any]) -> String {
        let itemName = arguments["itemName"] as? String ?? "item"
        return "Delete \(itemName) from inventory?"
    }

    func call(arguments: [String: Any]) throws -> String {
        guard let itemName = arguments["itemName"] as? String, !itemName.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let match = StockStore.all().first(where: { $0.itemName.localizedCaseInsensitiveCompare(itemName) == .orderedSame })
                ?? StockStore.all().first(where: { $0.itemName.localizedCaseInsensitiveContains(itemName) })
        else {
            throw AgentToolError(message: "No stock entry named \"\(itemName)\".")
        }

        StockStore.delete(id: match.id)
        return "Deleted \(match.itemName) (\(formatQuantity(match.quantity)) \(match.unit)) from inventory."
    }
}
