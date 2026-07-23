import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreLoadsAndFiltersPreviewListsAndHabits() async throws {
  let suiteName = "appStoreLoadsAndFiltersPreviewListsAndHabits.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  // The store's calendar timeline is a window around today; the fixed seed
  // event (2026-05-22) sits outside it, so search exercises a fresh
  // in-window event.
  let todayYMD = LorvexDateFormatters.ymd.string(from: Date())
  let searchable = try await core.createCalendarEvent(
    title: "Migration review follow-up", startDate: todayYMD, endDate: nil,
    startTime: "10:00", endTime: "10:30", allDay: false, location: nil, notes: nil)
  let store = AppStore(core: core, defaults: defaults)

  await store.refresh()
  #expect(store.selectedListID == "inbox")
  #expect(store.selectedListDetail?.tasks.count == 1)

  store.searchText = "apple"
  #expect(store.filteredLists.map(\.id) == [LorvexPreviewSeedID.appleNativeList])

  store.searchText = "end of day"
  #expect(store.filteredHabits.map(\.id) == [LorvexPreviewSeedID.dailyReviewHabit])

  store.searchText = "migration review"
  #expect(store.filteredCalendarEvents.map(\.id) == [searchable.id])
}

@MainActor
@Test
func appStoreSelectsPreviewListDetail() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  await store.loadSelectedListDetailForUI()

  #expect(store.selectedListDetail?.list.name == "Apple Native")
  #expect(
    store.filteredSelectedListTasks.map(\.id) == [
      LorvexPreviewSeedID.agendaTask,
      LorvexPreviewSeedID.statusUpdateTask,
    ])
}

@MainActor
@Test
func appStoreCreatesListAndMovesSelectedPreviewTask() async throws {
  let suiteName = "AppStoreCreatesListAndMovesSelectedPreviewTask.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.selectedTaskID = LorvexPreviewSeedID.agendaTask
  let selectedTaskID = try #require(store.selectedTaskID)
  store.draftListName = "Writing"
  store.draftListDescription = "Drafting work"
  await store.createDraftList()

  #expect(store.selectedListDetail?.list.name == "Writing")
  #expect(store.selectedListDetail?.tasks.isEmpty == true)

  await store.moveSelectedTaskToSelectedList()

  #expect(store.selectedListDetail?.tasks.map(\.id) == [selectedTaskID])
  #expect(store.lists?.lists.first { $0.id == store.selectedListID }?.openCount == 1)
}

@MainActor
@Test
func appStoreListDetailSelectionSupportsBatchCompleteAndReopen() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  await store.loadSelectedListDetailForUI()
  let selectedIDs = Set(store.filteredSelectedListTasks.prefix(2).map(\.id))
  #expect(selectedIDs.count == 2)
  store.setSelectedListTaskSelection(selectedIDs)

  await store.completeSelectedListTaskSelection()

  // The list detail lists open tasks, so the completed rows leave it.
  #expect(!(store.selectedListDetail?.tasks ?? []).contains { selectedIDs.contains($0.id) })
  for id in selectedIDs {
    #expect(try await store.core.loadTask(id: id).status == .completed)
  }
  #expect(store.errorMessage == nil)

  // Reopening happens where completed tasks are listed: the task workspace.
  await store.loadTaskWorkspace()
  for id in selectedIDs {
    store.selectTaskFromList(id)
    await store.reopenSelectedTask()
  }
  await store.loadSelectedListDetailForUI()
  #expect(selectedIDs.isSubset(of: Set(store.selectedListDetail?.tasks.filter { $0.status == .open }.map(\.id) ?? [])))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreListDetailSelectionSupportsBatchMoveAndCancel() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.draftListName = "Batch Destination"
  await store.createDraftList()
  let targetListID = try #require(store.selectedListID)
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  await store.loadSelectedListDetailForUI()
  let selectedIDs = Set(store.filteredSelectedListTasks.prefix(2).map(\.id))
  #expect(selectedIDs.count == 2)
  store.setSelectedListTaskSelection(selectedIDs)

  await store.moveSelectedListTaskSelection(toListID: targetListID)

  #expect(store.selectedListTaskSelectionCount == 0)
  store.selectedListID = targetListID
  await store.loadSelectedListDetailForUI()
  #expect(selectedIDs.isSubset(of: Set(store.selectedListDetail?.tasks.map(\.id) ?? [])))

  store.setSelectedListTaskSelection(selectedIDs)
  await store.cancelSelectedListTaskSelection()
  #expect(store.pendingRecurringBatchCancel?.surface == .selectedList)
  await store.confirmPendingRecurringBatchCancel(scope: .thisOccurrence)

  // The list detail lists open tasks, so the cancelled rows leave it.
  #expect(!(store.selectedListDetail?.tasks ?? []).contains { selectedIDs.contains($0.id) })
  for id in selectedIDs {
    #expect(try await store.core.loadTask(id: id).status == .cancelled)
  }
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func listDetailTaskRowSelectionSeparatesOpenFromBatchSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  await store.loadSelectedListDetailForUI()
  let tasks = store.filteredSelectedListTasks
  let first = try #require(tasks.first)
  let second = try #require(tasks.dropFirst().first)

  store.selectOnlySelectedListTask(first.id)

  #expect(store.selectedTaskID == first.id)
  #expect(store.selectedListTaskIDs == [first.id])

  store.toggleSelectedListTaskBatchSelection(second.id)

  #expect(store.selectedTaskID == second.id)
  #expect(store.selectedListTaskIDs == [first.id, second.id])

  store.toggleSelectedListTaskBatchSelection(second.id)

  #expect(store.selectedTaskID == first.id)
  #expect(store.selectedListTaskIDs == [first.id])
}

