import Foundation

extension LorvexCaptureVocabulary {
  // The Vietnamese clock-time rules: a time written with "giờ" or "h" ("3 giờ
  // chiều", "15h30", "lúc 3 giờ rưỡi"), with a colon ("15:30", "3:30 CH"), the half
  // hour and the quarter before ("3 giờ rưỡi", "3 giờ kém 15"), a range of times,
  // midnight, and the rules that keep a deadline written as a clock time in the
  // title. The vocabulary's other words are in ``vietnamese``.

  // MARK: - Parts of the day

  /// A part of the day a clock time may be written with.
  private enum VietnamesePart {
    /// "sáng", "sáng sớm", "rạng sáng": 1 to 11 in the morning.
    case morning
    /// "trưa": 10 and 11 in the morning, noon, and the early afternoon, 1 to 4.
    case noon
    /// "chiều": the afternoon, 1 to 11 counted from noon.
    case afternoon
    /// "tối": the evening, 5 to 11 counted from noon.
    case evening
    /// "đêm", "khuya": the night, up to the small hours after midnight.
    case night
    /// "SA" (sáng), the 12-hour clock's AM.
    case am
    /// "CH" (chiều), the 12-hour clock's PM.
    case pm
  }

  /// The part of the day a matched word or phrase names: "chiều", "buổi tối",
  /// "rạng sáng", "đêm", "SA".
  private static func vietnamesePartOfDay(_ text: String) -> VietnamesePart? {
    // "SA" and "CH" are typed in capitals, which the lowercased key would not
    // tell from the words.
    switch text.trimmingCharacters(in: .whitespaces) {
    case "SA": return .am
    case "CH": return .pm
    default: break
    }
    let words = vietnameseKey(text).split(separator: " ").map(String.init)
    if words.contains("khuya") || words.contains("dem") { return .night }
    if words.contains("toi") { return .evening }
    if words.contains("chieu") { return .afternoon }
    if words.contains("trua") { return .noon }
    return words.contains("sang") ? .morning : nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for an
  /// hour no one says with it: "7 giờ sáng" is 07:00, "12 giờ trưa" noon, "2 giờ
  /// trưa" 14:00, "3 giờ chiều" 15:00, "8 giờ tối" 20:00, "2 giờ đêm" 02:00 on the
  /// next day, "9:30 SA" 09:30, "12:30 SA" 00:30, "3:30 CH" 15:30, and "12 giờ
  /// đêm" or "12 giờ tối" the midnight that ends the named day, on the next day. An
  /// hour on the 24-hour clock (13 to 23) is read as written when its part of the
  /// day is one it falls in: the noon is 13 to 16, the afternoon 13 to 19, and the
  /// evening 17 to 23.
  private static func vietnameseTimeWithPart(hour: Int, minute: Int, part: VietnamesePart) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    let written = ClockTime(minutes: hour * 60 + minute)
    switch part {
    case .morning:
      return (1...11).contains(hour) ? written : nil
    case .noon:
      if hour == 12 || (10...11).contains(hour) || (13...16).contains(hour) { return written }
      return (1...4).contains(hour) ? ClockTime(minutes: (hour + 12) * 60 + minute) : nil
    case .afternoon:
      if (1...11).contains(hour) { return ClockTime(minutes: (hour + 12) * 60 + minute) }
      return (13...19).contains(hour) ? written : nil
    case .evening:
      if (5...11).contains(hour) { return ClockTime(minutes: (hour + 12) * 60 + minute) }
      if hour == 12 { return ClockTime(minutes: minute, isAfterMidnight: true) }
      return (17...23).contains(hour) ? written : nil
    case .night:
      return nightTime(hour: hour, minute: minute)
    case .am:
      return (1...12).contains(hour) ? ClockTime(minutes: (hour % 12) * 60 + minute) : nil
    case .pm:
      return (1...12).contains(hour) ? ClockTime(minutes: (hour % 12 + 12) * 60 + minute) : nil
    }
  }

  /// The words after a part of the day that make it part of another word: "sáng
  /// tạo", "sáng kiến", "chiều cao", "chiều dài", "tối đa", "tối thiểu", "tối ưu".
  private static let vietnameseNotCompoundAfterPart =
    #"(?!\s+\#(vietnameseAlternation(["tạo", "kiến", "tác", "lập", "cao", "dài", "rộng", "đa", "thiểu", "ưu", "giản"]))\#(vietnameseEnd))"#

