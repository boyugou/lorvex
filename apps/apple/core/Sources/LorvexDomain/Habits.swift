import Foundation

// MARK: - Frequency type wire tag

/// Closed vocabulary of `habits.frequency_type` wire values
/// (`daily` / `weekly` / `monthly` / `times_per_week`). Matches the schema CHECK
/// constraint on `habits.frequency_type`; the snake_case raw value is the
/// canonical wire form.
///
/// The richer typed primitive is ``HabitCadence``, which carries each cadence's
/// detail (`weekly` weekday set, `monthly` day-of-month, `times_per_week`
/// count) in a dedicated field. `HabitFrequencyType` is the bare rhythm tag.
public enum HabitFrequencyType: String, Sendable, Equatable, Codable, CaseIterable {
  case daily
  case weekly
  case monthly
  case timesPerWeek = "times_per_week"

  /// Stable wire-format token: the canonical `habits.frequency_type` string
  /// (matches the schema CHECK constraint).
  public var wireString: String { rawValue }

  /// Parse a wire-format token. Returns `nil` for any other value so callers
  /// can fall back to a ``ValidationError`` with caller-shaped wording.
  public static func parse(_ value: String) -> HabitFrequencyType? {
    HabitFrequencyType(rawValue: value)
  }
}

// MARK: - WeekDay

/// Three-letter lowercase weekday tag (`mon`..`sun`). Comparable in
/// Monday-first order so `sort()` / `sorted()` yields the canonical
/// Mon..Sun sequence used in cadence JSON payloads.
public enum WeekDay: Int, Sendable, Equatable, Hashable, Comparable, CaseIterable {
  case mon = 0
  case tue = 1
  case wed = 2
  case thu = 3
  case fri = 4
  case sat = 5
  case sun = 6

  public static func < (lhs: WeekDay, rhs: WeekDay) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  /// Parse a three-letter lowercase wire token. Returns `nil` for any other
  /// input.
  public static func parse(_ value: String) -> WeekDay? {
    switch value {
    case "mon": return .mon
    case "tue": return .tue
    case "wed": return .wed
    case "thu": return .thu
    case "fri": return .fri
    case "sat": return .sat
    case "sun": return .sun
    default: return nil
    }
  }

  /// Stable lowercase three-letter wire token. ``parse(_:)`` accepts every
  /// value returned here, so `parse(weekday.wireString) == weekday` holds
  /// for every variant.
  public var wireString: String {
    switch self {
    case .mon: return "mon"
    case .tue: return "tue"
    case .wed: return "wed"
    case .thu: return "thu"
    case .fri: return "fri"
    case .sat: return "sat"
    case .sun: return "sun"
    }
  }

  /// Derive the weekday of a calendar date in the proleptic Gregorian
  /// calendar (Monday-first).
  public static func from(date: LorvexDate) -> WeekDay {
    // LorvexDate exposes year/month/day; derive weekday via the shared UTC
    // gregorian calendar, then map Foundation's Sunday-first weekday below.
    let cal = IsoDate.calendar
    var comps = DateComponents()
    comps.year = date.ymd.year
    comps.month = date.ymd.month
    comps.day = date.ymd.day
    guard let d = cal.date(from: comps) else {
      return .mon
    }
    // Foundation: Sunday = 1, Monday = 2, ..., Saturday = 7
    let wd = cal.component(.weekday, from: d)
    switch wd {
    case 2: return .mon
    case 3: return .tue
    case 4: return .wed
    case 5: return .thu
    case 6: return .fri
    case 7: return .sat
    case 1: return .sun
    default: return .mon
    }
  }
}

// MARK: - HabitCadence

