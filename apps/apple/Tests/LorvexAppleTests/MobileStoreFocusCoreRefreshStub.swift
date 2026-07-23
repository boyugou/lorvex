import Foundation
import LorvexCore
import LorvexMobile
import Testing

extension StubFocusCoreService {
  func loadToday() async throws -> TodaySnapshot {
    loadTodayCallCount += 1
    loadTodayAppliedInboundBatchCounts.append(appliedInboundBatchCount())
    if let loadTodayError {
      throw loadTodayError
    }
    // Capture the result BEFORE gating so a gated caller returns the data as
    // of its entry — modelling an older read whose completion lands after a
    // newer read committed.
    let result: TodaySnapshot
    if let todayOverride {
      result = todayOverride
    } else {
      result = try await preview.loadToday()
    }
    if let loadTodayGate {
      await loadTodayGate()
    }
    return result
  }
  func loadCurrentFocus(date: String) async throws -> CurrentFocusPlan? {
    loadCurrentFocusCallCount += 1
    if let loadCurrentFocusGate {
      await loadCurrentFocusGate()
    }
    if let loadCurrentFocusError {
      throw loadCurrentFocusError
    }
    return try await preview.loadCurrentFocus(date: date)
  }
  func loadWeeklyReview() async throws -> WeeklyReviewSnapshot {
    if let loadWeeklyReviewError {
      throw loadWeeklyReviewError
    }
    return try await preview.loadWeeklyReview()
  }
  func createTask(title: String, notes: String) async throws -> LorvexTask {
    try await preview.createTask(title: title, notes: notes)
  }
  func createTask(_ draft: TaskCreateDraft) async throws -> LorvexTask {
    try await preview.createTask(draft)
  }
  func batchCreateTasks(_ drafts: [TaskCreateDraft]) async throws -> [LorvexTask] {
    try await preview.batchCreateTasks(drafts)
  }
  func batchUpdateTasks(_ drafts: [TaskUpdateDraft]) async throws -> [LorvexTask] {
    try await preview.batchUpdateTasks(drafts)
  }
  func batchCancelTasks(ids: [LorvexTask.ID], cancelSeries: Bool) async throws
    -> TaskBatchCancelByIdResult
  {
    try await preview.batchCancelTasks(ids: ids, cancelSeries: cancelSeries)
  }
  func completeTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    if completeTaskDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: completeTaskDelayNanoseconds)
    }
    return try await preview.completeTask(id: id)
  }
  func cancelTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try await preview.cancelTask(id: id)
  }
  func reopenTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try await preview.reopenTask(id: id)
  }
  func startTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try await preview.startTask(id: id)
  }
  func pauseTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try await preview.pauseTask(id: id)
  }
  func deferTask(id: LorvexTask.ID, until date: Date, reason: String?, note: String?) async throws
    -> TodaySnapshot
  {
    try await preview.deferTask(id: id, until: date, reason: reason, note: note)
  }
  func completeTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.completeTaskReturningTask(id: id)
  }
  func startTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.startTaskReturningTask(id: id)
  }
  func pauseTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.pauseTaskReturningTask(id: id)
  }
  func cancelTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.cancelTaskReturningTask(id: id)
  }
  func reopenTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.reopenTaskReturningTask(id: id)
  }
  func deferTaskReturningTask(
    id: LorvexTask.ID, until date: Date, reason: String?, note: String?
  ) async throws -> LorvexTask {
    try await preview.deferTaskReturningTask(id: id, until: date, reason: reason, note: note)
  }
  func searchTasks(query: String, status: String, limit: Int, offset: Int) async throws
    -> TaskSearchResult
  {
    try await preview.searchTasks(query: query, status: status, limit: limit, offset: offset)
  }
  func listTasks(
    status: String,
    listID: LorvexList.ID?,
    priority: Int?,
    text: String?,
    limit: Int,
    offset: Int
  ) async throws -> TaskPageResult {
    listTasksCallCount += 1
    if let listTasksError {
      throw listTasksError
    }
    return try await preview.listTasks(
      status: status,
      listID: listID,
      priority: priority,
      text: text,
      limit: limit,
      offset: offset
    )
  }
  func getScheduledTasks(from: String, to: String, limit: Int) async throws -> [LorvexTask] {
    scheduledTasksCallCount += 1
    return try await preview.getScheduledTasks(from: from, to: to, limit: limit)
  }
  func getHiddenScheduledTasks(limit: Int, offset: Int) async throws -> TaskPageResult {
    try await preview.getHiddenScheduledTasks(limit: limit, offset: offset)
  }
  func getTodayTasks(limit: Int, offset: Int) async throws -> TaskPageResult {
    try await preview.getTodayTasks(limit: limit, offset: offset)
  }
  func getTasksWithUpcomingReminders(hoursAhead: Int, limit: Int) async throws -> [LorvexTask] {
    upcomingReminderTaskCallCount += 1
    return try await preview.getTasksWithUpcomingReminders(hoursAhead: hoursAhead, limit: limit)
  }
  func getDeferredTasks(listID: LorvexList.ID?, limit: Int, offset: Int) async throws
    -> TaskPageResult
  {
    try await preview.getDeferredTasks(listID: listID, limit: limit, offset: offset)
  }
  func addToCurrentFocus(
    date: String, taskIDs: [LorvexTask.ID], briefing: String?, timezone: String
  ) async throws -> CurrentFocusPlan {
    try await preview.addToCurrentFocus(
      date: date, taskIDs: taskIDs, briefing: briefing, timezone: timezone)
  }
  func removeFromCurrentFocus(date: String, taskID: LorvexTask.ID) async throws -> CurrentFocusPlan?
  {
    try await preview.removeFromCurrentFocus(date: date, taskID: taskID)
  }
}
