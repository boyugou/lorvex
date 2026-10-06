import Foundation

extension LorvexCaptureVocabulary {
  // The Greek day rules: the due day, the planned day, the date ranges, and the
  // past days and named holidays that stay in the title. The vocabulary's other
  // words are in ``greek``.

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let greekNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  // MARK: - Weekdays and parts of the day

  /// Each weekday's name as the reading form leaves it, Sunday first.
  private static let greekWeekdayStems = [
    "κυριακη", "δευτερα", "τριτη", "τεταρτη", "πεμπτη", "παρασκευη", "σαββατο",
  ]

  /// Each weekday's plural, Sunday first: "τις Δευτέρες", "τα Σάββατα".
  static let greekWeekdayPlurals = [
    "κυριακεσ", "δευτερεσ", "τριτεσ", "τεταρτεσ", "πεμπτεσ", "παρασκευεσ", "σαββατα",
  ]

  /// The weekday abbreviations that read with or without a period, and the two
  /// that read only with one ("Παρ." and "Κυρ."): "παρ" and "κυρ" are words of
  /// their own.
  private static let greekWeekdayAbbreviations = ["δευ", "τρι", "τετ", "πεμ", "σαβ"]

  /// The weekday names, as a pattern without groups: the full names and the
  /// abbreviations.
  static var greekWeekdayNames: String {
    #"\#(alternation(of: greekWeekdayStems))|(?:\#(alternation(of: greekWeekdayAbbreviations)))\.?|(?:παρ|κυρ)\."#
  }

  private static let greekWeekdayWords: [String: Int] = {
    var words: [String: Int] = ["κυρ": 0, "δευ": 1, "τρι": 2, "τετ": 3, "πεμ": 4, "παρ": 5, "σαβ": 6]
    for (index, stem) in greekWeekdayStems.enumerated() { words[stem] = index }
    for (index, plural) in greekWeekdayPlurals.enumerated() { words[plural] = index }
    return words
  }()

  /// The weekday a matched word names, 0 = Sunday: a full name, a plural, or an
  /// abbreviation with or without its period. The word is in the reading form.
  static func greekWeekdayIndex(_ word: String) -> Int? {
    var key = greekKey(word)
    if key.hasSuffix(".") { key.removeLast() }
    return greekWeekdayWords[key]
  }

  /// The names that are also ordinals ("την τρίτη φορά"): they name a day only
  /// with the article or a word that makes them one, or capitalized.
  private static let greekOrdinalNames: Set<String> = ["τριτη", "τεταρτη", "πεμπτη"]

  /// Whether a weekday word, a full name or an abbreviation, is also a first
  /// name: Παρασκευή and Κυριακή, and "Παρ." and "Κυρ.".
  private static func greekIsPersonWeekday(_ word: String) -> Bool {
    greekWeekdayIndex(word).map { greekPersonWeekdays.contains($0) } ?? false
  }

  /// The weekdays whose names are also first names ("με την Κυριακή"), Sunday
  /// and Friday, in the numbering of ``greekWeekdayIndex(_:)``.
  private static let greekPersonWeekdays: Set<Int> = [0, 5]

  /// A part of the day a day word or an hour may carry.
  enum GreekPartOfDay {
    case morning, noon, afternoon, evening, night
  }

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: "το πρωί", "το μεσημέρι", "το απόγευμα", "το βράδυ", "τη
  /// νύχτα", each with or without its article.
  static let greekPartWords = #"(?:το\s+|τη\s+)?(?:πρωι|μεσημερι|απογευμα|βραδυ|νυχτα)"#

  /// The same, with the space that sets it apart from the word before it, as an
  /// optional pattern without groups.
  static let greekPartTail = #"(?:\s+\#(greekPartWords))?"#

  /// The part of the day a matched word or phrase names: "το πρωί", "βράδυ",
  /// "απόγευμα".
  static func greekPartOfDay(_ text: String) -> GreekPartOfDay? {
    let key = greekPhrase(text)
    if key.contains("πρωι") { return .morning }
    if key.contains("μεσημερι") { return .noon }
    if key.contains("απογευμα") { return .afternoon }
    if key.contains("βραδυ") { return .evening }
    if key.contains("νυχτα") { return .night }
    return nil
  }

  /// Whether a matched day phrase names an evening or a night, which puts a
  /// clock time written without a part of the day in that evening.
  private static func greekNamesEvening(_ tokens: [String]) -> Bool {
    tokens.contains { ["βραδυ", "νυχτα", "αποψε"].contains($0) }
  }

