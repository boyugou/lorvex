import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ro"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["ro"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weekly = TaskRecurrenceRule(freq: .weekly)
private let monthly = TaskRecurrenceRule(freq: .monthly)
private let yearly = TaskRecurrenceRule(freq: .yearly)

/// The unicode scalars of `text`. A title is compared by them where the typed
/// form matters, since `String` equality treats a letter with a combining mark
/// as equal to its precomposed form.
private func scalars(_ text: String) -> [Unicode.Scalar] {
  Array(text.unicodeScalars)
}

/// `text` with the cedilla letters ş, ţ, Ş, Ţ in place of the comma-below
/// letters ș, ț, Ș, Ț: the forms older keyboards and fonts produce.
private func withCedillas(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{0219}", with: "\u{015F}").replacingOccurrences(of: "\u{021B}", with: "\u{0163}")
    .replacingOccurrences(of: "\u{0218}", with: "\u{015E}").replacingOccurrences(of: "\u{021A}", with: "\u{0162}")
}

/// `text` with the comma-below letters ș, ț, Ș, Ț in place of the cedilla
/// letters, which is the form Romanian is written in.
private func withCommas(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{015F}", with: "\u{0219}").replacingOccurrences(of: "\u{0163}", with: "\u{021B}")
    .replacingOccurrences(of: "\u{015E}", with: "\u{0218}").replacingOccurrences(of: "\u{0162}", with: "\u{021A}")
}

/// `text` as someone types it without diacritics: ă, â, î, ș, ț as a, a, i, s, t.
private func withoutDiacritics(_ text: String) -> String {
  withCommas(text).folding(options: .diacriticInsensitive, locale: nil)
}

/// The three spellings of a Romanian line: comma-below letters, cedilla
/// letters, and no diacritics.
private let spellings: [@Sendable (String) -> String] = [withCommas, withCedillas, withoutDiacritics]

/// Romanian capture lines, read for a user whose languages include Romanian.
@Suite("Capture parser Romanian")
struct CaptureParserRomanianTests {
  // MARK: - Days

  @Test("Days: azi, mâine, poimâine, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Dentist mâine")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Dentist")
    #expect(line.phrases.map(\.text) == ["mâine"])

