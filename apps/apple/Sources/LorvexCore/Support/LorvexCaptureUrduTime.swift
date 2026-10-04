import Foundation

extension LorvexCaptureVocabulary {
  // The Urdu clock-time rules: a time with بجے, a time with a part of the day,
  // a range of times, and the rule that keeps a deadline written as a clock
  // time in the title. The vocabulary's other words are in ``urdu``.

  // MARK: - Parts of the day

  /// The words that name a part of the day, as a pattern without groups: the
  /// morning (صبح, the doubled "صبح صبح", "صبح سویرے", سویرے, تڑکے), the day
  /// (دوپہر, "سہ پہر"), the evening (شام), and the night (رات, "دیر رات"). A
  /// compound may be typed with a space, a zero-width non-joiner, or nothing
  /// between its words.
  static let urduPartOfDayWords =
    #"(?:دیر\s+رات|رات|صبح(?:[-‐‑]|\s+)صبح|صبح\s+سویرے|صبح|سویرے|تڑکے|دوپہر|سہ\s*پہر|شام)"#

  private static let urduMorningKeys = ["صبح", "سویرے", "تڑکے"].map(urduTableKey)
  private static let urduDayKeys = ["دوپہر", "سہ پہر"].map(urduTableKey)

  /// A part of the day before an hour, as a pattern: "صبح 9 بجے", "شام کو 5
  /// بجے", "رات کے 10 بجے", "صبح ٹھیک 6 بجے", "صبح جلدی 6 بجے". With `capturing`,
  /// the part's words are group 1 of the lead. A part that "ہر" stands before
  /// ("ہر صبح 6 بجے") belongs to the repeat, so the lead leaves it there and the
  /// hour takes its part from the line (``urduLinePartOfDay(beside:)``). The
  /// look-behind holds single-letter sets, so its length is bounded however
  /// many vowel signs a typed word carries.
  private static func urduPartLead(capturing: Bool) -> String {
    let words = capturing ? "(\(urduPartOfDayWords))" : urduPartOfDayWords
    return
      #"(?:(?<![ہ][ر]\s)\#(words)(?:\s+(?:کے|کو|میں))?\s+(?:(?:ٹھیک|تقریبا|قریبا|لگ\s*بھگ|قریب|جلدی)\s+)?)"#
  }