  // MARK: - Months

  /// Each month's names (the genitive that follows a day number, and the
  /// colloquial one) and its abbreviation, January first.
  private static let greekMonthRows: [(names: [String], abbreviation: String)] = [
    (["ιανουαριου", "γεναρη"], "ιαν"), (["φεβρουαριου", "φλεβαρη"], "φεβ"), (["μαρτιου", "μαρτη"], "μαρ"),
    (["απριλιου", "απριλη"], "απρ"), (["μαιου", "μαη"], "μαι"), (["ιουνιου", "ιουνη"], "ιουν"),
    (["ιουλιου", "ιουλη"], "ιουλ"), (["αυγουστου"], "αυγ"), (["σεπτεμβριου", "σεπτεμβρη"], "σεπ"),
    (["οκτωβριου", "οκτωβρη"], "οκτ"), (["νοεμβριου", "νοεμβρη"], "νοε"), (["δεκεμβριου", "δεκεμβρη"], "δεκ"),
  ]

  /// The month names and abbreviations, as a pattern without groups. A month is
  /// read only after its day number, so none of the abbreviations is taken for a
  /// word of the title.
  static var greekMonthNames: String {
    alternation(of: greekMonthRows.flatMap(\.names) + greekMonthRows.map(\.abbreviation))
  }

  /// The month a word names, 0 = January: a name or an abbreviation, maybe with
  /// its period.
  private static func greekMonthIndex(_ word: String) -> Int? {
    var key = greekKey(word)
    if key.hasSuffix(".") { key.removeLast() }
    return greekMonthRows.firstIndex { $0.names.contains(key) || $0.abbreviation == key }
  }

  // MARK: - Dates

