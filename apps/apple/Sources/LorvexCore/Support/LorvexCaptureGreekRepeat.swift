import Foundation

extension LorvexCaptureVocabulary {
  // The Greek repeat rules: working days, weekends, a span of weekdays, a day of
  // the month, counted intervals, repeated weekdays, cadence phrases, and the
  // adverbs at the end of a line. The vocabulary's other words are in
  // ``greek``.

  /// The repeat rules in the order they are tried: the working days, the
  /// weekend, and a day of the month before the rules for every day and every
  /// month, which would leave "τις καθημερινές" or the day's number in the
  /// title; a span of weekdays and the counted intervals before the weekday
  /// rule, so "κάθε Δευτέρα έως Πέμπτη" and "κάθε δεύτερη Παρασκευή" are read
  /// whole; the weekday rule before "κάθε εβδομάδα", so "κάθε εβδομάδα
  /// Παρασκευή" is read whole.
  static let greekRepeatRules: [Rule<Repeat>] = [
    Rule(pattern: greekWorkdaysPattern, read: greekWorkdays),
    Rule(pattern: greekWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    Rule(pattern: greekMonthDayRepeatPattern, read: greekMonthDayRepeat),
    Rule(pattern: greekWeekdaySpanPattern, read: greekWeekdaySpan),
    Rule(pattern: greekIntervalRepeatPattern, read: greekIntervalRepeat),
    Rule(pattern: greekWeekdayRepeatPattern, read: greekWeekdayRepeat),
    Rule(pattern: greekEveryUnitPattern, read: greekEveryUnit),
    Rule(pattern: greekAdverbPattern, read: greekAdverb),
  ]

  // MARK: - Words shared by the rules

  /// The separator of a list of weekdays: a comma, "και", "κι", or "&".
  private static let greekListSeparator = #"(?:\s*,\s*(?:και\s+)?|\s+(?:και|κι)\s+|\s*&\s*)"#

  /// The article a weekday may take: "την Παρασκευή", "το Σάββατο".
  private static let greekDayArticle = #"(?:(?:την|τη|το)\s+)?"#

  /// A weekday name in a repeat, as a pattern without groups. An ordinal noun
  /// after a name that is also an ordinal ("κάθε τρίτη μέρα") makes it a count,
  /// not a day.
  private static var greekRepeatName: String {
    #"(?:\#(greekWeekdayNames))(?![\p{L}\p{M}\p{N}])(?!\s+(?:\#(greekOrdinalNouns))(?![\p{L}\p{M}]))"#
  }

  /// The weekday names of a list, as a pattern without groups: "Δευτέρα", "Τρίτη
  /// και Πέμπτη", "Δευτέρα, Τετάρτη και Παρασκευή", each name maybe after its
  /// own "κάθε" or article.
  private static var greekNamesList: String {
    let day = greekRepeatName
    return #"\#(day)(?:\#(greekListSeparator)(?:καθε\s+)?\#(greekDayArticle)\#(day)){0,6}"#
  }

  /// The plural weekday names of a list, as a pattern without groups: "Δευτέρες",
  /// "Δευτέρες και Πέμπτες", "Δευτέρες και τα Σάββατα".
  private static var greekPluralList: String {
    let plural = #"(?:\#(alternation(of: greekWeekdayPlurals)))(?![\p{L}\p{M}\p{N}])"#
    let article = #"(?:(?:τισ|στισ|τα|στα)\s+)?"#
    return #"\#(plural)(?:\#(greekListSeparator)\#(article)\#(plural)){0,6}"#
  }

  /// The weekdays a matched list names, 0 = Sunday.
  private static func greekRepeatWeekdays(_ list: String) -> [Int] {
    letterWords(list).compactMap { greekWeekdayIndex($0) }
  }

  // MARK: - Working days and weekends

  /// "τις καθημερινές", "στις καθημερινές μέρες", "τις εργάσιμες ημέρες", "κάθε
  /// εργάσιμη μέρα", "κάθε καθημερινή", "Δευτέρα-Παρασκευή", "Δευτέρα έως
  /// Παρασκευή", "από Δευτέρα μέχρι Παρασκευή". "Καθημερινές" and "εργάσιμες"
  /// are adjectives too ("τις καθημερινές δουλειές", "τις εργάσιμες ώρες"), so
  /// without a day noun they are read only where the line goes on with nothing
  /// or with a word that can follow a detail. A span of Monday to Friday after
  /// "κάθε" is read by the span rule. Groups: 1 the adjective after "τις", 2
  /// "καθημερινή" after "κάθε".
  private static var greekWorkdaysPattern: String {
    let article = greekDayArticle
    let monday = #"(?:δευτερα|δευ\.?)"#
    let friday = #"(?:παρασκευη|παρ\.)"#
    let dashed = #"(?<!καθε\s)(?:απο\s+)?\#(article)\#(monday)\s*[-–—]\s*\#(article)\#(friday)"#
    let worded = #"(?<!καθε\s)(?:απο\s+)?\#(article)\#(monday)\s+(?:εωσ|μεχρι|ωσ)\s+\#(article)\#(friday)"#
    let withNoun = #"(?:τισ|στισ)\s+(?:εργασιμεσ|καθημερινεσ)\s+(?:μερεσ|ημερεσ)"#
    let everyWorkday = #"καθε\s+εργασιμη\s+(?:μερα|ημερα)"#
    let adjective = #"(?:τισ|στισ)\s+(εργασιμεσ|καθημερινεσ)"#
    let everyWeekday = #"καθε\s+(καθημερινη)"#
    return
      #"\#(greekStart)(?:\#(withNoun)|\#(everyWorkday)|\#(adjective)|\#(everyWeekday)|\#(dashed)|\#(worded))\#(greekEnd)"#
  }

  private static func greekWorkdays(_ match: Match) -> Repeat? {
    if match.group(1) != nil || match.group(2) != nil, !greekFollowsAsDetail(match) { return nil }
    return workdays
  }

  /// "τα Σαββατοκύριακα", "στα Σαββατοκύριακα", "κάθε Σαββατοκύριακο". "Το
  /// Σαββατοκύριακο" alone names the coming weekend, a day.
  private static let greekWeekendRepeatPattern =
    #"\#(greekStart)(?:(?:τα|στα)\s+σαββατοκυριακα|καθε\s+σαββατοκυριακο)\#(greekEnd)"#

  // MARK: - Day of the month

  /// "κάθε μήνα στις 15", "κάθε μήνα την 15η", "στις 15 κάθε μήνα", "στις 15 του
  /// κάθε μήνα", "κάθε 15 του μήνα", "κάθε 1η του μήνα", "κάθε πρώτη του μήνα":
  /// a day of every month. The number is a day only where no unit or counted
  /// noun follows it and no minutes or fraction does ("κάθε μήνα στις 15:30" is
  /// a time). Groups: 1 the day after "κάθε μήνα", 2 the day before "κάθε μήνα",
  /// 3 the day after "κάθε", 4 "πρώτη".
  private static var greekMonthDayRepeatPattern: String {
    let lead = #"(?:στισ|στην|στη|την|τη)"#
    let day = #"(\d{1,2})(?:ησ|η)?"#
    let after = #"καθε\s+μηνα\s+\#(lead)\s+\#(day)\#(greekNoMoreDigits)\#(greekNoCountedUnitAfter)"#
    let before = #"\#(lead)\s+\#(day)\s+(?:του\s+)?καθε\s+μηνα"#
    let ofMonth = #"καθε\s+(?:(\d{1,2})(?:ησ|η)?|(πρωτη))\s+του\s+(?:μηνα|μηνοσ)"#
    return #"\#(greekStart)(?:\#(after)|\#(before)|\#(ofMonth))\#(greekEnd)"#
  }

  private static func greekMonthDayRepeat(_ match: Match) -> Repeat? {
    if match.group(4) != nil { return monthly(every: nil, on: 1) }
    guard let day = (match.group(1) ?? match.group(2) ?? match.group(3)).flatMap(number) else { return nil }
    return monthly(every: nil, on: day)
  }

  // MARK: - Span of weekdays

  /// "κάθε Δευτέρα έως Πέμπτη", "κάθε Δευτέρα-Παρασκευή", "κάθε Παρασκευή έως
  /// Δευτέρα": every day from the first weekday through the last. Groups: 1 the
  /// first weekday, 2 the last.
  private static var greekWeekdaySpanPattern: String {
    let name = #"(?:\#(greekWeekdayNames))"#
    let article = greekDayArticle
    return
      #"\#(greekStart)καθε\s+\#(article)(\#(name))(?:\s*[-–—]\s*|\s+(?:εωσ|μεχρι|ωσ)\s+)\#(article)(\#(name))\#(greekEnd)"#
  }

  /// Monday to Friday is the working week; any other span repeats on each of its
  /// days, going on through Sunday when it wraps ("Παρασκευή έως Δευτέρα" is
  /// Friday, Saturday, Sunday, and Monday).
  private static func greekWeekdaySpan(_ match: Match) -> Repeat? {
    guard let firstText = match.group(1), let lastText = match.group(2),
      let first = greekWeekdayIndex(firstText), let last = greekWeekdayIndex(lastText), first != last
    else { return nil }
    if first == 1, last == 5 { return workdays }
    var days = [first]
    var day = first
    while day != last {
      day = (day + 1) % 7
      days.append(day)
    }
    return weekly(every: nil, on: days)
  }

  // MARK: - Counted intervals

  /// The repeat every `every` (nil for each) of the unit a word names, by its
  /// first letters: days, weeks, months, or years. A whole number of weeks
  /// counted in days is a weekly repeat ("κάθε 14 μέρες"), and a word that
  /// names no unit returns nil.
  private static func greekRepeat(unit: String, every: Int?) -> Repeat? {
    let key = greekKey(unit)
    if key.hasPrefix("εβδ") || key.hasPrefix("βδο") { return weekly(every: every, on: []) }
    if key.hasPrefix("μην") { return monthly(every: every, on: nil) }
    if key.hasPrefix("χρον") || key.hasPrefix("ετ") {
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
    guard key.hasPrefix("μερ") || key.hasPrefix("ημερ") else { return nil }
    if let count = every, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
  }

  /// The count an ordinal word before a unit names: "κάθε δεύτερη μέρα" is every
  /// second day.
  private static func greekOrdinal(_ word: String) -> Int? {
    switch greekKey(word) {
    case "δευτερη", "δευτερο": 2
    case "τριτη", "τριτο": 3
    case "τεταρτη", "τεταρτο": 4
    case "πεμπτη", "πεμπτο": 5
    default: nil
    }
  }

  /// The unit a word names, as a class: 0 days, 1 weeks, 2 months, 3 years.
  private static func greekUnitClass(_ unit: String) -> Int? {
    let key = greekKey(unit)
    if key.hasPrefix("μερ") || key.hasPrefix("ημερ") { return 0 }
    if key.hasPrefix("εβδ") || key.hasPrefix("βδο") { return 1 }
    if key.hasPrefix("μην") { return 2 }
    if key.hasPrefix("χρον") || key.hasPrefix("ετ") { return 3 }
    return nil
  }

  /// "κάθε δύο μέρες", "κάθε 2 εβδομάδες", "κάθε τρεις μήνες", "κάθε 2 χρόνια",
  /// "κάθε δεύτερη μέρα", "κάθε τρίτη εβδομάδα", "κάθε δεύτερο μήνα", "μέρα παρά
  /// μέρα", "εβδομάδα παρά εβδομάδα", "μία φορά την εβδομάδα", "μία φορά τον
  /// μήνα", each maybe before a weekday ("κάθε 2 εβδομάδες την Παρασκευή"), and
  /// "κάθε δεύτερη Παρασκευή" (every other Friday). "Δύο φορές την εβδομάδα"
  /// counts times in a week, which no repeat says, so it stays. Groups: 1 and 2
  /// the count and the unit; 3 and 4 an ordinal and its unit (a day or a week);
  /// 5 and 6 an ordinal and its unit (a month or a year); 7 and 8 the units
  /// around "παρά"; 9 the unit after "μία φορά"; 10 the weekday names after the
  /// interval; 11 the weekday names after "κάθε δεύτερη".
  private static var greekIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(greekCountWords))"#
    let units = #"μερεσ|ημερεσ|εβδομαδεσ|βδομαδεσ|μηνεσ|χρονια|ετη"#
    let unit = #"μερα|ημερα|εβδομαδα|βδομαδα|μηνα|χρονο"#
    let counted = #"καθε\s+\#(count)\s+(\#(units))"#
    let ordinalFeminine = #"καθε\s+(δευτερη|τριτη|τεταρτη|πεμπτη)\s+(μερα|ημερα|εβδομαδα|βδομαδα)"#
    let ordinalNeuter = #"καθε\s+(δευτερο|τριτο|τεταρτο|πεμπτο)\s+(μηνα|χρονο|ετοσ)"#
    let alternate = #"(\#(unit))\s+παρα\s+(\#(unit))"#
    let perPeriod =
      #"(?:μια|ενα|1)\s+φορα\s+(?:την|τη|τον|το|ανα)\s+(εβδομαδα|βδομαδα|μηνα|χρονο|μερα|ημερα)"#
    let tail = #"(?:\s+\#(greekDayArticle)(\#(greekNamesList)))?"#
    let everyOther = #"καθε\s+(?:δευτερη|δευτερο)\s+(\#(greekNamesList))"#
    return
      #"\#(greekStart)(?:(?:\#(counted)|\#(ordinalFeminine)|\#(ordinalNeuter)|\#(alternate)|\#(perPeriod))\#(tail)|\#(everyOther))\#(greekEnd)"#
  }

