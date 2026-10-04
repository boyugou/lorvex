import Foundation

extension LorvexCaptureVocabulary {
  // The Hindi clock-time rules: a time with बजे, a time with a part of the
  // day, a range of times, and the rule that keeps a deadline written as a
  // clock time in the title. The vocabulary's other words are in ``hindi``.

  // MARK: - Parts of the day

  /// The words that name a part of the day, as a pattern without groups: the
  /// morning (सुबह, the doubled "सुबह-सुबह" with a hyphen or a space, सवेरे,
  /// तड़के), the day (दोपहर), the evening (शाम), and the night (रात, देर रात).
  static let hindiPartOfDayWords =
    #"(?:देर\s+रात|रात|सुबह(?:[-‐‑]|\s+)सुबह|सुबह|सवेरे|सबेरे|तड़के|दोपहर|दुपहर|शाम)"#

  /// The part-of-day words in a form a look-behind can hold, which needs a
  /// bounded length.
  private static let hindiPartOfDayWordsBounded =
    #"(?:देर\s{1,3}रात|रात|सुबह(?:[-‐‑]|\s{1,3})सुबह|सुबह|सवेरे|सबेरे|तड़के|दोपहर|दुपहर|शाम)"#

  /// A part of the day before an hour, as a pattern: "सुबह 9 बजे", "शाम को 5
  /// बजे", "रात के 10 बजे", "सुबह ठीक 6 बजे", "सुबह जल्दी 6 बजे". With
  /// `capturing`, the part's words are group 1 of the lead. A part that "हर"
  /// stands before ("हर सुबह 6 बजे") belongs to the repeat, so the lead leaves
  /// it there and the hour takes its part from the line
  /// (``hindiLinePartOfDay(beside:)``).
  private static func hindiPartLead(capturing: Bool) -> String {
    let words = capturing ? "(\(hindiPartOfDayWords))" : hindiPartOfDayWords
    return
      #"(?:(?<!\#(hindiEvery)\s)\#(words)(?:\s+(?:के|को|में))?\s+(?:(?:ठीक|करीब|लगभग|तकरीबन|जल्दी)\s+)?)"#
  }

  private static let hindiMorningWords: Set<String> = Set(["सुबह", "सवेरे", "सबेरे", "तड़के"].map(hindiKey))
  private static let hindiDayWords: Set<String> = Set(["दोपहर", "दुपहर"].map(hindiKey))

