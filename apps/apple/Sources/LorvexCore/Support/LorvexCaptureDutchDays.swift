import Foundation

extension LorvexCaptureVocabulary {
  // The Dutch day rules: the due day, the planned day, and the date ranges.
  // The vocabulary's other words are in ``dutch``.

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  private static let dutchNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  // MARK: - Weekdays and months

  /// Each weekday's name, Sunday first.
  private static let dutchWeekdayNameRow = [
    "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag",
  ]

  /// The weekday abbreviations, Sunday first.
  private static let dutchWeekdayAbbreviationRow = ["zo", "ma", "di", "wo", "do", "vr", "za"]

  /// The weekday names, as a pattern without groups.
  static let dutchWeekdayNames = "zondag|maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag"

  /// The weekday abbreviations with their optional dot, as a pattern without
  /// groups.
  static let dutchWeekdayAbbreviations = #"(?:zo|ma|di|wo|do|vr|za)\.?"#

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: "morgenochtend", "vrijdagavond", "morgen vroeg".
  static let dutchDayPartWords = "ochtend|morgen|voormiddag|middag|namiddag|avond|nacht|vroeg"

  /// The weekday a word names, 0 = Sunday: a name ("maandag"), an
  /// abbreviation ("ma", "ma."), or the adverb of repeated days ("maandags").
  /// The word is in the reading form.
  static func dutchWeekdayIndex(_ word: String) -> Int? {
    var key = dutchKey(word)
    if key.hasSuffix(".") { key.removeLast() }
    if let index = dutchWeekdayNameRow.firstIndex(of: key) { return index }
    if let index = dutchWeekdayAbbreviationRow.firstIndex(of: key) { return index }
    guard key.hasSuffix("s"), key.count > 3 else { return nil }
    key.removeLast()
    return dutchWeekdayNameRow.firstIndex(of: key)
  }

  /// The weekday a word names with the part of the day written onto it
  /// ("vrijdagavond", "zaterdagochtend"), and that part; nil for a word that is
  /// no weekday name. The word is as ``dutchKey(_:)`` leaves it.
  private static func dutchWeekdayWithPart(_ word: String) -> (weekday: Int, part: String?)? {
    for (index, name) in dutchWeekdayNameRow.enumerated() where word.hasPrefix(name) {
      let rest = String(word.dropFirst(name.count))
      if rest.isEmpty { return (index, nil) }
      if dutchDayPartWords.split(separator: "|").contains(where: { $0 == rest }) { return (index, rest) }
    }
    return nil
  }

  /// Each month's names, January first: the full name, then the abbreviations.
  private static let dutchMonthRows = [
    ["januari", "jan"], ["februari", "feb"], ["maart", "mrt"], ["april", "apr"], ["mei"], ["juni", "jun"],
    ["juli", "jul"], ["augustus", "aug"], ["september", "sept", "sep"], ["oktober", "okt"], ["november", "nov"],
    ["december", "dec"],
  ]

  /// The month names and abbreviations, longest first, as a pattern without
  /// groups.
  private static var dutchMonthNames: String {
    alternation(of: dutchMonthRows.flatMap { $0 })
  }

  /// The month a word names in any spelling, 0 = January.
  private static func dutchMonthIndex(_ word: String) -> Int? {
    let key = dutchKey(word)
    return dutchMonthRows.firstIndex { $0.contains(key) }
  }

  // MARK: - Dates

  /// "15 oktober", "15 okt", "15 okt.", "1 mei 2027": a day with its month,
  /// maybe with a year. A month needs its day number ("mei" alone is no date).
  static var dutchMonthDatePattern: String {
    #"(?<![\p{N}.,:/-])\#(dutchMonthDateBody)"#
  }

