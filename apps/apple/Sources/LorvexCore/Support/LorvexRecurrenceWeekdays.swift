import Foundation

/// The weekdays of a recurrence rule's `byDay`, named for display in the app's
/// language. A token is an RFC 5545 weekday code (`MO` through `SU`), led in a
/// monthly or yearly rule by an optional signed position within the month or
/// year: `1MO` is the first Monday, `-1FR` the last Friday.
///
/// Plain weekdays come first, in the order of the weekday picker, which starts
/// the week on the user's first weekday (``LorvexWeekdayOrder``); then
/// positioned weekdays by position, those counted from the end last. Each
/// reads as the calendar's short weekday name ("Mon"); a positioned one as
/// "1st Mon", "last Fri", or "2nd-to-last Fri", its position written as the
/// locale's ordinal number. The names are joined as the locale's narrow list
/// ("Mon, Wed, Fri", "lun, mié y vie", "周一、周三和周五"), whose separators and
/// conjunction belong to the language. A token that is not a weekday code is
/// kept as written, after the rest.
public enum LorvexRecurrenceWeekdays {
  public static func summary(
    _ tokens: [String],
    calendar: Calendar = LorvexDateFormatters.displayCalendar(timeZone: .autoupdatingCurrent),
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    let symbols = calendar.shortWeekdaySymbols
    let weekStart = LorvexWeekdayOrder.startIndex(of: calendar)
    var ordinals: NumberFormatter?
    func ordinal(_ position: Int) -> String {
      let formatter = ordinals ?? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter
      }()
      ordinals = formatter
      return formatter.string(from: NSNumber(value: position)) ?? String(position)
    }
    let names = tokens.enumerated()
      .map { Token($0.element, index: $0.offset, weekStart: weekStart) }
      .sorted { $0.sortKey.lexicographicallyPrecedes($1.sortKey) }
      .map { token -> String in
        guard let weekday = token.weekday, symbols.count == 7 else { return token.raw }
        // `shortWeekdaySymbols` starts on Sunday whatever the first weekday is.
        let day = symbols[(weekday + 1) % 7]
        switch token.position {
        case nil:
          return day
        case .some(-1):
          return String(
            localized: "recurrence.weekday.last", defaultValue: "last \(day)",
            table: "Localizable", bundle: CoreL10n.bundle)
        case let position? where position < 0:
          let place = ordinal(-position)
          return String(
            localized: "recurrence.weekday.nth_last", defaultValue: "\(place)-to-last \(day)",
            table: "Localizable", bundle: CoreL10n.bundle)
        case let position?:
          let place = ordinal(position)
          return String(
            localized: "recurrence.weekday.nth", defaultValue: "\(place) \(day)",
            table: "Localizable", bundle: CoreL10n.bundle)
        }
      }
    return names.formatted(.list(type: .and, width: .narrow).locale(locale))
  }

  /// The same summary for weekdays given as Monday-first indices (0 = Monday
  /// … 6 = Sunday), the form a habit's weekdays take. Indices outside 0…6 are
  /// skipped.
  public static func summary(
    mondayFirst weekdays: [Int],
    calendar: Calendar = LorvexDateFormatters.displayCalendar(timeZone: .autoupdatingCurrent),
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    let tokens = weekdays.filter { Token.codes.indices.contains($0) }.map { Token.codes[$0] }
    return summary(tokens, calendar: calendar, locale: locale)
  }

  /// One `byDay` token: its weekday as a Monday-first index, and its signed
  /// position (nil for a plain weekday). An unreadable token has no weekday.
  private struct Token {
    static let codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

    let raw: String
    let weekday: Int?
    let position: Int?
    /// Plain weekdays, then positions counted from the start, then from the
    /// end, then unreadable tokens; weekdays in the shown week's order, and
    /// ties in the order they were given in.
    let sortKey: [Int]

    init(_ raw: String, index: Int, weekStart: Int) {
      self.raw = raw
      let code = String(raw.suffix(2))
      let prefix = String(raw.dropLast(2))
      guard let weekday = Self.codes.firstIndex(of: code),
        prefix.isEmpty || Int(prefix).map({ $0 != 0 }) == true
      else {
        weekday = nil
        position = nil
        sortKey = [3, 0, 0, index]
        return
      }
      self.weekday = weekday
      position = prefix.isEmpty ? nil : Int(prefix)
      let place = LorvexWeekdayOrder.position(weekday, start: weekStart)
      switch position {
      case nil: sortKey = [0, 0, place, index]
      case let position? where position > 0: sortKey = [1, position, place, index]
      case let position?: sortKey = [2, -position, place, index]
      }
    }
  }
}
