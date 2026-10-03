import Foundation

extension LorvexCaptureVocabulary {
  /// Spanish, read for a user who reads Spanish, as written in Spain and in
  /// Latin America. A word needs a boundary of Latin letters and digits on
  /// both sides, as in English, and accents may be left out ("manana",
  /// "miercoles", "a las 3 de la tarde").
  ///
  /// Spanish says a clock time with "a las" ("a las 3", "a las 15:30"), and
  /// the hours may end in h, hs, hrs, or horas ("a las 15 h", "15:30 hrs"). An
  /// hour count written with the letter h alone ("2h", "1h30") is a length, as
  /// in English, so, unlike French and Portuguese, this vocabulary does not
  /// turn "2h" into a clock time. A bare hour after "a las" is a time only
  /// when the line goes on with a word that can follow a time ("a las 3 con
  /// Pedro", "a las 3 mañana") rather than a counted noun ("a las 3
  /// hermanas"). An hour after antes de, hasta, or para is a deadline, which
  /// a task's time cannot hold, so it stays in the title.
  ///
  /// English is read beside Spanish, so a detail that needs no Spanish word
  /// is left to English, which reads its own "at 3pm", "from 3-4pm", or "for
  /// 2h" whole: a time with no Spanish word ("3pm", "15:30"), a range with a
  /// dash ("14:00-16:30"), and an amount after "for".
  ///
  /// "Mañana" is both tomorrow and the morning. Alone it is tomorrow ("llamar
  /// mañana"); after an hour with de, por, or en la it is the morning ("a las
  /// 9 de la mañana" is 9 AM and names no day); after de, del, la, cada, or
  /// todas las it is not a day at all ("turno de mañana", "por la mañana",
  /// "cada mañana"); and "mañana por la mañana" is tomorrow.
  ///
  /// - Day: hoy, hoy mismo, esta mañana, esta tarde, esta noche, mañana,
  ///   mañana mismo, mañana temprano, mañana por la mañana, por la tarde, or
  ///   por la noche, pasado mañana, the weekday names
  ///   (alone, after el or este, with próximo or que viene), la próxima
  ///   semana, la semana que viene, el fin de semana, este finde, el próximo
  ///   fin de semana, en 3 días, dentro de una semana, each maybe after
  ///   desde or a partir de; a date: 15 de octubre, el 15 de octubre, lunes
  ///   15 de octubre, 1º de octubre, el primero de octubre, 15 oct., 15 de
  ///   octubre de 2027, and a day of the month alone after el or día ("el 15",
  ///   "el día 15"), which counts only at the end of the line or before a
  ///   word that can follow a date. A weekday alone means the next such day,
  ///   a full week ahead when it names today; after este it is this week's,
  ///   and with próximo or que viene next week's, weeks starting on Monday.
  ///   Hoy por la noche, esta noche, and mañana por la noche are evenings. A
  ///   weekday in the plural ("los lunes") is a habit, not a day, and a day
  ///   after de or del ("la reunión del lunes"), a weekday followed by pasado
  ///   ("el lunes pasado"), "hoy en día", and a capitalized "Domingo" that
  ///   does not open the line (a name) are left in the title. A date written
  ///   in digits ("15/10") is not read, since the order of its day and month
  ///   depends on the region.
  /// - Repeat: todos los días, cada día, a diario, cada mañana, entre semana,
  ///   de lunes a viernes, todos los días laborables, cada semana, cada dos
  ///   semanas, cada quince días (every two weeks, as Spanish counts a
  ///   fortnight), cada lunes, todos los lunes, cada lunes y jueves, todos
  ///   los lunes y los jueves, cada dos lunes, los lunes at the end of the
  ///   line (a plural weekday before another word is part of the title), un
  ///   día sí y otro no, cada 3 días, cada tres meses, cada mes, el 5 de cada
  ///   mes, el primero de cada mes, cada año, todos los años; diariamente,
  ///   semanalmente, quincenalmente, mensualmente, and anualmente at the end
  ///   of the line.
  /// - Due: a day after antes de, antes del, para, hasta, vence, fecha límite,
  ///   plazo, or a más tardar ("para el viernes"), or before a más tardar.
  /// - Time: a las 3, a las 15:30, a las 9 y 30, a las 9 de la mañana, a las
  ///   3 de la tarde, a las 8 de la noche, a las 3 y media, a las 3 y cuarto,
  ///   a las 4 menos cuarto, a las 3 en punto, a las 3 pm, a las 15 h, a la
  ///   una, sobre las 6, desde las 8, 3 de la tarde, 15:30 hrs, mediodía, al
  ///   mediodía, a medianoche; a range: de 3 a 4, de 14:00 a 16:30, de las 3 a
  ///   las 4 de la tarde, entre las 3 y las 4, desde las 9 hasta el mediodía.
  ///   A time from 1 to 6 o'clock with no part of the day is the afternoon,
  ///   unless written with a leading zero ("06:30"). De la mañana keeps the
  ///   morning (12 de la mañana is noon), de la tarde is the afternoon, de la
  ///   noche is the evening from 6 to 11 and runs past midnight from 12 to 5
  ///   ("a las 3 de la noche" is 03:00 of the next day), and de la madrugada
  ///   is the small hours of the same day. A range of two bare
  ///   hours counts after de or desde ("de 3 a 4"), or after entre when an
  ///   article marks them ("entre las 3 y las 4"), and only when the line goes
  ///   on with a word that can follow a time, so "de 3 a 5 páginas" is a
  ///   title. "Mediodía" and "medianoche" after el, la, del, or de ("menú del
  ///   mediodía") are not times.
  /// - Length: durante 2 horas, por 2 horas, de 2 horas, 2h, 1h30, 1h30min,
  ///   1,5 horas, 30 min, 30 minutos, 2 horas, 2 horas y media, 1 hora y 30
  ///   minutos, una hora, dos horas, media hora, una hora y media, un cuarto
  ///   de hora, tres cuartos de hora. An amount after en, dentro de, hace,
  ///   tras, después de, antes de, cada, más de, menos de, cerca de, or a lead
  ///   such as a las names a moment, an interval, or a deadline, not a length
  ///   ("en 2 horas", "cada 8 horas"); an hour count that ends a range ("de 9
  ///   a 14 h") is the range's end.
  /// - Priority: prioridad alta, alta prioridad, prioridad media, prioridad
  ///   baja, baja prioridad (also máxima, elevada, normal, and mínima), and
  ///   "urgente" at the end of the line or opening it before a colon or
  ///   comma.
  static let spanish = LorvexCaptureVocabulary(
    readingForm: unaccentedForMatching,
    priority: [Rule(pattern: spanishPriorityPattern, read: spanishPriority)],
    length: [Rule(pattern: spanishLengthPattern, read: spanishLength)],
    time: [
      Rule(pattern: spanishFromToPattern, read: spanishRange),
      Rule(pattern: spanishBetweenPattern, read: spanishRange),
      Rule(pattern: spanishTimePattern, read: spanishTime),
    ],
    repeats: [
      // The working days and a day of the month before every day and every
      // month, which would leave "laborables" or the day's number in the
      // title.
      Rule(
        pattern:
          #"\#(latinStart)(?:todos\s+los\s+dias\s+(?:laborables|laborales|habiles)|cada\s+dia\s+(?:laborable|laboral|habil)|los\s+dias\s+(?:laborables|laborales|habiles)|entre\s+semana|de\s+lunes\s+a\s+viernes)\#(latinEnd)"#
      ) { _ in workdays },
      Rule(pattern: spanishMonthDayRepeatPattern) { match in
        (match.group(1) ?? match.group(2)).flatMap(spanishDayNumber).flatMap { monthly(every: nil, on: $0) }
      },
      Rule(pattern: spanishWeekdayRepeatPattern, read: spanishWeekdayRepeat),
      Rule(pattern: spanishIntervalRepeatPattern, read: spanishIntervalRepeat),
      Rule(
        pattern: #"\#(latinStart)(?:un|una)\s+(dia|semana|mes)\s+si,?\s+(?:y\s+)?(?:otro|otra)\s+no\#(latinEnd)"#,
        read: spanishAlternateRepeat),
      Rule(pattern: cadencePattern("cada\\s+quincena", adverb: "quincenalmente")) { _ in weekly(every: 2, on: []) },
      Rule(
        pattern: cadencePattern(
          "cada\\s+dia|todos\\s+los\\s+dias|a\\s+diario|cada\\s+(?:manana|tarde|noche)|todas\\s+las\\s+(?:mananas|tardes|noches)",
          adverb: "diariamente")
      ) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      Rule(pattern: cadencePattern("cada\\s+semana|todas\\s+las\\s+semanas", adverb: "semanalmente")) { _ in
        weekly(every: nil, on: [])
      },
      Rule(pattern: cadencePattern("cada\\s+mes|todos\\s+los\\s+meses", adverb: "mensualmente")) { _ in
        monthly(every: nil, on: nil)
      },
      Rule(pattern: cadencePattern("cada\\s+ano|todos\\s+los\\s+anos", adverb: "anualmente")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [
      Rule(pattern: spanishDuePattern, read: spanishDue),
      Rule(
        pattern: #"\#(latinStart)(?:(el)\s+)?(\#(spanishDayPattern))\s+a\s+mas\s+tardar\#(latinEnd)"#, read: spanishDue),
    ],
    when: [
      Rule(
        pattern:
          #"\#(latinStart)(?:(desde\s+el|desde|a\s+partir\s+del|a\s+partir\s+de\s+el|a\s+partir\s+de|el)\s+)?(\#(spanishDayPattern))\#(latinEnd)"#,
        read: spanishWhen)
    ])

  // MARK: - Words after a detail

  /// The words a detail with no unit of its own ("a las 3", "el 15", "de 3 a
  /// 4") may be followed by: prepositions, conjunctions, articles, and the
  /// words that say when or how often. Any other word after the number makes
  /// it a count ("a las 3 hermanas", "el 15 libros"), so it stays in the
  /// title.
  private static let spanishWordsAfterDetail: Set<String> = [
    "a", "al", "con", "en", "de", "del", "para", "por", "hasta", "desde", "sin", "sobre", "entre", "tras", "y", "e",
    "o", "u", "ni", "pero", "que", "el", "la", "los", "las", "lo", "este", "esta", "ese", "esa", "cada", "todos",
    "todas", "hoy", "manana", "pasado", "antes", "despues", "luego", "ya", "mas", "aprox", "aproximadamente", "mismo",
    "tambien", "se", "me", "te", "le", "les", "nos", "si", "no",
  ]

  /// Whether the line goes on after `match` with nothing, punctuation, or a
  /// word in ``spanishWordsAfterDetail`` (minus `excluding`).
  private static func spanishFollowsAsDetail(_ match: Match, excluding: Set<String> = []) -> Bool {
    guard let next = wordAfter(match) else { return true }
    return spanishWordsAfterDetail.contains(next) && !excluding.contains(next)
  }

  /// The words before a time or a day that make a "mediodía" or a "domingo"
  /// after them an ordinary noun.
  private static let spanishNounLeads: Set<String> = ["el", "la", "del", "de", "un", "una", "este", "esta", "ese", "esa"]

  // MARK: - Priority

  /// Group 1: a written priority; "urgente" has no group.
  private static let spanishPriorityPattern =
    #"\#(latinStart)(prioridad\s+(?:alta|maxima|elevada|media|normal|baja|minima)|(?:alta|media|baja)\s+prioridad)\#(latinEnd)|(?<=\s)urgente(?=\s*$)|^\s*urgente(?=\s*[，：:,])"#

  private static func spanishPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("media") || phrase.contains("normal") { return .p2 }
    if phrase.contains("baja") || phrase.contains("minima") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "durante 2 horas", "por 2h", "de 2 horas", "1h30min", "1,5 horas", "2
  /// horas y media", "2 horas", "30 min", or a length in words, each maybe
  /// after durante, por, or de. Groups: 1 durante, por, or de; 2 a word that
  /// makes the amount a moment or an interval; 3 and 4 the hours and minutes
  /// of "1h30" and "1h30min"; 5 the hours of "2 horas y media"; 6 hours with a
  /// unit ("2h", "1,5 horas") and 7 their minutes ("1 hora y 30 minutos"); 8
  /// minutes; 9 a length in words. The amount may not follow a digit, a colon,
  /// or a separator, so the "05 h" of "9:05 h" is not five hours; it may not be
  /// a side of a range ("de 9 a 14 h", "9-14 h"), which is a time range; and
  /// it may not follow the English "for", so English's "for 2h" keeps its
  /// "for".
  private static let spanishLengthPattern =
    #"\#(latinStart)(?:(durante|por|de)\s+|(en|dentro\s+de|hace|tras|despues\s+de|antes\s+de|cada|mas\s+de|menos\s+de|cerca\s+de|a\s+las?|desde\s+las?|hasta\s+las?|hacia\s+las?|sobre\s+las?)\s+)?(?<![\p{N}:.,])(?<![\p{N}hs]\s(?:a|al|hasta)\s)(?<![\p{N}hs]\s?[-–—]\s?)(?<!\bfor\s)(?:(\d+)\s*h\s*(\d{1,2})(?:\s*(?:minutos?|mins?))?|(\d+)\s*horas?\s+y\s+media|(\d+(?:[.,]\d+)?)\s*(?:horas?|hrs?|hs|h)(?:\s+(?:y\s+)?(\d{1,2})\s*(?:minutos?|mins?))?|(\d+)\s*(?:minutos?|mins?)|(media\s+hora|(?:una\s+)?hora\s+y\s+media|una\s+hora|dos\s+horas|(?:un\s+)?cuarto\s+de\s+hora|tres\s+cuartos\s+de\s+hora))(?![\p{Latin}\p{N}])(?!\s*[-–—]\s*\d|\s+(?:a|al|hasta)\s+\d)"#

  private static func spanishLength(_ match: Match) -> Int? {
    // An amount after en, dentro de, hace, tras, cada, or a las names a
    // moment or an interval ("en 2 horas", "cada 8 horas", "a las 3 horas"),
    // not a length.
    if match.group(2) != nil { return nil }
    if let hours = match.group(3).flatMap(number), let minutes = match.group(4).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let hours = match.group(5).flatMap(number) { return taskLength(minutes: hours * 60 + 30) }
    if let hours = match.group(6).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(7).flatMap(number) ?? 0))
    }
    if let minutes = match.group(8).flatMap(number) { return taskLength(minutes: minutes) }
    switch match.group(9).map(normalizedPhrase) {
    case "media hora": return 30
    case "hora y media", "una hora y media": return 90
    case "una hora": return 60
    case "dos horas": return 120
    case "cuarto de hora", "un cuarto de hora": return 15
    case "tres cuartos de hora": return 45
    default: return nil
    }
  }