  private static func greekIntervalRepeat(_ match: Match) -> Repeat? {
    if let list = match.group(11) {
      let days = greekRepeatWeekdays(list)
      return days.isEmpty ? nil : weekly(every: 2, on: days)
    }
    var base: Repeat?
    if let countText = match.group(1), let unit = match.group(2) {
      guard let count = greekCount(countText), (2...99).contains(count) else { return nil }
      base = greekRepeat(unit: unit, every: count)
    } else if let ordinal = match.group(3) ?? match.group(5), let unit = match.group(4) ?? match.group(6) {
      guard let count = greekOrdinal(ordinal) else { return nil }
      base = greekRepeat(unit: unit, every: count)
    } else if let first = match.group(7), let second = match.group(8) {
      guard greekUnitClass(first) == greekUnitClass(second) else { return nil }
      base = greekRepeat(unit: first, every: 2)
    } else if let unit = match.group(9) {
      base = greekRepeat(unit: unit, every: nil)
    }
    guard let base else { return nil }
    // A weekday after a weekly interval fixes the repeat's days.
    let weekdays = greekRepeatWeekdays(match.group(10) ?? "")
    guard !weekdays.isEmpty else { return base }
    return base.rule.freq == .weekly ? weekly(every: base.rule.interval, on: weekdays) : nil
  }

