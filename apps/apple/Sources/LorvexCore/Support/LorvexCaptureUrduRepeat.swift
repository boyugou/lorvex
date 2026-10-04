import Foundation

extension LorvexCaptureVocabulary {
  // The Urdu repeat rules. The vocabulary's other words are in ``urdu``.

  /// The repeat rules, in the order they are tried: a span of weekdays after
  /// "ہر" or beside the words for every day, the working days, the weekend, and
  /// a day of the month before the weekdays and every day and every month, which
  /// would leave "پیر" or the day's number in the title; then the weekdays, a
  /// part of the day (before the interval, so "ہر روز صبح" takes its "صبح"), an
  /// interval, "once a week", and the adverbs.
  static var urduRepeatRules: [Rule<Repeat>] {
    [
      urduRule(urduWeekdaySpanPattern, read: urduWeekdaySpanRepeat),
      urduRule(urduWorkdaysPattern) { _ in workdays },
      urduRule(urduWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      urduRule(urduMonthDayRepeatPattern, read: urduMonthDayRepeat),
      urduRule(urduWeekdayRepeatPattern, read: urduWeekdayRepeat),
      urduRule(urduPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      urduRule(urduIntervalRepeatPattern, read: urduIntervalRepeat),
      urduRule(urduOnceEveryPattern, read: urduOnceEvery),
      urduRule(urduAdverbPattern, read: urduAdverbRepeat),
    ]
  }

  // MARK: - Words

  /// The words for every day, which may stand beside a span of weekdays ("پیر
  /// سے جمعہ ہر روز"). A bare "روز" is not one: it is also "day" ("جمعہ کے روز").
  private static let urduEveryDayWords = #"(?:ہر\s+(?:دن|روز)|روزانہ)"#

  /// Whether the words around a span of weekdays make it a habit: "ہر" before it
  /// ("ہر اتوار سے جمعرات") or the words for every day before or after it
  /// ("روزانہ پیر سے جمعہ", "پیر سے جمعہ ہر روز"). The date-range rules leave
  /// such a span to the repeat rules.
  static func urduIsHabitSpan(_ match: Match) -> Bool {
    urduFinds(#"\#(urduStart)(?:ہر|\#(urduEveryDayWords))\s+$"#, in: urduTextBefore(match))
      || urduFinds(#"^\s+\#(urduEveryDayWords)\#(urduEnd)"#, in: urduTextAfter(match))
  }

  /// What may not follow a cadence: a word that makes it an attribute of a noun
  /// ("روزانہ کی رپورٹ", "ہر سال کا جائزہ"). "کی بنیاد پر" ("on a daily basis")
  /// is no attribute.
  private static let urduNotAttribute =
    #"(?!\s+(?:کا|کی(?!\s+بنیاد)|کے|والا|والی|والے)\#(urduEnd))"#

  /// "کی بنیاد پر", which may follow an adverb of cadence and goes with it.
  private static let urduBasis = #"(?:\s+کی\s+بنیاد\s+پر\#(urduEnd))?"#

  /// The unit words of an interval, as a pattern: days, weeks, months, and
  /// years, each in the singular and in the oblique plural.
  private static let urduUnits =
    "دنوں|دن|روز|ہفتوں|ہفتے|ہفتہ|مہینوں|مہینے|مہینہ|ماہ|سالوں|سال|برسوں|برس"

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years. `unit` is in the reading form.
  private static func urduRepeat(unit: String, every: Int?) -> Repeat? {
    switch unit {
    case urduTableKey("دن"), urduTableKey("دنوں"), urduTableKey("روز"):
      Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case urduTableKey("ہفتے"), urduTableKey("ہفتہ"), urduTableKey("ہفتوں"): weekly(every: every, on: [])
    case urduTableKey("مہینے"), urduTableKey("مہینہ"), urduTableKey("مہینوں"), urduTableKey("ماہ"):
      monthly(every: every, on: nil)
    case urduTableKey("سال"), urduTableKey("سالوں"), urduTableKey("برس"), urduTableKey("برسوں"):
      Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: nil
    }
  }

  // MARK: - Weekdays

  /// "ہر اتوار سے جمعرات", "پیر سے جمعہ ہر روز", "روزانہ پیر سے جمعہ", each maybe
  /// with "سے لے کر" for "سے" and "تک" after it: every day of a span of
  /// weekdays. Groups: 1 the words for every day before the span, 2 "ہر" before
  /// it, 3 the first weekday, 4 the last, 5 the words for every day after it.
  private static var urduWeekdaySpanPattern: String {
    let daily = #"\#(urduEveryDayWords)\s+"#
    return
      #"\#(urduStart)(\#(daily))?(ہر\s+)?(\#(urduWeekdayNames))\s+(?:سے|تا)(?:\s+(?:لے\s*کر|لیکر))?\s+(\#(urduWeekdayNames))\#(urduEnd)(?:\s+تک\#(urduEnd))?+(\s+\#(urduEveryDayWords)\#(urduEnd))?\#(urduNotAttribute)"#
  }

  /// A span runs from its first weekday to its last through the week's end. It
  /// is a habit only beside "ہر" or the words for every day: without them ("پیر
  /// سے جمعہ") it may as well be a week of work, which the date-range rules
  /// leave unread. A span from a day to itself is no span.
  private static func urduWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(3), let lastWord = match.group(4),
      let first = urduWeekdayIndex(firstWord), let last = urduWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(2) != nil || match.group(5) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "ہر کام کے دن", "ہر ورکنگ ڈے", "کام کے دنوں میں", "کاروباری دنوں میں": the
  /// working days, Monday to Friday.
  private static var urduWorkdaysPattern: String {
    let days = #"(?:کام\s+کے\s+دن|کاروباری\s+دن|ورکنگ\s+ڈے)"#
    let plural = #"(?:کام\s+کے\s+دنوں|کاروباری\s+دنوں|ورکنگ\s+ڈیز)"#
    return
      #"\#(urduStart)(?:ہر\s+\#(days)|\#(plural)\s+میں)\#(urduEnd)\#(urduNotAttribute)"#
  }

  /// "ہر ویک اینڈ", "ہر اختتام ہفتہ": Saturday and Sunday.
  private static var urduWeekendRepeatPattern: String {
    #"\#(urduStart)ہر\s+\#(urduWeekendWords)\#(urduEnd)\#(urduNotAttribute)"#
  }

  /// "ہر پیر", "ہر پیر کو", "ہر پیر اور جمعرات", "ہر پیر، بدھ اور جمعہ", "ہر دوسرے
  /// پیر", "ہر ہفتے پیر کو", "پیر اور جمعرات کو ہر ہفتے", "ہر ہفتے کو" (Saturdays).
  /// Groups: 1 the weekdays after "ہر ہفتے" and 2 the "کو" after them, 3 "دوسرے"
  /// after "ہر" (every other), 4 the weekdays after "ہر" and 5 the "کو" or "کے
  /// دن" after them, 6 the weekdays before "کو ہر ہفتے". ہفتہ and ہفتے name
  /// Saturday only in a list of several days or before "کو", "کے دن", or "کے
  /// روز": "ہر ہفتہ" alone is every week.
  private static var urduWeekdayRepeatPattern: String {
    let item = #"(?:\#(urduWeekdayNames))"#
    let separator = #"(?:\s*[,،]\s*(?:(?:اور|و)\s+)?|\s+(?:اور|و|نیز)\s+)"#
    let list = #"\#(item)(?:\#(separator)(?:ہر\s+)?\#(item)){0,6}"#
    let marker = #"(\s+(?:کو|کے\s+(?:دن|روز))\#(urduEnd))?"#
    let everyWeek = #"ہر\s+\#(urduWeekWord)\s+(\#(list))\#(marker)"#
    let every = #"ہر\s+(?:(دوسرے|دوسرا|دوسری)\s+)?(\#(list))\#(marker)"#
    let listFirst = #"(\#(list))\s+کو\s+ہر\s+\#(urduWeekWord)"#
    return
      #"\#(urduStart)(?:\#(everyWeek)|\#(every)|\#(listFirst))\#(urduEnd)\#(urduNotAttribute)"#
  }

  private static func urduWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(1) ?? match.group(4) ?? match.group(6) ?? ""
    let words = urduWords(in: list)
    let days = words.compactMap(urduWeekdayIndex)
    guard !days.isEmpty else { return nil }
    // ہفتہ and ہفتے alone are the week: Saturday needs "کو" or "کے دن" after it
    // or another weekday beside it.
    let isMarked = match.group(2) != nil || match.group(5) != nil || match.group(6) != nil || days.count > 1
    if days.count == 1, words.contains(where: urduIsWeekWord), !isMarked { return nil }
    return weekly(every: match.group(3) == nil ? nil : 2, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "ہر مہینے کی 5 تاریخ", "ہر مہینے 5 تاریخ کو", "ہر ماہ کی 5ویں تاریخ کو", "ہر
  /// مہینے کی پہلی تاریخ", "ہر مہینے کی 5 کو", "5 تاریخ کو ہر مہینے". Groups: 1 and
  /// 2 the day of the month in each form, in digits or "پہلی".
  private static var urduMonthDayRepeatPattern: String {
    let ordinal = #"(?:ویں|واں)?"#
    let day = #"\d{1,2}\#(ordinal)|پہلی"#
    let dayWord =
      #"(?:\s*تاریخ\#(urduEnd)(?:\s+کو\#(urduEnd))?|\s+کو\#(urduEnd))"#
    return
      #"\#(urduStart)(?:ہر\s+(?:مہینے|مہینہ|ماہ)(?:\s+کی)?\s+(\#(day))\#(dayWord)|(\#(day))\s*تاریخ\#(urduEnd)(?:\s+کو\#(urduEnd))?\s+ہر\s+(?:مہینے|مہینہ|ماہ)\#(urduEnd))"#
  }

  private static func urduMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = (match.group(1) ?? match.group(2)).map(urduPhrase) else { return nil }
    let digits = text.prefix(while: \.isNumber)
    guard let day = text == urduTableKey("پہلی") ? 1 : number(String(digits)) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// "ہر دن", "ہر ہفتے", "ہر مہینے", "ہر سال", "ہر برس", "ہر 2 دن", "ہر دو ہفتے", "ہر
  /// تین مہینے", "ہر 5 سال", "ہر پندرہ دن", "ہر دوسرے دن", "ہر دوسرے ہفتے", each
  /// maybe followed by "بعد" or "میں ایک بار". An interval shorter than a day
  /// ("ہر 2 گھنٹے") is no repeat. Groups: 1 the count, 2 "دوسرے" (every other), 3
  /// the unit.
  private static var urduIntervalRepeatPattern: String {
    #"\#(urduStart)ہر\s+(?:(\d{1,2}|\#(urduRoundCountWords))\s+|(دوسرے|دوسرا|دوسری)\s+)?(\#(urduUnits))(?:\s+(?:کے\s+)?بعد|\s+میں\s+ایک\s+(?:بار|مرتبہ|دفعہ))?\#(urduEnd)\#(urduNotAttribute)"#
  }

  private static func urduIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(3).map(urduKey) else { return nil }
    var count = 1
    if match.group(2) != nil {
      count = 2
    } else if let text = match.group(1) {
      guard let value = number(text) ?? urduRoundCounts[urduKey(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    return urduRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "ہفتے میں ایک بار", "مہینے میں ایک بار", "سال میں ایک بار", "دن میں ایک بار".
  /// Group 1: the unit.
  private static var urduOnceEveryPattern: String {
    #"\#(urduStart)(دن|ہفتے|ہفتہ|مہینے|مہینہ|ماہ|سال|برس)\s+میں\s+(?:صرف\s+|فقط\s+)?ایک\s+(?:بار|مرتبہ|دفعہ)\#(urduEnd)"#
  }

  private static func urduOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).map(urduKey).flatMap { urduRepeat(unit: $0, every: nil) }
  }

  // MARK: - Parts of the day and adverbs

  /// "ہر صبح", "ہر شام", "ہر رات", "ہر دوپہر", "ہر روز صبح", each maybe with "کو"
  /// or "میں" ("ہر شام کو"): every day.
  private static var urduPartOfDayRepeatPattern: String {
    #"\#(urduStart)ہر\s+(?:(?:روز|دن)\s+)?\#(urduPartOfDayWords)\#(urduEnd)(?:\s+(?:کو|میں)\#(urduEnd))?\#(urduNotAttribute)"#
  }

  /// The adverbs of cadence: group 1 for every day (روزانہ), 2 for every week
  /// (ہفتہ وار, "ہفتہ واری"), 3 for every month (ماہانہ, ماہوار), 4 for every year
  /// (سالانہ, سالیانہ). They say how a task repeats, and an attributive use
  /// ("روزانہ کی رپورٹ") is no repeat. Urdu puts an adjective before its noun, so
  /// the words are read wherever they stand: "روزانہ رپورٹ بھیجنا" is as often a
  /// daily task as a daily report. "کی بنیاد پر" after them goes with them. A
  /// bare "روز" is not read: it is also "day" ("جمعہ کے روز").
  private static var urduAdverbPattern: String {
    #"\#(urduStart)(?:(روزانہ|روزآنہ)|(ہفتہ\s*واری?|ہفتے\s*وار)|(ماہانہ|ماہوار|ماہیانہ)|(سالانہ|سالیانہ))\#(urduEnd)\#(urduBasis)\#(urduNotAttribute)"#
  }

  private static func urduAdverbRepeat(_ match: Match) -> Repeat? {
    if match.group(1) != nil { return Repeat(rule: TaskRecurrenceRule(freq: .daily)) }
    if match.group(2) != nil { return weekly(every: nil, on: []) }
    if match.group(3) != nil { return monthly(every: nil, on: nil) }
    if match.group(4) != nil { return Repeat(rule: TaskRecurrenceRule(freq: .yearly)) }
    return nil
  }
}
