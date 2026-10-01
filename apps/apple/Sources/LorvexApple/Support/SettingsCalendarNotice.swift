import Foundation

/// A problem the Calendar settings page reports above its controls. The page
/// reports nothing while all is well: the calendar itself shows what arrived,
/// and Diagnostics keeps the import detail for troubleshooting.
enum SettingsCalendarNotice: Hashable {
  /// Calendar access was denied, and only System Settings can grant it again.
  case accessDenied
  /// The latest read of the calendars failed. Every refresh reads them again,
  /// so the notice clears itself once the cause is gone.
  case readFailed
  /// The latest write of an event into a calendar failed. A write is not
  /// retried on its own; saving the event again retries it.
  case writeFailed

  /// The notices to show, in page order. Denied access explains any failed
  /// read or write, so it stands alone. Failures count only while two-way sync
  /// is on: a report from before the user turned it off describes nothing
  /// current.
  static func notices(
    needsAccessRecovery: Bool,
    isSyncEnabled: Bool,
    importReport: CalendarIntegrationReport,
    exportReport: CalendarIntegrationReport
  ) -> [SettingsCalendarNotice] {
    if needsAccessRecovery { return [.accessDenied] }
    guard isSyncEnabled else { return [] }
    var notices: [SettingsCalendarNotice] = []
    if importReport.status == .failed { notices.append(.readFailed) }
    if exportReport.status == .failed { notices.append(.writeFailed) }
    return notices
  }
}
