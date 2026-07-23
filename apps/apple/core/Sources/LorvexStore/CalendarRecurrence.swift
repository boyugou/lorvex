import Foundation
import LorvexDomain

extension CalendarRecurrence {
  /// Check whether `[start, end]` overlaps the query window `[from, to]`
  /// (both inclusive).
  static func overlapsCalendarRange(
    _ start: RDate, _ end: RDate, _ from: RDate, _ to: RDate
  ) -> Bool {
    start <= to && end >= from
  }

  // -------------------------------------------------------------------------
  // first_occurrence_on_or_after
  // -------------------------------------------------------------------------

  /// First occurrence of a recurrence on or after `target`, anchored at
  /// `base`, respecting UNTIL bounds.
  static func firstOccurrenceOnOrAfter(
    _ recurrenceJson: String, _ base: RDate, _ target: RDate
  ) throws -> RDate? {
    let rule = try parseRuleObject(recurrenceJson)
    return try firstOccurrenceOnOrAfter(rule: rule, base, target)
  }

  /// `firstOccurrenceOnOrAfter` over an already-parsed rule object. The
  /// per-occurrence expansion loop parses the recurrence JSON once and threads
  /// the rule here to avoid re-parsing it on every step. Identical result to
  /// the string overload.
  static func firstOccurrenceOnOrAfter(
    rule: [String: JSONValue], _ base: RDate, _ target: RDate
  ) throws -> RDate? {
    let freq = try parseFreq(rule)
    let interval = try parseInterval(rule)
    let until = try parseUntil(rule)
    if let bound = until, target > bound {
      return nil
    }

    let candidate: RDate
    switch freq {
    case "DAILY":
      guard let date = firstDailyCandidateOnOrAfter(base, target, interval) else {
        return nil
      }
      candidate = date
    case "WEEKLY":
      guard let date = try firstWeeklyCandidateOnOrAfter(rule, base, target, interval) else {
        return nil
      }
      candidate = date
    case "MONTHLY":
      guard let date = try firstMonthlyCandidateOnOrAfter(rule, base, target, interval) else {
        return nil
      }
      candidate = date
    case "YEARLY":
      guard let date = try firstYearlyCandidateOnOrAfter(rule, base, target, interval) else {
        return nil
      }
      candidate = date
    default:
      throw StoreError.validation("invalid recurrence rule: unsupported FREQ \(freq)")
    }

    if let bound = until, candidate > bound {
      return nil
    }
    return candidate
  }

  /// First DAILY occurrence on or after `target`, anchored at `base` with the
  /// given `interval`. Returns `nil` when the next occurrence would fall past
  /// the representable date range — an absurd `INTERVAL` pushes it beyond what
  /// the calendar can represent. Every step (`delta + interval`,
  /// `steps * interval`, and the day-shift) is overflow-checked, so no value of
  /// `interval` up to `Int64.max` can trap; the series simply yields no
  /// in-window occurrence.
  static func firstDailyCandidateOnOrAfter(
    _ base: RDate, _ target: RDate, _ interval: Int64
  ) -> RDate? {
    if target <= base {
      return base
    }
    let delta = base.daysUntil(target)
    guard let numerator = delta.addingNoOverflow(interval)?.addingNoOverflow(-1) else {
      return nil
    }
    let steps = numerator / interval
    guard let offset = steps.multiplyingNoOverflow(interval),
      let candidate = base.addingDays(offset)
    else { return nil }
    return candidate
  }

  /// Public string entry point for `firstOccurrenceOnOrAfter`, taking and
  /// returning canonical `YYYY-MM-DD` strings. THE function the
  /// recurrence-exception validators call.
  public static func firstOccurrenceOnOrAfter(
    recurrenceJson: String, baseDateYmd: String, targetDateYmd: String
  ) throws -> String? {
    let base = try parseRequiredYmd(baseDateYmd, "base_date")
    let target = try parseRequiredYmd(targetDateYmd, "target_date")
    return try firstOccurrenceOnOrAfter(recurrenceJson, base, target)?.ymdString
  }

  // -------------------------------------------------------------------------
  // recurs_on_date
  // -------------------------------------------------------------------------

