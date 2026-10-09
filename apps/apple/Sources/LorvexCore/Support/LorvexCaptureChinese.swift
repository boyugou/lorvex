import Foundation

extension LorvexCaptureVocabulary {
  /// Chinese, in Simplified or Traditional characters. Words need no
  /// boundary, since Chinese is written without spaces ("明天开会" plans "开会"
  /// for tomorrow). The patterns are written in Simplified characters and read
  /// the line through ``simplifiedForMatching(_:)``, so "後天", "下週三",
  /// "30分鐘", "兩個鐘頭", and "從5月3日到5月5日" are recognized as well.
  ///
  /// - Day: 今天, 今晚, 明天, 明晚, 后天, 大后天, 周三 / 星期三 / 礼拜三 (with
  ///   这 / 本 / 下), 下周, 下下周, 周末, 3天后; a date: 10月5日, 10月5号,
  ///   2026年10月5日, 5号. A date without a year that has passed this year
  ///   means next year's; "5号" means the coming 5th, unless a thing numbered
  ///   that way follows it (5号楼, 2号线, 3号会议室, 5号电池), which stays in
  ///   the title. A weekday alone means the next such day, a full week ahead
  ///   when it names today; with 这 or 本 it is this week's, with 下 next
  ///   week's, weeks starting on Monday. 今晚 and 明晚 are evenings, so
  ///   "今晚8点" is 8 PM.
  /// - Date range: 5月3日到5日, 5月3日至5日, 5月3日-5日, 5月3日到5月5日,
  ///   5月3号到5号, 5月30日到6月2日, 2026年12月30日到2027年1月2日, each maybe after
  ///   从 or 自, with 到, 至, a dash, or a tilde between the sides. The first
  ///   day is the planned day and the last the due day, so another day phrase
  ///   stays in the title. A day alone after the first date ("5日") takes its
  ///   month; the end must be after the start ("5月5日到3日" stays in the
  ///   title whole), and an end in an earlier month falls in the next year. A
  ///   range of days of the month alone is read only in 号: "3号到5号" counts,
  ///   "3日到5日" does not, since a lone 日 is not a date here. A range may
  ///   end in 前 or 之前 ("5月3日到5日前").
  /// - Repeat: 每天, 每日, 每隔一天, 每3天, 每周, 每两周, 每周一, 每周一三五,
  ///   每个工作日, 每月, 每月5号, 每年.
  /// - Due: a day before 前 or 之前 ("周五前").
  /// - Time: 下午3点, 晚上8点半, 三点一刻, 9点20分, 下午3:30, 15：30. A time with no
  ///   part of the day from 1 to 6 o'clock is the afternoon. The night of a
  ///   day (晚上, 半夜, 午夜) runs past midnight: 6 to 11 o'clock is that
  ///   evening, while 12 o'clock is the midnight that ends the day and 1 to 5
  ///   o'clock the small hours after it, both on the next day. "第三点" and
  ///   "一点" alone ("a little") are not times. A range (下午3点到5点, 3点-4点半,
  ///   下午3-5点, 晚上11点到1点) also sets the length.
  /// - Length: 30分钟, 2小时, 2个小时, 2个钟头, 半小时, 半个钟头, 一个半小时.
  /// - Priority: 紧急, not after 不.
  static let chinese = LorvexCaptureVocabulary(
    readingForm: simplifiedForMatching,
    priority: [Rule(pattern: #"(?<!不)紧急"#) { _ in .p1 }],
    dateRange: [Rule(pattern: chineseDateRangePattern, read: chineseDateRange)],
    length: [Rule(pattern: chineseLengthPattern, read: chineseLength)],
    time: [
      Rule(pattern: chineseRangePattern, read: chineseRange),
      Rule(pattern: chineseTimePattern, read: chineseTime),
    ],
    repeats: [
      Rule(pattern: #"每个?工作日"#) { _ in workdays },
      Rule(
        pattern:
          #"每(隔)?(\d{1,2}|[一两二三四五六七八九十]{1,2})?个?(?:周|星期|礼拜)([一二三四五六日天](?:[、,，和]?[一二三四五六日天])*)?"#,
        read: chineseWeeklyRepeat),
      Rule(pattern: #"每(隔)?(\d{1,2}|[一两二三四五六七八九十]{1,2})?个?月(?:(\d{1,2})[日号])?"#, read: chineseMonthlyRepeat),
      Rule(pattern: #"每(隔)?(\d{1,2}|[一两二三四五六七八九十]{1,2})?个?(天|日|年)"#, read: chineseDailyRepeat),
    ],
    due: [Rule(pattern: #"(\#(chineseDayPattern))(?:之前|前)"#, read: chineseDue)],
    when: [Rule(pattern: #"(\#(chineseDayPattern))"#, read: chineseWhen)])

  // MARK: - Traditional characters

  /// The Traditional characters the Chinese vocabulary uses, each with its
  /// Simplified form. Both sides of every pair are one UTF-16 unit.
  private static let simplifiedForms: [Character: Character] = [
    "後": "后", "週": "周", "這": "这", "禮": "礼", "點": "点", "鐘": "钟",
    "時": "时", "個": "个", "兩": "两", "緊": "紧", "號": "号", "頭": "头", "從": "从",
    "樓": "楼", "棟": "栋", "館": "馆", "廳": "厅", "櫃": "柜", "會": "会", "議": "议",
    "間": "间", "車": "车", "廂": "厢", "臺": "台", "電": "电", "線": "线", "門": "门",
    "診": "诊", "長": "长",
  ]

  /// `text` with each Traditional character of ``simplifiedForms`` replaced by
  /// its Simplified form, so the patterns, written in Simplified characters,
  /// read both scripts. Every replacement keeps the UTF-16 length, so a match
  /// range in the result is the same range in `text`.
  static func simplifiedForMatching(_ text: String) -> String {
    String(text.map { simplifiedForms[$0] ?? $0 })
  }

  // MARK: - Length

  /// "30分钟", "2个小时", "2个钟头", or a length in words. Groups: 1 an amount,
  /// 2 its unit; 3 the words.
  private static let chineseLengthPattern =
    #"(?<![\p{Latin}\p{N}.])(\d+(?:\.\d+)?)\s*(分钟|个?小时|个?钟头)(?![\p{Latin}\p{N}])|(一个半小时|一个半钟头|一个小时|一个钟头|一小时|两个小时|两个钟头|两小时|半个?小时|半个钟头)"#

  private static func chineseLength(_ match: Match) -> Int? {
    if let amount = match.group(1).flatMap(boundedDecimal), let unit = match.group(2) {
      let isHours = unit.hasSuffix("小时") || unit.hasSuffix("钟头")
      return taskLength(minutes: Int((isHours ? amount * 60 : amount).rounded()))
    }
    switch match.group(3) {
    case "一个半小时", "一个半钟头": return 90
    case "一个小时", "一个钟头", "一小时": return 60
    case "两个小时", "两个钟头", "两小时": return 120
    case .some: return 30
    case nil: return nil
    }
  }

  // MARK: - Time

  /// 下午3点, 晚上8点半, 三点一刻, 9点20分, 下午3:30, 15：30. Groups: 1 part of day,
  /// 2 hour, 3 half, 4 quarter, 5 minute; 6, 7, and 8 the part of day, hour,
  /// and minute of a colon time; 10 and 11 the hour and minute of a time with
  /// a full-width colon and no part of day. "第三点" and "一点" alone ("a
  /// little") are not times.
  private static let chineseTimePattern =
    #"\#(chineseDayPart)?(?<![第\d一二两三四五六七八九十])(\d{1,2}|[一二两三四五六七八九十]{1,3})点钟?(?:(半)|(一刻|三刻)|(\d{1,2}|[零一二三四五六七八九十]{1,3})分?)?|\#(chineseDayPart)(?<![\d:：])(\d{1,2})[:：](\d{2})(?![\d:：])|(?<![\d:：])()(\d{1,2})[：](\d{2})(?![\d:：])"#

  private static let chineseDayPartWords = "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|半夜|午夜"
  private static let chineseDayPart = "(\(chineseDayPartWords))"

  private static func chineseTime(_ match: Match) -> ClockTime? {
    chineseClock(match, readsBareOne: false)
  }

  /// The time a match of ``chineseTimePattern`` names. "一点" with no part of
  /// the day or minutes is one o'clock only when `readsBareOne` is true, as
  /// on a side of a range ("一点到两点"); alone it means "a little".
  private static func chineseClock(_ match: Match, readsBareOne: Bool) -> ClockTime? {
    let hourText: String
    var hour: Int
    var minute = 0
    let part: String?
    if let colonHour = match.group(7) ?? match.group(10), let value = number(colonHour),
      let minuteValue = (match.group(8) ?? match.group(11)).flatMap(number)
    {
      hourText = colonHour
      hour = value
      minute = minuteValue
      part = match.group(6)
    } else {
      guard let text = match.group(2), let value = number(text) ?? hanNumber(text) else { return nil }
      hourText = text
      hour = value
      part = match.group(1)
      if match.group(3) != nil {
        minute = 30
      } else if let quarter = match.group(4) {
        minute = quarter == "一刻" ? 15 : 45
      } else if let text = match.group(5) {
        guard let value = number(text) ?? hanNumber(text) else { return nil }
        minute = value
      } else if part == nil, text == "一", !readsBareOne {
        return nil
      }
    }
    guard (0...24).contains(hour), (0...59).contains(minute) else { return nil }
    guard let part, !part.isEmpty else {
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    switch part {
    case "凌晨", "早上", "早晨", "上午": if hour == 12 { hour = 0 }
    case "中午": if hour < 11 { hour += 12 }
    case "晚上", "半夜", "午夜": return nightTime(hour: hour, minute: minute)
    default: if hour < 12 { hour += 12 }
    }
    guard hour < 24 else { return nil }
    return ClockTime(minutes: hour * 60 + minute)
  }

  // MARK: - Time range

  /// 下午3点到5点, 3点-4点半, 下午3-5点, 15:00～16:30: a start, then 到, 至, a dash,
  /// or a tilde, then an end written with 点 or a colon. Groups: 1 the start,
  /// 2 the end.
  private static var chineseRangePattern: String {
    let hour = "(?<![第\\d一二两三四五六七八九十])(?:\\d{1,2}|[一二两三四五六七八九十]{1,3})"
    let clock =
      "\(hour)点钟?(?:半|一刻|三刻|(?:\\d{1,2}|[零一二三四五六七八九十]{1,3})分?)?|(?<![\\d:：])\\d{1,2}[:：]\\d{2}(?![\\d:：])"
    let part = "(?:\(chineseDayPartWords))"
    return "(\(part)?(?:\(clock)|\(hour)))\\s*(?:到|至|-|–|—|~|～)\\s*(\(part)?(?:\(clock)))\(noMeridiemAfter)"
  }

  private static func chineseRange(_ match: Match) -> ClockTime? {
    guard let start = match.group(1).flatMap({ chineseRangeSideTime($0, in: match) }),
      let end = match.group(2).flatMap({ chineseRangeSideTime($0, in: match) })
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a range: a clock time ("下午3点", "5点半", "15:30"), or a
  /// start hour written without 点 ("下午3" of "下午3-5点").
  private static func chineseRangeSideTime(_ text: String, in match: Match) -> ClockTime? {
    let read = { (side: Match) in chineseClock(side, readsBareOne: true) }
    return wholeTime(text, pattern: chineseTimePattern, in: match, read: read)
      ?? wholeTime(text + "点", pattern: chineseTimePattern, in: match, read: read)
      ?? colonTime(text)
  }

  // MARK: - Date range

  /// 5月3日到5日, 5月3日至5月5日, 5月3日-5日, 从5月3日到5月5日, 3号到5号: a date, then 到,
  /// 至, a dash, or a tilde, then a date or a day alone ("5日"), maybe after 从
  /// or 自 and before 前 or 之前. Days of the month alone are read only in 号,
  /// as the day rules read them. Groups: 1 the start and 2 the end of a
  /// range of dates; 3 the start and 4 the end of a range of days of the month.
  private static var chineseDateRangePattern: String {
    let date = #"(?:\d{4}年)?\d{1,2}月\d{1,2}[日号]"#
    let day = #"(?<![\d月])\d{1,2}(?:日|号\#(chineseNoNumberedThingAfter))"#
    let lone = #"(?<![\d月年])\d{1,2}号"#
    let connector = #"\s*(?:到|至|-|–|—|~|～|〜)\s*"#
    return #"(?:[从自]\s*)?(?:(\#(date))\#(connector)(\#(date)|\#(day))|(\#(lone))\#(connector)(\#(day)))(?:之前|前)?"#
  }

  private static func chineseDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1) ?? match.group(3), let endText = match.group(2) ?? match.group(4),
      let start = chineseRangeDate(startText), let end = chineseRangeDate(endText)
    else { return nil }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5月3日", "5月3号"), or a day alone ("5日",
  /// "3号"), which has no month.
  private static func chineseRangeDate(_ text: String) -> ExplicitDate? {
    if let date = chineseDate(text) { return date }
    guard let match = text.wholeMatch(of: /(\d{1,2})[日号]/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  // MARK: - Repeat

  /// The interval a repeat names: 每两周 is 2, 每隔一周 is 2 (one skipped), 每周
  /// is nil (every one); nil when the count is unreadable or over 99.
  /// Groups: 1 隔, 2 count.
  private static func chineseInterval(_ match: Match) -> Int?? {
    var count = 1
    if let text = match.group(2) {
      guard let value = number(text) ?? hanNumber(text), value > 0 else { return nil }
      count = value
    }
    if match.group(1) != nil { count += 1 }
    guard count <= 99 else { return nil }
    return .some(count == 1 ? nil : count)
  }

  /// 每周, 每两周, 每周一三五. Group 3: the weekday characters.
  private static func chineseWeeklyRepeat(_ match: Match) -> Repeat? {
    guard let interval = chineseInterval(match) else { return nil }
    return weekly(every: interval, on: (match.group(3) ?? "").compactMap(chineseWeekday))
  }

  /// 每月, 每两个月, 每月5号. Group 3: the day of the month.
  private static func chineseMonthlyRepeat(_ match: Match) -> Repeat? {
    guard let interval = chineseInterval(match) else { return nil }
    return monthly(every: interval, on: match.group(3).flatMap(number))
  }

  /// 每天, 每日, 每3天, 每年. Group 3: the unit.
  private static func chineseDailyRepeat(_ match: Match) -> Repeat? {
    guard let interval = chineseInterval(match), let unit = match.group(3) else { return nil }
    return Repeat(rule: TaskRecurrenceRule(freq: unit == "年" ? .yearly : .daily, interval: interval))
  }

  // MARK: - Days

  /// The days. Weekday characters: 一 … 六, and 日 / 天 for Sunday.
  private static let chineseDayPattern =
    #"(?:\d{4}年)?\d{1,2}月\d{1,2}[日号]|\d{1,2}月\d{1,2}(?![\d点:：])|(?<!\d)\d{1,2}号\#(chineseNoNumberedThingAfter)|大后天|后天|今天|今晚|明天|明晚|下下周|(?<!每)(?:这|本|下)?(?:周|星期|礼拜)[一二三四五六日天]|下周|周末|\d{1,3}天后"#

  /// What may not follow a number written with 号 for the number to be a day
  /// of the month: a thing numbered that way, as in 5号楼 (building 5), 2号线
  /// (line 2), 3号会议室 (room 3), or 5号电池 (AA batteries). 线上 and 线下
  /// (online, offline), 门诊 (a clinic), and 院长 (a dean) may follow a date.
  private static let chineseNoNumberedThingAfter =
    #"(?!楼|栋|馆|厅|柜|床|会议室|教室|房间|病房|窗口|车厢|站台|公路|电池|院(?!长)|线(?![上下])|门(?!诊))"#

  private static func chineseDue(_ match: Match) -> Day? {
    match.group(1)
      .flatMap { chineseDayOffset($0, todayWeekday: match.todayWeekday, today: match.today) }
      .map { Day(offset: $0) }
  }

  private static func chineseWhen(_ match: Match) -> Day? {
    guard let word = match.group(1),
      let offset = chineseDayOffset(word, todayWeekday: match.todayWeekday, today: match.today)
    else { return nil }
    return Day(offset: offset, isEvening: word == "今晚" || word == "明晚")
  }

  /// The weekday character's index, 0 = Sunday.
  private static func chineseWeekday(_ character: Character) -> Int? {
    ["日": 0, "天": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6][character]
  }

  private static func chineseDayOffset(_ word: String, todayWeekday: Int, today: Date?) -> Int? {
    if let date = chineseDate(word) {
      guard let today else { return nil }
      return offset(to: date, from: today)
    }
    switch word {
    case "今天", "今晚": return 0
    case "明天", "明晚": return 1
    case "后天": return 2
    case "大后天": return 3
    case "下周": return 7
    case "下下周": return 14
    case "周末": return weekendOffset(todayWeekday: todayWeekday)
    default: break
    }
    if let days = word.firstMatch(of: /(\d{1,3})天后/)?.output.1, let count = number(days) {
      return count
    }
    guard let last = word.last, let weekday = chineseWeekday(last), word.count >= 2 else { return nil }
    if word.hasPrefix("下") { return nextWeekOffset(weekday, todayWeekday: todayWeekday) }
    if word.hasPrefix("这") || word.hasPrefix("本") { return weekdayDelta(weekday, todayWeekday: todayWeekday) }
    return comingWeekdayOffset(weekday, todayWeekday: todayWeekday)
  }

  /// 2026年10月5日, 10月5号, 10月5, or 5号.
  private static func chineseDate(_ word: String) -> ExplicitDate? {
    if let match = word.wholeMatch(of: /(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]?/) {
      return ExplicitDate(
        year: match.output.1.flatMap(number), month: number(match.output.2), day: number(match.output.3) ?? 0)
    }
    if let match = word.wholeMatch(of: /(\d{1,2})号/) {
      return ExplicitDate(year: nil, month: nil, day: number(match.output.1) ?? 0)
    }
    return nil
  }
}
