import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["pl"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])

/// Polish capture lines, read for a user whose languages include Polish.
@Suite("Capture parser Polish")
struct CaptureParserPolishTests {
  @Test("Days: today, tomorrow, the day after, and a number of days")
  func days() {
    let line = parse("Zadzwonić do mamy jutro")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Zadzwonić do mamy")
    #expect(line.phrases.map(\.text) == ["jutro"])

    let days: [(text: String, title: String, offset: Int)] = [
      ("Dentysta dziś", "Dentysta", 0),
      ("Dentysta dzisiaj", "Dentysta", 0),
      ("Kupić chleb pojutrze", "Kupić chleb", 2),
      ("Zakupy na jutro", "Zakupy", 1),
      ("Zakupy na dziś", "Zakupy", 0),
      ("Dieta od jutra", "Dieta", 1),
      ("Zadzwonić DZIŚ", "Zadzwonić", 0),
      ("Zadzwonić za 3 dni", "Zadzwonić", 3),
      ("Zadzwonić za 5 dni", "Zadzwonić", 5),
      ("Zadzwonić za 1 dzień", "Zadzwonić", 1),
      ("Zadzwonić za dwa dni", "Zadzwonić", 2),
      ("Zadzwonić za tydzień", "Zadzwonić", 7),
      ("Zadzwonić za dwa tygodnie", "Zadzwonić", 14),
      ("Wyjazd w weekend", "Wyjazd", 4),
      ("Wyjazd na weekend", "Wyjazd", 4),
      ("Wyjazd w ten weekend", "Wyjazd", 4),
      ("Wyjazd w przyszły weekend", "Wyjazd", 11),
      ("Szkolenie w przyszłym tygodniu", "Szkolenie", 7),
      ("Szkolenie na przyszły tydzień", "Szkolenie", 7),
      ("Szkolenie od przyszłego tygodnia", "Szkolenie", 7),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.title == day.title, "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Jutro rano zadzwonić")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "zadzwonić")
  }

  @Test("An evening makes a clock time the evening's")
  func evenings() {
    let dinner = parse("Kolacja dziś wieczorem o 8")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "Kolacja")
    #expect(parse("Kolacja jutro wieczorem").plannedDayOffset == 1)
    #expect(parse("Kolacja jutro wieczorem").startMinutes == nil)
    #expect(parse("Kolacja jutro rano").plannedDayOffset == 1)
    #expect(parse("Kolacja jutro rano").title == "Kolacja")
    // The part of the day as a noun names no day.
    expectLinesUnread(
      ["Spotkanie wieczorem", "Spotkanie po południu", "Spotkanie przed południem", "Sobota rano"], languages: ["pl"])
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Basen w piątek", 3), ("Basen w środę", 1), ("Basen w sobotę", 4), ("Basen w niedzielę", 5),
      ("Basen w poniedziałek", 6), ("Basen na piątek", 3), ("Basen od poniedziałku", 6),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "w ten wtorek" is today.
      ("Targ we wtorek", 7), ("Targ w ten wtorek", 0), ("Basen w tę sobotę", 4), ("Basen w ten piątek", 3),
      ("Basen w przyszły piątek", 10), ("Basen w przyszły poniedziałek", 6), ("Basen w następną sobotę", 11),
      ("Basen W PIĄTEK", 3),
      // Sunday in the plural is the same word as "w niedzielę" without its ogonek.
      ("Msza w niedziele", 5),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == String(weekday.text.prefix { $0 != " " }), "\(weekday.text): title")
    }
    let opening = parse("W piątek zadzwonić")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "zadzwonić")
    // A weekday names a day with or without a part of the day after it.
    let morning = parse("Lekarz w poniedziałek rano")
    #expect(morning.plannedDayOffset == 6)
    #expect(morning.title == "Lekarz")
  }

  @Test("Written dates, with abbreviations, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Kupić 5 maja", "Kupić", "2027-05-05"),
      ("Kupić 1 stycznia", "Kupić", "2027-01-01"),
      ("Kupić 5. maja", "Kupić", "2027-05-05"),
      ("Kupić 5-go maja", "Kupić", "2027-05-05"),
      ("Kupić na 5 maja", "Kupić", "2027-05-05"),
      ("Kupić od 5 maja", "Kupić", "2027-05-05"),
      ("Kupić dnia 5 maja", "Kupić", "2027-05-05"),
      ("Kupić 5 sty.", "Kupić", "2027-01-05"),
      ("Kupić 5 wrz.", "Kupić", "2027-09-05"),
      ("Kupić 5 września 2027 r.", "Kupić", "2027-09-05"),
      ("Kupić 5 września 2027 roku", "Kupić", "2027-09-05"),
      ("Kupić 5 maja 2028", "Kupić", "2028-05-05"),
      ("Kupić 5 maj", "Kupić", "2027-05-05"),
      ("Kupić w poniedziałek, 5 października", "Kupić", "2026-10-05"),
      ("KUPIĆ 5 MAJA", "KUPIĆ", "2027-05-05"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A month needs a day number, an abbreviation needs its dot (several are
    // ordinary words), a date in digits is not read, and a day that the month
    // does not have names no date. Easter and Christmas are not dates.
    expectLinesUnread(
      [
        "Majówka", "Raport za maj", "Kupić 5.10", "Kupić 5/10", "Kupić 31 kwietnia", "Kupić 5 sty", "Posadzić 5 lip",
        "Kupić 5 sie", "Wielkanoc", "Boże Narodzenie", "Kupić prezent na Boże Narodzenie",
      ], languages: ["pl"])
    // A name that looks like a month is left alone beside a date.
    let name = parse("Urodziny Mai 5 maja")
    #expect(name.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(name.title == "Urodziny Mai")
    // A month with a capital letter after a day number in the middle of a line
    // is part of a street or a place name, as a capitalized weekday is a name.
    expectLinesUnread(
      ["Spotkanie na ul. 3 Maja", "Dojazd Aleja 11 Listopada", "Pomnik 3 Maja", "Raport do 5 Maja"], languages: ["pl"])
    // Opening the line, or written in capitals, the month is part of a date.
    let opening = parse("3 Maja zadzwonić")
    #expect(opening.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(opening.title == "zadzwonić")
    #expect(parse("Dojazd 3 MAJA").plannedDayOffset == captureDayOffset("2027-05-03"))
    // A street name does not hide the time that follows it.
    let street = parse("Spotkanie na ul. 3 Maja o 15:00")
    #expect(street.plannedDayOffset == nil)
    #expect(street.startMinutes == 15 * 60)
    #expect(street.title == "Spotkanie na ul. 3 Maja")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Urlop", "od 3 do 5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "od 30 maja do 2 czerwca", "2027-05-30", "2027-06-02"),
        ("Urlop", "od 3 maja do 5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "między 3 a 5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "między 3 i 5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "3–5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "3-5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "od 3 do 5 maja 2027", "2027-05-03", "2027-05-05"),
        ("Urlop nad morzem", "od 3 do 5 maja", "2027-05-03", "2027-05-05"),
        ("Urlop", "od 25 września do 3 października", "2026-09-25", "2026-10-03"),
        ("Urlop", "od 30 grudnia do 2 stycznia", "2026-12-30", "2027-01-02"),
        ("Konferencja", "12-14 października", "2026-10-12", "2026-10-14"),
      ], languages: ["pl"])
  }

  @Test("A range whose end is not after its start, or whose joining word is wrong, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Urlop od 5 do 3 maja", "Urlop od 3 maja do 3 maja", "Urlop 5-3 maja", "Urlop od 5 maja do 3 maja",
      ], languages: ["pl"])
    // "Do" joins the sides only after od, and "a" only after między: the end
    // is read as a day alone.
    let missingOd = parse("Urlop 3 do 5 maja")
    #expect(missingOd.plannedDayOffset == nil)
    #expect(missingOd.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(missingOd.title == "Urlop 3")
    let missingBetween = parse("Urlop od 3 a 5 maja")
    #expect(missingBetween.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(missingBetween.dueDayOffset == nil)
    #expect(missingBetween.title == "Urlop od 3 a")
    // Days of the month with no month are no range: two bare numbers are hours.
    let bare = parse("Urlop od 3 do 5")
    #expect(bare.plannedDayOffset == nil)
    #expect(bare.dueDayOffset == nil)
    #expect(bare.startMinutes == 15 * 60)
  }

  @Test("A day alone opens a range joined by a spaced dash only after an opening word")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 maja")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges(
      [
        ("Sprint", "12-20 maja", "2027-05-12", "2027-05-20"),
        ("Urlop", "od 12 - 20 maja", "2027-05-12", "2027-05-20"),
      ], languages: ["pl"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("Urlop od 3 do 5 maja jutro")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Urlop jutro")
    let timed = parse("Urlop od 3 do 5 maja o 9")
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Urlop")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("Raport od poniedziałku do środy")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "Raport")
    #expect(span.phrases.map(\.text) == ["od poniedziałku do środy"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("Raport od poniedzialku do srody", 6, 8),
      ("Wyjazd od piątku do niedzieli", 3, 5),
      ("Wyjazd od soboty do poniedziałku", 4, 6),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("Urlop od wtorku do czwartku", 7, 9),
    ]
    for line in spans {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day")
      #expect(parsed.dueDayOffset == line.due, "\(line.text): due day")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Monday to Friday is the working week, which repeats.
    let gym = parse("Siłownia od poniedziałku do piątku")
    #expect(gym.recurrence == workdays)
    #expect(gym.plannedDayOffset == nil)
    #expect(gym.dueDayOffset == nil)
    // Capitalized weekdays in the middle of a line are names, so neither side
    // is a day.
    let names = parse("Spotkanie od Wtorku do Czwartku")
    #expect(names.plannedDayOffset == nil)
    #expect(names.dueDayOffset == nil)
    #expect(names.title == "Spotkanie od Wtorku do Czwartku")
  }

  @Test("Due days: do, najpóźniej, nie później niż, termin, and deadline")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Raport do piątku", "Raport", 3),
      ("Raport do wtorku", "Raport", 7),
      ("Raport do 5 maja", "Raport", captureDayOffset("2027-05-05")),
      ("Raport termin: 5 maja", "Raport", captureDayOffset("2027-05-05")),
      ("Raport deadline 5 maja", "Raport", captureDayOffset("2027-05-05")),
      ("Raport ostateczny termin piątek", "Raport", 3),
      ("Raport najpóźniej w piątek", "Raport", 3),
      ("Raport nie później niż do piątku", "Raport", 3),
      ("Raport do dziś", "Raport", 0),
      ("Raport do jutra", "Raport", 1),
      ("Raport do pojutrza", "Raport", 2),
      ("Raport do przyszłego piątku", "Raport", 10),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let both = parse("Raport do piątku jutro")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "Raport")
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Raport do 18:00", "Raport przed 18:00", "Raport po 18:00", "Raport przed godz. 18:00",
        "Raport po godz. 18:00", "Raport do godz. 18", "Raport najpóźniej do 18:00", "Raport najpóźniej o 18:00",
        "Raport nie później niż o 18:00", "Raport nie wcześniej niż 18:00",
      ], languages: ["pl"])
    let day = parse("Raport do 18:00 jutro")
    #expect(day.title == "Raport do 18:00")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    // A time range that ends in a clock time is still a range.
    let range = parse("Spotkanie od 14 do 18:00")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 240)
    #expect(range.title == "Spotkanie")
    // Without Polish, English reads the clock time and leaves the word.
    let english = parse("Raport do 18:00", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "Raport do")
  }

  @Test("Clock times: o, a part of the day, noon, and midnight")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("Spotkanie o 15:00", "Spotkanie", 15 * 60),
      ("Spotkanie o 15", "Spotkanie", 15 * 60),
      ("Spotkanie o 15.30", "Spotkanie", 15 * 60 + 30),
      ("Spotkanie o godz. 15", "Spotkanie", 15 * 60),
      ("Spotkanie o godzinie 15:00", "Spotkanie", 15 * 60),
      ("Spotkanie godz. 15:00", "Spotkanie", 15 * 60),
      ("Spotkanie godz. 15", "Spotkanie", 15 * 60),
      ("Spotkanie o 3 po południu", "Spotkanie", 15 * 60),
      ("Spotkanie o 3:30 po południu", "Spotkanie", 15 * 60 + 30),
      ("Spotkanie o 3 popołudniu", "Spotkanie", 15 * 60),
      ("Spotkanie o 9 rano", "Spotkanie", 9 * 60),
      ("Spotkanie o 8:30 rano", "Spotkanie", 8 * 60 + 30),
      ("Spotkanie o 7 wieczorem", "Spotkanie", 19 * 60),
      ("Spotkanie o 7:30 wieczorem", "Spotkanie", 19 * 60 + 30),
      ("Spotkanie o 12 po południu", "Spotkanie", 12 * 60),
      ("Spotkanie o 11 w nocy", "Spotkanie", 23 * 60),
      ("Spotkanie o 4 nad ranem", "Spotkanie", 4 * 60),
      ("Spotkanie 9 rano", "Spotkanie", 9 * 60),
      ("Spotkanie 7 wieczorem", "Spotkanie", 19 * 60),
      ("Spotkanie 3:30 po południu", "Spotkanie", 15 * 60 + 30),
      ("Spotkanie w południe", "Spotkanie", 12 * 60),
      ("Spotkanie w samo południe", "Spotkanie", 12 * 60),
      ("Spotkanie około 15:00", "Spotkanie", 15 * 60),
      ("Spotkanie ok. 15:00", "Spotkanie", 15 * 60),
      ("Spotkanie około 3 po południu", "Spotkanie", 15 * 60),
      ("Spotkanie na 15:00", "Spotkanie", 15 * 60),
      ("Koncert od 18:00", "Koncert", 18 * 60),
      ("Spotkanie o 15-tej", "Spotkanie", 15 * 60),
      ("Spotkanie o 3-ciej", "Spotkanie", 15 * 60),
      ("Spotkanie o 7-mej", "Spotkanie", 7 * 60),
      ("Spotkanie o 9-tej rano", "Spotkanie", 9 * 60),
      ("Spotkanie godz. 15-tej", "Spotkanie", 15 * 60),
      ("Spotkanie o 12", "Spotkanie", 12 * 60),
      ("Spotkanie W POŁUDNIE", "Spotkanie", 12 * 60),
      ("Spotkanie O 15:00", "Spotkanie", 15 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
  }

  @Test("After midnight: w nocy runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("Spotkanie o 2 w nocy")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "Spotkanie")
    let midnight = parse("Spotkanie o północy")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    let twelve = parse("Spotkanie o 12 w nocy")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    let small = parse("Spotkanie o 0:30 w nocy")
    #expect(small.startMinutes == 30)
    #expect(small.plannedDayOffset == 1)
    // A named day keeps the time on its own night.
    let named = parse("Spotkanie w piątek o 2 w nocy")
    #expect(named.startMinutes == 2 * 60)
    #expect(named.plannedDayOffset == 4)
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("Spotkanie o 3").startMinutes == 15 * 60)
    #expect(parse("Spotkanie o 6").startMinutes == 18 * 60)
    #expect(parse("Spotkanie o 7").startMinutes == 7 * 60)
    #expect(parse("Spotkanie o 9").startMinutes == 9 * 60)
    #expect(parse("Spotkanie o 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Spotkanie o 03:00").startMinutes == 3 * 60)
    #expect(parse("Spotkanie o 3:00").startMinutes == 15 * 60)
    #expect(parse("Spotkanie o 12 rano").startMinutes == nil)
  }

  @Test("Time ranges: od with do, między with a, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Spotkanie od 14 do 16", 14 * 60, 120),
      ("Spotkanie od 14:00 do 16:00", 14 * 60, 120),
      ("Spotkanie od 14.00 do 16.00", 14 * 60, 120),
      ("Spotkanie od 9 rano do 6 wieczorem", 9 * 60, 540),
      ("Spotkanie od 2 do 4 po południu", 14 * 60, 120),
      ("Spotkanie od 10 do 12 godz.", 10 * 60, 120),
      ("Spotkanie od 14 do 18:00", 14 * 60, 240),
      ("Spotkanie godz. 14-16", 14 * 60, 120),
      ("Spotkanie godz. 14:00-16:00", 14 * 60, 120),
      ("Spotkanie w godzinach 14-16", 14 * 60, 120),
      ("Spotkanie między 14:00 a 16:00", 14 * 60, 120),
      ("Spotkanie od 14:00-16:00", 14 * 60, 120),
      ("Spotkanie o 15:00-16:00", 15 * 60, 60),
      ("Spotkanie o 14:00 - 16:00", 14 * 60, 120),
      ("Praca od 9 do 17", 9 * 60, 480),
      ("Lekcje od 9 do 14", 9 * 60, 300),
      ("Biuro od 9-tej do 17-tej", 9 * 60, 480),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // "Do" joins the sides only after od, and "a" only after między, which
    // needs a colon, a part of the day, or godz. with bare hours.
    let sloppy = parse("Spotkanie o 14 do 16")
    #expect(sloppy.startMinutes == 14 * 60)
    #expect(sloppy.estimatedMinutes == nil)
    #expect(sloppy.title == "Spotkanie do 16")
    expectLinesUnread(["Spotkanie między 14 a 16", "Spotkanie od 5.10 do 7.10"], languages: ["pl"])
    // English reads a range with a dash and no Polish word.
    let bare = parse("Spotkanie 14:00-16:00")
    #expect(bare.startMinutes == 14 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A bare hour counts as a time only before a word that can follow a time")
  func bareHours() {
    for text in [
      "Spotkanie o 3 osoby", "Spotkanie o 7 dni", "Spotkanie o 25:00", "Książka o 3 psach", "Film o 7 samurajach",
      "Spotkanie od 14 do 16 stron", "Wiek od 3 do 5 lat",
      // An amount or numbered items: a word that names what is counted before
      // the range, or a percent or currency sign after a number.
      "Obniżka o 15%", "Obniżka o 15 %", "Obniżka o 15 zł", "Obniżka o 15 PLN", "Obniżka o 15 euro",
      "Obniżka o 15$", "Spotkanie o 15 złotych", "Cena od 10 do 20", "Cena od 10 do 20 zł", "Koszt od 10 do 20 €",
      "Bilety od 10 do 20$", "Zniżka od 10 do 20%", "Zniżka od 10 do 20 %", "Bilety od 10 do 20 euro",
      "Przeczytać rozdziały od 3 do 5",
    ] {
      let line = parse(text)
      #expect(line.startMinutes == nil, "\(text)")
      #expect(line.title == text, "\(text): title")
    }
    let withPerson = parse("Spotkanie o 3 z Anią")
    #expect(withPerson.startMinutes == 15 * 60)
    #expect(withPerson.title == "Spotkanie z Anią")
    let comma = parse("Spotkanie o 3, potem obiad")
    #expect(comma.startMinutes == 15 * 60)
    #expect(comma.title == "Spotkanie, potem obiad")
    let day = parse("Spotkanie o 9 rano jutro")
    #expect(day.startMinutes == 9 * 60)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "Spotkanie")
    let shop = parse("Kupić mleko w sklepie o 9")
    #expect(shop.startMinutes == 9 * 60)
    #expect(shop.title == "Kupić mleko w sklepie")
    let cafe = parse("Spotkanie o 3 w kawiarni")
    #expect(cafe.startMinutes == 15 * 60)
    #expect(cafe.title == "Spotkanie w kawiarni")
    // A day part with a bare hour that names a deadline is no time.
    let deadline = parse("Zadzwonić do 5 po południu jutro")
    #expect(deadline.startMinutes == nil)
    #expect(deadline.plannedDayOffset == 1)
  }

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Czytać 30 minut", 30), ("Czytać 30 min", 30), ("Czytać 30 min.", 30), ("Czytać 45 minut", 45),
      ("Czytać 2 godziny", 120), ("Czytać 2 godz.", 120), ("Czytać 2 h", 120), ("Czytać 2h", 120),
      ("Czytać 5 godzin", 300), ("Czytać 1 godzinę", 60), ("Czytać 1,5 godziny", 90), ("Czytać 1.5 godziny", 90),
      ("Czytać półtorej godziny", 90), ("Czytać pół godziny", 30), ("Czytać kwadrans", 15),
      ("Czytać trzy kwadranse", 45), ("Czytać dwie godziny", 120), ("Czytać 1 godzina 30 minut", 90),
      ("Czytać 1 godz. 30 min", 90), ("Czytać 1h 30 min", 90), ("Czytać na 30 minut", 30),
      ("Czytać na godzinę", 60), ("Czytać przez 2 godziny", 120), ("Czytać około 2 godzin", 120),
      ("Czytać ok. 2 godzin", 120),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Czytać", "\(line.text): title")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
    }
    #expect(parse("Czytać na 30 minut").phrases.map(\.text) == ["na 30 minut"])
  }

  @Test("An amount after za, co, po, o, or w, or before temu or dziennie, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, or a bound, whether the unit is spelled out
        // or abbreviated the way English also reads it.
        "Czytać za 2 godziny", "Czytać za 15 min", "Czytać co 2 godziny", "Czytać co 2h", "Czytać o 15 minut",
        "Czytać po 2 godziny", "Czytać do 2 godzin", "Czytać do 30 min", "Czytać w ciągu 2 godzin", "Czytać w 2h",
        "Czytać ponad 2 godziny", "Czytać mniej niż 2 godziny", "Film o 2h",
        // The past, a difference, and a rate.
        "Czytać 30 minut temu", "Czytać 30 min temu", "Czytać 15 minut wcześniej", "Czytać 2 godziny dziennie",
        "Czytać 2h dziennie", "Czytać 30 min dziennie", "Czytać 2h w tygodniu", "Czytać 2 godziny na tydzień",
        // A range of amounts, and an hour as a noun.
        "Czytać 2-3 godziny", "Godzina szczytu", "Czytać godzinę",
      ], languages: ["pl"])
    // The phrase around an amount that is no length still reads.
    let day = parse("Zadzwonić za 15 min jutro")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "Zadzwonić za 15 min")
    let time = parse("Spotkanie jutro o 15:00 za 2 godziny")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "Spotkanie za 2 godziny")
    // A time and a length together.
    let both = parse("Spotkanie o 15:00 na 45 minut")
    #expect(both.startMinutes == 15 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "Spotkanie")
    // A length before the clock time it is not part of.
    let range = parse("Spotkanie od 14 do 16 na 30 minut")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 30)
  }

  @Test("Repeats: every day, week, month, and year")
  func cadences() {
    let daily = TaskRecurrenceRule(freq: .daily)
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Ćwiczenia każdego dnia", daily), ("Ćwiczenia każdy dzień", daily), ("Ćwiczenia co rano", daily),
      ("Ćwiczenia co wieczór", daily), ("Ćwiczenia co noc", daily), ("Ćwiczenia codziennie", daily),
      ("Ćwiczenia raz dziennie", daily),
      ("Przegląd co tydzień", weekly), ("Przegląd każdego tygodnia", weekly), ("Przegląd każdy tydzień", weekly),
      ("Przegląd cotygodniowo", weekly), ("Przegląd raz w tygodniu", weekly),
      ("Przegląd co miesiąc", monthly), ("Przegląd każdego miesiąca", monthly), ("Przegląd comiesięcznie", monthly),
      ("Przegląd raz w miesiącu", monthly),
      ("Przegląd co roku", yearly), ("Przegląd każdego roku", yearly), ("Przegląd corocznie", yearly),
      ("Przegląd raz w roku", yearly),
      ("Ćwiczenia co 2 dni", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Ćwiczenia co drugi dzień", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Przegląd co dwa tygodnie", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Przegląd co 2 tygodnie", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Przegląd co 2 tyg.", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Przegląd co drugi tydzień", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Przegląd raz na dwa tygodnie", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Przegląd co trzy miesiące", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Przegląd co 3 mies.", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Przegląd co 5 lat", TaskRecurrenceRule(freq: .yearly, interval: 5)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
  }

  @Test("Weekday repeats: co poniedziałek, w poniedziałki, and the working days and the weekend")
  func weekdayRepeats() {
    let coming = parse("Siłownia co poniedziałek")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Siłownia")
    #expect(parse("Siłownia w poniedziałki").recurrence == monday)
    #expect(parse("Siłownia w poniedziałki").plannedDayOffset == nil)
    #expect(parse("Siłownia poniedziałkami").recurrence == monday)
    #expect(parse("Siłownia w każdy poniedziałek").recurrence == monday)
    #expect(parse("Siłownia każdego poniedziałku").recurrence == monday)

    let pairs: [(text: String, days: [String])] = [
      ("Siłownia co poniedziałek i czwartek", ["MO", "TH"]),
      ("Siłownia co poniedziałek, środę i piątek", ["MO", "WE", "FR"]),
      ("Siłownia co środę", ["WE"]),
      ("Siłownia co sobotę", ["SA"]),
      ("Siłownia co niedzielę", ["SU"]),
      ("Siłownia w każdą sobotę", ["SA"]),
      ("Siłownia każdej soboty", ["SA"]),
      ("Siłownia w poniedziałki i czwartki", ["MO", "TH"]),
      ("Siłownia w poniedziałki, środy i piątki", ["MO", "WE", "FR"]),
      ("Siłownia we wtorki i czwartki", ["TU", "TH"]),
      ("Siłownia w soboty i niedziele", ["SU", "SA"]),
      ("Siłownia w niedziele i soboty", ["SU", "SA"]),
      ("Siłownia w weekendy", ["SU", "SA"]),
      ("Siłownia co weekend", ["SU", "SA"]),
      ("Siłownia w każdy weekend", ["SU", "SA"]),
      ("Siłownia weekendami", ["SU", "SA"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Siłownia", "\(line.text): title")
    }
    let everyOther = parse("Siłownia co drugi poniedziałek")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    let everyOtherFeminine = parse("Siłownia co drugą środę")
    #expect(everyOtherFeminine.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["WE"]))
    for text in [
      "Siłownia w dni robocze", "Siłownia w dni powszednie", "Siłownia od poniedziałku do piątku",
      "Siłownia codziennie od poniedziałku do piątku", "Siłownia w każdy dzień roboczy",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text)")
      #expect(parsed.title == "Siłownia", "\(text): title")
    }
    // The start of a repeat on Thursday and Monday is the nearer one.
    #expect(parse("Siłownia co poniedziałek i czwartek").recurrenceStartOffset == 2)
    // Sunday in the plural is the day alone, since without its ogonek it is the
    // same word as "w niedzielę".
    #expect(parse("Siłownia w niedziele").recurrence == nil)
    #expect(parse("Siłownia w niedziele").plannedDayOffset == 5)
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "Czynsz 5. każdego miesiąca", "Czynsz 5 każdego miesiąca", "Czynsz 5-go każdego miesiąca",
      "Czynsz 5. dnia każdego miesiąca", "Czynsz do 5. każdego miesiąca", "Czynsz każdego 5.", "Czynsz każdego 5-go",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text)")
      #expect(parsed.title == "Czynsz", "\(text): title")
    }
    // A day with its month name is a date, not a repeat.
    let date = parse("Czynsz każdego 5 maja")
    #expect(date.recurrence == nil)
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective or an adverb elsewhere stays in the title")
  func cadenceAdverbs() {
    let line = parse("Sprawdzać pocztę codziennie")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Sprawdzać pocztę")
    let morning = parse("Ćwiczyć codziennie rano")
    #expect(morning.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(morning.title == "Ćwiczyć")
    expectLinesUnread(
      [
        "Codziennie sprawdzać pocztę", "Codzienny raport", "Cotygodniowy raport", "Raport cotygodniowy",
        "Comiesięczne opłaty", "Spotkanie 2 razy w tygodniu", "Spotkanie dwa razy w tygodniu", "Ubrania na co dzień",
      ], languages: ["pl"])
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Zadzwonić do banku wysoki priorytet")
    #expect(line.priority == .p1)
    #expect(line.title == "Zadzwonić do banku")
    #expect(parse("Zadzwonić do banku priorytet wysoki").priority == .p1)
    #expect(parse("Zadzwonić do banku priorytet: wysoki").priority == .p1)
    #expect(parse("Zadzwonić do banku najwyższy priorytet").priority == .p1)
    #expect(parse("Zadzwonić do banku priorytet najwyższy").priority == .p1)
    #expect(parse("Posprzątać garaż niski priorytet").priority == .p3)
    #expect(parse("Posprzątać garaż priorytet niski").priority == .p3)
    #expect(parse("Posprzątać garaż priorytet minimalny").priority == .p3)
    #expect(parse("Przejrzeć pocztę średni priorytet").priority == .p2)
    #expect(parse("Przejrzeć pocztę priorytet normalny").priority == .p2)
    #expect(parse("Rachunek pilne").priority == .p1)
    #expect(parse("Rachunek pilne").title == "Rachunek")
    #expect(parse("Rachunek pilnie").priority == .p1)
    #expect(parse("Pilne: zadzwonić do hydraulika").priority == .p1)
    #expect(parse("Pilne: zadzwonić do hydraulika").title == "zadzwonić do hydraulika")
    #expect(parse("Pilne, zadzwonić do hydraulika").priority == .p1)
    // Without a colon or comma an opening "pilne" is a title word.
    let opening = parse("Pilne zadzwonić")
    #expect(opening.priority == nil)
    #expect(opening.title == "Pilne zadzwonić")
    // So is one in the middle.
    #expect(parse("Pilne dokumenty").priority == nil)
    #expect(parse("Zrobić pilne zakupy").priority == nil)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // A weekday alone, after "z", or as a name.
        "Raport z poniedziałku", "Sobota rano", "Piątek spotkanie", "Zadzwonić do Soboty", "Kupić w Piątek",
        "Zebranie z piątku",
        // "W" before something that is not a day.
        "Zadzwonić w sprawie 3 faktur",
        // A bare number that is a count.
        "Kupić 3 jabłka", "Przeczytać 5 rozdziałów", "Napisać 2 listy", "Stolik na 4 osoby", "Bilety na 5.10",
        "Wizyta od 5.10",
      ], languages: ["pl"])
    // A date still reads when its month is spelled as a date.
    #expect(parse("Kupić 5 maja").plannedDayOffset == captureDayOffset("2027-05-05"))
    // "W piątek" before other words is the day.
    let sprawa = parse("Zadzwonić w piątek w sprawie umowy")
    #expect(sprawa.plannedDayOffset == 3)
    #expect(sprawa.title == "Zadzwonić w sprawie umowy")
  }

  @Test("Polish letters are read as the plain letter and ł as l, and the title keeps the letters it was typed with")
  func diacritics() {
    let report = parse("Raport do piątku")
    #expect(report.dueDayOffset == 3)
    #expect(report.title == "Raport")
    #expect(parse("Raport do piatku").dueDayOffset == 3)
    #expect(parse("Spotkanie w środę").plannedDayOffset == 1)
    #expect(parse("Spotkanie w srode").plannedDayOffset == 1)
    #expect(parse("Wyjazd 5 października").plannedDayOffset == captureDayOffset("2026-10-05"))
    #expect(parse("Wyjazd 5 pazdziernika").plannedDayOffset == captureDayOffset("2026-10-05"))
    #expect(parse("Wizyta o 3 po południu").startMinutes == 15 * 60)
    #expect(parse("Wizyta o 3 po poludniu").startMinutes == 15 * 60)
    #expect(parse("Ćwiczenia o północy").startMinutes == 0)
    #expect(parse("Cwiczenia o polnocy").startMinutes == 0)
    #expect(parse("Czytać pół godziny").estimatedMinutes == 30)
    #expect(parse("Czytac pol godziny").estimatedMinutes == 30)
    #expect(parse("Czytać półtorej godziny").estimatedMinutes == 90)
    // ł is read as l, and it stays ł in the title.
    let gym = parse("Siłownia co tydzień")
    #expect(gym.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(gym.title == "Siłownia")
    #expect(parse("Silownia co tydzien").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(parse("Silownia co tydzien").title == "Silownia")
    #expect(parse("SIŁOWNIA CO TYDZIEŃ").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(parse("SIŁOWNIA CO TYDZIEŃ").title == "SIŁOWNIA")
    // Letters before and after the phrase keep their place in the title.
    let both = parse("Łódź zakupy jutro o 15:00 Żubr")
    #expect(both.plannedDayOffset == 1)
    #expect(both.startMinutes == 15 * 60)
    #expect(both.title == "Łódź zakupy Żubr")
    #expect(parse("Łazienka w piątek").plannedDayOffset == 3)
    #expect(parse("Łazienka w piątek").title == "Łazienka")
    // Capitals read like lower case letters.
    #expect(parse("ZADZWONIĆ JUTRO").plannedDayOffset == 1)
    #expect(parse("SPOTKANIE W PIĄTEK O 15:00").startMinutes == 15 * 60)
    #expect(parse("Spotkanie WE WTOREK").plannedDayOffset == 7)
    #expect(parse("Raport DO PIĄTKU").dueDayOffset == 3)
  }

  @Test("Beside Polish, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "pl"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "pl"]).estimatedMinutes == 20)
    let forHours = parse("Write the report for 2h", languages: ["en", "pl"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "pl"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "pl"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "pl"]).plannedDayOffset == 1)
    // English lines read the same with Polish beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min",
    ] {
      #expect(parse(text, languages: ["en", "pl"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom jutro at 3pm", languages: ["en", "pl"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting w piątek at 3pm", languages: ["en", "pl"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
  }

  @Test("Polish words are read only for a user who reads Polish")
  func languageGate() {
    let line = parse("Zadzwonić jutro", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Zadzwonić jutro")
    for languages in [["pl"], ["pl-PL"], ["pl_PL"], ["en-US", "pl-PL"], ["PL"]] {
      #expect(parse("Zadzwonić jutro", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Russian and Ukrainian words are not read for a Polish reader.
    #expect(parse("Позвонить завтра", languages: ["pl"]).plannedDayOffset == nil)
    #expect(parse("Подзвонити післязавтра", languages: ["pl"]).plannedDayOffset == nil)
    // Polish words are not read for a Russian reader.
    #expect(parse("Zadzwonić jutro", languages: ["ru"]).plannedDayOffset == nil)
  }
}
