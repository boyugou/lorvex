import Foundation

/// What a typed capture line says beyond its title.
///
/// Capture and the task detail share one vocabulary: the phrases this parser
/// recognizes become the same words the detail's property sentence shows, so
/// typing "Call the caterer tomorrow 20 min #offsite" creates the task the
/// sentence would describe as "Tomorrow for 20 min. In Offsite." Recognized
/// phrases are removed from the title; everything else stays verbatim.
///
/// Days are offsets from the product's logical today, so the caller converts
/// them through its own logical-day bridge rather than a device calendar.
public struct LorvexCaptureParse: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case when, due, time, repeats, length, list, priority, tag
  }

  /// One recognized phrase, in the order it appeared.
  public struct Phrase: Equatable, Sendable {
    public var kind: Kind
    /// The text as typed ("tomorrow", "20 min", "#offsite").
    public var text: String
  }

  public var title: String
  /// Days after the logical today the task is planned for.
  public var plannedDayOffset: Int?
  /// Days after the logical today the task is due.
  public var dueDayOffset: Int?
  public var estimatedMinutes: Int?
  /// The clock time the line named ("3pm", "下午3点"), in minutes since
  /// midnight.
  public var startMinutes: Int?
  /// How the task repeats ("every Monday", 每天).
  public var recurrence: TaskRecurrenceRule?
  /// Days after the logical today of the rule's first occurrence, when the
  /// rule fixes one: the next of its weekdays, or of its day of the month,
  /// today included.
  public var recurrenceStartOffset: Int?
  /// A list the text named with `#name`, matched against the known lists.
  public var listID: String?
  public var listName: String?
  public var priority: LorvexTask.Priority?
  /// `#words` that matched no list.
  public var tags: [String]
  public var phrases: [Phrase]

  public var hasDetails: Bool { !phrases.isEmpty }

  /// The day a task created from the line is planned for: the day it named,
  /// or the logical today when it named only a clock time, since a time
  /// belongs to a day.
  public var resolvedPlannedDayOffset: Int? {
    plannedDayOffset ?? (startMinutes == nil ? nil : (recurrence == nil ? 0 : resolvedDueDayOffset))
  }

  /// The day a task created from the line is due. A repeating task needs a
  /// due day, its first occurrence: the due day the line named, else the
  /// rule's first occurrence, else the planned day, else the logical today.
  public var resolvedDueDayOffset: Int? {
    guard recurrence != nil else { return dueDayOffset }
    return dueDayOffset ?? recurrenceStartOffset ?? plannedDayOffset ?? 0
  }

  /// The task's time on its planned day: from the clock time the line named,
  /// for its length or half an hour, kept inside the day.
  public var plannedTime: Range<Int>? {
    startMinutes.map {
      LorvexTaskFieldChoices.time(
        LorvexTaskFieldChoices.newTime(length: estimatedMinutes, nowMinutes: nil, isToday: false),
        movingStartTo: $0)
    }
  }
}

/// Reads a capture line in English or Chinese.
///
/// English words need a word boundary of Latin letters and digits on both
/// sides (an apostrophe counts as part of the word, so "today's" stays in the
/// title); Chinese words need none, since Chinese is written without spaces
/// ("明天开会" plans "开会" for tomorrow). The vocabulary:
///
/// - Day (`when`): today, tonight, tomorrow, the weekday names, "this"/"next"
///   with a weekday, next week, weekend, "in 3 days"; 今天, 今晚, 明天, 明晚,
///   后天, 大后天, 周三 / 星期三 / 礼拜三 (with 这 / 本 / 下), 下周, 周末,
///   3天后; a date: "Oct 5", "October 5th", "5 Oct", "2026-10-05", 10月5日,
///   10月5号, 5号. A date without a year that has passed this year means next
///   year's; "5号" means the coming 5th. A weekday's three- or four-letter abbreviation ("sat", "wed")
///   counts only capitalized or after on / for / this / next / by, since the
///   short forms are also English words. A capitalized weekday inside the line
///   with no lead word ("Monday Morning Memo") is a name, not a date.
/// - Repeat: every day, every weekday, every week, every other week, every 3
///   days, every month, every year, every Monday, every Mon and Thu, every
///   other Friday, and daily / weekly / monthly / yearly at the end of the
///   line ("Weekly review" stays a title); 每天, 每日, 每隔一天, 每3天, 每周,
///   每两周, 每周一, 每周一三五, 每个工作日, 每月, 每月5号, 每年.
/// - Due: "by" / "due" before a day; a Chinese day before 前 / 之前 ("周五前").
/// - Time: "3pm", "3:30 pm", "at 15:30", "noon", "at midnight"; 下午3点,
///   晚上8点半, 三点一刻, 9点20分, 15:30. A time with no AM, PM, or part of
///   day from 1 to 6 o'clock is the afternoon, since tasks are seldom planned
///   before dawn. The night of a day (晚上, 半夜, 午夜, or a time with no AM
///   or PM after tonight / 今晚 / 明晚) runs past midnight: 6 to 11 o'clock
///   is that evening, while 12 o'clock is the midnight that ends the day and
///   1 to 5 o'clock the small hours after it, both on the next day.
///   "Midnight" also ends the day it is named with. A time on the next day
///   moves the planned day one day on, and with it the days a repeat names
///   ("每周五晚上12点" repeats on Saturdays at 00:00).
/// - Length: "20 min", "1.5h", "20m", "1h30m", "half an hour"; 30分钟,
///   2小时, 2个小时, 半小时, 一个半小时.
/// - Priority: "!" to "!!!", p1 to p3, "high priority", "low priority",
///   "urgent" at the end of the line or opening it before a colon or comma,
///   and 紧急 (not after 不).
/// - List or tag: `#word`, in any script. The word names a list when it
///   matches a list's name or alias by its letters and digits, ignoring
///   case and accents ("#offsite2026", "#manana" for "Mañana"); any
///   other `#word` is a tag.
public enum LorvexCaptureParser {
  /// A list the parser can match a `#word` against.
  public struct ListOption: Sendable {
    public var id: String
    /// The name the parse reports, as the interface shows it.
    public var name: String
    /// Other names a `#word` may use for the list, such as the stored English
    /// name of a list the interface shows under a localized one.
    public var aliases: [String]

