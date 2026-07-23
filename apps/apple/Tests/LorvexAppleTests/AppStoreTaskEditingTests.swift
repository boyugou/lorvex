import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
private func makeTaskEditingStore(
  taskReminderScheduler: (any TaskReminderScheduling)? = nil
) async throws -> AppStore {
  let suiteName = "AppStoreTaskEditingTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  guard let taskReminderScheduler else {
    return AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  }
  return AppStore(
    core: try await makeSeededInMemoryCore(),
    taskReminderScheduler: taskReminderScheduler,
    defaults: defaults
  )
}

@MainActor
@Test
func appStoreTaskSelectionCountUsesExplicitSurface() async throws {
  let store = try await makeTaskEditingStore()
  let started = try await store.core.createTask(title: "Started routing task", notes: "")
  _ = try await store.core.startTaskReturningTask(id: started.id)
  await store.refresh()
  let orderedTodayIDs = store.orderedTaskIDs(on: .focus)
  let todayIDs = Set(orderedTodayIDs)
  store.setFocusWorkspaceSelection(todayIDs)

  #expect(orderedTodayIDs.first == started.id)
  #expect(orderedTodayIDs.filter { $0 == started.id }.count == 1)
  #expect(orderedTodayIDs.count == todayIDs.count)
  #expect(store.focusWorkspaceSelectedTasks.first?.id == started.id)
  // The scene supplies the surface explicitly. Another window's navigation
  // selection cannot redirect the command to a different selection set.
  store.selection = .calendar
  #expect(store.taskSelectionCount(on: .focus) == todayIDs.count)
  #expect(store.taskSelectionCount(on: .taskWorkspace) == 0)

  store.selection = .today
  store.selectOnlyFocusWorkspaceTask(started.id)
  #expect(store.selectedTask?.id == started.id)
  store.pruneFocusWorkspaceSelection()
  #expect(store.focusWorkspaceSelectedTaskIDs == [started.id])
  store.reconcileSelectedTaskAfterRefresh()
  #expect(store.selectedTaskID == started.id)
}