  /// The part of the day after an hour, as a pattern without groups: "sáng",
  /// "buổi chiều", "tối", "đêm", each with the space before it, and "SA" or "CH"
  /// in capitals, which may follow the time directly ("9:30SA"). A part followed by
  /// "nay" or "mai" ("8 giờ tối mai") is left to the day rule, which reads the
  /// whole "tối mai", and the clock reader finds the part after the match.
  private static let vietnamesePartAfterHour =
    #"(?:\s+\#(vietnameseBuoi)\#(vietnameseDayParts)(?!\s+(?:nay|mai)(?![\p{Latin}\p{N}\p{M}]))\#(vietnameseNotCompoundAfterPart)|\s*(?-i:SA|CH)(?![\p{Latin}\p{N}\p{M}]))"#

  /// A part of the day (maybe with a day after it, "tối nay", "sáng thứ Hai") at the
  /// end of the text before a clock time. Group 1: the part.
  private static var vietnamesePartBeforePattern: String {
    let day =
      #"(?:nay|mai|kia|\#(vietnameseWord("ngày"))\s+mai|\#(vietnameseWord("hôm nay"))|\#(vietnameseWeekdayNames)\#(vietnameseWeekdaySuffix)?)"#
    return #"(?:^|\s)\#(vietnameseBuoi)(\#(vietnameseDayParts))(?:\s+\#(day))?\s*[,:]?\s*$"#
  }

  /// A part of the day with "nay" or "mai" right at the start of the text after a
  /// clock time ("8 giờ" then " tối mai"). Group 1: the part.
  private static let vietnamesePartAfterPattern =
    #"^\s+\#(vietnameseBuoi)(\#(vietnameseDayParts))\s+(?:nay|mai)(?![\p{Latin}\p{N}\p{M}])"#

  /// A meal that names the part of the day it falls in: "ăn tối", "bữa trưa", "cơm
  /// chiều", "ăn sáng", "ăn khuya", "điểm tâm". Groups: 1 the part after "ăn",
  /// "bữa", or "cơm", 2 a phrase that names a part by itself.
  private static let vietnameseHabitPartPattern =
    #"\#(vietnameseStart)(?:\#(vietnameseAlternation(["ăn", "bữa", "cơm"]))\s+(\#(vietnameseDayParts))|(\#(vietnameseAlternation(["điểm tâm", "ăn khuya"]))))\#(vietnameseEnd)"#

