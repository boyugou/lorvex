import Foundation

/// One language's words for a capture line: for each kind of detail a line
/// can name, the patterns that recognize it and what each recognized phrase
/// means.
///
/// ``LorvexCaptureParser`` reads a line one kind of detail at a time and, for
/// each kind, tries the rules of every vocabulary ``vocabularies(for:)``
/// picks, in its order. A rule's pattern is matched case-insensitively
/// against the line without the phrases already recognized, in the
/// vocabulary's ``readingForm``. The rule's reader turns one match into a
/// value, or returns nil to leave the match in the title.
struct LorvexCaptureVocabulary: Sendable {
  /// The line as this vocabulary's patterns read it: the typed line; for
  /// Chinese the line with Traditional characters read as Simplified ones
  /// (``simplifiedForMatching(_:)``); for French, Portuguese, Spanish, and
  /// Italian the line with its accents left out
  /// (``unaccentedForMatching(_:)``); for Russian the line with ё read as е
  /// (``russianForMatching(_:)``); for Ukrainian the line with the curly and
  /// the modifier-letter apostrophe read as the straight one
  /// (``ukrainianForMatching(_:)``); for Polish the line without its accents
  /// and with ł read as l (``polishForMatching(_:)``); for Arabic the line with
  /// its digits read as ASCII ones and its alef, alef maksura, and teh marbuta
  /// forms read as one letter each (``arabicForMatching(_:)``); for Persian the
  /// line with its digits read as ASCII ones, its alefs with hamza or madda read
  /// as the bare alef, and its Arabic yeh, kaf, and teh marbuta forms read as
  /// the Persian yeh, kaf, and heh (``persianForMatching(_:)``); for Marathi
  /// the line with its digits read as ASCII ones, its precomposed nukta letters
  /// read as the base consonants, the candrabindu read as the anusvara, the
  /// eyelash ra (ऱ) read as ra, and the candra o (ऑ) read as aa
  /// (``marathiForMatching(_:)``); for Hindi the
  /// line with its digits read as ASCII ones, its precomposed nukta letters
  /// read as the base consonants, and the candrabindu read as the anusvara
  /// (``hindiForMatching(_:)``); for Bengali the line with its digits read as
  /// ASCII ones and its precomposed ড়, ঢ়, and য় read as the letters ড, ঢ, and য
  /// (``bengaliForMatching(_:)``); for Telugu the line with its digits read as
  /// ASCII ones (``teluguForMatching(_:)``); for Urdu the line with its Arabic-Indic and
  /// Extended Arabic-Indic digits read as ASCII ones, its alefs with hamza or
  /// madda read as the bare alef, its Arabic yeh forms read as the Urdu choti
  /// yeh, its Arabic kaf read as the Urdu kaf, its heh forms read as one heh,
  /// and its noon ghunna read as the noon (``urduForMatching(_:)``); for
  /// Hebrew the line with its final letters read as the regular ones, its
  /// maqaf and other hyphens read as the hyphen, and its apostrophe-like and
  /// double-quote-like marks read as the geresh and the gershayim
  /// (``hebrewForMatching(_:)``); for German the line with ä, ö, ü, and ß read
  /// as a, o, u, and s and a diaeresis typed as a separate sign after a, o,
  /// or u read as e, so every pattern reads a word typed with the umlauts, with
  /// "ae", "oe", "ue", and "ss", or with the dots left out
  /// (``germanForMatching(_:)``); for Dutch the line with its accents left out
  /// ("één" as "een", "vóór" as "voor", "geëindigd" as "geeindigd"), which
  /// ``unaccentedForMatching(_:)`` does; for Romanian the same, which reads ă,
  /// â, and î as a, a, and i and both the comma-below and the cedilla forms of
  /// ș/ş and ț/ţ as s and t ("mâine" as "maine", "sâmbătă" as "sambata"); for
  /// Turkish the line with ç, ğ, ö, ş, ü, â, î, and û read as c, g, o, s, u, a,
  /// i, and u and the dotted and dotless i (ı, I, İ) read as i, so "Salı",
  /// "SALI", and "sali" are one word and "persembe" reads as "perşembe", while
  /// a letter typed as a base letter and a combining mark stays as typed
  /// (``turkishForMatching(_:)``); for Greek the line with the accent and
  /// diaeresis taken off its letters and the final sigma ς read as σ, so
  /// "αύριο", "αυριο", and "ΑΥΡΙΟ" are one word, while a letter typed as a base
  /// letter and a combining mark stays as typed (``greekForMatching(_:)``); for
  /// Indonesian and Malay, which are written without diacritics, for
  /// Vietnamese, whose patterns spell each word with its tone and vowel marks,
  /// without any, or with only the stroke of "đ" written as "d", and for Thai,
  /// whose patterns spell each word with its vowel and tone marks, the line as
  /// typed. It must keep every character at its UTF-16 offset, so a match range
  /// in it is the same range in the typed line.
  var readingForm: @Sendable (String) -> String = { $0 }
  /// High (p1), medium (p2), or low (p3) priority.
  var priority: [Rule<LorvexTask.Priority>] = []
  /// A range of days written out ("May 3-5", "del 3 al 5 de mayo",
  /// 5月3日到5日): its first day is the planned day and its last the due day.
  var dateRange: [Rule<DayRangeReading>] = []
  /// Text that looks like a detail but is none, which stays in the title whole
  /// with no rule of any vocabulary reading a part of it: a deadline written
  /// as a clock time ("до 18:00") is no start time, yet English would read
  /// its "18:00" as one and leave "до" behind. A reader returns true for a
  /// match to keep and nil for a match to leave to the other rules; a pattern
  /// may also match text it must not keep (a range such as "с 14 до 18:00")
  /// so that the scan moves past it whole.
  var keptInTitle: [Rule<Bool>] = []
  /// A length in minutes, from 1 minute to 24 hours.
  var length: [Rule<Int>] = []
  /// A clock time.
  var time: [Rule<ClockTime>] = []
  /// How the task repeats.
  var repeats: [Rule<Repeat>] = []
  /// The day the task is due.
  var due: [Rule<Day>] = []
  /// The day the task is planned for.
  var when: [Rule<Day>] = []
  /// True for a language that writes a clock time with the letter h ("15h",
  /// "15h30"), which reads every hour count written with h itself, as a time
  /// or as a length by the words around it.
  var writesClockTimesWithH = false

