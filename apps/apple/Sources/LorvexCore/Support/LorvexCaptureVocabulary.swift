import Foundation

/// One language's words for a capture line: for each kind of detail a line
/// can name, the patterns that recognize it and what each recognized phrase
/// means.
///
/// ``LorvexCaptureParser`` reads a line one kind of detail at a time and, for
/// each kind, tries the rules of every vocabulary ``vocabularies(for:)``
/// picks, in its order. A rule's pattern is matched case-insensitively
/// against the line without the phrases already recognized, in the
/// vocabulary's ``readingForm``. The rule's reader turns one match into a
/// value, or returns nil to leave the match in the title.
struct LorvexCaptureVocabulary: Sendable {
  /// The line as this vocabulary's patterns read it: the typed line, or for
  /// Chinese the line with Traditional characters read as Simplified ones
  /// (``simplifiedForMatching(_:)``). It must keep every character at its
  /// UTF-16 offset, so a match range in it is the same range in the typed
  /// line.
  var readingForm: @Sendable (String) -> String = { $0 }
  /// High (p1), medium (p2), or low (p3) priority.
  var priority: [Rule<LorvexTask.Priority>] = []
  /// A length in minutes, from 1 minute to 24 hours.
  var length: [Rule<Int>] = []
  /// A clock time.
  var time: [Rule<ClockTime>] = []
  /// How the task repeats.
  var repeats: [Rule<Repeat>] = []
  /// The day the task is due.
  var due: [Rule<Day>] = []
  /// The day the task is planned for.
  var when: [Rule<Day>] = []

  /// The vocabularies a line is read with for a user who reads `languages`
  /// (BCP 47 codes such as "ja-JP"), in the order each kind of detail tries
  /// them: Japanese and Korean when `languages` includes them, then Chinese
  /// and English, which every line is read with.
  ///
  /// The order settles a phrase two vocabularies could both read. Japanese
  /// goes before Chinese, so a date the two write alike is taken with its
  /// Japanese particle ("10月5日に"). Every other language goes before
  /// English, so a part of the day written before a clock time ("下午3:30",
  /// "오후 3:30") is read with the time instead of being left in the title
  /// when the English pattern takes "3:30".
  static func vocabularies(for languages: [String]) -> [LorvexCaptureVocabulary] {
    let codes = Set(languages.compactMap { $0.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased() })
    var vocabularies: [LorvexCaptureVocabulary] = []
    if codes.contains("ja") { vocabularies.append(.japanese) }
    if codes.contains("ko") { vocabularies.append(.korean) }
    return vocabularies + [.chinese, .english]
  }
}

extension LorvexCaptureVocabulary {
  /// One pattern and what its matches mean.
  struct Rule<Value>: Sendable {
    var pattern: String
    /// The value one match names, or nil when the match is not that detail
    /// after all ("Monday Morning Memo" names no day).
    var read: @Sendable (Match) -> Value?
  }

  /// One match of a rule's pattern, with what a reader needs to judge it.
  struct Match {
    var result: NSTextCheckingResult
    /// The line as the parser reads it, whose UTF-16 offsets the match's
    /// ranges are.
    var source: String
    /// The logical today's weekday, 1 = Sunday … 7 = Saturday (the Gregorian
    /// `Calendar` convention).
    var todayWeekday: Int
    /// The UTC midnight of the logical today, when the caller gave the day;
    /// written-out dates are read only with it.
    var today: Date?

    /// The text of capture group `index`, or nil when the group took no part
    /// in the match.
    func group(_ index: Int) -> String? {
      let range = result.range(at: index)
      guard range.location != NSNotFound, let bounds = Range(range, in: source) else { return nil }
      return String(source[bounds])
    }
  }

  /// A day a phrase names.
  struct Day {
    /// Days after the logical today.
    var offset: Int
    /// True for the evening of a day ("tonight", 今晚), which puts a clock
    /// time written without AM, PM, or a part of the day in that evening.
    var isEvening = false
  }

