import Foundation

extension LorvexCaptureVocabulary {
  // The Telugu clock-time rules: a time with "గంటలకు", a half hour, a time
  // with a part of the day and the dative, a colon time, a range of times, and
  // the rule that keeps a deadline written as a clock time in the title. The
  // vocabulary's other words are in ``telugu``.

  // MARK: - Parts of the day

  /// The words that name each part of the day, in the endings people type:
  /// the plain word ("ఉదయం", "ఉదయము"), the adverbs ("ఉదయాన్నే", "ఉదయాన") and
  /// the dative ("ఉదయానికి"). తెల్లవారుజామున and వేకువజామున are the small hours
  /// of the morning, మిట్ట మధ్యాహ్నం the noon, సాయంకాలం another word for the
  /// evening, and the night includes అర్ధరాత్రి. The loanword మిడ్‌నైట్ names the
  /// night too, under the condition of ``teluguMidnightLoanword``.
  private static let teluguPartForms: [(part: PartOfDay, words: [String])] = [
    (
      .morning,
      [
        "ఉదయం", "ఉదయము", "ఉదయాన్నే", "ఉదయాన", "ఉదయానికి", "తెల్లవారుజామున", "తెల్లవారుజాము", "తెల్లవారు జామున",
        "వేకువజామున", "వేకువజాము", "వేకువ జామున",
      ]
    ),
    (
      .day,
      [
        "మధ్యాహ్నం", "మధ్యాహ్నము", "మధ్యాహ్నాన్నే", "మధ్యాహ్నాన", "మధ్యాహ్నానికి", "మిట్ట మధ్యాహ్నం", "మిట్టమధ్యాహ్నం",
      ]
    ),
    (
      .evening,
      [
        "సాయంత్రం", "సాయంత్రము", "సాయంత్రాన్నే", "సాయంత్రాన", "సాయంత్రానికి", "సాయంకాలం", "సాయంకాలము", "సాయంకాలాన",
        "సాయంకాలానికి",
      ]
    ),
    (
      .night,
      [
        "రాత్రి", "రాత్రికి", "రాత్రే", "రాత్రిపూట", "రాత్రి పూట", "అర్ధరాత్రి", "అర్థరాత్రి", "అర్ధ రాత్రి", "అర్ధరాత్రికి",
        "అర్థరాత్రికి",
      ]
    ),
  ]

  /// The words after a midnight that make it a bound or a point beside it:
  /// "అర్ధరాత్రి వరకు" is a deadline and "అర్ధరాత్రి తర్వాత" a time after it. A
  /// pattern without groups.
  private static let teluguMidnightBoundWords =
    #"(?:వరకు|వరకూ|దాకా|తర్వాత|తరువాత|ముందు|లోపు|లోగా|లోపల|కల్లా|నాటికి|అనంతరం)"#

  /// The loanword "మిడ్‌నైట్" for midnight, spaced or joined, as a pattern
  /// without groups. The system starts its colour names with it ("మిడ్‌నైట్
  /// బ్లూ", "మిడ్‌నైట్ బ్లాక్"; 6 of the 8 strings of Apple's Telugu that hold
  /// it), so it names the night only with a dative ending glued to it
  /// ("మిడ్‌నైట్‌కి"), with a word of ``teluguMidnightBoundWords`` after it
  /// ("శుక్రవారం మిడ్‌నైట్ వరకు"), or with no other Telugu word after it ("కారు
  /// మిడ్‌నైట్", "మిడ్‌నైట్ 12 గంటలకు").
  private static let teluguMidnightLoanword =
    #"మిడ్\s*నైట్(?=కి|కు|కే|(?!\s+(?!\#(teluguMidnightBoundWords)\#(teluguEnd))\p{Telugu}))"#

  /// The genitive forms of the parts of the day, which name the part a line is
  /// about ("ఉదయపు నడక 6 గంటలకు") but are not a part of a day phrase.
  private static let teluguPartGenitives: [(part: PartOfDay, word: String)] = [
    (.morning, "ఉదయపు"), (.day, "మధ్యాహ్నపు"), (.evening, "సాయంత్రపు"),
  ]

