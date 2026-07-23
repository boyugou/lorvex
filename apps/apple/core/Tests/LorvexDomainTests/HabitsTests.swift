import XCTest

@testable import LorvexDomain

final class HabitsTests: XCTestCase {

  private func d(_ s: String) -> LorvexDate {
    guard case let .success(ymd) = IsoDate.parseIsoDate(s) else {
      XCTFail("invalid test date: \(s)")
      return LorvexDate(ymd: IsoDate.YMD(year: 1970, month: 1, day: 1))
    }
    return LorvexDate(ymd: ymd)
  }

  // MARK: validation

  func testValidateHabitCreateDraftSanitizesAndComputesLookupKey() throws {
    let validated = try validateHabitCreateDraft(
      HabitCreateDraft(
        name: "  Morning Pages  ",
        icon: "  M  ",
        color: "  #AABBCC  ",
        cue: "  After coffee  ",
        frequency: .daily,
        targetCount: 0
      ))
    XCTAssertEqual(validated.name, "Morning Pages")
    XCTAssertEqual(validated.icon, "M")
    XCTAssertEqual(validated.color, "#AABBCC")
    XCTAssertEqual(validated.cue, "After coffee")
    XCTAssertEqual(validated.frequency, .daily)
    XCTAssertEqual(validated.targetCount, 1)
    XCTAssertEqual(validated.lookupKey, normalizeLookupKey("Morning Pages"))
  }

  func testValidateHabitCreateDraftOmittedFrequencyDefaultsToDaily() throws {
    let validated = try validateHabitCreateDraft(HabitCreateDraft(name: "Hydrate"))
    XCTAssertEqual(validated.frequency, .daily)
  }

  func testValidateHabitCreateDraftAcceptsEmojiIcon() throws {
    let validated = try validateHabitCreateDraft(
      HabitCreateDraft(name: "Run", icon: "🔥", frequency: .daily))
    XCTAssertEqual(validated.icon, "🔥")
  }

  func testValidateHabitCreateDraftRejectsProseIcon() {
    XCTAssertThrowsError(
      try validateHabitCreateDraft(
        HabitCreateDraft(name: "Run", icon: "ignore previous instructions", frequency: .daily)))
  }

  func testValidateHabitCreateDraftRejectsInvalidColor() {
    XCTAssertThrowsError(
      try validateHabitCreateDraft(
        HabitCreateDraft(name: "Hydrate", color: "red", frequency: .daily))
    ) { error in
      XCTAssertEqual(
        error as? ValidationError,
        .invalidFormat(field: "color", expected: "#RGB or #RRGGBB", actual: "red"))
    }
  }

  func testValidateHabitUpdateDraftNormalizesEmptyOptionalTextToClear() throws {
    let validated = try validateHabitUpdateDraft(
      HabitUpdateDraft(
        color: .set("   "),
        cue: .set("\u{200B}"),
        targetCount: -3
      ))
    XCTAssertEqual(validated.color, .clear)
    XCTAssertEqual(validated.cue, .clear)
    XCTAssertEqual(validated.targetCount, 1)
  }

  // MARK: cadence field bridge

  private func fields(
    _ type: String, weekdays: [WeekDay] = [], perPeriodTarget: Int64 = 1, dayOfMonth: Int? = nil
  ) -> HabitFrequencyFields {
    HabitFrequencyFields(
      frequencyType: type, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
      dayOfMonth: dayOfMonth)
  }

  func testFromFieldsTimesPerWeek() throws {
    let cadence = try HabitCadence.fromFields(fields("times_per_week", perPeriodTarget: 3))
    XCTAssertEqual(cadence, .timesPerWeek(count: 3))
    XCTAssertEqual(habitRequiredCompletionsPerPeriod(cadence, targetCount: 2), 6)
  }

