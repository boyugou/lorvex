import Foundation

extension LorvexCaptureVocabulary {
  // The Marathi repeat rules. The vocabulary's other words are in ``marathi``.

  /// The repeat rules, in the order they are tried: a span of weekdays beside
  /// "दर" or the words for every day, the working days, the weekend, and a day
  /// of the month before the weekdays and every day and every month, which
  /// would leave "सोमवार" or the day's number in the title; then the weekdays,
  /// an interval, "once a week", every other day, a part of the day, and the
  /// words for every day. When `besideHindi`, a repeat that Hindi words follow
  /// ("प्रत्येक सोमवार को", "रोज़ का काम") is left to Hindi
  /// (``marathiHindiAfter``).
  static func marathiRepeatRules(besideHindi: Bool) -> [Rule<Repeat>] {
    func rule(_ pattern: String, read: @escaping @Sendable (Match) -> Repeat?) -> Rule<Repeat> {
      marathiRule(marathiGuarded(pattern, besideHindi: besideHindi), read: read)
    }
    return [
      rule(marathiWeekdaySpanPattern, read: marathiWeekdaySpanRepeat),
      rule(marathiWorkdaysPattern) { _ in workdays },
      rule(marathiWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      rule(marathiMonthDayRepeatPattern, read: marathiMonthDayRepeat),
      rule(marathiWeekdayRepeatPattern, read: marathiWeekdayRepeat),
      rule(marathiIntervalRepeatPattern, read: marathiIntervalRepeat),
      rule(marathiOnceEveryPattern, read: marathiOnceEvery),
      rule(marathiAlternatePattern, read: marathiAlternate),
      rule(marathiPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      rule(marathiDailyWordPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
    ]
  }

  // MARK: - Words

  /// "दर" or "प्रत्येक": every.
  static let marathiEvery = #"(?:दर|प्रत्येक)"#

  /// "दर", "प्रत्येक", "रोज", or "दररोज": the words that may stand before a part
  /// of the day to make it every day's ("रोज सकाळी", "दर संध्याकाळी").
  static let marathiEveryOrDaily = #"(?:दररोज|रोज|दर|प्रत्येक)"#

  /// The words for every day, which may stand beside a span of weekdays
  /// ("सोमवार ते शुक्रवार दररोज").
  private static let marathiEveryDayWords =
    #"(?:दररोज|रोज|दर\s*दिवशी|प्रत्येक\s+दिवशी|प्रत्येक\s+दिवस)"#

  /// Whether the words around a span of weekdays make it a habit: "दर" before
  /// it ("दर रविवार ते गुरुवार") or the words for every day before or after it
  /// ("रोज सोमवार ते शुक्रवार", "सोमवार ते शुक्रवार दररोज"). The date-range
  /// rules leave such a span to the repeat rules.
  static func marathiIsHabitSpan(_ match: Match) -> Bool {
    guard let range = Range(match.result.range, in: match.source) else { return false }
    let before = String(match.source[..<range.lowerBound])
    let after = String(match.source[range.upperBound...])
    return marathiFinds(
      #"\#(devanagariStart)(?:\#(marathiEvery)|\#(marathiEveryDayWords))\s*$"#, in: before)
      || marathiFinds(#"^\s+\#(marathiEveryDayWords)\#(devanagariEnd)"#, in: after)
  }

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// stem: days, weeks, months, or years.
  private static func marathiRepeat(unit: String, every: Int?) -> Repeat? {
    let key = marathiKey(unit)
    if marathiHasPrefix(key, marathiKey("दिवस")) || marathiHasPrefix(key, marathiKey("दिवशी")) {
      return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    }
    if marathiHasPrefix(key, marathiKey("आठवड")) { return weekly(every: every, on: []) }
    if marathiHasPrefix(key, marathiKey("महिन")) || marathiHasPrefix(key, marathiKey("महा")) {
      return monthly(every: every, on: nil)
    }
    if marathiHasPrefix(key, marathiKey("वर्ष")) {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    return nil
  }

  // MARK: - Weekdays

  /// A weekday with its ending as a pattern: "सोमवार", "सोमवारी".
  private static var marathiWeekdayItem: String {
    #"(?:\#(marathiWeekdayNames))(?:·ी)?"#
  }

  /// "दर रविवार ते गुरुवार", "सोमवार ते शुक्रवार दररोज", "रोज सोमवार ते
  /// शुक्रवार": every day of a span of weekdays. Groups: 1 the words for every
  /// day before the span, 2 "दर" before it, 3 the first weekday, 4 the last,
  /// 5 the words for every day after it.
  private static var marathiWeekdaySpanPattern: String {
    let daily = #"\#(marathiEveryDayWords)\s+"#
    return
      #"\#(devanagariStart)(\#(daily))?(\#(marathiEvery)\s*)?(\#(marathiWeekdayNames))(?:·ी)?\s+ते\s+(\#(marathiWeekdayNames))(?:·ी)?(?:(?:·|\s+)पर्यंत)?+\#(devanagariEnd)(\s+\#(marathiEveryDayWords)\#(devanagariEnd))?"#
  }

  /// A span runs from its first weekday to its last through the week's end. It
  /// is a habit only beside "दर" or the words for every day: without them
  /// ("सोमवार ते शुक्रवार") it may as well be a week of work, which the
  /// date-range rules leave unread. A span from a day to itself is no span.
  private static func marathiWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(3), let lastWord = match.group(4),
      let first = marathiWeekdayIndex(firstWord), let last = marathiWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(2) != nil || match.group(5) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "कामाच्या दिवशी", "कामाच्या दिवसांत", "कामाच्या दिवसांमध्ये", "दर कामाच्या
  /// दिवशी", "रोज कामाच्या दिवशी": the working days, Monday to Friday. The
  /// noun phrase "कामाचे दिवस" ("days of work") is not read: it names the days
  /// as often as it says on which of them a task repeats.
  private static var marathiWorkdaysPattern: String {
    #"\#(devanagariStart)(?:(?:\#(marathiEveryOrDaily))\s*)?(?:कामाच्या|कामकाजाच्या)\s+(?:दिवशी|दिवसांत|दिवसांमध्ये)\#(devanagariEnd)"#
  }

  /// "दर वीकेंडला", "प्रत्येक वीकेंडला", "दर शनिवार-रविवारी": Saturday and Sunday.
  private static var marathiWeekendRepeatPattern: String {
    #"\#(devanagariStart)\#(marathiEvery)\s*\#(marathiWeekendWords)(?:·(?:ी|ला))?\#(devanagariEnd)"#
  }

  /// "दर सोमवारी", "दर सोमवार", "दर सोमवारी आणि गुरुवारी", "दर सोमवार, बुधवार आणि
  /// शुक्रवार", "दर दुसऱ्या सोमवारी", "दर आठवड्याला सोमवारी", "सोमवारी आणि
  /// गुरुवारी दर आठवड्याला". Groups: 1 "दुसऱ्या" after "दर" (every other), 2
  /// the weekdays after "दर", 3 the weekdays after "दर आठवड्याला", 4 the weekdays
  /// before "दर आठवड्याला".
  private static var marathiWeekdayRepeatPattern: String {
    let item = marathiWeekdayItem
    let separator = #"(?:\s*,\s*(?:(?:आणि|व)\s+)?|\s+(?:आणि|व|तसेच)\s+)"#
    let list = #"\#(item)(?:\#(separator)(?:\#(marathiEvery)\s*)?\#(item)){0,6}"#
    let everyWeek = #"\#(marathiEvery)\s*आठवड्याला"#
    let every = #"\#(marathiEvery)\s*(?:(दुसऱ्या)\s+)?(\#(list))"#
    let afterWeek = #"\#(everyWeek)\s+(\#(list))"#
    let beforeWeek = #"(\#(list))\s+\#(everyWeek)"#
    return #"\#(devanagariStart)(?:\#(every)|\#(afterWeek)|\#(beforeWeek))\#(devanagariEnd)"#
  }

  private static func marathiWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(2) ?? match.group(3) ?? match.group(4) ?? ""
    let days = marathiWords(in: list).compactMap(marathiWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: match.group(1) == nil ? nil : 2, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "दर महिन्याच्या 5 तारखेला", "दर महिन्याला 5 तारखेला", "दरमहा 5 तारखेला",
  /// "दर महिन्याची 5 तारीख", "दर महिन्याच्या पहिल्या तारखेला", "5 तारखेला दर
  /// महिन्याला". Groups: 1 and 2 the day of the month in each order, in digits
  /// or "पहिल्या".
  private static var marathiMonthDayRepeatPattern: String {
    let month = #"(?:\#(marathiEvery)\s*महिन्या(?:च्या|ची|ला|त)|दरमहा)"#
    let day = #"\d{1,2}|पहिल्या"#
    let dayWord = #"\s*(?:तारखे(?:ला|स)|तारीख)"#
    return
      #"\#(devanagariStart)(?:\#(month)\s*(\#(day))\#(dayWord)|(\#(day))\#(dayWord)\s+\#(marathiEvery)\s*महिन्याला)\#(devanagariEnd)"#
  }

  private static func marathiMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = (match.group(1) ?? match.group(2)).map(marathiPhrase) else { return nil }
    guard let day = text == marathiKey("पहिल्या") ? 1 : number(text) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// The unit words of an interval, as a pattern: days, weeks, months, and
  /// years, in the forms that follow "दर" and "प्रत्येक". "महा" is the "महा" of
  /// "दरमहा" (every month).
  private static let marathiUnits =
    "दिवसांनी|दिवशी|दिवस|आठवड्यांनी|आठवड्याला|आठवडे|आठवडा|महिन्यांनी|महिन्याला|महिने|महिना|महा|वर्षांनी|वर्षी|वर्षे|वर्ष"

  /// "दर दिवशी", "दर आठवड्याला", "दर महिन्याला", "दरमहा", "दरवर्षी", "दर वर्षी",
  /// "प्रत्येक आठवडा", "प्रत्येक महिना", "प्रत्येक वर्षी", "दर 2 दिवसांनी", "दर दोन
  /// आठवड्यांनी", "दर 3 महिन्यांनी", "दर 5 वर्षांनी", "दर पंधरा दिवसांनी", "प्रत्येक 2
  /// आठवडे", "दर दुसऱ्या दिवशी", "दर दुसऱ्या आठवड्याला", "प्रत्येक इतर दिवशी". An
  /// interval shorter than a day ("दर 2 तासांनी") is no repeat. Groups: 1 the
  /// count, 2 "दुसऱ्या" or "इतर" (every other), 3 the unit. A genitive glued
  /// to the unit ("दर महिन्याचा खर्च") makes the cadence an attribute of a
  /// noun and is left to the title.
  private static var marathiIntervalRepeatPattern: String {
    #"\#(devanagariStart)\#(marathiEvery)\s*(?:(\d{1,2}|\#(marathiRoundCountWords))\s+|(दुसऱ्या|इतर)\s+)?(\#(marathiUnits))\#(devanagariEnd)"#
  }

  private static func marathiIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(3) else { return nil }
    var count = 1
    if match.group(2) != nil {
      count = 2
    } else if let text = match.group(1) {
      guard let value = number(text) ?? marathiRoundCounts[marathiPhrase(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    return marathiRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "दिवसातून एकदा", "आठवड्यातून एकदा", "महिन्यातून एकदा", "वर्षातून एकदा", each
  /// maybe with "फक्त" or "केवळ" and with "एक वेळ" or "एक वेळा" for "एकदा". Group
  /// 1: the unit.
  private static var marathiOnceEveryPattern: String {
    #"\#(devanagariStart)((?:दिवसा|आठवड्या|महिन्या|वर्षा)तून)\s+(?:(?:फक्त|केवळ)\s+)?(?:एकदा|एक\s+वेळा?|एकवेळ)\#(devanagariEnd)"#
  }

  private static func marathiOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).flatMap { marathiRepeat(unit: $0, every: nil) }
  }

  /// "दिवसाआड", "एक दिवसाआड", "आठवड्याआड", "महिन्याआड", "वर्षाआड": every other day,
  /// week, month, or year. A count before the unit ("दोन दिवसाआड" is every
  /// third day) is another interval and is not read. Group 1: the unit.
  private static var marathiAlternatePattern: String {
    let counts = alternation(of: marathiCounts.keys.filter { $0 != marathiKey("एक") })
    return
      #"\#(devanagariStart)(?<!\p{N}\s)(?<!(?:\#(counts))\s)(?:एक\s+)?((?:दिवसा|आठवड्या|महिन्या|वर्षा)आड)\#(devanagariEnd)"#
  }

  private static func marathiAlternate(_ match: Match) -> Repeat? {
    match.group(1).flatMap { marathiRepeat(unit: $0, every: 2) }
  }

  // MARK: - Parts of the day and daily words

  /// "रोज सकाळी", "दर संध्याकाळी", "दररोज रात्री", "प्रत्येक सकाळी": every day.
  private static var marathiPartOfDayRepeatPattern: String {
    #"\#(devanagariStart)\#(marathiEveryOrDaily)\s+(?:\#(marathiDayPartWords))\#(devanagariEnd)"#
  }

  /// "रोज", "दररोज", "नित्य": every day. They say how a task repeats, and a
  /// genitive glued to them ("रोजचा व्यायाम") makes them an attribute of a
  /// noun, which the pattern does not list. "रोजी", "रोजगार", and "रोजनिशी" are
  /// other words.
  private static var marathiDailyWordPattern: String {
    #"\#(devanagariStart)(?:दररोज|रोज|नित्य)\#(devanagariEnd)"#
  }
}
