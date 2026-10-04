import Foundation

extension LorvexCaptureVocabulary {
  // The Persian day rules: the planned day, the due day, written dates in the
  // Solar Hijri and the Gregorian calendar, and date ranges. The vocabulary's
  // other words are in ``persian``.

  // MARK: - Names

  /// Each weekday's names, Sunday first, with a zero-width non-joiner where a
  /// name is a compound (which a typed name may also separate with a space or
  /// nothing). "شنبه" is Saturday; "یکشنبه" is Sunday. "آدینه" is Friday.
  private static let persianWeekdayNameList: [[String]] = [
    ["یک‌شنبه"], ["دو‌شنبه"], ["سه‌شنبه", "سشنبه"], ["چهار‌شنبه", "چار‌شنبه"], ["پنج‌شنبه", "پن‌شنبه"],
    ["جمعه", "آدینه"], ["شنبه"],
  ]

  private static let persianWeekdayIndexByKey: [String: Int] = {
    var index: [String: Int] = [:]
    for (weekday, names) in persianWeekdayNameList.enumerated() {
      for name in names { index[persianKey(persianForMatching(name))] = weekday }
    }
    return index
  }()

  /// The weekday names as a pattern, longest first.
  static let persianWeekdayNames = alternation(of: persianWeekdayNameList.flatMap { $0 })

  /// The weekday a name names, 0 = Sunday, however its compound is typed.
  static func persianWeekdayIndex(_ word: String) -> Int? {
    persianWeekdayIndexByKey[persianKey(word)]
  }

  /// Each month's names in the Solar Hijri calendar, Farvardin first, which
  /// Persian speakers use for a date. A month name before "ماه" ("مهر ماه")
  /// is the same month.
  private static let persianSolarMonthNameList: [[String]] = [
    ["فروردین"], ["اردی‌بهشت"], ["خرداد"], ["تیر"], ["مرداد", "امرداد"], ["شهریور"], ["مهر"], ["آبان"], ["آذر"],
    ["دی"], ["بهمن"], ["اسفند", "اسپند"],
  ]

  /// Each month's names in the Gregorian calendar as Persian writes them,
  /// January first. The Dari spelling "می" for May is not read: it is the verb
  /// prefix of every present-tense verb ("۲ می خرم"). The Afghan names of the
  /// Solar Hijri months (حمل, ثور, جوزا, ...) are not read either: most are
  /// ordinary words.
  private static let persianGregorianMonthNameList: [[String]] = [
    ["ژانویه", "ژانوییه", "جنوری"], ["فوریه", "فبریه", "فبروری"], ["مارس", "مارچ"], ["آوریل", "اپریل", "آپریل"],
    ["مه"], ["ژوئن", "ژون", "جون"], ["ژوئیه", "ژوییه", "جولای"], ["اوت", "آگوست", "اگوست", "اگست"],
    ["سپتامبر", "سپتمبر"],
    ["اکتبر", "اکتوبر"], ["نوامبر", "نومبر"], ["دسامبر", "دسمبر"],
  ]

  /// The month a name in the reading form names: its calendar and its index,
  /// 0 = Farvardin or January.
  private static let persianMonthByKey: [String: (isSolar: Bool, index: Int)] = {
    var index: [String: (isSolar: Bool, index: Int)] = [:]
    for (month, names) in persianSolarMonthNameList.enumerated() {
      for name in names { index[persianKey(persianForMatching(name))] = (true, month) }
    }
    for (month, names) in persianGregorianMonthNameList.enumerated() {
      for name in names { index[persianKey(persianForMatching(name))] = (false, month) }
    }
    return index
  }()

  /// The words that make a weekday or a week the coming one: "آینده", "آتی",
  /// and "بعدی", and "بعد" unless "از" follows it ("پنجشنبه بعد از ظهر" is the
  /// afternoon).
  static let persianNextWords = #"(?:آینده|آتی|بعدی|بعد(?!\s*از))"#

  // MARK: - Dates