  // MARK: - Time

  /// The words before an hour that make it a clock time.
  private static let spanishTimeLead =
    #"a\s+eso\s+de\s+las?|a\s+partir\s+de\s+las?|como\s+a\s+las?|sobre\s+las?|hacia\s+las?|desde\s+las?|a\s+las?"#

  /// An hour: digits, or the word for one of the twelve hours.
  private static let spanishHourWord = #"\d{1,2}|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce"#

  /// The part of the day written after a clock time: de la mañana, por la
  /// tarde, en la noche, de la madrugada, del mediodía. One group.
  private static let spanishPartOfDay =
    #"(?:\s+((?:de|por|en)\s+la\s+(?:manana|tarde|noche|madrugada)|del\s+mediodia))"#

  /// The part of the day or the meridiem after a clock time: a
  /// ``spanishPartOfDay``, or a. m. or pm. Two groups: the part of the day in
  /// words, and the letter of AM or PM.
  private static let spanishDayPart = #"(?:\#(spanishPartOfDay)|\s*([ap])\.?\s?m\.?)"#

  /// What may follow a clock time: no letter, digit, or colon, and no decimal
  /// fraction.
  private static let spanishTimeEnd = #"(?![\p{Latin}\p{N}:]|[.,]\p{N})"#

  /// "a las 3", "a las 15:30", "a las 9 de la mañana", "a las 3 y media", "a
  /// las 4 menos cuarto", "a las 3 en punto", "a las 15 h", "a las 3 pm", and
  /// "a la una"; "3 de la tarde" with no lead; "15:30 hrs"; and "mediodía" and
  /// "medianoche". A time written with no Spanish word ("3pm", "15:30") is
  /// left to English, whose "at 3pm" would lose its "at" here. Groups: 1 the
  /// lead (a las, sobre las, desde las, ...), 2 hour, 3 minute, 4 the h, hs,
  /// hrs, or horas after the hour, 5 media, cuarto, or minutes after "y", 6
  /// cuarto after "menos", 7 "en punto", 8 the part of the day, 9 the letter of
  /// AM or PM; 10 to 12 the hour, minute, and part of the day of a time with
  /// no lead; 13 and 14 the hour and minute of "15:30 hrs"; 15 the word before
  /// mediodía or medianoche, 16 the word, 17 its "y media".
  private static let spanishTimePattern =
    [
      #"\#(latinStart)(\#(spanishTimeLead))\s+(\#(spanishHourWord))(?:[.:](\d{2}))?(?:\s*(horas?|hrs?|hs|h)(?![\p{Latin}\p{N}]))?(?:\s+y\s+(media|cuarto|\d{2})|\s+menos\s+(cuarto))?(?:\s+(en\s+punto))?\#(spanishDayPart)?\#(spanishTimeEnd)"#,
      #"\#(latinStart)(?<![\p{N}:.,])(\d{1,2})(?::(\d{2}))?\#(spanishPartOfDay)\#(spanishTimeEnd)"#,
      #"\#(latinStart)(?<![\p{N}:.,])(\d{1,2}):(\d{2})\s*(?:horas?|hrs?|hs|h)(?![\p{Latin}\p{N}])"#,
      #"\#(latinStart)(?:(al|a|hacia|sobre|desde)\s+(?:(?:el|la)\s+)?)?(mediodia|medianoche)(?:\s+y\s+(media))?(?![\p{Latin}\p{N}])"#,
    ].joined(separator: "|")

