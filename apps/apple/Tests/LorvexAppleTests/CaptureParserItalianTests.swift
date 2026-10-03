import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["it-IT"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])

/// Italian capture lines, read for a user whose languages include Italian.
@Suite("Capture parser Italian")
struct CaptureParserItalianTests {
  @Test("Days, typed with or without accents")
  func days() {
    let line = parse("Chiamare Paolo domani")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Chiamare Paolo")
    #expect(line.phrases.map(\.text) == ["domani"])

    #expect(parse("Dentista DOMANI").plannedDayOffset == 1)
    #expect(parse("Dentista oggi").plannedDayOffset == 0)
    #expect(parse("Dentista oggi").title == "Dentista")
    #expect(parse("Restituire il libro dopodomani").plannedDayOffset == 2)
    #expect(parse("Restituire il libro dopo domani").plannedDayOffset == 2)
    #expect(parse("Restituire il libro dopodomani").title == "Restituire il libro")
    #expect(parse("Pulizie nel fine settimana").plannedDayOffset == 4)
    #expect(parse("Pulizie il fine settimana").plannedDayOffset == 4)
    #expect(parse("Pulizie nel weekend").plannedDayOffset == 4)
    #expect(parse("Pulizie questo weekend").plannedDayOffset == 4)
    #expect(parse("Pulizie il prossimo weekend").plannedDayOffset == 11)
    #expect(parse("Pulizie il weekend prossimo").plannedDayOffset == 11)
    #expect(parse("Pulizie il weekend prossimo").title == "Pulizie")
    #expect(parse("Bilancio la settimana prossima").plannedDayOffset == 7)
    #expect(parse("Bilancio la prossima settimana").plannedDayOffset == 7)
    #expect(parse("Bilancio la settimana che viene").plannedDayOffset == 7)
    #expect(parse("Bilancio la settimana prossima").title == "Bilancio")
    #expect(parse("Richiamare tra 3 giorni").plannedDayOffset == 3)
    #expect(parse("Richiamare fra 3 giorni").plannedDayOffset == 3)
    #expect(parse("Richiamare tra una settimana").plannedDayOffset == 7)
    #expect(parse("Richiamare tra 2 settimane").plannedDayOffset == 14)
    #expect(parse("Richiamare tra una settimana").title == "Richiamare")
    #expect(parse("Inviare il preventivo da domani").plannedDayOffset == 1)
    #expect(parse("Inviare il preventivo da domani").title == "Inviare il preventivo")
  }

  @Test("Evenings and parts of a day")
  func partsOfADay() {
    let tonight = parse("Cena stasera")
    #expect(tonight.plannedDayOffset == 0)
    #expect(tonight.startMinutes == nil)
    #expect(tonight.title == "Cena")
    #expect(parse("Cena questa sera").plannedDayOffset == 0)
    #expect(parse("Riunione stamattina").plannedDayOffset == 0)
    #expect(parse("Riunione oggi pomeriggio").plannedDayOffset == 0)
    #expect(parse("Riunione questo pomeriggio").plannedDayOffset == 0)
    #expect(parse("Riunione questo pomeriggio").title == "Riunione")
    #expect(parse("Cena domani sera").plannedDayOffset == 1)
    #expect(parse("Cena sabato sera").plannedDayOffset == 4)
    #expect(parse("Cena sabato sera").title == "Cena")
    #expect(parse("Riunione lunedì mattina").plannedDayOffset == 6)
    let stars = parse("Stanotte guardare le stelle")
    #expect(stars.plannedDayOffset == 0)
    #expect(stars.title == "guardare le stelle")
    // A bare hour named with an evening is the evening's.
    let supper = parse("Cena stasera alle 8")
    #expect(supper.plannedDayOffset == 0)
    #expect(supper.startMinutes == 20 * 60)
    #expect(supper.title == "Cena")
    #expect(parse("Film domani sera alle 21").startMinutes == 21 * 60)
    #expect(parse("Film domani sera alle 21").plannedDayOffset == 1)
    #expect(parse("Cena sabato sera alle 8").plannedDayOffset == 4)
    #expect(parse("Cena sabato sera alle 8").startMinutes == 20 * 60)
  }

