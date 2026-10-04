import Foundation

/// Reads a capture line: the details it names, and the title left once they
/// are taken out.
///
/// The line is read with the vocabularies of the user's languages
/// (``LorvexCaptureVocabulary/vocabularies(for:)``): English and Chinese, in
/// Simplified or Traditional characters, always, and Japanese, Korean,
/// French, Portuguese, Spanish, Italian, Russian, Ukrainian, Polish, Arabic,
/// Persian, Hindi, Urdu, and Hebrew for a user who reads them. Each vocabulary
/// lists its words. The details are read one kind at a time:
///
/// 1. `#words`, read as typed. A `#word` names a list when it matches a
///    list's name or alias by its letters and digits, ignoring case and
///    accents ("#offsite2026", "#manana" for "Mañana"); any other `#word` is
///    a tag. A word's combining marks (Devanagari and Thai vowel signs,
///    Arabic harakat, Hebrew niqqud) and joiners (Persian, Urdu, Indic) are
///    part of it.
/// 2. Text that looks like a detail but is none ("до 18:00", a deadline that
///    is no start time), which a vocabulary lists as text to keep
///    (``LorvexCaptureVocabulary/keptInTitle``). It stays in the title whole:
///    no rule reads a part of it, so English does not take its "18:00" and
///    leave "до" behind.
/// 3. Date ranges ("May 3-5", "del 3 al 5 de mayo", 5月3日到5日), before
///    clock times and lengths, so a range's day numbers are not read as
///    hours or amounts ("de 3 a 5 de maio" is not 15:00 to 17:00), and before
///    the day rules, so none of them reads one end of a range. The range's
///    first day is the planned day, its last the due day, and its whole
///    text, connecting words included, is one phrase.
/// 4. Priority, length, and clock time, so the day rules judge a weekday
///    against the title words alone.
/// 5. Repeats, before days, so "every monday" and 每周一 are not read as one
///    planned Monday, and 每月5号 not as one 5th.
/// 6. The due day, before the planned day, so "by friday" and "周五前" are not
///    read as planned days.
/// 7. The planned day.
///
/// The first phrase of each kind counts; a later one stays in the title. A
/// date range takes both the planned day and the due day, so any other day
/// phrase in the line stays in the title. Text written as a range that names
/// no days ("May 5-3", an end that is not after its start) stays in the title
/// whole: no other rule reads a part of it. A time range ("3-4pm",
/// 下午3点到5点) names the time and, unless the line names a length, the
/// length. A clock time written without AM, PM, or a part of the day, named
/// with a day's evening ("tonight 8:00", "今晚8点"), is that evening, and its
/// 12 o'clock the midnight that ends the day. A time after the midnight that
/// ends its day ("at midnight", "晚上12点") moves the planned day one day on,
/// and with it the days a repeat names ("每周五晚上12点" repeats on Saturdays
/// at 00:00). Recognized phrases are removed from the title; between two
/// characters of a script written without spaces (Chinese characters,
/// Japanese kana) a phrase leaves no gap, elsewhere a space.
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
  ///   - languages: the languages the user reads, as BCP 47 codes, which
  ///     decide whether Japanese, Korean, French, Portuguese, Spanish,
  ///     Italian, Russian, Ukrainian, Polish, Arabic, Persian, Hindi, Urdu,
  ///     and Hebrew words are read.
  public static func parse(
    _ text: String, lists: [ListOption], todayWeekday: Int, today: String? = nil,
    languages: [String] = Locale.preferredLanguages
  ) -> LorvexCaptureParse {
    typealias Vocabulary = LorvexCaptureVocabulary
    var result = LorvexCaptureParse(
      title: text, plannedDayOffset: nil, dueDayOffset: nil, estimatedMinutes: nil,
      startMinutes: nil, recurrence: nil, recurrenceStartOffset: nil, listID: nil, listName: nil,
      priority: nil, tags: [], phrases: [])
    let todayDate = today.flatMap(dayDate)
    var clockTime: Vocabulary.ClockTime?
    var isPlannedForEvening = false
    // The line as typed, without the phrases recognized so far; the title
    // and the phrases come from it.
    var remaining = text
    var found: [(range: Range<String.Index>, phrase: LorvexCaptureParse.Phrase)] = []
    // The spans of `remaining` that a date range claimed without reading
    // (``LorvexCaptureVocabulary/DayRangeReading/declined``), in its UTF-16
    // offsets. No rule reads a match that overlaps one, so "May 5-3" is not
    // read as the day "May 5" with "-3" left behind.
    var claimed: [NSRange] = []

    // Matches `pattern` against `remaining` in `form`, which keeps every
    // UTF-16 offset, so one match range locates a phrase in both. The handler
    // judges the matches front to back, so the first phrase of a kind is the
    // one that counts, and reads each match's groups from the line in `form`.
    // A match that overlaps a claimed span is not offered to the handler.
    func take(
      _ pattern: String, readingAs form: (String) -> String = { $0 },
      _ handle: (NSTextCheckingResult, String) -> LorvexCaptureParse.Kind?
    ) {
      guard let regex = LorvexCapturePatterns.regex(pattern) else {
        assertionFailure("A capture pattern does not compile: \(pattern)")
        return
      }
      var matchable = form(remaining)
      let nsRange = NSRange(matchable.startIndex..., in: matchable)
      let taken = regex.matches(in: matchable, range: nsRange).compactMap {
        match -> (range: NSRange, kind: LorvexCaptureParse.Kind)? in
        guard !claimed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return nil }
        return handle(match, matchable).map { (range: match.range, kind: $0) }
      }
      // Remove back to front so removing one leaves earlier ranges valid.
      for (matchRange, kind) in taken.reversed() {
        guard let range = Range(matchRange, in: remaining), let matchableRange = Range(matchRange, in: matchable)
        else { continue }
        let matched = String(remaining[range])
        found.append((range, .init(kind: kind, text: matched.trimmingCharacters(in: .whitespaces))))
        // Between two characters of a script written without spaces the
        // phrase leaves no gap; elsewhere a space keeps the words apart.
        let joinsUnspaced =
          range.lowerBound > remaining.startIndex && range.upperBound < remaining.endIndex
          && isUnspaced(remaining[remaining.index(before: range.lowerBound)])
          && isUnspaced(remaining[range.upperBound])
        remaining.replaceSubrange(range, with: joinsUnspaced ? "" : " ")
        matchable.replaceSubrange(matchableRange, with: joinsUnspaced ? "" : " ")
        // Claimed spans after the phrase move up with the text.
        let shrink = matchRange.length - (joinsUnspaced ? 0 : 1)
        for index in claimed.indices where claimed[index].location >= NSMaxRange(matchRange) {
          claimed[index].location -= shrink
        }
      }
    }

    let vocabularies = Vocabulary.vocabularies(for: languages)
    func context(_ match: NSTextCheckingResult, _ source: String) -> Vocabulary.Match {
      Vocabulary.Match(result: match, source: source, todayWeekday: todayWeekday, today: todayDate)
    }
    // Tries every vocabulary's rules for one kind of detail. A match is taken
    // while `isOpen` holds and its rule reads a value from it.
    func read<Value>(
      _ rules: KeyPath<Vocabulary, [Vocabulary.Rule<Value>]>, as kind: LorvexCaptureParse.Kind,
      while isOpen: () -> Bool, _ record: (Value) -> Void
    ) {
      for vocabulary in vocabularies {
        for rule in vocabulary[keyPath: rules] {
          take(rule.pattern, readingAs: vocabulary.readingForm) { match, source in
            guard isOpen(), let value = rule.read(context(match, source)) else { return nil }
            record(value)
            return kind
          }
        }
      }
    }

    take(#"(?<![\p{L}\p{M}\p{N}])#([\p{L}\p{M}\p{N}_‌‍-]+)"#) { match, source in
      guard let range = Range(match.range(at: 1), in: source) else { return nil }
      let name = String(source[range])
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
      result.tags.append(name)
      return .tag
    }
    // Text to keep in the title claims its span, so no rule reads a part of it.
    for vocabulary in vocabularies {
      for rule in vocabulary.keptInTitle {
        take(rule.pattern, readingAs: vocabulary.readingForm) { match, source in
          if rule.read(context(match, source)) == true { claimed.append(match.range) }
          return nil
        }
      }
    }
    // A date range takes both day slots, so it counts only while both are
    // free; one that names no days claims its text instead.
    for vocabulary in vocabularies {
      for rule in vocabulary.dateRange {
        take(rule.pattern, readingAs: vocabulary.readingForm) { match, source in
          guard result.plannedDayOffset == nil, result.dueDayOffset == nil,
            let reading = rule.read(context(match, source))
          else { return nil }
          switch reading {
          case .range(let days):
            result.plannedDayOffset = days.start
            result.dueDayOffset = days.end
            return .when
          case .declined:
            claimed.append(match.range)
            return nil
          }
        }
      }
    }
    read(\.priority, as: .priority, while: { result.priority == nil }) { result.priority = $0 }
    read(\.length, as: .length, while: { result.estimatedMinutes == nil }) { result.estimatedMinutes = $0 }
    read(\.time, as: .time, while: { result.startMinutes == nil }) { time in
      result.startMinutes = time.minutes
      clockTime = time
      // A range's span is its length unless the line named one.
      if result.estimatedMinutes == nil { result.estimatedMinutes = time.length }
    }
    read(\.repeats, as: .repeats, while: { result.recurrence == nil }) { cadence in
      result.recurrence = cadence.rule
      if !cadence.weekdays.isEmpty {
        result.recurrenceStartOffset =
          cadence.weekdays.map { Vocabulary.weekdayDelta($0, todayWeekday: todayWeekday) }.min()
      } else if let monthDay = cadence.monthDay, let todayDate {
        result.recurrenceStartOffset = Vocabulary.offset(to: .init(day: monthDay), from: todayDate)
      }
    }
    read(\.due, as: .due, while: { result.dueDayOffset == nil }) { result.dueDayOffset = $0.offset }
    read(\.when, as: .when, while: { result.plannedDayOffset == nil }) { day in
      result.plannedDayOffset = day.offset
      isPlannedForEvening = day.isEvening
    }

    // "Tonight 8:00" and "今晚8点" mean that evening, and "今晚12点" the
    // midnight that ends it.
    if isPlannedForEvening, let time = clockTime, let hour = time.writtenHour,
      let night = Vocabulary.nightTime(hour: hour, minute: time.minutes % 60)
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

  /// Moves a line whose time falls after the midnight ending its day onto the
  /// next day: the planned day (today when the line named none), or, for a
  /// repeat that names its weekdays or its day of the month, those days and
  /// its first occurrence, so the rule and the time agree.
  private static func moveToNextDay(_ result: inout LorvexCaptureParse) {
    guard var rule = result.recurrence, rule.byDay != nil || rule.byMonthDay != nil else {
      result.plannedDayOffset = (result.plannedDayOffset ?? 0) + 1
      return
    }
    let codes = LorvexCaptureVocabulary.weekdayCodes
    rule.byDay = rule.byDay?.map { code in
      codes.firstIndex(of: code).map { codes[($0 + 1) % 7] } ?? code
    }
    // The midnight after the 31st opens the next month.
    rule.byMonthDay = rule.byMonthDay?.map { $0 % 31 + 1 }
    result.recurrence = rule
    result.recurrenceStartOffset = result.recurrenceStartOffset.map { $0 + 1 }
    result.plannedDayOffset = result.plannedDayOffset.map { $0 + 1 }
  }

  /// The UTC midnight of a `yyyy-MM-dd` day.
  private static func dayDate(_ text: String) -> Date? {
    typealias Vocabulary = LorvexCaptureVocabulary
    guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) else { return nil }
    return Vocabulary.utcCalendar.date(
      from: DateComponents(
        year: Vocabulary.number(match.output.1), month: Vocabulary.number(match.output.2),
        day: Vocabulary.number(match.output.3)))
  }

  /// True for a character of a script written without spaces between words:
  /// a Chinese character (in Chinese or Japanese) or Japanese kana.
  private static func isUnspaced(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      scalar.properties.isIdeographic
        || (0x3040...0x30FF).contains(scalar.value)  // Hiragana, Katakana
        || (0x31F0...0x31FF).contains(scalar.value)  // Katakana phonetic extensions
        || (0xFF66...0xFF9F).contains(scalar.value)  // Halfwidth Katakana
    }
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
  /// the caterer ,", "：整理报销", "اتصل بأمي ،", "मीटिंग ।", "رپورٹ بھیجیں ۔"). The
  /// Arabic comma and semicolon count as separators like the others, and the
  /// Devanagari danda and the Urdu full stop end the sentence a removed phrase
  /// stood in without a gap before it.
  /// Connecting words ("on", "by", "for") are consumed with the phrase they
  /// introduce, so a title's own words are never trimmed.
  private static func cleanTitle(_ text: String) -> String {
    var title = text.replacingOccurrences(of: #"\s*[,，](\s*[,，])+"#, with: ",", options: .regularExpression)
    title = title.replacingOccurrences(of: #"\s*،(\s*[،,，])+"#, with: "،", options: .regularExpression)
    title = title.replacingOccurrences(of: #"\s+([,，،।۔])"#, with: "$1", options: .regularExpression)
    title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    title = title.replacingOccurrences(
      of: #"^[\s,;:\-–—，、：；،؛]+|[\s,;:\-–—，、：；،؛]+$"#, with: "", options: .regularExpression)
    return title.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
