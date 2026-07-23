import Foundation
import LorvexCore

/// Tasks-workspace entry points for the shared batch operations
/// (``AppStore/completeBatch(on:)`` & co. in `AppStoreBatchTaskActions`).
extension AppStore {
  func completeTaskWorkspaceSelection() async { await completeBatch(on: .taskWorkspace) }

  func deferTaskWorkspaceSelection() async { await deferBatch(on: .taskWorkspace) }

  func markTaskWorkspaceSelectionSomeday() async { await markBatchSomeday(on: .taskWorkspace) }

  func moveTaskWorkspaceSelection(toListID listID: LorvexList.ID) async {
    await moveBatch(on: .taskWorkspace, toListID: listID)
  }

  func cancelTaskWorkspaceSelection(
    recurringScope: RecurringTaskCancelScope? = nil,
    pending: AppStorePendingRecurringBatchCancel? = nil
  ) async {
    await cancelBatch(on: .taskWorkspace, recurringScope: recurringScope, pending: pending)
  }

  func reopenTaskWorkspaceSelection() async { await reopenBatch(on: .taskWorkspace) }
}
