import Foundation

extension LorvexCaptureVocabulary {
  // The Dutch clock-time rules: a time with a lead, with "uur" or "u", or with
  // a part of the day, the spoken forms ("half vier"), a range of times,
  // midnight, and the rules that keep a deadline written as a clock time in
  // the title. The vocabulary's other words are in ``dutch``.

  // MARK: - Parts of the day

  /// The words that name a part of the day after an hour, as a pattern without
  /// groups and with the space before them: "'s ochtends", "'s middags", "'s
  /// avonds", "'s nachts" (with the apostrophe straight, curly, or left out,
  /// and the "s" apart from the word or not), "avonds", "in de middag". A bare
  /// "morgen" is tomorrow, so it is no part of the day here.
  static let dutchPartAfterHour =
    #"(?:(?:\s*['’]s\s*|\s+s\s*|\s+)(?:ochtends|morgens|voormiddags|middags|namiddags|avonds|nachts)|\s+in\s+de\s+(?:ochtend|morgen|voormiddag|middag|namiddag|avond|nacht))"#

  /// The adverbs of a part of the day that may stand before a lead and its
  /// hour ("'s avonds om 8", "avonds om 8"), as a pattern without groups.
  private static let dutchPartAdverbs =
    #"(?:['’]s\s*|s\s+)?(?:ochtends|morgens|voormiddags|middags|namiddags|avonds|nachts)"#