  func testFromFieldsWeeklyDaysSortsAndDedups() throws {
    let cadence = try HabitCadence.fromFields(fields("weekly", weekdays: [.wed, .mon, .wed]))
    XCTAssertEqual(cadence, .weekly(days: [.mon, .wed]))
    XCTAssertEqual(habitRequiredCompletionsPerPeriod(cadence, targetCount: 1), 2)
  }

  func testFromFieldsMonthlyBare() throws {
    let cadence = try HabitCadence.fromFields(fields("monthly"))
    XCTAssertEqual(cadence, .monthly(dayOfMonth: nil))
    XCTAssertEqual(habitRequiredCompletionsPerPeriod(cadence, targetCount: 1), 1)
    XCTAssertTrue(isHabitScheduledOnDay(cadence, d("2026-04-15")))
    XCTAssertFalse(habitUsesWeekBucket(cadence))
  }

  func testFromFieldsMonthlyDayOfMonth() throws {
    let cadence = try HabitCadence.fromFields(fields("monthly", dayOfMonth: 15))
    XCTAssertEqual(cadence, .monthly(dayOfMonth: 15))
    // A completion on any day still counts toward the month bucket …
    XCTAssertTrue(isHabitScheduledOnDay(cadence, d("2026-04-03")))
    // … but the reminder fires only on the configured day.
    XCTAssertTrue(isHabitReminderDay(cadence, d("2026-04-15")))
    XCTAssertFalse(isHabitReminderDay(cadence, d("2026-04-14")))
  }

  func testMonthlyReminderDayClampsToShortMonth() throws {
    let cadence = try HabitCadence.fromFields(fields("monthly", dayOfMonth: 31))
    // February 2026 has 28 days, so day-31 fires on the 28th, not at all otherwise.
    XCTAssertTrue(isHabitReminderDay(cadence, d("2026-02-28")))
    XCTAssertFalse(isHabitReminderDay(cadence, d("2026-02-27")))
    XCTAssertEqual(effectiveMonthlyDay(31, year: 2026, month: 2), 28)
    XCTAssertEqual(effectiveMonthlyDay(31, year: 2026, month: 1), 31)
    XCTAssertEqual(effectiveMonthlyDay(nil, year: 2026, month: 4), 1)
  }

  func testFromFieldsMonthlyIgnoresOutOfRangeDay() throws {
    // A malformed/out-of-range day_of_month degrades to "unspecified" (the 1st).
    let cadence = try HabitCadence.fromFields(fields("monthly", dayOfMonth: 40))
    XCTAssertEqual(cadence, .monthly(dayOfMonth: nil))
  }

  func testReminderDayMatchesScheduleForNonMonthly() throws {
    let weekly = try HabitCadence.fromFields(fields("weekly", weekdays: [.mon, .fri]))
    for date in ["2026-04-06", "2026-04-07", "2026-04-10"].map(d) {
      XCTAssertEqual(isHabitReminderDay(weekly, date), isHabitScheduledOnDay(weekly, date))
    }
  }

  func testScheduleChecksWeekdayMembership() throws {
    let cadence = try HabitCadence.fromFields(fields("weekly", weekdays: [.mon, .fri]))
    XCTAssertTrue(isHabitScheduledOnDay(cadence, d("2026-04-06")))  // Monday
    XCTAssertFalse(isHabitScheduledOnDay(cadence, d("2026-04-07")))  // Tuesday
  }

  func testFromFieldsWeeklyEmptyDaysIsEveryDay() throws {
    // An empty weekday set is the "every day" idiom, not an error.
    let cadence = try HabitCadence.fromFields(fields("weekly", weekdays: []))
    XCTAssertEqual(cadence, .weekly(days: nil))
    XCTAssertTrue(isHabitScheduledOnDay(cadence, d("2026-04-07")))  // any day
  }