  /// "15 Οκτωβρίου", "15 του Οκτωβρίου", "1η Μαΐου", "25ης Μαρτίου", "15 Οκτ.":
  /// a day with its month, maybe with a year. A month needs its day number
  /// ("Οκτωβρίου" alone is no date).
  private static var greekMonthDate: String {
    #"(?<![\p{N}.,:/-])\d{1,2}(?:ησ|η)?\s+(?:του\s+)?(?:\#(greekMonthNames))(?![\p{L}\p{M}])\.?(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// "15.10.2026", "15.10.26", "15.10.": a day and a month in digits with the
  /// dot after the month, maybe with a year. A number that goes on with more
  /// digits or dots ("1.10.2.5", "192.168.1.1") is none.
  private static let greekNumericDate =
    #"(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N})|\d{2}(?!\p{N}))?(?![\p{N}]|[.,/]\p{N})"#

  /// "15/10/2026", "15-10-2026", "15/10/26": a day, a month, and a year in
  /// digits, which nothing else reads as.
  private static let greekSlashDate =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// What may not follow a number that is a date or an hour only by its shape: a
  /// unit or a counted noun, which would make it an amount or a fraction ("1/2
  /// κιλό", "3/4 ποτήρι", "στις 8 άτομα").
  static let greekNoCountedUnitAfter =
    #"(?!\s*(?:ωρα|ωρεσ|λεπτα|λεπτο|μερα|μερεσ|ημερα|ημερεσ|εβδομαδα|εβδομαδεσ|βδομαδα|βδομαδεσ|μηνα|μηνεσ|χρονο|χρονια|ετη|φορα|φορεσ|ατομα|ατομο|τεμαχια|τεμαχιο|κομματια|κομματι|πακετο|πακετα|κουτια|κουτι|μπουκαλια|μπουκαλι|ποτηρι|ποτηρια|φλιτζανι|φλιτζανια|κιλα|κιλο|γραμμαρια|γρ|λιτρα|λιτρο|μετρα|μετρο|εκ|χλμ|ετων|χρονων|ευρω|δολαρια|σελιδα|σελιδεσ|κεφαλαιο|κεφαλαια|μαθημα|μαθηματα|ταξη|οροφο|βαθμοι|βαθμο|βαθμουσ|μοναδεσ|ασκηση|ασκησεισ|δωματιο|δωματια|x)(?![\p{L}\p{N}\p{M}]))"#

  /// "15.10", "15/10", "15-10": a day and a month in digits with no year, which
  /// a date reads only where something introduces it, since "15.10" is as often
  /// a time and "1/2" a fraction.
  private static let greekLooseDate =
    #"(?<![\p{N}.,:/-])\d{1,2}(?:\.\d{1,2}|[/-]\d{1,2})(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})\#(greekNoCountedUnitAfter)"#

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, maybe with the article and a comma ("Παρασκευή 16
  /// Οκτωβρίου", "την Παρασκευή, 16/10/2026").
  private static var greekWeekdayBeforeDate: String {
    #"(?:(?:(?:την|τη|το)\s+)?(?:\#(greekWeekdayNames))\s*,?\s+)"#
  }

  /// The words that introduce a date, as a pattern without groups.
  private static let greekDateLead = #"(?:(?:στισ|στην|στη|τισ|την|τη)\s+)"#

  /// The dates a day may be written as without anything introducing them: a
  /// day with its month, or numbers with a year or the closing dot.
  private static var greekStrictDates: String {
    "\(greekMonthDate)|\(greekNumericDate)|\(greekSlashDate)"
  }

  /// The words after which a number with dots or slashes is a numbered item of
  /// the title, not a date: "κεφάλαιο 1.5", "έκδοση 2.3.4", "σκορ 3-1". A word
  /// counts only as a whole word, so "Slav 15.10.2026" still has its date.
  private static let greekNumberingPattern =
    #"(?<![\p{L}\p{M}])(?:κεφαλαιο|ενοτητα|σελιδα|σελ\.?|αριθμοσ|αρ\.?|εκδοση|εκδ\.?|βημα|επιπεδο|αιθουσα|γραμμη|ταξη|ομαδα|σκορ|αποτελεσμα|ticket|build|bug|task|διαφανεια|slide|μαθημα|ασκηση|θεμα|ερωτηση|εργασια|δωματιο|version|v|no\.?)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func greekFollowsNumbering(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(greekNumberingPattern) else { return false }
    let before = greekTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  /// A written-out date and whether it is written in digits only.
  private struct GreekWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``greekPhrase(_:)`` leaves
  /// it: nil when it names no date or a day or month the calendar lacks.
  private static func greekExplicitDate(_ key: String) -> GreekWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})(?:ησ|η)?\s+(?:του\s+)?([α-ω]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = greekMonthIndex(String(found.output.2))
    {
      return GreekWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-]?(\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2), (1...12).contains(month),
      (1...31).contains(day)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return GreekWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    return nil
  }

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5 Μαΐου", "30 Μαΐου 2027")
  /// or a day alone ("3"), maybe after "στις" or an article. The end of a range
  /// may follow its dash directly ("3-5 Μαΐου"), which a date alone may not.
  private static func greekRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let month =
      #"\d{1,2}(?:ησ|η)?\s+(?:του\s+)?(?:\#(greekMonthNames))(?![\p{L}\p{M}])\.?(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
    let bare = #"\d{1,2}(?:ησ|η)?\#(greekNoMoreDigits)"#
    return #"\#(lookbehind)\#(greekDateLead)?(?:\#(month)|\#(bare))"#
  }

  /// "3-5 Μαΐου", "3 Μαΐου - 5 Μαΐου", "από 3 έως 5 Μαΐου", "από τις 3 μέχρι τις 5
  /// Μαΐου", "από 30 Μαΐου έως 2 Ιουνίου", each maybe with a year after the end.
  /// Groups: 1 the opening word, 2 the start, 3 a dash between the sides, 4 the
  /// word that means "to" between them, 5 the end.
  static var greekDateRangePattern: String {
    #"\#(greekStart)(?:(απο)\s+)?(\#(greekRangeSide(isEnd: false)))(?:\s*([-–—])\s*|\s+(εωσ|μεχρι|ωσ)\s+)(\#(greekRangeSide(isEnd: true)))\#(greekEnd)"#
  }

  static func greekDateRange(_ match: Match) -> DayRangeReading? {
    slavicDateRange(match, side: greekRangeDate)
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func greekRangeDate(_ text: String) -> ExplicitDate? {
    let key = greekPhrase(text)
    if let found = greekExplicitDate(key), !found.isNumeric { return found.date }
    guard let day = key.firstMatch(of: /(\d{1,2})(?:ησ|η)?$/), let value = number(day.output.1), (1...31).contains(value)
    else { return nil }
    return ExplicitDate(day: value)
  }

  // MARK: - Weekday range

  /// "από Παρασκευή έως Κυριακή", "από την Παρασκευή μέχρι την Κυριακή",
  /// "Παρασκευή έως Κυριακή", "Παρασκευή-Κυριακή", "Παρ.-Κυρ.": a span of
  /// weekdays, joined by a dash or by "έως", "μέχρι", or "ως", with or without
  /// "από" before it. Groups: 1 the opening word, 2 the first weekday, 3 a dash,
  /// 4 the word that means "to", 5 the last weekday. "Κάθε Δευτέρα έως Πέμπτη"
  /// is a repeat, which the range does not take, and "από τρίτη έως πέμπτη
  /// τάξη" counts grades: an ordinal noun after the last name makes it no span.
  static var greekWeekdayRangePattern: String {
    let name = greekWeekdayNames
    let article = #"(?:(?:την|τη|το)\s+)?"#
    let noOrdinalNoun = #"(?!\s+(?:\#(greekOrdinalNouns))(?![\p{L}\p{M}]))"#
    return
      #"(?<!καθε\s)\#(greekStart)(?:(απο)\s+)?\#(article)(\#(name))(?:\s*([-–—])\s*|\s+(εωσ|μεχρι|ωσ)\s+)\#(article)(\#(name))\#(greekEnd)\#(noOrdinalNoun)"#
  }

  /// A span of weekdays plans the coming first day and is due on the last day
  /// after it, so on a Tuesday "από Παρασκευή έως Κυριακή" runs from Friday to
  /// the Sunday after it. Monday to Friday is the working week, which the
  /// repeat rules read, and a span from a day to itself is no span.
  static func greekWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(2), let lastWord = match.group(5),
      let first = greekWeekdayIndex(firstWord), let last = greekWeekdayIndex(lastWord),
      first != last, !(first == 1 && last == 5)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  // MARK: - Past days, named holidays, and ordinal weekdays

  /// "χθες", "χθες το βράδυ", "προχθές", "την περασμένη Παρασκευή", "την
  /// προηγούμενη εβδομάδα", "το περασμένο Σαββατοκύριακο", each with the clock
  /// time that follows it: a day or a week that is past, which names no day a
  /// task can be set for. It stays in the title whole, so the weekday or the
  /// hour inside it is not read.
  static var greekPastPattern: String {
    let name = greekWeekdayNames
    let clock = #"(?:\s+(?:(?:στισ|ωρα)\s+)?\d{1,2}(?:[.:]\d{2})?)?"#
    let past = #"(?:περασμενη|περασμενο|προηγουμενη|προηγουμενο)"#
    return
      #"\#(greekStart)(?:(?:χθεσ|εχθεσ|χτεσ|προχθεσ|προχτεσ)(?:\s+\#(greekPartWords))?|(?:την|τη|το)\s+\#(past)\s+(?:(?:\#(name))(?:\s+\#(greekPartWords))?|εβδομαδα|βδομαδα|σαββατοκυριακο|νυχτα|βραδυ))\#(clock)\#(greekEnd)"#
  }

  /// "Μεγάλη Παρασκευή", "Μεγάλο Σάββατο", "Καθαρά Δευτέρα", "Μαύρη Παρασκευή",
  /// "Κυριακή του Πάσχα", "Δευτέρα του Αγίου Πνεύματος", and an ordinal weekday
  /// of the month ("κάθε πρώτη Δευτέρα του μήνα", "την τελευταία Παρασκευή",
  /// "κάθε δεύτερη Δευτέρα του μήνα"): holidays and days that are not the plain
  /// weekday their last word names. They stay in the title whole. "Κάθε
  /// δεύτερη Παρασκευή" without "του μήνα" is every other Friday, which the
  /// repeat rules read.
  static var greekNamedDayPattern: String {
    let name = greekWeekdayNames
    let feast =
      #"πασχα|βαιων|θωμα|ορθοδοξιασ|αποκριασ|τυροφαγου|μυροφορων|παραλυτου|σαμαρειτιδοσ|τυφλου|πεντηκοστησ|αγιου\s+πνευματοσ|ασωτου|αγιων\s+πατερων|σταυροπροσκυνησησ|διακαινησιμου|λαμπρησ|αναστασησ|χριστουγεννων|θεοφανειων"#
    let ordinals =
      #"πρωτη|δευτερη|τριτη|τεταρτη|πεμπτη|τελευταια|πρωτο|δευτερο|τριτο|τεταρτο|πεμπτο|τελευταιο"#
    let otherOrdinals = #"πρωτη|τριτη|τεταρτη|πεμπτη|τελευταια|πρωτο|τριτο|τεταρτο|πεμπτο|τελευταιο"#
    let ofMonth = #"\s+του\s+(?:μηνα|μηνοσ)"#
    let ordinal =
      #"(?:(?:την|τη|το)\s+(?:\#(ordinals))|καθε\s+(?:\#(otherOrdinals)))\s+(?:\#(name))(?:\#(ofMonth))?|(?:καθε\s+)?(?:\#(ordinals))\s+(?:\#(name))\#(ofMonth)"#
    return
      #"\#(greekStart)(?:μεγαλη\s+(?:δευτερα|τριτη|τεταρτη|πεμπτη|παρασκευη)|μεγαλο\s+σαββατο|καθαρα\s+δευτερα|μαυρη\s+παρασκευη|(?:\#(name))\s+(?:του|των|τησ)\s+(?:\#(feast))|\#(ordinal))\#(greekEnd)"#
  }

  // MARK: - Words around a weekday

  /// The nouns an ordinal weekday name goes with ("την τρίτη φορά", "Τρίτη
  /// θέση"), which make it an ordinal. "Ώρα" followed by a digit is the clock
  /// ("Τρίτη ώρα 15:00").
  static let greekOrdinalNouns =
    #"φορα|θεση|εβδομαδα|βδομαδα|μερα|ημερα|ωρα(?!\s*\d)|ταξη|σειρα|γραμμη|σελιδα|ενοτητα|ασκηση|δοση|περιοδοσ|γενια|βαρδια|παρτιδα|ομαδα|κατηγορια|προσπαθεια|εκδοση|διαδρομη|επιλογη|συνεδρια|δεκαετια|ηλικια|εξεταση|φαση|μετρηση|προταση|ερωτηση|επαναληψη|δοκιμη|ομαδικη|κατασταση|λιστα"#

  /// What may follow a weekday name: no ordinal noun ("Τρίτη φορά"), and no
  /// further weekday joined to it by "και" or a comma, which makes the phrase a
  /// list of days that names no one planned day.
  private static var greekNameEnd: String {
    let name = greekWeekdayNames
    return
      #"(?!\s+(?:\#(greekOrdinalNouns))(?![\p{L}\p{M}]))(?!\s*(?:και|κι|,|&)\s*(?:(?:την|τη|το)\s+)?(?:\#(name))(?![\p{L}\p{M}]))"#
  }

  /// What may not stand before a weekday for it to name the day, as a lookbehind
  /// pattern: a word that makes the name something other than the day ("άλλη
  /// Παρασκευή", "περασμένη Δευτέρα", "δεύτερη Παρασκευή", an ordinal weekday of
  /// the month), or a weekday of a list: "και Παρασκευή", "και την Παρασκευή",
  /// and "Δευτέρα, Τετάρτη" after its comma. The "και" of "μέχρι και Παρασκευή"
  /// and "έως και την Παρασκευή" belongs to the deadline word and is no list.
  private static var greekNotAfterModifier: String {
    let modifiers =
      #"αλλη|αλλο|επομενη|επομενο|ερχομενη|ερχομενο|προσεχη|προσεχεσ|περασμενη|περασμενο|προηγουμενη|προηγουμενο|πρωτη|δευτερη|τριτη|τεταρτη|πεμπτη|τελευταια|πρωτο|δευτερο|τριτο|τεταρτο|πεμπτο|τελευταιο|και|κι|(?:και|κι)\s(?:την|τη|το)"#
    let list = #"(?<!(?:^|[^\p{L}\p{M}])(?:\#(greekWeekdayNames)),\s)"#
    return
      #"(?:\#(greekNotAfterWord(modifiers))\#(list)|(?<=(?:^|[^\p{L}\p{M}])(?:μεχρι|εωσ)\sκαι\s))"#
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "μέχρι",
  /// "έως", "ως", "πριν (από)", "το αργότερο", "προθεσμία", "παράδοση",
  /// "deadline", each with its colon or space.
  static let greekDueLead =
    #"(?:μεχρι(?:\s+και)?|εωσ(?:\s+και)?|ωσ|πριν(?:\s+απο)?|(?:το\s+)?αργοτερο|(?:η\s+)?προθεσμια(?:\s+ειναι)?|παραδοση|deadline|due)(?:\s*:\s*|\s+)"#

  /// The words before a clock time that make it a bound, not a start time:
  /// "μέχρι τις 5", "πριν τις 17:00", "μετά τις 3", "το αργότερο στις 5", as a
  /// pattern without groups.
  static let greekBoundWords =
    #"μεχρι(?:\s+και)?|εωσ|ωσ|πριν(?:\s+απο)?|μετα(?:\s+απο)?|(?:το\s+)?αργοτερο|νωριτερα\s+απο|αργοτερα\s+απο|οχι\s+πριν|οχι\s+μετα"#

  /// The days a phrase may name, as the alternatives of a pattern without
  /// groups: a weekend, a weekday phrase, a day word, next week (when
  /// `includeWeek`), and a date. After a word that introduces the day
  /// (`afterLead`) any weekday name may stand and a loose date ("15/10") is a
  /// date; without one the weekday phrase is the one a planned day reads, and a
  /// date is one of the strict forms.
  private static func greekDayAlternatives(afterLead: Bool, includeWeek: Bool) -> [String] {
    let name = greekWeekdayNames
    let tail = greekPartTail
    let weekdayPhrase = #"(?:\#(name))\#(greekNameEnd)\#(tail)"#
    let nextWeek = #"(?:επομενη|αλλη|ερχομενη|προσεχη)\s+(?:εβδομαδα|βδομαδα)"#
    let nextWeekGenitive = #"(?:επομενησ|αλλησ|ερχομενησ|προσεχουσ)\s+(?:εβδομαδασ|βδομαδασ)"#
    let dates =
      afterLead ? "\(greekStrictDates)|\(greekLooseDate)" : greekStrictDates
    var alternatives: [String] = [
      #"το\s+σαββατοκυριακο\s+τησ\s+\#(nextWeekGenitive)"#,
      #"(?:αυτο\s+)?το\s+(?:(?:επομενο|ερχομενο|προσεχεσ)\s+)?σαββατοκυριακο"#,
      #"(?:αυτη\s+την|αυτην\s+την|αυτη\s+τη|αυτο\s+το)\s+\#(weekdayPhrase)"#,
      #"(?:την|τη|το)\s+(?:επομενη|επομενο|ερχομενη|ερχομενο|προσεχη|προσεχεσ)\s+\#(weekdayPhrase)"#,
      #"(?:την|τη)\s+\#(nextWeek)\s+(?:(?:την|τη|το)\s+)?\#(weekdayPhrase)"#,
      #"(?:(?:την|τη|το)\s+)?(?:\#(name))\#(greekNameEnd)\s+τησ\s+\#(nextWeekGenitive)"#,
    ]
    if includeWeek {
      alternatives.append(#"(?:την|τη)\s+\#(nextWeek)(?!\s+(?:(?:την|τη|το)\s+)?(?:\#(name))(?![\p{L}\p{M}]))"#)
    }
    // A date goes before the weekday phrase, so "Παρασκευή 16 Οκτωβρίου" is the
    // date with its weekday, not the weekday with its date left behind.
    alternatives.append(contentsOf: [
      #"\#(greekWeekdayBeforeDate)?\#(greekDateLead)?(?:\#(dates))"#,
      #"\#(greekNotAfterModifier)(?:(?:την|τη|το)\s+)?\#(weekdayPhrase)"#,
      #"(?:μεθαυριο|αυριο|σημερα|αποψε)\#(tail)"#,
    ])
    return alternatives
  }

  /// The days a phrase may name right after a word that introduces a due day
  /// ("μέχρι", "προθεσμία"), as the alternatives of a pattern without groups.
  static var greekDaysAfterLead: String {
    greekDayAlternatives(afterLead: true, includeWeek: true).joined(separator: "|")
  }

  /// A clock time written as a bound right after a day, as a lookahead pattern:
  /// "την Παρασκευή μέχρι τις 5", "αύριο πριν τις 17:00", "Παρασκευή στις 5 το
  /// αργότερο". The day before it is the due day.
  private static let greekBeforeDeadlineClock =
    #"(?=\s*,?\s*(?:(?:\#(greekBoundWords))\s+(?:(?:τισ|την|τη|στισ|ωρα|την\s+ωρα)\s+)?(?:\d{1,2}|εννια|εννεα|δεκα|εντεκα|δωδεκα|πεντε|εξι|εφτα|επτα|οχτω|οκτω|τρεισ|τρια|τεσσερισ|τεσσερα|δυο|μια|ενα)(?![\p{L}\p{M}])|(?:στισ|τισ)\s+\d{1,2}(?:[.:]\d{2})?\s+το\s+αργοτερο(?![\p{L}\p{M}])))"#

  /// "μέχρι την Παρασκευή", "έως Παρασκευή", "ως αύριο", "μέχρι τις 15 Οκτωβρίου",
  /// "προθεσμία Παρασκευή", "για αύριο", "για την Παρασκευή", "Παρασκευή το
  /// αργότερο", and a day before a clock written as a bound ("την Παρασκευή
  /// μέχρι τις 5"). Groups: 1 the day after a word that introduces it; 2 the day
  /// after "για"; 3 the day before a deadline clock; 4 the day before "το
  /// αργότερο".
  static var greekDuePattern: String {
    let afterLead = greekDaysAfterLead
    let afterFor = greekDayAlternatives(afterLead: true, includeWeek: false).joined(separator: "|")
    let plain = greekDayAlternatives(afterLead: false, includeWeek: false).joined(separator: "|")
    return
      #"\#(greekStart)(?:\#(greekDueLead)(\#(afterLead))|για\s+(\#(afterFor))|(\#(plain))\#(greekBeforeDeadlineClock)|(\#(plain))\s+το\s+αργοτερο)\#(greekEnd)"#
  }

  static func greekDue(_ match: Match) -> Day? {
    let day: Day?
    if let phrase = match.group(1) {
      day = greekDay(phrase, in: match, context: .afterLead)
    } else if let phrase = match.group(2) {
      day = greekDay(phrase, in: match, context: .afterFor)
    } else if let phrase = match.group(3) ?? match.group(4) {
      day = greekDay(phrase, in: match, context: .plain)
    } else {
      return nil
    }
    return day.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "σήμερα", "αύριο", "μεθαύριο" (maybe with a part of the day), "απόψε", "σε
  /// 3 μέρες", "μετά από μία εβδομάδα", "την επόμενη εβδομάδα", "την άλλη
  /// εβδομάδα", "το Σαββατοκύριακο", a weekday phrase, and a date ("15
  /// Οκτωβρίου", "στις 15 Οκτωβρίου", "15.10.2026", "Παρασκευή 16 Οκτωβρίου",
  /// "στις 15/10"). Group 1: the day, with the words that introduce it.
  static var greekWhenPattern: String {
    let count = #"(?:\d{1,3}|\#(greekCountWords))"#
    let units = #"(?:μερα|μερεσ|ημερα|ημερεσ|εβδομαδα|εβδομαδεσ|βδομαδα|βδομαδεσ)"#
    let nextWeek = #"(?:επομενη|αλλη|ερχομενη|προσεχη)\s+(?:εβδομαδα|βδομαδα)"#
    var alternatives = greekDayAlternatives(afterLead: false, includeWeek: true)
    alternatives.insert(#"(?<!μεσα\s)(?:σε|μετα\s+απο)\s+\#(count)\s+\#(units)"#, at: 0)
    alternatives.append(contentsOf: [
      #"για\s+(?:την|τη)\s+\#(nextWeek)"#,
      #"σαββατοκυριακο(?=[\s.!]*$)"#,
      #"(?:στισ|ημερομηνια(?:\s*:)?)\s+\#(greekWeekdayBeforeDate)?\#(greekLooseDate)"#,
    ])
    return #"\#(greekStart)(\#(alternatives.joined(separator: "|")))\#(greekEnd)"#
  }

  static func greekWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { greekDay($0, in: match, context: .plain) }
  }

  // MARK: - Reading a day

  /// What introduced a day phrase, which decides how sure its words are.
  enum GreekDayContext {
    /// Nothing did: a name that is also an ordinal or a first name needs the
    /// words around it to make it a day.
    case plain
    /// A word that makes a day of what follows ("μέχρι", "έως", "προθεσμία").
    case afterLead
    /// "για", which a first name can also follow ("για την Κυριακή
    /// Παπαδοπούλου").
    case afterFor
  }

  /// The words before a bare weekday name that make it the subject or the
  /// object of a sentence rather than a day: "η Δευτέρα", "με Παρασκευή".
  private static let greekNotBeforeBareName: Set<String> = [
    "η", "ο", "οι", "τησ", "του", "των", "στη", "στην", "στο", "στον", "σε", "με", "απο", "κυρια", "κυριε", "κυρ",
    "προσ",
  ]

  /// The words before an article and a weekday name that make the name a
  /// person: "με την Κυριακή", "από την Παρασκευή".
  private static let greekNotBeforeArticle: Set<String> = [
    "με", "σε", "απο", "προσ", "τησ", "του", "των", "κυρια", "κυριε",
  ]

  /// Whether the weekday name of a plain day phrase names a day, from the words
  /// around it. `nameIndex` is the position of the name among the phrase's
  /// tokens, and `typed` the phrase's words as typed.
  private static func greekReadsAsDay(
    name: String, nameIndex: Int, tokens: [String], typed: [Substring], in match: Match
  ) -> Bool {
    let hasArticle = nameIndex > 0 && ["τη", "την", "το"].contains(tokens[nameIndex - 1])
    let before = wordBefore(match)
    if greekIsPersonWeekday(name), greekNameFollows(match) { return false }
    if hasArticle { return !greekNotBeforeArticle.contains(before ?? "") }
    if greekNotBeforeBareName.contains(before ?? "") { return false }
    if greekOrdinalNames.contains(name) {
      guard nameIndex < typed.count, typed[nameIndex].first?.isUppercase == true else { return false }
      return !greekTextBefore(match).allSatisfy(\.isWhitespace)
    }
    return true
  }

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when the phrase names no day, or names a date the
  /// calendar lacks.
  private static func greekDay(_ phrase: String, in match: Match, context: GreekDayContext) -> Day? {
    let words = greekPhrase(phrase)
    let tokens = words.split(separator: " ").map(String.init)
    let isEvening = greekNamesEvening(tokens)
    if let relative = words.wholeMatch(
      of: /(?:σε|μετα απο) (.+) (μερα|μερεσ|ημερα|ημερεσ|εβδομαδα|εβδομαδεσ|βδομαδα|βδομαδεσ)/),
      let count = greekCount(String(relative.output.1))
    {
      let isWeeks = relative.output.2.hasPrefix("εβδ") || relative.output.2.hasPrefix("βδ")
      return Day(offset: isWeeks ? count * 7 : count)
    }
    // A date keeps its hyphens ("15-10-2026"), which the phrase reads as spaces.
    if let found = greekExplicitDate(greekKey(phrase)) {
      if found.isNumeric, greekFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    let todayWeekday = match.todayWeekday
    if tokens.contains("σαββατοκυριακο") {
      let isNextWeek = tokens.contains { ["επομενησ", "αλλησ", "ερχομενησ", "προσεχουσ"].contains($0) }
      let isComing = tokens.contains { ["επομενο", "ερχομενο", "προσεχεσ"].contains($0) }
      let days =
        isNextWeek
        ? nextWeekOffset(6, todayWeekday: todayWeekday)
        : (isComing
          ? comingWeekdayOffset(6, todayWeekday: todayWeekday) : weekendOffset(todayWeekday: todayWeekday))
      return Day(offset: days)
    }
    let isNextWeek = tokens.contains { ["εβδομαδα", "βδομαδα", "εβδομαδασ", "βδομαδασ"].contains($0) }
    let typed = phrase.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
    guard let nameIndex = tokens.firstIndex(where: { greekWeekdayIndex($0) != nil }),
      let weekday = greekWeekdayIndex(tokens[nameIndex])
    else {
      if isNextWeek { return Day(offset: 7) }
      return greekDayWord(tokens: tokens, isEvening: isEvening)
    }
    if isNextWeek {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if ["αυτη", "αυτην", "αυτο"].contains(tokens[0]) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    let isComing = tokens.contains {
      ["επομενη", "επομενο", "ερχομενη", "ερχομενο", "προσεχη", "προσεχεσ"].contains($0)
    }
    if !isComing {
      switch context {
      case .plain:
        guard greekReadsAsDay(name: tokens[nameIndex], nameIndex: nameIndex, tokens: tokens, typed: typed, in: match)
        else { return nil }
      case .afterFor:
        if greekIsPersonWeekday(tokens[nameIndex]), greekNameFollows(match) { return nil }
      case .afterLead:
        break
      }
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// "σήμερα", "απόψε", "αύριο", "μεθαύριο" (each maybe with a part of the day):
  /// today, this evening, tomorrow, and the day after, an evening for "απόψε",
  /// "βράδυ", and "νύχτα".
  private static func greekDayWord(tokens: [String], isEvening: Bool) -> Day? {
    switch tokens.first {
    case "μεθαυριο": Day(offset: 2, isEvening: isEvening)
    case "αυριο": Day(offset: 1, isEvening: isEvening)
    case "σημερα", "αποψε": Day(offset: 0, isEvening: isEvening)
    default: nil
    }
  }
}
