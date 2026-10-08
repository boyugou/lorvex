import Foundation

extension LorvexCaptureVocabulary {
  // The Tamil clock-time rules: a time with "மணி", a half or a quarter hour, a
  // time with a part of the day and the dative, a colon time, a range of times,
  // and the rule that keeps a deadline written as a clock time in the title.
  // The vocabulary's other words are in ``tamil``.

  // MARK: - Parts of the day

  /// The words that name each part of the day, in the endings people type:
  /// the plain word ("காலை"), the locative ("காலையில்"), and the dative
  /// ("காலைக்கு"). அதிகாலை, விடியல், விடியற்காலை, and விடிகாலை are the small
  /// hours of the morning and முற்பகல் the forenoon; நண்பகல் and பகல் are the
  /// day, with மதியம், மத்தியானம், and பிற்பகல் the afternoon; சாயங்காலம் and
  /// சாயந்திரம் are other words for the evening, and the night includes
  /// ராத்திரி, நள்ளிரவு, and நடு இரவு. The loanword மிட்நைட் names the night
  /// too, under the condition of ``tamilMidnightLoanword``.
  private static let tamilPartForms: [(part: PartOfDay, words: [String])] = [
    (
      .morning,
      [
        "காலை", "காலையில்", "காலைக்கு", "அதிகாலை", "அதிகாலையில்", "அதிகாலைக்கு", "விடியல்", "விடியலில்", "விடியலுக்கு",
        "விடியற்காலை", "விடியற்காலையில்", "விடியற்காலைக்கு", "விடிகாலை", "விடிகாலையில்", "முற்பகல்", "முற்பகலில்",
        "முற்பகலுக்கு",
      ]
    ),
    (
      .day,
      [
        "மதியம்", "மதியத்தில்", "மதியத்திற்கு", "மதியத்துக்கு", "மத்தியானம்", "மத்தியானத்தில்", "மத்தியானத்திற்கு",
        "மத்தியானத்துக்கு", "நண்பகல்", "நண்பகலில்", "நண்பகலுக்கு", "பகல்", "பகலில்", "பகலுக்கு", "பிற்பகல்",
        "பிற்பகலில்", "பிற்பகலுக்கு",
      ]
    ),
    (
      .evening,
      [
        "மாலை", "மாலையில்", "மாலைக்கு", "சாயங்காலம்", "சாயங்காலத்தில்", "சாயங்காலத்திற்கு", "சாயங்காலத்துக்கு",
        "சாயந்திரம்", "சாயந்திரத்தில்", "சாயந்திரத்திற்கு", "சாயந்திரத்துக்கு",
      ]
    ),
    (
      .night,
      [
        "இரவு", "இரவில்", "இரவுக்கு", "ராத்திரி", "ராத்திரியில்", "ராத்திரிக்கு", "இராத்திரி", "இராத்திரியில்",
        "இராத்திரிக்கு", "நள்ளிரவு", "நள்ளிரவில்", "நள்ளிரவுக்கு", "நடு இரவு", "நடு இரவில்", "நடு இரவுக்கு",
        "நடு ராத்திரி", "நடு ராத்திரியில்", "நடு ராத்திரிக்கு",
      ]
    ),
  ]

  /// The words after a midnight that make it a bound or a point beside it:
  /// "நள்ளிரவு வரை" is a deadline and "நள்ளிரவுக்குப் பிறகு" a time after it. A
  /// pattern without groups.
  private static let tamilMidnightBoundWords =
    #"(?:வரைக்கும்|வரையில்|வரை|பிறகு|பின்னர்|பின்|முன்பாக|முன்பு|முன்னர்|முன்|மேல்)"#

  /// The loanword "மிட்நைட்" for midnight, spaced or joined, with no ending, as
  /// a pattern without groups. The system starts its colour names with it
  /// ("மிட்நைட் புளூ", "மிட்நைட் பிளாக்"; 6 of the 8 strings of Apple's Tamil
  /// that hold it), so it names the night only with a word of
  /// ``tamilMidnightBoundWords`` after it ("வெள்ளிக்கிழமை மிட்நைட் வரை") or with
  /// no other Tamil word after it ("கார் மிட்நைட்", "மிட்நைட் 12 மணிக்கு").
  private static let tamilMidnightLoanword =
    #"மிட்\s*நைட்(?!\s+(?!\#(tamilMidnightBoundWords)\#(tamilEnd))\p{Tamil})"#

  /// The forms of the parts of the day that stand before a noun ("மதிய உணவு",
  /// "சாயங்கால நடை"), which name the part a line is about but are not a part
  /// of a day phrase.
  private static let tamilPartAdjectives: [(part: PartOfDay, words: [String])] = [
    (.day, ["மதிய", "மத்தியான"]),
    (.evening, ["சாயங்கால", "சாயந்திர"]),
  ]

