import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
private func makeRecurrenceCoordinator(
  access: FakeEventKitAccess = FakeEventKitAccess()
) -> EventKitCoordinator {
  EventKitCoordinator(
    access: access,
    provider: FakeEventKitProvider(),
    loadAccessMode: { .busyOnly },
    loadCalendarFilter: { .all },
    isEnabled: { true })
}

private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
  var components = DateComponents()
  components.calendar = Calendar(identifier: .gregorian)
  components.timeZone = .current
  components.year = year
  components.month = month
  components.day = day
  components.hour = hour
  components.minute = minute
  return components.date ?? Date()
}

// MARK: - Recurrence flows through the service

@MainActor
@Test
func calendarCreateWritesTypedRecurrenceThroughCore() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(), eventKitCoordinator: makeRecurrenceCoordinator())
  await store.refresh()

  let start = makeDate(2026, 7, 6, 10, 0)
  store.draftCalendarTitle = "Weekly sync"
  store.draftCalendarDate = start
  store.draftCalendarStartTime = start
  store.draftCalendarEndTime = makeDate(2026, 7, 6, 10, 30)
  store.draftCalendarRecurrence = TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO", "WE"])

  await store.createDraftCalendarEvent()

  let created = try #require(store.calendarTimeline?.events.first { $0.title == "Weekly sync" })
  #expect(created.isRecurring)
  let parsed = try #require(TaskRecurrenceRule.bridgeRule(from: created.recurrenceRule))
  #expect(parsed.freq == .weekly)
  #expect(parsed.byDay == ["MO", "WE"])
  // The draft's recurrence resets alongside the other fields after a create.
  #expect(store.draftCalendarRecurrence == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func calendarUpdateWritesTypedRecurrenceThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  // The store's calendar window spans around today; the fixed 2026-05-22 seed
  // event sits outside it, so the edit targets a fresh in-window event.
  let seeded = try await core.createCalendarEvent(
    title: "Window review", startDate: LorvexDateFormatters.ymd.string(from: Date()),
    endDate: nil, startTime: "15:00", endTime: "15:45", allDay: false,
    location: nil, notes: nil)
  let store = AppStore(core: core, eventKitCoordinator: makeRecurrenceCoordinator())
  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.id == seeded.id })

  store.prepareCalendarDraft(for: event)
  store.draftCalendarRecurrence = TaskRecurrenceRule(freq: .daily, interval: 2)
  await store.updateCalendarEvent(event)

  let updated = try #require(store.calendarTimeline?.events.first { $0.eventID == event.eventID })
  #expect(updated.isRecurring)
  let parsed = try #require(TaskRecurrenceRule.bridgeRule(from: updated.recurrenceRule))
  #expect(parsed.freq == .daily)
  #expect(parsed.interval == 2)
  #expect(store.draftCalendarRecurrence == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func calendarUpdateCanExplicitlyClearRecurrence() async throws {
  let core = try await makeSeededInMemoryCore()
  let seeded = try await core.createCalendarEvent(
    title: "Recurring window review",
    startDate: LorvexDateFormatters.ymd.string(from: Date()),
    endDate: nil, startTime: "15:00", endTime: "15:45", allDay: false,
    location: nil, notes: nil,
    recurrence: TaskRecurrenceRule(freq: .daily, interval: 2),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let store = AppStore(core: core, eventKitCoordinator: makeRecurrenceCoordinator())
  await store.refresh()
  let event = try #require(
    store.calendarTimeline?.events.first {
      $0.eventID == seeded.id && $0.occurrenceDate == seeded.startDate
    })

  store.prepareCalendarDraft(for: event)
  store.draftCalendarRecurrence = nil
  #expect(store.draftCalendarRecurrencePatch == .clear)
  await store.saveScopedCalendarEvent(event, scope: .allEvents)

  let updated = try #require(store.calendarTimeline?.events.first { $0.eventID == event.eventID })
  #expect(!updated.isRecurring)
  #expect(updated.recurrenceRule == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func unchangedCalendarRecurrenceProducesUnsetPatch() async throws {
  let core = try await makeSeededInMemoryCore()
  let seeded = try await core.createCalendarEvent(
    title: "Recurring window review",
    startDate: LorvexDateFormatters.ymd.string(from: Date()),
    endDate: nil, startTime: "15:00", endTime: "15:45", allDay: false,
    location: nil, notes: nil,
    recurrence: TaskRecurrenceRule(freq: .daily, interval: 1),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let store = AppStore(core: core, eventKitCoordinator: makeRecurrenceCoordinator())
  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.eventID == seeded.id })

  store.prepareCalendarDraft(for: event)
  #expect(store.draftCalendarRecurrencePatch == .unset)
}

@MainActor
@Test
func opaqueCalendarRecurrencePreservesUntilExplicitlyCleared() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeRecurrenceCoordinator())
  let futureRuleEvent = CalendarTimelineEvent(
    id: "opaque-recurrence", title: "Future cadence", source: "canonical",
    editable: true, startDate: "2026-07-06", startTime: "09:00",
    endDate: nil, endTime: "09:30", allDay: false, location: nil,
    color: nil, eventType: "event", timezone: nil, isRecurring: true,
    recurrenceRule: #"{"FREQ":"FORTNIGHTLY","X-FUTURE":true}"#)

  store.prepareCalendarDraft(for: futureRuleEvent)
  #expect(store.draftCalendarRecurrenceIsOpaque)
  #expect(store.draftCalendarRecurrence == nil)
  #expect(store.draftCalendarRecurrencePatch == .unset)

  // The Custom → None picker transition assigns nil intentionally. The value
  // is unchanged structurally, so the touched bit is what distinguishes clear.
  store.draftCalendarRecurrence = nil
  #expect(store.draftCalendarRecurrencePatch == .clear)
}

