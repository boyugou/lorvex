import Foundation

extension LorvexCaptureVocabulary {
  /// Turkish, read for a user who reads Turkish. The reading form folds every
  /// Turkish letter to a plain one, one letter for one letter: ç, ğ, ö, ş, ü,
  /// and the circumflex vowels lose their marks, and the dotted and dotless
  /// letters i, ı, I, and İ all read as i, so "SALI", "Salı", "sali", and "SALİ"
  /// are one word, "CUMARTESİ" and "cumartesi" are one, and a line typed on a
  /// keyboard without Turkish letters ("persembe", "aksam", "gunu") reads like
  /// the accented one. The title keeps the letters that were typed. A letter
  /// typed as a base letter and a separate combining mark keeps its form in the
  /// reading form, so a detail word typed that way is left unread.
  ///
  /// A word needs a boundary of Latin letters, digits, and combining marks on
  /// both sides, no letter joined to it by a hyphen, and no letter joined by an
  /// apostrophe after it: a case ending is part of a detail only where a rule
  /// lists it ("cumaya kadar", "15 Ekim'de", "saat 5'te"), so "Cuma'nın",
  /// "yarından", and "cumaya" alone stay in the title.
  ///
  /// - Day: bugün, bu akşam, bu gece, yarın (alone or with a part of the day:
  ///   yarın sabah, yarın akşam, yarın öğlen), öbür gün, the weekday names
  ///   (alone, with "günü", after bu, önümüzdeki, gelecek, or haftaya, or with a
  ///   part of the day: cuma akşamı), haftaya, önümüzdeki hafta, gelecek hafta,
  ///   bu hafta sonu, 3 gün sonra, bir hafta sonra; a date: 15 Ekim, 15 Ekim
  ///   2026, 15 Ekim'de, 15.10.2026, 15.10.2026'da, with a weekday before it
  ///   (Cuma 16 Ekim), and after "tarih" or the locative the short 15.10 and
  ///   15/10. The two-word "bu gün" is not read: it is "this day" in many
  ///   sentences. A weekday alone is the next such day, a full week ahead when
  ///   it names today; with "bu" it is the coming one counting today ("bu salı"
  ///   on a Tuesday is today, "bu pazartesi" is the Monday ahead); with
  ///   "haftaya" or after "önümüzdeki hafta" it is next week's, weeks starting
  ///   on Monday; "önümüzdeki cuma" and "gelecek cuma" are the next one.
  ///   "Bu hafta sonu" is the coming Saturday and "önümüzdeki hafta sonu" the
  ///   one after it. A past day (dün, evvelsi gün, geçen cuma, geçen hafta
  ///   sonu) is never read, and stays in the title with the clock time that
  ///   follows it ("dün saat 3'te"). "Pazar" is also the market, so it names
  ///   Sunday only after bu, önümüzdeki, gelecek, or haftaya, or with "günü" or
  ///   a part of the day; "hafta sonu" alone and "hafta içi" alone are nouns of
  ///   many titles and stay. The short weekday forms "sal", "çar", "per", "cum",
  ///   and "paz" are words of their own and stay; "pzt" and "cmt" read.
  /// - Date range: 3-5 Mayıs, 3 Mayıs - 5 Mayıs, 3 Mayıs'tan 5 Mayıs'a kadar,
  ///   3 ile 5 Mayıs arası, each maybe with a year after the end; a span of
  ///   weekdays: cumadan pazara kadar, cuma-pazar, cuma ile pazar arası (Monday
  ///   to Friday is the working week, a repeat). The first day is the planned
  ///   day and the last the due day. The month abbreviations
  ///   (Oca, Şub, Mar, Nis, May, Haz, Tem, Ağu, Eyl, Eki, Kas, Ara) read when
  ///   capitalized or followed by a period, since several are ordinary words
  ///   ("ara", "kas", "haz", "eki").
  /// - Repeat: her gün, her pazartesi, her pazartesi ve perşembe, pazartesi
  ///   günleri, pazartesileri, pazartesi akşamları, her hafta, haftada bir,
  ///   iki günde bir, iki haftada bir, ayda bir, her ay, yılda bir, her yıl,
  ///   gün aşırı, her ikinci hafta, hafta içi her gün, iş günleri, hafta
  ///   sonları, her hafta sonu, her ayın 15'inde; günlük, haftalık, aylık, and
  ///   yıllık at the end of the line ("haftalık rapor" stays a title) or with
  ///   "olarak".
  /// - Due: a day with a dative ending before kadar, dek, or değin ("cumaya
  ///   kadar", "yarına kadar", "15 Ekim'e kadar"), a day before "önce" ("cumadan
  ///   önce"), or after son tarih, en geç, teslim, termin, or deadline. A clock
  ///   time before kadar, önce, or sonra ("saat 17:00'ye kadar", "5'ten önce")
  ///   is a bound that stays in the title, and the day before it is the due
  ///   day.
  /// - Time: saat 15:00, saat 15.00, 15:30'da, saat 3'te, akşam 8'de, sabah 9,
  ///   öğleden sonra 3, gece 12, öğlen 12, saat üç, saat üç buçuk, üç buçukta,
  ///   üçü çeyrek geçe, dörde çeyrek var, üçe on var, gece yarısı; a range:
  ///   saat 14-16, 14.00-16.00, 10:00'dan 11:00'e kadar, 14 ile 16 arası.
  ///   "Buçuk" adds the half hour to the hour it follows ("üç buçuk" is 3:30,
  ///   never 2:30). A time from 1 to 6 o'clock with no part of the day is the
  ///   afternoon, unless written with a leading zero. A bare 15:30 is left to
  ///   English; with an ending ("15:30'da") or "saat" it is read here.
  /// - Length: 30 dakika, 30 dk, 1 saat, 2 saat, 1,5 saat, yarım saat, çeyrek
  ///   saat, bir buçuk saat, 1 saat 30 dakika, and the adjective forms ("45
  ///   dakikalık toplantı" is a length of 45 minutes), each maybe after
  ///   "yaklaşık" or "tahmini süre" or before "boyunca". An amount that names a
  ///   moment or a bound ("30 dakika sonra", "2 saat içinde", "en fazla 2
  ///   saat") is no length.
  /// - Priority: acil, önemli, çok önemli at the end of the line or opening it
  ///   before a colon or comma ("acil servis" stays), yüksek öncelik, düşük
  ///   öncelik, öncelik: yüksek, öncelik 1.
  static let turkish = LorvexCaptureVocabulary(
    readingForm: turkishForMatching,
    priority: [Rule(pattern: turkishPriorityPattern, read: turkishPriority)],
    dateRange: [
      Rule(pattern: turkishDateRangePattern, read: turkishDateRange),
      Rule(pattern: turkishWeekdayRangePattern, read: turkishWeekdayRange),
    ],
    keptInTitle: [
      Rule(pattern: turkishPastPattern) { _ in true },
      Rule(pattern: turkishDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      Rule(pattern: turkishDueClockPattern) { turkishIsClockAfterDueDay($0) ? true : nil },
      Rule(pattern: turkishLengthPattern) { turkishClaimsLength($0) ? true : nil },
    ],
    length: [Rule(pattern: turkishLengthPattern, read: turkishLength)],
    time: [
      Rule(pattern: turkishTimeRangePattern, read: turkishTimeRange),
      Rule(pattern: turkishSpokenTimePattern, read: turkishSpokenTime),
      Rule(pattern: turkishClockPattern, read: turkishClock),
      Rule(pattern: turkishMeridiemTimePattern, read: turkishMeridiemTime),
      Rule(pattern: turkishMidnightPattern, read: turkishMidnight),
    ],
    repeats: turkishRepeatRules,
    due: [Rule(pattern: turkishDuePattern, read: turkishDue)],
    when: [Rule(pattern: turkishWhenPattern, read: turkishWhen)])

  // MARK: - Reading form

  /// The line with every Turkish letter read as a plain one: ç, ğ, ö, ş, ü, â,
  /// î, û as c, g, o, s, u, a, i, u, and ı, I, and İ as i. Each letter stays
  /// one UTF-16 unit, so a match range in it is the same range in the typed
  /// line. A letter typed as a base letter and a separate combining mark stays
  /// as typed, as does the dotted capital typed that way.
  static func turkishForMatching(_ line: String) -> String {
    var result = ""
    for character in line {
      let typed = String(character)
      if typed.utf16.count == 1, ["ı", "İ", "I"].contains(typed) {
        result += "i"
        continue
      }
      let folded = typed.folding(options: .diacriticInsensitive, locale: nil)
      result += folded.utf16.count == typed.utf16.count ? folded : typed
    }
    return result
  }

  // MARK: - Boundaries and matched words

  /// A word boundary for Turkish words: no Latin letter, digit, or combining
  /// mark on that side, no letter joined by a hyphen, and, after a word, no
  /// letter joined by an apostrophe, since an apostrophe starts the case ending
  /// of a name or a number ("Cuma'nın"), which a rule must list to read.
  static let turkishStart = #"(?<![\p{Latin}\p{N}\p{M}]|\p{L}[-–])"#
  static let turkishEnd = #"(?![\p{Latin}\p{N}\p{M}]|[-–]\p{L}|['’ʼ]\p{L})"#

  /// A matched word or phrase as a reader compares it: lowercased.
  static func turkishKey(_ text: String) -> String {
    text.lowercased()
  }

  /// ``turkishKey(_:)`` of a matched phrase with each apostrophe dropped and
  /// each run of spaces and hyphens as one space ("cuma'ya" as "cumaya").
  static func turkishPhrase(_ text: String) -> String {
    turkishKey(text).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
      .replacingOccurrences(of: "ʼ", with: "").replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  // MARK: - Text before a match

  /// How many characters before a match the rules that judge a match by its
  /// surroundings look at. A bounded look-behind keeps the time a line takes
  /// linear in its length.
  static let turkishContextLength = 60

  /// The text of the line just before `match`: at most ``turkishContextLength``
  /// characters, ending where the match starts.
  static func turkishTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    let from =
      match.source.index(start, offsetBy: -turkishContextLength, limitedBy: match.source.startIndex)
      ?? match.source.startIndex
    return String(match.source[from..<start])
  }

  // MARK: - Counts

  /// The counts Turkish spells as words in a repeat, a length, or a day phrase,
  /// as the reading form leaves them. "Bir" is the article too, so the
  /// patterns that take it check the unit after it.
  private static let turkishCountList: [(word: String, value: Int)] = [
    ("bir", 1), ("iki", 2), ("uc", 3), ("dort", 4), ("bes", 5), ("alti", 6), ("yedi", 7), ("sekiz", 8), ("dokuz", 9),
    ("on", 10), ("on bir", 11), ("on iki", 12), ("on uc", 13), ("on dort", 14), ("on bes", 15), ("yirmi", 20),
    ("yirmi bes", 25), ("otuz", 30), ("kirk", 40), ("kirk bes", 45), ("elli", 50),
  ]

  private static let turkishCounts: [String: Int] = Dictionary(
    uniqueKeysWithValues: turkishCountList.map { ($0.word, $0.value) })

  /// The count a Turkish word names, in digits or as a number word, or nil.
  static func turkishCount(_ word: String) -> Int? {
    number(word) ?? turkishCounts[turkishPhrase(word)]
  }

  /// The number words as the alternatives of a pattern, with a space between
  /// the words of a compound.
  static var turkishCountWords: String {
    alternation(of: turkishCountList.map(\.word)).replacingOccurrences(of: " ", with: #"\s+"#)
  }

  // MARK: - Priority

  /// The levels a priority may name, as a pattern without groups.
  private static let turkishPriorityLevels = #"yuksek|orta|normal|dusuk"#

  /// Group 1: a written priority ("yüksek öncelik", "düşük öncelikli", "öncelik:
  /// yüksek", "öncelik 1"); "acil" and "önemli" (maybe after "çok", and with the
  /// full stop or exclamation mark that ends the line) at the end of the line,
  /// or opening it before a colon or a comma, have no group. An adjective that
  /// goes on to a noun ("acil servis", "önemli bir toplantı") is no priority,
  /// and neither is a negation after it ("acil değil").
  private static var turkishPriorityPattern: String {
    let urgent = #"(?:(?:cok|son\s+derece)\s+)?(?:acilen|acil|onemli)"#
    let written =
      #"(?:(?:cok\s+)?(?:\#(turkishPriorityLevels))\s+oncelik(?:li)?|oncelik(?:li)?\s*[=:]?\s*(?:cok\s+)?(?:\#(turkishPriorityLevels)|[1-3]))"#
    return
      #"\#(turkishStart)(\#(written))\#(turkishEnd)|(?<=\s)\#(urgent)\#(turkishEnd)[.!]*(?=\s*$)|^\s*\#(urgent)\#(turkishEnd)(?=\s*[:,，：])"#
  }

  private static func turkishPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1) else { return .p1 }
    let key = turkishKey(phrase)
    if let digit = key.last(where: { "123".contains($0) }) {
      return digit == "1" ? .p1 : (digit == "2" ? .p2 : .p3)
    }
    if key.contains("dusuk") { return .p3 }
    if key.contains("orta") || key.contains("normal") { return .p2 }
    return .p1
  }

