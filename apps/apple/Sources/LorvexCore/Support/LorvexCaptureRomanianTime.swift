import Foundation

extension LorvexCaptureVocabulary {
  // The Romanian clock-time rules: a time with a lead ("la ora 15", "la 15:30"),
  // with a part of the day, the spoken forms ("la 3 și jumătate"), a range of
  // times, noon and midnight, and the rules that keep a deadline written as a
  // clock time in the title. The vocabulary's other words are in ``romanian``.

  // MARK: - Parts of the day

  /// The words that name a part of the day after an hour, as a pattern without
  /// groups and with the space before them: "dimineața", "seara", "noaptea",
  /// "după-amiaza", "după amiază", "după masă", each maybe with "de" before it
  /// ("la 7 de dimineață", "la 8 de seară").
  static let romanianPartAfterHour =
    #"(?:(?:\s+de)?\s+(?:dimineata|seara|noaptea|noapte)|\s+dupa[\s-]?(?:amiaza|masa))"#

  /// The adverbs of a part of the day that may stand before a lead and its hour
  /// ("seara la 8", "dimineața la 7"), as a pattern without groups.
  private static let romanianPartAdverbs = #"(?:dimineata|seara|noaptea|dupa[\s-]?amiaza|dupa[\s-]?masa)"#

  /// The part of the day a matched word or phrase names: "seara", "de
  /// dimineață", "după-amiaza", "diseară", "cina".
  static func romanianPartOfDay(_ text: String) -> PartOfDay? {
    let key = romanianPhrase(text).replacingOccurrences(of: " ", with: "")
    if key.contains("dupaamiaza") || key.contains("dupamasa") || key.contains("dupamiaza") { return .day }
    if key.contains("dimineata") { return .morning }
    if key.contains("seara") || key.contains("cina") || key.contains("dineu") { return .evening }
    if key.contains("noapte") { return .night }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The 12-hour hours follow
  /// ``partOfDayTime(hour:minute:part:)``: "7 dimineața" is 07:00, "12 la
  /// prânz" noon, "3 după-amiaza" 15:00, "8 seara" 20:00, and "2 noaptea" the
  /// small hours after midnight, on the next day. An hour on the 24-hour clock
  /// (13 to 23) is read as written when its part of the day is one it falls in:
  /// the afternoon is 13 to 18, the evening 16 to 23, and the night 18 to 23.
  private static func romanianTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    if (13...23).contains(hour) {
      let hours: ClosedRange<Int>? =
        switch part {
        case .morning: nil
        case .day: 13...18
        case .evening: 16...23
        case .night: 18...23
        }
      return hours?.contains(hour) == true ? ClockTime(minutes: hour * 60 + minute) : nil
    }
    return partOfDayTime(hour: hour, minute: minute, part: part)
  }

  /// A part of the day anywhere in a line, as a pattern: "diseară", the evening
  /// meal ("cina", "dineu"), a day word with its part ("mâine dimineață",
  /// "azi seara", "în fiecare seară", "în fiecare noapte"), a weekday with its
  /// part ("vineri seara"), or the part alone ("seara", "dimineața").
  private static let romanianLinePartPattern =
    #"\#(romanianStart)(?:diseara|deseara|cina|dineu|(?:azi|astazi|maine|poimaine|in\s+fiecare\s+zi|(?:\#(romanianWeekdayNames)))\s+(?:\#(romanianPartWords))|(?:in\s+fiecare\s+)?\#(romanianPartAdverbs)|in\s+fiecare\s+noapte)\#(romanianEnd)"#

