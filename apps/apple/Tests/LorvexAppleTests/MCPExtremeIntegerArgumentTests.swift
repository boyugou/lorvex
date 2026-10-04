import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// An assistant can send any JSON integer. Whatever it sends, a tool answers
/// with a page, a success, or a validation error, and the host keeps running:
/// no integer argument may overflow arithmetic or a narrower integer type. A
/// trap here ends the whole test process, so every sweep goes through the one
/// helper that names the call it is making.
@Suite("MCP extreme integer arguments")
struct MCPExtremeIntegerArgumentTests {
  private static let extremes: [Int] = [
    Int.max, Int.max - 1, Int.min, Int.min + 1, -1, 0, 4_294_967_296, 2_147_483_648, -2_147_483_649,
  ]

  /// Calls `tool` and expects an answer: the registry turns every handler
  /// failure into an error result, so a thrown error or a missing result is a
  /// bug in the dispatch itself.
  private func answers(
    _ registry: ToolRegistry, tool: String, arguments: [String: Value], _ label: String
  ) async {
    let result = try? await mcpRegistryCall(registry, tool: tool, arguments: arguments)
    #expect(result != nil, "\(tool) \(label)")
  }

  /// Calls `tool` once per extreme value with `argument` set to it.
  private func sweep(
    _ registry: ToolRegistry, tool: String, argument: String, base: [String: Value] = [:]
  ) async {
    for value in Self.extremes {
      var arguments = base
      arguments[argument] = .int(value)
      await answers(registry, tool: tool, arguments: arguments, "\(argument)=\(value)")
    }
  }

  @Test("paged read tools answer any limit, offset, days or hours")
  func pagedReadTools() async throws {
    let registry = try mcpInMemoryRegistry()
    let paged: [(tool: String, base: [String: Value], arguments: [String])] = [
      ("search_calendar_events", ["query": .string("a")], ["limit", "offset"]),
      (
        "get_calendar_timeline",
        ["from": .string("2026-05-01"), "to": .string("2026-05-31")], ["limit", "offset"]
      ),
      ("read_memory", [:], ["limit", "offset"]),
      ("get_upcoming_tasks", [:], ["days", "limit", "offset"]),
      ("get_due_task_reminders", [:], ["limit", "offset"]),
      ("get_upcoming_task_reminders", [:], ["hours", "limit", "offset"]),
      ("list_tasks", [:], ["priority", "limit", "offset"]),
      ("search_tasks", ["query": .string("a")], ["limit", "offset"]),
      ("get_deferred_tasks", [:], ["limit", "offset"]),
      ("get_ai_changelog", [:], ["limit", "offset"]),
      ("get_recent_logs", [:], ["limit", "offset"]),
      ("get_review_history", [:], ["limit"]),
      (
        "get_weekly_brief", [:],
        ["completed_limit", "stalled_lists_limit", "deferred_limit", "someday_limit"]
      ),
    ]
    for entry in paged {
      for argument in entry.arguments {
        await sweep(registry, tool: entry.tool, argument: argument, base: entry.base)
      }
    }
  }

  @Test("an offset past any collection selects an empty page")
  func hugeOffsetSelectsAnEmptyPage() async throws {
    let registry = try await mcpSeededRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "list_tasks", arguments: ["offset": .int(Int.max)])

