import Foundation

extension LorvexCaptureVocabulary {
  // The Persian clock-time rules: a time after "ساعت", a time with a part of
  // the day, a time given as minutes to an hour, a range of times, and the
  // rule that keeps a deadline written as a clock time in the title. The
  // vocabulary's other words are in ``persian``.

  // MARK: - Parts of the day

  /// The words that name a part of the day, as a pattern without groups: the
  /// morning (صبح, سحر, بامداد, پگاه, قبل از ظهر), the day (ظهر, بعد از ظهر),
  /// the evening (عصر, غروب), and the night (شب, شامگاه). A compound may be
  /// typed with a space, a zero-width non-joiner, or nothing between its words.
  static let persianPartOfDayWords =
    #"(?:قبل‌از‌ظهر|بعد‌از‌ظهر|صبح(?:گاه)?|سحر(?:گاه)?|بامداد|پگاه|ظهر|عصر(?:گاه)?|غروب|شامگاه|شب)"#

  /// The parts of the day that may open a weekday phrase ("صبح پنجشنبه",
  /// "عصر جمعه"). The night is not one: "شب جمعه" is the night before Friday.
  static let persianPartBeforeDayWords =
    #"(?:قبل‌از‌ظهر|بعد‌از‌ظهر|صبح(?:گاه)?|سحر(?:گاه)?|بامداد|پگاه|ظهر|عصر(?:گاه)?|غروب)"#

  /// The part of the day a matched word or phrase names. The evening is عصر
  /// and غروب, so "ساعت ۷ عصر" is 19:00.
  static func persianPartOfDay(_ text: String) -> PartOfDay? {
    let key = persianKey(text)
    if key.contains("قبلازظهر") { return .morning }
    if key.contains("ظهر") { return .day }
    if ["صبح", "سحر", "بامداد", "پگاه"].contains(where: key.contains) { return .morning }
    if key.contains("عصر") || key.contains("غروب") { return .evening }
    if key.contains("شب") || key.contains("شامگاه") { return .night }
    return nil
  }

