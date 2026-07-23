import Foundation
import LorvexCore

/// List-detail entry points for the shared batch operations
/// (``AppStore/completeBatch(on:)`` & co. in `AppStoreBatchTaskActions`). The
/// `.selectedList` surface reloads the open list's detail pane after each batch.
extension AppStore {
  func completeSelectedListTaskSelection() async { await completeBatch(on: .selectedList) }

  func deferSelectedListTaskSelection() async { await deferBatch(on: .selectedList) }

  func markSelectedListTaskSelectionSomeday() async { await markBatchSomeday(on: .selectedList) }

  func moveSelectedListTaskSelection(toListID listID: LorvexList.ID) async {
    await moveBatch(on: .selectedList, toListID: listID)
  }

  func cancelSelectedListTaskSelection(
    recurringScope: RecurringTaskCancelScope? = nil,
    pending: AppStorePendingRecurringBatchCancel? = nil
  ) async {
    await cancelBatch(on: .selectedList, recurringScope: recurringScope, pending: pending)
  }

  func reopenSelectedListTaskSelection() async { await reopenBatch(on: .selectedList) }
}