  /// A day with its month and maybe a year, as a pattern without groups and
  /// with no condition on what comes before it.
  private static var dutchMonthDateBody: String {
    #"\d{1,2}\.?\s*(?:\#(dutchMonthNames))\.?(?![\p{Latin}\p{N}\p{M}])(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// "15.10.", "15.10.2026", "15.10.26": a day and a month in digits, with the
  /// dot after the month, maybe with a year. A number that goes on with more
  /// digits or dots ("1.10.2.5", "192.168.1.1") is none.
  static let dutchNumericDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N})|\d{2}(?!\p{N}))?(?![\p{N}]|[.,/]\p{N})"#

  /// "15-10-2026", "15/10/2026", "15-10-26": a day, a month, and a year in
  /// digits, which nothing else reads as.
  static let dutchSlashDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// "15-10", "15/10", "15.10": a day and a month in digits with no closing
  /// dot and no year, which a date reads only after a word that introduces it
  /// ("op 15-10", "voor 15/10"), since "3-4 dagen" and "15.10 uur" are other
  /// things.
  static let dutchLooseDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}(?:\.\d{1,2}|[/-]\d{1,2})(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*(?:uur|uren|u|min|minuten|minuut|dagen|dag|weken|week|maanden|maand|jaar|jaren|keer|maal|x|euro|procent|personen|mensen|stuks|km|kg|m|cm|mm|l)(?![\p{Latin}\p{N}\p{M}]))"#

  /// The words after which a number with dots or dashes is a numbered item of
  /// the title, not a date: "hoofdstuk 1.5.", "versie 2.3.4", "stand 3-1".
  private static let dutchNumberingPattern =
    #"(?:hoofdstuk|punt|pagina|blz\.?|bladzijde|nr\.?|nummer|versie|paragraaf|art\.?|artikel|lid|kamer|lokaal|spoor|perron|lijn|release|build|ticket|issue|bug|dia|slide|stap|niveau|klas|groep|regel|deel|taak|opdracht|ronde|set|score|stand|uitslag)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func dutchFollowsNumbering(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(dutchNumberingPattern) else { return false }
    let before = dutchTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  /// The words and dates that name a day, as a pattern without groups that is
  /// anchored at the end of the text before a detail: "morgen", "vandaag",
  /// "overmorgen", "vanavond", "morgenochtend", a weekday maybe with a part of
  /// the day written onto it, a date with its month ("15 oktober"), and the
  /// adverb of a part of the day ("'s avonds").
  private static var dutchDayBeforeHourPattern: String {
    let parts = "ochtend|morgen|voormiddag|middag|namiddag|avond|nacht"
    let adverbs = #"(?:['’]s\s*|s\s+)?(?:ochtends|morgens|voormiddags|middags|namiddags|avonds|nachts)"#
    return
      #"(?:^|[\s,])(?:vandaag|morgen|overmorgen|vanochtend|vanmorgen|vanmiddag|vanavond|vannacht|(?:morgen|overmorgen)(?:\#(parts))|(?:\#(dutchWeekdayNames))(?:\#(parts))?|\d{1,2}\.?\s*(?:\#(dutchMonthNames))\.?(?:\s+(?:19|20)\d{2})?|\#(adverbs))\s*,?\s*$"#
  }

  /// Whether the text just before `match` ends with a day, a date, or a part of
  /// the day ("morgen", "vrijdagavond", "15 oktober", "'s avonds"), which makes
  /// an hour count that follows it ("morgen 9 uur", "'s avonds 8 uur") a
  /// clock time.
  static func dutchFollowsDay(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(dutchDayBeforeHourPattern) else { return false }
    let before = dutchTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  /// A written-out date and whether it is written in digits only.
  private struct DutchWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``dutchKey(_:)`` leaves it.
  private static func dutchExplicitDate(_ key: String) -> DutchWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})\.?\s*([a-z]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = dutchMonthIndex(String(found.output.2))
    {
      return DutchWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-]?(\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return DutchWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    return nil
  }

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5 mei", "30 mei 2027"),
  /// two numbers with their dots ("3.5."), or a day alone ("3"). The end of a
  /// range may follow its dash directly ("3-5 mei"), which a date alone may
  /// not.
  private static func dutchRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let bare = #"\d{1,2}\#(dutchNoMoreDigits)"#
    return #"\#(lookbehind)\#(dutchMonthDateBody)|\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N}))?|\#(bare)"#
  }

  /// "van 3 tot 5 mei", "van 3 tot en met 5 mei", "3 t/m 5 mei", "van 30 mei
  /// tot 2 juni", "tussen 3 en 5 mei", "3-5 mei", "3 mei tot 5 mei", each maybe
  /// with a year after the end. Groups: 1 the word that opens the range, if any
  /// (van, tussen), 2 the start, 3 a dash between the sides, 4 "tot", "tot en
  /// met", "t/m", "tm", or "en" between them, 5 the end.
  static var dutchDateRangePattern: String {
    let start = dutchRangeSide(isEnd: false)
    let end = dutchRangeSide(isEnd: true)
    return
      #"\#(dutchStart)(?:(van|tussen)\s+)?(\#(start))(?:\s*([-–—])\s*|\s+(tot\s+en\s+met|t\s*/\s*m|t\.m\.|tm|tot|en)\s+)(\#(end))(?![\p{Latin}\p{N}\p{M}'’]|[.,]\p{N})"#
  }

  static func dutchDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = dutchRangeDate(startText), let end = dutchRangeDate(endText), end.month != nil
    else { return nil }
    let lead = match.group(1).map(dutchKey)
    let word = match.group(4).map { dutchPhrase($0).replacingOccurrences(of: " ", with: "") }
    switch word {
    // "T/m" and "tot en met" join the sides after "van" or with no word before
    // them; "tot" joins them after "van", or after a start with its own month
    // ("3 mei tot 5 mei"); "en" joins them only after "tussen".
    case "tm", "t/m", "t.m.", "totenmet":
      guard lead != "tussen" else { return nil }
    case "tot":
      guard lead == "van" || start.month != nil else { return nil }
      guard lead != "tussen" else { return nil }
    case "en":
      guard lead == "tussen" else { return nil }
    default:
      // A dash joins the sides after nothing or "van", and a start that is a
      // day alone only when the dash touches both sides ("3-5 mei"): "Sprint
      // 12 - 20 mei" names a sprint and a date.
      if lead == "tussen" { return nil }
      if start.month == nil, lead == nil, !dashTouchesBothSides(match, start: 2, end: 5) { return nil }
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func dutchRangeDate(_ text: String) -> ExplicitDate? {
    let key = dutchKey(text)
    if let found = dutchExplicitDate(key) { return found.date }
    guard let day = key.wholeMatch(of: /(\d{1,2})\.?/), let value = number(day.output.1) else { return nil }
    return ExplicitDate(day: value)
  }

  /// "van maandag tot woensdag", "maandag t/m woensdag", "van ma t/m wo",
  /// "van maandag tot en met woensdag": a span of weekdays. The abbreviations
  /// count after "van" only. Groups: 1 and 2 the first and the last weekday
  /// after "van", 3 and 4 the first and the last weekday written as names.
  static var dutchWeekdayRangePattern: String {
    let names = dutchWeekdayNames
    let any = #"(?:\#(names)|\#(dutchWeekdayAbbreviations))"#
    let connector = #"(?:tot\s+en\s+met|t\s*/\s*m|t\.m\.|tm|tot)"#
    return
      #"\#(dutchStart)(?:van\s+(\#(any))\s+\#(connector)\s+(\#(any))|(\#(names))\s+\#(connector)\s+(\#(names)))\#(dutchEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first
  /// last day after it, so on a Tuesday "van maandag tot woensdag" runs from
  /// next Monday to the Wednesday after it, where reading "maandag" and
  /// "woensdag" apart would plan next Monday and make the task due tomorrow.
  /// Monday to Friday is the working week, which the repeat rules read, a span
  /// from a day to itself is no span, and a weekday after a title or a name
  /// ("mevrouw Maandag") is a name.
  static func dutchWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1) ?? match.group(3), let lastWord = match.group(2) ?? match.group(4),
      let first = dutchWeekdayIndex(firstWord), let last = dutchWeekdayIndex(lastWord),
      first != last, !(first == 1 && last == 5), !dutchIsNameBefore(match)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// The words after which a weekday is a family or a person's name
  /// ("mevrouw Vrijdag", "familie Zondag").
  private static let dutchNameTitles: Set<String> = [
    "meneer", "mevrouw", "mevr", "mw", "dhr", "heer", "familie", "fam", "dr", "prof", "juffrouw",
  ]

  /// Whether the word before `match` makes a weekday a name.
  private static func dutchIsNameBefore(_ match: Match) -> Bool {
    wordBefore(match).map { dutchNameTitles.contains(dutchKey($0)) } ?? false
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "voor",
  /// "tot", "tot en met", "t/m", "tegen", "uiterlijk" (maybe with "op", "voor",
  /// or "tegen"), "ten laatste", "deadline", "einddatum", "inleverdatum",
  /// each with its colon or space.
  static let dutchDueLead =
    #"(?:uiterlijk(?:\s+(?:op|voor|tegen|tot))?|ten\s+laatste(?:\s+op)?|tot\s+en\s+met|t\s*/\s*m|t\.m\.|tm|tot|tegen|voor|deadline|einddatum|inleverdatum)(?:\s*:\s*|\s+)"#

  /// The days a due phrase may name, as a pattern without groups: vandaag,
  /// vanavond, morgen, overmorgen (each maybe with a part of the day), a
  /// weekday (maybe after deze, komende, aankomende, aanstaande, or volgende,
  /// and maybe with a part of the day written onto it or after it, or beside
  /// "volgende week"), next week, and a date, maybe after its weekday. The
  /// weekend is no due day, and a weekday abbreviation counts only after one
  /// of the words.
  static var dutchDueDay: String {
    let modifier = dutchWeekModifier
    let alternatives = [
      #"(?:vandaag|morgen|overmorgen)(?:\s*(?:\#(dutchDayPartWords)))?"#,
      #"vanochtend|vanmorgen|vanmiddag|vanavond|vannacht"#,
      #"\#(dutchWeekdayBeforeDate)(?:\#(dutchMonthDatePattern)|\#(dutchNumericDatePattern)|\#(dutchSlashDatePattern)|\#(dutchLooseDatePattern))"#,
      #"(?:\#(dutchWeekdayNames))\s+(?:in\s+de\s+)?\#(dutchNextWeekWords)\s+week"#,
      #"\#(dutchNextWeekWords)\s+week\s+(?:op\s+)?(?:\#(dutchWeekdayNames))"#,
      #"(?:\#(modifier)\s+)?(?:\#(dutchWeekdayNames))(?:(?:\#(dutchDayPartWords))|\s+(?:\#(dutchDayPartWords)))?"#,
      #"\#(modifier)\s+\#(dutchWeekdayAbbreviations)"#,
      #"\#(dutchNextWeekWords)\s+week"#,
      dutchMonthDatePattern, dutchNumericDatePattern, dutchSlashDatePattern, dutchLooseDatePattern,
    ]
    return alternatives.joined(separator: "|")
  }

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, or its abbreviation with its dot, then maybe a comma
  /// ("vrijdag 16 oktober", "ma. 5 okt", "vrijdag, 16-10"). The abbreviation
  /// alone is a word too ("ma 5 okt" leaves "ma" in the title).
  static let dutchWeekdayBeforeDate =
    #"(?:(?:\#(dutchWeekdayNames))\s*,?|(?:zo|ma|di|wo|do|vr|za)\.\s*,?)\s+"#

  /// "voor vrijdag", "tot 15 oktober", "uiterlijk morgen", "tegen vrijdag",
  /// "deadline: vrijdag", "t/m 16-10", and "vrijdag uiterlijk". Group 1: the
  /// day after a word that introduces it; group 2: the day before "uiterlijk".
  static var dutchDuePattern: String {
    #"\#(dutchStart)(?:\#(dutchDueLead)(\#(dutchDueDay))|(\#(dutchDueDay))\s+uiterlijk)\#(dutchEnd)"#
  }

  static func dutchDue(_ match: Match) -> Day? {
    (match.group(1) ?? match.group(2)).flatMap { dutchDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// The words before a week or a weekday that make it this week's, the
  /// coming one, next week's, or a past one, as a pattern without groups.
  static let dutchWeekModifier = #"(?:deze|komende|aankomende|aanstaande|volgende|vorige|afgelopen|laatste)"#

  /// The words that make a week the next one.
  private static let dutchNextWeekWords = #"(?:volgende|komende|aankomende|aanstaande)"#

  /// "vandaag", "morgen", "overmorgen" (maybe after "vanaf", and with a part of
  /// the day: "morgenochtend", "morgen vroeg"), "vanochtend", "vanavond", "over
  /// 3 dagen", "over twee weken", "volgende week", "dit weekend", "in het
  /// weekend", "volgend weekend", a weekday ("op vrijdag", "komende vrijdag",
  /// "deze vrijdag", "volgende vrijdag", "volgende week vrijdag", "vrijdag
  /// volgende week", "vrijdagavond"), and a date, maybe with its weekday
  /// ("op 15 oktober", "vrijdag 16 oktober", "vanaf 1-5"). Group 1: the day,
  /// with the words that introduce it.
  static var dutchWhenPattern: String {
    let names = dutchWeekdayNames
    let weekendWords = "weekend|weekeinde"
    let weekend =
      #"(?:(?:in|op|tijdens)\s+(?:het|dit)\s+(?:\#(weekendWords))|(?:dit|komend|komende|aankomend|aankomende|aanstaand|aanstaande|volgend|volgende)\s+(?:\#(weekendWords)))"#
    let dateLead = #"(?:(?:op|vanaf)\s+)?"#
    let looseLead = #"(?:op|vanaf)\s+"#
    let weekdayPrefix = #"(?:\#(dutchWeekdayBeforeDate))?"#
    let strict = #"\#(dutchMonthDatePattern)|\#(dutchNumericDatePattern)|\#(dutchSlashDatePattern)"#
    let weekday =
      #"(?:(?:op|vanaf)\s+)?(?:\#(dutchWeekModifier)\s+)?(?:\#(names))(?:(?:\#(dutchDayPartWords))|\s+(?:\#(dutchDayPartWords)))?"#
    let abbreviated = #"(?:op|vanaf|\#(dutchWeekModifier))\s+\#(dutchWeekdayAbbreviations)"#
    let alternatives = [
      #"(?:\#(names))\s+(?:in\s+de\s+)?\#(dutchNextWeekWords)\s+week"#,
      #"(?:vanaf\s+)?\#(dutchNextWeekWords)\s+week\s+(?:op\s+)?(?:\#(names))"#,
      #"(?:vanaf\s+)?\#(dutchNextWeekWords)\s+week"#,
      weekend,
      #"over\s+(?:\d{1,3}|\#(dutchCountWords))\s+(?:dagen|dag|weken|week)"#,
      #"(?:vanaf\s+)?(?:vandaag|morgen|overmorgen)(?:\s*(?:\#(dutchDayPartWords)))?"#,
      #"vanochtend|vanmorgen|vanmiddag|vanavond|vannacht"#,
      #"\#(dateLead)\#(weekdayPrefix)(?:\#(strict))"#,
      #"\#(looseLead)\#(weekdayPrefix)\#(dutchLooseDatePattern)"#,
      abbreviated,
      weekday,
    ]
    return #"\#(dutchStart)(\#(alternatives.joined(separator: "|")))\#(dutchEnd)"#
  }

  static func dutchWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { dutchDay($0, in: match) }
  }

  /// The words before "morgen" that make it the noun for the morning ("goede
  /// morgen", "elke morgen", "de morgen") or a past day's ("gisteren morgen").
  private static let dutchWordsBeforeMorning: Set<String> = [
    "goede", "goeie", "de", "een", "elke", "iedere", "deze", "die", "vroege", "mooie", "gisteren", "eergisteren",
    "vorige", "afgelopen", "volgende", "komende", "ene", "andere", "hele", "van",
  ]

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when the phrase names no day, or names a past one
  /// ("vorige maandag"), or a name ("mevrouw Vrijdag"), or follows "behalve".
  private static func dutchDay(_ phrase: String, in match: Match) -> Day? {
    // A day after "behalve" is left out, not named ("elke dag behalve zondag").
    if let before = wordBefore(match).map(dutchKey), ["behalve", "uitgezonderd", "exclusief"].contains(before) {
      return nil
    }
    let key = dutchKey(phrase)
    let tokens = dutchPhrase(phrase).split(separator: " ").map {
      String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
    }
    let isEvening = tokens.contains { $0.hasSuffix("avond") || $0.hasSuffix("nacht") }
    if let found = dutchExplicitDate(key) {
      if found.isNumeric, dutchFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let relative = key.firstMatch(of: /\bover (\d{1,3}|[a-z]+) (dagen|dag|weken|week)\b/),
      let count = dutchCount(String(relative.output.1))
    {
      let unit = relative.output.2
      return Day(offset: unit.hasPrefix("week") || unit.hasPrefix("weke") ? count * 7 : count)
    }
    let pastWords = ["vorige", "afgelopen", "laatste"]
    if tokens.contains(where: { pastWords.contains($0) }) { return nil }
    let todayWeekday = match.todayWeekday
    if tokens.contains(where: { $0 == "weekend" || $0 == "weekeinde" }) {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: tokens.contains { $0 == "volgend" || $0 == "volgende" } ? weekend + 7 : weekend)
    }
    let named = tokens.lazy.compactMap { dutchWeekdayWithPart($0) }.first
    let abbreviated = tokens.lazy.compactMap { token -> Int? in
      dutchWeekdayAbbreviationRow.firstIndex(of: token)
    }.first
    if named == nil, abbreviated == nil {
      if tokens.contains("week") { return Day(offset: 7) }
      return dutchDayWord(tokens: tokens, in: match, isEvening: isEvening)
    }
    // A weekday abbreviation is read after a word that introduces it only:
    // "zo", "ma", "di", "wo", "do", "vr", and "za" are ordinary words too.
    if named == nil, tokens.count == 1 { return nil }
    guard let weekday = named?.weekday ?? abbreviated else { return nil }
    if tokens.first.map({ dutchWeekdayIndex($0) != nil }) == true, dutchIsNameBefore(match) { return nil }
    let evening = isEvening || (named?.part.map { $0 == "avond" || $0 == "nacht" } ?? false)
    if tokens.contains("week") || tokens.contains("volgende") {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: evening)
    }
    if tokens.contains("deze") { return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: evening) }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: evening)
  }

  /// "vandaag", "morgen", "overmorgen" (maybe after "vanaf", and with a part of
  /// the day), "vanochtend", "vanavond", and their compounds: today, tomorrow,
  /// and the day after, an evening for "avond" and "nacht". "Morgen" is
  /// tomorrow unless the word before it makes it the morning.
  private static func dutchDayWord(tokens: [String], in match: Match, isEvening: Bool) -> Day? {
    let today = ["vandaag", "vanochtend", "vanmorgen", "vanmiddag", "vanavond", "vannacht"]
    if tokens.contains(where: { today.contains($0) }) { return Day(offset: 0, isEvening: isEvening) }
    if tokens.contains(where: { $0.hasPrefix("overmorgen") }) { return Day(offset: 2, isEvening: isEvening) }
    guard let index = tokens.firstIndex(where: { $0.hasPrefix("morgen") }) else { return nil }
    // A "morgen" that opens the phrase after a word that makes it the morning
    // is a noun ("goede morgen", "elke morgen").
    if index == 0, let before = wordBefore(match), dutchWordsBeforeMorning.contains(dutchKey(before)) { return nil }
    return Day(offset: 1, isEvening: isEvening)
  }
}
