import Foundation
import LorvexDomain

/// Pure expansion of habit-reminder policies into concrete future firings,
/// shared by every `LorvexHabitServicing` backend so the on-disk core and the
/// in-memory fake apply byte-identical cadence / target / future gating.
///
/// The period-progress rules (period progress `<` the required completions per
/// period, over daily / week-bucket / monthly buckets) run across a rolling
/// horizon rather than a single "now" tick. Fire days are gated by
/// ``isHabitReminderDay(_:_:)`` rather than ``isHabitScheduledOnDay(_:_:)`` so a
/// monthly habit nudges only on its `dayOfMonth`, not every day of the month. The
/// backend supplies the timezone, the per-policy cadence/target, the completion
/// total for a `[start, end]` day range, and an optional last-delivered instant;
/// the planner owns the day walk, the period math, and the future/met/debounce
/// filters.
public enum HabitReminderOccurrencePlanner {
  /// One enabled policy plus the cadence/target of the habit it nudges.
  public struct PolicyInput: Sendable {
    public var policy: HabitReminderPolicy
    public var cadence: HabitCadence
    public var targetCount: Int64
    /// `last_delivered_at` for this policy from `habit_reminder_delivery_state`, or
    /// `nil` when the period has not been delivered (the in-memory fake, which
    /// has no delivery-state table, always passes `nil`).
    public var lastDeliveredAt: Date?

    public init(
      policy: HabitReminderPolicy, cadence: HabitCadence, targetCount: Int64,
      lastDeliveredAt: Date? = nil
    ) {
      self.policy = policy
      self.cadence = cadence
      self.targetCount = targetCount
      self.lastDeliveredAt = lastDeliveredAt
    }
  }

  /// Expand `inputs` into the occurrences that should fire over the next
  /// `horizonDays` days from `now`, in the supplied `zone`. `progressInRange`
  /// returns the summed completion `value` for a habit over an inclusive
  /// `[startDay, endDay]` range (the backend's only data dependency).
  public static func plan(
    inputs: [PolicyInput],
    now: Date,
    horizonDays: Int,
    zone: TimeZone,
    progressInRange: (_ habitID: String, _ startDay: String, _ endDay: String) throws -> Int64
  ) rethrows -> [DueHabitReminderOccurrence] {
    guard horizonDays > 0 else { return [] }
    var occurrences: [DueHabitReminderOccurrence] = []
    for input in inputs {
      guard input.policy.enabled,
        let (hour, minute) = parseReminderTime(input.policy.reminderTime)
      else { continue }

      for dayOffset in 0..<horizonDays {
        let dayString = Timezone.datePlusDaysYmdForTimezoneName(
          now: now, timezoneName: zone.identifier, offsetDays: dayOffset, systemFallback: zone)
        guard case .success(let ymd) = IsoDate.parseIsoDate(dayString) else { continue }
        let day = LorvexDate(ymd: ymd)
        guard isHabitReminderDay(input.cadence, day) else { continue }
        guard let fireDate = fireInstant(ymd: ymd, hour: hour, minute: minute, zone: zone),
          fireDate > now
        else { continue }

        let required = habitRequiredCompletionsPerPeriod(
          input.cadence, targetCount: input.targetCount)
        let (start, end) = periodBounds(cadence: input.cadence, day: ymd)
        let progress = try progressInRange(input.policy.habitID, start, end)
        guard progress < required else { continue }

        if let lastDelivered = input.lastDeliveredAt,
          deliveredInSamePeriod(cadence: input.cadence, lastDelivered: lastDelivered, day: ymd, zone: zone)
        {
          continue
        }
        occurrences.append(
          DueHabitReminderOccurrence(policy: input.policy, fireDate: fireDate))
      }
    }
    return occurrences
  }

  /// The latest reminder-day occurrence in the CURRENT period (the one
  /// containing `now`) whose fire instant has already elapsed (`fireInstant <=
  /// now`) while the period is still below target — i.e. the most recent firing
  /// the OS has already delivered this period. Returns its instant, or `nil`
  /// when the period is already met or no in-period firing has elapsed yet.
  ///
  /// The inverse of ``plan`` (which walks FUTURE occurrences): the backend
  /// stamps this instant as `habit_reminder_delivery_state.last_delivered_at` so the
  /// same-period debounce in ``plan`` suppresses the rest of the period. The
  /// `progress < required` gate matches ``plan``, so a met period stamps nothing
  /// (no reminder fired, and ``plan`` won't fire one either).
  public static func mostRecentDeliveredOccurrence(
    input: PolicyInput,
    now: Date,
    zone: TimeZone,
    progressInRange: (_ habitID: String, _ startDay: String, _ endDay: String) throws -> Int64
  ) rethrows -> Date? {
    guard input.policy.enabled,
      let (hour, minute) = parseReminderTime(input.policy.reminderTime)
    else { return nil }

    let todayString = Timezone.todayYmdForTimezoneName(
      now: now, timezoneName: zone.identifier, systemFallback: zone)
    guard case .success(let todayYmd) = IsoDate.parseIsoDate(todayString) else { return nil }

    let required = habitRequiredCompletionsPerPeriod(
      input.cadence, targetCount: input.targetCount)
    let (start, end) = periodBounds(cadence: input.cadence, day: todayYmd)
    let progress = try progressInRange(input.policy.habitID, start, end)
    guard progress < required else { return nil }

    guard case .success(let startYmd) = IsoDate.parseIsoDate(start) else { return nil }
    let todayCanonical = todayYmd.canonicalString
    var cursor = startYmd
    var latest: Date? = nil
    // Bounded walk over the period's days (<= 31 for a calendar month).
    for _ in 0..<32 {
      if cursor.canonicalString > todayCanonical { break }
      let day = LorvexDate(ymd: cursor)
      if isHabitReminderDay(input.cadence, day),
        let fire = fireInstant(ymd: cursor, hour: hour, minute: minute, zone: zone),
        fire <= now
      {
        latest = fire
      }
      guard let next = shiftDays(cursor, by: 1) else { break }
      cursor = next
    }
    return latest
  }

