import Foundation

extension LorvexCaptureVocabulary {
  // The Urdu day rules: the planned day, the due day, written dates, and date
  // ranges. The vocabulary's other words are in ``urdu``.

  // MARK: - Names

  /// Each weekday's names, Sunday first. ہفتہ and ہفتے also mean "the week",
  /// so they name Saturday only beside a mark of a day (``urdu`` explains
  /// which); سنیچر is Saturday only.
  private static let urduWeekdayNameList: [[String]] = [
    ["اتوار"], ["پیر", "سوموار"], ["منگل"], ["بدھ"], ["جمعرات"], ["جمعہ", "جمعے"], ["ہفتہ", "ہفتے", "سنیچر"],
  ]

  private static let urduWeekdayIndexByKey: [String: Int] = {
    var index: [String: Int] = [:]
    for (weekday, names) in urduWeekdayNameList.enumerated() {
      for name in names { index[urduTableKey(name)] = weekday }
    }
    return index
  }()

  /// The weekday a name in the reading form names, 0 = Sunday.
  static func urduWeekdayIndex(_ word: String) -> Int? {
    urduWeekdayIndexByKey[urduKey(word)]
  }

  /// Whether `word`, in the reading form without signs, is ہفتہ or ہفتے: the
  /// words that name both Saturday and the week.
  static func urduIsWeekWord(_ word: String) -> Bool {
    word == urduTableKey("ہفتہ") || word == urduTableKey("ہفتے")
  }

  /// `words` as a pattern without groups, longest first, with the words after a
  /// name that make it no day: "بدھ مت" (Buddhism), "جمعہ بازار", "جمعہ مبارک",
  /// and "پیر میں" (in the foot), "پیر صاحب" (a saint).
  private static func urduNames(_ words: [String]) -> String {
    let others = alternation(of: words.filter { $0 != "پیر" })
    return
      #"(?:\#(others)|پیر(?!\s+(?:میں|صاحب|بابا|سائیں)\#(urduEnd)))(?!\s+(?:مت|ازم|بازار|مبارک|المبارک)\#(urduEnd))"#
  }

  /// Every weekday name as a pattern, ہفتہ and ہفتے included.
  static let urduWeekdayNames = urduNames(urduWeekdayNameList.flatMap { $0 })

  /// The weekday names that name no week, as a pattern: every name but ہفتہ
  /// and ہفتے.
  static let urduDayOnlyNames = urduNames(urduWeekdayNameList.flatMap { $0 }.filter { $0 != "ہفتہ" && $0 != "ہفتے" })

  /// Each month's Gregorian names in the spellings people type, January first.
  /// The names of the Islamic months (محرم, صفر, ...) and of the Indian
  /// calendar's months are not here: they are not Gregorian dates.
  private static let urduMonthNameList: [[String]] = [
    ["جنوری"], ["فروری"], ["مارچ"], ["اپریل", "ایپریل"], ["مئی"], ["جون"], ["جولائی", "جولای"], ["اگست", "اگسٹ"],
    ["ستمبر"], ["اکتوبر"], ["نومبر"], ["دسمبر"],
  ]

  private static let urduMonthIndexByKey: [String: Int] = {
    var index: [String: Int] = [:]
    for (month, names) in urduMonthNameList.enumerated() {
      for name in names { index[urduTableKey(name)] = month }
    }
    return index
  }()

  // MARK: - Dates

  /// "5 مئی", "5 مئی 2027", "5 مئی، 2027", "5 مئی 2027ء": a day number before a
  /// Gregorian month name, maybe with a year (and the ء that Urdu writes after
  /// it). A date written in digits only ("5/10") and an Islamic month are not
  /// read.
  static var urduMonthDatePattern: String {
    let names = alternation(of: urduMonthNameList.flatMap { $0 })
    return #"\d{1,2}\s+(?:\#(names))(?:\s*[,،]?\s*(?:19|20)\d{2}(?:\s*ء)?)?"#
  }

