import Foundation

extension LorvexCaptureVocabulary {
  // The Romanian day rules: the due day, the planned day, and the date ranges.
  // The vocabulary's other words are in ``romanian``.

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  private static let romanianNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  // MARK: - Weekdays and months

  /// Each weekday's plain name, Sunday first.
  private static let romanianWeekdayNameRow = [
    "duminica", "luni", "marti", "miercuri", "joi", "vineri", "sambata",
  ]

  /// Each weekday's definite form ("on Mondays"), Sunday first. Saturday's and
  /// Sunday's read like their plain names once the diacritics are left out.
  private static let romanianWeekdayDefiniteRow = [
    "duminica", "lunea", "martea", "miercurea", "joia", "vinerea", "sambata",
  ]

  /// The weekday names, as a pattern without groups.
  static let romanianWeekdayNames = "miercuri|duminica|sambata|vineri|marti|luni|joi"

  /// The definite forms of the weekday names, as a pattern without groups.
  static let romanianWeekdayDefiniteNames = "miercurea|duminica|sambata|vinerea|martea|lunea|joia"

  /// The words that name a part of the day, as a pattern without groups:
  /// "dimineața", "seara", "noaptea", "după-amiaza", "după masă".
  static let romanianPartWords = #"dimineata|seara|noaptea|noapte|dupa[\s-]?amiaza|dupa[\s-]?masa"#

  /// The weekday a word names, 0 = Sunday: a plain name ("luni") or a definite
  /// form ("lunea"). The word is in the reading form.
  static func romanianWeekdayIndex(_ word: String) -> Int? {
    let key = romanianKey(word)
    return romanianWeekdayNameRow.firstIndex(of: key) ?? romanianWeekdayDefiniteRow.firstIndex(of: key)
  }

  /// Each month's names, January first: the full name, then the abbreviations.
  private static let romanianMonthRows = [
    ["ianuarie", "ian"], ["februarie", "feb"], ["martie", "mar"], ["aprilie", "apr"], ["mai"], ["iunie", "iun"],
    ["iulie", "iul"], ["august", "aug"], ["septembrie", "sept", "sep"], ["octombrie", "oct"], ["noiembrie", "nov"],
    ["decembrie", "dec"],
  ]

  /// What may not follow "mai" for it to be the month: the adjectives and
  /// adverbs it makes a comparative of ("3 mai multe", "5 mai târziu").
  private static let romanianMaiNotMonth =
    #"(?!\s+(?:multe|mult|multa|multi|putin|putine|putina|mic|mici|mica|mare|mari|bine|bun|buna|buni|bune|rau|rele|tarziu|devreme|tare|des|rar|repede|incet|departe|aproape|ieftin|scump|simplu|greu|usor|lung|lunga|lungi|scurt|scurta|intai|curand|frumos|frumoasa|sus|jos|nou|noua|noi|vechi|degraba|ales|ceva|nimic|nimeni|inainte|apoi|bogat|sarac|inalt|lat|gros|subtire|cald|rece|sigur|probabil|exact|activ|important|urgent|eficient|detaliat|clar)(?![\p{Latin}\p{N}\p{M}]))"#

  /// The month names and abbreviations, longest first, as a pattern without
  /// groups. "Mai" is the month unless an adjective or adverb of comparison
  /// follows it.
  private static var romanianMonthNames: String {
    alternation(of: romanianMonthRows.flatMap { $0 }.filter { $0 != "mai" }) + "|mai" + romanianMaiNotMonth
  }

  /// The month a word names in any spelling, 0 = January.
  private static func romanianMonthIndex(_ word: String) -> Int? {
    let key = romanianKey(word)
    return romanianMonthRows.firstIndex { $0.contains(key) }
  }

  // MARK: - Dates

  /// "15 octombrie", "15 oct.", "1 mai 2027": a day with its month, maybe with a
  /// year. A month needs its day number ("mai" alone is no date).
  static var romanianMonthDatePattern: String {
    #"(?<![\p{N}.,:/-])\#(romanianMonthDateBody)"#
  }

