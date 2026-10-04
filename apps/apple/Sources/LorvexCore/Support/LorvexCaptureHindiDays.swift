import Foundation

extension LorvexCaptureVocabulary {
  // The Hindi day rules: the planned day, the due day, written dates, and date
  // ranges. The vocabulary's other words are in ``hindi``.

  // MARK: - Names

  /// Each weekday's names, Sunday first. The short stems (सोम, मंगल, बुध, गुरु,
  /// शुक्र, शनि, रवि) are ordinary words or names and are not here.
  private static let hindiWeekdayNameList: [[String]] = [
    ["रविवार", "इतवार"], ["सोमवार"], ["मंगलवार"], ["बुधवार"],
    ["गुरुवार", "गुरूवार", "बृहस्पतिवार", "बृहस्पतवार", "वृहस्पतिवार", "वीरवार"],
    ["शुक्रवार"], ["शनिवार"],
  ]

  private static let hindiWeekdayIndexByName: [String: Int] = {
    var index: [String: Int] = [:]
    for (weekday, names) in hindiWeekdayNameList.enumerated() {
      for name in names { index[hindiKey(name)] = weekday }
    }
    return index
  }()

  /// The weekday names as a pattern, longest first.
  static let hindiWeekdayNames = alternation(of: hindiWeekdayNameList.flatMap { $0 })

  /// The weekday a name in the reading form names, 0 = Sunday, in the singular
  /// or in the oblique plural ("सोमवारों").
  static func hindiWeekdayIndex(_ word: String) -> Int? {
    let key = hindiKey(word)
    if let weekday = hindiWeekdayIndexByName[key] { return weekday }
    let scalars = Array(key.unicodeScalars)
    guard scalars.count > 2, scalars.suffix(2) == ["\u{094B}", "\u{0902}"] else { return nil }
    var stem = String.UnicodeScalarView()
    stem.append(contentsOf: scalars.dropLast(2))
    return hindiWeekdayIndexByName[String(stem)]
  }

  /// Each month's Gregorian names in the spellings people type, January first.
  /// The Vikram Samvat months (चैत्र, वैशाख, ...) are not here: they are not
  /// Gregorian dates.
  private static let hindiMonthNameList: [[String]] = [
    ["जनवरी"], ["फ़रवरी", "फरवरी"], ["मार्च"], ["अप्रैल", "अप्रेल"], ["मई"], ["जून"], ["जुलाई"], ["अगस्त"],
    ["सितंबर", "सितम्बर"], ["अक्टूबर", "अक्तूबर"], ["नवंबर", "नवम्बर"], ["दिसंबर", "दिसम्बर"],
  ]

  private static let hindiMonthIndexByName: [String: Int] = {
    var index: [String: Int] = [:]
    for (month, names) in hindiMonthNameList.enumerated() {
      for name in names { index[hindiKey(name)] = month }
    }
    return index
  }()

  // MARK: - Dates

  /// "5 मई", "5 मई 2027", "5 मई, 2027": a day number before a Gregorian month
  /// name, maybe with a year. A date written in digits only ("5/10") and a
  /// Vikram Samvat month are not read.
  static var hindiMonthDatePattern: String {
    let names = alternation(of: hindiMonthNameList.flatMap { $0 })
    return #"\d{1,2}\s+(?:\#(names))(?:,?\s+(?:19|20)\d{2})?"#
  }

  /// A date, maybe after a label and a weekday: "5 मई", "तारीख 5 मई", "दिनांक:
  /// 5 मई", "सोमवार, 5 अक्टूबर". The date has no group.
  private static var hindiDatePhrase: String {
    #"(?:(?:दिनांक|तारीख)\s*:?\s*)?(?:(?:\#(hindiWeekdayNames))\s*,?\s+)?\#(hindiMonthDatePattern)\#(hindiDateEnd)"#
  }

  /// A written-out date: "5 मई", "5 मई 2027". The words are a phrase as
  /// ``hindiPhrase(_:)`` leaves it.
  static func hindiDate(_ words: String) -> ExplicitDate? {
    let tokens = words.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    guard let dayIndex = tokens.firstIndex(where: { number($0) != nil }), let day = number(tokens[dayIndex]),
      dayIndex + 1 < tokens.count, let month = hindiMonthIndexByName[tokens[dayIndex + 1]]
    else { return nil }
    let year =
      dayIndex + 2 < tokens.count
      ? tokens[dayIndex + 2].wholeMatch(of: /(?:19|20)\d{2}/).flatMap { number($0.output) } : nil
    return ExplicitDate(year: year, month: month + 1, day: day)
  }

