import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["de"]) -> LorvexCaptureParse {
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

/// German capture lines, read for a user whose languages include German.
@Suite("Capture parser German")
struct CaptureParserGermanTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, a number of days, next week, and the weekend")
  func days() {
    let line = parse("Zahnarzt morgen")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Zahnarzt")
    #expect(line.phrases.map(\.text) == ["morgen"])

    let days: [(text: String, title: String, offset: Int)] = [
      ("Zahnarzt heute", "Zahnarzt", 0),
      ("Zahnarzt heute Abend", "Zahnarzt", 0),
      ("Zahnarzt heute Nacht", "Zahnarzt", 0),
      ("Zahnarzt heute früh", "Zahnarzt", 0),
      ("Zahnarzt heute Morgen", "Zahnarzt", 0),
      ("Zahnarzt morgen früh", "Zahnarzt", 1),
      ("Zahnarzt morgen Abend", "Zahnarzt", 1),
      ("Zahnarzt übermorgen", "Zahnarzt", 2),
      ("Bericht für übermorgen", "Bericht", 2),
      ("Zahnarzt in 3 Tagen", "Zahnarzt", 3),
      ("Zahnarzt in einer Woche", "Zahnarzt", 7),
      ("Zahnarzt in zwei Wochen", "Zahnarzt", 14),
      ("Zahnarzt nächste Woche", "Zahnarzt", 7),
      ("Zahnarzt kommende Woche", "Zahnarzt", 7),
      ("Zahnarzt übernächste Woche", "Zahnarzt", 14),
      ("Zahnarzt nächste Woche Montag", "Zahnarzt", 6),
      ("Zahnarzt Montag nächste Woche", "Zahnarzt", 6),
      ("Zahnarzt nächste Woche Mittwoch", "Zahnarzt", 8),
      ("Zahnarzt Freitag nächste Woche", "Zahnarzt", 10),
      ("Zahnarzt am Wochenende", "Zahnarzt", 4),
      ("Zahnarzt dieses Wochenende", "Zahnarzt", 4),
      ("Zahnarzt nächstes Wochenende", "Zahnarzt", 11),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == day.title, "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Morgen Zahnarzt")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "Zahnarzt")
    let capitals = parse("ÜBERMORGEN ZAHNARZT")
    #expect(capitals.plannedDayOffset == 2)
    #expect(capitals.title == "ZAHNARZT")
    // The weekend is a day only with a word that points at it.
    expectLinesUnread(["Zahnarzt Wochenende", "Wochenende planen", "Wochenendeinkauf"], languages: ["de"])
  }

  @Test("Morgen is tomorrow, and the morning only as a capitalized noun")
  func morgen() {
    #expect(parse("Zahnarzt morgen").plannedDayOffset == 1)
    #expect(parse("ZAHNARZT MORGEN").plannedDayOffset == 1)
    #expect(parse("ZAHNARZT MORGEN").title == "ZAHNARZT")
    // The capitalized noun in the middle or at the end of a line is the
    // morning, so it is no day.
    expectLinesUnread(
      [
        "Zahnarzt Morgen", "Guten Morgen sagen", "Am Morgen joggen", "Morgen-Routine planen", "Morgenroutine planen",
        "Morgenstern kaufen", "Bericht bis Morgen",
      ], languages: ["de"])
    // A part of the day after it makes it tomorrow, and so does opening the line.
    let early = parse("Zahnarzt Morgen früh")
    #expect(early.plannedDayOffset == 1)
    #expect(early.title == "Zahnarzt")
    let opening = parse("Morgen Zahnarzt")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "Zahnarzt")
    // Every morning is a daily repeat, which is no day.
    let daily = parse("Jeden Morgen joggen")
    #expect(daily.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(daily.plannedDayOffset == nil)
    #expect(daily.title == "joggen")
    // A due day takes the adverb in lower case only.
    #expect(parse("Bericht bis morgen").dueDayOffset == 1)
  }

  @Test("An evening makes a clock time the evening's")
  func evenings() {
    let dinner = parse("Meeting heute Abend um 8")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "Meeting")
    // Twelve in the evening is midnight, which ends the day.
    let midnight = parse("Meeting heute Abend um 12")
    #expect(midnight.plannedDayOffset == 1)
    #expect(midnight.startMinutes == 0)
    let evening = parse("Zahnarzt morgen Abend")
    #expect(evening.plannedDayOffset == 1)
    #expect(evening.startMinutes == nil)
    let early = parse("Meeting morgen früh um 6")
    #expect(early.plannedDayOffset == 1)
    #expect(early.startMinutes == 6 * 60)
    #expect(early.title == "Meeting")
    let weekday = parse("Dienstag Abend Sport")
    #expect(weekday.plannedDayOffset == 7)
    #expect(weekday.title == "Sport")
    // The evening meals give a bare hour the evening, as "heute Abend" does.
    for (line, minutes, title) in [
      ("Abendessen um 8", 20 * 60, "Abendessen"), ("Abendbrot um 6", 18 * 60, "Abendbrot"),
      ("Abendessen um 7 mit Anna", 19 * 60, "Abendessen mit Anna"), ("Abendessen um 19 Uhr", 19 * 60, "Abendessen"),
      ("Frühstück um 9", 9 * 60, "Frühstück"), ("Mittagessen um 1", 13 * 60, "Mittagessen"),
    ] {
      let meal = parse(line)
      #expect(meal.startMinutes == minutes, "\(line)")
      #expect(meal.title == title, "\(line)")
    }
    // The part of the day as a noun, or alone, names no day.
    expectLinesUnread(
      [
        "Lesen abends", "Abendessen vorbereiten", "Mittagessen mit Anna", "Frühstück machen", "Nachtisch kaufen",
        "Die Zeit läuft", "Über Nacht backen",
      ], languages: ["de"])
  }

  @Test("Past days are not read")
  func pastDays() {
    expectLinesUnread(
      [
        "Zahnarzt gestern", "Zahnarzt vorgestern", "Zahnarzt gestern Morgen", "Zahnarzt gestern Abend",
        "Zahnarzt vorgestern Abend", "Zahnarzt letzte Woche", "Zahnarzt vorige Woche", "Zahnarzt letzten Montag",
        "Zahnarzt letzten Freitag", "Zahnarzt vergangenen Montag",
      ], languages: ["de"])
    // The time that follows a past day still reads.
    let time = parse("Zahnarzt gestern um 3")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Zahnarzt gestern")
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Zahnarzt Freitag", 3), ("Zahnarzt am Freitag", 3), ("Zahnarzt Sonnabend", 4),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "diesen Dienstag" is today.
      ("Zahnarzt Dienstag", 7), ("Zahnarzt am Dienstag", 7), ("Zahnarzt diesen Dienstag", 0),
      ("Zahnarzt diesen Freitag", 3), ("Zahnarzt kommenden Freitag", 3), ("Zahnarzt nächsten Freitag", 10),
      ("Zahnarzt nächsten Montag", 6), ("Zahnarzt übernächsten Montag", 13), ("Zahnarzt MONTAG", 6),
      // A weekday abbreviation counts after a word that points at it.
      ("Zahnarzt am Mo", 6), ("Zahnarzt am Fr.", 3), ("Zahnarzt am Do", 2),
      // A part of the day written onto the weekday.
      ("Zahnarzt Samstagabend", 4), ("Zahnarzt Freitagnachmittag", 3), ("Zahnarzt Montagmorgen", 6),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Zahnarzt", "\(weekday.text): title")
    }
    let morning = parse("Meeting am Freitag um 15 Uhr")
    #expect(morning.plannedDayOffset == 3)
    #expect(morning.startMinutes == 15 * 60)
    #expect(morning.title == "Meeting")
  }

  @Test("A weekday that is a name, an abbreviation alone, or part of a compound stays in the title")
  func weekdayNames() {
    expectLinesUnread(
      [
        "Zahnarzt Mo", "Frau Freitag anrufen", "Herr Freitag anrufen", "Familie Montag besuchen", "Termin mit Dr. Mi",
        "Fr. Müller anrufen", "Montag-Meeting vorbereiten", "Mittwochs-Meeting vorbereiten", "Montagmorgen-Meeting",
        "Sonntagsbraten kaufen", "Mo Mi Fr Training", "So geht's nicht", "Do not disturb", "Dienstleistung buchen",
        "Sonne tanken",
      ], languages: ["de"])
    // "Fr." before a name abbreviates Frau, and a weekday after "am" is a day.
    let abbreviated = parse("Fr. Müller am Mo anrufen")
    #expect(abbreviated.plannedDayOffset == 6)
    #expect(abbreviated.title == "Fr. Müller anrufen")
    // A day after "außer" is left out of the days the line names.
    let except = parse("Gießen jeden Tag außer Sonntag")
    #expect(except.plannedDayOffset == nil)
    #expect(except.title == "Gießen außer Sonntag")
    #expect(parse("Gießen außer Freitag").title == "Gießen außer Freitag")
    #expect(parse("Gießen außer morgen").plannedDayOffset == nil)
  }

  @Test("A weekday abbreviation before um or gegen is the day, and so um or so gegen is an approximate time")
  func abbreviationBeforeTimeLead() {
    for (line, day, minutes, title) in [
      ("Brunch am So um 11 Uhr", 5, 11 * 60, "Brunch"), ("Brunch am So um 11", 5, 11 * 60, "Brunch"),
      ("Brunch bei Oma am So gegen 11", 5, 11 * 60, "Brunch bei Oma"), ("Anna am So um 10 anrufen", 5, 10 * 60, "Anna anrufen"),
      ("Anna am Sa um 10 anrufen", 4, 10 * 60, "Anna anrufen"), ("Anna am Mo gegen 10 anrufen", 6, 10 * 60, "Anna anrufen"),
      ("Brunch bei Oma am So um 11h", 5, 11 * 60, "Brunch bei Oma"), ("Brunch von So um 11", 5, 11 * 60, "Brunch"),
    ] {
      let reading = parse(line)
      #expect(reading.plannedDayOffset == day, "\(line)")
      #expect(reading.startMinutes == minutes, "\(line)")
      #expect(reading.title == title, "\(line)")
    }
    // Where no word points at a day, "so um" and "so gegen" are the colloquial approximation.
    for (line, minutes, title) in [
      ("Anna so um 10 anrufen", 10 * 60, "Anna anrufen"), ("Treffen so gegen 3", 15 * 60, "Treffen"),
      ("Anna so um 10", 10 * 60, "Anna"),
    ] {
      let reading = parse(line)
      #expect(reading.plannedDayOffset == nil, "\(line)")
      #expect(reading.startMinutes == minutes, "\(line)")
      #expect(reading.title == title, "\(line)")
    }
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Zahnarzt am 15. Oktober", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15. Oktober", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15 Oktober", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 1. Mai", "Zahnarzt", "2027-05-01"),
      ("Zahnarzt 15. Okt.", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15. Okt", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15 Okt.", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15. Oktober 2026", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15. Oktober 2027", "Zahnarzt", "2027-10-15"),
      ("Zahnarzt am 15.10.", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt am 15.10.2026", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15.10.", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15.10.26", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt am 15.10", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt am 15/10", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15/10/2026", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 15-10-2026", "Zahnarzt", "2026-10-15"),
      ("Zahnarzt 3. Jänner", "Zahnarzt", "2027-01-03"),
      ("Zahnarzt 3. März", "Zahnarzt", "2027-03-03"),
      ("Zahnarzt 3. Mär", "Zahnarzt", "2027-03-03"),
      ("Zahnarzt 3. Maerz", "Zahnarzt", "2027-03-03"),
      ("Zahnarzt 3. Marz", "Zahnarzt", "2027-03-03"),
      ("ZAHNARZT AM 15. OKTOBER", "ZAHNARZT", "2026-10-15"),
      // A weekday before the date is part of it, as a name or as an abbreviation with its dot or comma.
      ("Zahnarzt Freitag, den 16. Oktober", "Zahnarzt", "2026-10-16"),
      ("Zahnarzt am Freitag, den 16. Oktober", "Zahnarzt", "2026-10-16"),
      ("Zahnarzt Freitag, 16.10.", "Zahnarzt", "2026-10-16"),
      ("Zahnarzt Fr. 16.10.", "Zahnarzt", "2026-10-16"),
      ("Zahnarzt am Fr. 16.10.", "Zahnarzt", "2026-10-16"),
      ("Zahnarzt Fr, 16.10.", "Zahnarzt", "2026-10-16"),
      ("Zahnarzt Fr., 16. Oktober", "Zahnarzt", "2026-10-16"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A date opening the line, and a date beside other details.
    let opening = parse("15. Oktober Zahnarzt")
    #expect(opening.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(opening.title == "Zahnarzt")
    let timed = parse("Zahnarzt am 15. Oktober um 9 Uhr")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Zahnarzt")
  }

  @Test("Numbers that are no date, a past year, and a day the month does not have stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers without a word that makes them a date, a bare month, and an abbreviation without its dot.
        "Zahnarzt 15 Okt", "Zahnarzt 15.10", "Zahnarzt am 15.", "Zahnarzt Mai", "Oktober Abrechnung",
        "Oktober 2026 Abrechnung", "Mai-Feier planen", "Tag der Arbeit", "Jahr 2026 planen",
        // A day the month does not have, and a year that is past.
        "Zahnarzt am 31. April", "Zahnarzt 29. Februar", "Zahnarzt 15. Oktober 2025",
        // Chapters, versions, floors, matchdays, invoice and room numbers.
        "Kapitel 1.5. lesen", "Version 1.5.2 testen", "Wohnung 3. Stock besichtigen", "Am 3. Spieltag",
        "Rechnung Nr. 15.10 prüfen", "Sitzung Raum 3.10", "Buch Seite 15 lesen",
        // Words that sound like a date.
        "Geburtstag von Oma", "Tagebuch schreiben", "Wochenplan erstellen", "Jahresbericht schreiben",
      ], languages: ["de"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Urlaub", "vom 3. bis 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "vom 3. bis zum 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "vom 3. bis einschließlich 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "von 3 bis 5 Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "vom 30. Mai bis 2. Juni", "2027-05-30", "2027-06-02"),
        ("Urlaub", "vom 30. Mai bis zum 2. Juni", "2027-05-30", "2027-06-02"),
        ("Urlaub", "vom 3. Mai bis 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "zwischen dem 3. und 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "zwischen 3 und 5 Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "zwischen 3. und 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "3.-5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "3. bis 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "3. bis zum 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "vom 3.5. bis 5.5.", "2027-05-03", "2027-05-05"),
        ("Urlaub", "3.5.-5.5.", "2027-05-03", "2027-05-05"),
        ("Urlaub", "vom 3. bis 5. Mai 2027", "2027-05-03", "2027-05-05"),
        ("Urlaub in Wien", "vom 3. bis 5. Mai", "2027-05-03", "2027-05-05"),
        ("Urlaub", "vom 25. September bis 3. Oktober", "2026-09-25", "2026-10-03"),
        ("Urlaub", "vom 30. Dezember bis 2. Januar", "2026-12-30", "2027-01-02"),
        ("Vortrag", "12.-14. Oktober", "2026-10-12", "2026-10-14"),
        ("Vortrag", "12. - 14. Oktober", "2026-10-12", "2026-10-14"),
        ("Vortrag", "vom 12. - 14. Oktober", "2026-10-12", "2026-10-14"),
        ("Konferenz", "12.–14. Oktober", "2026-10-12", "2026-10-14"),
      ], languages: ["de"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Urlaub vom 5. bis 3. Mai", "Urlaub 5.-3. Mai", "Urlaub vom 3. Mai bis 3. Mai", "Urlaub 3 bis 5",
        "Seiten 3-5 lesen", "Preis 3-5 Euro",
      ], languages: ["de"])
    // Two bare numbers after "von" and "bis" are hours.
    let bare = parse("Urlaub von 3 bis 5")
    #expect(bare.plannedDayOffset == nil)
    #expect(bare.dueDayOffset == nil)
    #expect(bare.startMinutes == 15 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A day alone opens a range joined by a spaced dash only with its ordinal dot")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 Mai")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    let talk = parse("Vortrag 12 - 14 Oktober")
    #expect(talk.title == "Vortrag 12")
    #expect(talk.plannedDayOffset == captureDayOffset("2026-10-14"))
    #expect(talk.dueDayOffset == nil)
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time still reads")
  func rangeTakesBothDays() {
    let line = parse("Urlaub vom 3. bis 5. Mai morgen")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Urlaub morgen")
    let timed = parse("Urlaub vom 3. bis 5. Mai um 9 Uhr")
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Urlaub")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("Urlaub von Montag bis Mittwoch")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "Urlaub")
    #expect(span.phrases.map(\.text) == ["von Montag bis Mittwoch"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("Urlaub Montag bis Mittwoch", 6, 8), ("Urlaub Freitag bis Sonntag", 3, 5),
      ("Urlaub von Freitag bis Sonntag", 3, 5), ("Urlaub Sonnabend bis Montag", 4, 6),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("Urlaub von Dienstag bis Donnerstag", 7, 9),
      // The abbreviations and the dash count after "von" or "vom".
      ("Urlaub von Mo bis Mi", 6, 8), ("Urlaub von Mi bis Fr", 1, 3), ("Urlaub vom Mi bis Fr", 1, 3),
      ("Urlaub von Do bis Sa", 2, 4), ("Urlaub von Fr bis Mo", 3, 6), ("Urlaub von Do. bis Sa.", 2, 4),
      ("Urlaub von Mo-Mi", 6, 8), ("Urlaub von Mo - Mi", 6, 8),
    ]
    for line in spans {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day")
      #expect(parsed.dueDayOffset == line.due, "\(line.text): due day")
      #expect(parsed.title == "Urlaub", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Monday to Friday is the working week, which repeats.
    for text in ["Sport Montag bis Freitag", "Sport von Montag bis Freitag", "Sport von Mo bis Fr", "Sport Mo bis Fr"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Sport", "\(text): title")
    }
    // An abbreviation after no "von" is no span, and the span's time reads.
    expectLinesUnread(["Urlaub Mi bis Fr", "Mo bis Mi"], languages: ["de"])
    let timed = parse("Meeting von Mo bis Mi um 10 Uhr")
    #expect(timed.plannedDayOffset == 6)
    #expect(timed.dueDayOffset == 8)
    #expect(timed.startMinutes == 10 * 60)
    #expect(timed.title == "Meeting")
    // A weekday after a title is a name, so only the due day reads.
    let name = parse("Frau Montag bis Mittwoch")
    #expect(name.plannedDayOffset == nil)
    #expect(name.dueDayOffset == 1)
    #expect(name.title == "Frau Montag")
  }

  // MARK: - Due days

  @Test("Due days: bis, spätestens, fällig, Frist, Deadline, and Stichtag")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Bericht bis Freitag", "Bericht", 3),
      ("Bericht bis zum Freitag", "Bericht", 3),
      ("Bericht bis zum 15. Oktober", "Bericht", 23),
      ("Bericht bis spätestens morgen", "Bericht", 1),
      ("Bericht bis spaetestens Freitag", "Bericht", 3),
      ("Bericht spätestens am Freitag", "Bericht", 3),
      ("Bericht fällig bis 15.10.", "Bericht", 23),
      ("Bericht zum 1.5.", "Bericht", 221),
      ("Bericht zum 1. Mai", "Bericht", 221),
      ("Bericht bis zum 1. Mai", "Bericht", 221),
      ("Bericht Frist: Freitag", "Bericht", 3),
      ("Bericht Frist 15. Oktober", "Bericht", 23),
      ("Bericht Deadline Freitag", "Bericht", 3),
      ("Bericht Deadline: morgen", "Bericht", 1),
      ("Bericht Freitag spätestens", "Bericht", 3),
      ("Bericht fällig am Freitag", "Bericht", 3),
      ("Bericht fällig Freitag", "Bericht", 3),
      ("Bericht Abgabefrist Freitag", "Bericht", 3),
      ("Bericht Abgabefrist: 15. Oktober", "Bericht", 23),
      ("Bericht Stichtag 15.10.", "Bericht", 23),
      ("Bericht bis morgen Abend", "Bericht", 1),
      ("Bericht bis morgen früh", "Bericht", 1),
      ("Bericht bis heute", "Bericht", 0),
      ("Bericht bis übermorgen", "Bericht", 2),
      ("Bericht bis 15.10", "Bericht", 23),
      ("Bericht bis nächste Woche", "Bericht", 7),
      ("Bericht bis nächsten Montag", "Bericht", 6),
      ("Bericht bis kommenden Fr", "Bericht", 3),
      // A weekday beside "nächste Woche" is that week's, and a weekday before its date is part of the date.
      ("Bericht bis Montag nächste Woche", "Bericht", 6),
      ("Bericht bis Freitag nächste Woche", "Bericht", 10),
      ("Bericht bis nächste Woche Freitag", "Bericht", 10),
      ("Bericht bis nächste Woche am Freitag", "Bericht", 10),
      ("Bericht Freitag nächste Woche spätestens", "Bericht", 10),
      ("Bericht bis Freitag, 16.10.", "Bericht", 24),
      ("Bericht bis Fr. 16.10.", "Bericht", 24),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Bericht bis Freitag heute")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Bericht")
    // A deadline word that names no day, an abbreviation alone, or the weekend.
    expectLinesUnread(
      [
        "Bis bald", "Bis später", "Bis nächste Woche", "Zum Mittagessen", "Zum 1. Mai", "Zum 15.", "Abgabefrist",
        "Frist verlängern", "Frist: 3 Tage", "Deadline einhalten", "Bericht bis Fr", "Bericht bis Wochenende",
        "Bericht bis zum Wochenende", "Frist außer Kraft",
      ], languages: ["de"])
    let opening = parse("Bis Montag warten")
    #expect(opening.dueDayOffset == 6)
    #expect(opening.title == "warten")
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Meeting bis 17 Uhr", "Meeting bis 17:00", "Meeting bis 17.30", "Meeting bis spätestens 17 Uhr",
        "Meeting spätestens um 17:00", "Meeting frühestens 9 Uhr", "Meeting vor 8 Uhr", "Meeting nach 18 Uhr",
        "Meeting nicht später als 17 Uhr", "Meeting bis halb fünf",
      ], languages: ["de"])
    // The day before the clock is the due day, and the clock stays in the title.
    let friday = parse("Bericht bis Freitag um 17 Uhr")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "Bericht um 17 Uhr")
    let colon = parse("Bericht bis Freitag 17:00")
    #expect(colon.dueDayOffset == 3)
    #expect(colon.startMinutes == nil)
    #expect(colon.title == "Bericht 17:00")
    let tomorrow = parse("Bericht bis morgen 9 Uhr")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "Bericht 9 Uhr")
    // A time range that ends in a clock time is still a range.
    let range = parse("Meeting von 14 bis 17 Uhr")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 180)
    #expect(range.title == "Meeting")
    // Without German, English reads the clock time and leaves the word.
    let english = parse("Meeting bis 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
    #expect(english.title == "Meeting bis")
  }

  // MARK: - Clock times

  @Test("Clock times: um, Uhr, a part of the day, noon, and midnight")
  func times() {
    let times: [(text: String, minutes: Int)] = [
      ("Meeting um 15 Uhr", 15 * 60), ("Meeting um 15:30", 15 * 60 + 30), ("Meeting um 15.30 Uhr", 15 * 60 + 30),
      ("Meeting um 15 Uhr 30", 15 * 60 + 30), ("Meeting um 14.30", 14 * 60 + 30), ("Meeting um 3", 15 * 60),
      ("Meeting um 9 Uhr", 9 * 60), ("Meeting um 09:00 Uhr", 9 * 60), ("Meeting um 9.00 Uhr", 9 * 60),
      ("Meeting um 9:00", 9 * 60), ("Meeting um 9.30 Uhr", 9 * 60 + 30), ("Meeting gegen 15 Uhr", 15 * 60),
      ("Meeting ab 15:30", 15 * 60 + 30), ("Meeting ab 15.30 Uhr", 15 * 60 + 30), ("Meeting 15 Uhr", 15 * 60),
      ("Meeting 15:30 Uhr", 15 * 60 + 30), ("Meeting 15.30 Uhr", 15 * 60 + 30), ("Meeting 15 Uhr 30", 15 * 60 + 30),
      ("Meeting 15:30", 15 * 60 + 30), ("Meeting 17:30", 17 * 60 + 30), ("Meeting 0 Uhr", 0),
      ("Meeting um 8 Uhr morgens", 8 * 60), ("Meeting um 8 Uhr früh", 8 * 60), ("Meeting 8 Uhr früh", 8 * 60),
      ("Meeting 8 Uhr in der Früh", 8 * 60), ("Meeting um 10 Uhr vormittags", 10 * 60),
      ("Meeting um 12 Uhr mittags", 12 * 60), ("Meeting um 12:00 Uhr mittags", 12 * 60),
      ("Meeting um 1 Uhr nachmittags", 13 * 60), ("Meeting um 3 Uhr nachmittags", 15 * 60),
      ("Meeting um 8 abends", 20 * 60), ("Meeting 8 abends", 20 * 60), ("Meeting um 8 am Abend", 20 * 60),
      ("Meeting 7:30 abends", 19 * 60 + 30), ("Meeting um 6 Uhr abends", 18 * 60),
      ("Meeting um 11 Uhr abends", 23 * 60), ("Meeting um 11 Uhr nachts", 23 * 60),
      ("Meeting um 18 Uhr abends", 18 * 60), ("Meeting um 12", 12 * 60),
      // A part of the day before the clock time.
      ("Meeting morgens um 6", 6 * 60), ("Meeting morgens 7 Uhr", 7 * 60), ("Meeting morgens 7:30", 7 * 60 + 30),
      ("Meeting abends 7 Uhr", 19 * 60), ("Meeting abends 7:30", 19 * 60 + 30),
      ("Meeting abends 7:30 Uhr", 19 * 60 + 30), ("Meeting abends 19:30", 19 * 60 + 30),
      ("Meeting mittags 12:30", 12 * 60 + 30), ("Meeting nachmittags 3:30", 15 * 60 + 30),
      // Noon, and English forms the line may mix in.
      ("Meeting um Mittag", 12 * 60), ("Meeting um 3pm", 15 * 60), ("Meeting um 3 pm", 15 * 60),
      ("Meeting um 3:30pm", 15 * 60 + 30), ("Meeting 3pm", 15 * 60), ("Meeting 5pm", 17 * 60),
      ("Meeting at 3pm", 15 * 60),
      // Uppercase letters read like lowercase ones.
      ("MEETING UM 15 UHR", 15 * 60), ("Meeting UM 15 UHR", 15 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == (line.text.hasPrefix("MEETING") ? "MEETING" : "Meeting"), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Noon and midnight are times only after a word that points at them.
    expectLinesUnread(["Meeting Mittag", "Meeting Mitternacht", "Meeting zu Mittag"], languages: ["de"])
  }

  @Test("After midnight: nachts, 24 Uhr, and Mitternacht run past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("Meeting um 3 Uhr nachts")
    #expect(night.startMinutes == 3 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "Meeting")
    let after: [(text: String, minutes: Int)] = [
      ("Meeting um 24 Uhr", 0), ("Meeting 24 Uhr", 0), ("Meeting um 12 Uhr nachts", 0),
      ("Meeting um Mitternacht", 0), ("Meeting gegen Mitternacht", 0), ("Meeting um halb eins nachts", 30),
      ("Meeting nachts 3:30", 3 * 60 + 30), ("Meeting heute Nacht um 2", 2 * 60),
    ]
    for line in after {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.plannedDayOffset == 1, "\(line.text): planned day")
      #expect(parsed.title == "Meeting", "\(line.text): title")
    }
    // An hour before midnight stays on its day, and 0 Uhr is a time on its day.
    let late = parse("Meeting heute Nacht um 11")
    #expect(late.startMinutes == 23 * 60)
    #expect(late.plannedDayOffset == 0)
    #expect(parse("Meeting 0 Uhr").plannedDayOffset == nil)
    // A named day keeps the time on its own night.
    let named = parse("Meeting am Freitag um 2 Uhr nachts")
    #expect(named.startMinutes == 2 * 60)
    #expect(named.plannedDayOffset == 4)
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("Meeting um 3").startMinutes == 15 * 60)
    #expect(parse("Meeting um 6").startMinutes == 18 * 60)
    #expect(parse("Meeting um 7").startMinutes == 7 * 60)
    #expect(parse("Meeting um 9").startMinutes == 9 * 60)
    #expect(parse("Meeting um 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Meeting um 03:00").startMinutes == 3 * 60)
    #expect(parse("Meeting um 3:00").startMinutes == 15 * 60)
    #expect(parse("Meeting um 3 Uhr").startMinutes == 15 * 60)
    #expect(parse("Meeting 1 Uhr").startMinutes == 13 * 60)
    #expect(parse("Meeting 6 Uhr").startMinutes == 18 * 60)
    #expect(parse("Meeting 7 Uhr").startMinutes == 7 * 60)
    #expect(parse("Meeting 7 Uhr morgens").startMinutes == 7 * 60)
    #expect(parse("Meeting halb sieben").startMinutes == 18 * 60 + 30)
    // A part of the day settles the hour either way.
    #expect(parse("Meeting um 3 Uhr morgens").startMinutes == 3 * 60)
    // An hour or minutes that no clock has, or a part of the day that contradicts the hour, is no time.
    expectLinesUnread(
      [
        "Meeting um 25 Uhr", "Meeting um 25:00", "Meeting um 8:75", "Meeting um 8 Uhr 75", "Meeting morgens um 13 Uhr",
        "Meeting abends um 25 Uhr", "Meeting um 18 Uhr morgens", "Meeting um 12 Uhr morgens",
      ], languages: ["de"])
  }

  @Test("Spoken times: halb, viertel, dreiviertel, nach, and vor name the hour that follows")
  func spokenTimes() {
    let spoken: [(text: String, minutes: Int)] = [
      // "Halb vier" is half past three.
      ("Meeting halb vier", 15 * 60 + 30), ("Meeting um halb vier", 15 * 60 + 30), ("Meeting um halb 4", 15 * 60 + 30),
      ("Meeting halb 4", 15 * 60 + 30), ("Meeting halb eins", 12 * 60 + 30), ("Meeting halb zwölf", 11 * 60 + 30),
      ("Meeting halb zwoelf", 11 * 60 + 30), ("Meeting halb sieben morgens", 6 * 60 + 30),
      ("Meeting halb vier nachmittags", 15 * 60 + 30),
      // A quarter past, and a quarter to.
      ("Meeting um viertel vier", 15 * 60 + 15), ("Meeting um dreiviertel vier", 15 * 60 + 45),
      ("Meeting um drei viertel vier", 15 * 60 + 45), ("Meeting Viertel nach drei", 15 * 60 + 15),
      ("Meeting Viertel vor vier", 15 * 60 + 45),
      // Minutes past, minutes to, and minutes around the half hour.
      ("Meeting um fünf nach drei", 15 * 60 + 5), ("Meeting um fuenf nach drei", 15 * 60 + 5),
      ("Meeting um zehn vor vier", 15 * 60 + 50), ("Meeting um fünf vor halb vier", 15 * 60 + 25),
      ("Meeting um zehn nach halb vier", 15 * 60 + 40),
    ]
    for line in spoken {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "Meeting", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Half past midnight, and a part of the day before the spoken time.
    let night = parse("Meeting um halb eins nachts")
    #expect(night.startMinutes == 30)
    #expect(night.plannedDayOffset == 1)
    let evening = parse("Mama anrufen morgen Abend um halb acht")
    #expect(evening.plannedDayOffset == 1)
    #expect(evening.startMinutes == 19 * 60 + 30)
    #expect(evening.title == "Mama anrufen")
    // Without "um" or a clock beside them, the spoken forms are words of the title.
    expectLinesUnread(
      [
        "Meeting viertel vier", "Meeting fünf nach drei", "Meeting fuenf nach drei", "Halb so wild",
        "Viertel Wein bestellen", "Drei Viertel Wein", "Dreiviertel Takt üben", "Fünf nach Zwölf",
      ], languages: ["de"])
  }

  @Test("An hour spelled as a word after um or gegen is a clock time, and a count of things is not")
  func spelledHours() {
    let spelled: [(text: String, minutes: Int)] = [
      ("Meeting um drei Uhr", 15 * 60), ("Meeting um drei", 15 * 60), ("Meeting um zwölf Uhr", 12 * 60),
      ("Meeting um zwoelf Uhr", 12 * 60), ("Meeting um zwolf Uhr", 12 * 60), ("Meeting um eins", 13 * 60),
      ("Meeting um ein Uhr", 13 * 60), ("Meeting um Zwei", 14 * 60), ("Meeting um ZWEI UHR", 14 * 60),
      ("Meeting um drei Uhr nachmittags", 15 * 60), ("Meeting um acht Uhr abends", 20 * 60),
      ("Meeting abends um acht", 20 * 60), ("Meeting abends acht Uhr", 20 * 60), ("Meeting gegen vier", 16 * 60),
      ("Meeting gegen vier Uhr", 16 * 60), ("Meeting so um vier", 16 * 60), ("Meeting ab drei Uhr", 15 * 60),
      ("Meeting um zwei Uhr 30", 14 * 60 + 30),
    ]
    for line in spelled {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "Meeting", "\(line.text): title")
    }
    // The small hours are after midnight.
    let night = parse("Meeting um ein Uhr nachts")
    #expect(night.startMinutes == 60)
    #expect(night.plannedDayOffset == 1)
    // A spelled hour beside a day, and before a word that can follow a time.
    let monday = parse("Zahnarzt am Montag um zehn")
    #expect(monday.plannedDayOffset == 6)
    #expect(monday.startMinutes == 10 * 60)
    #expect(parse("Zahnarzt morgen um elf").startMinutes == 11 * 60)
    let withPerson = parse("Meeting um drei mit Anna")
    #expect(withPerson.startMinutes == 15 * 60)
    #expect(withPerson.title == "Meeting mit Anna")
    // A word that is no hour, a count of things, a watch, an hour with minutes
    // written beside it, and a bare hour without a lead stay in the title.
    expectLinesUnread(
      [
        "Meeting um eine Uhr", "Meeting um drei Kuchen", "Meeting um dreißig Minuten", "Meeting um achtzehn Uhr",
        "Meeting ab drei", "Meeting um drei:30", "Meeting um drei.30 Uhr", "Meeting abends acht",
        "Spiel gegen drei Gegner", "Meeting um zwei Uhren", "Meeting um zwei Uhr dreißig", "Bericht bis drei Uhr",
      ], languages: ["de"])
    // The minutes after "Uhr" in words keep the whole time in the title, with the day still read.
    let words = parse("Zahnarzt morgen um elf Uhr dreißig")
    #expect(words.plannedDayOffset == 1)
    #expect(words.startMinutes == nil)
    #expect(words.title == "Zahnarzt um elf Uhr dreißig")
  }

  @Test("Time ranges: von with bis, zwischen with und, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Meeting von 14 bis 16 Uhr", 14 * 60, 120), ("Meeting von 14:00 bis 16:30", 14 * 60, 150),
      ("Meeting zwischen 14 und 16 Uhr", 14 * 60, 120), ("Meeting 14-16 Uhr", 14 * 60, 120),
      ("Meeting 14 bis 16 Uhr", 14 * 60, 120), ("Meeting 14:00-16:00", 14 * 60, 120),
      ("Meeting 14:00 bis 16:00", 14 * 60, 120), ("Meeting von 9 Uhr bis 17 Uhr", 9 * 60, 480),
      ("Meeting von 8 bis 10 Uhr morgens", 8 * 60, 120), ("Meeting von 14 bis 16", 14 * 60, 120),
      ("Meeting von 14.00 bis 16.00 Uhr", 14 * 60, 120), ("Meeting um 14-16 Uhr", 14 * 60, 120),
      ("Meeting von 22 bis 24 Uhr", 22 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "Meeting", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let daily = parse("Sport täglich von 8 bis 9 Uhr")
    #expect(daily.startMinutes == 8 * 60)
    #expect(daily.estimatedMinutes == 60)
    #expect(daily.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(daily.title == "Sport")
    // Two bare numbers need "von", a clock mark, or a part of the day, and a count or an amount after them is no range.
    expectLinesUnread(
      [
        "Meeting zwischen 14 und 16", "Meeting von 14 bis 16 Personen", "Meeting von 14 bis 16 Seiten",
        "Meeting von 14 bis 16 Euro", "Preis von 10 bis 20 Euro", "Preis von 10 bis 20 €", "Kapitel von 3 bis 5",
      ], languages: ["de"])
  }

  @Test("A bare hour counts as a time only before a word that can follow a time")
  func bareHours() {
    expectLinesUnread(
      [
        "Meeting um 3 Personen", "Meeting um 3 Kuchen", "Treffen um 3 Tage", "Buch über 3 Hunde", "Film um 7 Samurai",
        // An amount or a price.
        "Kaufen um 15 Euro", "Rabatt um 15%", "Rabatt um 15 %", "Preis um 15 €", "Uhr kaufen um 15 Euro",
        // A count of things, and numbers that name a place or a page.
        "Kaffee um die Ecke", "Tisch für 4 reservieren", "Hotel buchen für 3 Nächte", "Alle 3 Kinder abholen",
        // A difference: the number says by how much, not when.
        "Preis um 5 erhöhen", "Preis um 5 senken", "Termin um 2 verschieben", "Gehalt um 3 Prozent erhöhen",
        "Um 3 kuchen backen",
      ], languages: ["de"])
    // An infinitive of an everyday activity follows a time as the task it is for.
    let activities: [(String, Int?, Int, String)] = [
      ("Um 7 aufstehen", nil, 7 * 60, "aufstehen"), ("Um 8 frühstücken", nil, 8 * 60, "frühstücken"),
      ("Heute Abend um 7 kochen", 0, 19 * 60, "kochen"), ("Morgen um 8 joggen", 1, 8 * 60, "joggen"),
      ("Um 6 einkaufen gehen", nil, 18 * 60, "einkaufen gehen"),
    ]
    for (line, day, minutes, title) in activities {
      let reading = parse(line)
      #expect(reading.plannedDayOffset == day, "\(line)")
      #expect(reading.startMinutes == minutes, "\(line)")
      #expect(reading.title == title, "\(line)")
    }
    let withPerson = parse("Meeting um 3 mit Anna")
    #expect(withPerson.startMinutes == 15 * 60)
    #expect(withPerson.title == "Meeting mit Anna")
    let place = parse("Meeting um 3 in Berlin")
    #expect(place.startMinutes == 15 * 60)
    #expect(place.title == "Meeting in Berlin")
    let cafe = parse("Meeting um 3 im Café")
    #expect(cafe.startMinutes == 15 * 60)
    #expect(cafe.title == "Meeting im Café")
    let comma = parse("Meeting um 3, dann Essen")
    #expect(comma.startMinutes == 15 * 60)
    #expect(comma.title == "Meeting, dann Essen")
    let person = parse("Hans um 5 treffen")
    #expect(person.startMinutes == 17 * 60)
    #expect(person.title == "Hans treffen")
    let after = parse("Meeting um 15 Uhr Anna anrufen")
    #expect(after.startMinutes == 15 * 60)
    #expect(after.title == "Meeting Anna anrufen")
    let percent = parse("Meeting 20% Rabatt um 15 Uhr")
    #expect(percent.startMinutes == 15 * 60)
    #expect(percent.title == "Meeting 20% Rabatt")
    // A clock mark makes the number a time even before an ordinary noun.
    let watch = parse("Armbanduhr 15 Uhr")
    #expect(watch.startMinutes == 15 * 60)
    #expect(watch.title == "Armbanduhr")
    let cake = parse("Kuchen 3 Uhr")
    #expect(cake.startMinutes == 15 * 60)
    #expect(cake.title == "Kuchen")
    let size = parse("Zahnarzt Größe 3 Uhr")
    #expect(size.startMinutes == 15 * 60)
    #expect(size.title == "Zahnarzt Größe")
  }

  @Test("An hour written with h is a clock time or a length of hours, beside English in either order")
  func hourWrittenWithH() {
    let clocks: [(text: String, minutes: Int)] = [
      ("Meeting 15h", 15 * 60), ("Meeting um 15h", 15 * 60), ("Meeting um 15h30", 15 * 60 + 30),
      ("Meeting um 3h", 15 * 60),
    ]
    for line in clocks {
      #expect(parse(line.text).startMinutes == line.minutes, "\(line.text)")
      #expect(parse(line.text).estimatedMinutes == nil, "\(line.text): length")
      for languages in [["en", "de"], ["de", "en"]] {
        let parsed = parse(line.text, languages: languages)
        #expect(parsed.startMinutes == line.minutes, "\(line.text) \(languages)")
        #expect(parsed.estimatedMinutes == nil, "\(line.text) \(languages): length")
      }
    }
    // English alone reads "15h" as fifteen hours.
    let english = parse("Meeting 15h", languages: ["en"])
    #expect(english.estimatedMinutes == 15 * 60)
    #expect(english.startMinutes == nil)
    // A small number of hours written with h is a length, in either order.
    for languages in [["de"], ["en", "de"], ["de", "en"]] {
      #expect(parse("Lesen 2h", languages: languages).estimatedMinutes == 120, "\(languages)")
      #expect(parse("Lesen 1h30", languages: languages).estimatedMinutes == 90, "\(languages)")
      #expect(parse("Lesen für 2h", languages: languages).estimatedMinutes == 120, "\(languages)")
      #expect(parse("Lesen 2h", languages: languages).startMinutes == nil, "\(languages)")
    }
    // A number of hours that is no hour of the morning or afternoon is left alone,
    // and so is a fraction of an hour written with h.
    expectLinesUnread(["Lesen 9h", "Meeting 9h", "Lesen 1/2h", "Lesen 3/4h"], languages: ["de"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Lesen 30 Min", 30), ("Lesen 30 Min.", 30), ("Lesen 30 Minuten", 30), ("Lesen 30 min", 30),
      ("Lesen 1 Std", 60), ("Lesen 1 Std.", 60), ("Lesen 1 Stunde", 60), ("Lesen 2 Stunden", 120),
      ("Lesen 1 Stunde 30 Minuten", 90), ("Lesen 1 Std 30 Min", 90), ("Lesen 1,5 Stunden", 90),
      ("Lesen 1.5 Stunden", 90), ("Lesen 2 h", 120), ("Lesen 9 h", 540), ("Lesen 2h", 120), ("Lesen 1h30", 90),
      ("Lesen 1h30m", 90), ("Lesen 1,5h", 90), ("Lesen für 2h", 120), ("Lesen for 2h", 120),
      ("Lesen eine halbe Stunde", 30), ("Lesen halbe Stunde", 30), ("Lesen anderthalb Stunden", 90),
      ("Lesen eineinhalb Stunden", 90), ("Lesen zweieinhalb Stunden", 150), ("Lesen Viertelstunde", 15),
      ("Lesen eine Viertelstunde", 15), ("Lesen viertel Stunde", 15), ("Lesen dreiviertel Stunde", 45),
      ("Lesen drei viertel Stunde", 45), ("Lesen eine Stunde", 60), ("Lesen zwei Stunden", 120),
      ("Lesen zwanzig Minuten", 20), ("Lesen fünf Minuten", 5), ("Lesen fuenf Minuten", 5),
      ("Lesen für 30 Minuten", 30), ("Lesen für zwei Stunden", 120), ("Lesen fuer zwei Stunden", 120),
      ("Lesen ca. 30 Minuten", 30), ("Lesen circa 45 Min", 45), ("Lesen etwa eine halbe Stunde", 30),
      ("Lesen 30 Minuten lang", 30), ("Lesen Dauer: 2 Stunden", 120), ("Lesen for 30 min", 30),
      ("Lesen 1/2 Stunde", 30), ("Lesen 1/4 Stunde", 15), ("Lesen 3/4 Stunde", 45),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Lesen", "\(line.text): title")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    #expect(parse("Lesen für 30 Minuten").phrases.map(\.text) == ["für 30 Minuten"])
    let both = parse("Meeting um 15 Uhr für 45 Minuten")
    #expect(both.startMinutes == 15 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "Meeting")
    let hour = parse("Meeting um 15:00 für eine Stunde")
    #expect(hour.startMinutes == 15 * 60)
    #expect(hour.estimatedMinutes == 60)
    let afterDay = parse("Wäsche waschen morgen um 8 Uhr für 1,5 Stunden")
    #expect(afterDay.plannedDayOffset == 1)
    #expect(afterDay.startMinutes == 8 * 60)
    #expect(afterDay.estimatedMinutes == 90)
    #expect(afterDay.title == "Wäsche waschen")
  }

  @Test("An amount after in, alle, nach, um, pro, mindestens, or before vorher, später, or pro Tag is no length")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, or a bound.
        "Lesen in 30 Minuten", "Lesen in 30 min", "Lesen alle 30 Minuten", "Lesen nach 2 Stunden",
        "Lesen um 15 Minuten", "Lesen pro Stunde", "Lesen mindestens 2 Stunden",
        // A difference, and a rate.
        "Lesen 30 Minuten vorher", "Lesen 30 Minuten später", "Lesen 30 Minuten vor dem Meeting",
        "Lesen 2 Stunden pro Tag",
        // A range of amounts, an amount that is none, and a unit as a noun.
        "Lesen 5-6 Stunden", "Lesen 0 Minuten", "Lesen 25 Stunden", "Lesen 9h", "Minute Papier",
        "Stundenplan ändern", "Uhr reparieren", "Frist: 3 Tage",
      ], languages: ["de"])
    // The details around an amount that is no length still read.
    let daily = parse("Lesen 30 Minuten täglich")
    #expect(daily.estimatedMinutes == 30)
    #expect(daily.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(daily.title == "Lesen")
    let before = parse("Lesen täglich 30 Minuten")
    #expect(before.estimatedMinutes == 30)
    #expect(before.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(before.title == "Lesen")
    // In English alone a moment "in 15 min" is a length; with German it stays whole.
    #expect(parse("Call in 15 min", languages: ["en"]).estimatedMinutes == 15)
    #expect(parse("Call in 15 min").estimatedMinutes == nil)
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func cadences() {
    let daily = TaskRecurrenceRule(freq: .daily)
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Sport jeden Tag", daily), ("Sport täglich", daily), ("Sport tagtäglich", daily), ("Sport taeglich", daily),
      ("Sport jeden Morgen", daily), ("Sport jeden Abend", daily), ("Sport jede Nacht", daily),
      ("Sport einmal täglich", daily), ("Sport einmal am Tag", daily),
      ("Sport jede Woche", weekly), ("Sport wöchentlich", weekly), ("Sport einmal pro Woche", weekly),
      ("Sport einmal wöchentlich", weekly), ("Sport alle 7 Tage", weekly),
      ("Sport monatlich", monthly), ("Sport jeden Monat", monthly), ("Sport einmal im Monat", monthly),
      ("Sport jährlich", yearly), ("Sport jedes Jahr", yearly), ("Sport alljährlich", yearly),
      ("Sport einmal im Jahr", yearly),
      ("Sport alle 3 Tage", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Sport alle zwei Tage", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Sport jeden zweiten Tag", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Sport jeden dritten Tag", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Sport alle zwoelf Tage", TaskRecurrenceRule(freq: .daily, interval: 12)),
      ("Sport alle 2 Wochen", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport alle zwei Wochen", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport alle 14 Tage", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport jede zweite Woche", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport zweiwöchentlich", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport zweiwoechentlich", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport vierzehntägig", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport 14-tägig", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Sport jeden zweiten Monat", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Sport zweimonatlich", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Sport alle zwei Monate", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Sport alle 3 Monate", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Sport vierteljährlich", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Sport dreimonatlich", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Sport halbjährlich", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("Sport jedes zweite Jahr", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("Sport alle 2 Jahre", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("Sport alle zwei Jahre", TaskRecurrenceRule(freq: .yearly, interval: 2)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "Sport", "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // A repeat in front of the line, and a date beside a yearly repeat.
    for text in ["Jeden Tag Obst essen", "Täglich Obst essen"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == daily, "\(text)")
      #expect(parsed.title == "Obst essen", "\(text): title")
    }
    #expect(parse("Wöchentlich Sport").recurrence == weekly)
    let birthday = parse("Geburtstag 3. Juni jedes Jahr")
    #expect(birthday.recurrence == yearly)
    #expect(birthday.plannedDayOffset == captureDayOffset("2027-06-03"))
    #expect(birthday.title == "Geburtstag")
    let date = parse("Sport jedes Jahr am 15. Oktober")
    #expect(date.recurrence == yearly)
    #expect(date.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(date.title == "Sport")
  }

  @Test("Weekday repeats: jeden Montag, montags, and the working days and the weekend")
  func weekdayRepeats() {
    let coming = parse("Sport jeden Montag")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Sport")
    for text in ["Sport montags", "Sport an jedem Montag", "Sport jede Woche am Montag", "Sport jeden Mo"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == monday, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.title == "Sport", "\(text): title")
    }
    let pairs: [(text: String, days: [String])] = [
      ("Sport jeden Montag und Donnerstag", ["MO", "TH"]),
      ("Sport jeden Montag, Mittwoch und Freitag", ["MO", "WE", "FR"]),
      ("Sport jeden Montag, Dienstag und Freitag", ["MO", "TU", "FR"]),
      ("Sport montags und donnerstags", ["MO", "TH"]),
      ("Sport montags, mittwochs und freitags", ["MO", "WE", "FR"]),
      ("Sport jeden Mo und Do", ["MO", "TH"]),
      ("Sport jeden Mo, Mi und Fr", ["MO", "WE", "FR"]),
      ("Sport an jedem Montag und Freitag", ["MO", "FR"]),
      ("Sport jede Woche am Montag", ["MO"]),
      ("Sport samstags und sonntags", ["SU", "SA"]),
      ("Putzen samstags", ["SA"]),
      ("Sport jedes Wochenende", ["SU", "SA"]),
      ("Sport an Wochenenden", ["SU", "SA"]),
      ("Sport wochenends", ["SU", "SA"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
    }
    let everyOther = parse("Sport jeden zweiten Montag")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    #expect(everyOther.recurrenceStartOffset == 6)
    #expect(
      parse("Sport jede zweite Woche am Freitag").recurrence
        == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR"]))
    #expect(
      parse("Sport alle zwei Wochen am Montag").recurrence
        == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    // A counted interval takes the weekdays after it, as "am", "jeden", or an adverb.
    let intervals: [(text: String, interval: Int?, days: [String])] = [
      ("Sport alle 2 Wochen montags", 2, ["MO"]), ("Sport alle 2 Wochen montags und mittwochs", 2, ["MO", "WE"]),
      ("Sport jede zweite Woche montags", 2, ["MO"]), ("Sport alle zwei Wochen jeden Montag", 2, ["MO"]),
      ("Sport alle zwei Wochen jeden Donnerstag und Montag", 2, ["MO", "TH"]),
      ("Sport alle 2 Wochen am Montag und Donnerstag", 2, ["MO", "TH"]),
      ("Sport alle 2 Wochen am Mittwoch, Freitag und Sonntag", 2, ["SU", "WE", "FR"]),
      ("Sport jede Woche am Montag und Donnerstag", nil, ["MO", "TH"]),
      ("Sport jede Woche am Samstag und Sonntag", nil, ["SU", "SA"]),
    ]
    for line in intervals {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, interval: line.interval, byDay: line.days), "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "Sport", "\(line.text): title")
    }
    for text in [
      "Sport werktags", "Sport werktäglich", "Sport an Werktagen", "Sport jeden Werktag", "Sport wochentags",
      "Sport an Wochentagen", "Sport jeden Wochentag", "Sport an allen Wochentagen", "Sport Montag bis Freitag",
      "Sport von Montag bis Freitag", "Sport Mo-Fr", "Sport Mo - Fr", "Sport Mo bis Fr",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text)")
      #expect(parsed.title == "Sport", "\(text): title")
    }
    // The weekend repeat starts on the nearer day, and "am Wochenende" is one day.
    #expect(parse("Sport jedes Wochenende").recurrence == weekend)
    #expect(parse("Sport jedes Wochenende").recurrenceStartOffset == 4)
    let day = parse("Sport am Wochenende")
    #expect(day.recurrence == nil)
    #expect(day.plannedDayOffset == 4)
    // The start of a repeat on Thursday and Monday is the nearer one.
    #expect(parse("Sport jeden Montag und Donnerstag").recurrenceStartOffset == 2)
    // A repeat with a time.
    let timed = parse("Sport jeden Montag und Donnerstag um 18 Uhr")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "Sport")
    let weekendTimed = parse("Sport jedes Wochenende um 10 Uhr")
    #expect(weekendTimed.recurrence == weekend)
    #expect(weekendTimed.startMinutes == 10 * 60)
    let friday = parse("Gießen freitags um 8 Uhr")
    #expect(friday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(friday.startMinutes == 8 * 60)
    #expect(friday.title == "Gießen")
    let evening = parse("Müll rausbringen jeden Dienstag und Freitag um 19 Uhr")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "FR"]))
    #expect(evening.recurrenceStartOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "Müll rausbringen")
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [15])
    for text in [
      "Sport jeden Monat am 15.", "Sport am 15. jedes Monats", "Sport jeden 15. des Monats",
      "Sport zum 15. jedes Monats", "Sport jeden Monat zum 15.",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 23, "\(text)")
      #expect(parsed.title == "Sport", "\(text): title")
    }
    let first = parse("Sport monatlich am 1.")
    #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    #expect(first.recurrenceStartOffset == 9)
    // A day with its month name is a date, not a repeat.
    #expect(parse("Sport jeden 15. Oktober").recurrence == nil)
  }

  @Test("A weekday by its place in the month stays whole, and a cadence adjective or noun stays in the title")
  func unreadRepeats() {
    expectLinesUnread(
      [
        // A weekday by its place in the month has no repeat rule, so no part of it is read as a weekday.
        "Sport jeden ersten Montag im Monat", "Sport jeden ersten Montag", "Sport jeden dritten Freitag",
        "Sport jeden zweiten Montag im Monat", "Gießen jeden 2. Montag", "Gießen jeden 1. Montag im Monat",
        "Gießen jeden 3. Freitag",
        // An adjective, a compound, or a count of days.
        "Sport tägliches Training", "Sport wöchentliches Meeting", "Sport Montags-Meeting", "Sport 5 Tage",
        // An interval written with an ordinal number, and cadences the repeat has no rule for.
        "Gießen jede 2. Woche", "Gießen jeden 2. Tag", "Gießen jedes Quartal", "Gießen stündlich",
        "Gießen jeden ersten Tag", "Gießen an jedem Tag",
        // Words that open with the letters of a cadence.
        "Alle Kinder abholen", "Alle 3 Kinder abholen", "Jede Menge Arbeit", "Jedes Mal fragen",
        "Einmal Pizza bestellen",
      ], languages: ["de"])
    // A day written after "jeden Tag außer" is left out of the repeat's days.
    let except = parse("Gießen täglich außer Sonntag")
    #expect(except.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(except.plannedDayOffset == nil)
  }

  // MARK: - Priorities

  @Test("Priorities: dringend, wichtig, hohe and niedrige Priorität, and Prio")
  func priorities() {
    let priorities: [(text: String, title: String, priority: LorvexTask.Priority)] = [
      ("Lesen dringend", "Lesen", .p1), ("Lesen wichtig", "Lesen", .p1), ("Lesen sehr dringend", "Lesen", .p1),
      ("Dringend: Lesen", "Lesen", .p1), ("Wichtig, Lesen", "Lesen", .p1),
      // The full stop or exclamation mark that ends the line goes with the word.
      ("Lesen dringend.", "Lesen", .p1), ("Lesen wichtig!", "Lesen", .p1),
      ("Bericht schreiben, dringend.", "Bericht schreiben", .p1),
      ("Lesen Priorität hoch", "Lesen", .p1), ("Lesen hohe Priorität", "Lesen", .p1),
      ("Lesen hohe Prio", "Lesen", .p1), ("Lesen höchste Priorität", "Lesen", .p1), ("Lesen Prio 1", "Lesen", .p1),
      ("Prioritaet hoch Lesen", "Lesen", .p1), ("Lesen Prioritaet hoch", "Lesen", .p1),
      ("Dringend: Praesentation", "Praesentation", .p1),
      ("Lesen Prio: niedrig", "Lesen", .p3), ("Lesen niedrige Priorität", "Lesen", .p3),
      ("Lesen geringe Priorität", "Lesen", .p3), ("Lesen Prio 3", "Lesen", .p3),
      ("Lesen Prioritaet niedrig", "Lesen", .p3),
      ("Lesen mittlere Priorität", "Lesen", .p2), ("Lesen normale Priorität", "Lesen", .p2),
      ("Lesen Prio 2", "Lesen", .p2),
      ("LESEN DRINGEND", "LESEN", .p1), ("LESEN HOHE PRIORITÄT", "LESEN", .p1),
      // The shorthand every language reads.
      ("Lesen !", "Lesen", .p1), ("Lesen p1", "Lesen", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A negated word, an adjective that describes a noun, and a word alone are no priority.
    expectLinesUnread(
      [
        "Lesen nicht dringend", "Lesen nicht so wichtig", "Lesen unwichtig", "Das ist nicht wichtig", "Lesen Prio 4",
        "Lesen Priorität", "Wichtiger Termin", "Dringende Anfrage beantworten", "Dringender Anruf", "Wichtige Mail",
        "Priorität prüfen", "Prio ändern",
      ], languages: ["de"])
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyDetail() {
    let line = parse("Bericht schreiben morgen um 15 Uhr für 2 Stunden dringend")
    #expect(line.title == "Bericht schreiben")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.priority == .p1)
    #expect(line.phrases.map(\.text) == ["morgen", "um 15 Uhr", "für 2 Stunden", "dringend"])
    let recurring = parse("Sport jeden Montag um 18 Uhr für 1 Stunde hohe Priorität")
    #expect(recurring.title == "Sport")
    #expect(recurring.recurrence == monday)
    #expect(recurring.startMinutes == 18 * 60)
    #expect(recurring.estimatedMinutes == 60)
    #expect(recurring.priority == .p1)
    let due = parse("Steuererklärung bis zum 31.7. Prio 2")
    #expect(due.title == "Steuererklärung")
    #expect(due.dueDayOffset == captureDayOffset("2027-07-31"))
    #expect(due.priority == .p2)
    // Lists and tags beside German details.
    let list = LorvexCaptureParser.parse(
      "Einkaufen #Liste morgen", lists: [.init(id: "L1", name: "Liste")], todayWeekday: 3, today: "2026-09-22",
      languages: ["de"])
    #expect(list.listName == "Liste")
    #expect(list.plannedDayOffset == 1)
    #expect(list.title == "Einkaufen")
    let tag = parse("Einkaufen heute #privat")
    #expect(tag.tags == ["privat"])
    #expect(tag.plannedDayOffset == 0)
    #expect(tag.title == "Einkaufen")
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Nouns made of a day word, a time word, or a number word.
        "Dienstleistung buchen", "Frühstück machen", "Tageskarte kaufen", "Stundenplan ändern",
        "Monatsbericht schreiben", "Vorbereitung Monatsabschluss", "Geburtstag von Oma", "Tag der Arbeit",
        // A word that is a weekday abbreviation or a month in another sense.
        "So geht's nicht", "Do not disturb", "Mo Mi Fr Training", "Zahnarzt Mo",
        // A noun that is a street or a title.
        "Strasse sperren", "Bericht ueber das Projekt", "Über Nacht backen",
        // Numbers that are counts, places, and amounts.
        "Tisch für 4 reservieren", "Buch Seite 15 lesen", "Kaffee um die Ecke",
      ], languages: ["de"])
    // A weekday that is a day, before other words.
    let report = parse("Zahnarzt am Freitag war ich dort")
    #expect(report.plannedDayOffset == 3)
    #expect(report.title == "Zahnarzt war ich dort")
  }

  @Test("Umlauts are read as the vowel or its digraph, ß as s or ss, and the title keeps the letters it was typed with")
  func umlautSpelling() {
    let spelled: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Zahnarzt übermorgen", { $0.plannedDayOffset == 2 }), ("Zahnarzt uebermorgen", { $0.plannedDayOffset == 2 }),
      ("Zahnarzt ubermorgen", { $0.plannedDayOffset == 2 }),
      ("Bericht bis spätestens Freitag", { $0.dueDayOffset == 3 }),
      ("Bericht bis spaetestens Freitag", { $0.dueDayOffset == 3 }),
      ("Meeting um 8 Uhr früh", { $0.startMinutes == 8 * 60 }), ("Meeting um 8 Uhr frueh", { $0.startMinutes == 8 * 60 }),
      ("Sport wöchentlich", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("Sport woechentlich", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("Sport zweiwoechentlich", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2) }),
      ("Sport alljährlich", { $0.recurrence == TaskRecurrenceRule(freq: .yearly) }),
      ("Sport alljaehrlich", { $0.recurrence == TaskRecurrenceRule(freq: .yearly) }),
      ("Lesen fünf Minuten", { $0.estimatedMinutes == 5 }), ("Lesen fuenf Minuten", { $0.estimatedMinutes == 5 }),
      ("Meeting um halb zwölf", { $0.startMinutes == 11 * 60 + 30 }),
      ("Meeting um halb zwoelf", { $0.startMinutes == 11 * 60 + 30 }),
      ("Urlaub 3. März", { $0.plannedDayOffset == captureDayOffset("2027-03-03") }),
      ("Urlaub 3. Maerz", { $0.plannedDayOffset == captureDayOffset("2027-03-03") }),
      ("Zahnarzt nächste Woche Mittwoch", { $0.plannedDayOffset == 8 }),
      ("Zahnarzt naechste Woche Mittwoch", { $0.plannedDayOffset == 8 }),
      ("Zahnarzt naechsten Freitag", { $0.plannedDayOffset == 10 }),
      ("Lesen für zwei Stunden", { $0.estimatedMinutes == 120 }), ("Lesen fuer zwei Stunden", { $0.estimatedMinutes == 120 }),
      ("Sport täglich", { $0.recurrence == TaskRecurrenceRule(freq: .daily) }),
      ("Sport taeglich", { $0.recurrence == TaskRecurrenceRule(freq: .daily) }),
      ("Sport alle zwoelf Tage", { $0.recurrence == TaskRecurrenceRule(freq: .daily, interval: 12) }),
      ("Meeting um fünf nach drei", { $0.startMinutes == 15 * 60 + 5 }),
      ("Meeting um fuenf nach drei", { $0.startMinutes == 15 * 60 + 5 }),
      ("Lesen Priorität hoch", { $0.priority == .p1 }), ("Lesen Prioritaet hoch", { $0.priority == .p1 }),
    ]
    for line in spelled {
      #expect(line.check(parse(line.text)), "\(line.text)")
    }
    // The letters of the title stay as they were typed, around and between the details.
    let titles: [(text: String, title: String)] = [
      ("Wäsche waschen morgen", "Wäsche waschen"), ("Käse kaufen heute", "Käse kaufen"),
      ("Mülltonne rausstellen jeden Dienstag", "Mülltonne rausstellen"),
      ("Prüfung vorbereiten bis Freitag", "Prüfung vorbereiten"), ("Zahnarzt Größe 3 Uhr", "Zahnarzt Größe"),
      ("Gießen alle 2 Tage", "Gießen"), ("Ausflug Strasse bis Freitag", "Ausflug Strasse"),
      ("Ärzte Besuch morgen", "Ärzte Besuch"), ("Üben heute", "Üben"), ("Café morgen", "Café"),
      ("Bericht für übermorgen", "Bericht"),
    ]
    for line in titles {
      #expect(scalars(parse(line.text).title) == scalars(line.title), "\(line.text)")
    }
    let both = parse("Öl wechseln morgen um 15 Uhr Größe 3")
    #expect(both.plannedDayOffset == 1)
    #expect(both.startMinutes == 15 * 60)
    #expect(both.title == "Öl wechseln Größe 3")
  }

  @Test("Capitals read like lowercase letters, and the title keeps the capitals it was typed with")
  func capitals() {
    let lines: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("ZAHNARZT HEUTE ABEND", "ZAHNARZT", { $0.plannedDayOffset == 0 }),
      ("ZAHNARZT AM 15. OKTOBER", "ZAHNARZT", { $0.plannedDayOffset == 23 }),
      ("MEETING UM 15 UHR", "MEETING", { $0.startMinutes == 15 * 60 }),
      ("MEETING UM HALB VIER", "MEETING", { $0.startMinutes == 15 * 60 + 30 }),
      ("SPORT JEDEN MONTAG", "SPORT", { $0.recurrence == monday }),
      ("SPORT WÖCHENTLICH", "SPORT", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("SPORT TÄGLICH", "SPORT", { $0.recurrence == TaskRecurrenceRule(freq: .daily) }),
      ("LESEN 30 MIN", "LESEN", { $0.estimatedMinutes == 30 }),
      ("LESEN DRINGEND", "LESEN", { $0.priority == .p1 }),
      ("BERICHT BIS FREITAG", "BERICHT", { $0.dueDayOffset == 3 }),
      ("Zahnarzt MONTAG", "Zahnarzt", { $0.plannedDayOffset == 6 }),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(line.check(parsed), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    #expect(parse("STRASSE SPERREN").title == "STRASSE SPERREN")
    #expect(parse("STRASSE SPERREN").phrases.isEmpty)
  }

  @Test("Letters typed as a base letter and a combining mark read like the precomposed letters")
  func decomposedLetters() {
    let lines: [(typed: String, title: String)] = [
      ("Zahnarzt übermorgen", "Zahnarzt"), ("Wäsche waschen morgen früh", "Wäsche waschen"),
      ("Meeting um halb zwölf", "Meeting"), ("Bericht bis spätestens Freitag", "Bericht"),
      ("Sport wöchentlich", "Sport"), ("Sport alljährlich", "Sport"), ("Lesen für 30 Minuten", "Lesen"),
      ("Urlaub 3. März", "Urlaub"), ("Urlaub 3. Jänner", "Urlaub"), ("Zahnarzt nächste Woche", "Zahnarzt"),
      ("Sport täglich um 8 Uhr", "Sport"), ("Käse kaufen heute", "Käse kaufen"),
      ("Mülltonne rausstellen jeden Dienstag", "Mülltonne rausstellen"), ("Lesen Priorität hoch", "Lesen"),
      ("Meeting um 8 Uhr früh", "Meeting"), ("Zahnarzt Größe 3 Uhr", "Zahnarzt Größe"),
      ("ÜBERMORGEN ZAHNARZT", "ZAHNARZT"), ("Üben heute", "Üben"), ("Ärzte Besuch morgen", "Ärzte Besuch"),
      ("Sport zweiwöchentlich", "Sport"), ("Meeting zwischen 14 und 16 Uhr", "Meeting"), ("Café morgen", "Café"),
      ("Meeting um zehn vor vier", "Meeting"), ("Zahnarzt Samstagabend", "Zahnarzt"),
      ("Lesen für zwei Stunden", "Lesen"),
    ]
    for line in lines {
      let composed = line.typed.precomposedStringWithCanonicalMapping
      let decomposed = line.typed.decomposedStringWithCanonicalMapping
      let expected = parse(composed)
      let parsed = parse(decomposed)
      #expect(parsed == expected, "\(line.typed)")
      #expect(!parsed.phrases.isEmpty, "\(line.typed): phrases")
      // Each form keeps its own scalars in the title.
      #expect(scalars(expected.title) == scalars(line.title.precomposedStringWithCanonicalMapping), "\(line.typed)")
      #expect(scalars(parsed.title) == scalars(line.title.decomposedStringWithCanonicalMapping), "\(line.typed)")
    }
    // A mark on a letter that is part of no detail changes nothing either.
    let stray = "u\u{0308}ber Bru\u{0308}cke"
    #expect(scalars(parse("\(stray) morgen").title) == scalars(stray))
    #expect(parse("\(stray) morgen").plannedDayOffset == 1)
  }

  // MARK: - Beside other languages

  @Test("Beside German, English lines read as they do alone, and an hour written with h is German's")
  func besideEnglish() {
    // English lines read the same with German beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily",
    ] {
      for languages in [["en", "de"], ["de", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // English alone reads "2h" as two hours and "15h" as fifteen; German reads "15h" as a time.
    let hours = parse("Write the report 2h", languages: ["en", "de"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "de"])
    #expect(clock.startMinutes == 15 * 60)
    #expect(clock.title == "Meet at")
    // A line may mix both languages.
    let mixed = parse("Call mom morgen at 3pm", languages: ["en", "de"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting am Freitag at 3pm", languages: ["en", "de"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Zahnarzt tomorrow", languages: ["en", "de"]).plannedDayOffset == 1)
    let review = parse("Review tomorrow at 3pm for 2 hours", languages: ["en", "de"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
  }

  @Test("Lines in other languages read the same with German beside them")
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
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "de"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["de", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix German with another language.
    #expect(parse("Appeler maman demain 15 Uhr", languages: ["fr", "de"]).startMinutes == 15 * 60)
    #expect(parse("Zahnarzt morgen 下午3点", languages: ["zh", "de"]).plannedDayOffset == 1)
    #expect(parse("Zahnarzt morgen", languages: ["he", "de"]).plannedDayOffset == 1)
    #expect(parse("Meeting jutro", languages: ["pl", "de"]).plannedDayOffset == 1)
  }

  @Test("German words are read only for a user who reads German")
  func languageGate() {
    let line = parse("Zahnarzt übermorgen", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Zahnarzt übermorgen")
    for languages in [["de"], ["de-DE"], ["de_CH"], ["de-AT"], ["en-US", "de-DE"], ["DE"]] {
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == 2, "\(languages)")
    }
    // Words of the languages written in Latin letters are not read for a German reader.
    for text in ["Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == nil, "\(text)")
      #expect(parsed.title == text, "\(text): title")
    }
    // German words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"]] {
      let parsed = parse("Zahnarzt übermorgen", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Zahnarzt übermorgen", "\(languages): title")
      #expect(parse("Meeting um 15 Uhr", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("Sport jeden Montag", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("um 15 Uhr ", 450), ("um 3 ", 1600), ("halb ", 1000), ("viertel ", 625), ("fünf nach ", 500),
      ("zehn vor halb ", 357), ("Viertel nach ", 384), ("15:30 ", 833), ("15.30 ", 833), ("0 Uhr ", 833),
      ("24 Uhr ", 714), ("12:30 pm ", 555), ("heute Abend ", 417), ("morgen früh ", 417), ("jeden Montag ", 384),
      ("jeden zweiten Tag ", 277), ("alle 2 Wochen ", 357), ("am 15. Oktober ", 333), ("vom 3. bis 5. Mai ", 277),
      ("von Montag bis Mittwoch ", 208), ("von Mo bis Mi ", 357), ("bis Freitag ", 416), ("nächste Woche ", 357),
      ("30 Minuten ", 454), ("2h ", 1666), ("eine halbe Stunde ", 277), ("5-6 Stunden ", 416),
      ("hohe Priorität ", 357), ("14-16 Uhr ", 500), ("von 14 bis 16 Uhr ", 277), ("Sprint 12 - 20 Mai ", 263),
      ("so ", 1666), ("Mo ", 1666), ("3.-", 1666), ("ä", 5000), ("ae", 2500), ("ss", 2500), ("ß", 5000),
      ("u\u{0308}", 2500), ("jeden ", 833), ("alle ", 1000), ("zwischen ", 555), ("bis ", 1250), ("von ", 1250),
      ("Uhr ", 1250), ("15 ", 1666), ("3. ", 1666), ("Mai ", 1250), ("Montag ", 714), ("Woche ", 833),
      ("dringend ", 555), ("Prio ", 1000), (", ", 2500), (".", 5000),
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
