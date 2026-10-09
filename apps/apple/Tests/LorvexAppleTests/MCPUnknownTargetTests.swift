import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// A write aimed at an id that names nothing says so with the `not_found` code,
/// and never reaches the database's constraint text.
@Suite("MCP unknown targets")
struct MCPUnknownTargetTests {
  private let unknownID = "01a11e52-1169-72c5-a925-f36e5d8937ba"

  @Test("update_habit with a new cadence on an unknown habit is not_found")
  func updateHabitWithCadenceOnUnknownHabit() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "update_habit",
      arguments: [
        "id": .string(unknownID), "frequency_type": .string("weekly"),
        "weekdays": .array([.int(1), .int(3)]),
      ])

    expectMCPStructuredError(result, code: "not_found", tool: "update_habit")
    #expect(!mcpTextContent(result).contains("SQLite"))
  }

  @Test("permanent_delete_task: an unknown task is not_found, a live task stays a conflict")
  func permanentDeleteTaskClassification() async throws {
    let registry = try mcpInMemoryRegistry()

    let unknown = try await mcpRegistryCall(
      registry, tool: "permanent_delete_task", arguments: ["id": .string(unknownID)])
    expectMCPStructuredError(unknown, code: "not_found", tool: "permanent_delete_task")

    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Still live")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let live = try await mcpRegistryCall(
      registry, tool: "permanent_delete_task", arguments: ["id": .string(id)])
    expectMCPStructuredError(live, code: "conflict", tool: "permanent_delete_task")
  }
}