    public init(id: String, name: String, aliases: [String] = []) {
      self.id = id
      self.name = name
      self.aliases = aliases
    }

    /// The option for `list`: its shown name, answering to its stored name too
    /// (``LorvexList/matchNames``), so `#收件箱` and `#inbox` both find the
    /// seeded Inbox in a Chinese interface.
    public init(list: LorvexList) {
      let names = list.matchNames
      self.init(id: list.id, name: names[0], aliases: Array(names.dropFirst()))
    }
  }

  /// Parse one capture line.
  ///
  /// - Parameters:
  ///   - text: what the user typed.
  ///   - lists: the lists a `#word` may name; matching ignores case, spaces,
  ///     and punctuation, so `#offsite2026` finds "Offsite 2026".
  ///   - todayWeekday: the logical today's weekday, 1 = Sunday … 7 = Saturday
  ///     (the Gregorian `Calendar` convention). A weekday name means the next
  ///     such day, a full week ahead when it names today.
  ///   - today: the logical today as `yyyy-MM-dd`. Dates written out ("Oct 5",
  ///     10月5日) are recognized only when it is given.
  public static func parse(
    _ text: String, lists: [ListOption], todayWeekday: Int, today: String? = nil
  ) -> LorvexCaptureParse {
    var result = LorvexCaptureParse(
      title: text, plannedDayOffset: nil, dueDayOffset: nil, estimatedMinutes: nil,
      startMinutes: nil, recurrence: nil, recurrenceStartOffset: nil, listID: nil, listName: nil,
      priority: nil, tags: [], phrases: [])
    let todayDate = today.flatMap(dayDate)
    var clockTime: ClockTime?
    var remaining = text
    var found: [(range: Range<String.Index>, phrase: LorvexCaptureParse.Phrase)] = []

    func take(_ pattern: String, _ handle: (NSTextCheckingResult, String) -> LorvexCaptureParse.Kind?) {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
      let nsRange = NSRange(remaining.startIndex..., in: remaining)
      // Walk matches back to front so removing one leaves earlier ranges valid.
      for match in regex.matches(in: remaining, range: nsRange).reversed() {
        guard let range = Range(match.range, in: remaining) else { continue }
        let matched = String(remaining[range])
        guard let kind = handle(match, remaining) else { continue }
        found.append((range, .init(kind: kind, text: matched.trimmingCharacters(in: .whitespaces))))
        // Between two Chinese characters the phrase leaves no gap; elsewhere a
        // space keeps the words on either side apart.
        let joinsHan =
          range.lowerBound > remaining.startIndex && range.upperBound < remaining.endIndex
          && isHan(remaining[remaining.index(before: range.lowerBound)]) && isHan(remaining[range.upperBound])
        remaining.replaceSubrange(range, with: joinsHan ? "" : " ")
      }
    }

    func group(_ match: NSTextCheckingResult, _ index: Int, in source: String) -> String? {
      guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: source)
      else { return nil }
      return String(source[range])
    }

