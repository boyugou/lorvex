import Foundation

extension LorvexCaptureVocabulary {
  // The Marathi day rules: the planned day, the due day, written dates, and
  // date ranges. The vocabulary's other words are in ``marathi``.

  // MARK: - Names

  /// Each weekday's names, Sunday first. The short stems (सोम, मंगळ, बुध, गुरु,
  /// शुक्र, शनि, रवि) are ordinary words or names and are not here.
  private static let marathiWeekdayNameList: [[String]] = [
    ["रविवार"], ["सोमवार"], ["मंगळवार"], ["बुधवार"], ["गुरुवार", "गुरूवार"], ["शुक्रवार"], ["शनिवार"],
  ]

  /// The weekday names as keys, longest first, each with its weekday (0 =
  /// Sunday).
  private static let marathiWeekdayKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (weekday, names) in marathiWeekdayNameList.enumerated() {
      for name in names { keys.append((marathiKey(name), weekday)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The weekday names as a pattern, longest first.
  static let marathiWeekdayNames = alternation(of: marathiWeekdayNameList.flatMap { $0 })

  /// The weekday a word names, 0 = Sunday, with or without an ending glued to
  /// it ("सोमवारी", "सोमवारपर्यंत").
  static func marathiWeekdayIndex(_ word: String) -> Int? {
    let key = marathiKey(word)
    return marathiWeekdayKeys.first(where: { marathiHasPrefix(key, $0.key) })?.index
  }

  /// Each month's Gregorian names, January first: the full name in the
  /// spellings people type, and the short form the system writes next to a day
  /// ("15 ऑक्टो"), which the full name of a month with no short form
  /// ("मार्च", "मे", "जून", "जुलै") stands for.
  private static let marathiMonthRows: [(full: [String], short: [String])] = [
    (["जानेवारी"], ["जाने"]), (["फेब्रुवारी", "फेब्रुअरी"], ["फेब्रु"]), (["मार्च"], []),
    (["एप्रिल", "एप्रील"], ["एप्रि"]), (["मे"], []), (["जून"], []), (["जुलै"], []), (["ऑगस्ट"], ["ऑग"]),
    (["सप्टेंबर"], ["सप्टें"]), (["ऑक्टोबर", "ऑक्टोंबर"], ["ऑक्टो"]), (["नोव्हेंबर"], ["नोव्हें"]),
    (["डिसेंबर"], ["डिसें"]),
  ]

  /// The month names as keys, longest first, each with its month (0 =
  /// January).
  private static let marathiMonthKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (month, row) in marathiMonthRows.enumerated() {
      for name in row.full + row.short { keys.append((marathiKey(name), month)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The month a word names, 0 = January, with or without an ending glued to
  /// it ("ऑक्टोबरला").
  private static func marathiMonthIndex(_ word: String) -> Int? {
    let key = marathiKey(word)
    return marathiMonthKeys.first(where: { marathiHasPrefix(key, $0.key) })?.index
  }

  // MARK: - Dates

  /// "15 ऑक्टोबर", "15 ऑक्टोबर 2026", "15 ऑक्टोबर, 2026", "15 ऑक्टो.": a day
  /// number before a Gregorian month name, full or short, maybe with a year. A
  /// month needs its day number, so "ऑक्टोबर" alone is no date.
  static var marathiMonthDatePattern: String {
    let full = alternation(of: marathiMonthRows.flatMap { $0.full })
    let short = alternation(of: marathiMonthRows.flatMap { $0.short })
    return #"\d{1,2}\s*(?:(?:\#(full))|(?:\#(short))\.?)(?:,?\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// "15 तारखे": a day of the month with no month, as the stem of the word
  /// for "on the 15th" ("15 तारखेला") or "until the 15th" ("15 तारखेपर्यंत").
  static let marathiDayOfMonthStem = #"\d{1,2}\s*तारखे"#

  /// The label that may stand before a date.
  private static let marathiDateLabel = #"(?:(?:दिनांक|तारीख)\s*[:：]?\s*)"#

  /// The endings that go with a date or a day as a planned day: "ला" ("15
  /// ऑक्टोबरला"), "पासून" (from), "साठी" (for), and "रोजी" (on) as a word of
  /// its own.
  private static let marathiPlannedDateEnding = #"(?:·(?:ला|पासून|साठी)|\s+रोजी)"#

  /// The endings that go with a date written in digits only: the same words,
  /// after a space or none ("15/10 ला", "15/10ला").
  private static let marathiNumericDateEnding = #"(?:\s*(?:ला|पासून|साठी)|\s+रोजी)"#

  /// A date in digits that is a date wherever it stands: with a four-digit
  /// year ("15/10/2026", "15.10.2026", "15-10-2026") or with the dot that
  /// closes the month ("15.10.").
  private static let marathiStrictNumericDate =
    #"(?:\#(numericDateWithYear)|(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?![\p{N}]|[.,/]\p{N}))"#

  /// A planned day written as a date, as a pattern without groups: a day and a
  /// month name with its optional weekday, label, year, and ending ("सोमवार, 5
  /// ऑक्टोबर", "तारीख 15 ऑक्टोबर", "15 ऑक्टोबरला", "15 ऑक्टोबर 2026 रोजी"), a day of
  /// the month with its ending ("15 तारखेला"), a date in digits with a year
  /// or a closing dot, and a date in digits with only a day and a month ("15/10
  /// ला", "तारीख 15/10"), which is as often a score, a fraction, or a time, so
  /// it is read only after a label or before an ending.
  private static var marathiPlannedDate: String {
    let month =
      #"\#(marathiDateLabel)?(?:(?:\#(marathiWeekdayNames))(?:·ी)?\s*,?\s+)?\#(marathiMonthDatePattern)\#(marathiPlannedDateEnding)?"#
    let dayOfMonth =
      #"\#(marathiDateLabel)?\#(marathiDayOfMonthStem)·(?:ला|स|पासून|साठी)"#
    let strict = #"\#(marathiDateLabel)?\#(marathiStrictNumericDate)\#(marathiNumericDateEnding)?"#
    let looseLabeled = #"\#(marathiDateLabel)\#(numericDateWithoutYear)\#(marathiNumericDateEnding)?"#
    let looseEnded = #"\#(numericDateWithoutYear)\#(marathiNumericDateEnding)"#
    return "\(month)|\(dayOfMonth)|\(strict)|\(looseLabeled)|\(looseEnded)"
  }

  /// A written-out date: "15 ऑक्टोबर", "15 ऑक्टोबर 2026", "15 तारखेला", "15/10".
  /// The words are a phrase as ``marathiPhrase(_:)`` leaves it.
  static func marathiDate(_ words: String) -> ExplicitDate? {
    let tokens = words.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    guard let dayIndex = tokens.firstIndex(where: { number($0) != nil }), let day = number(tokens[dayIndex]),
      dayIndex + 1 < tokens.count
    else { return nil }
    let following = marathiKey(tokens[dayIndex + 1])
    if let month = marathiMonthIndex(following) {
      let year =
        dayIndex + 2 < tokens.count
        ? tokens[dayIndex + 2].wholeMatch(of: /(?:19|20)\d{2}/).flatMap { number($0.output) } : nil
      return ExplicitDate(year: year, month: month + 1, day: day)
    }
    if marathiHasPrefix(following, marathiKey("तारखे")) { return ExplicitDate(day: day) }
    return nil
  }

  // MARK: - The words around a day

  /// The words before a weekday that make it this week's or next week's. A
  /// weekday with "येत्या", "येणाऱ्या", or "आगामी" before it is the coming one,
  /// which is how a weekday alone is read, so those words need no entry here.
  private static let marathiThisWords: Set<String> = Set(["या", "ह्या"].map(marathiKey))
  private static let marathiNextWords: Set<String> = Set(
    ["पुढच्या", "पुढील", "पुढचा", "पुढची", "पुढचे"].map(marathiKey))

  /// The words that may stand before a weekday, as a pattern.
  private static let marathiModifier =
    #"(?:(?:येत्या|येणाऱ्या|आगामी|पुढच्या|पुढील|पुढचा|पुढची|पुढचे|या|ह्या)\s+)"#

  /// "आठवड्यात" or "आठवड्यातील" between a modifier and a weekday ("पुढच्या
  /// आठवड्यात शुक्रवारी"), as a pattern.
  private static let marathiWeekWordBeforeWeekday = #"(?:आठवड्यात|आठवड्यातील)"#

  /// The weekend, written "वीकेंड", as the end of the week ("आठवडाअखेर",
  /// "आठवड्याच्या शेवटी"), or as Saturday and Sunday together ("शनिवार-रविवार").
  static let marathiWeekendWords =
    #"(?:वीक\s*[एे]ं?ड|आठवडा\s*अखेर|आठवडा\s*खेर|आठवड्याच्या\s+(?:अखेरीस|शेवटी)|शनिवार(?:\s*[-–—]\s*|\s+(?:आणि|व)\s+|\s+)रविवार)"#

  /// The words before a day phrase that make it no coming day: the past
  /// ("गेल्या शुक्रवारी", "मागील सोमवारी") and an ordinal ("पहिल्या शुक्रवारी" is
  /// the month's first Friday).
  private static let marathiNotComingModifiers: Set<String> = Set(
    [
      "गेल्या", "गेला", "गेली", "गेले", "मागील", "मागच्या", "मागचा", "मागची", "मागचे", "पहिल्या", "पहिला", "पहिली",
      "पहिले", "दुसऱ्या", "दुसरा", "दुसरी", "दुसरे", "तिसऱ्या", "तिसरा", "चौथ्या", "पाचव्या", "शेवटच्या", "शेवटचा",
      "शेवटची", "शेवटचे",
    ].map(marathiKey))

  /// The past-tense forms that put a line in the past: the auxiliary "होता" and
  /// the perfectives of "जाणे", "येणे", and "होणे". The perfective of "करणे"
  /// ("केले") is not here ("केले जाईल" is a future passive), nor "आले", which is
  /// also the word for ginger.
  private static let marathiPastMarkers: Set<String> = Set(
    [
      "होता", "होती", "होते", "होतो", "होतात", "होत्या", "होतं", "गेला", "गेली", "गेले", "गेलो", "गेल्या", "झाला",
      "झाली", "झाले", "झालो", "झाल्या", "आला", "आली", "आलो", "आल्या",
    ].map(marathiKey))

  /// Whether `match` names a day that is no coming one: a word that makes it
  /// past or ordinal comes before it ("गेल्या शुक्रवारी", "पहिल्या शुक्रवारी"), or
  /// the line is in the past tense ("काल मीटिंग होती").
  static func marathiIsNotComing(_ match: Match) -> Bool {
    if let before = marathiWordBefore(match), marathiNotComingModifiers.contains(before) { return true }
    return marathiWords(in: match.source).contains(where: marathiPastMarkers.contains)
  }

  /// The words that make a day a deadline when they follow it, glued to it or
  /// after a space: "पर्यंत" (until), "पूर्वी" and "आधी" (before), "अगोदर", and
  /// the genitive "च्या" before "आधी", "पूर्वी", or "अगोदर" ("शुक्रवारच्या आधी").
  static let marathiDeadlineWords =
    #"(?:(?:·|\s+)(?:पर्यंत|पूर्वी|आधी|अगोदर)|·च्या\s+(?:आधी|पूर्वी|अगोदर))"#

  /// A part of the day written as the word that goes with a deadline word:
  /// "सकाळपर्यंत", "संध्याकाळपर्यंत", "रात्रीपर्यंत".
  private static let marathiPartStem = #"(?:सकाळ|दुपार|संध्याकाळ|सायंकाळ|रात्री|रात्र|पहाटे|पहाट)"#

  /// The Hindi words that may follow a word Hindi and Marathi share ("आज", a
  /// weekday name, "मार्च"), as a pattern that fails where one of them follows:
  /// a part of the day, with or without "की" or "के" before it ("आज की रात",
  /// "सोमवार शाम"), a postposition ("को", "से", "पर", "में"), the particles
  /// "ही" and "भी", "तक", a possessive ("का", "की", "के"), and "वाला". Hindi
  /// reads such a phrase whole, or leaves it unread on purpose ("सोमवार की
  /// मीटिंग"), so the Marathi vocabulary used beside Hindi does not read the
  /// shared word alone.
  static let marathiHindiAfter =
    #"(?!\s+(?:(?:की|के)\s+)?(?:देर\s+रात|रात|सुबह|सवेरे|सबेरे|तड़के|दोपहर|दुपहर|शाम)\#(devanagariEnd)|\s+(?:को|से|पर|में|ही|भी|तक|तलक|का|की|के|वाल[ाीे]|वालों)\#(devanagariEnd))"#

  /// The Hindi words that may stand before a weekday, as a pattern that fails
  /// where one of them stands there: "इस", "अगले", "आने वाले", and the week
  /// word that goes with them ("इस हफ्ते शुक्रवार"). Hindi reads the weekday
  /// with them, so the Marathi vocabulary used beside Hindi leaves it. The
  /// spaces inside "आने वाले" are bounded because a lookbehind needs a
  /// bounded length.
  static let marathiHindiBefore =
    #"(?<!(?:इस|इसी|अगले|अगला|अगली|आने\s{1,3}वाले|आने\s{1,3}वाला|आने\s{1,3}वाली|हफ्ते|हफ्ता|सप्ताह|के)\s)"#

  // MARK: - Planned day

  /// A part of the day after a day word, as a phrase: "उद्या सकाळी", "शुक्रवारी
  /// संध्याकाळी". The word that goes with it is ``marathiDayPartWords``.
  private static var marathiPartPhrase: String {
    #"\s+(?:\#(marathiDayPartWords))\#(devanagariEnd)"#
  }

  /// Group 1: the day, with the ending that goes with it.
  ///
  /// Today ("आज"), tomorrow ("उद्या"), the day after ("परवा"), each maybe with
  /// a part of the day ("आज रात्री", "उद्या सकाळी") or an ending ("उद्याच",
  /// "उद्यापासून"); a number of days, weeks, or months ("3 दिवसांनी", "दोन
  /// आठवड्यांनी", "1 महिन्याने"); a weekday, alone or after "या", "ह्या",
  /// "येत्या", or "पुढच्या" ("सोमवारी", "या शुक्रवारी", "पुढच्या शुक्रवारी"),
  /// maybe with a part of the day; next week ("पुढच्या आठवड्यात"); the weekend;
  /// and a date (``marathiPlannedDate``). A weekday followed by a genitive
  /// ("सोमवारची मीटिंग") is no planned day, since the genitive is an ending
  /// this pattern does not list, and neither is a day followed by a deadline
  /// word of its own ("आज पर्यंत" means "so far"). When `besideHindi`, a phrase
  /// that Hindi words come around ``marathiHindiAfter`` and
  /// ``marathiHindiBefore`` is left to Hindi.
  static func marathiWhenPattern(besideHindi: Bool) -> String {
    let counted =
      #"(?:\d{1,3}|\#(marathiRoundCountWords)|एका)\s+(?:दिवस|आठवड्य|महिन्य)(?:ां(?:नी|नंतर)|ा(?:ने|नंतर))"#
    let relative = #"(?:आज|उद्या|परवा)(?:\#(marathiPartPhrase)|·(?:च|ला|पासून|साठी))?"#
    let weekday =
      #"(?:\#(marathiModifier)(?:\#(marathiWeekWordBeforeWeekday)\s+)?)?(?:\#(marathiWeekdayNames))(?:·(?:ी(?:च)?|ला|पासून|साठी))?(?:\#(marathiPartPhrase))?"#
    let nextWeek =
      #"(?:पुढच्या|पुढील|पुढचा|येत्या|येणाऱ्या|आगामी)\s+(?:आठवड्यात|आठवड्याला|आठवड्यापासून|आठवड्यासाठी|आठवडा)"#
    let weekend =
      #"(?:(?:या|ह्या|पुढच्या|पुढील|येत्या)\s+)?\#(marathiWeekendWords)(?:·(?:ी|ला|साठी|पासून))?"#
    let alternatives = [relative, counted, marathiPlannedDate, weekend, weekday, nextWeek]
    let deadlineWord = #"(?!\s+(?:पर्यंत|पूर्वी|आधी|अगोदर)\#(devanagariEnd))"#
    let before = besideHindi ? marathiHindiBefore : ""
    let after = besideHindi ? marathiHindiAfter : ""
    return
      #"\#(devanagariStart)\#(before)(\#(alternatives.joined(separator: "|")))\#(devanagariEnd)\#(deadlineWord)\#(after)"#
  }

  static func marathiWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !marathiIsNotComing(match) else { return nil }
    return marathiDay(phrase, in: match)
  }

  // MARK: - Due day

  /// The days a deadline may name, as a pattern without groups: tomorrow, the
  /// day after, a weekday, a date, and today only before a part of the day
  /// ("आज रात्रीपर्यंत"), since "आजपर्यंत" means "so far".
  private static var marathiDueDayBase: String {
    let date =
      #"\#(marathiDateLabel)?(?:(?:\#(marathiWeekdayNames))(?:·ी)?\s*,?\s+)?(?:\#(marathiMonthDatePattern)|\#(marathiDayOfMonthStem)|\#(marathiStrictNumericDate)|\#(numericDateWithoutYear))"#
    let weekday =
      #"(?:\#(marathiModifier)(?:\#(marathiWeekWordBeforeWeekday)\s+)?)?(?:\#(marathiWeekdayNames))"#
    return #"(?:(?:उद्या|परवा)|आज(?=\s+\#(marathiPartStem))|\#(date)|\#(weekday))"#
  }

  /// ``marathiDueDayBase`` with the part-of-day word that may follow it before
  /// a deadline word ("उद्या संध्याकाळपर्यंत", "शुक्रवारी रात्रीपर्यंत").
  private static var marathiDueDay: String {
    #"\#(marathiDueDayBase)(?:(?:·ी)?\s+\#(marathiPartStem))?"#
  }

  /// The days a deadline label or "देय" may name, as a pattern without groups:
  /// ``marathiDueDay`` and today.
  private static var marathiLabelDay: String {
    #"(?:आज(?:\s+\#(marathiPartStem))?|\#(marathiDueDay))"#
  }

  /// The clock times that bound a deadline, as a pattern without groups: an
  /// hour or a colon time with "वाजेपर्यंत" and its forms.
  static var marathiClockBound: String {
    let bound = #"(?:पर्यंत|पूर्वी|नंतर|च्या\s+(?:आधी|पूर्वी|नंतर))"#
    let hour = #"(?:(?:साडे|सव्वा|पावणे)\s*)?(?:\d{1,2}(?:[:.]\d{2})?|\#(marathiTimeWords))"#
    return
      #"(?:\#(hour)\s*(?:वाजे\#(bound)|वाजण्या(?:पूर्वी|आधी|अगोदर)|वाजल्यानंतर)|\d{1,2}:\d{2}\s*\#(bound)|\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)\s*\#(bound))"#
  }

  /// A day with a deadline word after it ("शुक्रवारपर्यंत", "उद्या
  /// संध्याकाळपर्यंत", "15 ऑक्टोबरपूर्वी"), a deadline label before it ("अंतिम
  /// तारीख: शुक्रवार", "शेवटचा दिनांक 15 ऑक्टोबर", "देय: शुक्रवार", "देय दिनांक
  /// शुक्रवार"), "देय" after it ("शुक्रवारी देय", "15 ऑक्टोबर रोजी देय", "आज देय"), or a
  /// deadline clock after it ("शुक्रवारी संध्याकाळी 5 वाजेपर्यंत", whose clock
  /// stays in the title). Groups: 1 the day after a label, 2 the day before a
  /// deadline word, 3 the day before a deadline clock, 4 the day before
  /// "देय". "आजपर्यंत" is not a deadline: it means "so far".
  static var marathiDuePattern: String {
    let label =
      #"(?:(?:अंतिम|शेवटची|शेवटचा|शेवटचे)\s+(?:तारीख|दिनांक|मुदत)|देय\s+(?:तारीख|दिनांक)|देय\s*[:：]|डेडला[इई]न)(?:\s*[:：]\s*|\s+)(?:(?:रोजी|पर्यंत)\s+)?(\#(marathiLabelDay)(?:·ी)?)(?:\s+(?:आहे|असेल)\#(devanagariEnd))?"#
    let before = #"(\#(marathiDueDay))\#(marathiDeadlineWords)"#
    let clock =
      #"(\#(marathiDueDayBase))(?:·ी)?(?=\s+(?:(?:\#(marathiPartLeadWords))\s+)?\#(marathiClockBound))"#
    let postfix =
      #"(\#(marathiLabelDay))(?:·ी)?(?:\s+रोजी)?\s+देय(?:\s+(?:आहे|असेल)\#(devanagariEnd))?\#(devanagariEnd)"#
    return #"\#(devanagariStart)(?:\#(label)|\#(before)\#(devanagariEnd)|\#(clock)|\#(postfix))"#
  }

  static func marathiDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4),
      !marathiIsNotComing(match)
    else { return nil }
    return marathiDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The words and numbers of `phrase`.
  private static func marathiDayTokens(_ phrase: String) -> [String] {
    marathiPhrase(phrase).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "या" and "ह्या" make it this week's,
  /// today when it names today; "पुढच्या" makes it next week's, weeks starting
  /// on Monday; "येत्या", "येणाऱ्या", and "आगामी" make it the coming one, a full
  /// week ahead when it names today.
  private static func marathiDay(_ phrase: String, in match: Match) -> Day? {
    if let date = numericDate(phrase) ?? marathiDate(marathiPhrase(phrase)) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let words = marathiPhrase(phrase)
    let tokens = marathiDayTokens(phrase)
    if let count = tokens.first.flatMap({ number($0) ?? marathiRoundCounts[$0] ?? ($0 == marathiKey("एका") ? 1 : nil) }),
      tokens.count == 2
    {
      return marathiRelativeDay(count: count, unit: tokens[1], in: match)
    }
    let isEvening = tokens.contains(where: { marathiHasPrefix($0, marathiKey("रात्र")) })
    func names(_ word: String) -> Bool { tokens.contains(where: { marathiHasPrefix($0, marathiKey(word)) }) }
    if names("आज") { return Day(offset: 0, isEvening: isEvening) }
    if names("उद्या") { return Day(offset: 1, isEvening: isEvening) }
    if names("परवा") { return Day(offset: 2, isEvening: isEvening) }
    let isNext = tokens.contains(where: marathiNextWords.contains)
    if marathiFinds(marathiWeekendWords, in: words) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    guard let weekday = tokens.lazy.compactMap(marathiWeekdayIndex).first else {
      return names("आठवड") ? Day(offset: 7) : nil
    }
    let todayWeekday = match.todayWeekday
    if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
    if tokens.contains(where: marathiThisWords.contains) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// The day of "3 दिवसांनी", "दोन आठवड्यांनी", "1 महिन्याने", from the count
  /// and the unit with its ending. A count of days or weeks needs no date; a
  /// count of months is counted on the calendar from today. Nil after a word
  /// that ties the amount to another event ("मीटिंगच्या 3 दिवसांनी", "आजपासून 3
  /// दिवसांनी").
  private static func marathiRelativeDay(count: Int, unit: String, in match: Match) -> Day? {
    guard count >= 1 else { return nil }
    if let before = marathiWordBefore(match),
      ["च्या", "पासून", "नंतर", "पूर्वी"].map(marathiKey).contains(where: { suffix in
        before.unicodeScalars.reversed().starts(with: suffix.unicodeScalars.reversed())
      })
    {
      return nil
    }
    if marathiHasPrefix(unit, marathiKey("दिवस")) { return Day(offset: count) }
    if marathiHasPrefix(unit, marathiKey("आठवड्य")) { return Day(offset: count * 7) }
    guard marathiHasPrefix(unit, marathiKey("महिन्य")), let today = match.today else { return nil }
    let calendar = utcCalendar
    guard let target = calendar.date(byAdding: .month, value: count, to: today),
      let days = calendar.dateComponents([.day], from: today, to: target).day
    else { return nil }
    return Day(offset: days)
  }

  // MARK: - Date range

  /// "३ ते ५ मे", "३ मे ते ५ मे", "30 जानेवारी ते 2 फेब्रुवारी", "3-5 मे", "३
  /// मेपासून ५ मेपर्यंत", each maybe with a year after a month, and with
  /// "पर्यंत" or "दरम्यान" after the end. The start is a date or a day alone
  /// ("3"); the end is a date. Groups: 1 the start, 2 a dash between the sides,
  /// 3 "ते" between them, 4 "पासून" between them, 5 the end.
  static var marathiDateRangePattern: String {
    let bare = #"\d{1,2}\#(marathiNoMoreDigits)"#
    let side = "\(marathiMonthDatePattern)|\(bare)"
    return
      #"\#(devanagariStart)\#(marathiDateLabel)?(\#(side))(?:\s*([-–—])\s*|\s+(ते)\s+|(?:·|\s+)(पासून)\s+)(\#(side))(?:(?:·|\s+)पर्यंत\#(devanagariEnd)|\s+(?:च्या\s+)?दरम्यान\#(devanagariEnd))?+\#(marathiDateEnd)"#
  }

  /// A range in the past tense names a trip or an event that the task may only
  /// prepare for: it is claimed whole and read as no days, so "8 मेपर्यंत" is
  /// not read alone as a due day. A day alone opens a range joined by a dash
  /// only when the dash touches both sides ("3-5 मे"): "Sprint 12 - 20 मे"
  /// names a sprint and a date.
  static func marathiDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(5),
      let start = marathiRangeDate(startText), let end = marathiRangeDate(endText)
    else { return nil }
    if start.month == nil, match.group(2) != nil, !dashTouchesBothSides(match, start: 1, end: 5) { return nil }
    guard end.month != nil else { return nil }
    if marathiIsNotComing(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 मे") or a day alone ("5"), which has no
  /// month.
  private static func marathiRangeDate(_ text: String) -> ExplicitDate? {
    let words = marathiPhrase(text)
    if let date = marathiDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  /// "सोमवार ते बुधवार", "शुक्रवार ते सोमवार", "सोमवारपासून बुधवारपर्यंत": a span of
  /// weekdays, maybe with "पर्यंत" after it and a genitive glued to its end
  /// ("सोमवार ते बुधवारची सुट्टी"). Groups: 1 the first weekday and 2 the last
  /// of a span joined by "ते", 3 and 4 the same of a span joined by "पासून", 5
  /// the genitive.
  static var marathiWeekdayRangePattern: String {
    let names = marathiWeekdayNames
    let tail = #"(?:(?:·|\s+)पर्यंत)?+"#
    return
      #"\#(devanagariStart)(?:(\#(names))(?:·ी)?\s+ते\s+(\#(names))(?:·ी)?\#(tail)|(\#(names))·पासून\s+(\#(names))(?:·ी)?\#(tail))(·(?:च्या|चा|ची|चे))?\#(devanagariEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "सोमवार ते बुधवार" runs from next Monday to
  /// the Wednesday after it. A span in the past tense, or one that a genitive
  /// is glued to ("सोमवार ते बुधवारची सुट्टी" is the holiday of those days), is
  /// claimed whole and read as no days. A span that "दर" or the words for every
  /// day accompany is a habit, which the repeat rules read
  /// (``marathiIsHabitSpan(_:)``), and Monday to Friday with no such word is
  /// claimed whole too: it is the working week as often as it is a span of
  /// days. A span from a day to itself is no span.
  static func marathiWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1) ?? match.group(3), let lastWord = match.group(2) ?? match.group(4),
      let first = marathiWeekdayIndex(firstWord), let last = marathiWeekdayIndex(lastWord), first != last
    else { return nil }
    if match.group(5) != nil || marathiIsNotComing(match) { return .declined }
    if marathiIsHabitSpan(match) { return nil }
    if first == 1 && last == 5 { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