/// Typed representation of a habit's recurrence rule.
///
/// The single source of truth for cadence detail; the schema, sync wire, and
/// DTOs store it as typed columns via ``HabitFrequencyFields``. Bridge with
/// ``HabitCadence/fromFields(_:)`` and ``HabitCadence/toFields()``.
///
/// Variants:
/// - ``daily`` — every day.
/// - ``weekly(days:)`` — weekly cadence. `nil` `days` (or an empty set) means
///   "every day"; a non-empty set pins the specific weekdays.
/// - ``monthly(dayOfMonth:)`` — once per calendar month. `dayOfMonth` (1–31,
///   clamped to the month's last day at use sites) is the day reminders fire
///   on; `nil` leaves it unspecified (reminders fall back to the 1st). A
///   completion on *any* day of the month counts toward the month's target
///   regardless — `dayOfMonth` governs only when the nudge fires, not what
///   counts (see ``isHabitReminderDay(_:_:)`` vs ``isHabitScheduledOnDay(_:_:)``).
/// - ``timesPerWeek(count:)`` — N completions per week with no weekday pinning.
public enum HabitCadence: Sendable, Equatable, Hashable {
  case daily
  case weekly(days: [WeekDay]?)
  case monthly(dayOfMonth: Int?)
  case timesPerWeek(count: Int64)

  /// Bridge the typed column fields (`frequency_type` + `weekdays` +
  /// `per_period_target` + `day_of_month`) into the typed ``HabitCadence`` enum.
  /// Throws ``ValidationError`` on an unsupported `frequencyType` or a
  /// non-positive `per_period_target` for a `times_per_week` cadence.
  public static func fromFields(_ fields: HabitFrequencyFields) throws -> HabitCadence {
    guard let type = HabitFrequencyType(rawValue: fields.frequencyType) else {
      throw ValidationError.message("unsupported frequency_type '\(fields.frequencyType)'")
    }
    switch type {
    case .daily:
      return .daily
    case .weekly:
      return .weekly(days: normalizeWeekdays(fields.weekdays))
    case .monthly:
      return .monthly(dayOfMonth: normalizeDayOfMonth(fields.dayOfMonth))
    case .timesPerWeek:
      guard fields.perPeriodTarget > 0 else {
        throw ValidationError.message("per_period_target must be positive for times_per_week")
      }
      return .timesPerWeek(count: fields.perPeriodTarget)
    }
  }

  /// Render the cadence into its typed column fields.
  ///
  /// Invariants:
  /// - ``daily`` → type `daily`, no detail (weekdays nil, perPeriodTarget 1,
  ///   dayOfMonth nil).
  /// - ``weekly`` with `days == nil`/empty → type `weekly`, weekdays nil ("every
  ///   day"); with a non-empty set → weekdays sorted+deduped Mon..Sun.
  /// - ``monthly`` → type `monthly`, dayOfMonth carried through (nil allowed).
  /// - ``timesPerWeek`` → type `times_per_week`, perPeriodTarget = count.
  public func toFields() -> HabitFrequencyFields {
    switch self {
    case .daily:
      return HabitFrequencyFields(frequencyType: HabitFrequencyType.daily.rawValue)
    case let .weekly(days):
      return HabitFrequencyFields(
        frequencyType: HabitFrequencyType.weekly.rawValue, weekdays: normalizeWeekdays(days))
    case let .monthly(dayOfMonth):
      return HabitFrequencyFields(
        frequencyType: HabitFrequencyType.monthly.rawValue,
        dayOfMonth: normalizeDayOfMonth(dayOfMonth))
    case let .timesPerWeek(count):
      return HabitFrequencyFields(
        frequencyType: HabitFrequencyType.timesPerWeek.rawValue, perPeriodTarget: max(count, 1))
    }
  }

  /// The weekday set a `weekly` cadence pins, sorted Mon..Sun; `nil` for every
  /// other cadence and for weekly-every-day. The materialized `habit_weekdays`
  /// child rows are exactly this set.
  public var weekdays: [WeekDay]? {
    if case let .weekly(days) = self { return normalizeWeekdays(days) }
    return nil
  }
}

/// Sort ascending (Mon..Sun) and drop duplicates; an empty/`nil` input maps to
/// `nil` (the "every day" idiom for a weekly cadence).
private func normalizeWeekdays(_ days: [WeekDay]?) -> [WeekDay]? {
  guard let days, !days.isEmpty else { return nil }
  var deduped: [WeekDay] = []
  for d in days.sorted() where deduped.last != d {
    deduped.append(d)
  }
  return deduped.isEmpty ? nil : deduped
}

