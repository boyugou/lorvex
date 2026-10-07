import Foundation
import LorvexCore

/// Today's entry points for the shared batch operations
/// (``AppStore/completeBatch(on:)`` & co. in `AppStoreBatchTaskActions`). The
/// `.today` surface additionally prunes its selection to the rows still shown
/// after each batch.
extension AppStore {
  func completeTodaySelection(undoManager: UndoManager? = nil) async {
    await completeBatch(on: .today, undoManager: undoManager)
  }

  func deferTodaySelection() async { await deferBatch(on: .today) }

  func markTodaySelectionSomeday() async { await markBatchSomeday(on: .today) }

  func moveTodaySelection(toListID listID: LorvexList.ID, undoManager: UndoManager? = nil) async {
    await moveBatch(on: .today, toListID: listID, undoManager: undoManager)
  }

  func cancelTodaySelection(
    recurringScope: RecurringTaskCancelScope? = nil,
    pending: AppStorePendingRecurringBatchCancel? = nil
  ) async {
    await cancelBatch(on: .today, recurringScope: recurringScope, pending: pending)
  }

  func reopenTodaySelection() async { await reopenBatch(on: .today) }

  /// Move the overbooked decision's tasks to tomorrow, the answer to Today's
  /// "About 6 hr of work, 4 hr free" well.
  func moveTodayTasksToTomorrow(_ ids: [LorvexTask.ID]) async {
    await deferTasksToTomorrow(ids: ids, on: .today)
  }

  /// Put tasks dropped on Today on today's list: each one not already on it is
  /// planned for today, in one batch write.
  func planTasksForToday(ids: [LorvexTask.ID]) async {
    let onToday = Set(today.tasks.map(\.id))
    let ids = ids.filter { !onToday.contains($0) }
    guard !ids.isEmpty else { return }
    await perform {
      let day = try storageDate(daysFromLogicalToday: 0)
      _ = try await core.batchUpdateTasks(ids.map { TaskUpdateDraft(id: $0, plannedDate: .set(day)) })
      let updatedToday = try await core.loadToday()
      lorvexAnimated(.snappy(duration: 0.18)) { today = updatedToday }
      try await afterSelectedTaskMutation()
    }
  }
}