  /// The part of the day a matched word or phrase names.
  static func urduPartOfDay(_ text: String) -> PartOfDay? {
    let key = urduKey(text)
    if key.contains(urduTableKey("رات")) { return .night }
    if urduMorningKeys.contains(where: key.contains) { return .morning }
    if urduDayKeys.contains(where: key.contains) { return .day }
    if key.contains(urduTableKey("شام")) { return .evening }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("رات 9
  /// بجے" is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that ends
  /// the day, and 1 to 5 the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``.
  private static func urduTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: one of
  /// ``urduPartOfDayWords`` as a whole word, unless a deadline word follows it
  /// ("کل صبح تک") or it is the "رات" of "آدھی رات". The look-behind holds
  /// single-letter sets, so its length is bounded.
  private static let urduLinePartPattern = urdu(
    #"\#(urduStart)(?<![آ][د][ھ][ی]\s)\#(urduPartOfDayWords)\#(urduEnd)(?!\s+(?:تک|سے\s+(?:پہلے|قبل)))"#)

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "کل صبح میٹنگ 6 بجے" and "ہر صبح 6 بجے ورزش" are 06:00, and
  /// "رات کا کھانا 8 بجے" is 20:00, where the hour alone would be 18:00 and
  /// 08:00. Nil when the line names no part of the day, or names two that
  /// differ ("صبح کی دوا، شام کی چائے 5 بجے").
  private static func urduLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(urduLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = urduPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no
  /// part or two, or the part has no such hour ("صبح کی سیر 12 بجے").
  private static func urduTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = urduLinePartOfDay(beside: match) else { return nil }
    return urduTimeWithPart(hour: hour, minute: minute, part: part)
  }

  // MARK: - Clock words

  /// The words that name an hour or a fraction of one before بجے: the counts
  /// one to twelve, ڈیڑھ (1:30), and ڈھائی (2:30).
  static var urduTimeWords: String {
    "\(urduCountWords)|ڈیڑھ|ڈھائی|اڑھائی"
  }

  /// The hours that ڈیڑھ and ڈھائی name.
  private static let urduHalfHours: [String: (hour: Int, minute: Int)] = [
    urduTableKey("ڈیڑھ"): (1, 30), urduTableKey("ڈھائی"): (2, 30), urduTableKey("اڑھائی"): (2, 30),
  ]

  /// A clock time as it stands before "تک" or "سے پہلے", as a pattern without
  /// groups: an hour with بجے (with a fraction word, a digit hour with
  /// minutes, or a number word), or a colon time.
  static var urduClockPhrase: String {
    #"(?:(?:ساڑھے|سوا|پونے)\s+)?(?:\d{1,2}(?:[:.]\d{2})?|\#(urduTimeWords))\s*بجے|\d{1,2}:\d{2}"#
  }

  // MARK: - Time

  /// "5 بجے", "5:30 بجے", "5.30 بجے", "ساڑھے 5 بجے", "سوا 5 بجے", "پونے 6 بجے",
  /// "ڈیڑھ بجے", "ڈھائی بجے", "پانچ بجے", "صبح 9 بجے", "شام کو 5 بجے", "رات کے
  /// 10 بجے", "9 بجے صبح", "10 بجے رات کو", each maybe after "ٹھیک", "تقریباً",
  /// "قریباً", "لگ بھگ", or "قریب" and with a word after بجے that goes with it:
  /// "پر", "سے", "کے لیے", "کے آس پاس", "کے قریب", or a possessive ("5 بجے کی
  /// میٹنگ"). A part of the day after بجے that a possessive follows ("5 بجے
  /// شام کی چائے") is part of the title. An hour with no part of the day of its
  /// own takes the one the line names elsewhere
  /// (``urduLinePartOfDay(beside:)``), and otherwise reads as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` does. Groups: 1 the part of the
  /// day before the hour, 2 the fraction word, 3 the hour in digits, 4 its
  /// minutes, 5 the hour in words, 6 the part of the day after بجے.
  static var urduTimePattern: String {
    let lead = #"(?:(?:ٹھیک|تقریبا|قریبا|لگ\s*بھگ|قریب)\s+)?"#
    let fraction = #"(?:(ساڑھے|سوا|پونے)\s+)?"#
    let hour = #"(?:(?<![:.,])(\d{1,2})(?:[:.](\d{2}))?|(\#(urduTimeWords)))"#
    let part =
      #"(?:\s+(\#(urduPartOfDayWords))\#(urduEnd)(?!\s+(?:کا|کی|کے|وال(?:ا|ی|ے))\#(urduEnd))(?:\s+(?:کو|میں)\#(urduEnd))?)?"#
    let trailing =
      #"(?:\s+(?:پر|سے(?!\s+(?:پہلے|قبل|بعد|لے|لیکر|\d))|کے\s+(?:لیے|آس\s*پاس|قریب|لگ\s*بھگ)|کا|کی|کے(?!\s+(?:بعد|پہلے|قبل|دوران|بیچ|درمیان|اندر)))\#(urduEnd))?"#
    return
      #"\#(urduStart)\#(lead)\#(urduPartLead(capturing: true))?\#(fraction)\#(hour)\s*بجے\#(part)\#(trailing)\#(urduTimeEnd)"#
  }

  static func urduTime(_ match: Match) -> ClockTime? {
    let fraction = match.group(2).map(urduPhrase)
    var minute = match.group(4).flatMap(number) ?? 0
    var hour: Int
    if let text = match.group(3) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(5).map(urduPhrase) {
      if let half = urduHalfHours[word] {
        guard fraction == nil else { return nil }
        (hour, minute) = half
      } else if let count = urduCounts[word] {
        hour = count
      } else {
        return nil
      }
    } else {
      return nil
    }
    // A fraction counts from an hour on the clock face: "ساڑھے 5" is 5:30,
    // "سوا 5" is 5:15, and "پونے 5" is 4:45.
    if let fraction {
      guard minute == 0, (1...12).contains(hour) else { return nil }
      switch fraction {
      case urduTableKey("ساڑھے"): minute = 30
      case urduTableKey("سوا"): minute = 15
      case urduTableKey("پونے"):
        hour = hour == 1 ? 12 : hour - 1
        minute = 45
      default: return nil
      }
    }
    // A part of the day on both sides of the hour contradicts itself.
    if match.group(1) != nil, match.group(6) != nil { return nil }
    if let partText = match.group(1) ?? match.group(6) {
      guard let part = urduPartOfDay(partText) else { return nil }
      return urduTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(match.group(3) ?? "") && fraction == nil
    return urduTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  /// "شام 5:30", "رات 10.30": a part of the day with a colon or dotted time and
  /// no بجے, or the colon time after a part that "ہر" stands before ("ہر رات
  /// 10:30"), which takes the part from the line. A bare hour with a part
  /// ("شام 5") is no time. Groups: 1 the part of the day, 2 the hour, 3 the
  /// minutes; 4 the hour and 5 the minutes of a colon time that ``urduPartColonTime(_:)``
  /// reads only after "ہر" and its part.
  static var urduPartColonTimePattern: String {
    let own = #"\#(urduPartLead(capturing: true))(?<![:.,])(\d{1,2})[:.](\d{2})"#
    let bare = #"(?<![:.,])(\d{1,2})[:.](\d{2})"#
    return #"\#(urduStart)(?:\#(own)|\#(bare))\#(urduTimeEnd)"#
  }

  static func urduPartColonTime(_ match: Match) -> ClockTime? {
    if let part = match.group(1).flatMap(urduPartOfDay), let hour = match.group(2).flatMap(number),
      let minute = match.group(3).flatMap(number)
    {
      return urduTimeWithPart(hour: hour, minute: minute, part: part)
    }
    guard let hour = match.group(4).flatMap(number), let minute = match.group(5).flatMap(number),
      urduFinds(#"(?:^|\s)ہر\s+\#(urduPartOfDayWords)\s*$"#, in: urduTextBefore(match)),
      let part = urduLinePartOfDay(beside: match)
    else { return nil }
    return urduTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// "آدھی رات", "نصف شب", "آدھی رات کو": the midnight that ends the day. "آدھی
  /// رات تک" is a deadline and "آدھی رات کے بعد" a time after it, so neither is
  /// read.
  static let urduMidnightPattern =
    #"\#(urduStart)(?:ٹھیک\s+)?(?:آدھی\s+رات|نصف\s+شب)(?:\s+(?:کو|میں)\#(urduEnd))?\#(urduEnd)(?!\s+(?:تک|کے\s+بعد|سے\s+(?:پہلے|قبل|بعد)))"#

  // MARK: - Time range

  /// The side of a range, as a pattern: an hour in digits with maybe minutes,
  /// or an hour in words.
  private static var urduRangeSide: String {
    #"((?<![:.,])\d{1,2}(?:[:.]\d{2})?|\#(urduCountWords))"#
  }

  /// What may follow the end of a range and go with it: "تک", "کے بیچ", "کے
  /// درمیان" ("3 سے 5 بجے کے بیچ").
  private static var urduRangeTail: String {
    #"(?:\s+(?:تک|کے\s+(?:بیچ|درمیان))\#(urduEnd))?+"#
  }

  /// The words between the two sides of a range: "سے", "تا", "سے لے کر", or a
  /// dash.
  private static let urduRangeConnector =
    #"(?:\s+(?:سے|تا)(?:\s+(?:لے\s*کر|لیکر))?\s+|\s*[-–—]\s*)"#

  /// "2 سے 4 بجے", "2 بجے سے 4 بجے تک", "صبح 9 سے 11 بجے تک", "صبح 9 بجے سے شام 5
  /// بجے تک", "دو سے چار بجے", "2-4 بجے", "2 تا 4 بجے", "2 بجے سے لے کر 4 بجے
  /// تک". The end carries بجے: two bare numbers ("2 سے 4") are as often an
  /// amount. A range with colons and no بجے ("14:00 سے 16:00") is
  /// ``urduColonTimeRangePattern``. Groups: 1 the part of the day before the
  /// start, 2 the start, 3 the part before the end, 4 the end.
  static var urduTimeRangePattern: String {
    #"\#(urduStart)\#(urduPartLead(capturing: true))?\#(urduRangeSide)(?:\s*بجے)?\#(urduRangeConnector)\#(urduPartLead(capturing: true))?\#(urduRangeSide)\s*بجے\#(urduRangeTail)\#(urduTimeEnd)"#
  }

  /// "14:00 سے 16:00", "9:30 سے 10:30 تک", "صبح 9:00 سے شام 5:00 تک": a range of
  /// two colon times joined by "سے" or "تا". The same groups as
  /// ``urduTimeRangePattern``. A range with a dash and no بجے ("14:00-16:00")
  /// is English's.
  static var urduColonTimeRangePattern: String {
    #"\#(urduStart)\#(urduPartLead(capturing: true))?((?<![:.,])\d{1,2}:\d{2})\s+(?:سے|تا)(?:\s+(?:لے\s*کر|لیکر))?\s+\#(urduPartLead(capturing: true))?(\d{1,2}:\d{2})\#(urduRangeTail)\#(urduTimeEnd)"#
  }

  static func urduTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(4) else { return nil }
    // A part of the day elsewhere in the line names the start's half of the day
    // (``urduLinePartOfDay(beside:)``); the end is the first reading after the
    // start.
    guard
      let start = urduRangeSideTime(startText, part: match.group(1), match: match, beside: match.group(1) == nil),
      let end = urduRangeSideTime(endText, part: match.group(3), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func urduRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = urduCounts[urduKey(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = urduPartOfDay(part) else { return nil }
      return urduTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = urduTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a bound ("5 بجے تک", "شام 5 بجے سے پہلے", "18:00
  /// تک", "5 بجے کے بعد", "5 بجے کے بیچ", "5 بجے کے دوران"), which names no
  /// start time.
  /// Group 1 is the bound, or nil for a range ("2 بجے سے 4 بجے تک"), which the
  /// range rules read and this rule only steps over, so the "4 بجے تک" inside
  /// it is not taken for a bound.
  static var urduDeadlineClockPattern: String {
    let part = urduPartLead(capturing: false)
    let side = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(urduCountWords))"#
    let range =
      #"(?:\#(part)?\#(side)(?:\s*بجے)?\#(urduRangeConnector)\#(part)?\#(side)\s*بجے|\#(part)?\d{1,2}:\d{2}\s+(?:سے|تا)(?:\s+(?:لے\s*کر|لیکر))?\s+\#(part)?\d{1,2}:\d{2})\#(urduRangeTail)"#
    let bound = #"(?:\#(urduDeadlineWords)|کے\s+(?:بعد|بیچ|درمیان|دوران))"#
    let deadline =
      #"((?:(?:ٹھیک|تقریبا|قریبا|لگ\s*بھگ|قریب)\s+)?\#(part)?(?:\#(urduClockPhrase))\s+\#(bound))"#
    return #"\#(urduStart)(?:\#(range)|\#(deadline))\#(urduEnd)"#
  }
}
