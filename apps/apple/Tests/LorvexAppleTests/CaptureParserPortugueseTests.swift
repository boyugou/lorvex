import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["pt-BR"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Portuguese capture lines, read for a user whose languages include
/// Portuguese.
@Suite("Capture parser Portuguese")
struct CaptureParserPortugueseTests {
  @Test("Days, typed with or without accents")
  func days() {
    let line = parse("Ligar para a Ana amanhã")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Ligar para a Ana")
    #expect(line.phrases.map(\.text) == ["amanhã"])

    #expect(parse("Pagar a conta amanha").plannedDayOffset == 1)
    #expect(parse("Pagar a conta hoje").plannedDayOffset == 0)
    #expect(parse("Pagar a conta hoje").title == "Pagar a conta")
    #expect(parse("Dentista depois de amanhã").plannedDayOffset == 2)
    #expect(parse("Dentista depois de amanhã").title == "Dentista")
    #expect(parse("Faxina no fim de semana").plannedDayOffset == 4)
    #expect(parse("Faxina no próximo fim de semana").plannedDayOffset == 11)
    #expect(parse("Balanço na próxima semana").plannedDayOffset == 7)
    #expect(parse("Balanço semana que vem").plannedDayOffset == 7)
    #expect(parse("Retornar daqui a 3 dias").plannedDayOffset == 3)
    #expect(parse("Retornar em 2 semanas").plannedDayOffset == 14)
    #expect(parse("Retornar em 2 semanas").title == "Retornar")
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    #expect(parse("Reunião na sexta").plannedDayOffset == 3)
    #expect(parse("Reunião na sexta").title == "Reunião")
    #expect(parse("Reunião na sexta-feira").plannedDayOffset == 3)
    #expect(parse("Feira sábado").plannedDayOffset == 4)
    #expect(parse("Feira no domingo").plannedDayOffset == 5)
    // Today is Tuesday, so Tuesday alone is a week ahead and "nesta terça" today.
    #expect(parse("Mercado na terça").plannedDayOffset == 7)
    #expect(parse("Mercado nesta terça").plannedDayOffset == 0)
    #expect(parse("Pilates nesta sexta").plannedDayOffset == 3)
    #expect(parse("Pilates sexta que vem").plannedDayOffset == 10)
    #expect(parse("Pilates na próxima segunda").plannedDayOffset == 6)
    #expect(parse("Pilates na próxima segunda").title == "Pilates")
  }

  @Test("A weekday's short form counts alone only at the end, after a word that is not an article")
  func weekdayShortForms() {
    let line = parse("Reunião sexta")
    #expect(line.plannedDayOffset == 3)
    #expect(line.title == "Reunião")
    let ordinal = parse("Ler a segunda parte")
    #expect(ordinal.plannedDayOffset == nil)
    #expect(ordinal.title == "Ler a segunda parte")
    #expect(parse("Assistir a segunda").plannedDayOffset == nil)
    #expect(parse("Ler a segunda parte amanhã").plannedDayOffset == 1)
    #expect(parse("Ler a segunda parte amanhã").title == "Ler a segunda parte")
    // The full name is never an ordinal.
    #expect(parse("Segunda-feira reunião").plannedDayOffset == 6)
  }

  @Test("Evenings put a bare clock time at night")
  func evenings() {
    let line = parse("Jantar hoje à noite às 8h")
    #expect(line.plannedDayOffset == 0)
    #expect(line.startMinutes == 20 * 60)
    #expect(line.title == "Jantar")
    #expect(parse("Cinema amanhã à noite 21h").plannedDayOffset == 1)
    #expect(parse("Cinema amanhã à noite 21h").startMinutes == 21 * 60)
    #expect(parse("Ligar esta noite").plannedDayOffset == 0)
  }

  @Test("Dates written out, and a day of the month alone")
  func dates() {
    let line = parse("Festa 5 de outubro")
    #expect(line.plannedDayOffset == 13)
    #expect(line.title == "Festa")
    #expect(parse("Festa dia 5 de outubro").plannedDayOffset == 13)
    #expect(parse("Festa dia 5 de outubro").title == "Festa")
    #expect(parse("Fatura 1º de outubro").plannedDayOffset == 9)
    // The 5th of this month has passed, so "dia 5" is October's.
    #expect(parse("Aluguel dia 5").plannedDayOffset == 13)
    // A date already passed this year is next year's.
    #expect(parse("Balanço 5 de fevereiro").plannedDayOffset == 136)
    // A date in digits depends on the region, so it stays in the title.
    #expect(parse("Festa 5/10").plannedDayOffset == nil)
  }

  @Test("Due days")
  func dueDays() {
    let line = parse("Relatório até sexta")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Relatório")
    #expect(parse("Entregar para o dia 5").dueDayOffset == 13)
    #expect(parse("Entregar para o dia 5").title == "Entregar")
    #expect(parse("Pagar até a próxima semana").dueDayOffset == 7)
    #expect(parse("Imposto prazo: 5 de outubro").dueDayOffset == 13)
    #expect(parse("Imposto prazo: 5 de outubro").title == "Imposto")
  }

  @Test("Clock times written with h are times")
  func times() {
    let line = parse("Ligar às 15h amanhã")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == nil)
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "Ligar")
    #expect(line.phrases.map(\.text) == ["às 15h", "amanhã"])

    #expect(parse("Dentista 9h30").startMinutes == 9 * 60 + 30)
    #expect(parse("Dentista às 15h30min").startMinutes == 15 * 60 + 30)
    #expect(parse("Dentista às 15h30min").estimatedMinutes == nil)
    // From 1 to 6 o'clock a bare time is the afternoon, unless it has a zero.
    #expect(parse("Reunião 3h").startMinutes == 15 * 60)
    #expect(parse("Trem 06h10").startMinutes == 6 * 60 + 10)
    #expect(parse("Ligar por volta das 18h").startMinutes == 18 * 60)
    #expect(parse("Ligar por volta das 18h").title == "Ligar")
    #expect(parse("Livre a partir das 14h").startMinutes == 14 * 60)
    #expect(parse("Ligar às 3 horas").startMinutes == 15 * 60)
    #expect(parse("Ligar às 3 horas").estimatedMinutes == nil)
    // An hour that no clock shows stays in the title.
    #expect(parse("Entrega 48h").startMinutes == nil)
    #expect(parse("Entrega 48h").title == "Entrega 48h")
  }

  @Test("Parts of the day, noon, and midnight")
  func partsOfTheDay() {
    #expect(parse("Aula às 9 da manhã").startMinutes == 9 * 60)
    #expect(parse("Café às 3 da tarde").startMinutes == 15 * 60)
    #expect(parse("Café às 3 da tarde").title == "Café")
    #expect(parse("Jantar às 8 da noite").startMinutes == 20 * 60)
    #expect(parse("Plantão às 2 da madrugada").startMinutes == 2 * 60)
    #expect(parse("Almoço ao meio-dia").startMinutes == 12 * 60)
    #expect(parse("Almoço ao meio-dia").title == "Almoço")
    #expect(parse("Almoço meio-dia e meia").startMinutes == 12 * 60 + 30)
    let midnight = parse("Fogos à meia-noite")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    #expect(midnight.title == "Fogos")
  }

  @Test("An hour that may be a time or a length, or a deadline, stays in the title")
  func ambiguousHours() {
    let meeting = parse("Reunião de 2h")
    #expect(meeting.startMinutes == nil)
    #expect(meeting.estimatedMinutes == nil)
    #expect(meeting.title == "Reunião de 2h")
    let deadline = parse("Entregar até às 18h")
    #expect(deadline.startMinutes == nil)
    #expect(deadline.title == "Entregar até às 18h")
    #expect(parse("Entregar até 18h").startMinutes == nil)
  }

  @Test("Time ranges plan the start and the length")
  func ranges() {
    let line = parse("Reunião das 14h às 16h")
    #expect(line.startMinutes == 14 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.title == "Reunião")
    #expect(parse("Aula de 14h a 16h").estimatedMinutes == 120)
    #expect(parse("Oficina 14h-16h30").estimatedMinutes == 150)
    #expect(parse("Plantão entre 14h e 16h").startMinutes == 14 * 60)
    #expect(parse("Plantão entre 14h e 16h").estimatedMinutes == 120)
    #expect(parse("Plantão das 9h ao meio-dia").startMinutes == 9 * 60)
    #expect(parse("Plantão das 9h ao meio-dia").estimatedMinutes == 180)
    // "E" names two times unless entre opens the range; the first counts.
    let twoTimes = parse("Ligar às 14h e 16h")
    #expect(twoTimes.startMinutes == 14 * 60)
    #expect(twoTimes.estimatedMinutes == nil)
  }

  @Test("Lengths")
  func lengths() {
    let line = parse("Ler por 2h")
    #expect(line.estimatedMinutes == 120)
    #expect(line.startMinutes == nil)
    #expect(line.title == "Ler")
    #expect(parse("Ler durante 1h30").estimatedMinutes == 90)
    #expect(parse("Corrida 1h30min").estimatedMinutes == 90)
    #expect(parse("Corrida 1h30min").startMinutes == nil)
    #expect(parse("Corrida 1,5 h").estimatedMinutes == 90)
    #expect(parse("Pausa 30 min").estimatedMinutes == 30)
    #expect(parse("Pausa 30 minutos").title == "Pausa")
    #expect(parse("Estudar 2 horas").estimatedMinutes == 120)
    #expect(parse("Estudar 2 horas e meia").estimatedMinutes == 150)
    #expect(parse("Estudar 1 hora e 30 minutos").estimatedMinutes == 90)
    #expect(parse("Cochilo meia hora").estimatedMinutes == 30)
    #expect(parse("Cochilo uma hora e meia").estimatedMinutes == 90)
    #expect(parse("Meditar um quarto de hora").estimatedMinutes == 15)
    #expect(parse("Meditar um quarto de hora").title == "Meditar")
    // An amount after em is a moment, not a length.
    #expect(parse("Sair em 2 horas").estimatedMinutes == nil)
  }

  @Test("Repeats")
  func repeats() {
    let line = parse("Academia toda segunda")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]))
    #expect(line.title == "Academia")
    #expect(
      parse("Inglês todas as segundas e quartas").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE"]))
    #expect(parse("Feira aos sábados").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(parse("Feira aos sábados").title == "Feira")
    #expect(parse("Missa nos domingos").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(parse("Remédio a cada 3 dias").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    // Portuguese counts a fortnight as fifteen days.
    #expect(parse("Faxina a cada 15 dias").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Faxina a cada quinze dias").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Reunião de 2 em 2 semanas").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Aluguel todo dia 5").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Aluguel todo dia 5").title == "Aluguel")
    #expect(parse("Água dia sim, dia não").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("Lixo semana sim, semana não").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Aniversário todo ano").recurrence == TaskRecurrenceRule(freq: .yearly))
    let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
    #expect(parse("Ponto nos dias úteis").recurrence == workdays)
    #expect(parse("Ponto de segunda a sexta").recurrence == workdays)
    #expect(parse("Ponto de segunda a sexta").title == "Ponto")
  }

  @Test("Weekdays in the plural after às or nas repeat at the end of the line")
  func habitualWeekdays() {
    let line = parse("Inglês às terças e quintas")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(line.title == "Inglês")
    #expect(parse("Futebol nas quartas").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["WE"]))
    #expect(
      parse("Feira às sextas e aos sábados").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR", "SA"]))
    // A time is read first, so the weekdays still end the line.
    let timed = parse("Inglês às terças às 19h")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    #expect(timed.startMinutes == 19 * 60)
    // Before another word the plural is an ordinal.
    let ordinal = parse("Pedir as segundas vias")
    #expect(ordinal.recurrence == nil)
    #expect(ordinal.title == "Pedir as segundas vias")
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective stays in the title")
  func cadenceWords() {
    let line = parse("Meditar diariamente")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Meditar")
    let report = parse("Relatório semanal")
    #expect(report.recurrence == nil)
    #expect(report.title == "Relatório semanal")
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Ligar para o banco prioridade alta")
    #expect(line.priority == .p1)
    #expect(line.title == "Ligar para o banco")
    #expect(parse("Arrumar a garagem baixa prioridade").priority == .p3)
    #expect(parse("Organizar e-mails prioridade média").priority == .p2)
    #expect(parse("Fatura urgente").priority == .p1)
    #expect(parse("Fatura urgente").title == "Fatura")
    #expect(parse("Urgente: ligar para o encanador").priority == .p1)
    #expect(parse("Urgente: ligar para o encanador").title == "ligar para o encanador")
  }

  @Test("Beside Portuguese, English leaves an hour written with h to Portuguese")
  func hoursBesideEnglish() {
    let both = parse("Write the report 2h", languages: ["en", "pt"])
    #expect(both.startMinutes == 14 * 60)
    #expect(both.estimatedMinutes == nil)
  }

  @Test("Portuguese words are read only for a user who reads Portuguese")
  func languageGate() {
    let line = parse("Ligar amanhã", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Ligar amanhã")
    #expect(parse("Ligar amanhã", languages: ["pt-PT"]).plannedDayOffset == 1)
  }
}
