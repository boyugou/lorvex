import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["es-ES"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])

/// Spanish capture lines, read for a user whose languages include Spanish.
@Suite("Capture parser Spanish")
struct CaptureParserSpanishTests {
  @Test("Days, typed with or without accents")
  func days() {
    let line = parse("Llamar a Pablo mañana")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Llamar a Pablo")
    #expect(line.phrases.map(\.text) == ["mañana"])

    #expect(parse("Dentista manana").plannedDayOffset == 1)
    #expect(parse("Dentista hoy").plannedDayOffset == 0)
    #expect(parse("Dentista hoy").title == "Dentista")
    #expect(parse("Entregar pasado mañana").plannedDayOffset == 2)
    #expect(parse("Entregar pasado mañana").title == "Entregar")
    #expect(parse("Pagar PASADO MAÑANA").plannedDayOffset == 2)
    #expect(parse("Limpieza el fin de semana").plannedDayOffset == 4)
    #expect(parse("Limpieza este fin de semana").plannedDayOffset == 4)
    #expect(parse("Limpieza el próximo fin de semana").plannedDayOffset == 11)
    #expect(parse("Limpieza el próximo fin de semana").title == "Limpieza")
    #expect(parse("Balance la próxima semana").plannedDayOffset == 7)
    #expect(parse("Balance la semana que viene").plannedDayOffset == 7)
    #expect(parse("Balance la semana que viene").title == "Balance")
    #expect(parse("Volver a llamar en 3 días").plannedDayOffset == 3)
    #expect(parse("Volver a llamar dentro de 3 días").plannedDayOffset == 3)
    #expect(parse("Volver a llamar dentro de una semana").plannedDayOffset == 7)
    #expect(parse("Volver a llamar dentro de una semana").title == "Volver a llamar")
    #expect(parse("Enviar presupuesto desde mañana").plannedDayOffset == 1)
    #expect(parse("Enviar presupuesto desde mañana").title == "Enviar presupuesto")
    #expect(parse("Reunión hoy mismo").plannedDayOffset == 0)
  }

  @Test("Mañana is tomorrow alone, and the morning after an hour or after por la")
  func mañana() {
    // Alone it is tomorrow.
    #expect(parse("Llamar mañana").plannedDayOffset == 1)

    // After an hour with "de la" it is the morning: 9 AM, and no day.
    let morning = parse("Clase a las 9 de la mañana")
    #expect(morning.startMinutes == 9 * 60)
    #expect(morning.plannedDayOffset == nil)
    #expect(morning.title == "Clase")
    #expect(morning.phrases.map(\.text) == ["a las 9 de la mañana"])

    // "Mañana por la mañana" is tomorrow morning: the day, and no time.
    let tomorrowMorning = parse("Clase mañana por la mañana")
    #expect(tomorrowMorning.plannedDayOffset == 1)
    #expect(tomorrowMorning.startMinutes == nil)
    #expect(tomorrowMorning.title == "Clase")
    let timed = parse("Clase mañana por la mañana a las 9")
    #expect(timed.plannedDayOffset == 1)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Clase")
    let both = parse("Clase mañana a las 9 de la mañana")
    #expect(both.plannedDayOffset == 1)
    #expect(both.startMinutes == 9 * 60)
    #expect(both.phrases.map(\.text) == ["mañana", "a las 9 de la mañana"])
    #expect(parse("Clase a las 9 mañana").plannedDayOffset == 1)
    #expect(parse("Clase a las 9 mañana").startMinutes == 9 * 60)
    #expect(parse("Estudiar mañana por la tarde").plannedDayOffset == 1)

    // The morning as a noun names no day.
    for text in ["Hacer yoga por la mañana", "Turno de mañana", "La reunión de mañana"] {
      let line = parse(text)
      #expect(line.plannedDayOffset == nil)
      #expect(line.title == text)
    }
    // "Esta mañana" is today; "cada mañana" repeats every day.
    #expect(parse("Reunión esta mañana").plannedDayOffset == 0)
    let daily = parse("Hacer yoga cada mañana")
    #expect(daily.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(daily.plannedDayOffset == nil)
    #expect(daily.title == "Hacer yoga")
    #expect(parse("Yoga todas las mañanas").recurrence == TaskRecurrenceRule(freq: .daily))
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    #expect(parse("Piscina el viernes").plannedDayOffset == 3)
    #expect(parse("Piscina el viernes").title == "Piscina")
    #expect(parse("Piscina viernes").plannedDayOffset == 3)
    #expect(parse("Piscina el miércoles").plannedDayOffset == 1)
    #expect(parse("Piscina el miercoles").plannedDayOffset == 1)
    #expect(parse("Piscina el sábado").plannedDayOffset == 4)
    // Today is Tuesday, so Tuesday alone is a week ahead and "este martes" today.
    #expect(parse("Mercado el martes").plannedDayOffset == 7)
    #expect(parse("Mercado este martes").plannedDayOffset == 0)
    #expect(parse("Piscina este viernes").plannedDayOffset == 3)
    #expect(parse("Piscina el próximo viernes").plannedDayOffset == 10)
    #expect(parse("Piscina viernes que viene").plannedDayOffset == 10)
    #expect(parse("Piscina el próximo lunes").plannedDayOffset == 6)
    #expect(parse("Piscina el próximo lunes").title == "Piscina")
  }

