import Foundation

extension LorvexCaptureVocabulary {
  /// Malay (Bahasa Melayu as written in Malaysia, Singapore, and Brunei), read
  /// for a user who reads Malay. A word needs a boundary of Latin letters,
  /// digits, and combining marks on both sides, and a letter joined by a hyphen
  /// makes a reduplicated or compound word that is no detail ("esok-esok",
  /// "pagi-pagi", "hari-hari" stay). The language has no diacritics, so the line
  /// is read as typed.
  ///
  /// - Day: hari ini, pagi ini, petang ini, malam ini, tengah hari ini, malam
  ///   nanti, esok (alone, or with pagi, tengah hari, petang, or malam before or
  ///   after it), besok, lusa, the weekday names (Isnin, Selasa, Rabu, Khamis,
  ///   Jumaat, Sabtu, Ahad: alone, after pada or hari, or with ini, depan,
  ///   hadapan, minggu ini, minggu depan, or a part of the day before or after
  ///   it: "Jumaat petang", "petang Jumaat"), minggu depan, minggu hadapan,
  ///   hujung minggu, weekend, 3 hari lagi, dalam 3 hari, seminggu lagi, 2 minggu
  ///   lagi; a date: 5 Oktober, 5 Okt, 5hb Oktober, 5 Okt 2026, tarikh 5 Oktober,
  ///   5/10/2026, 5-10-2026, 5.10.2026, and after pada or tarikh the short 5/10;
  ///   a day of the month alone: tarikh 5, pada 5hb, "Bayar sewa 5hb". A weekday
  ///   alone or with "pada" is the next such day, a full week ahead when it names
  ///   today; with ini it is this week's, and with depan or hadapan, or beside
  ///   minggu depan, next week's, weeks starting on Monday. "Minggu" is the week,
  ///   never Sunday, which is "Ahad". A past day (semalam, kelmarin, tadi, Isnin
  ///   lepas, minggu lalu) is never read, and neither are phrases whose day cannot
  ///   be named: "esok lusa" (tomorrow or the day after, or soon), "malam Jumaat"
  ///   (the night before Friday), a month ahead ("bulan depan"), "dalam seminggu"
  ///   (which is as often "in a week" as "per week"), "hujung minggu" after
  ///   sebelum, hingga, selepas, or untuk, a list of weekdays ("Isnin dan Rabu"),
  ///   and the names "solat Jumaat" and "Jumaat Agung". A part of the day that
  ///   forms a noun with the word before it ("makan malam", "pasar malam", "kelas
  ///   petang") stays with that noun when a day follows: "Makan malam esok" is
  ///   dinner tomorrow, and the title stays "Makan malam".
  /// - Date range: 5-7 Oktober, 5 hingga 7 Oktober, 5 sehingga 7 Oktober, 5
  ///   sampai 7 Oktober, dari 5 hingga 7 Oktober, antara 5 dan 7 Oktober, 5hb
  ///   hingga 7hb Oktober, 5 Oktober - 7 Oktober, each maybe with a year after
  ///   the end; dari Isnin hingga Rabu, Isnin - Rabu. The first day is the
  ///   planned day and the last the due day.
  /// - Repeat: setiap hari, tiap hari, tiap-tiap hari, setiap Isnin, setiap hari
  ///   Isnin, setiap Jumaat malam, setiap Isnin dan Khamis, setiap Isnin hingga
  ///   Jumaat, setiap 2 hari, setiap dua hari, 2 hari sekali, seminggu sekali,
  ///   sekali seminggu, sehari sekali, 2 minggu sekali, sebulan sekali, setahun
  ///   sekali, setiap minggu, setiap bulan, setiap tahun, setiap suku tahun,
  ///   setiap 5hb, setiap bulan pada tarikh 5, setiap hari bekerja, setiap hari
  ///   kerja, setiap hujung minggu, setiap pagi; harian, mingguan, bulanan, and
  ///   tahunan at the end of the line ("Laporan mingguan" repeats). A count of
  ///   times in a period ("dua kali seminggu"), an interval of hours ("setiap 2
  ///   jam"), and every day with a day left out ("setiap hari kecuali Ahad") name
  ///   no repeat the app can set and stay in the title.
  /// - Due: a day after sebelum, selewat-lewatnya, selambat-lambatnya, paling
  ///   lewat, paling lambat, hingga, sehingga, sampai, tarikh akhir, tarikh
  ///   tamat, tarikh tutup, tarikh jangka, had masa, or deadline ("sebelum
  ///   Jumaat", "tarikh akhir 15 Oktober", "hingga esok"). A clock time after
  ///   those words ("sebelum pukul 5", "hingga jam 17.00") is a bound that stays
  ///   in the title, and the day before it is the due day.
  /// - Time: pukul 3, jam 3, pukul 15.30, jam 15:30, pukul 3 petang, jam 8
  ///   malam, pukul 7 pagi, pukul 12 tengah hari, jam 12 tengah malam, pukul tiga,
  ///   pukul tiga setengah, tengah malam, 3.30 petang, 8 malam, 7 pagi, 9.30 PG,
  ///   3:30 PTG, pukul 3 tepat; a range: pukul 3-5 petang, dari pukul 3 hingga 5
  ///   petang, 9.00 pagi hingga 5.00 petang, jam 14.00-16.00. "Pukul", "jam", or
  ///   "pkl" before a number is the clock and a number before "jam" is a length
  ///   ("3 jam"). A time from 1 to 6 o'clock with no part of the day is the
  ///   afternoon, unless written with a leading zero. PG and PTG are the 12-hour
  ///   clock's AM and PM that Apple's Malay writes ("9:30 PG", "3:30 PTG"). The
  ///   half hour is written after the hour ("pukul tiga setengah" is 3:30, as
  ///   Malaysian Malay says it); a quarter ("pukul tiga suku", "kurang suku") is
  ///   said both ways and stays in the title, and so does "setengah tiga", which
  ///   Indonesian reads as 2:30. A part of the day or a meal, a prayer, or the
  ///   fast just before the clock gives it its part ("malam pukul 8", "makan
  ///   malam pukul 8", "berbuka pukul 7"). A time written with a colon or with no
  ///   Malay word ("15:30", "3pm") is English's.
  /// - Length: 30 minit, 30 min, 1 jam, 2 jam, 1.5 jam, 1,5 jam, 1 jam 30
  ///   minit, setengah jam, satu setengah jam, sejam, sejam setengah, suku jam,
  ///   tiga suku jam, dua jam, lima belas minit, each maybe after selama,
  ///   tempoh, anggaran, or kira-kira. A moment, a bound, a difference, or a rate
  ///   ("dalam 2 jam", "2 jam lagi", "2 jam sehari", "setiap 2 jam") is no length
  ///   and stays in the title, and neither is a side of a range ("2 hingga 3
  ///   jam").
  /// - Priority: keutamaan tinggi, keutamaan rendah, prioriti 1, and penting,
  ///   mendesak, urgent, or segera at the end of the line or opening it before a
  ///   colon or comma. A negation before them ("tidak penting") keeps them in the
  ///   title, and so does "segera" in "mi segera".
  static let malay = LorvexCaptureVocabulary(
    priority: [Rule(pattern: malayPriorityPattern, read: malayPriority)],
    dateRange: [
      Rule(pattern: malayDateRangePattern, read: malayDateRange),
      Rule(pattern: malayWeekdayRangePattern, read: malayWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: malayNegatedUrgentPattern) { _ in true },
      Rule(pattern: malayDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: malayDueClockPattern) { malayIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: malayLengthPattern) { malayClaimsLength($0) ? true : nil },
      Rule(pattern: malayQuarterClockPattern) { _ in true },
      Rule(pattern: malayOrdinalWeekdayPattern) { _ in true },
      Rule(pattern: malayNoDayWeekendPattern) { _ in true },
      Rule(pattern: malayVagueDayPattern) { _ in true },
      Rule(pattern: malayNamedWeekdayPattern) { _ in true },
    ],
    length: [Rule(pattern: malayLengthPattern, read: malayLength)],
    time: [
      Rule(pattern: malayTimeRangePattern, read: malayTimeRange),
      Rule(pattern: malayHalfPastPattern, read: malayHalfPast),
      Rule(pattern: malayClockPattern, read: malayClock),
      Rule(pattern: malayMeridiemTimePattern, read: malayMeridiemTime),
      Rule(pattern: malayMidnightPattern, read: malayMidnight),
    ],
    repeats: malayRepeatRules,
    due: [Rule(pattern: malayDuePattern, read: malayDue)],
    when: [Rule(pattern: malayWhenPattern, read: malayWhen)])

