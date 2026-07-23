import Foundation
import LorvexCore

extension MobileStore {
  @discardableResult
  public func completeTask(_ id: LorvexTask.ID) async -> Bool {
    let didMutate = await mutateTaskReturningToday(id: id) {
      try await core.completeTask(id: id)
    }
    if didMutate {
      feedbackProvider.playFeedback(.taskCompleted)
    }
    return didMutate
  }

  @discardableResult
  public func cancelTask(_ id: LorvexTask.ID) async -> Bool {
    let result = await mutateTaskReturningToday(id: id) {
      try await core.cancelTask(id: id)
    }
    if result { feedbackProvider.playFeedback(.taskCancelled) }
    return result
  }

  @discardableResult
  public func reopenTask(_ id: LorvexTask.ID) async -> Bool {
    let result = await mutateTaskReturningToday(id: id) {
      try await core.reopenTask(id: id)
    }
    if result { feedbackProvider.playFeedback(.taskReopened) }
    return result
  }

  /// Start a task (`open → in_progress`) — put the "In Progress" marker on.
  /// A dependency-blocked start surfaces the core's typed error.
  @discardableResult
  public func startTask(_ id: LorvexTask.ID) async -> Bool {
    let result = await mutateTaskReturningToday(id: id) {
      try await core.startTask(id: id)
    }
    if result { feedbackProvider.playFeedback(.taskReopened) }
    return result
  }

  /// Remove the "In Progress" marker (`in_progress → open`, "Mark as Not
  /// Started"). Leaves planned_date / defer_count intact.
  @discardableResult
  public func markTaskNotStarted(_ id: LorvexTask.ID) async -> Bool {
    let result = await mutateTaskReturningToday(id: id) {
      try await core.pauseTask(id: id)
    }
    if result { feedbackProvider.playFeedback(.taskReopened) }
    return result
  }

  @discardableResult
  public func deferTaskToTomorrow(_ id: LorvexTask.ID) async -> Bool {
    let didMutate = await mutateTaskReturningToday(id: id) {
      try await core.deferTask(id: id, until: tomorrowDate())
    }
    if didMutate {
      feedbackProvider.playFeedback(.taskDeferred)
    }
    return didMutate
  }

  /// Park an open task in the GTD Someday/Maybe bucket (`status = 'someday'`),
  /// leaving its list and dates intact. Mirrors the macOS "Move to Someday"
  /// action and the MCP `set_task_someday` tool; reversed via ``reopenTask(_:)``.
  @discardableResult
  public func markTaskSomeday(_ id: LorvexTask.ID) async -> Bool {
    let didMutate = await mutateTaskReturningTask(id: id) {
      try await core.markTaskSomeday(id: id)
    }
    if didMutate {
      feedbackProvider.playFeedback(.taskDeferred)
    }
    return didMutate
  }

  @discardableResult
  public func completeTasks(_ ids: [LorvexTask.ID]) async -> Bool {
    let uniqueIDs = stableUniqueTaskIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    let didMutate = await mutateTaskReturningToday {
      try await core.batchCompleteTasks(ids: uniqueIDs).snapshot
    }
    if didMutate {
      feedbackProvider.playFeedback(.taskCompleted)
    }
    return didMutate
  }

  @discardableResult
  public func reopenTasks(_ ids: [LorvexTask.ID]) async -> Bool {
    let uniqueIDs = stableUniqueTaskIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    let didMutate = await mutateTaskReturningToday {
      try await core.batchReopenTasks(ids: uniqueIDs).snapshot
    }
    if didMutate {
      feedbackProvider.playFeedback(.taskReopened)
    }
    return didMutate
  }

  @discardableResult
  public func deferTasksToTomorrow(_ ids: [LorvexTask.ID]) async -> Bool {
    let uniqueIDs = stableUniqueTaskIDs(ids)
    guard !uniqueIDs.isEmpty else { return false }
    let didMutate = await mutateTaskReturningToday {
      try await core.batchDeferTasks(ids: uniqueIDs, until: tomorrowDate())
    }
    if didMutate {
      feedbackProvider.playFeedback(.taskDeferred)
    }
    return didMutate
  }

  private func stableUniqueTaskIDs(_ ids: [LorvexTask.ID]) -> [LorvexTask.ID] {
    var seen = Set<LorvexTask.ID>()
    return ids.filter { seen.insert($0).inserted }
  }

  /// The configured product day's tomorrow as a storage-frame date. This stays
  /// stable when the iPhone's current zone differs from the synced product zone.
  private func tomorrowDate() throws -> Date {
    guard
      let tomorrow = PlannedDayBridge.storageDate(
        forLogicalDay: logicalTodayString,
        addingDays: 1)
    else {
      throw LorvexCoreError.unsupportedOperation("Couldn't compute tomorrow's date.")
    }
    return tomorrow
  }

  public func planTask(_ id: LorvexTask.ID, on day: Date) async {
    await mutateTaskReturningTask(id: id) {
      let task = try await core.loadTask(id: id)
      return try await core.updateTask(
        id: task.id,
        title: task.title,
        notes: task.notes,
        priority: task.priority,
        estimatedMinutes: task.estimatedMinutes,
        dueDate: task.dueDate,
        plannedDate: PlannedDayBridge.storageDate(forLocalInstant: day),
        availableFrom: task.availableFrom,
        tags: task.tags,
        dependsOn: task.dependsOn
      )
    }
  }

  /// Single entry point for an interactive cancel. A recurring task routes to
  /// the occurrence-vs-series confirmation (``pendingRecurringCancelTaskID``);
  /// a non-recurring task cancels immediately. This mirrors the macOS
  /// `AppStore.requestCancel(_:)` so both surfaces offer the same choice
  /// instead of silently cancelling one occurrence and spawning the next.
  public func requestCancelTask(_ task: LorvexTask) async {
    if task.recurrence != nil {
      pendingRecurringCancelTaskID = task.id
    } else {
      await cancelTask(task.id)
    }
  }

  /// Apply a recurring-task cancel for the chosen scope.
  /// `.thisOccurrence` cancels the current task and lets the series spawn its
  /// successor; `.all` removes the recurrence rule first so no successor is
  /// spawned, then cancels. Clears ``pendingRecurringCancelTaskID``.
  @discardableResult
  public func cancelRecurringTask(id: LorvexTask.ID, scope: RecurringTaskCancelScope) async -> Bool {
    pendingRecurringCancelTaskID = nil
    let result = await mutateTaskReturningToday(id: id) {
      var snapshot: TodaySnapshot?
      for operation in scope.coreOperations {
        switch operation {
        case .removeRecurrence:
          _ = try await core.removeTaskRecurrence(taskID: id)
        case .cancelTask:
          snapshot = try await core.cancelTask(id: id)
        }
      }
      guard let snapshot else { return try await core.loadToday() }
      return snapshot
    }
    if result { feedbackProvider.playFeedback(.taskCancelled) }
    return result
  }

}