  /// The hours the words una to doce spell.
  private static let spanishHours = [
    "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
    "once": 11, "doce": 12,
  ]

  private static func spanishTime(_ match: Match) -> ClockTime? {
    if let word = match.group(16)?.lowercased() {
      // "El mediodía" and "menú del mediodía" are nouns, not a time.
      if match.group(15) == nil, let before = wordBefore(match), spanishNounLeads.contains(before) { return nil }
      let half = match.group(17) == nil ? 0 : 30
      return word == "mediodia" ? ClockTime(minutes: 12 * 60 + half) : ClockTime(minutes: half, isAfterMidnight: true)
    }
    if let hourText = match.group(13) {
      guard let hour = number(hourText), let minute = match.group(14).flatMap(number) else { return nil }
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    let hourText: String
    let minuteText: String?
    let part: String?
    let meridiem: String?
    let hasLead = match.group(2) != nil
    if let text = match.group(2) {
      hourText = text
      minuteText = match.group(3)
      part = match.group(8)
      meridiem = match.group(9)
    } else if let text = match.group(10) {
      hourText = text
      minuteText = match.group(11)
      part = match.group(12)
      meridiem = nil
    } else {
      return nil
    }
    guard var hour = spanishHours[hourText.lowercased()] ?? number(hourText) else { return nil }
    var minute = minuteText.flatMap(number) ?? 0
    if hasLead, let fraction = match.group(5)?.lowercased() {
      guard minuteText == nil else { return nil }
      minute = fraction == "media" ? 30 : (fraction == "cuarto" ? 15 : number(fraction) ?? 0)
    } else if hasLead, match.group(6) != nil {
      // "A las 4 menos cuarto" is 3:45, and "a la una menos cuarto" 12:45.
      guard minuteText == nil, hour >= 1 else { return nil }
      hour = hour == 1 ? 12 : hour - 1
      minute = 45
    }
    guard (0...59).contains(minute) else { return nil }
    if part != nil || meridiem != nil {
      return spanishPartTime(
        hour: hour, minute: minute, part: part.map(normalizedPhrase), meridiem: meridiem?.lowercased())
    }
    // A bare hour ("a las 3") is a time unless a counted noun follows it ("a
    // las 3 hermanas").
    let isBare = hasLead && (3...7).allSatisfy { match.group($0) == nil }
    if isBare, !spanishFollowsAsDetail(match) { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  /// The time an hour of a 12-hour clock names with a part of the day or AM or
  /// PM; nil for an hour no such clock shows.
  private static func spanishPartTime(hour: Int, minute: Int, part: String?, meridiem: String?) -> ClockTime? {
    guard (1...12).contains(hour) else { return nil }
    if let meridiem {
      return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
    }
    guard let part else { return nil }
    if part.hasSuffix("manana") { return ClockTime(minutes: hour * 60 + minute) }
    if part.hasSuffix("tarde") || part.hasSuffix("mediodia") { return ClockTime(minutes: (hour % 12 + 12) * 60 + minute) }
    if part.hasSuffix("madrugada") { return ClockTime(minutes: (hour % 12) * 60 + minute) }
    return nightTime(hour: hour, minute: minute)
  }

  // MARK: - Time range

  /// One side of a range: an hour with maybe minutes and h, an hour word,
  /// mediodía, or medianoche.
  private static let spanishRangeSide =
    #"\d{1,2}(?:[.:]\d{2})?(?:\s*(?:hrs?|hs|h))?|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|mediodia|medianoche"#

  /// An article before a side of a range: las or la before an hour, el before
  /// mediodía. One group.
  private static let spanishRangeArticle = #"((?:las?|el)\s+)?"#

  /// "de 3 a 4", "de las 3 a las 4", "desde las 9 hasta el mediodía". A range
  /// with a dash ("14:00-16:30", "3-4pm") is left to English. The two range
  /// patterns share their groups: 1 the word that opens the range (de, desde,
  /// entre), 2 the article before the start, 3 the start, 4 the article before
  /// the end, 5 the end, 6 the part of the day written after the end, 7 the
  /// letter of AM or PM.
  private static let spanishFromToPattern =
    #"\#(latinStart)(de|desde)\s+\#(spanishRangeArticle)(\#(spanishRangeSide))\s+(?:a|al|hasta)\s+\#(spanishRangeArticle)(\#(spanishRangeSide))\#(spanishDayPart)?\#(spanishTimeEnd)"#

  /// "entre las 3 y las 4".
  private static let spanishBetweenPattern =
    #"\#(latinStart)(entre)\s+\#(spanishRangeArticle)(\#(spanishRangeSide))\s+y\s+\#(spanishRangeArticle)(\#(spanishRangeSide))\#(spanishDayPart)?\#(spanishTimeEnd)"#

  private static func spanishRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(3), let endText = match.group(5), let start = spanishRangeSideTime(startText),
      var end = spanishRangeSideTime(endText)
    else { return nil }
    // El before a number names a day of the month ("entre el 3 y el 10 de
    // agosto", "desde el 3 hasta el 10"): an hour takes la or las, and only
    // mediodía takes el.
    let sides = [(match.group(2), startText), (match.group(4), endText)]
    if sides.contains(where: { article, side in
      article.map(normalizedPhrase) == "el" && side.lowercased() != "mediodia"
    }) {
      return nil
    }
    let part = match.group(6).map(normalizedPhrase)
    let meridiem = match.group(7)?.lowercased()
    if part != nil || meridiem != nil {
      // The part of the day written after the end belongs to the end; the
      // start takes the reading of its hour that fits before it.
      guard let hour = end.writtenHour,
        let named = spanishPartTime(hour: hour, minute: end.minutes % 60, part: part, meridiem: meridiem)
      else { return nil }
      end = named
    } else if spanishIsBareHour(startText) && spanishIsBareHour(endText) {
      // Two bare hours are as often a count: they are a range after de,
      // desde, or entre las, and only when no counted noun follows.
      let opener = match.group(1)?.lowercased()
      let hasArticle = match.group(2) != nil || match.group(4) != nil
      guard let opener, opener != "entre" || hasArticle, spanishFollowsAsDetail(match) else { return nil }
    }
    return timeRange(from: start, to: end)
  }

  /// Whether a range side is only an hour, in digits or in a word.
  private static func spanishIsBareHour(_ text: String) -> Bool {
    text.allSatisfy(\.isNumber) || spanishHours[text.lowercased()] != nil
  }

  private static func spanishRangeSideTime(_ text: String) -> ClockTime? {
    let lower = text.lowercased()
    switch lower {
    case "mediodia": return ClockTime(minutes: 12 * 60)
    case "medianoche": return ClockTime(minutes: 0, isAfterMidnight: true)
    default: break
    }
    if let hour = spanishHours[lower] { return bareTime(hour: hour, minute: 0, hasLeadingZero: false) }
    guard let match = lower.wholeMatch(of: /(\d{1,2})(?:[.:](\d{2}))?\s*(?:hrs?|hs|h)?/), let hour = number(match.output.1)
    else { return nil }
    let minute = match.output.2.flatMap { number($0) } ?? 0
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(match.output.1)))
  }