/// Clamp a `day_of_month` to `1...31`, mapping anything outside that range (or
/// `nil`) to `nil` ("unspecified"). Lenient so a malformed value degrades
/// rather than blocking the habit from loading.
private func normalizeDayOfMonth(_ day: Int?) -> Int? {
  guard let day, (1...31).contains(day) else { return nil }
  return day
}

/// Typed carrier for a habit's cadence columns — the storage / wire shape of
/// ``HabitCadence``. Reflects the `habits` schema columns: `frequency_type`
/// selects the rhythm; `weekdays` materializes into the `habit_weekdays` child
/// (weekly only); `perPeriodTarget` is the N for `times_per_week`; `dayOfMonth`
/// is the monthly reminder day. Produced by
/// ``HabitCadence/toFields()``; consumed by ``HabitCadence/fromFields(_:)``.
public struct HabitFrequencyFields: Sendable, Equatable, Hashable {
  public var frequencyType: String
  public var weekdays: [WeekDay]?
  public var perPeriodTarget: Int64
  public var dayOfMonth: Int?

  public init(
    frequencyType: String,
    weekdays: [WeekDay]? = nil,
    perPeriodTarget: Int64 = 1,
    dayOfMonth: Int? = nil
  ) {
    self.frequencyType = frequencyType
    self.weekdays = weekdays
    self.perPeriodTarget = perPeriodTarget
    self.dayOfMonth = dayOfMonth
  }
}

// MARK: - Archive action

/// Tri-state archive intent for a habit update patch. ``noChange`` leaves
/// the existing flag alone; ``archive`` / ``unarchive`` set it explicitly.
public enum ArchiveAction: Sendable, Equatable, Hashable {
  case noChange
  case archive
  case unarchive

  /// Build from the `Optional<Bool>` shape that clap / serde produce at the
  /// MCP / CLI boundary. `nil → noChange`, `true → archive`, `false →
  /// unarchive`.
  public static func fromOptionalBool(_ value: Bool?) -> ArchiveAction {
    switch value {
    case .none: return .noChange
    case .some(true): return .archive
    case .some(false): return .unarchive
    }
  }

  /// The resulting `archived` boolean when the patch carries a change, or
  /// `nil` when it leaves the flag alone.
  public var targetValue: Bool? {
    switch self {
    case .noChange: return nil
    case .archive: return true
    case .unarchive: return false
    }
  }

  /// True iff the patch carries an archive change of any kind.
  public var isPresent: Bool {
    self != .noChange
  }
}

// MARK: - Drafts

/// Boundary draft for `create_habit` callers. ``frequency`` is the typed
/// cadence; a `nil` value defaults to ``HabitCadence/daily`` after
/// validation.
public struct HabitCreateDraft: Sendable, Equatable {
  public var name: String
  public var icon: String?
  public var color: String?
  public var cue: String?
  public var frequency: HabitCadence?
  public var targetCount: Int64?

  public init(
    name: String,
    icon: String? = nil,
    color: String? = nil,
    cue: String? = nil,
    frequency: HabitCadence? = nil,
    targetCount: Int64? = nil
  ) {
    self.name = name
    self.icon = icon
    self.color = color
    self.cue = cue
    self.frequency = frequency
    self.targetCount = targetCount
  }
}

/// Boundary draft for `update_habit` patches.
///
/// - ``name`` / ``targetCount`` use `Optional` — `nil` means leave alone.
/// - ``icon`` / ``color`` / ``cue`` use ``Patch`` — distinguishes
///   "unset / clear / set" for the three nullable text fields.
/// - ``frequency`` replaces the entire cadence atomically when non-nil.
/// - ``archived`` is the tri-state ``ArchiveAction``.
public struct HabitUpdateDraft: Sendable, Equatable {
  public var name: String?
  public var icon: Patch<String>
  public var color: Patch<String>
  public var cue: Patch<String>
  public var frequency: HabitCadence?
  public var targetCount: Int64?
  public var archived: ArchiveAction

  public init(
    name: String? = nil,
    icon: Patch<String> = .unset,
    color: Patch<String> = .unset,
    cue: Patch<String> = .unset,
    frequency: HabitCadence? = nil,
    targetCount: Int64? = nil,
    archived: ArchiveAction = .noChange
  ) {
    self.name = name
    self.icon = icon
    self.color = color
    self.cue = cue
    self.frequency = frequency
    self.targetCount = targetCount
    self.archived = archived
  }
}

