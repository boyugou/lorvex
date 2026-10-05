import Foundation

extension LorvexCaptureVocabulary {
  // The Romanian repeat rules: working days, weekends, a day of the month,
  // repeated weekdays, counted intervals, "once per", cadence phrases, and the
  // adverbs at the end of a line. The vocabulary's other words are in
  // ``romanian``.

  /// The repeat rules in the order they are tried: the working days, the
  /// weekend, and a day of the month before the rules for every day and every
  /// month, which would leave "în zilele lucrătoare" or the day's number in the
  /// title; the counted intervals before the weekday rules, so "la două
  /// săptămâni joia" takes its interval with its weekday; "săptămânal" with its
  /// weekdays before the weekday rules, so "săptămânal luni" is read whole.
  static let romanianRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: romanianWorkdaysPattern) { _ in workdays },
    Rule(pattern: romanianWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: romanianMonthDayRepeatPattern, read: romanianMonthDayRepeat),
    Rule(pattern: romanianIntervalRepeatPattern, read: romanianIntervalRepeat),
    Rule(pattern: romanianWeeklyOnPattern, read: romanianWeeklyOn),
    Rule(pattern: romanianWeekdayRepeatPattern, read: romanianWeekdayRepeat),
    Rule(pattern: romanianOnceEveryPattern, read: romanianOnceEvery),
    Rule(pattern: romanianEveryUnitPattern, read: romanianEveryUnit),
    Rule(pattern: romanianAdverbPattern, read: romanianAdverb),
  ]

  // MARK: - Working days and weekends

  /// "în zilele lucrătoare", "zilele de lucru", "în fiecare zi lucrătoare", "de
  /// luni până vineri", "luni până vineri", "luni - vineri". "Zile lucrătoare"
  /// with no article is no repeat ("în 5 zile lucrătoare").
  private static let romanianWorkdaysPattern =
    #"\#(romanianStart)(?:(?:in\s+)?(?:toate\s+)?zilele\s+(?:lucratoare|de\s+lucru)|(?:in\s+)?fiecare\s+zi\s+(?:lucratoare|de\s+lucru)|(?:de\s+)?luni\s*(?:[-–—]|pana\s+(?:la\s+|in\s+)?)\s*vineri)\#(romanianEnd)"#

  /// "în fiecare weekend", "fiecare weekend", "în fiecare sfârșit de
  /// săptămână", "în weekenduri", "în toate weekendurile", "weekend-urile". "În
  /// weekend" and "weekendul acesta" name the coming weekend, a day.
  private static let romanianWeekendRepeatPattern =
    #"\#(romanianStart)(?:(?:(?:in|la)\s+)?fiecare\s+(?:weekend(?:-?ul)?|sfarsit\s+de\s+saptamana)|(?:(?:in|la)\s+)?(?:toate\s+)?weekend(?:-?uri(?:le)?|urile))\#(romanianEnd)"#

  // MARK: - Day of the month

  /// What may not follow a bare day of the month: a unit or a counted noun,
  /// which would make the number an amount ("în fiecare lună pe 15 lei").
  private static let romanianNoCountedUnitAfter =
    #"(?!\s*(?:ore|ora|min|minute|minut|zile|zi|saptamani|saptamana|luni|luna|ani|an|ori|x|euro|lei|ron|procente|persoane|oameni|bucati)(?![\p{Latin}\p{N}\p{M}]))"#

  /// "în fiecare 15 ale lunii", "pe 15 ale fiecărei luni", "în fiecare lună pe
  /// 15", "lunar pe 15", "pe 15 în fiecare lună". Groups 1, 2, and 3: the day of
  /// the month in each form.
  private static var romanianMonthDayRepeatPattern: String {
    #"\#(romanianStart)(?:(?:(?:in|la)\s+fiecare|pe)\s+(\d{1,2})\s+(?:ale|al|a)\s+(?:lunii|fiecarei\s+luni)|(?:(?:in|la)\s+fiecare\s+luna|lunar)\s+(?:pe|la|in)\s+(\d{1,2})\#(romanianNoCountedUnitAfter)|pe\s+(\d{1,2})\s+in\s+fiecare\s+luna)\#(romanianEnd)"#
  }

  private static func romanianMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let text = match.group(1) ?? match.group(2) ?? match.group(3) else { return nil }
    return number(text).flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The separator of a list of weekdays: a comma, "și", or "&".
  private static let romanianListSeparator = #"(?:\s*,\s*|\s+si\s+|\s*&\s*)"#

  /// The weekday names after "în fiecare", as a pattern without groups: "luni",
  /// "luni și joi", "luni, miercuri și vineri", each maybe after its own "în
  /// fiecare".
  private static var romanianNamesList: String {
    let day = #"(?:\#(romanianWeekdayNames))"#
    return #"\#(day)(?:\#(romanianListSeparator)(?:(?:in\s+)?fiecare\s+)?\#(day)){0,6}"#
  }

  /// The definite weekday forms, as a pattern without groups: "lunea", "lunea
  /// și joia", "marțea, joia și sâmbăta".
  private static var romanianDefiniteList: String {
    let day = #"(?:\#(romanianWeekdayDefiniteNames))"#
    return #"\#(day)(?:\#(romanianListSeparator)\#(day)){0,6}"#
  }

  /// The definite forms of Monday to Friday, which no plain name shares a
  /// reading with. The definite forms of Saturday and Sunday ("sâmbăta",
  /// "duminica") read like the plain names once the diacritics are left out,
  /// so a list of definite forms is a repeat only when one of these stands in
  /// it.
  private static let romanianUnambiguousDefinites: Set<String> = ["lunea", "martea", "miercurea", "joia", "vinerea"]

  /// The weekdays a matched list names, 0 = Sunday.
  private static func romanianRepeatWeekdays(_ list: String) -> [Int] {
    letterWords(list).compactMap { romanianWeekdayIndex($0) }
  }

  /// "în fiecare luni", "în fiecare zi de luni", "în fiecare marți și joi",
  /// "în zilele de marți și joi", "lunea", "lunea și joia", each maybe with a
  /// part of the day after it ("în fiecare luni dimineața"). A definite form
  /// with "viitoare", "următoare", "asta", "aceasta", or "trecută" after it
  /// ("lunea viitoare") names one day, which the day rules read. Groups: 1 the
  /// weekdays after "în fiecare", 2 the weekdays after "în zilele de", 3 the
  /// definite forms.
  private static var romanianWeekdayRepeatPattern: String {
    let oneDay = #"(?!\s+(?:viitoare|urmatoare|asta|aceasta|trecuta|anterioara))"#
    return
      #"\#(romanianStart)(?:(?:(?:in|la)\s+)?fiecare\s+(?:zi\s+de\s+)?(\#(romanianNamesList))|in\s+zilele\s+(?:de\s+)?(\#(romanianNamesList))|(\#(romanianDefiniteList))\#(oneDay))(?:\s+(?:\#(romanianPartWords)))?\#(romanianEnd)"#
  }

  private static func romanianWeekdayRepeat(_ match: Match) -> Repeat? {
    if let list = match.group(3) {
      guard letterWords(list).contains(where: { romanianUnambiguousDefinites.contains($0) }) else { return nil }
      let days = romanianRepeatWeekdays(list)
      return days.isEmpty ? nil : weekly(every: nil, on: days)
    }
    let days = romanianRepeatWeekdays(match.group(1) ?? match.group(2) ?? "")
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "săptămânal luni", "săptămânal luni și joi", "săptămânal în zilele de
  /// marți", "săptămânal marțea": "săptămânal" with the weekdays it repeats on,
  /// anywhere in the line. The adverb alone is read at the end of the line only
  /// (``romanianAdverbPattern``). Groups: 1 the weekday names, 2 the definite
  /// forms.
  private static var romanianWeeklyOnPattern: String {
    #"\#(romanianStart)saptamanal\s+(?:(?:(?:in\s+(?:zilele\s+de\s+)?|pe\s+|la\s+)?(\#(romanianNamesList)))|(\#(romanianDefiniteList)))\#(romanianEnd)"#
  }

  private static func romanianWeeklyOn(_ match: Match) -> Repeat? {
    if let list = match.group(2) {
      guard letterWords(list).contains(where: { romanianUnambiguousDefinites.contains($0) }) else { return nil }
      let days = romanianRepeatWeekdays(list)
      return days.isEmpty ? nil : weekly(every: nil, on: days)
    }
    let days = romanianRepeatWeekdays(match.group(1) ?? "")
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "prima luni din lună", "ultima vineri din lună", "a doua marți", "în
  /// fiecare a treia joi", "prima zi de luni a lunii": a weekday of each month
  /// by its place in it. The repeat has no such rule and no day rule can name
  /// it, so the text stays in the title whole, with no part of it read as a
  /// weekday.
  static let romanianOrdinalWeekdayPattern =
    #"\#(romanianStart)(?:(?:(?:in|la)\s+)?fiecare\s+)?(?:prima|a\s+doua|a\s+treia|a\s+patra|a\s+cincea|ultima|penultima|a\s+\d{1,2}\s*-\s*a)\s+(?:zi\s+de\s+)?(?:\#(romanianWeekdayNames)|\#(romanianWeekdayDefiniteNames))(?:\s+(?:din|a|ale)\s+(?:luna|lunii|fiecarei\s+luni|fiecare\s+luna))?\#(romanianEnd)"#

  /// "până la weekend", "înainte de weekend", "după weekend", "pentru
  /// weekendul acesta", "de weekend", "peste weekend", "la weekend", and
  /// "weekendul trecut": a bound at the weekend, a weekend a task is for, or a
  /// past one. None names a day the planner can set, so the whole phrase stays
  /// in the title, where English would otherwise plan the bare "weekend" with
  /// the preposition left behind.
  static let romanianNoDayWeekendPattern =
    #"\#(romanianStart)(?:(?:pana\s+(?:la|in)|inainte\s+de|dupa|pentru|spre|catre|peste|de|la|in\s+timpul|pe\s+timpul)\s+(?:acest\s+|acel\s+)?weekend(?:-?ul)?(?:\s+(?:acesta|asta|viitor|urmator))?|weekend(?:-?ul)?\s+(?:trecut|anterior|ce\s+a\s+trecut))\#(romanianEnd)"#

  /// "azi noapte", "sâmbătă și duminică": phrases the reader cannot give one
  /// day. "Azi noapte" names the night just gone as often as the one to come,
  /// and "sâmbăta și duminica" (on Saturdays and Sundays) reads like "sâmbătă
  /// și duminică" (Saturday and Sunday) once the diacritics are left out, so
  /// both stay in the title whole.
  static let romanianAmbiguousDayPattern =
    #"\#(romanianStart)(?:(?:azi|astazi)\s+noapte|sambata\s+si\s+duminica|duminica\s+si\s+sambata)\#(romanianEnd)"#

  // MARK: - Counted intervals

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// first letters: days, weeks, months, or years. A whole number of weeks
  /// counted in days is a weekly repeat ("la 14 zile"), and a unit that is none
  /// returns nil.
  private static func romanianRepeat(unit: String, every: Int?) -> Repeat? {
    let key = romanianKey(unit)
    if key.hasPrefix("saptam") { return weekly(every: every, on: []) }
    if key.hasPrefix("lun") { return monthly(every: every, on: nil) }
    if key == "an" || key == "ani" || key == "anul" {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    guard key == "zi" || key == "zile" else { return nil }
    if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  /// The count an ordinal that goes with "fiecare" names: "în fiecare a doua
  /// zi" is every other day.
  private static let romanianRepeatOrdinals: [String: Int] = [
    "doua": 2, "treia": 3, "patra": 4, "cincea": 5, "sasea": 6, "saptea": 7, "opta": 8,
  ]

  /// "la fiecare 3 zile", "în fiecare două săptămâni", "din 2 în 2 zile", "din
  /// două în două săptămâni", "o dată la două săptămâni", "în fiecare a doua zi",
  /// "la două zile", each maybe before a weekday ("o dată la două săptămâni
  /// joia", "la 2 săptămâni luni"). The particle "de" may stand between a count
  /// and its unit ("la 30 de zile"). Groups: 1 and 2 the count and its unit
  /// after "în fiecare" or "la fiecare"; 3 and 4 the same after a bare
  /// "fiecare"; 5 and 6 the two counts and 7 the unit of "din N în N"; 8 and 9
  /// the count and its unit after "o dată la"; 10 and 11 the ordinal and its
  /// unit after "fiecare a"; 12 and 13 the count and its unit after a bare
  /// "la"; 14 the weekday names after a weekly interval and 15 the definite
  /// forms.
  private static var romanianIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(romanianCountWords))"#
    let units = #"(?:de\s+)?(zile|saptamani|luni|ani)"#
    let weekdays =
      #"(?:\s+(?:(?:in\s+(?:zilele\s+de\s+)?|pe\s+)?(\#(romanianNamesList))|(\#(romanianDefiniteList))))?"#
    return
      #"\#(romanianStart)(?:(?:la|in)\s+fiecare\s+\#(count)\s+\#(units)|fiecare\s+\#(count)\s+\#(units)|din\s+\#(count)\s+in\s+\#(count)\s+\#(units)|(?:o\s+data|odata)\s+(?:la|in)\s+\#(count)\s+\#(units)|(?:(?:in|la)\s+)?fiecare\s+a\s+(doua|treia|patra|cincea|sasea|saptea|opta)\s+(zi|saptamana|luna|an)|la\s+\#(count)\s+\#(units))\#(weekdays)\#(romanianEnd)"#
  }

  private static func romanianIntervalRepeat(_ match: Match) -> Repeat? {
    // The groups the alternatives number: the two "fiecare" forms are 1 to 4,
    // "din N în N" 5 to 7, "o dată la" 8 and 9, the ordinal 10 and 11, the bare
    // "la" 12 and 13, the weekdays 14 and 15.
    let weekdays = romanianRepeatWeekdays(match.group(14) ?? match.group(15) ?? "")
    if let list = match.group(15), !letterWords(list).contains(where: { romanianUnambiguousDefinites.contains($0) }) {
      return nil
    }
    var base: Repeat?
    if let countText = match.group(1) ?? match.group(3), let unit = match.group(2) ?? match.group(4) {
      guard let count = romanianCount(countText), (1...99).contains(count) else { return nil }
      base = romanianRepeat(unit: unit, every: count == 1 ? nil : count)
    } else if let first = match.group(5), let second = match.group(6), let unit = match.group(7) {
      guard let count = romanianCount(first), count == romanianCount(second), (1...99).contains(count) else {
        return nil
      }
      base = romanianRepeat(unit: unit, every: count == 1 ? nil : count)
    } else if let countText = match.group(8), let unit = match.group(9) {
      guard let count = romanianCount(countText), (1...99).contains(count) else { return nil }
      base = romanianRepeat(unit: unit, every: count == 1 ? nil : count)
    } else if let ordinal = match.group(10), let unit = match.group(11) {
      guard let count = romanianRepeatOrdinals[romanianKey(ordinal)] else { return nil }
      base = romanianRepeat(unit: unit, every: count)
    } else if let countText = match.group(12), let unit = match.group(13) {
      guard let count = romanianCount(countText), (2...99).contains(count),
        romanianFollowsAsDetail(match, excluding: ["dupa", "inainte", "de", "din", "fara"])
      else { return nil }
      base = romanianRepeat(unit: unit, every: count)
    }
    guard let base else { return nil }
    // A weekday after a weekly interval fixes the repeat's days.
    guard !weekdays.isEmpty else { return base }
    return base.rule.freq == .weekly ? weekly(every: base.rule.interval, on: weekdays) : nil
  }

  // MARK: - Once per

  /// "o dată pe săptămână", "o dată pe zi", "odată pe lună", "o dată pe an", "1x
  /// pe săptămână". Group 1: the unit.
  private static let romanianOnceEveryPattern =
    #"\#(romanianStart)(?:o\s+data|odata|1\s*x|1\s+data)\s+(?:pe|la|in)\s+(zi|saptamana|luna|an)\#(romanianEnd)"#

  private static func romanianOnceEvery(_ match: Match) -> Repeat? {
    match.group(1).flatMap { romanianRepeat(unit: $0, every: nil) }
  }

  // MARK: - Cadence phrases

  /// "în fiecare zi", "în fiecare dimineață", "în fiecare seară", "în fiecare
  /// noapte", "în fiecare săptămână", "în fiecare lună", "în fiecare an", "în
  /// fiecare trimestru", "în fiecare semestru", "în toate zilele". Group 1: the
  /// unit or the part of the day after "fiecare"; group 2: the plural unit after
  /// "toate".
  private static let romanianEveryUnitPattern =
    #"\#(romanianStart)(?:(?:(?:in|la)\s+)?fiecare\s+(zi|dimineata|seara|noaptea|noapte|dupa[\s-]?amiaza|dupa[\s-]?masa|saptamana|luna|an|trimestru|semestru)|(?:in\s+)?toate\s+(zilele|saptamanile|lunile|anii))\#(romanianEnd)"#

  private static func romanianEveryUnit(_ match: Match) -> Repeat? {
    guard let word = (match.group(1) ?? match.group(2)).map(romanianKey) else { return nil }
    switch word {
    case "saptamana", "saptamanile": return weekly(every: nil, on: [])
    case "luna", "lunile": return monthly(every: nil, on: nil)
    case "an", "anii": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "trimestru": return monthly(every: 3, on: nil)
    case "semestru": return monthly(every: 6, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
  }

  // MARK: - Adverbs

  /// "zilnic", "săptămânal", "lunar", "anual", "trimestrial", "semestrial" at
  /// the end of the line, or "zilnic", "săptămânal", "lunar", "anual" opening
  /// the line before a colon or a comma. The word is an adjective too ("raport
  /// săptămânal"), and the end of the line is where it says how a task
  /// repeats; the feminine and plural adjectives ("săptămânală",
  /// "săptămânale") are no adverb and stay in the title. Groups: 1 the adverb at
  /// the end, 2 the adverb that opens the line.
  private static let romanianAdverbPattern =
    #"\#(romanianStart)(zilnic|saptamanal|lunar|anual|trimestrial|semestrial)\#(romanianEnd)(?=[\s.!]*$)|^\s*(zilnic|saptamanal|lunar|anual)\#(romanianEnd)(?=\s*[:,，：])"#

  private static func romanianAdverb(_ match: Match) -> Repeat? {
    guard let word = (match.group(1) ?? match.group(2)).map(romanianKey) else { return nil }
    switch word {
    case "zilnic": return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    case "saptamanal": return weekly(every: nil, on: [])
    case "lunar": return monthly(every: nil, on: nil)
    case "anual": return Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    case "trimestrial": return monthly(every: 3, on: nil)
    default: return monthly(every: 6, on: nil)
    }
  }
}
