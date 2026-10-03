import Foundation

extension LorvexCaptureVocabulary {
  /// Portuguese, read for a user who reads Portuguese, as written in Brazil
  /// and in Portugal. A word needs a boundary of Latin letters and digits on
  /// both sides, as in English, and accents may be left out ("amanha",
  /// "sabado", "as 15h").
  ///
  /// Portuguese writes a clock time with the letter h, from 0h to 23h ("15h",
  /// "15h30"), so an hour count written that way is a time. A length says so
  /// with por or durante ("por 2h"), with minutes ("1h30min"), or with a word
  /// ("2 horas"). An hour after "de" with no end can be either ("reunião de
  /// 2h"), so it stays in the title, as does an hour after até, which names a
  /// deadline rather than a time to start.
  ///
  /// - Day: hoje, hoje à noite, esta noite, amanhã, amanhã à noite, depois de
  ///   amanhã, the weekday names (segunda-feira or segunda … sexta, sábado,
  ///   domingo; alone, after na, nesta, or este, or with próxima or que vem),
  ///   próxima semana, semana que vem, fim de semana, próximo fim de semana,
  ///   daqui a 3 dias, em 3 dias, each maybe after de, desde, or a partir de;
  ///   a date: 5 de outubro, dia 5 de outubro, 1º de outubro, 5 de outubro de
  ///   2027, or dia 5 for the coming 5th. A weekday alone means the next such
  ///   day, a full week ahead when it names today; after nesta or este it is
  ///   this week's, and with próxima or que vem next week's, weeks starting
  ///   on Monday. A weekday's short form ("segunda", "sexta") is also an
  ///   ordinal ("a segunda parte"), so with no word introducing it, it counts
  ///   only at the end of the line after a word that is not an article. Hoje
  ///   à noite, esta noite, and amanhã à noite are evenings. A date written in
  ///   digits ("5/10") is not read, since the order of its day and month
  ///   depends on the region.
  /// - Date range: de 3 a 5 de maio, de 3 até 5 de maio, de 3 de maio a 5 de
  ///   maio, de 30 de maio a 2 de junho, do dia 3 ao dia 5 de maio, entre 3 e 5
  ///   de maio, entre os dias 3 e 5 de maio, entre o dia 3 e o dia 5 de maio,
  ///   3-5 de maio, 3 a 5 de maio, each maybe with a year after the end ("de 3
  ///   a 5 de maio de 2027"). The first day is the planned day and the last
  ///   the due day, so another day phrase stays in the title. A day written
  ///   without its month takes the month of the end; the end must be after the
  ///   start ("de 5 a 3 de maio" stays in the title whole), and an end in an
  ///   earlier month falls in the next year. "A", "ao", and "até" need no
  ///   opening word when the end names a month, and "e" joins two days only
  ///   after entre. Days of the month alone are read as "dia 5" is, with a
  ///   word that joins the sides: "do dia 3 ao dia 5", "entre os dias 3 e 5"
  ///   count, "de 3 a 5" does not. A day alone opens a range joined by a dash
  ///   only when the dash touches both sides or an opening word comes first:
  ///   "Sprint 12 - 20 de maio" names a sprint and a date.
  /// - Repeat: todo dia, todos os dias, dia sim dia não, todo dia útil, dias
  ///   úteis, de segunda a sexta, toda semana, semana sim semana não, toda
  ///   segunda, todas as segundas e quartas, todo sábado, aos domingos, nos
  ///   sábados, às terças e nas quintas at the end of the line, a cada
  ///   3 dias, de 2 em 2 semanas, a cada quinze dias (every two weeks, as
  ///   Portuguese counts a fortnight), todo mês, todo dia 5, todo ano;
  ///   diariamente, semanalmente, quinzenalmente, mensalmente, and anualmente
  ///   at the end of the line.
  /// - Due: a day after até, para, pra, prazo, or vence ("até sexta").
  /// - Time: 15h, 15h30, às 9h, às 15h30min, por volta das 18h, a partir das
  ///   14h, às 3 da tarde, às 9 da manhã, às 8 da noite, às 3 horas,
  ///   meio-dia, meio-dia e meia, à meia-noite; a range: das 14h às 16h, de
  ///   14h a 16h, 14h-16h, entre 14h e 16h, das 9h ao meio-dia. A time from 1
  ///   to 6 o'clock with no part of the day is the afternoon, unless written
  ///   with a leading zero ("06h"). Da noite runs past midnight, as the
  ///   evening of a day does.
  /// - Length: por 2h, durante 1h30, 1h30min, 1,5 h, 30 min, 30 minutos, 2
  ///   horas, 2 horas e meia, 1 hora e 30 minutos, uma hora, duas horas, meia
  ///   hora, uma hora e meia, um quarto de hora.
  /// - Priority: prioridade alta, alta prioridade, prioridade média,
  ///   prioridade baixa, baixa prioridade, and "urgente" at the end of the
  ///   line or opening it before a colon or comma.
  static let portuguese = LorvexCaptureVocabulary(
    readingForm: unaccentedForMatching,
    priority: [Rule(pattern: portuguesePriorityPattern, read: portuguesePriority)],
    dateRange: [Rule(pattern: portugueseDateRangePattern, read: portugueseDateRange)],
    length: [Rule(pattern: portugueseLengthPattern, read: portugueseLength)],
    time: [
      Rule(pattern: portugueseRangePattern, read: portugueseRange),
      Rule(pattern: portugueseTimePattern, read: portugueseTime),
    ],
    repeats: [
      // The working days and a day of the month before every day, which would
      // leave "útil" or the day's number in the title.
      Rule(
        pattern:
          #"\#(latinStart)(?:todos\s+os\s+dias\s+uteis|todo\s+dia\s+util|(?:nos\s+|em\s+)?dias\s+uteis|de\s+segunda\s+a\s+sexta(?:[-\s]feira)?)\#(latinEnd)"#
      ) { _ in workdays },
      Rule(pattern: portugueseMonthDayRepeatPattern) { match in
        (match.group(1) ?? match.group(2) ?? match.group(3)).flatMap(number).flatMap { monthly(every: nil, on: $0) }
      },
      Rule(pattern: portugueseWeekdayRepeatPattern, read: portugueseWeekdayRepeat),
      Rule(pattern: portugueseIntervalRepeatPattern, read: portugueseIntervalRepeat),
      Rule(pattern: #"\#(latinStart)(?:dia\s+sim,?\s+dia\s+nao|em\s+dias\s+alternados)\#(latinEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2))
      },
      Rule(pattern: cadencePattern("semana\\s+sim,?\\s+semana\\s+nao", adverb: "quinzenalmente")) { _ in
        weekly(every: 2, on: [])
      },
      Rule(pattern: cadencePattern("todos\\s+os\\s+dias|todo\\s+dia", adverb: "diariamente")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily))
      },
      Rule(pattern: cadencePattern("toda\\s+semana|todas\\s+as\\s+semanas", adverb: "semanalmente")) { _ in
        weekly(every: nil, on: [])
      },
      Rule(pattern: cadencePattern("todo\\s+mes|todos\\s+os\\s+meses", adverb: "mensalmente")) { _ in
        monthly(every: nil, on: nil)
      },
      Rule(pattern: cadencePattern("todo\\s+ano|todos\\s+os\\s+anos", adverb: "anualmente")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [
      // An article goes with a day it can precede ("até o dia 5", "até a
      // próxima semana"), never with a weekday's short form, which after one
      // reads as an ordinal ("para a segunda filha").
      Rule(
        pattern:
          #"\#(latinStart)(?:ate|para|pra|prazo\s*:?|vence)\s+(?:(?:o|a)\s+(?=dia|fim|proxim))?(\#(portugueseDayPattern))\#(latinEnd)"#,
        read: portugueseDue)
    ],
    when: [
      Rule(
        pattern: #"\#(latinStart)(?:(de|desde|a\s+partir\s+de)\s+)?(\#(portugueseDayPattern))\#(latinEnd)"#,
        read: portugueseWhen)
    ],
    writesClockTimesWithH: true)

