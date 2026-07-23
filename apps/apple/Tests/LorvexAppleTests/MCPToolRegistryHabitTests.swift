import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Tool Registry — habit area")
struct HabitToolTests {

  /// Creates a daily habit and returns its id.
  private func makeHabit(_ registry: ToolRegistry, name: String) async throws -> String {
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string(name)])
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  @Test("create_habit then complete_habit round-trip")
  func createAndCompleteHabit() async throws {
    let registry = try mcpInMemoryRegistry()
    let createResult = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: ["name": .string("Test Habit"), "cue": .string("Morning")]
    )
    #expect(createResult.isError != true)

    guard
      let obj = createResult.structuredContent?.objectValue,
      let idValue = obj["id"],
      let habitID = idValue.stringValue
    else {
      Issue.record("create_habit did not return structured content with an id")
      return
    }

    // Completing without a date records today's completion, which is what
    // `completions_today` counts (a past-dated completion would leave it 0).
    let completeResult = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string(habitID)]
    )
    #expect(completeResult.isError != true)
    let completions = completeResult.structuredContent?.objectValue?["completions_today"]?.intValue
    #expect(completions == 1)
  }

  @Test("create_habit with missing name returns structured error")
  func createHabitMissingName() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "create_habit", arguments: [:])
    #expect(result.isError == true)
  }

  @Test("create_habit rejects target_count below 1 (matches update_habit)")
  func createHabitRejectsZeroTarget() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: ["name": .string("Zero"), "target_count": .int(0)])
    #expect(result.isError == true)
  }

  @Test("create_habit rejects a non-integer weekday rather than dropping it")
  func createHabitRejectsNonIntegerWeekday() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: [
        "name": .string("Weekly"),
        "frequency_type": .string("weekly"),
        "weekdays": .array([.int(0), .string("tue")]),
      ])
    #expect(result.isError == true)
  }

  @Test("complete_habit with unknown id returns structured error")
  func completeHabitUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string("no-such-habit"), "date": .string("2026-05-24")]
    )
    #expect(result.isError == true)
  }

  @Test("get_habits habit carries the full production field set")
  func getHabits() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await makeHabit(registry, name: "Field-set habit")
    let result = try await mcpRegistryCall(registry, tool: "get_habits")
    #expect(result.isError != true)
    let habit = try #require(result.structuredContent?.objectValue?["habits"]?.arrayValue?.first?.objectValue)
    // Every key the on-disk core adapter emits must be present, including the
    // milestone standing fields.
    for key in [
      "id", "name", "cue", "icon", "color", "frequency_type", "weekdays",
      "per_period_target", "day_of_month", "target_count", "completions_today",
      "total_completions", "archived", "milestone_target", "milestone_metric",
      "milestone_value", "next_milestone", "progress_to_next",
    ] {
      #expect(habit.keys.contains(key), "missing \(key)")
    }
  }

  @Test("get_habit_completions returns recorded completions")
  func getHabitCompletions() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Completions habit")
    _ = try await mcpRegistryCall(
      registry,
      tool: "complete_habit",
      arguments: ["id": .string(habitID)]
    )

    let result = try await mcpRegistryCall(
      registry,
      tool: "get_habit_completions",
      arguments: ["habit_id": .string(habitID)]
    )

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["habit_id"]?.stringValue == habitID)
    #expect(result.structuredContent?.objectValue?["completions"]?.arrayValue?.isEmpty == false)
  }

  @Test("get_habit_stats returns stats for a real habit")
  func getHabitStats() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Stats habit")
    let result = try await mcpRegistryCall(
      registry,
      tool: "get_habit_stats",
      arguments: ["habit_id": .string(habitID)]
    )

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["habit_id"]?.stringValue == habitID)
    #expect(result.structuredContent?.objectValue?["progress_kind"]?.stringValue != nil)
  }

  @Test("upsert_habit_reminder_policy then get_habit_reminder_policies round-trips the policy")
  func upsertAndGetHabitReminderPolicy() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Reminder policy habit")
    let upsert = try await mcpRegistryCall(
      registry,
      tool: "upsert_habit_reminder_policy",
      arguments: [
        "habit_id": .string(habitID),
        "reminder_time": .string("18:30"),
        "enabled": .bool(true),
      ]
    )
    #expect(upsert.isError != true)
    let policyID = try #require(upsert.structuredContent?.objectValue?["id"]?.stringValue)

    let list = try await mcpRegistryCall(
      registry,
      tool: "get_habit_reminder_policies",
      arguments: ["habit_id": .string(habitID)]
    )

    #expect(list.isError != true)
    let policies = list.structuredContent?.objectValue?["policies"]?.arrayValue ?? []
    #expect(policies.contains { $0.objectValue?["id"]?.stringValue == policyID })
    #expect(policies.first?.objectValue?["reminder_time"]?.stringValue == "18:30")
  }

  @Test("upsert_habit_reminder_policy rejects an invalid time")
  func upsertHabitReminderPolicyInvalidTime() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Bad time habit")
    let result = try await mcpRegistryCall(
      registry,
      tool: "upsert_habit_reminder_policy",
      arguments: [
        "habit_id": .string(habitID),
        "reminder_time": .string("25:99"),
      ]
    )

    #expect(result.isError == true)
  }

  @Test("update_habit patches habit fields")
  func updateHabit() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Habit to update")
    let result = try await mcpRegistryCall(
      registry,
      tool: "update_habit",
      arguments: [
        "id": .string(habitID),
        "name": .string("Review updated"),
        "target_count": .int(2),
      ]
    )

    #expect(result.isError != true)
    let fencedName: String = SecurityFencing.fence("Review updated")
    #expect(result.structuredContent?.objectValue?["name"]?.stringValue == fencedName)
    #expect(result.structuredContent?.objectValue?["target_count"]?.intValue == 2)
  }

  @Test("batch_complete_habits completes the supplied habits")
  func batchCompleteHabits() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Batch habit")
    let result = try await mcpRegistryCall(
      registry,
      tool: "batch_complete_habits",
      arguments: [
        "habit_ids": .array([.string(habitID)])
      ]
    )

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["count"]?.intValue == 1)
    // Unified batch shape: full habit objects under `results`, not `habits`.
    #expect(result.structuredContent?.objectValue?["results"]?.arrayValue?.count == 1)
    #expect(result.structuredContent?.objectValue?["habits"] == nil)
    #expect(result.structuredContent?.objectValue?["skipped"]?.arrayValue != nil)
  }

  @Test("delete_habit removes the habit")
  func deleteHabit() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = try await makeHabit(registry, name: "Habit to delete")
    let result = try await mcpRegistryCall(
      registry,
      tool: "delete_habit",
      arguments: ["id": .string(habitID)]
    )

    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["deleted"]?.boolValue == true)

    // The deleted habit no longer lists.
    let habits = try await mcpRegistryCall(registry, tool: "get_habits")
    let remaining = habits.structuredContent?.objectValue?["habits"]?.arrayValue ?? []
    #expect(!remaining.contains { $0.objectValue?["id"]?.stringValue == habitID })
  }

  @Test("delete_habit of a missing id reports deleted:false, not a spurious success")
  func deleteHabitOfMissingIdReportsDeletedFalse() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "delete_habit", arguments: ["id": .string("does-not-exist")])
    #expect(result.isError != true)
    #expect(
      result.structuredContent?.objectValue?["deleted"]?.boolValue == false,
      "deleting a nonexistent habit is a no-op and must not report deleted:true")
  }

  @Test("reorder_habits sets the manual order and returns the refreshed board")
  func reorderHabitsRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await makeHabit(registry, name: "Alpha habit")
    _ = try await makeHabit(registry, name: "Beta habit")

    func boardIDs(_ result: CallTool.Result) -> [String] {
      result.structuredContent?.objectValue?["habits"]?.arrayValue?
        .compactMap { $0.objectValue?["id"]?.stringValue } ?? []
    }

    let before = try await mcpRegistryCall(registry, tool: "get_habits")
    let original = boardIDs(before)
    #expect(original.count == 2)
    let reversed = Array(original.reversed())
    #expect(reversed != original)

    let reordered = try await mcpRegistryCall(
      registry, tool: "reorder_habits",
      arguments: ["habit_ids": .array(reversed.map(Value.string))])
    #expect(reordered.isError != true)
    // Rich return per Core Design Rule 7: the full refreshed board in the new order.
    #expect(boardIDs(reordered) == reversed)

    let after = try await mcpRegistryCall(registry, tool: "get_habits")
    #expect(boardIDs(after) == reversed)
  }

  @Test("reorder_habits with an empty habit_ids array is a validation error")
  func reorderHabitsRejectsEmpty() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "reorder_habits", arguments: ["habit_ids": .array([])])
    #expect(result.isError == true)
  }
}
