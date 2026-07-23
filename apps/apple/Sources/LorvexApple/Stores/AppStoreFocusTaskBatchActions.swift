import Foundation
import LorvexCore

/// Focus/Today entry points for the shared batch operations
/// (``AppStore/completeBatch(on:)`` & co. in `AppStoreBatchTaskActions`). The
/// `.focus` surface additionally prunes the curated selection after each batch.
extension AppStore {
  func completeFocusWorkspaceSelection() async { await completeBatch(on: .focus) }

  func deferFocusWorkspaceSelection() async { await deferBatch(on: .focus) }

  func markFocusWorkspaceSelectionSomeday() async { await markBatchSomeday(on: .focus) }

  func moveFocusWorkspaceSelection(toListID listID: LorvexList.ID) async {
    await moveBatch(on: .focus, toListID: listID)
  }

  func cancelFocusWorkspaceSelection(
    recurringScope: RecurringTaskCancelScope? = nil,
    pending: AppStorePendingRecurringBatchCancel? = nil
  ) async {
    await cancelBatch(on: .focus, recurringScope: recurringScope, pending: pending)
  }

  func reopenFocusWorkspaceSelection() async { await reopenBatch(on: .focus) }
}
