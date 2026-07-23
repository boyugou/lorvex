import Foundation
import LorvexDomain

extension CalendarRecurrence {
  // -------------------------------------------------------------------------
  // Core date arithmetic
  // -------------------------------------------------------------------------

  /// Advance `base` by `monthsToAdd` months, clamping the day to `targetDay`
  /// (or the month maximum). The explicit `targetDay` preserves BYMONTHDAY
  /// anchors through short months (Jan 31 → Feb 28 → Mar 31).
  static func addMonthsClamped(
    _ base: RDate, _ monthsToAdd: Int64, _ targetDay: UInt32
  ) -> RDate? {
    addMonthsWithAnchor(base, monthsToAdd, .fromStart(targetDay))
  }

  /// Like ``addMonthsClamped`` but accepts a signed anchor so `fromEnd(n)`
  /// (BYMONTHDAY=-n) resolves against the target month's length. Uses
  /// Euclidean div/mod so negative month indices wrap to the prior year —
  /// Swift's `/` and `%` truncate toward zero, which would give the wrong
  /// year/month for dates before the epoch month.
  static func addMonthsWithAnchor(
    _ base: RDate, _ monthsToAdd: Int64, _ anchor: ByMonthDayAnchor
  ) -> RDate? {
    // `year * 12 + month0 + monthsToAdd` can overflow Int64 for an absurd
    // INTERVAL (`monthsToAdd` near Int64.max). Overflow means the target month
    // is unrepresentably far out → no such occurrence.
    guard let base12 = Int64(base.year).multiplyingNoOverflow(12),
      let withMonth0 = base12.addingNoOverflow(Int64(base.month0)),
      let totalMonthIndex = withMonth0.addingNoOverflow(monthsToAdd)
    else { return nil }
    let newYear64 = totalMonthIndex.quotientAndRemainder(dividingBy: 12)
    // Euclidean division: floor toward negative infinity.
    var q = newYear64.quotient
    var r = newYear64.remainder
    if r < 0 {
      r += 12
      q -= 1
    }
    guard let newYear = Int(exactly: q) else { return nil }
    let newMonth0 = UInt32(r)
    let newMonth = newMonth0 + 1
    guard let day = anchor.resolve(newYear, newMonth) else { return nil }
    return RDate.fromYMD(newYear, newMonth, day)
  }

  static func addMonthsClampedRequired(
    _ base: RDate, _ monthsToAdd: Int64, _ anchor: ByMonthDayAnchor
  ) throws -> RDate {
    guard let result = addMonthsWithAnchor(base, monthsToAdd, anchor) else {
      throw StoreError.invariant(
        "failed to advance recurrence month from \(base.ymdString) by \(monthsToAdd) months with anchor \(anchor)"
      )
    }
    return result
  }

  static func nthWeekdayInMonth(
    _ year: Int, _ month: UInt32, _ dow: UInt32, _ ordinal: Int32
  ) -> RDate? {
    if ordinal == 0 { return nil }
    guard let maxDay = daysInMonth(year, month) else { return nil }
    if ordinal > 0 {
      guard let first = RDate.fromYMD(year, month, 1) else { return nil }
      let firstDow = first.numDaysFromSunday
      let offset = (dow + 7 - firstDow) % 7
      // Checked arithmetic so BYDAY=53MO can't overflow.
      guard let a = UInt32(ordinal).subtractingNoOverflow(1) else { return nil }
      guard let b = a.multiplyingNoOverflow(7) else { return nil }
      guard let day = b.addingNoOverflow(1 + offset) else { return nil }
      if day <= maxDay {
        return RDate.fromYMD(year, month, day)
      }
      return nil
    } else {
      guard let last = RDate.fromYMD(year, month, maxDay) else { return nil }
      let lastDow = last.numDaysFromSunday
      let offset = (lastDow + 7 - dow) % 7
      let absOrd = UInt32(ordinal.magnitude)
      guard let a = absOrd.subtractingNoOverflow(1) else { return nil }
      guard let b = a.multiplyingNoOverflow(7) else { return nil }
      guard let subtract = b.addingNoOverflow(offset) else { return nil }
      guard let day = maxDay.subtractingNoOverflow(subtract) else { return nil }
      return RDate.fromYMD(year, month, day)
    }
  }