  /// Whether a recurring event has an occurrence on exactly
  /// `targetDateYmd`.
  public static func recursOnDate(
    recurrenceJson: String, baseDateYmd: String, targetDateYmd: String
  ) throws -> Bool {
    let base = try parseRequiredYmd(baseDateYmd, "base_date")
    let target = try parseRequiredYmd(targetDateYmd, "target_date")
    if target < base {
      return false
    }
    if target == base {
      return true
    }

    // R-1: anchor a MONTHLY/YEARLY rule without an explicit BYMONTHDAY to the
    // original base day (clamped per month) so a bounded (COUNT) series doesn't
    // drift after a month-end clamp — the loop below chains `current`, so Jan-31
    // would otherwise become Feb-28 → Mar-28 → …. Same family as the
    // calendar-expansion fix.
    let anchoredJson =
      try injectBymonthday(recurrenceJson: recurrenceJson, dueDateYmd: baseDateYmd) ?? recurrenceJson

    let rule = try parseRuleObject(anchoredJson)

    if let until = try parseUntil(rule), target > until {
      return false
    }

    if let count = try parseBoundedCountForExpansion(rule) {
      var current = baseDateYmd
      var i: Int64 = 1
      while i < count {
        guard let next = try calculateNextOccurrenceDate(anchoredJson, current),
          next > current
        else {
          return false
        }
        if next == targetDateYmd {
          return true
        }
        if next > targetDateYmd {
          return false
        }
        current = next
        i += 1
      }
      return false
    }

    let first = try firstOccurrenceOnOrAfter(anchoredJson, base, target)
    return first == target
  }

  // -------------------------------------------------------------------------
  // calculate_next_occurrence_date
  // -------------------------------------------------------------------------

  static func calculateNextOccurrenceDate(
    _ recurrenceJson: String, _ baseDateYmd: String
  ) throws -> String? {
    let rule = try parseRuleObject(recurrenceJson)
    return try calculateNextOccurrenceDate(rule: rule, base: parseRequiredYmd(baseDateYmd, "base_date"))?.ymdString
  }

  /// `calculateNextOccurrenceDate` over an already-parsed rule + ``RDate``
  /// base, returning the next ``RDate`` (or `nil` past UNTIL). Lets the
  /// expansion loop step without re-parsing the JSON each iteration. Identical
  /// result to the string overload.
  static func calculateNextOccurrenceDate(
    rule: [String: JSONValue], base: RDate
  ) throws -> RDate? {
    // At the calendar's upper boundary there is no representable next day, so
    // there is no next occurrence.
    guard let target = base.addingDays(1) else { return nil }
    guard let next = try firstOccurrenceOnOrAfter(rule: rule, base, target) else {
      return nil
    }
    if let until = try parseUntil(rule), next > until {
      return nil
    }
    return next
  }

  /// Public entry point for the next occurrence after `baseDateYmd`,
  /// respecting UNTIL.
  public static func calculateNextOccurrenceDate(
    recurrenceJson: String, baseDateYmd: String
  ) throws -> String? {
    try calculateNextOccurrenceDate(recurrenceJson, baseDateYmd)
  }

  // -------------------------------------------------------------------------
  // next_occurrence_strictly_after
  // -------------------------------------------------------------------------

  /// Next recurrence strictly after both `todayYmd` and `baseDateYmd`, using
  /// `baseDateYmd` for cadence alignment.
  public static func nextOccurrenceStrictlyAfter(
    recurrenceJson: String, baseDateYmd: String, todayYmd: String
  ) throws -> String? {
    let base = try parseRequiredYmd(baseDateYmd, "base_date")
    let today = try parseRequiredYmd(todayYmd, "today")
    let floor = base > today ? base : today
    guard let target = floor.addingDays(1) else { return nil }
    return try firstOccurrenceOnOrAfter(recurrenceJson, base, target)?.ymdString
  }

  // -------------------------------------------------------------------------
  // count_end_date
  // -------------------------------------------------------------------------

  /// Date of the Nth occurrence (1-indexed; COUNT=1 → the base date itself).
  /// Returns `nil` if COUNT is absent or the series terminates early.
  public static func countEndDate(
    recurrenceJson: String, baseDate: String
  ) throws -> String? {
    let rule = try parseRuleObject(recurrenceJson)
    let base = try parseRequiredYmd(baseDate, "base_date")
    return try countEndDate(rule: rule, base: base)?.ymdString
  }

  /// `countEndDate` over an already-parsed rule + ``RDate`` base, returning the
  /// COUNT-th occurrence as an ``RDate`` (or `nil` when COUNT is absent / the
  /// series terminates early). Lets the expansion loop reuse the parsed rule.
  /// Identical result to the string overload.
  static func countEndDate(
    rule: [String: JSONValue], base: RDate
  ) throws -> RDate? {
    guard let count = try parseBoundedCountForExpansion(rule) else {
      return nil
    }
    if count == 1 {
      return base
    }
    let boundedCount = min(count, maxRecurrenceCount)
    var current = base
    var i: Int64 = 1
    while i < boundedCount {
      guard let next = try calculateNextOccurrenceDate(rule: rule, base: current) else {
        return nil
      }
      if next <= current {
        throw StoreError.invariant(
          "non-advancing recurrence when computing COUNT end date from \(current.ymdString)")
      }
      current = next
      i += 1
    }
    return current
  }

