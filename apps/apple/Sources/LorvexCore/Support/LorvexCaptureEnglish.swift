import Foundation

extension LorvexCaptureVocabulary {
  /// English. A word needs a boundary of Latin letters and digits on both
  /// sides; an apostrophe counts as part of the word, so "today's" stays in
  /// the title.
  ///
  /// - Day: today, tonight, tomorrow (tmrw, tmr), the weekday names, "this"
  ///   or "next" with a weekday, next week, weekend, this weekend, "in 3
  ///   days"; a date: "Oct 5", "October 5th", "5 Oct", "5th of October",
  ///   "2026-10-05". A date without a year that has passed this year means
  ///   next year's. A weekday means the next such day, a full week ahead when
  ///   it names today. A weekday's three- or four-letter abbreviation ("sat",
  ///   "wed") counts only capitalized or after on / for / this / next / by,
  ///   since the short forms are also English words. A capitalized weekday
  ///   inside the line with no lead word ("Monday Morning Memo") is a name,
  ///   not a date. Tonight is an evening, so "tonight 8:00" is 8 PM.
  /// - Date range: "May 3-5", "May 3 - 5", "May 3 to 5", "May 3 through 5",
  ///   "May 3 to May 5", "May 3rd-5th", "3-5 May", "May 30 - June 2",
  ///   "2026-10-03 to 2026-10-05", each maybe after "from", and "between May 3
  ///   and May 5". The first day is the planned day and the last the due day,
  ///   so another day phrase stays in the title. A month written once serves
  ///   both sides; the end must be after the start ("May 5-3" stays in the
  ///   title whole); an end in an earlier month falls in the next year ("Dec
  ///   30 - Jan 2"); a year at the end of a side counts ("May 3-5, 2027"). A
  ///   range with no month ("3-5", "the 3rd to the 5th") is not a date, and
  ///   nor is one whose end is followed by AM or PM ("May 3-5pm" is a time
  ///   range) or by a length unit ("Oct 5 - 30 min"). A day alone opens a
  ///   range joined by a dash only when the dash touches both sides ("3-5
  ///   May") or "from" comes first: "Sprint 12 - 20 May" names a sprint and a
  ///   date.
  /// - Repeat: every day, every weekday, every week, every other week, every
  ///   3 days, every month, every year, every Monday, every Mon and Thu,
  ///   every other Friday, and daily / weekly / monthly / yearly at the end of
  ///   the line ("Weekly review" stays a title).
  /// - Due: "by" or "due" before a day.
  /// - Time: "3pm", "3:30 pm", "at 15:30", "noon", "at midnight". A time with
  ///   no AM or PM from 1 to 6 o'clock is the afternoon. Midnight ends the day
  ///   it is named with. A range ("3-4pm", "11am to 1pm", "from 9am until
  ///   noon", "15:00–16:30", "10pm-midnight") is read when one side has AM,
  ///   PM, a colon, noon, or midnight, since "3-4" alone is as often a count.
  /// - Length: "20 min", "1.5h", "20m", "1h30m", "half an hour".
  /// - Priority: "!" to "!!!", p1 to p3, "high priority", "low priority", and
  ///   "urgent" at the end of the line or opening it before a colon or comma.
  static let english = englishVocabulary(readsHoursWithH: true)

  /// English for a line also read in a language that writes a clock time
  /// with the letter h (French, Portuguese, German, and Vietnamese "15h",
  /// "15h30"): an hour count written with h ("2h", "1.5h", "1h30m") is left to
  /// that language, which reads it as a time or a length by the words around
  /// it. Every other word reads as in ``english``.
  static let englishBesideHourClock = englishVocabulary(readsHoursWithH: false)

