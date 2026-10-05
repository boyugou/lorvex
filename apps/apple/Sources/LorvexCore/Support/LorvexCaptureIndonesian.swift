import Foundation

extension LorvexCaptureVocabulary {
  /// Indonesian, read for a user who reads Indonesian. A word needs a boundary
  /// of Latin letters, digits, and combining marks on both sides, and a letter
  /// joined by a hyphen makes a reduplicated or compound word that is no detail
  /// ("besok-besok", "pagi-pagi", "hari-hari" stay). The language has no
  /// diacritics, so the line is read as typed.
  ///
  /// - Day: hari ini, pagi ini, siang ini, sore ini, malam ini, nanti malam,
  ///   besok (alone or with pagi, siang, sore, or malam), lusa, the weekday names
  ///   (alone, after pada, di, or hari, or with ini, depan, minggu ini, minggu
  ///   depan, or a part of the day: "Jumat sore", "besok pagi sekali"), minggu
  ///   depan, pekan depan, akhir pekan, weekend, 3 hari lagi, dalam 3 hari,
  ///   seminggu lagi, 2 minggu lagi;
  ///   a date: 5 Oktober, 5 Okt, 5 Okt 2026, tanggal 5 Oktober, tgl. 5 Okt, tanggal
  ///   5, 5/10/2026, 5-10-2026, 5.10.2026, and after pada, tanggal, or tgl the short
  ///   5/10. A weekday alone or with "pada" is the next such day, a full week
  ///   ahead when it names today; with ini it is this week's, and with depan, or
  ///   beside minggu depan, next week's, weeks starting on Monday. "Minggu" is
  ///   the week: it is Sunday only after "hari" ("hari Minggu") or beside another
  ///   weekday ("Sabtu dan Minggu", "Jumat sampai Minggu"), so "minggu depan" is
  ///   next week and "Sekolah Minggu" stays in the title. A past day (kemarin,
  ///   kemarin lusa, tadi, Senin lalu, minggu lalu, semalam) is never read, and
  ///   neither are phrases whose day cannot be named: "besok lusa" (tomorrow or
  ///   the day after), "malam Jumat" (the night before Friday), a month ahead
  ///   ("bulan depan", "sebulan lagi"), "akhir pekan" after sebelum, sampai, or
  ///   setelah, a list of weekdays ("Senin dan Rabu"), and the names "salat
  ///   Jumat" and "Jumat Agung". A count after "kali" is a rate, not a day ("dua
  ///   kali dalam seminggu").
  /// - Date range: 5-7 Oktober, 5 sampai 7 Oktober, 5 s/d 7 Oktober, dari 5
  ///   hingga 7 Oktober, dari tanggal 5 sampai tanggal 7 Oktober, antara 5 dan 7
  ///   Oktober, 5 Oktober - 7 Oktober, each maybe with a year after the end;
  ///   dari Senin sampai Rabu, Senin - Rabu. The first day is the planned day and
  ///   the last the due day.
  /// - Repeat: setiap hari, tiap hari, setiap Senin, setiap hari Senin, setiap
  ///   Jumat malam, setiap Senin dan Kamis, setiap Senin sampai Jumat, setiap 2
  ///   hari, setiap dua hari, 2 hari sekali, seminggu sekali, sekali seminggu, 2
  ///   minggu sekali, sebulan sekali, setahun sekali, setiap minggu, setiap bulan,
  ///   setiap tahun, setiap tanggal 5, setiap bulan tanggal 5, setiap hari kerja,
  ///   setiap akhir pekan, setiap pagi, setiap triwulan; harian, mingguan,
  ///   bulanan, and tahunan at the end of the line ("Laporan mingguan" repeats).
  ///   "Setiap minggu" is every week and "setiap hari Minggu" every Sunday. A
  ///   count of times in a period ("dua kali seminggu") and an interval of hours
  ///   ("setiap 2 jam") name no repeat the app can set and stay in the title.
  /// - Due: a day after sebelum, paling lambat, selambat-lambatnya, sampai,
  ///   hingga, tenggat, batas waktu, deadline, or jatuh tempo ("sebelum Jumat",
  ///   "paling lambat tanggal 15 Oktober", "tenggat besok"). A clock time after
  ///   those words ("sebelum jam 5", "sampai pukul 17.00") is a bound that stays
  ///   in the title, and the day before it is the due day.
  /// - Time: jam 3, pukul 15.30, jam 15:30, jam 3 sore, jam 8 malam, jam 7 pagi,
  ///   jam 12 siang, jam 12 malam, jam 12 tengah malam, jam tiga, jam 3 kurang 10,
  ///   jam 3 lewat 15, jam 3 kurang seperempat, setengah empat, tengah malam,
  ///   tengah hari, and 7.30 malam; a range: jam 3-5 sore, dari jam 3 sampai jam
  ///   5, jam 3 sampai 5, jam 14.00-16.00; a side with no part of the day takes
  ///   the reading that fits the other ("jam 3 sampai 5 sore" starts at 15:00,
  ///   "jam 9 sampai 5 sore" at 9:00). "Jam" or "pukul" before a number is the
  ///   clock and a number before "jam" is a length ("3 jam"). Indonesian counts
  ///   the half hour toward the next hour ("setengah empat" is 3:30) and takes
  ///   minutes off or adds them with "kurang" and "lewat". A time from 1 to 6
  ///   o'clock with no part of the day is the afternoon, unless written with a
  ///   leading zero. A part of the day just before the clock gives it its
  ///   part ("malam jam 8", "makan malam jam 8"). A time written with a colon or
  ///   with no Indonesian word ("15:30", "3pm") is English's.
  /// - Length: 30 menit, 30 mnt, 1 jam, 2 jam, 1,5 jam, 1 jam 30 menit, setengah
  ///   jam, satu setengah jam, sejam, seperempat jam, tiga perempat jam, dua jam,
  ///   lima belas menit, each maybe after selama, durasi (with a colon too),
  ///   sekitar, or untuk. A moment, a bound, a difference, or a rate ("dalam 2
  ///   jam", "2 jam lagi", "2 jam sehari", "setiap 2 jam") is no length and stays
  ///   in the title, and neither is a side of a range ("2 sampai 3 jam").
  /// - Priority: prioritas tinggi, prioritas rendah, prioritas 1, prio 2, and
  ///   penting, mendesak, urgent, darurat, or segera at the end of the line or
  ///   opening it before a colon or comma. A negation before them ("tidak
  ///   penting") keeps them in the title.
  static let indonesian = LorvexCaptureVocabulary(
    priority: [Rule(pattern: indonesianPriorityPattern, read: indonesianPriority)],
    dateRange: [
      Rule(pattern: indonesianDateRangePattern, read: indonesianDateRange),
      Rule(pattern: indonesianWeekdayRangePattern, read: indonesianWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: indonesianNegatedUrgentPattern) { _ in true },
      Rule(pattern: indonesianDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: indonesianDueClockPattern) { indonesianIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: indonesianLengthPattern) { indonesianClaimsLength($0) ? true : nil },
      Rule(pattern: indonesianOrdinalWeekdayPattern) { _ in true },
      Rule(pattern: indonesianNoDayWeekendPattern) { _ in true },
      Rule(pattern: indonesianVagueDayPattern) { _ in true },
      Rule(pattern: indonesianNamedWeekdayPattern) { _ in true },
    ],
    length: [Rule(pattern: indonesianLengthPattern, read: indonesianLength)],
    time: [
      Rule(pattern: indonesianTimeRangePattern, read: indonesianTimeRange),
      Rule(pattern: indonesianSpokenTimePattern, read: indonesianSpokenTime),
      Rule(pattern: indonesianClockPattern, read: indonesianClock),
      Rule(pattern: indonesianMeridiemTimePattern, read: indonesianMeridiemTime),
      Rule(pattern: indonesianNoonOrMidnightPattern, read: indonesianNoonOrMidnight),
    ],
    repeats: indonesianRepeatRules,
    due: [Rule(pattern: indonesianDuePattern, read: indonesianDue)],
    when: [Rule(pattern: indonesianWhenPattern, read: indonesianWhen)])

