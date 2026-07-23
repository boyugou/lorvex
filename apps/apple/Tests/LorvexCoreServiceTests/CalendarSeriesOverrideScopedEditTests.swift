import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// Recurring calendar-event single-occurrence decision model.
///
/// A `this_only` scoped edit must materialize the edited occurrence as an
/// deterministic replacement decision linked to its series master via
/// `series_id`, `recurrence_generation`, and `recurrence_instance_date` (not a
/// fresh, unlinked standalone event). With that linkage, all-series operations
/// invalidate or sweep the decision without orphaning a visible occurrence.
final class CalendarSeriesOverrideScopedEditTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func makeRecurringEvent(_ service: SwiftLorvexCoreService) async throws
    -> CalendarTimelineEvent
  {
    try await service.createCalendarEvent(
      title: "Daily standup", startDate: "2026-06-22", endDate: nil,
      startTime: "09:00", endTime: "09:15", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","INTERVAL":1}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
  }

  /// A `this_only` edit links the replacement occurrence to its series master
  /// (`series_id` = master id, `recurrence_instance_date` = the occurrence),
  /// rather than minting a fresh unlinked standalone event.
  func testThisOnlyEditMaterializesLinkedOverride() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Standup (moved)"))
    let replacement = try XCTUnwrap(result.replacementEvent)

    let (seriesId, instanceDate, recurrence, replacementId): (String?, String?, String?, String) =
      try service.read { db in
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT series_id, recurrence_instance_date, recurrence
            FROM calendar_events WHERE id = ?
            """,
          arguments: [replacement.id])!
        return (row[0], row[1], row[2], replacement.id)
      }
    XCTAssertNotEqual(replacementId, event.id, "the override is a distinct row")
    XCTAssertEqual(seriesId, event.id, "override must link to its series master")
    XCTAssertEqual(instanceDate, "2026-06-23", "override pins the occurrence date it replaces")
    XCTAssertNil(recurrence, "an override carries no recurrence of its own")
  }

  /// Corruption scenario (a): edit one occurrence, then Delete All. The
  /// previously-edited occurrence must be swept with the series — no orphan ghost.
  func testThisOnlyEditThenDeleteAllLeavesNoOrphan() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)

    _ = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Standup (moved)"))

    // Sanity: exactly one override now exists, linked to the series.
    let overrideCount: Int = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id = ? AND recurrence IS NULL",
        arguments: [event.id]) ?? -1
    }
    XCTAssertEqual(overrideCount, 1)

    _ = try await service.deleteScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-22", scope: "all_in_series")

    let remaining: Int = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?1 OR series_id = ?1",
        arguments: [event.id]) ?? -1
    }
    XCTAssertEqual(remaining, 0, "Delete All must sweep the series master AND its overrides")
  }

  /// Corruption scenario (b): edit one occurrence, then Edit All. Edit All must
  /// reach the edited occurrence and sweep its decision register so the natural
  /// occurrence reappears under the series-wide edit.
  func testThisOnlyEditThenEditAllReachesTheOverride() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)

    _ = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Standup (moved)"))

    _ = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "all_in_series",
      updates: ScopedCalendarEventUpdates(title: "Standup (all edited)"))

    let (decisions, masterTitle): (Int, String) = try service.read { db in
      let overrides =
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id = ? AND recurrence IS NULL",
          arguments: [event.id]) ?? -1
      let title =
        try String.fetchOne(
          db, sql: "SELECT title FROM calendar_events WHERE id = ?", arguments: [event.id]) ?? ""
      return (overrides, title)
    }
    XCTAssertEqual(decisions, 0, "Edit All must sweep the per-occurrence decision")
    XCTAssertEqual(masterTitle, "Standup (all edited)", "the master series carries the edit")
  }

  func testThisOnlyReeditReusesExistingOverrideFromMasterOrOverrideID() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)
    let first = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "First edit"))
    let override = try XCTUnwrap(first.replacementEvent)

    let throughMaster = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Second edit"))
    XCTAssertEqual(throughMaster.replacementEvent?.id, override.id)
    XCTAssertEqual(throughMaster.replacementEvent?.title, "Second edit")

    let throughOverride = try await service.editScopedCalendarEvent(
      eventID: override.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Third edit"))
    XCTAssertEqual(throughOverride.replacementEvent?.id, override.id)
    XCTAssertEqual(throughOverride.replacementEvent?.title, "Third edit")

    let state = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) AS decision_count,
                 SUM(CASE WHEN occurrence_state = 'replacement' THEN 1 ELSE 0 END)
                   AS replacement_count
          FROM calendar_events WHERE series_id = ?
          """,
        arguments: [event.id])!
    }
    let decisionCount: Int = state["decision_count"]
    let replacementCount: Int = state["replacement_count"]
    XCTAssertEqual(decisionCount, 1)
    XCTAssertEqual(replacementCount, 1)
  }

  func testScopedEditsHonorReplacementStartDateWhileKeepingOccurrenceIdentity() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)

    let one = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(
        title: "Moved occurrence", startDate: "2026-06-25"))
    let override = try XCTUnwrap(one.replacementEvent)
    XCTAssertEqual(override.startDate, "2026-06-25")
    let identity: String? = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence_instance_date FROM calendar_events WHERE id = ?",
        arguments: [override.id])
    }
    XCTAssertEqual(identity, "2026-06-23")

    let tail = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "Moved tail", startDate: "2026-06-26"))
    XCTAssertEqual(tail.replacementEvent?.startDate, "2026-06-26")
  }

  func testThisOnlyStartTimeMovePreservesCrossMidnightDuration() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Overnight maintenance", startDate: "2026-06-22", endDate: "2026-06-23",
      startTime: "23:00", endTime: "01:00", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_only",
      updates: ScopedCalendarEventUpdates(startTime: "22:00"))
    let replacement = try XCTUnwrap(result.replacementEvent)
    XCTAssertEqual(replacement.startDate, "2026-06-24")
    XCTAssertEqual(replacement.startTime, "22:00")
    XCTAssertEqual(replacement.endDate, "2026-06-25")
    XCTAssertEqual(replacement.endTime, "00:00")
  }

  func testThisOnlyEditCanClearOptionalFields() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Detailed series", startDate: "2026-06-22", endDate: nil,
      startTime: "09:00", endTime: "09:15", allDay: false,
      location: "Room 4", notes: "Bring notes",
      recurrence: TaskRecurrenceRule(freq: .daily), timezone: nil,
      url: nil, color: "#336699", eventType: nil, personName: nil, attendees: nil)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(location: "", notes: "", color: ""))
    let replacement = try XCTUnwrap(result.replacementEvent)
    XCTAssertEqual(replacement.location, "")
    XCTAssertEqual(replacement.notes, "")
    XCTAssertNil(replacement.color)
  }

  func testThisAndFollowingFromOverrideTruncatesMasterAndCleansTail() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Daily with attendees", startDate: "2026-06-22", endDate: nil,
      startTime: "09:00", endTime: "09:15", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily, count: 5),
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil,
      personName: nil,
      attendees: [CalendarEventAttendee(email: "alex@example.com", name: "Alex")])
    let seededSplit = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Tail seed"))
    let splitOverride = try XCTUnwrap(seededSplit.replacementEvent)
    _ = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Later override"))

    let split = try await service.editScopedCalendarEvent(
      eventID: splitOverride.id, occurrenceDate: "2026-06-23",
      scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Replacement tail"))

    let original = try XCTUnwrap(split.originalEvent)
    let replacement = try XCTUnwrap(split.replacementEvent)
    XCTAssertEqual(original.id, event.id)
    XCTAssertTrue(original.isRecurring)
    XCTAssertNotEqual(replacement.id, splitOverride.id)
    XCTAssertTrue(replacement.isRecurring)
    XCTAssertEqual(replacement.title, "Replacement tail")
    XCTAssertEqual(replacement.attendees?.first?.email, "alex@example.com")
    let replacementRule = try XCTUnwrap(
      TaskRecurrenceRule.bridgeRule(from: try XCTUnwrap(replacement.recurrenceRule)))
    XCTAssertEqual(replacementRule.count, 4)

    let remainingDecisions = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id = ?",
        arguments: [event.id]) ?? -1
    }
    XCTAssertEqual(remainingDecisions, 0)
  }

  func testDeleteScopesAcceptOverrideIDWithoutLeavingFutureMaster() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)
    let seededFirst = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Edited occurrence"))
    let firstOverride = try XCTUnwrap(seededFirst.replacementEvent)

    let thisOnly = try await service.deleteScopedCalendarEvent(
      eventID: firstOverride.id, occurrenceDate: "2026-06-23", scope: "this_only")
    XCTAssertEqual(thisOnly.event?.id, event.id)
    let deletedFirst = try await service.getCalendarEvent(id: firstOverride.id)
    XCTAssertNil(deletedFirst)

    let seededLater = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Future occurrence"))
    let laterOverride = try XCTUnwrap(seededLater.replacementEvent)
    let truncated = try await service.deleteScopedCalendarEvent(
      eventID: laterOverride.id, occurrenceDate: "2026-06-24",
      scope: "this_and_following")

    XCTAssertEqual(truncated.event?.id, event.id)
    XCTAssertNotNil(truncated.event?.recurrenceRule)
    let deletedLater = try await service.getCalendarEvent(id: laterOverride.id)
    XCTAssertNil(deletedLater)
  }

  func testEditAllReportsEveryInvalidatedReplacementID() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)
    let first = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "First replacement"))
    let second = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Second replacement"))
    let firstID = try XCTUnwrap(first.replacementEvent?.id)
    let secondID = try XCTUnwrap(second.replacementEvent?.id)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-22", scope: "all_in_series",
      updates: ScopedCalendarEventUpdates(title: "Reset whole series"))

    XCTAssertEqual(Set(result.invalidatedReplacementEventIDs), Set([firstID, secondID]))
  }

  func testDeleteThisAndFollowingReportsOnlyInvalidatedTailReplacementIDs() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)
    let before = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Surviving prefix"))
    let atSplit = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Split replacement"))
    let after = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-25", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Tail replacement"))
    let beforeID = try XCTUnwrap(before.replacementEvent?.id)
    let atSplitID = try XCTUnwrap(atSplit.replacementEvent?.id)
    let afterID = try XCTUnwrap(after.replacementEvent?.id)

    let result = try await service.deleteScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-24", scope: "this_and_following")

    XCTAssertEqual(Set(result.invalidatedReplacementEventIDs), Set([atSplitID, afterID]))
    XCTAssertFalse(result.invalidatedReplacementEventIDs.contains(beforeID))
  }

  func testCancelThenRestoreReusesTheSameDecisionRegister() async throws {
    let service = try makeService()
    let event = try await makeRecurringEvent(service)
    let occurrenceDate = "2026-06-23"

    _ = try await service.deleteScopedCalendarEvent(
      eventID: event.id, occurrenceDate: occurrenceDate, scope: "this_only")
    let cancelled = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT id, occurrence_state FROM calendar_events
          WHERE series_id = ? AND recurrence_instance_date = ?
          """,
        arguments: [event.id, occurrenceDate])!
    }
    let cancelledID: String = cancelled["id"]
    let cancelledState: String = cancelled["occurrence_state"]
    XCTAssertEqual(cancelledState, "cancelled")

    _ = try await service.removeCalendarEventException(
      eventID: event.id, date: occurrenceDate)
    let restored = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT id, occurrence_state FROM calendar_events
          WHERE series_id = ? AND recurrence_instance_date = ?
          """,
        arguments: [event.id, occurrenceDate])!
    }
    let restoredID: String = restored["id"]
    let restoredState: String = restored["occurrence_state"]
    XCTAssertEqual(restoredID, cancelledID)
    XCTAssertEqual(restoredState, "inherit")
    let timeline = try await service.loadCalendarTimeline(
      from: occurrenceDate, to: occurrenceDate)
    XCTAssertTrue(timeline.events.contains { $0.eventID == event.id })
  }
}
