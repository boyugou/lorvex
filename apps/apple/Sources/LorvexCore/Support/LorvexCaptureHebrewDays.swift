import Foundation

extension LorvexCaptureVocabulary {
  // The Hebrew day rules: the planned day, the due day, written dates, and date
  // ranges. The vocabulary's other words are in ``hebrew``.

  // MARK: - Names

  /// Each weekday's name, Sunday first. The ordinal names (ראשון, שני, ...) are
  /// also ordinary words, so they name a day only after "יום" or an attached ב
  /// ("ביום שני", "בשלישי"); שבת is the Sabbath and so it too names a day only
  /// there.
  private static let hebrewWeekdayNameList = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]

  /// The weekday names with an attached ב ("בשלישי"), keyed as
  /// ``hebrewKey(_:)`` leaves a matched word.
  private static let hebrewWeekdayIndexByKey: [String: Int] = {
    var index: [String: Int] = [:]
    for (weekday, name) in hebrewWeekdayNameList.enumerated() {
      index[hebrewTableKey(name)] = weekday
      index[hebrewTableKey("ב" + name)] = weekday
    }
    return index
  }()

  /// The one-letter names of the weekdays, written with a geresh after "יום"
  /// ("יום ג׳" is Tuesday): א׳ Sunday through ו׳ Friday, and ש׳ Saturday.
  private static let hebrewAbbreviationIndex: [String: Int] = {
    var index: [String: Int] = [:]
    for (weekday, letter) in ["א", "ב", "ג", "ד", "ה", "ו", "ש"].enumerated() {
      index[hebrewForMatching(letter + "׳")] = weekday
    }
    return index
  }()

  /// The weekday a name in the reading form names, 0 = Sunday.
  static func hebrewWeekdayIndex(_ word: String) -> Int? {
    let bare = hebrewBare(word)
    return hebrewAbbreviationIndex[bare] ?? hebrewWeekdayIndexByKey[hebrewKey(bare)]
  }

  /// The full weekday names, as a pattern without groups.
  private static let hebrewFullNames = #"(?:ראשון|שני|שלישי|רביעי|חמישי|שישי|שבת)"#

  /// A weekday name after "יום", as a pattern without groups: the names and the
  /// one-letter forms.
  private static let hebrewYomNames = #"(?:\#(hebrewFullNames)|[אבגדהוש]׳)"#

  /// "יום שני", "ביום שני", "ליום שני", "מיום שני", "יום ג׳". The phrase has no
  /// group.
  private static let hebrewYomPhrase = #"[בלמ]?יום\s+\#(hebrewYomNames)"#

  /// A name with an attached ב and no "יום" ("בשלישי", "בשבת"), which
  /// ``hebrewIsBareWeekday(_:in:)`` judges by the words around it. The phrase has
  /// no group.
  private static let hebrewBethName = #"ב(?:ראשון|שני|שלישי|רביעי|חמישי|שישי|שבת)"#

  /// A name with no "יום" and no ב, as it stands after "עד" ("עד שלישי"). שני is
  /// not here: "עד שני" is as often "until the second" as "until Monday".
  private static let hebrewBareName = #"(?:ראשון|שלישי|רביעי|חמישי|שישי|שבת)"#

  /// The weekday names for a repeat, as a pattern without groups, each with
  /// "יום" before it or not.
  static let hebrewRepeatNames = #"(?:ראשון|שני|שלישי|רביעי|חמישי|שישי|שבת|[אבגדהוש]׳)"#

  // MARK: - Dates

  /// Each month's Gregorian names, January first. The names of the Hebrew
  /// calendar's months (תשרי, חשוון, ניסן, ...) are not here: they are not
  /// Gregorian dates.
  private static let hebrewMonthNameList: [[String]] = [
    ["ינואר"], ["פברואר"], ["מרץ", "מרס"], ["אפריל"], ["מאי"], ["יוני"], ["יולי"], ["אוגוסט"], ["ספטמבר"],
    ["אוקטובר"], ["נובמבר"], ["דצמבר"],
  ]

  /// The month names keyed as ``hebrewKey(_:)`` leaves a matched word, with and
  /// without the ב that Hebrew attaches to a month ("במרץ").
  private static let hebrewMonthIndexByKey: [String: Int] = {
    var index: [String: Int] = [:]
    for (month, names) in hebrewMonthNameList.enumerated() {
      for name in names {
        index[hebrewTableKey(name)] = month
        index[hebrewTableKey("ב" + name)] = month
      }
    }
    return index
  }()

  /// "5 במרץ", "5 מרץ", "5 במרץ 2027", "5 במרץ, 2027": a day number before a
  /// Gregorian month name, maybe with a year. A date written in digits only
  /// ("5.3", "5/3/2027") and a month of the Hebrew calendar are not read.
  static var hebrewMonthDatePattern: String {
    let names = alternation(of: hebrewMonthNameList.flatMap { $0 })
    return #"\d{1,2}\s+ב?(?:\#(names))(?:\s*,?\s*(?:19|20)\d{2})?"#
  }

  /// A date, maybe after a label and a weekday and with a preposition attached
  /// to its number: "5 במרץ", "ב-5 במרץ", "ה-5 במרץ", "בתאריך 5 במרץ", "ביום שני,
  /// 5 באוקטובר". The phrase has no group.
  private static var hebrewDatePhrase: String {
    #"(?:[בל]?תאריך\s*:?\s*)?(?:[בל]?יום\s+\#(hebrewYomNames)\s*,?\s+)?(?:(?:מה|[בלהמ])-?)?\#(hebrewMonthDatePattern)\#(hebrewDateEnd)"#
  }

  /// A written-out date: "5 במרץ", "ב-5 במרץ 2027". The words are a phrase as
  /// ``hebrewPhrase(_:)`` leaves it.
  static func hebrewDate(_ words: String) -> ExplicitDate? {
    let tokens = words.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    guard let dayIndex = tokens.firstIndex(where: { number($0) != nil }), let day = number(tokens[dayIndex]),
      dayIndex + 1 < tokens.count, let month = hebrewMonthIndexByKey[hebrewKey(tokens[dayIndex + 1])]
    else { return nil }
    let year =
      dayIndex + 2 < tokens.count
      ? tokens[dayIndex + 2].wholeMatch(of: /(?:19|20)\d{2}/).flatMap { number($0.output) } : nil
    return ExplicitDate(year: year, month: month + 1, day: day)
  }

  // MARK: - The words around a day

  /// The words that make a day phrase no coming day: the line puts its day in the
  /// past ("היה", "אתמול") or the phrase is followed by a word that makes the
  /// day past or ordinal ("שעבר", "הקודם", "האחרון"). The forms of "היה" are
  /// listed in both spellings, with and without the second yod ("הייתה",
  /// "היתה").
  private static let hebrewPastMarkers: Set<String> = Set(
    [
      "היה", "הייתה", "היתה", "היו", "הייתי", "היתי", "היית", "הייתם", "היתם", "הייתן", "היתן", "היינו", "אתמול",
      "שלשום", "אמש",
    ].map(hebrewTableKey))

  /// Whether `match` names a day that is no coming one: the line is in the past
  /// tense ("הפגישה הייתה ביום שני"), or a word after the phrase makes the day
  /// past ("יום שני שעבר", "ביום שני האחרון").
  static func hebrewIsNotComing(_ match: Match) -> Bool {
    if hebrewFinds(
      #"^\s+(?:שעבר|שעברה|שעברו|הקודם|הקודמת|האחרון|האחרונה|שחלף|שחלפה)\#(hebrewEnd)"#, in: hebrewTextAfter(match))
    {
      return true
    }
    return hebrewWords(in: match.source).contains { hebrewPastMarkers.contains(hebrewKey($0)) }
  }

  /// The words before a day phrase that make it no planned day: a possessive or
  /// "every" ("הדוח של מחר", "כל יום", "בכל יום"), a bound or a comparison
  /// ("עד", "לפני", "אחרי", "מאז"), and "סוף" ("end of": "סוף היום").
  private static let hebrewNotPlannedBefore: Set<String> = Set(
    ["של", "כל", "בכל", "לכל", "מדי", "עד", "לפני", "אחרי", "מאז", "מעל", "בתוך", "במשך", "סוף"].map(hebrewTableKey))

  /// The words that open a day phrase and make it a noun when a word in the
  /// construct state, which ends in ת, stands before it: "ארוחת הערב" (dinner),
  /// "חדשות הערב" (the evening news), "משמרת הלילה", "את היום" (the object
  /// "the day"), and "ישיבת יום שני" (Monday's meeting).
  private static let hebrewConstructOpeners: Set<String> = Set(
    ["הערב", "הלילה", "הבוקר", "היום", "יום"].map(hebrewTableKey))

  /// Whether a possessive or "every" stands before the phrase, or a word in the
  /// construct state stands before an opener that it makes a noun with.
  private static func hebrewIsAttribute(_ tokens: [String], in match: Match) -> Bool {
    guard let before = hebrewWordBefore(match) else { return false }
    if hebrewNotPlannedBefore.contains(before) { return true }
    return before.hasSuffix(hebrewTableKey("ת")) && tokens.first.map(hebrewConstructOpeners.contains) ?? false
  }

  /// The part of the day after a day, as an optional piece of a phrase: "מחר
  /// בבוקר", "היום בערב", "ביום שלישי אחר הצהריים".
  private static var hebrewDayPart: String { #"(?:\s+\#(hebrewPartOfDayWords))?"# }

  // MARK: - Planned day

  /// What may not follow "היום": the article and an adjective that make it "the
  /// day" ("היום הראשון", "היום הבא", "היום הלאומי").
  private static let hebrewTodayGuard =
    #"(?!\s+ה(?:ראשון|שני|שלישי|רביעי|חמישי|שישי|שביעי|אחרון|בא|קודם|זה|נוכחי|בינלאומי|לאומי|עולמי)\#(hebrewEnd))"#

  /// Today, tomorrow, the day after, and this evening, each maybe with a part of
  /// the day ("מחר בבוקר", "היום אחר הצהריים"). The phrase has no group.
  private static var hebrewDayWords: String {
    #"(?:(?:ל?מחרת(?:יי|י)ם|ל?מחר|היום\#(hebrewTodayGuard))\#(hebrewDayPart)|ה(?:ערב|לילה|בוקר))"#
  }

  /// "בעוד 3 ימים", "בעוד שלושה ימים", "בעוד יומיים", "בעוד שבוע", "בעוד שבועיים",
  /// "בעוד חודש", "בעוד 3 חודשים". The phrase has no group.
  private static var hebrewCountedPhrase: String {
    #"בעוד\s+(?:(?:\d{1,3}|\#(hebrewCountWords))\s+(?:ימים|שבועות|חודשים)|יומיים|שבועיים|חודשיים|(?:יום|שבוע|חודש)(?:\s+אחד)?)"#
  }

  /// The week that follows ("בשבוע הבא", "שבוע הבא", "השבוע הבא") and this one
  /// ("השבוע", "בשבוע הזה"), as patterns without groups.
  private static let hebrewNextWeekWords = #"(?:ב|ל)?ה?שבוע\s+הבא"#
  private static let hebrewThisWeekWords = #"(?:ב?ה?שבוע\s+(?:הזה|זה)|השבוע)"#

  /// The weekend: "סוף שבוע", "סוף השבוע", "סופ״ש", each maybe with ב or ל and with
  /// "הבא", "הקרוב", or "הזה" after it. The phrase has no group.
  static let hebrewWeekendWords = #"(?:ב|ל)?(?:סוף[\s-]+ה?שבוע|סופ״?ש)(?:\s+(?:הבא|הקרוב|הזה))?"#

  /// A weekday, with "יום" or an attached ב, and the weeks around it: "ביום שני",
  /// "ביום שני הבא", "ביום שני בשבוע הבא", "בשבוע הבא ביום שני", "השבוע ביום
  /// שני", "ביום שני השבוע", each maybe with a part of the day. The phrase has no
  /// group.
  private static var hebrewWeekdayPhrase: String {
    let before = #"(?:(?:\#(hebrewNextWeekWords)|\#(hebrewThisWeekWords))\s*,?\s+)"#
    let after =
      #"(?:\s+(?:(?:של\s+)?(?:\#(hebrewNextWeekWords)|\#(hebrewThisWeekWords))|הבאה?|הקרובה?|הזה|הזאת))"#
    return #"\#(before)?(?:\#(hebrewYomPhrase)|\#(hebrewBethName))\#(after)?\#(hebrewDayPart)"#
  }

  /// "בשבוע הבא", "שבוע הבא": seven days ahead. The phrase has no group.
  private static var hebrewNextWeekPhrase: String { hebrewNextWeekWords }

  /// Group 1: the day. Today ("היום"), tomorrow ("מחר", "למחר"), the day after
  /// ("מחרתיים"), this evening ("הערב", "הלילה", "הבוקר"), each maybe with a
  /// part of the day; a number of days, weeks, or months ("בעוד 3 ימים"); next
  /// week; a weekday with "יום" or an attached ב; the weekend; and a date. A
  /// phrase that a possessive or "every" comes before is no planned day ("הדוח
  /// של מחר", "כל יום שני").
  static var hebrewWhenPattern: String {
    let alternatives = [
      hebrewDayWords, hebrewCountedPhrase, hebrewDatePhrase, hebrewWeekendWords, hebrewWeekdayPhrase,
      hebrewNextWeekPhrase,
    ]
    return #"\#(hebrewStart)(\#(alternatives.joined(separator: "|")))\#(hebrewEnd)"#
  }

  /// The words and numbers of `phrase`, without niqqud, a geresh kept in a
  /// word ("ג׳").
  private static func hebrewDayTokens(_ phrase: String) -> [String] {
    hebrewPhrase(phrase).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "\u{05F3}" }).map(String.init)
  }

  /// Whether `tokens` hold the word that makes the phrase a day that is always
  /// ahead (tomorrow, the day after, in a number of days), which a past-tense
  /// line leaves as it is. Today and this evening are no such days: "היום הייתה
  /// פגישה" says what happened.
  private static func hebrewIsFixedDay(_ tokens: [String]) -> Bool {
    let fixed = ["מחר", "למחר", "מחרתיים", "מחרתים", "למחרתיים", "למחרתים", "בעוד"]
    return tokens.contains(where: Set(fixed.map(hebrewTableKey)).contains)
  }

  /// Whether `match`, a weekday phrase, is one name of a list of weekdays ("ביום
  /// שני וחמישי", "ביום שני וביום רביעי", "בשישי ובשבת", "בשני, בחמישי", "בשישי
  /// או בשבת", "בשישי-שבת"): none is read alone, since one planned day cannot
  /// carry the list and the others would stay in the title.
  private static func hebrewIsListedWeekday(in match: Match) -> Bool {
    let separator = #"(?:(?:\s*,\s*|\s+)(?:ו|או\s+|וגם\s+)?|\s*-\s*)"#
    return hebrewFinds(
      #"^\#(separator)(?:ב?יום\s+|ב)?\#(hebrewYomNames)\#(hebrewEnd)"#, in: hebrewTextAfter(match))
      || hebrewFinds(
        #"\#(hebrewStart)(?:ב?יום\s+|ב)?\#(hebrewYomNames)(?:\s*,\s*|\s+ו|\s+או\s+|\s+וגם\s+)(?:ב?יום\s+)?$"#,
        in: hebrewTextBefore(match))
  }

  /// Whether a name with an attached ב and no "יום" ("בשלישי") is a weekday here:
  /// not before a month or "החודש" ("בראשון לחודש", "בראשון במאי"), the city
  /// "ראשון לציון", or "מתוך" ("בשישי מתוך עשרה" is the sixth of ten), and, for
  /// "בשני", which is also "in two" ("בשני מקומות"), only where nothing but a
  /// part of the day, a time, "הבא", or the end of the line follows.
  private static func hebrewIsBareWeekday(_ tokens: [String], in match: Match) -> Bool {
    guard let name = tokens.first(where: { hebrewWeekdayIndex($0) != nil && $0.hasPrefix(hebrewTableKey("ב")) }) else {
      return true
    }
    let after = hebrewTextAfter(match)
    let months = alternation(of: hebrewMonthNameList.flatMap { $0 })
    if hebrewFinds(#"^\s+(?:[בל](?:חודש|\#(months))|לציון|מתוך)\#(hebrewEnd)"#, in: after) { return false }
    guard name == hebrewTableKey("בשני") else { return true }
    return hebrewFinds(
      #"^(?:\s*$|\s*[,.;:!?)]|\s+(?:\#(hebrewPartOfDayWords)|בשעה|ב-?\d|\d|הבא|הקרוב))"#, in: after)
  }

  static func hebrewWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1) else { return nil }
    let tokens = hebrewDayTokens(phrase)
    if hebrewIsAttribute(tokens, in: match) { return nil }
    if !hebrewIsFixedDay(tokens) {
      if hebrewIsNotComing(match) || hebrewIsListedWeekday(in: match) { return nil }
      if !hebrewIsBareWeekday(tokens, in: match) { return nil }
    }
    return hebrewDay(phrase, in: match)
  }

  // MARK: - Due day

  /// The weekday of a deadline, as a pattern without groups: "יום שני", "ביום שני
  /// הבא", "בשבוע הבא ביום שני", or a name alone ("שלישי"), maybe with the weeks
  /// around it.
  private static var hebrewWeekdayDay: String {
    let before = #"(?:(?:\#(hebrewNextWeekWords)|\#(hebrewThisWeekWords))\s*,?\s+)"#
    let after =
      #"(?:\s+(?:(?:של\s+)?(?:\#(hebrewNextWeekWords)|\#(hebrewThisWeekWords))|הבאה?|הקרובה?|הזה|הזאת))"#
    return #"\#(before)?(?:\#(hebrewYomPhrase)|\#(hebrewBareName))\#(after)?"#
  }

  /// The days a deadline may name, as a pattern without groups: tomorrow, the day
  /// after, this evening, the end of today ("סוף היום"), a date, a weekday (maybe
  /// after "סוף": "סוף יום שני"), next week. "עד היום" ("so far") and "עד הבוקר"
  /// are not deadlines, and the weekend is not one either ("עד סוף השבוע" is the
  /// end of the working week as often as it is the weekend).
  static var hebrewDueDay: String {
    #"(?:מחרת(?:יי|י)ם|מחר|ה(?:ערב|לילה)|סוף\s+היום|\#(hebrewDatePhrase)|(?:סוף\s+)?\#(hebrewWeekdayDay)|\#(hebrewNextWeekPhrase))"#
  }

  /// A day after "עד", "לפני", or "לא יאוחר מ" ("עד יום שישי", "עד מחר", "עד ה-5
  /// במרץ", "עד מחר בבוקר", "לפני יום שישי", "לא יאוחר מיום שלישי", "לא יאוחר
  /// ממחר"), or after a deadline label ("מועד אחרון: יום שישי", "תאריך יעד: 5
  /// במרץ", "דדליין מחר"). "לפני" takes a weekday or a date only, since "לפני
  /// מחר" may be today as well as tomorrow. A part of the day after the day goes
  /// with it. Groups: 1 the day after a label, 2 the day after "עד", 3 the day
  /// after "לפני", 4 the day after "לא יאוחר מ". The clock after a deadline day
  /// stays in the title (``hebrewDueClockPattern``).
  static var hebrewDuePattern: String {
    let label =
      #"(?:מועד\s+(?:אחרון|הגשה|יעד|סופי)|תאריך\s+(?:יעד|אחרון|הגשה|סופי|סיום|היעד)|דד\s*ליין)(?:\s*[:：]\s*|\s+)(?:עד\s+)?(\#(hebrewDueDay))\#(hebrewEnd)"#
    let part = #"(?:\s+\#(hebrewPartOfDayWords))?"#
    let until = #"עד\s+(\#(hebrewDueDay))\#(part)\#(hebrewEnd)"#
    let before = #"לפני\s*-?\s*(?!שבת\#(hebrewEnd))(\#(hebrewWeekdayDay)|\#(hebrewDatePhrase))\#(part)\#(hebrewEnd)"#
    let notLater = #"לא\s+יאוחר\s+מ-?\s*(\#(hebrewDueDay))\#(part)\#(hebrewEnd)"#
    return #"\#(hebrewStart)(?:\#(label)|\#(until)|\#(before)|\#(notLater))"#
  }

  static func hebrewDue(_ match: Match) -> Day? {
    guard let phrase = (1...4).lazy.compactMap({ match.group($0) }).first, !hebrewIsNotComing(match) else {
      return nil
    }
    return hebrewDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The day a phrase names. A weekday alone means the next such day, a full week
  /// ahead when it names today; "הזה", "השבוע", or "בשבוע הזה" makes it this
  /// week's, today when it names today; "בשבוע הבא" makes it next week's, weeks
  /// starting on Monday; "הבא" and "הקרוב" make it the coming one, a full week
  /// ahead when it names today.
  private static func hebrewDay(_ phrase: String, in match: Match) -> Day? {
    let words = hebrewPhrase(phrase)
    if let date = hebrewDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = hebrewDayTokens(phrase)
    if tokens.first == hebrewTableKey("בעוד") { return hebrewRelativeDay(Array(tokens.dropFirst()), in: match) }
    let has: (String) -> Bool = { tokens.contains(hebrewTableKey($0)) }
    let isEvening = tokens.contains { [.night, .evening].contains(hebrewPartOfDay($0)) }
    if has("היום") { return Day(offset: 0, isEvening: isEvening) }
    if has("הערב") || has("הלילה") { return Day(offset: 0, isEvening: true) }
    if has("הבוקר") { return Day(offset: 0) }
    if has("מחר") || has("למחר") { return Day(offset: 1, isEvening: isEvening) }
    if has("מחרתיים") || has("מחרתים") || has("למחרתיים") || has("למחרתים") {
      return Day(offset: 2, isEvening: isEvening)
    }
    let isNext = has("הבא")
    if hebrewFinds(hebrewWeekendWords, in: words) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    let hasWeek = has("שבוע") || has("בשבוע") || has("השבוע") || has("לשבוע")
    let todayWeekday = match.todayWeekday
    if let weekday = tokens.lazy.compactMap(hebrewWeekdayIndex).first {
      if hasWeek && isNext {
        return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      if has("השבוע") || has("הזה") || has("הזאת") || (hasWeek && (has("זה"))) {
        return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return hasWeek && isNext ? Day(offset: 7) : nil
  }

  /// The day of "בעוד 3 ימים", "בעוד יומיים", "בעוד שבוע", "בעוד חודש", from the
  /// words after "בעוד": a count and a unit, or a dual or a singular unit. A
  /// count of days or weeks needs no date; a count of months is counted on the
  /// calendar from today.
  private static func hebrewRelativeDay(_ tokens: [String], in match: Match) -> Day? {
    func months(_ count: Int) -> Day? {
      guard let today = match.today else { return nil }
      let calendar = utcCalendar
      guard let target = calendar.date(byAdding: .month, value: count, to: today),
        let days = calendar.dateComponents([.day], from: today, to: target).day
      else { return nil }
      return Day(offset: days)
    }
    guard let unit = tokens.last else { return nil }
    var counted = tokens.dropLast().joined()
    var count = 1
    if unit == hebrewTableKey("אחד"), tokens.count >= 2 {
      return hebrewRelativeDay(Array(tokens.dropLast()), in: match)
    }
    if !counted.isEmpty {
      guard let value = number(counted) ?? hebrewCounts[counted], value >= 1 else { return nil }
      count = value
      counted = ""
    }
    switch unit {
    case hebrewTableKey("יומיים"): return Day(offset: 2)
    case hebrewTableKey("שבועיים"): return Day(offset: 14)
    case hebrewTableKey("חודשיים"): return months(2)
    case hebrewTableKey("יום"), hebrewTableKey("ימים"): return Day(offset: count)
    case hebrewTableKey("שבוע"), hebrewTableKey("שבועות"): return Day(offset: count * 7)
    case hebrewTableKey("חודש"), hebrewTableKey("חודשים"): return months(count)
    default: return nil
    }
  }

  // MARK: - Date range

  /// "מ-3 עד 5 במרץ", "מה-3 ועד ה-5 במרץ", "מ-3 במרץ עד 5 במרץ", "מ-30 בינואר עד 2
  /// בפברואר", "בין 3 ל-5 במרץ", "בין 3 ו-5 במרץ", "3-5 במרץ", each maybe with a
  /// year after a month. The start is a date or a day alone ("3"); the end is a
  /// date. Groups: 1 the opener ("מ-", "מתאריך", "מיום", "בין", "בתאריכים"), 2
  /// the start, 3 a dash between the sides, 4 "עד" or "ועד", 5 "ל-", "ו-", or
  /// "לבין", 6 the end.
  static var hebrewDateRangePattern: String {
    let bare = #"\d{1,2}\#(hebrewNoMoreDigits)"#
    let side = #"(?:ה-?)?(?:\#(hebrewMonthDatePattern)|\#(bare))"#
    let opener = #"(בין\s+(?:התאריכים\s+)?|מתאריך\s+|מיום\s+|מ(?:ה)?-?|בתאריכים\s+)"#
    return
      #"\#(hebrewStart)\#(opener)?(\#(side))(?:\s*([-–—])\s*|\s+(עד|ועד)\s+|\s+(ל-?|ו-?|לבין\s+))(\#(side))\#(hebrewDateEnd)"#
  }

  /// The first group-1 opener, then the connector, decide whether the text is a
  /// range: "עד" and "ועד" join the sides after an opener that begins with מ,
  /// "ל-", "ו-", and "לבין" after "בין", and a dash anywhere (a day alone
  /// opens a range joined by a dash only when the dash touches both sides:
  /// "ספרינט 12 - 20 במרץ" names a sprint and a date). Two days joined by "ו-"
  /// with no "בין" ("3 ו-5 במרץ") are two days, not a range, and stay in the
  /// title whole, and so does a range in the past tense.
  static func hebrewDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(6),
      let start = hebrewRangeDate(startText), let end = hebrewRangeDate(endText)
    else { return nil }
    let opener = match.group(1).map(hebrewKey)
    let isBetween = opener?.hasPrefix(hebrewTableKey("בין")) ?? false
    let isFrom = opener != nil && !isBetween
    if start.month == nil, match.group(3) != nil, opener == nil, !dashTouchesBothSides(match, start: 2, end: 6) {
      return nil
    }
    guard end.month != nil else { return nil }
    if let connector = match.group(5).map(hebrewKey) {
      if !isBetween { return connector == hebrewTableKey("ו") ? .declined : nil }
    } else if match.group(4) != nil {
      if !isFrom { return nil }
    }
    if hebrewIsNotComing(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 במרץ") or a day alone ("5", "ה-5"), which
  /// has no month.
  private static func hebrewRangeDate(_ text: String) -> ExplicitDate? {
    let words = hebrewPhrase(text)
    if let date = hebrewDate(words) { return date }
    let tokens = words.split(separator: " ").map(String.init)
    guard let token = tokens.first(where: { number($0) != nil }), let day = number(token),
      tokens.allSatisfy({ $0 == token || $0 == hebrewTableKey("ה") })
    else { return nil }
    return ExplicitDate(day: day)
  }

  /// "מיום שני עד יום רביעי", "מיום שני ועד רביעי", "משני עד רביעי", "בין יום שני
  /// ליום רביעי", "מיום ב׳ עד ד׳": a span of weekdays. The name after an
  /// attached מ is a full name, never a letter. Groups: 1 the first weekday and 2
  /// the last after "עד"; 3 the first and 4 the last after "בין".
  static var hebrewWeekdayRangePattern: String {
    let name = hebrewYomNames
    let from = #"(?:(?:מיום|ביום|יום)\s+|מ(?=\#(hebrewFullNames)))"#
    return
      #"\#(hebrewStart)(?:\#(from)(\#(name))\s+(?:עד|ועד)\s+(?:יום\s+)?(\#(name))|בין\s+יום\s+(\#(name))\s+[לו](?:ב?יום\s+)?(\#(name)))\#(hebrewEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "מיום שני עד יום רביעי" runs from next Monday
  /// to the Wednesday after it. A span in the past tense is claimed whole and
  /// read as no days. A span that "כל" accompanies is a habit, which the repeat
  /// rules read (``hebrewIsHabitSpan(_:)``), and Sunday to Thursday, Monday to
  /// Friday, and the like with none of them are claimed whole too: they are the
  /// working week as often as they are a span of days. A span from a day to
  /// itself names no days and is claimed whole, like a span in the past tense.
  static func hebrewWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1) ?? match.group(3), let lastWord = match.group(2) ?? match.group(4),
      let first = hebrewWeekdayIndex(firstWord), let last = hebrewWeekdayIndex(lastWord)
    else { return nil }
    if first == last || hebrewIsNotComing(match) { return .declined }
    if hebrewIsHabitSpan(match) { return nil }
    if (first == 1 && (last == 5 || last == 6)) || (first == 0 && (last == 4 || last == 5)) { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
