import Foundation

extension LorvexCaptureVocabulary {
  // The Greek clock-time rules: a time after "στις" or "ώρα" ("στις 15:00",
  // "στις 3 το απόγευμα"), a part of the day before an hour ("το απόγευμα στις
  // 7"), an hour with π.μ. or μ.μ., the spoken forms ("στις 3 και μισή", "στις
  // 4 παρά τέταρτο"), a range of times, midnight, and the rules that keep a
  // deadline written as a clock time in the title. The vocabulary's other words
  // are in ``greek``.

  // MARK: - Hours spelled as words

  /// The hours one to twelve as Greek spells them after "στις", as the reading
  /// form leaves them. "Μία" is the form of one ("στη μία"), "τρεις" and
  /// "τέσσερις" the forms of three and four.
  private static let greekHourWordList: [(word: String, value: Int)] = [
    ("μια", 1), ("ενα", 1), ("δυο", 2), ("τρεισ", 3), ("τρια", 3), ("τεσσερισ", 4), ("τεσσερα", 4), ("πεντε", 5),
    ("εξι", 6), ("εφτα", 7), ("επτα", 7), ("οχτω", 8), ("οκτω", 8), ("εννια", 9), ("εννεα", 9), ("δεκα", 10),
    ("εντεκα", 11), ("δωδεκα", 12),
  ]

  private static let greekHourValues: [String: Int] = Dictionary(
    uniqueKeysWithValues: greekHourWordList.map { ($0.word, $0.value) })

  /// The hour words as the alternatives of a pattern without groups.
  static var greekHourWords: String {
    alternation(of: greekHourWordList.map(\.word))
  }

  /// The hours that Greek says as one word with "and a half": "εννιάμισι" is
  /// 9:30, "μιάμιση" 1:30.
  private static let greekHalfHourWords: [String: Int] = [
    "μιαμιση": 1, "δυομισι": 2, "τρεισημισι": 3, "τεσσεραμισι": 4, "πεντεμισι": 5, "εφταμισι": 7, "επταμισι": 7,
    "οχτωμισι": 8, "οκτωμισι": 8, "εννιαμισι": 9, "εννεαμισι": 9, "δεκαμισι": 10, "εντεκαμισι": 11,
    "δωδεκαμισι": 12,
  ]

  /// The hour a matched text names: digits, or an hour word.
  private static func greekHourNumber(_ text: String) -> Int? {
    number(text) ?? greekHourValues[greekPhrase(text)]
  }

  // MARK: - Parts of the day

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The 12-hour hours follow
  /// ``partOfDayTime(hour:minute:part:)``: "9 το πρωί" is 09:00, "12 το
  /// μεσημέρι" noon, "3 το μεσημέρι" and "3 το απόγευμα" 15:00, "8 το βράδυ"
  /// 20:00, "12 το βράδυ" the midnight that ends the day, and "2 τη νύχτα" the
  /// small hours after midnight, on the next day. An hour on the 24-hour clock
  /// (13 to 23) is read as written when its part of the day is one it falls in.
  private static func greekTimeWithPart(hour: Int, minute: Int, part: GreekPartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    if (13...23).contains(hour) {
      let hours: ClosedRange<Int>? =
        switch part {
        case .morning: nil
        case .noon: 13...15
        case .afternoon: 13...19
        case .evening: 17...23
        case .night: 18...23
        }
      return hours?.contains(hour) == true ? ClockTime(minutes: hour * 60 + minute) : nil
    }
    switch part {
    case .morning: return partOfDayTime(hour: hour, minute: minute, part: .morning)
    case .noon: return partOfDayTime(hour: hour, minute: minute, part: .day)
    case .afternoon: return partOfDayTime(hour: hour, minute: minute, part: .evening)
    case .evening:
      return hour == 12 ? ClockTime(minutes: minute, isAfterMidnight: true)
        : partOfDayTime(hour: hour, minute: minute, part: .evening)
    case .night: return partOfDayTime(hour: hour, minute: minute, part: .night)
    }
  }

