import Foundation
import LorvexCore

extension MobileStore {
  public func taskIsFocused(_ id: LorvexTask.ID) -> Bool {
    snapshot.currentFocus?.taskIDs.contains(id) == true
  }

  public func toggleTaskFocus(_ id: LorvexTask.ID) async {
    await mutateTask(id: id) {
      let date = logicalTodayString
      if taskIsFocused(id) {
        _ = try await core.removeFromCurrentFocus(date: date, taskID: id)
      } else {
        _ = try await core.addToCurrentFocus(
          date: date,
          taskIDs: [id],
          briefing: snapshot.currentFocus?.briefing,
          timezone: logicalTimezoneName
        )
      }
    }
  }
}
