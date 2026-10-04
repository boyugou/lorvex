import Foundation

extension LorvexCaptureVocabulary {
  // The Hebrew clock-time rules: a time with a lead ("בשעה", "ב-"), a time with a
  // part of the day, a range of times, and the rules that keep a deadline
  // written as a clock time in the title. The vocabulary's other words are in
  // ``hebrew``.

  // MARK: - Parts of the day

  /// What may not follow a bare "ערב": the holiday or the day it is the eve of
  /// ("ערב שבת", "ערב חג"), which makes it a noun, not the evening.
  static let hebrewEveGuard =
    #"(?!\s+(?:חג|שבת|פסח|סוכות|שבועות|חנוכה|פורים|ראש|יום|החג)\#(hebrewEnd))"#

  /// The words that name a part of the day, as a pattern without groups: the
  /// morning (בוקר, "לפנות בוקר", "לפני הצהריים", לפנה״צ), the noon (צהריים), the
  /// afternoon ("אחר הצהריים", "אחרי הצהריים", אחה״צ), the evening (ערב, "לפנות
  /// ערב"), and the night (לילה), the plain words with ב or ה attached ("בבוקר",
  /// "הערב") or after "בשעות ה" ("בשעות הערב"). The full and the short
  /// spellings of the noon are both read (צהריים and צהרים).
  static let hebrewPartOfDayWords =
    #"(?:לפנות\s+(?:בוקר|ערב)|לפני\s+ה?צהר(?:יי|י)ם|לפנה״?צ|(?:בשעות\s+)?אחר(?:י)?[\s-]+ה?צהר(?:יי|י)ם|אחה״?צ|(?:בשעות\s+ה|ב|ה)?(?:בוקר|לילה|צהר(?:יי|י)ם)|(?:בשעות\s+ה|ב|ה)?ערב\#(hebrewEveGuard))"#

