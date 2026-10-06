import Foundation

extension LorvexCaptureVocabulary {
  // The Turkish day rules: the due day, the planned day, the date ranges, and
  // the past days that stay in the title. The vocabulary's other words are in
  // ``turkish``.

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  private static let turkishNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  // MARK: - Case endings

  /// The locative ending of a date ("15 Ekim'de", "3 Mayıs'ta"), with the
  /// adjective ending that follows it ("15 Ekim'deki toplantı"), as a pattern
  /// without groups. The apostrophe may be left out.
  static let turkishLocative = #"(?:['’ʼ]?(?:d[ae]|t[ae])(?:ki)?)"#

  /// The dative ending of a day ("cumaya", "yarına", "15 Ekim'e"), as a pattern
  /// without groups. The apostrophe may be left out.
  static let turkishDative = #"(?:['’ʼ]?(?:ya|ye|a|e))"#

  /// The ablative ending of a day ("cumadan", "15 Ekim'den"), as a pattern
  /// without groups. The apostrophe may be left out.
  static let turkishAblative = #"(?:['’ʼ]?(?:d[ae]n|t[ae]n))"#

  // MARK: - Weekdays and parts of the day

  /// Each weekday's stem, Sunday first. A case ending or the plural of a
  /// weekday begins with its stem.
  private static let turkishWeekdayStems = [
    "pazar", "pazartesi", "sali", "carsamba", "persembe", "cuma", "cumartesi",
  ]

  /// The weekday names, as a pattern without groups: the stems and the two
  /// short forms that are no other word, "pzt" and "cmt". "Sal", "çar", "per",
  /// "cum", and "paz" are words of their own and are not names.
  static let turkishWeekdayNames = alternation(of: turkishWeekdayStems + ["pzt", "cmt"])

  /// The weekday names but "pazar", which is the market as often as Sunday and
  /// names the day only with a word that makes it one ("bu pazar", "pazar
  /// günü"), as a pattern without groups.
  static let turkishBareWeekdayNames = alternation(
    of: turkishWeekdayStems.filter { $0 != "pazar" } + ["pzt", "cmt"])

  /// The weekday a word names, 0 = Sunday: a stem, a short form, or a stem with
  /// a case ending or a plural. The word is in the reading form.
  static func turkishWeekdayIndex(_ word: String) -> Int? {
    let key = turkishKey(word)
    if key == "pzt" { return 1 }
    if key == "cmt" { return 6 }
    let matches = turkishWeekdayStems.enumerated().filter { key.hasPrefix($0.element) }
    return matches.max { $0.element.count < $1.element.count }?.offset
  }

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: "sabah", "öğlen", "öğleden sonra", "ikindi", "akşam",
  /// "akşam üstü", "gece", each maybe with its possessive ending ("akşamı",
  /// "gecesi").
  static let turkishPartWords =
    #"ogleden\s+sonra(?:si)?|aksam\s+ustu|sabah(?:i)?|oglen(?:i)?|ogle|ikindi(?:si)?|aksam(?:i)?|gece(?:si)?"#

  /// The part of the day a matched word or phrase names: "akşam", "öğleden
  /// sonra", "sabahı", "gece".
  static func turkishPartOfDay(_ text: String) -> PartOfDay? {
    let key = turkishPhrase(text)
    if key.contains("ogleden sonra") || key.contains("ikindi") { return .day }
    if key.contains("sabah") { return .morning }
    if key.contains("ogle") { return .day }
    if key.contains("aksam") { return .evening }
    if key.contains("gece") { return .night }
    return nil
  }

  // MARK: - Months

  /// Each month's full name and its three-letter abbreviation, January first.
  private static let turkishMonthRows: [(full: String, abbreviation: String)] = [
    ("ocak", "oca"), ("subat", "sub"), ("mart", "mar"), ("nisan", "nis"), ("mayis", "may"), ("haziran", "haz"),
    ("temmuz", "tem"), ("agustos", "agu"), ("eylul", "eyl"), ("ekim", "eki"), ("kasim", "kas"), ("aralik", "ara"),
  ]

