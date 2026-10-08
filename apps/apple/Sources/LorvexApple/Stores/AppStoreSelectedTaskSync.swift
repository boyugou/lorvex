import Foundation
import LorvexCore

extension AppStore {
  func selectTaskFromList(_ id: LorvexTask.ID?) {
    selectedTaskID = id
    syncSelectedTaskDraft()
  }

  func loadSelectedTaskDetail() async {
    guard let id = selectedTaskID else { return }
    do {
      let detail = try await core.loadTask(id: id)
      replaceTask(detail)
      // Refresh the draft from the fuller loaded record (checklist, recurrence,
      // …), but only when the selection hasn't moved on and the user has no
      // unsaved scalar edits — a force-sync mid-edit would replace the title or
      // notes the user is typing with the stored values.
      if selectedTaskID == id, !selectedTaskHasUnsavedEditorState {
        syncSelectedTaskDraft(force: true)
      }
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
      if selectedTaskID == id, selectedTask == nil {
        selectedTaskID = nil
        clearSelectedTaskDraft()
      }
    }
  }

  /// Re-reads the selected task from the core into the store's own copy of it.
  ///
  /// The inspector reads ``selectedTask``, which falls back to this copy once a
  /// change has taken the task out of every list the store loads: a completed,
  /// deferred, parked, or moved task is in none of them. Without a re-read the
  /// inspector keeps showing the task as it was when it was opened. A failed
  /// read, such as for a task another device just deleted, leaves the copy as it
  /// was; the selection check that follows a refresh handles that case.
  func refreshSelectedTaskRecord() async {
    guard let id = selectedTaskID, let task = try? await core.loadTask(id: id),
      selectedTaskID == id
    else { return }
    replaceTask(task)
  }

  /// ``refreshSelectedTaskRecord()`` for a local change to a task, then the
  /// inspector's draft adopts the stored values, so a changed day or status
  /// shows in its fields. A draft with unsaved edits is kept: whether the
  /// draft is clean is read before the record changes, because afterward every
  /// draft differs from a record a change has touched.
  func reloadSelectedTaskAfterMutation() async {
    let snapshot = taskDetailReloadSnapshot()
    await refreshSelectedTaskRecord()
    guard let id = selectedTaskID, dirtyTaskIDToPreserve(after: snapshot) != id else { return }
    syncSelectedTaskDraft(force: true)
  }

  func syncSelectedTaskDraft() {
    syncSelectedTaskDraft(force: false)
  }

  func syncSelectedTaskDraft(force: Bool) {
    guard let task = selectedTask else {
      clearSelectedTaskDraft()
      return
    }
    let isNewTask = taskDetailDraftTaskID != task.id
    guard force || isNewTask else { return }
    taskDetailDraftTaskID = task.id
    taskDetailStorage.taskDetailDraftSource = task
    taskDetailTitle = task.title
    taskDetailNotes = task.notes
    taskDetailPriority = task.priority
    taskDetailEstimatedMinutesText = task.estimatedMinutes.map { LorvexNumberInput.text(for: $0) } ?? ""
    // The stored planned date is a UTC-midnight day anchor; the picker is a
    // local-calendar control, so re-anchor to local midnight or the picker
    // shows the previous day west of UTC.
    let pickerDate = task.plannedDate.map { PlannedDayBridge.displayDate(forStorageDate: $0) }
    taskDetailPlannedDate = pickerDate
    if let pickerDate {
      taskDetailStorage.taskDetailPlannedDatePickerDate = pickerDate
    }
    taskDetailHasPlannedDate = task.plannedDate != nil
    taskDetailPlannedTime = task.plannedTime
    // Due date is a day anchor too — re-anchor the same way as the planned date.
    let duePickerDate = task.dueDate.map { PlannedDayBridge.displayDate(forStorageDate: $0) }
    taskDetailDueDate = duePickerDate
    if let duePickerDate {
      taskDetailStorage.taskDetailDueDatePickerDate = duePickerDate
    }
    taskDetailHasDueDate = task.dueDate != nil
    // Available-from (defer-until) is a UTC-midnight day anchor too — re-anchor
    // to local midnight for the picker the same way as the planned/due dates.
    let availablePickerDate = task.availableFrom.map {
      PlannedDayBridge.displayDate(forStorageDate: $0)
    }
    taskDetailAvailableFrom = availablePickerDate
    if let availablePickerDate {
      taskDetailStorage.taskDetailAvailableFromPickerDate = availablePickerDate
    }
    taskDetailHasAvailableFrom = task.availableFrom != nil
    taskDetailTagsText = task.tags.joined(separator: ", ")
    taskDetailDependsOnText = task.dependsOn.joined(separator: ", ")
    taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft(rule: task.recurrence)
    taskDetailChecklistDrafts = Dictionary(
      uniqueKeysWithValues: task.checklistItems.map { ($0.id, $0.text) }
    )
    if isNewTask {
      resetTaskDetailReminderDate()
    }
  }

  func resetTaskDetailReminderDate(now: Date = Date()) {
    taskDetailReminderDate = AppStoreTaskDetailStorage.defaultReminderDate(
      now: now,
      timeZone: logicalTimeZone)
  }

  /// Refresh the checklist text drafts from the selected task, leaving the scalar
  /// draft (title, notes, priority, …) untouched. Checklist and reminder
  /// mutations call this instead of a full force-sync so they never clobber an
  /// in-progress, unsaved title or notes edit in the inspector.
  ///
  /// The per-item drafts are *merged*, not rebuilt: an item whose draft still
  /// differs from the stored text keeps that in-progress edit, while untouched
  /// items adopt the server text and items that no longer exist are dropped. A
  /// blind rebuild would revert a half-typed checklist label whenever a sibling
  /// action (toggle / reorder / add / remove) refreshes the task.
  ///
  /// The draft's source record takes the same checklist, so the items the merge
  /// adopted do not read as edits and the ones still being typed do.
  func syncSelectedTaskChecklistDrafts() {
    guard let task = selectedTask else { return }
    let previous = taskDetailChecklistDrafts
    taskDetailChecklistDrafts = Dictionary(
      uniqueKeysWithValues: task.checklistItems.map { item in
        if let draft = previous[item.id], draft != item.text {
          return (item.id, draft)
        }
        return (item.id, item.text)
      }
    )
    if var source = taskDetailStorage.taskDetailDraftSource, source.id == task.id {
      source.checklistItems = task.checklistItems
      taskDetailStorage.taskDetailDraftSource = source
    }
  }

  func clearSelectedTaskDraft() {
    taskDetailStorage.resetDraft()
  }

  func replaceTask(_ task: LorvexTask) {
    taskDetailStorage.loadedTasksByID[task.id] = task
    if let index = today.inProgressTasks.firstIndex(where: { $0.id == task.id }) {
      today.inProgressTasks[index] = task
    }
    if let index = today.tasks.firstIndex(where: { $0.id == task.id }) {
      today.tasks[index] = task
    }
    if var detail = selectedListDetail,
      let index = detail.tasks.firstIndex(where: { $0.id == task.id })
    {
      detail.tasks[index] = task
      selectedListDetail = detail
    }
    replaceTaskInWorkspace(task)
    if let index = todayStorage.doneTodayTasks.firstIndex(where: { $0.id == task.id }) {
      todayStorage.doneTodayTasks[index] = task
    }
  }
}
