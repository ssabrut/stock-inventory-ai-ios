//
//  StockStoreService.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 28/09/26.
//

import Foundation
import SwiftData

enum StockError: LocalizedError {
    case unitMismatch(existing: String)
    case duplicateName
    case insufficientStock
    
    var errorDescription: String? {
        switch self {
        case .unitMismatch(let existing): return "Satuan harus \(existing), sama seperti stok yang sudah ada"
        case .duplicateName: return "Nama barang sudah dipakai"
        case .insufficientStock: return "Jumlah melebihi stok yang tersedia"
        }
    }
}

struct StockStore {
    let context: ModelContext
    
    func findItem(named name: String) throws -> StockItem? {
        try context.fetch(FetchDescriptor<StockItem>())
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    
    /// Create — or merge into an existing item with the same name.
    func addStock(name: String, quantity: Double, unit: String, totalCost: Double, date: Date = .now) throws {
        let costPerUnit = quantity > 0 ? totalCost / quantity : 0
        let item: StockItem
        
        if let existing = try findItem(named: name) {
            guard existing.unit == unit else { throw StockError.unitMismatch(existing: existing.unit) }
            let newQuantity = existing.quantity + quantity
            existing.costPerUnit = newQuantity > 0
                ? (existing.quantity * existing.costPerUnit + totalCost) / newQuantity
                : costPerUnit
            existing.quantity = newQuantity
            existing.updatedAt = date
            item = existing
        } else {
            item = StockItem(name: name, unit: unit, quantity: quantity, costPerUnit: costPerUnit, updatedAt: date)
            context.insert(item)
        }
        
        context.insert(StockTransaction(itemName: item.name, unit: unit, quantity: quantity, costPerUnit: costPerUnit, kind: .add, date: date))
        try context.save()
    }
    
    /// Update — data correction from the edit form.
    func update(_ item: StockItem, name: String, quantity: Double, unit: String) throws {
        if name.caseInsensitiveCompare(item.name) != .orderedSame, try findItem(named: name) != nil {
            throw StockError.duplicateName
        }
        item.name = name
        item.unit = unit
        try setQuantity(item, to: quantity, note: "Koreksi manual")
    }

    /// Shared by edit and opname: sets absolute quantity, logs the difference.
    func setQuantity(_ item: StockItem, to quantity: Double, note: String) throws {
        let diff = quantity - item.quantity
        item.quantity = quantity
        item.updatedAt = .now
        if diff != 0 {
            context.insert(StockTransaction(itemName: item.name, unit: item.unit, quantity: diff, costPerUnit: item.costPerUnit, kind: .adjust, note: note))
        }
        try context.save()
    }

    /// "Pakai" — stock out, priced at current average cost (feeds COGS).
    func use(_ item: StockItem, quantity: Double, note: String? = nil) throws {
        guard quantity > 0, quantity <= item.quantity else { throw StockError.insufficientStock }
        item.quantity -= quantity
        item.updatedAt = .now
        context.insert(StockTransaction(itemName: item.name, unit: item.unit, quantity: -quantity, costPerUnit: item.costPerUnit, kind: .use, note: note))
        try context.save()
    }

    /// Delete — removes the item; its transactions stay in History.
    func delete(_ item: StockItem) throws {
        context.delete(item)
        try context.save()
    }
}
