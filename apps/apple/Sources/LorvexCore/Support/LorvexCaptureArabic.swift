import Foundation

extension LorvexCaptureVocabulary {
  /// Arabic, read for a user who reads Arabic. A word needs a boundary on both
  /// sides: no Arabic letter, vowel sign, tatweel, joiner, or digit beside it.
  /// A word may carry vowel signs and tatweel anywhere ("غداً", "غدًا", "غدا",
  /// and "غـداً" are one word), and the letters that are spelled in more than
  /// one way are read as one: أ, إ, آ, and ٱ as ا, ى as ي, and ة as ه
  /// ("الأربعاء" and "الاربعاء", "ساعة" and "ساعه"), and a pattern is written
  /// in the natural spelling and read through the same form. The Arabic-Indic
  /// and Extended Arabic-Indic digits ("٣", "۳") are read as the digits they
  /// stand for, beside the Latin ones.
  ///
  /// Arabic writes a one-letter word onto the word after it (و "and", ب, ل, ف,
  /// ك), and the same letters begin many other words, so an attached form is
  /// read only where a rule lists it: و between weekdays ("كل اثنين وخميس"), ل
  /// before an amount, a date, or a day ("لـ 20 دقيقة", "لـ 5 مارس", "ليوم
  /// الخميس", "لمدة ساعة"), ب in "بحلول", "بالليل", and "بأولوية", and ع for
  /// "على" ("ع الساعة 5"). Every other attached word ("وغداً", "لغد", "بغد")
  /// stays in the title.
  ///
  /// Arabic says a clock time with "الساعة" ("الساعة 3", "في الساعة 3:30", "عند
  /// الساعة 9 صباحاً"), with a part of the day after the hour ("الساعة 3
  /// مساءً"), or with ص or م beside an hour that is plainly a time ("الساعة 3
  /// م", "3:30 ص"), so a time needs one of them; a bare number ("اجتماع 3",
  /// "3 م", which is also 3 meters) is never read as an hour. A deadline
  /// written as a clock time ("قبل الساعة 18:00", "حتى 18:00", "بحلول 18:00")
  /// is no start time, so it stays in the title. English is read beside Arabic,
  /// so a detail that needs no Arabic word is left to it: "15:00", "3pm", "for
  /// 2h", "!!", and "p1" read as they do in any line.
  ///
  /// A weekday is a day only with a word before it: "يوم", "في يوم", "ليوم", or
  /// "في" ("يوم الخميس"), "هذا" or "هذه" ("هذا الخميس"), or a part of the day
  /// ("مساء الخميس"); or with a word for next after it ("الخميس القادم").
  /// Alone it is a noun or a name ("صلاة الجمعة", "الجمعة العظيمة"). A weekday
  /// the line puts in the past ("الخميس الماضي") or whose night is meant ("ليلة
  /// الجمعة" is the night before Friday) is not read. "الأحد" needs its
  /// article everywhere: without it "أحد" means "someone" ("كل أحد" is
  /// everyone, "يوم أحد" is the day of the battle of Uhud), so "كل يوم أحد"
  /// stays in the title too.
  ///
  /// - Day: اليوم, الليلة, هذه الليلة, هذا الصباح, هذا المساء, غداً, بكرة (and
  ///   بكرا), بعد غد, each maybe with a part of the day after it ("غداً
  ///   صباحاً", "اليوم مساءً"); بعد 3 أيام, بعد ثلاثة أيام, بعد يومين, بعد يوم
  ///   واحد, بعد أسبوع, بعد أسبوعين, بعد 3 أسابيع, each maybe with "من الآن"
  ///   ("بعد يوم" alone and "بعد 3 أيام من الاجتماع" are not days); الأسبوع
  ///   القادم and في الأسبوع المقبل (seven days ahead); the weekday names with
  ///   the leads above; a date: 5 مارس, 5 من مارس, في 5 مارس, يوم 5 مارس,
  ///   بتاريخ 5 مارس, من 5 مارس, ليوم 5 مارس, 5 مارس 2027, 5 مارس 2027م, 5 كانون
  ///   الثاني. A weekday names the next such day, a full week ahead when it
  ///   names today; "هذا" makes it this week's, today when it names today; a
  ///   word for next ("القادم", "المقبل", "الجاي", "التالي") makes it the coming
  ///   one, a full week ahead when it names today. A phrase after a word that
  ///   sets it against something else ("قبل", "بعد", "حتى", "بحلول", "منذ", "إلى")
  ///   or inside a stretch ("كل", "طوال", "خلال", "نهاية", "بداية", "منتصف", "آخر",
  ///   "أول") is no planned day, and "اليوم" before another word with the article
  ///   ("اليوم الوطني") is no day. The months are the Gregorian ones, in the
  ///   three sets of names the Arab world uses (يناير, كانون الثاني, جانفي); a
  ///   month name needs its day number ("مارس" is also a verb), a date written
  ///   in digits only ("5/3") is not read, and neither is a Hijri date ("3
  ///   رمضان") nor a day written in words.
  /// - Date range: من 3 إلى 5 مارس, من 30 يناير إلى 2 فبراير, من 3 مارس حتى 5
  ///   أبريل, بين 3 و5 مارس, 3-5 مارس, each maybe with a year after the end. The
  ///   first day is the planned day and the last the due day, so another day
  ///   phrase stays in the title. A day written without its month takes the
  ///   month of the end, the end must be after the start ("من 5 إلى 3 مارس" stays
  ///   in the title whole), and an end in an earlier month falls in the next
  ///   year. "إلى" and "حتى" join the sides only after "من", and "و" only after
  ///   "بين". Days of the month with no month ("من 3 إلى 5") are no range.
  /// - Repeat: كل يوم, كل أسبوع, كل شهر, كل سنة, كل عام, كل يومين, كل أسبوعين,
  ///   كل شهرين, كل سنتين, كل 3 أيام, كل ثلاثة أسابيع, كل 15 يوماً, كل 5 سنوات;
  ///   كل صباح, كل مساء, كل ليلة; كل اثنين, كل يوم خميس, كل يوم الخميس, كل الأحد,
  ///   كل اثنين وخميس, كل اثنين وأربعاء وجمعة, الاثنين والخميس من كل أسبوع; كل
  ///   يوم من الأحد إلى الخميس (the span runs through the week's end: "من
  ///   الجمعة إلى الاثنين" is Friday, Saturday, Sunday, Monday); 5 من كل شهر;
  ///   مرة في الأسبوع, مرة في الشهر, مرة واحدة في السنة, مرة كل أسبوعين, مرة كل
  ///   جمعة; the adverbs يومياً, أسبوعياً, شهرياً, and سنوياً only at the end of
  ///   the line, where a part of the day may follow them ("يومياً صباحاً").
  ///   "تقرير يومي" is a title, "كل عام وأنتم بخير" is a greeting, and an
  ///   interval shorter than a day ("كل ساعتين", "كل 15 دقيقة") is no repeat; it
  ///   stays in the title whole, so English does not read its "15 دقيقة" as a
  ///   length.
  /// - Due: a day after قبل, حتى, بحلول, or لغاية ("قبل الخميس", "حتى غداً",
  ///   "بحلول 5 مارس", "قبل يوم الأحد", "لغاية الخميس القادم", "قبل نهاية
  ///   اليوم"), or after "الموعد النهائي", "موعد التسليم", "في موعد أقصاه", "آخر
  ///   موعد", "تاريخ التسليم", or "استحقاق" ("الموعد النهائي: الخميس"). The
  ///   weekday is the due day itself.
  /// - Time: الساعة 3, الساعة 3:30, الساعة 15:00, في الساعة 3, عند الساعة 9, في
  ///   تمام الساعة 5, حوالي الساعة 5, ع الساعة 5; with a part of the day or a
  ///   letter: الساعة 3 مساءً, الساعة 9 صباحاً, الساعة 3 م, الساعة 3:30 ص, 3:30 م,
  ///   9 صباحاً, 3:30 عصراً, في 8 مساءً; with a fraction of the hour: الساعة 3
  ///   ونصف, الساعة 3 وربع, الساعة 3 وثلث, الساعة 3 إلا ربع, الساعة 3 إلا ثلث;
  ///   عند منتصف الليل, في منتصف النهار; a range: من الساعة 2 إلى 4, من الساعة 9
  ///   صباحاً إلى 5 مساءً, من 2 إلى 4 مساءً, من 14:00 إلى 16:00, بين الساعة 2
  ///   و4, الساعة 2-4. The morning is صباحاً, الصباح, الصبح, فجراً (1 to 11
  ///   o'clock; "12 صباحاً" is no time), the day ظهراً, عصراً, بعد الظهر, العصر
  ///   (noon at 12 and the afternoon from 1 to 6), the evening مساءً and
  ///   المساء (1 to 11 o'clock; "12 مساءً" is no time), and the night ليلاً,
  ///   الليل, بالليل: 6 to 11 o'clock is the evening, 12 is the midnight that
  ///   ends the day, and 1 to 5 o'clock are the small hours of the next day. A
  ///   time from 1 to 6 o'clock with no part of the day is the afternoon,
  ///   unless written with a leading zero ("06:30"). A time with no part of its
  ///   own takes the part of the day phrase beside it: "غداً صباحاً الساعة 6"
  ///   is 06:00 and "مساء الخميس الساعة 4" is 16:00, and in "الساعة 5 مساء
  ///   الخميس" the word "مساء" belongs to the day. A range of two bare hours
  ///   counts only after "الساعة" or with a part of the day or a colon ("من 14
  ///   إلى 16 صفحة" is a title). A time after قبل, بعد, حتى, بحلول, منذ, or
  ///   إلى is a bound, not a start ("قبل الساعة 5").
  /// - Length: 20 دقيقة, 30 د, 3 ساعات, ساعتين, 1.5 ساعة, 2 ساعة و30 دقيقة, 1 س
  ///   30 د, نصف ساعة, ربع ساعة, ثلاثة أرباع الساعة, ساعة ونصف, ساعة واحدة,
  ///   ثلاث ساعات, خمس دقائق, عشرين دقيقة, each maybe after لمدة, مدة, حوالي,
  ///   نحو, تقريباً, زهاء, قرابة, ما يقارب, or ل. An amount after بعد, كل, قبل,
  ///   منذ, خلال, في, أكثر من, أقل من, حتى, or إلى names a moment, an interval, or
  ///   a bound, not a length ("بعد 15 دقيقة", "كل ساعتين"), "20 دقيقة في اليوم"
  ///   is a rate, and "20 دقيقة قبل النوم" is a time before something, none a
  ///   length. Such an amount stays whole in the title even when English
  ///   could read part of it. "ساعة" and "دقيقة" alone are nouns (a watch, a
  ///   moment) and are a length only after لمدة, مدة, or an approximation
  ///   ("حوالي ساعة"). The abbreviations د and س need a number before them and
  ///   no letter after, and "50 د.إ" is an amount of money.
  /// - Priority: أولوية عالية, أولوية متوسطة, أولوية منخفضة (also مرتفعة, قصوى,
  ///   عليا, عادية, دنيا, قليلة), each also before the word ("عالية الأولوية"),
  ///   after "ذات", or with the ب attached ("بأولوية عالية"); "عاجل" or "عاجلة"
  ///   at the end of the line, and "عاجل" opening it before a colon or comma.
  ///
  /// The vocabulary accepts some collisions with ordinary words: "ساعتين" and
  /// "ساعات" after a number read as a length where they count watches ("3
  /// ساعات"), "كل اثنين" reads as every Monday where it could say every two,
  /// "اليوم" reads as today in "تقرير اليوم", and a weekday after a part of the
  /// day reads as a day in a title such as "حفلة مساء الخميس". The working days
  /// and the weekend are not read: which days they are depends on the country.
  static let arabic = LorvexCaptureVocabulary(
    readingForm: arabicForMatching,
    priority: [arabicRule(arabicPriorityPattern, read: arabicPriority)],
    dateRange: [arabicRule(arabicDateRangePattern, read: arabicDateRange)],
    keptInTitle: [
      arabicRule(arabicDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      arabicRule(arabicLengthPattern) { arabicDeclinesLength($0) ? true : nil },
    ],
    length: [arabicRule(arabicLengthPattern, read: arabicLength)],
    time: [
      arabicRule(arabicTimeRangePattern, read: arabicTimeRange),
      arabicRule(arabicTimePattern, read: arabicTime),
    ],
    repeats: arabicRepeatRules,
    due: [arabicRule(arabicDuePattern, read: arabicDue)],
    when: [arabicRule(arabicWhenPattern, read: arabicWhen)])

  // MARK: - Reading form and patterns

  /// The line with each letter and digit read in one form: the Arabic-Indic
  /// and the Extended Arabic-Indic digits as ASCII digits, the Arabic decimal
  /// separator and percent sign as "." and "%", the hamza-carrying and wasla
  /// alefs (أ إ آ ٱ) as the bare alef, alef maksura (ى) as yeh (ي), and teh
  /// marbuta (ة) as heh (ه). Written with or without these distinctions, a
  /// word reads the same ("الأربعاء" and "الاربعاء", "ساعة" and "ساعه"), and a
  /// pattern, written in its natural spelling, is read through the same form
  /// by ``arabic(_:)``. Each replacement is one UTF-16 unit for one, so a
  /// match range in the result is the same range in `line`.
  static func arabicForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(arabicReading(of: scalar)) }
    return String(scalars)
  }

  private static func arabicReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{0660}"..."\u{0669}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x0660))
    case "\u{06F0}"..."\u{06F9}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x06F0))
    case "\u{066B}": "."
    case "\u{066A}": "%"
    case "\u{0622}", "\u{0623}", "\u{0625}", "\u{0671}": "\u{0627}"
    case "\u{0649}": "\u{064A}"
    case "\u{0629}": "\u{0647}"
    default: scalar
    }
  }

  /// Whether `scalar` is a vowel sign (harakat, including the tanween and the
  /// shadda), the dagger alef, or the tatweel, which a typed word may carry
  /// between or after its letters without changing it.
  private static func isArabicMark(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value == 0x0640 || (0x064B...0x065F).contains(scalar.value) || scalar.value == 0x0670
  }

  /// `text` without its vowel signs and tatweel: the letters of a matched word
  /// as a reader compares them. `text` is already in the reading form.
  static func arabicBare(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isArabicMark(scalar) { scalars.append(scalar) }
    return String(scalars)
  }

  /// A matched phrase as a reader compares it: without vowel signs and
  /// tatweel, each run of spaces as one.
  static func arabicPhrase(_ text: String) -> String {
    normalizedPhrase(arabicBare(text))
  }

  /// `pattern`, written in the natural spelling of its words, ready to match a
  /// line in the reading form: each Arabic letter outside a character set is
  /// read through ``arabicForMatching(_:)`` and may be followed by vowel signs
  /// and tatweel (غداً, غدًا, غدا, and غـداً are one word), and a letter that a
  /// quantifier follows ("ثلاثاء?") keeps the quantifier on the letter with its
  /// signs. Escapes and character sets pass through, their letters read
  /// through the same form. Patterns hold no lookbehind that contains a
  /// letter, since the signs after a letter make its length unbounded.
  static func arabic(_ pattern: String) -> String {
    let signs = #"[\p{M}\x{0640}]*"#
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let scalars = Array(pattern.unicodeScalars)
    var result = ""
    var isEscaped = false
    var isInSet = false
    for (index, scalar) in scalars.enumerated() {
      if isEscaped {
        result.unicodeScalars.append(scalar)
        isEscaped = false
      } else if scalar == "\\" {
        result.unicodeScalars.append(scalar)
        isEscaped = true
      } else if isInSet {
        if scalar == "]" { isInSet = false }
        result.unicodeScalars.append(arabicReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else {
        let reading = arabicReading(of: scalar)
        guard ("\u{0621}"..."\u{064A}").contains(reading), reading.value != 0x0640 else {
          result.unicodeScalars.append(scalar)
          continue
        }
        let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
        let letter = "\(Character(reading))\(signs)"
        result += isQuantified ? "(?:\(letter))" : letter
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in natural spelling (see
  /// ``arabic(_:)``).
  static func arabicRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: arabic(pattern), read: read)
  }

  // MARK: - Boundaries and words around a detail

  /// A word boundary for words written in Arabic letters: no Arabic letter,
  /// vowel sign, digit, tatweel, or joiner on that side, so a word is never
  /// cut out of a longer one.
  static let arabicStart = #"(?<![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}])"#
  static let arabicEnd = #"(?![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}])"#

  /// What may follow a clock time: no Arabic letter, vowel sign, digit, or
  /// colon (the word or the number goes on), no decimal fraction, no percent or
  /// currency sign with or without a space before it (the number is an amount),
  /// and no dash before a digit, which makes the time one side of a range
  /// written with a dash ("14:00-16:00").
  static let arabicTimeEnd =
    #"(?![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Arabic letter, vowel sign, digit, or colon, and
  /// no decimal fraction.
  static let arabicDateEnd = #"(?![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}:]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let arabicNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The word just before `match`, as a reader compares it (without vowel
  /// signs), or nil when the match opens the line or punctuation comes first.
  static func arabicWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(arabicBare), !word.isEmpty else { return nil }
    return word
  }

  /// The words before a day, an hour, or an amount that make it a bound, a
  /// moment relative to something else, or a past one, so it names no start
  /// time, planned day, or length: "قبل الساعة 5" (before 5 o'clock), "بعد
  /// الخميس" (after Thursday), "حتى الساعة 5" (until 5 o'clock), "منذ يوم
  /// الخميس" (since Thursday).
  static let arabicBoundWords: Set<String> = ["قبل", "بعد", "حتي", "بحلول", "لغايه", "الي", "منذ", "مذ"]

  /// The numerals one to ten that stand before a counted noun in the plural,
  /// in both genders ("ثلاث ساعات", "خمسة أيام"), written as the reading form
  /// reads them.
  static let arabicCounts: [String: Int] = {
    let spellings: [(Int, [String])] = [
      (3, ["ثلاث", "ثلاثة"]), (4, ["أربع", "أربعة"]), (5, ["خمس", "خمسة"]), (6, ["ست", "ستة"]),
      (7, ["سبع", "سبعة"]), (8, ["ثماني", "ثمان", "ثمانية"]), (9, ["تسع", "تسعة"]), (10, ["عشر", "عشرة"]),
    ]
    var counts: [String: Int] = [:]
    for (value, words) in spellings {
      for word in words { counts[arabicForMatching(word)] = value }
    }
    return counts
  }()

  /// The count words as a pattern.
  static var arabicCountWords: String {
    alternation(of: Array(arabicCounts.keys))
  }

  // MARK: - Priority

  /// Group 1: a written priority, in either order ("أولوية عالية", "عالية
  /// الأولوية"), each maybe after "ذات" or with a "ب" attached ("بأولوية
  /// عالية"); "عاجل" has no group.
  private static var arabicPriorityPattern: String {
    let level =
      "عالية|عالي|مرتفعة|مرتفع|قصوى|عليا|متوسطة|متوسط|عادية|عادي|منخفضة|منخفض|دنيا|قليلة|ضعيفة|متدنية"
    return
      #"\#(arabicStart)((?:ذات\s+|ب)?(?:ال)?أولوية\s*:?\s*(?:ال)?(?:\#(level))|(?:\#(level))\s+(?:ال)?أولوية)\#(arabicEnd)|(?<=\s)(?:بشكل\s+)?عاجل(?:ة|ا)?(?=\s*$)|^\s*عاجل(?:ة)?(?=\s*[،,:：])"#
  }

  private static func arabicPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(arabicPhrase) else { return .p1 }
    if ["متوسط", "عادي"].contains(where: phrase.contains) { return .p2 }
    if ["منخفض", "دنيا", "قليل", "ضعيف", "متدني"].contains(where: phrase.contains) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "20 دقيقة", "30 د", "3 ساعات", "ساعتين", "1.5 ساعة", "2 ساعة و30 دقيقة",
  /// "1 س 30 د", "نصف ساعة", "ربع ساعة", "ساعة ونصف", "ثلاث ساعات", "خمس دقائق",
  /// each maybe after "لمدة", "حوالي", or "ل". Groups: 1 a word that opens a
  /// length; 2 a word that makes the amount a moment, an interval, or a bound
  /// ("بعد 15 دقيقة", "كل ساعتين"); 3 the hours of an amount with a unit and
  /// 4 its minutes; 5 minutes; 6 a length in words; 7 a word after the amount
  /// that makes it the past, a comparison, or a rate ("20 دقيقة قبل
  /// الاجتماع", "20 دقيقة في اليوم"). A match with group 2 or 7 is no length:
  /// ``arabicLength(_:)`` declines it and a keep rule claims it. The amount may
  /// not follow a digit, a colon, or a separator, and it may not be a side of a
  /// range ("2-3 ساعات"). The abbreviations د and س are read only when no
  /// letter follows them or a dot between letters ("50 د.إ" is an amount of
  /// money).
  static var arabicLengthPattern: String {
    let opener =
      #"(?:(لمدة|مدة|حوالي|نحو|تقريبا|زهاء|قرابة|ما\s+يقارب|ل\x{0640}?)\s*|(بعد|كل|قبل|منذ|مذ|خلال|في|أكثر\s+من|أقل\s+من|لأكثر\s+من|لأقل\s+من|حتى|إلى|ما\s+يزيد\s+عن|يزيد\s+عن|ما\s+يقل\s+عن|يقل\s+عن)\s+)?"#
    let boundaries = #"(?<![\p{N}:.,])(?<!\p{N}\s?[-–—]\s?)"#
    let abbreviation = #"(?!\.\p{Arabic})"#
    let hours =
      #"(\d+(?:[.,]\d+)?)\s*(?:ساعتين|ساعتان|ساعات|ساعة|س\#(abbreviation))(?:(?:\s*و\s*|\s+)(\d{1,2})\s*(?:دقيقتين|دقيقتان|دقائق|دقيقة|د\#(abbreviation)))?"#
    let minutes = #"(\d+)\s*(?:دقيقتين|دقيقتان|دقائق|دقيقة|د\#(abbreviation))"#
    let fraction = #"و\s*(?:ال)?(?:نصف|ربع)"#
    let words =
      #"(نصف\s+(?:ال)?ساعة|ربع\s+(?:ال)?ساعة|ثلاثة\s+أرباع\s+(?:ال)?ساعة|ساعة\s+\#(fraction)|ساعتين\s+\#(fraction)|ساعتان\s+\#(fraction)|ساعة\s+واحدة|ساعتين|ساعتان|دقيقة\s+واحدة|دقيقتين|دقيقتان|(?:\#(arabicCountWords))\s+(?:ساعات|دقائق)|(?:عشرين|ثلاثين|أربعين|خمسين)\s+دقيقة|ساعة|دقيقة)"#
    let trailing =
      #"(?:\s+(?:تقريبا|(قبل|بعد|مضت|مضى|سابقا|لاحقا|(?:في|خلال|لكل)\s+(?:ال)?(?:يوم|أسبوع|شهر|سنة|عام|ساعة|دقيقة)))\#(arabicEnd))?"#
    return
      #"\#(arabicStart)\#(opener)\#(boundaries)(?:\#(hours)|\#(minutes)|\#(words))\#(arabicEnd)(?!\s*[-–—]\s*\d|\s+(?:إلى|حتى)\s+\d)\#(trailing)"#
  }

  /// True for a match that is no length: a moment, an interval, or a bound
  /// ("بعد 15 دقيقة", "كل ساعتين"), a past or a rate ("20 دقيقة في اليوم"), or
  /// the end of a range of amounts ("من 2 إلى 3 ساعات").
  private static func arabicDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil || arabicIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number and a word that means
  /// "to" ("من 2 إلى"), which makes the amount the end of a range.
  private static func arabicIsRangeEnd(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let before = arabicBare(String(match.source[..<start]))
    return before.firstMatch(of: /\d\s+(?:الي|حتي)\s+$/) != nil
  }

  private static func arabicLength(_ match: Match) -> Int? {
    if arabicDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    guard let phrase = match.group(6).map(arabicPhrase) else { return nil }
    let tokens = phrase.split(separator: " ").map(String.init)
    let fraction = phrase.contains("نصف") ? 30 : 15
    if tokens.starts(with: ["ثلاثه", "ارباع"]) { return 45 }
    switch tokens[0] {
    case "نصف": return 30
    case "ربع": return 15
    case "ساعتين", "ساعتان": return 120 + (tokens.count > 1 ? fraction : 0)
    case "ساعه":
      if tokens.count == 1 { return arabicIsDuration(match) ? 60 : nil }
      return tokens[1] == "واحده" ? 60 : 60 + fraction
    case "دقيقتين", "دقيقتان": return 2
    case "دقيقه":
      if tokens.count == 1 { return arabicIsDuration(match) ? 1 : nil }
      return 1
    case "عشرين", "ثلاثين", "اربعين", "خمسين":
      return ["عشرين": 20, "ثلاثين": 30, "اربعين": 40, "خمسين": 50][tokens[0]]
    default:
      guard tokens.count == 2, let count = arabicCounts[tokens[0]] else { return nil }
      return taskLength(minutes: tokens[1] == "ساعات" ? count * 60 : count)
    }
  }

  /// Whether the word that opens the match says that what follows is a stretch
  /// of time ("لمدة ساعة", "حوالي ساعة"). "ساعة" and "دقيقة" alone are nouns (a
  /// watch, a moment) unless a word of duration or of approximation opens them.
  /// The bare "ل" does not: "لساعة" is as often "for a watch".
  private static func arabicIsDuration(_ match: Match) -> Bool {
    match.group(1).map(arabicPhrase).map { $0 != "ل" } ?? false
  }
}