// MARK: - Progress / scheduling

/// Whether a habit is tracked as a single yes/no completion per period
/// (``binary``) or as an accumulating numeric count (``accumulative``).
/// The snake_case `rawValue` is the canonical wire form for MCP responses and
/// platform surfaces.
public enum HabitProgressKind: String, Sendable, Equatable, Codable, CaseIterable {
  case binary
  case accumulative
}

public func habitProgressKind(targetCount: Int64) -> HabitProgressKind {
  if max(targetCount, 1) > 1 { return .accumulative }
  return .binary
}

/// True iff a habit with `cadence` is "scheduled" on `date` — i.e. a
/// completion on that day counts toward the period bucket.
///
/// A `weekly` cadence with no pinned weekdays (nil or an empty set) is treated
/// as "every day" so the habit surfaces rather than silently never firing.
public func isHabitScheduledOnDay(_ cadence: HabitCadence, _ date: LorvexDate) -> Bool {
  switch cadence {
  case .daily, .monthly:
    return true
  case let .weekly(days):
    guard let configured = days, !configured.isEmpty else { return true }
    return configured.contains(WeekDay.from(date: date))
  case let .timesPerWeek(count):
    return count > 0
  }
}

/// True iff a habit's *reminders* should fire on `date`.
///
/// Identical to ``isHabitScheduledOnDay(_:_:)`` for every cadence except
/// ``HabitCadence/monthly(dayOfMonth:)``. A monthly habit is "scheduled" every
/// day (a completion on any day counts toward the month's target), but its
/// reminder fires on exactly one day — the configured `dayOfMonth`, clamped to
/// the month's last day, defaulting to the 1st. Reminder scheduling must gate
/// on this rather than ``isHabitScheduledOnDay(_:_:)`` or a monthly reminder
/// would fire every day until the month's target was met.
public func isHabitReminderDay(_ cadence: HabitCadence, _ date: LorvexDate) -> Bool {
  switch cadence {
  case let .monthly(dayOfMonth):
    return date.ymd.day
      == effectiveMonthlyDay(dayOfMonth, year: date.ymd.year, month: date.ymd.month)
  default:
    return isHabitScheduledOnDay(cadence, date)
  }
}

/// The day-of-month a monthly habit's reminder fires on for a given month: the
/// configured `dayOfMonth` (defaulting to 1) clamped down to the month's last
/// day, so a habit set to day 31 fires on Feb 28/29, Apr 30, and so on.
public func effectiveMonthlyDay(_ dayOfMonth: Int?, year: Int, month: Int) -> Int {
  let requested = max(dayOfMonth ?? 1, 1)
  return min(requested, daysInGregorianMonth(year: year, month: month))
}

private func daysInGregorianMonth(year: Int, month: Int) -> Int {
  let cal = IsoDate.calendar
  var comps = DateComponents()
  comps.year = year
  comps.month = month
  comps.day = 1
  guard let date = cal.date(from: comps),
    let range = cal.range(of: .day, in: .month, for: date)
  else { return 31 }
  return range.count
}

public func habitRequiredCompletionsPerPeriod(
  _ cadence: HabitCadence, targetCount: Int64
) -> Int64 {
  let targetCount = max(targetCount, 1)
  let scheduledSlots: Int64
  switch cadence {
  case .daily, .monthly:
    scheduledSlots = 1
  case let .weekly(days):
    scheduledSlots = max(Int64(days?.count ?? 1), 1)
  case let .timesPerWeek(count):
    scheduledSlots = max(count, 1)
  }
  return scheduledSlots * targetCount
}

/// Number of independently met calendar dates required for one streak period.
/// A date reaches this projection only after its stored completion value meets
/// the habit's per-day target, so `targetCount` must not be multiplied into this
/// requirement a second time. Weekly-every-day has seven scheduled dates; a
/// pinned week uses its normalized weekday count; `times_per_week` uses its N.
public func habitRequiredMetDaysPerStreakPeriod(_ cadence: HabitCadence) -> Int64 {
  switch cadence {
  case .daily, .monthly:
    return 1
  case .weekly:
    return Int64(cadence.weekdays?.count ?? WeekDay.allCases.count)
  case let .timesPerWeek(count):
    return max(count, 1)
  }
}