@MainActor
@Test
func appStorePermanentDeleteRemovesTaskAndClearsSelection() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id

  // Requesting only stages the confirmation; nothing is deleted yet.
  store.requestPermanentDelete(task)
  #expect(store.pendingPermanentDeleteTask?.id == task.id)
  #expect(store.today.tasks.contains { $0.id == task.id })

  await store.confirmPermanentDelete()
  #expect(store.pendingPermanentDeleteTask == nil)
  #expect(!store.today.tasks.contains { $0.id == task.id })
  #expect(store.selectedTaskID == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreEditsSelectedPreviewTaskDetail() async throws {
  let store = try await makeTaskEditingStore()

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  #expect(!store.selectedTaskCanSave)
  store.taskDetailTitle = "Updated native task"
  store.taskDetailNotes = "Edited from detail."
  store.taskDetailPriority = .p3
  store.taskDetailEstimatedMinutesText = "45"
  store.taskDetailTagsText = "native, metadata, native"
  // depends_on must reference existing tasks (validated UUIDs).
  let core = store.core
  let depAlpha = try await core.createTask(title: "Dependency alpha", notes: "")
  let depBeta = try await core.createTask(title: "Dependency beta", notes: "")
  store.taskDetailDependsOnText = "\(depAlpha.id)\n\(depBeta.id)"
  // The draft holds picker-frame (local-calendar) dates; the save bridges
  // them to the storage frame. Feed the draft what the picker would produce
  // for the stored day, and assert the saved due date in the storage frame.
  let storagePlannedDate = Date(timeIntervalSince1970: 1_779_494_400)
  store.taskDetailHasPlannedDate = true
  store.taskDetailPlannedDate = PlannedDayBridge.displayDate(forStorageDate: storagePlannedDate)
  #expect(store.selectedTaskCanSave)
  await store.saveSelectedTaskDraft()

  #expect(store.selectedTask?.title == "Updated native task")
  #expect(store.selectedTask?.notes == "Edited from detail.")
  #expect(store.selectedTask?.priority == .p3)
  #expect(store.selectedTask?.estimatedMinutes == 45)
  #expect(store.selectedTask?.plannedDate == storagePlannedDate)
  // Tags added in one write surface alphabetically (shared created_at),
  // deduplicated.
  #expect(store.selectedTask?.tags == ["metadata", "native"])
  #expect(store.selectedTask?.dependsOn.sorted() == [depAlpha.id, depBeta.id].sorted())
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreEditsSelectedTaskDueDate() async throws {
  let store = try await makeTaskEditingStore()

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()

  // The detail form now edits the due date (a day anchor, re-anchored to storage
  // like the planned date). Set it in the picker frame; assert the storage frame.
  let storageDueDate = Date(timeIntervalSince1970: 1_779_494_400)
  store.taskDetailHasDueDate = true
  store.taskDetailDueDate = PlannedDayBridge.displayDate(forStorageDate: storageDueDate)
  #expect(store.taskDetailDueDateForSave == storageDueDate)
  #expect(store.selectedTaskCanSave)
  await store.saveSelectedTaskDraft()
  #expect(store.selectedTask?.dueDate == storageDueDate)

  // Clearing the due date persists nil.
  store.setTaskDetailHasDueDate(false)
  #expect(store.taskDetailDueDateForSave == nil)
  #expect(store.selectedTaskCanSave)
  await store.saveSelectedTaskDraft()
  #expect(store.selectedTask?.dueDate == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskDetailEstimateForSaveKeepsExistingOnMalformedInput() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()

  store.taskDetailEstimatedMinutesText = "45"
  #expect(store.taskDetailEstimateForSave(taskID: task.id) == 45)

  store.taskDetailEstimatedMinutesText = ""  // blank clears the estimate
  #expect(store.taskDetailEstimateForSave(taskID: task.id) == nil)

  store.taskDetailEstimatedMinutesText = "30m"  // unparseable → keep existing
  #expect(!store.taskDetailEstimateIsValid)
  #expect(store.taskDetailEstimateForSave(taskID: task.id) == task.estimatedMinutes)

  for invalid in ["0", "1441"] {
    store.taskDetailEstimatedMinutesText = invalid
    #expect(!store.taskDetailEstimateIsValid)
    #expect(store.taskDetailEstimateForSave(taskID: task.id) == task.estimatedMinutes)
  }
}

@MainActor
@Test
func appStoreDoesNotSaveTodayWhenPlannedDateDraftIsMissing() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.dueDate == nil })
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()

  store.taskDetailHasPlannedDate = true
  store.taskDetailPlannedDate = nil

  #expect(store.taskDetailPlannedDateForSave == nil)
  #expect(!store.selectedTaskCanSave)

  await store.saveTaskDetailDraft(id: task.id, preserveSelection: task.id)

  let saved = try #require(store.today.tasks.first { $0.id == task.id })
  #expect(saved.dueDate == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskDetailPlannedDatePickerUsesStableDraftDate() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.dueDate == nil })
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()

  let initialPickerDate = store.taskDetailPlannedDatePickerDate
  #expect(store.taskDetailPlannedDatePickerDate == initialPickerDate)
  #expect(store.taskDetailPlannedDate == nil)

  let editedDate = Date(timeIntervalSince1970: 1_780_012_800)
  store.taskDetailPlannedDatePickerDate = editedDate

  #expect(store.taskDetailPlannedDatePickerDate == editedDate)
  #expect(store.taskDetailPlannedDate == editedDate)
}

