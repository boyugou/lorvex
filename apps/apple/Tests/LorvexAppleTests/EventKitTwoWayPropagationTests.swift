@preconcurrency import EventKit
import Foundation
import LorvexCore
import LorvexStore
import Testing

@testable import LorvexApple

// MARK: - Fake EKEventStore

/// Fake EKEventStore that records calls and returns a configurable list of
/// events. Never touches the real calendar database.
final class FakeEKEventStore: EventKitEventStoring, @unchecked Sendable {
  let backing = EKEventStore()
  var fakeEvents: [EKEvent] = []
  var savedEvents: [(EKEvent, EKSpan)] = []
  var savedEventCommitFlags: [Bool] = []
  var removedEvents: [(EKEvent, EKSpan)] = []
  var savedCalendars: [EKCalendar] = []
  var existingCalendars: [EKCalendar] = []
  var sourceList: [EKSource] = []
  var fullAccessGranted = true
  var saveError: EventKitAccessError?
  var filterEventsToPredicateWindow = false
  private var predicateWindow: (start: Date, end: Date)?
  /// EKEvents addressable by identifier. Empty by default (a real store's
  /// identifier lookup is not exercised then). Seeded to model EventKit resolving
  /// a recurring event's identifier to its first occurrence for series-scope
  /// tests: map an occurrence's `calendarItemIdentifier` to the series master.
  var itemsByIdentifier: [String: EKEvent] = [:]
  private(set) var requestFullAccessCount = 0

  func requestFullAccessToEvents() async throws -> Bool {
    requestFullAccessCount += 1
    return fullAccessGranted
  }

  func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
    if let saveError { throw saveError }
    savedEvents.append((event, span))
    savedEventCommitFlags.append(commit)
  }
  func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
    removedEvents.append((event, span))
  }
  func events(matching predicate: NSPredicate) -> [EKEvent] {
    guard filterEventsToPredicateWindow, let predicateWindow else { return fakeEvents }
    return fakeEvents.filter {
      $0.startDate < predicateWindow.end && $0.endDate > predicateWindow.start
    }
  }
  func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?)
    -> NSPredicate
  {
    predicateWindow = (startDate, endDate)
    return NSPredicate(value: true)
  }
  func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
    itemsByIdentifier[identifier]
  }
  var defaultCalendarForNewEvents: EKCalendar? { nil }
  func makeEvent() -> EKEvent { EKEvent(eventStore: backing) }

  func calendar(withIdentifier identifier: String) -> EKCalendar? {
    (existingCalendars + savedCalendars).first { $0.calendarIdentifier == identifier }
  }
  func makeCalendar() -> EKCalendar { EKCalendar(for: .event, eventStore: backing) }
  func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws { savedCalendars.append(calendar) }
  func eventCalendars() -> [EKCalendar] { existingCalendars + savedCalendars }
  var preferredCalendarSource: EKSource? { sourceList.first }
  private(set) var resetCount = 0
  func reset() { resetCount += 1 }
}

/// Thread-safe holder for the cached Lorvex-calendar identifier so the
/// `@Sendable` load/save closures can share mutable state in tests.
final class CalendarIDBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: String?
  func get() -> String? { lock.withLock { value } }
  func set(_ v: String) { lock.withLock { value = v } }
}

@Test
func liveAccessMapsExclusiveAllDayEndToLorvexInclusiveEnd() throws {
  let store = FakeEKEventStore()
  let event = store.makeEvent()
  event.isAllDay = true
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  var components = DateComponents()
  components.timeZone = calendar.timeZone
  components.year = 2030
  components.month = 5
  components.day = 24
  event.startDate = calendar.date(from: components)
  components.day = 27
  event.endDate = calendar.date(from: components)

  let fetched = LiveEventKitAccess.fetchedEvent(from: event)

  #expect(fetched.startDate == "2030-05-24")
  #expect(fetched.endDate == "2030-05-26")
  #expect(fetched.startTime == nil)
  #expect(fetched.endTime == nil)
}

@Test
func liveAccessMapsTimedEventInItsOwnTimezoneAcrossMidnight() throws {
  let store = FakeEKEventStore()
  let event = store.makeEvent()
  let reference = Date(timeIntervalSince1970: 1_900_000_000)
  let east = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
  let west = try #require(TimeZone(identifier: "Pacific/Honolulu"))
  // At least one of these fixed-offset zones differs from the test machine.
  // Choosing dynamically keeps this regression deterministic on any CI host.
  let eventTimeZone =
    east.secondsFromGMT(for: reference) != TimeZone.current.secondsFromGMT(for: reference)
    ? east : west
  event.timeZone = eventTimeZone
  event.isAllDay = false
  event.startDate = try eventKitTestDate(
    year: 2030, month: 5, day: 24, hour: 23, minute: 30, timeZone: eventTimeZone)
  event.endDate = try eventKitTestDate(
    year: 2030, month: 5, day: 25, hour: 0, minute: 30, timeZone: eventTimeZone)

  let fetched = LiveEventKitAccess.fetchedEvent(from: event)

  #expect(fetched.startDate == "2030-05-24")
  #expect(fetched.startTime == "23:30")
  #expect(fetched.endDate == "2030-05-25")
  #expect(fetched.endTime == "00:30")
  #expect(fetched.timezone == eventTimeZone.identifier)
}

