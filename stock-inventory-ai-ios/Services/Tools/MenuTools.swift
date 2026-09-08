//
//  MenuTools.swift
//  stock-inventory-ai-ios
//

import Foundation

/// Lists all POS menu items, or filters by name (substring, case-insensitive)
/// when the LLM is answering a question about one specific item — e.g.
/// "how much is Nasi Goreng?" -> itemName: "Nasi Goreng".
struct GetMenuTool: AgentTool {
    let name = "get_menu"
    let description = "Look up POS menu items. Omit itemName to list everything, or pass it to filter to matching items."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Item name to filter by (substring match)", isRequired: false)
    ]

    func call(arguments: [String: Any]) throws -> String {
        var items = MenuStore.all()

        if let itemName = arguments["itemName"] as? String, !itemName.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(itemName) }
            guard !items.isEmpty else {
                throw AgentToolError(message: "No menu items found matching \"\(itemName)\".")
            }
        }

        guard !items.isEmpty else {
            return "Menu is empty."
        }

        return items
            .map { "\($0.name) (\($0.category)): \($0.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))" }
            .joined(separator: "\n")
    }
}

/// Adds a new menu item. Category is restricted to the two POS categories —
/// Makanan and Minuman — matched case-insensitively against whatever the LLM
/// or user typed.
struct AddMenuTool: AgentTool {
    let name = "add_menu"
    let description = "Add a new item to the POS menu. Category must be Makanan or Minuman."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "name", type: "string", description: "Name of the menu item"),
        AgentToolParameter(name: "price", type: "number", description: "Sell price"),
        AgentToolParameter(name: "category", type: "string", description: "Makanan or Minuman"),
        AgentToolParameter(name: "icon", type: "string", description: "SF Symbol name for the item's icon", isRequired: false)
    ]
    let isMutating = true

    func confirmationSummary(arguments: [String: Any]) -> String {
        let name = arguments["name"] as? String ?? "item"
        let price = (arguments["price"] as? NSNumber)?.doubleValue ?? 0
        let category = arguments["category"] as? String ?? ""
        return "Add \(name) (\(category)) to menu at \(price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))?"
    }

    func call(arguments: [String: Any]) throws -> String {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let price = (arguments["price"] as? NSNumber)?.doubleValue, price > 0 else {
            throw AgentToolError(message: "Missing or invalid price.")
        }
        guard let rawCategory = arguments["category"] as? String,
              let category = MenuCategory(looselyMatching: rawCategory)
        else {
            throw AgentToolError(message: "Category must be Makanan or Minuman.")
        }
        let icon = (arguments["icon"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "fork.knife"

        let item = MenuStore.add(name: name, price: price, category: category.rawValue, icon: icon)
        return "Added \(item.name) (\(item.category)) at \(item.price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))."
    }
}

/// Updates an existing menu item, matched by name (first case-insensitive
/// match). Only the fields the LLM supplies are changed.
struct UpdateMenuTool: AgentTool {
    let name = "update_menu"
    let description = "Update an existing POS menu item's name, price, and/or category. Matches the item by its current name."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Current name of the item to update"),
        AgentToolParameter(name: "newItemName", type: "string", description: "New name for the item", isRequired: false),
        AgentToolParameter(name: "price", type: "number", description: "New price", isRequired: false),
        AgentToolParameter(name: "category", type: "string", description: "New category: Makanan or Minuman", isRequired: false)
    ]
    let isMutating = true

    func confirmationSummary(arguments: [String: Any]) -> String {
        let itemName = arguments["itemName"] as? String ?? "item"
        var changes: [String] = []
        if let newItemName = arguments["newItemName"] as? String, !newItemName.isEmpty {
            changes.append("rename to \(newItemName)")
        }
        if let price = (arguments["price"] as? NSNumber)?.doubleValue {
            changes.append("price to \(price.formatted(.currency(code: "IDR").precision(.fractionLength(0))))")
        }
        if let category = arguments["category"] as? String, !category.isEmpty {
            changes.append("category to \(category)")
        }
        let changeText = changes.isEmpty ? "update" : changes.joined(separator: ", ")
        return "Update \(itemName): \(changeText)?"
    }

    func call(arguments: [String: Any]) throws -> String {
        guard let itemName = arguments["itemName"] as? String, !itemName.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let match = MenuStore.all().first(where: { $0.name.localizedCaseInsensitiveCompare(itemName) == .orderedSame })
                ?? MenuStore.all().first(where: { $0.name.localizedCaseInsensitiveContains(itemName) })
        else {
            throw AgentToolError(message: "No menu item named \"\(itemName)\".")
        }

        var newCategory = match.category
        if let rawCategory = arguments["category"] as? String, !rawCategory.isEmpty {
            guard let category = MenuCategory(looselyMatching: rawCategory) else {
                throw AgentToolError(message: "Category must be Makanan or Minuman.")
            }
            newCategory = category.rawValue
        }

        let newItemName = (arguments["newItemName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? match.name
        let newPrice = (arguments["price"] as? NSNumber)?.doubleValue ?? match.price

        let updated = MenuItem(id: match.id, name: newItemName, price: newPrice, category: newCategory, icon: match.icon)
        MenuStore.update(updated)
        return "Updated \(match.name) to \(updated.name), \(updated.price.formatted(.currency(code: "IDR").precision(.fractionLength(0)))), \(updated.category)."
    }
}

/// Deletes a menu item matched by name (first case-insensitive match, exact
/// preferred over substring).
struct DeleteMenuTool: AgentTool {
    let name = "delete_menu"
    let description = "Delete a POS menu item by name."
    let parameters: [AgentToolParameter] = [
        AgentToolParameter(name: "itemName", type: "string", description: "Name of the item to delete")
    ]
    let isMutating = true

    func confirmationSummary(arguments: [String: Any]) -> String {
        let itemName = arguments["itemName"] as? String ?? "item"
        return "Delete \(itemName) from menu?"
    }

    func call(arguments: [String: Any]) throws -> String {
        guard let itemName = arguments["itemName"] as? String, !itemName.isEmpty else {
            throw AgentToolError(message: "Missing item name.")
        }
        guard let match = MenuStore.all().first(where: { $0.name.localizedCaseInsensitiveCompare(itemName) == .orderedSame })
                ?? MenuStore.all().first(where: { $0.name.localizedCaseInsensitiveContains(itemName) })
        else {
            throw AgentToolError(message: "No menu item named \"\(itemName)\".")
        }

        MenuStore.delete(id: match.id)
        return "Deleted \(match.name) from menu."
    }
}
