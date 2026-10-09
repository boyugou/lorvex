import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// Delete / unlink / day-time / batch tools must report the REAL outcome: a
/// no-op returns `deleted`/`removed` = false or an empty `cleared_tasks` (and
/// writes no `ai_changelog` row), rather than a phantom success. These run against the on-disk Swift core
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

  @Test("save_daily_schedule reports the times a save actually cleared")
  func clearDayTimesHonesty() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-02"

    // Clearing a day with no times is a no-op: no cleared tasks.
    let empty = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": .array([])])
    #expect(empty.isError != true)
    #expect(empty.structuredContent?.objectValue?["cleared_tasks"]?.arrayValue?.isEmpty == true)

    let task = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Timed task")])
    let taskID = try #require(task.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: [
        "date": .string(date),
        "times": .array([
          .object([
            "task_id": .string(taskID), "start_time": .string("09:00"),
            "end_time": .string("10:00"),
          ])
        ]),
      ])

    let cleared = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": .array([])])
    let clearedIDs = cleared.structuredContent?.objectValue?["cleared_tasks"]?.arrayValue?
      .compactMap { $0.objectValue?["id"]?.stringValue }
    #expect(clearedIDs == [taskID])
  }

  /// A save that changes no task's time short-circuits before any write, so it
  /// records no ai_changelog row for the date.
  @Test("day-time no-ops write no ai_changelog row")
  func dayTimesNoOpWritesNoChangelog() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let date = "2026-06-05"

    func dayChangelogCount(for day: String) async throws -> Int {
      let log = try await mcpRegistryCall(
        registry, tool: "get_ai_changelog",
        arguments: ["limit": .int(50), "entity_id": .string(day)])
      return log.structuredContent?.objectValue?["entries"]?.arrayValue?.count ?? 0
    }

    // Clearing a day that never had times is a pure no-op: no changelog row.
    let emptyDate = "2026-06-06"
    _ = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(emptyDate), "times": .array([])])
    #expect(try await dayChangelogCount(for: emptyDate) == 0)

    let task = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Planned")])
    let taskID = try #require(task.structuredContent?.objectValue?["id"]?.stringValue)
    let times: Value = .array([
      .object([
        "task_id": .string(taskID), "start_time": .string("09:00"),
        "end_time": .string("10:00"),
      ])
    ])
    _ = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": times])
    // The save itself wrote one changelog row for the date.
    let afterSave = try await dayChangelogCount(for: date)
    #expect(afterSave == 1)

    // Saving the same times again changes nothing: no new row.
    _ = try await mcpRegistryCall(
      registry, tool: "save_daily_schedule",
      arguments: ["date": .string(date), "times": times])
    #expect(try await dayChangelogCount(for: date) == afterSave)
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

  @Test("archive_list and unarchive_list on a list already in that state write no changelog row")
  func listArchiveNoOpsWriteNoChangelog() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_list", arguments: ["name": .string("Projects")])
    let listID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // A new list is active, so unarchiving it changes nothing.
    let unarchive = try await mcpRegistryCall(
      registry, tool: "unarchive_list", arguments: ["id": .string(listID)])
    #expect(unarchive.structuredContent?.objectValue?["archived"]?.boolValue == false)
    #expect(try await mcpChangelogTools(registry, entityID: listID) == ["create_list"])

    _ = try await mcpRegistryCall(
      registry, tool: "archive_list", arguments: ["id": .string(listID)])
    let afterArchive = try await mcpChangelogTools(registry, entityID: listID)
    #expect(afterArchive == ["archive_list", "create_list"])

    // Archiving an archived list changes nothing either.
    let again = try await mcpRegistryCall(
      registry, tool: "archive_list", arguments: ["id": .string(listID)])
    #expect(again.structuredContent?.objectValue?["archived"]?.boolValue == true)
    #expect(try await mcpChangelogTools(registry, entityID: listID) == afterArchive)
  }

  @Test("set_task_reminders with no reminders on a task without any writes no changelog row")
  func clearingNoRemindersWritesNoChangelog() async throws {
    let registry = try mcpInMemoryRegistry()
    let task = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("No reminders")])
    let taskID = try #require(task.structuredContent?.objectValue?["id"]?.stringValue)
    let changelogBefore = try await mcpChangelogTools(registry, entityID: taskID)

    let result = try await mcpRegistryCall(
      registry, tool: "set_task_reminders",
      arguments: ["task_id": .string(taskID), "reminders": .array([])])

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["id"]?.stringValue == taskID)
    #expect(try await mcpChangelogTools(registry, entityID: taskID) == changelogBefore)
  }

  @Test("delete tools say so when there was nothing to delete")
  func deleteToolsSayNothingWasDeleted() async throws {
    let registry = try mcpInMemoryRegistry()
    let unknownID = "01a11e52-1169-72c5-a925-f36e5d8937ba"

    let list = try await mcpRegistryCall(
      registry, tool: "delete_list", arguments: ["id": .string(unknownID)])
    #expect(list.structuredContent?.objectValue?["deleted"]?.boolValue == false)
    #expect(mcpTextContent(list).contains("nothing was deleted"))

    let habit = try await mcpRegistryCall(
      registry, tool: "delete_habit", arguments: ["id": .string(unknownID)])
    #expect(habit.structuredContent?.objectValue?["deleted"]?.boolValue == false)
    #expect(mcpTextContent(habit).contains("nothing was deleted"))

    let event = try await mcpRegistryCall(
      registry, tool: "delete_calendar_event", arguments: ["event_id": .string(unknownID)])
    #expect(event.structuredContent?.objectValue?["deleted"]?.boolValue == false)
    #expect(mcpTextContent(event).contains("nothing was deleted"))

    // `language` is a known preference key that a fresh store has not set.
    let preference = try await mcpRegistryCall(
      registry, tool: "delete_preference", arguments: ["key": .string("language")])
    #expect(preference.structuredContent?.objectValue?["deleted"]?.boolValue == false)
    #expect(mcpTextContent(preference).contains("was not set"))
  }
}
