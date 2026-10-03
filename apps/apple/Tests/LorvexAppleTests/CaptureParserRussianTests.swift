import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ru"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])

/// Russian capture lines, read for a user whose languages include Russian.
@Suite("Capture parser Russian")
struct CaptureParserRussianTests {
  @Test("Days: today, tomorrow, the day after, and a number of days")
  func days() {
    let line = parse("Позвонить Павлу завтра")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Позвонить Павлу")
    #expect(line.phrases.map(\.text) == ["завтра"])

    let days: [(text: String, title: String, offset: Int)] = [
      ("Стоматолог сегодня", "Стоматолог", 0),
      ("Сдать отчёт послезавтра", "Сдать отчёт", 2),
      ("Сдать отчёт на завтра", "Сдать отчёт", 1),
      ("Позвонить СЕГОДНЯ", "Позвонить", 0),
      ("Позвонить через 3 дня", "Позвонить", 3),
      ("Позвонить через 5 дней", "Позвонить", 5),
      ("Позвонить через 1 день", "Позвонить", 1),
      ("Позвонить через две недели", "Позвонить", 14),
      ("Позвонить через неделю", "Позвонить", 7),
      ("Уборка на выходных", "Уборка", 4),
      ("Уборка в выходные", "Уборка", 4),
      ("Уборка на следующих выходных", "Уборка", 11),
      ("Баланс на следующей неделе", "Баланс", 7),
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
    let dinner = parse("Ужин сегодня вечером в 8")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "Ужин")
    #expect(parse("Ужин завтра вечером").plannedDayOffset == 1)
    #expect(parse("Ужин завтра вечером").startMinutes == nil)
    #expect(parse("Ужин завтра утром").plannedDayOffset == 1)
    #expect(parse("Ужин завтра утром").title == "Ужин")
    // The part of the day as a noun names no day.
    expectLinesUnread(["Зарядка по утрам", "Утренняя зарядка", "Вечер пятницы"], languages: ["ru"])
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Бассейн в пятницу", 3), ("Бассейн в среду", 1), ("Бассейн в субботу", 4), ("Бассейн в воскресенье", 5),
      ("Бассейн в понедельник", 6), ("Бассейн на пятницу", 3), ("Бассейн с понедельника", 6),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "в этот вторник" is today.
      ("Рынок во вторник", 7), ("Рынок в этот вторник", 0), ("Бассейн в эту пятницу", 3),
      ("Бассейн в следующую пятницу", 10), ("Бассейн в следующий понедельник", 6), ("Бассейн В ПЯТНИЦУ", 3),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.title == String(weekday.text.prefix { $0 != " " }), "\(weekday.text): title")
    }
    let opening = parse("В пятницу позвонить")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "позвонить")
  }

  @Test("Written dates, with abbreviations, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Купить 5 мая", "Купить", "2027-05-05"),
      ("Купить 1 января", "Купить", "2027-01-01"),
      ("Купить 5-го мая", "Купить", "2027-05-05"),
      ("Купить на 5 мая", "Купить", "2027-05-05"),
      ("Купить 5 янв.", "Купить", "2027-01-05"),
      ("Купить 5 сент.", "Купить", "2027-09-05"),
      ("Купить 5 сентября 2027 года", "Купить", "2027-09-05"),
      ("Купить 5 мая 2028", "Купить", "2028-05-05"),
      ("Купить в понедельник, 5 октября", "Купить", "2026-10-05"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A month needs a day number, and a date in digits is not read.
    expectLinesUnread(["Майские праздники", "Отчёт за май", "Купить 5.10", "Купить 5/10"], languages: ["ru"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Командировка", "с 3 по 5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "с 3 до 5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "от 3 до 5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "от 3 по 5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "с 30 мая по 2 июня", "2027-05-30", "2027-06-02"),
        ("Командировка", "с 3 мая по 5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "3–5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "3-5 мая", "2027-05-03", "2027-05-05"),
        ("Командировка", "с 3 по 5 мая 2027", "2027-05-03", "2027-05-05"),
        ("Командировка в Казань", "с 3 по 5 мая", "2027-05-03", "2027-05-05"),
        ("Отпуск", "с 25 сентября по 3 октября", "2026-09-25", "2026-10-03"),
        ("Отпуск", "с 30 декабря по 2 января", "2026-12-30", "2027-01-02"),
      ], languages: ["ru"])
  }

  @Test("A range whose end is not after its start, or names no month, stays in the title whole")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Командировка с 5 по 3 мая", "Командировка с 3 мая по 3 мая", "Командировка с 3 по 5",
        "Командировка 5-3 мая", "Командировка с 5 мая по 3 мая",
      ], languages: ["ru"])
  }

  @Test("A day alone opens a range joined by a spaced dash only after an opening word")
  func spacedDash() {
    let sprint = parse("Спринт 12 - 20 мая")
    #expect(sprint.title == "Спринт 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges(
      [
        ("Спринт", "12-20 мая", "2027-05-12", "2027-05-20"),
        ("Отпуск", "с 12 - 20 мая", "2027-05-12", "2027-05-20"),
        ("Отпуск", "от 12 - 20 мая", "2027-05-12", "2027-05-20"),
      ], languages: ["ru"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("Командировка с 3 по 5 мая завтра")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Командировка завтра")
    let timed = parse("Командировка с 3 по 5 мая в 9 утра")
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Командировка")
  }

  @Test("Due days: до, к, не позднее, срок, and дедлайн")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Отчёт до пятницы", "Отчёт", 3),
      ("Отчёт к пятнице", "Отчёт", 3),
      ("Отчёт до 5 мая", "Отчёт", captureDayOffset("2027-05-05")),
      ("Отчёт к 5 мая", "Отчёт", captureDayOffset("2027-05-05")),
      ("Отчёт срок: 5 мая", "Отчёт", captureDayOffset("2027-05-05")),
      ("Отчёт дедлайн 5 мая", "Отчёт", captureDayOffset("2027-05-05")),
      ("Отчёт крайний срок пятница", "Отчёт", 3),
      ("Отчёт не позднее пятницы", "Отчёт", 3),
      ("Отчёт до завтра", "Отчёт", 1),
      ("Отчёт к следующему понедельнику", "Отчёт", 6),
      ("Отчёт до следующей пятницы", "Отчёт", 10),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let both = parse("Отчёт до пятницы завтра")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "Отчёт")
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      ["Отчёт до 18:00", "Отчёт к 18:00", "Отчёт после 18:00", "Отчёт перед 18:00", "Отчёт не позднее 18:00"],
      languages: ["ru"])
    let day = parse("Отчёт до 18:00 завтра")
    #expect(day.title == "Отчёт до 18:00")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    // A time range that ends in a clock time is still a range.
    let range = parse("Встреча с 14 до 18:00")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 240)
    #expect(range.title == "Встреча")
    // Without Russian, English reads the clock time and leaves the word.
    let english = parse("Отчёт до 18:00", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "Отчёт до")
  }

  @Test("Clock times: в, a part of the day, noon, and midnight")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("Встреча в 15:00", "Встреча", 15 * 60),
      ("Встреча в 15", "Встреча", 15 * 60),
      ("Встреча в 15.30", "Встреча", 15 * 60 + 30),
      ("Встреча в 15 часов", "Встреча", 15 * 60),
      ("Встреча в 15 ч", "Встреча", 15 * 60),
      ("Встреча в 3 часа дня", "Встреча", 15 * 60),
      ("Встреча в 3 часа 30 минут", "Встреча", 15 * 60 + 30),
      ("Встреча в 3 часа 30 минут дня", "Встреча", 15 * 60 + 30),
      ("Встреча в 9 утра", "Встреча", 9 * 60),
      ("Встреча в 7 вечера", "Встреча", 19 * 60),
      ("Встреча в 7:30 вечера", "Встреча", 19 * 60 + 30),
      ("Встреча в 3 дня", "Встреча", 15 * 60),
      ("Встреча в 12 дня", "Встреча", 12 * 60),
      ("Встреча в 11 ночи", "Встреча", 23 * 60),
      ("Встреча в полдень", "Встреча", 12 * 60),
      ("Встреча 9 утра", "Встреча", 9 * 60),
      ("Встреча 7 вечера", "Встреча", 19 * 60),
      ("Встреча 3 часа дня", "Встреча", 15 * 60),
      ("Встреча 3:30 дня", "Встреча", 15 * 60 + 30),
      ("Встреча около 15:00", "Встреча", 15 * 60),
      ("Встреча примерно в 15:00", "Встреча", 15 * 60),
      ("Встреча ровно в 9", "Встреча", 9 * 60),
      ("Концерт с 18:00", "Концерт", 18 * 60),
      ("Встреча в ПОЛДЕНЬ", "Встреча", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
  }

  @Test("After midnight: ночи runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("Встреча в 2 ночи")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "Встреча")
    let midnight = parse("Встреча в полночь")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    let small = parse("Встреча в 0:30 ночи")
    #expect(small.startMinutes == 30)
    #expect(small.plannedDayOffset == 1)
    // A named day keeps the time on its own night.
    let named = parse("Встреча в пятницу в 2 ночи")
    #expect(named.startMinutes == 2 * 60)
    #expect(named.plannedDayOffset == 4)
    // "2 часа ночи" is a time, never a length.
    let hours = parse("Встреча 2 часа ночи")
    #expect(hours.startMinutes == 2 * 60)
    #expect(hours.estimatedMinutes == nil)
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("Встреча в 3").startMinutes == 15 * 60)
    #expect(parse("Встреча в 6").startMinutes == 18 * 60)
    #expect(parse("Встреча в 7").startMinutes == 7 * 60)
    #expect(parse("Встреча в 9").startMinutes == 9 * 60)
    #expect(parse("Встреча в 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Встреча в 03:00").startMinutes == 3 * 60)
    #expect(parse("Встреча в 3:00").startMinutes == 15 * 60)
    #expect(parse("Встреча в 12 утра").startMinutes == nil)
  }

  @Test("Time ranges: с and от with до, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Встреча с 14 до 16", 14 * 60, 120),
      ("Встреча от 14 до 16", 14 * 60, 120),
      ("Встреча с 14:00 до 16:00", 14 * 60, 120),
      ("Встреча с 9 утра до 6 вечера", 9 * 60, 540),
      ("Встреча с 10 до 12 часов", 10 * 60, 120),
      ("Встреча с 14 до 18:00", 14 * 60, 240),
      ("Встреча с 14:00-16:00", 14 * 60, 120),
      ("Встреча в 15:00-16:00", 15 * 60, 60),
      ("Встреча в 14:00 - 16:00", 14 * 60, 120),
      ("Встреча с 14-16", 14 * 60, 120),
      ("Работа от 9 до 18", 9 * 60, 540),
      ("Уроки с 9 до 14", 9 * 60, 300),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // "До" joins the sides only after с, со, or от.
    let sloppy = parse("Встреча в 14 до 16")
    #expect(sloppy.startMinutes == 14 * 60)
    #expect(sloppy.estimatedMinutes == nil)
    #expect(sloppy.title == "Встреча до 16")
    // English reads a range with a dash and no Russian word.
    let bare = parse("Встреча 14:00-16:00")
    #expect(bare.startMinutes == 14 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A bare hour counts as a time only before a word that can follow a time")
  func bareHours() {
    for text in [
      "Встреча в 3 этапа", "Встреча в 5 раз", "Встреча в 3 года", "Встреча в 25:00", "Встреча в 7 дня",
      "Работа в 3-5 раз", "Встреча с 14 до 16 страниц", "Игрушки от 3 до 5 лет", "Скидка от 10 до 20%", "Скидка 20%",
      "Встреча в 5%", "Встреча 3 дня",
      // An amount or numbered items: a word that names what is counted before
      // the range, or a percent or currency sign after a number.
      "Цена от 10 до 20", "Стоимость с 10 до 20", "Бюджет от 10 до 20 ₽", "Билет от 10 до 20 €",
      "Билет от 10 до 20$", "Скидка от 10 до 20 %", "Подписка в 10$", "Прочитать главы с 3 до 5",
      "Посмотреть серии с 3 до 5",
    ] {
      let line = parse(text)
      #expect(line.startMinutes == nil, "\(text)")
      #expect(line.title == text, "\(text): title")
    }
    let withPerson = parse("Встреча в 3 с Иваном")
    #expect(withPerson.startMinutes == 15 * 60)
    #expect(withPerson.title == "Встреча с Иваном")
    let comma = parse("Встреча в 3, потом обед")
    #expect(comma.startMinutes == 15 * 60)
    #expect(comma.title == "Встреча, потом обед")
    let day = parse("Встреча в 9 утра завтра")
    #expect(day.startMinutes == 9 * 60)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "Встреча")
    let shop = parse("Купить молоко в магазине в 9")
    #expect(shop.startMinutes == 9 * 60)
    #expect(shop.title == "Купить молоко в магазине")
    // A day part with a bare hour that names a deadline is no time.
    let deadline = parse("Позвонить до 5 вечера завтра")
    #expect(deadline.startMinutes == nil)
    #expect(deadline.plannedDayOffset == 1)
  }

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Читать 30 минут", 30), ("Читать 30 мин", 30), ("Читать 30 мин.", 30), ("Читать 45 минут", 45),
      ("Читать 2 часа", 120), ("Читать 2 ч", 120), ("Читать 1,5 часа", 90), ("Читать 1.5 часа", 90),
      ("Читать полтора часа", 90), ("Читать полчаса", 30), ("Читать пол часа", 30), ("Читать четверть часа", 15),
      ("Читать три четверти часа", 45), ("Читать один час", 60), ("Читать два часа", 120),
      ("Читать 1 час 30 минут", 90), ("Читать 1ч 30мин", 90), ("Читать на 30 минут", 30),
      ("Читать в течение 2 часов", 120), ("Читать в течении 2 часов", 120), ("Читать около 2 часов", 120),
      ("Читать 5 часов", 300),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Читать", "\(line.text): title")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
    }
    #expect(parse("Читать на 30 минут").phrases.map(\.text) == ["на 30 минут"])
  }

  @Test("An amount after через, за, по, or в names a moment, an interval, or a bound, not a length")
  func notLengths() {
    expectLinesUnread(
      [
        "Читать через 2 часа", "Читать 45 минут назад", "Читать 2-3 часа", "Читать по 2 часа",
        "Читать 2 часа в день", "Читать 2 часа в неделю", "Читать 30 минут в день", "Читать каждые 2 часа", "Час пик",
        "Читать за 2 часа",
      ], languages: ["ru"])
    // "В 2 часа" is a time, never a length.
    let time = parse("Встреча в 2 часа")
    #expect(time.startMinutes == 14 * 60)
    #expect(time.estimatedMinutes == nil)
    // A time and a length together.
    let both = parse("Встреча в 15:00 на 45 минут")
    #expect(both.startMinutes == 15 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "Встреча")
    // A length before the clock time it is not part of.
    let range = parse("Встреча с 14 до 16 на 30 минут")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 30)
  }

  @Test("Repeats: every day, week, month, and year")
  func cadences() {
    let daily = TaskRecurrenceRule(freq: .daily)
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Зарядка каждый день", daily), ("Зарядка каждое утро", daily), ("Зарядка каждый вечер", daily),
      ("Зарядка каждую ночь", daily), ("Зарядка ежедневно", daily), ("Зарядка раз в день", daily),
      ("Обзор каждую неделю", weekly), ("Обзор еженедельно", weekly), ("Обзор раз в неделю", weekly),
      ("Обзор каждый месяц", TaskRecurrenceRule(freq: .monthly)),
      ("Обзор ежемесячно", TaskRecurrenceRule(freq: .monthly)),
      ("Обзор раз в месяц", TaskRecurrenceRule(freq: .monthly)),
      ("Обзор каждый год", TaskRecurrenceRule(freq: .yearly)),
      ("Обзор ежегодно", TaskRecurrenceRule(freq: .yearly)),
      ("Обзор раз в год", TaskRecurrenceRule(freq: .yearly)),
      ("Зарядка каждые 2 дня", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Обзор каждые две недели", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Обзор каждые 2 недели", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Обзор раз в 2 недели", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Обзор каждые 3 месяца", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Обзор каждые 5 лет", TaskRecurrenceRule(freq: .yearly, interval: 5)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
  }

  @Test("Weekday repeats: каждый понедельник, по понедельникам, and the weekdays and the weekend")
  func weekdayRepeats() {
    let coming = parse("Планёрка каждый понедельник")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Планёрка")
    #expect(parse("Планёрка по понедельникам").recurrence == monday)
    #expect(parse("Планёрка по понедельникам").plannedDayOffset == nil)

    let pairs: [(text: String, days: [String])] = [
      ("Планёрка каждый понедельник и четверг", ["MO", "TH"]),
      ("Планёрка каждый понедельник, среду и пятницу", ["MO", "WE", "FR"]),
      ("Планёрка каждую среду", ["WE"]),
      ("Планёрка по понедельникам и четвергам", ["MO", "TH"]),
      ("Планёрка по понедельникам, средам и пятницам", ["MO", "WE", "FR"]),
      ("Планёрка по воскресеньям", ["SU"]),
      ("Планёрка по выходным", ["SU", "SA"]),
      ("Планёрка каждые выходные", ["SU", "SA"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Планёрка", "\(line.text): title")
    }
    for text in ["Планёрка по будням", "Планёрка в рабочие дни", "Планёрка с понедельника по пятницу"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text)")
      #expect(parsed.title == "Планёрка", "\(text): title")
    }
    // The start of a repeat on Thursday and Monday is the nearer one.
    #expect(parse("Планёрка каждый понедельник и четверг").recurrenceStartOffset == 2)
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in ["Аренда 5-го числа каждого месяца", "Аренда каждого 5-го числа", "Аренда каждый месяц 5-го числа"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text)")
      #expect(parsed.title == "Аренда", "\(text): title")
    }
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective or an adverb elsewhere stays in the title")
  func cadenceAdverbs() {
    let line = parse("Проверять почту ежедневно")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Проверять почту")
    expectLinesUnread(
      ["Ежедневно проверять почту", "Ежедневный отчёт", "Еженедельный отчёт", "Ежемесячные взносы", "2 раза в неделю"],
      languages: ["ru"])
  }

  @Test("Через день is both in a day and every other day, so it stays in the title")
  func everyOtherDay() {
    expectLinesUnread(["Лекарство через день", "Позвонить через день", "Уборка через день после обеда"], languages: ["ru"])
    #expect(parse("Позвонить через день").plannedDayOffset == nil)
    #expect(parse("Позвонить через день").recurrence == nil)
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Позвонить в банк высокий приоритет")
    #expect(line.priority == .p1)
    #expect(line.title == "Позвонить в банк")
    #expect(parse("Позвонить в банк приоритет высокий").priority == .p1)
    #expect(parse("Разобрать гараж низкий приоритет").priority == .p3)
    #expect(parse("Разобрать гараж приоритет низкий").priority == .p3)
    #expect(parse("Разобрать почту средний приоритет").priority == .p2)
    #expect(parse("Счёт срочно").priority == .p1)
    #expect(parse("Счёт срочно").title == "Счёт")
    #expect(parse("Срочно: позвонить сантехнику").priority == .p1)
    #expect(parse("Срочно: позвонить сантехнику").title == "позвонить сантехнику")
    // Without a colon or comma an opening "срочно" is a title word.
    let opening = parse("Срочно позвонить")
    #expect(opening.priority == nil)
    #expect(opening.title == "Срочно позвонить")
    // So is one in the middle.
    #expect(parse("Срочно нужные документы").priority == nil)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Среда is also the environment.
        "Настроить среду разработки", "Тест Windows 11 в среде разработки", "Описать в среду разработки",
        // A weekday after "за" or as an adjective names no day.
        "Отчёт за понедельник", "Понедельничная планёрка", "Итоги за вторник", "Пятничная пицца",
        // A capitalized weekday that does not open the line is a name.
        "Купить в Пятнице", "Позвонить в Среду", "Пятница встреча",
        // A month name as an adjective, and an hour as a noun.
        "Майские праздники", "Час пик", "Купить апрельские билеты",
        // A bare number that is a count.
        "Купить 3 яблока", "Прочитать 5 глав", "Написать 2 письма", "Встреча на 3 человека",
      ], languages: ["ru"])
    // A date still reads when its month is spelled as a date.
    #expect(parse("Купить 5 мая").plannedDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("A typed ё is read as е, and the title keeps the ё it was typed with")
  func yo() {
    let report = parse("Отчёт до пятницы")
    #expect(report.dueDayOffset == 3)
    #expect(report.title == "Отчёт")
    #expect(parse("Отчет до пятницы").title == "Отчет")
    #expect(parse("Планёрка сегодня днём").plannedDayOffset == 0)
    #expect(parse("Планёрка сегодня днём").title == "Планёрка")
    #expect(parse("Планёрка сегодня днём").phrases.map(\.text) == ["сегодня днём"])
    // ё before and after the phrase keeps its place in the title.
    let both = parse("Приёмка товара завтра в 15:00 Ёлка")
    #expect(both.plannedDayOffset == 1)
    #expect(both.startMinutes == 15 * 60)
    #expect(both.title == "Приёмка товара Ёлка")
    // The capital Ё reads as Е and stays as typed.
    let capital = parse("Ёлка в понедельник")
    #expect(capital.plannedDayOffset == 6)
    #expect(capital.title == "Ёлка")
    // A weekday typed in capitals is the day.
    #expect(parse("Встреча ВО ВТОРНИК").plannedDayOffset == 7)
  }

  @Test("Beside Russian, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "ru"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "ru"]).estimatedMinutes == 20)
    let forHours = parse("Write the report for 2h", languages: ["en", "ru"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "ru"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "ru"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "ru"]).plannedDayOffset == 1)
    // English lines read the same with Russian beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
    ] {
      #expect(parse(text, languages: ["en", "ru"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom завтра at 3pm", languages: ["en", "ru"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
  }

  @Test("Russian words are read only for a user who reads Russian")
  func languageGate() {
    let line = parse("Позвонить завтра", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Позвонить завтра")
    for languages in [["ru"], ["ru-RU"], ["ru_RU"], ["en-US", "ru-RU"], ["ru-UA"]] {
      #expect(parse("Позвонить завтра", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Ukrainian words are not read for a Russian reader.
    #expect(parse("Подзвонити післязавтра", languages: ["ru"]).plannedDayOffset == nil)
    #expect(parse("Подзвонити у п'ятницю", languages: ["ru"]).plannedDayOffset == nil)
  }
}
