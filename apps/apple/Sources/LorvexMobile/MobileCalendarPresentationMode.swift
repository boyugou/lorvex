import Foundation

/// How many days the mobile calendar's time grid shows: the width-adaptive
/// 1/2/3-day grid (the default), or the seven days of a week. The cases are
/// in picker order, Day before Week.
public enum MobileCalendarPresentationMode: String, CaseIterable, Identifiable, Sendable {
  case grid
  case week

  public var id: String { rawValue }

  /// The mode's name in the picker. The grid is named by the days it shows
  /// at the current width: "Day" for one, "3 Days" for more.
  public func title(gridDayCount: Int) -> String {
    switch self {
    case .week:
      return String(
        localized: "calendar.mode.week", defaultValue: "Week", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .grid where gridDayCount > 1:
      return String(
        localized: "calendar.mode.days", defaultValue: "\(gridDayCount) Days",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .grid:
      return String(
        localized: "calendar.mode.day", defaultValue: "Day", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}
