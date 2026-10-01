import Foundation
import LorvexCore

extension AppStore {
  /// How many open tasks a Lists catalog card previews.
  static let listPreviewTaskCount = 3

  /// Each list's first open tasks in the canonical order, for the Lists
  /// catalog's cards. A list whose read fails is left out, so its card shows
  /// only its counts.
  func loadListPreviews(ids: [LorvexList.ID]) async -> [LorvexList.ID: [LorvexTask]] {
    var previews: [LorvexList.ID: [LorvexTask]] = [:]
    for id in ids {
      if let page = try? await core.listTasks(
        status: "open", listID: id, priority: nil, text: nil, limit: Self.listPreviewTaskCount, offset: 0)
      {
        previews[id] = page.tasks
      }
    }
    return previews
  }

  /// Open `taskID` in its list's Tasks scope with its inspector.
  func openTaskInListScope(_ taskID: LorvexTask.ID, listID: LorvexList.ID) {
    openTaskListScope(listID)
    selectedTaskID = taskID
  }
}
