import Foundation

extension LorvexCaptureVocabulary {
  /// Japanese, read for a user who reads Japanese. Words need no boundary,
  /// since Japanese is written without spaces, and the particle after a day
  /// or a time is taken with it ("金曜日に", "明日も", "10時から"), so the title
  /// reads on without it.
  ///
  /// - Day: 今日, 本日, 今朝, 今夜, 今晩, 明日, あした, 明晩, 明後日, あさって, 月曜日 or
  ///   月曜 (alone, or after 今週, 来週, 再来週, or 次の), 来週, 再来週, 週末, 今週末,
  ///   来週末, 3日後; a date: 10月5日 or 10/5, with or without its weekday in
  ///   brackets ("10/5(月)"). A weekday alone or after 次の means the next such
  ///   day, a full week ahead when it names today; after 今週 it is this week's,
  ///   after 来週 next week's, after 再来週 the week after's, weeks starting on
  ///   Monday. 今夜, 今晩, 明晩, and 明日の夜 are evenings. A name that begins with
  ///   a day word (明日香, 今日子) stays in the title.
  /// - Repeat: 毎日, 毎朝, 毎晩, 平日毎日, 毎週, 隔週, 毎週月曜, 毎月曜, 毎週月・水・金,
  ///   毎週月水金, 毎週土日, 毎週末 (Saturdays), 毎月, 毎月5日, 毎年, 隔日, 1日おき,
  ///   1週間おき, 3日ごと, 2週間ごと, 3か月ごと. A single weekday character after
  ///   毎週 counts only in a list, so "毎週水やり" is watering every week.
  /// - Due: a day before まで or までに ("金曜までに"), 今日中, 明日中.
  /// - Time: 15時, 午後3時, 3時半, 9時20分, 午前10時, 朝7時, 夕方6時, 午後3:30, 正午,
  ///   maybe with 頃 or ごろ, then から, まで, or に, after it. A time with no
  ///   part of the day from 1 to 6 o'clock is the afternoon. 夜 and 深夜 run past
  ///   midnight: 夜8時 is 8 PM, 夜12時 the midnight that ends the day, 深夜1時 the
  ///   small hours after it. 一時 alone ("for a while") is not a time. A range
  ///   (15時から16時まで, 午後3時〜5時, 3〜5時, 10:00〜11:30) also sets the length.
  /// - Length: 30分, 30分間, 2時間, 1時間半, 1時間30分, 一時間, with ほど, くらい,
  ///   or 程度 after it. The minutes of a clock time ("9時20分") are not a
  ///   length.
  /// - Priority: 至急, 大至急, 急ぎ. The Chinese words read 緊急.
  static let japanese = LorvexCaptureVocabulary(
    priority: [Rule(pattern: #"大?至急|急ぎ(?:の|で)?"#) { _ in .p1 }],
    length: [Rule(pattern: japaneseLengthPattern, read: japaneseLength)],
    time: [
      Rule(pattern: japaneseRangePattern, read: japaneseRange),
      Rule(pattern: japaneseTimePattern, read: japaneseTime),
    ],
    repeats: [
      // 毎日曜 is every Sunday and 毎月曜 every Monday, so these go before 毎日
      // and 毎月.
      Rule(pattern: #"毎([日月火水木金土])曜日?(?:に|は)?"#) { match in
        match.group(1)?.first.flatMap(japaneseWeekday).map { weekly(every: nil, on: [$0]) }
      },
      // 平日毎日 before 毎日, which would leave 平日 in the title.
      Rule(pattern: #"平日毎日|毎平日"#) { _ in workdays },
      Rule(pattern: #"毎日(?!曜)|毎朝|毎晩"#) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      Rule(pattern: #"毎週末(?:に|は)?"#) { _ in weekly(every: nil, on: [6]) },
      Rule(pattern: japaneseWeeklyPattern, read: japaneseWeeklyRepeat),
      Rule(pattern: #"毎月(?![曜末])(?:(\d{1,2})日)?(?:に|は)?"#) { match in
        monthly(every: nil, on: match.group(1).flatMap(number))
      },
      Rule(pattern: #"毎年"#) { _ in Repeat(rule: TaskRecurrenceRule(freq: .yearly)) },
      Rule(pattern: #"隔日|[1１一]日おき(?:に)?"#) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2)) },
      Rule(pattern: #"[1１一]週間おき(?:に)?"#) { _ in weekly(every: 2, on: []) },
      Rule(pattern: #"(\d{1,2})(日|週間?|[かヶカケ箇]月)(?:ごと|毎)(?:に)?"#, read: japaneseIntervalRepeat),
    ],
    due: [Rule(pattern: japaneseDuePattern, read: japaneseDue)],
    when: [Rule(pattern: japaneseWhenPattern, read: japaneseWhen)])

  // MARK: - Length

  /// 1時間30分, 1時間半, 2時間, 一時間, 30分, 30分間, each maybe followed by ほど,
  /// くらい, or 程度. Groups: 1 and 2 the hours and minutes of "1時間30分"; 3
  /// hours, 4 half; 5 minutes, which do not follow a clock hour.
  private static let japaneseLengthPattern =
    #"(?:(?<![\d.])(\d+)時間(\d+)分(?:間)?|(?<![\d.])(\d+(?:\.\d+)?|[一二三四五六七八九十]{1,3})時間(半)?|(?<![時\d.])(?<!時\s)(\d+)分(?:間)?)(?:ほど|くらい|ぐらい|程度)?"#

  private static func japaneseLength(_ match: Match) -> Int? {
    if let hours = match.group(1).flatMap(number), let minutes = match.group(2).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let text = match.group(3) {
      guard let hours = LorvexNumberInput.decimal(from: text) ?? hanNumber(text).map(Double.init) else { return nil }
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4) == nil ? 0 : 30))
    }
    return match.group(5).flatMap(number).flatMap { taskLength(minutes: $0) }
  }

  // MARK: - Time

  /// 15時, 午後3時, 3時半, 9時20分, 午後3:30, 正午, maybe with 頃 or ごろ, then から,
  /// まで, or に, after it.
  /// Groups: 1 part of the day, 2 hour, 3 half, 4 minute; 5, 6, and 7 the part
  /// of the day, hour, and minute of a colon time; 8 正午.
  private static let japaneseTimePattern =
    #"\#(japaneseDayPart)?\s*(?<![\d一二三四五六七八九十])(\d{1,2}|[一二三四五六七八九十]{1,3})時(?!間)(?:(半)|(\d{1,2})分)?(?:頃|ごろ)?(?:から|まで(?:に)?|に)?|\#(japaneseDayPart)\s*(?<![\d:：])(\d{1,2})[:：](\d{2})(?![\d:：])(?:頃|ごろ)?(?:から|まで(?:に)?|に)?|(正午)(?:頃|ごろ)?(?:から|まで(?:に)?|に)?"#

  /// A part of the day written before a clock time. 夜 and 朝 after 今 belong
  /// to the day words 今夜 and 今朝.
  private static let japaneseDayPart = "((?<!今)(?:午前|午後|朝|昼|夕方|夜|深夜))"

  private static func japaneseTime(_ match: Match) -> ClockTime? {
    japaneseClock(match, readsBareOne: false)
  }

  /// The time a match of ``japaneseTimePattern`` names. 一時 with no part of
  /// the day or minutes is one o'clock only when `readsBareOne` is true, as on
  /// a side of a range ("一時から二時まで"); alone it means "for a while".
  private static func japaneseClock(_ match: Match, readsBareOne: Bool) -> ClockTime? {
    if match.group(8) != nil { return ClockTime(minutes: 12 * 60) }
    let hourText: String
    var minute = 0
    let part: String?
    if let colonHour = match.group(6), let colonMinute = match.group(7).flatMap(number) {
      hourText = colonHour
      minute = colonMinute
      part = match.group(5)
    } else {
      guard let text = match.group(2) else { return nil }
      hourText = text
      part = match.group(1)
      if match.group(3) != nil {
        minute = 30
      } else if let text = match.group(4) {
        guard let value = number(text) else { return nil }
        minute = value
      } else if part == nil, text == "一", !readsBareOne {
        return nil
      }
    }
    guard let hour = number(hourText) ?? hanNumber(hourText), (0...24).contains(hour), (0...59).contains(minute)
    else { return nil }
    guard let part else {
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    var clockHour = hour
    switch part {
    case "午前", "朝": if clockHour == 12 { clockHour = 0 }
    case "昼": if clockHour < 11 { clockHour += 12 }
    case "夜", "深夜": return nightTime(hour: hour, minute: minute)
    default: if clockHour < 12 { clockHour += 12 }
    }
    guard clockHour < 24 else { return nil }
    return ClockTime(minutes: clockHour * 60 + minute)
  }

  // MARK: - Time range

  /// 15時から16時まで, 午後3時〜5時, 3〜5時, 10:00〜11:30: a start, then から, a
  /// wave dash, or a dash, then an end written with 時 or a colon, maybe
  /// before まで. Groups: 1 the start, 2 the end.
  private static var japaneseRangePattern: String {
    let hour = "(?<![\\d一二三四五六七八九十])(?:\\d{1,2}|[一二三四五六七八九十]{1,3})"
    let clock = "\(hour)時(?!間)(?:半|\\d{1,2}分)?|(?<![\\d:：])\\d{1,2}[:：]\\d{2}(?![\\d:：])|正午"
    let part = "(?:(?<!今)(?:午前|午後|朝|昼|夕方|夜|深夜)\\s*)"
    return "(\(part)?(?:\(clock)|\(hour)))\\s*(?:〜|～|~|-|–|—|から)\\s*(\(part)?(?:\(clock)))(?:まで(?:に)?)?"
      + noMeridiemAfter
  }

  private static func japaneseRange(_ match: Match) -> ClockTime? {
    guard let start = match.group(1).flatMap({ japaneseRangeSideTime($0, in: match) }),
      let end = match.group(2).flatMap({ japaneseRangeSideTime($0, in: match) })
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a range: a clock time ("午後3時", "5時半", "10:00"), or a start
  /// hour written without 時 ("3" of "3〜5時").
  private static func japaneseRangeSideTime(_ text: String, in match: Match) -> ClockTime? {
    let read = { (side: Match) in japaneseClock(side, readsBareOne: true) }
    return wholeTime(text, pattern: japaneseTimePattern, in: match, read: read)
      ?? wholeTime(text + "時", pattern: japaneseTimePattern, in: match, read: read)
      ?? colonTime(text)
  }

  // MARK: - Repeat

  /// 毎週 or 隔週, then maybe weekdays: written out ("月曜", "月曜日と木曜日"),
  /// or as single characters in a list ("月・水・金", "月水金", "土日"). Groups: 1
  /// 毎週 or 隔週, 2 written-out weekdays, 3 single characters.
  private static let japaneseWeeklyPattern =
    #"(毎週|隔週)(?!末)(?:([日月火水木金土]曜日?(?:\s*[・、,と]?\s*[日月火水木金土]曜日?)*)|([日月火水木金土](?:[・、,][日月火水木金土])+|[日月火水木金土]{2,}))?(?:に|は)?"#

  private static func japaneseWeeklyRepeat(_ match: Match) -> Repeat? {
    var days: [Int] = []
    if let written = match.group(2) {
      days = written.matches(of: /([日月火水木金土])曜/).compactMap { $0.output.1.first.flatMap(japaneseWeekday) }
    } else if let letters = match.group(3) {
      days = letters.compactMap(japaneseWeekday)
    }
    return weekly(every: match.group(1) == "隔週" ? 2 : nil, on: days)
  }

  /// 3日ごと, 2週間ごと, 3か月ごと. Groups: 1 count, 2 unit.
  private static func japaneseIntervalRepeat(_ match: Match) -> Repeat? {
    guard let count = match.group(1).flatMap(number), (1...99).contains(count), let unit = match.group(2)
    else { return nil }
    let every = count == 1 ? nil : count
    if unit == "日" { return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every)) }
    if unit.hasPrefix("週") { return weekly(every: every, on: []) }
    return monthly(every: every, on: nil)
  }

  // MARK: - Days

  /// The weekday a character names, 0 = Sunday.
  private static func japaneseWeekday(_ character: Character) -> Int? {
    ["日": 0, "月": 1, "火": 2, "水": 3, "木": 4, "金": 5, "土": 6][character]
  }

  /// The days, without a particle after them.
  private static var japaneseDayPattern: String {
    let weekday = "[日月火水木金土]曜日?"
    return "今日の夜|明日の夜|今日(?!子)|本日|今朝|今夜|今晩|明日(?![香美菜奈])|あした|明晩|明後日|あさって"
      + "|再来週の?(?:\(weekday))?|来週末|来週の?(?:\(weekday))?|今週の?\(weekday)|次の\(weekday)|今週末|週末"
      + "|\(weekday)|\\d{1,3}日後"
      + "|\\d{1,2}月\\d{1,2}日|(?<![\\d/])\\d{1,2}/\\d{1,2}(?![\\d/])"
  }

  /// A date's weekday in brackets, which says nothing the date does not:
  /// "(月)".
  private static let japaneseDateWeekday = "(?:[(（][日月火水木金土][)）])?"

  /// A day with the particle after it. Group 1: the day.
  private static var japaneseWhenPattern: String {
    "(\(japaneseDayPattern))\(japaneseDateWeekday)(?:には|に|は|の|から|も)?"
  }

  /// A day before まで or 締め切り, or 今日中 / 明日中. Groups: 1 the day; 2 the
  /// day of 中.
  private static var japaneseDuePattern: String {
    "(\(japaneseDayPattern))\(japaneseDateWeekday)(?:まで(?:に)?|締め?切り?)|(今日|本日|明日)中(?:に)?"
  }

  private static func japaneseDue(_ match: Match) -> Day? {
    guard let word = match.group(1) ?? match.group(2),
      let day = japaneseDay(word, todayWeekday: match.todayWeekday, today: match.today)
    else { return nil }
    return Day(offset: day.offset)
  }

  private static func japaneseWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { japaneseDay($0, todayWeekday: match.todayWeekday, today: match.today) }
  }

  private static func japaneseDay(_ word: String, todayWeekday: Int, today: Date?) -> Day? {
    if let date = japaneseDate(word) {
      guard let today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    switch word {
    case "今日", "本日", "今朝": return Day(offset: 0)
    case "今夜", "今晩", "今日の夜": return Day(offset: 0, isEvening: true)
    case "明日", "あした": return Day(offset: 1)
    case "明晩", "明日の夜": return Day(offset: 1, isEvening: true)
    case "明後日", "あさって": return Day(offset: 2)
    case "来週", "来週の": return Day(offset: 7)
    case "再来週", "再来週の": return Day(offset: 14)
    case "週末", "今週末": return Day(offset: weekendOffset(todayWeekday: todayWeekday))
    case "来週末": return Day(offset: weekendOffset(todayWeekday: todayWeekday) + 7)
    default: break
    }
    if let days = word.firstMatch(of: /(\d{1,3})日後/)?.output.1, let count = number(days) {
      return Day(offset: count)
    }
    guard let weekday = word.firstMatch(of: /([日月火水木金土])曜/)?.output.1.first.flatMap(japaneseWeekday)
    else { return nil }
    if word.hasPrefix("再来週") { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday) + 7) }
    if word.hasPrefix("来週") { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday)) }
    if word.hasPrefix("今週") { return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday)) }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday))
  }

  /// 10月5日 or 10/5.
  private static func japaneseDate(_ word: String) -> ExplicitDate? {
    guard let match = word.wholeMatch(of: /(\d{1,2})(?:月|\/)(\d{1,2})日?/) else { return nil }
    return ExplicitDate(month: number(match.output.1), day: number(match.output.2) ?? 0)
  }
}
