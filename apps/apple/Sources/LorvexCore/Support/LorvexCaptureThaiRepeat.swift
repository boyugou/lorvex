import Foundation

extension LorvexCaptureVocabulary {
  // The Thai repeat rules: a day of the month, working days, weekends, a span of
  // weekdays, alternating units, counted intervals, repeated weekdays, and the
  // cadence phrases. The vocabulary's other words are in ``thai``.

  /// The repeat rules in the order they are tried: a day of the month, the
  /// working days, and the weekend before the rules for every day and every
  /// month, which would leave "ทุกวันทำงาน" or the day's number in the title; a
  /// span of weekdays, the alternating units, and the counted intervals before
  /// the weekday rule, so "ทุกวันจันทร์ถึงวันพุธ" and "ทุก 2 สัปดาห์วันศุกร์" are
  /// read whole; the weekday rule before "ทุกสัปดาห์", so "ทุกสัปดาห์วันศุกร์" is
  /// read whole.
  static let thaiRepeatRules: [Rule<Repeat>] = [
    thaiRule(thaiMonthDayRepeatPattern, read: thaiMonthDayRepeat),
    thaiRule(thaiWorkdaysPattern) { _ in workdays },
    thaiRule(thaiWeekendRepeatPattern) { _ in weekly(every: nil, on: [6, 0]) },
    thaiRule(thaiWeekdaySpanPattern, read: thaiWeekdaySpan),
    thaiRule(thaiAlternatingPattern, read: thaiAlternating),
    thaiRule(thaiIntervalRepeatPattern, read: thaiIntervalRepeat),
    thaiRule(thaiPeriodRepeatPattern, read: thaiPeriodRepeat),
    thaiRule(thaiWeekdayRepeatPattern, read: thaiWeekdayRepeat),
    thaiRule(thaiPerPeriodPattern, read: thaiPerPeriod),
    thaiRule(thaiEveryUnitPattern, read: thaiEveryUnit),
  ]

  // MARK: - Words shared by the rules

  /// "ทุก" and "ทุกๆ", every, which does not end "บรรทุก" (to load) and which
  /// "ทุกข์" (suffering) never matches, since a unit or a weekday follows it.
  private static let thaiEvery = #"(?<!บรร)ทุก(?:ๆ)?\s*"#

  /// The units of a repeat: day, week, month, year.
  private static let thaiUnits = #"วัน|สัปดาห์|อาทิตย์|เดือน|ปี"#

  /// The words that make "วัน" after "ทุก" or a count something other than the
  /// unit: "วันหยุด" (holiday), "วันละ" (per day), "วันเกิด" (birthday), a
  /// weekday, and the other words that follow it.
  private static var thaiNotAfterDayUnit: String {
    #"(?!ที่|นี้|หยุด|เกิด|ละ|เว้น|ทำงาน|ทำการ|ธรรมดา|พิเศษ|แรก|สุดท้าย|ว่าง|ลา|\#(thaiWeekdayNames)|สุดสัปดาห์)"#
  }

  /// The separator of a list of weekdays: a comma, "และ", "กับ", a slash, "&",
  /// a space, or nothing between names written together.
  private static let thaiListSeparator = #"\s*(?:(?:,|และ|กับ|/|&)\s*)?"#

  /// The first name of a list of weekdays: with "วัน", or without it for any
  /// day but Sunday, since "ทุกอาทิตย์" is every week.
  private static var thaiRepeatFirstName: String {
    #"(?:วัน(?:\#(thaiWeekdayNames))|(?:\#(thaiWeekdayNamesExceptSunday)))\#(thaiEnd)"#
  }

  /// A later name of a list: any weekday, with or without "วัน".
  private static var thaiRepeatLaterName: String {
    #"(?:วัน)?(?:\#(thaiWeekdayNames))\#(thaiEnd)"#
  }

  /// The weekday names of a list, as a pattern without groups: "วันจันทร์", "วันจันทร์และวันพุธ",
  /// "จันทร์ พุธ ศุกร์", "วันเสาร์อาทิตย์".
  private static var thaiNamesList: String {
    #"\#(thaiRepeatFirstName)(?:\#(thaiListSeparator)\#(thaiRepeatLaterName)){0,6}"#
  }