  // -------------------------------------------------------------------------
  // mutation helpers
  // -------------------------------------------------------------------------

  /// For MONTHLY/YEARLY rules without an explicit BYMONTHDAY, inject the
  /// day-of-month from `dueDateYmd` so "monthly on the 15th" stays anchored.
  /// Returns `nil` when injection is not needed.
  ///
  /// The injected value is `BYMONTHDAY=-1` (count-from-end, "last day of the
  /// month") ONLY when the anchor day is invariantly its month's last day —
  /// see ``anchoredBymonthdayValue(_:)``. That reproduces the friendly
  /// month-end series (Jan31→Feb28→Mar31→Apr30) while staying RFC 5545-faithful
  /// and exportable — a positive month-end day would instead *skip* short months
  /// at expansion. Any other day (including a Feb-28 in a common year, which is
  /// the literal 28th rather than a month-end) is injected verbatim and skips
  /// months it lacks.
  public static func injectBymonthday(
    recurrenceJson: String, dueDateYmd: String
  ) throws -> String? {
    var rule = try parseRuleObject(recurrenceJson)
    let freq = try parseFreq(rule)
    if freq != "MONTHLY" && freq != "YEARLY" {
      return nil
    }
    if !isNoneOrNull(rule["BYMONTHDAY"]) {
      return nil
    }
    if !isNoneOrNull(rule["BYDAY"]) || !isNoneOrNull(rule["BYSETPOS"]) {
      return nil
    }
    let date = try parseRequiredYmd(dueDateYmd, "due_date")
    // BYMONTHDAY is canonically an array; inject the single anchor as a
    // one-element array so the stored rule matches the normalizer's wire shape.
    rule["BYMONTHDAY"] = .array([.int(anchoredBymonthdayValue(date))])
    do {
      let canonical = try canonicalizeJSON(.object(rule))
      return canonical
    } catch {
      throw StoreError.serialization(
        "canonicalize recurrence after BYMONTHDAY inject: \(error)")
    }
  }

  /// Day-of-month value ``injectBymonthday`` writes for an anchor `date`.
  ///
  /// Returns `-1` (RFC 5545 count-from-end, "last day of the month") only when
  /// the anchor is INVARIANTLY its month's last day across every year — i.e. its
  /// day equals the month's maximum possible length. This is year-independent:
  /// February's maximum length is 29, so a Feb-28 in a common year is the literal
  /// 28th (`BYMONTHDAY=28`), not a month-end anchor, and only Feb-29 in a leap
  /// year reads as "last day of February" (`-1`). Every 30- or 31-day month is
  /// unambiguous because its length never varies (Jan-31 → -1, Apr-30 → -1,
  /// Mar-30 → 30). Any other day injects verbatim.
  static func anchoredBymonthdayValue(_ date: RDate) -> Int64 {
    // Only February's length varies by year; its invariant month-end is the
    // leap-year value, 29. All other months' actual length is already invariant.
    let maxDay: UInt32 = date.month == 2 ? 29 : (daysInMonth(date.year, date.month) ?? date.day)
    return date.day == maxDay ? -1 : Int64(date.day)
  }

