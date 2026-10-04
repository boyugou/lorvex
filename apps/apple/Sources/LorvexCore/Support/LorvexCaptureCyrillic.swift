import Foundation

// What the Russian and Ukrainian vocabularies share: word boundaries and
// endings for Cyrillic text and the clock times a part of the day names. The
// readers of text that the Slavic vocabularies judge the same way (a
// capitalized name, the words of a list, a date range) serve Polish too, and
// the clock times of a part of the day and the date-range reader serve Arabic.

extension LorvexCaptureVocabulary {
  /// What may follow a clock time: no Cyrillic letter, digit, colon, or
  /// apostrophe (the word or the number goes on), no decimal fraction, no
  /// percent or currency sign, with or without a space before it (the number
  /// is an amount: "20%", "20 ₽", "20$"), and no dash before a digit, which
  /// makes the time one side of a range written with a dash ("14:00-16:00")
  /// that English reads whole.
  static let cyrillicTimeEnd = #"(?![\p{Cyrillic}\p{N}'\x{2019}\x{02BC}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d)"#

  /// What may follow a date: no Cyrillic letter, digit, colon, or apostrophe,
  /// and no decimal fraction.
  static let cyrillicDateEnd = #"(?![\p{Cyrillic}\p{N}'\x{2019}\x{02BC}:]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let cyrillicNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// `words` as the alternatives of a pattern, longest first and without
  /// repeats, so a word is never cut short by a shorter one that starts it.
  static func alternation(of words: [String]) -> String {
    let unique: [String] = Array(Set(words))
    let ordered = unique.sorted { (first: String, second: String) -> Bool in
      first.count != second.count ? first.count > second.count : first < second
    }
    return ordered.joined(separator: "|")
  }

  /// The part of the day written after an hour: "9 утра", "7 вечера", "2 ночи".
  enum PartOfDay {
    case morning, day, evening, night
  }

  /// The clock time `hour` (a 12-hour clock's) and `minute` name with a part
  /// of the day, or nil for an hour no one says with it.
  ///
  /// The morning is 1 to 11 o'clock (12 in the morning is read either way, so
  /// it is no time). The day is noon at 12 and the afternoon from 1 to 6. The
  /// evening is 1 to 11 o'clock and counts from noon (12 in the evening is
  /// read either way). The night is the midnight that ends the day at 12 (and
  /// at 0), the small hours after it from 1 to 5, and the evening at 10 and
  /// 11; the hours between are no one's night. A time past the midnight that
  /// ends its day is on the next day (``ClockTime/isAfterMidnight``).
  static func partOfDayTime(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    switch part {
    case .morning:
      return (1...11).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .day:
      if hour == 12 { return ClockTime(minutes: 12 * 60 + minute) }
      return (1...6).contains(hour) ? ClockTime(minutes: (hour + 12) * 60 + minute) : nil
    case .evening:
      return (1...11).contains(hour) ? ClockTime(minutes: (hour + 12) * 60 + minute) : nil
    case .night:
      return [0, 1, 2, 3, 4, 5, 10, 11, 12].contains(hour) ? nightTime(hour: hour, minute: minute) : nil
    }
  }

  /// Whether the line goes on after `match` with nothing, punctuation, a digit,
  /// or a word in `words` (minus `excluding`): the words that can follow a
  /// detail written with no unit of its own, such as a bare hour after "в".
  /// Any other word after the number makes it a count ("в 3 этапа"), so the
  /// number stays in the title.
  static func followsAsDetail(_ match: Match, words: Set<String>, excluding: Set<String> = []) -> Bool {
    guard let next = wordAfter(match) else { return true }
    return words.contains(next) && !excluding.contains(next)
  }

  /// True for `word`, a weekday as typed, written with a capital first letter
  /// and lowercase ones ("Пятница") when its match does not open the line: a
  /// name, not the day. A word in capitals ("ПЯТНИЦУ") or in lowercase is the
  /// day.
  static func isCapitalizedName(_ word: String, in match: Match) -> Bool {
    guard let first = word.first, first.isUppercase, word.dropFirst().allSatisfy(\.isLowercase),
      let start = Range(match.result.range, in: match.source)?.lowerBound
    else { return false }
    return !match.source[..<start].allSatisfy(\.isWhitespace)
  }

  /// The words of a matched list of weekdays or of a day phrase, as letters
  /// only: "понедельникам, средам и пятницам" as its three weekday names and
  /// "и".
  static func letterWords(_ text: String) -> [String] {
    text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
  }

  /// The date range a match of a range pattern names, as Russian, Ukrainian,
  /// Polish, and Arabic write one ("с 3 по 5 мая", "з 3 до 5 травня", "od 3 do
  /// 5 maja", "من 3 إلى 5 مارس"). Groups: 1 the opening word, if any ("с", "з",
  /// "od", "من"), 2 the start, 3 a dash between the sides, 4 the word that
  /// means "to" between them ("по", "до", "do", "إلى"), 5 the end. `side` reads
  /// one side's text as a date, with a month for a date and with none for a
  /// day alone.
  ///
  /// A word that means "to" joins the sides only after the opening word, so
  /// "3 по 5 мая" stays in the title. A start that is a day alone, with a dash
  /// between the sides and no opening word, is read only when the dash touches
  /// both sides ("3-5 мая"): "Спринт 12 - 20 мая" names a sprint and a date.
  /// The end must name a month, so days of the month with none ("с 3 по 5")
  /// are no range, and it must be after the start
  /// (``dayRangeReading(from:to:today:)``).
  static func slavicDateRange(_ match: Match, side: (String) -> ExplicitDate?) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = side(startText), let end = side(endText)
    else { return nil }
    let hasOpeningWord = match.group(1) != nil
    if match.group(4) != nil, !hasOpeningWord { return nil }
    if start.month == nil, !hasOpeningWord, match.group(3) != nil,
      !dashTouchesBothSides(match, start: 2, end: 5)
    {
      return nil
    }
    guard end.month != nil else { return nil }
    return dayRangeReading(from: start, to: end, today: match.today)
  }
}