    #expect(result.isError != true)
    let structured = try #require(result.structuredContent?.objectValue)
    #expect(structured["returned"]?.intValue == 0)
  }

  @Test("task write tools answer any priority or estimate")
  func taskWriteTools() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Probe")])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    for argument in ["priority", "estimated_minutes"] {
      await sweep(registry, tool: "create_task", argument: argument, base: ["title": .string("A")])
      await sweep(registry, tool: "update_task", argument: argument, base: ["id": .string(id)])
      for value in Self.extremes {
        await answers(
          registry, tool: "batch_create_tasks",
          arguments: ["tasks": .array([.object(["title": .string("B"), argument: .int(value)])])],
          "\(argument)=\(value)")
        await answers(
          registry, tool: "batch_update_tasks",
          arguments: ["updates": .array([.object(["id": .string(id), argument: .int(value)])])],
          "\(argument)=\(value)")
      }
    }
  }

  @Test("habit tools answer any target, cadence, adjustment or limit")
  func habitTools() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: ["name": .string("Probe"), "target_count": .int(3)])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    await sweep(
      registry, tool: "create_habit", argument: "target_count", base: ["name": .string("A")])
    await sweep(
      registry, tool: "create_habit", argument: "milestone_target", base: ["name": .string("B")])
    await sweep(
      registry, tool: "create_habit", argument: "per_period_target",
      base: ["name": .string("C"), "frequency_type": .string("times_per_week")])
    await sweep(
      registry, tool: "create_habit", argument: "day_of_month",
      base: ["name": .string("D"), "frequency_type": .string("monthly")])
    for argument in ["target_count", "milestone_target"] {
      await sweep(registry, tool: "update_habit", argument: argument, base: ["id": .string(id)])
    }
    await sweep(
      registry, tool: "update_habit", argument: "per_period_target",
      base: ["id": .string(id), "frequency_type": .string("times_per_week")])
    await sweep(
      registry, tool: "update_habit", argument: "day_of_month",
      base: ["id": .string(id), "frequency_type": .string("monthly")])
    await sweep(
      registry, tool: "adjust_habit_completion", argument: "delta",
      base: ["id": .string(id), "date": .string("2026-05-25")])
    await sweep(
      registry, tool: "get_habit_completions", argument: "limit", base: ["habit_id": .string(id)])
  }

  @Test("an adjustment beyond the target lands on the target or on zero")
  func hugeHabitAdjustmentSaturates() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit",
      arguments: ["name": .string("Glasses"), "target_count": .int(3)])
    let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    func count(after delta: Int) async throws -> Int? {
      let result = try await mcpRegistryCall(
        registry, tool: "adjust_habit_completion",
        arguments: ["id": .string(id), "delta": .int(delta)])
      return result.structuredContent?.objectValue?["completions_today"]?.intValue
    }

    #expect(try await count(after: 1) == 1)
    #expect(try await count(after: Int.max) == 3)
    #expect(try await count(after: Int.max) == 3)
    #expect(try await count(after: Int.min) == 0)
  }

  @Test("recurrence rules answer any interval, count, position or ordinal")
  func recurrenceRules() async throws {
    let registry = try mcpInMemoryRegistry()
    let fields: [(name: String, value: (Int) -> Value)] = [
      ("interval", { .int($0) }),
      ("count", { .int($0) }),
      ("bymonthday", { .array([.int($0)]) }),
      ("bysetpos", { .array([.int($0)]) }),
      ("bymonth", { .array([.int($0)]) }),
      ("byday", { .array([.string("\($0)MO")]) }),
    ]
    for freq in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] {
      for field in fields {
        for number in Self.extremes {
          let rule: Value = .object(["freq": .string(freq), field.name: field.value(number)])
          let label = "\(freq) \(field.name)=\(number)"

          // A recurring task spawns its successor when completed, and an
          // event's occurrences are expanded when a range is read.
          let created = try await mcpRegistryCall(
            registry, tool: "create_task",
            arguments: ["title": .string("Rule"), "due_date": .string("2026-05-25")])
          let id = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
          await answers(
            registry, tool: "set_task_recurrence",
            arguments: ["task_id": .string(id), "recurrence": rule], label)
          await answers(
            registry, tool: "complete_task", arguments: ["id": .string(id)], label)
          await answers(
            registry, tool: "create_calendar_event",
            arguments: [
              "title": .string("Event"), "start_date": .string("2026-05-25"),
              "all_day": .bool(true), "recurrence": rule,
            ], label)
          await answers(
            registry, tool: "get_calendar_timeline",
            arguments: ["from": .string("2026-01-01"), "to": .string("2027-12-31")], label)
        }
      }
    }
  }

  @Test("daily review tools answer any mood or energy level")
  func reviewTools() async throws {
    let registry = try mcpInMemoryRegistry()
    let added = try await mcpRegistryCall(
      registry, tool: "add_daily_review", arguments: ["summary": .string("Probe")])
    let date = try #require(added.structuredContent?.objectValue?["date"]?.stringValue)

    for argument in ["mood", "energy_level"] {
      await sweep(
        registry, tool: "add_daily_review", argument: argument, base: ["summary": .string("A")])
      await sweep(
        registry, tool: "amend_daily_review", argument: argument, base: ["date": .string(date)])
    }
  }
}
