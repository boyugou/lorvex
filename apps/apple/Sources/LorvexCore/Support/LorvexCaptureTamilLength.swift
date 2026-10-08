import Foundation

extension LorvexCaptureVocabulary {
  // MARK: - Length

  /// The hour nouns of a length, in the forms that stand after an amount:
  /// "மணி நேரம்" (one word or two), its plural, the dative ("2 மணி நேரத்திற்கு"
  /// is for 2 hours), and the stem before a noun ("2 மணி நேர கூட்டம்", "2 மணி
  /// நேரக் கூட்டம்"); "மணித்தியாலம்" is Sri Lanka's word for the same unit.
  private static let tamilHourNounWords = [
    "மணி நேரங்கள்", "மணி நேரம்", "மணி நேரத்திற்கு", "மணி நேரத்துக்கு", "மணி நேரக்", "மணி நேர", "மணித்தியாலங்கள்",
    "மணித்தியாலம்", "மணித்தியாலத்திற்கு", "மணித்தியாலத்துக்கு", "மணித்தியாலக்", "மணித்தியால",
  ]

  /// The minute nouns of a length, in the forms that stand after an amount.
  /// "நிமி" is the abbreviation, which the compact "நிமி." with its period
  /// leaves to ``tamilLengthPattern``'s compact form, so the bare abbreviation
  /// stands only where no period follows it.
  private static let tamilMinuteNounWords = [
    "நிமிடங்கள்", "நிமிடம்", "நிமிடங்களுக்கு", "நிமிடத்திற்கு", "நிமிடத்துக்கு", "நிமிடக்", "நிமிட", "நிமிஷங்கள்", "நிமிஷம்",
    "நிமிஷத்திற்கு", "நிமிஷத்துக்கு", "நிமிஷக்", "நிமிஷ", #"நிமி(?!\.)"#,
  ]

