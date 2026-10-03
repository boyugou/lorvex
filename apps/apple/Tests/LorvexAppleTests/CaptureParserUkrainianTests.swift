import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["uk"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])

/// Ukrainian capture lines, read for a user whose languages include Ukrainian.
@Suite("Capture parser Ukrainian")
struct CaptureParserUkrainianTests {
  @Test("Days: today, tomorrow, the day after, and a number of days")
  func days() {
    let line = parse("Подзвонити Павлу завтра")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Подзвонити Павлу")
    #expect(line.phrases.map(\.text) == ["завтра"])

    let days: [(text: String, title: String, offset: Int)] = [
      ("Стоматолог сьогодні", "Стоматолог", 0),
      ("Здати звіт післязавтра", "Здати звіт", 2),
      ("Здати звіт на завтра", "Здати звіт", 1),
      ("Подзвонити СЬОГОДНІ", "Подзвонити", 0),
      ("Подзвонити через 3 дні", "Подзвонити", 3),
      ("Подзвонити через 5 днів", "Подзвонити", 5),
      ("Подзвонити через 1 день", "Подзвонити", 1),
      ("Подзвонити через два тижні", "Подзвонити", 14),
      ("Подзвонити через тиждень", "Подзвонити", 7),
      ("Прибирання на вихідних", "Прибирання", 4),
      ("Прибирання у вихідні", "Прибирання", 4),
      ("Прибирання на наступних вихідних", "Прибирання", 11),
      ("Баланс наступного тижня", "Баланс", 7),
      ("Баланс на наступному тижні", "Баланс", 7),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.title == day.title, "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
  }

  @Test("An evening makes a clock time the evening's")
  func evenings() {
    let dinner = parse("Вечеря сьогодні ввечері о 8")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "Вечеря")
    #expect(parse("Вечеря завтра ввечері").plannedDayOffset == 1)
    #expect(parse("Вечеря завтра ввечері").startMinutes == nil)
    #expect(parse("Вечеря завтра вранці").plannedDayOffset == 1)
    #expect(parse("Вечеря завтра вранці").title == "Вечеря")
    // The part of the day as a noun names no day.
    expectLinesUnread(["Зарядка вранці", "Ранкова зарядка", "Вечір п'ятниці"], languages: ["uk"])
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Басейн у п'ятницю", 3), ("Басейн в середу", 1), ("Басейн у суботу", 4), ("Басейн у неділю", 5),
      ("Басейн у понеділок", 6), ("Басейн в понеділок", 6), ("Басейн на п'ятницю", 3), ("Басейн з понеділка", 6),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "у цей вівторок" is today.
      ("Ринок у вівторок", 7), ("Ринок у цей вівторок", 0), ("Басейн у цю п'ятницю", 3), ("Басейн цієї п'ятниці", 3),
      ("Басейн у наступну п'ятницю", 10), ("Басейн наступної п'ятниці", 10), ("Басейн у наступний понеділок", 6),
      ("Басейн наступного понеділка", 6), ("Басейн У П'ЯТНИЦЮ", 3),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.title == String(weekday.text.prefix { $0 != " " }), "\(weekday.text): title")
    }
    let opening = parse("У п'ятницю подзвонити")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "подзвонити")
  }

  @Test("Written dates, with abbreviations, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Купити 5 травня", "Купити", "2027-05-05"),
      ("Купити 1 січня", "Купити", "2027-01-01"),
      ("Купити 5-го травня", "Купити", "2027-05-05"),
      ("Купити на 5 травня", "Купити", "2027-05-05"),
      ("Купити 5 січ.", "Купити", "2027-01-05"),
      ("Купити 5 вер.", "Купити", "2027-09-05"),
      ("Купити 5 вересня 2027 року", "Купити", "2027-09-05"),
      ("Купити 5 травня 2028", "Купити", "2028-05-05"),
      ("Купити у понеділок, 5 жовтня", "Купити", "2026-10-05"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A month needs a day number, an abbreviation its dot, and a date in digits is not read.
    expectLinesUnread(
      ["Травневі свята", "Звіт за травень", "Купити 5.10", "Купити 5/10", "Купити 5 січ"], languages: ["uk"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Відрядження", "з 3 по 5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "з 3 до 5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "від 3 до 5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "від 3 по 5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "з 30 травня по 2 червня", "2027-05-30", "2027-06-02"),
        ("Відрядження", "з 3 травня по 5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "3–5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "3-5 травня", "2027-05-03", "2027-05-05"),
        ("Відрядження", "з 3 по 5 травня 2027", "2027-05-03", "2027-05-05"),
        ("Відрядження до Львова", "з 3 по 5 травня", "2027-05-03", "2027-05-05"),
        ("Відпустка", "з 25 вересня по 3 жовтня", "2026-09-25", "2026-10-03"),
        ("Відпустка", "з 30 грудня по 2 січня", "2026-12-30", "2027-01-02"),
      ], languages: ["uk"])
  }

  @Test("A range whose end is not after its start, or names no month, stays in the title whole")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Відрядження з 5 по 3 травня", "Відрядження з 3 травня по 3 травня", "Відрядження з 3 по 5",
        "Відрядження 5-3 травня", "Відрядження з 5 травня по 3 травня",
      ], languages: ["uk"])
  }

  @Test("A day alone opens a range joined by a spaced dash only after an opening word")
  func spacedDash() {
    let sprint = parse("Спринт 12 - 20 травня")
    #expect(sprint.title == "Спринт 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges(
      [
        ("Спринт", "12-20 травня", "2027-05-12", "2027-05-20"),
        ("Відпустка", "з 12 - 20 травня", "2027-05-12", "2027-05-20"),
        ("Відпустка", "від 12 - 20 травня", "2027-05-12", "2027-05-20"),
      ], languages: ["uk"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("Відрядження з 3 по 5 травня завтра")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Відрядження завтра")
    let timed = parse("Відрядження з 3 по 5 травня о 9 ранку")
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Відрядження")
  }

  @Test("Due days: до, не пізніше, термін, and дедлайн")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Звіт до п'ятниці", "Звіт", 3),
      ("Звіт до 5 травня", "Звіт", captureDayOffset("2027-05-05")),
      ("Звіт термін: 5 травня", "Звіт", captureDayOffset("2027-05-05")),
      ("Звіт термін здачі 5 травня", "Звіт", captureDayOffset("2027-05-05")),
      ("Звіт дедлайн 5 травня", "Звіт", captureDayOffset("2027-05-05")),
      ("Звіт кінцевий термін п'ятниця", "Звіт", 3),
      ("Звіт не пізніше п'ятниці", "Звіт", 3),
      ("Звіт не пізніше ніж п'ятниці", "Звіт", 3),
      ("Звіт до завтра", "Звіт", 1),
      ("Звіт до наступного понеділка", "Звіт", 6),
      ("Звіт до наступної п'ятниці", "Звіт", 10),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let both = parse("Звіт до п'ятниці завтра")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "Звіт")
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      ["Звіт до 18:00", "Звіт після 18:00", "Звіт перед 18:00", "Звіт не пізніше 18:00", "Звіт не пізніше ніж 18:00"],
      languages: ["uk"])
    let day = parse("Звіт до 18:00 завтра")
    #expect(day.title == "Звіт до 18:00")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    // A time range that ends in a clock time is still a range.
    let range = parse("Зустріч з 14 до 18:00")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 240)
    #expect(range.title == "Зустріч")
    // Without Ukrainian, English reads the clock time and leaves the word.
    let english = parse("Звіт до 18:00", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "Звіт до")
  }

  @Test("Clock times: о, a part of the day, noon, and midnight")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("Зустріч о 15:00", "Зустріч", 15 * 60),
      ("Зустріч о 15", "Зустріч", 15 * 60),
      ("Зустріч о 15.30", "Зустріч", 15 * 60 + 30),
      ("Зустріч о 3 години", "Зустріч", 15 * 60),
      ("Зустріч о 5 годині", "Зустріч", 17 * 60),
      ("Зустріч о 3 годині дня", "Зустріч", 15 * 60),
      ("Зустріч о 5 годині ранку", "Зустріч", 5 * 60),
      ("Зустріч о 3 годині 30 хвилин", "Зустріч", 15 * 60 + 30),
      ("Зустріч о 3 години 30 хвилин", "Зустріч", 15 * 60 + 30),
      ("Зустріч о 3 годині 30 хв дня", "Зустріч", 15 * 60 + 30),
      ("Зустріч о 9 ранку", "Зустріч", 9 * 60),
      ("Зустріч об 11 ранку", "Зустріч", 11 * 60),
      ("Зустріч о 7 вечора", "Зустріч", 19 * 60),
      ("Зустріч о 7:30 вечора", "Зустріч", 19 * 60 + 30),
      ("Зустріч о 12 дня", "Зустріч", 12 * 60),
      ("Зустріч о 11 ночі", "Зустріч", 23 * 60),
      ("Зустріч опівдні", "Зустріч", 12 * 60),
      ("Зустріч 9 ранку", "Зустріч", 9 * 60),
      ("Зустріч 7 вечора", "Зустріч", 19 * 60),
      ("Зустріч 3 години дня", "Зустріч", 15 * 60),
      ("Зустріч 3:30 дня", "Зустріч", 15 * 60 + 30),
      ("Зустріч близько 15:00", "Зустріч", 15 * 60),
      ("Зустріч приблизно о 15:00", "Зустріч", 15 * 60),
      ("Зустріч рівно о 9", "Зустріч", 9 * 60),
      ("Концерт з 18:00", "Концерт", 18 * 60),
      ("Зустріч ОПІВДНІ", "Зустріч", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
  }

  @Test("After midnight: ночі runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("Зустріч о 2 ночі")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "Зустріч")
    let midnight = parse("Зустріч опівночі")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    let small = parse("Зустріч о 0:30 ночі")
    #expect(small.startMinutes == 30)
    #expect(small.plannedDayOffset == 1)
    // A named day keeps the time on its own night.
    let named = parse("Зустріч у п'ятницю о 2 ночі")
    #expect(named.startMinutes == 2 * 60)
    #expect(named.plannedDayOffset == 4)
    // "2 години ночі" is a time, never a length.
    let hours = parse("Зустріч 2 години ночі")
    #expect(hours.startMinutes == 2 * 60)
    #expect(hours.estimatedMinutes == nil)
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("Зустріч о 3").startMinutes == 15 * 60)
    #expect(parse("Зустріч о 6").startMinutes == 18 * 60)
    #expect(parse("Зустріч о 7").startMinutes == 7 * 60)
    #expect(parse("Зустріч о 9").startMinutes == 9 * 60)
    #expect(parse("Зустріч о 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Зустріч о 03:00").startMinutes == 3 * 60)
    #expect(parse("Зустріч о 3:00").startMinutes == 15 * 60)
    #expect(parse("Зустріч о 12 ранку").startMinutes == nil)
  }

  @Test("Time ranges: з and від with до, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Зустріч з 14 до 16", 14 * 60, 120),
      ("Зустріч від 14 до 16", 14 * 60, 120),
      ("Зустріч з 14:00 до 16:00", 14 * 60, 120),
      ("Зустріч з 9 ранку до 6 вечора", 9 * 60, 540),
      ("Зустріч з 10 до 12 годин", 10 * 60, 120),
      ("Зустріч з 14 до 18:00", 14 * 60, 240),
      ("Зустріч з 14:00-16:00", 14 * 60, 120),
      ("Зустріч о 14:00-16:00", 14 * 60, 120),
      ("Зустріч о 14:00 - 16:00", 14 * 60, 120),
      ("Зустріч з 14-16", 14 * 60, 120),
      ("Робота від 9 до 18", 9 * 60, 540),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // "До" joins the sides only after з, із, зі, or від.
    let sloppy = parse("Зустріч о 14 до 16")
    #expect(sloppy.startMinutes == 14 * 60)
    #expect(sloppy.estimatedMinutes == nil)
    #expect(sloppy.title == "Зустріч до 16")
    // English reads a range with a dash and no Ukrainian word.
    let bare = parse("Зустріч 14:00-16:00")
    #expect(bare.startMinutes == 14 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A bare hour counts as a time only before a word that can follow a time")
  func bareHours() {
    for text in [
      "Зустріч о 2 етапи", "Зустріч о 3 етапи", "Зустріч о 25:00", "Зустріч о 7 дня", "Зустріч в 3 дні",
      "Зустріч о 5 числа", "Зустріч о 5%", "Зустріч з 14 до 16 сторінок", "Іграшки від 3 до 5 років",
      "Знижка від 10 до 20%", "Робота у 3-5 разів", "Зустріч 3 дні",
      // An amount or numbered items: a word that names what is counted before
      // the range, or a percent or currency sign after a number.
      "Ціна від 10 до 20", "Вартість з 10 до 20", "Бюджет від 10 до 20 ₴", "Квиток від 10 до 20 €",
      "Квиток від 10 до 20$", "Знижка від 10 до 20 %", "Підписка о 10$", "Прочитати розділи з 3 до 5",
      "Подивитися серії з 3 до 5",
    ] {
      let line = parse(text)
      #expect(line.startMinutes == nil, "\(text)")
      #expect(line.title == text, "\(text): title")
    }
    let withPerson = parse("Зустріч о 3 з Іваном")
    #expect(withPerson.startMinutes == 15 * 60)
    #expect(withPerson.title == "Зустріч з Іваном")
    let comma = parse("Зустріч о 3, потім обід")
    #expect(comma.startMinutes == 15 * 60)
    #expect(comma.title == "Зустріч, потім обід")
    let day = parse("Зустріч о 9 ранку завтра")
    #expect(day.startMinutes == 9 * 60)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "Зустріч")
    let shop = parse("Купити молоко в магазині о 9")
    #expect(shop.startMinutes == 9 * 60)
    #expect(shop.title == "Купити молоко в магазині")
    // A day part with a bare hour that names a deadline is no time.
    let deadline = parse("Зустріч до 5 вечора завтра")
    #expect(deadline.startMinutes == nil)
    #expect(deadline.plannedDayOffset == 1)
  }

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Читати 30 хвилин", 30), ("Читати 30 хв", 30), ("Читати 30 хв.", 30), ("Читати 45 хвилин", 45),
      ("Читати 2 години", 120), ("Читати 2 год", 120), ("Читати 2 год.", 120), ("Читати 1,5 години", 90),
      ("Читати півтори години", 90), ("Читати пів години", 30), ("Читати півгодини", 30),
      ("Читати чверть години", 15), ("Читати три чверті години", 45), ("Читати одна година", 60),
      ("Читати дві години", 120), ("Читати 1 година 30 хвилин", 90), ("Читати 2 години 30 хвилин", 150),
      ("Читати на 30 хвилин", 30), ("Читати протягом 2 годин", 120), ("Читати близько 2 годин", 120),
      ("Читати 5 годин", 300),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Читати", "\(line.text): title")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
    }
    #expect(parse("Читати на 30 хвилин").phrases.map(\.text) == ["на 30 хвилин"])
  }

  @Test("An amount after через, за, по, or в names a moment, an interval, or a bound, not a length")
  func notLengths() {
    expectLinesUnread(
      [
        "Читати через 2 години", "Читати 45 хвилин тому", "Читати 2-3 години", "Читати по 2 години",
        "Читати 2 години на день", "Читати 2 години в день", "Читати кожні 2 години", "Година пік", "Читати за 2 години",
      ], languages: ["uk"])
    // "О 2 години" is a time, never a length.
    let time = parse("Зустріч о 2 години")
    #expect(time.startMinutes == 14 * 60)
    #expect(time.estimatedMinutes == nil)
    // A time and a length together.
    let both = parse("Зустріч о 15:00 на 45 хвилин")
    #expect(both.startMinutes == 15 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "Зустріч")
    let range = parse("Зустріч з 14 до 16 на 30 хвилин")
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
      ("Зарядка щодня", daily), ("Зарядка кожного дня", daily), ("Зарядка кожен день", daily),
      ("Зарядка щоранку", daily), ("Зарядка кожного ранку", daily), ("Зарядка щовечора", daily),
      ("Зарядка кожної ночі", daily), ("Зарядка кожну ніч", daily), ("Зарядка щоденно", daily),
      ("Зарядка раз на день", daily),
      ("Огляд щотижня", weekly), ("Огляд кожного тижня", weekly), ("Огляд кожен тиждень", weekly),
      ("Огляд щотижнево", weekly), ("Огляд раз на тиждень", weekly),
      ("Огляд щомісяця", monthly), ("Огляд кожного місяця", monthly), ("Огляд кожен місяць", monthly),
      ("Огляд щомісячно", monthly), ("Огляд раз на місяць", monthly),
      ("Огляд щороку", yearly), ("Огляд кожного року", yearly), ("Огляд кожен рік", yearly),
      ("Огляд щорічно", yearly), ("Огляд раз на рік", yearly),
      ("Зарядка кожні 2 дні", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Огляд кожні два тижні", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Огляд кожні 2 тижні", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Огляд раз на 2 тижні", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Огляд кожні 3 місяці", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Огляд кожні 5 років", TaskRecurrenceRule(freq: .yearly, interval: 5)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
  }

  @Test("Weekday repeats: кожного понеділка, по понеділках, and the weekdays and the weekend")
  func weekdayRepeats() {
    let coming = parse("Планерка кожного понеділка")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Планерка")
    #expect(parse("Планерка кожен понеділок").recurrence == monday)
    #expect(parse("Планерка щопонеділка").recurrence == monday)
    #expect(parse("Планерка по понеділках").recurrence == monday)
    #expect(parse("Планерка по понеділках").plannedDayOffset == nil)

    let pairs: [(text: String, days: [String])] = [
      ("Планерка кожного понеділка і четверга", ["MO", "TH"]),
      ("Планерка кожну середу і п'ятницю", ["WE", "FR"]),
      ("Планерка кожну середу, п'ятницю і суботу", ["WE", "FR", "SA"]),
      ("Планерка по понеділках і четвергах", ["MO", "TH"]),
      ("Планерка по понеділках, середах і п'ятницях", ["MO", "WE", "FR"]),
      ("Планерка по неділях", ["SU"]),
      ("Планерка щосереди", ["WE"]),
      ("Планерка щоп'ятниці", ["FR"]),
      ("Планерка по вихідних", ["SU", "SA"]),
      ("Планерка кожні вихідні", ["SU", "SA"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Планерка", "\(line.text): title")
    }
    for text in ["Планерка по буднях", "Планерка у робочі дні", "Планерка з понеділка по п'ятницю"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text)")
      #expect(parsed.title == "Планерка", "\(text): title")
    }
    // The start of a repeat on Thursday and Monday is the nearer one.
    #expect(parse("Планерка кожного понеділка і четверга").recurrenceStartOffset == 2)
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in ["Оренда 5 числа кожного місяця", "Оренда кожного 5 числа", "Оренда щомісяця 5 числа"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text)")
      #expect(parsed.title == "Оренда", "\(text): title")
    }
  }

  @Test("щодня repeats anywhere; a formal adverb repeats at the end of the line, and an adjective stays in the title")
  func cadenceAdverbs() {
    let opening = parse("Щодня перевіряти пошту")
    #expect(opening.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(opening.title == "перевіряти пошту")
    let line = parse("Перевіряти пошту щоденно")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Перевіряти пошту")
    expectLinesUnread(
      ["Щоденно перевіряти пошту", "Щоденний звіт", "Щотижневий звіт", "Щомісячні внески", "2 рази на тиждень"],
      languages: ["uk"])
  }

  @Test("Через день is both in a day and every other day, so it stays in the title")
  func everyOtherDay() {
    expectLinesUnread(["Ліки через день", "Подзвонити через день", "Прибирання через день після обіду"], languages: ["uk"])
    #expect(parse("Подзвонити через день").plannedDayOffset == nil)
    #expect(parse("Подзвонити через день").recurrence == nil)
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Подзвонити в банк високий пріоритет")
    #expect(line.priority == .p1)
    #expect(line.title == "Подзвонити в банк")
    #expect(parse("Подзвонити в банк пріоритет високий").priority == .p1)
    #expect(parse("Розібрати гараж низький пріоритет").priority == .p3)
    #expect(parse("Розібрати гараж пріоритет низький").priority == .p3)
    #expect(parse("Розібрати пошту середній пріоритет").priority == .p2)
    #expect(parse("Рахунок терміново").priority == .p1)
    #expect(parse("Рахунок терміново").title == "Рахунок")
    #expect(parse("Терміново: подзвонити сантехніку").priority == .p1)
    #expect(parse("Терміново: подзвонити сантехніку").title == "подзвонити сантехніку")
    // Without a colon or comma an opening "терміново" is a title word.
    let opening = parse("Терміново подзвонити")
    #expect(opening.priority == nil)
    #expect(opening.title == "Терміново подзвонити")
    // So is one in the middle.
    #expect(parse("Терміново потрібні документи").priority == nil)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Середа is a weekday, середовище the environment.
        "Налаштувати середовище розробки", "Тест у середовищі розробки",
        // A weekday after "за" or as an adjective names no day.
        "Звіт за понеділок", "Понеділкова планерка", "Підсумки за вівторок", "П'ятнична піца",
        // A capitalized weekday that does not open the line is a name.
        "Купити у Суботу", "Зустріч у Середу", "П'ятниця зустріч",
        // A month name as an adjective, and an hour as a noun.
        "Травневі свята", "Година пік", "Купити квітневі квитки",
        // A bare number that is a count, and a city whose name starts with в.
        "Купити 3 яблука", "Прочитати 5 розділів", "Написати 2 листи", "Зустріч на 3 особи", "В'ятка",
      ], languages: ["uk"])
    // A date still reads when its month is spelled as a date.
    #expect(parse("Купити 5 травня").plannedDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("The apostrophe is typed as U+0027, U+2019, or U+02BC, or left out, and the title keeps what was typed")
  func apostrophes() {
    for text in [
      "Подзвонити у п'ятницю", "Подзвонити у п\u{2019}ятницю", "Подзвонити у п\u{02BC}ятницю", "Подзвонити у пятницю",
    ] {
      let line = parse(text)
      #expect(line.plannedDayOffset == 3, "\(text)")
      #expect(line.title == "Подзвонити", "\(text): title")
      #expect(line.phrases.map(\.text) == [String(text.dropFirst("Подзвонити ".count))], "\(text): phrase")
    }
    for text in ["Звіт до п'ятниці", "Звіт до п\u{2019}ятниці", "Звіт до п\u{02BC}ятниці"] {
      #expect(parse(text).dueDayOffset == 3, "\(text)")
    }
    for text in ["Планерка по п'ятницях", "Планерка по п\u{2019}ятницях", "Планерка щоп\u{02BC}ятниці"] {
      #expect(parse(text).recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]), "\(text)")
    }
    #expect(parse("Планерка з понеділка по п\u{2019}ятницю").recurrence == workdays)
    #expect(parse("Огляд кожні п\u{2019}ять днів").recurrence == TaskRecurrenceRule(freq: .daily, interval: 5))
    #expect(parse("Огляд кожні пять днів").recurrence == TaskRecurrenceRule(freq: .daily, interval: 5))
    // An apostrophe typed before or after the phrase keeps its place in the title.
    let before = parse("Зв\u{2019}язатися з Іваном завтра о 15:00 Зв\u{02BC}язок")
    #expect(before.plannedDayOffset == 1)
    #expect(before.startMinutes == 15 * 60)
    #expect(before.title == "Зв\u{2019}язатися з Іваном Зв\u{02BC}язок")
    // An apostrophe joins the letters around it into one word: "в'язні" is not the word "в", and "завтра'я"
    // is not the word "завтра".
    expectLinesUnread(
      ["Зустріч о 3 в'язні", "Зустріч о 3 в\u{2019}язні", "Зустріч о 3 в\u{02BC}язні", "Кар'єра завтра'я"],
      languages: ["uk"])
  }

  @Test("Beside Ukrainian, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "uk"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "uk"]).estimatedMinutes == 20)
    let forHours = parse("Write the report for 2h", languages: ["en", "uk"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "uk"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "uk"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "uk"]).plannedDayOffset == 1)
    // English lines read the same with Ukrainian beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
    ] {
      #expect(parse(text, languages: ["en", "uk"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom завтра at 3pm", languages: ["en", "uk"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
  }

  @Test("Ukrainian words are read only for a user who reads Ukrainian")
  func languageGate() {
    let line = parse("Подзвонити післязавтра", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Подзвонити післязавтра")
    for languages in [["uk"], ["uk-UA"], ["uk_UA"], ["en-US", "uk-UA"]] {
      #expect(parse("Подзвонити післязавтра", languages: languages).plannedDayOffset == 2, "\(languages)")
    }
    // Russian words are not read for a Ukrainian reader.
    #expect(parse("Позвонить послезавтра", languages: ["uk"]).plannedDayOffset == nil)
    #expect(parse("Позвонить в пятницу", languages: ["uk"]).plannedDayOffset == nil)
    // A user who reads both gets both.
    #expect(parse("Позвонить послезавтра", languages: ["ru", "uk"]).plannedDayOffset == 2)
    #expect(parse("Подзвонити післязавтра", languages: ["ru", "uk"]).plannedDayOffset == 2)
  }
}
