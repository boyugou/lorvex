import Foundation

extension LorvexCaptureVocabulary {
  /// French, read for a user who reads French. A word needs a boundary of
  /// Latin letters and digits on both sides, as in English. Accents may be
  /// left out ("apres-demain", "fevrier"), and an apostrophe may be straight
  /// or curly ("aujourd’hui").
  ///
  /// French writes a clock time with the letter h, from 0h to 23h ("15h",
  /// "15h30", "15 h 30"), so an hour count written that way is a time. A
  /// length says so with pendant or durant ("pendant 2h"), with minutes
  /// ("1h30min"), or with a word ("2 heures"). An hour after "de" with no end
  /// can be either ("le train de 9h", "une réunion de 2h"), so it stays in the
  /// title, as does an hour after avant, d'ici, or jusqu'à, which names a
  /// deadline rather than a time to start.
  ///
  /// - Day: aujourd'hui, ce matin, cet après-midi, ce soir, cette nuit,
  ///   demain, demain matin, demain soir, après-demain, the weekday names
  ///   (alone, after ce, or before prochain), la semaine prochaine,
  ///   ce week-end, le week-end prochain, dans 3 jours, dans une semaine,
  ///   each maybe after le, de, dès, or à partir de; a date: 5 octobre, le
  ///   1er octobre, lundi 5 octobre, 5 oct., 5 octobre 2027. A weekday alone
  ///   means the next such day, a full week ahead when it names today; after
  ///   ce it is this week's, and before prochain next week's, weeks starting
  ///   on Monday. Ce soir, cette nuit, and demain soir are evenings. A date
  ///   written in digits ("5/10") is not read, since the order of its day and
  ///   month depends on the region.
  /// - Date range: du 3 au 5 mai, du 3 mai au 5 mai, du 30 mai au 2 juin, du
  ///   1er au 5 mai, du lundi 3 au mercredi 5 mai, du 3 mai jusqu'au 5 mai,
  ///   entre le 3 et le 5 mai, entre le 3 mai et le 5 mai, 3-5 mai, 3 mai - 5
  ///   mai, 3 au 5 mai, each maybe with a year after the end ("du 3 au 5 mai
  ///   2027"). The first day is the planned day and the last the due day, so
  ///   another day phrase stays in the title. A day written without its month
  ///   takes the month of the end; the end must be after the start ("du 5 au 3
  ///   mai" stays in the title whole), and an end in an earlier month falls in
  ///   the next year. "Et" joins two days only after entre. A range with no
  ///   month ("du 3 au 5") is not read, since a lone day of the month is not a
  ///   date here, and "du lundi au vendredi" is a repeat. A day alone opens a
  ///   range joined by a dash only when the dash touches both sides or an
  ///   opening word comes first: "Sprint 12 - 20 mai" names a sprint and a
  ///   date.
  /// - Repeat: tous les jours, chaque jour, un jour sur deux, en semaine, tous
  ///   les jours ouvrés, du lundi au vendredi, toutes les semaines, chaque
  ///   semaine, une semaine sur deux, tous les quinze jours (every two weeks,
  ///   as French counts a fortnight), tous les lundis, chaque lundi, tous les
  ///   lundis et jeudis, les lundis, un lundi sur deux, tous les 3 jours,
  ///   toutes les 2 semaines, tous les trois mois, tous les mois, le 5 de
  ///   chaque mois, tous les ans, chaque année; quotidiennement,
  ///   hebdomadairement, mensuellement, and annuellement at the end of the
  ///   line.
  /// - Due: a day after avant, d'ici, pour, jusqu'à, échéance, or date limite
  ///   ("pour vendredi"), or before au plus tard.
  /// - Time: 15h, 15h30, 15 h 30, à 9h, vers 18h, dès 8h, à partir de 14h, 9h
  ///   du matin, 3h de l'après-midi, 8h du soir, à 3 heures, midi, ce midi, à
  ///   minuit; a range: de 14h à 16h, 14h-16h30, de 14 à 16h, entre 14h et
  ///   16h, de 9h à midi. A time from 1 to 6 o'clock with no part of the day
  ///   is the afternoon, unless written with a leading zero ("06h"). Du soir
  ///   and de la nuit run past midnight, as the evening of a day does.
  /// - Length: pendant 2h, durant 1h30, 1h30min, 1,5 h, 30 min, 30 minutes, 2
  ///   heures, 1 heure 30, 2 heures et demie, une heure, une demi-heure, une
  ///   heure et demie, un quart d'heure, trois quarts d'heure.
  /// - Priority: priorité haute, haute priorité, priorité moyenne, priorité
  ///   basse, basse priorité, and "urgente" at the end of the line or opening
  ///   it before a colon or comma; "urgent" reads as in English.
  static let french = LorvexCaptureVocabulary(
    readingForm: unaccentedForMatching,
    priority: [Rule(pattern: frenchPriorityPattern, read: frenchPriority)],
    dateRange: [Rule(pattern: frenchDateRangePattern, read: frenchDateRange)],
    length: [Rule(pattern: frenchLengthPattern, read: frenchLength)],
    time: [
      Rule(pattern: frenchRangePattern, read: frenchRange),
      Rule(pattern: frenchTimePattern, read: frenchTime),
    ],
    repeats: [
      // The working days before every day, which would leave "ouvrés" in the
      // title.
      Rule(
        pattern:
          #"\#(latinStart)(?:tous\s+les\s+jours\s+(?:ouvres|ouvrables|de\s+(?:la\s+)?semaine)|chaque\s+jour\s+(?:ouvre|ouvrable|de\s+(?:la\s+)?semaine)|en\s+semaine|du\s+lundi\s+au\s+vendredi)\#(latinEnd)"#
      ) { _ in workdays },
      Rule(pattern: frenchWeekdayRepeatPattern, read: frenchWeekdayRepeat),
      Rule(pattern: #"\#(latinStart)un\s+(\#(frenchWeekdayNames))\s+sur\s+deux\#(latinEnd)"#) { match in
        match.group(1).flatMap(frenchWeekdayIndex).map { weekly(every: 2, on: [$0]) }
      },
      Rule(pattern: frenchIntervalRepeatPattern, read: frenchIntervalRepeat),
      Rule(pattern: #"\#(latinStart)un\s+jour\s+sur\s+deux\#(latinEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2))
      },
      Rule(pattern: #"\#(latinStart)une\s+semaine\s+sur\s+deux\#(latinEnd)"#) { _ in weekly(every: 2, on: []) },
      Rule(pattern: #"\#(latinStart)un\s+mois\s+sur\s+deux\#(latinEnd)"#) { _ in monthly(every: 2, on: nil) },
      Rule(pattern: cadencePattern("tous\\s+les\\s+jours|chaque\\s+jour", adverb: "quotidiennement")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily))
      },
      Rule(pattern: cadencePattern("toutes\\s+les\\s+semaines|chaque\\s+semaine", adverb: "hebdomadairement")) { _ in
        weekly(every: nil, on: [])
      },
      // A day of the month before every month, which would leave "le 5" in the
      // title.
      Rule(pattern: frenchMonthDayRepeatPattern) { match in
        (match.group(1) ?? match.group(2) ?? match.group(3)).flatMap(frenchDayNumber).flatMap {
          monthly(every: nil, on: $0)
        }
      },
      Rule(pattern: cadencePattern("tous\\s+les\\s+mois|chaque\\s+mois", adverb: "mensuellement")) { _ in
        monthly(every: nil, on: nil)
      },
      Rule(pattern: cadencePattern("tous\\s+les\\s+ans|chaque\\s+(?:annee|an)", adverb: "annuellement")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [
      Rule(
        pattern:
          #"\#(latinStart)(?:avant|d['’]ici|pour|jusqu['’](?:a|au)|echeance\s*:?|date\s+limite\s*:?)\s+(?:le\s+)?(\#(frenchDayPattern))\#(latinEnd)"#,
        read: frenchDue),
      Rule(pattern: #"\#(latinStart)(\#(frenchDayPattern))\s+au\s+plus\s+tard\#(latinEnd)"#, read: frenchDue),
    ],
    when: [
      Rule(
        pattern: #"\#(latinStart)(?:(?:le|de|des|a\s+partir\s+de)\s+)?(\#(frenchDayPattern))\#(latinEnd)"#,
        read: frenchWhen)
    ],
    writesClockTimesWithH: true)

  // MARK: - Priority

  /// Group 1: a written priority; "urgente" has no group.
  private static let frenchPriorityPattern =
    #"\#(latinStart)(priorite\s+(?:haute|elevee|maximale|moyenne|normale|basse|faible)|(?:haute|basse)\s+priorite)\#(latinEnd)|(?<=\s)urgente(?=\s*$)|^\s*urgente(?=\s*[:,，：])"#

  private static func frenchPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("moyenne") || phrase.contains("normale") { return .p2 }
    if phrase.contains("basse") || phrase.contains("faible") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "pendant 2h", "1h30min", "1,5 h", "2 heures et demie", "2 heures",
  /// "30 min", or a length in words, each maybe after pendant or durant.
  /// Groups: 1 pendant or durant; 2 and 3 the hours and minutes of "1h30min";
  /// 4 hours written with h and 5 their minutes ("2h", "1h30", "1,5h"); 6 the
  /// hours of "2 heures et demie"; 7 hours written as a word and 8 their
  /// minutes ("1 heure 30"); 9 minutes; 10 a length in words.
  private static let frenchLengthPattern =
    #"\#(latinStart)(?:(pendant|durant)\s+)?(?:(\d+)\s*h\s*(\d{1,2})\s*(?:minutes?|min|mn)|(\d+(?:[.,]\d+)?)\s*h(?:\s*(\d{2}))?|(\d+)\s*heures?\s+et\s+demie|(\d+(?:[.,]\d+)?)\s*heures?(?:\s+(\d{1,2})(?:\s*(?:minutes?|min|mn))?)?|(\d+)\s*(?:minutes?|min|mn)|(une\s+demi[-\s]?heure|une\s+heure\s+et\s+demie|une\s+heure|un\s+quart\s+d['’]heure|trois\s+quarts\s+d['’]heure))(?![\p{Latin}\p{N}])(?!\s+(?:du\s+(?:matin|soir)|de\s+l['’]apres|de\s+la\s+nuit))"#

  private static func frenchLength(_ match: Match) -> Int? {
    let isLed = match.group(1) != nil
    // An amount after à, vers, dès, or dans names a time or a moment, not a
    // length ("à 3 heures", "dans 30 min").
    if !isLed, let before = wordBefore(match), ["a", "vers", "des", "dans"].contains(before) { return nil }
    if let hours = match.group(2).flatMap(number), let minutes = match.group(3).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(4), let hours = decimalAmount(amountText) {
      // A whole hour written with h is a clock time unless pendant or durant
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
    case "une demi heure", "une demiheure": return 30
    case "une heure et demie": return 90
    case "une heure": return 60
    case let phrase? where phrase.hasPrefix("un quart"): return 15
    case let phrase? where phrase.hasPrefix("trois quarts"): return 45
    default: return nil
    }
  }

  // MARK: - Time

  /// The part of the day written after a clock time: du matin, de
  /// l'après-midi (or de l'aprem), du soir, de la nuit.
  private static let frenchDayPart = #"du\s+matin|de\s+l['’]apres[-\s]?midi|de\s+l['’]aprem|du\s+soir|de\s+la\s+nuit"#

  /// "15h30", "à 9h du matin", "à 3 heures", "midi", "à minuit". Groups: 1 the
  /// word before the hour (à, vers, dès, à partir de), 2 "@", 3 hour, 4
  /// minute, 5 part of the day; 6, 7, and 8 the hour, minute, and part of the
  /// day of "à 3 heures"; 9 midi; 10 minuit. "Midi" after "après" (the
  /// afternoon) or "le" (the south of France) is not noon.
  private static let frenchTimePattern =
    #"\#(latinStart)(?:(a\s+partir\s+de|a|vers|des)\s+|(@)\s*)?(?<![\p{N}:.,])(\d{1,2})\s*h(?:\s*(\d{2}))?(?![\p{Latin}\p{N}])(?:\s+(\#(frenchDayPart)))?|\#(latinStart)(?:a|vers|des)\s+(\d{1,2}|une)\s+heures?(?:\s+(\d{2}))?(?![\p{Latin}\p{N}])(?:\s+(\#(frenchDayPart)))?|\#(latinStart)(?:(?:a|vers|des|ce)\s+)?(?<!apres[-\s])(?<!apres)(?<!le\s)(midi)(?![\p{Latin}\p{N}'’-])|\#(latinStart)(?:a|vers|des)\s+(minuit)\#(latinEnd)"#

  private static func frenchTime(_ match: Match) -> ClockTime? {
    if match.group(9) != nil { return ClockTime(minutes: 12 * 60) }
    if match.group(10) != nil { return ClockTime(minutes: 0, isAfterMidnight: true) }
    // An hour after avant, d'ici, or jusqu'à is a deadline, which a task's
    // time cannot hold.
    if let before = wordBefore(match), ["avant", "d'ici", "jusqu'a"].contains(before) { return nil }
    let hourText: String
    let minuteText: String?
    let part: String?
    if let text = match.group(3) {
      // An hour after "de" with no end is a time ("le train de 9h") or a
      // length ("une réunion de 2h").
      if match.group(1) == nil, match.group(2) == nil, wordBefore(match) == "de" { return nil }
      hourText = text
      minuteText = match.group(4)
      part = match.group(5)
    } else if let text = match.group(6) {
      hourText = text
      minuteText = match.group(7)
      part = match.group(8)
    } else {
      return nil
    }
    guard let hour = hourText.lowercased() == "une" ? 1 : number(hourText) else { return nil }
    let minute = minuteText.flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    guard let part = part.map(normalizedPhrase) else {
      return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
    }
    guard (0...12).contains(hour) else { return nil }
    if part.hasSuffix("matin") { return ClockTime(minutes: (hour % 12) * 60 + minute) }
    if part.hasSuffix("midi") || part.hasSuffix("aprem") { return ClockTime(minutes: (hour % 12 + 12) * 60 + minute) }
    return nightTime(hour: hour, minute: minute)
  }

  // MARK: - Time range

  /// One side of a range: an hour with h and maybe minutes, a colon time,
  /// midi, or minuit.
  private static let frenchRangeSide = #"\d{1,2}\s*h(?:\s*\d{2})?|\d{1,2}[：:]\d{2}|midi|minuit"#

  /// "de 14h à 16h", "14h-16h30", "de 14 à 16h", "entre 14h et 16h", "de 9h à
  /// midi". The start may be an hour without h when the end has one. Groups:
  /// 1 de, entre, or à partir de; 2 the start; 3 the word or dash between; 4
  /// the end.
  private static let frenchRangePattern =
    #"\#(latinStart)(?:(de|entre|a\s+partir\s+de)\s+)?(\#(frenchRangeSide)|\d{1,2})\s*(-|–|—|a|jusqu['’]a|et)\s*(\#(frenchRangeSide))(?![\p{Latin}\p{N}:])"#

  private static func frenchRange(_ match: Match) -> ClockTime? {
    // "Et" joins a range only after entre: "à 14h et 16h" names two times.
    guard (match.group(3)?.lowercased() == "et") == (match.group(1)?.lowercased() == "entre"),
      let start = match.group(2).flatMap(frenchRangeSideTime), let end = match.group(4).flatMap(frenchRangeSideTime)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  private static func frenchRangeSideTime(_ text: String) -> ClockTime? {
    switch text.lowercased() {
    case "midi": return ClockTime(minutes: 12 * 60)
    case "minuit": return ClockTime(minutes: 0, isAfterMidnight: true)
    default: break
    }
    return colonTime(text) ?? hourTime(text)
  }

  // MARK: - Date range

  /// "du 3 au 5 mai", "du 3 mai au 5 mai", "du lundi 3 au mercredi 5 mai", "du
  /// 3 mai jusqu'au 5 mai", "entre le 3 et le 5 mai", "3-5 mai", "3 mai - 5
  /// mai", "3 au 5 mai". The start is a date or a day alone ("3", "lundi 3",
  /// "1er"); the end is a date, whose month the start takes when it has none.
  /// Groups: 1 du, de, or entre, if any; 2 the start; 3 a dash between the
  /// sides; 4 au, jusqu'au, or et between them; 5 the end.
  private static var frenchDateRangePattern: String {
    let weekday = "(?:(?:\(frenchWeekdayNames))\\s+)?"
    let bareDay = "\(weekday)(?:\\d{1,2}|1er|premier)(?![\\p{Latin}\\p{N}:])"
    return
      #"\#(latinStart)(?:(du|de|entre)\s+(?:le\s+)?)?(\#(frenchDatePattern)|\#(bareDay))(?:\s*([-–—])\s*|\s+(au|jusqu['’]au|et)\s+)(?:le\s+)?(\#(frenchDatePattern))\#(latinEnd)"#
  }

  private static func frenchDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = frenchRangeDate(startText), let end = frenchRangeDate(endText)
    else { return nil }
    // "Et" joins the sides only after entre ("le 3 mai et le 5 mai" names two
    // days); "au" and "jusqu'au" join them after du or de, and with no
    // opening word ("3 au 5 mai").
    if let word = match.group(4)?.lowercased() {
      let lead = match.group(1)?.lowercased()
      guard (word == "et") == (lead == "entre"), lead != nil || joinsWithoutOpeningWord(match, end: end) else {
        return nil
      }
    }
    if start.month == nil, match.group(1) == nil, match.group(3) != nil, !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 mai", "lundi 1er octobre 2027"), or a
  /// day alone ("5", "lundi 5", "1er"), which has no month.
  private static func frenchRangeDate(_ text: String) -> ExplicitDate? {
    let words = normalizedPhrase(text)
    if let date = frenchDate(words) { return date }
    guard let match = words.wholeMatch(of: /(?:\p{L}+ )?(\d{1,2}|1er|premier)/),
      let day = frenchDayNumber(String(match.output.1))
    else { return nil }
    return ExplicitDate(day: day)
  }

  // MARK: - Repeat

  /// The weekday names, longest first, as a pattern.
  private static var frenchWeekdayNames: String {
    frenchWeekdays.sorted { $0.count > $1.count }.joined(separator: "|")
  }

  /// "tous les lundis", "chaque lundi", "tous les lundis et jeudis", and "les
  /// lundis", whose plural says the day recurs. Group 1 or 2: the weekdays.
  private static var frenchWeekdayRepeatPattern: String {
    let day = "(?:\(frenchWeekdayNames))s?"
    let plural = "(?:\(frenchWeekdayNames))s"
    let days = "\(day)(?:\\s*(?:,|et)\\s*(?:les\\s+)?\(day))*"
    let plurals = "\(plural)(?:\\s*(?:,|et)\\s*(?:les\\s+)?\(plural))*"
    return "\(latinStart)(?:(?:tous\\s+les|chaque)\\s+(\(days))|les\\s+(\(plurals)))\(latinEnd)"
  }

  private static func frenchWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = (match.group(1) ?? match.group(2) ?? "").split { !$0.isLetter }.map(String.init)
      .compactMap(frenchWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "tous les 3 jours", "toutes les deux semaines", "tous les trois mois".
  /// Groups: 1 the count, 2 the unit.
  private static var frenchIntervalRepeatPattern: String {
    let counts = frenchNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    return "\(latinStart)(?:tous|toutes)\\s+les\\s+(\\d{1,2}|\(counts))\\s+(jours|semaines|mois|ans|annees)\(latinEnd)"
  }

  private static func frenchIntervalRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1)?.lowercased(), let count = number(countText) ?? frenchNumbers[countText],
      (1...99).contains(count), let unit = match.group(2)?.lowercased()
    else { return nil }
    let every = count == 1 ? nil : count
    switch unit {
    // French counts a fortnight as fifteen days: "tous les quinze jours" is
    // every two weeks.
    case "jours": return count == 15 ? weekly(every: 2, on: []) : Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "semaines": return weekly(every: every, on: [])
    case "mois": return monthly(every: every, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
  }

  /// "le 5 de chaque mois", "tous les 5 du mois", "chaque mois le 5". Groups
  /// 1, 2, and 3: the day of the month in each form.
  private static let frenchMonthDayRepeatPattern =
    #"\#(latinStart)(?:le\s+(\d{1,2}|1er|premier)\s+(?:de\s+)?chaque\s+mois|tous\s+les\s+(\d{1,2}|1er|premier)\s+du\s+mois|(?:chaque|tous\s+les)\s+mois\s+le\s+(\d{1,2}|1er|premier))\#(latinEnd)"#

  /// The counts a repeat or a day phrase may spell out.
  private static let frenchNumbers = [
    "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9,
    "dix": 10, "onze": 11, "douze": 12, "quinze": 15,
  ]

  // MARK: - Days

  /// The weekday names, Sunday first.
  private static let frenchWeekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

  /// Each month's names without accents, January first: the name, then its
  /// abbreviations.
  private static let frenchMonths = [
    ["janvier", "janv"], ["fevrier", "fevr", "fev"], ["mars"], ["avril", "avr"], ["mai"], ["juin"],
    ["juillet", "juil"], ["aout"], ["septembre", "sept"], ["octobre", "oct"], ["novembre", "nov"],
    ["decembre", "dec"],
  ]

  /// The days, without the word that may introduce them.
  private static var frenchDayPattern: String {
    let count = "(?:\\d{1,3}|un|une|deux|trois|quinze)"
    return #"aujourd['’]hui|ce\s+matin|cet\s+apres[-\s]?midi|ce\s+soir|cette\s+nuit|apres[-\s]?demain"#
      + #"|demain(?:\s+(?:matin|soir|apres[-\s]?midi))?|(?:la\s+)?semaine\s+prochaine"#
      + #"|(?:le\s+)?week[-\s]?end\s+prochain|(?:ce\s+|le\s+)?week[-\s]?end"#
      + "|dans\\s+\(count)\\s+(?:jours?|semaines?)|\(frenchDatePattern)"
      + "|(?:ce\\s+)?(?:\(frenchWeekdayNames))(?:\\s+prochain)?"
  }

  /// "5 octobre", "1er octobre", "lundi 5 octobre", "5 oct.", "5 octobre 2027".
  private static var frenchDatePattern: String {
    let months = frenchMonths.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    return "(?:(?:\(frenchWeekdayNames))\\s+)?(?:\\d{1,2}|1er|premier)\\s+(?:\(months))\\.?(?:\\s+\\d{4})?"
  }

  private static func frenchWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { frenchDay($0, todayWeekday: match.todayWeekday, today: match.today) }
  }

  private static func frenchDue(_ match: Match) -> Day? {
    frenchWhen(match).map { Day(offset: $0.offset) }
  }

  private static func frenchDay(_ phrase: String, todayWeekday: Int, today: Date?) -> Day? {
    let words = normalizedPhrase(phrase).replacingOccurrences(of: "weekend", with: "week end")
      .replacingOccurrences(of: "apresmidi", with: "apres midi").replacingOccurrences(of: "apresdemain", with: "apres demain")
    if let date = frenchDate(words) {
      guard let today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let weekend = weekendOffset(todayWeekday: todayWeekday)
    switch words {
    case "aujourd'hui", "ce matin", "cet apres midi": return Day(offset: 0)
    case "ce soir", "cette nuit": return Day(offset: 0, isEvening: true)
    case "demain", "demain matin", "demain apres midi": return Day(offset: 1)
    case "demain soir": return Day(offset: 1, isEvening: true)
    case "apres demain": return Day(offset: 2)
    case "semaine prochaine", "la semaine prochaine": return Day(offset: 7)
    case "week end", "ce week end", "le week end": return Day(offset: weekend)
    case "week end prochain", "le week end prochain": return Day(offset: weekend + 7)
    default: break
    }
    if let match = words.wholeMatch(of: /dans (\w+) (jour|jours|semaine|semaines)/) {
      let countText = String(match.output.1)
      guard let count = number(countText) ?? frenchNumbers[countText] else { return nil }
      return Day(offset: match.output.2.hasPrefix("semaine") ? count * 7 : count)
    }
    let parts = words.split(separator: " ").map(String.init)
    guard let weekday = parts.lazy.compactMap(frenchWeekdayIndex).first else { return nil }
    if parts.first == "ce" { return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday)) }
    if parts.last == "prochain" { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday)) }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday))
  }

  /// A written-out date, maybe after its weekday: "5 octobre", "lundi 1er
  /// octobre 2027".
  private static func frenchDate(_ words: String) -> ExplicitDate? {
    guard let match = words.wholeMatch(of: /(?:\p{L}+ )?(\d{1,2}|1er|premier) (\p{L}+)\.?(?: (\d{4}))?/),
      let day = frenchDayNumber(String(match.output.1)),
      let month = frenchMonths.firstIndex(where: { $0.contains(String(match.output.2)) })
    else { return nil }
    return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
  }

  /// The day of the month "5", "1er", or "premier" names.
  private static func frenchDayNumber(_ text: String) -> Int? {
    let lower = text.lowercased()
    return lower == "1er" || lower == "premier" ? 1 : number(lower)
  }

  /// The weekday a word names, 0 = Sunday, singular or plural ("lundis").
  private static func frenchWeekdayIndex(_ word: String) -> Int? {
    let lower = word.lowercased()
    return frenchWeekdays.firstIndex { lower == $0 || lower == $0 + "s" }
  }
}
