import Foundation

extension LorvexCaptureVocabulary {
  // The Russian range rules, which read "с 3 по 5 мая" and "с 14 до 16", and the
  // rule that keeps a deadline written as a clock time in the title. The
  // vocabulary's other words are in ``russian``.

  /// "с 3 по 5 мая", "с 3 до 5 мая", "от 3 до 5 мая", "с 30 мая по 2 июня", "3-5
  /// мая", "3–5 мая", each maybe with a year after the end. The start is a date
  /// or a day alone ("3"); the end is a date. Groups: 1 the word that opens the
  /// range, if any (с, со, от), 2 the start, 3 a dash between the sides, 4 по
  /// or до between them, 5 the end.
  static var russianDateRangePattern: String {
    let bare = #"\d{1,2}(?:-?го)?\#(cyrillicNoMoreDigits)"#
    return
      #"\#(cyrillicStart)(?:(с|со|от)\s+)?(\#(russianMonthDatePattern)|\#(bare))(?:\s*([-–—])\s*|\s+(по|до)\s+)(\#(russianMonthDatePattern)|\#(bare))\#(cyrillicDateEnd)"#
  }

  static func russianDateRange(_ match: Match) -> DayRangeReading? {
    slavicDateRange(match, side: russianRangeDate)
  }

  /// A side of a date range: a date ("5 мая") or a day alone ("5"), which has
  /// no month.
  private static func russianRangeDate(_ text: String) -> ExplicitDate? {
    let words = normalizedPhrase(text)
    if let date = russianDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})(?: го)?/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  /// "с 14 до 16", "от 14 до 16", "с 14:00 до 16:00", "с 9 утра до 6 вечера",
  /// "с 2 до 4 дня", "с 10 до 12 часов", and with a dash: "с 14:00-16:00", "в
  /// 14:00-16:00". A range with a dash and no word before it ("14:00-16:00")
  /// is left to English. Groups: 1 the word before the range (с, со, от, в,
  /// во), 2 the start, 3 the part of the day after it, 4 до or a dash between
  /// the sides, 5 the end, 6 the part of the day after it, 7 the word for hour
  /// after the end.
  static let russianTimeRangePattern =
    #"\#(cyrillicStart)(с|со|от|в|во)\s+(\d{1,2}(?:[:.]\d{2})?)(?:\s+(утра|дня|вечера|ночи))?(\s+до\s+|\s*[-–—]\s*)(\d{1,2}(?:[:.]\d{2})?)(?:\s+(утра|дня|вечера|ночи))?(?:\s+(часов|часа|час|ч))?\#(cyrillicTimeEnd)"#

  static func russianTimeRange(_ match: Match) -> ClockTime? {
    guard let lead = match.group(1).map(normalizedPhrase), let connector = match.group(4),
      let startText = match.group(2), let endText = match.group(5),
      let start = russianRangeSide(startText, part: match.group(3)),
      let end = russianRangeSide(endText, part: match.group(6))
    else { return nil }
    // "До" joins the sides only after с, со, or от: "в 14 до 16" is no range.
    if connector.contains(where: \.isLetter), lead == "в" || lead == "во" { return nil }
    // Two bare hours are as often an amount or a span of numbered items: they
    // are a range only when no counted noun follows ("с 14 до 16 страниц") and
    // no word that names what is counted comes before ("Цена от 10 до 20",
    // "Прочитать главы с 3 до 5").
    let isBare = [startText, endText].allSatisfy { $0.allSatisfy(\.isNumber) }
    let hasWord = match.group(3) != nil || match.group(6) != nil || match.group(7) != nil
    if isBare, !hasWord {
      if !russianFollowsAsDetail(match) { return nil }
      if let before = wordBefore(match), russianCountedWords.contains(before) { return nil }
    }
    return timeRange(from: start, to: end)
  }

  /// Words that name an amount or numbered items, which a range of two bare
  /// numbers after them counts ("Цена от 10 до 20", "главы с 3 до 5"). Words
  /// that also name a time of day are left out: "уроки с 9 до 14" are school
  /// hours.
  private static let russianCountedWords: Set<String> = [
    "цена", "цену", "цены", "стоимость", "бюджет", "скидка", "скидку", "скидки", "зарплата", "зарплату",
    "оклад", "сумма", "сумму", "возраст", "вес", "рост", "размер", "тираж", "количество", "оценка",
    "оценку", "температура", "главы", "главу", "страницы", "задания", "упражнения", "пункты", "билеты",
    "вопросы", "номера", "серии", "параграфы", "слайды",
  ]

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one.
  private static func russianRangeSide(_ text: String, part: String?) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.2.flatMap { number($0) } ?? 0
    if let part {
      guard let kind = russianPartsOfDay[part.lowercased()] else { return nil }
      return partOfDayTime(hour: hour, minute: minute, part: kind)
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)))
  }

  /// A clock time written as a deadline ("до 18:00", "к 18:00", "не позднее
  /// 18:00"), which names no start time. Group 1 is the word before the time,
  /// or nil for a range ("с 14 до 18:00"), which the range rule reads and this
  /// rule only steps over, so the "до 18:00" inside it is not taken for a
  /// deadline.
  static let russianDeadlineClockPattern =
    #"\#(cyrillicStart)(?:(?:с|со|от)\s+\d{1,2}(?:[:.]\d{2})?(?:\s+(?:утра|дня|вечера|ночи))?\s+до\s+\d{1,2}:\d{2}|(до|к|ко|перед|после|не\s+позднее|не\s+позже)\s+\d{1,2}:\d{2})(?![\p{N}:]|[.,]\p{N})"#
}
