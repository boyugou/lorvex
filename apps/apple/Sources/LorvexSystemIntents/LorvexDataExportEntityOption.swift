import AppIntents
import LorvexCore

/// Selectable entity for the export App Intent. The `all` sentinel plus one case
/// per ``LorvexDataExportCategory``, so every export category is individually
/// selectable from Shortcuts/Siri. The case rawValues are AppIntents
/// serialization identifiers (camelCase, distinct from the snake_case core
/// names); ``coreEntityName`` and ``caseDisplayRepresentations`` are derived from
/// the matching `LorvexDataExportCategory` so the user-facing labels and the core
/// selector strings stay in one source of truth.
enum LorvexDataExportEntityOption: String, AppEnum {
  case all
  case tasks
  case lists
  case tags
  case habits
  case calendarEvents
  case dailyReviews
  case currentFocus
  case focusSchedules
  case taskCalendarEventLinks
  case memory
  case preferences

  /// The export category this option maps to, or `nil` for the `all` sentinel.
  private var category: LorvexDataExportCategory? {
    switch self {
    case .all: nil
    case .tasks: .tasks
    case .lists: .lists
    case .tags: .tags
    case .habits: .habits
    case .calendarEvents: .calendarEvents
    case .dailyReviews: .dailyReviews
    case .currentFocus: .currentFocus
    case .focusSchedules: .focusSchedules
    case .taskCalendarEventLinks: .taskCalendarEventLinks
    case .memory: .memory
    case .preferences: .preferences
    }
  }

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.data_entity.type", defaultValue: "Data Entity", table: "Localizable", bundle: SystemL10n.bundle))
  // Must be a compile-time static literal — the AppIntents `ExtractAppIntentsMetadata`
  // build phase parses this at build time and rejects a computed/closure form.
  // Labels mirror `LorvexDataExportCategory.displayLabel`.
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .all: .init(title: LocalizedStringResource("system.option.data_entity.all", defaultValue: "All", table: "Localizable", bundle: SystemL10n.bundle)),
    .tasks: .init(title: LocalizedStringResource("system.option.data_entity.tasks", defaultValue: "Tasks", table: "Localizable", bundle: SystemL10n.bundle)),
    .lists: .init(title: LocalizedStringResource("system.option.data_entity.lists", defaultValue: "Lists", table: "Localizable", bundle: SystemL10n.bundle)),
    .tags: .init(title: LocalizedStringResource("system.option.data_entity.tags", defaultValue: "Tags", table: "Localizable", bundle: SystemL10n.bundle)),
    .habits: .init(title: LocalizedStringResource("system.option.data_entity.habits", defaultValue: "Habits", table: "Localizable", bundle: SystemL10n.bundle)),
    .calendarEvents: .init(title: LocalizedStringResource("system.option.data_entity.calendar_events", defaultValue: "Calendar Events", table: "Localizable", bundle: SystemL10n.bundle)),
    .dailyReviews: .init(title: LocalizedStringResource("system.option.data_entity.daily_reviews", defaultValue: "Daily Reviews", table: "Localizable", bundle: SystemL10n.bundle)),
    .currentFocus: .init(title: LocalizedStringResource("system.option.data_entity.current_focus", defaultValue: "Current Focus", table: "Localizable", bundle: SystemL10n.bundle)),
    .focusSchedules: .init(title: LocalizedStringResource("system.option.data_entity.focus_schedules", defaultValue: "Focus Schedules", table: "Localizable", bundle: SystemL10n.bundle)),
    .taskCalendarEventLinks: .init(title: LocalizedStringResource("system.option.data_entity.task_calendar_event_links", defaultValue: "Task Calendar Links", table: "Localizable", bundle: SystemL10n.bundle)),
    .memory: .init(title: LocalizedStringResource("system.option.data_entity.memory", defaultValue: "Memory", table: "Localizable", bundle: SystemL10n.bundle)),
    .preferences: .init(title: LocalizedStringResource("system.option.data_entity.preferences", defaultValue: "Preferences", table: "Localizable", bundle: SystemL10n.bundle)),
  ]

  /// The canonical core entity name passed to `exportData(entities:format:)`.
  var coreEntityName: String { category?.rawValue ?? "all" }
}
