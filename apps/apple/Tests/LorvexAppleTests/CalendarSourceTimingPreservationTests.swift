import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor
@Suite("Calendar detail edits preserve source clocks and missing endpoints")
struct CalendarSourceTimingPreservationTests {
  @Test(
    arguments: [false, true],
    [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func editingDetailsOnASpringGapKeepsTheOriginalSchedule(
    mobile: Bool, scope: CalendarEventEditScope
  ) async throws {
    let (core, before, occurrence) = try await fixture(openEnd: false)
    #expect(occurrence.startTime == "03:00")
    #expect(occurrence.sourceTiming?.startTime == "02:30")
    try await editDetails(core, occurrence, mobile: mobile, scope: scope)
    try await expectSameSchedule(core, before: before, scope: scope)
  }

  @Test(
    arguments: [false, true],
    [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func editingDetailsDoesNotSaveTheEditorsDefaultEnd(
    mobile: Bool, scope: CalendarEventEditScope
  ) async throws {
    let (core, before, occurrence) = try await fixture(openEnd: true)
    #expect(occurrence.endTime == nil)
    try await editDetails(core, occurrence, mobile: mobile, scope: scope)
    try await expectSameSchedule(core, before: before, scope: scope)
  }

  @Test(arguments: [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func aCoreDetailPatchCanRetainAnInheritedGapStart(scope: CalendarEventEditScope) async throws {
    let (core, before, occurrence) = try await fixture(openEnd: false)
    _ = try await core.editScopedCalendarEvent(
      eventID: occurrence.eventID, occurrenceDate: "2026-03-08", scope: scope.rawValue,
      updates: ScopedCalendarEventUpdates(title: "Renamed", notes: "Changed notes"))
    try await expectSameSchedule(core, before: before, scope: scope)
  }

  @Test(arguments: [false, true], [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func editingOnlyTheEndRetainsTheInheritedStart(mobile: Bool, scope: CalendarEventEditScope) async throws {
    let (core, before, occurrence) = try await fixture(openEnd: false)
    if mobile {
      let store = MobileStore(core: core)
      store.prepareCalendarDraft(for: occurrence)
      store.calendarDraft.timing.setEnd(store.calendarDraft.timing.end.addingTimeInterval(1_800))
      #expect(await store.saveScopedCalendarEvent(occurrence, scope: scope))
      #expect(store.errorMessage == nil)
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      store.prepareCalendarDraft(for: occurrence)
      store.draftCalendarTiming.setEnd(store.draftCalendarTiming.end.addingTimeInterval(1_800))
      await store.saveScopedCalendarEvent(occurrence, scope: scope)
      #expect(store.errorMessage == nil)
    }
    let after = try await core.loadCalendarTimeline(from: "2026-03-07", to: "2026-03-10").events
      .filter { $0.title == "Original" }
    #expect(after.count == before.count)
    #expect(after.map { $0.projection?.start } == before.map { $0.projection?.start })
    #expect(after.allSatisfy { $0.sourceTiming?.startTime == "02:30" })
    for event in after {
      let slot = try #require(event.occurrenceDate)
      let edited = scope == .allEvents || slot == "2026-03-08"
        || (scope == .thisAndFollowing && slot > "2026-03-08")
      #expect(event.sourceTiming?.endTime == (edited ? "04:00" : "03:30"))
    }
  }

  @Test(arguments: [.thisEvent, .thisAndFollowing] as [CalendarEventEditScope])
  func inheritedGapPermissionDoesNotAcceptANewGapClock(scope: CalendarEventEditScope) async throws {
    let (core, before, occurrence) = try await fixture(openEnd: false)
    await #expect(throws: (any Error).self) {
      _ = try await core.editScopedCalendarEvent(
        eventID: occurrence.eventID, occurrenceDate: "2026-03-08", scope: scope.rawValue,
        updates: ScopedCalendarEventUpdates(startTime: "02:45"))
    }
    let after = try await core.loadCalendarTimeline(from: "2026-03-07", to: "2026-03-10").events
      .filter { $0.title == "Original" }
    #expect(after.map(\.sourceTiming) == before.map(\.sourceTiming))
  }

  @Test func aGapOccurrenceCanBeCancelledRestoredAndEditedAgain() async throws {
    let (core, before, occurrence) = try await fixture(openEnd: false)
    _ = try await core.addCalendarEventException(eventID: occurrence.eventID, date: "2026-03-08")
    let cancelled = try await core.loadCalendarTimeline(from: "2026-03-08", to: "2026-03-08")
    #expect(!cancelled.events.contains { $0.title == "Original" })
    _ = try await core.removeCalendarEventException(eventID: occurrence.eventID, date: "2026-03-08")
    for title in ["First edit", "Renamed"] {
      _ = try await core.editScopedCalendarEvent(
        eventID: occurrence.eventID, occurrenceDate: "2026-03-08", scope: "this_only",
        updates: ScopedCalendarEventUpdates(title: title, notes: "Changed notes"))
    }
    try await expectSameSchedule(core, before: before, scope: .thisEvent)
  }

  @Test func changingTheMasterDoesNotPreventCancellingAnExistingGapReplacement() async throws {
    let (core, _, occurrence) = try await fixture(openEnd: false)
    _ = try await core.editScopedCalendarEvent(
      eventID: occurrence.eventID, occurrenceDate: "2026-03-08", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Replacement"))
    _ = try await core.updateCalendarEvent(
      id: occurrence.eventID, title: nil, startDate: nil, endDate: nil, startTime: "01:30",
      endTime: nil, allDay: nil, location: nil, notes: nil)
    _ = try await core.addCalendarEventException(eventID: occurrence.eventID, date: "2026-03-08")
    _ = try await core.removeCalendarEventException(eventID: occurrence.eventID, date: "2026-03-08")
    let events = try await core.loadCalendarTimeline(from: "2026-03-08", to: "2026-03-08").events
    let restored = try #require(events.first { $0.title == "Original" })
    #expect(restored.startTime == "01:30")
  }

  @Test(arguments: [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func explicitlyClearingAScopedZoneCreatesFloatingClocks(scope: CalendarEventEditScope) async throws {
    let (core, _, occurrence) = try await fixture(openEnd: true)
    _ = try await core.editScopedCalendarEvent(
      eventID: occurrence.eventID, occurrenceDate: "2026-03-08", scope: scope.rawValue,
      updates: ScopedCalendarEventUpdates(title: "Floating", timezone: ""))
    let edited = try await core.loadCalendarTimeline(from: "2026-03-08", to: "2026-03-10").events
      .filter { $0.title == "Floating" }
    #expect(!edited.isEmpty)
    #expect(edited.allSatisfy { $0.timezone == nil && $0.projection == nil && $0.startTime == "09:00" })
  }

  @Test(arguments: [.thisEvent, .thisAndFollowing] as [CalendarEventEditScope])
  func scopedDetailEditsKeepFloatingClocksFloating(scope: CalendarEventEditScope) async throws {
    let (core, _, occurrence) = try await fixture(openEnd: true)
    _ = try await core.updateCalendarEvent(
      id: occurrence.eventID, title: nil, startDate: nil, endDate: nil, startTime: nil,
      endTime: nil, allDay: nil, location: nil, notes: nil, recurrence: .unset,
      timezone: "", url: nil, color: nil, eventType: nil, personName: nil, attendees: .unset)
    _ = try await core.editScopedCalendarEvent(
      eventID: occurrence.eventID, occurrenceDate: "2026-03-08", scope: scope.rawValue,
      updates: ScopedCalendarEventUpdates(title: "Renamed"))
    let edited = try await core.loadCalendarTimeline(from: "2026-03-08", to: "2026-03-10").events
      .filter { $0.title == "Renamed" }
    #expect(!edited.isEmpty)
    #expect(edited.allSatisfy { $0.timezone == nil && $0.projection == nil && $0.startTime == "09:00" })
  }

  @Test(arguments: [false, true], [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func untouchedFieldsRetainChangesMadeWhileTheEditorWasOpen(mobile: Bool, scope: CalendarEventEditScope) async throws {
    let (core, _, occurrence) = try await fixture(openEnd: true)
    func changeExternally() async throws {
      _ = try await core.updateCalendarEvent(
        id: occurrence.eventID, title: nil, startDate: nil, endDate: nil, startTime: "10:00",
        endTime: nil, allDay: nil, location: "New room", notes: "Updated elsewhere")
    }
    if mobile {
      let store = MobileStore(core: core)
      store.prepareCalendarDraft(for: occurrence)
      store.calendarDraft.title = "Renamed"
      try await changeExternally()
      #expect(await store.saveScopedCalendarEvent(occurrence, scope: scope))
      #expect(store.errorMessage == nil)
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      store.prepareCalendarDraft(for: occurrence)
      store.draftCalendarTitle = "Renamed"
      try await changeExternally()
      await store.saveScopedCalendarEvent(occurrence, scope: scope)
      #expect(store.errorMessage == nil)
    }
    let events = try await core.loadCalendarTimeline(from: "2026-03-07", to: "2026-03-10").events
      .filter { ["Original", "Renamed"].contains($0.title) }
    #expect(events.count == 4)
    #expect(events.allSatisfy {
      $0.startTime == "10:00" && $0.endTime == nil
        && $0.location == "New room" && $0.notes == "Updated elsewhere"
    })
  }

  private func fixture(openEnd: Bool) async throws -> (
    SwiftLorvexCoreService, [CalendarTimelineEvent], CalendarTimelineEvent
  ) {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "America/New_York")
    let master = try await core.createCalendarEvent(
      title: "Original", startDate: "2026-03-07", endDate: nil,
      startTime: openEnd ? "09:00" : "02:30", endTime: openEnd ? nil : "03:30",
      allDay: false, location: "Room", notes: "Original notes",
      recurrence: TaskRecurrenceRule(freq: .daily, interval: 1, count: 4),
      timezone: "America/New_York", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let before = try await core.loadCalendarTimeline(from: "2026-03-07", to: "2026-03-10").events
      .filter { $0.eventID == master.eventID }
    #expect(before.count == 4)
    return (core, before, try #require(before.first { $0.occurrenceDate == "2026-03-08" }))
  }

  private func editDetails(
    _ core: SwiftLorvexCoreService, _ occurrence: CalendarTimelineEvent,
    mobile: Bool, scope: CalendarEventEditScope
  ) async throws {
    if mobile {
      let store = MobileStore(core: core)
      store.prepareCalendarDraft(for: occurrence)
      store.calendarDraft.title = "Renamed"
      store.calendarDraft.notes = "Changed notes"
      #expect(await store.saveScopedCalendarEvent(occurrence, scope: scope))
      #expect(store.errorMessage == nil)
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      store.prepareCalendarDraft(for: occurrence)
      store.draftCalendarTitle = "Renamed"
      store.draftCalendarNotes = "Changed notes"
      await store.saveScopedCalendarEvent(occurrence, scope: scope)
      #expect(store.errorMessage == nil)
    }
  }

  private func expectSameSchedule(
    _ core: SwiftLorvexCoreService, before: [CalendarTimelineEvent], scope: CalendarEventEditScope
  ) async throws {
    let after = try await core.loadCalendarTimeline(from: "2026-03-07", to: "2026-03-10").events
      .filter { ["Original", "Renamed"].contains($0.title) }
    #expect(after.count == before.count)
    #expect(after.map(\.projection) == before.map(\.projection))
    #expect(after.map(\.sourceTiming) == before.map(\.sourceTiming))
    for event in after {
      let slot = try #require(event.occurrenceDate)
      let edited =
        scope == .allEvents || slot == "2026-03-08"
        || (scope == .thisAndFollowing && slot > "2026-03-08")
      #expect(event.title == (edited ? "Renamed" : "Original"))
      #expect(event.notes == (edited ? "Changed notes" : "Original notes"))
    }
  }
}