  /// "۱۲ مهر", "۱۲ مهر ماه", "۱۲ مهر ۱۴۰۵", "۵ مارس", "۵ مارس ۲۰۲۷": a day
  /// number before a month name of the Solar Hijri or the Gregorian calendar,
  /// maybe with a year of that calendar. A date written in digits only
  /// ("۱۴۰۵/۷/۱۲") is not read.
  static var persianMonthDatePattern: String {
    let solar = alternation(of: persianSolarMonthNameList.flatMap { $0 })
    let gregorian = alternation(of: persianGregorianMonthNameList.flatMap { $0 })
    return
      #"\d{1,2}\s+(?:(?:\#(solar))(?:‌ماه)?(?:\s+(?:13|14)\d{2})?|(?:\#(gregorian))(?:\s+(?:19|20)\d{2})?)"#
  }

  /// A written-out date: the day, its calendar, and the year when it has
  /// one. The words are a phrase as ``persianPhrase(_:)`` leaves it.
  static func persianWrittenDate(_ words: String) -> (date: ExplicitDate, isSolar: Bool)? {
    let tokens = words.split(separator: " ").map(String.init)
    guard let dayIndex = tokens.firstIndex(where: { $0.count <= 2 && number($0) != nil }),
      let day = number(tokens[dayIndex]), dayIndex + 1 < tokens.count
    else { return nil }
    var index = dayIndex + 1
    var month: (isSolar: Bool, index: Int)?
    // A month name typed as two words ("اردی بهشت"), or with "ماه" attached.
    if index + 1 < tokens.count, let two = persianMonthByKey[tokens[index] + tokens[index + 1]] {
      month = two
      index += 2
    } else if let one = persianMonthByKey[tokens[index]] {
      month = one
      index += 1
    } else if tokens[index].hasSuffix("ماه"), let attached = persianMonthByKey[String(tokens[index].dropLast(3))] {
      month = attached
      index += 1
    }
    guard let month else { return nil }
    if index < tokens.count, tokens[index] == "ماه" { index += 1 }
    let year =
      index < tokens.count
      ? tokens[index].wholeMatch(of: /(?:13|14|19|20)\d{2}/).flatMap { number($0.output) } : nil
    return (ExplicitDate(year: year, month: month.index + 1, day: day), month.isSolar)
  }