  // MARK: - Length

  /// The words that open a length and go with it: "yaklaşık 2 saat", "tahmini
  /// süre: 2 saat", "süre: 30 dakika", "toplam 2 saat".
  private static let turkishLengthOpener =
    #"yaklasik|tahmini\s+sure\s*:?|tahmini|sure(?:si)?\s*:|toplam"#

  /// The words before an amount that make it a moment, an interval, or a bound
  /// rather than a length: "her 2 saat", "son 30 dakika", "ilk 2 saat", "en
  /// fazla 2 saat", "en az 30 dakika", "tam 2 saat".
  private static let turkishLengthDecliner =
    #"her|son|ilk|en\s+fazla|en\s+az|tam|sonraki|onceki|gecen|yaklasik\s+her"#

  /// The words after an amount that make it a moment, the past, a bound, a
  /// rate, or the minutes of a spoken time: "30 dakika sonra", "2 saat önce", "2
  /// saat içinde", "2 saat daha", "2 saat başı", "üçü on dakika geçe", "üçe on
  /// dakika var".
  private static let turkishLengthTrailing =
    #"sonra|sonraya|once|evvel|icinde|icerisinde|daha|basi|arayla|aralikla|ara|gece|var|kala"#

  /// The words after an amount that say how long a task takes and go with it:
  /// "2 saat boyunca", "2 saat kadar", "2 saat civarında", "2 saat sürecek".
  private static let turkishLengthClosing =
    #"boyunca|sureyle|suresince|kadar|civarinda|civari|surecek|surer|suren"#

