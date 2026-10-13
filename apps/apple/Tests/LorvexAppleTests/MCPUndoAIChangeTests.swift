import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// `undo_ai_change` takes back an update an assistant made to a task, from its `get_ai_changelog`
/// entry, without overwriting anything edited since.
@Suite("MCP undo_ai_change")
struct MCPUndoAIChangeTests {
  /// The newest entry of `operation`, or the oldest entry of all when `operation` is nil.
  private func changelogEntry(
    _ registry: ToolRegistry, operation: String? = "update"
  ) async throws -> [String: Value] {
    let arguments: [String: Value] = operation.map { ["operation": .string($0)] } ?? [:]
    let log = try await mcpRegistryCall(registry, tool: "get_ai_changelog", arguments: arguments)
    let entries = try #require(log.structuredContent?.objectValue?["entries"]?.arrayValue)
    let entry = operation == nil ? entries.last : entries.first
    return try #require(entry?.objectValue)
  }

  @Test("an assistant's update is marked undoable and undo puts the task back")
  func undoRestoresTheTask() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Write report")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(taskID), "title": .string("Write the Q3 report"), "priority": .int(1),
      ])

    let entry = try await changelogEntry(registry)
    #expect(entry["undoable"]?.boolValue == true)
    let changelogID = try #require(entry["id"]?.stringValue)

    let undone = try await mcpRegistryCall(
      registry, tool: "undo_ai_change", arguments: ["changelog_id": .string(changelogID)])

    #expect(undone.isError != true, "\(mcpTextContent(undone))")
    let object = try #require(undone.structuredContent?.objectValue)
    #expect(Set(object["reverted"]?.arrayValue?.compactMap(\.stringValue) ?? []) == ["title", "priority"])
    #expect(object["kept"]?.arrayValue?.isEmpty == true)
    #expect(mcpTextContent(undone).contains("Undid the change"))
    let task = try await mcpRegistryCall(
      registry, tool: "get_task", arguments: ["id": .string(taskID)])
    let title = try #require(task.structuredContent?.objectValue?["title"]?.stringValue)
    #expect(title.contains("Write report"))
    #expect(!title.contains("Q3"))
  }

  @Test("a field edited since is kept, and a second undo changes nothing")
  func laterEditsSurvive() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Write report")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(taskID), "title": .string("First change"), "notes": .string("A")])
    let changelogID = try #require(try await changelogEntry(registry)["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(taskID), "notes": .string("Edited later")])

    let first = try await mcpRegistryCall(
      registry, tool: "undo_ai_change", arguments: ["changelog_id": .string(changelogID)])
    let object = try #require(first.structuredContent?.objectValue)
    #expect(object["reverted"]?.arrayValue?.compactMap(\.stringValue) == ["title"])
    #expect(object["kept"]?.arrayValue?.compactMap(\.stringValue) == ["notes"])

    let second = try await mcpRegistryCall(
      registry, tool: "undo_ai_change", arguments: ["changelog_id": .string(changelogID)])
    #expect(second.isError != true)
    #expect(second.structuredContent?.objectValue?["reverted"]?.arrayValue?.isEmpty == true)
    #expect(mcpTextContent(second).contains("Nothing to undo"))
  }

  @Test("an entry that is not an update, a missing id, and a missing argument are refused clearly")
  func refusals() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    _ = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Write report")])
    let creation = try await changelogEntry(registry, operation: nil)
    #expect(creation["undoable"]?.boolValue == false)

    let notAnUpdate = try await mcpRegistryCall(
      registry, tool: "undo_ai_change",
      arguments: ["changelog_id": .string(try #require(creation["id"]?.stringValue))])
    expectMCPStructuredError(notAnUpdate, code: "validation", tool: "undo_ai_change")
    #expect(mcpTextContent(notAnUpdate).contains("Only an update to a task"))

    let unknown = try await mcpRegistryCall(
      registry, tool: "undo_ai_change", arguments: ["changelog_id": .string("no-such-change")])
    expectMCPStructuredError(unknown, code: "validation", tool: "undo_ai_change")
    #expect(mcpTextContent(unknown).contains("No change with that id"))

    let missing = try await mcpRegistryCall(registry, tool: "undo_ai_change", arguments: [:])
    expectMCPStructuredError(missing, code: "validation", tool: "undo_ai_change")
  }
}
