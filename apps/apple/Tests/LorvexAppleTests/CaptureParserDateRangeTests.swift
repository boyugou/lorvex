import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, today: String? = "2026-09-22") -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: today, languages: ["en"])
}

/// Days from the logical today of the capture tests, 2026-09-22, to `date`
/// (`yyyy-MM-dd`): the unit a parse reports days in.
func captureDayOffset(_ date: String) -> Int {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
  func midnight(_ text: String) -> Date {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .distantPast
  }
  return calendar.dateComponents([.day], from: midnight("2026-09-22"), to: midnight(date)).day ?? 0
}

/// A capture line made of a title and a date range written after it: the
/// title, the range as typed, and the range's first and last day as
/// `yyyy-MM-dd`.
typealias DateRangeLine = (title: String, range: String, start: String, end: String)

/// Expects each line to read as a date range: the planned day is its first
/// day, the due day its last, the title is what the range leaves, and the
/// range is the line's one phrase, of kind `.when`.
func expectDateRanges(
  _ lines: [DateRangeLine], languages: [String], sourceLocation: SourceLocation = #_sourceLocation
) {
  for line in lines {
    let text = "\(line.title) \(line.range)"
    let parsed = LorvexCaptureParser.parse(
      text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
    #expect(parsed.plannedDayOffset == captureDayOffset(line.start), "\(text): planned day", sourceLocation: sourceLocation)
    #expect(parsed.dueDayOffset == captureDayOffset(line.end), "\(text): due day", sourceLocation: sourceLocation)
    #expect(parsed.title == line.title, "\(text): title", sourceLocation: sourceLocation)
    #expect(parsed.phrases.map(\.text) == [line.range], "\(text): phrase", sourceLocation: sourceLocation)
    #expect(parsed.phrases.map(\.kind) == [.when], "\(text): phrase kind", sourceLocation: sourceLocation)
  }
}

/// Expects each line to stay in the title whole, with no day and no phrase:
/// a range that names no days, or text that is not a date range.
func expectLinesUnread(_ texts: [String], languages: [String], sourceLocation: SourceLocation = #_sourceLocation) {
  for text in texts {
    let parsed = LorvexCaptureParser.parse(
      text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
    #expect(parsed.title == text, "\(text): title", sourceLocation: sourceLocation)
    #expect(parsed.plannedDayOffset == nil, "\(text): planned day", sourceLocation: sourceLocation)
    #expect(parsed.dueDayOffset == nil, "\(text): due day", sourceLocation: sourceLocation)
    #expect(parsed.phrases.isEmpty, "\(text): phrases", sourceLocation: sourceLocation)
  }
}

/// English and Chinese date ranges, what a range does to the rest of its line,
/// and the spaced-dash rule every vocabulary that writes a day before its month
/// shares. The other languages' ranges are tested with their vocabularies.
@Suite("Capture parser date ranges")
struct CaptureParserDateRangeTests {
  @Test("English: a month written once serves both days")
  func englishMonthOnce() {
    expectDateRanges(
      [
        ("Trip", "May 3-5", "2027-05-03", "2027-05-05"),
        ("Trip", "May 3 - 5", "2027-05-03", "2027-05-05"),
        ("Trip", "May 3 – 5", "2027-05-03", "2027-05-05"),
        ("Trip", "May 3 to 5", "2027-05-03", "2027-05-05"),
        ("Trip", "May 3 through 5", "2027-05-03", "2027-05-05"),
        ("Trip", "from May 3 to 5", "2027-05-03", "2027-05-05"),
        ("Trip", "3-5 May", "2027-05-03", "2027-05-05"),
        ("Trip", "3 to 5 May", "2027-05-03", "2027-05-05"),
        ("Trip", "May 3rd-5th", "2027-05-03", "2027-05-05"),
        ("Trip", "3rd to 5th of May", "2027-05-03", "2027-05-05"),
        ("Trip to Boston", "May 3-5", "2027-05-03", "2027-05-05"),
        ("Trip", "May 3-5, 2027", "2027-05-03", "2027-05-05"),
        ("Trip", "Sep 22 - 25", "2026-09-22", "2026-09-25"),
      ], languages: ["en"])
  }

  @Test("English: a month on each side, and from and between")
  func englishMonthOnEachSide() {
    expectDateRanges(
      [
        ("Trip", "May 3 to May 5", "2027-05-03", "2027-05-05"),
        ("Trip", "from May 3 to May 5", "2027-05-03", "2027-05-05"),
        ("Trip", "from May 3 until May 5", "2027-05-03", "2027-05-05"),
        ("Trip", "between May 3 and May 5", "2027-05-03", "2027-05-05"),
        ("Trip", "between May 3rd and May 5th", "2027-05-03", "2027-05-05"),
        ("Trip", "Oct 3rd to Oct 5th", "2026-10-03", "2026-10-05"),
        ("Trip", "May 30 - June 2", "2027-05-30", "2027-06-02"),
        ("Trip", "May 30 to June 2", "2027-05-30", "2027-06-02"),
        ("Trip", "2026-10-03 to 2026-10-05", "2026-10-03", "2026-10-05"),
        ("Trip", "from 2026-10-03 to 2026-10-05", "2026-10-03", "2026-10-05"),
      ], languages: ["en"])
  }

  @Test("English: a range with no year is the next one, and its end may fall in the following year")
  func englishYears() {
    expectDateRanges(
      [
        // The 21st has passed this year: next year's.
        ("Trip", "Sep 21 - 25", "2027-09-21", "2027-09-25"),
        ("Trip", "Dec 30 - Jan 2", "2026-12-30", "2027-01-02"),
        // A year written on the end places the start in the year before it.
        ("Trip", "Dec 30 - Jan 2, 2028", "2027-12-30", "2028-01-02"),
        ("Trip", "Dec 31, 2026 - Jan 2, 2027", "2026-12-31", "2027-01-02"),
        ("Trip", "Feb 29 - Mar 1, 2028", "2028-02-29", "2028-03-01"),
      ], languages: ["en"])
  }

  @Test("English: a range whose end is not after its start, or that names no day, stays in the title whole")
  func englishDeclined() {
    expectLinesUnread(
      [
        "Trip May 5-3", "Trip 5-3 May", "Trip May 5 to 3", "Trip from May 5 to May 3",
        "Trip between May 5 and May 3", "Trip Oct 1, 2026 - Oct 1, 2026",
        "Trip Oct 5, 2026 - Oct 3, 2026", "Trip May 3 - Feb 30", "Trip May 3-45", "Trip Feb 29 - Mar 1",
        // A written year that has passed.
        "Trip Jan 3-5, 2025", "Trip Oct 5, 2025 - Oct 7",
      ], languages: ["en"])
  }

  @Test("English: time ranges, counts, weekday ranges, and days with no month are not date ranges")
  func englishNonRanges() {
    let time = parse("Meeting 3-4pm")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == 60)
    #expect(time.plannedDayOffset == nil)
    #expect(time.dueDayOffset == nil)
    #expect(time.phrases.map(\.text) == ["3-4pm"])

    // An end followed by AM or PM makes the range a time.
    let dated = parse("Trip May 3-5pm")
    #expect(dated.startMinutes == 15 * 60)
    #expect(dated.estimatedMinutes == 120)
    #expect(dated.dueDayOffset == nil)
    #expect(dated.phrases.map(\.text) == ["3-5pm"])

    // An end followed by a length unit is a day and a length.
    let length = parse("Trip Oct 5 - 30 min")
    #expect(length.plannedDayOffset == captureDayOffset("2026-10-05"))
    #expect(length.dueDayOffset == nil)
    #expect(length.estimatedMinutes == 30)
    #expect(length.phrases.map(\.text) == ["Oct 5", "30 min"])

    // The day before a number that continues is a day alone.
    for text in ["Trip May 3-5.5", "Trip May 3-5%", "Trip May 3-5-2027", "Trip May 3 and May 5"] {
      let line = parse(text)
      #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"), "\(text)")
      #expect(line.dueDayOffset == nil, "\(text)")
    }

    expectLinesUnread(
      [
        "Read pages 3-5", "Read chapters 3 to 5", "Score 3-5", "Score 3 to 5", "Buy 3-5 apples", "Call 555-1234",
        "Trip 3 to 5", "Trip the 3rd to the 5th", "Trip between 3 and 5",
      ], languages: ["en"])

    // A weekday range names no date: only one weekday is read, and the due
    // day stays free.
    for text in ["Standup Mon-Fri", "Standup from Monday to Friday", "Standup Monday through Friday"] {
      #expect(parse(text).dueDayOffset == nil, "\(text)")
    }
  }

  @Test("Chinese: dates, with 到, 至, dashes, and tildes between them")
  func chineseRanges() {
    expectDateRanges(
      [
        ("出差", "5月3日到5日", "2027-05-03", "2027-05-05"),
        ("出差", "5月3日至5日", "2027-05-03", "2027-05-05"),
        ("出差", "5月3日-5日", "2027-05-03", "2027-05-05"),
        ("出差", "5月3日～5日", "2027-05-03", "2027-05-05"),
        ("出差", "5月3日到5月5日", "2027-05-03", "2027-05-05"),
        ("出差", "5月3号到5号", "2027-05-03", "2027-05-05"),
        ("出差", "从5月3日到5月5日", "2027-05-03", "2027-05-05"),
        ("出差", "自5月3日至5月5日", "2027-05-03", "2027-05-05"),
        ("出差", "5月3日到5日前", "2027-05-03", "2027-05-05"),
        ("出差", "5月30日到6月2日", "2027-05-30", "2027-06-02"),
        ("出差", "12月30日到1月2日", "2026-12-30", "2027-01-02"),
        ("出差", "2026年12月30日到2027年1月2日", "2026-12-30", "2027-01-02"),
        // Days of the month alone are read in 号, as a day alone is.
        ("出差", "3号到5号", "2026-10-03", "2026-10-05"),
      ], languages: ["en"])

    // No space is needed around the range.
    let leading = parse("5月3日到5日出差")
    #expect(leading.title == "出差")
    #expect(leading.phrases.map(\.text) == ["5月3日到5日"])
  }

  @Test("Chinese: Traditional characters read as Simplified ones do")
  func traditionalChineseRanges() {
    expectDateRanges(
      [
        ("出差", "5月3號到5號", "2027-05-03", "2027-05-05"),
        ("出差", "從5月3日到5月5日", "2027-05-03", "2027-05-05"),
        ("旅行", "5月3日至5月5日", "2027-05-03", "2027-05-05"),
      ], languages: ["en"])
  }

  @Test("Chinese: a range whose end is not after its start stays in the title whole")
  func chineseDeclined() {
    expectLinesUnread(
      [
        "出差 5月5日到3日", "出差 5月5日到5月3日", "出差 5月3日到5月3日", "出差 5号到3号", "出差 5月3日到2月30日",
        "出差 從5月5日到5月3日",
      ], languages: ["en"])
  }

  @Test("Chinese: weekday and time ranges, counts, and a lone 日 are not date ranges")
  func chineseNonRanges() {
    let time = parse("下午3点到5点开会")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == 120)
    #expect(time.title == "开会")
    #expect(time.dueDayOffset == nil)
    #expect(time.phrases.map(\.text) == ["下午3点到5点"])

    #expect(parse("周一到周五上班").dueDayOffset == nil)
    // A day of the month alone is a date only in 号.
    expectLinesUnread(["出差 3日到5日", "出差 3天到5天", "买3-5个苹果"], languages: ["en"])

    // 到 before a thing numbered in 号 goes to it, so only the date is read,
    // whether or not the number is after the day.
    for text in ["5月3日到5号楼开会", "5月3日到3号会议室开会"] {
      let line = parse(text)
      #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"), "\(text)")
      #expect(line.dueDayOffset == nil, "\(text)")
      #expect(line.title == String(text.dropFirst(4)), "\(text)")
    }
  }

  @Test("A day alone opens a range joined by a spaced dash only after an opening word")
  func spacedDashAfterLoneDay() {
    // A spaced dash after a number sets the number apart as part of the title,
    // in every vocabulary that writes a date as its day and then its month, and
    // the date after it is read alone.
    let alone: [(text: String, languages: [String])] = [
      ("Sprint 12 - 20 May", ["en"]), ("Sprint 12 - 20 mai", ["fr"]), ("Sprint 12 - 20 de maio", ["pt"]),
      ("Sprint 12 - 20 de mayo", ["es"]), ("Sprint 12 - 20 maggio", ["it"]), ("Sprint 12 - 20 мая", ["ru"]),
      ("Sprint 12 - 20 травня", ["uk"]),
    ]
    for line in alone {
      let parsed = LorvexCaptureParser.parse(
        line.text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: line.languages)
      #expect(parsed.title == "Sprint 12", "\(line.text)")
      #expect(parsed.plannedDayOffset == captureDayOffset("2027-05-20"), "\(line.text)")
      #expect(parsed.dueDayOffset == nil, "\(line.text)")
    }

    // A dash that touches both sides, or an opening word, makes it a range.
    expectDateRanges(
      [("Sprint", "12-20 May", "2027-05-12", "2027-05-20"), ("Trip", "from 12 - 20 May", "2027-05-12", "2027-05-20")],
      languages: ["en"])
    expectDateRanges(
      [("Vacances", "12-20 mai", "2027-05-12", "2027-05-20"), ("Vacances", "du 12 - 20 mai", "2027-05-12", "2027-05-20")],
      languages: ["fr"])
    expectDateRanges([("Viagem", "de 12 - 20 de maio", "2027-05-12", "2027-05-20")], languages: ["pt"])
    expectDateRanges([("Viaje", "del 12 - 20 de mayo", "2027-05-12", "2027-05-20")], languages: ["es"])
    expectDateRanges([("Viaggio", "dal 12 - 20 maggio", "2027-05-12", "2027-05-20")], languages: ["it"])
    expectDateRanges(
      [("Поездка", "12-20 мая", "2027-05-12", "2027-05-20"), ("Поездка", "с 12 - 20 мая", "2027-05-12", "2027-05-20")],
      languages: ["ru"])
    expectDateRanges(
      [("Поїздка", "12-20 травня", "2027-05-12", "2027-05-20"), ("Поїздка", "з 12 - 20 травня", "2027-05-12", "2027-05-20")],
      languages: ["uk"])
  }

  @Test("A range takes the planned day and the due day, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let maySpan = (captureDayOffset("2027-05-03"), captureDayOffset("2027-05-05"))

    let due = parse("Trip May 3-5 by Friday")
    #expect(due.plannedDayOffset == maySpan.0)
    #expect(due.dueDayOffset == maySpan.1)
    #expect(due.title == "Trip by Friday")
    #expect(due.phrases.map(\.text) == ["May 3-5"])

    // The range counts wherever it stands in the line.
    let before = parse("Trip by Friday May 3-5")
    #expect(before.dueDayOffset == maySpan.1)
    #expect(before.title == "Trip by Friday")

    let planned = parse("Trip May 3-5 tomorrow")
    #expect(planned.plannedDayOffset == maySpan.0)
    #expect(planned.title == "Trip tomorrow")

    // The first range counts; a second stays in the title.
    let two = parse("Trip May 3-5 then June 10-12")
    #expect(two.plannedDayOffset == maySpan.0)
    #expect(two.dueDayOffset == maySpan.1)
    #expect(two.title == "Trip then June 10-12")
    #expect(two.phrases.map(\.text) == ["May 3-5"])
  }

  @Test("A range sits beside a time, a length, a repeat, a priority, and a tag")
  func rangeBesideOtherDetails() {
    let at = parse("Trip May 3-5 at 3pm")
    #expect(at.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(at.startMinutes == 15 * 60)
    #expect(at.phrases.map(\.kind) == [.when, .time])

    // The range does not take the day numbers of a time range after it.
    let times = parse("Trip May 3-5 3-4pm")
    #expect(times.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(times.startMinutes == 15 * 60)
    #expect(times.estimatedMinutes == 60)
    #expect(times.phrases.map(\.text) == ["May 3-5", "3-4pm"])

    let length = parse("Trip May 3-5 20 min")
    #expect(length.estimatedMinutes == 20)
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))

    let repeats = parse("Trip May 3-5 every week")
    #expect(repeats.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(repeats.dueDayOffset == captureDayOffset("2027-05-05"))

    let marked = parse("Trip May 3-5 p1 #travel")
    #expect(marked.priority == .p1)
    #expect(marked.tags == ["travel"])
    #expect(marked.title == "Trip")
    #expect(marked.plannedDayOffset == captureDayOffset("2027-05-03"))
  }

  @Test("A range that names no days keeps its text from every other rule")
  func declinedRangeIsNotReadInPart() {
    // Neither "May 5" nor "3" is read from "May 5-3", but the rest of the line is.
    let planned = parse("Trip May 5-3 tomorrow")
    #expect(planned.title == "Trip May 5-3")
    #expect(planned.plannedDayOffset == 1)
    #expect(planned.phrases.map(\.text) == ["tomorrow"])

    let due = parse("Trip May 5-3 by Friday")
    #expect(due.title == "Trip May 5-3")
    #expect(due.dueDayOffset == 3)
    #expect(due.plannedDayOffset == nil)

    // A range after a declined one still counts.
    let later = parse("Trip May 5-3 then May 3-5")
    #expect(later.title == "Trip May 5-3 then")
    #expect(later.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(later.dueDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("Written-out ranges need the logical today")
  func rangesNeedToday() {
    for text in ["Trip May 3-5", "出差 5月3日到5日"] {
      let line = parse(text, today: nil)
      #expect(line.title == text)
      #expect(line.plannedDayOffset == nil)
      #expect(line.dueDayOffset == nil)
      #expect(line.phrases.isEmpty)
    }
  }
}
