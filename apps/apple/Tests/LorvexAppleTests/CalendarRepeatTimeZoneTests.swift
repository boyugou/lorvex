import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
struct CalendarRepeatTimeZoneTests {
  private func fixture(recurring: Bool = false) async throws -> (
    SwiftLorvexCoreService, AppStore, CalendarTimelineEvent
  ) {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    let created = try await core.createCalendarEvent(
      title: "Late Los Angeles meeting", startDate: "2026-10-31", endDate: "2026-11-01",
      startTime: "23:30", endTime: "00:30", allDay: false, location: nil, notes: nil,
      recurrence: recurring ? TaskRecurrenceRule(freq: .daily) : nil,
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    let event = try #require(timeline.events.first { $0.eventID == created.id })
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-31T14:10:00Z"))
    let store = AppStore(core: core, cloudSyncMode: .off, now: { now })
    await store.refresh()
    store.prepareCalendarDraft(for: event)
    #expect(store.draftCalendarTiming.startDate == "2026-11-01")
    return (core, store, event)
  }

  @Test(arguments: [.weekly, .monthly] as [TaskRecurrenceRule.Frequency])
  func newEventRepeatsOnItsDraftDayAcrossTheMonthBoundary(
    frequency: TaskRecurrenceRule.Frequency
  ) async throws {
    let (core, store, _) = try await fixture()
    store.beginCreateCalendarDraft()
    store.draftCalendarTitle = "Tokyo midnight"
    #expect(store.draftCalendarTiming.startDate == "2026-11-01")
    #expect(store.draftCalendarTiming.startTime == "00:00")
    let rule = CalendarEventRepeatField.ruleFor(
      frequency: frequency, from: nil, referenceTiming: store.draftCalendarRecurrenceTiming)
    #expect(rule.byDay == (frequency == .weekly ? ["SU"] : nil))
    #expect(rule.byMonthDay == (frequency == .monthly ? [1] : nil))
    store.draftCalendarRecurrence = rule

    // A settings change while the form is open cannot change its recurrence
    // defaults or the zone ultimately written with the event.
    #expect(await store.setLogicalTimeZone("America/Los_Angeles"))
    #expect(store.draftCalendarRecurrenceTiming.calendar.timeZone.identifier == "Asia/Tokyo")
    await store.createDraftCalendarEvent()
    #expect(store.errorMessage == nil)
    let matches = try await core.searchCalendarEvents(
      query: "Tokyo midnight", from: nil, to: nil, limit: 10)
    let saved = try #require(matches.first)
    #expect(saved.timezone == "Asia/Tokyo")
    #expect(saved.startDate == "2026-11-01")
    #expect(TaskRecurrenceRule.bridgeRule(from: saved.recurrenceRule)?.byDay == rule.byDay)
    #expect(TaskRecurrenceRule.bridgeRule(from: saved.recurrenceRule)?.byMonthDay == rule.byMonthDay)
  }

  @Test(arguments: [.weekly, .monthly] as [TaskRecurrenceRule.Frequency])
  func addingRepeatToAProjectedEventKeepsItsSourceCalendar(
    frequency: TaskRecurrenceRule.Frequency
  ) async throws {
    let (core, store, event) = try await fixture()
    let reference = store.draftCalendarRecurrenceTiming
    #expect(reference.startDate == "2026-10-31")
    #expect(reference.startTime == "23:30")
    #expect(reference.calendar.timeZone.identifier == "America/Los_Angeles")
    let rule = CalendarEventRepeatField.ruleFor(
      frequency: frequency, from: nil, referenceTiming: reference)
    #expect(rule.byDay == (frequency == .weekly ? ["SA"] : nil))
    #expect(rule.byMonthDay == (frequency == .monthly ? [31] : nil))
    store.draftCalendarRecurrence = rule
    await store.updateCalendarEvent(event)
    #expect(store.errorMessage == nil)
    let saved = try #require(await core.getCalendarEvent(id: event.eventID))
    #expect(saved.startDate == "2026-10-31")
    #expect(saved.startTime == "23:30")
    #expect(saved.timezone == "America/Los_Angeles")

    // The source keeps 23:30 through its fall-back; Tokyo sees 15:30 before
    // and 16:30 after. An explicit monthly 31 skips November, so its next
    // occurrence is December 31 in Los Angeles and January 1 in Tokyo.
    let nextDay = frequency == .weekly ? "2026-11-08" : "2027-01-01"
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-01", to: nextDay)
    let occurrences = timeline.events.filter { $0.eventID == event.eventID }
    #expect(occurrences.map(\.startDate) == ["2026-11-01", nextDay])
    #expect(occurrences.map(\.startTime) == ["15:30", "16:30"])
  }

  @Test(arguments: [.allEvents, .thisAndFollowing] as [CalendarEventEditScope])
  func aLaterOccurrenceChangesFrequencyInTheSourceZone(scope: CalendarEventEditScope) async throws {
    let (core, store, first) = try await fixture(recurring: true)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-08", to: "2026-11-08")
    let later = try #require(timeline.events.first { $0.eventID == first.eventID })
    #expect(later.occurrenceDate == "2026-11-07")
    store.prepareCalendarDraft(for: later)
    store.draftCalendarRecurrence = CalendarEventRepeatField.ruleFor(
      frequency: .weekly, from: store.draftCalendarRecurrence,
      referenceTiming: store.draftCalendarRecurrenceTiming)
    #expect(store.draftCalendarRecurrence?.byDay == ["SA"])
    await store.saveScopedCalendarEvent(later, scope: scope)
    #expect(store.errorMessage == nil)
    let updated = try await core.loadCalendarTimeline(from: "2026-11-08", to: "2026-11-15")
    #expect(updated.events.map(\.startDate) == ["2026-11-08", "2026-11-15"])
    #expect(updated.events.allSatisfy { $0.startTime == "16:30" })
  }

  @Test(arguments: [false, true])
  func openingCreateAndReturningToEditRestoresEachRepeatZone(fromGrid: Bool) async throws {
    let (_, store, _) = try await fixture()
    if fromGrid {
      let day = try #require(PlannedDayBridge.displayDate(
        forLogicalDay: "2026-11-01", timeZone: .current))
      CalendarWorkspaceView(store: store).prepareCreateDraft(date: day, minutes: 9 * 60)
    } else {
      store.beginCreateCalendarDraft()
    }
    #expect(store.draftCalendarRecurrenceTiming.calendar.timeZone.identifier == "Asia/Tokyo")
    #expect(store.draftCalendarRecurrenceTiming.startDate == "2026-11-01")
    store.restoreStashedCalendarDraft()
    #expect(store.draftCalendarTiming.calendar.timeZone.identifier == "Asia/Tokyo")
    #expect(store.draftCalendarRecurrenceTiming.calendar.timeZone.identifier == "America/Los_Angeles")
    #expect(store.draftCalendarRecurrenceTiming.startDate == "2026-10-31")
  }

  @Test
  func allDayAndFloatingRepeatsUseTheirCivilDay() async throws {
    let (_, store, event) = try await fixture()
    store.draftCalendarTiming.allDay = true
    let allDay = store.draftCalendarRecurrenceTiming
    #expect(allDay.startDate == "2026-11-01")
    #expect(CalendarEventRepeatField.ruleFor(
      frequency: .weekly, from: nil, referenceTiming: allDay).byDay == ["SU"])
    store.draftCalendarTiming.allDay = false
    #expect(store.draftCalendarRecurrenceTiming.startDate == "2026-10-31")

    var floating = event
    floating.timezone = nil
    floating.projection = nil
    store.prepareCalendarDraft(for: floating)
    #expect(store.draftCalendarRecurrenceTiming == store.draftCalendarTiming)
    #expect(store.draftCalendarRecurrenceTiming.startDate == "2026-11-01")
  }

  @Test
  func repeatDefaultsUseGregorianDaysInAFractionalOffsetZone() throws {
    var calendar = Calendar(identifier: .islamicCivil)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kathmandu"))
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-31T18:30:00Z"))
    let timing = CalendarEventTiming.timed(startingAt: instant, calendar: calendar)
    #expect(timing.startDate == "2026-11-01")
    #expect(CalendarEventRepeatField.ruleFor(
      frequency: .weekly, from: nil, referenceTiming: timing).byDay == ["SU"])
    #expect(CalendarEventRepeatField.ruleFor(
      frequency: .monthly, from: nil, referenceTiming: timing).byMonthDay == [1])
  }
}
