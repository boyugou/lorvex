import Foundation

extension LorvexCaptureVocabulary {
  /// German, read for a user who reads German.
  static let german = LorvexCaptureVocabulary(
    readingForm: germanForMatching,
    priority: [germanRule(germanPriorityPattern, read: germanPriority)],
    dateRange: [
      germanRule(germanDateRangePattern, read: germanDateRange),
      germanRule(germanWeekdayRangePattern, read: germanWeekdayRange),
    ],
    keptInTitle: [
      germanRule(germanDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      germanRule(germanDueClockPattern) { germanIsClockAfterDueDay($0) ? true : nil },
      germanRule(germanLengthPattern) { germanDeclinesLength($0) ? true : nil },
      germanRule(germanOrdinalWeekdayPattern) { _ in true },
    ],
    length: [
      germanRule(germanLengthPattern, read: germanLength),
      germanRule(germanHourCountPattern, read: germanHourCount),
    ],
    time: [
      germanRule(germanTimeRangePattern, read: germanTimeRange),
      germanRule(germanSpokenTimePattern, read: germanSpokenTime),
      germanRule(germanClockPattern, read: germanClock),
      germanRule(germanMeridiemTimePattern, read: germanMeridiemTime),
      germanRule(germanHourCountPattern, read: germanHourClock),
      germanRule(germanNoonOrMidnightPattern, read: germanNoonOrMidnight),
    ],
    repeats: germanRepeatRules,
    due: [germanRule(germanDuePattern, read: germanDue)],
    when: [germanRule(germanWhenPattern, read: germanWhen)],
    writesClockTimesWithH: true)

  // MARK: - Reading form and patterns

  /// The line with each German letter read in its digraph-free form: ä as a,
  /// ö as o, ü as u, and ß as s, so the patterns, which spell those letters
  /// both ways (``german(_:)``), read a line typed with the letters, with "ae",
  /// "oe", "ue", and "ss", or with the dots and the sharp s left out ("früh",
  /// "frueh", "fruh"). A diaeresis typed as a separate sign after a, o, or u
  /// is read as the "e" of the digraph, so a decomposed "ü" reads like "ue".
  /// Each replacement is one UTF-16 unit for one, so a match range in the
  /// result is the same range in `line`.
  static func germanForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    var previous: Unicode.Scalar?
    for scalar in line.unicodeScalars {
      switch scalar {
      case "\u{00E4}": scalars.append("a")
      case "\u{00C4}": scalars.append("A")
      case "\u{00F6}": scalars.append("o")
      case "\u{00D6}": scalars.append("O")
      case "\u{00FC}": scalars.append("u")
      case "\u{00DC}": scalars.append("U")
      case "\u{00DF}", "\u{1E9E}": scalars.append("s")
      case "\u{0308}":
        if let previous, "aouAOU".unicodeScalars.contains(previous) {
          scalars.append("e")
        } else {
          scalars.append(scalar)
        }
      default: scalars.append(scalar)
      }
      previous = scalar
    }
    return String(scalars)
  }

