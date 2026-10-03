import Foundation

extension LorvexCaptureVocabulary {
  // The Polish range rules, which read "od 3 do 5 maja", "od poniedziałku do
  // środy", and "od 14 do 16", and the rule that keeps a deadline written as a
  // clock time in the title. The vocabulary's other words are in ``polish``.

  /// "od 3 do 5 maja", "od 30 maja do 2 czerwca", "między 3 a 5 maja", "3-5
  /// maja", "3–5 maja", each maybe with a year after the end. The start is a
  /// date or a day alone ("3", "3."); the end is a date. Groups: 1 the word
  /// that opens the range, if any (od, między), 2 the start, 3 a dash between
  /// the sides, 4 do, a, or i between them, 5 the end.
  static var polishDateRangePattern: String {
    let bare = #"\d{1,2}(?:\.|-?go)?\#(polishNoMoreDigits)"#
    return
      #"\#(latinStart)(?:(od|miedzy)\s+)?(\#(polishMonthDatePattern)|\#(bare))(?:\s*([-–—])\s*|\s+(do|a|i)\s+)(\#(polishMonthDatePattern)|\#(bare))\#(polishDateEnd)"#
  }

  static func polishDateRange(_ match: Match) -> DayRangeReading? {
    // "Do" joins the sides only after od, and "a" or "i" only after między: "3
    // do 5 maja" and "od 3 a 5 maja" stay in the title.
    if let word = match.group(4)?.lowercased() {
      let lead = match.group(1)?.lowercased()
      guard word == "do" ? lead == "od" : lead == "miedzy" else { return nil }
    }
    return slavicDateRange(match, side: polishRangeDate)
  }