  /// The part of the day a matched word or phrase names: "'s avonds", "in de
  /// middag", "vanavond", "vrijdagochtend".
  static func dutchPartOfDay(_ text: String) -> PartOfDay? {
    let key = dutchPhrase(text)
    // The last part of a compound decides ("morgenavond" is an evening), so
    // "morgen", which also means tomorrow, is tried last.
    if key.contains("avond") || key.contains("diner") { return .evening }
    if key.contains("nacht") { return .night }
    if key.contains("voormiddag") { return .morning }
    if key.contains("middag") { return .day }
    if key.contains("ochtend") || key.contains("vroeg") || key.contains("morgen") { return .morning }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The 12-hour hours follow
  /// ``partOfDayTime(hour:minute:part:)``: "8 uur 's ochtends" is 08:00, "12 uur
  /// 's middags" noon, "3 uur 's middags" 15:00, "8 uur 's avonds" 20:00, and
  /// "2 uur 's nachts" the small hours after midnight, on the next day. An hour
  /// on the 24-hour clock (13 to 23) is read as written when its part of the
  /// day is one it falls in: the afternoon is 13 to 18, the evening 16 to 23,
  /// and the night 18 to 23.
  private static func dutchTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
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

  /// A part of the day anywhere in a line, as a pattern: an adverb ("'s
  /// avonds", "ochtends"), the evening meals ("avondeten", "diner"), a day
  /// word with its part ("vanavond", "morgenochtend", "morgen vroeg", "elke
  /// ochtend"), or a weekday with the part written onto it or after it
  /// ("vrijdagavond", "vrijdag avond").
  private static let dutchLinePartPattern =
    #"\#(dutchStart)(?:vanochtend|vanmorgen|vanmiddag|vanavond|vannacht|avondeten|avondmaal|diner|\#(dutchPartAdverbs)|(?:vandaag|morgen|overmorgen|elke|iedere|elk|ieder)\s*(?:ochtend|morgen|voormiddag|middag|namiddag|avond|nacht|vroeg)|(?:\#(dutchWeekdayNames))(?:ochtend|morgen|voormiddag|middag|namiddag|avond|nacht|vroeg|\s+(?:ochtend|morgen|voormiddag|middag|namiddag|avond|nacht)))\#(dutchEnd)"#

  /// The part of the day the line names beside `match` (within
  /// ``dutchContextLength`` characters of it), for an hour written without one:
  /// "'s ochtends om 8", "morgen vroeg om 6", and "vanavond om 8" are 08:00,
  /// 06:00, and 20:00, where the hour alone would be 08:00, 18:00, and 08:00. Nil
  /// when the line names no part of the day there, or names two that differ
  /// ("'s ochtends en 's avonds om 8").
  private static func dutchLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(dutchLinePartPattern) else { return nil }
    let source = match.source
    let own = match.result.range
    let lower = max(0, own.location - dutchContextLength)
    let upper = min(source.utf16.count, NSMaxRange(own) + dutchContextLength)
    var named: PartOfDay?
    for found in regex.matches(
      in: source, options: [.withTransparentBounds, .withoutAnchoringBounds],
      range: NSRange(location: lower, length: upper - lower))
    {
      guard NSIntersectionRange(found.range, own).length == 0,
        let range = Range(found.range, in: source), let part = dutchPartOfDay(String(source[range]))
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
  private static func dutchTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = dutchLinePartOfDay(beside: match) else { return nil }
    return dutchTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part
  /// of the day of its own) names: its line's part of the day when the line
  /// names one, else the hour as ``bareTime(hour:minute:hasLeadingZero:)``
  /// reads it.
  private static func dutchBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    dutchTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, colon, or
  /// apostrophe (the word or the number goes on), no letter joined by a hyphen
  /// ("15 uur-afspraak"), no decimal fraction, no percent or currency sign with
  /// or without a space before it, and no dash before a digit, which makes the
  /// time one side of a range written with a dash.
  static let dutchTimeEnd =
    #"(?![\p{Latin}\p{N}\p{M}'’:]|[-–]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d|\s*[ap]\.?m\.?(?![\p{Latin}\p{M}]))"#

  /// The words before an hour that make it a bound, not a start: "tot 17 uur",
  /// "voor 17 uur", "tegen 17 uur", "uiterlijk 17 uur", "na 18 uur", "niet
  /// later dan 17 uur", "ten laatste 17 uur".
  private static let dutchBoundWords: Set<String> = [
    "tot", "voor", "tegen", "uiterlijk", "na", "dan", "laatste", "vroegste",
  ]

  /// The words before a number that name what it counts, so a range of bare
  /// numbers after them is no range of hours ("hoofdstuk van 3 tot 5").
  private static let dutchCountedWords: Set<String> = [
    "hoofdstuk", "hoofdstukken", "pagina", "pagina's", "bladzijde", "bladzijden", "blz", "dia", "dia's", "opdracht",
    "opdrachten", "taak", "taken", "prijs", "prijzen", "kosten", "leeftijd", "jaar", "jaren", "euro", "dag", "dagen",
    "week", "weken", "plaats", "plaatsen", "kamer", "lokaal", "nummer", "nummers", "nr", "punt", "punten", "deel",
    "delen", "niveau", "klas", "groep", "spoor", "perron", "boek", "boeken", "regel", "regels", "artikel", "artikelen",
    "paragraaf", "temperatuur", "graden", "gewicht", "lengte", "breedte", "hoogte", "budget", "bedrag", "salaris",
    "tarief", "loon", "huur", "score", "cijfer", "aantal", "waarde", "totaal",
  ]

  /// The words before a clock time that make it a time to start at: "om",
  /// "rond", "omstreeks", "vanaf", and the approximations "ongeveer", "circa",
  /// and "ca.", as a pattern without groups.
  private static let dutchClockLead = #"(?:om|rond|omstreeks|vanaf|ongeveer|circa|ca\.?)"#

  /// Whether a clock lead, as ``dutchPhrase(_:)`` leaves it, is one a bare hour
  /// may follow ("om 3", "rond 15") or one a dotted time reads after ("om
  /// 15.30"): "om", "rond", and "omstreeks".
  private static func dutchIsStrongLead(_ lead: String) -> Bool {
    ["om", "rond", "omstreeks"].contains(lead)
  }

  /// Whether the word just before `match` makes its clock time a bound.
  private static func dutchFollowsBoundWord(_ match: Match) -> Bool {
    wordBefore(match).map { dutchBoundWords.contains(dutchKey($0)) } ?? false
  }

  // MARK: - Clock time

  /// The hours Dutch spells as words after a lead ("om drie", "om twaalf uur"):
  /// "een" through "twaalf", as a pattern without groups.
  private static let dutchHourWords = "twaalf|elf|tien|negen|acht|zeven|zes|vijf|vier|drie|twee|een"

  /// "om 15:00", "om 15.30 uur", "om 3 uur", "om 15u", "om 15u30", "om drie
  /// uur", "rond 15:00", "vanaf 15:30", "om 3", "15:30 uur", "15.30 uur", "15u",
  /// "15u30", "3 uur 's middags", "8 uur 's avonds", "7:30 's avonds", "8 's
  /// avonds", "'s avonds om 8", "'s avonds 7:30", "'s avonds 8 uur", and a
  /// colon time with the part of the day another word of the line names
  /// ("vanavond 7:30"). An hour spelled as a word needs a lead and has no
  /// minutes. A time written with no Dutch word ("15:30", "3pm") is left to
  /// English, and "3 uur" with no lead and no part of the day is a length.
  /// Groups: 1 the lead; 2 hour, 3 the colon or the dot, 4 minute, 5 "uur" or
  /// "u", 6 the minutes after it, 7 the part of the day; 8 to 13 the same
  /// without a lead; 14 to 17 an hour with a part of the day and no unit (14
  /// hour, 15 separator, 16 minute, 17 part); 18 to 20 a colon time with
  /// nothing else (18 hour, 19 the colon, 20 minute); 21 to 27 an hour after
  /// the adverb of its part of the day, with a lead, with minutes, or with
  /// "uur" (21 the adverb, 22 the lead, 23 hour, 24 separator, 25 minute, 26
  /// unit, 27 the minutes after it).
  static var dutchClockPattern: String {
    let part = #"(\#(dutchPartAfterHour))"#
    let hour = #"(\d{1,2})(?:([.:])(\d{2}))?"#
    let hourOrWord = #"(\d{1,2}|\#(dutchHourWords))(?:([.:])(\d{2}))?"#
    let unit = #"(?:\s*(uur|u)(?:\s*(\d{2}))?)?"#
    let unattached = #"\#(dutchStart)(?<![\p{N}:.,])(?<![-–—])(?<![-–—]\s)"#
    let leading =
      #"\#(dutchStart)(\#(dutchClockLead))\s+\#(hourOrWord)\#(unit)\#(part)?\#(dutchTimeEnd)"#
    let marked = #"\#(unattached)\#(hour)\s*(uur|u)(?:\s*(\d{2}))?\#(part)?\#(dutchTimeEnd)"#
    let partOnly = #"\#(unattached)\#(hour)\#(part)\#(dutchTimeEnd)"#
    let colonOnly = #"\#(unattached)(\d{1,2})(:)(\d{2})\#(dutchTimeEnd)"#
    let afterPart =
      #"\#(dutchStart)(\#(dutchPartAdverbs))\s+(?:(\#(dutchClockLead))\s+)?\#(hourOrWord)\#(unit)\#(dutchTimeEnd)"#
    return [leading, marked, partOnly, colonOnly, afterPart].joined(separator: "|")
  }

  static func dutchClock(_ match: Match) -> ClockTime? {
    let base: Int
    if match.group(2) != nil {
      base = 2
    } else if match.group(8) != nil {
      base = 8
    } else if match.group(14) != nil {
      base = 14
    } else if match.group(18) != nil {
      base = 18
    } else if match.group(23) != nil {
      base = 23
    } else {
      return nil
    }
    let hasUnitGroups = base == 2 || base == 8 || base == 23
    guard let hourText = match.group(base), let hour = dutchCount(hourText) else { return nil }
    let lead = (base == 2 ? match.group(1) : (base == 23 ? match.group(22) : nil)).map(dutchPhrase)
    let separator = match.group(base + 1)
    // An hour spelled as a word has no minutes after it, in digits or in words
    // ("om elf uur dertig" stays whole).
    if number(hourText) == nil, separator != nil || wordAfter(match).flatMap(dutchCount) != nil { return nil }
    let unit = hasUnitGroups ? match.group(base + 3)?.lowercased() : nil
    let minuteText = match.group(base + 2)
    let minutesAfter = hasUnitGroups ? match.group(base + 4) : nil
    let partText: String? =
      switch base {
      case 2: match.group(7)
      case 8: match.group(13)
      case 14: match.group(17)
      case 23: match.group(21)
      default: nil
      }
    var minute = 0
    if let minuteText {
      guard let value = number(minuteText) else { return nil }
      minute = value
    }
    if let minutesAfter {
      guard minuteText == nil, let value = number(minutesAfter) else { return nil }
      minute = value
    }
    guard (0...59).contains(minute), !dutchFollowsBoundWord(match) else { return nil }
    let hasMinutes = minuteText != nil || minutesAfter != nil
    // An adverb of a part of the day takes an hour through a lead, a colon, or
    // "uur" ("'s avonds om 8", "'s avonds 8:30", "'s avonds 8 uur"); a bare
    // number after it ("'s avonds 8") may count anything.
    if base == 23, lead == nil, separator != ":", unit != "uur" { return nil }
    // "Vanaf 5.10" and "ca. 5.10" may be dates; after "om" and "rond" and with
    // a unit a dotted time is a time.
    if separator == ".", let lead, !dutchIsStrongLead(lead), unit == nil, minute != 0, minute < 13 { return nil }
    if hour == 24 {
      return unit != nil && minute == 0 && partText == nil ? ClockTime(minutes: 0, isAfterMidnight: true) : nil
    }
    guard (0...23).contains(hour) else { return nil }
    if let partText {
      guard let part = dutchPartOfDay(partText) else { return nil }
      return dutchTimeWithPart(hour: hour, minute: minute, part: part)
    }
    // "3 uur" with no lead and no part of the day is a length of three hours,
    // unless it follows a day ("morgen 9 uur").
    if base == 8, unit == "uur", !hasMinutes, !dutchFollowsDay(match) { return nil }
    let hasLeadingZero = startsWithZero(hourText)
    if base == 2, unit == nil, !hasMinutes {
      // A bare hour is a time after "om", "rond", and "omstreeks" when the line
      // goes on with a word that can follow a time ("om 3 met Anna") and not
      // with a counted noun ("om 3 koekjes").
      guard let lead, dutchIsStrongLead(lead), dutchFollowsAsDetail(match) else { return nil }
    }
    // A colon time with no Dutch word and no part of the day in the line is
    // English's.
    if base == 18 {
      return dutchTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    }
    return dutchBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
  }

  /// An hour count written with u and no space ("om 15u", "15u30", "om 3u")
  /// that ``dutchHourCountIsLength(isDecimal:hasSpacedMinutes:lead:)`` reads as
  /// a clock time.
  static func dutchHourClock(_ match: Match) -> ClockTime? {
    guard let hourText = match.group(2), !hourText.contains(where: { $0 == "," || $0 == "." }),
      let hour = number(hourText), (0...23).contains(hour)
    else { return nil }
    let minuteText = match.group(3) ?? match.group(4)
    let minute = minuteText.flatMap(number) ?? 0
    guard (0...59).contains(minute), !dutchFollowsBoundWord(match),
      !dutchHourCountIsLength(isDecimal: false, hasSpacedMinutes: match.group(4) != nil, lead: match.group(1).map(dutchPhrase))
    else { return nil }
    return dutchBareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText), match: match)
  }

