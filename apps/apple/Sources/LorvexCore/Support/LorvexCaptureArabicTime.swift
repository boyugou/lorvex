import Foundation

extension LorvexCaptureVocabulary {
  // The Arabic clock-time rules: a time after "الساعة", a time with a part of
  // the day or with AM or PM, a range of times, and the rule that keeps a
  // deadline written as a clock time in the title. The vocabulary's other
  // words are in ``arabic``.

  // MARK: - Parts of the day

  /// The words that name a part of the day, as a pattern: the morning
  /// (صباحاً, الصباح, في الصباح, الصبح, فجراً), the day (ظهراً, بعد الظهر, عصراً,
  /// العصر), the evening (مساءً, المساء), and the night (ليلاً, الليل,
  /// بالليل). A word in the pattern has no group.
  static let arabicPartOfDayWords =
    #"(?:(?:في\s+)?(?:ال)?(?:صباح|صبح|فجر)ا?|(?:(?:في|بعد)\s+)?(?:ال)?(?:ظهر|عصر)ا?|(?:في\s+)?(?:ال)?مساءا?|(?:في\s+)?ب?(?:ال)?ليلا?)"#

  /// A part of the day or AM or PM (ص, م) after an hour. A letter stands for
  /// AM or PM only beside an hour that is plainly a time (after "الساعة" or
  /// with minutes), since a number before م is as often meters.
  static let arabicPartOrMeridiem = #"(?:\#(arabicPartOfDayWords)|ص|م)"#

  /// The part of the day a matched word or phrase names.
  static func arabicPartOfDay(_ text: String) -> PartOfDay? {
    let words = arabicPhrase(text)
    if ["صباح", "صبح", "فجر"].contains(where: { words.contains($0) }) { return .morning }
    if ["ظهر", "عصر"].contains(where: { words.contains($0) }) { return .day }
    if words.contains("مساء") { return .evening }
    if words.contains("ليل") { return .night }
    return nil
  }

