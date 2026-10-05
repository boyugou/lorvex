import Foundation

extension LorvexCaptureVocabulary {
  // The Malay day rules: the due day, the planned day, and the date ranges. The
  // vocabulary's other words are in ``malay``.

  // MARK: - Weekdays, parts of the day, and months

  /// Each weekday's plain name, Sunday first.
  private static let malayWeekdayRow = ["ahad", "isnin", "selasa", "rabu", "khamis", "jumaat", "sabtu"]

  /// The weekday names, as a pattern without groups. "Jumaat" may be written
  /// with an apostrophe ("Juma'at"). "Minggu" is the week and no weekday, so
  /// Sunday is always "Ahad".
  static let malayWeekdayNames = #"selasa|isnin|sabtu|rabu|khamis|juma['’ʼ]?at|ahad"#

  /// One weekday written as a day, as a pattern without groups: a name, maybe
  /// after "hari" ("hari Isnin").
  static let malayWeekdayWord = #"(?:hari\s+)?(?:\#(malayWeekdayNames))"#

  /// The weekday a matched word names, 0 = Sunday: a name, maybe with "hari"
  /// before it.
  static func malayWeekdayIndex(_ word: String) -> Int? {
    guard let last = malayPhrase(word).split(separator: " ").last else { return nil }
    return malayWeekdayRow.firstIndex(of: String(last).replacingOccurrences(of: "'", with: ""))
  }

  /// "Tengah hari" (midday), written as two words or as one ("tengahari"), as a
  /// pattern without groups.
  static let malayMiddayWord = #"tengah(?:\s?hari|ari)"#

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: "esok pagi", "esok tengah hari", "Jumaat petang", "Sabtu
  /// malam".
  static let malayDayParts = #"(?:pagi|\#(malayMiddayWord)|petang|malam)"#

  /// The parts of the day that name a weekday's part when written before it, as
  /// a pattern without groups: "pagi Isnin", "petang Jumaat". "Malam Jumaat" is
  /// the night before Friday, which no rule names.
  private static let malayPartBeforeWeekday = #"(?:pagi|\#(malayMiddayWord)|petang)"#

  /// A lookbehind that fails after a word that forms a noun with the part of the
  /// day written next to it ("makan malam", "pasar malam", "rehat tengah hari",
  /// "kelas petang", "senaman pagi"). That part belongs to the noun, so it is not
  /// the part of a day that follows it: in "Makan malam esok" the day is "esok"
  /// and the title stays "Makan malam".
  static let malayNotNounBeforePart =
    #"(?<!(?:makan|minum|sarapan|pasar|rehat|kelas|kuliah|ceramah|senaman|latihan|solat|berita|kerja|syif)\s{1,3})"#

  /// The words that follow a weekday and set its week or put it in the past, as a
  /// pattern without groups: "ini", "depan", "hadapan", "minggu ini", "minggu
  /// depan", "lepas", "lalu", "minggu lepas", "yang lalu", "yang lepas".
  static let malayWeekdaySuffix =
    #"(?:\s+(?:minggu\s+)?(?:ini|depan|hadapan|lepas|lalu)|\s+yang\s+(?:lalu|lepas))"#

  /// Each month's names, January first: the full name, then the abbreviations.
  private static let malayMonthRows = [
    ["januari", "jan"], ["februari", "feb"], ["mac"], ["april", "apr"], ["mei"], ["jun"], ["julai", "jul"],
    ["ogos", "ogo"], ["september", "sept", "sep"], ["oktober", "okt"], ["november", "nov"], ["disember", "dis"],
  ]

  /// The month names and abbreviations, longest first, as a pattern without
  /// groups. "Mac" is March unless an Apple product's name follows it ("2 Mac
  /// mini" counts computers).
  static var malayMonthNames: String {
    let plain = alternation(of: malayMonthRows.flatMap { $0 }.filter { $0 != "mac" })
    return #"\#(plain)|mac(?!\s+(?:mini|pro|studio|air|os|book)(?![\p{Latin}\p{M}]))"#
  }

  /// The month a word names in any spelling, 0 = January.
  private static func malayMonthIndex(_ word: String) -> Int? {
    let key = malayKey(word)
    return malayMonthRows.firstIndex { $0.contains(key) }
  }

  // MARK: - Dates

