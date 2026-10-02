import Foundation
import LorvexCore

extension AppStore {
  /// How many open tasks a Lists catalog card previews.
  static let listPreviewTaskCount = 3

  /// Each list's first open tasks in the canonical order, for the Lists
  /// catalog's cards. A list whose read fails is left out, so its card shows
  /// only its counts.
  ///
  /// Throws `CancellationError` once the calling task is cancelled instead of
  /// returning previews for only some lists or for lists that have since
  /// changed: the catalog starts a new load whenever the lists change, and a
  /// superseded load must not overwrite the newer one's previews.
  func loadListPreviews(
    ids: [LorvexList.ID]
  ) async throws(CancellationError) -> [LorvexList.ID: [LorvexTask]] {
    var previews: [LorvexList.ID: [LorvexTask]] = [:]
    for id in ids {
      if Task.isCancelled { throw CancellationError() }
      if let page = try? await core.listTasks(
        status: "open", listID: id, priority: nil, text: nil, limit: Self.listPreviewTaskCount, offset: 0)
      {
        previews[id] = page.tasks
      }
    }
    if Task.isCancelled { throw CancellationError() }
    return previews
  }

  /// Open `taskID` in its list's Tasks scope with its inspector.
  func openTaskInListScope(_ taskID: LorvexTask.ID, listID: LorvexList.ID) {
    openTaskListScope(listID)
    selectedTaskID = taskID
  }
}
