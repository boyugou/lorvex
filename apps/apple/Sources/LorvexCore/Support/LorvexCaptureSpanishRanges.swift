import Foundation

extension LorvexCaptureVocabulary {
  // The Spanish date-range rule, which reads "del 3 al 5 de mayo" and its
  // forms. The vocabulary's other words are in ``spanish``.

  /// "del 3 al 5 de mayo", "de 3 a 5 de mayo", "del 30 de mayo al 2 de junio",
  /// "desde el 3 hasta el 5 de mayo", "entre el 3 y el 5 de mayo", "3-5 de
  /// mayo", "3 al 5 de mayo", and, for days of the month alone, "del 3 al 5".
  /// The start is a date or a day alone ("3", "día 3", "lunes 3", "primero");
  /// the end is a date or a day alone, maybe after "el". Groups: 1 the word
  /// that opens the range, if any (del, de, de el, desde, desde el, entre,
  /// entre el), 2 the start, 3 a dash between the sides, 4 al, a, hasta, or y
  /// between them, 5 the end.
  static var spanishDateRangePattern: String {
    let weekday = "(?:(?:\(spanishWeekdayNames))\\s+)?"
    let day = #"(?:\d{1,2}[ºo°]?|1ro|primero)"#
    let bare = "\(weekday)(?:dia\\s+)?\(day)\(spanishNoMoreDigits)"
    return
      #"\#(latinStart)(?:(del|de\s+el|desde\s+el|desde|de|entre\s+el|entre)\s+)?(\#(spanishMonthDatePattern)|\#(bare))(?:\s*([-–—])\s*|\s+(al|a|hasta|y)\s+)(?:el\s+)?(\#(spanishMonthDatePattern)|\#(bare))\#(spanishTimeEnd)"#
  }

  static func spanishDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = spanishRangeDate(startText), let end = spanishRangeDate(endText)
    else { return nil }
    let lead = match.group(1).map(normalizedPhrase)
    // "Y" joins the sides only after entre ("el 3 y el 5 de mayo" names two
    // days); al, a, and hasta join them after del, de, or desde, and with no
    // opening word when the end names a month ("3 al 5 de mayo").
    if let word = match.group(4)?.lowercased() {
      guard (word == "y") == (lead?.hasPrefix("entre") == true),
        lead != nil || joinsWithoutOpeningWord(match, end: end)
      else { return nil }
    }
    if start.month == nil, lead == nil, match.group(3) != nil, !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    switch (start.month, end.month) {
    case (nil, nil):
      // Days of the month alone are read as "el 15" is: after del, el, or
      // día, with a word between the sides, and only at the end of the line
      // or before a word that can follow a date, never "de" ("del 3 al 5 de
      // la lista"), so "de 3 a 4" stays a time range.
      guard match.group(4) != nil,
        lead == "del" || lead?.hasSuffix(" el") == true || startText.lowercased().contains("dia"),
        spanishFollowsAsDetail(match, excluding: ["de", "del"])
      else { return nil }
    case (_, nil): return nil
    default: break
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 de mayo", "lunes 5 de mayo de 2027"),
  /// or a day alone ("5", "día 5", "primero"), which has no month.
  private static func spanishRangeDate(_ text: String) -> ExplicitDate? {
    let words = normalizedPhrase(text)
    if let date = spanishDate(words), date.month != nil { return date }
    guard let match = words.wholeMatch(of: /(?:\p{L}+ )?(\d{1,2}|1ro|primero)[ºo°]?/),
      let day = spanishDayNumber(String(match.output.1))
    else { return nil }
    return ExplicitDate(day: day)
  }
}
