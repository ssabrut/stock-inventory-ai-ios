//
//  StockTools.swift
//  stock-inventory-ai-ios
//

import Foundation

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
            .map { "\($0.itemName): \($0.quantity) \($0.unit)" }
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
        AgentToolParameter(name: "quantity", type: "integer", description: "Amount to add"),
        AgentToolParameter(name: "unit", type: "string", description: "Unit of measure, e.g. gram, kg, pcs")
    ]

    func call(arguments: [String: Any]) throws -> String {
        guard let itemName = arguments["itemName"] as? String, !itemName.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let quantity = arguments["quantity"] as? Int, quantity > 0 else {
            throw AgentToolError(message: "Missing or invalid quantity.")
        }
        guard let unit = arguments["unit"] as? String, !unit.isEmpty else {
            throw AgentToolError(message: "Missing unit.")
        }

        let entry = StockStore.add(itemName: itemName, quantity: quantity, unit: unit)
        return "Added \(entry.quantity) \(entry.unit) of \(entry.itemName)."
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
        AgentToolParameter(name: "quantity", type: "integer", description: "New quantity", isRequired: false),
        AgentToolParameter(name: "unit", type: "string", description: "New unit of measure", isRequired: false)
    ]

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
        let newQuantity = arguments["quantity"] as? Int ?? match.quantity
        let newUnit = (arguments["unit"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? match.unit

        StockStore.update(id: match.id, itemName: newItemName, quantity: newQuantity, unit: newUnit, date: match.date)
        return "Updated \(match.itemName) to \(newQuantity) \(newUnit)\(newItemName != match.itemName ? " (renamed to \(newItemName))" : "")."
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
        return "Deleted \(match.itemName) (\(match.quantity) \(match.unit)) from inventory."
    }
}
