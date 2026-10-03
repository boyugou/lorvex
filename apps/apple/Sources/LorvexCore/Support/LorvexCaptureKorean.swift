import Foundation

extension LorvexCaptureVocabulary {
  /// Korean, read for a user who reads Korean. A phrase stands as its own
  /// word: no Hangul syllable may touch it on either side, except the
  /// particle after it, which is taken with it ("금요일엔", "3시부터"), so the
  /// title reads on without it and "오늘날" or "긴급회의" stays whole.
  ///
  /// - Day: 오늘, 오늘 밤, 내일, 내일 밤, 모레, 내일모레, 글피, 월요일 (alone, or after
  ///   이번 주, 다음 주, 다다음 주, or 다음), 다음 주, 다다음 주, 주말, 이번 주말, 다음 주말,
  ///   3일 후, 3일 뒤;
  ///   a date: 10월 5일 or 10/5. A weekday alone or after 다음 means the next
  ///   such day, a full week ahead when it names today; after 이번 주 it is
  ///   this week's, after 다음 주 next week's, after 다다음 주 the week after's,
  ///   weeks starting on Monday. 오늘 밤 and 내일 밤 are evenings.
  /// - Repeat: 매일, 날마다, 격일, 평일마다, 매주, 격주, 매주 월요일, 월요일마다,
  ///   매주 월, 수, 금, 매주 월수금, 주마다, 매달, 매월, 매달 5일, 매년, 해마다,
  ///   3일마다, 2주마다, 3개월마다.
  /// - Due: a day before 까지 or 마감 ("금요일까지").
  /// - Time: 3시, 오후 3시, 3시 반, 9시 20분, 오전 10시, 저녁 7시, 오후 세 시,
  ///   오후 3:30, 정오, 자정, maybe with 쯤, 에, 에는, 부터, or 까지 after it. A
  ///   number may touch the word before it ("내일3시"). A time with no
  ///   part of the day from 1 to 6 o'clock is the afternoon. 밤 runs past
  ///   midnight: 밤 8시 is 8 PM, 밤 12시 the midnight that ends the day, as is
  ///   자정. A range (3시부터 4시까지, 오후 3시~5시, 3~5시, 10:00~11:30) also sets
  ///   the length.
  /// - Length: 30분, 30분간, 2시간, 1시간 반, 1시간 30분, 한 시간, 반 시간, with 동안,
  ///   정도, 쯤, or 짜리 after it. The minutes of a clock time ("9시 20분") are
  ///   not a length.
  /// - Priority: 긴급, 급함.
  static let korean = LorvexCaptureVocabulary(
    priority: [Rule(pattern: #"\#(hangulStart)(?:긴급|급함)\#(hangulEnd)"#) { _ in .p1 }],
    length: [Rule(pattern: koreanLengthPattern, read: koreanLength)],
    time: [
      Rule(pattern: koreanRangePattern, read: koreanRange),
      Rule(pattern: koreanTimePattern, read: koreanTime),
    ],
    repeats: [
      Rule(pattern: #"\#(hangulStart)(?:매일|날마다)\#(hangulEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily))
      },
      Rule(pattern: #"\#(hangulStart)격일\#(hangulEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2))
      },
      Rule(pattern: #"\#(hangulStart)(?:평일\s*마다|매\s*평일|평일\s*매일)\#(hangulEnd)"#) { _ in workdays },
      Rule(pattern: koreanWeeklyPattern, read: koreanWeeklyRepeat),
      Rule(pattern: #"\#(hangulStart)([일월화수목금토])요일\s*마다\#(hangulEnd)"#) { match in
        match.group(1)?.first.flatMap(koreanWeekday).map { weekly(every: nil, on: [$0]) }
      },
      // "2주마다" and "3달마다" before the bare "주마다" and "달마다", which would
      // leave the count in the title.
      Rule(pattern: #"(?<![\d.])(\d{1,2})\s*(일|주|개월|달)\s*마다\#(hangulEnd)"#, read: koreanIntervalRepeat),
      Rule(pattern: #"(?<![\p{Hangul}\d])주\s*마다\#(hangulEnd)"#) { _ in weekly(every: nil, on: []) },
      Rule(pattern: #"(?<![\p{Hangul}\d])(?:매달|매월|달\s*마다)(?:\s*(\d{1,2})\s*일)?(?:에|마다)?\#(hangulEnd)"#) {
        match in monthly(every: nil, on: match.group(1).flatMap(number))
      },
      Rule(pattern: #"\#(hangulStart)(?:매년|해\s*마다)\#(hangulEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [Rule(pattern: koreanDuePattern, read: koreanDue)],
    when: [Rule(pattern: koreanWhenPattern, read: koreanWhen)])

  /// No Hangul syllable before or after: a Korean phrase stands as its own
  /// word.
  private static let hangulStart = #"(?<!\p{Hangul})"#
  private static let hangulEnd = #"(?!\p{Hangul})"#

  // MARK: - Length

  /// 1시간 30분, 1시간 반, 2시간, 한 시간, 반 시간, 30분, 30분간, each maybe followed
  /// by 동안, 정도, 쯤, or 짜리. A number may touch the word before it ("회의30분").
  /// Groups: 1 and 2 the hours and minutes of "1시간 30분"; 3 hours in digits,
  /// 4 hours in a word, 5 half; 6 the 반 of "반 시간"; 7 minutes, which do not
  /// follow a clock hour.
  private static let koreanLengthPattern =
    #"(?:(?<![\d.])(\d+)\s*시간\s*(\d+)\s*분(?:간)?|(?:(?<![\d.])(\d+(?:\.\d+)?)|\#(hangulStart)(한|두|세))\s*시간(?:\s*(반))?|\#(hangulStart)(반)\s*시간|(?<![\d.])(?<!시)(?<!시\s)(\d+)\s*분(?:간)?)(?:\s*(?:동안|정도|쯤)|짜리)?\#(hangulEnd)"#

  private static func koreanLength(_ match: Match) -> Int? {
    if let hours = match.group(1).flatMap(number), let minutes = match.group(2).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    let words = ["한": 1.0, "두": 2.0, "세": 3.0]
    if let hours = match.group(3).flatMap(LorvexNumberInput.decimal(from:)) ?? match.group(4).flatMap({ words[$0] }) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(5) == nil ? 0 : 30))
    }
    if match.group(6) != nil { return 30 }
    return match.group(7).flatMap(number).flatMap { taskLength(minutes: $0) }
  }

  // MARK: - Time

  /// 3시, 오후 3시, 3시 반, 9시 20분, 오후 세 시, 오후 3:30, 정오, 자정, maybe with 쯤
  /// and then 에, 에는, 부터, or 까지 after it. An hour in digits may touch the
  /// word before it ("내일3시"). Groups: 1 part of the day, 2 hour in digits, 3
  /// hour in a word, 4 half, 5 minute; 6, 7, and 8 the part of the day, hour,
  /// and minute of a colon time; 9 정오 or 자정.
  private static var koreanTimePattern: String {
    let after = "(?:\\s*쯤)?(?:에는|에|부터|까지)?\(hangulEnd)"
    // A number word follows a space or a part of the day written against it
    // ("오후세시"), never another Hangul syllable.
    let hour = "(?:(?<!\\d)(\\d{1,2})|(?:(?<=\(koreanDayPartWords))|\(hangulStart))(\(koreanHourWords)))"
    return "(?:\(hangulStart)\(koreanDayPart)\\s*)?\(hour)\\s*시(?!간)(?:\\s*(반)|\\s*(\\d{1,2})\\s*분)?\(after)"
      + "|\(hangulStart)\(koreanDayPart)\\s*(?<![\\d:：])(\\d{1,2})[:：](\\d{2})(?![\\d:：])\(after)"
      + "|\(hangulStart)(정오|자정)\(after)"
  }

  private static let koreanDayPartWords = "오전|오후|아침|낮|저녁|밤|새벽"
  private static let koreanDayPart = "(\(koreanDayPartWords))"

  /// The native Korean numbers a clock hour is said in, longest first so
  /// 열한 is not read as 열.
  private static let koreanHourWords = "열한|열두|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열"

  private static let koreanHours: [String: Int] = [
    "한": 1, "두": 2, "세": 3, "네": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10,
    "열한": 11, "열두": 12,
  ]

  private static func koreanTime(_ match: Match) -> ClockTime? {
    switch match.group(9) {
    case "정오": return ClockTime(minutes: 12 * 60)
    case "자정": return ClockTime(minutes: 0, isAfterMidnight: true)
    default: break
    }
    let hourText: String
    var minute = 0
    let part: String?
    if let colonHour = match.group(7), let colonMinute = match.group(8).flatMap(number) {
      hourText = colonHour
      minute = colonMinute
      part = match.group(6)
    } else {
      guard let text = match.group(2) ?? match.group(3) else { return nil }
      hourText = text
      part = match.group(1)
      if match.group(4) != nil {
        minute = 30
      } else if let text = match.group(5) {
        guard let value = number(text) else { return nil }
        minute = value
      }
    }
    guard let hour = number(hourText) ?? koreanHours[hourText], (0...24).contains(hour), (0...59).contains(minute)
    else { return nil }
    guard let part else {
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    var clockHour = hour
    switch part {
    case "오전", "아침", "새벽": if clockHour == 12 { clockHour = 0 }
    case "낮": if clockHour < 11 { clockHour += 12 }
    case "밤": return nightTime(hour: hour, minute: minute)
    default: if clockHour < 12 { clockHour += 12 }
    }
    guard clockHour < 24 else { return nil }
    return ClockTime(minutes: clockHour * 60 + minute)
  }

  // MARK: - Time range

  /// 3시부터 4시까지, 오후 3시~5시, 3~5시, 10:00~11:30: a start, then 부터, a
  /// tilde, or a dash, then an end written with 시 or a colon, maybe before
  /// 까지. Groups: 1 the start, 2 the end.
  private static var koreanRangePattern: String {
    let hour = "(?:(?<!\\d)\\d{1,2}|(?:(?<=\(koreanDayPartWords))|\(hangulStart))(?:\(koreanHourWords)))"
    let clock =
      "\(hour)\\s*시(?!간)(?:\\s*반|\\s*\\d{1,2}\\s*분)?|(?<![\\d:：])\\d{1,2}[:：]\\d{2}(?![\\d:：])|\(hangulStart)(?:정오|자정)"
    let part = "(?:\(hangulStart)(?:\(koreanDayPartWords))\\s*)"
    return "(\(part)?(?:\(clock)|\(hour)))\\s*(?:~|〜|～|-|–|—|부터)\\s*(\(part)?(?:\(clock)))(?:\\s*까지)?"
      + hangulEnd + noMeridiemAfter
  }

  private static func koreanRange(_ match: Match) -> ClockTime? {
    guard let start = match.group(1).flatMap({ koreanRangeSideTime($0, in: match) }),
      let end = match.group(2).flatMap({ koreanRangeSideTime($0, in: match) })
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a range: a clock time ("오후 3시", "5시 반", "10:00"), or a
  /// start hour written without 시 ("3" of "3~5시").
  private static func koreanRangeSideTime(_ text: String, in match: Match) -> ClockTime? {
    wholeTime(text, pattern: koreanTimePattern, in: match, read: koreanTime)
      ?? wholeTime(text + "시", pattern: koreanTimePattern, in: match, read: koreanTime)
      ?? colonTime(text)
  }

  // MARK: - Repeat

  /// 매주 or 격주, then maybe weekdays: written out ("월요일", "월요일과 목요일"),
  /// or as single syllables in a list ("월, 수, 금", "월수금"). Groups: 1 매주
  /// or 격주, 2 written-out weekdays, 3 single syllables.
  private static var koreanWeeklyPattern: String {
    let day = "[일월화수목금토]"
    let written = "\(day)요일(?:\\s*(?:,|·|、|와|과|및|하고)?\\s*\(day)요일)*"
    let letters = "\(day)(?:\\s*[,·、]\\s*\(day))+|\(day){2,}"
    return "\(hangulStart)(매주|격주)(?:\\s*(\(written))|\\s*(\(letters)))?(?:에|마다)?\(hangulEnd)"
  }

  private static func koreanWeeklyRepeat(_ match: Match) -> Repeat? {
    var days: [Int] = []
    if let written = match.group(2) {
      days = written.matches(of: /([일월화수목금토])요일/).compactMap { $0.output.1.first.flatMap(koreanWeekday) }
    } else if let letters = match.group(3) {
      days = letters.compactMap(koreanWeekday)
    }
    return weekly(every: match.group(1) == "격주" ? 2 : nil, on: days)
  }

  /// 3일마다, 2주마다, 3개월마다. Groups: 1 count, 2 unit.
  private static func koreanIntervalRepeat(_ match: Match) -> Repeat? {
    guard let count = match.group(1).flatMap(number), (1...99).contains(count), let unit = match.group(2)
    else { return nil }
    let every = count == 1 ? nil : count
    switch unit {
    case "일": return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "주": return weekly(every: every, on: [])
    default: return monthly(every: every, on: nil)
    }
  }

  // MARK: - Days

  /// The weekday a syllable names, 0 = Sunday.
  private static func koreanWeekday(_ character: Character) -> Int? {
    ["일": 0, "월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6][character]
  }

  /// The days, without a particle after them.
  private static var koreanDayPattern: String {
    let weekday = "[일월화수목금토]요일"
    return "오늘\\s*밤|내일\\s*밤|내일\\s*모레|오늘|내일|모레|글피|다다음\\s*주(?:\\s*\(weekday))?|다음\\s*주말"
      + "|다음\\s*주(?:\\s*\(weekday))?"
      + "|이번\\s*주\\s*\(weekday)|다음\\s*\(weekday)|(?:이번\\s*)?주말|\(weekday)|\\d{1,3}\\s*일\\s*(?:후|뒤)"
      + "|\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일|(?<![\\d/])\\d{1,2}/\\d{1,2}(?![\\d/])"
  }

  /// A day with the particle after it. Group 1: the day.
  private static var koreanWhenPattern: String {
    "\(hangulStart)(\(koreanDayPattern))(?:에는|엔|에|은|는|도|의|부터)?\(hangulEnd)"
  }

  /// A day before 까지 or 마감. Group 1: the day.
  private static var koreanDuePattern: String {
    "\(hangulStart)(\(koreanDayPattern))\\s*(?:까지(?:는)?|마감)\(hangulEnd)"
  }

  private static func koreanDue(_ match: Match) -> Day? {
    guard let word = match.group(1), let day = koreanDay(word, todayWeekday: match.todayWeekday, today: match.today)
    else { return nil }
    return Day(offset: day.offset)
  }

  private static func koreanWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { koreanDay($0, todayWeekday: match.todayWeekday, today: match.today) }
  }

  private static func koreanDay(_ phrase: String, todayWeekday: Int, today: Date?) -> Day? {
    let word = phrase.filter { !$0.isWhitespace }
    if let date = koreanDate(word) {
      guard let today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    switch word {
    case "오늘": return Day(offset: 0)
    case "오늘밤": return Day(offset: 0, isEvening: true)
    case "내일": return Day(offset: 1)
    case "내일밤": return Day(offset: 1, isEvening: true)
    case "모레", "내일모레": return Day(offset: 2)
    case "글피": return Day(offset: 3)
    case "다음주": return Day(offset: 7)
    case "다다음주": return Day(offset: 14)
    case "주말", "이번주말": return Day(offset: weekendOffset(todayWeekday: todayWeekday))
    case "다음주말": return Day(offset: weekendOffset(todayWeekday: todayWeekday) + 7)
    default: break
    }
    if let days = word.firstMatch(of: /(\d{1,3})일(?:후|뒤)/)?.output.1, let count = number(days) {
      return Day(offset: count)
    }
    guard let weekday = word.firstMatch(of: /([일월화수목금토])요일/)?.output.1.first.flatMap(koreanWeekday)
    else { return nil }
    if word.hasPrefix("다다음주") { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday) + 7) }
    if word.hasPrefix("다음주") { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday)) }
    if word.hasPrefix("이번주") { return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday)) }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday))
  }

  /// 10월5일 or 10/5, with the spaces taken out.
  private static func koreanDate(_ word: String) -> ExplicitDate? {
    guard let match = word.wholeMatch(of: /(\d{1,2})(?:월|\/)(\d{1,2})일?/) else { return nil }
    return ExplicitDate(month: number(match.output.1), day: number(match.output.2) ?? 0)
  }
}
