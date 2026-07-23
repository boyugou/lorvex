import Foundation

// MARK: - Notification name

extension Notification.Name {
  /// Posted when a CloudKit silent push arrives indicating records changed in
  /// the Lorvex private database. Listeners should trigger AppStore.refresh().
  public static let lorvexCloudKitRemoteChange = Notification.Name(
    "com.lorvex.cloudkit.remoteChange"
  )

  /// Posted when a notification action handler encounters an error. The
  /// `userInfo` dictionary carries `"errorMessage"` (String).
  public static let lorvexNotificationActionError = Notification.Name(
    "com.lorvex.notificationAction.error"
  )

  /// Posted after an in-process background mutation (a notification "Complete" /
  /// "Defer" action) succeeds, so the running app refreshes — otherwise the
  /// completed task keeps showing as open, its reminders stay pending, and the
  /// badge stays stale until the next manual refresh. Listeners trigger
  /// `AppStore.refresh()`.
  public static let lorvexBackgroundMutationApplied = Notification.Name(
    "com.lorvex.notificationAction.applied"
  )
}

// MARK: - Parser

/// Inspects a remote-notification payload and determines whether it
/// originated from a Lorvex CloudKit database subscription.
public enum CloudKitPushParser {
  /// Returns `true` when the payload contains a CloudKit notification whose
  /// subscription ID starts with `"lorvex-"`.
  public static func isLorvexCloudKitNotification(_ userInfo: [String: Any]) -> Bool {
    guard
      let ck = userInfo["ck"] as? [String: Any],
      let sub = ck["sub"] as? String
    else { return false }
    return sub.hasPrefix("lorvex-")
  }
}
