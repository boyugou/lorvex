import Foundation

extension LorvexCaptureVocabulary {
  // The Bengali clock-time rules: a time with the classifier of an hour, a
  // time with a part of the day, a colon time, a range of times, and the rule
  // that keeps a deadline written as a clock time in the title. The
  // vocabulary's other words are in ``bengali``.

  // MARK: - Parts of the day

  /// The words that name a part of the day, as a pattern without groups: the
  /// morning (সকাল, ভোর), the day (দুপুর), the evening (বিকেল, বিকাল, সন্ধ্যা,
  /// and the spellings of "সন্ধ্যে"), the night (রাত, রাত্রি), and the
  /// midnight (মধ্যরাত, মাঝরাত), longest first.
  private static let bengaliPartStems =
    #"মধ্যরাত্রি|মধ্যরাত্র|মধ্যরাত|মাঝরাত্রি|মাঝরাত্র|মাঝরাত|সকাল|ভোর|দুপুর|বিকেল|বিকাল|সন্ধ্যা|সন্ধ্যে|সন্ধে|সন্ধা|রাত্রি|রাত্র|রাত"#

  /// The words that name a part of the day after a day word, as a pattern
  /// without groups: a stem alone or with the locative ending ("সকালে",
  /// "রাতে", "সন্ধ্যায়", "রাত্রিতে") or with "বেলা" ("সকালবেলা",
  /// "সন্ধ্যাবেলায়"). The genitive ("রাতের") is not here: "আজ রাতের খাবার" is
  /// tonight's dinner, and the part belongs to the noun.
  static let bengaliDayPartWords =
    #"(?:\#(bengaliPartStems))(?:·(?:ে|য়|তে)|·বেলা(?:·য়)?)?"#

  /// The words that may stand before an hour to give its part of the day, as a
  /// pattern without groups: the words of ``bengaliDayPartWords`` and the
  /// genitive ("রাতের ১০টায়", "সকালের ৭টায়").
  static let bengaliPartLeadWords =
    #"(?:\#(bengaliPartStems))(?:·(?:ের|ে|য়|তে|র)|·বেলা(?:·(?:য়|র))?)?"#

  /// A part of the day before an hour, as a pattern: "সকাল ৯টা", "সকালে ৯টায়",
  /// "রাতের ১০টায়", "রাতে ঠিক ১০টায়". With `capturing`, the part's words are
  /// group 1 of the lead. A part that "প্রতি", "রোজ", or "প্রত্যেক" stands
  /// before ("রোজ সকালে ৬টায়") belongs to the repeat, so the lead leaves it
  /// there and the hour takes its part from the line
  /// (``bengaliLinePartOfDay(beside:)``).
  private static func bengaliPartLead(capturing: Bool) -> String {
    let words = capturing ? "(\(bengaliPartLeadWords))" : "(?:\(bengaliPartLeadWords))"
    return
      #"(?:(?<!\#(bengaliEveryOrDaily)\s)\#(words)\s+(?:(?:ঠিক|প্রায়|আনুমানিক|মোটামুটি)\s+)?)"#
  }

