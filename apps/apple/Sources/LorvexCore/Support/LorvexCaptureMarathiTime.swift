import Foundation

extension LorvexCaptureVocabulary {
  // The Marathi clock-time rules: a time with वाजता, a time with a part of the
  // day, a range of times, and the rule that keeps a deadline written as a
  // clock time in the title. The vocabulary's other words are in ``marathi``.

  // MARK: - Parts of the day

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: the morning (सकाळी, पहाटे), the day (दुपारी), the evening
  /// (संध्याकाळी, सायंकाळी), and the night (रात्री).
  static let marathiDayPartWords = #"सकाळी|दुपारी|संध्याकाळी|सायंकाळी|रात्री|पहाटे"#

  /// The words that may stand before an hour to give its part of the day, as a
  /// pattern without groups: the words of ``marathiDayPartWords``, the same
  /// words with the genitive "च्या" ("सकाळच्या 7 वाजता", "रात्रीच्या 10 वाजता"),
  /// and the midnight ("मध्यरात्री 12 वाजता").
  static let marathiPartLeadWords =
    #"सकाळी|सकाळच्या|दुपारी|दुपारच्या|संध्याकाळी|संध्याकाळच्या|सायंकाळी|सायंकाळच्या|मध्यरात्रीच्या|मध्यरात्री|रात्रीच्या|रात्री|पहाटेच्या|पहाटे"#

  /// A part of the day before an hour, as a pattern: "सकाळी 9 वाजता",
  /// "सकाळच्या 7 वाजता", "रात्री ठीक 10 वाजता", "सकाळी लवकर 6 वाजता". With
  /// `capturing`, the part's words are group 1 of the lead. A part that "दर",
  /// "रोज", or "प्रत्येक" stands before ("रोज सकाळी 6 वाजता") belongs to the
  /// repeat, so the lead leaves it there and the hour takes its part from the
  /// line (``marathiLinePartOfDay(beside:)``).
  private static func marathiPartLead(capturing: Bool) -> String {
    let words = capturing ? "(\(marathiPartLeadWords))" : "(?:\(marathiPartLeadWords))"
    return
      #"(?:(?<!\#(marathiEveryOrDaily)\s)\#(words)\s+(?:(?:ठीक|साधारण|सुमारे|जवळपास|अंदाजे|लवकर)\s+)?)"#
  }

