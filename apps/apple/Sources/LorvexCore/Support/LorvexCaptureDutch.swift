import Foundation

extension LorvexCaptureVocabulary {
  /// Dutch, read for a user who reads Dutch. A word needs a boundary of Latin
  /// letters, digits, and combining marks on both sides, and a letter joined
  /// by a hyphen makes a compound that is no day ("maandag-meeting"). Accents
  /// may be left out or typed ("één" and "een", "vóór" and "voor" read alike),
  /// and an apostrophe may be straight or curly ("'s middags").
  ///
  /// - Day: vandaag, vanochtend, vanmorgen, vanmiddag, vanavond, vannacht,
  ///   morgen (alone or with a part of the day: morgenochtend, morgenavond,
  ///   morgen vroeg), overmorgen, the weekday names (alone, after op or
  ///   vanaf, or with komende, aankomende, aanstaande, deze, or volgende),
  ///   a weekday with a part of the day (vrijdagavond), volgende week,
  ///   dit weekend, volgend weekend, in het weekend, tijdens het weekend, over
  ///   3 dagen, over een week; a date: 15 oktober, 15 okt, 1 mei 2027,
  ///   15-10-2026, 15.10., and after op, voor, tegen, tot, uiterlijk, or vanaf
  ///   the short 15-10 and 15/10. A weekday alone, after op, or after komende,
  ///   aankomende, or aanstaande means the next such day, a full week ahead
  ///   when it names today; after deze it is this week's, and after volgende,
  ///   or beside volgende week, next week's, weeks starting on Monday. A past
  ///   day (gisteren, eergisteren, vorige maandag, afgelopen vrijdag) is never
  ///   read, and a weekend named by what it comes before, after, or follows
  ///   (voor het weekend, vorig weekend, afgelopen weekend) stays whole in the
  ///   title. The abbreviations ma, di, wo, do, vr, za, and zo are also
  ///   ordinary words, so they name a day only after op, vanaf, deze,
  ///   komende, aankomende, aanstaande, or volgende, or after elke or iedere
  ///   in a repeat.
  /// - Date range: van 3 tot 5 mei, van 3 tot en met 5 mei, 3 t/m 5 mei, 3-5
  ///   mei, van 3 mei tot 5 mei, van 30 mei tot 2 juni, tussen 3 en 5 mei, each
  ///   maybe with a year after the end; van maandag tot woensdag, maandag t/m
  ///   woensdag. The first day is the planned day and the last the due day.
  ///   "Tot" joins two days only after van (or between two dates with their
  ///   months), "en" only after tussen, and a day alone opens a range joined
  ///   by a dash only when the dash touches both sides or van comes first.
  /// - Repeat: elke dag, iedere maandag, elke ma en wo, maandags, om de dag,
  ///   om de week, om de twee weken, elke 2 weken, elke twee dagen, om de
  ///   maandag, elke maand, elk jaar, elke 15e van de maand, een keer per
  ///   week, doordeweeks, op werkdagen, ma-vr, elk weekend, in de weekenden;
  ///   dagelijks, wekelijks, maandelijks, jaarlijks, and tweewekelijks at the
  ///   end of the line ("Wekelijks overleg" stays a title), and wekelijks or
  ///   tweewekelijks with the weekdays it fixes ("wekelijks op maandag").
  /// - Due: a day after voor, tot, tot en met, t/m, tegen, uiterlijk, ten
  ///   laatste, deadline, or einddatum ("voor vrijdag"), or before uiterlijk.
  ///   A clock time after those words ("tot 17 uur", "voor 17:00") is a bound
  ///   that stays in the title, and the day before it is the due day.
  /// - Time: om 15:00, om 15.30 uur, om 3 uur, om 15u30, om drie uur, rond
  ///   half vier, om kwart over drie, 15:30 uur, 3 uur 's middags, 8 uur 's
  ///   avonds, 's avonds om 8, 's avonds 8 uur, om middernacht; a range: van
  ///   14 tot 16 uur, 14:00-16:00 uur, tussen 14 en 16 uur. "Half vier" is
  ///   3:30. A time from 1 to 6 o'clock with no part of the day is the
  ///   afternoon, unless written with a leading zero. A bare "3 uur" is a
  ///   length; "om 3 uur", and "3 uur" after a day, a date, or a part of the
  ///   day ("morgen 3 uur", "'s avonds 8 uur"), is the time.
  /// - Length: 30 min, 30 minuten, 2 uur, 1,5 uur, 1 uur 30, een half uur,
  ///   anderhalf uur, een kwartier, drie kwartier, tweeënhalf uur, een uurtje.
  /// - Priority: prioriteit hoog, hoge prioriteit, lage prioriteit, prio 1,
  ///   and dringend or belangrijk at the end of the line or opening it before
  ///   a colon or comma; "urgent" reads as in English.
  static let dutch = LorvexCaptureVocabulary(
    readingForm: unaccentedForMatching,
    priority: [Rule(pattern: dutchPriorityPattern, read: dutchPriority)],
    dateRange: [
      Rule(pattern: dutchDateRangePattern, read: dutchDateRange),
      Rule(pattern: dutchWeekdayRangePattern, read: dutchWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: dutchNegatedUrgentPattern) { _ in true },
      Rule(pattern: dutchDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: dutchDueClockPattern) { dutchIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: dutchLengthPattern) { dutchClaimsLength($0) ? true : nil },
      Rule(pattern: dutchOrdinalWeekdayPattern) { _ in true },
      Rule(pattern: dutchNoDayWeekendPattern) { _ in true },
    ],
    length: [
      Rule(pattern: dutchLengthPattern, read: dutchLength),
      Rule(pattern: dutchHourCountPattern, read: dutchHourCount),
    ],
    time: [
      Rule(pattern: dutchTimeRangePattern, read: dutchTimeRange),
      Rule(pattern: dutchSpokenTimePattern) { dutchSpokenTime($0) },
      Rule(pattern: dutchClockPattern, read: dutchClock),
      Rule(pattern: dutchMeridiemTimePattern, read: dutchMeridiemTime),
      Rule(pattern: dutchHourCountPattern, read: dutchHourClock),
      Rule(pattern: dutchMidnightPattern, read: dutchMidnight),
    ],
    repeats: dutchRepeatRules,
    due: [Rule(pattern: dutchDuePattern, read: dutchDue)],
    when: [Rule(pattern: dutchWhenPattern, read: dutchWhen)])

