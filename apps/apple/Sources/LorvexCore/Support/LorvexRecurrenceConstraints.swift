import Foundation

/// The date filters a repeat summary names beside its frequency and weekdays.
/// Month numbers always name Gregorian months, even in a locale that displays
/// another calendar. Signed days and positions count from the start or end;
/// malformed values remain visible without overflowing ordinal arithmetic.
enum LorvexRecurrenceConstraints {
  static func months(_ values: [Int], locale: Locale = LorvexClockFormat.displayLocale) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    let names = calendar.shortStandaloneMonthSymbols
    return Set(values).sorted().map { month in
      (1...12).contains(month) && names.count == 12 ? names[month - 1] : String(month)
    }.formatted(.list(type: .and, width: .narrow).locale(locale))
  }

  static func monthDays(_ values: [Int], locale: Locale = LorvexClockFormat.displayLocale) -> String {
    signedDays(values, selection: false, locale: locale)
  }

  static func positions(_ values: [Int], locale: Locale = LorvexClockFormat.displayLocale) -> String {
    signedDays(values, selection: true, locale: locale)
  }

  static func weekStart(_ code: String) -> String {
    let day = LorvexRecurrenceWeekdays.summary([code])
    return String(
      localized: "recurrence.week_start", defaultValue: "week starts \(day)",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static func signedDays(_ values: [Int], selection: Bool, locale: Locale) -> String {
    let ordered = Set(values).sorted { lhs, rhs in
      if (lhs > 0) != (rhs > 0) { return lhs > 0 }
      return lhs.magnitude < rhs.magnitude
    }
    var ordinals: NumberFormatter?
    func ordinal(_ value: Int) -> String {
      let formatter = ordinals ?? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter
      }()
      ordinals = formatter
      return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    let names = ordered.map { value -> String in
      let limit: UInt = selection ? 366 : 31
      guard value != 0, value.magnitude <= limit else { return String(value) }
      if selection {
        if value == -1 {
          return String(
            localized: "recurrence.position.last", defaultValue: "last matching day",
            table: "Localizable", bundle: CoreL10n.bundle)
        }
        let place = ordinal(Int(value.magnitude))
        if value < 0 {
          return String(
            localized: "recurrence.position.nth_last", defaultValue: "\(place)-to-last matching day",
            table: "Localizable", bundle: CoreL10n.bundle)
        }
        return String(
          localized: "recurrence.position.nth", defaultValue: "\(place) matching day",
          table: "Localizable", bundle: CoreL10n.bundle)
      }
      if value == -1 {
        return String(
          localized: "recurrence.month_day.last", defaultValue: "last day",
          table: "Localizable", bundle: CoreL10n.bundle)
      }
      if value < 0 {
        let place = ordinal(-value)
        return String(
          localized: "recurrence.month_day.nth_last", defaultValue: "\(place)-to-last day",
          table: "Localizable", bundle: CoreL10n.bundle)
      }
      let number = value.formatted(.number.locale(locale))
      return String(
        localized: "recurrence.month_day.number", defaultValue: "day \(number)",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
    return names.formatted(.list(type: .and, width: .narrow).locale(locale))
  }
}
