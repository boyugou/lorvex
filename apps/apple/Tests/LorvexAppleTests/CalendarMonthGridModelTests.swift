import Foundation
import LorvexCore
import Testing

// MARK: - gridRange: leading days, week count, first-weekday variants

@Test
func calendarMonthGridRangeAddsNoLeadingDaysWhenMonthStartsOnFirstWeekday() throws {
  // January 1, 2023 was a Sunday. With a Sunday-first calendar, the grid
  // should start exactly on the 1st — no leading days from December.
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2023, month: 1, day: 15)))

  let range = CalendarMonthGridModel.gridRange(forMonthContaining: monthAnchor, calendar: calendar)

  let jan1 = try #require(calendar.date(from: DateComponents(year: 2023, month: 1, day: 1)))
  #expect(calendar.isDate(range.start, inSameDayAs: jan1))
  // 31-day month with no leading days needs 5 rows (31 -> ceil(31/7) = 5).
  #expect(range.dayCount == 35)
}

@Test
func calendarMonthGridRangeLeadingDaysShiftWithFirstWeekday() throws {
  // January 1, 2024 was a Monday. A Monday-first calendar needs no leading
  // days; a Sunday-first calendar needs exactly one (December 31).
  var mondayFirst = Calendar(identifier: .gregorian)
  mondayFirst.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  mondayFirst.firstWeekday = 2
  var sundayFirst = mondayFirst
  sundayFirst.firstWeekday = 1
  let monthAnchor = try #require(
    mondayFirst.date(from: DateComponents(year: 2024, month: 1, day: 15)))

  let mondayRange = CalendarMonthGridModel.gridRange(
    forMonthContaining: monthAnchor, calendar: mondayFirst)
  let sundayRange = CalendarMonthGridModel.gridRange(
    forMonthContaining: monthAnchor, calendar: sundayFirst)

  let jan1 = try #require(mondayFirst.date(from: DateComponents(year: 2024, month: 1, day: 1)))
  let dec31 = try #require(mondayFirst.date(from: DateComponents(year: 2023, month: 12, day: 31)))
  #expect(mondayFirst.isDate(mondayRange.start, inSameDayAs: jan1))
  #expect(mondayFirst.isDate(sundayRange.start, inSameDayAs: dec31))
  #expect(mondayRange.dayCount == 35)
  #expect(sundayRange.dayCount == 35)
}

@Test
func calendarMonthGridRangeSpansSixWeeksWhenLeadingDaysPushPastFiveRows() throws {
  // January 1, 2023 was a Sunday (weekday 1). A Tuesday-first (firstWeekday
  // 3) calendar pushes 5 leading days (Dec 27-31) in front of the 31-day
  // month, totalling 36 days -> 6 rows, not 5.
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 3
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2023, month: 1, day: 15)))

  let range = CalendarMonthGridModel.gridRange(forMonthContaining: monthAnchor, calendar: calendar)

  let dec27 = try #require(calendar.date(from: DateComponents(year: 2022, month: 12, day: 27)))
  #expect(calendar.isDate(range.start, inSameDayAs: dec27))
  #expect(range.dayCount == 42)
}

// MARK: - buildDays: leading/trailing fill, isCurrentMonth, event/task placement

@Test
func calendarMonthGridBuildDaysFillsLeadingAndTrailingDaysAcrossMonthBoundaries() throws {
  // February 2024 (leap year, 29 days) starts on a Thursday. A Sunday-first
  // calendar needs 4 leading January days and 2 trailing March days to reach
  // a whole 5-row (35-day) grid.
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [],
    tasks: [],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  #expect(days.count == 35)
  #expect(days.first?.dayKey == "2024-01-28")
  #expect(days.last?.dayKey == "2024-03-02")
  // The 4 leading January days and 2 trailing March days are dimmed;
  // every one of the 29 February days is the current month.
  #expect(days.prefix(4).allSatisfy { !$0.isCurrentMonth })
  #expect(days.dropFirst(4).prefix(29).allSatisfy { $0.isCurrentMonth })
  #expect(days.suffix(2).allSatisfy { !$0.isCurrentMonth })
}

@Test
func calendarMonthGridBuildDaysPlacesMultiDayEventsOnEveryDayTheySpan() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))

  let trip = calendarMonthGridEvent(
    id: "trip", title: "Conference", startDate: "2024-02-08", endDate: "2024-02-10", allDay: true)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [trip],
    tasks: [],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  let spanned = days.filter { $0.events.contains(where: { $0.id == "trip" }) }.map(\.dayKey)
  #expect(spanned == ["2024-02-08", "2024-02-09", "2024-02-10"])
}