@Test
func liveAccessMapsTimedEventAcrossDstGapWithoutChangingItsInstants() throws {
  let store = FakeEKEventStore()
  let event = store.makeEvent()
  let newYork = try #require(TimeZone(identifier: "America/New_York"))
  event.timeZone = newYork
  event.isAllDay = false
  // The US spring-forward gap makes this a one-hour absolute interval whose
  // local wall-clock endpoints are two hours apart.
  event.startDate = try eventKitTestDate(
    year: 2024, month: 3, day: 10, hour: 1, minute: 30, timeZone: newYork)
  event.endDate = try eventKitTestDate(
    year: 2024, month: 3, day: 10, hour: 3, minute: 30, timeZone: newYork)

  let fetched = LiveEventKitAccess.fetchedEvent(from: event)

  #expect(fetched.startDate == "2024-03-10")
  #expect(fetched.startTime == "01:30")
  #expect(fetched.endDate == "2024-03-10")
  #expect(fetched.endTime == "03:30")
  #expect(event.endDate.timeIntervalSince(event.startDate) == 60 * 60)
}

private func eventKitTestDate(
  year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZone: TimeZone
) throws -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = Locale(identifier: "en_US_POSIX")
  calendar.timeZone = timeZone
  var components = DateComponents()
  components.timeZone = timeZone
  components.year = year
  components.month = month
  components.day = day
  components.hour = hour
  components.minute = minute
  return try #require(calendar.date(from: components))
}

// MARK: - Isolated write-back into the Lorvex calendar

@Test
func liveAccessCreatesLorvexCalendarAndWritesEventThere() async throws {
  let store = FakeEKEventStore()
  let source = EKEventStore().sources.first ?? EKSource()
  store.sourceList = [source]
  let box = CalendarIDBox()
  let access = LiveEventKitAccess(
    store: store,
    loadCalendarID: { box.get() },
    saveCalendarID: { box.set($0) }
  )

  let result = try await access.upsertLorvexEvent(
    existingKey: nil, title: "Plan", start: Date(), end: Date().addingTimeInterval(1800),
    isAllDay: false, location: nil, notes: nil, recurrence: nil, lorvexEventID: "lorvex-1")

  // A dedicated "Lorvex" calendar was created, and the event landed in it.
  #expect(store.savedCalendars.count == 1)
  #expect(store.savedCalendars.first?.title == "Lorvex")
  #expect(box.get() != nil)
  #expect(store.savedEvents.count == 1)
  #expect(store.savedEvents.first?.0.calendar?.title == "Lorvex")
  #expect(!result.providerEventKey.isEmpty)
}

@Test
func liveAccessReusesCachedLorvexCalendarOnSecondWrite() async throws {
  let store = FakeEKEventStore()
  store.sourceList = [EKEventStore().sources.first ?? EKSource()]
  let box = CalendarIDBox()
  let access = LiveEventKitAccess(
    store: store, loadCalendarID: { box.get() }, saveCalendarID: { box.set($0) })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "A", start: Date(), end: Date().addingTimeInterval(600),
    isAllDay: false, location: nil, notes: nil, recurrence: nil, lorvexEventID: "lorvex-a")
  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "B", start: Date(), end: Date().addingTimeInterval(600),
    isAllDay: false, location: nil, notes: nil, recurrence: nil, lorvexEventID: "lorvex-b")

  // The calendar is created once and reused; both events land in it.
  #expect(store.savedCalendars.count == 1)
  #expect(store.savedEvents.count == 2)
}

@Test
func liveAccessWritesLorvexEventRecurrenceRule() async throws {
  let store = FakeEKEventStore()
  store.sourceList = [EKEventStore().sources.first ?? EKSource()]
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil,
    title: "Weekly planning",
    start: Date(),
    end: Date().addingTimeInterval(1800),
    isAllDay: false,
    location: nil,
    notes: nil,
    recurrence: #"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO","WE"],"COUNT":4}"#,
    lorvexEventID: "lorvex-recurring")

  let rule = try #require(store.savedEvents.first?.0.recurrenceRules?.first)
  #expect(rule.frequency == .weekly)
  #expect(rule.interval == 2)
  #expect(rule.recurrenceEnd?.occurrenceCount == 4)
  #expect(rule.daysOfTheWeek?.map { $0.dayOfTheWeek } == [.monday, .wednesday])
}

