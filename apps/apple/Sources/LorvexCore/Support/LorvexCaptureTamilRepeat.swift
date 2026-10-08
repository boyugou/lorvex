import Foundation

extension LorvexCaptureVocabulary {
  // The Tamil repeat rules. The vocabulary's other words are in ``tamil``.

  /// The repeat rules, in the order they are tried: a span of weekdays beside
  /// "ஒவ்வொரு" or the words for every day, the working days, the weekend, and a
  /// day of the month before the weekdays and every day and every month, which
  /// would leave "திங்கள்" or the day's number in the title; then the weekdays,
  /// a part of the day, an amount of days with "ஒருமுறை" or every other day
  /// ("நாள் விட்டு நாள்") before the plain interval, which would leave the
  /// "ஒருமுறை" of "3 மாதங்களுக்கு ஒருமுறை" in the title, "once a week", the
  /// weekly, monthly, and yearly words ("வாரந்தோறும்"), the words for every day,
  /// and the adjectives that say how a task repeats.
  static var tamilRepeatRules: [Rule<Repeat>] {
    [
      tamilRule(tamilWeekdaySpanPattern, read: tamilWeekdaySpanRepeat),
      tamilRule(tamilWorkdaysPattern) { _ in workdays },
      tamilRule(tamilWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      tamilRule(tamilMonthDayRepeatPattern, read: tamilMonthDayRepeat),
      tamilRule(tamilWeekdayRepeatPattern, read: tamilWeekdayRepeat),
      tamilRule(tamilPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      tamilRule(tamilSpacedRepeatPattern, read: tamilSpacedRepeat),
      tamilRule(tamilAlternateRepeatPattern, read: tamilAlternateRepeat),
      tamilRule(tamilIntervalRepeatPattern, read: tamilIntervalRepeat),
      tamilRule(tamilOnceEveryPattern, read: tamilOnceEvery),
      tamilRule(tamilUnitWordPattern, read: tamilUnitWord),
      tamilRule(tamilDailyWordPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      tamilRule(tamilCadenceAdjectivePattern, read: tamilCadenceAdjective),
    ]
  }

  // MARK: - Words

  /// "ஒவ்வொரு": every.
  static let tamilEvery = #"ஒவ்வொரு"#

  /// "தினமும்", "தினந்தோறும்", "தினம் தோறும்", "நாள்தோறும்", "ஒவ்வொரு நாளும்",
  /// or "ஒவ்வொரு நாள்": every day.
  static let tamilEveryDayWords =
    #"(?:தினந்தோறும்|தினம்\s*தோறும்|தினமும்|நாள்\s*தோறும்|ஒவ்வொரு\s*நாளும்|ஒவ்வொரு\s*நாள்)"#

  /// The words that may stand before a part of the day to make it every day's
  /// ("தினமும் காலை", "ஒவ்வொரு மாலை"), "தினசரி" among them. The spaces inside
  /// them are bounded because a lookbehind needs a bounded length.
  static let tamilEveryOrDaily =
    #"(?:தினந்தோறும்|தினம்\s{0,3}தோறும்|தினமும்|தினசரி|நாள்\s{0,3}தோறும்|ஒவ்வொரு\s{1,3}நாளும்|ஒவ்வொரு)"#

  /// Whether the words around a span of weekdays make it a habit: "ஒவ்வொரு" before
  /// it ("ஒவ்வொரு திங்கள் முதல் வெள்ளி வரை") or the words for every day before or
  /// after it ("தினமும் திங்கள் முதல் வெள்ளி வரை", "திங்கள் முதல் வெள்ளி வரை
  /// தினமும்"). The date-range rules leave such a span to the repeat rules.
  static func tamilIsHabitSpan(_ match: Match) -> Bool {
    guard let range = Range(match.result.range, in: match.source) else { return false }
    let before = String(match.source[..<range.lowerBound])
    let after = String(match.source[range.upperBound...])
    return tamilFinds(#"\#(tamilStart)(?:\#(tamilEvery)|\#(tamilEveryDayWords))\s*$"#, in: before)
      || tamilFinds(#"^\s+\#(tamilEveryDayWords)\#(tamilEnd)"#, in: after)
  }

  /// The unit of an interval, by the stem of the word that names it.
  private enum TamilUnit {
    case day, week, month, year
  }

  /// The unit a word names ("நாட்களுக்கு", "வாரங்கள்", "மாதத்திற்கு",
  /// "வருடம்", "ஆண்டுகள்"), or nil for any other word.
  private static func tamilUnit(_ word: String) -> TamilUnit? {
    let key = tamilKey(word)
    func names(_ stem: String) -> Bool { tamilHasPrefix(key, tamilKey(stem)) }
    if names("நாள") || names("நாட்") || names("தின") { return .day }
    if names("வார") { return .week }
    if names("மாத") { return .month }
    if names("வருட") || names("ஆண்ட") { return .year }
    return nil
  }

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years.
  private static func tamilRepeat(unit: String, every: Int?) -> Repeat? {
    switch tamilUnit(unit) {
    case .day: Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case .week: weekly(every: every, on: [])
    case .month: monthly(every: every, on: nil)
    case .year: Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    case nil: nil
    }
  }

  // MARK: - Weekdays

  /// A weekday as the repeat rules read it, as a pattern without groups: the
  /// long name ("திங்கட்கிழமை") or the bare name ("திங்கள்"), maybe with the
  /// inclusive ending "-உம்" ("திங்கட்கிழமையும்", "திங்களும்").
  private static var tamilRepeatWeekdayItem: String {
    #"(?:(?:\#(tamilWeekdayLong))(?:யும்)?|(?:\#(tamilWeekdayBareInclusive)|\#(tamilWeekdayNames))\#(tamilNotPlanet))"#
  }

  /// A weekday with the inclusive ending "-உம்", as a pattern without groups:
  /// "திங்கட்கிழமையும்", "திங்களும்", "வெள்ளியும்". Items with it follow each
  /// other with no word between ("திங்களும் புதனும்").
  private static var tamilInclusiveWeekdayItem: String {
    #"(?:(?:\#(tamilWeekdayLong))யும்|(?:\#(tamilWeekdayBareInclusive))\#(tamilNotPlanet))"#
  }

  /// "ஒவ்வொரு ஞாயிறு முதல் வியாழன் வரை", "திங்கள் முதல் வெள்ளி வரை தினமும்",
  /// "தினமும் திங்கள் முதல் வெள்ளி": every day of a span of weekdays. Groups: 1
  /// the words for every day before the span, 2 "ஒவ்வொரு" before it, 3 the first
  /// weekday, 4 the last, 5 the words for every day after it.
  private static var tamilWeekdaySpanPattern: String {
    let item = tamilRepeatWeekdayItem
    return
      #"\#(tamilStart)(\#(tamilEveryDayWords)\s+)?(\#(tamilEvery)\s+)?(\#(item))\s+முதல்\s+(\#(item))(?:\s+(?:வரைக்கும்|வரையில்|வரை))?+\#(tamilEnd)(\s+\#(tamilEveryDayWords)\#(tamilEnd))?"#
  }

  /// A span runs from its first weekday to its last through the week's end. It
  /// is a habit only beside "ஒவ்வொரு" or the words for every day: without them
  /// ("திங்கள் முதல் வெள்ளி வரை") it may as well be a week of work, which the
  /// date-range rules leave unread. A span from a day to itself is no span.
  private static func tamilWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(3), let lastWord = match.group(4),
      let first = tamilWeekdayIndex(firstWord), let last = tamilWeekdayIndex(lastWord), first != last,
      match.group(1) != nil || match.group(2) != nil || match.group(5) != nil
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// A lookbehind that fails after an amount, in digits or in words: "3 வார
  /// இறுதிகளில்" and "மூன்று திங்கட்கிழமைகளில்" count weekends and Mondays,
  /// which no repeat rule reads.
  private static var tamilNotCounted: String {
    #"(?<!\p{N}\s{0,3})(?<!(?:\#(tamilCountWords))\s{1,3})"#
  }

  /// "வேலை நாட்களில்", "வார நாட்களில்", "ஒவ்வொரு வேலை நாளும்", "தினமும் வார
  /// நாட்களில்": the working days, Monday to Friday. The singular noun phrases
  /// are read only after "ஒவ்வொரு" or the words for every day, since alone they
  /// name the days as often as they say on which of them a task repeats. An
  /// amount before the plural ("3 வேலை நாட்களில்") makes it a count of days.
  private static var tamilWorkdaysPattern: String {
    let day = #"(?:வேலை|வார)\s*நாள(?:்|ும்)"#
    let plural = #"\#(tamilNotCounted)(?:தினமும்\s+)?(?:வேலை|வார)\s*நாட்கள(?:ில்|ிலும்)"#
    return #"\#(tamilStart)(?:(?:\#(tamilEvery)|தினமும்|தினந்தோறும்)\s+\#(day)|\#(plural))\#(tamilEnd)"#
  }

  /// "ஒவ்வொரு வார இறுதியும்", "வார இறுதிகளில்", "ஒவ்வொரு வீக்கெண்டும்", "சனி
  /// ஞாயிறுகளில்": Saturday and Sunday. An amount before the plural ("3 வார
  /// இறுதிகளில்") makes it a count of weekends.
  private static var tamilWeekendRepeatPattern: String {
    let base = #"(?:வார\s*இறுதி|வாரயிறுதி|வாரஇறுதி)"#
    let every =
      #"\#(tamilEvery)\s+(?:\#(base)(?:யும்|யிலும்|யில்)?|வீக்கெண்ட(?:்|ும்|ில்|ிலும்))|\#(base)தோறும்"#
    let sunday = #"(?:ஞாயிறு(?:கள(?:ில்|ிலும்))|(?:ஞாயிற்று|ஞாயிறு)(?:க்)?\s*கிழமைகள(?:ில்|ிலும்))"#
    let plural =
      #"\#(tamilNotCounted)(?:\#(base)(?:கள(?:ில்|ிலும்)|\s*நாட்கள(?:ில்|ிலும்))|சனி(?:க்)?(?:\s*கிழமை)?\s*[,-]?\s*(?:மற்றும்\s+)?\#(sunday))"#
    return #"\#(tamilStart)(?:\#(every)|\#(plural))\#(tamilEnd)"#
  }

  /// "ஒவ்வொரு திங்கட்கிழமை", "ஒவ்வொரு திங்கட்கிழமையும்", "ஒவ்வொரு திங்கள்,
  /// புதன்", "திங்களும் புதனும் ஒவ்வொரு வாரமும்", "ஒவ்வொரு வாரமும் திங்கள்",
  /// "திங்கள்தோறும்", "திங்கட்கிழமைகளில்". The names of a list stand apart by a
  /// comma, "மற்றும்", "&", or a space ("ஒவ்வொரு திங்கள் புதன் வெள்ளி"). Groups:
  /// 1 the weekdays after "ஒவ்வொரு", 2 the weekdays after "ஒவ்வொரு வாரமும்", 3
  /// the weekdays before it, 4 the weekday before "தோறும்", 5 the weekdays in
  /// the plural.
  private static var tamilWeekdayRepeatPattern: String {
    let item = tamilRepeatWeekdayItem
    let separator = #"(?:\s*,\s*(?:(?:மற்றும்|&)\s+)?|\s+(?:மற்றும்|&)\s+|\s*&\s*|\s+)"#
    let plainList =
      #"\#(item)(?:\#(separator)(?:\#(tamilEvery)\s+)?\#(item)){0,6}"#
    let inclusive = tamilInclusiveWeekdayItem
    let inclusiveList = #"\#(inclusive)(?:\s+\#(inclusive)){0,6}"#
    let list = #"(?:\#(inclusiveList)|\#(plainList))"#
    let pluralItem = #"(?:\#(tamilWeekdayStems))(?:க்)?\s*கிழமைகள(?:ில்|ிலும்)"#
    let plural = #"(?:\#(item)\#(separator))*\#(pluralItem)(?:\#(separator)\#(pluralItem)){0,6}"#
    let everyWeek = #"(?:\#(tamilEvery)\s+வாரமும்|\#(tamilEvery)\s+வாரம்|வாரந்தோறும்|வாரம்\s*தோறும்)"#
    let every = #"\#(tamilEvery)\s+(\#(list))"#
    let afterWeek = #"\#(everyWeek)\s+(\#(list))"#
    let beforeWeek = #"(\#(list))\s+\#(everyWeek)"#
    let perWeek = #"(\#(item))தோறும்"#
    return
      #"\#(tamilStart)(?:\#(every)|\#(afterWeek)|\#(beforeWeek)|\#(perWeek)|\#(tamilNotCounted)(\#(plural)))\#(tamilEnd)"#
  }

  private static func tamilWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) ?? match.group(5) ?? ""
    let days = tamilWords(in: list).compactMap(tamilWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "ஒவ்வொரு மாதமும் 5ஆம் தேதி", "ஒவ்வொரு மாதம் 5ஆம் தேதியில்", "மாதந்தோறும்
  /// முதல் தேதி", "5ஆம் தேதி ஒவ்வொரு மாதமும்". Groups: 1 the day after the month
  /// word, 2 the day before it, each in digits or as "முதல்".
  private static var tamilMonthDayRepeatPattern: String {
    let month = #"(?:ஒவ்வொரு\s+மாதமும்|ஒவ்வொரு\s+மாதம்|மாதந்தோறும்|மாதம்\s*தோறும்)"#
    let day =
      #"(\d{1,2}|முதல்)(?:\s*-?\s*(?:ஆம்|ஆவது|வது|ம்))?\s*தேதி(?:யில்|யன்று|க்கு\#(tamilSandhi)|அன்று)?"#
    let reverse =
      #"(\d{1,2}|முதல்)(?:\s*-?\s*(?:ஆம்|ஆவது|வது|ம்))?\s*தேதி(?:யில்|யன்று|க்கு\#(tamilSandhi))?\s+\#(month)"#
    return #"\#(tamilStart)(?:\#(month)\s+\#(day)|\#(reverse))\#(tamilEnd)"#
  }

  private static func tamilMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = (match.group(1) ?? match.group(2)).map(tamilPhrase) else { return nil }
    guard let day = text == tamilKey("முதல்") ? 1 : number(text) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// The unit words of an interval, in the forms they take after a count and
  /// "ஒவ்வொரு": days, weeks, months, and years, plural or singular, with the
  /// distributive ending ("ஒவ்வொரு 2 நாட்களுக்கும்", "ஒவ்வொரு வாரமும்") or
  /// without it.
  private static let tamilIntervalUnits = tamilAlternation(of: [
    "நாட்களுக்கும்", "நாட்களுக்கு", "நாட்களும்", "நாட்கள்", "நாளுக்கும்", "நாளுக்கு", "நாளும்", "நாள்", "வாரங்களுக்கும்",
    "வாரங்களுக்கு", "வாரங்களும்", "வாரங்கள்", "வாரத்திற்கும்", "வாரத்துக்கும்", "வாரத்திற்கு", "வாரத்துக்கு", "வாரமும்",
    "வாரம்", "மாதங்களுக்கும்", "மாதங்களுக்கு", "மாதங்களும்", "மாதங்கள்", "மாதத்திற்கும்", "மாதத்துக்கும்",
    "மாதத்திற்கு", "மாதத்துக்கு", "மாதமும்", "மாதம்", "வருடங்களுக்கும்", "வருடங்களுக்கு", "வருடங்களும்", "வருடங்கள்",
    "வருடத்திற்கும்", "வருடத்துக்கும்", "வருடத்திற்கு", "வருடத்துக்கு", "வருடமும்", "வருடம்", "ஆண்டுகளுக்கும்",
    "ஆண்டுகளுக்கு", "ஆண்டுகளும்", "ஆண்டுகள்", "ஆண்டுக்கும்", "ஆண்டுக்கு", "ஆண்டும்", "ஆண்டு",
  ])

  /// "ஒவ்வொரு நாளும்", "ஒவ்வொரு வாரம்", "ஒவ்வொரு மாதமும்", "ஒவ்வொரு வருடமும்",
  /// "ஒவ்வொரு 2 நாட்களுக்கும்", "ஒவ்வொரு இரண்டு வாரங்களுக்கும்", "ஒவ்வொரு 3
  /// மாதங்களுக்கும்", "ஒவ்வொரு பதினைந்து நாட்களுக்கும்", "ஒவ்வொரு இரண்டாவது
  /// நாளும்" (every other day). An interval shorter than a day ("ஒவ்வொரு 2 மணி
  /// நேரத்திற்கும்") is no repeat. Groups: 1 the count, 2 "இரண்டாவது" or
  /// "இரண்டாம்" (every other), 3 the unit. The unit is the end of the phrase, so
  /// a genitive glued to it ("ஒவ்வொரு மாதத்தின்") is another word.
  private static var tamilIntervalRepeatPattern: String {
    #"\#(tamilStart)\#(tamilEvery)\s+(?:(\d{1,2}|\#(tamilRoundCountWords))\s*|(இரண்டாவது|இரண்டாம்)\s+)?(\#(tamilIntervalUnits))\#(tamilEnd)"#
  }

  private static func tamilIntervalRepeat(_ match: Match) -> Repeat? {
    guard let unit = match.group(3) else { return nil }
    var count = 1
    if match.group(2) != nil {
      count = 2
    } else if let text = match.group(1) {
      guard let value = number(text) ?? tamilRoundCounts[tamilCompactKey(text)] else { return nil }
      count = value
    }
    guard (1...99).contains(count) else { return nil }
    return tamilRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// The words for "once" after an interval: "ஒருமுறை", "ஒரு முறை",
  /// "ஒருதடவை", "ஒரு தடவை".
  private static let tamilOnce = #"(?:ஒருமுறை|ஒரு\s*முறை|ஒருதடவை|ஒரு\s*தடவை)"#

  /// "2 நாட்களுக்கு ஒருமுறை", "3 மாதங்களுக்கு ஒரு முறை", "இரண்டு வாரங்களுக்கு
  /// ஒருமுறை", "ஒவ்வொரு 2 நாட்களுக்கு ஒருமுறை", "இரு வாரத்திற்கு ஒருமுறை": an
  /// amount of days, weeks, months, or years with its dative and "ஒருமுறை"
  /// after it. A count of one is every one ("1 நாளுக்கு ஒருமுறை"). Groups: 1 the
  /// count, 2 the unit.
  private static var tamilSpacedRepeatPattern: String {
    let units = tamilAlternation(of: [
      "நாட்களுக்கு", "நாளுக்கு", "வாரங்களுக்கு", "வாரத்திற்கு", "வாரத்துக்கு", "மாதங்களுக்கு", "மாதத்திற்கு",
      "மாதத்துக்கு", "வருடங்களுக்கு", "வருடத்திற்கு", "வருடத்துக்கு", "ஆண்டுகளுக்கு", "ஆண்டுக்கு",
    ])
    return
      #"\#(tamilStart)(?:\#(tamilEvery)\s+)?(\d{1,2}|\#(tamilRoundCountWords))\s*(\#(units))\s+\#(tamilOnce)\#(tamilEnd)"#
  }

  private static func tamilSpacedRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1), let unit = match.group(2),
      let count = number(countText) ?? tamilRoundCounts[tamilCompactKey(countText)], (1...99).contains(count)
    else { return nil }
    return tamilRepeat(unit: unit, every: count == 1 ? nil : count)
  }

  /// "நாள் விட்டு நாள்", "வாரம் விட்டு வாரம்", "ஒரு மாதம் விட்டு ஒரு மாதம்",
  /// "ஒருநாள் விட்டு ஒருநாள்": every other day, week, or month. Group 1: the
  /// unit.
  private static var tamilAlternateRepeatPattern: String {
    #"\#(tamilStart)(?:ஒரு\s*)?(நாள்|வாரம்|மாதம்)\s+விட்டு\s+(?:ஒரு\s*)?\1\#(tamilEnd)"#
  }

  private static func tamilAlternateRepeat(_ match: Match) -> Repeat? {
    match.group(1).flatMap { tamilRepeat(unit: $0, every: 2) }
  }

  /// "நாளுக்கு ஒருமுறை", "தினம் ஒருமுறை", "வாரத்திற்கு ஒருமுறை", "வாரம் ஒரு
  /// முறை", "மாதத்துக்கு ஒருமுறை", "மாதம் ஒருமுறை", "வருடத்திற்கு ஒருமுறை",
  /// "ஆண்டுக்கு ஒருமுறை". Group 1: the unit.
  private static var tamilOnceEveryPattern: String {
    let units = tamilAlternation(of: [
      "நாளுக்கு", "தினமும்", "தினம்", "வாரத்திற்கு", "வாரத்துக்கு", "வாரம்", "மாதத்திற்கு", "மாதத்துக்கு", "மாதம்",
      "வருடத்திற்கு", "வருடத்துக்கு", "வருடம்", "ஆண்டுக்கு", "ஆண்டு",
    ])
    return #"\#(tamilStart)(\#(units))\s+\#(tamilOnce)\#(tamilEnd)"#
  }

  private static func tamilOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).flatMap { tamilRepeat(unit: $0, every: nil) }
  }

  // MARK: - Parts of the day and daily words

  /// "தினமும் காலை", "ஒவ்வொரு இரவும்", "தினசரி மாலை", "தினந்தோறும் காலையில்",
  /// "ஒவ்வொரு காலை": every day.
  private static var tamilPartOfDayRepeatPattern: String {
    #"\#(tamilStart)\#(tamilEveryOrDaily)\s+(?:\#(tamilDayPartWords)|\#(tamilPartInclusiveWords))\#(tamilEnd)"#
  }

  /// "வாரந்தோறும்", "மாதந்தோறும்", "வருடந்தோறும்", "ஆண்டுதோறும்", and the forms
  /// with a space before "தோறும்": every week, month, or year, the names the
  /// app writes for the frequencies. An ending glued to them makes them another
  /// word, which the pattern does not list. Group 1: the word.
  private static var tamilUnitWordPattern: String {
    #"\#(tamilStart)((?:வாரம்|மாதம்|வருடம்|ஆண்டு)\s*தோறும்|(?:வார|மாத|வருட)ந்தோறும்)\#(tamilEnd)"#
  }

  private static func tamilUnitWord(_ match: Match) -> Repeat? {
    match.group(1).flatMap { tamilRepeat(unit: $0, every: nil) }
  }

  /// "தினமும்", "தினந்தோறும்", "நாள்தோறும்", "ஒவ்வொரு நாளும்": every day. They
  /// say how a task repeats, and an ending glued to them makes them another
  /// word, which the pattern does not list.
  private static var tamilDailyWordPattern: String {
    #"\#(tamilStart)\#(tamilEveryDayWords)\#(tamilEnd)"#
  }

  /// "தினசரி", "வாராந்திர", "மாதாந்திர", "வருடாந்திர": how a task repeats, only at
  /// the end of the line, before a colon or comma, or with "அடிப்படையில்" after
  /// it. They are ordinary adjectives too ("வாராந்திர அறிக்கை" is a weekly
  /// report), and the end of the line is where they say how a task repeats.
  /// Group 1: the adjective.
  private static var tamilCadenceAdjectivePattern: String {
    #"\#(tamilStart)(தினசரி|வாராந்திர|வாராந்தர|மாதாந்திர|மாதாந்தர|வருடாந்திர|வருடாந்தர)(?:\s+அடிப்படையில்|(?=\s*[:：,，])|(?=\s*[.!।]?\s*$))\#(tamilEnd)"#
  }

  private static func tamilCadenceAdjective(_ match: Match) -> Repeat? {
    guard let word = match.group(1).map(tamilCompactKey) else { return nil }
    switch word {
    case tamilCompactKey("தினசரி"): return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case tamilCompactKey("வாராந்திர"), tamilCompactKey("வாராந்தர"): return weekly(every: nil, on: [])
    case tamilCompactKey("மாதாந்திர"), tamilCompactKey("மாதாந்தர"): return monthly(every: nil, on: nil)
    case tamilCompactKey("வருடாந்திர"), tamilCompactKey("வருடாந்தர"):
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: return nil
    }
  }
}