@MainActor
@Test
func calendarRepeatFrequencyChangeClearsIncompatibleAdvancedFields() {
  let referenceDate = makeDate(2026, 7, 6, 9, 0)  // Monday
  let advanced = TaskRecurrenceRule(
    freq: .monthly, interval: 2, byDay: ["1MO"], byMonth: [3],
    byMonthDay: nil, bySetPos: [1], wkst: "SU", until: "2028-12-31")

  let weekly = CalendarEventRepeatField.ruleFor(
    frequency: .weekly, from: advanced, referenceDate: referenceDate)

  #expect(weekly.freq == .weekly)
  #expect(weekly.interval == 2)
  #expect(weekly.byDay == ["MO"])
  #expect(weekly.byMonth == nil)
  #expect(weekly.byMonthDay == nil)
  #expect(weekly.bySetPos == nil)
  #expect(weekly.wkst == nil)
  #expect(weekly.until == advanced.until)

  // Re-selecting the current frequency is lossless; the basic picker must not
  // erase an advanced rule merely because its menu binding re-emits the value.
  #expect(
    CalendarEventRepeatField.ruleFor(
      frequency: .monthly, from: advanced, referenceDate: referenceDate) == advanced)
}

@MainActor
@Test
func calendarPrepareDraftSeedsRecurrenceFromEvent() async throws {
  let core = try await makeSeededInMemoryCore()
  let seeded = try await core.createCalendarEvent(
    title: "Window review", startDate: LorvexDateFormatters.ymd.string(from: Date()),
    endDate: nil, startTime: "15:00", endTime: "15:45", allDay: false,
    location: nil, notes: nil)
  let store = AppStore(core: core, eventKitCoordinator: makeRecurrenceCoordinator())
  await store.refresh()

  // A one-off event opens the Repeat row on "None".
  let oneOff = try #require(store.calendarTimeline?.events.first { $0.id == seeded.id })
  #expect(!oneOff.isRecurring)
  store.prepareCalendarDraft(for: oneOff)
  #expect(store.draftCalendarRecurrence == nil)

  // A recurring event round-trips its rule back into the draft so the editor
  // opens showing the current cadence.
  let start = makeDate(2026, 7, 13, 9, 0)
  store.beginCreateCalendarDraft()
  store.draftCalendarTitle = "Standup"
  store.draftCalendarDate = start
  store.draftCalendarStartTime = start
  store.draftCalendarEndTime = makeDate(2026, 7, 13, 9, 15)
  store.draftCalendarRecurrence = TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"])
  await store.createDraftCalendarEvent()

  let recurring = try #require(store.calendarTimeline?.events.first { $0.title == "Standup" })
  store.prepareCalendarDraft(for: recurring)
  #expect(store.draftCalendarRecurrence?.freq == .weekly)
  #expect(store.draftCalendarRecurrence?.byDay == ["MO"])
}

// MARK: - Source-scan guards

@Test
func calendarRepeatFieldEditsTypedRuleThroughCommonCases() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarEventRepeatField.swift"),
    encoding: .utf8)

  // Produces the typed rule the service accepts, not a string.
  #expect(source.contains("@Binding var recurrence: TaskRecurrenceRule?"))
  #expect(source.contains("static func ruleFor("))
  // The common cases: None + all four frequencies, weekly weekday set, monthly
  // day-of-month, and an interval.
  #expect(source.contains("case custom, none, daily, weekly, monthly, yearly"))
  #expect(source.contains("HabitWeekdayPicker("))
  #expect(source.contains("byMonthDay"))
  #expect(source.contains(".onChange(of: referenceDate)"))
  // Dot-separated accessibility identifiers.
  #expect(source.contains(#".accessibilityIdentifier("\(idPrefix).repeat")"#))
  #expect(source.contains(#".accessibilityIdentifier("\(idPrefix).repeat.interval")"#))
  #expect(source.contains(#".accessibilityIdentifier("\(idPrefix).repeat.dayOfMonth")"#))
  // Motion on state changes.
  #expect(source.contains(".animation(.snappy(duration: 0.18), value: recurrence)"))
}

@Test
func calendarAllDayPillsTintByListColorAndAreBounded() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let chrome = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridChrome.swift"),
    encoding: .utf8)
  let metrics = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridComponents.swift"),
    encoding: .utf8)

  // Task pills resolve their owning list's color instead of flat gray.
  #expect(chrome.contains("func taskColor(_ task: LorvexTask) -> Color"))
  #expect(chrome.contains("store.lists?.lists.first(where: { $0.id == listID })"))
  #expect(chrome.contains("color: taskColor(task)"))
  #expect(!chrome.contains("allDayPill(title: task.title, color: .secondary)"))
  // Event pills still reflect their event color.
  #expect(chrome.contains("color: eventColor(event)"))

  // The all-day strip is bounded: a per-column cap + a "+N more" overflow pill.
  #expect(metrics.contains("static let allDayMaxItems"))
  #expect(chrome.contains("allDayOverflowPill("))
  #expect(chrome.contains("CalendarWeekGridMetrics.allDayMaxItems"))
  #expect(chrome.contains(#".accessibilityIdentifier("calendar.allDay.overflow")"#))
}