@Test
func taskDetailPlannedDateSavePathDoesNotFallbackToToday() throws {
  let root = packageRoot().appending(path: "Sources/LorvexApple/Stores")
  let stateSource = try String(
    contentsOf: root.appending(path: "AppStoreTaskDetailState.swift"),
    encoding: .utf8)
  let actionsSource = try String(
    contentsOf: root.appending(path: "AppStoreSelectedTaskActions.swift"),
    encoding: .utf8)

  #expect(stateSource.contains("var taskDetailPlannedDateForSave: Date?"))
  #expect(actionsSource.contains("plannedDate: taskDetailPlannedDateForSave"))
  #expect(!stateSource.contains("taskDetailPlannedDate ?? Date()"))
  #expect(!actionsSource.contains("taskDetailPlannedDate ?? Date()"))
}

@Test
func taskDetailPlannedDatePickerViewDoesNotFallbackToDateNow() throws {
  let root = packageRoot().appending(path: "Sources/LorvexApple")
  let viewSource = try String(
    contentsOf: root.appending(path: "Views/TaskDetailMetadataSection.swift"),
    encoding: .utf8)

  #expect(viewSource.contains("store.taskDetailPlannedDatePickerDate"))
  #expect(!viewSource.contains("taskDetailPlannedDate ?? Date()"))
}