  func testStreakPeriodRequirementCountsMetDaysRatherThanCompletionUnits() {
    XCTAssertEqual(habitRequiredMetDaysPerStreakPeriod(.daily), 1)
    XCTAssertEqual(habitRequiredMetDaysPerStreakPeriod(.monthly(dayOfMonth: 15)), 1)
    XCTAssertEqual(habitRequiredMetDaysPerStreakPeriod(.timesPerWeek(count: 3)), 3)
    XCTAssertEqual(habitRequiredMetDaysPerStreakPeriod(.weekly(days: [.mon, .wed])), 2)
    XCTAssertEqual(
      habitRequiredMetDaysPerStreakPeriod(.weekly(days: nil)), 7,
      "weekly-every-day requires all seven independently met days in the week")
    XCTAssertEqual(
      habitRequiredMetDaysPerStreakPeriod(.weekly(days: [])), 7,
      "the empty weekday spelling has the same every-day contract as nil")
  }

  func testFromFieldsTimesPerWeekRejectsNonPositive() {
    XCTAssertThrowsError(
      try HabitCadence.fromFields(fields("times_per_week", perPeriodTarget: 0))
    ) { error in
      XCTAssertTrue("\(error)".contains("per_period_target"))
    }
  }

  // MARK: typed-field round-trip

  func testCadenceToFieldsDaily() {
    let f = HabitCadence.daily.toFields()
    XCTAssertEqual(f.frequencyType, "daily")
    XCTAssertNil(f.weekdays)
    XCTAssertEqual(f.perPeriodTarget, 1)
    XCTAssertNil(f.dayOfMonth)
  }

  func testCadenceToFieldsMonthlyDay() {
    let f = HabitCadence.monthly(dayOfMonth: 15).toFields()
    XCTAssertEqual(f.frequencyType, "monthly")
    XCTAssertEqual(f.dayOfMonth, 15)
  }

  func testCadenceToFieldsWeeklyDays() {
    let f = HabitCadence.weekly(days: [.fri, .mon, .wed]).toFields()
    XCTAssertEqual(f.frequencyType, "weekly")
    XCTAssertEqual(f.weekdays, [.mon, .wed, .fri])
  }

  func testCadenceToFieldsTimesPerWeek() {
    let f = HabitCadence.timesPerWeek(count: 4).toFields()
    XCTAssertEqual(f.frequencyType, "times_per_week")
    XCTAssertEqual(f.perPeriodTarget, 4)
  }

  func testCadenceRoundTripThroughFieldsIsStable() throws {
    let cases: [HabitCadence] = [
      .daily,
      .weekly(days: nil),
      .weekly(days: [.mon, .fri]),
      .monthly(dayOfMonth: nil),
      .monthly(dayOfMonth: 15),
      .timesPerWeek(count: 5),
    ]
    for original in cases {
      let parsed = try HabitCadence.fromFields(original.toFields())
      XCTAssertEqual(parsed, original, "round-trip mismatch for \(original)")
    }
  }

  func testFromFieldsRejectsUnknownFrequencyType() {
    XCTAssertThrowsError(try HabitCadence.fromFields(fields("yearly"))) { error in
      XCTAssertTrue("\(error)".contains("yearly"))
    }
  }

  func testFrequencyTypeVocabularyMatchesSchema() {
    XCTAssertEqual(
      Set(HabitFrequencyType.allCases.map(\.wireString)),
      ["daily", "weekly", "monthly", "times_per_week"])
    XCTAssertNil(HabitFrequencyType.parse("custom"))
  }

  func testWeekdayWireStringRoundTripsThroughParse() {
    for day in WeekDay.allCases {
      XCTAssertEqual(WeekDay.parse(day.wireString), day)
    }
  }

  func testWeekdayConventionIsMondayFirstZeroBased() {
    // The `habit_weekdays.weekday` column stores these raw values verbatim.
    XCTAssertEqual(WeekDay.mon.rawValue, 0)
    XCTAssertEqual(WeekDay.sun.rawValue, 6)
  }

  // MARK: sync payload

