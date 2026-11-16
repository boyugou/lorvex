import Foundation
import Testing

@testable import LorvexCore
@testable import LorvexMobile
@testable import LorvexApple

@MainActor
@Suite("Calendar offset transitions remain visible and chronological")
struct CalendarTimelineFoldPresentationTests {
  @Test(arguments: [
    ("2026-11-01", "05:45", "06:15", "America/New_York", "2026-11-01", [[60, 75], [105, 120]], 30),
    ("2026-11-01", "05:30", "06:30", "America/New_York", "2026-11-01", [[60, 90], [90, 120]], 60),
    ("2026-03-08", "06:30", "07:30", "America/New_York", "2026-03-08", [[90, 120], [180, 210]], 60),
    ("2026-04-04", "14:50", "15:10", "Australia/Lord_Howe", "2026-04-05", [[90, 100], [110, 120]], 20),
  ])
  func gridSplitsTrueOccupiedClocks(
    sourceDay: String, start: String, end: String, zone: String, shownDay: String,
    expected: [[Int]], duration: Int
  ) async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: zone)
    let saved = try await create(core, day: sourceDay, start: start, end: end)
    let snapshot = try await core.loadCalendarTimeline(from: shownDay, to: shownDay)
    let event = try #require(snapshot.events.first { $0.eventID == saved.id })
    let day = try #require(days(events: [event], on: shownDay).first)
    #expect(day.timedBlocks.map { [$0.startMin, $0.endMin] } == expected)
    #expect(Set(day.timedBlocks.map(\.id)).count == expected.count)
    #expect(day.timedBlocks.allSatisfy { $0.event.id == event.id && !$0.canEditOnGrid })
    #expect(day.timedBlocks.allSatisfy { $0.clockSegment != nil && $0.rangeLabel?.contains("GMT") == true })
    #expect(event.elapsedMinutes == duration)
    let timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    #expect(timing.isValid)
    #expect(timing.clockOffsetNote?.contains("GMT") == true)
    #expect(timing.storing(for: event).startTime == start)
    #expect(timing.storing(for: event).endTime == end)
    let text = try #require(event.whenLines(allDay: "All day").second)
    #expect(text.components(separatedBy: "GMT").count == 3)
    #expect(calendarEventAccessibilityLabel(event).contains(text))
    #expect(event.listTimeLabel(on: shownDay, range: { _, _ in "unqualified clock" }) == text)
    let export = try #require(CalendarEventExport(event: event, notes: nil,
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: .gmt)))
    #expect(export.startDate == event.projection?.start)
    #expect(export.endDate == event.projection?.end)
    #expect(Int(export.endDate.timeIntervalSince(export.startDate) / 60) == duration)
    let occupied = LorvexWeekLoad.mergedMeetings([event], key: shownDay, workStart: 0, workEnd: 1440)
    let expectedMinutes = Set(expected.flatMap { Array($0[0]..<$0[1]) })
    #expect(Set(occupied.flatMap { Array($0.start..<$0.end) }) == expectedMinutes)
  }

  @Test func agendaAndNowLineFollowInstantsThroughRepeatedHour() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "America/New_York")
    let early = try await create(core, start: "05:45", end: "06:15")
    let later = try await create(core, start: "06:20", end: "06:30")
    let snapshot = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    let events = snapshot.eventsOccurring(on: "2026-11-01")
    #expect(events.map(\.eventID) == [early.id, later.id])
    #expect(LorvexAgendaDay.build(todayKey: "2026-10-31", events: events, tasks: [], dayCount: 1)
      .first?.events.map(\.eventID) == [early.id, later.id])
    let duringFirstHour = LorvexTodayTimeline.build(
      day: "2026-11-01", events: events, tasks: [], times: [:], nowMinutes: 110,
      now: instant("2026-11-01T05:50:00Z"))
    #expect(duringFirstHour.map(\.id) == ["event:\(early.id)", "now", "event:\(later.id)"])
    #expect(!duringFirstHour[0].isPast)
    let calm = LorvexCalmToday.build(tasks: [], events: events, doneToday: 0, nowMinutes: 110,
      logicalDay: "2026-11-01", workingHours: nil, now: instant("2026-11-01T05:50:00Z"))
    #expect(calm.remainingMeetings == 2)
    #expect(duringFirstHour[0].timeLabel.contains("GMT-4"))
    #expect(duringFirstHour[0].timeLabel.contains("GMT-5"))
    let duringSecondHour = LorvexTodayTimeline.build(
      day: "2026-11-01", events: events, tasks: [], times: [:], nowMinutes: 77,
      now: instant("2026-11-01T06:17:00Z"))
    #expect(duringSecondHour[0].isPast)
    #expect(LorvexTodayTimeline.earlierFold(duringSecondHour) == 0..<1)
    let mobile = MobileCalendarAgendaDay(date: civil("2026-11-01"), key: "2026-11-01", events: events, tasks: [])
    #expect(mobile.entries.map(\.id) == ["event:\(early.id)", "event:\(later.id)"])
    #expect(!mobile.hasPassed(events[0], todayKey: "2026-11-01", nowMinutes: 110, now: instant("2026-11-01T05:50:00Z")))
    #expect(mobile.hasPassed(events[0], todayKey: "2026-11-01", nowMinutes: 77, now: instant("2026-11-01T06:17:00Z")))
    #expect(events[1].timeLabel(for: .whole)?.contains("GMT-5") == true)
  }

  @Test func geometryNeverInventsAnEndpoint() {
    for end in [nil, "09:00"] as [String?] {
      let event = CalendarTimelineEvent(id: "point", title: "Point", source: "canonical", editable: true,
        startDate: "2026-11-01", startTime: "09:00", endDate: nil, endTime: end,
        allDay: false, location: nil, color: nil, eventType: "event", timezone: nil, isRecurring: false)
      let block = days(events: [event], on: "2026-11-01")[0].timedBlocks[0]
      #expect(block.rangeLabel == lorvexClockTimeLabel("09:00"))
      #expect(block.drawnEndMin > block.startMin)
    }
  }

  @Test func draftOffsetNoteFollowsEditsAndAllDaySwitch() throws {
    let event = try #require(MobileCalendarDebugState.clockFoldExample(editable: true))
    var timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    #expect(timing.clockOffsetNote?.contains("GMT-4") == true)
    #expect(timing.clockOffsetNote?.contains("GMT-5") == true)
    timing.start = instant("2026-11-02T15:00:00Z")
    timing.end = instant("2026-11-02T15:30:00Z")
    #expect(timing.clockOffsetNote == nil)
    timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    timing.allDay = true
    #expect(timing.clockOffsetNote == nil)
  }

  @Test(arguments: [
    ("2026-11-01T05:45:00Z", "2026-11-01T06:15:00Z", "America/New_York"),
    ("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "America/New_York"),
    ("2026-11-01T06:10:00Z", "2026-11-01T06:40:00Z", "America/New_York"),
    ("2026-04-04T14:50:00Z", "2026-04-04T15:10:00Z", "Australia/Lord_Howe"),
  ])
  func unchangedPickerValuesKeepBothInstants(start: String, end: String, zone: String) {
    let original = CalendarEventTiming(start: instant(start), end: instant(end), allDay: false,
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: TimeZone(identifier: zone)!))
    var timing = original
    timing.moveStart(to: original.start)
    #expect(timing == original)
    timing.setStartDay(original.calendar.startOfDay(for: original.start))
    #expect(timing == original)
    timing.setStartTime(original.start)
    #expect(timing == original)
    timing.setEndDay(original.calendar.startOfDay(for: original.end))
    #expect(timing == original)
    timing.setEndTime(original.end)
    #expect(timing == original)
    timing.setEnd(original.end)
    #expect(timing == original)
  }

  @Test(arguments: [
    ("2026-11-01T05:45:00Z", "2026-11-01T06:15:00Z", "America/New_York"),
    ("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "America/New_York"),
    ("2026-04-04T14:50:00Z", "2026-04-04T15:10:00Z", "Australia/Lord_Howe"),
  ])
  func movingCollapsedOrReversedClocksKeepsElapsedLength(start: String, end: String, zone: String) {
    var timing = CalendarEventTiming(start: instant(start), end: instant(end), allDay: false,
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: TimeZone(identifier: zone)!))
    let elapsed = timing.end.timeIntervalSince(timing.start)
    timing.setStartDay(timing.start.addingTimeInterval(86_400))
    #expect(timing.isValid)
    #expect(timing.end.timeIntervalSince(timing.start) == elapsed)
    #expect(timing.clockOffsetNote == nil)
  }

  @Test func editingAnAmbiguousClockKeepsItsCurrentReading() throws {
    let event = try #require(MobileCalendarDebugState.clockFoldExample(editable: true))
    var timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    timing.setEndTime(instant("2026-11-01T06:20:00Z"))
    #expect(timing.end == instant("2026-11-01T06:20:00Z"))
    #expect(timing.endDate == nil)
    timing.setEndTime(instant("2026-11-01T06:50:00Z"))
    #expect(timing.end == instant("2026-11-01T06:50:00Z"))
    timing = CalendarEventTiming(start: instant("2026-11-01T06:10:00Z"), end: instant("2026-11-01T06:40:00Z"),
      allDay: false, calendar: timing.calendar)
    timing.setStartTime(instant("2026-11-01T06:20:00Z"))
    #expect(timing.start == instant("2026-11-01T06:20:00Z"))
    #expect(timing.end == instant("2026-11-01T06:50:00Z"))
    let short = CalendarEventTiming.timed(startingAt: instant("2026-11-01T06:15:00Z"), minutes: 15, calendar: timing.calendar)
    #expect(short.end == instant("2026-11-01T06:30:00Z"))
  }

  @Test(arguments: ["en_US", "zh_CN", "ja_JP", "ar_SA"])
  func equalClocksKeepBothOffsetsInEveryClockFormat(locale: String) async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "America/New_York")
    _ = try await create(core, start: "05:30", end: "06:30")
    let snapshot = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    let event = try #require(snapshot.events.first)
    for format in [LorvexClockFormat.twelveHour, .twentyFourHour] {
      let locale = format.applied(to: Locale(identifier: locale))
      let text = try #require(event.offsetClockRangeLabel(locale: locale))
      for offset in [-14400, -18000] {
        let label = LorvexDateFormatters.string(instant("2026-11-01T06:30:00Z"), template: "O",
          timeZone: TimeZone(secondsFromGMT: offset)!, locale: locale)
        #expect(text.contains(label))
      }
    }
  }

  private func days(events: [CalendarTimelineEvent], on key: String) -> [CalendarGridDay] {
    CalendarGridModel.buildDays(rangeStart: civil(key), dayCount: 1,
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: .gmt), events: events, tasks: [],
      dayKeyFor: { LorvexDateFormatters.ymdUTC.string(from: $0) })
  }
  private func civil(_ key: String) -> Date { LorvexDateFormatters.ymdUTC.date(from: key)! }
  private func instant(_ key: String) -> Date { ISO8601DateFormatter().date(from: key)! }
  private func create(_ core: SwiftLorvexCoreService, day: String = "2026-11-01", start: String, end: String) async throws -> CalendarTimelineEvent {
    try await core.createCalendarEvent(
      title: "Clock change", startDate: day, endDate: nil, startTime: start, endTime: end,
      allDay: false, location: nil, notes: nil, recurrence: nil, timezone: "UTC", url: nil,
      color: nil, eventType: nil, personName: nil, attendees: nil)
  }
}
