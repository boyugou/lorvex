import Foundation
import LorvexDomain
import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Helpers (file-private to avoid collision with sibling MCP test files)

private func xcall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func xstruct(_ result: CallTool.Result) -> [String: Value]? {
  result.structuredContent?.objectValue
}

private func makeTask(_ registry: ToolRegistry, title: String) async throws -> String {
  let created = try await xcall(registry, tool: "create_task", arguments: ["title": .string(title)])
  return try #require(xstruct(created)?["id"]?.stringValue)
}

/// Captures the ``ValidationError`` a strict decoder throws so its field/wording
/// can be asserted directly, keeping the shared-decoder unit tests independent of
/// the MCP dispatch layer.
private func captureValidationError(_ body: () throws -> Void) -> ValidationError? {
  do {
    try body()
    return nil
  } catch let error as ValidationError {
    return error
  } catch {
    return nil
  }
}

// MARK: - Shared decoder unit tests

@Suite("StrictArgumentArray — shared typed-array decoder")
struct StrictArgumentArrayTests {
  @Test("optionalStrings returns nil for an absent argument or JSON null")
  func optionalStringsAbsent() throws {
    #expect(try StrictArgumentArray.optionalStrings(nil, field: "tags") == nil)
    #expect(try StrictArgumentArray.optionalStrings(.null, field: "tags") == nil)
  }

  @Test("optionalStrings preserves an explicit empty array")
  func optionalStringsEmpty() throws {
    #expect(try StrictArgumentArray.optionalStrings(.array([]), field: "tags") == [])
  }

  @Test("optionalStrings decodes a homogeneous string array")
  func optionalStringsValid() throws {
    let decoded = try StrictArgumentArray.optionalStrings(
      .array([.string("a"), .string("b")]), field: "tags")
    #expect(decoded == ["a", "b"])
  }

  @Test("optionalStrings rejects a non-array value instead of treating it as absent")
  func optionalStringsRejectsNonArray() throws {
    let error = captureValidationError {
      _ = try StrictArgumentArray.optionalStrings(.string("urgent"), field: "tags")
    }
    #expect(error != nil)
    #expect(String(describing: error).contains("tags"))
  }

  @Test("optionalStrings rejects a wrong-typed element instead of dropping it")
  func optionalStringsRejectsBadElement() throws {
    // A bare compactMap would drop `.int(3)` and return ["a"], applying a smaller
    // set than the caller sent. The decoder must reject the whole array and name
    // the offending index.
    let error = captureValidationError {
      _ = try StrictArgumentArray.optionalStrings(
        .array([.string("a"), .int(3)]), field: "tags")
    }
    #expect(error != nil)
    #expect(String(describing: error).contains("tags[1]"))
  }

  @Test("requiredStrings defaults an absent argument to an empty array")
  func requiredStringsAbsent() throws {
    #expect(try StrictArgumentArray.requiredStrings(nil, field: "task_ids") == [])
    #expect(try StrictArgumentArray.requiredStrings(.null, field: "task_ids") == [])
  }

  @Test("requiredStrings still rejects a wrong-typed element")
  func requiredStringsRejectsBadElement() throws {
    let error = captureValidationError {
      _ = try StrictArgumentArray.requiredStrings(
        .array([.string("t1"), .bool(true)]), field: "task_ids")
    }
    #expect(error != nil)
    #expect(String(describing: error).contains("task_ids[1]"))
  }

  @Test("requiredUniqueStrings rejects the repeated element at its exact index")
  func requiredUniqueStringsRejectsDuplicate() throws {
    let error = captureValidationError {
      _ = try StrictArgumentArray.requiredUniqueStrings(
        .array([.string("a"), .string("b"), .string("a")]), field: "task_ids")
    }
    #expect(error != nil)
    #expect(String(describing: error).contains("task_ids[2]"))
  }
}

// MARK: - Representative single-tool handlers

