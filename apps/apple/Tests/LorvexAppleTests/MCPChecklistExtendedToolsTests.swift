import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Helpers (file-private to avoid collision with MCPToolRegistryTests)

private func xcall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func xtext(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let t, _, _) = $0 { return t }
    return nil
  }.joined()
}

// MARK: - Task Checklist

@Suite("MCP Extended — task checklist")
struct TaskChecklistExtendedTests {
  @Test("checklist item add toggle update reorder remove round-trips")
  func checklistRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_task", arguments: ["title": .string("Checklist host task")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let first = try await xcall(
      registry,
      tool: "add_task_checklist_item",
      arguments: ["task_id": .string(taskID), "text": .string("First Swift checklist")]
    )
    #expect(first.isError != true)
    let firstID = try #require(
      first.structuredContent?.objectValue?["checklist_items"]?.arrayValue?.first?.objectValue?[
        "id"]?.stringValue
    )

    let second = try await xcall(
      registry,
      tool: "add_task_checklist_item",
      arguments: ["task_id": .string(taskID), "text": .string("Second Swift checklist")]
    )
    #expect(second.isError != true)
    let items = second.structuredContent?.objectValue?["checklist_items"]?.arrayValue ?? []
    let secondID = try #require(items.last?.objectValue?["id"]?.stringValue)

    let toggled = try await xcall(
      registry,
      tool: "toggle_task_checklist_item",
      arguments: ["item_id": .string(firstID), "completed": .bool(true)]
    )
    #expect(toggled.isError != true)
    let completedItem = toggled.structuredContent?.objectValue?["checklist_items"]?.arrayValue?
      .first { $0.objectValue?["id"]?.stringValue == firstID }
    #expect(completedItem?.objectValue?["completed_at"]?.stringValue?.isEmpty == false)

    let updated = try await xcall(
      registry,
      tool: "update_task_checklist_item",
      arguments: ["item_id": .string(firstID), "text": .string("Updated Swift checklist")]
    )
    #expect(updated.isError != true)

    let reordered = try await xcall(
      registry,
      tool: "reorder_task_checklist_items",
      arguments: ["task_id": .string(taskID), "item_ids": .array([.string(secondID), .string(firstID)])]
    )
    #expect(reordered.isError != true)
    let reorderedItems = reordered.structuredContent?.objectValue?["checklist_items"]?.arrayValue ?? []
    #expect(reorderedItems.first?.objectValue?["id"]?.stringValue == secondID)

    let removed = try await xcall(
      registry,
      tool: "remove_task_checklist_item",
      arguments: ["item_id": .string(firstID)]
    )
    #expect(removed.isError != true)
    let remaining = removed.structuredContent?.objectValue?["checklist_items"]?.arrayValue ?? []
    #expect(!remaining.contains { $0.objectValue?["id"]?.stringValue == firstID })
  }
}