  // MARK: - Boundaries and matched words

  /// A word boundary for Malay words: no Latin letter, digit, or combining mark
  /// on that side, and no letter joined by a hyphen, since a hyphen builds a
  /// reduplicated or compound word that is no day.
  static let malayStart = #"(?<![\p{Latin}\p{N}\p{M}]|\p{L}[-–])"#
  static let malayEnd = #"(?![\p{Latin}\p{N}\p{M}]|[-–]\p{L})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let malayNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// What may not follow a Malay day or clock time: "sore" or "siang", the
  /// Indonesian words for the afternoon. "Besok sore" and "jam 3 sore" belong
  /// whole to the Indonesian rules, so Malay leaves them for those rules, which
  /// read the whole phrase, instead of reading the day or the hour and leaving the
  /// word in the title.
  static let malayNotIndonesianPart = #"(?!\s+(?:sore|siang)(?![\p{Latin}\p{M}]))"#

  /// What may not come before a date: "tanggal" or "tgl", the Indonesian words
  /// for "date", which make the date the Indonesian rules' to read whole. Malay
  /// writes "tarikh".
  static let malayNotAfterTanggal = #"(?<!(?:tanggal|tgl\.?)\s{0,3})"#

  /// A matched word or phrase as a reader compares it: lowercased, with a
  /// curly or modifier-letter apostrophe read as a straight one ("Juma’at").
  static func malayKey(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "ʼ", with: "'")
  }

  /// ``malayKey(_:)`` of a matched phrase with each run of spaces and hyphens
  /// as one space.
  static func malayPhrase(_ text: String) -> String {
    malayKey(text).replacingOccurrences(of: "-", with: " ").split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Words after a detail

  /// The words that a detail written with no lead of its own ("dari 3 hingga
  /// 5") may be followed by: prepositions, conjunctions, pronouns, the words
  /// that say when, a part of the day, and a few everyday verbs. Any other word
  /// after the number makes it an amount or a count ("dari 3 hingga 5 hari"),
  /// so it stays in the title.
  private static let malayWordsAfterDetail: Set<String> = [
    "di", "ke", "dari", "dengan", "bersama", "untuk", "pada", "dan", "atau", "ya", "lah", "kita", "kami", "saya", "aku",
    "awak", "kamu", "anda", "dia", "mereka", "akan", "mahu", "nak", "perlu", "kena", "jumpa", "berkumpul", "bertolak",
    "pergi", "mula", "siap", "tiba", "balik", "pulang", "datang", "bertemu", "pagi", "petang", "malam", "esok", "besok",
    "lusa", "nanti", "isnin", "selasa", "rabu", "khamis", "jumaat", "sabtu", "ahad", "myt", "sgt", "penting", "mendesak",
    "segera", "urgent", "harian", "mingguan", "bulanan", "tahunan",
  ]

  /// Whether the line goes on after `match` with nothing, punctuation, a digit,
  /// or a word in ``malayWordsAfterDetail``.
  static func malayFollowsAsDetail(_ match: Match) -> Bool {
    guard let next = wordAfter(match) else { return true }
    return malayWordsAfterDetail.contains(malayKey(next))
  }

  // MARK: - Text around a match

  /// How many characters before and after a match the rules that judge a match
  /// by its surroundings look at: a deadline word before it, a part of the day
  /// beside it. A bounded look-around keeps the time a line takes linear in its
  /// length.
  static let malayContextLength = 60

  /// The text of the line just before `match`: at most ``malayContextLength``
  /// characters, ending where the match starts.
  static func malayTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -malayContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  /// The text of the line just after `match`: at most ``malayContextLength``
  /// characters, starting where the match ends.
  static func malayTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return String(match.source[end...].prefix(malayContextLength))
  }

  /// Whether `pattern` matches somewhere in `text`.
  static func malayFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(pattern) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Counts

  private static let malayUnitWords: [String: Int] = [
    "satu": 1, "dua": 2, "tiga": 3, "empat": 4, "lima": 5, "enam": 6, "tujuh": 7, "lapan": 8, "sembilan": 9,
  ]

  /// The numbers 1 to 99 spelled as words, as a pattern without groups:
  /// "tiga", "sepuluh", "sebelas", "lima belas", "dua puluh", "empat puluh
  /// lima".
  static let malayNumberWords: String = {
    let units = "satu|dua|tiga|empat|lima|enam|tujuh|lapan|sembilan"
    return #"(?:(?:\#(units))\s+puluh(?:\s+(?:\#(units)))?|(?:\#(units))\s+belas|sepuluh|sebelas|\#(units))"#
  }()

  /// The hours 1 to 12 spelled as words, as a pattern without groups.
  static let malayHourWords =
    #"(?:dua\s+belas|sebelas|sepuluh|sembilan|lapan|tujuh|enam|lima|empat|tiga|dua|satu)"#

  /// The count a matched word or phrase names, in digits or as a number word
  /// from 1 to 99, or nil.
  static func malayCount(_ text: String) -> Int? {
    if let digits = number(text) { return digits }
    let tokens = malayPhrase(text).split(separator: " ").map(String.init)
    switch tokens.count {
    case 1:
      if tokens[0] == "sepuluh" { return 10 }
      if tokens[0] == "sebelas" { return 11 }
      return malayUnitWords[tokens[0]]
    case 2:
      guard let unit = malayUnitWords[tokens[0]] else { return nil }
      if tokens[1] == "belas" { return 10 + unit }
      return tokens[1] == "puluh" ? unit * 10 : nil
    case 3:
      guard tokens[1] == "puluh", let tens = malayUnitWords[tokens[0]], let ones = malayUnitWords[tokens[2]]
      else { return nil }
      return tens * 10 + ones
    default:
      return nil
    }
  }

  // MARK: - Priority

  /// The words that make a task urgent, maybe after "sangat", as a pattern
  /// without groups: "penting", "mendesak", "urgent", and "segera", which is
  /// no urgency in the names of instant food ("mi segera", "makanan segera").
  private static let malayUrgentWords =
    #"(?:(?:sangat|amat|terlalu|cukup)\s+)?(?:penting|mendesak|urgent|(?<!(?:makanan|minuman|mi|mee|bihun|kopi|teh|bubur|nasi|sup|bahan|barangan)\s{1,3})segera)"#

  /// Group 1: a written priority ("keutamaan tinggi", "prioriti: rendah",
  /// "keutamaan 1", "dengan keutamaan sederhana"); the urgency words (at the end
  /// of the line, with the full stop or exclamation mark that ends it, or
  /// opening the line before a colon or a comma) have no group. The words are
  /// adjectives too ("dokumen penting"), and the end of the line is where one
  /// says how urgent a task is.
  private static var malayPriorityPattern: String {
    let written =
      #"(?:dengan\s+)?(?:keutamaan|prioriti|prio)\s*[=:]?\s*(?:sangat\s+)?(?:tinggi|utama|sederhana|rendah|[1-3](?![\p{N}.,:]))"#
    return
      #"\#(malayStart)(\#(written))\#(malayEnd)|(?<=\s)\#(malayUrgentWords)\#(malayEnd)[.!]*(?=\s*$)|^\s*\#(malayUrgentWords)\#(malayEnd)(?=\s*[:,，：])"#
  }

  private static func malayPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return .p1 }
    let key = malayKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if key.contains("sederhana") { return .p2 }
    return key.contains("rendah") ? .p3 : .p1
  }

  /// "tidak penting", "bukan urgent", "kurang penting", "tidak berapa penting",
  /// "tak begitu mendesak": a negation turns the urgency word around, so the
  /// phrase stays in the title whole and English does not read the "urgent".
  private static let malayNegatedUrgentPattern =
    #"\#(malayStart)(?:tidak|tak|bukan|kurang|belum|jangan)(?:\s+(?:begitu|berapa|terlalu|sangat|amat|lagi|perlu|payah|usah|mesti))*\s+\#(malayUrgentWords)\#(malayEnd)"#

  // MARK: - Length

  /// The words that open a length and go with it: "selama 2 jam", "tempoh 2
  /// jam", "anggaran 30 minit", "kira-kira 1 jam", "lebih kurang 1 jam", "untuk 2
  /// jam".
  private static let malayLengthOpener =
    #"selama|tempoh|durasi|anggaran|kira[\s-]?kira|lebih\s+kurang|sekitar|untuk"#

  /// The words before an amount that make it a moment, an interval, or a bound
  /// rather than a length: "dalam 2 jam", "dalam masa 2 jam", "setiap 2 jam",
  /// "selepas 30 minit", "sebelum 2 jam", "kurang daripada 2 jam", "maksimum 2
  /// jam".
  private static let malayLengthDecliner =
    #"dalam\s+(?:masa|tempoh)|dalam|setiap|tiap(?:[-\s]tiap)?|per|selepas|lepas|setelah|sesudah|sebelum|sehingga|hingga|sampai|selang|menjelang|sepanjang|kurang\s+(?:daripada|dari)|lebih\s+(?:daripada|dari)|maksimum|maksimal|maks|minimum|minimal|paling\s+(?:lama|cepat|kurang|sedikit|banyak)|tidak\s+(?:lebih|melebihi)|tak\s+lebih|usai"#

  /// The words after an amount that make it a moment, the past, a difference, or
  /// a rate: "2 jam lagi", "2 jam lalu", "2 jam sekali", "2 jam sehari", "2 jam
  /// per hari", "30 minit lebih awal".
  private static let malayLengthTrailing =
    #"lagi|lalu|yang\s+(?:lalu|lepas)|lepas|kemudian|sekali|sehari|seminggu|sebulan|setahun|sejam|per\s+(?:hari|minggu|bulan|tahun|jam)|sebelumnya|selepasnya|dari\s+sekarang|tambahan|ekstra|lebih|awal|lewat|dahulu"#

  /// What may not follow the word "jam" of an hours amount, as a lookahead: a
  /// number, since then "jam" opens a clock time ("bilik 3 jam 10 pagi" is room 3
  /// at 10 in the morning), and the nouns that make "jam" a clock or a watch ("2
  /// jam tangan" is two wristwatches).
  private static let malayNotAClock =
    #"(?!\s+(?:\d|(?:tangan|dinding|pasir|loceng|penggera|randik|meja|saku|bandul|matahari|digital|analog|pintar)(?![\p{Latin}\p{M}])))"#

  /// The lengths written as words, as a pattern without groups.
  private static var malayLengthWords: String {
    let count = malayNumberWords
    return [
      #"setengah\s+jam"#,
      #"suku\s+jam"#,
      #"tiga\s+suku\s+jam"#,
      #"sejam(?:\s+(?:setengah|suku))?"#,
      #"semenit"#,
      #"(?:\d+|\#(count))\s+setengah\s+jam"#,
      #"\#(count)\s+jam\#(malayNotAClock)(?:\s+(?:setengah|suku))?"#,
      #"\#(count)\s+minit"#,
    ].joined(separator: "|")
  }

  /// "30 minit", "30 min", "2 jam", "1.5 jam", "1,5 jam", "2 jam setengah", "2
  /// jam suku", "2 jam 30 minit", "setengah jam", "satu setengah jam", "sejam",
  /// "suku jam", "tiga suku jam", "dua jam", or "lima belas minit", each maybe
  /// after an opener. Groups: 1 the opener; 2 a word that makes the amount a
  /// moment, an interval, or a bound; 3 and 4 the hours and the minutes of "2 jam
  /// 30 minit"; 5 hours with a decimal fraction and 6 the "setengah" or "suku"
  /// after them; 7 minutes; 8 a length in words; 9 a word after the amount that
  /// makes it the past, a difference, or a rate. A match with group 2 or 9 is no
  /// length: the reader declines it and the title keeps it. An opener may be
  /// followed by a colon ("tempoh: 2 jam"). The amount may not follow a digit, a
  /// colon, or a separator, and an amount that is a side of a range ("2-3 jam",
  /// "2 hingga 3 jam", "2 atau 3 jam") is no length. Hours before a number or a
  /// clock noun ("bilik 3 jam 10 pagi", "2 jam tangan") are no length either,
  /// since "jam" is then the clock or a watch.
  static var malayLengthPattern: String {
    let count = malayNumberWords
    let amount = #"\d+|\#(count)"#
    let units = #"(?:minit|min|mnt)"#
    return
      #"\#(malayStart)(?:(\#(malayLengthOpener))(?:\s*:\s*|\s+)|(\#(malayLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}]\s?[-–—]\s?)(?<!\d\s?(?:minit|min|mnt|jam)\.?\s?[-–—]\s?)(?<!\d\s{1,3}(?:dan|atau|hingga|sehingga|sampai)\s{1,3})(?:(\#(amount))\s*jam\s*(?:dan\s+)?(\#(amount))\s*\#(units)|(\d+(?:[.,]\d+)?)\s*jam\#(malayNotAClock)(?:\s+(setengah|suku))?|(\d+)\s*\#(units)|(\#(malayLengthWords)))\#(malayEnd)(?!\s*[-–—]\s*\d)(?:\s+(\#(malayLengthTrailing))\#(malayEnd))?"#
  }

  /// Whether a match of ``malayLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, a difference, the past, or a rate.
  static func malayClaimsLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(9) != nil
  }

  /// Whether `match` is the minutes of a spoken time ("pukul 3 lewat 10 minit",
  /// "pukul 3 kurang 10 minit"), which Indonesian reads with its hour and Malay
  /// leaves in the title.
  private static func malayFollowsSpokenHour(_ match: Match) -> Bool {
    malayFinds(#"(?:^|\s)(?:lewat|lebih|kurang)\s+$"#, in: malayTextBefore(match))
  }

  private static func malayLength(_ match: Match) -> Int? {
    if malayClaimsLength(match) || malayFollowsSpokenHour(match) { return nil }
    if let hoursText = match.group(3), let minutesText = match.group(4), let hours = malayCount(hoursText),
      let minutes = malayCount(minutesText)
    {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(5) {
      guard let hours = decimalAmount(amountText) else { return nil }
      var minutes = Int((hours * 60).rounded())
      if let fraction = match.group(6) {
        // "Setengah" and "suku" follow a whole number of hours only.
        guard hours == hours.rounded() else { return nil }
        minutes += malayKey(fraction) == "setengah" ? 30 : 15
      }
      return taskLength(minutes: minutes)
    }
    if let minutes = match.group(7).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(8).flatMap(malayWordLength)
  }

  /// The minutes a length written in words names: "setengah jam", "suku jam",
  /// "tiga suku jam", "sejam", "sejam setengah", "sejam suku", "satu setengah
  /// jam", "dua jam", "dua jam setengah", "lima belas minit".
  private static func malayWordLength(_ phrase: String) -> Int? {
    let key = malayPhrase(phrase)
    switch key {
    case "setengah jam": return 30
    case "suku jam": return 15
    case "tiga suku jam": return 45
    case "sejam": return 60
    case "sejam setengah": return 90
    case "sejam suku": return 75
    case "semenit": return 1
    default: break
    }
    if let found = key.wholeMatch(of: /(.+) setengah jam/), let count = malayCount(String(found.output.1)) {
      return taskLength(minutes: count * 60 + 30)
    }
    if let found = key.wholeMatch(of: /(.+) jam(?: (setengah|suku))?/), let count = malayCount(String(found.output.1)) {
      let extra = found.output.2.map { $0 == "setengah" ? 30 : 15 } ?? 0
      return taskLength(minutes: count * 60 + extra)
    }
    if let found = key.wholeMatch(of: /(.+) minit/), let count = malayCount(String(found.output.1)) {
      return taskLength(minutes: count)
    }
    return nil
  }
}
