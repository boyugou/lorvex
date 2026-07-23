import Foundation
import LorvexCore

public enum MobileTab: String, CaseIterable, Identifiable, Sendable {
  case today
  case tasks
  case calendar
  case habits
  /// The "More" tab on iPhone — presents a list of additional domain destinations.
  case more

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .today:
      String(
        localized: "tab.today", defaultValue: "Today", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .tasks:
      String(
        localized: "destination.tasks", defaultValue: "Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .calendar:
      String(
        localized: "destination.calendar", defaultValue: "Calendar", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .habits:
      String(
        localized: "destination.habits", defaultValue: "Habits", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .more:
      String(
        localized: "tab.more", defaultValue: "More", table: "Localizable", bundle: MobileL10n.bundle
      )
    }
  }

  public var systemImage: String {
    switch self {
    case .today: "sun.max"
    case .tasks: "checklist"
    case .calendar: "calendar"
    case .habits: "repeat"
    case .more: "ellipsis.circle"
    }
  }
}

/// A destination reachable from the "More" tab on iPhone or the full sidebar on iPad.
public enum MobileDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
  case tasks
  case calendar
  case habits
  case lists
  case memory
  case review
  case settings

  public var id: String { rawValue }

  /// Domain workspaces shown in the iPhone "More" list and the iPad sidebar's
  /// secondary section. Excludes the surfaces promoted to primary tabs
  /// (tasks / calendar / habits) and Settings, which sits in its own group.
  ///
  /// Lists is intentionally omitted: it's merged into the Tasks tab, whose home
  /// presents lists as first-class rows alongside the smart collections, so a
  /// separate More/sidebar entry would be redundant.
  public static let secondaryWorkspaces: [MobileDestination] = [
    .memory, .review,
  ]

  public var title: String {
    switch self {
    case .tasks:
      String(
        localized: "destination.tasks", defaultValue: "Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .calendar:
      String(
        localized: "destination.calendar", defaultValue: "Calendar", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .habits:
      String(
        localized: "destination.habits", defaultValue: "Habits", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .lists:
      String(
        localized: "destination.lists", defaultValue: "Lists", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .memory:
      String(
        localized: "destination.memory", defaultValue: "Memory", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .review:
      String(
        localized: "destination.review", defaultValue: "Review", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .settings:
      String(
        localized: "destination.settings", defaultValue: "Settings", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  public var systemImage: String {
    switch self {
    case .tasks: "checklist"
    case .calendar: "calendar"
    case .habits: "repeat.circle"
    case .lists: "folder"
    case .memory: "brain"
    case .review: "chart.line.uptrend.xyaxis"
    case .settings: "gearshape"
    }
  }

  public var keyboardShortcutKey: String {
    switch self {
    case .tasks: "6"
    case .calendar: "7"
    case .lists: "8"
    case .habits: "9"
    case .memory: "m"
    case .review: "e"
    case .settings: ","
    }
  }
}

public enum MobileRoute: Hashable, Sendable {
  case task(LorvexTask.ID)
  case habit(LorvexHabit.ID)
  case list(LorvexList.ID)
  /// A scoped task list (a smart collection or a list) pushed from the Tasks
  /// home. Carried as a `MobileRoute` so it rides the same typed `tasksRoutePath`
  /// as task-detail pushes.
  case tasksScope(MobileTasksScope)
}