/// The number of completions a cadence's schedule genuinely *expects* over the
/// inclusive day range `from...to` — the adherence denominator.
///
/// Counts the scheduled occurrences that have actually come DUE inside the
/// window, respecting *which* days each cadence pins, instead of pro-rating a
/// per-period quota linearly across the raw day count. Pro-rating a young
/// non-daily habit against a fractional expectation (a `times_per_week(3)`
/// habit's `3 × 1/7 ≈ 0.43`) lets a single completion saturate the ratio to
/// 100%, or reads a spurious fraction on a pinned habit created on a day it is
/// not scheduled; counting due occurrences avoids both.
///
/// Each due occurrence expects `max(targetCount, 1)` completions. Per cadence:
/// - ``daily`` — every day in the range is due, giving `dayCount × targetCount`
///   (identical to a linear daily pro-rate: daily behavior is unchanged).
/// - ``weekly`` — each day whose weekday the cadence pins is one due occurrence;
///   a `nil`/empty weekday set ("every day") makes every day due. A window that
///   contains no pinned weekday has **zero** due occurrences — the caller reads
///   that as "nothing due yet", not a fraction.
/// - ``monthly`` — the one day-of-month the habit fires on
///   (``effectiveMonthlyDay(_:year:month:)``, clamped to the month's last day) is
///   the due occurrence, matched by ``isHabitReminderDay(_:_:)``. A window before
///   that day has come round has zero; a 30-day window straddling two months can
///   legitimately contain two due occurrences.
/// - ``timesPerWeek`` — the whole ISO week is the period: every ISO week the
///   window touches contributes the full `count` quota, so the current
///   (in-progress) week's quota is in play from its first day. A partially met
///   young week therefore reads a real fraction (1 of 3 → ⅓) rather than a
///   saturated 100%.
///
/// `from` and `to` are inclusive; a reversed range (`from > to`) yields 0.
public func habitScheduledOccurrencesDue(
  _ cadence: HabitCadence, targetCount: Int64, from: LorvexDate, to: LorvexDate
) -> Double {
  let perOccurrence = Double(max(targetCount, 1))
  let fromDay = IsoDate.dayNumber(from.ymd)
  let toDay = IsoDate.dayNumber(to.ymd)
  guard fromDay <= toDay else { return 0 }

  switch cadence {
  case let .timesPerWeek(count):
    var weeks: Set<ISOWeekKey> = []
    var day = fromDay
    while day <= toDay {
      weeks.insert(isoWeekKey(LorvexDate(ymd: IsoDate.ymdFromDayNumber(day))))
      day += 1
    }
    return Double(max(count, 1)) * perOccurrence * Double(weeks.count)
  case .daily, .weekly, .monthly:
    var dueDays = 0
    var day = fromDay
    while day <= toDay {
      if isHabitReminderDay(cadence, LorvexDate(ymd: IsoDate.ymdFromDayNumber(day))) {
        dueDays += 1
      }
      day += 1
    }
    return Double(dueDays) * perOccurrence
  }
}

public func habitUsesWeekBucket(_ cadence: HabitCadence) -> Bool {
  switch cadence {
  case .daily, .monthly: return false
  default: return true
  }
}

// MARK: - Streaks

public enum HabitStreakFrequency: Sendable, Equatable, Hashable {
  case daily
  case weekly
  case monthly

  /// `"daily" → daily`, `"monthly" → monthly`, everything else (including
  /// `"weekly"` and `"times_per_week"`) → ``weekly`` (the week-bucket branch).
  public static func fromWireString(_ value: String) -> HabitStreakFrequency {
    switch value {
    case "daily": return .daily
    case "monthly": return .monthly
    default: return .weekly
    }
  }
}

