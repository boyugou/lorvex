import Foundation
import LorvexCore

extension AppStore {
  /// Signal the inline quick-add row of the current task surface to claim
  /// keyboard focus. ⌘N (the New Task command) and the empty-state capture
  /// buttons call this instead of opening a popup window — every `QuickAddRow`
  /// observes `quickAddFocusToken` and focuses its field when the value bumps.
  func requestQuickAddFocus() {
    quickAddFocusToken &+= 1
  }

  func createDraftTask() async {
    guard !isCreating else { return }
    let titles = CaptureTitleParser.titles(from: draftTitle)
    // An empty capture field has nothing to create — no-op silently rather than
    // pushing an empty title into the core and surfacing a "title required"
    // error the user never deliberately triggered.
    guard !titles.isEmpty else { return }
    isCreating = true
    defer { isCreating = false }
    let notes = draftNotes
    if titles.count > 1 {
      await createTasks(titles: titles, notes: notes)
    } else {
      await createSingleTask(title: draftTitle, notes: notes)
    }
    if errorMessage == nil {
      clearDraftCapture()
    }
  }

  func clearDraftCapture() {
    draftTitle = ""
    draftNotes = ""
  }

  func createTask(title: String, notes: String) async {
    guard !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    await createSingleTask(title: title, notes: notes)
  }

  private func createSingleTask(title: String, notes: String) async {
    guard
      let task = await performCanonicalMutation({
        try await core.createTask(title: title, notes: notes)
      })
    else { return }

    selectedTaskID = task.id
    await reconcileAfterCommittedMutation(source: "macos.task.create.reconcile") {
      today = try await core.loadToday()
      currentFocus = try await core.loadCurrentFocus(date: logicalTodayDateString)
    }
    await reindexTasksForSpotlight()
    await republishSurfacesAfterLocalMutation()
    feedbackProvider.playFeedback(.captureSubmitted)
    selection = .today
  }

  /// Create a task directly into `listID` without leaving the current
  /// workspace — the inline quick-add path. Unlike `createTask` (the global
  /// capture, which navigates to Today and selects the new task), this stays
  /// where the user is typing so consecutive adds flow, and reloads only the
  /// surfaces that show the list's tasks.
  func createTaskInList(title: String, listID: LorvexList.ID) async {
    guard !isCreating else { return }
    guard let trimmed = title.trimmedNilIfEmpty else { return }
    isCreating = true
    defer { isCreating = false }
    guard
      await performCanonicalMutation({
        try await core.createTask(TaskCreateDraft(title: trimmed, listID: listID))
      }) != nil
    else { return }

    await reconcileAfterCommittedMutation(source: "macos.task.create_in_list.reconcile") {
      today = try await core.loadToday()
      lists = try await core.loadLists()
      try await loadSelectedListDetail()
      try await reloadTaskWorkspaceIfLoadedReportingFailure()
    }
    await reindexTasksForSpotlight()
    await republishSurfacesAfterLocalMutation()
    feedbackProvider.playFeedback(.captureSubmitted)
  }

  /// Create a task into the default/inbox list without leaving the current
  /// view — the inline quick-add path for the all-tasks Tasks workspace (no list
  /// scope). Same stay-in-place contract as `createTaskInList(title:listID:)`:
  /// unlike the global `createTask(title:notes:)`, this neither navigates to
  /// Today nor selects the new task, so consecutive adds flow in place.
  func createTaskInInbox(title: String) async {
    guard !isCreating else { return }
    guard let trimmed = title.trimmedNilIfEmpty else { return }
    isCreating = true
    defer { isCreating = false }
    guard
      await performCanonicalMutation({
        try await core.createTask(title: trimmed, notes: "")
      }) != nil
    else { return }

    await reconcileAfterCommittedMutation(source: "macos.task.create_in_inbox.reconcile") {
      today = try await core.loadToday()
      lists = try await core.loadLists()
      try await reloadTaskWorkspaceIfLoadedReportingFailure()
    }
    await reindexTasksForSpotlight()
    await republishSurfacesAfterLocalMutation()
    feedbackProvider.playFeedback(.captureSubmitted)
  }

  /// Create a task planned for today without leaving the Today view — the
  /// inline quick-add path for the daily plan. Same stay-in-place contract as
  /// `createTaskInList(title:listID:)`.
  func createTaskPlannedToday(title: String) async {
    guard !isCreating else { return }
    guard let trimmed = title.trimmedNilIfEmpty else { return }
    isCreating = true
    defer { isCreating = false }
    guard
      await performCanonicalMutation({
        let plannedDate = try storageDate(daysFromLogicalToday: 0)
        return try await core.createTask(
          TaskCreateDraft(title: trimmed, plannedDate: plannedDate))
      }) != nil
    else { return }

    await reconcileAfterCommittedMutation(source: "macos.task.create_planned_today.reconcile") {
      today = try await core.loadToday()
      // A planned task also lands in the calendar's scheduled lane.
      try await refreshCurrentCalendarTimeline()
      try await loadSelectedListDetail()
      try await reloadTaskWorkspaceIfLoadedReportingFailure()
    }
    await reindexTasksForSpotlight()
    await republishSurfacesAfterLocalMutation()
    feedbackProvider.playFeedback(.captureSubmitted)
  }

  func createTasks(titles: [String], notes: String) async {
    let drafts = titles.map { TaskCreateDraft(title: $0, notes: notes) }
    guard
      let tasks = await performCanonicalMutation({
        try await core.batchCreateTasks(drafts)
      })
    else { return }

    selectedTaskID = tasks.first?.id
    await reconcileAfterCommittedMutation(source: "macos.task.batch_create.reconcile") {
      today = try await core.loadToday()
      currentFocus = try await core.loadCurrentFocus(date: logicalTodayDateString)
    }
    await reindexTasksForSpotlight()
    await republishSurfacesAfterLocalMutation()
    feedbackProvider.playFeedback(.captureSubmitted)
    selection = .today
  }

}
