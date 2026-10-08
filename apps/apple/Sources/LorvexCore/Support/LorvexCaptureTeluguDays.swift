import Foundation

extension LorvexCaptureVocabulary {
  // The Telugu day rules: the planned day, the due day, written dates, and
  // date ranges. The vocabulary's other words are in ``telugu``.

  // MARK: - Names

  /// Each weekday's name without its ending, Sunday first. Every name is a stem
  /// that "ం", "ము", or an ending of the day phrases follows ("సోమవారం",
  /// "సోమవారానికి"). The short forms the system writes (ఆది, సోమ, మంగళ, బుధ,
  /// గురు, శుక్ర, శని, and its one-syllable forms) are ordinary words, names,
  /// and planets, so none of them is here.
  private static let teluguWeekdayStemList: [[String]] = [
    ["ఆదివార"], ["సోమవార"], ["మంగళవార"], ["బుధవార"], ["గురువార", "బృహస్పతివార"], ["శుక్రవార"], ["శనివార"],
  ]

  /// The weekday stems as keys, longest first, each with its weekday (0 =
  /// Sunday).
  private static let teluguWeekdayKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (weekday, stems) in teluguWeekdayStemList.enumerated() {
      for stem in stems { keys.append((teluguKey(stem), weekday)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The weekday stems as a pattern, longest first.
  static let teluguWeekdayStems = teluguAlternation(of: teluguWeekdayStemList.flatMap { $0 })

  /// A weekday as the day phrases read it: the plain name ("సోమవారం",
  /// "సోమవారము"), emphatic ("సోమవారమే"), with the dative ("సోమవారానికి"), or
  /// with "నాడు" glued ("సోమవారంనాడు"), as a pattern without groups.
  static var teluguWeekdayForm: String {
    #"(?:\#(teluguWeekdayStems))(?:ం|ము|మే|ానికి|ానికే|ంనాడు)"#
  }

  /// The weekday a word names, 0 = Sunday, with or without an ending glued to
  /// it ("సోమవారం", "సోమవారానికి", "సోమవారాల్లో").
  static func teluguWeekdayIndex(_ word: String) -> Int? {
    let key = teluguKey(word)
    return teluguWeekdayKeys.first(where: { teluguHasPrefix(key, $0.key) })?.index
  }

  /// Each month's Gregorian names, January first: the full name in the
  /// spellings people type, and the short forms the system writes next to a
  /// day ("15 అక్టో"), which the full name of a month with no short form
  /// ("మార్చి", "మే", "జూన్", "జులై") stands for.
  private static let teluguMonthRows: [(full: [String], short: [String])] = [
    (["జనవరి", "జనవరీ"], ["జన"]),
    (["ఫిబ్రవరి", "ఫిబ్రవరీ", "ఫెబ్రవరి"], ["ఫిబ్ర"]),
    (["మార్చి", "మార్చ్"], []),
    (["ఏప్రిల్", "ఏప్రిలు"], ["ఏప్రి"]),
    (["మే"], []),
    (["జూన్", "జూను"], []),
    (["జులై", "జూలై"], []),
    (["ఆగస్టు", "ఆగస్ట్", "ఆగష్టు", "ఆగష్ట్"], ["ఆగ"]),
    (["సెప్టెంబర్", "సెప్టెంబరు"], ["సెప్టెం"]),
    (["అక్టోబర్", "అక్టోబరు"], ["అక్టో"]),
    (["నవంబర్", "నవంబరు"], ["నవం"]),
    (["డిసెంబర్", "డిసెంబరు"], ["డిసెం"]),
  ]

  /// The month names as keys, longest first, each with its month (0 =
  /// January).
  private static let teluguMonthKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (month, row) in teluguMonthRows.enumerated() {
      for name in row.full + row.short { keys.append((teluguKey(name), month)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The month a word names, 0 = January, with or without an ending glued to
  /// it.
  private static func teluguMonthIndex(_ word: String) -> Int? {
    let key = teluguKey(word)
    return teluguMonthKeys.first(where: { teluguHasPrefix(key, $0.key) })?.index
  }

  // MARK: - Dates

  /// The words for "date" that follow a day number ("15వ తేదీ"), as a pattern
  /// without groups.
  private static let teluguDateWord = #"(?:తేదీ|తేది|తారీఖు|తారీకు)"#

  /// The words for "date" as keys.
  private static let teluguDateWordKeys: [String] = ["తేదీ", "తేది", "తారీఖు", "తారీకు"].map(teluguKey)

  /// A day number, plain ("15") or with its ordinal sign and the word for date
  /// ("15వ", "15వ తేదీ"), as a pattern without groups.
  private static let teluguDayNumber = #"\d{1,2}(?:వ(?:\s*\#(teluguDateWord))?)?"#

  /// The label that may stand before a date.
  private static let teluguDateLabel = #"(?:\#(teluguDateWord)\s*[:：]?\s*)"#

  /// The words after a month and a day number that make the number an amount
  /// ("మే 10 రూపాయలు"), as a pattern that fails where one follows.
  private static let teluguNoAmountAfter =
    #"(?!\s*(?:రూపాయలు|రూపాయల|రూపాయి|డాలర్లు|డాలర్|నిమిషాలు|నిమిషాల|నిమిషం|గంటలు|గంటల|గంట|రోజులు|రోజుల|వారాలు|వారాల|నెలలు|నెలల|సంవత్సరాలు|మంది|సార్లు|కిలోలు|కిలో|%)\#(teluguEnd))"#

  /// "15 అక్టోబర్", "15వ తేదీ అక్టోబర్", "15 అక్టోబర్ 2026", "15 అక్టోబర్, 2026",
  /// "15 అక్టో", "అక్టోబర్ 15", "అక్టోబర్ 15వ తేదీ", "అక్టోబర్ 15, 2026": a day
  /// number and a Gregorian month name, in either order, maybe with a year. A
  /// short month name is read only after its day number, since it is a word's
  /// first letters too ("ఆగ"). A month needs its day number, so "అక్టోబర్" alone
  /// is no date.
  static var teluguMonthDatePattern: String {
    let full = teluguAlternation(of: teluguMonthRows.flatMap { $0.full })
    let short = teluguAlternation(of: teluguMonthRows.flatMap { $0.short })
    let year = #"(?:,?\s+(?:19|20)\d{2}(?!\p{N}))?"#
    return
      #"(?:\#(teluguDayNumber)\s*(?:(?:\#(full))|(?:\#(short))\.?)\#(year)|(?:\#(full))\s*\#(teluguDayNumber)\#(teluguNoMoreDigits)\#(teluguNoAmountAfter)\#(year))"#
  }

  /// "15వ తేదీ", "15 తేదీ": a day of the month with no month, the stem of the
  /// phrase for "on the 15th" ("15వ తేదీన") or "from the 15th".
  private static let teluguDayOfMonthStem = #"\d{1,2}(?:వ)?\s*\#(teluguDateWord)"#

  /// The endings that go with a date: "న" (on), "కి" or "కు" (for), and "నాడు",
  /// "నుండి", "నుంచి", "నించి", or "కోసం" as words of their own, as a pattern
  /// without groups.
  private static let teluguDateEnding = #"(?:·(?:న|కి|కు)|\s+(?:నాడు|నుండి|నుంచి|నించి|కోసం))"#

  /// The weekday the system writes after a long date ("15 అక్టోబర్ 2026,
  /// గురువారం"), as a pattern without groups.
  private static let teluguWeekdayAfterDate = #"(?:\s*,\s*(?:\#(teluguWeekdayStems))(?:ం|ము))"#

  /// A date in digits that is a date wherever it stands: with a four-digit year
  /// ("15/10/2026", "15.10.2026", "15-10-2026") or with the dot that closes the
  /// month ("15.10.").
  private static let teluguStrictNumericDate =
    #"(?:\#(numericDateWithYear)|(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?![\p{N}]|[.,/]\p{N}))"#

  /// A planned day written as a date, as a pattern without groups: a day and a
  /// month name with its optional weekday, label, year, and ending ("సోమవారం, 5
  /// అక్టోబర్", "తేదీ 15 అక్టోబర్", "అక్టోబర్ 15న", "15 అక్టోబర్ 2026 నుండి"), a day
  /// of the month with its ending ("15వ తేదీన", "15న"), a date in digits with a
  /// year or a closing dot, and a date in digits with only a day and a month
  /// ("15/10"), which is as often a score, a fraction, or a time, so it is read
  /// only after a label or before an ending.
  private static var teluguPlannedDate: String {
    let month =
      #"\#(teluguDateLabel)?(?:\#(teluguWeekdayForm)\s*,?\s+)?\#(teluguMonthDatePattern)\#(teluguWeekdayAfterDate)?\#(teluguDateEnding)?"#
    let dayOfMonth =
      #"\#(teluguDateLabel)?(?:(?<![\p{N}.,:/-])\d{1,2}·న|\#(teluguDayOfMonthStem)\#(teluguDateEnding)?)"#
    let strict = #"\#(teluguDateLabel)?\#(teluguStrictNumericDate)\#(teluguDateEnding)?"#
    let looseLabeled = #"\#(teluguDateLabel)\#(numericDateWithoutYear)\#(teluguDateEnding)?"#
    let looseEnded = #"\#(numericDateWithoutYear)\#(teluguDateEnding)"#
    return "\(month)|\(dayOfMonth)|\(strict)|\(looseLabeled)|\(looseEnded)"
  }

  /// A written-out date: "15 అక్టోబర్", "15వ తేదీ అక్టోబర్ 2026", "అక్టోబర్ 15", "15వ
  /// తేదీన", "15న". The words are a phrase as ``teluguPhrase(_:)`` leaves it. A
  /// day number with a month name names a date; with the word for date, or
  /// with "న" alone, it names a day of the month.
  static func teluguDate(_ words: String) -> ExplicitDate? {
    let runs = teluguRuns(words)
    let numbers = runs.compactMap { run in number(run).map { (run: run, value: $0) } }
    guard let day = numbers.first(where: { $0.run.count <= 2 && (1...31).contains($0.value) })?.value else {
      return nil
    }
    let year = numbers.first(where: { $0.run.count == 4 && (1900...2099).contains($0.value) })?.value
    let names = runs.filter { number($0) == nil && teluguWeekdayIndex($0) == nil }
    if let month = names.lazy.compactMap(teluguMonthIndex).first {
      return ExplicitDate(year: year, month: month + 1, day: day)
    }
    if names.contains(where: { name in teluguDateWordKeys.contains(where: { teluguHasPrefix(name, $0) }) })
      || (runs.count == 2 && runs[1] == teluguKey("న"))
    {
      return ExplicitDate(day: day)
    }
    return nil
  }

  // MARK: - The words around a day

  /// The words before a weekday that make it this week's ("ఈ"), the coming
  /// one ("వచ్చే", "రాబోయే"), or next week's ("తదుపరి", "తర్వాతి", "తరువాతి";
  /// weeks start on Monday). A week word between them and the weekday ("వచ్చే
  /// వారం సోమవారం") makes the coming words next week's too.
  private static let teluguThisWords: Set<String> = Set(["ఈ"].map(teluguKey))
  private static let teluguComingWords: Set<String> = Set(["వచ్చే", "రాబోయే"].map(teluguKey))
  private static let teluguNextWords: Set<String> = Set(["తదుపరి", "తర్వాతి", "తరువాతి"].map(teluguKey))

  /// The week words that stand between a modifier and a weekday, as keys.
  private static let teluguWeekWords: Set<String> = Set(["వారం", "వారంలో", "వారానికి", "వారపు"].map(teluguKey))

  /// The words that may stand before a weekday, as a pattern.
  private static let teluguModifier = #"(?:(?:ఈ|వచ్చే|రాబోయే|తదుపరి|తర్వాతి|తరువాతి)\s+)"#

  /// "వారం" or its likes between a modifier and a weekday ("వచ్చే వారం
  /// సోమవారం"), as a pattern.
  private static let teluguWeekWordBeforeWeekday = #"(?:వారం|వారపు)"#

  /// The weekend: "వారాంతం", "వీకెండ్", or Saturday and Sunday together ("శని
  /// ఆదివారాలు", "శనివారం మరియు ఆదివారం", "శనివారం, ఆదివారం").
  static let teluguWeekendWords =
    #"(?:వారాంత(?:ం(?:లో)?|ము(?:లో)?|ానికి)|వీకెండ్(?:·(?:లో|కి|కు))?|శని\s*[-–—,]?\s*ఆదివారాలు|(?:శనివారం|శని)\s*(?:మరియు|&|,|-)\s*ఆదివారం|శనివారం\s+ఆదివారం)"#

  /// The words before a day phrase that make it no coming day: the past ("గత
  /// శుక్రవారం", "పోయిన సోమవారం", "మునుపటి మంగళవారం"), "ఆ" (which points back
  /// at a day already named), the last of a month ("చివరి శుక్రవారం", "ఆఖరి
  /// శుక్రవారం"), and an ordinal ("మొదటి శుక్రవారం" is the month's first Friday).
  private static let teluguNotComingModifiers: Set<String> = Set(
    [
      "గత", "పోయిన", "మునుపటి", "ఆ", "ఆఖరి", "చివరి", "మొదటి", "రెండవ", "రెండో", "మూడవ", "మూడో", "నాలుగవ", "నాలుగో",
    ].map(teluguKey))

  /// The past-tense verb stems that put a line in the past, each with the
  /// endings of the first person ("-ాను", "-ాం", "-ాము") and of the third
  /// ("-ింది", "-ారు", "-ాడు", "-ాయి"): "చేశాను", "వెళ్లాను", "వచ్చింది", "అయ్యారు",
  /// "జరిగింది", "చూశాను", "కలిశాం", "చెప్పాడు", "పంపాను", "కొన్నాను". The last
  /// three stems say that a deadline has passed ("గడువు ముగిసింది", "గడువు
  /// మీరింది", "గడువు దాటింది"), so a day beside them is read as no plan.
  private static let teluguPastStems = [
    "చేశ", "చేస", "వెళ్ళ", "వెళ్ల", "వచ్చ", "అయ్య", "జరిగ", "చూశ", "చూస", "కలిశ", "కలిస", "చెప్ప", "పంప", "ఇచ్చ",
    "చదివ", "రాశ", "కొన్న", "తీసుకున్న", "ముగిస", "మీర", "దాట",
  ]

  /// The endings that make a past stem a verb form.
  private static let teluguPastEndings = ["ాను", "ాం", "ాము", "ింది", "ారు", "ాడు", "ాయి"]

  /// The past-tense forms as keys: the stems with each ending, and "అయింది"
  /// ("it happened"), which no stem builds.
  private static let teluguPastMarkers: Set<String> = {
    var markers: Set<String> = [teluguKey("అయింది"), teluguKey("అయ్యింది")]
    for stem in teluguPastStems {
      for ending in teluguPastEndings { markers.insert(teluguKey(stem + ending)) }
    }
    return markers
  }()

  /// Whether `match` names a day that is no coming one: a word that makes it
  /// past or ordinal comes before it ("గత శుక్రవారం", "మొదటి శుక్రవారం"), or the
  /// line is in the past tense ("రేపు మీటింగ్ జరిగింది").
  static func teluguIsNotComing(_ match: Match) -> Bool {
    if let before = teluguWordBefore(match), teluguNotComingModifiers.contains(before) { return true }
    return teluguWords(in: match.source).contains(where: teluguPastMarkers.contains)
  }

  /// The words that mean "until" or "by" after a day, as a pattern without
  /// groups: వరకు, వరకూ, దాకా (until), లోగా, లోపు, లోపల (within), కల్లా, and
  /// నాటికి (by).
  private static let teluguDeadlineWord = #"(?:వరకు|వరకూ|దాకా|లోగా|లోపు|లోపల|కల్లా|నాటికి)"#

  /// The same without వరకు, వరకూ, and దాకా, which also mean "so far" after
  /// today.
  private static let teluguDeadlineWordAfterToday = #"(?:లోగా|లోపు|లోపల|కల్లా|నాటికి)"#

  /// The words that mean "until" after a day, as a pattern.
  private static let teluguUntilWords = #"(?:వరకు|వరకూ|దాకా)"#

  /// The words that mean "from" after a day or an hour, as a pattern.
  static let teluguFromWords = #"(?:నుండి|నుంచి|నించి)"#

  // MARK: - Planned day

  /// A part of the day after a day word, as a phrase: "రేపు ఉదయం", "శుక్రవారం
  /// సాయంత్రం". The words that go with it are ``teluguDayPartWords``.
  private static var teluguPartPhrase: String {
    #"\s+(?:\#(teluguDayPartWords))\#(teluguEnd)"#
  }

  /// Today, with its endings, as a pattern without groups: "ఈరోజు", "ఈ రోజు",
  /// "ఇవాళ", "ఇవ్వాళ", "నేడు", each maybe emphatic ("ఈరోజే"), with the
  /// dative ("ఈరోజుకి", "ఇవాళ్టికి", "నేటికి"), or with "న" ("ఈరోజున").
  private static let teluguToday =
    #"(?:ఈ\s*రోజ(?:ు(?:కి|కు|న)?|ే)|ఇవ(?:్వ)?ాళ(?:ే|్టికి)?|నేడు|నేడే|నేటికి)"#

  /// Tomorrow, with its endings: "రేపు", "రేపే", "రేపటికి", or "రేపటి" before
  /// "నుండి" ("రేపటి నుండి": from tomorrow).
  private static let teluguTomorrow = #"(?:రేప(?:ు|ే)|రేపటిక(?:ి|ే)|రేపటి(?=\s*\#(teluguFromWords)))"#

  /// The day after tomorrow, with its endings: "ఎల్లుండి", "ఎల్లుండే",
  /// "ఎల్లుండికి".
  private static let teluguDayAfter = #"(?:ఎల్లుండ(?:ి|ే|ికి|ికే))"#

  /// Today, as ``teluguToday`` and the phrases "ఈ రాత్రి" and "ఈ సాయంత్రం", which
  /// name today's part: "ఈ" and the plain name of a part of the day.
  private static let teluguTodayPart =
    #"(?:ఈ\s+(?:ఉదయం|ఉదయము|మధ్యాహ్నం|మధ్యాహ్నము|సాయంత్రం|సాయంత్రము|రాత్రి))"#

  /// The words after a counted amount of days, weeks, or months that make it
  /// a day: "రోజుల్లో", "రోజుల తర్వాత", and the likes, as a pattern without
  /// groups.
  private static let teluguCountedUnits =
    #"(?:రోజుల్లో|రోజులలో|రోజుల\s+(?:తర్వాత|తరువాత)|రోజు\s+(?:తర్వాత|తరువాత)|వారాల్లో|వారాలలో|వారాల\s+(?:తర్వాత|తరువాత)|వారం\s+(?:తర్వాత|తరువాత)|వారంలో|నెలల్లో|నెలలలో|నెలల\s+(?:తర్వాత|తరువాత)|నెల\s+(?:తర్వాత|తరువాత)|నెలలో)"#

  /// Group 1: the day, with the ending that goes with it; groups 2 and 3: the
  /// count and the unit of a number of days, weeks, or months.
  ///
  /// Today ("ఈరోజు", "ఇవాళ"), tomorrow ("రేపు"), the day after ("ఎల్లుండి"),
  /// each maybe with a part of the day ("ఈరోజు రాత్రి", "రేపు ఉదయం") or an
  /// ending ("రేపే", "ఈరోజుకి", "రేపటి నుండి"); today's part of the day ("ఈ
  /// సాయంత్రం"); a number of days, weeks, or months ("3 రోజుల్లో", "రెండు
  /// వారాల తర్వాత", "1 నెల తర్వాత"); a weekday, alone or after "ఈ", "వచ్చే",
  /// "రాబోయే", "తదుపరి", "తర్వాతి", or "తరువాతి", maybe with "వారం" between
  /// ("సోమవారానికి", "ఈ శుక్రవారం", "వచ్చే వారం సోమవారం"), maybe with "నాడు",
  /// "రోజున", or "రోజు" and a part of the day after it; next week ("వచ్చే
  /// వారం"); the weekend; and a date (``teluguPlannedDate``). A day word or
  /// weekday may be followed by "నుండి" ("సోమవారం నుండి జిమ్" plans Monday), unless
  /// that "నుండి" starts a counted day. A weekday with any ending this pattern
  /// does not list ("సోమవారపు మీటింగ్") is no planned day, and neither is a day
  /// that "నాటి" follows ("శుక్రవారం నాటి మీటింగ్" is Friday's meeting: the word
  /// makes the day an attribute of the noun, as a genitive does) or that
  /// "వరకు" follows ("ఈరోజు వరకు" means "so far", and "శుక్రవారం వరకు" is a
  /// deadline that ``teluguDuePattern`` reads first).
  static var teluguWhenPattern: String {
    let counted = #"(?:(\d{1,3}|\#(teluguRoundCountWords))\s*(\#(teluguCountedUnits)))"#
    let from = #"(?:\s+\#(teluguFromWords))?"#
    let notFromCount =
      #"(?!\s+\#(teluguFromWords)\s+(?:\d{1,3}|\#(teluguRoundCountWords))\s*\#(teluguCountedUnits))"#
    let relative =
      #"(?:\#(teluguToday)|\#(teluguTomorrow)|\#(teluguDayAfter))\#(notFromCount)(?:\#(teluguPartPhrase))?\#(from)"#
    let todayPart = #"\#(teluguTodayPart)\#(notFromCount)\#(from)"#
    let weekday =
      #"(?:\#(teluguModifier)(?:\#(teluguWeekWordBeforeWeekday)\s+)?)?\#(teluguWeekdayForm)\#(notFromCount)(?:\s+(?:నాడు|రోజున|రోజు))?(?:\#(teluguPartPhrase))?\#(from)"#
    let nextWeek =
      #"(?:వచ్చే|రాబోయే|తదుపరి|తర్వాతి|తరువాతి)\s+(?:వారం(?:లో)?|వారానికి)\#(from)"#
    let weekend = #"(?:(?:ఈ|వచ్చే|రాబోయే|తదుపరి)\s+)?\#(teluguWeekendWords)"#
    let alternatives = [relative, todayPart, counted, teluguPlannedDate, weekend, weekday, nextWeek]
    let notFollowed = #"(?!\s+(?:\#(teluguUntilWords)|నాటి)\#(teluguEnd))"#
    return #"\#(teluguStart)(\#(alternatives.joined(separator: "|")))\#(teluguEnd)\#(notFollowed)"#
  }

  static func teluguWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !teluguIsNotComing(match) else { return nil }
    if let count = match.group(2), let unit = match.group(3) {
      guard let amount = number(count) ?? teluguRoundCounts[teluguCompactKey(count)] else { return nil }
      return teluguRelativeDay(count: amount, unit: teluguPhrase(unit), in: match)
    }
    return teluguDay(phrase, in: match)
  }

  // MARK: - Due day

  /// The relative days a deadline may name, as a pattern without groups:
  /// tomorrow and the day after, each as the genitive or the plain word
  /// ("రేపటి లోగా", "రేపు లోగా"), and today only before a part of the day or
  /// before a deadline word that does not also mean "so far".
  private static let teluguDueTomorrow = #"(?:రేపటి|రేపు|ఎల్లుండి)"#

  /// The forms of today a deadline word that does not mean "so far" follows,
  /// as a pattern without groups: "ఈరోజు", "ఈ రోజు", "ఇవాళ", "ఇవాళ్టి", "నేటి".
  private static let teluguDueToday = #"(?:ఈ\s*రోజు|ఇవ(?:్వ)?ాళ(?:్టి)?|నేటి|నేడు)"#

  /// A weekday before a deadline word, as a pattern without groups: the plain
  /// name ("శుక్రవారం", "శుక్రవారంలోగా" after the word), or the dative glued to
  /// "కల్లా" ("శుక్రవారానికల్లా").
  private static var teluguDueWeekday: String {
    #"(?:\#(teluguModifier)(?:\#(teluguWeekWordBeforeWeekday)\s+)?)?(?:\#(teluguWeekdayStems))(?:ం|ము)"#
  }

  /// A date a deadline may name, as a pattern without groups: a written date
  /// with its optional weekday and label, a day of the month with the word for
  /// date, and a date in digits.
  private static var teluguDueDate: String {
    #"\#(teluguDateLabel)?(?:\#(teluguWeekdayForm)\s*,?\s+)?(?:\#(teluguMonthDatePattern)\#(teluguWeekdayAfterDate)?|\#(teluguDayOfMonthStem)|\#(teluguStrictNumericDate)|\#(numericDateWithoutYear))"#
  }

  /// A part of the day that may stand between a day and a deadline word
  /// ("శుక్రవారం రాత్రి వరకు", "రేపు ఉదయంలోగా"), as a pattern without groups.
  private static var teluguDuePart: String {
    #"(?:\s+(?:\#(teluguDayPartWords)))?"#
  }

  /// The days a deadline word may follow, as a pattern with a group for the
  /// deadline word that follows each: group 1 the deadline word after a
  /// weekday, a date, tomorrow, or the day after; group 2 the one that goes
  /// with today. "ఈరోజు వరకు" is not a deadline: it means "so far".
  private static var teluguDueBeforeWord: String {
    let word = teluguDeadlineWord
    let todayWord = teluguDeadlineWordAfterToday
    let weekday = #"(?:\#(teluguDueWeekday)\#(teluguDuePart)\s*\#(word)|(?:\#(teluguWeekdayStems))ానికల్లా)"#
    let date = #"(?:\#(teluguDueDate))\s*\#(word)"#
    let tomorrow = #"\#(teluguDueTomorrow)\#(teluguDuePart)\s*\#(word)"#
    let today =
      #"(?:\#(teluguDueToday)\s*\#(todayWord)|(?:ఈ\s+(?:రాత్రి|సాయంత్రం|సాయంత్రము|ఉదయం|ఉదయము|మధ్యాహ్నం|మధ్యాహ్నము))\s*\#(word)|\#(teluguDueToday)\s+(?:\#(teluguDayPartWords))\s*\#(word))"#
    return "\(weekday)|\(date)|\(tomorrow)|\(today)"
  }

  /// The days a deadline label may name, as a pattern without groups: any
  /// day a planned-day phrase names that is also a day alone: today, tomorrow,
  /// the day after, a date, and a weekday. A date comes before a weekday
  /// alone, so "గడువు: గురువారం, 15 అక్టోబర్" is one date and not Thursday with
  /// a date left over.
  private static var teluguLabelDay: String {
    #"(?:\#(teluguToday)|\#(teluguDueTomorrow)|\#(teluguDueToday)|\#(teluguDueDate)|\#(teluguDueWeekday))(?:\s+(?:\#(teluguDayPartWords)))?"#
  }

  /// The words that bound a deadline written as a clock time and the clock
  /// times themselves, as a pattern without groups, from ``teluguClockBound``.
  private static var teluguDueClockAfterDay: String {
    teluguClockBoundAfterDay
  }

  /// A day with a deadline word after it ("శుక్రవారం వరకు", "శుక్రవారంలోగా",
  /// "రేపటి లోపు", "అక్టోబర్ 15 నాటికి", "శుక్రవారానికల్లా", "ఈ రాత్రి
  /// వరకు"), a deadline label before it ("గడువు: శుక్రవారం", "గడువు తేదీ
  /// అక్టోబర్ 15", "చివరి తేదీ శుక్రవారం", "డెడ్‌లైన్ రేపు"), the label after it
  /// as the app writes it ("శుక్రవారం గడువు", "రేపు గడువు"), or a deadline
  /// clock after it ("శుక్రవారం సాయంత్రం 5 గంటలలోగా", whose clock stays in the
  /// title). Groups: 1 the day after a label, 2 the day before a deadline
  /// word, 3 the day before the label, 4 the day before a deadline clock.
  static var teluguDuePattern: String {
    let label =
      #"(?:(?:గడువు\s+తేదీ|గడువు\s+తేది|గడువు|చివరి\s+తేదీ|చివరి\s+తేది|ఆఖరి\s+తేదీ|ఆఖరి\s+తేది|డెడ్\s*లైన్)(?:\s*[:：]\s*|\s+)(\#(teluguLabelDay)))"#
    let before = #"(\#(teluguDueBeforeWord))"#
    let after =
      #"((?:\#(teluguToday)|\#(teluguDueTomorrow)|\#(teluguDueToday)|\#(teluguDueWeekday)|\#(teluguDueDate))(?:\s+(?:\#(teluguDayPartWords)))?)\s+గడువు(?:\s+తేదీ|\s+తేది)?"#
    let clock =
      #"((?:\#(teluguToday)|\#(teluguDueTomorrow)|\#(teluguDueToday)|\#(teluguDueWeekday)|\#(teluguDueDate)))(?=\#(teluguDueClockAfterDay))"#
    return
      #"\#(teluguStart)(?:\#(label)\#(teluguEnd)|\#(before)\#(teluguEnd)|\#(after)\#(teluguEnd)|\#(clock))"#
  }

  static func teluguDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4),
      !teluguIsNotComing(match)
    else { return nil }
    return teluguDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "ఈ" makes it this week's, today when it
  /// names today; "వచ్చే" and "రాబోయే" make it the coming one, a full week
  /// ahead when it names today; "తదుపరి", "తర్వాతి", and "తరువాతి" make it next
  /// week's, weeks starting on Monday, and a week word between "వచ్చే" and the
  /// weekday makes it next week's too ("వచ్చే వారం సోమవారం").
  private static func teluguDay(_ phrase: String, in match: Match) -> Day? {
    if let date = numericDate(phrase) ?? teluguDate(teluguPhrase(phrase)) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let isEvening = teluguFinds(#"(?:రాత్రి|అర్ధరాత్రి|అర్థరాత్రి|అర్ధ\s*రాత్రి|మిడ్\s*నైట్)"#, in: phrase)
    if teluguFinds("^(?:\(teluguToday)|\(teluguDueToday)|\(teluguTodayPart))", in: phrase) {
      return Day(offset: 0, isEvening: isEvening)
    }
    if teluguFinds("^(?:\(teluguTomorrow)|రేపటి)", in: phrase) { return Day(offset: 1, isEvening: isEvening) }
    if teluguFinds("^\(teluguDayAfter)", in: phrase) { return Day(offset: 2, isEvening: isEvening) }
    let tokens = teluguWords(in: phrase)
    let hasWeekWord = tokens.contains(where: teluguWeekWords.contains)
    let isNext =
      tokens.contains(where: teluguNextWords.contains)
      || (hasWeekWord && tokens.contains(where: teluguComingWords.contains))
    if teluguFinds(teluguWeekendWords, in: phrase) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: tokens.contains(where: teluguNextWords.contains) ? weekend + 7 : weekend)
    }
    guard let weekday = tokens.lazy.compactMap(teluguWeekdayIndex).first else {
      return hasWeekWord ? Day(offset: 7) : nil
    }
    let todayWeekday = match.todayWeekday
    if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
    if tokens.contains(where: teluguThisWords.contains) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// The words that tie a counted amount of days to another event, which
  /// makes it no day of its own: "మీటింగ్ నుండి 3 రోజుల తర్వాత" and "మీటింగ్
  /// అయిన 3 రోజుల తర్వాత" count from the meeting.
  private static let teluguEventTies: Set<String> = Set(
    ["నుండి", "నుంచి", "నించి", "తర్వాత", "తరువాత", "అయిన", "చేసిన", "అయ్యాక", "చేశాక", "చేసాక"].map(teluguKey))

  /// The day of "3 రోజుల్లో", "రెండు వారాల తర్వాత", "1 నెల తర్వాత", from the
  /// count and the unit. A count of days or weeks needs no date; a count of
  /// months is counted on the calendar from today. Nil after a word that ties
  /// the amount to another event.
  private static func teluguRelativeDay(count: Int, unit: String, in match: Match) -> Day? {
    guard count >= 1 else { return nil }
    if let before = teluguWordBefore(match), teluguEventTies.contains(before) { return nil }
    let key = teluguKey(unit)
    if teluguHasPrefix(key, teluguKey("రోజు")) { return Day(offset: count) }
    if teluguHasPrefix(key, teluguKey("వార")) { return Day(offset: count * 7) }
    guard teluguHasPrefix(key, teluguKey("నెల")), let today = match.today else { return nil }
    let calendar = utcCalendar
    guard let target = calendar.date(byAdding: .month, value: count, to: today),
      let days = calendar.dateComponents([.day], from: today, to: target).day
    else { return nil }
    return Day(offset: days)
  }

  // MARK: - Date range

  /// "అక్టోబర్ 3 నుండి 5 వరకు", "3 నుండి 5 అక్టోబర్ వరకు", "3 అక్టోబర్ నుండి 5
  /// అక్టోబర్ వరకు", "అక్టోబర్ 3-5", "3-5 అక్టోబర్", each with "నుంచి" for
  /// "నుండి", maybe with a year after a month, and with "వరకు", "వరకూ", or
  /// "దాకా" after the end. The start and the end are each a date or a day
  /// alone ("3", "3వ తేదీ"). The end may carry "న", "కి", or "కు" glued to it;
  /// any other letter or sign glued to the end ("3 నుండి 5 మార్చిలో") makes it
  /// another word and leaves the line unread. Groups: 1 the start, 2 a dash
  /// between the sides, 3 "నుండి" between them, 4 the end, 5 the word for
  /// "until".
  static var teluguDateRangePattern: String {
    let bare = #"\d{1,2}(?:వ(?:\s*\#(teluguDateWord))?)?\#(teluguNoMoreDigits)"#
    let side = "\(teluguMonthDatePattern)|\(bare)"
    let connector = #"(?:\s*([-–—])\s*|\s+(\#(teluguFromWords))\s+)"#
    let ending = #"(?:·(?:న|కి|కు))?"#
    return
      #"\#(teluguStart)\#(teluguDateLabel)?(\#(side))\#(connector)(\#(side))\#(ending)(?:\s+(\#(teluguUntilWords)))?\#(teluguDateEnd)"#
  }

  /// A range names days only when a month stands in it: the start with a month
  /// and an end without one ("అక్టోబర్ 3 నుండి 5 వరకు") needs "వరకు" or a dash,
  /// since "అక్టోబర్ 3 నుండి 5 మంది" is no range; a start without a month needs
  /// the end's. A range in the past tense names a trip or an event that the
  /// task may only prepare for: it is claimed whole and read as no days, so "8
  /// మే వరకు" is not read alone as a due day. A day alone opens a range joined by
  /// a dash only when the dash touches both sides ("3-5 మే"): "Sprint 12 - 20
  /// మే" names a sprint and a date.
  static func teluguDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(4),
      let start = teluguRangeDate(startText), let end = teluguRangeDate(endText)
    else { return nil }
    if start.month == nil {
      guard end.month != nil else { return nil }
      if match.group(2) != nil, !dashTouchesBothSides(match, start: 1, end: 4) { return nil }
    } else if end.month == nil, match.group(5) == nil, match.group(2) == nil {
      return nil
    }
    if teluguIsNotComing(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 మే") or a day alone ("5", "5వ తేదీ"),
  /// which has no month.
  private static func teluguRangeDate(_ text: String) -> ExplicitDate? {
    let words = teluguPhrase(text)
    if let date = teluguDate(words) { return date }
    let runs = teluguRuns(words)
    guard let first = runs.first, let day = number(first), (1...31).contains(day),
      runs.dropFirst().allSatisfy({ run in ([teluguKey("వ")] + teluguDateWordKeys).contains(run) })
    else { return nil }
    return ExplicitDate(day: day)
  }

  /// "సోమవారం నుండి బుధవారం వరకు", "శుక్రవారం నుండి సోమవారం", "సోమవారం నుంచి
  /// బుధవారం": a span of weekdays, maybe with "వరకు" after it and a genitive glued
  /// to its end ("సోమవారం నుండి బుధవారపు సెలవు"). Groups: 1 the first weekday, 2
  /// the last, 3 the genitive.
  static var teluguWeekdayRangePattern: String {
    let stems = teluguWeekdayStems
    return
      #"\#(teluguStart)((?:\#(stems))(?:ం|ము))\s+\#(teluguFromWords)\s+((?:\#(stems))(?:ం|ము|(పు)))(?:\s+\#(teluguUntilWords))?+\#(teluguEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "సోమవారం నుండి బుధవారం" runs from next Monday to
  /// the Wednesday after it. A span in the past tense, or one that a genitive
  /// is glued to ("సోమవారం నుండి బుధవారపు సెలవు" is the holiday of those days), is
  /// claimed whole and read as no days. A span that "ప్రతి" or the words for
  /// every day accompany is a habit, which the repeat rules read
  /// (``teluguIsHabitSpan(_:)``), and Monday to Friday with no such word is
  /// claimed whole too: it is the working week as often as it is a span of
  /// days. A span from a day to itself is no span.
  static func teluguWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1), let lastWord = match.group(2),
      let first = teluguWeekdayIndex(firstWord), let last = teluguWeekdayIndex(lastWord), first != last
    else { return nil }
    if match.group(3) != nil || teluguIsNotComing(match) { return .declined }
    if teluguIsHabitSpan(match) { return nil }
    if first == 1 && last == 5 { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
