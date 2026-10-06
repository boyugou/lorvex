import Foundation
import LorvexCore
import SwiftUI

/// Per-surface behavior for the shared batch-task operations. The task
/// surfaces (Tasks workspace, Today, a list detail) run the same six batch
/// operations and differ only in three things, captured here: which selection
/// set they act on, how they refresh their owning view, and whether they prune
/// the selection afterward (Today alone does).
extension AppStoreBatchCancelSurface {
  @MainActor
  func selectedTasks(_ store: AppStore) -> [LorvexTask] {
    switch self {
    case .taskWorkspace: store.taskWorkspaceSelectedTasks
    case .today: store.todaySelectedTasks
    case .selectedList: store.selectedListTasksForBatch
    }
  }

  /// Reload the surface that owns the selection. The list detail reloads its own
  /// pane; the others refresh the shared list surfaces.
  @MainActor
  func refreshOwningSurface(_ store: AppStore) async throws {
    switch self {
    case .selectedList: try await store.loadSelectedListDetail()
    case .taskWorkspace, .today: try await store.refreshListSurfaces()
    }
  }

  /// A batch that takes tasks off Today (completing, deferring, cancelling)
  /// must drop them from Today's selection too; the other surfaces re-derive
  /// their selection from the reloaded results.
  @MainActor
  func pruneSelection(_ store: AppStore) {
    if case .today = self { store.pruneTodaySelection() }
  }
}

extension AppStore {
  /// The refresh tail every batch operation shares: reload the owning surface
  /// and the Tasks workspace (if loaded), prune the
  /// selection where applicable, then publish the Apple sync surfaces.
  private func finishBatchMutation(on surface: AppStoreBatchCancelSurface) async throws {
    try await surface.refreshOwningSurface(self)
    await reloadTaskWorkspaceIfLoaded()
    surface.pruneSelection(self)
    await republishSurfacesAfterLocalMutation()
  }

  /// Publishes a batch's new Today snapshot. A batch over a few tasks
  /// animates, so its rows settle into their new places; a batch over many
  /// replaces Today's rows at once (``TaskRowChangeAnimation``).
  func publishBatchToday(_ updatedToday: TodaySnapshot, taskCount: Int) {
    if TaskRowChangeAnimation.animates(batchOf: taskCount) {
      lorvexAnimated(TaskRowChangeAnimation.animation) { today = updatedToday }
    } else {
      today = updatedToday
    }
  }

  func completeBatch(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status.isActive }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchCompleteTasks(ids: ids).snapshot
      feedbackProvider.playFeedback(.taskCompleted)
      publishBatchToday(updatedToday, taskCount: ids.count)
      try await finishBatchMutation(on: surface)
    }
  }

  func deferBatch(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status.isActive }
      .map(\.id)
    await deferTasksToTomorrow(ids: ids, on: surface)
  }

  /// Defer `ids` to tomorrow in one core call, then refresh `surface`.
  func deferTasksToTomorrow(ids: [LorvexTask.ID], on surface: AppStoreBatchCancelSurface) async {
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchDeferTasks(ids: ids, until: tomorrowDate())
      feedbackProvider.playFeedback(.taskDeferred)
      publishBatchToday(updatedToday, taskCount: ids.count)
      try await finishBatchMutation(on: surface)
    }
  }

  /// Park the selected open tasks in the GTD Someday/Maybe bucket. Only `open`
  /// tasks are eligible. `markTaskSomeday` returns one task at a time, so each is
  /// applied in turn before a single batched refresh — `today` is reloaded
  /// because the marked tasks drop out of Today's open lanes.
  func markBatchSomeday(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status == .open }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      for id in ids {
        _ = try await core.markTaskSomeday(id: id)
      }
      today = try await core.loadToday()
      try await finishBatchMutation(on: surface)
    }
  }

  /// Moves the surface's selected tasks into `listID` through
  /// ``moveTasks(ids:toListID:undoManager:)``, so a move from a selection menu
  /// confirms itself and undoes like a drag onto the list does.
  func moveBatch(
    on surface: AppStoreBatchCancelSurface, toListID listID: LorvexList.ID,
    undoManager: UndoManager? = nil
  ) async {
    await moveTasks(
      ids: surface.selectedTasks(self).map(\.id), toListID: listID, undoManager: undoManager)
  }

  func reopenBatch(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status.isResolved }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchReopenTasks(ids: ids).snapshot
      publishBatchToday(updatedToday, taskCount: ids.count)
      try await finishBatchMutation(on: surface)
      syncSelectedTaskDraft()
    }
  }

  /// Cancel the surface's selection. With no `recurringScope`, a selection that
  /// has any cancellable task stages `pendingRecurringBatchCancel` (the shared
  /// occurrence-vs-series / confirm dialog) and returns; the dialog re-enters
  /// with the captured `pending` and a chosen scope.
  func cancelBatch(
    on surface: AppStoreBatchCancelSurface,
    recurringScope: RecurringTaskCancelScope? = nil,
    pending: AppStorePendingRecurringBatchCancel? = nil
  ) async {
    let selectedTasks = surface.selectedTasks(self)
    if recurringScope == nil,
      let staged = pendingBatchCancel(surface: surface, tasks: selectedTasks)
    {
      pendingRecurringBatchCancel = staged
      return
    }
    let ids = pending?.taskIDs ?? selectedTasks
      .filter { $0.status.isActive }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await cancelTaskBatch(
        ids: ids,
        recurringIDs: pending?.recurringTaskIDs ?? [],
        recurringScope: recurringScope ?? .thisOccurrence
      )
      if let updatedToday {
        publishBatchToday(updatedToday, taskCount: ids.count)
      }
      try await finishBatchMutation(on: surface)
      syncSelectedTaskDraft()
    }
  }
}