  /// A repeat a phrase names.
  struct Repeat {
    var rule: TaskRecurrenceRule
    /// The weekdays the rule names, 0 = Sunday, which fix its first
    /// occurrence.
    var weekdays: [Int] = []
    /// The day of the month the rule names, which fixes its first occurrence.
    var monthDay: Int?
  }

  /// A clock time a line named.
  struct ClockTime {
    /// Minutes since midnight on the day the time falls on.
    var minutes: Int
    /// For a time written with no AM, PM, or part of day, the hour as
    /// written, before a 1 to 6 o'clock moves to the afternoon; nil otherwise.
    var writtenHour: Int?
    /// True when the time falls after the midnight that ends the named day
    /// ("晚上12点", "半夜1点", "at midnight"), so it is on the next day.
    var isAfterMidnight = false
    /// For a range ("3-4pm", 下午3点到5点), the minutes from this time to the
    /// range's end; nil for a single time.
    var length: Int?
  }
}

// MARK: - Shared by the vocabularies

extension LorvexCaptureVocabulary {
  /// A word boundary for words written in Latin letters: no Latin letter,
  /// digit, or apostrophe on that side, so "today's" is one word.
  static let latinStart = #"(?<![\p{Latin}\p{N}'’])"#
  static let latinEnd = #"(?![\p{Latin}\p{N}'’])"#

  /// RFC 5545 weekday codes, Sunday first.
  static let weekdayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

  /// Every Monday to Friday, starting on the next of them.
  static var workdays: Repeat {
    Repeat(rule: TaskRecurrenceRule(freq: .weekly, byDay: Array(weekdayCodes[1...5])), weekdays: Array(1...5))
  }

  /// Every `interval` weeks (nil for every week), on `days` (0 = Sunday) when
  /// it names any.
  static func weekly(every interval: Int?, on days: [Int]) -> Repeat {
    let unique = Array(Set(days)).sorted()
    return Repeat(
      rule: TaskRecurrenceRule(
        freq: .weekly, interval: interval, byDay: unique.isEmpty ? nil : unique.map { weekdayCodes[$0] }),
      weekdays: unique)
  }

  /// Every `interval` months (nil for every month), on `day` of the month
  /// when one is named; nil for a day of the month past 31.
  static func monthly(every interval: Int?, on day: Int?) -> Repeat? {
    if let day, !(1...31).contains(day) { return nil }
    return Repeat(
      rule: TaskRecurrenceRule(freq: .monthly, interval: interval, byMonthDay: day.map { [$0] }), monthDay: day)
  }

  /// The whole number a matched run of digits spells. The patterns' `\d`
  /// matches the decimal digits of every script (a full-width "３" from a
  /// Chinese input method, an Arabic-Indic "٣"), which `Int(_:)` cannot read.
  static func number(_ text: some StringProtocol) -> Int? {
    LorvexNumberInput.integer(from: text)
  }

