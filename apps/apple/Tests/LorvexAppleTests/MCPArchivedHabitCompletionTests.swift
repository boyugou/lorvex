import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// An archived habit is hidden from every surface and absent from the catalog a
/// completion write returns, so a completion write against it is refused before
/// anything is stored. The refusal must leave no completion row and no
/// `ai_changelog` entry behind.
@Suite("MCP archived habit completion")
struct MCPArchivedHabitCompletionTests {
  private let date = "2026-06-04"

  /// An archived habit that carries one completion on `date`.
  private func archivedHabit(_ registry: ToolRegistry) async throws -> String {
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Evening walk")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "complete_habit", arguments: ["id": .string(id), "date": .string(date)])
    let archived = try await mcpRegistryCall(
      registry, tool: "update_habit", arguments: ["id": .string(id), "archived": .bool(true)])
    #expect(archived.isError != true)
    return id
  }

  private func completionValues(_ registry: ToolRegistry, _ id: String) async throws -> [Int] {
    let result = try await mcpRegistryCall(
      registry, tool: "get_habit_completions", arguments: ["habit_id": .string(id)])
    return (result.structuredContent?.objectValue?["completions"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["value"]?.intValue }
  }

  @Test(
    "complete, uncomplete and adjust refuse an archived habit and change nothing",
    arguments: ["complete_habit", "uncomplete_habit", "adjust_habit_completion"])
  func singleWritesRefuseAnArchivedHabit(tool: String) async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await archivedHabit(registry)
    var arguments: [String: Value] = ["id": .string(id), "date": .string(date)]
    if tool == "adjust_habit_completion" { arguments["delta"] = .int(1) }
    let changelogBefore = try await mcpChangelogTools(registry, entityID: id)

    let result = try await mcpRegistryCall(registry, tool: tool, arguments: arguments)

    expectMCPStructuredError(result, code: "validation", tool: tool)
    #expect(mcpTextContent(result).contains("is archived"))
    #expect(try await completionValues(registry, id) == [1])
    #expect(try await mcpChangelogTools(registry, entityID: id) == changelogBefore)
  }

  @Test("batch_complete_habits skips an archived habit and completes the rest")
  func batchSkipsAnArchivedHabit() async throws {
    let registry = try mcpInMemoryRegistry()
    let archivedID = try await archivedHabit(registry)
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Read")])
    let activeID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let batch = try await mcpRegistryCall(
      registry, tool: "batch_complete_habits",
      arguments: [
        "habit_ids": .array([.string(archivedID), .string(activeID)]),
        "date": .string("2026-06-05"),
      ])

    #expect(batch.isError != true)
    let object = try #require(batch.structuredContent?.objectValue)
    #expect(object["count"]?.intValue == 1)
    #expect(object["results"]?.arrayValue?.first?.objectValue?["id"]?.stringValue == activeID)
    let skipped = try #require(object["skipped"]?.arrayValue)
    #expect(skipped.count == 1)
    #expect(skipped.first?.objectValue?["id"]?.stringValue == archivedID)
    #expect(skipped.first?.objectValue?["reason"]?.stringValue == "archived")
    #expect(try await completionValues(registry, archivedID) == [1])
  }

  @Test("a restored habit takes completions again")
  func aRestoredHabitCompletesAgain() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await archivedHabit(registry)
    _ = try await mcpRegistryCall(
      registry, tool: "update_habit", arguments: ["id": .string(id), "archived": .bool(false)])

    let result = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string(id), "date": .string("2026-06-05")])

    #expect(result.isError != true)
    #expect(try await completionValues(registry, id).count == 2)
  }
}