  /// The parts of the day with the ending "-உம்" ("ஒவ்வொரு காலையும்"), which
  /// stand in the words for every morning, evening, or night and name the part
  /// a line is about.
  private static let tamilPartInclusives: [(part: PartOfDay, words: [String])] = [
    (.morning, ["காலையும்", "அதிகாலையும்", "முற்பகலும்"]),
    (.day, ["மதியமும்", "மத்தியானமும்", "நண்பகலும்", "பகலும்", "பிற்பகலும்"]),
    (.evening, ["மாலையும்", "சாயங்காலமும்", "சாயந்திரமும்"]),
    (.night, ["இரவும்", "ராத்திரியும்", "நள்ளிரவும்"]),
  ]

  /// Each form of a part of the day as a key, with its part.
  private static let tamilPartByKey: [String: PartOfDay] = {
    var parts: [String: PartOfDay] = [:]
    for table in [tamilPartForms, tamilPartAdjectives, tamilPartInclusives] {
      for (part, words) in table {
        for word in words { parts[tamilCompactKey(word)] = part }
      }
    }
    parts[tamilCompactKey("மிட்நைட்")] = .night
    return parts
  }()

  /// The words that name a part of the day after a day word or before an hour,
  /// as a pattern without groups: the words of ``tamilPartForms`` longest
  /// first, then the loanword for midnight.
  static let tamilDayPartWords =
    tamilAlternation(of: tamilPartForms.flatMap { $0.words }) + "|" + tamilMidnightLoanword

  /// The parts of the day with "-உம்", as a pattern without groups.
  static let tamilPartInclusiveWords = tamilAlternation(of: tamilPartInclusives.flatMap { $0.words })

  /// The part of the day a matched word names. A word that the consonant
  /// doubled before the next word ends ("காலைக்" in "காலைக் கூட்டம்") names the
  /// part of the word without it.
  static func tamilPartOfDay(_ text: String) -> PartOfDay? {
    let key = tamilCompactKey(text)
    if let part = tamilPartByKey[key] { return part }
    var scalars = Array(key.unicodeScalars)
    guard scalars.count > 2, scalars.last == "\u{0BCD}" else { return nil }
    scalars.removeLast(2)
    return tamilPartByKey[String(String.UnicodeScalarView(scalars))]
  }

  /// The words that make a part of the day belong to a phrase of its own:
  /// the words for every day before it ("தினமும் காலை", "ஒவ்வொரு இரவு") and
  /// "இந்த" ("இந்த மாலை"). An hour after such a part takes its half of the day
  /// from the line instead of claiming the part, so the repeat or the day phrase
  /// keeps its words.
  private static let tamilPartOwner = #"(?:\#(tamilEveryOrDaily)|இந்த(?:க்)?)"#

  /// The words that may stand before an hour or after its part of the day,
  /// that make it approximate or exact.
  private static let tamilApproximate =
    #"(?:(?:சரியாக|துல்லியமாக|சுமார்|சுமாராக|கிட்டத்தட்ட|தோராயமாக|ஏறக்குறைய|அண்ணளவாக)\s+)?"#

  /// A part of the day before an hour, as a pattern: "காலை 9 மணிக்கு",
  /// "இரவு சரியாக 10 மணிக்கு". With `capturing`, the part's words are group 1
  /// of the lead. A part that "இந்த" or the words for every day stand before
  /// ("தினமும் காலை 6 மணிக்கு") belongs to that phrase, so the lead leaves it
  /// there and the hour takes its part from the line
  /// (``tamilLinePartOfDay(beside:)``).
  private static func tamilPartLead(capturing: Bool) -> String {
    let words = capturing ? "(\(tamilDayPartWords))" : "(?:\(tamilDayPartWords))"
    return #"(?:(?<!\#(tamilPartOwner)\s{1,3})\#(words)\s+\#(tamilApproximate))"#
  }

  /// The clock time `hour` and `minute` name with a part of the day, or nil for
  /// an hour no one says with it. The night counts from the evening ("இரவு 9
  /// மணிக்கு" is 9 PM): 6 to 11 o'clock is the evening, 12 the midnight that
  /// ends the day, and 1 to 5 the small hours after it
  /// (``nightTime(hour:minute:)``). The other parts follow
  /// ``partOfDayTime(hour:minute:part:)``.
  private static func tamilTimeWithPart(hour: Int, minute: Int, part: PartOfDay) -> ClockTime? {
    guard (0...59).contains(minute) else { return nil }
    return part == .night ? nightTime(hour: hour, minute: minute) : partOfDayTime(hour: hour, minute: minute, part: part)
  }

