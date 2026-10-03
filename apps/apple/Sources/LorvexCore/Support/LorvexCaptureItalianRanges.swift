import Foundation

extension LorvexCaptureVocabulary {
  // The Italian date-range rule, which reads "dal 3 al 5 maggio" and its
  // forms. The vocabulary's other words are in ``italian``.

  /// "dal 3 al 5 maggio", "dal 30 maggio al 2 giugno", "dal 3 fino al 5
  /// maggio", "tra il 3 e il 5 maggio", "3-5 maggio", "3 al 5 maggio", and,
  /// for days of the month alone, "dal 3 al 10". The start is a date or a day
  /// alone ("3", "lunedì 3", "primo"); the end is a date or a day alone, maybe
  /// after "il". Groups: 1 the word that opens the range, if any (dal, tra,
  /// tra il, fra, fra il), 2 the start, 3 a dash between the sides, 4 al, fino
  /// al, or e between them, 5 the end.
  static var italianDateRangePattern: String {
    let weekday = "(?:(?:\(italianDayNames))\\s+)?"
    let day = #"(?:\d{1,2}[º°]?|primo)"#
    let bare = "\(weekday)\(day)\(italianNoMoreDigits)"
    return
      #"\#(latinStart)(?:(dal|(?:tra|fra)(?:\s+il)?)\s+)?(\#(italianMonthDatePattern)|\#(bare))(?:\s*([-–—])\s*|\s+(al|fino\s+al|e)\s+)(?:il\s+)?(\#(italianMonthDatePattern)|\#(bare))\#(italianTimeEnd)"#
  }

  static func italianDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = italianRangeDate(startText), let end = italianRangeDate(endText)
    else { return nil }
    let lead = match.group(1).map(normalizedPhrase)
    // "E" joins the sides only after tra or fra ("il 3 e il 5 maggio" names two
    // days); al and fino al join them after dal, and with no opening word when
    // the end names a month ("3 al 5 maggio").
    if let word = match.group(4).map(normalizedPhrase) {
      let opensBetween = lead.map { $0.hasPrefix("tra") || $0.hasPrefix("fra") } ?? false
      guard (word == "e") == opensBetween, lead != nil || joinsWithoutOpeningWord(match, end: end) else { return nil }
    }
    if start.month == nil, lead == nil, match.group(3) != nil, !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    switch (start.month, end.month) {
    case (nil, nil):
      // Days of the month alone are read as "il 15" is: after il, al, or dal,
      // with a word between the sides, and only at the end of the line or
      // before a word that can follow a date, never "di" ("dal 3 al 5 di
      // maggio" names a month).
      guard match.group(4) != nil, lead == "dal" || lead?.hasSuffix(" il") == true,
        italianFollowsAsDetail(match, excluding: ["di", "del"])
      else { return nil }
    case (_, nil): return nil
    default: break
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 maggio", "lunedì 5 maggio 2027"), or
  /// a day alone ("5", "lunedì 5", "primo"), which has no month.
  private static func italianRangeDate(_ text: String) -> ExplicitDate? {
    let words = normalizedPhrase(text)
    if let date = italianDate(words), date.month != nil { return date }
    guard let match = words.wholeMatch(of: /(?:\p{L}+ )?(\d{1,2}|primo)[º°]?/),
      let day = italianDayNumber(String(match.output.1))
    else { return nil }
    return ExplicitDate(day: day)
  }
}