  @Test("Lunedì is the coming Monday, with or without the accent")
  func weekdays() {
    let coming = parse("Riunione lunedì")
    #expect(coming.plannedDayOffset == 6)
    #expect(coming.recurrence == nil)
    #expect(coming.title == "Riunione")
    #expect(parse("Riunione lunedi").plannedDayOffset == 6)
    #expect(parse("Piscina venerdì").plannedDayOffset == 3)
    #expect(parse("Piscina venerdi").plannedDayOffset == 3)
    #expect(parse("Piscina mercoledì").plannedDayOffset == 1)
    #expect(parse("Piscina sabato").plannedDayOffset == 4)
    #expect(parse("Piscina domenica").plannedDayOffset == 5)
    #expect(parse("Pranzo con Anna domenica").plannedDayOffset == 5)
    #expect(parse("Pranzo con Anna domenica").title == "Pranzo con Anna")
    // Today is Tuesday, so Tuesday alone is a week ahead and "questo martedì" today.
    #expect(parse("Mercato martedì").plannedDayOffset == 7)
    #expect(parse("Mercato questo martedì").plannedDayOffset == 0)
    #expect(parse("Piscina questo venerdì").plannedDayOffset == 3)
    #expect(parse("Piscina venerdì prossimo").plannedDayOffset == 10)
    #expect(parse("Piscina il prossimo venerdì").plannedDayOffset == 10)
    #expect(parse("Piscina lunedì prossimo").plannedDayOffset == 6)
    #expect(parse("Piscina lunedì prossimo").title == "Piscina")
  }

