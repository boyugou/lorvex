import Foundation

/// Canonical NSUserActivity type string constants shared across all Lorvex Apple targets.
///
/// Every activity type uses the `com.lorvex.apple.*` prefix so they match the
/// NSUserActivityTypes entries in each target's Info.plist.
///
/// - `openTask`: carries a task ID; navigates to TaskDetailView.
/// - `openDestination`: carries a SidebarSelection rawValue; navigates to a workspace.
/// - `openList`: carries a list ID; deep-links to that list in the Lists
///   workspace. Published by the detached list window's `ListDetailPane`.
public enum LorvexActivityType {
  public static let openTask = "com.lorvex.apple.openTask"
  public static let openDestination = "com.lorvex.apple.openDestination"
  public static let openList = "com.lorvex.apple.openList"

  public static let all: [String] = [openTask, openDestination, openList]
}

/// userInfo dictionary key constants for LorvexActivityType payloads.
public enum LorvexActivityKey {
  public static let taskID = "taskID"
  public static let destination = "destination"
  public static let listID = "listID"
}
