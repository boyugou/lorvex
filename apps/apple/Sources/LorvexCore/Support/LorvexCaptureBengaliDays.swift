import Foundation

extension LorvexCaptureVocabulary {
  // The Bengali day rules: the planned day, the due day, written dates, and
  // date ranges. The vocabulary's other words are in ``bengali``.

  // MARK: - Names

  /// Each weekday's names, Sunday first. The short stems (রবি, সোম, মঙ্গল, বুধ,
  /// বৃহস্পতি, শুক্র, শনি) are ordinary words or names, and the one-letter
  /// forms the system writes are letters: neither is here.
  private static let bengaliWeekdayNameList: [[String]] = [
    ["রবিবার", "রোববার"], ["সোমবার"], ["মঙ্গলবার"], ["বুধবার"], ["বৃহস্পতিবার", "বৃহষ্পতিবার"], ["শুক্রবার"],
    ["শনিবার"],
  ]

  /// The weekday names as keys, longest first, each with its weekday (0 =
  /// Sunday).
  private static let bengaliWeekdayKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (weekday, names) in bengaliWeekdayNameList.enumerated() {
      for name in names { keys.append((bengaliKey(name), weekday)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The weekday names as a pattern, longest first.
  static let bengaliWeekdayNames = alternation(of: bengaliWeekdayNameList.flatMap { $0 })

  /// The weekday a word names, 0 = Sunday, with or without an ending glued to
  /// it ("সোমবারে", "সোমবারের").
  static func bengaliWeekdayIndex(_ word: String) -> Int? {
    let key = bengaliKey(word)
    return bengaliWeekdayKeys.first(where: { bengaliHasPrefix(key, $0.key) })?.index
  }

  /// Each month's Gregorian names, January first: the full name in the
  /// spellings people type, and the short forms the system writes next to a
  /// day ("15 অক্টো", "15 অক্টোঃ"), which the full name of a month with no
  /// short form ("মার্চ", "মে", "জুন") stands for.
  private static let bengaliMonthRows: [(full: [String], short: [String])] = [
    (["জানুয়ারি", "জানুয়ারী"], ["জানু"]),
    (["ফেব্রুয়ারি", "ফেব্রুয়ারী", "ফেব্রুআরি"], ["ফেব্রু", "ফেব"]),
    (["মার্চ"], []),
    (["এপ্রিল"], ["এপ্রি"]),
    (["মে"], []),
    (["জুন"], []),
    (["জুলাই"], ["জুল"]),
    (["আগস্ট", "আগষ্ট"], ["আগ"]),
    (["সেপ্টেম্বর"], ["সেপ্টেঃ", "সেপ্টে", "সেপ্ট", "সেপ"]),
    (["অক্টোবর"], ["অক্টোঃ", "অক্টো"]),
    (["নভেম্বর"], ["নভেঃ", "নভে"]),
    (["ডিসেম্বর"], ["ডিসেঃ", "ডিসে"]),
  ]

  /// The month names as keys, longest first, each with its month (0 =
  /// January).
  private static let bengaliMonthKeys: [(key: String, index: Int)] = {
    var keys: [(key: String, index: Int)] = []
    for (month, row) in bengaliMonthRows.enumerated() {
      for name in row.full + row.short { keys.append((bengaliKey(name), month)) }
    }
    return keys.sorted { $0.key.unicodeScalars.count > $1.key.unicodeScalars.count }
  }()

  /// The month a word names, 0 = January, with or without an ending glued to
  /// it ("অক্টোবরে").
  private static func bengaliMonthIndex(_ word: String) -> Int? {
    let key = bengaliKey(word)
    return bengaliMonthKeys.first(where: { bengaliHasPrefix(key, $0.key) })?.index
  }

  // MARK: - Dates

  /// The suffix a day of the month takes when it is written as an ordinal:
  /// "১লা", "২রা", "৩রা", "৪ঠা", "৫ই" to "১৮ই", "১৯শে" to "৩১শে".
  private static let bengaliOrdinalSuffix = #"(?:·(?:ই|শে|লা|রা|ঠা))"#

  /// The ordinal suffixes as keys.
  private static let bengaliOrdinalSuffixes: Set<String> = Set(["ই", "শে", "লা", "রা", "ঠা"].map(bengaliKey))

  /// The words after a month and a day number that make the number an amount
  /// ("মে ১০ টাকা"), as a pattern that fails where one follows.
  private static let bengaliNoAmountAfter =
    #"(?!\s*(?:টা|টি|টে|টো|টায়|মিনিট|ঘ[ণন]্টা|টাকা|ডলার|দিন|সপ্তাহ|মাস|বছর|জন|%)\#(bengaliEnd))"#

  /// "১৫ অক্টোবর", "১৫ই অক্টোবর", "১৫ অক্টোবর ২০২৬", "১৫ অক্টোবর, ২০২৬", "১৫
  /// অক্টো", "অক্টোবর ১৫", "অক্টোবর ১৫, ২০২৬": a day number and a Gregorian
  /// month name, in either order, maybe with a year. A short month name is read
  /// only after its day number, since it is a word's first letters too ("আগ").
  /// A month needs its day number, so "অক্টোবর" alone is no date.
  static var bengaliMonthDatePattern: String {
    let full = alternation(of: bengaliMonthRows.flatMap { $0.full })
    let short = alternation(of: bengaliMonthRows.flatMap { $0.short })
    let day = #"\d{1,2}\#(bengaliOrdinalSuffix)?"#
    let year = #"(?:,?\s+(?:19|20)\d{2}(?!\p{N}))?"#
    return
      #"(?:\#(day)\s*(?:(?:\#(full))|(?:\#(short))\.?)\#(year)|(?:\#(full))\s*\#(day)\#(bengaliNoMoreDigits)\#(bengaliNoAmountAfter)\#(year))"#
  }

  /// "১৫ তারিখ": a day of the month with no month, as the stem of the word for
  /// "on the 15th" ("১৫ তারিখে") or "from the 15th" ("১৫ তারিখ থেকে").
  static let bengaliDayOfMonthStem = #"\d{1,2}\#(bengaliOrdinalSuffix)?\s*তারিখ"#

  /// The label that may stand before a date.
  private static let bengaliDateLabel = #"(?:তারিখ\s*[:：]?\s*)"#

  /// The endings that go with a date written with a month name as a planned
  /// day: the locative ("১৫ অক্টোবরে", "১৫ জুলাইয়ে"), "থেকে" (from), "-এ"
  /// after a year, and the genitive before "জন্য" ("১৫ অক্টোবরের জন্য").
  private static let bengaliPlannedDateEnding =
    #"(?:·(?:য়ে|ে)|\s+থেকে|(?:·ের|·র)\s+জন্য|-এ)"#

  /// The endings that go with a date written in digits only: "এ" glued or after
  /// a space, "থেকে", and the genitive "-এর" before "জন্য".
  private static let bengaliNumericDateEnding = #"(?:-?এ|\s+এ|\s+থেকে|-এর\s+জন্য)"#

  /// A date in digits that is a date wherever it stands: with a four-digit year
  /// ("১৫/১০/২০২৬", "১৫.১০.২০২৬", "১৫-১০-২০২৬") or with the dot that closes
  /// the month ("১৫.১০.").
  private static let bengaliStrictNumericDate =
    #"(?:\#(numericDateWithYear)|(?<![\p{N}.,:/-])\d{1,2}\.\d{1,2}\.(?![\p{N}]|[.,/]\p{N}))"#

  /// A planned day written as a date, as a pattern without groups: a day and a
  /// month name with its optional weekday, label, year, and ending ("সোমবার, ৫
  /// অক্টোবর", "তারিখ ১৫ অক্টোবর", "১৫ অক্টোবরে", "১৫ অক্টোবর ২০২৬-এ"), a day
  /// of the month with its ending ("১৫ তারিখে"), a date in digits with a year
  /// or a closing dot, and a date in digits with only a day and a month ("১৫/১০"),
  /// which is as often a score, a fraction, or a time, so it is read only after
  /// a label or before an ending.
  private static var bengaliPlannedDate: String {
    let month =
      #"\#(bengaliDateLabel)?(?:(?:\#(bengaliWeekdayNames))(?:·ে)?\s*,?\s+)?\#(bengaliMonthDatePattern)\#(bengaliPlannedDateEnding)?"#
    let dayOfMonth = #"\#(bengaliDateLabel)?\#(bengaliDayOfMonthStem)(?:·ে|\s+থেকে)"#
    let strict = #"\#(bengaliDateLabel)?\#(bengaliStrictNumericDate)\#(bengaliNumericDateEnding)?"#
    let looseLabeled = #"\#(bengaliDateLabel)\#(numericDateWithoutYear)\#(bengaliNumericDateEnding)?"#
    let looseEnded = #"\#(numericDateWithoutYear)\#(bengaliNumericDateEnding)"#
    return "\(month)|\(dayOfMonth)|\(strict)|\(looseLabeled)|\(looseEnded)"
  }

  /// The words and numbers of `text`, with each run of digits and each run of
  /// letters apart ("5ই" is "5" and "ই").
  static func bengaliRuns(_ text: String) -> [String] {
    var runs: [String] = []
    var current = ""
    var isDigits = false
    for character in text {
      let isDigit = character.isNumber
      guard isDigit || character.isLetter else {
        if !current.isEmpty { runs.append(current) }
        current = ""
        continue
      }
      if !current.isEmpty, isDigit != isDigits {
        runs.append(current)
        current = ""
      }
      isDigits = isDigit
      current.append(character)
    }
    if !current.isEmpty { runs.append(current) }
    return runs
  }

  /// A written-out date: "১৫ অক্টোবর", "১৫ই অক্টোবর ২০২৬", "অক্টোবর ১৫", "১৫
  /// তারিখে". The words are a phrase as ``bengaliPhrase(_:)`` leaves it. A day
  /// number with a month name names a date; with "তারিখ" it names a day of the
  /// month.
  static func bengaliDate(_ words: String) -> ExplicitDate? {
    let runs = bengaliRuns(words)
    let numbers = runs.compactMap { run in number(run).map { (run: run, value: $0) } }
    guard let day = numbers.first(where: { $0.run.count <= 2 && (1...31).contains($0.value) })?.value else {
      return nil
    }
    let year = numbers.first(where: { $0.run.count == 4 && (1900...2099).contains($0.value) })?.value
    if let month = runs.lazy.compactMap(bengaliMonthIndex).first {
      return ExplicitDate(year: year, month: month + 1, day: day)
    }
    if runs.contains(where: { bengaliHasPrefix($0, bengaliKey("তারিখ")) }) { return ExplicitDate(day: day) }
    return nil
  }

  // MARK: - The words around a day

  /// The words before a weekday that make it this week's, next week's, or the
  /// coming one. "এই" is this week's; "পরের" is next week's; "আগামী", "আসছে",
  /// "সামনের", and "আসন্ন" are the coming one, which is how a weekday alone is
  /// read, and next week's when "সপ্তাহের" stands between them and the weekday.
  private static let bengaliThisWords: Set<String> = Set(["এই"].map(bengaliKey))
  private static let bengaliNextWords: Set<String> = Set(["পরের"].map(bengaliKey))
  private static let bengaliComingWords: Set<String> = Set(
    ["আগামী", "আসছে", "সামনের", "আসন্ন"].map(bengaliKey))

  /// The week words that stand between a modifier and a weekday ("পরের
  /// সপ্তাহের শুক্রবার"), as keys.
  private static let bengaliWeekWords: Set<String> = Set(
    ["সপ্তাহের", "সপ্তাহে", "সপ্তাহ", "হপ্তার", "হপ্তায়", "হপ্তা"].map(bengaliKey))

  /// The words that may stand before a weekday, as a pattern.
  private static let bengaliModifier = #"(?:(?:এই|আগাম[িী]|আসছে|সামনের|আসন্ন|পরের)\s+)"#

  /// "সপ্তাহের" or its likes between a modifier and a weekday ("পরের সপ্তাহের
  /// শুক্রবার"), as a pattern.
  private static let bengaliWeekWordBeforeWeekday = #"(?:সপ্তাহের|সপ্তাহে|হপ্তার|হপ্তায়)"#

  /// The weekend: "উইকেন্ড", "সপ্তাহান্ত", "সপ্তাহের শেষে", or Saturday and
  /// Sunday together ("শনিবার ও রবিবার", "শনি-রবিবার").
  static let bengaliWeekendWords =
    #"(?:উইক(?:ে|\s*-?\s*এ)ন্ড(?:·ে)?|সপ্তাহান্ত(?:·ে)?|সপ্তাহের\s+শেষে|(?:শনিবার|শনি)(?:\s*[-–—]\s*|\s+(?:ও|এবং)\s+)(?:রবিবার|রোববার)|শনিবার\s+(?:রবিবার|রোববার))"#

  /// The words before a day phrase that make it no coming day: the past ("গত
  /// শুক্রবার", "আগের সোমবার"), "পরবর্তী" (which may be the next one or the
  /// one after it), and an ordinal ("প্রথম শুক্রবার" is the month's first
  /// Friday).
  private static let bengaliNotComingModifiers: Set<String> = Set(
    [
      "গত", "গেল", "আগের", "বিগত", "পরবর্তী", "শেষ", "প্রথম", "দ্বিতীয়", "তৃতীয়", "চতুর্থ", "পঞ্চম",
    ].map(bengaliKey))

  /// The past-tense forms that put a line in the past: the auxiliary "ছিল" and
  /// the perfectives of "হওয়া", "যাওয়া", "আসা", and "করা" in the first and
  /// third person ("কাল মিটিং ছিল", "কাল ফোন করেছি"). "হল" is the word for a
  /// hall too and "গেল" the word for "last", so neither is here.
  private static let bengaliPastMarkers: Set<String> = Set(
    [
      "ছিল", "ছিলো", "ছিলাম", "ছিলেন", "ছিলে", "ছিলি", "ছিলুম", "হয়েছিল", "হয়েছিলো", "হয়েছিলাম", "হয়েছিলেন",
      "হলো", "হলাম", "গিয়েছিল", "গিয়েছিলো", "গিয়েছিলাম", "গিয়েছিলেন", "গিয়েছি", "গেলাম", "এসেছিল", "এসেছিলো",
      "এসেছিলাম", "এসেছিলেন", "এসেছি", "এলাম", "করেছিল", "করেছিলো", "করেছিলাম", "করেছিলেন", "করেছি", "করলাম",
    ].map(bengaliKey))

  /// Whether `match` names a day that is no coming one: a word that makes it
  /// past or ordinal comes before it ("গত শুক্রবার", "প্রথম শুক্রবার"), or the
  /// line is in the past tense ("কাল মিটিং ছিল").
  static func bengaliIsNotComing(_ match: Match) -> Bool {
    if let before = bengaliWordBefore(match), bengaliNotComingModifiers.contains(before) { return true }
    return bengaliWords(in: match.source).contains(where: bengaliPastMarkers.contains)
  }

  /// "পর্যন্ত" and "অবধি" (until) after a day, as a pattern.
  static let bengaliUntilWords = #"\s+(?:পর্যন্ত|অবধি)"#

  /// The words that make a day a deadline when they follow it: "পর্যন্ত" and
  /// "অবধি" after a space, and a genitive ending ("শুক্রবারের", "আজকের",
  /// "রাতের", "সন্ধ্যার", "মে-র", "২০২৬-এর", "২০২৬ সালের") before "মধ্যে" (within),
  /// "আগে", or "পূর্বে" (before).
  static let bengaliDeadlineWords =
    #"(?:\#(bengaliUntilWords)|(?:·কের|·ের|·র|-এর|-র|\s+সালের)\s+(?:মধ্যে(?:ই)?|আগে|প[ূু]র্বে))"#

  /// A part of the day in its plain form, as the word that goes with a
  /// deadline word ("সন্ধ্যা পর্যন্ত", "রাতের মধ্যে").
  private static let bengaliPartStem =
    #"(?:সকাল|ভোর|দুপুর|(?:বিকেল|বিকাল)|সন্ধ্যা|সন্ধ্যে|সন্ধে|সন্ধা|রাত্রি|রাত)"#

  // MARK: - Planned day

  /// A part of the day after a day word, as a phrase: "কাল সকালে", "শুক্রবার
  /// সন্ধ্যায়". The word that goes with it is ``bengaliDayPartWords``.
  private static var bengaliPartPhrase: String {
    #"\s+(?:\#(bengaliDayPartWords))\#(bengaliEnd)"#
  }

  /// The day words that name today, tomorrow, and the day after tomorrow, as
  /// patterns without groups. "কাল" and "পরশু" also name the day before
  /// yesterday and the one before that: they are read as the coming day
  /// (``bengaliIsNotComing(_:)``).
  private static let bengaliToday = #"আজ(?:·(?:কে(?:ই)?|ই))?"#
  private static let bengaliTomorrow = #"(?:আগাম[িী]\s*)?কাল(?:·(?:কে(?:ই)?|ই))?"#
  private static let bengaliDayAfter = #"(?:আগাম[িী]\s+)?পরশু(?:·দিন)?(?:·ই)?"#

  /// Group 1: the day, with the ending that goes with it; groups 2 and 3: the
  /// count and the unit of a number of days, weeks, or months.
  ///
  /// Today ("আজ"), tomorrow ("কাল", "আগামীকাল"), the day after ("পরশু"), each
  /// maybe with a part of the day ("আজ রাতে", "কাল সকালে") or an ending
  /// ("আজই", "কালকে"); a number of days, weeks, or months ("৩ দিন পর", "দুই
  /// সপ্তাহ পরে", "১ মাস বাদে"); a weekday, alone or after "এই", "পরের",
  /// "আগামী", "আসছে", "সামনের", or "আসন্ন", maybe with "সপ্তাহের" between
  /// ("সোমবারে", "এই শুক্রবার", "পরের সপ্তাহের শুক্রবার"), maybe with a part
  /// of the day; next week ("পরের সপ্তাহে"); the weekend; and a date
  /// (``bengaliPlannedDate``). A day word or weekday may be followed by
  /// "থেকে" or "হতে" ("কাল থেকে জিম শুরু" plans tomorrow), unless the
  /// "থেকে" starts a counted day ("আজ থেকে ৩ দিন পর", "সোমবার থেকে ২ সপ্তাহ
  /// পর"). A weekday followed by a genitive ("সোমবারের মিটিং") is no planned
  /// day, since the genitive is an ending this pattern does not list, and
  /// neither is a day that "পর্যন্ত" or "অবধি" follows with any ending ("আজ
  /// পর্যন্ত" means "so far", and "শুক্রবার পর্যন্তের কাজ" is work that runs up to
  /// Friday); a deadline is read by ``bengaliDuePattern`` first.
  static var bengaliWhenPattern: String {
    let counted =
      #"(?:(\d{1,3}|\#(bengaliRoundCountWords))\s*(দিন|সপ্তাহ|হপ্তা|মাস)\s+(?:পরে|পর|বাদে)(?:·ই)?(?!\s+পর(?:ে)?\#(bengaliEnd)))"#
    let from = #"(?:\s+(?:থেকে|হতে)(?:·ই)?)?"#
    let notFromCount =
      #"(?!\s+(?:থেকে|হতে)\s+(?:\d{1,3}|\#(bengaliRoundCountWords))\s*(?:দিন|সপ্তাহ|হপ্তা|মাস)\s+(?:পরে|পর|বাদে))"#
    let relative =
      #"(?:\#(bengaliToday)|\#(bengaliTomorrow)|\#(bengaliDayAfter))\#(notFromCount)(?:\#(bengaliPartPhrase))?\#(from)"#
    let weekday =
      #"(?:\#(bengaliModifier)(?:\#(bengaliWeekWordBeforeWeekday)\s+)?)?(?:\#(bengaliWeekdayNames))(?:·(?:ে(?:ই)?|ই))?\#(notFromCount)(?:\#(bengaliPartPhrase))?\#(from)"#
    let nextWeek =
      #"(?:পরের|আগাম[িী]|আসছে|সামনের|আসন্ন)\s+(?:সপ্তাহ(?:·ে)?|হপ্তা(?:·য়)?)(?:\s+থেকে)?"#
    let weekend =
      #"(?:(?:এই|আগাম[িী]|আসছে|সামনের|পরের)\s+)?\#(bengaliWeekendWords)"#
    let alternatives = [relative, counted, bengaliPlannedDate, weekend, weekday, nextWeek]
    let deadlineWord = #"(?!\#(bengaliUntilWords))"#
    return
      #"\#(bengaliStart)(\#(alternatives.joined(separator: "|")))\#(bengaliEnd)\#(deadlineWord)"#
  }

  static func bengaliWhen(_ match: Match) -> Day? {
    guard let phrase = match.group(1), !bengaliIsNotComing(match) else { return nil }
    if let count = match.group(2), let unit = match.group(3) {
      guard let amount = number(count) ?? bengaliRoundCounts[bengaliPhrase(count)] else { return nil }
      return bengaliRelativeDay(count: amount, unit: bengaliPhrase(unit), in: match)
    }
    return bengaliDay(phrase, in: match)
  }

  // MARK: - Due day

  /// The days a deadline may name, as a pattern without groups: tomorrow, the
  /// day after, a weekday, a date, and today only before a part of the day
  /// ("আজ রাত পর্যন্ত", "আজ রাতের মধ্যে") or with its genitive ("আজকের
  /// মধ্যে"), since "আজ পর্যন্ত" means "so far".
  private static var bengaliDueDayBase: String {
    let date =
      #"\#(bengaliDateLabel)?(?:(?:\#(bengaliWeekdayNames))(?:·ে)?\s*,?\s+)?(?:\#(bengaliMonthDatePattern)|\#(bengaliDayOfMonthStem)|\#(bengaliStrictNumericDate)|\#(numericDateWithoutYear))"#
    let weekday =
      #"(?:\#(bengaliModifier)(?:\#(bengaliWeekWordBeforeWeekday)\s+)?)?(?:\#(bengaliWeekdayNames))"#
    let today = #"আজ(?=\s+\#(bengaliPartStem)|·কের\s+মধ্যে)"#
    return #"(?:\#(bengaliTomorrow)|\#(bengaliDayAfter)|\#(today)|\#(date)|\#(weekday))"#
  }

  /// ``bengaliDueDayBase`` with the part-of-day word that may follow it before
  /// a deadline word ("কাল সন্ধ্যা পর্যন্ত", "শুক্রবার রাতের মধ্যে").
  private static var bengaliDueDay: String {
    #"\#(bengaliDueDayBase)(?:\s+\#(bengaliPartStem))?"#
  }

  /// The days a deadline label may name, as a pattern without groups:
  /// ``bengaliDueDay`` and today.
  private static var bengaliLabelDay: String {
    #"(?:আজ(?:\s+\#(bengaliPartStem))?|\#(bengaliDueDay))"#
  }

  /// The clock times that bound a deadline, as a pattern without groups: an
  /// hour with the classifier and "র মধ্যে" or "পর্যন্ত" ("৫টার মধ্যে", "সাড়ে
  /// ৩টা পর্যন্ত"), a colon time with "পর্যন্ত" or "-এর মধ্যে", and an hour
  /// with AM or PM before them.
  static var bengaliClockBound: String {
    let words = #"(?:মধ্যে(?:ই)?|আগে|প[ূু]র্বে|পরে|পর)"#
    let hour = #"(?:(?:সাড়ে|সোয়া|সওয়া|পৌনে)\s*)?(?:\d{1,2}(?:[:.]\d{2})?|(?:\#(bengaliTimeWords))['’]?)"#
    let classifier = #"(?:টা|টে|টো)"#
    let tail = #"(?:\#(bengaliUntilWords)|\s*-?এর\s+\#(words))"#
    return
      #"(?:\#(hour)\#(classifier)(?:·র\s+\#(words)|\#(bengaliUntilWords))|\d{1,2}[:.]\d{2}\#(tail)|\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)\#(tail))"#
  }

  /// A day with a deadline word after it ("শুক্রবার পর্যন্ত", "কাল সন্ধ্যা
  /// পর্যন্ত", "১৫ অক্টোবরের মধ্যে", "আগামীকালের আগে"), a deadline label
  /// before it ("শেষ তারিখ: শুক্রবার", "ডেডলাইন ১৫ অক্টোবর", "সময়সীমা শুক্রবার"),
  /// or a deadline clock after it ("শুক্রবার সন্ধ্যা ৫টার মধ্যে", whose clock
  /// stays in the title). Groups: 1 the day after a label, 2 the day before a
  /// deadline word, 3 the day before a deadline clock. "আজ পর্যন্ত" is not a
  /// deadline: it means "so far".
  static var bengaliDuePattern: String {
    let label =
      #"(?:(?:শেষ|অন্তিম)\s+তারিখ|ডেডলাইন|ডেড\s+লাইন|সময়সীমা)(?:\s*[:：]\s*|\s+(?:হবে\s+)?)(\#(bengaliLabelDay))"#
    let before = #"(\#(bengaliDueDay))\#(bengaliDeadlineWords)"#
    let clock =
      #"(\#(bengaliDueDayBase))(?:·ে)?(?=\s+(?:(?:\#(bengaliPartLeadWords))\s+)?\#(bengaliClockBound))"#
    return #"\#(bengaliStart)(?:\#(label)\#(bengaliEnd)|\#(before)\#(bengaliEnd)|\#(clock))"#
  }

  static func bengaliDue(_ match: Match) -> Day? {
    guard let phrase = match.group(1) ?? match.group(2) ?? match.group(3), !bengaliIsNotComing(match) else {
      return nil
    }
    return bengaliDay(phrase, in: match).map { Day(offset: $0.offset) }
  }

  // MARK: - Reading a day

  /// The day a phrase names. A weekday alone means the next such day, a full
  /// week ahead when it names today; "এই" makes it this week's, today when it
  /// names today; "পরের" makes it next week's, weeks starting on Monday;
  /// "আগামী", "আসছে", "সামনের", and "আসন্ন" make it the coming one, a full
  /// week ahead when it names today, and next week's when a week word stands
  /// between them and the weekday.
  private static func bengaliDay(_ phrase: String, in match: Match) -> Day? {
    let words = bengaliPhrase(phrase)
    if let date = numericDate(phrase) ?? bengaliDate(words) {
      guard let today = match.today, let days = offset(to: date, from: today) else { return nil }
      return Day(offset: days)
    }
    let tokens = bengaliRuns(words)
    func names(_ word: String) -> Bool { tokens.contains(where: { bengaliHasPrefix($0, bengaliKey(word)) }) }
    let isEvening = names("রাত") || names("মধ্যরাত") || names("মাঝরাত")
    if names("আজ") { return Day(offset: 0, isEvening: isEvening) }
    if names("কাল") || names("আগামিকাল") { return Day(offset: 1, isEvening: isEvening) }
    if names("পরশু") { return Day(offset: 2, isEvening: isEvening) }
    let hasWeekWord = tokens.contains(where: bengaliWeekWords.contains)
    let isNext =
      tokens.contains(where: bengaliNextWords.contains)
      || (hasWeekWord && tokens.contains(where: bengaliComingWords.contains))
    if bengaliFinds(bengaliWeekendWords, in: phrase) {
      let weekend = weekendOffset(todayWeekday: match.todayWeekday)
      return Day(offset: isNext ? weekend + 7 : weekend)
    }
    guard let weekday = tokens.lazy.compactMap(bengaliWeekdayIndex).first else {
      return hasWeekWord ? Day(offset: 7) : nil
    }
    let todayWeekday = match.todayWeekday
    if isNext { return Day(offset: nextWeekOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening) }
    if tokens.contains(where: bengaliThisWords.contains) {
      return Day(offset: weekdayDelta(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
    }
    return Day(offset: comingWeekdayOffset(weekday, todayWeekday: todayWeekday), isEvening: isEvening)
  }

  /// The day of "৩ দিন পর", "দুই সপ্তাহ পরে", "১ মাস বাদে", from the count and
  /// the unit. A count of days or weeks needs no date; a count of months is
  /// counted on the calendar from today. Nil after a genitive or "থেকে", which
  /// tie the amount to another event ("মিটিংয়ের ৩ দিন পর", "আজ থেকে ৩ দিন
  /// পর").
  private static func bengaliRelativeDay(count: Int, unit: String, in match: Match) -> Day? {
    guard count >= 1 else { return nil }
    if let before = bengaliWordBefore(match),
      before.unicodeScalars.last == "র" || ["থেকে", "হতে"].map(bengaliKey).contains(before)
    {
      return nil
    }
    if bengaliHasPrefix(unit, bengaliKey("দিন")) { return Day(offset: count) }
    if bengaliHasPrefix(unit, bengaliKey("সপ্তাহ")) || bengaliHasPrefix(unit, bengaliKey("হপ্তা")) {
      return Day(offset: count * 7)
    }
    guard bengaliHasPrefix(unit, bengaliKey("মাস")), let today = match.today else { return nil }
    let calendar = utcCalendar
    guard let target = calendar.date(byAdding: .month, value: count, to: today),
      let days = calendar.dateComponents([.day], from: today, to: target).day
    else { return nil }
    return Day(offset: days)
  }

  // MARK: - Date range

  /// "৩ থেকে ৫ মে", "৩ মে থেকে ৫ মে", "৩০ জানুয়ারি থেকে ২ ফেব্রুয়ারি", "৩-৫ মে",
  /// "৩ মে হতে ৫ মে", each maybe with a year after a month, and with the
  /// locative ("৩ থেকে ৫ মার্চে"), "-এ" after a year ("৫ মার্চ ২০২৭-এ"), or
  /// "পর্যন্ত" after the end. The start is a date or a day alone ("৩"); the end
  /// is a date. Any other ending after the end, a genitive among them ("৩ থেকে
  /// ৫ মার্চের ছুটি", "৩ থেকে ৫ মে-র ছুটি"), leaves the line unread. Groups: 1
  /// the start, 2 a dash between the sides, 3 "থেকে" or "হতে" between them, 4
  /// the end.
  static var bengaliDateRangePattern: String {
    let bare = #"\d{1,2}\#(bengaliOrdinalSuffix)?\#(bengaliNoMoreDigits)"#
    let side = "\(bengaliMonthDatePattern)|\(bare)"
    let ending = #"(?:·(?:য়ে|ে)|-এ)?"#
    return
      #"\#(bengaliStart)\#(bengaliDateLabel)?(\#(side))(?:\s*([-–—])\s*|\s+(থেকে|হতে)\s+)(\#(side))\#(ending)(?:\#(bengaliUntilWords)\#(bengaliEnd))?+\#(bengaliDateEnd)"#
  }

  /// A range in the past tense names a trip or an event that the task may only
  /// prepare for: it is claimed whole and read as no days, so "৮ মে পর্যন্ত" is
  /// not read alone as a due day. A day alone opens a range joined by a dash
  /// only when the dash touches both sides ("৩-৫ মে"): "Sprint 12 - 20 মে"
  /// names a sprint and a date.
  static func bengaliDateRange(_ match: Match) -> DayRangeReading? {
    guard let startText = match.group(1), let endText = match.group(4),
      let start = bengaliRangeDate(startText), let end = bengaliRangeDate(endText)
    else { return nil }
    if start.month == nil, match.group(2) != nil, !dashTouchesBothSides(match, start: 1, end: 4) { return nil }
    guard end.month != nil else { return nil }
    if bengaliIsNotComing(match) { return .declined }
    return dayRangeReading(from: start, to: end, today: match.today)
  }

  /// A side of a date range: a date ("৫ মে") or a day alone ("৫", "৫ই"), which
  /// has no month.
  private static func bengaliRangeDate(_ text: String) -> ExplicitDate? {
    let words = bengaliPhrase(text)
    if let date = bengaliDate(words) { return date }
    let runs = bengaliRuns(words)
    guard let first = runs.first, let day = number(first), (1...31).contains(day),
      runs.dropFirst().allSatisfy(bengaliOrdinalSuffixes.contains)
    else { return nil }
    return ExplicitDate(day: day)
  }

  /// "সোমবার থেকে বুধবার", "শুক্রবার থেকে সোমবার", "সোমবার হতে বুধবার পর্যন্ত": a
  /// span of weekdays, maybe with "পর্যন্ত" after it and a genitive glued to
  /// its end ("সোমবার থেকে বুধবারের ছুটি"). Groups: 1 the first weekday, 2 the
  /// last, 3 the genitive.
  static var bengaliWeekdayRangePattern: String {
    let names = bengaliWeekdayNames
    let tail = #"(?:\#(bengaliUntilWords))?+"#
    return
      #"\#(bengaliStart)(\#(names))(?:·ে)?\s+(?:থেকে|হতে)\s+(\#(names))(?:·ে)?\#(tail)(·ের)?\#(bengaliEnd)"#
  }

  /// A span of weekdays plans the coming first day and is due on the first last
  /// day after it, so on a Tuesday "সোমবার থেকে বুধবার" runs from next Monday to
  /// the Wednesday after it. A span in the past tense, or one that a genitive
  /// is glued to ("সোমবার থেকে বুধবারের ছুটি" is the holiday of those days), is
  /// claimed whole and read as no days. A span that "প্রতি" or the words for
  /// every day accompany is a habit, which the repeat rules read
  /// (``bengaliIsHabitSpan(_:)``), and Monday to Friday with no such word is
  /// claimed whole too: it is the working week as often as it is a span of
  /// days. A span from a day to itself is no span.
  static func bengaliWeekdayRange(_ match: Match) -> DayRangeReading? {
    guard let firstWord = match.group(1), let lastWord = match.group(2),
      let first = bengaliWeekdayIndex(firstWord), let last = bengaliWeekdayIndex(lastWord), first != last
    else { return nil }
    if match.group(3) != nil || bengaliIsNotComing(match) { return .declined }
    if bengaliIsHabitSpan(match) { return nil }
    if first == 1 && last == 5 { return .declined }
    let start = comingWeekdayOffset(first, todayWeekday: match.todayWeekday)
    return .range(DayRange(start: start, end: start + (last - first + 7) % 7))
  }
}