  @Test("Il lunedì, ogni lunedì, and tutti i lunedì repeat")
  func habitualWeekdays() {
    let habit = parse("Palestra il lunedì")
    #expect(habit.recurrence == monday)
    #expect(habit.plannedDayOffset == nil)
    #expect(habit.title == "Palestra")
    #expect(parse("Palestra il lunedi").recurrence == monday)
    #expect(parse("Sport ogni lunedì").recurrence == monday)
    #expect(parse("Corso tutti i lunedì").recurrence == monday)
    #expect(parse("Corso tutti i lunedì").title == "Corso")
    #expect(parse("Messa la domenica").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(parse("Palestra i sabati").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(parse("Calcio i mercoledì").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["WE"]))
    #expect(
      parse("Palestra il lunedì e il giovedì").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(
      parse("Palestra il lunedì e giovedì").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(
      parse("Mercato il martedì e il sabato").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "SA"]))
    // A time is read first, so the weekday still ends the line.
    let timed = parse("Palestra il lunedì alle 18")
    #expect(timed.recurrence == monday)
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "Palestra")
  }

  @Test("The article forms of a weekday stay in the title inside ordinary text")
  func weekdayArticleGuards() {
    for text in [
      "La riunione del lunedì", "Riunione di lunedì", "Pranzo di sabato", "Riunione lunedì scorso", "Il lunedì palestra",
      "Pizza il sabato sera", "Chiamare Domenica",
    ] {
      let line = parse(text)
      #expect(line.plannedDayOffset == nil)
      #expect(line.recurrence == nil)
      #expect(line.title == text)
    }
    // A capitalized Domenica that opens the line is the day.
    let sunday = parse("Domenica pranzo in famiglia")
    #expect(sunday.plannedDayOffset == 5)
    #expect(sunday.title == "pranzo in famiglia")
  }

  @Test("Dates written out, and a day of the month alone")
  func dates() {
    let line = parse("Festa il 5 ottobre")
    #expect(line.plannedDayOffset == 13)
    #expect(line.title == "Festa")
    #expect(parse("Festa 5 ottobre").plannedDayOffset == 13)
    #expect(parse("Festa 5 di ottobre").plannedDayOffset == 13)
    #expect(parse("Festa lunedì 5 ottobre").plannedDayOffset == 13)
    #expect(parse("Festa lunedì 5 ottobre").title == "Festa")
    #expect(parse("Fattura 1º novembre").plannedDayOffset == 40)
    #expect(parse("Festa 1° novembre").plannedDayOffset == 40)
    #expect(parse("Fattura il primo novembre").plannedDayOffset == 40)
    #expect(parse("Viaggio 5 ott.").plannedDayOffset == 13)
    #expect(parse("Festa 5 ottobre 2027").plannedDayOffset == 378)
    // The 5th of this month has passed, so "il 5" is October's.
    #expect(parse("Affitto il 5").plannedDayOffset == 13)
    #expect(parse("Affitto il 5 di ottobre").plannedDayOffset == 13)
    #expect(parse("Chiamare il 15 con Anna").plannedDayOffset == 23)
    #expect(parse("Chiamare il 15 con Anna").title == "Chiamare con Anna")
    // A date already passed this year is next year's.
    #expect(parse("Bilancio 5 febbraio").plannedDayOffset == 136)
    // A date in digits depends on the region, so it stays in the title.
    #expect(parse("Festa 5/10").plannedDayOffset == nil)
    #expect(
      LorvexCaptureParser.parse("Festa il 5 ottobre", lists: [], todayWeekday: 3, languages: ["it"])
        .plannedDayOffset == nil)
  }

  @Test("A day of the month alone counts only at the end or before a word that can follow a date")
  func bareDayOfTheMonth() {
    for text in ["Comprare il 3 di noi", "Comprare 2 set di piatti", "Relazione per 15 persone"] {
      let line = parse(text)
      #expect(line.plannedDayOffset == nil)
      #expect(line.dueDayOffset == nil)
      #expect(line.title == text)
    }
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Vacanze", "dal 3 al 5 maggio", "2027-05-03", "2027-05-05"),
        ("Viaggio a Roma", "dal 3 al 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "dal 30 maggio al 2 giugno", "2027-05-30", "2027-06-02"),
        ("Vacanze", "tra il 3 e il 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "fra il 3 e il 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "3-5 maggio", "2027-05-03", "2027-05-05"),
        ("Ferie", "3-10 agosto", "2027-08-03", "2027-08-10"),
        ("Vacanze", "dal 3 maggio al 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "tra il 3 maggio e il 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "dal 3 fino al 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "dal 1º al 5 maggio", "2027-05-01", "2027-05-05"),
        ("Vacanze", "dal primo al 5 maggio", "2027-05-01", "2027-05-05"),
        ("Vacanze", "dal lunedì 3 al mercoledì 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "dal 3 al 5 maggio 2027", "2027-05-03", "2027-05-05"),
        ("Vacanze", "dal 3 al 5 di maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "dal 3 al 10 agosto", "2027-08-03", "2027-08-10"),
        ("Vacanze", "dal 30 dicembre al 2 gennaio", "2026-12-30", "2027-01-02"),
        ("Vacanze", "dal 3 al 5 ottobre", "2026-10-03", "2026-10-05"),
        // A word that means "to" needs no opening word when the end names a month.
        ("Vacanze", "3 al 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "3 fino al 5 maggio", "2027-05-03", "2027-05-05"),
        ("Vacanze", "3 maggio al 5 maggio", "2027-05-03", "2027-05-05"),
      ], languages: ["it-IT"])
  }

  @Test("Beside Spanish, an Italian range is read whole with its opening word")
  func dateRangesBesideSpanish() {
    // Spanish reads "3 al 10 agosto" with no opening word, so it must not take
    // that text out of the middle of "dal 3 al 10 agosto".
    let lines: [DateRangeLine] = [
      ("Vacanze", "dal 3 al 10 agosto", "2027-08-03", "2027-08-10"),
      ("Vacanze", "dal 3 al 5 marzo", "2027-03-03", "2027-03-05"),
      ("Vacanze", "3 al 10 agosto", "2027-08-03", "2027-08-10"),
    ]
    expectDateRanges(lines, languages: ["it-IT", "es-ES"])
    expectDateRanges(lines, languages: ["ja-JP", "ko-KR", "fr-FR", "pt-BR", "es-ES", "it-IT"])
  }

  @Test("A range of days with no month is read where a day of the month alone is")
  func dateRangesWithoutAMonth() {
    // The 3rd has passed this month, so the days are October's.
    expectDateRanges(
      [
        ("Vacanze", "dal 3 al 10", "2026-10-03", "2026-10-10"),
        ("Vacanze", "tra il 3 e il 5", "2026-10-03", "2026-10-05"),
        ("Vacanze", "fra il 3 e il 5", "2026-10-03", "2026-10-05"),
      ], languages: ["it-IT"])

    let withDetail = parse("Ferie dal 3 al 10 con Marco")
    #expect(withDetail.title == "Ferie con Marco")
    #expect(withDetail.plannedDayOffset == captureDayOffset("2026-10-03"))
    #expect(withDetail.dueDayOffset == captureDayOffset("2026-10-10"))

    // Not before a word that goes on with the days, as for "il 3" alone.
    #expect(parse("Comprare dal 3 al 5 libri").dueDayOffset == nil)
    expectLinesUnread(["Leggere da 3 a 5 capitoli", "Viaggio 3-5 persone"], languages: ["it-IT"])
  }

  @Test("A range whose end is not after its start stays in the title whole")
  func declinedDateRanges() {
    expectLinesUnread(
      [
        "Vacanze dal 5 al 3 maggio", "Vacanze 5-3 maggio", "Vacanze tra il 5 e il 3 maggio",
        "Vacanze dal 3 al 31 aprile", "Vacanze dal 5 al 3", "Vacanze 5 al 3 maggio",
      ], languages: ["it-IT"])
  }

  @Test("Time ranges, weekday ranges, and counts are not date ranges")
  func nonDateRanges() {
    let dalle = parse("Riunione dalle 3 alle 4")
    #expect(dalle.startMinutes == 15 * 60)
    #expect(dalle.estimatedMinutes == 60)
    #expect(dalle.plannedDayOffset == nil)
    #expect(dalle.dueDayOffset == nil)
    #expect(dalle.phrases.map(\.text) == ["dalle 3 alle 4"])
    for text in ["Riunione tra le 3 e le 4", "Riunione da 3 a 5"] {
      let line = parse(text)
      #expect(line.startMinutes == 15 * 60, "\(text)")
      #expect(line.dueDayOffset == nil, "\(text)")
    }
    let weekdays = parse("Ferie dal lunedì al venerdì")
    #expect(weekdays.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"]))
    #expect(weekdays.dueDayOffset == nil)
    // Two days joined by "e" without tra are two days, not a range.
    #expect(parse("Pranzo il 3 e il 5").dueDayOffset == nil)
    #expect(parse("Pranzo 3 e 5 maggio").dueDayOffset == nil)
  }

  @Test("Due days")
  func dueDays() {
    let line = parse("Relazione entro venerdì")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Relazione")
    #expect(parse("Relazione per venerdì").dueDayOffset == 3)
    #expect(parse("Relazione entro domani").dueDayOffset == 1)
    #expect(parse("Relazione per domani").dueDayOffset == 1)
    #expect(parse("Relazione fino a venerdì").dueDayOffset == 3)
    #expect(parse("Relazione non oltre venerdì").dueDayOffset == 3)
    #expect(parse("Relazione entro il 5 ottobre").dueDayOffset == 13)
    #expect(parse("Relazione scade il 5 ottobre").dueDayOffset == 13)
    #expect(parse("Relazione scade il 5 ottobre").title == "Relazione")
    #expect(parse("Relazione scadenza: venerdì").dueDayOffset == 3)
    #expect(parse("Relazione scadenza: venerdì").title == "Relazione")
    #expect(parse("Relazione venerdì al più tardi").dueDayOffset == 3)
    #expect(parse("Relazione venerdì al più tardi").title == "Relazione")
    #expect(parse("Relazione entro il 15").dueDayOffset == 23)
    #expect(parse("Relazione fino al 15").dueDayOffset == 23)
    #expect(parse("Relazione per il 15").dueDayOffset == 23)
  }

  @Test("Clock times written with alle or ore are times")
  func times() {
    let line = parse("Chiamare Paolo alle 15 domani")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == nil)
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "Chiamare Paolo")
    #expect(line.phrases.map(\.text) == ["alle 15", "domani"])

    #expect(parse("Dentista alle 9:30").startMinutes == 9 * 60 + 30)
    #expect(parse("Dentista alle 9.30").startMinutes == 9 * 60 + 30)
    #expect(parse("Dentista alle 9.30").title == "Dentista")
    #expect(parse("Chiamare alle 9 e 30").startMinutes == 9 * 60 + 30)
    #expect(parse("Chiamare alle nove").startMinutes == 9 * 60)
    #expect(parse("Dentista ore 15").startMinutes == 15 * 60)
    #expect(parse("Dentista ore 15:30").startMinutes == 15 * 60 + 30)
    #expect(parse("Chiamare alle ore 15").startMinutes == 15 * 60)
    // From 1 to 6 o'clock a bare time is the afternoon, unless it has a zero.
    #expect(parse("Caffè alle 3").startMinutes == 15 * 60)
    #expect(parse("Treno alle 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Treno 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Chiamare verso le 6").startMinutes == 18 * 60)
    #expect(parse("Chiamare verso le 6").title == "Chiamare")
    #expect(parse("Disponibile dalle 8").startMinutes == 8 * 60)
    #expect(parse("Disponibile dalle 8").title == "Disponibile")
    #expect(parse("Chiamare alle 9 con Anna").startMinutes == 9 * 60)
    #expect(parse("Chiamare alle 9 con Anna").title == "Chiamare con Anna")
    #expect(parse("Chiamare alle 9 domani").plannedDayOffset == 1)
    #expect(parse("Chiamare 15:30").startMinutes == 15 * 60 + 30)
    // AM and PM after the hour name the same clock time.
    #expect(parse("Festa alle 3 pm").startMinutes == 15 * 60)
    #expect(parse("Chiamare alle 3:30 pm").startMinutes == 15 * 60 + 30)
    // A time said in words.
    #expect(parse("Riunione all'una").startMinutes == 13 * 60)
    #expect(parse("Riunione all’una e mezza").startMinutes == 13 * 60 + 30)
    #expect(parse("Riunione alle 3 e mezza").startMinutes == 15 * 60 + 30)
    #expect(parse("Riunione alle 3 e mezzo").startMinutes == 15 * 60 + 30)
    #expect(parse("Riunione alle 3 e un quarto").startMinutes == 15 * 60 + 15)
    #expect(parse("Riunione alle 4 meno un quarto").startMinutes == 15 * 60 + 45)
    #expect(parse("Riunione alle 3 in punto").startMinutes == 15 * 60)
    #expect(parse("Riunione alle 3 in punto").title == "Riunione")
  }

  @Test("A bare hour is a time only when no counted noun follows it")
  func countedNouns() {
    for text in ["Festa alle 3 amiche", "Chiamare alle 15 persone", "Chiamare alle 48"] {
      let line = parse(text)
      #expect(line.startMinutes == nil)
      #expect(line.title == text)
    }
  }

  @Test("An hour that names a deadline stays in the title")
  func deadlineHours() {
    for text in ["Relazione entro le 18", "Consegna entro le 18"] {
      let line = parse(text)
      #expect(line.startMinutes == nil)
      #expect(line.dueDayOffset == nil)
      #expect(line.title == text)
    }
  }

  @Test("Parts of the day turn an hour into the afternoon or the evening; di mattina keeps the morning")
  func timesOfDay() {
    // Di sera and del pomeriggio turn 3 into 15:00.
    #expect(parse("Chiamare alle 3 di sera").startMinutes == 15 * 60)
    let afternoon = parse("Caffè alle 3 del pomeriggio")
    #expect(afternoon.startMinutes == 15 * 60)
    #expect(afternoon.plannedDayOffset == nil)
    #expect(afternoon.title == "Caffè")
    #expect(parse("Festa 3 del pomeriggio").startMinutes == 15 * 60)
    #expect(parse("Festa 3 del pomeriggio").title == "Festa")
    #expect(parse("Cena alle 8 di sera").startMinutes == 20 * 60)
    #expect(parse("Cena alle 8 della sera").startMinutes == 20 * 60)
    // Di mattina and del mattino keep the morning.
    let morning = parse("Lezione alle 9 di mattina")
    #expect(morning.startMinutes == 9 * 60)
    #expect(morning.plannedDayOffset == nil)
    #expect(morning.title == "Lezione")
    #expect(parse("Chiamare alle 5 di mattina").startMinutes == 5 * 60)
    #expect(parse("Chiamare alle 3 del mattino").startMinutes == 3 * 60)
    #expect(parse("Pranzo alle 12 di mattina").startMinutes == 12 * 60)
    // A night hour from 1 to 4 comes after midnight, on the next day.
    let night = parse("Guardia alle 2 di notte")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(parse("Chiamare alle 11 di notte").startMinutes == 23 * 60)
    #expect(parse("Chiamare alle 11 di notte").plannedDayOffset == nil)
    #expect(parse("Pranzo a mezzogiorno").startMinutes == 12 * 60)
    #expect(parse("Pranzo a mezzogiorno").title == "Pranzo")
    #expect(parse("Pranzo mezzogiorno").startMinutes == 12 * 60)
    let midnight = parse("Fuochi d'artificio a mezzanotte")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    #expect(midnight.title == "Fuochi d'artificio")
    // The noun "mezzogiorno" is no time.
    #expect(parse("Il mezzogiorno d'Italia").startMinutes == nil)
    #expect(parse("Il mezzogiorno d'Italia").title == "Il mezzogiorno d'Italia")
  }

  @Test("Time ranges plan the start and the length")
  func ranges() {
    let line = parse("Riunione dalle 3 alle 4")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(line.title == "Riunione")
    #expect(parse("Riunione dalle 14 alle 16:30").startMinutes == 14 * 60)
    #expect(parse("Riunione dalle 14 alle 16:30").estimatedMinutes == 150)
    #expect(parse("Riunione dalle 9:30 alle 11").estimatedMinutes == 90)
    #expect(parse("Riunione dalle 15.00 alle 16.30").estimatedMinutes == 90)
    #expect(parse("Riunione dalle ore 9 alle ore 11").estimatedMinutes == 120)
    #expect(parse("Riunione dalle ore 9 alle ore 11").title == "Riunione")
    #expect(parse("Riunione dalle 3 alle 4 del pomeriggio").startMinutes == 15 * 60)
    #expect(parse("Riunione dalle 3 alle 4 del pomeriggio").estimatedMinutes == 60)
    #expect(parse("Riunione tra le 3 e le 4").startMinutes == 15 * 60)
    #expect(parse("Riunione tra le 3 e le 4").estimatedMinutes == 60)
    #expect(parse("Riunione tra le 3 e le 4 del pomeriggio").estimatedMinutes == 60)
    #expect(parse("Riunione da 3 a 4 con Anna").title == "Riunione con Anna")
    #expect(parse("Riunione da 3 a 4 con Anna").startMinutes == 15 * 60)
    #expect(parse("Guardia dalle 9 a mezzogiorno").startMinutes == 9 * 60)
    #expect(parse("Guardia dalle 9 a mezzogiorno").estimatedMinutes == 180)
    // A range with a dash is English's.
    #expect(parse("Atelier 14:00-16:30").startMinutes == 14 * 60)
    #expect(parse("Atelier 14:00-16:30").estimatedMinutes == 150)
    #expect(parse("Riunione 3-4 pm").estimatedMinutes == 60)
  }

  @Test("Two bare hours are a range only after dalle or da, or after tra with le, and before no counted noun")
  func bareRanges() {
    for text in ["Riunione tra 3 e 4", "Leggere da 3 a 5 capitoli"] {
      let line = parse(text)
      #expect(line.startMinutes == nil)
      #expect(line.estimatedMinutes == nil)
      #expect(line.title == text)
    }
  }

  @Test("Lengths")
  func lengths() {
    let line = parse("Leggere per 2 ore")
    #expect(line.estimatedMinutes == 120)
    #expect(line.startMinutes == nil)
    #expect(line.title == "Leggere")
    #expect(parse("Leggere per 2h").estimatedMinutes == 120)
    #expect(parse("Studiare durata 2 ore").estimatedMinutes == 120)
    #expect(parse("Studiare durata 2 ore").title == "Studiare")
    #expect(parse("Riunione di 2 ore").estimatedMinutes == 120)
    #expect(parse("Riunione di 2 ore").title == "Riunione")
    #expect(parse("Riunione di 2h").title == "Riunione")
    #expect(parse("Correre 1h30").estimatedMinutes == 90)
    #expect(parse("Correre 1h30").startMinutes == nil)
    #expect(parse("Correre 1h30min").estimatedMinutes == 90)
    #expect(parse("Correre 1,5 ore").estimatedMinutes == 90)
    #expect(parse("Pausa 30 min").estimatedMinutes == 30)
    #expect(parse("Pausa 30 minuti").title == "Pausa")
    #expect(parse("Studiare 2 ore").estimatedMinutes == 120)
    #expect(parse("Studiare due ore").estimatedMinutes == 120)
    #expect(parse("Studiare 2 ore e mezza").estimatedMinutes == 150)
    #expect(parse("Studiare 1 ora e 30").estimatedMinutes == 90)
    #expect(parse("Studiare 1 ora e 30 minuti").estimatedMinutes == 90)
    #expect(parse("Pisolino mezz'ora").estimatedMinutes == 30)
    #expect(parse("Pisolino mezz’ora").estimatedMinutes == 30)
    #expect(parse("Pisolino mezza ora").estimatedMinutes == 30)
    #expect(parse("Pisolino un'ora").estimatedMinutes == 60)
    #expect(parse("Pisolino un'ora e mezza").estimatedMinutes == 90)
    #expect(parse("Meditare un quarto d'ora").estimatedMinutes == 15)
    #expect(parse("Meditare un quarto d'ora").title == "Meditare")
    #expect(parse("Meditare tre quarti d'ora").estimatedMinutes == 45)
    // An amount after tra or ogni is a moment or an interval.
    for text in ["Uscire tra 2 ore", "Pastiglia ogni 8 ore"] {
      let line = parse(text)
      #expect(line.estimatedMinutes == nil)
      #expect(line.title == text)
    }
  }

  @Test("Repeats")
  func repeats() {
    let line = parse("Annaffiare le piante ogni giorno")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Annaffiare le piante")
    #expect(parse("Annaffiare le piante tutti i giorni").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(
      parse("Corso tutti i lunedì e giovedì").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(
      parse("Corso tutti i lunedì e i giovedì").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(parse("Corso tutti i lunedì e i giovedì").title == "Corso")
    #expect(parse("Corso ogni lunedì e giovedì").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(parse("Palestra ogni sabato").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(parse("Palestra tutte le domeniche").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(
      parse("Riunione un lunedì sì e uno no").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    // Italian counts a fortnight as fifteen days.
    #expect(parse("Bilancio ogni 15 giorni").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Bilancio ogni quindici giorni").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Medicina ogni 3 giorni").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("Fattura ogni tre mesi").recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3))
    #expect(parse("Pagare ogni mese").recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(parse("Affitto il 5 di ogni mese").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Affitto il 5 di ogni mese").title == "Affitto")
    #expect(parse("Affitto ogni mese il 5").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Affitto ogni 5 del mese").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Spazzatura un giorno sì e uno no").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("Spazzatura a giorni alterni").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("Spazzatura una settimana sì e una no").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Compleanno ogni anno").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("Compleanno tutti gli anni").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("Yoga ogni mattina").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(parse("Yoga tutte le mattine").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(parse("Annaffiare ogni sera").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(parse("Annaffiare ogni sera").plannedDayOffset == nil)
    let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
    #expect(parse("Riunione di squadra nei giorni feriali").recurrence == workdays)
    #expect(parse("Riunione di squadra ogni giorno lavorativo").recurrence == workdays)
    #expect(parse("Riunione di squadra dal lunedì al venerdì").recurrence == workdays)
    #expect(parse("Riunione di squadra dal lunedì al venerdì").title == "Riunione di squadra")
    let weekly = parse("Ogni settimana controllare la posta")
    #expect(weekly.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(weekly.title == "controllare la posta")
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective stays in the title")
  func cadenceWords() {
    let line = parse("Meditare quotidianamente")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Meditare")
    #expect(parse("Rapporto settimanalmente").recurrence == TaskRecurrenceRule(freq: .weekly))
    let report = parse("Rapporto settimanale")
    #expect(report.recurrence == nil)
    #expect(report.title == "Rapporto settimanale")
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Chiamare la banca priorità alta")
    #expect(line.priority == .p1)
    #expect(line.title == "Chiamare la banca")
    #expect(parse("Chiamare la banca priorita alta").priority == .p1)
    #expect(parse("Chiamare la banca alta priorità").priority == .p1)
    #expect(parse("Sistemare il garage bassa priorità").priority == .p3)
    #expect(parse("Ordinare le mail priorità media").priority == .p2)
    #expect(parse("Fattura urgente").priority == .p1)
    #expect(parse("Fattura urgente").title == "Fattura")
    #expect(parse("Urgente: chiamare l'idraulico").priority == .p1)
    #expect(parse("Urgente: chiamare l'idraulico").title == "chiamare l'idraulico")
  }

  @Test("Beside Italian, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    // Italian does not write a clock time with h, so English keeps "2h" as two hours.
    let hours = parse("Write the report 2h", languages: ["en", "it"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "it"]).estimatedMinutes == 20)
    // English words around a detail leave with it.
    let forHours = parse("Write the report for 2h", languages: ["en", "it"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "it"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "it"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "it"]).plannedDayOffset == 1)
    // English lines read the same with Italian beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon",
      "Clean the garage this weekend",
    ] {
      #expect(parse(text, languages: ["en", "it"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // Italian reads "weekend" only with its article, so an English "this weekend" is English's.
    let weekend = parse("Clean the garage this weekend", languages: ["en", "it"])
    #expect(weekend.plannedDayOffset == 4)
    #expect(weekend.title == "Clean the garage")
    // A line may mix both languages.
    let mixed = parse("Call mom domani at 3pm", languages: ["en", "it"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
  }

  @Test("Italian words are read only for a user who reads Italian")
  func languageGate() {
    let line = parse("Chiamare domani", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Chiamare domani")
    for languages in [["it"], ["it-IT"], ["it-CH"], ["it_IT"], ["en-US", "it-IT"]] {
      #expect(parse("Chiamare domani", languages: languages).plannedDayOffset == 1)
    }
    // Spanish words are not read for an Italian reader.
    #expect(parse("Llamar mañana", languages: ["it-IT"]).plannedDayOffset == nil)
  }
}