  // MARK: - The words around a day

  /// The words before a weekday that make it this week's or next week's. A
  /// weekday with "आने वाले" or "आगामी" before it is the coming one, which is how
  /// a weekday alone is read, so those words need no entry here.
  private static let hindiThisWords: Set<String> = ["इस", "इसी"]
  private static let hindiNextWords: Set<String> = ["अगले", "अगला", "अगली"]

  /// The words that may stand before a weekday, as a pattern.
  private static let hindiModifier =
    #"(?:(?:इस|इसी|अगले|अगला|अगली|आने\s+वाले|आने\s+वाला|आने\s+वाली|आगामी)\s+)"#

  static let hindiWeekWord = #"(?:हफ्ते|हफ्ता|सप्ताह)"#

  /// The weekend, written "वीकेंड" or "सप्ताहांत" or as the end of the week.
  static let hindiWeekendWords =
    #"(?:वीक(?:\s*एं?ड|[ेै](?:ं|न्)ड)|सप्ताहांत|(?:सप्ताह|हफ्ते)\s+के\s+अंत)"#

  /// The words before a day phrase that make it no coming day: the past ("बीता
  /// कल", "पिछले शुक्रवार") and the ordinal first ("पहले शुक्रवार" is the
  /// month's first Friday, and "पहले" also means "earlier").
  private static let hindiNotComingModifiers: Set<String> = Set(
    [
      "बीता", "बीते", "बीती", "गुज़रा", "गुज़रे", "गुज़री", "पिछला", "पिछले", "पिछली", "पहला", "पहले", "पहली",
    ].map(hindiKey))

  /// The past-tense forms that put a line in the past: the auxiliary "था" and
  /// the perfective of "जाना", "आना", and "होना". "किया" is not here ("किया
  /// जाना है" is a future passive), nor "हुए" ("करते हुए").
  private static let hindiPastMarkers: Set<String> = Set(
    [
      "था", "थी", "थे", "थीं", "गया", "गई", "गए", "गये", "गयी", "गईं", "गयीं", "चुका", "चुकी", "चुके", "चुकीं",
      "आया", "आई", "आए", "आये", "आईं", "हुआ", "हुई",
    ].map(hindiKey))

  /// Whether `match` names a day that is no coming one: a word that makes it
  /// past or ordinal comes before it ("बीता कल", "पिछले शुक्रवार", "पहले
  /// शुक्रवार"), or the line is in the past tense ("कल मीटिंग थी").
  static func hindiIsNotComing(_ match: Match) -> Bool {
    if let before = hindiWordBefore(match), hindiNotComingModifiers.contains(before) { return true }
    return hindiWords(in: match.source).contains(where: hindiPastMarkers.contains)
  }

  /// Whether a possessive or "वाला" follows `match` and makes what it names an
  /// attribute of a noun ("सोमवार की मीटिंग", "5 से 8 मई तक की छुट्टी"). "के
  /// लिए" is a purpose ("शुक्रवार के लिए") and is no possessive.
  static func hindiIsPossessed(_ match: Match) -> Bool {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return false }
    return hindiFinds(
      #"^\s+(?:का|की|के(?!\s+लिए)|वाल[ाीे])\#(devanagariEnd)"#, in: String(match.source[end...]))
  }

  /// The words that make a day a deadline when they follow it: "तक", "से
  /// पहले", "के पहले", "से पूर्व".
  static let hindiDeadlineWords = #"(?:तक|तलक|से\s+पहले|के\s+पहले|से\s+पूर्व)"#

  /// The emphatic "ही" and "भी" that may follow a day, its postposition, or a
  /// deadline word ("आज ही", "सोमवार को ही", "शुक्रवार तक ही") and go with it.
  private static let hindiDayParticle = #"(?:\s+(?:ही|भी)\#(devanagariEnd))?"#

