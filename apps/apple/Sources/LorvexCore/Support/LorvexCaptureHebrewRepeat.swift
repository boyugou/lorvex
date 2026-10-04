import Foundation

extension LorvexCaptureVocabulary {
  // The Hebrew repeat rules. The vocabulary's other words are in ``hebrew``.

  /// The repeat rules, in the order they are tried: a span of weekdays after
  /// "כל" or "בימי", the weekend, and a day of the month before the weekdays and
  /// every day and every month, which would leave the weekday or the day's
  /// number in the title; then the weekdays, a part of the day (before the
  /// interval, so "כל יום בבוקר" takes its "בבוקר"), an interval, "once a
  /// week", "a day yes, a day no", and "on a weekly basis".
  static var hebrewRepeatRules: [Rule<Repeat>] {
    [
      hebrewRule(hebrewWeekdaySpanPattern, read: hebrewWeekdaySpanRepeat),
      hebrewRule(hebrewWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
      hebrewRule(hebrewMonthDayRepeatPattern, read: hebrewMonthDayRepeat),
      hebrewRule(hebrewWeekdayRepeatPattern, read: hebrewWeekdayRepeat),
      hebrewRule(hebrewPartOfDayRepeatPattern) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      hebrewRule(hebrewIntervalRepeatPattern, read: hebrewIntervalRepeat),
      hebrewRule(hebrewOnceEveryPattern, read: hebrewOnceEvery),
      hebrewRule(hebrewAlternatingPattern, read: hebrewAlternatingRepeat),
      hebrewRule(hebrewBasisPattern, read: hebrewBasisRepeat),
    ]
  }

  // MARK: - Words

  /// "כל", "בכל", and "מדי", the words for "every", as a pattern without groups.
  private static let hebrewEvery = #"(?:כל|בכל|מדי)"#

  /// Whether "כל" stands just before a span of weekdays ("כל יום ראשון עד
  /// חמישי"), which makes the span a habit. The date-range rules leave such a
  /// span to the repeat rules.
  static func hebrewIsHabitSpan(_ match: Match) -> Bool {
    hebrewFinds(#"\#(hebrewStart)\#(hebrewEvery)\s+$"#, in: hebrewTextBefore(match))
  }

  /// The words that make a day a working day, as a pattern without groups: "כל
  /// יום עבודה", "בימי עבודה", "ימי חול". The working week is Sunday to Thursday in
  /// Israel and Monday to Friday elsewhere, and a repeat holds only one of them,
  /// so these phrases are not read. They stay in the title whole, which also
  /// keeps "כל יום" from being read alone as every day with "עבודה" left behind.
  static let hebrewWorkdaysPattern =
    #"\#(hebrewStart)(?:\#(hebrewEvery)\s+יום\s+(?:ה)?(?:עבודה|חול)|ב?ימי\s+(?:ה)?(?:עבודה|חול))\#(hebrewEnd)"#

  /// What may not follow a singular "יום" in a pattern for a unit: a weekday
  /// name ("כל יום שני" is Mondays and "פעם ביום ראשון" is no daily repeat), or
  /// a noun that "יום" forms a compound with, which makes it a particular day
  /// and no unit ("כל יום הולדת", "פעם ביום החג").
  private static let hebrewNoDayNameAfter =
    #"(?!\s+(?:\#(hebrewRepeatNames)|ה?(?:הולדת|חג|חופש|חופשה|עיון|כיף|מנוחה|לימודים|נישואין|גיבוש|בחירות|זיכרון|עצמאות|שואה|כיפור|כיפורים|אהבה|אישה|אם|אב|משפחה|ילד|ילדה)|טוב)\#(hebrewEnd))"#

  /// The units of an interval, as a pattern with four groups: the count (digits
  /// or a word), the plural unit after it, the dual unit ("יומיים"), and the
  /// singular unit. A singular "יום" before a weekday name or a compound noun is no unit.
  private static let hebrewUnits =
    #"(?:(\d{1,2}|\#(hebrewCountWords))\s+(ימים|שבועות|חודשים|שנים)|(יומיים|שבועיים|חודשיים|שנתיים)|(יום\#(hebrewNoDayNameAfter)|שבוע|חודש|שנה))"#

  /// The repeat every `every` (nil for each) of the unit a word names: days,
  /// weeks, months, or years. `unit` is in the reading form.
  private static func hebrewRepeat(unit: String, every: Int?) -> Repeat? {
    switch unit {
    case hebrewTableKey("יום"), hebrewTableKey("ימים"):
      Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case hebrewTableKey("שבוע"), hebrewTableKey("שבועות"): weekly(every: every, on: [])
    case hebrewTableKey("חודש"), hebrewTableKey("חודשים"): monthly(every: every, on: nil)
    case hebrewTableKey("שנה"), hebrewTableKey("שנים"):
      Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    default: nil
    }
  }

  /// Each dual unit and the count it names: "יומיים" is two days.
  private static let hebrewDualUnits: [String: (unit: String, count: Int)] = [
    hebrewTableKey("יומיים"): (hebrewTableKey("יום"), 2),
    hebrewTableKey("שבועיים"): (hebrewTableKey("שבוע"), 2),
    hebrewTableKey("חודשיים"): (hebrewTableKey("חודש"), 2),
    hebrewTableKey("שנתיים"): (hebrewTableKey("שנה"), 2),
  ]

  /// The repeat the four groups of ``hebrewUnits`` name, which start at group 1:
  /// a count and a plural unit, a dual unit, or a singular unit.
  private static func hebrewUnitRepeat(_ match: Match) -> Repeat? {
    if let dual = match.group(3).map(hebrewKey), let reading = hebrewDualUnits[dual] {
      return hebrewRepeat(unit: reading.unit, every: reading.count)
    }
    if let unit = match.group(2).map(hebrewKey) {
      guard let text = match.group(1), let count = number(text) ?? hebrewCounts[hebrewKey(text)],
        (1...99).contains(count)
      else { return nil }
      return hebrewRepeat(unit: unit, every: count == 1 ? nil : count)
    }
    return match.group(4).map(hebrewKey).flatMap { hebrewRepeat(unit: $0, every: nil) }
  }

  // MARK: - Weekdays

  /// A list of weekdays, as a pattern without groups: names with "יום" before
  /// each or not, separated by commas or "ו", each maybe after its own "כל"
  /// ("יום שני וחמישי", "שני, רביעי וחמישי", "א׳ ו-ג׳", "שני וכל חמישי"). A name
  /// that stands alone, as "שני" does in "כל שני ימים", is judged by the rules
  /// that use the list (``hebrewNotCounted``).
  private static let hebrewWeekdayList =
    #"(?:יום\s+)?\#(hebrewRepeatNames)(?:(?:\s*,\s*ו?|\s+ו-?)(?:כל\s+)?(?:יום\s+)?\#(hebrewRepeatNames)){0,6}"#

  /// What may not follow a list of weekdays: a unit that makes the name a count
  /// ("כל שני ימים" is every two days) and "בחודש" ("כל יום ראשון בחודש" is one
  /// Sunday of the month, which a repeat cannot hold).
  private static let hebrewNotCounted =
    #"(?!\s+(?:ימים|שבועות|חודשים|שנים|שעות|דקות|ב?חודש)\#(hebrewEnd))"#

  /// "כל יום ראשון עד חמישי", "כל ראשון עד חמישי", "בימי ראשון עד חמישי", "בימים
  /// א׳-ה׳": every day of a span of weekdays. Groups: 1 the first weekday and 2
  /// the last after "כל"; 3 the first and 4 the last after "בימי". The "עד"
  /// inside the span joins its days and is no deadline word.
  static var hebrewWeekdaySpanPattern: String {
    let name = hebrewRepeatNames
    return
      #"\#(hebrewStart)(?:\#(hebrewEvery)\s+(?:יום\s+)?(\#(name))\s+(?:עד|ועד)\s+(?:יום\s+)?(\#(name))|(?:בימי|בימים)\s+(\#(name))\s*(?:(?:עד|ועד)\s+|[-–—])\s*(\#(name)))\#(hebrewEnd)"#
  }

  /// A span runs from its first weekday to its last through the week's end: it
  /// holds the days it names, whatever the working week is.
  private static func hebrewWeekdaySpanRepeat(_ match: Match) -> Repeat? {
    guard let firstWord = match.group(1) ?? match.group(3), let lastWord = match.group(2) ?? match.group(4),
      let first = hebrewWeekdayIndex(firstWord), let last = hebrewWeekdayIndex(lastWord), first != last
    else { return nil }
    return weekly(every: nil, on: (0...(last - first + 7) % 7).map { (first + $0) % 7 })
  }

  /// "כל סוף שבוע", "בכל סופ״ש": Saturday and Sunday, the weekend of the app's
  /// week. Israel's weekend is Friday and Saturday, which no repeat names here.
  private static var hebrewWeekendRepeatPattern: String {
    #"\#(hebrewStart)\#(hebrewEvery)\s+(?:סוף[\s-]+ה?שבוע|סופ״?ש)\#(hebrewEnd)"#
  }

  /// "כל יום שני", "כל שני וחמישי", "בכל יום ראשון", "כל יום שני ורביעי", "בימי שני
  /// וחמישי", "בימים ב׳ ו-ד׳", "כל שבוע ביום שני". Groups: 1 the weekdays after
  /// "כל שבוע ב", 2 those after "כל", 3 those after "בימי".
  private static var hebrewWeekdayRepeatPattern: String {
    let list = hebrewWeekdayList
    return
      #"\#(hebrewStart)(?:\#(hebrewEvery)\s+שבוע\s+(?:ביום|בימי|בימים)\s+(\#(list))|\#(hebrewEvery)\s+(\#(list))|(?:בימי|בימים)\s+(\#(list)))\#(hebrewEnd)\#(hebrewNotCounted)"#
  }

  private static func hebrewWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(1) ?? match.group(2) ?? match.group(3) ?? ""
    let words = hebrewPhrase(list).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
    let days = words.compactMap { word in
      hebrewWeekdayIndex(word)
        ?? (word.hasPrefix(hebrewTableKey("ו")) ? hebrewWeekdayIndex(String(word.dropFirst())) : nil)
    }
    guard !days.isEmpty else { return nil }
    return weekly(every: nil, on: days)
  }

  // MARK: - Days of the month and intervals

  /// "כל חודש ב-5", "בכל חודש ב-5", "ב-5 בכל חודש", "ב-5 לכל חודש", "בכל 5
  /// לחודש": a day of the month in each form. Groups: 1, 2, and 3 the day.
  private static var hebrewMonthDayRepeatPattern: String {
    #"\#(hebrewStart)(?:\#(hebrewEvery)\s+חודש\s+[בה]-?(\d{1,2})(?:\s+לחודש)?|[בה]-?(\d{1,2})\s+(?:בכל|לכל|מדי)\s+חודש|בכל\s+(\d{1,2})\s+לחודש)\#(hebrewEnd)"#
  }

  private static func hebrewMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = match.group(1) ?? match.group(2) ?? match.group(3), let day = number(text) else { return nil }
    return monthly(every: nil, on: day)
  }

