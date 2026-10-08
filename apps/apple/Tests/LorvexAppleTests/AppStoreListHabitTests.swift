import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreLoadsPreviewListsAndHabits() async throws {
  let suiteName = "appStoreLoadsPreviewListsAndHabits.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  #expect(store.selectedListID == "inbox")
  #expect(store.selectedListDetail?.tasks.count == 1)
  #expect(store.orderedLists.contains { $0.id == LorvexPreviewSeedID.appleNativeList })
  #expect(store.orderedHabits.contains { $0.id == LorvexPreviewSeedID.dailyReviewHabit })
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
    store.selectedListTasks.map(\.id) == [
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

  let listID = try #require(store.selectedListID)
  await store.moveTasks(ids: [selectedTaskID], toListID: listID)

  #expect(store.selectedListDetail?.tasks.map(\.id) == [selectedTaskID])
  #expect(store.lists?.lists.first { $0.id == listID }?.openCount == 1)
}

@MainActor
@Test
func appStoreListDetailLoadsFurtherPagesAndKeepsThemAcrossReloads() async throws {
  let core = try await makeSeededInMemoryCore()
  let list = try await core.createList(name: "Reading", description: nil)
  var createdIDs: [LorvexTask.ID] = []
  for index in 0..<(AppStore.listDetailPageSize + 5) {
    let task = try await core.createTask(TaskCreateDraft(title: "Paged list task \(index)", listID: list.id))
    createdIDs.append(task.id)
  }

  let store = AppStore(core: core)
  store.selectedListID = list.id
  await store.loadSelectedListDetailForUI()

  #expect(store.selectedListDetail?.tasks.count == AppStore.listDetailPageSize)
  #expect(store.selectedListHasMoreTasks)

  await store.loadMoreSelectedListTasks()

  let loadedIDs = store.selectedListDetail?.tasks.map(\.id) ?? []
  #expect(loadedIDs.count == createdIDs.count)
  #expect(Set(loadedIDs) == Set(createdIDs))
  #expect(!store.selectedListHasMoreTasks)

  // The reload a mutation triggers keeps every loaded row instead of
  // shrinking the list back to its first page.
  await store.loadSelectedListDetailForUI()

  #expect(store.selectedListDetail?.tasks.count == createdIDs.count)
}

@MainActor
@Test
func appStoreListDetailSelectionSupportsBatchCompleteAndReopen() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  await store.loadSelectedListDetailForUI()
  let selectedIDs = Set(store.selectedListTasks.prefix(2).map(\.id))
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
  let selectedIDs = Set(store.selectedListTasks.prefix(2).map(\.id))
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
  let tasks = store.selectedListTasks
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
func appStoreKeepsTheInboxActiveWhenArchivingItIsAttempted() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()

  let inbox = try #require(store.lists?.lists.first { $0.id == "inbox" })
  await store.archiveList(inbox)
  #expect(store.lists?.lists.contains { $0.id == inbox.id } == true)
  #expect(store.archivedLists?.lists.contains { $0.id == inbox.id } != true)
  #expect(store.errorMessage?.contains("Cannot archive the inbox list") == true)
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

  // The inspector's name and encouragement fields write only what changed.
  await store.updateHabitFields(habit, name: "Planning Review", cue: .set("After standup"))
  let renamed = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(renamed.name == "Planning Review")
  #expect(renamed.cue == "After standup")
  #expect(renamed.targetCount == habit.targetCount)
  #expect(renamed.frequencyType == habit.frequencyType)

  // The Repeat editor loads the rhythm into the draft and saves it back.
  store.prepareHabitRhythmDraft(for: renamed)
  #expect(store.draftHabitTargetCountText == "\(habit.targetCount)")
  store.draftHabitTargetCountText = "3"
  await store.saveHabitRhythmDraft(renamed)

  let updated = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(updated.targetCount == 3)
  #expect(updated.name == "Planning Review")
  #expect(updated.cue == "After standup")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("Clearing a habit's icon and color restores the defaults and leaves the other fields alone")
func appStoreClearsHabitAppearanceOnly() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  await store.updateHabitFields(habit, cue: .set("After dinner"), milestoneTarget: .set(30))
  let goaled = try #require(store.habits?.habits.first { $0.id == habit.id })
  await store.updateHabitFields(goaled, icon: .set("figure.walk"), color: .set("#22C55E"))
  let styled = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(styled.icon == "figure.walk")
  #expect(styled.color == "#22C55E")

  await store.updateHabitFields(styled, icon: .clear, color: .clear)
  let cleared = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(cleared.icon == nil)
  #expect(cleared.color == nil)
  #expect(cleared.name == habit.name)
  #expect(cleared.cue == "After dinner")
  #expect(cleared.milestoneTarget == 30)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("An unparsable per-day count blocks a rhythm counted per day, and only such a rhythm")
func appStoreRhythmDraftWithUnparsableCount() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  store.prepareHabitRhythmDraft(for: habit)
  store.draftHabitCadenceMode = .weekly
  store.draftHabitWeekdays = [0, 2]
  store.draftHabitTargetCountText = "lots"
  await store.saveHabitRhythmDraft(habit)
  let unchanged = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(unchanged.frequencyType == habit.frequencyType)
  #expect(unchanged.targetCount == habit.targetCount)

  // A times-a-week rhythm hides the per-day count, so it never blocks one.
  store.draftHabitCadenceMode = .timesPerWeek
  await store.saveHabitRhythmDraft(unchanged)
  let weekly = try #require(store.habits?.habits.first { $0.id == habit.id })
  #expect(weekly.frequencyType == "times_per_week")
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

  // The inspector's Goal editor raises the stored goal.
  await store.updateHabitFields(created, milestoneTarget: .set(66))
  let raised = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(raised.milestoneTarget == 66)

  // An edit that does not pass the goal leaves it as stored.
  await store.updateHabitFields(raised, cue: .set("Before breakfast"))
  let kept = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(kept.milestoneTarget == 66)

  // No Goal clears it (Patch.clear), rather than leaving it unchanged.
  await store.updateHabitFields(kept, milestoneTarget: .clear)
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

  // The Repeat editor reloads the habit's full cadence into the draft, then
  // writes it back verbatim — switching to daily clears the weekday payload.
  store.prepareHabitRhythmDraft(for: created)
  #expect(store.draftHabitCadenceMode == .weekly)
  #expect(store.draftHabitWeekdays == [0, 2, 4])
  #expect(store.draftHabitTargetCountText == "3")
  store.draftHabitCadenceMode = .daily
  await store.saveHabitRhythmDraft(created)
  let edited = try #require(store.habits?.habits.first { $0.id == created.id })
  #expect(edited.frequencyType == "daily")
  #expect(edited.weekdays == nil)
  #expect(edited.targetCount == 3)
  #expect(edited.name == "Long run")
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
  #expect(store.orderedHabits.contains { $0.id == habit.id })
  #expect(store.archivedHabits.isEmpty)

  // Archiving moves the habit out of the active catalog and into the archived
  // list (the restore surface).
  await store.setHabitArchived(habit, archived: true)
  #expect(!store.orderedHabits.contains { $0.id == habit.id })
  #expect(store.archivedHabits.contains { $0.id == habit.id })

  // Restoring brings it back to the active catalog and clears it from archived.
  await store.setHabitArchived(habit, archived: false)
  #expect(store.orderedHabits.contains { $0.id == habit.id })
  #expect(!store.archivedHabits.contains { $0.id == habit.id })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreRefreshKeepsLoadedArchivedHabitsCurrent() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadArchivedHabits()
  #expect(store.archivedHabits.isEmpty)
  let first = try #require(store.habits?.habits.first)

  // An assistant archives a habit while the Habits workspace is open.
  _ = try await core.updateHabit(
    id: first.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
    archived: true)
  await store.refresh()
  #expect(store.archivedHabits.map(\.id) == [first.id])

  _ = try await core.updateHabit(
    id: first.id, name: "Renamed elsewhere", cue: .unset, color: nil, icon: nil,
    targetCount: nil, archived: nil)
  await store.refresh()
  #expect(store.archivedHabits.map(\.name) == ["Renamed elsewhere"])

  _ = try await core.deleteHabit(id: first.id)
  await store.refresh()
  #expect(store.archivedHabits.isEmpty)
}