@MainActor
@Test
func appStoreUpdatesPreviewList() async throws {
  let suiteName = "appStoreUpdatesPreviewList.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  let list = try #require(store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  store.prepareListDraft(for: list)
  store.draftListName = "  Apple Platform  "
  store.draftListDescription = "  Native app work  "

  await store.updateList(list)

  let updated = try #require(store.lists?.lists.first { $0.id == list.id })
  #expect(updated.name == "Apple Platform")
  #expect(updated.description == "Native app work")
  #expect(store.selectedListID == list.id)
  #expect(store.selectedListDetail?.list.name == "Apple Platform")
  #expect(store.draftListName == "")
  // Editing a list no longer force-navigates to the Lists workspace (which no
  // longer has a sidebar row); management happens in place.
  #expect(store.selection != .lists)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreDeletesEmptyPreviewList() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.draftListName = "Empty List"
  await store.createDraftList()
  let list = try #require(store.lists?.lists.first { $0.name == "Empty List" })

  await store.deleteList(list)

  #expect(store.lists?.lists.contains { $0.id == list.id } == false)
  #expect(store.selectedListID != list.id)
  #expect(store.selectedListDetail?.list.id != list.id)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreRejectsDeletingListWithTasks() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()

  // The Inbox is the canonical fallback for tasks and can never be deleted.
  let inbox = try #require(store.lists?.lists.first { $0.id == "inbox" })
  await store.deleteList(inbox)
  #expect(store.lists?.lists.contains { $0.id == inbox.id } == true)
  #expect(store.errorMessage?.contains("Cannot delete the inbox list") == true)

  // A populated list is refused with the assigned-task count.
  store.errorMessage = nil
  let populated = try #require(
    store.lists?.lists.first { $0.id == LorvexPreviewSeedID.appleNativeList })
  await store.deleteList(populated)
  #expect(store.lists?.lists.contains { $0.id == populated.id } == true)
  #expect(store.errorMessage?.contains("Cannot delete list while") == true)
}

@MainActor
@Test
func appStoreCompletesAndResetsPreviewHabit() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(habit.completionsToday == 0)

  await store.completeHabit(habit)
  let completed = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(completed.completionsToday == 1)

  await store.uncompleteHabit(completed)
  let reset = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(reset.completionsToday == 0)
}

