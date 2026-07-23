import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

// `beginCreate*Draft()` exists because create and edit share one draft. Opening
// a create sheet after an edit (or a prior cancelled create) must start clean,
// not inherit the edited entity's fields.

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

  store.prepareHabitDraft(for: habit)
  #expect(!store.draftHabitName.isEmpty)

  store.beginCreateHabitDraft()
  #expect(store.draftHabitName.isEmpty)
  #expect(store.draftHabitCue.isEmpty)
  #expect(store.draftHabitTargetCountText == "1")
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
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
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
