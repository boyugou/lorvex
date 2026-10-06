import Foundation

extension LorvexCaptureVocabulary {
  /// Greek, read for a user who reads Greek. The reading form takes every
  /// accent and diaeresis off the Greek letters and reads the final sigma ς as
  /// σ, so "αύριο", "αυριο", and "ΑΥΡΙΟ" are one word, "Δευτέρα", "δευτερα", and
  /// "ΔΕΥΤΕΡΑ" are one, and a line typed on a keyboard without accents reads
  /// like the accented one. Every letter stays one UTF-16 unit, so match ranges
  /// map back to the typed line, and the title keeps the letters that were
  /// typed. A letter typed as a base letter and a separate combining mark stays
  /// as typed, so a detail word typed that way is left unread.
  ///
  /// A word needs a boundary of letters, digits, and combining marks on both
  /// sides and no letter joined to it by a hyphen, so "αυριανό", "σήμερα-αύριο",
  /// and a weekday inside a longer word stay in the title.
  ///
  /// - Day: σήμερα, απόψε, αύριο (alone or with a part of the day: αύριο το
  ///   πρωί, αύριο βράδυ), μεθαύριο, the weekday names (with the article τη,
  ///   την, or το, or alone where nothing else can be meant: Δευτέρα, Σάββατο,
  ///   Δευ, Τρι, Τετ, Πεμ, Σαβ, and Παρ. and Κυρ. with their period), αυτή την
  ///   Παρασκευή, την επόμενη Παρασκευή, την επόμενη εβδομάδα, την άλλη
  ///   εβδομάδα, (την) Παρασκευή της επόμενης εβδομάδας, το Σαββατοκύριακο, σε 3
  ///   μέρες, μετά από 3 μέρες, σε μία εβδομάδα; a date: 15 Οκτωβρίου, 15 Οκτ.,
  ///   1η Μαΐου, 25ης Μαρτίου, στις 15 Οκτωβρίου 2026, 15.10.2026, 15/10/2026,
  ///   with a weekday before it (Παρασκευή 16 Οκτωβρίου), and after "στις",
  ///   "ημερομηνία", or a deadline word the short 15/10 and 15.10. A weekday
  ///   alone is the next such day, a full week ahead when it names today; with
  ///   "αυτή την" it is the coming one counting today; "την επόμενη Παρασκευή"
  ///   is the next one; with "της επόμενης εβδομάδας" or after "την επόμενη
  ///   εβδομάδα" it is next week's, weeks starting on Monday. "Το
  ///   Σαββατοκύριακο" is the coming Saturday. A past day (χθες, προχθές, την
  ///   περασμένη Παρασκευή, το περασμένο Σαββατοκύριακο) is never read and stays
  ///   in the title with the clock time that follows it. A name that is also an
  ///   ordinal (Τρίτη, Τετάρτη, Πέμπτη) or a first name (Παρασκευή, Κυριακή)
  ///   names the day only with the article and no ordinal noun after it ("την
  ///   Τρίτη φορά" is the third time), or alone when capitalized and not opening
  ///   the line; "με την Κυριακή" and "την Κυριακή Παπαδοπούλου" name a person.
  ///   The weekdays of a list ("Δευτέρα και Τρίτη", "Δευτέρα, Τετάρτη") name no
  ///   single planned day and stay in the title. Named holidays (Μεγάλη
  ///   Παρασκευή, Καθαρά Δευτέρα, Κυριακή του Πάσχα) and "κάθε πρώτη Δευτέρα του
  ///   μήνα" stay whole.
  /// - Date range: 3-5 Μαΐου, 3 Μαΐου - 5 Μαΐου, από 3 έως 5 Μαΐου, από τις 3
  ///   μέχρι τις 5 Μαΐου, each maybe with a year after the end; a span of
  ///   weekdays: από Παρασκευή έως Κυριακή, Παρασκευή-Κυριακή (Monday to Friday
  ///   is the working week, a repeat). The first day is the planned day and the
  ///   last the due day. The month abbreviations (Ιαν, Φεβ, Μαρ, Απρ, Μαΐ, Ιουν,
  ///   Ιουλ, Αυγ, Σεπ, Οκτ, Νοε, Δεκ) read after a day number, and the
  ///   colloquial months (Γενάρη, Φλεβάρη, Μάρτη, Μάη, Οκτώβρη) as the full
  ///   names.
  /// - Repeat: κάθε μέρα, κάθε πρωί, κάθε Δευτέρα, κάθε Δευτέρα και Πέμπτη, τις
  ///   Δευτέρες, τα Σάββατα, κάθε εβδομάδα, κάθε μήνα, κάθε χρόνο, κάθε δύο
  ///   μέρες, κάθε 2 εβδομάδες, κάθε δεύτερη Παρασκευή, μέρα παρά μέρα, εβδομάδα
  ///   παρά εβδομάδα, μία φορά την εβδομάδα, τις καθημερινές, κάθε εργάσιμη
  ///   μέρα, κάθε Δευτέρα έως Παρασκευή, κάθε Σαββατοκύριακο, τα Σαββατοκύριακα,
  ///   κάθε μήνα στις 15, κάθε 15 του μήνα; ημερησίως, εβδομαδιαίως, μηνιαίως,
  ///   ετησίως anywhere, and καθημερινά, εβδομαδιαία, μηνιαία, ετήσια at the end
  ///   of the line ("εβδομαδιαία αναφορά" stays a title) or with "βάση".
  /// - Due: μέχρι (και), έως (και), ως, or πριν (από) before a day ("μέχρι την
  ///   Παρασκευή", "έως και Παρασκευή", "ως αύριο", "μέχρι τις 15
  ///   Οκτωβρίου"), προθεσμία, παράδοση, or deadline before a day, a day before
  ///   "το αργότερο", and "για" before a day ("για αύριο", "για την
  ///   Παρασκευή"). A clock time written as a bound (μέχρι τις 5, πριν τις
  ///   17:00, μετά τις 3, στις 5 το αργότερο) is no start time: it stays in the
  ///   title, and the day before it is the due day.
  /// - Time: στις 15:00, στις 3, στις 3 το απόγευμα, 3 μ.μ., 9 π.μ., στις 3 και
  ///   μισή (3:30), στις 3 και τέταρτο (3:15), στις 4 παρά τέταρτο (3:45), στις
  ///   4 παρά 10 (3:50), στις τρεις και είκοσι, ώρα 15:00, το απόγευμα στις 7,
  ///   τα μεσάνυχτα; a range: στις 14-16, 3-5 το απόγευμα, από τις 3 έως τις 5,
  ///   από τις 9 π.μ. έως τις 5 μ.μ. A bare hour needs "στις", "στη", or "ώρα"
  ///   before it, and the word after it must be one that can follow a time
  ///   ("στις 3 ώρες" and "στις 3 άτομα" count something). "Και μισή" adds the
  ///   half hour to the hour it follows and "παρά" takes minutes off the hour
  ///   after it. A time from 1 to 6 o'clock with no part of the day is the
  ///   afternoon, unless written with a leading zero. A colon time with no
  ///   Greek word ("15:30", "3pm") is left to English.
  /// - Length: 30 λεπτά, 30 λ, 1 ώρα, 2 ώρες, 1,5 ώρα, μισή ώρα, μιάμιση ώρα,
  ///   δύο ώρες και μισή, ένα τέταρτο της ώρας, 1 ώρα και 30 λεπτά, each maybe
  ///   after "για", "διάρκεια", or "περίπου". An amount that names a moment or
  ///   a bound ("σε 30 λεπτά", "μετά από 2 ώρες", "τουλάχιστον 2 ώρες") is no
  ///   length.
  /// - Priority: επείγον, επείγουσα, σημαντικό, σημαντική (maybe after "πολύ")
  ///   at the end of the line or opening it before a colon or comma ("επείγον
  ///   μήνυμα" stays), υψηλή προτεραιότητα, χαμηλή προτεραιότητα, προτεραιότητα:
  ///   υψηλή, προτεραιότητα 1.
  static let greek = LorvexCaptureVocabulary(
    readingForm: greekForMatching,
    priority: [Rule(pattern: greekPriorityPattern, read: greekPriority)],
    dateRange: [
      Rule(pattern: greekDateRangePattern, read: greekDateRange),
      Rule(pattern: greekWeekdayRangePattern, read: greekWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: greekPastPattern) { _ in true },
      Rule(pattern: greekNamedDayPattern) { _ in true },
      Rule(pattern: greekMinutesWithUnitPattern) { _ in true },
      Rule(pattern: greekDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: greekDueClockPattern) { greekIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: greekLengthPattern) { greekClaimsLength($0) ? true : nil },
    ],
    length: [Rule(pattern: greekLengthPattern, read: greekLength)],
    time: [
      Rule(pattern: greekTimeRangePattern, read: greekTimeRange),
      Rule(pattern: greekSpokenTimePattern, read: greekSpokenTime),
      Rule(pattern: greekClockPattern, read: greekClock),
      Rule(pattern: greekMeridiemTimePattern, read: greekMeridiemTime),
      Rule(pattern: greekMidnightPattern, read: greekMidnight),
    ],
    repeats: greekRepeatRules,
    due: [Rule(pattern: greekDuePattern, read: greekDue)],
    when: [Rule(pattern: greekWhenPattern, read: greekWhen)])