    let days: [(text: String, offset: Int)] = [
      ("Dentist azi", 0), ("Dentist astăzi", 0), ("Dentist diseară", 0), ("Dentist deseară", 0),
      ("Dentist în seara asta", 0), ("Dentist în seara aceasta", 0), ("Dentist în noaptea asta", 0),
      ("Dentist azi dimineață", 0), ("Dentist azi seara", 0),
      ("Dentist mâine", 1), ("Dentist mâine dimineață", 1), ("Dentist mâine seara", 1), ("Dentist mâine seară", 1),
      ("Dentist mâine după-amiază", 1), ("Dentist mâine noaptea", 1),
      ("Dentist poimâine", 2), ("Dentist poimâine seara", 2),
      ("Dentist peste o zi", 1), ("Dentist peste 3 zile", 3), ("Dentist peste trei zile", 3),
      ("Dentist peste o săptămână", 7), ("Dentist peste 2 săptămâni", 14), ("Dentist peste două săptămâni", 14),
      ("Dentist săptămâna viitoare", 7), ("Dentist în săptămâna viitoare", 7), ("Dentist săptămâna următoare", 7),
      ("Dentist săptămâna care vine", 7),
      ("Dentist weekendul acesta", 4), ("Dentist weekendul asta", 4), ("Dentist în weekend", 4),
      ("Dentist în acest weekend", 4), ("Dentist acest weekend", 4), ("Dentist weekendul care vine", 4),
      ("Dentist weekendul viitor", 11),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Dentist", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Mâine dentist")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "dentist")
    // "În 3 zile" may mean in 3 days or within 3 days, and a month ahead has no day offset.
    expectLinesUnread(
      ["Dentist în 3 zile", "Dentist peste câteva zile", "Dentist peste o lună", "Dentist peste un an"],
      languages: ["ro"])
  }

  @Test("Luni is Monday, and after a count or before de zile it is the plural of lună and stays in the title")
  func luniIsMondayOrMonths() {
    for text in ["Dentist luni", "Dentist Luni", "Dentist LUNI", "Dentist la luni", "Dentist de luni"] {
      #expect(parse(text).plannedDayOffset == 6, "\(text)")
      #expect(parse(text).title == "Dentist", "\(text): title")
    }
    expectLinesUnread(
      [
        "Raport peste 3 luni", "Raport peste două luni", "Raport peste 6 luni", "Raport peste câteva luni",
        "Raport 3 luni", "Raport 30 de luni", "Raport câteva luni", "Raport luni de zile", "Raport luni întregi",
        "Concediu peste două luni", "Programează o vizită la medic peste 3 luni",
      ], languages: ["ro"])
  }

  @Test("Mai is the month only where it is no adverb of comparison")
  func mai() {
    for (text, title, date) in [
      ("Concediu 1 mai", "Concediu", "2027-05-01"), ("Dentist 3 mai", "Dentist", "2027-05-03"),
      ("Dentist 1 mai 2027", "Dentist", "2027-05-01"),
    ] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(date), "\(text)")
      #expect(parsed.title == title, "\(text): title")
    }
    expectLinesUnread(
      [
        "Dentist 3 mai multe", "Dentist 5 mai târziu", "Vacanța în mai", "Mai", "Raport mai 2027", "Mai multe idei",
        "Mai verifică o dată",
      ], languages: ["ro"])
  }

  @Test("An evening makes a clock time the evening's")
  func evenings() {
    for (line, day, minutes) in [
      ("Ședință diseară la 7", 0, 19 * 60), ("Ședință diseară la 8", 0, 20 * 60),
      ("Ședință diseară 7:30", 0, 19 * 60 + 30), ("Ședință mâine seara la 7", 1, 19 * 60),
      ("Ședință mâine seara la 7:30", 1, 19 * 60 + 30), ("Ședință mâine seară 8:30", 1, 20 * 60 + 30),
      ("Ședință în seara asta la 8", 0, 20 * 60), ("Ședință vineri seara la 8", 3, 20 * 60),
      ("Ședință vineri seara la ora 8", 3, 20 * 60),
      // Another part of the day, or none, keeps the hour as it is.
      ("Ședință mâine dimineață la 7", 1, 7 * 60), ("Ședință mâine dimineață la 8", 1, 8 * 60),
      ("Ședință mâine la 7", 1, 7 * 60), ("Ședință mâine la 8", 1, 8 * 60), ("Ședință azi la 7", 0, 7 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Ședință", "\(line): title")
    }
    // Twelve in the evening is midnight, which ends the day.
    let tonight = parse("Ședință diseară la 12")
    #expect(tonight.plannedDayOffset == 1)
    #expect(tonight.startMinutes == 0)
    // An evening on its own plans the day and no time, and twelve after it is no hour.
    let evening = parse("Ședință mâine seara")
    #expect(evening.plannedDayOffset == 1)
    #expect(evening.startMinutes == nil)
    let late = parse("Ședință mâine seara la 12")
    #expect(late.plannedDayOffset == 1)
    #expect(late.startMinutes == nil)
    #expect(late.title == "Ședință la 12")
    expectLinesUnread(["Ședință la 12 seara", "Ședință seara la 12"], languages: ["ro"])
    // The evening meals give a bare hour the evening, as "diseară" does.
    for (line, minutes, title) in [
      ("Cina la 8", 20 * 60, "Cina"), ("Cină la 7", 19 * 60, "Cină"), ("Cina la 8 seara", 20 * 60, "Cina"),
      ("Prânz la 1", 13 * 60, "Prânz"),
    ] {
      let meal = parse(line)
      #expect(meal.startMinutes == minutes, "\(line)")
      #expect(meal.title == title, "\(line): title")
    }
    // The part of the day as a noun names no day or time.
    expectLinesUnread(
      ["Cafeaua de dimineață", "Cina de seară", "Seara de film", "Dimineața devreme", "Plimbare după masă"],
      languages: ["ro"])
  }

  @Test("A line that is nothing but a detail keeps its text as the title")
  func lineOfDetailsOnly() {
    expectLinesUnread(
      ["Seara la 8", "Dimineața la 7", "Seara 8:30", "Joi la 5", "Ora 5", "Joi, 15 octombrie", "Mâine", "Luni"],
      languages: ["ro"])
  }

  @Test("Past days are not read")
  func pastDays() {
    expectLinesUnread(
      [
        "Dentist ieri", "Dentist alaltăieri", "Dentist alaltaieri", "Dentist ieri seara", "Dentist ieri dimineață",
        "Dentist luni trecută", "Dentist marți trecută", "Dentist vinerea trecută", "Dentist săptămâna trecută",
        "Dentist weekendul trecut", "Dentist luni anterioară",
      ], languages: ["ro"])
    // The time that follows a past day still reads.
    let time = parse("Dentist ieri la ora 3")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Dentist ieri")
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Dentist luni", 6), ("Dentist marți", 7), ("Dentist miercuri", 1), ("Dentist joi", 2), ("Dentist vineri", 3),
      ("Dentist sâmbătă", 4), ("Dentist duminică", 5), ("Dentist pe vineri", 3), ("Dentist în joi", 2),
      // The definite forms of Saturday and Sunday read like the plain names, and name the day.
      ("Dentist sâmbăta", 4), ("Dentist duminica", 5),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "marți asta" is today.
      ("Dentist marți asta", 0), ("Dentist marți aceasta", 0), ("Dentist miercuri asta", 1),
      ("Dentist vineri asta", 3), ("Dentist vineri care vine", 3),
      ("Dentist luni viitoare", 6), ("Dentist luni următoare", 6), ("Dentist luni care vine", 6),
      ("Dentist marți viitoare", 7), ("Dentist joi viitoare", 9), ("Dentist vineri viitoare", 10),
      ("Dentist vineri următoare", 10), ("Dentist vinerea viitoare", 10), ("Dentist lunea viitoare", 6),
      ("Dentist săptămâna viitoare vineri", 10), ("Dentist vineri, săptămâna viitoare", 10),
      ("Dentist luni, săptămâna viitoare", 6),
      // A part of the day written after the weekday.
      ("Dentist vineri dimineața", 3), ("Dentist joi după-amiaza", 2), ("Dentist vineri seara", 3),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Dentist", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("Dentist luni la ora 9")
    #expect(timed.plannedDayOffset == 6)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Dentist")
    let opening = parse("Luni ședință")
    #expect(opening.plannedDayOffset == 6)
    #expect(opening.title == "ședință")
    let sentence = parse("Mâine e examenul")
    #expect(sentence.plannedDayOffset == 1)
    #expect(sentence.title == "e examenul")
  }

  @Test("Saturdays and Sundays together, a weekday by its place in the month, and the night just gone stay whole")
  func ambiguousDays() {
    expectLinesUnread(
      [
        // The definite forms of Saturday and Sunday read like the plain names, so the pair has no one day.
        "Alergare sâmbăta și duminica", "Alergare sâmbătă și duminică", "Alergare duminica și sâmbăta",
        // A weekday by its place in the month has no day or repeat rule.
        "Alergare prima luni din lună", "Alergare ultima vineri din lună", "Alergare în fiecare a doua marți",
        // "Azi noapte" names the night just gone as often as the night to come.
        "Alergare azi noapte", "Alergare azi-noapte",
      ], languages: ["ro"])
    // A list with a definite form of Monday to Friday is a repeat, and a single Saturday is a day.
    let list = parse("Alergare lunea și sâmbăta")
    #expect(list.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "SA"]))
    #expect(list.plannedDayOffset == nil)
    let single = parse("Alergare sâmbăta")
    #expect(single.recurrence == nil)
    #expect(single.plannedDayOffset == 4)
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("Raport în weekend", 0), ("Raport weekendul acesta", 0), ("Raport weekendul viitor", 7),
      ("Raport sâmbătă", 7), ("Raport duminică", 1), ("Raport sâmbătă asta", 0), ("Raport luni", 2),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("Raport în weekend", 0), ("Raport weekendul acesta", 0), ("Raport weekendul viitor", 7),
      ("Raport duminică", 7), ("Raport duminică asta", 0), ("Raport duminică viitoare", 7),
      ("Raport sâmbătă", 6), ("Raport luni", 1), ("Raport luni asta", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "luni asta" is today.
    for (text, offset) in [
      ("Raport luni", 7), ("Raport luni asta", 0), ("Raport luni viitoare", 7), ("Raport marți", 1),
    ] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("Raport până luni", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("Raport în fiecare luni", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("Raport de la luni până miercuri", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
    let tuesdayToThursday = parse("Raport de la marți până joi", on: "2026-09-21", weekday: 2)
    #expect(tuesdayToThursday.plannedDayOffset == 1)
    #expect(tuesdayToThursday.dueDayOffset == 3)
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Depunere 15 octombrie", "Depunere", "2026-10-15"),
      ("Depunere pe 15 octombrie", "Depunere", "2026-10-15"),
      ("Depunere la 15 octombrie", "Depunere", "2026-10-15"),
      ("Depunere în data de 15 octombrie", "Depunere", "2026-10-15"),
      ("Depunere 15 oct.", "Depunere", "2026-10-15"),
      ("Depunere 15 oct", "Depunere", "2026-10-15"),
      ("DEPUNERE PE 15 OCTOMBRIE", "DEPUNERE", "2026-10-15"),
      ("Depunere 1 mai 2027", "Depunere", "2027-05-01"),
      ("Depunere 15.10.2026", "Depunere", "2026-10-15"),
      ("Depunere 15.10.", "Depunere", "2026-10-15"),
      ("Depunere 15.10.26", "Depunere", "2026-10-15"),
      ("Depunere 15/10/2026", "Depunere", "2026-10-15"),
      ("Depunere 15-10-2026", "Depunere", "2026-10-15"),
      ("Depunere pe 15.10", "Depunere", "2026-10-15"),
      ("Depunere pe 15/10", "Depunere", "2026-10-15"),
      ("Depunere în data de 15.10", "Depunere", "2026-10-15"),
      ("Depunere 3 ianuarie", "Depunere", "2027-01-03"),
      ("Depunere 3 ian", "Depunere", "2027-01-03"),
      ("Depunere 3 februarie", "Depunere", "2027-02-03"),
      ("Depunere 3 feb", "Depunere", "2027-02-03"),
      ("Depunere 3 martie", "Depunere", "2027-03-03"),
      ("Depunere 3 mar.", "Depunere", "2027-03-03"),
      ("Depunere 3 aprilie", "Depunere", "2027-04-03"),
      ("Depunere 3 apr", "Depunere", "2027-04-03"),
      ("Depunere 3 iunie", "Depunere", "2027-06-03"),
      ("Depunere 3 iun", "Depunere", "2027-06-03"),
      ("Depunere 3 iulie", "Depunere", "2027-07-03"),
      ("Depunere 3 iul", "Depunere", "2027-07-03"),
      ("Depunere 3 august", "Depunere", "2027-08-03"),
      ("Depunere 3 aug", "Depunere", "2027-08-03"),
      ("Depunere 3 septembrie", "Depunere", "2027-09-03"),
      ("Depunere 3 sept.", "Depunere", "2027-09-03"),
      ("Depunere 3 sep", "Depunere", "2027-09-03"),
      ("Depunere 3 octombrie", "Depunere", "2026-10-03"),
      ("Depunere 3 noiembrie", "Depunere", "2026-11-03"),
      ("Depunere 3 nov", "Depunere", "2026-11-03"),
      ("Depunere 3 decembrie", "Depunere", "2026-12-03"),
      ("Depunere 3 dec", "Depunere", "2026-12-03"),
      ("Depunere 22 septembrie", "Depunere", "2026-09-22"),
      // A weekday before the date is part of it.
      ("Depunere vineri 16 octombrie", "Depunere", "2026-10-16"),
      ("Depunere vineri, 16 octombrie", "Depunere", "2026-10-16"),
      ("Depunere pe vineri 16 octombrie", "Depunere", "2026-10-16"),
      ("Ziua de naștere a Mariei 14 martie", "Ziua de naștere a Mariei", "2027-03-14"),
      ("Zi liberă 1 Decembrie", "Zi liberă", "2026-12-01"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Ședință joi 15 octombrie la ora 14:30")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Ședință")
    let concert = parse("Concert 20 oct. ora 19")
    #expect(concert.plannedDayOffset == captureDayOffset("2026-10-20"))
    #expect(concert.startMinutes == 19 * 60)
    #expect(concert.title == "Concert")
  }

  @Test("Numbers that are no date, a past year, and a day the month does not have stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers without a word that makes them a date, and a bare month.
        "Depunere 15.10", "Depunere 15/10", "Vacanța în mai", "Ianuarie", "Raport mai 2027",
        // A day the month does not have, a year that is past, and an ordinal ending.
        "Depunere 31 februarie", "Depunere 15 octombrie 2025", "Ediția a 15-a",
        // Chapters, versions, rooms, scores, percentages, prices, versions, quarters, and phone numbers.
        "Capitolul 1.5.", "Versiunea 2.3.4", "Pagina 15-10", "Camera 15.10", "Scor 3-1", "15% reducere",
        "Preț 15,50 lei", "Preț 15.30 lei", "iOS 17.4", "Q3 2026", "Sună 0722 123 456",
      ], languages: ["ro"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Vacanță", "de la 3 la 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "de la 3 până la 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "din 3 până în 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "între 3 și 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "în perioada 3-5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "în perioada 3 - 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "în perioada 3 până la 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "3-5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "pe 3-5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "de la 3 - 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "3 mai - 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "3 mai până la 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "din 3 mai până în 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "pe 3 mai până pe 5 mai", "2027-05-03", "2027-05-05"),
        ("Vacanță", "de la 30 mai la 2 iunie", "2027-05-30", "2027-06-02"),
        ("Vacanță", "între 30 mai și 2 iunie", "2027-05-30", "2027-06-02"),
        ("Vacanță", "de la 3 la 5 mai 2027", "2027-05-03", "2027-05-05"),
        ("Vacanță", "de la 5 la 9 octombrie", "2026-10-05", "2026-10-09"),
        ("Vacanță de iarnă", "24 dec - 2 ian", "2026-12-24", "2027-01-02"),
        ("Vacanță", "24 dec. - 2 ian.", "2026-12-24", "2027-01-02"),
      ], languages: ["ro"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Vacanță de la 5 la 3 mai", "Vacanță 5-3 mai", "Vacanță 3 mai - 3 mai", "Vacanță între 5 și 3 mai",
        "Preț 3-5 lei",
      ], languages: ["ro"])
    // "Până la" joins a day alone to a day with its month only after "de la" or "din": the end is read as a due day.
    let missing = parse("Vacanță 3 până la 5 mai")
    #expect(missing.plannedDayOffset == nil)
    #expect(missing.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(missing.title == "Vacanță 3")
    // Two bare numbers after "de la" and "la" are hours.
    let bare = parse("Ședință de la 3 la 5")
    #expect(bare.plannedDayOffset == nil)
    #expect(bare.dueDayOffset == nil)
    #expect(bare.startMinutes == 15 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A day alone opens a range joined by a spaced dash only after nothing that names a day")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 mai")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    let meeting = parse("Ședință 12 - 14 octombrie")
    #expect(meeting.title == "Ședință 12")
    #expect(meeting.plannedDayOffset == captureDayOffset("2026-10-14"))
    #expect(meeting.dueDayOffset == nil)
    let holiday = parse("Vacanță 3 - 5 mai")
    #expect(holiday.title == "Vacanță 3")
    #expect(holiday.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(holiday.dueDayOffset == nil)
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time or a length still reads")
  func rangeTakesBothDays() {
    let line = parse("Vacanță de la 3 la 5 mai mâine")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Vacanță mâine")
    let timed = parse("Vacanță 3-5 mai la ora 9")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Vacanță")
    let length = parse("Vacanță 3-5 mai 30 min")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "Vacanță")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    expectDateRanges(
      [
        ("Conferință", "de la luni până miercuri", "2026-09-28", "2026-09-30"),
        ("Conferință", "de la vineri la duminică", "2026-09-25", "2026-09-27"),
        ("Conferință", "de la vineri până luni", "2026-09-25", "2026-09-28"),
        ("Conferință", "vineri - duminică", "2026-09-25", "2026-09-27"),
        ("Conferință", "sâmbătă - duminică", "2026-09-26", "2026-09-27"),
        ("Vacanță", "luni - miercuri", "2026-09-28", "2026-09-30"),
        ("Vacanță", "luni-miercuri", "2026-09-28", "2026-09-30"),
        ("Vacanță", "din luni până miercuri", "2026-09-28", "2026-09-30"),
        ("Vacanță", "din luni până în miercuri", "2026-09-28", "2026-09-30"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Conferință", "de la marți până joi", "2026-09-29", "2026-10-01"),
      ], languages: ["ro"])
    // Monday to Friday is the working week, which repeats.
    for text in [
      "Sală luni - vineri", "Sală luni până la vineri", "Sală de luni până vineri", "Sală de luni până în vineri",
      "Sală zilele lucrătoare", "Sală în zilele lucrătoare", "Sală în toate zilele lucrătoare",
      "Sală în zilele de lucru", "Sală în fiecare zi lucrătoare",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Sală", "\(text): title")
    }
    let opening = parse("Luni-vineri sală")
    #expect(opening.recurrence == workdays)
    #expect(opening.title == "sală")
  }

  // MARK: - Due days

  @Test("Due days: până, cel târziu, înainte de, pentru, termen, deadline, and scadent")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Raport până vineri", "Raport", 3),
      ("Raport până la vineri", "Raport", 3),
      ("Raport până mâine", "Raport", 1),
      ("Raport până azi", "Raport", 0),
      ("Raport până diseară", "Raport", 0),
      ("Raport până poimâine", "Raport", 2),
      ("Raport până sâmbătă", "Raport", 4),
      ("Raport până luni viitoare", "Raport", 6),
      ("Raport până săptămâna viitoare", "Raport", 7),
      ("Raport până vineri dimineața", "Raport", 3),
      ("Raport până pe 15 octombrie", "Raport", 23),
      ("Raport până la 15 octombrie", "Raport", 23),
      ("Raport până la 15 oct.", "Raport", 23),
      ("Raport până la 15.10", "Raport", 23),
      ("Raport până pe 15.10.2026", "Raport", 23),
      ("Raport cel târziu vineri", "Raport", 3),
      ("Raport cel târziu pe 15 octombrie", "Raport", 23),
      ("Raport cel târziu la 15 octombrie", "Raport", 23),
      ("Raport înainte de vineri", "Raport", 3),
      ("Raport vineri cel târziu", "Raport", 3),
      ("Raport termen: vineri", "Raport", 3),
      ("Raport termen limită vineri", "Raport", 3),
      ("Raport termen limită: vineri", "Raport", 3),
      ("Raport deadline vineri", "Raport", 3),
      ("Raport deadline: vineri", "Raport", 3),
      ("Raport scadent vineri", "Raport", 3),
      ("Raport scadent 15 octombrie", "Raport", 23),
      ("Raport pentru vineri", "Raport", 3),
      ("Raport pentru mâine", "Raport", 1),
      ("Raport pentru poimâine", "Raport", 2),
      ("Raport pentru diseară", "Raport", 0),
      ("Raport pentru 15 octombrie", "Raport", 23),
      ("Raport pentru 15.10.2026", "Raport", 23),
      ("Raport pentru săptămâna viitoare", "Raport", 7),
      ("Tema pentru luni", "Tema", 6),
      ("Pregătește prezentarea pentru sâmbătă", "Pregătește prezentarea", 4),
      ("Trimite raportul până vineri", "Trimite raportul", 3),
      ("Cumpără pâine pentru mâine", "Cumpără pâine", 1),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Raport până vineri azi")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Raport")
    // A due phrase that opens the line.
    let opening = parse("Până vineri trimite raportul")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "trimite raportul")
    // The weekend names no due day, a bare number is no day, and a count of days, months, or a person is no deadline.
    expectLinesUnread(
      [
        "Raport până la weekend", "Raport înainte de weekend", "Raport după weekend", "Raport de weekend",
        "Raport pentru weekend", "Raport pentru weekendul acesta", "Raport până la 17", "Raport până peste 3 luni",
        "Salariu pentru 3 luni", "Plan pentru luni de zile", "Raport pentru 3 zile", "Cumpără cadou pentru mama",
        "Plătește 100 lei până pe 15",
      ], languages: ["ro"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Raport până la ora 17", "Raport până la 17:00", "Raport înainte de 17:00", "Raport înainte de ora 17",
        "Raport cel târziu la ora 17", "Raport cel târziu la 17:00", "Raport după ora 18", "Raport după 18:00",
        "Raport nu mai târziu de ora 17", "Raport până la 5 seara", "Raport până la ora 5 după-amiaza",
        "Raport până la 3 și jumătate", "Raport până la ora 17:30", "Raport până la 2 și jumătate",
      ], languages: ["ro"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Raport până vineri la ora 17", "Raport la ora 17", 3), ("Raport până vineri la 17:00", "Raport la 17:00", 3),
      ("Raport până vineri 17:00", "Raport 17:00", 3), ("Raport până luni la ora 9", "Raport la ora 9", 6),
      ("Raport cel târziu mâine la 9:00", "Raport la 9:00", 1), ("Raport termen: vineri la 17:00", "Raport la 17:00", 3),
      ("Raport pentru vineri la ora 17", "Raport la ora 17", 3), ("Raport pentru vineri la 17:00", "Raport la 17:00", 3),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A time range that ends in a clock time is still a range, and a bound after a day stays a bound.
    let range = parse("Ședință de la 14 la 17:30")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 210)
    #expect(range.title == "Ședință")
    let bound = parse("Ședință până la 17:30 mâine")
    #expect(bound.plannedDayOffset == 1)
    #expect(bound.startMinutes == nil)
    #expect(bound.title == "Ședință până la 17:30")
    // Without Romanian, English reads the clock time and leaves the words.
    let english = parse("Raport până la 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
    #expect(english.title == "Raport până la")
  }

  // MARK: - Clock times

  @Test("Clock times: la, ora, a part of the day, noon, and AM and PM")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Ședință la ora 15", 15 * 60), ("Ședință la ora 3", 15 * 60), ("Ședință la ora 03", 3 * 60),
      ("Ședință la 15", 15 * 60), ("Ședință ora 15", 15 * 60), ("Ședință ora 3", 15 * 60),
      ("Ședință la 15:30", 15 * 60 + 30), ("Ședință la 15.30", 15 * 60 + 30), ("Ședință ora 15.30", 15 * 60 + 30),
      ("Ședință la orele 15:30", 15 * 60 + 30), ("Ședință orele 15", 15 * 60), ("Ședință de la ora 15", 15 * 60),
      ("Ședință la 08:30", 8 * 60 + 30), ("Ședință la 00:30", 30), ("Ședință la 18", 18 * 60),
      ("Ședință la ora 18", 18 * 60), ("Ședință la ora 12", 12 * 60), ("Ședință la 12", 12 * 60),
      ("Ședință la 8", 8 * 60), ("Ședință la 9:30", 9 * 60 + 30), ("Ședință la 20:30", 20 * 60 + 30),
      ("Ședință la ora 0", 0), ("Ședință la 03:00", 3 * 60), ("Ședință la ora 5.10", 17 * 60 + 10),
      ("Ședință pe la 5", 17 * 60), ("Ședință pe la ora 5", 17 * 60), ("Ședință în jurul orei 5", 17 * 60),
      // An hour spelled as a word after a lead.
      ("Ședință la trei", 15 * 60), ("Ședință la ora trei", 15 * 60),
      // A part of the day after the hour.
      ("Ședință ora 3 după-amiază", 15 * 60), ("Ședință ora 3 după amiază", 15 * 60),
      ("Ședință ora 3 dupa amiaza", 15 * 60), ("Ședință la 3 după-amiază", 15 * 60),
      ("Ședință la 8 seara", 20 * 60), ("Ședință la 8 de seară", 20 * 60), ("Ședință la 7 dimineața", 7 * 60),
      ("Ședință la 7 de dimineață", 7 * 60), ("Ședință la 8 dimineața", 8 * 60), ("Ședință la 11 seara", 23 * 60),
      ("Ședință la 20:30 seara", 20 * 60 + 30), ("Ședință 8 seara", 20 * 60), ("Ședință 7:30 seara", 19 * 60 + 30),
      ("Ședință 3:30 după-amiaza", 15 * 60 + 30), ("Ședință 20:30 seara", 20 * 60 + 30),
      // The part of the day before the hour.
      ("Ședință dimineața la 7", 7 * 60), ("Ședință dimineața 7:30", 7 * 60 + 30),
      ("Ședință seara la 8", 20 * 60), ("Ședință seara la ora 8", 20 * 60), ("Ședință după-amiaza la 3", 15 * 60),
      ("Ședință noaptea la 11", 23 * 60),
      // Noon.
      ("Ședință la prânz", 12 * 60), ("Ședință la pranz", 12 * 60), ("Ședință la amiază", 12 * 60),
      ("Ședință la miezul zilei", 12 * 60), ("Ședință pe la prânz", 12 * 60),
      // AM and PM after a lead take the lead with them; with no lead English reads them.
      ("Ședință la 3pm", 15 * 60), ("Ședință la 3 pm", 15 * 60), ("Ședință la 3:30 pm", 15 * 60 + 30),
      ("Ședință la ora 3 pm", 15 * 60), ("Ședință 15:30", 15 * 60 + 30), ("Ședință 3pm", 15 * 60),
      ("Ședință 17:30", 17 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Ședință", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The title is what the time leaves.
    #expect(parse("Vorbit cu mama la 3").title == "Vorbit cu mama")
    #expect(parse("Telefon la bancă la ora 9").title == "Telefon la bancă")
    #expect(parse("Interviu mâine la 14:30").title == "Interviu")
    // A time that no Romanian word introduces is left to English, which leaves the preposition behind.
    #expect(parse("Ședință de la prânz").startMinutes == nil)
  }

  @Test("After midnight: noaptea, miezul nopții, and miez de noapte run past the midnight that ends the day")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("Ședință la 2 noaptea", 1, 2 * 60), ("Ședință la 1 noaptea", 1, 60), ("Ședință la 12 noaptea", 1, 0),
      ("Ședință la miezul nopții", 1, 0), ("Ședință la miezul noptii", 1, 0), ("Ședință la miez de noapte", 1, 0),
      ("Ședință mâine noaptea la 2", 2, 2 * 60), ("Ședință mâine noaptea la 12", 2, 0),
      ("Ședință mâine la 12 noaptea", 2, 0),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Ședință", "\(line): title")
    }
    // Eleven at night is still the day itself, and the 24th hour is no time of day.
    let eleven = parse("Ședință la 11 noaptea")
    #expect(eleven.plannedDayOffset == nil)
    #expect(eleven.startMinutes == 23 * 60)
    expectLinesUnread(["Ședință la ora 24", "Ședință la 24:00", "Ședință la 25:00", "Ședință la 9:60"], languages: ["ro"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func twelveHourRules() {
    for (line, minutes) in [
      ("Ședință la 1", 13 * 60), ("Ședință la 3", 15 * 60), ("Ședință la 6", 18 * 60), ("Ședință la 7", 7 * 60),
      ("Ședință la 06:00", 6 * 60), ("Ședință la ora 03", 3 * 60), ("Ședință la 11", 11 * 60),
      ("Ședință la 12", 12 * 60), ("Ședință la ora 5.10", 17 * 60 + 10), ("Prânz la 1", 13 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
    }
  }

  @Test("Spoken times: și jumătate, și un sfert, and fără name the hour with minutes added or taken off")
  func spokenTimes() {
    let spoken: [(text: String, minutes: Int)] = [
      ("Ședință la 3 și jumătate", 15 * 60 + 30), ("Ședință la ora 3 și jumătate", 15 * 60 + 30),
      ("Ședință la 3 și un sfert", 15 * 60 + 15), ("Ședință la 3 fără un sfert", 14 * 60 + 45),
      ("Ședință la 3 fără 10", 14 * 60 + 50), ("Ședință la 3 și 10", 15 * 60 + 10),
      ("Ședință ora trei și jumătate", 15 * 60 + 30), ("Ședință la trei și jumătate", 15 * 60 + 30),
      ("Ședință la trei și un sfert", 15 * 60 + 15), ("Ședință la trei fără un sfert", 14 * 60 + 45),
      ("Ședință la trei fără zece", 14 * 60 + 50), ("Ședință la 12 și jumătate", 12 * 60 + 30),
      ("Ședință la 1 fără un sfert", 12 * 60 + 45), ("Ședință la 12 fără un sfert", 11 * 60 + 45),
      ("Ședință la 3 și jumătate după-amiaza", 15 * 60 + 30), ("Ședință la 7 și jumătate seara", 19 * 60 + 30),
      ("Ședință la 8 și jumătate seara", 20 * 60 + 30), ("Ședință la 11 fără 5 seara", 22 * 60 + 55),
      ("Ședință la 3 și douăzeci", 15 * 60 + 20), ("Ședință la 3 și douăzeci și cinci", 15 * 60 + 25),
      ("Ședință la 3 fără douăzeci și cinci", 14 * 60 + 35), ("Ședință la 2 și jumătate", 14 * 60 + 30),
    ]
    for line in spoken {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
      #expect(parsed.title == "Ședință", "\(line.text): title")
    }
    // Without a lead, "3 și jumătate" is as often an amount.
    expectLinesUnread(["Ședință 3 și jumătate", "Cumpără 3 și jumătate kg"], languages: ["ro"])
    let title = parse("Ședință la 2 și jumătate la birou")
    #expect(title.title == "Ședință la birou")
    #expect(title.startMinutes == 14 * 60 + 30)
  }

  @Test("Spoken minutes written with a unit word stay in the title whole")
  func spokenMinutesWithUnit() {
    expectLinesUnread(
      [
        "Ședință la 3 și 5 minute", "Ședință la 3 fără 5 minute", "Ședință la 3 și zece minute",
        "Ședință la 3 fără zece minute", "Ședință la 3 și 10 min", "Ședință la ora 15 și 30 min",
        "Ședință la ora 15 și 30 de minute", "Ședință la 3 și 30 min cu Ana",
      ], languages: ["ro"])
    // The same minutes with no unit are the time, and a length that stands apart is still a length.
    #expect(parse("Ședință la 3 și 10").startMinutes == 15 * 60 + 10)
    let apart = parse("Ședință la 3 și 30 min 20 min")
    #expect(apart.startMinutes == nil)
    #expect(apart.estimatedMinutes == 20)
    #expect(apart.title == "Ședință la 3 și 30 min")
  }

  @Test("A bare hour counts as a time only before a word that can follow a time, and a count of things is not")
  func bareHours() {
    for (line, title, minutes) in [
      ("Ședință la 3 cu Ana", "Ședință cu Ana", 15 * 60), ("Vorbit cu mama la 3", "Vorbit cu mama", 15 * 60),
      ("La ora 5 ridică copiii", "ridică copiii", 17 * 60), ("Ședință la 3, Ana", "Ședință, Ana", 15 * 60),
      ("Ședință la 3 și apoi cumpărături", "Ședință și apoi cumpărături", 15 * 60),
      ("Mama sună la 7", "Mama sună", 7 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
      #expect(parsed.title == title, "\(line): title")
    }
    expectLinesUnread(
      [
        "Ședință la 3 prieteni", "Ședință la 15 oameni", "Plec la 3 prieteni", "Rezervă la 4 persoane",
        "La 7 ridică copiii", "Cumpără pâine la 3 lei", "Cumpără 3 mere la 15 lei", "Ședință la 5.10",
        "Ședință la 15.10", "Ședință 15.30", "Ședință în jur de 5",
      ], languages: ["ro"])
  }

  @Test("Time ranges: de la with la or până la, între with și, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Ședință de la 14 la 16", 14 * 60, 120), ("Ședință de la 14:00 până la 16:00", 14 * 60, 120),
      ("Ședință de la 14.00 la 16.00", 14 * 60, 120), ("Ședință între 14 și 16", 14 * 60, 120),
      ("Ședință între 14:00 și 16:00", 14 * 60, 120), ("Ședință 14:00-16:00", 14 * 60, 120),
      ("Ședință 14:00 - 16:00", 14 * 60, 120), ("Ședință ora 14-16", 14 * 60, 120),
      ("Ședință orele 14-16", 14 * 60, 120), ("Ședință de la ora 14 până la ora 16", 14 * 60, 120),
      ("Ședință de la 8 la 10 dimineața", 8 * 60, 120), ("Ședință între 2 și 4 după-amiaza", 14 * 60, 120),
      ("Ședință de la 8 la 10 seara", 20 * 60, 120), ("Ședință de la 15:30 la 17:00", 15 * 60 + 30, 90),
      ("Ședință de la 9 la 12", 9 * 60, 180), ("Ședință între 3 și 5", 15 * 60, 120),
      ("Ședință ora 3-4", 15 * 60, 60), ("Ședință de la 14 la 17:30", 14 * 60, 210),
      ("Ședință de la 3 la 5", 15 * 60, 120), ("Ședință între 14:00 și 15:30", 14 * 60, 90),
      ("Ședință între 9 și 12", 9 * 60, 180), ("Cursuri între 8 și 10 dimineața", 8 * 60, 120),
      ("Cursuri de la 8 la 10 dimineața", 8 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title.hasPrefix("Ședință") || parsed.title.hasPrefix("Cursuri"), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // An evening makes the range the evening's, as it does a single hour.
    let evening = parse("Ședință diseară de la 7 la 9")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.estimatedMinutes == 120)
    let morning = parse("Ședință mâine de la 7 la 9")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 7 * 60)
    #expect(parse("Ședință de la 7 la 9 seara").startMinutes == 19 * 60)
    // Numbers that count something are no range of hours, and neither are two bare hours whose end comes
    // before a start on the 24-hour clock.
    expectLinesUnread(
      [
        "Ședință 14-16", "Ședință 3-5", "Ședință 14.00-16.00", "Locuri 14-16", "Capitolele de la 3 la 5",
        "Paginile 3-5", "Ședință între 15 și 10", "Ședință de la 15 la 10", "Ședință între 3 și 5 oameni",
        "Buget între 5 și 10", "Salariu între 5 și 10", "Preț între 5 și 10", "Cost între 5 și 10",
        "Ședință între 9 și 12 dimineața",
      ], languages: ["ro"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Ședință 30 de minute", 30), ("Ședință 30 minute", 30), ("Ședință 12 minute", 12),
      ("Ședință 12 de minute", 12), ("Ședință 20 de minute", 20), ("Ședință 30 min", 30), ("Ședință 30 min.", 30),
      ("Ședință 45min", 45), ("Ședință 5 min", 5), ("Ședință 90 minute", 90), ("Ședință 1440 min", 1440),
      ("Ședință o oră", 60), ("Ședință 1 oră", 60), ("Ședință 1 ora", 60), ("Ședință 2 ore", 120),
      ("Ședință 2 ore și 30 de minute", 150), ("Ședință 2 ore 30 min", 150), ("Ședință o oră și jumătate", 90),
      ("Ședință două ore și jumătate", 150), ("Ședință jumătate de oră", 30), ("Ședință o jumătate de oră", 30),
      ("Ședință un sfert de oră", 15), ("Ședință trei sferturi de oră", 45), ("Ședință 1,5 ore", 90),
      ("Ședință 1.5 ore", 90), ("Ședință 0,5 ore", 30), ("Ședință 2,5 ore", 150), ("Ședință 1h", 60),
      ("Ședință 2h", 120), ("Ședință timp de 2 ore", 120), ("Ședință durata: 2 ore", 120),
      ("Ședință durează 2 ore", 120), ("Ședință de 2 ore", 120), ("Ședință pentru 30 de minute", 30),
      ("Ședință cam 30 de minute", 30), ("Ședință aproximativ 2 ore", 120), ("Ședință zece minute", 10),
      ("Ședință douăzeci de minute", 20), ("Ședință cinci minute", 5),
      ("Ședință patruzeci și cinci de minute", 45), ("Ședință 2 ore și un sfert", 135), ("Ședință trei ore", 180),
      ("Ședință 24 de ore", 1440), ("Ședință 20 de ore", 1200),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Ședință", "\(line.text): title")
    }
    let before = parse("30 de minute ședință")
    #expect(before.estimatedMinutes == 30)
    #expect(before.title == "ședință")
    #expect(parse("Curs de 2 ore").title == "Curs")
    // A length beside a day and a time.
    let line = parse("Ședință mâine la ora 3 pentru 2 ore")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.title == "Ședință")
  }

  @Test("An amount after peste, după, or la fiecare, a duration of something else, and a size is no length")
  func notLengths() {
    expectLinesUnread(
      [
        "Ședință peste 2 ore", "Ședință după 30 de minute", "Ședință acum 2 ore", "Ședință la fiecare 2 ore",
        "Ședință până la 2 ore", "Ședință mai mult de 2 ore", "Ședință 30 de minute înainte", "Ședință 2 ore în urmă",
        "Ședință 2 ore pe zi", "Ședință 30 min mai târziu", "Ședință 2 ore suplimentare", "Ședință 2-3 ore",
        "Ședință între 2 și 3 ore", "Ședință 2 - 3 ore", "Ședință 25 de ore", "Ședință 1500 min",
        "Ședință 0 minute", "Ședință 2h30", "Ședință 3.5.2 ore", "Sună-mă în 10 minute",
      ], languages: ["ro"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func cadences() {
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Alergare în fiecare zi", daily), ("Alergare zilnic", daily), ("Alergare în fiecare dimineață", daily),
      ("Alergare în fiecare seară", daily), ("Alergare în toate zilele", daily), ("Alergare o dată pe zi", daily),
      ("Alergare în fiecare săptămână", weekly), ("Alergare săptămânal", weekly),
      ("Alergare o dată pe săptămână", weekly), ("Alergare 1x pe săptămână", weekly),
      ("Alergare în fiecare lună", monthly), ("Alergare lunar", monthly), ("Alergare o dată pe lună", monthly),
      ("Alergare odată pe lună", monthly), ("Alergare în fiecare an", yearly), ("Alergare anual", yearly),
      ("Alergare o dată pe an", yearly),
      ("Alergare la două zile", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Alergare la 2 zile", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Alergare la fiecare 2 zile", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Alergare din două în două zile", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Alergare în fiecare a doua zi", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Alergare din 3 în 3 zile", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Alergare în fiecare a treia zi", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Alergare la 3 săptămâni", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("Alergare la fiecare două săptămâni", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Alergare o dată la două săptămâni", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Alergare în fiecare a doua săptămână", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Alergare la 14 zile", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Alergare la fiecare 2 luni", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Alergare trimestrial", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Alergare în fiecare trimestru", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Alergare semestrial", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("Alergare în fiecare semestru", TaskRecurrenceRule(freq: .monthly, interval: 6)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "Alergare", "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // A repeat in front of the line.
    let opening = parse("Zilnic: alergare")
    #expect(opening.recurrence == daily)
    #expect(opening.title == "alergare")
    // A repeat at the end of a line that goes on after a noun.
    #expect(parse("Raport lunar").recurrence == monthly)
    #expect(parse("Raport trimestrial").recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3))
    // A date beside a yearly repeat.
    let birthday = parse("Ziua Anei 15 octombrie în fiecare an")
    #expect(birthday.recurrence == yearly)
    #expect(birthday.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(birthday.title == "Ziua Anei")
    let date = parse("Ziua Anei în fiecare an pe 15 octombrie")
    #expect(date.recurrence == yearly)
    #expect(date.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(date.title == "Ziua Anei")
    #expect(parse("Ziua Anei în fiecare an").recurrence == yearly)
    // A repeat with a time or a length.
    for (text, rule, minutes, length) in [
      ("Alergare în fiecare dimineață la 7", daily, 7 * 60, nil), ("Alergare în fiecare dimineață la ora 7", daily, 7 * 60, nil),
      ("Alergare în fiecare dimineață 7:30", daily, 7 * 60 + 30, nil), ("Alergare în fiecare seară la 8", daily, 20 * 60, nil),
      ("Alergare în fiecare seară 8:30", daily, 20 * 60 + 30, nil),
      ("Alergare în fiecare noapte la 11", daily, 23 * 60, nil),
      ("Alergare în fiecare seară la 8 pentru 30 de minute", daily, 20 * 60, 30),
      ("Medicamente în fiecare zi la 8 dimineața", daily, 8 * 60, nil),
      ("Medicamente zilnic la 8 seara", daily, 20 * 60, nil),
    ] as [(String, TaskRecurrenceRule, Int, Int?)] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == String(text.prefix { $0 != " " }), "\(text): title")
    }
  }

  @Test("Weekday repeats: în fiecare luni, lunea, and the working days and the weekend")
  func weekdayRepeats() {
    let coming = parse("Alergare în fiecare luni")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Alergare")
    for text in [
      "Alergare lunea", "Alergare în fiecare zi de luni", "Alergare în fiecare luni dimineața", "Alergare în fiecare luni",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == monday, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.title == "Alergare", "\(text): title")
    }
    let pairs: [(text: String, days: [String])] = [
      ("Alergare în fiecare marți și joi", ["TU", "TH"]),
      ("Alergare în fiecare luni, miercuri și vineri", ["MO", "WE", "FR"]),
      ("Alergare în fiecare luni și joi", ["MO", "TH"]),
      ("Alergare lunea și joia", ["MO", "TH"]),
      ("Alergare în zilele de marți", ["TU"]),
      ("Alergare în zilele de marți și joi", ["TU", "TH"]),
      ("Alergare marțea", ["TU"]),
      ("Alergare miercurea", ["WE"]),
      ("Alergare vinerea", ["FR"]),
      ("Alergare lunea și sâmbăta", ["MO", "SA"]),
      ("Alergare săptămânal luni și joi", ["MO", "TH"]),
      ("Alergare săptămânal marțea", ["TU"]),
      ("Alergare în fiecare sâmbătă", ["SA"]),
      ("Alergare în fiecare duminică", ["SU"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Alergare", "\(line.text): title")
    }
    // An interval takes the weekdays after it.
    let interval = parse("Alergare o dată la 2 săptămâni joia")
    #expect(interval.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TH"]))
    #expect(interval.recurrenceStartOffset == 2)
    #expect(interval.title == "Alergare")
    // The start of a repeat on Wednesday, Friday, and Monday is the nearest day.
    #expect(parse("Alergare în fiecare luni, miercuri și vineri").recurrenceStartOffset == 1)
    #expect(parse("Alergare în fiecare marți și joi").recurrenceStartOffset == 0)
    #expect(parse("Alergare lunea și sâmbăta").recurrenceStartOffset == 4)
    for text in ["Alergare în fiecare weekend", "Alergare în weekenduri"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == weekend, "\(text)")
      #expect(parsed.recurrenceStartOffset == 4, "\(text): start")
      #expect(parsed.title == "Alergare", "\(text): title")
    }
    // "În weekend" is one day.
    let day = parse("Spală mașina în weekend")
    #expect(day.recurrence == nil)
    #expect(day.plannedDayOffset == 4)
    #expect(day.title == "Spală mașina")
    // A repeat with a time.
    let timed = parse("Yoga în fiecare marți și joi la ora 19:30")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(timed.startMinutes == 19 * 60 + 30)
    #expect(timed.title == "Yoga")
    let evening = parse("Yoga în fiecare marți la 7 seara")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    #expect(evening.startMinutes == 19 * 60)
    let morning = parse("Alergare în fiecare luni dimineața la 7")
    #expect(morning.recurrence == monday)
    #expect(morning.startMinutes == 7 * 60)
    #expect(morning.title == "Alergare")
    let weekendTimed = parse("Spălat rufe în fiecare weekend la 10")
    #expect(weekendTimed.recurrence == weekend)
    #expect(weekendTimed.startMinutes == 10 * 60)
    #expect(weekendTimed.title == "Spălat rufe")
    let lunch = parse("Mergi la sală în fiecare marți și joi")
    #expect(lunch.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(lunch.title == "Mergi la sală")
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [15])
    for text in ["Chirie în fiecare 15 ale lunii", "Chirie în fiecare lună pe 15", "Chirie lunar pe 15"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 23, "\(text): start")
      #expect(parsed.title == "Chirie", "\(text): title")
    }
    let first = TaskRecurrenceRule(freq: .monthly, byMonthDay: [1])
    for text in ["Chirie în fiecare 1 ale lunii", "Chirie lunar pe 1"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == first, "\(text)")
      #expect(parsed.recurrenceStartOffset == 9, "\(text): start")
    }
    let fifth = parse("Facturi în fiecare lună pe 5")
    #expect(fifth.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(fifth.recurrenceStartOffset == 13)
    // An amount after "în fiecare lună" is no day of the month.
    let amount = parse("Chirie în fiecare lună 15 lei")
    #expect(amount.recurrence == monthly)
    #expect(amount.title == "Chirie 15 lei")
    let counted = parse("Chirie în fiecare lună pe 15 lei")
    #expect(counted.recurrence == monthly)
    #expect(counted.title == "Chirie pe 15 lei")
  }

  @Test("A weekday by its place in the month stays whole, and a cadence adjective or noun stays in the title")
  func unreadRepeats() {
    expectLinesUnread(
      [
        // A weekday by its place in the month has no repeat rule, so no part of it is read as a weekday.
        "Alergare prima luni din lună", "Alergare ultima vineri din lună", "Alergare în fiecare a doua marți",
        // An adjective, a noun, or an adverb that is not at the end of the line.
        "Ședință săptămânală", "Raport săptămânal pentru echipă", "Ședință lunară", "Planificare anuală",
        "Zilnic yoga", "Alergare zilnic: alergare",
        // A count of days that is no cadence.
        "Alergare în 5 zile lucrătoare", "Alergare în 3 zile", "Alergare la 2 zile după ședință",
        "Alergare din 2 în 3 zile",
      ], languages: ["ro"])
  }

  // MARK: - Priorities

  @Test("Priorities: urgent, important, prioritate mare or scăzută, and prio")
  func priorities() {
    let priorities: [(text: String, title: String, priority: LorvexTask.Priority)] = [
      ("Raport urgent", "Raport", .p1), ("Raport urgent.", "Raport", .p1), ("Raport urgent!", "Raport", .p1),
      ("Raport foarte urgent", "Raport", .p1), ("Raport important", "Raport", .p1),
      ("Raport foarte important", "Raport", .p1), ("Urgent: raport", "raport", .p1),
      ("Important, raport", "raport", .p1),
      ("Raport prioritate mare", "Raport", .p1), ("Raport prioritate înaltă", "Raport", .p1),
      ("Raport prioritate ridicată", "Raport", .p1), ("Raport prioritate 1", "Raport", .p1),
      ("Raport prio 1", "Raport", .p1), ("Raport prio: mare", "Raport", .p1), ("Raport de mare prioritate", "Raport", .p1),
      ("Raport cu prioritate mare", "Raport", .p1), ("Raport mare prioritate", "Raport", .p1),
      ("Raport prioritatea mare", "Raport", .p1), ("Prioritate mare: raport", "raport", .p1),
      ("Raport prioritate medie", "Raport", .p2), ("Raport prioritate 2", "Raport", .p2),
      ("Raport prioritate scăzută", "Raport", .p3), ("Raport prioritate mică", "Raport", .p3),
      ("Raport prioritate 3", "Raport", .p3), ("Raport prio mică", "Raport", .p3),
      ("Prioritate redusă raport", "raport", .p3),
      ("Raport URGENT", "Raport", .p1), ("Raport PRIORITATE MARE", "Raport", .p1),
      // The shorthand every language reads.
      ("Raport !", "Raport", .p1), ("Raport p1", "Raport", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A negated word, a word that opens a sentence, a word in the middle of a line, a noun, and a feminine
    // adjective (which is the same letters as a noun once the diacritics are left out) are no priority.
    expectLinesUnread(
      [
        "Urgent raport", "Raport nu e urgent", "Raport nu este urgent", "Raport deloc urgent",
        "Raport nu prea important", "Raport mai puțin important", "Un raport urgent pentru Anna",
        "Raport urgent pentru Anna", "Raport urgent: sună", "Raport prioritate 4", "Raport prioritate",
        "Raport urgentă", "Ședință importantă", "Raport importante", "Raport fără urgență", "Plan de urgențe",
        "Sună în caz de urgență", "Raport de mare importanță", "Fără întârziere",
      ], languages: ["ro"])
    // The word in the middle of a line stays in the title, and what follows it reads.
    let middle = parse("Raport urgent mâine la 15")
    #expect(middle.title == "Raport urgent")
    #expect(middle.priority == nil)
    #expect(middle.plannedDayOffset == 1)
    #expect(middle.startMinutes == 15 * 60)
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyDetail() {
    let line = parse("Scrie raportul mâine la ora 15 2 ore urgent")
    #expect(line.title == "Scrie raportul")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.priority == .p1)
    #expect(line.phrases.map(\.text) == ["mâine", "la ora 15", "2 ore", "urgent"])
    let recurring = parse("Alergare în fiecare luni la ora 18 1 oră prioritate mare")
    #expect(recurring.title == "Alergare")
    #expect(recurring.recurrence == monday)
    #expect(recurring.startMinutes == 18 * 60)
    #expect(recurring.estimatedMinutes == 60)
    #expect(recurring.priority == .p1)
    let due = parse("Declarația fiscală până la 31.07 prio 2")
    #expect(due.title == "Declarația fiscală")
    #expect(due.dueDayOffset == captureDayOffset("2027-07-31"))
    #expect(due.priority == .p2)
    let lunch = parse("Prânz cu Ana mâine la 12:30 1 oră")
    #expect(lunch.title == "Prânz cu Ana")
    #expect(lunch.plannedDayOffset == 1)
    #expect(lunch.startMinutes == 12 * 60 + 30)
    #expect(lunch.estimatedMinutes == 60)
    // Lists and tags beside Romanian details.
    let list = LorvexCaptureParser.parse(
      "Cumpărături #Listă mâine", lists: [.init(id: "L1", name: "Listă")], todayWeekday: 3, today: "2026-09-22",
      languages: ["ro"])
    #expect(list.listName == "Listă")
    #expect(list.plannedDayOffset == 1)
    #expect(list.title == "Cumpărături")
    let tag = parse("Cumpărături azi #personal")
    #expect(tag.tags == ["personal"])
    #expect(tag.plannedDayOffset == 0)
    #expect(tag.title == "Cumpărături")
    let tagFirst = parse("#muncă Ședință mâine la 3")
    #expect(tagFirst.tags == ["muncă"])
    #expect(tagFirst.plannedDayOffset == 1)
    #expect(tagFirst.startMinutes == 15 * 60)
    #expect(tagFirst.title == "Ședință")
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Nouns made of a day word, a time word, or a number word.
        "Ora de matematică", "Ora de sport", "Sunt la ora de sport", "Cafeaua de dimineață", "Cina de seară",
        "Seara de film", "Dimineața devreme", "Mai multe idei", "Mai verifică o dată", "Fără întârziere",
        // Numbers that are counts, places, and amounts.
        "Cumpără lapte", "Cumpără 3 mere", "Cumpără pâine și lapte", "Plătește 15 lei", "Plătește 15 lei pe 3 luni",
        "Întâlnire cu 3 prieteni", "Plec la 3 prieteni", "Capitolul 3", "Pagina 15", "Camera 15", "Camera 12, etaj 3",
        "Locul 3 la 5", "Versiunea 2.3", "Pasul 3 din 5", "Sprint 12", "Test 2 din 5", "Tema 3", "Pagina 5 din raport",
        "Sună 0722 123 456", "Alergare 5 km", "Cumpără 3 kg de roșii", "Citește 30 de pagini",
        "Cumpără bilete pentru 3 persoane", "Cazare pentru 3 zile", "Fă temele la matematică",
        "A doua întâlnire cu clientul", "Facturi: gaz, curent", "Plimbare după masă", "Plimbare cu câinele după-amiază",
        "Ora 7: trezire",
        // A quantity of time that is a duration of something else.
        "Ședință peste 2 ore", "Sună-mă în 10 minute",
      ], languages: ["ro"])
    // A line that opens with a time keeps the rest as the title.
    let lead = parse("Ora 5 prezentare")
    #expect(lead.startMinutes == 17 * 60)
    #expect(lead.title == "prezentare")
  }

  @Test("A hyphen joins a compound that is no day, and extra spaces or punctuation between details change nothing")
  func hyphensAndSpacing() {
    expectLinesUnread(["Raport azi-dimineață", "Raport mâine-seară", "Raport vineri-seara"], languages: ["ro"])
    let spaced = parse("Raport   la   ora   15")
    #expect(spaced.startMinutes == 15 * 60)
    #expect(spaced.title == "Raport")
    let tabbed = parse("Raport în\tfiecare luni")
    #expect(tabbed.recurrence == monday)
    #expect(tabbed.title == "Raport")
    for text in ["Raport mâine, la 15", "Raport mâine; la 15"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "Raport", "\(text): title")
    }
  }

  @Test("Comma-below letters, cedilla letters, and no diacritics read alike, and the title keeps the letters it was typed with")
  func diacriticSpelling() {
    let days: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Ședință mâine", "Ședință", { $0.plannedDayOffset == 1 }),
      ("Ședință marți", "Ședință", { $0.plannedDayOffset == 7 }),
      ("Ședință sâmbătă dimineața", "Ședință", { $0.plannedDayOffset == 4 }),
      ("Ședință săptămâna viitoare", "Ședință", { $0.plannedDayOffset == 7 }),
      ("Ședință peste două săptămâni", "Ședință", { $0.plannedDayOffset == 14 }),
      ("Ședință diseară la 8", "Ședință", { $0.plannedDayOffset == 0 && $0.startMinutes == 20 * 60 }),
      ("Ședință între 3 și 5 mai", "Ședință", { $0.dueDayOffset == captureDayOffset("2027-05-05") }),
      ("Raport până vineri", "Raport", { $0.dueDayOffset == 3 }),
      ("Raport înainte de vineri", "Raport", { $0.dueDayOffset == 3 }),
      ("Raport cel târziu vineri", "Raport", { $0.dueDayOffset == 3 }),
      ("Raport pentru mâine", "Raport", { $0.dueDayOffset == 1 }),
    ]
    let times: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Ședință la ora 3 după-amiază", "Ședință", { $0.startMinutes == 15 * 60 }),
      ("Ședință la 3 și jumătate", "Ședință", { $0.startMinutes == 15 * 60 + 30 }),
      ("Ședință la 3 fără un sfert", "Ședință", { $0.startMinutes == 14 * 60 + 45 }),
      ("Ședință la prânz", "Ședință", { $0.startMinutes == 12 * 60 }),
      ("Ședință la miezul nopții", "Ședință", { $0.startMinutes == 0 && $0.plannedDayOffset == 1 }),
      ("Raport două ore și jumătate", "Raport", { $0.estimatedMinutes == 150 }),
      ("Raport jumătate de oră", "Raport", { $0.estimatedMinutes == 30 }),
      ("Raport prioritate scăzută", "Raport", { $0.priority == .p3 }),
      ("Raport prioritate înaltă", "Raport", { $0.priority == .p1 }),
    ]
    let repeats: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Alergare în fiecare marți", "Alergare", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]) }),
      ("Alergare marțea", "Alergare", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]) }),
      ("Alergare în zilele lucrătoare", "Alergare", { $0.recurrence == workdays }),
      ("Alergare în fiecare săptămână", "Alergare", { $0.recurrence == weekly }),
      ("Alergare o dată la două săptămâni", "Alergare", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2) }),
    ]
    for line in days + times + repeats {
      for spell in spellings {
        let typed = spell(line.text)
        let parsed = parse(typed)
        #expect(line.check(parsed), "\(typed)")
        #expect(scalars(parsed.title) == scalars(spell(line.title)), "\(typed): title")
      }
    }
    // The cedilla and comma-below letters are different characters that read alike: the readings differ
    // only in the letters the title and the phrase keep as typed.
    #expect(scalars(withCedillas("Ședință")) != scalars("Ședință"))
    let cedilla = parse(withCedillas("Ședință marți"))
    let comma = parse(withCommas("Ședință marți"))
    #expect(cedilla.plannedDayOffset == comma.plannedDayOffset)
    #expect(cedilla.phrases.map(\.kind) == comma.phrases.map(\.kind))
    #expect(scalars(cedilla.title) == scalars(withCedillas("Ședință")))
    #expect(scalars(comma.title) == scalars(withCommas("Ședință")))
  }

  @Test("Capitals read like lowercase letters, and the title keeps the capitals it was typed with")
  func capitals() {
    let lines: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("DENTIST MÂINE", "DENTIST", { $0.plannedDayOffset == 1 }),
      ("DENTIST MAINE", "DENTIST", { $0.plannedDayOffset == 1 }),
      ("RAPORT SÂMBĂTĂ", "RAPORT", { $0.plannedDayOffset == 4 }),
      ("ȘEDINȚĂ LA ORA 15", "ȘEDINȚĂ", { $0.startMinutes == 15 * 60 }),
      ("SEDINTA LA ORA 3 DUPA-AMIAZA", "SEDINTA", { $0.startMinutes == 15 * 60 }),
      ("RAPORT LA 3 ȘI JUMĂTATE", "RAPORT", { $0.startMinutes == 15 * 60 + 30 }),
      ("RAPORT PÂNĂ VINERI", "RAPORT", { $0.dueDayOffset == 3 }),
      ("RAPORT PÂNĂ LA 15 OCTOMBRIE", "RAPORT", { $0.dueDayOffset == 23 }),
      ("RAPORT PE 15 OCTOMBRIE", "RAPORT", { $0.plannedDayOffset == 23 }),
      ("RAPORT ÎN FIECARE LUNI", "RAPORT", { $0.recurrence == monday }),
      ("RAPORT ÎN ZILELE LUCRĂTOARE", "RAPORT", { $0.recurrence == workdays }),
      ("RAPORT ZILNIC", "RAPORT", { $0.recurrence == daily }),
      ("RAPORT 2 ORE", "RAPORT", { $0.estimatedMinutes == 120 }),
      ("RAPORT O ORĂ ȘI JUMĂTATE", "RAPORT", { $0.estimatedMinutes == 90 }),
      ("RAPORT URGENT", "RAPORT", { $0.priority == .p1 }),
      ("RAPORT PRIORITATE SCĂZUTĂ", "RAPORT", { $0.priority == .p3 }),
      ("Raport MARȚI la 15", "Raport", { $0.plannedDayOffset == 7 && $0.startMinutes == 15 * 60 }),
      ("Raport VINERI SEARA", "Raport", { $0.plannedDayOffset == 3 }),
    ]
    for line in lines {
      for spell in [withCommas, withCedillas] {
        let parsed = parse(spell(line.text))
        #expect(line.check(parsed), "\(line.text)")
        #expect(scalars(parsed.title) == scalars(spell(line.title)), "\(line.text): title")
      }
    }
  }

  @Test("Letters typed as a base letter and a combining mark keep their form, and an accent inside a detail word is left unread")
  func decomposedLetters() {
    // An accent in a title word changes nothing: both forms read the same, and each keeps its own scalars.
    let lines: [(typed: String, title: String)] = [
      ("Ședință vineri", "Ședință"), ("Tâmplar vineri", "Tâmplar"), ("Șef luni", "Șef"),
      ("Ședință luni la ora 15", "Ședință"), ("Ședință peste 3 zile", "Ședință"),
      ("Ședință 15 octombrie", "Ședință"), ("Ședință 30 de minute", "Ședință"),
    ]
    for line in lines {
      let composed = line.typed.precomposedStringWithCanonicalMapping
      let decomposed = line.typed.decomposedStringWithCanonicalMapping
      let expected = parse(composed)
      let parsed = parse(decomposed)
      #expect(parsed == expected, "\(line.typed)")
      #expect(!parsed.phrases.isEmpty, "\(line.typed): phrases")
      #expect(scalars(expected.title) == scalars(line.title.precomposedStringWithCanonicalMapping), "\(line.typed)")
      #expect(scalars(parsed.title) == scalars(line.title.decomposedStringWithCanonicalMapping), "\(line.typed)")
    }
    // A detail word typed with a combining accent is not read, and the line stays whole as typed.
    for line in [
      "Ședință mâine", "Ședință marți", "Ședință la 3 după-amiază", "Ședință săptămâna viitoare", "Ședință diseară",
      "Ședință prioritate scăzută",
    ] {
      let composed = line.precomposedStringWithCanonicalMapping
      let decomposed = line.decomposedStringWithCanonicalMapping
      #expect(parse(composed).phrases.count == 1, "\(line)")
      let parsed = parse(decomposed)
      #expect(parsed.phrases.isEmpty, "\(line): phrases")
      #expect(scalars(parsed.title) == scalars(decomposed), "\(line): title")
    }
    // A mark on a letter that is part of no detail changes nothing either.
    let stray = "s\u{0326}ef a\u{0306}la"
    #expect(scalars(parse("\(stray) mâine").title) == scalars(stray))
    #expect(parse("\(stray) mâine").plannedDayOffset == 1)
  }

  // MARK: - Beside other languages

  @Test("Beside Romanian, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Romanian beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Meet at 15h",
      "Meet 10h",
    ] {
      for languages in [["en", "ro"], ["ro", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Romanian writes its hours with "ora" or a colon, so "15h" and "2h" are lengths beside it.
    let hours = parse("Write the report 2h", languages: ["en", "ro"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "ro"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    // "În 15 min" is a moment in Romanian, so beside it English's "in 15 min" is no length.
    let alone = parse("Call in 15 min", languages: ["en"])
    #expect(alone.estimatedMinutes == 15)
    #expect(alone.title == "Call in")
    for languages in [["en", "ro"], ["ro", "en"]] {
      let beside = parse("Call in 15 min", languages: languages)
      #expect(beside.estimatedMinutes == nil, "\(languages)")
      #expect(beside.title == "Call in 15 min", "\(languages): title")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom mâine at 3pm", languages: ["en", "ro"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting vineri at 3pm", languages: ["en", "ro"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Dentist tomorrow", languages: ["en", "ro"]).plannedDayOffset == 1)
    let review = parse("Review mâine la 15:00 for 2 hours", languages: ["en", "ro"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english = parse("Raport mâine 3pm")
    #expect(english.plannedDayOffset == 1)
    #expect(english.startMinutes == 15 * 60)
    #expect(english.title == "Raport")
    #expect(parse("Ședință la 15h").estimatedMinutes == 15 * 60)
    #expect(parse("Raport 30 min mâine").estimatedMinutes == 30)
    #expect(parse("Raport mâine 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("Ședință tomorrow").plannedDayOffset == 1)
  }

  @Test("Lines in other languages read the same with Romanian beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"), ("تقرير قبل الخميس", "ar"),
      ("مراجعة من 3 إلى 5 مارس", "ar"), ("تماس با مادر فردا ساعت ۳ بعدازظهر", "fa"), ("ورزش هر دوشنبه", "fa"),
      ("گزارش تا جمعه", "fa"), ("امی کو فون کرنا کل شام 5 بجے", "ur"), ("رپورٹ جمعہ تک", "ur"),
      ("कल शाम 5 बजे मीटिंग", "hi"), ("रिपोर्ट सोमवार तक", "hi"), ("हर सोमवार योग 30 मिनट", "hi"),
      ("Позвонить маме завтра в 15:00", "ru"), ("Спортзал каждый понедельник", "ru"), ("Отчёт до пятницы", "ru"),
      ("Подзвонити мамі завтра о 15:00", "uk"), ("Звіт до п'ятниці", "uk"),
      ("Appeler maman demain à 15h", "fr"), ("Réunion tous les lundis à 9h", "fr"), ("Rapport avant vendredi", "fr"),
      ("Lire 30 min", "fr"), ("Réunion de 14h à 16h", "fr"), ("Vacances du 3 au 5 mai", "fr"),
      ("Courses ce soir à 19h", "fr"), ("Dentiste après-demain", "fr"), ("Payer le loyer le 5 de chaque mois", "fr"),
      ("Llamar a mamá mañana a las 15:00", "es"), ("Gimnasio cada lunes", "es"), ("Informe antes del viernes", "es"),
      ("Reunión a las 3 de la tarde", "es"), ("Vacaciones del 3 al 5 de mayo", "es"), ("Leer 30 minutos", "es"),
      ("Chiamare mamma domani alle 15:00", "it"), ("Palestra ogni lunedì", "it"), ("Relazione entro venerdì", "it"),
      ("Leggere 30 minuti", "it"),
      ("Ligar para a mãe amanhã às 15h", "pt"), ("Relatório até sexta", "pt"), ("Academia toda segunda", "pt"),
      ("Ler 30 minutos", "pt"),
      ("Zadzwonić jutro o 15:00", "pl"), ("Siłownia co poniedziałek", "pl"), ("Raport do piątku", "pl"),
      ("Czytać 30 minut", "pl"),
      ("Zahnarzt übermorgen", "de"), ("Meeting um 15 Uhr", "de"), ("Sport jeden Montag", "de"),
      ("Bericht bis Freitag", "de"), ("Urlaub vom 3. bis 5. Mai", "de"), ("Zahnarzt am Freitag", "de"),
      ("Tandarts morgen", "nl"), ("Sporten elke maandag", "nl"), ("Rapport voor vrijdag", "nl"),
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "ro"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["ro", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Romanian with another language.
    for languages in [["fr", "ro"], ["ro", "fr"]] {
      let mixed = parse("Appeler maman demain la ora 15", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Appeler maman demain à 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentist poimâine", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste 3 mai", languages: languages).plannedDayOffset == captureDayOffset("2027-05-03"), "\(languages)")
      #expect(parse("Alergare în fiecare luni", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Rapport urgent", languages: languages).priority == .p1, "\(languages)")
      expectDateRanges(
        [
          ("Vacances", "du 3 au 5 mai", "2027-05-03", "2027-05-05"),
          ("Vacanță", "de la 3 la 5 mai", "2027-05-03", "2027-05-05"),
        ], languages: languages)
    }
    #expect(parse("Dentist 下午3点 mâine", languages: ["zh", "ro"]).plannedDayOffset == 1)
    #expect(parse("Dentist מחר", languages: ["he", "ro"]).plannedDayOffset == 1)
    #expect(parse("Meeting jutro", languages: ["pl", "ro"]).plannedDayOffset == 1)
    // Romanian beside Dutch or German: each keeps its own words. "Morgen" is tomorrow in both of those, so
    // the day after tomorrow, which they write differently, tells them apart.
    for languages in [["nl", "ro"], ["ro", "nl"], ["de", "ro"], ["ro", "de"]] {
      #expect(parse("Dentist mâine la ora 15", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Alergare în fiecare luni", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Tandarts overmorgen", languages: languages).plannedDayOffset == (languages.contains("nl") ? 2 : nil), "\(languages)")
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == (languages.contains("de") ? 2 : nil), "\(languages)")
    }
  }

  @Test("Romanian words are read only for a user who reads Romanian")
  func languageGate() {
    let line = parse("Dentist poimâine", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Dentist poimâine")
    for languages in [["ro"], ["ro-RO"], ["ro_MD"], ["ro-MD"], ["en-US", "ro-RO"], ["RO"]] {
      #expect(parse("Dentist poimâine", languages: languages).plannedDayOffset == 2, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Romanian reader.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen",
      ], languages: ["ro"])
    // Romanian words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"]] {
      let parsed = parse("Dentist poimâine", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Dentist poimâine", "\(languages): title")
      #expect(parse("Ședință la ora 15", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("Alergare în fiecare luni", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("la ora 15 ", 500), ("la 3 ", 1000), ("ora 3 ", 833), ("3 ", 2500), ("de la ", 833), ("între ", 833),
      ("între 3 și 5 ", 384), ("de la 3 la 5 ", 384), ("14-16 ", 833), ("14:00-16:00 ", 416), ("15:30 ", 833),
      ("la 3 și jumătate ", 294), ("la 3 fără un sfert ", 263), ("la 3 și ", 625), ("mâine ", 833),
      ("mâine dimineața ", 312), ("în seara asta ", 357), ("luni ", 1000), ("lunea ", 833), ("în fiecare luni ", 312),
      ("în zilele lucrătoare ", 238), ("de luni până vineri ", 250), ("la două zile ", 384),
      ("din două în două zile ", 227), ("o dată la două săptămâni ", 200), ("în fiecare 15 ale lunii ", 208),
      ("15 octombrie ", 384), ("15.10.2026 ", 454), ("pe 15.10 ", 555), ("3-5 mai ", 625),
      ("de la 3 până la 5 mai ", 227), ("mai ", 1250), ("Sprint 12 - 20 mai ", 263), ("până vineri ", 416),
      ("până la ", 625), ("cel târziu ", 454), ("peste 3 zile ", 384), ("peste 3 luni ", 384),
      ("săptămâna viitoare ", 263), ("în weekend ", 454), ("30 de minute ", 384), ("30 min ", 714), ("2 ore ", 833),
      ("o oră și jumătate ", 277), ("2h ", 1666), ("jumătate de oră ", 312), ("urgent ", 714),
      ("prioritate mare ", 312), ("prio ", 1000), ("ă", 5000), ("ș", 5000), ("î", 5000), ("s\u{0326}", 2500),
      ("a\u{0306}", 2500), ("ședință ", 600), (", ", 2500), (".", 5000), ("la prânz ", 555), ("ora 3 și ", 555),
      ("între 14 și 16 ", 333), ("3.-", 1666), ("seara la 8 ", 454), ("în fiecare dimineață la 7 ", 192),
      ("de ", 1666), ("la ", 1666),
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for entry in unit {
        let line = "Anna " + String(repeating: entry.token, count: entry.repeats) + " Telefon"
        let parsed = parse(line)
        #expect(!parsed.title.isEmpty, "\(entry.token)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}