@MainActor
@Test
func appStoreNavigationSaveKeepsOtherEditsWhenEstimateMalformed() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  store.selectedTaskID = first.id
  store.syncSelectedTaskDraft()
  store.taskDetailTitle = "Edited with a malformed estimate"
  store.taskDetailEstimatedMinutesText = "30m"  // unparseable

  await store.saveTaskDetailDraft(id: first.id, preserveSelection: second.id)

  let saved = try #require(store.today.tasks.first { $0.id == first.id })
  #expect(saved.title == "Edited with a malformed estimate")
  // The malformed estimate is ignored — the task keeps its prior value rather
  // than dropping the whole edit.
  #expect(saved.estimatedMinutes == first.estimatedMinutes)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreSavesDirtyTaskDraftWhilePreservingNewSelection() async throws {
  let suiteName = "appStoreSavesDirtyTaskDraftWhilePreservingNewSelection.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.selection = .today
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  store.selectedTaskID = first.id
  store.syncSelectedTaskDraft()
  store.taskDetailTitle = "Autosaved before selection changes"

  await store.saveTaskDetailDraft(id: first.id, preserveSelection: second.id)

  #expect(store.selectedTaskID == second.id)
  #expect(
    store.today.tasks.first { $0.id == first.id }?.title == "Autosaved before selection changes")
  #expect(store.selectedTask?.id == second.id)
  #expect(!store.selectedTaskDraftHasChanges)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreDoesNotSnapSelectionBackWhenUserNavigatesPastTheSaveTarget() async throws {
  let suiteName =
    "appStoreDoesNotSnapSelectionBackWhenUserNavigatesPastTheSaveTarget.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.selection = .today
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  let third = try #require(store.today.tasks.dropFirst(2).first)
  store.selectedTaskID = first.id
  store.syncSelectedTaskDraft()
  store.taskDetailTitle = "Edited first while navigating away"
  // The user navigated first → second (queuing this save with preserve=second),
  // then on to a third task before the save's awaits resumed.
  store.selectedTaskID = third.id

  await store.saveTaskDetailDraft(id: first.id, preserveSelection: second.id)

  // The stale save must not snap the selection back from the task the user just
  // opened to its older preserve target.
  #expect(store.selectedTaskID == third.id)
  #expect(
    store.today.tasks.first { $0.id == first.id }?.title == "Edited first while navigating away")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreSavesSelectedTaskDraftOnlyWhenDirtyAndValid() async throws {
  let store = try await makeTaskEditingStore()

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()

  await store.saveSelectedTaskDraftIfNeeded()
  #expect(store.selectedTask?.title == task.title)
  #expect(store.errorMessage == nil)

  store.taskDetailTitle = "Committed on blur"
  store.taskDetailEstimatedMinutesText = "not a number"
  await store.saveSelectedTaskDraftIfNeeded()
  #expect(store.selectedTask?.title == task.title)
  #expect(store.selectedTaskDraftHasChanges)

  store.taskDetailEstimatedMinutesText = ""
  await store.saveSelectedTaskDraftIfNeeded()
  #expect(store.selectedTask?.title == "Committed on blur")
  #expect(!store.selectedTaskDraftHasChanges)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreEditsSelectedPreviewTaskRecurrence() async throws {
  let store = try await makeTaskEditingStore()

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  #expect(!store.taskDetailRecurrenceCanSave)

  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .weekly
  store.taskDetailRecurrenceIntervalText = "2"
  store.taskDetailRecurrenceByDay.insert("MO")
  store.taskDetailRecurrenceByDay.insert("WE")

  #expect(store.taskDetailRecurrenceCanSave)
  await store.saveSelectedTaskRecurrence()

  #expect(store.selectedTask?.recurrence?.freq == .weekly)
  #expect(store.selectedTask?.recurrence?.interval == 2)
  #expect(store.selectedTask?.recurrence?.byDay == ["MO", "WE"])
  #expect(store.taskDetailHasRecurrence)
  #expect(store.taskDetailRecurrenceFrequency == .weekly)
  #expect(store.taskDetailRecurrenceIntervalText == "2")
  #expect(store.taskDetailRecurrenceByDay == Set(["MO", "WE"]))
  #expect(!store.taskDetailRecurrenceCanSave)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreRecurrenceIntervalEditPreservesAdvancedFields() async throws {
  let store = try await makeTaskEditingStore()
  let core = store.core
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  let advanced = TaskRecurrenceRule(
    freq: .monthly, interval: 1, byDay: ["1MO"], byMonth: [3],
    byMonthDay: [1, 15], bySetPos: [1], wkst: "SU", count: 12)
  _ = try await core.setTaskRecurrence(taskID: task.id, rule: advanced)
  await store.refresh()
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft(force: true)

  #expect(!store.taskDetailRecurrenceCanSave)
  store.taskDetailRecurrenceIntervalText = "2"
  #expect(store.selectedTaskHasUnsavedEditorState)
  await store.saveSelectedTaskRecurrence()

  // The awaited save reloads, but under maximum parallel suite load the reload
  // can coalesce into a trailing re-run that has not repopulated the derived
  // selection yet. Wait with real bounded backoff (same discipline as the
  // focus-navigation converge helper); a genuine regression still exhausts the
  // loop and fails the require below.
  var backoffNs: UInt64 = 1_000_000
  for _ in 0..<20 where store.selectedTask?.recurrence == nil {
    try? await Task.sleep(nanoseconds: backoffNs)
    backoffNs = min(backoffNs * 2, 50_000_000)
    await store.refresh()
  }
  let saved = try #require(store.selectedTask?.recurrence)
  #expect(saved.interval == 2)
  #expect(saved.byDay == advanced.byDay)
  #expect(saved.byMonth == advanced.byMonth)
  #expect(saved.byMonthDay == advanced.byMonthDay)
  #expect(saved.bySetPos == advanced.bySetPos)
  #expect(saved.wkst == advanced.wkst)
  #expect(saved.count == advanced.count)
  #expect(!store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test
func appStoreNoOpRecurrenceSavePreservesExceptions() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  _ = try await core.setTaskRecurrence(
    taskID: task.id, rule: TaskRecurrenceRule(freq: .daily, interval: 1))
  _ = try await core.addTaskRecurrenceException(
    taskID: task.id, exceptionDate: "2026-08-12")
  await store.refresh()
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft(force: true)
  #expect(!store.taskDetailRecurrenceCanSave)

  // The mutation method itself must enforce the no-op, not just its disabled
  // button. Entering setTaskRecurrence would clear the EXDATE registry.
  await store.saveSelectedTaskRecurrence()

  let persisted = try await core.loadTask(id: task.id)
  #expect(persisted.recurrenceExceptions == ["2026-08-12"])
}