  private static func englishVocabulary(readsHoursWithH: Bool) -> LorvexCaptureVocabulary {
    LorvexCaptureVocabulary(
      priority: [Rule(pattern: englishPriorityPattern, read: englishPriority)],
      dateRange: [Rule(pattern: englishDateRangePattern, read: englishDateRange)],
      length: [Rule(pattern: englishLengthPattern) { englishLength($0, readsHoursWithH: readsHoursWithH) }],
      time: [
        Rule(pattern: englishRangePattern, read: englishRange),
        Rule(pattern: englishTimePattern, read: englishTime),
      ],
      repeats: [Rule(pattern: englishRepeatPattern, read: englishRepeat)],
      due: [Rule(pattern: #"\#(latinStart)(?:by|due)\s+(\#(englishDayPattern))\#(latinEnd)"#, read: englishDue)],
      when: [
        Rule(pattern: #"\#(latinStart)(?:(on|for|this|next)\s+)?(\#(englishDayPattern))\#(latinEnd)"#, read: englishWhen)
      ])
  }

  // MARK: - Priority

  /// Groups: 1 a written priority; "!" and "urgent" have no group.
  private static let englishPriorityPattern =
    #"\#(latinStart)(high priority|low priority|p[1-3])\#(latinEnd)|(?<!\S)(!{1,3})(?!\S)|(?<=\s)urgent(?=\s*$)|^\s*urgent(?=\s*[:,，：])"#

  private static func englishPriority(_ match: Match) -> LorvexTask.Priority? {
    switch match.group(1)?.lowercased() {
    case "low priority", "p3": .p3
    case "p2": .p2
    default: .p1
    }
  }

  // MARK: - Length

  /// "1h30m", "20 min", "1.5h", "20m", "half an hour", each optionally after
  /// "for". Groups: 1 and 2 the hours and minutes of "1h30m"; 3 an amount,
  /// with its unit in 4 (a word) or 5 (a letter); 6 half an hour.
  private static let englishLengthPattern =
    #"(?<![\p{Latin}\p{N}.])(?:for\s+)?(?:(\d+)\s*h\s*(\d+)\s*m(?:in)?|(\d+(?:\.\d+)?)(?:\s*(minutes|minute|mins|min|hours|hour|hrs|hr)|(m|h)))(?![\p{Latin}\p{N}])|(?<![\p{Latin}\p{N}])(?:for\s+)?(half an hour)(?![\p{Latin}\p{N}])"#

  /// The length a match names. Without `readsHoursWithH`, an hour count
  /// written with the letter h ("2h", "1h30m") names none.
  private static func englishLength(_ match: Match, readsHoursWithH: Bool) -> Int? {
    if let hours = match.group(1).flatMap(number), let rest = match.group(2).flatMap(number) {
      return readsHoursWithH ? taskLength(minutes: hours * 60 + rest) : nil
    }
    if let amount = match.group(3).flatMap(boundedDecimal),
      let unit = (match.group(4) ?? match.group(5))?.lowercased()
    {
      if !readsHoursWithH, match.group(5)?.lowercased() == "h" { return nil }
      return taskLength(minutes: Int((unit.hasPrefix("h") ? amount * 60 : amount).rounded()))
    }
    return match.group(6) == nil ? nil : 30
  }

  // MARK: - Time

  /// "3pm", "3:30 pm", "at 15:30", "noon", each optionally after "at" or
  /// "@", and "at midnight" ("Midnight" alone is as often a name). Groups: 1
  /// hour, 2 minute, 3 meridiem; 4 and 5 a colon time's hour and minute; 6
  /// noon; 7 midnight. `\d` matches the digits of every script, where a digit
  /// range such as `[0-5]` would match only ASCII, so the minute's range is
  /// checked in code.
  private static let englishTimePattern =
    #"(?<![\p{Latin}\p{N}:])(?:(?:(?:at|@)\s*)?(?:(\d{1,2})(?::(\d\d))?\s*([ap]\.?m\.?)|(?<!\d)(\d{1,2}):(\d\d)|(noon))|(?:at|@)\s*(midnight))(?![\p{Latin}\p{N}:])"#

  private static func englishTime(_ match: Match) -> ClockTime? {
    if match.group(6) != nil { return ClockTime(minutes: 12 * 60) }
    if match.group(7) != nil { return ClockTime(minutes: 0, isAfterMidnight: true) }
    if let hour = match.group(1).flatMap(number), let meridiem = match.group(3)?.lowercased() {
      let minute = match.group(2).flatMap(number) ?? 0
      guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
      let isPM = meridiem.hasPrefix("p")
      return ClockTime(minutes: ((hour % 12) + (isPM ? 12 : 0)) * 60 + minute)
    }
    guard let hourText = match.group(4), let hour = number(hourText), let minute = match.group(5).flatMap(number)
    else { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  // MARK: - Time range

  /// "3-4pm", "3pm to 4:30pm", "from 9am until noon", "15:00–16:30",
  /// "10pm-midnight", each optionally after "from", "at", or "@". Groups: 1
  /// the start, 2 the end.
  private static let englishRangePattern =
    #"(?<![\p{Latin}\p{N}:])(?:(?:from|at)\s+|@\s*)?(\#(englishRangeSide))\s*(?:-|–|—|to|until|till)\s*(\#(englishRangeSide))(?![\p{Latin}\p{N}:])"#

  /// One side of a range: an hour, maybe with minutes and AM or PM; noon;
  /// midnight.
  private static let englishRangeSide = #"\d{1,2}(?::\d\d)?(?:\s*[ap]\.?m\.?)?|noon|midnight"#

  private static func englishRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(1), let endText = match.group(2),
      // A side that is not only digits has AM, PM, a colon, noon, or midnight.
      [startText, endText].contains(where: { !$0.allSatisfy(\.isNumber) }),
      let start = englishRangeSideTime(startText, in: match), let end = englishRangeSideTime(endText, in: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  private static func englishRangeSideTime(_ text: String, in match: Match) -> ClockTime? {
    if let hour = number(text) { return bareTime(hour: hour, minute: 0, hasLeadingZero: startsWithZero(text)) }
    if text.lowercased() == "midnight" { return ClockTime(minutes: 0, isAfterMidnight: true) }
    return wholeTime(text, pattern: englishTimePattern, in: match, read: englishTime)
  }

  // MARK: - Date range

  /// "May 3-5", "May 3 to May 5", "May 30 - June 2", "3-5 May", "5th of May to
  /// 7th of May", "2026-10-03 to 2026-10-05", each maybe after "from" or
  /// "between" and with a year after a side. A side written as a day alone
  /// ("5" of "May 3-5", "3" of "3-5 May") takes the other side's month.
  /// Groups: 1 from or between, 2 the start, 3 the word between the sides
  /// (nil for a dash), 4 the end. The end may not be followed by AM or PM,
  /// which makes "May 3-5pm" a time range, by a unit, which makes "Oct 5 - 30
  /// min" a date and a length, or by a percent sign, a decimal fraction, or
  /// another dash-joined number, which make it a different number.
  private static var englishDateRangePattern: String {
    let day = #"\d{1,2}(?:st|nd|rd|th)?"#
    let year = #"(?:,?\s+\d{4})?"#
    let iso = #"\d{4}-\d{2}-\d{2}"#
    let monthFirst = "(?:\(englishMonthNames))\\.?\\s+\(day)(?![\\p{N}:])\(year)"
    let dayFirst = "\(day)\\s+(?:of\\s+)?(?:\(englishMonthNames))\\.?\(year)"
    let dayOnly = "\(day)(?![\\p{N}:])\(year)"
    let side = "\(iso)|\(monthFirst)|\(dayFirst)|\(dayOnly)"
    let unit = #"(?!\s*(?:hours?|hrs?|h|minutes?|mins?|m)(?![\p{Latin}\p{N}]))"#
    let noNumberAfter = #"(?![%]|[.,]\p{N}|[-–—]\p{N})"#
    return
      #"\#(latinStart)(?:(from|between)\s+)?(\#(side))(?:\s*[-–—]\s*|\s+(to|through|thru|until|till|and)\s+)(\#(side))\#(latinEnd)\#(noMeridiemAfter)\#(unit)\#(noNumberAfter)"#
  }

  private static func englishDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(4),
      let start = englishRangeDate(startText), let end = englishRangeDate(endText)
    else { return nil }
    // "And" joins two days only after "between": "May 3 and May 5" names two.
    if match.group(3)?.lowercased() == "and", match.group(1)?.lowercased() != "between" { return nil }
    if start.month == nil, match.group(1) == nil, match.group(3) == nil, !dashTouchesBothSides(match, start: 2, end: 4) {
      return nil
    }
    // A side without a month takes the other side's, so the other side needs
    // one, and the day alone stands where the month is written around it: at
    // the start of "3-5 May", at the end of "May 3-5".
    switch (start.month, end.month) {
    case (nil, nil): return nil
    case (nil, _): guard endText.first?.isNumber == true, start.year == nil else { return nil }
    case (_, nil): guard startText.first?.isLetter == true else { return nil }
    default: break
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("May 3", "3rd of May, 2027"), or a day
  /// alone ("5th"), which has no month.
  private static func englishRangeDate(_ text: String) -> ExplicitDate? {
    let lower = text.lowercased()
    if let date = englishDate(lower) { return date }
    guard let match = lower.wholeMatch(of: /(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?/), let day = number(match.output.1)
    else { return nil }
    return ExplicitDate(year: match.output.2.flatMap { number($0) }, month: nil, day: day)
  }

  // MARK: - Repeat

  /// "every other week", "every 3 days", "every Mon and Thu", or a cadence
  /// adverb at the end of the line. Groups: 1 other, 2 count, 3 unit or
  /// weekdays, 4 adverb.
  private static var englishRepeatPattern: String {
    let names = englishWeekdays.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    let days = "(?:\(names))(?:\\s*(?:,|and|&)\\s*(?:\(names)))*"
    return "\(latinStart)every\\s+(other\\s+)?(?:(\\d{1,2})\\s+)?(days?|weekdays?|weeks?|months?|years?|\(days))\(latinEnd)"
      + "|\(latinStart)(daily|weekly|monthly|yearly|annually)(?=\\s*$)"
  }

  private static func englishRepeat(_ match: Match) -> Repeat? {
    if let adverb = match.group(4)?.lowercased() {
      switch adverb {
      case "daily": return Repeat(rule: TaskRecurrenceRule(freq: .daily))
      case "weekly": return Repeat(rule: TaskRecurrenceRule(freq: .weekly))
      case "monthly": return Repeat(rule: TaskRecurrenceRule(freq: .monthly))
      default: return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      }
    }
    guard let unit = match.group(3)?.lowercased() else { return nil }
    var interval = match.group(2).flatMap(number) ?? 1
    if match.group(1) != nil { interval *= 2 }
    guard (1...99).contains(interval) else { return nil }
    let every = interval == 1 ? nil : interval
    switch unit {
    case "day", "days": return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "weekday", "weekdays": return workdays
    case "week", "weeks": return Repeat(rule: TaskRecurrenceRule(freq: .weekly, interval: every))
    case "month", "months": return Repeat(rule: TaskRecurrenceRule(freq: .monthly, interval: every))
    case "year", "years": return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default:
      let days = unit.split { !$0.isLetter }.map(String.init).compactMap(englishWeekdayIndex)
      return days.isEmpty ? nil : weekly(every: every, on: days)
    }
  }

  // MARK: - Days

  private static func englishDue(_ match: Match) -> Day? {
    match.group(1)
      .flatMap { englishDayOffset($0, todayWeekday: match.todayWeekday, today: match.today) }
      .map { Day(offset: $0) }
  }

  /// Groups: 1 the lead word (on, for, this, next), 2 the day.
  private static func englishWhen(_ match: Match) -> Day? {
    guard let word = match.group(2),
      var offset = englishDayOffset(word, todayWeekday: match.todayWeekday, today: match.today)
    else { return nil }
    let lead = match.group(1)?.lowercased()
    if lead == nil, let weekday = englishWeekdayIndex(word) {
      let isCapitalized = word.first?.isUppercase == true
      // The short forms are English words ("sat", "wed"), so alone they
      // count only capitalized.
      if word.lowercased() != englishWeekdays[weekday][0], !isCapitalized { return nil }
      // A capitalized weekday inside the line is a name ("Monday Morning
      // Memo") unless it ends the line.
      if isCapitalized, let end = Range(match.result.range, in: match.source)?.upperBound,
        !match.source[end...].trimmingCharacters(in: .whitespaces).isEmpty
      {
        return nil
      }
    }
    if let weekday = englishWeekdayIndex(word) {
      if lead == "this" { offset = weekdayDelta(weekday, todayWeekday: match.todayWeekday) }
      if lead == "next", offset < 7 { offset += 7 }
    }
    return Day(offset: offset, isEvening: word.lowercased() == "tonight")
  }

  /// Each weekday's names, full name first, Sunday first.
  private static let englishWeekdays = [
    ["sunday", "sun"], ["monday", "mon"], ["tuesday", "tue", "tues"], ["wednesday", "wed"],
    ["thursday", "thu", "thur", "thurs"], ["friday", "fri"], ["saturday", "sat"],
  ]

  /// Each month's names, full name first, January first.
  private static let englishMonths = [
    ["january", "jan"], ["february", "feb"], ["march", "mar"], ["april", "apr"], ["may"],
    ["june", "jun"], ["july", "jul"], ["august", "aug"], ["september", "sept", "sep"],
    ["october", "oct"], ["november", "nov"], ["december", "dec"],
  ]

  private static var englishDayPattern: String {
    let names = englishWeekdays.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    return #"today|tonight|tomorrow|tmrw|tmr|next week|this weekend|weekend|in\s+\d{1,3}\s+days?|"#
      + #"\d{4}-\d{2}-\d{2}|"# + englishMonthDayPattern + "|" + names
  }

  /// The month names and abbreviations, longest first, as a pattern.
  private static var englishMonthNames: String {
    englishMonths.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
  }

  /// "Oct 5", "October 5th, 2027", "5 Oct", "5th of October".
  private static var englishMonthDayPattern: String {
    let day = #"\d{1,2}(?:st|nd|rd|th)?"#
    let year = #"(?:,?\s+\d{4})?"#
    return "(?:\(englishMonthNames))\\.?\\s+\(day)(?![\\p{N}:])\(year)|\(day)\\s+(?:of\\s+)?(?:\(englishMonthNames))\(year)"
  }

  private static func englishWeekdayIndex(_ word: String) -> Int? {
    let lower = word.lowercased()
    return englishWeekdays.firstIndex { $0.contains(lower) }
  }

  private static func englishDayOffset(_ word: String, todayWeekday: Int, today: Date?) -> Int? {
    let lower = word.lowercased()
    if let date = englishDate(lower) {
      guard let today else { return nil }
      return offset(to: date, from: today)
    }
    switch lower {
    case "today", "tonight": return 0
    case "tomorrow", "tmrw", "tmr": return 1
    case "next week": return 7
    case "weekend", "this weekend": return weekendOffset(todayWeekday: todayWeekday)
    default: break
    }
    if let days = lower.firstMatch(of: /in\s+(\d{1,3})\s+days?/)?.output.1, let count = number(days) {
      return count
    }
    return englishWeekdayIndex(word).map { comingWeekdayOffset($0, todayWeekday: todayWeekday) }
  }

  /// "2026-10-05", or a month name with a day and maybe a year.
  private static func englishDate(_ word: String) -> ExplicitDate? {
    if let match = word.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
      return ExplicitDate(year: number(match.output.1), month: number(match.output.2), day: number(match.output.3) ?? 0)
    }
    let words = word.split { !$0.isLetter }.map(String.init)
    let numbers = word.matches(of: /\d+/).compactMap { number($0.output) }
    guard let month = englishMonths.firstIndex(where: { names in words.contains { names.contains($0) } }),
      let day = numbers.first
    else { return nil }
    return ExplicitDate(year: numbers.count > 1 ? numbers[1] : nil, month: month + 1, day: day)
  }
}