    // Tags, priority, and length go first, so the day rules below judge a
    // weekday against the title words alone.
    // A word's combining marks (Devanagari and Thai vowel signs, Arabic
    // harakat) and joiners (Persian, Indic) are part of it.
    take(#"(?<![\p{L}\p{M}\p{N}])#([\p{L}\p{M}\p{N}_\u200C\u200D-]+)"#) { match, source in
      guard let name = group(match, 1, in: source) else { return nil }
      let key = normalized(name)
      if result.listID == nil,
        let list = lists.first(where: { option in
          ([option.name] + option.aliases).contains { normalized($0) == key }
        })
      {
        result.listID = list.id
        result.listName = list.name
        return .list
      }
      result.tags.insert(name, at: 0)
      return .tag
    }
    take(
      #"\#(latinStart)(high priority|low priority|p[1-3])\#(latinEnd)|(?<!\S)(!{1,3})(?!\S)|(?<!不)(紧急)|(?<=\s)urgent(?=\s*$)|^\s*urgent(?=\s*[:,，：])"#
    ) { match, source in
      guard result.priority == nil else { return nil }
      switch group(match, 1, in: source)?.lowercased() {
      case "low priority", "p3": result.priority = .p3
      case "p2": result.priority = .p2
      default: result.priority = .p1
      }
      return .priority
    }
    take(lengthPattern) { match, source in
      guard result.estimatedMinutes == nil, let minutes = lengthMinutes(match, in: source) else { return nil }
      result.estimatedMinutes = minutes
      return .length
    }
    // Chinese first, so "下午3:30" keeps its part of day.
    take(hanTimePattern) { match, source in
      guard result.startMinutes == nil, let time = hanTime(match, in: source) else { return nil }
      result.startMinutes = time.minutes
      clockTime = time
      return .time
    }
    take(latinTimePattern) { match, source in
      guard result.startMinutes == nil, let time = latinTime(match, in: source) else { return nil }
      result.startMinutes = time.minutes
      clockTime = time
      return .time
    }

    // Repeats before days, so "every monday" and 每周一 are not read as one
    // planned Monday, and 每月5号 not as one 5th.
    func repeats(_ rule: TaskRecurrenceRule, weekdays: [Int] = [], monthDay: Int? = nil) -> LorvexCaptureParse.Kind? {
      guard result.recurrence == nil else { return nil }
      result.recurrence = rule
      if !weekdays.isEmpty {
        result.recurrenceStartOffset = weekdays.map { weekdayDelta($0, todayWeekday: todayWeekday) }.min()
      } else if let monthDay, let todayDate {
        result.recurrenceStartOffset = offset(to: ExplicitDate(year: nil, month: nil, day: monthDay), from: todayDate)
      }
      return .repeats
    }
    take(latinRepeatPattern) { match, source in
      if let adverb = group(match, 4, in: source)?.lowercased() {
        switch adverb {
        case "daily": return repeats(TaskRecurrenceRule(freq: .daily))
        case "weekly": return repeats(TaskRecurrenceRule(freq: .weekly))
        case "monthly": return repeats(TaskRecurrenceRule(freq: .monthly))
        default: return repeats(TaskRecurrenceRule(freq: .yearly))
        }
      }
      guard let unit = group(match, 3, in: source)?.lowercased() else { return nil }
      var interval = group(match, 2, in: source).flatMap(number) ?? 1
      if group(match, 1, in: source) != nil { interval *= 2 }
      guard (1...99).contains(interval) else { return nil }
      let every = interval == 1 ? nil : interval
      switch unit {
      case "day", "days": return repeats(TaskRecurrenceRule(freq: .daily, interval: every))
      case "weekday", "weekdays":
        return repeats(TaskRecurrenceRule(freq: .weekly, byDay: Array(weekdayCodes[1...5])), weekdays: Array(1...5))
      case "week", "weeks": return repeats(TaskRecurrenceRule(freq: .weekly, interval: every))
      case "month", "months": return repeats(TaskRecurrenceRule(freq: .monthly, interval: every))
      case "year", "years": return repeats(TaskRecurrenceRule(freq: .yearly, interval: every))
      default:
        let days = unit.split { !$0.isLetter }.map(String.init).compactMap(weekdayIndex)
        guard !days.isEmpty else { return nil }
        let unique = Array(Set(days)).sorted()
        return repeats(
          TaskRecurrenceRule(freq: .weekly, interval: every, byDay: unique.map { weekdayCodes[$0] }), weekdays: unique)
      }
    }
    take(#"每个?工作日"#) { _, _ in
      repeats(TaskRecurrenceRule(freq: .weekly, byDay: Array(weekdayCodes[1...5])), weekdays: Array(1...5))
    }
    take(#"每(隔)?(\d{1,2}|[一两二三四五六七八九十]{1,2})?个?(?:周|星期|礼拜)([一二三四五六日天](?:[、,，和]?[一二三四五六日天])*)?"#) { match, source in
      guard let interval = hanInterval(match, in: source) else { return nil }
      let days = (group(match, 3, in: source) ?? "").compactMap(hanWeekday)
      let unique = Array(Set(days)).sorted()
      return repeats(
        TaskRecurrenceRule(
          freq: .weekly, interval: interval, byDay: unique.isEmpty ? nil : unique.map { weekdayCodes[$0] }),
        weekdays: unique)
    }
    take(#"每(隔)?(\d{1,2}|[一两二三四五六七八九十]{1,2})?个?月(?:(\d{1,2})[日号])?"#) { match, source in
      guard let interval = hanInterval(match, in: source) else { return nil }
      let day = group(match, 3, in: source).flatMap(number)
      if let day, !(1...31).contains(day) { return nil }
      return repeats(
        TaskRecurrenceRule(freq: .monthly, interval: interval, byMonthDay: day.map { [$0] }), monthDay: day)
    }
    take(#"每(隔)?(\d{1,2}|[一两二三四五六七八九十]{1,2})?个?(天|日|年)"#) { match, source in
      guard let interval = hanInterval(match, in: source), let unit = group(match, 3, in: source) else { return nil }
      return repeats(TaskRecurrenceRule(freq: unit == "年" ? .yearly : .daily, interval: interval))
    }