  private func habitPayloadFixture(
    frequencyType: String = "weekly", weekdays: [WeekDay] = [.mon, .wed],
    perPeriodTarget: Int64 = 1, dayOfMonth: Int? = nil
  ) -> HabitSyncFields {
    HabitSyncFields(
      id: "habit-1",
      name: "Read",
      icon: "book",
      color: "#112233",
      cue: "After dinner",
      frequencyType: frequencyType,
      weekdays: weekdays,
      perPeriodTarget: perPeriodTarget,
      dayOfMonth: dayOfMonth,
      targetCount: 1,
      archived: false,
      createdAt: "2026-04-01T00:00:00Z",
      updatedAt: "2026-04-02T00:00:00Z",
      version: "0000000000000_0000_a0a0a0a0a0a0a0a0",
      position: 5
    )
  }

  func testHabitSyncPayloadIncludesTypedCadenceShape() {
    let payload = habitSyncPayload(
      habitPayloadFixture(frequencyType: "weekly", weekdays: [.mon, .wed]))
    guard case let .object(map) = payload else {
      XCTFail("expected object payload")
      return
    }
    XCTAssertEqual(map["id"], .string("habit-1"))
    XCTAssertEqual(map["name"], .string("Read"))
    XCTAssertEqual(map["icon"], .string("book"))
    XCTAssertEqual(map["color"], .string("#112233"))
    XCTAssertEqual(map["cue"], .string("After dinner"))
    XCTAssertEqual(map["frequency_type"], .string("weekly"))
    // Weekdays travel INSIDE the payload as Monday-first ints; no frequency_value.
    XCTAssertEqual(map["weekdays"], .array([.int(0), .int(2)]))
    XCTAssertNil(map["frequency_value"])
    XCTAssertEqual(map["per_period_target"], .int(1))
    XCTAssertEqual(map["day_of_month"], .null)
    XCTAssertEqual(map["target_count"], .int(1))
    XCTAssertEqual(map["archived"], .bool(false))
    XCTAssertEqual(map["created_at"], .string("2026-04-01T00:00:00Z"))
    XCTAssertEqual(map["updated_at"], .string("2026-04-02T00:00:00Z"))
    XCTAssertEqual(map["position"], .int(5))
    XCTAssertEqual(map["version"], .string("0000000000000_0000_a0a0a0a0a0a0a0a0"))
  }

  func testHabitSyncPayloadMonthlyCarriesDayOfMonth() {
    let payload = habitSyncPayload(
      habitPayloadFixture(frequencyType: "monthly", weekdays: [], dayOfMonth: 15))
    guard case let .object(map) = payload else {
      XCTFail("expected object payload")
      return
    }
    XCTAssertEqual(map["frequency_type"], .string("monthly"))
    XCTAssertEqual(map["weekdays"], .array([]))
    XCTAssertEqual(map["day_of_month"], .int(15))
  }

  // MARK: streaks

  func testDailyCurrentAllowsTodayOrYesterdayButNotOlder() {
    XCTAssertEqual(
      computeHabitCurrentStreak(
        dates: [d("2026-05-13"), d("2026-05-12"), d("2026-05-11")],
        today: d("2026-05-13"),
        frequency: .daily,
        targetCount: 1),
      3)
    XCTAssertEqual(
      computeHabitCurrentStreak(
        dates: [d("2026-05-12"), d("2026-05-11")],
        today: d("2026-05-13"),
        frequency: .daily,
        targetCount: 1),
      2)
    XCTAssertEqual(
      computeHabitCurrentStreak(
        dates: [d("2026-05-10"), d("2026-05-09")],
        today: d("2026-05-13"),
        frequency: .daily,
        targetCount: 1),
      0)
  }

  func testDailyLongestResetsOnSkippedDays() {
    XCTAssertEqual(
      computeHabitLongestStreak(
        dates: [
          d("2026-05-01"), d("2026-05-02"),
          d("2026-05-04"), d("2026-05-05"), d("2026-05-06"),
        ],
        frequency: .daily,
        targetCount: 1),
      3)
  }