  /// The value of a numeral written in Han characters, from 0 to 59, as
  /// Chinese and Japanese write them: 三, 十, 十二, 二十, 四十五, 两.
  static func hanNumber(_ text: String) -> Int? {
    let digits: [Character: Int] = [
      "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    let characters = Array(text)
    guard let tenIndex = characters.firstIndex(of: "十") else {
      return characters.count == 1 ? digits[characters[0]] : nil
    }
    let tens = tenIndex == 0 ? 1 : (tenIndex == 1 ? digits[characters[0]] : nil)
    let rest = characters[(tenIndex + 1)...]
    guard let tens, rest.count <= 1 else { return nil }
    let ones = rest.first.map { digits[$0] } ?? 0
    guard let ones else { return nil }
    let value = tens * 10 + ones
    return value < 60 ? value : nil
  }

  /// `minutes` when it is a length a task can take, from 1 minute to 24
  /// hours.
  static func taskLength(minutes: Int) -> Int? {
    minutes > 0 && minutes <= 24 * 60 ? minutes : nil
  }

  /// Whether a written hour starts with a zero digit in any script ("09",
  /// "０９"), which marks it as a 24-hour time.
  static func startsWithZero(_ hourText: String) -> Bool {
    hourText.first.flatMap { number(String($0)) } == 0
  }

  /// A time written without AM, PM, or a part of day: from 1 to 6 o'clock it
  /// is the afternoon, since tasks are seldom planned before dawn, unless
  /// written with a leading zero ("06:30").
  static func bareTime(hour: Int, minute: Int, hasLeadingZero: Bool) -> ClockTime? {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    let shifted = !hasLeadingZero && (1...6).contains(hour) ? hour + 12 : hour
    return ClockTime(minutes: shifted * 60 + minute, writtenHour: hour)
  }

  /// A time in the night of the named day, which runs past midnight: 12
  /// o'clock (or 0 or 24) is the midnight that ends the day and 1 to 5
  /// o'clock the small hours after it, both on the next day; 6 to 11 o'clock
  /// is the evening; a 24-hour time from 13:00 stays as written.
  static func nightTime(hour: Int, minute: Int) -> ClockTime? {
    switch hour {
    case 0, 12, 24: ClockTime(minutes: minute, isAfterMidnight: true)
    case 1...5: ClockTime(minutes: hour * 60 + minute, isAfterMidnight: true)
    case 6...11: ClockTime(minutes: (hour + 12) * 60 + minute)
    case 13...23: ClockTime(minutes: hour * 60 + minute)
    default: nil
    }
  }

  /// The minutes since midnight an hour written without AM, PM, or a part of
  /// the day can mean: 3 is 3:00 or 15:00, 12 is 0:00 or 12:00, and 0 or an
  /// hour from 13 only itself.
  static func readings(ofHour hour: Int, minute: Int) -> [Int] {
    switch hour {
    case 1...12: [(hour % 12) * 60 + minute, (hour % 12 + 12) * 60 + minute]
    default: [hour * 60 + minute]
    }
  }

  /// The time a range names ("3-4pm", "下午3点到5点"): its start, with the
  /// length to its end, from both sides read as clock times.
  ///
  /// A side written without AM, PM, or a part of the day (one with a
  /// ``ClockTime/writtenHour``) takes the reading that fits the other side. A
  /// bare start is the latest reading of its hour before a written end:
  /// "3-4pm" starts at 15:00, "11-1pm" at 11:00. A bare end is the first
  /// reading of its hour after the start: "下午3点到5点" ends at 17:00,
  /// "晚上11点到1点" at 1:00 the next day. A written end at or before the start
  /// is on the next day. Nil when no reading fits or the range lasts a day or
  /// more.
  static func timeRange(from start: ClockTime, to end: ClockTime) -> ClockTime? {
    let day = 24 * 60
    let writtenEnd = end.minutes + (end.isAfterMidnight ? day : 0)
    var startMinutes = start.minutes
    if let hour = start.writtenHour, end.writtenHour == nil {
      guard let latest = readings(ofHour: hour, minute: start.minutes % 60).filter({ $0 < writtenEnd }).max()
      else { return nil }
      startMinutes = latest
    }
    var endMinutes = writtenEnd
    if let hour = end.writtenHour {
      let sameDay = readings(ofHour: hour, minute: end.minutes % 60)
      guard let first = (sameDay + sameDay.map { $0 + day }).filter({ $0 > startMinutes }).min() else { return nil }
      endMinutes = first
    } else if endMinutes <= startMinutes {
      endMinutes += day
    }
    let length = endMinutes - startMinutes
    guard (1..<day).contains(length) else { return nil }
    // A range with both sides bare stays bare, so "tonight 8:00-10:00" moves
    // to the evening like "tonight 8:00".
    let isBare = start.writtenHour != nil && end.writtenHour != nil
    return ClockTime(
      minutes: startMinutes, writtenHour: isBare ? start.writtenHour : nil, isAfterMidnight: start.isAfterMidnight,
      length: length)
  }

  /// The clock time all of `text` names under `pattern`, a time rule's
  /// pattern, as `read` reads it; nil unless the pattern matches the whole
  /// text. A range rule reads each of its sides with it.
  static func wholeTime(
    _ text: String, pattern: String, in match: Match, read: (Match) -> ClockTime?
  ) -> ClockTime? {
    guard let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: [.caseInsensitive]),
      let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return read(Match(result: result, source: text, todayWeekday: match.todayWeekday, today: match.today))
  }