  // MARK: - Boundaries and matched words

  /// A word boundary for Dutch words: no Latin letter, digit, combining mark,
  /// or apostrophe on that side, and no letter joined by a hyphen, since a
  /// hyphen builds a compound ("maandag-meeting", "morgen-routine") that is no
  /// day. A combining mark counts as part of the word, so a letter typed as a
  /// base letter and a separate accent is never cut in two.
  static let dutchStart = #"(?<![\p{Latin}\p{N}\p{M}'’]|\p{L}[-–])"#
  static let dutchEnd = #"(?![\p{Latin}\p{N}\p{M}'’]|[-–]\p{L})"#

  /// A matched word or phrase as a reader compares it: lowercased, with a
  /// curly apostrophe read as a straight one.
  static func dutchKey(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "’", with: "'")
  }

  /// ``dutchKey(_:)`` of a matched phrase with each run of spaces and hyphens
  /// as one space.
  static func dutchPhrase(_ text: String) -> String {
    dutchKey(text).replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Words after a detail

  /// The words, as ``dutchKey(_:)`` leaves them, that a detail written with no
  /// unit of its own ("om 3", "rond 15") may be followed by: prepositions,
  /// conjunctions, articles, pronouns, and the words that say when or how
  /// often. Any other word after the number, except an activity verb, makes it
  /// a count ("om 3 koekjes", "rond 15 mensen"), so it stays in the title.
  private static let dutchWordsAfterDetail: Set<String> = [
    "met", "in", "bij", "naar", "voor", "van", "tot", "op", "aan", "uit", "en", "of", "maar", "dan", "we", "wij", "ik",
    "je", "jij", "u", "hij", "zij", "ze", "het", "de", "een", "dit", "dat", "vandaag", "morgen", "overmorgen",
    "vanavond", "nog", "ook", "weer", "graag", "alsjeblieft", "alstublieft", "svp", "even", "stipt", "precies",
    "ongeveer", "ca", "circa", "dringend", "belangrijk", "elke", "iedere", "dagelijks", "samen",
  ]

  /// The infinitives of everyday activities that follow a time as the task it is
  /// for ("om 7 opstaan", "vandaag om 8 hardlopen"). A verb of change ("om 5
  /// verhogen", "om 2 verplaatsen") is none: its number is a difference.
  private static let dutchActivityVerbs: Set<String> = [
    "bellen", "afspreken", "vertrekken", "komen", "gaan", "starten", "beginnen", "eten", "koken", "opstaan", "sporten",
    "hardlopen", "wandelen", "werken", "leren", "slapen", "douchen", "lezen", "spelen", "poetsen", "inpakken", "bakken",
    "ophalen", "opruimen", "mailen", "appen", "vergaderen", "trainen", "zwemmen", "fietsen", "rijden", "lopen",
    "ontbijten", "lunchen", "studeren", "overleggen", "uitgaan", "thuiskomen", "aankomen", "afronden", "inleveren",
  ]

  /// Whether the line goes on after `match` with nothing, punctuation, a digit,
  /// a word in ``dutchWordsAfterDetail`` (minus `excluding`), or an activity
  /// verb.
  static func dutchFollowsAsDetail(_ match: Match, excluding: Set<String> = []) -> Bool {
    guard let next = wordAfter(match) else { return true }
    let key = dutchKey(next)
    return (dutchWordsAfterDetail.contains(key) || dutchActivityVerbs.contains(key)) && !excluding.contains(key)
  }

  // MARK: - Text around a match

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at: a deadline word or a numbering word before
  /// it, a part of the day beside it. A bounded look-around keeps the time a
  /// line takes linear in its length.
  static let dutchContextLength = 60

  /// The text of the line just before `match`: at most ``dutchContextLength``
  /// characters, ending where the match starts.
  static func dutchTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -dutchContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  // MARK: - Counts

  /// The counts Dutch spells as words in a repeat, a length, or a day phrase.
  /// "Een" is both the number and the article, so the patterns that take it
  /// check the unit after it.
  private static let dutchCountList: [(word: String, value: Int)] = [
    ("een", 1), ("twee", 2), ("drie", 3), ("vier", 4), ("vijf", 5), ("zes", 6), ("zeven", 7), ("acht", 8),
    ("negen", 9), ("tien", 10), ("elf", 11), ("twaalf", 12), ("dertien", 13), ("veertien", 14), ("vijftien", 15),
    ("twintig", 20), ("dertig", 30),
  ]

  private static let dutchCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: dutchCountList.map { ($0.word, $0.value) })

  /// The count a Dutch word names, in digits or as a number word, or nil.
  static func dutchCount(_ word: String) -> Int? {
    number(word) ?? dutchCounts[dutchKey(word)]
  }

  /// The number words as the alternatives of a pattern.
  static var dutchCountWords: String {
    alternation(of: dutchCountList.map(\.word))
  }

  // MARK: - Priority

  /// The levels a priority may name, as a pattern without groups.
  private static let dutchPriorityLevels =
    #"hoog|hoge|hogere|hoogste|middel|middelmatig|middelmatige|gemiddeld|gemiddelde|normaal|normale|laag|lage|lagere|laagste"#

  /// Group 1: a written priority ("prioriteit hoog", "hoge prioriteit", "prio:
  /// laag", "prio 1"); "dringend" and "belangrijk" (maybe after "zeer", and
  /// with the full stop or exclamation mark that ends the line) at the end of
  /// the line, or opening it before a colon or a comma, have no group.
  private static var dutchPriorityPattern: String {
    let urgent = #"(?:(?:zeer|erg|heel|super|extreem)\s+)?(?:dringend|belangrijk)"#
    return
      #"\#(dutchStart)((?:prioriteit|prio)\s*[=:]?\s*(?:\#(dutchPriorityLevels)|[1-3])|(?:\#(dutchPriorityLevels))\s+(?:prioriteit|prio))\#(dutchEnd)|(?<=\s)\#(urgent)\#(dutchEnd)[.!]*(?=\s*$)|^\s*\#(urgent)\#(dutchEnd)(?=\s*[:,，：])"#
  }

  /// Whether the text before `match` says "not" ("niet dringend", "minder
  /// belangrijk", "niet zo belangrijk"), which turns an urgency word around.
  private static func dutchIsNegated(_ match: Match) -> Bool {
    guard
      let regex = LorvexCapturePatterns.regex(
        #"(?:^|\s)(?:niet|geen|minder|weinig|nooit|nauwelijks)\s+(?:zo\s+|erg\s+|echt\s+|heel\s+|zeer\s+|bijzonder\s+|meer\s+)?$"#
      )
    else { return false }
    let before = dutchTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  private static func dutchPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return dutchIsNegated(match) ? nil : .p1 }
    let key = dutchKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if ["middel", "gemiddeld", "normaal", "normale"].contains(where: { key.contains($0) }) { return .p2 }
    if ["laag", "lage", "lagere", "laagste"].contains(where: { key.contains($0) }) { return .p3 }
    return .p1
  }

  /// "niet urgent", "niet zo urgent", "minder urgent": the English word
  /// "urgent", which Dutch shares, names no priority after a negation, so the
  /// phrase stays in the title whole and English does not read the "urgent".
  private static let dutchNegatedUrgentPattern =
    #"\#(dutchStart)(?:niet|geen|minder|weinig|nooit|nauwelijks)(?:\s+(?:zo|erg|echt|heel|zeer|bijzonder|meer))?\s+urgent\#(dutchEnd)"#

  // MARK: - Length

  /// The words that open a length and go with it: "gedurende 2 uur",
  /// "ongeveer 30 minuten", "ca. 30 min", "zo'n half uur", "duur: 2 uur",
  /// "voor 30 min".
  private static let dutchLengthOpener =
    #"gedurende|ongeveer|circa|ca\.?|zo['’]n|ruim|bijna|voor|(?:een\s+)?duur\s+van|tijdsduur\s*:?|duur\s*:?"#

  /// The words before an amount that make it a moment, an interval, a bound, a
  /// difference, or a rate rather than a length: "over 30 min", "na 2 uur",
  /// "elke 2 uur", "om de 2 uur", "per 30 min", "binnen 2 uur", "minstens 2
  /// uur". "Om", "rond", "omstreeks", and "vanaf" before an hour count lead a
  /// clock time, which the time rules read.
  private static let dutchLengthDecliner =
    #"om\s+de|meer\s+dan|minder\s+dan|ten\s+minste|ten\s+hoogste|ten\s+laatste|over|na|binnen|sinds|tot|tegen|tussen|elke|elk|iedere|ieder|per|minstens|maximaal|hooguit|vanaf|uiterlijk|rond|omstreeks|om"#

  /// The decliner words that can also lead or bound a clock time ("om 3 uur",
  /// "vanaf 3 uur", "tot 16 uur", "tussen 3 en 5 uur", "na 2 uur"), so an hour
  /// count after them is left to the time rules.
  private static let dutchClockWords: Set<String> = [
    "om", "rond", "omstreeks", "vanaf", "tot", "tegen", "tussen", "uiterlijk", "na", "sinds", "ten laatste",
  ]

  /// The words after an amount that make it a moment, the past, a difference,
  /// or a rate: "30 min later", "2 uur geleden", "30 min voor de vergadering",
  /// "30 min te laat", "2 uur per dag".
  private static let dutchLengthTrailing =
    #"later|eerder|vroeger|geleden|extra|vooraf|achteraf|daarvoor|daarna|ervoor|erna|voor|na|te\s+laat|te\s+vroeg|van\s+tevoren|per\s+(?:dag|week|maand|jaar)|elke\s+(?:dag|week|maand|jaar)"#

  /// The lengths written as words, as a pattern without groups.
  private static let dutchLengthWords = [
    #"(?:een\s+)?half\s*uur(?:tje)?"#,
    #"(?:een|twee|drie|vier|\d+)\s+kwartier(?:tje)?"#,
    #"(?:(?:\d+|een|twee|drie|vier|vijf|zes|zeven|acht)\s*(?:en\s+(?:een\s+)?half|enhalf))\s+uur"#,
    #"(?:een|twee|drie|vier|vijf|zes|zeven|acht|negen|tien|elf|twaalf)\s+uur(?:tje)?"#,
    #"(?:anderhalf|anderhalve)\s+uur"#,
    #"(?:vijf|tien|vijftien|twintig|vijfentwintig|dertig|veertig|vijfenveertig|zestig)\s+minuten"#,
  ].joined(separator: "|")

  /// "30 min", "30 minuten", "2 uur", "1,5 uur", "1 uur 30 min", "1 uur en 30
  /// minuten", "een half uur", "een kwartier", "anderhalf uur", or a length in
  /// words, each maybe after an opener and before "lang". Groups: 1 the opener;
  /// 2 a word that makes the amount a moment, an interval, a bound, or a rate;
  /// 3 and 4 the hours and minutes of "1 uur 30 min"; 5 hours; 6 minutes; 7 a
  /// length in words; 8 a word after the amount that makes it the past, a
  /// difference, or a rate. A match with group 2 or 8 is no length: the reader
  /// declines it, and the title keeps it unless a clock lead before an hour
  /// count leaves it to the time rules. The amount may not follow a digit, a
  /// colon, or a separator, and it may not follow the English "for", which
  /// English reads with its amount. An amount that is a side of a range ("5-6
  /// uur", "2 uur tot 3 uur", "tussen 3 en 5 uur") is no length, and neither is
  /// a count of hours that goes on with minutes written without a unit ("1 uur
  /// 30") or with a part of the day ("3 uur 's middags"), which are clock times.
  static var dutchLengthPattern: String {
    let minutes = #"(?:minuten|minuut|min\.?)"#
    let hours = #"(?:uren|uur)"#
    let betweenHours = #"(?<!tussen\s{1,3}\d{1,2}(?:[.:]\d{2})?(?:\s{0,3}(?:uur|u))?\s{1,3}en\s{1,3})"#
    let clockContinuation = #"(?!\s*\d{2}(?![\p{N}.,:])|\#(dutchPartAfterHour)\#(dutchEnd))"#
    return
      #"\#(dutchStart)(?:(\#(dutchLengthOpener))\s+|(\#(dutchLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}h]\s?[-–—]\s?)(?<!\d\s?(?:minuten|minuut|min|uren|uur)\.?\s?[-–—]\s?)(?<!\bfor\s)\#(betweenHours)(?:(\d+)\s*\#(hours)\s*(?:en\s+)?(\d{1,2})\s*\#(minutes)|(\d+(?:[.,]\d+)?)\s*\#(hours)\#(clockContinuation)|(\d+)\s*\#(minutes)|(\#(dutchLengthWords)))\#(dutchEnd)(?!\s*[-–—]\s*\d|\s+(?:tot|t/m|tm)\s+\d)(?:\s+lang\#(dutchEnd))?(?:\s+(\#(dutchLengthTrailing))\#(dutchEnd))?"#
  }

  /// Whether a match of ``dutchLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, a difference, the past, or a rate.
  /// Minutes are never a clock time, so such an amount is always kept; an
  /// amount of hours after a word that can lead or bound a clock time ("om 3
  /// uur", "van 14 tot 16 uur") is left to the time rules.
  static func dutchClaimsLength(_ match: Match) -> Bool {
    guard let decliner = match.group(2).map(dutchPhrase) else { return match.group(8) != nil }
    let isMinutes = match.group(6) != nil || (match.group(7).map(dutchPhrase)?.hasSuffix("minuten") ?? false)
    return isMinutes || !dutchClockWords.contains(decliner)
  }

  private static func dutchLength(_ match: Match) -> Int? {
    if match.group(2) != nil || match.group(8) != nil { return nil }
    let opener = match.group(1).map(dutchPhrase)
    if let hours = match.group(3).flatMap(number), let minutes = match.group(4).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(5) {
      guard let hours = decimalAmount(amountText) else { return nil }
      // A dot before two digits that make minutes is a clock time ("15.30
      // uur"), where Dutch writes a decimal fraction with a comma.
      if let clock = amountText.wholeMatch(of: /\d{1,2}\.(\d{2})/), let minutes = number(clock.output.1), minutes < 60 {
        return nil
      }
      if !amountText.contains(where: { $0 == "," || $0 == "." }) {
        // A whole count of hours after "voor" is as often a clock bound ("voor 2
        // uur" is before two o'clock). With no opener, "3 uur" is a length up
        // to 12 hours: a count from 13 or with a leading zero is a clock time
        // as often, and so is a count right after a day ("morgen 9 uur"),
        // unless it is said to be a length ("morgen 3 uur lang").
        if opener == "voor" { return nil }
        if opener == nil, startsWithZero(amountText) || hours > 12 { return nil }
        if opener == nil, dutchFollowsDay(match), !dutchPhrase(match.group(0) ?? "").hasSuffix(" lang") { return nil }
      }
      return taskLength(minutes: Int((hours * 60).rounded()))
    }
    if let minutes = match.group(6).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(7).flatMap(dutchWordLength)
  }

  /// The minutes a length written in words names: "een half uur", "een
  /// halfuurtje", "een kwartier", "drie kwartier", "een uur", "twee uur",
  /// "anderhalf uur", "tweeënhalf uur", "twee en een half uur", "vijftien
  /// minuten".
  private static func dutchWordLength(_ phrase: String) -> Int? {
    let key = dutchPhrase(phrase)
    if key == "anderhalf uur" || key == "anderhalve uur" { return 90 }
    if key.wholeMatch(of: /(?:een )?half ?uur(?:tje)?/) != nil { return 30 }
    if let found = key.wholeMatch(of: /(\S+) kwartier(?:tje)?/), let count = dutchCount(String(found.output.1)) {
      return taskLength(minutes: count * 15)
    }
    if let found = key.wholeMatch(of: /(\S+?) ?(?:en (?:een )?half|enhalf) uur/),
      let count = dutchCount(String(found.output.1))
    {
      return taskLength(minutes: count * 60 + 30)
    }
    if let found = key.wholeMatch(of: /(\S+) uur(?:tje)?/), let count = dutchCount(String(found.output.1)) {
      return taskLength(minutes: count * 60)
    }
    if let found = key.wholeMatch(of: /(\S+) minuten/) {
      let minutes: [String: Int] = [
        "vijf": 5, "tien": 10, "vijftien": 15, "twintig": 20, "vijfentwintig": 25, "dertig": 30, "veertig": 40,
        "vijfenveertig": 45, "zestig": 60,
      ]
      return minutes[String(found.output.1)]
    }
    return nil
  }

  // MARK: - Hour counts written with u

  /// The words before an hour count written with u that say it is a length:
  /// "voor 2u", "gedurende 2u", "duur: 2u".
  private static let dutchLengthLeads: Set<String> = [
    "voor", "gedurende", "duur", "duur:", "tijdsduur", "tijdsduur:", "ongeveer", "circa", "ca", "ca.", "zo'n", "ruim",
    "bijna",
  ]

  /// An hour count written with u and no space: "15u", "15u30", "2u30min", "1,5u",
  /// each maybe after a lead. Groups: 1 the lead; 2 the hours, with a decimal
  /// fraction for a length; 3 minutes written after the u; 4 minutes written
  /// after a space with a unit. The count may not follow a digit, a colon, or a
  /// separator.
  static let dutchHourCountPattern =
    #"\#(dutchStart)(?:(voor|gedurende|duur\s*:?|tijdsduur\s*:?|ongeveer|circa|ca\.?|zo['’]n|ruim|bijna|om|rond|omstreeks|vanaf)\s+)?(?<![\p{N}:.,/])(\d{1,2}(?:[.,]\d+)?)u(?:(\d{2})(?:\s?(?:minuten|minuut|min\.?))?|\s(\d{1,2})\s?(?:minuten|minuut|min\.?))?\#(dutchEnd)"#

  /// Whether an hour count written with u names a length. A decimal count
  /// does, and so does one after a word that opens a length; one with minutes
  /// and their unit after a space does unless a clock lead stands before it.
  /// Any other count ("15u", "9u30", "om 3u") is a clock time, which Dutch
  /// written in Belgium gives with the letter u.
  static func dutchHourCountIsLength(isDecimal: Bool, hasSpacedMinutes: Bool, lead: String?) -> Bool {
    if isDecimal { return true }
    if let lead, dutchLengthLeads.contains(lead) { return true }
    if lead != nil { return false }
    return hasSpacedMinutes
  }

  private static func dutchHourCount(_ match: Match) -> Int? {
    guard let amountText = match.group(2) else { return nil }
    let minutes = (match.group(3) ?? match.group(4)).flatMap(number)
    let isDecimal = amountText.contains { $0 == "," || $0 == "." }
    guard
      dutchHourCountIsLength(
        isDecimal: isDecimal, hasSpacedMinutes: match.group(4) != nil, lead: match.group(1).map(dutchPhrase))
    else { return nil }
    guard let hours = decimalAmount(amountText) else { return nil }
    return taskLength(minutes: Int((hours * 60).rounded()) + (minutes ?? 0))
  }
}