  // MARK: - Repeated weekdays

  /// "κάθε Δευτέρα", "κάθε εβδομάδα Παρασκευή", "κάθε Δευτέρα και Πέμπτη", "τις
  /// Δευτέρες", "τις Δευτέρες και τις Πέμπτες", "τα Σάββατα", "στα Σάββατα".
  /// Groups: 1 the weekdays after "κάθε", 2 the plural weekdays.
  private static var greekWeekdayRepeatPattern: String {
    let article = greekDayArticle
    return
      #"\#(greekStart)(?:καθε\s+(?:(?:εβδομαδα|βδομαδα)\s+)?\#(article)(\#(greekNamesList))|(?:τισ|στισ|τα|στα)\s+(\#(greekPluralList)))\#(greekEnd)"#
  }

  private static func greekWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = greekRepeatWeekdays(match.group(1) ?? match.group(2) ?? "")
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Cadence phrases

  /// "κάθε μέρα", "κάθε εβδομάδα", "κάθε μήνα", "κάθε χρόνο", "κάθε πρωί", "κάθε
  /// βράδυ", "κάθε απόγευμα". Group 1: the unit or the part of the day after
  /// "κάθε". "Για κάθε μέρα" and "όπως κάθε μέρα" are not such phrases: they say
  /// "for each day" and "like every day".
  private static var greekEveryUnitPattern: String {
    #"\#(greekStart)\#(greekNotAfterWord("για|σαν|οπωσ"))καθε\s+(μερα|ημερα|εβδομαδα|βδομαδα|μηνα|χρονο|ετοσ|πρωι|μεσημερι|απογευμα|βραδυ|νυχτα)\#(greekEnd)"#
  }

