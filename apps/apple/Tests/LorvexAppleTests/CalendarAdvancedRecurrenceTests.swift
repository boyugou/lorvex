import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

@Suite("Advanced calendar recurrence")
struct CalendarAdvancedRecurrenceTests {
  @Test func monthEndIsDistinctFromTheLiteralThirtyFirst() {
    let last = TaskRecurrenceRule(freq: .monthly, byMonthDay: [-1]).localizedCadence
    let literal = TaskRecurrenceRule(freq: .monthly, byMonthDay: [31]).localizedCadence
    #expect(last == "Every month · last day")
    #expect(literal == "Every month · day 31")
    #expect(last != literal)
  }

  @Test func allMonthDaysRemainVisible() {
    let summary = TaskRecurrenceRule(freq: .monthly, byMonthDay: [-2, 15, -1, 1]).localizedCadence
    #expect(summary == "Every month · day 1, day 15, last day, 2nd-to-last day")
  }

  @Test func selectionPositionsAreShownAfterTheMatchingWeekdays() {
    let summary = TaskRecurrenceRule(
      freq: .monthly, byDay: ["MO", "FR"], bySetPos: [-1, 1]).localizedCadence
    #expect(summary == "Every month · Mon, Fri · 1st matching day, last matching day")
  }

  @Test func everyConstraintSurvivesTheFullSummary() {
    let summary = TaskRecurrenceRule(
      freq: .yearly, interval: 2, byDay: ["1MO"], byMonth: [9, 3],
      byMonthDay: [15, 1], bySetPos: [-2], wkst: "SU", count: 12).localizedDisplaySummary()
    #expect(summary == "Every 2 years · Mar, Sep · 1st Mon · day 1, day 15 · 2nd-to-last matching day · week starts Sun · 12 times")
  }

  @Test func theWeekStartIsVisibleWhenItDefinesAnInterval() {
    let summary = TaskRecurrenceRule(
      freq: .weekly, interval: 2, byDay: ["SU", "TU"], wkst: "SU").localizedCadence
    #expect(summary.hasSuffix(" · week starts Sun"))
  }

  @Test(arguments: ["en_US@calendar=hebrew", "en_US@calendar=islamic", "en_US@calendar=buddhist"])
  func monthNumbersAlwaysNameGregorianMonths(locale: String) {
    #expect(LorvexRecurrenceConstraints.months([9, 3], locale: Locale(identifier: locale)) == "Mar, Sep")
  }

