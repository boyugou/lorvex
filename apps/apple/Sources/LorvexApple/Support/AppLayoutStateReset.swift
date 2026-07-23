import Foundation

enum AppLayoutStateReset {
  private static let splitViewKeyPrefix = "NSSplitView Subview Frames"
  private static let mainWindowFrameKeyPrefix = "NSWindow Frame main-AppWindow"
  private static let mainNavigationSplitViewID = "SidebarNavigationSplitView"
  private static let mainWindowAutosaveID = "main-AppWindow"
  private static let resetMigrationKey = "layoutStateReset.mainThreePane.v6"

  static func removeStaleMainWindowAutosaveState(defaults: UserDefaults = .standard) {
    guard !defaults.bool(forKey: resetMigrationKey) else { return }

    for key in defaults.dictionaryRepresentation().keys where shouldRemove(key) {
      defaults.removeObject(forKey: key)
    }
    defaults.set(true, forKey: resetMigrationKey)
  }

  private static func shouldRemove(_ key: String) -> Bool {
    if key.hasPrefix(mainWindowFrameKeyPrefix) {
      return true
    }
    guard key.hasPrefix(splitViewKeyPrefix) else {
      return false
    }
    return key.contains(mainWindowAutosaveID) || key.contains(mainNavigationSplitViewID)
  }
}