  /// Each form of a part of the day as a key, with its part.
  private static let teluguPartByKey: [String: PartOfDay] = {
    var parts: [String: PartOfDay] = [:]
    for (part, words) in teluguPartForms {
      for word in words { parts[teluguCompactKey(word)] = part }
    }
    for (part, word) in teluguPartGenitives { parts[teluguCompactKey(word)] = part }
    parts[teluguCompactKey("మిడ్‌నైట్")] = .night
    return parts
  }()

  /// The words that name a part of the day after a day word or before an hour,
  /// as a pattern without groups: the words of ``teluguPartForms`` longest
  /// first, then the loanword for midnight.
  static let teluguDayPartWords =
    teluguAlternation(of: teluguPartForms.flatMap { $0.words }) + "|" + teluguMidnightLoanword

  /// The part of the day a matched word names.
  static func teluguPartOfDay(_ text: String) -> PartOfDay? {
    teluguPartByKey[teluguCompactKey(text)]
  }

  /// The words that make a part of the day belong to a phrase of its own:
  /// the words for every day before it ("ప్రతి ఉదయం", "రోజూ రాత్రి") and "ఈ"
  /// ("ఈ సాయంత్రం"). An hour after such a part takes its half of the day from
  /// the line instead of claiming the part, so the repeat or the day phrase
  /// keeps its words.
  private static let teluguPartOwner = #"(?:\#(teluguEveryOrDaily)|ఈ)"#

  /// The words that may stand before an hour or after its part of the day,
  /// that make it approximate or exact.
  private static let teluguApproximate = #"(?:(?:సరిగ్గా|ఖచ్చితంగా|సుమారు|దాదాపు)\s+)?"#

