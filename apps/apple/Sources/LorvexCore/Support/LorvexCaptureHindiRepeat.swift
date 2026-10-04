import Foundation

extension LorvexCaptureVocabulary {
  // The Hindi repeat rules. The vocabulary's other words are in ``hindi``.

  /// The repeat rules, in the order they are tried: a span of weekdays after
  /// "हर" or beside the words for every day, the working days, the weekend, and
  /// a day of the month before the weekdays and every day and every month, which
  /// would leave "सोमवार" or the day's number in the title; then the weekdays,
  /// an interval, "once a week", a part of the day, and the words for every
  /// day.
  static var hindiRepeatRules: [Rule<Repeat>] {
    [
      hindiRule(hindiWeekdaySpanPattern, read: hindiWeekdaySpanRepeat),
      hindiRule(hindiWorkdaysPattern) { _ in workdays },
      hindiRule(hindiWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      hindiRule(hindiMonthDayRepeatPattern, read: hindiMonthDayRepeat),
      hindiRule(hindiWeekdayRepeatPattern, read: hindiWeekdayRepeat),
      hindiRule(hindiIntervalRepeatPattern, read: hindiIntervalRepeat),
      hindiRule(hindiOnceEveryPattern, read: hindiOnceEvery),
      hindiRule(hindiPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      hindiRule(hindiDailyWordPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
    ]
  }

  // MARK: - Words

  /// "हर", "प्रत्येक", or "हरेक": every.
  static let hindiEvery = #"(?:हर|प्रत्येक|हरेक)"#

  /// The words for every day, which may stand beside a span of weekdays ("सोमवार
  /// से शुक्रवार हर दिन").
  private static let hindiEveryDayWords = #"(?:हर\s+दिन|रोज(?:ाना)?|प्रतिदिन)"#

  /// Whether the words around a span of weekdays make it a habit: "हर" before
  /// it ("हर रविवार से गुरुवार") or the words for every day before or after it
  /// ("रोज़ सोमवार से शुक्रवार", "सोमवार से शुक्रवार हर दिन"). The date-range
  /// rules leave such a span to the repeat rules.
  static func hindiIsHabitSpan(_ match: Match) -> Bool {
    guard let range = Range(match.result.range, in: match.source) else { return false }
    let before = String(match.source[..<range.lowerBound])
    let after = String(match.source[range.upperBound...])
    return hindiFinds(#"\#(devanagariStart)(?:\#(hindiEvery)|\#(hindiEveryDayWords))\s+$"#, in: before)
      || hindiFinds(#"^\s+\#(hindiEveryDayWords)\#(devanagariEnd)"#, in: after)
  }

  /// What may not follow a cadence: a word that makes it an attribute of a noun
  /// ("रोज़ का काम", "हर साल की रिपोर्ट").
  private static let hindiNotAttribute = #"(?!\s+(?:का|की|के|वाला|वाली|वाले)\#(devanagariEnd))"#

  /// The unit words of an interval, as a pattern: days, weeks, months, and
  /// years, each in the singular and in the oblique plural.
  private static let hindiUnits =
    "दिनों|दिन|हफ्तों|हफ्ते|हफ्ता|सप्ताहों|सप्ताह|महीनों|महीने|महीना|माह|सालों|साल|वर्षों|वर्ष"

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func hindiRepeat(unit: String, every: Int?) -> Repeat? {
    switch unit {
    case "दिन", "दिनों": Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "हफ्ते", "हफ्ता", "हफ्तों", "सप्ताह", "सप्ताहों": weekly(every: every, on: [])
    case "महीने", "महीना", "महीनों", "माह": monthly(every: every, on: nil)
    case "साल", "सालों", "वर्ष", "वर्षों": Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: nil
    }
  }

  // MARK: - Weekdays

  /// "हर रविवार से गुरुवार", "सोमवार से शुक्रवार हर दिन", "रोज़ सोमवार से
  /// शुक्रवार", each maybe with "से लेकर" for "से" and "तक" after it: every day
  /// of a span of weekdays. Groups: 1 the words for every day before the span, 2
  /// "हर" before it, 3 the first weekday, 4 the last, 5 the words for every day
  /// after it.
  private static var hindiWeekdaySpanPattern: String {
    let daily = #"\#(hindiEveryDayWords)\s+"#
    return
      #"\#(devanagariStart)(\#(daily))?(\#(hindiEvery)\s+)?(\#(hindiWeekdayNames))\s+से(?:\s+लेकर)?\s+(\#(hindiWeekdayNames))\#(devanagariEnd)(?:\s+तक\#(devanagariEnd))?+(\s+\#(hindiEveryDayWords)\#(devanagariEnd))?\#(hindiNotAttribute)"#
  }

  /// A span runs from its first weekday to its last through the week's end. It
  /// is a habit only beside "हर" or the words for every day: without them
  /// ("सोमवार से शुक्रवार") it may as well be a week of work, which the
  /// date-range rules leave unread. A span from a day to itself is no span.
  private static func hindiWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(3), let lastWord = match.group(4),
      let first = hindiWeekdayIndex(firstWord), let last = hindiWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(2) != nil || match.group(5) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "हर कार्यदिवस", "कार्यदिवसों में", "हर कामकाजी दिन", "कामकाजी दिनों में": the
  /// working days, Monday to Friday.
  private static var hindiWorkdaysPattern: String {
    let daily = #"(?:\#(hindiEveryDayWords)\s+)?"#
    return
      #"\#(devanagariStart)\#(daily)(?:\#(hindiEvery)\s+(?:कार्य\s*दिवस(?:ों)?|कामकाजी\s+दिन(?:ों)?)|(?:कार्य\s*दिवसों|कामकाजी\s+दिनों)\s+में)\#(devanagariEnd)\#(hindiNotAttribute)"#
  }

  /// "हर वीकेंड", "हर सप्ताहांत": Saturday and Sunday.
  private static var hindiWeekendRepeatPattern: String {
    #"\#(devanagariStart)\#(hindiEvery)\s+\#(hindiWeekendWords)\#(devanagariEnd)\#(hindiNotAttribute)"#
  }

  /// "हर सोमवार", "हर सोमवार को", "हर सोमवार और गुरुवार", "हर सोमवार, बुधवार और
  /// शुक्रवार", "हर दूसरे सोमवार", "हर हफ्ते सोमवार को", "सोमवार और गुरुवार को हर
  /// हफ्ते", "सोमवारों को". Groups: 1 "दूसरे" after "हर" (every other), 2 the
  /// weekdays after "हर", 3 the weekdays after "हर हफ्ते", 4 the weekdays before
  /// "को हर हफ्ते", 5 the plural weekdays before "को".
  private static var hindiWeekdayRepeatPattern: String {
    let item = #"(?:\#(hindiWeekdayNames))"#
    let separator = #"(?:\s*,\s*(?:(?:और|व)\s+)?|\s+(?:और|व|तथा)\s+)"#
    let list = #"\#(item)(?:\#(separator)(?:\#(hindiEvery)\s+)?\#(item)){0,6}"#
    let plural = #"(?:\#(hindiWeekdayNames))ों"#
    let plurals = #"\#(plural)(?:\#(separator)\#(plural)){0,6}"#
    let every = #"\#(hindiEvery)\s+(?:(दूसरे|दूसरा)\s+)?(\#(list))(?:\s+को\#(devanagariEnd))?"#
    let everyWeek = #"\#(hindiEvery)\s+\#(hindiWeekWord)\s+(\#(list))(?:\s+को\#(devanagariEnd))?"#
    let listFirst = #"(\#(list))\s+को\s+\#(hindiEvery)\s+\#(hindiWeekWord)"#
    return
      #"\#(devanagariStart)(?:\#(every)|\#(everyWeek)|\#(listFirst)|(\#(plurals))\s+को)\#(devanagariEnd)\#(hindiNotAttribute)"#
  }

  private static func hindiWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(2) ?? match.group(3) ?? match.group(4) ?? match.group(5) ?? ""
    let days = hindiWords(in: list).compactMap(hindiWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: match.group(1) == nil ? nil : 2, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "हर महीने की 5 तारीख", "हर महीने 5 तारीख को", "हर माह की 5वीं तारीख़ को",
  /// "हर महीने की पहली तारीख", "हर महीने की 5 को", "5 तारीख को हर महीने".
  /// Groups: 1 and 2 the day of the month in each form, in digits or "पहली".
  private static var hindiMonthDayRepeatPattern: String {
    let ordinal = #"(?:वीं|वी|वें)?"#
    let day = #"\d{1,2}\#(ordinal)|पहली"#
    let dayWord =
      #"(?:\s*(?:तारीख|तिथि)\#(devanagariEnd)(?:\s+को\#(devanagariEnd))?|\s+को\#(devanagariEnd))"#
    return
      #"\#(devanagariStart)(?:\#(hindiEvery)\s+(?:महीने|माह)(?:\s+की)?\s+(\#(day))\#(dayWord)|(\#(day))\s*(?:तारीख|तिथि)\#(devanagariEnd)(?:\s+को\#(devanagariEnd))?\s+\#(hindiEvery)\s+(?:महीने|माह)\#(devanagariEnd))"#
  }

  private static func hindiMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = (match.group(1) ?? match.group(2)).map(hindiPhrase) else { return nil }
    let digits = text.prefix(while: \.isNumber)
    guard let day = text == "पहली" ? 1 : number(String(digits)) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// "हर दिन", "हर हफ्ते", "हर महीने", "हर साल", "हर वर्ष", "हर 2 दिन", "हर दो
  /// हफ्ते", "हर तीन महीने", "हर 5 साल", "हर पंद्रह दिन", "हर दूसरे दिन", "हर
  /// दूसरे हफ्ते", each maybe followed by "में एक बार". An interval shorter than a
  /// day ("हर 2 घंटे") is no repeat. Groups: 1 the count, 2 "दूसरे" (every
  /// other), 3 the unit.
  private static var hindiIntervalRepeatPattern: String {
    #"\#(devanagariStart)\#(hindiEvery)\s+(?:(\d{1,2}|\#(hindiRoundCountWords))\s+|(दूसरे|दूसरा)\s+)?(\#(hindiUnits))(?:\s+में\s+एक\s+बार)?\#(devanagariEnd)\#(hindiNotAttribute)"#
  }

  private static func hindiIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(3).map(hindiPhrase) else { return nil }
    var count = 1
    if match.group(2) != nil {
      count = 2
    } else if let text = match.group(1) {
      guard let value = number(text) ?? hindiRoundCounts[hindiPhrase(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    return hindiRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "सप्ताह में एक बार", "हफ्ते में एक बार", "महीने में एक बार", "साल में एक बार",
  /// "दिन में एक बार". Group 1: the unit.
  private static var hindiOnceEveryPattern: String {
    #"\#(devanagariStart)(दिन|सप्ताह|हफ्ते|हफ्ता|महीने|महीना|माह|साल|वर्ष)\s+में\s+(?:सिर्फ\s+|केवल\s+)?एक\s+बार\#(devanagariEnd)"#
  }

  private static func hindiOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).map(hindiPhrase).flatMap { hindiRepeat(unit: $0, every: nil) }
  }

  // MARK: - Parts of the day and daily words

  /// "हर सुबह", "हर शाम", "हर रात", "हर दोपहर", each maybe with "को" or "में"
  /// ("हर शाम को"): every day.
  private static var hindiPartOfDayRepeatPattern: String {
    #"\#(devanagariStart)\#(hindiEvery)\s+\#(hindiPartOfDayWords)\#(devanagariEnd)(?:\s+(?:को|में)\#(devanagariEnd))?\#(hindiNotAttribute)"#
  }

  /// "रोज़", "रोज", "रोज़ाना", "रोजाना", "हर रोज़", "प्रतिदिन", "नित्य": every day.
  /// They say how a task repeats, and an attributive use ("रोज़ का काम") is no
  /// repeat.
  private static var hindiDailyWordPattern: String {
    #"\#(devanagariStart)(?:(?:\#(hindiEvery)\s+)?रोज(?:ाना)?|प्रतिदिन|नित्य)\#(devanagariEnd)\#(hindiNotAttribute)"#
  }
}
