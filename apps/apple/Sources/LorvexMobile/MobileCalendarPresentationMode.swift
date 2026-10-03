import Foundation

/// How the mobile calendar shows time: the width-adaptive 1/2/3-day time grid
/// (the default), the seven days of a week, or a month of days over the
/// chosen day's agenda. The cases are in picker order: Day, Week, Month.
public enum MobileCalendarPresentationMode: String, CaseIterable, Identifiable, Sendable {
  case grid
  case week
  case month

  public var id: String { rawValue }

  /// The `UserDefaults` key holding the mode the user last chose.
  static let defaultsKey = "calendar.presentationMode"

  /// The mode last chosen as `defaults` remembers it, or Day when it holds
  /// none (or a value no case names).
  static func remembered(in defaults: UserDefaults) -> MobileCalendarPresentationMode {
    defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .grid
  }

  /// The mode's name in the picker. The grid is named by the days it shows
  /// at the current width: "Day" for one, "3 Days" for more.
  public func title(gridDayCount: Int) -> String {
    switch self {
    case .week:
      return String(
        localized: "calendar.mode.week", defaultValue: "Week", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .month:
      return String(
        localized: "calendar.mode.month", defaultValue: "Month", table: "Localizable",
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
