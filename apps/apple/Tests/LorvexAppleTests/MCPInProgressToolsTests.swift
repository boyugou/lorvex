import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// MCP wire contract for the `in_progress` lifecycle: the `start_task` /
/// `pause_task` tools, idempotency-key replay, the dependency-blocked-start
/// typed error, `create_task(status: "in_progress")` routing through the start
/// transition, and the `list_tasks` status filter. Runs the real registry over
/// a real in-memory core.
@Suite("MCP in_progress tools")
struct MCPInProgressToolsTests {
  private func createTask(
    _ registry: ToolRegistry, title: String, dependsOn: [String] = []
  ) async throws -> String {
    var args: [String: Value] = ["title": .string(title)]
    if !dependsOn.isEmpty { args["depends_on"] = .array(dependsOn.map(Value.string)) }
    let result = try await mcpRegistryCall(registry, tool: "create_task", arguments: args)
    return try #require(result.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func status(_ result: CallTool.Result) -> String? {
    result.structuredContent?.objectValue?["status"]?.stringValue
  }

  private func taskIDs(_ result: CallTool.Result) -> [String] {
    (result.structuredContent?.objectValue?["tasks"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["id"]?.stringValue }
  }

  @Test("start_task marks a task in_progress and returns the full task")
  func startTask() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTask(registry, title: "Write report")
    let result = try await mcpRegistryCall(
      registry, tool: "start_task", arguments: ["id": .string(id)])
    #expect(result.isError != true)
    #expect(status(result) == "in_progress")
    #expect(mcpTextContent(result).contains("Started"))
  }

  @Test("pause_task returns a started task to open")
  func pauseTask() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTask(registry, title: "Write report")
    _ = try await mcpRegistryCall(registry, tool: "start_task", arguments: ["id": .string(id)])
    let result = try await mcpRegistryCall(
      registry, tool: "pause_task", arguments: ["id": .string(id)])
    #expect(status(result) == "open")
  }

  @Test("create_task status=in_progress routes through the start transition")
  func createInProgress() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Already started"), "status": .string("in_progress")])
    #expect(status(result) == "in_progress")
  }

  @Test("list_tasks status=in_progress returns started tasks")
  func listFilter() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTask(registry, title: "Started task")
    _ = try await mcpRegistryCall(registry, tool: "start_task", arguments: ["id": .string(id)])
    let list = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["status": .string("in_progress")])
    let tasks = list.structuredContent?.objectValue?["tasks"]?.arrayValue ?? []
    #expect(tasks.contains { $0.objectValue?["id"]?.stringValue == id })
  }

  @Test("list_tasks with no status defaults to actionable (open + in_progress)")
  func listDefaultsToActionable() async throws {
    let registry = try mcpInMemoryRegistry()
    let openID = try await createTask(registry, title: "Open work")
    let startedID = try await createTask(registry, title: "Started work")
    _ = try await mcpRegistryCall(registry, tool: "start_task", arguments: ["id": .string(startedID)])

    let list = try await mcpRegistryCall(registry, tool: "list_tasks", arguments: [:])
    let ids = Set(taskIDs(list))
    #expect(ids.contains(openID))
    #expect(ids.contains(startedID))
  }

  @Test("list_tasks status=actionable returns open and in_progress")
  func listActionable() async throws {
    let registry = try mcpInMemoryRegistry()
    let openID = try await createTask(registry, title: "Open work")
    let startedID = try await createTask(registry, title: "Started work")
    _ = try await mcpRegistryCall(registry, tool: "start_task", arguments: ["id": .string(startedID)])

    let list = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["status": .string("actionable")])
    let ids = Set(taskIDs(list))
    #expect(ids.contains(openID))
    #expect(ids.contains(startedID))
  }

  @Test("list_tasks status=open stays open-only (excludes in_progress)")
  func listOpenExcludesInProgress() async throws {
    let registry = try mcpInMemoryRegistry()
    let openID = try await createTask(registry, title: "Open work")
    let startedID = try await createTask(registry, title: "Started work")
    _ = try await mcpRegistryCall(registry, tool: "start_task", arguments: ["id": .string(startedID)])

    let list = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["status": .string("open")])
    let ids = Set(taskIDs(list))
    #expect(ids.contains(openID))
    #expect(!ids.contains(startedID))
  }

  @Test("start_task replays under a reused idempotency key")
  func idempotencyReplay() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTask(registry, title: "Write report")
    let key = "start-\(UUID().uuidString)"
    let first = try await mcpRegistryCall(
      registry, tool: "start_task",
      arguments: ["id": .string(id), "idempotency_key": .string(key)])
    let second = try await mcpRegistryCall(
      registry, tool: "start_task",
      arguments: ["id": .string(id), "idempotency_key": .string(key)])
    #expect(status(first) == "in_progress")
    #expect(status(second) == "in_progress")
  }

  @Test("start_task on a dependency-blocked task returns a validation error")
  func blockedStart() async throws {
    let registry = try mcpInMemoryRegistry()
    let blocker = try await createTask(registry, title: "Blocker")
    let dependent = try await createTask(registry, title: "Dependent", dependsOn: [blocker])
    let result = try await mcpRegistryCall(
      registry, tool: "start_task", arguments: ["id": .string(dependent)])
    #expect(result.isError == true)
    #expect(result.structuredContent?.objectValue?["code"]?.stringValue == "validation")
  }
}