@MainActor
@Test
func appStoreHabitsReloadFromAPeerKeepsLoadedArchivedHabitsCurrent() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadArchivedHabits()
  let first = try #require(store.habits?.habits.first)

  _ = try await core.updateHabit(
    id: first.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
    archived: true)
  await store.performSelectiveInboundReload([.habits])
  #expect(store.archivedHabits.map(\.id) == [first.id])

  _ = try await core.deleteHabit(id: first.id)
  await store.performSelectiveInboundReload([.habits])
  #expect(store.archivedHabits.isEmpty)
}

@MainActor
@Test
func appStoreLeavesArchivedHabitsUnreadUntilTheWorkspaceLoadsThem() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let first = try #require(store.habits?.habits.first)
  _ = try await core.updateHabit(
    id: first.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
    archived: true)

  await store.refresh()
  #expect(store.archivedHabits.isEmpty)

  await store.loadArchivedHabits()
  #expect(store.archivedHabits.map(\.id) == [first.id])
}

@MainActor
@Test
func listPreviewsShowEachListsOpenTasksInCanonicalOrder() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  let previews = try await store.loadListPreviews(ids: [LorvexPreviewSeedID.appleNativeList])

  // The list's completed task stays out of its card.
  #expect(
    previews[LorvexPreviewSeedID.appleNativeList]?.map(\.id) == [
      LorvexPreviewSeedID.agendaTask,
      LorvexPreviewSeedID.statusUpdateTask,
    ])
}

/// The Lists catalog cancels a preview load when the lists change; the
/// cancelled load must throw rather than overwrite the newer load's previews.
@MainActor
@Test
func listPreviewsThrowOnceTheirLoadIsCancelled() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  // The load cannot start before the test yields the main actor, so it starts
  // already cancelled.
  let load = Task { @MainActor in
    try await store.loadListPreviews(ids: [LorvexPreviewSeedID.appleNativeList])
  }
  load.cancel()

  await #expect(throws: CancellationError.self) { try await load.value }
}

/// A new title from the assistant moves no list count, so the lists snapshot
/// stays equal; the previews still quote the old title unless their key moves
/// with the task data.
@MainActor
@Test
func listPreviewKeyMovesWhenAnAssistantRenamesAPreviewedTask() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let listsBefore = store.lists
  let keyBefore = store.listPreviewKey

  _ = try await core.updateTask(
    TaskUpdateDraft(id: LorvexPreviewSeedID.agendaTask, title: "Renamed by the assistant"))
  await store.refresh()

  #expect(store.lists == listsBefore)
  #expect(store.listPreviewKey != keyBefore)
  let previews = try await store.loadListPreviews(ids: [LorvexPreviewSeedID.appleNativeList])
  #expect(
    previews[LorvexPreviewSeedID.appleNativeList]?.map(\.title).contains("Renamed by the assistant")
      == true)
}
