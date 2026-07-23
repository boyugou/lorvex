@preconcurrency import EventKit
import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func scopedMirrorDate(
  _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
) throws -> Date {
  var components = DateComponents()
  components.calendar = Calendar.current
  components.timeZone = Calendar.current.timeZone
  components.year = year
  components.month = month
  components.day = day
  components.hour = hour
  components.minute = minute
  return try #require(components.date)
}

private func scopedMirrorCoordinator(
  access: FakeEventKitAccess
) -> EventKitCoordinator {
  EventKitCoordinator(
    access: access,
    provider: FakeEventKitProvider(),
    loadAccessMode: { .busyOnly },
    isEnabled: { true })
}

@Test
func eventKitCoordinatorRemovesSingleLorvexOccurrence() async throws {
  let access = FakeEventKitAccess()
  let coordinator = scopedMirrorCoordinator(access: access)
  let occurrenceDate = try scopedMirrorDate(2026, 6, 23, 15)

  try await coordinator.removeOccurrenceWriteBack(
    lorvexEventID: "event-recurring", occurrenceDate: occurrenceDate)

  let removals = await access.recordedOccurrenceRemovals()
  #expect(removals.count == 1)
  #expect(removals.first?.lorvexID == "event-recurring")
  #expect(removals.first?.occurrenceDate == occurrenceDate)
}

@Test
func eventKitCoordinatorRemovesCurrentAndFutureLorvexOccurrences() async throws {
  let access = FakeEventKitAccess()
  let coordinator = scopedMirrorCoordinator(access: access)
  let occurrenceDate = try scopedMirrorDate(2026, 6, 23, 15)

  try await coordinator.removeFutureWriteBack(
    lorvexEventID: "event-recurring", occurrenceDate: occurrenceDate)

  let removals = await access.recordedFutureSeriesRemovals()
  #expect(removals.count == 1)
  #expect(removals.first?.lorvexID == "event-recurring")
  #expect(removals.first?.occurrenceDate == occurrenceDate)
}

@MainActor
@Test
func appStoreThisEventDeleteMirrorsOccurrenceRemoval() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let event = CalendarTimelineEvent(
    id: "a1de73f5-4de1-4c8e-9db1-1af6f1f2b101",
    title: "Weekly planning",
    source: "canonical",
    editable: true,
    startDate: "2026-06-23",
    startTime: "15:00",
    endDate: nil,
    endTime: "15:30",
    allDay: false,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: nil,
    isRecurring: true,
    recurrenceRule: #"{"FREQ":"WEEKLY"}"#)

  // The stored row must itself be recurring — the scoped-edit paths read the
  // stored recurrence, not the passed-in value object.
  _ = try await store.core.importCalendarEvent(
    id: event.id,
    title: event.title,
    startDate: event.startDate,
    startTime: event.startTime,
    endDate: event.endDate,
    endTime: event.endTime,
    allDay: event.allDay,
    location: event.location,
    notes: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil, timezone: nil, recurrence: event.recurrenceRule,
    seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
    recurrenceGeneration: nil, seriesCutoverId: nil)

  await store.deleteScopedCalendarEvent(event, scope: .thisEvent)

  let removals = await access.recordedOccurrenceRemovals()
  let expectedDate = try scopedMirrorDate(2026, 6, 23, 15)
  #expect(removals.count == 1)
  #expect(removals.first?.lorvexID == "a1de73f5-4de1-4c8e-9db1-1af6f1f2b101")
  #expect(removals.first?.occurrenceDate == expectedDate)
}