  static func nthWeekdayInYear(_ year: Int, _ dow: UInt32, _ ordinal: Int32) -> RDate? {
    if ordinal == 0 { return nil }
    if ordinal > 0 {
      guard let first = RDate.fromYMD(year, 1, 1) else { return nil }
      let firstDow = first.numDaysFromSunday
      let offset = (dow + 7 - firstDow) % 7
      guard let a = UInt32(ordinal).subtractingNoOverflow(1) else { return nil }
      guard let b = a.multiplyingNoOverflow(7) else { return nil }
      guard let dayOfYear = b.addingNoOverflow(1 + offset) else { return nil }
      return RDate.fromYearOrdinal(year, dayOfYear)
    } else {
      guard let last = RDate.fromYMD(year, 12, 31) else { return nil }
      let lastDow = last.numDaysFromSunday
      let offset = (lastDow + 7 - dow) % 7
      let absOrd = UInt32(ordinal.magnitude)
      guard let a = absOrd.subtractingNoOverflow(1) else { return nil }
      guard let b = a.multiplyingNoOverflow(7) else { return nil }
      guard let subtract = b.addingNoOverflow(offset) else { return nil }
      guard let dayOfYear = last.ordinal.subtractingNoOverflow(subtract) else { return nil }
      return RDate.fromYearOrdinal(year, dayOfYear)
    }
  }

  static func applyBysetpos(_ candidates: [RDate], _ positions: [Int64]) -> [RDate] {
    var sorted = candidates.sorted()
    sorted = dedupSorted(sorted)
    let len = Int64(sorted.count)
    var selected: [RDate] = []
    for position in positions {
      let index: Int64 = position > 0 ? position - 1 : len + position
      if (0..<len).contains(index) {
        selected.append(sorted[Int(index)])
      }
    }
    selected.sort()
    return dedupSorted(selected)
  }

  static func resolveBymonthdayForMonth(
    _ anchor: ByMonthDayAnchor, _ year: Int, _ month: UInt32, _ clamp: Bool
  ) -> RDate? {
    guard let maxDay = daysInMonth(year, month) else { return nil }
    let day: UInt32
    switch anchor {
    case let .fromStart(d) where d <= maxDay:
      day = d
    case let .fromStart(d) where clamp:
      day = min(d, maxDay)
    case .fromStart:
      return nil
    case let .fromEnd(offset):
      let clamped = min(offset, maxDay)
      day = maxDay - clamped + 1
    }
    return RDate.fromYMD(year, month, day)
  }

  static func monthCandidates(
    _ rule: [String: JSONValue], _ year: Int, _ month: UInt32, _ fallbackDay: UInt32,
    _ applySetpos: Bool
  ) throws -> [RDate] {
    guard let maxDay = daysInMonth(year, month) else {
      throw StoreError.invariant(
        "invalid recurrence month \(year)-\(String(format: "%02d", month))")
    }
    let byday = try parseBydayTokens(rule)
    let bysetpos = try parseBysetpos(rule)
    let hasBymonthday: Bool = {
      switch rule["BYMONTHDAY"] {
      case nil, .some(.null): return false
      default: return true
      }
    }()
    let anchors = try parseBymonthday(rule, fallbackDay)

    var candidates: [RDate]
    if hasBymonthday {
      // Explicit BYMONTHDAY follows RFC 5545 §3.3.10: a positive day the month
      // lacks (31 in February) yields *no* occurrence — the month is skipped,
      // never clamped. A clamped Feb-28 instance is un-exportable: the EventKit
      // bridge (`daysOfTheMonth`) and the verbatim `BYMONTHDAY=31` RRULE both
      // skip, so the engine must skip too or expansion would disagree with every
      // synced/exported calendar. Negative anchors resolve against month length.
      // Multiple month-days (`[1, 15]`) each resolve independently; the sort +
      // dedup below merges them into a single ascending list for the month.
      candidates = anchors.compactMap { resolveBymonthdayForMonth($0, year, month, false) }
    } else if byday != nil || bysetpos != nil {
      candidates = (1...maxDay).compactMap { RDate.fromYMD(year, month, $0) }
    } else {
      // Implicit day-of-month, no positional keys: clamp to the month end so an
      // un-injected raw rule still advances. Authoring paths inject an explicit
      // BYMONTHDAY first (negative for month-end anchors), so the friendly
      // Jan31→Feb28→Mar31 series flows through the branch above, RFC-faithfully.
      // `anchors` here is the single fallback [.fromStart(fallbackDay)].
      candidates = anchors.compactMap { resolveBymonthdayForMonth($0, year, month, true) }
    }

    if let tokens = byday {
      candidates = candidates.filter { date in
        tokens.contains { token in
          if date.numDaysFromSunday != token.dow {
            return false
          }
          guard let ordinal = token.ordinal else { return true }
          return nthWeekdayInMonth(year, month, token.dow, ordinal) == date
        }
      }
    }

    candidates.sort()
    candidates = dedupSorted(candidates)
    if applySetpos, let positions = bysetpos {
      candidates = applyBysetpos(candidates, positions)
    }
    return candidates
  }

