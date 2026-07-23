import Foundation

// MARK: - Parser functions

/// Extracts the task ID from an `openTask` NSUserActivity.
/// Returns nil if the activity type is wrong, userInfo is missing, or the ID is empty.
public func parseOpenTaskActivity(_ activity: NSUserActivity) -> LorvexTask.ID? {
  guard activity.activityType == LorvexActivityType.openTask,
    let taskID = activity.userInfo?[LorvexActivityKey.taskID] as? String,
    !taskID.isEmpty
  else { return nil }
  return taskID
}

/// Extracts the SidebarSelection from an `openDestination` NSUserActivity.
/// Returns nil if the activity type is wrong, userInfo is missing, or the rawValue is unrecognised.
public func parseOpenDestinationActivity(_ activity: NSUserActivity) -> SidebarSelection? {
  guard activity.activityType == LorvexActivityType.openDestination,
    let rawValue = activity.userInfo?[LorvexActivityKey.destination] as? String,
    let selection = SidebarSelection.matching(rawValue)
  else { return nil }
  return selection
}

/// Extracts the list ID from an `openList` NSUserActivity.
/// Returns nil if the activity type is wrong, userInfo is missing, or the ID is empty.
public func parseOpenListActivity(_ activity: NSUserActivity) -> LorvexList.ID? {
  guard activity.activityType == LorvexActivityType.openList,
    let listID = activity.userInfo?[LorvexActivityKey.listID] as? String,
    !listID.isEmpty
  else { return nil }
  return listID
}
