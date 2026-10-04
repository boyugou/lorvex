import Foundation

extension LorvexCaptureVocabulary {
  // The Persian repeat rules. The vocabulary's other words are in ``persian``.

  /// The repeat rules, in the order they are tried: a span of weekdays beside
  /// the words for every day, and the weekdays after "هر" or in the plural,
  /// which would leave "دوشنبه" in the title; then "every other", a part of
  /// the day (before the interval, so "هر روز صبح" takes its "صبح"), an
  /// interval, "once a week", and the adverbs.
  static var persianRepeatRules: [Rule<Repeat>] {
    [
      persianRule(persianWeekdaySpanPattern, read: persianWeekdaySpanRepeat),
      persianRule(persianWeekdayRepeatPattern, read: persianWeekdayRepeat),
      persianRule(persianEveryOtherPattern, read: persianEveryOther),
      persianRule(persianPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      persianRule(persianIntervalRepeatPattern, read: persianIntervalRepeat),
      persianRule(persianOncePerPattern, read: persianOncePer),
      persianRule(persianAdverbPattern, read: persianAdverbRepeat),
    ]
  }

  // MARK: - Words

  /// The words for every day, as a pattern without groups: "هر روز", "هر روزه",
  /// "همه روزه", "روزانه".
  static let persianEveryDayWords = #"(?:هر\s*روزه?|همه\s*روزه|روزانه)"#

  /// The unit words of an interval, as a pattern: days, weeks, months, and
  /// years.
  private static let persianUnits = "روز|هفته|ماه|سال"

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func persianRepeat(unit: String, every: Int?) -> Repeat? {
    switch persianKey(unit) {
    case "روز": Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "هفته": weekly(every: every, on: [])
    case "ماه": monthly(every: every, on: nil)
    case "سال": Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: nil
    }
  }

  // MARK: - Weekdays

  /// A weekday as an item of a list, with the plural ending ("دوشنبه‌ها").
  private static var persianWeekdayItem: String { #"(?:\#(persianWeekdayNames))(?:‌ها)?"# }

  /// The words between the weekdays of a list: a comma or "و" ("دوشنبه و
  /// پنجشنبه", "دوشنبه، چهارشنبه و جمعه").
  private static let persianListSeparator = #"(?:\s*[،,]\s*(?:و\s+)?|\s+و\s+)"#

  /// "از شنبه تا چهارشنبه هر روز", "هر روز از دوشنبه تا جمعه", "روزهای شنبه تا
  /// چهارشنبه", "روزانه دوشنبه تا جمعه": every day of a span of weekdays. Groups:
  /// 1 the word before the span that makes it a habit ("هر", "هر روز",
  /// "روزهای", "روزانه"), 2 the first weekday, 3 the last, 4 the words for every
  /// day after it.
  private static var persianWeekdaySpanPattern: String {
    let item = #"(?:\#(persianWeekdayNames))"#
    return
      #"\#(persianStart)(?:(\#(persianEveryDayWords)|روزهای|هر)\s*[،,]?\s+)?(?:از\s+)?(\#(item))\s+(?:تا|الی)\s+(\#(item))\#(persianEnd)(?:\s+(\#(persianEveryDayWords))\#(persianEnd))?"#
  }

  /// A span runs from its first weekday to its last through the week's end, so
  /// "از شنبه تا چهارشنبه" is Saturday, Sunday, Monday, Tuesday, and Wednesday.
  /// It is a habit only beside "هر", "روزهای", or the words for every day:
  /// without them ("از دوشنبه تا جمعه") it may as well be a week of work. A
  /// span from a day to itself is no span.
  private static func persianWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(2), let lastWord = match.group(3),
      let first = persianWeekdayIndex(firstWord), let last = persianWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(4) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "هر دوشنبه", "هر روز دوشنبه", "هر هفته دوشنبه", "هر دوشنبه و پنجشنبه", "هر
  /// صبح جمعه", "روزهای دوشنبه و چهارشنبه", "دوشنبه‌ها", "همه دوشنبه‌ها و
  /// پنجشنبه‌ها", "دوشنبه و پنجشنبه هر هفته". Groups: 1 the weekdays after "هر",
  /// 2 the weekdays after "روزهای", 3 the plural weekdays, 4 the weekdays before
  /// "هر هفته". A part of the day before the weekday ("هر صبح جمعه") is part of
  /// the phrase, except the night: "هر شب جمعه" is every Thursday night, which no
  /// weekday names.
  private static var persianWeekdayRepeatPattern: String {
    let item = persianWeekdayItem
    let list = #"\#(item)(?:\#(persianListSeparator)(?:هر\s+)?\#(item)){0,6}"#
    let plural = #"(?:\#(persianWeekdayNames))‌ها"#
    let plurals = #"\#(plural)(?:\#(persianListSeparator)\#(plural)){0,6}"#
    let part = #"(?:\#(persianPartBeforeDayWords)\s+)?"#
    let every = #"هر\s+(?:هفته\s+)?\#(part)(?:روز\s+)?(\#(list))"#
    let days = #"(?:(?:همه|تمام)\s+)?روزهای\s+(\#(list))"#
    let pluralDays = #"(?:(?:همه|تمام)\s+)?(\#(plurals))"#
    let beforeEveryWeek = #"(\#(list))\s+هر\s+هفته"#
    return #"\#(persianStart)(?:\#(every)|\#(days)|\#(pluralDays)|\#(beforeEveryWeek))\#(persianEnd)"#
  }

  private static func persianWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) ?? ""
    let days = persianWeekdays(in: list)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Intervals

  /// "یک روز در میان", "روز در میان", "هر هفته در میان", "یک ماه در میان", "یک
  /// دوشنبه در میان": every other day, week, month, or weekday. Groups: 1 the
  /// unit, 2 the weekday.
  private static var persianEveryOtherPattern: String {
    #"\#(persianStart)(?:هر\s+)?(?:(?:یک|یه)\s+)?(?:(\#(persianUnits))|(\#(persianWeekdayNames)))\s+در\s*میان\#(persianEnd)"#
  }

  private static func persianEveryOther(_ match: Match) -> Repeat? {
    if let unit = match.group(1) { return persianRepeat(unit: unit, every: 2) }
    guard let weekday = match.group(2).flatMap(persianWeekdayIndex) else { return nil }
    return weekly(every: 2, on: [weekday])
  }

  /// "هر روز", "هر هفته", "هر ماه", "هر سال", "هر ۲ روز", "هر دو هفته", "هر سه
  /// ماه", "هر ۵ سال", "هر پانزده روز", each maybe followed by "یک بار" ("هر دو
  /// روز یک بار"). An interval shorter than a day ("هر ۲ ساعت") is no repeat.
  /// Groups: 1 the count, 2 the unit.
  private static var persianIntervalRepeatPattern: String {
    #"\#(persianStart)هر\s+(?:(\d{1,2}|\#(persianCountWords))\s+)?(\#(persianUnits))(?:\s+یک‌بار)?\#(persianEnd)"#
  }

  private static func persianIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(2).map(persianKey) else { return nil }
    var count = 1
    if let text = match.group(1) {
      guard let value = number(text) ?? persianCounts[persianKey(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    if unit == "ماه", persianNamesDayOfMonth(match) { return nil }
    return persianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// Whether the words around "هر ماه" name a day of the month ("هر ماه ۵ام",
  /// "هر ماه روز ۵", "۵ام هر ماه", "روز ۱۵ هر ماه"). Persian speakers count the
  /// days of a month in the Solar Hijri calendar, whose months are not the
  /// Gregorian months a monthly repeat keeps, so the line stays as typed.
  private static func persianNamesDayOfMonth(_ match: Match) -> Bool {
    persianFinds(
      #"^\s+(?:روز\s+\d{1,2}\#(persianNoMoreDigits)|\d{1,2}\s*(?:ام|م)\#(persianEnd))"#, in: persianTextAfter(match))
      || persianFinds(#"(?:^|\s)(?:\d{1,2}\s*(?:ام|م)?|روز\s+\d{1,2})\s*$"#, in: persianTextBefore(match))
  }

  /// "هفته‌ای یک بار", "ماهی یک بار", "سالی یک بار", "روزی یک بار", "ماهی فقط یک
  /// بار", "دو هفته یک بار", "۳ ماه یک بار". Groups: 1 the unit of "هفته‌ای یک
  /// بار", 2 the count and 3 the unit of "دو هفته یک بار".
  private static var persianOncePerPattern: String {
    let once = #"(?:فقط\s+|تنها\s+)?یک‌بار"#
    return
      #"\#(persianStart)(?:(\#(persianUnits))(?:‌ای|ی)\s+\#(once)|(\d{1,2}|\#(persianCountWords))\s+(\#(persianUnits))\s+یک‌بار)\#(persianEnd)"#
  }

  private static func persianOncePer(_ match: Match) -> Repeat? {
    if let unit = match.group(1) { return persianRepeat(unit: unit, every: nil) }
    guard let unit = match.group(3), let text = match.group(2),
      let count = number(text) ?? persianCounts[persianKey(text)], (1...99).contains(count)
    else { return nil }
    return persianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  // MARK: - Parts of the day and adverbs

  /// "هر صبح", "هر روز صبح", "هر شب", "هر عصر", "صبح‌ها", "شب‌ها": every day. A
  /// part of the day before a weekday ("هر شب جمعه") is that day's, not a
  /// daily one.
  private static var persianPartOfDayRepeatPattern: String {
    let weekdayAfter = #"(?!\s+(?:روز\s+)?(?:\#(persianWeekdayNames))\#(persianEnd))"#
    return
      #"\#(persianStart)(?:هر\s+(?:روز\s+)?\#(persianPartOfDayWords)|\#(persianPartOfDayWords)‌ها)\#(persianEnd)\#(weekdayAfter)"#
  }

  /// "روزانه", "هر روزه", "هفتگی", "ماهانه", "سالانه" at the start of the line or
  /// at its end after a comma: the adverb says how a task repeats ("روزانه ۳۰
  /// دقیقه ورزش"), and after the task's noun the same word is its adjective
  /// ("گزارش روزانه", "جلسه هفتگی"), which names the title. The end of the line
  /// may hold the commas and the full stop that a phrase read before the
  /// adverb leaves behind ("مرور، روزانه، ساعت ۸ شب"). Groups: 1 the adverb
  /// that opens the line, 2 the adverb that ends it.
  private static var persianAdverbPattern: String {
    let words = #"روزانه|هر\s*روزه|همه\s*روزه|هفتگی|ماهانه|ماهیانه|سالانه|سالیانه"#
    return
      #"^\s*(\#(words))\#(persianEnd)|(?<=[،,;؛]\s{0,3})(\#(words))\#(persianEnd)(?=[\s،,;؛.!؟?]*$)"#
  }

  private static func persianAdverbRepeat(_ match: Match) -> Repeat? {
    switch (match.group(1) ?? match.group(2)).map(persianKey) {
    case "روزانه", "هرروزه", "همهروزه": Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case "هفتگی": weekly(every: nil, on: [])
    case "ماهانه", "ماهیانه": monthly(every: nil, on: nil)
    case "سالانه", "سالیانه": Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: nil
    }
  }
}
