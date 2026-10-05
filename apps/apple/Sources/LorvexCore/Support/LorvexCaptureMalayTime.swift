import Foundation

extension LorvexCaptureVocabulary {
  // The Malay clock-time rules: a time with "pukul" or "jam" ("pukul 3", "jam
  // 15.30"), with a part of the day ("pukul 8 malam", "8 malam", "7.30 malam"),
  // with PG or PTG ("9.30 PG"), the half hour ("pukul tiga setengah"), a range
  // of times, midnight, and the rules that keep a deadline written as a clock
  // time, or a quarter hour, in the title. The vocabulary's other words are in
  // ``malay``.

  // MARK: - Parts of the day

  /// A part of the day a clock time may be written with.
  private enum MalayPart {
    /// "subuh" and "dini hari": the hours before sunrise, 1 to 6.
    case dawn
    /// "pagi": 1 to 11 in the morning.
    case morning
    /// "tengah hari": noon and the early afternoon, 12 to 4.
    case midday
    /// "petang": the afternoon and the evening, 1 to 11 counted from noon.
    case afternoon
    /// "malam": the evening and the night, up to the small hours after midnight.
    case night
    /// "tengah malam": 12 at night.
    case midnight
    /// "PG" (pagi), the 12-hour clock's AM.
    case am
    /// "PTG" (petang), the 12-hour clock's PM.
    case pm
  }

  /// The words that name a part of the day after an hour, as a pattern without
  /// groups: "pagi", "petang", "malam" (each maybe with "ini" or "nanti" after
  /// it), "tengah hari", "tengah malam", "dini hari", "subuh", each with the
  /// space before it and maybe after "nanti" ("pukul 8 nanti malam"); and the
  /// abbreviations "pg" and "ptg", which may follow the time directly ("9.30pg").
  private static let malayPartAfterHour =
    #"(?:\s+(?:nanti\s+)?(?:tengah\s?malam|\#(malayMiddayWord)|dini\s?hari|subuh|(?:pagi|petang|malam)(?:\s+(?:ini|nanti))?)|\s*(?:pg|ptg)(?![\p{Latin}\p{N}\p{M}]))"#

  /// The part of the day a matched word or phrase names: "malam ini", "dini
  /// hari", "tengah malam", "tengahari", "ptg".
  private static func malayPartOfDay(_ text: String) -> MalayPart? {
    let key = malayPhrase(text).replacingOccurrences(of: "tengahari", with: "tengah hari")
      .replacingOccurrences(of: "tengahmalam", with: "tengah malam").replacingOccurrences(of: "dinihari", with: "dini hari")
    let words = key.split(separator: " ").map(String.init)
    if let tengah = words.firstIndex(of: "tengah"), tengah + 1 < words.count {
      if words[tengah + 1] == "malam" { return .midnight }
      if words[tengah + 1] == "hari" { return .midday }
    }
    if words.contains("subuh") || words.contains("dini") { return .dawn }
    if words.contains("pg") { return .am }
    if words.contains("ptg") { return .pm }
    if words.contains("pagi") { return .morning }
    if words.contains("petang") { return .afternoon }
    if words.contains("malam") { return .night }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it: "7 pagi" is 07:00, "12 tengah hari" noon, "1
  /// tengah hari" 13:00, "3 petang" 15:00, "8 malam" 20:00, "2 dini hari" 02:00,
  /// "9.30 PG" 09:30, "12.30 PG" 00:30, "3.30 PTG" 15:30, and "12 malam" or "1
  /// malam" the midnight and the small hours that end the named day, on the next
  /// day. An hour on the 24-hour clock (13 to 23) is read as written when its part
  /// of the day is one it falls in: the midday is 13 to 16, the afternoon 13 to
  /// 19, and the night 18 to 23.
  private static func malayTimeWithPart(hour: Int, minute: Int, part: MalayPart) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    switch part {
    case .dawn:
      return (1...6).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .morning:
      return (1...11).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .midday:
      if hour == 12 || (13...16).contains(hour) { return ClockTime(minutes: hour * 60 + minute) }
      return (1...4).contains(hour) ? ClockTime(minutes: (hour + 12) * 60 + minute) : nil
    case .afternoon:
      if (1...11).contains(hour) { return ClockTime(minutes: (hour + 12) * 60 + minute) }
      return (13...19).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil
    case .night:
      if (13...23).contains(hour) { return (18...23).contains(hour) ? ClockTime(minutes: hour * 60 + minute) : nil }
      return nightTime(hour: hour, minute: minute)
    case .midnight:
      return [0, 12].contains(hour) ? ClockTime(minutes: minute, isAfterMidnight: true) : nil
    case .am:
      return (1...12).contains(hour) ? ClockTime(minutes: (hour % 12) * 60 + minute) : nil
    case .pm:
      return (1...12).contains(hour) ? ClockTime(minutes: (hour % 12 + 12) * 60 + minute) : nil
    }
  }