@Test
func liveAccessDeleteByMarkerRemovesMatchingEvent() async throws {
  let store = FakeEKEventStore()
  let ekEvent = EKEvent(eventStore: store.backing)
  ekEvent.notes = "lorvex-event-id:lorvex-del"
  store.fakeEvents = [ekEvent]
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  try await access.deleteLorvexEvent(lorvexEventID: "lorvex-del")
  #expect(store.removedEvents.count == 1)
  // A non-recurring mirror deletes as itself with `.thisEvent`.
  #expect(store.removedEvents.first?.0 === ekEvent)
  #expect(store.removedEvents.first?.1 == .thisEvent)
}

// MARK: - Whole-series edit / delete operate on the series, not one occurrence

/// A fresh weekly recurring EKEvent carrying the Lorvex marker for `lorvexID`.
private func makeRecurringMirror(in store: FakeEKEventStore, lorvexID: String) -> EKEvent {
  let event = store.makeEvent()
  event.title = "Weekly planning"
  event.startDate = Date()
  event.endDate = Date().addingTimeInterval(1800)
  event.notes = "Focus\n\(lorvexCalendarEventPrefix)\(lorvexID)"
  event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
  return event
}

@Test
func liveAccessDeleteByMarkerRemovesWholeRecurringSeriesWithFutureSpan() async throws {
  // The marker predicate scan yields whichever occurrence sits in its window;
  // deleting the series must normalize to the first occurrence and use
  // `.futureEvents`, else only that one occurrence is removed and the rest are
  // orphaned in the user's live calendar.
  let store = FakeEKEventStore()
  let occurrence = makeRecurringMirror(in: store, lorvexID: "lorvex-series")
  let master = makeRecurringMirror(in: store, lorvexID: "lorvex-series")
  store.fakeEvents = [occurrence]
  store.itemsByIdentifier[occurrence.calendarItemIdentifier] = master
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  try await access.deleteLorvexEvent(lorvexEventID: "lorvex-series")

  #expect(store.removedEvents.count == 1)
  #expect(store.removedEvents.first?.0 === master)
  #expect(store.removedEvents.first?.1 == .futureEvents)
}

@Test
func liveAccessDeleteByKeyRemovesWholeRecurringSeriesWithFutureSpan() async throws {
  let store = FakeEKEventStore()
  let master = makeRecurringMirror(in: store, lorvexID: "lorvex-key-series")
  // The provider key resolves directly to the recurring event via identifier
  // lookup (EventKit returns the first occurrence for a recurring identifier).
  store.itemsByIdentifier[master.calendarItemIdentifier] = master
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  try await access.deleteLorvexEvent(providerEventKey: master.calendarItemIdentifier)

  #expect(store.removedEvents.count == 1)
  #expect(store.removedEvents.first?.0 === master)
  #expect(store.removedEvents.first?.1 == .futureEvents)
}

@Test
func liveAccessEditRecurringSeriesRewritesFirstOccurrenceWithFutureSpan() async throws {
  // Editing the fields/recurrence of a recurring mirror is a whole-series edit:
  // it must rewrite the series' first occurrence with `.futureEvents` (EventKit
  // rejects `.thisEvent` once recurrence rules change, and `.thisEvent` would
  // detach a single occurrence), not re-save the scanned occurrence.
  let store = FakeEKEventStore()
  let work = store.makeCalendar()
  work.title = "Work"
  store.existingCalendars = [work]
  let occurrence = makeRecurringMirror(in: store, lorvexID: "lorvex-edit")
  occurrence.calendar = work
  let master = makeRecurringMirror(in: store, lorvexID: "lorvex-edit")
  master.calendar = work
  store.fakeEvents = [occurrence]
  store.itemsByIdentifier[occurrence.calendarItemIdentifier] = master
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "Renamed series", start: Date(),
    end: Date().addingTimeInterval(1800), isAllDay: false, location: nil, notes: nil,
    recurrence: #"{"FREQ":"DAILY"}"#, lorvexEventID: "lorvex-edit", target: .keepExisting)

  #expect(store.savedEvents.count == 1)
  #expect(store.savedEvents.first?.0 === master)
  #expect(store.savedEvents.first?.1 == .futureEvents)
  // The edit applied to the series master, and its recurrence was rewritten.
  #expect(store.savedEvents.first?.0.title == "Renamed series")
  #expect(store.savedEvents.first?.0.recurrenceRules?.first?.frequency == .daily)
}