  /// The lengths written as words, as a pattern without groups: "yarım saat",
  /// "çeyrek saat", "üç çeyrek saat", "bir buçuk saat", "iki saat", "yirmi
  /// dakika". "Bir dakika" is left out: it is as often "just a moment".
  private static let turkishLengthWords = [
    #"yarim\s+saat(?:lik)?"#,
    #"ceyrek\s+saat(?:lik)?"#,
    #"uc\s+ceyrek\s+saat(?:lik)?"#,
    #"(?:bir|iki|uc|dort|bes|alti|yedi|sekiz|dokuz|on)\s+bucuk\s+saat(?:lik)?"#,
    #"(?:bir|iki|uc|dort|bes|alti|yedi|sekiz|dokuz|on|on\s+bir|on\s+iki)\s+saat(?:lik)?"#,
    #"(?:iki|uc|dort|bes|alti|yedi|sekiz|dokuz|on|on\s+bes|yirmi|yirmi\s+bes|otuz|kirk|kirk\s+bes|elli)\s+(?:dakika|dk)(?:lik)?"#,
  ].joined(separator: "|")

  /// "30 dakika", "30 dk", "45 dakikalık", "2 saat", "1,5 saat", "1 saat 30
  /// dakika", "yarım saat", "bir buçuk saat", each maybe after an opener and
  /// before a closing word. Groups: 1 the opener; 2 a word before the amount
  /// that makes it a moment, an interval, or a bound; 3 and 4 the hours and
  /// minutes of "1 saat 30 dakika"; 5 hours with a decimal fraction; 6 minutes;
  /// 7 a length in words; 8 a word after the amount that makes it a moment, the
  /// past, a bound, or a rate. A match with group 2 or 8 is no length: the
  /// reader declines it and the title keeps it. The amount may not follow a
  /// digit, a colon, or a separator, and an amount that is a side of a range
  /// ("2-3 saat") is no length.
  static var turkishLengthPattern: String {
    let minutes = #"(?:dakika|dak\.?|dk\.?)(?:lik)?"#
    let hours = #"saat(?:lik)?"#
    return
      #"\#(turkishStart)(?:(\#(turkishLengthOpener))\s+|(\#(turkishLengthDecliner))\s+)?(?<![\p{N}:.,/])(?<![\p{N}]\s?[-–—]\s?)(?:(\d+)\s*\#(hours)\s*(?:ve\s+)?(\d{1,2})\s*\#(minutes)|(\d+(?:[.,]\d+)?)\s*\#(hours)|(\d+)\s*\#(minutes)|(\#(turkishLengthWords)))\#(turkishEnd)(?!\s*[-–—]\s*\d)(?:\s+(?:\#(turkishLengthClosing))\#(turkishEnd))?(?:\s+(\#(turkishLengthTrailing))\#(turkishEnd))?"#
  }

