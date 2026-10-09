import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// A whole-series edit that leaves the occurrence grid alone must not bring back an
/// occurrence the user skipped, whether it arrives through `edit_scoped_calendar_event`
/// with `all_in_series` or through `update_calendar_event`.
@Suite("MCP whole-series edits")
struct MCPScopedSeriesEditTests {
  private func createSeries(_ registry: ToolRegistry) async throws -> String {
    let created = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Daily stand"), "start_date": .string("2026-11-02"),
        "start_time": .string("09:00"), "end_time": .string("09:30"),
        "recurrence": .object(["freq": .string("DAILY"), "interval": .int(1), "count": .int(8)]),
      ])
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func occurrenceDates(_ registry: ToolRegistry) async throws -> [String] {
    let timeline = try await mcpRegistryCall(
      registry, tool: "get_calendar_timeline",
      arguments: ["from": .string("2026-11-01"), "to": .string("2026-11-12")])
    let events = try #require(timeline.structuredContent?.objectValue?["events"]?.arrayValue)
    return events.compactMap { $0.objectValue?["occurrence_date"]?.stringValue }.sorted()
  }

  @Test("edit_scoped_calendar_event all_in_series keeps skipped occurrences skipped")
  func scopedEditKeepsSkippedOccurrences() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createSeries(registry)
    _ = try await mcpRegistryCall(
      registry, tool: "add_calendar_event_exception",
      arguments: ["event_id": .string(id), "occurrence_date": .string("2026-11-04")])
    _ = try await mcpRegistryCall(
      registry, tool: "delete_scoped_calendar_event",
      arguments: [
        "event_id": .string(id), "occurrence_date": .string("2026-11-06"),
        "scope": .string("this_only"),
      ])

    let edited = try await mcpRegistryCall(
      registry, tool: "edit_scoped_calendar_event",
      arguments: [
        "event_id": .string(id), "occurrence_date": .string("2026-11-02"),
        "scope": .string("all_in_series"), "title": .string("Renamed stand"),
      ])

    #expect(edited.isError != true)
    let dates = try await occurrenceDates(registry)
    #expect(dates == ["2026-11-02", "2026-11-03", "2026-11-05", "2026-11-07", "2026-11-08", "2026-11-09"])
  }

  @Test("update_calendar_event keeps skipped occurrences skipped")
  func plainUpdateKeepsSkippedOccurrences() async throws {
    let registry = try mcpInMemoryRegistry()
    let id = try await createSeries(registry)
    _ = try await mcpRegistryCall(
      registry, tool: "add_calendar_event_exception",
      arguments: ["event_id": .string(id), "occurrence_date": .string("2026-11-04")])

    let updated = try await mcpRegistryCall(
      registry, tool: "update_calendar_event",
      arguments: ["event_id": .string(id), "title": .string("Renamed again")])

    #expect(updated.isError != true)
    let dates = try await occurrenceDates(registry)
    #expect(!dates.contains("2026-11-04"))
    #expect(dates.count == 7)
  }
}