public func computeHabitCurrentStreak(
  dates: [LorvexDate], today: LorvexDate,
  frequency: HabitStreakFrequency, targetCount: Int64
) -> Int64 {
  switch frequency {
  case .daily:
    let sorted = dates.sorted(by: >)
    return dailyCurrentStreak(sorted, today: today)
  case .weekly:
    return weeklyCurrentStreak(dates, today: today, targetCount: targetCount)
  case .monthly:
    return monthlyCurrentStreak(dates, today: today, targetCount: targetCount)
  }
}

public func computeHabitLongestStreak(
  dates: [LorvexDate], frequency: HabitStreakFrequency, targetCount: Int64
) -> Int64 {
  let sorted = dates.sorted(by: <)
  switch frequency {
  case .daily: return dailyLongestStreak(sorted)
  case .weekly: return weeklyLongestStreak(sorted, targetCount: targetCount)
  case .monthly: return monthlyLongestStreak(sorted, targetCount: targetCount)
  }
}

private func dailyCurrentStreak(_ datesDesc: [LorvexDate], today: LorvexDate) -> Int64 {
  guard !datesDesc.isEmpty else { return 0 }
  let daysSince = daysBetween(from: datesDesc[0], to: today)
  if daysSince > 1 { return 0 }
  var streak: Int64 = 1
  var i = 1
  while i < datesDesc.count {
    if daysBetween(from: datesDesc[i], to: datesDesc[i - 1]) == 1 {
      streak += 1
    } else {
      break
    }
    i += 1
  }
  return streak
}

private func dailyLongestStreak(_ datesAsc: [LorvexDate]) -> Int64 {
  guard !datesAsc.isEmpty else { return 0 }
  var longest: Int64 = 1
  var current: Int64 = 1
  for i in 1..<datesAsc.count {
    if daysBetween(from: datesAsc[i - 1], to: datesAsc[i]) == 1 {
      current += 1
      longest = max(longest, current)
    } else {
      current = 1
    }
  }
  return longest
}

private func weeklyCurrentStreak(
  _ dates: [LorvexDate], today: LorvexDate, targetCount: Int64
) -> Int64 {
  guard !dates.isEmpty else { return 0 }
  var weekCounts: [ISOWeekKey: Int64] = [:]
  for d in dates {
    let k = isoWeekKey(d)
    weekCounts[k, default: 0] += 1
  }
  let target = max(targetCount, 1)
  let todayWeek = isoWeekKey(today)
  let currentWeekCount = weekCounts[todayWeek] ?? 0
  var streak: Int64 = currentWeekCount >= target ? 1 : 0

  var cursor = addDays(isoWeekStart(year: todayWeek.year, week: todayWeek.week), -1)
  while true {
    let week = isoWeekKey(cursor)
    let count = weekCounts[week] ?? 0
    if count < target { break }
    streak += 1
    cursor = addDays(isoWeekStart(year: week.year, week: week.week), -1)
    if streak > 10_000 { break }
  }
  return streak
}

private func weeklyLongestStreak(
  _ datesAsc: [LorvexDate], targetCount: Int64
) -> Int64 {
  guard !datesAsc.isEmpty else { return 0 }
  var weekCounts: [ISOWeekKey: Int64] = [:]
  for d in datesAsc {
    let k = isoWeekKey(d)
    weekCounts[k, default: 0] += 1
  }
  let target = max(targetCount, 1)
  var longest: Int64 = 0
  var current: Int64 = 0
  var prevKey: ISOWeekKey? = nil

  // Iterate in ascending sorted order over week keys.
  let orderedKeys = weekCounts.keys.sorted { (lhs, rhs) in
    if lhs.year != rhs.year { return lhs.year < rhs.year }
    return lhs.week < rhs.week
  }
  for key in orderedKeys {
    let count = weekCounts[key]!
    let isConsecutive: Bool
    if let prev = prevKey {
      let prevStart = isoWeekStart(year: prev.year, week: prev.week)
      let thisStart = isoWeekStart(year: key.year, week: key.week)
      isConsecutive = daysBetween(from: prevStart, to: thisStart) == 7
    } else {
      isConsecutive = false
    }
    if count >= target {
      current = isConsecutive ? current + 1 : 1
      longest = max(longest, current)
    } else {
      current = 0
    }
    prevKey = key
  }
  return longest
}

