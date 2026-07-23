import Foundation
import LorvexDomain

extension CalendarTimeline {

  /// A timeline item plus the recurrence fields stripped before output.
  struct RawCalendarRow {
    var item: CalendarTimelineItem
    var recurrence: String?
    var recurrenceExceptions: String?
    var ownedFromDate: String?
    var ownedUntilDate: String?

    init(
      item: CalendarTimelineItem,
      recurrence: String?,
      recurrenceExceptions: String?,
      ownedFromDate: String? = nil,
      ownedUntilDate: String? = nil
    ) {
      self.item = item
      self.recurrence = recurrence
      self.recurrenceExceptions = recurrenceExceptions
      self.ownedFromDate = ownedFromDate
      self.ownedUntilDate = ownedUntilDate
    }
  }

  /// Hard upper bound on instances expanded for a single recurrence row in
  /// one call. Hitting the cap returns the partial list with
  /// `truncatedAtStepCap = true`, not an error.
  static let maxExpansionSteps = 5_000

  /// Outcome of ``expandRowForRange``: the occurrence list plus a flag set
  /// when expansion stopped at ``maxExpansionSteps``.
  struct ExpandedCalendarRow {
    var items: [CalendarTimelineItem]
    var truncatedAtStepCap: Bool
  }

  /// Expand a single raw row into the `CalendarTimelineItem`s overlapping
  /// `[from, to]`. Non-recurring rows return their (projected) span if it
  /// overlaps; recurring rows emit each in-window occurrence as a separate
  /// item, suppressing dates in the EXDATE set.
  static func expandRowForRange(
    _ row: RawCalendarRow, _ from: RDate, _ to: RDate, _ anchorTimezone: String
  ) throws -> ExpandedCalendarRow {
    let baseStart = try CalendarRecurrence.parseYmd(row.item.startDate.asString)
    let baseEnd = try row.item.endDate.map { try CalendarRecurrence.parseYmd($0.asString) } ?? baseStart
    let durationDays = max(baseStart.daysUntil(baseEnd), 0)

    let recurrence: String? = {
      if let raw = row.recurrence, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return nil
    }()

    // ── Non-recurring ────────────────────────────────────────────────
    guard let recurrence else {
      // A tail whose recurrence was cleared still represents the occurrence at
      // its cutover slot even when the one-off display timing was moved.
      let originalSlot = row.ownedFromDate ?? row.item.startDate.asString
      if let ownedFromDate = row.ownedFromDate, originalSlot < ownedFromDate {
        return ExpandedCalendarRow(items: [], truncatedAtStepCap: false)
      }
      if let ownedUntilDate = row.ownedUntilDate, originalSlot >= ownedUntilDate {
        return ExpandedCalendarRow(items: [], truncatedAtStepCap: false)
      }
      let projected = try projectItemToAnchor(row.item, anchorTimezone)
      if overlapsItemRange(projected, from, to) {
        return ExpandedCalendarRow(items: [projected], truncatedAtStepCap: false)
      }
      return ExpandedCalendarRow(items: [], truncatedAtStepCap: false)
    }

    // R-1: anchor a MONTHLY/YEARLY rule that lacks an explicit BYMONTHDAY to the
    // *original* start day (clamped per month) before expanding. Otherwise the
    // loop derives each month's fallback day from the previous (possibly clamped)
    // occurrence, so a Jan-31 monthly series collapses to Feb-28 → Mar-28 → …
    // instead of 31/30/28. Reuses the task-spawn `injectBymonthday` mitigation.
    let anchoredRecurrence =
      try CalendarRecurrence.injectBymonthday(
        recurrenceJson: recurrence, dueDateYmd: baseStart.ymdString) ?? recurrence

    // Parse the recurrence JSON once and thread the rule object through every
    // per-occurrence step below; re-parsing it each step dominated expansion.
    let rule = try validateRecurrenceJSON(anchoredRecurrence, eventId: row.item.id)

    let bufferDays = projectionBufferDays(row.item)

    // ── COUNT-derived effective end ──────────────────────────────────
    // Buffer the scan window, never the series bound. The timed-projection
    // buffer widens how far past `to` we look for occurrences that project
    // back into the window, but a COUNT-bounded series has no occurrence
    // beyond its COUNT-th, so the loop must stop at `countLimit`. Adding the
    // buffer to the count bound admits a phantom (COUNT+1)th step because
    // `calculateNextOccurrenceDate` honors UNTIL but not COUNT.
    let countLimit = try CalendarRecurrence.countEndDate(rule: rule, base: baseStart)
    // Window-buffer shifts are small; `nil` only at the calendar boundary, where
    // the un-buffered bound is the correct fallback.
    let bufferedTo = to.addingDays(bufferDays) ?? to
    let effectiveTo = countLimit.map { min(bufferedTo, $0) } ?? bufferedTo

    // If the count-limited series ended before the query window, skip.
    if let limit = countLimit, limit < (from.addingDays(-durationDays) ?? from) {
      return ExpandedCalendarRow(items: [], truncatedAtStepCap: false)
    }

    // ── Parse exception dates ────────────────────────────────────────
    let excluded = try parseRecurrenceExceptions(row.recurrenceExceptions, eventId: row.item.id)

    // ── First occurrence on or after the adjusted start ──────────────
    var targetStart = from.addingDays(-(durationDays + bufferDays)) ?? from
    if let ownedFromDate = row.ownedFromDate,
      let ownedFrom = try? CalendarRecurrence.parseYmd(ownedFromDate),
      ownedFrom > targetStart
    {
      targetStart = ownedFrom
    }
    let targetEnd = to.addingDays(bufferDays) ?? to
    guard
      var currentStart = try CalendarRecurrence.firstOccurrenceOnOrAfter(
        rule: rule, baseStart, targetStart)
    else {
      return ExpandedCalendarRow(items: [], truncatedAtStepCap: false)
    }

    var out: [CalendarTimelineItem] = []
    var truncated = false
    var guardCount = 0

    while currentStart <= effectiveTo {
      guardCount += 1
      if guardCount > maxExpansionSteps {
        truncated = true
        break
      }

      let currentStr = currentStart.ymdString
      if let ownedUntilDate = row.ownedUntilDate, currentStr >= ownedUntilDate {
        break
      }
      // A multi-day occurrence whose end rolls past the representable range can
      // no longer be projected; later occurrences advance monotonically and are
      // equally unrepresentable, so stop rather than trap on the boundary.
      guard let currentEnd = currentStart.addingDays(durationDays) else { break }

      if !excluded.contains(currentStr)
        && CalendarRecurrence.overlapsCalendarRange(currentStart, currentEnd, targetStart, targetEnd)
      {
        // Stop expanding once an occurrence rolls past the representable date
        // range. `LorvexDate.parse` accepts only a 10-character `YYYY-MM-DD`, so
        // a year ≥ 10000 renders to 11 characters and cannot be stored (a
        // multi-day occurrence anchored at 9999-12-31 reaches this via its end
        // date). Occurrences advance monotonically, so every later one is
        // equally unrepresentable — break rather than crash on the boundary.
        guard let newStartDate = try? LorvexDate.parse(currentStart.ymdString).get() else { break }
        let newEndDate: LorvexDate?
        if row.item.endDate != nil {
          guard let parsedEnd = try? LorvexDate.parse(currentEnd.ymdString).get() else { break }
          newEndDate = parsedEnd
        } else {
          newEndDate = nil
        }
        let newTiming = CalendarEventTiming.fromFlatFields(
          startDate: newStartDate, startTime: row.item.startTime,
          endDate: newEndDate, endTime: row.item.endTime, allDay: row.item.allDay)
        switch newTiming {
        case let .success(t):
          var instance = row.item
          instance.timing = t
          if instance.source == .canonical,
            let seriesId = instance.seriesId,
            let generation = instance.recurrenceGeneration
          {
            instance.id = CalendarOccurrenceDecisionID.make(
              seriesId: seriesId,
              recurrenceGeneration: generation,
              recurrenceInstanceDate: currentStr)
            instance.recurrenceInstanceDate = currentStr
          } else if instance.source == .provider {
            instance.id = "\(instance.eventId):occurrence:\(currentStr)"
          }
          let projected = try projectItemToAnchor(instance, anchorTimezone)
          if overlapsItemRange(projected, from, to) {
            out.append(projected)
          }
        case let .failure(err):
          throw StoreError.validation(
            "expanded occurrence timing invalid for calendar event \(row.item.id): \(err.messageString)")
        }
      }

      guard
        let nextStart = try CalendarRecurrence.calculateNextOccurrenceDate(rule: rule, base: currentStart)
      else { break }
      if nextStart <= currentStart {
        throw StoreError.invariant(
          "calendar recurrence rule did not advance past \(currentStr) for event '\(row.item.id)' "
            + "— likely malformed RRULE")
      }
      currentStart = nextStart
    }

    return ExpandedCalendarRow(items: out, truncatedAtStepCap: truncated)
  }

  /// Parse the EXDATE registry into a set, surfacing malformed JSON as a
  /// `StoreError.serialization` with the event id interpolated.
  static func parseRecurrenceExceptions(
    _ raw: String?, eventId: String
  ) throws -> Set<String> {
    do {
      return try RecurrenceExceptionsRepo.parseExceptionDatesAsSet(raw)
    } catch let StoreError.validation(m) {
      throw StoreError.serialization(
        "invalid recurrence_exceptions for calendar event \(eventId): \(m)")
    }
  }

  /// Validate that `raw` parses to a JSON object and return the parsed rule so
  /// the expansion loop can reuse it instead of re-parsing the JSON on every
  /// occurrence step. On failure it throws `.serialization` with the event id.
  @discardableResult
  static func validateRecurrenceJSON(_ raw: String, eventId: String) throws -> [String: JSONValue] {
    guard let parsed = JSONValue.parse(raw), case let .object(rule) = parsed else {
      throw StoreError.serialization(
        "invalid recurrence rule for calendar event \(eventId): recurrence must be a JSON object")
    }
    return rule
  }
}
