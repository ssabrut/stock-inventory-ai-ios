//
//  Formatting.swift
//  stock-inventory-ai-ios
//

import Foundation

/// Whole numbers print without a decimal ("5 kg"); fractional amounts keep
/// up to 2 decimal places.
func formatQuantity(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(value))
        : String(format: "%.2f", value)
}
