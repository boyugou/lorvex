import Foundation

/// A selectable category of data in an export run.
///
/// `rawValue` is the canonical entity name shared across every export surface:
/// the `exportData(entities:format:)` selector, the CSV section headers, and
/// the App Intent entity options all key off these same strings. `displayLabel`
/// is the human-facing title for selection UI.
public enum LorvexDataExportCategory: String, CaseIterable, Identifiable, Sendable {
  case tasks
  case lists
  case tags
  case habits
  case calendarEvents = "calendar_events"
  case dailyReviews = "daily_reviews"
  case dailyBriefings = "daily_briefings"
  case taskCalendarEventLinks = "task_calendar_event_links"
  case memory
  case preferences

  public var id: String { rawValue }

  public var displayLabel: String {
    switch self {
    case .tasks: "Tasks"
    case .lists: "Lists"
    case .tags: "Tags"
    case .habits: "Habits"
    case .calendarEvents: "Calendar Events"
    case .dailyReviews: "Daily Reviews"
    case .dailyBriefings: "Daily Briefings"
    case .taskCalendarEventLinks: "Task–Event Links"
    case .memory: "Memory"
    case .preferences: "Preferences"
    }
  }
}

extension LorvexDataExportCategory {
  /// The groups an export picker lists the categories under, in order: what
  /// you plan with, the calendar, what you and the assistant wrote about your
  /// days, and the app's settings.
  public enum Group: String, CaseIterable, Identifiable, Sendable {
    case planning
    case calendar
    case reflection
    case settings

    public var id: String { rawValue }

    /// The group's categories, in the order the picker lists them.
    public var categories: [LorvexDataExportCategory] {
      LorvexDataExportCategory.allCases.filter { $0.group == self }
    }
  }

  public var group: Group {
    switch self {
    case .tasks, .lists, .tags, .habits: .planning
    case .calendarEvents, .taskCalendarEventLinks: .calendar
    case .dailyReviews, .dailyBriefings, .memory: .reflection
    case .preferences: .settings
    }
  }

  /// The category's symbol, the one the app's own surfaces use for it.
  public var systemImage: String {
    switch self {
    case .tasks: "checklist"
    case .lists: "list.bullet.rectangle"
    case .tags: "tag"
    case .habits: "repeat.circle"
    case .calendarEvents: "calendar"
    case .taskCalendarEventLinks: "link"
    case .dailyReviews: "text.badge.checkmark"
    case .dailyBriefings: "sun.max"
    case .memory: "brain"
    case .preferences: "gearshape"
    }
  }
}
