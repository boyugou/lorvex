import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// `skip_habit` and `unskip_habit`: an excused day set through the assistant.
/// A skipped day is neither done nor missed, a day holds a check-in or a skip
/// and never both, and a repeated call changes nothing.
@Suite("MCP habit skip")
struct MCPHabitSkipToolTests {
  private let date = "2026-06-04"
  private let nextDate = "2026-06-05"

  private func makeHabit(_ registry: ToolRegistry) async throws -> String {
    let created = try await mcpRegistryCall(
      registry, tool: "create_habit", arguments: ["name": .string("Cardio")])
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func call(
    _ registry: ToolRegistry, _ tool: String, _ id: String, on day: String? = nil
  ) async throws -> CallTool.Result {
    var arguments: [String: Value] = ["id": .string(id)]
    if let day { arguments["date"] = .string(day) }
    return try await mcpRegistryCall(registry, tool: tool, arguments: arguments)
  }

  /// The habit's row in `get_habits` for `day`.
  private func row(_ registry: ToolRegistry, _ id: String, on day: String) async throws -> [String: Value] {
    let result = try await mcpRegistryCall(
      registry, tool: "get_habits", arguments: ["date": .string(day)])
    let rows = (result.structuredContent?.objectValue?["habits"]?.arrayValue ?? [])
      .compactMap(\.objectValue)
    return try #require(rows.first { $0["id"]?.stringValue == id })
  }

  private func count(_ tool: String, in registry: ToolRegistry, _ id: String) async throws -> Int {
    try await mcpChangelogTools(registry, entityID: id).filter { $0 == tool }.count
  }

  @Test("skip_habit sets the day aside and get_habits reports it for that day only")
  func skipSetsTheDayAside() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)

    let result = try await call(registry, "skip_habit", id, on: date)

    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["skipped_today"]?.boolValue == true)
    #expect(object["completions_today"]?.intValue == 0)
    #expect(try await row(registry, id, on: date)["skipped_today"]?.boolValue == true)
    #expect(try await row(registry, id, on: nextDate)["skipped_today"]?.boolValue == false)
  }

  @Test("skipping a skipped day changes nothing")
  func skippingTwiceChangesNothing() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)
    _ = try await call(registry, "skip_habit", id, on: date)

    let again = try await call(registry, "skip_habit", id, on: date)

    #expect(again.isError != true)
    #expect(again.structuredContent?.objectValue?["skipped_today"]?.boolValue == true)
    #expect(try await count("skip_habit", in: registry, id) == 1)
  }

  @Test("unskip_habit takes the skip back, and taking back an open day changes nothing")
  func unskipTakesTheSkipBack() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)
    _ = try await call(registry, "skip_habit", id, on: date)

    let result = try await call(registry, "unskip_habit", id, on: date)
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["skipped_today"]?.boolValue == false)
    #expect(try await row(registry, id, on: date)["skipped_today"]?.boolValue == false)

    let again = try await call(registry, "unskip_habit", id, on: date)
    #expect(again.isError != true)
    #expect(try await count("unskip_habit", in: registry, id) == 1)
  }

  @Test("a check-in on a skipped day removes the skip")
  func aCheckInRemovesTheSkip() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)
    _ = try await call(registry, "skip_habit", id, on: date)

    let completed = try await call(registry, "complete_habit", id, on: date)

    let object = try #require(completed.structuredContent?.objectValue)
    #expect(object["completions_today"]?.intValue == 1)
    #expect(object["skipped_today"]?.boolValue == false)
    let reread = try await row(registry, id, on: date)
    #expect(reread["completions_today"]?.intValue == 1)
    #expect(reread["skipped_today"]?.boolValue == false)
  }

  @Test("batch_complete_habits clears a skipped day too")
  func aBatchCheckInRemovesTheSkip() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)
    _ = try await call(registry, "skip_habit", id, on: date)

    let batch = try await mcpRegistryCall(
      registry, tool: "batch_complete_habits",
      arguments: ["habit_ids": .array([.string(id)]), "date": .string(date)])

    #expect(batch.isError != true)
    #expect(batch.structuredContent?.objectValue?["count"]?.intValue == 1)
    let reread = try await row(registry, id, on: date)
    #expect(reread["completions_today"]?.intValue == 1)
    #expect(reread["skipped_today"]?.boolValue == false)
  }

  @Test("skip_habit refuses a day that already has a check-in and stores nothing")
  func skipRefusesACheckedInDay() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)
    _ = try await call(registry, "complete_habit", id, on: date)
    let before = try await mcpChangelogTools(registry, entityID: id)

    let result = try await call(registry, "skip_habit", id, on: date)

    expectMCPStructuredError(result, code: "validation", tool: "skip_habit")
    #expect(mcpTextContent(result).contains("already checked in"))
    #expect(try await mcpChangelogTools(registry, entityID: id) == before)
    #expect(try await row(registry, id, on: date)["skipped_today"]?.boolValue == false)

    _ = try await call(registry, "uncomplete_habit", id, on: date)
    let retry = try await call(registry, "skip_habit", id, on: date)
    #expect(retry.isError != true)
    #expect(retry.structuredContent?.objectValue?["skipped_today"]?.boolValue == true)
  }

  @Test("an unknown habit and a malformed date are refused")
  func refusesBadInput() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)

    for tool in ["skip_habit", "unskip_habit"] {
      let unknown = try await call(registry, tool, "no-such-habit", on: date)
      expectMCPStructuredError(unknown, code: "not_found", tool: tool)

      let malformed = try await call(registry, tool, id, on: "June 4")
      expectMCPStructuredError(malformed, code: "validation", tool: tool)

      let missing = try await mcpRegistryCall(registry, tool: tool, arguments: [:])
      expectMCPStructuredError(missing, code: "validation", tool: tool)
    }
    #expect(try await count("skip_habit", in: registry, id) == 0)
  }

  @Test("a repeated idempotency key replays the skip without a second write")
  func idempotencyKeyReplays() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await makeHabit(registry)
    let arguments: [String: Value] = [
      "id": .string(id), "date": .string(date), "idempotency_key": .string("skip-cardio-1"),
    ]

    let first = try await mcpRegistryCall(registry, tool: "skip_habit", arguments: arguments)
    _ = try await call(registry, "unskip_habit", id, on: date)
    let replay = try await mcpRegistryCall(registry, tool: "skip_habit", arguments: arguments)

    #expect(first.isError != true)
    #expect(replay.isError != true)
    #expect(try await count("skip_habit", in: registry, id) == 1)
    #expect(
      try await row(registry, id, on: date)["skipped_today"]?.boolValue == false,
      "the replay must not skip the day again after the unskip")
  }
}
