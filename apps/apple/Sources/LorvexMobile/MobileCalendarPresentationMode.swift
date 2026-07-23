import Foundation

/// How the mobile calendar renders: a seven-day grouped agenda or the default
/// width-adaptive 1/2/3-day time-axis grid.
public enum MobileCalendarPresentationMode: String, CaseIterable, Identifiable, Sendable {
  case week
  case grid

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .week:
      return String(
        localized: "calendar.mode.week", defaultValue: "Week", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .grid:
      return String(
        localized: "calendar.mode.day", defaultValue: "Day", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}