@Suite("MCP ACF-05 rollout — representative handlers")
struct StrictArrayHandlerTests {
  @Test("create_task rejects a wrong-typed tags element instead of dropping it")
  func createTaskRejectsBadTag() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "create_task",
      arguments: ["title": .string("Tagged"), "tags": .array([.string("home"), .int(7)])])
    expectMCPStructuredError(result, code: "validation", tool: "create_task")
  }

  @Test("create_task still accepts an explicit empty tags array")
  func createTaskAllowsEmptyTags() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "create_task",
      arguments: ["title": .string("No tags"), "tags": .array([])])
    #expect(result.isError != true)
    #expect(xstruct(result)?["tags"]?.arrayValue?.isEmpty == true)
  }

  @Test("update_task rejects a wrong-typed depends_on element without mutating the task")
  func updateTaskRejectsBadDependsOn() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Keep tags")
    _ = try await xcall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "tags": .array([.string("keeper")])])

    let result = try await xcall(
      registry, tool: "update_task",
      arguments: ["id": .string(id), "depends_on": .array([.string("dep-1"), .int(2)])])
    expectMCPStructuredError(result, code: "validation", tool: "update_task")

    // The rejected call performed no mutation: the earlier tag survives rather
    // than being wiped alongside the malformed depends_on.
    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    #expect(reread.structuredContent?.objectValue?["tags"]?.arrayValue?.count == 1)
  }

  @Test("reorder_lists rejects a wrong-typed list_ids element")
  func reorderListsRejectsBadElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "reorder_lists",
      arguments: ["list_ids": .array([.string("list-a"), .int(3)])])
    expectMCPStructuredError(result, code: "validation", tool: "reorder_lists")
  }

  @Test("reorder_task_checklist_items rejects a wrong-typed item_ids element")
  func reorderChecklistRejectsBadElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = try await makeTask(registry, title: "Checklist owner")
    let result = try await xcall(
      registry, tool: "reorder_task_checklist_items",
      arguments: ["task_id": .string(taskID), "item_ids": .array([.string("item-1"), .null])])
    expectMCPStructuredError(result, code: "validation", tool: "reorder_task_checklist_items")
  }

  @Test("add_daily_review rejects a wrong-typed linked_task_ids element without saving a review")
  func addDailyReviewRejectsBadLink() async throws {
    let registry = try mcpInMemoryRegistry()
    let date = "2026-07-12"
    let result = try await xcall(
      registry, tool: "add_daily_review",
      arguments: [
        "date": .string(date),
        "summary": .string("Solid day"),
        "linked_task_ids": .array([.string("t1"), .int(9)]),
      ])
    expectMCPStructuredError(result, code: "validation", tool: "add_daily_review")

    // The rejected write did not persist a partial review: get_daily_review
    // returns `{date, review: null}` for a date that never had one saved.
    let reread = try await xcall(
      registry, tool: "get_daily_review", arguments: ["date": .string(date)])
    #expect(reread.structuredContent?.objectValue?["review"] == .null)
  }

  @Test("list_tasks rejects a wrong-typed tags filter element instead of filtering on a subset")
  func listTasksRejectsBadTagFilter() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "list_tasks",
      arguments: ["tags": .array([.string("work"), .int(1)])])
    expectMCPStructuredError(result, code: "validation", tool: "list_tasks")
  }

  @Test("list_tasks rejects a wrong-typed fields projection element")
  func listTasksRejectsBadFieldsElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "list_tasks",
      arguments: ["fields": .array([.string("title"), .int(5)])])
    expectMCPStructuredError(result, code: "validation", tool: "list_tasks")
  }

  @Test("get_recent_logs rejects a wrong-typed levels element")
  func recentLogsRejectsBadLevel() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "get_recent_logs",
      arguments: ["levels": .array([.string("info"), .int(2)])])
    expectMCPStructuredError(result, code: "validation", tool: "get_recent_logs")
  }
}

// MARK: - Batch tools (silent-partial-apply is the acute hazard here)