  /// The part of the day written just before `match` with nothing between:
  /// "malam pukul 8", "esok malam pukul 8", "malam ini pukul 8", "Jumaat petang
  /// pukul 4".
  private static let malayPartBeforePattern =
    #"(?:^|\s)(?:nanti\s+)?(pagi|\#(malayMiddayWord)|petang|malam|subuh|dini\s?hari)(?:\s+(?:ini|nanti|esok|besok))?\s*[,:]?\s*$"#

  /// A meal, a prayer, or the fast that names the part of the day it falls in:
  /// "makan malam", "makan tengah hari", "sarapan", "zohor", "maghrib", "isyak",
  /// "berbuka puasa". Groups: 1 the part after "makan", 2 after "santap", 3 after
  /// "minum", 4 a word that names a part by itself.
  private static let malayHabitPartPattern =
    #"\#(malayStart)(?:makan\s+(malam|\#(malayMiddayWord)|pagi|petang)|santap\s+(malam|\#(malayMiddayWord)|pagi)|minum\s+(pagi|petang)|(sarapan|sahur|bersahur|subuh|zohor|zuhur|asar|maghrib|isyak|isya|berbuka(?:\s+puasa)?|iftar))\#(malayEnd)"#

  /// The part of the day a meal, a prayer, or the fast written in
  /// ``malayHabitPartPattern`` names.
  private static func malayHabitPart(_ word: String) -> MalayPart? {
    switch malayPhrase(word) {
    case "sarapan": return .morning
    case "sahur", "bersahur", "subuh": return .dawn
    case "zohor", "zuhur": return .midday
    case "asar": return .afternoon
    case "maghrib", "isyak", "isya", "berbuka", "berbuka puasa", "iftar": return .night
    default: return malayPartOfDay(word)
    }
  }