  // MARK: - Repeat

  /// The weekday names, longest first, as a pattern.
  private static var spanishWeekdayNames: String {
    spanishWeekdays.sorted { $0.count > $1.count }.joined(separator: "|")
  }

  /// "todos los lunes", "cada lunes", "cada dos lunes", "cada lunes y jueves",
  /// "todos los lunes y los jueves", and "los lunes" or "los sábados y
  /// domingos" at the end of the line, since "los lunes" before another word
  /// is part of the title ("los lunes de agosto"). Groups: 1 the weekdays after
  /// todos los or todas las, 2 the count after cada, 3 the weekdays after cada,
  /// 4 the weekdays after los.
  private static var spanishWeekdayRepeatPattern: String {
    let day = "(?:\(spanishWeekdayNames))s?"
    let plural = "(?:lunes|martes|miercoles|jueves|viernes|sabados|domingos)"
    let days = "\(day)(?:\\s*(?:,|y)\\s*(?:(?:los|el)\\s+)?\(day)){0,6}"
    let plurals = "\(plural)(?:\\s*(?:,|y)\\s*(?:los\\s+)?\(plural)){0,6}"
    return "\(latinStart)(?:(?:todos\\s+los|todas\\s+las)\\s+(\(days))\(latinEnd)"
      + "|cada\\s+(?:(dos|2)\\s+)?(\(days))\(latinEnd)"
      + "|los\\s+(\(plurals))(?=[\\s.,;!?]*$))"
  }

