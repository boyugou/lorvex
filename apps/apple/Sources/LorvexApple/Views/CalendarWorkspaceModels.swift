import Foundation
import LorvexCore

/// Calendar presentation: a focused day timeline, the default week timeline,
/// or the month grid. `String`-backed so the workspace can persist the user's
/// choice via `@AppStorage`, matching how the Tasks workspace persists
/// `isTableMode`.
enum CalendarPresentationMode: String, Hashable, CaseIterable {
  case day
  case week
  case month

  /// The first day of the period this mode shows around `anchor`: the day
  /// itself, the first day of its week by the calendar's first weekday, or
  /// the first day of its month.
  func periodStart(containing anchor: Date, calendar: Calendar) -> Date {
    switch self {
    case .day: calendar.startOfDay(for: anchor)
    case .week: CalendarGridModel.startOfWeek(containing: anchor, calendar: calendar)
    case .month: CalendarMonthGridModel.startOfMonth(containing: anchor, calendar: calendar)
    }
  }

  /// `anchor` moved by `periods` of this mode: days, weeks of seven days, or
  /// calendar months. A week step keeps the weekday; a month step keeps the
  /// day of the month, clamped to the target month's length.
  func anchor(_ anchor: Date, steppedBy periods: Int, calendar: Calendar) -> Date {
    let moved =
      switch self {
      case .day: calendar.date(byAdding: .day, value: periods, to: anchor)
      case .week: calendar.date(byAdding: .day, value: 7 * periods, to: anchor)
      case .month: calendar.date(byAdding: .month, value: periods, to: anchor)
      }
    return moved ?? anchor
  }

  /// The accessibility label of the Day/Week/Month choice as a whole.
  static var pickerLabel: String {
    String(
      localized: "calendar.nav.view_mode.a11y", defaultValue: "Calendar view mode",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The mode's name in the Day/Week/Month toggle and the View menu.
  var title: String {
    switch self {
    case .day:
      String(localized: "calendar.mode.day", defaultValue: "Day", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "calendar.mode.week", defaultValue: "Week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "calendar.mode.month", defaultValue: "Month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// The jump back to the period that holds today: "Today", "This Week" or
  /// "This Month".
  var currentPeriodTitle: String {
    switch self {
    case .day:
      String(localized: "calendar.nav.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "calendar.nav.this_week", defaultValue: "This Week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "calendar.nav.this_month", defaultValue: "This Month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// The period a calendar mode shows around an anchor day, named by the mode
/// and the period's first day. Two anchors in the same week share a week
/// period, so picking another day inside the visible period leaves it equal
/// and nothing refetches.
struct CalendarVisiblePeriod: Equatable {
  let mode: CalendarPresentationMode
  let start: Date

  init(mode: CalendarPresentationMode, anchor: Date, calendar: Calendar) {
    self.mode = mode
    self.start = mode.periodStart(containing: anchor, calendar: calendar)
  }
}