@Test
func liveAccessPreserveNotesPatchKeepsUserTextAcrossSeriesRewrite() async throws {
  let store = FakeEKEventStore()
  let work = store.makeCalendar()
  work.title = "Work"
  store.existingCalendars = [work]
  let occurrence = makeRecurringMirror(in: store, lorvexID: "lorvex-preserve")
  occurrence.calendar = work
  occurrence.notes = "Keep this context\n\(lorvexCalendarEventPrefix)lorvex-preserve"
  let master = makeRecurringMirror(in: store, lorvexID: "lorvex-preserve")
  master.calendar = work
  master.notes = occurrence.notes
  store.fakeEvents = [occurrence]
  store.itemsByIdentifier[occurrence.calendarItemIdentifier] = master
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "Truncated series", start: Date(),
    end: Date().addingTimeInterval(1800), isAllDay: false, location: nil,
    notesPatch: .preserve, recurrence: #"{"FREQ":"DAILY","UNTIL":"2026-12-01"}"#,
    lorvexEventID: "lorvex-preserve", target: .keepExisting)

  #expect(store.savedEvents.first?.0.notes ==
    "Keep this context\n\(lorvexCalendarEventPrefix)lorvex-preserve")
}

@Test
func liveAccessAtomicallyReplacesCurrentAndFutureSeriesOccurrences() async throws {
  let store = FakeEKEventStore()
  let work = store.makeCalendar()
  work.title = "Work"
  let home = store.makeCalendar()
  home.title = "Home"
  store.existingCalendars = [work, home]
  let occurrence = makeRecurringMirror(in: store, lorvexID: "lorvex-original")
  occurrence.calendar = work
  store.fakeEvents = [occurrence]
  let replacementEvent = CalendarTimelineEvent(
    id: "lorvex-replacement", title: "New future cadence", source: "canonical",
    editable: true, startDate: "2026-08-15", startTime: "14:00",
    endDate: nil, endTime: "15:30", allDay: false, location: "Studio",
    notes: "Bring the new plan", color: nil, eventType: "event", timezone: nil,
    isRecurring: true,
    recurrenceRule: #"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["SA"]}"#)
  let replacement = try #require(
    CalendarEventExport(event: replacementEvent, notes: replacementEvent.notes))
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.replaceFutureLorvexEventSeries(
    originalLorvexEventID: "lorvex-original",
    occurrenceDate: occurrence.startDate,
    replacement: replacement,
    replacementLorvexEventID: replacementEvent.id,
    target: .calendar(id: home.calendarIdentifier))

  #expect(store.savedEvents.count == 1)
  #expect(store.savedEvents.first?.0 === occurrence)
  #expect(store.savedEvents.first?.1 == .futureEvents)
  #expect(store.savedEventCommitFlags == [true])
  #expect(store.removedEvents.isEmpty)
  #expect(occurrence.title == replacement.title)
  #expect(occurrence.startDate == replacement.startDate)
  #expect(occurrence.endDate == replacement.endDate)
  #expect(occurrence.location == replacement.location)
  #expect(occurrence.calendar?.calendarIdentifier == home.calendarIdentifier)
  #expect(
    occurrence.notes
      == "Bring the new plan\n\(lorvexCalendarEventPrefix)\(replacementEvent.id)")
  #expect(occurrence.notes?.contains("lorvex-original") == false)
  #expect(occurrence.recurrenceRules?.first?.frequency == .weekly)
  #expect(occurrence.recurrenceRules?.first?.interval == 2)
}

@Test
func liveAccessFutureSeriesSaveFailureDoesNotPersistOrRemoveAnything() async throws {
  let store = FakeEKEventStore()
  let work = store.makeCalendar()
  store.existingCalendars = [work]
  let occurrence = makeRecurringMirror(in: store, lorvexID: "lorvex-original")
  occurrence.calendar = work
  store.fakeEvents = [occurrence]
  store.saveError = .writeAccessDenied
  let replacementEvent = CalendarTimelineEvent(
    id: "lorvex-replacement", title: "Future replacement", source: "canonical",
    editable: true, startDate: "2026-08-15", startTime: "14:00",
    endDate: nil, endTime: "15:00", allDay: false, location: nil,
    notes: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: true, recurrenceRule: #"{"FREQ":"DAILY"}"#)
  let replacement = try #require(CalendarEventExport(event: replacementEvent, notes: nil))
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  await #expect(throws: EventKitAccessError.writeAccessDenied) {
    _ = try await access.replaceFutureLorvexEventSeries(
      originalLorvexEventID: "lorvex-original",
      occurrenceDate: occurrence.startDate,
      replacement: replacement,
      replacementLorvexEventID: replacementEvent.id,
      target: .keepExisting)
  }

  #expect(store.savedEvents.isEmpty)
  #expect(store.removedEvents.isEmpty)
}

