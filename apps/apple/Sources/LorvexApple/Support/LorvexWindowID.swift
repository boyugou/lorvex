import SwiftUI

enum LorvexWindowID: String, CaseIterable {
  case main
  case today
  case tasks
  case calendar
  case lists
  case habits
  case reviews
  case taskDetail = "task-detail"

  // The detachable workspace Window scenes shown in the Workspace menu. `.main`
  // (the primary three-pane window) and `.taskDetail` (the inspector) are their
  // own scenes and stay out of this list.
  static let workspaceWindows: [LorvexWindowID] = [
    .today,
    .calendar,
    .tasks,
    .lists,
    .habits,
    .reviews,
  ]

  static let refreshOnOpenWindows: [LorvexWindowID] =
    workspaceWindows + [
      .taskDetail
    ]

  static var detachedListTitle: String {
    String(localized: "window.title.detached_list", defaultValue: "Lorvex List", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var stickyTaskTitle: String {
    String(localized: "window.title.sticky_task", defaultValue: "Lorvex Sticky", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  /// Explicit `WindowGroup` id so opening a sticky is unambiguous next to the
  /// detached-task group, which also keys on a task identifier.
  static let stickyTaskGroupID = "sticky-task"

  var title: String {
    switch self {
    case .main: "Lorvex"  // brand name — not localized
    case .today: String(localized: "sidebar.item.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .tasks: String(localized: "sidebar.item.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendar: String(localized: "sidebar.item.calendar", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case .lists: String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habits: String(localized: "sidebar.item.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reviews: String(localized: "sidebar.item.reviews", defaultValue: "Reviews", table: "Localizable", bundle: LorvexL10n.bundle)
    case .taskDetail: String(localized: "window.title.task_detail", defaultValue: "Task Detail", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var windowMenuTitle: String {
    switch self {
    case .main:
      title
    default:
      String(
        format: String(localized: "window.menu.title_format", defaultValue: "%@ Window", table: "Localizable", bundle: LorvexL10n.bundle),
        title
      )
    }
  }

  var systemImage: String {
    switch self {
    case .main: "checklist.checked"
    case .today: "sun.max"
    case .tasks: "checklist"
    case .calendar: "calendar"
    case .lists: "list.bullet.rectangle"
    case .habits: "repeat.circle"
    case .reviews: "text.badge.checkmark"
    case .taskDetail: "sidebar.right"
    }
  }

  /// ⇧⌘1-6 open the six workspace windows, mirroring the ⌘1-6 sidebar
  /// navigation but in a separate window instead of switching the main pane.
  var keyboardShortcut: KeyEquivalent? {
    switch self {
    case .today:    "1"
    case .calendar: "2"
    case .tasks:    "3"
    case .lists:    "4"
    case .habits:   "5"
    case .reviews:  "6"
    default: nil
    }
  }

  var minimumContentSize: CGSize {
    switch self {
    case .main:
      // The three-pane layout (sidebar + workspace + task-detail inspector)
      // needs enough width that none of the panes collapse or clip; 680 let the
      // window be dragged into a zone where the sidebar half-collapsed and the
      // inspector ran off the right edge.
      CGSize(width: 1000, height: 600)
    case .today:
      CGSize(width: 560, height: 560)
    case .tasks:
      CGSize(width: 660, height: 560)
    case .calendar:
      CGSize(width: 560, height: 560)
    case .lists:
      CGSize(width: 660, height: 560)
    case .habits:
      CGSize(width: 560, height: 560)
    case .reviews:
      CGSize(width: 700, height: 560)
    case .taskDetail:
      CGSize(width: 480, height: 560)
    }
  }
}