  /// "30 நிமிடங்கள்", "2 மணி நேரம்", "1.5 மணி நேரம்", "1 மணி நேரம் 30
  /// நிமிடங்கள்" (also "1 மணி நேரம், 30 நிமிடங்கள்", the system's "1 ம. 30
  /// நிமி.", and its "1 மணி, 30 நிமி"), "அரை மணி நேரம்", "ஒரு அரை மணி நேரம்",
  /// "கால் மணி", "முக்கால் மணி நேரம்", "ஒன்றரை மணி நேரம்", "இரண்டு மணி நேரம்",
  /// "இருபது நிமிடங்கள்", each maybe after "சுமார்" or "கிட்டத்தட்ட". The minutes
  /// after the hours of an amount with a unit may be in digits or in words ("ஒரு
  /// மணி நேரம் முப்பது நிமிடங்கள்", "1 மணி நேரம் 30 நிமிடங்கள்"), and "1 மற்றும்
  /// அரை மணிநேரம்" is an hour and a half. The unit may also stand in its dative
  /// ("30 நிமிடத்திற்கு" is for 30 minutes) or its form before a noun ("30 நிமிட
  /// கூட்டம்" is a meeting of 30 minutes). "மணி" alone is the hour of a length
  /// only with a comma and the minutes after it, since "2 மணி 30 நிமிடம்" may be
  /// a time as well; minutes that follow "மணி" with no comma ("2 மணி முப்பது
  /// நிமிடம்") are no length of their own.
  ///
  /// Groups: 1 a word that makes the length approximate; 2 a word that makes the
  /// amount a bound or a rate ("குறைந்தது 2 மணி நேரம்", "ஒவ்வொரு 2 மணி நேரம்",
  /// "ஒரு நாளைக்கு 2 மணி நேரம்"); 3 the hours of an amount with a unit and 4 its
  /// minutes; 5 minutes; 6 the hours and 7 the minutes of the system's
  /// abbreviations ("1 ம. 30 நிமி."); 8 minutes in that abbreviation ("30
  /// நிமி."); 9 the hours and 10 the minutes of "1 மணி, 30 நிமி"; 11 a length in
  /// words, which holds 12 the hours of an amount in words with a unit ("ஒரு மணி
  /// நேரம்"), 13 the minutes after them, and 14 the hours of "1 மற்றும் அரை
  /// மணிநேரம்"; 15 a word after the amount that makes it a moment, the past, a
  /// bound, or the start of a range ("2 மணி நேரம் கழித்து", "2 மணி நேரம் வரை",
  /// "5 நிமிடங்கள் முதல் 10 நிமிடங்கள்").
  ///
  /// A match with group 2 or 15 is no length: ``tamilDeclinesLength(_:)``
  /// declines it and a keep rule claims it, so the amount stays whole in the
  /// title. Any other ending glued to the unit ("2 மணி நேரத்தில்", "30
  /// நிமிடங்களில்") leaves the unit unread. The amount may not follow a digit, a
  /// colon, a slash, or a separator, and it may not be a side of a range ("2-3
  /// மணி நேரம்", "2 முதல் 3 மணி நேரம்").
  static var tamilLengthPattern: String {
    let hourNoun = "(?:\(tamilAlternation(of: tamilHourNounWords)))"
    let minuteNoun = "(?:\(tamilAlternation(of: tamilMinuteNounWords)))"
    let opener =
      #"(?:(?:(சுமார்|சுமாராக|கிட்டத்தட்ட|தோராயமாக|ஏறக்குறைய|அண்ணளவாக)|(குறைந்தது|குறைந்தபட்சம்|குறைந்தபட்சமாக|அதிகபட்சம்|அதிகபட்சமாக|ஒவ்வொரு|ஒரு\s*நாளைக்கு|நாளொன்றுக்கு|வாரத்திற்கு|வாரத்துக்கு|மாதத்திற்கு|மாதத்துக்கு))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,/])(?<!\p{N}\s?[-–—]\s?)"#
    let amount = tamilCountWords
    let roundAmount = tamilRoundCountWords
    let minutesAfterHours =
      #"(?:,?\s+(?:(?:மற்றும்|&)\s+)?(\d{1,2}|\#(roundAmount))\s*\#(minuteNoun))?"#
    let hours = #"(\d+(?:\.\d+)?)\s*\#(hourNoun)\#(minutesAfterHours)"#
    let minutes = #"(?<!மணி,?\s{1,3})(\d+)\s*\#(minuteNoun)"#
    let compact =
      #"(\d+)\s*(?:ம\.நே\.|ம\.)(?:\s*(\d{1,2})\s*(?:நிமி\.|நி\.))?|(\d+)\s*நிமி\.|(\d+)\s*மணி\s*,\s*(\d{1,2})\s*(?:நிமிடங்கள்|நிமிடம்|நிமி(?!\.))"#
    let words =
      #"((?:ஒரு\s+)?(?:அரை|கால்|முக்கால்)\s*மணி(?:\s*நேரம்)?|(?:\#(tamilHalfWordPattern))\s*\#(hourNoun)|((?:\#(amount))\s*\#(hourNoun))\#(minutesAfterHours)|(?<!மணி,?\s{1,3})(?:\#(roundAmount))\s*\#(minuteNoun)|\#(boundaries)(\d{1,2})\s+மற்றும்\s+அரை\s*மணி(?:\s*நேரம்)?)"#
    let trailing =
      #"(?:\s+(கழித்து|முன்பு|முன்னர்|முன்|பிறகு|பின்னர்|பின்|வரைக்கும்|வரை|முதல்|மேல்|கீழ்|குறைவாக|அதிகமாக|ஒருமுறை|ஒரு\s*முறை)\#(tamilEnd))?"#
    return
      #"\#(tamilStart)\#(opener)(?:\#(boundaries)(?:\#(hours)|\#(minutes)|\#(compact))|\#(words))\#(tamilEnd)(?!\s*[-–—]\s*\d)\#(trailing)"#
  }

