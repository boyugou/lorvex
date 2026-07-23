import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// MCP write-path contract coverage for `update_task`: the singular update tool
/// must accept the same keys and enforce the same validation as `create_task`
/// and the batch update tools, so a client that used one shape on create does
/// not silently lose an edit on update.
///
/// Runs against the on-disk Swift core bridge (`mcpOnDiskRegistry`) so coverage
/// exercises the full write path — MCP tool → `CoreBridgeClient` →
/// `SwiftLorvexCoreService` — rather than the in-memory preview fallback.
@Suite("MCP — update_task contract")
struct MCPTaskUpdateContractTests {
  private func tags(_ result: CallTool.Result) -> [String]? {
    result.structuredContent?.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue)
  }

  @Test("update_task accepts the `tags` alias for `tags_set`")
  func updateAcceptsTagsAlias() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    // Create with the `tags` alias (create_task advertises both keys).
    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: ["title": .string("Tagged"), "tags": .array([.string("old")])])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    #expect(tags(created) == [SecurityFencing.fence("old")])

    // Update the tags using the `tags` alias — the change must be applied, not
    // silently dropped in favor of the untouched existing set.
    let updated = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "tags": .array([.string("new-a"), .string("new-b")])])
    #expect(updated.isError != true)
    // Tag order is not part of the contract (tags added in one transaction share
    // a created_at and are ordered by their random tag_id), so compare the set.
    #expect(
      Set(tags(updated) ?? [])
        == [SecurityFencing.fence("new-a"), SecurityFencing.fence("new-b")])
  }

  @Test("update_task `tags` and `tags_set` are interchangeable")
  func updateTagsAliasMatchesTagsSet() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let first = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("A")])
    let firstID = try #require(first.structuredContent?.objectValue?["id"]?.stringValue)
    let second = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("B")])
    let secondID = try #require(second.structuredContent?.objectValue?["id"]?.stringValue)

    let viaAlias = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(firstID), "tags": .array([.string("x"), .string("y")])])
    let viaCanonical = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(secondID), "tags_set": .array([.string("x"), .string("y")])])
    // The two aliases must produce the same tag set; order is not contractual.
    #expect(Set(tags(viaAlias) ?? []) == Set(tags(viaCanonical) ?? []))
    #expect(tags(viaAlias)?.count == 2)
  }

  private func priority(_ result: CallTool.Result) -> Int? {
    result.structuredContent?.objectValue?["priority"]?.intValue
  }

  @Test("update_task rejects a priority outside 1–3")
  func updateRejectsOutOfRangePriority() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: ["title": .string("Priority guard"), "priority": .int(1)])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let rejected = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "priority": .int(5)])
    expectMCPStructuredError(rejected, code: "validation", tool: "update_task")

    // The rejected write must not have mutated the priority.
    let fetched = try await mcpRegistryCall(
      fixture.registry, tool: "get_task", arguments: ["id": .string(taskID)])
    #expect(priority(fetched) == 1)
  }

  @Test("update_task omitting priority keeps the existing priority")
  func updateOmittedPriorityUnchanged() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: ["title": .string("Keep priority"), "priority": .int(3)])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let renamed = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: ["id": .string(taskID), "title": .string("Keep priority (renamed)")])
    #expect(renamed.isError != true)
    #expect(priority(renamed) == 3)
  }

  /// The MCP host is a separate process from other Lorvex writers, so a peer's
  /// edit to a task can land between an `update_task` read and its write. This
  /// interleaves a title-only `update_task` (which omits `planned_date`) with a
  /// concurrent `deferTask` that sets `planned_date`, both on the SAME core
  /// instance. Patch semantics mean `update_task` never writes `planned_date`,
  /// so the deferred value survives every interleaving. The old read-modify-write
  /// could echo a stale (nil) `planned_date` back at a higher HLC, losing the
  /// concurrent defer.
  @Test("update_task omitting a field never clobbers a concurrent write to it")
  func updateTaskOmittedFieldSurvivesConcurrentWrite() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-b11-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let dbPath = dir.appendingPathComponent("db.sqlite").path
    let service = SwiftLorvexCoreService(databasePath: dbPath)
    let registry = ToolRegistry(coreBridge: CoreBridgeClient(databasePath: dbPath, service: service))

    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Race target")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let deferDate = try #require(LorvexDateFormatters.ymdUTC.date(from: "2027-01-15"))

    for i in 0..<40 {
      async let update = mcpRegistryCall(
        registry, tool: "update_task",
        arguments: ["id": .string(taskID), "title": .string("Race \(i)")])
      async let deferred: TodaySnapshot? = try? await service.deferTask(
        id: taskID, until: deferDate, reason: nil)
      let result = try await update
      _ = await deferred

      #expect(result.isError != true)
      let planned = try await service.loadTask(id: taskID).plannedDate
      #expect(
        planned == deferDate,
        "planned_date set by a concurrent defer must survive an update_task that omits it")
    }
  }
}
