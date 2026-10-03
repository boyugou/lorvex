import Foundation

extension LorvexCaptureVocabulary {
  /// Polish, read for a user who reads Polish. A word needs a boundary of Latin
  /// letters, digits, and apostrophes on both sides, as in English, and the
  /// Polish letters are optional: ą, ć, ę, ń, ó, ś, ź, and ż are read as the
  /// letter without its mark and ł as l ("środa" and "sroda", "dziś" and
  /// "dzis", "łączność" and "lacznosc"), so the patterns are written without
  /// them.
  ///
  /// Polish says a clock time with "o" ("o 15:00", "o 15", "o godz. 15", "o 3
  /// po południu"), a day with "w" or "na" before a weekday ("w piątek", "na
  /// piątek") and a deadline with "do". A bare hour after "o" is a time only
  /// when the line goes on with a word that can follow a time ("o 3 z Anią", "o
  /// 3 jutro") rather than a counted noun ("o 3 osoby"). A clock time after do,
  /// przed, po, or najpóźniej is a deadline, which a task's time cannot hold, so
  /// it stays in the title ("do 18:00", "przed godz. 18:00", "najpóźniej o
  /// 18:00").
  ///
  /// English is read beside Polish, so a detail that needs no Polish word is
  /// left to English, which reads its own "3pm", "15:00", "for 2h", or "from
  /// 3-4pm" whole.
  ///
  /// A weekday is a day only with a word before it: w, we, or na before it, or
  /// od for its start ("od poniedziałku"). Alone it is a noun or a name ("Raport
  /// z poniedziałku", "Sobota" the surname). A weekday with a capital letter
  /// that does not open the line ("Kupić w Piątek") is a name, and so is a
  /// month written with a capital letter after a day number there ("ul. 3
  /// Maja" is a street, "3 maja" a date). "W niedziele"
  /// (on Sundays) alone is read as the coming Sunday, since without the ogonek
  /// it is the same word as "w niedzielę", and it is a habit only in a list
  /// with another plural weekday ("w soboty i niedziele"); every other weekday
  /// in the plural is a habit ("w poniedziałki").
  ///
  /// - Day: dziś, dzisiaj, dzisiaj wieczorem (an evening), jutro, jutro rano,
  ///   pojutrze, each maybe after na ("na jutro") or, for jutro, pojutrze, and
  ///   dziś, after od ("od jutra"); the weekday names after w, we, or na ("w
  ///   poniedziałek", "we wtorek", "w środę", "na piątek"), after od ("od
  ///   poniedziałku"); w ten piątek, w tę środę (this week's), w przyszły
  ///   piątek, w następną sobotę (next week's, weeks starting on Monday); w
  ///   przyszłym tygodniu, na przyszły tydzień, od przyszłego tygodnia; w
  ///   weekend, na weekend, w ten weekend, w przyszły weekend; za 3 dni, za 5
  ///   dni, za 1 dzień, za dwa dni, za tydzień, za dwa tygodnie; a date: 5 maja,
  ///   5. maja, 5-go maja, dnia 5 maja, na 5 maja, od 5 maja, w poniedziałek, 5
  ///   października, 5 sty., 5 maja 2027 r., 5 maja 2027 roku. A weekday alone
  ///   means the next such day, a full week ahead when it names today.
  ///   Wieczorem and w nocy make an evening ("jutro wieczorem"). A month name
  ///   needs a day number ("Majówka" and "Raport za maj" are titles), a month
  ///   abbreviation needs its dot ("5 lip" counts lindens, "5 sty." is a date),
  ///   and a date written in digits ("5.10") is not read. Wielkanoc and Boże
  ///   Narodzenie are not dates.
  /// - Date range: od 3 do 5 maja, od 30 maja do 2 czerwca, od 3 maja do 5
  ///   maja, między 3 a 5 maja, 3–5 maja, 3-5 maja, each maybe with a year after
  ///   the end. The first day is the planned day and the last the due day, so
  ///   another day phrase stays in the title. A day written without its month
  ///   takes the month of the end, the end must be after the start ("od 5 do 3
  ///   maja" stays in the title whole), and an end in an earlier month falls in
  ///   the next year. "Do" joins the sides only after od, and "a" or "i" only
  ///   after między. A day alone opens a range joined by a dash only when the
  ///   dash touches both sides or od comes first: "Sprint 12 - 20 maja" names a
  ///   sprint and a date. Days of the month with no month ("od 3 do 5") are no
  ///   range. A span of weekdays ("od poniedziałku do środy", "od piątku do
  ///   niedzieli") plans the coming first day and is due on the first last day
  ///   after it, so the due day never falls before the planned day; Monday to
  ///   Friday is the working week, a repeat.
  /// - Repeat: codziennie (at the end of the line), każdego dnia, każdy dzień,
  ///   co rano, co wieczór, co noc, co tydzień, każdego tygodnia, cotygodniowo,
  ///   co miesiąc, każdego miesiąca, comiesięcznie, co roku, każdego roku,
  ///   corocznie, co poniedziałek, w każdy poniedziałek, każdego poniedziałku,
  ///   co poniedziałek i czwartek, co drugi poniedziałek, co drugą środę, w
  ///   poniedziałki, w poniedziałki i czwartki, poniedziałkami, w dni robocze, w
  ///   dni powszednie, od poniedziałku do piątku, w weekendy, co weekend, w
  ///   każdy weekend, co 2 dni, co dwa tygodnie, co trzy miesiące, co 5 lat, co
  ///   drugi dzień, co drugi tydzień, raz w tygodniu, raz w miesiącu, raz w
  ///   roku, raz dziennie, raz na dwa tygodnie, 5. każdego miesiąca, 5. dnia
  ///   każdego miesiąca, każdego 5.; the adverbs codziennie, cotygodniowo,
  ///   comiesięcznie, and corocznie only at the end of the line, where a day
  ///   part may follow them ("codziennie rano"). "Codzienny raport" is a title,
  ///   and "na co dzień" (day to day) is none of the above.
  /// - Due: a day after do, najpóźniej, najpóźniej do, nie później niż,
  ///   termin, ostateczny termin, or deadline ("do piątku", "do 5 maja",
  ///   "najpóźniej w piątek", "termin: 5 maja").
  /// - Time: o 15:00, o 15.30, o 15, o godz. 15, o godzinie 15:00, o 3 po
  ///   południu, o 9 rano, o 7 wieczorem, o 2 w nocy, o 4 nad ranem, 9 rano, 7
  ///   wieczorem, w południe, w samo południe, o północy, około 15:00, ok.
  ///   15:00, godz. 15:00, na 15:00, od 18:00; a range: od 14 do 16, od 14:00
  ///   do 16:00, od 9 rano do 6 wieczorem, od 10 do 12 godz., godz. 14-16, w
  ///   godzinach 14-16, między 14:00 a 16:00, and with a dash after od, o, or
  ///   godz. ("o 14:00-16:00"). A time from 1 to 6 o'clock with no part of the
  ///   day is the afternoon, unless written with a leading zero ("06:30"). Rano
  ///   is the morning (12 rano is no time), po południu is noon at 12 and the
  ///   afternoon from 1 to 6, wieczorem is the evening, and w nocy runs past
  ///   midnight: "o 2 w nocy" is 02:00 of the next day, "o 11 w nocy" 23:00. The
  ///   hours are written in digits, which may end in their ordinal suffix ("o
  ///   15-tej", "od 9-tej do 17-tej"): "o piątej" is not read. A dotted time
  ///   reads after o, godz., or około ("o 15.30"); after na and od a time needs a
  ///   colon, since "na 5.10" and "od 5.10" are dates. A range of two bare
  ///   hours counts only when the line goes on with a word that can follow a
  ///   time and no word that names an amount or numbered items comes before it,
  ///   so "od 14 do 16 stron", "Cena od 10 do 20", and "rozdziały od 3 do 5"
  ///   are titles; "między 14 a 16" needs a colon, a part of the day, or godz.,
  ///   and "od 3 do 5" is never read as days. A number before a percent sign, a
  ///   currency sign, or the words "zł" and "PLN" is never a time ("od 10 do 20
  ///   zł", "o 15 zł").
  /// - Length: 30 minut, 30 min, 2 godziny, 2 godz., 2 h, 1,5 godziny, 1
  ///   godzina 30 minut, półtorej godziny, pół godziny, kwadrans, trzy
  ///   kwadranse, dwie godziny, godzinę after na or przez, each maybe after na,
  ///   przez, or około. An amount after za, co, po, przed, do, od, o, w, w
  ///   ciągu, ponad, or a comparison names a moment, an interval, or a bound,
  ///   not a length ("za 2 godziny", "co 2 godziny", "o 15 minut"), "2 godziny
  ///   dziennie" is a rate and "30 minut temu" is the past, neither a length.
  ///   Such an amount stays whole in the title even when English could read
  ///   part of it ("za 15 min", "co 2h", "2h dziennie"). "Godzina" alone is no
  ///   length ("Godzina szczytu"), and "kwadrans po piątej" is a time of day,
  ///   not a length.
  /// - Priority: wysoki priorytet, średni priorytet, niski priorytet (also
  ///   maksymalny, najwyższy, normalny, minimalny, and najniższy), each also
  ///   after the word ("priorytet wysoki", "priorytet: niski"); "pilne" or
  ///   "pilnie" at the end of the line, and "pilne" opening it before a colon
  ///   or comma.
  static let polish = LorvexCaptureVocabulary(
    readingForm: polishForMatching,
    priority: [Rule(pattern: polishPriorityPattern, read: polishPriority)],
    dateRange: [
      Rule(pattern: polishDateRangePattern, read: polishDateRange),
      Rule(pattern: polishWeekdayRangePattern, read: polishWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: polishDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: polishLengthPattern) { polishDeclinesLength($0) ? true : nil },
    ],
    length: [Rule(pattern: polishLengthPattern, read: polishLength)],
    time: [
      Rule(pattern: polishTimeRangePattern, read: polishTimeRange),
      Rule(pattern: polishTimePattern, read: polishTime),
    ],
    repeats: [
      // The working days, the weekend, and a day of the month before every
      // day and every month, which would leave "w dni robocze" or the day's
      // number in the title.
      Rule(pattern: polishWorkdaysPattern) { _ in workdays },
      Rule(pattern: polishWeekendPattern) { _ in weekly(every: nil, on: [6, 0]) },
      Rule(pattern: polishMonthDayRepeatPattern, read: polishMonthDayRepeat),
      Rule(pattern: polishWeekdayRepeatPattern, read: polishWeekdayRepeat),
      Rule(pattern: polishIntervalRepeatPattern, read: polishIntervalRepeat),
      Rule(pattern: polishOnceEveryPattern, read: polishOnceEvery),
      Rule(
        pattern: polishCadencePattern(
          #"kazdego\s+(?:dnia|ranka|wieczora|wieczoru)|kazdej\s+nocy|kazdy\s+(?:dzien|ranek|wieczor)|kazda\s+noc|co\s+(?:rano|wieczor|noc)"#,
          adverb: "codziennie")
      ) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      Rule(
        pattern: polishCadencePattern(#"kazdego\s+tygodnia|kazdy\s+tydzien|co\s+tydzien"#, adverb: "cotygodniowo")
      ) { _ in weekly(every: nil, on: []) },
      Rule(
        pattern: polishCadencePattern(#"kazdego\s+miesiaca|kazdy\s+miesiac|co\s+miesiac"#, adverb: "comiesiecznie")
      ) { _ in monthly(every: nil, on: nil) },
      Rule(pattern: polishCadencePattern(#"kazdego\s+roku|kazdy\s+rok|co\s+roku?"#, adverb: "corocznie")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [Rule(pattern: polishDuePattern, read: polishDue)],
    when: [Rule(pattern: polishWhenPattern, read: polishWhen)])

  /// The line with each Polish letter read without its mark (ą as a, ć as c, ę
  /// as e, ń as n, ó as o, ś as s, ź and ż as z) and ł as l, so the patterns,
  /// written with plain letters, read a line typed with or without them. Each
  /// replacement is one UTF-16 unit for one, so a match range in the result is
  /// the same range in `line`. A letter typed with a separate combining mark
  /// stays as typed.
  static func polishForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in unaccentedForMatching(line).unicodeScalars {
      switch scalar {
      case "ł": scalars.append("l")
      case "Ł": scalars.append("L")
      default: scalars.append(scalar)
      }
    }
    return String(scalars)
  }

  // MARK: - Boundaries and words after a detail

  /// What may follow a clock time: no letter, digit, colon, or apostrophe (the
  /// word or the number goes on), no decimal fraction, no percent or currency
  /// sign and no "zł" or "PLN", with or without a space before it (the number
  /// is an amount: "20%", "20 zł", "15,50 zł"), and no dash before a digit,
  /// which makes the time one side of a range written with a dash
  /// ("14:00-16:00") that English reads whole.
  static let polishTimeEnd =
    #"(?![\p{Latin}\p{N}'’:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*(?:zl|pln)(?![\p{Latin}\p{N}])|\s*[-–—]\s*\d)"#

  /// What may follow a date: no letter, digit, or apostrophe, and no decimal
  /// fraction.
  static let polishDateEnd = #"(?![\p{Latin}\p{N}'’]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let polishNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The words a detail with no unit of its own ("o 3") may be followed by:
  /// prepositions, conjunctions, particles, and the words that say when or how
  /// often. Any other word after the number makes it a count ("o 3 osoby", "o 5
  /// minut"), so it stays in the title.
  private static let polishWordsAfterDetail: Set<String> = [
    "i", "a", "oraz", "lub", "albo", "ale", "z", "ze", "w", "we", "na", "do", "od", "po", "przed", "przy", "przez", "u",
    "o", "dla", "bez", "pod", "nad", "za", "okolo", "mniej", "dzis", "dzisiaj", "jutro", "pojutrze", "dokladnie",
    "punktualnie", "najpozniej", "codziennie", "kazdego", "kazdy", "kazda", "kazde", "co", "juz", "jeszcze", "tez",
    "rowniez", "takze", "koniecznie", "prosze", "pilnie", "pilne", "rano", "wieczorem",
  ]

  static func polishFollowsAsDetail(_ match: Match) -> Bool {
    followsAsDetail(match, words: polishWordsAfterDetail)
  }

  /// The words before an hour that make it a deadline, or a bound, not a time:
  /// "do godz. 5", "najpóźniej o 5", "przed 5 po południu".
  private static let polishDeadlineWords: Set<String> = ["do", "przed", "po", "najpozniej", "niz"]

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "priorytet"; "pilne" and "pilnie" have no group.
  private static var polishPriorityPattern: String {
    let level = "wysoki|maksymalny|najwyzszy|sredni|normalny|niski|minimalny|najnizszy"
    return
      #"\#(latinStart)(priorytet\s*:?\s*(?:\#(level))|(?:\#(level))\s+priorytet)\#(latinEnd)|(?<=\s)(?:pilne|pilnie)(?=\s*$)|^\s*pilne(?=\s*[，：:,])"#
  }

  private static func polishPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("sredni") || phrase.contains("normalny") { return .p2 }
    if phrase.contains("niski") || phrase.contains("minimalny") || phrase.contains("najnizszy") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 minut", "30 min", "2 godziny", "2 godz.", "2 h", "1,5 godziny", "1
  /// godzina 30 minut", "pół godziny", or a length in words, each maybe after
  /// na, przez, or około. Groups: 1 the word that opens a length, 2 a word that
  /// makes the amount a moment, an interval, or a bound; 3 the hours of an
  /// amount with a unit and 4 its minutes; 5 minutes; 6 a length in words; 7
  /// the word after the amount that makes it the past, a difference, or a rate
  /// ("30 minut temu", "15 minut wcześniej", "2 godziny dziennie"). A match
  /// with group 2 or 7 is no length: ``polishLength(_:)`` declines it and a
  /// keep rule claims it, so English does not read the "15 min" of "za 15 min"
  /// or the "2h" of "co 2h". The amount may not follow a digit, a colon, or a
  /// separator, it may not be a side of a range ("od 14 do 16 godz.", "2-3
  /// godziny"), and it may not follow the English "for", which English reads
  /// with its amount.
  private static var polishLengthPattern: String {
    let opener =
      #"(?:(na|przez|okolo|ok\.)\s+|(za|co|po|przed|do|od|o|w|we|w\s+ciagu|ponad|powyzej|ponizej|wiecej\s+niz|mniej\s+niz|nie\s+wiecej\s+niz|nie\s+mniej\s+niz)\s+)?"#
    let boundaries = #"(?<![\p{N}:.,])(?<![\p{N}h]\sdo\s)(?<![\p{N}h]\s?[-–—]\s?)(?<!\bfor\s)"#
    let hours =
      #"(\d+(?:[.,]\d+)?)\s*(?:godziny|godzine|godzina|godzin|godz\.?|h)(?:\s+(?:i\s+)?(\d{1,2})\s*(?:minuty|minute|minut|min\.?))?"#
    let minutes = #"(\d+)\s*(?:minuty|minute|minut|min\.?)"#
    let words =
      #"(poltorej\s+godziny|poltora\s+godziny|pol\s+godziny|kwadrans(?!\s+(?:po|przed)(?![\p{Latin}\p{N}]))|trzy\s+kwadranse|dwie\s+godziny|godzine(?!\s*\p{N}))"#
    let trailing =
      #"(?:\s+(temu|wczesniej|pozniej|dluzej|krocej|dziennie|tygodniowo|miesiecznie|rocznie|dobowo|(?:na|w)\s+(?:dzien|tydzien|tygodniu|miesiac|miesiacu|rok|roku|dobe))\#(latinEnd))?"#
    return
      #"\#(latinStart)\#(opener)\#(boundaries)(?:\#(hours)|\#(minutes)|\#(words))\#(latinEnd)(?!\s*[-–—]\s*\d|\s+do\s+\d)\#(trailing)"#
  }

  /// True for a match that is no length but an amount English could read: a
  /// moment, an interval, or a bound ("za 15 min", "co 2h"), the past, or a rate
  /// ("30 min temu", "2h dziennie").
  private static func polishDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil
  }

  private static func polishLength(_ match: Match) -> Int? {
    if polishDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    switch match.group(6).map(normalizedPhrase) {
    case "pol godziny": return 30
    case "poltorej godziny", "poltora godziny": return 90
    case "kwadrans": return 15
    case "trzy kwadranse": return 45
    case "dwie godziny": return 120
    // "Godzinę" is an hour only for a stretch of time ("na godzinę"); alone it
    // is a noun.
    case "godzine": return ["na", "przez"].contains(match.group(1)?.lowercased()) ? 60 : nil
    default: return nil
    }
  }

  // MARK: - Time

  /// The words after an hour that name a part of the day, as a pattern.
  static let polishPartOfDayWords =
    #"rano|nad\s+ranem|przed\s+poludniem|po\s+poludniu|popoludniu|wieczorem|w\s+nocy"#

  /// The part of the day a word after an hour names.
  static func polishPartOfDay(_ text: String) -> PartOfDay? {
    switch normalizedPhrase(text) {
    case "rano", "nad ranem", "przed poludniem": .morning
    case "po poludniu", "popoludniu": .day
    case "wieczorem": .evening
    case "w nocy": .night
    default: nil
    }
  }

  /// The words before an hour that make it a clock time: "o", maybe after
  /// "około", which reads with or without "godz."; "godz." or "godzinie" with
  /// no "o"; "około" alone, and "na" or "od", which read only with minutes or a
  /// part of the day ("na 3" and "od 3" are no times).
  private static let polishTimeLead =
    #"(?:(?:okolo|kolo|ok\.)\s+)?(?:(?:o|na|od)\s+)?(?:godz\.?|godzinie|godzine)(?:\s+|(?<=\.)\s*)|o\s+|(?:okolo|kolo|ok\.)\s+|(?:na|od)\s+"#

  /// The ordinal ending an hour may carry in writing ("o 15-tej", "od 9-tej do
  /// 17-tej", "o 3-ciej"), with or without its hyphen, as a pattern.
  static let polishHourSuffix = #"(?:-?(?:szej|giej|ciej|tej|mej|stej|ej))?"#

  /// "o 15:00", "o 15.30", "o 15", "o 15-tej", "o godz. 15", "o godzinie
  /// 15:00", "o 3 po południu", "o 9 rano", "o 2 w nocy", "na 15:00", "od
  /// 18:00", "około 15:00", and, with no lead, "9 rano", "7 wieczorem", "3:30
  /// po południu"; "w południe" and "o północy". A time written with no Polish
  /// word ("15:00", "3pm") is left to English. Groups: 1 the lead, 2 hour, 3
  /// the colon or the dot, 4 minute, 5 the part of the day; 6 to 9 the same
  /// without a lead; 10 the word after the lead of "w południe" and "o
  /// północy".
  private static var polishTimePattern: String {
    let leading =
      #"\#(latinStart)(\#(polishTimeLead))(\d{1,2})(?:([.:])(\d{2}))?\#(polishHourSuffix)(?:\s+(\#(polishPartOfDayWords)))?\#(polishTimeEnd)"#
    let partOnly =
      #"\#(latinStart)(?<![.,:])(\d{1,2})(?:([.:])(\d{2}))?\#(polishHourSuffix)\s+(\#(polishPartOfDayWords))\#(polishTimeEnd)"#
    let noonOrMidnight =
      #"\#(latinStart)(?:(?:w|o)\s+(?:samo\s+)?|(?:okolo|kolo)\s+)(poludnie|poludnia|polnocy|polnoc)\#(latinEnd)"#
    return [leading, partOnly, noonOrMidnight].joined(separator: "|")
  }

  private static func polishTime(_ match: Match) -> ClockTime? {
    if let word = match.group(10)?.lowercased() {
      return word.hasPrefix("polud") ? ClockTime(minutes: 12 * 60) : ClockTime(minutes: 0, isAfterMidnight: true)
    }
    let lead = match.group(1).map(normalizedPhrase)
    // The groups of the hour, its separator, its minutes, and the part of the
    // day follow the lead or start the alternative with none.
    let first = lead == nil ? 6 : 2
    guard let hourText = match.group(first), let hour = number(hourText) else { return nil }
    let isDotted = match.group(first + 1) == "."
    let minuteText = match.group(first + 2)
    let minute = minuteText.flatMap(number) ?? 0
    let part = match.group(first + 3).flatMap(polishPartOfDay)
    // A deadline ("do godz. 18", "najpóźniej o 18", "przed 5 po południu") is
    // no start time.
    if let before = wordBefore(match), polishDeadlineWords.contains(before) { return nil }
    if let lead, lead != "o", !lead.contains("godz") {
      // "Na" and "od" introduce dates as often as hours, so they read only
      // with a colon or a part of the day ("na 5.10" is a date); "około" reads
      // with minutes or a part of the day.
      if minuteText == nil, part == nil { return nil }
      if isDotted, lead == "na" || lead == "od" { return nil }
    }
    if let kind = part { return partOfDayTime(hour: hour, minute: minute, part: kind) }
    // A bare hour ("o 3") is a time unless a counted noun follows it.
    let isBare = minuteText == nil
    if isBare, !polishFollowsAsDetail(match) { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  // MARK: - Repeat

  /// A repeat pattern: a cadence written as `phrases` anywhere in the line, or
  /// as `adverb` at its end, where a part of the day may follow it ("codziennie
  /// rano"). An adverb says how a task repeats at the end of the line, where it
  /// cannot be taken for a word of the title.
  private static func polishCadencePattern(_ phrases: String, adverb: String) -> String {
    #"\#(latinStart)(?:\#(phrases))\#(latinEnd)|\#(latinStart)\#(adverb)(?:\s+(?:\#(polishPartOfDayWords)))?(?=\s*$)"#
  }

  /// "w dni robocze", "w dni powszednie", "od poniedziałku do piątku", "w każdy
  /// dzień roboczy", each maybe after "codziennie".
  private static let polishWorkdaysPattern =
    #"\#(latinStart)(?:codziennie\s+)?(?:w\s+dni\s+(?:robocze|powszednie)|od\s+poniedzialku\s+do\s+piatku|(?:w\s+)?kazdy\s+dzien\s+(?:roboczy|powszedni))\#(latinEnd)"#

  /// "w weekendy", "co weekend", "w każdy weekend", "weekendami".
  private static let polishWeekendPattern =
    #"\#(latinStart)(?:co\s+weekend|(?:w\s+)?kazdy\s+weekend|w\s+weekendy|weekendami)\#(latinEnd)"#

  /// "5. każdego miesiąca", "5. dnia każdego miesiąca", "do 5. każdego
  /// miesiąca", "każdego 5.". Groups 1 and 2: the day of the month in each
  /// form. A day followed by a month name is a yearly date, not a repeat.
  private static var polishMonthDayRepeatPattern: String {
    let ordinal = #"(?:\.|-?go)"#
    let months = alternation(of: polishMonths.flatMap { $0 })
    return
      #"\#(latinStart)(?:(?:do\s+)?(\d{1,2})\#(ordinal)?\s+(?:dnia\s+)?kazdego\s+miesiaca|kazdego\s+(\d{1,2})\#(ordinal)(?!\p{N})(?!\s+(?:\#(months))\.?\#(latinEnd)))\#(latinEnd)"#
  }

  private static func polishMonthDayRepeat(_ match: Match) -> Repeat? {
    (match.group(1) ?? match.group(2)).flatMap(number).flatMap { monthly(every: nil, on: $0) }
  }

  /// "co poniedziałek", "co poniedziałek i czwartek", "co drugą środę", "w
  /// każdy poniedziałek", "każdego poniedziałku", "w poniedziałki", "w
  /// poniedziałki, środy i piątki", "poniedziałkami". Sunday in the plural is
  /// the same word as "w niedzielę", so alone it names the day; it is a habit
  /// only in a list with another plural weekday ("w soboty i niedziele", "w
  /// niedziele i soboty"). Groups: 1 drugi or druga after co (every other), 2 the
  /// weekdays after co, 3 the weekdays after każdy, 4 the weekdays after
  /// każdego, 5 the plural weekdays after w, 6 the plural in the instrumental.
  private static var polishWeekdayRepeatPattern: String {
    let day = polishWeekdayForms([0, 1])
    let genitive = polishWeekdayForms([2])
    let plural = alternation(of: polishWeekdays.dropFirst().map { $0[3] })
    let pluralWithSunday = "\(plural)|niedziele"
    let instrumental = polishWeekdayForms([4])
    let separator = #"(?:\s*,\s*|\s+i\s+)"#
    let days = #"(?:\#(day))(?:\#(separator)(?:co\s+|kazd[yae]\s+)?(?:\#(day))){0,6}"#
    let genitives = #"(?:\#(genitive))(?:\#(separator)(?:kazde(?:go|j)\s+)?(?:\#(genitive))){0,6}"#
    let plurals =
      #"(?:\#(plural))(?:\#(separator)(?:\#(pluralWithSunday))){0,6}|niedziele(?:\#(separator)(?:\#(pluralWithSunday))){1,6}"#
    let instrumentals = #"(?:\#(instrumental))(?:\#(separator)(?:\#(instrumental))){0,6}"#
    return
      #"\#(latinStart)(?:co\s+(?:(drugi|druga)\s+)?(\#(days))|(?:w\s+)?kazd[yae]\s+(\#(days))|(?:w\s+)?kazde(?:go|j)\s+(\#(genitives))|(?:w|we)\s+(\#(plurals))|(\#(instrumentals)))\#(latinEnd)"#
  }

  private static func polishWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(2) ?? match.group(3) ?? match.group(4) ?? match.group(5) ?? match.group(6) ?? ""
    let days = letterWords(list).compactMap(polishWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: match.group(1) == nil ? nil : 2, on: days)
  }

  /// The counts a repeat or a day phrase may spell out.
  private static let polishCounts = [
    "dwa": 2, "dwie": 2, "trzy": 3, "cztery": 4, "piec": 5, "szesc": 6, "siedem": 7, "osiem": 8, "dziewiec": 9,
    "dziesiec": 10,
  ]

  private static var polishCountWords: String {
    alternation(of: Array(polishCounts.keys))
  }

  /// "co 2 dni", "co dwa tygodnie", "co 3 miesiące", "co 5 lat", "co 2 tyg.",
  /// "co drugi dzień", "co drugi tydzień". Groups: 1 the count, 2 its unit; 3
  /// the unit after "drugi".
  private static var polishIntervalRepeatPattern: String {
    let units = #"dni|dzien|tygodnie|tygodni|tydzien|tyg\.?|miesiace|miesiecy|miesiac|mies\.?|lata|lat|rok"#
    return
      #"\#(latinStart)co\s+(?:(\d{1,2}|\#(polishCountWords))\s+(\#(units))|drugi\s+(dzien|tydzien|miesiac|rok))\#(latinEnd)"#
  }

  private static func polishIntervalRepeat(_ match: Match) -> Repeat? {
    if let unit = match.group(3)?.lowercased() { return polishRepeat(unit: unit, every: 2) }
    guard let countText = match.group(1)?.lowercased(), let count = number(countText) ?? polishCounts[countText],
      (1...99).contains(count), let unit = match.group(2)?.lowercased()
    else { return nil }
    return polishRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "raz w tygodniu", "raz w miesiącu", "raz w roku", "raz dziennie", "raz na
  /// tydzień", "raz na dwa tygodnie", "raz na 3 miesiące". Groups: 1 the unit
  /// after "w", 2 the count after "na", 3 its unit, 4 "dziennie".
  private static var polishOnceEveryPattern: String {
    #"\#(latinStart)raz\s+(?:w\s+(tygodniu|miesiacu|roku)|na\s+(?:(\d{1,2}|\#(polishCountWords))\s+)?(tydzien|tygodnie|tygodni|miesiac|miesiace|miesiecy|rok|lata|lat|dzien|dni)|(dziennie))\#(latinEnd)"#
  }

  private static func polishOnceEvery(_ match: Match) -> Repeat? {
    if match.group(4) != nil { return polishRepeat(unit: "dzien", every: nil) }
    if let unit = match.group(1)?.lowercased() { return polishRepeat(unit: unit, every: nil) }
    guard let unit = match.group(3)?.lowercased() else { return nil }
    guard let countText = match.group(2)?.lowercased() else { return polishRepeat(unit: unit, every: nil) }
    guard let count = number(countText) ?? polishCounts[countText], (1...99).contains(count) else { return nil }
    return polishRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func polishRepeat(unit: String, every: Int?) -> Repeat? {
    if unit.hasPrefix("tyd") || unit.hasPrefix("tyg") { return weekly(every: every, on: []) }
    if unit.hasPrefix("mies") { return monthly(every: every, on: nil) }
    if unit.hasPrefix("rok") || unit.hasPrefix("lat") {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  // MARK: - Days

  /// The weekday names without accents, Sunday first: nominative, accusative,
  /// genitive, plural, and instrumental plural.
  private static let polishWeekdays = [
    ["niedziela", "niedziele", "niedzieli", "niedziele", "niedzielami"],
    ["poniedzialek", "poniedzialek", "poniedzialku", "poniedzialki", "poniedzialkami"],
    ["wtorek", "wtorek", "wtorku", "wtorki", "wtorkami"],
    ["sroda", "srode", "srody", "srody", "srodami"],
    ["czwartek", "czwartek", "czwartku", "czwartki", "czwartkami"],
    ["piatek", "piatek", "piatku", "piatki", "piatkami"],
    ["sobota", "sobote", "soboty", "soboty", "sobotami"],
  ]

  /// The weekday names in the given forms (indexes into a row of
  /// ``polishWeekdays``), longest first, as a pattern.
  static func polishWeekdayForms(_ forms: [Int]) -> String {
    var names: [String] = []
    for row in polishWeekdays {
      for form in forms { names.append(row[form]) }
    }
    return alternation(of: names)
  }

  /// The weekday a word names in any form, 0 = Sunday.
  static func polishWeekdayIndex(_ word: String) -> Int? {
    polishWeekdays.firstIndex { $0.contains(word) }
  }

  /// Each month's genitive name, as a date reads it, then its abbreviations,
  /// January first.
  private static let polishMonths = [
    ["stycznia", "sty"], ["lutego", "lut"], ["marca", "mar"], ["kwietnia", "kwi"], ["maja", "maj"],
    ["czerwca", "cze"], ["lipca", "lip"], ["sierpnia", "sie"], ["wrzesnia", "wrz"], ["pazdziernika", "paz"],
    ["listopada", "lis"], ["grudnia", "gru"],
  ]

  /// The month a lowercase word names in either spelling, 0 = January.
  private static func polishMonthIndex(_ word: String) -> Int? {
    polishMonths.firstIndex { $0.contains(word) }
  }

  /// "5 maja", "5. maja", "5-go maja", "5 sty.", "5 maja 2027", "5 maja 2027
  /// r.", "5 maja 2027 roku": a day with its month, maybe with a year. A month
  /// needs its day number, and an abbreviation needs its dot, since several
  /// are ordinary words too ("5 lip" counts lindens, "5 sie" is "5 się"); the
  /// nominative "maj" stands without one.
  static var polishMonthDatePattern: String {
    let full = alternation(of: polishMonths.map { $0[0] } + ["maj"])
    let short = alternation(of: polishMonths.map { $0[1] })
    return
      #"\d{1,2}(?:\.|-?go)?\s+(?:(?:\#(full))\.?|(?:\#(short))\.)(?:\s+(?:19|20)\d{2}(?:\s*(?:roku|r(?![\p{Latin}\p{N}])\.?))?)?"#
  }

  /// A date, maybe after its weekday: "5 maja", "w poniedziałek, 5
  /// października".
  private static var polishDatePattern: String {
    #"(?:(?:w|we|na)\s+(?:\#(polishWeekdayForms([1])))\s*,?\s+)?\#(polishMonthDatePattern)"#
  }

  /// The part of the day that may follow a day: "rano", "wieczorem".
  private static let polishDayPart = #"(?:\s+(?:\#(polishPartOfDayWords)))"#

  /// Group 1: the day, with the words that introduce it.
  private static var polishWhenPattern: String {
    let modifiers = #"(?:(?:ten|te|ta|przyszly|przyszla|nastepny|nastepna)\s+)?"#
    let genitiveModifiers = #"(?:(?:tego|tej|przyszlego|przyszlej|nastepnego|nastepnej)\s+)?"#
    let alternatives = [
      #"(?:na\s+)?(?:dzisiaj|dzis|jutro|pojutrze)\#(polishDayPart)?"#,
      #"od\s+(?:dzis|dzisiaj|jutra|pojutrza)"#,
      #"za\s+(?:(?:\d{1,3}|\#(polishCountWords))\s+(?:dzien|dni|tydzien|tygodnie|tygodni)|tydzien)"#,
      #"(?:(?:w|we)\s+(?:przyszlym|nastepnym)\s+tygodniu|na\s+(?:przyszly|nastepny)\s+tydzien|od\s+(?:przyszlego|nastepnego)\s+tygodnia)"#,
      #"(?:w|we|na)\s+(?:(?:ten|przyszly|nastepny)\s+)?weekend"#,
      #"(?:(?:na|od|dnia)\s+)?\#(polishDatePattern)"#,
      #"(?:w|we|na)\s+\#(modifiers)(?:\#(polishWeekdayForms([1])))\#(polishDayPart)?"#,
      #"od\s+\#(genitiveModifiers)(?:\#(polishWeekdayForms([2])))"#,
    ]
    return #"\#(latinStart)(\#(alternatives.joined(separator: "|")))\#(latinEnd)"#
  }

  /// "do piątku", "do 5 maja", "do jutra", "najpóźniej w piątek", "nie później
  /// niż do piątku", "termin: 5 maja", "deadline piątek". Group 1: the day.
  private static var polishDuePattern: String {
    let modifiers =
      #"(?:(?:ten|te|ta|tego|tej|przyszly|przyszla|przyszlego|przyszlej|nastepny|nastepna|nastepnego|nastepnej)\s+)?"#
    let alternatives = [
      "(?:dzis|dzisiaj|jutro|jutra|pojutrze|pojutrza)",
      polishMonthDatePattern,
      #"\#(modifiers)(?:\#(polishWeekdayForms([0, 1, 2])))"#,
    ]
    let lead =
      #"(?:do|najpozniej(?:\s+(?:do|w|we|na))?|nie\s+pozniej\s+niz(?:\s+(?:do|w|we|na))?)\s+|(?:(?:ostateczny\s+)?termin(?:\s+(?:wykonania|oddania|realizacji|zlozenia))?|deadline)(?:\s*:\s*|\s+)(?:(?:do|na|w|we)\s+)?"#
    return #"\#(latinStart)(?:\#(lead))(\#(alternatives.joined(separator: "|")))\#(latinEnd)"#
  }

  private static func polishWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { polishDay($0, in: match) }
  }

  private static func polishDue(_ match: Match) -> Day? {
    match.group(1).flatMap { polishDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  /// The words that make a weekday next week's, and this week's.
  private static let polishNextWords: Set<String> = [
    "przyszly", "przyszla", "przyszlego", "przyszlej", "nastepny", "nastepna", "nastepnego", "nastepnej",
  ]
  private static let polishThisWords: Set<String> = ["ten", "te", "ta", "tego", "tej"]

  /// The day a phrase names. A weekday or a month with a capital letter that
  /// does not open the line is a name ("Kupić w Piątek", "ul. 3 Maja").
  private static func polishDay(_ phrase: String, in match: Match) -> Day? {
    let words = normalizedPhrase(phrase)
    if let date = polishDate(words) {
      let month = phrase.split(whereSeparator: { !$0.isLetter }).first { polishMonthIndex($0.lowercased()) != nil }
      if let month, isCapitalizedName(String(month), in: match) { return nil }
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = words.split(separator: " ").map(String.init)
    let isEvening = words.hasSuffix("wieczorem") || words.hasSuffix("w nocy")
    if tokens.first == "za" {
      guard let relative = words.wholeMatch(of: /za (?:(\w+) )?(dzien|dni|tydzien|tygodnie|tygodni)/) else { return nil }
      var count = 1
      if let countText = relative.output.1 {
        guard let value = number(countText) ?? polishCounts[String(countText)] else { return nil }
        count = value
      }
      return Day(offset: relative.output.2.hasPrefix("ty") ? count * 7 : count)
    }
    if tokens.contains(where: { $0 == "pojutrze" || $0 == "pojutrza" }) { return Day(offset: 2, isEvening: isEvening) }
    if tokens.contains(where: { $0 == "jutro" || $0 == "jutra" }) { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains(where: { $0 == "dzis" || $0 == "dzisiaj" }) { return Day(offset: 0, isEvening: isEvening) }
    let todayWeekday = match.todayWeekday
    let isNext = tokens.contains(where: polishNextWords.contains)
    if tokens.contains("weekend") {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    if tokens.contains(where: { $0 == "tydzien" || $0 == "tygodniu" || $0 == "tygodnia" }) { return Day(offset: 7) }
    let typed = phrase.split(whereSeparator: { !$0.isLetter }).map(String.init)
    guard let word = typed.first(where: { polishWeekdayIndex($0.lowercased()) != nil }),
      let weekday = polishWeekdayIndex(word.lowercased())
    else { return nil }
    if isCapitalizedName(word, in: match) { return nil }
    if isNext {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if tokens.contains(where: polishThisWords.contains) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// A written-out date: "5 maja", "5. maja", "5-go maja 2027 r.". The words
  /// are a phrase as ``normalizedPhrase(_:)`` leaves it.
  static func polishDate(_ words: String) -> ExplicitDate? {
    guard let match = words.firstMatch(of: /(\d{1,2})(?:\.| go)? (\p{L}+)\.?(?: ((?:19|20)\d{2}))?/),
      let day = number(match.output.1),
      let month = polishMonthIndex(String(match.output.2))
    else { return nil }
    return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
  }
}