  /// The weekdays a matched list names, 0 = Sunday.
  private static func thaiRepeatWeekdays(_ list: String) -> [Int] {
    guard let regex = LorvexCapturePatterns.regex(thaiSaraAm(#"(?:วัน)?(\#(thaiWeekdayNames))"#)) else { return [] }
    return regex.matches(in: list, range: NSRange(list.startIndex..., in: list)).compactMap { result in
      Range(result.range(at: 1), in: list).flatMap { thaiWeekdayIndex(String(list[$0])) }
    }
  }

  /// The repeat every `every` (nil for each) of the unit a word names.
  /// A whole number of weeks counted in days is a weekly repeat ("ทุก 14 วัน").
  private static func thaiRepeat(unit: String, every: Int?) -> Repeat? {
    let interval = every == 1 ? nil : every
    switch unit {
    case "วัน":
      if let count = interval, count % 7 == 0 { return weekly(every: count / 7 == 1 ? nil : count / 7, on: []) }
      return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: interval))
    case "สัปดาห์", "อาทิตย์":
      return weekly(every: interval, on: [])
    case "เดือน":
      return monthly(every: interval, on: nil)
    case "ปี":
      return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: interval))
    default:
      return nil
    }
  }

  // MARK: - Day of the month

  /// "ทุกวันที่ 15", "ทุกเดือนวันที่ 15", "ทุกวันที่ 15 ของเดือน", "วันที่ 15 ของทุกเดือน":
  /// a day of every month. The number is a day only where no time, fraction,
  /// or month name follows it ("ทุกวันที่ 15:30" is a time). Groups: 1 the day
  /// after "ทุก", 2 the day before "ของเดือน".
  private static var thaiMonthDayRepeatPattern: String {
    let after = #"\#(thaiEvery)(?:เดือน\s*)?(?:ใน)?วันที่\s*(\d{1,2})(?![\p{N}:./-])(?:\s*ของ(?:ทุก)?เดือน)?"#
    let before = #"(?:ใน)?วันที่\s*(\d{1,2})(?![\p{N}:./-])\s*ของ(?:ทุก)?เดือน"#
    return #"\#(thaiStart)(?:\#(after)|\#(before))\#(thaiEnd)"#
  }

  private static func thaiMonthDayRepeat(_ match: Match) -> Repeat? {
    guard let day = (match.group(1) ?? match.group(2)).flatMap(number) else { return nil }
    return monthly(every: nil, on: day)
  }

  // MARK: - Working days and weekends

  /// "ทุกวันทำงาน", "ทุกวันทำการ": every working day. A span of Monday to Friday
  /// after "ทุก" is read by the span rule.
  private static let thaiWorkdaysPattern = #"\#(thaiStart)\#(thaiEvery)วัน(?:ทำงาน|ทำการ)\#(thaiEnd)"#

  /// "ทุกสุดสัปดาห์": every Saturday and Sunday. "สุดสัปดาห์" alone names the coming
  /// weekend, a day.
  private static let thaiWeekendRepeatPattern = #"\#(thaiStart)\#(thaiEvery)(?:วัน)?สุดสัปดาห์\#(thaiEnd)"#

  // MARK: - Span of weekdays

  /// "ทุกวันจันทร์ถึงวันศุกร์", "ทุกจันทร์-ศุกร์", "ทุกวันศุกร์ถึงวันจันทร์": every day
  /// from the first weekday through the last. Groups: 1 the first weekday, 2 the
  /// last.
  private static var thaiWeekdaySpanPattern: String {
    let name = thaiWeekdayNames
    return
      #"\#(thaiStart)\#(thaiEvery)(?:วัน)?(\#(name))\s*(?:[-–—]\s*|(?:จนถึง|ถึง|จน)\s*)(?:วัน)?(\#(name))\#(thaiEnd)"#
  }

  /// Monday to Friday is the working week; any other span repeats on each of its
  /// days, going on through Sunday when it wraps ("ศุกร์ถึงจันทร์" is Friday,
  /// Saturday, Sunday, and Monday).
  private static func thaiWeekdaySpan(_ match: Match) -> Repeat? {
    guard let firstText = match.group(1), let lastText = match.group(2),
      let first = thaiWeekdayIndex(firstText), let last = thaiWeekdayIndex(lastText), first != last
    else { return nil }
    if first == 1, last == 5 { return workdays }
    var days = [first]
    var day = first
    while day != last {
      day = (day + 1) % 7
      days.append(day)
    }
    return weekly(every: nil, on: days)
  }

  // MARK: - Alternating units and counted intervals

  /// "วันเว้นวัน", "สัปดาห์เว้นสัปดาห์", "เดือนเว้นเดือน", "ปีเว้นปี": every other
  /// day, week, month, or year. Groups: 1 and 2 the units around "เว้น".
  private static var thaiAlternatingPattern: String {
    #"\#(thaiStart)(?<!ตะ)(\#(thaiUnits))\s*เว้น\s*(\#(thaiUnits))\#(thaiEnd)"#
  }

  private static func thaiAlternating(_ match: Match) -> Repeat? {
    guard let first = match.group(1), let second = match.group(2) else { return nil }
    let weeks: Set<String> = ["สัปดาห์", "อาทิตย์"]
    guard first == second || (weeks.contains(first) && weeks.contains(second)) else { return nil }
    return thaiRepeat(unit: first, every: 2)
  }

  /// "ทุก 2 วัน", "ทุก 3 สัปดาห์", "ทุกสองเดือน", "ทุก 2 ปี", each maybe before the
  /// weekdays of a weekly repeat ("ทุก 2 สัปดาห์วันศุกร์"). Groups: 1 the count, 2
  /// the unit, 3 the weekday names after the interval.
  private static var thaiIntervalRepeatPattern: String {
    let count = #"(\d{1,3}|\#(thaiNumberWords))"#
    let tail = #"(?:\s*(\#(thaiNamesList)))?"#
    return
      #"\#(thaiStart)\#(thaiEvery)\#(count)\s*(\#(thaiUnits))(?!ที่|นี้|หยุด|เกิด|ละ|เว้น|ทำงาน|ทำการ|ว่าง|ลา)\#(thaiEnd)\#(tail)"#
  }

  private static func thaiIntervalRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1), let unit = match.group(2), let count = thaiCount(countText),
      (1...99).contains(count), let base = thaiRepeat(unit: unit, every: count)
    else { return nil }
    let weekdays = thaiRepeatWeekdays(match.group(3) ?? "")
    guard !weekdays.isEmpty else { return base }
    return base.rule.freq == .weekly ? weekly(every: base.rule.interval, on: weekdays) : nil
  }

  /// "ทุกไตรมาส" (every quarter) and "ทุกครึ่งปี" (every half year): every three
  /// and every six months.
  private static let thaiPeriodRepeatPattern = #"\#(thaiStart)\#(thaiEvery)(ไตรมาส|ครึ่งปี)\#(thaiEnd)"#

  private static func thaiPeriodRepeat(_ match: Match) -> Repeat? {
    guard let word = match.group(1) else { return nil }
    return monthly(every: word == "ไตรมาส" ? 3 : 6, on: nil)
  }

  // MARK: - Repeated weekdays

  /// "ทุกวันจันทร์", "ทุกจันทร์", "ทุกวันจันทร์และวันพุธ", "ทุกวันจันทร์ พุธ ศุกร์",
  /// "ทุกสัปดาห์วันศุกร์", "ทุกอาทิตย์วันพุธ", "ทุกเสาร์อาทิตย์". Group 1: the
  /// weekday names.
  private static var thaiWeekdayRepeatPattern: String {
    #"\#(thaiStart)\#(thaiEvery)(?:(?:สัปดาห์|อาทิตย์)\s*)?(\#(thaiNamesList))"#
  }

  private static func thaiWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = thaiRepeatWeekdays(match.group(1) ?? "")
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  // MARK: - Cadence phrases

  /// "วันละครั้ง", "สัปดาห์ละครั้ง", "เดือนละครั้ง", "ปีละครั้ง": once a day, week,
  /// month, or year. Several times in a period ("สัปดาห์ละ 2 ครั้ง") count
  /// times, which no repeat says, so they stay. Group 1: the unit.
  private static var thaiPerPeriodPattern: String {
    #"\#(thaiStart)(?<!ตะ)(\#(thaiUnits))\s*ละ\s*(?:(?:1|หนึ่ง|๑)\s*)?ครั้ง\#(thaiEnd)"#
  }

  private static func thaiPerPeriod(_ match: Match) -> Repeat? {
    match.group(1).flatMap { thaiRepeat(unit: $0, every: nil) }
  }

  /// "ทุกวัน", "ทุกสัปดาห์", "ทุกอาทิตย์", "ทุกเดือน", "ทุกปี", "ทุกเช้า", "ทุกเย็น",
  /// "ทุกคืน". "ทุกวันนี้" (nowadays), "ทุกวันหยุด" (every holiday), and the
  /// other words that begin with these are no cadence. Groups: 1 a day, 2 a
  /// week, 3 a month, 4 a year, 5 a part of the day.
  private static var thaiEveryUnitPattern: String {
    let weeks = #"(สัปดาห์|อาทิตย์)(?!ที่|นี้|หน้า|ละ|เว้น|ก่อน|แรก|สุดท้าย)"#
    let months = #"(เดือน)(?!ที่|นี้|ละ|เว้น|ก่อน|แรก|สุดท้าย)"#
    let years = #"(ปี)(?!ที่|นี้|ละ|เว้น|ก่อน|ใหม่)"#
    let parts = #"(เช้า|บ่าย|เย็น|ค่ำ|คืน|ดึก)\#(thaiPartEnd)"#
    return
      #"\#(thaiStart)\#(thaiEvery)(?:(วัน)\#(thaiNotAfterDayUnit)|\#(weeks)|\#(months)|\#(years)|\#(parts))\#(thaiEnd)"#
  }

  private static func thaiEveryUnit(_ match: Match) -> Repeat? {
    guard let unit = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) else {
      return Repeat(rule: TaskRecurrenceRule(freq: .daily))
    }
    return thaiRepeat(unit: unit, every: nil)
  }
}