  /// The part of the day a matched word or phrase names.
  static func hindiPartOfDay(_ text: String) -> PartOfDay? {
    let words = Set(hindiWords(in: text))
    if words.contains(hindiKey("रात")) { return .night }
    if !words.isDisjoint(with: hindiMorningWords) { return .morning }
    if !words.isDisjoint(with: hindiDayWords) { return .day }
    if words.contains(hindiKey("शाम")) { return .evening }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("रात 9
  /// बजे" is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that ends
  /// the day, and 1 to 5 the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``.
  private static func hindiTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: one of
  /// ``hindiPartOfDayWords`` as a whole word, unless a deadline word follows it
  /// ("कल सुबह तक") or it is the "रात" of "आधी रात".
  private static let hindiLinePartPattern = hindi(
    #"\#(devanagariStart)(?<!आधी\s)\#(hindiPartOfDayWords)\#(devanagariEnd)(?!\s+(?:तक|तलक|से\s+पहले|के\s+पहले))"#)

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "कल सुबह मीटिंग 6 बजे" and "हर सुबह 6 बजे योग" are 06:00, and
  /// "रात का खाना 8 बजे" is 20:00, where the hour alone would be 18:00 and
  /// 08:00. Nil when the line names no part of the day, or names two that
  /// differ ("सुबह की दवा, शाम की चाय 5 बजे").
  private static func hindiLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(hindiLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = hindiPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no
  /// part or two, or the part has no such hour ("सुबह की सैर 12 बजे").
  private static func hindiTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = hindiLinePartOfDay(beside: match) else { return nil }
    return hindiTimeWithPart(hour: hour, minute: minute, part: part)
  }

  // MARK: - Clock words

  /// The words that name an hour or a fraction of one before बजे: the counts
  /// one to twelve, डेढ़ (1:30), and ढाई (2:30).
  static var hindiTimeWords: String {
    "\(hindiCountWords)|डेढ़|ढाई|अढाई|अढ़ाई"
  }

  /// The hours that डेढ़ and ढाई name.
  private static let hindiHalfHours: [String: (hour: Int, minute: Int)] = [
    hindiKey("डेढ़"): (1, 30), hindiKey("ढाई"): (2, 30), hindiKey("अढाई"): (2, 30),
  ]

  /// A clock time as it stands before "तक" or "से पहले", as a pattern without
  /// groups: an hour with बजे (with a fraction word, a digit hour with
  /// minutes, or a number word), or a colon time.
  static var hindiClockPhrase: String {
    #"(?:(?:साढ़े|सवा|पौने)\s+)?(?:\d{1,2}(?:[:.]\d{2})?|\#(hindiTimeWords))\s*बजे|\d{1,2}:\d{2}"#
  }

  // MARK: - Time

  /// "5 बजे", "5:30 बजे", "5.30 बजे", "साढ़े 5 बजे", "सवा 5 बजे", "पौने 6 बजे",
  /// "डेढ़ बजे", "ढाई बजे", "पाँच बजे", "सुबह 9 बजे", "शाम को 5 बजे", "रात के 10
  /// बजे", "9 बजे सुबह", "10 बजे रात को", each maybe after "ठीक", "करीब",
  /// "लगभग", or "तकरीबन" and with a word after बजे that goes with it: "पर",
  /// "से", "के लिए", "के आसपास", or a possessive ("5 बजे की मीटिंग"). A part of
  /// the day after बजे that a possessive follows ("5 बजे शाम की चाय") is part
  /// of the title. An hour with no part of the day of its own takes the one the
  /// line names elsewhere (``hindiLinePartOfDay(beside:)``), and otherwise
  /// reads as ``bareTime(hour:minute:hasLeadingZero:)`` does.
  /// Groups: 1 the part of the day before the hour, 2 the fraction word, 3 the
  /// hour in digits, 4 its minutes, 5 the hour in words, 6 the part of the day
  /// after बजे.
  static var hindiTimePattern: String {
    let lead = #"(?:(?:ठीक|करीब|लगभग|तकरीबन)\s+)?"#
    let fraction = #"(?:(साढ़े|सवा|पौने)\s+)?"#
    let hour = #"(?:(?<![:.,])(\d{1,2})(?:[:.](\d{2}))?|(\#(hindiTimeWords)))"#
    let part =
      #"(?:\s+(\#(hindiPartOfDayWords))\#(devanagariEnd)(?!\s+(?:का|की|के|वाल[ाीे])\#(devanagariEnd))(?:\s+(?:को|में)\#(devanagariEnd))?)?"#
    let trailing =
      #"(?:\s+(?:पर|से(?!\s+(?:पहले|बाद|लेकर|\d))|के\s+(?:लिए|आस[\s-]?पास|करीब|लगभग)|का|की|के(?!\s+(?:बाद|पहले|दौरान|बीच|अंदर|भीतर)))\#(devanagariEnd))?"#
    return
      #"\#(devanagariStart)\#(lead)\#(hindiPartLead(capturing: true))?\#(fraction)\#(hour)\s*बजे\#(part)\#(trailing)\#(hindiTimeEnd)"#
  }

  static func hindiTime(_ match: Match) -> ClockTime? {
    let fraction = match.group(2).map(hindiPhrase)
    var minute = match.group(4).flatMap(number) ?? 0
    var hour: Int
    if let text = match.group(3) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(5).map(hindiPhrase) {
      if let half = hindiHalfHours[word] {
        guard fraction == nil else { return nil }
        (hour, minute) = half
      } else if let count = hindiCounts[word] {
        hour = count
      } else {
        return nil
      }
    } else {
      return nil
    }
    // A fraction counts from an hour on the clock face: "साढ़े 5" is 5:30,
    // "सवा 5" is 5:15, and "पौने 5" is 4:45.
    if let fraction {
      guard minute == 0, (1...12).contains(hour) else { return nil }
      switch fraction {
      case hindiKey("साढ़े"): minute = 30
      case "सवा": minute = 15
      case hindiKey("पौने"):
        hour = hour == 1 ? 12 : hour - 1
        minute = 45
      default: return nil
      }
    }
    // A part of the day on both sides of the hour contradicts itself.
    if match.group(1) != nil, match.group(6) != nil { return nil }
    if let partText = match.group(1) ?? match.group(6) {
      guard let part = hindiPartOfDay(partText) else { return nil }
      return hindiTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(match.group(3) ?? "") && fraction == nil
    return hindiTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  /// "शाम 5:30", "रात 10.30": a part of the day with a colon or dotted time and
  /// no बजे, or the colon time after a part that "हर" stands before ("हर रात
  /// 10:30"), which takes the part from the line. A bare hour with a part ("शाम
  /// 5") is no time. Groups: 1 the part of the day, 2 the hour, 3 the
  /// minutes; 4 the hour and 5 the minutes after "हर" and its part.
  static var hindiPartColonTimePattern: String {
    let own = #"\#(hindiPartLead(capturing: true))(?<![:.,])(\d{1,2})[:.](\d{2})"#
    let afterEvery = #"(?<=\#(hindiEvery)\s\#(hindiPartOfDayWordsBounded)\s)(?<![:.,])(\d{1,2})[:.](\d{2})"#
    return #"\#(devanagariStart)(?:\#(own)|\#(afterEvery))\#(hindiTimeEnd)"#
  }

  static func hindiPartColonTime(_ match: Match) -> ClockTime? {
    if let part = match.group(1).flatMap(hindiPartOfDay), let hour = match.group(2).flatMap(number),
      let minute = match.group(3).flatMap(number)
    {
      return hindiTimeWithPart(hour: hour, minute: minute, part: part)
    }
    guard let hour = match.group(4).flatMap(number), let minute = match.group(5).flatMap(number),
      let part = hindiLinePartOfDay(beside: match)
    else { return nil }
    return hindiTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// "आधी रात", "आधी रात को": the midnight that ends the day. "आधी रात तक" is a
  /// deadline and "आधी रात के बाद" a time after it, so neither is read.
  static let hindiMidnightPattern =
    #"\#(devanagariStart)(?:ठीक\s+)?आधी\s+रात(?:\s+(?:को|में)\#(devanagariEnd))?\#(devanagariEnd)(?!\s+(?:तक|तलक|के\s+बाद|से\s+(?:पहले|बाद)))"#

  // MARK: - Time range

  /// The side of a range, as a pattern: an hour in digits with maybe minutes,
  /// or an hour in words.
  private static var hindiRangeSide: String {
    #"((?<![:.,])\d{1,2}(?:[:.]\d{2})?|\#(hindiCountWords))"#
  }

  /// What may follow the end of a range and go with it: "तक", "के बीच", "के
  /// दौरान" ("3 से 5 बजे के बीच").
  private static var hindiRangeTail: String {
    #"(?:\s+(?:तक|के\s+(?:बीच|दौरान))\#(devanagariEnd))?+"#
  }

  /// "2 से 4 बजे", "2 बजे से 4 बजे तक", "सुबह 9 से 11 बजे तक", "सुबह 9 बजे से
  /// शाम 5 बजे तक", "दो से चार बजे", "2-4 बजे", "2 बजे से लेकर 4 बजे तक". The
  /// end carries बजे: two bare numbers ("2 से 4") are as often an amount. A
  /// range with colons and no बजे ("14:00 से 16:00") is
  /// ``hindiColonTimeRangePattern``. Groups: 1 the part of the day before the
  /// start, 2 the start, 3 the part before the end, 4 the end.
  static var hindiTimeRangePattern: String {
    let connector = #"(?:\s+से(?:\s+लेकर)?\s+|\s*[-–—]\s*)"#
    return
      #"\#(devanagariStart)\#(hindiPartLead(capturing: true))?\#(hindiRangeSide)(?:\s*बजे)?\#(connector)\#(hindiPartLead(capturing: true))?\#(hindiRangeSide)\s*बजे\#(hindiRangeTail)\#(hindiTimeEnd)"#
  }

  /// "14:00 से 16:00", "9:30 से 10:30 तक", "सुबह 9:00 से शाम 5:00 तक": a range of
  /// two colon times joined by "से". The same groups as
  /// ``hindiTimeRangePattern``. A range with a dash and no बजे ("14:00-16:00")
  /// is English's.
  static var hindiColonTimeRangePattern: String {
    #"\#(devanagariStart)\#(hindiPartLead(capturing: true))?((?<![:.,])\d{1,2}:\d{2})\s+से(?:\s+लेकर)?\s+\#(hindiPartLead(capturing: true))?(\d{1,2}:\d{2})\#(hindiRangeTail)\#(hindiTimeEnd)"#
  }

  static func hindiTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(4) else { return nil }
    // A part of the day elsewhere in the line names the start's half of the day
    // (``hindiLinePartOfDay(beside:)``); the end is the first reading after the
    // start.
    guard
      let start = hindiRangeSideTime(startText, part: match.group(1), match: match, beside: match.group(1) == nil),
      let end = hindiRangeSideTime(endText, part: match.group(3), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func hindiRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = hindiCounts[hindiPhrase(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = hindiPartOfDay(part) else { return nil }
      return hindiTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = hindiTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a bound ("5 बजे तक", "शाम 5 बजे से पहले", "18:00
  /// तक", "5 बजे के बाद", "3 और 5 बजे के बीच"), which names no start time.
  /// Group 1 is the bound, or nil for a range ("2 बजे से 4 बजे तक"), which the
  /// range rules read and this rule only steps over, so the "4 बजे तक" inside
  /// it is not taken for a bound.
  static var hindiDeadlineClockPattern: String {
    let part = hindiPartLead(capturing: false)
    let side = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(hindiCountWords))"#
    let connector = #"(?:\s+से(?:\s+लेकर)?\s+|\s*[-–—]\s*)"#
    let range =
      #"(?:\#(part)?\#(side)(?:\s*बजे)?\#(connector)\#(part)?\#(side)\s*बजे|\#(part)?\d{1,2}:\d{2}\s+से(?:\s+लेकर)?\s+\#(part)?\d{1,2}:\d{2})\#(hindiRangeTail)"#
    let bound = #"(?:\#(hindiDeadlineWords)|के\s+(?:बाद|बीच|दौरान))"#
    let deadline =
      #"((?:(?:ठीक|करीब|लगभग|तकरीबन)\s+)?\#(part)?(?:\#(hindiClockPhrase))\s+\#(bound))"#
    return #"\#(devanagariStart)(?:\#(range)|\#(deadline))\#(devanagariEnd)"#
  }
}