@MainActor
@Test
func taskDetailRecurrenceIntervalIsValidReflectsParseability() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  store.syncSelectedTaskDraft()

  // Empty is valid — an omitted interval defaults to 1.
  store.taskDetailRecurrenceIntervalText = ""
  #expect(store.taskDetailRecurrenceIntervalIsValid)

  store.taskDetailRecurrenceIntervalText = "3"
  #expect(store.taskDetailRecurrenceIntervalIsValid)

  // Non-positive and unparseable text are both invalid (Save stays disabled).
  store.taskDetailRecurrenceIntervalText = "0"
  #expect(!store.taskDetailRecurrenceIntervalIsValid)

  store.taskDetailRecurrenceIntervalText = "x"
  #expect(!store.taskDetailRecurrenceIntervalIsValid)
}

@MainActor
@Test
func appStoreRemovesSelectedPreviewTaskRecurrence() async throws {
  let store = try await makeTaskEditingStore()

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  store.taskDetailHasRecurrence = true
  store.taskDetailRecurrenceFrequency = .daily
  await store.saveSelectedTaskRecurrence()

  #expect(store.selectedTask?.recurrence != nil)

  store.taskDetailHasRecurrence = false
  #expect(store.taskDetailRecurrenceCanSave)
  await store.saveSelectedTaskRecurrence()

  #expect(store.selectedTask?.recurrence == nil)
  #expect(store.selectedTask?.recurrenceExceptions.isEmpty == true)
  #expect(!store.taskDetailHasRecurrence)
  #expect(!store.taskDetailRecurrenceCanSave)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreMutatesPreviewChecklistItems() async throws {
  let store = try await makeTaskEditingStore()

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  let initialCount = store.selectedTask?.checklistItems.count ?? 0
  store.taskDetailNewChecklistText = "Check native detail"
  await store.addChecklistItemToSelectedTask()
  // New item is appended; find it by text since seed data may already have items.
  let item = try #require(
    store.selectedTask?.checklistItems.first { $0.text == "Check native detail" })

  #expect(store.taskDetailNewChecklistText == "")

  await store.toggleChecklistItem(item)
  let completed = try #require(store.selectedTask?.checklistItems.first { $0.id == item.id })
  #expect(completed.completedAt != nil)

  store.taskDetailChecklistDrafts[completed.id] = "Updated native detail"
  await store.updateChecklistItem(completed)
  let updated = try #require(store.selectedTask?.checklistItems.first { $0.id == item.id })
  #expect(updated.text == "Updated native detail")

  store.taskDetailNewChecklistText = "Second native detail"
  await store.addChecklistItemToSelectedTask()
  let second = try #require(
    store.selectedTask?.checklistItems.first { $0.text == "Second native detail" })
  await store.moveChecklistItem(second, direction: -1)
  // After move up, second should be before updated in the list (not necessarily index 0 with seed items)
  let items = try #require(store.selectedTask?.checklistItems)
  let secondIndex = try #require(items.firstIndex { $0.id == second.id })
  let updatedIndex = try #require(items.firstIndex { $0.id == updated.id })
  #expect(secondIndex < updatedIndex)

  await store.removeChecklistItem(updated)
  await store.removeChecklistItem(second)
  #expect(store.selectedTask?.checklistItems.count == initialCount)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreReordersChecklistItemsByDrag() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id

  for text in ["Drag A", "Drag B", "Drag C"] {
    store.taskDetailNewChecklistText = text
    await store.addChecklistItemToSelectedTask()
  }
  let a = try #require(store.selectedTask?.checklistItems.first { $0.text == "Drag A" })
  let b = try #require(store.selectedTask?.checklistItems.first { $0.text == "Drag B" })
  let c = try #require(store.selectedTask?.checklistItems.first { $0.text == "Drag C" })

  // Dragging A down onto C lands it after C: relative order becomes B, C, A.
  await store.reorderChecklistItem(a.id, toPositionOf: c.id)
  func index(_ id: TaskChecklistItem.ID) throws -> Int {
    try #require(store.selectedTask?.checklistItems.firstIndex { $0.id == id })
  }
  #expect(try index(b.id) < index(c.id))
  #expect(try index(c.id) < index(a.id))

  // Dragging A back up onto B lands it before B: relative order becomes A, B, C.
  await store.reorderChecklistItem(a.id, toPositionOf: b.id)
  #expect(try index(a.id) < index(b.id))
  #expect(try index(b.id) < index(c.id))

  // Unknown / self targets are inert.
  await store.reorderChecklistItem(a.id, toPositionOf: a.id)
  await store.reorderChecklistItem("not-a-real-id", toPositionOf: b.id)
  #expect(try index(a.id) < index(b.id))

  for item in [a, b, c] {
    await store.removeChecklistItem(item)
  }
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreMutatesPreviewTaskReminders() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let store = try await makeTaskEditingStore(taskReminderScheduler: scheduler)
  let reminderDate = Date().addingTimeInterval(3600)

  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  let initialReminderCount = store.selectedTask?.reminders.count ?? 0
  let initialReminderIDs = Set(store.selectedTask?.reminders.map(\.id) ?? [])
  store.taskDetailReminderDate = reminderDate
  await store.addReminderToSelectedTask()
  let reminder = try #require(
    store.selectedTask?.reminders.first { !initialReminderIDs.contains($0.id) })
  let storedDate = try #require(
    LorvexDateFormatters.iso8601Fractional.date(from: reminder.reminderAt))

  #expect(abs(storedDate.timeIntervalSince(reminderDate)) < 1)
  // lastScheduledReminderCount reflects all reminders across all tasks; just check it increased.
  #expect(store.lastScheduledReminderCount >= 1)
  #expect(store.lastTaskReminderScheduleReport.status == .scheduled)

  await store.removeReminder(reminder)
  #expect(store.selectedTask?.reminders.count == initialReminderCount)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreCancelsAndReopensSelectedPreviewTask() async throws {
  let suiteName = "AppStoreCancelsAndReopensSelectedPreviewTask.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, defaults: defaults)

  await store.refresh()
  let selectedID = try #require(store.today.tasks.first?.id)
  store.selectedTaskID = selectedID
  #expect(store.selectedTaskCanCancel)

  await store.cancelSelectedTask()
  #expect(store.selectedTask?.status == .cancelled)
  // The Today snapshot carries only open tasks; the cancelled row is the
  // store's evidence.
  #expect(!store.today.tasks.contains { $0.id == selectedID })
  #expect(try await core.loadTask(id: selectedID).status == .cancelled)
  #expect(store.selectedTaskCanReopen)
  #expect(!store.selectedTaskCanCancel)

  await store.reopenSelectedTask()
  #expect(store.selectedTask?.status == .open)
  #expect(store.openTasks.contains { $0.id == selectedID })
  #expect(store.selectedTaskCanCancel)
}