  private static func greekEveryUnit(_ match: Match) -> Repeat? {
    guard let word = match.group(1) else { return nil }
    return greekRepeat(unit: word, every: nil) ?? Repeat(rule: TaskRecurrenceRule(freq: .daily))
  }

  // MARK: - Adverbs

  /// "ημερησίως", "εβδομαδιαίως", "μηνιαίως", "ετησίως", "καθημερινώς" anywhere;
  /// "καθημερινά", "εβδομαδιαία", "μηνιαία", "ετήσια" at the end of the line,
  /// opening the line before a colon or a comma, or before "στις"; "σε
  /// καθημερινή βάση", "σε εβδομαδιαία βάση", "σε μηνιαία βάση", "σε ετήσια
  /// βάση". The neuter forms are adjectives too ("εβδομαδιαία αναφορά", "ετήσια
  /// άδεια"), and the end of the line is where they say how a task repeats.
  /// Groups: 1 the adverb, 2 the word at the end, 3 the word that opens the
  /// line, 4 the word before "στις", 5 the word before "βάση".
  private static var greekAdverbPattern: String {
    let adverbs = #"ημερησιωσ|εβδομαδιαιωσ|μηνιαιωσ|ετησιωσ|καθημερινωσ"#
    let forms = #"καθημερινα|εβδομαδιαια|μηνιαια|ετησια"#
    let basis = #"καθημερινη|ημερησια|εβδομαδιαια|μηνιαια|ετησια"#
    let atEnd = #"\#(greekStart)(\#(forms))\#(greekEnd)(?=[\s.!]*$)"#
    let opening = #"^\s*(\#(forms))\#(greekEnd)(?=\s*[:,，：])"#
    let beforeClock = #"\#(greekStart)(\#(forms))\#(greekEnd)(?=\s+(?:στισ|στη|στην|ωρα)(?![\p{L}\p{M}]))"#
    let onBasis = #"\#(greekStart)σε\s+(\#(basis))\s+βαση\#(greekEnd)"#
    return #"\#(greekStart)(\#(adverbs))\#(greekEnd)|\#(atEnd)|\#(opening)|\#(beforeClock)|\#(onBasis)"#
  }

  private static func greekAdverb(_ match: Match) -> Repeat? {
    guard let word = (1...5).lazy.compactMap({ match.group($0) }).first.map(greekKey) else { return nil }
    if word.hasPrefix("εβδ") { return weekly(every: nil, on: []) }
    if word.hasPrefix("μην") { return monthly(every: nil, on: nil) }
    if word.hasPrefix("ετ") { return Repeat(rule: TaskRecurrenceRule(freq: .yearly)) }
    return Repeat(rule: TaskRecurrenceRule(freq: .daily))
  }
}
