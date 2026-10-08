import Foundation

extension LorvexCaptureVocabulary {
  // The Tamil day rules: the planned day, the due day, written dates, and
  // date ranges. The vocabulary's other words are in ``tamil``.

  // MARK: - Weekday names

  /// Each weekday's forms, Sunday first, as pattern text: `name` the bare name
  /// the system writes ("திங்கள்"), `stems` the forms before "கிழமை"
  /// ("திங்கட்கிழமை", "திங்கள்கிழமை"), `dative` the bare name with its dative,
  /// `onThe` the bare name with "அன்று" glued to it, and `abbreviation` the
  /// short form the system writes with a period ("திங்.").
  private static let tamilWeekdayRows: [(name: String, stems: String, dative: String, onThe: String, abbreviation: String)] = [
    ("ஞாயிறு", "ஞாயிற்று|ஞாயிறு", "ஞாயிற்றுக்கு|ஞாயிறுக்கு", "ஞாயிறன்று|ஞாயிற்றன்று", #"ஞாயி\."#),
    ("திங்கள்", "திங்கள்|திங்கட்", "திங்களுக்கு", "திங்களன்று", #"திங்\."#),
    ("செவ்வாய்", "செவ்வாய்", "செவ்வாய்க்கு", "செவ்வாயன்று", #"செவ்\."#),
    ("புதன்", "புதன்", "புதனுக்கு", "புதனன்று", #"புத\."#),
    ("வியாழன்", "வியாழன்|வியாழ", "வியாழனுக்கு", "வியாழனன்று", #"வியா\."#),
    ("வெள்ளி", "வெள்ளி", "வெள்ளிக்கு", "வெள்ளியன்று", #"வெள்\."#),
    ("சனி", "சனி", "சனிக்கு", "சனியன்று", ""),
  ]

  /// The first letters that tell each weekday's words apart, as keys, with the
  /// weekday (0 = Sunday): every form of a name, with any ending, starts with
  /// them.
  private static let tamilWeekdayKeys: [(key: String, index: Int)] = [
    ("ஞாயி", 0), ("திங்", 1), ("செவ்", 2), ("புத", 3), ("வியா", 4), ("வெள்", 5), ("சனி", 6),
  ].map { (tamilKey($0.0), $0.1) }

  /// The weekday a word names, 0 = Sunday, with or without an ending glued to
  /// it ("திங்கட்கிழமை", "திங்களுக்கு", "வெள்ளியன்று").
  static func tamilWeekdayIndex(_ word: String) -> Int? {
    let key = tamilKey(word)
    return tamilWeekdayKeys.first(where: { tamilHasPrefix(key, $0.key) })?.index
  }

  /// The words after a bare weekday name that make it a planet or a metal
  /// ("செவ்வாய் கிரகம்", "வெள்ளி நகை"), not a day, as a pattern that fails
  /// where one follows. A name followed by "கிழமை" is always a day.
  static let tamilNotPlanet =
    #"(?!\s+(?:கிரக|கோள்|பகவான்|பெயர்ச்சி|தோஷ|நிறம்|நிறத்|நகை(?!ச்சுவை)|நாணய|கொலுசு|மோதிர|பாத்திர|விழா))"#

  /// A weekday name with "கிழமை" after it, as alternatives to put in a group:
  /// the stem, maybe the doubled க், maybe a space ("திங்கட்கிழமை", "வெள்ளிக்
  /// கிழமை", "வெள்ளி கிழமை").
  static var tamilWeekdayLong: String {
    tamilWeekdayRows.map { #"(?:\#($0.stems))(?:க்)?\s*கிழமை"# }.joined(separator: "|")
  }

  /// The stems that stand before "கிழமை", as alternatives to put in a group
  /// ("ஞாயிற்று", "ஞாயிறு", "திங்கள்", "திங்கட்").
  static var tamilWeekdayStems: String {
    tamilWeekdayRows.map(\.stems).joined(separator: "|")
  }

  /// The bare names, as alternatives to put in a group ("திங்கள்", "வெள்ளி").
  static var tamilWeekdayNames: String {
    tamilWeekdayRows.map(\.name).joined(separator: "|")
  }

  /// The bare names with the inclusive ending "-உம்" ("திங்களும்", "வெள்ளியும்",
  /// "ஞாயிறும்"), as alternatives to put in a group. A name that ends in a
  /// consonant with its pulli takes the vowel sign "ு" in place of it; a name
  /// that ends in "ு" takes "ம்", and one that ends in "ி" takes "யும்".
  static var tamilWeekdayBareInclusive: String {
    tamilWeekdayRows.map { tamilInclusiveForm(of: $0.name) }.joined(separator: "|")
  }

  private static func tamilInclusiveForm(of name: String) -> String {
    var scalars = Array(name.unicodeScalars)
    guard let last = scalars.last else { return name }
    if last == "\u{0BCD}" {
      scalars.removeLast()
      return String(String.UnicodeScalarView(scalars)) + "\u{0BC1}ம்"
    }
    return name + (last == "\u{0BC1}" ? "ம்" : "யும்")
  }

  /// The bare names and the short forms with a period, as a pattern without
  /// groups.
  private static var tamilWeekdayBareNames: String {
    (tamilWeekdayRows.map(\.name) + tamilWeekdayRows.map(\.abbreviation).filter { !$0.isEmpty }).joined(separator: "|")
  }

  /// A weekday as the plain name, without an ending: the long name or the bare
  /// name or its short form ("வெள்ளிக்கிழமை", "வெள்ளி", "வெள்."), as a pattern
  /// without groups. A bare name is read only where no planet or metal word
  /// follows.
  static var tamilWeekdayWord: String {
    #"(?:\#(tamilWeekdayLong)|(?:\#(tamilWeekdayBareNames))\#(tamilNotPlanet))"#
  }

  /// A weekday as the day phrases read it, as a pattern without groups: the
  /// plain name, the long name with "யே" (emphatic), "க்கு" (the day a task is
  /// planned for), "யன்று" or "யில்" (on that day), and the bare name with its
  /// dative or with "அன்று" glued to it ("வெள்ளிக்கு", "வெள்ளியன்று").
  static var tamilWeekdayForm: String {
    let datives = tamilWeekdayRows.map(\.dative).joined(separator: "|")
    let onThe = tamilWeekdayRows.map(\.onThe).joined(separator: "|")
    return
      #"(?:(?:\#(tamilWeekdayLong))(?:யே|யன்று|யில்|க்கு\#(tamilSandhi)|யிலிருந்து)?|(?:\#(tamilWeekdayBareNames)|(?:\#(datives))\#(tamilSandhi)|\#(onThe))\#(tamilNotPlanet))"#
  }

  /// A weekday with "க்குள்" or "க்குள்ளாக" (by that day), as a pattern without
  /// groups: "வெள்ளிக்கிழமைக்குள்", "வெள்ளிக்குள்", "திங்களுக்குள்ளாக".
  static var tamilWeekdayBound: String {
    let datives = tamilWeekdayRows.map(\.dative).joined(separator: "|")
    return
      #"(?:(?:\#(tamilWeekdayLong))க்குள்(?:ளாக)?|(?:\#(datives))ள்(?:ளாக)?\#(tamilNotPlanet))"#
  }

  // MARK: - Month names

  /// Each month's Gregorian names, January first: the full name in the
  /// spellings people type, and the short form the system writes with a period
  /// ("15 அக்."), which a month with no short form ("மே", "ஜூன்", "ஜூலை")
  /// stands for by its full name.
  private static let tamilMonthRows: [(full: [String], short: [String])] = [
    (["ஜனவரி"], ["ஜன"]),
    (["பிப்ரவரி", "பெப்ரவரி", "பிப்ருவரி"], ["பிப்"]),
    (["மார்ச்", "மார்ச்சு"], ["மார்"]),
    (["ஏப்ரல்", "ஏப்ரில்"], ["ஏப்"]),
    (["மே"], []),
    (["ஜூன்", "ஜுன்"], []),
    (["ஜூலை", "ஜுலை"], []),
    (["ஆகஸ்ட்", "ஆகஸ்டு", "ஆகஸ்ட்டு"], ["ஆக"]),
    (["செப்டம்பர்", "செப்டெம்பர்"], ["செப்"]),
    (["அக்டோபர்"], ["அக்"]),
    (["நவம்பர்"], ["நவ"]),
    (["டிசம்பர்"], ["டிச"]),
  ]

  /// The month names as keys, longest first, each with its month (0 =
  /// January).
  private static let tamilMonthKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (month, row) in tamilMonthRows.enumerated() {
      for name in row.full + row.short { keys.append((tamilKey(name), month)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The month a word names, 0 = January, with or without an ending glued to
  /// it.
  private static func tamilMonthIndex(_ word: String) -> Int? {
    let key = tamilKey(word)
    return tamilMonthKeys.first(where: { tamilHasPrefix(key, $0.key) })?.index
  }

  // MARK: - Dates

  /// The word for "date" that follows a day number ("15ஆம் தேதி"), as a pattern
  /// without groups.
  private static let tamilDateWord = #"தேதி"#

  /// The ordinal sign of a day number, glued to it or after a hyphen or a space
  /// ("15ஆம்", "15-ஆம்", "15ம்", "15ஆவது", "15வது"), as a pattern without
  /// groups.
  private static let tamilOrdinal = #"(?:\s*-?\s*(?:ஆம்|ஆவது|வது|ம்))"#

  /// A day number, plain ("15") or with its ordinal sign and the word for date
  /// ("15ஆம்", "15ஆம் தேதி"), as a pattern without groups.
  private static let tamilDayNumber = #"\d{1,2}(?:\#(tamilOrdinal)(?:\s*\#(tamilDateWord))?)?"#

  /// The label that may stand before a date.
  private static let tamilDateLabel = #"(?:\#(tamilDateWord)\s*[:：]?\s*)"#

  /// The words after a month and a day number that make the number an amount
  /// ("மே 10 ரூபாய்"), as a pattern that fails where one follows.
  private static let tamilNoAmountAfter =
    #"(?!\s*(?:ரூபாய்|ரூ|டாலர்|நிமிட|மணி|நாள்|நாட்|வார|மாத|வருட|ஆண்டு|பேர்|முறை|தடவை|கிலோ|%))"#

  /// "15 அக்டோபர்", "15ஆம் தேதி அக்டோபர்", "15 அக்டோபர் 2026", "15 அக்டோபர்,
  /// 2026", "15 அக்.", "அக்டோபர் 15", "அக்டோபர் மாதம் 15ஆம் தேதி", "அக். 15",
  /// "அக்டோபர் 15, 2026": a day number and a Gregorian month name, in either
  /// order, maybe with a year. A short month name is read only with its period,
  /// since it is a word's first letters too ("ஆக"). A month needs its day
  /// number, so "அக்டோபர்" alone is no date.
  static var tamilMonthDatePattern: String {
    let full = tamilAlternation(of: tamilMonthRows.flatMap { $0.full })
    let short = tamilAlternation(of: tamilMonthRows.flatMap { $0.short })
    let year = #"(?:,?\s+(?:19|20)\d{2}(?!\p{N}))?"#
    let month = #"(?:(?:\#(full))(?:\s*மாதம்)?|(?:\#(short))\.)"#
    return
      #"(?:\#(tamilDayNumber)\s*\#(month)\#(year)|\#(month)\s*\#(tamilDayNumber)\#(tamilNoMoreDigits)\#(tamilNoAmountAfter)\#(year))"#
  }

  /// The words for a month of the calendar before a day of the month ("அடுத்த
  /// மாதம் 5ஆம் தேதி"), as a lookbehind that fails where one stands. A day of
  /// the month with no month of its own is the next such day, which is not the
  /// day of the month the words name when it falls in the month that is
  /// running, so the phrase stays unread whole.
  private static let tamilNoMonthWordBefore =
    #"(?<!(?:அடுத்த|வரும்|வருகிற|இந்த|கடந்த|சென்ற|போன|முந்தைய)\s{1,3}மாத(?:ம்|த்தின்)\s{1,3})"#

  /// "15ஆம் தேதி", "15 தேதி": a day of the month with no month, the stem of the
  /// phrase for "on the 15th" ("15ஆம் தேதியன்று") or "from the 15th".
  private static let tamilDayOfMonthStem =
    #"\#(tamilNoMonthWordBefore)\d{1,2}(?:\#(tamilOrdinal))?\s*\#(tamilDateWord)"#

  /// The endings that go with a date: "க்கு" (for) or "இல்" glued to a day
  /// number or to "தேதி" ("15க்கு", "15இல்", "தேதிக்கு", "தேதியில்"), "யன்று"
  /// glued to "தேதி", and "அன்று" or "முதல்" as words of their own, as a
  /// pattern without groups.
  private static let tamilDateEnding =
    #"(?:(?:-?·(?:க்கு|இல்)|யில்|யன்று)\#(tamilSandhi)|\s+(?:அன்று|முதல்))"#

  /// The weekday the system writes after a long date ("15 அக்டோபர், 2026,
  /// வியாழன்"), as a pattern without groups.
  private static var tamilWeekdayAfterDate: String {
    #"(?:\s*,\s*\#(tamilWeekdayWord))"#
  }

  /// A date in digits that is a date wherever it stands: with a four-digit year
  /// ("15/10/2026", "15.10.2026", "15-10-2026") or with the dot that closes the
  /// month ("15.10.").
  private static let tamilStrictNumericDate =
    #"(?:\#(numericDateWithYear)|(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?![\p{N}]|[.,/]\p{N}))"#

  /// A planned day written as a date, as a pattern without groups: a day and a
  /// month name with its optional weekday, label, year, and ending ("வியாழன்,
  /// 15 அக்டோபர்", "தேதி 15 அக்டோபர்", "அக்டோபர் 15இல்", "15 அக்டோபர் 2026
  /// முதல்"), a day of the month with its ending ("15ஆம் தேதியன்று"), a date in
  /// digits with a year or a closing dot, and a date in digits with only a day
  /// and a month ("15/10"), which is as often a score, a fraction, or a time, so
  /// it is read only after a label or before an ending.
  private static var tamilPlannedDate: String {
    let month =
      #"\#(tamilDateLabel)?(?:\#(tamilWeekdayWord)\s*,?\s+)?\#(tamilMonthDatePattern)\#(tamilWeekdayAfterDate)?\#(tamilDateEnding)?"#
    let dayOfMonth = #"\#(tamilDateLabel)?\#(tamilDayOfMonthStem)\#(tamilDateEnding)?"#
    let strict = #"\#(tamilDateLabel)?\#(tamilStrictNumericDate)\#(tamilDateEnding)?"#
    let looseLabeled = #"\#(tamilDateLabel)\#(numericDateWithoutYear)\#(tamilDateEnding)?"#
    let looseEnded = #"\#(numericDateWithoutYear)\#(tamilDateEnding)"#
    return "\(month)|\(dayOfMonth)|\(strict)|\(looseLabeled)|\(looseEnded)"
  }

  /// A written-out date: "15 அக்டோபர்", "15ஆம் தேதி அக்டோபர் 2026", "அக்டோபர் 15",
  /// "15ஆம் தேதியன்று". The words are a phrase as ``tamilPhrase(_:)`` leaves
  /// it. A day number with a month name names a date; with the word for date it
  /// names a day of the month.
  static func tamilDate(_ words: String) -> ExplicitDate? {
    let runs = tamilRuns(words)
    let numbers = runs.compactMap { run in number(run).map { (run: run, value: $0) } }
    guard let day = numbers.first(where: { $0.run.count <= 2 && (1...31).contains($0.value) })?.value else {
      return nil
    }
    let year = numbers.first(where: { $0.run.count == 4 && (1900...2099).contains($0.value) })?.value
    let names = runs.filter { number($0) == nil && tamilWeekdayIndex($0) == nil }
    if let month = names.lazy.compactMap(tamilMonthIndex).first {
      return ExplicitDate(year: year, month: month + 1, day: day)
    }
    if names.contains(where: { tamilHasPrefix($0, tamilKey("தேதி")) }) { return ExplicitDate(day: day) }
    return nil
  }

  // MARK: - The words around a day

  /// The words before a weekday that make it this week's ("இந்த"), the coming
  /// one ("வரும்", "வருகிற"), or next week's ("அடுத்த"; weeks start on Monday).
  /// A week word between them and the weekday ("வரும் வாரம் திங்கள்") makes
  /// the coming words next week's too.
  private static let tamilThisWords: Set<String> = Set(["இந்த"].map(tamilKey))
  private static let tamilComingWords: Set<String> = Set(["வரும்", "வருகிற"].map(tamilKey))
  private static let tamilNextWords: Set<String> = Set(["அடுத்த"].map(tamilKey))

  /// The week words that stand between a modifier and a weekday, as keys.
  private static let tamilWeekWords: Set<String> = Set(
    ["வாரம்", "வாரத்தில்", "வாரத்திற்கு", "வாரத்துக்கு"].map(tamilKey))

  /// `word`, a word of a matched phrase or the word before it, without the
  /// consonant that doubles after a modifier before a word that starts with
  /// it: "இந்தச்" is "இந்த", "அந்தச்" is "அந்த", "எல்லாச்" is "எல்லா". Any other
  /// word comes back as it is.
  private static func tamilWithoutDoubling(_ word: String) -> String {
    let consonants = ["க்", "ச்", "த்", "ப்"].map(tamilKey)
    for modifier in tamilThisWords.union(tamilNextWords).union(tamilNotComingModifiers) {
      for consonant in consonants where word == modifier + consonant { return modifier }
    }
    return word
  }

  /// The words that may stand before a weekday, as a pattern: "இந்த" (which a
  /// doubled consonant may follow: "இந்தச் சனிக்கிழமை"), "வரும்", "வருகிற",
  /// and "அடுத்த".
  private static let tamilModifier =
    #"(?:(?:(?:இந்த|அடுத்த)\#(tamilSandhi)|வரும்|வருகிற)\s+)"#

  /// "வாரம்" or "வாரத்தில்" between a modifier and a weekday ("வரும் வாரம்
  /// திங்கள்"), as a pattern.
  private static let tamilWeekWordBeforeWeekday = #"(?:வாரம்|வாரத்தில்)"#

  /// The weekend: "வார இறுதி", "வாரயிறுதி", "வீக்கெண்ட்", or Saturday and
  /// Sunday together ("சனி ஞாயிறு", "சனி மற்றும் ஞாயிறு", "சனிக்கிழமை,
  /// ஞாயிற்றுக்கிழமை"), with the dative or the locative after the first
  /// words. "வீக்கெண்ட்" takes its endings as a Tamil word ending in ட் does
  /// ("வீக்கெண்டில்", "வீக்கெண்டுக்கு") or fused to the loan word.
  static let tamilWeekendWords =
    #"(?:(?:வார\s*இறுதி|வாரயிறுதி|வாரஇறுதி)(?:யில்|க்கு)?|(?:வீக்கெண்|வீக்எண்|வீகெண்)(?:ட்(?:·(?:இல்|க்கு))?|டில்|டுக்கு)|(?:சனிக்கிழமை|சனி)\s*(?:மற்றும்|&|,|-)?\s*(?:ஞாயிற்றுக்கிழமை|ஞாயிறுக்கிழமை|ஞாயிறு))"#

  /// The words before a day phrase that make it no coming day: the past ("கடந்த
  /// வெள்ளிக்கிழமை", "சென்ற திங்கள்", "போன புதன்"), "அந்த" (which points back
  /// at a day already named), the last of a month ("கடைசி வெள்ளிக்கிழமை"), an
  /// ordinal ("முதல் வெள்ளிக்கிழமை" is the month's first Friday), and the
  /// words for a Friday that is any or every one ("ஒரு", "ஒவ்வொரு", "எந்த").
  private static let tamilNotComingModifiers: Set<String> = Set(
    [
      "கடந்த", "சென்ற", "போன", "முந்தைய", "முந்திய", "அந்த", "கடைசி", "இறுதி", "முதல்", "இரண்டாவது", "மூன்றாவது",
      "நான்காவது", "ஐந்தாவது", "ஒரு", "ஒவ்வொரு", "எந்த", "எல்லா",
    ].map(tamilKey))

  /// The stems of the past-tense verbs that put a line in the past, each ending
  /// in the pulli that the person endings replace: "செய்த்" gives "செய்தேன்",
  /// "செய்தது", "செய்தார்". The words of a deadline that has passed ("முடிந்தது",
  /// "கடந்தது", "தாண்டியது", "மீறியது") are among them, so a day beside them is
  /// read as no plan.
  private static let tamilPastStems = [
    "செய்த்", "சென்ற்", "வந்த்", "போன்", "முடித்த்", "முடிந்த்", "நடந்த்", "பார்த்த்", "அனுப்பின்", "அனுப்பிய்",
    "கொடுத்த்", "வாங்கின்", "வாங்கிய்", "படித்த்", "எழுதின்", "எழுதிய்", "சந்தித்த்", "பேசின்", "பேசிய்", "சொன்ன்",
    "கேட்ட்", "கட்டின்", "கடந்த்", "தாண்டின்", "தாண்டிய்", "மீறின்", "மீறிய்", "இருந்த்", "ஆன்", "ஆகிவிட்ட்",
    "முடிந்துவிட்ட்", "கடந்துவிட்ட்", "தாண்டிவிட்ட்", "மீறிவிட்ட்", "செய்துவிட்ட்", "சென்றுவிட்ட்", "வந்துவிட்ட்",
  ]

  /// The endings of the first person ("-ஏன்", "-ஓம்"), the second ("-ஆய்",
  /// "-ீர்கள்"), and the third ("-ஆன்", "-ஆள்", "-ஆர்", "-ஆர்கள்", "-அது",
  /// "-அன", "-அனர்"), which a past stem takes in place of its pulli.
  private static let tamilPastEndings = [
    "\u{0BC7}ன்", "\u{0BCB}ம்", "\u{0BBE}ய்", "\u{0BBE}ன்", "\u{0BBE}ள்", "\u{0BBE}ர்", "\u{0BBE}ர்கள்", "\u{0BC0}ர்கள்", "\u{0BC0}ர்",
    "து", "ன", "னர்",
  ]

  /// The past-tense forms as keys: the stems with each ending.
  private static let tamilPastMarkers: Set<String> = {
    var markers: Set<String> = []
    for stem in tamilPastStems {
      let base = String(stem.unicodeScalars.dropLast())
      for ending in tamilPastEndings { markers.insert(tamilKey(base + ending)) }
    }
    return markers
  }()

  /// Whether `match` names a day that is no coming one: a word that makes it
  /// past or ordinal comes before it ("கடந்த வெள்ளிக்கிழமை", "முதல்
  /// வெள்ளிக்கிழமை"), or the line is in the past tense ("நாளை கூட்டம்
  /// நடந்தது"). "முதல்" after a day is no ordinal: it says "from", and the day
  /// after it ends the span ("நாளை முதல் வெள்ளி வரை", "15ஆம் தேதி முதல் 17ஆம்
  /// தேதி வரை").
  static func tamilIsNotComing(_ match: Match) -> Bool {
    if let before = tamilWordBefore(match).map(tamilWithoutDoubling), tamilNotComingModifiers.contains(before),
      !(before == tamilKey("முதல்") && tamilFollowsDayFrom(match))
    {
      return true
    }
    return tamilWords(in: match.source).contains(where: tamilPastMarkers.contains)
  }

  /// Whether the words before `match` end with a day and "முதல்": today,
  /// tomorrow, a weekday, a day of the month, or a number (the day of a date).
  private static func tamilFollowsDayFrom(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let day = #"(?:\#(tamilToday)|\#(tamilDueTomorrow)|\#(tamilWeekdayWord)|தேதி|\d)"#
    return tamilFinds(#"\#(tamilStart)\#(day)\s+முதல்\s+$"#, in: String(match.source[..<start]))
  }

  /// The words that mean "until" after a day, as a pattern without groups.
  private static let tamilUntilWords = #"(?:வரைக்கும்|வரையில்|வரை)"#

  /// The words that follow a day phrase and make it a point of reference, not a
  /// plan: "வெள்ளிக்கு முன்" (before Friday), "வெள்ளிக்குப் பிறகு" (after it),
  /// as a pattern that fails where one follows.
  private static let tamilNotPointOfReference =
    #"(?!\s+(?:முன்பாக|முன்பு|முன்னர்|முன்|பிறகு|பின்னர்|பின்|மேல்|கழித்து)\#(tamilEnd))"#

  // MARK: - Planned day

  /// A part of the day after a day word, as a phrase: "நாளை காலை", "வெள்ளி
  /// மாலை", "நாளைக் காலை". The words that go with it are ``tamilDayPartWords``.
  private static var tamilPartPhrase: String {
    #"\#(tamilSandhi)\s+(?:\#(tamilDayPartWords))\#(tamilEnd)"#
  }

  /// Today, with its endings, as a pattern without groups: "இன்று", "இன்றே",
  /// "இன்றைக்கு", "இன்னைக்கு", "இன்னிக்கு", "இன்றிலிருந்து". The dative may
  /// take the consonant that doubles before the next word ("இன்றைக்குத்
  /// தொடங்கு").
  private static let tamilToday =
    #"(?:இன்று|இன்றே|இன்றைக்கு\#(tamilSandhi)|இன்றைக்கே|இன்னைக்கு\#(tamilSandhi)|இன்னைக்கே|இன்னிக்கு\#(tamilSandhi)|இன்னிக்கே|இன்றிலிருந்து)"#

  /// Tonight, a word of its own: "இன்றிரவு", "இன்றிரவே", "இன்றிரவுக்கு".
  private static let tamilTonight = #"(?:இன்றிரவு|இன்றிரவே|இன்றிரவுக்கு)"#

  /// Tomorrow, with its endings, as a pattern without groups: "நாளை", "நாளையே",
  /// "நாளைக்கு", "நாளையிலிருந்து". The consonant that doubles before a word
  /// starting with the same one ("நாளைக் காலை") also stands as the word's end
  /// when that word has been taken out ("நாளைக்" in "நாளைக் ஜிம்"). "நாளை" is
  /// also a form of "நாள்" (day), so a reader takes it as tomorrow only where no
  /// number or determiner stands before it (``tamilIsDayWord(_:)``).
  private static let tamilTomorrow =
    #"(?:நாளையிலிருந்து|நாளைக்கு\#(tamilSandhi)|நாளைக்கே|நாளையே|நாளைக்(?=\s|$)|நாளை)"#

  /// The day after tomorrow, with its endings: "நாளை மறுநாள்", "நாளைமறுநாள்",
  /// "நாளை மறுநாளே", "நாளை மறுநாளுக்கு", "நாளை மறுதினம்".
  private static let tamilDayAfter =
    #"நாளை\s*மறு(?:நாளுக்கு\#(tamilSandhi)|நாளுக்கே|நாளே|நாள்|தினத்திற்கு|தினத்துக்கு|தினம்)"#

  /// Today's part of the day after "இந்த": "இந்த இரவு", "இந்த மாலை", "இந்தக்
  /// காலை", which names today's part.
  private static var tamilThisPart: String {
    #"(?:இந்த\#(tamilSandhi)\s+(?:\#(tamilDayPartWords)))"#
  }

  /// The words after a counted amount of days, weeks, or months that make it a
  /// day: "நாட்களில்", "நாட்களுக்குப் பிறகு", "நாட்கள் கழித்து", and the likes,
  /// as a pattern without groups. The dative may or may not double its
  /// consonant before "பிறகு", and "கழித்து" may take the consonant that doubles
  /// before the next word ("ஒரு நாள் கழித்துத் திட்டமிடு").
  private static let tamilCountedUnits =
    #"(?:நாட்களில்|நாளில்|வாரங்களில்|வாரத்தில்|மாதங்களில்|மாதத்தில்|(?:நாட்களுக்கு|நாளுக்கு|வாரங்களுக்கு|வாரத்திற்கு|வாரத்துக்கு|மாதங்களுக்கு|மாதத்திற்கு|மாதத்துக்கு)(?:ப்)?\s+(?:பிறகு|பின்னர்|பின்)|(?:நாட்கள்|நாள்|வாரங்கள்|வாரம்|மாதங்கள்|மாதம்)\s+கழித்து\#(tamilSandhi))"#

  /// The words that make "நாளை" a form of "நாள்" (day) and no tomorrow when they
  /// stand before it: a determiner or a numeral ("இந்த நாளை", "ஒரு நாளைக்கு"
  /// is per day, "1 நாளைக்கு முன்பு" is a day before).
  private static let tamilDayWordDeterminers: Set<String> = Set(
    [
      "ஒரு", "ஒவ்வொரு", "இந்த", "அந்த", "எந்த", "இன்னொரு", "ஒரே", "பல", "சில", "இரு", "இரண்டு", "மூன்று", "நான்கு",
      "ஐந்து", "ஆறு", "ஏழு", "எட்டு", "ஒன்பது", "பத்து", "முதல்", "கடைசி", "அடுத்த", "மறு",
    ].map(tamilKey))

  /// Whether "நாளை" or "நாளைக்கு" in `match` is a form of "நாள்" (day): a
  /// numeral or a determiner stands before it. "முதல்" after a day says
  /// "from" ("இன்று முதல் நாளை வரை") and is no determiner there.
  private static func tamilIsDayWord(_ match: Match) -> Bool {
    if tamilFollowsNumber(match) { return true }
    guard let before = tamilWordBefore(match), tamilDayWordDeterminers.contains(before) else { return false }
    return !(before == tamilKey("முதல்") && tamilFollowsDayFrom(match))
  }

  /// Group 1: the day, with the ending that goes with it; groups 2 and 3: the
  /// count and the unit of a number of days, weeks, or months.
  ///
  /// Today ("இன்று", "இன்றைக்கு"), tomorrow ("நாளை"), the day after ("நாளை
  /// மறுநாள்"), each maybe with a part of the day ("இன்று இரவு", "நாளை
  /// காலை") or an ending ("நாளையே", "நாளைக்கு", "நாளை முதல்", "நாளையிலிருந்து");
  /// tonight ("இன்றிரவு"); today's part of the day ("இந்த மாலை"); a number of
  /// days, weeks, or months ("3 நாட்களில்", "இரண்டு வாரங்களுக்குப் பிறகு", "1
  /// மாதம் கழித்து"); a weekday, alone or after "இந்த", "வரும்", "வருகிற", or
  /// "அடுத்த", maybe with "வாரம்" between ("வெள்ளிக்கு", "இந்த வெள்ளிக்கிழமை",
  /// "அடுத்த வாரம் திங்கள்"), maybe with "அன்று" and a part of the day after it;
  /// next week ("அடுத்த வாரம்"); the weekend; and a date
  /// (``tamilPlannedDate``). A day word or weekday may be followed by "முதல்"
  /// ("திங்கள் முதல் ஜிம்" plans Monday), unless that "முதல்" starts a counted
  /// day. A weekday with any ending this pattern does not list ("வெள்ளிக்கிழமையின்
  /// கூட்டம்") is no planned day, and neither is a day that "வரை" follows
  /// ("இன்று வரை" means "so far", and "வெள்ளிக்கிழமை வரை" is a deadline that
  /// ``tamilDuePattern`` reads first) or that "முன்", "பிறகு", or a word of its
  /// kind follows ("வெள்ளிக்கு முன்": a day of reference, no plan).
  static var tamilWhenPattern: String {
    let counted = #"(?:(\d{1,3}|\#(tamilRoundCountWords))\s*(\#(tamilCountedUnits)))"#
    let from = #"(?:\s+முதல்)?"#
    let notFromCount =
      #"(?!\s+முதல்\s+(?:\d{1,3}|\#(tamilRoundCountWords))\s*\#(tamilCountedUnits))"#
    let relative =
      #"(?:\#(tamilToday)|\#(tamilTonight)|\#(tamilDayAfter)|\#(tamilTomorrow))\#(notFromCount)(?:\#(tamilPartPhrase))?\#(from)"#
    let thisPart = #"\#(tamilThisPart)\#(notFromCount)\#(from)"#
    let weekday =
      #"(?:\#(tamilModifier)(?:\#(tamilWeekWordBeforeWeekday)\s+)?)?\#(tamilWeekdayForm)\#(notFromCount)(?:\s+அன்று)?(?:\#(tamilPartPhrase))?\#(from)"#
    let nextWeek =
      #"(?:(?:அடுத்த|வரும்|வருகிற)\s+வார(?:ம்|த்தில்|த்திற்கு|த்துக்கு))\#(from)"#
    let weekend = #"(?:(?:இந்த|வரும்|வருகிற|அடுத்த)\s+)?\#(tamilWeekendWords)\#(from)"#
    let alternatives = [relative, thisPart, counted, tamilPlannedDate, weekend, weekday, nextWeek]
    let notFollowed = #"(?!\s+\#(tamilUntilWords))\#(tamilNotPointOfReference)"#
    return #"\#(tamilStart)(\#(alternatives.joined(separator: "|")))\#(tamilEnd)\#(notFollowed)"#
  }

  static func tamilWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !tamilIsNotComing(match) else { return nil }
    if let count = match.group(2), let unit = match.group(3) {
      guard let amount = number(count) ?? tamilRoundCounts[tamilCompactKey(count)] else { return nil }
      return tamilRelativeDay(count: amount, unit: tamilPhrase(unit), in: match)
    }
    if tamilFinds("^\(tamilTomorrow)", in: phrase), !tamilFinds("^\(tamilDayAfter)", in: phrase),
      tamilIsDayWord(match)
    {
      return nil
    }
    return tamilDay(phrase, in: match)
  }

  // MARK: - Due day

  /// The relative days a deadline may name, as a pattern without groups:
  /// tomorrow and the day after ("நாளை", "நாளை மறுநாள்"), which are no deadline
  /// where a numeral or a determiner stands before them (see
  /// ``tamilIsDayWord(_:)``).
  private static let tamilDueTomorrow =
    #"(?:நாளை\s*மறுநாள்|நாளை\s*மறுதினம்|நாளை\#(tamilSandhi))"#

  /// The forms of today a deadline word reads: "இன்று", "இன்றைக்கு", "இன்னைக்கு",
  /// "இன்னிக்கு".
  private static let tamilDueToday = #"(?:இன்றைக்கு|இன்னைக்கு|இன்னிக்கு|இன்று)"#

  /// A weekday before a deadline word, as a pattern without groups: the plain
  /// name, maybe after a modifier ("வரும் வெள்ளிக்கிழமை வரை").
  private static var tamilDueWeekday: String {
    #"(?:\#(tamilModifier)(?:\#(tamilWeekWordBeforeWeekday)\s+)?)?\#(tamilWeekdayWord)"#
  }

  /// A date a deadline may name, as a pattern without groups: a written date
  /// with its optional weekday and label, a day of the month with the word for
  /// date, and a date in digits.
  private static var tamilDueDate: String {
    #"\#(tamilDateLabel)?(?:\#(tamilWeekdayWord)\s*,?\s+)?(?:\#(tamilMonthDatePattern)\#(tamilWeekdayAfterDate)?|\#(tamilDayOfMonthStem)|\#(tamilStrictNumericDate)|\#(numericDateWithoutYear))"#
  }

  /// A part of the day that may stand between a day and a deadline word
  /// ("வெள்ளிக்கிழமை இரவு வரை"), as a pattern without groups.
  private static var tamilDuePart: String {
    #"(?:\s+(?:\#(tamilDayPartWords)))?"#
  }

  /// The words that bound a deadline after a day with "க்குள்": the dative of the
  /// day word and the bound, as in "நாளைக்குள்", "இன்றைக்குள்", "15ஆம்
  /// தேதிக்குள்", "வெள்ளிக்கிழமை மாலைக்குள்", as a pattern without groups.
  private static let tamilBoundSuffix = #"க்குள்(?:ளாக)?"#

  /// The parts of the day with "க்குள்" glued to them ("மாலைக்குள்", "இரவுக்குள்"),
  /// as a pattern without groups.
  private static let tamilPartBound =
    #"(?:காலைக்குள்(?:ளாக)?|மாலைக்குள்(?:ளாக)?|இரவுக்குள்(?:ளாக)?|மதியத்திற்குள்|மதியத்துக்குள்|பகலுக்குள்|நண்பகலுக்குள்|பிற்பகலுக்குள்(?:ளாக)?|முற்பகலுக்குள்(?:ளாக)?)"#

  /// The days a deadline word may follow, as a pattern with a group for the
  /// part that holds the day: group 1 the day of a phrase that ends in a
  /// deadline word ("வெள்ளிக்கிழமை வரை", "வெள்ளிக்குள்", "நாளைக்குள்", "15ஆம்
  /// தேதிக்குள்", "இன்று இரவு வரை"). "இன்று வரை" is not a deadline: it means "so
  /// far".
  private static var tamilDueBeforeWord: String {
    let until = tamilUntilWords
    let weekday =
      #"(?:\#(tamilDueWeekday)\#(tamilDuePart)\s*\#(until)|\#(tamilWeekdayBound)|\#(tamilDueWeekday)\s+\#(tamilPartBound))"#
    let date =
      #"(?:\#(tamilDueDate))(?:\s*\#(until)|·க்குள்(?:ளாக)?)"#
    let tomorrow =
      #"(?:\#(tamilDueTomorrow)\#(tamilDuePart)\s*\#(until)|நாளைக்குள்(?:ளாக)?|நாளை\s*மறுநாளுக்குள்(?:ளாக)?|\#(tamilDueTomorrow)\s+\#(tamilPartBound))"#
    let today =
      #"(?:\#(tamilDueToday)\s+(?:\#(tamilDayPartWords))\s*\#(until)|இன்(?:றை|னை|னி)க்குள்(?:ளாக)?|இன்றிரவு\s*(?:வரை|வரைக்கும்)|இன்றிரவுக்குள்|இந்த\#(tamilSandhi)\s+(?:\#(tamilDayPartWords))\s*\#(until)|\#(tamilDueToday)\s+\#(tamilPartBound))"#
    return "\(weekday)|\(date)|\(tomorrow)|\(today)"
  }

  /// The days a deadline label may name, as a pattern without groups: today,
  /// tomorrow, the day after, a date, and a weekday. A date comes before a
  /// weekday alone, so "காலக்கெடு: வியாழன், 15 அக்டோபர்" is one date and not
  /// Thursday with a date left over.
  private static var tamilLabelDay: String {
    #"(?:\#(tamilToday)|\#(tamilDueTomorrow)|\#(tamilDueDate)|\#(tamilDueWeekday))(?:\s+(?:\#(tamilDayPartWords)))?"#
  }

  /// The words and clock times that bound a deadline written as a clock time,
  /// as a pattern without groups, from ``tamilClockBoundAfterDay``.
  private static var tamilDueClockAfterDay: String {
    tamilClockBoundAfterDay
  }

  /// A day with a deadline word after it ("வெள்ளிக்கிழமை வரை", "வெள்ளிக்குள்",
  /// "நாளைக்குள்", "அக்டோபர் 15க்குள்", "இன்று இரவு வரை"), a deadline label
  /// before it ("காலக்கெடு: வெள்ளிக்கிழமை", "காலக்கெடு நாளை", "கடைசி தேதி
  /// அக்டோபர் 15"), the label after it as the app writes it ("வெள்ளி காலக்கெடு",
  /// "நாளை காலக்கெடு"), or a deadline clock after it ("வெள்ளிக்கிழமை மாலை 5
  /// மணிக்குள்", whose clock stays in the title). Groups: 1 the day after a
  /// label, 2 the day before a deadline word, 3 the day before the label, 4 the
  /// day before a deadline clock.
  static var tamilDuePattern: String {
    let label =
      #"(?:(?:காலக்கெடு\s+தேதி|காலக்கெடு|கடைசி\s+தேதி|இறுதி\s+தேதி|கடைசி\s+நாள்|இறுதி\s+நாள்|டெட்லைன்|டெட்\s*லைன்)(?:\s*[:：]\s*|\s+)(\#(tamilLabelDay)))"#
    let before = #"(\#(tamilDueBeforeWord))"#
    let after =
      #"((?:\#(tamilToday)|\#(tamilDueTomorrow)|\#(tamilDueWeekday)|\#(tamilDueDate))(?:\s+(?:\#(tamilDayPartWords)))?)\s+காலக்கெடு(?:\s+தேதி)?"#
    let clock =
      #"((?:\#(tamilToday)|\#(tamilDueTomorrow)|\#(tamilDueWeekday)|\#(tamilDueDate)))(?=\#(tamilDueClockAfterDay))"#
    return
      #"\#(tamilStart)(?:\#(label)\#(tamilEnd)|\#(before)\#(tamilEnd)|\#(after)\#(tamilEnd)|\#(clock))"#
  }

  static func tamilDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4),
      !tamilIsNotComing(match)
    else { return nil }
    if tamilFinds("^(?:நாளை|நாளைக்குள்)", in: phrase), !tamilFinds("^\(tamilDayAfter)", in: phrase),
      tamilIsDayWord(match)
    {
      return nil
    }
    return tamilDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "இந்த" makes it this week's, today when it
  /// names today; "வரும்" and "வருகிற" make it the coming one, a full week ahead
  /// when it names today; "அடுத்த" makes it next week's, weeks starting on
  /// Monday, and a week word after "வரும்" makes it next week's too ("வரும்
  /// வாரம் திங்கள்").
  private static func tamilDay(_ phrase: String, in match: Match) -> Day? {
    if let date = numericDate(phrase) ?? tamilDate(tamilPhrase(phrase)) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let isEvening = tamilFinds(
      #"(?:இரவு|இரவில்|இரவுக்கு|ராத்திரி|இராத்திரி|நள்ளிரவு|நடு\s*இரவு|நடு\s*ராத்திரி|மிட்நைட்|இன்றிரவ)"#, in: phrase)
    if tamilFinds("^(?:\(tamilToday)|\(tamilTonight)|\(tamilThisPart)|\(tamilDueToday))", in: phrase) {
      return Day(offset: 0, isEvening: isEvening)
    }
    if tamilFinds("^\(tamilDayAfter)", in: phrase) { return Day(offset: 2, isEvening: isEvening) }
    if tamilFinds("^\(tamilDueTomorrow)", in: phrase) { return Day(offset: 1, isEvening: isEvening) }
    let tokens = tamilWords(in: phrase).map(tamilWithoutDoubling)
    let hasWeekWord = tokens.contains(where: tamilWeekWords.contains)
    let isNext =
      tokens.contains(where: tamilNextWords.contains)
      || (hasWeekWord && tokens.contains(where: tamilComingWords.contains))
    if tamilFinds(tamilWeekendWords, in: phrase) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: tokens.contains(where: tamilNextWords.contains) ? weekend + 7 : weekend)
    }
    guard let weekday = tokens.lazy.compactMap(tamilWeekdayIndex).first else {
      return hasWeekWord ? Day(offset: 7) : nil
    }
    let todayWeekday = match.todayWeekday
    if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
    if tokens.contains(where: tamilThisWords.contains) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// The words that tie a counted amount of days to another event, which makes
  /// it no day of its own: "கூட்டம் முடிந்த 3 நாட்களுக்குப் பிறகு" counts from
  /// the meeting, and "கடந்த 3 நாட்களில்" and "அடுத்த 3 நாட்களில்" name a window.
  private static let tamilEventTies: Set<String> = Set(
    ["கடந்த", "சென்ற", "அடுத்த", "முந்தைய", "முதல்", "முடிந்த", "ஆன", "செய்த", "முடிந்து", "ஆகி"].map(tamilKey))

  /// Whether `word` is the ablative "இருந்து" (from) or a noun that ends in it
  /// ("கூட்டத்திலிருந்து"): the amount after it counts from the thing it names.
  private static func tamilIsAblative(_ word: String) -> Bool {
    word == tamilKey("இருந்து")
      || word.unicodeScalars.reversed().starts(with: tamilKey("லிருந்து").unicodeScalars.reversed())
  }

  /// The day of "3 நாட்களில்", "இரண்டு வாரங்களுக்குப் பிறகு", "1 மாதம் கழித்து",
  /// from the count and the unit. A count of days or weeks needs no date; a
  /// count of months is counted on the calendar from today. Nil after a word
  /// that ties the amount to another event.
  private static func tamilRelativeDay(count: Int, unit: String, in match: Match) -> Day? {
    guard count >= 1 else { return nil }
    if let before = tamilWordBefore(match), tamilEventTies.contains(before) || tamilIsAblative(before) { return nil }
    let key = tamilKey(unit)
    if tamilHasPrefix(key, tamilKey("நாள")) || tamilHasPrefix(key, tamilKey("நாட்")) { return Day(offset: count) }
    if tamilHasPrefix(key, tamilKey("வார")) { return Day(offset: count * 7) }
    guard tamilHasPrefix(key, tamilKey("மாத")), let today = match.today else { return nil }
    let calendar = utcCalendar
    guard let target = calendar.date(byAdding: .month, value: count, to: today),
      let days = calendar.dateComponents([.day], from: today, to: target).day
    else { return nil }
    return Day(offset: days)
  }

  // MARK: - Date range

  /// "அக்டோபர் 3 முதல் 5 வரை", "3 முதல் 5 அக்டோபர் வரை", "3 அக்டோபர் முதல் 5
  /// அக்டோபர் வரை", "அக்டோபர் 3-5", "3-5 அக்டோபர்", maybe with a year after a
  /// month, and with "வரை", "வரைக்கும்", or "வரையில்" after the end. The start
  /// and the end are each a date or a day alone ("3", "3ஆம் தேதி"). The end
  /// may carry "க்கு" or "இல்" glued to it; any other letter or sign glued to
  /// the end makes it another word and leaves the line unread. Groups: 1 the
  /// start, 2 a dash between the sides, 3 "முதல்" between them, 4 the end, 5 the
  /// word for "until".
  static var tamilDateRangePattern: String {
    let bare = #"\d{1,2}(?:\#(tamilOrdinal)(?:\s*\#(tamilDateWord))?)?\#(tamilNoMoreDigits)"#
    let side = "\(tamilMonthDatePattern)|\(bare)"
    let connector = #"(?:\s*([-–—])\s*|\s+(முதல்)\s+)"#
    let ending = #"(?:·(?:க்கு|இல்))?"#
    return
      #"\#(tamilStart)\#(tamilDateLabel)?(\#(side))\#(connector)(\#(side))\#(ending)(?:\s+(\#(tamilUntilWords)))?\#(tamilDateEnd)"#
  }

  /// A range names days only when a month stands in it: the start with a month
  /// and an end without one ("அக்டோபர் 3 முதல் 5 வரை") needs "வரை" or a dash,
  /// since "அக்டோபர் 3 முதல் 5 பேர்" is no range; a start without a month needs
  /// the end's. A range in the past tense names a trip or an event that the
  /// task may only prepare for: it is claimed whole and read as no days, so "8
  /// மே வரை" is not read alone as a due day. A day alone opens a range joined by
  /// a dash only when the dash touches both sides ("3-5 மே"): "Sprint 12 - 20
  /// மே" names a sprint and a date.
  static func tamilDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(4),
      let start = tamilRangeDate(startText), let end = tamilRangeDate(endText)
    else { return nil }
    if start.month == nil {
      guard end.month != nil else { return nil }
      if match.group(2) != nil, !dashTouchesBothSides(match, start: 1, end: 4) { return nil }
    } else if end.month == nil, match.group(5) == nil, match.group(2) == nil {
      return nil
    }
    if tamilIsNotComing(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("5 மே") or a day alone ("5", "5ஆம் தேதி"),
  /// which has no month.
  private static func tamilRangeDate(_ text: String) -> ExplicitDate? {
    let words = tamilPhrase(text)
    if let date = tamilDate(words) { return date }
    let runs = tamilRuns(words)
    let signs = ["ஆம்", "ஆவது", "வது", "ம்", "தேதி"].map(tamilKey)
    guard let first = runs.first, let day = number(first), (1...31).contains(day),
      runs.dropFirst().allSatisfy({ run in signs.contains(run) })
    else { return nil }
    return ExplicitDate(day: day)
  }

  /// "திங்கள் முதல் புதன் வரை", "வெள்ளி முதல் ஞாயிறு", "திங்கட்கிழமை முதல்
  /// புதன்கிழமை வரை": a span of weekdays, maybe with "வரை" after it and "இலான"
  /// after that ("திங்கள் முதல் புதன் வரையிலான விடுமுறை"). Groups: 1 the first
  /// weekday, 2 the last, 3 "யிலான".
  static var tamilWeekdayRangePattern: String {
    #"\#(tamilStart)(\#(tamilWeekdayWord))\s+முதல்\s+(\#(tamilWeekdayWord))(?:\s+(?:வரைக்கும்|வரையில்|வரை)(யிலான)?)?+\#(tamilEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "திங்கள் முதல் புதன் வரை" runs from next
  /// Monday to the Wednesday after it. A span that "யிலான" follows ("திங்கள்
  /// முதல் புதன் வரையிலான விடுமுறை" is the holiday of those days) is claimed
  /// whole and read as no days. A span that "ஒவ்வொரு" or the words for every
  /// day accompany is a habit, which the repeat rules read
  /// (``tamilIsHabitSpan(_:)``). Any other span in the past tense, or after a
  /// word that makes it no coming one, is claimed whole too, and so is Monday
  /// to Friday with no word for every day: it is the working week as often as
  /// it is a span of days. A span from a day to itself is no span.
  static func tamilWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1), let lastWord = match.group(2),
      let first = tamilWeekdayIndex(firstWord), let last = tamilWeekdayIndex(lastWord), first != last
    else { return nil }
    if match.group(3) != nil { return .declined }
    if tamilIsHabitSpan(match) { return nil }
    if tamilIsNotComing(match) { return .declined }
    if first == 1 && last == 5 { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