@Test
func calendarMonthGridBuildDaysLeavesAnEventEndingAtMidnightOffItsEndDay() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))

  // 10 PM to midnight takes no time on the 15th; 11 PM to 12:30 AM does.
  let lateShow = calendarMonthGridEvent(
    id: "late-show", title: "Late show", startDate: "2024-02-14", endDate: "2024-02-15",
    startTime: "22:00", endTime: "00:00")
  let redEye = calendarMonthGridEvent(
    id: "red-eye", title: "Red-eye", startDate: "2024-02-14", endDate: "2024-02-15",
    startTime: "23:00", endTime: "00:30")

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [lateShow, redEye],
    tasks: [],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  #expect(days.first { $0.dayKey == "2024-02-14" }?.events.map(\.id) == ["late-show", "red-eye"])
  #expect(days.first { $0.dayKey == "2024-02-15" }?.events.map(\.id) == ["red-eye"])
}

@Test
func calendarMonthGridBuildDaysPlacesDueDatedTasksOnlyOnTheirDueDay() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))
  let dueDate = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 14)))

  let task = calendarMonthGridTask(id: "t1", title: "File taxes", dueDate: dueDate)
  let undated = calendarMonthGridTask(id: "t2", title: "No due date", dueDate: nil)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [],
    tasks: [task, undated],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  let withTasks = days.filter { !$0.scheduledTasks.isEmpty }
  #expect(withTasks.map(\.dayKey) == ["2024-02-14"])
  #expect(withTasks.first?.scheduledTasks.map(\.id) == ["t1"])
}

@Test
func calendarMonthGridUsesPlannedFirstStorageDaysWithoutTimezoneShift() throws {
  let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = timeZone
  calendar.firstWeekday = 1
  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = timeZone
  formatter.dateFormat = "yyyy-MM-dd"
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))

  let plannedOnly = calendarMonthGridTask(
    id: "planned-only",
    title: "Planned only",
    dueDate: nil,
    plannedDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-27"))
  let plannedWins = calendarMonthGridTask(
    id: "planned-wins",
    title: "Planned wins",
    dueDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-26"),
    plannedDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-28"))

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [],
    tasks: [plannedOnly, plannedWins],
    dayKeyFor: { formatter.string(from: $0) }
  )

  #expect(days.first { $0.dayKey == "2026-05-26" }?.scheduledTasks.isEmpty == true)
  #expect(days.first { $0.dayKey == "2026-05-27" }?.scheduledTasks.map(\.id) == ["planned-only"])
  #expect(days.first { $0.dayKey == "2026-05-28" }?.scheduledTasks.map(\.id) == ["planned-wins"])
}

@Test
func calendarMonthGridBuildDaysOrdersAllDayEventsBeforeTimedEventsByStartMinute() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))

  let afternoon = calendarMonthGridEvent(
    id: "afternoon", title: "Afternoon sync", startDate: "2024-02-14", startTime: "14:00")
  let morning = calendarMonthGridEvent(
    id: "morning", title: "Morning standup", startDate: "2024-02-14", startTime: "09:00")
  let holiday = calendarMonthGridEvent(
    id: "holiday", title: "Valentine's Day", startDate: "2024-02-14", allDay: true)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [afternoon, morning, holiday],
    tasks: [],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  let day = try #require(days.first { $0.dayKey == "2024-02-14" })
  #expect(day.events.map(\.id) == ["holiday", "morning", "afternoon"])
}

// MARK: - chips: bounded visible count + overflow

@Test
func calendarMonthGridChipsShowsEverythingWhenUnderTheCap() {
  let day = CalendarMonthGridDay(
    date: Date(), dayKey: "2024-02-14", isCurrentMonth: true,
    events: [
      calendarMonthGridEvent(id: "e1", title: "One", startDate: "2024-02-14", allDay: true),
      calendarMonthGridEvent(id: "e2", title: "Two", startDate: "2024-02-14", allDay: true),
    ],
    scheduledTasks: [])

  let result = CalendarMonthGridModel.chips(for: day, maxVisible: 3)

  #expect(result.visible.count == 2)
  #expect(result.overflowCount == 0)
}

