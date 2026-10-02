import Foundation

/// Lengths of time — task estimates, planned blocks, a day's load, time left —
/// written by the system's CLDR duration rules in a display locale, so each
/// language gets its own unit words, plural forms, digits, and spacing: "45
/// min", "1 hr 30 min", "2 hr" in English; "45分钟", "1小时30分钟" in Chinese;
/// "1 ч 30 мин" in Russian.
///
/// The locale defaults to ``LorvexClockFormat/displayLocale``, read on every
/// call: the language the process's bundles resolved, with the user's region
/// conventions. A label is therefore always in the language of the strings
/// around it, including when the system language is one Lorvex does not ship.
public enum LorvexDurationFormat {
  /// How the units are written.
  public enum Style: Sendable {
    /// Compact unit words for labels: "1 hr 30 min", "45 min".
    case compact
    /// Spelled-out units for VoiceOver: "1 hour, 30 minutes", "45 minutes".
    case spoken

    fileprivate var width: Duration.UnitsFormatStyle.UnitWidth {
      switch self {
      case .compact: .condensedAbbreviated
      case .spoken: .wide
      }
    }
  }

  /// `minutes` in minutes alone ("90 min"), the way task estimates read: an
  /// estimate's size compares best in one unit.
  public static func minutes(
    _ minutes: Int, style: Style = .compact, locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    format(minutes, units: [.minutes], style: style, locale: locale)
  }

  /// `minutes` in hours and minutes, leaving out a zero part: "45 min", "2
  /// hr", "2 hr 30 min". For planned time, a day's load, and intervals.
  public static func hoursAndMinutes(
    _ minutes: Int, style: Style = .compact, locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    format(minutes, units: [.hours, .minutes], style: style, locale: locale)
  }

  /// `minutes` in hours alone, with one decimal for a part hour: "3 hr",
  /// "2.5 hr" ("2,5 h" in Spanish). For a rough total that reads as one
  /// figure; round `minutes` to the precision the label claims first.
  public static func hours(
    _ minutes: Int, style: Style = .compact, locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    format(
      minutes, units: [.hours], style: style, locale: locale,
      fractionalPart: minutes.isMultiple(of: 60) ? .hide : .show(length: 1))
  }

  private static func format(
    _ minutes: Int, units: Set<Duration.UnitsFormatStyle.Unit>, style: Style, locale: Locale,
    fractionalPart: Duration.UnitsFormatStyle.FractionalPartDisplayStrategy = .hide
  ) -> String {
    Duration.seconds(Int64(max(0, minutes)) * 60)
      .formatted(
        .units(allowed: units, width: style.width, fractionalPart: fractionalPart).locale(locale))
  }
}