  // MARK: - Reading form

  /// The line with every accent and diaeresis taken off its Greek letters
  /// ("ά" as "α", "ΐ" as "ι") and the final sigma ς read as σ. Each letter
  /// stays one UTF-16 unit, so a match range in it is the same range in the
  /// typed line. A letter typed as a base letter and a separate combining mark
  /// stays as typed.
  static func greekForMatching(_ line: String) -> String {
    var result = ""
    for character in line {
      let typed = String(character)
      if typed == "ς" {
        result += "σ"
        continue
      }
      let folded = typed.folding(options: .diacriticInsensitive, locale: nil)
      result += folded.utf16.count == typed.utf16.count ? folded : typed
    }
    return result
  }

  // MARK: - Boundaries and matched words

  /// A word boundary for Greek words: no letter, digit, or combining mark on
  /// that side, and no letter joined by a hyphen.
  static let greekStart = #"(?<![\p{L}\p{N}\p{M}]|\p{L}[-–])"#
  static let greekEnd = #"(?![\p{L}\p{N}\p{M}]|[-–]\p{L})"#

  /// A lookbehind that rejects a position right after one of `words` and a
  /// space, where the word stands on its own and is not the end of a longer one:
  /// "ψυχολογία κάθε μέρα" does not follow "για". `words` is a pattern without
  /// groups, in the reading form, whose alternatives are of bounded length.
  static func greekNotAfterWord(_ words: String) -> String {
    #"(?<!(?:^|[^\p{L}\p{M}])(?:\#(words))\s)"#
  }