  /// "om 3pm", "om 3:30 pm", "rond 3 pm", "vanaf 3pm": a time with AM or PM
  /// after a Dutch lead, which takes the lead with it where English would
  /// leave "om" behind. A time with AM or PM and no lead is English's. Groups:
  /// 1 hour, 2 minute, 3 the "a" or "p".
  static let dutchMeridiemTimePattern =
    #"\#(dutchStart)(?:om|rond|omstreeks|vanaf)\s+(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}\p{M}'’:])"#

  static func dutchMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased()
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Spoken times

  /// The hours a spoken time names, as a pattern without groups: the number
  /// words one to twelve and digits.
  private static let dutchSpokenHour = #"(?:twaalf|elf|tien|negen|acht|zeven|zes|vijf|vier|drie|twee|een|\d{1,2})"#

  /// The shapes of a spoken time, as a pattern without groups: "half vier",
  /// "kwart over drie", "kwart voor vier", "tien over drie", "vijf voor vier",
  /// "vijf voor half vier", "vijf over half vier".
  private static let dutchSpokenShapes =
    #"(?:half\s+\#(dutchSpokenHour)|kwart\s+(?:over|voor)\s+\#(dutchSpokenHour)|(?:vijf|tien|twintig|5|10|20)\s+(?:over|voor)\s+(?:half\s+)?\#(dutchSpokenHour))"#

