import Foundation
import LorvexCore
import Testing

// How a task's fields read and write in the system's reminder shape. Dates are
// checked in a fixed zone so the expectations hold wherever the suite runs.

private let siriZone = TimeZone(identifier: "America/Los_Angeles")!

private var siriCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = siriZone
  return calendar
}

/// The Gregorian calendar with weeks that start on `firstWeekday` (1 is Sunday).
private func siriCalendar(weekStartingOn firstWeekday: Int) -> Calendar {
  var calendar = siriCalendar
  calendar.firstWeekday = firstWeekday
  return calendar
}

private func siriDay(_ key: String) -> Date {
  LorvexDateFormatters.ymdUTC.date(from: key)!
}

private func siriMoment(
  _ components: DateComponents, now: Date = Date()
) throws -> SiriTaskMapping.Moment {
  try SiriTaskMapping.moment(from: components, now: now, timeZone: siriZone)
}

// MARK: - Date

@Test
func siriDateWithYearMonthDayNamesThatDay() throws {
  // Components without a calendar are counted in the Gregorian one, whatever
  // calendar the device shows.
  let moment = try siriMoment(DateComponents(year: 2026, month: 12, day: 4))
  #expect(moment == .init(day: siriDay("2026-12-04")))
  // A year without a day is the first of the month or of the year.
  #expect(try siriMoment(DateComponents(year: 2028, month: 3)).day == siriDay("2028-03-01"))
  #expect(try siriMoment(DateComponents(year: 2028)).day == siriDay("2028-01-01"))
}

@Test
func siriDateWithClockTimeSetsStartMinutes() throws {
  let moment = try siriMoment(DateComponents(year: 2026, month: 12, day: 4, hour: 15, minute: 30))
  #expect(moment == .init(day: siriDay("2026-12-04"), startMinutes: 15 * 60 + 30))
  // An hour without minutes is the top of that hour.
  let onTheHour = try siriMoment(DateComponents(year: 2026, month: 12, day: 4, hour: 9))
  #expect(onTheHour.startMinutes == 9 * 60)
}

@Test
func siriDateInAnotherZoneIsReadOnTheTaskClock() throws {
  // 01:00 on 5 December in New York is 22:00 on 4 December in Los Angeles.
  let newYork = TimeZone(identifier: "America/New_York")!
  let timed = try siriMoment(
    DateComponents(timeZone: newYork, year: 2026, month: 12, day: 5, hour: 1))
  #expect(timed == .init(day: siriDay("2026-12-04"), startMinutes: 22 * 60))

  // A day without a time keeps its label whatever zone it was written in.
  let tokyo = TimeZone(identifier: "Asia/Tokyo")!
  let dayOnly = try siriMoment(DateComponents(timeZone: tokyo, year: 2026, month: 12, day: 5))
  #expect(dayOnly == .init(day: siriDay("2026-12-05")))
}

@Test
func siriDateCountedInAnotherCalendarNamesTheGregorianDay() throws {
  var buddhist = Calendar(identifier: .buddhist)
  buddhist.timeZone = siriZone
  let moment = try siriMoment(DateComponents(calendar: buddhist, year: 2569, month: 12, day: 4))
  #expect(moment == .init(day: siriDay("2026-12-04")))
}

@Test
func siriClockTimeAloneNamesItsNextOccurrence() throws {
  let now = siriCalendar.date(
    from: DateComponents(year: 2026, month: 12, day: 4, hour: 10))!
  let laterToday = try siriMoment(DateComponents(hour: 15), now: now)
  #expect(laterToday == .init(day: siriDay("2026-12-04"), startMinutes: 15 * 60))
  let tomorrow = try siriMoment(DateComponents(hour: 9, minute: 15), now: now)
  #expect(tomorrow == .init(day: siriDay("2026-12-05"), startMinutes: 9 * 60 + 15))
}

@Test
func siriDayWithoutAYearCanBeToday() throws {
  // 10:00 on Sunday 22 November 2026.
  let now = siriCalendar.date(
    from: DateComponents(year: 2026, month: 11, day: 22, hour: 10))!
  #expect(try siriMoment(DateComponents(month: 11, day: 22), now: now).day == siriDay("2026-11-22"))
  #expect(try siriMoment(DateComponents(day: 22), now: now).day == siriDay("2026-11-22"))
  #expect(try siriMoment(DateComponents(weekday: 1), now: now).day == siriDay("2026-11-22"))
  // A day that has passed this month, and a weekday that is not today, are
  // the next ones.
  #expect(try siriMoment(DateComponents(day: 21), now: now).day == siriDay("2026-12-21"))
  #expect(try siriMoment(DateComponents(weekday: 2), now: now).day == siriDay("2026-11-23"))
}