  // MARK: - Priority

  /// Group 1: a written priority; "urgente" has no group.
  private static let portuguesePriorityPattern =
    #"\#(latinStart)(prioridade\s+(?:alta|maxima|media|normal|baixa)|(?:alta|baixa)\s+prioridade)\#(latinEnd)|(?<=\s)urgente(?=\s*$)|^\s*urgente(?=\s*[:,，：])"#

  private static func portuguesePriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("media") || phrase.contains("normal") { return .p2 }
    if phrase.contains("baixa") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "por 2h", "1h30min", "1,5 h", "2 horas e meia", "2 horas", "30 min", or
  /// a length in words, each maybe after por or durante. Groups: 1 por or
  /// durante; 2 and 3 the hours and minutes of "1h30min"; 4 hours written with
  /// h and 5 their minutes ("2h", "1h30", "1,5h"); 6 the hours of "2 horas e
  /// meia"; 7 hours written as a word and 8 their minutes ("1 hora e 30
  /// minutos"); 9 minutes; 10 a length in words.
  private static let portugueseLengthPattern =
    #"\#(latinStart)(?:(por|durante)\s+)?(?:(\d+)\s*h\s*(\d{1,2})\s*min(?:utos?)?|(\d+(?:[.,]\d+)?)\s*h(?:\s*(\d{2}))?|(\d+)\s*horas?\s+e\s+meia|(\d+(?:[.,]\d+)?)\s*horas?(?:\s+e\s+(\d{1,2})\s*min(?:utos?)?)?|(\d+)\s*(?:minutos?|min)|(meia\s+hora|uma\s+hora\s+e\s+meia|uma\s+hora|duas\s+horas|um\s+quarto\s+de\s+hora|tres\s+quartos\s+de\s+hora))(?![\p{Latin}\p{N}])(?!\s+da\s+(?:manha|tarde|noite|madrugada))"#