@MainActor
@Test
func appStoreThisEventEditMirrorsOccurrenceRemoval() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let event = CalendarTimelineEvent(
    id: "b2ef84a6-5ef2-4d9f-8ec2-2ba7a2a3c202",
    title: "Weekly planning",
    source: "canonical",
    editable: true,
    startDate: "2026-06-24",
    startTime: "10:00",
    endDate: nil,
    endTime: "10:30",
    allDay: false,
    location: nil,
    color: nil,
    eventType: "event",
    timezone: nil,
    isRecurring: true,
    recurrenceRule: #"{"FREQ":"WEEKLY"}"#)

  // The stored row must itself be recurring — the scoped-edit paths read the
  // stored recurrence, not the passed-in value object.
  _ = try await store.core.importCalendarEvent(
    id: event.id,
    title: event.title,
    startDate: event.startDate,
    startTime: event.startTime,
    endDate: event.endDate,
    endTime: event.endTime,
    allDay: event.allDay,
    location: event.location,
    notes: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil, timezone: nil, recurrence: event.recurrenceRule,
    seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
    recurrenceGeneration: nil, seriesCutoverId: nil)
  store.draftCalendarTitle = "Moved planning"
  store.draftCalendarDate = try scopedMirrorDate(2026, 6, 24)
  store.draftCalendarStartTime = try scopedMirrorDate(2026, 6, 24, 11)
  store.draftCalendarEndTime = try scopedMirrorDate(2026, 6, 24, 11, 30)

  await store.saveScopedCalendarEvent(event, scope: .thisEvent)

  let removals = await access.recordedOccurrenceRemovals()
  let expectedDate = try scopedMirrorDate(2026, 6, 24, 10)
  #expect(removals.count == 1)
  #expect(removals.first?.lorvexID == "b2ef84a6-5ef2-4d9f-8ec2-2ba7a2a3c202")
  #expect(removals.first?.occurrenceDate == expectedDate)
}

@MainActor
@Test
func appStoreScopedEditDoesNotRemoveOccurrenceWhenReplacementWriteFails() async throws {
  let access = FakeEventKitAccess()
  await access.setUpsertError(.writeAccessDenied)
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let event = CalendarTimelineEvent(
    id: "c3f095b7-6f03-4eaf-9fd3-3cb8b3b4d303",
    title: "Weekly planning", source: "canonical", editable: true,
    startDate: "2026-06-24", startTime: "10:00", endDate: nil,
    endTime: "10:30", allDay: false, location: nil, color: nil,
    eventType: "event", timezone: nil, isRecurring: true,
    recurrenceRule: #"{"FREQ":"WEEKLY"}"#)
  _ = try await store.core.importCalendarEvent(
    id: event.id, title: event.title, startDate: event.startDate,
    startTime: event.startTime, endDate: event.endDate, endTime: event.endTime,
    allDay: event.allDay, location: nil, notes: nil, url: nil, color: nil,
    eventType: nil, personName: nil, attendees: nil, timezone: nil,
    recurrence: event.recurrenceRule, seriesId: nil, recurrenceInstanceDate: nil,
    occurrenceState: nil, recurrenceGeneration: nil, seriesCutoverId: nil)
  store.prepareCalendarDraft(for: event)
  store.draftCalendarTitle = "Replacement that cannot mirror"

  await store.saveScopedCalendarEvent(event, scope: .thisEvent)

  #expect(await access.recordedWrites().isEmpty)
  #expect(await access.recordedOccurrenceRemovals().isEmpty)
  #expect(store.lastCalendarExportReport.status == .failed)
}

@MainActor
@Test
func appStoreOverrideAddressedEditRemovesOccurrenceFromMasterMirror() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let masterID = "d401a6c8-7014-4fb0-a0e4-4dc9c4c5e404"
  _ = try await store.core.importCalendarEvent(
    id: masterID, title: "Daily planning", startDate: "2026-06-22",
    startTime: "10:00", endDate: nil, endTime: "10:30", allDay: false,
    location: nil, notes: nil, url: nil, color: nil, eventType: nil,
    personName: nil, attendees: nil, timezone: nil,
    recurrence: #"{"FREQ":"DAILY"}"#, seriesId: nil, recurrenceInstanceDate: nil,
    occurrenceState: nil, recurrenceGeneration: nil, seriesCutoverId: nil)
  let first = try await store.core.editScopedCalendarEvent(
    eventID: masterID, occurrenceDate: "2026-06-24", scope: "this_only",
    updates: ScopedCalendarEventUpdates(title: "First override"))
  let override = try #require(first.replacementEvent)
  store.prepareCalendarDraft(for: override)
  store.draftCalendarTitle = "Re-edited override"

  await store.saveScopedCalendarEvent(override, scope: .thisEvent)

  let removal = try #require(await access.recordedOccurrenceRemovals().last)
  #expect(removal.lorvexID == masterID)
}