  func testWeeklyCurrentAndLongestUseISOWeekBoundariesAndTargetCount() {
    let dates = [
      d("2025-12-29"),
      d("2026-01-01"),
      d("2026-01-05"),
      d("2026-01-07"),
      d("2026-01-12"),
    ]
    XCTAssertEqual(
      computeHabitCurrentStreak(
        dates: dates, today: d("2026-01-14"), frequency: .weekly, targetCount: 2),
      2)
    XCTAssertEqual(
      computeHabitLongestStreak(dates: dates, frequency: .weekly, targetCount: 2),
      2)
  }

  func testMonthlyCurrentAndLongestUseCalendarMonthsAndTargetCount() {
    let dates = [
      d("2025-12-01"), d("2025-12-15"),
      d("2026-01-03"), d("2026-01-20"),
      d("2026-03-01"), d("2026-03-02"),
    ]
    XCTAssertEqual(
      computeHabitCurrentStreak(
        dates: dates, today: d("2026-03-13"), frequency: .monthly, targetCount: 2),
      1)
    XCTAssertEqual(
      computeHabitLongestStreak(dates: dates, frequency: .monthly, targetCount: 2),
      2)
  }

  // MARK: scheduled-occurrences-due (adherence denominator)

  /// Shift a date by whole days on the shared UTC-proleptic calendar.
  private func shift(_ date: LorvexDate, byDays days: Int) -> LorvexDate {
    LorvexDate(ymd: IsoDate.ymdFromDayNumber(IsoDate.dayNumber(date.ymd) + days))
  }

  /// The Monday that opens `date`'s ISO week (`WeekDay.mon.rawValue == 0`), so a
  /// `mondayOf(x) ... mondayOf(x)+6` range is exactly one ISO week.
  private func mondayOf(_ date: LorvexDate) -> LorvexDate {
    shift(date, byDays: -WeekDay.from(date: date).rawValue)
  }