  /// The part of the day written directly before `match`.
  private static func malayPartBefore(_ match: Match) -> MalayPart? {
    let before = malayTextBefore(match)
    guard let regex = LorvexCapturePatterns.regex(malayPartBeforePattern),
      let found = regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)),
      let range = Range(found.range(at: 1), in: before)
    else { return nil }
    return malayPartOfDay(String(before[range]))
  }

  /// The parts of the day the meals, prayers, and fasts in `text` name.
  private static func malayHabitParts(in text: String) -> [MalayPart] {
    guard let regex = LorvexCapturePatterns.regex(malayHabitPartPattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { found in
      for group in 1...4 {
        if let range = Range(found.range(at: group), in: text) { return malayHabitPart(String(text[range])) }
      }
      return nil
    }
  }

  /// The part of the day the line names beside `match` for an hour written
  /// without one: the part written directly before it ("malam pukul 8", "esok
  /// malam pukul 8"), or a meal, a prayer, or the fast in the same clause ("makan
  /// malam dengan keluarga pukul 8", "pukul 7 berbuka puasa"). Nil when the line
  /// names no part there, or names two that differ.
  private static func malayLinePart(beside match: Match) -> MalayPart? {
    let separators = CharacterSet(charactersIn: ".;!?,\n")
    var parts: [MalayPart] = []
    if let adjacent = malayPartBefore(match) { parts.append(adjacent) }
    let before = malayTextBefore(match).components(separatedBy: separators).last ?? ""
    let after = malayTextAfter(match).components(separatedBy: separators).first ?? ""
    parts += malayHabitParts(in: before) + malayHabitParts(in: after)
    guard let first = parts.first, parts.allSatisfy({ $0 == first }) else { return nil }
    return first
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part
  /// of the day of its own) names: its line's part of the day when the line names
  /// one and the hour is on the clock of 12 hours, else the hour as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func malayBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    if !hasLeadingZero, (1...12).contains(hour), let part = malayLinePart(beside: match),
      let time = malayTimeWithPart(hour: hour, minute: minute, part: part)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, or colon (the
  /// word or the number goes on), no letter joined by a hyphen, no decimal
  /// fraction, no percent or currency sign with or without a space before it, no
  /// dash before a digit, which makes the time one side of a range written with a
  /// dash, no AM or PM, which English reads, and none of the Indonesian words for
  /// the afternoon, which the Indonesian rules read with the time.
  private static let malayTimeEnd =
    #"(?![\p{Latin}\p{N}\p{M}:]|[-–]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d|\s*[ap]\.?m\.?(?![\p{Latin}\p{M}]))\#(malayNotIndonesianPart)"#

  /// The word "tepat" ("sharp") after a clock time, which goes with the time:
  /// "pukul 3 tepat".
  private static let malaySharp = #"(?:\s+tepat\#(malayEnd))?"#

  /// What may not come right before an hour that has a part of the day and no
  /// "pukul" or "jam": a word that makes the number a count of nights ("tinggal 3
  /// malam", "hotel 2 malam"), and a count of days ("pakej 3 hari 2 malam").
  private static let malayNotNights =
    #"(?<!(?:selama|bermalam|menginap|penginapan|inap|hotel|homestay|chalet|resort|pakej|percutian|khemah|tinggal|sewa)\s{1,3})(?<!\d\s{1,3}hari\s{1,3})"#

  /// The words before a clock time that make it a bound, not a start: "sampai",
  /// "sebelum", "selepas". The deadline rules keep such a bound in the title; the
  /// readers decline a time after one as well.
  private static let malayBoundWords: Set<String> = [
    "sampai", "hingga", "sehingga", "sebelum", "menjelang", "selepas", "lepas", "setelah", "sesudah", "usai",
    "lewatnya", "lambatnya",
  ]

  /// Whether the word just before `match` makes its clock time a bound.
  private static func malayFollowsBoundWord(_ match: Match) -> Bool {
    wordBefore(match).map { malayBoundWords.contains(malayKey($0)) } ?? false
  }

  /// The words before a number that name what it counts, so two bare numbers
  /// after "dari" are no range of hours ("dari bab 3 hingga 5").
  private static let malayCountedWords: Set<String> = [
    "bab", "halaman", "hlm", "surat", "perenggan", "fasal", "ayat", "nombor", "no", "bil", "versi", "bilik", "dewan",
    "tingkat", "aras", "lot", "blok", "kelas", "kumpulan", "langkah", "peringkat", "tahap", "set", "skor", "markah",
    "keputusan", "tiket", "slaid", "bahagian", "seksyen", "soalan", "gambar", "rajah", "jadual", "lampiran", "tugasan",
    "tugas", "task", "umur", "usia", "harga", "kos", "rm", "ringgit", "jumlah", "orang", "anak", "biji", "buah",
    "peserta", "kerusi", "meja", "tetamu",
  ]

  /// Whether the text after `match` goes on with the minutes of a spoken time
  /// ("pukul 4 kurang 10", "pukul 3 lewat 15", "pukul 4 kurang seperempat"). Malay
  /// leaves such a time in the title, and Indonesian, which reads it, can.
  private static func malayFollowsSpokenMinutes(_ match: Match) -> Bool {
    malayFinds(
      #"^\s+(?:kurang|lewat|lebih)\s+(?:\d|suku|seperempat|\#(malayNumberWords)(?![\p{Latin}\p{M}]))"#,
      in: malayTextAfter(match))
  }

  // MARK: - Clock time

  /// "pukul 3", "jam 3", "pkl. 15.30", "pukul tiga", "pukul 3 petang", "jam 8
  /// malam", "pukul 7 pagi", "pukul 12 tengah hari", "jam 12 tengah malam", "pukul
  /// 3 tepat", "pukul 9.30 PG", "8 malam", "7 pagi", "3.30 petang", "7.30 malam",
  /// "9.30 PG", "3:30 PTG", "Makan malam 7:30", "malam ini pukul 8". An hour
  /// spelled as a word needs its lead and has no minutes. A time written with no
  /// Malay word and no part of the day just before it ("15:30", "3pm") is
  /// English's. Groups: 1 the lead; 2 hour, 3 the colon or the dot, 4 minute, 5
  /// the part of the day; 6 to 9 an hour with a part of the day and no lead (6
  /// hour, 7 separator, 8 minute, 9 part); 10 to 12 a time with minutes and
  /// nothing else (10 hour, 11 separator, 12 minute).
  static var malayClockPattern: String {
    let part = #"(\#(malayPartAfterHour))"#
    let hourOrWord = #"(\d{1,2}|\#(malayHourWords))(?:([.:])(\d{2}))?"#
    let unattached = #"\#(malayStart)(?<![\p{N}:.,])(?<![-–—])(?<![-–—]\s)\#(malayNotNights)"#
    let leading =
      #"\#(malayStart)(?:pada\s+)?(?:tepat\s+)?(jam|pukul|pkl\.?|pk\.)\s*\#(hourOrWord)\#(part)?\#(malayTimeEnd)\#(malaySharp)"#
    let partOnly = #"\#(unattached)(\d{1,2})(?:([.:])(\d{2}))?\#(part)\#(malayTimeEnd)\#(malaySharp)"#
    let minutesOnly = #"\#(unattached)(\d{1,2})([.:])(\d{2})\#(malayTimeEnd)"#
    return [leading, partOnly, minutesOnly].joined(separator: "|")
  }

  /// Whether `hour` with `part` and no lead, no minutes ("8 malam") may be read
  /// as a time: a bare hour is a count as often as a clock ("2 malam" is two
  /// nights), so a night counts from 6 o'clock, and PG and PTG ("5 pg" is five
  /// pages) need minutes or a lead.
  private static func malayBareHourReads(hour: Int, part: MalayPart) -> Bool {
    guard (1...12).contains(hour) else { return false }
    switch part {
    case .am, .pm: return false
    case .night: return hour >= 6
    default: return true
    }
  }

  static func malayClock(_ match: Match) -> ClockTime? {
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
    guard let hour = malayCount(hourText) else { return nil }
    let isWord = number(hourText) == nil
    // An hour spelled as a word has no minutes after it.
    if isWord, separator != nil { return nil }
    var minute = 0
    if let minuteText {
      guard let value = number(minuteText) else { return nil }
      minute = value
    }
    guard (0...59).contains(minute), (0...23).contains(hour), !malayFollowsBoundWord(match),
      !malayFollowsSpokenMinutes(match)
    else { return nil }
    if isWord, !(1...12).contains(hour) { return nil }
    if let partText {
      guard let part = malayPartOfDay(partText) else { return nil }
      if !hasLead, minuteText == nil, !malayBareHourReads(hour: hour, part: part) { return nil }
      return malayTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(hourText)
    if hasLead {
      return malayBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    }
    // A time with minutes and no lead reads only after a part of the day ("Makan
    // malam 7:30"); "17:30" alone is English's. A dotted time whose minutes could
    // be a month ("5.10") may be a date.
    guard !hasLeadingZero, let part = malayPartBefore(match) else { return nil }
    if separator == ".", minute != 0, minute < 13 { return nil }
    return malayTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// "pukul tiga setengah", "jam 3 setengah petang", "pukul 12 setengah": the
  /// half hour written after the hour, as Malaysian Malay says it ("lapan
  /// setengah" is 8:30, where Indonesian says "setengah sembilan"). It needs
  /// "pukul" or "jam", since "tiga setengah" alone is three and a half of
  /// something, and may be followed by a part of the day. Groups: 1 the hour, 2 the
  /// part of the day.
  static var malayHalfPastPattern: String {
    let hour = #"(\d{1,2}|\#(malayHourWords))"#
    return
      #"\#(malayStart)(?:pada\s+)?(?:tepat\s+)?(?:jam|pukul|pkl\.?|pk\.)\s*\#(hour)\s+setengah(?!\s+(?:jam|minit|hari|minggu|bulan|tahun|kali|juta|ribu|ratus|peratus|kilo|\d))(\#(malayPartAfterHour))?\#(malayTimeEnd)\#(malaySharp)"#
  }

  static func malayHalfPast(_ match: Match) -> ClockTime? {
    guard let hourText = match.group(1), let hour = malayCount(hourText), (1...12).contains(hour),
      !malayFollowsBoundWord(match)
    else { return nil }
    if let partText = match.group(2) {
      guard let part = malayPartOfDay(partText) else { return nil }
      return malayTimeWithPart(hour: hour, minute: 30, part: part)
    }
    return malayBareTime(hour: hour, minute: 30, hasLeadingZero: false, match: match)
  }

  /// "pukul 3pm", "jam 3:30 pm", "pada pukul 3 PM": a time with AM or PM after
  /// "pukul" or "jam", which takes its lead with it where English would leave it
  /// behind. A time with AM or PM and no lead is English's. Groups: 1 hour, 2
  /// minute, 3 the "a" or "p".
  static let malayMeridiemTimePattern =
    #"\#(malayStart)(?:pada\s+)?(?:jam|pukul|pkl\.?|pk\.)\s*(\d{1,2})(?:[.:](\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}\p{M}:])"#

  static func malayMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased()
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Midnight

  /// "tengah malam" (midnight), maybe after "pada", "saat", or "tepat". Noon has
  /// no standalone rule: "tengah hari" is also the word for lunch ("makan tengah
  /// hari") and for a stretch of the early afternoon, so it names a time only
  /// after an hour ("pukul 12 tengah hari"). A bound before midnight ("sampai
  /// tengah malam") is kept in the title by ``malayDeadlineClockPattern``, and a
  /// past one ("tengah malam tadi") is no time.
  static let malayMidnightPattern =
    #"\#(malayStart)(?:(?:pada|saat|tepat)\s+)?tengah\s?malam\#(malayEnd)(?!\s+(?:tadi|semalam|kelmarin))"#

  static func malayMidnight(_ match: Match) -> ClockTime? {
    malayFollowsBoundWord(match) ? nil : ClockTime(minutes: 0, isAfterMidnight: true)
  }

  // MARK: - Time range

  /// The body of the range pattern, with its groups capturing or not. A side is a
  /// time written in digits ("14", "14.30", "14:30"), maybe after "pukul" or
  /// "jam" and before a part of the day.
  private static func malayTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let digits = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2})?"#
    let markerWords = #"jam|pukul|pkl\.?|pk\."#
    let marker = #"(?:\#(group(markerWords))\s*)?"#
    let part = #"(?:\#(group(malayPartAfterHour)))?"#
    let word = #"hingga|sehingga|sampai|dan"#
    let connector = #"(?:\s+\#(group(word))\s+|\s*\#(group("[-–—]"))\s*)"#
    let opener = #"dari|antara|mulai"#
    return
      #"(?:\#(group(opener))\s+)?\#(marker)\#(group(digits))\#(part)\#(connector)\#(marker)\#(group(digits))\#(part)"#
  }

  /// "pukul 3-5 petang", "pukul 3 hingga 5 petang", "dari pukul 3 hingga pukul 5",
  /// "dari jam 14.00 sehingga 16.00", "9.00 pagi hingga 5.00 petang", "jam
  /// 14.00-16.00", "09.00-11.00", "antara pukul 3 dan 5 petang". Groups: 1 the
  /// opener, 2 "pukul" or "jam" before the start, 3 the start, 4 its part of the
  /// day, 5 "hingga", "sehingga", "sampai", or "dan", 6 a dash, 7 "pukul" or "jam"
  /// before the end, 8 the end, 9 its part of the day.
  static var malayTimeRangePattern: String {
    #"\#(malayStart)(?:pada\s+)?\#(malayTimeRangeBody(capturing: true))\#(malayTimeEnd)"#
  }

  /// Whether `text` is a time written with a dot and minutes that no month can be:
  /// "14.00", "09.30", "7.45".
  private static func malayIsDottedClock(_ text: String) -> Bool {
    guard let side = text.wholeMatch(of: /(\d{1,2})\.(\d{2})/), let hour = number(side.output.1),
      let minute = number(side.output.2)
    else { return false }
    return (0...23).contains(hour) && (minute == 0 || (13...59).contains(minute))
  }

  static func malayTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(3), let endText = match.group(8) else { return nil }
    let lead = match.group(1).map(malayPhrase)
    let word = match.group(5).map(malayPhrase)
    let hasMarker = match.group(2) != nil || match.group(7) != nil
    let startPart = match.group(4)
    let endPart = match.group(9)
    let hasPart = startPart != nil || endPart != nil
    let hasMinutes = [startText, endText].contains { $0.contains(":") || $0.contains(".") }
    // "Dan" joins the sides only after "antara", which takes no dash and no other
    // joiner.
    if (word == "dan") != (lead == "antara") { return nil }
    // PG and PTG on a side with no minutes and no marker ("5 pg") may be pages.
    for (text, part) in [(startText, startPart), (endText, endPart)] {
      if let kind = part.flatMap(malayPartOfDay), kind == .am || kind == .pm, !hasMarker,
        !(text.contains(":") || text.contains("."))
      {
        return nil
      }
    }
    if !(hasMarker || hasPart) {
      if lead == nil {
        // "14.00-16.00": two dotted times whose minutes are no month. Colon times
        // are English's, and bare hours are as often numbered items.
        guard malayIsDottedClock(startText), malayIsDottedClock(endText) else { return nil }
      } else if !hasMinutes {
        // Two bare hours after "dari" are a range only where the line goes on with
        // a word that can follow a time and no word that names an amount or
        // numbered items comes before it ("dari bab 3 hingga 5").
        guard malayFollowsAsDetail(match) else { return nil }
        if let before = wordBefore(match), malayCountedWords.contains(malayKey(before)) { return nil }
        // A start on the 24-hour clock ends at a later hour on it.
        if let first = number(startText), first > 12, let last = number(endText), last <= first { return nil }
      }
    }
    if malayFollowsBoundWord(match) { return nil }
    guard
      let start = malayRangeSide(startText, part: startPart, hasMarker: hasMarker, hasPart: hasPart, match: match),
      let end = malayRangeSide(endText, part: endPart, hasMarker: hasMarker, hasPart: hasPart, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its own part of
  /// the day or none. A side with no part is bare, and the range reads it against
  /// the other side ("9 hingga 5 petang" starts at 9:00, "3-5 petang" at 15:00).
  /// Dotted minutes that are a month ("5.10") make a date, not a time, unless
  /// "pukul" or a part of the day says it is a time.
  private static func malayRangeSide(
    _ text: String, part: String?, hasMarker: Bool, hasPart: Bool, match: Match
  ) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    if side.output.2 == ".", (1...12).contains(minute), !hasMarker, !hasPart { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    if let kind = part.flatMap(malayPartOfDay) { return malayTimeWithPart(hour: hour, minute: minute, part: kind) }
    return malayBareTime(hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time as a pattern without groups: "pukul 17", "jam 17.30", "pukul 5
  /// petang", "pukul tiga", "pukul tiga setengah", "5 petang", "5pm", "17:30", a
  /// dotted time whose minutes cannot be a month ("17.00"), and "tengah malam".
  private static var malayClockShape: String {
    let hourWords = malayHourWords
    let digits = #"\d{1,2}(?:[.:]\d{2})?"#
    let leadHour =
      #"(?:jam|pukul|pkl\.?|pk\.)\s*(?:\#(digits)|\#(hourWords))(?:\s+setengah)?(?:\#(malayPartAfterHour))?(?:\s*[ap]\.?m\.?)?"#
    let withPart = #"\#(digits)\#(malayPartAfterHour)"#
    let meridiem = #"\d{1,2}(?:[.:]\d{2})?\s*[ap]\.?m\.?"#
    let colon = #"\d{1,2}:\d{2}"#
    let dotted = #"\d{1,2}\.(?:00|1[3-9]|[2-5]\d)"#
    let named = #"tengah\s?malam|\#(malayMiddayWord)"#
    return "(?:\(leadHour)|\(withPart)|\(meridiem)|\(colon)|\(dotted)|\(named))"
  }

  /// The words that make a clock time a bound or a deadline, as a pattern without
  /// groups, with the colon or the space and the "pada" after them.
  private static let malayClockBound =
    #"(?:paling\s+(?:lewat|lambat|awal|cepat)|selewat[\s-]?lewatnya|selambat[\s-]?lambatnya|sebelum|sehingga|hingga|sampai|menjelang|selepas|lepas|setelah|sesudah|usai|tarikh\s+(?:akhir|tamat|tutup|jangka)|had\s+masa|deadline|maksimum|minimum)(?:\s*:\s*|\s+)(?:pada\s+)?"#

  /// A clock time written as a bound ("sebelum pukul 17", "hingga jam 17.00",
  /// "paling lewat pukul 5 petang", "selepas pukul 18", "menjelang tengah malam",
  /// "deadline pukul 5"), which names no start time. Group 1 is the bound, or nil
  /// for a range ("dari pukul 14 hingga pukul 17.30"), which the range rule reads
  /// and this rule only steps over, so the "hingga pukul 17.30" inside it is not
  /// taken for a bound.
  static var malayDeadlineClockPattern: String {
    #"\#(malayStart)(?:\#(malayTimeRangeBody(capturing: false))|(\#(malayClockBound)\#(malayClockShape)))\#(malayTimeEnd)"#
  }

  /// The clock after a deadline day ("sebelum Jumaat pukul 17", "paling lewat esok
  /// pukul 9.00"), which is a deadline's clock and stays in the title with the
  /// rest of the line once the day is read as the due day.
  static var malayDueClockPattern: String {
    #"\#(malayStart)(?:(?:pada|di)\s+)?\#(malayClockShape)\#(malayTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a word
  /// that introduces a due day, the day, with a comma or a space before the clock.
  private static var malayAfterDueDayPattern: String {
    #"(?:^|\s)\#(malayDueLead)(?:\#(malayDueDay))\s*,?\s*$"#
  }

  /// The text before a clock that ends a range of days or of weekdays ("dari 3
  /// hingga 5 Oktober pukul 9", "dari Isnin hingga Rabu pukul 9"), whose "hingga"
  /// and day are no deadline.
  private static var malayAfterRangePattern: String {
    #"(?:\#(malayDateRangePattern)|\#(malayWeekdayRangePattern))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a deadline word and a day
  /// ("sebelum Jumaat", "paling lewat esok"). The "hingga" of a range of days is no
  /// deadline word, so the clock after "dari Isnin hingga Rabu" is the range's
  /// time.
  static func malayIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = malayTextBefore(match)
    let whole = NSRange(before.startIndex..., in: before)
    if let range = LorvexCapturePatterns.regex(malayAfterRangePattern), range.firstMatch(in: before, range: whole) != nil
    {
      return false
    }
    guard let regex = LorvexCapturePatterns.regex(malayAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: whole) != nil
  }

  // MARK: - Quarter hours

  /// "pukul tiga suku", "pukul 3 tiga suku", "pukul empat kurang suku", "suku
  /// kurang lima": a quarter written after the hour. Malay speakers say it both
  /// ways ("pukul tiga suku" is 3:15 in some books and 2:45 in others), so the
  /// whole phrase stays in the title and no rule reads its hour as a time. "Suku
  /// jam" is a length and is no quarter of the clock.
  static let malayQuarterClockPattern: String = {
    let hour = #"(?:\d{1,2}|\#(malayHourWords))"#
    let lead = #"(?:jam|pukul|pkl\.?|pk\.)\s*\#(hour)\s+(?:kurang\s+suku|(?:tiga\s+)?suku(?!\s+jam(?![\p{Latin}\p{M}])))"#
    let before = #"suku\s+kurang\s+\#(hour)"#
    return #"\#(malayStart)(?:\#(lead)|\#(before))(?:\#(malayPartAfterHour))?\#(malayEnd)"#
  }()
}