  /// The vocabularies a line is read with for a user who reads `languages`
  /// (BCP 47 codes such as "ja-JP"), in the order each kind of detail tries
  /// them: Japanese, Korean, French, Portuguese, Spanish, Italian, Russian,
  /// Ukrainian, Polish, Arabic, Persian, Marathi, Hindi, Bengali, Telugu, Urdu,
  /// Hebrew, German, Dutch, Romanian, Malay, Indonesian, Vietnamese, Turkish,
  /// Thai, and Greek when `languages` includes them (any region of a language:
  /// "es-MX", "es-419", "it-CH", "uk-UA", "pl-PL", "ar-SA", "fa-IR", "fa-AF",
  /// "mr-IN", "hi-IN", "bn-BD", "bn-IN", "te-IN", "ur-PK", "ur-IN", "he-IL",
  /// "de-AT", "de-CH", "nl-BE", "ro-MD", "ms-MY", "ms-SG", "ms-BN", "id-ID",
  /// "vi-VN", "tr-TR", "tr-CY", "th-TH", "el-GR", "el-CY"), then Chinese and
  /// English, which every line is read with.
  ///
  /// The order settles a phrase two vocabularies could both read. Japanese
  /// goes before Chinese, so a date the two write alike is taken with its
  /// Japanese particle ("10月5日に"). Every other language goes before
  /// English, so a part of the day or a word written before or after a clock
  /// time ("下午3:30", "오후 3:30", "a las 3:30", "в 15:00", "o 15:00", "الساعة 3:30",
  /// "ساعت 3:30", "3:30 वाजता", "3:30 बजे", "সকাল 3:30", "3:30 بجے", "בשעה 3:30", "um 15:30",
  /// "abends 7:30", "om 15:30", "'s avonds 7:30", "la 15:30", "seara 7:30",
  /// "15:00 น.") is read with the time instead of being left in the title when
  /// the English pattern takes "3:30" or "15:00". Persian goes after Arabic, so
  /// for a user who reads both, a phrase the two could read is read the Arabic
  /// way; they share few words.
  /// Marathi goes before Hindi. Both write Devanagari and share a few day words
  /// (आज, the weekday names, मार्च and जून, वीकेंड) and cadence words (प्रत्येक,
  /// रोज, नित्य), and Hindi writes the words that go with them as separate
  /// words ("आज की रात", "सोमवार को", "प्रत्येक सोमवार को"), which Marathi would
  /// leave behind in the title if it took the shared word alone. For a user who
  /// reads both, Marathi therefore leaves a shared word to Hindi whenever such a
  /// Hindi word follows it, or precedes a weekday (``marathiBesideHindi``), so
  /// each language's lines read as they do alone; the words only Marathi has
  /// ("उद्या", "वाजता", "दर सोमवारी") are read by Marathi.
  /// Bengali goes after Hindi: its letters, digits, and words belong to no other
  /// vocabulary, so its position settles no phrase between it and another
  /// language. A Bengali rule that could take a phrase English reads with the
  /// words around it ("at 3:30 PM") reads it only beside a Bengali word.
  /// Telugu goes after Bengali for the same reason: its script, digits, and
  /// words belong to no other vocabulary, and a Telugu rule that could take a
  /// phrase English reads with the words around it reads it only beside a
  /// Telugu word.
  /// Urdu goes after Persian and Hindi, so for a user who
  /// reads Urdu and one of them, a phrase two of them could read is read the
  /// earlier way; Urdu shares its script with Arabic and Persian and its spoken
  /// words with Hindi, but few written words with any of them. Hebrew goes
  /// after them: its letters belong to no other vocabulary, so its position
  /// settles no phrase between it and another language. German, Dutch,
  /// Romanian, Malay, Indonesian, Vietnamese, and Turkish go next: their words
  /// are written in Latin letters like the French, Portuguese, Spanish,
  /// Italian, and Polish ones, but no phrase is the same in two of them ("um 15 Uhr", "om 15 uur", "la ora 15", "pukul 15", "3 giờ
  /// chiều", "saat 15:00", "jeden Montag", "elke maandag", "în fiecare luni",
  /// "setiap Isnin", "mỗi thứ Hai", "her pazartesi"), and where two of them
  /// share a word with one meaning ("morgen", "15 oktober", "15 august",
  /// "15/10/2026") either reads it alike, so their positions settle no phrase
  /// either. Thai and Greek go after them: like Hebrew, their letters belong to
  /// no other vocabulary, so their positions settle no phrase between them and
  /// another language. Malay goes before Indonesian, which it
  /// shares many words with ("hari ini", "setiap", "pukul", "jam", "lusa"): a
  /// word they read alike is read alike, a phrase only Malay reads ("pukul tiga
  /// setengah", "8 malam", "5hb") is read by Malay, and a phrase only Indonesian
  /// reads ("setengah empat", "jam 3 sore", "tanggal 5 Oktober") is left by the
  /// Malay rules for the Indonesian ones, so a user who reads both has the whole
  /// phrase read instead of a part of it. Vietnamese goes after Indonesian and
  /// shares no phrase with it. Its clock time written with the letter h ("15h",
  /// "15h30") is also French, Portuguese, and German, which go before it and
  /// read the time alike, so for a user who reads one of them and Vietnamese a
  /// "lúc" before it stays in the title. Vietnamese also reads a line typed
  /// without tone marks ("ngay mai", "thu hai"), where a bare word may be
  /// another language's word ("mai" is May in French), so it reads such a word
  /// only inside the phrase that needs it ("ngày mai", "chiều mai", never "mai"
  /// alone). Beside a language that writes a clock time with the letter h
  /// (French, Portuguese, German, and Vietnamese), English leaves hour counts
  /// written with h to it (``englishBesideHourClock``), so "15h" is never read
  /// as fifteen hours.
  /// Spanish, Italian, Russian, Ukrainian, Polish, Arabic, Persian, Marathi,
  /// Hindi, Bengali, Telugu, Urdu, Hebrew, Dutch, Romanian, Malay, Indonesian,
  /// Turkish, Thai, and Greek do not write a clock time that way (Marathi
  /// writes its hours with "वाजता" after the hour, Bengali with the classifier
  /// "টা" after the hour, Telugu with "గంటలకు" after it, Dutch with "uur" or
  /// "u", Romanian with "ora"
  /// before the hour, Malay and Indonesian with "pukul" or "jam" before it,
  /// Turkish with "saat" before the hour or a case ending after it, Thai with
  /// "โมง", "ทุ่ม", or "ตี" or with "น." after the time, Greek with "στις" or
  /// "ώρα" before it), so "2h" beside them stays a length.
  static func vocabularies(for languages: [String]) -> [LorvexCaptureVocabulary] {
    let codes = Set(languages.compactMap { $0.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased() })
    var vocabularies: [LorvexCaptureVocabulary] = []
    if codes.contains("ja") { vocabularies.append(.japanese) }
    if codes.contains("ko") { vocabularies.append(.korean) }
    if codes.contains("fr") { vocabularies.append(.french) }
    if codes.contains("pt") { vocabularies.append(.portuguese) }
    if codes.contains("es") { vocabularies.append(.spanish) }
    if codes.contains("it") { vocabularies.append(.italian) }
    if codes.contains("ru") { vocabularies.append(.russian) }
    if codes.contains("uk") { vocabularies.append(.ukrainian) }
    if codes.contains("pl") { vocabularies.append(.polish) }
    if codes.contains("ar") { vocabularies.append(.arabic) }
    if codes.contains("fa") { vocabularies.append(.persian) }
    if codes.contains("mr") { vocabularies.append(codes.contains("hi") ? .marathiBesideHindi : .marathi) }
    if codes.contains("hi") { vocabularies.append(.hindi) }
    if codes.contains("bn") { vocabularies.append(.bengali) }
    if codes.contains("te") { vocabularies.append(.telugu) }
    if codes.contains("ur") { vocabularies.append(.urdu) }
    if codes.contains("he") { vocabularies.append(.hebrew) }
    if codes.contains("de") { vocabularies.append(.german) }
    if codes.contains("nl") { vocabularies.append(.dutch) }
    if codes.contains("ro") { vocabularies.append(.romanian) }
    if codes.contains("ms") { vocabularies.append(.malay) }
    if codes.contains("id") { vocabularies.append(.indonesian) }
    if codes.contains("vi") { vocabularies.append(.vietnamese) }
    if codes.contains("tr") { vocabularies.append(.turkish) }
    if codes.contains("th") { vocabularies.append(.thai) }
    if codes.contains("el") { vocabularies.append(.greek) }
    let english = vocabularies.contains(where: \.writesClockTimesWithH) ? englishBesideHourClock : .english
    return vocabularies + [.chinese, english]
  }
}

