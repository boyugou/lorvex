import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

/// MCP-surface coverage for habit milestones against the on-disk core: the
/// create/update `milestone_target` param and the milestone fields
/// `get_habits` / `get_habit_stats` expose.
@Suite("MCP Tool Registry — habit milestones")
struct HabitMilestoneToolTests {

  private func createHabit(
    _ registry: ToolRegistry, name: String, arguments extra: [String: Value] = [:]
  ) async throws -> String {
    var args: [String: Value] = ["name": .string(name)]
    args.merge(extra) { _, new in new }
    let result = try await mcpRegistryCall(registry, tool: "create_habit", arguments: args)
    #expect(result.isError != true)
    return try #require(result.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func habit(in result: CallTool.Result, id: String) -> [String: Value]? {
    result.structuredContent?.objectValue?["habits"]?.arrayValue?
      .compactMap(\.objectValue)
      .first { $0["id"]?.stringValue == id }
  }

  @Test("create_habit with milestone_target surfaces it in get_habits")
  func createWithMilestone() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let id = try await createHabit(
      registry, name: "Meditate", arguments: ["milestone_target": .int(30)])

    let habits = try await mcpRegistryCall(registry, tool: "get_habits")
    let created = try #require(habit(in: habits, id: id))
    #expect(created["milestone_target"]?.intValue == 30)
    #expect(created["milestone_metric"]?.stringValue == "streak")
    #expect(created["milestone_value"]?.intValue == 0)
    // A daily habit at 0 aims for the user target (30) before the ladder.
    #expect(created["next_milestone"]?.intValue == 30)
    #expect(created["progress_to_next"] != nil)
  }

  @Test("update_habit sets then clears milestone_target")
  func updateSetThenClear() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let id = try await createHabit(registry, name: "Read")

    _ = try await mcpRegistryCall(
      registry, tool: "update_habit",
      arguments: ["id": .string(id), "milestone_target": .int(14)])
    var habits = try await mcpRegistryCall(registry, tool: "get_habits")
    #expect(try #require(habit(in: habits, id: id))["milestone_target"]?.intValue == 14)

    // JSON null clears the goal; the next milestone falls back to the ladder (7).
    _ = try await mcpRegistryCall(
      registry, tool: "update_habit",
      arguments: ["id": .string(id), "milestone_target": .null])
    habits = try await mcpRegistryCall(registry, tool: "get_habits")
    let cleared = try #require(habit(in: habits, id: id))
    #expect(cleared["milestone_target"] == .null)
    #expect(cleared["next_milestone"]?.intValue == 7)
  }

  @Test("complete_habit reports reached_milestone at a boundary")
  func completeFlagsReachedMilestone() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }

    // A milestone target of 1: the first completion (streak 0→1) crosses it.
    let hit = try await createHabit(
      registry, name: "Hit", arguments: ["milestone_target": .int(1)])
    let hitResult = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string(hit), "date": .string("2026-06-30")])
    #expect(hitResult.structuredContent?.objectValue?["reached_milestone"]?.intValue == 1)

    // A distant target: one completion crosses nothing, so reached_milestone is null.
    let miss = try await createHabit(
      registry, name: "Miss", arguments: ["milestone_target": .int(30)])
    let missResult = try await mcpRegistryCall(
      registry, tool: "complete_habit",
      arguments: ["id": .string(miss), "date": .string("2026-06-30")])
    #expect(missResult.structuredContent?.objectValue?["reached_milestone"] == .null)
  }

  @Test("batch_complete_habits reports reached_milestone per result")
  func batchFlagsReachedMilestone() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let id = try await createHabit(
      registry, name: "BatchHit", arguments: ["milestone_target": .int(1)])
    let result = try await mcpRegistryCall(
      registry, tool: "batch_complete_habits",
      arguments: ["habit_ids": .array([.string(id)]), "date": .string("2026-06-30")])
    let first = try #require(
      result.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue)
    #expect(first["reached_milestone"]?.intValue == 1)
  }

  @Test("get_habit_stats exposes the milestone standing")
  func statsExposeMilestone() async throws {
    let (registry, _, cleanup) = mcpOnDiskRegistry()
    defer { cleanup() }
    let id = try await createHabit(
      registry, name: "Journal", arguments: ["milestone_target": .int(30)])

    let result = try await mcpRegistryCall(
      registry, tool: "get_habit_stats", arguments: ["habit_id": .string(id)])
    let stats = try #require(result.structuredContent?.objectValue)
    #expect(stats["current_streak"] != nil)
    #expect(stats["best_streak"] != nil)
    #expect(stats["milestone_target"]?.intValue == 30)
    #expect(stats["next_milestone"]?.intValue == 30)
    #expect(stats["progress_to_next"] != nil)
  }
}
