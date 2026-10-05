import Foundation

extension LorvexCaptureVocabulary {
  // The German repeat rules: working days, weekends, a day of the month,
  // repeated weekdays, counted intervals, "once per", and cadence words. The
  // vocabulary's other words are in ``german``.

  /// The repeat rules in the order they are tried: the working days, the
  /// weekend, and a day of the month before the rules for every day and every
  /// month, which would leave "werktags" or the day's number in the title; the
  /// counted intervals before the weekday adverbs, so "alle 2 Wochen montags"
  /// takes its interval with its weekday.
  static let germanRepeatRules: [Rule<Repeat>] = [
    germanRule(germanWorkdaysPattern) { _ in workdays },
    germanRule(germanWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    germanRule(germanMonthDayRepeatPattern, read: germanMonthDayRepeat),
    germanRule(germanIntervalRepeatPattern, read: germanIntervalRepeat),
    germanRule(germanWeekdayRepeatPattern, read: germanWeekdayRepeat),
    germanRule(germanWeeklyOnPattern, read: germanWeeklyOn),
    germanRule(germanOnceEveryPattern, read: germanOnceEvery),
    germanRule(
      #"\#(germanStart)(?:täglich|tagtäglich|jeden\s+(?:tag|morgen|vormittag|mittag|nachmittag|abend)|jede\s+nacht)\#(germanEnd)"#
    ) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
    germanRule(#"\#(germanStart)(?:wöchentlich|jede\s+woche)\#(germanEnd)"#) { _ in weekly(every: nil, on: []) },
    germanRule(#"\#(germanStart)(?:monatlich|jeden\s+monat)\#(germanEnd)"#) { _ in monthly(every: nil, on: nil) },
    germanRule(#"\#(germanStart)(?:jährlich|alljährlich|jedes\s+jahr)\#(germanEnd)"#) { _ in
      Repeat(rule: TaskRecurrenceRule(freq: .yearly))
    },
  ]

  // MARK: - Working days and weekends

  /// "werktags", "werktäglich", "wochentags", "an Werktagen", "an allen
  /// Werktagen", "jeden Werktag", "an Wochentagen", "jeden Wochentag", "an
  /// Arbeitstagen", "jeden Arbeitstag", "Montag bis Freitag", "von Montag bis
  /// Freitag", "Mo-Fr", "Mo bis Fr", "montags bis freitags".
  private static let germanWorkdaysPattern =
    #"\#(germanStart)(?:werktags|werktäglich|wochentags|(?:an|jeden)\s+(?:allen\s+)?(?:werktagen|werktag|wochentagen|wochentag|arbeitstagen|arbeitstag)|(?:von\s+)?(?:montag|mo\.?)\s*(?:bis|[-–—])\s*(?:freitag|fr\.?)|montags\s+bis\s+freitags)\#(germanEnd)"#

  /// "jedes Wochenende", "an jedem Wochenende", "an Wochenenden", "an allen
  /// Wochenenden", "wochenends". "Am Wochenende" names the coming weekend, a
  /// day.
  private static let germanWeekendRepeatPattern =
    #"\#(germanStart)(?:jedes\s+wochenende|an\s+jedem\s+wochenende|an\s+(?:allen\s+)?wochenenden|wochenends)\#(germanEnd)"#

  // MARK: - Day of the month

  /// "am 15. jedes Monats", "zum 1. jedes Monats", "jeden 15. des Monats", "am
  /// 1. eines jeden Monats", "jeden Monat am 15.", "monatlich am 15.". Groups 1
  /// and 2: the day of the month in each form.
  private static let germanMonthDayRepeatPattern =
    #"\#(germanStart)(?:(?:am|zum|an\s+jedem|jeden)\s+(\d{1,2})\.?\s+(?:jedes|des|im|eines\s+jeden)\s+monats?|(?:jeden\s+monat|monatlich)\s+(?:jeweils\s+)?(?:am|zum)\s+(\d{1,2})\.?)\#(germanEnd)"#

  private static func germanMonthDayRepeat(_ match: Match) -> Repeat? {
    (match.group(1) ?? match.group(2)).flatMap(number).flatMap { monthly(every: nil, on: $0) }
  }

  // MARK: - Repeated weekdays

  /// The separator of a list of weekdays: a comma, "und", "sowie", or "&".
  private static let germanListSeparator = #"(?:\s*,\s*|\s+und\s+|\s+sowie\s+|\s*&\s*)"#

  /// The weekdays of a list after "jeden", as a pattern without groups:
  /// names and abbreviations ("Montag, Mi und Freitag"), each maybe after its
  /// own "jeden".
  private static var germanEveryWeekdays: String {
    let day = #"(?:\#(germanWeekdayNames)|\#(germanWeekdayAbbreviations))"#
    return #"\#(day)(?:\#(germanListSeparator)(?:jede[nmrs]?\s+)?\#(day)){0,6}"#
  }

  /// The adverbs of repeated weekdays, as a pattern without groups: "montags",
  /// "montags und donnerstags", "montags, mittwochs und freitags".
  private static var germanWeekdayAdverbs: String {
    let adverb = #"(?:montags|dienstags|mittwochs|donnerstags|freitags|samstags|sonntags|sonnabends)"#
    return #"\#(adverb)(?:\#(germanListSeparator)\#(adverb)){0,6}"#
  }

  /// "jeden Montag", "jeden Montag und Donnerstag", "jede Woche am Montag" is
  /// ``germanWeeklyOnPattern``; "jeden zweiten Montag", "an jedem Montag",
  /// "jeden Mo und Do", "montags", "montags und donnerstags". Groups: 1 the
  /// ordinal "zweiten" (every other), 2 the weekdays after "jeden", 3 the
  /// adverbs. The weekday abbreviations count only after "jeden".
  private static var germanWeekdayRepeatPattern: String {
    #"\#(germanStart)(?:(?:jede[nmrs]?|an\s+jedem)\s+(?:(zweite[nmrs]?)\s+)?(\#(germanEveryWeekdays))|(\#(germanWeekdayAdverbs)))\#(germanEnd)"#
  }

  private static func germanWeekdayRepeat(_ match: Match) -> Repeat? {
    let list = match.group(2) ?? match.group(3) ?? ""
    let days = letterWords(list).compactMap(germanWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: match.group(1) == nil ? nil : 2, on: days)
  }

  /// "jeden zweiten Montag im Monat", "jeden ersten Montag", "jeden dritten
  /// Freitag", "jeden letzten Donnerstag im Monat", "jeden 2. Montag": a
  /// weekday of each month by its place in it. The repeat has no such rule, so
  /// the text stays in the title whole, with no part of it read as a weekday.
  static let germanOrdinalWeekdayPattern =
    #"\#(germanStart)jede[nmrs]?\s+(?:(?:(?:erste|zweite|dritte|vierte|fünfte|letzte)[nmrs]?|\d{1,2}\.)\s+(?:\#(germanWeekdayNames))\s+(?:im|des|jedes)\s+monat(?:s)?|(?:(?:erste|dritte|vierte|fünfte|letzte)[nmrs]?|\d{1,2}\.)\s+(?:\#(germanWeekdayNames)))\#(germanEnd)"#

  /// "jede Woche am Montag", "jede Woche am Montag und Donnerstag". Group 1:
  /// the weekdays.
  private static let germanWeeklyOnPattern =
    #"\#(germanStart)jede\s+woche\s+(?:jeweils\s+)?(?:am|an)\s+((?:\#(germanWeekdayNames))(?:(?:\s*,\s*|\s+und\s+)(?:\#(germanWeekdayNames))){0,6})\#(germanEnd)"#

  private static func germanWeeklyOn(_ match: Match) -> Repeat? {
    let days = letterWords(match.group(1) ?? "").compactMap(germanWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Counted intervals

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// first letters: days, weeks, months, or years. A whole number of weeks
  /// counted in days is a weekly repeat ("alle 14 Tage"), and a unit that is
  /// none returns nil.
  private static func germanRepeat(unit: String, every: Int?) -> Repeat? {
    let key = germanKey(unit)
    if key.hasPrefix("woche") { return weekly(every: every, on: []) }
    if key.hasPrefix("monat") { return monthly(every: every, on: nil) }
    if key.hasPrefix("jahr") { return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every)) }
    guard key.hasPrefix("tag") else { return nil }
    if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  /// "alle 3 Tage", "alle zwei Wochen", "alle 14 Tage", "alle 2 Wochen am
  /// Montag", "alle 2 Wochen montags", "alle 2 Wochen jeden Montag", "jeden
  /// zweiten Tag", "jeden dritten Tag", "jede zweite Woche", "jede zweite
  /// Woche am Montag", "jedes zweite Jahr", "zweiwöchentlich",
  /// "vierzehntägig", "14-tägig", "zweimonatlich", "vierteljährlich",
  /// "halbjährlich". Groups: 1 the count after "alle" and 2 its unit; 3 the
  /// ordinal after "jede" and 4 its unit; 5 the count of a compound ("zwei" of
  /// "zweiwöchentlich") and 6 its unit; 7 "vierteljährlich", "halbjährlich",
  /// or "vierzehntägig"; 8 the weekdays after "am", "an", or "jeden" and 9
  /// the weekday adverbs ("montags und mittwochs") after a weekly interval.
  private static var germanIntervalRepeatPattern: String {
    let units = #"tagen|tage|tag|wochen|woche|monaten|monate|monat|jahren|jahre|jahr"#
    let weekdays =
      #"(?:\s+(?:(?:(?:jeweils\s+)?(?:am|an)|jeden)\s+((?:\#(germanWeekdayNames))(?:(?:\s*,\s*|\s+und\s+)(?:\#(germanWeekdayNames))){0,6})|(\#(germanWeekdayAdverbs))))?"#
    return
      #"\#(germanStart)(?:alle\s+(\d{1,3}|\#(germanCountWords))\s+(\#(units))|jede[nmrs]?\s+(\#(germanOrdinalWords))\s+(tag|woche|monat|jahr)|(zwei|drei|vier|sechs)(wöchentlich|monatlich|jährlich)|(vierteljährlich|halbjährlich|vierzehntägig|14\s*-?\s*tägig))\#(weekdays)\#(germanEnd)"#
  }

  private static func germanIntervalRepeat(_ match: Match) -> Repeat? {
    let weekdays = letterWords(match.group(8) ?? match.group(9) ?? "").compactMap(germanWeekdayIndex)
    var base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      guard let count = germanCount(countText), (1...99).contains(count) else { return nil }
      base = germanRepeat(unit: unit, every: count == 1 ? nil : count)
    } else if let ordinalText = match.group(3), let unit = match.group(4) {
      guard let count = germanOrdinal(ordinalText) else { return nil }
      base = germanRepeat(unit: unit, every: count)
    } else if let countText = match.group(5), let unit = match.group(6) {
      guard let count = germanCount(countText) else { return nil }
      base = germanRepeat(unit: unit, every: count)
    } else if let word = match.group(7) {
      switch germanKey(word) {
      case "vierteljahrlich": base = monthly(every: 3, on: nil)
      case "halbjahrlich": base = monthly(every: 6, on: nil)
      default: base = weekly(every: 2, on: [])
      }
    }
    guard let base else { return nil }
    // A weekday after a weekly interval fixes the repeat's days.
    guard !weekdays.isEmpty else { return base }
    return base.rule.freq == .weekly ? weekly(every: base.rule.interval, on: weekdays) : nil
  }

  // MARK: - Once per

  /// "einmal pro Woche", "einmal im Monat", "einmal im Jahr", "einmal täglich",
  /// "einmal wöchentlich", "einmal die Woche", "einmal am Tag". Groups: 1 the
  /// unit, 2 the adverb.
  private static let germanOnceEveryPattern =
    #"\#(germanStart)einmal\s+(?:(?:pro|je|in\s+der|im|die|am|jede[nrs]?)\s+(tag|woche|monat|jahr)|(täglich|wöchentlich|monatlich|jährlich))\#(germanEnd)"#

  private static func germanOnceEvery(_ match: Match) -> Repeat? {
    if let adverb = match.group(2) {
      switch germanKey(adverb) {
      case "taglich": return germanRepeat(unit: "tag", every: nil)
      case "wochentlich": return germanRepeat(unit: "woche", every: nil)
      case "monatlich": return germanRepeat(unit: "monat", every: nil)
      default: return germanRepeat(unit: "jahr", every: nil)
      }
    }
    return match.group(1).flatMap { germanRepeat(unit: $0, every: nil) }
  }
}