  private static func spanishWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = (match.group(1) ?? match.group(3) ?? match.group(4) ?? "").split { !$0.isLetter }.map(String.init)
      .compactMap(spanishWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: match.group(2) == nil ? nil : 2, on: days)
  }

  /// "cada 3 días", "cada dos semanas", "cada tres meses", "cada quince días".
  /// Groups: 1 the count, 2 the unit.
  private static var spanishIntervalRepeatPattern: String {
    let counts = spanishNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    return "\(latinStart)cada\\s+(\\d{1,2}|\(counts))\\s+(dias|semanas|meses|anos)\(latinEnd)"
  }

  private static func spanishIntervalRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1)?.lowercased(), let count = number(countText) ?? spanishNumbers[countText],
      (1...99).contains(count), let unit = match.group(2)?.lowercased()
    else { return nil }
    let every = count == 1 ? nil : count
    switch unit {
    // Spanish counts a fortnight as fifteen days: "cada quince días" is every
    // two weeks.
    case "dias": return count == 15 ? weekly(every: 2, on: []) : Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "semanas": return weekly(every: every, on: [])
    case "meses": return monthly(every: every, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
  }

  /// "un día sí y otro no", "una semana sí y otra no", "un mes sí y otro no".
  private static func spanishAlternateRepeat(_ match: Match) -> Repeat? {
    switch match.group(1)?.lowercased() {
    case "dia": return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2))
    case "semana": return weekly(every: 2, on: [])
    case "mes": return monthly(every: 2, on: nil)
    default: return nil
    }
  }

  /// "el 5 de cada mes", "el día 5 de cada mes", "todos los 5 de cada mes",
  /// "cada mes el 5". Groups 1 and 2: the day of the month in each form.
  private static let spanishMonthDayRepeatPattern =
    #"\#(latinStart)(?:(?:todos\s+)?(?:el|los)\s+(?:dias?\s+)?(\d{1,2}|primero|1ro|1[ºo°])\s+de\s+cada\s+mes|(?:cada\s+mes|todos\s+los\s+meses)\s+(?:el\s+)?(?:dia\s+)?(\d{1,2}|primero|1ro|1[ºo°]))\#(latinEnd)"#

  /// The counts a repeat or a day phrase may spell out.
  private static let spanishNumbers = [
    "un": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
    "diez": 10, "once": 11, "doce": 12, "quince": 15,
  ]

  // MARK: - Days

  /// The weekday names without accents, Sunday first.
  private static let spanishWeekdays = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"]

  /// Each month's names without accents, January first: the name, then its
  /// abbreviations.
  private static let spanishMonths = [
    ["enero", "ene"], ["febrero", "feb"], ["marzo"], ["abril", "abr"], ["mayo", "may"], ["junio", "jun"],
    ["julio", "jul"], ["agosto", "ago"], ["septiembre", "setiembre", "sept", "sep"], ["octubre", "oct"],
    ["noviembre", "nov"], ["diciembre", "dic"],
  ]

  /// The days, without the word that may introduce them.
  private static var spanishDayPattern: String {
    let count = "(?:\\d{1,3}|un|una|dos|tres|quince)"
    return [
      #"hoy(?:\s+(?:mismo|temprano))?(?:\s+(?:por|en|a)\s+la\s+(?:manana|tarde|noche))?(?!\s+(?:en\s+)?dia(?![\p{Latin}\p{N}]))"#,
      #"esta\s+(?:manana|tarde|noche)"#,
      #"pasado\s+manana"#,
      #"manana(?:\s+(?:mismo|temprano))?(?:\s+(?:por|en|a)\s+la\s+(?:manana|tarde|noche))?"#,
      #"(?:en\s+)?(?:la\s+)?(?:proxima\s+semana|semana\s+(?:que\s+viene|proxima|entrante))"#,
      #"(?:(?:este|en\s+el)\s+)?(?:proximo\s+)?(?:fin\s+de\s+semana|finde)(?:\s+(?:que\s+viene|proximo))?"#,
      "(?:en|dentro\\s+de)\\s+\(count)\\s+(?:dias?|semanas?)",
      spanishDatePattern,
      // A weekday followed by pasado is the last one ("el lunes pasado").
      "(?:(?:este|esta|proximo|proxima)\\s+)?(?:\(spanishWeekdayNames))(?:\\s+(?:proximo|que\\s+viene))?"
        + "(?:\\s+(?:por|en|a)\\s+la\\s+(?:manana|tarde|noche))?(?!\\s+pasado)",
    ].joined(separator: "|")
  }

  /// "15 de octubre", "lunes 15 de octubre", "1º de octubre", "el primero de
  /// octubre", "15 oct.", "15 de octubre de 2027"; "día 15"; and a bare
  /// number after el or del ("el 15", "antes del 15"), as a day of the month.
  private static var spanishDatePattern: String {
    let months = spanishMonths.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    let day = #"(?:\d{1,2}[ºo°]?|1ro|primero)"#
    let notMore = #"(?![\p{N}%]|[:.,]\p{N})"#
    return "(?:(?:\(spanishWeekdayNames))\\s+)?(?:dia\\s+)?\(day)\\s+(?:de\\s+)?(?:\(months))\\.?(?:\\s+(?:de\\s+)?\\d{4})?"
      + "|dia\\s+\\d{1,2}\(notMore)"
      + "|(?<=\\bel\\s|\\bdel\\s)\\d{1,2}\(notMore)"
  }

  /// Words that, right before a day, make it part of the title instead: a
  /// plural weekday ("los lunes"), "la mañana", "cada mañana", "turno de
  /// mañana", "la reunión del lunes".
  private static let spanishNoDayAfter: Set<String> = [
    "de", "del", "la", "las", "los", "cada", "todo", "toda", "todos", "todas",
  ]

  /// Group 1: the word before the day (el, desde, a partir de) or nil; 2 the
  /// day.
  private static func spanishWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(2) else { return nil }
    if match.group(1) == nil {
      if let before = wordBefore(match), spanishNoDayAfter.contains(before) { return nil }
      if spanishIsPersonName(phrase, in: match) { return nil }
    }
    return spanishDay(phrase, in: match)
  }

  /// Group 1: "el" or nil; 2 the day.
  private static func spanishDue(_ match: Match) -> Day? {
    guard let phrase = match.group(2) else { return nil }
    if match.group(1) == nil, spanishIsPersonName(phrase, in: match) { return nil }
    return spanishDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  /// True for a capitalized "Domingo" that does not open the line: a person's
  /// name ("Llamar a Domingo"), not the day.
  private static func spanishIsPersonName(_ phrase: String, in match: Match) -> Bool {
    guard phrase.first?.isUppercase == true, spanishWeekdayIndex(phrase) == 0,
      let start = Range(match.result.range, in: match.source)?.lowerBound
    else { return false }
    return !match.source[..<start].allSatisfy(\.isWhitespace)
  }

  /// A day of the month alone ("el 15", "día 15") is a date only at the end
  /// of the line or before a word that can follow a date, never before "de"
  /// ("el 3 de la lista").
  private static func spanishDay(_ phrase: String, in match: Match) -> Day? {
    let words = normalizedPhrase(phrase)
    if let date = spanishDate(words) {
      let isBareDay = words.wholeMatch(of: /(?:dia )?\d{1,2}/) != nil
      if isBareDay, !spanishFollowsAsDetail(match, excluding: ["de", "del"]) { return nil }
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let todayWeekday = match.todayWeekday
    if let relative = words.wholeMatch(of: /(?:en|dentro de) (\w+) (dia|dias|semana|semanas)/) {
      let countText = String(relative.output.1)
      guard let count = number(countText) ?? spanishNumbers[countText] else { return nil }
      return Day(offset: relative.output.2.hasPrefix("semana") ? count * 7 : count)
    }
    if words.hasPrefix("hoy") { return Day(offset: 0, isEvening: words.hasSuffix("noche")) }
    if words == "esta noche" { return Day(offset: 0, isEvening: true) }
    if words == "esta manana" || words == "esta tarde" { return Day(offset: 0) }
    if words == "pasado manana" { return Day(offset: 2) }
    if words.hasPrefix("manana") { return Day(offset: 1, isEvening: words.hasSuffix("noche")) }
    let isNext = words.contains("proxim") || words.contains("que viene") || words.contains("entrante")
    if words.contains("fin de semana") || words.contains("finde") {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    if words.contains("semana") { return isNext ? Day(offset: 7) : nil }
    let parts = words.split(separator: " ").map(String.init)
    guard let weekday = parts.lazy.compactMap(spanishWeekdayIndex).first else { return nil }
    let isEvening = words.hasSuffix("noche")
    if isNext {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if parts.first == "este" || parts.first == "esta" {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// A written-out date, maybe after its weekday: "15 de octubre", "lunes 1º
  /// de octubre de 2027"; or a day of the month alone ("día 15", "15").
  private static func spanishDate(_ words: String) -> ExplicitDate? {
    if let match = words.wholeMatch(
      of: /(?:\p{L}+ )?(?:dia )?(\d{1,2}|1ro|primero)[ºo°]? (?:de )?(\p{L}+)\.?(?: (?:de )?(\d{4}))?/),
      let day = spanishDayNumber(String(match.output.1)),
      let month = spanishMonths.firstIndex(where: { $0.contains(String(match.output.2)) })
    {
      return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
    }
    if let match = words.wholeMatch(of: /(?:dia )?(\d{1,2})/), let day = number(match.output.1) {
      return ExplicitDate(day: day)
    }
    return nil
  }

  /// The day of the month "5", "1º", "1ro", or "primero" names.
  private static func spanishDayNumber(_ text: String) -> Int? {
    let lower = text.lowercased()
    return ["primero", "1ro", "1º", "1o", "1°"].contains(lower) ? 1 : number(lower)
  }

  /// The weekday a word names, 0 = Sunday, singular or plural ("sábados").
  private static func spanishWeekdayIndex(_ word: String) -> Int? {
    let lower = word.lowercased()
    return spanishWeekdays.firstIndex { lower == $0 || lower == $0 + "s" }
  }

  // MARK: - Due

  /// "para el viernes", "antes del viernes", "hasta mañana", "vence el 15",
  /// "fecha límite: 15 de octubre", "plazo: viernes", "a más tardar el
  /// viernes". Groups: 1 the article el or nil, 2 the day.
  private static var spanishDuePattern: String {
    #"\#(latinStart)(?:antes\s+de(?:l)?|para|hasta|vence|vencimiento|fecha\s+limite|plazo|limite|a\s+mas\s+tardar|no\s+mas\s+tarde\s+de(?:l)?)(?:\s*:\s*|\s+)(?:(el)\s+)?(\#(spanishDayPattern))\#(latinEnd)"#
  }
}