  /// "כל יום", "כל שבוע", "כל חודש", "כל שנה", "כל יומיים", "כל שבועיים", "כל 3
  /// ימים", "כל שלושה שבועות", "מדי יום", "מדי שבוע", "מדי יום ביומו". An
  /// interval shorter than a day ("כל שעתיים") is no repeat. Groups are those of
  /// ``hebrewUnits``.
  private static var hebrewIntervalRepeatPattern: String {
    #"\#(hebrewStart)\#(hebrewEvery)\s+\#(hebrewUnits)(?:\s+ביומו)?\#(hebrewEnd)"#
  }

  private static func hebrewIntervalRepeat(_ match: Match) -> Repeat? {
    hebrewUnitRepeat(match)
  }

  /// "אחת לשבוע", "אחת לחודשיים", "אחת ל-3 ימים", "פעם בשבוע", "פעם ביום", "פעם
  /// בשבועיים", "פעם ב-3 חודשים", "פעם אחת בחודש": once in a unit. "פעמיים
  /// בשבוע" is not read, and neither is a unit that a word makes a particular
  /// one ("פעם בשבוע הבא"). Groups are those of ``hebrewUnits``.
  private static var hebrewOnceEveryPattern: String {
    #"\#(hebrewStart)(?:אחת\s+ל|פעם\s+(?:אחת\s+)?ב)-?\#(hebrewUnits)\#(hebrewEnd)(?!\s+(?:שעבר|שעברה|הבא|הבאה|הקרוב|הקרובה|הזה|הזאת)\#(hebrewEnd))"#
  }

