import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

// Saving a list, habit, or event edit sheet writes only the fields the user
// changed from the record the sheet opened on. A field the user left alone
// keeps what the core holds, so a change another writer made while the sheet
// was open (the assistant, another device, a sync apply) survives the save,
// even after a refresh replaced the record the store shows.

@MainActor
private func makeEditSheetCoordinator(access: FakeEventKitAccess) -> EventKitCoordinator {
  EventKitCoordinator(
    access: access,
    provider: FakeEventKitProvider(),
    loadAccessMode: { .busyOnly },
    loadCalendarFilter: { .all },
    isEnabled: { true })
}

private let assistantSummary = "Everything the Apple apps need before launch"

@MainActor
@Test
func editSheetMacListSaveKeepsAnotherWritersDescription() async throws {
  let suiteName = "editSheetMacListSave.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  store.prepareListDraft(for: list)

  _ = try await core.updateList(
    id: list.id, name: nil, description: .set(assistantSummary), color: nil, icon: nil)
  await store.refresh()
  store.draftListName = "Apple Platform"
  await store.updateList(list)

  #expect(store.errorMessage == nil)
  let saved = try await core.getList(id: list.id)
  #expect(saved.name == "Apple Platform")
  #expect(saved.description == assistantSummary)

  // Emptying the description in the editor still clears it.
  store.prepareListDraft(for: saved)
  store.draftListDescription = "  "
  await store.updateList(saved)

  #expect(store.errorMessage == nil)
  let cleared = try await core.getList(id: list.id)
  #expect(cleared.description == nil)
  #expect(cleared.name == "Apple Platform")
}

@MainActor
@Test
func editSheetIPhoneListSaveKeepsAnotherWritersDescription() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  store.prepareListDraft(for: list)

  _ = try await core.updateList(
    id: list.id, name: nil, description: .set(assistantSummary), color: nil, icon: nil)
  await store.refresh()
  store.listDraft.name = "Apple Platform"

  #expect(await store.updateList(list))
  let saved = try await core.getList(id: list.id)
  #expect(saved.name == "Apple Platform")
  #expect(saved.description == assistantSummary)

  // Emptying the description in the editor still clears it.
  store.prepareListDraft(for: saved)
  store.listDraft.description = ""
  #expect(await store.updateList(saved))

  let cleared = try await core.getList(id: list.id)
  #expect(cleared.description == nil)
  #expect(cleared.name == "Apple Platform")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func editSheetIPhoneHabitSaveKeepsAnotherWritersNameAndRhythm() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let habit = try #require(
    store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  store.prepareHabitDraft(for: habit)

  _ = try await core.updateHabit(
    id: habit.id, name: "Evening stroll", cue: .unset, color: nil, icon: nil, targetCount: nil,
    archived: nil, cadence: HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 4))
  await store.refresh()
  store.habitDraft.cue = "After dinner"
  store.habitDraft.milestoneTargetText = "30"

  #expect(await store.updateHabit(habit))
  let saved = try await storedHabit(habit.id, in: core)
  #expect(saved.name == "Evening stroll")
  #expect(saved.frequencyType == "times_per_week")
  #expect(saved.perPeriodTarget == 4)
  #expect(saved.cue == "After dinner")
  #expect(saved.milestoneTarget == 30)

  // Emptying the cue in the editor still clears it.
  store.prepareHabitDraft(for: saved)
  store.habitDraft.cue = ""
  #expect(await store.updateHabit(saved))
  let cleared = try await storedHabit(habit.id, in: core)
  #expect(cleared.cue == nil)
  #expect(cleared.name == "Evening stroll")
  #expect(cleared.milestoneTarget == 30)

  // A save with nothing changed succeeds and leaves the habit as it was.
  store.prepareHabitDraft(for: cleared)
  #expect(await store.updateHabit(cleared))
  #expect(store.errorMessage == nil)
  let untouched = try await storedHabit(habit.id, in: core)
  #expect(untouched.name == "Evening stroll")
  #expect(untouched.frequencyType == "times_per_week")
  #expect(untouched.perPeriodTarget == 4)
}

private func storedHabit(
  _ id: LorvexHabit.ID, in core: SwiftLorvexCoreService
) async throws -> LorvexHabit {
  try #require(await core.loadHabits(date: "2026-05-23").habits.first { $0.id == id })
}

