import Foundation

extension LorvexCaptureVocabulary {
  // The Arabic day rules: the planned day, the due day, written dates, and
  // date ranges. The vocabulary's other words are in ``arabic``.

  // MARK: - Names

  /// Each weekday's names without the article, Sunday first, as the reading
  /// form reads them. "أحد" stands only with the article ("الأحد"): without
  /// it the word means "someone" ("كل أحد" is everyone, "يوم أحد" the battle).
  private static let arabicWeekdayStems: [[String]] = [
    ["أحد"], ["اثنين", "إثنين", "اتنين"], ["ثلاثاء", "ثلاثا"], ["أربعاء", "أربعا"], ["خميس"], ["جمعة"], ["سبت"],
  ].map { $0.map(arabicForMatching) }

  /// The weekday names as a pattern, longest first, with and without Sunday.
  static let arabicWeekdayNames = alternation(of: arabicWeekdayStems.flatMap { $0 })
  static let arabicWeekdayNamesWithoutSunday = alternation(of: arabicWeekdayStems.dropFirst().flatMap { $0 })

  /// The weekday a word names, with or without its article, 0 = Sunday.
  static func arabicWeekdayIndex(_ word: String) -> Int? {
    let bare = word.hasPrefix("ال") ? String(word.dropFirst(2)) : word
    return arabicWeekdayStems.firstIndex { $0.contains(bare) }
  }

  /// Each month's Gregorian names, January first: the names the Gulf and
  /// Egypt use (يناير), the Levant and Iraq (كانون الثاني), and the Maghreb
  /// (جانفي). The Hijri months are not here: a Hijri date is not read.
  private static let arabicMonths: [[String]] = [
    ["يناير", "كانون الثاني", "جانفي"], ["فبراير", "شباط", "فيفري"], ["مارس", "آذار"],
    ["أبريل", "نيسان", "أفريل"], ["مايو", "أيار", "ماي"], ["يونيو", "يونيه", "حزيران", "جوان"],
    ["يوليو", "يوليه", "تموز", "جويلية"], ["أغسطس", "آب", "أوت"], ["سبتمبر", "أيلول"],
    ["أكتوبر", "تشرين الأول"], ["نوفمبر", "تشرين الثاني"], ["ديسمبر", "كانون الأول"],
  ].map { $0.map(arabicForMatching) }

  /// The month a name in the reading form names, 0 = January.
  private static let arabicMonthIndex: [String: Int] = {
    var index: [String: Int] = [:]
    for (month, names) in arabicMonths.enumerated() {
      for name in names { index[name] = month }
    }
    return index
  }()

  /// The words that make a weekday or a week the coming one.
  private static let arabicNextWordList = ["القادم", "القادمة", "المقبل", "المقبلة", "الجاي", "الجاية", "التالي", "التالية"]
  private static let arabicNextWordSet = Set(arabicNextWordList.map(arabicForMatching))
  static let arabicNextWords = alternation(of: arabicNextWordList)

  /// What may not follow a weekday the line means as a day to come: the past
  /// ("الخميس الماضي" is last Thursday).
  private static let arabicNotPast =
    #"(?!\s+(?:الماضي|الماضية|السابق|السابقة|الفائت|الفائتة|الفايت|الفايتة))"#

  /// The words before a day phrase that make it no planned day: a bound or a
  /// moment relative to something else ("بعد", "منذ"), a stretch of time ("كل
  /// اليوم", "طوال اليوم", "نهاية الأسبوع القادم"), a "من" that starts a range
  /// ("من الخميس"), or "ليلة" ("ليلة الجمعة" is Thursday night).
  private static let arabicNotADayAfter: Set<String> = [
    "نهايه", "بدايه", "منتصف", "اخر", "اول", "طوال", "خلال", "كل", "ليله", "في", "على", "من",
  ]

  // MARK: - Dates