  private static func hebrewOnceEvery(_ match: Match) -> Repeat? {
    hebrewUnitRepeat(match)
  }

  // MARK: - Parts of the day, alternation, and basis

  /// "כל בוקר", "כל ערב", "כל לילה", "כל צהריים", "כל אחר הצהריים", "בכל בוקר",
  /// "מדי ערב", "כל יום בבוקר": every day. "כל הבוקר" is all morning, so the
  /// article is no part of the pattern, a bare "ערב" before a holiday ("כל ערב
  /// חג") is its eve, and a part of the day that another follows ("כל בוקר
  /// וערב", "כל בוקר וכל ערב") is two times a day, which a repeat does not hold.
  private static var hebrewPartOfDayRepeatPattern: String {
    let part = #"(?:ב|ה)?(?:בוקר|ערב|לילה|צהר(?:יי|י)ם|אחר(?:י)?[\s-]+ה?צהר(?:יי|י)ם)"#
    return
      #"\#(hebrewStart)\#(hebrewEvery)\s+(?:יום\s+)?(?:ב?(?:בוקר|לילה|צהר(?:יי|י)ם)|ב?ערב\#(hebrewEveGuard)|אחר(?:י)?[\s-]+ה?צהר(?:יי|י)ם)\#(hebrewEnd)(?!(?:\s*,\s*|\s+)ו-?(?:כל\s+)?\#(part)\#(hebrewEnd))"#
  }

