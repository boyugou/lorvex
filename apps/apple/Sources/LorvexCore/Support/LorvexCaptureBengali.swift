import Foundation

extension LorvexCaptureVocabulary {
  /// Bengali, read for a user who reads Bengali in the Bengali script (Bangladesh
  /// and India). A word needs a boundary of Bengali letters, signs, digits, and
  /// joiners on both sides (``bengaliStart``), so "আজকাল" (nowadays) and
  /// "কালো" (black) hold no day, and a hyphen between two Bengali words joins
  /// them. The danda (।) is punctuation. Bengali glues its case endings to the
  /// word ("সোমবারে", "অক্টোবরের", "৫টায়"), so each rule lists the endings it
  /// reads, and a word with any other ending is another word and stays in the
  /// title ("সোমবারের মিটিং", "আজকের কাজ"). A zero-width joiner or non-joiner
  /// typed before a listed ending changes nothing.
  ///
  /// The line is read in one form (``bengaliForMatching(_:)``): the Bengali
  /// digits as Latin ones ("৫টায়" is "5টায়") and the precomposed ড়, ঢ়, and য়
  /// (U+09DC, U+09DD, U+09DF, which Unicode normalization writes as a letter and
  /// a nukta) as the letters ড, ঢ, and য. A nukta typed as a separate sign after
  /// its letter, a joiner next to a hasanta, a vowel sign ো or ৌ typed as one
  /// sign or as its two parts, and the candrabindu of পাঁচ are tolerated in every
  /// word, so "জানুয়ারি", "সাড়ে", and "ঘণ্টা" read however a keyboard writes
  /// them, and "ঘন্টা" and "রোববার" are read beside "ঘণ্টা" and "রবিবার". The
  /// title keeps what was typed. Bengali written in Latin letters ("kal
  /// sokale") is not read.
  ///
  /// English is read beside Bengali, so a detail that needs no Bengali word is
  /// left to English, which reads its own "5pm", "17:30", "30 min", or "2h".
  /// Bengali does not write a clock time with the letter h, so "2h" beside
  /// Bengali stays a length.
  ///
  /// কাল means "tomorrow" and also "yesterday", and পরশু means "the day after
  /// tomorrow" and also "the day before yesterday". This vocabulary reads both
  /// as the future day and never reads গতকাল or any other past day. A day
  /// phrase is left unread when its line says the day is past or not coming: a
  /// past-tense form anywhere in the line (ছিল, ছিলাম, করেছি, গিয়েছিলাম, হয়েছিল,
  /// and the other listed forms: "কাল মিটিং ছিল"), or গত, গেল, আগের, বিগত,
  /// পরবর্তী, শেষ, or an ordinal (প্রথম, দ্বিতীয়, তৃতীয়, চতুর্থ) just before it
  /// ("গত শুক্রবার", "প্রথম শুক্রবার"). The rule holds for আজ and the weekdays
  /// too.
  ///
  /// A weekday is a day only with its full name ending in বার: the short
  /// stems রবি, সোম, মঙ্গল, বুধ, বৃহস্পতি, শুক্র, and শনি are ordinary words
  /// or names, and so are the one-letter forms the system writes. A day phrase
  /// that a genitive follows (-র, -ের) is an attribute of a noun, not a plan
  /// ("সোমবারের মিটিং", "আজকের কাজ").
  ///
  /// - Day: আজ, আজকে, আজই, আগামীকাল, কাল, কালকে, পরশু, each maybe with a part
  ///   of the day (সকাল, ভোর, দুপুর, বিকেল, সন্ধ্যা, রাত, with or without the
  ///   locative -ে or -য়: "আজ রাতে", "আগামীকাল সকাল"); the weekday names
  ///   (রবিবার or রোববার, সোমবার, মঙ্গলবার, বুধবার, বৃহস্পতিবার, শুক্রবার,
  ///   শনিবার), alone or with the locative -ে or -ই, or after এই (this
  ///   week's), পরের (next week's, weeks starting on Monday), or আগামী, আসছে,
  ///   সামনের, or আসন্ন (the coming one), with "সপ্তাহের" between ("পরের
  ///   সপ্তাহের শুক্রবার") and maybe a part of the day after; "পরের সপ্তাহে" and
  ///   its likes alone (seven days ahead); "৩ দিন পর", "তিন দিন পরে", "২ সপ্তাহ
  ///   বাদে", "১ মাস পর" (months counted on the calendar); the weekend,
  ///   "উইকেন্ড", "সপ্তাহান্ত", "সপ্তাহের শেষে", or "শনিবার ও রবিবার", alone or
  ///   after এই, আগামী, আসছে, সামনের, or পরের; a date ("১৫ অক্টোবর", "১৫ই
  ///   অক্টোবর ২০২৬", "অক্টোবর ১৫", "তারিখ ১৫ অক্টোবর", "সোমবার, ৫
  ///   অক্টোবর", "১৫ অক্টোবরে", "১৫ তারিখে"; "১৫/১০/২০২৬", "১৫.১০.২০২৬",
  ///   "১৫-১০-২০২৬", and "১৫.১০." in digits; "১৫/১০" and "১৫.১০" only after
  ///   তারিখ or before তারিখে, -এ, or -তে), with or without থেকে or "-র জন্য"
  ///   after it. A day word or a weekday may be followed by থেকে or হতে ("কাল
  ///   থেকে জিম শুরু" plans tomorrow), unless the থেকে starts a counted day ("আজ
  ///   থেকে ৩ দিন পর" stays whole). A weekday alone means the next such day, a
  ///   full week ahead when it names today, and "এই মঙ্গলবার" is today when it
  ///   names today. "এই
  ///   সপ্তাহে" alone names no single day and is not read. The weekend is the
  ///   coming Saturday (today on a Saturday or a Sunday) and, after পরের, the
  ///   Saturday a week later. A date needs its day number beside the month name
  ///   (জানুয়ারি, ফেব্রুয়ারি, মার্চ, এপ্রিল, মে, জুন, জুলাই, আগস্ট, সেপ্টেম্বর,
  ///   অক্টোবর, নভেম্বর, ডিসেম্বর, and the short forms the system writes next to
  ///   a day: জানু, ফেব, এপ্রি, জুল, আগ, সেপ, অক্টো, নভে, ডিসে, and the visarga
  ///   forms of bn-IN, with or without a dot, after a day number only); a month
  ///   alone, a date in digits with no label and no ending ("৫/১০"), a date the
  ///   calendar lacks ("৩১ এপ্রিল"), and the months of the Bengali calendar
  ///   (বৈশাখ, জ্যৈষ্ঠ, ...) stay in the title.
  /// - Date range: "৩ থেকে ৫ মে", "৩ মে থেকে ৫ মে", "৩০ জানুয়ারি থেকে ২
  ///   ফেব্রুয়ারি", "৩-৫ মে", each maybe with হতে for থেকে, a year after a
  ///   month, the locative or -এ after the end ("৩ থেকে ৫ মার্চে", "৫ মার্চ
  ///   ২০২৭-এ"), and পর্যন্ত after the end. The first day is the planned day
  ///   and the last the due day, so another day phrase stays in the title. A day
  ///   written without its month takes the month of the end, the end must be
  ///   after the start ("৫ থেকে ৩ মার্চ" stays in the title whole), and the end
  ///   names a month, so "৩ থেকে ৫" is never a range of days. A day alone opens a
  ///   range joined by a dash only when the dash touches both sides: "Sprint 12
  ///   - 20 মে" names a sprint and a date. A range in the past tense, or one that
  ///   a genitive follows, may be an event the task only prepares for: it stays
  ///   in the title whole. A span of weekdays ("সোমবার থেকে বুধবার", "শুক্রবার
  ///   থেকে সোমবার") plans the coming first day and is due on the first last day
  ///   after it. After প্রতি or beside the words for every day it is a repeat
  ///   instead, and Monday to Friday with none of them stays in the title
  ///   whole, since it is a week of work as often as it is the working week.
  /// - Repeat: প্রতিদিন, রোজ, প্রত্যহ, and প্রতি, রোজ, or প্রতিদিন with a part of
  ///   the day ("প্রতি সকালে", "রোজ রাতে"), which keeps its part for an hour
  ///   beside it ("প্রতি সকালে ৬টায় যোগব্যায়াম" is every day at 06:00); "প্রতি
  ///   সপ্তাহে", "প্রতি মাসে", "প্রতি বছর", "প্রত্যেক দিন"; "প্রতি সোমবার", "প্রতি
  ///   সোমবারে", "প্রতি সোমবার ও বৃহস্পতিবার", "প্রতি সোমবার, বুধবার ও
  ///   শুক্রবার", "প্রতি দ্বিতীয় সোমবারে", "প্রতি সপ্তাহে সোমবার"; "প্রতি ২ দিন
  ///   অন্তর", "প্রতি ২ সপ্তাহে", "প্রতি তিন মাসে", "প্রতি দ্বিতীয় সপ্তাহে", "৩
  ///   মাস পর পর"; "একদিন অন্তর" and "এক সপ্তাহ অন্তর" (every other day or
  ///   week); "দিনে একবার", "সপ্তাহে একবার", "মাসে একবার", "বছরে একবার"; "প্রতি
  ///   মাসের ৫ তারিখে", "প্রতি মাসে ৫ তারিখে"; "প্রতি সপ্তাহান্তে", "প্রতি
  ///   উইকেন্ডে"; the working days as "কর্মদিবসে", "প্রতি কর্মদিবস", or "কাজের
  ///   দিনে"; a span of weekdays with প্রতি or the words for every day ("প্রতি
  ///   সোমবার থেকে শুক্রবার", "সোমবার থেকে শুক্রবার প্রতিদিন"); and দৈনিক,
  ///   সাপ্তাহিক, মাসিক, or বার্ষিক at the end of the line, before a colon or comma,
  ///   or with "ভিত্তিতে", "হিসেবে", or "-ভাবে", since they are ordinary
  ///   adjectives too ("দৈনিক রিপোর্ট" is a daily report, and a দৈনিক is a
  ///   newspaper). An interval shorter than a day ("প্রতি ২ ঘণ্টায়") is no
  ///   repeat, and a cadence word that makes an attribute of a noun is none
  ///   ("প্রতিদিনের কাজ", "প্রতি মাসের খরচ"). "রোজা" and "রোজকার" are other
  ///   words. প্রতি is also the word for a rate, so "প্রতি দিন ৫০০ টাকা" is read
  ///   as a daily repeat.
  /// - Due: a day before পর্যন্ত or অবধি, or with the genitive before মধ্যে,
  ///   আগে, or পূর্বে ("শুক্রবার পর্যন্ত", "শুক্রবারের মধ্যে", "আগামীকালের
  ///   আগে", "১৫ অক্টোবরের মধ্যে", "আজকের মধ্যে", "আজ রাতের মধ্যে"); after
  ///   শেষ তারিখ, অন্তিম তারিখ, ডেডলাইন, or সময়সীমা ("শেষ তারিখ: শুক্রবার",
  ///   "ডেডলাইন ১৫ অক্টোবর"). A day before a clock deadline ("শুক্রবার সন্ধ্যা
  ///   ৫টার মধ্যে") is the due day, and the clock with its part of the day
  ///   stays in the title. "আজ পর্যন্ত" ("so far") is not read, nor is a
  ///   deadline that a genitive follows, nor a day that পর্যন্ত follows with
  ///   another ending ("শুক্রবার পর্যন্তের কাজ" is work that runs up to Friday).
  /// - Time: "৫টায়", "৫:৩০টায়", "সাড়ে ৩টায়" (3:30), "সোয়া ৩টায়" (3:15),
  ///   "পৌনে ৪টায়" (3:45), "দেড়টায়" (1:30), "আড়াইটায়" (2:30), "পাঁচটায়",
  ///   "সাড়ে তিনটে", each maybe after ঠিক, প্রায়, or আনুমানিক. The hour takes the
  ///   classifier টা, টে, or টো: with the locative ending (টায়, টেয়, টোয়) or
  ///   before "সময়", "দিকে", or "নাগাদ" it is a time by itself. With no ending
  ///   it is a time only after a part of the day, as a fraction, দেড় or আড়াই,
  ///   or as a range, since "৫টা বই" and "দুটো ডিম" count things. A part of the
  ///   day sets the hour and comes before it ("সকাল ৯টা", "রাত ১০টায়", "বিকেল
  ///   ৫টায়", "সকালে ঠিক ৬টায়"). সকাল and ভোর are the morning (12 is no
  ///   time), দুপুর is noon at 12 and the afternoon from 1 to 6, বিকেল and সন্ধ্যা
  ///   are the evening, and রাত runs past midnight: "রাত ১২টায়" is 00:00 of the
  ///   next day, "রাত ২টায়" is 02:00 of the next day, and "রাত ৮টায়" is 20:00.
  ///   "মধ্যরাতে" is the midnight that ends the day. The minutes may follow the
  ///   classifier with the locative of মিনিট ("সকাল ১০টা ৩০ মিনিটে" is 10:30);
  ///   "৫টা ৩০ মিনিট" is an hour and a length, and so is "৫টায় ৩০ মিনিটে".
  ///   A part of the day with a
  ///   colon time and no টা ("সকাল ৯:৩০", "রাত ১০.৩০"), and a colon time with
  ///   "এ" glued, after a hyphen, or after a space ("৩:৩০ PM-এ", "১৭:৩০-এ",
  ///   "৭:৩০ এ"), are times too. An hour on the 12-hour clock
  ///   (1 to 12, no leading zero) written with no part of the day beside it takes
  ///   its half of the day from the one part of the day the line names elsewhere:
  ///   in its day phrase ("আগামীকাল সকালে মিটিং ৬টায়" is 06:00), after প্রতি or
  ///   রোজ ("রোজ সকালে ৬টায় যোগব্যায়াম"), or in a noun ("রাতের খাবার ৮টায়" is
  ///   20:00, "সকালের হাঁটা ৬টায়" is 06:00). Two parts that differ leave the
  ///   hour as it reads alone, and an hour on the 24-hour clock (a leading
  ///   zero, 0, or 13 and later) is read as written. An hour from 1 to 6 with no
  ///   part of the day anywhere in the line is the afternoon, as in the other
  ///   languages ("৫টায়" is 17:00, "৭টায়" is 07:00), unless written with a
  ///   leading zero ("০৬:৩০টায়"). A range: "৩টা থেকে ৫টা", "সকাল ৯টা থেকে
  ///   ১১টা পর্যন্ত", "৩ থেকে ৫টায়", "৩-৫টায়", "১৪:০০ থেকে ১৬:০০"; the end
  ///   carries a classifier, so "৩ থেকে ৫" is no range. A clock time that is a
  ///   bound stays in the title whole: "৫টার মধ্যে", "সন্ধ্যা ৬টার আগে", "৫টা
  ///   পর্যন্ত", "১৮:০০ পর্যন্ত", "৩ PM পর্যন্ত". A number before a percent sign,
  ///   a currency sign, or a currency word is never a time.
  /// - Length: "৩০ মিনিট", "২ ঘণ্টা", "১.৫ ঘণ্টা", "১ ঘণ্টা ৩০ মিনিট", "আধ
  ///   ঘণ্টা", "দেড় ঘণ্টা", "আড়াই ঘণ্টা", "সোয়া ঘণ্টা" (75), "পৌনে এক ঘণ্টা"
  ///   (45), "সাড়ে তিন ঘণ্টা", "দুই ঘণ্টা", "বিশ মিনিট", "ঘণ্টাখানেক", each maybe
  ///   after প্রায়, আনুমানিক, or মোটামুটি, and with a genitive or "জন্য" or "ধরে"
  ///   after the unit, which goes with it ("৩০ মিনিটের মিটিং" is a meeting of 30
  ///   minutes, "২ ঘণ্টার জন্য" is for 2 hours). An amount before পর, পরে, আগে,
  ///   বাদে, অন্তর, or মধ্যে, or after প্রতি, অন্তত, কমপক্ষে, or দিনে, names a
  ///   moment, an interval, or a bound, not a length ("২ ঘণ্টা পর", "প্রতি ২
  ///   ঘণ্টা", "২ ঘণ্টার মধ্যে", "দিনে ২ ঘণ্টা"), and neither is a side of a
  ///   range ("২ থেকে ৩ ঘণ্টা", "২-৩ ঘণ্টা"): each stays whole in the title. An
  ///   amount whose unit has any other ending ("২ ঘণ্টায়", "৩০ মিনিটে") is no
  ///   length, and "ঘণ্টা" alone is none.
  /// - Priority: উচ্চ প্রাধান্য, মধ্যম প্রাধান্য, নিম্ন প্রাধান্য (also সর্বোচ্চ,
  ///   বেশি, মাঝারি, সাধারণ, স্বাভাবিক, সর্বনিম্ন, কম, and অগ্রাধিকার for
  ///   প্রাধান্য), each also after the word ("প্রাধান্য: উচ্চ"); জরুরি, অতি
  ///   জরুরি, আর্জেন্ট, or গুরুত্বপূর্ণ at the end of the line, and the same
  ///   words opening it before a colon or comma ("জরুরি: রিপোর্ট পাঠান"). These
  ///   are ordinary adjectives too, so "জরুরি বিভাগে যান" and "রিপোর্ট জরুরি
  ///   আছে" stay in the title.
  static let bengali = LorvexCaptureVocabulary(
    readingForm: bengaliForMatching,
    priority: [bengaliRule(bengaliPriorityPattern, read: bengaliPriority)],
    dateRange: [
      bengaliRule(bengaliDateRangePattern, read: bengaliDateRange),
      bengaliRule(bengaliWeekdayRangePattern, read: bengaliWeekdayRange),
    ],
    keptInTitle: [
      bengaliRule(bengaliDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      bengaliRule(bengaliLengthPattern) { bengaliDeclinesLength($0) ? true : nil },
    ],
    length: [bengaliRule(bengaliLengthPattern, read: bengaliLength)],
    time: [
      bengaliRule(bengaliTimeRangePattern, read: bengaliTimeRange),
      bengaliRule(bengaliColonTimeRangePattern, read: bengaliTimeRange),
      bengaliRule(bengaliTimePattern, read: bengaliTime),
      bengaliRule(bengaliColonTimePattern, read: bengaliColonTime),
      bengaliRule(bengaliMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
    ],
    repeats: bengaliRepeatRules,
    due: [bengaliRule(bengaliDuePattern, read: bengaliDue)],
    when: [bengaliRule(bengaliWhenPattern, read: bengaliWhen)])

  // MARK: - Reading form and patterns

  /// The line with each digit and letter read in one form: the Bengali digits
  /// (০-৯) as ASCII digits, and the precomposed ড়, ঢ়, and য় (U+09DC, U+09DD,
  /// U+09DF) as ড, ঢ, and য. A nukta typed as a separate sign stays where it was
  /// typed: a pattern, written in the base letters, tolerates it after those
  /// three letters (``bengali(_:)``). Each replacement is one UTF-16 unit for
  /// one, so a match range in the result is the same range in `line`.
  static func bengaliForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(bengaliReading(of: scalar)) }
    return String(scalars)
  }