@Test
func liveAccessFailsClosedWhenOriginalMirrorCannotBeResolved() async throws {
  let store = FakeEKEventStore()
  let home = store.makeCalendar()
  store.existingCalendars = [home]
  let replacementEvent = CalendarTimelineEvent(
    id: "lorvex-replacement", title: "Recovered future series", source: "canonical",
    editable: true, startDate: "2026-08-15", startTime: "14:00",
    endDate: nil, endTime: "15:00", allDay: false, location: nil,
    notes: "Recovered", color: nil, eventType: "event", timezone: nil,
    isRecurring: true, recurrenceRule: #"{"FREQ":"DAILY"}"#)
  let replacement = try #require(
    CalendarEventExport(event: replacementEvent, notes: replacementEvent.notes))
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  await #expect(
    throws: EventKitAccessError.originalMirrorOccurrenceUnresolved(
      eventID: "missing-original")
  ) {
    _ = try await access.replaceFutureLorvexEventSeries(
      originalLorvexEventID: "missing-original",
      occurrenceDate: Date(),
      replacement: replacement,
      replacementLorvexEventID: replacementEvent.id,
      target: .calendar(id: home.calendarIdentifier))
  }

  #expect(store.savedEvents.isEmpty)
  #expect(store.savedCalendars.isEmpty)
  #expect(store.removedEvents.isEmpty)
}

@Test
func liveAccessFailsClosedWhenMarkedSeriesFallsOutsideOccurrenceWindow() async throws {
  let store = FakeEKEventStore()
  store.filterEventsToPredicateWindow = true
  let originalOccurrenceDate = Date()
  let movedOccurrence = makeRecurringMirror(in: store, lorvexID: "lorvex-original")
  movedOccurrence.startDate = originalOccurrenceDate.addingTimeInterval(3 * 24 * 60 * 60)
  movedOccurrence.endDate = movedOccurrence.startDate.addingTimeInterval(30 * 60)
  store.fakeEvents = [movedOccurrence]
  let replacementEvent = CalendarTimelineEvent(
    id: "lorvex-replacement", title: "Future replacement", source: "canonical",
    editable: true, startDate: "2026-08-15", startTime: "14:00",
    endDate: nil, endTime: "15:00", allDay: false, location: nil,
    notes: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: true, recurrenceRule: #"{"FREQ":"DAILY"}"#)
  let replacement = try #require(CalendarEventExport(event: replacementEvent, notes: nil))
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  await #expect(
    throws: EventKitAccessError.originalMirrorOccurrenceUnresolved(
      eventID: "lorvex-original")
  ) {
    _ = try await access.replaceFutureLorvexEventSeries(
      originalLorvexEventID: "lorvex-original",
      occurrenceDate: originalOccurrenceDate,
      replacement: replacement,
      replacementLorvexEventID: replacementEvent.id,
      target: .keepExisting)
  }

  #expect(store.savedEvents.isEmpty)
  #expect(store.savedCalendars.isEmpty)
  #expect(store.removedEvents.isEmpty)
}

@Test
func liveAccessCreateRecurringUsesThisEventSpan() async throws {
  // Creating a brand-new recurring mirror (no reuse) saves with `.thisEvent`:
  // there is no existing series to span, and EventKit needs `.thisEvent` for a
  // new event.
  let store = FakeEKEventStore()
  store.sourceList = [EKEventStore().sources.first ?? EKSource()]
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "New standup", start: Date(),
    end: Date().addingTimeInterval(900), isAllDay: false, location: nil, notes: nil,
    recurrence: #"{"FREQ":"WEEKLY"}"#, lorvexEventID: "lorvex-new-series")

  #expect(store.savedEvents.count == 1)
  #expect(store.savedEvents.first?.1 == .thisEvent)
}

@Test
func liveAccessListsUserCalendarsForSettingsFilter() async throws {
  let store = FakeEKEventStore()
  let workCalendar = store.makeCalendar()
  workCalendar.title = "Work"
  let lorvexCalendar = store.makeCalendar()
  lorvexCalendar.title = "Lorvex"
  store.existingCalendars = [lorvexCalendar, workCalendar]
  let box = CalendarIDBox()
  box.set(lorvexCalendar.calendarIdentifier)
  let access = LiveEventKitAccess(
    store: store,
    loadCalendarID: { box.get() },
    saveCalendarID: { box.set($0) },
    readAuthorizationProvider: { store.fullAccessGranted })

  let calendars = try await access.availableCalendars()

  #expect(store.requestFullAccessCount == 0)
  #expect(calendars == [
    EventKitCalendarDescriptor(
      id: workCalendar.calendarIdentifier,
      title: "Work",
      sourceTitle: nil)
  ])
}