  @Test("El lunes is the coming Monday, while los lunes and cada lunes repeat")
  func habitualWeekdays() {
    let coming = parse("Reunión el lunes")
    #expect(coming.plannedDayOffset == 6)
    #expect(coming.recurrence == nil)

    let habit = parse("Deporte los lunes")
    #expect(habit.recurrence == monday)
    #expect(habit.plannedDayOffset == nil)
    #expect(habit.title == "Deporte")
    #expect(parse("Deporte cada lunes").recurrence == monday)
    #expect(parse("Deporte todos los lunes").recurrence == monday)
    #expect(parse("Misa los domingos").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(
      parse("Clase los martes y los jueves").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    // A time is read first, so the plural still ends the line.
    let timed = parse("Reunión los lunes a las 9")
    #expect(timed.recurrence == monday)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Reunión")
  }

  @Test("The article forms of a weekday stay in the title inside ordinary text")
  func weekdayArticleGuards() {
    for text in [
      "Los lunes de agosto", "Tareas los lunes por la mañana", "La reunión del lunes", "Reunión de lunes",
      "Reunión el lunes pasado", "Llamar a Domingo",
    ] {
      let line = parse(text)
      #expect(line.plannedDayOffset == nil)
      #expect(line.recurrence == nil)
      #expect(line.title == text)
    }
    // A capitalized Domingo that opens the line is the day.
    let sunday = parse("Domingo comida familiar")
    #expect(sunday.plannedDayOffset == 5)
    #expect(sunday.title == "comida familiar")
  }

  @Test("Evenings put a bare clock time at night")
  func evenings() {
    let line = parse("Cenar hoy por la noche a las 8")
    #expect(line.plannedDayOffset == 0)
    #expect(line.startMinutes == 20 * 60)
    #expect(line.title == "Cenar")
    #expect(parse("Cenar esta noche a las 8").startMinutes == 20 * 60)
    #expect(parse("Película mañana por la noche a las 9").plannedDayOffset == 1)
    #expect(parse("Película mañana por la noche a las 9").startMinutes == 21 * 60)
    #expect(parse("Cena el viernes por la noche a las 8").plannedDayOffset == 3)
    #expect(parse("Cena el viernes por la noche a las 8").startMinutes == 20 * 60)
    let afternoon = parse("Reunión esta tarde")
    #expect(afternoon.plannedDayOffset == 0)
    #expect(afternoon.startMinutes == nil)
    #expect(afternoon.title == "Reunión")
  }

