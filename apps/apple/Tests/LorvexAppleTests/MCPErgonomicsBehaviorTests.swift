import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// Behavioral coverage for the MCP ergonomics pass, run against the on-disk
/// Swift core bridge so each assertion exercises the full MCP tool →
/// `CoreBridgeClient` → `SwiftLorvexCoreService` write path:
///
/// - E3: task-scoped tools resolve the target task from `task_id`.
/// - E5: the day-planning tools default an omitted `date` to today.
/// - G1: `create_task` / `batch_create_tasks` build an ordered checklist in one
///   call, changelogged and idempotent-replay-safe.
/// - G2: `get_habits(include_stats: true)` enriches every row with stats fields.
@Suite("MCP ergonomics — behavior")
struct MCPErgonomicsBehaviorTests {
  private func createTask(
    _ fixture: (registry: ToolRegistry, dbPath: String, cleanup: () -> Void),
    title: String,
    extra: [String: Value] = [:]
  ) async throws -> String {
    var arguments: [String: Value] = ["title": .string(title)]
    for (key, value) in extra { arguments[key] = value }
    let created = try await mcpRegistryCall(fixture.registry, tool: "create_task", arguments: arguments)
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func tags(_ result: CallTool.Result) -> [String] {
    result.structuredContent?.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
  }

  private func checklistTexts(_ result: CallTool.Result) -> [String] {
    (result.structuredContent?.objectValue?["checklist_items"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["text"]?.stringValue }
  }

  // MARK: - E3: task-scoped tools resolve task_id

  @Test("E3: task-scoped tools resolve the target from task_id in every family")
  func e3TaskIDPerFamily() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let taskID = try await createTask(fixture, title: "Task-scoped target")

    // checklist family
    let checklist = try await mcpRegistryCall(
      fixture.registry, tool: "add_task_checklist_item",
      arguments: ["task_id": .string(taskID), "text": .string("step one")])
    #expect(checklist.isError != true)
    #expect(checklistTexts(checklist) == [SecurityFencing.fence("step one")])

    // reminder family
    let reminder = try await mcpRegistryCall(
      fixture.registry, tool: "add_task_reminder",
      arguments: ["task_id": .string(taskID), "reminder_at": .string("2027-01-15T09:00:00Z")])
    #expect(reminder.isError != true)

    // ai_notes family
    let aiNotes = try await mcpRegistryCall(
      fixture.registry, tool: "set_task_ai_notes",
      arguments: ["task_id": .string(taskID), "notes": .string("assistant context")])
    #expect(aiNotes.isError != true)

    // content family
    let appended = try await mcpRegistryCall(
      fixture.registry, tool: "append_to_task_body",
      arguments: ["task_id": .string(taskID), "text": .string("more detail")])
    #expect(appended.isError != true)

    // recurrence family
    let recurrence = try await mcpRegistryCall(
      fixture.registry, tool: "set_task_recurrence",
      arguments: [
        "task_id": .string(taskID),
        "recurrence": .object(["freq": .string("weekly"), "interval": .int(1)]),
      ])
    #expect(recurrence.isError != true)
  }

  @Test("E3: a task-scoped tool resolves task_id and rejects a call without it")
  func e3TaskIDResolvesAndMissingErrors() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let taskID = try await createTask(fixture, title: "Canonical")

    let viaTaskID = try await mcpRegistryCall(
      fixture.registry, tool: "add_task_checklist_item",
      arguments: ["task_id": .string(taskID), "text": .string("canonical step")])
    #expect(viaTaskID.isError != true)

    let missing = try await mcpRegistryCall(
      fixture.registry, tool: "add_task_checklist_item",
      arguments: ["text": .string("orphan")])
    expectMCPStructuredError(missing, code: "validation", tool: "add_task_checklist_item")

    // `id` is the task's own field name, not a task-scoped tool argument.
    let wrongName = try await mcpRegistryCall(
      fixture.registry, tool: "add_task_checklist_item",
      arguments: ["id": .string(taskID), "text": .string("wrong name")])
    expectMCPStructuredError(wrongName, code: "validation", tool: "add_task_checklist_item")
  }

  // MARK: - E5: day-planning tools default date to today

  @Test("E5: day-planning tools default an omitted date to today")
  func e5DayPlanningDefaultsToToday() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let today = try await fixture.registry.logicalDay(nil)

    let proposal = try await mcpRegistryCall(
      fixture.registry, tool: "propose_daily_schedule",
      arguments: ["include_calendar_events": .bool(false)])
    #expect(proposal.isError != true)
    #expect(proposal.structuredContent?.objectValue?["date"]?.stringValue == today)

    let read = try await mcpRegistryCall(fixture.registry, tool: "get_daily_schedule")
    #expect(read.structuredContent?.objectValue?["date"]?.stringValue == today)