private func monthlyCurrentStreak(
  _ dates: [LorvexDate], today: LorvexDate, targetCount: Int64
) -> Int64 {
  guard !dates.isEmpty else { return 0 }
  var monthCounts: [MonthKey: Int64] = [:]
  for d in dates {
    monthCounts[MonthKey(year: d.ymd.year, month: d.ymd.month), default: 0] += 1
  }
  let target = max(targetCount, 1)
  let todayKey = MonthKey(year: today.ymd.year, month: today.ymd.month)
  let currentMonthCount = monthCounts[todayKey] ?? 0
  var streak: Int64 = currentMonthCount >= target ? 1 : 0
  var cursor = prevMonth(todayKey)
  while true {
    let count = monthCounts[cursor] ?? 0
    if count < target { break }
    streak += 1
    cursor = prevMonth(cursor)
    if streak > 10_000 { break }
  }
  return streak
}

private func monthlyLongestStreak(
  _ datesAsc: [LorvexDate], targetCount: Int64
) -> Int64 {
  guard !datesAsc.isEmpty else { return 0 }
  var monthCounts: [MonthKey: Int64] = [:]
  for d in datesAsc {
    monthCounts[MonthKey(year: d.ymd.year, month: d.ymd.month), default: 0] += 1
  }
  let target = max(targetCount, 1)
  var longest: Int64 = 0
  var current: Int64 = 0
  var prevKey: MonthKey? = nil
  let orderedKeys = monthCounts.keys.sorted { (lhs, rhs) in
    if lhs.year != rhs.year { return lhs.year < rhs.year }
    return lhs.month < rhs.month
  }
  for key in orderedKeys {
    let count = monthCounts[key]!
    let isConsecutive: Bool
    if let prev = prevKey {
      isConsecutive = nextMonth(prev) == key
    } else {
      isConsecutive = false
    }
    if count >= target {
      current = isConsecutive ? current + 1 : 1
      longest = max(longest, current)
    } else {
      current = 0
    }
    prevKey = key
  }
  return longest
}

private struct MonthKey: Hashable {
  let year: Int
  let month: Int
}

private func prevMonth(_ k: MonthKey) -> MonthKey {
  if k.month == 1 { return MonthKey(year: k.year - 1, month: 12) }
  return MonthKey(year: k.year, month: k.month - 1)
}

private func nextMonth(_ k: MonthKey) -> MonthKey {
  if k.month == 12 { return MonthKey(year: k.year + 1, month: 1) }
  return MonthKey(year: k.year, month: k.month + 1)
}

// MARK: - ISO week helpers

private struct ISOWeekKey: Hashable {
  let year: Int
  let week: Int
}

private func gregorianCalendarUTC() -> Foundation.Calendar {
  var cal = Foundation.Calendar(identifier: .iso8601)
  cal.timeZone = TimeZone(identifier: "UTC")!
  cal.locale = Locale(identifier: "en_US_POSIX")
  cal.firstWeekday = 2  // Monday
  cal.minimumDaysInFirstWeek = 4  // ISO 8601
  return cal
}

private func dateFromLorvex(_ d: LorvexDate) -> Date {
  let cal = gregorianCalendarUTC()
  var comps = DateComponents()
  comps.year = d.ymd.year
  comps.month = d.ymd.month
  comps.day = d.ymd.day
  return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
}

private func lorvexFromDate(_ date: Date) -> LorvexDate {
  let cal = gregorianCalendarUTC()
  let comps = cal.dateComponents([.year, .month, .day], from: date)
  let ymd = IsoDate.YMD(
    year: comps.year ?? 1970,
    month: comps.month ?? 1,
    day: comps.day ?? 1)
  return LorvexDate(ymd: ymd)
}

private func daysBetween(from: LorvexDate, to: LorvexDate) -> Int {
  let cal = gregorianCalendarUTC()
  let a = dateFromLorvex(from)
  let b = dateFromLorvex(to)
  let comps = cal.dateComponents([.day], from: a, to: b)
  return comps.day ?? 0
}

private func addDays(_ d: LorvexDate, _ delta: Int) -> LorvexDate {
  let cal = gregorianCalendarUTC()
  let date = cal.date(byAdding: .day, value: delta, to: dateFromLorvex(d))
    ?? dateFromLorvex(d)
  return lorvexFromDate(date)
}

