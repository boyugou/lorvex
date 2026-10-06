import Foundation

extension LorvexCaptureVocabulary {
  // The Turkish clock-time rules: a time with "saat" or a case ending ("saat 15:00",
  // "15:30'da"), with a part of the day before it ("akşam 8"), the spoken
  // forms ("üç buçuk", "üçü çeyrek geçe", "dörde çeyrek var"), a range of
  // times, midnight, and the rules that keep a deadline written as a clock
  // time in the title. The vocabulary's other words are in ``turkish``.

  // MARK: - Hours spelled as words

  /// The hours one to twelve as Turkish spells them in the forms a clock phrase
  /// takes, as the reading form leaves them: the plain number ("saat üç"), the
  /// locative ("üçte"), the accusative of "üçü çeyrek geçe", the dative of
  /// "dörde çeyrek var", and the ablative of "beşten önce".
  private static let turkishHourForms:
    [(value: Int, plain: String, locative: String, accusative: String, dative: String, ablative: String)] = [
      (1, "bir", "birde", "biri", "bire", "birden"),
      (2, "iki", "ikide", "ikiyi", "ikiye", "ikiden"),
      (3, "uc", "ucte", "ucu", "uce", "ucten"),
      (4, "dort", "dortte", "dordu", "dorde", "dorten"),
      (5, "bes", "beste", "besi", "bese", "besten"),
      (6, "alti", "altida", "altiyi", "altiya", "altidan"),
      (7, "yedi", "yedide", "yediyi", "yediye", "yediden"),
      (8, "sekiz", "sekizde", "sekizi", "sekize", "sekizden"),
      (9, "dokuz", "dokuzda", "dokuzu", "dokuza", "dokuzdan"),
      (10, "on", "onda", "onu", "ona", "ondan"),
      (11, "on bir", "on birde", "on biri", "on bire", "on birden"),
      (12, "on iki", "on ikide", "on ikiyi", "on ikiye", "on ikiden"),
    ]

  /// `forms` as the alternatives of a pattern without groups, longest first, with
  /// a space between the words of a compound.
  private static func turkishHourAlternatives(_ forms: [String]) -> String {
    alternation(of: forms).replacingOccurrences(of: " ", with: #"\s+"#)
  }

  /// The plain and the locative forms ("üç", "üçte"), as a pattern without groups.
  private static var turkishHourWordsPlainOrLocative: String {
    turkishHourAlternatives(turkishHourForms.flatMap { [$0.plain, $0.locative] })
  }

  private static var turkishHourWordsPlain: String {
    turkishHourAlternatives(turkishHourForms.map(\.plain))
  }

  private static var turkishHourWordsAccusative: String {
    turkishHourAlternatives(turkishHourForms.map(\.accusative))
  }

  private static var turkishHourWordsDative: String {
    turkishHourAlternatives(turkishHourForms.map(\.dative))
  }

  /// Every form of every hour, as a pattern without groups.
  private static var turkishHourWordsAny: String {
    turkishHourAlternatives(turkishHourForms.flatMap { [$0.plain, $0.locative, $0.accusative, $0.dative, $0.ablative] })
  }

  /// The hour a matched text names: digits, maybe with a case ending after
  /// them ("3'ü"), or an hour word in any of its forms.
  private static func turkishHourNumber(_ text: String) -> Int? {
    if let digits = text.firstMatch(of: /^\d{1,2}/) { return number(digits.output) }
    let key = turkishPhrase(text)
    return turkishHourForms.first {
      [$0.plain, $0.locative, $0.accusative, $0.dative, $0.ablative].contains(key)
    }?.value
  }

  // MARK: - Parts of the day

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The 12-hour hours follow
  /// ``partOfDayTime(hour:minute:part:)``: "sabah 9" is 09:00, "öğlen 12" noon,
  /// "öğleden sonra 3" 15:00, "akşam 8" 20:00, and "gece 2" the small hours
  /// after midnight, on the next day. An hour on the 24-hour clock (13 to 23)
  /// is read as written when its part of the day is one it falls in: the
  /// afternoon is 13 to 18, the evening 16 to 23, and the night 18 to 23.
  private static func turkishTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    if (13...23).contains(hour) {
      let hours: ClosedRange<Int>? =
        switch part {
        case .morning: nil
        case .day: 13...18
        case .evening: 16...23
        case .night: 18...23
        }
      return hours?.contains(hour) == true ? ClockTime(minutes: hour * 60 + minute) : nil
    }
    return partOfDayTime(hour: hour, minute: minute, part: part)
  }