    let briefing = try await mcpRegistryCall(
      fixture.registry, tool: "set_daily_briefing",
      arguments: ["briefing": .string("Start with the draft.")])
    #expect(briefing.structuredContent?.objectValue?["date"]?.stringValue == today)
  }

  // MARK: - G1: checklist at create

  @Test("G1: create_task builds an ordered, fenced, changelogged checklist")
  func g1CreateWithChecklist() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task",
      arguments: [
        "title": .string("With checklist"),
        "checklist": .array([.string("first"), .string("second"), .string("third")]),
      ])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // Items exist, in array order, with text fenced like every other user string.
    #expect(
      checklistTexts(created)
        == [
          SecurityFencing.fence("first"), SecurityFencing.fence("second"),
          SecurityFencing.fence("third"),
        ])
    // Positions ascend 0,1,2.
    let positions = (created.structuredContent?.objectValue?["checklist_items"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["position"]?.intValue }
    #expect(positions == [0, 1, 2])

    // Each item routed through the validated checklist path, so each is changelogged.
    let changelog = try await mcpRegistryCall(
      fixture.registry, tool: "get_ai_changelog",
      arguments: ["entity_id": .string(taskID), "operation": .string("checklist_add")])
    let entries = changelog.structuredContent?.objectValue?["entries"]?.arrayValue ?? []
    #expect(entries.count == 3)
  }

  @Test("G1: create_task with a checklist is idempotent-replay-safe")
  func g1ChecklistIdempotentReplay() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }
    let arguments: [String: Value] = [
      "title": .string("Replay"),
      "checklist": .array([.string("a"), .string("b")]),
      "idempotency_key": .string("ergonomics-g1-replay"),
    ]

    let first = try await mcpRegistryCall(fixture.registry, tool: "create_task", arguments: arguments)
    let taskID = try #require(first.structuredContent?.objectValue?["id"]?.stringValue)
    let replay = try await mcpRegistryCall(fixture.registry, tool: "create_task", arguments: arguments)

    // The replay returns the same task, not a second one.
    #expect(replay.structuredContent?.objectValue?["id"]?.stringValue == taskID)
    // And the task still has exactly two checklist items — the replay did not re-add.
    let fetched = try await mcpRegistryCall(
      fixture.registry, tool: "get_task", arguments: ["id": .string(taskID)])
    #expect(checklistTexts(fetched) == [SecurityFencing.fence("a"), SecurityFencing.fence("b")])
  }

  @Test("G1: an empty checklist item fails validation before the task is created")
  func g1EmptyChecklistItemRejected() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let result = try await mcpRegistryCall(
      fixture.registry, tool: "create_task",
      arguments: [
        "title": .string("Bad checklist"),
        "checklist": .array([.string("ok"), .string("   ")]),
      ])
    expectMCPStructuredError(result, code: "validation", tool: "create_task")
  }

  @Test("G1: batch_create_tasks builds a per-row checklist")
  func g1BatchCreateWithChecklist() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let batch = try await mcpRegistryCall(
      fixture.registry, tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object([
            "title": .string("Batch checklist"),
            "checklist": .array([.string("one"), .string("two")]),
          ])
        ])
      ])
    let row = try #require(batch.structuredContent?.objectValue?["results"]?.arrayValue?.first)
    let texts = (row.objectValue?["checklist_items"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["text"]?.stringValue }
    #expect(texts == [SecurityFencing.fence("one"), SecurityFencing.fence("two")])
  }

  // MARK: - G2: all-habit stats

  @Test("G2: get_habits(include_stats: true) enriches every row with stats fields")
  func g2IncludeStatsShape() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let habit = try await mcpRegistryCall(
      fixture.registry, tool: "create_habit", arguments: ["name": .string("Daily walk")])
    let habitID = try #require(habit.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "complete_habit", arguments: ["id": .string(habitID)])

    // Without the flag, the stats-only keys are absent.
    let plain = try await mcpRegistryCall(fixture.registry, tool: "get_habits")
    let plainRow = try #require(plain.structuredContent?.objectValue?["habits"]?.arrayValue?.first)
    #expect(plainRow.objectValue?["current_streak"] == nil)

    // With the flag, every row carries the get_habit_stats enrichment.
    let enriched = try await mcpRegistryCall(
      fixture.registry, tool: "get_habits", arguments: ["include_stats": .bool(true)])
    let row = try #require(enriched.structuredContent?.objectValue?["habits"]?.arrayValue?.first)
    let object = try #require(row.objectValue)
    #expect(object["current_streak"]?.intValue != nil)
    #expect(object["best_streak"]?.intValue != nil)
    #expect(object["completion_rate_30d"]?.doubleValue != nil)
    #expect(object["progress_kind"]?.stringValue != nil)

    // The enriched values agree with the single-habit stats tool.
    let stats = try await mcpRegistryCall(
      fixture.registry, tool: "get_habit_stats", arguments: ["habit_id": .string(habitID)])
    let statsObject = stats.structuredContent?.objectValue
    #expect(object["current_streak"]?.intValue == statsObject?["current_streak"]?.intValue)
    #expect(object["best_streak"]?.intValue == statsObject?["best_streak"]?.intValue)
  }
}