  /// Parse a stored `HH:MM` reminder time into `(hour, minute)`, rejecting any
  /// out-of-range or malformed value.
  public static func parseReminderTime(_ raw: String) -> (Int, Int)? {
    let parts = raw.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0...23).contains(hour), (0...59).contains(minute)
    else { return nil }
    return (hour, minute)
  }

  /// Inclusive `[start, end]` day strings for the period containing `day` under
  /// `cadence`: monthly → the calendar month; daily → the single day;
  /// week-bucket cadences → the Monday–Sunday ISO week.
  static func periodBounds(cadence: HabitCadence, day: IsoDate.YMD) -> (String, String) {
    switch cadence {
    case .monthly:
      return monthBounds(day)
    case .daily:
      return (day.canonicalString, day.canonicalString)
    case .weekly, .timesPerWeek:
      return weekBounds(LorvexDate(ymd: day))
    }
  }

  private static func deliveredInSamePeriod(
    cadence: HabitCadence, lastDelivered: Date, day: IsoDate.YMD, zone: TimeZone
  ) -> Bool {
    let deliveredString = Timezone.todayYmdForTimezoneName(
      now: lastDelivered, timezoneName: zone.identifier, systemFallback: zone)
    guard case .success(let deliveredYmd) = IsoDate.parseIsoDate(deliveredString) else {
      return false
    }
    return periodBounds(cadence: cadence, day: deliveredYmd).0
      == periodBounds(cadence: cadence, day: day).0
  }

  private static func monthBounds(_ day: IsoDate.YMD) -> (String, String) {
    let start = IsoDate.YMD(year: day.year, month: day.month, day: 1)
    let nextMonth =
      day.month == 12
      ? IsoDate.YMD(year: day.year + 1, month: 1, day: 1)
      : IsoDate.YMD(year: day.year, month: day.month + 1, day: 1)
    let end = shiftDays(nextMonth, by: -1) ?? nextMonth
    return (start.canonicalString, end.canonicalString)
  }

  private static func weekBounds(_ day: LorvexDate) -> (String, String) {
    let offset = WeekDay.from(date: day).rawValue
    let start = shiftDays(day.ymd, by: -offset) ?? day.ymd
    let end = shiftDays(start, by: 6) ?? start
    return (start.canonicalString, end.canonicalString)
  }

  /// Add `days` to a `YYYY-MM-DD` triple using the UTC proleptic Gregorian
  /// calendar; day arithmetic is timezone-agnostic so this never crosses a DST
  /// boundary in the calendar used for the math.
  private static func shiftDays(_ ymd: IsoDate.YMD, by days: Int) -> IsoDate.YMD? {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = .gmt
    var dc = DateComponents()
    dc.year = ymd.year
    dc.month = ymd.month
    dc.day = ymd.day
    guard let base = cal.date(from: dc),
      let shifted = cal.date(byAdding: .day, value: days, to: base)
    else { return nil }
    let c = cal.dateComponents([.year, .month, .day], from: shifted)
    return IsoDate.YMD(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
  }

  /// The UTC instant of local wall-clock `hour:minute` on `ymd` in `zone`, or
  /// `nil` when that wall time does not exist because it falls in a
  /// spring-forward DST gap (the reminder for a nonexistent local time is
  /// deliberately skipped, not slid to a nearby real instant).
  ///
  /// `Calendar.date(from:)` is lenient: for a gap time such as 02:30 on a day
  /// the clock jumps 02:00 → 03:00 it returns 03:30 (the next real instant)
  /// rather than failing. To honor the skip contract, the result is verified to
  /// round-trip to the requested wall clock in `zone`; a mismatch (the gap case)
  /// yields `nil`. A fall-back repeated time (e.g. 01:30 occurring twice)
  /// round-trips fine and resolves to the earlier of the two instants, the value
  /// `Calendar.date(from:)` returns.
  private static func fireInstant(
    ymd: IsoDate.YMD, hour: Int, minute: Int, zone: TimeZone
  ) -> Date? {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = zone
    var dc = DateComponents()
    dc.year = ymd.year
    dc.month = ymd.month
    dc.day = ymd.day
    dc.hour = hour
    dc.minute = minute
    dc.second = 0
    guard let candidate = cal.date(from: dc) else { return nil }
    let roundTrip = cal.dateComponents([.hour, .minute], from: candidate)
    guard roundTrip.hour == hour, roundTrip.minute == minute else { return nil }
    return candidate
  }
}
