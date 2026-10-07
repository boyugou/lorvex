import Foundation
import LorvexCore

/// List-detail entry points for the shared batch operations
/// (``AppStore/completeBatch(on:)`` & co. in `AppStoreBatchTaskActions`). The
/// `.selectedList` surface reloads the open list's detail pane after each batch.
extension AppStore {
  func completeSelectedListTaskSelection(undoManager: UndoManager? = nil) async {
    await completeBatch(on: .selectedList, undoManager: undoManager)
  }

  func deferSelectedListTaskSelection() async { await deferBatch(on: .selectedList) }

  func markSelectedListTaskSelectionSomeday() async { await markBatchSomeday(on: .selectedList) }

  func moveSelectedListTaskSelection(
    toListID listID: LorvexList.ID, undoManager: UndoManager? = nil
  ) async {
    await moveBatch(on: .selectedList, toListID: listID, undoManager: undoManager)
  }

  func cancelSelectedListTaskSelection(
    recurringScope: RecurringTaskCancelScope? = nil,
    pending: AppStorePendingRecurringBatchCancel? = nil
  ) async {
    await cancelBatch(on: .selectedList, recurringScope: recurringScope, pending: pending)
  }

  func reopenSelectedListTaskSelection() async { await reopenBatch(on: .selectedList) }
}
