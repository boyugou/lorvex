import Foundation

extension LorvexCaptureVocabulary {
  // The Indonesian clock-time rules: a time with "jam" or "pukul" ("jam 3",
  // "pukul 15.30"), with a part of the day ("jam 8 malam", "7.30 malam"), the
  // spoken forms ("jam 3 lewat 15", "setengah empat"), a range of times, noon
  // and midnight, and the rules that keep a deadline written as a clock time in
  // the title. The vocabulary's other words are in ``indonesian``.

  // MARK: - Parts of the day

  /// A part of the day a clock time may be written with.
  private enum IndonesianPart {
    /// "subuh" and "dini hari": the hours before sunrise, 1 to 6.
    case dawn
    /// "pagi": 1 to 11 in the morning.
    case morning
    /// "siang": late morning and early afternoon, 10 to 3 (12 is noon).
    case midday
    /// "sore": the afternoon until sunset, 1 to 11 counted from noon.
    case afternoon
    /// "malam": the evening and the night, up to the small hours after midnight.
    case night
    /// "tengah malam": 12 at night.
    case midnight
    /// "tengah hari" and "siang bolong": 12 at noon.
    case noon
  }

  /// The words that name a part of the day after an hour, as a pattern without
  /// groups and with the space before them: "pagi", "siang", "sore", "malam"
  /// (each maybe with "ini" after it), "subuh", "dini hari", "tengah malam",
  /// "tengah hari", "siang bolong", each maybe after "nanti" ("jam 8 nanti
  /// malam").
  private static let indonesianPartAfterHour =
    #"(?:\s+(?:nanti\s+)?(?:siang\s+bolong|tengah\s+malam|tengah\s+hari|dini\s+hari|subuh|(?:pagi|siang|sore|malam)(?:\s+ini)?))"#

  /// The part of the day a matched word or phrase names: "malam ini", "nanti
  /// malam", "dini hari", "tengah malam".
  private static func indonesianPartOfDay(_ text: String) -> IndonesianPart? {
    let words = indonesianPhrase(text).split(separator: " ").map(String.init)
    if words.contains("bolong") { return .noon }
    if let tengah = words.firstIndex(of: "tengah"), tengah + 1 < words.count {
      if words[tengah + 1] == "malam" { return .midnight }
      if words[tengah + 1] == "hari" { return .noon }
    }
    if words.contains("subuh") || words.contains("dini") { return .dawn }
    if words.contains("pagi") { return .morning }
    if words.contains("siang") { return .midday }
    if words.contains("sore") { return .afternoon }
    if words.contains("malam") { return .night }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it: "7 pagi" is 07:00, "12 siang" noon, "3 sore"
  /// 15:00, "8 malam" 20:00, "2 dini hari" 02:00, and "12 malam" or "1 malam"
  /// the midnight and the small hours that end the named day, on the next day.
  /// An hour on the 24-hour clock (13 to 23) is read as written when its part
  /// of the day is one it falls in: the midday is 13 to 16, the afternoon 13 to
  /// 19, and the night 18 to 23.
  private static func indonesianTimeWithPart(hour: Int, minute: Int, part: IndonesianPart) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    switch part {
    case .dawn:
      return (1...6).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .morning:
      return (1...11).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .midday:
      if hour == 12 || (10...11).contains(hour) || (13...16).contains(hour) {
        return ClockTime(minutes: hour * 60 + minute)
      }
      return (1...6).contains(hour) ? ClockTime(minutes: (hour + 12) * 60 + minute) : nil
    case .afternoon:
      if (1...11).contains(hour) { return ClockTime(minutes: (hour + 12) * 60 + minute) }
      return (13...19).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .night:
      if (13...23).contains(hour) { return (18...23).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil }
      return nightTime(hour: hour, minute: minute)
    case .midnight:
      return [0, 12].contains(hour) ? ClockTime(minutes: minute, isAfterMidnight: true) : nil
    case .noon:
      return hour == 12 ? ClockTime(minutes: 12 * 60 + minute) : nil
    }
  }

