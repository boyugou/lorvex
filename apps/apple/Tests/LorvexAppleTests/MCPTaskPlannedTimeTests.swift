import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// The time pair on `create_task` and `update_task`: `planned_start_time` and
/// `planned_end_time` in HH:MM on the task's planned day.
@Suite("MCP task tools — planned time")
struct MCPTaskPlannedTimeTests {
  @Test("create_task stores a time on the planned day and returns it")
  func createReturnsTheTime() async throws {
    let registry = try mcpInMemoryRegistry()

    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Timed on create"), "planned_date": .string("2026-06-02"),
        "planned_start_time": .string("09:30"), "planned_end_time": .string("10:15"),
      ])

    #expect(created.isError != true)
    let task = try #require(created.structuredContent?.objectValue)
    #expect(task["planned_date"]?.stringValue == "2026-06-02")
    #expect(task["planned_start_time"]?.stringValue == "09:30")
    #expect(task["planned_end_time"]?.stringValue == "10:15")
  }

  @Test("update_task accepts 24:00 as the end, and nulls clear the time but keep the day")
  func updateSetsAndClearsTheTime() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTaskID(registry, plannedDate: "2026-06-02")

    let timed = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(id), "planned_start_time": .string("23:00"),
        "planned_end_time": .string("24:00"),
      ])
    #expect(timed.isError != true)
    #expect(timed.structuredContent?.objectValue?["planned_start_time"]?.stringValue == "23:00")
    #expect(timed.structuredContent?.objectValue?["planned_end_time"]?.stringValue == "24:00")

    let cleared = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "planned_start_time": .null, "planned_end_time": .null])
    #expect(cleared.isError != true)
    let task = try #require(cleared.structuredContent?.objectValue)
    #expect(task["planned_start_time"] == .null)
    #expect(task["planned_end_time"] == .null)
    #expect(task["planned_date"]?.stringValue == "2026-06-02")
  }

  @Test("update_task rejects half a time and a time on a task with no planned day")
  func updateRejectsAnIncompleteTime() async throws {
    let registry = try mcpInMemoryRegistry()
    let dated = try await createTaskID(registry, plannedDate: "2026-06-02")
    let undated = try await createTaskID(registry, plannedDate: nil)

    let half = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(dated), "planned_start_time": .string("09:00")])
    let floating = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(undated), "planned_start_time": .string("09:00"),
        "planned_end_time": .string("10:00"),
      ])

    #expect(half.isError == true)
    #expect(floating.isError == true)
    for id in [dated, undated] {
      let task = try await mcpRegistryCall(registry, tool: "get_task", arguments: ["id": .string(id)])
      #expect(task.structuredContent?.objectValue?["planned_start_time"] == .null)
    }
  }

  @Test("moving the planned day without a new time clears the time")
  func movingTheDayClearsTheTime() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createTaskID(registry, plannedDate: "2026-06-02")
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(id), "planned_start_time": .string("09:00"),
        "planned_end_time": .string("10:00"),
      ])

    let moved = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "planned_date": .string("2026-06-03")])

    #expect(moved.isError != true)
    #expect(moved.structuredContent?.objectValue?["planned_date"]?.stringValue == "2026-06-03")
    #expect(moved.structuredContent?.objectValue?["planned_start_time"] == .null)
  }
}

/// Creates a task through `create_task`, planned for `plannedDate` when given,
/// and returns its id.
private func createTaskID(_ registry: ToolRegistry, plannedDate: String?) async throws -> String {
  var arguments: [String: Value] = ["title": .string("Timed task")]
  if let plannedDate { arguments["planned_date"] = .string(plannedDate) }
  let created = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)
  return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
}
