import Foundation
import LorvexCore
import SwiftUI

/// Per-surface behavior for the shared batch-task operations. The task
/// surfaces (Tasks workspace, Focus/Today, a list detail) run
/// the same six batch operations and differ only in three things, captured
/// here: which selection set they act on, how they refresh their owning view,
/// and whether they prune the selection afterward (Focus alone does).
extension AppStoreBatchCancelSurface {
  @MainActor
  func selectedTasks(_ store: AppStore) -> [LorvexTask] {
    switch self {
    case .taskWorkspace: store.taskWorkspaceSelectedTasks
    case .focus: store.focusWorkspaceSelectedTasks
    case .selectedList: store.selectedListTasksForBatch
    }
  }

  /// Reload the surface that owns the selection. The list detail reloads its own
  /// pane; the others refresh the shared list surfaces.
  @MainActor
  func refreshOwningSurface(_ store: AppStore) async throws {
    switch self {
    case .selectedList: try await store.loadSelectedListDetail()
    case .taskWorkspace, .focus: try await store.refreshListSurfaces()
    }
  }

  /// Focus mirrors Today's curated set, so a batch that removes tasks from the
  /// lanes must drop them from the selection too; the other surfaces re-derive
  /// their selection from the reloaded results.
  @MainActor
  func pruneSelection(_ store: AppStore) {
    if case .focus = self { store.pruneFocusWorkspaceSelection() }
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

  func completeBatch(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status.isActive }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchCompleteTasks(ids: ids).snapshot
      lorvexAnimated(.snappy(duration: 0.18)) { today = updatedToday }
      try await finishBatchMutation(on: surface)
      feedbackProvider.playFeedback(.taskCompleted)
    }
  }

  func deferBatch(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status.isActive }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchDeferTasks(ids: ids, until: tomorrowDate())
      lorvexAnimated(.snappy(duration: 0.18)) { today = updatedToday }
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

  func moveBatch(on surface: AppStoreBatchCancelSurface, toListID listID: LorvexList.ID) async {
    let ids = surface.selectedTasks(self).map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      _ = try await core.batchMoveTasks(ids: ids, toListID: listID)
      today = try await core.loadToday()
      lists = try await core.loadLists()
      try await finishBatchMutation(on: surface)
    }
  }

  func reopenBatch(on surface: AppStoreBatchCancelSurface) async {
    let ids = surface.selectedTasks(self)
      .filter { $0.status.isResolved }
      .map(\.id)
    guard !ids.isEmpty else { return }
    await perform {
      let updatedToday = try await core.batchReopenTasks(ids: ids).snapshot
      lorvexAnimated(.snappy(duration: 0.18)) { today = updatedToday }
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
        lorvexAnimated(.snappy(duration: 0.18)) { today = updatedToday }
      }
      try await finishBatchMutation(on: surface)
      syncSelectedTaskDraft()
    }
  }
}
