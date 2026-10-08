import Foundation

extension LorvexCaptureVocabulary {
  // The Bengali repeat rules. The vocabulary's other words are in ``bengali``.

  /// The repeat rules, in the order they are tried: a span of weekdays beside
  /// "প্রতি" or the words for every day, the working days, the weekend, and a
  /// day of the month before the weekdays and every day and every month, which
  /// would leave "সোমবার" or the day's number in the title; then the weekdays,
  /// a part of the day, an amount of days with "অন্তর" or "পর পর" before the
  /// plain interval, which would leave the "অন্তর" of "প্রতি ২ দিন অন্তর" in the
  /// title, "once a week", the words for every day, and the adjectives that
  /// say how a task repeats.
  static var bengaliRepeatRules: [Rule<Repeat>] {
    [
      bengaliRule(bengaliWeekdaySpanPattern, read: bengaliWeekdaySpanRepeat),
      bengaliRule(bengaliWorkdaysPattern) { _ in workdays },
      bengaliRule(bengaliWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      bengaliRule(bengaliMonthDayRepeatPattern, read: bengaliMonthDayRepeat),
      bengaliRule(bengaliWeekdayRepeatPattern, read: bengaliWeekdayRepeat),
      bengaliRule(bengaliPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      bengaliRule(bengaliSpacedRepeatPattern, read: bengaliSpacedRepeat),
      bengaliRule(bengaliIntervalRepeatPattern, read: bengaliIntervalRepeat),
      bengaliRule(bengaliOnceEveryPattern, read: bengaliOnceEvery),
      bengaliRule(bengaliDailyWordPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      bengaliRule(bengaliCadenceAdjectivePattern, read: bengaliCadenceAdjective),
    ]
  }

  // MARK: - Words

  /// "প্রতি" or "প্রত্যেক": every.
  static let bengaliEvery = #"(?:প্রতি|প্রত্যেক)"#

  /// "প্রতিদিন", "প্রতি", "প্রত্যেক", "প্রত্যহ", or "রোজ": the words that may
  /// stand before a part of the day to make it every day's ("রোজ সকালে", "প্রতি
  /// সন্ধ্যায়"). The space inside "প্রতি দিন" is bounded because a lookbehind
  /// needs a bounded length.
  static let bengaliEveryOrDaily = #"(?:প্রতিদিন|প্রতি\s{1,3}দিন|প্রতি|প্রত্যেক|প্রত্যহ|রোজ)"#

  /// The words for every day, which may stand beside a span of weekdays
  /// ("সোমবার থেকে শুক্রবার প্রতিদিন").
  private static let bengaliEveryDayWords = #"(?:প্রতিদিন|প্রতি\s+দিন|প্রত্যহ|রোজ)"#

  /// Whether the words around a span of weekdays make it a habit: "প্রতি" before
  /// it ("প্রতি রবিবার থেকে বৃহস্পতিবার") or the words for every day before or
  /// after it ("রোজ সোমবার থেকে শুক্রবার", "সোমবার থেকে শুক্রবার প্রতিদিন"). The
  /// date-range rules leave such a span to the repeat rules.
  static func bengaliIsHabitSpan(_ match: Match) -> Bool {
    guard let range = Range(match.result.range, in: match.source) else { return false }
    let before = String(match.source[..<range.lowerBound])
    let after = String(match.source[range.upperBound...])
    return bengaliFinds(
      #"\#(bengaliStart)(?:\#(bengaliEvery)|\#(bengaliEveryDayWords))\s*$"#, in: before)
      || bengaliFinds(#"^\s+\#(bengaliEveryDayWords)\#(bengaliEnd)"#, in: after)
  }

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// stem: days, weeks, months, or years.
  private static func bengaliRepeat(unit: String, every: Int?) -> Repeat? {
    let key = bengaliKey(unit)
    if bengaliHasPrefix(key, bengaliKey("দিন")) {
      return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    }
    if bengaliHasPrefix(key, bengaliKey("সপ্তাহ")) || bengaliHasPrefix(key, bengaliKey("হপ্তা")) {
      return weekly(every: every, on: [])
    }
    if bengaliHasPrefix(key, bengaliKey("মাস")) { return monthly(every: every, on: nil) }
    if bengaliHasPrefix(key, bengaliKey("বছর")) || bengaliHasPrefix(key, bengaliKey("বৎসর")) {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    return nil
  }

  // MARK: - Weekdays

  /// A weekday with its ending as a pattern: "সোমবার", "সোমবারে".
  private static var bengaliWeekdayItem: String {
    #"(?:\#(bengaliWeekdayNames))(?:·ে)?"#
  }

  /// "প্রতি রবিবার থেকে বৃহস্পতিবার", "সোমবার থেকে শুক্রবার প্রতিদিন", "রোজ সোমবার
  /// থেকে শুক্রবার": every day of a span of weekdays. Groups: 1 the words for
  /// every day before the span, 2 "প্রতি" before it, 3 the first weekday, 4 the
  /// last, 5 the words for every day after it.
  private static var bengaliWeekdaySpanPattern: String {
    let daily = #"\#(bengaliEveryDayWords)\s+"#
    return
      #"\#(bengaliStart)(\#(daily))?(\#(bengaliEvery)\s*)?(\#(bengaliWeekdayNames))(?:·ে)?\s+(?:থেকে|হতে)\s+(\#(bengaliWeekdayNames))(?:·ে)?(?:\#(bengaliUntilWords))?+\#(bengaliEnd)(\s+\#(bengaliEveryDayWords)\#(bengaliEnd))?"#
  }

  /// A span runs from its first weekday to its last through the week's end. It
  /// is a habit only beside "প্রতি" or the words for every day: without them
  /// ("সোমবার থেকে শুক্রবার") it may as well be a week of work, which the
  /// date-range rules leave unread. A span from a day to itself is no span.
  private static func bengaliWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(3), let lastWord = match.group(4),
      let first = bengaliWeekdayIndex(firstWord), let last = bengaliWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(2) != nil || match.group(5) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "কর্মদিবসে", "প্রতি কর্মদিবস", "কাজের দিনে", "রোজ কাজের দিনে", "কাজের
  /// দিনগুলোতে": the working days, Monday to Friday. The noun phrases "কর্মদিবস"
  /// and "কাজের দিন" with no ending are read only after প্রতি, প্রত্যেক, প্রত্যহ,
  /// or রোজ: alone they name the days as often as they say on which of them a
  /// task repeats.
  private static var bengaliWorkdaysPattern: String {
    let days = #"(?:কর্মদিবস|কাজের\s+দিন)"#
    return
      #"\#(bengaliStart)(?:\#(bengaliEveryOrDaily)\s*\#(days)(?:·ে|·গুলোতে)?|\#(days)(?:·ে|·গুলোতে))\#(bengaliEnd)"#
  }

  /// "প্রতি সপ্তাহান্তে", "প্রতি উইকেন্ডে", "প্রতি শনিবার ও রবিবার": Saturday
  /// and Sunday.
  private static var bengaliWeekendRepeatPattern: String {
    #"\#(bengaliStart)\#(bengaliEvery)\s*\#(bengaliWeekendWords)\#(bengaliEnd)"#
  }

  /// "প্রতি সোমবার", "প্রতি সোমবারে", "প্রতি সোমবার ও বৃহস্পতিবার", "প্রতি
  /// সোমবার, বুধবার ও শুক্রবার", "প্রতি দ্বিতীয় সোমবারে", "প্রতি সপ্তাহে
  /// সোমবার", "সোমবার ও বৃহস্পতিবার প্রতি সপ্তাহে". Groups: 1 "দ্বিতীয়" after
  /// "প্রতি" (every other), 2 the weekdays after "প্রতি", 3 the weekdays after
  /// "প্রতি সপ্তাহে", 4 the weekdays before "প্রতি সপ্তাহে".
  private static var bengaliWeekdayRepeatPattern: String {
    let item = bengaliWeekdayItem
    let separator = #"(?:\s*,\s*(?:(?:ও|এবং)\s+)?|\s+(?:ও|এবং)\s+)"#
    let list = #"\#(item)(?:\#(separator)(?:\#(bengaliEvery)\s*)?\#(item)){0,6}"#
    let everyWeek = #"\#(bengaliEvery)\s*(?:সপ্তাহে|হপ্তায়)"#
    let every = #"\#(bengaliEvery)\s*(?:(দ্বিতীয়)\s+)?(\#(list))"#
    let afterWeek = #"\#(everyWeek)\s+(\#(list))"#
    let beforeWeek = #"(\#(list))\s+\#(everyWeek)"#
    return #"\#(bengaliStart)(?:\#(every)|\#(afterWeek)|\#(beforeWeek))\#(bengaliEnd)"#
  }

  private static func bengaliWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(2) ?? match.group(3) ?? match.group(4) ?? ""
    let days = bengaliWords(in: list).compactMap(bengaliWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: match.group(1) == nil ? nil : 2, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "প্রতি মাসের ৫ তারিখে", "প্রতি মাসে ৫ তারিখে", "প্রতি মাসের ১লা তারিখে",
  /// "প্রতি মাসের প্রথম তারিখে", "৫ তারিখে প্রতি মাসে". Groups: 1 and 2 the day
  /// of the month in each order, in digits with maybe an ordinal suffix, or
  /// "প্রথম".
  private static var bengaliMonthDayRepeatPattern: String {
    let month = #"(?:\#(bengaliEvery)\s*মাস(?:·(?:ের|ে))?)"#
    let day = #"\d{1,2}(?:·(?:ই|শে|লা|রা|ঠা))?|প্রথম"#
    let dayWord = #"\s*তারিখ(?:·ে)?"#
    return
      #"\#(bengaliStart)(?:\#(month)\s*(\#(day))\#(dayWord)|(\#(day))\#(dayWord)\s+\#(bengaliEvery)\s*মাসে)\#(bengaliEnd)"#
  }

  private static func bengaliMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = (match.group(1) ?? match.group(2)).map(bengaliPhrase) else { return nil }
    guard let day = text == bengaliKey("প্রথম") ? 1 : bengaliRuns(text).first.flatMap(number) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// The unit words of an interval, as a pattern: days, weeks, months, and
  /// years, with the locative that follows an interval ("প্রতি ২ দিনে") or
  /// without it.
  private static let bengaliUnits =
    "দিনে|দিন|সপ্তাহে|সপ্তাহ|হপ্তায়|হপ্তা|মাসে|মাস|বছরে|বছর|বৎসরে|বৎসর"

  /// "প্রতিদিন", "প্রতি দিন", "প্রতি সপ্তাহে", "প্রতি মাসে", "প্রতি বছর", "প্রতিবছর",
  /// "প্রতি ২ দিনে", "প্রতি দুই সপ্তাহে", "প্রতি ৩ মাসে", "প্রতি ৫ বছরে", "প্রতি
  /// পনেরো দিনে", "প্রতি দ্বিতীয় দিনে", "প্রতি অন্য দিন". An interval shorter than a
  /// day ("প্রতি ২ ঘণ্টায়") is no repeat. Groups: 1 the count, 2 "দ্বিতীয়" or
  /// "অন্য" (every other), 3 the unit. A genitive glued to the unit
  /// ("প্রতিদিনের কাজ", "প্রতি মাসের খরচ") makes the cadence an attribute of a
  /// noun and is left to the title.
  private static var bengaliIntervalRepeatPattern: String {
    #"\#(bengaliStart)\#(bengaliEvery)\s*(?:(\d{1,2}|\#(bengaliRoundCountWords))\s*|(দ্বিতীয়|অন্য)\s+)?(\#(bengaliUnits))\#(bengaliEnd)"#
  }

  private static func bengaliIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(3) else { return nil }
    var count = 1
    if match.group(2) != nil {
      count = 2
    } else if let text = match.group(1) {
      guard let value = number(text) ?? bengaliRoundCounts[bengaliPhrase(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    return bengaliRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "২ দিন অন্তর", "প্রতি ২ দিন অন্তর", "৩ মাস পর পর", "তিন সপ্তাহ পরপর", "এক
  /// দিন অন্তর", "একদিন পর পর": an amount of days, weeks, months, or years
  /// with "অন্তর" or "পর পর". A count of two or more is the interval itself;
  /// one is every other, since "একদিন অন্তর" counts the day that is skipped.
  /// Groups: 1 the count, 2 the unit.
  private static var bengaliSpacedRepeatPattern: String {
    #"\#(bengaliStart)(?:\#(bengaliEvery)\s*)?(\d{1,2}|\#(bengaliRoundCountWords))\s*(দিন|সপ্তাহ|হপ্তা|মাস|বছর|বৎসর)\s+(?:অন্তর|পর\s*পর)\#(bengaliEnd)"#
  }

  private static func bengaliSpacedRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1), let unit = match.group(2),
      let count = number(countText) ?? bengaliRoundCounts[bengaliPhrase(countText)], (1...99).contains(count)
    else { return nil }
    return bengaliRepeat(unit: unit, every: count == 1 ? 2 : count)
  }

  /// "দিনে একবার", "সপ্তাহে একবার", "মাসে একবার", "বছরে একবার", each maybe with
  /// "শুধু" or "মাত্র" and with "এক বার" or "একদিন" for "একবার". Group 1: the
  /// unit.
  private static var bengaliOnceEveryPattern: String {
    #"\#(bengaliStart)(দিনে|সপ্তাহে|হপ্তায়|মাসে|বছরে|বৎসরে)\s+(?:(?:শুধু|মাত্র)\s+)?(?:একবার|এক\s+বার|একদিন|এক\s+দিন)\#(bengaliEnd)"#
  }

  private static func bengaliOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).flatMap { bengaliRepeat(unit: $0, every: nil) }
  }

  // MARK: - Parts of the day and daily words

  /// "রোজ সকালে", "প্রতি সন্ধ্যায়", "প্রতিদিন রাতে", "প্রত্যেক ভোরে": every day.
  private static var bengaliPartOfDayRepeatPattern: String {
    #"\#(bengaliStart)\#(bengaliEveryOrDaily)\s+(?:\#(bengaliDayPartWords))\#(bengaliEnd)"#
  }

  /// "প্রতিদিন", "প্রতি দিন", "প্রত্যহ", "রোজ": every day. They say how a task
  /// repeats, and a genitive glued to them ("প্রতিদিনের কাজ") makes them an
  /// attribute of a noun, which the pattern does not list. "রোজা" and
  /// "রোজকার" are other words.
  private static var bengaliDailyWordPattern: String {
    #"\#(bengaliStart)\#(bengaliEveryDayWords)\#(bengaliEnd)"#
  }

  /// "দৈনিক", "সাপ্তাহিক", "মাসিক", "বার্ষিক": how a task repeats, only at the end
  /// of the line, before a colon or comma, with "ভিত্তিতে" or "হিসেবে" after it,
  /// or with "ভাবে" glued to it. They are ordinary adjectives too ("দৈনিক
  /// রিপোর্ট" is a daily report), and the end of the line is where they say
  /// how a task repeats. Group 1: the adjective.
  private static var bengaliCadenceAdjectivePattern: String {
    #"\#(bengaliStart)(দৈনিক|সাপ্তাহিক|মাসিক|বার্ষিক|বাৎসরিক)(?:·ভাবে|\s+(?:ভিত্তিতে|হিসেবে|হিসাবে)|(?=\s*[:：,，])|(?=\s*[।.!]?\s*$))\#(bengaliEnd)"#
  }

  private static func bengaliCadenceAdjective(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(bengaliPhrase) else { return nil }
    switch word {
    case bengaliKey("দৈনিক"): return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case bengaliKey("সাপ্তাহিক"): return weekly(every: nil, on: [])
    case bengaliKey("মাসিক"): return monthly(every: nil, on: nil)
    case bengaliKey("বার্ষিক"), bengaliKey("বাৎসরিক"): return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: return nil
    }
  }
}
