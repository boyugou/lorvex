import MCP
import Testing
import Foundation

@testable import LorvexMCPHost

@Suite("MCP Tool Registry — schema validation")
struct SchemaValidationTests {

  @Test("invoking unknown tool returns isError true without crashing")
  func unknownToolReturnsError() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "nonexistent_tool_xyz")
    #expect(mcpTextContent(result).contains("Unknown tool"))
    expectMCPStructuredError(
      result,
      code: "unknown_tool",
      tool: "nonexistent_tool_xyz",
      message: "Unknown tool: nonexistent_tool_xyz"
    )
  }

  @Test("registry remains usable after unknown tool call")
  func registryUsableAfterUnknownTool() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await mcpRegistryCall(registry, tool: "nonexistent_tool_xyz")
    let result = try await mcpRegistryCall(registry, tool: "get_session_context")
    #expect(result.isError != true)
  }

  @Test("get_task with empty id returns structured error")
  func getTaskEmptyID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "get_task", arguments: ["id": .string("")])
    expectMCPStructuredError(result, code: "validation", tool: "get_task")
  }
}

@Suite("MCP Tool Registry — write/read consistency")
struct WriteReadConsistencyTests {

  @Test("create_task write is reflected in list_tasks")
  func createTaskReflectedInList() async throws {
    let registry = try mcpInMemoryRegistry()
    let uniqueTitle = "ConsistencyTest-\(Int.random(in: 10000...99999))"
    let createResult = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string(uniqueTitle)]
    )
    #expect(createResult.isError != true)

    let listResult = try await mcpRegistryCall(registry, tool: "list_tasks")
    #expect(listResult.isError != true)

    let combinedText = mcpTextContent(listResult)
      + (listResult.structuredContent?.description ?? "")
    #expect(combinedText.contains(uniqueTitle))
  }

  @Test("create_task accepts rich single-task fields")
  func createTaskAcceptsRichFields() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "create_task",
      arguments: [
        "title": .string("Rich preview create"),
        "notes": .string("Captured with fields"),
        "list_id": .string("inbox"),
        "priority": .int(1),
        "estimated_minutes": .int(20),
        "due_date": .string("2026-07-04"),
        "planned_date": .string("2026-07-03"),
        "tags_set": .array([.string("preview-rich")]),
      ])
    #expect(result.isError != true)
    let task = try #require(result.structuredContent?.objectValue)
    #expect(task["priority"]?.intValue == 1)
    #expect(task["estimated_minutes"]?.intValue == 20)
    #expect(task["due_date"]?.stringValue == "2026-07-04")
    #expect(task["planned_date"]?.stringValue == "2026-07-03")
    #expect(task["tags"]?.arrayValue?.first?.stringValue?.contains("preview-rich") == true)
  }

  @Test("registry preserves and fences success text content")
  func registryPreservesFencedSuccessTextContent() async throws {
    let registry = try mcpInMemoryRegistry()
    let uniqueTitle = "FencedText-\(Int.random(in: 10000...99999))"
    let result = try await mcpRegistryCall(
      registry,
      tool: "create_task",
      arguments: ["title": .string(uniqueTitle)])
    #expect(result.isError != true)
    let expectedText: String = SecurityFencing.fence("Created task: \(uniqueTitle)")
    let expectedTitle: String = SecurityFencing.fence(uniqueTitle)
    #expect(mcpTextContent(result) == expectedText)
    #expect(
      result.structuredContent?.objectValue?["title"]?.stringValue
        == expectedTitle)
  }

  @Test("list_tasks filters tasks by text")
  func listTasksFiltersByText() async throws {
    let registry = try mcpInMemoryRegistry()
    let uniqueTitle = "QueryFilter-\(Int.random(in: 10000...99999))"
    _ = try await mcpRegistryCall(
      registry,
      tool: "create_task",
      arguments: ["title": .string(uniqueTitle)]
    )

    let result = try await mcpRegistryCall(
      registry,
      tool: "list_tasks",
      arguments: ["text": .string(uniqueTitle)]
    )
    #expect(result.isError != true)
    let tasks = result.structuredContent?.objectValue?["tasks"]?.arrayValue ?? []
    // Response titles are fenced; check the raw title is present inside the sentinel wrappers.
    #expect(
      tasks.contains {
        $0.objectValue?["title"]?.stringValue?.contains(uniqueTitle) == true
      }
    )
  }

  @Test("search_tasks with empty query returns no tasks")
  func searchTasksEmptyQueryReturnsNoTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry,
      tool: "search_tasks",
      arguments: ["query": .string("")]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["returned"]?.intValue == 0)
  }

  @Test("create_task records an ai_changelog row (Rule 2)")
  func createTaskRecordsChangelogRow() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Changelog signal test")]
    )
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let log = try await mcpRegistryCall(
      registry, tool: "get_ai_changelog",
      arguments: ["entity_id": .string(taskID)]
    )
    let entries = try #require(log.structuredContent?.objectValue?["entries"]?.arrayValue)
    #expect(entries.count == 1)
  }
}