@MainActor
@Test
func appStoreReplacementDeleteRemovesOneOffAndMasterOccurrenceMirrors() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let masterID = "e512b7d9-8125-40c1-b1f5-5ed0d5d6f505"
  _ = try await store.core.importCalendarEvent(
    id: masterID, title: "Daily planning", startDate: "2026-06-22",
    startTime: "10:00", endDate: nil, endTime: "10:30", allDay: false,
    location: nil, notes: nil, url: nil, color: nil, eventType: nil,
    personName: nil, attendees: nil, timezone: nil,
    recurrence: #"{"FREQ":"DAILY"}"#, seriesId: nil, recurrenceInstanceDate: nil,
    occurrenceState: nil, recurrenceGeneration: nil, seriesCutoverId: nil)
  let edit = try await store.core.editScopedCalendarEvent(
    eventID: masterID, occurrenceDate: "2026-06-24", scope: "this_only",
    updates: ScopedCalendarEventUpdates(title: "One-off planning"))
  let replacement = try #require(edit.replacementEvent)

  await store.deleteScopedCalendarEvent(replacement, scope: .thisEvent)

  #expect(await access.recordedDeletes().contains(replacement.id))
  let removal = try #require(await access.recordedOccurrenceRemovals().last)
  #expect(removal.lorvexID == masterID)
  #expect(replacement.eventID == masterID)
}

@MainActor
@Test
func appStoreReplacementResolvesItsOwnEventKitCalendar() async throws {
  let access = FakeEventKitAccess()
  await access.setLorvexEventCalendarID("work-calendar")
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let replacement = CalendarTimelineEvent(
    id: "replacement-id", eventID: "series-id", seriesID: "series-id",
    recurrenceGeneration: "1000-0-device", occurrenceDate: "2026-06-24",
    occurrenceState: .replacement,
    title: "Moved planning", source: "canonical", editable: true,
    startDate: "2026-06-26", startTime: "10:00", endDate: nil, endTime: "10:30",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  store.calendarTimeline = CalendarTimelineSnapshot(
    from: "2026-06-22", to: "2026-06-28", events: [replacement], truncated: false,
    nextOffset: nil)
  store.selectCalendarEvent(replacement)

  await store.resolveDraftTargetCalendar(for: replacement)

  #expect(await access.recordedCalendarIDLookups() == [replacement.id])
  #expect(store.draftCalendarTargetCalendarID == "work-calendar")
}

@MainActor
@Test
func appStoreEditAllRemovesEveryInvalidatedReplacementMirror() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: scopedMirrorCoordinator(access: access))
  let master = try await store.core.createCalendarEvent(
    title: "Daily planning", startDate: "2026-06-22", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let first = try await store.core.editScopedCalendarEvent(
    eventID: master.eventID, occurrenceDate: "2026-06-23", scope: "this_only",
    updates: ScopedCalendarEventUpdates(title: "First one-off"))
  let second = try await store.core.editScopedCalendarEvent(
    eventID: master.eventID, occurrenceDate: "2026-06-24", scope: "this_only",
    updates: ScopedCalendarEventUpdates(title: "Second one-off"))
  let firstID = try #require(first.replacementEvent?.id)
  let secondID = try #require(second.replacementEvent?.id)
  store.prepareCalendarDraft(for: master)
  store.draftCalendarTitle = "Reset planning"

  await store.saveScopedCalendarEvent(master, scope: .allEvents)

  #expect(Set(await access.recordedDeletes()) == Set([firstID, secondID]))
}

