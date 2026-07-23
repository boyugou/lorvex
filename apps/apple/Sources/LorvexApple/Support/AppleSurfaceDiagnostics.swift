import Foundation
import LorvexCore
import LorvexWidgetKitSupport

/// A point-in-time snapshot of Apple surface integration health exposed in
/// Settings. All fields are derived from the last completed operation; errors
/// are informational only and never block core Lorvex calendar data.
struct AppleSurfaceDiagnostics: Equatable, Sendable {
  var spotlightIndexedTaskCount: Int
  var spotlightIndexedCalendarEventCount: Int
  var spotlightTaskIndexErrorMessage: String? = nil
  var spotlightContentIndexErrorMessage: String? = nil
  var scheduledReminderCount: Int
  var taskReminderScheduleReport: TaskReminderScheduleReport
  var habitReminderScheduleReport: TaskReminderScheduleReport = .disabled
  var widgetSnapshot: WidgetSnapshot?

  // EventKit calendar import
  var lastCalendarImportReport: CalendarIntegrationReport
  var importedCalendarEventCount: Int

  var spotlightStatus: String {
    if let errorMessage = spotlightTaskIndexErrorMessage ?? spotlightContentIndexErrorMessage {
      return Self.failedStatus(errorMessage)
    }
    let taskCount = spotlightIndexedTaskCount
    let taskLabel = String(
      localized: "settings.diagnostics.status.spotlight_task_count",
      defaultValue: taskCount == 1 ? "\(taskCount) task" : "\(taskCount) tasks",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
    let eventCount = spotlightIndexedCalendarEventCount
    let eventLabel = String(
      localized: "settings.diagnostics.status.spotlight_event_count",
      defaultValue: eventCount == 1
        ? "\(eventCount) calendar event" : "\(eventCount) calendar events",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
    return String(
      format: String(
        localized: "settings.diagnostics.status.spotlight",
        defaultValue: "%1$@, %2$@",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      taskLabel,
      eventLabel
    )
  }

  var reminderStatus: String {
    Self.reminderStatus(taskReminderScheduleReport, scheduledCount: scheduledReminderCount)
  }

  var habitReminderStatus: String {
    Self.reminderStatus(
      habitReminderScheduleReport, scheduledCount: habitReminderScheduleReport.scheduledCount)
  }

  private static func reminderStatus(
    _ report: TaskReminderScheduleReport, scheduledCount: Int
  ) -> String {
    switch report.status {
    case .disabled:
      return String(
        localized: "settings.diagnostics.status.disabled", defaultValue: "Disabled",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .scheduled:
      return String(
        localized: "settings.diagnostics.status.reminders_scheduled_count",
        defaultValue: scheduledCount == 1
          ? "\(scheduledCount) scheduled reminder"
          : "\(scheduledCount) scheduled reminders",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .permissionDenied:
      return String(
        localized: "settings.diagnostics.status.permission_denied",
        defaultValue: "Permission Denied",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .failed:
      return failedStatus(report.errorMessage)
    }
  }

  var widgetStatus: String {
    guard let widgetSnapshot else {
      return String(
        localized: "settings.diagnostics.status.widget_no_snapshot",
        defaultValue: "No snapshot published",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return String(
      format: String(
        localized: "settings.diagnostics.status.widget_published",
        defaultValue: "Published v%lld",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      widgetSnapshot.version
    )
  }

  var widgetFocusTaskCount: Int {
    widgetSnapshot?.focusTasks.count ?? 0
  }

  var widgetGeneratedAt: String? {
    widgetSnapshot?.generatedAt
  }

  var calendarImportStatus: String {
    switch lastCalendarImportReport.status {
    case .notStarted:
      return String(
        localized: "settings.diagnostics.status.not_started", defaultValue: "Not started",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .succeeded:
      let importedCount = importedCalendarEventCount
      return String(
        localized: "settings.diagnostics.status.calendar_import_succeeded_count",
        defaultValue: importedCount == 1
          ? "\(importedCount) imported event"
          : "\(importedCount) imported events",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .skipped:
      return String(
        localized: "settings.diagnostics.status.skipped", defaultValue: "Skipped",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .failed:
      return Self.failedStatus(lastCalendarImportReport.errorMessage)
    }
  }

  private static func failedStatus(_ message: String?) -> String {
    String(
      format: String(
        localized: "settings.diagnostics.status.failed", defaultValue: "Failed: %@",
        table: "Localizable", bundle: LorvexL10n.bundle),
      message ?? String(
        localized: "settings.diagnostics.status.unknown_error", defaultValue: "unknown error",
        table: "Localizable", bundle: LorvexL10n.bundle)
    )
  }
}