  /// A part of the day beside a day word anywhere in a line, as a pattern:
  /// "bu akşam", "her sabah", "yarın akşam", "cuma akşamı".
  private static var turkishLinePartPattern: String {
    #"\#(turkishStart)(?:bu|her|bugun|yarin|obur\s+gun|(?:\#(turkishWeekdayNames))(?:\s+gunu)?)\s+(?:\#(turkishPartWords))\#(turkishEnd)"#
  }

  /// The part of the day the line names beside `match` (within
  /// ``turkishContextLength`` characters of it), for an hour written without
  /// one: "bu akşam saat 8", "her sabah 7'de", and "yarın akşam toplantı saat
  /// 8'de" are 20:00, 07:00, and 20:00, where the hour alone would be 08:00,
  /// 07:00, and 08:00. Nil when the line names no part of the day there, or
  /// names two that differ.
  private static func turkishLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(turkishLinePartPattern) else { return nil }
    let source = match.source
    let own = match.result.range
    let lower = max(0, own.location - turkishContextLength)
    let upper = min(source.utf16.count, NSMaxRange(own) + turkishContextLength)
    var named: PartOfDay?
    for found in regex.matches(
      in: source, options: [.withTransparentBounds, .withoutAnchoringBounds],
      range: NSRange(location: lower, length: upper - lower))
    {
      guard NSIntersectionRange(found.range, own).length == 0,
        let range = Range(found.range, in: source), let part = turkishPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the day
  /// its line names elsewhere, or nil when the hour is written on the 24-hour
  /// clock (a leading zero, 0, or 13 and later), the line names no part or two,
  /// or the part has no such hour.
  private static func turkishTimeWithLinePart(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = turkishLinePartOfDay(beside: match) else { return nil }
    return turkishTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The time a bare hour (written on the clock of 12 or 24 hours, with no part
  /// of the day of its own) names: its line's part of the day when the line
  /// names one, else the hour as ``bareTime(hour:minute:hasLeadingZero:)`` reads
  /// it.
  private static func turkishBareTime(hour: Int, minute: Int, hasLeadingZero: Bool, match: Match) -> ClockTime? {
    turkishTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Words around a clock time

  /// What may follow a clock time: no letter, digit, combining mark, or colon
  /// (the word or the number goes on), no letter joined by a hyphen or an
  /// apostrophe (a case ending the rule did not list), no decimal fraction, no
  /// percent or currency sign with or without a space before it, no dash before
  /// a digit, which makes the time one side of a range written with a dash, and
  /// no AM or PM, which English reads.
  static let turkishTimeEnd =
    #"(?![\p{Latin}\p{N}\p{M}:]|[-–]\p{L}|['’ʼ]\p{L}|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d|\s*[ap]\.?m\.?(?![\p{Latin}\p{M}]))"#

  /// The locative ending of a clock time ("5'te", "8'de", "15:30'da"), as a
  /// pattern without groups. The apostrophe may be left out.
  private static let turkishClockLocative = #"(?:['’ʼ]?(?:d[ae]|t[ae]))"#

  // MARK: - Clock time

  /// "saat 15:00", "saat 3'te", "saat üç", "saat üçte", "15:30'da", "5'te", "sabah
  /// 9", "akşam 8'de", "öğleden sonra 3", "gece 12", "öğlen 12", "bu akşam 8", "her
  /// sabah 7", and a colon time with the part of the day another word of the
  /// line names ("bu akşam toplantı 7:30"). An hour spelled as a word needs
  /// "saat" and has no minutes. A time written with no Turkish word ("15:30",
  /// "3pm") is left to English. Groups: 1 to 3 the hour, the colon or the dot,
  /// and the minute after "saat"; 4 the part of the day before an hour and 5 to
  /// 7 the hour, the separator, and the minute after it; 8 to 10 an hour with
  /// the locative ending after an apostrophe, or an hour with minutes and the
  /// ending after an apostrophe or none ("15:30'da", "15:30da"); 11 to 13 an
  /// hour right after "bu" or "her" and a part of the day; 14 to 16 a colon
  /// time with nothing else.
  /// The part of the day after "bu" or "her" belongs to the day word or the
  /// repeat, which the hour that follows it does not take with it.
  static var turkishClockPattern: String {
    let hourOrWord = #"(\d{1,2}|\#(turkishHourWordsPlainOrLocative))"#
    let minutes = #"(?:([.:])(\d{2}))?"#
    let optionalLocative = #"\#(turkishClockLocative)?"#
    let unattached = #"(?<![\p{N}:.,/])(?<![-–—])(?<![-–—]\s)"#
    let lead = #"\#(turkishStart)saat\s+\#(hourOrWord)\#(minutes)\#(optionalLocative)\#(turkishTimeEnd)"#
    let partFirst =
      #"\#(turkishStart)(?<!\bher\s)(?<!\bbu\s)(\#(turkishPartWords))\s+(?:saat\s+)?\#(hourOrWord)\#(minutes)\#(optionalLocative)\#(turkishNoCountedUnitAfter)\#(turkishTimeEnd)"#
    let locative =
      #"\#(turkishStart)\#(unattached)(\d{1,2})(?:([.:])(\d{2})['’ʼ]?|['’ʼ])(?:d[ae]|t[ae])\#(turkishTimeEnd)"#
    let afterDayPart =
      #"(?<=(?:^|\s)(?:bu|her)\s(?:aksam|gece|sabah|oglen|ikindi)\s)\#(unattached)(\d{1,2})\#(minutes)\#(optionalLocative)\#(turkishNoCountedUnitAfter)\#(turkishTimeEnd)"#
    let colonOnly = #"\#(turkishStart)\#(unattached)(\d{1,2})(:)(\d{2})\#(turkishTimeEnd)"#
    return [lead, partFirst, locative, afterDayPart, colonOnly].joined(separator: "|")
  }

  static func turkishClock(_ match: Match) -> ClockTime? {
    let hourText: String
    let separator: String?
    let minuteText: String?
    var partText: String?
    var isLocative = false
    var isColonOnly = false
    if let text = match.group(1) {
      (hourText, separator, minuteText) = (text, match.group(2), match.group(3))
    } else if let text = match.group(5) {
      (hourText, separator, minuteText, partText) = (text, match.group(6), match.group(7), match.group(4))
    } else if let text = match.group(8) {
      (hourText, separator, minuteText) = (text, match.group(9), match.group(10))
      isLocative = true
    } else if let text = match.group(11) {
      (hourText, separator, minuteText) = (text, match.group(12), match.group(13))
    } else if let text = match.group(14) {
      (hourText, separator, minuteText) = (text, match.group(15), match.group(16))
      isColonOnly = true
    } else {
      return nil
    }
    guard let hour = turkishHourNumber(hourText), (0...23).contains(hour) else { return nil }
    let isWord = number(hourText) == nil
    var minute = 0
    if let minuteText {
      guard let value = number(minuteText), (0...59).contains(value) else { return nil }
      minute = value
    }
    if isWord, !(1...12).contains(hour) { return nil }
    // "15.10'da" may be a date; "saat 15.10" and "akşam 8.10" are times.
    if isLocative, separator == ".", (1...12).contains(minute) { return nil }
    if let partText {
      guard let part = turkishPartOfDay(partText) else { return nil }
      return turkishTimeWithPart(hour: hour, minute: minute, part: part)
    }
    let hasLeadingZero = startsWithZero(hourText)
    // A colon time with no Turkish word and no part of the day in the line is
    // English's.
    if isColonOnly {
      return turkishTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    }
    return turkishBareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
  }

  /// "saat 3pm", "saat 3:30 pm": a time with AM or PM after "saat", which takes
  /// the word with it where English would leave "saat" behind. A time with AM or
  /// PM and no "saat" is English's. Groups: 1 hour, 2 minute, 3 the "a" or "p".
  static let turkishMeridiemTimePattern =
    #"\#(turkishStart)saat\s+(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?(?![\p{Latin}\p{N}\p{M}:])"#

  static func turkishMeridiemTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(1).flatMap(number), (1...12).contains(hour),
      let meridiem = match.group(3)?.lowercased()
    else { return nil }
    let minute = match.group(2).flatMap(number) ?? 0
    guard (0...59).contains(minute) else { return nil }
    return ClockTime(minutes: (hour % 12 + (meridiem == "p" ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Spoken times

  /// The minutes a spoken time may name before "geçe", "var", or "kala", as a
  /// pattern without groups: digits and the words five, ten, a quarter, twenty,
  /// and twenty-five.
  private static let turkishSpokenMinutes = #"(?:yirmi\s+bes|yirmi|ceyrek|bes|on|\d{1,2})"#

  /// The minutes a spoken amount names.
  private static func turkishMinuteCount(_ text: String) -> Int? {
    if let digits = number(text) { return digits }
    let words: [String: Int] = ["bes": 5, "on": 10, "ceyrek": 15, "yirmi": 20, "yirmi bes": 25]
    return words[turkishPhrase(text)]
  }

  /// "üç buçuk" (3:30), "saat üç buçukta", "akşam sekiz buçuk", "üçü çeyrek geçe"
  /// (3:15), "üçü on geçe" (3:10), "dörde çeyrek var" (3:45), "üçe on var" (2:50),
  /// "beşe yirmi kala" (4:40), with the hour in words or in digits ("3'ü çeyrek
  /// geçe", "4'e çeyrek var"), each maybe after "saat" or a part of the day.
  /// "Buçuk" adds the half hour to the hour before it, so "üç buçuk" is 3:30
  /// and never 2:30. It is a time only after "saat" or a part of the day, or
  /// with the ending "-ta": "bir buçuk" alone counts as often ("bir buçuk
  /// litre"). Groups: 1 the part of the day, 2 "saat", 3 the hour of "buçuk", 4
  /// its "ta", 5 the hour and 6 the minutes of "geçe", 7 the hour and 8 the
  /// minutes of "var" or "kala".
  static var turkishSpokenTimePattern: String {
    let part = #"(?:(?<!\bher\s)(?<!\bbu\s)(\#(turkishPartWords))\s+)?"#
    let lead = #"(?:(saat)\s+)?"#
    let accusativeDigits = #"\d{1,2}['’ʼ]?(?:y?[iu])"#
    let dativeDigits = #"\d{1,2}['’ʼ]?(?:y?[ae])"#
    return
      #"\#(turkishStart)\#(part)\#(lead)(?:(\#(turkishHourWordsPlain)|\d{1,2})\s+bucuk(ta)?|(\#(turkishHourWordsAccusative)|\#(accusativeDigits))\s+(\#(turkishSpokenMinutes))\s+gece|(\#(turkishHourWordsDative)|\#(dativeDigits))\s+(\#(turkishSpokenMinutes))\s+(?:var|kala))\#(turkishTimeEnd)"#
  }

  static func turkishSpokenTime(_ match: Match) -> ClockTime? {
    let partText = match.group(1)
    let hour: Int
    let minute: Int
    if let text = match.group(3) {
      // "Üç buçuk" is a time after "saat" or a part of the day, or as "üç buçukta".
      guard match.group(2) != nil || match.group(4) != nil || partText != nil,
        let value = turkishHourNumber(text), (1...23).contains(value), number(text) != nil || value <= 12
      else { return nil }
      (hour, minute) = (value, 30)
    } else if let text = match.group(5), let amount = match.group(6) {
      guard let value = turkishHourNumber(text), (1...23).contains(value),
        let minutes = turkishMinuteCount(amount), (1...29).contains(minutes)
      else { return nil }
      (hour, minute) = (value, minutes)
    } else if let text = match.group(7), let amount = match.group(8) {
      guard let value = turkishHourNumber(text), (1...23).contains(value),
        let minutes = turkishMinuteCount(amount), (1...29).contains(minutes)
      else { return nil }
      (hour, minute) = (value == 1 ? 12 : value - 1, 60 - minutes)
    } else {
      return nil
    }
    if let partText {
      guard let part = turkishPartOfDay(partText) else { return nil }
      return turkishTimeWithPart(hour: hour, minute: minute, part: part)
    }
    return turkishBareTime(hour: hour, minute: minute, hasLeadingZero: false, match: match)
  }

  // MARK: - Midnight

  /// "gece yarısı", "gece yarısında", "bu gece yarısı": midnight, which ends the
  /// day it names. "Bu" belongs to the phrase: the time takes it with it, and the
  /// time after midnight puts the task on the next day.
  static let turkishMidnightPattern = #"\#(turkishStart)(?:bu\s+)?gece\s+yarisi(?:nda)?\#(turkishEnd)"#

  static func turkishMidnight(_ match: Match) -> ClockTime? {
    ClockTime(minutes: 0, isAfterMidnight: true)
  }

  // MARK: - Time range

  /// The body of the range pattern, with its groups capturing or not. A side is
  /// a time written in digits ("14", "14:30", "14.30"), maybe after "saat" and
  /// a part of the day; the sides are joined by a dash, by "ile" before "arası",
  /// or by the endings of "14'ten 16'ya kadar".
  private static func turkishTimeRangeBody(capturing: Bool) -> String {
    func group(_ pattern: String) -> String { capturing ? "(\(pattern))" : "(?:\(pattern))" }
    let side = #"(?<![\p{N}:.,])\d{1,2}(?:[.:]\d{2})?"#
    let lead =
      #"(?:\#(group("saat"))\s+)?(?:(?<!\bher\s)(?<!\bbu\s)\#(group(turkishPartWords))\s+)?"#
    let ablative = group(#"['’ʼ]?(?:d[ae]n|t[ae]n)"#)
    let dative = group(#"['’ʼ]?(?:y?[ae])"#)
    let joiner = #"(?:\#(ablative)\s+|\s*\#(group("[-–—]"))\s*|\s+\#(group("ile"))\s+)"#
    let tail = #"(?:\s+\#(group("kadar|arasi|arasinda")))?"#
    return #"\#(lead)\#(group(side))\#(joiner)\#(group(side))(?:\#(dative))?\#(tail)"#
  }

  /// "saat 14-16", "14.00-16.00", "akşam 7-9", "saat 14'ten 16'ya kadar",
  /// "10:00'dan 11:00'e kadar", "saat 14 ile 16 arası", "14-16 arası". Groups: 1
  /// "saat", 2 the part of the day before the start, 3 the start, 4 the
  /// ablative ending of the start, 5 a dash, 6 "ile", 7 the end, 8 the dative
  /// ending of the end, 9 the word after the end ("kadar", "arası", "arasında").
  static var turkishTimeRangePattern: String {
    #"\#(turkishStart)\#(turkishTimeRangeBody(capturing: true))\#(turkishTimeEnd)"#
  }

  static func turkishTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(3), let endText = match.group(7) else { return nil }
    let hasLead = match.group(1) != nil
    let partText = match.group(2)
    let closing = match.group(9).map(turkishKey)
    let isBetween = closing == "arasi" || closing == "arasinda"
    if match.group(4) != nil {
      // "14'ten 16'ya (kadar)": the ablative and the dative join the sides.
      guard match.group(8) != nil, closing == nil || closing == "kadar" else { return nil }
    } else if match.group(6) != nil {
      // "14 ile 16 arası": "ile" joins the sides before "arası" only.
      guard isBetween, match.group(8) == nil else { return nil }
    } else {
      guard match.group(5) != nil, match.group(8) == nil, closing == nil || isBetween else { return nil }
    }
    let sides = [startText, endText]
    let hasMinutes = sides.contains { $0.contains(":") || $0.contains(".") }
    // Two bare hours are as often an amount or numbered items ("2'den 4'e
    // kadar" counts pages), so a range needs "saat", a part of the day, or
    // minutes.
    guard hasLead || partText != nil || hasMinutes else { return nil }
    // A dashed range of colon times with nothing else is English's.
    if match.group(5) != nil, !hasLead, partText == nil, sides.allSatisfy({ $0.contains(":") }) { return nil }
    let part = partText.flatMap(turkishPartOfDay)
    guard let start = turkishRangeSide(startText, part: part, hasMarker: hasLead, match: match),
      let end = turkishRangeSide(endText, part: part, hasMarker: hasLead, match: match)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with the part of the
  /// day the range names or the one the line names elsewhere. Dotted minutes
  /// that are a month ("5.10") make a date, not a time, unless "saat" or a part
  /// of the day says it is a time.
  private static func turkishRangeSide(_ text: String, part: PartOfDay?, hasMarker: Bool, match: Match) -> ClockTime? {
    guard let side = text.wholeMatch(of: /(\d{1,2})(?:([:.])(\d{2}))?/), let hour = number(side.output.1) else {
      return nil
    }
    let minute = side.output.3.flatMap { number($0) } ?? 0
    guard (0...59).contains(minute) else { return nil }
    if side.output.2 == ".", (1...12).contains(minute), !hasMarker, part == nil { return nil }
    if hour == 24 { return minute == 0 ? ClockTime(minutes: 0, isAfterMidnight: true) : nil }
    guard (0...23).contains(hour) else { return nil }
    if let part { return turkishTimeWithPart(hour: hour, minute: minute, part: part) }
    return turkishBareTime(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(String(side.output.1)), match: match)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written with its minutes and no word before it, as a pattern
  /// without groups: "17:30", "9:00", and "17.30" or "9.00". Minutes after a
  /// dot are a clock time only where they are no month: "15.10" is a date.
  private static let turkishBareClock = #"\d{1,2}(?::\d{2}|\.(?:00|1[3-9]|[2-5]\d))"#

  /// A clock time as a pattern without groups, in a form that names an hour of
  /// its own: "saat 17", "saat akşam 5", "akşam 5", "akşam saat 5", "17:30",
  /// "17.30".
  private static var turkishClockShape: String {
    let part = turkishPartWords
    return
      #"(?:saat\s+(?:(?:\#(part))\s+)?\d{1,2}(?:[.:]\d{2})?|(?:\#(part))\s+(?:saat\s+)?\d{1,2}(?:[.:]\d{2})?|\#(turkishBareClock))"#
  }

  /// A clock time written as a bound ("saat 17:00'ye kadar", "17:00'den önce",
  /// "saat 5'ten sonra", "saat beşe kadar", "en geç saat 17:00", "en geç akşam
  /// 8'de", "en erken saat 9"), which names no start time. A bare number after
  /// "en geç" is a bound only with minutes, an ending, or "saat" or a part of
  /// the day: "en geç 15 Ekim" is a date. Group 1 is the bound, or nil for a range
  /// ("saat 14'ten 17:30'a kadar"), which the range rule reads and this rule
  /// only steps over, so the "17:30'a kadar" inside it is not taken for a bound.
  static var turkishDeadlineClockPattern: String {
    let afterWords = #"kadar|dek|degin|once|evvel|sonra|itibaren"#
    let suffix = #"['’ʼ]?(?:y?[ae]|[dt][ae]n)"#
    let part = turkishPartWords
    let hour = #"\d{1,2}(?:[.:]\d{2})?"#
    let before =
      #"en\s+(?:gec|erken)\s+(?:(?:saat\s+(?:(?:\#(part))\s+)?|(?:\#(part))\s+(?:saat\s+)?)(?:\#(hour)|\#(turkishHourWordsAny))\#(turkishClockLocative)?|\#(turkishBareClock)\#(turkishClockLocative)?|\d{1,2}['’ʼ](?:d[ae]|t[ae]))"#
    let after =
      #"\#(turkishClockShape)\#(suffix)\s+(?:\#(afterWords))|saat\s+(?:\#(turkishHourWordsAny))\s+(?:\#(afterWords))"#
    return
      #"\#(turkishStart)(?:\#(turkishTimeRangeBody(capturing: false))|(\#(before)|\#(after)))\#(turkishEnd)"#
  }

  /// The clock after a deadline day ("son tarih cuma saat 17:00", "teslim:
  /// yarın 9.00"), which is a deadline's clock and stays in the title with the
  /// rest of the line once the day is read as the due day.
  static var turkishDueClockPattern: String {
    #"\#(turkishStart)\#(turkishClockShape)\#(turkishClockLocative)?\#(turkishTimeEnd)"#
  }

  /// The text before a deadline clock that makes it the clock of a due day: a
  /// word that introduces a due day, the day, with a comma or a space before the
  /// clock.
  private static var turkishAfterDueDayPattern: String {
    #"(?:^|\s)\#(turkishDueLead)(?:\#(turkishPlainDay(afterLead: true)))\s*,?\s*$"#
  }

  /// Whether the text before `match` ends with a word that introduces a due day
  /// and the day ("son tarih cuma", "en geç yarın").
  static func turkishIsClockAfterDueDay(_ match: Match) -> Bool {
    let before = turkishTextBefore(match)
    guard let regex = LorvexCapturePatterns.regex(turkishAfterDueDayPattern) else { return false }
    return regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil
  }
}
