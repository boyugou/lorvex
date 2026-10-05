import Foundation

extension LorvexCaptureVocabulary {
  // The Dutch repeat rules: working days, weekends, a day of the month,
  // repeated weekdays, counted intervals, "once per", cadence phrases, and the
  // adverbs at the end of a line. The vocabulary's other words are in
  // ``dutch``.

  /// The repeat rules in the order they are tried: the working days, the
  /// weekend, and a day of the month before the rules for every day and every
  /// month, which would leave "doordeweeks" or the day's number in the title;
  /// the counted intervals before the weekday rules, so "om de week op
  /// maandag" takes its interval with its weekday; the weekly adverbs with their
  /// weekdays before the weekday adverbs, so "wekelijks maandags" is read whole.
  static let dutchRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: dutchWorkdaysPattern) { _ in workdays },
    Rule(pattern: dutchWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: dutchMonthDayRepeatPattern, read: dutchMonthDayRepeat),
    Rule(pattern: dutchIntervalRepeatPattern, read: dutchIntervalRepeat),
    Rule(pattern: dutchWeeklyOnPattern, read: dutchWeeklyOn),
    Rule(pattern: dutchWeekdayRepeatPattern, read: dutchWeekdayRepeat),
    Rule(pattern: dutchOnceEveryPattern, read: dutchOnceEvery),
    Rule(pattern: dutchEveryUnitPattern, read: dutchEveryUnit),
    Rule(pattern: dutchAdverbPattern, read: dutchAdverb),
  ]

  // MARK: - Working days and weekends

  /// "doordeweeks", "op werkdagen", "alle werkdagen", "elke werkdag", "iedere
  /// werkdag", "op doordeweekse dagen", "elke doordeweekse dag", "ma-vr", "ma
  /// t/m vr", "maandag tot en met vrijdag", "van maandag tot vrijdag". The
  /// singular "werkdag" and the plural "werkdagen" alone are no repeat ("de
  /// eerste werkdag", "binnen 5 werkdagen").
  private static let dutchWorkdaysPattern =
    #"\#(dutchStart)(?:doordeweeks|(?:op|alle)\s+(?:werkdagen|doordeweekse\s+dagen)|(?:elke|iedere)\s+(?:werkdag|doordeweekse\s+dag)|(?:(?:elke|iedere|van)\s+)?(?:maandag|ma\.?)\s*(?:t\s*/\s*m|t\.m\.|tm|tot\s+en\s+met|tot|[-–—])\s*(?:vrijdag|vr\.?))\#(dutchEnd)"#

  /// "elk weekend", "ieder weekend", "elke weekend", "in de weekenden", "in
  /// weekenden", "op de weekenden", "alle weekenden". "In het weekend" and "dit
  /// weekend" name the coming weekend, a day.
  private static let dutchWeekendRepeatPattern =
    #"\#(dutchStart)(?:(?:elk|elke|ieder|iedere)\s+(?:weekend|weekeinde)|(?:in|op)\s+(?:de\s+)?(?:weekenden|weekends|weekeinden)|alle\s+(?:weekenden|weekends|weekeinden))\#(dutchEnd)"#

  // MARK: - Day of the month

  /// A day of the month written after "op" or between "elke" and "van de
  /// maand": a number with an optional ordinal ending ("15", "15e", "15de",
  /// "1ste") or "eerste". Group-free except for the day.
  private static let dutchMonthDayNumber = #"(\d{1,2}(?:e|de|ste)?|eerste)"#

  /// What may not follow a bare day of the month: a unit or a counted noun,
  /// which would make the number an amount ("elke maand op 15 euro").
  private static let dutchNoCountedUnitAfter =
    #"(?!\s*(?:uur|uren|min|minuten|minuut|dagen|dag|weken|week|maanden|maand|jaar|jaren|keer|maal|x|euro|procent|personen|mensen|stuks)(?![\p{Latin}\p{N}\p{M}]))"#

  /// "elke 15e van de maand", "iedere 1ste van de maand", "elke eerste van de
  /// maand", "elke maand op de 15e", "elke maand op 15", "maandelijks op de
  /// 15e". Groups 1 and 2: the day of the month in each form.
  private static var dutchMonthDayRepeatPattern: String {
    let day = dutchMonthDayNumber
    return
      #"\#(dutchStart)(?:(?:elke|iedere)\s+\#(day)\s+van\s+de\s+maand|(?:(?:elke|iedere)\s+maand|maandelijks)\s+(?:op\s+de|op)\s+\#(day)\#(dutchNoCountedUnitAfter))\#(dutchEnd)"#
  }

  private static func dutchMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = match.group(1) ?? match.group(2) else { return nil }
    let day = dutchKey(text) == "eerste" ? 1 : number(text.prefix(while: \.isNumber))
    return day.flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The separator of a list of weekdays: a comma, "en", or "&".
  private static let dutchListSeparator = #"(?:\s*,\s*|\s+en\s+|\s*&\s*)"#

  /// The part of the day a weekday may carry in a repeat, written onto it
  /// ("elke maandagochtend") or after it ("elke vrijdag avond"), as a pattern
  /// without groups. "Morgen" counts only written onto the weekday, since after
  /// it the word is as often tomorrow.
  private static let dutchRepeatDayPart =
    #"(?:(?:ochtend|morgen|voormiddag|middag|namiddag|avond|nacht)|\s+(?:ochtend|voormiddag|middag|namiddag|avond|nacht))"#

  /// The parts of the day written onto a weekday, longest first.
  private static let dutchRepeatPartSuffixes = ["voormiddag", "namiddag", "middag", "ochtend", "morgen", "avond", "nacht"]

  /// The weekdays after "elke" or "iedere", as a pattern without groups: names
  /// and abbreviations ("maandag, wo en vrijdag"), each maybe with its part of
  /// the day and each maybe after its own "elke".
  private static var dutchEveryWeekdays: String {
    let day = #"(?:(?:\#(dutchWeekdayNames))(?:\#(dutchRepeatDayPart))?|\#(dutchWeekdayAbbreviations))"#
    return #"\#(day)(?:\#(dutchListSeparator)(?:(?:elke|iedere)\s+)?\#(day)){0,6}"#
  }

  /// The adverbs of repeated weekdays, as a pattern without groups: "maandags",
  /// "maandags en donderdags", "maandags, woensdags en vrijdags".
  private static var dutchWeekdayAdverbs: String {
    let adverb = #"(?:maandags|dinsdags|woensdags|donderdags|vrijdags|zaterdags|zondags)"#
    return #"\#(adverb)(?:\#(dutchListSeparator)(?:['’]s\s+)?\#(adverb)){0,6}"#
  }

  /// The weekdays a matched list names, 0 = Sunday: names, abbreviations,
  /// adverbs, and names with a part of the day written onto them.
  private static func dutchRepeatWeekdays(_ list: String) -> [Int] {
    letterWords(list).compactMap { word in
      if let index = dutchWeekdayIndex(word) { return index }
      for suffix in dutchRepeatPartSuffixes where word.hasSuffix(suffix) {
        let name = String(word.dropLast(suffix.count))
        if name.count > 3, let index = dutchWeekdayIndex(name) { return index }
      }
      return nil
    }
  }

  /// "elke maandag", "iedere dinsdag en donderdag", "elke ma en wo", "elke
  /// andere maandag" (every other Monday), "om de maandag", "maandags", "'s
  /// maandags", "maandags en donderdags". Groups: 1 "andere" (every other), 2
  /// the weekdays after "elke" or "iedere", 3 the weekday after "om de", 4 the
  /// adverbs. The abbreviations count only after "elke" or "iedere".
  private static var dutchWeekdayRepeatPattern: String {
    #"\#(dutchStart)(?:(?:elke|iedere)\s+(?:(andere)\s+)?(\#(dutchEveryWeekdays))|om\s+de\s+((?:\#(dutchWeekdayNames))(?:\#(dutchRepeatDayPart))?)|(?:['’]s\s+)?(\#(dutchWeekdayAdverbs)))\#(dutchEnd)"#
  }

  private static func dutchWeekdayRepeat(_ match: Match) -> Repeat? {
    if let list = match.group(3) {
      let days = dutchRepeatWeekdays(list)
      return days.isEmpty ? nil : weekly(every: 2, on: days)
    }
    let days = dutchRepeatWeekdays(match.group(2) ?? match.group(4) ?? "")
    return days.isEmpty ? nil : weekly(every: match.group(1) == nil ? nil : 2, on: days)
  }

  /// "wekelijks op maandag", "tweewekelijks op dinsdag en vrijdag", "wekelijks
  /// maandags": a weekly adverb with the weekdays it repeats on, anywhere in
  /// the line. The adverb alone is read at the end of the line only
  /// (``dutchAdverbPattern``). Groups: 1 the adverb, 2 the weekday names after
  /// an optional "op", 3 the weekday adverbs.
  private static var dutchWeeklyOnPattern: String {
    let names = #"(?:\#(dutchWeekdayNames))(?:\#(dutchRepeatDayPart))?"#
    return
      #"\#(dutchStart)(wekelijks|tweewekelijks)\s+(?:(?:op\s+)?(\#(names)(?:\#(dutchListSeparator)\#(names)){0,6})|(\#(dutchWeekdayAdverbs)))\#(dutchEnd)"#
  }

  private static func dutchWeeklyOn(_ match: Match) -> Repeat? {
    let days = dutchRepeatWeekdays(match.group(2) ?? match.group(3) ?? "")
    guard let adverb = match.group(1), !days.isEmpty else { return nil }
    return weekly(every: dutchKey(adverb) == "tweewekelijks" ? 2 : nil, on: days)
  }

  /// "elke eerste maandag van de maand", "elke tweede vrijdag", "elke 2e
  /// dinsdag van de maand", "de laatste donderdag van de maand", "derde
  /// woensdag": a weekday of each month by its place in it. The repeat has no
  /// such rule and no day rule can name it, so the text stays in the title
  /// whole, with no part of it read as a weekday.
  static let dutchOrdinalWeekdayPattern =
    #"\#(dutchStart)(?:(?:elke|iedere)\s+)?(?:eerste|tweede|derde|vierde|vijfde|(?<!ten\s)laatste|\d{1,2}(?:e|de|ste))\s+(?:\#(dutchWeekdayNames))(?:\s+van\s+(?:de|deze|elke|iedere|volgende|dezelfde|die)\s+maand)?\#(dutchEnd)"#

  /// "voor het weekend", "voor dit weekend", "na het weekend", "tot volgend
  /// weekend", "tegen het weekend": a bound at the weekend, and "vorig weekend",
  /// "afgelopen weekend": a past one. Neither names a day the planner can set,
  /// so the whole phrase stays in the title, where "dit weekend" would else be
  /// read as the day with "voor" left behind and the English reading of
  /// "weekend" would plan the coming one.
  static let dutchNoDayWeekendPattern =
    #"\#(dutchStart)(?:(?:voor|na|tot|tegen)\s+(?:het|dit|volgend|volgende|komend|komende|aankomend|aankomende|aanstaand|aanstaande)|(?:vorig|vorige|afgelopen|laatste))\s+(?:weekend|weekeinde)\#(dutchEnd)"#

  // MARK: - Counted intervals

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// first letters: days, weeks, months, or years. A whole number of weeks
  /// counted in days is a weekly repeat ("elke 14 dagen"), and a unit that is
  /// none returns nil.
  private static func dutchRepeat(unit: String, every: Int?) -> Repeat? {
    let key = dutchKey(unit)
    if key.hasPrefix("week") || key.hasPrefix("weke") { return weekly(every: every, on: []) }
    if key.hasPrefix("maand") { return monthly(every: every, on: nil) }
    if key.hasPrefix("jaar") || key.hasPrefix("jare") {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    guard key.hasPrefix("dag") else { return nil }
    if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  /// The count an ordinal that goes with "elke" names: "elke tweede week" is
  /// every other week, and "elke andere dag" every other day.
  private static let dutchRepeatOrdinals: [String: Int] = [
    "andere": 2, "tweede": 2, "derde": 3, "vierde": 4, "vijfde": 5, "zesde": 6, "zevende": 7, "achtste": 8,
  ]

  /// "elke 3 dagen", "elke twee weken", "iedere 14 dagen", "om de 2 weken", "om
  /// de twee weken", "om de week", "om de dag", "om de andere dag", "elke
  /// tweede dag", "elke andere week", "elk kwartaal", "elk half jaar", each maybe
  /// before a weekday ("om de week op maandag", "elke 2 weken maandags").
  /// Groups: 1 the count and 2 its unit; 3 the ordinal and 4 its unit; 5 the
  /// unit after "om de"; 6 "kwartaal" or "half jaar"; 7 the weekday names after
  /// "op" and 8 the weekday adverbs, both after a weekly interval.
  /// "Elke tweede maandag" has no unit and is no interval: it stays whole.
  private static var dutchIntervalRepeatPattern: String {
    let units = #"dagen|dag|weken|week|maanden|maand|jaren|jaar"#
    let names = #"(?:\#(dutchWeekdayNames))(?:\#(dutchRepeatDayPart))?"#
    let weekdays =
      #"(?:\s+(?:op\s+)?(\#(names)(?:\#(dutchListSeparator)\#(names)){0,6})|\s+(\#(dutchWeekdayAdverbs)))?"#
    return
      #"\#(dutchStart)(?:(?:elke|elk|iedere|ieder|om\s+de)\s+(\d{1,3}|\#(dutchCountWords))\s+(\#(units))|(?:elke|elk|iedere|ieder)\s+(andere|tweede|derde|vierde|vijfde|zesde|zevende|achtste)\s+(dag|week|maand|jaar)|om\s+de\s+(?:andere\s+)?(dag|week|maand|jaar)|(?:elk|ieder)\s+(kwartaal|half\s+jaar))\#(weekdays)\#(dutchEnd)"#
  }

  private static func dutchIntervalRepeat(_ match: Match) -> Repeat? {
    let weekdays = dutchRepeatWeekdays(match.group(7) ?? match.group(8) ?? "")
    var base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      guard let count = dutchCount(countText), (1...99).contains(count) else { return nil }
      base = dutchRepeat(unit: unit, every: count == 1 ? nil : count)
    } else if let ordinal = match.group(3), let unit = match.group(4) {
      guard let count = dutchRepeatOrdinals[dutchKey(ordinal)] else { return nil }
      base = dutchRepeat(unit: unit, every: count)
    } else if let unit = match.group(5) {
      base = dutchRepeat(unit: unit, every: 2)
    } else if let word = match.group(6) {
      base = monthly(every: dutchKey(word) == "kwartaal" ? 3 : 6, on: nil)
    }
    guard let base else { return nil }
    // A weekday after a weekly interval fixes the repeat's days.
    guard !weekdays.isEmpty else { return base }
    return base.rule.freq == .weekly ? weekly(every: base.rule.interval, on: weekdays) : nil
  }

  // MARK: - Once per

  /// "een keer per week", "een keer per dag", "1 keer in de week", "eenmaal per
  /// maand", "een keer per jaar", "1x per week". Group 1: the unit.
  private static let dutchOnceEveryPattern =
    #"\#(dutchStart)(?:(?:een|1)\s*(?:keer|maal)|eenmaal|1\s*x)\s+(?:per|in\s+de|in\s+het|elke)\s+(dag|week|maand|jaar)\#(dutchEnd)"#

  private static func dutchOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).flatMap { dutchRepeat(unit: $0, every: nil) }
  }

  // MARK: - Cadence phrases

  /// "elke dag", "iedere dag", "elke ochtend", "elke avond", "elke nacht",
  /// "elke week", "elke maand", "elk jaar", "ieder jaar". Group 1: the unit or
  /// the part of the day.
  private static let dutchEveryUnitPattern =
    #"\#(dutchStart)(?:elke?|iedere?)\s+(dag|morgen|ochtend|voormiddag|middag|namiddag|avond|nacht|week|maand|jaar)\#(dutchEnd)"#

  private static func dutchEveryUnit(_ match: Match) -> Repeat? {
    guard let word = match.group(1) else { return nil }
    switch dutchKey(word) {
    case "week": return weekly(every: nil, on: [])
    case "maand": return monthly(every: nil, on: nil)
    case "jaar": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    default: return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
  }

  // MARK: - Adverbs

  /// "dagelijks", "wekelijks", "maandelijks", "jaarlijks", "tweewekelijks",
  /// "veertiendaags", "driemaandelijks", "halfjaarlijks" at the end of the line,
  /// or "dagelijks", "wekelijks", "maandelijks", "jaarlijks" opening the line
  /// before a colon or a comma. The word is an adjective too ("Wekelijks
  /// overleg", "Dagelijks leven"), and the end of the line is where it says how
  /// a task repeats. Groups: 1 the adverb at the end, 2 the adverb that opens the
  /// line.
  private static let dutchAdverbPattern =
    #"\#(dutchStart)(dagelijks|wekelijks|maandelijks|jaarlijks|tweewekelijks|veertiendaags|driemaandelijks|halfjaarlijks)\#(dutchEnd)(?=[\s.!]*$)|^\s*(dagelijks|wekelijks|maandelijks|jaarlijks)\#(dutchEnd)(?=\s*[:,，：])"#

  private static func dutchAdverb(_ match: Match) -> Repeat? {
    guard let word = match.group(1) ?? match.group(2) else { return nil }
    switch dutchKey(word) {
    case "dagelijks": return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case "wekelijks": return weekly(every: nil, on: [])
    case "maandelijks": return monthly(every: nil, on: nil)
    case "jaarlijks": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "tweewekelijks", "veertiendaags": return weekly(every: 2, on: [])
    case "driemaandelijks": return monthly(every: 3, on: nil)
    default: return monthly(every: 6, on: nil)
    }
  }
}
