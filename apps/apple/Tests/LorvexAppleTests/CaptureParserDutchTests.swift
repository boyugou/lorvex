import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["nl"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])

/// The unicode scalars of `text`. A title is compared by them where the typed
/// form matters, since `String` equality treats a letter with a combining mark
/// as equal to its precomposed form.
private func scalars(_ text: String) -> [Unicode.Scalar] {
  Array(text.unicodeScalars)
}

/// Dutch capture lines, read for a user whose languages include Dutch.
@Suite("Capture parser Dutch")
struct CaptureParserDutchTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Tandarts morgen")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Tandarts")
    #expect(line.phrases.map(\.text) == ["morgen"])

    let days: [(text: String, offset: Int)] = [
      ("Tandarts vandaag", 0), ("Tandarts vanavond", 0), ("Tandarts vanochtend", 0), ("Tandarts vanmorgen", 0),
      ("Tandarts vanmiddag", 0), ("Tandarts vannacht", 0),
      ("Tandarts morgen", 1), ("Tandarts morgenochtend", 1), ("Tandarts morgenmiddag", 1),
      ("Tandarts morgenavond", 1), ("Tandarts morgen vroeg", 1), ("Tandarts morgen avond", 1),
      ("Tandarts overmorgen", 2),
      ("Tandarts over 1 dag", 1), ("Tandarts over 3 dagen", 3), ("Tandarts over drie dagen", 3),
      ("Tandarts over een week", 7), ("Tandarts over 1 week", 7), ("Tandarts over twee weken", 14),
      ("Tandarts over 2 weken", 14), ("Tandarts over 3 weken", 21),
      ("Tandarts volgende week", 7), ("Tandarts volgende week maandag", 6), ("Tandarts maandag volgende week", 6),
      ("Tandarts dit weekend", 4), ("Tandarts volgend weekend", 11), ("Tandarts in het weekend", 4),
      ("Tandarts tijdens het weekend", 4),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Tandarts", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Morgen tandarts")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "tandarts")
    let capitals = parse("MORGEN TANDARTS")
    #expect(capitals.plannedDayOffset == 1)
    #expect(capitals.title == "TANDARTS")
    // A number of days or weeks is read with its count only.
    expectLinesUnread(["Tandarts over anderhalve week", "Tandarts over een tijdje"], languages: ["nl"])
  }

  @Test("Morgen is tomorrow, and the morning only after a word that makes it a noun")
  func morgen() {
    #expect(parse("Tandarts morgen").plannedDayOffset == 1)
    #expect(parse("TANDARTS MORGEN").plannedDayOffset == 1)
    #expect(parse("TANDARTS MORGEN").title == "TANDARTS")
    expectLinesUnread(
      [
        "Goedemorgen zeggen", "Goede morgen zeggen", "Goedemorgen zeggen tegen Piet", "De morgen na de storm",
        "Morgenrood fotograferen",
      ], languages: ["nl"])
    // Every morning is a daily repeat, which is no day.
    let daily = parse("Elke morgen koffie")
    #expect(daily.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(daily.plannedDayOffset == nil)
    #expect(daily.title == "koffie")
  }

  @Test("An evening makes a clock time the evening's")
  func evenings() {
    for (line, day, minutes) in [
      ("Afspraak vanavond om 7", 0, 19 * 60), ("Afspraak vanavond om 8", 0, 20 * 60),
      ("Afspraak vanavond 7:30", 0, 19 * 60 + 30), ("Afspraak vanavond 8 uur", 0, 20 * 60),
      ("Afspraak morgenavond om 7", 1, 19 * 60), ("Afspraak morgenavond om 7 uur", 1, 19 * 60),
      ("Afspraak morgenavond 7:30", 1, 19 * 60 + 30), ("Afspraak morgen avond om 8", 1, 20 * 60),
      ("Afspraak overmorgenavond om 7", 2, 19 * 60), ("Afspraak zondagavond om 8", 5, 20 * 60),
      ("Afspraak vandaag avond om 7", 0, 19 * 60),
      // Another part of the day, or none, keeps the hour as it is.
      ("Afspraak morgenochtend om 7", 1, 7 * 60), ("Afspraak morgenochtend om 8", 1, 8 * 60),
      ("Afspraak morgenmiddag om 3", 1, 15 * 60), ("Afspraak morgenmiddag om 2", 1, 14 * 60),
      ("Afspraak maandagmiddag om 2", 6, 14 * 60), ("Afspraak morgen om 7", 1, 7 * 60),
      ("Afspraak vandaag om 7", 0, 7 * 60), ("Afspraak morgen vroeg om 7", 1, 7 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Afspraak", "\(line): title")
    }
    // Twelve in the evening is midnight, which ends the day.
    let tonight = parse("Afspraak vanavond om 12")
    #expect(tonight.plannedDayOffset == 1)
    #expect(tonight.startMinutes == 0)
    let tomorrowNight = parse("Afspraak morgenavond om 12")
    #expect(tomorrowNight.plannedDayOffset == 2)
    #expect(tomorrowNight.startMinutes == 0)
    // An evening on its own plans the day and no time.
    let evening = parse("Tandarts morgenavond")
    #expect(evening.plannedDayOffset == 1)
    #expect(evening.startMinutes == nil)
    // The evening meals give a bare hour the evening, as "vanavond" does.
    for (line, minutes, title) in [
      ("Avondeten om 7", 19 * 60, "Avondeten"), ("Diner om 8", 20 * 60, "Diner"), ("Diner om 8 uur", 20 * 60, "Diner"),
      ("Ontbijt om 8", 8 * 60, "Ontbijt"), ("Lunch om 12", 12 * 60, "Lunch"), ("Lunch om 1", 13 * 60, "Lunch"),
    ] {
      let meal = parse(line)
      #expect(meal.startMinutes == minutes, "\(line)")
      #expect(meal.title == title, "\(line)")
    }
    // The part of the day as a noun, or in a compound, names no day.
    expectLinesUnread(["Avondeten koken", "Vrijdagmiddagborrel organiseren", "Zon in de zomer"], languages: ["nl"])
  }

  @Test("Past days are not read")
  func pastDays() {
    expectLinesUnread(
      [
        "Tandarts gisteren", "Tandarts eergisteren", "Tandarts gisteravond", "Tandarts gisterenavond",
        "Tandarts gisteren morgen", "Tandarts vorige week", "Tandarts afgelopen week", "Tandarts vorige maandag",
        "Tandarts vorige dinsdag", "Tandarts afgelopen vrijdag", "Tandarts vorig weekend", "Tandarts afgelopen weekend",
      ], languages: ["nl"])
    // The time that follows a past day still reads.
    let time = parse("Tandarts gisteren om 3 uur")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Tandarts gisteren")
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Tandarts maandag", 6), ("Tandarts Maandag", 6), ("Tandarts MAANDAG", 6), ("Tandarts dinsdag", 7),
      ("Tandarts op dinsdag", 7), ("Tandarts op zaterdag", 4), ("Tandarts zondag", 5), ("Tandarts vanaf maandag", 6),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "deze dinsdag" is today.
      ("Tandarts deze dinsdag", 0), ("Tandarts deze vrijdag", 3), ("Tandarts aanstaande vrijdag", 3),
      ("Tandarts aankomende vrijdag", 3), ("Tandarts komende vrijdag", 3), ("Tandarts volgende vrijdag", 10),
      // A weekday abbreviation counts after a word that points at it.
      ("Tandarts op ma", 6), ("Tandarts op ma.", 6), ("Tandarts op di", 7), ("Tandarts op wo", 1),
      ("Tandarts op do", 2), ("Tandarts op vr", 3), ("Tandarts op za", 4), ("Tandarts op zo", 5),
      ("Tandarts komende ma", 6), ("Tandarts deze wo", 1), ("Tandarts volgende do", 9),
      // A part of the day written onto the weekday or after it.
      ("Tandarts vrijdagavond", 3), ("Tandarts vrijdag avond", 3), ("Tandarts vrijdagochtend", 3),
      ("Tandarts maandagmorgen", 6),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Tandarts", "\(weekday.text): title")
    }
    let timed = parse("Vergadering maandag om 9 uur")
    #expect(timed.plannedDayOffset == 6)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Vergadering")
    let both = parse("Overleg op maandag")
    #expect(both.plannedDayOffset == 6)
    #expect(both.title == "Overleg")
    let opening = parse("Maandag overleg")
    #expect(opening.plannedDayOffset == 6)
    #expect(opening.title == "overleg")
  }

  @Test("A weekday that is a name, an abbreviation alone, or part of a compound stays in the title")
  func weekdayNames() {
    expectLinesUnread(
      [
        "Tandarts ma", "Tandarts di", "Tandarts do", "Wo ruimen", "Do het af", "Zo snel mogelijk bellen",
        "Maandag-meeting", "Maandag-meeting plannen", "Tandarts maandag-meeting", "Koffie met mevrouw Maandag",
        "Vrijdagmiddagborrel organiseren",
      ], languages: ["nl"])
    // An abbreviation after no word that points at it is no weekday, but the time beside it still reads.
    let time = parse("Tandarts om 3 uur ma")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Tandarts ma")
    // A weekday that opens the line is the day, and a weekday after "behalve" is left out.
    let except = parse("Afval elke dag behalve zondag")
    #expect(except.plannedDayOffset == nil)
    #expect(except.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(except.title == "Afval behalve zondag")
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Tandarts 15 oktober", "Tandarts", "2026-10-15"),
      ("Tandarts op 15 oktober", "Tandarts", "2026-10-15"),
      ("Tandarts 15 okt", "Tandarts", "2026-10-15"),
      ("Tandarts 15 okt.", "Tandarts", "2026-10-15"),
      ("Tandarts 15 october", "Tandarts", "2026-10-15"),
      ("TANDARTS OP 15 OKTOBER", "TANDARTS", "2026-10-15"),
      ("Tandarts 1 mei 2027", "Tandarts", "2027-05-01"),
      ("Tandarts 3 mei", "Tandarts", "2027-05-03"),
      ("Tandarts 12 juni 2027", "Tandarts", "2027-06-12"),
      ("Tandarts 15-10-2026", "Tandarts", "2026-10-15"),
      ("Tandarts 15/10/2026", "Tandarts", "2026-10-15"),
      ("Tandarts 15.10.2026", "Tandarts", "2026-10-15"),
      ("Tandarts 15.10.", "Tandarts", "2026-10-15"),
      ("Tandarts op 15-10", "Tandarts", "2026-10-15"),
      ("Tandarts op 15/10", "Tandarts", "2026-10-15"),
      ("Tandarts op 15.10", "Tandarts", "2026-10-15"),
      ("Tandarts vanaf 15-10", "Tandarts", "2026-10-15"),
      ("Tandarts vanaf 15/10", "Tandarts", "2026-10-15"),
      ("Tandarts 3 januari", "Tandarts", "2027-01-03"),
      ("Tandarts 3 jan", "Tandarts", "2027-01-03"),
      ("Tandarts 3 februari", "Tandarts", "2027-02-03"),
      ("Tandarts 3 feb", "Tandarts", "2027-02-03"),
      ("Tandarts 3 maart", "Tandarts", "2027-03-03"),
      ("Tandarts 3 mrt", "Tandarts", "2027-03-03"),
      ("Tandarts 3 april", "Tandarts", "2027-04-03"),
      ("Tandarts 3 apr", "Tandarts", "2027-04-03"),
      ("Tandarts 3 jun", "Tandarts", "2027-06-03"),
      ("Tandarts 3 juli", "Tandarts", "2027-07-03"),
      ("Tandarts 3 jul", "Tandarts", "2027-07-03"),
      ("Tandarts 3 augustus", "Tandarts", "2027-08-03"),
      ("Tandarts 3 aug", "Tandarts", "2027-08-03"),
      ("Tandarts 3 sept", "Tandarts", "2027-09-03"),
      ("Tandarts 3 sep.", "Tandarts", "2027-09-03"),
      ("Tandarts 3 okt", "Tandarts", "2026-10-03"),
      ("Tandarts 3 november", "Tandarts", "2026-11-03"),
      ("Tandarts 3 nov", "Tandarts", "2026-11-03"),
      ("Tandarts 3 december", "Tandarts", "2026-12-03"),
      ("Tandarts 3 dec", "Tandarts", "2026-12-03"),
      // A weekday before the date is part of it, as a name or as an abbreviation with its dot.
      ("Tandarts vrijdag 16 oktober", "Tandarts", "2026-10-16"),
      ("Tandarts op vrijdag 16 oktober", "Tandarts", "2026-10-16"),
      ("Tandarts vr. 16 okt", "Tandarts", "2026-10-16"),
      ("Tandarts maandag 5 oktober", "Tandarts", "2026-10-05"),
      ("Tandarts dinsdag 22 september", "Tandarts", "2026-09-22"),
      ("Tandarts woensdag 23 september", "Tandarts", "2026-09-23"),
      ("Verjaardag Anna 15 oktober", "Verjaardag Anna", "2026-10-15"),
      ("Dinsdag 22 september afspraak", "afspraak", "2026-09-22"),
      ("Uitjes 5 mei", "Uitjes", "2027-05-05"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Afspraak donderdag 15 oktober om 14:30")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Afspraak")
  }

  @Test("Numbers that are no date, a past year, and a day the month does not have stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers without a word that makes them a date, and a bare month.
        "Tandarts 15-10", "Tandarts 15/10", "Tandarts 15.10", "Koffie in mei", "In maart naar Spanje",
        // A day the month does not have, a year that is past, and an ordinal ending.
        "Afspraak 31 februari", "Afspraak 15 oktober 2025", "Afspraak 15e oktober",
        // Chapters, versions, rooms, scores, numbers, percentages, and prices.
        "Hoofdstuk 3.5 lezen", "Versie 2.3.4 uitbrengen", "Pagina 15-10 lezen", "Kamer 15.10 boeken",
        "Score 3-1 noteren", "Nummer 15/10 bellen", "15% korting", "Prijs 15,50 betalen", "€15,30 betalen",
        "15.30 euro betalen",
      ], languages: ["nl"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Vakantie", "van 3 tot 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "van 3 tot en met 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "3 t/m 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "3 tm 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "3-5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "van 3 mei tot 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "3 mei t/m 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "3 mei - 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "van 30 mei tot 2 juni", "2027-05-30", "2027-06-02"),
        ("Vakantie", "tussen 3 en 5 mei", "2027-05-03", "2027-05-05"),
        ("Vakantie", "van 3 tot 5 mei 2027", "2027-05-03", "2027-05-05"),
      ], languages: ["nl"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Vakantie 5-3 mei", "Vakantie van 5 tot 3 mei", "Vakantie van 3 mei tot 3 mei", "Pagina's 3-5 lezen",
        "Prijs 3-5 euro", "Hoofdstuk 3-5 lezen",
      ], languages: ["nl"])
    // "Tot" joins a day alone to a day with its month only after "van": the end is read as a due day.
    let missingVan = parse("Vakantie 3 tot 5 mei")
    #expect(missingVan.plannedDayOffset == nil)
    #expect(missingVan.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(missingVan.title == "Vakantie 3")
    // Two bare numbers after "van" and "tot" are hours.
    let bare = parse("Vakantie van 3 tot 5")
    #expect(bare.plannedDayOffset == nil)
    #expect(bare.dueDayOffset == nil)
    #expect(bare.startMinutes == 15 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A day alone opens a range joined by a spaced dash only after nothing that names a day")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 mei")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    let meeting = parse("Vergadering 12 - 14 oktober")
    #expect(meeting.title == "Vergadering 12")
    #expect(meeting.plannedDayOffset == captureDayOffset("2026-10-14"))
    #expect(meeting.dueDayOffset == nil)
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time still reads")
  func rangeTakesBothDays() {
    let line = parse("Vakantie van 3 tot 5 mei morgen")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Vakantie morgen")
    let timed = parse("Vakantie 3 t/m 5 mei om 9 uur")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Vakantie")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    expectDateRanges(
      [
        ("Conferentie", "van maandag tot woensdag", "2026-09-28", "2026-09-30"),
        ("Conferentie", "maandag t/m woensdag", "2026-09-28", "2026-09-30"),
        ("Conferentie", "van ma t/m wo", "2026-09-28", "2026-09-30"),
        ("Conferentie", "van ma. tot wo.", "2026-09-28", "2026-09-30"),
        ("Conferentie", "vrijdag t/m zondag", "2026-09-25", "2026-09-27"),
        ("Conferentie", "van vrijdag tot maandag", "2026-09-25", "2026-09-28"),
        ("Conferentie", "van zaterdag tot en met zondag", "2026-09-26", "2026-09-27"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Conferentie", "van dinsdag tot donderdag", "2026-09-29", "2026-10-01"),
      ], languages: ["nl"])
    // Monday to Friday is the working week, which repeats.
    for text in [
      "Sporten ma-vr", "Sporten van ma-vr", "Sporten ma t/m vr", "Sporten maandag t/m vrijdag",
      "Sporten van maandag tot en met vrijdag",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Sporten", "\(text): title")
    }
    // A weekday after a title is a name, so only the due day reads.
    let name = parse("Mevrouw Maandag t/m woensdag")
    #expect(name.plannedDayOffset == nil)
    #expect(name.dueDayOffset == 1)
    #expect(name.title == "Mevrouw Maandag")
  }

  // MARK: - Due days

  @Test("Due days: voor, tot, uiterlijk, tegen, deadline, and einddatum")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Rapport voor vrijdag", "Rapport", 3),
      ("Rapport tot vrijdag", "Rapport", 3),
      ("Rapport tot en met vrijdag", "Rapport", 3),
      ("Rapport t/m vrijdag", "Rapport", 3),
      ("Rapport tegen vrijdag", "Rapport", 3),
      ("Rapport uiterlijk vrijdag", "Rapport", 3),
      ("Rapport uiterlijk op vrijdag", "Rapport", 3),
      ("Rapport ten laatste vrijdag", "Rapport", 3),
      ("Rapport deadline vrijdag", "Rapport", 3),
      ("Rapport deadline: vrijdag", "Rapport", 3),
      ("Rapport vrijdag uiterlijk", "Rapport", 3),
      ("Rapport inleverdatum vrijdag", "Rapport", 3),
      ("Rapport uiterlijk morgen", "Rapport", 1),
      ("Rapport voor morgen", "Rapport", 1),
      ("Rapport voor overmorgen", "Rapport", 2),
      ("Rapport voor maandag", "Rapport", 6),
      ("Rapport tot zondag", "Rapport", 5),
      ("Rapport tot en met zaterdag", "Rapport", 4),
      ("Rapport voor deze vrijdag", "Rapport", 3),
      ("Rapport voor komende vrijdag", "Rapport", 3),
      ("Rapport voor vrijdagavond", "Rapport", 3),
      ("Rapport voor 15 oktober", "Rapport", 23),
      ("Rapport voor 15 okt", "Rapport", 23),
      ("Rapport tot 15-10", "Rapport", 23),
      ("Rapport t/m 15-10", "Rapport", 23),
      ("Rapport einddatum 15 oktober", "Rapport", 23),
      ("Rapport voor volgende week", "Rapport", 7),
      ("Rapport voor volgende week vrijdag", "Rapport", 10),
      ("Cadeau kopen voor 15 oktober", "Cadeau kopen", 23),
      ("Cadeau kopen uiterlijk 14 oktober", "Cadeau kopen", 22),
      ("Cadeau kopen tot en met 14 oktober", "Cadeau kopen", 22),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Rapport voor vrijdag vandaag")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Rapport")
    // A due phrase that opens the line.
    let opening = parse("Tot maandag wachten")
    #expect(opening.dueDayOffset == 6)
    #expect(opening.title == "wachten")
    // The weekend names no due day, and a weekday abbreviation after a deadline word is no day.
    expectLinesUnread(
      [
        "Rapport voor het weekend", "Rapport voor dit weekend", "Rapport voor ma", "Rapport tot ma",
        "Rapport uiterlijk vr", "Rapport voor vr.",
      ], languages: ["nl"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Rapport tot 17 uur", "Rapport tot 17:00", "Rapport voor 17:00", "Rapport tegen 17 uur",
        "Rapport uiterlijk 17:00", "Rapport uiterlijk om 17 uur", "Rapport na 18 uur", "Rapport niet later dan 17 uur",
        "Rapport tot half vijf", "Rapport voor 3 uur", "Rapport tot 3 uur", "Rapport voor 15:00 uur",
        "Rapport voor 9u",
      ], languages: ["nl"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Rapport voor vrijdag om 17 uur", "Rapport om 17 uur", 3), ("Rapport voor vrijdag 17 uur", "Rapport 17 uur", 3),
      ("Rapport voor vrijdag 17:00", "Rapport 17:00", 3), ("Rapport uiterlijk vrijdag 17:00", "Rapport 17:00", 3),
      ("Rapport uiterlijk vrijdag om 17:00", "Rapport om 17:00", 3),
      ("Rapport uiterlijk maandag om 9:00", "Rapport om 9:00", 6), ("Rapport voor maandag 9 uur", "Rapport 9 uur", 6),
      ("Cadeau kopen tot 14 oktober om 17:00", "Cadeau kopen om 17:00", 22),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A time range that ends in a clock time is still a range.
    let range = parse("Afspraak van 14 tot 17 uur")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 180)
    #expect(range.title == "Afspraak")
    // Without Dutch, English reads the clock time and leaves the word.
    let english = parse("Rapport tot 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
    #expect(english.title == "Rapport tot")
  }

  // MARK: - Clock times

  @Test("Clock times: om, uur, u, a part of the day, noon, and midnight")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Afspraak om 15:00", 15 * 60), ("Afspraak om 15.30", 15 * 60 + 30), ("Afspraak om 15.30 uur", 15 * 60 + 30),
      ("Afspraak om 15u", 15 * 60), ("Afspraak om 15u30", 15 * 60 + 30), ("Afspraak om 3 uur", 15 * 60),
      ("Afspraak om 9", 9 * 60), ("Afspraak om 9 uur", 9 * 60), ("Afspraak om 12 uur", 12 * 60),
      ("Afspraak om 12", 12 * 60), ("Afspraak om 12u", 12 * 60), ("Afspraak om 18 uur", 18 * 60),
      ("Afspraak om 18:30", 18 * 60 + 30), ("Afspraak om 23:59", 23 * 60 + 59), ("Afspraak om 09:00", 9 * 60),
      ("Afspraak 15:00", 15 * 60), ("Afspraak 15:30 uur", 15 * 60 + 30), ("Afspraak 15u", 15 * 60),
      ("Afspraak 15u30", 15 * 60 + 30), ("Afspraak 12u", 12 * 60), ("Afspraak 00:30", 30),
      ("Afspraak 08:30", 8 * 60 + 30), ("Afspraak 8.30 uur", 8 * 60 + 30), ("Afspraak om 8.30", 8 * 60 + 30),
      ("Afspraak om 10.15", 10 * 60 + 15), ("Afspraak vanaf 10.15", 10 * 60 + 15), ("Afspraak 5.10 uur", 17 * 60 + 10),
      ("Afspraak vanaf 15:30", 15 * 60 + 30), ("Afspraak rond 15:00", 15 * 60), ("Afspraak omstreeks 15:00", 15 * 60),
      ("Afspraak circa 15:00", 15 * 60), ("Afspraak vanaf 3 uur", 15 * 60), ("Afspraak om 0:30", 30),
      ("Afspraak donderdag 14 uur", 14 * 60), ("Afspraak donderdag 14.00 uur", 14 * 60),
      ("Afspraak donderdag 14:00 uur", 14 * 60),
      // A part of the day, with the apostrophe straight, curly, or left out.
      ("Afspraak om 3 uur 's middags", 15 * 60), ("Afspraak 3 uur 's middags", 15 * 60),
      ("Afspraak 3 uur ’s middags", 15 * 60), ("Afspraak 3 uur s middags", 15 * 60),
      ("Afspraak 3 uur middags", 15 * 60), ("Afspraak 8 uur 's ochtends", 8 * 60),
      ("Afspraak 8 uur 's morgens", 8 * 60), ("Afspraak 8 uur 's avonds", 20 * 60),
      ("Afspraak 12 uur 's middags", 12 * 60), ("Afspraak 11 uur 's nachts", 23 * 60),
      ("Afspraak 6 uur 's ochtends", 6 * 60), ("Afspraak om 5 uur 's ochtends", 5 * 60),
      ("Afspraak om 6 uur 's avonds", 18 * 60), ("Afspraak om 7 uur 's avonds", 19 * 60),
      ("Afspraak om 11 uur 's avonds", 23 * 60), ("Afspraak om 11 uur 's ochtends", 11 * 60),
      ("Afspraak om 1 uur 's middags", 13 * 60), ("Afspraak om 13 uur 's middags", 13 * 60),
      ("Afspraak om 15 uur 's middags", 15 * 60), ("Afspraak 3 uur in de middag", 15 * 60),
      ("Afspraak 8 uur in de ochtend", 8 * 60), ("Afspraak 8 uur in de avond", 20 * 60),
      ("Afspraak 7 uur avonds", 19 * 60), ("Afspraak 7 avonds", 19 * 60), ("Afspraak 8 's avonds", 20 * 60),
      ("Afspraak om 7 's avonds", 19 * 60), ("Afspraak 7 's avonds", 19 * 60), ("Afspraak 7:30 's avonds", 19 * 60 + 30),
      ("Afspraak 3:30 's middags", 15 * 60 + 30), ("Afspraak 20:30 's avonds", 20 * 60 + 30),
      ("Afspraak 8:30 's morgens", 8 * 60 + 30),
      // The adverb of a part of the day before the hour.
      ("Afspraak 's avonds om 8", 20 * 60), ("Afspraak 's avonds om 8 uur", 20 * 60),
      ("Afspraak avonds om 8", 20 * 60), ("Afspraak ’s avonds om 8", 20 * 60), ("Afspraak s avonds om 8", 20 * 60),
      ("Afspraak 's ochtends om 8", 8 * 60), ("Afspraak 's avonds 8:30", 20 * 60 + 30),
      ("Afspraak 's avonds 8 uur", 20 * 60), ("Afspraak 's middags 3 uur", 15 * 60),
      ("Afspraak morgen 's avonds om 8", 20 * 60), ("Sporten 's morgens om 7", 7 * 60),
      ("Sporten 's morgens 7 uur", 7 * 60),
      // AM and PM after a lead take the lead with them.
      ("Afspraak om 3pm", 15 * 60), ("Afspraak om 3:30 pm", 15 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title.hasPrefix("Afspraak") || parsed.title.hasPrefix("Sporten"), "\(line.text): title")
      #expect(parsed.phrases.count >= 1, "\(line.text): phrases")
    }
    // The title is what the time leaves.
    #expect(parse("Afspraak om 3 uur 's middags").title == "Afspraak")
    #expect(parse("Afspraak om 3:30 pm").title == "Afspraak")
    #expect(parse("Oma bellen om 3 uur").title == "Oma bellen")
  }

  @Test("After midnight: 's nachts, 24 uur, and middernacht run past the midnight that ends the day")
  func afterMidnight() {
    for (line, minutes) in [
      ("Afspraak 2 uur 's nachts", 2 * 60), ("Afspraak om 1 uur 's nachts", 60), ("Afspraak 's nachts om 2", 2 * 60),
      ("Afspraak om 12 uur 's nachts", 0), ("Afspraak om middernacht", 0), ("Afspraak om 24 uur", 0),
      ("Wandelen vannacht om 2 uur", 2 * 60), ("Wandelen vannacht om 12 uur", 0),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == 1, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == String(line.prefix { $0 != " " }), "\(line): title")
    }
    // Eleven at night is still the day itself, and 24:00 is no time of day.
    #expect(parse("Afspraak 11 uur 's nachts").plannedDayOffset == nil)
    expectLinesUnread(["Afspraak 24:00"], languages: ["nl"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func twelveHourRules() {
    for (line, minutes) in [
      ("Afspraak om 1", 13 * 60), ("Afspraak om 1 uur", 13 * 60), ("Afspraak om 3", 15 * 60),
      ("Afspraak om 6 uur", 18 * 60), ("Afspraak om 6", 18 * 60), ("Afspraak om 7", 7 * 60),
      ("Afspraak om 06:00", 6 * 60), ("Afspraak om 06", 6 * 60), ("Afspraak om 11", 11 * 60),
      ("Afspraak om 12", 12 * 60), ("Afspraak om 5.10", 17 * 60 + 10), ("Afspraak 2u", 14 * 60),
      ("Afspraak 2u30", 14 * 60 + 30), ("Lunch om 1", 13 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
    }
  }

  @Test("Spoken times: half, kwart, over, and voor name the hour that follows")
  func spokenTimes() {
    let spoken: [(text: String, minutes: Int)] = [
      ("Afspraak half vier", 15 * 60 + 30), ("Afspraak om half vier", 15 * 60 + 30),
      ("Afspraak om half 4", 15 * 60 + 30), ("Afspraak om half zeven", 18 * 60 + 30),
      ("Afspraak half 12", 11 * 60 + 30), ("Afspraak om half een", 12 * 60 + 30),
      ("Afspraak om half één", 12 * 60 + 30), ("Afspraak om half twaalf", 11 * 60 + 30),
      ("Afspraak kwart over drie", 15 * 60 + 15), ("Afspraak om kwart over 3", 15 * 60 + 15),
      ("Afspraak kwart voor vier", 15 * 60 + 45), ("Afspraak om kwart voor 4", 15 * 60 + 45),
      ("Afspraak om tien over drie", 15 * 60 + 10), ("Afspraak om tien voor vier", 15 * 60 + 50),
      ("Afspraak om vijf voor half vier", 15 * 60 + 25), ("Afspraak om vijf over half vier", 15 * 60 + 35),
      ("Afspraak om kwart over drie 's middags", 15 * 60 + 15), ("Afspraak om half vier 's middags", 15 * 60 + 30),
      ("Afspraak half acht 's avonds", 19 * 60 + 30), ("Afspraak rond half vier", 15 * 60 + 30),
      ("Bellen vanmiddag om half drie", 14 * 60 + 30), ("Sporten morgenochtend half zeven", 6 * 60 + 30),
      ("Sporten morgenochtend om half zeven", 6 * 60 + 30), ("Sporten overmorgen om kwart voor acht", 7 * 60 + 45),
      ("Afspraak vanavond om half 8", 19 * 60 + 30), ("MEETING OM HALF VIER", 15 * 60 + 30),
    ]
    for line in spoken {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
    }
    // Half and a quarter that sit before an hour with no lead read; a number of minutes needs "om".
    expectLinesUnread(["Afspraak half een", "Afspraak tien over drie"], languages: ["nl"])
    let title = parse("Afspraak om half vier met Anna")
    #expect(title.title == "Afspraak met Anna")
    #expect(title.startMinutes == 15 * 60 + 30)
  }

  @Test("A bare hour counts as a time only before a word that can follow a time, and a count of things is not")
  func bareHours() {
    for (line, title, minutes) in [
      ("Afspraak om 3 met Anna", "Afspraak met Anna", 15 * 60), ("Oma bellen om 3", "Oma bellen", 15 * 60),
      ("Om 5 uur opstaan", "opstaan", 17 * 60), ("Om 7 opstaan", "opstaan", 7 * 60),
      ("Tandarts om 3, Anna", "Tandarts, Anna", 15 * 60), ("Tandarts om 3 en dan boodschappen", "Tandarts en dan boodschappen", 15 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
      #expect(parsed.title == title, "\(line): title")
    }
    expectLinesUnread(
      [
        "Afspraak om 3 koekjes", "Om 3 koekjes vragen", "Om 5 verhogen", "3 koekjes kopen",
        "Pizza bestellen voor 4 personen", "4 personen uitnodigen", "Mail Piet voor 3 uur", "Wacht tot 5 uur",
        "Taart bakken 3 eieren", "Afspraak 24:00", "Afspraak 8.30", "Afspraak 10.15", "Afspraak 5.10",
        "Afspraak om 11 uur 's middags", "Afspraak om 12 uur 's avonds", "Afspraak om 15 uur 's ochtends",
      ], languages: ["nl"])
  }

  @Test("Time ranges: van with tot, tussen with en, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Afspraak van 14 tot 16 uur", 14 * 60, 120), ("Afspraak van 14:00 tot 16:00", 14 * 60, 120),
      ("Afspraak van 14.00 tot 16.00 uur", 14 * 60, 120), ("Afspraak van 9 uur tot 17 uur", 9 * 60, 480),
      ("Afspraak van 15u tot 17u", 15 * 60, 120), ("Afspraak van 9 tot 12", 9 * 60, 180),
      ("Afspraak van 9 tot 12 uur", 9 * 60, 180), ("Afspraak van 9 uur tot 12 uur", 9 * 60, 180),
      ("Afspraak van 3 tot 5", 15 * 60, 120), ("Afspraak van 3 uur tot 5 uur", 15 * 60, 120),
      ("Afspraak van 8 tot 10 uur 's ochtends", 8 * 60, 120), ("Afspraak van 2 tot 4 uur 's middags", 14 * 60, 120),
      ("Afspraak tussen 14 en 16 uur", 14 * 60, 120), ("Afspraak tussen 14:00 en 16:00", 14 * 60, 120),
      ("Afspraak tussen 3 en 5 uur", 15 * 60, 120), ("Afspraak tussen 9 en 12", 9 * 60, 180),
      ("Afspraak tussen 2 en 4 uur 's middags", 14 * 60, 120), ("Afspraak 14-16 uur", 14 * 60, 120),
      ("Afspraak 14:00-16:00", 14 * 60, 120), ("Afspraak 14:00 - 16:00 uur", 14 * 60, 120),
      ("Afspraak 9-17 uur", 9 * 60, 480), ("Afspraak 9u-17u", 9 * 60, 480), ("Tandarts om 3-4", 15 * 60, 60),
      ("Tandarts 3-4 uur", 15 * 60, 60), ("Tandarts 15:30-16:30", 15 * 60 + 30, 60), ("Tandarts 15-17 uur", 15 * 60, 120),
      ("Tandarts van 15 tot 17 uur", 15 * 60, 120),
      // Spoken sides.
      ("Afspraak van half 3 tot half 5", 14 * 60 + 30, 120), ("Afspraak van half drie tot half vijf", 14 * 60 + 30, 120),
      ("Afspraak van half 3 tot 5 uur", 14 * 60 + 30, 150), ("Afspraak van 2 tot half 5", 14 * 60, 150),
      ("Afspraak half 3 - half 5", 14 * 60 + 30, 120),
      ("Afspraak van kwart over 3 tot kwart voor 5", 15 * 60 + 15, 90),
      ("Afspraak van half een tot half twee", 12 * 60 + 30, 60), ("Afspraak van half 12 tot half 2", 11 * 60 + 30, 120),
      ("Afspraak van half 8 tot half 10 's avonds", 19 * 60 + 30, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title.hasPrefix("Afspraak") || parsed.title.hasPrefix("Tandarts"), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let evening = parse("Afspraak vanavond van half 8 tot half 10")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60 + 30)
    #expect(evening.estimatedMinutes == 120)
    #expect(parse("Afspraak van half drie tot half vijf met Anna").title == "Afspraak met Anna")
    // Numbers that count something are no range of hours, and neither are two bare hours whose end
    // comes before a start on the 24-hour clock.
    expectLinesUnread(
      [
        "Afspraak van 15 tot 10", "Afspraak tussen 15 en 10",
        "Afspraak hoofdstuk 3 tot 5", "Afspraak tussen 3 en 5 mensen", "Afspraak tussen 10 en 15 euro",
        "Prijs tussen 5 en 10", "Budget tussen 5 en 10", "Salaris tussen 3 en 5", "Tandarts 1/2 uur",
      ], languages: ["nl"])
  }

  @Test("An hour count with uur is a length alone, and a clock time after a lead, a day, or a part of the day")
  func uurIsLengthOrTime() {
    // Alone, a count of hours is a length.
    for (line, minutes) in [("Tandarts 3 uur", 180), ("Afspraak 3 uur", 180), ("Afspraak 12 uur", 720)] {
      let parsed = parse(line)
      #expect(parsed.estimatedMinutes == minutes, "\(line)")
      #expect(parsed.startMinutes == nil, "\(line): time")
    }
    // After a day or a date it is the time of that day.
    for (line, day, minutes) in [
      ("Rapport morgen 3 uur", 1, 15 * 60), ("Rapport morgen 9 uur", 1, 9 * 60),
      ("Rapport morgen 9 uur 's ochtends", 1, 9 * 60), ("Rapport morgen 14 uur", 1, 14 * 60),
      ("Rapport morgen om 14 uur", 1, 14 * 60), ("Rapport morgen om 14:30 uur", 1, 14 * 60 + 30),
      ("Tandarts vrijdag 3 uur", 3, 15 * 60), ("Tandarts vrijdag 14 uur", 3, 14 * 60),
      ("Tandarts vrijdagavond 8 uur", 3, 20 * 60), ("Tandarts 15 oktober 9 uur", 23, 9 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.estimatedMinutes == nil, "\(line): length")
    }
    // "Lang" or a minute unit makes it a length after a day.
    let long = parse("Rapport morgen 3 uur lang")
    #expect(long.plannedDayOffset == 1)
    #expect(long.estimatedMinutes == 180)
    #expect(long.startMinutes == nil)
    let minutes = parse("Tandarts vrijdag 20 min")
    #expect(minutes.plannedDayOffset == 3)
    #expect(minutes.estimatedMinutes == 20)
    // Two-digit minutes after "uur" make a clock time, and "min" a length.
    #expect(parse("Rapport 1 uur 30").startMinutes == 13 * 60 + 30)
    #expect(parse("Rapport 1 uur 30 min").estimatedMinutes == 90)
    // An hour above twelve with no lead or day is not read.
    expectLinesUnread(["Lunch 13 uur", "Tandarts 14 uur", "Rapport 13 uur"], languages: ["nl"])
  }

  @Test("An hour written with u is a clock time, and one written with h is a length of hours")
  func uAndH() {
    for (line, minutes) in [("Meeting om 15u", 15 * 60), ("Meeting 15u", 15 * 60), ("Rapport 2u", 14 * 60), ("Rapport 2u30", 14 * 60 + 30)] {
      #expect(parse(line).startMinutes == minutes, "\(line)")
    }
    // A decimal is a length of hours even with u.
    #expect(parse("Rapport 1,5u").estimatedMinutes == 90)
    #expect(parse("Rapport 2h").estimatedMinutes == 120)
    #expect(parse("Rapport 2h").startMinutes == nil)
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Rapport 30 min", 30), ("Rapport 30 minuten", 30), ("Rapport 30min", 30), ("Rapport 15 minuten", 15),
      ("Rapport 90 min", 90), ("Rapport 90 minuten", 90), ("Rapport 2 uur", 120), ("Rapport 3 uur", 180),
      ("Rapport 1,5 uur", 90), ("Rapport 1.5 uur", 90), ("Rapport 1,5u", 90), ("Rapport 2h", 120),
      ("Rapport 1 uur 30 min", 90), ("Rapport 1 uur en 30 minuten", 90), ("Rapport een half uur", 30),
      ("Rapport een halfuurtje", 30), ("Rapport halfuur", 30), ("Rapport anderhalf uur", 90),
      ("Rapport tweeënhalf uur", 150), ("Rapport tweeenhalf uur", 150), ("Rapport twee en een half uur", 150),
      ("Rapport een kwartier", 15), ("Rapport drie kwartier", 45), ("Rapport een uurtje", 60),
      ("Rapport een uur", 60), ("Rapport twee uur", 120), ("Rapport vijftien minuten", 15),
      ("Rapport dertig minuten", 30), ("Rapport ongeveer 2 uur", 120), ("Rapport gedurende 2 uur", 120),
      ("Rapport voor 30 min", 30), ("Rapport 45 minuten lang", 45), ("Rapport duur: 2 uur", 120),
      ("Rapport duur 30 min", 30), ("Rapport zo'n half uur", 30), ("Rapport zo’n 20 min", 20),
      ("Rapport ca. 30 min", 30), ("LEZEN 30 MIN", 30),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == (line.text.hasPrefix("LEZEN") ? "LEZEN" : "Rapport"), "\(line.text): title")
    }
  }

  @Test("An amount after over, voor, or elke, a duration that counts something else, or a size is no length")
  func notLengths() {
    expectLinesUnread(
      [
        "Rapport voor 2 uur", "Rapport over 30 min", "Rapport 30 min later", "Rapport 2 uur geleden",
        "Rapport elke 2 uur", "Rapport 1500 min", "Rapport 25 uur", "Rapport 0 min", "Rapport 10 min voor de vergadering",
        "Rapport 2 uur per dag", "Rapport 20 min extra",
      ], languages: ["nl"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func cadences() {
    let daily = TaskRecurrenceRule(freq: .daily)
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Afval elke dag", daily), ("Afval iedere dag", daily), ("Afval dagelijks", daily), ("Afval elke ochtend", daily),
      ("Afval elke avond", daily), ("Afval elke nacht", daily), ("Afval elke morgen", daily),
      ("Afval 1 keer per dag", daily),
      ("Afval elke week", weekly), ("Afval iedere week", weekly), ("Afval wekelijks", weekly),
      ("Afval een keer per week", weekly), ("Afval een keer in de week", weekly), ("Afval 1x per week", weekly),
      ("Afval elke 7 dagen", weekly),
      ("Afval elke maand", monthly), ("Afval maandelijks", monthly), ("Afval 1 keer per maand", monthly),
      ("Afval elk jaar", yearly), ("Afval ieder jaar", yearly), ("Afval jaarlijks", yearly),
      ("Afval eenmaal per jaar", yearly),
      ("Afval elke twee dagen", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Afval elke 3 dagen", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Afval om de 3 dagen", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Afval elke derde dag", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Afval om de dag", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Afval om de andere dag", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Afval elke andere dag", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Afval om de week", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval om de 2 weken", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval om de twee weken", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval elke tweede week", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval elke andere week", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval elke 14 dagen", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval tweewekelijks", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Afval iedere 3 weken", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("Afval om de maand", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Afval elke 2 maanden", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Afval om de 2 maanden", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Afval om de twee maanden", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Afval elk kwartaal", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Afval driemaandelijks", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Afval elk half jaar", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("Afval halfjaarlijks", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("Afval elke twee jaar", TaskRecurrenceRule(freq: .yearly, interval: 2)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "Afval", "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // A repeat in front of the line.
    for (text, title) in [("Dagelijks: lezen", "lezen"), ("Wekelijks, overleg", "overleg")] {
      let parsed = parse(text)
      #expect(parsed.recurrence != nil, "\(text)")
      #expect(parsed.title == title, "\(text): title")
    }
    #expect(parse("Dagelijks: lezen").recurrence == daily)
    #expect(parse("Wekelijks, overleg").recurrence == weekly)
    // A date beside a yearly repeat.
    let birthday = parse("Verjaardag Anna 15 oktober elk jaar")
    #expect(birthday.recurrence == yearly)
    #expect(birthday.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(birthday.title == "Verjaardag Anna")
    let date = parse("Verjaardag Anna elk jaar op 15 oktober")
    #expect(date.recurrence == yearly)
    #expect(date.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(date.title == "Verjaardag Anna")
    #expect(parse("Verjaardag elk jaar").recurrence == yearly)
    // A repeat with a time or a length.
    let timed = parse("Zwemmen elke dag om 7:30 30 min")
    #expect(timed.recurrence == daily)
    #expect(timed.startMinutes == 7 * 60 + 30)
    #expect(timed.estimatedMinutes == 30)
    #expect(timed.title == "Zwemmen")
    let every = parse("Afval iedere dag 10 min")
    #expect(every.recurrence == daily)
    #expect(every.estimatedMinutes == 10)
    let morning = parse("Afval dagelijks om 8 uur")
    #expect(morning.recurrence == daily)
    #expect(morning.startMinutes == 8 * 60)
  }

  @Test("Weekday repeats: elke maandag, maandags, and the working days and the weekend")
  func weekdayRepeats() {
    let coming = parse("Boodschappen doen elke maandag")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Boodschappen doen")
    for text in ["Afval iedere maandag", "Afval maandags", "Afval 's maandags", "Afval ’s maandags"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == monday, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.title == "Afval", "\(text): title")
    }
    let pairs: [(text: String, days: [String])] = [
      ("Afval elke dinsdag en donderdag", ["TU", "TH"]),
      ("Afval elke maandag, woensdag en vrijdag", ["MO", "WE", "FR"]),
      ("Afval elke maandag en elke donderdag", ["MO", "TH"]),
      ("Afval elke ma en wo", ["MO", "WE"]),
      ("Afval elke ma. en wo.", ["MO", "WE"]),
      ("Afval maandags en donderdags", ["MO", "TH"]),
      ("Afval dinsdags en donderdags", ["TU", "TH"]),
      ("Afval elke zaterdag en zondag", ["SU", "SA"]),
      ("Afval zaterdags", ["SA"]),
      ("Afval zondags", ["SU"]),
      ("Afval elke vrijdagavond", ["FR"]),
      ("Afval elke maandagochtend", ["MO"]),
      ("Afval elke dinsdag avond", ["TU"]),
      ("Sporten wekelijks op maandag", ["MO"]),
      ("Sporten wekelijks op maandag en donderdag", ["MO", "TH"]),
      ("Sporten wekelijks maandags", ["MO"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
    }
    // An interval takes the weekdays after it.
    let intervals: [(text: String, interval: Int?, days: [String])] = [
      ("Afval elke 2 weken op maandag", 2, ["MO"]), ("Afval om de week op dinsdag", 2, ["TU"]),
      ("Afval om de week maandags", 2, ["MO"]), ("Sporten tweewekelijks op dinsdag", 2, ["TU"]),
      ("Wassen om de week op zaterdag", 2, ["SA"]),
    ]
    for line in intervals {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, interval: line.interval, byDay: line.days), "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
    }
    // The start of a repeat on Wednesday, Friday, and Monday is the nearest day.
    #expect(parse("Afval elke maandag, woensdag en vrijdag").recurrenceStartOffset == 1)
    #expect(parse("Afval elke dinsdag en donderdag").recurrenceStartOffset == 0)
    #expect(parse("Afval elke zaterdag en zondag").recurrenceStartOffset == 4)
    for text in [
      "Afval doordeweeks", "Afval op werkdagen", "Afval elke werkdag", "Afval alle werkdagen", "Afval ma-vr",
      "Afval ma t/m vr", "Afval maandag t/m vrijdag", "Afval van maandag tot en met vrijdag",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text)")
      #expect(parsed.title == "Afval", "\(text): title")
    }
    // The weekend repeat starts on the nearer day, and "in het weekend" is one day.
    for text in ["Afval elk weekend", "Afval ieder weekend", "Afval in de weekenden", "Afval in weekenden"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == weekend, "\(text)")
      #expect(parsed.recurrenceStartOffset == 4, "\(text)")
      #expect(parsed.title == "Afval", "\(text): title")
    }
    let day = parse("Afval in het weekend")
    #expect(day.recurrence == nil)
    #expect(day.plannedDayOffset == 4)
    // A repeat with a time.
    let timed = parse("Yoga elke dinsdag en donderdag om 19:30")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(timed.startMinutes == 19 * 60 + 30)
    #expect(timed.title == "Yoga")
    let evening = parse("Yoga elke dinsdag om 7 uur 's avonds")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "Yoga")
    let everyOther = parse("Yoga om de week op dinsdag om 7 uur 's avonds")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TU"]))
    #expect(everyOther.startMinutes == 19 * 60)
    let weekendTimed = parse("Sporten elk weekend om 10 uur")
    #expect(weekendTimed.recurrence == weekend)
    #expect(weekendTimed.startMinutes == 10 * 60)
    let dayTimed = parse("Sporten in het weekend om 10 uur")
    #expect(dayTimed.recurrence == nil)
    #expect(dayTimed.plannedDayOffset == 4)
    #expect(dayTimed.startMinutes == 10 * 60)
    let tuesdayAndThursday = parse("Sporten elke di en do om 19:00")
    #expect(tuesdayAndThursday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(tuesdayAndThursday.startMinutes == 19 * 60)
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [15])
    for text in [
      "Afval elke maand op de 15e", "Afval elke maand op de 15de", "Afval elke maand op 15", "Afval elke 15e van de maand",
      "Afval maandelijks op de 15e",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 23, "\(text)")
      #expect(parsed.title == "Afval", "\(text): title")
    }
    let first = TaskRecurrenceRule(freq: .monthly, byMonthDay: [1])
    for text in [
      "Afval elke maand op de eerste", "Afval iedere 1ste van de maand", "Afval elke eerste van de maand",
      "Sporten maandelijks op de 1e", "Sporten elke 1e van de maand",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == first, "\(text)")
      #expect(parsed.recurrenceStartOffset == 9, "\(text)")
    }
    // An amount after "elke maand" is no day of the month.
    let amount = parse("Afval elke maand 15 euro")
    #expect(amount.recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(amount.title == "Afval 15 euro")
  }

  @Test("A weekday by its place in the month stays whole, and a cadence adjective or noun stays in the title")
  func unreadRepeats() {
    expectLinesUnread(
      [
        // A weekday by its place in the month has no repeat rule, so no part of it is read as a weekday.
        "Afval elke tweede maandag", "Afval elke eerste maandag van de maand", "Afval elke laatste vrijdag van de maand",
        "Afval de eerste maandag van de maand",
        // An adjective, a compound, or a count of times.
        "Wekelijks overleg", "Dagelijkse stand-up", "Dagelijks leven", "Afval twee keer per week", "Afval 3 keer per dag",
        "Tandarts 2x per week", "Sporten twee keer per maand", "Sporten viermaal per jaar",
        // Cadences the repeat has no rule for.
        "Afval om het jaar", "Sporten tweemaandelijks", "Sporten driewekelijks",
      ], languages: ["nl"])
    // A weekly adverb before a noun is an adjective, but a weekday after it is still a day.
    let adjective = parse("Wekelijks overleg op maandag")
    #expect(adjective.recurrence == nil)
    #expect(adjective.plannedDayOffset == 6)
    #expect(adjective.title == "Wekelijks overleg")
  }

  // MARK: - Priorities

  @Test("Priorities: dringend, belangrijk, urgent, hoge and lage prioriteit, and prio")
  func priorities() {
    let priorities: [(text: String, title: String, priority: LorvexTask.Priority)] = [
      ("Rapport dringend", "Rapport", .p1), ("Rapport belangrijk", "Rapport", .p1), ("Rapport urgent", "Rapport", .p1),
      ("Rapport zeer belangrijk", "Rapport", .p1), ("Rapport erg dringend", "Rapport", .p1),
      ("Dringend: rapport", "rapport", .p1), ("Belangrijk, rapport", "rapport", .p1),
      // The full stop or exclamation mark that ends the line goes with the word.
      ("Rapport belangrijk.", "Rapport", .p1), ("Rapport dringend!", "Rapport", .p1),
      ("Bericht schrijven, dringend.", "Bericht schrijven", .p1),
      ("Rapport hoge prioriteit", "Rapport", .p1), ("Rapport prioriteit hoog", "Rapport", .p1),
      ("Rapport prio hoog", "Rapport", .p1), ("Rapport prio 1", "Rapport", .p1),
      ("Rapport lage prioriteit", "Rapport", .p3), ("Rapport prioriteit laag", "Rapport", .p3),
      ("Rapport prio: laag", "Rapport", .p3), ("Rapport prio 3", "Rapport", .p3),
      ("Rapport gemiddelde prioriteit", "Rapport", .p2), ("Rapport normale prioriteit", "Rapport", .p2),
      ("Rapport prio 2", "Rapport", .p2),
      ("RAPPORT DRINGEND", "RAPPORT", .p1),
      // The shorthand every language reads.
      ("Rapport !", "Rapport", .p1), ("Rapport p1", "Rapport", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A negated word, an adjective that describes a noun, and a word alone are no priority.
    expectLinesUnread(
      [
        "Dringend rapport schrijven", "Rapport niet dringend", "Rapport niet urgent", "Rapport hoog",
        "Een belangrijke vergadering", "Een belangrijk rapport schrijven", "Dringend!", "Rapport minder belangrijk",
        "Rapport niet zo belangrijk", "Rapport !urgent",
      ], languages: ["nl"])
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyDetail() {
    let line = parse("Rapport schrijven morgen om 15 uur 2 uur lang dringend")
    #expect(line.title == "Rapport schrijven")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.priority == .p1)
    #expect(line.phrases.map(\.text) == ["morgen", "om 15 uur", "2 uur lang", "dringend"])
    let recurring = parse("Sporten elke maandag om 18 uur 1 uur hoge prioriteit")
    #expect(recurring.title == "Sporten")
    #expect(recurring.recurrence == monday)
    #expect(recurring.startMinutes == 18 * 60)
    #expect(recurring.estimatedMinutes == 60)
    #expect(recurring.priority == .p1)
    let due = parse("Belastingaangifte uiterlijk 31-7 prio 2")
    #expect(due.title == "Belastingaangifte")
    #expect(due.dueDayOffset == captureDayOffset("2027-07-31"))
    #expect(due.priority == .p2)
    let lunch = parse("Lunch met Anna morgen om 12:30 1 uur")
    #expect(lunch.title == "Lunch met Anna")
    #expect(lunch.plannedDayOffset == 1)
    #expect(lunch.startMinutes == 12 * 60 + 30)
    #expect(lunch.estimatedMinutes == 60)
    // Lists and tags beside Dutch details.
    let list = LorvexCaptureParser.parse(
      "Boodschappen #Lijst morgen", lists: [.init(id: "L1", name: "Lijst")], todayWeekday: 3, today: "2026-09-22",
      languages: ["nl"])
    #expect(list.listName == "Lijst")
    #expect(list.plannedDayOffset == 1)
    #expect(list.title == "Boodschappen")
    let tag = parse("Boodschappen vandaag #prive")
    #expect(tag.tags == ["prive"])
    #expect(tag.plannedDayOffset == 0)
    #expect(tag.title == "Boodschappen")
    let tagFirst = parse("#werk Vergadering morgen om 3 uur")
    #expect(tagFirst.tags == ["werk"])
    #expect(tagFirst.plannedDayOffset == 1)
    #expect(tagFirst.startMinutes == 15 * 60)
    #expect(tagFirst.title == "Vergadering")
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Nouns made of a day word, a time word, or a number word.
        "Avondeten koken", "Weekendtas pakken", "Morgenrood fotograferen", "Goedemorgen zeggen", "Dagelijks leven",
        "Maandag-meeting", "Vrijdagmiddagborrel organiseren",
        // A word that is a weekday abbreviation or a month in another sense.
        "Zo snel mogelijk bellen", "Do het af", "Wo ruimen", "Koffie in mei", "Zon in de zomer",
        // Numbers that are counts, places, and amounts.
        "3 koekjes kopen", "Pizza bestellen voor 4 personen", "Taart bakken 3 eieren", "Hoofdstuk 3.5 lezen",
        "Versie 2.3.4 uitbrengen", "Score 3-1 noteren", "Kamer 15.10 boeken", "15% korting", "Prijs 15,50 betalen",
        // A quantity of time that is a duration of something else.
        "Rapport 2 uur geleden", "Rapport over 30 min",
      ], languages: ["nl"])
    // A weekday that is a day, before other words.
    let report = parse("Tandarts op vrijdag was ik daar")
    #expect(report.plannedDayOffset == 3)
    #expect(report.title == "Tandarts was ik daar")
    // A weekday name written as part of a name stays, and the day after it reads.
    let name = parse("Koffie met mevrouw Maandag vandaag")
    #expect(name.plannedDayOffset == 0)
    #expect(name.title == "Koffie met mevrouw Maandag")
  }

  @Test("Accents are read as the plain letters, and the title keeps the letters it was typed with")
  func accentSpelling() {
    let spelled: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Afspraak om half één", { $0.startMinutes == 12 * 60 + 30 }),
      ("Afspraak om half een", { $0.startMinutes == 12 * 60 + 30 }),
      ("Afspraak om één uur", { $0.startMinutes == 13 * 60 }), ("Afspraak om een uur", { $0.startMinutes == 13 * 60 }),
      ("Rapport vóór vrijdag", { $0.dueDayOffset == 3 }), ("Rapport voor vrijdag", { $0.dueDayOffset == 3 }),
      ("Rapport tweeënhalf uur", { $0.estimatedMinutes == 150 }),
      ("Rapport tweeenhalf uur", { $0.estimatedMinutes == 150 }),
      ("Rapport één kwartier", { $0.estimatedMinutes == 15 }), ("Rapport een kwartier", { $0.estimatedMinutes == 15 }),
      ("Rapport één keer per week", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("Rapport een keer per week", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("Rapport één uur", { $0.estimatedMinutes == 60 }), ("Rapport één half uur", { $0.estimatedMinutes == 30 }),
      ("Afspraak over één week", { $0.plannedDayOffset == 7 }),
    ]
    for line in spelled {
      #expect(line.check(parse(line.text)), "\(line.text)")
    }
    // The letters of the title stay as they were typed, around and between the details.
    let titles: [(text: String, title: String)] = [
      ("Café morgen", "Café"), ("Zoë bellen morgen", "Zoë bellen"), ("Naïef meisje bellen vrijdag", "Naïef meisje bellen"),
      ("Reünie op 15 oktober", "Reünie"), ("Coördinatie vergadering maandag", "Coördinatie vergadering"),
      ("Café morgen om 3 uur", "Café"), ("Geëerd worden morgen", "Geëerd worden"), ("Ëxtra morgen", "Ëxtra"),
    ]
    for line in titles {
      #expect(scalars(parse(line.text).title) == scalars(line.title), "\(line.text)")
    }
    let both = parse("Café Zoë morgen om 3 uur Reünie")
    #expect(both.plannedDayOffset == 1)
    #expect(both.startMinutes == 15 * 60)
    #expect(both.title == "Café Zoë Reünie")
  }

  @Test("Capitals read like lowercase letters, and the title keeps the capitals it was typed with")
  func capitals() {
    let lines: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("TANDARTS VANAVOND", "TANDARTS", { $0.plannedDayOffset == 0 }),
      ("TANDARTS OP 15 OKTOBER", "TANDARTS", { $0.plannedDayOffset == 23 }),
      ("MEETING OM 15 UUR", "MEETING", { $0.startMinutes == 15 * 60 }),
      ("MEETING OM HALF VIER", "MEETING", { $0.startMinutes == 15 * 60 + 30 }),
      ("SPORTEN ELKE MAANDAG", "SPORTEN", { $0.recurrence == monday }),
      ("SPORTEN WEKELIJKS", "SPORTEN", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("LEZEN 30 MIN", "LEZEN", { $0.estimatedMinutes == 30 }),
      ("RAPPORT DRINGEND", "RAPPORT", { $0.priority == .p1 }),
      ("RAPPORT TOT VRIJDAG", "RAPPORT", { $0.dueDayOffset == 3 }),
      ("Tandarts MAANDAG", "Tandarts", { $0.plannedDayOffset == 6 }),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(line.check(parsed), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
  }

  @Test("Letters typed as a base letter and a combining mark keep their form, and an accent inside a detail word is left unread")
  func decomposedLetters() {
    // An accent in a title word changes nothing: both forms read the same, and each keeps its own scalars.
    let lines: [(typed: String, title: String)] = [
      ("Café morgen om 3 uur", "Café"), ("Zoë bellen morgen", "Zoë bellen"),
      ("Naïef meisje bellen vrijdag", "Naïef meisje bellen"), ("Reünie op 15 oktober", "Reünie"),
      ("Coördinatie vergadering maandag", "Coördinatie vergadering"), ("Tandarts morgen om half vier", "Tandarts"),
      ("Sporten elke maandag", "Sporten"), ("Rapport voor vrijdag", "Rapport"),
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
    for line in ["Afspraak om half één", "Rapport tweeënhalf uur", "Rapport één kwartier", "Rapport één keer per week"] {
      let composed = line.precomposedStringWithCanonicalMapping
      let decomposed = line.decomposedStringWithCanonicalMapping
      #expect(parse(composed).phrases.count == 1, "\(line)")
      let parsed = parse(decomposed)
      #expect(parsed.phrases.isEmpty, "\(line): phrases")
      #expect(scalars(parsed.title) == scalars(decomposed), "\(line): title")
    }
    // A mark on a letter that is part of no detail changes nothing either.
    let stray = "e\u{0308}xtra Bru\u{0308}cke"
    #expect(scalars(parse("\(stray) morgen").title) == scalars(stray))
    #expect(parse("\(stray) morgen").plannedDayOffset == 1)
  }

  // MARK: - Beside other languages

  @Test("Beside Dutch, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Dutch beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Meet at 15h",
    ] {
      for languages in [["en", "nl"], ["nl", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Dutch writes its hours with "uur" or "u", so "15h" and "2h" are lengths beside it, and "15u" is a time.
    let hours = parse("Write the report 2h", languages: ["en", "nl"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "nl"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    let dutchClock = parse("Run 15u", languages: ["en", "nl"])
    #expect(dutchClock.startMinutes == 15 * 60)
    #expect(dutchClock.title == "Run")
    // A line may mix both languages.
    let mixed = parse("Call mom morgen at 3pm", languages: ["en", "nl"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting op vrijdag at 3pm", languages: ["en", "nl"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Tandarts tomorrow", languages: ["en", "nl"]).plannedDayOffset == 1)
    let review = parse("Review morgen om 15:00 for 2 hours", languages: ["en", "nl"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english = parse("Rapport morgen 3pm")
    #expect(english.plannedDayOffset == 1)
    #expect(english.startMinutes == 15 * 60)
    #expect(english.title == "Rapport")
    #expect(parse("Rapport 30 min morgen").estimatedMinutes == 30)
    #expect(parse("Rapport morgen 17:30").startMinutes == 17 * 60 + 30)
  }

  @Test("Lines in other languages read the same with Dutch beside them")
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
      ("Courses ce soir à 19h", "fr"), ("Dentiste après-demain", "fr"),
      ("Llamar a mamá mañana a las 15:00", "es"), ("Gimnasio cada lunes", "es"), ("Informe antes del viernes", "es"),
      ("Reunión a las 3 de la tarde", "es"), ("Vacaciones del 3 al 5 de mayo", "es"),
      ("Chiamare mamma domani alle 15:00", "it"), ("Palestra ogni lunedì", "it"), ("Relazione entro venerdì", "it"),
      ("Ligar para a mãe amanhã às 15h", "pt"), ("Relatório até sexta", "pt"), ("Academia toda segunda", "pt"),
      ("Zadzwonić jutro o 15:00", "pl"), ("Siłownia co poniedziałek", "pl"), ("Raport do piątku", "pl"),
      ("Zahnarzt übermorgen", "de"), ("Meeting um 15 Uhr", "de"), ("Sport jeden Montag", "de"),
      ("Bericht bis Freitag", "de"), ("Urlaub vom 3. bis 5. Mai", "de"), ("Zahnarzt am Freitag", "de"),
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "nl"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["nl", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Dutch with another language.
    let frenchAndDutch = parse("Appeler maman demain om 15 uur", languages: ["fr", "nl"])
    #expect(frenchAndDutch.plannedDayOffset == 1)
    #expect(frenchAndDutch.startMinutes == 15 * 60)
    #expect(frenchAndDutch.title == "Appeler maman")
    #expect(parse("Appeler maman demain à 15h", languages: ["fr", "nl"]).startMinutes == 15 * 60)
    #expect(parse("Tandarts morgen 下午3点", languages: ["zh", "nl"]).plannedDayOffset == 1)
    #expect(parse("Tandarts morgen", languages: ["he", "nl"]).plannedDayOffset == 1)
    #expect(parse("Meeting jutro", languages: ["pl", "nl"]).plannedDayOffset == 1)
    // Dutch and German share "morgen" and agree on it, and each keeps its own words.
    for languages in [["nl", "de"], ["de", "nl"]] {
      #expect(parse("Tandarts morgen", languages: languages).plannedDayOffset == 1, "\(languages)")
      #expect(parse("Zahnarzt morgen um 15 Uhr", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Tandarts morgen om 15 uur", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Sport jeden Montag", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Sporten elke maandag", languages: languages).recurrence == monday, "\(languages)")
      // Beside German, an hour written with h is a time, and beside Dutch alone it is a length.
      #expect(parse("Meeting 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Rapport 2h", languages: languages).estimatedMinutes == 120, "\(languages)")
    }
  }

  @Test("Dutch words are read only for a user who reads Dutch")
  func languageGate() {
    let line = parse("Tandarts overmorgen", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Tandarts overmorgen")
    for languages in [["nl"], ["nl-NL"], ["nl_BE"], ["nl-BE"], ["en-US", "nl-NL"], ["NL"]] {
      #expect(parse("Tandarts overmorgen", languages: languages).plannedDayOffset == 2, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Dutch reader.
    for text in ["Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã", "Zahnarzt übermorgen"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == nil, "\(text)")
      #expect(parsed.title == text, "\(text): title")
    }
    // Dutch words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"]] {
      let parsed = parse("Tandarts overmorgen", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Tandarts overmorgen", "\(languages): title")
      #expect(parse("Meeting om 15 uur", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("Sporten elke maandag", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("om 15 uur ", 450), ("om 3 ", 1600), ("half ", 1000), ("kwart over ", 450), ("tien voor half ", 330),
      ("15:30 ", 833), ("15.30 ", 833), ("0 uur ", 833), ("24 uur ", 714), ("12:30 pm ", 555), ("vanavond ", 555),
      ("morgen vroeg ", 384), ("elke maandag ", 384), ("elke tweede dag ", 312), ("om de 2 weken ", 357),
      ("op 15 oktober ", 357), ("van 3 tot 5 mei ", 312), ("van maandag tot woensdag ", 200), ("van ma tot wo ", 357),
      ("voor vrijdag ", 416), ("volgende week ", 357), ("30 minuten ", 454), ("2u ", 1666), ("een half uur ", 384),
      ("5-6 uur ", 625), ("hoge prioriteit ", 312), ("14-16 uur ", 500), ("van 14 tot 16 uur ", 277),
      ("tussen 14 en 16 uur ", 250), ("Sprint 12 - 20 mei ", 263), ("zo ", 1666), ("ma ", 1666), ("3.-", 1666),
      ("ë", 5000), ("é", 5000), ("e\u{0308}", 2500), ("elke ", 1000), ("om de ", 833), ("tussen ", 714), ("tot ", 1250),
      ("van ", 1250), ("uur ", 1250), ("15 ", 1666), ("mei ", 1250), ("maandag ", 625), ("week ", 1000),
      ("dringend ", 555), ("prio ", 1000), ("'s ", 1666), ("’s ", 1666), ("om 3 uur 's ", 450), ("'s avonds om ", 384),
      ("wekelijks op ", 416), (", ", 2500), (".", 5000),
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for entry in unit {
        let line = "Anna " + String(repeating: entry.token, count: entry.repeats) + " Telefoon"
        let parsed = parse(line)
        #expect(!parsed.title.isEmpty, "\(entry.token)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}
