/// The flagship App Shortcuts that `LorvexShortcutsProvider` is expected to
/// register with the system, in registration order.
///
/// A test-owned fixture: the system surfaces only a small number of an app's
/// shortcuts, so this pins the curated, highest-value entry points — their
/// order, short titles, and SF Symbols — against `LorvexShortcutsProvider`.
enum LorvexShortcutDescriptor: CaseIterable, Equatable, Sendable {
  case captureTask
  case openLorvex
  case readOverview
  case completeTask
  case deferTask
  case focusTask
  case listTasks
  case searchTasks
  case createHabit
  case readWeeklyReview

  var shortTitle: String {
    switch self {
    case .captureTask: "Capture Task"
    case .openLorvex: "Open Lorvex"
    case .readOverview: "Overview"
    case .completeTask: "Complete Task"
    case .deferTask: "Defer Task"
    case .focusTask: "Focus Task"
    case .listTasks: "List Tasks"
    case .searchTasks: "Search Tasks"
    case .createHabit: "Create Habit"
    case .readWeeklyReview: "Weekly Review"
    }
  }

  var systemImageName: String {
    switch self {
    case .captureTask: "plus"
    case .openLorvex: "sun.max"
    case .readOverview: "rectangle.3.group"
    case .completeTask: "checkmark.circle"
    case .deferTask: "calendar.badge.clock"
    case .focusTask: "scope"
    case .listTasks: "list.bullet.rectangle"
    case .searchTasks: "text.magnifyingglass"
    case .createHabit: "repeat.circle"
    case .readWeeklyReview: "calendar.badge.checkmark"
    }
  }
}