extension LorvexCaptureVocabulary {
  /// One pattern and what its matches mean.
  struct Rule<Value>: Sendable {
    var pattern: String
    /// The value one match names, or nil when the match is not that detail
    /// after all ("Monday Morning Memo" names no day).
    var read: @Sendable (Match) -> Value?
  }

  /// One match of a rule's pattern, with what a reader needs to judge it.
  struct Match {
    var result: NSTextCheckingResult
    /// The line as the parser reads it, whose UTF-16 offsets the match's
    /// ranges are.
    var source: String
    /// The logical today's weekday, 1 = Sunday … 7 = Saturday (the Gregorian
    /// `Calendar` convention).
    var todayWeekday: Int
    /// The UTC midnight of the logical today, when the caller gave the day;
    /// written-out dates are read only with it.
    var today: Date?

    /// The text of capture group `index`, or nil when the group took no part
    /// in the match.
    func group(_ index: Int) -> String? {
      let range = result.range(at: index)
      guard range.location != NSNotFound, let bounds = Range(range, in: source) else { return nil }
      return String(source[bounds])
    }
  }

  /// A day a phrase names.
  struct Day {
    /// Days after the logical today.
    var offset: Int
    /// True for the evening of a day ("tonight", 今晚), which puts a clock
    /// time written without AM, PM, or a part of the day in that evening.
    var isEvening = false
  }