  // MARK: - The part of the day beside a time

  /// A part of the day anywhere in a line, as a pattern: the plain word, the
  /// locative, the dative, the form before a noun, or the form with "-உம்", as a
  /// whole word that the consonant doubled before the next word may end ("காலைக்
  /// கூட்டம்", "இரவுப் பணி"). "காலைக்குள்" and "மாலைப்பொழுது" are other words.
  private static let tamilLinePartPattern = tamil(
    #"\#(tamilStart)(?:\#(tamilDayPartWords)|\#(tamilLineOnlyPartWords))\#(tamilSandhi)\#(tamilEnd)"#)

  /// The adjective and "-உம்" forms of the parts of the day, as a pattern
  /// without groups.
  private static let tamilLineOnlyPartWords = tamilAlternation(
    of: (tamilPartAdjectives + tamilPartInclusives).flatMap { $0.words })

  /// The part of the day the line names outside `match`, for an hour written
  /// without one: "நாளை காலை கூட்டம் 6 மணிக்கு" and "ஒவ்வொரு காலையும் 6 மணிக்கு
  /// யோகா" are 06:00, and "இரவு உணவு 8 மணிக்கு" is 20:00, where the hour alone
  /// would be 18:00 and 08:00. Nil when the line names no part of the day, or
  /// names two that differ ("காலை டீ, மாலை ஸ்நாக்ஸ் 5 மணிக்கு").
  private static func tamilLinePartOfDay(beside match: Match) -> PartOfDay? {
    guard let regex = LorvexCapturePatterns.regex(tamilLinePartPattern) else { return nil }
    let source = match.source
    var named: PartOfDay?
    for found in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard NSIntersectionRange(found.range, match.result.range).length == 0,
        let range = Range(found.range, in: source), let part = tamilPartOfDay(String(source[range]))
      else { continue }
      if let named, named != part { return nil }
      named = part
    }
    return named
  }

  /// The clock time an hour on the 12-hour clock names with the part of the
  /// day its line names elsewhere, or nil when the hour is written on the
  /// 24-hour clock (a leading zero, 0, or 13 and later), the line names no part
  /// or two, or the part has no such hour ("காலை நடை 12 மணிக்கு").
  private static func tamilTimeWithLinePart(
    hour: Int, minute: Int, hasLeadingZero: Bool, match: Match
  ) -> ClockTime? {
    guard !hasLeadingZero, (1...12).contains(hour), let part = tamilLinePartOfDay(beside: match) else { return nil }
    return tamilTimeWithPart(hour: hour, minute: minute, part: part)
  }

