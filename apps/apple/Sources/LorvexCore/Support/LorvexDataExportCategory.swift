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
  case currentFocus = "current_focus"
  case focusSchedules = "focus_schedules"
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
    case .currentFocus: "Current Focus"
    case .focusSchedules: "Focus Schedules"
    case .taskCalendarEventLinks: "Task Calendar Links"
    case .memory: "Memory"
    case .preferences: "Preferences"
    }
  }
}