  /// The month names, as a pattern without groups: every full name, and each
  /// abbreviation written with a capital first letter ("Eki") or followed by a
  /// period ("eki."). Several abbreviations are ordinary words ("ara", "kas",
  /// "haz", "eki"), so a lowercase one with no period is no month.
  private static var turkishMonthNames: String {
    let full = alternation(of: turkishMonthRows.map(\.full))
    let capitalized = turkishMonthRows.map {
      "(?-i:\($0.abbreviation.prefix(1).uppercased()))\($0.abbreviation.dropFirst())"
    }.joined(separator: "|")
    let dotted = "(?:\(alternation(of: turkishMonthRows.map(\.abbreviation))))(?=\\.)"
    return "\(full)|\(capitalized)|\(dotted)"
  }

  /// The month a word names, 0 = January: a full name with any ending after it,
  /// or an abbreviation.
  private static func turkishMonthIndex(_ word: String) -> Int? {
    let key = turkishKey(word)
    if let index = turkishMonthRows.firstIndex(where: { key.hasPrefix($0.full) }) { return index }
    return turkishMonthRows.firstIndex { $0.abbreviation == key }
  }

  // MARK: - Dates

  /// "15 Ekim", "15 Ekim 2026", "15 Eki.": a day with its month, maybe with a
  /// year, then `suffix`. A month needs its day number ("Ekim" alone is no
  /// date).
  private static func turkishMonthDate(suffix: String) -> String {
    #"(?<![\p{N}.,:/-])\d{1,2}\s+(?:\#(turkishMonthNames))\.?(?:\s+(?:19|20)\d{2}(?!\p{N}))?\#(suffix)"#
  }

  /// "15.10.2026", "15.10.26", "15.10.": a day and a month in digits with the
  /// dot after the month, maybe with a year, then `suffix`. A number that goes
  /// on with more digits or dots ("1.10.2.5", "192.168.1.1") is none.
  private static func turkishNumericDate(suffix: String) -> String {
    #"(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N})|\d{2}(?!\p{N}))?\#(suffix)(?![\p{N}]|[.,/]\p{N})"#
  }