    // Due before when, so "by friday" and "周五前" are not read as planned days.
    take(#"\#(latinStart)(?:by|due)\s+(\#(latinDayPattern))\#(latinEnd)|(\#(hanDayPattern))(?:之前|前)"#) { match, source in
      guard result.dueDayOffset == nil,
        let word = group(match, 1, in: source) ?? group(match, 2, in: source),
        let offset = dayOffset(word, todayWeekday: todayWeekday, today: todayDate)
      else { return nil }
      result.dueDayOffset = offset
      return .due
    }
    take(#"\#(latinStart)(?:(on|for|this|next)\s+)?(\#(latinDayPattern))\#(latinEnd)"#) { match, source in
      guard result.plannedDayOffset == nil, let word = group(match, 2, in: source),
        var offset = dayOffset(word, todayWeekday: todayWeekday, today: todayDate)
      else { return nil }
      let lead = group(match, 1, in: source)?.lowercased()
      if lead == nil, let weekday = weekdayIndex(word) {
        let isCapitalized = word.first?.isUppercase == true
        // The short forms are English words ("sat", "wed"), so alone they
        // count only capitalized.
        if word.lowercased() != weekdays[weekday][0], !isCapitalized { return nil }
        // A capitalized weekday inside the line is a name ("Monday Morning
        // Memo") unless it ends the line.
        if isCapitalized, let end = Range(match.range, in: source)?.upperBound,
          !source[end...].trimmingCharacters(in: .whitespaces).isEmpty
        {
          return nil
        }
      }
      if let weekday = weekdayIndex(word) {
        if lead == "this" { offset = weekdayDelta(weekday, todayWeekday: todayWeekday) }
        if lead == "next", offset < 7 { offset += 7 }
      }
      result.plannedDayOffset = offset
      return .when
    }
    take(#"(\#(hanDayPattern))"#) { match, source in
      guard result.plannedDayOffset == nil, let word = group(match, 1, in: source),
        let offset = dayOffset(word, todayWeekday: todayWeekday, today: todayDate)
      else { return nil }
      result.plannedDayOffset = offset
      return .when
    }

    // "Tonight 8:00" and "今晚8点" mean that evening, and "今晚12点" the
    // midnight that ends it.
    if let time = clockTime, let hour = time.writtenHour,
      found.contains(where: { entry in
        entry.phrase.kind == .when && eveningWords.contains { entry.phrase.text.lowercased().hasSuffix($0) }
      }),
      let night = nightTime(hour: hour, minute: time.minutes % 60)
    {
      clockTime = night
      result.startMinutes = night.minutes
    }
    if clockTime?.isAfterMidnight == true {
      moveToNextDay(&result)
    }