  /// A day with its month and maybe a year, as a pattern without groups and with
  /// no condition on what comes before it: "5 Oktober", "5hb Oktober", "5 Okt.",
  /// "tarikh 5 Oktober", "5 Okt 2026". The day may carry "hb" (haribulan), with
  /// or without a space before it.
  private static var malayMonthDateBody: String {
    #"(?:tarikh\s*)?\d{1,2}(?:\s?hb\.?|\.)?\s*(?:\#(malayMonthNames))\.?(?![\p{Latin}\p{N}\p{M}])(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// A day with its month: "5 Oktober", "tarikh 5 Oktober", "5hb Oktober", "5 Okt
  /// 2026". A month needs its day number ("Oktober" alone is no date).
  static var malayMonthDatePattern: String {
    #"\#(malayNotAfterTanggal)(?<![\p{N}.,:/-])\#(malayMonthDateBody)"#
  }

  /// "5.10.2026": a day, a month, and a four-digit year with dots, which nothing
  /// else reads as. A number that goes on with more digits or dots is none.
  static let malayNumericDatePattern =
    #"\#(malayNotAfterTanggal)(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.\d{4}(?![\p{N}]|[.,/]\p{N})"#

  /// "5/10/2026", "5-10-2026", "5/10/26": a day, a month, and a year in digits,
  /// which nothing else reads as.
  static let malaySlashDatePattern =
    #"\#(malayNotAfterTanggal)(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// "5/10", "5-10": a day and a month in digits with no year, which a date reads
  /// only after a word that introduces it ("pada 5/10", "tarikh 5/10", "sebelum
  /// 5/10"), since "3-4 hari" and "skor 3-1" are other things.
  static let malayLooseDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*(?:jam|minit|min|hari|minggu|bulan|tahun|kali|x|orang|biji|buah|ekor|batang|keping|helai|peratus|ringgit|rm|kg|km|m|cm|mm|l)(?![\p{Latin}\p{N}\p{M}]))"#

  /// "tarikh 5", "5hb": a day of the month with no month, read as this month's
  /// or, once passed, next month's. "Hb" is read in lowercase only, since "2HB"
  /// is a pencil. It may not go on as a list or a range of days ("tarikh 5 dan 7",
  /// "5hb hingga 7hb").
  static let malayDayOfMonthPattern =
    #"(?:tarikh\s*\d{1,2}|(?<![\p{N}.,:/-])\d{1,2}(?-i:hb)\.?)(?![\p{Latin}\p{N}\p{M}%]|[.,:]\p{N})(?!\s*(?:[-–—/,&]|hingga|sehingga|sampai|dan|atau)\s*\d)"#