  /// "half vier" (half past three, 3:30), "kwart over drie" (3:15), "kwart voor
  /// vier" (3:45), "tien over drie" (3:10), "tien voor vier" (3:50), "vijf voor
  /// half vier" (3:25), "vijf over half vier" (3:35), each maybe after a lead
  /// ("om half vier") and before a part of the day ("half vier 's middags"),
  /// with the hour in words or digits. Groups: 1 the lead, 2 "half" and 3 its
  /// hour, 4 "kwart", 5 over or voor, and 6 the hour, 7 the minutes, 8 over or
  /// voor, 9 "half", 10 the hour, 11 the part of the day.
  static var dutchSpokenTimePattern: String {
    let hour = dutchSpokenHour
    let forms = [
      #"(half)\s+(\#(hour))"#,
      #"(kwart)\s+(over|voor)\s+(\#(hour))"#,
      #"(vijf|tien|twintig|5|10|20)\s+(over|voor)\s+(?:(half)\s+)?(\#(hour))"#,
    ]
    return
      #"\#(dutchStart)(?:(\#(dutchClockLead))\s+)?(?:\#(forms.joined(separator: "|")))(\#(dutchPartAfterHour))?\#(dutchTimeEnd)"#
  }

  /// Reads a spoken time. `line` is the match of the range rule when `match`
  /// is one side of a time range read apart from it: the part of the day the
  /// line names then comes from `line`, and the words that judge a time with no
  /// lead (an article "een", a bare digit hour) are the range's to judge.
  static func dutchSpokenTime(_ match: Match, line: Match? = nil) -> ClockTime? {
    func count(_ text: String?) -> Int? {
      text.flatMap(dutchCount)
    }
    // An hour on the clock of 12 hours.
    func hourValue(_ text: String?) -> Int? {
      count(text).flatMap { (1...12).contains($0) ? $0 : nil }
    }
    // The hour before `hour` on a clock of 12 hours.
    func before(_ hour: Int) -> Int { hour == 1 ? 12 : hour - 1 }
    let lead = match.group(1).map(dutchPhrase)
    let hour: Int
    let minute: Int
    var needsLead = false
    // The groups are numbered by form: "half" 2-3, "kwart" 4-6, a count of
    // minutes 7-10; the part of the day is 11.
    var hourText = ""
    if match.group(2) != nil {
      guard let value = hourValue(match.group(3)) else { return nil }
      hour = before(value)
      minute = 30
      hourText = match.group(3) ?? ""
    } else if match.group(4) != nil {
      guard let value = hourValue(match.group(6)), let direction = match.group(5)?.lowercased() else { return nil }
      hour = direction == "over" ? value : before(value)
      minute = direction == "over" ? 15 : 45
      hourText = match.group(6) ?? ""
    } else if let minutesText = match.group(7) {
      guard let value = hourValue(match.group(10)), let minutes = count(minutesText),
        let direction = match.group(8)?.lowercased()
      else { return nil }
      let isHalf = match.group(9) != nil
      switch (direction == "over", isHalf) {
      case (true, false): hour = value; minute = minutes
      case (false, false): hour = before(value); minute = 60 - minutes
      case (true, true): hour = before(value); minute = 30 + minutes
      case (false, true): hour = before(value); minute = 30 - minutes
      }
      needsLead = true
      hourText = match.group(10) ?? ""
    } else {
      return nil
    }
    guard (1...12).contains(hour), (0...59).contains(minute), !dutchFollowsBoundWord(match) else { return nil }
    if needsLead, lead == nil { return nil }
    // "Een" is also the article, so "een" after "half" or "over" is an hour
    // only after a lead ("om half een").
    if line == nil, lead == nil, dutchKey(hourText) == "een" { return nil }
    // A bare digit hour with no lead ("half 4") is a time only where a word
    // that can follow a time comes next.
    if line == nil, lead == nil, number(hourText) != nil, !dutchFollowsAsDetail(match) { return nil }
    if let partText = match.group(11) {
      guard let part = dutchPartOfDay(partText) else { return nil }
      return dutchTimeWithPart(hour: hour, minute: minute, part: part)
    }
    return dutchBareTime(hour: hour, minute: minute, hasLeadingZero: false, match: line ?? match)
  }

