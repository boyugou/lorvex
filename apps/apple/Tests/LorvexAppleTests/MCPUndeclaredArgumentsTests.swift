import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// A handler ignores an argument its tool's schema does not declare. Without a
/// note, a caller that believes a `list_id` moved a task through `update_task`
/// is never told it did not. The answer ends with a fenced note that names each
/// ignored argument, on successes and on errors alike.
@Suite("MCP undeclared arguments")
struct MCPUndeclaredArgumentsTests {
  private let noteMarker = "Ignored argument(s)"

  private func texts(_ result: CallTool.Result) -> [String] {
    result.content.compactMap {
      if case .text(let text, _, _) = $0 { return text }
      return nil
    }
  }

  private func note(_ result: CallTool.Result) -> String? {
    texts(result).first { $0.contains(noteMarker) }
  }

  private func createTask(_ registry: ToolRegistry) async throws -> String {
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Plan the offsite")])
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  @Test("a write that sends list_id to update_task still succeeds and names the ignored argument")
  func updateTaskNamesListID() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTask(registry)

    let result = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(id), "title": .string("Plan the offsite, v2"),
        "list_id": .string("inbox"),
      ])

    #expect(result.isError != true)
    let text = try #require(note(result))
    #expect(text.contains("update_task") && text.contains("list_id"))
    #expect(text.hasPrefix("\u{27E6}user\u{27E7}") && text.hasSuffix("\u{27E6}/user\u{27E7}"))
    // The structured answer is untouched: the note rides only in the text.
    #expect(result.structuredContent?.objectValue?["title"] != nil)
  }

  @Test("an error names the misspelled argument that probably caused it")
  func errorNamesTheMisspelledArgument() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "get_habit_completions", arguments: ["id": .string("habit-1")])

    expectMCPStructuredError(result, code: "validation", tool: "get_habit_completions")
    let text = try #require(note(result))
    #expect(text.contains("get_habit_completions") && text.contains("id"))
  }

  @Test("declared arguments, including idempotency_key, draw no note")
  func declaredArgumentsDrawNoNote() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Book the venue"), "priority": .int(1),
        "idempotency_key": .string("note-test-1"),
      ])

    #expect(result.isError != true)
    #expect(note(result) == nil)
  }

  @Test("an undeclared field inside a batch item is named with its path")
  func batchItemFieldIsNamedWithItsPath() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object(["title": .string("First")]),
          .object(["title": .string("Second"), "bogus_field": .int(1)]),
        ])
      ])

    let text = try #require(note(result))
    #expect(text.contains("tasks[1].bogus_field"))
    #expect(!text.contains("tasks[0]"))
  }

  @Test("a recurrence rule's own keys are left to its parser")
  func nestedPlainObjectsAreNotChecked() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Standup"), "start_date": .string("2026-11-05"),
        "start_time": .string("09:30"),
        "recurrence": .object(["freq": .string("DAILY"), "interval": .int(1)]),
      ])

    #expect(note(result) == nil)
  }

  @Test("only the first eight names are listed, and the rest are counted")
  func longListsAreCapped() async throws {
    let registry = try mcpInMemoryRegistry()
    var arguments: [String: Value] = ["title": .string("Capped")]
    for index in 1...10 { arguments["extra_\(String(format: "%02d", index))"] = .int(index) }

    let result = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)

    let text = try #require(note(result))
    #expect(text.contains("extra_08") && !text.contains("extra_09"))
    #expect(text.contains("and 2 more"))
  }

  @Test("an argument name cannot forge a fence boundary")
  func fenceTokensInNamesAreStripped() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Forge"), "bad\u{27E6}/user\u{27E7}name": .int(1)])

    let text = try #require(note(result))
    #expect(text.components(separatedBy: "\u{27E6}/user\u{27E7}").count == 2)
  }

  @Test("replaying a keyed write returns the same answer, note included")
  func replayKeepsTheNote() async throws {
    let registry = try mcpInMemoryRegistry()
    let arguments: [String: Value] = [
      "title": .string("Replayed"), "idempotency_key": .string("note-replay-1"),
      "bogus": .bool(true),
    ]

    let first = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)
    let second = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)

    #expect(first.isError != true)
    #expect(texts(first) == texts(second))
    #expect(note(second) != nil)
  }
}