  /// Daily denominator is the raw day count times the per-day target — the same
  /// value a linear pro-rate produced, so daily adherence is unchanged.
  func testScheduledOccurrencesDailyEqualsDayCountTimesTarget() {
    XCTAssertEqual(
      habitScheduledOccurrencesDue(.daily, targetCount: 1, from: d("2026-06-15"), to: d("2026-06-15")),
      1, accuracy: 1e-9)
    XCTAssertEqual(
      habitScheduledOccurrencesDue(.daily, targetCount: 1, from: d("2026-06-15"), to: d("2026-06-18")),
      4, accuracy: 1e-9)
    // A full 30-day window (today-29 … today) with a per-day target of 2.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(.daily, targetCount: 2, from: d("2026-05-20"), to: d("2026-06-18")),
      60, accuracy: 1e-9)
  }

  /// A pinned-weekday cadence counts only the days whose weekday it pins. A
  /// window that contains no pinned weekday — a habit created on a day it is not
  /// scheduled — has zero due occurrences (the caller reads that as "nothing due
  /// yet", not a spurious fraction).
  func testScheduledOccurrencesWeeklyPinnedCountsOnlyScheduledWeekdays() {
    let from = d("2026-06-15")
    let to = d("2026-06-21")  // seven consecutive days: each weekday once
    let onePin: HabitCadence = .weekly(days: [WeekDay.from(date: d("2026-06-17"))])
    XCTAssertEqual(
      habitScheduledOccurrencesDue(onePin, targetCount: 1, from: from, to: to),
      1, accuracy: 1e-9)
    let twoPins: HabitCadence = .weekly(
      days: [WeekDay.from(date: d("2026-06-17")), WeekDay.from(date: d("2026-06-19"))])
    XCTAssertEqual(
      habitScheduledOccurrencesDue(twoPins, targetCount: 3, from: from, to: to),
      6, accuracy: 1e-9)  // 2 scheduled days × target 3
    // Created on a non-scheduled day: a one-day window pinned to a *different*
    // weekday than that day has zero due occurrences.
    let nonScheduled: HabitCadence = .weekly(days: [WeekDay.from(date: d("2026-06-16"))])
    XCTAssertEqual(
      habitScheduledOccurrencesDue(
        nonScheduled, targetCount: 1, from: d("2026-06-15"), to: d("2026-06-15")),
      0, accuracy: 1e-9)
  }

  /// A weekly cadence with no pinned weekdays ("every day") makes every day due,
  /// like a daily habit.
  func testScheduledOccurrencesWeeklyEveryDayCountsEveryDay() {
    XCTAssertEqual(
      habitScheduledOccurrencesDue(
        .weekly(days: nil), targetCount: 1, from: d("2026-06-15"), to: d("2026-06-19")),
      5, accuracy: 1e-9)
  }

  /// A monthly cadence's due occurrence is the single day-of-month it fires on
  /// (clamped to the month's last day). A window before that day has come round
  /// has zero; a window straddling two months can contain two.
  func testScheduledOccurrencesMonthlyCountsDayOfMonthOccurrences() {
    let monthly15: HabitCadence = .monthly(dayOfMonth: 15)
    // Window containing the 15th → one due occurrence.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(monthly15, targetCount: 1, from: d("2026-06-10"), to: d("2026-06-20")),
      1, accuracy: 1e-9)
    // Window entirely before the 15th → nothing due yet.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(monthly15, targetCount: 1, from: d("2026-06-01"), to: d("2026-06-14")),
      0, accuracy: 1e-9)
    // Straddling two months (window contains both 15ths) → two due occurrences.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(monthly15, targetCount: 1, from: d("2026-02-10"), to: d("2026-03-20")),
      2, accuracy: 1e-9)
    // day_of_month 31 clamps to Feb's last day (28 in 2026), so all of February
    // still yields exactly one due occurrence rather than none.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(
        .monthly(dayOfMonth: 31), targetCount: 1, from: d("2026-02-01"), to: d("2026-02-28")),
      1, accuracy: 1e-9)
  }

  /// A `times_per_week` cadence treats the whole ISO week as the period: every
  /// ISO week the window touches contributes the full quota, so a partially met
  /// young week reads a real fraction (one completion against the full quota)
  /// instead of saturating against a sub-1 linear pro-rate.
  func testScheduledOccurrencesTimesPerWeekCountsFullWeekQuotaPerIsoWeek() {
    // One-day-old habit: a single in-progress ISO week already expects the full
    // quota of 3 — a lone completion is 1/3, never 1/0.43.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(
        .timesPerWeek(count: 3), targetCount: 1, from: d("2026-06-15"), to: d("2026-06-15")),
      3, accuracy: 1e-9)
    let monday = mondayOf(d("2026-06-15"))
    // Exactly one ISO week (Mon…Sun) → one quota.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(
        .timesPerWeek(count: 3), targetCount: 1, from: monday, to: shift(monday, byDays: 6)),
      3, accuracy: 1e-9)
    // Two ISO weeks → two quotas; per-day target multiplies the quota.
    XCTAssertEqual(
      habitScheduledOccurrencesDue(
        .timesPerWeek(count: 2), targetCount: 3, from: monday, to: shift(monday, byDays: 13)),
      12, accuracy: 1e-9)  // 2 weeks × quota 2 × target 3
  }

  /// A reversed range yields zero rather than a negative or wrapped count.
  func testScheduledOccurrencesReversedRangeIsZero() {
    XCTAssertEqual(
      habitScheduledOccurrencesDue(.daily, targetCount: 1, from: d("2026-06-18"), to: d("2026-06-15")),
      0, accuracy: 1e-9)
  }
}
