import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// Delete / unlink / focus / batch tools must report the REAL outcome: a no-op
/// returns `deleted`/`removed`/`cleared` = false (and writes no `ai_changelog`
/// row), rather than a phantom success. These run against the on-disk Swift core
/// bridge, where the outcome flag was previously hardcoded.
@Suite("MCP no-op honesty")
struct MCPNoOpHonestyTests {

  @Test("delete_calendar_event reports the real outcome and carries previous")
  func deleteCalendarEventHonesty() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }

    let created = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Deletable event"), "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
      ])
    let createdObject = try #require(created.structuredContent?.objectValue)
    let eventID = try #require(createdObject["event_id"]?.stringValue)
    #expect(createdObject["id"]?.stringValue == eventID)

    let deleted = try await mcpRegistryCall(
      registry, tool: "delete_calendar_event", arguments: ["event_id": .string(eventID)])
    let object = try #require(deleted.structuredContent?.objectValue)
    #expect(object["deleted"]?.boolValue == true)
    #expect(object["id"]?.stringValue == eventID)
    #expect(object["previous"]?.objectValue?["id"]?.stringValue == eventID)

    // Deleting the same (now-absent) event is a no-op: deleted:false, previous null.
    let noop = try await mcpRegistryCall(
      registry, tool: "delete_calendar_event", arguments: ["event_id": .string(eventID)])
    let noopObject = try #require(noop.structuredContent?.objectValue)
    #expect(noopObject["deleted"]?.boolValue == false)
    #expect(noopObject["previous"] == .null)
  }

  @Test("unlink_task_from_provider_event reports deleted:false on a no-op")
  func unlinkNoOpHonesty() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }

    let task = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Never-linked task")])
    let taskID = try #require(task.structuredContent?.objectValue?["id"]?.stringValue)

    // The task was never linked to this provider event, so unlinking removes
    // nothing: deleted:false, and no ai_changelog row is written.
    let noop = try await mcpRegistryCall(
      registry, tool: "unlink_task_from_provider_event",
      arguments: ["task_id": .string(taskID), "provider_event_id": .string("ek-never")])
    #expect(noop.structuredContent?.objectValue?["deleted"]?.boolValue == false)
  }

  @Test("clear_current_focus reports whether a plan was actually cleared")
  func clearFocusHonesty() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-02"

    // Clearing an empty day is a no-op: cleared:false.
    let empty = try await mcpRegistryCall(
      registry, tool: "clear_current_focus", arguments: ["date": .string(date)])
    #expect(empty.structuredContent?.objectValue?["cleared"]?.boolValue == false)

    let task = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Focus task")])
    let taskID = try #require(task.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "set_current_focus",
      arguments: ["date": .string(date), "task_ids": .array([.string(taskID)])])

    let cleared = try await mcpRegistryCall(
      registry, tool: "clear_current_focus", arguments: ["date": .string(date)])
    let object = try #require(cleared.structuredContent?.objectValue)
    #expect(object["cleared"]?.boolValue == true)
    // The cleared plan is echoed under previous.
    #expect(object["previous"]?.objectValue?["task_count"]?.intValue == 1)
  }

  @Test("remove_from_current_focus reports whether the task was in focus")
  func removeFocusHonesty() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-03"

    let a = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("In focus")])
    let inFocusID = try #require(a.structuredContent?.objectValue?["id"]?.stringValue)
    let b = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Not in focus")])
    let outsideID = try #require(b.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "set_current_focus",
      arguments: ["date": .string(date), "task_ids": .array([.string(inFocusID)])])

    // Removing a task that was never in focus is a no-op: removed:false.
    let noop = try await mcpRegistryCall(
      registry, tool: "remove_from_current_focus",
      arguments: ["date": .string(date), "task_id": .string(outsideID)])
    #expect(noop.structuredContent?.objectValue?["removed"]?.boolValue == false)

    let real = try await mcpRegistryCall(
      registry, tool: "remove_from_current_focus",
      arguments: ["date": .string(date), "task_id": .string(inFocusID)])
    #expect(real.structuredContent?.objectValue?["removed"]?.boolValue == true)
  }

  /// B-12: a focus no-op must short-circuit before the write transaction, so it
  /// records no ai_changelog row (previously `remove_from_current_focus` of a
  /// task not in focus wrote a null-effect "set current focus" row).
  @Test("focus no-ops write no ai_changelog row")
  func focusNoOpWritesNoChangelog() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-05"

    func focusChangelogCount(for entityID: String) async throws -> Int {
      let log = try await mcpRegistryCall(
        registry, tool: "get_ai_changelog",
        arguments: ["limit": .int(50), "entity_id": .string(entityID)])
      return log.structuredContent?.objectValue?["entries"]?.arrayValue?.count ?? 0
    }

    // Clearing a day that never had a plan is a pure no-op: no changelog row.
    let emptyDate = "2026-06-06"
    _ = try await mcpRegistryCall(
      registry, tool: "clear_current_focus", arguments: ["date": .string(emptyDate)])
    #expect(try await focusChangelogCount(for: emptyDate) == 0)

    let inFocus = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Planned")])
    let inFocusID = try #require(inFocus.structuredContent?.objectValue?["id"]?.stringValue)
    let outside = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Unplanned")])
    let outsideID = try #require(outside.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "set_current_focus",
      arguments: ["date": .string(date), "task_ids": .array([.string(inFocusID)])])
    // The set itself wrote one changelog row for the date.
    let afterSet = try await focusChangelogCount(for: date)
    #expect(afterSet == 1)

    // Removing a task that was never in the plan changes nothing: no new row.
    _ = try await mcpRegistryCall(
      registry, tool: "remove_from_current_focus",
      arguments: ["date": .string(date), "task_id": .string(outsideID)])
    #expect(try await focusChangelogCount(for: date) == afterSet)
  }

  @Test("batch_complete_habits excludes already-complete habits from results/count")
  func batchCompleteHabitsHonesty() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-04"

    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Daily walk")])
    let habitID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string(habitID), "date": .string(date)])

    // The habit is already complete for the day; batch-completing it is a no-op.
    let batch = try await mcpRegistryCall(
      registry, tool: "batch_complete_habits",
      arguments: ["habit_ids": .array([.string(habitID)]), "date": .string(date)])
    let object = try #require(batch.structuredContent?.objectValue)
    #expect(object["count"]?.intValue == 0)
    #expect(object["results"]?.arrayValue?.isEmpty == true)
    let skipped = try #require(object["skipped"]?.arrayValue)
    #expect(skipped.first?.objectValue?["id"]?.stringValue == habitID)
    #expect(skipped.first?.objectValue?["reason"]?.stringValue == "already complete")
  }

  @Test("batch_complete_habits reports an unknown id as skipped `not found`, not a silent drop")
  func batchCompleteHabitsReportsUnknownIds() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-05"

    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Daily walk")])
    let habitID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // A real habit and a nonexistent id in one batch: the real habit completes and
    // the unknown id is reported as skipped `not found`. Before the core skipped
    // unknown ids, the `habit_completions.habit_id` foreign key would have rejected
    // the missing-habit insert and rolled the whole batch back.
    let batch = try await mcpRegistryCall(
      registry, tool: "batch_complete_habits",
      arguments: [
        "habit_ids": .array([.string(habitID), .string("ghost-habit")]),
        "date": .string(date),
      ])
    let object = try #require(batch.structuredContent?.objectValue)
    #expect(object["count"]?.intValue == 1)
    #expect(object["results"]?.arrayValue?.count == 1)
    let skipped = try #require(object["skipped"]?.arrayValue)
    #expect(skipped.count == 1)
    #expect(skipped.first?.objectValue?["id"]?.stringValue == "ghost-habit")
    #expect(skipped.first?.objectValue?["reason"]?.stringValue == "not found")
  }
}