  @Test func malformedPositionsRemainReadableWithoutOverflow() {
    let values = [Int.min, Int.max, 0]
    for summary in [
      LorvexRecurrenceConstraints.monthDays(values),
      LorvexRecurrenceConstraints.positions(values),
    ] {
      for value in values { #expect(summary.contains(String(value))) }
    }
  }

  @MainActor
  @Test(arguments: [
    (TaskRecurrenceRule(freq: .daily), false),
    (TaskRecurrenceRule(freq: .yearly), false),
    (TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "FR"]), false),
    (TaskRecurrenceRule(freq: .monthly), false),
    (TaskRecurrenceRule(freq: .monthly, byMonthDay: [31]), false),
    (TaskRecurrenceRule(freq: .monthly, byMonthDay: [-1]), true),
    (TaskRecurrenceRule(freq: .monthly, byMonthDay: [1, 15]), true),
    (TaskRecurrenceRule(freq: .monthly, byDay: ["1MO"]), true),
    (TaskRecurrenceRule(freq: .monthly, byDay: ["MO", "FR"], bySetPos: [-1]), true),
    (TaskRecurrenceRule(freq: .yearly, byMonth: [3, 9]), true),
    (TaskRecurrenceRule(freq: .weekly, byDay: ["MO"], wkst: "SU"), true),
    (TaskRecurrenceRule(freq: .daily, byDay: ["MO"]), true),
  ])
  func basicControlsNeverPretendToRepresentACustomPattern(rule: TaskRecurrenceRule, custom: Bool) {
    #expect(CalendarEventRepeatField.hasCustomPattern(rule) == custom)
  }

  @MainActor
  @Test func choosingMonthlyFromCustomExplicitlyReplacesThePattern() throws {
    let timing = CalendarEventTiming.timed(
      startingAt: try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-07-06")),
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: .gmt))
    let custom = TaskRecurrenceRule(
      freq: .monthly, interval: 2, byDay: ["1MO"], byMonth: [3], byMonthDay: [-1],
      bySetPos: [1], wkst: "SU", until: "2028-12-31")
    let unchanged = CalendarEventRepeatField.ruleFor(
      frequency: .monthly, from: custom, referenceTiming: timing)
    #expect(unchanged == custom)
    let replacement = CalendarEventRepeatField.ruleFor(
      frequency: .monthly, from: custom, referenceTiming: timing, replacingCustomPattern: true)
    #expect(replacement == TaskRecurrenceRule(
      freq: .monthly, interval: 2, byMonthDay: [6], until: "2028-12-31"))
    #expect(!CalendarEventRepeatField.hasCustomPattern(replacement))
  }

  @MainActor
  @Test(arguments: [
    (TaskRecurrenceRule(freq: .monthly, byMonthDay: [-1], count: 12),
      ["2026-01-31", "2026-03-31", "2026-05-31"]),
    (TaskRecurrenceRule(freq: .monthly, byMonthDay: [1, 15], count: 12),
      ["2026-01-01", "2026-01-15", "2026-03-01", "2026-03-15", "2026-05-01", "2026-05-15"]),
    (TaskRecurrenceRule(freq: .monthly, byDay: ["MO", "TU", "WE", "TH", "FR"],
      bySetPos: [-1], wkst: "SU", count: 12), ["2026-01-30", "2026-03-31", "2026-05-29"]),
    (TaskRecurrenceRule(freq: .yearly, byDay: ["1MO"], byMonth: [3, 9], until: "2028-12-31"),
      ["2026-03-02"]),
  ])
  func titleAndIntervalEditsPreserveThePatternAndItsFutureDates(
    rule: TaskRecurrenceRule, expectedDays: [String]
  ) async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "UTC")
    let saved = try await core.createCalendarEvent(
      title: "Custom repeat", startDate: "2026-01-01", endDate: nil,
      startTime: "09:00", endTime: "10:00", allDay: false, location: nil, notes: nil,
      recurrence: rule, timezone: "UTC", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let original = try #require(TaskRecurrenceRule.bridgeRule(from: saved.recurrenceRule))
    let store = AppStore(core: core, cloudSyncMode: .off)
    await store.refresh()
    func firstOccurrence() async throws -> CalendarTimelineEvent {
      let timeline = try await core.loadCalendarTimeline(from: "2026-01-01", to: "2026-06-30")
      return try #require(timeline.events.first { $0.eventID == saved.id })
    }
    let first = try await firstOccurrence()
    store.prepareCalendarDraft(for: first)
    #expect(store.draftCalendarRecurrencePatch == .unset)
    #expect(CalendarEventRepeatField.hasCustomPattern(try #require(store.draftCalendarRecurrence)))
    store.draftCalendarTitle = "Retitled"
    await store.saveScopedCalendarEvent(first, scope: .allEvents)
    #expect(store.errorMessage == nil)
    #expect(try #require(await core.getCalendarEvent(id: saved.id)).recurrenceRule == saved.recurrenceRule)

    let renamed = try await firstOccurrence()
    store.prepareCalendarDraft(for: renamed)
    store.draftCalendarRecurrence?.interval = 2
    await store.saveScopedCalendarEvent(renamed, scope: .allEvents)
    #expect(store.errorMessage == nil)
    let updated = try #require(await core.getCalendarEvent(id: saved.id))
    var expected = original
    expected.interval = 2
    #expect(TaskRecurrenceRule.bridgeRule(from: updated.recurrenceRule) == expected)
    #expect(updated.title == "Retitled")
    let timeline = try await core.loadCalendarTimeline(from: "2026-01-01", to: "2026-06-30")
    #expect(timeline.events.filter { $0.eventID == saved.id }.map(\.startDate) == expectedDays)
    if rule.freq == .yearly {
      #expect(try await core.loadCalendarTimeline(from: "2027-01-01", to: "2027-12-31").events.isEmpty)
    }
  }
}