  /// "od poniedziałku do środy", "od piątku do niedzieli": a span of weekdays,
  /// both in the genitive. Groups: 1 the first weekday, 2 the last.
  static var polishWeekdayRangePattern: String {
    let genitive = polishWeekdayForms([2])
    return #"\#(latinStart)od\s+(\#(genitive))\s+do\s+(\#(genitive))\#(latinEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first
  /// last day after it, so on a Tuesday "od poniedziałku do środy" runs from
  /// next Monday to the Wednesday after it, where reading "od poniedziałku"
  /// and "do środy" apart would make the task due tomorrow and planned next
  /// Monday. Monday to Friday is the working week, which the repeat rules read
  /// ("od poniedziałku do piątku"), a span from a day to itself is no span, and
  /// a capitalized weekday in the middle of a line is a name.
  static func polishWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1), let lastWord = match.group(2),
      let first = polishWeekdayIndex(firstWord.lowercased()),
      let last = polishWeekdayIndex(lastWord.lowercased()),
      first != last, !(first == 1 && last == 5),
      !isCapitalizedName(firstWord, in: match), !isCapitalizedName(lastWord, in: match)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// A side of a date range: a date ("5 maja") or a day alone ("5"), which has
  /// no month.
  private static func polishRangeDate(_ text: String) -> ExplicitDate? {
    let words = normalizedPhrase(text)
    if let date = polishDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})(?:\.| go)?/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  /// "od 14 do 16", "od 14:00 do 16:00", "od 9 rano do 6 wieczorem", "od 2 do 4
  /// po południu", "od 10 do 12 godz.", "od 9-tej do 17-tej", "godz. 14-16", "w
  /// godzinach 14-16", "między 14:00 a 16:00", and with a dash after a lead:
  /// "od 14:00-16:00", "o 14:00-16:00". A range with a dash and no lead
  /// ("14:00-16:00") is left to English. Groups: 1 the words before the range (od, o, godz., w godzinach,
  /// między, each maybe with "godz."), 2 the start, 3 the part of the day after
  /// it, 4 do, a, i, or a dash between the sides, 5 the end, 6 the part of the
  /// day after it, 7 the word for hour after the end.
  static let polishTimeRangePattern =
    #"\#(latinStart)((?:w\s+)?(?:godzinach|godz\.?)(?:\s+od)?|od(?:\s+godz\.?)?|o(?:\s+godz\.?)?|miedzy(?:\s+godz\.?)?)(?:\s+|(?<=\.)\s*)(\d{1,2}(?:[.:]\d{2})?)\#(polishHourSuffix)(?:\s+(\#(polishPartOfDayWords)))?(\s+do\s+|\s+(?:a|i)\s+|\s*[-–—]\s*)(\d{1,2}(?:[.:]\d{2})?)\#(polishHourSuffix)(?:\s+(\#(polishPartOfDayWords)))?(?:\s+(godzin|godz\.?|h)(?![\p{Latin}\p{N}]))?\#(polishTimeEnd)"#

  static func polishTimeRange(_ match: Match) -> ClockTime? {
    guard let lead = match.group(1).map(normalizedPhrase), let connector = match.group(4),
      let startText = match.group(2), let endText = match.group(5),
      let start = polishRangeSide(startText, part: match.group(3)),
      let end = polishRangeSide(endText, part: match.group(6))
    else { return nil }
    let leadWords = lead.split(separator: " ")
    let opensWithFrom = leadWords.contains("od")
    let opensWithBetween = leadWords.contains("miedzy")
    let isMarked = leadWords.contains { $0.hasPrefix("godz") }
    // "Do" joins the sides only after od ("o 14 do 16" is no range), and "a"
    // or "i" only after między, which takes no dash.
    switch connector.trimmingCharacters(in: .whitespaces) {
    case "do": if !opensWithFrom { return nil }
    case "a", "i": if !opensWithBetween { return nil }
    default: if opensWithBetween { return nil }
    }
    // Two bare hours are as often an amount or a span of numbered items: they
    // are a range only when the lead says they are hours (godz.), or when no
    // counted noun follows ("od 14 do 16 stron") and no word that names what
    // is counted comes before ("Cena od 10 do 20", "Przeczytać rozdziały od 3
    // do 5"). "Między 14 a 16" needs more than two bare hours.
    let isBare = [startText, endText].allSatisfy { $0.allSatisfy(\.isNumber) }
    let hasWord = match.group(3) != nil || match.group(6) != nil || match.group(7) != nil
    if isBare, !hasWord, !isMarked {
      if opensWithBetween { return nil }
      if !polishFollowsAsDetail(match) { return nil }
      if let before = wordBefore(match), polishCountedWords.contains(before) { return nil }
    }
    return timeRange(from: start, to: end)
  }

  /// Words that name an amount or numbered items, which a range of two bare
  /// numbers after them counts ("Cena od 10 do 20", "rozdziały od 3 do 5").
  /// Words that also name a time of day are left out: "lekcje od 9 do 14" are
  /// school hours.
  private static let polishCountedWords: Set<String> = [
    "cena", "cene", "ceny", "koszt", "koszty", "budzet", "rabat", "rabaty", "znizka", "znizke", "znizki", "pensja",
    "pensje", "wynagrodzenie", "kwota", "kwote", "wiek", "waga", "wage", "wzrost", "rozmiar", "rozmiary", "naklad",
    "ilosc", "liczba", "ocena", "ocene", "oceny", "temperatura", "roznica", "rozdzial", "rozdzialy", "strona",
    "strony", "zadania", "punkt", "punkty", "pytanie", "pytania", "numer", "numery", "odcinek", "odcinki", "slajd",
    "slajdy", "paragraf", "paragrafy", "bilety", "miejsca", "wiersze", "linie",
  ]

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one. Dotted minutes that are a month ("5.10") make a date,
  /// not a time.
  private static func polishRangeSide(_ text: String, part: String?) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    if side.output.2 == ".", (1...12).contains(minute) { return nil }
    if let part {
      guard let kind = polishPartOfDay(part) else { return nil }
      return partOfDayTime(hour: hour, minute: minute, part: kind)
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)))
  }

  /// A clock time written as a deadline ("do 18:00", "przed godz. 18:00", "po
  /// 18:00", "najpóźniej do 18:00", "nie później niż o 18:00"), which names no
  /// start time. Group 1 is the deadline, or nil for a range ("od 14 do
  /// 18:00"), which the range rule reads and this rule only steps over, so the
  /// "do 18:00" inside it is not taken for a deadline.
  static let polishDeadlineClockPattern =
    #"\#(latinStart)(?:od\s+(?:godz\.?\s*)?\d{1,2}(?:[.:]\d{2})?(?:\s+(?:\#(polishPartOfDayWords)))?\s+do\s+(?:godz\.?\s*)?\d{1,2}:\d{2}|((?:do|przed|po|najpozniej(?:\s+(?:do|o))?|nie\s+(?:pozniej|wczesniej)\s+niz(?:\s+(?:do|o))?)\s+(?:(?:godz\.?|godzinie|godziny)\s*)?\d{1,2}:\d{2}))(?![\p{N}:]|[.,]\p{N})"#
}