    result.phrases = found.sorted { $0.range.lowerBound < $1.range.lowerBound }.map(\.phrase)
    result.title = cleanTitle(remaining)
    // A line that is nothing but details keeps its text as the title rather than
    // creating a task with no name.
    if result.title.isEmpty {
      return LorvexCaptureParse(
        title: text.trimmingCharacters(in: .whitespacesAndNewlines), plannedDayOffset: nil,
        dueDayOffset: nil, estimatedMinutes: nil, startMinutes: nil, recurrence: nil,
        recurrenceStartOffset: nil, listID: nil, listName: nil, priority: nil, tags: [], phrases: [])
    }
    return result
  }

  // MARK: - Vocabulary

  /// A word boundary for English: no Latin letter, digit, or apostrophe on
  /// that side.
  private static let latinStart = #"(?<![\p{Latin}\p{N}'’])"#
  private static let latinEnd = #"(?![\p{Latin}\p{N}'’])"#

  /// Each weekday's names, full name first, Sunday first.
  private static let weekdays = [
    ["sunday", "sun"], ["monday", "mon"], ["tuesday", "tue", "tues"], ["wednesday", "wed"],
    ["thursday", "thu", "thur", "thurs"], ["friday", "fri"], ["saturday", "sat"],
  ]

  private static var latinDayPattern: String {
    let names = weekdays.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    return #"today|tonight|tomorrow|tmrw|tmr|next week|this weekend|weekend|in\s+\d{1,3}\s+days?|"#
      + #"\d{4}-\d{2}-\d{2}|"# + latinMonthDayPattern + "|" + names
  }

  /// RFC 5545 weekday codes, Sunday first.
  private static let weekdayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

  /// "every other week", "every 3 days", "every Mon and Thu", or a cadence
  /// adverb at the end of the line. Groups: 1 other, 2 count, 3 unit or
  /// weekdays, 4 adverb.
  private static var latinRepeatPattern: String {
    let names = weekdays.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    let days = "(?:\(names))(?:\\s*(?:,|and|&)\\s*(?:\(names)))*"
    return "\(latinStart)every\\s+(other\\s+)?(?:(\\d{1,2})\\s+)?(days?|weekdays?|weeks?|months?|years?|\(days))\(latinEnd)"
      + "|\(latinStart)(daily|weekly|monthly|yearly|annually)(?=\\s*$)"
  }

  /// The interval a Chinese repeat names: 每两周 is 2, 每隔一周 is 2 (one
  /// skipped), 每周 is nil (every one). Groups: 1 隔, 2 count.
  private static func hanInterval(_ match: NSTextCheckingResult, in source: String) -> Int?? {
    var count = 1
    if match.range(at: 2).location != NSNotFound, let range = Range(match.range(at: 2), in: source) {
      let text = String(source[range])
      guard let value = number(text) ?? hanNumber(text), value > 0 else { return nil }
      count = value
    }
    if match.range(at: 1).location != NSNotFound { count += 1 }
    guard count <= 99 else { return nil }
    return .some(count == 1 ? nil : count)
  }

  /// Each month's names, full name first, January first.
  private static let months = [
    ["january", "jan"], ["february", "feb"], ["march", "mar"], ["april", "apr"], ["may"],
    ["june", "jun"], ["july", "jul"], ["august", "aug"], ["september", "sept", "sep"],
    ["october", "oct"], ["november", "nov"], ["december", "dec"],
  ]

  /// "Oct 5", "October 5th, 2027", "5 Oct", "5th of October".
  private static var latinMonthDayPattern: String {
    let names = months.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    let day = #"\d{1,2}(?:st|nd|rd|th)?"#
    let year = #"(?:,?\s+\d{4})?"#
    return "(?:\(names))\\.?\\s+\(day)(?![\\p{N}:])\(year)|\(day)\\s+(?:of\\s+)?(?:\(names))\(year)"
  }

  /// The day words that put a bare clock time in the evening.
  private static let eveningWords: Set<String> = ["tonight", "今晚", "明晚"]

  /// The Chinese days. Weekday characters: 一 … 六, and 日 / 天 for Sunday.
  private static let hanDayPattern =
    #"(?:\d{4}年)?\d{1,2}月\d{1,2}[日号]|\d{1,2}月\d{1,2}(?![\d点:：])|(?<!\d)\d{1,2}号|大后天|后天|今天|今晚|明天|明晚|下下周|(?<!每)(?:这|本|下)?(?:周|星期|礼拜)[一二三四五六日天]|下周|周末|\d{1,3}天后"#

  /// "3pm", "3:30 pm", "at 15:30", "noon", each optionally after "at" or
  /// "@", and "at midnight" ("Midnight" alone is as often a name). Groups: 1
  /// hour, 2 minute, 3 meridiem; 4 and 5 a colon time's hour and minute; 6
  /// noon; 7 midnight. `\d` matches the digits of every script, where a digit
  /// range such as `[0-5]` would match only ASCII, so the minute's range is
  /// checked in code.
  private static let latinTimePattern =
    #"(?<![\p{Latin}\p{N}:])(?:(?:(?:at|@)\s*)?(?:(\d{1,2})(?::(\d\d))?\s*([ap]\.?m\.?)|(?<!\d)(\d{1,2}):(\d\d)|(noon))|(?:at|@)\s*(midnight))(?![\p{Latin}\p{N}:])"#

  /// 下午3点, 晚上8点半, 三点一刻, 9点20分, 下午3:30, 15：30. Groups: 1 part of
  /// day, 2 hour, 3 half, 4 quarter, 5 minute; 6, 7, and 8 the part of day,
  /// hour, and minute of a colon time. "第三点" and "一点" alone ("a little")
  /// are not times.
  private static let hanTimePattern =
    #"\#(hanDayPart)?(?<![第\d一二两三四五六七八九十])(\d{1,2}|[一二两三四五六七八九十]{1,3})[点點]钟?(?:(半)|(一刻|三刻)|(\d{1,2}|[零一二三四五六七八九十]{1,3})分?)?|\#(hanDayPart)(?<![\d:：])(\d{1,2})[:：](\d{2})(?![\d:：])|(?<![\d:：])()(\d{1,2})[：](\d{2})(?![\d:：])"#

  private static let hanDayPart = "(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|半夜|午夜)"

  /// A clock time a line named.
  private struct ClockTime {
    /// Minutes since midnight on the day the time falls on.
    var minutes: Int
    /// For a time written with no AM, PM, or part of day, the hour as
    /// written, before a 1 to 6 o'clock moves to the afternoon; nil otherwise.
    var writtenHour: Int?
    /// True when the time falls after the midnight that ends the named day
    /// ("晚上12点", "半夜1点", "at midnight"), so it is on the next day.
    var isAfterMidnight = false
  }

  private static func latinTime(_ match: NSTextCheckingResult, in source: String) -> ClockTime? {
    func group(_ index: Int) -> String? {
      guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: source)
      else { return nil }
      return String(source[range])
    }
    if group(6) != nil { return ClockTime(minutes: 12 * 60) }
    if group(7) != nil { return ClockTime(minutes: 0, isAfterMidnight: true) }
    if let hour = group(1).flatMap(number), let meridiem = group(3)?.lowercased() {
      let minute = group(2).flatMap(number) ?? 0
      guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
      let isPM = meridiem.hasPrefix("p")
      return ClockTime(minutes: ((hour % 12) + (isPM ? 12 : 0)) * 60 + minute)
    }
    guard let hourText = group(4), let hour = number(hourText), let minute = group(5).flatMap(number) else { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  private static func hanTime(_ match: NSTextCheckingResult, in source: String) -> ClockTime? {
    func group(_ index: Int) -> String? {
      guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: source)
      else { return nil }
      return String(source[range])
    }
    let hourText: String
    var hour: Int
    var minute = 0
    let part: String?
    if let colonHour = group(7) ?? group(10), let value = number(colonHour),
      let minuteValue = (group(8) ?? group(11)).flatMap(number)
    {
      hourText = colonHour
      hour = value
      minute = minuteValue
      part = group(6)
    } else {
      guard let text = group(2), let value = number(text) ?? hanNumber(text) else { return nil }
      hourText = text
      hour = value
      part = group(1)
      if group(3) != nil {
        minute = 30
      } else if let quarter = group(4) {
        minute = quarter == "一刻" ? 15 : 45
      } else if let text = group(5) {
        guard let value = number(text) ?? hanNumber(text) else { return nil }
        minute = value
      } else if part == nil, text == "一" {
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

  /// A time in the night of the named day, which runs past midnight: 12
  /// o'clock (or 0 or 24) is the midnight that ends the day and 1 to 5
  /// o'clock the small hours after it, both on the next day; 6 to 11 o'clock
  /// is the evening; a 24-hour time from 13:00 stays as written.
  private static func nightTime(hour: Int, minute: Int) -> ClockTime? {
    switch hour {
    case 0, 12, 24: ClockTime(minutes: minute, isAfterMidnight: true)
    case 1...5: ClockTime(minutes: hour * 60 + minute, isAfterMidnight: true)
    case 6...11: ClockTime(minutes: (hour + 12) * 60 + minute)
    case 13...23: ClockTime(minutes: hour * 60 + minute)
    default: nil
    }
  }

  /// The whole number a matched run of digits spells. The patterns' `\d`
  /// matches the decimal digits of every script (a full-width "３" from a
  /// Chinese input method, an Arabic-Indic "٣"), which `Int(_:)` cannot read.
  private static func number(_ text: some StringProtocol) -> Int? {
    LorvexNumberInput.integer(from: text)
  }

  /// Whether a written hour starts with a zero digit in any script ("09",
  /// "０９"), which marks it as a 24-hour time.
  private static func startsWithZero(_ hourText: String) -> Bool {
    hourText.first.flatMap { number(String($0)) } == 0
  }

  /// A time written without AM, PM, or a part of day: from 1 to 6 o'clock it
  /// is the afternoon, unless written with a leading zero ("06:30").
  private static func bareTime(hour: Int, minute: Int, hasLeadingZero: Bool) -> ClockTime? {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    let shifted = !hasLeadingZero && (1...6).contains(hour) ? hour + 12 : hour
    return ClockTime(minutes: shifted * 60 + minute, writtenHour: hour)
  }

  /// Moves a line whose time falls after the midnight ending its day onto the
  /// next day: the planned day (today when the line named none), or, for a
  /// repeat that names its weekdays or its day of the month, those days and
  /// its first occurrence, so the rule and the time agree.
  private static func moveToNextDay(_ result: inout LorvexCaptureParse) {
    guard var rule = result.recurrence, rule.byDay != nil || rule.byMonthDay != nil else {
      result.plannedDayOffset = (result.plannedDayOffset ?? 0) + 1
      return
    }
    rule.byDay = rule.byDay?.map { code in
      weekdayCodes.firstIndex(of: code).map { weekdayCodes[($0 + 1) % 7] } ?? code
    }
    // The midnight after the 31st opens the next month.
    rule.byMonthDay = rule.byMonthDay?.map { $0 % 31 + 1 }
    result.recurrence = rule
    result.recurrenceStartOffset = result.recurrenceStartOffset.map { $0 + 1 }
    result.plannedDayOffset = result.plannedDayOffset.map { $0 + 1 }
  }

  /// The value of a Chinese numeral from 0 to 59: 三, 十, 十二, 二十, 四十五, 两.
  private static func hanNumber(_ text: String) -> Int? {
    let digits: [Character: Int] = [
      "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    let characters = Array(text)
    guard let tenIndex = characters.firstIndex(of: "十") else {
      return characters.count == 1 ? digits[characters[0]] : nil
    }
    let tens = tenIndex == 0 ? 1 : (tenIndex == 1 ? digits[characters[0]] : nil)
    let rest = characters[(tenIndex + 1)...]
    guard let tens, rest.count <= 1 else { return nil }
    let ones = rest.first.map { digits[$0] } ?? 0
    guard let ones else { return nil }
    let value = tens * 10 + ones
    return value < 60 ? value : nil
  }

  private static let lengthPattern =
    #"(?<![\p{Latin}\p{N}.])(?:for\s+)?(?:(\d+)\s*h\s*(\d+)\s*m(?:in)?|(\d+(?:\.\d+)?)(?:\s*(minutes|minute|mins|min|hours|hour|hrs|hr|分钟|个?小时)|(m|h)))(?![\p{Latin}\p{N}])|(一个半小时|一个小时|一小时|两个小时|两小时|半个?小时)|(?<![\p{Latin}\p{N}])(?:for\s+)?(half an hour)(?![\p{Latin}\p{N}])"#

  /// The minutes a length match names, between 1 and 24 hours' worth.
  private static func lengthMinutes(_ match: NSTextCheckingResult, in source: String) -> Int? {
    func group(_ index: Int) -> String? {
      guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: source)
      else { return nil }
      return String(source[range])
    }
    let minutes: Int
    if let hours = group(1).flatMap(number), let rest = group(2).flatMap(number) {
      minutes = hours * 60 + rest
    } else if let amount = group(3).flatMap(LorvexNumberInput.decimal(from:)), let unit = (group(4) ?? group(5))?.lowercased() {
      let isHours = unit.hasPrefix("h") || unit.hasSuffix("小时")
      minutes = Int((isHours ? amount * 60 : amount).rounded())
    } else if let word = group(6) {
      switch word {
      case "一个半小时": minutes = 90
      case "一个小时", "一小时": minutes = 60
      case "两个小时", "两小时": minutes = 120
      default: minutes = 30
      }
    } else if group(7) != nil {
      minutes = 30
    } else {
      return nil
    }
    return minutes > 0 && minutes <= 24 * 60 ? minutes : nil
  }

  private static func weekdayIndex(_ word: String) -> Int? {
    let lower = word.lowercased()
    return weekdays.firstIndex { $0.contains(lower) }
  }

  /// Days from today to the next `weekday` (0 = Sunday), 0 when it is today.
  private static func weekdayDelta(_ weekday: Int, todayWeekday: Int) -> Int {
    (weekday + 1 - todayWeekday + 7) % 7
  }

  /// The Chinese weekday character's index, 0 = Sunday.
  private static func hanWeekday(_ character: Character) -> Int? {
    ["日": 0, "天": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6][character]
  }

  private static func dayOffset(_ word: String, todayWeekday: Int, today: Date?) -> Int? {
    let lower = word.lowercased()
    if let explicit = explicitDate(lower) {
      guard let today else { return nil }
      return offset(to: explicit, from: today)
    }
    switch lower {
    case "today", "tonight", "今天", "今晚": return 0
    case "tomorrow", "tmrw", "tmr", "明天", "明晚": return 1
    case "后天": return 2
    case "大后天": return 3
    case "next week", "下周": return 7
    case "下下周": return 14
    case "weekend", "this weekend", "周末":
      // On Saturday or Sunday the weekend is today.
      return todayWeekday == 7 || todayWeekday == 1 ? 0 : 7 - todayWeekday
    default: break
    }
    if let days = lower.firstMatch(of: /(?:in\s+)?(\d{1,3})(?:\s+days?|天后)/)?.output.1, let count = number(days) {
      return count
    }
    if let last = word.last, let weekday = hanWeekday(last), word.count >= 2 {
      if word.hasPrefix("下") {
        // 下周三: the Wednesday of next week, weeks starting on Monday.
        let todayFromMonday = (todayWeekday + 5) % 7
        let weekdayFromMonday = (weekday + 6) % 7
        return 7 - todayFromMonday + weekdayFromMonday
      }
      if word.hasPrefix("这") || word.hasPrefix("本") {
        return weekdayDelta(weekday, todayWeekday: todayWeekday)
      }
      let delta = weekdayDelta(weekday, todayWeekday: todayWeekday)
      return delta == 0 ? 7 : delta
    }
    guard let index = weekdayIndex(word) else { return nil }
    let delta = weekdayDelta(index, todayWeekday: todayWeekday)
    return delta == 0 ? 7 : delta
  }

  /// A written-out date: year (nil when not written), month (nil for "5号"),
  /// and day.
  private struct ExplicitDate {
    var year: Int?
    var month: Int?
    var day: Int
  }

  private static func explicitDate(_ word: String) -> ExplicitDate? {
    if let match = word.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
      return ExplicitDate(year: number(match.output.1), month: number(match.output.2), day: number(match.output.3) ?? 0)
    }
    if let match = word.wholeMatch(of: /(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]?/) {
      return ExplicitDate(
        year: match.output.1.flatMap(number), month: number(match.output.2), day: number(match.output.3) ?? 0)
    }
    if let match = word.wholeMatch(of: /(\d{1,2})号/) {
      return ExplicitDate(year: nil, month: nil, day: number(match.output.1) ?? 0)
    }
    let words = word.split { !$0.isLetter }.map(String.init)
    let numbers = word.matches(of: /\d+/).compactMap { number($0.output) }
    guard let month = months.firstIndex(where: { names in words.contains { names.contains($0) } }),
      let day = numbers.first
    else { return nil }
    return ExplicitDate(year: numbers.count > 1 ? numbers[1] : nil, month: month + 1, day: day)
  }

  /// The UTC midnight of a `yyyy-MM-dd` day.
  private static func dayDate(_ text: String) -> Date? {
    guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) else { return nil }
    return utcCalendar.date(
      from: DateComponents(year: number(match.output.1), month: number(match.output.2), day: number(match.output.3)))
  }

  private static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  /// Days from `today` to `date`: a date without a year is this year's, or
  /// next year's once passed; a date without a month is this month's, or next
  /// month's once passed. Nil for a day the calendar lacks, a written year's
  /// date in the past, or one more than ten years ahead.
  private static func offset(to date: ExplicitDate, from today: Date) -> Int? {
    let calendar = utcCalendar
    let now = calendar.dateComponents([.year, .month, .day], from: today)
    guard let thisYear = now.year, let thisMonth = now.month else { return nil }
    func days(year: Int, month: Int) -> Int? {
      let components = DateComponents(year: year, month: month, day: date.day)
      guard let target = calendar.date(from: components),
        calendar.component(.day, from: target) == date.day
      else { return nil }
      return calendar.dateComponents([.day], from: today, to: target).day
    }
    let result: Int?
    if let month = date.month {
      if let year = date.year {
        result = days(year: year, month: month)
      } else if let current = days(year: thisYear, month: month), current >= 0 {
        result = current
      } else {
        result = days(year: thisYear + 1, month: month)
      }
    } else if let current = days(year: thisYear, month: thisMonth), current >= 0 {
      result = current
    } else {
      result = thisMonth == 12 ? days(year: thisYear + 1, month: 1) : days(year: thisYear, month: thisMonth + 1)
    }
    guard let result, (0...3650).contains(result) else { return nil }
    return result
  }

  private static func isHan(_ character: Character) -> Bool {
    character.unicodeScalars.contains { $0.properties.isIdeographic }
  }

  /// A list name or `#word` reduced to what a match compares: its letters and
  /// digits, with case and accents folded in the user's language, so "#manana"
  /// finds the list "Mañana".
  private static func normalized(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .filter { $0.isLetter || $0.isNumber }
  }

  /// Collapses the gaps removed phrases leave behind: repeated spaces, commas
  /// with nothing between them, and separators stranded at either end ("Call
  /// the caterer ,", "：整理报销"). Connecting words ("on", "by", "for") are
  /// consumed with the phrase they introduce, so a title's own words are never
  /// trimmed.
  private static func cleanTitle(_ text: String) -> String {
    var title = text.replacingOccurrences(of: #"\s*[,，](\s*[,，])+"#, with: ",", options: .regularExpression)
    title = title.replacingOccurrences(of: #"\s+([,，])"#, with: "$1", options: .regularExpression)
    title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    title = title.replacingOccurrences(
      of: #"^[\s,;:\-–—，、：；]+|[\s,;:\-–—，、：；]+$"#, with: "", options: .regularExpression)
    return title.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