  /// Re-anchor a stored MONTHLY/YEARLY rule whose BYMONTHDAY was auto-injected
  /// from `oldAnchorYmd` (see ``injectBymonthday``) so it instead reflects
  /// `newAnchorYmd`, reproducing what create-time normalization would have
  /// injected had the series been created at the new anchor. Returns the input
  /// JSON verbatim when nothing is re-anchored.
  ///
  /// Only an auto-injected anchor day is re-derived: the stored BYMONTHDAY is
  /// re-anchored when it is a single element equal to
  /// ``anchoredBymonthdayValue(_:)`` for `oldAnchorYmd`. A BYMONTHDAY the caller
  /// set explicitly (any other value or shape) is left untouched, and rules that
  /// never receive injection — WEEKLY, or MONTHLY/YEARLY carrying
  /// BYDAY/BYSETPOS — pass through unchanged. This makes "move the series' start"
  /// yield the same day-of-month rule as "create the series at that start"
  /// without clobbering a deliberately-chosen day-of-month.
  public static func reanchorBymonthday(
    recurrenceJson: String, oldAnchorYmd: String, newAnchorYmd: String
  ) throws -> String {
    var rule = try parseRuleObject(recurrenceJson)
    let freq = try parseFreq(rule)
    guard freq == "MONTHLY" || freq == "YEARLY" else { return recurrenceJson }
    guard isNoneOrNull(rule["BYDAY"]), isNoneOrNull(rule["BYSETPOS"]) else {
      return recurrenceJson
    }
    guard case .array(let elements)? = rule["BYMONTHDAY"], elements.count == 1,
      let storedDay = elements[0].rcI64
    else {
      return recurrenceJson
    }
    let oldAnchor = try parseRequiredYmd(oldAnchorYmd, "old_anchor")
    guard storedDay == anchoredBymonthdayValue(oldAnchor) else {
      // Stored day differs from the old anchor's auto-injected value → it was
      // chosen explicitly; preserve it rather than overwrite the user's rule.
      return recurrenceJson
    }
    let newDay = anchoredBymonthdayValue(try parseRequiredYmd(newAnchorYmd, "new_anchor"))
    if newDay == storedDay { return recurrenceJson }
    rule["BYMONTHDAY"] = .array([.int(newDay)])
    do {
      return try canonicalizeJSON(.object(rule))
    } catch {
      throw StoreError.serialization(
        "canonicalize recurrence after BYMONTHDAY re-anchor: \(error)")
    }
  }

  /// Decrement the COUNT field for a spawned successor. `nil` when COUNT==1
  /// (last occurrence), original when no COUNT key, decremented otherwise.
  /// COUNT<1 surfaces as `StoreError.invariant`.
  public static func decrementRecurrenceCount(
    recurrenceJson: String
  ) throws -> String? {
    var rule = try parseRuleObject(recurrenceJson)

    if let value = rule["COUNT"], let rawCount = value.rcI64, rawCount < 1 {
      throw StoreError.invariant(
        "recurrence COUNT=\(rawCount) violates invariant (expected >= 1) — "
          + "a peer payload bypassed validation; refusing to silently clear "
          + "the recurrence series")
    }

    switch try parsePositiveCount(rule) {
    case 1:
      return nil
    case let .some(count):
      rule["COUNT"] = .int(count - 1)
      do {
        return try canonicalizeJSON(.object(rule))
      } catch {
        throw StoreError.serialization(
          "canonicalize recurrence after COUNT decrement: \(error)")
      }
    case nil:
      return recurrenceJson
    }
  }

  // -------------------------------------------------------------------------
  // completion-anchored advancement (Lorvex ANCHOR extension)
  // -------------------------------------------------------------------------

  /// Whether the rule carries `"ANCHOR":"completion"`: the next occurrence is
  /// measured from the completion date rather than the fixed calendar cadence.
  public static func recurrenceAnchorIsCompletion(recurrenceJson: String) throws -> Bool {
    let rule = try parseRuleObject(recurrenceJson)
    return rule["ANCHOR"]?.rcStr == "completion"
  }

  /// Next due date for a completion-anchored rule: `INTERVAL` units of `FREQ`
  /// after `completionYmd`. Returns `nil` when the result falls past `UNTIL`
  /// (series ended). Positional keys (BYDAY/BYMONTH/…) are intentionally
  /// ignored — the normalizer rejects them on completion-anchored rules.
  public static func nextOccurrenceAfterCompletion(
    recurrenceJson: String, completionYmd: String
  ) throws -> String? {
    let rule = try parseRuleObject(recurrenceJson)
    let freq = try parseFreq(rule)
    let interval = try parseInterval(rule)
    let base = try parseRequiredYmd(completionYmd, "completion_date")

    let next: RDate?
    switch freq {
    case "DAILY": next = base.addingDays(interval)
    case "WEEKLY": next = interval.multiplyingNoOverflow(7).flatMap { base.addingDays($0) }
    case "MONTHLY": next = base.addingMonths(interval)
    case "YEARLY": next = interval.multiplyingNoOverflow(12).flatMap { base.addingMonths($0) }
    default:
      throw StoreError.validation("invalid recurrence rule: unsupported FREQ \(freq)")
    }
    guard let resolved = next else {
      throw StoreError.invariant(
        "completion-anchored recurrence overflowed advancing from \(completionYmd)")
    }
    if let until = try parseUntil(rule), resolved > until {
      return nil
    }
    return resolved.ymdString
  }

  private static func isNoneOrNull(_ value: JSONValue?) -> Bool {
    switch value {
    case nil, .some(.null): return true
    default: return false
    }
  }
}
