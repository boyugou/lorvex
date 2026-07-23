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

// MARK: - Task Content Operations

private func createFixtureTask(_ registry: ToolRegistry, title: String) async throws -> String {
  let created = try await xcall(
    registry, tool: "create_task", arguments: ["title": .string(title)])
  guard let id = created.structuredContent?.objectValue?["id"]?.stringValue else {
    throw TestFixtureError(message: "create_task returned no id")
  }
  return id
}

private struct TestFixtureError: Error { let message: String }

@Suite("MCP Extended — task content ops")
struct TaskContentExtendedTests {
  @Test("append_to_task_body appends to task notes")
  func appendToTaskBody() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await createFixtureTask(registry, title: "Body append target")
    let result = try await xcall(
      registry,
      tool: "append_to_task_body",
      arguments: [
        "task_id": .string(taskID),
        "text": .string("Native Swift MCP body append"),
      ]
    )
    #expect(result.isError != true)
    let notes = result.structuredContent?.objectValue?["notes"]?.stringValue ?? ""
    #expect(notes.contains("Native Swift MCP body append"))
  }

  @Test("set_task_reminders replaces task reminders")
  func setTaskReminders() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await createFixtureTask(registry, title: "Reminder target")
    let result = try await xcall(
      registry,
      tool: "set_task_reminders",
      arguments: [
        "task_id": .string(taskID),
        "reminders": .array([
          .string("2099-06-01T09:00:00Z"),
          .string("2099-06-02T09:00:00Z"),
        ]),
      ]
    )
    #expect(result.isError != true)
    let reminders = result.structuredContent?.objectValue?["reminders"]?.arrayValue ?? []
    #expect(reminders.count == 2)
  }

  @Test("set_task_reminders requires explicit reminders array")
  func setTaskRemindersRejectsMissingArray() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await createFixtureTask(registry, title: "Reminder validation target")
    let missing = try await xcall(
      registry,
      tool: "set_task_reminders",
      arguments: ["task_id": .string(taskID)]
    )
    #expect(missing.isError == true)
    #expect(xtext(missing).contains("reminders array is required"))

    let wrongType = try await xcall(
      registry,
      tool: "set_task_reminders",
      arguments: [
        "task_id": .string(taskID),
        "reminders": .string("2099-06-01T09:00:00Z"),
      ]
    )
    #expect(wrongType.isError == true)
    #expect(xtext(wrongType).contains("reminders array is required"))
  }

  @Test("set_task_reminders rejects non-string reminder entries")
  func setTaskRemindersRejectsNonStringEntries() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await createFixtureTask(registry, title: "Reminder entry-type target")
    let result = try await xcall(
      registry,
      tool: "set_task_reminders",
      arguments: [
        "task_id": .string(taskID),
        "reminders": .array([.string("2099-06-01T09:00:00Z"), .int(42)]),
      ]
    )
    #expect(result.isError == true)
    #expect(xtext(result).contains("Each reminders entry"))
  }
}
