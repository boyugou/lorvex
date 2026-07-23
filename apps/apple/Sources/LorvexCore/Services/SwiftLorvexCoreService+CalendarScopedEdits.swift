import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Scoped (This / This-and-Following / All) edits + deletes for recurring
/// calendar events, built on one deterministic occurrence-decision register per
/// `(series, generation, occurrence date)`. This file
/// owns the public scope dispatchers and the shared low-level helpers; the
/// per-scope implementations live in
/// `SwiftLorvexCoreService+CalendarSeriesEdits.swift`.
extension SwiftLorvexCoreService {
  public func editScopedCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String,
    scope: String,
    updates: ScopedCalendarEventUpdates
  ) async throws -> ScopedCalendarEventEditResult {
    guard let parsedScope = CalendarEventEditScope(rawValue: scope.lowercased()) else {
      throw LorvexCoreError.validation(
        field: "scope",
        message: "Unknown scope '\(scope)'. Use all_in_series, this_only, or this_and_following.")
    }
    switch parsedScope {
    case .allEvents:
      return try editAllInSeriesCalendarEvent(eventID: eventID, updates: updates)
    case .thisEvent:
      return try editThisOnlyCalendarEvent(
        eventID: eventID, occurrenceDate: occurrenceDate, updates: updates)
    case .thisAndFollowing:
      return try editThisAndFollowingCalendarEvent(
        eventID: eventID, occurrenceDate: occurrenceDate, updates: updates)
    }
  }

  public func deleteScopedCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String,
    scope: String
  ) async throws -> ScopedCalendarEventDeleteResult {
    guard let parsedScope = CalendarEventEditScope(rawValue: scope.lowercased()) else {
      throw LorvexCoreError.validation(
        field: "scope",
        message: "Unknown scope '\(scope)'. Use all_in_series, this_only, or this_and_following.")
    }
    switch parsedScope {
    case .allEvents:
      return try deleteAllInSeriesCalendarEvent(eventID: eventID)
    case .thisEvent:
      return try deleteThisOnlyCalendarEvent(eventID: eventID, occurrenceDate: occurrenceDate)
    case .thisAndFollowing:
      return try deleteThisAndFollowingCalendarEvent(
        eventID: eventID, occurrenceDate: occurrenceDate)
    }
  }

  // MARK: - Shared low-level helpers

  /// Which locally-known occurrence decisions a physical cleanup targets.
  /// Correctness never depends on this cleanup: generation and recurrence
  /// membership make stale decisions inert even when they arrive later.
  enum DecisionSweepScope {
    /// Every decision linked to the series, across every generation.
    case all
    /// Decisions whose occurrence falls on or after `splitDate` (the "following"
    /// tail of a `this_and_following` operation).
    case onOrAfter(String)
  }

  struct DecisionSweepResult {
    var deletedAny = false
    var invalidatedReplacementEventIDs: [String] = []
  }

  /// Delete every locally-known decision row linked to `seriesId` matching
  /// `scope`, using the canonical single-row delete (sync tombstone + focus
  /// cleanup + changelog). This is bounded storage cleanup only. A peer may
  /// replay an old-generation decision after the sweep; it remains invisible.
  @discardableResult
  func sweepSeriesDecisions(
    _ db: Database, hlc: HlcSession, deviceId: String, seriesId: String,
    scope: DecisionSweepScope
  ) throws -> DecisionSweepResult {
    let predicate: String
    var arguments: [DatabaseValueConvertible] = [seriesId]
    switch scope {
    case .all:
      predicate = ""
    case .onOrAfter(let date):
      predicate = " AND recurrence_instance_date >= ?"
      arguments.append(date)
    }
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT id, occurrence_state FROM calendar_events "
        + "WHERE series_id = ?\(predicate) ORDER BY id",
      arguments: StatementArguments(arguments))
    var result = DecisionSweepResult()
    for row in rows {
      let id: String = row["id"]
      let state: String? = row["occurrence_state"]
      if try deleteCalendarEventRowInline(db, hlc: hlc, deviceId: deviceId, id: id) {
        result.deletedAny = true
        if state == CalendarOccurrenceState.replacement.rawValue {
          result.invalidatedReplacementEventIDs.append(id)
        }
      }
    }
    return result
  }

  /// Validate that `occurrenceDate` is a real member of the current recurring
  /// master. Scoped APIs must not create decisions for arbitrary dates.
  static func validateSeriesOccurrence(
    _ master: CalendarEventRow, occurrenceDate: String
  ) throws {
    guard master.seriesId == nil, let recurrence = master.recurrence else {
      throw LorvexCoreError.validation(
        field: "occurrence_date", message: "The calendar event is not a recurring series.")
    }
    guard IsoDate.parse(occurrenceDate) != nil else {
      throw LorvexCoreError.validation(
        field: "occurrence_date", message: "Invalid date format: \(occurrenceDate).")
    }
    guard occurrenceDate >= master.startDate.asString else {
      throw LorvexCoreError.validation(
        field: "occurrence_date", message: "The occurrence predates the series anchor.")
    }
    do {
      guard
        try CalendarRecurrence.recursOnDate(
          recurrenceJson: recurrence,
          baseDateYmd: master.startDate.asString,
          targetDateYmd: occurrenceDate)
      else {
        throw LorvexCoreError.validation(
          field: "occurrence_date",
          message: "The date is not an occurrence of the current recurrence pattern.")
      }
    } catch let error as LorvexCoreError {
      throw error
    } catch {
      throw LorvexCoreError.validation(
        field: "recurrence", message: "The stored recurrence rule is invalid: \(error)")
    }
  }

  /// Delete one `calendar_events` row with the full bookkeeping: edge tombstones
  /// (task↔event links) before the cascade, focus-schedule cleanup, the sync
  /// delete envelope (built from the pre-delete aggregate snapshot), and the
  /// changelog row. Returns whether a row was actually removed. Shared by the
  /// whole-event delete and every series sweep.
  @discardableResult
  func deleteCalendarEventRowInline(
    _ db: Database, hlc: HlcSession, deviceId: String, id: String
  ) throws -> Bool {
    let before = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: id)
    var eventSnapshot: JSONValue?
    do {
      eventSnapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.calendarEvent, entityId: id)
    } catch EnqueueError.entityNotFound {
      eventSnapshot = nil
    }
    // Stamp DELETE envelopes for every task↔event link edge BEFORE the
    // calendar_events DELETE fires its ON DELETE CASCADE on the link rows.
    try OutboxEnqueue.enqueueEdgeTombstonesForCalendarEventDelete(
      db, eventId: id, deviceId: deviceId, mintVersion: { hlc.nextVersionString() })
    try db.execute(sql: "DELETE FROM calendar_events WHERE id = ?", arguments: [id])
    let deleted = db.changesCount > 0
    // Deterministic segment ids can be referenced by a focus schedule or link
    // before their private event row arrives (event-first import/sync). Always
    // clean dependent references, even when the event row itself is absent.
    try removeCalendarEventFromFocusSchedules(db, hlc: hlc, deviceId: deviceId, calendarEventID: id)
    if deleted {
      if let eventSnapshot {
        try enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: id,
          payload: eventSnapshot)
      }
      try writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opDelete, entityType: EntityName.calendarEvent, entityId: id,
          summary: "Deleted calendar event '\(id)'", before: before),
        deviceId: deviceId)
    }
    return deleted
  }

  /// Resolve the recurrence rule for the replacement series in a
  /// `this_and_following` split: an explicit override wins; otherwise a
  /// COUNT-bounded original is rebased to the occurrences remaining from the
  /// split onward, and any other rule passes through unchanged.
  static func scopedReplacementRecurrence(
    original: String?, patch: CalendarEventRecurrencePatch,
    occurrenceDate: String, seriesStartDate: String
  ) throws -> String? {
    switch patch {
    case .clear:
      return nil
    case .set(let rule):
      guard let canonical = rule.canonicalRecurrenceJSON() else {
        throw LorvexCoreError.validation(
          field: "recurrence", message: "The recurrence rule could not be serialized.")
      }
      return canonical
    case .unset:
      break
    }
    guard let original else {
      return nil
    }
    guard let parsed = JSONValue.parse(original), case .object(var rule) = parsed else {
      return original
    }
    guard let count = calendarRecurrenceCount(rule), count > 0 else {
      return original
    }
    var beforeSplit = 0
    var current = seriesStartDate
    while current < occurrenceDate && beforeSplit < count {
      beforeSplit += 1
      guard
        let next = try CalendarRecurrence.calculateNextOccurrenceDate(
          recurrenceJson: original, baseDateYmd: current),
        next > current
      else {
        break
      }
      current = next
    }
    let remaining = max(1, count - beforeSplit)
    rule["COUNT"] = .int(Int64(remaining))
    return try SyncCanonicalize.canonicalizeJSON(.object(rule))
  }

  private static func calendarRecurrenceCount(_ rule: [String: JSONValue]) -> Int? {
    switch rule["COUNT"] {
    case .int(let value)? where value <= Int64(Int.max):
      return Int(value)
    case .uint(let value)? where value <= UInt64(Int.max):
      return Int(value)
    default:
      return nil
    }
  }
}
