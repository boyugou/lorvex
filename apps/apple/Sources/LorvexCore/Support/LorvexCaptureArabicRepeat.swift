import Foundation

extension LorvexCaptureVocabulary {
  // The Arabic repeat rules. The vocabulary's other words are in ``arabic``.

  /// The repeat rules, in the order they are tried: the span of weekdays, a day
  /// of the month, and the weekdays before every day and every week, which
  /// would leave "الخميس" or the day's number in the title; then an interval,
  /// "once a week", a part of the day, and the adverbs. Weekdays and intervals
  /// take a leading "مرة" ("once"), so that "مرة كل أسبوعين" leaves no "مرة"
  /// in the title.
  static var arabicRepeatRules: [Rule<Repeat>] {
    [
      arabicRule(arabicWeekdaySpanPattern, read: arabicWeekdaySpanRepeat),
      arabicRule(arabicMonthDayRepeatPattern, read: arabicMonthDayRepeat),
      arabicRule(arabicWeekdayRepeatPattern, read: arabicWeekdayRepeat),
      arabicRule(arabicIntervalRepeatPattern, read: arabicIntervalRepeat),
      arabicRule(arabicOnceEveryPattern, read: arabicOnceEvery),
      arabicRule(#"\#(arabicStart)كل\s+(?:صباح|مساء|ليلة|فجر)\#(arabicEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily))
      },
      arabicRule(arabicAdverbPattern, read: arabicAdverbRepeat),
    ]
  }

  // MARK: - Words

  /// A weekday with or without the article, Sunday only with it.
  private static var arabicWeekdayItem: String {
    #"(?:(?:ال)?(?:\#(arabicWeekdayNamesWithoutSunday))|الأحد)"#
  }

  /// The "مرة" ("once") that may open "كل" in "مرة كل أسبوعين" and "مرة كل
  /// جمعة".
  private static let arabicOnce = #"(?:مرة\s+(?:واحدة\s+)?)?"#

  /// The unit words of an interval, as a pattern: days, weeks, months, and
  /// years, each in its singular (after a count of 11 or more or with none),
  /// its dual ("يومين" is two days), its plural (3 to 10), and its accusative
  /// ("يوماً").
  private static let arabicUnits =
    "يومين|يومان|يوما|يوم|أيام|أسبوعين|أسبوعان|أسبوعا|أسبوع|أسابيع|شهرين|شهران|شهرا|شهر|أشهر|شهور|سنتين|سنتان|سنة|سنين|سنوات|عامين|عامان|عاما|عام|أعوام"

