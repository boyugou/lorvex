import Foundation

extension LorvexCaptureVocabulary {
  // The Ukrainian range rules, which read "з 3 по 5 травня" and "з 14 до 16", and
  // the rule that keeps a deadline written as a clock time in the title. The
  // vocabulary's other words are in ``ukrainian``.

  /// "з 3 по 5 травня", "з 3 до 5 травня", "від 3 до 5 травня", "з 30 травня по
  /// 2 червня", "3-5 травня", "3–5 травня", each maybe with a year after the
  /// end. The start is a date or a day alone ("3"); the end is a date. Groups:
  /// 1 the word that opens the range, if any (з, із, зі, від), 2 the start, 3 a
  /// dash between the sides, 4 по or до between them, 5 the end.
  static var ukrainianDateRangePattern: String {
    let bare = #"\d{1,2}(?:-?го)?\#(cyrillicNoMoreDigits)"#
    return
      #"\#(cyrillicStart)(?:(з|із|зі|від)\s+)?(\#(ukrainianMonthDatePattern)|\#(bare))(?:\s*([-–—])\s*|\s+(по|до)\s+)(\#(ukrainianMonthDatePattern)|\#(bare))\#(cyrillicDateEnd)"#
  }

  static func ukrainianDateRange(_ match: Match) -> DayRangeReading? {
    slavicDateRange(match, side: ukrainianRangeDate)
  }

  /// A side of a date range: a date ("5 травня") or a day alone ("5"), which
  /// has no month.
  private static func ukrainianRangeDate(_ text: String) -> ExplicitDate? {
    let words = normalizedPhrase(text)
    if let date = ukrainianDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})(?: го)?/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  /// "з 14 до 16", "від 14 до 16", "з 14:00 до 16:00", "з 9 ранку до 6 вечора",
  /// "з 2 до 4 дня", "з 10 до 12 годин", and with a dash: "з 14:00-16:00", "о
  /// 14:00-16:00". A range with a dash and no word before it ("14:00-16:00")
  /// is left to English. Groups: 1 the word before the range (з, із, зі, від,
  /// о, об, у, в), 2 the start, 3 the part of the day after it, 4 до or a dash
  /// between the sides, 5 the end, 6 the part of the day after it, 7 the word
  /// for hour after the end.
  static let ukrainianTimeRangePattern =
    #"\#(cyrillicStart)(з|із|зі|від|об|о|у|в)\s+(\d{1,2}(?:[:.]\d{2})?)(?:\s+(ранку|дня|вечора|ночі))?(\s+до\s+|\s*[-–—]\s*)(\d{1,2}(?:[:.]\d{2})?)(?:\s+(ранку|дня|вечора|ночі))?(?:\s+(годин|години|годину|година|год))?\#(cyrillicTimeEnd)"#

  static func ukrainianTimeRange(_ match: Match) -> ClockTime? {
    guard let lead = match.group(1).map(normalizedPhrase), let connector = match.group(4),
      let startText = match.group(2), let endText = match.group(5),
      let start = ukrainianRangeSide(startText, part: match.group(3)),
      let end = ukrainianRangeSide(endText, part: match.group(6))
    else { return nil }
    // "До" joins the sides only after з, із, зі, or від: "о 14 до 16" is no range.
    if connector.contains(where: \.isLetter), !["з", "із", "зі", "від"].contains(lead) { return nil }
    // Two bare hours are as often an amount or a span of numbered items: they
    // are a range only when no counted noun follows ("з 14 до 16 сторінок")
    // and no word that names what is counted comes before ("Ціна від 10 до
    // 20", "Прочитати розділи з 3 до 5").
    let isBare = [startText, endText].allSatisfy { $0.allSatisfy(\.isNumber) }
    let hasWord = match.group(3) != nil || match.group(6) != nil || match.group(7) != nil
    if isBare, !hasWord {
      if !ukrainianFollowsAsDetail(match) { return nil }
      if let before = wordBefore(match), ukrainianCountedWords.contains(before) { return nil }
    }
    return timeRange(from: start, to: end)
  }

  /// Words that name an amount or numbered items, which a range of two bare
  /// numbers after them counts ("Ціна від 10 до 20", "розділи з 3 до 5").
  /// Words that also name a time of day are left out: "уроки з 9 до 14" are
  /// school hours, and "завдання" is also one task.
  private static let ukrainianCountedWords: Set<String> = [
    "ціна", "ціну", "ціни", "вартість", "бюджет", "знижка", "знижку", "знижки", "зарплата", "зарплату",
    "оклад", "сума", "суму", "вік", "вага", "вагу", "зріст", "розмір", "наклад", "кількість", "оцінка",
    "оцінку", "температура", "розділи", "сторінки", "вправи", "пункти", "білети", "питання", "номери",
    "серії", "параграфи", "слайди",
  ]

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one.
  private static func ukrainianRangeSide(_ text: String, part: String?) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.2.flatMap { number($0) } ?? 0
    if let part {
      guard let kind = ukrainianPartsOfDay[part.lowercased()] else { return nil }
      return partOfDayTime(hour: hour, minute: minute, part: kind)
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)))
  }

  /// A clock time written as a deadline ("до 18:00", "перед 18:00", "не пізніше
  /// 18:00"), which names no start time. Group 1 is the word before the time,
  /// or nil for a range ("з 14 до 18:00"), which the range rule reads and this
  /// rule only steps over, so the "до 18:00" inside it is not taken for a
  /// deadline.
  static let ukrainianDeadlineClockPattern =
    #"\#(cyrillicStart)(?:(?:з|із|зі|від)\s+\d{1,2}(?:[:.]\d{2})?(?:\s+(?:ранку|дня|вечора|ночі))?\s+до\s+\d{1,2}:\d{2}|(до|перед|після|не\s+пізніше(?:\s+ніж)?|не\s+пізніш\s+як)\s+\d{1,2}:\d{2})(?![\p{N}:]|[.,]\p{N})"#
}
