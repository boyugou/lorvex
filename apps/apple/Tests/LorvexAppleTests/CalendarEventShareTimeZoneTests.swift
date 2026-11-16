import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore
@testable import LorvexMobile

@MainActor
@Suite("Calendar sharing keeps its time context")
struct CalendarEventShareTimeZoneTests {
  @Test func aProjectedWeeklyEventNamesBothClocks() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    let saved = try await core.createCalendarEvent(
      title: "Monday meeting", startDate: "2026-11-23", endDate: nil,
      startTime: "23:30", endTime: "23:45", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .weekly), timezone: "America/New_York",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-24", to: "2026-11-24")
    let displayed = try #require(timeline.events.first { $0.eventID == saved.id })
    for text in sharedTexts(displayed) {
      #expect(text.contains("Tuesday, November 24, 2026"))
      #expect(text.contains(lorvexClockRangeLabel(start: "13:30", end: "13:45")))
      #expect(text.contains("Time Zone: Tokyo · GMT+9"))
      #expect(text.contains("Repeats: Every week · Mon"))
      #expect(text.contains("Repeats in New York · GMT-5"))
    }
    let storedText = CalendarEventShare.text(for: saved)
    #expect(storedText.contains("Monday, November 23, 2026"))
    #expect(storedText.contains("Time Zone: New York · GMT-5"))
    #expect(!storedText.contains("Repeats in"))
  }

  @Test(arguments: [("2026-01-15", "GMT-5"), ("2026-07-15", "GMT-4")])
  func aStoredEventUsesItsOwnSeasonalOffset(day: String, offset: String) {
    for text in sharedTexts(event(day: day, timezone: "America/New_York")) {
      #expect(text.contains("Time Zone: New York · \(offset)"))
      #expect(text.contains("2026"))
    }
  }

  @Test(arguments: [
    ("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "America/New_York", "GMT-4", "GMT-5"),
    ("2026-03-08T06:30:00Z", "2026-03-08T07:30:00Z", "America/New_York", "GMT-5", "GMT-4"),
    ("2026-04-04T14:45:00Z", "2026-04-04T15:15:00Z", "Australia/Lord_Howe", "GMT+11", "GMT+10:30"),
  ])
  func anOffsetChangeNamesBothEndsEvenWhenTheirWallClocksMatch(
    start: String, end: String, zone: String, firstOffset: String, lastOffset: String
  ) async throws {
    let projected = try await storedProjection(start: start, end: end, zone: zone)
    for text in sharedTexts(projected) {
      let when = try #require(text.split(separator: "\n").first { $0.hasPrefix("When:") })
      #expect(when.contains(firstOffset))
      #expect(when.contains(lastOffset))
      #expect(when.contains("2026"))
    }
  }

  @Test func aForwardInstantRangeCanHaveAReversedWallClock() throws {
    let projected = try projected(
      start: "2026-11-01T05:45:00Z", end: "2026-11-01T06:15:00Z", zone: "America/New_York")
    for text in sharedTexts(projected) {
      #expect(text.contains("GMT-4"))
      #expect(text.contains("GMT-5"))
      #expect(text.contains("1:45"))
      #expect(text.contains("1:15"))
    }
  }

  @Test(arguments: ["en_US", "zh_CN", "ja_JP", "ar_SA"], [LorvexClockFormat.twelveHour, .twentyFourHour])
  func anOffsetChangeSurvivesEachLocaleAndClockChoice(language: String, clock: LorvexClockFormat) throws {
    let locale = clock.applied(to: Locale(identifier: language))
    let event = try projected(
      start: "2026-11-01T05:30:00Z", end: "2026-11-01T06:30:00Z", zone: "America/New_York")
    let projection = try #require(event.projection)
    let labels = LorvexEventShareLabels(
      field: { _ in "" }, line: { "\($0): \($1)" }, dayAtTime: { "\($0), \($1)" },
      allDay: "All day", repeating: "Repeating event")
    let timing = LorvexEventShareTiming(event: event, labels: labels, locale: locale)
    let first = try #require(LorvexTimeZoneChoice(
      identifier: projection.timezone, now: projection.start, locale: locale))
    let end = try #require(projection.end)
    let last = try #require(LorvexTimeZoneChoice(
      identifier: projection.timezone, now: end, locale: locale))
    #expect(first.offsetLabel != last.offsetLabel)
    #expect(timing.when.contains(first.offsetLabel))
    #expect(timing.when.contains(last.offsetLabel))
    #expect(timing.timeZone == first.city)
  }

  @Test func anOpenEndedEventKeepsTheExactSecondReadingOfAnHour() throws {
    let projected = try projected(start: "2026-11-01T06:30:00Z", end: nil, zone: "America/New_York")
    for text in sharedTexts(projected) {
      #expect(text.contains("Time Zone: New York · GMT-5"))
      #expect(!text.contains("GMT-4"))
      #expect(!text.contains("2:30"))
    }
  }

  @Test func midnightNamesTheDayItEndsOn() throws {
    let projected = try projected(
      start: "2026-10-02T14:00:00Z", end: "2026-10-02T15:00:00Z", zone: "Asia/Tokyo")
    #expect(!projected.isMultiDay)
    for text in sharedTexts(projected) {
      #expect(text.contains("October 2"))
      #expect(text.contains("October 3"))
      #expect(text.contains("2026"))
      #expect(text.contains("Time Zone: Tokyo · GMT+9"))
    }
  }

  @Test func aYearBoundaryRetainsBothYears() throws {
    let projected = try projected(
      start: "2026-12-31T23:30:00Z", end: "2027-01-01T00:30:00Z", zone: "UTC")
    for text in sharedTexts(projected) {
      #expect(text.contains("2026"))
      #expect(text.contains("2027"))
      #expect(text.contains("Time Zone: UTC"))
    }
  }

  @Test func aLegacyEndOfDayClockMeansMidnightOnTheFollowingDate() {
    var midnight = event(timezone: "Asia/Tokyo")
    midnight.startTime = "22:00"
    midnight.endTime = "24:00"
    for text in sharedTexts(midnight) {
      #expect(text.contains("October 2"))
      #expect(text.contains("October 3"))
      #expect(text.contains(lorvexClockTimeLabel("00:00")))
      #expect(!text.contains(lorvexClockTimeLabel("23:00")))
    }
  }

  @Test func aDateWithoutAClockDoesNotAcquireNineAMOrAZone() {
    var timeless = event(timezone: "America/New_York")
    timeless.startTime = nil
    timeless.endTime = nil
    for text in sharedTexts(timeless) {
      #expect(text == "Meeting\n\nWhen: Friday, October 2, 2026")
    }
  }

  @Test(arguments: [false, true])
  func floatingAndAllDayEventsStayCivil(allDay: Bool) {
    var civil = event(day: "2011-12-30", timezone: allDay ? "Pacific/Apia" : nil)
    civil.allDay = allDay
    if allDay { civil.startTime = nil; civil.endTime = nil }
    for text in sharedTexts(civil) {
      #expect(text.contains("Friday, December 30, 2011"))
      #expect(!text.contains("Time Zone:"))
      #expect(!text.contains("GMT"))
    }
  }

  @Test func aBadDayNeverAcquiresAGuessedZoneOrFallbackDate() {
    for text in sharedTexts(event(day: "not-a-day", timezone: "America/New_York")) {
      #expect(text.contains("not-a-day"))
      #expect(!text.contains("Time Zone:"))
    }
  }

  private func sharedTexts(_ event: CalendarTimelineEvent) -> [String] {
    let mac = CalendarEventShare.text(for: event)
    let mobile = MobileShareText.event(event)
    #expect(mac == mobile)
    return [mac, mobile]
  }

  private func event(day: String = "2026-10-02", timezone: String?) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: "share-event", title: "Meeting", source: "canonical", editable: true,
      startDate: day, startTime: "09:00", endDate: nil, endTime: "10:00", allDay: false,
      location: nil, color: nil, eventType: "event", timezone: timezone, isRecurring: false)
  }

  private func projected(start: String, end: String?, zone: String) throws -> CalendarTimelineEvent {
    let first = try #require(LorvexDateFormatters.iso8601.date(from: start))
    let last = try end.map { try #require(LorvexDateFormatters.iso8601.date(from: $0)) }
    let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: try #require(TimeZone(identifier: zone)))
    let timing = CalendarEventTiming(start: first, end: last ?? first, allDay: false, calendar: calendar)
    var event = event(day: timing.startDate, timezone: "UTC")
    event.startTime = timing.startTime
    event.endDate = last == nil ? nil : timing.endDate
    event.endTime = last == nil ? nil : timing.endTime
    event.projection = CalendarEventProjection(timezone: zone, start: first, end: last)
    return event
  }

  private func storedProjection(start: String, end: String?, zone: String) async throws -> CalendarTimelineEvent {
    let raw = try projected(start: start, end: end, zone: "UTC")
    let expected = try projected(start: start, end: end, zone: zone)
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: zone)
    let saved = try await core.createCalendarEvent(
      title: "Meeting", startDate: raw.startDate, endDate: raw.endDate,
      startTime: raw.startTime, endTime: raw.endTime, allDay: false, location: nil, notes: nil,
      recurrence: nil, timezone: "UTC", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(
      from: expected.startDate, to: expected.endDate ?? expected.startDate)
    let actual = try #require(timeline.events.first { $0.eventID == saved.id })
    #expect(actual.projection == expected.projection)
    return actual
  }
}
