//
//  StockToolsTests.swift
//  stock-inventory-ai-iosTests
//

import Testing
@testable import stock_inventory_ai_ios

// Both suites share the same StockStore.context static var, so they're
// merged into one .serialized suite — otherwise Swift Testing's default
// parallel execution lets separate suites' init() calls race and swap the
// shared in-memory store out from under each other mid-test.
@Suite(.serialized)
struct StockToolsTests {
    // Held statically so the in-memory PersistenceController (and its
    // NSPersistentContainer/coordinator) outlives each test's init() —
    // StockStore.context only keeps the viewContext, and without a strong
    // reference to the owning controller ARC deallocates it immediately,
    // leaving the context pointing at a torn-down coordinator (EXC_BAD_ACCESS
    // on the very next fetch/save).
    private static let persistence = PersistenceController(inMemory: true)

    init() {
        StockStore.context = Self.persistence.viewContext
        for entry in StockStore.all() {
            StockStore.delete(id: entry.id)
        }
    }

    // MARK: - GetStockTool

    @Test func getStock_emptyInventory_returnsEmptyMessage() throws {
        let result = try GetStockTool().call(arguments: [:])
        #expect(result == "Inventory is empty.")
    }

    @Test func getStock_noFilter_listsAllEntries() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")
        StockStore.add(itemName: "Rice", quantity: 2, unit: "kg")