  /// "15/10/2026", "15-10-2026", "15/10/26": a day, a month, and a year in
  /// digits, then `suffix`, which nothing else reads as.
  private static func turkishSlashDate(suffix: String) -> String {
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})\#(suffix)(?![\p{N}]|[.,/]\p{N})"#
  }

  /// What may not follow a number that is a date or an hour only by its shape: a
  /// unit or a counted noun, which would make it an amount or a fraction ("1/2
  /// kilo", "3/4 bardak", "akşam 8 kişi").
  static let turkishNoCountedUnitAfter =
    #"(?!\s*(?:saat|dakika|dak|dk|gun|hafta|ay|yil|sene|kez|kere|defa|kisi|kisilik|tane|adet|parca|paket|kutu|sise|bardak|fincan|kasik|kg|kilo|gr|gram|lt|litre|metre|cm|mm|km|yas|yasinda|tl|lira|euro|dolar|numara|sayfa|madde|bolum|oda|kat|derece|sinif|puan|x)(?![\p{Latin}\p{N}\p{M}]))"#

  /// "15.10", "15/10", "15-10": a day and a month in digits with no year, then
  /// `suffix`, which a date reads only where something introduces it, since
  /// "15.10" is as often a time and "1/2" a fraction.
  private static func turkishLooseDate(suffix: String) -> String {
    #"(?<![\p{N}.,:/-])\d{1,2}(?:\.\d{1,2}|[/-]\d{1,2})\#(suffix)(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})\#(turkishNoCountedUnitAfter)"#
  }

  /// "15/10": a day and a month with a slash and no year, then `suffix`. A slash
  /// is no time, so a locative ending after it makes it a date ("15/10'da"),
  /// where "15.10'da" may be a time.
  private static func turkishLooseSlashDate(suffix: String) -> String {
    #"(?<![\p{N}.,:/-])\d{1,2}/\d{1,2}\#(suffix)(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})\#(turkishNoCountedUnitAfter)"#
  }

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, maybe "günü", then maybe a comma ("Cuma 16 Ekim", "Cuma
  /// günü 16 Ekim", "Cuma, 16.10.2026").
  private static var turkishWeekdayBeforeDate: String {
    #"(?:(?:\#(turkishWeekdayNames))(?:\s+gunu)?\s*,?\s+)"#
  }

  /// The dates a day may be written as without anything introducing them, with
  /// `suffix` after each: a day with its month, or numbers with a year or the
  /// closing dot.
  private static func turkishStrictDates(suffix: String) -> String {
    #"\#(turkishMonthDate(suffix: suffix))|\#(turkishNumericDate(suffix: suffix))|\#(turkishSlashDate(suffix: suffix))"#
  }

  /// The words after which a number with dots or slashes is a numbered item of
  /// the title, not a date: "bölüm 1.5", "sürüm 2.3.4", "skor 3-1".
  private static let turkishNumberingPattern =
    #"(?:bolum|madde|sayfa|sf\.?|no\.?|numara|surum|versiyon|paragraf|sekil|tablo|adim|seviye|oda|salon|hat|peron|sinif|grup|etap|tur|set|skor|sonuc|ticket|build|bug|slayt|slide|ders|alistirma|konu|soru|gorev|task|kat|blok|daire)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func turkishFollowsNumbering(_ match: Match) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(turkishNumberingPattern) else { return false }
    let before = turkishTextBefore(match)
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }

  /// A written-out date and whether it is written in digits only.
  private struct TurkishWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``turkishKey(_:)`` leaves it.
  private static func turkishExplicitDate(_ key: String) -> TurkishWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})\s+([a-z]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = turkishMonthIndex(String(found.output.2))
    {
      return TurkishWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-]?(\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return TurkishWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    return nil
  }

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5 Mayıs", "30 Mayıs
  /// 2027"), two numbers with their dots ("3.5."), or a day alone ("3"), then
  /// `suffix`. The end of a range may follow its dash directly ("3-5 Mayıs"),
  /// which a date alone may not.
  private static func turkishRangeSide(isEnd: Bool, suffix: String) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let month =
      #"\d{1,2}\s+(?:\#(turkishMonthNames))\.?(?:\s+(?:19|20)\d{2}(?!\p{N}))?\#(suffix)"#
    let bare = #"\d{1,2}\#(suffix)\#(turkishNoMoreDigits)"#
    return #"\#(lookbehind)(?:\#(month)|\d{1,2}\.\d{1,2}\.(?:\d{4}(?!\p{N}))?|\#(bare))"#
  }

  /// "3-5 Mayıs", "3-5 Mayıs'ta", "3 Mayıs - 5 Mayıs", "3 Mayıs'tan 5 Mayıs'a
  /// kadar", "3'ten 5 Mayıs'a kadar", "3 ile 5 Mayıs arası", "3 Mayıs ile 5
  /// Mayıs arasında", each maybe with a year after the end. The end may carry
  /// the dative or the locative ending. Groups: 1 the start, 2 a dash between
  /// the sides, 3 "ile" between them, 4 the end, 5 the word after the end
  /// ("kadar", "arası", "arasında").
  static var turkishDateRangePattern: String {
    let optionalAblative = #"(?:\#(turkishAblative))?"#
    let optionalEnding = #"(?:\#(turkishDative)|\#(turkishLocative))?"#
    let start = turkishRangeSide(isEnd: false, suffix: optionalAblative)
    let end = turkishRangeSide(isEnd: true, suffix: optionalEnding)
    return
      #"\#(turkishStart)(\#(start))(?:\s*([-–—])\s*|\s+(ile)\s+|\s+)(\#(end))(?:\s+(kadar|arasi|arasinda))?\#(turkishEnd)"#
  }

  static func turkishDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(4),
      let start = turkishRangeDate(startText), let end = turkishRangeDate(endText), end.month != nil
    else { return nil }
    let hasDash = match.group(2) != nil
    let closing = match.group(5).map(turkishKey)
    if match.group(3) != nil {
      // "3 ile 5 Mayıs arası": "ile" joins the sides only before "arası".
      guard closing == "arasi" || closing == "arasinda" else { return nil }
    } else if !hasDash {
      // "3 Mayıs'tan 5 Mayıs'a": the endings join the sides, the ablative on the
      // start and the dative on the end.
      guard turkishHasEnding(startText, turkishAblative), turkishHasEnding(endText, turkishDative) else { return nil }
    } else if start.month == nil, closing == nil || closing == "kadar", !dashTouchesBothSides(match, start: 1, end: 4) {
      // A start that is a day alone is read with a dash that touches both sides
      // ("3-5 Mayıs"): "Sprint 12 - 20 Mayıs" names a sprint and a date.
      return nil
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// Whether `text` ends with the case ending `ending`, a pattern.
  private static func turkishHasEnding(_ text: String, _ ending: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(#"(?:\#(ending))$"#) else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func turkishRangeDate(_ text: String) -> ExplicitDate? {
    let key = turkishKey(text)
    if let found = turkishExplicitDate(key) { return found.date }
    guard let day = key.firstMatch(of: /^(\d{1,2})/), let value = number(day.output.1) else { return nil }
    return ExplicitDate(day: value)
  }

  // MARK: - Weekday range

  /// "cumadan pazara kadar", "cuma-pazar", "cuma - pazar", "cumartesiden
  /// pazartesiye kadar", "cuma ile pazar arası": a span of weekdays. Groups: 1
  /// and 2 the first and the last weekday of the form with case endings, 3 and
  /// 4 of the dashed form, 5 and 6 of the form with "ile" and "arası". The case
  /// endings are no part of a group.
  static var turkishWeekdayRangePattern: String {
    let names = turkishWeekdayNames
    return
      #"\#(turkishStart)(?:(\#(names))\#(turkishAblative)\s+(\#(names))\#(turkishDative)(?:\s+kadar)?|(\#(names))\s*[-–—]\s*(\#(names))|(\#(names))\s+ile\s+(\#(names))\s+(?:arasi|arasinda))\#(turkishEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the last day
  /// after it, so on a Tuesday "cumadan pazara kadar" runs from Friday to the
  /// Sunday after it. Monday to Friday is the working week, which the repeat
  /// rules read, and a span from a day to itself is no span.
  static func turkishWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1) ?? match.group(3) ?? match.group(5),
      let lastWord = match.group(2) ?? match.group(4) ?? match.group(6),
      let first = turkishWeekdayIndex(firstWord), let last = turkishWeekdayIndex(lastWord),
      first != last, !(first == 1 && last == 5)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  // MARK: - Past days and weeks

  /// "dün", "dün akşam", "evvelsi gün", "önceki gün", "geçen cuma", "geçen hafta",
  /// "geçen hafta sonu", "geçen akşam", each with the clock time that follows
  /// it: a day or a week that is past, which names no day a task can be set
  /// for. It stays in the title whole, so the weekday or the hour inside it is
  /// not read.
  static var turkishPastPattern: String {
    let names = turkishWeekdayNames
    let part = turkishPartWords
    let clock = #"(?:\s+(?:saat\s+)?\d{1,2}(?:[.:]\d{2})?\#(turkishLocative)?)?"#
    return
      #"\#(turkishStart)(?:dun|evvelsi\s+gun|onceki\s+gun|gecen\s+(?:hafta\s+sonu|hafta|aksam|gece|sabah|oglen|(?:\#(names))(?:\s+gunu)?))(?:\s+(?:\#(part)))?\#(clock)\#(turkishEnd)"#
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "son
  /// tarih", "son gün", "son teslim tarihi", "en geç", "teslim", "teslim
  /// tarihi", "termin", "deadline", "vade", each with its colon or space.
  static let turkishDueLead =
    #"(?:en\s+gec(?:\s+tarih)?|son\s+(?:teslim\s+tarihi|teslim|tarih|gun)|teslim(?:\s+tarihi)?|termin|deadline|vadesi|vade)(?:\s*:\s*|\s+)"#

  /// The weekday phrase of a planned or due day, as a pattern without groups:
  /// a name (after bu, önümüzdeki, gelecek, or haftaya, or alone), then maybe
  /// "günü", then maybe a part of the day. "Pazar" stands alone only with
  /// "günü" or a part of the day.
  private static var turkishWeekdayPhrase: String {
    let names = turkishWeekdayNames
    let part = turkishPartWords
    let tail = #"(?:\s+gunu)?(?:\s+(?:\#(part)))?"#
    return
      #"(?:(?:bu|onumuzdeki|gelecek|haftaya)\s+(?:\#(names))|(?:\#(turkishBareWeekdayNames))|pazar(?=\s+(?:gunu|\#(part))(?![\p{Latin}\p{N}\p{M}])))\#(tail)"#
  }

  /// The words after "gelecek hafta" or "önümüzdeki hafta" that make the phrase
  /// a part of a longer one ("gelecek hafta sonuna kadar", "gelecek hafta
  /// başı", "gelecek hafta içinde").
  private static let turkishNotWeekEnd =
    #"(?!\s+(?:sonu|sonuna|basi|basina|ici|icinde|icerisinde|boyunca|itibaren)(?![\p{Latin}\p{M}]))"#

  /// The days a due phrase may name, as a pattern without groups: yarın, bugün,
  /// öbür gün (each maybe with a part of the day), a weekday phrase, next week,
  /// and a date. After a word that introduces the day (`afterLead`) any weekday
  /// name and a loose date ("15.10") may stand; without one the weekday phrase
  /// is the one a planned day reads, and a date is one of the strict forms.
  static func turkishPlainDay(afterLead: Bool) -> String {
    let names = turkishWeekdayNames
    let part = turkishPartWords
    let weekday =
      afterLead
      ? #"(?:(?:bu|onumuzdeki|gelecek|haftaya)\s+)?(?:\#(names))(?:\s+gunu)?(?:\s+(?:\#(part)))?"#
      : turkishWeekdayPhrase
    let dates =
      ([turkishMonthDate(suffix: ""), turkishNumericDate(suffix: ""), turkishSlashDate(suffix: "")]
        + (afterLead ? [turkishLooseDate(suffix: "")] : [])).joined(separator: "|")
    let alternatives = [
      #"\#(turkishWeekdayBeforeDate)(?:\#(dates))"#,
      #"(?:onumuzdeki|gelecek)\s+hafta\s+(?:\#(names))(?:\s+gunu)?(?:\s+(?:\#(part)))?"#,
      weekday,
      #"yarin(?:\s+(?:\#(part)))?|bugun|obur\s+gun(?:\s+(?:\#(part)))?"#,
      #"(?:onumuzdeki|gelecek)\s+hafta\#(turkishNotWeekEnd)|haftaya(?!\s+(?:\#(names)))"#,
      dates,
    ]
    return alternatives.joined(separator: "|")
  }

  /// The days a due phrase may name before "kadar", "dek", or "değin", as a
  /// pattern without groups, each with its dative ending: a weekday ("cumaya",
  /// "cuma gününe", "bu cumaya"), "yarına", "bugüne", "öbür güne", "haftaya", or
  /// a date ("15 Ekim'e", "15.10.2026'ya", "15/10'a").
  private static var turkishDativeDay: String {
    let names = turkishWeekdayNames
    let weekday =
      #"(?:(?:bu|onumuzdeki|gelecek|haftaya)\s+(?:\#(names))|(?:\#(turkishBareWeekdayNames)))\#(turkishDative)|(?:\#(names))\s+gunune"#
    let words = #"yarina|bugune|obur\s+gune|(?:(?:onumuzdeki|gelecek)\s+)?haftaya"#
    let dates = [
      turkishMonthDate(suffix: turkishDative), turkishNumericDate(suffix: turkishDative),
      turkishSlashDate(suffix: turkishDative), turkishLooseDate(suffix: turkishDative),
    ].joined(separator: "|")
    return #"\#(weekday)|\#(words)|\#(turkishWeekdayBeforeDate)?(?:\#(dates))"#
  }

  /// The days a due phrase may name before "önce" or "evvel", as a pattern
  /// without groups, each with its ablative ending: a weekday ("cumadan") or a
  /// date ("15 Ekim'den").
  private static var turkishAblativeDay: String {
    let names = turkishWeekdayNames
    let weekday =
      #"(?:(?:bu|onumuzdeki|gelecek|haftaya)\s+(?:\#(names))|(?:\#(turkishBareWeekdayNames)))\#(turkishAblative)"#
    let dates = [
      turkishMonthDate(suffix: turkishAblative), turkishNumericDate(suffix: turkishAblative),
      turkishSlashDate(suffix: turkishAblative), turkishLooseDate(suffix: turkishAblative),
    ].joined(separator: "|")
    return #"\#(weekday)|\#(turkishWeekdayBeforeDate)?(?:\#(dates))"#
  }

  /// What may follow a due day directly: a clock time written as a bound ("saat
  /// 17:00'ye kadar", "en geç saat 5", "17:00'den önce"), so the day before it
  /// is the due day.
  private static let turkishBeforeDeadlineClock =
    #"(?=\s*,?\s*(?:en\s+gec\s+(?:saat\s+)?\d|(?:saat\s+)?\d{1,2}(?:[.:]\d{2})?\S*\s+(?:kadar|dek|degin|once|evvel)(?![\p{Latin}\p{M}])|saat\s+[a-z]+(?:\s+(?:bir|iki)\S*)?\s+(?:kadar|dek|degin|once|evvel)(?![\p{Latin}\p{M}])))"#

  /// "cumaya kadar", "cuma'ya kadar", "yarına kadar", "15 Ekim'e kadar", "cumadan
  /// önce", "son tarih cuma", "en geç yarın", "teslim: 15 Ekim", and a day before
  /// a clock written as a bound ("cuma saat 17:00'ye kadar", "yarın en geç saat
  /// 5"). Groups: 1 the day with its dative ending before kadar, dek, or değin;
  /// 2 the day after a word that introduces it; 3 the day with its ablative
  /// ending before önce; 4 the day before a deadline clock.
  static var turkishDuePattern: String {
    #"\#(turkishStart)(?:(\#(turkishDativeDay))\s+(?:kadar|dek|degin)|\#(turkishDueLead)(\#(turkishPlainDay(afterLead: true)))|(\#(turkishAblativeDay))\s+(?:once|evvel)|(\#(turkishPlainDay(afterLead: false)))\#(turkishBeforeDeadlineClock))\#(turkishEnd)"#
  }

  static func turkishDue(_ match: Match) -> Day? {
    (match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4)).flatMap { turkishDay($0, in: match) }
      .map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "bugün", "yarın", "öbür gün" (maybe with a part of the day), "bu akşam",
  /// "bu gece", "3 gün sonra", "bir hafta sonra", "önümüzdeki hafta", "gelecek
  /// hafta", "haftaya", "bu hafta sonu", "önümüzdeki hafta sonu", a weekday
  /// phrase, and a date ("15 Ekim", "15 Ekim'de", "15.10.2026", "Cuma 16 Ekim",
  /// "tarih 15.10", "15/10'da"). Group 1: the day, with the words that
  /// introduce it.
  static var turkishWhenPattern: String {
    let names = turkishWeekdayNames
    let part = turkishPartWords
    let locative = #"(?:\#(turkishLocative))?"#
    let strict = turkishStrictDates(suffix: locative)
    let dateLead = #"(?:\#(turkishWeekdayBeforeDate))?"#
    let alternatives = [
      #"(?:bu|onumuzdeki|gelecek)\s+hafta\s+sonu"#,
      #"(?:onumuzdeki|gelecek)\s+hafta\s+(?:\#(names))(?:\s+gunu)?(?:\s+(?:\#(part)))?"#,
      #"(?:onumuzdeki|gelecek)\s+hafta\#(turkishNotWeekEnd)"#,
      #"(?:\d{1,3}|\#(turkishCountWords))\s+(?:gun|hafta)\s+sonra"#,
      #"bugun(?:\s+(?:\#(part)))?|bu\s+(?:aksam|gece|sabah|oglen|ikindi)"#,
      #"yarin(?:\s+(?:\#(part)))?|obur\s+gun(?:\s+(?:\#(part)))?"#,
      #"\#(dateLead)(?:\#(strict))"#,
      #"tarih(?:inde|ine|i)?\s*:?\s+\#(dateLead)\#(turkishLooseDate(suffix: locative))"#,
      #"\#(dateLead)\#(turkishLooseSlashDate(suffix: turkishLocative))"#,
      turkishWeekdayPhrase,
      #"haftaya"#,
    ]
    return #"\#(turkishStart)(\#(alternatives.joined(separator: "|")))\#(turkishEnd)"#
  }

  static func turkishWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { turkishDay($0, in: match) }
  }

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it and the case ending it carries. Nil when the phrase names no
  /// day, or names a date the calendar lacks.
  private static func turkishDay(_ phrase: String, in match: Match) -> Day? {
    let key = turkishKey(phrase)
    let words = turkishPhrase(phrase)
    let tokens = words.split(separator: " ").map(String.init)
    let isEvening = tokens.contains { $0.hasPrefix("aksam") || $0.hasPrefix("gece") }
    if let found = turkishExplicitDate(key) {
      if found.isNumeric, turkishFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let relative = words.wholeMatch(of: /(.+) (gun|hafta) sonra/), let count = turkishCount(String(relative.output.1)) {
      return Day(offset: relative.output.2 == "hafta" ? count * 7 : count)
    }
    let todayWeekday = match.todayWeekday
    if tokens.contains("hafta"), tokens.contains(where: { $0.hasPrefix("sonu") }) {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: tokens.first == "bu" ? weekend : weekend + 7)
    }
    let isNextWeek = tokens.contains("hafta") || tokens.contains(where: { $0 == "haftaya" })
    guard let weekday = tokens.lazy.compactMap({ turkishWeekdayIndex($0) }).first else {
      if isNextWeek { return Day(offset: 7) }
      return turkishDayWord(tokens: tokens, isEvening: isEvening)
    }
    if isNextWeek {
      return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if tokens.first == "bu" {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// "bugün", "bu akşam", "bu gece", "yarın", "öbür gün" (each maybe with a part
  /// of the day, and with a case ending): today, tomorrow, and the day after,
  /// an evening for "akşam" and "gece".
  private static func turkishDayWord(tokens: [String], isEvening: Bool) -> Day? {
    if tokens.first == "obur" { return Day(offset: 2, isEvening: isEvening) }
    if tokens.first?.hasPrefix("yarin") == true { return Day(offset: 1, isEvening: isEvening) }
    if tokens.first?.hasPrefix("bugun") == true || tokens.first == "bu" {
      return Day(offset: 0, isEvening: isEvening)
    }
    return nil
  }
}