  /// The part of the day a matched word or phrase names.
  static func bengaliPartOfDay(_ text: String) -> PartOfDay? {
    let words = bengaliWords(in: text)
    func names(_ stem: String) -> Bool { words.contains { bengaliHasPrefix($0, bengaliKey(stem)) } }
    if names("রাত") || names("মধ্যরাত") || names("মাঝরাত") { return .night }
    if names("সকাল") || names("ভোর") { return .morning }
    if names("দুপুর") { return .day }
    if names("বিকেল") || names("বিকাল") || names("সন্ধ") { return .evening }
    return nil
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("রাত ৯টা"
  /// is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that ends the
  /// day, and 1 to 5 the small hours after it (``nightTime(hour:minute:)``).
  /// The other parts follow ``partOfDayTime(hour:minute:part:)``.
  private static func bengaliTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: the stem alone, with
  /// the locative or the genitive, or with "বেলা", as a whole word. "সকালবেলার"
  /// and "রাতভর" are other words only where the ending is not listed.
  private static let bengaliLinePartPattern = bengali(
    #"\#(bengaliStart)(?:\#(bengaliPartStems))(?:·(?:ের|ে|য়|তে|র)|·বেলা(?:·(?:য়|র))?)?\#(bengaliEnd)"#)

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "কাল সকালে মিটিং ৬টায়" and "রোজ সকালে ৬টায় যোগব্যায়াম" are
  /// 06:00, and "রাতের খাবার ৮টায়" is 20:00, where the hour alone would be
  /// 18:00 and 08:00. Nil when the line names no part of the day, or names two
  /// that differ ("সকালের ওষুধ, সন্ধ্যার চা ৫টায়").
  private static func bengaliLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(bengaliLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = bengaliPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no
  /// part or two, or the part has no such hour ("সকালের হাঁটা ১২টায়").
  private static func bengaliTimeWithLinePart(
    hour: Int, minute: Int, hasLeadingZero: Bool, match: Match
  ) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = bengaliLinePartOfDay(beside: match) else { return nil }
    return bengaliTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The clock time an hour names: with its own part of the day when it has
  /// one, else with the part the line names elsewhere, else as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func bengaliClock(
    hour: Int, minute: Int, hasLeadingZero: Bool, part: PartOfDay?, match: Match
  ) -> ClockTime? {
    if let part { return bengaliTimeWithPart(hour: hour, minute: minute, part: part) }
    return bengaliTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Clock words

  /// The words that name an hour or half of one before the classifier: the
  /// numerals one to twelve and দেড় (1:30) and আড়াই (2:30).
  static var bengaliTimeWords: String {
    "\(bengaliHourStemWords)|দেড়|আড়াই"
  }

  /// The classifier of an hour: টা, টে, or টো, alone or with the locative য়
  /// ("৫টা", "৫টায়", "তিনটে", "তিনটেয়", "দুটো", "দুটোয়").
  private static let bengaliClassifier = #"(?:টায়|টেয়|টোয়|টা|টে|টো)"#

  /// The hours that দেড় and আড়াই name.
  private static let bengaliHalfHours: [String: (hour: Int, minute: Int)] = [
    bengaliKey("দেড়"): (1, 30), bengaliKey("আড়াই"): (2, 30),
  ]

  /// The hour a fraction word makes of the count after it, on the clock face:
  /// "সাড়ে তিনটে" is 3:30, "সোয়া তিনটে" is 3:15, and "পৌনে চারটে" is 3:45. Nil
  /// for a word that is no fraction.
  private static func bengaliFractionTime(_ fraction: String, hour: Int) -> (hour: Int, minute: Int)? {
    guard (1...12).contains(hour) else { return nil }
    switch fraction {
    case bengaliKey("সাড়ে"): return (hour, 30)
    case bengaliKey("সোয়া"), bengaliKey("সওয়া"): return (hour, 15)
    case bengaliKey("পৌনে"): return (hour == 1 ? 12 : hour - 1, 45)
    default: return nil
    }
  }

  /// The time of an hour on the 12-hour clock with AM or PM written after it.
  private static func bengaliMeridiemTime(hour: Int, minute: Int, meridiem: String) -> ClockTime? {
    guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
    let isAfternoon = meridiem.lowercased().hasPrefix("p")
    return ClockTime(minutes: ((hour % 12) + (isAfternoon ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Time

  /// "৫টায়", "৫:৩০টায়", "সাড়ে ৩টায়" (3:30), "সোয়া ৩টায়" (3:15), "পৌনে ৪টায়"
  /// (3:45), "দেড়টায়" (1:30), "আড়াইটায়" (2:30), "পাঁচটায়", "সকাল ৯টা", "রাতের
  /// ১০টায়", "৫টার সময়", "৫টা নাগাদ", each maybe after "ঠিক", "প্রায়",
  /// "আনুমানিক", or "মোটামুটি". A fraction word may be written apart from its
  /// hour ("সাড়ে তিনটে", "সাড়ে ৩টা"). The hour takes the classifier টা, টে, or
  /// টো: with the locative য় (টায়, টেয়, টোয়) it is a time by itself, and
  /// without it only where something else says it is a time (a part of the day
  /// before it, a fraction word, দেড় or আড়াই, minutes after a colon, or "র
  /// সময়", "র দিকে", or "নাগাদ" after it), since "৫টা বই" and "একটা কাজ"
  /// count things. The hour may be followed by its minutes with the locative
  /// of "মিনিট" ("সকাল ১০টা ৩০ মিনিটে" is 10:30): only after the classifier
  /// without the locative য়, since "৫টায় ৩০ মিনিটে শেষ" is two phrases, and
  /// only with the locative, since "৫টা ৩০ মিনিট" is an hour and a length. An
  /// hour with no part of the day of its own takes the one the
  /// line names elsewhere (``bengaliLinePartOfDay(beside:)``), and otherwise
  /// reads as ``bareTime(hour:minute:hasLeadingZero:)`` does.
  /// Groups: 1 the part of the day before the hour, 2 the fraction word, 3 the
  /// hour in digits, 4 its minutes after a colon, 5 the hour in words, 6 the
  /// classifier, 7 the words that make it a time after it, 8 the minutes with
  /// "মিনিটে" after the classifier.
  static var bengaliTimePattern: String {
    let approximate = #"(?:(?:ঠিক|প্রায়|আনুমানিক|মোটামুটি)\s+)?"#
    let fraction = #"(?:(সাড়ে|সোয়া|সওয়া|পৌনে)\s*)?"#
    let hour = #"(?:(?<![:.,])(\d{1,2})(?:[:.](\d{2}))?|(\#(bengaliTimeWords))['’]?)"#
    let anchor = #"((?:·র\s+(?:সময়|দিকে)|\s+নাগাদ)\#(bengaliEnd))?"#
    let minutes =
      #"(?:(?<![\x{09AF}\x{09BC}])\s+(\d{1,2}|\#(bengaliRoundCountWords))\s*মিনিটে(?=\s|$|[.,;:!?।]))?"#
    return
      #"\#(bengaliStart)\#(approximate)\#(bengaliPartLead(capturing: true))?\#(fraction)\#(hour)·(\#(bengaliClassifier))\#(anchor)\#(minutes)\#(bengaliTimeEnd)"#
  }

  static func bengaliTime(_ match: Match) -> ClockTime? {
    let fraction = match.group(2).map(bengaliPhrase)
    var minute = match.group(4).flatMap(number) ?? 0
    var hour: Int
    var isHalfWord = false
    if let text = match.group(3) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(5).map(bengaliPhrase) {
      if let half = bengaliHalfHours[word] {
        guard fraction == nil else { return nil }
        (hour, minute) = half
        isHalfWord = true
      } else if let count = bengaliHourStems[word] {
        hour = count
      } else {
        return nil
      }
    } else {
      return nil
    }
    if let text = match.group(8) {
      guard match.group(4) == nil, match.group(7) == nil, fraction == nil, !isHalfWord,
        let value = number(text) ?? bengaliRoundCounts[bengaliPhrase(text)], (0...59).contains(value)
      else { return nil }
      minute = value
    }
    // The locative য় is the ending of "at"; the other endings need a reason.
    let isLocative = (match.group(6) ?? "").unicodeScalars.contains("\u{09AF}")
    let part = match.group(1).flatMap(bengaliPartOfDay)
    guard
      isLocative || fraction != nil || isHalfWord || part != nil || match.group(4) != nil || match.group(7) != nil
        || match.group(8) != nil
    else { return nil }
    // A fraction counts from an hour on the clock face.
    if let fraction {
      guard minute == 0, let time = bengaliFractionTime(fraction, hour: hour) else { return nil }
      (hour, minute) = time
    }
    let hasLeadingZero = startsWithZero(match.group(3) ?? "") && fraction == nil
    return bengaliClock(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, part: part, match: match)
  }

  /// "সকাল ৯:৩০", "রাত ১০.৩০", "১৭:৩০-এ", "৩:৩০ এ", "৩:৩০ PM-এ": a colon or
  /// dotted time with a part of the day before it, or with "এ" after it (glued,
  /// after a hyphen, or after a space), maybe with AM or PM between. A colon
  /// time with
  /// neither is left to English, which reads its own "17:30" and "3:30 PM"
  /// together with the words around them ("at 3:30 PM"). A bare hour with a
  /// part ("সন্ধ্যা ৫") is no time. Groups: 1 the part of the day, 2 the hour,
  /// 3 the minutes, 4 AM or PM, 5 the "এ" ending.
  static var bengaliColonTimePattern: String {
    let approximate = #"(?:(?:ঠিক|প্রায়|আনুমানিক|মোটামুটি)\s+)?"#
    let meridiem = #"(?:\s*(am|pm|a\.m\.|p\.m\.))?"#
    return
      #"\#(bengaliStart)\#(approximate)\#(bengaliPartLead(capturing: true))?(?<![:.,])(\d{1,2})[:.](\d{2})\#(meridiem)((?:\s*[-‐‑–]\s*|\s*)এ)?\#(bengaliTimeEnd)"#
  }

  static func bengaliColonTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(2).flatMap(number), let minute = match.group(3).flatMap(number) else { return nil }
    if let part = match.group(1).flatMap(bengaliPartOfDay) {
      guard match.group(4) == nil else { return nil }
      return bengaliTimeWithPart(hour: hour, minute: minute, part: part)
    }
    guard match.group(1) == nil, match.group(5) != nil else { return nil }
    if let meridiem = match.group(4) { return bengaliMeridiemTime(hour: hour, minute: minute, meridiem: meridiem) }
    return bengaliClock(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(match.group(2) ?? ""), part: nil, match: match)
  }

  /// "মধ্যরাতে", "মধ্যরাত্রে", "মাঝরাতে", "ঠিক মধ্যরাতে": the midnight that ends
  /// the day. "মধ্যরাত পর্যন্ত" is a deadline and "মধ্যরাতের পরে" a time after
  /// it, so neither is read.
  static let bengaliMidnightPattern =
    #"\#(bengaliStart)(?:ঠিক\s+)?(?:মধ্যরাত্রি(?:·তে)?|মধ্যরাত্রে|মধ্যরাত(?:·ে)?|মাঝরাত্রি(?:·তে)?|মাঝরাত্রে|মাঝরাত(?:·ে)?)\#(bengaliEnd)(?!\#(bengaliUntilWords)\#(bengaliEnd)|\s+(?:পরে|পর|আগে|মধ্যে)\#(bengaliEnd))"#

  // MARK: - Time range

  /// The side of a range, as a pattern: an hour in digits with maybe minutes,
  /// or an hour in words.
  private static var bengaliRangeSide: String {
    #"((?<![:.,])\d{1,2}(?:[:.]\d{2})?|\#(bengaliHourStemWords))"#
  }

  /// The words between the two sides of a range: "থেকে" or "হতে", or a dash.
  private static let bengaliRangeConnector = #"(?:\s+(?:থেকে|হতে)\s+|\s*[-–—]\s*)"#

  /// "৩টা থেকে ৫টা", "৩ থেকে ৫টায়", "৩-৫টায়", "সকাল ৯টা থেকে ১১টা পর্যন্ত",
  /// "দুপুর ২টা থেকে বিকেল ৪টা", "তিনটা হতে পাঁচটা". The end carries the
  /// classifier: two bare numbers ("৩ থেকে ৫") are as often an amount. Groups: 1
  /// the part of the day before the start, 2 the start, 3 the part before the
  /// end, 4 the end.
  static var bengaliTimeRangePattern: String {
    #"\#(bengaliStart)\#(bengaliPartLead(capturing: true))?\#(bengaliRangeSide)['’]?(?:\#(bengaliClassifier))?\#(bengaliRangeConnector)\#(bengaliPartLead(capturing: true))?\#(bengaliRangeSide)['’]?\#(bengaliClassifier)(?:\#(bengaliUntilWords))?+\#(bengaliTimeEnd)"#
  }

  /// "১৪:০০ থেকে ১৬:০০", "৯:৩০ হতে ১০:৩০ পর্যন্ত", "সকাল ৯:০০ থেকে বিকেল ৫:০০":
  /// a range of two colon times joined by "থেকে" or "হতে", maybe with
  /// "পর্যন্ত" after it. The same groups as ``bengaliTimeRangePattern``. A range
  /// joined by a dash ("১৪:০০-১৬:০০") is English's.
  static var bengaliColonTimeRangePattern: String {
    #"\#(bengaliStart)\#(bengaliPartLead(capturing: true))?((?<![:.,])\d{1,2}[:.]\d{2})\s+(?:থেকে|হতে)\s+\#(bengaliPartLead(capturing: true))?(\d{1,2}[:.]\d{2})(?:\#(bengaliUntilWords))?+\#(bengaliTimeEnd)"#
  }

  static func bengaliTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(4) else { return nil }
    // A part of the day elsewhere in the line names the start's half of the day
    // (``bengaliLinePartOfDay(beside:)``); the end is the first reading after the
    // start.
    guard
      let start = bengaliRangeSideTime(startText, part: match.group(1), match: match, beside: match.group(1) == nil),
      let end = bengaliRangeSideTime(endText, part: match.group(3), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func bengaliRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = bengaliHourStems[bengaliPhrase(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = bengaliPartOfDay(part) else { return nil }
      return bengaliTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = bengaliTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// A clock time written as a bound ("৫টার মধ্যে", "সন্ধ্যা ৬টার আগে", "৫টা
  /// পর্যন্ত", "১৮:০০ পর্যন্ত", "৩ PM পর্যন্ত", "৫টার পর"), which names no start
  /// time. Group 1 is the bound, or nil for a range ("৩টা থেকে ৫টা
  /// পর্যন্ত"), which the range rules read and this rule only steps over, so
  /// the "৫টা পর্যন্ত" inside it is not taken for a bound.
  static var bengaliDeadlineClockPattern: String {
    let lead = bengaliPartLead(capturing: false)
    let side = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(bengaliHourStemWords))"#
    let range =
      #"(?:\#(lead)?\#(side)['’]?(?:\#(bengaliClassifier))?\#(bengaliRangeConnector)\#(lead)?\#(side)['’]?\#(bengaliClassifier)(?:\#(bengaliUntilWords))?+|\#(lead)?\d{1,2}[:.]\d{2}\s+(?:থেকে|হতে)\s+\#(lead)?\d{1,2}[:.]\d{2}(?:\#(bengaliUntilWords))?+)"#
    let deadline =
      #"((?:(?:ঠিক|প্রায়|আনুমানিক|মোটামুটি)\s+)?\#(lead)?\#(bengaliClockBound))"#
    return #"\#(bengaliStart)(?:\#(range)|\#(deadline))\#(bengaliEnd)"#
  }
}
