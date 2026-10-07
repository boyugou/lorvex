import SwiftUI

/// The days a menu offers for planning a task without dragging it: today,
/// tomorrow, three days on, and a week on. Each counts from the product's logical
/// today, as ``AppStore/planTasks(ids:daysFromToday:undoManager:)`` does. The row
/// context menu and the Task menu in the menu bar list the same four choices.
enum TaskPlanDayChoice: CaseIterable, Identifiable {
  case today
  case tomorrow
  case inThreeDays
  case nextWeek

  var id: Self { self }

  /// Days after the product's logical today.
  var daysFromToday: Int {
    switch self {
    case .today: 0
    case .tomorrow: 1
    case .inThreeDays: 3
    case .nextWeek: 7
    }
  }

  var title: String {
    switch self {
    case .today:
      String(localized: "date_chip.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .tomorrow:
      String(localized: "date_chip.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle)
    case .inThreeDays:
      String(localized: "task.defer.in_3_days", defaultValue: "In 3 days", table: "Localizable", bundle: LorvexL10n.bundle)
    case .nextWeek:
      String(localized: "date_chip.next_week", defaultValue: "Next Week", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var systemImage: String {
    switch self {
    case .today: "sun.max"
    case .tomorrow: "sunrise"
    case .inThreeDays: "calendar"
    case .nextWeek: "calendar.badge.clock"
    }
  }
}