@Test
func calendarMonthGridChipsReservesOneSlotForTheOverflowBadgeWhenOverCapacity() {
  let day = CalendarMonthGridDay(
    date: Date(), dayKey: "2024-02-14", isCurrentMonth: true,
    events: [
      calendarMonthGridEvent(id: "e1", title: "One", startDate: "2024-02-14", allDay: true),
      calendarMonthGridEvent(id: "e2", title: "Two", startDate: "2024-02-14", allDay: true),
      calendarMonthGridEvent(id: "e3", title: "Three", startDate: "2024-02-14", allDay: true),
    ],
    scheduledTasks: [
      calendarMonthGridTask(id: "t1", title: "Task", dueDate: Date())
    ])

  // 4 items over a cap of 3: only 2 chips show (cap - 1), leaving 2 hidden.
  let result = CalendarMonthGridModel.chips(for: day, maxVisible: 3)

  #expect(result.visible.map(\.id) == ["event#e1", "event#e2"])
  #expect(result.overflowCount == 2)
}

@Test
func calendarMonthGridChipsHandlesAZeroCapAsAllOverflow() {
  let day = CalendarMonthGridDay(
    date: Date(), dayKey: "2024-02-14", isCurrentMonth: true,
    events: [calendarMonthGridEvent(id: "e1", title: "One", startDate: "2024-02-14", allDay: true)],
    scheduledTasks: [])

  let result = CalendarMonthGridModel.chips(for: day, maxVisible: 0)

  #expect(result.visible.isEmpty)
  #expect(result.overflowCount == 1)
}

// MARK: - Fixtures

// MARK: - buildDays: timed tasks

@Test
func calendarMonthGridPlacesATimedTaskOnItsPlannedDayOnly() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))
  let dueDate = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 13)))
  let plannedDate = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 14)))
  // Due on the 13th, planned for 10:55 on the 14th: the planned day is where
  // the task is drawn, the way the week grid draws it.
  let task = calendarMonthGridTask(
    id: "t1", title: "Send the status update", dueDate: dueDate, plannedDate: plannedDate,
    plannedTime: 10 * 60 + 55..<11 * 60 + 35)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [],
    tasks: [task],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  let dueDay = try #require(days.first { $0.dayKey == "2024-02-13" })
  let planDay = try #require(days.first { $0.dayKey == "2024-02-14" })
  #expect(dueDay.entries.isEmpty)
  #expect(planDay.scheduledTasks.isEmpty)
  #expect(planDay.timedTasks.map(\.id) == ["t1"])
  #expect(planDay.entries.map(\.id) == ["timed#t1"])
}

@Test
func calendarMonthGridDrawsATimedTaskOnceAndSkipsCancelledTasks() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))
  let plannedDate = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 14)))
  let planned = calendarMonthGridTask(
    id: "t1", title: "Draft the agenda", dueDate: nil, plannedDate: plannedDate,
    plannedTime: 9 * 60 + 45..<10 * 60 + 45)
  let cancelled = calendarMonthGridTask(
    id: "t2", title: "Dropped", dueDate: nil, plannedDate: plannedDate,
    plannedTime: 13 * 60..<13 * 60 + 30, status: .cancelled)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [],
    tasks: [planned, planned, cancelled],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  let planDay = try #require(days.first { $0.dayKey == "2024-02-14" })
  #expect(planDay.scheduledTasks.isEmpty)
  #expect(planDay.timedTasks.map(\.id) == ["t1"])
  #expect(days.allSatisfy { $0.entries.allSatisfy { !$0.id.hasSuffix("#t2") } })
}

@Test
func calendarMonthGridOrdersTimedTasksWithTimedEventsByStart() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))
  let day14 = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 14)))
  let offsite = calendarMonthGridEvent(id: "offsite", title: "Offsite", startDate: "2024-02-14", allDay: true)
  let standup = calendarMonthGridEvent(
    id: "standup", title: "Standup", startDate: "2024-02-14", startTime: "09:30")
  let lunch = calendarMonthGridEvent(id: "lunch", title: "Lunch", startDate: "2024-02-14", startTime: "12:00")
  let venue = calendarMonthGridTask(id: "t3", title: "Book the venue", dueDate: day14)
  let agenda = calendarMonthGridTask(
    id: "t2", title: "Draft the agenda", dueDate: nil, plannedDate: day14,
    plannedTime: 9 * 60 + 45..<10 * 60 + 45)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [lunch, standup, offsite],
    tasks: [venue, agenda],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )

  let day = try #require(days.first { $0.dayKey == "2024-02-14" })
  #expect(
    day.entries.map(\.id) == ["event#offsite", "task#t3", "event#standup", "timed#t2", "event#lunch"])
  let chips = CalendarMonthGridModel.chips(for: day, maxVisible: 3)
  #expect(chips.visible.map(\.id) == ["event#offsite", "task#t3"])
  #expect(chips.overflowCount == 3)
}