  /// "15:30" or "15：30" with nothing around it, as a time written without AM,
  /// PM, or a part of the day.
  static func colonTime(_ text: String) -> ClockTime? {
    guard let match = text.wholeMatch(of: /(\d{1,2})[:：](\d{2})/), let hour = number(match.output.1),
      let minute = number(match.output.2)
    else { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(match.output.1)))
  }

  /// No AM or PM after a range: one written "3:00-4:00 pm" is left to the
  /// English range rule, which reads the PM.
  static let noMeridiemAfter = #"(?!\s*[ap]\.?m\.?(?!\p{Latin}))"#

  /// Days from today to the next `weekday` (0 = Sunday), 0 when it is today.
  static func weekdayDelta(_ weekday: Int, todayWeekday: Int) -> Int {
    (weekday + 1 - todayWeekday + 7) % 7
  }

  /// Days from today to the coming Saturday, or 0 on a Saturday or Sunday,
  /// when the weekend is already here.
  static func weekendOffset(todayWeekday: Int) -> Int {
    todayWeekday == 7 || todayWeekday == 1 ? 0 : 7 - todayWeekday
  }

  /// Days from today to `weekday` (0 = Sunday) of next week, weeks starting
  /// on Monday: on a Tuesday, next week's Wednesday is 8 days ahead and next
  /// week's Monday 6.
  static func nextWeekOffset(_ weekday: Int, todayWeekday: Int) -> Int {
    let todayFromMonday = (todayWeekday + 5) % 7
    let weekdayFromMonday = (weekday + 6) % 7
    return 7 - todayFromMonday + weekdayFromMonday
  }

  /// Days from today to the next `weekday` (0 = Sunday) when a weekday is
  /// named alone: a full week ahead when it names today.
  static func comingWeekdayOffset(_ weekday: Int, todayWeekday: Int) -> Int {
    let delta = weekdayDelta(weekday, todayWeekday: todayWeekday)
    return delta == 0 ? 7 : delta
  }

  /// A written-out date: year (nil when not written), month (nil for a day
  /// of the month alone, such as "5号"), and day.
  struct ExplicitDate {
    var year: Int?
    var month: Int?
    var day: Int
  }

  /// Days from `today`, a UTC midnight, to `date`: a date without a year is
  /// this year's, or next year's once passed; a date without a month is this
  /// month's, or next month's once passed. Nil for a day the calendar lacks,
  /// a written year's date in the past, or one more than ten years ahead.
  static func offset(to date: ExplicitDate, from today: Date) -> Int? {
    let calendar = utcCalendar
    let now = calendar.dateComponents([.year, .month, .day], from: today)
    guard let thisYear = now.year, let thisMonth = now.month else { return nil }
    func days(year: Int, month: Int) -> Int? {
      let components = DateComponents(year: year, month: month, day: date.day)
      guard let target = calendar.date(from: components),
        calendar.component(.day, from: target) == date.day
      else { return nil }
      return calendar.dateComponents([.day], from: today, to: target).day
    }
    let result: Int?
    if let month = date.month {
      if let year = date.year {
        result = days(year: year, month: month)
      } else if let current = days(year: thisYear, month: month), current >= 0 {
        result = current
      } else {
        result = days(year: thisYear + 1, month: month)
      }
    } else if let current = days(year: thisYear, month: thisMonth), current >= 0 {
      result = current
    } else {
      result = thisMonth == 12 ? days(year: thisYear + 1, month: 1) : days(year: thisYear, month: thisMonth + 1)
    }
    guard let result, (0...3650).contains(result) else { return nil }
    return result
  }

  /// The Gregorian calendar in UTC, in which the logical today and written
  /// dates are counted as whole days.
  static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }
}