  /// A part of the day before an hour, as a pattern: "ఉదయం 9 గంటలకు",
  /// "రాత్రి సరిగ్గా 10 గంటలకు". With `capturing`, the part's words are group
  /// 1 of the lead. A part that "ప్రతి", "రోజూ", or "ఈ" stands before
  /// ("ప్రతి ఉదయం 6 గంటలకు") belongs to that phrase, so the lead leaves it
  /// there and the hour takes its part from the line
  /// (``teluguLinePartOfDay(beside:)``).
  private static func teluguPartLead(capturing: Bool) -> String {
    let words = capturing ? "(\(teluguDayPartWords))" : "(?:\(teluguDayPartWords))"
    return #"(?:(?<!\#(teluguPartOwner)\s)\#(words)\s+\#(teluguApproximate))"#
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("రాత్రి 9
  /// గంటలకు" is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that
  /// ends the day, and 1 to 5 the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``.
  private static func teluguTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: the plain word, the
  /// adverbs, the dative, or the genitive, as a whole word. "ఉదయంపూట" and
  /// "రాత్రింబవళ్లు" are other words.
  private static let teluguLinePartPattern = telugu(
    #"\#(teluguStart)(?:\#(teluguDayPartWords)|ఉదయపు|మధ్యాహ్నపు|సాయంత్రపు)\#(teluguEnd)"#)

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "రేపు ఉదయం మీటింగ్ 6 గంటలకు" and "రోజూ ఉదయం 6 గంటలకు యోగా"
  /// are 06:00, and "రాత్రి భోజనం 8 గంటలకు" is 20:00, where the hour alone would
  /// be 18:00 and 08:00. Nil when the line names no part of the day, or names
  /// two that differ ("ఉదయం టీ, సాయంత్రం స్నాక్స్ 5 గంటలకు").
  private static func teluguLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(teluguLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = teluguPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no part
  /// or two, or the part has no such hour ("ఉదయం నడక 12 గంటలకు").
  private static func teluguTimeWithLinePart(
    hour: Int, minute: Int, hasLeadingZero: Bool, match: Match
  ) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = teluguLinePartOfDay(beside: match) else { return nil }
    return teluguTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The clock time an hour names: with its own part of the day when it has
  /// one, else with the part the line names elsewhere, else as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func teluguClock(
    hour: Int, minute: Int, hasLeadingZero: Bool, part: PartOfDay?, match: Match
  ) -> ClockTime? {
    if let part { return teluguTimeWithPart(hour: hour, minute: minute, part: part) }
    return teluguTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  /// The time of an hour on the 12-hour clock with AM or PM written after it.
  private static func teluguMeridiemTime(hour: Int, minute: Int, meridiem: String) -> ClockTime? {
    guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
    let isAfternoon = meridiem.lowercased().hasPrefix("p")
    return ClockTime(minutes: ((hour % 12) + (isAfternoon ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Clock words

  /// The words that follow an hour and make it a time by itself: the dative
  /// of "గంట" ("5 గంటలకు", "5 గంటలకి", "5 గంటలకే", "ఒంటి గంటకు") or "గంటల" and a
  /// word that says "at the time of" ("5 గంటల సమయంలో", "5 గంటల ప్రాంతంలో") or
  /// "from" ("5 గంటల నుండి"), as a pattern without groups.
  private static let teluguHourEnding =
    #"\s*(?:గంటలకు|గంటలకి|గంటలకే|గంటకు|గంటకి|గంటకే|గంటల\s+(?:సమయంలో|సమయానికి|ప్రాంతంలో|ప్రాంతానికి|నుండి|నుంచి|నించి)|గంటలప్పుడు)"#

  /// The spoken forms of "at N o'clock" that glue the dative to the hour word:
  /// "రెండింటికి", "ఐదింటికి", "ఎనిమిదింటికి". They are also the dative of
  /// "the two of them" ("రెండింటికి"), so they are read only after a part of the
  /// day ("సాయంత్రం ఐదింటికి").
  private static let teluguDativeHourSpellings: [(Int, [String])] = [
    (2, ["రెండింటికి"]), (3, ["మూడింటికి"]), (4, ["నాలుగింటికి"]), (5, ["ఐదింటికి", "అయిదింటికి"]),
    (6, ["ఆరింటికి"]), (7, ["ఏడింటికి"]), (8, ["ఎనిమిదింటికి"]), (9, ["తొమ్మిదింటికి"]), (10, ["పదింటికి"]),
    (11, ["పదకొండింటికి"]), (12, ["పన్నెండింటికి"]),
  ]

  /// The dative hour words as keys.
  private static let teluguDativeHours: [String: Int] = {
    var words: [String: Int] = [:]
    for (value, spellings) in teluguDativeHourSpellings {
      for word in spellings { words[teluguCompactKey(word)] = value }
    }
    return words
  }()

  /// The dative hour words as a pattern.
  private static var teluguDativeHourWords: String {
    teluguAlternation(of: teluguDativeHourSpellings.flatMap { $0.1 })
  }

  // MARK: - Time

  /// "5 గంటలకు", "5:30 గంటలకు", "ఐదు గంటలకు", "ఒంటి గంటకు", "5 గంటల 30
  /// నిమిషాలకు", "సాయంత్రం 5 గంటలకు", "రాత్రి 10 గంటలకు", "5 గంటల ప్రాంతంలో",
  /// each maybe after "సరిగ్గా", "ఖచ్చితంగా", "సుమారు", or "దాదాపు". The hour
  /// takes "గంటలకు" or one of the endings of ``teluguHourEnding``: without
  /// them it is an amount of hours ("5 గంటలు" is a length). The hour may be
  /// followed by its minutes ("5 గంటల 30 నిమిషాలకు" is 5:30). An hour after
  /// "ప్రతి" ("ప్రతి 2 గంటలకు" is every 2 hours) is no time. An hour with no
  /// part of the day of its own takes the one the line names elsewhere
  /// (``teluguLinePartOfDay(beside:)``), and otherwise reads as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` does. Groups: 1 the part of the
  /// day before the hour, 2 the hour in digits, 3 its minutes after a colon, 4
  /// the hour in words, 5 the minutes written after "గంటల".
  static var teluguHourPattern: String {
    let hour = #"(?:(?<![\p{N}:.,/])(\d{1,2})(?:[:.](\d{2}))?|(\#(teluguHourWordPattern)))"#
    let minutes =
      #"\s*గంటల\s+(\d{1,2}|\#(teluguRoundCountWords))\s*(?:నిమిషాలకు|నిమిషాలకి|నిమిషాలకే|నిముషాలకు|నిముషాలకి)"#
    return
      #"\#(teluguStart)\#(teluguApproximate)\#(teluguPartLead(capturing: true))?(?<!(?:ప్రతి|ప్రతీ)\s{1,3})\#(hour)(?:\#(minutes)|\#(teluguHourEnding))\#(teluguTimeEnd)"#
  }

  static func teluguHourTime(_ match: Match) -> ClockTime? {
    var minute = match.group(3).flatMap(number) ?? 0
    let hour: Int
    if let text = match.group(2) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(4).map(teluguCompactKey), let count = teluguHourWords[word] {
      hour = count
    } else {
      return nil
    }
    if let text = match.group(5) {
      guard match.group(3) == nil,
        let value = number(text) ?? teluguRoundCounts[teluguCompactKey(text)], (0...59).contains(value)
      else { return nil }
      minute = value
    }
    let part = match.group(1).flatMap(teluguPartOfDay)
    return teluguClock(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(match.group(2) ?? ""), part: part, match: match)
  }

  /// "ఐదున్నరకు" (5:30), "ఐదున్నర గంటలకు", "ఒంటిగంటన్నరకు" (1:30), "సాయంత్రం
  /// ఐదున్నర", each maybe after "సరిగ్గా" or "సుమారు": an hour and a half on
  /// the clock face, as Apple's Telugu writes the half hours of its clock faces.
  /// The word is also a number ("ఐదున్నర కిలోలు"), so it is a time only with an
  /// ending or after a part of the day. Groups: 1 the part of the day, 2 the
  /// half-hour word, 3 the ending.
  static var teluguHalfTimePattern: String {
    let ending =
      #"(?:కు|కి|కే|\s*గంటల(?:కు|కి|కే)|\s*గంటల\s+(?:సమయంలో|సమయానికి|ప్రాంతంలో|ప్రాంతానికి))"#
    return
      #"\#(teluguStart)\#(teluguApproximate)\#(teluguPartLead(capturing: true))?(\#(teluguHalfWordPattern))(\#(ending))?\#(teluguTimeEnd)"#
  }

  static func teluguHalfTime(_ match: Match) -> ClockTime? {
    guard let word = match.group(2).map(teluguCompactKey), let hour = teluguHalfHours[word] else { return nil }
    let part = match.group(1).flatMap(teluguPartOfDay)
    guard part != nil || match.group(3) != nil else { return nil }
    return teluguClock(hour: hour, minute: 30, hasLeadingZero: false, part: part, match: match)
  }

  /// "సాయంత్రం 5కి", "రాత్రి 8కి", "ఉదయం 7కి", "5 PMకి", "సాయంత్రం ఐదింటికి": an
  /// hour that takes the dative "కి", "కు", or "కే" glued to it, after a part
  /// of the day or with AM or PM, since "5కి" alone may be a count or a date
  /// ("అక్టోబర్ 15కి"). The spoken dative hour words ("ఐదింటికి") are read only
  /// after a part of the day. Groups: 1 the part of the day, 2 the hour, 3 AM
  /// or PM, 4 a dative hour word.
  static var teluguDativeTimePattern: String {
    let meridiem = #"(?:\s*(am|pm|a\.m\.|p\.m\.)\s*)?"#
    return
      #"\#(teluguStart)\#(teluguApproximate)\#(teluguPartLead(capturing: true))?(?:(?<![\p{N}:.,/])(\d{1,2})\#(meridiem)·(?:కి|కు|కే)|(\#(teluguDativeHourWords)))\#(teluguTimeEnd)"#
  }

  static func teluguDativeTime(_ match: Match) -> ClockTime? {
    let part = match.group(1).flatMap(teluguPartOfDay)
    if let word = match.group(4).map(teluguCompactKey) {
      guard let part, let hour = teluguDativeHours[word] else { return nil }
      return teluguTimeWithPart(hour: hour, minute: 0, part: part)
    }
    guard let hour = match.group(2).flatMap(number) else { return nil }
    if let meridiem = match.group(3) {
      guard part == nil else { return nil }
      return teluguMeridiemTime(hour: hour, minute: 0, meridiem: meridiem)
    }
    guard let part else { return nil }
    return teluguTimeWithPart(hour: hour, minute: 0, part: part)
  }

  /// "ఉదయం 9:30", "రాత్రి 10.30", "17:30కి", "3:30 PMకి", "9:30 కి": a colon or
  /// dotted time with a part of the day before it, or with "కి", "కు", or "కే"
  /// after it, maybe with AM or PM between. A colon time with neither is left
  /// to English, which reads its own "17:30" and "3:30 PM" together with the
  /// words around them ("at 3:30 PM"). Groups: 1 the part of the day, 2 the
  /// hour, 3 the minutes, 4 AM or PM, 5 the dative.
  static var teluguColonTimePattern: String {
    let meridiem = #"(?:\s*(am|pm|a\.m\.|p\.m\.))?"#
    return
      #"\#(teluguStart)\#(teluguApproximate)\#(teluguPartLead(capturing: true))?(?<![\p{N}:.,/])(\d{1,2})[:.](\d{2})\#(meridiem)(?:\s*·(కి|కు|కే))?\#(teluguTimeEnd)"#
  }

  static func teluguColonTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(2).flatMap(number), let minute = match.group(3).flatMap(number) else { return nil }
    if let part = match.group(1).flatMap(teluguPartOfDay) {
      guard match.group(4) == nil else { return nil }
      return teluguTimeWithPart(hour: hour, minute: minute, part: part)
    }
    guard match.group(1) == nil, match.group(5) != nil else { return nil }
    if let meridiem = match.group(4) { return teluguMeridiemTime(hour: hour, minute: minute, meridiem: meridiem) }
    return teluguClock(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(match.group(2) ?? ""), part: nil, match: match)
  }

  /// "అర్ధరాత్రి", "అర్ధరాత్రికి", "ఈ అర్ధరాత్రి", "సరిగ్గా అర్ధరాత్రి", "మిడ్‌నైట్": the
  /// midnight that ends the day. "ఈ" goes with it so a day phrase does not
  /// leave it behind. "అర్ధరాత్రి వరకు" is a deadline and "అర్ధరాత్రి తర్వాత" a time
  /// after it, so neither is read. The loanword is a time only under the
  /// condition of ``teluguMidnightLoanword``: "మిడ్‌నైట్ బ్లూ" is a colour.
  static let teluguMidnightPattern =
    #"\#(teluguStart)(?:ఈ\s+)?(?:సరిగ్గా\s+)?(?:అర్ధరాత్రి|అర్థరాత్రి|అర్ధ\s*రాత్రి|\#(teluguMidnightLoanword))(?:కి|కు|కే)?\#(teluguEnd)(?!\s+\#(teluguMidnightBoundWords)\#(teluguEnd))"#

  // MARK: - Time range

  /// The side of a range, as a pattern: an hour in digits with maybe minutes,
  /// or an hour in words.
  private static var teluguRangeSide: String {
    #"((?<![\p{N}:.,/])\d{1,2}(?:[:.]\d{2})?|\#(teluguHourWordPattern))"#
  }

  /// The words between the two sides of a range: "నుండి", "నుంచి", or "నించి"
  /// between spaces, or a dash.
  private static let teluguRangeConnector = #"(?:\s+\#(teluguFromWords)\s+|\s*[-–—]\s*)"#

  /// What follows the end of a range: "వరకు", "వరకూ", or "దాకా", with "గంటల"
  /// before it or not, or "గంటలకు" or "గంటలకి".
  private static let teluguRangeTail = #"(?:(?:\s*గంటల)?\s+(?:వరకు|వరకూ|దాకా)|\s*గంటల(?:కు|కి))"#

  /// "9 నుండి 11 వరకు", "ఉదయం 9 నుండి 11 వరకు", "9 గంటల నుండి 11 గంటల వరకు",
  /// "మధ్యాహ్నం 2 నుండి సాయంత్రం 4 వరకు", "9-11 గంటలకు": two hours, in digits or
  /// words, joined by "నుండి" or a dash, with "వరకు" or "గంటలకు" after the end.
  /// Two bare numbers ("3 నుండి 5 వరకు") are as often an amount, so the range is
  /// read only with a part of the day or "గంటల" in it, or with colon minutes on
  /// a side, or right after a part of the day that a repeat or "ఈ" owns ("రోజూ
  /// ఉదయం 9 నుండి 11 వరకు"). Groups: 1 the part of the day before the start, 2
  /// the start, 3 the part before the end, 4 the end.
  static var teluguTimeRangePattern: String {
    #"\#(teluguStart)\#(teluguPartLead(capturing: true))?\#(teluguRangeSide)(?:\s*గంటల)?\#(teluguRangeConnector)\#(teluguPartLead(capturing: true))?\#(teluguRangeSide)\#(teluguRangeTail)\#(teluguTimeEnd)"#
  }

  /// "14:00 నుండి 16:00 వరకు", "9:30 నుంచి 10:30", "ఉదయం 9:00 నుండి సాయంత్రం
  /// 5:00 వరకు": a range of two colon times joined by "నుండి", maybe with
  /// "వరకు" after it. The same groups as ``teluguTimeRangePattern``. A range
  /// joined by a dash ("14:00-16:00") is English's.
  static var teluguColonTimeRangePattern: String {
    #"\#(teluguStart)\#(teluguPartLead(capturing: true))?((?<![\p{N}:.,/])\d{1,2}[:.]\d{2})\s+\#(teluguFromWords)\s+\#(teluguPartLead(capturing: true))?(\d{1,2}[:.]\d{2})(?:\s+(?:వరకు|వరకూ|దాకా))?+\#(teluguTimeEnd)"#
  }

  /// Whether a part of the day stands right before `match`, where the range's
  /// own lead did not take it because a repeat word or "ఈ" owns it ("రోజూ
  /// ఉదయం 9 నుండి 11 వరకు": "రోజూ ఉదయం" is the repeat, and the range is read
  /// in the part's half of the day).
  private static func teluguPartPrecedes(_ match: Match) -> Bool {
    let source = match.source
    guard let range = Range(match.result.range, in: source) else { return false }
    return teluguFinds(
      #"\#(teluguStart)(?:\#(teluguDayPartWords))\s+$"#, in: String(source[..<range.lowerBound]))
  }

  static func teluguTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(4) else { return nil }
    let isHours = match.group(0).map { teluguFinds("గంటల", in: $0) } ?? false
    guard
      match.group(1) != nil || match.group(3) != nil || isHours || startText.contains(":") || endText.contains(":")
        || teluguPartPrecedes(match)
    else { return nil }
    // A part of the day elsewhere in the line names the start's half of the day
    // (``teluguLinePartOfDay(beside:)``); the end is the first reading after the
    // start.
    guard
      let start = teluguRangeSideTime(startText, part: match.group(1), match: match, beside: match.group(1) == nil),
      let end = teluguRangeSideTime(endText, part: match.group(3), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func teluguRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = teluguHourWords[teluguCompactKey(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = teluguPartOfDay(part) else { return nil }
      return teluguTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = teluguTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// The words that make a clock time a bound: "లోగా", "లోపు", "లోపల", "కల్లా",
  /// "నాటికి" (by), "వరకు", "వరకూ", "దాకా" (until), and "తర్వాత", "తరువాత",
  /// "అనంతరం" (after) or "ముందు" and its emphatic "ముందే" (before).
  private static let teluguBoundWords =
    #"(?:లోగా|లోపు|లోపల|కల్లా|వరకు|వరకూ|దాకా|నాటికి|తర్వాత|తరువాత|ముంద(?:ు|ే)|అనంతరం)"#

  /// The clock times that bound a deadline, as a pattern without groups, each
  /// one saying by itself that it is a clock time: an hour with "గంటల" and a
  /// bound word ("5 గంటలలోగా", "5 గంటల లోపు", "5 గంటలకల్లా", "5 గంటల వరకు", "5
  /// గంటల తర్వాత"), an hour with the dative "గంటలకు" and "ముందు" ("5 గంటలకు
  /// ముందు": before 5 o'clock), a colon time with a bound word ("18:00
  /// వరకు"), and an hour with AM or PM and a bound word ("3 PM లోపు").
  static var teluguClockBound: String {
    let hour = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(teluguHourWordPattern)|\#(teluguHalfWordPattern))"#
    let meridiem = #"(?:am|pm|a\.m\.|p\.m\.)"#
    return
      #"(?:\#(hour)\s*గంటల(?:\s*\#(teluguBoundWords)|(?:కు|కి)\s+ముంద(?:ు|ే))|\d{1,2}[:.]\d{2}\s*(?:\#(meridiem)\s*)?\#(teluguBoundWords)|\d{1,2}(?::\d{2})?\s*\#(meridiem)\s*\#(teluguBoundWords))"#
  }

  /// An hour and a bound word with no "గంటల" between them, which is a clock
  /// time only after a part of the day ("సాయంత్రం 6 లోపు"), as a pattern
  /// without groups.
  private static var teluguBareBound: String {
    #"(?:\d{1,2}(?:[:.]\d{2})?|\#(teluguHourWordPattern)|\#(teluguHalfWordPattern))\s*\#(teluguBoundWords)"#
  }

  /// What follows the day of a due phrase that ends in a deadline clock, as a
  /// pattern without groups: a space, maybe a part of the day, and the clock
  /// bound ("శుక్రవారం సాయంత్రం 5 గంటలలోగా", "రేపు 18:00 వరకు").
  static var teluguClockBoundAfterDay: String {
    let lead = #"(?:\#(teluguDayPartWords))\s+\#(teluguApproximate)"#
    return
      #"\s+(?:\#(lead)(?:\#(teluguClockBound)|\#(teluguBareBound))|\#(teluguApproximate)\#(teluguClockBound))"#
  }

  /// A clock time written as a bound ("5 గంటలలోగా", "సాయంత్రం 6 లోపు", "5
  /// గంటల వరకు", "18:00 వరకు", "3 PM లోపు", "5 గంటల తర్వాత"), which names no
  /// start time. Group 1 is the bound, or nil for a range ("9 గంటల నుండి 11
  /// గంటల వరకు"), which the range rules read and this rule only steps over, so
  /// the "11 గంటల వరకు" inside it is not taken for a bound.
  static var teluguDeadlineClockPattern: String {
    let lead = teluguPartLead(capturing: false)
    let side = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(teluguHourWordPattern))"#
    let tail = #"(?:\s+(?:వరకు|వరకూ|దాకా)|\s*గంటల(?:కు|కి))"#
    let range =
      #"(?:\#(lead)?\#(side)(?:\s*గంటల)?\#(teluguRangeConnector)\#(lead)?\#(side)(?:\s*గంటల)?(?:\#(tail))?+|\#(lead)?\d{1,2}[:.]\d{2}\s+\#(teluguFromWords)\s+\#(lead)?\d{1,2}[:.]\d{2}(?:\s+(?:వరకు|వరకూ|దాకా))?+)"#
    let bound =
      #"(\#(teluguApproximate)(?:\#(lead)?\#(teluguClockBound)|\#(lead)\#(teluguBareBound)))"#
    return #"\#(teluguStart)(?:\#(range)|\#(bound))\#(teluguEnd)"#
  }
}