  // MARK: - Midnight

  /// "om middernacht", "rond middernacht". A "middernacht" alone is as often a
  /// name or a word of the title.
  static let dutchMidnightPattern = #"\#(dutchStart)(?:om|rond|omstreeks)\s+middernacht\#(dutchEnd)"#

  /// The midnight that ends the day.
  static func dutchMidnight(_ match: Match) -> ClockTime? {
    ClockTime(minutes: 0, isAfterMidnight: true)
  }

  // MARK: - Time range

  /// The words that may open a range of times: "van", "tussen", "om", "vanaf",
  /// "rond".
  private static let dutchRangeOpener = "van|tussen|om|vanaf|rond"

  /// The body of the range pattern, with its groups capturing or not. A side
  /// is a time written in digits ("14", "14:30", "14.30", "14u30") or a spoken
  /// one that needs no lead ("half drie", "kwart over drie").
  private static func dutchTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let digits = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2}|u(?:\d{2})?)?"#
    let side =
      #"(?:\#(digits)|half\s+\#(dutchSpokenHour)|kwart\s+(?:over|voor)\s+\#(dutchSpokenHour))"#
    let unit = #"(?:\s*\#(group("uur")))?"#
    let part = #"(?:\#(group(dutchPartAfterHour)))?"#
    let word = #"tot\s+en\s+met|t\s*/\s*m|tm|tot|en"#
    let connector = #"(?:\s+\#(group(word))\s+|\s*\#(group("[-–—]"))\s*)"#
    return
      #"(?:\#(group(dutchRangeOpener))\s+)?\#(group(side))\#(unit)\#(part)\#(connector)\#(group(side))\#(unit)\#(part)"#
  }

  /// "van 14 tot 16 uur", "van 14:00 tot 16:30", "van 9 uur tot 17 uur", "tussen
  /// 14 en 16 uur", "14-16 uur", "14 tot 16 uur", "om 14-16 uur", "van 8 tot 10 uur
  /// 's ochtends", "van 14.00 tot 16.00 uur", "van 14u tot 16u". Groups: 1 the
  /// opener, 2 the start, 3 its "uur", 4 its part of the day, 5 "tot", "tot en
  /// met", "t/m", or "en", 6 a dash, 7 the end, 8 its "uur", 9 its part of the
  /// day.
  static var dutchTimeRangePattern: String {
    #"\#(dutchStart)\#(dutchTimeRangeBody(capturing: true))\#(dutchTimeEnd)"#
  }

  static func dutchTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(7) else { return nil }
    let lead = match.group(1).map(dutchPhrase)
    let word = match.group(5).map { dutchPhrase($0).replacingOccurrences(of: " ", with: "") }
    func isSpoken(_ text: String) -> Bool { text.first.map { !$0.isNumber } ?? false }
    func isHourWithU(_ text: String) -> Bool { text.contains { $0 == "u" || $0 == "U" } && !isSpoken(text) }
    let hasUnit = match.group(3) != nil || match.group(8) != nil || isHourWithU(startText) || isHourWithU(endText)
    let startPart = match.group(4)
    let endPart = match.group(9)
    let hasPart = startPart != nil || endPart != nil
    let hasColon = startText.contains(":") || endText.contains(":")
    let hasSpoken = isSpoken(startText) || isSpoken(endText)
    // "En" joins the sides only after "tussen", which takes no dash and no
    // "tot".
    if word == "en", lead != "tussen" { return nil }
    if lead == "tussen", word != "en" { return nil }
    if lead == nil, match.group(6) != nil, !hasUnit, !hasPart, !hasSpoken {
      // "14:00-16:00" is English's, unless the line names a part of the day
      // that English cannot give the hours.
      guard hasColon, dutchLinePartOfDay(beside: match) != nil else { return nil }
    }
    if !(hasUnit || hasPart || hasColon || hasSpoken) {
      // Two bare hours are as often an amount or numbered items: they are a
      // range only after "van", "tussen", "om", "vanaf", or "rond" and where
      // the line goes on with a word that can follow a time and no word that
      // names an amount or numbered items comes before it ("hoofdstuk van 3 tot
      // 5").
      guard lead != nil, dutchFollowsAsDetail(match) else { return nil }
      if let before = wordBefore(match), dutchCountedWords.contains(dutchKey(before)) { return nil }
      // A start on the 24-hour clock ends at a later hour on it, so "vanaf
      // 15-10" is a date and no range of hours.
      if let first = number(startText), first > 12, let last = number(endText), last <= first { return nil }
    }
    if dutchFollowsBoundWord(match) { return nil }
    let sharedPart = (endPart ?? startPart).flatMap(dutchPartOfDay)
    guard
      let start = dutchRangeSide(startText, part: startPart, shared: sharedPart, hasUnit: hasUnit, lead: lead, match: match),
      let end = dutchRangeSide(endText, part: endPart, shared: sharedPart, hasUnit: hasUnit, lead: lead, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its own part of
  /// the day, the one the other side names, or the one the line names
  /// elsewhere. Dotted minutes that are a month ("5.10") make a date, not a
  /// time, unless "uur" or "om" says it is a time. A spoken side ("half drie")
  /// reads as ``dutchSpokenTime(_:line:)`` does.
  private static func dutchRangeSide(
    _ text: String, part: String?, shared: PartOfDay?, hasUnit: Bool, lead: String?, match: Match
  ) -> ClockTime? {
    if text.first.map({ !$0.isNumber }) == true {
      let kind = part.flatMap(dutchPartOfDay) ?? shared
      return wholeTime(text, pattern: dutchSpokenTimePattern, in: match) { side in
        let spoken = dutchSpokenTime(side, line: match)
        // A part of the day the range names moves the spoken hour to it.
        guard let kind, let spoken, let hour = spoken.writtenHour else { return spoken }
        return dutchTimeWithPart(hour: hour, minute: spoken.minutes % 60, part: kind)
      }
    }
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2})|u(\d{2})?)?/), let hour = number(side.output.1)
    else { return nil }
    let minute = (side.output.3 ?? side.output.4).flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    if side.output.2 == ".", (1...12).contains(minute), !hasUnit, lead != "om" { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    let kind = part.flatMap(dutchPartOfDay) ?? shared
    if let kind { return dutchTimeWithPart(hour: hour, minute: minute, part: kind) }
    return dutchBareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time as a pattern without groups: a colon time ("17:30", "17:30
  /// uur"), an hour with "uur" ("17 uur", "17.30 uur", "17 uur 30"), an hour
  /// with u ("17u", "17u30"), a dotted time whose minutes cannot be a month
  /// ("17.30"), or a spoken time ("half vijf").
  private static var dutchClockShape: String {
    let digits =
      #"(?<![\p{N}:.,])(?:\d{1,2}:\d{2}(?:\s*uur)?|\d{1,2}(?:[.:]\d{2})?\s*uur(?:\s*\d{2})?|\d{1,2}u(?:\d{2})?|\d{1,2}\.(?:00|1[3-9]|[2-5]\d))"#
    return #"(?:\#(digits)|\#(dutchSpokenShapes))"#
  }

  /// A clock time written as a bound ("tot 17 uur", "voor 17:00", "tegen 17
  /// uur", "uiterlijk 17:00", "uiterlijk om 17 uur", "na 18 uur", "niet later dan
  /// 17 uur", "tot half vijf"), which names no start time. Group 1 is the
  /// bound, or nil for a range ("van 14 tot 17:30"), which the range rule reads
  /// and this rule only steps over, so the "tot 17:30" inside it is not taken for
  /// a bound.
  static var dutchDeadlineClockPattern: String {
    let bound =
      #"tot(?:\s+en\s+met)?|voor|tegen|uiterlijk(?:\s+(?:om|voor|tegen|tot))?|ten\s+laatste(?:\s+om)?|ten\s+vroegste(?:\s+om)?|na|niet\s+(?:later|eerder)\s+dan"#
    // The spoken times "vijf voor half vier" and "tien over half vier" hold a
    // "voor" or "over" before a spoken time, which is no bound either.
    let minutesAround = #"(?:vijf|tien|twintig|5|10|20)\s+(?:over|voor)\s+(?:half\s+)?\#(dutchSpokenHour)"#
    return
      #"\#(dutchStart)(?:\#(dutchTimeRangeBody(capturing: false))|\#(minutesAround)|((?:\#(bound))\s+(?:om\s+)?\#(dutchClockShape)))\#(dutchTimeEnd)"#
  }

  /// The clock after a deadline day ("voor vrijdag om 17 uur", "uiterlijk
  /// morgen 9:00"), which is a deadline's clock and stays in the title with the
  /// rest of the line once the day is read as the due day.
  static var dutchDueClockPattern: String {
    #"\#(dutchStart)(?:(?:om|rond|vanaf|tegen)\s+)?\#(dutchClockShape)\#(dutchTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a
  /// word that introduces a due day, the day, with a comma or a space before the
  /// clock.
  private static let dutchAfterDueDayPattern = #"(?:^|\s)\#(dutchDueLead)(?:\#(dutchDueDay))\s*,?\s*$"#

  /// The text before a clock that ends a range of days or of weekdays ("van 3
  /// tot 5 mei", "van maandag tot woensdag"), whose "tot" and day are no
  /// deadline.
  private static var dutchAfterRangePattern: String {
    #"(?:\#(dutchDateRangePattern)|\#(dutchWeekdayRangePattern))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a deadline word and a day
  /// ("voor vrijdag", "uiterlijk morgenochtend"). The "tot" of a range of days
  /// is no deadline word, so the clock after "van maandag tot woensdag" is the
  /// range's time.
  static func dutchIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = dutchTextBefore(match)
    let whole = NSRange(before.startIndex..., in: before)
    if let range = LorvexCapturePatterns.regex(dutchAfterRangePattern),
      range.firstMatch(in: before, range: whole) != nil
    {
      return false
    }
    guard let regex = LorvexCapturePatterns.regex(dutchAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: whole) != nil
  }
}
