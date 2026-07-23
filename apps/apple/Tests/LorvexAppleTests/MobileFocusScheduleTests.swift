import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test
func mobileStoreRefreshLoadsSavedFocusSchedule() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.addToCurrentFocus(
    date: date,
    taskIDs: [task.id],
    briefing: nil,
    timezone: "UTC"
  )
  let saved = try await core.saveFocusSchedule(
    date: date,
    blocks: [
      FocusScheduleBlock(
        blockType: "task",
        startTime: "09:00",
        endTime: "09:30",
        taskID: task.id,
        title: task.title
      )
    ],
    rationale: "Morning focus"
  )
  let store = MobileStore(core: core, todayString: { date })

  await store.refresh()

  #expect(store.focusSchedule == saved)
  #expect(store.proposedFocusSchedule == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreProposesAndSavesFocusSchedule() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.addToCurrentFocus(
    date: date,
    taskIDs: [task.id],
    briefing: nil,
    timezone: "UTC"
  )
  let store = MobileStore(core: core, todayString: { date })
  await store.refresh()

  await store.proposeFocusSchedule()

  let proposed = try #require(store.proposedFocusSchedule)
  #expect(proposed.date == date)
  #expect(proposed.blocks.map(\.taskID).contains(task.id))
  #expect(store.focusSchedule == nil)

  await store.saveProposedFocusSchedule()

  let saved = try #require(store.focusSchedule)
  #expect(saved.date == date)
  #expect(saved.blocks == proposed.blocks)
  #expect(store.proposedFocusSchedule == nil)
  #expect(store.snapshot.currentFocus?.taskIDs.contains(task.id) == true)
  #expect(try await core.loadFocusSchedule(date: date) == saved)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreSavesLocalizedFallbackFocusScheduleRationale() async throws {
  let core = try await makeSeededInMemoryCore()
  let date = "2026-05-23"
  let task = try #require(try await core.loadToday().tasks.first)
  let store = MobileStore(core: core, todayString: { date })
  store.proposedFocusSchedule = FocusSchedule(
    date: date,
    blocks: [
      FocusScheduleBlock(
        blockType: "task",
        startTime: "09:00",
        endTime: "09:30",
        taskID: task.id,
        title: task.title
      )
    ]
  )

  await store.saveProposedFocusSchedule()

  let saved = try #require(store.focusSchedule)
  #expect(
    saved.rationale
      == String(
        localized: "focus.schedule.rationale.savedFromLorvex",
        defaultValue: "Saved from Lorvex",
        table: "Localizable",
        bundle: MobileL10n.bundle))
  #expect(store.proposedFocusSchedule == nil)
}

@MainActor
@Test
func mobileStoreDiscardFocusScheduleProposalKeepsSavedSchedule() async throws {
  let core = try await makeSeededInMemoryCore()
  let date = "2026-05-23"
  let task = try #require(try await core.loadToday().tasks.first)
  let saved = FocusSchedule(
    date: date,
    rationale: "Existing plan",
    blocks: [
      FocusScheduleBlock(
        blockType: "task",
        startTime: "09:00",
        endTime: "09:30",
        taskID: task.id,
        title: task.title
      )
    ]
  )
  let proposal = FocusSchedule(
    date: date,
    rationale: "Proposal",
    blocks: [
      FocusScheduleBlock(
        blockType: "task",
        startTime: "10:00",
        endTime: "10:30",
        taskID: task.id,
        title: task.title
      )
    ]
  )
  let store = MobileStore(core: core, todayString: { date })
  store.focusSchedule = saved
  store.proposedFocusSchedule = proposal

  store.discardProposedFocusSchedule()

  #expect(store.focusSchedule == saved)
  #expect(store.proposedFocusSchedule == nil)
}

@MainActor
@Test
func mobileStoreClearCurrentFocusClearsScheduleAndMembership() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.addToCurrentFocus(
    date: date,
    taskIDs: [task.id],
    briefing: nil,
    timezone: "UTC"
  )
  _ = try await core.saveFocusSchedule(
    date: date,
    blocks: [
      FocusScheduleBlock(
        blockType: "task",
        startTime: "10:00",
        endTime: "10:30",
        taskID: task.id,
        title: task.title
      )
    ],
    rationale: "Saved from test"
  )
  let store = MobileStore(core: core, todayString: { date })
  await store.refresh()
  await store.proposeFocusSchedule()
  #expect(store.focusSchedule != nil)
  #expect(store.proposedFocusSchedule != nil)

  await store.clearCurrentFocus()

  #expect(store.focusSchedule == nil)
  #expect(store.proposedFocusSchedule == nil)
  #expect(store.snapshot.currentFocus?.taskIDs.isEmpty != false)
  #expect(try await core.loadFocusSchedule(date: date) == nil)
  #expect(store.errorMessage == nil)
}