private func isoWeekKey(_ d: LorvexDate) -> ISOWeekKey {
  let cal = gregorianCalendarUTC()
  let date = dateFromLorvex(d)
  let year = cal.component(.yearForWeekOfYear, from: date)
  let week = cal.component(.weekOfYear, from: date)
  return ISOWeekKey(year: year, week: week)
}

private func isoWeekStart(year: Int, week: Int) -> LorvexDate {
  let cal = gregorianCalendarUTC()
  var comps = DateComponents()
  comps.yearForWeekOfYear = year
  comps.weekOfYear = week
  comps.weekday = 2  // Monday (Foundation: Sunday = 1)
  if let date = cal.date(from: comps) {
    return lorvexFromDate(date)
  }
  return LorvexDate(ymd: IsoDate.YMD(year: year, month: 1, day: 1))
}

// MARK: - Sync payload

/// Stable JSON shape used for habit sync upsert and delete payloads.
///
/// Cadence rides as typed fields, not a JSON-in-TEXT blob: `frequency_type` +
/// `perPeriodTarget` + `dayOfMonth` mirror the `habits` columns,
/// and `weekdays` (Monday-first 0=Mon … 6=Sun) carries the `weekly` set INSIDE
/// the habit payload so the applier can rebuild the `habit_weekdays` child.
/// `milestoneTarget` is the optional user-set milestone goal (nil when unset).
public struct HabitSyncFields: Sendable, Equatable {
  public var id: String
  public var name: String
  public var icon: String?
  public var color: String?
  public var cue: String?
  public var frequencyType: String
  public var weekdays: [WeekDay]
  public var perPeriodTarget: Int64
  public var dayOfMonth: Int?
  public var targetCount: Int64
  public var milestoneTarget: Int?
  public var archived: Bool
  public var createdAt: String
  public var updatedAt: String
  public var version: String
  /// Synced manual display order (ascending). Defaults to 0 until the habit is
  /// explicitly reordered.
  public var position: Int64

  public init(
    id: String, name: String, icon: String?, color: String?, cue: String?,
    frequencyType: String, weekdays: [WeekDay] = [], perPeriodTarget: Int64 = 1,
    dayOfMonth: Int? = nil, targetCount: Int64, milestoneTarget: Int? = nil,
    archived: Bool, createdAt: String, updatedAt: String, version: String,
    position: Int64 = 0
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    self.color = color
    self.cue = cue
    self.frequencyType = frequencyType
    self.weekdays = weekdays
    self.perPeriodTarget = perPeriodTarget
    self.dayOfMonth = dayOfMonth
    self.targetCount = targetCount
    self.milestoneTarget = milestoneTarget
    self.archived = archived
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.version = version
    self.position = position
  }
}

/// Build the sync payload JSON for a habit upsert/delete. Field insertion order
/// is a stable wire contract, so the resulting object's key sequence must stay
/// byte-identical across surfaces. `weekdays` is
/// always an array (empty when the cadence pins no specific days); the
/// integers are Monday-first (0=Mon … 6=Sun).
public func habitSyncPayload(_ fields: HabitSyncFields) -> JSONValue {
  return .object([
    "id": .string(fields.id),
    "name": .string(fields.name),
    "icon": fields.icon.map(JSONValue.string) ?? .null,
    "color": fields.color.map(JSONValue.string) ?? .null,
    "cue": fields.cue.map(JSONValue.string) ?? .null,
    "frequency_type": .string(fields.frequencyType),
    "weekdays": .array(fields.weekdays.map { .int(Int64($0.rawValue)) }),
    "per_period_target": .int(fields.perPeriodTarget),
    "day_of_month": fields.dayOfMonth.map { .int(Int64($0)) } ?? .null,
    "target_count": .int(fields.targetCount),
    "milestone_target": fields.milestoneTarget.map { .int(Int64($0)) } ?? .null,
    "archived": .bool(fields.archived),
    "created_at": .string(fields.createdAt),
    "updated_at": .string(fields.updatedAt),
    "position": .int(fields.position),
    "version": .string(fields.version),
  ])
}
