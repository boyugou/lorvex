import Foundation
import LorvexCore

extension WidgetSnapshotProjector {
  /// `tasks` narrowed to the Focus filter's lists while one is active, in the
  /// order given; every task otherwise.
  static func focusScoped(
    _ tasks: [LorvexTask], focusFilter: FocusFilterConfiguration
  ) -> [LorvexTask] {
    guard focusFilter.isActive else { return tasks }
    let listIDs = Set(focusFilter.listIDs)
    return tasks.filter { task in task.listID.map(listIDs.contains) ?? false }
  }

  static func dateOnlyString(from date: Date) -> String {
    LorvexDateFormatters.ymdUTC.string(from: date)
  }

  /// `YYYY-MM-DD` for `date` in `calendar`'s time zone — the user's perceived
  /// wall-calendar day. Used to derive "today" for the due-today/overdue stats,
  /// versus `dateOnlyString` which reads a stored due date's canonical day in
  /// UTC.
  static func localDateOnlyString(from date: Date, calendar: Calendar) -> String {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let components = gregorian.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  static func timestampString(from date: Date) -> String {
    LorvexDateFormatters.iso8601.string(from: date)
  }
}