  /// The first and the last day of a range a phrase names ("May 3-5").
  struct DayRange {
    /// Days after the logical today of the first day.
    var start: Int
    /// Days after the logical today of the last day, which is after the first.
    var end: Int
  }

  /// What a date-range rule makes of one match.
  enum DayRangeReading {
    /// The match names these days, and its whole text leaves the title.
    case range(DayRange)
    /// The match is written as a range but names none, as "May 5-3" (the end
    /// is not after the start) or "May 3 - Feb 30" (no such day). Its text
    /// stays in the title, and no other rule reads a part of it, so neither
    /// "May 5" nor "3 May" is taken from it.
    case declined
  }

  /// A repeat a phrase names.
  struct Repeat {
    var rule: TaskRecurrenceRule
    /// The weekdays the rule names, 0 = Sunday, which fix its first
    /// occurrence.
    var weekdays: [Int] = []
    /// The day of the month the rule names, which fixes its first occurrence.
    var monthDay: Int?
  }

  /// A clock time a line named.
  struct ClockTime {
    /// Minutes since midnight on the day the time falls on.
    var minutes: Int
    /// For a time written with no AM, PM, or part of day, the hour as
    /// written, before a 1 to 6 o'clock moves to the afternoon; nil otherwise.
    var writtenHour: Int?
    /// True when the time falls after the midnight that ends the named day
    /// ("晚上12点", "半夜1点", "at midnight"), so it is on the next day.
    var isAfterMidnight = false
    /// For a range ("3-4pm", 下午3点到5点), the minutes from this time to the
    /// range's end; nil for a single time.
    var length: Int?
  }
}

// MARK: - Shared by the vocabularies

extension LorvexCaptureVocabulary {
  /// A word boundary for words written in Latin letters: no Latin letter,
  /// digit, or apostrophe on that side, so "today's" is one word.
  static let latinStart = #"(?<![\p{Latin}\p{N}'’])"#
  static let latinEnd = #"(?![\p{Latin}\p{N}'’])"#

