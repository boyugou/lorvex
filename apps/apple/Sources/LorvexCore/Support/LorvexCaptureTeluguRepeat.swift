import Foundation

extension LorvexCaptureVocabulary {
  // The Telugu repeat rules. The vocabulary's other words are in ``telugu``.

  /// The repeat rules, in the order they are tried: a span of weekdays beside
  /// "ప్రతి" or the words for every day, the working days, the weekend, and a
  /// day of the month before the weekdays and every day and every month, which
  /// would leave "సోమవారం" or the day's number in the title; then the weekdays,
  /// a part of the day, an amount of days with "కోసారి" or "ఒకసారి" or every
  /// other day ("రోజు విడిచి రోజు") before the plain interval, which would
  /// leave the "ఒకసారి" of "3 నెలలకు ఒకసారి" in the title, "once a week", the
  /// words for every day, and the adjectives that say how a task repeats.
  static var teluguRepeatRules: [Rule<Repeat>] {
    [
      teluguRule(teluguWeekdaySpanPattern, read: teluguWeekdaySpanRepeat),
      teluguRule(teluguWorkdaysPattern) { _ in workdays },
      teluguRule(teluguWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      teluguRule(teluguMonthDayRepeatPattern, read: teluguMonthDayRepeat),
      teluguRule(teluguWeekdayRepeatPattern, read: teluguWeekdayRepeat),
      teluguRule(teluguPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      teluguRule(teluguSpacedRepeatPattern, read: teluguSpacedRepeat),
      teluguRule(teluguAlternateRepeatPattern, read: teluguAlternateRepeat),
      teluguRule(teluguIntervalRepeatPattern, read: teluguIntervalRepeat),
      teluguRule(teluguOnceEveryPattern, read: teluguOnceEvery),
      teluguRule(teluguDailyWordPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      teluguRule(teluguCadenceAdjectivePattern, read: teluguCadenceAdjective),
    ]
  }

  // MARK: - Words

  /// "ప్రతి" or "ప్రతీ": every.
  static let teluguEvery = #"(?:ప్రతి|ప్రతీ)"#

  /// "ప్రతిరోజు", "ప్రతిరోజూ", "ప్రతి రోజు", "ప్రతీ రోజూ", or "రోజూ": every day.
  static let teluguEveryDayWords =
    #"(?:ప్రతి\s*రోజూ|ప్రతి\s*రోజు|ప్రతీ\s*రోజూ|ప్రతీ\s*రోజు|రోజూ)"#

  /// The words that may stand before a part of the day to make it every day's
  /// ("రోజూ ఉదయం", "ప్రతి సాయంత్రం"). The space inside "ప్రతి రోజు" is bounded
  /// because a lookbehind needs a bounded length.
  static let teluguEveryOrDaily =
    #"(?:ప్రతిరోజూ|ప్రతిరోజు|ప్రతి\s{1,3}రోజూ|ప్రతి\s{1,3}రోజు|ప్రతి|ప్రతీ|రోజూ)"#

  /// Whether the words around a span of weekdays make it a habit: "ప్రతి" before
  /// it ("ప్రతి ఆదివారం నుండి గురువారం వరకు") or the words for every day before or
  /// after it ("రోజూ సోమవారం నుండి శుక్రవారం వరకు", "సోమవారం నుండి శుక్రవారం
  /// వరకు ప్రతిరోజూ"). The date-range rules leave such a span to the repeat
  /// rules.
  static func teluguIsHabitSpan(_ match: Match) -> Bool {
    guard let range = Range(match.result.range, in: match.source) else { return false }
    let before = String(match.source[..<range.lowerBound])
    let after = String(match.source[range.upperBound...])
    return teluguFinds(#"\#(teluguStart)(?:\#(teluguEvery)|\#(teluguEveryDayWords))\s*$"#, in: before)
      || teluguFinds(#"^\s+\#(teluguEveryDayWords)\#(teluguEnd)"#, in: after)
  }

  /// The unit of an interval, by the stem of the word that names it.
  private enum TeluguUnit {
    case day, week, month, year
  }

  /// The unit a word names ("రోజులకు", "వారాలు", "నెలల", "సంవత్సరం", "ఏళ్లు",
  /// "ఏడాది", "ఏటా"), or nil for any other word.
  private static func teluguUnit(_ word: String) -> TeluguUnit? {
    let key = teluguKey(word)
    func names(_ stem: String) -> Bool { teluguHasPrefix(key, teluguKey(stem)) }
    if names("రోజ") { return .day }
    if names("వార") { return .week }
    if names("నెల") { return .month }
    if names("సంవత్సర") || names("ఏళ్") || names("ఏడాది") || names("ఏట") { return .year }
    return nil
  }

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func teluguRepeat(unit: String, every: Int?) -> Repeat? {
    switch teluguUnit(unit) {
    case .day: Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case .week: weekly(every: every, on: [])
    case .month: monthly(every: every, on: nil)
    case .year: Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    case nil: nil
    }
  }

  // MARK: - Weekdays

  /// A weekday as the repeat rules read it: the plain name ("సోమవారం",
  /// "సోమవారము") or the inclusive "సోమవారమూ", as a pattern without groups.
  private static var teluguWeekdayItem: String {
    #"(?:\#(teluguWeekdayStems))(?:ం|ము|మూ)"#
  }

  /// "ప్రతి ఆదివారం నుండి గురువారం వరకు", "సోమవారం నుండి శుక్రవారం వరకు ప్రతిరోజూ",
  /// "రోజూ సోమవారం నుండి శుక్రవారం": every day of a span of weekdays. Groups: 1
  /// the words for every day before the span, 2 "ప్రతి" before it, 3 the first
  /// weekday, 4 the last, 5 the words for every day after it.
  private static var teluguWeekdaySpanPattern: String {
    let item = teluguWeekdayItem
    return
      #"\#(teluguStart)(\#(teluguEveryDayWords)\s+)?(\#(teluguEvery)\s*)?(\#(item))\s+\#(teluguFromWords)\s+(\#(item))(?:\s+(?:వరకు|వరకూ|దాకా))?+\#(teluguEnd)(\s+\#(teluguEveryDayWords)\#(teluguEnd))?"#
  }

  /// A span runs from its first weekday to its last through the week's end. It
  /// is a habit only beside "ప్రతి" or the words for every day: without them
  /// ("సోమవారం నుండి శుక్రవారం వరకు") it may as well be a week of work, which the
  /// date-range rules leave unread. A span from a day to itself is no span.
  private static func teluguWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(3), let lastWord = match.group(4),
      let first = teluguWeekdayIndex(firstWord), let last = teluguWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(2) != nil || match.group(5) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// A lookbehind that fails after an amount, in digits or in words: "3
  /// వారాంతాల్లో" and "మూడు సోమవారాల్లో" count weekends and Mondays, which no
  /// repeat rule reads.
  private static var teluguNotCounted: String {
    #"(?<!\p{N}\s{0,3})(?<!(?:\#(teluguCountWords))\s{1,3})"#
  }

  /// "పనిరోజుల్లో", "పని దినాల్లో", "ప్రతి పనిరోజు", "రోజూ పని దినం": the working
  /// days, Monday to Friday. The noun phrases "పనిరోజు" and "పని దినం" with
  /// no ending are read only after "ప్రతి" or the words for every day: alone
  /// they name the days as often as they say on which of them a task repeats.
  /// An amount before the plural ("3 పనిరోజుల్లో") makes it a count of days.
  private static var teluguWorkdaysPattern: String {
    let day = #"పని\s*(?:రోజు|దినం|దినము)"#
    let plural = #"\#(teluguNotCounted)పని\s*(?:రోజుల్లో|రోజులలో|దినాల్లో|దినాలలో)"#
    return #"\#(teluguStart)(?:\#(teluguEveryOrDaily)\s*\#(day)|\#(plural))\#(teluguEnd)"#
  }

  /// "ప్రతి వారాంతం", "వారాంతాల్లో", "ప్రతి వీకెండ్", "శని ఆదివారాల్లో": Saturday
  /// and Sunday. An amount before the plural ("3 వారాంతాల్లో") makes it a count
  /// of weekends.
  private static var teluguWeekendRepeatPattern: String {
    let plural = #"\#(teluguNotCounted)(?:వారాంతాల్లో|వారాంతాలలో|శని\s*[,-]?\s*ఆదివారాల్లో|శని\s*[,-]?\s*ఆదివారాలలో)"#
    return #"\#(teluguStart)(?:\#(teluguEvery)\s*(?:వారాంత(?:ం|ము)|వీకెండ్)|\#(plural))\#(teluguEnd)"#
  }

  /// "ప్రతి సోమవారం", "ప్రతి సోమవారం మరియు గురువారం", "ప్రతి సోమవారం, బుధవారం,
  /// శుక్రవారం", "సోమవారాల్లో", "ప్రతి వారం సోమవారం", "సోమవారం ప్రతి వారం".
  /// Groups: 1 the weekdays after "ప్రతి", 2 the weekdays after "ప్రతి వారం", 3
  /// the weekdays before "ప్రతి వారం", 4 the weekdays in the plural ("సోమవారాల్లో").
  private static var teluguWeekdayRepeatPattern: String {
    let item = teluguWeekdayItem
    let separator = #"(?:\s*,\s*(?:(?:మరియు|&)\s+)?|\s+(?:మరియు|&)\s+|\s*&\s*)"#
    let list = #"\#(item)(?:\#(separator)(?:\#(teluguEvery)\s*)?\#(item)){0,6}"#
    let pluralItem = #"(?:\#(teluguWeekdayStems))ా(?:ల్లో|లలో)"#
    let plural = #"\#(pluralItem)(?:\#(separator)\#(pluralItem)){0,6}"#
    let everyWeek = #"\#(teluguEvery)\s*(?:వారం|వారమూ)"#
    let every = #"\#(teluguEvery)\s*(\#(list))"#
    let afterWeek = #"\#(everyWeek)\s+(\#(list))"#
    let beforeWeek = #"(\#(list))\s+\#(everyWeek)"#
    return
      #"\#(teluguStart)(?:\#(every)|\#(afterWeek)|\#(beforeWeek)|\#(teluguNotCounted)(\#(plural)))\#(teluguEnd)"#
  }

  private static func teluguWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) ?? ""
    let days = teluguWords(in: list).compactMap(teluguWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "ప్రతి నెల 5వ తేదీన", "ప్రతి నెల 5న", "ప్రతి నెలా 5న", "ప్రతి నెల మొదటి
  /// తేదీన", "5వ తేదీన ప్రతి నెల". Groups: 1 the day with "తేదీ" after "ప్రతి
  /// నెల", 2 the day with "న" after it, 3 the day before "ప్రతి నెల", each in
  /// digits or as "మొదటి".
  private static var teluguMonthDayRepeatPattern: String {
    let month = #"\#(teluguEvery)\s*నెల(?:ా|లో)?"#
    let dateWord = #"\s*(?:తేదీ|తేది)"#
    let forward = #"\#(month)\s+(\d{1,2}|మొదటి)(?:వ)?\#(dateWord)(?:·(?:న|కి|కు))?"#
    let forwardOn = #"\#(month)\s+(\d{1,2})·న"#
    let reverse = #"(\d{1,2}|మొదటి)(?:వ)?\#(dateWord)(?:·న)?\s+\#(teluguEvery)\s*నెలా?"#
    return #"\#(teluguStart)(?:\#(forward)|\#(forwardOn)|\#(reverse))\#(teluguEnd)"#
  }

  private static func teluguMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = (match.group(1) ?? match.group(2) ?? match.group(3)).map(teluguPhrase) else { return nil }
    guard let day = text == teluguKey("మొదటి") ? 1 : number(text) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// The unit words of an interval, in the forms they take after a count and
  /// "ప్రతి": days, weeks, months, and years, plural or singular, with the
  /// dative of the plural ("ప్రతి 2 రోజులకు") or without it.
  private static let teluguUnits = teluguAlternation(of: [
    "రోజులకు", "రోజులకి", "రోజులు", "రోజుల", "రోజూ", "రోజు", "వారాలకు", "వారాలకి", "వారాలు", "వారాల", "వారమూ", "వారం",
    "నెలలకు", "నెలలకి", "నెలలు", "నెలల", "నెలా", "నెల", "సంవత్సరాలకు", "సంవత్సరాలకి", "సంవత్సరాలు", "సంవత్సరాల",
    "సంవత్సరమూ", "సంవత్సరం", "ఏళ్లకు", "ఏళ్ళకు", "ఏళ్లు", "ఏళ్ళు", "ఏళ్ల", "ఏళ్ళ", "ఏడాదికి", "ఏడాది", "ఏటా",
  ])

  /// "ప్రతి రోజు", "ప్రతి వారం", "ప్రతి నెల", "ప్రతి సంవత్సరం", "ప్రతి ఏడాది", "ప్రతి
  /// ఏటా", "ప్రతి 2 రోజులకు", "ప్రతి రెండు వారాలు", "ప్రతి 3 నెలలకు", "ప్రతి 5
  /// సంవత్సరాలు", "ప్రతి పదిహేను రోజులకు", "ప్రతి రెండో రోజు" (every other day).
  /// An interval shorter than a day ("ప్రతి 2 గంటలకు") is no repeat. Groups: 1
  /// the count, 2 "రెండవ" or "రెండో" (every other), 3 the unit. The unit is
  /// the end of the phrase, so a genitive glued to it ("ప్రతి నెల
  /// ఖర్చుల") is another word.
  private static var teluguIntervalRepeatPattern: String {
    #"\#(teluguStart)\#(teluguEvery)\s*(?:(\d{1,2}|\#(teluguRoundCountWords))\s*|(రెండవ|రెండో)\s+)?(\#(teluguUnits))\#(teluguEnd)"#
  }

  private static func teluguIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(3) else { return nil }
    var count = 1
    if match.group(2) != nil {
      count = 2
    } else if let text = match.group(1) {
      guard let value = number(text) ?? teluguRoundCounts[teluguCompactKey(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    return teluguRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// The words for "once" after an interval: "ఒకసారి", "ఒక్కసారి", "ఒక సారి".
  private static let teluguOnce = #"(?:ఒకసారి|ఒక్కసారి|ఒక\s+సారి)"#

  /// "2 రోజులకు ఒకసారి", "3 నెలలకోసారి", "రెండు వారాలకొకసారి", "ప్రతి 2 రోజులకు
  /// ఒకసారి": an amount of days, weeks, months, or years with "ఒకసారి" or
  /// "కోసారి" after the unit. A count of one is every one ("1 రోజుకోసారి"). Groups:
  /// 1 the count, 2 the unit.
  private static var teluguSpacedRepeatPattern: String {
    let units = "రోజుల|రోజు|వారాల|వారాని|నెలల|నెల|సంవత్సరాల|సంవత్సరాని|ఏళ్ల|ఏళ్ళ|ఏడాది"
    return
      #"\#(teluguStart)(?:\#(teluguEvery)\s*)?(\d{1,2}|\#(teluguRoundCountWords))\s*(\#(units))(?:(?:కు|కి)\s+\#(teluguOnce)|(?:కో|కొక)సారి)\#(teluguEnd)"#
  }

  private static func teluguSpacedRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1), let unit = match.group(2),
      let count = number(countText) ?? teluguRoundCounts[teluguCompactKey(countText)], (1...99).contains(count)
    else { return nil }
    return teluguRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "రోజు విడిచి రోజు", "వారం తప్పించి వారం", "ఒక నెల విడిచి ఒక నెల": every
  /// other day, week, or month. Group 1: the unit.
  private static var teluguAlternateRepeatPattern: String {
    #"\#(teluguStart)(?:ఒక\s+)?(రోజు|వారం|నెల)\s+(?:విడిచి|తప్పించి)\s+(?:ఒక\s+)?\1\#(teluguEnd)"#
  }

  private static func teluguAlternateRepeat(_ match: Match) -> Repeat? {
    match.group(1).flatMap { teluguRepeat(unit: $0, every: 2) }
  }

  /// "రోజుకు ఒకసారి", "వారానికి ఒకసారి", "నెలకు ఒకసారి", "సంవత్సరానికి ఒకసారి",
  /// "ఏడాదికి ఒకసారి", "రోజుకోసారి", "వారానికోసారి", "నెలకోసారి", each maybe with
  /// "కేవలం" or "మాత్రమే" before "ఒకసారి". Group 1: the unit.
  private static var teluguOnceEveryPattern: String {
    #"\#(teluguStart)(రోజు|వారాని|నెల|సంవత్సరాని|ఏడాది)(?:(?:కు|కి)\s+(?:(?:కేవలం|మాత్రమే)\s+)?\#(teluguOnce)|(?:కో|కొక)సారి)\#(teluguEnd)"#
  }

  private static func teluguOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).flatMap { teluguRepeat(unit: $0, every: nil) }
  }

  // MARK: - Parts of the day and daily words

  /// "ప్రతి ఉదయం", "రోజూ రాత్రి", "ప్రతి సాయంత్రం", "ప్రతిరోజు ఉదయాన్నే": every
  /// day.
  private static var teluguPartOfDayRepeatPattern: String {
    #"\#(teluguStart)\#(teluguEveryOrDaily)\s+(?:\#(teluguDayPartWords))\#(teluguEnd)"#
  }

  /// "ప్రతిరోజు", "ప్రతి రోజు", "ప్రతిరోజూ", "రోజూ": every day. They say how a
  /// task repeats, and an ending glued to them ("రోజూవారీ") makes them another
  /// word, which the pattern does not list.
  private static var teluguDailyWordPattern: String {
    #"\#(teluguStart)\#(teluguEveryDayWords)\#(teluguEnd)"#
  }

  /// "రోజువారీ", "వారంవారీ", "నెలవారీ", "సంవత్సరంవారీ": how a task repeats, only at
  /// the end of the line, before a colon or comma, with "ప్రాతిపదికన" after it,
  /// or with "గా" glued to it. They are ordinary adjectives too ("రోజువారీ
  /// రిపోర్ట్" is a daily report), and the end of the line is where they say how
  /// a task repeats. Group 1: the adjective.
  private static var teluguCadenceAdjectivePattern: String {
    #"\#(teluguStart)(రోజువారీ|రోజూవారీ|వారం\s*వారీ|నెలవారీ|సంవత్సరం\s*వారీ|ఏడాదివారీ)(?:గా|\s+ప్రాతిపదికన|\s+ప్రాతిపదిక|(?=\s*[:：,，])|(?=\s*[.!।]?\s*$))\#(teluguEnd)"#
  }

  private static func teluguCadenceAdjective(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(teluguCompactKey) else { return nil }
    switch word {
    case teluguCompactKey("రోజువారీ"), teluguCompactKey("రోజూవారీ"): return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case teluguCompactKey("వారంవారీ"): return weekly(every: nil, on: [])
    case teluguCompactKey("నెలవారీ"): return monthly(every: nil, on: nil)
    case teluguCompactKey("సంవత్సరంవారీ"), teluguCompactKey("ఏడాదివారీ"):
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: return nil
    }
  }
}