  /// The clock time `hour` and `minute` name with a matched part of the day, or
  /// nil when no one says that hour with it. The night counts from the
  /// evening, since "ساعت ۹ شب" is 9 PM: 6 to 11 o'clock is the evening, 12 is
  /// the midnight that ends the day, and 1 to 5 are the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``. A 24-hour hour agrees with a part
  /// of the day that fits it ("ساعت ۱۷ عصر" is 17:00) and is read as written.
  private static func persianTimeWithPart(hour: Int, minute: Int, part text: String) -> ClockTime? {
    guard (0...59).contains(minute), let part = persianPartOfDay(text) else { return nil }
    if (13...23).contains(hour) {
      return part == .morning ? nil : ClockTime(minutes: hour * 60 + minute)
    }
    return part == .night
      ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day, maybe with its day, that ends the text before a time
  /// ("فردا صبح " before "ساعت ۶", "صبح فردا " before "ساعت ۶", "هر شب "
  /// before "ساعت ۱۰"), in the form of text without vowel signs. Group 1 is the
  /// part of the day.
  private static let persianDayPartBefore = persian(
    #"(?:^|\s)(\#(persianPartOfDayWords))(?:\s+(?:امروز|فردا|پس‌فردا|(?:روز\s+)?(?:\#(persianWeekdayNames))(?:(?:‌ی)?\s+\#(persianNextWords))?))?\s+$"#,
    readsMarks: false)

  /// The part of the day a time written without one takes from the line: a
  /// part of the day, maybe with its day, right before it ("فردا صبح ساعت 6"
  /// is 06:00, not 18:00, and "هر شب ساعت 10" is 22:00). Nil when none
  /// stands there.
  private static func persianDayPart(beside match: Match) -> String? {
    guard let regex = LorvexCapturePatterns.regex(persianDayPartBefore) else { return nil }
    let before = persianTextBefore(match)
    guard let found = regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)),
      let captured = Range(found.range(at: 1), in: before)
    else { return nil }
    return String(before[captured])
  }

  // MARK: - Bounds

  /// The words that may stand between a bound word and the clock it bounds:
  /// "حدود", "حوالی", and the like.
  private static let persianApproximations = #"(?:(?:در|رأس|حدود|حدودا|حوالی|نزدیک|تقریبا|دقیقا)\s+)"#

  /// The text before a clock time that makes it a bound, not a start: "تا",
  /// "قبل از", "پیش از", "بعد از", or "پس از", maybe with the day it bounds
  /// ("تا فردا ساعت ۵", "تا جمعه صبح ساعت ۸"), approximations, and the word
  /// "ساعت" (for the hour of "قبل از ساعت ۵ عصر", which a rule without "ساعت"
  /// reads), at the end of the text before the time.
  private static let persianBoundBefore = persian(
    #"(?:^|\s)(?:تا|الی|(?:قبل|پیش|بعد|پس)\s+از)\s+(?:(?:\#(persianDueDayWords))\s+)?\#(persianApproximations)*(?:ساعت\s+)?$"#,
    readsMarks: false)

  /// Whether the text before `match` makes it a bound ("قبل از ساعت ۵", "تا
  /// ساعت ۵", "بعد از ۵ عصر"), which names no start time.
  static func persianIsBound(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(persianBoundBefore) else { return false }
    let before = persianTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  // MARK: - Fractions of an hour

  /// How a fraction phrase moves an hour: after it ("و نیم", "و ربع", "و ده
  /// دقیقه") or before the next one ("ربع کم", "ده دقیقه کم"), and by how many
  /// minutes, from 1 to 59. `text` is a matched phrase.
  private static func persianFraction(_ text: String) -> (isBefore: Bool, minutes: Int)? {
    var tokens = persianPhrase(text).split(separator: " ").map(String.init)
    let isBefore = tokens.last == "کم"
    if isBefore { tokens.removeLast() }
    if tokens.first == "و" { tokens.removeFirst() }
    guard let minutes = persianFractionMinutes(tokens) else { return nil }
    return (isBefore, minutes)
  }

  /// The minutes of "نیم" (30), "ربع" or "یک ربع" (15), and a count of minutes
  /// in digits or in words with or without "دقیقه" after it.
  private static func persianFractionMinutes(_ words: [String]) -> Int? {
    var tokens = words
    if tokens.last == "دقیقه" { tokens.removeLast() }
    let minutes: Int?
    switch tokens {
    case ["نیم"]: minutes = 30
    case ["ربع"], ["یک", "ربع"], ["یه", "ربع"]: minutes = 15
    default:
      if let (count, rest) = persianLeadingCount(tokens), rest.isEmpty { minutes = count } else { minutes = nil }
    }
    return minutes.flatMap { (1...59).contains($0) ? $0 : nil }
  }

  /// The count a run of words names: digits, one count word, or two joined by
  /// "و" as in "چهل و پنج"; with the words after it.
  static func persianLeadingCount(_ tokens: [String]) -> (count: Int, rest: ArraySlice<String>)? {
    guard let first = tokens.first else { return nil }
    if let value = number(first) { return (value, tokens.dropFirst()) }
    if tokens.count >= 3, tokens[1] == "و", let value = persianCounts[first + "و" + tokens[2]] {
      return (value, tokens.dropFirst(3))
    }
    guard let value = persianCounts[first] else { return nil }
    return (value, tokens.dropFirst())
  }

  /// The clock time of an `hour` and `minute` with a fraction that moves it
  /// and a part of the day, or the part of the day the line names beside the
  /// time, else as ``bareTime(hour:minute:hasLeadingZero:)`` reads it. A
  /// fraction "before" the next hour takes the hour before it ("ساعت ۶ ربع کم"
  /// is 5:45), and minutes written with a colon beside a fraction are no time.
  private static func persianClock(
    hour: Int, minute: Int, hasLeadingZero: Bool, change: (isBefore: Bool, minutes: Int)?, part: String?,
    match: Match
  ) -> ClockTime? {
    var hour = hour
    var minute = minute
    if let change {
      guard minute == 0 else { return nil }
      if change.isBefore {
        guard hour != 0 else { return nil }
        hour = hour == 1 ? 12 : hour - 1
        minute = 60 - change.minutes
      } else {
        minute = change.minutes
      }
    }
    if let part { return persianTimeWithPart(hour: hour, minute: minute, part: part) }
    if let beside = persianDayPart(beside: match),
      let time = persianTimeWithPart(hour: hour, minute: minute, part: beside)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero && change == nil)
  }

  // MARK: - Time

  /// A clock time as it stands after a bound word, as a pattern without
  /// groups: "ساعت ۵", "ساعت پنج", "ساعت ۵ عصر", or a colon time.
  static var persianClockPhrase: String {
    #"(?:ساعت(?:\s*\d{1,2}(?:[.:]\d{2})?|\s+(?:\#(persianClockHourWords))\#(persianEnd))|\d{1,2}:\d{2})(?:\s*\#(persianPartOfDayWords))?"#
  }

  /// "ساعت ۵", "ساعت ۵:۳۰", "ساعت ۱۷", "ساعت پنج", "در ساعت ۵", "رأس ساعت ۵",
  /// "حدود ساعت ۵", each maybe with a fraction of the hour ("ساعت ۵ و نیم",
  /// "ساعت ۵ و ربع", "ساعت ۵ و ده دقیقه", "ساعت ۶ ربع کم", "ساعت ۶ ده دقیقه
  /// کم") and a part of the day ("ساعت ۵ عصر", "ساعت ۸ و نیم شب"). Groups: 1
  /// hour in digits, 2 the colon or the dot, 3 minutes, 4 hour in words, 5 the
  /// fraction, 6 the part of the day. The number after "ساعت" is the hour
  /// unless "دقیقه" or "ربع" and "به" follow it: "ساعت ۱۰ دقیقه به ۶" and
  /// "ساعت یک ربع به ۶" count minutes before the hour, which
  /// ``persianToHourPattern`` reads.
  static var persianMarkedTimePattern: String {
    let amount = #"(?:\d{1,2}|\#(persianCountWords))"#
    let fraction =
      #"(\s+و\s+(?:نیم|(?:یک\s+)?ربع|\#(amount)\s*دقیقه)|\s+(?:(?:یک\s+)?ربع|\#(amount)\s*دقیقه)\s+کم)?"#
    let part = #"(?:\s*(\#(persianPartOfDayWords)))?"#
    let notMinutesToHour = #"(?!\s*(?:دقیقه|ربع)\s+(?:مانده\s+)?به\s)"#
    return
      #"\#(persianStart)\#(persianTimeLead)ساعت(?:\s*(\d{1,2})(?:([.:])(\d{2}))?|\s+(\#(persianClockHourWords)))\#(notMinutesToHour)\#(fraction)\#(part)\#(persianTimeEnd)"#
  }

  /// The words before "ساعت" that may be part of a time: "در", "رأس" (sharp),
  /// "حدود", "حوالی", and "نزدیک" (about), and "دقیقا" (exactly).
  private static let persianTimeLead =
    #"(?:(?:در|رأس|حدود|حدودا|حوالی|نزدیک|تقریبا|دقیقا)\s+){0,3}"#

  static func persianMarkedTime(_ match: Match) -> ClockTime? {
    guard !persianIsBound(match) else { return nil }
    let hour: Int
    let hasLeadingZero: Bool
    if let text = match.group(1), let value = number(text) {
      hour = value
      hasLeadingZero = startsWithZero(text)
    } else if let word = match.group(4), let value = persianHourCounts[persianKey(word)] {
      hour = value
      hasLeadingZero = false
    } else {
      return nil
    }
    let change = match.group(5).flatMap(persianFraction)
    if match.group(5) != nil, change == nil { return nil }
    return persianClock(
      hour: hour, minute: match.group(3).flatMap(number) ?? 0, hasLeadingZero: hasLeadingZero, change: change,
      part: match.group(6), match: match)
  }

  /// "۸ شب", "۹ صبح", "۵ عصر", "۸:۳۰ شب", "۸ و نیم شب", "۹ بامداد", "در ۸ شب":
  /// an hour in digits with a part of the day and no "ساعت". A number before a
  /// part of the day is as often a count ("۳ شب" is three nights), so the night
  /// names no hour from 1 to 5 without "ساعت". Groups: 1 hour, 2 the colon or
  /// the dot, 3 minutes, 4 the fraction, 5 the part of the day.
  static var persianPartTimePattern: String {
    let fraction = #"(?:\s+(و\s+(?:نیم|(?:یک\s+)?ربع)))?"#
    return
      #"\#(persianStart)(?:(?:در|رأس|حدود|حوالی)\s+)?(?<![\p{N}:.,])(\d{1,2})(?:([.:])(\d{2}))?\#(fraction)\s*(\#(persianPartOfDayWords))\#(persianTimeEnd)"#
  }

  static func persianPartTime(_ match: Match) -> ClockTime? {
    guard !persianIsBound(match), let hourText = match.group(1), let hour = number(hourText),
      let part = match.group(5)
    else { return nil }
    if persianPartOfDay(part) == .night, (1...5).contains(hour) { return nil }
    let change = match.group(4).flatMap(persianFraction)
    if match.group(4) != nil, change == nil { return nil }
    return persianClock(
      hour: hour, minute: match.group(3).flatMap(number) ?? 0, hasLeadingZero: startsWithZero(hourText),
      change: change, part: part, match: match)
  }

  /// "یک ربع به ۶", "ربع به ۶", "ده دقیقه به ۶", "۱۰ دقیقه مانده به ۶", "بیست
  /// دقیقه به شش", each maybe with "ساعت" before the amount or the hour and a
  /// part of the day after the hour ("یک ربع به ۶ عصر"): minutes before an
  /// hour. Groups: 1 the amount, 2 the hour in digits, 3 the hour in words, 4
  /// the part of the day.
  static var persianToHourPattern: String {
    let amount = #"((?:یک\s+)?ربع|\d{1,2}\s*دقیقه|(?:\#(persianCountWords))\s+دقیقه)"#
    return
      #"\#(persianStart)(?:(?:در|ساعت)\s+)?\#(amount)\s+(?:مانده\s+)?به\s+(?:ساعت\s+)?(?:(\d{1,2})|(\#(persianClockHourWords)))(?:\s*(\#(persianPartOfDayWords)))?\#(persianTimeEnd)"#
  }

  static func persianToHourTime(_ match: Match) -> ClockTime? {
    guard !persianIsBound(match), let amount = match.group(1),
      let minutes = persianFractionMinutes(persianPhrase(amount).split(separator: " ").map(String.init))
    else { return nil }
    let hour: Int
    if let text = match.group(2), let value = number(text) {
      hour = value
    } else if let word = match.group(3), let value = persianHourCounts[persianKey(word)] {
      hour = value
    } else {
      return nil
    }
    return persianClock(
      hour: hour, minute: 0, hasLeadingZero: false, change: (isBefore: true, minutes: minutes), part: match.group(4),
      match: match)
  }

  /// "۵ و نیم", "۸ و ربع" at the end of the line (maybe before a punctuation
  /// mark): an hour with a fraction and no "ساعت" or part of the day. The
  /// fraction word must end the line: "۲ و نیم کیلو" counts kilograms. Groups: 1
  /// the hour, 2 the fraction.
  static var persianBareFractionPattern: String {
    #"\#(persianStart)(?<![\p{N}:.,/])(\d{1,2})\s+و\s+(نیم|ربع)\#(persianEnd)(?=\s*[،,.;!؟?]?\s*$)"#
  }

  static func persianBareFractionTime(_ match: Match) -> ClockTime? {
    guard !persianIsBound(match), let hourText = match.group(1), let hour = number(hourText),
      let word = match.group(2).map(persianKey)
    else { return nil }
    return persianClock(
      hour: hour, minute: 0, hasLeadingZero: false, change: (isBefore: false, minutes: word == "نیم" ? 30 : 15),
      part: nil, match: match)
  }

  /// "در نیمه‌شب", "ساعت نیمه شب", "رأس نیمه‌شب": the midnight that ends the
  /// day.
  static var persianMidnightPattern: String {
    #"\#(persianStart)(?:(?:در|رأس|حدود|حوالی|ساعت)\s+)نیمه‌شب\#(persianEnd)"#
  }

  static func persianMidnightTime(_ match: Match) -> ClockTime? {
    persianIsBound(match) ? nil : ClockTime(minutes: 0, isAfterMidnight: true)
  }

  // MARK: - Time range

  /// "از ساعت ۲ تا ۴", "ساعت ۲ تا ۴", "ساعت ۲ الی ۴", "از ۹ صبح تا ۵ بعدازظهر",
  /// "از ساعت ۱۴:۰۰ تا ۱۶:۰۰", "بین ساعت ۲ و ۴", "ساعت ۲-۴", "از ۲ تا ۴ عصر".
  /// Groups: 1 the words before the range (از, بین, or ساعت, each maybe with
  /// "ساعت"), 2 the start, 3 the part of the day after it, 4 the word or the
  /// dash between the sides, 5 the end, 6 the part of the day after it.
  static var persianTimeRangePattern: String {
    let side = #"(\d{1,2}(?::\d{2})?)"#
    let part = #"(?:\s*(\#(persianPartOfDayWords)))?"#
    return
      #"\#(persianStart)((?:از|بین)(?:\s+ساعت)?|(?:در\s+)?ساعت)\s*\#(side)\#(part)(\s+(?:تا|الی)\s+|\s+و\s+|\s*[-–—]\s*)(?:ساعت\s*)?\#(side)\#(part)\#(persianTimeEnd)"#
  }

  static func persianTimeRange(_ match: Match) -> ClockTime? {
    guard let lead = match.group(1).map(persianPhrase), let connector = match.group(4).map(persianPhrase),
      let startText = match.group(2), let endText = match.group(5),
      let start = persianRangeSide(startText, part: match.group(3)),
      let end = persianRangeSide(endText, part: match.group(6)), !persianIsBound(match)
    else { return nil }
    let leadWords = lead.split(separator: " ")
    let opensWithBetween = leadWords.contains("بین")
    let isMarked = leadWords.contains("ساعت")
    // "و" joins the sides only after "بین", which takes no dash.
    switch connector {
    case "و": if !opensWithBetween { return nil }
    case "تا", "الی": break
    default: if opensWithBetween { return nil }
    }
    // Two bare hours are as often an amount or numbered items ("از ۱۴ تا ۱۶
    // صفحه"): they are a range only when the lead says they are hours.
    let isBare = [startText, endText].allSatisfy { $0.allSatisfy(\.isNumber) }
    if isBare, match.group(3) == nil, match.group(6) == nil, !isMarked { return nil }
    return timeRange(from: start, to: end)
  }

  /// "۱۴:۰۰ تا ۱۶:۰۰", "۹:۳۰ الی ۱۰:۳۰": a range of two colon times joined by
  /// "تا" or "الی". A range with a dash ("14:00-16:00") is English's. Groups:
  /// 1 the start, 2 the end.
  static var persianColonTimeRangePattern: String {
    #"\#(persianStart)(?<![.,:])(\d{1,2}:\d{2})\s+(?:تا|الی)\s+(\d{1,2}:\d{2})\#(persianTimeEnd)"#
  }

  static func persianColonTimeRange(_ match: Match) -> ClockTime? {
    guard !persianIsBound(match), let start = match.group(1).flatMap(colonTime),
      let end = match.group(2).flatMap(colonTime)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of
  /// the day when it has one.
  private static func persianRangeSide(_ text: String, part: String?) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.2.flatMap { number($0) } ?? 0
    if let part { return persianTimeWithPart(hour: hour, minute: minute, part: part) }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)))
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a deadline ("تا ساعت ۱۸:۰۰", "قبل از ۱۸:۰۰", "بعد
  /// از ساعت ۵:۳۰"), which names no start time. Group 1 is the deadline, or nil
  /// for a range ("از ۱۴ تا ۱۸:۰۰", "ساعت ۲ تا ۴:۳۰", "۱۴:۰۰ تا ۱۶:۰۰"), which
  /// the range rules read and this rule only steps over, so the "تا ۱۸:۰۰"
  /// inside it is not taken for a deadline.
  static var persianDeadlineClockPattern: String {
    let start =
      #"(?:از\s+(?:ساعت\s*)?|ساعت\s*)\d{1,2}(?:[.:]\d{2})?(?:\s*\#(persianPartOfDayWords))?|\d{1,2}:\d{2}"#
    return
      #"\#(persianStart)(?:(?:\#(start))\s+(?:تا|الی)\s+(?:ساعت\s*)?\d{1,2}:\d{2}|((?:تا|قبل\s+از|پیش\s+از|بعد\s+از|پس\s+از)\s+(?:ساعت\s*)?\d{1,2}:\d{2}))(?![\p{N}:]|[.,]\p{N})"#
  }
}