@MainActor
@Test
func appStoreCreatesPreviewHabit() async throws {
  let suiteName = "appStoreCreatesPreviewHabit.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.draftHabitName = "Hydrate"
  store.draftHabitCue = "After coffee"
  store.draftHabitTargetCountText = "2"
  await store.createDraftHabit()

  let habit = try #require(store.habits?.habits.first { $0.name == "Hydrate" })
  #expect(habit.cue == "After coffee")
  #expect(habit.targetCount == 2)
  #expect(store.draftHabitName == "")
  #expect(store.draftHabitTargetCountText == "1")
  #expect(store.selection == .habits)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreUpdatesPreviewHabit() async throws {
  let suiteName = "appStoreUpdatesPreviewHabit.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  store.prepareHabitDraft(for: habit)
  store.draftHabitName = "  Planning Review  "
  store.draftHabitCue = "  After standup  "
  store.draftHabitTargetCountText = "3"

  await store.updateHabit(habit)

  let updated = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(updated.name == "Planning Review")
  #expect(updated.cue == "After standup")
  #expect(updated.targetCount == 3)
  #expect(store.draftHabitName == "")
  #expect(store.draftHabitTargetCountText == "1")
  #expect(store.selection == .habits)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreThreadsMilestoneGoalThroughCreateEditAndClear() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // Create carries the optional milestone goal to the core.
  store.draftHabitName = "Meditate"
  store.draftHabitMilestoneTargetText = "30"
  await store.createDraftHabit()
  let created = try #require(store.habits?.habits.first { $0.name == "Meditate" })
  #expect(created.milestoneTarget == 30)
  // The draft field is cleared after a create, like the other draft fields.
  #expect(store.draftHabitMilestoneTargetText == "")

  // Editing seeds the field from the stored goal, then raises it.
  store.prepareHabitDraft(for: created)
  #expect(store.draftHabitMilestoneTargetText == "30")
  store.draftHabitMilestoneTargetText = "66"
  await store.updateHabit(created)
  let raised = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(raised.milestoneTarget == 66)

  // Clearing the field clears the goal (Patch.clear), not leaves it unchanged.
  store.prepareHabitDraft(for: raised)
  store.draftHabitMilestoneTargetText = ""
  await store.updateHabit(raised)
  let cleared = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(cleared.milestoneTarget == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreStagesMilestoneCelebrationOnCrossing() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // A daily habit with a personal goal of 1: the first completion reaches it.
  store.draftHabitName = "First step"
  store.draftHabitMilestoneTargetText = "1"
  await store.createDraftHabit()
  let habit = try #require(store.habits?.habits.first { $0.name == "First step" })
  #expect(store.milestoneCelebration == nil)

  await store.completeHabit(habit)
  let celebration = try #require(store.milestoneCelebration)
  #expect(celebration.milestone == 1)
  #expect(celebration.habitName == "First step")

  // A completion that crosses nothing leaves no new celebration staged.
  store.milestoneCelebration = nil
  let plain = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  await store.completeHabit(plain)
  #expect(store.milestoneCelebration == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreDeletesPreviewHabit() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.deleteHabit(habit)

  #expect(store.habits?.habits.contains { $0.id == habit.id } == false)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreCreatesWeeklyHabitWithCadence() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  store.draftHabitName = "Long run"
  store.draftHabitCadenceMode = .weekly
  store.draftHabitWeekdays = [0, 2, 4]  // Mon / Wed / Fri
  store.draftHabitTargetCountText = "3"
  await store.createDraftHabit()

  let created = try #require(store.habits?.habits.first { $0.name == "Long run" })
  #expect(created.frequencyType == "weekly")
  #expect(created.weekdays == [0, 2, 4])  // Mon / Wed / Fri, Monday-first
  #expect(created.targetCount == 3)
  #expect(store.errorMessage == nil)

  // Editing reloads the habit's full cadence into the editor, then writes it
  // back verbatim — switching to daily clears the weekday payload.
  store.prepareHabitDraft(for: created)
  #expect(store.draftHabitCadenceMode == .weekly)
  #expect(store.draftHabitWeekdays == [0, 2, 4])
  store.draftHabitCadenceMode = .daily
  await store.updateHabit(created)
  let edited = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(edited.frequencyType == "daily")
  #expect(edited.weekdays == nil)
}

/// Every ``HabitCadenceMode`` case must assemble into its matching wire
/// `frequency_type` string — the exhaustive switch a bare `String` draft field
/// couldn't guarantee at compile time (a typo like `"timesperWeek"` would have
/// silently fallen through to `daily`).
@MainActor
@Test
func appStoreDraftCadenceInputCoversEveryMode() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let expectedWireStrings: [HabitCadenceMode: String] = [
    .daily: "daily",
    .weekly: "weekly",
    .timesPerWeek: "times_per_week",
    .monthly: "monthly",
  ]
  #expect(Set(expectedWireStrings.keys) == Set(HabitCadenceMode.allCases))

  for mode in HabitCadenceMode.allCases {
    store.draftHabitCadenceMode = mode
    store.draftHabitWeekdays = [0, 2, 4]
    let draft = store.draftHabitCadenceInput()
    #expect(draft.cadence.frequencyType == expectedWireStrings[mode])
  }
}

@MainActor
@Test
func appStoreArchivesAndRestoresHabit() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  await store.loadArchivedHabits()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
  #expect(store.filteredHabits.contains { $0.id == habit.id })
  #expect(store.archivedHabits.isEmpty)

  // Archiving moves the habit out of the active catalog and into the archived
  // list (the restore surface).
  await store.setHabitArchived(habit, archived: true)
  #expect(!store.filteredHabits.contains { $0.id == habit.id })
  #expect(store.archivedHabits.contains { $0.id == habit.id })

  // Restoring brings it back to the active catalog and clears it from archived.
  await store.setHabitArchived(habit, archived: false)
  #expect(store.filteredHabits.contains { $0.id == habit.id })
  #expect(!store.archivedHabits.contains { $0.id == habit.id })
  #expect(store.errorMessage == nil)
}
