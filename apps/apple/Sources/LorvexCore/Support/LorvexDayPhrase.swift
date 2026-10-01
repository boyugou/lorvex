import Foundation

/// A stored calendar day named the way a sentence says it, relative to the
/// product's logical today.
///
/// Within a day of the logical today the phrase is "today", "tomorrow", or
/// "yesterday"; within the coming week it is the weekday ("Thursday");
/// otherwise it is the month and day, with the year only when it is not the
/// logical today's year ("Oct 12", "Jan 4, 2027").
///
/// Day-granular values (`planned_date`, `due_date`, `available_from`) are
/// stored as UTC midnights, and the logical today is the configured-timezone
/// day as a `yyyy-MM-dd` key. The phrase compares the two as day keys and
/// formats the day in UTC, so no device timezone moves it across a boundary.
public enum LorvexDayPhrase {
  /// Where the phrase sits in its sentence, which decides its capitalization.
  public enum Position: Sendable {
    /// Opens a sentence or stands alone as a label: "Today for 90 min", a
    /// "Tomorrow" chip.
    case leading
    /// Follows other words: "due today", "Hidden until tomorrow".
    case inline
  }

  /// The phrase for the stored day `date`.
  ///
  /// - Parameters:
  ///   - logicalDay: the product's logical today, `yyyy-MM-dd`. A value that
  ///     is not a day key leaves only the dated form, with its year.
  ///   - position: where the phrase sits. English capitalizes a relative day
  ///     only at the start ("Today", but "due today"); a weekday or a month
  ///     keeps its own capitalization.
  ///   - locale: the locale the weekday and the date are written in.
  public static func phrase(
    for date: Date, logicalDay: String, position: Position,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    let offset = lorvexDayOffset(from: logicalDay, to: date)
    switch offset {
    case 0: return today(position)
    case 1: return tomorrow(position)
    case -1: return yesterday(position)
    default:
      var style = Date.FormatStyle(
        locale: locale, calendar: locale.calendar, timeZone: .gmt,
        capitalizationContext: position == .leading ? .beginningOfSentence : .middleOfSentence)
      if let offset, (2...6).contains(offset) {
        return date.formatted(style.weekday(.wide))
      }
      style = style.month(.abbreviated).day()
      let sameYear =
        logicalDay.count == 10 && LorvexDateFormatters.ymdUTC.string(from: date).prefix(4) == logicalDay.prefix(4)
      return date.formatted(sameYear ? style : style.year())
    }
  }

  /// The due day as the word after "due" in a task's sentence, which opens
  /// with the planned day when the task has one.
  ///
  /// A due day that is also the planned day reads "the same day", because the
  /// sentence has just named it ("Today, due the same day"). A deadline that
  /// passed before yesterday carries how late it is ("Sep 20 · 9 days late"),
  /// since a date leaves the reader to count; "yesterday" already says so.
  ///
  /// - Parameters:
  ///   - due: the stored due day.
  ///   - plannedDay: the stored planned day, or `nil` when the task has none.
  ///   - logicalDay: the product's logical today, `yyyy-MM-dd`.
  ///   - locale: the locale a weekday or a date is written in.
  public static func due(
    _ due: Date, plannedDay: Date?, logicalDay: String,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    let isPlannedDay = plannedDay.map {
      LorvexDateFormatters.ymdUTC.string(from: $0) == LorvexDateFormatters.ymdUTC.string(from: due)
    } ?? false
    let day = isPlannedDay ? sameDay : phrase(for: due, logicalDay: logicalDay, position: .inline, locale: locale)
    guard let offset = lorvexDayOffset(from: logicalDay, to: due), offset < -1 else { return day }
    return "\(day) · \(daysLate(-offset))"
  }

  private static func today(_ position: Position) -> String {
    switch position {
    case .leading:
      String(localized: "day_phrase.today", defaultValue: "Today", table: "Localizable", bundle: CoreL10n.bundle)
    case .inline:
      String(localized: "day_phrase.today.inline", defaultValue: "today", table: "Localizable", bundle: CoreL10n.bundle)
    }
  }

  private static func tomorrow(_ position: Position) -> String {
    switch position {
    case .leading:
      String(localized: "day_phrase.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: CoreL10n.bundle)
    case .inline:
      String(
        localized: "day_phrase.tomorrow.inline", defaultValue: "tomorrow", table: "Localizable",
        bundle: CoreL10n.bundle)
    }
  }

  private static func yesterday(_ position: Position) -> String {
    switch position {
    case .leading:
      String(localized: "day_phrase.yesterday", defaultValue: "Yesterday", table: "Localizable", bundle: CoreL10n.bundle)
    case .inline:
      String(
        localized: "day_phrase.yesterday.inline", defaultValue: "yesterday", table: "Localizable",
        bundle: CoreL10n.bundle)
    }
  }

  private static var sameDay: String {
    String(
      localized: "day_phrase.same_day", defaultValue: "the same day", table: "Localizable",
      bundle: CoreL10n.bundle)
  }

  private static func daysLate(_ days: Int) -> String {
    String(
      localized: "day_phrase.days_late", defaultValue: "\(days) days late", table: "Localizable",
      bundle: CoreL10n.bundle)
  }
}

/// Whole days from the logical today to a stored day; negative when the day is
/// in the past. `nil` when `logicalDay` is not a parseable `yyyy-MM-dd`.
public func lorvexDayOffset(from logicalDay: String, to date: Date) -> Int? {
  guard let start = LorvexDateFormatters.ymdUTC.date(from: logicalDay) else { return nil }
  let day = LorvexDateFormatters.ymdUTC.string(from: date)
  guard let end = LorvexDateFormatters.ymdUTC.date(from: day) else { return nil }
  return Int((end.timeIntervalSince(start) / 86_400).rounded())
}
