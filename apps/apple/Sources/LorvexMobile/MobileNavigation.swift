import Foundation
import LorvexCore

public enum MobileTab: String, CaseIterable, Identifiable, Sendable {
  case today
  case tasks
  case calendar
  case habits
  case review

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
        localized: "destination.plan", defaultValue: "Calendar", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .habits:
      String(
        localized: "destination.habits", defaultValue: "Habits", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .review:
      String(
        localized: "destination.review", defaultValue: "Review", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  public var systemImage: String {
    switch self {
    case .today: "sun.max"
    case .tasks: "checklist"
    case .calendar: "calendar"
    case .habits: "repeat"
    case .review: "text.badge.checkmark"
    }
  }
}

/// A workspace destination: a primary tab, or a secondary workspace reached
/// from a row or button inside a primary tab (Memory and Habits on the Tasks
/// home, Settings on Today), or from the keyboard-shortcut mnemonic system.
public enum MobileDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
  case tasks
  case calendar
  case habits
  case lists
  case memory
  case review
  case settings

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .tasks:
      String(
        localized: "destination.tasks", defaultValue: "Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .calendar:
      String(
        localized: "destination.plan", defaultValue: "Calendar", table: "Localizable",
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
    case .review: "text.badge.checkmark"
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
  /// A scoped task list (a smart collection or a list). A list's screen is
  /// always this route, `.tasksScope(.list(id))`, whether the Tasks home, a
  /// deep link, Handoff, or a newly created list pushes it. Carried as a
  /// `MobileRoute` so it rides the same typed stacks as task-detail pushes.
  case tasksScope(MobileTasksScope)
  /// A memory entry's detail, pushed from the Memory workspace's list at
  /// compact width the way a task or habit row pushes its own detail.
  case memoryEntry(MemoryEntry.ID)
  /// A secondary workspace pushed onto the stack of the primary tab that hosts
  /// it in the tab-bar layout: Memory rides the Tasks tab, Settings rides
  /// Today. Carried as a route so keyboard mnemonics, deep links, and the
  /// in-content rows all push the same screen.
  case workspace(MobileDestination)
}