  /// The part of the day a matched word or phrase names.
  static func hebrewPartOfDay(_ text: String) -> PartOfDay? {
    let key = hebrewKey(text)
    let has: (String) -> Bool = { key.contains(hebrewTableKey($0)) }
    if has("לילה") { return .night }
    if has("לפנה״צ") || (has("לפני") && has("צהר")) || has("בוקר") { return .morning }
    if has("אחר") || has("צהר") || has("אחה״צ") { return .day }
    if has("ערב") { return .evening }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("ב-9
  /// בלילה" is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that ends
  /// the day, and 1 to 5 the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``. An hour on the 24-hour clock (13 to
  /// 23) is read as written when its part of the day is one it falls in ("17:30
  /// בערב", "15:00 אחר הצהריים"), the afternoon being 13 to 18, the evening 16 to
  /// 23, and the night 18 to 23.
  private static func hebrewTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
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
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: one of
  /// ``hebrewPartOfDayWords`` as a whole word, unless "עד" stands before it ("עד
  /// הבוקר" is a bound). The look-behind holds single-letter sets, so its
  /// length is bounded.
  private static let hebrewLinePartPattern = hebrew(
    #"\#(hebrewStart)(?<![ע][ד]\s)\#(hebrewPartOfDayWords)\#(hebrewEnd)"#)

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "מחר בבוקר בשעה 6" and "כל בוקר ב-6:30" are 06:00 and 06:30,
  /// and "ארוחת ערב בשעה 8" is 20:00, where the hour alone would be 18:00 and
  /// 08:00. Nil when the line names no part of the day, or names two that
  /// differ ("תרופות בבוקר ובערב בשעה 8").
  private static func hebrewLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(hebrewLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = hebrewPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no
  /// part or two, or the part has no such hour ("בוקר טוב, בשעה 12").
  private static func hebrewTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = hebrewLinePartOfDay(beside: match) else { return nil }
    return hebrewTimeWithPart(hour: hour, minute: minute, part: part)
  }

  // MARK: - Clock phrases

  /// The minutes that follow an hour: "ו-10 דקות", "ועשר דקות", "ועשרים וחמש
  /// דקות". The count is the one group when `capturing`.
  private static func hebrewMinutesAfterHour(capturing: Bool) -> String {
    let count = capturing ? "(\(hebrewMinuteCount))" : hebrewMinuteCount
    return #"(?:\s+ו-?\#(count)\s*(?:\#(hebrewMinuteNouns)))"#
  }

  /// A clock time that is plainly one, as a pattern without groups, with
  /// `lead` in front of the forms that need none of their own: an hour after
  /// "שעה" ("בשעה 5", "שעה 17:30", "בשעה 5 ו-10 דקות"), a colon time, an hour
  /// with a fraction word ("3 וחצי", "שלוש ורבע", "4 פחות רבע"), an hour with a
  /// part of the day ("5 בערב", "חמש אחר הצהריים"), or "רבע ל" and an hour
  /// ("רבע לשש"). A bare hour is none.
  private static func hebrewClockShapes(lead: String) -> String {
    let hour = #"(?:(?<![\p{N}:.,])\d{1,2}|\#(hebrewHourWords))"#
    let fraction = #"(?:\s+(?:וחצי|ורבע|פחות\s+רבע))"#
    let minutes = hebrewMinutesAfterHour(capturing: false)
    let part = #"(?:\s+\#(hebrewPartOfDayWords)\#(hebrewEnd))"#
    let marked =
      #"(?:ב|ל|ה)?שעה\s+(?:רבע\s+ל-?)?(?:\d{1,2}(?:[:.]\d{2})?|\#(hebrewHourWords))(?:\#(fraction)|\#(minutes))?\#(part)?"#
    return
      #"(?:\#(marked)|\#(lead)(?:(?<![\p{N}:.,])\d{1,2}:\d{2}\#(part)?|\#(hour)\#(fraction)\#(part)?|\#(hour)\#(part)|רבע\s+ל-?\#(hour)\#(part)?))"#
  }

  private static var hebrewClockPhrase: String { hebrewClockShapes(lead: "") }

  // MARK: - Time

  /// "בשעה 5", "בשעה 17:30", "בשעה 5.30", "ב-17:30", "ב-9 בבוקר", "9 בבוקר", "5
  /// אחר הצהריים", "בשלוש וחצי", "בשעה 3 ורבע", "רבע לשש", "בשעה 4 פחות רבע",
  /// "בשעה 3 ו-10 דקות", "בחמש בערב", "ב-3pm", each with the part of the day
  /// after the hour and maybe with "בשעה", "לשעה", "השעה", or "שעה" before it,
  /// after "בערך", "בסביבות", "בדיוק", or "בקירוב", and before "בדיוק" or
  /// "בערך" ("בערך בשעה 5", "בסביבות 5 בערב", "בשעה 5 בדיוק"). Groups: 1 the lead
  /// ("ב-" or a "שעה" word), 2 "רבע ל" (a quarter to the hour), 3 the hour in
  /// digits, 4 the separator of its minutes, 5 the minutes, 6 the hour in words,
  /// 7 the count of minutes after the hour ("ו-10 דקות"), 8 a fraction word after
  /// the hour, 9 the part of the day after it, 10 the "a" or "p" of an English am
  /// or pm. ``hebrewTime(_:)`` decides what makes the number a time: a lead that
  /// is a "שעה" word, a colon, a fraction word, "רבע ל", or a part of the day or
  /// an am or pm. A bare hour after "ב-" ("ב-5") is none, since "ב-5 ימים" and
  /// "ב-5 ש״ח" count things. An am or pm with no lead ("3:30 pm") is left to
  /// English, which takes the "at" before it too.
  static var hebrewTimePattern: String {
    let lead = #"(?:(ב-?|(?:ב|ל|ה)?שעה\s+))?"#
    let hour = #"(?:(?<![\p{N}:.,])(\d{1,2})(?:([:.])(\d{2}))?|(\#(hebrewHourWords)))"#
    let minutesAfter = hebrewMinutesAfterHour(capturing: true) + "?"
    let fraction = #"(?:\s+(וחצי|ורבע|פחות\s+רבע))?"#
    let part = #"(?:\s+(\#(hebrewPartOfDayWords))\#(hebrewEnd))?"#
    let meridiem = #"(?:\s*([ap])\.?m\.?(?!\p{Latin}))?"#
    let before = #"(?:(?:בערך|בסביבות|בדיוק|בקירוב)\s+)?"#
    let after = #"(?:\s+(?:בדיוק|בערך)\#(hebrewEnd))?"#
    return
      #"\#(hebrewStart)\#(before)\#(lead)(רבע\s+ל-?)?\#(hour)\#(minutesAfter)\#(fraction)\#(part)\#(meridiem)\#(hebrewTimeEnd)\#(after)"#
  }

  static func hebrewTime(_ match: Match) -> ClockTime? {
    let beth = hebrewTableKey("ב")
    let lead = match.group(1).map(hebrewKey)
    let hasMarker = lead != nil && lead != beth
    let quarterTo = match.group(2) != nil
    let fraction = match.group(8).map(hebrewPhrase)
    let part = match.group(9)
    let meridiem = match.group(10)?.lowercased()
    let hasDigits = match.group(3) != nil
    let hasColon = match.group(4) == ":"
    if match.group(4) == ".", !hasMarker { return nil }
    var minute = match.group(5).flatMap(number) ?? 0
    if let count = match.group(7) {
      // "בשעה 3 ו-10 דקות": the count after the hour is its minutes, which no
      // colon, fraction word, or "רבע ל" already gives.
      guard let after = number(count) ?? hebrewRoundCounts[hebrewKey(count)], (0...59).contains(after),
        match.group(5) == nil, match.group(8) == nil, !quarterTo
      else { return nil }
      minute = after
    }
    var hour: Int
    if let text = match.group(3) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(6), let value = hebrewHours[hebrewKey(word)] {
      hour = value
    } else {
      return nil
    }
    // What makes the number a time. The "שעה" word is enough; with "ב-" or with
    // no lead the number needs a colon, a fraction, "רבע ל", a part of the day,
    // or an am or pm beside it, and a number written in words needs more than a
    // colon, which it cannot carry.
    if !hasMarker {
      let hasSign = hasColon || fraction != nil || quarterTo || part != nil || meridiem != nil
      guard hasSign else { return nil }
      if lead == nil, !(quarterTo || (part != nil && hasDigits) || hasColon) { return nil }
      if !hasDigits, !(fraction != nil || quarterTo || part != nil) { return nil }
    }
    if let fraction {
      guard minute == 0, (1...12).contains(hour) else { return nil }
      switch fraction {
      case hebrewTablePhrase("וחצי"): minute = 30
      case hebrewTablePhrase("ורבע"): minute = 15
      default:
        hour = hour == 1 ? 12 : hour - 1
        minute = 45
      }
    }
    if quarterTo {
      guard minute == 0, fraction == nil, (1...12).contains(hour) else { return nil }
      hour = hour == 1 ? 12 : hour - 1
      minute = 45
    }
    if let meridiem {
      // An am or pm with no Hebrew lead ("3:30 pm") is English's, which takes the
      // "at" before it as well.
      guard lead != nil, part == nil, (1...12).contains(hour), (0...59).contains(minute) else { return nil }
      return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
    }
    if let part {
      guard let kind = hebrewPartOfDay(part) else { return nil }
      return hebrewTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(match.group(3) ?? "") && fraction == nil && !quarterTo
    if let time = hebrewTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match) {
      return time
    }
    // A colon time with no part of the day anywhere in the line is English's.
    if lead == nil, !quarterTo, fraction == nil { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  /// "בחצות", "בחצות הלילה", "בשעה חצות": the midnight that ends the day. "עד
  /// חצות" and "אחרי חצות" are bounds and are not read.
  static let hebrewMidnightPattern = #"\#(hebrewStart)(?:ב|בשעה\s+)חצות(?:\s+הלילה)?\#(hebrewEnd)"#

  // MARK: - Time range

  /// The words that may open a range: "ב-", "מ-", "מהשעה", "משעה", "בין", "בין
  /// השעות", "בשעות", "בשעה", "שעה".
  private static let hebrewRangeOpener =
    #"(?:ב-?|מ(?:ה)?(?:שעה\s+)?-?|בין\s+(?:ה?שע(?:ה|ות)\s+)?|בשעות\s+|(?:ב|ל)?ה?שעה\s+)"#

  /// The words between the two sides of a range: a dash, "עד" or "ועד", "ל-" or
  /// "ו" (after "בין"), "לבין".
  private static let hebrewRangeConnector = #"(?:\s*([-–—])\s*|\s+(עד|ועד)\s+(?:ה?שעה\s+)?|\s+(ל-?|ו-?|לבין\s+))"#

  /// The body of the range pattern, with its groups capturing or not.
  private static func hebrewTimeRangeBody(capturing: Bool) -> String {
    let open = capturing ? "(" : "(?:"
    let side = #"\#(open)(?<![\p{N}:.,])\d{1,2}(?::\d{2})?|\#(hebrewHourWords))"#
    let part = #"(?:\s+\#(open)\#(hebrewPartOfDayWords))\#(hebrewEnd))?"#
    let connector = capturing ? hebrewRangeConnector : hebrewRangeConnector.replacingOccurrences(of: "(", with: "(?:")
      .replacingOccurrences(of: "(?:?:", with: "(?:")
    return #"\#(open)\#(hebrewRangeOpener))?\#(side)\#(part)\#(connector)\#(side)\#(part)"#
  }

  /// "מ-9 עד 11 בבוקר", "בין 2 ל-4 אחר הצהריים", "בין השעות 14:00 ל-16:00", "משעה 9
  /// עד 11", "9:00 עד 11:00", "ב-9:00-11:00", "בשעות 9-11", "מ-9 בבוקר עד 5 אחר
  /// הצהריים". The sides are two bare numbers ("מ-14 עד 16 עמודים" is a title) only
  /// with a word for hours ("משעה", "מהשעה", "בין השעות", "בשעות"), a colon, or a
  /// part of the day. Groups: 1 the opener, 2 the start, 3 its part of the day, 4
  /// a dash, 5 "עד" or "ועד", 6 "ל-", "ו-", or "לבין", 7 the end, 8 its part of
  /// the day.
  static var hebrewTimeRangePattern: String {
    #"\#(hebrewStart)\#(hebrewTimeRangeBody(capturing: true))\#(hebrewTimeEnd)\#(noMeridiemAfter)"#
  }

  static func hebrewTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(7) else { return nil }
    let opener = match.group(1).map(hebrewKey) ?? ""
    let isBetween = opener.hasPrefix(hebrewTableKey("בין"))
    let hasHourWord = opener.contains(hebrewTableKey("שע"))
    let hasPart = match.group(3) != nil || match.group(8) != nil
    guard hasHourWord || startText.contains(":") || endText.contains(":") || hasPart else { return nil }
    // "ל-" and "ו" join the sides after "בין" only; "עד" does not join them there.
    if match.group(6) != nil, !isBetween { return nil }
    if match.group(5) != nil, isBetween { return nil }
    guard
      let start = hebrewRangeSideTime(startText, part: match.group(3), match: match, beside: match.group(3) == nil),
      let end = hebrewRangeSideTime(endText, part: match.group(8), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func hebrewRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = hebrewHours[hebrewKey(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = hebrewPartOfDay(part) else { return nil }
      return hebrewTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = hebrewTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a bound ("עד 17:00", "עד השעה 5", "עד 5 בערב", "לפני
  /// 5 אחר הצהריים", "אחרי 18:00", "לא יאוחר מ-17:00"), which names no start
  /// time. Group 1 is the bound, or nil for a range ("מ-14:00 עד 16:00"), which
  /// the range rule reads and this rule only steps over, so the "עד 16:00" inside
  /// it is not taken for a bound.
  static var hebrewDeadlineClockPattern: String {
    let bound =
      #"((?:עד|לפני|אחרי|לא\s+יאוחר\s+מ-?)(?:\s+ה?שעה)?\s*-?\s*\#(hebrewClockPhrase))"#
    return #"\#(hebrewStart)(?:\#(hebrewTimeRangeBody(capturing: false))|\#(bound))\#(hebrewTimeEnd)"#
  }

  /// The clock after a deadline day ("עד יום שישי בשעה 17:00", "עד מחר ב-9:00"),
  /// which is a deadline's clock and stays in the title with the rest of the
  /// line once the day is read as the due day.
  static var hebrewDueClockPattern: String {
    #"\#(hebrewStart)\#(hebrewClockShapes(lead: "(?:ב-?)?"))\#(hebrewTimeEnd)"#
  }

  /// Whether the text before `match` ends with a deadline word and a day, and
  /// maybe a part of the day ("עד יום שישי", "עד מחר בבוקר"). The "עד" that joins
  /// the days of a repeating span of weekdays is no deadline word, so the clock
  /// after "כל יום ראשון עד חמישי" is the repeat's time.
  static func hebrewIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = hebrewTextBefore(match)
    if hebrewFinds(#"\#(hebrewWeekdaySpanPattern)\s*$"#, in: before) { return false }
    return hebrewFinds(
      #"(?:עד|לפני|לא\s+יאוחר\s+מ)\s*-?\s*(?:\#(hebrewDueDay))(?:\s+\#(hebrewPartOfDayWords))?\s*$"#,
      in: before)
  }
}