@Test
func calendarMonthGridOrdersAnEventByTheTimeItTakesOnEachDayItTouches() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 10)))
  let redEye = calendarMonthGridEvent(
    id: "redeye", title: "Red-eye to Berlin", startDate: "2024-02-14", endDate: "2024-02-15",
    startTime: "22:00", endTime: "06:00")
  let conference = calendarMonthGridEvent(
    id: "conference", title: "Conference", startDate: "2024-02-14", endDate: "2024-02-16",
    startTime: "09:00", endTime: "17:00")
  let standups = ["14", "15", "16"].map {
    calendarMonthGridEvent(
      id: "standup-\($0)", title: "Standup", startDate: "2024-02-\($0)", startTime: "09:30")
  }
  let offsite = calendarMonthGridEvent(
    id: "offsite", title: "Offsite", startDate: "2024-02-15", allDay: true)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor,
    calendar: calendar,
    events: [redEye, conference, offsite] + standups,
    tasks: [],
    dayKeyFor: { calendarMonthGridYMD.string(from: $0) }
  )
  func entryIDs(_ dayKey: String) throws -> [String] {
    try #require(days.first { $0.dayKey == dayKey }).entries.map(\.id)
  }

  // The conference opens before the standup on the 14th and the red-eye
  // leaves that night. On the 15th the conference fills the day beside the
  // all-day offsite, and the red-eye, in the air since midnight, leads the
  // timed entries. On the 16th the conference ends before the standup.
  let first = try entryIDs("2024-02-14")
  let second = try entryIDs("2024-02-15")
  let third = try entryIDs("2024-02-16")
  #expect(first == ["event#conference", "event#standup-14", "event#redeye"])
  #expect(second == ["event#conference", "event#offsite", "event#redeye", "event#standup-15"])
  #expect(third == ["event#conference", "event#standup-16"])
}

private let calendarMonthGridYMD: DateFormatter = {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter
}()

private func calendarMonthGridEvent(
  id: String,
  title: String,
  startDate: String,
  endDate: String? = nil,
  startTime: String? = nil,
  endTime: String? = nil,
  allDay: Bool = false
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: id,
    title: title,
    source: "lorvex",
    editable: true,
    startDate: startDate,
    startTime: startTime,
    endDate: endDate,
    endTime: endTime,
    allDay: allDay,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: nil,
    isRecurring: false
  )
}

private func calendarMonthGridTask(
  id: String,
  title: String,
  dueDate: Date?,
  plannedDate: Date? = nil,
  plannedTime: Range<Int>? = nil,
  status: LorvexTask.Status = .open
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: "",
    priority: .p3,
    status: status,
    dueDate: dueDate,
    plannedDate: plannedDate,
    plannedTime: plannedTime,
    estimatedMinutes: nil,
    tags: []
  )
}

// MARK: - minimumWeeks: a grid that keeps six rows for every month

@Test
func calendarMonthGridPadsAShortMonthToTheMinimumWeeksWithTheNextMonth() throws {
  // February 2026 starts on a Sunday and has 28 days, so a Sunday-first grid
  // needs exactly four rows; a six-row grid fills two more with March 1–14.
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 1
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.timeZone = calendar.timeZone
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"

  #expect(CalendarMonthGridModel.gridRange(forMonthContaining: monthAnchor, calendar: calendar).dayCount == 28)
  let range = CalendarMonthGridModel.gridRange(
    forMonthContaining: monthAnchor, calendar: calendar, minimumWeeks: 6)
  #expect(range.dayCount == 42)

  let days = CalendarMonthGridModel.buildDays(
    monthAnchor: monthAnchor, calendar: calendar, events: [], tasks: [], minimumWeeks: 6,
    dayKeyFor: { formatter.string(from: $0) })
  #expect(days.count == 42)
  #expect(days.first?.dayKey == "2026-02-01")
  #expect(days[27].dayKey == "2026-02-28")
  #expect(days[28].dayKey == "2026-03-01")
  #expect(days.last?.dayKey == "2026-03-14")
  #expect(days.prefix(28).allSatisfy { $0.isCurrentMonth })
  #expect(days.suffix(14).allSatisfy { !$0.isCurrentMonth })
}

@Test
func calendarMonthGridMinimumWeeksNeverShortensALongMonth() throws {
  // January 2023 under a Tuesday-first calendar needs six rows on its own; a
  // smaller minimum leaves it at six.
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
  calendar.firstWeekday = 3
  let monthAnchor = try #require(calendar.date(from: DateComponents(year: 2023, month: 1, day: 15)))

  let range = CalendarMonthGridModel.gridRange(
    forMonthContaining: monthAnchor, calendar: calendar, minimumWeeks: 4)
  #expect(range.dayCount == 42)
}