  /// The clock time `hour` and `minute` name with a matched part of the day or
  /// with ص (AM) or م (PM), or nil when no one says that hour with it.
  ///
  /// A letter is exact: 1 to 12 o'clock, 12 AM being 0:00 and 12 PM noon. The
  /// night counts from the evening, since "الساعة 9 ليلاً" is 9 PM: 6 to 11
  /// o'clock is the evening, 12 the midnight that ends the day, and 1 to 5 the
  /// small hours after it (``nightTime(hour:minute:)``). The other parts of
  /// the day follow ``partOfDayTime(hour:minute:part:)``.
  private static func arabicTimeWithPart(hour: Int, minute: Int, part: String) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    let word = arabicPhrase(part)
    if word == "ص" || word == "م" {
      guard (1...12).contains(hour) else { return nil }
      return ClockTime(minutes: (hour % 12 + (word == "م" ? 12 : 0)) * 60 + minute)
    }
    guard let kind = arabicPartOfDay(word) else { return nil }
    return kind == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: kind)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day that opens a weekday phrase ("مساء الخميس"), which the
  /// day rule reads as one day.
  private static let arabicPartBeforeWeekday =
    #"(?:صباح|ظهر|عصر|مساء|فجر)\s+ال(?:\#(arabicWeekdayNames))\#(arabicEnd)"#

  /// A part of the day, maybe with its weekday, that ends the text before a
  /// time ("غداً صباحاً " before "الساعة 6", "مساء الخميس " before "الساعة 8"),
  /// in the form of text without vowel signs. Group 1 is the part of the day.
  private static let arabicDayPartBefore = arabicForMatching(
    #"(?:^|\s)(\#(arabicPartOfDayWords))(?:\s+(?:يوم\s+)?(?:ال)?(?:\#(arabicWeekdayNames))(?:\s+(?:\#(arabicNextWords)))?)?\s+$"#
  )

  /// A part of the day that opens a weekday phrase and starts the text after a
  /// time ("مساء الخميس" after "الساعة 5"), in the form of text without vowel
  /// signs. Group 1 is the part of the day.
  private static let arabicDayPartAfter = arabicForMatching(#"^\s+(صباح|ظهر|عصر|مساء|فجر)\s+ال(?:\#(arabicWeekdayNames))\#(arabicEnd)"#)

  /// The part of the day a time written without one takes from the day phrase
  /// beside it: "غداً صباحاً" or "مساء الخميس" before the hour ("غداً صباحاً
  /// الساعة 6" is 6:00, not 18:00, and "هذا المساء الساعة 5" is 17:00), or a
  /// part of the day that opens a weekday phrase after it ("الساعة 5 مساء
  /// الخميس"). Nil when neither stands beside the time.
  private static func arabicDayPart(beside match: Match) -> String? {
    guard let timeRange = Range(match.result.range, in: match.source) else { return nil }
    func part(of pattern: String, in text: String) -> String? {
      guard let regex = LorvexCapturePatterns.regex(pattern),
        let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let captured = Range(found.range(at: 1), in: text)
      else { return nil }
      return String(text[captured])
    }
    let before = arabicBare(String(match.source[..<timeRange.lowerBound]))
    if let found = part(of: arabicDayPartBefore, in: before) { return found }
    return part(of: arabicDayPartAfter, in: arabicBare(String(match.source[timeRange.upperBound...])))
  }

  // MARK: - Time

  /// The words before "الساعة" that may be part of a time: "في", "عند", "على",
  /// the colloquial "ع", "في تمام" (at exactly), and "حوالي" (about).
  private static let arabicTimeLead =
    #"(?:في\s+تمام|عند\s+تمام|على\s+تمام|تمام|في|عند|على|ع|حوالي|نحو|قرابة|بحدود|تقريبا)\s+"#

  /// "الساعة 3", "الساعة 3:30", "في الساعة 3 مساءً", "عند الساعة 9 صباحاً",
  /// "الساعة 3 م", "الساعة 3 ونصف", "الساعة 3 وربع", "الساعة 3 إلا ربع", "الساعة
  /// 15:00"; with no "الساعة": "9 صباحاً", "3:30 عصراً", "في 8 مساءً", "3:30 م"; and
  /// "عند منتصف الليل", "في منتصف النهار". A time with no Arabic word ("15:00",
  /// "3pm") is left to English. A part of the day that opens a weekday phrase
  /// right after the hour ("الساعة 5 مساء الخميس") is not part of the time: the
  /// day rule reads it with its weekday. Groups: 1 hour, 2 the colon or the
  /// dot, 3 minute, 4 "ونصف", "وربع", "وثلث", or "إلا ربع" after the hour, 5
  /// the part of the day or the letter; 6 hour, 7 minute, 8 the letter of "3:30
  /// م"; 9 hour, 10 the colon or the dot, 11 minute, 12 the part of the day of
  /// "9 صباحاً"; 13 midnight or noon.
  static var arabicTimePattern: String {
    let clock = #"(\d{1,2})(?:([.:])(\d{2}))?"#
    let fraction = #"(?:\s+(و\s*(?:ال)?(?:نصف|ربع|ثلث)|إلا\s+(?:ال)?(?:ربع|ثلث)))?"#
    let part = #"(?:\s*(?!\#(arabicPartBeforeWeekday))(\#(arabicPartOrMeridiem)))?"#
    let marked =
      #"\#(arabicStart)(?:\#(arabicTimeLead))?(?:ال)?ساعة\s*\#(clock)\#(fraction)\#(part)\#(arabicTimeEnd)"#
    let colonMeridiem = #"\#(arabicStart)(?<![.,:])(\d{1,2}):(\d{2})\s*(ص|م)\#(arabicTimeEnd)"#
    let partOnly =
      #"\#(arabicStart)(?:(?:في|عند|على|ع)\s+)?(?<![.,:])(\d{1,2})(?:([.:])(\d{2}))?\s*(\#(arabicPartOfDayWords))\#(arabicTimeEnd)"#
    let noonOrMidnight =
      #"\#(arabicStart)(?:في|عند)\s+((?:ال)?منتصف\s+(?:ال)?(?:ليل|نهار)|نصف\s+(?:ال)?ليل)\#(arabicEnd)"#
    return [marked, colonMeridiem, partOnly, noonOrMidnight].joined(separator: "|")
  }

  static func arabicTime(_ match: Match) -> ClockTime? {
    if let word = match.group(13).map(arabicPhrase) {
      return word.contains("نهار") ? ClockTime(minutes: 12 * 60) : ClockTime(minutes: 0, isAfterMidnight: true)
    }
    // A bound ("قبل الساعة 5", "حتى 9 صباحاً") is no start time.
    if let before = arabicWordBefore(match), arabicBoundWords.contains(before) { return nil }
    let hourGroup: Int
    let minuteGroup: Int
    let partGroup: Int
    if match.group(1) != nil {
      (hourGroup, minuteGroup, partGroup) = (1, 3, 5)
    } else if match.group(6) != nil {
      (hourGroup, minuteGroup, partGroup) = (6, 7, 8)
    } else {
      (hourGroup, minuteGroup, partGroup) = (9, 11, 12)
    }
    guard let hourText = match.group(hourGroup), let hour = number(hourText) else { return nil }
    var effectiveHour = hour
    var minute = match.group(minuteGroup).flatMap(number) ?? 0
    if let fraction = match.group(4).map(arabicPhrase) {
      // "3 ونصف" is half past; "3 إلا ربع" a quarter to, which is the 45th
      // minute of the hour before. Minutes written with a colon beside either
      // are no time.
      guard minute == 0 else { return nil }
      let minutes = fraction.contains("نصف") ? 30 : (fraction.contains("ربع") ? 15 : 20)
      if fraction.hasPrefix("و") {
        minute = minutes
      } else {
        guard hour != 0 else { return nil }
        effectiveHour = hour == 1 ? 12 : hour - 1
        minute = 60 - minutes
      }
    }
    if let part = match.group(partGroup) {
      return arabicTimeWithPart(hour: effectiveHour, minute: minute, part: part)
    }
    if let part = arabicDayPart(beside: match),
      let time = arabicTimeWithPart(hour: effectiveHour, minute: minute, part: part)
    {
      return time
    }
    return bareTime(
      hour: effectiveHour, minute: minute, hasLeadingZero: startsWithZero(hourText) && match.group(4) == nil)
  }

  // MARK: - Time range

  /// "من الساعة 2 إلى 4", "من 2 مساءً إلى 4 مساءً", "من 9 صباحاً حتى 5 مساءً", "من
  /// 14:00 إلى 16:00", "من 9 ص إلى 5 م", "بين الساعة 2 و4", "الساعة 2-4", "الساعة
  /// 14:00-16:00", "من 14:00-16:00". A range with a dash and no lead
  /// ("14:00-16:00") is left to English. Groups: 1 the words before the range
  /// (من, بين, الساعة, each maybe with "الساعة"), 2 the start, 3 the part of the
  /// day after it, 4 the word or the dash between the sides, 5 the end, 6 the
  /// part of the day after it.
  static var arabicTimeRangePattern: String {
    let side = #"(\d{1,2}(?::\d{2})?)"#
    let part = #"(?:\s*(\#(arabicPartOrMeridiem)))?"#
    return
      #"\#(arabicStart)((?:من|بين)(?:\s+(?:ال)?ساعة)?|(?:(?:في|عند|على|ع)\s+)?(?:ال)?ساعة)\s*\#(side)\#(part)(\s+(?:إلى|حتى)\s+|\s+و\s*|\s*[-–—]\s*)(?:(?:ال)?ساعة\s*)?\#(side)\#(part)\#(arabicTimeEnd)"#
  }

  static func arabicTimeRange(_ match: Match) -> ClockTime? {
    guard let lead = match.group(1).map(arabicPhrase), let connector = match.group(4).map(arabicPhrase),
      let startText = match.group(2), let endText = match.group(5),
      let start = arabicRangeSide(startText, part: match.group(3)),
      let end = arabicRangeSide(endText, part: match.group(6))
    else { return nil }
    let leadWords = lead.split(separator: " ")
    let opensWithBetween = leadWords.contains("بين")
    let isMarked = leadWords.contains("ساعه") || leadWords.contains("الساعه")
    // "إلى" and "حتى" join the sides after "من" or "الساعة", "و" only after
    // "بين", which takes no dash.
    switch connector {
    case "الي", "حتي": if !leadWords.contains("من"), !isMarked { return nil }
    case "و": if !opensWithBetween { return nil }
    default: if opensWithBetween { return nil }
    }
    // Two bare hours are as often an amount or numbered items ("من 14 إلى 16
    // صفحة"): they are a range only when the lead says they are hours.
    let isBare = [startText, endText].allSatisfy { $0.allSatisfy(\.isNumber) }
    if isBare, match.group(3) == nil, match.group(6) == nil, !isMarked { return nil }
    if let before = arabicWordBefore(match), arabicBoundWords.contains(before) { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of
  /// the day when it has one.
  private static func arabicRangeSide(_ text: String, part: String?) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.2.flatMap { number($0) } ?? 0
    if let part { return arabicTimeWithPart(hour: hour, minute: minute, part: part) }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)))
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a deadline ("قبل الساعة 18:00", "حتى 18:00", "بعد
  /// الساعة 5:30", "بحلول 9:00"), which names no start time. Group 1 is the
  /// deadline, or nil for a range ("من 14 إلى 18:00"), which the range rule
  /// reads and this rule only steps over, so the "إلى 18:00" inside it is not
  /// taken for a deadline.
  static let arabicDeadlineClockPattern =
    #"\#(arabicStart)(?:من\s+(?:(?:ال)?ساعة\s*)?\d{1,2}(?:[.:]\d{2})?(?:\s*\#(arabicPartOrMeridiem))?\s+(?:إلى|حتى)\s+(?:(?:ال)?ساعة\s*)?\d{1,2}:\d{2}|((?:قبل|بعد|حتى|بحلول|لغاية|إلى|منذ|مذ)\s+(?:(?:ال)?ساعة\s*)?\d{1,2}:\d{2}))(?![\p{N}:]|[.,]\p{N})"#
}