  /// A day with its month and maybe a year, as a pattern without groups and
  /// with no condition on what comes before it.
  private static var romanianMonthDateBody: String {
    #"\d{1,2}\.?\s*(?:\#(romanianMonthNames))\.?(?![\p{Latin}\p{N}\p{M}])(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// "15.10.", "15.10.2026", "15.10.26": a day and a month in digits, with the
  /// dot after the month, maybe with a year. A number that goes on with more
  /// digits or dots ("1.10.2.5", "192.168.1.1") is none.
  static let romanianNumericDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N})|\d{2}(?!\p{N}))?(?![\p{N}]|[.,/]\p{N})"#

  /// "15/10/2026", "15-10-2026", "15/10/26": a day, a month, and a year in
  /// digits, which nothing else reads as.
  static let romanianSlashDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// "15.10", "15/10", "15-10": a day and a month in digits with no closing dot
  /// and no year, which a date reads only after a word that introduces it ("pe
  /// 15.10", "până la 15/10"), since "3-4 zile" and "la 15.10" (a time) are
  /// other things.
  static let romanianLooseDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}(?:\.\d{1,2}|[/-]\d{1,2})(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*(?:ore|ora|min|minute|minut|zile|zi|saptamani|saptamana|luni|luna|ani|an|ori|x|euro|lei|ron|procente|persoane|oameni|bucati|km|kg|m|cm|mm|l)(?![\p{Latin}\p{N}\p{M}]))"#

  /// The words after which a number with dots or dashes is a numbered item of
  /// the title, not a date: "capitolul 1.5.", "versiunea 2.3.4", "scor 3-1".
  private static let romanianNumberingPattern =
    #"(?:capitolul|capitol|punctul|punct|pagina|pag\.?|nr\.?|numarul|numar|versiunea|versiune|paragraful|paragraf|art\.?|articolul|articol|camera|sala|linia|linie|peronul|peron|clasa|grupa|etapa|pasul|nivelul|nivel|runda|setul|scorul|scor|rezultat|ticket|build|bug|slide|diapozitivul|sectiunea|sectiune|lectia|lectie|exercitiul|exercitiu|tema|problema|figura|tabelul|tabel|anexa|task|sarcina)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func romanianFollowsNumbering(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(romanianNumberingPattern) else { return false }
    let before = romanianTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  /// A written-out date and whether it is written in digits only.
  private struct RomanianWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``romanianKey(_:)`` leaves it.
  private static func romanianExplicitDate(_ key: String) -> RomanianWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})\.?\s*([a-z]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = romanianMonthIndex(String(found.output.2))
    {
      return RomanianWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-]?(\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return RomanianWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    return nil
  }

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5 mai", "30 mai 2027"),
  /// two numbers with their dots ("3.5."), or a day alone ("3"). The end of a
  /// range may follow its dash directly ("3-5 mai"), which a date alone may
  /// not.
  private static func romanianRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let bare = #"\d{1,2}\#(romanianNoMoreDigits)"#
    return #"\#(lookbehind)\#(romanianMonthDateBody)|\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N}))?|\#(bare)"#
  }

  /// "de la 3 la 5 mai", "de la 3 până la 5 mai", "din 3 până în 5 mai", "între
  /// 3 și 5 mai", "în perioada 3-5 mai", "3-5 mai", "de la 30 mai la 2 iunie",
  /// "3 mai până la 5 mai", each maybe with a year after the end. Groups: 1 the
  /// word that opens the range, if any ("de la", "din", "între", "în
  /// perioada", "pe"), 2 the start, 3 a dash between the sides, 4 "la", "până
  /// la", or "și" between them, 5 the end.
  static var romanianDateRangePattern: String {
    let start = romanianRangeSide(isEnd: false)
    let end = romanianRangeSide(isEnd: true)
    return
      #"\#(romanianStart)(?:(de\s+la|din|intre|in\s+perioada|pe)\s+)?(\#(start))(?:\s*([-–—])\s*|\s+(pana\s+la|pana\s+in|pana\s+pe|pana|la|si)\s+)(\#(end))(?![\p{Latin}\p{N}\p{M}]|[.,]\p{N})"#
  }

  static func romanianDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = romanianRangeDate(startText), let end = romanianRangeDate(endText), end.month != nil
    else { return nil }
    let lead = match.group(1).map(romanianPhrase)
    let word = match.group(4).map(romanianPhrase)
    // "Pe" opens a date and no range by itself, as no opening word at all does.
    let isBare = lead == nil || lead == "pe"
    switch word {
    // "La" joins the sides after "de la" only, and "și" after "între" only; "până
    // (la)" joins them after "de la", "din", or "în perioada", or after a start
    // with its own month ("3 mai până la 5 mai").
    case "la":
      guard lead == "de la" else { return nil }
    case "si":
      guard lead == "intre" else { return nil }
    case .some:
      guard lead == "de la" || lead == "din" || lead == "in perioada" || (isBare && start.month != nil) else {
        return nil
      }
    case .none:
      // A dash joins the sides after any opening word but "între" and "din", and
      // a start that is a day alone only when the dash touches both sides
      // ("3-5 mai") or a word that opens a range comes first: "Sprint 12 - 20
      // mai" names a sprint and a date.
      if lead == "intre" || lead == "din" { return nil }
      if start.month == nil, isBare, !dashTouchesBothSides(match, start: 2, end: 5) { return nil }
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func romanianRangeDate(_ text: String) -> ExplicitDate? {
    let key = romanianKey(text)
    if let found = romanianExplicitDate(key) { return found.date }
    guard let day = key.wholeMatch(of: /(\d{1,2})\.?/), let value = number(day.output.1) else { return nil }
    return ExplicitDate(day: value)
  }

  /// "de la luni până miercuri", "de la luni la miercuri", "din luni până în
  /// miercuri", "luni - miercuri", "luni până miercuri": a span of weekdays.
  /// Groups: 1 and 2 the first and the last weekday after "de la" or "din", 3
  /// and 4 the first and the last weekday around a dash, 5 and 6 the first and
  /// the last weekday around "până".
  static var romanianWeekdayRangePattern: String {
    let names = romanianWeekdayNames
    return
      #"\#(romanianStart)(?:(?:de\s+la|din)\s+(\#(names))\s+(?:pana\s+(?:la\s+|in\s+)?|la\s+)(\#(names))|(\#(names))\s*[-–—]\s*(\#(names))|(\#(names))\s+pana\s+(?:la\s+|in\s+)?(\#(names)))\#(romanianEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first
  /// occurrence of the last weekday after it, so on a Tuesday "de la luni până
  /// miercuri" runs from next Monday to the Wednesday after it, where reading
  /// "luni" and "miercuri" apart would plan next Monday and make the task due
  /// tomorrow. Monday to Friday is the working week, which the repeat rules
  /// read, and a span from a day to itself is no span.
  static func romanianWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1) ?? match.group(3) ?? match.group(5),
      let lastWord = match.group(2) ?? match.group(4) ?? match.group(6),
      let first = romanianWeekdayIndex(firstWord), let last = romanianWeekdayIndex(lastWord),
      first != last, !(first == 1 && last == 5)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "până
  /// (la, în, pe)", "cel târziu" (maybe with "la", "pe", or "până la"),
  /// "înainte de", "pentru" ("temă pentru luni"), "termen" ("termen limită"),
  /// "deadline", "scadență", "data limită", each with its colon or space.
  static let romanianDueLead =
    #"(?:cel\s+tarziu(?:\s+(?:pana\s+la|pana\s+pe|la|pe|in))?|pana\s+(?:la|in|pe)|pana|inainte\s+de|pentru|termen(?:ul)?(?:\s+limita)?|deadline|scadenta|scadent|data\s+limita|data\s+scadenta)(?:\s*:\s*|\s+)"#

  /// The days a due phrase may name, as a pattern without groups: azi, astăzi,
  /// diseară, mâine, poimâine (each maybe with a part of the day), a weekday
  /// (maybe with viitoare, următoare, asta, or aceasta, and a part of the
  /// day), next week, and a date, maybe after its weekday. The weekend is no
  /// due day.
  static var romanianDueDay: String {
    let names = romanianWeekdayNames
    let part = romanianPartWords
    let alternatives = [
      #"(?:azi|astazi|maine|poimaine)(?:\s+(?:\#(part)))?"#,
      #"diseara|deseara|(?:in\s+)?seara\s+(?:asta|aceasta)"#,
      #"\#(romanianWeekdayBeforeDate)(?:\#(romanianMonthDatePattern)|\#(romanianNumericDatePattern)|\#(romanianSlashDatePattern)|\#(romanianLooseDatePattern))"#,
      #"(?:\#(names))\s+(?:in\s+)?saptamana\s+\#(romanianNextWeekWords)"#,
      #"(?:in\s+)?saptamana\s+\#(romanianNextWeekWords)\s+(?:\#(names))"#,
      #"(?:\#(names))(?:\s+(?:viitoare|urmatoare|care\s+vine|asta|aceasta))?(?:\s+(?:\#(part)))?"#,
      #"(?:lunea|martea|miercurea|joia|vinerea)\s+(?:viitoare|urmatoare|asta|aceasta)(?:\s+(?:\#(part)))?"#,
      #"(?:in\s+)?saptamana\s+\#(romanianNextWeekWords)"#,
      romanianMonthDatePattern, romanianNumericDatePattern, romanianSlashDatePattern, romanianLooseDatePattern,
    ]
    return alternatives.joined(separator: "|")
  }

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, then maybe a comma ("vineri 16 octombrie", "vineri, 16.10").
  static let romanianWeekdayBeforeDate = #"(?:(?:\#(romanianWeekdayNames))\s*,?\s+)"#

  /// The words that make a week the next one, as a pattern without groups.
  private static let romanianNextWeekWords = #"(?:viitoare|urmatoare|care\s+vine)"#

  /// "până vineri", "până la 15 octombrie", "cel târziu mâine", "înainte de
  /// vineri", "termen: vineri", "deadline 15.10", and "vineri cel târziu".
  /// Group 1: the day after a word that introduces it; group 2: the day before
  /// "cel târziu".
  static var romanianDuePattern: String {
    #"\#(romanianStart)(?:\#(romanianDueLead)(\#(romanianDueDay))|(\#(romanianDueDay))\s+cel\s+tarziu)\#(romanianEnd)"#
  }

  static func romanianDue(_ match: Match) -> Day? {
    (match.group(1) ?? match.group(2)).flatMap { romanianDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "azi", "astăzi", "mâine", "poimâine" (maybe with a part of the day),
  /// "diseară", "în seara asta", "peste 3 zile", "peste o săptămână",
  /// "săptămâna viitoare", "weekendul acesta", "în weekend", "weekendul
  /// viitor", a weekday ("luni", "la luni", "pe luni", "de luni", "luni
  /// viitoare", "luni asta", "luni dimineața", "luni, săptămâna viitoare"), and
  /// a date, maybe with its weekday ("pe 15 octombrie", "vineri 16 octombrie",
  /// "pe 15.10"). Group 1: the day, with the words that introduce it.
  static var romanianWhenPattern: String {
    let names = romanianWeekdayNames
    let part = romanianPartWords
    let weekend =
      #"(?:in\s+)?weekend(?:-?ul)?\s+(?:acesta|asta|care\s+vine|viitor|urmator)|(?:in\s+(?:acest\s+)?|acest\s+)weekend(?:-?ul)?"#
    let dateLead = #"(?:(?:pe|la|in)\s+(?:data\s+de\s+)?)?"#
    let looseLead = #"(?:pe\s+(?:data\s+de\s+)?|(?:la|in)\s+data\s+de\s+)"#
    let weekdayPrefix = #"(?:\#(romanianWeekdayBeforeDate))?"#
    let strict = #"\#(romanianMonthDatePattern)|\#(romanianNumericDatePattern)|\#(romanianSlashDatePattern)"#
    let weekday =
      #"(?:(?:la|in|pe|de)\s+)?(?:\#(names))(?:\s+(?:viitoare|urmatoare|care\s+vine|asta|aceasta|trecuta|trecut|trecute|trecuti|anterioara))?(?:\s+(?:\#(part)))?"#
    let definite =
      #"(?:lunea|martea|miercurea|joia|vinerea)\s+(?:viitoare|urmatoare|asta|aceasta|trecuta|anterioara)(?:\s+(?:\#(part)))?"#
    let alternatives = [
      #"(?:\#(names))\s*,?\s+(?:in\s+)?saptamana\s+\#(romanianNextWeekWords)"#,
      #"(?:in\s+)?saptamana\s+\#(romanianNextWeekWords)\s+(?:\#(names))"#,
      #"(?:in\s+)?saptamana\s+\#(romanianNextWeekWords)"#,
      weekend,
      #"peste\s+(?:\d{1,3}|\#(romanianCountWords))\s+(?:zile|zi|saptamani|saptamana)"#,
      #"(?:azi|astazi|maine|poimaine)(?:\s+(?:\#(part)))?"#,
      #"diseara|deseara|(?:in\s+)?seara\s+(?:asta|aceasta)|(?:in\s+)?noaptea\s+(?:asta|aceasta)"#,
      #"\#(dateLead)\#(weekdayPrefix)(?:\#(strict))"#,
      #"\#(looseLead)\#(weekdayPrefix)\#(romanianLooseDatePattern)"#,
      definite,
      weekday,
    ]
    return #"\#(romanianStart)(\#(alternatives.joined(separator: "|")))\#(romanianEnd)"#
  }

  static func romanianWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { romanianDay($0, in: match) }
  }

  /// The words after which a day is left out of a phrase, not named ("în
  /// fiecare zi fără duminică").
  private static let romanianExceptWords: Set<String> = ["fara", "exceptand", "excluzand", "except"]

  /// The count words, digits, and quantifiers that make "luni" before them the
  /// plural of "lună" ("3 luni", "30 de luni", "două luni", "câteva luni", "mai
  /// multe luni", "ultimele luni"), as a pattern anchored at the end of the text
  /// before a weekday.
  private static var romanianCountBeforeMonthsPattern: String {
    #"(?:^|[\s(,;])(?:\d+|\#(romanianCountWords)|cateva|multe|mai\s+multe|mai\s+putine|alte|ultimele|primele|urmatoarele|viitoarele|zeci|sute|cele|doar|inca)\s+(?:de\s+)?$"#
  }

  /// The words after "luni" that make it the plural of "lună" ("luni de zile",
  /// "luni întregi", "luni la rând", "luni bune"), as a pattern anchored at the
  /// start of the text after a weekday.
  private static let romanianMonthsContinuationPattern = #"^\s*(?:de\s+zile|intregi|la\s+rand|bune|lungi)"#

  /// Whether `match`, a weekday phrase with "luni" in it, counts months: "luni"
  /// is Monday and the plural of "lună", and it is the plural after a number or
  /// a word that counts and before "de zile" or "întregi".
  private static func romanianIsMonthsCount(_ match: Match) -> Bool {
    let before = romanianTextBefore(match)
    if let regex = LorvexCapturePatterns.regex(romanianCountBeforeMonthsPattern),
      regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
    {
      return true
    }
    let after = romanianTextAfter(match)
    guard let regex = LorvexCapturePatterns.regex(romanianMonthsContinuationPattern) else { return false }
    return regex.firstMatch(in: after, range: NSRange(after.startIndex..., in: after)) != nil
  }

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when the phrase names no day, or names a past one
  /// ("luni trecută"), or counts months ("peste 3 luni"), or follows "fără".
  private static func romanianDay(_ phrase: String, in match: Match) -> Day? {
    if let before = wordBefore(match).map(romanianKey), romanianExceptWords.contains(before) { return nil }
    let key = romanianKey(phrase)
    let tokens = romanianPhrase(phrase).split(separator: " ").map {
      String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
    }
    let isEvening = tokens.contains { ["seara", "diseara", "deseara", "noaptea", "noapte"].contains($0) }
    if let found = romanianExplicitDate(key) {
      if found.isNumeric, romanianFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let relative = key.firstMatch(of: /\bpeste (\d{1,3}|[a-z]+) (zile|zi|saptamani|saptamana)\b/),
      let count = romanianCount(String(relative.output.1))
    {
      return Day(offset: relative.output.2.hasPrefix("sapt") ? count * 7 : count)
    }
    let pastWords: Set<String> = ["trecuta", "trecut", "trecute", "trecuti", "anterioara", "anterior"]
    if tokens.contains(where: { pastWords.contains($0) }) { return nil }
    let todayWeekday = match.todayWeekday
    if tokens.contains(where: { $0.hasPrefix("weekend") }) {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: tokens.contains(where: { $0 == "viitor" || $0 == "urmator" }) ? weekend + 7 : weekend)
    }
    guard let weekday = tokens.lazy.compactMap({ romanianWeekdayIndex($0) }).first else {
      if tokens.contains("saptamana") { return Day(offset: 7) }
      return romanianDayWord(tokens: tokens, isEvening: isEvening)
    }
    if tokens.contains("luni"), romanianIsMonthsCount(match) { return nil }
    let nextWords: Set<String> = ["viitoare", "urmatoare"]
    if tokens.contains("saptamana") || tokens.contains(where: { nextWords.contains($0) }) {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if tokens.contains("asta") || tokens.contains("aceasta") {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// "azi", "astăzi", "diseară", "în seara asta", "mâine", "poimâine" (each
  /// maybe with a part of the day): today, tomorrow, and the day after, an
  /// evening for "seara", "noaptea", and "diseară".
  private static func romanianDayWord(tokens: [String], isEvening: Bool) -> Day? {
    if tokens.contains("poimaine") { return Day(offset: 2, isEvening: isEvening) }
    if tokens.contains("maine") { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains(where: { ["azi", "astazi", "diseara", "deseara"].contains($0) }) {
      return Day(offset: 0, isEvening: isEvening)
    }
    // "În seara asta" and "în noaptea asta" are this evening and this night.
    if (tokens.contains("seara") || tokens.contains("noaptea")), tokens.contains(where: { $0 == "asta" || $0 == "aceasta" })
    {
      return Day(offset: 0, isEvening: true)
    }
    return nil
  }
}
