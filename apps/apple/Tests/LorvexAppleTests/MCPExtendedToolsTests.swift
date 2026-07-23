import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

// MARK: - Helpers (file-private to avoid collision with MCPToolRegistryTests)

private func xcall(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func xtext(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let t, _, _) = $0 { return t }
    return nil
  }.joined()
}

// MARK: - Calendar Links

@Suite("MCP Extended — calendar links")
struct CalendarLinksExtendedTests {

  @Test("update_calendar_event patches the title and is visible in search")
  func updateEventRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Swift migration review"),
        "start_date": .string("2026-06-04"),
        "all_day": .bool(true),
      ]
    )
    let createdObject = try #require(created.structuredContent?.objectValue)
    let eventID = try #require(createdObject["event_id"]?.stringValue)
    #expect(createdObject["id"]?.stringValue == eventID)
    let updateResult = try await xcall(
      registry, tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "title": .string("Swift migration review — UPDATED"),
      ]
    )
    #expect(updateResult.isError != true)
    let returnedID = updateResult.structuredContent?.objectValue?["id"]?.stringValue
    #expect(returnedID == eventID)

    let searchResult = try await xcall(
      registry, tool: "search_calendar_events",
      arguments: ["query": .string("UPDATED")]
    )
    #expect(searchResult.isError != true)
    let count = searchResult.structuredContent?.objectValue?["returned"]?.intValue ?? 0
    #expect(count >= 1)
  }

  @Test("recurring timeline rows use event_id for whole-series update and delete")
  func recurringEventAddressRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Recurring address contract"),
        "start_date": .string("2026-06-01"),
        "start_time": .string("09:00"),
        "end_time": .string("09:30"),
        "recurrence": .object([
          "freq": .string("WEEKLY"),
          "count": .int(2),
        ]),
      ])
    let stableEventID = try #require(
      created.structuredContent?.objectValue?["event_id"]?.stringValue)

    let timeline = try await xcall(
      registry, tool: "get_calendar_timeline",
      arguments: ["from": .string("2026-06-01"), "to": .string("2026-06-15")])
    let occurrences = try #require(timeline.structuredContent?.objectValue?["events"]?.arrayValue)
      .compactMap(\.objectValue)
      .filter { $0["event_id"]?.stringValue == stableEventID }
    #expect(occurrences.count == 2)
    #expect(occurrences.allSatisfy { $0["id"]?.stringValue != stableEventID })

    let updated = try await xcall(
      registry, tool: "update_calendar_event",
      arguments: [
        "event_id": .string(stableEventID),
        "title": .string("Updated whole series"),
      ])
    #expect(updated.isError != true)
    #expect(updated.structuredContent?.objectValue?["event_id"]?.stringValue == stableEventID)

    let updatedTimeline = try await xcall(
      registry, tool: "get_calendar_timeline",
      arguments: ["from": .string("2026-06-01"), "to": .string("2026-06-15")])
    let updatedOccurrences = try #require(
      updatedTimeline.structuredContent?.objectValue?["events"]?.arrayValue)
      .compactMap(\.objectValue)
      .filter { $0["event_id"]?.stringValue == stableEventID }
    #expect(updatedOccurrences.count == 2)
    let fencedUpdatedTitle: String = SecurityFencing.fence("Updated whole series")
    #expect(updatedOccurrences.compactMap { $0["title"]?.stringValue } == [
      fencedUpdatedTitle, fencedUpdatedTitle,
    ])

    let deleted = try await xcall(
      registry, tool: "delete_calendar_event",
      arguments: ["event_id": .string(stableEventID)])
    #expect(deleted.structuredContent?.objectValue?["deleted"]?.boolValue == true)

    let emptyTimeline = try await xcall(
      registry, tool: "get_calendar_timeline",
      arguments: ["from": .string("2026-06-01"), "to": .string("2026-06-15")])
    let remaining = try #require(
      emptyTimeline.structuredContent?.objectValue?["events"]?.arrayValue)
    #expect(!remaining.contains { $0.objectValue?["event_id"]?.stringValue == stableEventID })
  }

  @Test("update_calendar_event with missing event_id returns structured error")
  func updateEventMissingID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(registry, tool: "update_calendar_event", arguments: [:])
    #expect(result.isError == true)
  }

  @Test("update_calendar_event with unknown event_id returns structured error")
  func updateEventUnknownID() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "update_calendar_event",
      arguments: ["event_id": .string("no-such-event")]
    )
    #expect(result.isError == true)
  }

  @Test("delete_calendar_event removes the event and marks deleted true")
  func deleteCalendarEvent() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Removable review"),
        "start_date": .string("2026-06-04"),
        "all_day": .bool(true),
      ]
    )
    let createdObject = try #require(created.structuredContent?.objectValue)
    let eventID = try #require(createdObject["event_id"]?.stringValue)
    #expect(createdObject["id"]?.stringValue == eventID)
    let result = try await xcall(
      registry, tool: "delete_calendar_event",
      arguments: ["event_id": .string(eventID)]
    )
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["deleted"]?.boolValue == true)
    #expect(object["id"]?.stringValue == eventID)
    // Uniform delete-return shape: previous carries the removed event.
    #expect(object["previous"]?.objectValue?["id"]?.stringValue == eventID)

    // The timeline no longer contains the deleted event.
    let timeline = try await xcall(
      registry, tool: "get_calendar_timeline",
      arguments: ["from": .string("2026-06-01"), "to": .string("2026-06-10")]
    )
    let events = timeline.structuredContent?.objectValue?["events"]?.arrayValue ?? []
    #expect(!events.contains { $0.objectValue?["id"]?.stringValue == eventID })
  }

  @Test("search_calendar_events returns matching events for existing title fragment")
  func searchCalendarEvents() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await xcall(
      registry, tool: "create_calendar_event",
      arguments: [
        "title": .string("Swift migration review"),
        "start_date": .string("2026-06-04"),
        "all_day": .bool(true),
      ]
    )
    let result = try await xcall(
      registry, tool: "search_calendar_events",
      arguments: ["query": .string("Swift")]
    )
    #expect(result.isError != true)
    let count = result.structuredContent?.objectValue?["returned"]?.intValue ?? 0
    #expect(count >= 1)
  }

  @Test("search_calendar_events compact rows omit heavy fields by default")
  func searchCalendarEventsCompactRows() async throws {
    let registry = try mcpInMemoryRegistry()
    let title = "CalendarCompact-\(Int.random(in: 10000...99999))"
    _ = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string(title),
        "start_date": .string("2026-06-06"),
        "all_day": .bool(true),
        "notes": .string("Agenda details"),
        "attendees": .array([.object(["email": .string("compact@example.com")])]),
      ])

    let compact = try await xcall(
      registry,
      tool: "search_calendar_events",
      arguments: ["query": .string(title), "limit": .int(1)])
    let compactEvent = compact.structuredContent?.objectValue?["events"]?.arrayValue?.first?
      .objectValue
    #expect(compactEvent?["id"] != nil)
    #expect(compactEvent?["title"] != nil)
    #expect(compactEvent?["notes"] == nil)
    #expect(compactEvent?["attendees"] == nil)

    let full = try await xcall(
      registry,
      tool: "search_calendar_events",
      arguments: ["query": .string(title), "limit": .int(1), "shape": .string("full")])
    let fullEvent = full.structuredContent?.objectValue?["events"]?.arrayValue?.first?.objectValue
    #expect(fullEvent?["notes"] != nil)
    #expect(fullEvent?["attendees"] != nil)
  }

  @Test("search_calendar_events with non-matching query returns empty results")
  func searchCalendarEventsEmpty() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry, tool: "search_calendar_events",
      arguments: ["query": .string("zzz-no-match-xyz")]
    )
    #expect(result.isError != true)
    let count = result.structuredContent?.objectValue?["returned"]?.intValue ?? 0
    #expect(count == 0)
  }

  @Test("search_calendar_events rides the pagination envelope and pages by offset")
  func searchCalendarEventsPaginationEnvelope() async throws {
    let registry = try mcpInMemoryRegistry()
    let token = "PageToken-\(Int.random(in: 10000...99999))"
    for day in ["2026-07-01", "2026-07-02"] {
      _ = try await xcall(
        registry, tool: "create_calendar_event",
        arguments: [
          "title": .string("\(token) meeting"), "start_date": .string(day),
          "all_day": .bool(true),
        ])
    }

    let firstPage = try await xcall(
      registry, tool: "search_calendar_events",
      arguments: ["query": .string(token), "limit": .int(1)])
    let firstObject = try #require(firstPage.structuredContent?.objectValue)
    for key in [
      "total_matching", "returned", "limit", "offset", "next_offset", "next_cursor", "truncated",
    ] {
      #expect(firstObject[key] != nil, "missing envelope key: \(key)")
    }
    #expect(firstObject["count"] == nil)
    #expect(firstObject["events"]?.arrayValue?.count == 1)
    #expect(firstObject["returned"]?.intValue == 1)
    #expect(firstObject["truncated"]?.boolValue == true)
    #expect(firstObject["next_offset"]?.intValue == 1)
    // A merged canonical+provider search has no cheap total.
    #expect(firstObject["total_matching"] == .null)

    let secondPage = try await xcall(
      registry, tool: "search_calendar_events",
      arguments: ["query": .string(token), "limit": .int(1), "offset": .int(1)])
    let secondObject = try #require(secondPage.structuredContent?.objectValue)
    #expect(secondObject["events"]?.arrayValue?.count == 1)
    #expect(secondObject["truncated"]?.boolValue == false)
    #expect(secondObject["next_offset"] == .null)
  }

  @Test("create_calendar_event appears in the timeline and can be deleted")
  func createTimelineDeleteEvent() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Native calendar planning"),
        "start_date": .string("2026-06-05"),
        "start_time": .string("09:30"),
        "end_time": .string("10:00"),
      ]
    )
    #expect(created.isError != true)
    let eventID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let timeline = try await xcall(
      registry,
      tool: "get_calendar_timeline",
      arguments: ["from": .string("2026-06-01"), "to": .string("2026-06-10")]
    )
    #expect(timeline.isError != true)
    let events = timeline.structuredContent?.objectValue?["events"]?.arrayValue ?? []
    #expect(events.contains { $0.objectValue?["id"]?.stringValue == eventID })

    let deleted = try await xcall(
      registry,
      tool: "delete_calendar_event",
      arguments: ["event_id": .string(eventID)]
    )
    #expect(deleted.isError != true)
    #expect(deleted.structuredContent?.objectValue?["deleted"]?.boolValue == true)
  }

  @Test("create_calendar_event and update_calendar_event preserve extended calendar fields")
  func extendedCalendarFieldsRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Conference travel"),
        "start_date": .string("2026-06-09"),
        "start_time": .string("08:00"),
        "end_time": .string("09:00"),
        "recurrence": .object(["freq": .string("WEEKLY"), "count": .int(2)]),
        "timezone": .string("America/Los_Angeles"),
        "url": .string("https://example.com/itinerary"),
        "color": .string("#34C759"),
        "event_type": .string("event"),
        "notes": .string("Booked through corporate travel"),
        "person_name": .string("Alex"),
        "attendees": .array([
          .object([
            "email": .string("alice@example.com"),
            "name": .string("Alice"),
          ])
        ]),
      ]
    )
    #expect(created.isError != true)
    let createdObject = try #require(created.structuredContent?.objectValue)
    let eventID = try #require(createdObject["event_id"]?.stringValue)
    #expect(createdObject["id"]?.stringValue == eventID)
    // recurrence is a typed object of system-controlled fields — never fenced —
    // and round-trips as the same lowercase-keyed shape tasks emit.
    let createdRecurrence = try #require(createdObject["recurrence"]?.objectValue)
    #expect(createdRecurrence["freq"]?.stringValue == "weekly")
    #expect(createdRecurrence["count"]?.intValue == 2)
    #expect(createdObject["is_recurring"]?.boolValue == true)
    #expect(createdObject["recurrence_rule"] == nil)
    // url is user-supplied free text, so it's fenced.
    let fencedCreatedURL: String = SecurityFencing.fence("https://example.com/itinerary")
    #expect(createdObject["url"]?.stringValue == fencedCreatedURL)
    #expect(createdObject["color"]?.stringValue == "#34C759")
    // The notes field is exposed to clients as `notes` (it maps to the
    // `description` column) — it must survive the create round-trip.
    let fencedCreatedNotes: String = SecurityFencing.fence("Booked through corporate travel")
    let fencedCreatedPerson: String = SecurityFencing.fence("Alex")
    let fencedAliceEmail: String = SecurityFencing.fence("alice@example.com")
    let fencedAliceName: String = SecurityFencing.fence("Alice")
    #expect(createdObject["notes"]?.stringValue == fencedCreatedNotes)
    #expect(createdObject["person_name"]?.stringValue == fencedCreatedPerson)
    let createdAttendees = try #require(createdObject["attendees"]?.arrayValue)
    #expect(createdAttendees.first?.objectValue?["email"]?.stringValue == fencedAliceEmail)
    #expect(createdAttendees.first?.objectValue?["name"]?.stringValue == fencedAliceName)

    let updated = try await xcall(
      registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "notes": .string("Rebooked on an earlier flight"),
        "url": .string("https://example.com/updated"),
        "color": .string("#FF9500"),
        "person_name": .string("Yu"),
        "attendees": .array([
          .object([
            "email": .string("bob@example.com"),
          ])
        ]),
      ]
    )
    #expect(updated.isError != true)
    let updatedObject = try #require(updated.structuredContent?.objectValue)
    // The update leaves recurrence untouched, so the typed object is preserved.
    let updatedRecurrence = try #require(updatedObject["recurrence"]?.objectValue)
    #expect(updatedRecurrence["freq"]?.stringValue == "weekly")
    #expect(updatedRecurrence["count"]?.intValue == 2)
    let fencedUpdatedURL: String = SecurityFencing.fence("https://example.com/updated")
    #expect(updatedObject["url"]?.stringValue == fencedUpdatedURL)
    #expect(updatedObject["color"]?.stringValue == "#FF9500")
    let fencedUpdatedNotes: String = SecurityFencing.fence("Rebooked on an earlier flight")
    let fencedUpdatedPerson: String = SecurityFencing.fence("Yu")
    let fencedBobEmail: String = SecurityFencing.fence("bob@example.com")
    #expect(updatedObject["notes"]?.stringValue == fencedUpdatedNotes)
    #expect(updatedObject["person_name"]?.stringValue == fencedUpdatedPerson)
    let updatedAttendees = try #require(updatedObject["attendees"]?.arrayValue)
    #expect(updatedAttendees.count == 1)
    #expect(updatedAttendees.first?.objectValue?["email"]?.stringValue == fencedBobEmail)

    let cleared = try await xcall(
      registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "attendees": .null,
      ]
    )
    #expect(cleared.isError != true)
    #expect(cleared.structuredContent?.objectValue?["attendees"] == .null)
  }

  @Test("create_calendar_event rejects a fully empty attendee")
  func rejectsFullyEmptyCalendarAttendee() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Empty attendee"),
        "start_date": .string("2026-06-09"),
        "all_day": .bool(true),
        "attendees": .array([
          .object([
            "email": .string("   "),
            "name": .string("   "),
          ])
        ]),
      ]
    )

    #expect(result.isError == true)
    #expect(xtext(result).contains("email or a name") == true)
  }

  @Test("create_calendar_event round-trips a typed recurrence object (bymonthday)")
  func createRecurrenceBymonthdayRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Rent + mid-month review"),
        "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
        "recurrence": .object([
          "freq": .string("MONTHLY"),
          "bymonthday": .array([.int(1), .int(15)]),
        ]),
      ])
    #expect(created.isError != true)
    let object = try #require(created.structuredContent?.objectValue)
    // Calendar recurrence emits the same lowercase-keyed object shape as tasks.
    let recurrence = try #require(object["recurrence"]?.objectValue)
    #expect(recurrence["freq"]?.stringValue == "monthly")
    #expect(recurrence["bymonthday"]?.arrayValue?.compactMap(\.intValue) == [1, 15])
    #expect(object["is_recurring"]?.boolValue == true)
    // The opaque recurrence_rule string is gone.
    #expect(object["recurrence_rule"] == nil)
  }

  @Test("create_calendar_event round-trips a recurrence UNTIL + INTERVAL")
  func createRecurrenceUntilRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Standup"),
        "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
        "recurrence": .object([
          "freq": .string("DAILY"),
          "interval": .int(2),
          "until": .string("2026-12-31"),
        ]),
      ])
    #expect(created.isError != true)
    let recurrence = try #require(
      created.structuredContent?.objectValue?["recurrence"]?.objectValue)
    #expect(recurrence["freq"]?.stringValue == "daily")
    #expect(recurrence["interval"]?.intValue == 2)
    #expect(recurrence["until"]?.stringValue == "2026-12-31")
  }

  @Test("create_calendar_event rejects a recurrence object missing freq")
  func createRecurrenceMissingFreqRejected() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Bad recurrence"),
        "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
        "recurrence": .object(["interval": .int(1)]),
      ])
    #expect(result.isError == true)
  }

  @Test("create_calendar_event rejects empty and wrong-typed recurrence objects")
  func createMalformedRecurrenceRejected() async throws {
    let registry = try mcpInMemoryRegistry()
    let empty = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Empty recurrence"),
        "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
        "recurrence": .object([:]),
      ])
    #expect(empty.isError == true)
    #expect(xtext(empty).contains("non-empty recurrence rule object"))

    let wrongType = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Wrong recurrence"),
        "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
        "recurrence": .object([
          "freq": .string("DAILY"),
          "count": .string("5"),
        ]),
      ])
    #expect(wrongType.isError == true)
    #expect(xtext(wrongType).contains("count must be an integer"))
  }

  @Test("update_calendar_event distinguishes omitted, object, and null recurrence")
  func updateRecurrencePatchRoundTrip() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await xcall(
      registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Recurring patch contract"),
        "start_date": .string("2026-06-01"),
        "all_day": .bool(true),
        "recurrence": .object([
          "freq": .string("WEEKLY"),
          "byday": .array([.string("MO")]),
        ]),
      ])
    let createdObject = try #require(created.structuredContent?.objectValue)
    let eventID = try #require(createdObject["event_id"]?.stringValue)
    #expect(createdObject["id"]?.stringValue == eventID)

    let omitted = try await xcall(
      registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "title": .string("Still recurring"),
      ])
    #expect(omitted.isError != true)
    #expect(
      omitted.structuredContent?.objectValue?["recurrence"]?.objectValue?["freq"]?.stringValue
        == "weekly")

    let replaced = try await xcall(
      registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "recurrence": .object([
          "freq": .string("DAILY"),
          "interval": .int(2),
        ]),
      ])
    #expect(replaced.isError != true)
    let replacementRule = try #require(
      replaced.structuredContent?.objectValue?["recurrence"]?.objectValue)
    #expect(replacementRule["freq"]?.stringValue == "daily")
    #expect(replacementRule["interval"]?.intValue == 2)

    let cleared = try await xcall(
      registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "recurrence": .null,
      ])
    #expect(cleared.isError != true)
    #expect(cleared.structuredContent?.objectValue?["recurrence"] == .null)
    #expect(cleared.structuredContent?.objectValue?["is_recurring"]?.boolValue == false)

    let emptyObject = try await xcall(
      registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "recurrence": .object([:]),
      ])
    #expect(emptyObject.isError == true)
    #expect(xtext(emptyObject).contains("non-empty recurrence rule object"))
  }
}