  /// "5 مارس", "5 من مارس", "5 من شهر مارس", "5 مارس 2027", "5 مارس 2027م",
  /// "5 كانون الثاني": a day number before a Gregorian month name, maybe with a
  /// year. The month name needs its number ("مارس" is also a verb), a date
  /// written in digits only ("5/3") is not read, and neither is a Hijri date.
  static var arabicMonthDatePattern: String {
    let names = alternation(of: arabicMonths.flatMap { $0 }.map { $0.replacingOccurrences(of: " ", with: #"\s+"#) })
    return
      #"\d{1,2}(?:\s+من)?(?:\s+شهر)?\s+(?:\#(names))(?:\s+(?:19|20)\d{2}(?:\s*م(?![\p{Arabic}\p{M}\x{0640}]))?)?"#
  }

  /// A written-out date: "5 مارس", "في 5 مارس 2027". The words are a phrase as
  /// ``arabicPhrase(_:)`` leaves it. A "ل" attached to the day number ("ل5
  /// مارس") is not part of it.
  static func arabicDate(_ words: String) -> ExplicitDate? {
    let tokens = words.split(separator: " ").map(String.init)
    func dayNumber(_ token: String) -> Int? {
      number(token.hasPrefix("ل") ? String(token.dropFirst()) : token)
    }
    guard let dayIndex = tokens.firstIndex(where: { dayNumber($0) != nil }), let day = dayNumber(tokens[dayIndex])
    else { return nil }
    var index = dayIndex + 1
    while index < tokens.count, tokens[index] == "من" || tokens[index] == "شهر" { index += 1 }
    guard index < tokens.count else { return nil }
    let month: Int
    if index + 1 < tokens.count, let two = arabicMonthIndex["\(tokens[index]) \(tokens[index + 1])"] {
      month = two
      index += 2
    } else if let one = arabicMonthIndex[tokens[index]] {
      month = one
      index += 1
    } else {
      return nil
    }
    let year = index < tokens.count ? tokens[index].wholeMatch(of: /(?:19|20)\d{2}/).flatMap { number($0.output) } : nil
    return ExplicitDate(year: year, month: month + 1, day: day)
  }

  // MARK: - Planned day

  /// Group 1: the day, with the words that introduce it.
  ///
  /// Today ("اليوم", "الليلة", "هذا المساء"), tomorrow ("غداً", "بكرة"), the day
  /// after ("بعد غد"), a number of days or weeks ("بعد 3 أيام", "بعد يومين",
  /// "بعد أسبوع"), next week ("الأسبوع القادم"), a weekday after "يوم", "في",
  /// or "ليوم" ("يوم الخميس"), with "هذا" ("هذا الخميس"), after a part of the
  /// day ("مساء الخميس"), or with a word for next ("الخميس القادم"), and a
  /// date ("5 مارس", "في 5 مارس"), each maybe with a part of the day after it.
  static var arabicWhenPattern: String {
    let part = #"(?:\s+\#(arabicPartOfDayWords))?"#
    let weekday = #"ال(?:\#(arabicWeekdayNames))"#
    let demonstrative = #"(?:هذا|هذه)"#
    let relative =
      #"بعد\s+(?:(?:\d{1,3}|\#(arabicCountWords))\s+(?:يوما|يوم|أيام|أسبوعا|أسبوع|أسابيع)|يومين|يومان|أسبوعين|أسبوعان|(?:يوم|أسبوع)\s+واحد|أسبوع)(?:\s+من\s+الآن)?(?!\s+من\#(arabicEnd))"#
    let alternatives = [
      #"(?:\#(demonstrative)\s+ال(?:صباح|مساء|ليلة)|الليلة|اليوم(?!\s+ال(?!ساعة|مساء|صباح|ظهر|عصر|ليل|فجر)))\#(part)"#,
      #"(?:غدا|بكرة|بكرا)\#(part)"#,
      #"بعد\s+(?:غد|غدا|بكرة|بكرا)"#,
      relative,
      #"(?:في\s+)?(?:ال)?أسبوع\s+(?:\#(arabicNextWords))"#,
      #"(?:(?:(?:في\s+)?يوم|ليوم|في)\s+(?:\#(demonstrative)\s+)?|\#(demonstrative)\s+|(?:صباح|ظهر|عصر|مساء|فجر)\s+(?:يوم\s+)?)\#(weekday)\#(arabicNotPast)(?:\s+(?:\#(arabicNextWords)))?\#(part)|\#(weekday)\#(arabicNotPast)\s+(?:\#(arabicNextWords))\#(part)"#,
      #"(?:ل\x{0640}?\s*|(?:(?:في\s+)?يوم|بتاريخ|ليوم|في|من)\s+)?\#(arabicMonthDatePattern)"#,
    ]
    return #"\#(arabicStart)(\#(alternatives.joined(separator: "|")))\#(arabicEnd)"#
  }

  static func arabicWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1) else { return nil }
    if let before = arabicWordBefore(match), arabicBoundWords.contains(before) || arabicNotADayAfter.contains(before) {
      return nil
    }
    return arabicDay(phrase, in: match)
  }

  // MARK: - Due day

  /// "قبل الخميس", "حتى غداً", "بحلول 5 مارس", "قبل نهاية اليوم", "لغاية يوم
  /// الخميس القادم", "الموعد النهائي: الخميس", "موعد التسليم 5 مارس", "في موعد
  /// أقصاه الخميس". Group 1: the day.
  static var arabicDuePattern: String {
    let weekday = #"(?:(?:ال)?(?:\#(arabicWeekdayNamesWithoutSunday))|الأحد)"#
    let alternatives = [
      #"(?:نهاية\s+)?(?:يوم\s+)?\#(weekday)\#(arabicNotPast)(?:\s+(?:\#(arabicNextWords)))?"#,
      #"(?:يوم\s+)?\#(arabicMonthDatePattern)"#,
      #"(?:نهاية\s+)?(?:غدا|بكرة|بكرا)"#,
      #"بعد\s+(?:غد|غدا|بكرة|بكرا)"#,
      #"نهاية\s+اليوم"#,
    ]
    let words =
      #"قبل|حتى|بحلول|لغاية|(?:في\s+)?موعد\s+أقصاه|(?:ال)?موعد\s+(?:ال)?(?:نهائي|تسليم)|آخر\s+موعد|(?:ال)?أجل\s+(?:ال)?نهائي|تاريخ\s+(?:ال)?(?:تسليم|استحقاق)|استحقاق"#
    return
      #"\#(arabicStart)(?:\#(words))(?:\s*[:：]\s*|\s+)(?:في\s+)?(\#(alternatives.joined(separator: "|")))\#(arabicEnd)"#
  }

  static func arabicDue(_ match: Match) -> Day? {
    match.group(1).flatMap { arabicDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The day a phrase names. A weekday means the next such day, a full week
  /// ahead when it names today, and "هذا" makes it this week's, today when it
  /// names today.
  private static func arabicDay(_ phrase: String, in match: Match) -> Day? {
    let words = arabicPhrase(phrase)
    if let date = arabicDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = words.split(separator: " ").map(String.init)
    let isEvening = words.contains("مساء") || words.contains("ليل")
    if tokens.first == "بعد" {
      let rest = tokens.dropFirst().filter { $0 != "من" && $0 != "الان" }
      if rest.count == 1, ["غد", "غدا", "بكره", "بكرا"].contains(rest[0]) { return Day(offset: 2) }
      return arabicRelativeOffset(Array(rest)).map { Day(offset: $0) }
    }
    if tokens.contains(where: { ["غدا", "بكره", "بكرا"].contains($0) }) {
      return Day(offset: 1, isEvening: isEvening)
    }
    if let weekday = tokens.lazy.compactMap(arabicWeekdayIndex).first {
      let isNext = tokens.contains(where: arabicNextWordSet.contains)
      let isThis = tokens.contains("هذا") || tokens.contains("هذه")
      let days =
        isThis && !isNext
        ? weekdayDelta(weekday, todayWeekday: match.todayWeekday)
        : comingWeekdayOffset(weekday, todayWeekday: match.todayWeekday)
      return Day(offset: days, isEvening: isEvening)
    }
    let isDemonstrative = tokens.first == "هذا" || tokens.first == "هذه"
    if tokens.contains("اليوم") || tokens.contains("الليله")
      || (isDemonstrative && tokens.count == 2 && ["الصباح", "المساء"].contains(tokens[1]))
    {
      return Day(offset: 0, isEvening: isEvening)
    }
    if tokens.contains(where: { $0 == "اسبوع" || $0 == "الاسبوع" }) { return Day(offset: 7) }
    return nil
  }

  /// The days from today of "بعد 3 أيام", "بعد يومين", "بعد أسبوع", "بعد يوم
  /// واحد", "بعد 3 أسابيع", from the words after "بعد" without "من الآن": a
  /// count and a unit, a dual, "أسبوع" alone, or a singular unit with "واحد"
  /// ("one"). "يوم" alone is no count ("بعد يوم" is also "after a day of").
  private static func arabicRelativeOffset(_ words: [String]) -> Int? {
    let isOne = words.last == "واحد"
    let tokens = isOne ? Array(words.dropLast()) : words
    guard let unit = tokens.last else { return nil }
    let count: Int
    switch unit {
    case "يومين", "يومان", "اسبوعين", "اسبوعان": count = 2
    default:
      if tokens.count == 2, !isOne, let value = number(tokens[0]) ?? arabicCounts[tokens[0]] {
        count = value
      } else if tokens.count == 1, unit == "اسبوع" || (isOne && unit == "يوم") {
        count = 1
      } else {
        return nil
      }
    }
    return count * (unit.hasPrefix("اسبوع") || unit.hasPrefix("اسابيع") ? 7 : 1)
  }

  // MARK: - Date range

  /// "من 3 إلى 5 مارس", "من 30 مارس إلى 2 أبريل", "من 3 مارس حتى 5 مارس", "بين 3
  /// و5 مارس", "3-5 مارس", "3–5 مارس", each maybe with a year after the end.
  /// The start is a date or a day alone ("3"); the end is a date. Groups: 1 the
  /// word that opens the range, if any (من, بين), 2 the start, 3 a dash between
  /// the sides, 4 إلى, حتى, or و between them, 5 the end.
  static var arabicDateRangePattern: String {
    let bare = #"\d{1,2}\#(arabicNoMoreDigits)"#
    return
      #"\#(arabicStart)(?:(من|بين)\s+)?(\#(arabicMonthDatePattern)|\#(bare))(?:\s*([-–—])\s*|(?:\s+|(?<=\d))(إلى\s+|حتى\s+|و\s*))(\#(arabicMonthDatePattern)|\#(bare))\#(arabicDateEnd)"#
  }

  static func arabicDateRange(_ match: Match) -> DayRangeReading? {
    // "إلى" and "حتى" join the sides only after "من", and "و" only after "بين":
    // "3 إلى 5 مارس" and "من 3 و5 مارس" stay in the title.
    if let word = match.group(4).map(arabicPhrase) {
      let lead = match.group(1).map(arabicPhrase)
      guard word == "و" ? lead == "بين" : lead == "من" else { return nil }
    }
    return slavicDateRange(match, side: arabicRangeDate)
  }

  /// A side of a date range: a date ("5 مارس") or a day alone ("5"), which has
  /// no month.
  private static func arabicRangeDate(_ text: String) -> ExplicitDate? {
    let words = arabicPhrase(text)
    if let date = arabicDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }
}