  /// What may not follow a day phrase, with or without its particle: a bound or
  /// a comparison ("शुक्रवार तक", "शुक्रवार के बाद", "शुक्रवार से पहले"), or a
  /// possessive that makes it a noun's attribute ("सोमवार की मीटिंग", "कल रात
  /// का खाना", "आज ही की रिपोर्ट").
  private static let hindiNotFollowing =
    #"(?!(?:\s+(?:ही|भी)\#(devanagariEnd))?\s+(?:तक|तलक|का|की|के(?!\s+लिए)|वाल[ाीे]|से\s+(?:पहले|पूर्व|लेकर|बाद))\#(devanagariEnd))"#

  /// The postposition that goes with a day: "सोमवार को", "कल से" (starting
  /// tomorrow), "5 मई को", "अगले हफ्ते में", "वीकेंड पर", "शुक्रवार के लिए".
  private static let hindiDayPostposition = #"(?:\s+(?:को|से|पर|में|के\s+लिए)\#(devanagariEnd))?"#

  // MARK: - Planned day

  /// A part of the day after a day, as an optional piece of a phrase: "कल
  /// सुबह", "आज की रात", "शुक्रवार शाम", and the afternoon as "दोपहर बाद" or
  /// "दोपहर के बाद" ("कल दोपहर बाद"). A part that "बाद" follows in any other
  /// way ("कल शाम के बाद") is no part of the phrase.
  private static var hindiDayPart: String {
    let after = #"\s+(?:के\s+)?बाद\#(devanagariEnd)"#
    return
      #"(?:\s+(?:(?:की|के)\s+)?\#(hindiPartOfDayWords)(?:(?<=दोपहर|दुपहर)\#(after)|(?!\#(after))))?"#
  }

  /// Group 1: the day, without the postposition that goes with it.
  ///
  /// Today ("आज"), tomorrow ("कल"), the day after ("परसों"), each maybe with a
  /// part of the day ("आज रात", "कल सुबह"); a number of days, weeks, or months
  /// ("3 दिन बाद", "एक हफ्ते बाद", "1 महीने बाद"); next week ("अगले हफ्ते"); a
  /// weekday, alone or after "इस", "अगले", or "आने वाले" ("सोमवार", "इस
  /// शुक्रवार", "अगले शुक्रवार"), maybe with a part of the day; the weekend; and
  /// a date ("5 मई", "सोमवार, 5 अक्टूबर"). A phrase that a bound or a possessive
  /// follows is no planned day ("सोमवार की मीटिंग").
  static var hindiWhenPattern: String {
    let counted =
      #"(?:\d{1,3}|\#(hindiRoundCountWords))\s+(?:दिन|दिनों|हफ्ते|हफ्ता|हफ्तों|सप्ताह|सप्ताहों|महीने|महीना|महीनों|माह)\s+बाद"#
    let alternatives = [
      #"(?:आज|कल|परसों|परसो)\#(hindiDayPart)\#(devanagariEnd)"#,
      "\(counted)\(devanagariEnd)",
      hindiDatePhrase,
      #"(?:\#(hindiModifier)(?:\#(hindiWeekWord)\s+(?:के\s+)?)?)?(?:\#(hindiWeekdayNames))\#(hindiDayPart)\#(devanagariEnd)"#,
      #"(?:अगले|आने\s+वाले|आगामी)\s+\#(hindiWeekWord)\#(devanagariEnd)"#,
      #"(?:(?:इस|इसी|अगले|आने\s+वाले|आगामी)\s+)?\#(hindiWeekendWords)\#(devanagariEnd)"#,
    ]
    return
      #"\#(devanagariStart)(\#(alternatives.joined(separator: "|")))\#(hindiDayParticle)\#(hindiNotFollowing)\#(hindiDayPostposition)\#(hindiDayParticle)"#
  }