  /// A matched word or phrase as a reader compares it: lowercased, with the
  /// final sigma read as σ.
  static func greekKey(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "ς", with: "σ")
  }

  /// ``greekKey(_:)`` of a matched phrase with each run of spaces and hyphens
  /// as one space.
  static func greekPhrase(_ text: String) -> String {
    greekKey(text).replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Text around a match

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at. A bounded look-around keeps the time a line
  /// takes linear in its length.
  static let greekContextLength = 60

  /// The text of the line just before `match`: at most ``greekContextLength``
  /// characters, ending where the match starts.
  static func greekTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -greekContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  /// The text of the line just after `match`: at most ``greekContextLength``
  /// characters, starting where the match ends.
  static func greekTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return String(match.source[end...].prefix(greekContextLength))
  }

  /// Whether the first word after `match` is written with a capital first
  /// letter and lowercase ones ("Παπαδοπούλου"): a surname or another name, not
  /// a word of the sentence. A word in capitals is no name.
  static func greekNameFollows(_ match: Match) -> Bool {
    let after = greekTextAfter(match).drop(while: \.isWhitespace)
    let word = after.prefix(while: \.isLetter)
    guard let first = word.first, first.isUppercase, word.count > 1 else { return false }
    return word.dropFirst().allSatisfy(\.isLowercase)
  }

  // MARK: - Counts

  /// The counts Greek spells as words in a repeat, a length, or a day phrase,
  /// as the reading form leaves them. The feminine and neuter forms of one,
  /// three, and four are the forms the units take.
  private static let greekCountList: [(word: String, value: Int)] = [
    ("ενα", 1), ("μια", 1), ("ενασ", 1), ("δυο", 2), ("τρια", 3), ("τρεισ", 3), ("τεσσερα", 4), ("τεσσερισ", 4),
    ("πεντε", 5), ("εξι", 6), ("εφτα", 7), ("επτα", 7), ("οχτω", 8), ("οκτω", 8), ("εννια", 9), ("εννεα", 9),
    ("δεκα", 10), ("εντεκα", 11), ("δωδεκα", 12), ("δεκαπεντε", 15), ("εικοσι", 20), ("εικοσι πεντε", 25),
    ("τριαντα", 30), ("σαραντα", 40), ("σαραντα πεντε", 45), ("πενηντα", 50),
  ]

  private static let greekCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: greekCountList.map { ($0.word, $0.value) })

  /// The count a Greek word names, in digits or as a number word, or nil.
  static func greekCount(_ word: String) -> Int? {
    number(word) ?? greekCounts[greekPhrase(word)]
  }

  /// The number words as the alternatives of a pattern, with a space between
  /// the words of a compound.
  static var greekCountWords: String {
    alternation(of: greekCountList.map(\.word)).replacingOccurrences(of: " ", with: #"\s+"#)
  }

  // MARK: - Words after a detail

  /// The words a detail with no unit of its own ("στις 3") may be followed by:
  /// prepositions, conjunctions, articles, particles, and the words that say
  /// when or how often. Any other word after the number makes it a count ("στις
  /// 3 ώρες", "στις 3 άτομα") or the day of a month ("στις 3 του μήνα"), so it
  /// stays in the title.
  private static let greekWordsAfterDetail: Set<String> = [
    "και", "κι", "η", "αλλα", "ομωσ", "ενω", "αν", "οταν", "πριν", "μετα", "μεχρι", "εωσ", "ωσ", "με", "για", "απο",
    "σε", "προσ", "στο", "στη", "στην", "στον", "στουσ", "στισ", "στα", "κατα", "χωρισ", "περι", "το", "τον", "την",
    "τη", "τουσ", "τισ", "τα", "θα", "να", "δεν", "μην", "μη", "ασ", "σημερα", "αυριο", "μεθαυριο", "αποψε",
    "περιπου", "ακριβωσ", "ηδη", "παλι", "παντα", "καθε", "οπωσδηποτε", "παρακαλω", "νωριτερα", "αργοτερα",
  ]

  /// Whether the line goes on after `match` with nothing or with a word that can
  /// follow a time written without a unit.
  static func greekFollowsAsDetail(_ match: Match) -> Bool {
    followsAsDetail(match, words: greekWordsAfterDetail)
  }

  // MARK: - Priority

  /// Group 1: a written priority ("υψηλή προτεραιότητα", "χαμηλής
  /// προτεραιότητας", "προτεραιότητα: υψηλή", "προτεραιότητα 1"); "επείγον" and
  /// "σημαντικό" (maybe after "πολύ", and with the full stop or exclamation
  /// mark that ends the line) at the end of the line, or opening it before a
  /// colon or a comma, have no group. An adjective that goes on to a noun
  /// ("επείγον μήνυμα", "σημαντική συνάντηση") is no priority, and neither is a
  /// negation before it ("όχι επείγον", "δεν είναι σημαντικό").
  private static var greekPriorityPattern: String {
    let high = #"υψηλη|μεγαλη|μεγιστη|υψιστη|ανωτατη"#
    let medium = #"μεσαια|κανονικη|μετρια"#
    let low = #"χαμηλη|μικρη|ελαχιστη"#
    let levels = "\(high)|\(medium)|\(low)"
    let written =
      #"(?:(?:\#(levels))σ?\s+προτεραιοτητα(?:σ)?|προτεραιοτητα(?:σ)?\s*[=:]?\s*(?:(?:\#(levels))σ?|[1-3]))"#
    let adverb = #"(?:(?:πολυ|ιδιαιτερα|εξαιρετικα|παρα\s+πολυ)\s+)?"#
    let urgent =
      #"\#(adverb)(?:επειγον|επειγουσα|επειγων|επειγοντωσ|σημαντικο|σημαντικη|σημαντικοσ|σημαντικοτατο)"#
    let negation = greekNotAfterWord(#"οχι|μη|μην|δεν\sειναι|καθολου|δεν"#)
    return
      #"\#(greekStart)(\#(written))\#(greekEnd)|(?<=\s)\#(negation)\#(urgent)\#(greekEnd)[.!]*(?=\s*$)|^\s*\#(urgent)\#(greekEnd)(?=\s*[:,，：])"#
  }

  private static func greekPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return .p1 }
    let key = greekKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if ["χαμηλη", "μικρη", "ελαχιστη"].contains(where: key.contains) { return .p3 }
    if ["μεσαια", "κανονικη", "μετρια"].contains(where: key.contains) { return .p2 }
    return .p1
  }

  // MARK: - Length

  /// The words that open a length and go with it: "για 2 ώρες", "διάρκεια: 30
  /// λεπτά", "περίπου 2 ώρες", "γύρω στα 30 λεπτά".
  private static let greekLengthOpener =
    #"για|εκτιμωμενη\s+διαρκεια\s*:?|διαρκεια\s*:?|περιπου|γυρω\s+στα?|κατα\s+προσεγγιση|συνολικα"#

  /// The words before an amount that make it a moment, an interval, a bound, or
  /// a malformed clock time rather than a length: "σε 30 λεπτά", "μετά από 2
  /// ώρες", "κάθε 2 ώρες", "τουλάχιστον 2 ώρες", "το πολύ 2 ώρες", "στις 3 ώρες".
  private static let greekLengthDecliner =
    #"μεσα\s+σε|σε|στισ|μετα(?:\s+απο)?|καθε|ανα|πριν(?:\s+απο)?|μεχρι|εωσ|ωσ|εντοσ|τουλαχιστον|το\s+πολυ|πανω\s+απο|κατω\s+απο|περιπου\s+καθε"#

  /// The words after an amount that make it a moment, the past, a bound, or a
  /// rate: "30 λεπτά πριν", "2 ώρες μετά", "20 λεπτά ακόμα", "2 ώρες τη μέρα".
  private static let greekLengthTrailing =
    #"πριν|μετα|αργοτερα|νωριτερα|ακομα|ακομη|παραπανω|λιγοτερο|περισσοτερο|τη\s+μερα|την\s+ημερα|την\s+εβδομαδα|τη\s+βδομαδα|το\s+μηνα|το\s+χρονο|ανα\s+(?:μερα|ημερα|εβδομαδα|βδομαδα|μηνα|χρονο)"#

  /// The words after an amount that say how long a task takes and go with it:
  /// "2 ώρες περίπου", "30 λεπτά ακριβώς".
  private static let greekLengthClosing = #"περιπου|ακριβωσ|συνολικα"#

  /// The halves written as one word before "ώρες": "δυόμισι ώρες" is 2.5 hours.
  private static let greekHalfWords: [String: Int] = [
    "δυομισι": 2, "τρεισημισι": 3, "τεσσεραμισι": 4, "πεντεμισι": 5, "εφταμισι": 7, "επταμισι": 7, "οχτωμισι": 8,
    "οκτωμισι": 8, "εννιαμισι": 9, "εννεαμισι": 9, "δεκαμισι": 10,
  ]

  /// The lengths written as words, as a pattern without groups: "μισή ώρα",
  /// "μιάμιση ώρα", "μία ώρα", "δύο ώρες", "δύο ώρες και μισή", "δύο ώρες και 30
  /// λεπτά", "δυόμισι ώρες", "είκοσι λεπτά", "ένα τέταρτο", "τρία τέταρτα της
  /// ώρας". "Ένα λεπτό" is left out: it is as often "just a moment". A count of
  /// hours in digits ("2 ώρες", "1 ώρα και 30 λεπτά") is read by the amount
  /// alternatives of ``greekLengthPattern``; the words go before them only where
  /// a half or minutes follow the hours.
  private static var greekLengthWords: String {
    let halves = alternation(of: Array(greekHalfWords.keys))
    let half = #"\s+και\s+μισ(?:η|ο)"#
    let count = #"(?:\#(greekCountWords)|\d+)"#
    return [
      #"\#(count)\s+(?:ωρα|ωρεσ)\s+και\s+(?:\#(greekCountWords)|\d{1,2})\s+λεπτα"#,
      #"\#(count)\s+(?:ωρα|ωρεσ)\#(half)"#,
      #"μισ(?:η|ο)\s+ωρα"#,
      #"μιαμιση\s+ωρα"#,
      #"(?:ενα|μια)\s+ωρα"#,
      #"(?:\#(halves))\s+ωρεσ"#,
      #"(?:\#(greekCountWords))\s+ωρεσ"#,
      #"(?:δυο|τρια|τεσσερα|πεντε|εξι|εφτα|οχτω|εννια|δεκα|δεκαπεντε|εικοσι|εικοσι\s+πεντε|τριαντα|σαραντα|σαραντα\s+πεντε|πενηντα)\s+λεπτα"#,
      #"ενα\s+τεταρτο(?:\s+τησ\s+ωρασ)?|τρια\s+τεταρτα(?:\s+τησ\s+ωρασ)?"#,
    ].joined(separator: "|")
  }

  /// "30 λεπτά", "30 λ", "2 ώρες", "1 ώρα", "1,5 ώρα", "1 ώρα και 30 λεπτά",
  /// "μισή ώρα", "δύο ώρες και μισή", each maybe after an opener and before a
  /// closing word. Groups: 1 the opener; 2 a word before the amount that makes it
  /// a moment, an interval, or a bound; 3 a length in words; 4 and 5 the hours
  /// and minutes of "1 ώρα και 30 λεπτά"; 6 hours with a decimal fraction; 7
  /// minutes; 8 a word after the amount that makes it a moment, the past, a
  /// bound, or a rate. A match with group 2 or 8 is no length: the reader
  /// declines it and the title keeps it. The amount may not follow a digit, a
  /// colon, or a separator, and an amount that is a side of a range ("2-3 ώρες")
  /// is no length.
  static var greekLengthPattern: String {
    let minutes = #"(?:λεπτα|λεπτο|λεπτ\.|λεπ\.?|λ\.?)"#
    let hours = #"(?:ωρεσ|ωρα|ωρ\.?)"#
    return
      #"\#(greekStart)(?:(\#(greekLengthOpener))\s+|(\#(greekLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}]\s?[-–—]\s?)(?:(\#(greekLengthWords))|(\d+)\s*\#(hours)\s*(?:και\s+)?(\d{1,2})\s*\#(minutes)|(\d+(?:[.,]\d+)?)\s*\#(hours)|(\d+)\s*\#(minutes))\#(greekEnd)(?!\s*[-–—]\s*\d)(?:\s+(?:\#(greekLengthClosing))\#(greekEnd))?(?:\s+(\#(greekLengthTrailing))\#(greekEnd))?"#
  }

  /// Whether a match of ``greekLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, the past, or a rate.
  static func greekClaimsLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(8) != nil
  }

  private static func greekLength(_ match: Match) -> Int? {
    if greekClaimsLength(match) { return nil }
    if let words = match.group(3) {
      // "Ένα τέταρτο" without "της ώρας" is a fraction as often as a length.
      let key = greekKey(words)
      if key.hasPrefix("ενα τεταρτο"), !key.contains("ωρασ"), !greekFollowsAsDetail(match) { return nil }
      return greekWordLength(words)
    }
    if let hours = match.group(4).flatMap(number), let minutes = match.group(5).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(6) {
      guard let hours = decimalAmount(amountText) else { return nil }
      return taskLength(minutes: Int((hours * 60).rounded()))
    }
    return match.group(7).flatMap(number).flatMap { taskLength(minutes: $0) }
  }

  /// The minutes a length written in words names.
  private static func greekWordLength(_ phrase: String) -> Int? {
    let key = greekPhrase(phrase)
    if key.wholeMatch(of: /μισ(?:η|ο) ωρα/) != nil { return 30 }
    if key == "μιαμιση ωρα" { return 90 }
    if key.hasPrefix("ενα τεταρτο") { return 15 }
    if key.hasPrefix("τρια τεταρτα") { return 45 }
    if let found = key.wholeMatch(of: /(.+) ωρεσ/), let hours = greekHalfWords[String(found.output.1)] {
      return taskLength(minutes: hours * 60 + 30)
    }
    if let found = key.wholeMatch(of: /(.+?) (?:ωρα|ωρεσ) και (.+?) λεπτα/),
      let hours = greekCount(String(found.output.1)), let minutes = greekCount(String(found.output.2))
    {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let found = key.wholeMatch(of: /(.+?) (?:ωρα|ωρεσ) και μισ(?:η|ο)/), let count = greekCount(String(found.output.1)) {
      return taskLength(minutes: count * 60 + 30)
    }
    if let found = key.wholeMatch(of: /(.+) (?:ωρα|ωρεσ)/), let count = greekCount(String(found.output.1)) {
      return taskLength(minutes: count * 60)
    }
    if let found = key.wholeMatch(of: /(.+) λεπτα/), let count = greekCount(String(found.output.1)) {
      return taskLength(minutes: count)
    }
    return nil
  }
}