@MainActor
@Test
func appStoreMarksSelectedTaskSomedayAndActivatesItBackToOpen() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectedTaskID = task.id
  #expect(store.selectedTaskCanMarkSomeday)
  #expect(!store.selectedTaskIsSomeday)

  await store.markSelectedTaskSomeday()
  #expect(store.selectedTask?.status == .someday)
  #expect(store.selectedTaskIsSomeday)
  #expect(!store.selectedTaskCanMarkSomeday)
  // A parked task drops out of Today's open lanes while keeping its list.
  #expect(!store.openTasks.contains { $0.id == task.id })
  #expect(store.selectedTask?.listID == task.listID)
  #expect(store.errorMessage == nil)

  // Activating (someday → open) reuses reopenTask, which reads the real row
  // status and moves it cleanly back to open.
  await store.reopenSelectedTask()
  #expect(store.selectedTask?.status == .open)
  #expect(!store.selectedTaskIsSomeday)
  #expect(store.openTasks.contains { $0.id == task.id })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreBatchMarksSelectedWorkspaceTasksSomeday() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  await store.loadTaskWorkspace()
  let openTasks = Array(store.taskWorkspaceOpenTasks.prefix(2))
  let openIDs = openTasks.map(\.id)
  #expect(!openIDs.isEmpty)
  store.setTaskWorkspaceSelection(Set(openIDs))

  await store.markTaskWorkspaceSelectionSomeday()

  let somedayIDs = Set(store.taskWorkspaceSomedayTasks.map(\.id))
  for id in openIDs {
    #expect(somedayIDs.contains(id))
  }
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreWeeklyReviewSnapshotSurfacesTopSomeday() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectedTaskID = task.id
  await store.markSelectedTaskSomeday()

  let review = try await store.core.loadWeeklyReview()
  #expect(review.someday >= 1)
  #expect(review.topSomeday.contains { $0.id == task.id })
  #expect(review.topSomeday.allSatisfy { $0.status == "someday" })
}

