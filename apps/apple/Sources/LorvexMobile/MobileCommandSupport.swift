import Foundation

public enum MobileCommandTitles {
  public static var workspaceMenu: String {
    String(
      localized: "mobileCommandMenu.workspace", defaultValue: "Workspace", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  public static var refresh: String {
    String(
      localized: "mobileCommand.refresh", defaultValue: "Refresh", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  public static var newCapture: String {
    String(
      localized: "mobileCommand.newCapture", defaultValue: "Capture", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  public static func title(for tab: MobileTab) -> String {
    switch tab {
    case .today:
      String(
        localized: "mobileCommand.today", defaultValue: "Today", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .tasks:
      String(
        localized: "mobileCommand.tasks", defaultValue: "Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .calendar:
      String(
        localized: "mobileCommand.calendar", defaultValue: "Calendar", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .habits:
      String(
        localized: "mobileCommand.habits", defaultValue: "Habits", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .more:
      String(
        localized: "mobileCommand.more", defaultValue: "More", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  public static func title(for destination: MobileDestination) -> String {
    switch destination {
    case .tasks:
      String(
        localized: "mobileCommand.tasks", defaultValue: "Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .calendar:
      String(
        localized: "mobileCommand.calendar", defaultValue: "Calendar", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .habits:
      String(
        localized: "mobileCommand.habits", defaultValue: "Habits", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .lists:
      String(
        localized: "mobileCommand.lists", defaultValue: "Lists", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .memory:
      String(
        localized: "mobileCommand.memory", defaultValue: "Memory", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .review:
      String(
        localized: "mobileCommand.review", defaultValue: "Review", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .settings:
      String(
        localized: "mobileCommand.settings", defaultValue: "Settings", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}

extension MobileStore {
  public func openPrimaryShortcutTab(_ tab: MobileTab) {
    selectedTab = tab
    if tab != .more {
      iPadDestination = nil
      moreNavigationPath = []
      pendingListRoute = nil
    }
  }

  public func openShortcutDestination(_ destination: MobileDestination) {
    selectedTab = .more
    moreNavigationPath = [destination]
    iPadDestination = destination
  }
}
