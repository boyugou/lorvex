import Foundation

extension LorvexCaptureVocabulary {
  /// Ukrainian, read for a user who reads Ukrainian. A word needs a boundary of
  /// Cyrillic letters, digits, and apostrophes on both sides. The apostrophe
  /// inside a word is typed as U+0027, U+2019, or U+02BC ("п'ятниця", "п’ятниця",
  /// "пʼятниця"), and all three are read as the straight one; "п'ятниця" is
  /// also read without it.
  ///
  /// Ukrainian says a clock time with "о" ("о 15:00", "о 15", "о 3 годині дня"),
  /// a day with "у" or "в" before a weekday ("у п'ятницю") and a deadline with
  /// "до". A bare hour after "о" is a time only when the line goes on with a
  /// word that can follow a time ("о 3 з Іваном", "о 3 завтра") rather than a
  /// counted noun ("о 2 етапи"). A clock time after до, перед, після, or не
  /// пізніше is a deadline, which a task's time cannot hold, so it stays in the
  /// title.
  ///
  /// English is read beside Ukrainian, so a detail that needs no Ukrainian word
  /// is left to English, which reads its own "3pm", "15:00", "for 2h", or "from
  /// 3-4pm" whole.
  ///
  /// A weekday is a day only with a word before it: у, в, or на before it, з,
  /// із, зі, or починаючи з for its start, or цього, цієї, наступного, or
  /// наступної, which name a day on their own ("наступної п'ятниці"). Alone it
  /// is a noun or a name ("Звіт за понеділок", "Понеділкова планерка"). A weekday
  /// with a capital letter that does not open the line ("Купити у Суботу") is a
  /// name.
  ///
  /// - Day: сьогодні, сьогодні ввечері (an evening), завтра, завтра вранці,
  ///   післязавтра, each maybe after на ("на завтра"); the weekday names after
  ///   у, в, or на ("у понеділок", "у вівторок", "в середу", "у п'ятницю", "на
  ///   п'ятницю"), after з, із, зі, or починаючи з ("з понеділка"); у цю
  ///   п'ятницю, цієї п'ятниці (this week's), у наступну п'ятницю, наступної
  ///   п'ятниці (next week's, weeks starting on Monday); наступного тижня, на
  ///   наступному тижні; на вихідних, у вихідні, на наступних вихідних; через
  ///   3 дні, через 5 днів, через 1 день, через два тижні, через тиждень; a
  ///   date: 5 травня, 5-го травня, на 5 травня, у понеділок, 5 жовтня, 5 січ.,
  ///   5 травня 2027 року. A weekday alone means the next such day, a full
  ///   week ahead when it names today. Ввечері and вночі make an evening
  ///   ("завтра ввечері"). A month name needs a day number ("Травневі свята" is
  ///   a title), an abbreviation ends with its dot ("5 січ."), and a date
  ///   written in digits ("5.10") is not read. "Через день" is both "in a day"
  ///   and "every other day", so it stays in the title.
  /// - Date range: з 3 по 5 травня, з 3 до 5 травня, від 3 до 5 травня, з 30
  ///   травня по 2 червня, 3–5 травня, 3-5 травня, each maybe with a year after
  ///   the end. The first day is the planned day and the last the due day, so
  ///   another day phrase stays in the title. A day written without its month
  ///   takes the month of the end, the end must be after the start ("з 5 по 3
  ///   травня" stays in the title whole), and an end in an earlier month falls
  ///   in the next year. A day alone opens a range joined by a dash only when
  ///   the dash touches both sides or з comes first: "Спринт 12 - 20 травня"
  ///   names a sprint and a date. Days of the month with no month ("з 3 по 5")
  ///   are no range.
  /// - Repeat: щодня, кожного дня, кожен день, щоранку, кожного ранку, щовечора,
  ///   кожної ночі, щотижня, кожного тижня, кожен тиждень, щомісяця, кожного
  ///   місяця, щороку, кожного року, щопонеділка, кожного понеділка, кожен
  ///   понеділок, кожного понеділка і четверга, по понеділках, по понеділках і
  ///   четвергах, по буднях, у робочі дні, з понеділка по п'ятницю, по вихідних,
  ///   кожні 2 дні, кожні два тижні, кожні 3 місяці, раз на тиждень, раз на 2
  ///   тижні, раз на місяць, 5 числа кожного місяця, кожного 5 числа, щомісяця 5
  ///   числа; щоденно, щотижнево, щомісячно, and щорічно at the end of the line.
  ///   "Щоденний звіт" and "Щотижневий звіт" are titles.
  /// - Due: a day after до, не пізніше, термін, термін здачі, кінцевий термін,
  ///   or дедлайн ("до п'ятниці", "до 5 травня", "термін: 5 травня").
  /// - Time: о 15:00, о 15.30, о 15, о 3 годині, о 3 годині 30 хвилин, о 3
  ///   годині дня, о 9 ранку, о 7 вечора, о 2 ночі, 9 ранку, 7 вечора, опівдні,
  ///   опівночі, близько 15:00, з 18:00; a range: з 14 до 16, від 14 до 16, з
  ///   14:00 до 16:00, з 9 ранку до 6 вечора, з 10 до 12 годин, and with a dash
  ///   between the sides after з, від, о, or в ("о 14:00-16:00"). A time from 1
  ///   to 6 o'clock with no part of the day is the afternoon, unless written
  ///   with a leading zero ("06:30"). Ранку is the morning (12 ранку is no
  ///   time), дня is noon at 12 and the afternoon from 1 to 6, вечора is the
  ///   evening, and ночі runs past midnight: "о 2 ночі" is 02:00 of the next
  ///   day, "о 11 ночі" 23:00. A range of two bare hours counts only when the
  ///   line goes on with a word that can follow a time and no word that names
  ///   an amount or numbered items comes before it, so "з 14 до 16 сторінок",
  ///   "Ціна від 10 до 20", and "розділи з 3 до 5" are titles; "з 3 по 5" is
  ///   never a time, and neither is a number before a percent or currency sign
  ///   ("від 10 до 20 ₴").
  /// - Length: 30 хвилин, 30 хв, 2 години, 2 год, 1,5 години, 1 година 30
  ///   хвилин, півтори години, пів години, півгодини, чверть години, три чверті
  ///   години, одна година, дві години, each maybe after на, протягом, or
  ///   близько. An amount after через, за, по, кожні, раз на, понад, до, or о
  ///   names a moment, an interval, or a bound, not a length ("через 2 години",
  ///   "по 2 години"), "2 години на день" is a rate, not a length, and an amount
  ///   before a part of the day is a time ("2 години ночі"). "Година" alone is
  ///   no length ("Година пік").
  /// - Priority: високий пріоритет, пріоритет високий, середній пріоритет,
  ///   низький пріоритет (also максимальний, найвищий, нормальний, and
  ///   мінімальний), and "терміново" at the end of the line or opening it
  ///   before a colon or comma.
  static let ukrainian = LorvexCaptureVocabulary(
    readingForm: ukrainianForMatching,
    priority: [Rule(pattern: ukrainianPriorityPattern, read: ukrainianPriority)],
    dateRange: [Rule(pattern: ukrainianDateRangePattern, read: ukrainianDateRange)],
    keptInTitle: [Rule(pattern: ukrainianDeadlineClockPattern) { $0.group(1) == nil ? nil : true }],
    length: [Rule(pattern: ukrainianLengthPattern, read: ukrainianLength)],
    time: [
      Rule(pattern: ukrainianTimeRangePattern, read: ukrainianTimeRange),
      Rule(pattern: ukrainianTimePattern, read: ukrainianTime),
    ],
    repeats: [
      // The working days, the weekend, and a day of the month before every
      // day and every month, which would leave "по буднях" or the day's number
      // in the title.
      Rule(pattern: ukrainianWorkdaysPattern) { _ in workdays },
      Rule(pattern: ukrainianWeekendPattern) { _ in weekly(every: nil, on: [6, 0]) },
      Rule(pattern: ukrainianMonthDayRepeatPattern, read: ukrainianMonthDayRepeat),
      Rule(pattern: ukrainianWeekdayRepeatPattern, read: ukrainianWeekdayRepeat),
      Rule(pattern: ukrainianIntervalRepeatPattern, read: ukrainianIntervalRepeat),
      Rule(pattern: ukrainianOnceEveryPattern, read: ukrainianOnceEvery),
      Rule(
        pattern: ukrainianCadencePattern(
          #"кожного\s+(?:дня|ранку|вечора)|кожної\s+ночі|кожен\s+день|кожну\s+ніч|щодня|щоранку|щовечора|щоночі"#,
          adverb: "щоденно")
      ) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      Rule(pattern: ukrainianCadencePattern(#"кожного\s+тижня|кожен\s+тиждень|щотижня"#, adverb: "щотижнево")) {
        _ in weekly(every: nil, on: [])
      },
      Rule(pattern: ukrainianCadencePattern(#"кожного\s+місяця|кожен\s+місяць|щомісяця"#, adverb: "щомісячно")) {
        _ in monthly(every: nil, on: nil)
      },
      Rule(pattern: ukrainianCadencePattern(#"кожного\s+року|кожен\s+рік|щороку"#, adverb: "щорічно")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [Rule(pattern: ukrainianDuePattern, read: ukrainianDue)],
    when: [Rule(pattern: ukrainianWhenPattern, read: ukrainianWhen)])

  /// The line with the curly apostrophe (U+2019) and the modifier letter
  /// apostrophe (U+02BC) read as the straight one (U+0027), so the patterns,
  /// written with the straight one, read a word typed with any of the three.
  /// Each replacement is one UTF-16 unit for one, so a match range in the
  /// result is the same range in `line`.
  static func ukrainianForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars {
      scalars.append(scalar == "\u{2019}" || scalar == "\u{02BC}" ? "'" : scalar)
    }
    return String(scalars)
  }

  /// `word` as a pattern that also reads it typed without its apostrophe:
  /// "п'ятниця" and "пятниця".
  private static func ukrainianWord(_ word: String) -> String {
    word.replacingOccurrences(of: "'", with: "'?")
  }

  /// `words` as the alternatives of a pattern, each readable without its
  /// apostrophe.
  private static func ukrainianWords(_ words: [String]) -> String {
    alternation(of: words.map(ukrainianWord))
  }

  /// `word` without apostrophes, which is how a reader compares a typed word
  /// with a name in a table, since a word may be typed with or without its
  /// apostrophe.
  private static func withoutApostrophes(_ word: String) -> String {
    word.replacingOccurrences(of: "'", with: "")
  }

  // MARK: - Words after a detail

  /// The words a detail with no unit of its own ("о 3") may be followed by:
  /// prepositions, conjunctions, particles, and the words that say when or how
  /// often. Any other word after the number makes it a count ("о 2 етапи"), so
  /// it stays in the title.
  private static let ukrainianWordsAfterDetail: Set<String> = [
    "і", "й", "та", "а", "але", "або", "чи", "ж", "б", "би", "в", "у", "на", "з", "із", "зі", "по", "до", "о", "об",
    "від", "за", "при", "для", "без", "про", "після", "перед", "близько", "приблизно", "рівно", "сьогодні", "завтра",
    "післязавтра", "вранці", "вдень", "ввечері", "вночі", "щодня", "щотижня", "щомісяця", "щороку", "кожен",
    "кожного", "кожну", "кожні", "вже", "ще", "теж", "також", "будь",
  ]

  static func ukrainianFollowsAsDetail(_ match: Match) -> Bool {
    followsAsDetail(match, words: ukrainianWordsAfterDetail)
  }

  /// The words before an hour with a part of the day that make it a deadline,
  /// or a bound, not a time: "до 5 вечора", "не пізніше 9 ранку".
  private static let ukrainianDeadlineWords: Set<String> = ["до", "перед", "після", "пізніше", "ніж", "як"]

  // MARK: - Priority

  /// Group 1: a written priority; "терміново" has no group.
  private static let ukrainianPriorityPattern =
    #"\#(cyrillicStart)(пріоритет\s*:?\s*(?:високий|максимальний|найвищий|середній|нормальний|низький|мінімальний)|(?:високий|середній|низький)\s+пріоритет)\#(cyrillicEnd)|(?<=\s)терміново(?=\s*$)|^\s*терміново(?=\s*[，：:,])"#

  private static func ukrainianPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("середн") || phrase.contains("нормальн") { return .p2 }
    if phrase.contains("низьк") || phrase.contains("мінімальн") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 хвилин", "30 хв", "2 години", "2 год", "1,5 години", "1 година 30
  /// хвилин", "півгодини", or a length in words, each maybe after на, протягом,
  /// or близько. Groups: 1 the word that opens a length, 2 a word that makes
  /// the amount a moment, an interval, or a bound; 3 the hours of an amount
  /// with a unit and 4 its minutes; 5 minutes; 6 a length in words. The amount
  /// may not follow a digit, a colon, or a separator, it may not be a side of a
  /// range ("з 14 до 16 годин", "2-3 години"), and it may not name a time ("2
  /// години ночі") or the past ("30 хвилин тому").
  private static let ukrainianLengthPattern =
    #"\#(cyrillicStart)(?:(на|протягом|близько|приблизно|орієнтовно|десь)\s+|(через|за|кожні|кожних|раз\s+на|понад|не\s+більше|не\s+менше|більше|менше|після|перед|до|о|об|з|із|зі|по|у|в)\s+)?(?<![\p{N}:.,])(?<!годині\s{1,3})(?<![\p{N}д]\s(?:до|по)\s)(?<![\p{N}д]\s?[-–—]\s?)(?:(\d+(?:[.,]\d+)?)\s*(?:годин|години|годину|година|год\.?)(?:\s+(\d{1,2})\s*(?:хвилини|хвилин|хвилину|хв\.?))?|(\d+)\s*(?:хвилини|хвилин|хвилину|хв\.?)|(півтори\s+години|пів\s*години|півгодини|чверть\s+години|три\s+чверті\s+години|одна\s+година|дві\s+години))\#(cyrillicEnd)(?!\s+(?:ранку|дня|вечора|ночі|тому)\#(cyrillicEnd))(?!\s+(?:на|у|в)\s+(?:день|тиждень|місяць|рік|добу)\#(cyrillicEnd))(?!\s*[-–—]\s*\d|\s+(?:до|по)\s+\d)"#

  private static func ukrainianLength(_ match: Match) -> Int? {
    if match.group(2) != nil { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    switch match.group(6).map(normalizedPhrase) {
    case "півгодини", "пів години": return 30
    case "півтори години": return 90
    case "чверть години": return 15
    case "три чверті години": return 45
    case "одна година": return 60
    case "дві години": return 120
    default: return nil
    }
  }

  // MARK: - Time

  /// The part of the day a word after an hour names.
  static let ukrainianPartsOfDay: [String: PartOfDay] = [
    "ранку": .morning, "дня": .day, "вечора": .evening, "ночі": .night,
  ]

  /// The words before an hour that make it a clock time: о and об, and
  /// близько, maybe after приблизно or рівно; and з, із, зі, у, and в, which
  /// read only with minutes or a part of the day ("з 3 по 5" is no time).
  private static let ukrainianTimeLead =
    #"(?:(?:приблизно|орієнтовно|рівно|десь)\s+)?(?:об|о)|близько|зі|із|з|у|в"#

  /// "о 15:00", "о 15.30", "о 15", "о 3 годині", "о 3 годині 30 хвилин", "о 3
  /// годині дня", "о 9 ранку", "о 7:30 вечора", and, with no lead, "9 ранку",
  /// "7 вечора", "3 години дня", "3:30 дня"; "опівдні" and "опівночі". A time
  /// written with no Ukrainian word ("15:00", "3pm") is left to English.
  /// Groups: 1 the lead, 2 hour, 3 minute, 4 the word for hour, 5 minutes after
  /// it, 6 the part of the day; 7 to 11 the same without a lead; 12 the word
  /// "опівдні" or "опівночі".
  private static let ukrainianTimePattern =
    [
      #"\#(cyrillicStart)(\#(ukrainianTimeLead))\s+(\d{1,2})(?:[:.](\d{2})|\s+(годин|години|годину|година|годині|год)(?:\s+(\d{1,2})\s*(?:хвилини|хвилин|хвилину|хв))?)?(?:\s+(ранку|дня|вечора|ночі))?\#(cyrillicTimeEnd)"#,
      #"(?<![\p{N}:.,])(\d{1,2})(?:[:.](\d{2})|\s+(годин|години|годину|година|годині)(?:\s+(\d{1,2})\s*(?:хвилини|хвилин|хвилину|хв))?)?\s+(ранку|дня|вечора|ночі)\#(cyrillicTimeEnd)"#,
      #"\#(cyrillicStart)(?:(?:о|об|близько)\s+)?(опівдні|опівночі)\#(cyrillicEnd)"#,
    ].joined(separator: "|")

  private static func ukrainianTime(_ match: Match) -> ClockTime? {
    if let word = match.group(12)?.lowercased() {
      return word == "опівдні" ? ClockTime(minutes: 12 * 60) : ClockTime(minutes: 0, isAfterMidnight: true)
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
    if let word = match.group(first + 4)?.lowercased(), let part = ukrainianPartsOfDay[word] {
      // A count of days is no time, so with no lead a day part needs minutes or
      // the word for hour; a deadline ("до 5 вечора") is none either.
      if lead == nil {
        if part == .day, minuteText == nil, match.group(first + 2) == nil { return nil }
        if let before = wordBefore(match), ukrainianDeadlineWords.contains(before) { return nil }
      }
      return partOfDayTime(hour: hour, minute: minute, part: part)
    }
    // "З 3 по 5" is no time, and neither is "у 3 дні": з, із, зі, у, and в open
    // a time only with minutes.
    if let lead, ["з", "із", "зі", "у", "в"].contains(lead), minuteText == nil { return nil }
    // A bare hour ("о 3") is a time unless a counted noun follows it.
    let isBare = minuteText == nil && match.group(first + 2) == nil
    if isBare, !ukrainianFollowsAsDetail(match) { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  // MARK: - Repeat

  /// A repeat pattern: a cadence written as `phrases` anywhere in the line, or
  /// as `adverb` at its end. A formal adverb ("щоденно") says how a task
  /// repeats at the end of the line, where it cannot be taken for a word of the
  /// title.
  private static func ukrainianCadencePattern(_ phrases: String, adverb: String) -> String {
    #"\#(cyrillicStart)(?:\#(phrases))\#(cyrillicEnd)|\#(cyrillicStart)\#(adverb)(?=\s*$)"#
  }

  /// "по буднях", "по робочих днях", "у будні", "в будні", "у робочі дні", "в
  /// робочі дні", "кожен будній день", "кожен робочий день", "щобудня", and "з
  /// понеділка по п'ятницю".
  private static var ukrainianWorkdaysPattern: String {
    let friday = ukrainianWord("п'ятницю")
    return
      #"\#(cyrillicStart)(?:по\s+(?:буднях|робочих\s+днях)|(?:у|в)\s+(?:будні|робочі\s+дні)|кожен\s+(?:будній|робочий)\s+день|щобудня|(?:з|із|зі)\s+понеділка\s+(?:по|до)\s+\#(friday))\#(cyrillicEnd)"#
  }

  /// "по вихідних", "кожні вихідні", "щовихідних".
  private static let ukrainianWeekendPattern =
    #"\#(cyrillicStart)(?:по\s+вихідних|кожні\s+вихідні|щовихідних)\#(cyrillicEnd)"#

  /// "5 числа кожного місяця", "5-го числа щомісяця", "кожного 5 числа",
  /// "щомісяця 5 числа". Groups 1 to 3: the day of the month in each form.
  private static let ukrainianMonthDayRepeatPattern =
    #"\#(cyrillicStart)(?:(\d{1,2})(?:-?(?:го|е))?\s+числа\s+(?:кожного\s+місяця|щомісяця)|кожного\s+(\d{1,2})(?:-?(?:го|е))?\s+числа|(?:щомісяця|кожного\s+місяця|кожен\s+місяць)\s+(\d{1,2})(?:-?(?:го|е))?\s+числа)\#(cyrillicEnd)"#

  private static func ukrainianMonthDayRepeat(_ match: Match) -> Repeat? {
    (match.group(1) ?? match.group(2) ?? match.group(3)).flatMap(number).flatMap { monthly(every: nil, on: $0) }
  }

  /// "кожен понеділок", "кожну середу і п'ятницю", "кожного понеділка і
  /// четверга", "щопонеділка", "по понеділках", "по понеділках і четвергах".
  /// Groups: 1 the weekdays after кожен, кожну, кожного, or кожної, 2 the
  /// weekdays after по, 3 the weekday after що.
  private static var ukrainianWeekdayRepeatPattern: String {
    let day = ukrainianWeekdayForms([1, 2])
    let plural = ukrainianWeekdayForms([3])
    let genitive = ukrainianWeekdayForms([2])
    let separator = #"(?:\s*,\s*|\s+(?:і|й|та)\s+)"#
    let days = #"(?:\#(day))(?:\#(separator)(?:(?:кожен|кожну|кожного|кожної)\s+)?(?:\#(day))){0,6}"#
    let plurals = #"(?:\#(plural))(?:\#(separator)(?:\#(plural))){0,6}"#
    return
      #"\#(cyrillicStart)(?:(?:кожен|кожну|кожного|кожної)\s+(\#(days))|по\s+(\#(plurals))|що(\#(genitive)))\#(cyrillicEnd)"#
  }

  private static func ukrainianWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = letterWords(match.group(1) ?? match.group(2) ?? match.group(3) ?? "")
      .compactMap(ukrainianWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// The counts a repeat or a day phrase may spell out.
  private static let ukrainianCounts = [
    "два": 2, "дві": 2, "три": 3, "чотири": 4, "п'ять": 5, "шість": 6, "сім": 7, "вісім": 8, "дев'ять": 9,
    "десять": 10,
  ]

  private static var ukrainianCountWords: String {
    ukrainianWords(Array(ukrainianCounts.keys))
  }

  private static func ukrainianCount(_ text: String) -> Int? {
    if let count = number(text) { return count }
    let word = withoutApostrophes(text.lowercased())
    return ukrainianCounts.first(where: { withoutApostrophes($0.key) == word })?.value
  }

  /// "кожні 2 дні", "кожні два тижні", "кожні 3 місяці", "кожні 5 років".
  /// Groups: 1 the count, 2 the unit.
  private static var ukrainianIntervalRepeatPattern: String {
    #"\#(cyrillicStart)кожні\s+(\d{1,2}|\#(ukrainianCountWords))\s+(дні|днів|день|тижні|тижнів|тиждень|місяці|місяців|місяць|роки|років|рік)\#(cyrillicEnd)"#
  }

  private static func ukrainianIntervalRepeat(_ match: Match) -> Repeat? {
    guard let count = match.group(1).flatMap(ukrainianCount), (1...99).contains(count),
      let unit = match.group(2)?.lowercased()
    else { return nil }
    return ukrainianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "раз на тиждень", "раз на 2 тижні", "раз на місяць", "раз на рік", "раз
  /// на день". Groups: 1 the count, if any, 2 the unit.
  private static var ukrainianOnceEveryPattern: String {
    #"\#(cyrillicStart)раз\s+на\s+(?:(\d{1,2}|\#(ukrainianCountWords))\s+)?(день|дні|днів|добу|тиждень|тижні|тижнів|місяць|місяці|місяців|рік|роки|років)\#(cyrillicEnd)"#
  }

  private static func ukrainianOnceEvery(_ match: Match) -> Repeat? {
    guard let unit = match.group(2)?.lowercased() else { return nil }
    guard let countText = match.group(1) else { return ukrainianRepeat(unit: unit, every: nil) }
    guard let count = ukrainianCount(countText), (1...99).contains(count) else { return nil }
    return ukrainianRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func ukrainianRepeat(unit: String, every: Int?) -> Repeat? {
    if unit.hasPrefix("тиж") { return weekly(every: every, on: []) }
    if unit.hasPrefix("місяц") { return monthly(every: every, on: nil) }
    if ["рік", "роки", "років"].contains(unit) {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  // MARK: - Days

  /// The weekday names, Sunday first: nominative, accusative, genitive, and
  /// locative plural.
  private static let ukrainianWeekdays = [
    ["неділя", "неділю", "неділі", "неділях"],
    ["понеділок", "понеділок", "понеділка", "понеділках"],
    ["вівторок", "вівторок", "вівторка", "вівторках"],
    ["середа", "середу", "середи", "середах"],
    ["четвер", "четвер", "четверга", "четвергах"],
    ["п'ятниця", "п'ятницю", "п'ятниці", "п'ятницях"],
    ["субота", "суботу", "суботи", "суботах"],
  ]

  /// The weekday names in the given forms (indexes into a row of
  /// ``ukrainianWeekdays``), longest first, as a pattern that also reads
  /// "п'ятниця" without its apostrophe.
  static func ukrainianWeekdayForms(_ forms: [Int]) -> String {
    var names: [String] = []
    for row in ukrainianWeekdays {
      for form in forms { names.append(row[form]) }
    }
    return ukrainianWords(names)
  }

  /// The weekday a word names in any form, 0 = Sunday.
  private static func ukrainianWeekdayIndex(_ word: String) -> Int? {
    let typed = withoutApostrophes(word)
    return ukrainianWeekdays.firstIndex { row in row.contains { withoutApostrophes($0) == typed } }
  }

  /// Each month's genitive name, as a date reads it, then its abbreviations,
  /// which a date reads only with their dot, January first.
  private static let ukrainianMonths = [
    ["січня", "січ"], ["лютого", "лют"], ["березня", "бер"], ["квітня", "квіт"], ["травня", "трав"],
    ["червня", "черв"], ["липня", "лип"], ["серпня", "серп"], ["вересня", "вер"], ["жовтня", "жовт"],
    ["листопада", "лист"], ["грудня", "груд"],
  ]

  /// "5 травня", "5-го травня", "5 січ.", "5 травня 2027", "5 травня 2027
  /// року": a day with its month, maybe with a year. A month needs its day
  /// number, and an abbreviation its dot.
  static var ukrainianMonthDatePattern: String {
    var names: [String] = []
    var abbreviations: [String] = []
    for month in ukrainianMonths {
      names.append(month[0])
      abbreviations.append(month[1])
    }
    let full = alternation(of: names)
    let short = alternation(of: abbreviations)
    return
      #"\d{1,2}(?:-?го)?\s+(?:(?:\#(full))\.?|(?:\#(short))\.)(?:\s+(?:19|20)\d{2}(?:\s*(?:року|р)(?![\p{Cyrillic}\p{N}])\.?)?)?"#
  }

  /// A date, maybe after its weekday: "5 травня", "у понеділок, 5 жовтня".
  private static var ukrainianDatePattern: String {
    #"(?:(?:у|в|на)\s+(?:\#(ukrainianWeekdayForms([1])))\s*,?\s+)?\#(ukrainianMonthDatePattern)"#
  }

  /// The part of the day that may follow a day: "ввечері", "вранці".
  private static let ukrainianDayPart = #"(?:\s+(?:вранці|уранці|зранку|вдень|удень|ввечері|увечері|вночі|уночі))"#

  /// Group 1: the day, with the words that introduce it.
  private static var ukrainianWhenPattern: String {
    let alternatives = [
      #"(?:на\s+)?(?:сьогодні|завтра|післязавтра)\#(ukrainianDayPart)?"#,
      #"через\s+(?:(?:\d{1,3}|\#(ukrainianCountWords))\s+(?:день|дні|днів|тиждень|тижні|тижнів)|тиждень)"#,
      #"наступного\s+тижня|на\s+наступному\s+тижні"#,
      #"(?:на\s+(?:цих\s+|наступних\s+)?вихідних|(?:у|в|на)\s+(?:ці\s+|наступні\s+)?вихідні)"#,
      #"(?:(?:на|з|із|зі|починаючи\s+з)\s+)?\#(ukrainianDatePattern)"#,
      #"(?:у|в|на)\s+(?:(?:цей|цю|це|наступний|наступну|наступне)\s+)?(?:\#(ukrainianWeekdayForms([1])))\#(ukrainianDayPart)?"#,
      #"(?:цього|цієї|наступного|наступної)\s+(?:\#(ukrainianWeekdayForms([2])))\#(ukrainianDayPart)?"#,
      #"(?:починаючи\s+з|з|із|зі)\s+(?:(?:цього|цієї|наступного|наступної)\s+)?(?:\#(ukrainianWeekdayForms([2])))\#(ukrainianDayPart)?"#,
    ]
    return #"\#(cyrillicStart)(\#(alternatives.joined(separator: "|")))\#(cyrillicEnd)"#
  }

  /// "до п'ятниці", "до 5 травня", "до завтра", "не пізніше п'ятниці", "термін:
  /// 5 травня", "дедлайн у п'ятницю". Group 1: the day.
  private static var ukrainianDuePattern: String {
    let alternatives = [
      "(?:сьогодні|завтра|післязавтра)",
      ukrainianDatePattern,
      #"(?:(?:цей|ця|цю|це|цього|цієї|наступний|наступна|наступну|наступне|наступного|наступної)\s+)?(?:\#(ukrainianWeekdayForms([0, 1, 2])))"#,
    ]
    return
      #"\#(cyrillicStart)(?:(?:до|не\s+пізніше(?:\s+ніж)?|не\s+пізніш\s+як)\s+|(?:термін(?:\s+здачі)?|кінцевий\s+термін|дедлайн)(?:\s*:\s*|\s+)(?:(?:до|у|в)\s+)?)(\#(alternatives.joined(separator: "|")))\#(cyrillicEnd)"#
  }

  private static func ukrainianWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { ukrainianDay($0, in: match) }
  }

  private static func ukrainianDue(_ match: Match) -> Day? {
    match.group(1).flatMap { ukrainianDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  /// The day a phrase names. A weekday with a capital letter that does not open
  /// the line is a name.
  private static func ukrainianDay(_ phrase: String, in match: Match) -> Day? {
    let words = normalizedPhrase(phrase)
    if let date = ukrainianDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let isEvening = ["ввечері", "увечері", "вночі", "уночі"].contains { words.hasSuffix($0) }
    if words.hasPrefix("через ") {
      if words == "через тиждень" { return Day(offset: 7) }
      guard let relative = words.wholeMatch(of: /через ([\p{L}'\d]+) (\p{L}+)/),
        let count = ukrainianCount(String(relative.output.1))
      else { return nil }
      return Day(offset: relative.output.2.hasPrefix("тиж") ? count * 7 : count)
    }
    if words.contains("післязавтра") { return Day(offset: 2, isEvening: isEvening) }
    if words.contains("завтра") { return Day(offset: 1, isEvening: isEvening) }
    if words.contains("сьогодні") { return Day(offset: 0, isEvening: isEvening) }
    let todayWeekday = match.todayWeekday
    if words.contains("вихідн") {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: words.contains("наступн") ? weekend + 7 : weekend)
    }
    if words.hasSuffix("тижня") || words.hasSuffix("тижні") { return Day(offset: 7) }
    let typed = phrase.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
    guard let word = typed.first(where: { ukrainianWeekdayIndex($0.lowercased()) != nil }),
      let weekday = ukrainianWeekdayIndex(word.lowercased())
    else { return nil }
    if isCapitalizedName(word, in: match) { return nil }
    if words.contains("наступн") {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if words.split(separator: " ").contains(where: { $0.hasPrefix("ц") }) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// A written-out date, maybe after its weekday: "5 травня", "у понеділок, 5
  /// жовтня", "5-го травня 2027 року". The words are a phrase as
  /// ``normalizedPhrase(_:)`` leaves it.
  static func ukrainianDate(_ words: String) -> ExplicitDate? {
    guard let match = words.firstMatch(of: /(\d{1,2})(?: го)? (\p{L}+)\.?(?: ((?:19|20)\d{2}))?/),
      let day = number(match.output.1),
      let month = ukrainianMonths.firstIndex(where: { $0.contains(String(match.output.2)) })
    else { return nil }
    return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
  }
}