  /// The parts of the day the meals in `text` name.
  private static func vietnameseHabitParts(in text: String) -> [VietnamesePart] {
    guard let regex = LorvexCapturePatterns.regex(vietnameseHabitPartPattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { found in
      if let range = Range(found.range(at: 1), in: text) { return vietnamesePartOfDay(String(text[range])) }
      guard let range = Range(found.range(at: 2), in: text) else { return nil }
      return vietnameseKey(String(text[range])) == "diem tam" ? .morning : .night
    }
  }

  /// The part written at the end of `text` ("tối", "sáng mai", "chiều thứ Sáu").
  private static func vietnamesePartBefore(_ text: String) -> VietnamesePart? {
    guard let regex = LorvexCapturePatterns.regex(vietnamesePartBeforePattern),
      let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(found.range(at: 1), in: text)
    else { return nil }
    return vietnamesePartOfDay(String(text[range]))
  }

  /// The part of the day the line names beside `match` for an hour written without
  /// one: the part written directly before it ("tối 8 giờ", "sáng mai 7h", "chiều
  /// thứ Sáu 4 giờ"), the part that opens the text after it before "nay" or "mai"
  /// ("8 giờ" then " tối mai"), or a meal in the same clause ("ăn tối lúc 7 giờ").
  /// Nil when the line names no part there, or names two that differ.
  private static func vietnameseLinePart(beside match: Match) -> VietnamesePart? {
    let separators = CharacterSet(charactersIn: ".;!?,\n")
    let beforeText = vietnameseTextBefore(match)
    let afterText = vietnameseTextAfter(match)
    var parts: [VietnamesePart] = []
    if let adjacent = vietnamesePartBefore(beforeText) { parts.append(adjacent) }
    if let regex = LorvexCapturePatterns.regex(vietnamesePartAfterPattern),
      let found = regex.firstMatch(in: afterText, range: NSRange(afterText.startIndex..., in: afterText)),
      let range = Range(found.range(at: 1), in: afterText), let adjacent = vietnamesePartOfDay(String(afterText[range]))
    {
      parts.append(adjacent)
    }
    let before = beforeText.components(separatedBy: separators).last ?? ""
    let after = afterText.components(separatedBy: separators).first ?? ""
    parts += vietnameseHabitParts(in: before) + vietnameseHabitParts(in: after)
    guard let first = parts.first, parts.allSatisfy({ $0 == first }) else { return nil }
    return first
  }

  /// Whether the line names a part of the day beside `match`, as
  /// ``vietnameseLinePart(beside:)`` finds one.
  static func vietnameseHasLinePart(beside match: Match) -> Bool {
    vietnameseLinePart(beside: match) != nil
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part of
  /// the day of its own) names: its line's part of the day when the line names one
  /// and the hour is on the clock of 12 hours, else the hour as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func vietnameseBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    if !hasLeadingZero, (1...12).contains(hour), let part = vietnameseLinePart(beside: match),
      let time = vietnameseTimeWithPart(hour: hour, minute: minute, part: part)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, colon, or
  /// slash (the word or the number goes on), no letter joined by a hyphen, no
  /// decimal fraction, no percent or currency sign with or without a space before
  /// it, and no dash before a digit, which makes the time one side of a range
  /// written with a dash.
  private static let vietnameseTimeEnd =
    #"(?![\p{Latin}\p{N}\p{M}:/]|[-–]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d)"#

  /// The word "đúng" ("sharp") after a clock time, which goes with the time: "3 giờ
  /// đúng". It is read only with its mark: "dung" is also "dùng" (to use).
  private static let vietnameseSharp = #"(?:\s+\#(vietnameseWord("đúng", strict: true))\#(vietnameseEnd))?"#

  /// The minute units: "phút", "ph", "p".
  private static let vietnameseMinuteUnit =
    #"(?:\#(vietnameseWord("phút"))|ph|p)(?![\p{Latin}\p{N}\p{M}])"#

  /// What may stand between an hour's unit and the minutes written after it, as a
  /// pattern without groups: nothing or a space after "giờ" ("3 giờ 30"); after
  /// "h" nothing ("15h30"), or a space when the minutes carry their unit ("1h
  /// 30p"). A bare number after "h" and a space is the next thing of the line, not
  /// minutes: "18h 1 tiếng" is 18:00 and an hour.
  private static let vietnameseBeforeMinutes =
    #"(?:(?<![hH])\s*|(?<=[hH])(?:\s+(?=\d{1,2}\s*\#(vietnameseMinuteUnit)))?)"#

  /// The words that count something after a number of minutes or hours, which
  /// makes the number a count and no minutes: "3 giờ 2 người".
  static let vietnameseNotCounted: String = {
    let nouns = vietnameseAlternation([
      "người", "bạn", "bé", "em", "cái", "con", "chiếc", "quyển", "cuốn", "lần", "buổi", "ngày", "tuần", "tháng", "năm",
      "tuổi", "đồng", "nghìn", "ngàn", "triệu", "tỷ", "kg", "km", "cm", "mm", "ml", "usd", "vnd", "trang", "bài", "câu",
      "tập", "phần", "gói", "hộp", "chai", "ly", "cốc", "viên",
    ])
    return #"(?!\s*\#(nouns)\#(vietnameseEnd))"#
  }()

  /// The words before a clock time that go with it and leave the title with it:
  /// "lúc", "vào lúc", "vào", "từ", "đúng", and the approximate "khoảng", "tầm",
  /// "chừng", "cỡ" ("lúc khoảng"), as a pattern without groups. "Đúng" is read only
  /// with its mark.
  private static let vietnameseClockLeadWords: String = {
    let plain = vietnameseAlternation([
      "vào lúc", "lúc", "vào", "từ", "khoảng", "tầm", "chừng", "cỡ", "vào khoảng", "vào tầm", "lúc khoảng", "lúc tầm",
    ])
    return "(?:\(vietnameseExactLead)|\(plain))"
  }()

  /// "đúng", "lúc đúng", "vào lúc đúng", "đúng lúc": the lead "exactly", as a pattern
  /// without groups. "Đúng" is read only with its mark: "dung" is also "dùng" (to
  /// use).
  private static let vietnameseExactLead: String = {
    let exactly = vietnameseWord("đúng", strict: true)
    let at = vietnameseWord("lúc")
    return #"(?:(?:\#(vietnameseWord("vào"))\s+)?\#(at)\s+\#(exactly)|\#(exactly)(?:\s+\#(at))?)"#
  }()

  /// The words before an hour that make it a clock time, as a pattern without
  /// groups: "lúc", "vào lúc", "vào", "từ", "đúng". The approximate "khoảng" is none:
  /// "khoảng 3 giờ" is about three o'clock or about three hours.
  static let vietnameseClockLead: String =
    "(?:\(vietnameseExactLead)|\(vietnameseAlternation(["vào lúc", "lúc", "vào", "từ"])))"

  /// Whether a matched lead is an approximation ("khoảng", "tầm", "chừng", "cỡ").
  private static func vietnameseIsApproximate(_ lead: String) -> Bool {
    vietnameseKey(lead).split(separator: " ").contains { ["khoang", "tam", "chung", "co"].contains($0) }
  }

  /// The words before a clock time that make it a bound, not a start: "trước",
  /// "sau", "đến", "tới", "hết", "nhất" ("chậm nhất"), "hạn", "deadline". The
  /// deadline rules keep such a bound in the title; the readers decline a time after
  /// one as well. "Tới" is a bound only with its mark: "toi" is also "tối".
  private static let vietnameseBoundWords = VietnameseWordSet([
    "trước", "sau", "đến", "hết", "nhất", "hạn", "chót", "deadline",
  ])

  /// The words after which "sau" or "tới" names the next day, week, month, or time,
  /// not a bound on the clock time that follows: "tuần sau 9 giờ" and "tuần tới 9 giờ"
  /// are next week at nine, and "thứ Sáu" typed without marks is "thu Sau". As a
  /// pattern without groups, with bounded gaps so that a look-behind may hold it.
  static let vietnameseNounBeforeNext = vietnameseAlternation(
    ["thứ", "tuần", "tháng", "năm", "quý", "ngày", "hôm", "buổi", "lần", "đợt", "kỳ"], gap: #"\s{1,3}"#)

  /// Whether the word just before `match` makes its clock time a bound. "Sau" typed
  /// without marks after "thứ" is Friday, and "sau" or "tới" after "tuần" is next
  /// week: no bound.
  private static func vietnameseFollowsBoundWord(_ match: Match) -> Bool {
    guard let word = wordBefore(match) else { return false }
    if word == "sau" || word == "tới",
      vietnameseFinds(
        #"\#(vietnameseStart)\#(vietnameseNounBeforeNext)\s+(?:sau|\#(vietnameseWord("tới")))\s*$"#,
        in: vietnameseTextBefore(match))
    {
      return false
    }
    return word == "tới" || vietnameseBoundWords.contains(word)
  }

  // MARK: - Clock time

  /// "3 giờ", "3 giờ chiều", "lúc 3 giờ 15", "lúc 3 giờ 15 phút", "3 giờ rưỡi", "3 giờ
  /// kém 15", "ba giờ chiều", "15h", "15h30", "3h chiều", "3 rưỡi chiều", "15:30", "3:30
  /// CH", "lúc 15.30", "3 giờ đúng", "tối 8 giờ", "ăn tối 7 giờ". An hour spelled as
  /// a word and an hour with "rưỡi" and no "giờ" need a lead or a part of the day. A
  /// time written with a colon and nothing else ("15:30") is English's. Groups: 1 the
  /// lead; 2 the hour; 3 its unit ("giờ" or "h"); 4 "rưỡi" after the unit; 5 "kém"
  /// after the unit, 6 the minutes after it, 7 their unit; 8 the minutes after the
  /// unit with no "kém", 9 their unit; 10 the colon or the dot, 11 the minutes after
  /// it; 12 "rưỡi" after an hour with no unit; 13 the part of the day. Minutes
  /// after "h" follow it directly or, with their unit, after a space (see
  /// ``vietnameseBeforeMinutes``).
  static var vietnameseClockPattern: String {
    let hour = #"(\d{1,2}|\#(vietnameseHourWords))"#
    let minutes = #"(\d{1,2}|\#(vietnameseNumberWords))"#
    // Minutes spelled as words after the hour count only with their unit ("ba giờ mười lăm phút").
    let plainMinutes = #"(\d{1,2}|\#(vietnameseNumberWords)(?=\s*\#(vietnameseMinuteUnit)))"#
    let minuteUnit = #"(?:\s*(\#(vietnameseMinuteUnit)))?"#
    let half = vietnameseWord("rưỡi")
    let afterUnit =
      #"(?:\s+(\#(half))|\s+(\#(vietnameseWord("kém")))\s+\#(minutes)\#(minuteUnit)|\#(vietnameseBeforeMinutes)\#(plainMinutes)\#(minuteUnit)\#(vietnameseNotCounted))?"#
    let unit = #"\s*(\#(vietnameseWord("giờ"))|h)\#(afterUnit)"#
    return
      #"\#(vietnameseStart)(?:(\#(vietnameseClockLeadWords))\s*)?(?<![\p{N}:.,/])(?<![-–—])(?<![-–—]\s)\#(hour)(?:\#(unit)|([.:])(\d{2})|\s+(\#(half)))(\#(vietnamesePartAfterHour))?\#(vietnameseSharp)\#(vietnameseTimeEnd)"#
  }

  static func vietnameseClock(_ match: Match) -> ClockTime? {
    guard let hourText = match.group(2), let hour = vietnameseCount(hourText), (0...23).contains(hour),
      !vietnameseFollowsBoundWord(match)
    else { return nil }
    let isWord = number(hourText) == nil
    let hasLead = match.group(1) != nil
    let isApproximate = match.group(1).map(vietnameseIsApproximate) ?? false
    let separator = match.group(10)
    let isHalf = match.group(4) != nil || match.group(12) != nil
    var minute = 0
    var behind = 0
    if isHalf {
      minute = 30
    } else if match.group(5) != nil {
      // "3 giờ kém 15" is 15 minutes before three.
      guard let text = match.group(6), let value = vietnameseCount(text), (1...59).contains(value) else { return nil }
      behind = value
    } else if let text = match.group(8) ?? match.group(11) {
      guard let value = vietnameseCount(text), (0...59).contains(value) else { return nil }
      minute = value
    }
    let ownPart = match.group(13).flatMap(vietnamesePartOfDay)
    if match.group(13) != nil, ownPart == nil { return nil }
    let hasMinutes = minute != 0 || behind != 0 || separator != nil
    // SA and CH are the system's AM and PM, written after minutes or a lead.
    if ownPart == .am || ownPart == .pm, !(hasLead || hasMinutes) { return nil }
    let linePart = ownPart == nil && !startsWithZero(hourText) && (1...12).contains(hour) ? vietnameseLinePart(beside: match) : nil
    let part = ownPart ?? linePart
    // An hour with no "giờ" or "h" ("3 rưỡi", "15:30") and an hour spelled as a word are a clock only
    // where the line says so: a lead or a part of the day.
    let hasEvidence = (hasLead && !isApproximate) || part != nil
    if isWord {
      guard match.group(3).map(vietnameseKey) == "gio", separator == nil, (1...12).contains(hour), hasEvidence else {
        return nil
      }
    }
    if match.group(12) != nil, !hasEvidence { return nil }
    if let separator {
      // A colon time with no lead and no part is English's; a dotted one may be a date.
      guard hasEvidence || (hasLead && separator == ":") else { return nil }
    }
    // "About 3 o'clock" and "about 3 hours" are written alike.
    if isApproximate, part == nil, !hasMinutes, !isHalf { return nil }
    func time(_ hour: Int, _ minute: Int) -> ClockTime? {
      if let part { return vietnameseTimeWithPart(hour: hour, minute: minute, part: part) }
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    guard var result = time(hour, minute) else { return nil }
    if behind > 0 {
      result.writtenHour = nil
      var total = result.minutes - behind
      if total < 0 {
        guard result.isAfterMidnight else { return nil }
        result.isAfterMidnight = false
        total += 24 * 60
      }
      result.minutes = total
    }
    return result
  }

  // MARK: - Meridiem with a lead

  /// "lúc 3pm", "vào lúc 3:30 pm", "từ 9am": a time with AM or PM after "lúc" or a
  /// similar lead, which takes its lead with it where English would leave it behind.
  /// A time with AM or PM and no lead is English's. Groups: 1 hour, 2 minute, 3 the
  /// "a" or "p".
  static var vietnameseMeridiemTimePattern: String {
    #"\#(vietnameseStart)\#(vietnameseClockLeadWords)\s*(\d{1,2})(?:[.:](\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}\p{M}:])"#
  }

  static func vietnameseMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased(), !vietnameseFollowsBoundWord(match)
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Midnight

  /// "nửa đêm", "giữa đêm" (midnight), maybe after "lúc", "vào lúc", or "vào". Noon
  /// has no standalone rule: "trưa" is also lunch and a stretch of the early
  /// afternoon, so it names a time only after an hour. A bound before midnight
  /// ("trước nửa đêm") is kept in the title by ``vietnameseDeadlineClockPattern``,
  /// and a midnight with a day word after it ("nửa đêm nay", "nửa đêm qua") is no
  /// time the rules can place, so ``vietnameseMidnightDayPattern`` keeps it whole.
  static let vietnameseMidnightPattern =
    #"\#(vietnameseStart)(?:\#(vietnameseAlternation(["vào lúc", "lúc", "vào"]))\s+)?\#(vietnameseAlternation(["nửa đêm", "giữa đêm"]))\#(vietnameseEnd)(?!\s+(?:nay|mai|qua|\#(vietnameseWord("nữa"))|\#(vietnameseWord("hôm qua"))))"#

  static func vietnameseMidnight(_ match: Match) -> ClockTime? {
    vietnameseFollowsBoundWord(match) ? nil : ClockTime(minutes: 0, isAfterMidnight: true)
  }

  /// "nửa đêm nay", "nửa đêm mai", "nửa đêm qua": midnight with a day word, kept
  /// whole in the title.
  static let vietnameseMidnightDayPattern =
    #"\#(vietnameseStart)\#(vietnameseAlternation(["nửa đêm", "giữa đêm"]))\s+(?:nay|mai|qua|\#(vietnameseWord("nữa"))|\#(vietnameseWord("hôm qua")))\#(vietnameseEnd)"#

  // MARK: - Time range

  /// The body of the range pattern, with its groups capturing or not. A side is an
  /// hour with a unit ("3 giờ", "3h30", "3 giờ rưỡi"), a colon or dotted time, or a
  /// bare hour, maybe before a part of the day.
  private static func vietnameseTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let unit = #"\s*\#(group("\(vietnameseWord("giờ"))|h"))(?:\s+\#(group(vietnameseWord("rưỡi")))|\s*\#(group(#"\d{1,2}"#)))?"#
    let colon = #"\#(group("[.:]"))\#(group(#"\d{2}"#))"#
    let side = #"(?<![\p{N}:.,/])\#(group(#"\d{1,2}"#))(?:\#(unit)|\#(colon))?\#(group(vietnamesePartAfterHour))?"#
    let lead = #"(?:\#(vietnameseWord("lúc"))\s+)?"#
    // "Tới" is read only with its mark: "toi" is also "tối" ("7 giờ tối 9 giờ").
    let words = "\(vietnameseAlternation(["đến", "cho đến", "và"]))|\(vietnameseAlternation(["tới", "cho tới"], strict: true))"
    let joiner = #"(?:\s+\#(group(words))\s+|\s*\#(group("[-–—]"))\s*)"#
    return
      #"(?:\#(group(vietnameseAlternation(["từ", "giữa"])))\s+)?\#(lead)\#(side)\#(joiner)\#(lead)\#(side)"#
  }

  /// "từ 3 giờ đến 5 giờ chiều", "từ 3 đến 5 giờ chiều", "3-5 giờ chiều", "3h-5h chiều",
  /// "9 giờ sáng đến 5 giờ chiều", "từ 14h đến 16h30", "từ 14:00 đến 16:00", "giữa 3 giờ
  /// và 5 giờ chiều", "tối nay 7-9 giờ". Groups: 1 the opener ("từ", "giữa"); the
  /// first side, 2 hour, 3 unit, 4 "rưỡi", 5 minutes after the unit, 6 colon or dot,
  /// 7 minutes after it, 8 part of the day; 9 the word between the sides, 10 a dash;
  /// the second side, 11 to 17 as the first side's 2 to 8 in the same order, 17 its
  /// part of the day.
  static var vietnameseTimeRangePattern: String {
    #"\#(vietnameseStart)\#(vietnameseTimeRangeBody(capturing: true))\#(vietnameseTimeEnd)"#
  }

  /// One side of a range: the groups from `first`, its hour, to `first + 6`, its
  /// part of the day.
  private struct VietnameseRangeSide {
    var hour: Int
    var minute: Int
    var hasUnit: Bool
    var hasSeparator: Bool
    var part: String?
    var hasLeadingZero: Bool
  }

  private static func vietnameseRangeSide(_ match: Match, first: Int) -> VietnameseRangeSide? {
    guard let hourText = match.group(first), let hour = number(hourText), (0...24).contains(hour) else { return nil }
    var minute = 0
    if match.group(first + 2) != nil {
      minute = 30
    } else if let text = match.group(first + 3) ?? match.group(first + 5) {
      guard let value = number(text), (0...59).contains(value) else { return nil }
      minute = value
    }
    return VietnameseRangeSide(
      hour: hour, minute: minute, hasUnit: match.group(first + 1) != nil, hasSeparator: match.group(first + 4) != nil,
      part: match.group(first + 6), hasLeadingZero: startsWithZero(hourText))
  }

  /// The time one side of a range names: its own part of the day, else its hour
  /// as a bare time, which the range reads against the other side.
  private static func vietnameseRangeTime(_ side: VietnameseRangeSide, match: Match) -> ClockTime? {
    if side.hour == 24 { return side.minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    if let text = side.part {
      guard let part = vietnamesePartOfDay(text) else { return nil }
      return vietnameseTimeWithPart(hour: side.hour, minute: side.minute, part: part)
    }
    return vietnameseBareTime(hour: side.hour, minute: side.minute, hasLeadingZero: side.hasLeadingZero, match: match)
  }

  /// Whether the dash of the range touches both sides ("3-5 giờ"), not a spaced one.
  private static func vietnameseDashIsTight(_ match: Match, group: Int) -> Bool {
    let range = match.result.range(at: group)
    guard range.location != NSNotFound, let bounds = Range(range, in: match.source) else { return false }
    let source = match.source
    guard bounds.lowerBound > source.startIndex, bounds.upperBound < source.endIndex else { return false }
    return !source[source.index(before: bounds.lowerBound)].isWhitespace && !source[bounds.upperBound].isWhitespace
  }

  static func vietnameseTimeRange(_ match: Match) -> ClockTime? {
    let opener = match.group(1).map(vietnameseKey)
    let word = match.group(9).map(vietnameseKey)
    // "Và" joins the sides after "giữa" only, which takes no dash and no other joiner.
    if (word == "va") != (opener == "giua") { return nil }
    guard let start = vietnameseRangeSide(match, first: 2), let end = vietnameseRangeSide(match, first: 11),
      !vietnameseFollowsBoundWord(match)
    else { return nil }
    let hasUnit = start.hasUnit || end.hasUnit
    let hasPart = start.part != nil || end.part != nil
    let hasSeparator = start.hasSeparator || end.hasSeparator
    // Two bare hours are as often numbered items, and two colon times are English's.
    guard hasUnit || hasPart || (opener != nil && hasSeparator) else { return nil }
    // A start with no unit, part, or minutes and a spaced dash ("Bước 3 - 5 giờ chiều") names a number of the title.
    if opener == nil, word == nil, !start.hasUnit, start.part == nil, !start.hasSeparator,
      !vietnameseDashIsTight(match, group: 10)
    {
      return nil
    }
    // SA and CH on a side with no minutes ("5 CH") need the colon or a unit.
    for side in [start, end] {
      if let kind = side.part.flatMap(vietnamesePartOfDay), kind == .am || kind == .pm, !(side.hasSeparator || side.hasUnit) {
        return nil
      }
    }
    guard let from = vietnameseRangeTime(start, match: match), let to = vietnameseRangeTime(end, match: match) else {
      return nil
    }
    return timeRange(from: from, to: to)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time as a pattern without groups: "5 giờ chiều", "5h", "17h30", "3 giờ
  /// kém 15", "17:30", "5pm", and "nửa đêm".
  private static var vietnameseClockShape: String {
    let hour = #"(?:\d{1,2}|\#(vietnameseHourWords))"#
    let minutes = #"(?:\d{1,2}|\#(vietnameseNumberWords))"#
    let minuteUnit = #"(?:\s*\#(vietnameseMinuteUnit))?"#
    let unit =
      #"\#(hour)\s*(?:\#(vietnameseWord("giờ"))|h)(?:\s+\#(vietnameseWord("rưỡi"))|\s+\#(vietnameseWord("kém"))\s+\#(minutes)\#(minuteUnit)|\#(vietnameseBeforeMinutes)\d{1,2}\#(minuteUnit))?"#
    let colon = #"\d{1,2}:\d{2}"#
    let meridiem = #"\d{1,2}(?:[.:]\d{2})?\s*[ap]\.?m\.?"#
    let midnight = vietnameseAlternation(["nửa đêm", "giữa đêm"])
    return #"(?:(?:\#(unit)|\#(colon))(?:\#(vietnamesePartAfterHour))?|\#(meridiem)|\#(midnight))"#
  }

  /// The words that make a clock time a bound or a deadline, as a pattern without
  /// groups, with the colon or the space and the "lúc" after them. "Tới" is read
  /// only with its mark: "toi" is also "tối".
  private static let vietnameseClockBound: String = {
    let words = vietnameseAlternation([
      "chậm nhất là", "chậm nhất", "muộn nhất là", "muộn nhất", "trễ nhất là", "trễ nhất", "sớm nhất",
      "không muộn hơn", "không trễ hơn", "không chậm hơn", "hạn chót", "hạn cuối cùng", "hạn cuối", "hạn nộp", "hạn",
      "tối đa", "tối thiểu", "trước", "đến", "hết", "cho đến", "cho tới",
    ])
    // "Sau" typed without marks is also "Sáu" of "thứ Sáu", and "tuần sau" and "tuần tới" are next week, so
    // "sau" and "tới" are a bound only where no such word stands before them.
    let after = #"(?<!\#(vietnameseNounBeforeNext)\s{1,3})(?:sau|\#(vietnameseWord("tới", strict: true)))"#
    return
      #"(?:\#(words)|\#(after)|deadline)(?:\s*:\s*|\s+)(?:(?:\#(vietnameseWord("vào"))\s+)?\#(vietnameseWord("lúc"))\s+)?"#
  }()

  /// A clock time written as a bound ("trước 5 giờ chiều", "đến 17h", "chậm nhất 5
  /// giờ", "sau 18:00", "trước nửa đêm", "deadline 5pm"), which names no start time.
  /// Group 1 is the bound, or nil for a range ("từ 14h đến 17h30"), which the range
  /// rule reads and this rule only steps over, so the "đến 17h30" inside it is not
  /// taken for a bound.
  static var vietnameseDeadlineClockPattern: String {
    #"\#(vietnameseStart)(?:\#(vietnameseTimeRangeBody(capturing: false))|(\#(vietnameseClockBound)\#(vietnameseClockShape)))\#(vietnameseTimeEnd)"#
  }

  /// The clock after a deadline day ("trước thứ Sáu 5 giờ chiều", "hạn ngày mai 9
  /// giờ"), which is a deadline's clock and stays in the title with the rest of the
  /// line once the day is read as the due day.
  static var vietnameseDueClockPattern: String {
    #"\#(vietnameseStart)(?:(?:\#(vietnameseWord("vào"))\s+)?\#(vietnameseWord("lúc"))\s+)?\#(vietnameseClockShape)\#(vietnameseTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a word
  /// that introduces a due day, the day, with a comma or a space before the clock.
  private static var vietnameseAfterDueDayPattern: String {
    #"(?:^|\s)\#(vietnameseDueLead)(?:\#(vietnameseDueDay))\s*,?\s*$"#
  }

  /// The text before a clock that ends a range of days or of weekdays ("từ 3 đến 5
  /// tháng 10 lúc 9 giờ", "từ thứ Hai đến thứ Tư 9 giờ"), whose "đến" and day are no
  /// deadline.
  private static var vietnameseAfterRangePattern: String {
    #"(?:\#(vietnameseDateRangePattern)|\#(vietnameseWeekdayRangePattern))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a deadline word and a day ("trước
  /// thứ Sáu", "hạn ngày mai"). The "đến" of a range of days is no deadline word,
  /// so the clock after "từ thứ Hai đến thứ Tư" is the range's time.
  static func vietnameseIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = vietnameseTextBefore(match)
    let whole = NSRange(before.startIndex..., in: before)
    // The cheap test first: most clock times follow no deadline word.
    guard let dueDay = LorvexCapturePatterns.regex(vietnameseAfterDueDayPattern),
      dueDay.firstMatch(in: before, range: whole) != nil
    else { return false }
    if let range = LorvexCapturePatterns.regex(vietnameseAfterRangePattern),
      range.firstMatch(in: before, range: whole) != nil
    {
      return false
    }
    return true
  }
}