  /// Whether a match of ``turkishLengthPattern`` is kept in the title whole: it
  /// names a moment, an interval, a bound, the past, or a rate.
  static func turkishClaimsLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(8) != nil
  }

  private static func turkishLength(_ match: Match) -> Int? {
    if turkishClaimsLength(match) { return nil }
    if let hours = match.group(3).flatMap(number), let minutes = match.group(4).flatMap(number) {
      return taskLength(minutes: hours * 60 + minutes)
    }
    if let amountText = match.group(5) {
      guard let hours = decimalAmount(amountText) else { return nil }
      return taskLength(minutes: Int((hours * 60).rounded()))
    }
    if let minutes = match.group(6).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(7).flatMap(turkishWordLength)
  }

  /// The minutes a length written in words names: "yarım saat", "çeyrek saat",
  /// "üç çeyrek saat", "bir buçuk saat", "iki saat", "yirmi dakika". The adjective
  /// ending ("saatlik", "dakikalık") is the same length.
  private static func turkishWordLength(_ phrase: String) -> Int? {
    var key = turkishPhrase(phrase)
    for unit in ["saat", "dakika", "dk"] {
      for ending in ["lik", "luk"] where key.hasSuffix(unit + ending) {
        key.removeLast(ending.count)
      }
    }
    switch key {
    case "yarim saat": return 30
    case "ceyrek saat": return 15
    case "uc ceyrek saat": return 45
    default: break
    }
    if let found = key.wholeMatch(of: /(.+) bucuk saat/), let count = turkishCount(String(found.output.1)) {
      return taskLength(minutes: count * 60 + 30)
    }
    if let found = key.wholeMatch(of: /(.+) saat/), let count = turkishCount(String(found.output.1)) {
      return taskLength(minutes: count * 60)
    }
    if let found = key.wholeMatch(of: /(.+) (?:dakika|dk)/), let count = turkishCount(String(found.output.1)) {
      return taskLength(minutes: count)
    }
    return nil
  }
}
