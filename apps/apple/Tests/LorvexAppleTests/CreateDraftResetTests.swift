import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

// `beginCreate*Draft()` exists because a create sheet's draft outlives the
// sheet: an edit that shares the draft (a list edit, an iOS habit edit, the
// Mac habit inspector's Repeat editor) or a cancelled create leaves fields
// behind, and the next create sheet must start clean rather than inherit them.

@MainActor
@Test
func appStoreBeginCreateListDraftClearsEditedFields() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let list = try #require(store.lists?.lists.first)

  store.prepareListDraft(for: list)
  #expect(!store.draftListName.isEmpty)

  store.beginCreateListDraft()
  #expect(store.draftListName.isEmpty)
  #expect(store.draftListDescription.isEmpty)
}

@MainActor
@Test
func appStoreBeginCreateHabitDraftResetsToDefaults() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let habit = try #require(store.habits?.habits.first)

  // A cancelled create leaves its name and encouragement behind; the Repeat
  // editor leaves the habit's rhythm behind.
  store.draftHabitName = "Abandoned"
  store.draftHabitCue = "Never mind"
  store.draftHabitMilestoneTargetText = "30"
  store.prepareHabitRhythmDraft(for: habit)
  store.draftHabitCadenceMode = .weekly
  store.draftHabitWeekdays = [1, 3]
  store.draftHabitTargetCountText = "4"

  store.beginCreateHabitDraft()
  #expect(store.draftHabitName.isEmpty)
  #expect(store.draftHabitCue.isEmpty)
  #expect(store.draftHabitMilestoneTargetText.isEmpty)
  #expect(store.draftHabitTargetCountText == "1")
  #expect(store.draftHabitCadenceMode == .daily)
}

@MainActor
@Test
func appStoreBeginCreateCalendarDraftClearsEditedFields() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.draftCalendarTitle = "Edited event"
  store.draftCalendarAllDay = true
  store.draftCalendarLocation = "Office"
  store.draftCalendarColor = "#3B82F6"

  store.beginCreateCalendarDraft()
  #expect(store.draftCalendarTitle.isEmpty)
  #expect(store.draftCalendarLocation.isEmpty)
  #expect(store.draftCalendarAllDay == false)
  #expect(store.draftCalendarColor == nil)
  #expect(store.draftCalendarEndTime > store.draftCalendarStartTime)
  #expect(store.draftCalendarEndTime.timeIntervalSince(store.draftCalendarStartTime) == 60 * 60)
}

@MainActor
@Test
func mobileStoreBeginCreateListDraftClearsEditedFields() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let list = try #require(try await core.loadLists().lists.first)

  store.prepareListDraft(for: list)
  #expect(!store.listDraft.name.isEmpty)

  store.beginCreateListDraft()
  #expect(store.listDraft == MobileListDraft())
}

@MainActor
@Test
func mobileStoreBeginCreateHabitDraftResetsToDefaults() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let habit = try #require(try await core.loadHabits(date: "2026-05-23").habits.first)

  store.prepareHabitDraft(for: habit)
  #expect(!store.habitDraft.name.isEmpty)

  store.beginCreateHabitDraft()
  #expect(store.habitDraft == MobileHabitDraft())
}

@MainActor
@Test
func mobileStoreBeginCreateCalendarDraftClearsEditedTitle() async throws {
  // A mid-morning clock: the default block is clamped to the start's day, so a
  // wall-clock `now` inside the last hour before midnight would shorten it.
  let now = try #require(Calendar.current.date(
    from: DateComponents(year: 2026, month: 5, day: 23, hour: 10, minute: 0)))
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" }, now: { now })
  store.calendarDraft.title = "Edited event"
  store.calendarDraft.location = "Office"

  store.beginCreateCalendarDraft()
  #expect(store.calendarDraft.trimmedTitle.isEmpty)
  #expect(store.calendarDraft.trimmedLocation.isEmpty)
  #expect(store.calendarDraft.endTime.timeIntervalSince(store.calendarDraft.startTime) == 60 * 60)
}

@Test
func createCalendarDraftDurationsDoNotUseOptionalCalendarFallbacks() throws {
  let root = packageRoot()
  let files = [
    "Sources/LorvexApple/Stores/AppStoreCalendarActions.swift",
    "Sources/LorvexApple/Views/CalendarWorkspaceCreateDraft.swift",
    "Sources/LorvexMobile/MobileStoreCalendarActions.swift",
    "Sources/LorvexMobile/MobileCalendarDayActions.swift",
  ]

  for file in files {
    let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
    #expect(
      !source.contains("date(byAdding: .hour"),
      "\(file) should use fixed-duration Date arithmetic for draft end times")
    #expect(
      !source.contains("date(byAdding: .minute"),
      "\(file) should use fixed-duration Date arithmetic for draft end times")
  }
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}
