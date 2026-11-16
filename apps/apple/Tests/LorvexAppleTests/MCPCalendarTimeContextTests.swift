import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP calendar clocks carry their frame and real instants")
struct MCPCalendarTimeContextTests {
  @Test func compactAndNarrowRowsDisambiguateRepeatedClocks() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(key: "timezone", value: "America/New_York")
    let id = try await create(registry, title: "Fold", start: "05:45", end: "06:15")
    for extra: [String: Value] in [
      [:], ["shape": .string("full")], ["fields": .array([.string("start_time")])],
    ] {
      let result = try await timeline(registry, extra: extra)
      #expect(result["timezone"]?.stringValue == "America/New_York")
      let event = try #require(result["events"]?.arrayValue?.first?.objectValue)
      #expect(event["event_id"]?.stringValue == id)
      #expect(event["start_time"]?.stringValue == "01:45")
      #expect(event["timezone"]?.stringValue == "America/New_York")
      let context = try #require(event["time_context"]?.objectValue)
      #expect(context["kind"]?.stringValue == "zoned")
      #expect(context["clock_basis"]?.stringValue == "display")
      #expect(context["source_timezone"]?.stringValue == "UTC")
      #expect(context["start_at"]?.stringValue == "2026-11-01T05:45:00.000Z")
      if extra["fields"] == nil {
        #expect(event["end_time"]?.stringValue == "01:15")
        #expect(context["end_at"]?.stringValue == "2026-11-01T06:15:00.000Z")
      } else {
        #expect(event["end_time"] == nil)
        #expect(context["end_at"] == nil)
      }
    }
    for requested in ["title", "start_date"] {
      let result = try await timeline(
        registry,
        extra: [
          "fields": .array([.string(requested)]), "shape": .string("full"),
          "include": .array([.string("time")]),
        ])
      let event = try #require(result["events"]?.arrayValue?.first?.objectValue)
      #expect(event["start_time"] == nil)
      #expect(event["time_context"]?.objectValue?["start_at"] == nil)
      #expect(event["time_context"]?.objectValue?["source_timing"] == nil)
      if requested == "title" { #expect(event["time_context"] == nil) }
    }
    let endOnly = try await timeline(registry, extra: ["fields": .array([.string("end_time")])])
    let endpoint = try #require(endOnly["events"]?.arrayValue?.first?.objectValue)
    #expect(endpoint["timezone"]?.stringValue == "America/New_York")
    #expect(endpoint["time_context"]?.objectValue?["start_at"] == nil)
    #expect(
      endpoint["time_context"]?.objectValue?["end_at"]?.stringValue == "2026-11-01T06:15:00.000Z")
  }

  @Test func sourceTimingRoundTripsWithoutChangingTheMeeting() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(key: "timezone", value: "America/New_York")
    let id = try await create(registry, title: "No drift", start: "05:45", end: "06:15")
    let before = try await timeline(registry, extra: ["include": .array([.string("time")])])
    let row = try #require(before["events"]?.arrayValue?.first?.objectValue)
    let context = try #require(row["time_context"]?.objectValue)
    var source = try #require(context["source_timing"]?.objectValue)
    #expect(source["timezone"]?.stringValue == "UTC")
    #expect(source["start_time"]?.stringValue == "05:45")
    #expect(source["end_time"]?.stringValue == "06:15")
    source["event_id"] = .string(id)
    let edited = try await mcpRegistryCall(
      registry, tool: "update_calendar_event", arguments: source)
    #expect(edited.isError != true)
    let after = try await timeline(registry)
    let refreshed = try #require(after["events"]?.arrayValue?.first?.objectValue)
    #expect(refreshed["start_time"] == row["start_time"])
    #expect(refreshed["end_time"] == row["end_time"])
    #expect(refreshed["time_context"]?.objectValue?["start_at"] == context["start_at"])
    let searched = try await mcpRegistryCall(
      registry, tool: "search_calendar_events",
      arguments: ["query": .string("No drift")])
    let found = try #require(
      searched.structuredContent?.objectValue?["events"]?.arrayValue?.first?.objectValue)
    #expect(found["start_time"]?.stringValue == "05:45")
    #expect(found["timezone"]?.stringValue == "UTC")
    #expect(found["time_context"]?.objectValue?["clock_basis"]?.stringValue == "source")
    #expect(found["time_context"]?.objectValue?["start_at"] == nil)
  }

  @Test func paginationFollowsRealTimeThroughTheRepeatedHour() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(key: "timezone", value: "America/New_York")
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode, value: "full_details")
    let earlier = try await create(registry, title: "Earlier", start: "05:50", end: "05:55")
    let later = try await create(registry, title: "Later", start: "06:10", end: "06:20")
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(
        from: [
          EventKitFetchedEvent(
            key: "floating", title: "Floating", notes: nil,
            startDate: "2026-11-01", startTime: "01:30", endDate: nil, endTime: "01:40",
            allDay: false, location: nil, timezone: nil)
        ], scope: "device", accessMode: .fullDetails), builtAtMode: .fullDetails,
      windowStart: "2026-11-01", windowEnd: "2026-11-01")
    var ids: [String] = []
    for offset in 0..<3 {
      let page = try await timeline(registry, extra: ["limit": .int(1), "offset": .int(offset)])
      let row = try #require(page["events"]?.arrayValue?.first?.objectValue)
      ids.append(try #require(row["event_id"]?.stringValue))
      #expect(page["timezone"]?.stringValue == "America/New_York")
      if offset == 0 {
        #expect(row["timezone"] == .null)
        #expect(row["time_context"]?.objectValue?["kind"]?.stringValue == "floating")
        #expect(row["time_context"]?.objectValue?["start_at"] == nil)
      }
    }
    #expect(ids == ["eventkit:device:floating", earlier, later])
  }

  @Test func civilDaysAndMissingEndsDoNotGainInstantsOrDurations() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(key: "timezone", value: "Asia/Tokyo")
    let pointID = try await create(registry, title: "Point", start: "06:30", end: nil)
    let createdDay = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Civil day"), "start_date": .string("2026-11-01"),
        "all_day": .bool(true), "timezone": .string("America/New_York"),
      ])
    let result = try await timeline(registry, extra: ["shape": .string("full")])
    let rows = try #require(result["events"]?.arrayValue).compactMap(\.objectValue)
    let point = try #require(rows.first { $0["event_id"]?.stringValue == pointID })
    #expect(point["end_time"] == .null)
    #expect(point["time_context"]?.objectValue?["end_at"] == .null)
    #expect(point["time_context"]?.objectValue?["source_timing"]?.objectValue?["end_time"] == .null)
    let dayID = try #require(createdDay.structuredContent?.objectValue?["event_id"]?.stringValue)
    let day = try #require(rows.first { $0["event_id"]?.stringValue == dayID })
    #expect(day["start_date"]?.stringValue == "2026-11-01")
    #expect(day["timezone"] == .null)
    #expect(day["time_context"]?.objectValue?["kind"]?.stringValue == "all_day")
    #expect(day["time_context"]?.objectValue?["start_at"] == .null)
  }

  @Test(arguments: [CalendarAiAccessMode.fullDetails, .busyOnly])
  func providerLinksRetainTheSamePreciseReadingAsTheTimeline(mode: CalendarAiAccessMode)
    async throws
  {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode, value: mode.rawValue)
    let start = Date(timeIntervalSince1970: 1_793_511_900)  // 2026-11-01 05:45 UTC
    let end = start.addingTimeInterval(1800)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(
        from: [
          EventKitFetchedEvent(
            key: "fold", title: "Linked fold", notes: "Private notes",
            startDate: "2026-11-01", startTime: "01:45", endDate: nil, endTime: "01:15",
            allDay: false, location: "Private place", timezone: "America/New_York",
            occurrenceInstants: [
              ProviderOccurrenceInstant(date: "2026-11-01", start: start, end: end)
            ])
        ], scope: "device", accessMode: mode), builtAtMode: mode,
      windowStart: "2026-11-01", windowEnd: "2026-11-01")
    let created = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Prepare")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    let linked = try await mcpRegistryCall(
      registry, tool: "link_task_to_provider_event",
      arguments: [
        "task_id": .string(taskID), "provider_event_id": .string("eventkit:device:fold"),
        "provider_source": .string("eventkit"),
      ])
    #expect(linked.isError != true)
    let loaded = try await mcpRegistryCall(
      registry, tool: "get_linked_events_for_task", arguments: ["task_id": .string(taskID)])
    let row = try #require(
      loaded.structuredContent?.objectValue?["events"]?.arrayValue?.first?.objectValue)
    #expect(row["event_id"]?.stringValue == "eventkit:device:fold")
    #expect(row["timezone"]?.stringValue == "America/New_York")
    #expect(row["notes"] == nil)
    #expect(row["time_context"]?.objectValue?["source_timing"] == nil)
    #expect(
      row["title"]?.stringValue
        == (mode.includesDetails ? "⟦user⟧Linked fold⟦/user⟧" : "⟦user⟧Busy⟦/user⟧"))
    if !mode.includesDetails { #expect(row["location"] == nil) }
    #expect(
      row["time_context"]?.objectValue?["start_at"]?.stringValue
        == LorvexDateFormatters.iso8601Fractional.string(from: start))
    #expect(
      row["time_context"]?.objectValue?["end_at"]?.stringValue
        == LorvexDateFormatters.iso8601Fractional.string(from: end))
  }

  @Test func changingTimezoneAlsoUpdatesEmptyAndCivilOnlyWindows() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    for zone in ["America/New_York", "Asia/Tokyo"] {
      _ = try await service.setPreference(key: "timezone", value: zone)
      let empty = try await timeline(registry)
      #expect(empty["timezone"]?.stringValue == zone)
      #expect(empty["events"]?.arrayValue?.isEmpty == true)
    }
    let created = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Civil day"), "start_date": .string("2026-11-01"), "all_day": .bool(true),
      ])
    #expect(created.isError != true)
    for zone in ["America/New_York", "Asia/Tokyo"] {
      _ = try await service.setPreference(key: "timezone", value: zone)
      let result = try await timeline(registry, extra: ["shape": .string("full")])
      let row = try #require(result["events"]?.arrayValue?.first?.objectValue)
      #expect(result["timezone"]?.stringValue == zone)
      #expect(row["start_date"]?.stringValue == "2026-11-01")
      #expect(row["timezone"] == .null)
      #expect(row["time_context"]?.objectValue?["kind"]?.stringValue == "all_day")
      #expect(row["time_context"]?.objectValue?["start_at"] == .null)
    }
  }

  @Test func scopedEditsKeepTheSourceSlotWhenTheDisplayDayDiffers() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(key: "timezone", value: "Asia/Tokyo")
    let created = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Evening series"), "start_date": .string("2026-11-01"),
        "start_time": .string("23:00"), "end_time": .string("23:30"), "timezone": .string("UTC"),
        "recurrence": .object(["freq": .string("DAILY"), "count": .int(3)]),
      ])
    #expect(created.isError != true)
    let window: [String: Value] = [
      "from": .string("2026-11-03"), "to": .string("2026-11-03"), "shape": .string("full"),
    ]
    let before = try await timeline(registry, extra: window)
    let row = try #require(before["events"]?.arrayValue?.first?.objectValue)
    #expect(row["occurrence_date"]?.stringValue == "2026-11-02")
    #expect(row["start_date"]?.stringValue == "2026-11-03")
    #expect(row["start_time"]?.stringValue == "08:00")
    var source = try #require(row["time_context"]?.objectValue?["source_timing"]?.objectValue)
    #expect(source["start_date"]?.stringValue == "2026-11-02")
    #expect(source["start_time"]?.stringValue == "23:00")
    source["event_id"] = row["event_id"]
    source["occurrence_date"] = row["occurrence_date"]
    source["scope"] = .string("this_only")
    source["title"] = .string("Changed occurrence")
    let edited = try await mcpRegistryCall(
      registry, tool: "edit_scoped_calendar_event", arguments: source)
    #expect(edited.isError != true)
    let after = try await timeline(registry, extra: window)
    let updated = try #require(after["events"]?.arrayValue?.first?.objectValue)
    #expect(updated["title"]?.stringValue == "⟦user⟧Changed occurrence⟦/user⟧")
    #expect(updated["occurrence_date"] == row["occurrence_date"])
    #expect(
      updated["time_context"]?.objectValue?["start_at"]
        == row["time_context"]?.objectValue?["start_at"])
    let master = try await mcpRegistryCall(
      registry, tool: "search_calendar_events", arguments: ["query": .string("Evening series")])
    let stored = try #require(
      master.structuredContent?.objectValue?["events"]?.arrayValue?.first?.objectValue)
    #expect(stored["start_date"]?.stringValue == "2026-11-01")
    #expect(stored["start_time"]?.stringValue == "23:00")
    #expect(stored["timezone"]?.stringValue == "UTC")
  }

  @Test func aRecurrenceGapKeepsItsIntendedSourceClock() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    _ = try await service.setPreference(key: "timezone", value: "America/New_York")
    let created = try await mcpRegistryCall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Before the jump"), "start_date": .string("2026-03-07"),
        "start_time": .string("02:30"), "end_time": .string("03:30"),
        "timezone": .string("America/New_York"),
        "recurrence": .object(["freq": .string("DAILY"), "count": .int(3)]),
      ])
    #expect(created.isError != true)
    let result = try await timeline(
      registry,
      extra: [
        "from": .string("2026-03-08"), "to": .string("2026-03-08"), "shape": .string("full"),
      ])
    let row = try #require(result["events"]?.arrayValue?.first?.objectValue)
    #expect(row["start_time"]?.stringValue == "03:00")
    let context = try #require(row["time_context"]?.objectValue)
    #expect(context["start_at"]?.stringValue == "2026-03-08T07:00:00.000Z")
    #expect(context["source_timing"]?.objectValue?["start_time"]?.stringValue == "02:30")
    #expect(context["source_timing"]?.objectValue?["start_date"]?.stringValue == "2026-03-08")
  }

  private func create(_ registry: ToolRegistry, title: String, start: String, end: String?)
    async throws -> String
  {
    var arguments: [String: Value] = [
      "title": .string(title), "start_date": .string("2026-11-01"),
      "start_time": .string(start), "timezone": .string("UTC"),
    ]
    arguments["end_time"] = end.map(Value.string)
    let result = try await mcpRegistryCall(
      registry, tool: "create_calendar_event", arguments: arguments)
    #expect(result.isError != true)
    return try #require(result.structuredContent?.objectValue?["event_id"]?.stringValue)
  }

  private func timeline(_ registry: ToolRegistry, extra: [String: Value] = [:]) async throws
    -> [String: Value]
  {
    var args: [String: Value] = ["from": .string("2026-11-01"), "to": .string("2026-11-01")]
    args.merge(extra) { _, new in new }
    let result = try await mcpRegistryCall(registry, tool: "get_calendar_timeline", arguments: args)
    #expect(result.isError != true)
    return try #require(result.structuredContent?.objectValue)
  }
}
