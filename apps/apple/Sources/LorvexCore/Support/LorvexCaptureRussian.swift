import Foundation

extension LorvexCaptureVocabulary {
  /// Russian, read for a user who reads Russian. A word needs a boundary of
  /// Cyrillic letters, digits, and apostrophes on both sides, and ё is read as
  /// е ("отчёт" and "отчет", "днём" and "днем").
  ///
  /// Russian says a clock time with "в" ("в 15:00", "в 15", "в 3 часа дня"), a
  /// day with "в" before a weekday ("в пятницу") and a deadline with "до" or
  /// "к". A bare hour after "в" is a time only when the line goes on with a
  /// word that can follow a time ("в 3 с Иваном", "в 3 завтра") rather than a
  /// counted noun ("в 3 этапа"). A clock time after до, к, перед, после, or не
  /// позднее is a deadline, which a task's time cannot hold, so it stays in the
  /// title.
  ///
  /// English is read beside Russian, so a detail that needs no Russian word is
  /// left to English, which reads its own "3pm", "15:00", "for 2h", or "from
  /// 3-4pm" whole.
  ///
  /// A weekday is a day only with a word before it: в, во, or на before it, or
  /// с, со, or начиная с for its start. Alone it is a noun or a name ("среда"
  /// is also the environment: "Настроить среду разработки", "Отчёт за
  /// понедельник", "Понедельничная планёрка"). A weekday with a capital letter
  /// that does not open the line ("Купить в Пятнице") is a name, and the
  /// Wednesday before a word that makes it an environment ("в среду
  /// разработки") is no day.
  ///
  /// - Day: сегодня, сегодня вечером (an evening), завтра, завтра утром,
  ///   послезавтра, each maybe after на ("на завтра"); the weekday names after
  ///   в, во, or на ("в понедельник", "во вторник", "в среду", "на пятницу"),
  ///   after с, со, or начиная с ("с понедельника"); в эту пятницу (this
  ///   week's), в следующую пятницу (next week's, weeks starting on Monday);
  ///   на следующей неделе; на выходных, в выходные, на следующих выходных;
  ///   через 3 дня, через 1 день, через две недели, через неделю; a date: 5
  ///   мая, 5-го мая, на 5 мая, в понедельник, 5 октября, 5 янв., 5 мая 2027
  ///   года. A weekday alone means the next such day, a full week ahead when it
  ///   names today. Вечером and ночью make an evening ("завтра вечером"). A
  ///   month name needs a day number ("Майские праздники" is a title), and a
  ///   date written in digits ("5.10") is not read. "Через день" is both "in a
  ///   day" and "every other day", so it stays in the title.
  /// - Date range: с 3 по 5 мая, с 3 до 5 мая, от 3 до 5 мая, с 30 мая по 2
  ///   июня, 3–5 мая, 3-5 мая, each maybe with a year after the end. The first
  ///   day is the planned day and the last the due day, so another day phrase
  ///   stays in the title. A day written without its month takes the month of
  ///   the end, the end must be after the start ("с 5 по 3 мая" stays in the
  ///   title whole), and an end in an earlier month falls in the next year. A
  ///   day alone opens a range joined by a dash only when the dash touches both
  ///   sides or с comes first: "Спринт 12 - 20 мая" names a sprint and a date.
  ///   Days of the month with no month ("с 3 по 5") are no range.
  /// - Repeat: каждый день, каждое утро, каждый вечер, ежедневно (at the end of
  ///   the line), каждую неделю, еженедельно, каждый месяц, ежемесячно, каждый
  ///   год, ежегодно, каждый понедельник, каждый понедельник и четверг, по
  ///   понедельникам, по понедельникам и четвергам, по будням, в рабочие дни,
  ///   с понедельника по пятницу, по выходным, каждые 2 дня, каждые две недели,
  ///   каждые 3 месяца, раз в неделю, раз в 2 недели, раз в месяц, 5-го числа
  ///   каждого месяца, каждый месяц 5-го числа.
  /// - Due: a day after до, к, не позднее, не позже, срок, срок сдачи, крайний
  ///   срок, or дедлайн ("до пятницы", "к пятнице", "до 5 мая", "срок: 5 мая").
  /// - Time: в 15:00, в 15.30, в 15, в 3 часа, в 3 часа 30 минут, в 3 часа дня,
  ///   в 9 утра, в 7 вечера, в 2 ночи, 9 утра, 7 вечера, в полдень, в полночь,
  ///   около 15:00, с 18:00; a range: с 14 до 16, от 14 до 16, с 14:00 до
  ///   16:00, с 9 утра до 6 вечера, с 10 до 12 часов, and with a dash between
  ///   the sides after с, от, or в ("в 14:00-16:00"). A time from 1 to 6
  ///   o'clock with no part of the day is the afternoon, unless written with a
  ///   leading zero ("06:30").
  ///   Утра is the morning (12 утра is no time), дня is noon at 12 and the
  ///   afternoon from 1 to 6, вечера is the evening, and ночи runs past
  ///   midnight: "в 2 ночи" is 02:00 of the next day, "в 11 ночи" 23:00. "В 3
  ///   дня" and "в 3 часа дня" are times, but "3 дня" with no в is a count of
  ///   days. A range of two bare hours counts only when the line goes on with a
  ///   word that can follow a time and no word that names an amount or
  ///   numbered items comes before it, so "с 14 до 16 страниц", "Цена от 10 до
  ///   20", and "главы с 3 до 5" are titles; "с 3 по 5" is never a time, and
  ///   neither is a number before a percent or currency sign ("от 10 до 20 ₽").
  /// - Length: 30 минут, 30 мин, 2 часа, 2 ч, 1,5 часа, 1 час 30 минут,
  ///   полтора часа, полчаса, четверть часа, три четверти часа, один час, два
  ///   часа, each maybe after на, в течение, or около. An amount after через,
  ///   за, по, каждые, раз в, более, менее, до, к, or в names a moment, an
  ///   interval, or a bound, not a length ("через 2 часа", "по 2 часа", "в 2
  ///   часа"), "2 часа в день" is a rate, not a length, and an amount before a
  ///   part of the day is a time ("2 часа ночи"). "Час" alone is no length ("Час
  ///   пик").
  /// - Priority: высокий приоритет, приоритет высокий, средний приоритет, низкий
  ///   приоритет (also максимальный, наивысший, нормальный, and минимальный),
  ///   and "срочно" at the end of the line or opening it before a colon or
  ///   comma.
  static let russian = LorvexCaptureVocabulary(
    readingForm: russianForMatching,
    priority: [Rule(pattern: russianPriorityPattern, read: russianPriority)],
    dateRange: [Rule(pattern: russianDateRangePattern, read: russianDateRange)],
    keptInTitle: [Rule(pattern: russianDeadlineClockPattern) { $0.group(1) == nil ? nil : true }],
    length: [Rule(pattern: russianLengthPattern, read: russianLength)],
    time: [
      Rule(pattern: russianTimeRangePattern, read: russianTimeRange),
      Rule(pattern: russianTimePattern, read: russianTime),
    ],
    repeats: [
      // The working days, the weekend, and a day of the month before every
      // day and every month, which would leave "по будням" or the day's number
      // in the title.
      Rule(pattern: russianWorkdaysPattern) { _ in workdays },
      Rule(pattern: russianWeekendPattern) { _ in weekly(every: nil, on: [6, 0]) },
      Rule(pattern: russianMonthDayRepeatPattern, read: russianMonthDayRepeat),
      Rule(pattern: russianWeekdayRepeatPattern, read: russianWeekdayRepeat),
      Rule(pattern: russianIntervalRepeatPattern, read: russianIntervalRepeat),
      Rule(pattern: russianOnceEveryPattern, read: russianOnceEvery),
      Rule(pattern: russianCadencePattern(#"кажд(?:ый|ое)\s+(?:день|утро|вечер)|каждую\s+ночь"#, adverb: "ежедневно")) {
        _ in Repeat(rule: TaskRecurrenceRule(freq: .daily))
      },
      Rule(pattern: russianCadencePattern(#"каждую\s+неделю"#, adverb: "еженедельно")) { _ in
        weekly(every: nil, on: [])
      },
      Rule(pattern: russianCadencePattern(#"кажд(?:ый|ое)\s+месяц"#, adverb: "ежемесячно")) { _ in
        monthly(every: nil, on: nil)
      },
      Rule(pattern: russianCadencePattern(#"кажд(?:ый|ое)\s+год"#, adverb: "ежегодно")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [Rule(pattern: russianDuePattern, read: russianDue)],
    when: [Rule(pattern: russianWhenPattern, read: russianWhen)])

  /// The line with ё read as е and Ё as Е, so the patterns, written with е,
  /// read a line typed with either. Each replacement is one UTF-16 unit for
  /// one, so a match range in the result is the same range in `line`. A ё
  /// typed as е and a combining diaeresis stays as typed.
  static func russianForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars {
      switch scalar {
      case "ё": scalars.append("е")
      case "Ё": scalars.append("Е")
      default: scalars.append(scalar)
      }
    }
    return String(scalars)
  }

  // MARK: - Words after a detail

  /// The words a detail with no unit of its own ("в 3") may be followed by:
  /// prepositions, conjunctions, particles, and the words that say when or how
  /// often. Any other word after the number makes it a count ("в 3 этапа", "в 5
  /// раз"), so it stays in the title.
  private static let russianWordsAfterDetail: Set<String> = [
    "и", "а", "но", "или", "же", "ли", "бы", "в", "во", "на", "с", "со", "по", "до", "к", "ко", "у", "из", "за", "от",
    "о", "об", "при", "для", "без", "про", "после", "перед", "около", "примерно", "ровно", "сегодня", "завтра",
    "послезавтра", "вечером", "утром", "днем", "ночью", "каждый", "каждую", "каждое", "каждые", "ежедневно",
    "еженедельно", "ежемесячно", "ежегодно", "уже", "еще", "тоже", "также", "обязательно", "пожалуйста",
  ]

  static func russianFollowsAsDetail(_ match: Match) -> Bool {
    followsAsDetail(match, words: russianWordsAfterDetail)
  }

  /// The words before an hour with a part of the day that make it a deadline,
  /// or a bound, not a time: "до 5 вечера", "не позднее 9 утра".
  private static let russianDeadlineWords: Set<String> = ["до", "к", "ко", "перед", "после", "позднее", "позже"]

  // MARK: - Priority

  /// Group 1: a written priority; "срочно" has no group.
  private static let russianPriorityPattern =
    #"\#(cyrillicStart)(приоритет\s*:?\s*(?:высокий|максимальный|наивысший|средний|нормальный|низкий|минимальный)|(?:высокий|средний|низкий)\s+приоритет)\#(cyrillicEnd)|(?<=\s)срочно(?=\s*$)|^\s*срочно(?=\s*[，：:,])"#

  private static func russianPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("средн") || phrase.contains("нормальн") { return .p2 }
    if phrase.contains("низк") || phrase.contains("минимальн") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 минут", "30 мин", "2 часа", "2 ч", "1,5 часа", "1 час 30 минут",
  /// "полчаса", or a length in words, each maybe after на, в течение, or
  /// около. Groups: 1 the word that opens a length, 2 a word that makes the
  /// amount a moment, an interval, or a bound; 3 the hours of an amount with a
  /// unit and 4 its minutes; 5 minutes; 6 a length in words. The amount may
  /// not follow a digit, a colon, or a separator, it may not be a side of a
  /// range ("с 14 до 16 часов", "2-3 часа"), and it may not name a time ("2
  /// часа ночи") or the past ("30 минут назад").
  private static let russianLengthPattern =
    #"\#(cyrillicStart)(?:(на|в\s+течение|в\s+течении|около|примерно|порядка)\s+|(через|за|кажд(?:ые|ую|ый)|раз\s+в|не\s+более|не\s+менее|более|менее|свыше|после|перед|до|ко|к|во|в|со|с|по)\s+)?(?<![\p{N}:.,])(?<![\p{N}ч]\s(?:до|по)\s)(?<![\p{N}ч]\s?[-–—]\s?)(?:(\d+(?:[.,]\d+)?)\s*(?:часов|часа|час|ч\.?)(?:\s+(\d{1,2})\s*(?:минуты|минут|минуту|мин\.?))?|(\d+)\s*(?:минуты|минут|минуту|мин\.?)|(полтора\s+часа|пол[\s-]*часа|четверть\s+часа|три\s+четверти\s+часа|один\s+час|два\s+часа))\#(cyrillicEnd)(?!\s+(?:утра|дня|вечера|ночи|назад)\#(cyrillicEnd))(?!\s+в\s+(?:день|неделю|месяц|год|сутки)\#(cyrillicEnd))(?!\s*[-–—]\s*\d|\s+(?:до|по)\s+\d)"#

  private static func russianLength(_ match: Match) -> Int? {
    if match.group(2) != nil { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    switch match.group(6).map(normalizedPhrase) {
    case "полчаса", "пол часа": return 30
    case "полтора часа": return 90
    case "четверть часа": return 15
    case "три четверти часа": return 45
    case "один час": return 60
    case "два часа": return 120
    default: return nil
    }
  }

  // MARK: - Time

  /// The part of the day a word after an hour names.
  static let russianPartsOfDay: [String: PartOfDay] = [
    "утра": .morning, "дня": .day, "вечера": .evening, "ночи": .night,
  ]

  /// The words before an hour that make it a clock time: в, во, and около, maybe
  /// after примерно or ровно, and с or со, which read only with minutes or a
  /// part of the day ("с 3 по 5" is no time).
  private static let russianTimeLead = #"(?:(?:примерно|приблизительно|ровно|где-то)\s+)?(?:в|во)|около|со|с"#

  /// "в 15:00", "в 15.30", "в 15", "в 3 часа", "в 3 часа 30 минут", "в 3 часа
  /// дня", "в 9 утра", "в 7:30 вечера", and, with no lead, "9 утра", "7 вечера",
  /// "3 часа дня", "3:30 дня"; "в полдень" and "в полночь". A time written
  /// with no Russian word ("15:00", "3pm") is left to English. Groups: 1 the
  /// lead, 2 hour, 3 minute, 4 the word for hour, 5 minutes after it, 6 the
  /// part of the day; 7 to 11 the same without a lead; 12 the word after the
  /// lead of "в полдень".
  private static let russianTimePattern =
    [
      #"\#(cyrillicStart)(\#(russianTimeLead))\s+(\d{1,2})(?:[:.](\d{2})|\s+(часов|часа|час|ч)(?:\s+(\d{1,2})\s*(?:минуты|минут|минуту|мин))?)?(?:\s+(утра|дня|вечера|ночи))?\#(cyrillicTimeEnd)"#,
      #"(?<![\p{N}:.,])(\d{1,2})(?:[:.](\d{2})|\s+(часов|часа|час)(?:\s+(\d{1,2})\s*(?:минуты|минут|минуту|мин))?)?\s+(утра|дня|вечера|ночи)\#(cyrillicTimeEnd)"#,
      #"\#(cyrillicStart)(?:(?:(?:примерно|приблизительно|ровно|где-то)\s+)?(?:в|во)|около)\s+(полдень|полночь|полудня|полуночи)\#(cyrillicEnd)"#,
    ].joined(separator: "|")

  private static func russianTime(_ match: Match) -> ClockTime? {
    if let word = match.group(12)?.lowercased() {
      return word.hasPrefix("полд") ? ClockTime(minutes: 12 * 60) : ClockTime(minutes: 0, isAfterMidnight: true)
    }
    let lead = match.group(1).map(normalizedPhrase)
    // The groups of the hour, its minutes, its word, the minutes after the
    // word, and the part of the day follow the lead or start the alternative
    // with none.
    let first = lead == nil ? 7 : 2
    guard let hourText = match.group(first), let hour = number(hourText) else { return nil }
    let minuteText = match.group(first + 1)
    let wordMinuteText = match.group(first + 3)
    let minute = (minuteText ?? wordMinuteText).flatMap(number) ?? 0
    if let word = match.group(first + 4)?.lowercased(), let part = russianPartsOfDay[word] {
      // A count of days ("3 дня") is no time, so with no lead a day part needs
      // minutes or the word for hour; a deadline ("до 5 вечера") is none either.
      if lead == nil {
        if part == .day, minuteText == nil, match.group(first + 2) == nil { return nil }
        if let before = wordBefore(match), russianDeadlineWords.contains(before) { return nil }
      }
      return partOfDayTime(hour: hour, minute: minute, part: part)
    }
    // "С 3 по 5" is no time: с and со open a time only with minutes.
    if lead == "с" || lead == "со", minuteText == nil { return nil }
    // A bare hour ("в 3") is a time unless a counted noun follows it.
    let isBare = minuteText == nil && match.group(first + 2) == nil
    if isBare, !russianFollowsAsDetail(match) { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  // MARK: - Repeat

  /// A repeat pattern: a cadence written as `phrases` anywhere in the line, or
  /// as `adverb` at its end. An adverb ("ежедневно") says how a task repeats at
  /// the end of the line, where it cannot be taken for a word of the title.
  private static func russianCadencePattern(_ phrases: String, adverb: String) -> String {
    #"\#(cyrillicStart)(?:\#(phrases))\#(cyrillicEnd)|\#(cyrillicStart)\#(adverb)(?=\s*$)"#
  }

  /// "по будням", "по будним дням", "по рабочим дням", "в будни", "в будние
  /// дни", "в рабочие дни", "каждый будний день", "каждый рабочий день", and
  /// "с понедельника по пятницу".
  private static let russianWorkdaysPattern =
    #"\#(cyrillicStart)(?:по\s+(?:будням|будним\s+дням|рабочим\s+дням)|в\s+(?:будни|будние\s+дни|рабочие\s+дни)|каждый\s+(?:будний|рабочий)\s+день|с\s+понедельника\s+по\s+пятницу)\#(cyrillicEnd)"#

  /// "по выходным", "каждые выходные".
  private static let russianWeekendPattern = #"\#(cyrillicStart)(?:по\s+выходным|кажд(?:ые|ую)\s+выходные)\#(cyrillicEnd)"#

  /// "5-го числа каждого месяца", "каждого 5-го числа", "каждый месяц 5-го
  /// числа". Groups 1 to 3: the day of the month in each form.
  private static let russianMonthDayRepeatPattern =
    #"\#(cyrillicStart)(?:(\d{1,2})(?:-?(?:го|е))?\s+числа\s+каждого\s+месяца|кажд(?:ого|ое)\s+(\d{1,2})(?:-?(?:го|е))?\s+числ[ао]|каждый\s+месяц\s+(\d{1,2})(?:-?(?:го|е))?\s+числа)\#(cyrillicEnd)"#

  private static func russianMonthDayRepeat(_ match: Match) -> Repeat? {
    (match.group(1) ?? match.group(2) ?? match.group(3)).flatMap(number).flatMap { monthly(every: nil, on: $0) }
  }

  /// "каждый понедельник", "каждый понедельник и четверг", "каждую среду и
  /// пятницу", "по понедельникам", "по понедельникам и четвергам", "по
  /// понедельникам, средам и пятницам". Groups: 1 the weekdays after каждый, 2
  /// the weekdays after по.
  private static var russianWeekdayRepeatPattern: String {
    let day = russianWeekdayForms([1])
    let plural = russianWeekdayForms([4])
    let days = #"(?:\#(day))(?:(?:\s*,\s*|\s+и\s+)(?:кажд(?:ый|ую|ое)\s+)?(?:\#(day))){0,6}"#
    let plurals = #"(?:\#(plural))(?:(?:\s*,\s*|\s+и\s+)(?:\#(plural))){0,6}"#
    return #"\#(cyrillicStart)(?:кажд(?:ый|ую|ое)\s+(\#(days))|по\s+(\#(plurals)))\#(cyrillicEnd)"#
  }

  private static func russianWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = letterWords(match.group(1) ?? match.group(2) ?? "").compactMap(russianWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// The counts a repeat or a day phrase may spell out.
  private static let russianCounts = [
    "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
    "десять": 10,
  ]

  private static var russianCountWords: String {
    alternation(of: Array(russianCounts.keys))
  }

  /// "каждые 2 дня", "каждые две недели", "каждые 3 месяца", "каждые 5 лет".
  /// Groups: 1 the count, 2 the unit.
  private static var russianIntervalRepeatPattern: String {
    #"\#(cyrillicStart)кажд(?:ые|ую|ый|ое)\s+(\d{1,2}|\#(russianCountWords))\s+(дня|дней|день|недели|недель|неделю|месяца|месяцев|месяц|года|лет|год)\#(cyrillicEnd)"#
  }

  private static func russianIntervalRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1)?.lowercased(), let count = number(countText) ?? russianCounts[countText],
      (1...99).contains(count), let unit = match.group(2)?.lowercased()
    else { return nil }
    return russianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "раз в неделю", "раз в 2 недели", "раз в месяц", "раз в год", "раз в
  /// день". Groups: 1 the count, if any, 2 the unit.
  private static var russianOnceEveryPattern: String {
    #"\#(cyrillicStart)раз\s+в\s+(?:(\d{1,2}|\#(russianCountWords))\s+)?(день|дня|дней|неделю|недели|недель|месяц|месяца|месяцев|год|года|лет)\#(cyrillicEnd)"#
  }

  private static func russianOnceEvery(_ match: Match) -> Repeat? {
    guard let unit = match.group(2)?.lowercased() else { return nil }
    guard let countText = match.group(1)?.lowercased() else { return russianRepeat(unit: unit, every: nil) }
    guard let count = number(countText) ?? russianCounts[countText], (1...99).contains(count) else { return nil }
    return russianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func russianRepeat(unit: String, every: Int?) -> Repeat? {
    if unit.hasPrefix("недел") { return weekly(every: every, on: []) }
    if unit.hasPrefix("месяц") { return monthly(every: every, on: nil) }
    if ["год", "года", "лет"].contains(unit) {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  // MARK: - Days

  /// The weekday names, Sunday first: nominative, accusative, genitive,
  /// dative, and dative plural.
  private static let russianWeekdays = [
    ["воскресенье", "воскресенье", "воскресенья", "воскресенью", "воскресеньям"],
    ["понедельник", "понедельник", "понедельника", "понедельнику", "понедельникам"],
    ["вторник", "вторник", "вторника", "вторнику", "вторникам"],
    ["среда", "среду", "среды", "среде", "средам"],
    ["четверг", "четверг", "четверга", "четвергу", "четвергам"],
    ["пятница", "пятницу", "пятницы", "пятнице", "пятницам"],
    ["суббота", "субботу", "субботы", "субботе", "субботам"],
  ]

  /// The weekday names in the given forms (indexes into a row of
  /// ``russianWeekdays``), longest first, as a pattern.
  static func russianWeekdayForms(_ forms: [Int]) -> String {
    var names: [String] = []
    for row in russianWeekdays {
      for form in forms { names.append(row[form]) }
    }
    return alternation(of: names)
  }

  /// The weekday a word names in any form, 0 = Sunday.
  private static func russianWeekdayIndex(_ word: String) -> Int? {
    russianWeekdays.firstIndex { $0.contains(word) }
  }

  /// Each month's genitive name, as a date reads it, then its abbreviations,
  /// January first.
  private static let russianMonths = [
    ["января", "янв"], ["февраля", "февр", "фев"], ["марта", "мар"], ["апреля", "апр"], ["мая"], ["июня", "июн"],
    ["июля", "июл"], ["августа", "авг"], ["сентября", "сент", "сен"], ["октября", "окт"], ["ноября", "нояб", "ноя"],
    ["декабря", "дек"],
  ]

  /// "5 мая", "5-го мая", "5 янв.", "5 мая 2027", "5 мая 2027 года": a day with
  /// its month, maybe with a year. A month needs its day number.
  static var russianMonthDatePattern: String {
    let months = alternation(of: russianMonths.flatMap { $0 })
    return #"\d{1,2}(?:-?го)?\s+(?:\#(months))\.?(?:\s+(?:19|20)\d{2}(?:\s*(?:года|г(?![\p{Cyrillic}\p{N}])\.?))?)?"#
  }

  /// A date, maybe after its weekday: "5 мая", "в понедельник, 5 октября".
  private static var russianDatePattern: String {
    #"(?:(?:в|во|на)\s+(?:\#(russianWeekdayForms([1])))\s*,?\s+)?\#(russianMonthDatePattern)"#
  }

  /// The part of the day that may follow a day: "вечером", "с утра".
  private static let russianDayPart = #"(?:\s+(?:утром|днем|вечером|ночью|с\s+утра))"#

  /// Group 1: the day, with the words that introduce it.
  private static var russianWhenPattern: String {
    let alternatives = [
      #"(?:на\s+)?(?:сегодня|завтра|послезавтра)\#(russianDayPart)?"#,
      #"через\s+(?:(?:\d{1,3}|\#(russianCountWords))\s+(?:день|дня|дней|неделю|недели|недель)|неделю)"#,
      #"на\s+(?:следующей|будущей)\s+неделе"#,
      #"(?:на\s+(?:этих\s+|следующих\s+)?выходных|(?:в|на)\s+(?:эти\s+|следующие\s+)?выходные)"#,
      #"(?:(?:на|с|со|начиная\s+с)\s+)?\#(russianDatePattern)"#,
      #"(?:в|во|на)\s+(?:(?:этот|эту|это|следующий|следующую|следующее)\s+)?(?:\#(russianWeekdayForms([1])))\#(russianDayPart)?"#,
      #"(?:начиная\s+с|с|со)\s+(?:(?:этого|этой|следующего|следующей)\s+)?(?:\#(russianWeekdayForms([2])))\#(russianDayPart)?"#,
    ]
    return #"\#(cyrillicStart)(\#(alternatives.joined(separator: "|")))\#(cyrillicEnd)"#
  }

  /// "до пятницы", "к пятнице", "до 5 мая", "до завтра", "не позднее пятницы",
  /// "срок: 5 мая", "дедлайн в пятницу". Group 1: the day.
  private static var russianDuePattern: String {
    let alternatives = [
      "(?:сегодня|завтра|послезавтра)",
      russianDatePattern,
      #"(?:(?:этот|эта|эту|это|этой|этого|этому|следующий|следующая|следующую|следующее|следующей|следующего|следующему)\s+)?(?:\#(russianWeekdayForms([0, 1, 2, 3])))"#,
    ]
    return #"\#(cyrillicStart)(?:(?:до|к|ко|не\s+позднее|не\s+позже)\s+|(?:срок(?:\s+сдачи)?|крайний\s+срок|дедлайн)(?:\s*:\s*|\s+)(?:(?:до|к|ко|в|во)\s+)?)(\#(alternatives.joined(separator: "|")))\#(cyrillicEnd)"#
  }

  private static func russianWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { russianDay($0, in: match) }
  }

  private static func russianDue(_ match: Match) -> Day? {
    match.group(1).flatMap { russianDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  /// Words that follow a Wednesday to make it an environment ("в среду
  /// разработки"), not a day.
  private static let russianEnvironmentWords: Set<String> = [
    "разработки", "тестирования", "выполнения", "исполнения", "обитания", "сборки", "программирования",
    "моделирования", "развертывания", "интеграции", "отладки", "запуска",
  ]

  /// The day a phrase names. A weekday with a capital letter that does not open
  /// the line is a name, and a Wednesday before a word of ``russianEnvironmentWords``
  /// is an environment.
  private static func russianDay(_ phrase: String, in match: Match) -> Day? {
    let words = normalizedPhrase(phrase)
    if let date = russianDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let isEvening = words.hasSuffix("вечером") || words.hasSuffix("ночью")
    if words.hasPrefix("через ") {
      if words == "через неделю" { return Day(offset: 7) }
      guard let relative = words.wholeMatch(of: /через (\w+) (\p{L}+)/),
        let count = number(relative.output.1) ?? russianCounts[String(relative.output.1)]
      else { return nil }
      return Day(offset: relative.output.2.hasPrefix("недел") ? count * 7 : count)
    }
    if words.contains("послезавтра") { return Day(offset: 2, isEvening: isEvening) }
    if words.contains("завтра") { return Day(offset: 1, isEvening: isEvening) }
    if words.contains("сегодня") { return Day(offset: 0, isEvening: isEvening) }
    let todayWeekday = match.todayWeekday
    if words.contains("выходн") {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: words.contains("следующ") ? weekend + 7 : weekend)
    }
    if words.hasSuffix("неделе") { return Day(offset: 7) }
    let typed = phrase.split(whereSeparator: { !$0.isLetter }).map(String.init)
    guard let word = typed.first(where: { russianWeekdayIndex($0.lowercased()) != nil }),
      let weekday = russianWeekdayIndex(word.lowercased())
    else { return nil }
    if isCapitalizedName(word, in: match) { return nil }
    if weekday == 3, let next = wordAfter(match), russianEnvironmentWords.contains(next) { return nil }
    if words.contains("следующ") {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if words.split(separator: " ").contains(where: { $0.hasPrefix("эт") }) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// A written-out date, maybe after its weekday: "5 мая", "в понедельник, 5
  /// октября", "5-го мая 2027 года". The words are a phrase as
  /// ``normalizedPhrase(_:)`` leaves it.
  static func russianDate(_ words: String) -> ExplicitDate? {
    guard let match = words.firstMatch(of: /(\d{1,2})(?: го)? (\p{L}+)\.?(?: ((?:19|20)\d{2}))?/),
      let day = number(match.output.1),
      let month = russianMonths.firstIndex(where: { $0.contains(String(match.output.2)) })
    else { return nil }
    return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
  }
}