  /// A date, maybe after a label and a weekday: "5 مئی", "تاریخ 5 مئی", "بتاریخ:
  /// 5 مئی", "پیر، 5 اکتوبر". The date has no group.
  private static var urduDatePhrase: String {
    #"(?:(?:بتاریخ|تاریخ)\s*[:：]?\s*)?(?:(?:\#(urduWeekdayNames))\s*[,،]?\s+)?\#(urduMonthDatePattern)\#(urduDateEnd)"#
  }

  /// A written-out date: "5 مئی", "5 مئی 2027". The words are a phrase as
  /// ``urduPhrase(_:)`` leaves it.
  static func urduDate(_ words: String) -> ExplicitDate? {
    let tokens = words.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    guard let dayIndex = tokens.firstIndex(where: { number($0) != nil }), let day = number(tokens[dayIndex]),
      dayIndex + 1 < tokens.count, let month = urduMonthIndexByKey[tokens[dayIndex + 1]]
    else { return nil }
    // The year may carry the ء that Urdu writes after it ("2028ء"), a letter.
    let year =
      dayIndex + 2 < tokens.count
      ? String(tokens[dayIndex + 2].filter(\.isNumber)).wholeMatch(of: /(?:19|20)\d{2}/).flatMap { number($0.output) }
      : nil
    return ExplicitDate(year: year, month: month + 1, day: day)
  }

  // MARK: - The words around a day

  /// The words before a weekday that make it this week's, next week's, or the
  /// coming one. A weekday alone is the coming one, so آئندہ and "آنے والے"
  /// change nothing; they exist so a phrase that names them is read whole.
  private static let urduThisWords: Set<String> = Set(["اس", "اسی"].map(urduTableKey))
  private static let urduNextWords: Set<String> = Set(["اگلے", "اگلا", "اگلی"].map(urduTableKey))
  private static let urduComingWords: Set<String> = Set(["آئندہ", "آنے"].map(urduTableKey))

  /// The words that, before ہفتہ or ہفتے, make it the week: "اس ہفتے", "اگلے
  /// ہفتے", "پورے ہفتے", "ہر ہفتے".
  private static let urduWeekModifiers: Set<String> = Set(
    [
      "اس", "اسی", "اگلے", "اگلا", "اگلی", "آئندہ", "آنے", "والے", "والا", "والی", "پورے", "پورا", "ہر", "گزشتہ",
      "پچھلے", "پچھلا", "پچھلی",
    ].map(urduTableKey))

  /// The words that may stand before a weekday, as a pattern.
  private static let urduModifier =
    #"(?:(?:اس|اسی|اگلے|اگلا|اگلی|آنے\s+والے|آنے\s+والا|آنے\s+والی|آئندہ)\s+)"#

  /// The week, as a word that follows a modifier: "اس ہفتے جمعہ".
  static let urduWeekWord = #"(?:ہفتے|ہفتہ)"#

  /// The weekend, written "ویک اینڈ", "اختتام ہفتہ", as the end of the week, or
  /// as Saturday and Sunday.
  static let urduWeekendWords =
    #"(?:ویک\s*اینڈ|اختتام\s+ہفت(?:ہ|ے)|ہفت(?:ہ|ے)\s+کے\s+آخر(?:\s+میں)?|ہفت(?:ہ|ے)\s+(?:اور|و)\s+اتوار)"#

  /// The words before a day phrase that make it no coming day: the past
  /// ("گزشتہ کل", "پچھلے جمعہ") and the ordinal first ("پہلے جمعہ" is the
  /// month's first Friday, and "پہلے" also means "earlier").
  private static let urduNotComingModifiers: Set<String> = Set(
    [
      "گزشتہ", "گزرا", "گزرے", "گزری", "پچھلا", "پچھلے", "پچھلی", "پہلا", "پہلے", "پہلی", "بیتا", "بیتے", "بیتی",
    ].map(urduTableKey))

  /// The past-tense forms that put a line in the past: the auxiliary "تھا"
  /// and the perfective of "جانا", "آنا", and "ہونا". "کیا" is not here ("کیا
  /// جانا ہے" is a future passive, and "کیا" is also "what"), nor "آئی" and
  /// "آئے", which also form the subjunctive and the future ("وہ کل آئے گا"),
  /// nor "ہوئے" ("کرتے ہوئے").
  private static let urduPastMarkers: Set<String> = Set(
    [
      "تھا", "تھی", "تھے", "تھیں", "گیا", "گئی", "گئے", "گئیں", "چکا", "چکی", "چکے", "چکیں", "آیا", "ہوا", "ہوئی",
    ].map(urduTableKey))

