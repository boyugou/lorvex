import Foundation

/// A naive local wall clock (year/month/day/hour/minute/second, no zone), the
/// input to ``DstResolution/resolveLocalDatetime(timezone:local:)``.
public struct NaiveDateTime: Sendable, Equatable, Hashable {
  public let year: Int
  public let month: Int
  public let day: Int
  public let hour: Int
  public let minute: Int
  public let second: Int

  public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
    self.year = year
    self.month = month
    self.day = day
    self.hour = hour
    self.minute = minute
    self.second = second
  }

  var components: DateComponents {
    var dc = DateComponents()
    dc.year = year
    dc.month = month
    dc.day = day
    dc.hour = hour
    dc.minute = minute
    dc.second = second
    return dc
  }
}

/// Outcome of resolving a naive local wall clock against an IANA zone.
///
/// Each case carries the resolved UTC
/// instant(s) as `Foundation.Date`; callers convert to whatever rendering they
/// need (tests check the UTC wall clock).
public enum DstResolution: Sendable, Equatable {
  /// Unambiguous — the wall clock maps to exactly one UTC instant.
  case valid(Date)
  /// Fall-back ambiguity — the wall clock occurs twice. `earlier` is the first
  /// occurrence (pre-transition offset), `later` the second.
  case ambiguous(earlier: Date, later: Date)
  /// Spring-forward gap — the wall clock was skipped entirely. `snappedTo` is the
  /// earliest valid instant after the gap, provided as a best-effort fallback.
  case skipped(requested: NaiveDateTime, snappedTo: Date)

  /// Resolve a naive local wall clock against an IANA timezone, reporting the DST
  /// shape explicitly. The single entry point for converting a user-supplied wall
  /// clock to UTC.
  ///
  /// Foundation has no `LocalResult`-style three-way classification, so it is
  /// reconstructed: a candidate instant is built, then its components are read
  /// back. If the round-trip differs, the wall clock fell in a spring-forward gap
  /// (`Skipped`). If it matches, the alternate-offset candidate (shifted by the
  /// zone's DST offset) is tested — if it also renders to the same wall clock the
  /// time is `Ambiguous` (fall-back overlap), otherwise `Valid`. The two
  /// ambiguous candidates are ordered by instant so `earlier`/`later` are
  /// stable regardless of which one Foundation picks first.
  public static func resolveLocalDatetime(
    timezone: TimeZone, local: NaiveDateTime
  ) -> DstResolution {
    let cal = calendar(timezone)
    guard let candidate = cal.date(from: local.components) else {
      // Foundation could not build the date at all; treat as a gap and snap.
      return .skipped(requested: local, snappedTo: snapForwardOutOfGap(timezone, local))
    }
    if !roundTripsTo(local, candidate, cal) {
      return .skipped(requested: local, snappedTo: snapForwardOutOfGap(timezone, local))
    }
    // Round-trips: Valid or Ambiguous. Probe the alternate DST offset.
    let dstOffset = timezone.daylightSavingTimeOffset(for: candidate)
    // The fall-back overlap spans the DST offset magnitude (typically 3600s).
    // Try both directions so the test does not depend on which offset Foundation
    // assigns to the boundary instant.
    let offsetMagnitude = abs(dstOffset) > 0 ? abs(dstOffset) : 3600
    for delta in [offsetMagnitude, -offsetMagnitude] {
      let alt = candidate.addingTimeInterval(delta)
      if alt != candidate, roundTripsTo(local, alt, cal) {
        let earlier = min(candidate, alt)
        let later = max(candidate, alt)
        return .ambiguous(earlier: earlier, later: later)
      }
    }
    return .valid(candidate)
  }

  /// Probe forward in 15-minute steps until a valid wall clock is reached,
  /// returning the resolved instant. Real DST gaps never exceed ~2 hours, so the
  /// cap of 120 steps (30 hours) is a
  /// generous guard against exotic zone data.
  static func snapForwardOutOfGap(_ timezone: TimeZone, _ local: NaiveDateTime) -> Date {
    let cal = calendar(timezone)
    var candidate = local
    for _ in 0..<120 {
      candidate = addMinutes(candidate, 15, cal)
      // Build the candidate at its own offset and check whether that wall clock
      // exists (round-trips). The first valid step out of the gap is the snap.
      if let date = cal.date(from: candidate.components), roundTripsTo(candidate, date, cal) {
        // If the stepped wall clock is itself ambiguous, take the earlier instant.
        let dstOffset = timezone.daylightSavingTimeOffset(for: date)
        let mag = abs(dstOffset) > 0 ? abs(dstOffset) : 3600
        for delta in [mag, -mag] {
          let alt = date.addingTimeInterval(delta)
          if alt != date, roundTripsTo(candidate, alt, cal) {
            return min(date, alt)
          }
        }
        return date
      }
    }
    // No real IANA zone reaches this branch; interpret the naive value as UTC.
    let utcCal = IsoDate.calendar
    return utcCal.date(from: local.components) ?? Date(timeIntervalSince1970: 0)
  }

  /// Add `minutes` to a naive wall clock as pure calendar arithmetic (no zone), so
  /// the step never silently re-snaps across a DST boundary.
  private static func addMinutes(
    _ local: NaiveDateTime, _ minutes: Int, _ cal: Calendar
  ) -> NaiveDateTime {
    let utcCal = IsoDate.calendar
    guard let base = utcCal.date(from: local.components),
      let shifted = utcCal.date(byAdding: .minute, value: minutes, to: base)
    else { return local }
    let c = utcCal.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: shifted)
    return NaiveDateTime(
      year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0,
      hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0)
  }

  /// True iff `date`, read back through `cal`, reproduces the input wall clock.
  private static func roundTripsTo(
    _ local: NaiveDateTime, _ date: Date, _ cal: Calendar
  ) -> Bool {
    let c = cal.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    return c.year == local.year && c.month == local.month && c.day == local.day
      && c.hour == local.hour && c.minute == local.minute && c.second == local.second
  }

  private static func calendar(_ timezone: TimeZone) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = timezone
    return cal
  }
}