  /// A word boundary for words written in Cyrillic letters: no Cyrillic
  /// letter, digit, or apostrophe on that side. Ukrainian writes an apostrophe
  /// inside a word in three forms (U+0027, U+2019, and U+02BC: п'ятниця), so a
  /// word that contains any of them is one word.
  static let cyrillicStart = #"(?<![\p{Cyrillic}\p{N}'\x{2019}\x{02BC}])"#
  static let cyrillicEnd = #"(?![\p{Cyrillic}\p{N}'\x{2019}\x{02BC}])"#

  /// The line with each accented letter read without its accent ("après" as
  /// "apres", "ç" as "c"), so a pattern written without accents matches a
  /// line typed with or without them. A character whose unaccented form takes
  /// a different number of UTF-16 units, such as a letter typed with a
  /// separate combining accent, stays as typed, which keeps every character
  /// at its UTF-16 offset.
  static func unaccentedForMatching(_ line: String) -> String {
    var result = ""
    for character in line {
      let typed = String(character)
      let unaccented = typed.folding(options: .diacriticInsensitive, locale: nil)
      result += unaccented.utf16.count == typed.utf16.count ? unaccented : typed
    }
    return result
  }

  /// The word just before `match` in its line, lowercased, with a curly
  /// apostrophe read as a straight one ("d'ici"), or nil when the match opens
  /// the line. A rule reads it to judge a match by the word that introduces
  /// it.
  static func wordBefore(_ match: Match) -> String? {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return nil }
    let word = match.source[..<start].reversed().drop(while: \.isWhitespace)
      .prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" })
    return word.isEmpty ? nil : String(word.reversed()).lowercased().replacingOccurrences(of: "’", with: "'")
  }

  /// The word just after `match` in its line, lowercased, with a curly
  /// apostrophe read as a straight one, or nil when the match ends the line or
  /// punctuation, a digit, or a symbol follows it. A rule reads it to judge a
  /// match by the word that follows it ("a las 3 hermanas" counts sisters, it
  /// does not name an hour).
  static func wordAfter(_ match: Match) -> String? {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return nil }
    let word = match.source[end...].drop(while: \.isWhitespace)
      .prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" })
    return word.isEmpty ? nil : String(word).lowercased().replacingOccurrences(of: "’", with: "'")
  }

  /// Whether nothing but spaces and punctuation follows `match` in its line.
  static func endsLine(_ match: Match) -> Bool {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return false }
    return match.source[end...].allSatisfy { $0.isWhitespace || $0.isPunctuation }
  }

  /// The amount a matched number spells, with a comma or a point before its
  /// fraction ("1,5", "1.5"), since French, Portuguese, Spanish, and Italian
  /// write either.
  static func decimalAmount(_ text: String) -> Double? {
    LorvexNumberInput.decimal(from: text.replacingOccurrences(of: ",", with: "."))
  }

  /// A matched phrase as a reader compares it: lowercased, with a curly
  /// apostrophe read as a straight one, hyphens read as spaces, and each run
  /// of spaces as one ("Après-demain" as "après demain").
  static func normalizedPhrase(_ phrase: String) -> String {
    phrase.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// A repeat pattern for a language that writes Latin letters: a cadence
  /// written as `phrases` anywhere in the line, or as `adverb` at its end.
  /// An adverb ("hebdomadairement", "semanalmente") cannot belong to a title
  /// the way an adjective after its noun can ("Rapport hebdomadaire",
  /// "Relatório semanal"), and the end of the line is where it says how a
  /// task repeats.
  static func cadencePattern(_ phrases: String, adverb: String) -> String {
    "\(latinStart)(?:\(phrases))\(latinEnd)|\(latinStart)\(adverb)(?=\\s*$)"
  }

  /// "15h", "15h30", "15 h 30", or a bare "15", with nothing around it, as a
  /// time written without a part of the day: one side of a range in a
  /// language that writes a clock time with the letter h.
  static func hourTime(_ text: String) -> ClockTime? {
    guard let match = text.wholeMatch(of: /(\d{1,2})\s*(?:[hH](?:\s*(\d{2}))?)?/), let hour = number(match.output.1)
    else { return nil }
    let minute = match.output.2.flatMap { number($0) } ?? 0
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(match.output.1)))
  }

  /// RFC 5545 weekday codes, Sunday first.
  static let weekdayCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

  /// Every Monday to Friday, starting on the next of them.
  static var workdays: Repeat {
    Repeat(rule: TaskRecurrenceRule(freq: .weekly, byDay: Array(weekdayCodes[1...5])), weekdays: Array(1...5))
  }

  /// Every `interval` weeks (nil for every week), on `days` (0 = Sunday) when
  /// it names any.
  static func weekly(every interval: Int?, on days: [Int]) -> Repeat {
    let unique = Array(Set(days)).sorted()
    return Repeat(
      rule: TaskRecurrenceRule(
        freq: .weekly, interval: interval, byDay: unique.isEmpty ? nil : unique.map { weekdayCodes[$0] }),
      weekdays: unique)
  }

  /// Every `interval` months (nil for every month), on `day` of the month
  /// when one is named; nil for a day of the month past 31.
  static func monthly(every interval: Int?, on day: Int?) -> Repeat? {
    if let day, !(1...31).contains(day) { return nil }
    return Repeat(
      rule: TaskRecurrenceRule(freq: .monthly, interval: interval, byMonthDay: day.map { [$0] }), monthDay: day)
  }

  /// The whole number a matched run of digits spells. The patterns' `\d`
  /// matches the decimal digits of every script (a full-width "３" from a
  /// Chinese input method, an Arabic-Indic "٣"), which `Int(_:)` cannot read.
  static func number(_ text: some StringProtocol) -> Int? {
    LorvexNumberInput.integer(from: text)
  }

  /// The value of a numeral written in Han characters, from 0 to 59, as
  /// Chinese and Japanese write them: 三, 十, 十二, 二十, 四十五, 两.
  static func hanNumber(_ text: String) -> Int? {
    let digits: [Character: Int] = [
      "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    let characters = Array(text)
    guard let tenIndex = characters.firstIndex(of: "十") else {
      return characters.count == 1 ? digits[characters[0]] : nil
    }
    let tens = tenIndex == 0 ? 1 : (tenIndex == 1 ? digits[characters[0]] : nil)
    let rest = characters[(tenIndex + 1)...]
    guard let tens, rest.count <= 1 else { return nil }
    let ones = rest.first.map { digits[$0] } ?? 0
    guard let ones else { return nil }
    let value = tens * 10 + ones
    return value < 60 ? value : nil
  }

  /// `minutes` when it is a length a task can take, from 1 minute to 24
  /// hours.
  static func taskLength(minutes: Int) -> Int? {
    minutes > 0 && minutes <= 24 * 60 ? minutes : nil
  }

  /// Whether a written hour starts with a zero digit in any script ("09",
  /// "０９"), which marks it as a 24-hour time.
  static func startsWithZero(_ hourText: String) -> Bool {
    hourText.first.flatMap { number(String($0)) } == 0
  }

  /// A time written without AM, PM, or a part of day: from 1 to 6 o'clock it
  /// is the afternoon, since tasks are seldom planned before dawn, unless
  /// written with a leading zero ("06:30").
  static func bareTime(hour: Int, minute: Int, hasLeadingZero: Bool) -> ClockTime? {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    let shifted = !hasLeadingZero && (1...6).contains(hour) ? hour + 12 : hour
    return ClockTime(minutes: shifted * 60 + minute, writtenHour: hour)
  }

  /// A time in the night of the named day, which runs past midnight: 12
  /// o'clock (or 0 or 24) is the midnight that ends the day and 1 to 5
  /// o'clock the small hours after it, both on the next day; 6 to 11 o'clock
  /// is the evening; a 24-hour time from 13:00 stays as written.
  static func nightTime(hour: Int, minute: Int) -> ClockTime? {
    switch hour {
    case 0, 12, 24: ClockTime(minutes: minute, isAfterMidnight: true)
    case 1...5: ClockTime(minutes: hour * 60 + minute, isAfterMidnight: true)
    case 6...11: ClockTime(minutes: (hour + 12) * 60 + minute)
    case 13...23: ClockTime(minutes: hour * 60 + minute)
    default: nil
    }
  }

  /// The minutes since midnight an hour written without AM, PM, or a part of
  /// the day can mean: 3 is 3:00 or 15:00, 12 is 0:00 or 12:00, and 0 or an
  /// hour from 13 only itself.
  static func readings(ofHour hour: Int, minute: Int) -> [Int] {
    switch hour {
    case 1...12: [(hour % 12) * 60 + minute, (hour % 12 + 12) * 60 + minute]
    default: [hour * 60 + minute]
    }
  }

  /// The time a range names ("3-4pm", "下午3点到5点"): its start, with the
  /// length to its end, from both sides read as clock times.
  ///
  /// A side written without AM, PM, or a part of the day (one with a
  /// ``ClockTime/writtenHour``) takes the reading that fits the other side. A
  /// bare start is the latest reading of its hour before a written end:
  /// "3-4pm" starts at 15:00, "11-1pm" at 11:00. A bare end is the first
  /// reading of its hour after the start: "下午3点到5点" ends at 17:00,
  /// "晚上11点到1点" at 1:00 the next day. A written end at or before the start
  /// is on the next day. Nil when no reading fits or the range lasts a day or
  /// more.
  static func timeRange(from start: ClockTime, to end: ClockTime) -> ClockTime? {
    let day = 24 * 60
    let writtenEnd = end.minutes + (end.isAfterMidnight ? day : 0)
    var startMinutes = start.minutes
    if let hour = start.writtenHour, end.writtenHour == nil {
      guard let latest = readings(ofHour: hour, minute: start.minutes % 60).filter({ $0 < writtenEnd }).max()
      else { return nil }
      startMinutes = latest
    }
    var endMinutes = writtenEnd
    if let hour = end.writtenHour {
      let sameDay = readings(ofHour: hour, minute: end.minutes % 60)
      guard let first = (sameDay + sameDay.map { $0 + day }).filter({ $0 > startMinutes }).min() else { return nil }
      endMinutes = first
    } else if endMinutes <= startMinutes {
      endMinutes += day
    }
    let length = endMinutes - startMinutes
    guard (1..<day).contains(length) else { return nil }
    // A range with both sides bare stays bare, so "tonight 8:00-10:00" moves
    // to the evening like "tonight 8:00".
    let isBare = start.writtenHour != nil && end.writtenHour != nil
    return ClockTime(
      minutes: startMinutes, writtenHour: isBare ? start.writtenHour : nil, isAfterMidnight: start.isAfterMidnight,
      length: length)
  }

  /// The clock time all of `text` names under `pattern`, a time rule's
  /// pattern, as `read` reads it; nil unless the pattern matches the whole
  /// text. A range rule reads each of its sides with it.
  static func wholeTime(
    _ text: String, pattern: String, in match: Match, read: (Match) -> ClockTime?
  ) -> ClockTime? {
    guard let regex = LorvexCapturePatterns.regex("^(?:\(pattern))$"),
      let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return read(Match(result: result, source: text, todayWeekday: match.todayWeekday, today: match.today))
  }

  /// "15:30" or "15：30" with nothing around it, as a time written without AM,
  /// PM, or a part of the day.
  static func colonTime(_ text: String) -> ClockTime? {
    guard let match = text.wholeMatch(of: /(\d{1,2})[:：](\d{2})/), let hour = number(match.output.1),
      let minute = number(match.output.2)
    else { return nil }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(match.output.1)))
  }

  /// No AM or PM after a range: one written "3:00-4:00 pm" is left to the
  /// English range rule, which reads the PM.
  static let noMeridiemAfter = #"(?!\s*[ap]\.?m\.?(?!\p{Latin}))"#

  /// Days from today to the next `weekday` (0 = Sunday), 0 when it is today.
  static func weekdayDelta(_ weekday: Int, todayWeekday: Int) -> Int {
    (weekday + 1 - todayWeekday + 7) % 7
  }

  /// Days from today to the coming Saturday, or 0 on a Saturday or Sunday,
  /// when the weekend is already here.
  static func weekendOffset(todayWeekday: Int) -> Int {
    todayWeekday == 7 || todayWeekday == 1 ? 0 : 7 - todayWeekday
  }

  /// Days from today to `weekday` (0 = Sunday) of next week, weeks starting
  /// on Monday: on a Tuesday, next week's Wednesday is 8 days ahead and next
  /// week's Monday 6.
  static func nextWeekOffset(_ weekday: Int, todayWeekday: Int) -> Int {
    let todayFromMonday = (todayWeekday + 5) % 7
    let weekdayFromMonday = (weekday + 6) % 7
    return 7 - todayFromMonday + weekdayFromMonday
  }

  /// Days from today to the next `weekday` (0 = Sunday) when a weekday is
  /// named alone: a full week ahead when it names today.
  static func comingWeekdayOffset(_ weekday: Int, todayWeekday: Int) -> Int {
    let delta = weekdayDelta(weekday, todayWeekday: todayWeekday)
    return delta == 0 ? 7 : delta
  }

  /// A written-out date: year (nil when not written), month (nil for a day
  /// of the month alone, such as "5号"), and day.
  struct ExplicitDate {
    var year: Int?
    var month: Int?
    var day: Int
  }

  /// Days from `today`, a UTC midnight, to `date`: a date without a year is
  /// this year's, or next year's once passed; a date without a month is this
  /// month's, or next month's once passed. Nil for a day the calendar lacks,
  /// a written year's date in the past, or one more than ten years ahead.
  static func offset(to date: ExplicitDate, from today: Date) -> Int? {
    let calendar = utcCalendar
    let now = calendar.dateComponents([.year, .month, .day], from: today)
    guard let thisYear = now.year, let thisMonth = now.month else { return nil }
    func days(year: Int, month: Int) -> Int? {
      let components = DateComponents(year: year, month: month, day: date.day)
      guard let target = calendar.date(from: components),
        calendar.component(.day, from: target) == date.day
      else { return nil }
      return calendar.dateComponents([.day], from: today, to: target).day
    }
    let result: Int?
    if let month = date.month {
      if let year = date.year {
        result = days(year: year, month: month)
      } else if let current = days(year: thisYear, month: month), current >= 0 {
        result = current
      } else {
        result = days(year: thisYear + 1, month: month)
      }
    } else if let current = days(year: thisYear, month: thisMonth), current >= 0 {
      result = current
    } else {
      result = thisMonth == 12 ? days(year: thisYear + 1, month: 1) : days(year: thisYear, month: thisMonth + 1)
    }
    guard let result, (0...3650).contains(result) else { return nil }
    return result
  }

  /// The range of days from the written-out date `start` to `end`, each read
  /// like a single date by ``offset(to:from:)``.
  ///
  /// A side written without a month takes the other side's ("May 3-5", "3-5
  /// May"). The start without a year is the next such day, and the end the
  /// first one after it: an end in an earlier month than the start's falls in
  /// the following year ("Dec 30 - Jan 2"). A year written on the end only
  /// ("Dec 30 - Jan 2, 2027") places the start too. When neither side has a
  /// month ("del 3 al 5"), the start is the next such day and the end is a day
  /// of the start's month.
  ///
  /// Nil without `today`, since written-out days are read only with it.
  /// ``DayRangeReading/declined`` when a side names a day the calendar lacks, a
  /// year is in the past, or the end is not after the start.
  static func dayRangeReading(from start: ExplicitDate, to end: ExplicitDate, today: Date?) -> DayRangeReading? {
    guard let today else { return nil }
    var start = start
    var end = end
    start.month = start.month ?? end.month
    end.month = end.month ?? start.month
    if start.year == nil, let endYear = end.year {
      start.year = (start.month ?? 1) <= (end.month ?? 12) ? endYear : endYear - 1
    }
    let calendar = utcCalendar
    guard let first = offset(to: start, from: today),
      let firstDay = calendar.date(byAdding: .day, value: first, to: today),
      let year = calendar.dateComponents([.year], from: firstDay).year,
      let month = calendar.dateComponents([.month], from: firstDay).month
    else { return .declined }
    let endMonth = end.month ?? month
    end.month = endMonth
    end.year = end.year ?? (endMonth >= month ? year : year + 1)
    guard let last = offset(to: end, from: today), last > first else { return .declined }
    return .range(DayRange(start: first, end: last))
  }

  /// The words that open a date range in the Latin-script vocabularies that
  /// write one with an opening word ("du", "del", "dal", "entre", "tra").
  private static let rangeOpeningWords: Set<String> = ["de", "del", "desde", "do", "du", "dal", "entre", "tra", "fra"]

  /// Whether a range joined by a word that means "to" may stand without an
  /// opening word ("3 al 5 de mayo"): its end names a month, and the word
  /// before it is not an opening word. That word would make the text part of
  /// a range that opens in another language, which that language reads whole:
  /// Spanish would otherwise read "3 al 10 agosto" out of the Italian "dal 3
  /// al 10 agosto" and leave "dal" in the title.
  static func joinsWithoutOpeningWord(_ match: Match, end: ExplicitDate) -> Bool {
    end.month != nil && !rangeOpeningWords.contains(wordBefore(match) ?? "")
  }

  /// Whether the dash between capture groups `start` and `end`, the two sides
  /// of a range, touches both, as in "3-5 May". A range that opens with a day
  /// alone and no opening word is read only then: a spaced dash after a number
  /// ("Sprint 12 - 20 May") sets a number of the title apart from a date.
  static func dashTouchesBothSides(_ match: Match, start: Int, end: Int) -> Bool {
    let first = match.result.range(at: start)
    let last = match.result.range(at: end)
    guard first.location != NSNotFound, last.location != NSNotFound, last.location >= NSMaxRange(first),
      let gap = Range(NSRange(location: NSMaxRange(first), length: last.location - NSMaxRange(first)), in: match.source)
    else { return false }
    return !match.source[gap].contains(where: \.isWhitespace)
  }

  /// The Gregorian calendar in UTC, in which the logical today and written
  /// dates are counted as whole days.
  static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }
}