  /// "יום כן יום לא" (every second day) and "שבוע כן שבוע לא" (every second
  /// week). Group 1 is the day form, group 2 the week form.
  private static var hebrewAlternatingPattern: String {
    #"\#(hebrewStart)(?:(יום)(?:\s*,\s*|\s+)כן(?:\s*,\s*|\s+)יום\s+לא|(שבוע)(?:\s*,\s*|\s+)כן(?:\s*,\s*|\s+)שבוע\s+לא)\#(hebrewEnd)"#
  }

  private static func hebrewAlternatingRepeat(_ match: Match) -> Repeat? {
    match.group(1) != nil ? hebrewRepeat(unit: hebrewTableKey("יום"), every: 2) : weekly(every: 2, on: [])
  }

  /// "על בסיס יומי", "על בסיס שבועי", "על בסיס חודשי", "על בסיס שנתי": the
  /// cadence as the attribute of "basis", which no title uses for anything
  /// else. The bare adjectives ("דוח שבועי") are not read, since they follow
  /// their noun as a title's own words do. Groups: 1 day, 2 week, 3 month, 4
  /// year.
  private static var hebrewBasisPattern: String {
    #"\#(hebrewStart)על\s+בסיס\s+(?:(יומי)|(שבועי)|(חודשי)|(שנתי))\#(hebrewEnd)"#
  }

  private static func hebrewBasisRepeat(_ match: Match) -> Repeat? {
    if match.group(1) != nil { return Repeat(rule: TaskRecurrenceRule(freq: .daily)) }
    if match.group(2) != nil { return weekly(every: nil, on: []) }
    if match.group(3) != nil { return monthly(every: nil, on: nil) }
    if match.group(4) != nil { return Repeat(rule: TaskRecurrenceRule(freq: .yearly)) }
    return nil
  }
}