  /// The Solar Hijri calendar in UTC, in which Persian dates are counted.
  private static var persianSolarCalendar: Calendar {
    var calendar = Calendar(identifier: .persian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  /// Days from `today`, a UTC midnight, to the Solar Hijri `date`, which names
  /// its month: a date without a year is this Solar year's, or next year's
  /// once passed. Nil for a day the calendar lacks (30 Esfand in a year that
  /// is not a leap year, or 31 of a month after Shahrivar), a written year's
  /// date in the past, or one more than ten years ahead.
  static func persianSolarOffset(to date: ExplicitDate, from today: Date) -> Int? {
    guard let month = date.month else { return nil }
    let calendar = persianSolarCalendar
    guard let thisYear = calendar.dateComponents([.year], from: today).year else { return nil }
    func days(year: Int) -> Int? {
      guard let target = calendar.date(from: DateComponents(year: year, month: month, day: date.day)) else { return nil }
      let parts = calendar.dateComponents([.year, .month, .day], from: target)
      guard parts.year == year, parts.month == month, parts.day == date.day else { return nil }
      return utcCalendar.dateComponents([.day], from: today, to: target).day
    }
    let result: Int?
    if let year = date.year {
      result = days(year: year)
    } else if let current = days(year: thisYear), current >= 0 {
      result = current
    } else {
      result = days(year: thisYear + 1)
    }
    guard let result, (0...3650).contains(result) else { return nil }
    return result
  }

  /// Days from `today` to a written date in its own calendar.
  private static func persianOffset(of written: (date: ExplicitDate, isSolar: Bool), from today: Date) -> Int? {
    written.isSolar ? persianSolarOffset(to: written.date, from: today) : offset(to: written.date, from: today)
  }

  // MARK: - Pieces of a day phrase

  /// A part of the day before or after a day, as a pattern without groups.
  private static var persianPartAfterDay: String { #"(?:\s+\#(persianPartOfDayWords))?"# }
  private static var persianPartBeforeDay: String { #"(?:\#(persianPartOfDayWords)\s+)?"# }

  private static var persianTodayPhrase: String {
    #"(?:همین\s+)?\#(persianPartBeforeDay)امروز\#(persianPartAfterDay)|امشب|این\s+(?:\#(persianPartBeforeDayWords)|شب)"#
  }

  private static var persianTomorrowPhrase: String {
    #"(?:همین\s+)?\#(persianPartBeforeDay)فردا\#(persianPartAfterDay)"#
  }

  private static var persianDayAfterPhrase: String {
    #"\#(persianPartBeforeDay)پس‌فردا\#(persianPartAfterDay)"#
  }

  /// "۳ روز دیگر", "دو هفته دیگه", "یک ماه دیگر", "۳ روز بعد", "بعد از ۳ روز",
  /// "هفته دیگر": a count of days, weeks, or months ahead. A phrase that "از",
  /// "مانده", or "باقی" follows is counted from something else or counts what
  /// is left ("۳ روز بعد از جلسه", "۳ روز دیگر مانده").
  private static var persianRelativePhrase: String {
    let count = #"(?:\d{1,3}|\#(persianCountWords))"#
    let unit = #"(?:روز|هفته|ماه)"#
    let notCounted = #"(?!\s+(?:از|مانده|باقی)\#(persianEnd))"#
    return
      #"(?:(?:بعد|پس)\s+از\s+\#(count)\s+\#(unit)(?!\s+(?:پیش|قبل)\#(persianEnd))|\#(count)\s+\#(unit)\s+(?:دیگر|دیگه|بعد)\#(notCounted)|هفته(?:‌ی)?\s+(?:دیگر|دیگه)\#(notCounted))"#
  }

  /// "هفته آینده", "هفته‌ی بعد", "هفته آتی": seven days ahead.
  private static var persianNextWeekPhrase: String {
    #"هفته(?:‌ی)?\s+\#(persianNextWords)"#
  }

  /// A weekday with the words around it that fix which one: a part of the day
  /// before it ("صبح پنجشنبه"), "این" or "همین" ("این جمعه"), "روز" ("روز
  /// جمعه"), a week before ("هفته آینده سه‌شنبه") or after ("سه‌شنبه هفته
  /// آینده", "پنجشنبه این هفته"), a word for next ("پنجشنبه آینده", "پنجشنبه‌ی
  /// بعد"), and a part of the day after it ("جمعه عصر", "پنجشنبه شب"). A
  /// weekday that "گذشته", "پیش", or "قبل" follows is the past ("پنجشنبه
  /// گذشته", "جمعه قبل"; "جمعه قبل از ظهر" is the morning), and one that
  /// "بازار" or "سوری" follows is a name ("جمعه بازار", "چهارشنبه‌سوری").
  private static var persianWeekdayPhrase: String {
    let ezafe = #"(?:‌ی)?"#
    let nextWeek = #"هفته\#(ezafe)\s+\#(persianNextWords)"#
    let past = #"گذشته|(?:پیش|قبل)(?!\s*از)|قبلی|پار"#
    let name = #"[\s\x{200C}]?(?:بازار|سوری)"#
    let notPast =
      #"(?!\#(ezafe)\s+(?:\#(past))\#(persianEnd)|\#(ezafe)\s+هفته\#(ezafe)\s+(?:\#(past))\#(persianEnd)|\#(name)\#(persianEnd))"#
    return
      #"(?:\#(persianPartBeforeDayWords)\s+)?(?:(?:این|همین)\s+)?(?:\#(nextWeek)\s+)?(?:روز\s+)?(?:\#(persianWeekdayNames))\#(notPast)(?:\#(ezafe)\s+(?:\#(persianNextWords)|این\s+هفته|\#(nextWeek)))?\#(persianPartAfterDay)"#
  }

  /// A date, maybe after its weekday: "۱۲ مهر", "پنجشنبه ۱۲ مهر", "پنجشنبه،
  /// ۱۲ مهر ۱۴۰۵".
  private static var persianDatePhrase: String {
    #"(?:(?:\#(persianWeekdayNames))\s*[،,]?\s+)?\#(persianMonthDatePattern)\#(persianDateEnd)"#
  }

  /// The end of the day, as a day: "آخر روز", "پایان امروز".
  private static let persianEndOfDayPhrase = #"(?:آخر|پایان|انتهای)\s+(?:روز|امروز)"#

  /// The words of an end of the day, as ``persianDay(_:in:)`` compares them.
  private static let persianEndOfDayWords: Set<String> = Set(
    ["آخر", "پایان", "انتهای"].map { persianKey(persianForMatching($0)) })

  /// The days a deadline may name, as a pattern without groups: the end of the
  /// day, today, tomorrow, the day after, a number of days ahead, a date, a
  /// weekday, next week. A date goes before a weekday, which it may follow
  /// ("پنجشنبه ۱۲ مهر"), and a weekday before next week, which it may follow
  /// ("هفته آینده سه‌شنبه").
  static var persianDueDayWords: String {
    #"(?:\#(persianEndOfDayPhrase)|\#(persianTodayPhrase)|\#(persianTomorrowPhrase)|\#(persianDayAfterPhrase)|\#(persianRelativePhrase)|\#(persianDatePhrase)|\#(persianWeekdayPhrase)|\#(persianNextWeekPhrase))"#
  }

  // MARK: - Planned day

  /// The text before a day that makes it no planned day: a bound or a moment
  /// relative to something else ("تا", "قبل از", "بعد از", "از"), a stretch of
  /// time ("هر", "همه", "تمام", "طی", "ظرف", "آخر", "اول", "نیمه", "پایان",
  /// "ابتدای", "طول"), "شب" ("شب جمعه" is Thursday night), or a noun that a
  /// weekday names ("نماز جمعه" is the Friday prayer, "بازار جمعه" the Friday
  /// market), at the end of the text before the day.
  private static let persianNotADayBefore = persian(
    #"(?:^|\s)(?:تا|الی|(?:قبل|پیش|بعد|پس)\s+از|از|طی|ظرف|هر|همه|تمام|آخر|اول|نیمه|پایان|ابتدای|طول|شب|جز|به\s+جز|بجز|نماز|بازار)\s*$"#,
    readsMarks: false)

  private static func persianIsNotADay(_ match: Match) -> Bool {
    persianFinds(persianNotADayBefore, in: persianTextBefore(match))
  }

  /// Group 1: the day, with the words that introduce it ("برای فردا", "در
  /// روز جمعه").
  ///
  /// Today ("امروز", "امشب", "امروز صبح", "این عصر"), tomorrow ("فردا", "فردا
  /// شب", "صبح فردا"), the day after ("پس‌فردا"), a number of days, weeks, or
  /// months ahead ("۳ روز دیگر", "بعد از ۳ روز"), next week ("هفته آینده"), a
  /// weekday alone or with the words that fix which one ("جمعه", "این جمعه",
  /// "جمعه آینده", "هفته آینده سه‌شنبه", "عصر جمعه"), and a date ("۱۲ مهر",
  /// "۵ مارس"), each maybe after "برای" or "در".
  static var persianWhenPattern: String {
    let alternatives = [
      persianTodayPhrase, persianTomorrowPhrase, persianDayAfterPhrase, persianRelativePhrase, persianDatePhrase,
      persianWeekdayPhrase, persianNextWeekPhrase,
    ]
    return
      #"\#(persianStart)((?:(?:برای|در)\s+)?(?:\#(alternatives.joined(separator: "|"))))\#(persianEnd)"#
  }

  static func persianWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !persianIsNotADay(match) else { return nil }
    return persianDay(phrase, in: match)
  }

  // MARK: - Due day

  /// A day after a deadline word ("تا جمعه", "قبل از فردا", "تا ۱۲ مهر",
  /// "حداکثر پنجشنبه") or a deadline label ("مهلت: جمعه", "ددلاین ۱۲ مهر", "سررسید
  /// فردا"), the day before a clock deadline ("جمعه تا ساعت ۵", "فردا قبل از
  /// ساعت ۵"), and the day between a deadline word and a clock ("تا جمعه ساعت
  /// ۵", where the clock stays with its "تا"). Groups: 1 the day after a label,
  /// 2 the day between a deadline word and a clock, 3 the day after a deadline
  /// word, 4 the day before a clock deadline.
  static var persianDuePattern: String {
    let bound = #"(?:تا\s+قبل\s+از|تا|قبل\s+از|پیش\s+از|حداکثر\s+تا|حداکثر|نهایتا\s+تا|نهایتا)"#
    let label =
      #"(?:ددلاین|آخرین\s+(?:مهلت|فرصت)|مهلت(?:\s+(?:تحویل|انجام|ارسال))?|موعد(?:\s+تحویل)?|سررسید|تاریخ\s+(?:سررسید|تحویل))"#
    let clock = persianClockPhrase
    let part = #"(?:\#(persianPartOfDayWords)\s+)?"#
    let ahead = #"(?=\s+\#(part)\#(clock))"#
    let afterBound = #"(?<=[ت][ا]\s|[ق][ب][ل]\s[ا][ز]\s|[پ][ی][ش]\s[ا][ز]\s)"#
    let alternatives = [
      #"\#(label)(?:\s*[:：]\s*|\s+)(?:تا\s+)?(\#(persianDueDayWords))"#,
      #"\#(afterBound)(\#(persianDueDayWords))\#(ahead)"#,
      #"\#(bound)\s+(\#(persianDueDayWords))(?!\s+\#(part)\#(clock))"#,
      #"(\#(persianDueDayWords))(?=\s+\#(part)(?:تا|قبل\s+از|پیش\s+از)\s+\#(clock))"#,
    ]
    return #"\#(persianStart)(?:\#(alternatives.joined(separator: "|")))\#(persianEnd)"#
  }

  static func persianDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) else { return nil }
    return persianDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "این" makes it this week's, today when it
  /// names today; a word for next after it ("آینده", "بعد") makes it the coming
  /// one, a full week ahead when it names today; the week named first or
  /// after ("هفته آینده سه‌شنبه", "سه‌شنبه هفته آینده") makes it next week's,
  /// weeks starting on Monday.
  private static func persianDay(_ phrase: String, in match: Match) -> Day? {
    let words = persianPhrase(phrase)
    if let written = persianWrittenDate(words) {
      guard let today = match.today, let days = persianOffset(of: written, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = words.split(separator: " ").map(String.init)
    let isEvening = tokens.contains(where: ["شب", "امشب", "عصر", "غروب", "شامگاه"].contains)
    if tokens.contains("امشب") { return Day(offset: 0, isEvening: true) }
    if let weekday = persianWeekdays(in: words).first {
      let isNext = persianFinds(persianNextWords, in: words)
      let isThis = tokens.contains("این") || tokens.contains("همین")
      let days: Int
      if isNext, tokens.contains("هفته") {
        days = nextWeekOffset(weekday, todayWeekday: match.todayWeekday)
      } else if isThis, !isNext {
        days = weekdayDelta(weekday, todayWeekday: match.todayWeekday)
      } else {
        days = comingWeekdayOffset(weekday, todayWeekday: match.todayWeekday)
      }
      return Day(offset: days, isEvening: isEvening)
    }
    if let relative = persianRelativeDay(tokens, in: match) { return relative }
    if persianKey(words).contains("پسفردا") { return Day(offset: 2, isEvening: isEvening) }
    if tokens.contains("فردا") { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains("امروز") || tokens.first == "این" || tokens.contains(where: persianEndOfDayWords.contains) {
      return Day(offset: 0, isEvening: isEvening)
    }
    if tokens.contains("هفته"), persianFinds(persianNextWords, in: words) { return Day(offset: 7) }
    return nil
  }

  /// The weekdays a text names, in the order it names them, 0 = Sunday: each
  /// name however its compound is typed ("سه‌شنبه", "سه شنبه", "سهشنبه"), with
  /// or without the plural ending after it ("دوشنبه‌ها").
  static func persianWeekdays(in text: String) -> [Int] {
    let bare = persianBare(text)
    guard let regex = LorvexCapturePatterns.regex(persian("(?:\(persianWeekdayNames))", readsMarks: false)) else {
      return []
    }
    return regex.matches(in: bare, range: NSRange(bare.startIndex..., in: bare)).compactMap { found in
      Range(found.range, in: bare).flatMap { persianWeekdayIndex(String(bare[$0])) }
    }
  }

  /// The days from today of "۳ روز دیگر", "دو هفته دیگر", "یک ماه دیگر", "بعد
  /// از ۳ روز", and "هفته دیگر", from the words of the phrase: a count and a
  /// unit. Months are counted on the Solar Hijri calendar.
  private static func persianRelativeDay(_ tokens: [String], in match: Match) -> Day? {
    guard let unitIndex = tokens.firstIndex(where: { ["روز", "هفته", "ماه"].contains($0) }) else { return nil }
    var countTokens = Array(tokens[..<unitIndex])
    while let first = countTokens.first, ["بعد", "پس", "از", "در", "برای"].contains(first) {
      countTokens.removeFirst()
    }
    let count: Int
    if countTokens.isEmpty {
      guard tokens[unitIndex] == "هفته", tokens.contains(where: ["دیگر", "دیگه"].contains) else { return nil }
      count = 1
    } else if let (value, rest) = persianLeadingCount(countTokens), rest.isEmpty {
      count = value
    } else {
      return nil
    }
    guard count >= 1 else { return nil }
    switch tokens[unitIndex] {
    case "روز": return Day(offset: count)
    case "هفته": return Day(offset: count * 7)
    default:
      guard let today = match.today,
        let target = persianSolarCalendar.date(byAdding: .month, value: count, to: today),
        let days = utcCalendar.dateComponents([.day], from: today, to: target).day
      else { return nil }
      return Day(offset: days)
    }
  }

  // MARK: - Date range

  /// "از ۳ تا ۵ آبان", "۳ تا ۵ آبان", "از ۳ آبان تا ۵ آبان", "از ۳۰ مهر تا ۲
  /// آبان", "بین ۳ و ۵ آبان", "۳-۵ آبان", "از ۳ تا ۵ مارس", each maybe with a
  /// year after the end. The start is a date or a day alone ("۳"); the end is a
  /// date. Groups: 1 the word that opens the range, if any (از, بین), 2 the
  /// start, 3 a dash between the sides, 4 the word that means "to" between them
  /// (تا, الی), 5 "و" between them, 6 the end.
  static var persianDateRangePattern: String {
    let bare = #"\d{1,2}\#(persianNoMoreDigits)"#
    let side = "\(persianMonthDatePattern)|\(bare)"
    return
      #"\#(persianStart)(?:(از|بین)\s+)?(\#(side))(?:\s*([-–—])\s*|\s+(تا|الی)\s+|\s+(و)\s+)(\#(side))\#(persianDateEnd)"#
  }

  /// A range's days. The end must name a month, so "از ۳ تا ۵" and "ساعت ۵ و
  /// ۱۰ دقیقه" are never a range of days. "و" joins the sides only after "بین"
  /// ("۳ و ۵ آبان" names two days and stays in the title whole). A start that
  /// is a day alone, joined by a dash with no opening word, makes a range only
  /// when the dash touches both sides ("۳-۵ آبان"): "اسپرینت ۱۲ - ۲۰ مهر" names
  /// a sprint and a date. The end must be after the start. A range in the
  /// Gregorian calendar is read by ``dayRangeReading(from:to:today:)`` and a
  /// range in the Solar Hijri calendar the same way on that calendar; a range
  /// whose two sides name different calendars is claimed whole and read as no
  /// days.
  static func persianDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(6),
      let start = persianRangeSide(startText), let end = persianRangeSide(endText),
      let isSolar = end.isSolar
    else { return nil }
    let opening = match.group(1).map(persianKey)
    if match.group(5) != nil, opening != "بین" { return .declined }
    if start.date.month == nil, opening == nil, match.group(3) != nil,
      !dashTouchesBothSides(match, start: 2, end: 6)
    {
      return nil
    }
    if let startIsSolar = start.isSolar, startIsSolar != isSolar { return .declined }
    if isSolar { return persianSolarDayRange(from: start.date, to: end.date, today: match.today) }
    return dayRangeReading(from: start.date, to: end.date, today: match.today)
  }

  /// A side of a date range: a date ("۵ مهر") with its calendar, or a day alone
  /// ("۵"), which has no month and no calendar.
  private static func persianRangeSide(_ text: String) -> (date: ExplicitDate, isSolar: Bool?)? {
    let words = persianPhrase(text)
    if let written = persianWrittenDate(words) { return (written.date, written.isSolar) }
    guard let match = words.wholeMatch(of: /(\d{1,2})/), let day = number(match.output.1) else { return nil }
    return (ExplicitDate(day: day), nil)
  }

  // MARK: - Weekday span

  /// "از دوشنبه تا چهارشنبه", "دوشنبه تا چهارشنبه", "از شنبه الی پنجشنبه",
  /// "بین دوشنبه و چهارشنبه": a span of weekdays. Groups: 1 the word that opens
  /// the span (از, بین), 2 the first weekday, 3 the word between the weekdays
  /// (تا, الی, و), 4 the last.
  static var persianWeekdayRangePattern: String {
    let item = #"(?:\#(persianWeekdayNames))"#
    return #"\#(persianStart)(?:(از|بین)\s+)?(\#(item))\s+(تا|الی|و)\s+(\#(item))\#(persianEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first
  /// last day after it, so on a Tuesday "از پنجشنبه تا شنبه" runs from this
  /// Thursday to the Saturday after it. The span runs through the week's end
  /// ("از جمعه تا دوشنبه"), and "و" joins the weekdays only after "بین". A
  /// span that "هر", "روزهای", or the words for every day accompany is a
  /// habit, which the repeat rules read, and a working week (Monday to
  /// Friday, Saturday to Wednesday, Saturday to Thursday) with none of them
  /// is claimed whole and read as no days: it is a week of work as often as it
  /// is a span of days. A span that "گذشته", "پیش", "قبل", or "قبلی" follows
  /// is past, and a span from a day to itself names no days: both are claimed
  /// whole too.
  static func persianWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(2), let lastWord = match.group(4),
      let first = persianWeekdayIndex(firstWord), let last = persianWeekdayIndex(lastWord)
    else { return nil }
    if match.group(3).map(persianKey) == "و", match.group(1).map(persianKey) != "بین" { return nil }
    let habit = #"(?:\#(persianEveryDayWords)|روزهای|هر)"#
    if persianFinds(#"(?:^|\s)\#(habit)\s*[،,]?\s*$"#, in: persianTextBefore(match))
      || persianFinds(#"^\s+\#(persianEveryDayWords)\#(persianEnd)"#, in: persianTextAfter(match))
    {
      return nil
    }
    if persianFinds(#"^\s+(?:گذشته|قبلی|(?:پیش|قبل)(?!\s*از))\#(persianEnd)"#, in: persianTextAfter(match)) {
      return .declined
    }
    if first == last { return .declined }
    if [(1, 5), (6, 3), (6, 4)].contains(where: { $0 == (first, last) }) { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// The range of days from the Solar Hijri date `start` to `end`, read the
  /// way ``dayRangeReading(from:to:today:)`` reads a Gregorian range: a side
  /// without a month takes the other side's, the start without a year is the
  /// next such day, and the end the first one after it ("۳۰ اسفند - ۲
  /// فروردین" ends in the next Solar year). Nil without `today`;
  /// ``DayRangeReading/declined`` when a side names a day the calendar lacks or
  /// the end is not after the start.
  private static func persianSolarDayRange(
    from start: ExplicitDate, to end: ExplicitDate, today: Date?
  ) -> DayRangeReading? {
    guard let today else { return nil }
    var start = start
    var end = end
    start.month = start.month ?? end.month
    end.month = end.month ?? start.month
    if start.year == nil, let endYear = end.year {
      start.year = (start.month ?? 1) <= (end.month ?? 12) ? endYear : endYear - 1
    }
    guard let first = persianSolarOffset(to: start, from: today),
      let firstDay = utcCalendar.date(byAdding: .day, value: first, to: today)
    else { return .declined }
    let parts = persianSolarCalendar.dateComponents([.year, .month], from: firstDay)
    guard let year = parts.year, let month = parts.month else { return .declined }
    let endMonth = end.month ?? month
    end.month = endMonth
    end.year = end.year ?? (endMonth >= month ? year : year + 1)
    guard let last = persianSolarOffset(to: end, from: today), last > first else { return .declined }
    return .range(DayRange(start: first, end: last))
  }
}