  /// The part of the day a matched word or phrase names.
  static func marathiPartOfDay(_ text: String) -> PartOfDay? {
    let words = marathiWords(in: text)
    func names(_ stem: String) -> Bool { words.contains { marathiHasPrefix($0, marathiKey(stem)) } }
    if names("रात्र") || names("मध्यरात्र") { return .night }
    if names("सकाळ") || names("पहाट") { return .morning }
    if names("दुपार") { return .day }
    if names("संध्याकाळ") || names("सायंकाळ") { return .evening }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("रात्री 9
  /// वाजता" is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that ends
  /// the day, and 1 to 5 the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``.
  private static func marathiTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: the adverb ("सकाळी"),
  /// or the stem with a genitive ("सकाळचा", "रात्रीचे", "संध्याकाळच्या"), as a
  /// whole word. "सकाळपर्यंत" and "रात्रभर" are other words.
  private static let marathiLinePartPattern = marathi(
    #"\#(devanagariStart)(?:सकाळ(?:ी|चा|ची|चे|च्या)|पहाट(?:े(?:चा|ची|चे|च्या)?|चा|ची|चे|च्या)|दुपार(?:ी|चा|ची|चे|च्या)|संध्याकाळ(?:ी|चा|ची|चे|च्या)|सायंकाळ(?:ी|चा|ची|चे|च्या)|रात्री(?:चा|ची|चे|च्या)?)\#(devanagariEnd)"#)

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "उद्या सकाळी मीटिंग 6 वाजता" and "रोज सकाळी 6 वाजता योग" are
  /// 06:00, and "रात्रीचे जेवण 8 वाजता" is 20:00, where the hour alone would be
  /// 18:00 and 08:00. Nil when the line names no part of the day, or names two
  /// that differ ("सकाळची औषधे, संध्याकाळचा चहा 5 वाजता").
  private static func marathiLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(marathiLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = marathiPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no
  /// part or two, or the part has no such hour ("सकाळची सैर 12 वाजता").
  private static func marathiTimeWithLinePart(
    hour: Int, minute: Int, hasLeadingZero: Bool, match: Match
  ) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = marathiLinePartOfDay(beside: match) else { return nil }
    return marathiTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The clock time an hour names: with its own part of the day when it has
  /// one, else with the part the line names elsewhere, else as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func marathiClock(
    hour: Int, minute: Int, hasLeadingZero: Bool, part: PartOfDay?, match: Match
  ) -> ClockTime? {
    if let part { return marathiTimeWithPart(hour: hour, minute: minute, part: part) }
    return marathiTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Clock words

  /// The words that name an hour or a fraction of one before वाजता: the counts
  /// one to twelve, दीड (1:30), and अडीच (2:30).
  static var marathiTimeWords: String {
    "\(marathiCountWords)|द[िी]ड|अड[िी]च"
  }

  /// The hours that दीड and अडीच name.
  private static let marathiHalfHours: [String: (hour: Int, minute: Int)] = [
    marathiKey("दीड"): (1, 30), marathiKey("दिड"): (1, 30), marathiKey("अडीच"): (2, 30), marathiKey("अडिच"): (2, 30),
  ]

  /// The hour a fraction word makes of the count after it, on the clock face:
  /// "साडेतीन" is 3:30, "सव्वातीन" is 3:15, and "पावणेचार" is 3:45. Nil for a
  /// word that is no fraction.
  private static func marathiFractionTime(_ fraction: String, hour: Int) -> (hour: Int, minute: Int)? {
    guard (1...12).contains(hour) else { return nil }
    switch fraction {
    case marathiKey("साडे"): return (hour, 30)
    case marathiKey("सव्वा"): return (hour, 15)
    case marathiKey("पावणे"): return (hour == 1 ? 12 : hour - 1, 45)
    default: return nil
    }
  }

  /// The time of an hour on the 12-hour clock with AM or PM written after it.
  private static func marathiMeridiemTime(hour: Int, minute: Int, meridiem: String) -> ClockTime? {
    guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
    let isAfternoon = meridiem.lowercased().hasPrefix("p")
    return ClockTime(minutes: ((hour % 12) + (isAfternoon ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Time

  /// "5 वाजता", "5:30 वाजता", "5.30 वाजता", "साडेपाच वाजता" (5:30), "सव्वापाच
  /// वाजता" (5:15), "पावणेसहा वाजता" (5:45), "दीड वाजता" (1:30), "अडीच वाजता"
  /// (2:30), "पाच वाजता", "सकाळी 9 वाजता", "रात्रीच्या 10 वाजता", "3:30 PM
  /// वाजता", each maybe after "ठीक", "साधारण", "सुमारे", "जवळपास", or "अंदाजे" and
  /// with a genitive glued to "वाजता" that goes with it ("5 वाजताची मीटिंग" is
  /// the meeting at 5). A fraction word may be written apart from its hour
  /// ("साडे पाच", "साडे 5"). An hour with no part of the day of its own takes
  /// the one the line names elsewhere (``marathiLinePartOfDay(beside:)``), and
  /// otherwise reads as ``bareTime(hour:minute:hasLeadingZero:)`` does. AM and
  /// PM after the hour are the system's own writing of a time ("3:30 PM
  /// वाजता"). A part of the day after वाजता is not read.
  /// Groups: 1 the part of the day before the hour, 2 the fraction word, 3 the
  /// hour in digits, 4 its minutes, 5 the hour in words, 6 AM or PM.
  static var marathiTimePattern: String {
    let approximate = #"(?:(?:ठीक|साधारण|सुमारे|जवळपास|अंदाजे)\s+)?"#
    let fraction = #"(?:(साडे|सव्वा|पावणे)\s*)?"#
    let hour = #"(?:(?<![:.,])(\d{1,2})(?:[:.](\d{2}))?|(\#(marathiTimeWords)))"#
    let meridiem = #"(?:(am|pm|a\.m\.|p\.m\.)\s*)?"#
    return
      #"\#(devanagariStart)\#(approximate)\#(marathiPartLead(capturing: true))?\#(fraction)\#(hour)\s*\#(meridiem)वाजता(?:·(?:चा|ची|चे|च्या))?\#(marathiTimeEnd)"#
  }

  static func marathiTime(_ match: Match) -> ClockTime? {
    let fraction = match.group(2).map(marathiPhrase)
    var minute = match.group(4).flatMap(number) ?? 0
    var hour: Int
    if let text = match.group(3) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(5).map(marathiPhrase) {
      if let half = marathiHalfHours[word] {
        guard fraction == nil else { return nil }
        (hour, minute) = half
      } else if let count = marathiCounts[word] {
        hour = count
      } else {
        return nil
      }
    } else {
      return nil
    }
    // A fraction counts from an hour on the clock face.
    if let fraction {
      guard minute == 0, let time = marathiFractionTime(fraction, hour: hour) else { return nil }
      (hour, minute) = time
    }
    if let meridiem = match.group(6) {
      guard match.group(1) == nil else { return nil }
      return marathiMeridiemTime(hour: hour, minute: minute, meridiem: meridiem)
    }
    let hasLeadingZero = startsWithZero(match.group(3) ?? "") && fraction == nil
    return marathiClock(
      hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, part: match.group(1).flatMap(marathiPartOfDay),
      match: match)
  }

  /// "साडेतीनला", "सव्वाचारला", "पावणेचारला", "दीडला", "अडीचला", "संध्याकाळी
  /// सहाला", "सकाळी 7 ला": a time with the ending "ला" glued to the hour or to
  /// the fraction and its count, as spoken ("at half past three"); after an
  /// hour in digits the ending may stand apart ("7 ला"). A fraction or दीड and
  /// अडीच make the hour a time by themselves; any other hour ("सहाला", "7 ला")
  /// needs a part of the day before it, since a number with "ला" is as often a
  /// count. Groups: 1 the part of the day, 2 the fraction word and 3 its hour
  /// (digits or words), 4 दीड or अडीच, 5 an hour in digits or words.
  static var marathiAtHourPattern: String {
    let alternatives =
      #"(?:(साडे|सव्वा|पावणे)\s*(\d{1,2}|\#(marathiCountWords))|(द[िी]ड|अड[िी]च)|(\d{1,2}|\#(marathiCountWords)))"#
    return
      #"\#(devanagariStart)\#(marathiPartLead(capturing: true))?\#(alternatives)(?:·|(?<=\d)\s+)ला\#(marathiTimeEnd)"#
  }

  static func marathiAtHour(_ match: Match) -> ClockTime? {
    let part = match.group(1).flatMap(marathiPartOfDay)
    if let fraction = match.group(2).map(marathiPhrase), let text = match.group(3) {
      guard let count = number(text) ?? marathiCounts[marathiPhrase(text)],
        let time = marathiFractionTime(fraction, hour: count)
      else { return nil }
      return marathiClock(hour: time.hour, minute: time.minute, hasLeadingZero: false, part: part, match: match)
    }
    if let word = match.group(4).map(marathiPhrase), let half = marathiHalfHours[word] {
      return marathiClock(hour: half.hour, minute: half.minute, hasLeadingZero: false, part: part, match: match)
    }
    guard let text = match.group(5), let part,
      let hour = number(text) ?? marathiCounts[marathiPhrase(text)]
    else { return nil }
    return marathiTimeWithPart(hour: hour, minute: 0, part: part)
  }

  /// "सकाळी 5:30", "रात्री 10.30": a part of the day with a colon or dotted time
  /// and no वाजता, or the colon time after a part that "रोज" or "दर" stands
  /// before ("रोज रात्री 10:30"), which takes the part from the line. A bare
  /// hour with a part ("संध्याकाळी 5") is no time. Groups: 1 the part of the
  /// day, 2 the hour, 3 the minutes; 4 the hour and 5 the minutes after "रोज"
  /// and its part.
  static var marathiPartColonTimePattern: String {
    let own = #"\#(marathiPartLead(capturing: true))(?<![:.,])(\d{1,2})[:.](\d{2})"#
    let afterEvery =
      #"(?<=\#(marathiEveryOrDaily)\s(?:\#(marathiPartLeadWords))\s)(?<![:.,])(\d{1,2})[:.](\d{2})"#
    return #"\#(devanagariStart)(?:\#(own)|\#(afterEvery))\#(marathiTimeEnd)"#
  }

  static func marathiPartColonTime(_ match: Match) -> ClockTime? {
    if let part = match.group(1).flatMap(marathiPartOfDay), let hour = match.group(2).flatMap(number),
      let minute = match.group(3).flatMap(number)
    {
      return marathiTimeWithPart(hour: hour, minute: minute, part: part)
    }
    guard let hour = match.group(4).flatMap(number), let minute = match.group(5).flatMap(number),
      let part = marathiLinePartOfDay(beside: match)
    else { return nil }
    return marathiTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// "मध्यरात्री", "मध्यरात्रीला", "ठीक मध्यरात्री": the midnight that ends the
  /// day. "मध्यरात्रीपर्यंत" is a deadline and "मध्यरात्रीनंतर" a time after it, so
  /// neither is read.
  static let marathiMidnightPattern =
    #"\#(devanagariStart)(?:ठीक\s+)?मध्यरात्री(?:·ला)?\#(devanagariEnd)"#

  // MARK: - Time range

  /// The side of a range, as a pattern: an hour in digits with maybe minutes,
  /// or an hour in words.
  private static var marathiRangeSide: String {
    #"((?<![:.,])\d{1,2}(?:[:.]\d{2})?|\#(marathiCountWords))"#
  }

  /// The words between the two sides of a range: "ते", a dash, or the
  /// "वाजेपासून" that ends the start ("3 वाजेपासून 5 वाजेपर्यंत").
  private static let marathiRangeConnector =
    #"(?:\s+ते\s+|\s*[-–—]\s*|\s*(?:वाजेपासून|वाजल्यापासून)\s+)"#

  /// "2 ते 4 वाजता", "2 वाजता ते 4 वाजता", "सकाळी 9 ते 11 वाजेपर्यंत", "सकाळी 9
  /// वाजेपासून संध्याकाळी 5 वाजेपर्यंत", "दोन ते चार वाजता", "2-4 वाजता". The
  /// end carries वाजता or वाजेपर्यंत: two bare numbers ("2 ते 4") are as often an
  /// amount. Groups: 1 the part of the day before the start, 2 the start, 3 the
  /// part before the end, 4 the end.
  static var marathiTimeRangePattern: String {
    #"\#(devanagariStart)\#(marathiPartLead(capturing: true))?\#(marathiRangeSide)(?:\s*वाजता)?\#(marathiRangeConnector)\#(marathiPartLead(capturing: true))?\#(marathiRangeSide)\s*(?:वाजता|वाजेपर्यंत)\#(marathiTimeEnd)"#
  }

  /// "14:00 ते 16:00", "9:30 ते 10:30 पर्यंत", "सकाळी 9:00 ते संध्याकाळी 5:00": a
  /// range of two colon times joined by "ते", maybe with "पर्यंत" after it. The
  /// same groups as ``marathiTimeRangePattern``. A range joined by a dash with
  /// no वाजता ("14:00-16:00") is English's.
  static var marathiColonTimeRangePattern: String {
    #"\#(devanagariStart)\#(marathiPartLead(capturing: true))?((?<![:.,])\d{1,2}:\d{2})\s+ते\s+\#(marathiPartLead(capturing: true))?(\d{1,2}:\d{2})(?:(?:·|\s+)पर्यंत)?+\#(marathiTimeEnd)"#
  }

  static func marathiTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(4) else { return nil }
    // A part of the day elsewhere in the line names the start's half of the day
    // (``marathiLinePartOfDay(beside:)``); the end is the first reading after the
    // start.
    guard
      let start = marathiRangeSideTime(startText, part: match.group(1), match: match, beside: match.group(1) == nil),
      let end = marathiRangeSideTime(endText, part: match.group(3), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func marathiRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = marathiCounts[marathiPhrase(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = marathiPartOfDay(part) else { return nil }
      return marathiTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = marathiTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a bound ("5 वाजेपर्यंत", "संध्याकाळी 5 वाजेपूर्वी",
  /// "18:00 पर्यंत", "5 वाजल्यानंतर", "5 PM पर्यंत"), which names no start time.
  /// Group 1 is the bound, or nil for a range ("2 वाजेपासून 4 वाजेपर्यंत"),
  /// which the range rules read and this rule only steps over, so the "4
  /// वाजेपर्यंत" inside it is not taken for a bound.
  static var marathiDeadlineClockPattern: String {
    let lead = marathiPartLead(capturing: false)
    let side = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(marathiCountWords))"#
    let range =
      #"(?:\#(lead)?\#(side)(?:\s*वाजता)?\#(marathiRangeConnector)\#(lead)?\#(side)\s*(?:वाजता|वाजेपर्यंत)|\#(lead)?\d{1,2}:\d{2}\s+ते\s+\#(lead)?\d{1,2}:\d{2}(?:(?:·|\s+)पर्यंत)?+)"#
    let deadline =
      #"((?:(?:ठीक|साधारण|सुमारे|जवळपास|अंदाजे)\s+)?\#(lead)?\#(marathiClockBound))"#
    return #"\#(devanagariStart)(?:\#(range)|\#(deadline))\#(devanagariEnd)"#
  }
}
