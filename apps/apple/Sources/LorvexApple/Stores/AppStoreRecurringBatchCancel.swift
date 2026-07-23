import Foundation
import LorvexCore

enum AppStoreBatchCancelSurface: Sendable {
  case taskWorkspace
  case selectedList
  case focus
}

struct AppStorePendingRecurringBatchCancel: Sendable {
  let surface: AppStoreBatchCancelSurface
  let taskIDs: [LorvexTask.ID]
  let recurringTaskIDs: Set<LorvexTask.ID>
}

extension AppStore {
  /// Pending state for a batch cancel awaiting confirmation. Returned whenever
  /// the selection has any cancellable task — both to surface the
  /// occurrence-vs-series scope choice when it contains recurring tasks and to
  /// require a plain confirmation (no scope) when it does not, so a bulk cancel
  /// is never one irreversible un-undoable click. `recurringTaskIDs` is empty in
  /// the plain case.
  func pendingBatchCancel(
    surface: AppStoreBatchCancelSurface,
    tasks: [LorvexTask]
  ) -> AppStorePendingRecurringBatchCancel? {
    let cancellable = tasks.filter { $0.status.isActive }
    guard !cancellable.isEmpty else { return nil }
    let recurringIDs = Set(cancellable.filter { $0.recurrence != nil }.map(\.id))
    return AppStorePendingRecurringBatchCancel(
      surface: surface,
      taskIDs: cancellable.map(\.id),
      recurringTaskIDs: recurringIDs
    )
  }

  /// Runs the core operations a recurring-cancel `scope` maps to for a single
  /// task `id`, in order (`RecurringTaskCancelScope.coreOperations`). Returns the
  /// `TodaySnapshot` produced by the scope's `cancelTask` step, or `nil` when the
  /// scope performs no cancel (e.g. a series edit that only strips recurrence).
  func applyRecurringCancelScope(
    _ scope: RecurringTaskCancelScope, taskID id: LorvexTask.ID
  ) async throws -> TodaySnapshot? {
    var snapshot: TodaySnapshot?
    for operation in scope.coreOperations {
      switch operation {
      case .removeRecurrence:
        _ = try await core.removeTaskRecurrence(taskID: id)
      case .cancelTask:
        snapshot = try await core.cancelTask(id: id)
      }
    }
    return snapshot
  }

  func cancelTaskBatch(
    ids: [LorvexTask.ID],
    recurringIDs: Set<LorvexTask.ID> = [],
    recurringScope: RecurringTaskCancelScope = .thisOccurrence
  ) async throws -> TodaySnapshot? {
    var updatedToday: TodaySnapshot?
    for id in ids {
      if recurringIDs.contains(id) {
        if let snapshot = try await applyRecurringCancelScope(recurringScope, taskID: id) {
          updatedToday = snapshot
        }
      } else {
        updatedToday = try await core.cancelTask(id: id)
      }
    }
    return updatedToday
  }

  func confirmPendingRecurringBatchCancel(scope: RecurringTaskCancelScope) async {
    guard let pending = pendingRecurringBatchCancel else { return }
    pendingRecurringBatchCancel = nil
    switch pending.surface {
    case .taskWorkspace:
      await cancelTaskWorkspaceSelection(recurringScope: scope, pending: pending)
    case .selectedList:
      await cancelSelectedListTaskSelection(recurringScope: scope, pending: pending)
    case .focus:
      await cancelFocusWorkspaceSelection(recurringScope: scope, pending: pending)
    }
  }
}