  /// The clock time an hour names: with its own part of the day when it has
  /// one, else with the part the line names elsewhere, else as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` reads it.
  private static func tamilClock(
    hour: Int, minute: Int, hasLeadingZero: Bool, part: PartOfDay?, match: Match
  ) -> ClockTime? {
    if let part { return tamilTimeWithPart(hour: hour, minute: minute, part: part) }
    return tamilTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
      ?? bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  /// The time of an hour on the 12-hour clock with AM or PM written after it.
  private static func tamilMeridiemTime(hour: Int, minute: Int, meridiem: String) -> ClockTime? {
    guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
    let isAfternoon = meridiem.lowercased().hasPrefix("p")
    return ClockTime(minutes: ((hour % 12) + (isAfternoon ? 12 : 0)) * 60 + minute)
  }

  // MARK: - Clock words

  /// The words that follow an hour and make it a time by itself: "மணி" alone
  /// ("5 மணி"), with the dative ("5 மணிக்கு", "5 மணிக்கே"), or with a word that
  /// says "around" ("5 மணியளவில்", "5 மணி அளவில்", "5 மணி வாக்கில்") or "from"
  /// ("5 மணி முதல்", "5 மணியிலிருந்து"), as a pattern without groups. "மணி
  /// நேரம்" is the unit of a length ("5 மணி நேரம்"), so "மணி" is a clock word
  /// only where "நேரம்" does not follow. "2 மணி 30 நிமிடம்" with no ending after
  /// the minutes may be a time or a length, so its "மணி" is no clock word
  /// either, and neither is the "மணி" of "2 மணி, 30 நிமி". The minutes may be
  /// in digits or in words ("2 மணி முப்பது நிமிடம்"). The consonant that
  /// doubles before the next word may end the dative ("5 மணிக்குத்
  /// தொடங்கு").
  private static let tamilHourEnding =
    #"\s*மணி(?!\s*நேர)(?!,?\s+(?:\d{1,2}|\#(tamilRoundCountWords))\s*நிமி)(?:க்கு\#(tamilSandhi)|க்கே|யளவில்|\s+அளவில்|\s+வாக்கில்|\s+முதல்|யிலிருந்து|யில்\s+இருந்து)?"#

  /// The dative forms of the half-hour and quarter-hour words, which glue the
  /// ending to the word ("ஐந்தரைக்கு", "ஐந்தேகாலுக்கு"): a word that ends in a
  /// consonant takes "-உ" in place of its pulli before the ending.
  private static let tamilFractionDativeSpellings: [(hour: Int, minute: Int, words: [String])] =
    tamilFractionSpellings.map { row in
      (row.hour, row.minute, row.words.flatMap { word in tamilDatives(of: word) })
    }

  private static func tamilDatives(of word: String) -> [String] {
    var scalars = Array(word.unicodeScalars)
    if scalars.last == "\u{0BCD}" {
      scalars.removeLast()
      scalars.append("\u{0BC1}")
    }
    let base = String(String.UnicodeScalarView(scalars))
    return [base + "க்கு", base + "க்கே"]
  }

  /// The dative forms of the fraction words as keys, each with its hour and
  /// minutes.
  private static let tamilFractionDativeTimes: [String: (hour: Int, minute: Int)] = {
    var words: [String: (hour: Int, minute: Int)] = [:]
    for row in tamilFractionDativeSpellings {
      for word in row.words { words[tamilCompactKey(word)] = (row.hour, row.minute) }
    }
    return words
  }()

  // MARK: - Time

  /// "5 மணிக்கு", "5:30 மணிக்கு", "ஐந்து மணிக்கு", "5 மணி", "5 மணி 30
  /// நிமிடத்திற்கு", "மாலை 5 மணிக்கு", "இரவு 10 மணிக்கு", "5 மணியளவில்", each
  /// maybe after "சரியாக", "சுமார்", or a word of its kind. The hour takes
  /// "மணி", with or without an ending of ``tamilHourEnding``: "5 மணி நேரம்" is
  /// an amount of hours (a length), and a number without "மணி" is none of
  /// these. The hour may be followed by its minutes ("5 மணி 30 நிமிடத்திற்கு"
  /// is 5:30). An hour after "ஒவ்வொரு" ("ஒவ்வொரு 2 மணிக்கு") is no time. An
  /// hour with no part of the day of its own takes the one the line names
  /// elsewhere (``tamilLinePartOfDay(beside:)``), and otherwise reads as
  /// ``bareTime(hour:minute:hasLeadingZero:)`` does. Groups: 1 the part of the
  /// day before the hour, 2 the hour in digits, 3 its minutes after a colon, 4
  /// the hour in words, 5 the minutes written after "மணி".
  static var tamilHourPattern: String {
    let hour = #"(?:(?<![\p{N}:.,/])(\d{1,2})(?:[:.](\d{2}))?|(\#(tamilHourWordPattern)))"#
    let minutes =
      #"\s*மணி\s+(\d{1,2}|\#(tamilRoundCountWords))\s*(?:நிமிடத்துக்கு|நிமிடத்திற்கு|நிமிடங்களுக்கு|நிமிஷத்துக்கு|நிமிஷத்திற்கு)"#
    return
      #"\#(tamilStart)\#(tamilApproximate)\#(tamilPartLead(capturing: true))?(?<!ஒவ்வொரு\s{1,3})\#(hour)(?:\#(minutes)|\#(tamilHourEnding))\#(tamilTimeEnd)"#
  }

  static func tamilHourTime(_ match: Match) -> ClockTime? {
    var minute = match.group(3).flatMap(number) ?? 0
    let hour: Int
    if let text = match.group(2) {
      guard let value = number(text) else { return nil }
      hour = value
    } else if let word = match.group(4).map(tamilCompactKey), let count = tamilHourWords[word] {
      hour = count
    } else {
      return nil
    }
    if let text = match.group(5) {
      guard match.group(3) == nil,
        let value = number(text) ?? tamilRoundCounts[tamilCompactKey(text)], (0...59).contains(value)
      else { return nil }
      minute = value
    }
    let part = match.group(1).flatMap(tamilPartOfDay)
    return tamilClock(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(match.group(2) ?? ""), part: part, match: match)
  }

  /// "ஐந்தரை மணிக்கு" (5:30), "ஐந்தரைக்கு", "ஐந்தேகால் மணிக்கு" (5:15), "ஐந்தே
  /// முக்கால் மணிக்கு" (5:45), "ஒன்றரை மணி" (1:30), "மாலை ஐந்தரை", and the clock
  /// face "ஐந்து முப்பது மணி" (5:30), each maybe after "சரியாக" or "சுமார்": an
  /// hour and a half or a quarter on the clock, as spoken Tamil tells it. The
  /// words are also numbers ("ஐந்தரை கிலோ"), so they are a time only with "மணி"
  /// ("மணி நேரம்" is a length), with an ending glued to them, or after a part
  /// of the day. Groups: 1 the part of the day, 2 a fraction word, 3 its
  /// ending, 4 a fraction word with its dative, 5 the hour of a clock face.
  static var tamilWordTimePattern: String {
    let dative = tamilAlternation(of: tamilFractionDativeSpellings.flatMap { $0.words })
    let face = #"(\#(tamilCountingWordPattern))\s+முப்பது\s*மணி(?!\s*நேர)(?:க்கு\#(tamilSandhi)|க்கே)?"#
    return
      #"\#(tamilStart)\#(tamilApproximate)\#(tamilPartLead(capturing: true))?(?:(\#(tamilFractionWordPattern))(\#(tamilHourEnding))?|(\#(dative))\#(tamilSandhi)|\#(face))\#(tamilTimeEnd)"#
  }

  static func tamilWordTime(_ match: Match) -> ClockTime? {
    let part = match.group(1).flatMap(tamilPartOfDay)
    if let word = match.group(5).map(tamilCompactKey) {
      guard let hour = tamilCountingWords[word] else { return nil }
      return tamilClock(hour: hour, minute: 30, hasLeadingZero: false, part: part, match: match)
    }
    if let word = match.group(4).map(tamilCompactKey) {
      guard let time = tamilFractionDativeTimes[word] else { return nil }
      return tamilClock(hour: time.hour, minute: time.minute, hasLeadingZero: false, part: part, match: match)
    }
    guard let word = match.group(2).map(tamilCompactKey), let time = tamilFractionTimes[word] else { return nil }
    guard part != nil || match.group(3) != nil else { return nil }
    return tamilClock(hour: time.hour, minute: time.minute, hasLeadingZero: false, part: part, match: match)
  }

  /// "மாலை 5க்கு", "இரவு 8க்கு", "காலை 7க்கு", "5 PMக்கு", "மாலை ஐந்துக்கு": an
  /// hour that takes the dative "க்கு" or "க்கே" glued to it, after a part of
  /// the day or with AM or PM, since "5க்கு" alone may be a count or a date
  /// ("அக்டோபர் 15க்கு"). A hyphen may join the ending to the digits ("5-க்கு"),
  /// and the consonant that doubles before the next word may end it. The dative
  /// of an hour in words ("ஐந்துக்கு") is read only after a part of the day.
  /// Groups: 1 the part of the day, 2 the hour, 3 AM or PM, 4 an hour in words.
  static var tamilDativeTimePattern: String {
    let meridiem = #"(?:\s*(am|pm|a\.m\.|p\.m\.)\s*)?"#
    return
      #"\#(tamilStart)\#(tamilApproximate)\#(tamilPartLead(capturing: true))?(?:(?<![\p{N}:.,/])(\d{1,2})\#(meridiem)-?·(?:க்கு|க்கே)|(\#(tamilCountingWordPattern))(?:க்கு|க்கே))\#(tamilSandhi)\#(tamilTimeEnd)"#
  }

  static func tamilDativeTime(_ match: Match) -> ClockTime? {
    let part = match.group(1).flatMap(tamilPartOfDay)
    if let word = match.group(4).map(tamilCompactKey) {
      guard let part, let hour = tamilCountingWords[word] else { return nil }
      return tamilTimeWithPart(hour: hour, minute: 0, part: part)
    }
    guard let hour = match.group(2).flatMap(number) else { return nil }
    if let meridiem = match.group(3) {
      guard part == nil else { return nil }
      return tamilMeridiemTime(hour: hour, minute: 0, meridiem: meridiem)
    }
    guard let part else { return nil }
    return tamilTimeWithPart(hour: hour, minute: 0, part: part)
  }

  /// "காலை 9:30", "இரவு 10.30", "17:30க்கு", "9:30 மணிக்கு", "3:30 PMக்கு",
  /// "9:30 மணி": a colon or dotted time with a part of the day before it, or
  /// with "மணி" or the dative "க்கு" or "க்கே" after it, maybe with AM or PM
  /// between. A colon time with neither is left to English, which reads its own
  /// "17:30" and "3:30 PM" together with the words around them ("at 3:30 PM").
  /// Groups: 1 the part of the day, 2 the hour, 3 the minutes, 4 AM or PM, 5
  /// the ending.
  static var tamilColonTimePattern: String {
    let meridiem = #"(?:\s*(am|pm|a\.m\.|p\.m\.))?"#
    let ending =
      #"(\s*மணி(?!\s*நேர)(?:க்கு\#(tamilSandhi)|க்கே|யளவில்)?|-?·(?:க்கு|க்கே)\#(tamilSandhi))"#
    return
      #"\#(tamilStart)\#(tamilApproximate)\#(tamilPartLead(capturing: true))?(?<![\p{N}:.,/])(\d{1,2})[:.](\d{2})\#(meridiem)\#(ending)?\#(tamilTimeEnd)"#
  }

  static func tamilColonTime(_ match: Match) -> ClockTime? {
    guard let hour = match.group(2).flatMap(number), let minute = match.group(3).flatMap(number) else { return nil }
    if let part = match.group(1).flatMap(tamilPartOfDay) {
      guard match.group(4) == nil else { return nil }
      return tamilTimeWithPart(hour: hour, minute: minute, part: part)
    }
    guard match.group(1) == nil, match.group(5) != nil else { return nil }
    if let meridiem = match.group(4) { return tamilMeridiemTime(hour: hour, minute: minute, meridiem: meridiem) }
    return tamilClock(
      hour: hour, minute: minute, hasLeadingZero: startsWithZero(match.group(2) ?? ""), part: nil, match: match)
  }

  /// "நள்ளிரவு", "நள்ளிரவில்", "இந்த நள்ளிரவு", "சரியாக நள்ளிரவு", "நடு இரவில்",
  /// "மிட்நைட்": the midnight that ends the day. "இந்த" goes with it so a day
  /// phrase does not leave it behind. "நள்ளிரவு வரை" is a deadline and "நள்ளிரவுக்குப்
  /// பிறகு" a time after it, so neither is read. The loanword "மிட்நைட்" is
  /// also the first word of the system's colour names ("மிட்நைட் புளூ", "மிட்நைட்
  /// பிளாக்"), so it is a time only with an ending glued to it ("மிட்நைட்டில்")
  /// or under the condition of ``tamilMidnightLoanword``.
  static let tamilMidnightPattern =
    #"\#(tamilStart)(?:இந்த(?:க்)?\s+)?(?:சரியாக\s+)?(?:நள்ளிரவு(?:க்கு|க்கே)?|நள்ளிரவில்|நள்ளிரவே|நடு\s*இரவு(?:க்கு|க்கே)?|நடு\s*இரவில்|நடு\s*இரவே|நடு\s*ராத்திரி(?:க்கு|க்கே)?|நடு\s*ராத்திரியில்|நடு\s*ராத்திரியே|மிட்\s*நைட்(?:க்கு|டில்|டுக்கு|டிற்கு)|\#(tamilMidnightLoanword))\#(tamilEnd)(?!\s+\#(tamilMidnightBoundWords)\#(tamilEnd))"#

  // MARK: - Time range

  /// The side of a range, as a pattern: an hour in digits with maybe minutes,
  /// or an hour in words.
  private static var tamilRangeSide: String {
    #"((?<![\p{N}:.,/])\d{1,2}(?:[:.]\d{2})?|\#(tamilHourWordPattern))"#
  }

  /// What follows the start of a range and joins it to the end, as a pattern
  /// without groups: "முதல்" between spaces ("9 முதல் 11", "9 மணி முதல் 11"),
  /// "மணியிலிருந்து" ("9 மணியிலிருந்து 11"), or a dash ("9-11", "9 மணி - 11"). A
  /// "மணி" before them belongs to the start.
  private static let tamilRangeConnector =
    #"(?:\s*மணி(?:யிலிருந்து|யில்\s+இருந்து)\s+|(?:\s*மணி(?!\s*நேர))?(?:\s+முதல்\s+|\s*[-–—]\s*))"#

  /// What follows the end of a range, as a pattern without groups: "மணி" with
  /// "வரை", "வரைக்கும்", or "வரையில்", or with the dative, or alone, or "வரை"
  /// alone. "மணி நேரம்" is the unit of a length ("3 முதல் 5 மணி நேரம்").
  private static let tamilRangeTail =
    #"(?:\s*மணி(?!\s*நேர)(?:\s*(?:வரைக்கும்|வரையில்|வரை)|க்கு|க்கே)?|\s+(?:வரைக்கும்|வரையில்|வரை))"#

  /// "9 மணி முதல் 11 மணி வரை", "காலை 9 மணி முதல் 11 மணி வரை", "9 முதல் 11 மணி
  /// வரை", "மதியம் 2 மணி முதல் மாலை 4 மணி வரை", "9 மணியிலிருந்து 11 மணி வரை", "9-11
  /// மணிக்கு": two hours, in digits or words, joined by "முதல்" or a dash, with
  /// "மணி" or "வரை" after the end. Two bare numbers ("3 முதல் 5 வரை") are as often
  /// an amount, so the range is read only with a part of the day or "மணி" in it,
  /// or with colon minutes on a side, or right after a part of the day that a
  /// repeat or "இந்த" owns ("தினமும் காலை 9 முதல் 11 வரை"). Groups: 1 the part
  /// of the day before the start, 2 the start, 3 the part before the end, 4 the
  /// end.
  static var tamilTimeRangePattern: String {
    #"\#(tamilStart)\#(tamilPartLead(capturing: true))?\#(tamilRangeSide)\#(tamilRangeConnector)\#(tamilPartLead(capturing: true))?\#(tamilRangeSide)\#(tamilRangeTail)\#(tamilTimeEnd)"#
  }

  /// "14:00 முதல் 16:00 வரை", "9:30 முதல் 10:30", "காலை 9:00 முதல் மாலை 5:00
  /// வரை": a range of two colon times joined by "முதல்", maybe with "மணி" after
  /// each and "வரை" after the end. The same groups as
  /// ``tamilTimeRangePattern``. A range joined by a dash ("14:00-16:00") is
  /// English's.
  static var tamilColonTimeRangePattern: String {
    #"\#(tamilStart)\#(tamilPartLead(capturing: true))?((?<![\p{N}:.,/])\d{1,2}[:.]\d{2})(?:\s*மணி(?!\s*நேர))?\s+முதல்\s+\#(tamilPartLead(capturing: true))?(\d{1,2}[:.]\d{2})(?:\s*மணி(?!\s*நேர))?(?:\s+(?:வரைக்கும்|வரையில்|வரை))?+\#(tamilTimeEnd)"#
  }

  /// Whether a part of the day stands right before `match`, where the range's
  /// own lead did not take it because a repeat word or "இந்த" owns it ("தினமும்
  /// காலை 9 முதல் 11 வரை": "தினமும் காலை" is the repeat, and the range is read
  /// in the part's half of the day).
  private static func tamilPartPrecedes(_ match: Match) -> Bool {
    let source = match.source
    guard let range = Range(match.result.range, in: source) else { return false }
    return tamilFinds(
      #"\#(tamilStart)(?:\#(tamilDayPartWords))\s+$"#, in: String(source[..<range.lowerBound]))
  }

  static func tamilTimeRange(_ match: Match) -> ClockTime? {
    guard let startText = match.group(2), let endText = match.group(4) else { return nil }
    let isHours = match.group(0).map { tamilFinds("மணி", in: $0) } ?? false
    guard
      match.group(1) != nil || match.group(3) != nil || isHours || startText.contains(":") || endText.contains(":")
        || tamilPartPrecedes(match)
    else { return nil }
    // A part of the day elsewhere in the line names the start's half of the day
    // (``tamilLinePartOfDay(beside:)``); the end is the first reading after the
    // start.
    guard
      let start = tamilRangeSideTime(startText, part: match.group(1), match: match, beside: match.group(1) == nil),
      let end = tamilRangeSideTime(endText, part: match.group(3), match: match, beside: false)
    else { return nil }
    return timeRange(from: start, to: end)
  }

  /// One side of a time range: an hour with maybe minutes, with its part of the
  /// day when it has one (its own, or the one the line names elsewhere when
  /// `beside`).
  private static func tamilRangeSideTime(_ text: String, part: String?, match: Match, beside: Bool) -> ClockTime? {
    let hour: Int
    var minute = 0
    if let side = text.wholeMatch(of: /(\d{1,2})(?:[:.](\d{2}))?/), let value = number(side.output.1) {
      hour = value
      minute = side.output.2.flatMap { number($0) } ?? 0
    } else if let count = tamilHourWords[tamilCompactKey(text)] {
      hour = count
    } else {
      return nil
    }
    if let part {
      guard let kind = tamilPartOfDay(part) else { return nil }
      return tamilTimeWithPart(hour: hour, minute: minute, part: kind)
    }
    let hasLeadingZero = startsWithZero(text)
    if beside,
      let time = tamilTimeWithLinePart(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero, match: match)
    {
      return time
    }
    return bareTime(hour: hour, minute: minute, hasLeadingZero: hasLeadingZero)
  }

  // MARK: - Deadline written as a clock time

  /// The endings that glue a bound to a clock time: "க்குள்", "க்குள்ளாக",
  /// "க்குள்ளே" (by), and "க்கெல்லாம்" (by, at the latest).
  private static let tamilGluedBound = #"(?:க்குள்ளாக|க்குள்ளே|க்குள்|க்கெல்லாம்)"#

  /// The words that follow a clock time and make it a bound: "வரை",
  /// "வரைக்கும்", "வரையில்" (until), "பிறகு", "பின்னர்", "பின்", "மேல்", "மேலே"
  /// (after), and "முன்", "முன்பு", "முன்னர்", "முன்பாக", "முன்னதாக" (before).
  private static let tamilBoundWords =
    #"(?:முன்பாக|முன்னதாக|முன்பு|முன்னர்|முன்|பிறகு|பின்னர்|பின்|மேலே|மேல்|வரைக்கும்|வரையில்|வரை)"#

  /// A bound after a clock time, as a pattern without groups: a glued ending, or
  /// a word of ``tamilBoundWords`` after the dative or alone ("5 மணிக்குள்", "5
  /// மணிக்கு முன்", "5 மணிக்குப் பிறகு", "5 மணி வரை").
  private static var tamilBound: String {
    #"(?:\#(tamilGluedBound)|(?:க்கு\#(tamilSandhi))?\s*\#(tamilBoundWords))"#
  }

  /// The clock times that bound a deadline, as a pattern without groups, each
  /// one saying by itself that it is a clock time: an hour with "மணி" and a
  /// bound ("5 மணிக்குள்", "5 மணிக்கெல்லாம்", "5 மணி வரை", "5 மணிக்கு முன்", "5
  /// மணிக்குப் பிறகு"), a half or quarter hour with a bound ("ஐந்தரைக்குள்"), a
  /// colon time with a bound ("18:00 வரை", "18:00க்குள்"), and an hour with AM
  /// or PM and a bound ("3 PMக்குள்", "3 PM வரை").
  static var tamilClockBound: String {
    let hour = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(tamilHourWordPattern)|\#(tamilFractionWordPattern))"#
    let meridiem = #"(?:am|pm|a\.m\.|p\.m\.)"#
    return
      #"(?:\#(hour)\s*மணி(?!\s*நேர)\#(tamilBound)|(?:\#(tamilFractionWordPattern))\#(tamilBound)|\d{1,2}[:.]\d{2}\s*(?:\#(meridiem)\s*)?-?\#(tamilBound)|\d{1,2}(?::\d{2})?\s*\#(meridiem)\s*-?\#(tamilBound))"#
  }

  /// An hour and a bound with no "மணி" between them, which is a clock time only
  /// after a part of the day ("மாலை 6க்குள்", "மாலை 6 வரை"), as a pattern
  /// without groups.
  private static var tamilBareBound: String {
    #"(?:\d{1,2}(?:[:.]\d{2})?|\#(tamilHourWordPattern)|\#(tamilFractionWordPattern))(?:\#(tamilGluedBound)|(?:க்கு\#(tamilSandhi))?\s+\#(tamilBoundWords))"#
  }

  /// What follows the day of a due phrase that ends in a deadline clock, as a
  /// pattern without groups: a space, maybe a part of the day, and the clock
  /// bound ("வெள்ளிக்கிழமை மாலை 5 மணிக்குள்", "நாளை 18:00 வரை").
  static var tamilClockBoundAfterDay: String {
    let lead = #"(?:\#(tamilDayPartWords))\s+\#(tamilApproximate)"#
    return
      #"\s+(?:\#(lead)(?:\#(tamilClockBound)|\#(tamilBareBound))|\#(tamilApproximate)\#(tamilClockBound))"#
  }

  /// A clock time written as a bound ("5 மணிக்குள்", "மாலை 6க்குள்", "5 மணி
  /// வரை", "18:00 வரை", "3 PMக்குள்", "5 மணிக்குப் பிறகு"), which names no start
  /// time. Group 1 is the bound, or nil for a range ("9 மணி முதல் 11 மணி வரை"),
  /// which the range rules read and this rule only steps over, so the "11 மணி
  /// வரை" inside it is not taken for a bound.
  static var tamilDeadlineClockPattern: String {
    let lead = tamilPartLead(capturing: false)
    let side = #"(?:\d{1,2}(?:[:.]\d{2})?|\#(tamilHourWordPattern))"#
    let range =
      #"(?:\#(lead)?\#(side)\#(tamilRangeConnector)\#(lead)?\#(side)(?:\#(tamilRangeTail))?+|\#(lead)?\d{1,2}[:.]\d{2}(?:\s*மணி(?!\s*நேர))?\s+முதல்\s+\#(lead)?\d{1,2}[:.]\d{2}(?:\s*மணி(?!\s*நேர))?(?:\s+(?:வரைக்கும்|வரையில்|வரை))?+)"#
    let bound =
      #"(\#(tamilApproximate)(?:\#(lead)?\#(tamilClockBound)|\#(lead)\#(tamilBareBound)))"#
    return #"\#(tamilStart)(?:\#(range)|\#(bound))\#(tamilEnd)"#
  }
}
