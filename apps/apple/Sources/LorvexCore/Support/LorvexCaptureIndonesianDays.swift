import Foundation

extension LorvexCaptureVocabulary {
  // The Indonesian day rules: the due day, the planned day, and the date ranges.
  // The vocabulary's other words are in ``indonesian``.

  // MARK: - Weekdays, parts of the day, and months

  /// Each weekday's plain name, Sunday first.
  private static let indonesianWeekdayRow = ["minggu", "senin", "selasa", "rabu", "kamis", "jumat", "sabtu"]

  /// The weekday names but Sunday, as a pattern without groups. "Jum'at" is
  /// written with an apostrophe in either form.
  static let indonesianWeekdayNames = #"selasa|senin|sabtu|rabu|kamis|jum['’ʼ]?at"#

  /// One weekday written as a day, as a pattern without groups: a name, maybe
  /// after "hari" ("hari Senin"), "hari Minggu", or "Minggu" before a part of the
  /// day ("Minggu pagi", "Minggu malam"). "Minggu" alone is the week, so Sunday
  /// needs its "hari" or its part of the day.
  static let indonesianWeekdayWord =
    #"(?:(?:hari\s+)?(?:\#(indonesianWeekdayNames))|hari\s+minggu|minggu(?=\s+(?:pagi|siang|sore|malam)(?![\p{Latin}\p{M}])))"#

  /// One weekday where another stands beside it (a range, a list), as a pattern
  /// without groups: "Minggu" alone is Sunday there.
  static let indonesianWeekdayWordOrSunday = #"(?:hari\s+)?(?:\#(indonesianWeekdayNames)|minggu)"#

  /// The weekday a matched word names, 0 = Sunday: a name, maybe with "hari"
  /// before it. The word's own "Minggu" counts as Sunday, so the caller decides
  /// where that is right.
  static func indonesianWeekdayIndex(_ word: String) -> Int? {
    guard let last = indonesianPhrase(word).split(separator: " ").last else { return nil }
    return indonesianWeekdayRow.firstIndex(of: String(last).replacingOccurrences(of: "'", with: ""))
  }

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: "besok pagi", "Jumat sore", and with the intensifier that
  /// goes with them, "besok pagi sekali" (very early tomorrow morning), so the
  /// intensifier does not stay behind in the title.
  static let indonesianDayParts = #"(?:pagi|siang|sore|malam)(?:\s+sekali)?"#

  /// The words that follow a weekday and set its week or put it in the past, as
  /// a pattern without groups: "ini", "depan", "minggu ini", "minggu depan",
  /// "lalu", "minggu lalu", "yang lalu", "kemarin".
  static let indonesianWeekdaySuffix =
    #"(?:\s+(?:(?:minggu|pekan)\s+)?(?:ini|depan|lalu|kemarin)|\s+yang\s+lalu)"#

  /// Each month's names, January first: the full name, then the abbreviations
  /// and the older spellings.
  private static let indonesianMonthRows = [
    ["januari", "jan"], ["februari", "pebruari", "feb"], ["maret", "mar"], ["april", "apr"], ["mei"], ["juni", "jun"],
    ["juli", "jul"], ["agustus", "agu", "agt", "ags"], ["september", "sept", "sep"], ["oktober", "okt"],
    ["november", "nopember", "nov"], ["desember", "des"],
  ]

  /// The month names and abbreviations, longest first, as a pattern without
  /// groups.
  static var indonesianMonthNames: String {
    alternation(of: indonesianMonthRows.flatMap { $0 })
  }

  /// The month a word names in any spelling, 0 = January.
  private static func indonesianMonthIndex(_ word: String) -> Int? {
    let key = indonesianKey(word)
    return indonesianMonthRows.firstIndex { $0.contains(key) }
  }

  // MARK: - Dates