  static func firstMonthlyCandidateOnOrAfter(
    _ rule: [String: JSONValue], _ base: RDate, _ target: RDate, _ interval: Int64
  ) throws -> RDate? {
    let bymonth = try parseBymonth(rule)
    let tgt = max(target, base)
    let monthsBetween =
      (Int64(tgt.year - base.year) * 12) + Int64(tgt.month0) - Int64(base.month0)
    let initialSteps: Int64 = monthsBetween <= 0 ? 0 : max(monthsBetween / interval, 0)

    var steps = initialSteps
    while steps < initialSteps + 2400 {
      guard let baseFirst = RDate.fromYMD(base.year, base.month, 1) else {
        throw StoreError.invariant("invalid monthly recurrence base date \(base.ymdString)")
      }
      // `steps * interval` overflow for an absurd INTERVAL → no candidate in-window.
      guard let monthsToAdd = steps.multiplyingNoOverflow(interval) else { return nil }
      let monthStart = try addMonthsClampedRequired(baseFirst, monthsToAdd, .fromStart(1))
      let monthAllowed = bymonth.map { $0.contains(monthStart.month) } ?? true
      if monthAllowed {
        for candidate in try monthCandidates(
          rule, monthStart.year, monthStart.month, base.day, true)
        {
          if candidate >= tgt {
            return candidate
          }
        }
      }
      steps += 1
    }
    return nil
  }

  static func yearlyCandidates(
    _ rule: [String: JSONValue], _ base: RDate, _ year: Int
  ) throws -> [RDate] {
    let bymonth = try parseBymonth(rule)
    let byday = try parseBydayTokens(rule)
    let bysetpos = try parseBysetpos(rule)
    let hasBymonth: Bool = {
      switch rule["BYMONTH"] {
      case nil, .some(.null): return false
      default: return true
      }
    }()
    let hasBymonthday: Bool = {
      switch rule["BYMONTHDAY"] {
      case nil, .some(.null): return false
      default: return true
      }
    }()
    let months: [UInt32]
    if let m = bymonth {
      months = m
    } else if byday != nil && !hasBymonthday {
      months = Array(1...12)
    } else {
      months = [base.month]
    }

    var candidates: [RDate] = []
    for month in months {
      var monthDates = try monthCandidates(rule, year, month, base.day, false)
      if let tokens = byday, !hasBymonth {
        monthDates = monthDates.filter { date in
          tokens.contains { token in
            if date.numDaysFromSunday != token.dow {
              return false
            }
            guard let ordinal = token.ordinal else { return true }
            return nthWeekdayInYear(year, token.dow, ordinal) == date
          }
        }
      }
      candidates.append(contentsOf: monthDates)
    }

    if !hasBymonth, !hasBymonthday, byday == nil, bysetpos == nil {
      let anchors = try parseBymonthday(rule, base.day)
      candidates = anchors.compactMap { resolveBymonthdayForMonth($0, year, base.month, true) }
    }

    candidates.sort()
    candidates = dedupSorted(candidates)
    if let positions = bysetpos {
      candidates = applyBysetpos(candidates, positions)
    }
    return candidates
  }

  static func firstYearlyCandidateOnOrAfter(
    _ rule: [String: JSONValue], _ base: RDate, _ target: RDate, _ interval: Int64
  ) throws -> RDate? {
    let tgt = max(target, base)
    let yearsBetween = Int64(tgt.year - base.year)
    let initialSteps: Int64 = yearsBetween <= 0 ? 0 : max(yearsBetween / interval, 0)

    var steps = initialSteps
    while steps < initialSteps + 400 {
      // `steps * interval` overflow, or a step count exceeding Int32, means the
      // target year is unrepresentably far out → no candidate in-window.
      guard let stepYears = steps.multiplyingNoOverflow(interval),
        let stepYearsInt = Int32(exactly: stepYears)
      else {
        return nil
      }
      let year = base.year + Int(stepYearsInt)
      for candidate in try yearlyCandidates(rule, base, year) {
        if candidate >= tgt {
          return candidate
        }
      }
      steps += 1
    }
    return nil
  }
}

/// Checked unsigned arithmetic returning `nil` on overflow/underflow so
/// callers treat it as "no such occurrence".
extension UInt32 {
  func subtractingNoOverflow(_ other: UInt32) -> UInt32? {
    let (r, overflow) = subtractingReportingOverflow(other)
    return overflow ? nil : r
  }
  func multiplyingNoOverflow(_ other: UInt32) -> UInt32? {
    let (r, overflow) = multipliedReportingOverflow(by: other)
    return overflow ? nil : r
  }
  func addingNoOverflow(_ other: UInt32) -> UInt32? {
    let (r, overflow) = addingReportingOverflow(other)
    return overflow ? nil : r
  }
}

/// Checked signed arithmetic returning `nil` on overflow so recurrence-interval
/// math treats an out-of-range `INTERVAL` (e.g. a synced poison rule reaching
/// expansion) as "no further occurrence" instead of trapping.
extension Int64 {
  func multiplyingNoOverflow(_ other: Int64) -> Int64? {
    let (r, overflow) = multipliedReportingOverflow(by: other)
    return overflow ? nil : r
  }
  func addingNoOverflow(_ other: Int64) -> Int64? {
    let (r, overflow) = addingReportingOverflow(other)
    return overflow ? nil : r
  }
}
