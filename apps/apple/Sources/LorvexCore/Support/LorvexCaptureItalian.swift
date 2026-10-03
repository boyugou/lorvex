import Foundation

extension LorvexCaptureVocabulary {
  /// Italian, read for a user who reads Italian. A word needs a boundary of
  /// Latin letters, digits, and apostrophes on both sides, as in English.
  /// Accents may be left out ("lunedi", "priorita"), and an apostrophe may be
  /// straight or curly ("all’una", "mezz’ora").
  ///
  /// Italian says a clock time with "alle" or "ore" ("alle 15", "ore 15:30"),
  /// writing the minutes after a colon or a point ("alle 15.30"), and does not
  /// write it with the letter h, so an hour count written with h alone ("2h",
  /// "1h30") is a length, as in English, and, unlike French and Portuguese,
  /// this vocabulary does not turn "2h" into a clock time. A bare hour after
  /// "alle" is a time only when the line goes on with a word that can follow
  /// a time ("alle 3 con Marco", "alle 3 domani") rather than a counted noun
  /// ("alle 3 amiche"). An hour after entro, fino a, or per is a deadline,
  /// which a task's time cannot hold, so it stays in the title.
  ///
  /// English is read beside Italian, so a detail that needs no Italian word is
  /// left to English, which reads its own "at 3pm", "from 3-4pm", "for 2h", or
  /// "this weekend" whole: a time with no Italian word ("3pm", "15:30"), a
  /// range with a dash ("14:00-16:30"), an amount after "for", and "weekend"
  /// without an article or questo ("nel weekend" is Italian, "weekend" alone
  /// is not).
  ///
  /// A weekday written alone is the coming one ("lunedì"), while the same name
  /// after an article is a habit ("il lunedì", "i sabati"): it repeats at the
  /// end of a line and otherwise stays in the title.
  ///
  /// - Day: oggi, stamattina, oggi pomeriggio, questo pomeriggio, stasera,
  ///   questa sera, stanotte, domani, domani mattina, domani sera,
  ///   dopodomani, the weekday names (alone, after questo, or with prossimo or
  ///   che viene, each maybe followed by mattina, pomeriggio, sera, or notte),
  ///   la settimana prossima, la prossima settimana, il fine settimana, nel
  ///   weekend, questo weekend, il weekend prossimo, tra 3 giorni, fra una
  ///   settimana, each maybe after il, da, dal, or a partire da; a date: 15
  ///   ottobre, il 15 ottobre, lunedì 15 ottobre, 1º ottobre, il primo
  ///   ottobre, 15 ott., 15 ottobre 2027, and a day of the month alone after
  ///   il, al, or dal ("il 15"), which counts only at the end of the line or
  ///   before a word that can follow a date. A weekday alone means the next
  ///   such day, a full week ahead when it names today; after questo it is
  ///   this week's, and with prossimo or che viene next week's, weeks starting
  ///   on Monday. Stasera, stanotte, domani sera, and sabato sera are
  ///   evenings. A weekday after di or del ("la riunione del lunedì"), a
  ///   weekday followed by scorso or passato ("lunedì scorso"), and a
  ///   capitalized "Domenica" that does not open the line (a name) are left
  ///   in the title. A date written in digits ("15/10") is not read, since
  ///   the order of its day and month depends on the region.
  /// - Repeat: ogni giorno, tutti i giorni, ogni mattina, ogni giorno
  ///   lavorativo, nei giorni feriali, dal lunedì al venerdì, ogni settimana,
  ///   tutte le settimane, ogni due settimane, ogni quindici giorni (every two
  ///   weeks, as Italian counts a fortnight), ogni lunedì, tutti i lunedì,
  ///   ogni lunedì e giovedì, tutti i lunedì e i giovedì, il lunedì at the end
  ///   of the line (a habitual weekday before another word is part of the
  ///   title), un lunedì sì e uno no, a giorni alterni, ogni 3 giorni, ogni
  ///   tre mesi, ogni mese, il 5 di ogni mese, ogni mese il 5, ogni 5 del
  ///   mese, ogni anno, tutti gli anni; quotidianamente, settimanalmente,
  ///   mensilmente, and annualmente at the end of the line.
  /// - Due: a day after entro, per, fino a, scade, scadenza, or data limite
  ///   ("entro venerdì"), or before al più tardi.
  /// - Time: alle 15, alle 15:30, alle 15.30, alle 9 e 30, ore 15, alle 3 del
  ///   pomeriggio, alle 9 di mattina, alle 8 di sera, alle 3 e mezza, alle 3 e
  ///   un quarto, alle 4 meno un quarto, alle 3 in punto, alle 3 pm, all'una,
  ///   verso le 6, dalle 8, 3 del pomeriggio, mezzogiorno, a mezzanotte; a
  ///   range: dalle 3 alle 4, dalle 14 alle 16:30, tra le 3 e le 4, dalle 9 a
  ///   mezzogiorno. A time from 1 to 6 o'clock with no part of the day is the
  ///   afternoon, unless written with a leading zero ("06:30"). Di mattina
  ///   and del mattino keep the morning (12 di mattina is noon), del
  ///   pomeriggio and di sera put the hour in the afternoon or the evening
  ///   ("alle 3 di sera" is 15:00), and di notte runs past midnight from 12 to
  ///   5 ("alle 3 di notte" is 03:00 of the next day). A range of two bare
  ///   hours counts after dalle, da, or tra le, and only when the line goes
  ///   on with a word that can follow a time, so "da 3 a 5 capitoli" is a
  ///   title. "Mezzogiorno" and "mezzanotte" after il, la, del, or di ("il
  ///   mezzogiorno d'Italia") are not times.
  /// - Length: per 2 ore, durata 2 ore, di 2 ore, 2h, 1h30, 1h30min, 1,5 ore,
  ///   30 min, 30 minuti, 2 ore, 2 ore e mezza, 1 ora e 30, un'ora, due ore,
  ///   mezz'ora, un'ora e mezza, un quarto d'ora, tre quarti d'ora. An amount
  ///   after tra, fra, in, dopo, entro, ogni, prima di, più di, meno di, or a
  ///   lead such as alle names a moment, an interval, or a deadline, not a
  ///   length ("tra 2 ore", "ogni 8 ore").
  /// - Priority: priorità alta, alta priorità, priorità media, priorità
  ///   bassa, bassa priorità (also massima, elevata, normale, and minima), and
  ///   "urgente" at the end of the line or opening it before a colon or
  ///   comma.
  static let italian = LorvexCaptureVocabulary(
    readingForm: unaccentedForMatching,
    priority: [Rule(pattern: italianPriorityPattern, read: italianPriority)],
    length: [Rule(pattern: italianLengthPattern, read: italianLength)],
    time: [
      Rule(pattern: italianFromToPattern, read: italianRange),
      Rule(pattern: italianBetweenPattern, read: italianRange),
      Rule(pattern: italianTimePattern, read: italianTime),
    ],
    repeats: [
      // The working days before every day, which would leave "lavorativo" in
      // the title.
      Rule(
        pattern:
          #"\#(latinStart)(?:ogni\s+giorno\s+(?:lavorativo|feriale)|tutti\s+i\s+giorni\s+(?:lavorativi|feriali)|nei\s+giorni\s+(?:lavorativi|feriali)|dal\s+lunedi\s+al\s+venerdi)\#(latinEnd)"#
      ) { _ in workdays },
      // A day of the month before every month, which would leave "il 5" in
      // the title.
      Rule(pattern: italianMonthDayRepeatPattern) { match in
        (match.group(1) ?? match.group(2) ?? match.group(3)).flatMap(italianDayNumber).flatMap {
          monthly(every: nil, on: $0)
        }
      },
      Rule(pattern: italianWeekdayRepeatPattern, read: italianWeekdayRepeat),
      Rule(pattern: italianIntervalRepeatPattern, read: italianIntervalRepeat),
      Rule(pattern: italianAlternatePattern, read: italianAlternateRepeat),
      Rule(pattern: #"\#(latinStart)a\s+giorni\s+alterni\#(latinEnd)"#) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2))
      },
      Rule(pattern: #"\#(latinStart)a\s+settimane\s+alterne\#(latinEnd)"#) { _ in weekly(every: 2, on: []) },
      Rule(
        pattern: cadencePattern(
          "ogni\\s+giorno|tutti\\s+i\\s+giorni|ogni\\s+(?:mattina|pomeriggio|sera|notte)|tutte\\s+le\\s+(?:mattine|sere|notti)|tutti\\s+i\\s+pomeriggi",
          adverb: "(?:quotidianamente|giornalmente)")
      ) { _ in Repeat(rule: TaskRecurrenceRule(freq: .daily)) },
      Rule(pattern: cadencePattern("ogni\\s+settimana|tutte\\s+le\\s+settimane", adverb: "settimanalmente")) { _ in
        weekly(every: nil, on: [])
      },
      Rule(pattern: cadencePattern("ogni\\s+mese|tutti\\s+i\\s+mesi", adverb: "mensilmente")) { _ in
        monthly(every: nil, on: nil)
      },
      Rule(pattern: cadencePattern("ogni\\s+anno|tutti\\s+gli\\s+anni", adverb: "annualmente")) { _ in
        Repeat(rule: TaskRecurrenceRule(freq: .yearly))
      },
    ],
    due: [
      Rule(pattern: italianDuePattern, read: italianDue),
      Rule(
        pattern: #"\#(latinStart)(?:(il)\s+)?(\#(italianDayPattern))\s+al\s+piu\s+tardi\#(latinEnd)"#,
        read: italianDue),
    ],
    when: [
      Rule(
        pattern:
          #"\#(latinStart)(?:(a\s+partire\s+dalla|a\s+partire\s+dal|a\s+partire\s+da|dalla|dal|da|il)\s+)?(\#(italianDayPattern))\#(latinEnd)"#,
        read: italianWhen)
    ])

  // MARK: - Words after a detail

  /// The words a detail with no unit of its own ("alle 3", "il 15", "da 3 a
  /// 4") may be followed by: prepositions, conjunctions, articles, and the
  /// words that say when. An apostrophe ends a word ("all'ufficio" is read as
  /// "all'"). Any other word after the number makes it a count ("alle 3
  /// amiche", "il 15 libri"), so it stays in the title.
  private static let italianWordsAfterDetail: Set<String> = [
    "a", "ad", "al", "allo", "alla", "alle", "all'", "ai", "agli", "con", "in", "di", "del", "della", "dei", "da", "dal",
    "dalle", "dall'", "per", "su", "sul", "tra", "fra", "e", "ed", "o", "ma", "che", "il", "lo", "la", "le", "l'", "i",
    "gli", "un", "una", "un'", "questo", "questa", "ogni", "tutti", "tutte", "oggi", "domani", "dopodomani", "stasera",
    "stamattina", "prima", "dopo", "poi", "gia", "circa", "anche", "si", "no", "mi", "ti", "ci", "vi", "non",
  ]

  /// Whether the line goes on after `match` with nothing, punctuation, or a
  /// word in ``italianWordsAfterDetail`` (minus `excluding`).
  private static func italianFollowsAsDetail(_ match: Match, excluding: Set<String> = []) -> Bool {
    guard let next = wordAfter(match) else { return true }
    let head = next.firstIndex(of: "'").map { String(next[...$0]) } ?? next
    return italianWordsAfterDetail.contains(head) && !excluding.contains(head)
  }

  /// The words before "mezzogiorno" or "mezzanotte" that make it an ordinary
  /// noun ("il mezzogiorno d'Italia", "la messa di mezzanotte").
  private static let italianNounLeads: Set<String> = [
    "il", "lo", "la", "l'", "del", "dello", "della", "di", "d'", "nel", "nello", "nella", "al", "allo", "alla", "un",
    "una", "questo", "questa",
  ]

  // MARK: - Priority

  /// Group 1: a written priority; "urgente" has no group.
  private static let italianPriorityPattern =
    #"\#(latinStart)(priorita\s+(?:alta|massima|elevata|media|normale|bassa|minima)|(?:alta|media|bassa)\s+priorita)\#(latinEnd)|(?<=\s)urgente(?=\s*$)|^\s*urgente(?=\s*[，：:,])"#

  private static func italianPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1)?.lowercased() else { return .p1 }
    if phrase.contains("media") || phrase.contains("normale") { return .p2 }
    if phrase.contains("bassa") || phrase.contains("minima") { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "per 2 ore", "di 2 ore", "1h30min", "1,5 ore", "2 ore e mezza", "1 ora e
  /// 30", "2 ore", "30 min", or a length in words, each maybe after per,
  /// durata, or di. Groups: 1 per, durata, or di; 2 a word that makes the
  /// amount a moment or an interval; 3 and 4 the hours and minutes of "1h30";
  /// 5 the hours of "2 ore e mezza"; 6 hours with a unit ("2h", "1,5 ore"), 7
  /// their minutes after "e" and 8 their minutes with a unit; 9 minutes; 10 a
  /// length in words. The amount may not follow a digit, a colon, or a
  /// separator, so the "05 h" of "9:05 h" is not five hours, and it may not
  /// follow the English "for", so English's "for 2h" keeps its "for".
  private static let italianLengthPattern =
    #"\#(latinStart)(?:(per|durata|di)\s*:?\s+|((?:tra|fra|in|ogni|dopo|entro|alle|dalle|verso\s+le|intorno\s+alle|fino\s+alle|fino\s+a|circa\s+alle|prima\s+di|piu\s+di|meno\s+di)\s+|(?:all|dall)['’]))?(?<![\p{N}:.,])(?<!\bfor\s)(?:(\d+)\s*h\s*(\d{1,2})(?:\s*(?:minuti|minuto|min))?|(\d+)\s*ore\s+e\s+mezz[ao]|(\d+(?:[.,]\d+)?)\s*(?:ore|ora|h)(?:\s+e\s+(\d{1,2})(?:\s*(?:minuti|minuto|min))?|\s+(\d{1,2})\s*(?:minuti|minuto|min))?|(\d+)\s*(?:minuti|minuto|min)|(mezz['’]ora|mezzora|mezza\s+ora|un['’]ora\s+e\s+mezz[ao]|un['’]ora|un\s+ora|due\s+ore|un\s+quarto\s+d['’]ora|tre\s+quarti\s+d['’]ora))\#(latinEnd)"#

  private static func italianLength(_ match: Match) -> Int? {
    // An amount after tra, fra, in, dopo, entro, ogni, or alle names a moment
    // or an interval ("tra 2 ore", "ogni 8 ore"), not a length.
    if match.group(2) != nil { return nil }
    if let hours = match.group(3).flatMap(number), let minutes = match.group(4).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let hours = match.group(5).flatMap(number) { return taskLength(minutes: hours * 60 + 30) }
    if let hours = match.group(6).flatMap(decimalAmount) {
      let minutes = (match.group(7) ?? match.group(8)).flatMap(number) ?? 0
      return taskLength(minutes: Int((hours * 60).rounded()) + minutes)
    }
    if let minutes = match.group(9).flatMap(number) { return taskLength(minutes: minutes) }
    switch match.group(10).map(normalizedPhrase) {
    case "mezz'ora", "mezzora", "mezza ora": return 30
    case "un'ora e mezza", "un'ora e mezzo": return 90
    case "un'ora", "un ora": return 60
    case "due ore": return 120
    case "un quarto d'ora": return 15
    case "tre quarti d'ora": return 45
    default: return nil
    }
  }

  // MARK: - Time

  /// What separates a word from the number after it: a space, or nothing after
  /// an apostrophe ("all'una").
  private static let italianSeparator = #"(?:\s+|(?<=['’]))"#

  /// The words before an hour that make it a clock time.
  private static let italianTimeLead =
    #"intorno\s+all['’]|intorno\s+alle|circa\s+all['’]|circa\s+alle|verso\s+l['’]|verso\s+le|dall['’]|dalle|all['’]|alle|ore"#

  /// An hour: digits, or the word for one of the twelve hours.
  private static let italianHourWord = #"\d{1,2}|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici"#

  /// The part of the day written after a clock time: di mattina, del
  /// pomeriggio, di sera, della notte. One group.
  private static let italianPartOfDay =
    #"(?:\s+((?:di|del|della|nel|nella)\s+(?:mattina|mattino|pomeriggio|sera|notte)))"#

  /// The part of the day or the meridiem after a clock time: an
  /// ``italianPartOfDay``, or a. m. or pm. Two groups: the part of the day in
  /// words, and the letter of AM or PM.
  private static let italianDayPart = #"(?:\#(italianPartOfDay)|\s*([ap])\.?\s?m\.?)"#

  /// What may follow a clock time: no letter, digit, or colon, and no decimal
  /// fraction.
  private static let italianTimeEnd = #"(?![\p{Latin}\p{N}:]|[.,]\p{N})"#

  /// "alle 3", "alle 15:30", "alle 15.30", "ore 15", "alle 9 di mattina",
  /// "alle 3 e mezza", "alle 4 meno un quarto", "alle 3 in punto", "alle 3
  /// pm", and "all'una"; "3 del pomeriggio" with no lead; and "mezzogiorno"
  /// and "mezzanotte". A time written with no Italian word ("3pm", "15:30") is
  /// left to English, whose "at 3pm" would lose its "at" here. Groups: 1 the
  /// lead (alle, verso le, dalle, ore, ...), 2 hour, 3 minute, 4 what follows
  /// "e" (mezza, mezzo, un quarto, or minutes), 5 "un quarto" after "meno", 6
  /// "in punto", 7 the part of the day, 8 the letter of AM or PM; 9 to 11 the
  /// hour, minute, and part of the day of a time with no lead; 12 the word
  /// before mezzogiorno or mezzanotte, 13 the word, 14 its "e mezza".
  private static let italianTimePattern =
    [
      #"\#(latinStart)(\#(italianTimeLead))\#(italianSeparator)(?:ore\s+)?(\#(italianHourWord))(?:[.:](\d{2}))?(?:\s+e\s+(mezza|mezzo|un\s+quarto|\d{2})|\s+meno\s+(un\s+quarto))?(?:\s+(in\s+punto))?\#(italianDayPart)?\#(italianTimeEnd)"#,
      #"\#(latinStart)(?<![\p{N}:.,])(\d{1,2})(?::(\d{2}))?\#(italianPartOfDay)\#(italianTimeEnd)"#,
      #"\#(latinStart)(?:(a|verso|intorno\s+a|circa)\s+)?(mezzogiorno|mezzanotte)(?:\s+e\s+(mezza))?\#(latinEnd)"#,
    ].joined(separator: "|")

  /// The hours the words una to dodici spell.
  private static let italianHours = [
    "una": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9, "dieci": 10,
    "undici": 11, "dodici": 12,
  ]

  private static func italianTime(_ match: Match) -> ClockTime? {
    if let word = match.group(13)?.lowercased() {
      // "Il mezzogiorno" and "la messa di mezzanotte" are nouns, not a time.
      if match.group(12) == nil, let before = wordBefore(match), italianNounLeads.contains(before) { return nil }
      let half = match.group(14) == nil ? 0 : 30
      return word == "mezzogiorno"
        ? ClockTime(minutes: 12 * 60 + half) : ClockTime(minutes: half, isAfterMidnight: true)
    }
    let hourText: String
    let minuteText: String?
    let part: String?
    let meridiem: String?
    let hasLead = match.group(2) != nil
    if let text = match.group(2) {
      hourText = text
      minuteText = match.group(3)
      part = match.group(7)
      meridiem = match.group(8)
    } else if let text = match.group(9) {
      hourText = text
      minuteText = match.group(10)
      part = match.group(11)
      meridiem = nil
    } else {
      return nil
    }
    guard var hour = italianHours[hourText.lowercased()] ?? number(hourText) else { return nil }
    var minute = minuteText.flatMap(number) ?? 0
    if hasLead, let fraction = match.group(4) {
      guard minuteText == nil else { return nil }
      switch normalizedPhrase(fraction) {
      case "mezza", "mezzo": minute = 30
      case "un quarto": minute = 15
      default: minute = number(fraction) ?? 0
      }
    } else if hasLead, match.group(5) != nil {
      // "Alle 4 meno un quarto" is 3:45, and "all'una meno un quarto" 12:45.
      guard minuteText == nil, hour >= 1 else { return nil }
      hour = hour == 1 ? 12 : hour - 1
      minute = 45
    }
    guard (0...59).contains(minute) else { return nil }
    if part != nil || meridiem != nil {
      return italianPartTime(
        hour: hour, minute: minute, part: part.map(normalizedPhrase), meridiem: meridiem?.lowercased())
    }
    // A bare hour ("alle 3") is a time unless a counted noun follows it
    // ("alle 3 amiche").
    let isBare = hasLead && (3...6).allSatisfy { match.group($0) == nil }
    if isBare, !italianFollowsAsDetail(match) { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(hourText))
  }

  /// The time an hour of a 12-hour clock names with a part of the day or AM or
  /// PM; nil for an hour no such clock shows.
  private static func italianPartTime(hour: Int, minute: Int, part: String?, meridiem: String?) -> ClockTime? {
    guard (1...12).contains(hour) else { return nil }
    if let meridiem {
      return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
    }
    guard let part else { return nil }
    if part.hasSuffix("mattina") || part.hasSuffix("mattino") { return ClockTime(minutes: hour * 60 + minute) }
    if part.hasSuffix("pomeriggio") { return ClockTime(minutes: (hour % 12 + 12) * 60 + minute) }
    if part.hasSuffix("sera") {
      return hour == 12 ? nightTime(hour: 12, minute: minute) : ClockTime(minutes: (hour + 12) * 60 + minute)
    }
    return nightTime(hour: hour, minute: minute)
  }

  // MARK: - Time range

  /// One side of a range: an hour with maybe minutes, an hour word,
  /// mezzogiorno, or mezzanotte.
  private static let italianRangeSide =
    #"\d{1,2}(?:[.:]\d{2})?|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici|mezzogiorno|mezzanotte"#

  /// "dalle 3 alle 4", "dalle ore 9 alle ore 11", "dalle 9 a mezzogiorno". A
  /// range with a dash ("14:00-16:30", "3-4pm") is left to English. The two
  /// range patterns share their groups: 1 the word that opens the range
  /// (dalle, dal, da, tra, fra), 2 "ore" or the article before the start, 3 the
  /// start, 4 "ore" or the article before the end, 5 the end, 6 the part of the
  /// day written after the end, 7 the letter of AM or PM.
  private static let italianFromToPattern =
    #"\#(latinStart)(dalle|dall['’]|dal|da)\#(italianSeparator)(ore\s+)?(\#(italianRangeSide))\s+(?:alle\s+|all['’]|ad\s+|a\s+|fino\s+alle\s+|fino\s+all['’]|fino\s+ad\s+|fino\s+a\s+)(ore\s+)?(\#(italianRangeSide))\#(italianDayPart)?\#(italianTimeEnd)"#

  /// "tra le 3 e le 4".
  private static let italianBetweenPattern =
    #"\#(latinStart)(tra|fra)\s+((?:le\s+|l['’]))?(\#(italianRangeSide))\s+e\s+((?:le\s+|l['’]))?(\#(italianRangeSide))\#(italianDayPart)?\#(italianTimeEnd)"#

  private static func italianRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(3), let endText = match.group(5), let start = italianRangeSideTime(startText),
      var end = italianRangeSideTime(endText)
    else { return nil }
    let part = match.group(6).map(normalizedPhrase)
    let meridiem = match.group(7)?.lowercased()
    if part != nil || meridiem != nil {
      // The part of the day written after the end belongs to the end; the
      // start takes the reading of its hour that fits before it.
      guard let hour = end.writtenHour,
        let named = italianPartTime(hour: hour, minute: end.minutes % 60, part: part, meridiem: meridiem)
      else { return nil }
      end = named
    } else if italianIsBareHour(startText) && italianIsBareHour(endText) {
      // Two bare hours are as often a count: they are a range after dalle,
      // da, or tra le, and only when no counted noun follows.
      let opener = match.group(1)?.lowercased()
      let hasArticle = match.group(2) != nil || match.group(4) != nil
      let isBetween = opener == "tra" || opener == "fra"
      guard opener != nil, !isBetween || hasArticle, italianFollowsAsDetail(match) else { return nil }
    }
    return timeRange(from: start, to: end)
  }

