import Foundation

public enum SidebarSelection: String, CaseIterable, Identifiable, Sendable {
  case today
  case tasks
  case lists
  case calendar
  case habits
  case reviews
  case memory

  public var id: String { rawValue }

  public static func matching(_ rawValue: String) -> SidebarSelection? {
    allCases.first {
      $0.rawValue.compare(rawValue, options: [.caseInsensitive]) == .orderedSame
    }
  }

  public var title: String {
    switch self {
    case .today: "Today"
    case .tasks: "Tasks"
    case .lists: "Lists"
    case .calendar: "Calendar"
    case .habits: "Habits"
    case .reviews: "Reviews"
    case .memory: "Memory"
    }
  }

  public var systemImage: String {
    switch self {
    case .today: "sun.max"
    case .tasks: "checklist"
    case .lists: "folder"
    case .calendar: "calendar"
    case .habits: "repeat.circle"
    case .reviews: "text.badge.checkmark"
    case .memory: "brain"
    }
  }
}