@Test
func siriTimeTheClocksSkipIsKeptAsWritten() throws {
  // On 14 March 2027 the Los Angeles clock goes from 02:00 to 03:00. A task
  // planned at 02:30 that day reports 02:30, and handing that back names the
  // same time.
  let skipped = SiriTaskMapping.Moment(day: siriDay("2027-03-14"), startMinutes: 150)
  #expect(try siriMoment(SiriTaskMapping.dateComponents(for: skipped)) == skipped)
}

@Test
func siriDateThatCannotBeReadIsRefused() {
  let unreadable = [
    DateComponents(),
    DateComponents(year: 2026, month: 12, day: 4, hour: 24),
    DateComponents(year: 2026, month: 12, day: 4, hour: 9, minute: 60),
  ]
  for components in unreadable {
    #expect(throws: LorvexCoreError.self, "\(components)") {
      _ = try siriMoment(components)
    }
  }
}

@Test
func siriMomentRoundTripsThroughDateComponents() throws {
  for moment in [
    SiriTaskMapping.Moment(day: siriDay("2026-12-04")),
    SiriTaskMapping.Moment(day: siriDay("2027-01-01"), startMinutes: 23 * 60 + 55),
    SiriTaskMapping.Moment(day: siriDay("2026-03-08"), startMinutes: 0),
  ] {
    let components = SiriTaskMapping.dateComponents(for: moment)
    #expect(components.timeZone == nil)
    #expect(try siriMoment(components) == moment)
  }
}

@Test
func siriPlannedTimeKeepsTheStartAndTheKnownLength() {
  let fresh = SiriTaskMapping.plannedTime(startingAt: 540, replacing: nil, estimatedMinutes: nil)
  #expect(fresh == 540..<570)
  let estimated = SiriTaskMapping.plannedTime(startingAt: 540, replacing: nil, estimatedMinutes: 45)
  #expect(estimated == 540..<585)
  let moved = SiriTaskMapping.plannedTime(
    startingAt: 600, replacing: 540..<600, estimatedMinutes: 45)
  #expect(moved == 600..<660)
  // Late in the day the time is cut at midnight; the start does not move.
  let late = SiriTaskMapping.plannedTime(startingAt: 23 * 60 + 50, replacing: nil, estimatedMinutes: 60)
  #expect(late == (23 * 60 + 50)..<(24 * 60))
  let lastMinutes = SiriTaskMapping.plannedTime(
    startingAt: 23 * 60 + 58, replacing: nil, estimatedMinutes: nil)
  #expect(lastMinutes == (23 * 60 + 58)..<(24 * 60))
}

// MARK: - Notes

@Test
func siriLinksJoinTheNotesOnce() {
  let first = URL(string: "https://example.com/a")!
  let second = URL(string: "https://example.com/b")!
  #expect(SiriTaskMapping.notes("", appending: [first]) == "https://example.com/a")
  #expect(
    SiriTaskMapping.notes("Read this", appending: [first, second])
      == "Read this\n\nhttps://example.com/a\n\nhttps://example.com/b")
  // A link the notes already hold is not added again.
  #expect(
    SiriTaskMapping.notes("See https://example.com/a", appending: [first])
      == "See https://example.com/a")
  #expect(SiriTaskMapping.notes("Plain", appending: []) == "Plain")
  // Notes that get no link keep their blank space; notes that get one lose
  // only what is at their end.
  #expect(SiriTaskMapping.notes("    code\n", appending: []) == "    code\n")
  #expect(
    SiriTaskMapping.notes("    code\n\n", appending: [first])
      == "    code\n\nhttps://example.com/a")
}

// MARK: - Repeat rule

@Test
func siriRepeatRuleBecomesATaskRule() throws {
  let calendar = siriCalendar

  let daily = try SiriTaskMapping.taskRecurrence(from: .daily(calendar: calendar))
  #expect(daily == TaskRecurrenceRule(freq: .daily))

  let weekly = try SiriTaskMapping.taskRecurrence(
    from: .weekly(
      calendar: siriCalendar(weekStartingOn: 2), interval: 2,
      weekdays: [.every(.monday), .every(.wednesday)]))
  #expect(weekly == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"]))

  let secondFriday = try SiriTaskMapping.taskRecurrence(
    from: .monthly(calendar: calendar, weekdays: [.nth(2, .friday)]))
  #expect(secondFriday == TaskRecurrenceRule(freq: .monthly, byDay: ["2FR"]))

  let lastSunday = try SiriTaskMapping.taskRecurrence(
    from: .monthly(calendar: calendar, weekdays: [.nth(-1, .sunday)]))
  #expect(lastSunday == TaskRecurrenceRule(freq: .monthly, byDay: ["-1SU"]))

  let monthDay = try SiriTaskMapping.taskRecurrence(
    from: .monthly(calendar: calendar, daysOfTheMonth: [1, 15]))
  #expect(monthDay == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1, 15]))

  let yearly = try SiriTaskMapping.taskRecurrence(
    from: .yearly(calendar: calendar, months: [3], daysOfTheMonth: [3]))
  #expect(yearly == TaskRecurrenceRule(freq: .yearly, byMonth: [3], byMonthDay: [3]))
}