  /// `pattern`, written in the natural spelling of its words, ready to match a
  /// line in the reading form: ä, ö, ü, and ß each become the alternatives
  /// that read the letter and its digraph (`ä` as `(?:a|ae)`, `ß` as
  /// `(?:s|ss)`). A letter inside a character set reads as its plain letter,
  /// so a set holds none. Expanding a pattern twice changes nothing.
  static func german(_ pattern: String) -> String {
    var result = ""
    var isEscaped = false
    var isInSet = false
    for scalar in pattern.unicodeScalars {
      if isEscaped {
        isEscaped = false
        result.unicodeScalars.append(scalar)
        continue
      }
      switch scalar {
      case "\\":
        isEscaped = true
        result.unicodeScalars.append(scalar)
      case "[":
        isInSet = true
        result.unicodeScalars.append(scalar)
      case "]":
        isInSet = false
        result.unicodeScalars.append(scalar)
      case "\u{00E4}": result += isInSet ? "a" : "(?:a|ae)"
      case "\u{00F6}": result += isInSet ? "o" : "(?:o|oe)"
      case "\u{00FC}": result += isInSet ? "u" : "(?:u|ue)"
      case "\u{00DF}": result += isInSet ? "s" : "(?:s|ss)"
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in natural spelling (see
  /// ``german(_:)``).
  static func germanRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: german(pattern), read: read)
  }

  /// A matched word or phrase as a reader compares it: lowercased, with every
  /// digraph read as the plain letter ("übermorgen", "uebermorgen", and
  /// "ubermorgen" are all "ubermorgen"). The match is in the reading form
  /// already.
  static func germanKey(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "ae", with: "a").replacingOccurrences(of: "oe", with: "o")
      .replacingOccurrences(of: "ue", with: "u").replacingOccurrences(of: "ss", with: "s")
  }

  /// `germanKey(_:)` of a matched phrase with each run of spaces and hyphens
  /// as one space.
  static func germanPhrase(_ text: String) -> String {
    germanKey(text).replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Boundaries and words after a detail

  /// What may follow a clock time: no letter, digit, colon, or apostrophe (the
  /// word or the number goes on), no letter joined by a hyphen ("15 Uhr-Termin"),
  /// no decimal fraction, no percent or currency sign with or without a space
  /// before it, and no dash before a digit, which makes the time one side of a
  /// range written with a dash.
  static let germanTimeEnd = #"(?![\p{Latin}\p{N}'’:]|[-–]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d)"#

  /// The words, as ``germanKey(_:)`` leaves them, that a detail written with
  /// no unit of its own ("um 3", "gegen 15") may be followed by:
  /// prepositions, conjunctions, articles, pronouns, and the words that say
  /// when or how often. Any other word after the number, except an activity
  /// verb, makes it a count ("um 3 Kuchen", "ab 15 Personen"), so it stays in
  /// the title.
  private static let germanWordsAfterDetail: Set<String> = [
    "mit", "im", "in", "ins", "bei", "beim", "zu", "zum", "zur", "fur", "von", "vom", "nach", "vor", "auf", "an", "am",
    "aus", "um", "bis", "ab", "gegen", "und", "oder", "aber", "dann", "wir", "ich", "du", "er", "sie", "es", "ihr",
    "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "bitte", "heute", "morgen",
    "ubermorgen", "nicht", "noch", "auch", "also", "wieder", "jeden", "jede", "jedes", "alle", "taglich", "dringend",
    "wichtig", "sofort", "ca", "etwa", "genau", "punkt", "los", "start", "treffen", "anrufen",
  ]

  /// The infinitives of everyday activities that follow a time as the task it
  /// is for ("um 7 aufstehen", "heute um 8 joggen"), in natural spelling. A verb
  /// of change ("um 5 erhöhen", "um 2 verschieben") is none: its number is a
  /// difference.
  private static let germanActivityVerbs = [
    "aufstehen", "essen", "kochen", "frühstücken", "joggen", "laufen", "gehen", "losgehen", "losfahren", "fahren",
    "abfahren", "ankommen", "aufbrechen", "abholen", "kommen", "starten", "beginnen", "anfangen", "arbeiten",
    "lernen", "schlafen", "telefonieren", "trainieren", "duschen", "lesen", "spielen", "putzen", "packen", "backen",
    "grillen", "einkaufen",
  ]

  /// ``germanActivityVerbs`` as ``germanKey(_:)`` leaves them in a line.
  private static let germanActivityKeys = Set(germanActivityVerbs.map(germanFold))

  /// Whether the line goes on after `match` with nothing, punctuation, a digit,
  /// a word in ``germanWordsAfterDetail`` (minus `excluding`), or an activity
  /// verb.
  static func germanFollowsAsDetail(_ match: Match, excluding: Set<String> = []) -> Bool {
    guard let next = wordAfter(match) else { return true }
    let key = germanKey(next)
    return (germanWordsAfterDetail.contains(key) || germanActivityKeys.contains(key)) && !excluding.contains(key)
  }

  // MARK: - Text around a match

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at: a deadline word or a numbering word before
  /// it, a part of the day beside it. A bounded look-around keeps the time a
  /// line takes linear in its length.
  static let germanContextLength = 60

  /// The text of the line just before `match`: at most ``germanContextLength``
  /// characters, ending where the match starts.
  static func germanTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -germanContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  // MARK: - Counts

  /// The counts German spells as words in a repeat, a length, or a day phrase,
  /// with the forms that stand before a noun in any case ("einem Tag", "einer
  /// Woche"), in natural spelling.
  private static let germanCountList: [(word: String, value: Int)] = [
    ("ein", 1), ("eine", 1), ("einen", 1), ("einem", 1), ("einer", 1), ("eins", 1), ("zwei", 2), ("zwo", 2),
    ("drei", 3), ("vier", 4), ("fünf", 5), ("sechs", 6), ("sieben", 7), ("acht", 8), ("neun", 9), ("zehn", 10),
    ("elf", 11), ("zwölf", 12), ("dreizehn", 13), ("vierzehn", 14), ("fünfzehn", 15), ("zwanzig", 20),
    ("dreißig", 30),
  ]

  /// The count a number word names, by ``germanKey(_:)``.
  static let germanCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: germanCountList.map { (germanFold($0.word), $0.value) })

  /// `text`, a word in natural spelling, as ``germanKey(_:)`` reads it in a
  /// line: with ä, ö, ü, and ß as the plain letters.
  static func germanFold(_ text: String) -> String {
    germanKey(germanForMatching(text))
  }

  /// The count a German word names, in digits or as a number word, or nil.
  static func germanCount(_ word: String) -> Int? {
    number(word) ?? germanCounts[germanKey(word)]
  }

  /// The number words as the alternatives of a pattern.
  static var germanCountWords: String {
    alternation(of: germanCountList.map(\.word))
  }

  /// The ordinals German puts after "jeden", "jede", and "jedes" ("jeden
  /// zweiten Tag"), by stem, with the ending left off.
  private static let germanOrdinalStems: [String: Int] = [
    "zweit": 2, "dritt": 3, "viert": 4, "funft": 5, "sechst": 6, "siebt": 7, "acht": 8, "neunt": 9, "zehnt": 10,
  ]

  /// The ordinal word `word` spells ("zweiten", "dritte"), or nil.
  static func germanOrdinal(_ word: String) -> Int? {
    var key = germanKey(word)
    if let ending = ["en", "er", "es", "em", "e"].first(where: { key.hasSuffix($0) && key.count > $0.count + 2 }) {
      key.removeLast(ending.count)
    }
    return germanOrdinalStems[key]
  }

  /// The ordinals as the alternatives of a pattern, with any ending.
  static let germanOrdinalWords =
    #"(?:zweit|dritt|viert|fünft|sechst|siebt|acht|neunt|zehnt)(?:en|er|es|em|e)"#

  // MARK: - Priority

  /// The levels a priority may name, as a pattern without groups.
  private static let germanPriorityLevels =
    #"hoch|hohe|hoher|hohes|höchste|höchster|höchstes|maximal|maximale|maximaler|mittel|mittlere|mittlerer|mittleres|normal|normale|normaler|niedrig|niedrige|niedriger|niedriges|niedrigste|gering|geringe|geringer|tief|tiefe|tiefer|minimal|minimale"#

  /// Group 1: a written priority ("Priorität hoch", "hohe Priorität", "Prio:
  /// niedrig", "Prio 1"); "dringend", "dringlich", "eilig", and "wichtig" (maybe
  /// after "sehr", and with the full stop or exclamation mark that ends the
  /// line) at the end of the line, or opening it before a colon or a comma,
  /// have no group.
  private static var germanPriorityPattern: String {
    let urgent = #"(?:(?:sehr|besonders|äußerst|extrem)\s+)?(?:dringend|dringlich|eilig|wichtig)"#
    return
      #"\#(latinStart)((?:priorität|prio)\s*[=:]?\s*(?:\#(germanPriorityLevels)|[1-3])|(?:\#(germanPriorityLevels))\s+(?:priorität|prio))\#(latinEnd)|(?<=\s)\#(urgent)\#(latinEnd)[.!]*(?=\s*$)|^\s*\#(urgent)\#(latinEnd)(?=\s*[:,，：])"#
  }

  /// Whether the text before `match` says "not" ("nicht dringend", "nicht so
  /// wichtig", "kein"), which turns an urgency word around.
  private static func germanIsNegated(_ match: Match) -> Bool {
    guard
      let regex = LorvexCapturePatterns.regex(
        #"(?:^|\s)(?:nicht|kein|keine|keinen|nie|weniger|kaum|wenig)\s+(?:so\s+|sehr\s+|mehr\s+|besonders\s+)?$"#)
    else { return false }
    let before = germanTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  private static func germanPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return germanIsNegated(match) ? nil : .p1 }
    let key = germanKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if key.contains("mittel") || key.contains("mittler") || key.contains("normal") { return .p2 }
    if ["niedrig", "gering", "tief", "minimal"].contains(where: { key.contains($0) }) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// The words that open a length and go with it: "für 2 Stunden", "ca. 30
  /// Minuten", "etwa eine halbe Stunde", "Dauer: 2 Stunden".
  private static let germanLengthOpener = #"für|ca\.?|circa|zirka|etwa|ungefähr|rund|dauer\s*:?"#

  /// The words before an amount that make it a moment, an interval, a bound, a
  /// difference, or a rate rather than a length: "in 30 Minuten", "alle 2
  /// Stunden", "nach 2 Stunden", "um 15 Minuten", "pro Stunde", "mindestens 2
  /// Stunden".
  private static let germanLengthDecliner =
    #"in|vor|nach|alle|binnen|innerhalb|seit|über|mehr\s+als|weniger\s+als|mindestens|höchstens|maximal|um|pro|je|jede[nmrs]?|ab|bis(?:\s+zu)?|gegen"#

  /// The words after an amount that make it a moment, the past, a difference,
  /// or a rate: "30 Minuten vorher", "2 Stunden später", "30 Minuten früher",
  /// "30 Minuten vor dem Meeting", "2 Stunden pro Tag".
  private static let germanLengthTrailing =
    #"vorher|nachher|davor|danach|zuvor|später|früher|länger|kürzer|mehr|weniger|vor|nach|pro\s+(?:tag|woche|monat|jahr)|am\s+tag|je\s+(?:tag|woche|monat)"#

  /// The lengths written as words, as a pattern without groups.
  private static let germanLengthWords = [
    #"(?:1/2|1/4|3/4)\s*stunden?"#,
    #"(?:eine\s+)?halbe\s+stunde"#,
    #"(?:eine\s+)?(?:drei\s*viertel|viertel)\s*stunde"#,
    #"(?:eine|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf)\s+stunden?"#,
    #"(?:anderthalb|eineinhalb|zweieinhalb|dreieinhalb|viereinhalb|fünfeinhalb|sechseinhalb)\s+stunden?"#,
    #"(?:fünf|zehn|fünfzehn|zwanzig|dreißig|vierzig|fünfundvierzig|sechzig)\s+minuten"#,
  ].joined(separator: "|")

  /// "30 Minuten", "30 Min.", "2 Stunden", "2 Std.", "2 h", "1,5 Stunden", "1
  /// Stunde 30 Minuten", "1 Std 30 Min", "eine halbe Stunde", "1/2 Stunde", or
  /// a length in words, each maybe after an opener and before "lang". Groups: 1 the
  /// opener; 2 a word that makes the amount a moment, an interval, a bound, or
  /// a rate; 3 and 4 the hours and minutes of "1 Stunde 30 Minuten"; 5 hours,
  /// with a unit; 6 minutes; 7 a length in words; 8 a word after the amount
  /// that makes it the past, a difference, or a rate. A match with group 2 or
  /// 8 is no length: ``germanLength(_:)`` declines it and a keep rule claims
  /// it, so English does not read the "30 min" of "in 30 min". The amount may
  /// not follow a digit, a colon, or a separator, and it may not follow the
  /// English "for", which English reads with its amount. An amount that is a
  /// side of a range ("5-6 Stunden", "2 Stunden bis 3 Stunden") is no length.
  /// An hour count written with h and no space ("2h") is
  /// ``germanHourCountPattern``'s.
  static var germanLengthPattern: String {
    let minutes = #"(?:minuten|minute|min\.?)"#
    let hours = #"(?:stunden|stunde|std\.?)"#
    return
      #"\#(latinStart)(?:(\#(germanLengthOpener))\s+|(\#(germanLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}h]\s?[-–—]\s?)(?<!\d\s?(?:minuten|minute|min|stunden|stunde|std)\.?\s?[-–—]\s?)(?<!\bfor\s)(?:(\d+)\s*\#(hours)\s*(?:und\s+)?(\d{1,2})\s*\#(minutes)|(\d+(?:[.,]\d+)?)(?:\s*\#(hours)|\s+h)|(\d+)\s*\#(minutes)|(\#(germanLengthWords)))\#(latinEnd)(?!\s*[-–—]\s*\d|\s+bis\s+\d)(?:\s+lang\#(latinEnd))?(?:\s+(\#(germanLengthTrailing))\#(latinEnd))?"#
  }

  /// True for a match that is no length: a moment, an interval, a bound, a
  /// difference, the past, or a rate.
  static func germanDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(8) != nil
  }

  private static func germanLength(_ match: Match) -> Int? {
    if germanDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(number), let minutes = match.group(4).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let hours = match.group(5).flatMap(decimalAmount) { return taskLength(minutes: Int((hours * 60).rounded())) }
    if let minutes = match.group(6).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(7).flatMap(germanWordLength)
  }

  /// The minutes a length written in words names: "eine halbe Stunde", "1/2
  /// Stunde", "Viertelstunde", "dreiviertel Stunde", "eine Stunde", "zwei
  /// Stunden", "anderthalb Stunden", "zweieinhalb Stunden", "zwanzig Minuten".
  private static func germanWordLength(_ phrase: String) -> Int? {
    let key = germanKey(phrase).filter { !$0.isWhitespace }
    if let stem = ["minuten", "minute"].compactMap({ key.hasSuffix($0) ? String(key.dropLast($0.count)) : nil }).first {
      return germanCounts[stem].flatMap { taskLength(minutes: $0) } ?? [
        "funf": 5, "zehn": 10, "funfzehn": 15, "zwanzig": 20, "dreisig": 30, "vierzig": 40, "funfundvierzig": 45,
        "sechzig": 60,
      ][stem]
    }
    guard let stem = ["stunden", "stunde"].compactMap({ key.hasSuffix($0) ? String(key.dropLast($0.count)) : nil }).first
    else { return nil }
    switch stem {
    case "halbe", "einehalbe", "1/2": return 30
    case "dreiviertel", "einedreiviertel", "3/4": return 45
    case "viertel", "eineviertel", "1/4": return 15
    case "anderthalb", "eineinhalb": return 90
    default:
      if stem.hasSuffix("einhalb"), let count = germanCounts[String(stem.dropLast("einhalb".count))] {
        return taskLength(minutes: count * 60 + 30)
      }
      return germanCounts[stem].flatMap { taskLength(minutes: $0 * 60) }
    }
  }

  // MARK: - Hour counts written with h

  /// The words before an hour count written with h that say it is a length:
  /// "für 2h", "for 2h" (English), "Dauer: 2h".
  private static let germanLengthLeads: Set<String> = ["fur", "for", "dauer", "dauer:"]

  /// The words before an hour count written with h that say it is a clock time:
  /// "um 15h", "gegen 15h", "ab 15h".
  private static let germanClockLeads: Set<String> = ["um", "gegen", "ab", "so um", "so gegen"]

  /// An hour count written with h and no space: "2h", "1,5h", "1h30", "1h30m",
  /// "1h 30min", "15h", "15h30", each maybe after an opener. Groups: 1 the
  /// opener ("für", "for", "ca.", "um", "gegen", ...); 2 the hours, with a
  /// decimal fraction for a length; 3 minutes written after the h; 4 minutes
  /// written after a space with a unit. The count may not follow a digit, a
  /// colon, or a separator.
  static let germanHourCountPattern =
    #"\#(latinStart)(?:(für|for|dauer\s*:?|ca\.?|circa|zirka|etwa|ungefähr|rund|um|gegen|ab|\#(germanSoLead)(?:um|gegen))\s+)?(?<![\p{N}:.,/])(\d{1,2}(?:[.,]\d+)?)h(?:(\d{2})(?:\s?(?:minuten|minute|min\.?|m))?|\s(\d{1,2})\s?(?:minuten|minute|min\.?|m))?\#(latinEnd)"#

  /// How an hour count written with h and no space reads. A decimal count, or
  /// one after "für", "for", or "Dauer", is a length; one after "um", "gegen",
  /// or "ab", from 13h, or with a leading zero is a clock time. Otherwise
  /// "2h" to "8h" and "1h30" to "5h30" are lengths, "6h30" to "12h30" are
  /// clock times, and "9h" to "12h" alone could be either, so they stay.
  enum GermanHourCountReading {
    case length, clock, undecided
  }

  static func germanHourCountReading(
    hours: Int, hasMinutes: Bool, hasLeadingZero: Bool, isDecimal: Bool, opener: String?
  ) -> GermanHourCountReading {
    let lead = opener.map(germanPhrase)
    if isDecimal { return .length }
    if let lead, germanLengthLeads.contains(lead) { return .length }
    if let lead, germanClockLeads.contains(lead) { return .clock }
    if hasLeadingZero || hours == 0 || hours >= 13 { return .clock }
    if hasMinutes { return hours <= 5 ? .length : .clock }
    return hours <= 8 ? .length : .undecided
  }

  private static func germanHourCount(_ match: Match) -> Int? {
    guard let amountText = match.group(2) else { return nil }
    let minutes = (match.group(3) ?? match.group(4)).flatMap(number)
    let isDecimal = amountText.contains { $0 == "," || $0 == "." }
    if isDecimal {
      guard let hours = decimalAmount(amountText) else { return nil }
      return taskLength(minutes: Int((hours * 60).rounded()) + (minutes ?? 0))
    }
    guard let hours = number(amountText),
      germanHourCountReading(
        hours: hours, hasMinutes: minutes != nil, hasLeadingZero: startsWithZero(amountText), isDecimal: false,
        opener: match.group(1)) == .length
    else { return nil }
    return taskLength(minutes: hours * 60 + (minutes ?? 0))
  }
}