@MainActor
@Test
func editSheetMacEventSaveKeepsAnotherWritersTimesAndNotes() async throws {
  let core = try await makeSeededInMemoryCore()
  // The store's calendar window spans around today, so the event starts today.
  let seeded = try await core.createCalendarEvent(
    title: "Window review", startDate: LorvexDateFormatters.ymd.string(from: Date()),
    endDate: nil, startTime: "15:00", endTime: "15:45", allDay: false,
    location: "Conference Room B", notes: "Original agenda")
  let access = FakeEventKitAccess()
  let store = AppStore(core: core, eventKitCoordinator: makeEditSheetCoordinator(access: access))
  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.eventID == seeded.eventID })
  store.prepareCalendarDraft(for: event)

  _ = try await core.updateCalendarEvent(
    id: event.eventID, title: nil, startDate: nil, endDate: nil, startTime: "16:00",
    endTime: "17:00", allDay: nil, location: nil, notes: "The assistant's agenda")
  await store.refresh()
  store.draftCalendarTitle = "Window review, revised"
  await store.updateCalendarEvent(event)

  #expect(store.errorMessage == nil)
  let saved = try #require(await core.getCalendarEvent(id: event.eventID))
  #expect(saved.title == "Window review, revised")
  #expect(saved.startTime == "16:00")
  #expect(saved.endTime == "17:00")
  #expect(saved.notes == "The assistant's agenda")
  #expect(saved.location == "Conference Room B")
  // Calendar's copy takes the stored notes, not the ones the form opened with.
  #expect(await access.recordedWriteNotesPatches().last == .replace("The assistant's agenda"))

  // Emptying the location in the form still clears it.
  store.prepareCalendarDraft(for: saved)
  store.draftCalendarLocation = "  "
  await store.updateCalendarEvent(saved)
  #expect(store.errorMessage == nil)
  let cleared = try #require(await core.getCalendarEvent(id: event.eventID))
  #expect((cleared.location ?? "").isEmpty)
  #expect(cleared.title == "Window review, revised")
  #expect(cleared.notes == "The assistant's agenda")

  // A save with nothing changed succeeds and leaves the event as it was.
  store.prepareCalendarDraft(for: cleared)
  await store.updateCalendarEvent(cleared)
  #expect(store.errorMessage == nil)
  let untouched = try #require(await core.getCalendarEvent(id: event.eventID))
  #expect(untouched.title == "Window review, revised")
  #expect(untouched.startTime == "16:00")
  #expect(untouched.endTime == "17:00")
  #expect(untouched.notes == "The assistant's agenda")
}

@MainActor
@Test
func editSheetIPhoneEventSaveKeepsAnotherWritersTimesAndLocation() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let event = try await core.createCalendarEvent(
    title: "Design review", startDate: "2026-06-02", endDate: nil, startTime: "15:00",
    endTime: "15:45", allDay: false, location: "Studio", notes: "Bring sketches")
  await store.refresh()
  store.prepareCalendarDraft(for: event)

  _ = try await core.updateCalendarEvent(
    id: event.eventID, title: nil, startDate: nil, endDate: nil, startTime: "16:00",
    endTime: "17:00", allDay: nil, location: "Room 4", notes: nil)
  await store.refresh()
  store.calendarDraft.title = "Design review, round two"

  #expect(await store.updateCalendarEvent(event))
  let saved = try #require(await core.getCalendarEvent(id: event.eventID))
  #expect(saved.title == "Design review, round two")
  #expect(saved.startDate == "2026-06-02")
  #expect(saved.startTime == "16:00")
  #expect(saved.endTime == "17:00")
  #expect(saved.location == "Room 4")
  #expect(saved.notes == "Bring sketches")

  // Emptying the notes in the form still clears them.
  store.prepareCalendarDraft(for: saved)
  store.calendarDraft.notes = "\n "
  #expect(await store.updateCalendarEvent(saved))
  let cleared = try #require(await core.getCalendarEvent(id: event.eventID))
  #expect((cleared.notes ?? "").isEmpty)
  #expect(cleared.location == "Room 4")
  #expect(cleared.title == "Design review, round two")

  // A save with nothing changed succeeds and leaves the event as it was.
  store.prepareCalendarDraft(for: cleared)
  #expect(await store.updateCalendarEvent(cleared))
  #expect(store.errorMessage == nil)
  let untouched = try #require(await core.getCalendarEvent(id: event.eventID))
  #expect(untouched.startTime == "16:00")
  #expect(untouched.endTime == "17:00")
  #expect(untouched.location == "Room 4")
}
