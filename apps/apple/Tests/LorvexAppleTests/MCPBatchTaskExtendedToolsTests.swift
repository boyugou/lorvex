import Foundation
import GRDB
import MCP
import Testing

@testable import LorvexCore
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

/// True when the unified `skipped: [{id, reason}]` array carries an entry for `id`.
private func skippedContains(_ result: CallTool.Result, id: String) -> Bool {
  result.structuredContent?.objectValue?["skipped"]?.arrayValue?.contains {
    $0.objectValue?["id"]?.stringValue == id && $0.objectValue?["reason"] != nil
  } == true
}

/// Creates one open task and returns its id.
private func makeTask(_ registry: ToolRegistry, title: String) async throws -> String {
  let created = try await xcall(
    registry, tool: "create_task", arguments: ["title": .string(title)])
  guard let id = created.structuredContent?.objectValue?["id"]?.stringValue else {
    throw BatchFixtureError()
  }
  return id
}

private struct BatchFixtureError: Error {}

// MARK: - Batch Task Operations

@Suite("MCP Extended — batch task ops")
struct BatchTaskOpsExtendedTests {
  @Test("batch_create_tasks then batch_update_tasks round-trips tasks")
  func batchCreateUpdateRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object([
            "title": .string("Preview batch created task"),
            "notes": .string("Created through Swift MCP preview store"),
            "estimated_minutes": .int(25),
            "due_date": .string("2026-06-03"),
            "planned_date": .string("2026-06-02"),
            "tags": .array([.string("mcp-rich-create")]),
          ])
        ])
      ]
    )
    #expect(created.isError != true)
    let taskID = try #require(
      created.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue?["id"]?
        .stringValue
    )
    let createdTask = created.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue
    #expect(created.structuredContent?.objectValue?["count"]?.intValue == 1)
    #expect(createdTask?["estimated_minutes"]?.intValue == 25)
    #expect(createdTask?["due_date"]?.stringValue == "2026-06-03")
    #expect(createdTask?["planned_date"]?.stringValue == "2026-06-02")
    #expect(createdTask?["tags"]?.arrayValue?.count == 1)
    #expect(created.structuredContent?.objectValue?["next_occurrences"] == nil)

    let updated = try await xcall(
      registry,
      tool: "batch_update_tasks",
      arguments: [
        "updates": .array([
          .object([
            "id": .string(taskID),
            "title": .string("Preview batch updated task"),
            "priority": .int(1),
          ])
        ])
      ]
    )
    #expect(updated.isError != true)
    let updatedTask = updated.structuredContent?.objectValue?["results"]?.arrayValue?.first
    let fencedTitle: String = SecurityFencing.fence("Preview batch updated task")
    #expect(updatedTask?.objectValue?["title"]?.stringValue == fencedTitle)
    #expect(updatedTask?.objectValue?["priority"]?.intValue == 1)
    #expect(updatedTask?.objectValue?["priority_label"]?.stringValue == "P1")
    #expect(updated.structuredContent?.objectValue?["next_occurrences"] == nil)
  }

  @Test("batch_create_tasks lands valid rows while parse and service failures skip per row")
  func batchCreateMixedRowsPartialSuccess() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry,
      tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object(["title": .string("Mixed batch valid A")]),
          .object([
            "title": .string("Mixed batch bad date"),
            "due_date": .string("not-a-date"),
          ]),
          .object([
            "title": .string("Mixed batch absent dependency"),
            "depends_on": .array([.string("11111111-1111-4111-8111-111111111111")]),
          ]),
          .object(["title": .string("Mixed batch valid B")]),
        ])
      ]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 2)
    let titles = result.structuredContent?.objectValue?["results"]?.arrayValue?.compactMap {
      $0.objectValue?["title"]?.stringValue
    }
    #expect(titles == [
      SecurityFencing.fence("Mixed batch valid A"),
      SecurityFencing.fence("Mixed batch valid B"),
    ])
    #expect(skippedContains(result, id: "Mixed batch bad date"))
    #expect(skippedContains(result, id: "Mixed batch absent dependency"))

    // Both surviving rows are durably committed and readable after the batch.
    let listed = try await xcall(
      registry, tool: "search_tasks", arguments: ["query": .string("Mixed batch valid")])
    #expect(listed.structuredContent?.objectValue?["returned"]?.intValue == 2)
  }

  @Test("a keyed batch_create_tasks claim is exact across registries on one database")
  func keyedBatchCreateClaimIsExactAcrossRegistries() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    _ = try await xcall(fixture.registry, tool: "get_overview")
    let prefix = "BatchClaim-\(UUID().uuidString.prefix(8))"
    let args: [String: Value] = [
      "tasks": .array([
        .object(["title": .string("\(prefix)-A")]),
        .object(["title": .string("\(prefix)-bad"), "due_date": .string("not-a-date")]),
        .object(["title": .string("\(prefix)-B")]),
      ]),
      "idempotency_key": .string("batch-create-claim-exactness"),
    ]
    let first = try await xcall(fixture.registry, tool: "batch_create_tasks", arguments: args)
    #expect(first.isError != true)
    #expect(first.structuredContent?.objectValue?["count"]?.intValue == 2)

    // A second registry over the same database simulates a restarted host
    // retrying the same keyed call: it must observe the finalized replay of the
    // whole batch — not re-run it, not report it partially applied.
    let replayRegistry = mcpOnDiskRegistry(dbPath: fixture.dbPath).registry
    _ = try await xcall(replayRegistry, tool: "get_overview")
    let replay = try await xcall(replayRegistry, tool: "batch_create_tasks", arguments: args)
    #expect(replay.isError != true)
    #expect(replay.structuredContent?.objectValue?["count"]?.intValue == 2)
    let firstIds = first.structuredContent?.objectValue?["results"]?.arrayValue?.compactMap {
      $0.objectValue?["id"]?.stringValue
    }
    let replayIds = replay.structuredContent?.objectValue?["results"]?.arrayValue?.compactMap {
      $0.objectValue?["id"]?.stringValue
    }
    #expect(firstIds == replayIds)

    let service = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    let count = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tasks WHERE title LIKE ?1",
        arguments: ["\(prefix)%"]) ?? 0
    }
    #expect(count == 2, "the keyed batch must have applied exactly once")
  }

  @Test("batch_update_tasks rejects blank titles before mutating")
  func batchUpdateRejectsBlankTitle() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object(["title": .string("Title guard seed")])
        ])
      ]
    )
    let taskID = try #require(
      created.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue?["id"]?
        .stringValue
    )

    let updated = try await xcall(
      registry,
      tool: "batch_update_tasks",
      arguments: [
        "updates": .array([
          .object([
            "id": .string(taskID),
            "title": .string("   "),
          ])
        ])
      ]
    )
    #expect(updated.isError == true)
  }

  @Test("batch_complete_tasks marks all supplied IDs as completed")
  func batchCompleteAffectsAll() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Batch complete target")
    let result = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(taskID)])]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 1)
    let completed = result.structuredContent?.objectValue?["results"]?.arrayValue?.first
    #expect(completed?.objectValue?["status"]?.stringValue == "completed")
  }

  @Test("batch_complete_tasks captures results in-transaction, never re-reading after commit")
  func batchCompleteDoesNotReadBackAfterCommit() async throws {
    let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
    let bridge = CoreBridgeClient(databasePath: "/tmp/lorvex-test.sqlite", service: core)
    let registry = ToolRegistry(coreBridge: bridge)

    // The stub's `loadTask` throws ("stub"). The batch must still succeed and
    // return the changed task: `results` now comes from the enriched tasks
    // captured inside the write transaction, not a post-commit re-read — the gap
    // where a concurrent delete used to drop a task the batch had mutated (and,
    // as here, could turn a succeeded write into a spurious tool error).
    let result = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(LorvexPreviewSeedID.venueTask)])]
    )
    #expect(result.isError != true)
    #expect(!xtext(result).contains("stub"))
    let results = result.structuredContent?.objectValue?["results"]?.arrayValue
    #expect(results?.isEmpty == false)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == results?.count)
  }

  @Test("batch_complete_tasks with empty task_ids returns structured error")
  func batchCompleteEmptyIDs() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([])]
    )
    #expect(result.isError == true)
  }

  @Test("batch_reopen_tasks reopens a previously completed task")
  func batchReopenTask() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Batch reopen target")
    _ = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(taskID)])]
    )
    let result = try await xcall(
      registry, tool: "batch_reopen_tasks",
      arguments: ["task_ids": .array([.string(taskID)])]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 1)
    let reopened = result.structuredContent?.objectValue?["results"]?.arrayValue?.first
    #expect(reopened?.objectValue?["status"]?.stringValue == "open")
  }

  @Test("batch_move_tasks moves tasks to the target list")
  func batchMoveTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Batch move target")
    let listResult = try await xcall(
      registry, tool: "create_list", arguments: ["name": .string("Move destination")])
    let listID = try #require(listResult.structuredContent?.objectValue?["id"]?.stringValue)
    let result = try await xcall(
      registry, tool: "batch_move_tasks",
      arguments: [
        "task_ids": .array([.string(taskID)]),
        "list_id": .string(listID),
      ]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 1)
    #expect(result.structuredContent?.objectValue?["list_id"]?.stringValue == listID)
    let moved = result.structuredContent?.objectValue?["results"]?.arrayValue?.first
    #expect(moved?.objectValue?["list_id"]?.stringValue == listID)
  }

  @Test("batch_move_tasks with unknown list returns structured error")
  func batchMoveUnknownList() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Move to nowhere")
    let result = try await xcall(
      registry, tool: "batch_move_tasks",
      arguments: [
        "task_ids": .array([.string(taskID)]),
        "list_id": .string("no-such-list"),
      ]
    )
    #expect(result.isError == true)
  }

  @Test("batch_defer_tasks defers the supplied tasks")
  func batchDeferTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Batch defer target")
    let result = try await xcall(
      registry, tool: "batch_defer_tasks",
      arguments: [
        "task_ids": .array([.string(taskID)]),
        "until_date": .string("2099-01-01"),
      ]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 1)
    let deferred = result.structuredContent?.objectValue?["results"]?.arrayValue?.first
    #expect(deferred?.objectValue?["planned_date"]?.stringValue == "2099-01-01")
    #expect(deferred?.objectValue?["defer_count"]?.intValue == 1)
  }

  @Test("batch lifecycle tools report skipped ids instead of throwing")
  func batchLifecycleReportsSkippedIds() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Skipped-ids companion")
    let listResult = try await xcall(
      registry, tool: "create_list", arguments: ["name": .string("Skip destination")])
    let listID = try #require(listResult.structuredContent?.objectValue?["id"]?.stringValue)

    let complete = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: [
        "task_ids": .array([
          .string(taskID),
          .string("missing-task-id"),
        ])
      ])
    #expect(complete.isError != true)
    #expect(skippedContains(complete, id: "missing-task-id"))

    let reopen = try await xcall(
      registry, tool: "batch_reopen_tasks",
      arguments: [
        "task_ids": .array([
          .string(taskID),
          .string("missing-reopen-id"),
        ])
      ])
    #expect(reopen.isError != true)
    #expect(reopen.structuredContent?.objectValue?["already_open"] == nil)
    #expect(skippedContains(reopen, id: "missing-reopen-id"))

    let move = try await xcall(
      registry, tool: "batch_move_tasks",
      arguments: [
        "task_ids": .array([
          .string(taskID),
          .string("missing-move-id"),
        ]),
        "list_id": .string(listID),
      ])
    #expect(move.isError != true)
    #expect(skippedContains(move, id: "missing-move-id"))

    let deferResult = try await xcall(
      registry, tool: "batch_defer_tasks",
      arguments: [
        "task_ids": .array([
          .string(taskID),
          .string("missing-defer-id"),
        ]),
        "until_date": .string("2099-01-01"),
      ])
    #expect(deferResult.isError != true)
    #expect(skippedContains(deferResult, id: "missing-defer-id"))
  }

  @Test("batch_cancel_tasks marks all supplied IDs as cancelled")
  func batchCancelTasks() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Batch cancel target")
    let result = try await xcall(
      registry, tool: "batch_cancel_tasks",
      arguments: ["task_ids": .array([.string(taskID)])]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 1)
    let cancelled = result.structuredContent?.objectValue?["results"]?.arrayValue?.first
    #expect(cancelled?.objectValue?["status"]?.stringValue == "cancelled")
  }

  @Test("batch_cancel_tasks schema exposes cancel_series")
  func batchCancelTasksSchemaExposesCancelSeries() async throws {
    let tool = try #require(ToolRegistry.listTools().first { $0.name == "batch_cancel_tasks" })
    let properties = tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:]
    #expect(properties["cancel_series"] != nil)
  }

  @Test("batch_complete_tasks and batch_cancel_tasks do not return fake next_occurrences")
  func batchLifecyclePayloadDoesNotClaimNextOccurrences() async throws {
    let registry = try mcpInMemoryRegistry()
    let completeTarget = try await makeTask(registry, title: "Complete without occurrences")
    let complete = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(completeTarget)])]
    )
    #expect(complete.isError != true)
    #expect(complete.structuredContent?.objectValue?["next_occurrences"] == nil)

    let cancelTarget = try await makeTask(registry, title: "Cancel without occurrences")
    let cancel = try await xcall(
      registry, tool: "batch_cancel_tasks",
      arguments: ["task_ids": .array([.string(cancelTarget)])]
    )
    #expect(cancel.isError != true)
    #expect(cancel.structuredContent?.objectValue?["next_occurrences"] == nil)
  }

  @Test("batch_cancel_tasks with empty task_ids returns structured error")
  func batchCancelEmptyIds() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "batch_cancel_tasks",
      arguments: ["task_ids": .array([])]
    )
    #expect(result.isError == true)
  }

  @Test("batch_complete_tasks rejects a non-string task id instead of dropping it")
  func batchRejectsNonStringId() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Real batch target")
    // A bare `compactMap(\.stringValue)` would silently drop the `.int` element and
    // complete only the real task, reporting a full run. The call must reject.
    let result = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(id), .int(123)])])
    expectMCPStructuredError(result, code: "validation", tool: "batch_complete_tasks")

    // No partial completion happened: the real task is still open.
    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    #expect(reread.structuredContent?.objectValue?["status"]?.stringValue == "open")
  }

  @Test("batch_defer_tasks rejects a non-string task id instead of dropping it")
  func batchDeferRejectsNonStringId() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Defer batch target")
    let result = try await xcall(
      registry, tool: "batch_defer_tasks",
      arguments: [
        "task_ids": .array([.string(id), .null]),
        "until_date": .string("2099-01-01"),
      ])
    expectMCPStructuredError(result, code: "validation", tool: "batch_defer_tasks")
  }
}

