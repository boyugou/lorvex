import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

// MARK: - Builder functions

/// Returns a configured NSUserActivity for opening a specific task.
///
/// Eligible for Handoff and Spotlight search. Set `title` to a user-visible string
/// such as the task's own title so Spotlight suggestions are meaningful.
/// The returned activity is inactive; call `becomeCurrent()` to advertise it.
public func makeOpenTaskActivity(taskID: LorvexTask.ID, title: String? = nil) -> NSUserActivity {
  let activity = NSUserActivity(activityType: LorvexActivityType.openTask)
  activity.title = title.map { "Continue task: \($0)" } ?? "Open Task"
  activity.isEligibleForHandoff = true
  activity.isEligibleForSearch = true
  activity.requiredUserInfoKeys = [LorvexActivityKey.taskID]
  activity.addUserInfoEntries(from: [LorvexActivityKey.taskID: taskID])
  return activity
}

/// Returns a configured NSUserActivity for opening a sidebar destination.
///
/// Today and Reviews are eligible for Siri Suggestion prediction (iOS/watchOS only).
/// All destinations are eligible for Handoff and Spotlight search.
/// The returned activity is inactive; call `becomeCurrent()` to advertise it.
public func makeOpenDestinationActivity(selection: SidebarSelection) -> NSUserActivity {
  let activity = NSUserActivity(activityType: LorvexActivityType.openDestination)
  activity.title = "Open \(selection.title)"
  activity.isEligibleForHandoff = true
  activity.isEligibleForSearch = true
  #if !os(macOS)
  activity.isEligibleForPrediction = (selection == .today || selection == .reviews)
  if activity.isEligibleForPrediction {
    activity.persistentIdentifier = "\(LorvexActivityType.openDestination).\(selection.rawValue)"
  }
  #endif
  activity.requiredUserInfoKeys = [LorvexActivityKey.destination]
  activity.addUserInfoEntries(from: [LorvexActivityKey.destination: selection.rawValue])
  return activity
}

/// Returns a configured NSUserActivity for opening a specific list.
///
/// Eligible for Handoff and Spotlight search.
/// The returned activity is inactive; call `becomeCurrent()` to advertise it.
public func makeOpenListActivity(listID: LorvexList.ID, title: String? = nil) -> NSUserActivity {
  let activity = NSUserActivity(activityType: LorvexActivityType.openList)
  activity.title = title.map { "Open list: \($0)" } ?? "Open List"
  activity.isEligibleForHandoff = true
  activity.isEligibleForSearch = true
  activity.requiredUserInfoKeys = [LorvexActivityKey.listID]
  activity.addUserInfoEntries(from: [LorvexActivityKey.listID: listID])
  return activity
}