@MainActor
@Test
func appStoreLoadSelectedTaskDetailPreservesInProgressTitleEdit() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()

  // Simulate the user typing a new title before the async detail load lands.
  store.taskDetailTitle = "Half-typed title the load must not eat"
  #expect(store.selectedTaskDraftHasChanges)

  await store.loadSelectedTaskDetail()

  // The in-flight load's force-sync must not overwrite the unsaved edit.
  #expect(store.taskDetailTitle == "Half-typed title the load must not eat")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreDoesNotAutosaveEmptySelectedTaskTitle() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id

  store.syncSelectedTaskDraft()
  store.taskDetailTitle = ""

  await store.saveSelectedTaskDraftIfNeeded()

  #expect(store.selectedTask?.title == task.title)
  #expect(store.taskDetailTitle.isEmpty)
  #expect(store.selectedTaskDraftHasChanges)
  #expect(!store.selectedTaskCanSave)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreNavigationAutosaveSkipsEmptyTitleDraft() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  store.selectedTaskID = first.id
  store.syncSelectedTaskDraft()

  store.taskDetailTitle = ""
  store.selectedTaskID = second.id
  await store.saveTaskDetailDraft(id: first.id, preserveSelection: second.id)

  let unchanged = try #require(store.today.tasks.first { $0.id == first.id })
  #expect(unchanged.title == first.title)
  #expect(store.selectedTaskID == second.id)
  #expect(store.taskDetailTitle == second.title)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreLoadSelectedTaskDetailRefreshesDraftWhenNoUnsavedEdits() async throws {
  let store = try await makeTaskEditingStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  #expect(!store.selectedTaskDraftHasChanges)

  await store.loadSelectedTaskDetail()

  // With no unsaved edits, the load refreshes the draft from the stored record.
  #expect(store.taskDetailTitle == store.selectedTask?.title)
  #expect(store.taskDetailDraftTaskID == task.id)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreLoadSelectedTaskDetailHydratesDraftAfterRestoredSelection() async throws {
  let core = try await makeSeededInMemoryCore()
  let snapshot = try await core.loadToday()
  let task = try #require(snapshot.tasks.first)
  let store = AppStore(core: core)

  // Simulate app launch restoring only the selected task ID before any task
  // collections have loaded. The inspector may appear with an empty draft, but
  // that draft is not a user edit and must be replaced by the loaded task.
  store.selectedTaskID = task.id
  store.clearSelectedTaskDraft()
  #expect(store.selectedTask == nil)
  #expect(!store.selectedTaskDraftHasChanges)

  await store.loadSelectedTaskDetail()

  #expect(store.selectedTask?.id == task.id)
  #expect(store.taskDetailTitle == task.title)
  #expect(store.taskDetailPriority == task.priority)
  #expect(store.taskDetailDraftTaskID == task.id)
  #expect(!store.selectedTaskDraftHasChanges)
  #expect(store.errorMessage == nil)
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}