@Test
func siriRepeatRuleEndBecomesCountOrUntil() throws {
  let calendar = siriCalendar
  let counted = try SiriTaskMapping.taskRecurrence(
    from: .daily(calendar: calendar, end: .afterOccurrences(5)), timeZone: siriZone)
  #expect(counted.count == 5)
  #expect(counted.until == nil)

  // 20:00 on 31 December in Los Angeles is already 1 January in UTC; the
  // rule ends on the day the person sees.
  let lastEvening = calendar.date(
    from: DateComponents(year: 2026, month: 12, day: 31, hour: 20))!
  let dated = try SiriTaskMapping.taskRecurrence(
    from: .weekly(calendar: calendar, end: .afterDate(lastEvening)), timeZone: siriZone)
  #expect(dated.until == "2026-12-31")
  #expect(dated.count == nil)
}

@Test
func siriRepeatEveryOtherWeekKeepsWhereTheWeekStarts() throws {
  let days: [Calendar.RecurrenceRule.Weekday] = [.every(.sunday), .every(.monday)]
  // A week that starts on Sunday puts a Sunday and the Monday after it in one
  // week; a week that starts on Monday does not.
  let sundayFirst = try SiriTaskMapping.taskRecurrence(
    from: .weekly(calendar: siriCalendar(weekStartingOn: 1), interval: 2, weekdays: days))
  #expect(sundayFirst == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["SU", "MO"], wkst: "SU"))
  // Monday is the start a task rule has when it names none.
  let mondayFirst = try SiriTaskMapping.taskRecurrence(
    from: .weekly(calendar: siriCalendar(weekStartingOn: 2), interval: 2, weekdays: days))
  #expect(mondayFirst == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["SU", "MO"]))
  #expect(!SiriTaskMapping.repeatsOnSameDays(sundayFirst, mondayFirst))
  // Every week, the start changes nothing and is left out.
  let everyWeek = try SiriTaskMapping.taskRecurrence(
    from: .weekly(calendar: siriCalendar(weekStartingOn: 1), weekdays: days))
  #expect(everyWeek == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO"]))
  #expect(
    SiriTaskMapping.repeatsOnSameDays(
      everyWeek, TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO"], wkst: "SU")))

  // The reported rule's calendar starts the week where the task rule does,
  // so handing it back names the same days.
  for stored in [sundayFirst, mondayFirst] {
    let reported = try #require(SiriTaskMapping.recurrence(for: stored, timeZone: siriZone))
    #expect(reported.calendar.firstWeekday == (stored.wkst == "SU" ? 1 : 2))
    let back = try SiriTaskMapping.taskRecurrence(from: reported, timeZone: siriZone)
    #expect(SiriTaskMapping.repeatsOnSameDays(stored, back), "\(stored)")
  }

  // Sunday 22 November 2026: the Monday of a week that starts on Sunday is
  // the 23rd, and the next Monday in a counted week that starts on Monday is
  // the 30th.
  let sunday = siriDay("2026-11-22")
  #expect(
    SiriTaskMapping.firstOccurrenceDay(
      of: .weekly(
        calendar: siriCalendar(weekStartingOn: 1), interval: 2, weekdays: [.every(.monday)]),
      onOrAfter: sunday) == siriDay("2026-11-23"))
  #expect(
    SiriTaskMapping.firstOccurrenceDay(
      of: .weekly(
        calendar: siriCalendar(weekStartingOn: 2), interval: 2, weekdays: [.every(.monday)]),
      onOrAfter: sunday) == siriDay("2026-11-30"))
}

@Test
func siriRepeatOnADayThatDoesNotExistSkipsIt() throws {
  let calendar = siriCalendar
  // A task rule on the 31st skips the shorter months, so the first due day is
  // never one the stored rule does not land on.
  #expect(
    SiriTaskMapping.firstOccurrenceDay(
      of: .monthly(calendar: calendar, daysOfTheMonth: [31]), onOrAfter: siriDay("2027-02-01"))
      == siriDay("2027-03-31"))
  #expect(
    SiriTaskMapping.firstOccurrenceDay(
      of: .yearly(calendar: calendar, months: [2], daysOfTheMonth: [29]),
      onOrAfter: siriDay("2026-11-22")) == siriDay("2028-02-29"))
  // The reported rule says so too.
  let reported = try #require(
    SiriTaskMapping.recurrence(
      for: TaskRecurrenceRule(freq: .monthly, byMonthDay: [31]), timeZone: siriZone))
  #expect(reported.matchingPolicy == .strict)
}