@Test
func liveAccessAvailableCalendarsDoesNotPromptWhenUnauthorized() async throws {
  let store = FakeEKEventStore()
  store.fullAccessGranted = false
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  await #expect(throws: EventKitAccessError.readAccessDenied) {
    _ = try await access.availableCalendars()
  }
  #expect(store.requestFullAccessCount == 0)
}

// MARK: - Writable-calendar picker + calendar targeting

@Test
func liveAccessWritableCalendarsListsWritableUserCalendarsWithColor() async throws {
  let store = FakeEKEventStore()
  let work = store.makeCalendar()
  work.title = "Work"
  work.color = .systemGreen
  let lorvex = store.makeCalendar()
  lorvex.title = "Lorvex"
  store.existingCalendars = [lorvex, work]
  let box = CalendarIDBox()
  box.set(lorvex.calendarIdentifier)
  let access = LiveEventKitAccess(
    store: store,
    loadCalendarID: { box.get() },
    saveCalendarID: { box.set($0) },
    readAuthorizationProvider: { store.fullAccessGranted })

  let calendars = try await access.writableCalendars()

  // The dedicated Lorvex calendar is excluded (it is the picker's default), and
  // the writable user calendar carries its color for the picker dot.
  #expect(calendars.map(\.title) == ["Work"])
  #expect(calendars.first?.colorHex != nil)
}

@Test
func liveAccessWritesNewEventIntoChosenCalendar() async throws {
  let store = FakeEKEventStore()
  store.sourceList = [EKEventStore().sources.first ?? EKSource()]
  let work = store.makeCalendar()
  work.title = "Work"
  store.existingCalendars = [work]
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "Plan", start: Date(), end: Date().addingTimeInterval(1800),
    isAllDay: false, location: nil, notes: nil, recurrence: nil, lorvexEventID: "lorvex-target",
    target: .calendar(id: work.calendarIdentifier))

  // The event landed in the chosen calendar; no dedicated Lorvex calendar was
  // created because the target was an existing writable one.
  #expect(store.savedEvents.first?.0.calendar?.calendarIdentifier == work.calendarIdentifier)
  #expect(store.savedCalendars.isEmpty)
}

@Test
func liveAccessKeepExistingLeavesReusedEventInItsCalendar() async throws {
  let store = FakeEKEventStore()
  let work = store.makeCalendar()
  work.title = "Work"
  store.existingCalendars = [work]
  let existing = EKEvent(eventStore: store.backing)
  existing.notes = "lorvex-event-id:lorvex-keep"
  existing.calendar = work
  store.fakeEvents = [existing]
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "Moved time", start: Date(), end: Date().addingTimeInterval(600),
    isAllDay: false, location: nil, notes: nil, recurrence: nil, lorvexEventID: "lorvex-keep",
    target: .keepExisting)

  // A drag-reschedule reuses the existing mirror in place — it neither creates a
  // new event nor relocates it to the Lorvex calendar.
  #expect(store.savedEvents.count == 1)
  #expect(store.savedEvents.first?.0.calendar?.calendarIdentifier == work.calendarIdentifier)
  #expect(store.savedCalendars.isEmpty)
}

@Test
func liveAccessMovesReusedEventToChosenCalendar() async throws {
  let store = FakeEKEventStore()
  store.sourceList = [EKEventStore().sources.first ?? EKSource()]
  let work = store.makeCalendar()
  work.title = "Work"
  let home = store.makeCalendar()
  home.title = "Home"
  store.existingCalendars = [work, home]
  let existing = EKEvent(eventStore: store.backing)
  existing.notes = "lorvex-event-id:lorvex-move"
  existing.calendar = work
  store.fakeEvents = [existing]
  let access = LiveEventKitAccess(
    store: store, readAuthorizationProvider: { store.fullAccessGranted })

  _ = try await access.upsertLorvexEvent(
    existingKey: nil, title: "Rehome", start: Date(), end: Date().addingTimeInterval(600),
    isAllDay: false, location: nil, notes: nil, recurrence: nil, lorvexEventID: "lorvex-move",
    target: .calendar(id: home.calendarIdentifier))

  // Editing the calendar of an existing event reuses the marker event and moves
  // it into the chosen calendar rather than orphaning it and writing a duplicate.
  #expect(store.savedEvents.count == 1)
  #expect(store.savedEvents.first?.0 === existing)
  #expect(store.savedEvents.first?.0.calendar?.calendarIdentifier == home.calendarIdentifier)
}

@Test
func liveAccessRequestAccessDoesNotPromptWhenAlreadyAuthorized() async throws {
  let store = FakeEKEventStore()
  let access = LiveEventKitAccess(
    store: store,
    authorizationStatusProvider: { .fullAccess },
    readAuthorizationProvider: { true })

  let granted = try await access.requestAccess()

  #expect(granted == true)
  #expect(store.requestFullAccessCount == 0)
}