  /// The units that already say two.
  private static let arabicDualUnits: Set<String> = [
    "يومين", "يومان", "اسبوعين", "اسبوعان", "شهرين", "شهران", "سنتين", "سنتان", "عامين", "عامان",
  ]

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func arabicRepeat(unit: String, every: Int?) -> Repeat? {
    if ["اسبوع", "اسبوعا", "اسبوعين", "اسبوعان", "اسابيع"].contains(unit) { return weekly(every: every, on: []) }
    if ["شهر", "شهرا", "شهرين", "شهران", "اشهر", "شهور"].contains(unit) { return monthly(every: every, on: nil) }
    if ["سنه", "سنين", "سنوات", "سنتين", "سنتان", "عام", "عاما", "عامين", "عامان", "اعوام"].contains(unit) {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  /// The repeat of "كل 3 أيام", "كل يومين", "كل ثلاثة أسابيع": `countText` is
  /// the count as written (nil for none), `unit` the unit word.
  private static func arabicRepeat(count countText: String?, unit: String) -> Repeat? {
    let count: Int
    if arabicDualUnits.contains(unit) {
      count = 2
    } else if let countText {
      guard let value = number(countText) ?? arabicCounts[countText] else { return nil }
      count = value
    } else {
      count = 1
    }
    guard (1...99).contains(count) else { return nil }
    return arabicRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  // MARK: - Weekdays

  /// "كل يوم من الأحد إلى الخميس": every day of a span of weekdays. Groups: 1
  /// the first weekday, 2 the last.
  private static var arabicWeekdaySpanPattern: String {
    #"\#(arabicStart)كل\s+يوم\s+من\s+(\#(arabicWeekdayItem))\s+(?:إلى|حتى)\s+(\#(arabicWeekdayItem))\#(arabicEnd)"#
  }

  /// A span runs from its first weekday to its last through the week's end,
  /// so "من السبت إلى الأربعاء" is Saturday, Sunday, Monday, Tuesday, and
  /// Wednesday. A span from a day to itself is no span.
  private static func arabicWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let first = match.group(1).map(arabicBare).flatMap(arabicWeekdayIndex),
      let last = match.group(2).map(arabicBare).flatMap(arabicWeekdayIndex), first != last
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "كل اثنين", "كل يوم اثنين", "كل يوم الخميس", "كل اثنين وخميس", "كل اثنين،
  /// أربعاء وجمعة", and "الاثنين والخميس من كل أسبوع". The conjunction و
  /// attaches to the next weekday ("وخميس"), which may carry the article
  /// ("والخميس"). Groups: 1 the weekdays after كل, 2 the weekdays before "من كل
  /// أسبوع". "كل أحد" means everyone, so Sunday stands only with its article.
  private static var arabicWeekdayRepeatPattern: String {
    let separator = #"(?:\s*[،,]\s*(?:و\s*)?|\s+و\s*)"#
    let list = #"\#(arabicWeekdayItem)(?:\#(separator)\#(arabicWeekdayItem)){0,6}"#
    return
      #"\#(arabicStart)(?:\#(arabicOnce)كل\s+(?:يوم\s+)?(\#(list))|(\#(list))\s+من\s+كل\s+أسبوع)\#(arabicEnd)"#
  }

  private static func arabicWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = arabicBare(match.group(1) ?? match.group(2) ?? "")
    let days = list.split(whereSeparator: { !$0.isLetter }).compactMap { word -> Int? in
      let token = String(word)
      return arabicWeekdayIndex(token) ?? (token.hasPrefix("و") ? arabicWeekdayIndex(String(token.dropFirst())) : nil)
    }
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "5 من كل شهر", "في 5 من كل شهر", "يوم 5 من كل شهر". Group 1: the day of
  /// the month.
  private static var arabicMonthDayRepeatPattern: String {
    #"\#(arabicStart)(?:(?:في\s+)?(?:يوم\s+)?)(\d{1,2})\s+من\s+كل\s+شهر\#(arabicEnd)"#
  }

  private static func arabicMonthDayRepeat(_ match: Match) -> Repeat? {
    match.group(1).flatMap(number).flatMap { monthly(every: nil, on: $0) }
  }

  /// "كل يوم", "كل أسبوع", "كل شهر", "كل سنة", "كل عام", "كل يومين", "كل 3 أيام",
  /// "كل ثلاثة أسابيع", "كل 15 يوماً", "كل شهرين", "كل 5 سنوات", and each of
  /// them after "مرة" ("مرة كل أسبوعين"). "كل عام وأنتم بخير" (the greeting)
  /// is no repeat. Groups: 1 the count, 2 the unit.
  private static var arabicIntervalRepeatPattern: String {
    let greeting = #"(?!\s+و(?:أنتم|أنت|أنتما|أنتن)\#(arabicEnd))"#
    return
      #"\#(arabicStart)\#(arabicOnce)كل\s+(?:(\d{1,2}|\#(arabicCountWords))\s+)?(\#(arabicUnits))\#(arabicEnd)\#(greeting)"#
  }

  /// "كل يوم" before a weekday ("كل يوم أحد") or before "من" ("كل يوم من
  /// الشهر") names a day of the week or of the month, not every day.
  private static func arabicIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(2).map(arabicPhrase) else { return nil }
    if match.group(1) == nil, unit == "يوم",
      let next = wordAfter(match).map(arabicBare), next == "من" || arabicWeekdayIndex(next) != nil
    {
      return nil
    }
    return arabicRepeat(count: match.group(1).map(arabicPhrase), unit: unit)
  }

  /// "مرة في الأسبوع", "مرة في الشهر", "مرة واحدة في السنة", "مرة في اليوم".
  /// Group 1: the unit.
  private static var arabicOnceEveryPattern: String {
    #"\#(arabicStart)مرة\s+(?:واحدة\s+)?في\s+(?:ال)?(يوم|أسبوع|شهر|سنة|عام)\#(arabicEnd)"#
  }

  private static func arabicOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).map(arabicPhrase).flatMap { arabicRepeat(unit: $0, every: nil) }
  }

  // MARK: - Adverbs

  /// "يومياً", "أسبوعياً", "شهرياً", "سنوياً" at the end of the line, where a part
  /// of the day may follow them ("يومياً صباحاً"). An adverb says how a task
  /// repeats at the end of the line; the adjective ("تقرير يومي") is a title.
  /// Groups: 1 daily, 2 weekly, 3 monthly, 4 yearly.
  private static var arabicAdverbPattern: String {
    #"\#(arabicStart)(?:(يوميا)|(أسبوعيا)|(شهريا)|(سنويا))(?:\s+\#(arabicPartOfDayWords))?(?=\s*$)"#
  }

  private static func arabicAdverbRepeat(_ match: Match) -> Repeat? {
    if match.group(1) != nil { return Repeat(rule: TaskRecurrenceRule(freq: .daily)) }
    if match.group(2) != nil { return weekly(every: nil, on: []) }
    if match.group(3) != nil { return monthly(every: nil, on: nil) }
    return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
  }
}
