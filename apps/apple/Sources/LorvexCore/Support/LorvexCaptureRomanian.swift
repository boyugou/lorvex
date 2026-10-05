import Foundation

extension LorvexCaptureVocabulary {
  /// Romanian, read for a user who reads Romanian. A word needs a boundary of
  /// Latin letters, digits, and combining marks on both sides, and a letter
  /// joined by a hyphen makes a compound that is no day ("azi-dimineață"
  /// stays). Diacritics are optional: the reading form leaves out ă, â, î, and
  /// both the comma-below (ș, ț) and the cedilla (ş, ţ) forms of s and t, so
  /// "mâine" and "maine", "sâmbătă" and "sambata", and "marți", "marţi", and
  /// "marti" read alike, and the title keeps the letters that were typed. A
  /// letter typed as a base letter and a separate combining accent keeps its
  /// form in the reading form, so a detail word typed that way is left unread.
  ///
  /// - Day: azi, astăzi, diseară, în seara asta, mâine (alone or with a part of
  ///   the day: mâine dimineață, mâine seara), poimâine, the weekday names
  ///   (alone, after în, pe, la, or de, or with viitoare, următoare, asta, or
  ///   aceasta), a weekday with a part of the day (vineri seara), săptămâna
  ///   viitoare, weekendul acesta, în weekend, weekendul viitor, peste 3 zile,
  ///   peste o săptămână; a date: 15 octombrie, 15 oct., 1 mai 2027,
  ///   15.10.2026, 15.10., and after pe or "data de" the short 15.10 and
  ///   15/10. A weekday alone or with "care vine" is the next such day, a full
  ///   week ahead when it names today; with asta or aceasta it is this week's,
  ///   and with viitoare, următoare, or beside săptămâna viitoare, next week's,
  ///   weeks starting on Monday. "În weekend" is the coming Saturday and
  ///   "weekendul viitor" the one after. A past day (ieri, alaltăieri, luni
  ///   trecută, weekendul trecut) is never read, and neither is "azi noapte",
  ///   which names the night just gone as often as the one to come. "Luni" is
  ///   also the plural of "lună" (month), so it is no weekday after a number or
  ///   a word that counts ("peste 3 luni", "două luni") or before "de zile".
  /// - Date range: de la 3 la 5 mai, de la 3 până la 5 mai, din 3 până în 5
  ///   mai, între 3 și 5 mai, în perioada 3-5 mai, 3-5 mai, de la 30 mai la 2
  ///   iunie, 3 mai - 5 mai, each maybe with a year after the end; de la luni
  ///   până miercuri, luni - miercuri. The first day is the planned day and
  ///   the last the due day. "Mai" is the month only where it is no adverb of
  ///   comparison ("3 mai multe" stays).
  /// - Repeat: în fiecare zi, în fiecare luni, în fiecare luni și joi, lunea,
  ///   lunea și joia, în zilele de marți, la două zile, din două în două zile,
  ///   la fiecare 2 săptămâni, o dată pe săptămână, o dată la două săptămâni,
  ///   în fiecare a doua zi, în fiecare lună, în fiecare 15 ale lunii, în
  ///   fiecare an, în fiecare trimestru, în zilele lucrătoare, de luni până
  ///   vineri, în fiecare weekend; zilnic, săptămânal, lunar, anual,
  ///   trimestrial, and semestrial at the end of the line ("Ședință
  ///   săptămânală" stays a title). The definite forms of Saturday
  ///   and Sunday (sâmbăta, duminica) read like the plain names once the
  ///   diacritics are left out, so they repeat a task only in a list with
  ///   another definite weekday ("lunea și sâmbăta").
  /// - Due: a day after până (la, pe), cel târziu, înainte de, pentru, termen,
  ///   or deadline ("până vineri", "până la 15 octombrie", "pentru luni"). A
  ///   clock time after those words ("până la ora 17", "înainte de 17:00") is
  ///   a bound that stays in the title, and the day before it is the due day.
  /// - Time: la ora 15, la 15:30, ora 15.30, ora 3 după-amiază, la 8 seara, la 7
  ///   dimineața, la 2 noaptea, la 8 de seară, la prânz, la miezul nopții, la 3
  ///   și jumătate, la 3 și un sfert, la 3 fără un sfert, la 3 fără 10, la 3 și
  ///   10; a range: de la 14 la 16, între 14 și 16, 14:00-16:00, ora 14-16.
  ///   Romanian adds the half hour to the hour it names ("3 și jumătate" is
  ///   3:30) and "fără" takes minutes off it ("3 fără un sfert" is 2:45, "3
  ///   fără 10" is 2:50). A time from 1 to 6 o'clock with no part of the day
  ///   is the afternoon, unless written with a leading zero. A bare hour after
  ///   "la" is a time where the line goes on with nothing or a word that can
  ///   follow a time ("la 3 prieteni" stays), and the spoken forms need "la",
  ///   "ora", or another lead. Spoken minutes with a unit word ("la 3 și 10
  ///   minute") stay in the title whole.
  /// - Length: 30 de minute, 12 minute, 30 min, o oră, 2 ore, 24 de ore, o
  ///   oră și jumătate, jumătate de oră, un sfert de oră, 1,5 ore. The
  ///   particle "de" joins a count from 20 up to its noun ("30 de minute")
  ///   and may be left out.
  /// - Priority: prioritate mare, prioritate scăzută, prio 1, and urgent or
  ///   important at the end of the line or opening it before a colon or comma.
  ///   The feminine "urgentă" and "importantă" stay in the title: they are the
  ///   same letters as the nouns "urgență" and "importanță" once the
  ///   diacritics are left out.
  static let romanian = LorvexCaptureVocabulary(
    readingForm: unaccentedForMatching,
    priority: [Rule(pattern: romanianPriorityPattern, read: romanianPriority)],
    dateRange: [
      Rule(pattern: romanianDateRangePattern, read: romanianDateRange),
      Rule(pattern: romanianWeekdayRangePattern, read: romanianWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: romanianNegatedUrgentPattern) { _ in true },
      Rule(pattern: romanianDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: romanianDueClockPattern) { romanianIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: romanianLengthPattern) { romanianClaimsLength($0) ? true : nil },
      Rule(pattern: romanianSpokenMinutesWithUnitPattern) { _ in true },
      Rule(pattern: romanianOrdinalWeekdayPattern) { _ in true },
      Rule(pattern: romanianNoDayWeekendPattern) { _ in true },
      Rule(pattern: romanianAmbiguousDayPattern) { _ in true },
    ],
    length: [Rule(pattern: romanianLengthPattern, read: romanianLength)],
    time: [
      Rule(pattern: romanianTimeRangePattern, read: romanianTimeRange),
      Rule(pattern: romanianSpokenTimePattern, read: romanianSpokenTime),
      Rule(pattern: romanianClockPattern, read: romanianClock),
      Rule(pattern: romanianMeridiemTimePattern, read: romanianMeridiemTime),
      Rule(pattern: romanianNoonOrMidnightPattern, read: romanianNoonOrMidnight),
    ],
    repeats: romanianRepeatRules,
    due: [Rule(pattern: romanianDuePattern, read: romanianDue)],
    when: [Rule(pattern: romanianWhenPattern, read: romanianWhen)])

