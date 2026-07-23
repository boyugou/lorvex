import Foundation

/// Cached user-facing formatters that follow the language selected for the
/// LorvexMobile resource bundle, including per-app language overrides.
enum MobileDateFormatting {
  static let weekdayAbbrev: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter
  }()

  static let dayOfMonth: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = MobileL10n.locale
    formatter.setLocalizedDateFormatFromTemplate("d")
    return formatter
  }()

  static func abbreviatedRelativeString(for date: Date, relativeTo referenceDate: Date) -> String {
    makeAbbreviatedRelativeFormatter().localizedString(for: date, relativeTo: referenceDate)
  }

  static func makeAbbreviatedRelativeFormatter() -> RelativeDateTimeFormatter {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = MobileL10n.locale
    formatter.unitsStyle = .abbreviated
    return formatter
  }
}