  /// Whether a range side is only an hour, in digits or in a word.
  private static func italianIsBareHour(_ text: String) -> Bool {
    text.allSatisfy(\.isNumber) || italianHours[text.lowercased()] != nil
  }

  private static func italianRangeSideTime(_ text: String) -> ClockTime? {
    let lower = text.lowercased()
    switch lower {
    case "mezzogiorno": return ClockTime(minutes: 12 * 60)
    case "mezzanotte": return ClockTime(minutes: 0, isAfterMidnight: true)
    default: break
    }
    if let hour = italianHours[lower] { return bareTime(hour: hour, minute: 0, hasLeadingZero: false) }
    guard let match = lower.wholeMatch(of: /(\d{1,2})(?:[.:](\d{2}))?/), let hour = number(match.output.1) else {
      return nil
    }
    let minute = match.output.2.flatMap { number($0) } ?? 0
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(match.output.1)))
  }

  // MARK: - Repeat

  /// The singular weekday names, longest first, as a pattern.
  private static var italianDayNames: String {
    italianWeekdays.sorted { $0.count > $1.count }.joined(separator: "|")
  }

  /// The weekday names with the plural forms "sabati" and "domeniche", longest
  /// first, as a pattern.
  private static var italianWeekdayNames: String {
    (italianWeekdays + ["sabati", "domeniche"]).sorted { $0.count > $1.count }.joined(separator: "|")
  }

  /// "ogni lunedì", "tutti i lunedì", "ogni lunedì e giovedì", "tutti i lunedì
  /// e i giovedì", and "il lunedì" or "i sabati" at the end of the line, since
  /// "il lunedì" before another word is part of the title ("il lunedì sera").
  /// Groups: 1 the weekdays after ogni, tutti i, or tutte le; 2 the weekdays
  /// after an article.
  private static var italianWeekdayRepeatPattern: String {
    let day = "(?:\(italianWeekdayNames))"
    let days = "\(day)(?:\\s*(?:,|e|ed)\\s*(?:(?:il|la|i|le|gli|l['’])\\s*)?\(day)){0,6}"
    return "\(latinStart)(?:(?:ogni|tutti\\s+i|tutte\\s+le)\\s+(\(days))\(latinEnd)"
      + "|(?:il|la|i|le)\\s+(\(days))(?=[\\s.,;!?]*$))"
  }

  private static func italianWeekdayRepeat(_ match: Match) -> Repeat? {
    let days = (match.group(1) ?? match.group(2) ?? "").split { !$0.isLetter }.map(String.init)
      .compactMap(italianWeekdayIndex)
    return days.isEmpty ? nil : weekly(every: nil, on: days)
  }

  /// "ogni 3 giorni", "ogni due settimane", "ogni tre mesi", "ogni quindici
  /// giorni". Groups: 1 the count, 2 the unit.
  private static var italianIntervalRepeatPattern: String {
    let counts = italianNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    return "\(latinStart)ogni\\s+(\\d{1,2}|\(counts))\\s+(giorni|settimane|mesi|anni)\(latinEnd)"
  }

  private static func italianIntervalRepeat(_ match: Match) -> Repeat? {
    guard let countText = match.group(1)?.lowercased(), let count = number(countText) ?? italianNumbers[countText],
      (1...99).contains(count), let unit = match.group(2)?.lowercased()
    else { return nil }
    let every = count == 1 ? nil : count
    switch unit {
    // Italian counts a fortnight as fifteen days: "ogni quindici giorni" is
    // every two weeks.
    case "giorni":
      return count == 15 ? weekly(every: 2, on: []) : Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: every))
    case "settimane": return weekly(every: every, on: [])
    case "mesi": return monthly(every: every, on: nil)
    default: return Repeat(rule: TaskRecurrenceRule(freq: .yearly, interval: every))
    }
  }

  /// "un giorno sì e uno no", "una settimana sì e una no", "un mese sì e uno
  /// no", "un lunedì sì e uno no". Group 1: the unit or the weekday.
  private static var italianAlternatePattern: String {
    "\(latinStart)(?:un|una)\\s+(giorno|settimana|mese|\(italianDayNames))\\s+si\\s+e\\s+(?:uno|una)\\s+no\(latinEnd)"
  }

  private static func italianAlternateRepeat(_ match: Match) -> Repeat? {
    guard let word = match.group(1)?.lowercased() else { return nil }
    switch word {
    case "giorno": return Repeat(rule: TaskRecurrenceRule(freq: .daily, interval: 2))
    case "settimana": return weekly(every: 2, on: [])
    case "mese": return monthly(every: 2, on: nil)
    default: return italianWeekdayIndex(word).map { weekly(every: 2, on: [$0]) }
    }
  }

  /// "il 5 di ogni mese", "ogni mese il 5", "ogni 5 del mese". Groups 1, 2,
  /// and 3: the day of the month in each form.
  private static let italianMonthDayRepeatPattern =
    #"\#(latinStart)(?:(?:il\s+)?(\d{1,2}|primo)\s+di\s+ogni\s+mese|ogni\s+mese\s+il\s+(\d{1,2}|primo)|ogni\s+(\d{1,2}|primo)\s+del\s+mese)\#(latinEnd)"#

  /// The counts a repeat or a day phrase may spell out.
  private static let italianNumbers = [
    "un": 1, "uno": 1, "una": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8,
    "nove": 9, "dieci": 10, "undici": 11, "dodici": 12, "quindici": 15,
  ]

  // MARK: - Days

  /// The weekday names without accents, Sunday first.
  private static let italianWeekdays = ["domenica", "lunedi", "martedi", "mercoledi", "giovedi", "venerdi", "sabato"]

  /// Each month's names, January first: the name, then its abbreviations.
  private static let italianMonths = [
    ["gennaio", "gen"], ["febbraio", "feb"], ["marzo"], ["aprile", "apr"], ["maggio", "mag"], ["giugno", "giu"],
    ["luglio", "lug"], ["agosto", "ago"], ["settembre", "sett"], ["ottobre", "ott"], ["novembre", "nov"],
    ["dicembre", "dic"],
  ]

  /// The days, without the word that may introduce them.
  private static var italianDayPattern: String {
    let count = "(?:\\d{1,3}|un|una|due|tre|quindici)"
    return [
      #"oggi(?:\s+(?:pomeriggio|mattina|sera|stesso))?|stamattina|stamani|stasera|stanotte"#,
      #"(?:questa|questo)\s+(?:mattina|pomeriggio|sera|notte)"#,
      #"dopo\s*domani"#,
      #"domani(?:\s+(?:mattina|pomeriggio|sera|notte|stesso))?"#,
      #"(?:la\s+)?(?:settimana\s+(?:prossima|che\s+viene)|prossima\s+settimana)"#,
      // The borrowed word "weekend" needs its article or demonstrative, so
      // an English "this weekend" is left to English.
      #"(?:(?:il|questo|nel)\s+)?(?:prossimo\s+)?fine\s+settimana(?:\s+prossimo)?"#,
      #"(?:il|questo|nel)\s+(?:prossimo\s+)?week[\s-]?end(?:\s+prossimo)?"#,
      "(?:tra|fra)\\s+\(count)\\s+(?:giorni|giorno|settimane|settimana)",
      italianDatePattern,
      // A weekday followed by scorso or passato is the last one ("lunedì
      // scorso").
      "(?:(?:questo|questa|prossimo|prossima)\\s+)?(?:\(italianDayNames))(?:\\s+(?:prossimo|prossima|che\\s+viene))?"
        + "(?:\\s+(?:mattina|pomeriggio|sera|notte))?(?!\\s+(?:scorso|scorsa|passato|passata))",
    ].joined(separator: "|")
  }

  /// "15 ottobre", "lunedì 15 ottobre", "1º ottobre", "il primo ottobre", "15
  /// di ottobre", "15 ott.", "15 ottobre 2027"; and a bare number after il, al,
  /// or dal ("il 15", "entro il 15"), as a day of the month.
  private static var italianDatePattern: String {
    let months = italianMonths.flatMap { $0 }.sorted { $0.count > $1.count }.joined(separator: "|")
    let day = #"(?:\d{1,2}[º°]?|primo)"#
    let notMore = #"(?![\p{N}%]|[:.,]\p{N})"#
    return "(?:(?:\(italianDayNames))\\s+)?\(day)\\s+(?:di\\s+)?(?:\(months))\\.?(?:\\s+(?:del\\s+)?\\d{4})?"
      + "|(?<=\\bil\\s|\\bal\\s|\\bdal\\s)\\d{1,2}\(notMore)"
  }

  /// Words that, right before a day, make it part of the title instead: "la
  /// riunione del lunedì", "di sabato vado al mercato".
  private static let italianNoDayAfter: Set<String> = [
    "di", "del", "dello", "della", "dei", "degli", "delle", "d'", "ogni", "tutti", "tutte",
  ]

  /// The articles before a weekday that make it a habit, never the coming day.
  private static let italianHabitualArticles: Set<String> = ["il", "lo", "la", "l'", "i", "gli", "le"]

  /// Group 1: the word before the day (il, da, dal, a partire da) or nil; 2
  /// the day.
  private static func italianWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(2) else { return nil }
    let lead = match.group(1).map(normalizedPhrase)
    let isBareWeekday = italianBareWeekday(phrase) != nil
    if lead == "il", isBareWeekday { return nil }
    if lead == nil {
      if let before = wordBefore(match) {
        if italianNoDayAfter.contains(before) { return nil }
        if isBareWeekday, italianHabitualArticles.contains(before) { return nil }
      }
      if italianIsPersonName(phrase, in: match) { return nil }
    }
    return italianDay(phrase, in: match)
  }

  /// Group 1: "il" or nil; 2 the day.
  private static func italianDue(_ match: Match) -> Day? {
    guard let phrase = match.group(2) else { return nil }
    if match.group(1) == nil, italianIsPersonName(phrase, in: match) { return nil }
    return italianDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  /// The weekday a phrase names when it is a weekday and nothing else, maybe
  /// followed by a part of the day ("sabato sera").
  private static func italianBareWeekday(_ phrase: String) -> Int? {
    var parts = normalizedPhrase(phrase).split(separator: " ").map(String.init)
    if parts.count == 2, ["mattina", "pomeriggio", "sera", "notte"].contains(parts[1]) { parts.removeLast() }
    return parts.count == 1 ? italianWeekdayIndex(parts[0]) : nil
  }

  /// True for a capitalized "Domenica" that does not open the line: a person's
  /// name ("Chiamare Domenica"), not the day.
  private static func italianIsPersonName(_ phrase: String, in match: Match) -> Bool {
    guard phrase.first?.isUppercase == true, italianBareWeekday(phrase) == 0,
      let start = Range(match.result.range, in: match.source)?.lowerBound
    else { return false }
    return !match.source[..<start].allSatisfy(\.isWhitespace)
  }

  /// A day of the month alone ("il 15") is a date only at the end of the line
  /// or before a word that can follow a date, never before "di" ("il 3 di
  /// noi").
  private static func italianDay(_ phrase: String, in match: Match) -> Day? {
    let words = normalizedPhrase(phrase)
    if let date = italianDate(words) {
      let isBareDay = words.wholeMatch(of: /\d{1,2}/) != nil
      if isBareDay, !italianFollowsAsDetail(match, excluding: ["di", "del"]) { return nil }
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let relative = words.wholeMatch(of: /(?:tra|fra) (\w+) (giorno|giorni|settimana|settimane)/) {
      let countText = String(relative.output.1)
      guard let count = number(countText) ?? italianNumbers[countText] else { return nil }
      return Day(offset: relative.output.2.hasPrefix("settiman") ? count * 7 : count)
    }
    let todayWeekday = match.todayWeekday
    let isNext = words.contains("prossim") || words.contains("che viene")
    if words.contains("fine settimana") || words.contains("weekend") || words.contains("week end") {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    if words.contains("settimana") { return isNext ? Day(offset: 7) : nil }
    let isEvening = words.hasSuffix("sera") || words.hasSuffix("notte")
    let parts = words.split(separator: " ").map(String.init)
    if words.hasPrefix("oggi") { return Day(offset: 0, isEvening: isEvening) }
    if words == "stamattina" || words == "stamani" { return Day(offset: 0) }
    if words == "stasera" || words == "stanotte" { return Day(offset: 0, isEvening: true) }
    if parts.count == 2, parts[0] == "questa" || parts[0] == "questo",
      ["mattina", "pomeriggio", "sera", "notte"].contains(parts[1])
    {
      return Day(offset: 0, isEvening: isEvening)
    }
    if words.hasPrefix("dopo") && words.hasSuffix("domani") { return Day(offset: 2) }
    if words.hasPrefix("domani") { return Day(offset: 1, isEvening: isEvening) }
    guard let weekday = parts.lazy.compactMap(italianWeekdayIndex).first else { return nil }
    if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
    if parts.first == "questo" || parts.first == "questa" {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// A written-out date, maybe after its weekday: "15 ottobre", "lunedì 1º
  /// ottobre 2027", "15 di ottobre"; or a day of the month alone ("15").
  private static func italianDate(_ words: String) -> ExplicitDate? {
    if let match = words.wholeMatch(of: /(?:\p{L}+ )?(\d{1,2}|primo)[º°]? (?:di )?(\p{L}+)\.?(?: (?:del )?(\d{4}))?/),
      let day = italianDayNumber(String(match.output.1)),
      let month = italianMonths.firstIndex(where: { $0.contains(String(match.output.2)) })
    {
      return ExplicitDate(year: match.output.3.flatMap { number($0) }, month: month + 1, day: day)
    }
    if let match = words.wholeMatch(of: /(\d{1,2})/), let day = number(match.output.1) {
      return ExplicitDate(day: day)
    }
    return nil
  }

  /// The day of the month "5", "1º", or "primo" names.
  private static func italianDayNumber(_ text: String) -> Int? {
    let lower = text.lowercased()
    return lower == "primo" ? 1 : number(lower)
  }

  /// The weekday a word names, 0 = Sunday, singular or plural ("sabati").
  private static func italianWeekdayIndex(_ word: String) -> Int? {
    switch word.lowercased() {
    case "sabati": return 6
    case "domeniche": return 0
    case let lower: return italianWeekdays.firstIndex(of: lower)
    }
  }

  // MARK: - Due

  /// "entro venerdì", "per domani", "fino al 15", "scade il 15 ottobre",
  /// "scadenza: venerdì", "data limite venerdì". Groups: 1 the article il or
  /// nil, 2 the day.
  private static var italianDuePattern: String {
    #"\#(latinStart)(?:entro|scadenza|scade|per|fino\s+al?|non\s+oltre|data\s+limite)(?:\s*:\s*|\s+)(?:(il)\s+)?(\#(italianDayPattern))\#(latinEnd)"#
  }
}