  /// True for a match of ``tamilLengthPattern`` that is no length: a bound or
  /// a rate ("குறைந்தது 2 மணி நேரம்", "ஒரு நாளைக்கு 2 மணி நேரம்", "ஒரு
  /// மணிநேரத்திற்கு 5 மைல்கள்"), a moment, the past, or a bound ("2 மணி நேரம்
  /// கழித்து", "2 மணி நேரம் வரை"), or the end of a range of amounts ("2 முதல் 3
  /// மணி நேரம்").
  static func tamilDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(15) != nil || tamilIsRangeEnd(match) || tamilIsRate(match)
  }

  /// Whether `match` ends with "ஒரு" and a unit in its dative and a number or a
  /// placeholder comes right after it: "per hour" and "per minute" ("ஒரு
  /// மணிநேரத்திற்கு 5 மைல்கள்", "ஒரு நிமிடத்திற்கு 10 சுவாசங்கள்"), a rate and
  /// no length. A dative after a number in digits ("2 மணி நேரத்திற்கு 500
  /// ரூபாய்") is for that long and stays a length.
  private static func tamilIsRate(_ match: Match) -> Bool {
    guard let text = match.group(0), let end = Range(match.result.range, in: match.source)?.upperBound else {
      return false
    }
    let unit = #"ஒரு\s*(?:மணி\s*நேரத்|மணித்தியாலத்|நிமிடத்|நிமிஷத்)(?:திற்கு|துக்கு)$"#
    return tamilFinds(unit, in: text) && tamilFinds(#"^\s+[\d%]"#, in: String(match.source[end...]))
  }

  /// Whether the text before `match` ends with a number or a unit and "முதல்",
  /// which makes the amount the end of a range ("2 முதல் 3 மணி நேரம்").
  private static func tamilIsRangeEnd(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let before = String(match.source[..<start])
    return tamilFinds(#"(?:\d|நிமிடங்கள்|நிமிடம்|நேரம்|நேரங்கள்)\s+முதல்\s+$"#, in: before)
  }

  /// The minutes a match of ``tamilLengthPattern`` names, or nil when it names
  /// none: the match is declined (``tamilDeclinesLength(_:)``) or its amount in
  /// words is no amount the vocabulary lists.
  static func tamilLength(_ match: Match) -> Int? {
    if tamilDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(tamilMinuteCount) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    if let hours = match.group(6).flatMap(number) {
      return taskLength(minutes: hours * 60 + (match.group(7).flatMap(number) ?? 0))
    }
    if let minutes = match.group(8).flatMap(number) { return taskLength(minutes: minutes) }
    if let hours = match.group(9).flatMap(number) {
      return taskLength(minutes: hours * 60 + (match.group(10).flatMap(number) ?? 0))
    }
    if let hourPhrase = match.group(12).map(tamilPhrase) {
      guard let hours = tamilWordsLength(hourPhrase.replacingOccurrences(of: " ", with: "")) else { return nil }
      return taskLength(minutes: hours + (match.group(13).flatMap(tamilMinuteCount) ?? 0))
    }
    if let hours = match.group(14).flatMap(number) { return taskLength(minutes: hours * 60 + 30) }
    guard let phrase = match.group(11).map(tamilPhrase) else { return nil }
    return tamilWordsLength(phrase.replacingOccurrences(of: " ", with: ""))
  }

  /// The minutes a count after the hours of a length names, in digits ("30")
  /// or in words ("முப்பது").
  private static func tamilMinuteCount(_ text: String) -> Int? {
    number(text) ?? tamilRoundCounts[tamilCompactKey(text)]
  }

  /// The minutes a length written in words names: `phrase` is a phrase as
  /// ``tamilPhrase(_:)`` leaves it with its spaces taken out, an amount word or
  /// a fraction word before a unit, and "ஒரு" may stand before a half or a
  /// quarter ("ஒரு அரை மணிநேரம்" is half an hour).
  private static func tamilWordsLength(_ phrase: String) -> Int? {
    let compact = phrase.replacingOccurrences(
      of: #"^ஒரு(?=அரை|கால்|முக்கால்)"#, with: "", options: .regularExpression)
    switch compact {
    case tamilCompactKey("அரை மணி"), tamilCompactKey("அரை மணி நேரம்"): return 30
    case tamilCompactKey("கால் மணி"), tamilCompactKey("கால் மணி நேரம்"): return 15
    case tamilCompactKey("முக்கால் மணி"), tamilCompactKey("முக்கால் மணி நேரம்"): return 45
    default: break
    }
    let hourUnit = compact.replacingOccurrences(
      of: #"(?:மணிநேரங்கள்|மணிநேரத்திற்கு|மணிநேரத்துக்கு|மணிநேரம்|மணிநேரக்|மணிநேர|மணித்தியாலங்கள்|மணித்தியாலத்திற்கு|மணித்தியாலத்துக்கு|மணித்தியாலம்|மணித்தியாலக்|மணித்தியால)$"#,
      with: "", options: .regularExpression)
    if hourUnit != compact {
      if let half = tamilFractionTimes[hourUnit], half.minute == 30 { return taskLength(minutes: half.hour * 60 + 30) }
      return tamilCounts[hourUnit].flatMap { taskLength(minutes: $0 * 60) }
    }
    let minuteUnit = compact.replacingOccurrences(
      of: #"(?:நிமிடங்களுக்கு|நிமிடங்கள்|நிமிடத்திற்கு|நிமிடத்துக்கு|நிமிடம்|நிமிடக்|நிமிட|நிமிஷங்கள்|நிமிஷத்திற்கு|நிமிஷத்துக்கு|நிமிஷம்|நிமிஷக்|நிமிஷ|நிமி)$"#,
      with: "", options: .regularExpression)
    guard minuteUnit != compact else { return nil }
    return tamilRoundCounts[minuteUnit].flatMap { taskLength(minutes: $0) }
  }
}