  /// The words after which a number with dots or dashes is a numbered item of
  /// the title, not a date: "bab 1-2", "versi 2-3", "skor 3-1".
  private static let malayNumberingPattern =
    #"(?:bab|muka\s+surat|ms\.?|m/s|halaman|hlm\.?|perenggan|fasal|ayat|nombor|no\.?|bil\.?|versi|ver\.?|bilik|dewan|tingkat|aras|lot|blok|kelas|kumpulan|langkah|peringkat|tahap|set|skor|markah|keputusan|tiket|slaid|bahagian|seksyen|soalan|gambar|rajah|jadual|lampiran|tugasan|tugas|task|lorong|pintu|platform|barisan|unit|rumah|jalan|siri)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func malayFollowsNumbering(_ match: Match) -> Bool {
    malayFinds(malayNumberingPattern, in: malayTextBefore(match))
  }

  /// A written-out date and whether it is written in digits only.
  private struct MalayWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``malayKey(_:)`` leaves it.
  private static func malayExplicitDate(_ key: String) -> MalayWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})(?:\s?hb\.?|\.)?\s*([a-z]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = malayMonthIndex(String(found.output.2))
    {
      return MalayWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-](\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return MalayWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    if let found = key.firstMatch(of: /(?:tarikh ?(\d{1,2})|(\d{1,2})hb)/),
      let day = (found.output.1 ?? found.output.2).flatMap({ number($0) })
    {
      return MalayWrittenDate(date: ExplicitDate(day: day), isNumeric: false)
    }
    return nil
  }

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, then maybe a comma ("Jumaat 16 Oktober", "Ahad, 4
  /// Oktober").
  static let malayWeekdayBeforeDate = #"(?:\#(malayWeekdayWord)\s*,?\s+)"#

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5 Oktober", "5hb Oktober
  /// 2027"), or a day alone ("5", "5hb", "tarikh 5"). The end of a range may
  /// follow its dash directly ("5-7 Oktober"), which a start may not.
  private static func malayRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let bare = #"(?:tarikh\s*)?\d{1,2}(?:\s?hb\.?)?\#(malayNoMoreDigits)"#
    return #"\#(lookbehind)\#(malayMonthDateBody)|\#(lookbehind)\#(bare)"#
  }

  /// "5-7 Oktober", "5 hingga 7 Oktober", "5 sehingga 7 Oktober", "5 sampai 7
  /// Oktober", "dari 5 hingga 7 Oktober", "5hb hingga 7hb Oktober", "antara 5 dan
  /// 7 Oktober", "5 Oktober - 7 Oktober", each maybe with a year after the end.
  /// Groups: 1 the word that opens the range, if any ("dari", "antara", "pada"), 2
  /// the start, 3 a dash between the sides, 4 the word between them ("hingga",
  /// "sehingga", "sampai", "dan"), 5 the end.
  static var malayDateRangePattern: String {
    let start = malayRangeSide(isEnd: false)
    let end = malayRangeSide(isEnd: true)
    return
      #"\#(malayStart)(?:(dari|antara|pada)\s+)?(\#(start))(?:\s*([-–—])\s*|\s+(hingga|sehingga|sampai|dan)\s+)(\#(end))(?![\p{Latin}\p{N}\p{M}]|[.,]\p{N})"#
  }

  static func malayDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5), let start = malayRangeDate(startText),
      let end = malayRangeDate(endText), end.month != nil
    else { return nil }
    let lead = match.group(1).map(malayPhrase)
    let word = match.group(4).map(malayPhrase)
    // "Dan" joins the sides after "antara" only, and "antara" takes no other joiner.
    if (lead == "antara") != (word == "dan") { return nil }
    // A start that is a day alone with a dash and no opening word reads only when the dash
    // touches both sides ("5-7 Oktober"): "Sprint 12 - 20 Mei" names a sprint and a date.
    if word == nil, start.month == nil, lead == nil || lead == "pada", !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range as a date: with its month, or a day alone, which has
  /// no month.
  private static func malayRangeDate(_ text: String) -> ExplicitDate? {
    let key = malayKey(text)
    if let found = malayExplicitDate(key), found.date.month != nil { return found.date }
    guard let day = key.wholeMatch(of: /(?:tarikh ?)?(\d{1,2})(?:\s?hb\.?)?/), let value = number(day.output.1) else {
      return nil
    }
    return ExplicitDate(day: value)
  }

  /// "dari Isnin hingga Rabu", "Isnin sehingga Rabu", "hari Jumaat sampai hari
  /// Ahad", "Isnin - Rabu": a span of weekdays. Groups: 1 "dari", 2 and 5 the first
  /// and the last weekday, 3 the word between them, 4 a dash.
  static var malayWeekdayRangePattern: String {
    let day = malayWeekdayWord
    return
      #"\#(malayStart)(?:(dari)\s+)?(\#(day))(?:\s+(hingga|sehingga|sampai)\s+|\s*([-–—])\s*)(\#(day))\#(malayEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "Rabu hingga Jumaat" runs from tomorrow to
  /// Friday and "Isnin hingga Rabu" from next Monday to the Wednesday after it,
  /// where reading the two weekdays apart would plan next Monday and make the
  /// task due tomorrow. A span after "setiap" or "tiap" repeats, which the repeat
  /// rules read, and a span from a day to itself is no span.
  static func malayWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(2), let lastWord = match.group(5), let first = malayWeekdayIndex(firstWord),
      let last = malayWeekdayIndex(lastWord), first != last, !malayIsEveryWordBefore(match)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// Whether the word before `match` is "setiap" or "tiap".
  static func malayIsEveryWordBefore(_ match: Match) -> Bool {
    guard let word = wordBefore(match) else { return false }
    return word == "setiap" || word == "tiap"
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "sebelum",
  /// "paling lewat" ("paling lambat", "selewat-lewatnya", "selambat-lambatnya"),
  /// "hingga", "sehingga", "sampai", "tarikh akhir" ("tarikh tamat", "tarikh
  /// tutup", "tarikh jangka"), "had masa", "deadline", each with its colon or
  /// space and maybe "pada" after it.
  static let malayDueLead =
    #"(?:paling\s+(?:lewat|lambat)|selewat[\s-]?lewatnya|selambat[\s-]?lambatnya|sebelum|sehingga|hingga|sampai|tarikh\s+(?:akhir|tamat|tutup|jangka)|had\s+masa|deadline)(?:\s*:\s*|\s+)(?:pada\s+)?"#

  /// The days a due phrase may name, as a pattern without groups: hari ini,
  /// esok, lusa (each maybe with a part of the day), a weekday (maybe with ini,
  /// depan, hadapan, or a part of the day), next week, and a date, maybe after
  /// its weekday. The weekend and a count of days are no due day.
  static var malayDueDay: String {
    let names = malayWeekdayWord
    let part = malayDayParts
    let alternatives = [
      #"hari\s+ini"#,
      #"(?:esok|besok)(?:\s+\#(part))?"#,
      #"\#(malayNotNounBeforePart)\#(part)\s+(?:esok|besok)"#,
      #"(?<!(?:kelmarin|kemarin|semalam)\s{1,3})lusa(?:\s+\#(part))?"#,
      #"\#(malayWeekdayBeforeDate)(?:\#(malayMonthDatePattern)|\#(malayNumericDatePattern)|\#(malaySlashDatePattern)|\#(malayLooseDatePattern))"#,
      #"minggu\s+(?:depan|hadapan)\s+\#(names)"#,
      #"\#(malayNotNounBeforePart)\#(malayPartBeforeWeekday)\s+\#(names)\#(malayWeekdaySuffix)?"#,
      #"\#(names)\#(malayWeekdaySuffix)?(?:\s+\#(part))?"#,
      #"minggu\s+(?:depan|hadapan)"#,
      malayMonthDatePattern, malayNumericDatePattern, malaySlashDatePattern, malayLooseDatePattern,
      malayDayOfMonthPattern,
    ]
    return alternatives.joined(separator: "|")
  }

  /// "sebelum Jumaat", "tarikh akhir 15 Oktober", "hingga esok", "sampai hari
  /// Isnin", "deadline 5/10", "selewat-lewatnya 5hb Oktober". Group 1: the day
  /// after a word that introduces it.
  static var malayDuePattern: String {
    #"\#(malayStart)\#(malayDueLead)(\#(malayDueDay))\#(malayEnd)\#(malayNotIndonesianPart)"#
  }

  static func malayDue(_ match: Match) -> Day? {
    match.group(1).flatMap { malayDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "hari ini", "pagi ini", "petang ini", "malam ini", "malam nanti", "esok",
  /// "esok pagi", "malam esok", "lusa", "minggu depan", "hujung minggu", "weekend", "3
  /// hari lagi", "dalam 3 hari", "seminggu lagi", a weekday ("Isnin", "hari Isnin",
  /// "pada Isnin", "Isnin ini", "Isnin depan", "Isnin minggu depan", "minggu depan
  /// Isnin", "Jumaat petang", "petang Jumaat", "Sabtu dan Ahad"), and a date, maybe
  /// with its weekday ("pada 5 Oktober", "Jumaat 16 Oktober", "tarikh 5", "pada
  /// 5hb", "pada 5/10"). Group 1: the day, with the words that introduce it.
  static var malayWhenPattern: String {
    let names = malayWeekdayWord
    let part = malayDayParts
    let count = #"(?:\d{1,3}|\#(malayNumberWords))"#
    let weekend =
      #"(?:(?:di|pada)\s+)?(?:hujung\s+minggu|weekend)(?:\s+(?:ini|depan|hadapan|lepas|lalu|yang\s+(?:lalu|lepas)))?"#
    // A count after "kali" is a rate ("tiga kali dalam 2 hari"), not a day.
    let counts = [
      #"(?<!kali\s{1,3})dalam\s+\#(count)\s+(?:hari|minggu)(?!\s+(?:bekerja|kerja|cuti|lepas|lalu|terakhir|akan\s+datang|sebelum))(?:\s+lagi)?"#,
      #"\#(count)\s+(?:hari|minggu)\s+lagi"#,
      #"(?:sehari|seminggu)\s+lagi"#,
    ]
    let today =
      #"hari\s+ini|(?:pagi|petang|malam)\s+ini|\#(malayMiddayWord)\s+ini|(?:malam|petang)\s+nanti|nanti\s+(?:petang|malam)"#
    let dateLead = #"(?:pada\s+)?"#
    let looseLead = #"(?:(?:pada\s+)?tarikh\s*|pada\s+)"#
    let strict = #"\#(malayMonthDatePattern)|\#(malayNumericDatePattern)|\#(malaySlashDatePattern)"#
    let weekdayPair = #"(?:hari\s+)?sabtu\s*(?:dan|&|,)\s*(?:hari\s+)?ahad"#
    let partFirst =
      #"(?:pada\s+)?\#(malayNotNounBeforePart)\#(malayPartBeforeWeekday)\s+\#(names)\#(malayWeekdaySuffix)?"#
    let weekday = #"(?:pada\s+)?\#(names)\#(malayWeekdaySuffix)?(?:\s+\#(part))?"#
    let alternatives =
      [
        #"minggu\s+(?:depan|hadapan|ini)\s+\#(names)"#,
        #"minggu\s+(?:depan|hadapan)"#,
        weekend,
      ] + counts + [
        today,
        #"(?:esok|besok)(?:\s+\#(part))?"#,
        #"\#(malayNotNounBeforePart)\#(part)\s+(?:esok|besok)"#,
        #"(?<!(?:kelmarin|kemarin|semalam)\s{1,3})lusa(?:\s+\#(part))?"#,
        #"\#(dateLead)(?:\#(malayWeekdayBeforeDate))?(?:\#(strict))"#,
        #"\#(looseLead)(?:\#(malayWeekdayBeforeDate))?\#(malayLooseDatePattern)"#,
        #"\#(dateLead)\#(malayDayOfMonthPattern)"#,
        weekdayPair,
        partFirst,
        weekday,
      ]
    return #"\#(malayStart)(\#(alternatives.joined(separator: "|")))\#(malayEnd)\#(malayNotIndonesianPart)"#
  }

  static func malayWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { malayDay($0, in: match) }
  }

  /// The words after which a day is left out of a phrase, not named ("setiap hari
  /// kecuali Ahad").
  private static let malayExceptWords: Set<String> = ["kecuali", "selain", "tanpa"]

  /// The weekday a day phrase's words name, 0 = Sunday.
  private static func malayPhraseWeekday(_ tokens: [String]) -> Int? {
    for token in tokens {
      if let weekday = malayWeekdayIndex(token) { return weekday }
    }
    return nil
  }

  /// The count of units a day phrase spells, in days: "dalam 3 hari", "3 hari
  /// lagi", "2 minggu lagi", "seminggu lagi", "dalam 3 hari lagi".
  private static func malayCountedDays(_ phrase: String) -> Int? {
    let key = malayPhrase(phrase)
    func days(_ count: Int, _ unit: Substring) -> Int { unit == "hari" ? count : count * 7 }
    if let found = key.wholeMatch(of: /dalam (\d{1,3}|[a-z]+(?: [a-z]+){0,2}) (hari|minggu)(?: lagi)?/),
      let count = malayCount(String(found.output.1))
    {
      return days(count, found.output.2)
    }
    if let found = key.wholeMatch(of: /(\d{1,3}|[a-z]+(?: [a-z]+){0,2}) (hari|minggu) lagi/),
      let count = malayCount(String(found.output.1))
    {
      return days(count, found.output.2)
    }
    if let found = key.wholeMatch(of: /(sehari|seminggu) lagi/) {
      return found.output.1 == "sehari" ? 1 : 7
    }
    return nil
  }

  /// Whether the weekday `match` names stands in a list of weekdays ("Isnin dan
  /// Rabu", "Isnin atau Selasa", "Isnin, Rabu"): a list names no one day, so none
  /// of its weekdays is read, and the whole list stays in the title. "Sabtu dan
  /// Ahad" is the weekend, which a rule of its own reads before this one is asked.
  private static func malayIsInWeekdayList(_ match: Match) -> Bool {
    let names = malayWeekdayNames
    let separator = #"\s*(?:,\s*(?:dan|atau|serta)|,|dan|atau|serta|&)\s*(?:hari\s+)?"#
    let day = #"(?:hari\s+)?(?:\#(names))"#
    let part = #"(?:\s+(?:pagi|\#(malayMiddayWord)|petang|malam))?"#
    return malayFinds(#"^\#(separator)(?:\#(names))(?![\p{Latin}\p{M}])"#, in: malayTextAfter(match))
      || malayFinds(#"(?<![\p{Latin}\p{M}])\#(day)\#(part)\#(separator)$"#, in: malayTextBefore(match))
  }

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when the phrase names no day, or a past one ("Isnin
  /// lepas"), or follows "kecuali", or is one weekday of a list.
  private static func malayDay(_ phrase: String, in match: Match) -> Day? {
    if let before = wordBefore(match).map(malayKey), malayExceptWords.contains(before) { return nil }
    let key = malayKey(phrase)
    let tokens = malayPhrase(phrase).split(separator: " ").map {
      String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
    }
    let isEvening = tokens.contains("malam")
    if let found = malayExplicitDate(key) {
      if found.isNumeric, malayFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let days = malayCountedDays(phrase) { return Day(offset: days) }
    let pastWords: Set<String> = ["lepas", "lalu"]
    if tokens.contains(where: { pastWords.contains($0) }) { return nil }
    let todayWeekday = match.todayWeekday
    if tokens.contains("weekend") || (tokens.contains("hujung") && tokens.contains("minggu")) {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: tokens.contains("depan") || tokens.contains("hadapan") ? weekend + 7 : weekend)
    }
    // "Sabtu dan Ahad": both days of the weekend, planned from the first.
    if tokens.contains("sabtu"), tokens.contains("ahad"), tokens.contains(where: { $0 == "dan" || $0 == "&" }) {
      return Day(offset: weekendOffset(todayWeekday: todayWeekday))
    }
    if let weekday = malayPhraseWeekday(tokens) {
      if malayIsInWeekdayList(match) { return nil }
      if tokens.contains("depan") || tokens.contains("hadapan") {
        return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      if tokens.contains("ini") {
        return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if (tokens.contains("depan") || tokens.contains("hadapan")), tokens.contains("minggu") {
      return Day(offset: 7)
    }
    if tokens.contains("lusa") { return Day(offset: 2, isEvening: isEvening) }
    if tokens.contains("esok") || tokens.contains("besok") { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains("hari") || tokens.contains("ini") || tokens.contains("nanti") {
      return Day(offset: 0, isEvening: isEvening)
    }
    return nil
  }

  // MARK: - Text that names no day

  /// "Isnin pertama", "Jumaat terakhir bulan ini", "setiap Selasa kedua", "Isnin
  /// minggu kedua": a weekday by its place in the month. The repeat has no such
  /// rule and no day rule can name it, so the text stays in the title whole, with
  /// no part of it read as a weekday.
  static let malayOrdinalWeekdayPattern =
    #"\#(malayStart)(?:(?:setiap|tiap(?:[-\s]tiap)?)\s+)?\#(malayWeekdayWord)\s+(?:minggu\s+)?(?:pertama|kedua|ketiga|keempat|kelima|terakhir)(?:\s+(?:dalam|di|pada|setiap|tiap)\s+(?:bulan|setiap\s+bulan))?\#(malayEnd)"#

  /// "sebelum hujung minggu", "hingga weekend", "selepas hujung minggu", "untuk
  /// hujung minggu", and "hujung minggu lepas": a bound at the weekend, a weekend
  /// a task is for, or a past one. None names a day the planner can set, so the
  /// whole phrase stays in the title, where English would otherwise plan the bare
  /// "weekend" with the preposition left behind.
  static let malayNoDayWeekendPattern =
    #"\#(malayStart)(?:(?:sebelum|sehingga|hingga|sampai|menjelang|selepas|lepas|setelah|sesudah|selama|untuk|buat|semasa|sepanjang)\s+(?:hujung\s+minggu|weekend)(?:\s+(?:ini|depan|hadapan|lepas|lalu))?|(?:hujung\s+minggu|weekend)\s+(?:lepas|lalu|yang\s+(?:lalu|lepas)))\#(malayEnd)"#

  /// "esok lusa", "malam Jumaat", "malam Sabtu": phrases the reader cannot give
  /// one day. "Esok lusa" means tomorrow or the day after, or soon, and "malam
  /// Jumaat" is the night before Friday, so both stay in the title whole. "Makan
  /// malam Jumaat" and "Kelas malam Jumaat" are dinner and a class on Friday, and
  /// read as Friday.
  static let malayVagueDayPattern =
    #"\#(malayStart)(?:(?:esok|besok)\s+lusa|\#(malayNotNounBeforePart)malam\s+(?:\#(malayWeekdayNames)))\#(malayEnd)"#

  /// "solat Jumaat", "khutbah Jumaat", "Jumaat Agung": the name of a prayer or a
  /// holiday with a weekday in it, which names no day to plan, so the whole name
  /// stays in the title.
  static let malayNamedWeekdayPattern =
    #"\#(malayStart)(?:(?:solat|sembahyang|salat|khutbah)\s+juma['’ʼ]?at|juma['’ʼ]?at\s+agung)\#(malayEnd)"#
}