@MainActor
@Test
func appStoreFollowingEditUsesOneAtomicFutureSeriesReplacement() async throws {
  let access = FakeEventKitAccess()
  let core = try await makeSeededInMemoryCore()
  let master = try await core.createCalendarEvent(
    title: "Daily planning", startDate: "2026-07-01", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: "Keep existing EventKit notes",
    recurrence: TaskRecurrenceRule(freq: .daily), timezone: nil, url: nil,
    color: nil, eventType: nil, personName: nil, attendees: nil)
  let occurrence = try #require(
    try await core.loadCalendarTimeline(from: "2026-07-02", to: "2026-07-02")
      .events.first { $0.source == "canonical" && $0.occurrenceDate == "2026-07-02" })
  let store = AppStore(
    core: core, eventKitCoordinator: scopedMirrorCoordinator(access: access))
  store.prepareCalendarDraft(for: occurrence)
  store.draftCalendarTitle = "New cadence"

  await store.saveScopedCalendarEvent(occurrence, scope: .thisAndFollowing)

  let calls = await access.recordedFutureSeriesReplacements()
  let call = try #require(calls.first)
  let expectedOccurrenceDate = try scopedMirrorDate(2026, 7, 2, 10)
  #expect(calls.count == 1)
  #expect(call.originalLorvexEventID == master.eventID)
  #expect(call.occurrenceDate == expectedOccurrenceDate)
  #expect(call.replacementLorvexEventID != master.eventID)
  #expect(call.replacement.title == "New cadence")
  #expect(call.replacement.notes == "Keep existing EventKit notes")
  #expect(call.replacement.recurrence?.contains(#""FREQ":"DAILY""#) == true)
  #expect(call.target == .lorvexDefault)
  #expect(await access.recordedWrites().isEmpty)
  #expect(await access.recordedDeletes().isEmpty)
  #expect(await access.recordedOccurrenceRemovals().isEmpty)
  #expect(store.lastCalendarExportReport.status == .succeeded)
}

@MainActor
@Test
func appStoreNestedFollowingEditTargetsTheAddressedSegmentMirror() async throws {
  let access = FakeEventKitAccess()
  let core = try await makeSeededInMemoryCore()
  let root = try await core.createCalendarEvent(
    title: "Root cadence", startDate: "2026-08-01", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let firstSplit = try await core.editScopedCalendarEvent(
    eventID: root.eventID, occurrenceDate: "2026-08-03", scope: "this_and_following",
    updates: ScopedCalendarEventUpdates(title: "First segment"))
  let firstTail = try #require(firstSplit.replacementEvent)
  _ = try await core.editScopedCalendarEvent(
    eventID: firstTail.eventID, occurrenceDate: "2026-08-07", scope: "this_and_following",
    updates: ScopedCalendarEventUpdates(title: "Later segment"))
  let nestedOccurrence = try #require(
    try await core.loadCalendarTimeline(from: "2026-08-04", to: "2026-08-04")
      .events.first {
        $0.source == "canonical" && $0.eventID == firstTail.eventID
          && $0.occurrenceDate == "2026-08-04"
      })
  let store = AppStore(
    core: core, eventKitCoordinator: scopedMirrorCoordinator(access: access))
  store.prepareCalendarDraft(for: nestedOccurrence)
  store.draftCalendarTitle = "Nested segment"

  await store.saveScopedCalendarEvent(nestedOccurrence, scope: .thisAndFollowing)

  let calls = await access.recordedFutureSeriesReplacements()
  let call = try #require(calls.first)
  let expectedOccurrenceDate = try scopedMirrorDate(2026, 8, 4, 10)
  #expect(calls.count == 1)
  #expect(call.originalLorvexEventID == firstTail.eventID)
  #expect(call.replacementLorvexEventID != firstTail.eventID)
  #expect(call.replacement.title == "Nested segment")
  #expect(call.occurrenceDate == expectedOccurrenceDate)
  #expect(call.replacement.recurrence?.contains(#""UNTIL":"2026-08-06""#) == true)
  #expect(call.replacement.recurrence?.contains(#""COUNT""#) == false)
  let storedReplacement = try #require(
    try await core.getCalendarEvent(id: call.replacementLorvexEventID))
  #expect(storedReplacement.recurrenceRule?.contains(#""UNTIL""#) == false)
}