  /// The part of the day written just before `match` with nothing between: "malam
  /// jam 8", "besok malam jam 8", "malam ini jam 8", "nanti malam, jam 8", "Jumat
  /// sore jam 4".
  private static let indonesianPartBeforePattern =
    #"(?:^|\s)(?:nanti\s+)?(pagi|siang|sore|malam|subuh|dini\s+hari)(?:\s+(?:ini|nanti))?\s*[,:]?\s*$"#

  /// A meal that names the part of the day it is eaten in: "makan malam",
  /// "makan siang", "sarapan". Groups: 1 the part after "makan", 2 the part
  /// after "santap", 3 "sarapan".
  private static let indonesianMealPattern =
    #"\#(indonesianStart)(?:makan\s+(malam|siang|pagi|sore)|santap\s+(malam|siang|pagi)|(sarapan))\#(indonesianEnd)"#

  /// The part of the day written directly before `match`.
  private static func indonesianPartBefore(_ match: Match) -> IndonesianPart? {
    let before = indonesianTextBefore(match)
    guard let regex = LorvexCapturePatterns.regex(indonesianPartBeforePattern),
      let found = regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)),
      let range = Range(found.range(at: 1), in: before)
    else { return nil }
    return indonesianPartOfDay(String(before[range]))
  }

  /// The parts of the day the meals in `text` name.
  private static func indonesianMealParts(in text: String) -> [IndonesianPart] {
    guard let regex = LorvexCapturePatterns.regex(indonesianMealPattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { found in
      if found.range(at: 3).location != NSNotFound { return .morning }
      for group in [1, 2] {
        if let range = Range(found.range(at: group), in: text) { return indonesianPartOfDay(String(text[range])) }
      }
      return nil
    }
  }

  /// The part of the day the line names beside `match` for an hour written
  /// without one: the part written directly before it ("malam jam 8", "besok
  /// malam jam 8"), or a meal in the same clause ("makan malam dengan keluarga
  /// jam 8", "jam 8 makan malam"). Nil when the line names no part there, or
  /// names two that differ.
  private static func indonesianLinePart(beside match: Match) -> IndonesianPart? {
    let separators = CharacterSet(charactersIn: ".;!?,\n")
    var parts: [IndonesianPart] = []
    if let adjacent = indonesianPartBefore(match) { parts.append(adjacent) }
    let before = indonesianTextBefore(match).components(separatedBy: separators).last ?? ""
    let after = indonesianTextAfter(match).components(separatedBy: separators).first ?? ""
    parts += indonesianMealParts(in: before) + indonesianMealParts(in: after)
    guard let first = parts.first, parts.allSatisfy({ $0 == first }) else { return nil }
    return first
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part
  /// of the day of its own) names: its line's part of the day when the line
  /// names one and the hour is on the clock of 12 hours, else the hour as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func indonesianBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    if !hasLeadingZero, (1...12).contains(hour), let part = indonesianLinePart(beside: match),
      let time = indonesianTimeWithPart(hour: hour, minute: minute, part: part)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, or colon
  /// (the word or the number goes on), no letter joined by a hyphen, no decimal
  /// fraction, no percent or currency sign with or without a space before it,
  /// no dash before a digit, which makes the time one side of a range written
  /// with a dash, and no AM or PM, which English reads.
  private static let indonesianTimeEnd =
    #"(?![\p{Latin}\p{N}\p{M}:]|[-–]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d|\s*[ap]\.?m\.?(?![\p{Latin}\p{M}]))"#

  /// The words before a clock time that make it a bound, not a start: "sampai",
  /// "sebelum", "setelah". The deadline rules keep such a bound in the title; the
  /// readers decline a time after one as well.
  private static let indonesianBoundWords: Set<String> = [
    "sampai", "hingga", "sebelum", "menjelang", "setelah", "sesudah", "selepas", "usai", "lambatnya",
  ]

  /// Whether the word just before `match` makes its clock time a bound.
  private static func indonesianFollowsBoundWord(_ match: Match) -> Bool {
    wordBefore(match).map { indonesianBoundWords.contains(indonesianKey($0)) } ?? false
  }

  /// The words before a number that name what it counts, so two bare numbers
  /// after "dari" are no range of hours ("dari bab 3 sampai 5").
  private static let indonesianCountedWords: Set<String> = [
    "bab", "halaman", "hal", "hlm", "pasal", "ayat", "nomor", "nomer", "no", "versi", "ruang", "ruangan", "kamar",
    "lantai", "baris", "jalur", "kelas", "kelompok", "grup", "tahap", "langkah", "level", "babak", "set", "skor",
    "nilai", "hasil", "tiket", "slide", "seksi", "bagian", "pelajaran", "latihan", "soal", "gambar", "tabel",
    "lampiran", "tugas", "task", "usia", "umur", "harga", "biaya", "rp", "rupiah", "jumlah", "total", "orang",
    "anak", "buah", "peserta", "kursi", "meja", "tamu",
  ]

  // MARK: - Clock time

  /// "jam 3", "pukul 15.30", "pk. 15:30", "jam tiga", "jam 3 sore", "jam 8
  /// malam", "jam 7 pagi", "jam 12 siang", "jam 12 tengah malam", "7.30 malam",
  /// "3:30 sore", "Makan malam 7:30", "malam ini jam 8". An hour spelled as a
  /// word needs its lead and has no minutes. A time written with no Indonesian
  /// word and no part of the day just before it ("15:30", "3pm") is English's.
  /// Groups: 1 the lead; 2 hour, 3 the colon or the dot, 4 minute, 5 the part of
  /// the day; 6 to 9 an hour with minutes and a part of the day and no lead (6
  /// hour, 7 separator, 8 minute, 9 part); 10 to 12 a time with minutes and
  /// nothing else (10 hour, 11 separator, 12 minute).
  static var indonesianClockPattern: String {
    let part = #"(\#(indonesianPartAfterHour))"#
    let hourOrWord = #"(\d{1,2}|\#(indonesianHourWords))(?:([.:])(\d{2}))?"#
    let digits = #"(\d{1,2})([.:])(\d{2})"#
    let unattached = #"\#(indonesianStart)(?<![\p{N}:.,])(?<![-–—])(?<![-–—]\s)"#
    let leading = #"\#(indonesianStart)(?:pada\s+)?(jam|pukul|pk\.)\s*\#(hourOrWord)\#(part)?\#(indonesianTimeEnd)"#
    let partOnly = #"\#(unattached)\#(digits)\#(part)\#(indonesianTimeEnd)"#
    let minutesOnly = #"\#(unattached)\#(digits)\#(indonesianTimeEnd)"#
    return [leading, partOnly, minutesOnly].joined(separator: "|")
  }

  static func indonesianClock(_ match: Match) -> ClockTime? {
    let hourText: String
    let separator: String?
    let minuteText: String?
    let partText: String?
    let hasLead: Bool
    if let hour = match.group(2) {
      (hourText, separator, minuteText, partText, hasLead) = (hour, match.group(3), match.group(4), match.group(5), true)
    } else if let hour = match.group(6) {
      (hourText, separator, minuteText, partText, hasLead) = (hour, match.group(7), match.group(8), match.group(9), false)
    } else if let hour = match.group(10) {
      (hourText, separator, minuteText, partText, hasLead) = (hour, match.group(11), match.group(12), nil, false)
    } else {
      return nil
    }
    guard let hour = indonesianCount(hourText) else { return nil }
    let isWord = number(hourText) == nil
    // An hour spelled as a word has no minutes after it.
    if isWord, separator != nil { return nil }
    var minute = 0
    if let minuteText {
      guard let value = number(minuteText) else { return nil }
      minute = value
    }
    guard (0...59).contains(minute), (0...23).contains(hour), !indonesianFollowsBoundWord(match) else { return nil }
    if isWord, !(1...12).contains(hour) { return nil }
    if let partText {
      guard let part = indonesianPartOfDay(partText) else { return nil }
      return indonesianTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(hourText)
    if hasLead {
      return indonesianBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    }
    // A time with minutes and no lead reads only after a part of the day
    // ("Makan malam 7:30"); "17:30" alone is English's. A dotted time whose
    // minutes could be a month ("5.10") may be a date.
    guard !hasLeadingZero, let part = indonesianPartBefore(match) else { return nil }
    if separator == ".", minute != 0, minute < 13 { return nil }
    return indonesianTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// "jam 3pm", "pukul 3:30 pm", "pada jam 3 PM": a time with AM or PM after
  /// "jam" or "pukul", which takes its lead with it where English would leave it
  /// behind. A time with AM or PM and no lead is English's. Groups: 1 hour, 2
  /// minute, 3 the "a" or "p".
  static let indonesianMeridiemTimePattern =
    #"\#(indonesianStart)(?:pada\s+)?(?:jam|pukul|pk\.)\s*(\d{1,2})(?:[.:](\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}\p{M}:])"#

  static func indonesianMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased()
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Spoken times

  /// The minutes a spoken time may name after "lewat" or "kurang", as a pattern
  /// without groups: digits, a quarter, and the number words five, ten, fifteen,
  /// twenty, and twenty-five.
  private static let indonesianSpokenMinutes =
    #"(?:\d{1,2}|seperempat|lima\s+belas|dua\s+puluh\s+lima|dua\s+puluh|sepuluh|lima)"#

  /// The minutes a spoken amount names: digits, a quarter, or one of the number
  /// words ``indonesianSpokenMinutes`` allows.
  private static func indonesianMinuteCount(_ text: String) -> Int? {
    if indonesianPhrase(text) == "seperempat" { return 15 }
    return indonesianCount(text)
  }

  /// "jam 3 lewat 15" (3:15), "jam 3 lebih 10 menit" (3:10, "minit" in Malay's
  /// spelling too), "jam 3 kurang 10" (2:50), "pukul tiga kurang seperempat"
  /// (2:45), "setengah empat" (3:30), "jam setengah 4", "setengah empat sore",
  /// each maybe before a part of the day, with the hour in words or digits.
  /// Indonesian counts the half hour toward the next hour, so "setengah empat"
  /// is half an hour before four. The minutes forms need "jam" or "pukul";
  /// "setengah" alone reads when a part of the day follows it or the line goes on
  /// with a word that can follow a time (see ``indonesianFollowsAsDetail(_:)``),
  /// since "setengah empat kilo" is an amount. Groups: 1 the hour and 2 the
  /// amount after "lewat" or "lebih", 3 the amount after "kurang", 4 the part of
  /// the day; 5 the lead of "setengah", 6 its hour, 7 the part of the day.
  static var indonesianSpokenTimePattern: String {
    let amount = indonesianSpokenMinutes
    let hour = #"(\d{1,2}|\#(indonesianHourWords))"#
    let minutes =
      #"\#(indonesianStart)(?:pada\s+)?(?:jam|pukul)\s+\#(hour)\s+(?:(?:lewat|lebih)\s+(\#(amount))|kurang\s+(\#(amount)))(?:\s+(?:menit|minit))?(\#(indonesianPartAfterHour))?\#(indonesianTimeEnd)"#
    let half =
      #"\#(indonesianStart)(?:pada\s+)?((?:jam|pukul)\s+)?setengah\s+\#(hour)(\#(indonesianPartAfterHour))?\#(indonesianTimeEnd)"#
    return "\(minutes)|\(half)"
  }

  static func indonesianSpokenTime(_ match: Match) -> ClockTime? {
    // The hour before `hour` on a clock of 12 hours.
    func before(_ hour: Int) -> Int { hour == 1 ? 12 : hour - 1 }
    let hour: Int
    let minute: Int
    let partText: String?
    let hasLead: Bool
    if let hourText = match.group(1) {
      guard let value = indonesianCount(hourText), (1...12).contains(value) else { return nil }
      if let amount = match.group(2) {
        guard let minutes = indonesianMinuteCount(amount), (1...59).contains(minutes) else { return nil }
        (hour, minute) = (value, minutes)
      } else if let amount = match.group(3) {
        guard let minutes = indonesianMinuteCount(amount), (1...29).contains(minutes) else { return nil }
        (hour, minute) = (before(value), 60 - minutes)
      } else {
        return nil
      }
      (partText, hasLead) = (match.group(4), true)
    } else if let hourText = match.group(6) {
      guard let value = indonesianCount(hourText), (1...12).contains(value) else { return nil }
      (hour, minute) = (before(value), 30)
      (partText, hasLead) = (match.group(7), match.group(5) != nil)
    } else {
      return nil
    }
    guard !indonesianFollowsBoundWord(match) else { return nil }
    if let partText {
      guard let part = indonesianPartOfDay(partText) else { return nil }
      return indonesianTimeWithPart(hour: hour, minute: minute, part: part)
    }
    // "Setengah empat" with no lead and no part of the day may count anything.
    if !hasLead, !indonesianFollowsAsDetail(match) { return nil }
    return indonesianBareTime(hour: hour, minute: minute, hasLeadingZero: false, match: match)
  }

  // MARK: - Noon and midnight

  /// "tengah hari", "siang bolong" (noon), and "tengah malam" (midnight), each
  /// maybe after "pada", "saat", or "tepat". A bound before them ("sampai
  /// tengah malam") is kept in the title by ``indonesianDeadlineClockPattern``.
  /// Groups: 1 noon, 2 midnight.
  static let indonesianNoonOrMidnightPattern =
    #"\#(indonesianStart)(?:(?:pada|saat|tepat)\s+)?(?:(tengah\s+hari|siang\s+bolong)|(tengah\s+malam))\#(indonesianEnd)"#

  static func indonesianNoonOrMidnight(_ match: Match) -> ClockTime? {
    guard !indonesianFollowsBoundWord(match) else { return nil }
    if match.group(1) != nil { return ClockTime(minutes: 12 * 60) }
    return match.group(2) != nil ? ClockTime(minutes: 0, isAfterMidnight: true) : nil
  }

  // MARK: - Time range

  /// The body of the range pattern, with its groups capturing or not. A side is
  /// a time written in digits ("14", "14.30", "14:30"), maybe after "jam" or
  /// "pukul" and before a part of the day.
  private static func indonesianTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let digits = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2})?"#
    let markerWords = #"jam|pukul|pk\."#
    let marker = #"(?:\#(group(markerWords))\s*)?"#
    let part = #"(?:\#(group(indonesianPartAfterHour)))?"#
    let word = #"sampai\s+dengan|sampai|hingga|s/d|s\.d\.|dan"#
    let connector = #"(?:\s+\#(group(word))\s+|\s*\#(group("[-–—]"))\s*)"#
    let opener = #"dari|antara|mulai"#
    return
      #"(?:\#(group(opener))\s+)?\#(marker)\#(group(digits))\#(part)\#(connector)\#(marker)\#(group(digits))\#(part)"#
  }

  /// "jam 3-5 sore", "jam 3 sampai 5 sore", "dari jam 3 sampai jam 5", "dari
  /// jam 14.00 sampai 16.00", "jam 14.00-16.00", "pukul 09.00 - 11.00", "09.00-
  /// 11.00", "antara jam 3 dan 5 sore", "jam 3 s/d 5". Groups: 1 the opener, 2
  /// "jam" or "pukul" before the start, 3 the start, 4 its part of the day, 5
  /// "sampai", "hingga", "s/d", or "dan", 6 a dash, 7 "jam" or "pukul" before the
  /// end, 8 the end, 9 its part of the day.
  static var indonesianTimeRangePattern: String {
    #"\#(indonesianStart)(?:pada\s+)?\#(indonesianTimeRangeBody(capturing: true))\#(indonesianTimeEnd)"#
  }

  /// Whether `text` is a time written with a dot and minutes that no month can
  /// be: "14.00", "09.30", "7.45".
  private static func indonesianIsDottedClock(_ text: String) -> Bool {
    guard let side = text.wholeMatch(of: /(\d{1,2})\.(\d{2})/), let hour = number(side.output.1),
      let minute = number(side.output.2)
    else { return false }
    return (0...23).contains(hour) && (minute == 0 || (13...59).contains(minute))
  }

  static func indonesianTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(3), let endText = match.group(8) else { return nil }
    let lead = match.group(1).map(indonesianPhrase)
    let word = match.group(5).map(indonesianPhrase)
    let hasMarker = match.group(2) != nil || match.group(7) != nil
    let startPart = match.group(4)
    let endPart = match.group(9)
    let hasPart = startPart != nil || endPart != nil
    let hasMinutes = [startText, endText].contains { $0.contains(":") || $0.contains(".") }
    // "Dan" joins the sides only after "antara", which takes no dash and no other
    // joiner.
    if (word == "dan") != (lead == "antara") { return nil }
    if !(hasMarker || hasPart) {
      if lead == nil {
        // "14.00-16.00": two dotted times whose minutes are no month. Colon times
        // are English's, and bare hours are as often numbered items.
        guard indonesianIsDottedClock(startText), indonesianIsDottedClock(endText) else { return nil }
      } else if !hasMinutes {
        // Two bare hours after "dari" are a range only where the line goes on
        // with a word that can follow a time and no word that names an amount or
        // numbered items comes before it ("dari bab 3 sampai 5").
        guard indonesianFollowsAsDetail(match) else { return nil }
        if let before = wordBefore(match), indonesianCountedWords.contains(indonesianKey(before)) { return nil }
        // A start on the 24-hour clock ends at a later hour on it.
        if let first = number(startText), first > 12, let last = number(endText), last <= first { return nil }
      }
    }
    if indonesianFollowsBoundWord(match) { return nil }
    guard
      let start = indonesianRangeSide(startText, part: startPart, hasMarker: hasMarker, hasPart: hasPart, match: match),
      let end = indonesianRangeSide(endText, part: endPart, hasMarker: hasMarker, hasPart: hasPart, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its own part of
  /// the day or none. A side with none takes the reading that fits the other
  /// side ("jam 9 sampai 5 sore" starts at 9:00, "jam 3 sampai 5 sore" at 15:00)
  /// or the part the line names elsewhere. Dotted minutes that are a month
  /// ("5.10") make a date, not a time, unless "jam" or a part of the day on
  /// either side says it is a time.
  private static func indonesianRangeSide(
    _ text: String, part: String?, hasMarker: Bool, hasPart: Bool, match: Match
  ) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    let kind = part.flatMap(indonesianPartOfDay)
    if side.output.2 == ".", (1...12).contains(minute), !hasMarker, !hasPart { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    if let kind { return indonesianTimeWithPart(hour: hour, minute: minute, part: kind) }
    return indonesianBareTime(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time as a pattern without groups: "jam 17", "pukul 17.30", "jam 5
  /// sore", "jam tiga", "jam 3 lewat 15", "setengah lima", "5 sore", "5pm",
  /// "17:30", a dotted time whose minutes cannot be a month ("17.00"), and
  /// "tengah malam".
  private static var indonesianClockShape: String {
    let hourWords = indonesianHourWords
    let amount = indonesianSpokenMinutes
    let digits = #"\d{1,2}(?:[.:]\d{2})?"#
    let leadHour =
      #"(?:jam|pukul|pk\.)\s*(?:\#(digits)|\#(hourWords))(?:\#(indonesianPartAfterHour))?(?:\s+(?:lewat|lebih|kurang)\s+\#(amount)(?:\s+(?:menit|minit))?)?(?:\s*[ap]\.?m\.?)?"#
    let half = #"(?:(?:jam|pukul)\s+)?setengah\s+(?:\d{1,2}|\#(hourWords))(?:\#(indonesianPartAfterHour))?"#
    let withPart = #"\#(digits)\#(indonesianPartAfterHour)"#
    let meridiem = #"\d{1,2}(?:[.:]\d{2})?\s*[ap]\.?m\.?"#
    let colon = #"\d{1,2}:\d{2}"#
    let dotted = #"\d{1,2}\.(?:00|1[3-9]|[2-5]\d)"#
    let named = #"tengah\s+(?:malam|hari)|siang\s+bolong"#
    return "(?:\(leadHour)|\(half)|\(withPart)|\(meridiem)|\(colon)|\(dotted)|\(named))"
  }

  /// The words that make a clock time a bound or a deadline, as a pattern
  /// without groups, with the colon or the space and the "pada" after them.
  private static let indonesianClockBound =
    #"(?:paling\s+(?:lambat|telat|cepat|awal|akhir)|selambat[\s-]?lambatnya|selambatnya|sebelum|sampai(?:\s+dengan)?|hingga|menjelang|setelah|sesudah|selepas|usai|tenggat(?:\s+waktu)?|batas\s+(?:waktu|akhir)|deadline|jatuh\s+tempo|maksimal|maks\.?|minimal)(?:\s*:\s*|\s+)(?:pada\s+)?"#

  /// A clock time written as a bound ("sebelum jam 17", "sampai pukul 17.00",
  /// "paling lambat jam 5 sore", "setelah jam 18", "menjelang tengah malam",
  /// "deadline jam 5"), which names no start time. Group 1 is the bound, or nil
  /// for a range ("dari jam 14 sampai jam 17.30"), which the range rule reads and
  /// this rule only steps over, so the "sampai jam 17.30" inside it is not taken
  /// for a bound.
  static var indonesianDeadlineClockPattern: String {
    #"\#(indonesianStart)(?:\#(indonesianTimeRangeBody(capturing: false))|(\#(indonesianClockBound)\#(indonesianClockShape)))\#(indonesianTimeEnd)"#
  }

  /// The clock after a deadline day ("sebelum Jumat jam 17", "paling lambat
  /// besok pukul 9.00"), which is a deadline's clock and stays in the title with
  /// the rest of the line once the day is read as the due day.
  static var indonesianDueClockPattern: String {
    #"\#(indonesianStart)(?:(?:pada|di)\s+)?\#(indonesianClockShape)\#(indonesianTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a
  /// word that introduces a due day, the day, with a comma or a space before the
  /// clock.
  private static var indonesianAfterDueDayPattern: String {
    #"(?:^|\s)\#(indonesianDueLead)(?:\#(indonesianDueDay))\s*,?\s*$"#
  }

  /// The text before a clock that ends a range of days or of weekdays ("dari 3
  /// sampai 5 Oktober jam 9", "dari Senin sampai Rabu jam 9"), whose "sampai"
  /// and day are no deadline.
  private static var indonesianAfterRangePattern: String {
    #"(?:\#(indonesianDateRangePattern)|\#(indonesianWeekdayRangePattern))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a deadline word and a day
  /// ("sebelum Jumat", "paling lambat besok"). The "sampai" of a range of days is
  /// no deadline word, so the clock after "dari Senin sampai Rabu" is the range's
  /// time.
  static func indonesianIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = indonesianTextBefore(match)
    let whole = NSRange(before.startIndex..., in: before)
    if let range = LorvexCapturePatterns.regex(indonesianAfterRangePattern),
      range.firstMatch(in: before, range: whole) != nil
    {
      return false
    }
    guard let regex = LorvexCapturePatterns.regex(indonesianAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: whole) != nil
  }
}
