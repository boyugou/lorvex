import Foundation
import LorvexCore

extension LorvexDataExportCategory {
  var lorvexLocalizedDisplayLabel: String {
    switch self {
    case .tasks:
      String(localized: "data_export.category.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .lists:
      String(localized: "data_export.category.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case .tags:
      String(localized: "data_export.category.tags", defaultValue: "Tags", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habits:
      String(localized: "data_export.category.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendarEvents:
      String(localized: "data_export.category.calendar_events", defaultValue: "Calendar Events", table: "Localizable", bundle: LorvexL10n.bundle)
    case .dailyReviews:
      String(localized: "data_export.category.daily_reviews", defaultValue: "Daily Reviews", table: "Localizable", bundle: LorvexL10n.bundle)
    case .dailyBriefings:
      String(localized: "data_export.category.daily_briefings", defaultValue: "Daily Briefings", table: "Localizable", bundle: LorvexL10n.bundle)
    case .taskCalendarEventLinks:
      String(localized: "data_export.category.task_calendar_event_links", defaultValue: "Task–Event Links", table: "Localizable", bundle: LorvexL10n.bundle)
    case .memory:
      String(localized: "data_export.category.memory", defaultValue: "Memory", table: "Localizable", bundle: LorvexL10n.bundle)
    case .preferences:
      String(localized: "data_export.category.preferences", defaultValue: "Preferences", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

enum LorvexImportSummaryText {
  static let provider = ImportSummaryTextProvider(
    categoryName: { $0.lorvexLocalizedDisplayLabel },
    importedRecordSummary: { imported, skipped in
      let base = String(
        localized: "settings.data_import.summary.imported_count",
        defaultValue: "\(imported) imported records",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
      guard skipped > 0 else { return base }
      return String(
        format: String(
          localized: "settings.data_import.summary.imported_with_skipped",
          defaultValue: "%1$@, %2$@ already present",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        base,
        String(
          localized: "settings.data_import.summary.skipped_count",
          defaultValue: "\(skipped) records",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      )
    },
    categoryResultSummary: { imported, skipped in
      let base = String(
        format: String(
          localized: "settings.data_import.summary.category_imported_count",
          defaultValue: "%lld imported",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        Int64(imported))
      guard skipped > 0 else { return base }
      return String(
        format: String(
          localized: "settings.data_import.summary.category_imported_with_skipped",
          defaultValue: "%1$@, %2$@ skipped",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        base,
        String(
          format: String(
            localized: "settings.data_import.summary.category_skipped_count",
            defaultValue: "%lld",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          Int64(skipped))
      )
    },
    errorSummary: { count in
      String(
        localized: "settings.data_import.summary.error_count",
        defaultValue: "\(count) records skipped due to errors:",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    },
    hiddenErrorsSummary: { count in
      String(
        format: String(
          localized: "settings.data_import.summary.more_errors_count",
          defaultValue: "and %lld more…",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        Int64(count))
    }
  )


}

extension LorvexDataExportCategory.Group {
  var lorvexLocalizedName: String {
    switch self {
    case .planning: String(localized: "data_export.group.planning", defaultValue: "Planning", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendar: String(localized: "data_export.group.calendar", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reflection: String(localized: "data_export.group.reflection", defaultValue: "Reviews & Assistant", table: "Localizable", bundle: LorvexL10n.bundle)
    case .settings: String(localized: "data_export.group.settings", defaultValue: "Settings", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