  @Test("Dates written out, and a day of the month alone")
  func dates() {
    let line = parse("Fiesta el 5 de octubre")
    #expect(line.plannedDayOffset == 13)
    #expect(line.title == "Fiesta")
    #expect(parse("Fiesta 5 de octubre").plannedDayOffset == 13)
    #expect(parse("Fiesta lunes 5 de octubre").plannedDayOffset == 13)
    #expect(parse("Fiesta lunes 5 de octubre").title == "Fiesta")
    #expect(parse("Factura 1º de octubre").plannedDayOffset == 9)
    #expect(parse("Factura el primero de octubre").plannedDayOffset == 9)
    #expect(parse("Viaje 5 oct.").plannedDayOffset == 13)
    #expect(parse("Fiesta 5 de octubre de 2027").plannedDayOffset == 378)
    // The 5th of this month has passed, so "el 5" and "día 5" are October's.
    #expect(parse("Alquiler el día 5").plannedDayOffset == 13)
    #expect(parse("Alquiler el 5").plannedDayOffset == 13)
    #expect(parse("Alquiler día 5").title == "Alquiler")
    #expect(parse("Llamar el 15 con Ana").plannedDayOffset == 23)
    #expect(parse("Llamar el 15 con Ana").title == "Llamar con Ana")
    // A date already passed this year is next year's.
    #expect(parse("Balance 5 de febrero").plannedDayOffset == 136)
    // A date in digits depends on the region, so it stays in the title.
    #expect(parse("Fiesta 5/10").plannedDayOffset == nil)
    #expect(
      LorvexCaptureParser.parse("Fiesta el 5 de octubre", lists: [], todayWeekday: 3, languages: ["es"])
        .plannedDayOffset == nil)
  }

  @Test("A day of the month alone counts only at the end or before a word that can follow a date")
  func bareDayOfTheMonth() {
    for text in ["Comprar el 3 de la lista", "Comprar 2 hermanas el 15 libros"] {
      let line = parse(text)
      #expect(line.plannedDayOffset == nil)
      #expect(line.title == text)
    }
    #expect(parse("Entregar para el 3 de la lista").dueDayOffset == nil)
    #expect(parse("Entregar para 15 personas").dueDayOffset == nil)
  }

  @Test("Due days")
  func dueDays() {
    let line = parse("Informe para el viernes")
    #expect(line.dueDayOffset == 3)
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Informe")
    #expect(parse("Informe antes del viernes").dueDayOffset == 3)
    #expect(parse("Informe hasta mañana").dueDayOffset == 1)
    #expect(parse("Informe para hoy").dueDayOffset == 0)
    #expect(parse("Pagar alquiler antes del 5 de octubre").dueDayOffset == 13)
    #expect(parse("Pagar alquiler vence el 5 de octubre").dueDayOffset == 13)
    #expect(parse("Pagar alquiler vence el 5 de octubre").title == "Pagar alquiler")
    #expect(parse("Declaración fecha límite: 5 de octubre").dueDayOffset == 13)
    #expect(parse("Declaración fecha límite: 5 de octubre").title == "Declaración")
    #expect(parse("Informe el viernes a más tardar").dueDayOffset == 3)
    #expect(parse("Informe el viernes a más tardar").title == "Informe")
    #expect(parse("Informe a más tardar el viernes").dueDayOffset == 3)
    #expect(parse("Entregar para el 15").dueDayOffset == 23)
  }

  @Test("Clock times written with a las are times")
  func times() {
    let line = parse("Llamar a Pablo a las 15:00 mañana")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == nil)
    #expect(line.plannedDayOffset == 1)
    #expect(line.title == "Llamar a Pablo")
    #expect(line.phrases.map(\.text) == ["a las 15:00", "mañana"])

    #expect(parse("Dentista a las 9:30").startMinutes == 9 * 60 + 30)
    #expect(parse("Dentista a las 9 y 30").startMinutes == 9 * 60 + 30)
    #expect(parse("Dentista a las nueve").startMinutes == 9 * 60)
    // From 1 to 6 o'clock a bare time is the afternoon, unless it has a zero.
    #expect(parse("Café a las 3").startMinutes == 15 * 60)
    #expect(parse("Tren a las 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Tren 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("Llamar sobre las 6").startMinutes == 18 * 60)
    #expect(parse("Llamar sobre las 6").title == "Llamar")
    #expect(parse("Disponible desde las 8").startMinutes == 8 * 60)
    #expect(parse("Disponible desde las 8").title == "Disponible")
    #expect(parse("Café a las 3 con Ana").startMinutes == 15 * 60)
    #expect(parse("Café a las 3 con Ana").title == "Café con Ana")
    // An h, hs, hrs, or horas after the hour names the same clock time.
    #expect(parse("Fiesta a las 15 h").startMinutes == 15 * 60)
    #expect(parse("Fiesta a las 15:30 hrs").startMinutes == 15 * 60 + 30)
    #expect(parse("Fiesta a las 15:30 hrs").title == "Fiesta")
    #expect(parse("Fiesta a las 15 horas").startMinutes == 15 * 60)
    #expect(parse("Fiesta a las 15 horas").estimatedMinutes == nil)
    #expect(parse("Fiesta a las 3 pm").startMinutes == 15 * 60)
    // A time said in words.
    #expect(parse("Café a la una").startMinutes == 13 * 60)
    #expect(parse("Café a la una y media").startMinutes == 13 * 60 + 30)
    #expect(parse("Café a las 3 y media").startMinutes == 15 * 60 + 30)
    #expect(parse("Café a las 3 y cuarto").startMinutes == 15 * 60 + 15)
    #expect(parse("Café a las 4 menos cuarto").startMinutes == 15 * 60 + 45)
    #expect(parse("Café a las 3 en punto").startMinutes == 15 * 60)
    #expect(parse("Café a las 3 en punto").title == "Café")
  }

  @Test("A bare hour is a time only when no counted noun follows it")
  func countedNouns() {
    for text in ["Cena a las 3 hermanas", "Llamar a las 15 personas", "Llamar a las 48"] {
      let line = parse(text)
      #expect(line.startMinutes == nil)
      #expect(line.title == text)
    }
    #expect(parse("Llamar a las 9").startMinutes == 9 * 60)
    #expect(parse("Llamar a las 9 con Ana").startMinutes == 9 * 60)
    #expect(parse("Llamar a las 9 mañana").plannedDayOffset == 1)
  }

  @Test("An hour that names a deadline stays in the title")
  func deadlineHours() {
    for text in ["Cita antes de las 6", "Entregar hasta las 6", "Entregar para las 6"] {
      let line = parse(text)
      #expect(line.startMinutes == nil)
      #expect(line.dueDayOffset == nil)
      #expect(line.title == text)
    }
  }

  @Test("Parts of the day turn an hour into the afternoon or the evening; de la mañana keeps the morning")
  func partsOfTheDay() {
    #expect(parse("Clase a las 9 de la mañana").startMinutes == 9 * 60)
    #expect(parse("Llamar a las 12 de la mañana").startMinutes == 12 * 60)
    let afternoon = parse("Clase a las 3 de la tarde")
    #expect(afternoon.startMinutes == 15 * 60)
    #expect(afternoon.plannedDayOffset == nil)
    #expect(afternoon.title == "Clase")
    #expect(parse("Fiesta 3 de la tarde").startMinutes == 15 * 60)
    #expect(parse("Fiesta 3 de la tarde").title == "Fiesta")
    #expect(parse("Llamar a las 12 del mediodía").startMinutes == 12 * 60)
    #expect(parse("Cena a las 8 de la noche").startMinutes == 20 * 60)
    #expect(parse("Cena a las 11 de la noche").startMinutes == 23 * 60)
    // The small hours of the night come after midnight, on the next day.
    let night = parse("Guardia a las 3 de la noche")
    #expect(night.startMinutes == 3 * 60)
    #expect(night.plannedDayOffset == 1)
    // "De la madrugada" is the small hours of the same day.
    let dawn = parse("Guardia a las 2 de la madrugada")
    #expect(dawn.startMinutes == 2 * 60)
    #expect(dawn.plannedDayOffset == nil)
    #expect(parse("Almuerzo al mediodía").startMinutes == 12 * 60)
    #expect(parse("Almuerzo al mediodía").title == "Almuerzo")
    #expect(parse("Almuerzo a mediodía").startMinutes == 12 * 60)
    #expect(parse("Almuerzo mediodía").startMinutes == 12 * 60)
    let midnight = parse("Fuegos artificiales a medianoche")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    #expect(midnight.title == "Fuegos artificiales")
    // The noun "mediodía" is no time, and an hour no clock shows stays in the title.
    #expect(parse("Menú del mediodía").startMinutes == nil)
    #expect(parse("Menú del mediodía").title == "Menú del mediodía")
    #expect(parse("Llamar a las 0 de la noche").startMinutes == nil)
  }

  @Test("Time ranges plan the start and the length")
  func ranges() {
    let line = parse("Reunión de 3 a 4")
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 60)
    #expect(line.title == "Reunión")
    #expect(parse("Reunión de 14:00 a 16:30").startMinutes == 14 * 60)
    #expect(parse("Reunión de 14:00 a 16:30").estimatedMinutes == 150)
    #expect(parse("Reunión de las 3 a las 4 de la tarde").startMinutes == 15 * 60)
    #expect(parse("Reunión de las 3 a las 4 de la tarde").estimatedMinutes == 60)
    #expect(parse("Reunión entre las 3 y las 4").estimatedMinutes == 60)
    #expect(parse("Reunión entre las 3 y las 4").title == "Reunión")
    #expect(parse("Reunión de 3 a 4 con Ana").title == "Reunión con Ana")
    #expect(parse("Guardia desde las 9 hasta el mediodía").startMinutes == 9 * 60)
    #expect(parse("Guardia desde las 9 hasta el mediodía").estimatedMinutes == 180)
    // An h after the end names the hour, so "9 a 14 h" is a range, not 14 hours.
    #expect(parse("Horario de 9 a 14 h").startMinutes == 9 * 60)
    #expect(parse("Horario de 9 a 14 h").estimatedMinutes == 300)
    #expect(parse("Horario de 9 a 14 h").title == "Horario")
    // A range with a dash is English's.
    #expect(parse("Taller 14:00-16:30").startMinutes == 14 * 60)
    #expect(parse("Taller 14:00-16:30").estimatedMinutes == 150)
  }

  @Test("Two bare hours are a range only after de or desde, or after entre with las, and before no counted noun")
  func bareRanges() {
    for text in ["Reunión entre 3 y 4", "Leer de 3 a 5 capítulos", "Taller de 3 a 5 páginas"] {
      let line = parse(text)
      #expect(line.startMinutes == nil)
      #expect(line.estimatedMinutes == nil)
      #expect(line.title == text)
    }
    // El before a number names a day of the month, never an hour.
    for text in ["Vacaciones entre el 3 y el 10 de agosto", "Feria desde el 3 hasta el 10"] {
      let line = parse(text)
      #expect(line.startMinutes == nil, "\(text)")
      #expect(line.estimatedMinutes == nil, "\(text)")
    }
  }

  @Test("Lengths")
  func lengths() {
    let line = parse("Leer durante 2 horas")
    #expect(line.estimatedMinutes == 120)
    #expect(line.startMinutes == nil)
    #expect(line.title == "Leer")
    #expect(parse("Leer por 2h").estimatedMinutes == 120)
    #expect(parse("Leer por 2h").title == "Leer")
    #expect(parse("Reunión de 2 horas").estimatedMinutes == 120)
    #expect(parse("Reunión de 2 horas").title == "Reunión")
    #expect(parse("Correr 1h30").estimatedMinutes == 90)
    #expect(parse("Correr 1h30").startMinutes == nil)
    #expect(parse("Correr 1h30min").estimatedMinutes == 90)
    #expect(parse("Correr 1,5 horas").estimatedMinutes == 90)
    #expect(parse("Pausa 30 min").estimatedMinutes == 30)
    #expect(parse("Pausa 30 minutos").title == "Pausa")
    #expect(parse("Estudiar 2 horas").estimatedMinutes == 120)
    #expect(parse("Estudiar 2 horas y media").estimatedMinutes == 150)
    #expect(parse("Estudiar 1 hora y 30 minutos").estimatedMinutes == 90)
    #expect(parse("Siesta media hora").estimatedMinutes == 30)
    #expect(parse("Siesta una hora y media").estimatedMinutes == 90)
    #expect(parse("Meditar un cuarto de hora").estimatedMinutes == 15)
    #expect(parse("Meditar un cuarto de hora").title == "Meditar")
    #expect(parse("Meditar tres cuartos de hora").estimatedMinutes == 45)
    // An amount after en, dentro de, antes de, or cada is a moment or an interval.
    for text in ["Salir en 2 horas", "Salir dentro de 2 horas", "Pastilla cada 8 horas", "Entregar antes de 2 horas"] {
      let line = parse(text)
      #expect(line.estimatedMinutes == nil)
      #expect(line.title == text)
    }
  }

  @Test("Repeats")
  func repeats() {
    let line = parse("Regar las plantas todos los días")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Regar las plantas")
    #expect(parse("Regar las plantas cada día").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(parse("Deporte a diario").recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(
      parse("Clase todos los lunes y jueves").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(parse("Clase todos los lunes y los jueves").title == "Clase")
    #expect(parse("Clase cada lunes y jueves").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(
      parse("Reunión cada dos lunes").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    // Spanish counts a fortnight as fifteen days.
    #expect(parse("Balance cada 15 días").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Balance cada quince días").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Medicina cada 3 días").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    #expect(parse("Factura cada tres meses").recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3))
    #expect(parse("Pagar cada mes").recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(parse("Alquiler el 5 de cada mes").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Alquiler el 5 de cada mes").title == "Alquiler")
    #expect(parse("Alquiler el día 5 de cada mes").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Alquiler cada mes el 5").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [5]))
    #expect(parse("Basura un día sí y otro no").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    #expect(parse("Basura una semana sí y otra no").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2))
    #expect(parse("Cumpleaños cada año").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("Cumpleaños todos los años").recurrence == TaskRecurrenceRule(freq: .yearly))
    let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
    #expect(parse("Punto de equipo entre semana").recurrence == workdays)
    #expect(parse("Punto de equipo todos los días laborables").recurrence == workdays)
    #expect(parse("Punto de equipo de lunes a viernes").recurrence == workdays)
    #expect(parse("Punto de equipo de lunes a viernes").title == "Punto de equipo")
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective stays in the title")
  func cadenceWords() {
    let line = parse("Meditar diariamente")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "Meditar")
    #expect(parse("Informe semanalmente").recurrence == TaskRecurrenceRule(freq: .weekly))
    let report = parse("Informe semanal")
    #expect(report.recurrence == nil)
    #expect(report.title == "Informe semanal")
  }

  @Test("Priorities")
  func priorities() {
    let line = parse("Llamar al banco prioridad alta")
    #expect(line.priority == .p1)
    #expect(line.title == "Llamar al banco")
    #expect(parse("Ordenar el garaje prioridad baja").priority == .p3)
    #expect(parse("Ordenar el garaje baja prioridad").priority == .p3)
    #expect(parse("Ordenar correos prioridad media").priority == .p2)
    #expect(parse("Factura urgente").priority == .p1)
    #expect(parse("Factura urgente").title == "Factura")
    #expect(parse("Urgente: llamar al fontanero").priority == .p1)
    #expect(parse("Urgente: llamar al fontanero").title == "llamar al fontanero")
    // Without a colon or comma an opening "urgente" is a title word.
    #expect(parse("Urgente llamar").priority == nil)
  }

  @Test("Beside Spanish, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    // Spanish does not write a clock time with h, so English keeps "2h" as two hours.
    let hours = parse("Write the report 2h", languages: ["en", "es"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "es"]).estimatedMinutes == 20)
    // English words around a detail leave with it.
    let forHours = parse("Write the report for 2h", languages: ["en", "es"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "es"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "es"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "es"]).plannedDayOffset == 1)
    // English lines read the same with Spanish beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon",
    ] {
      #expect(parse(text, languages: ["en", "es"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom mañana at 3pm", languages: ["en", "es"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
  }

  @Test("Spanish words are read only for a user who reads Spanish")
  func languageGate() {
    let line = parse("Llamar mañana", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Llamar mañana")
    for languages in [["es"], ["es-MX"], ["es-419"], ["es_ES"], ["en-US", "es-US"]] {
      #expect(parse("Llamar mañana", languages: languages).plannedDayOffset == 1)
    }
    // Italian words are not read for a Spanish reader.
    #expect(parse("Chiamare domani", languages: ["es-ES"]).plannedDayOffset == nil)
  }
}