// MARK: - Patch input strictness (wrong-typed field must reject, not silently clear)

@Suite("MCP Extended — patch input strictness")
struct PatchInputStrictnessTests {
  @Test("update_task rejects a string estimated_minutes instead of clearing it")
  func updateRejectsStringForInt() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keep estimate"), "estimated_minutes": .int(30)])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await xcall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "estimated_minutes": .string("45")])
    expectMCPStructuredError(result, code: "validation", tool: "update_task")

    // The rejected call performed no mutation: the original estimate survives
    // rather than being wiped by a silent `.clear`.
    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    #expect(reread.structuredContent?.objectValue?["estimated_minutes"]?.intValue == 30)
  }

  @Test("update_task rejects an int due_date instead of clearing it")
  func updateRejectsIntForDate() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keep due date"), "due_date": .string("2026-04-15")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await xcall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "due_date": .int(20260415)])
    expectMCPStructuredError(result, code: "validation", tool: "update_task")

    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    #expect(reread.structuredContent?.objectValue?["due_date"]?.stringValue == "2026-04-15")
  }

  @Test("update_task rejects an int raw_input instead of clearing it")
  func updateRejectsIntForString() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_task",
      arguments: ["title": .string("Keep raw input"), "raw_input": .string("original capture")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await xcall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "raw_input": .int(7)])
    expectMCPStructuredError(result, code: "validation", tool: "update_task")

    // `raw_input` is user-controlled text, so the read tool prompt-injection-fences
    // it (Rule 6); the point is that the original value survived rather than being
    // cleared to null.
    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    let rawInput = reread.structuredContent?.objectValue?["raw_input"]?.stringValue
    #expect(rawInput?.contains("original capture") == true)
  }

  @Test("update_task still clears estimated_minutes on an explicit JSON null")
  func updateClearsOnNull() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_task",
      arguments: ["title": .string("Clear estimate"), "estimated_minutes": .int(30)])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let result = try await xcall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "estimated_minutes": .null])
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["estimated_minutes"] == .null)
  }
}