  static func hindiWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !hindiIsNotComing(match) else { return nil }
    return hindiDay(phrase, in: match)
  }

  // MARK: - Due day

  /// The days a deadline may name, as a pattern without groups: today,
  /// tomorrow, the day after, a weekday, a date.
  private static var hindiDueDay: String {
    #"(?:(?:आज|कल|परसों|परसो)\#(devanagariEnd)|\#(hindiDatePhrase)|(?:\#(hindiModifier)(?:\#(hindiWeekWord)\s+(?:के\s+)?)?)?(?:\#(hindiWeekdayNames))\#(devanagariEnd))"#
  }

  /// A day with a deadline word after it ("शुक्रवार तक", "कल शाम से पहले"), a
  /// deadline label before it ("अंतिम तिथि: 5 मई", "डेडलाइन शुक्रवार"), or a
  /// deadline clock after it ("शुक्रवार शाम 5 बजे तक", whose clock stays in the
  /// title). Groups: 1 the day after a label, 2 the day before a deadline word,
  /// 3 the day before a deadline clock. "आज तक" and "आज से पहले" are not
  /// deadlines: they mean "so far" and "never before". A deadline that a
  /// possessive follows ("शुक्रवार तक की रिपोर्ट") is an attribute of the noun.
  static var hindiDuePattern: String {
    let label =
      #"(?:(?:अंतिम|आखिरी|आख़िरी|आखरी)\s+(?:तिथि|तारीख|दिनांक)|नियत\s+(?:तिथि|तारीख)|डेडलाइन|समय[\s-]?सीमा)(?:\s*[:：]\s*|\s+)(?:(?:को|तक)\s+)?(\#(hindiDueDay))(?:\s+है\#(devanagariEnd))?"#
    let word = hindiDeadlineWords
    let before =
      #"(?!आज\s+\#(word)\#(devanagariEnd))(\#(hindiDueDay))(?:\s+(?:को\s+)?(?:(?:की|के)\s+)?\#(hindiPartOfDayWords))?\s+\#(word)\#(devanagariEnd)(?!(?:\s+(?:ही|भी)\#(devanagariEnd))?\s+(?:का|की|के|वाल[ाीे])\#(devanagariEnd))\#(hindiDayParticle)"#
    let clock =
      #"(\#(hindiDueDay))(?:\s+को\#(devanagariEnd))?(?=\s+(?:\#(hindiPartOfDayWords)\s+(?:(?:के|को)\s+)?)?(?:\#(hindiClockPhrase))\s+\#(word)\#(devanagariEnd))"#
    return #"\#(devanagariStart)(?:\#(label)|\#(before)|\#(clock))"#
  }

  static func hindiDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3), !hindiIsNotComing(match) else { return nil }
    return hindiDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The words and numbers of `phrase`, without nukta signs.
  private static func hindiDayTokens(_ phrase: String) -> [String] {
    hindiPhrase(phrase).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "इस" makes it this week's, today when it
  /// names today; "अगले" makes it next week's, weeks starting on Monday; "आने
  /// वाले" makes it the coming one, a full week ahead when it names today.
  private static func hindiDay(_ phrase: String, in match: Match) -> Day? {
    let words = hindiPhrase(phrase)
    if let date = hindiDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = hindiDayTokens(phrase)
    if tokens.last == "बाद", let first = tokens.first, (number(first) ?? hindiRoundCounts[first]) != nil {
      return hindiRelativeDay(Array(tokens.dropLast()), in: match)
    }
    let isEvening = tokens.contains("रात")
    if tokens.contains("आज") { return Day(offset: 0, isEvening: isEvening) }
    if tokens.contains("कल") { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains(where: { $0 == "परसों" || $0 == "परसो" }) { return Day(offset: 2, isEvening: isEvening) }
    let isNext = tokens.contains(where: hindiNextWords.contains)
    if hindiFinds(hindiWeekendWords, in: words) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    guard let weekday = tokens.lazy.compactMap(hindiWeekdayIndex).first else {
      let isWeek = tokens.contains(where: { $0 == "हफ्ते" || $0 == "हफ्ता" || $0 == "सप्ताह" })
      return isWeek ? Day(offset: 7) : nil
    }
    let todayWeekday = match.todayWeekday
    if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
    if tokens.contains(where: hindiThisWords.contains) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// The day of "3 दिन बाद", "एक हफ्ते बाद", "1 महीने बाद", from the words
  /// before "बाद": a count and a unit. A count of days or weeks needs no date;
  /// a count of months is counted on the calendar from today. Nil after a word
  /// that ties the amount to another event ("मीटिंग के 3 दिन बाद", "आज से 3 दिन
  /// बाद").
  private static func hindiRelativeDay(_ tokens: [String], in match: Match) -> Day? {
    guard tokens.count == 2, let count = number(tokens[0]) ?? hindiRoundCounts[tokens[0]], count >= 1 else {
      return nil
    }
    if let before = hindiWordBefore(match), ["के", "की", "का", "से"].contains(before) { return nil }
    switch tokens[1] {
    case "दिन", "दिनों": return Day(offset: count)
    case "हफ्ते", "हफ्ता", "हफ्तों", "सप्ताह", "सप्ताहों": return Day(offset: count * 7)
    default:
      guard let today = match.today else { return nil }
      let calendar = utcCalendar
      guard let target = calendar.date(byAdding: .month, value: count, to: today),
        let days = calendar.dateComponents([.day], from: today, to: target).day
      else { return nil }
      return Day(offset: days)
    }
  }

  // MARK: - Date range

  /// "3 से 5 मार्च", "3 मार्च से 5 मार्च तक", "30 जनवरी से 2 फ़रवरी तक", "3-5
  /// मार्च", "3–5 मार्च", each maybe with a year after a month, with "से लेकर"
  /// for "से", and with "तक", "के बीच", or "के दौरान" after the end. The start
  /// is a date or a day alone ("3"); the end is a date. Groups: 1 the start, 2
  /// a dash between the sides, 3 "से" between them, 4 the end.
  static var hindiDateRangePattern: String {
    let bare = #"\d{1,2}\#(hindiNoMoreDigits)"#
    let side = "\(hindiMonthDatePattern)|\(bare)"
    return
      #"\#(devanagariStart)(?:(?:दिनांक|तारीख)\s*:?\s*)?(\#(side))(?:\s*([-–—])\s*|\s+(से)(?:\s+लेकर)?\s+)(\#(side))(?:\s+(?:तक|के\s+(?:बीच|दौरान))\#(devanagariEnd))?+\#(hindiDateEnd)"#
  }

  /// A range in the past tense, or one that a possessive follows ("5 से 8 मई तक
  /// की छुट्टी"), names a trip or an event that the task may only prepare for:
  /// it is claimed whole and read as no days, so "8 मई तक" is not read alone as
  /// a due day. A day alone opens a range joined by a dash only when the dash
  /// touches both sides ("3-5 मार्च"): "Sprint 12 - 20 मार्च" names a sprint and
  /// a date.
  static func hindiDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(4),
      let start = hindiRangeDate(startText), let end = hindiRangeDate(endText)
    else { return nil }
    if start.month == nil, match.group(2) != nil, !dashTouchesBothSides(match, start: 1, end: 4) { return nil }
    guard end.month != nil else { return nil }
    if hindiIsNotComing(match) || hindiIsPossessed(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 मई") or a day alone ("5"), which has no
  /// month.
  private static func hindiRangeDate(_ text: String) -> ExplicitDate? {
    let words = hindiPhrase(text)
    if let date = hindiDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  /// "सोमवार से बुधवार तक", "शुक्रवार से सोमवार": a span of weekdays, maybe with
  /// "से लेकर" for "से" and with "तक", "के बीच", or "के दौरान" after it.
  /// Groups: 1 the first weekday, 2 the last.
  static var hindiWeekdayRangePattern: String {
    #"\#(devanagariStart)(\#(hindiWeekdayNames))\s+से(?:\s+लेकर)?\s+(\#(hindiWeekdayNames))\#(devanagariEnd)(?:\s+(?:तक|के\s+(?:बीच|दौरान))\#(devanagariEnd))?+"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "सोमवार से बुधवार तक" runs from next Monday
  /// to the Wednesday after it. A span in the past tense or one that a
  /// possessive follows ("सोमवार से बुधवार तक की छुट्टी") is claimed whole and
  /// read as no days. A span that "हर" or the words for every day accompany is
  /// a habit, which the repeat rules read (``hindiIsHabitSpan(_:)``), and
  /// Monday to Friday with no such word is claimed whole too: it is the working
  /// week as often as it is a span of days. A span from a day to itself is no
  /// span.
  static func hindiWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1), let lastWord = match.group(2),
      let first = hindiWeekdayIndex(firstWord), let last = hindiWeekdayIndex(lastWord), first != last
    else { return nil }
    if hindiIsNotComing(match) || hindiIsPossessed(match) { return .declined }
    if hindiIsHabitSpan(match) { return nil }
    if first == 1 && last == 5 { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