  /// A day with its month and maybe a year, as a pattern without groups and
  /// with no condition on what comes before it: "5 Oktober", "5 Okt.", "tanggal
  /// 5 Oktober", "tgl. 5 Okt 2026".
  private static var indonesianMonthDateBody: String {
    #"(?:(?:tanggal|tgl\.?)\s*)?\d{1,2}\.?\s*(?:\#(indonesianMonthNames))\.?(?![\p{Latin}\p{N}\p{M}])(?:\s+(?:19|20)\d{2}(?!\p{N}))?"#
  }

  /// A day with its month: "5 Oktober", "tanggal 5 Oktober", "5 Okt 2026". A
  /// month needs its day number ("Oktober" alone is no date).
  static var indonesianMonthDatePattern: String {
    #"(?<![\p{N}.,:/-])\#(indonesianMonthDateBody)"#
  }

  /// "5.10.2026": a day, a month, and a four-digit year with dots, which
  /// nothing else reads as. A number that goes on with more digits or dots is
  /// none.
  static let indonesianNumericDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.\d{4}(?![\p{N}]|[.,/]\p{N})"#

  /// "5/10/2026", "5-10-2026", "5/10/26": a day, a month, and a year in
  /// digits, which nothing else reads as.
  static let indonesianSlashDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})(?![\p{N}]|[.,/]\p{N})"#

  /// "5/10", "5-10": a day and a month in digits with no year, which a date
  /// reads only after a word that introduces it ("pada 5/10", "tanggal 5/10",
  /// "sebelum 5/10"), since "3-4 hari" and "skor 3-1" are other things.
  static let indonesianLooseDatePattern =
    #"(?<![\p{N}.,:/-])\d{1,2}[/-]\d{1,2}(?![\p{N}]|[.,/]\p{N}|[-–]\p{N})(?!\s*(?:jam|menit|mnt|min|hari|minggu|pekan|bulan|tahun|kali|x|orang|buah|biji|porsi|persen|rupiah|rp|kg|km|m|cm|mm|l)(?![\p{Latin}\p{N}\p{M}]))"#

  /// "tanggal 5", "tgl. 5": a day of the month with no month, read as this
  /// month's or, once passed, next month's. It may not go on as a list or a
  /// range of days ("tanggal 5 dan 7", "tanggal 5 sampai 7").
  static let indonesianDayOfMonthPattern =
    #"(?:tanggal|tgl\.?)\s*\d{1,2}\#(indonesianNoMoreDigits)(?!\s*(?:[-–—/,&]|sampai|hingga|s/d|dan|atau)\s*\d)"#

  /// The words after which a number with dots or dashes is a numbered item of
  /// the title, not a date: "bab 1-2", "versi 2-3", "skor 3-1".
  private static let indonesianNumberingPattern =
    #"(?:bab|halaman|hal\.?|hlm\.?|pasal|ayat|nomor|nomer|no\.?|versi|ver\.?|ruang|ruangan|kamar|lantai|baris|jalur|peron|kelas|kelompok|grup|tahap|langkah|level|babak|set|skor|nilai|hasil|tiket|build|bug|slide|seksi|bagian|pelajaran|latihan|soal|gambar|tabel|lampiran|tugas|task)\s*$"#

  /// Whether the word before `match` makes a number a numbered item of the
  /// title.
  private static func indonesianFollowsNumbering(_ match: Match) -> Bool {
    indonesianFinds(indonesianNumberingPattern, in: indonesianTextBefore(match))
  }

  /// A written-out date and whether it is written in digits only.
  private struct IndonesianWrittenDate {
    var date: ExplicitDate
    var isNumeric: Bool
  }

  /// The date a day phrase names, in the phrase as ``indonesianKey(_:)`` leaves
  /// it.
  private static func indonesianExplicitDate(_ key: String) -> IndonesianWrittenDate? {
    guard key.contains(where: \.isNumber) else { return nil }
    if let found = key.firstMatch(of: /(\d{1,2})\.?\s*([a-z]+)\.?(?:\s+((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = indonesianMonthIndex(String(found.output.2))
    {
      return IndonesianWrittenDate(
        date: ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month + 1, day: day), isNumeric: false)
    }
    if let found = key.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-](\d{4}|\d{2})(?!\d))?/),
      let day = number(found.output.1), let month = number(found.output.2)
    {
      let year = found.output.3.flatMap { number($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
      return IndonesianWrittenDate(date: ExplicitDate(year: year, month: month, day: day), isNumeric: true)
    }
    if let found = key.firstMatch(of: /(?:tanggal|tgl\.?) ?(\d{1,2})/), let day = number(found.output.1) {
      return IndonesianWrittenDate(date: ExplicitDate(day: day), isNumeric: false)
    }
    return nil
  }

  /// A weekday written before the date it belongs to, as a pattern without
  /// groups: its name, then maybe a comma ("Jumat 16 Oktober", "Minggu, 4
  /// Oktober"). A date follows, so "Minggu" alone is Sunday here.
  static let indonesianWeekdayBeforeDate = #"(?:\#(indonesianWeekdayWordOrSunday)\s*,?\s+)"#

  // MARK: - Date range

  /// A side of a date range: a date with its month ("5 Oktober", "tanggal 5
  /// Oktober 2027"), or a day alone ("5", "tanggal 5"). The end of a range may
  /// follow its dash directly ("5-7 Oktober"), which a start may not.
  private static func indonesianRangeSide(isEnd: Bool) -> String {
    let lookbehind = isEnd ? #"(?<![\p{N}.,:/])"# : #"(?<![\p{N}.,:/-])"#
    let bare = #"(?:(?:tanggal|tgl\.?)\s*)?\d{1,2}\#(indonesianNoMoreDigits)"#
    return #"\#(lookbehind)\#(indonesianMonthDateBody)|\#(lookbehind)\#(bare)"#
  }

  /// "5-7 Oktober", "5 sampai 7 Oktober", "5 s/d 7 Oktober", "dari 5 hingga 7
  /// Oktober", "dari tanggal 5 sampai tanggal 7 Oktober", "antara 5 dan 7
  /// Oktober", "5 Oktober - 7 Oktober", each maybe with a year after the end.
  /// Groups: 1 the word that opens the range, if any ("dari", "antara",
  /// "pada"), 2 the start, 3 a dash between the sides, 4 the word between them
  /// ("sampai", "sampai dengan", "hingga", "s/d", "dan"), 5 the end.
  static var indonesianDateRangePattern: String {
    let start = indonesianRangeSide(isEnd: false)
    let end = indonesianRangeSide(isEnd: true)
    return
      #"\#(indonesianStart)(?:(dari|antara|pada)\s+)?(\#(start))(?:\s*([-–—])\s*|\s+(sampai\s+dengan|sampai|hingga|s/d|s\.d\.|dan)\s+)(\#(end))(?![\p{Latin}\p{N}\p{M}]|[.,]\p{N})"#
  }

  static func indonesianDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(2), let endText = match.group(5),
      let start = indonesianRangeDate(startText), let end = indonesianRangeDate(endText), end.month != nil
    else { return nil }
    let lead = match.group(1).map(indonesianPhrase)
    let word = match.group(4).map(indonesianPhrase)
    // "Dan" joins the sides after "antara" only, and "antara" takes no other joiner.
    if (lead == "antara") != (word == "dan") { return nil }
    // A start that is a day alone with a dash and no opening word reads only when the dash
    // touches both sides ("5-7 Oktober"): "Sprint 12 - 20 Mei" names a sprint and a date.
    if word == nil, start.month == nil, lead == nil || lead == "pada", !dashTouchesBothSides(match, start: 2, end: 5) {
      return nil
    }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range as a date: with its month, or a day alone, which
  /// has no month.
  private static func indonesianRangeDate(_ text: String) -> ExplicitDate? {
    let key = indonesianKey(text)
    if let found = indonesianExplicitDate(key), found.date.month != nil { return found.date }
    guard let day = key.wholeMatch(of: /(?:(?:tanggal|tgl\.?) ?)?(\d{1,2})/), let value = number(day.output.1) else {
      return nil
    }
    return ExplicitDate(day: value)
  }

  /// "dari Senin sampai Rabu", "Senin hingga Rabu", "hari Jumat sampai hari
  /// Minggu", "Senin - Rabu": a span of weekdays. Groups: 1 "dari", 2 and 5 the
  /// first and the last weekday, 3 the word between them, 4 a dash.
  static var indonesianWeekdayRangePattern: String {
    let day = indonesianWeekdayWordOrSunday
    return
      #"\#(indonesianStart)(?:(dari)\s+)?(\#(day))(?:\s+(sampai\s+dengan|sampai|hingga|s/d|s\.d\.)\s+|\s*([-–—])\s*)(\#(day))\#(indonesianEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "Rabu sampai Jumat" runs from tomorrow to
  /// Friday and "Senin sampai Rabu" from next Monday to the Wednesday after it,
  /// where reading the two weekdays apart would plan next Monday and make the
  /// task due tomorrow. A span after "setiap" or "tiap" repeats, which the
  /// repeat rules read, and a span from a day to itself is no span.
  static func indonesianWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(2), let lastWord = match.group(5),
      let first = indonesianWeekdayIndex(firstWord), let last = indonesianWeekdayIndex(lastWord),
      first != last, !indonesianIsEveryWordBefore(match)
    else { return nil }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }

  /// Whether the word before `match` is "setiap" or "tiap".
  static func indonesianIsEveryWordBefore(_ match: Match) -> Bool {
    guard let word = wordBefore(match) else { return false }
    return word == "setiap" || word == "tiap"
  }

  // MARK: - Due day

  /// The words that introduce a due day, as a pattern without groups: "sebelum",
  /// "paling lambat" ("paling telat", "selambat-lambatnya"), "sampai" ("sampai
  /// dengan"), "hingga", "tenggat" ("tenggat waktu"), "batas waktu", "batas
  /// akhir", "deadline", "jatuh tempo", "maksimal", each with its colon or space.
  static let indonesianDueLead =
    #"(?:paling\s+(?:lambat|telat)|selambat[\s-]?lambatnya|selambatnya|sebelum|sampai(?:\s+dengan)?|hingga|tenggat(?:\s+waktu)?|batas\s+(?:waktu|akhir)|deadline|jatuh\s+tempo|maksimal|maks\.?)(?:\s*:\s*|\s+)"#

  /// The days a due phrase may name, as a pattern without groups: hari ini,
  /// besok, lusa (each maybe with a part of the day), a weekday (maybe with ini,
  /// depan, or a part of the day), next week, and a date, maybe after its
  /// weekday. The weekend and a count of days are no due day.
  static var indonesianDueDay: String {
    let names = indonesianWeekdayWord
    let part = indonesianDayParts
    let alternatives = [
      #"hari\s+ini"#,
      #"besok(?:\s+(?:\#(part)))?"#,
      #"(?<!kemarin\s{1,3})lusa(?:\s+(?:\#(part)))?"#,
      #"\#(indonesianWeekdayBeforeDate)(?:\#(indonesianMonthDatePattern)|\#(indonesianNumericDatePattern)|\#(indonesianSlashDatePattern)|\#(indonesianLooseDatePattern))"#,
      #"(?:minggu|pekan)\s+depan\s+\#(names)"#,
      #"\#(names)\#(indonesianWeekdaySuffix)?(?:\s+(?:\#(part)))?"#,
      #"(?:minggu|pekan)\s+depan"#,
      indonesianMonthDatePattern, indonesianNumericDatePattern, indonesianSlashDatePattern, indonesianLooseDatePattern,
      indonesianDayOfMonthPattern,
    ]
    return alternatives.joined(separator: "|")
  }

  /// "sebelum Jumat", "paling lambat tanggal 15 Oktober", "tenggat besok",
  /// "sampai hari Senin", "deadline 5/10", "jatuh tempo 5 Oktober". Group 1: the
  /// day after a word that introduces it.
  static var indonesianDuePattern: String {
    #"\#(indonesianStart)\#(indonesianDueLead)(\#(indonesianDueDay))\#(indonesianEnd)"#
  }

  static func indonesianDue(_ match: Match) -> Day? {
    match.group(1).flatMap { indonesianDay($0, in: match) }.map { Day(offset: $0.offset) }
  }

  // MARK: - Planned day

  /// "hari ini", "pagi ini", "siang ini", "sore ini", "malam ini", "nanti
  /// malam", "besok", "besok pagi", "lusa", "minggu depan", "pekan depan",
  /// "akhir pekan", "weekend", "3 hari lagi", "dalam 3 hari", "seminggu lagi", a
  /// weekday ("Senin", "hari Senin", "pada Senin", "Senin ini", "Senin depan",
  /// "Senin minggu depan", "minggu depan Senin", "Jumat sore", "Sabtu dan
  /// Minggu"), and a date, maybe with its weekday ("pada 5 Oktober", "Jumat 16
  /// Oktober", "tanggal 5", "pada 5/10"). Group 1: the day, with the words that
  /// introduce it.
  static var indonesianWhenPattern: String {
    let names = indonesianWeekdayWord
    let part = indonesianDayParts
    let count = #"(?:\d{1,3}|\#(indonesianNumberWords))"#
    let weekend =
      #"(?:(?:di|pada)\s+)?(?:akhir\s+pekan|weekend)(?:\s+(?:ini|depan|lalu|kemarin|yang\s+lalu))?"#
    // A count after "kali" or "sekali" is a rate ("dua kali dalam seminggu"), not a day.
    let counts = [
      #"(?<!kali\s{1,3})dalam\s+\#(count)\s+(?:hari|minggu|pekan)(?!\s+(?:kerja|libur|ke\s+depan|terakhir|lalu|kemarin))"#,
      #"\#(count)\s+(?:hari|minggu|pekan)\s+lagi"#,
      #"(?:sehari|seminggu|sepekan)\s+lagi|(?<!kali\s{1,3})dalam\s+(?:sehari|seminggu|sepekan)"#,
    ]
    let today = #"hari\s+ini|(?:pagi|siang|sore|malam)\s+ini|nanti\s+(?:siang|sore|malam)"#
    let dateLead = #"(?:pada\s+)?"#
    let looseLead = #"(?:(?:pada\s+)?(?:tanggal|tgl\.?)\s*|pada\s+)"#
    let strict = #"\#(indonesianMonthDatePattern)|\#(indonesianNumericDatePattern)|\#(indonesianSlashDatePattern)"#
    let weekdayPair = #"(?:hari\s+)?sabtu\s*(?:dan|&|,)\s*(?:hari\s+)?minggu"#
    let weekday = #"(?:(?:pada|di)\s+)?\#(names)\#(indonesianWeekdaySuffix)?(?:\s+(?:\#(part)))?"#
    let alternatives =
      [
        #"(?:minggu|pekan)\s+(?:depan|ini)\s+\#(names)"#,
        #"(?:minggu|pekan)\s+depan"#,
        weekend,
      ] + counts + [
        today,
        #"besok(?:\s+(?:\#(part)))?"#,
        #"(?<!kemarin\s{1,3})lusa(?:\s+(?:\#(part)))?"#,
        #"\#(dateLead)(?:\#(indonesianWeekdayBeforeDate))?(?:\#(strict))"#,
        #"\#(looseLead)(?:\#(indonesianWeekdayBeforeDate))?\#(indonesianLooseDatePattern)"#,
        #"\#(dateLead)\#(indonesianDayOfMonthPattern)"#,
        weekdayPair,
        weekday,
      ]
    return #"\#(indonesianStart)(\#(alternatives.joined(separator: "|")))\#(indonesianEnd)"#
  }

  static func indonesianWhen(_ match: Match) -> Day? {
    match.group(1).flatMap { indonesianDay($0, in: match) }
  }

  /// The words after which a day is left out of a phrase, not named ("setiap
  /// hari kecuali Minggu").
  private static let indonesianExceptWords: Set<String> = ["kecuali", "selain", "tanpa"]

  /// The weekday a day phrase's words name, 0 = Sunday: "Minggu" counts only
  /// after "hari" ("hari Minggu") or before a part of the day ("Minggu pagi"),
  /// since alone it is the week.
  private static func indonesianPhraseWeekday(_ tokens: [String]) -> Int? {
    let parts: Set<String> = ["pagi", "siang", "sore", "malam"]
    for (index, token) in tokens.enumerated() {
      if token == "minggu" {
        if index > 0, tokens[index - 1] == "hari" { return 0 }
        if index + 1 < tokens.count, parts.contains(tokens[index + 1]) { return 0 }
        continue
      }
      if let weekday = indonesianWeekdayIndex(token), weekday != 0 { return weekday }
    }
    return nil
  }

  /// The count of units a day phrase spells, in days: "dalam 3 hari", "3 hari
  /// lagi", "2 minggu lagi", "seminggu lagi", "dalam sepekan".
  private static func indonesianCountedDays(_ phrase: String) -> Int? {
    let key = indonesianPhrase(phrase)
    func days(_ count: Int, _ unit: Substring) -> Int { unit == "hari" ? count : count * 7 }
    if let found = key.wholeMatch(of: /dalam (\d{1,3}|[a-z]+(?: [a-z]+){0,2}) (hari|minggu|pekan)/),
      let count = indonesianCount(String(found.output.1))
    {
      return days(count, found.output.2)
    }
    if let found = key.wholeMatch(of: /(\d{1,3}|[a-z]+(?: [a-z]+){0,2}) (hari|minggu|pekan) lagi/),
      let count = indonesianCount(String(found.output.1))
    {
      return days(count, found.output.2)
    }
    if let found = key.wholeMatch(of: /(?:dalam )?(sehari|seminggu|sepekan)(?: lagi)?/) {
      return found.output.1 == "sehari" ? 1 : 7
    }
    return nil
  }

  /// Whether the weekday `match` names stands in a list of weekdays ("Senin dan
  /// Rabu", "Senin atau Selasa", "Senin, Rabu"): a list names no one day, so none
  /// of its weekdays is read, and the whole list stays in the title. "Sabtu dan
  /// Minggu" is the weekend, which a rule of its own reads before this one is
  /// asked.
  private static func indonesianIsInWeekdayList(_ match: Match) -> Bool {
    let day = #"(?:(?:hari\s+)?(?:\#(indonesianWeekdayNames))|hari\s+minggu)"#
    let separator = #"\s*(?:,\s*(?:dan|atau|serta)|,|dan|atau|serta|&)\s*(?:hari\s+)?"#
    let part = #"(?:\s+(?:pagi|siang|sore|malam))?"#
    return indonesianFinds(
      #"^\#(separator)(?:\#(indonesianWeekdayNames)|(?<=hari\s{1,3})minggu)(?![\p{Latin}\p{M}])"#,
      in: indonesianTextAfter(match))
      || indonesianFinds(
        #"(?<![\p{Latin}\p{M}])\#(day)\#(part)\#(separator)$"#, in: indonesianTextBefore(match))
  }

  /// The day a phrase names: the phrase of a rule's match, with the words that
  /// introduce it. Nil when the phrase names no day, or a past one ("Senin
  /// lalu"), or follows "kecuali", or is one weekday of a list.
  private static func indonesianDay(_ phrase: String, in match: Match) -> Day? {
    if let before = wordBefore(match).map(indonesianKey), indonesianExceptWords.contains(before) { return nil }
    let key = indonesianKey(phrase)
    let tokens = indonesianPhrase(phrase).split(separator: " ").map {
      String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
    }
    let isEvening = tokens.contains("malam")
    if let found = indonesianExplicitDate(key) {
      if found.isNumeric, indonesianFollowsNumbering(match) { return nil }
      guard let today = match.today, let days = offset(to: found.date, from: today) else { return nil }
      return Day(offset: days)
    }
    if let days = indonesianCountedDays(phrase) { return Day(offset: days) }
    let pastWords: Set<String> = ["lalu", "kemarin"]
    if tokens.contains(where: { pastWords.contains($0) }) { return nil }
    let todayWeekday = match.todayWeekday
    if tokens.contains("weekend") || (tokens.contains("akhir") && tokens.contains("pekan")) {
      let weekend = weekendOffset(todayWeekday: todayWeekday)
      return Day(offset: tokens.contains("depan") ? weekend + 7 : weekend)
    }
    // "Sabtu dan Minggu": both days of the weekend, planned from the first.
    if tokens.contains("sabtu"), tokens.contains("minggu"), tokens.contains(where: { $0 == "dan" || $0 == "&" }) {
      return Day(offset: weekendOffset(todayWeekday: todayWeekday))
    }
    if let weekday = indonesianPhraseWeekday(tokens) {
      if indonesianIsInWeekdayList(match) { return nil }
      if tokens.contains("depan") {
        return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      if tokens.contains("ini") {
        return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
      }
      return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    if tokens.contains("depan"), tokens.contains(where: { $0 == "minggu" || $0 == "pekan" }) {
      return Day(offset: 7)
    }
    if tokens.contains("lusa") { return Day(offset: 2, isEvening: isEvening) }
    if tokens.contains("besok") { return Day(offset: 1, isEvening: isEvening) }
    if tokens.contains("hari") || tokens.contains("ini") || tokens.contains("nanti") {
      return Day(offset: 0, isEvening: isEvening)
    }
    return nil
  }

  // MARK: - Text that names no day

  /// "Senin pertama", "Jumat terakhir bulan ini", "setiap Selasa kedua": a
  /// weekday by its place in the month. The repeat has no such rule and no day
  /// rule can name it, so the text stays in the title whole, with no part of it
  /// read as a weekday.
  static let indonesianOrdinalWeekdayPattern =
    #"\#(indonesianStart)(?:(?:setiap|tiap)\s+)?\#(indonesianWeekdayWord)\s+(?:pertama|kedua|ketiga|keempat|kelima|terakhir)(?:\s+(?:dalam|di|pada|setiap|tiap)\s+(?:bulan|setiap\s+bulan))?\#(indonesianEnd)"#

  /// "sebelum akhir pekan", "sampai weekend", "setelah akhir pekan", "untuk
  /// akhir pekan", and "akhir pekan lalu": a bound at the weekend, a weekend a
  /// task is for, or a past one. None names a day the planner can set, so the
  /// whole phrase stays in the title, where English would otherwise plan the
  /// bare "weekend" with the preposition left behind.
  static let indonesianNoDayWeekendPattern =
    #"\#(indonesianStart)(?:(?:sebelum|sampai(?:\s+dengan)?|hingga|menjelang|setelah|sesudah|selama|untuk|buat|saat|ketika|sepanjang|selepas)\s+(?:akhir\s+pekan|weekend)(?:\s+(?:ini|depan|lalu))?|(?:akhir\s+pekan|weekend)\s+(?:lalu|kemarin|yang\s+lalu))\#(indonesianEnd)"#

  /// "besok lusa", "malam Jumat", "malam Minggu": phrases the reader cannot give
  /// one day. "Besok lusa" means tomorrow or the day after, and "malam Jumat" is
  /// the night before Friday, so both stay in the title whole. "Makan malam
  /// Jumat" is dinner on Friday and reads as one.
  static let indonesianVagueDayPattern =
    #"\#(indonesianStart)(?:besok\s+lusa|(?<!makan\s{1,3})malam\s+(?:\#(indonesianWeekdayNames)|minggu))\#(indonesianEnd)"#

  /// "salat Jumat", "khotbah Jumat", "Jumat Agung": the name of a prayer or a
  /// holiday with a weekday in it, which names no day to plan, so the whole name
  /// stays in the title.
  static let indonesianNamedWeekdayPattern =
    #"\#(indonesianStart)(?:(?:salat|shalat|sholat|solat|khotbah|khutbah)\s+jum['’ʼ]?at|jum['’ʼ]?at\s+agung)\#(indonesianEnd)"#
}