  private static func portugueseLength(_ match: Match) -> Int? {
    let isLed = match.group(1) != nil
    // An amount after às, das, até, em, or daqui a names a time or a moment,
    // not a length ("às 3 horas", "em 30 minutos").
    if !isLed, let before = wordBefore(match), ["as", "a", "das", "ate", "em"].contains(before) { return nil }
    if let hours = match.group(2).flatMap(number), let minutes = match.group(3).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(4), let hours = decimalAmount(amountText) {
      // A whole hour written with h is a clock time unless por or durante
      // names a length; a fraction of an hour cannot be a time.
      guard isLed || amountText.contains(where: { $0 == "," || $0 == "." }) else { return nil }
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(5).flatMap(number) ?? 0))
    }
    if let hours = match.group(6).flatMap(number) { return taskLength(minutes: hours * 60 + 30) }
    if let hours = match.group(7).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(8).flatMap(number) ?? 0))
    }
    if let minutes = match.group(9).flatMap(number) { return taskLength(minutes: minutes) }
    switch match.group(10).map(normalizedPhrase) {
    case "meia hora": return 30
    case "uma hora e meia": return 90
    case "uma hora": return 60
    case "duas horas": return 120
    case "um quarto de hora": return 15
    case "tres quartos de hora": return 45
    default: return nil
    }
  }

  // MARK: - Time

  /// The part of the day written after a clock time.
  private static let portugueseDayPart = #"da\s+manha|da\s+tarde|da\s+noite|da\s+madrugada"#

  /// "15h30", "às 9h da manhã", "às 15h30min", "às 3 da tarde", "às 3 horas",
  /// "meio-dia", "à meia-noite". Groups: 1 the word before the hour (às, à,
  /// por volta das, a partir das), 2 "@", 3 hour, 4 minute, 5 part of the
  /// day; 6 and 7 the hour and part of the day of "às 3 da tarde"; 8 the hour
  /// of "às 3 horas"; 9 meio-dia and 10 its "e meia"; 11 meia-noite.
  private static let portugueseTimePattern =
    #"\#(latinStart)(?:(a\s+partir\s+das?|por\s+volta\s+das?|as|a)\s+|(@)\s*)?(?<![\p{N}:.,])(\d{1,2})\s*h(?:\s*(\d{2}))?(?:\s*min)?(?![\p{Latin}\p{N}])(?:\s+(\#(portugueseDayPart)))?"#
    + #"|\#(latinStart)(?:as|a)\s+(\d{1,2}|uma|duas|tres)(?:\s+horas?)?\s+(\#(portugueseDayPart))"#
    + #"|\#(latinStart)(?:as|a)\s+(\d{1,2}|uma|duas)\s+horas?(?![\p{Latin}\p{N}])"#
    + #"|\#(latinStart)(?:(?:ao|a|as|por\s+volta\s+do)\s+)?(meio[-\s]?dia)(?:\s+e\s+(meia))?(?![\p{Latin}\p{N}])"#
    + #"|\#(latinStart)(?:a|as|por\s+volta\s+da)\s+(meia[-\s]?noite)\#(latinEnd)"#

  /// The hours "às uma", "às duas", and "às três" spell out.
  private static let portugueseHours = ["uma": 1, "duas": 2, "tres": 3]

  private static func portugueseTime(_ match: Match) -> ClockTime? {
    if match.group(9) != nil { return ClockTime(minutes: 12 * 60 + (match.group(10) == nil ? 0 : 30)) }
    if match.group(11) != nil { return ClockTime(minutes: 0, isAfterMidnight: true) }
    // An hour after até is a deadline, which a task's time cannot hold.
    if wordBefore(match) == "ate" { return nil }
    let hourText: String
    let minuteText: String?
    let part: String?
    if let text = match.group(3) {
      // An hour after "de" with no end is a time or a length ("reunião de
      // 2h").
      if match.group(1) == nil, match.group(2) == nil, wordBefore(match) == "de" { return nil }
      hourText = text
      minuteText = match.group(4)
      part = match.group(5)
    } else if let text = match.group(6) {
      hourText = text
      minuteText = nil
      part = match.group(7)
    } else if let text = match.group(8) {
      hourText = text
      minuteText = nil
      part = nil
    } else {
      return nil
    }
    guard let hour = portugueseHours[hourText.lowercased()] ?? number(hourText) else { return nil }
    let minute = minuteText.flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    guard let part = part.map(normalizedPhrase) else {
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    guard (0...12).contains(hour) else { return nil }
    switch part {
    case "da manha", "da madrugada": return ClockTime(minutes: (hour % 12) * 60 + minute)
    case "da tarde": return ClockTime(minutes: (hour % 12 + 12) * 60 + minute)
    default: return nightTime(hour: hour, minute: minute)
    }
  }

  // MARK: - Time range

  /// One side of a range: an hour with h and maybe minutes, a colon time,
  /// meio-dia, or meia-noite.
  private static let portugueseRangeSide =
    #"\d{1,2}\s*h(?:\s*\d{2})?|\d{1,2}[：:]\d{2}|meio[-\s]?dia|meia[-\s]?noite"#

  /// "das 14h às 16h", "de 14h a 16h", "14h-16h", "entre 14h e 16h", "das 9h
  /// ao meio-dia". The start may be an hour without h when the end has one.
  /// Groups: 1 das, de, entre, or a partir das; 2 the start; 3 the word or
  /// dash between; 4 the end.
  private static let portugueseRangePattern =
    #"\#(latinStart)(?:(das?|de|entre|a\s+partir\s+das?)\s+)?(\#(portugueseRangeSide)|\d{1,2})\s*(-|–|—|ate\s+as|ate|as|ao|a|e)\s*(\#(portugueseRangeSide))(?![\p{Latin}\p{N}:])"#

  private static func portugueseRange(_ match: Match) -> ClockTime? {
    // "E" joins a range only after entre: "às 14h e 16h" names two times.
    guard (match.group(3)?.lowercased() == "e") == (match.group(1)?.lowercased() == "entre"),
      let start = match.group(2).flatMap(portugueseRangeSideTime),
      let end = match.group(4).flatMap(portugueseRangeSideTime)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  private static func portugueseRangeSideTime(_ text: String) -> ClockTime? {
    switch normalizedPhrase(text) {
    case "meio dia", "meiodia": return ClockTime(minutes: 12 * 60)
    case "meia noite", "meianoite": return ClockTime(minutes: 0, isAfterMidnight: true)
    default: return colonTime(text) ?? hourTime(text)
    }
  }

  // MARK: - Date range

  /// "de 3 a 5 de maio", "de 3 de maio a 5 de maio", "do dia 3 ao dia 5 de
  /// maio", "entre os dias 3 e 5 de maio", "3-5 de maio", "3 a 5 de maio",
  /// and, for days of the month alone, "do dia 3 ao dia 5". The start is a date
  /// or a day alone ("3", "dia 3"), the end a date or a day alone; each side
  /// may have "dia" or "o dia" before it. Groups: 1 the word that opens the
  /// range, if any (de, do, desde, entre, entre os dias), 2 the start, 3 a dash
  /// between the sides, 4 a, ao, até, or e between them, 5 the end.
  private static var portugueseDateRangePattern: String {
    let dayMark = #"(?:(?:o\s+)?dia\s+)?"#
    let day = #"\d{1,2}[º°o]?"#
    let year = #"(?:\s+(?:de\s+)?\d{4})?"#
    let full = "\(dayMark)\(day)\\s+(?:de\\s+)?(?:\(portugueseMonths.joined(separator: "|")))\(year)"
    let bare = "\(dayMark)\(day)(?![\\p{N}:h])"
    return
      #"\#(latinStart)(?:(de|do|desde|entre(?:\s+os\s+dias)?)\s+)?(\#(full)|\#(bare))(?:\s*([-–—])\s*|\s+(a|ao|ate|e)\s+)(\#(full)|\#(bare))(?![\p{Latin}\p{N}:])"#
  }

  private static func portugueseDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = portugueseRangeDate(startText), let end = portugueseRangeDate(endText)
    else { return nil }
    let lead = match.group(1).map(normalizedPhrase)
    // "E" joins the sides only after entre ("dia 3 e dia 5" names two days); a,
    // ao, and até join them after de, do, or desde, and with no opening word
    // when the end names a month ("3 a 5 de maio").
    if let word = match.group(4)?.lowercased() {
      guard (word == "e") == (lead?.hasPrefix("entre") == true),
        lead != nil || joinsWithoutOpeningWord(match, end: end)
      else { return nil }
    }
    if start.month == nil, lead == nil, match.group(3) != nil, !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    switch (start.month, end.month) {
    case (nil, nil):
      // Days of the month alone are read as "dia 5" is, with a word between
      // the sides, so "de 3 a 5" and "dia 5 - 10 min" stay as they are.
      guard match.group(4) != nil, startText.lowercased().contains("dia") || lead?.hasSuffix("dias") == true
      else { return nil }
    case (_, nil): return nil
    default: break
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 de maio", "dia 5 de maio de 2027", "o
  /// dia 5 de maio"), or a day alone ("5", "dia 5"), which has no month.
  private static func portugueseRangeDate(_ text: String) -> ExplicitDate? {
    var words = normalizedPhrase(text)
    if words.hasPrefix("o ") { words.removeFirst(2) }
    if let date = portugueseDate(words) { return date }
    guard let match = words.wholeMatch(of: /(\d{1,2})[º°o]?/), let day = number(match.output.1) else { return nil }
    return ExplicitDate(day: day)
  }

  // MARK: - Repeat

  /// "toda segunda", "todas as segundas e quartas", "todo sábado", "aos
  /// domingos", "nos sábados"; and "às segundas", "nas terças e quintas", or
  /// "às sextas e aos sábados" at the end of the line, since a plural short
  /// form after an article is also an ordinal ("as segundas vias"). Group 1
  /// or 2: the weekdays.
  private static var portugueseWeekdayRepeatPattern: String {
    let day = "(?:(?:segunda|terca|quarta|quinta|sexta)s?(?:[-\\s]feiras?)?|sabados?|domingos?)"
    let plural = "(?:(?:segunda|terca|quarta|quinta|sexta)s(?:[-\\s]feiras)?|sabados|domingos)"
    let days = "\(day)(?:\\s*(?:,|e)\\s*(?:(?:aos|nos|as|os|a|o)\\s+)?\(day))*"
    let plurals = "\(plural)(?:\\s*(?:,|e)\\s*(?:(?:aos|nos|as|nas)\\s+)?\(plural))*"
    return "\(latinStart)(?:(?:todas\\s+as|todos\\s+os|toda|todo|aos|nos)\\s+(\(days))\(latinEnd)"
      + "|(?:as|nas)\\s+(\(plurals))(?=[\\s.,;!?]*$))"
  }

  private static func portugueseWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = (match.group(1) ?? match.group(2) ?? "").split { !$0.isLetter }.map(String.init)
      .compactMap(portugueseWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "a cada 3 dias", "de 2 em 2 semanas", "a cada quinze dias". Groups: 1
  /// the count after a cada; 2 and 3 the counts of "de 2 em 2"; 4 the unit.
  private static var portugueseIntervalRepeatPattern: String {
    let count = "\\d{1,2}|" + portugueseNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    return "\(latinStart)(?:a\\s+cada\\s+(\(count))|de\\s+(\(count))\\s+em\\s+(\(count)))\\s+(dias|semanas|meses|anos)"
      + latinEnd
  }

  private static func portugueseIntervalRepeat(_ match: Match) -> Repeat? {
    func value(_ text: String?) -> Int? {
      text.flatMap { number($0) ?? portugueseNumbers[$0.lowercased()] }
    }
    let count: Int?
    if let single = value(match.group(1)) {
      count = single
    } else if let first = value(match.group(2)), first == value(match.group(3)) {
      count = first
    } else {
      count = nil
    }
    guard let count, (1...99).contains(count), let unit = match.group(4)?.lowercased() else { return nil }
    let every = count == 1 ? nil : count
    switch unit {
    // Portuguese counts a fortnight as fifteen days: "a cada quinze dias" is
    // every two weeks.
    case "dias":
      return count == 15 ? weekly(every: 2, on: []) : Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "semanas": return weekly(every: every, on: [])
    case "meses": return monthly(every: every, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
  }

  /// "todo dia 5", "todo mês no dia 5", "dia 5 de cada mês". Groups 1, 2, and
  /// 3: the day of the month in each form.
  private static let portugueseMonthDayRepeatPattern =
    #"\#(latinStart)(?:todo\s+dia\s+(\d{1,2})|(?:todo\s+mes|todos\s+os\s+meses)\s+(?:no\s+)?dia\s+(\d{1,2})|dia\s+(\d{1,2})\s+de\s+cada\s+mes)\#(latinEnd)"#

  /// The counts a repeat or a day phrase may spell out.
  private static let portugueseNumbers = [
    "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8,
    "nove": 9, "dez": 10, "onze": 11, "doze": 12, "quinze": 15,
  ]

  // MARK: - Days

  /// The weekday names without accents, Sunday first; Monday to Friday also
  /// take "-feira".
  private static let portugueseWeekdays = ["domingo", "segunda", "terca", "quarta", "quinta", "sexta", "sabado"]

  /// The month names without accents, January first.
  private static let portugueseMonths = [
    "janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro",
    "dezembro",
  ]

  /// The days, without the word that may introduce them.
  private static var portugueseDayPattern: String {
    let count = "(?:\\d{1,3}|um|uma|dois|duas|tres|quinze)"
    let weekday = "(?:segunda|terca|quarta|quinta|sexta)(?:[-\\s]feira)?|sabado|domingo"
    return #"hoje\s+(?:a|de)\s+noite|(?:n?esta|n?essa)\s+noite|hoje(?:\s+(?:a\s+tarde|de\s+manha|cedo))?"#
      + #"|depois\s+de\s+amanha|amanha\s+(?:a|de)\s+noite|amanha(?:\s+(?:a\s+tarde|de\s+manha|cedo))?"#
      + #"|(?:na\s+)?(?:proxima\s+semana|semana\s+que\s+vem)"#
      + #"|(?:no\s+)?(?:proximo\s+fim\s+de\s+semana|fim\s+de\s+semana\s+que\s+vem)|(?:n?este\s+|n?esse\s+|no\s+)?fim\s+de\s+semana"#
      + "|(?:daqui\\s+a|em)\\s+\(count)\\s+(?:dias?|semanas?)|\(portugueseDatePattern)"
      + "|(?:(?:na|no|n?esta|n?este|n?essa|n?esse)\\s+)?(?:(?:proxima|proximo)\\s+)?(?:\(weekday))(?:\\s+que\\s+vem)?"
  }

  /// "5 de outubro", "dia 5 de outubro", "1º de outubro de 2027", or "dia 5".
  private static var portugueseDatePattern: String {
    let months = portugueseMonths.joined(separator: "|")
    return "(?:dia\\s+)?\\d{1,2}[º°o]?\\s+(?:de\\s+)?(?:\(months))(?:\\s+(?:de\\s+)?\\d{4})?|dia\\s+\\d{1,2}(?![\\p{N}:h])"
  }

  private static func portugueseWhen(_ match: Match) -> Day? {
    match.group(2).flatMap { portugueseDay($0, in: match, isLed: match.group(1) != nil) }
  }

  private static func portugueseDue(_ match: Match) -> Day? {
    match.group(1).flatMap { portugueseDay($0, in: match, isLed: true) }.map { Day(offset: $0.offset) }
  }

  private static func portugueseDay(_ phrase: String, in match: Match, isLed: Bool) -> Day? {
    let words = normalizedPhrase(phrase)
    let todayWeekday = match.todayWeekday
    if let date = portugueseDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let weekend = weekendOffset(todayWeekday: todayWeekday)
    switch words {
    case "hoje", "hoje a tarde", "hoje de manha", "hoje cedo": return Day(offset: 0)
    case "hoje a noite", "hoje de noite", "esta noite", "nesta noite", "essa noite", "nessa noite":
      return Day(offset: 0, isEvening: true)
    case "amanha", "amanha a tarde", "amanha de manha", "amanha cedo": return Day(offset: 1)
    case "amanha a noite", "amanha de noite": return Day(offset: 1, isEvening: true)
    case "depois de amanha": return Day(offset: 2)
    case "proxima semana", "na proxima semana", "semana que vem", "na semana que vem": return Day(offset: 7)
    case "fim de semana", "este fim de semana", "neste fim de semana", "esse fim de semana", "nesse fim de semana",
      "no fim de semana":
      return Day(offset: weekend)
    case "proximo fim de semana", "no proximo fim de semana", "fim de semana que vem", "no fim de semana que vem":
      return Day(offset: weekend + 7)
    default: break
    }
    if let relative = words.wholeMatch(of: /(?:daqui a|em) (\w+) (dia|dias|semana|semanas)/) {
      let countText = String(relative.output.1)
      guard let count = number(countText) ?? portugueseNumbers[countText] else { return nil }
      return Day(offset: relative.output.2.hasPrefix("semana") ? count * 7 : count)
    }
    let parts = words.split(separator: " ").map(String.init)
    guard let weekday = parts.lazy.compactMap(portugueseWeekdayIndex).first else { return nil }
    // A weekday's short form is also an ordinal ("a segunda parte"), so with
    // no word introducing it, it counts only at the end of the line after a
    // word that is not an article.
    if parts.count == 1, !isLed, (1...5).contains(weekday) {
      let articles: Set = ["a", "o", "as", "os", "da", "do", "das", "dos", "um", "uma"]
      guard endsLine(match), !articles.contains(wordBefore(match) ?? "") else { return nil }
    }
    if parts.contains(where: { $0.hasPrefix("proxim") }) || words.hasSuffix("que vem") {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday))
    }
    if ["nesta", "neste", "esta", "este", "nessa", "nesse", "essa", "esse"].contains(parts[0]) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday))
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday))
  }

  /// A written-out date ("5 de outubro", "dia 1º de outubro de 2027"), or a
  /// day of the month alone ("dia 5"), the coming one.
  private static func portugueseDate(_ words: String) -> ExplicitDate? {
    if let match = words.wholeMatch(of: /(?:dia )?(\d{1,2})[º°o]? (?:de )?(\p{L}+)(?: (?:de )?(\d{4}))?/),
      let day = number(match.output.1), let month = portugueseMonths.firstIndex(of: String(match.output.2))
    {
      return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
    }
    if let match = words.wholeMatch(of: /dia (\d{1,2})/), let day = number(match.output.1) {
      return ExplicitDate(day: day)
    }
    return nil
  }

  /// The weekday a word names, 0 = Sunday, singular or plural ("segundas").
  private static func portugueseWeekdayIndex(_ word: String) -> Int? {
    let lower = word.lowercased()
    return portugueseWeekdays.firstIndex { lower == $0 || lower == $0 + "s" }
  }
}