  /// Whether `match` names a day that is no coming one: a word that makes it
  /// past or ordinal comes before it ("گزشتہ کل", "پچھلے جمعہ", "پہلے جمعہ"), or
  /// the line is in the past tense ("کل میٹنگ تھی").
  static func urduIsNotComing(_ match: Match) -> Bool {
    if let before = urduWordBefore(match), urduNotComingModifiers.contains(before) { return true }
    return urduWords(in: match.source).contains(where: urduPastMarkers.contains)
  }

  /// Whether a possessive or "والا" follows `match` and makes what it names an
  /// attribute of a noun ("پیر کی میٹنگ", "5 سے 8 مئی تک کی چھٹی"). "کے لیے" is
  /// a purpose ("جمعہ کے لیے") and "کے دن" and "کے روز" mark a weekday, so none
  /// of them is a possessive.
  static func urduIsPossessed(_ match: Match) -> Bool {
    urduFinds(#"^\s+(?:کا|کی|کے(?!\s+(?:لیے|دن|روز))|وال(?:ا|ی|ے|وں))\#(urduEnd)"#, in: urduTextAfter(match))
  }

  /// Whether `phrase` names a weekday that a word before `match` makes a noun:
  /// "نماز جمعہ" is the Friday prayer, "خطبہ جمعہ" the Friday sermon.
  private static func urduIsPrayerDay(_ phrase: String, in match: Match) -> Bool {
    urduFinds(#"(?:^|\s)(?:نماز|خطبہ)\s*$"#, in: urduTextBefore(match))
      && urduDayTokens(phrase).contains(where: { urduWeekdayIndex($0) != nil })
  }

  /// The words that make a day a deadline when they follow it: تک, "سے
  /// پہلے", "سے قبل".
  static let urduDeadlineWords = #"(?:تک|سے\s+(?:پہلے|قبل))"#

  /// The emphatic ہی and بھی that may follow a day, its postposition, or a
  /// deadline word ("آج ہی", "پیر کو ہی", "جمعہ تک ہی") and go with it.
  private static let urduDayParticle = #"(?:\s+(?:ہی|بھی)\#(urduEnd))?"#

  /// What may not follow a day phrase, with or without its particle: a bound or
  /// a comparison ("جمعہ تک", "جمعہ سے پہلے"), or a possessive that makes it a
  /// noun's attribute ("پیر کی میٹنگ", "کل رات کا کھانا", "آج ہی کی رپورٹ").
  private static let urduNotFollowing =
    #"(?!(?:\s+(?:ہی|بھی)\#(urduEnd))?\s+(?:تک|کا|کی|کے(?!\s+(?:لیے|دن|روز))|وال(?:ا|ی|ے|وں)|سے\s+(?:پہلے|قبل|لے|لیکر|بعد))\#(urduEnd))"#

  /// The postposition that goes with a day, as group 2 of the planned-day
  /// pattern: "پیر کو", "کل سے" (starting tomorrow), "5 مئی کو", "ویک اینڈ پر",
  /// "جمعہ کے لیے", "جمعہ کے دن", "ہفتے کے روز". "میں" is not one: it is also "I".
  private static let urduDayPostposition =
    #"(\s+(?:کو|سے|پر|کے\s+لیے|کے\s+(?:دن|روز))\#(urduEnd))?"#

  /// The words after کل that make it "total", not "tomorrow": "کل رقم" (the
  /// total amount), "کل تعداد", "کل ملا کر".
  private static let urduTotalWords =
    #"(?!\s+(?:رقم|تعداد|ملا|جمع|اخراجات|لاگت|قیمت|آمدنی|فروخت|منافع|نمبر|وقتی)\#(urduEnd))"#

  // MARK: - Planned day

  /// A part of the day after a day, as an optional piece of a phrase: "کل
  /// صبح", "آج کی رات", "جمعہ شام", and the afternoon as "دوپہر بعد" or "دوپہر
  /// کے بعد" ("کل دوپہر بعد"). A part that "بعد" follows in any other way ("کل
  /// شام کے بعد") is no part of the phrase.
  private static var urduDayPart: String {
    let after = #"\s+(?:کے\s+)?بعد\#(urduEnd)"#
    return
      #"(?:\s+(?:(?:کی|کے)\s+)?(?:(?:دوپہر|سہ\s*پہر)\#(after)|\#(urduPartOfDayWords)(?!\#(after))))?"#
  }

  /// The words of a weekday phrase: the weekday names, alone or after "بروز", or
  /// after a modifier and maybe a week word ("اس جمعہ", "اگلے پیر", "اس ہفتے
  /// جمعہ", "آنے والے جمعہ"), each maybe with a part of the day. A modifier
  /// goes with the names that mean no week only, so "اس ہفتے" and "اگلے ہفتے"
  /// are never read as a Saturday. The phrase has no group.
  private static var urduWeekdayPhrase: String {
    let modified =
      #"\#(urduModifier)(?:\#(urduWeekWord)\s+(?:کے\s+)?)?(?:\#(urduDayOnlyNames))"#
    let bare = #"(?:بروز\s+)?(?:\#(urduWeekdayNames))"#
    return #"(?:\#(modified)|\#(bare))\#(urduDayPart)"#
  }

  /// "اگلے ہفتے", "آئندہ ہفتے", "آنے والے ہفتے": seven days ahead. The phrase
  /// has no group.
  private static let urduNextWeekPhrase =
    #"(?:اگلے|اگلا|آئندہ|آنے\s+والے|آنے\s+والا)\s+\#(urduWeekWord)"#

  /// The weekend, alone or after a modifier. The phrase has no group.
  private static var urduWeekendPhrase: String {
    #"(?:(?:اس|اسی|اگلے|آنے\s+والے|آئندہ)\s+)?\#(urduWeekendWords)"#
  }

  /// Today, tomorrow, and the day after, each maybe with a part of the day, and
  /// "آئندہ کل", which the app writes for tomorrow. کل is no day before a word
  /// that makes it "total". The phrase has no group.
  private static var urduDayWords: String {
    #"(?:(?:(?:آئندہ|آنے\s+والا)\s+)?کل\#(urduTotalWords)|آج|پرسوں?)\#(urduDayPart)"#
  }

  /// Group 1: the day, without the postposition that goes with it; group 2: that
  /// postposition.
  ///
  /// Today ("آج"), tomorrow ("کل"), the day after ("پرسوں"), each maybe with a
  /// part of the day ("آج رات", "کل صبح"); a number of days, weeks, or months
  /// ("3 دن بعد", "ایک ہفتے بعد", "1 مہینے بعد"); next week ("اگلے ہفتے"); a
  /// weekday, alone or after "اس", "اگلے", or "آنے والے" ("پیر", "اس جمعہ",
  /// "اگلے جمعہ"), maybe with a part of the day; the weekend; and a date ("5
  /// مئی", "پیر، 5 اکتوبر"). A phrase that a bound or a possessive follows is no
  /// planned day ("پیر کی میٹنگ").
  static var urduWhenPattern: String {
    let counted =
      #"(?:\d{1,3}|\#(urduRoundCountWords))\s+(?:دنوں|دن|ہفتے|ہفتہ|ہفتوں|مہینے|مہینہ|مہینوں|ماہ)\s+(?:کے\s+)?بعد"#
    let alternatives = [
      urduDayWords, counted, urduDatePhrase, urduWeekendPhrase, urduWeekdayPhrase, urduNextWeekPhrase,
    ]
    return
      #"\#(urduStart)(\#(alternatives.joined(separator: "|")))\#(urduEnd)\#(urduDayParticle)\#(urduNotFollowing)\#(urduDayPostposition)\#(urduDayParticle)"#
  }

  /// Whether a word that makes ہفتہ or ہفتے the week ("اس", "اگلے", "ہر") stands in
  /// `tokens` or right before `match`.
  private static func urduHasWeekModifier(_ tokens: [String], in match: Match) -> Bool {
    tokens.contains(where: urduWeekModifiers.contains)
      || (urduWordBefore(match).map(urduWeekModifiers.contains) ?? false)
  }

  /// Whether `phrase` names a weekday that belongs to a list of weekdays ("پیر
  /// اور جمعرات کو", "جمعہ، ہفتہ"): none of them is read alone, since one
  /// planned day cannot carry the list and the others would stay in the title.
  private static func urduIsListedWeekday(_ phrase: String, in match: Match) -> Bool {
    let tokens = urduDayTokens(phrase)
    let names = tokens.filter { urduWeekdayIndex($0) != nil }
    guard names.contains(where: { !urduIsWeekWord($0) }) || (!names.isEmpty && !urduHasWeekModifier(tokens, in: match))
    else { return false }
    let name = "(?:\(urduWeekdayNames))"
    let separator = #"(?:\s*[,،]\s*|\s+(?:اور|و)\s+)"#
    return urduFinds(#"\#(name)\#(separator)$"#, in: urduTextBefore(match))
      || urduFinds(#"^\#(separator)\#(name)\#(urduEnd)"#, in: urduTextAfter(match))
  }

  static func urduWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !urduIsNotComing(match), !urduIsPrayerDay(phrase, in: match),
      !urduIsListedWeekday(phrase, in: match)
    else { return nil }
    let marker = match.group(2).map(urduPhrase) ?? ""
    let isMarked = ["کو", "کے دن", "کے روز"].map(urduTablePhrase).contains(marker)
    return urduDay(phrase, in: match, isMarked: isMarked)
  }

  // MARK: - Due day

  /// The days a deadline may name, as a pattern without groups: today,
  /// tomorrow, the day after, a date, the weekend, a weekday, next week.
  private static var urduDueDay: String {
    #"(?:(?:آج|کل\#(urduTotalWords)|پرسوں?)\#(urduEnd)|\#(urduDatePhrase)|\#(urduWeekendPhrase)\#(urduEnd)|\#(urduWeekdayDay)\#(urduEnd)|\#(urduNextWeekPhrase)\#(urduEnd))"#
  }

  /// A weekday for a deadline: the names after a modifier and maybe a week
  /// word, or any name alone. The phrase has no group.
  private static var urduWeekdayDay: String {
    #"(?:\#(urduModifier)(?:\#(urduWeekWord)\s+(?:کے\s+)?)?(?:\#(urduDayOnlyNames))|\#(urduWeekdayNames))"#
  }

  /// A day with a deadline word after it ("جمعہ تک", "کل شام سے پہلے"), a
  /// deadline label before it ("آخری تاریخ: 5 مئی", "ڈیڈ لائن جمعہ"), or a
  /// deadline clock after it ("جمعہ شام 5 بجے تک", whose clock stays in the
  /// title). Groups: 1 the day after a label, 2 the day before a deadline word,
  /// 3 the day before a deadline clock. "آج تک" and "آج سے پہلے" are not
  /// deadlines: they mean "so far" and "never before". A deadline that a
  /// possessive follows ("جمعہ تک کی رپورٹ") is an attribute of the noun.
  static var urduDuePattern: String {
    let label =
      #"(?:(?:آخری|مقررہ|حتمی)\s+(?:تاریخ|مہلت)|ڈیڈ\s*لائن)(?:\s*[:：]\s*|\s+)(?:(?:کو|تک)\s+)?(\#(urduDueDay))(?:\s+ہے\#(urduEnd))?"#
    let word = urduDeadlineWords
    let before =
      #"(?!آج\s+\#(word)\#(urduEnd))(\#(urduDueDay))(?:\s+(?:کو\s+)?(?:(?:کی|کے)\s+)?\#(urduPartOfDayWords))?\s+\#(word)\#(urduEnd)(?!(?:\s+(?:ہی|بھی)\#(urduEnd))?\s+(?:کا|کی|کے|وال(?:ا|ی|ے))\#(urduEnd))\#(urduDayParticle)"#
    let clock =
      #"(\#(urduDueDay))(?:\s+کو\#(urduEnd))?(?=\s+(?:\#(urduPartOfDayWords)\s+(?:(?:کے|کو)\s+)?)?(?:\#(urduClockPhrase))\s+\#(word)\#(urduEnd))"#
    return #"\#(urduStart)(?:\#(label)|\#(before)|\#(clock))"#
  }

  static func urduDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3), !urduIsNotComing(match),
      !urduIsPrayerDay(phrase, in: match)
    else { return nil }
    return urduDay(phrase, in: match, isMarked: true).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The words and numbers of `phrase`, without vowel signs.
  private static func urduDayTokens(_ phrase: String) -> [String] {
    urduPhrase(phrase).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }

  /// Whether `tokens` hold a part of the day.
  private static func urduHasPartOfDay(_ tokens: [String]) -> Bool {
    let parts = Set(["صبح", "سویرے", "تڑکے", "دوپہر", "پہر", "شام", "رات"].map(urduTableKey))
    return tokens.contains(where: parts.contains)
  }

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "اس" makes it this week's, today when it
  /// names today; "اگلے" makes it next week's, weeks starting on Monday; "آئندہ"
  /// and "آنے والے" make it the coming one, a full week ahead when it names
  /// today. ہفتہ and ہفتے name Saturday only when `isMarked` (a postposition
  /// that marks a day follows, or a deadline word or label stands by the phrase),
  /// or "بروز" or a part of the day goes with them, and no word that makes them
  /// the week comes before them.
  private static func urduDay(_ phrase: String, in match: Match, isMarked: Bool) -> Day? {
    let words = urduPhrase(phrase)
    if let date = urduDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = urduDayTokens(phrase)
    if tokens.last == urduTableKey("بعد"), let first = tokens.first, (number(first) ?? urduRoundCounts[first]) != nil {
      return urduRelativeDay(tokens.dropLast().filter { $0 != urduTableKey("کے") }, in: match)
    }
    let isEvening = tokens.contains(urduTableKey("رات"))
    if tokens.contains(urduTableKey("آج")) { return Day(offset: 0, isEvening: isEvening) }
    if tokens.contains(urduTableKey("کل")) { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains(urduTableKey("پرسوں")) || tokens.contains(urduTableKey("پرسو")) {
      return Day(offset: 2, isEvening: isEvening)
    }
    let isNext = tokens.contains(where: urduNextWords.contains)
    if urduFinds(urduWeekendWords, in: words) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    let todayWeekday = match.todayWeekday
    if let weekday = tokens.lazy.filter({ !urduIsWeekWord($0) }).compactMap(urduWeekdayIndex).first {
      if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
      if tokens.contains(where: urduThisWords.contains) {
        return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    guard tokens.contains(where: urduIsWeekWord) else { return nil }
    if isNext || tokens.contains(where: urduComingWords.contains) { return Day(offset: 7) }
    // A bare ہفتہ or ہفتے: Saturday beside a mark of a day, otherwise the week.
    let isMarkedByWords = tokens.contains(urduTableKey("بروز")) || urduHasPartOfDay(tokens)
    guard !urduHasWeekModifier(tokens, in: match), isMarked || isMarkedByWords else { return nil }
    return Day(offset: comingWeekdayOffset(6, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// The day of "3 دن بعد", "ایک ہفتے بعد", "1 مہینے بعد", from the words
  /// before "بعد": a count and a unit. A count of days or weeks needs no date;
  /// a count of months is counted on the calendar from today. Nil after a word
  /// that ties the amount to another event ("میٹنگ کے 3 دن بعد", "آج سے 3 دن
  /// بعد").
  private static func urduRelativeDay(_ tokens: [String], in match: Match) -> Day? {
    guard tokens.count == 2, let count = number(tokens[0]) ?? urduRoundCounts[tokens[0]], count >= 1 else {
      return nil
    }
    if let before = urduWordBefore(match), ["کے", "کی", "کا", "سے"].map(urduTableKey).contains(before) { return nil }
    switch tokens[1] {
    case urduTableKey("دن"), urduTableKey("دنوں"): return Day(offset: count)
    case urduTableKey("ہفتے"), urduTableKey("ہفتہ"), urduTableKey("ہفتوں"): return Day(offset: count * 7)
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

  /// "3 سے 5 مارچ", "3 مارچ سے 5 مارچ تک", "30 جنوری سے 2 فروری تک", "3 تا 5
  /// مارچ", "3-5 مارچ", "3 اور 5 مارچ کے درمیان", each maybe with a year after a
  /// month, with "سے لے کر" for "سے", and with تک, "کے بیچ", or "کے درمیان"
  /// after the end. The start is a date or a day alone ("3"); the end is a
  /// date. Groups: 1 the start, 2 a dash between the sides, 3 "سے" or "تا"
  /// between them, 4 "اور" between them, 5 the end, 6 "کے بیچ" or "کے درمیان"
  /// after the end.
  static var urduDateRangePattern: String {
    let bare = #"\d{1,2}\#(urduNoMoreDigits)"#
    let side = "\(urduMonthDatePattern)|\(bare)"
    return
      #"\#(urduStart)(?:(?:بتاریخ|تاریخ)\s*[:：]?\s*)?(\#(side))(?:\s*([-–—])\s*|\s+(سے|تا)(?:\s+(?:لے\s*کر|لیکر))?\s+|\s+(اور|و)\s+)(\#(side))(?:\s+(?:تک|(کے\s+(?:بیچ|درمیان)))\#(urduEnd))?+\#(urduDateEnd)"#
  }

  /// A range in the past tense, or one that a possessive follows ("5 سے 8 مئی
  /// تک کی چھٹی"), names a trip or an event that the task may only prepare for:
  /// it is claimed whole and read as no days, so "8 مئی تک" is not read alone as
  /// a due day. So is two days joined by "اور" with no "کے درمیان" after them
  /// ("3 اور 5 مارچ" names two days). A day alone opens a range joined by a dash
  /// only when the dash touches both sides ("3-5 مارچ"): "Sprint 12 - 20 مارچ"
  /// names a sprint and a date.
  static func urduDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(5),
      let start = urduRangeDate(startText), let end = urduRangeDate(endText)
    else { return nil }
    if start.month == nil, match.group(2) != nil, !dashTouchesBothSides(match, start: 1, end: 5) { return nil }
    guard end.month != nil else { return nil }
    if match.group(4) != nil, match.group(6) == nil { return .declined }
    if urduIsNotComing(match) || urduIsPossessed(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 مئی") or a day alone ("5"), which has no
  /// month.
  private static func urduRangeDate(_ text: String) -> ExplicitDate? {
    let words = urduPhrase(text)
    if let date = urduDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  /// "پیر سے بدھ تک", "جمعہ سے پیر", "پیر تا بدھ": a span of weekdays, maybe
  /// with "سے لے کر" for "سے" and with تک, "کے بیچ", or "کے درمیان" after it.
  /// Groups: 1 the first weekday, 2 the last.
  static var urduWeekdayRangePattern: String {
    #"\#(urduStart)(\#(urduWeekdayNames))\s+(?:سے|تا)(?:\s+(?:لے\s*کر|لیکر))?\s+(\#(urduWeekdayNames))\#(urduEnd)(?:\s+(?:تک|کے\s+(?:بیچ|درمیان))\#(urduEnd))?+"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "پیر سے بدھ تک" runs from next Monday to the
  /// Wednesday after it. A span in the past tense or one that a possessive
  /// follows ("پیر سے بدھ تک کی چھٹی") is claimed whole and read as no days. A
  /// span that "ہر" or the words for every day accompany is a habit, which the
  /// repeat rules read (``urduIsHabitSpan(_:)``), and Monday to Friday or to
  /// Saturday with no such word is claimed whole too: it is the working week as
  /// often as it is a span of days. A span from a day to itself is no span, and
  /// a span that begins with ہفتہ or ہفتے after a word that makes it the week
  /// ("اگلے ہفتے سے بدھ تک") is no span of weekdays.
  static func urduWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1), let lastWord = match.group(2),
      let first = urduWeekdayIndex(firstWord), let last = urduWeekdayIndex(lastWord), first != last
    else { return nil }
    if urduIsWeekWord(urduKey(firstWord)), urduWordBefore(match).map(urduWeekModifiers.contains) ?? false {
      return nil
    }
    if urduIsNotComing(match) || urduIsPossessed(match) { return .declined }
    if urduIsHabitSpan(match) { return nil }
    if first == 1 && (last == 5 || last == 6) { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
