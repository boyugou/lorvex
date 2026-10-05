import Foundation

extension LorvexCaptureVocabulary {
  // The German day rules: the due day, the planned day, and the date ranges.
  // The vocabulary's other words are in ``german``.

  // MARK: - Boundaries

  /// A word boundary for German words: no Latin letter, digit, or apostrophe
  /// on that side, and no letter joined by a hyphen, since a hyphen builds a
  /// compound ("Montag-Termin", "Morgen-Routine", "Montags-Meeting") that is
  /// no day.
  static let germanStart = #"(?<![\p{Latin}\p{N}'’]|\p{L}[-–])"#
  static let germanEnd = #"(?![\p{Latin}\p{N}'’]|[-–]\p{L})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  private static let germanNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  // MARK: - Weekdays and months

  /// Each weekday's names, Sunday first.
  private static let germanWeekdayNameRows = [
    ["sonntag"], ["montag"], ["dienstag"], ["mittwoch"], ["donnerstag"], ["freitag"], ["samstag", "sonnabend"],
  ]

  /// The weekday abbreviations, Sunday first.
  private static let germanWeekdayAbbreviationRow = ["so", "mo", "di", "mi", "do", "fr", "sa"]

  /// The weekday names, as a pattern without groups.
  static let germanWeekdayNames = "sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend"

  /// The weekday abbreviations with their optional dot, as a pattern without
  /// groups.
  static let germanWeekdayAbbreviations = #"(?:so|mo|di|mi|do|fr|sa)\.?"#

  /// The weekday a word names, 0 = Sunday: a name ("Montag"), an abbreviation
  /// ("Mo", "Mo."), or the adverb of repeated days ("montags"). The word is in
  /// the reading form.
  static func germanWeekdayIndex(_ word: String) -> Int? {
    var key = germanKey(word)
    if key.hasSuffix(".") { key.removeLast() }
    if let index = germanWeekdayNameRows.firstIndex(where: { $0.contains(key) }) { return index }
    if let index = germanWeekdayAbbreviationRow.firstIndex(of: key) { return index }
    guard key.hasSuffix("s"), key.count > 3 else { return nil }
    key.removeLast()
    return germanWeekdayNameRows.firstIndex { $0.contains(key) }
  }

  /// The weekday a word names with the part of the day written onto it
  /// ("Samstagabend", "Montagfrüh"), and that part; nil for a word that is no
  /// weekday name. The word is as ``germanKey(_:)`` leaves it.
  private static func germanWeekdayWithPart(_ word: String) -> (weekday: Int, part: String?)? {
    for (index, names) in germanWeekdayNameRows.enumerated() {
      for name in names where word.hasPrefix(name) {
        let rest = String(word.dropFirst(name.count))
        if rest.isEmpty { return (index, nil) }
        if ["abend", "nachmittag", "vormittag", "nacht", "fruh", "morgen", "mittag"].contains(rest) {
          return (index, rest)
        }
      }
    }
    return nil
  }

  /// Each month's names in natural spelling, January first: the full name
  /// (with Austria's "Jänner"), then the abbreviations.
  private static let germanMonthRows = [
    ["januar", "jänner", "jan"], ["februar", "feb"], ["märz", "mär", "mrz"], ["april", "apr"], ["mai"],
    ["juni", "jun"], ["juli", "jul"], ["august", "aug"], ["september", "sept", "sep"], ["oktober", "okt"],
    ["november", "nov"], ["dezember", "dez"],
  ]

  /// The month names that are whole words, as a pattern without groups.
  private static var germanFullMonths: String {
    alternation(of: ["januar", "jänner", "februar", "märz", "april", "mai", "juni", "juli", "august", "september",
      "oktober", "november", "dezember"])
  }

  /// The month abbreviations, as a pattern without groups. Several are names
  /// or words too ("Jan", "Mar", "Sep"), so a date reads one only with a dot.
  private static var germanShortMonths: String {
    alternation(of: ["jan", "feb", "mär", "mrz", "apr", "jun", "jul", "aug", "sept", "sep", "okt", "nov", "dez"])
  }