@Test
func liveAccessRequestAccessDoesNotPromptWhenDenied() async throws {
  let store = FakeEKEventStore()
  store.fullAccessGranted = true
  let access = LiveEventKitAccess(
    store: store,
    authorizationStatusProvider: { .denied },
    readAuthorizationProvider: { false })

  let granted = try await access.requestAccess()

  #expect(granted == false)
  #expect(store.requestFullAccessCount == 0)
}

@Test
func liveAccessRequestAccessPromptsOnlyWhenUndecided() async throws {
  let store = FakeEKEventStore()
  store.fullAccessGranted = true
  let access = LiveEventKitAccess(
    store: store,
    authorizationStatusProvider: { .notDetermined },
    readAuthorizationProvider: { false })

  let granted = try await access.requestAccess()

  #expect(granted == true)
  #expect(store.requestFullAccessCount == 1)
}

@Test
func liveAccessGrantLatchesAndResetsStore() async throws {
  // A fresh grant (notDetermined -> granted) must persist the confirmed-access
  // latch and reset the store so the launch-time instance sees the new access.
  let store = FakeEKEventStore()
  store.fullAccessGranted = true
  let latch = CalendarIDBox()  // reused as a thread-safe bool holder via "1"
  let access = LiveEventKitAccess(
    store: store,
    authorizationStatusProvider: { .notDetermined },
    readAuthorizationProvider: { false },
    loadConfirmedReadAccess: { latch.get() == "1" },
    saveConfirmedReadAccess: { latch.set($0 ? "1" : "0") })

  let granted = try await access.requestAccess()

  #expect(granted == true)
  #expect(store.resetCount == 1)
  #expect(latch.get() == "1")
}

@Test
func liveAccessReadAuthorizedTrustsLatchOnStaleNotDetermined() {
  // Static status stuck at notDetermined after a grant, but the latch is set:
  // reads must stay authorized (no regression to "denied" mid-session).
  let store = FakeEKEventStore()
  let access = LiveEventKitAccess(
    store: store,
    authorizationStatusProvider: { .notDetermined },
    readAuthorizationProvider: { false },
    loadConfirmedReadAccess: { true })
  #expect(access.isReadAuthorized() == true)
}

@Test
func liveAccessReadAuthorizedRespectsRealDenialOverLatch() {
  // A genuine denial is never overridden by the latch.
  let store = FakeEKEventStore()
  let access = LiveEventKitAccess(
    store: store,
    authorizationStatusProvider: { .denied },
    readAuthorizationProvider: { false },
    loadConfirmedReadAccess: { true })
  #expect(access.isReadAuthorized() == false)
}

@Test
func liveAccessAppliesIncludedCalendarFilterBeforeIngest() async throws {
  let store = FakeEKEventStore()
  let workCalendar = store.makeCalendar()
  workCalendar.title = "Work"
  let personalCalendar = store.makeCalendar()
  personalCalendar.title = "Personal"
  let workEvent = store.makeEvent()
  workEvent.title = "Design review"
  workEvent.startDate = Date()
  workEvent.endDate = Date().addingTimeInterval(1800)
  workEvent.calendar = workCalendar
  let personalEvent = store.makeEvent()
  personalEvent.title = "Dinner"
  personalEvent.startDate = Date()
  personalEvent.endDate = Date().addingTimeInterval(1800)
  personalEvent.calendar = personalCalendar
  store.fakeEvents = [workEvent, personalEvent]
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  let fetched = try await access.fetchEvents(
    start: Date().addingTimeInterval(-60),
    end: Date().addingTimeInterval(3600),
    windowEndDay: "2026-07-21",
    calendarFilter: EventKitCalendarFilter(
      includedCalendarIDs: [workCalendar.calendarIdentifier],
      excludedCalendarIDs: []))

  #expect(fetched.map(\.title) == ["Design review"])
}

@Test
func liveAccessAppliesExcludedCalendarFilterBeforeIngest() async throws {
  let store = FakeEKEventStore()
  let visibleCalendar = store.makeCalendar()
  visibleCalendar.title = "Visible"
  let hiddenCalendar = store.makeCalendar()
  hiddenCalendar.title = "Hidden"
  let visibleEvent = store.makeEvent()
  visibleEvent.title = "Planning"
  visibleEvent.startDate = Date()
  visibleEvent.endDate = Date().addingTimeInterval(1800)
  visibleEvent.calendar = visibleCalendar
  let hiddenEvent = store.makeEvent()
  hiddenEvent.title = "Private"
  hiddenEvent.startDate = Date()
  hiddenEvent.endDate = Date().addingTimeInterval(1800)
  hiddenEvent.calendar = hiddenCalendar
  store.fakeEvents = [visibleEvent, hiddenEvent]
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  let fetched = try await access.fetchEvents(
    start: Date().addingTimeInterval(-60),
    end: Date().addingTimeInterval(3600),
    windowEndDay: "2026-07-21",
    calendarFilter: EventKitCalendarFilter(
      includedCalendarIDs: [],
      excludedCalendarIDs: [hiddenCalendar.calendarIdentifier]))

  #expect(fetched.map(\.title) == ["Planning"])
}

