import Foundation

#if canImport(CoreSpotlight)
  import CoreSpotlight
  import UniformTypeIdentifiers
#endif

// MARK: - Open-entity activities

/// Configures `activity`, of type ``LorvexActivityType/openTask``, to open the
/// task `taskID` through Handoff and Spotlight.
///
/// Its title is the task's own title, which Spotlight shows as the result's
/// name; an activity without a title is offered to Handoff only. Where Core
/// Spotlight exists, the activity names the task's indexed item, so Spotlight
/// lists the task once and drops the activity when the task leaves the index.
public func configureOpenTaskActivity(_ activity: NSUserActivity, taskID: LorvexTask.ID, title: String?) {
  configureOpenEntityActivity(activity, title: title, route: .task(taskID))
  activity.requiredUserInfoKeys = [LorvexActivityKey.taskID]
  activity.addUserInfoEntries(from: [LorvexActivityKey.taskID: taskID])
}

/// Configures `activity`, of type ``LorvexActivityType/openList``, to open the
/// list `listID` through Handoff and Spotlight, named by the list's title the
/// way ``configureOpenTaskActivity(_:taskID:title:)`` names a task.
public func configureOpenListActivity(_ activity: NSUserActivity, listID: LorvexList.ID, title: String?) {
  configureOpenEntityActivity(activity, title: title, route: .list(listID))
  activity.requiredUserInfoKeys = [LorvexActivityKey.listID]
  activity.addUserInfoEntries(from: [LorvexActivityKey.listID: listID])
}

/// Configures `activity`, of type ``LorvexActivityType/openDestination``, to
/// open the destination `selection` through Handoff and Spotlight.
///
/// `title` is the destination's name as the caller's interface shows it
/// ("Today", "今天"); a destination is not an indexed entity, so the activity
/// stands on its own in Spotlight. Today and Review are offered to Siri
/// Suggestions where the platform has them.
public func configureOpenDestinationActivity(
  _ activity: NSUserActivity, selection: SidebarSelection, title: String?
) {
  configureOpenEntityActivity(activity, title: title, route: .destination(selection))
  #if !os(macOS)
    activity.isEligibleForPrediction = (selection == .today || selection == .reviews)
    if activity.isEligibleForPrediction {
      activity.persistentIdentifier = "\(LorvexActivityType.openDestination).\(selection.rawValue)"
    }
  #endif
  activity.requiredUserInfoKeys = [LorvexActivityKey.destination]
  activity.addUserInfoEntries(from: [LorvexActivityKey.destination: selection.rawValue])
}

/// A new, inactive activity configured by
/// ``configureOpenTaskActivity(_:taskID:title:)``; call `becomeCurrent()` to
/// advertise it.
public func makeOpenTaskActivity(taskID: LorvexTask.ID, title: String? = nil) -> NSUserActivity {
  let activity = NSUserActivity(activityType: LorvexActivityType.openTask)
  configureOpenTaskActivity(activity, taskID: taskID, title: title)
  return activity
}

/// A new, inactive activity configured by
/// ``configureOpenListActivity(_:listID:title:)``; call `becomeCurrent()` to
/// advertise it.
public func makeOpenListActivity(listID: LorvexList.ID, title: String? = nil) -> NSUserActivity {
  let activity = NSUserActivity(activityType: LorvexActivityType.openList)
  configureOpenListActivity(activity, listID: listID, title: title)
  return activity
}

/// A new, inactive activity configured by
/// ``configureOpenDestinationActivity(_:selection:title:)``; call
/// `becomeCurrent()` to advertise it.
public func makeOpenDestinationActivity(selection: SidebarSelection, title: String? = nil) -> NSUserActivity {
  let activity = NSUserActivity(activityType: LorvexActivityType.openDestination)
  configureOpenDestinationActivity(activity, selection: selection, title: title)
  return activity
}

/// The parts every open-entity activity shares: its title, Handoff, search
/// eligibility only while it has a title to show, and the link to the
/// entity's Spotlight item when the route names one.
private func configureOpenEntityActivity(_ activity: NSUserActivity, title: String?, route: LorvexDeepLinkRoute) {
  let title = title.flatMap { $0.isEmpty ? nil : $0 }
  activity.title = title
  activity.isEligibleForHandoff = true
  activity.isEligibleForSearch = title != nil
  #if canImport(CoreSpotlight)
    if let identifier = route.spotlightIdentifier {
      let attributes = CSSearchableItemAttributeSet(contentType: .content)
      attributes.relatedUniqueIdentifier = identifier
      activity.contentAttributeSet = attributes
    }
  #endif
}
