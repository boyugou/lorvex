import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// `completed_at` restores the completion time of a task that is completed. The
/// schema keeps `completed_at` non-null exactly when the status is `completed`,
/// so a create that carries a completion time for any other status is a
/// validation error, never a raw database error, and creates nothing.
@Suite("MCP create_task completed_at")
struct MCPTaskCompletedAtTests {
  private let completedAt = "2026-10-04T05:39:00Z"

  private func taskCount(_ registry: ToolRegistry) async throws -> Int {
    let all = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["status": .string("all")])
    return all.structuredContent?.objectValue?["tasks"]?.arrayValue?.count ?? -1
  }

  @Test(
    "completed_at without status completed is a validation error that creates nothing",
    arguments: [nil, "open", "in_progress", "someday", "cancelled"] as [String?])
  func completedAtNeedsACompletedStatus(status: String?) async throws {
    let registry = try mcpInMemoryRegistry()
    var arguments: [String: Value] = [
      "title": .string("Backfilled"), "completed_at": .string(completedAt),
    ]
    if let status { arguments["status"] = .string(status) }

    let result = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)

    expectMCPStructuredError(result, code: "validation", tool: "create_task")
    #expect(mcpTextContent(result).contains("completed_at"))
    #expect(!mcpTextContent(result).contains("SQLite"))
    #expect(try await taskCount(registry) == 0)
  }

  @Test("completed_at with status completed is stored as given")
  func completedAtWithCompletedStatusIsKept() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: [
        "title": .string("Backfilled"), "status": .string("completed"),
        "completed_at": .string(completedAt),
      ])

    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["status"]?.stringValue == "completed")
    #expect(object["completed_at"]?.stringValue?.hasPrefix("2026-10-04T05:39:00") == true)
  }

  @Test("batch_create_tasks reports a row with a stray completed_at and keeps the others")
  func batchReportsAStrayCompletedAt() async throws {
    let registry = try mcpInMemoryRegistry()

    let batch = try await mcpRegistryCall(
      registry, tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object(["title": .string("Fine")]),
          .object(["title": .string("Stray"), "completed_at": .string(completedAt)]),
        ])
      ])

    #expect(batch.isError != true)
    let object = try #require(batch.structuredContent?.objectValue)
    #expect(object["count"]?.intValue == 1)
    let skipped = try #require(object["skipped"]?.arrayValue)
    #expect(skipped.count == 1)
    let reason = skipped.first?.objectValue?["reason"]?.stringValue ?? ""
    #expect(reason.contains("completed_at"))
    #expect(!reason.contains("SQLite"))
  }
}
