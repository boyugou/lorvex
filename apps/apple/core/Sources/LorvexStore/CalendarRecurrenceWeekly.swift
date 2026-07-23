import Foundation
import LorvexDomain

extension CalendarRecurrence {
  /// Sorted, deduplicated day-of-week numbers from a rule's `BYDAY` array.
  /// Returns `nil` if the array is absent or empty.
  static func weeklyTargetDows(_ rule: [String: JSONValue]) throws -> [UInt32]? {
    guard let byday = rule["BYDAY"]?.rcArray else {
      return nil
    }
    if byday.isEmpty {
      return nil
    }
    var targetDows: [UInt32] = []
    targetDows.reserveCapacity(byday.count)
    for raw in byday {
      guard let code = raw.rcStr else {
        throw StoreError.validation(
          "invalid recurrence rule: BYDAY entries must be weekday codes")
      }
      guard let dow = bydayCodeToNum(code) else {
        throw StoreError.validation(
          "invalid recurrence rule: unsupported BYDAY code \(code)")
      }
      targetDows.append(dow)
    }
    targetDows.sort()
    return dedupSorted(targetDows)
  }

  /// For a WEEKLY rule with BYDAY, find the first occurrence on or after
  /// `target` aligned to the cadence anchored at `base`.
  static func firstWeeklyBydayOccurrenceOnOrAfter(
    _ rule: [String: JSONValue], _ base: RDate, _ target: RDate, _ interval: Int64
  ) throws -> RDate? {
    guard var targetDows = try weeklyTargetDows(rule) else {
      return nil
    }
    let wkst = try parseWkst(rule)
    func weekStart(_ date: RDate) -> RDate? {
      let dow = date.numDaysFromSunday
      return date.addingDays(-Int64((dow + 7 - wkst) % 7))
    }
    func dayOffset(_ dow: UInt32) -> Int64 { Int64((dow + 7 - wkst) % 7) }
    targetDows.sort { dayOffset($0) < dayOffset($1) }
    // Week-start shifts are tiny (0–6 days) on in-window dates; `nil` only at the
    // extreme calendar boundary, which has no representable occurrence anyway.
    guard let baseWeekStart = weekStart(base),
      let targetWeekStart = weekStart(max(target, base))
    else { return nil }
    let weeksBetween = max(baseWeekStart.daysUntil(targetWeekStart) / 7, 0)
    // `(weeksBetween / interval) * interval <= weeksBetween`, so this product is
    // bounded by the representable day span and cannot overflow.
    let alignedWeeks = (weeksBetween / interval) * interval
    guard let alignedDays = alignedWeeks.multiplyingNoOverflow(7),
      var currentWeekStart = baseWeekStart.addingDays(alignedDays)
    else { return nil }

    for _ in 0..<3 {
      let minimumDate: RDate
      if currentWeekStart == baseWeekStart {
        minimumDate = max(base, target)
      } else {
        minimumDate = max(target, currentWeekStart)
      }
      for dow in targetDows {
        guard let candidate = currentWeekStart.addingDays(dayOffset(dow)) else { continue }
        if candidate < base {
          continue
        }
        if candidate >= minimumDate {
          return candidate
        }
      }
      // Advance one INTERVAL of weeks. Overflow of `interval * 7`, or a shift
      // past the calendar's representable range, means no further occurrence
      // exists → stop rather than trap.
      guard let stepDays = interval.multiplyingNoOverflow(7),
        let advanced = currentWeekStart.addingDays(stepDays)
      else { return nil }
      currentWeekStart = advanced
    }

    return nil
  }

  static func firstWeeklyCandidateOnOrAfter(
    _ rule: [String: JSONValue], _ base: RDate, _ target: RDate, _ interval: Int64
  ) throws -> RDate? {
    let bymonth = try parseBymonth(rule)
    func allowedMonth(_ date: RDate) -> Bool {
      guard let months = bymonth else { return true }
      return months.contains(date.month)
    }

    let bydayNonEmpty = (rule["BYDAY"]?.rcArray).map { !$0.isEmpty } ?? false
    if bydayNonEmpty {
      var cursor = max(target, base)
      for _ in 0..<2400 {
        guard
          let candidate = try firstWeeklyBydayOccurrenceOnOrAfter(rule, base, cursor, interval)
        else {
          return nil
        }
        if allowedMonth(candidate) {
          return candidate
        }
        guard let next = candidate.addingDays(1) else { return nil }
        cursor = next
      }
      throw StoreError.invariant(
        "failed to find weekly BYMONTH recurrence candidate from \(base.ymdString) on or after \(target.ymdString)"
      )
    }

    let tgt = max(target, base)
    // `interval * 7`, `delta + intervalDays - 1`, and `steps * intervalDays` can
    // each exceed Int64 for an absurd INTERVAL; the day-shift can exceed the
    // calendar range. Any overflow means the next occurrence is unrepresentably
    // far out → no occurrence in-window.
    guard let intervalDays = interval.multiplyingNoOverflow(7) else { return nil }
    let delta = max(base.daysUntil(tgt), 0)
    guard let numerator = delta.addingNoOverflow(intervalDays)?.addingNoOverflow(-1) else {
      return nil
    }
    let initialSteps = numerator / intervalDays
    var steps = initialSteps
    while steps < initialSteps + 2400 {
      guard let offset = steps.multiplyingNoOverflow(intervalDays),
        let candidate = base.addingDays(offset)
      else { return nil }
      if candidate >= tgt, allowedMonth(candidate) {
        return candidate
      }
      steps += 1
    }
    throw StoreError.invariant(
      "failed to find weekly recurrence candidate from \(base.ymdString) on or after \(target.ymdString)"
    )
  }
}
