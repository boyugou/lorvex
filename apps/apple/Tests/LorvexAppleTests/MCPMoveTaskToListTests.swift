import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// Moving tasks between lists reports the real outcome: a list that does not
/// exist is a validation error that moves nothing, and a task already in the
/// target list comes back unchanged instead of being reported as missing.
@Suite("MCP move task to list")
struct MCPMoveTaskToListTests {
  private let unknownList = "01a11e52-1169-72c5-a925-f36e5d8937ba"
  private let unknownTask = "01a11e52-1169-72c5-a925-f36e5d8937bb"

  private func createTask(
    _ registry: ToolRegistry, _ title: String, listID: String? = nil
  ) async throws -> String {
    var arguments: [String: Value] = ["title": .string(title)]
    if let listID { arguments["list_id"] = .string(listID) }
    let created = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func createList(_ registry: ToolRegistry, _ name: String) async throws -> String {
    let created = try await mcpRegistryCall(
      registry, tool: "create_list", arguments: ["name": .string(name)])
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  @Test("a list that does not exist is a validation error and moves nothing")
  func unknownListIsAValidationError() async throws {
    let registry = try mcpInMemoryRegistry()
    let task = try await createTask(registry, "Draft")
    let calls: [(tool: String, arguments: [String: Value])] = [
      ("move_task_to_list", ["id": .string(task), "list_id": .string(unknownList)]),
      ("batch_move_tasks", ["task_ids": .array([.string(task)]), "list_id": .string(unknownList)]),
    ]
    for call in calls {
      let result = try await mcpRegistryCall(
        registry, tool: call.tool, arguments: call.arguments)
      expectMCPStructuredError(result, code: "validation", tool: call.tool)
      #expect(mcpTextContent(result).contains("does not exist"))
      #expect(!mcpTextContent(result).contains("SQLite"))
    }
    let after = try await mcpRegistryCall(
      registry, tool: "get_task", arguments: ["id": .string(task)])
    #expect(after.structuredContent?.objectValue?["list_id"]?.stringValue == "inbox")
  }

  @Test("moving a task to the list it is already in returns it and writes no changelog row")
  func sameListMoveIsANoOp() async throws {
    let registry = try mcpInMemoryRegistry()
    let task = try await createTask(registry, "Draft")
    let changelogBefore = try await mcpChangelogTools(registry, entityID: task)

    let result = try await mcpRegistryCall(
      registry, tool: "move_task_to_list",
      arguments: ["id": .string(task), "list_id": .string("inbox")])

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["id"]?.stringValue == task)
    #expect(result.structuredContent?.objectValue?["list_id"]?.stringValue == "inbox")
    #expect(try await mcpChangelogTools(registry, entityID: task) == changelogBefore)
  }

  @Test("moving a task that does not exist is still not found")
  func unknownTaskIsNotFound() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "move_task_to_list",
      arguments: ["id": .string(unknownTask), "list_id": .string("inbox")])

    expectMCPStructuredError(result, code: "not_found", tool: "move_task_to_list")
  }

  @Test("batch_move_tasks names the reason each task stayed where it was")
  func batchReportsWhyATaskWasNotMoved() async throws {
    let registry = try mcpInMemoryRegistry()
    let work = try await createList(registry, "Work")
    let moving = try await createTask(registry, "Moves")
    let staying = try await createTask(registry, "Already there", listID: work)

    let batch = try await mcpRegistryCall(
      registry, tool: "batch_move_tasks",
      arguments: [
        "task_ids": .array([.string(moving), .string(staying), .string(unknownTask)]),
        "list_id": .string(work),
      ])

    let object = try #require(batch.structuredContent?.objectValue)
    #expect(object["count"]?.intValue == 1)
    #expect(object["results"]?.arrayValue?.first?.objectValue?["id"]?.stringValue == moving)
    let reasons = Dictionary(
      uniqueKeysWithValues: (object["skipped"]?.arrayValue ?? []).compactMap { entry -> (String, String)? in
        guard let id = entry.objectValue?["id"]?.stringValue,
          let reason = entry.objectValue?["reason"]?.stringValue
        else { return nil }
        return (id, reason)
      })
    #expect(reasons == [staying: "already in the list", unknownTask: "not found"])
  }
}
