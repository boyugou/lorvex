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

  /// One surface's state as its Settings row shows it.
  struct Status: Equatable {
    /// The short state: a count, "Disabled", "Permission Denied", or "Failed".
    var value: String
    /// The line under the state: what went wrong, in the error's own words;
    /// how many reminders a denied permission kept from being scheduled; or
    /// when the widget snapshot was published.
    var detail: String?
    /// True for a state the user should look at: a failure, or a denied
    /// permission that keeps reminders from being scheduled.
    var needsAttention: Bool

    init(_ value: String, detail: String? = nil, needsAttention: Bool = false) {
      self.value = value
      self.detail = detail
      self.needsAttention = needsAttention
    }
  }

  var spotlight: Status {
    if let errorMessage = spotlightTaskIndexErrorMessage ?? spotlightContentIndexErrorMessage {
      return Self.failed(errorMessage)
    }
    let tasks = spotlightIndexedTaskCount
    let events = spotlightIndexedCalendarEventCount
    return Status(
      String(
        localized: "settings.diagnostics.status.spotlight",
        defaultValue: "\(tasks) tasks, \(events) calendar events",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
  }

  var taskReminders: Status {
    Self.reminders(taskReminderScheduleReport, scheduledCount: scheduledReminderCount)
  }

  var habitReminders: Status {
    Self.reminders(habitReminderScheduleReport, scheduledCount: habitReminderScheduleReport.scheduledCount)
  }

  private static func reminders(_ report: TaskReminderScheduleReport, scheduledCount: Int) -> Status {
    switch report.status {
    case .disabled:
      return Status(
        String(
          localized: "settings.diagnostics.status.disabled", defaultValue: "Disabled",
          table: "Localizable", bundle: LorvexL10n.bundle))
    case .scheduled:
      return Status(
        String(
          localized: "settings.diagnostics.status.reminders_scheduled_count",
          defaultValue: scheduledCount == 1
            ? "\(scheduledCount) scheduled reminder"
            : "\(scheduledCount) scheduled reminders",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
    case .permissionDenied:
      let requested = report.requestedCount
      return Status(
        String(
          localized: "settings.diagnostics.status.permission_denied",
          defaultValue: "Permission Denied",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        detail: requested > 0
          ? String(
            localized: "settings.diagnostics.reminder_requests.detail",
            defaultValue: "\(requested) requested",
            table: "Localizable", bundle: LorvexL10n.bundle)
          : nil,
        needsAttention: true)
    case .failed:
      return failed(report.errorMessage)
    }
  }

  var widget: Status {
    guard widgetSnapshot != nil else {
      return Status(
        String(
          localized: "settings.diagnostics.status.widget_no_snapshot",
          defaultValue: "No snapshot published",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
    }
    return Status(
      String(
        localized: "settings.diagnostics.status.widget_published",
        defaultValue: "Published",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      detail: widgetGeneratedAt.map { LorvexDateFormatters.dayAndClockTime($0) })
  }

  /// How many of Today's tasks the published widget snapshot carries.
  var widgetTodayTaskCount: Int {
    widgetSnapshot?.tasks.count ?? 0
  }

  /// When the widget snapshot was published, parsed from its ISO 8601 stamp;
  /// nil when no snapshot has been published or the stamp cannot be read.
  var widgetGeneratedAt: Date? {
    guard let raw = widgetSnapshot?.generatedAt else { return nil }
    return LorvexDateFormatters.iso8601Fractional.date(from: raw)
      ?? LorvexDateFormatters.iso8601.date(from: raw)
  }

  var calendarImport: Status {
    switch lastCalendarImportReport.status {
    case .notStarted:
      return Status(
        String(
          localized: "settings.diagnostics.status.not_started", defaultValue: "Not started",
          table: "Localizable", bundle: LorvexL10n.bundle))
    case .succeeded:
      let importedCount = importedCalendarEventCount
      return Status(
        String(
          localized: "settings.diagnostics.status.calendar_import_succeeded_count",
          defaultValue: importedCount == 1
            ? "\(importedCount) imported event"
            : "\(importedCount) imported events",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
    case .skipped:
      return Status(
        String(
          localized: "settings.diagnostics.status.skipped", defaultValue: "Skipped",
          table: "Localizable", bundle: LorvexL10n.bundle))
    case .failed:
      return Self.failed(lastCalendarImportReport.errorMessage)
    }
  }

  /// A failure: "Failed", with the error's own words on the line under it.
  private static func failed(_ message: String?) -> Status {
    Status(
      String(
        localized: "settings.diagnostics.status.failed", defaultValue: "Failed",
        table: "Localizable", bundle: LorvexL10n.bundle),
      detail: message,
      needsAttention: true)
  }
}
