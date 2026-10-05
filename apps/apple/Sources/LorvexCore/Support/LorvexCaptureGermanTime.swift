import Foundation

extension LorvexCaptureVocabulary {
  // The German clock-time rules: a time with a lead, with "Uhr", or with a
  // part of the day, the spoken forms ("halb vier"), a range of times, noon
  // and midnight, and the rules that keep a deadline written as a clock time
  // in the title. The vocabulary's other words are in ``german``.

  // MARK: - Parts of the day

  /// The words that name a part of the day beside an hour, as a pattern
  /// without groups: "morgens", "vormittags", "mittags", "nachmittags",
  /// "abends", "nachts", "früh", "in der Früh", "am Morgen", "am Vormittag",
  /// "am Mittag", "am Nachmittag", "am Abend", "in der Nacht". A bare "morgen"
  /// is tomorrow, so it is no part of the day here.
  static let germanPartOfDayWords =
    #"morgens|vormittags|mittags|nachmittags|abends|nachts|(?:in\s+der\s+)?früh|am\s+(?:morgen|vormittag|mittag|nachmittag|abend)|in\s+der\s+nacht"#

  /// The part of the day a matched word or phrase names, by its last word:
  /// "abends", "am Abend", "heute Abend", "Samstagabend".
  static func germanPartOfDay(_ text: String) -> PartOfDay? {
    guard let word = germanPhrase(text).split(separator: " ").last.map(String.init) else { return nil }
    if word.contains("nachmittag") { return .day }
    if word.contains("vormittag") || word.contains("morgen") || word.contains("fruh") { return .morning }
    if word.contains("mittag") { return .day }
    if word.contains("nacht") { return .night }
    if word.contains("abend") { return .evening }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The 12-hour hours follow
  /// ``partOfDayTime(hour:minute:part:)``: "8 Uhr morgens" is 08:00, "12 Uhr
  /// mittags" noon, "3 Uhr nachmittags" 15:00, "8 Uhr abends" 20:00, and "2 Uhr
  /// nachts" the small hours after midnight, on the next day. An hour on the
  /// 24-hour clock (13 to 23) is read as written when its part of the day is
  /// one it falls in: the afternoon is 13 to 18, the evening 16 to 23, and the
  /// night 18 to 23.
  private static func germanTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
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

  /// A part of the day anywhere in a line, as a pattern: an adverb ("morgens",
  /// "abends", "früh"), the evening meals ("Abendessen", "Abendbrot"), a noun
  /// after a word that makes it the day's part ("heute Abend", "morgen
  /// Nachmittag", "jeden Morgen", "am Abend"), or a weekday with the part
  /// written onto it or after it ("Freitagabend", "Freitag Abend").
  private static let germanLinePartPattern = german(
    #"\#(germanStart)(?:morgens|vormittags|mittags|nachmittags|abends|nachts|früh|abendessen|abendbrot|(?:heute|morgen|übermorgen|jeden|jede|diesen|dieser|am)\s+(?:morgen|vormittag|mittag|nachmittag|abend|nacht)|(?:\#(germanWeekdayNames))(?:abend|nachmittag|vormittag|nacht|früh|morgen|mittag|\s+(?:morgen|vormittag|mittag|nachmittag|abend|nacht)))\#(germanEnd)"#)

  /// The part of the day the line names beside `match` (within
  /// ``germanContextLength`` characters of it), for an hour written without
  /// one: "morgens um 8", "morgen früh um 6", and "heute Abend um 8" are
  /// 08:00, 06:00, and 20:00, where the hour alone would be 08:00, 18:00, and
  /// 08:00. Nil when the line names no part of the day there, or names two
  /// that differ ("morgens und abends um 8").
  private static func germanLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(germanLinePartPattern) else { return nil }
    let source = match.source
    let own = match.result.range
    let lower = max(0, own.location - germanContextLength)
    let upper = min(source.utf16.count, NSMaxRange(own) + germanContextLength)
    var named: PartOfDay?
    for found in regex.matches(
      in: source, options: [.withTransparentBounds, .withoutAnchoringBounds],
      range: NSRange(location: lower, length: upper - lower))
    {
      guard NSIntersectionRange(found.range, own).length == 0,
        let range = Range(found.range, in: source), let part = germanPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no
  /// part or two, or the part has no such hour.
  private static func germanTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = germanLinePartOfDay(beside: match) else { return nil }
    return germanTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no
  /// part of the day of its own) names: its line's part of the day when the
  /// line names one, else the hour as ``bareTime(hour:minute:hasLeadingZero:)``
  /// reads it.
  private static func germanBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    germanTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// The words before an hour that make it a bound, not a start: "bis 17
  /// Uhr", "spätestens 17 Uhr", "frühestens 9 Uhr", "vor 8 Uhr", "nach 18 Uhr".
  private static let germanBoundWords: Set<String> = ["bis", "spatestens", "fruhestens", "vor", "nach"]

  /// The words before a number that name what it counts, so a range of bare
  /// numbers after them is no range of hours ("Kapitel von 3 bis 5").
  private static let germanCountedWords: Set<String> = [
    "kapitel", "seite", "seiten", "folie", "folien", "aufgabe", "aufgaben", "preis", "preise", "kosten", "alter",
    "jahre", "jahren", "euro", "tag", "tage", "tagen", "woche", "wochen", "platz", "platze", "zimmer", "raum",
    "nummer", "nr", "punkt", "punkte", "teil", "teile", "stufe", "klasse", "gruppe", "gleis", "buch", "bucher",
    "zeile", "zeilen", "artikel", "absatz", "paragraph", "temperatur", "grad", "gewicht", "lange", "hohe", "breite",
  ]

  /// The colloquial "so" before "um" or "gegen" ("so um 3", "so gegen 15"), as
  /// a pattern without groups. After a word that points at a weekday the "So"
  /// is Sunday ("am So um 10"), so it opens no lead there.
  static let germanSoLead =
    #"(?:(?<!(?:am|an|auf|für|ab|von|vom|bis|jeden|diesen|nächsten|übernächsten|kommenden)\s)so\s+)"#

  /// The words before a clock time that make it a time to start at: "um",
  /// "gegen" (each maybe after "so" and before "die" or an approximation:
  /// "so um", "um die", "um ca."), "ab", and the approximations "ca.",
  /// "circa", "zirka", "etwa", and "ungefähr", as a pattern without groups.
  private static let germanClockLead =
    #"(?:\#(germanSoLead)?(?:um|gegen)(?:\s+(?:die|ca\.?|circa|zirka|etwa|ungefähr))?|ab|ca\.?|circa|zirka|etwa|ungefähr)"#

  /// Whether a clock lead, as ``germanPhrase(_:)`` leaves it, is one a bare
  /// hour may follow ("um 3", "gegen 15", "um die 3") or one a dotted time
  /// reads after ("um 15.30"): "um" and "gegen", with what goes with them.
  private static func germanIsStrongLead(_ lead: String) -> Bool {
    ["um", "gegen", "so um", "so gegen"].contains { lead == $0 || lead.hasPrefix($0 + " ") }
  }

  /// Whether the word just before `match` makes its clock time a bound.
  private static func germanFollowsBoundWord(_ match: Match) -> Bool {
    wordBefore(match).map { germanBoundWords.contains(germanKey($0)) } ?? false
  }

  // MARK: - Clock time

  /// The adverbs of a part of the day that may stand before a lead and its
  /// hour ("abends um 8"), as a pattern without groups.
  private static let germanPartAdverbs = "morgens|vormittags|mittags|nachmittags|abends|nachts"

  /// The hours German spells as words after a lead ("um drei", "um zwölf Uhr"):
  /// "ein" and "eins" through "zwölf", as a pattern without groups.
  private static let germanHourWords = "eins|ein|zwei|zwo|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf"

  /// "um 15 Uhr", "um 15:30", "um 15.30 Uhr", "um 15 Uhr 30", "um 3", "um drei
  /// Uhr", "gegen 15 Uhr", "ab 15:30", "ca. 15 Uhr", "15 Uhr", "15:30 Uhr",
  /// "15.30 Uhr", "15 Uhr 30", "um 8 Uhr morgens", "um 3 Uhr nachmittags", "8
  /// abends", "7:30 abends", "abends um 8", "abends 7:30", "abends 7 Uhr", and
  /// a colon time with the part of the day another word of the line names
  /// ("heute Abend 7:30"). An hour spelled as a word needs a lead and has no
  /// minutes. A time written with no German word ("15:30", "3pm") is left to
  /// English. Groups: 1 the lead; 2 hour, 3 the colon or the dot, 4 minute, 5
  /// "Uhr", 6 the minutes after it, 7 the part of the day; 8 to 13 the same
  /// without a lead; 14 to 17 an hour with a part of the day and no "Uhr" (14
  /// hour, 15 separator, 16 minute, 17 part); 18 to 20 a colon time with
  /// nothing else (18 hour, 19 the colon, 20 minute); 21 to 27 an hour after
  /// the adverb of its part of the day, with a lead or with minutes or "Uhr"
  /// (21 the adverb, 22 the lead, 23 hour, 24 separator, 25 minute, 26 "Uhr",
  /// 27 the minutes after it).
  static var germanClockPattern: String {
    let part = #"(?:\s+(\#(germanPartOfDayWords)))"#
    let hour = #"(\d{1,2})(?:([.:])(\d{2}))?"#
    let hourOrWord = #"(\d{1,2}|\#(germanHourWords))(?:([.:])(\d{2}))?"#
    let unattached = #"\#(germanStart)(?<![\p{N}:.,])(?<![-–—])(?<![-–—]\s)"#
    let leading =
      #"\#(germanStart)(\#(germanClockLead))\s+\#(hourOrWord)(?:\s*(uhr)(?:\s+(\d{2}))?)?\#(part)?\#(germanTimeEnd)"#
    let marked = #"\#(unattached)\#(hour)\s*(uhr)(?:\s+(\d{2}))?\#(part)?\#(germanTimeEnd)"#
    let partOnly = #"\#(unattached)\#(hour)\#(part)\#(germanTimeEnd)"#
    let colonOnly = #"\#(unattached)(\d{1,2})(:)(\d{2})\#(germanTimeEnd)"#
    let afterPart =
      #"\#(germanStart)(\#(germanPartAdverbs))\s+(?:(\#(germanClockLead))\s+)?\#(hourOrWord)(?:\s*(uhr)(?:\s+(\d{2}))?)?\#(germanTimeEnd)"#
    return [leading, marked, partOnly, colonOnly, afterPart].joined(separator: "|")
  }

  static func germanClock(_ match: Match) -> ClockTime? {
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
    let hasUhrGroups = base == 2 || base == 8 || base == 23
    guard let hourText = match.group(base), let hour = germanCount(hourText) else { return nil }
    let lead = (base == 2 ? match.group(1) : (base == 23 ? match.group(22) : nil)).map(germanPhrase)
    let separator = match.group(base + 1)
    // An hour spelled as a word has no minutes after it, in digits or in words
    // ("um elf Uhr dreißig" stays whole).
    if number(hourText) == nil, separator != nil || wordAfter(match).flatMap(germanCount) != nil { return nil }
    let hasUhr = hasUhrGroups && match.group(base + 3) != nil
    let minuteText = match.group(base + 2)
    let minutesAfter = hasUhrGroups ? match.group(base + 4) : nil
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
    guard (0...59).contains(minute), !germanFollowsBoundWord(match) else { return nil }
    let hasMinutes = minuteText != nil || minutesAfter != nil
    // An adverb of a part of the day takes a bare hour only through a lead.
    if base == 23, lead == nil, !hasUhr, separator != ":" { return nil }
    // "Ab 5.10" and "ca. 5.10" may be dates; after "um" and "gegen" and with
    // "Uhr" a dotted time is a time.
    if separator == ".", let lead, !germanIsStrongLead(lead), !hasUhr, minute != 0, minute < 13 { return nil }
    if hour == 24 {
      return hasUhr && minute == 0 && partText == nil ? ClockTime(minutes: 0, isAfterMidnight: true) : nil
    }
    guard (0...23).contains(hour) else { return nil }
    if let partText {
      guard let part = germanPartOfDay(partText) else { return nil }
      return germanTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(hourText)
    if base == 2, !hasUhr, !hasMinutes {
      // A bare hour is a time after "um" and "gegen" when the line goes on
      // with a word that can follow a time ("um 3 mit Anna") and not with a
      // counted noun ("um 3 Kuchen").
      guard let lead, germanIsStrongLead(lead), germanFollowsAsDetail(match) else { return nil }
    }
    // A colon time with no German word and no part of the day in the line is
    // English's.
    if base == 18 { return germanTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match) }
    return germanBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
  }

  /// An hour count written with h and no space ("um 15h", "15h30", "um 3h")
  /// that ``germanHourCountReading(hours:hasMinutes:hasLeadingZero:isDecimal:opener:)``
  /// reads as a clock time.
  static func germanHourClock(_ match: Match) -> ClockTime? {
    guard let hourText = match.group(2), !hourText.contains(where: { $0 == "," || $0 == "." }),
      let hour = number(hourText), (0...23).contains(hour)
    else { return nil }
    let minuteText = match.group(3) ?? match.group(4)
    let minute = minuteText.flatMap(number) ?? 0
    guard (0...59).contains(minute), !germanFollowsBoundWord(match),
      germanHourCountReading(
        hours: hour, hasMinutes: minuteText != nil, hasLeadingZero: startsWithZero(hourText), isDecimal: false,
        opener: match.group(1)) == .clock
    else { return nil }
    return germanBareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText), match: match)
  }

  /// "um 3pm", "um 3:30 pm", "gegen 3 pm", "ab 3pm": a time with AM or PM
  /// after a German lead, which takes the lead with it where English would
  /// leave "um" behind. A time with AM or PM and no lead is English's.
  /// Groups: 1 hour, 2 minute, 3 the "a" or "p".
  static let germanMeridiemTimePattern =
    #"\#(germanStart)(?:um|gegen|ab)\s+(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}'’:])"#

  static func germanMeridiemTime(_ match: Match) -> ClockTime? {
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
  private static let germanSpokenHour = #"(?:zwölf|zehn|neun|acht|sieben|sechs|fünf|vier|drei|zwei|zwo|elf|eins|ein|\d{1,2})"#

  /// The shapes of a spoken time, as a pattern without groups: "halb vier",
  /// "viertel vier", "dreiviertel vier", "Viertel nach drei", "Viertel vor
  /// vier", "fünf nach drei", "zehn vor vier", "fünf vor halb vier", "zehn
  /// nach halb vier".
  private static let germanSpokenShapes =
    #"(?:halb\s+\#(germanSpokenHour)|(?:dreiviertel|drei\s+viertel|viertel)\s+(?:(?:nach|vor)\s+)?\#(germanSpokenHour)|(?:fünf|zehn|zwanzig|5|10|20)\s+(?:nach|vor)\s+(?:halb\s+)?\#(germanSpokenHour))"#

  /// "halb vier" (half past three, 3:30), "viertel vier" (3:15), "dreiviertel
  /// vier" (3:45), "Viertel nach drei" (3:15), "Viertel vor vier" (3:45),
  /// "fünf nach drei" (3:05), "zehn vor vier" (3:50), "fünf vor halb vier"
  /// (3:25), "zehn nach halb vier" (3:40), each maybe after a lead ("um halb
  /// vier") and before a part of the day ("halb vier nachmittags"), with the
  /// hour in words or digits. Groups: 1 the lead, 2 "halb" and 3 its hour, 4
  /// the quarter word and 5 its hour, 6 "viertel", 7 nach or vor, and 8 the
  /// hour, 9 the minutes, 10 nach or vor, 11 "halb", 12 the hour, 13 the part
  /// of the day.
  static var germanSpokenTimePattern: String {
    let hour = germanSpokenHour
    let forms = [
      #"(halb)\s+(\#(hour))"#,
      #"(viertel)\s+(nach|vor)\s+(\#(hour))"#,
      #"(dreiviertel|drei\s+viertel|viertel)\s+(\#(hour))"#,
      #"(fünf|zehn|zwanzig|5|10|20)\s+(nach|vor)\s+(?:(halb)\s+)?(\#(hour))"#,
    ]
    return
      #"\#(germanStart)(?:(\#(germanClockLead))\s+)?(?:\#(forms.joined(separator: "|")))(?:\s+(\#(germanPartOfDayWords)))?\#(germanTimeEnd)"#
  }

  static func germanSpokenTime(_ match: Match) -> ClockTime? {
    func count(_ text: String?) -> Int? {
      guard let text else { return nil }
      return number(text) ?? germanCounts[germanKey(text)]
    }
    // An hour on the clock of 12 hours.
    func hourValue(_ text: String?) -> Int? {
      count(text).flatMap { (1...12).contains($0) ? $0 : nil }
    }
    // The hour before `hour` on a clock of 12 hours.
    func before(_ hour: Int) -> Int { hour == 1 ? 12 : hour - 1 }
    let lead = match.group(1).map(germanPhrase)
    let hour: Int
    let minute: Int
    var needsLead = false
    // The groups are numbered by form: "halb" 2-3, "viertel nach/vor" 4-6, the
    // quarter word 7-8, a count of minutes 9-12; the part of the day is 13.
    if match.group(2) != nil {
      guard let value = hourValue(match.group(3)) else { return nil }
      hour = before(value)
      minute = 30
    } else if match.group(4) != nil {
      guard let value = hourValue(match.group(6)), let direction = match.group(5)?.lowercased() else { return nil }
      hour = direction == "nach" ? value : before(value)
      minute = direction == "nach" ? 15 : 45
    } else if let word = match.group(7) {
      guard let value = hourValue(match.group(8)) else { return nil }
      hour = before(value)
      minute = germanKey(word) == "viertel" ? 15 : 45
      needsLead = true
    } else if let minutesText = match.group(9) {
      guard let value = hourValue(match.group(12)), let minutes = count(minutesText),
        let direction = match.group(10)?.lowercased()
      else { return nil }
      let isHalf = match.group(11) != nil
      switch (direction == "nach", isHalf) {
      case (true, false): hour = value; minute = minutes
      case (false, false): hour = before(value); minute = 60 - minutes
      case (true, true): hour = before(value); minute = 30 + minutes
      case (false, true): hour = before(value); minute = 30 - minutes
      }
      needsLead = true
    } else {
      return nil
    }
    guard (1...12).contains(hour), (0...59).contains(minute), !germanFollowsBoundWord(match) else { return nil }
    if needsLead, lead == nil { return nil }
    // A bare digit hour with no lead ("halb 4") is a time only where a word
    // that can follow a time comes next.
    let hourText = match.group(3) ?? match.group(6) ?? match.group(8) ?? match.group(12) ?? ""
    if lead == nil, number(hourText) != nil, !germanFollowsAsDetail(match) { return nil }
    if let partText = match.group(13) {
      guard let part = germanPartOfDay(partText) else { return nil }
      return germanTimeWithPart(hour: hour, minute: minute, part: part)
    }
    return germanBareTime(hour: hour, minute: minute, hasLeadingZero: false, match: match)
  }

  // MARK: - Noon and midnight

  /// "um Mitternacht", "gegen Mitternacht", "um Mittag", "gegen Mittag". A
  /// "Mitternacht" or "Mittag" alone is as often a name or a meal.
  static let germanNoonOrMidnightPattern = #"\#(germanStart)(?:um|gegen|ab)\s+(mitternacht|mittag)\#(germanEnd)"#

  /// The midnight that ends the day, or noon.
  static func germanNoonOrMidnight(_ match: Match) -> ClockTime? {
    switch match.group(1).map(germanKey) {
    case "mitternacht": ClockTime(minutes: 0, isAfterMidnight: true)
    case "mittag": ClockTime(minutes: 12 * 60)
    default: nil
    }
  }

  // MARK: - Time range

  /// The words that may open a range of times: "von", "zwischen", "um", "ab",
  /// "gegen". "Vom" opens a range of dates.
  private static let germanRangeOpener = "von|zwischen|um|ab|gegen"

  /// The body of the range pattern, with its groups capturing or not.
  private static func germanTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let side = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2})?"#
    let uhr = #"(?:\s*\#(group("uhr")))?"#
    let part = #"(?:\s+\#(group(germanPartOfDayWords)))?"#
    let connector = #"(?:\s+\#(group("bis|und"))\s+|\s*\#(group("[-–—]"))\s*)"#
    return
      #"(?:\#(group(germanRangeOpener))\s+)?\#(group(side))\#(uhr)\#(part)\#(connector)\#(group(side))\#(uhr)\#(part)"#
  }

  /// "von 14 bis 16 Uhr", "von 14:00 bis 16:30", "von 9 Uhr bis 17 Uhr",
  /// "zwischen 14 und 16 Uhr", "14-16 Uhr", "14 bis 16 Uhr", "um 14-16 Uhr", "von
  /// 8 bis 10 Uhr morgens", "von 14.00 bis 16.00 Uhr". Groups: 1 the opener, 2
  /// the start, 3 its "Uhr", 4 its part of the day, 5 "bis" or "und", 6 a
  /// dash, 7 the end, 8 its "Uhr", 9 its part of the day.
  static var germanTimeRangePattern: String {
    #"\#(germanStart)\#(germanTimeRangeBody(capturing: true))\#(germanTimeEnd)"#
  }

  static func germanTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(7) else { return nil }
    let lead = match.group(1).map(germanPhrase)
    let word = match.group(5).map(germanKey)
    let hasUhr = match.group(3) != nil || match.group(8) != nil
    let startPart = match.group(4)
    let endPart = match.group(9)
    let hasPart = startPart != nil || endPart != nil
    let hasColon = startText.contains(":") || endText.contains(":")
    // "Und" joins the sides only after "zwischen", which takes no dash and no
    // "bis".
    if word == "und", lead != "zwischen" { return nil }
    if lead == "zwischen", word != "und" { return nil }
    if lead == nil, match.group(6) != nil, !hasUhr, !hasPart {
      // "14:00-16:00" is English's, unless the line names a part of the day
      // that English cannot give the hours.
      guard hasColon, germanLinePartOfDay(beside: match) != nil else { return nil }
    }
    if !(hasUhr || hasPart || hasColon) {
      // Two bare hours are as often an amount or numbered items: they are a
      // range only after "von", "um", "ab", or "gegen" and where the line
      // goes on with a word that can follow a time and no word that names an
      // amount or numbered items comes before it ("Kapitel von 3 bis 5").
      guard let lead, lead != "zwischen", germanFollowsAsDetail(match) else { return nil }
      if let before = wordBefore(match), germanCountedWords.contains(germanKey(before)) { return nil }
    }
    if germanFollowsBoundWord(match) { return nil }
    let sharedPart = (endPart ?? startPart).flatMap(germanPartOfDay)
    guard let start = germanRangeSide(startText, part: startPart, shared: sharedPart, hasUhr: hasUhr, lead: lead, match: match),
      let end = germanRangeSide(endText, part: endPart, shared: sharedPart, hasUhr: hasUhr, lead: lead, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its own part
  /// of the day, the one the other side names, or the one the line names
  /// elsewhere. Dotted minutes that are a month ("5.10") make a date, not a
  /// time, unless "Uhr" or "um" says it is a time.
  private static func germanRangeSide(
    _ text: String, part: String?, shared: PartOfDay?, hasUhr: Bool, lead: String?, match: Match
  ) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    if side.output.2 == ".", (1...12).contains(minute), !hasUhr, lead != "um" { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    let kind = part.flatMap(germanPartOfDay) ?? shared
    if let kind { return germanTimeWithPart(hour: hour, minute: minute, part: kind) }
    return germanBareTime(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time as a pattern without groups: a colon time ("17:30", "17:30
  /// Uhr"), an hour with "Uhr" ("17 Uhr", "17.30 Uhr", "17 Uhr 30"), an hour
  /// with h ("17h", "17h30"), a dotted time whose minutes cannot be a month
  /// ("17.30"), or a spoken time ("halb fünf").
  private static var germanClockShape: String {
    let digits =
      #"(?<![\p{N}:.,])(?:\d{1,2}:\d{2}(?:\s*uhr)?|\d{1,2}(?:[.:]\d{2})?\s*uhr(?:\s+\d{2})?|\d{1,2}h(?:\d{2})?|\d{1,2}\.(?:00|1[3-9]|[2-5]\d))"#
    return #"(?:\#(digits)|\#(germanSpokenShapes))"#
  }

  /// A clock time written as a bound ("bis 17 Uhr", "bis 17:00", "bis spätestens
  /// 17 Uhr", "spätestens um 17:00", "frühestens 9 Uhr", "vor 8 Uhr", "nach
  /// 18 Uhr", "nicht später als 17 Uhr", "bis halb fünf"), which names no
  /// start time. Group 1 is the bound, or nil for a range ("von 14 bis 17:30"),
  /// which the range rule reads and this rule only steps over, so the "bis
  /// 17:30" inside it is not taken for a bound.
  static var germanDeadlineClockPattern: String {
    let bound = #"bis(?:\s+spätestens)?|spätestens|frühestens|vor|nach|nicht\s+(?:später|früher)\s+als"#
    // The spoken times "fünf vor halb vier" and "zehn nach halb vier" hold a
    // "vor" or "nach" before a spoken time, which is no bound either.
    let minutesAround = #"(?:fünf|zehn|zwanzig|5|10|20)\s+(?:nach|vor)\s+(?:halb\s+)?\#(germanSpokenHour)"#
    return
      #"\#(germanStart)(?:\#(germanTimeRangeBody(capturing: false))|\#(minutesAround)|((?:\#(bound))\s+(?:um\s+)?\#(germanClockShape)))\#(germanTimeEnd)"#
  }

  /// The clock after a deadline day ("bis Freitag um 17 Uhr", "bis morgen
  /// 9:00"), which is a deadline's clock and stays in the title with the rest
  /// of the line once the day is read as the due day.
  static var germanDueClockPattern: String {
    #"\#(germanStart)(?:(?:um|gegen|ab)\s+)?\#(germanClockShape)\#(germanTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day:
  /// a word that introduces a due day, the day, and maybe a part of the day,
  /// with a comma or a space before the clock.
  private static let germanAfterDueDayPattern = german(
    #"(?:^|\s)\#(germanDueLead)(?:\#(germanDueDay))(?:\s+(?:\#(germanPartOfDayWords)))?\s*,?\s*$"#)

  /// The text before a clock that ends a range of days or of weekdays ("vom 3.
  /// bis 5. Mai", "von Montag bis Mittwoch"), whose "bis" and day are no
  /// deadline.
  private static var germanAfterRangePattern: String {
    german(#"(?:\#(germanDateRangePattern)|\#(germanWeekdayRangePattern))\s*,?\s*$"#)
  }

  /// Whether the text before `match` ends with a deadline word and a day, and
  /// maybe a part of the day ("bis Freitag", "bis morgen früh"). The "bis" of a
  /// range of days is no deadline word, so the clock after "von Montag bis
  /// Mittwoch" is the range's time.
  static func germanIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = germanTextBefore(match)
    let whole = NSRange(before.startIndex..., in: before)
    if let range = LorvexCapturePatterns.regex(germanAfterRangePattern),
      range.firstMatch(in: before, range: whole) != nil
    {
      return false
    }
    guard let regex = LorvexCapturePatterns.regex(germanAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: whole) != nil
  }
}