@Test
func liveAccessFetchSkipsLorvexAuthoredEventsByMarkerWhenCalendarIDUnknown() async throws {
  let store = FakeEKEventStore()
  let externalCalendar = store.makeCalendar()
  externalCalendar.title = "Work"

  let externalEvent = store.makeEvent()
  externalEvent.title = "Design review"
  externalEvent.startDate = Date()
  externalEvent.endDate = Date().addingTimeInterval(1800)
  externalEvent.calendar = externalCalendar

  // A Lorvex-authored event that synced down to this Mac via iCloud: this device
  // never cached the Lorvex calendar's id, but the event carries the marker.
  let lorvexAuthored = store.makeEvent()
  lorvexAuthored.title = "Lorvex task block"
  lorvexAuthored.startDate = Date()
  lorvexAuthored.endDate = Date().addingTimeInterval(1800)
  lorvexAuthored.calendar = externalCalendar
  lorvexAuthored.notes = "Focus time\n\(lorvexCalendarEventPrefix)lorvex-xyz"
  store.fakeEvents = [externalEvent, lorvexAuthored]

  // Default loadCalendarID is nil, so the calendar-id exclusion can't fire —
  // only the marker keeps the Lorvex-authored event from being re-ingested.
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  let fetched = try await access.fetchEvents(
    start: Date().addingTimeInterval(-60),
    end: Date().addingTimeInterval(3600),
    windowEndDay: "2026-07-21")

  #expect(fetched.map(\.title) == ["Design review"])
}

// MARK: - Coordinator write-back binds a link row

@Test
func coordinatorWriteBackCreatesLinkRow() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: access, provider: provider, loadAccessMode: { .busyOnly }, isEnabled: { true })

  let key = try await coordinator.writeBack(
    taskID: "task-1", existingKey: nil, lorvexEventID: "lorvex-1",
    title: "Block", start: Date(), end: Date().addingTimeInterval(1800),
    isAllDay: false, location: nil, notes: nil)

  let links = provider.recordedLinks()
  #expect(links.count == 1)
  #expect(links.first?.taskID == "task-1")
  #expect(links.first?.key == key)
}

@Test
func coordinatorRemoveWriteBackDeletesEventAndUnbinds() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: access, provider: provider, loadAccessMode: { .busyOnly }, isEnabled: { true })
  _ = try await coordinator.writeBack(
    taskID: "task-1", existingKey: nil, lorvexEventID: "lorvex-1",
    title: "Block", start: Date(), end: Date().addingTimeInterval(1800),
    isAllDay: false, location: nil, notes: nil)

  try await coordinator.removeWriteBack(taskID: "task-1", lorvexEventID: "lorvex-1")

  #expect(provider.recordedLinks().isEmpty)
  let deletes = await access.recordedDeletes()
  #expect(deletes.count == 1)
}

// MARK: - Authorization helper

@Test
func authorizationHelperNeedsSettingsRecoveryForDenied() {
  let helper = EventKitAuthorizationHelper(statusProvider: { _ in .denied })
  #expect(helper.needsSettingsRecovery == true)
}

@Test
func authorizationHelperNeedsSettingsRecoveryForRestricted() {
  let helper = EventKitAuthorizationHelper(statusProvider: { _ in .restricted })
  #expect(helper.needsSettingsRecovery == true)
}

@Test
func authorizationHelperNoRecoveryForNotDetermined() {
  let helper = EventKitAuthorizationHelper(statusProvider: { _ in .notDetermined })
  #expect(helper.needsSettingsRecovery == false)
}

@Test
func authorizationHelperIsAuthorizedForFullAccess() {
  let helper = EventKitAuthorizationHelper(statusProvider: { _ in .fullAccess })
  #expect(helper.isAuthorized == true)
  #expect(helper.needsSettingsRecovery == false)
}

// MARK: - Change observer

@Test
func changeObserverCallsRefreshClosureOnNotification() async {
  actor Counter {
    var value = 0
    func increment() { value += 1 }
  }
  let counter = Counter()
  let observer = EventKitChangeObserver { await counter.increment() }
  let task = Task { await observer.observe() }
  try? await Task.sleep(nanoseconds: 10_000_000)
  NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
  NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
  try? await Task.sleep(nanoseconds: 50_000_000)
  task.cancel()
  let count = await counter.value
  #expect(count >= 1)
}