  // MARK: - Boundaries and matched words

  /// A word boundary for Romanian words: no Latin letter, digit, or combining
  /// mark on that side, and no letter joined by a hyphen, since a hyphen builds
  /// a compound that is no day. A combining mark counts as part of the word, so
  /// a letter typed as a base letter and a separate accent is never cut in two.
  static let romanianStart = #"(?<![\p{Latin}\p{N}\p{M}]|\p{L}[-–])"#
  static let romanianEnd = #"(?![\p{Latin}\p{N}\p{M}]|[-–]\p{L})"#

  /// A matched word or phrase as a reader compares it: lowercased.
  static func romanianKey(_ text: String) -> String {
    text.lowercased()
  }

  /// ``romanianKey(_:)`` of a matched phrase with each run of spaces and hyphens
  /// as one space.
  static func romanianPhrase(_ text: String) -> String {
    romanianKey(text).replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Words after a detail

  /// The words, as ``romanianKey(_:)`` leaves them in the reading form, that a
  /// detail written with no unit of its own ("la 3", "pe la 15") may be followed
  /// by: prepositions, conjunctions, pronouns, the words that say when or how
  /// often, and a few everyday verbs. Any other word after the number makes it
  /// a count ("la 3 prieteni", "la 15 oameni"), so it stays in the title.
  private static let romanianWordsAfterDetail: Set<String> = [
    "cu", "si", "sau", "dar", "apoi", "pentru", "la", "in", "pe", "de", "din", "spre", "catre", "dupa", "inainte", "fara",
    "ca", "sa", "se", "nu", "eu", "tu", "el", "ea", "noi", "voi", "ei", "ele", "ma", "te", "ne", "va", "imi", "maine",
    "azi", "astazi", "diseara", "deseara", "poimaine", "luni", "marti", "miercuri", "joi", "vineri", "sambata",
    "duminica", "seara", "dimineata", "noaptea", "urgent", "important", "zilnic", "saptamanal", "lunar", "anual",
    "impreuna", "aproximativ", "circa", "cam", "fix", "exact", "vreau", "trebuie", "plec", "plecam", "vin", "venim",
    "ajung", "sun", "iau", "trec", "incepe", "incepem", "mergem", "merg", "ies", "iesim", "vedem", "intalnim",
  ]

  /// Whether the line goes on after `match` with nothing, punctuation, a digit,
  /// or a word in ``romanianWordsAfterDetail`` (minus `excluding`).
  static func romanianFollowsAsDetail(_ match: Match, excluding: Set<String> = []) -> Bool {
    guard let next = wordAfter(match) else { return true }
    let key = romanianKey(next)
    return romanianWordsAfterDetail.contains(key) && !excluding.contains(key)
  }

  // MARK: - Text around a match

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at: a deadline word or a numbering word before
  /// it, a part of the day beside it. A bounded look-around keeps the time a
  /// line takes linear in its length.
  static let romanianContextLength = 60

  /// The text of the line just before `match`: at most
  /// ``romanianContextLength`` characters, ending where the match starts.
  static func romanianTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -romanianContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  /// The text of the line just after `match`: at most
  /// ``romanianContextLength`` characters, starting where the match ends.
  static func romanianTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return String(match.source[end...].prefix(romanianContextLength))
  }