  private static func bengaliReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{09E6}"..."\u{09EF}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x09E6))
    case "\u{09DC}": "\u{09A1}"
    case "\u{09DD}": "\u{09A2}"
    case "\u{09DF}": "\u{09AF}"
    default: scalar
    }
  }

  /// `text` as a reader compares a word: in canonical composed form (so a ো
  /// typed as ে and া is the one sign), without its nukta signs, candrabindu, and
  /// zero-width joiners, and with the long vowel signs ী and ূ read as the short
  /// ones, so the two spellings of "আগামীকাল" and "জরুরি" are one word. `text`
  /// is already in the reading form. Comparisons of Bengali text go through
  /// scalars or whole words: a `Character` is a grapheme cluster ("কি" is one),
  /// so `hasPrefix("ক")` does not match "কিনুন".
  static func bengaliBare(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
      switch scalar {
      case "\u{09BC}", "\u{0981}", "\u{200C}", "\u{200D}": continue
      case "\u{09C0}": result.append("\u{09BF}")
      case "\u{09C2}": result.append("\u{09C1}")
      default: result.append(scalar)
      }
    }
    return String(result)
  }

  /// A matched phrase as a reader compares it: as ``bengaliBare(_:)`` leaves
  /// it, each run of spaces as one, hyphens read as spaces.
  static func bengaliPhrase(_ text: String) -> String {
    normalizedPhrase(bengaliBare(text))
  }

  /// A word written in a vocabulary table, as ``bengaliPhrase(_:)`` leaves a
  /// matched word, whichever way the table spells it.
  static func bengaliKey(_ word: String) -> String {
    bengaliBare(bengaliForMatching(word))
  }

  /// Whether the scalars of `key` start with the scalars of `prefix`. Both are
  /// in the form ``bengaliKey(_:)`` leaves them.
  static func bengaliHasPrefix(_ key: String, _ prefix: String) -> Bool {
    key.unicodeScalars.starts(with: prefix.unicodeScalars)
  }

  /// `pattern`, written in the base letters of its words, ready to match a
  /// line in the reading form.
  ///
  /// The letters ড, ঢ, and য may be followed by a nukta, a hasanta may have
  /// zero-width joiners on either side (the joiner of "র‍্য" comes before it),
  /// the vowel signs ো and ৌ also match the two signs they are made of, the
  /// candrabindu may be left out, and a quantifier that follows such a letter
  /// applies to the letter with its extras. A middle dot (·) marks the boundary
  /// between a word and an ending glued to it, where a zero-width joiner or
  /// non-joiner may have been typed. The pattern is read in canonical composed
  /// form, so a letter or sign typed there in any spelling is read like its
  /// base. Escapes and character sets pass through, the letters in a set read
  /// through the reading form. A pattern is expanded once, by
  /// ``bengaliRule(_:read:)``, never in parts that another pattern then embeds.
  static func bengali(_ pattern: String) -> String {
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let joiners = #"[\x{200C}\x{200D}]{0,2}"#
    let scalars = Array(
      pattern.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
        $0 != "\u{09BC}" && $0 != "\u{200C}" && $0 != "\u{200D}"
      })
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
        result.unicodeScalars.append(bengaliReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else if scalar == "\u{00B7}" {
        result += joiners
      } else {
        let reading = bengaliReading(of: scalar)
        var unit = String(Character(reading))
        switch reading {
        case "\u{09A1}", "\u{09A2}", "\u{09AF}":
          unit += #"\x{09BC}?"#
        case "\u{09CD}":
          unit = joiners + unit + joiners
        case "\u{0981}":
          unit = #"\x{0981}?"#
        case "\u{09CB}":
          unit = #"(?:\x{09CB}|\x{09C7}\x{09BE})"#
        case "\u{09CC}":
          unit = #"(?:\x{09CC}|\x{09C7}\x{09D7})"#
        default:
          break
        }
        let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
        result += unit.count > 1 && isQuantified && !unit.hasPrefix("(?:") ? "(?:\(unit))" : unit
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in base letters (see ``bengali(_:)``).
  static func bengaliRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: bengali(pattern), read: read)
  }

  /// Whether `pattern`, written in base letters, matches somewhere in `text`,
  /// which is in the reading form.
  static func bengaliFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(bengali(pattern)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Boundaries and words around a detail

  /// A word boundary for words written in the Bengali script: no Bengali letter,
  /// vowel sign, hasanta, nukta, candrabindu, anusvara, visarga, joiner, or
  /// digit on that side, and no hyphen that joins it to another Bengali word
  /// ("আজ-কাল" is one word, "nowadays"). The danda (।) is punctuation and a
  /// boundary.
  static let bengaliStart =
    #"(?<![\p{Bengali}\p{M}\p{N}\x{200C}\x{200D}])(?<![\p{Bengali}\p{M}]-)"#
  static let bengaliEnd =
    #"(?![\p{Bengali}\p{M}\p{N}\x{200C}\x{200D}])(?!-\p{Bengali})"#

  /// What may follow a clock time: no Bengali letter, vowel sign, digit, or
  /// colon (the word or the number goes on), no decimal fraction, no percent
  /// or currency sign or word with or without a space before it (the number
  /// is an amount: "20%", "৫০০ টাকা"), no dash before a digit (a range written
  /// with a dash and no টা is English's), and no AM or PM after it.
  static let bengaliTimeEnd =
    #"(?![\p{Bengali}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*(?:টাকা|রুপি|রুপী|ডলার|পয়সা)\#(bengaliEnd)|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Bengali letter, vowel sign, digit, or colon, no
  /// decimal fraction, and no hyphen that joins a Bengali word to it ("মে-র").
  static let bengaliDateEnd = #"(?![\p{Bengali}\p{M}\p{N}\x{200C}\x{200D}:]|[.,]\p{N}|-\p{Bengali})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let bengaliNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The word just before `match` as a reader compares it, or nil when the
  /// match opens the line or punctuation comes first.
  static func bengaliWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(bengaliBare), !word.isEmpty else { return nil }
    return word
  }

  /// The words of `text`, as letters only and as ``bengaliBare(_:)`` leaves
  /// them.
  static func bengaliWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { bengaliBare(String($0)) }
  }

  // MARK: - Counts

  /// The numerals one to twelve that stand before the classifier of an hour
  /// (টা, টে, টো): the stem of "পাঁচটা", "দুটো", "ছটা", "নটা", and "বারোটা", in
  /// the spellings people type.
  private static let bengaliHourStemSpellings: [(Int, [String])] = [
    (1, ["এক"]), (2, ["দুই", "দু"]), (3, ["তিন"]), (4, ["চার"]), (5, ["পাঁচ"]), (6, ["ছয়", "ছ"]), (7, ["সাত"]),
    (8, ["আট"]), (9, ["নয়", "ন"]), (10, ["দশ"]), (11, ["এগারো", "এগার"]), (12, ["বারো", "বার"]),
  ]

  /// The hour stems as keys.
  static let bengaliHourStems: [String: Int] = {
    var stems: [String: Int] = [:]
    for (value, words) in bengaliHourStemSpellings {
      for word in words { stems[bengaliKey(word)] = value }
    }
    return stems
  }()

  /// The hour stems as a pattern.
  static var bengaliHourStemWords: String {
    alternation(of: bengaliHourStemSpellings.flatMap { $0.1 })
  }

  /// The numerals of an amount of hours, days, or weeks that stand apart from
  /// their noun ("তিন ঘণ্টা", "দু সপ্তাহ", "এক ঘণ্টা"): one to twelve, written
  /// out in full.
  private static let bengaliCountSpellings: [(Int, [String])] = [
    (1, ["এক"]), (2, ["দুই", "দু"]), (3, ["তিন"]), (4, ["চার"]), (5, ["পাঁচ"]), (6, ["ছয়"]), (7, ["সাত"]),
    (8, ["আট"]), (9, ["নয়"]), (10, ["দশ"]), (11, ["এগারো", "এগার"]), (12, ["বারো"]),
  ]

  /// The round numbers of an amount of minutes: fifteen to sixty.
  private static let bengaliRoundSpellings: [(Int, [String])] = [
    (15, ["পনেরো", "পনের"]), (20, ["বিশ"]), (25, ["পঁচিশ"]), (30, ["ত্রিশ", "তিরিশ"]), (40, ["চল্লিশ"]),
    (45, ["পঁয়তাল্লিশ"]), (50, ["পঞ্চাশ"]), (60, ["ষাট"]),
  ]

  /// The numerals of an amount, as keys.
  static let bengaliCounts: [String: Int] = {
    var counts: [String: Int] = [:]
    for (value, words) in bengaliCountSpellings {
      for word in words { counts[bengaliKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount of minutes or days: the counts above and the
  /// round numbers up to sixty, as keys.
  static let bengaliRoundCounts: [String: Int] = {
    var counts = bengaliCounts
    for (value, words) in bengaliRoundSpellings {
      for word in words { counts[bengaliKey(word)] = value }
    }
    return counts
  }()

  /// The numerals of an amount, as a pattern.
  static var bengaliCountWords: String {
    alternation(of: bengaliCountSpellings.flatMap { $0.1 })
  }

  /// The numerals of an amount of minutes or days, as a pattern.
  static var bengaliRoundCountWords: String {
    alternation(of: (bengaliCountSpellings + bengaliRoundSpellings).flatMap { $0.1 })
  }

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "প্রাধান্য" or "অগ্রাধিকার"; an urgent word has no group. A level word with
  /// "সম্পন্ন" or "যুক্ত" after the priority describes a noun ("উচ্চ প্রাধান্য
  /// সম্পন্ন কাজ") and is no priority.
  private static var bengaliPriorityPattern: String {
    let level =
      #"সর্বোচ্চ|সর্বনিম্ন|সবচেয়ে\s+(?:বেশি|কম)|উচ্চ|মধ্যম|মাঝার[িী]|সাধারণ|স্বাভাবিক|নিম্ন|বেশি|কম"#
    let word = "প্রাধান্য|অগ্রাধিকার"
    let urgent =
      #"(?:(?:অতি|খুব|অত্যন্ত)\s+)?(?:জরুর[িী]|আর্জেন্ট|গুরুত্বপূর্ণ)(?:\s+ভিত্তিতে)?"#
    let described = #"(?!\s+(?:সম্পন্ন|যুক্ত)\#(bengaliEnd))"#
    return
      #"\#(bengaliStart)((?:\#(level))\s*(?:\#(word))|(?:\#(word))\s*[:：]?\s*(?:\#(level)))\#(bengaliEnd)\#(described)|(?<=\s)(?:\#(urgent))\#(bengaliEnd)(?=\s*[।.!]?\s*$)|^\s*(?:\#(urgent))\#(bengaliEnd)(?=\s*[:：,，])"#
  }

  private static func bengaliPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(bengaliPhrase) else { return .p1 }
    let words = Set(bengaliWords(in: phrase))
    if !words.isDisjoint(with: ["মধ্যম", "মাঝারি", "সাধারণ", "স্বাভাবিক"].map(bengaliKey)) { return .p2 }
    if !words.isDisjoint(with: ["নিম্ন", "সর্বনিম্ন", "কম"].map(bengaliKey)) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "৩০ মিনিট", "২ ঘণ্টা", "১.৫ ঘণ্টা", "১ ঘণ্টা ৩০ মিনিট", "আধ ঘণ্টা", "দেড়
  /// ঘণ্টা", "আড়াই ঘণ্টা", "সোয়া ঘণ্টা", "পৌনে এক ঘণ্টা", "সাড়ে তিন ঘণ্টা",
  /// "দুই ঘণ্টা", "বিশ মিনিট", "ঘণ্টাখানেক", each maybe after "প্রায়",
  /// "আনুমানিক", or "মোটামুটি", and maybe with a genitive, "জন্য", or "ধরে" after the
  /// unit, which goes with it ("৩০ মিনিটের মিটিং" is a meeting of 30 minutes, "২
  /// ঘণ্টার জন্য" is for 2 hours). Groups: 1 a word that makes the length
  /// approximate; 2 a word that makes the amount a bound or a rate ("অন্তত ২
  /// ঘণ্টা", "প্রতি ২ ঘণ্টা", "দিনে ২ ঘণ্টা"); 3 the hours of an amount with a unit
  /// and 4 its minutes; 5 minutes; 6 a length in words; 7 a word after the
  /// amount that makes it a moment, the past, or a bound ("২ ঘণ্টা পর", "২
  /// ঘণ্টার মধ্যে"). A match with group 2 or 7 is no length:
  /// ``bengaliLength(_:)`` declines it and a keep rule claims it, so the amount
  /// stays whole in the title. Any other ending glued to the unit ("২ ঘণ্টায়",
  /// "৩০ মিনিটে") leaves the unit unread. The amount may not follow a digit, a
  /// colon, a slash, or a separator ("১/২ ঘণ্টা" is a fraction, not 2 hours),
  /// and it may not be a side of a range ("২-৩ ঘণ্টা", "২ থেকে ৩ ঘণ্টা", "৫ মিনিট
  /// থেকে ১০ মিনিট").
  static var bengaliLengthPattern: String {
    let hourNoun = #"ঘ[ণন]্টা"#
    let minuteNoun = #"মিনিট"#
    let opener =
      #"(?:(?:(প্রায়|আনুমানিক|মোটামুটি)|(অন্তত|কমপক্ষে|কম\s+পক্ষে|বড়জোর|সর্বোচ্চ|সর্বাধিক|প্রতি|দিনে|সপ্তাহে|মাসে))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,/])(?<!\p{N}\s?[-–—]\s?)"#
    let hours =
      #"(\d+(?:\.\d+)?)\s*\#(hourNoun)(?:\s+(?:(?:এবং|ও)\s+)?(\d{1,2})\s*\#(minuteNoun))?"#
    let minutes = #"(\d+)\s*\#(minuteNoun)"#
    let fractionCount = #"(?:\d{1,2}|\#(bengaliCountWords))"#
    let words =
      #"((?:আধা?|দেড়|আড়াই)\s*\#(hourNoun)|(?:সোয়া|সওয়া|পৌনে)\s*(?:\#(fractionCount)\s+)?\#(hourNoun)|সাড়ে\s*\#(fractionCount)\s*\#(hourNoun)|(?:\#(bengaliCountWords))\s*\#(hourNoun)|(?:\#(bengaliRoundCountWords))\s*\#(minuteNoun)|ঘ[ণন]্টাখানেক)"#
    let ending = #"(?:(?:·ের|·র)?\s+(?:জন্য|ধরে)\#(bengaliEnd)|·ের|·র)?"#
    let trailing =
      #"(?:\s+(পর|পরে|আগে|বাদে|অন্তর|মধ্যে|ভেতরে|ভিতরে)\#(bengaliEnd))?"#
    return
      #"\#(bengaliStart)\#(opener)(?:\#(boundaries)(?:\#(hours)|\#(minutes))|\#(words))\#(ending)\#(bengaliEnd)(?!\s*[-–—]\s*\d|\s+(?:থেকে|হতে)\s+\d)\#(trailing)"#
  }

  /// True for a match that is no length: a bound or a rate ("অন্তত ২ ঘণ্টা",
  /// "দিনে ২ ঘণ্টা"), a moment, the past, or a bound ("২ ঘণ্টা পর", "২ ঘণ্টার
  /// মধ্যে"), or the end of a range of amounts ("২ থেকে ৩ ঘণ্টা").
  static func bengaliDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil || bengaliIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number or a unit and "থেকে" or
  /// "হতে", which makes the amount the end of a range ("২ থেকে ৩ ঘণ্টা", "৫ মিনিট
  /// থেকে ১০ মিনিট").
  private static func bengaliIsRangeEnd(_ match: Match) -> Bool {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return false }
    let before = String(match.source[..<start])
    return bengaliFinds(#"(?:\d|মিনিট|ঘ[ণন]্টা)\s+(?:থেকে|হতে)\s+$"#, in: before)
  }

  private static func bengaliLength(_ match: Match) -> Int? {
    if bengaliDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    guard let phrase = match.group(6).map(bengaliPhrase) else { return nil }
    return bengaliWordsLength(phrase)
  }

  /// The minutes a length written in words names: the phrase is as
  /// ``bengaliPhrase(_:)`` leaves it, an amount word or a fraction word with
  /// its count before a unit.
  private static func bengaliWordsLength(_ phrase: String) -> Int? {
    func ends(with suffix: String) -> Bool {
      phrase.unicodeScalars.reversed().starts(with: bengaliKey(suffix).unicodeScalars.reversed())
    }
    if ends(with: "খানেক") { return 60 }
    let amount = phrase.replacingOccurrences(of: #"\s*(?:ঘণ্টা|ঘন্টা|মিনিট)$"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: " ", with: "")
    if ends(with: "মিনিট") { return bengaliRoundCounts[amount].flatMap { taskLength(minutes: $0) } }
    switch amount {
    case bengaliKey("আধ"), bengaliKey("আধা"): return 30
    case bengaliKey("দেড়"): return 90
    case bengaliKey("আড়াই"): return 150
    case bengaliKey("সোয়া"), bengaliKey("সওয়া"): return 75
    case bengaliKey("পৌনে"): return 45
    default: break
    }
    if let (fraction, count) = bengaliFraction(of: amount) {
      switch fraction {
      case bengaliKey("সাড়ে"): return taskLength(minutes: count * 60 + 30)
      case bengaliKey("পৌনে"): return taskLength(minutes: count * 60 - 15)
      default: return taskLength(minutes: count * 60 + 15)
      }
    }
    return bengaliCounts[amount].flatMap { taskLength(minutes: $0 * 60) }
  }

  /// The fraction word and the hour count of an amount such as "সাড়েতিন" or
  /// "সোয়াদুই" (one word, as ``bengaliKey(_:)`` leaves it), or nil when `text`
  /// is no fraction word followed by a count of 1 to 12.
  static func bengaliFraction(of text: String) -> (fraction: String, count: Int)? {
    for fraction in ["সাড়ে", "সোয়া", "সওয়া", "পৌনে"].map(bengaliKey) where bengaliHasPrefix(text, fraction) {
      let rest = String(text.unicodeScalars.dropFirst(fraction.unicodeScalars.count))
      guard let count = number(rest) ?? bengaliCounts[rest], (1...12).contains(count) else { return nil }
      return (fraction, count)
    }
    return nil
  }
}