        let result = try GetStockTool().call(arguments: [:])
        #expect(result.contains("Chicken: 50 gram"))
        #expect(result.contains("Rice: 2 kg"))
    }

    @Test func getStock_withMatchingFilter_returnsOnlyMatches() throws {
        StockStore.add(itemName: "Chicken Breast", quantity: 50, unit: "gram")
        StockStore.add(itemName: "Rice", quantity: 2, unit: "kg")

        let result = try GetStockTool().call(arguments: ["itemName": "chicken"])
        #expect(result.contains("Chicken Breast"))
        #expect(!result.contains("Rice"))
    }

    @Test func getStock_withNoMatch_throws() throws {
        StockStore.add(itemName: "Rice", quantity: 2, unit: "kg")

        #expect(throws: AgentToolError.self) {
            try GetStockTool().call(arguments: ["itemName": "chicken"])
        }
    }

    // MARK: - AddStockTool

    @Test func addStock_validArgs_addsEntryAndReturnsConfirmation() throws {
        let result = try AddStockTool().call(arguments: ["itemName": "Chicken", "quantity": 50, "unit": "gram"])

        #expect(result == "Added 50 gram of Chicken.")
        let stored = StockStore.all()
        #expect(stored.count == 1)
        #expect(stored.first?.itemName == "Chicken")
        #expect(stored.first?.quantity == 50)
        #expect(stored.first?.unit == "gram")
    }

    @Test func addStock_missingItemName_throws() throws {
        #expect(throws: AgentToolError.self) {
            try AddStockTool().call(arguments: ["quantity": 50, "unit": "gram"])
        }
        #expect(StockStore.all().isEmpty)
    }

    @Test func addStock_zeroQuantity_throws() throws {
        #expect(throws: AgentToolError.self) {
            try AddStockTool().call(arguments: ["itemName": "Chicken", "quantity": 0, "unit": "gram"])
        }
        #expect(StockStore.all().isEmpty)
    }

    @Test func addStock_missingUnit_throws() throws {
        #expect(throws: AgentToolError.self) {
            try AddStockTool().call(arguments: ["itemName": "Chicken", "quantity": 50])
        }
        #expect(StockStore.all().isEmpty)
    }

    // MARK: - UpdateStockTool

    @Test func updateStock_existingItem_updatesQuantityAndUnit() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")

        let result = try UpdateStockTool().call(arguments: ["itemName": "Chicken", "quantity": 100, "unit": "kg"])

        #expect(result == "Updated Chicken to 100 kg.")
        let stored = StockStore.all().first
        #expect(stored?.quantity == 100)
        #expect(stored?.unit == "kg")
    }

    @Test func updateStock_partialArgs_keepsOtherFieldsUnchanged() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")

        _ = try UpdateStockTool().call(arguments: ["itemName": "Chicken", "quantity": 75])

        let stored = StockStore.all().first
        #expect(stored?.quantity == 75)
        #expect(stored?.unit == "gram")
        #expect(stored?.itemName == "Chicken")
    }

    @Test func updateStock_rename_updatesNameAndMentionsRename() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")

        let result = try UpdateStockTool().call(arguments: ["itemName": "Chicken", "newItemName": "Chicken Breast"])

        #expect(result.contains("renamed to Chicken Breast"))
        #expect(StockStore.all().first?.itemName == "Chicken Breast")
    }

    @Test func updateStock_caseInsensitiveMatch_findsEntry() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")

        let result = try UpdateStockTool().call(arguments: ["itemName": "CHICKEN", "quantity": 60])
        #expect(result.contains("Updated Chicken"))
    }

    @Test func updateStock_unknownItem_throws() throws {
        #expect(throws: AgentToolError.self) {
            try UpdateStockTool().call(arguments: ["itemName": "Nonexistent", "quantity": 10])
        }
    }

    @Test func updateStock_missingItemName_throws() throws {
        #expect(throws: AgentToolError.self) {
            try UpdateStockTool().call(arguments: ["quantity": 10])
        }
    }

    // MARK: - DeleteStockTool

    @Test func deleteStock_existingItem_removesEntry() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")

        let result = try DeleteStockTool().call(arguments: ["itemName": "Chicken"])

        #expect(result == "Deleted Chicken (50 gram) from inventory.")
        #expect(StockStore.all().isEmpty)
    }

    @Test func deleteStock_caseInsensitiveMatch_removesEntry() throws {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")

        _ = try DeleteStockTool().call(arguments: ["itemName": "chicken"])
        #expect(StockStore.all().isEmpty)
    }

    @Test func deleteStock_unknownItem_throwsAndLeavesInventoryUntouched() throws {
        StockStore.add(itemName: "Rice", quantity: 2, unit: "kg")

        #expect(throws: AgentToolError.self) {
            try DeleteStockTool().call(arguments: ["itemName": "Chicken"])
        }
        #expect(StockStore.all().count == 1)
    }

    @Test func deleteStock_missingItemName_throws() throws {
        #expect(throws: AgentToolError.self) {
            try DeleteStockTool().call(arguments: [:])
        }
    }

    // MARK: - parseReply

    @Test func parseReply_answerJSON_returnsAnswer() throws {
        let registry = ToolRegistry()
        let reply = registry.parseReply(#"{"answer": "There are 50 grams of chicken."}"#)

        guard case .answer(let text) = reply else {
            Issue.record("Expected .answer case")
            return
        }
        #expect(text == "There are 50 grams of chicken.")
    }

    @Test func parseReply_toolCallJSON_returnsToolCall() throws {
        let registry = ToolRegistry()
        let reply = registry.parseReply(#"{"tool": "get_stock", "args": {"itemName": "chicken"}}"#)

        guard case .toolCall(let call) = reply else {
            Issue.record("Expected .toolCall case")
            return
        }
        #expect(call.name == "get_stock")
        #expect(call.arguments["itemName"] as? String == "chicken")
    }

    @Test func parseReply_toolCallWithoutArgs_defaultsToEmptyArgs() throws {
        let registry = ToolRegistry()
        let reply = registry.parseReply(#"{"tool": "get_stock"}"#)

        guard case .toolCall(let call) = reply else {
            Issue.record("Expected .toolCall case")
            return
        }
        #expect(call.arguments.isEmpty)
    }

    @Test func parseReply_jsonWrappedInStrayText_stillExtractsObject() throws {
        let registry = ToolRegistry()
        let reply = registry.parseReply(#"Sure, here you go: {"answer": "42"} thanks!"#)

        guard case .answer(let text) = reply else {
            Issue.record("Expected .answer case")
            return
        }
        #expect(text == "42")
    }

    @Test func parseReply_malformedJSON_fallsBackToRawTextAsAnswer() throws {
        let registry = ToolRegistry()
        let reply = registry.parseReply("I'm not sure what you mean.")

        guard case .answer(let text) = reply else {
            Issue.record("Expected .answer case")
            return
        }
        #expect(text == "I'm not sure what you mean.")
    }

    // MARK: - execute

    @Test func execute_knownTool_runsAndReturnsResult() {
        StockStore.add(itemName: "Chicken", quantity: 50, unit: "gram")
        let registry = ToolRegistry()

        let result = registry.execute(ToolCall(name: "get_stock", arguments: ["itemName": "chicken"]))
        #expect(result.contains("Chicken: 50 gram"))
    }

    @Test func execute_unknownTool_returnsErrorString() {
        let registry = ToolRegistry()

        let result = registry.execute(ToolCall(name: "nonexistent_tool", arguments: [:]))
        #expect(result == "Error: unknown tool \"nonexistent_tool\".")
    }

    @Test func execute_toolThrowsAgentToolError_returnsErrorPrefixedMessage() {
        let registry = ToolRegistry()

        let result = registry.execute(ToolCall(name: "delete_stock", arguments: ["itemName": "Nonexistent"]))
        #expect(result.hasPrefix("Error: No stock entry named"))
    }

    // MARK: - systemPromptFragment

    @Test func systemPromptFragment_listsAllRegisteredTools() {
        let registry = ToolRegistry()
        let fragment = registry.systemPromptFragment

        #expect(fragment.contains("get_stock"))
        #expect(fragment.contains("add_stock"))
        #expect(fragment.contains("update_stock"))
        #expect(fragment.contains("delete_stock"))
    }
}