@Suite("MCP ACF-05 rollout — batch tools")
struct StrictArrayBatchTests {
  @Test("batch_complete_tasks rejects duplicate ids before mutating")
  func batchCompleteTasksRejectsDuplicateID() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Duplicate completion guard")
    let result = try await xcall(
      registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(id), .string(id)])])
    expectMCPStructuredError(result, code: "validation", tool: "batch_complete_tasks")

    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    #expect(reread.structuredContent?.objectValue?["status"]?.stringValue == "open")
  }

  @Test("batch_update_tasks rejects two patches for one entity before mutating")
  func batchUpdateTasksRejectsDuplicateID() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Original duplicate-patch title")
    let result = try await xcall(
      registry, tool: "batch_update_tasks",
      arguments: [
        "updates": .array([
          .object(["id": .string(id), "title": .string("First patch")]),
          .object(["id": .string(id), "title": .string("Second patch")]),
        ])
      ])
    expectMCPStructuredError(result, code: "validation", tool: "batch_update_tasks")

    let reread = try await xcall(registry, tool: "get_task", arguments: ["id": .string(id)])
    let expectedTitle: String = SecurityFencing.fence("Original duplicate-patch title")
    #expect(
      reread.structuredContent?.objectValue?["title"]?.stringValue
        == expectedTitle)
  }

  @Test("batch_create_calendar_events rejects duplicate original ids before any write")
  func batchCalendarCreateRejectsDuplicateOriginalID() async throws {
    let registry = try mcpInMemoryRegistry()
    let prefix = "Duplicate calendar guard \(UUID().uuidString)"
    let originalID = "11111111-1111-4111-8111-111111111111"
    let result = try await xcall(
      registry, tool: "batch_create_calendar_events",
      arguments: [
        "events": .array([
          .object([
            "title": .string("\(prefix) A"), "start_date": .string("2026-07-20"),
            "original_id": .string(originalID),
          ]),
          .object([
            "title": .string("\(prefix) B"), "start_date": .string("2026-07-21"),
            "original_id": .string(originalID),
          ]),
        ])
      ])
    expectMCPStructuredError(
      result, code: "validation", tool: "batch_create_calendar_events")

    let search = try await xcall(
      registry, tool: "search_calendar_events", arguments: ["query": .string(prefix)])
    #expect(search.structuredContent?.objectValue?["returned"]?.intValue == 0)
  }

  @Test("batch_complete_habits rejects a wrong-typed habit_ids element instead of dropping it")
  func batchCompleteHabitsRejectsBadElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_habit", arguments: ["name": .string("Stretch")])
    let habitID = try #require(xstruct(created)?["id"]?.stringValue)
    let result = try await xcall(
      registry, tool: "batch_complete_habits",
      arguments: ["habit_ids": .array([.string(habitID), .int(1)])])
    expectMCPStructuredError(result, code: "validation", tool: "batch_complete_habits")
  }

  @Test("reorder_habits rejects a wrong-typed habit_ids element")
  func reorderHabitsRejectsBadElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_habit", arguments: ["name": .string("Read")])
    let habitID = try #require(xstruct(created)?["id"]?.stringValue)
    let result = try await xcall(
      registry, tool: "reorder_habits",
      arguments: ["habit_ids": .array([.string(habitID), .bool(true)])])
    expectMCPStructuredError(result, code: "validation", tool: "reorder_habits")
  }

  @Test("batch_cancel_tasks_in_list rejects a wrong-typed statuses element")
  func batchCancelInListRejectsBadStatus() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "batch_cancel_tasks_in_list",
      arguments: [
        "list_id": .string("some-list"),
        "statuses": .array([.string("open"), .int(4)]),
      ])
    expectMCPStructuredError(result, code: "validation", tool: "batch_cancel_tasks_in_list")
  }

  @Test("set_current_focus rejects a wrong-typed task_ids element")
  func setCurrentFocusRejectsBadElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Focus target")
    let result = try await xcall(
      registry, tool: "set_current_focus",
      arguments: ["date": .string("2026-07-12"), "task_ids": .array([.string(id), .int(0)])])
    expectMCPStructuredError(result, code: "validation", tool: "set_current_focus")
  }

  @Test("add_to_current_focus rejects a wrong-typed task_ids element")
  func addToCurrentFocusRejectsBadElement() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Focus add target")
    let result = try await xcall(
      registry, tool: "add_to_current_focus",
      arguments: ["date": .string("2026-07-12"), "task_ids": .array([.string(id), .null])])
    expectMCPStructuredError(result, code: "validation", tool: "add_to_current_focus")
  }

  @Test("batch_create_tasks skips (does not drop) a row whose tags element is wrong-typed")
  func batchCreateSkipsRowWithBadTag() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object(["title": .string("Good row"), "tags": .array([.string("ok")])]),
          .object(["title": .string("Bad row"), "tags": .array([.string("ok"), .int(2)])]),
        ])
      ])
    #expect(result.isError != true)
    // The malformed row is reported as skipped rather than landing with its bad
    // tag silently pruned; the clean row still lands.
    #expect(xstruct(result)?["count"]?.intValue == 1)
    #expect(xstruct(result)?["skipped"]?.arrayValue?.count == 1)
    let reason = xstruct(result)?["skipped"]?.arrayValue?.first?.objectValue?["reason"]?.stringValue
    #expect(reason?.contains("tags") == true)
  }

  @Test("batch_update_tasks rejects the whole batch when a row's depends_on element is wrong-typed")
  func batchUpdateRejectsRowWithBadDependsOn() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeTask(registry, title: "Batch update target")
    let result = try await xcall(
      registry, tool: "batch_update_tasks",
      arguments: [
        "updates": .array([
          .object([
            "id": .string(id),
            "depends_on": .array([.string("dep"), .int(1)]),
          ])
        ])
      ])
    expectMCPStructuredError(result, code: "validation", tool: "batch_update_tasks")
  }
}
