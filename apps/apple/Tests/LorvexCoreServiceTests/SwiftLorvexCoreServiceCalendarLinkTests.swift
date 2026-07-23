import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceCalendarLinkTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  func testReplacementLinkNormalizesToSeriesMasterInBothReadDirections() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Prepare agenda", notes: "")
    let master = try await service.createCalendarEvent(
      title: "Daily review", startDate: "2026-08-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let edit = try await service.editScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2026-08-02", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Moved review", startDate: "2026-08-04"))
    let replacement = try XCTUnwrap(edit.replacementEvent)

    let normalized = try await service.resolveTaskCalendarEventLinkTarget(
      calendarEventID: replacement.id)
    XCTAssertEqual(normalized, master.eventID)
    let imported = try await service.importTaskCalendarEventLink(
      ExportTaskCalendarEventLink(
        taskID: task.id, calendarEventID: replacement.id))
    XCTAssertTrue(imported)

    let links = try await service.loadTaskCalendarEventLinksForDataExport()
    XCTAssertEqual(links.map(\.calendarEventID), [master.eventID])
    let events = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertEqual(events.map(\.eventID), [master.eventID])
    let linkedTasks = try await service.getLinkedTasksForEvent(eventID: replacement.id)
    XCTAssertEqual(linkedTasks.map(\.id), [task.id])

    let unlinked = try await service.unlinkTaskCalendarEventLink(
      taskID: task.id, calendarEventID: replacement.id)
    XCTAssertTrue(unlinked)
    let remainingEvents = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertTrue(remainingEvents.isEmpty)
  }

  func testCancelledDecisionCannotBecomeCanonicalLinkEndpoint() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Cancelled prep", notes: "")
    let master = try await service.createCalendarEvent(
      title: "Daily standup", startDate: "2026-08-01", endDate: nil,
      startTime: "09:00", endTime: "09:15", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    _ = try await service.deleteScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2026-08-02", scope: "this_only")
    let generation = try XCTUnwrap(master.recurrenceGeneration)
    let cancelledID = CalendarOccurrenceDecisionID.make(
      seriesId: master.eventID,
      recurrenceGeneration: generation,
      recurrenceInstanceDate: "2026-08-02")

    do {
      _ = try await service.importTaskCalendarEventLink(
        ExportTaskCalendarEventLink(taskID: task.id, calendarEventID: cancelledID))
      XCTFail("Expected a cancelled occurrence endpoint to be rejected")
    } catch {
      XCTAssertTrue(String(describing: error).contains("not an active replacement"))
    }
    let exportedLinks = try await service.loadTaskCalendarEventLinksForDataExport()
    XCTAssertTrue(exportedLinks.isEmpty)
  }

  func testHiddenSeriesSegmentCannotBecomeCanonicalLinkEndpoint() async throws {
    let service = try makeService()
    let master = try await service.createCalendarEvent(
      title: "Daily planning", startDate: "2026-08-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let split = try await service.editScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2026-08-03",
      scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Later planning"))
    let segmentID = try XCTUnwrap(split.replacementEvent?.eventID)

    // Model an interrupted/partially repaired store where the permanent
    // boundary is already deleted but its private event row has not yet been
    // swept. Read/link boundaries must fail closed instead of exposing it.
    try service.write { db in
      try db.execute(
        sql: "UPDATE calendar_series_cutovers SET state = 'deleted' WHERE id = ?",
        arguments: [segmentID])
    }

    do {
      _ = try await service.resolveTaskCalendarEventLinkTarget(
        calendarEventID: segmentID)
      XCTFail("Expected an inactive segment endpoint to be rejected")
    } catch {
      XCTAssertTrue(String(describing: error).contains("not active"))
    }
  }

  func testCanonicalLinksRemainVisibleWhenProviderAccessIsOff() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    let provider = EventKitFetchedEvent(
      key: "provider-event", title: "Private meeting", notes: "private",
      startDate: "2026-08-03", startTime: "10:00", endDate: "2026-08-03",
      endTime: "10:30", allDay: false, location: "Room 1", timezone: "UTC")
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: [provider], scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-08-01", windowEnd: "2026-08-05")
    let task = try await service.createTask(title: "Two calendars", notes: "")
    let canonical = try await service.createCalendarEvent(
      title: "Native meeting", startDate: "2026-08-02", endDate: nil,
      startTime: "11:00", endTime: "11:30", allDay: false, location: nil, notes: nil)
    _ = try await service.importTaskCalendarEventLink(
      ExportTaskCalendarEventLink(taskID: task.id, calendarEventID: canonical.eventID))
    _ = try await service.linkTaskToProviderEvent(
      taskID: task.id, providerEventID: "eventkit:device:provider-event",
      providerSource: "eventkit")

    let allEvents = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertEqual(allEvents.count, 2)
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .off)
    }
    let offEvents = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertEqual(offEvents.map(\.eventID), [canonical.eventID])
    let canonicalTasks = try await service.getLinkedTasksForEvent(eventID: canonical.eventID)
    XCTAssertEqual(canonicalTasks.map(\.id), [task.id])
    let providerTasks = try await service.getLinkedTasksForEvent(
      eventID: "eventkit:device:provider-event")
    XCTAssertTrue(providerTasks.isEmpty)
  }

  func testRecurringProviderOccurrencesKeepOneLinkAddress() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    let provider = EventKitFetchedEvent(
      key: "recurring:provider:opaque", title: "External daily", notes: nil,
      startDate: "2026-09-01", startTime: "09:00", endDate: "2026-09-01",
      endTime: "09:30", allDay: false, location: nil, timezone: "UTC",
      recurrence: #"{"FREQ":"DAILY"}"#)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: [provider], scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-09-01", windowEnd: "2026-09-03")

    let occurrences = try await service.loadCalendarTimeline(
      from: "2026-09-01", to: "2026-09-02").events
      .filter { $0.source == "provider" }
    XCTAssertEqual(occurrences.count, 2)
    XCTAssertEqual(Set(occurrences.map(\.id)).count, 2)
    XCTAssertEqual(
      Set(occurrences.map(\.eventID)), ["eventkit:device:recurring:provider:opaque"])

    let task = try await service.createTask(title: "Prepare external daily", notes: "")
    let linked = try await service.linkTaskToProviderEvent(
      taskID: task.id, providerEventID: try XCTUnwrap(occurrences.last?.eventID),
      providerSource: "eventkit")
    XCTAssertEqual(linked.providerEventID, "recurring:provider:opaque")
    let linkedEvents = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertEqual(linkedEvents.map(\.eventID), ["eventkit:device:recurring:provider:opaque"])
    let firstEventID = try XCTUnwrap(occurrences.first?.eventID)
    let linkedTasks = try await service.getLinkedTasksForEvent(eventID: firstEventID)
    XCTAssertEqual(linkedTasks.map(\.id), [task.id])

    let removed = try await service.unlinkTaskFromProviderEvent(
      taskID: task.id, providerEventID: firstEventID)
    XCTAssertTrue(removed)
    let remainingEvents = try await service.getLinkedEventsForTask(taskID: task.id)
    let remainingTasks = try await service.getLinkedTasksForEvent(eventID: firstEventID)
    XCTAssertTrue(remainingEvents.isEmpty)
    XCTAssertTrue(remainingTasks.isEmpty)
  }
}