  // MARK: - Boundaries and matched words

  /// A word boundary for Indonesian words: no Latin letter, digit, or combining
  /// mark on that side, and no letter joined by a hyphen, since a hyphen builds
  /// a reduplicated or compound word that is no day.
  static let indonesianStart = #"(?<![\p{Latin}\p{N}\p{M}]|\p{L}[-–])"#
  static let indonesianEnd = #"(?![\p{Latin}\p{N}\p{M}]|[-–]\p{L})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let indonesianNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// A matched word or phrase as a reader compares it: lowercased, with a
  /// curly or modifier-letter apostrophe read as a straight one ("Jum’at").
  static func indonesianKey(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "ʼ", with: "'")
  }

  /// ``indonesianKey(_:)`` of a matched phrase with each run of spaces and
  /// hyphens as one space.
  static func indonesianPhrase(_ text: String) -> String {
    indonesianKey(text).replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Words after a detail

  /// The words that a detail written with no lead of its own ("setengah empat")
  /// may be followed by: prepositions, conjunctions, pronouns, the words that
  /// say when, a part of the day, and a few everyday verbs. Any other word
  /// after the number makes it an amount or a count ("setengah empat kilo",
  /// "dari 3 sampai 5 hari"), so it stays in the title.
  private static let indonesianWordsAfterDetail: Set<String> = [
    "di", "ke", "dari", "dengan", "sama", "bersama", "untuk", "pada", "dan", "atau", "ya", "yuk", "nih", "dong", "deh",
    "kok", "kan", "lah", "kita", "kami", "saya", "aku", "kamu", "dia", "mereka", "akan", "mau", "harus", "perlu",
    "ketemu", "kumpul", "berangkat", "pergi", "mulai", "selesai", "tiba", "pulang", "datang", "bertemu", "pagi",
    "siang", "sore", "malam", "besok", "lusa", "nanti", "senin", "selasa", "rabu", "kamis", "jumat", "sabtu", "wib",
    "wita", "wit", "urgent", "penting", "mendesak", "harian", "mingguan", "bulanan", "tahunan",
  ]

  /// Whether the line goes on after `match` with nothing, punctuation, a digit,
  /// or a word in ``indonesianWordsAfterDetail``.
  static func indonesianFollowsAsDetail(_ match: Match) -> Bool {
    guard let next = wordAfter(match) else { return true }
    return indonesianWordsAfterDetail.contains(indonesianKey(next))
  }

  // MARK: - Text around a match

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at: a deadline word before it, a part of the day
  /// beside it. A bounded look-around keeps the time a line takes linear in its
  /// length.
  static let indonesianContextLength = 60

  /// The text of the line just before `match`: at most
  /// ``indonesianContextLength`` characters, ending where the match starts.
  static func indonesianTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -indonesianContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  /// The text of the line just after `match`: at most
  /// ``indonesianContextLength`` characters, starting where the match ends.
  static func indonesianTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return String(match.source[end...].prefix(indonesianContextLength))
  }

  /// Whether `pattern` matches somewhere in `text`.
  static func indonesianFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(pattern) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Counts

  private static let indonesianUnitWords: [String: Int] = [
    "satu": 1, "dua": 2, "tiga": 3, "empat": 4, "lima": 5, "enam": 6, "tujuh": 7, "delapan": 8, "sembilan": 9,
  ]

  /// The numbers 1 to 99 spelled as words, as a pattern without groups:
  /// "tiga", "sepuluh", "sebelas", "lima belas", "dua puluh", "empat puluh
  /// lima".
  static let indonesianNumberWords: String = {
    let units = "satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan"
    return #"(?:(?:\#(units))\s+puluh(?:\s+(?:\#(units)))?|(?:\#(units))\s+belas|sepuluh|sebelas|\#(units))"#
  }()

  /// The hours 1 to 12 spelled as words, as a pattern without groups.
  static let indonesianHourWords =
    #"(?:dua\s+belas|sebelas|sepuluh|sembilan|delapan|tujuh|enam|lima|empat|tiga|dua|satu)"#

  /// The count a matched word or phrase names, in digits or as a number word
  /// from 1 to 99, or nil.
  static func indonesianCount(_ text: String) -> Int? {
    if let digits = number(text) { return digits }
    let tokens = indonesianPhrase(text).split(separator: " ").map(String.init)
    switch tokens.count {
    case 1:
      if tokens[0] == "sepuluh" { return 10 }
      if tokens[0] == "sebelas" { return 11 }
      return indonesianUnitWords[tokens[0]]
    case 2:
      guard let unit = indonesianUnitWords[tokens[0]] else { return nil }
      if tokens[1] == "belas" { return 10 + unit }
      return tokens[1] == "puluh" ? unit * 10 : nil
    case 3:
      guard tokens[1] == "puluh", let tens = indonesianUnitWords[tokens[0]],
        let ones = indonesianUnitWords[tokens[2]]
      else { return nil }
      return tens * 10 + ones
    default:
      return nil
    }
  }

  // MARK: - Priority

  /// "penting", "mendesak", "urgent", "darurat", or "segera", maybe after
  /// "sangat" and before "sekali", as a pattern without groups.
  private static let indonesianUrgentWords =
    #"(?:(?:sangat|amat|cukup|super)\s+)?(?:penting|mendesak|urgent|darurat|segera)(?:\s+sekali)?"#

  /// Group 1: a written priority ("prioritas tinggi", "prio: rendah",
  /// "prioritas 1", "dengan prioritas sedang"); the urgency words (at the end of
  /// the line, with the full stop or exclamation mark that ends it, or opening
  /// the line before a colon or a comma) have no group. The words are adjectives
  /// too ("dokumen penting"), and the end of the line is where one says how
  /// urgent a task is.
  private static var indonesianPriorityPattern: String {
    let written =
      #"(?:dengan\s+)?(?:prioritas|prio)\s*[=:]?\s*(?:sangat\s+)?(?:tinggi|utama|sedang|menengah|rendah|[1-3](?![\p{N}.,:]))"#
    return
      #"\#(indonesianStart)(\#(written))\#(indonesianEnd)|(?<=\s)\#(indonesianUrgentWords)\#(indonesianEnd)[.!]*(?=\s*$)|^\s*\#(indonesianUrgentWords)\#(indonesianEnd)(?=\s*[:,，：])"#
  }

  private static func indonesianPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return .p1 }
    let key = indonesianKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if key.contains("sedang") || key.contains("menengah") { return .p2 }
    return key.contains("rendah") ? .p3 : .p1
  }

  /// "tidak penting", "bukan urgent", "kurang mendesak", "tidak terlalu
  /// penting": a negation turns the urgency word around, so the phrase stays in
  /// the title whole and English does not read the "urgent".
  private static let indonesianNegatedUrgentPattern =
    #"\#(indonesianStart)(?:tidak|tak|bukan|kurang|belum|nggak|gak|enggak)(?:\s+(?:terlalu|begitu|sangat|amat|lagi|usah|perlu|harus))*\s+\#(indonesianUrgentWords)\#(indonesianEnd)"#

  // MARK: - Length

  /// The words that open a length and go with it: "selama 2 jam", "durasi 2
  /// jam", "sekitar 30 menit", "kurang lebih 1 jam", "untuk 2 jam".
  private static let indonesianLengthOpener =
    #"selama|durasi|lamanya|lama|sekitar|kira[\s-]?kira|kurang\s+lebih|estimasi|perkiraan|untuk"#

  /// The words before an amount that make it a moment, an interval, or a bound
  /// rather than a length: "dalam 2 jam", "setiap 2 jam", "setelah 30 menit",
  /// "sebelum 2 jam", "kurang dari 2 jam", "maksimal 2 jam".
  private static let indonesianLengthDecliner =
    #"dalam|setiap|tiap|per|setelah|sesudah|sebelum|sampai|hingga|selang|menjelang|kurang\s+dari|lebih\s+dari|maksimal|maksimum|maks|minimal|minimum|paling\s+lama|paling\s+cepat|paling\s+sedikit|paling\s+banyak|tidak\s+lebih\s+dari|usai|habis"#

  /// The words after an amount that make it a moment, the past, a difference, or
  /// a rate: "2 jam lagi", "2 jam yang lalu", "2 jam sekali", "2 jam sehari", "2
  /// jam per hari", "30 menit lebih".
  private static let indonesianLengthTrailing =
    #"lagi|lalu|yang\s+lalu|kemudian|sekali|sehari|seminggu|sebulan|setahun|per\s+(?:hari|minggu|bulan|tahun|jam)|sebelumnya|sesudahnya|setelahnya|dari\s+sekarang|ke\s+depan|tambahan|ekstra|lebih"#

  /// What may not follow the word "jam" of an hours amount, as a lookahead: a
  /// number, since then "jam" opens a clock time ("ruang 3 jam 10 pagi" is room
  /// 3 at 10 in the morning), and the nouns that make "jam" a clock or a watch
  /// ("2 jam tangan" is two wristwatches).
  private static let indonesianNotAClock =
    #"(?!\s+(?:\d|(?:tangan|dinding|pasir|weker|meja|saku|bandul|matahari|digital|analog|pintar|alarm)(?![\p{Latin}\p{M}])))"#

  /// The lengths written as words, as a pattern without groups.
  private static var indonesianLengthWords: String {
    let count = indonesianNumberWords
    return [
      #"setengah\s+jam"#,
      #"seperempat\s+jam"#,
      #"tiga\s+perempat\s+jam"#,
      #"sejam(?:\s+setengah)?"#,
      #"semenit"#,
      #"(?:\d+|\#(count))\s+setengah\s+jam"#,
      #"\#(count)\s+jam\#(indonesianNotAClock)(?:\s+setengah)?"#,
      #"\#(count)\s+menit"#,
    ].joined(separator: "|")
  }

  /// "30 menit", "30 mnt", "2 jam", "1,5 jam", "2 jam setengah", "2 jam 30
  /// menit", "setengah jam", "satu setengah jam", "sejam", "dua jam", or "lima
  /// belas menit", each maybe after an opener. Groups: 1 the opener; 2 a word
  /// that makes the amount a moment, an interval, or a bound; 3 and 4 the hours
  /// and the minutes of "2 jam 30 menit"; 5 hours with a decimal fraction and 6
  /// the "setengah" after them; 7 minutes; 8 a length in words; 9 a word after
  /// the amount that makes it the past, a difference, or a rate. A match with
  /// group 2 or 9 is no length: the reader declines it and the title keeps it.
  /// An opener may be followed by a colon ("durasi: 2 jam"). The amount may not
  /// follow a digit, a colon, or a separator, and an amount that is a side of a
  /// range ("2-3 jam", "2 sampai 3 jam", "2 atau 3 jam") is no length. Hours
  /// before a number or a clock noun ("ruang 3 jam 10 pagi", "2 jam tangan") are
  /// no length either, since "jam" is then the clock or a watch.
  static var indonesianLengthPattern: String {
    let count = indonesianNumberWords
    let amount = #"\d+|\#(count)"#
    let units = #"(?:menit|mnt|min)"#
    return
      #"\#(indonesianStart)(?:(\#(indonesianLengthOpener))(?:\s*:\s*|\s+)|(\#(indonesianLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}]\s?[-–—]\s?)(?<!\d\s?(?:menit|mnt|min|jam)\.?\s?[-–—]\s?)(?<!\d\s{1,3}(?:dan|atau|sampai|hingga|s/d)\s{1,3})(?:(\#(amount))\s*jam\s*(?:dan\s+)?(\#(amount))\s*\#(units)|(\d+(?:[.,]\d+)?)\s*jam\#(indonesianNotAClock)(?:\s+(setengah))?|(\d+)\s*\#(units)|(\#(indonesianLengthWords)))\#(indonesianEnd)(?!\s*[-–—]\s*\d)(?:\s+(\#(indonesianLengthTrailing))\#(indonesianEnd))?"#
  }

  /// Whether a match of ``indonesianLengthPattern`` is kept in the title whole:
  /// it names a moment, an interval, a bound, a difference, the past, or a rate.
  static func indonesianClaimsLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(9) != nil
  }

  /// Whether `match` is the minutes of a spoken time ("jam 3 lewat 10 menit",
  /// "jam 3 kurang 10 menit"), which the time rules read with their hour.
  private static func indonesianFollowsSpokenHour(_ match: Match) -> Bool {
    indonesianFinds(#"(?:^|\s)(?:lewat|lebih|kurang)\s+$"#, in: indonesianTextBefore(match))
  }

  private static func indonesianLength(_ match: Match) -> Int? {
    if indonesianClaimsLength(match) || indonesianFollowsSpokenHour(match) { return nil }
    if let hoursText = match.group(3), let minutesText = match.group(4),
      let hours = indonesianCount(hoursText), let minutes = indonesianCount(minutesText)
    {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(5) {
      guard let hours = decimalAmount(amountText) else { return nil }
      var minutes = Int((hours * 60).rounded())
      if match.group(6) != nil {
        // "Setengah" follows a whole number of hours only.
        guard hours == hours.rounded() else { return nil }
        minutes += 30
      }
      return taskLength(minutes: minutes)
    }
    if let minutes = match.group(7).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(8).flatMap(indonesianWordLength)
  }

  /// The minutes a length written in words names: "setengah jam", "seperempat
  /// jam", "tiga perempat jam", "sejam", "sejam setengah", "satu setengah jam",
  /// "dua jam", "dua jam setengah", "lima belas menit".
  private static func indonesianWordLength(_ phrase: String) -> Int? {
    let key = indonesianPhrase(phrase)
    switch key {
    case "setengah jam": return 30
    case "seperempat jam": return 15
    case "tiga perempat jam": return 45
    case "sejam": return 60
    case "sejam setengah": return 90
    case "semenit": return 1
    default: break
    }
    if let found = key.wholeMatch(of: /(.+) setengah jam/), let count = indonesianCount(String(found.output.1)) {
      return taskLength(minutes: count * 60 + 30)
    }
    if let found = key.wholeMatch(of: /(.+) jam(?: setengah)?/), let count = indonesianCount(String(found.output.1)) {
      return taskLength(minutes: count * 60 + (key.hasSuffix("setengah") ? 30 : 0))
    }
    if let found = key.wholeMatch(of: /(.+) menit/), let count = indonesianCount(String(found.output.1)) {
      return taskLength(minutes: count)
    }
    return nil
  }
}
