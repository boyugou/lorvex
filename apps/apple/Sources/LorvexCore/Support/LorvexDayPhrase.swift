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
      let sameYear = sharesYear(date, withLogicalDay: logicalDay, in: locale.calendar)
      return date.formatted(sameYear ? style : style.year())
    }
  }

  /// Whether the stored day `date` falls in the logical today's year as
  /// `calendar` counts years: a Persian year turns at Nowruz in March, not on
  /// January 1. False when `logicalDay` is not a day key.
  private static func sharesYear(
    _ date: Date, withLogicalDay logicalDay: String, in calendar: Calendar
  ) -> Bool {
    guard let today = LorvexDateFormatters.ymdUTC.date(from: logicalDay) else { return false }
    var calendar = calendar
    calendar.timeZone = .gmt
    return calendar.isDate(date, equalTo: today, toGranularity: .year)
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

  /// Whether a task's planned day falls after a deadline that has not passed
  /// yet, so working on it that day would finish it late.
  ///
  /// False when either day is missing, when the planned day is on or before
  /// the deadline, and once the deadline has gone by: an overdue task's
  /// deadline already says how late it is, and planning it for today or later
  /// is the expected way to catch up, not a plan to warn about.
  ///
  /// - Parameters:
  ///   - planned: the stored planned day, or `nil`.
  ///   - due: the stored due day, or `nil`.
  ///   - logicalDay: the product's logical today, `yyyy-MM-dd`.
  public static func isPlannedAfterDeadline(planned: Date?, due: Date?, logicalDay: String) -> Bool {
    guard let planned, let due,
      let dueOffset = lorvexDayOffset(from: logicalDay, to: due), dueOffset >= 0,
      let plannedOffset = lorvexDayOffset(from: logicalDay, to: planned)
    else { return false }
    return plannedOffset > dueOffset
  }

  /// A planned day's phrase with the fact that it falls after the deadline
  /// ("Tomorrow · after the deadline"), for a planned day
  /// ``isPlannedAfterDeadline(planned:due:logicalDay:)`` flags. The fact
  /// keeps its words together, so a value too wide for its line wraps after
  /// the separator rather than inside the fact.
  public static func afterDeadline(_ plannedPhrase: String) -> String {
    let fact = String(
      localized: "day_phrase.after_deadline", defaultValue: "after the deadline", table: "Localizable",
      bundle: CoreL10n.bundle)
    return "\(plannedPhrase) · \(lorvexUnbreakable(fact))"
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