@MainActor
@Test
func appStoreAllInCurrentSegmentClipsRootAndMiddleEventKitMirrorsOnly() async throws {
  let access = FakeEventKitAccess()
  let core = try await makeSeededInMemoryCore()
  let root = try await core.createCalendarEvent(
    title: "Root cadence", startDate: "2026-10-01", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let firstSplit = try await core.editScopedCalendarEvent(
    eventID: root.eventID, occurrenceDate: "2026-10-03", scope: "this_and_following",
    updates: ScopedCalendarEventUpdates(title: "Middle cadence"))
  let middle = try #require(firstSplit.replacementEvent)
  _ = try await core.editScopedCalendarEvent(
    eventID: middle.eventID, occurrenceDate: "2026-10-07", scope: "this_and_following",
    updates: ScopedCalendarEventUpdates(title: "Last cadence"))
  let store = AppStore(
    core: core, eventKitCoordinator: scopedMirrorCoordinator(access: access))

  store.prepareCalendarDraft(for: root)
  store.draftCalendarTitle = "Edited root"
  await store.saveScopedCalendarEvent(root, scope: .allEvents)
  store.prepareCalendarDraft(for: middle)
  store.draftCalendarTitle = "Edited middle"
  await store.saveScopedCalendarEvent(middle, scope: .allEvents)

  let recurrences = await access.recordedWriteRecurrences()
  #expect(recurrences.count == 2)
  #expect(recurrences[0]?.contains(#""UNTIL":"2026-10-02""#) == true)
  #expect(recurrences[1]?.contains(#""UNTIL":"2026-10-06""#) == true)
  let storedRoot = try #require(try await core.getCalendarEvent(id: root.eventID))
  let storedMiddle = try #require(try await core.getCalendarEvent(id: middle.eventID))
  #expect(storedRoot.recurrenceRule?.contains(#""UNTIL""#) == false)
  #expect(storedMiddle.recurrenceRule?.contains(#""UNTIL""#) == false)
}

@MainActor
@Test
func appStoreFollowingEditFailureDoesNotCreateOrRemoveAnyMirror() async throws {
  let access = FakeEventKitAccess()
  await access.setFutureSeriesReplacementError(.writeAccessDenied)
  let core = try await makeSeededInMemoryCore()
  _ = try await core.createCalendarEvent(
    title: "Daily planning", startDate: "2026-07-01", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let occurrence = try #require(
    try await core.loadCalendarTimeline(from: "2026-07-03", to: "2026-07-03")
      .events.first { $0.source == "canonical" && $0.occurrenceDate == "2026-07-03" })
  let store = AppStore(
    core: core, eventKitCoordinator: scopedMirrorCoordinator(access: access))
  store.prepareCalendarDraft(for: occurrence)
  store.draftCalendarTitle = "Failed future cadence"

  await store.saveScopedCalendarEvent(occurrence, scope: .thisAndFollowing)

  #expect(await access.recordedFutureSeriesReplacements().count == 1)
  #expect(await access.recordedWrites().isEmpty)
  #expect(await access.recordedDeletes().isEmpty)
  #expect(await access.recordedOccurrenceRemovals().isEmpty)
  #expect(store.lastCalendarExportReport.status == .failed)
}

@MainActor
@Test
func appStoreFollowingDeleteUsesOneNativeFutureSeriesRemoval() async throws {
  let access = FakeEventKitAccess()
  let core = try await makeSeededInMemoryCore()
  let master = try await core.createCalendarEvent(
    title: "Daily planning", startDate: "2026-07-01", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let occurrence = try #require(
    try await core.loadCalendarTimeline(from: "2026-07-03", to: "2026-07-03")
      .events.first { $0.source == "canonical" && $0.occurrenceDate == "2026-07-03" })
  let store = AppStore(
    core: core, eventKitCoordinator: scopedMirrorCoordinator(access: access))

  await store.deleteScopedCalendarEvent(occurrence, scope: .thisAndFollowing)

  let removals = await access.recordedFutureSeriesRemovals()
  let expectedOccurrenceDate = try scopedMirrorDate(2026, 7, 3, 10)
  #expect(removals.count == 1)
  #expect(removals.first?.lorvexID == master.eventID)
  #expect(removals.first?.occurrenceDate == expectedOccurrenceDate)
  #expect(await access.recordedWrites().isEmpty)
  #expect(await access.recordedOccurrenceRemovals().isEmpty)
  #expect(store.lastCalendarExportReport.status == .succeeded)
}

@MainActor
@Test
func appStoreNestedFollowingDeleteTargetsTheAddressedSegmentMirror() async throws {
  let access = FakeEventKitAccess()
  let core = try await makeSeededInMemoryCore()
  let root = try await core.createCalendarEvent(
    title: "Root cadence", startDate: "2026-09-01", endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false,
    location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
    timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
    attendees: nil)
  let firstSplit = try await core.editScopedCalendarEvent(
    eventID: root.eventID, occurrenceDate: "2026-09-03", scope: "this_and_following",
    updates: ScopedCalendarEventUpdates(title: "First segment"))
  let firstTail = try #require(firstSplit.replacementEvent)
  let nestedOccurrence = try #require(
    try await core.loadCalendarTimeline(from: "2026-09-04", to: "2026-09-04")
      .events.first {
        $0.source == "canonical" && $0.eventID == firstTail.eventID
          && $0.occurrenceDate == "2026-09-04"
      })
  let store = AppStore(
    core: core, eventKitCoordinator: scopedMirrorCoordinator(access: access))

  await store.deleteScopedCalendarEvent(nestedOccurrence, scope: .thisAndFollowing)

  let removals = await access.recordedFutureSeriesRemovals()
  let expectedOccurrenceDate = try scopedMirrorDate(2026, 9, 4, 10)
  #expect(removals.count == 1)
  #expect(removals.first?.lorvexID == firstTail.eventID)
  #expect(removals.first?.occurrenceDate == expectedOccurrenceDate)
}

