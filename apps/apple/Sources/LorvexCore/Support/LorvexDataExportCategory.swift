import Foundation

/// A selectable category of data in an export run.
///
/// `rawValue` is the canonical entity name shared across every export surface:
/// the `exportData(entities:format:)` selector, the CSV section headers, and
/// the App Intent entity options all key off these same strings.
/// ``localizedDisplayName`` is the name people see for it on every surface:
/// the export pickers, the import preview, and the import summary.
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

  /// The category's name, from LorvexCore's catalog ("Tasks", "Calendar
  /// Events"), so the Mac and iPhone export and import screens name it alike.
  public var localizedDisplayName: String {
    switch self {
    case .tasks:
      String(localized: "data_export.category.tasks", defaultValue: "Tasks", table: "Localizable", bundle: CoreL10n.bundle)
    case .lists:
      String(localized: "data_export.category.lists", defaultValue: "Lists", table: "Localizable", bundle: CoreL10n.bundle)
    case .tags:
      String(localized: "data_export.category.tags", defaultValue: "Tags", table: "Localizable", bundle: CoreL10n.bundle)
    case .habits:
      String(localized: "data_export.category.habits", defaultValue: "Habits", table: "Localizable", bundle: CoreL10n.bundle)
    case .calendarEvents:
      String(localized: "data_export.category.calendar_events", defaultValue: "Calendar Events", table: "Localizable", bundle: CoreL10n.bundle)
    case .dailyReviews:
      String(localized: "data_export.category.daily_reviews", defaultValue: "Daily Reviews", table: "Localizable", bundle: CoreL10n.bundle)
    case .dailyBriefings:
      String(localized: "data_export.category.daily_briefings", defaultValue: "Daily Briefings", table: "Localizable", bundle: CoreL10n.bundle)
    case .taskCalendarEventLinks:
      String(localized: "data_export.category.task_calendar_event_links", defaultValue: "Task–Event Links", table: "Localizable", bundle: CoreL10n.bundle)
    case .memory:
      String(localized: "data_export.category.memory", defaultValue: "Memory", table: "Localizable", bundle: CoreL10n.bundle)
    case .preferences:
      String(localized: "data_export.category.preferences", defaultValue: "Preferences", table: "Localizable", bundle: CoreL10n.bundle)
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

    /// The group's name over its categories in an export picker, from
    /// LorvexCore's catalog ("Planning", "Reviews & Assistant").
    public var localizedName: String {
      switch self {
      case .planning:
        String(localized: "data_export.group.planning", defaultValue: "Planning", table: "Localizable", bundle: CoreL10n.bundle)
      case .calendar:
        String(localized: "data_export.group.calendar", defaultValue: "Calendar", table: "Localizable", bundle: CoreL10n.bundle)
      case .reflection:
        String(localized: "data_export.group.reflection", defaultValue: "Reviews & Assistant", table: "Localizable", bundle: CoreL10n.bundle)
      case .settings:
        String(localized: "data_export.group.settings", defaultValue: "Settings", table: "Localizable", bundle: CoreL10n.bundle)
      }
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