@Test
func siriRepeatEndDayRoundTripsWhenTheClocksChange() throws {
  // 14 March 2027 is 23 hours long in Los Angeles and 1 November 2026 is 25.
  for until in ["2027-03-14", "2026-11-01", "2030-03-03"] {
    let stored = TaskRecurrenceRule(freq: .daily, until: until)
    let reported = try #require(SiriTaskMapping.recurrence(for: stored, timeZone: siriZone))
    let back = try SiriTaskMapping.taskRecurrence(from: reported, timeZone: siriZone)
    #expect(back.until == until)
  }
}

@Test
func siriRepeatRuleATaskCannotHoldIsRefused() {
  let calendar = siriCalendar
  var twiceADay = Calendar.RecurrenceRule.daily(calendar: calendar)
  twiceADay.hours = [9, 17]
  var byWeekNumber = Calendar.RecurrenceRule.yearly(calendar: calendar)
  byWeekNumber.weeks = [20]
  var hebrew = Calendar(identifier: .hebrew)
  hebrew.timeZone = siriZone
  let refused: [Calendar.RecurrenceRule] = [
    .hourly(calendar: calendar),
    .minutely(calendar: calendar),
    twiceADay,
    byWeekNumber,
    .monthly(calendar: hebrew, daysOfTheMonth: [15]),
    // A week has no "second Friday"; the core's rule check refuses it.
    .weekly(calendar: calendar, weekdays: [.nth(2, .friday)]),
  ]
  for rule in refused {
    #expect(throws: LorvexCoreError.self, "\(rule)") {
      _ = try SiriTaskMapping.taskRecurrence(from: rule, timeZone: siriZone)
    }
  }
}

@Test
func siriRepeatRuleWithOneTimeOfDayKeepsOnlyTheDays() throws {
  var rule = Calendar.RecurrenceRule.daily(calendar: siriCalendar)
  rule.hours = [9]
  rule.minutes = [0]
  #expect(try SiriTaskMapping.taskRecurrence(from: rule) == TaskRecurrenceRule(freq: .daily))
}

@Test
func siriTaskRuleRoundTripsThroughTheSystemRule() throws {
  let rules = [
    TaskRecurrenceRule(freq: .daily),
    TaskRecurrenceRule(freq: .daily, interval: 3, anchor: .completion),
    TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "FR"]),
    TaskRecurrenceRule(freq: .monthly, byDay: ["-1SU"]),
    TaskRecurrenceRule(freq: .monthly, byMonthDay: [15], count: 6),
    TaskRecurrenceRule(freq: .yearly, byMonth: [3], byMonthDay: [3], until: "2030-03-03"),
  ]
  for rule in rules {
    let system = try #require(SiriTaskMapping.recurrence(for: rule, timeZone: siriZone))
    let back = try SiriTaskMapping.taskRecurrence(from: system, timeZone: siriZone)
    #expect(SiriTaskMapping.repeatsOnSameDays(rule, back), "\(rule)")
    // The system rule has no completion anchor, so the way back is a
    // schedule rule; `repeatsOnSameDays` is what tells the two are one repeat.
    #expect(back.anchor == .schedule)
  }
  #expect(
    !SiriTaskMapping.repeatsOnSameDays(
      TaskRecurrenceRule(freq: .daily), TaskRecurrenceRule(freq: .weekly)))
  #expect(SiriTaskMapping.recurrence(for: TaskRecurrenceRule(freq: .weekly, byDay: ["??"])) == nil)
}

@Test
func siriFirstOccurrenceIsTheFirstDayTheRuleLandsOn() {
  let calendar = siriCalendar
  // 22 November 2026 is a Sunday.
  let sunday = siriDay("2026-11-22")
  #expect(
    SiriTaskMapping.firstOccurrenceDay(
      of: .weekly(calendar: calendar, weekdays: [.every(.monday)]), onOrAfter: sunday)
      == siriDay("2026-11-23"))
  #expect(
    SiriTaskMapping.firstOccurrenceDay(of: .daily(calendar: calendar), onOrAfter: sunday)
      == sunday)
  #expect(
    SiriTaskMapping.firstOccurrenceDay(
      of: .monthly(calendar: calendar, daysOfTheMonth: [15]), onOrAfter: sunday)
      == siriDay("2026-12-15"))
  // A time of day and an end in the rule do not move the first day.
  var timed = Calendar.RecurrenceRule.weekly(
    calendar: calendar, end: .afterOccurrences(1), weekdays: [.every(.sunday)])
  timed.hours = [23]
  #expect(SiriTaskMapping.firstOccurrenceDay(of: timed, onOrAfter: sunday) == sunday)
}