@Test
func liveEventKitAccessRemovesMatchingOccurrenceWithThisEventSpan() async throws {
  let store = FakeEKEventStore()
  let expected = store.makeEvent()
  expected.title = "Weekly planning"
  expected.startDate = try scopedMirrorDate(2026, 6, 25, 14)
  expected.endDate = try scopedMirrorDate(2026, 6, 25, 14, 30)
  expected.notes = "Planning\n\(lorvexCalendarEventPrefix)event-recurring-live"
  let unrelated = store.makeEvent()
  unrelated.title = "Other"
  unrelated.startDate = try scopedMirrorDate(2026, 6, 25, 14)
  unrelated.endDate = try scopedMirrorDate(2026, 6, 25, 14, 30)
  unrelated.notes = "lorvex-event-id:other-event"
  store.fakeEvents = [unrelated, expected]
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  try await access.removeLorvexEventOccurrence(
    lorvexEventID: "event-recurring-live",
    occurrenceDate: try scopedMirrorDate(2026, 6, 25, 14))

  #expect(store.removedEvents.count == 1)
  #expect(store.removedEvents.first?.0 === expected)
  #expect(store.removedEvents.first?.1 == .thisEvent)
}

@Test
func liveEventKitAccessRemovesMatchingOccurrenceWithFutureEventsSpan() async throws {
  let store = FakeEKEventStore()
  let expected = store.makeEvent()
  expected.title = "Weekly planning"
  expected.startDate = try scopedMirrorDate(2026, 6, 25, 14)
  expected.endDate = try scopedMirrorDate(2026, 6, 25, 14, 30)
  expected.notes = "Planning\n\(lorvexCalendarEventPrefix)event-future-live"
  store.fakeEvents = [expected]
  let access = LiveEventKitAccess(
    store: store,
    readAuthorizationProvider: { store.fullAccessGranted })

  try await access.removeFutureLorvexEventSeries(
    lorvexEventID: "event-future-live",
    occurrenceDate: try scopedMirrorDate(2026, 6, 25, 14))

  #expect(store.removedEvents.count == 1)
  #expect(store.removedEvents.first?.0 === expected)
  #expect(store.removedEvents.first?.1 == .futureEvents)
}
