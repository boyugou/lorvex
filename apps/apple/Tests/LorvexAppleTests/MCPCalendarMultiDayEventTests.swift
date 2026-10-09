import Foundation
import MCP
import Testing

@testable import LorvexMCPHost

/// A timed event that ends on a later day needs an end time: the schema admits
/// an open end only for an all-day event or one that ends the day it starts.
/// The tool says so in a validation error instead of surfacing the database's
/// constraint text. An all-day event holds no times, so a time patch that does
/// not also turn `all_day` off is refused the same way.
@Suite("MCP multi-day calendar events")
struct MCPCalendarMultiDayEventTests {
  @Test("a timed event ending on a later day without end_time is a validation error")
  func timedMultiDayEventNeedsAnEndTime() async throws {
    let registry = try mcpInMemoryRegistry()

    let result = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Offsite"), "start_date": .string("2026-11-05"),
        "start_time": .string("09:30"), "end_date": .string("2026-11-07"),
      ])

    expectMCPStructuredError(result, code: "validation", tool: "create_calendar_event")
    #expect(mcpTextContent(result).contains("end_time is required"))
    #expect(!mcpTextContent(result).contains("SQLite"))
  }

  @Test("a timed multi-day event with end_time and an all-day multi-day event are created")
  func multiDayEventsWithTheirTimesAreCreated() async throws {
    let registry = try mcpInMemoryRegistry()

    let timed = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Offsite"), "start_date": .string("2026-11-05"),
        "start_time": .string("09:30"), "end_date": .string("2026-11-07"),
        "end_time": .string("16:00"),
      ])
    #expect(timed.isError != true)

    let allDay = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Conference"), "start_date": .string("2026-11-05"),
        "end_date": .string("2026-11-07"), "all_day": .bool(true),
      ])
    #expect(allDay.isError != true)
  }

  @Test("times on an all-day event are refused unless all_day is turned off with them")
  func timesOnAnAllDayEventNeedAllDayOff() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Conference"), "start_date": .string("2026-11-05"),
        "all_day": .bool(true),
      ])
    let id = try #require(created.structuredContent?.objectValue?["event_id"]?.stringValue)

    let refused = try await mcpRegistryCall(
      registry, tool: "update_calendar_event",
      arguments: [
        "event_id": .string(id), "start_time": .string("09:31"), "end_time": .string("11:20"),
      ])
    expectMCPStructuredError(refused, code: "validation", tool: "update_calendar_event")
    #expect(mcpTextContent(refused).contains("all_day"))
    #expect(!mcpTextContent(refused).contains("SQLite"))

    let timed = try await mcpRegistryCall(
      registry, tool: "update_calendar_event",
      arguments: [
        "event_id": .string(id), "all_day": .bool(false), "start_time": .string("09:31"),
        "end_time": .string("11:20"),
      ])
    #expect(timed.isError != true)
    let object = try #require(timed.structuredContent?.objectValue)
    #expect(object["all_day"]?.boolValue == false)
    #expect(object["start_time"]?.stringValue == "09:31")
  }
}