  // MARK: - Counts

  /// The counts Romanian spells as words in a repeat, a length, or a day phrase,
  /// as the reading form leaves them. "O" and "un" are the article too, so the
  /// patterns that take them check the unit after them; "doi" and "două" are
  /// the masculine and the feminine two, and "unșpe" and "doișpe" the spoken
  /// eleven and twelve.
  private static let romanianCountList: [(word: String, value: Int)] = [
    ("o", 1), ("un", 1), ("una", 1), ("unu", 1), ("doi", 2), ("doua", 2), ("trei", 3), ("patru", 4), ("cinci", 5),
    ("sase", 6), ("sapte", 7), ("opt", 8), ("noua", 9), ("zece", 10), ("unsprezece", 11), ("unspe", 11),
    ("doisprezece", 12), ("douasprezece", 12), ("doispe", 12), ("treisprezece", 13), ("paisprezece", 14),
    ("cincisprezece", 15), ("douazeci", 20), ("treizeci", 30),
  ]

  private static let romanianCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: romanianCountList.map { ($0.word, $0.value) })

  /// The count a Romanian word names, in digits or as a number word, or nil.
  static func romanianCount(_ word: String) -> Int? {
    number(word) ?? romanianCounts[romanianKey(word)]
  }

  /// The number words as the alternatives of a pattern.
  static var romanianCountWords: String {
    alternation(of: romanianCountList.map(\.word))
  }

  /// The hours Romanian spells as words after a lead ("la trei", "ora opt"):
  /// one through twelve, as a pattern without groups.
  static let romanianHourWords =
    "doisprezece|douasprezece|doispe|unsprezece|unspe|zece|noua|opt|sapte|sase|cinci|patru|trei|doua|doi|unu|una"

  // MARK: - Priority

  /// The levels a priority may name, as a pattern without groups.
  private static let romanianPriorityLevels =
    #"mare|mari|ridicata|inalta|maxima|medie|normala|mijlocie|mica|mici|scazuta|redusa|joasa|minima"#

  /// Group 1: a written priority ("prioritate mare", "prioritate scăzută",
  /// "prio: mică", "prioritate 1", "de mare prioritate"); "urgent" and
  /// "important" (maybe after "foarte", and with the full stop or exclamation
  /// mark that ends the line) at the end of the line, or opening it before a
  /// colon or a comma, have no group. The feminine and plural adjectives
  /// ("urgentă", "importante") are the same letters as the nouns "urgență" and
  /// "importanță" once the diacritics are left out, so they are not read.
  private static var romanianPriorityPattern: String {
    let urgent = #"(?:(?:foarte|extrem\s+de|super)\s+)?(?:urgent|important)"#
    let written =
      #"(?:(?:cu|de)\s+)?(?:(?:prioritate|prioritatea|prio)\s*[=:]?\s*(?:foarte\s+)?(?:\#(romanianPriorityLevels)|[1-3])|(?:foarte\s+)?(?:\#(romanianPriorityLevels))\s+(?:prioritate|prio))"#
    return
      #"\#(romanianStart)(\#(written))\#(romanianEnd)|(?<=\s)\#(urgent)\#(romanianEnd)[.!]*(?=\s*$)|^\s*\#(urgent)\#(romanianEnd)(?=\s*[:,，：])"#
  }

  /// Whether the text before `match` says "not" ("nu e urgent", "nu prea
  /// important", "mai puțin important", "deloc urgent"), which turns an urgency
  /// word around.
  private static func romanianIsNegated(_ match: Match) -> Bool {
    guard
      let regex = LorvexCapturePatterns.regex(
        #"(?:^|\s)(?:nu(?:\s+(?:e|este|prea|chiar|foarte|atat\s+de|asa\s+de))*|deloc|nici|mai\s+putin)\s+$"#)
    else { return false }
    let before = romanianTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  private static func romanianPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return romanianIsNegated(match) ? nil : .p1 }
    let key = romanianKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if ["medie", "normala", "mijlocie"].contains(where: { key.contains($0) }) { return .p2 }
    if ["mica", "mici", "scazuta", "redusa", "joasa", "minima"].contains(where: { key.contains($0) }) { return .p3 }
    return .p1
  }

  /// "nu e urgent", "nu este urgent", "deloc urgent", "mai puțin urgent": the
  /// word "urgent", which Romanian shares with English, names no priority after
  /// a negation, so the phrase stays in the title whole and English does not
  /// read the "urgent".
  private static let romanianNegatedUrgentPattern =
    #"\#(romanianStart)(?:nu|deloc|nici|mai\s+putin)(?:\s+(?:e|este|prea|chiar|foarte|atat\s+de|asa\s+de))*\s+urgent\#(romanianEnd)"#

  // MARK: - Length

  /// The words that open a length and go with it: "timp de 2 ore", "cam 30 de
  /// minute", "aproximativ 2 ore", "durata: 2 ore", "pentru 30 de minute", "pe
  /// 2 ore", "durează 2 ore", and the "de" of "ședință de 2 ore".
  private static let romanianLengthOpener =
    #"timp\s+de|durata\s+de|durata\s*:?|dureaza|estimat\s*:?|aproximativ|in\s+jur\s+de|pentru|circa|aproape|vreo|cam|pe|de"#

  /// The words before an amount that make it a moment, an interval, or a bound
  /// rather than a length: "peste 2 ore", "după 30 de minute", "la fiecare 2
  /// ore", "acum 2 ore", "până la 2 ore", "mai mult de 2 ore".
  private static let romanianLengthDecliner =
    #"peste|in|dupa|acum|la\s+fiecare|la|din|inainte\s+de|pana\s+la|pana\s+in|pana|mai\s+mult\s+de|mai\s+putin\s+de|cel\s+putin|cel\s+mult|maxim|minim|fiecare|fiecarei"#

  /// The words after an amount that make it a moment, the past, a difference,
  /// or a rate: "30 de minute înainte", "2 ore în urmă", "2 ore pe zi", "30 min
  /// mai târziu", "2 ore suplimentare".
  private static let romanianLengthTrailing =
    #"inainte|mai\s+tarziu|mai\s+devreme|in\s+urma|extra|suplimentar[ea]?|pe\s+(?:zi|saptamana|luna|an|ora)|dupa|ramase|ramas"#

  /// The lengths written as words, as a pattern without groups.
  private static let romanianLengthWords = [
    #"(?:o\s+)?(?:jumatate|jumate)\s+de\s+ora"#,
    #"(?:un\s+)?sfert\s+de\s+ora"#,
    #"(?:trei|3)\s+sferturi\s+de\s+ora"#,
    #"(?:o|un)\s+ora(?:\s+si\s+(?:jumatate|jumate|un\s+sfert))?"#,
    #"(?:doua|doi|trei|patru|cinci|sase|sapte|opt|noua|zece|unsprezece|doisprezece|douasprezece)\s+ore(?:\s+si\s+(?:jumatate|jumate|un\s+sfert))?"#,
    #"(?:cinci|zece|cincisprezece|douazeci|treizeci|patruzeci\s+si\s+cinci|patruzeci)\s+(?:de\s+)?minute"#,
  ].joined(separator: "|")

  /// "30 de minute", "12 minute", "30 min", "2 ore", "1,5 ore", "o oră", "2 ore
  /// și 30 de minute", "o oră și jumătate", "jumătate de oră", "un sfert de
  /// oră", or a length in words, each maybe after an opener. Groups: 1 the
  /// opener; 2 a word that makes the amount a moment, an interval, or a bound; 3
  /// and 4 the hours and minutes of "2 ore 30 de minute"; 5 hours with a decimal
  /// fraction and 6 the "și jumătate" or "și un sfert" after them; 7 minutes; 8
  /// a length in words; 9 a word after the amount that makes it the past, a
  /// difference, or a rate. A match with group 2 or 9 is no length: the reader
  /// declines it and the title keeps it. The amount may not follow a digit, a
  /// colon, or a separator, and an amount that is a side of a range ("2-3 ore",
  /// "între 2 și 3 ore") is no length.
  static var romanianLengthPattern: String {
    let minutes = #"(?:minute|minut|min\.?)"#
    let hours = #"(?:ore|ora)"#
    let betweenHours = #"(?<!intre\s{1,3}\d{1,2}\s{1,3}si\s{1,3})"#
    return
      #"\#(romanianStart)(?:(\#(romanianLengthOpener))\s+|(\#(romanianLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}]\s?[-–—]\s?)(?<!\d\s?(?:minute|minut|min|ore|ora)\.?\s?[-–—]\s?)\#(betweenHours)(?:(\d+)(?:\s+de)?\s*\#(hours)\s*(?:si\s*)?(\d{1,2})\s*(?:de\s+)?\#(minutes)|(\d+(?:[.,]\d+)?)(?:\s+de)?\s*\#(hours)(?:\s+si\s+(jumatate|jumate|un\s+sfert))?|(\d+)\s*(?:de\s+)?\#(minutes)|(\#(romanianLengthWords)))\#(romanianEnd)(?!\s*[-–—]\s*\d)(?:\s+(\#(romanianLengthTrailing))\#(romanianEnd))?"#
  }

  /// Whether a match of ``romanianLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, a difference, the past, or a rate.
  static func romanianClaimsLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(9) != nil
  }

  private static func romanianLength(_ match: Match) -> Int? {
    if romanianClaimsLength(match) { return nil }
    if let hours = match.group(3).flatMap(number), let minutes = match.group(4).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(5) {
      guard let hours = decimalAmount(amountText) else { return nil }
      var minutes = Int((hours * 60).rounded())
      if let fraction = match.group(6) { minutes += romanianPhrase(fraction).hasSuffix("sfert") ? 15 : 30 }
      return taskLength(minutes: minutes)
    }
    if let minutes = match.group(7).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(8).flatMap(romanianWordLength)
  }

  /// The minutes a length written in words names: "jumătate de oră", "un sfert
  /// de oră", "trei sferturi de oră", "o oră", "o oră și jumătate", "două ore",
  /// "trei ore și jumătate", "douăzeci de minute".
  private static func romanianWordLength(_ phrase: String) -> Int? {
    let key = romanianPhrase(phrase)
    if key.hasSuffix("sferturi de ora") { return 45 }
    if key.hasSuffix("jumatate de ora") || key.hasSuffix("jumate de ora") { return 30 }
    if key.hasSuffix("sfert de ora") { return 15 }
    if let found = key.wholeMatch(of: /(\S+) (?:ora|ore)(?: si (jumatate|jumate|un sfert))?/),
      let count = romanianCount(String(found.output.1))
    {
      let extra: Int =
        switch found.output.2 {
        case .none: 0
        case .some(let word): word == "un sfert" ? 15 : 30
        }
      return taskLength(minutes: count * 60 + extra)
    }
    if let found = key.wholeMatch(of: /(.+?) (?:de )?minute/) {
      let minutes: [String: Int] = [
        "cinci": 5, "zece": 10, "cincisprezece": 15, "douazeci": 20, "treizeci": 30, "patruzeci": 40,
        "patruzeci si cinci": 45,
      ]
      return minutes[String(found.output.1)]
    }
    return nil
  }
}