  /// The part of the day the line names beside `match` (within
  /// ``romanianContextLength`` characters of it), for an hour written without
  /// one: "dimineața la 8", "mâine seara la 7", and "diseară la 8" are 08:00,
  /// 19:00, and 20:00, where the hour alone would be 08:00, 07:00, and 08:00. Nil
  /// when the line names no part of the day there, or names two that differ
  /// ("dimineața și seara la 8").
  private static func romanianLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(romanianLinePartPattern) else { return nil }
    let source = match.source
    let own = match.result.range
    let lower = max(0, own.location - romanianContextLength)
    let upper = min(source.utf16.count, NSMaxRange(own) + romanianContextLength)
    var named: PartOfDay?
    for found in regex.matches(
      in: source, options: [.withTransparentBounds, .withoutAnchoringBounds],
      range: NSRange(location: lower, length: upper - lower))
    {
      guard NSIntersectionRange(found.range, own).length == 0,
        let range = Range(found.range, in: source), let part = romanianPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no part
  /// or two, or the part has no such hour.
  private static func romanianTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match)
    -> ClockTime?
  {
    guard !hasLeadingZero, (1...12).contains(hour), let part = romanianLinePartOfDay(beside: match) else { return nil }
    return romanianTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part
  /// of the day of its own) names: its line's part of the day when the line
  /// names one, else the hour as ``bareTime(hour:minute:hasLeadingZero:)``
  /// reads it.
  private static func romanianBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    romanianTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, or colon
  /// (the word or the number goes on), no letter joined by a hyphen, no decimal
  /// fraction, no percent or currency sign with or without a space before it,
  /// and no dash before a digit, which makes the time one side of a range
  /// written with a dash.
  static let romanianTimeEnd =
    #"(?![\p{Latin}\p{N}\p{M}:]|[-–]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d|\s*[ap]\.?m\.?(?![\p{Latin}\p{M}]))"#

  /// The words before a clock time that make it a bound, not a start: "până la
  /// 17", "cel târziu la 17", "după 18", "înainte de 17".
  private static let romanianBoundWords: Set<String> = ["pana", "dupa", "inainte", "tarziu", "devreme"]

  /// The words before a number that name what it counts, so a range of bare
  /// numbers after them is no range of hours ("capitolele de la 3 la 5").
  private static let romanianCountedWords: Set<String> = [
    "capitolul", "capitolele", "capitol", "capitole", "pagina", "pagini", "paginile", "pag", "slide", "slideul",
    "slideurile", "tema", "temele", "exercitiul", "exercitiu", "exercitiile", "sarcina", "sarcinile", "task",
    "taskul", "pretul", "pret", "preturile", "costul", "cost", "varsta", "anii", "ani", "euro", "lei", "zilele",
    "zile", "saptamanile", "locul", "loc", "locurile", "locuri", "camera", "camerele", "sala", "numarul", "numar",
    "numerele", "nr", "punctul", "punct", "punctele", "nivelul", "nivel", "clasa", "grupa", "peronul", "linia",
    "liniile", "cartea", "cartile", "randul", "randurile", "articolul", "articolele", "paragraful", "temperatura",
    "gradele", "greutatea", "greutate", "bugetul", "buget", "suma", "salariul", "salariu", "tariful", "tarif",
    "scorul", "scor", "nota", "valoarea", "valoare", "totalul", "total", "cantitatea", "cantitate", "pasii", "pasul",
    "pas", "runda",
  ]

  /// The words before a clock time that make it a time to start at, as a
  /// pattern without groups: "la ora", "la orele", "pe la ora", "în jurul
  /// orei", "ora", "orele", "de la ora", "de la", "pe la", "la".
  private static let romanianClockLead =
    #"(?:de\s+la\s+ora|de\s+la\s+orele|de\s+la|pe\s+la\s+ora|pe\s+la|la\s+ora|la\s+orele|in\s+jurul\s+orei|orele|ora|la)"#

  /// Whether a clock lead, as ``romanianPhrase(_:)`` leaves it, names the hour
  /// itself ("ora", "la ora", "pe la ora", "în jurul orei", "de la ora"), so a
  /// bare hour or a dotted time after it is a time.
  private static func romanianIsStrongLead(_ lead: String?) -> Bool {
    guard let lead else { return false }
    return lead.hasSuffix("ora") || lead.hasSuffix("orele") || lead.hasSuffix("orei")
  }

  /// Whether the word just before `match` makes its clock time a bound.
  private static func romanianFollowsBoundWord(_ match: Match) -> Bool {
    wordBefore(match).map { romanianBoundWords.contains(romanianKey($0)) } ?? false
  }

  /// Whether a number stands just before `match` ("de la 3 la 5"), which makes a
  /// bare hour after "la" the end of a range of numbers, not a time.
  private static func romanianFollowsNumber(_ match: Match) -> Bool {
    romanianTextBefore(match).last(where: { !$0.isWhitespace })?.isNumber ?? false
  }

  // MARK: - Clock time

  /// "la ora 15", "ora 15", "la 15:30", "ora 15.30", "la trei", "pe la 5", "la 8
  /// seara", "la 7 dimineața", "la 8 de seară", "ora 3 după-amiază", "8 seara",
  /// "7:30 seara", "seara la 8", "dimineața 7:30", and a colon time with the
  /// part of the day another word of the line names ("diseară 7:30"). An hour
  /// spelled as a word needs a lead and has no minutes. A time written with no
  /// Romanian word ("15:30", "3pm") is left to English. Groups: 1 the lead; 2
  /// hour, 3 the colon or the dot, 4 minute, 5 the part of the day; 6 to 9 an
  /// hour with a part of the day and no lead (6 hour, 7 separator, 8 minute, 9
  /// part); 10 to 14 an hour after the adverb of its part of the day (10 the
  /// adverb, 11 the lead, 12 hour, 13 separator, 14 minute); 15 to 17 a colon
  /// time with nothing else (15 hour, 16 the colon, 17 minute).
  static var romanianClockPattern: String {
    let part = #"(\#(romanianPartAfterHour))"#
    let hourOrWord = #"(\d{1,2}|\#(romanianHourWords))(?:([.:])(\d{2}))?"#
    let digits = #"(\d{1,2})(?:([.:])(\d{2}))?"#
    let unattached = #"\#(romanianStart)(?<![\p{N}:.,])(?<![-–—])(?<![-–—]\s)"#
    let leading = #"\#(romanianStart)(\#(romanianClockLead))\s+\#(hourOrWord)\#(part)?\#(romanianTimeEnd)"#
    let partOnly = #"\#(unattached)\#(digits)\#(part)\#(romanianTimeEnd)"#
    // The adverb after "fiecare" is the unit of a repeat ("în fiecare seară la
    // 8"), which the hour that follows it does not join.
    let afterPart =
      #"\#(romanianStart)(?<!fiecare\s{1,3})(\#(romanianPartAdverbs))\s+(?:(\#(romanianClockLead))\s+)?\#(hourOrWord)\#(romanianTimeEnd)"#
    let colonOnly = #"\#(unattached)(\d{1,2})(:)(\d{2})\#(romanianTimeEnd)"#
    return [leading, partOnly, afterPart, colonOnly].joined(separator: "|")
  }

  static func romanianClock(_ match: Match) -> ClockTime? {
    let hourText: String
    let separator: String?
    let minuteText: String?
    let partText: String?
    let lead: String?
    let isLeading = match.group(2) != nil
    let isAfterPart = match.group(12) != nil
    let isColonOnly = match.group(15) != nil
    if isLeading {
      (hourText, separator, minuteText, partText, lead) = (
        match.group(2) ?? "", match.group(3), match.group(4), match.group(5), match.group(1).map(romanianPhrase)
      )
    } else if match.group(6) != nil {
      (hourText, separator, minuteText, partText, lead) = (
        match.group(6) ?? "", match.group(7), match.group(8), match.group(9), nil
      )
    } else if isAfterPart {
      (hourText, separator, minuteText, partText, lead) = (
        match.group(12) ?? "", match.group(13), match.group(14), match.group(10), match.group(11).map(romanianPhrase)
      )
    } else if isColonOnly {
      (hourText, separator, minuteText, partText, lead) = (
        match.group(15) ?? "", match.group(16), match.group(17), nil, nil
      )
    } else {
      return nil
    }
    guard let hour = romanianCount(hourText) else { return nil }
    let isWord = number(hourText) == nil
    // An hour spelled as a word has no minutes after it.
    if isWord, separator != nil { return nil }
    var minute = 0
    if let minuteText {
      guard let value = number(minuteText) else { return nil }
      minute = value
    }
    guard (0...59).contains(minute), !romanianFollowsBoundWord(match) else { return nil }
    // An adverb of a part of the day takes an hour through a lead or a colon
    // ("seara la 8", "seara 8:30"); a bare number after it may count anything.
    if isAfterPart, lead == nil, separator != ":" { return nil }
    if isLeading, partText == nil {
      if minuteText == nil {
        // A bare hour is a time after a lead that names the hour ("ora 3"), or
        // after "la" or "pe la" when the line goes on with nothing or a word
        // that can follow a time; "de la 3" opens a range and "la 3 prieteni"
        // counts something.
        guard let lead else { return nil }
        if !romanianIsStrongLead(lead) {
          guard lead != "de la", !romanianFollowsNumber(match), romanianFollowsAsDetail(match) else { return nil }
        }
      } else if separator == ".", minute != 0, minute < 13, !romanianIsStrongLead(lead) {
        // "La 15.10" may be a date; after "ora" a dotted time is a time.
        return nil
      }
    }
    if hour == 24 { return nil }
    guard (0...23).contains(hour) else { return nil }
    if isWord, !(1...12).contains(hour) { return nil }
    if let partText {
      guard let part = romanianPartOfDay(partText) else { return nil }
      return romanianTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(hourText)
    // A colon time with no Romanian word and no part of the day in the line is
    // English's.
    if isColonOnly {
      return romanianTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    }
    return romanianBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
  }

  /// "la 3pm", "la 3:30 pm", "ora 3 pm", "pe la 3pm": a time with AM or PM after
  /// a Romanian lead, which takes the lead with it where English would leave
  /// "la" behind. A time with AM or PM and no lead is English's. Groups: 1
  /// hour, 2 minute, 3 the "a" or "p".
  static let romanianMeridiemTimePattern =
    #"\#(romanianStart)(?:la\s+ora|la\s+orele|pe\s+la|orele|ora|la)\s+(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}\p{M}:])"#

  static func romanianMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased()
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Spoken times

  /// The minutes a spoken time may name after "și" or "fără", as a pattern
  /// without groups: digits and the number words five, ten, fifteen, twenty,
  /// and twenty-five.
  private static let romanianSpokenMinutes = #"(?:\d{1,2}|cincisprezece|douazeci\s+si\s+cinci|douazeci|zece|cinci)"#

  /// The minutes a spoken amount names: digits or one of the words
  /// ``romanianSpokenMinutes`` allows.
  private static func romanianMinuteCount(_ text: String) -> Int? {
    if let digits = number(text) { return digits }
    let words: [String: Int] = [
      "cinci": 5, "zece": 10, "cincisprezece": 15, "douazeci": 20, "douazeci si cinci": 25,
    ]
    return words[romanianPhrase(text)]
  }

  /// "la 3 și jumătate" (3:30), "la 3 și un sfert" (3:15), "la 3 fără un sfert"
  /// (2:45), "la 3 fără 10" (2:50), "la 3 și 10" (3:10), "ora trei și jumătate",
  /// each with its lead and maybe before a part of the day ("la 3 și jumătate
  /// după-amiaza"), with the hour in words or digits. The lead is required: "3
  /// și jumătate" alone is as often an amount. The minutes take no unit word
  /// (see ``romanianSpokenMinutesWithUnitPattern``). Groups: 1 the lead, 2 the
  /// hour, 3 the amount after "și", 4 the amount after "fără", 5 the part of
  /// the day.
  static var romanianSpokenTimePattern: String {
    let amount = romanianSpokenMinutes
    return
      #"\#(romanianStart)(\#(romanianClockLead))\s+(\d{1,2}|\#(romanianHourWords))\s+(?:si\s+(jumatate|jumate|un\s+sfert|\#(amount))|fara\s+(un\s+sfert|\#(amount)))(\#(romanianPartAfterHour))?\#(romanianTimeEnd)"#
  }

  /// A spoken time whose minutes carry a unit word: "la 3 și 10 minute", "ora
  /// trei fără zece minute", "la ora 15 și 30 de minute". A count of minutes
  /// is a length elsewhere in the line, and the lengths of other languages read
  /// "10 min" wherever it stands, so the phrase would split into the hour and a
  /// length with "și" left behind. It stays in the title whole instead, where
  /// the same minutes with no unit ("la 3 și 10") are read as a time.
  static var romanianSpokenMinutesWithUnitPattern: String {
    #"\#(romanianStart)(?:\#(romanianClockLead))\s+(?:\d{1,2}|\#(romanianHourWords))\s+(?:si|fara)\s+\#(romanianSpokenMinutes)(?:\s+de)?\s+(?:minute|minut|min\.?)(?![\p{Latin}\p{M}])"#
  }

  static func romanianSpokenTime(_ match: Match) -> ClockTime? {
    guard let hourText = match.group(2), let value = romanianCount(hourText), (1...12).contains(value) else {
      return nil
    }
    // The hour before `hour` on a clock of 12 hours.
    func before(_ hour: Int) -> Int { hour == 1 ? 12 : hour - 1 }
    let hour: Int
    let minute: Int
    if let amount = match.group(3) {
      hour = value
      switch romanianPhrase(amount) {
      case "jumatate", "jumate": minute = 30
      case "un sfert": minute = 15
      default:
        guard let minutes = romanianMinuteCount(amount), (1...59).contains(minutes) else { return nil }
        minute = minutes
      }
    } else if let amount = match.group(4) {
      hour = before(value)
      if romanianPhrase(amount) == "un sfert" {
        minute = 45
      } else {
        guard let minutes = romanianMinuteCount(amount), (1...29).contains(minutes) else { return nil }
        minute = 60 - minutes
      }
    } else {
      return nil
    }
    guard !romanianFollowsBoundWord(match) else { return nil }
    if let partText = match.group(5) {
      guard let part = romanianPartOfDay(partText) else { return nil }
      return romanianTimeWithPart(hour: hour, minute: minute, part: part)
    }
    return romanianBareTime(hour: hour, minute: minute, hasLeadingZero: false, match: match)
  }

  // MARK: - Noon and midnight

  /// "la prânz", "la amiază", "la miezul zilei" (noon), "la miezul nopții", "la
  /// miez de noapte" (midnight), each maybe after "pe". "De la prânz" opens a
  /// range and stays. Groups: 1 noon, 2 midnight.
  static let romanianNoonOrMidnightPattern =
    #"\#(romanianStart)(?<!de\s)(?:pe\s+)?la\s+(?:(pranz(?:ul)?|amiaza|miezul\s+zilei)|(miezul\s+noptii|miez\s+de\s+noapte))\#(romanianEnd)"#

  static func romanianNoonOrMidnight(_ match: Match) -> ClockTime? {
    if match.group(1) != nil { return ClockTime(minutes: 12 * 60) }
    return match.group(2) != nil ? ClockTime(minutes: 0, isAfterMidnight: true) : nil
  }

  // MARK: - Time range

  /// The words that may open a range of times: "de la", "între", "la".
  private static let romanianRangeOpener = #"de\s+la|intre|la"#

  /// The body of the range pattern, with its groups capturing or not. A side is
  /// a time written in digits ("14", "14:30", "14.30"), maybe after "ora" or
  /// "orele" and before a part of the day.
  private static func romanianTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let digits = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2})?"#
    let marker = #"(?:\#(group("ora|orele"))\s+)?"#
    let part = #"(?:\#(group(romanianPartAfterHour)))?"#
    let word = #"pana\s+la|pana\s+in|pana|la|si"#
    let connector = #"(?:\s+\#(group(word))\s+|\s*\#(group("[-–—]"))\s*)"#
    return
      #"(?:\#(group(romanianRangeOpener))\s+)?\#(marker)\#(group(digits))\#(part)\#(connector)\#(marker)\#(group(digits))\#(part)"#
  }

  /// "de la 14 la 16", "de la 14:00 până la 16:30", "între 14 și 16", "ora
  /// 14-16", "orele 14-16", "14:00-16:00", "14.00 - 16.00", "de la 8 la 10
  /// dimineața", "între 2 și 4 după-amiaza". Groups: 1 the opener, 2 "ora" or
  /// "orele" before the start, 3 the start, 4 its part of the day, 5 "la",
  /// "până la", or "și", 6 a dash, 7 "ora" or "orele" before the end, 8 the end,
  /// 9 its part of the day.
  static var romanianTimeRangePattern: String {
    #"\#(romanianStart)\#(romanianTimeRangeBody(capturing: true))\#(romanianTimeEnd)"#
  }

  static func romanianTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(3), let endText = match.group(8) else { return nil }
    let lead = match.group(1).map(romanianPhrase)
    let word = match.group(5).map(romanianPhrase)
    let hasMarker = match.group(2) != nil || match.group(7) != nil
    let startPart = match.group(4)
    let endPart = match.group(9)
    let hasPart = startPart != nil || endPart != nil
    let hasMinutes = [startText, endText].contains { $0.contains(":") || $0.contains(".") }
    // "Și" joins the sides only after "între", which takes no dash and no "la";
    // "la" joins them only after "de la".
    if word == "si", lead != "intre" { return nil }
    if lead == "intre", word != "si" { return nil }
    if word == "la", lead != "de la" { return nil }
    if let word, word.hasPrefix("pana"), lead != "de la", !(hasMarker || hasPart || hasMinutes) { return nil }
    if lead == nil, match.group(6) != nil, !hasMarker, !hasPart {
      // "14:00-16:00" is English's, unless the line names a part of the day that
      // English cannot give the hours.
      guard hasMinutes, romanianLinePartOfDay(beside: match) != nil else { return nil }
    }
    if !(hasMarker || hasPart || hasMinutes) {
      // Two bare hours are as often an amount or numbered items: they are a
      // range only after "de la", "între", or "la" and where the line goes on
      // with a word that can follow a time and no word that names an amount or
      // numbered items comes before it ("capitolele de la 3 la 5").
      guard lead != nil, romanianFollowsAsDetail(match) else { return nil }
      if let before = wordBefore(match), romanianCountedWords.contains(romanianKey(before)) { return nil }
      // A start on the 24-hour clock ends at a later hour on it.
      if let first = number(startText), first > 12, let last = number(endText), last <= first { return nil }
    }
    if romanianFollowsBoundWord(match) { return nil }
    let sharedPart = (endPart ?? startPart).flatMap(romanianPartOfDay)
    guard
      let start = romanianRangeSide(startText, part: startPart, shared: sharedPart, hasMarker: hasMarker, match: match),
      let end = romanianRangeSide(endText, part: endPart, shared: sharedPart, hasMarker: hasMarker, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its own part of
  /// the day, the one the other side names, or the one the line names
  /// elsewhere. Dotted minutes that are a month ("5.10") make a date, not a
  /// time, unless "ora" or a part of the day says it is a time.
  private static func romanianRangeSide(
    _ text: String, part: String?, shared: PartOfDay?, hasMarker: Bool, match: Match
  ) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    let kind = part.flatMap(romanianPartOfDay) ?? shared
    if side.output.2 == ".", (1...12).contains(minute), !hasMarker, kind == nil { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    if let kind { return romanianTimeWithPart(hour: hour, minute: minute, part: kind) }
    return romanianBareTime(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// The spoken forms of a time, as a pattern without groups: "3 și jumătate",
  /// "3 și un sfert", "3 fără un sfert", "3 fără 10", "3 și 10".
  private static var romanianSpokenShapes: String {
    #"(?:\d{1,2}|\#(romanianHourWords))\s+(?:si\s+(?:jumatate|jumate|un\s+sfert|\#(romanianSpokenMinutes))|fara\s+(?:un\s+sfert|\#(romanianSpokenMinutes)))"#
  }

  /// A clock time as a pattern without groups: a colon time ("17:30"), a dotted
  /// time whose minutes cannot be a month ("17.30"), an hour or a time after
  /// "ora" or "orele" ("ora 17", "orele 17.30"), an hour with a part of the day
  /// ("5 seara", "5:30 după-amiaza"), or a spoken time ("3 și jumătate").
  private static var romanianClockShape: String {
    let digits =
      #"(?<![\p{N}:.,])(?:\d{1,2}:\d{2}|\d{1,2}\.(?:00|1[3-9]|[2-5]\d)|\d{1,2}(?:[.:]\d{2})?\#(romanianPartAfterHour))"#
    let afterHourWord = #"(?:ora|orele)\s+\d{1,2}(?:[.:]\d{2})?"#
    return #"(?:\#(afterHourWord)|\#(digits)|\#(romanianSpokenShapes))"#
  }

  /// A clock time written as a bound ("până la ora 17", "până la 17:00", "înainte
  /// de 17:00", "cel târziu la ora 17", "după ora 18", "nu mai târziu de ora
  /// 17", "până la 5 seara"), which names no start time. Group 1 is the bound,
  /// or nil for a range ("de la 14 la 17:30"), which the range rule reads and
  /// this rule only steps over, so the "la 17:30" inside it is not taken for a
  /// bound.
  static var romanianDeadlineClockPattern: String {
    let bound =
      #"pana\s+(?:la|in)|pana|cel\s+tarziu(?:\s+(?:pana\s+la|la|in))?|cel\s+devreme(?:\s+la)?|inainte\s+de|dupa|nu\s+mai\s+(?:tarziu|devreme)\s+de"#
    return
      #"\#(romanianStart)(?:\#(romanianTimeRangeBody(capturing: false))|((?:\#(bound))\s+\#(romanianClockShape)))\#(romanianTimeEnd)"#
  }

  /// The clock after a deadline day ("până vineri la ora 17", "cel târziu mâine
  /// la 9:00"), which is a deadline's clock and stays in the title with the rest
  /// of the line once the day is read as the due day.
  static var romanianDueClockPattern: String {
    #"\#(romanianStart)(?:(?:la|pe\s+la|de\s+la)\s+)?\#(romanianClockShape)\#(romanianTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a
  /// word that introduces a due day, the day, with a comma or a space before the
  /// clock.
  private static let romanianAfterDueDayPattern = #"(?:^|\s)\#(romanianDueLead)(?:\#(romanianDueDay))\s*,?\s*$"#

  /// The text before a clock that ends a range of days or of weekdays ("de la 3
  /// la 5 mai", "de la luni până miercuri"), whose "până" and day are no
  /// deadline.
  private static var romanianAfterRangePattern: String {
    #"(?:\#(romanianDateRangePattern)|\#(romanianWeekdayRangePattern))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a deadline word and a day ("până
  /// vineri", "cel târziu mâine"). The "până" of a range of days is no deadline
  /// word, so the clock after "de la luni până miercuri" is the range's time.
  static func romanianIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = romanianTextBefore(match)
    let whole = NSRange(before.startIndex..., in: before)
    if let range = LorvexCapturePatterns.regex(romanianAfterRangePattern),
      range.firstMatch(in: before, range: whole) != nil
    {
      return false
    }
    guard let regex = LorvexCapturePatterns.regex(romanianAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: whole) != nil
  }
}