  /// The clock time an hour names with the text written after it: a part of the
  /// day ("το πρωί", "βράδυ") or "π.μ." and "μ.μ.", which count like AM and PM.
  private static func greekTime(hour: Int, minute: Int, partText: String) -> ClockTime? {
    if partText.contains(".") {
      guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
      let isAfternoon = greekKey(partText).hasPrefix("μ")
      return ClockTime(minutes: (hour % 12 + (isAfternoon ? 12 : 0)) * 60 + minute)
    }
    guard let part = greekPartOfDay(partText) else { return nil }
    return greekTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// A part of the day beside a day word anywhere in a line, as a pattern:
  /// "αύριο το βράδυ", "κάθε πρωί", "την Παρασκευή το απόγευμα".
  private static var greekLinePartPattern: String {
    #"\#(greekStart)(?:αυριο|σημερα|μεθαυριο|καθε|(?:\#(greekWeekdayNames)))\s+\#(greekPartWords)\#(greekEnd)"#
  }

  /// The part of the day the line names beside `match` (within
  /// ``greekContextLength`` characters of it), for an hour written without one:
  /// "αύριο το βράδυ στις 8", "κάθε πρωί στις 7", and "την Παρασκευή το
  /// απόγευμα στις 5" are 20:00, 07:00, and 17:00, where the hour alone would be
  /// 08:00, 07:00, and 05:00. Nil when the line names no part of the day there,
  /// or names two that differ.
  private static func greekLinePartOfDay(beside match: Match) -> GreekPartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(greekLinePartPattern) else { return nil }
    let source = match.source
    let own = match.result.range
    let lower = max(0, own.location - greekContextLength)
    let upper = min(source.utf16.count, NSMaxRange(own) + greekContextLength)
    var named: GreekPartOfDay?
    for found in regex.matches(
      in: source, options: [.withTransparentBounds, .withoutAnchoringBounds],
      range: NSRange(location: lower, length: upper - lower))
    {
      guard NSIntersectionRange(found.range, own).length == 0,
        let range = Range(found.range, in: source), let part = greekPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the day
  /// its line names elsewhere, or nil when the hour is written on the 24-hour
  /// clock (a leading zero, 0, or 13 and later), the line names no part or two,
  /// or the part has no such hour.
  private static func greekTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = greekLinePartOfDay(beside: match) else { return nil }
    return greekTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part
  /// of the day of its own) names: its line's part of the day when the line
  /// names one, else the hour as ``bareTime(hour:minute:hasLeadingZero:)`` reads
  /// it.
  private static func greekBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    greekTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, or colon
  /// (the word or the number goes on), no letter joined by a hyphen, no decimal
  /// fraction, no slash and digit (which makes it a date), no percent or
  /// currency sign with or without a space before it, no dash before a digit,
  /// which makes the time one side of a range written with a dash, and no AM or
  /// PM, which English reads.
  static let greekTimeEnd =
    #"(?![\p{L}\p{N}\p{M}:]|[-–]\p{L}|[.,/]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d|\s*[ap]\.?m\.?(?![\p{L}\p{M}]))"#

  /// The words before an hour that make it a clock time: "στις", "στη", "στην",
  /// "ώρα", "την ώρα", each followed by the space before the hour.
  private static let greekClockLead = #"(?:στισ|στην|στη|(?:την\s+)?ωρα\s*:?)\s+"#

  /// The parts of the day, and the written AM and PM, an hour may carry after
  /// it, as a pattern without groups.
  private static let greekPartChoices = #"πρωι|μεσημερι|απογευμα|βραδυ|μεσανυχτα|νυχτα|π\.\s?μ\.?|μ\.\s?μ\.?"#

  // MARK: - Clock time

  /// "στις 15:00", "στις 3", "στις τρεις", "στις 3 το απόγευμα", "ώρα 15:00", "το
  /// απόγευμα στις 7", "9 το πρωί", "9 π.μ.", "3 μ.μ.", and a colon time with the
  /// part of the day another word of the line names ("αύριο το βράδυ 8:30"). A
  /// time written with no Greek word ("15:30", "3pm") is left to English.
  /// Groups: 1 to 5 the word before an hour, the hour, the colon or the dot, the
  /// minute, and the part of the day after it; 6 to 9 the part of the day before
  /// "στις", the hour, the separator, and the minute; 10 to 14 an hour with a
  /// part of the day and no word before it, its separator, its minute, the part
  /// written as a word, and the part written as π.μ. or μ.μ.; 15 to 17 a colon
  /// time with nothing else.
  static var greekClockPattern: String {
    let hourToken = #"(\d{1,2}|\#(greekHourWords))"#
    let minutes = #"(?:([.:])(\d{2}))?"#
    let words = #"πρωι|μεσημερι|απογευμα|βραδυ|μεσανυχτα|νυχτα"#
    let meridiem = #"π\.\s?μ\.?|μ\.\s?μ\.?"#
    let unattached = #"(?<![\p{N}:.,/])(?<![-–—])(?<![-–—]\s)"#
    let lead =
      #"\#(greekStart)(στισ|στην|στη|(?:την\s+)?ωρα\s*:?)\s+\#(hourToken)\#(minutes)(?:\s+(?:(?:το|τη|τα)\s+)?(\#(greekPartChoices)))?\#(greekTimeEnd)"#
    let partFirst =
      #"\#(greekStart)(?<!καθε\s)(?:(?:το|τη)\s+)?(\#(words))\s+\#(greekClockLead)\#(hourToken)\#(minutes)\#(greekTimeEnd)"#
    let withPart =
      #"\#(greekStart)\#(unattached)(\d{1,2})\#(minutes)(?:\s+(?:(?:το|τη|τα)\s+)?(\#(words))|\s*(\#(meridiem)))\#(greekNoCountedUnitAfter)\#(greekTimeEnd)"#
    let colonOnly = #"\#(greekStart)\#(unattached)(\d{1,2})(:)(\d{2})\#(greekTimeEnd)"#
    return [lead, partFirst, withPart, colonOnly].joined(separator: "|")
  }

  static func greekClock(_ match: Match) -> ClockTime? {
    let hourText: String
    let separator: String?
    let minuteText: String?
    var partText: String?
    var lead: String?
    var isColonOnly = false
    if let text = match.group(2) {
      (hourText, separator, minuteText) = (text, match.group(3), match.group(4))
      (partText, lead) = (match.group(5), match.group(1))
    } else if let text = match.group(7) {
      (hourText, separator, minuteText) = (text, match.group(8), match.group(9))
      partText = match.group(6)
    } else if let text = match.group(10) {
      (hourText, separator, minuteText) = (text, match.group(11), match.group(12))
      partText = match.group(13) ?? match.group(14)
    } else if let text = match.group(15) {
      (hourText, separator, minuteText) = (text, match.group(16), match.group(17))
      isColonOnly = true
    } else {
      return nil
    }
    guard let hour = greekHourNumber(hourText), (0...23).contains(hour) else { return nil }
    let isWord = number(hourText) == nil
    var minute = 0
    if let minuteText {
      guard let value = number(minuteText), (0...59).contains(value) else { return nil }
      minute = value
    }
    if isWord, !(1...12).contains(hour) { return nil }
    // "στις 15.10" is a date; "ώρα 15.10" and "στις 9.00" are times.
    if let lead, separator == ".", (1...12).contains(minute), !lead.contains("ωρα") { return nil }
    if let partText { return greekTime(hour: hour, minute: minute, partText: partText) }
    let hasLeadingZero = startsWithZero(hourText)
    // A colon time with no Greek word and no part of the day in the line is
    // English's.
    if isColonOnly {
      return greekTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    }
    // A bare hour is a time unless a counted noun follows it ("στις 3 ώρες") or
    // it is the day of a month ("κάθε μήνα στις 15").
    if minuteText == nil, !greekFollowsAsDetail(match) || greekIsDayOfMonth(match) { return nil }
    return greekBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
  }

  /// Whether a bare number after "στις" is the day of a month: "κάθε μήνα στις
  /// 15", "στις 15 κάθε μήνα".
  private static func greekIsDayOfMonth(_ match: Match) -> Bool {
    let before = greekTextBefore(match)
    let after = greekTextAfter(match)
    if let regex = LorvexCapturePatterns.regex(#"καθε\s+μηνα\s*$"#),
      regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
    {
      return true
    }
    guard let regex = LorvexCapturePatterns.regex(#"^\s*(?:καθε\s+μηνα|του\s+(?:μηνα|μηνοσ))"#) else { return false }
    return regex.firstMatch(in: after, range: NSRange(after.startIndex..., in: after)) != nil
  }

  /// "στις 3pm", "στις 3:30 pm": a time with AM or PM after "στις" or "ώρα",
  /// which takes the word with it where English would leave "στις" behind. A
  /// time with AM or PM and no such word is English's. Groups: 1 hour, 2
  /// minute, 3 the "a" or "p".
  static let greekMeridiemTimePattern =
    #"\#(greekStart)(?:στισ|ωρα)\s+(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?(?![\p{L}\p{N}\p{M}:])"#

  static func greekMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased()
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Spoken times

  /// The minutes a spoken time may name after "και", as a pattern without
  /// groups: a half, a quarter, digits, and the words five, ten, a quarter in
  /// one word, twenty, and twenty-five.
  private static let greekSpokenAnd =
    #"μισ(?:η|ο)|τεταρτο|\d{1,2}|εικοσι\s+πεντε|εικοσιπεντε|εικοσι|δεκαπεντε|δεκα|πεντε"#

  /// The minutes a spoken time may name after "παρά", as a pattern without
  /// groups.
  private static let greekSpokenPara =
    #"τεταρτο|\d{1,2}|εικοσι\s+πεντε|εικοσιπεντε|εικοσι|δεκαπεντε|δεκα|πεντε"#

  /// The minutes a spoken amount names.
  private static func greekSpokenMinutes(_ text: String) -> Int? {
    let key = greekPhrase(text)
    if key.hasPrefix("μισ") { return 30 }
    if key == "τεταρτο" { return 15 }
    if let digits = number(key) { return digits }
    return ["πεντε": 5, "δεκα": 10, "δεκαπεντε": 15, "εικοσι": 20, "εικοσι πεντε": 25, "εικοσιπεντε": 25][key]
  }

  /// "στις 3 και μισή" (3:30), "στις 3 και τέταρτο" (3:15), "στις 3 και δέκα"
  /// (3:10), "στις τρεις και είκοσι", "στις 4 παρά τέταρτο" (3:45), "στις 4 παρά
  /// 10" (3:50), "στις εννιάμισι" (9:30), each maybe with a part of the day
  /// before or after it ("στις 8 και μισή το βράδυ"). The hour needs "στις",
  /// "στη", or "ώρα" before it. "Και" adds the minutes to the hour before it and
  /// "παρά" takes them off the hour after it, so "4 παρά τέταρτο" is 3:45. A
  /// time followed by "ώρες" or "λεπτά" is an amount ("στις 3 και μισή ώρα").
  /// Groups: 1 the part of the day before the time; 2 the hour and 3 the minutes
  /// of "και"; 4 the hour and 5 the minutes of "παρά"; 6 the one-word half
  /// hour; 7 the part of the day after the time.
  static var greekSpokenTimePattern: String {
    let hourToken = #"(?:\d{1,2}|\#(greekHourWords))"#
    let halves = alternation(of: Array(greekHalfHourWords.keys))
    let partFirst = #"(?:((?:(?:το|τη)\s+)?(?:πρωι|μεσημερι|απογευμα|βραδυ|νυχτα))\s+)?"#
    let partAfter = #"(?:\s+(?:(?:το|τη|τα)\s+)?(\#(greekPartChoices)))?"#
    return
      #"\#(greekStart)(?<!καθε\s)\#(partFirst)\#(greekClockLead)(?:(\#(hourToken))\s+(?:και|κι)\s+(\#(greekSpokenAnd))|(\#(hourToken))\s+παρα\s+(\#(greekSpokenPara))|(\#(halves)))\#(partAfter)(?!\s+(?:ωρα|ωρεσ|λεπτα|λεπτο)(?![\p{L}\p{M}]))\#(greekTimeEnd)"#
  }

  static func greekSpokenTime(_ match: Match) -> ClockTime? {
    guard greekFollowsAsDetail(match) else { return nil }
    let hour: Int
    let minute: Int
    if let text = match.group(2), let amount = match.group(3) {
      guard let value = greekHourNumber(text), (1...23).contains(value),
        let minutes = greekSpokenMinutes(amount), (1...59).contains(minutes)
      else { return nil }
      (hour, minute) = (value, minutes)
    } else if let text = match.group(4), let amount = match.group(5) {
      guard let value = greekHourNumber(text), (1...23).contains(value),
        let minutes = greekSpokenMinutes(amount), (1...29).contains(minutes)
      else { return nil }
      (hour, minute) = (value == 1 ? 12 : value - 1, 60 - minutes)
    } else if let text = match.group(6), let value = greekHalfHourWords[greekKey(text)] {
      (hour, minute) = (value, 30)
    } else {
      return nil
    }
    if let partText = match.group(7) ?? match.group(1) {
      return greekTime(hour: hour, minute: minute, partText: partText)
    }
    return greekBareTime(hour: hour, minute: minute, hasLeadingZero: false, match: match)
  }

  // MARK: - Midnight

  /// "τα μεσάνυχτα", "στα μεσάνυχτα": midnight, which ends the day it names. The
  /// time after midnight puts the task on the next day.
  static let greekMidnightPattern = #"\#(greekStart)(?:στα|τα)\s+μεσανυχτα\#(greekEnd)"#

  static func greekMidnight(_ match: Match) -> ClockTime? {
    ClockTime(minutes: 0, isAfterMidnight: true)
  }

  // MARK: - Time range

  /// The body of the range pattern, with its groups capturing or not. A side is
  /// a time written in digits ("14", "14:30", "14.30"), maybe after "στις" and
  /// followed by a part of the day or π.μ. and μ.μ.; the sides are joined by a
  /// dash or, after "από", by "έως", "μέχρι", or "ως".
  private static func greekTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let side = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2})?"#
    let lead = #"στισ|στην|στη|τισ|ωρα"#
    let words = #"πρωι|μεσημερι|απογευμα|βραδυ|νυχτα"#
    let tail = #"(?:(?:\s+(?:(?:το|τη|τα)\s+)?|\s*)\#(group(greekPartChoices)))?"#
    let leadingPart = #"(?:(?:(?:το|τη)\s+)?\#(group(words))\s+)?"#
    let opening = #"(?:\#(group("απο"))\s+)?"#
    let leadWord = #"(?:\#(group(lead))\s+)?"#
    let joiner = #"(?:\s*\#(group("[-–—]"))\s*|\s+\#(group("εωσ|μεχρι|ωσ"))\s+)"#
    return
      #"\#(leadingPart)\#(opening)\#(leadWord)\#(group(side))\#(tail)\#(joiner)\#(leadWord)\#(group(side))\#(tail)"#
  }

  /// "στις 14-16", "14.00-16.00", "3-5 το απόγευμα", "το απόγευμα 3-5", "από τις 3
  /// έως τις 5", "από τις 9 π.μ. έως τις 5 μ.μ.", "από 10:00 μέχρι 11:00".
  /// Groups: 1 the part of the day before the range, 2 "από", 3 the word before
  /// the start, 4 the start, 5 the part of the day after the start, 6 a dash, 7
  /// the word that means "to", 8 the word before the end, 9 the end, 10 the part
  /// of the day after the end.
  static var greekTimeRangePattern: String {
    #"\#(greekStart)\#(greekTimeRangeBody(capturing: true))\#(greekTimeEnd)"#
  }

  static func greekTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(4), let endText = match.group(9) else { return nil }
    // "Έως", "μέχρι", and "ως" join the sides only after "από".
    if match.group(7) != nil, match.group(2) == nil { return nil }
    let hasLead = match.group(3) != nil || match.group(8) != nil
    let leadingPart = match.group(1)
    let startPart = match.group(5) ?? leadingPart
    let endPart = match.group(10) ?? leadingPart
    let sides = [startText, endText]
    let hasMinutes = sides.contains { $0.contains(":") || $0.contains(".") }
    // Two bare hours are as often an amount or numbered items ("από 2 έως 4"
    // counts pages), so a range needs "στις", a part of the day, or minutes.
    guard hasLead || startPart != nil || endPart != nil || hasMinutes else { return nil }
    // A dashed range of colon times with nothing else is English's.
    if match.group(6) != nil, !hasLead, startPart == nil, endPart == nil, sides.allSatisfy({ $0.contains(":") }) {
      return nil
    }
    guard let start = greekRangeSide(startText, partText: startPart, hasMarker: hasLead, match: match),
      let end = greekRangeSide(endText, partText: endPart, hasMarker: hasLead, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day or the one the line names elsewhere. Dotted minutes that are a month
  /// ("5.10") make a date, not a time, unless "στις" or a part of the day says
  /// it is a time. "12 το πρωί" in a range is noon: "10-12 το πρωί" ends at
  /// noon.
  private static func greekRangeSide(_ text: String, partText: String?, hasMarker: Bool, match: Match) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    if side.output.2 == ".", (1...12).contains(minute), !hasMarker, partText == nil { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    if let partText {
      if hour == 12, !partText.contains("."), greekPartOfDay(partText) == .morning {
        return ClockTime(minutes: 12 * 60 + minute)
      }
      return greekTime(hour: hour, minute: minute, partText: partText)
    }
    return greekBareTime(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// "στις 3 και 10 λεπτά", "στις τρεις παρά 5 λεπτά": a spoken time with its
  /// minutes counted in a unit, which stays in the title whole so the length
  /// rule does not read the minutes as one.
  static let greekMinutesWithUnitPattern =
    #"\#(greekStart)(?:στισ|στην|στη|ωρα)\s+(?:\d{1,2}|\#(greekHourWords))\s+(?:και|κι|παρα)\s+(?:\d{1,2}|\#(greekCountWords))\s+λεπτ(?:α|ο)\#(greekEnd)"#

  /// A clock time as a pattern without groups, in a form that names an hour of
  /// its own: "5", "17:30", "9.00", "9 π.μ.", "5 το απόγευμα", "πέντε". A dotted
  /// number whose minutes read as a month ("15.10") is a date, not a time.
  private static var greekClockShape: String {
    #"(?:\d{1,2}(?::\d{2}|\.(?:00|1[3-9]|[2-5]\d))?(?:\s*(?:π\.\s?μ\.?|μ\.\s?μ\.?|[ap]\.?m\.?))?|\#(greekHourWords))(?:\s+\#(greekPartWords))?"#
  }

  /// What may not follow the hour of a bound that is a date: a month ("μέχρι 15
  /// Οκτωβρίου") or the rest of a numeric date ("μέχρι 15/10").
  private static var greekNotADateAfter: String {
    #"(?!\s*(?:ησ|η)?\s+(?:του\s+)?(?:\#(greekMonthNames))(?![\p{L}\p{M}])|[./]\d)"#
  }

  /// A clock time written as a bound ("μέχρι τις 5", "πριν τις 17:00", "μετά
  /// τις 3", "το αργότερο στις 5", "στις 5 το αργότερο"), which names no start
  /// time. A bound that is a date ("μέχρι τις 15 Οκτωβρίου") or a count ("μετά
  /// από 3 μέρες") is no clock. Group 1 is the bound, or nil for a range ("από
  /// τις 14 έως τις 17:30"), which the range rule reads and this rule only steps
  /// over, so the "έως τις 17:30" inside it is not taken for a bound.
  static var greekDeadlineClockPattern: String {
    let article = #"(?:(?:τισ|την|τη|στισ|ωρα|την\s+ωρα)\s+)?"#
    let after =
      #"(?:\#(greekBoundWords))\s+\#(article)\#(greekClockShape)\#(greekNotADateAfter)\#(greekNoCountedUnitAfter)"#
    let before = #"(?:στισ|τισ)\s+\#(greekClockShape)\s+το\s+αργοτερο"#
    return
      #"\#(greekStart)(?:\#(greekTimeRangeBody(capturing: false))|(\#(after)|\#(before)))\#(greekEnd)"#
  }

  /// The clock after a deadline day ("προθεσμία Παρασκευή στις 5", "μέχρι αύριο
  /// 9:00"), which is a deadline's clock and stays in the title with the rest
  /// of the line once the day is read as the due day.
  static var greekDueClockPattern: String {
    #"\#(greekStart)(?:(?:στισ|ωρα|την\s+ωρα|τισ)\s+)?\#(greekClockShape)\#(greekTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a
  /// word that introduces a due day, the day, with a comma or a space before the
  /// clock.
  private static var greekAfterDueDayPattern: String {
    #"(?:^|\s)\#(greekDueLead)(?:\#(greekDaysAfterLead))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a word that introduces a due day
  /// and the day ("προθεσμία Παρασκευή", "μέχρι αύριο").
  static func greekIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = greekTextBefore(match)
    guard let regex = LorvexCapturePatterns.regex(greekAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }
}