  /// The month a word names in any spelling, 0 = January. The word is in the
  /// reading form.
  private static func germanMonthIndex(_ word: String) -> Int? {
    let key = germanKey(word)
    return germanMonthRows.firstIndex { $0.contains { germanFold($0) == key } }
  }

  // MARK: - Dates

  /// "15. Oktober", "15 Oktober", "15.Oktober", "1. Mai 2027", "15. Okt.", "15
  /// Okt.": a day with its month, maybe with a year. A month abbreviation
  /// needs a dot of its own or the day's ordinal dot. A month needs its day
  /// number ("Mai" alone is no date).
  static var germanMonthDatePattern: String {
    let full = germanFullMonths
    let short = germanShortMonths
    return
      #"(?<![\p{N}.,:/])\d{1,2}(?:\.\s*(?:\#(full)|\#(short))\.?|\s*(?:\#(full))\.?|\s*(?:\#(short))\.)(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// "15.10.", "15.10.2026", "15.10.26": a day and a month in digits, with the
  /// dot after the month, maybe with a year. A number that goes on with more
  /// digits or dots ("1.10.2.5", "192.168.1.1") is none.
  static let germanNumericDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N})|\d{2}(?!\p{N}))?(?![\p{N}]|[.,/]\p{N})"#

  /// "15.10", "15/10", "15-10": a day and a month in digits with no closing
  /// dot, which a date reads only after a word that introduces it ("bis
  /// 15.10"), since "15.10 Uhr" and "15-10 Stück" are other things.
  static let germanLooseDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}(?:\.\d{1,2}|[/-]\d{1,2})(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*(?:uhr|h)(?![\p{Latin}\p{N}]))"#

  /// "15/10/2026", "15-10-2026": a day, a month, and a year in digits, which
  /// nothing else reads as.
  static let germanSlashDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:20\d{2}|19\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// The words after which a number with dots is an ordinal or a number of the
  /// title, not a date: "Kapitel 1.5.", "Version 2.3.4".
  private static let germanNumberingPattern =
    #"(?:kapitel|punkt|seite|nr\.?|nummer|version|abschnitt|artikel|art\.?|absatz|abs\.?|ziffer|paragraph|paragraf|§|teil|aufgabe|raum|zimmer|gleis|linie|release|build|ticket|issue|bug|folie|slide|schritt|stufe|level|kategorie)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func germanFollowsNumbering(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(germanNumberingPattern) else { return false }
    let before = germanTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  /// A written-out date and whether it is written in digits only.
  private struct GermanWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``germanKey(_:)`` leaves it.
  private static func germanExplicitDate(_ key: String) -> GermanWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})\.?\s*([a-z]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = germanMonthIndex(String(found.output.2))
    {
      return GermanWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-]?(\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return GermanWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    return nil
  }

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5. Mai", "30. Mai 2027"),
  /// two numbers with their dots ("3.5."), or a day alone ("3", "3.").
  private static var germanRangeSide: String {
    let bare = #"\d{1,2}\.?\#(germanNoMoreDigits)"#
    return #"\#(germanMonthDatePattern)|\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N}))?|\#(bare)"#
  }

  /// "vom 3. bis 5. Mai", "vom 3. bis zum 5. Mai", "von 3 bis 5 Mai", "vom 30.
  /// Mai bis 2. Juni", "vom 3.5. bis 5.5.", "zwischen dem 3. und 5. Mai",
  /// "3.-5. Mai", "3. bis 5. Mai", each maybe with a year after the end.
  /// Groups: 1 the word that opens the range, if any (vom, von, zwischen,
  /// zwischen dem), 2 the start, 3 a dash between the sides, 4 "bis" (maybe
  /// with "zum" or "einschließlich") or "und" between them, 5 the end.
  static var germanDateRangePattern: String {
    let side = germanRangeSide
    return
      #"\#(germanStart)(?:(vom|von|zwischen(?:\s+dem)?)\s+)?(\#(side))(?:\s*([-–—])\s*|\s+(bis(?:\s+(?:zum|einschließlich))?|und)\s+)(\#(side))(?![\p{Latin}\p{N}'’]|[.,]\p{N})"#
  }

  static func germanDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = germanRangeDate(startText), let end = germanRangeDate(endText), end.month != nil
    else { return nil }
    let lead = match.group(1).map(germanKey)
    let isBetween = lead?.hasPrefix("zwischen") == true
    switch match.group(4).map(germanKey)?.split(separator: " ").first {
    // "Bis" joins the sides after "vom" or "von", or after a start with its
    // ordinal dot and no word before it ("3. bis 5. Mai"); "und" joins them
    // only after "zwischen".
    case "bis":
      guard !isBetween, lead != nil || startText.hasSuffix(".") else { return nil }
    case "und":
      guard isBetween else { return nil }
    default:
      // A dash joins the sides after nothing or "vom"/"von", and a start that
      // is a day alone only when it has its ordinal dot or the dash touches
      // both sides ("12. - 14. Oktober", "3.-5. Mai"): "Sprint 12 - 20 Mai"
      // names a sprint and a date.
      if isBetween { return nil }
      if start.month == nil, lead == nil, !startText.hasSuffix("."), !dashTouchesBothSides(match, start: 2, end: 5) {
        return nil
      }
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func germanRangeDate(_ text: String) -> ExplicitDate? {
    let key = germanKey(text)
    if let found = germanExplicitDate(key) { return found.date }
    guard let day = key.wholeMatch(of: /(\d{1,2})\.?/), let value = number(day.output.1) else { return nil }
    return ExplicitDate(day: value)
  }

  /// "von Montag bis Mittwoch", "Freitag bis Sonntag", "von Mo bis Mi", "vom
  /// Mo - Mi": a span of weekdays. The abbreviations and the dash count after
  /// "von" or "vom" only. Groups: 1 and 2 the first and the last weekday after
  /// "von", 3 and 4 the first and the last weekday written as names.
  static var germanWeekdayRangePattern: String {
    let names = germanWeekdayNames
    let any = #"(?:\#(names)|\#(germanWeekdayAbbreviations))"#
    return
      #"\#(germanStart)(?:(?:von|vom)\s+(\#(any))(?:\s+bis\s+|\s*[-–—]\s*)(\#(any))|(\#(names))\s+bis\s+(\#(names)))\#(germanEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first
  /// last day after it, so on a Tuesday "von Montag bis Mittwoch" runs from
  /// next Monday to the Wednesday after it, where reading "Montag" and
  /// "Mittwoch" apart would plan next Monday and make the task due tomorrow.
  /// Monday to Friday is the working week, which the repeat rules read, a span
  /// from a day to itself is no span, and a weekday after a title or a name
  /// ("Frau Montag") is a name.
  static func germanWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1) ?? match.group(3), let lastWord = match.group(2) ?? match.group(4),
      let first = germanWeekdayIndex(firstWord), let last = germanWeekdayIndex(lastWord),
      first != last, !(first == 1 && last == 5), !germanIsNameBefore(match)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// The words after which a weekday is a family or a person's name ("Frau
  /// Freitag", "Familie Montag").
  private static let germanNameTitles: Set<String> = [
    "herr", "herrn", "frau", "fraulein", "familie", "fam", "dr", "prof", "hr", "fr",
  ]

  /// Whether the word before `match` makes a weekday a name.
  private static func germanIsNameBefore(_ match: Match) -> Bool {
    wordBefore(match).map { germanNameTitles.contains(germanKey($0)) } ?? false
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "bis",
  /// "bis zum", "bis spätestens", "spätestens (bis|am|zum)", "fällig (bis|am|
  /// zum)", "zum", "Frist", "Abgabefrist", "Deadline", "Stichtag", each with
  /// its colon or space.
  static let germanDueLead =
    #"(?:bis(?:\s+(?:spätestens(?:\s+(?:zum|zur|am))?|zum|zur|einschließlich))?|spätestens(?:\s+(?:bis|am|zum|zur))?|fällig(?:\s+(?:bis|am|zum|zur|spätestens(?:\s+(?:bis|am|zum))?))?|zum|(?:abgabe)?frist|deadline|stichtag)(?:\s*:\s*|\s+)"#

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, or its abbreviation with its dot or a comma, then maybe
  /// a comma and "den" or "dem" ("Freitag, den ", "Freitag ", "Fr. ", "Fr, ").
  /// The abbreviation alone is a word too ("Fr 16.10." leaves "Fr" in the
  /// title).
  static let germanWeekdayBeforeDate =
    #"(?:(?:\#(germanWeekdayNames))\s*,?|(?:so|mo|di|mi|do|fr|sa)(?:\.\s*,?|\s*,))\s+(?:(?:den|dem)\s+)?"#

  /// The days a due phrase may name, as a pattern without groups: heute,
  /// morgen, übermorgen (each maybe with a part of the day), a weekday (maybe
  /// after diesen, kommenden, or nächsten, and maybe with a part of the day
  /// written onto it or after it, or beside "nächste Woche"), next week, and a
  /// date, maybe after its weekday. The weekend is no due day, and a weekday
  /// abbreviation counts only after one of the words.
  static var germanDueDay: String {
    let modifier = germanWeekModifier
    let alternatives = [
      #"(?:heute|morgen|übermorgen)(?:\s+(?:\#(germanDayPartWords)))?"#,
      #"\#(germanWeekdayBeforeDate)(?:\#(germanMonthDatePattern)|\#(germanNumericDatePattern)|\#(germanSlashDatePattern)|\#(germanLooseDatePattern))"#,
      #"(?:\#(germanWeekdayNames))\s+(?:(?:der|in\s+der)\s+)?\#(germanNextWeekWords)\s+woche"#,
      #"\#(germanNextWeekWords)\s+woche\s+(?:am\s+)?(?:\#(germanWeekdayNames))"#,
      #"(?:\#(modifier)\s+)?(?:\#(germanWeekdayNames))(?:abend|nachmittag|vormittag|nacht|früh|morgen|mittag|\s+(?:\#(germanDayPartWords)))?"#,
      #"\#(modifier)\s+\#(germanWeekdayAbbreviations)"#,
      #"(?:nächste[nmrs]?|kommende[nmrs]?)\s+woche"#,
      germanMonthDatePattern, germanNumericDatePattern, germanSlashDatePattern, germanLooseDatePattern,
    ]
    return alternatives.joined(separator: "|")
  }

  /// "bis Freitag", "bis zum 15. Oktober", "bis spätestens morgen", "spätestens
  /// am Freitag", "fällig bis 15.10.", "zum 1.5.", "Frist: Freitag", and "Freitag
  /// spätestens". Group 1: the day after a word that introduces it; group 2:
  /// the day before "spätestens".
  static var germanDuePattern: String {
    #"\#(germanStart)(?:\#(germanDueLead)(\#(germanDueDay))|(\#(germanDueDay))\s+spätestens)\#(germanEnd)"#
  }

  static func germanDue(_ match: Match) -> Day? {
    (match.group(1) ?? match.group(2)).flatMap { germanDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups.
  static let germanDayPartWords = #"früh|morgen|vormittag|mittag|nachmittag|abend|nacht"#

  /// The words before a week or a weekday that make it this week's, the
  /// coming one, next week's, the one after, or a past one, as a pattern
  /// without groups.
  static let germanWeekModifier =
    #"(?:diese[nmrs]?|kommende[nmrs]?|nächste[nmrs]?|übernächste[nmrs]?|letzte[nmrs]?|vorige[nmrs]?|vergangene[nmrs]?|vorherige[nmrs]?)"#

  /// The words that make a week the next one, or the one after.
  private static let germanNextWeekWords = #"(?:nächste[nmrs]?|kommende[nmrs]?|übernächste[nmrs]?)"#

  /// "heute", "morgen", "übermorgen" (maybe after für, auf, or ab, and with a
  /// part of the day: "morgen früh", "heute Abend"), "in 3 Tagen", "in zwei
  /// Wochen", "nächste Woche", "am Wochenende", "nächstes Wochenende", a
  /// weekday ("am Freitag", "diesen Freitag", "nächsten Montag", "Montag
  /// nächste Woche", "nächste Woche Montag"), and a date, maybe with its
  /// weekday, whose abbreviation needs its dot or a comma ("am 15. Oktober",
  /// "Freitag, den 16.10.", "Fr. 16.10.", "ab dem 1.5."). Group 1: the day,
  /// with the words that introduce it.
  static var germanWhenPattern: String {
    let names = germanWeekdayNames
    let weekendModifier = #"(?:diese[nms]?|kommende[nms]?|nächste[nms]?|übernächste[nms]?)"#
    let weekend =
      #"(?:(?:am|an|auf|für|über)\s+(?:(?:\#(weekendModifier)|das|dem)\s+)?|übers\s+|\#(weekendModifier)\s+)wochenende"#
    let weekdayPrefix = #"(?:\#(germanWeekdayBeforeDate))?"#
    let dateLead = #"(?:(?:am|an|ab|vom|für|auf|den|dem)\s+(?:(?:dem|den)\s+)?)?"#
    let looseLead = #"(?:am|an|ab|vom|für|auf)\s+(?:(?:dem|den)\s+)?"#
    let strict = #"\#(germanMonthDatePattern)|\#(germanNumericDatePattern)|\#(germanSlashDatePattern)"#
    let weekday =
      #"(?:(?:am|an|auf|für|ab|vom|von)\s+)?(?:\#(germanWeekModifier)\s+)?(?:(?:\#(names))(?:abend|nachmittag|vormittag|nacht|früh|morgen|mittag|\s+(?:\#(germanDayPartWords)))?|\#(germanWeekdayAbbreviations))"#
    let alternatives = [
      #"(?:\#(names))\s+(?:(?:der|in\s+der)\s+)?\#(germanNextWeekWords)\s+woche"#,
      #"\#(germanNextWeekWords)\s+woche\s+(?:am\s+)?(?:\#(names))"#,
      #"(?:(?:in|für|auf)\s+(?:der|die)\s+|ab\s+(?:(?:der|die)\s+)?)?\#(germanNextWeekWords)\s+woche"#,
      weekend,
      #"in\s+(?:\d{1,3}|\#(germanCountWords))\s+(?:tagen|tage|tag|wochen|woche)"#,
      #"(?:(?:für|auf|ab)\s+)?(?:heute|morgen|übermorgen)(?:\s+(?:\#(germanDayPartWords)))?"#,
      #"\#(dateLead)\#(weekdayPrefix)(?:\#(strict))"#,
      #"\#(looseLead)\#(weekdayPrefix)\#(germanLooseDatePattern)"#,
      weekday,
    ]
    return #"\#(germanStart)(\#(alternatives.joined(separator: "|")))\#(germanEnd)"#
  }

  static func germanWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { germanDay($0, in: match) }
  }

  /// The words before "morgen" that make it the noun for the morning ("guten
  /// Morgen", "am Morgen", "jeden Morgen") or a past day's ("gestern Morgen").
  private static let germanWordsBeforeMorning: Set<String> = [
    "guten", "gut", "schonen", "fruhen", "spaten", "am", "im", "vom", "zum", "beim", "jeden", "jeder", "diesen",
    "dieser", "diesem", "einen", "einem", "eines", "ein", "dem", "den", "der", "des", "nachsten", "kommenden",
    "folgenden", "gestern", "vorgestern", "heute",
  ]

  /// Whether "morgen" in `typed`, as typed, opens the day phrase of `match`
  /// and names tomorrow. A "morgen" in lowercase or in capitals does, unless
  /// the word before it makes it the morning ("am Morgen", "gestern früh").
  /// The capitalized "Morgen" is a noun in the middle of a line, so it names
  /// tomorrow only where a line opens with it ("Morgen Zahnarzt") or a part
  /// of the day follows it ("Morgen Abend", "Morgen früh").
  private static func germanMorgenIsTomorrow(_ typed: String, hasPart: Bool, in match: Match) -> Bool {
    if let before = wordBefore(match), germanWordsBeforeMorning.contains(germanKey(before)) { return false }
    guard let first = typed.first, first.isUppercase, typed.dropFirst().contains(where: \.isLowercase) else {
      return true
    }
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    return hasPart || match.source[..<start].allSatisfy(\.isWhitespace)
  }

  /// The day a phrase names: the phrase of a rule's match, with the words
  /// that introduce it. Nil when the phrase names no day, or names a past one
  /// ("letzten Montag"), or a name ("Frau Freitag"), or follows "außer".
  private static func germanDay(_ phrase: String, in match: Match) -> Day? {
    // A day after "außer" is left out, not named ("jeden Tag außer Sonntag").
    if wordBefore(match).map(germanKey) == "auser" { return nil }
    let key = germanKey(phrase)
    let tokens = germanPhrase(phrase).split(separator: " ").map {
      String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
    }
    let isEvening = tokens.contains { $0.hasSuffix("abend") || $0.hasSuffix("nacht") }
    if let found = germanExplicitDate(key) {
      if found.isNumeric, germanFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if tokens.first == "in", let relative = key.firstMatch(of: /\bin (\d{1,3}|[a-z]+) (tagen|tage|tag|wochen|woche)\b/),
      let count = germanCount(String(relative.output.1))
    {
      return Day(offset: relative.output.2.hasPrefix("woche") ? count * 7 : count)
    }
    let pastWords = ["letzte", "vorige", "vergangene", "vorherige"]
    if tokens.contains(where: { token in pastWords.contains { token.hasPrefix($0) } }) { return nil }
    let isAfterNext = tokens.contains { $0.hasPrefix("ubernachste") }
    let isNext = tokens.contains { $0.hasPrefix("nachste") } || isAfterNext
    let isThis = tokens.contains { $0.hasPrefix("diese") }
    let todayWeekday = match.todayWeekday
    if tokens.contains("wochenende") {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      let isFollowing = tokens.contains { $0.hasPrefix("nachste") || $0.hasPrefix("ubernachste") }
      return Day(offset: weekend + (isAfterNext ? 14 : (isFollowing ? 7 : 0)))
    }
    let named = tokens.lazy.compactMap { germanWeekdayWithPart($0) }.first
    let abbreviated = tokens.lazy.compactMap { token -> Int? in
      germanWeekdayAbbreviationRow.firstIndex(of: token)
    }.first
    if named == nil, abbreviated == nil {
      if tokens.contains("woche") { return Day(offset: isAfterNext ? 14 : 7) }
      return germanDayWord(phrase, tokens: tokens, in: match, isEvening: isEvening)
    }
    // A weekday abbreviation is read after a word that introduces it only:
    // "So", "Mo", "Di", "Mi", "Do", "Fr", and "Sa" are ordinary words too.
    if named == nil, tokens.count == 1 { return nil }
    guard let weekday = named?.weekday ?? abbreviated else { return nil }
    let compoundEvening = named?.part.map { $0 == "abend" || $0 == "nacht" } ?? false
    if tokens.first.map({ germanWeekdayIndex($0) != nil }) == true, germanIsNameBefore(match) { return nil }
    let evening = isEvening || compoundEvening
    if tokens.contains("woche") {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday) + (isAfterNext ? 7 : 0), isEvening: evening)
    }
    if isNext {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday) + (isAfterNext ? 7 : 0), isEvening: evening)
    }
    if isThis { return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: evening) }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: evening)
  }

  /// "heute", "morgen", "übermorgen" with their part of the day: today,
  /// tomorrow, and the day after, an evening for "Abend" and "Nacht". "Morgen"
  /// is tomorrow only by ``germanMorgenIsTomorrow(_:hasPart:in:)``.
  private static func germanDayWord(_ phrase: String, tokens: [String], in match: Match, isEvening: Bool) -> Day? {
    if tokens.contains("ubermorgen") { return Day(offset: 2, isEvening: isEvening) }
    if tokens.contains("heute") { return Day(offset: 0, isEvening: isEvening) }
    guard let index = tokens.firstIndex(of: "morgen") else { return nil }
    let typed = phrase.split(whereSeparator: { !$0.isLetter }).map(String.init)
    guard let word = typed.first(where: { germanKey($0) == "morgen" }) else { return nil }
    // A "morgen" after a word that introduces the day (für, auf, ab) is the day.
    let isOpening = index == 0
    if isOpening, !germanMorgenIsTomorrow(word, hasPart: tokens.count > 1, in: match) { return nil }
    return Day(offset: 1, isEvening: isEvening)
  }
}
