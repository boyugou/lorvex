import Foundation
import LorvexCore

extension LorvexDataExportCategory {
  var mobileLocalizedDisplayLabel: String {
    switch self {
    case .tasks:
      String(
        localized: "data_export.category.tasks", defaultValue: "Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .lists:
      String(
        localized: "data_export.category.lists", defaultValue: "Lists", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .tags:
      String(
        localized: "data_export.category.tags", defaultValue: "Tags", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .habits:
      String(
        localized: "data_export.category.habits", defaultValue: "Habits", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .calendarEvents:
      String(
        localized: "data_export.category.calendar_events", defaultValue: "Calendar Events",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .dailyReviews:
      String(
        localized: "data_export.category.daily_reviews", defaultValue: "Daily Reviews",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .dailyBriefings:
      String(
        localized: "data_export.category.daily_briefings", defaultValue: "Daily Briefings",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .taskCalendarEventLinks:
      String(
        localized: "data_export.category.task_calendar_event_links",
        defaultValue: "Task–Event Links", table: "Localizable", bundle: MobileL10n.bundle)
    case .memory:
      String(
        localized: "data_export.category.memory", defaultValue: "Memory", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .preferences:
      String(
        localized: "data_export.category.preferences", defaultValue: "Preferences",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

enum MobileImportSummaryText {
  static let provider = ImportSummaryTextProvider(
    categoryName: { $0.mobileLocalizedDisplayLabel },
    importedRecordSummary: { imported, skipped in
      let base = String(
        localized: "data_import.summary.imported_count",
        defaultValue: "\(imported) imported records",
        table: "Localizable", bundle: MobileL10n.bundle)
      guard skipped > 0 else { return base }
      return String(
        format: String(
          localized: "data_import.summary.imported_with_skipped",
          defaultValue: "%1$@, %2$@ already present", table: "Localizable",
          bundle: MobileL10n.bundle),
        base,
        String(
          localized: "data_import.summary.skipped_count", defaultValue: "\(skipped) records",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
    },
    categoryResultSummary: { imported, skipped in
      let base = String(
        localized: "data_import.summary.category_imported_count",
        defaultValue: "\(imported) imported",
        table: "Localizable", bundle: MobileL10n.bundle)
      guard skipped > 0 else { return base }
      return String(
        format: String(
          localized: "data_import.summary.category_imported_with_skipped",
          defaultValue: "%1$@, %2$@ skipped", table: "Localizable", bundle: MobileL10n.bundle),
        base,
        String(
          localized: "data_import.summary.category_skipped_count", defaultValue: "\(skipped)",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
    },
    errorSummary: { count in
      String(
        localized: "data_import.summary.error_count",
        defaultValue: "\(count) records skipped due to errors:",
        table: "Localizable", bundle: MobileL10n.bundle)
    },
    hiddenErrorsSummary: { count in
      String(
        localized: "data_import.summary.more_errors_count", defaultValue: "and \(count) more…",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  )

}

extension LorvexDataExportCategory.Group {
  var mobileLocalizedName: String {
    switch self {
    case .planning: String(localized: "data_export.group.planning", defaultValue: "Planning", table: "Localizable", bundle: MobileL10n.bundle)
    case .calendar: String(localized: "data_export.group.calendar", defaultValue: "Calendar", table: "Localizable", bundle: MobileL10n.bundle)
    case .reflection: String(localized: "data_export.group.reflection", defaultValue: "Reviews & Assistant", table: "Localizable", bundle: MobileL10n.bundle)
    case .settings: String(localized: "data_export.group.settings", defaultValue: "Settings", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}
