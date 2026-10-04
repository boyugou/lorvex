import Foundation

extension LorvexCaptureVocabulary {
  /// Hebrew, read for a user who reads Hebrew (he-IL and any other region). A word
  /// needs a boundary on both sides: no Hebrew letter, niqqud or cantillation mark,
  /// or digit beside it, and no letter joined to it by a geresh or a gershayim, so
  /// "מחרתיים" holds no "מחר" and "ג׳ינס" names no weekday. Hebrew attaches the
  /// one-letter prepositions and the article to the word they go with ("בשבוע",
  /// "למחר", "השבוע", "בבוקר"): each pattern spells the prefixes it accepts, and a
  /// word with another prefix ("ומחר", "שמחר") is left unread.
  ///
  /// The line is read in one form (``hebrewForMatching(_:)``): the final letters
  /// (ך ם ן ף ץ) as the regular ones (כ מ נ פ צ), the maqaf and the other hyphens as
  /// the hyphen ("ב־17:30" is "ב-17:30"), every apostrophe-like mark as the geresh
  /// and every double-quote-like mark as the gershayim, so "אחה"צ", "אחה”צ", and
  /// "אחה״צ" are one word and "ג'" and "ג׳" one letter. A word may carry niqqud
  /// on any letter, and the title keeps what was typed. A word with two common
  /// spellings is read in both ("שתיים" and "שתים", "צהריים" and "צהרים", "מרץ"
  /// and "מרס"). Hebrew written in Latin letters and Hebrew numerals ("י״ב") are
  /// not read.
  ///
  /// English is read beside Hebrew, so a detail that needs no Hebrew word is left
  /// to it: "3pm", "17:30", "30 min", "for 2h", "!!", and "p1" read as they do in
  /// any line. Hebrew does not write a clock time with the letter h, so "2h"
  /// beside Hebrew stays a length.
  ///
  /// Weeks start on Monday, as the app's weeks do in every language, and the
  /// weekend is Saturday and Sunday. Israel's week runs from Sunday and its
  /// weekend is Friday and Saturday, so a weekday after "הבא" or "בשבוע הבא" is
  /// counted from the Monday that begins the coming week, and "סוף השבוע" on a
  /// Friday is tomorrow, the Saturday, not today. A weekday alone is the coming
  /// one, a full week ahead when it names today; "הזה", "השבוע", and "בשבוע
  /// הזה" make it this week's, "הבא" and "הקרוב" the coming one (a full week
  /// ahead when it names today), and "בשבוע הבא" next week's.
  ///
  /// The weekday names are ראשון, שני, שלישי, רביעי, חמישי, שישי, and שבת, with "יום"
  /// before them or a ב attached to them ("ביום שני", "בשלישי"), or the letters
  /// א׳ to ו׳ and ש׳ after "יום" ("יום ג׳"). They are ordinary words too (שני is
  /// "second" and "two"), so a name with no "יום" names a day only with an
  /// attached ב, "בשני" only at the end of the line or before a part of the day, a
  /// time, or "הבא", and no name is a day before a month or "החודש" ("בראשון
  /// לחודש", "בראשון במאי"). A name after "עד" alone is a deadline's day, except
  /// שני ("עד שני" may be "until the second"). A weekday in a list of weekdays
  /// with no "כל" ("ביום שני וחמישי") is left unread: one planned day cannot
  /// carry the list, and the others would stay in the title.
  ///
  /// No day is read that is in the past: אתמול, שלשום, and אמש are no day words,
  /// and a line in the past tense (a form of "היה": היה, הייתה, היו, הייתי, היינו)
  /// or one that says אתמול, שלשום, or אמש ("היום הייתה פגישה") holds no day to
  /// plan, apart from tomorrow, the day after, and "בעוד" with a count, which
  /// are always ahead. A weekday followed by שעבר, הקודם, האחרון, or שחלף is the
  /// past one ("ביום שני שעבר"). A day phrase that a possessive, "every", a bound,
  /// or a construct noun ending in ת comes before is an attribute of a noun and
  /// names no plan: "הדוח של מחר", "כל יום שני", "עד מחר" (a deadline, read by the
  /// due rule), "ארוחת הערב", "חדשות הערב".
  ///
  /// - Day: היום, מחר, מחרתיים, הערב, הלילה, הבוקר, each maybe with "ל" ("למחר") and
  ///   with a part of the day (בבוקר, בצהריים, "אחר הצהריים" or אחה״צ, בערב, בלילה, "לפנות
  ///   בוקר": "מחר בבוקר", "היום אחר הצהריים"); "בעוד 3 ימים", "בעוד שלושה שבועות",
  ///   "בעוד יומיים", "בעוד שבוע", "בעוד חודש" (months counted on the calendar);
  ///   the weekday names above, maybe with a part of the day, after "בשבוע הבא"
  ///   (next week's, weeks starting on Monday) or "השבוע" and before "הבא", "הקרוב",
  ///   or "הזה": "ביום שני", "ביום שני הבא", "בשבוע הבא ביום רביעי"; "בשבוע
  ///   הבא", "לשבוע הבא", "השבוע הבא" (seven days ahead); the weekend ("סוף
  ///   השבוע", "סוף שבוע", "סופ״ש", each maybe with ב or ל and with "הבא",
  ///   "הקרוב", or "הזה") as the coming Saturday, today on a Saturday or a Sunday,
  ///   and after "הבא" the Saturday a week later; a date ("5 במרץ", "ב-5 במרץ",
  ///   "ה-5 במרץ 2027", "בתאריך 5 במרץ", "ביום שני, 5 באוקטובר"). A date needs its
  ///   day number before a Gregorian month name (ינואר, פברואר, מרץ or מרס, אפריל,
  ///   מאי, יוני, יולי, אוגוסט, ספטמבר, אוקטובר, נובמבר, דצמבר, each maybe with ב); a
  ///   month alone, a date written in digits ("5.3", "5/3"), a date the calendar
  ///   lacks ("31 באפריל"), and the months of the Hebrew calendar (תשרי, חשוון,
  ///   ניסן) stay in the title: the Hebrew calendar is not read. "היום" before "ה"
  ///   and an adjective ("היום הראשון") is "the day", not today, and "סוף היום" and
  ///   "עד היום" ("so far") name no day to plan.
  /// - Date range: "מ-3 עד 5 במרץ", "מה-3 ועד ה-5 במרץ", "מ-3 במרץ עד 5 במרץ", "בין
  ///   3 ל-5 במרץ", "בין 3 ו-5 במרץ", "3-5 במרץ", each maybe with a year after the
  ///   end. The first day is the planned day and the last the due day, so another
  ///   day phrase stays in the title. A day written without its month takes the
  ///   month of the end, the end must be after the start ("מ-5 עד 3 במרץ" stays in
  ///   the title whole), and the end names a month, so "3 עד 5" is never a range
  ///   of days. Two days joined by "ו-" with no "בין" ("ב-3 ו-5 במרץ") are two days,
  ///   not a range, and stay whole. A day alone opens a range joined by a dash only
  ///   when the dash touches both sides: "ספרינט 12 - 20 במרץ" names a sprint and a
  ///   date. A range in the past tense stays in the title whole. A span of
  ///   weekdays ("מיום שני עד יום רביעי", "משני עד רביעי", "בין יום שני ליום
  ///   רביעי", "מיום ב׳ עד ד׳") plans the coming first day and is due on the first
  ///   last day after it. Sunday to Thursday, Sunday to Friday, Monday to Friday,
  ///   and Monday to Saturday with no "כל" stay whole, since each is a week of
  ///   work as often as it is a span of days (Israel's working week is Sunday to
  ///   Thursday, the app's Monday to Friday); so does a span from a day to itself.
  /// - Repeat: "כל יום", "כל שבוע", "כל חודש", "כל שנה", "מדי יום", "מדי שבוע" (each
  ///   also with "בכל"), and "כל" with a part of the day ("כל בוקר", "כל ערב", "כל
  ///   לילה", "כל אחר הצהריים", "כל יום בבוקר"), which keeps its part for an hour
  ///   beside it ("כל בוקר בשעה 6" is every day at 06:00); "כל יום שני", "כל שני
  ///   וחמישי", "בכל יום ראשון", "כל שבוע ביום שני", "בימי שני וחמישי", "כל ב׳ וד׳";
  ///   a span of weekdays after "כל" or "בימי" ("כל יום ראשון עד חמישי", "בימים
  ///   א׳-ה׳"), which holds the days it names; "כל סוף שבוע" and "כל סופ״ש" as
  ///   Saturday and Sunday; "כל יומיים", "כל שבועיים", "כל חודשיים", "כל שנתיים", "כל
  ///   3 ימים", "כל שלושה שבועות", "כל שני ימים", "יום כן יום לא", "שבוע כן שבוע
  ///   לא"; "אחת לשבוע", "אחת לחודשיים", "אחת ל-3 ימים", "פעם בשבוע", "פעם ב-3
  ///   חודשים"; "כל חודש ב-5", "ב-1 לכל חודש", "בכל 15 לחודש"; and "על בסיס יומי",
  ///   "על בסיס שבועי", "על בסיס חודשי", "על בסיס שנתי". An interval shorter than a
  ///   day ("כל שעתיים") is no repeat, nor is "כל הבוקר" (all morning), "כל ערב
  ///   חג" (a holiday's eve), "כל יום ראשון בחודש" (one Sunday of the month), "פעם
  ///   ביום ראשון", or "כל יום הולדת" ("יום" in a compound is no unit). The
  ///   adjectives יומי, שבועי, חודשי, and שנתי are not read ("דוח
  ///   שבועי"): they follow their noun as a title's own words do. The phrases
  ///   "כל יום עבודה", "בימי עבודה", and "ימי חול" stay whole, because the working
  ///   week is Sunday to Thursday in Israel and Monday to Friday in the app's
  ///   repeat.
  /// - Due: a day after "עד" ("עד יום שישי", "עד מחר", "עד ה-5 במרץ", "עד סוף היום",
  ///   "עד השבוע הבא"), after "לפני" or "לא יאוחר מ" (a weekday or a date only), or
  ///   after a label ("מועד אחרון: יום חמישי", "תאריך יעד: 5 במרץ", "דדליין
  ///   מחר"), maybe with a part of the day. A day before a clock deadline ("עד
  ///   יום שישי בשעה 17:00") is the due day and the clock stays in the title. "עד
  ///   היום" ("so far"), "עד הבוקר", and "עד סוף השבוע" (the end of the working
  ///   week as often as the weekend) are not read, and neither is "לפני שבת",
  ///   which means before the Sabbath begins on Friday ("לפני יום שבת" is read).
  /// - Time: "בשעה 5", "בשעה 17:30", "ב-17:30", "ב-9 בבוקר", "בחמש אחר הצהריים",
  ///   "בשלוש וחצי" (3:30), "בשעה 3 ורבע" (3:15), "ברבע לשש" (5:45), "בשעה 4 פחות
  ///   רבע" (3:45), each with the number as digits or as a word from אחת to שתים
  ///   עשרה (the feminine forms, since "שעה" is feminine), and "בשעה 5.30". The
  ///   number needs more than "ב-" to be a time (a colon, a fraction word, "רבע
  ///   ל", a part of the day, am or pm), since "ב-5 ימים" counts things; after
  ///   "שעה" it is enough, and a number written in words needs a fraction word,
  ///   "רבע ל", or a part of the day. A part of the day sets the hour: בבוקר
  ///   and "לפנות בוקר" are the morning (12 is no time), בצהריים and "אחר הצהריים"
  ///   are noon at 12 and the afternoon from 1 to 6, בערב is the evening, and
  ///   בלילה runs past midnight: "בשעה 12 בלילה" is 00:00 of the next day, "בשעה 2
  ///   בלילה" is 02:00 of the next day, and "בשעה 8 בלילה" is 20:00. After "שעה" the
  ///   hour may take minutes: "בשעה 3 ו-10 דקות", "בשעה שלוש ועשרים דקות". "בחצות" is the
  ///   midnight that ends the day. An hour on the 12-hour clock (1 to 12, no
  ///   leading zero) written with no part of the day beside it takes its half of
  ///   the day from the one part of the day the line names elsewhere: in its
  ///   day phrase ("מחר בבוקר פגישה בשעה 6" is 06:00), after "כל" ("כל בוקר בשעה 6"),
  ///   or in a noun ("ארוחת ערב בשעה 8" is 20:00). Two parts that differ leave the
  ///   hour as it reads alone; an hour on the 24-hour clock (a leading zero, 0,
  ///   or 13 and later) is read as written. An hour from 1 to 6 with no part of
  ///   the day anywhere in the line is the afternoon, as in the other languages
  ///   ("בשעה 5" is 17:00, "בשעה 7" is 07:00), unless written with a leading zero
  ///   ("בשעה 06:30"). A range: "מ-9 עד 11 בבוקר", "בין 2 ל-4 אחר הצהריים", "בין
  ///   השעות 14:00 ל-16:00", "משעה 9 עד 11", "בשעה 17:30 עד 18:30", "18:00-19:30",
  ///   "מ-9 בבוקר עד 5 אחר הצהריים"; two bare numbers are a range only with a
  ///   word for hours ("משעה", "בשעות"), a colon, or a part of the day, so "מ-14
  ///   עד 16 עמודים" is a title. A clock time that is a bound stays whole in the
  ///   title: "עד 17:00", "לפני 18:00", "אחרי 18:00", "עד השעה 5", "עד 5 בערב", "לא
  ///   יאוחר מ-17:00". A number before a percent sign, a currency sign, or a
  ///   currency word or a unit is never a time ("ב-5 וחצי ק״מ", "בשלוש וחצי
  ///   שעות" count things).
  /// - Length: "30 דקות", "2 שעות", "1.5 שעות", "3 שעות ו-20 דקות", "שעה ו-30 דקות",
  ///   "שעה ועשרים דקות", "חצי שעה", "רבע שעה", "שלושת רבעי שעה", "שעה וחצי",
  ///   "שעתיים", "שעתיים וחצי", "שלוש שעות", "עשרים דקות", "שעה אחת", "30 דק׳", "3
  ///   שע׳", each maybe after "בערך", "כ-", "למשך", "במשך", "ל-", "של", "בן", or "בת" ("ריצה
  ///   של 30 דקות", "סרט בן שעתיים") and before "בערך" or "של". "שעה" and "דקה"
  ///   alone are lengths only after one of those words ("בערך שעה", "למשך
  ///   שעה"). An amount after "בעוד", "עוד", "תוך", "כל", "עד", "לפני", "אחרי",
  ///   "בתוך", "מ-" (as in "פחות מ-30 דקות"), "לפחות", or "ב-", or before "לפני",
  ///   "אחרי", "ביום", "בשבוע", "בחודש", or "מאז", names a moment, an interval,
  ///   a bound, or a rate, not a length ("בעוד 30 דקות", "30 דקות ביום", "30
  ///   דקות לפני הפגישה"), and neither is a side of a range ("2-3 שעות", "בין 2
  ///   ל-3 שעות"): each stays whole in the title. An amount before "כל יום" is
  ///   a length and the cadence a repeat ("ריצה 30 דקות כל יום").
  /// - Priority: "עדיפות גבוהה", "עדיפות בינונית" (also רגילה), "עדיפות נמוכה",
  ///   each also with "ב" before "עדיפות", after a colon, and with "מאוד"; and
  ///   "בדחיפות", דחוף, דחופה, בהול, maybe followed by "מאוד" or "ביותר", at the
  ///   end of the line, and the same words opening it before a colon or comma
  ///   ("דחוף: להגיש דוח"). דחוף is an ordinary adjective too, so it stays in the
  ///   title anywhere else ("דחוף לקנות חלב", "להגיש דוח דחוף היום").
  static let hebrew = LorvexCaptureVocabulary(
    readingForm: hebrewForMatching,
    priority: [hebrewRule(hebrewPriorityPattern, read: hebrewPriority)],
    dateRange: [
      hebrewRule(hebrewDateRangePattern, read: hebrewDateRange),
      hebrewRule(hebrewWeekdayRangePattern, read: hebrewWeekdayRange),
    ],
    keptInTitle: [
      hebrewRule(hebrewDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      hebrewRule(hebrewDueClockPattern) { hebrewIsClockAfterDueDay($0) ? true : nil },
      hebrewRule(hebrewLengthPattern) { hebrewDeclinesLength($0) ? true : nil },
      hebrewRule(hebrewWorkdaysPattern) { _ in true },
    ],
    length: [hebrewRule(hebrewLengthPattern, read: hebrewLength)],
    time: [
      hebrewRule(hebrewTimeRangePattern, read: hebrewTimeRange),
      hebrewRule(hebrewTimePattern, read: hebrewTime),
      hebrewRule(hebrewMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
    ],
    repeats: hebrewRepeatRules,
    due: [hebrewRule(hebrewDuePattern, read: hebrewDue)],
    when: [hebrewRule(hebrewWhenPattern, read: hebrewWhen)])

  // MARK: - Reading form and patterns

  /// The line with each letter and punctuation mark read in one form: the
  /// final letters (ך ם ן ף ץ) as the regular ones (כ מ נ פ צ), the maqaf and the
  /// other hyphens and dashes as the hyphen, every apostrophe-like mark (' ’ ‘ ʼ
  /// ` ´) as the geresh (׳), and every double-quote-like mark (" “ ” ″) as the
  /// gershayim (״), so "אחה"צ", "אחה”צ", and "אחה״צ" read the same, "ב־5" and
  /// "ב–5" read as "ב-5", and a pattern, written in its natural spelling, is
  /// read through the same form by ``hebrew(_:readsMarks:)``. Niqqud and
  /// cantillation marks stay as typed and are skipped by the patterns. Each
  /// replacement is one UTF-16 unit for one, so a match range in the result is
  /// the same range in `line`.
  static func hebrewForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(hebrewReading(of: scalar)) }
    return String(scalars)
  }

  /// `scalar` as the reading form has it. A character set of a pattern keeps its
  /// dashes (`foldsDashes` false): the set `[-–—]` read as `[---]` would name one
  /// character.
  private static func hebrewReading(of scalar: Unicode.Scalar, foldsDashes: Bool = true) -> Unicode.Scalar {
    switch scalar {
    case "\u{05DA}": "\u{05DB}"
    case "\u{05DD}": "\u{05DE}"
    case "\u{05DF}": "\u{05E0}"
    case "\u{05E3}": "\u{05E4}"
    case "\u{05E5}": "\u{05E6}"
    case "\u{05BE}", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}":
      foldsDashes ? "-" : scalar
    case "'", "\u{2018}", "\u{2019}", "\u{02BC}", "`", "\u{00B4}": "\u{05F3}"
    case "\"", "\u{201C}", "\u{201D}", "\u{2033}": "\u{05F4}"
    default: scalar
    }
  }

  /// Whether `scalar` is a niqqud, a cantillation mark, or another combining
  /// mark, which a typed word may carry without changing it.
  private static func isHebrewMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: return true
    default: return false
    }
  }

  /// Whether `scalar` is a letter of the Hebrew alphabet (א to ת).
  private static func isHebrewLetter(_ scalar: Unicode.Scalar) -> Bool {
    (0x05D0...0x05EA).contains(scalar.value)
  }

  /// Whether `scalar` is a bidirectional control character, which a pasted
  /// line may carry beside a number or a Latin word and which counts as a space.
  private static func isHebrewBidiControl(_ scalar: Unicode.Scalar) -> Bool {
    [0x200E, 0x200F, 0x061C, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
      .contains(scalar.value)
  }

  /// `text` without its niqqud and cantillation marks, for the letters of a
  /// matched word as a reader compares them. `text` is already in the reading
  /// form.
  static func hebrewBare(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isHebrewMark(scalar) { scalars.append(scalar) }
    return String(scalars)
  }

  /// A matched phrase as a reader compares it: without niqqud, each bidirectional
  /// control character, hyphen, and run of spaces as one space.
  static func hebrewPhrase(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isHebrewMark(scalar) {
      scalars.append(isHebrewBidiControl(scalar) ? " " : scalar)
    }
    return normalizedPhrase(String(scalars))
  }

  /// A matched word or phrase as one run of letters: spaces, geresh, and
  /// gershayim left out, so "אחה״צ" and "אחר הצהריים" compare as plain letters.
  static func hebrewKey(_ text: String) -> String {
    hebrewPhrase(text).filter { $0 != " " && $0 != "\u{05F3}" && $0 != "\u{05F4}" }
  }

  /// A word written in a vocabulary table, as ``hebrewKey(_:)`` leaves a
  /// matched word.
  static func hebrewTableKey(_ word: String) -> String {
    hebrewKey(hebrewForMatching(word))
  }

  /// A phrase written in a vocabulary table, as ``hebrewPhrase(_:)`` leaves a
  /// matched phrase.
  static func hebrewTablePhrase(_ phrase: String) -> String {
    hebrewPhrase(hebrewForMatching(phrase))
  }

  /// The words of `text`, as letters only and without niqqud.
  static func hebrewWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { hebrewBare(String($0)) }
  }

  /// The pattern text for one space between two words, which a pasted line may
  /// carry as a bidirectional control character beside the space.
  private static let hebrewSpace = #"[\s\x{200E}\x{200F}]"#

  /// `pattern`, written in the natural spelling of its words, ready to match a
  /// line in the reading form: each Hebrew letter, and each character set that
  /// holds one, is read through ``hebrewForMatching(_:)`` and, with
  /// `readsMarks`, may be followed by niqqud; a letter or a set that a
  /// quantifier follows keeps the quantifier on the letter or set with its
  /// marks. A look-behind reads no marks, so its length stays bounded. A `\s`
  /// outside a character set also matches a bidirectional control character.
  /// Other escapes pass through. A pattern is expanded once, by
  /// ``hebrewRule(_:read:)``, never in parts that another pattern then embeds.
  static func hebrew(_ pattern: String, readsMarks: Bool = true) -> String {
    let marks = #"[\p{M}]*"#
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let scalars = Array(pattern.unicodeScalars)
    var result = ""
    var isEscaped = false
    var isInSet = false
    var setEnding = ""
    // One entry per open group: whether it is, or is inside, a look-behind.
    var lookbehinds: [Bool] = []
    for (index, scalar) in scalars.enumerated() {
      let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
      let readsMarksHere = readsMarks && !(lookbehinds.last ?? false)
      if isEscaped {
        isEscaped = false
        if scalar == "s", !isInSet {
          result.unicodeScalars.removeLast()
          result += hebrewSpace
        } else {
          result.unicodeScalars.append(scalar)
        }
      } else if scalar == "\\" {
        result.unicodeScalars.append(scalar)
        isEscaped = true
      } else if isInSet {
        if scalar == "]" {
          isInSet = false
          result += "]" + setEnding
          setEnding = ""
        } else {
          result.unicodeScalars.append(hebrewReading(of: scalar, foldsDashes: false))
        }
      } else if scalar == "[" {
        isInSet = true
        let set = hebrewSet(in: scalars, from: index)
        if readsMarksHere, set.holdsLetter {
          if set.isQuantified { result += "(?:" }
          setEnding = marks + (set.isQuantified ? ")" : "")
        }
        result.unicodeScalars.append(scalar)
      } else if scalar == "(" {
        let opensLookbehind =
          index + 3 < scalars.count && scalars[index + 1] == "?" && scalars[index + 2] == "<"
          && (scalars[index + 3] == "=" || scalars[index + 3] == "!")
        lookbehinds.append((lookbehinds.last ?? false) || opensLookbehind)
        result.unicodeScalars.append(scalar)
      } else if scalar == ")" {
        _ = lookbehinds.popLast()
        result.unicodeScalars.append(scalar)
      } else {
        let reading = hebrewReading(of: scalar)
        guard isHebrewLetter(reading) else {
          result.unicodeScalars.append(reading)
          continue
        }
        let letter = readsMarksHere ? "\(Character(reading))\(marks)" : String(Character(reading))
        result += isQuantified && readsMarksHere ? "(?:\(letter))" : letter
      }
    }
    return result
  }

  /// The character set of a pattern that opens at `start` (the index of its
  /// "["): whether it holds a Hebrew letter and whether a quantifier follows its
  /// closing bracket.
  private static func hebrewSet(in scalars: [Unicode.Scalar], from start: Int) -> (holdsLetter: Bool, isQuantified: Bool)
  {
    var holdsLetter = false
    var isEscaped = false
    var end = start + 1
    while end < scalars.count {
      let scalar = scalars[end]
      if isEscaped {
        isEscaped = false
      } else if scalar == "\\" {
        isEscaped = true
      } else if scalar == "]" {
        break
      } else if isHebrewLetter(hebrewReading(of: scalar, foldsDashes: false)) {
        holdsLetter = true
      }
      end += 1
    }
    let isQuantified = end + 1 < scalars.count && ["?", "*", "+", "{"].contains(scalars[end + 1])
    return (holdsLetter, isQuantified)
  }

  /// A rule whose `pattern` is written in natural spelling (see
  /// ``hebrew(_:readsMarks:)``).
  static func hebrewRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: hebrew(pattern), read: read)
  }

  /// Whether `pattern`, written in natural spelling, matches somewhere in
  /// `text`, which is in the reading form without niqqud.
  static func hebrewFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(hebrew(pattern, readsMarks: false)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Boundaries and words around a detail

  /// The Hebrew letters (with the Yiddish ligatures and the presentation
  /// forms), as the inside of a character set.
  private static let hebrewLetterClass = #"\x{05D0}-\x{05EA}\x{05F0}-\x{05F2}\x{FB1D}-\x{FB4F}"#

  /// The characters that make a word go on: a Hebrew letter, a combining mark,
  /// or a digit.
  private static let hebrewWordCharacters = #"\#(hebrewLetterClass)\p{M}\p{N}"#

  /// A word boundary for words written in Hebrew letters: no letter, mark, or
  /// digit on that side, and no letter with a geresh or gershayim after it
  /// ("אחה״צ", "ג׳ינס"), so a word is never cut out of a longer one. A geresh or
  /// a gershayim that stands alone, as a quotation mark does, is no part of a
  /// word.
  static let hebrewStart = #"(?<![\#(hebrewWordCharacters)])(?<![\#(hebrewLetterClass)][׳״])"#
  static let hebrewEnd = #"(?![\#(hebrewWordCharacters)])(?![׳״][\#(hebrewLetterClass)])"#

  /// What may follow a clock time: no letter, mark, digit, or colon (the word or
  /// the number goes on), no decimal fraction, no percent or currency sign or
  /// word with or without a space before it, and no unit of time, measure, or
  /// count after a space (the number is an amount: "20%", "500 ש״ח", "ב-5 וחצי
  /// ק״מ", "בשלוש וחצי שעות", "ב-2 וחצי אלף שקל"), and no dash before a digit,
  /// which makes the time one side of a range written with a dash.
  static let hebrewTimeEnd =
    #"(?![\#(hebrewWordCharacters):]|[.,]\p{N}|\s*[%\p{Sc}]|\s*\#(hebrewCurrencyWords)\#(hebrewEnd)|\s+\#(hebrewUnitWords)\#(hebrewEnd)|\s*[-–—]\s*\d)"#

  /// The currency words that follow an amount, as a pattern without groups.
  private static let hebrewCurrencyWords = #"(?:שקל|שקלים|ש״?ח|דולר|דולרים|אירו|יורו|אחוז|אחוזים)"#

  /// The units of time, measure, and count that follow an amount, as a pattern
  /// without groups.
  private static let hebrewUnitWords =
    #"(?:שעות|דקות|ימים|שבועות|חודשים|שנים|פעמים|אנשים|עמודים|קילו|ק״ג|ק״מ|קילומטר|קילומטרים|מטר|מטרים|ליטר|גרם|אלף|אלפים|מיליון|מיליארד)"#

  /// What may follow a date: no letter, mark, digit, or colon, and no decimal
  /// fraction.
  static let hebrewDateEnd = #"(?![\#(hebrewWordCharacters):]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let hebrewNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The text before `match`, as a reader compares it: in the reading form
  /// without niqqud.
  static func hebrewTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    return hebrewBare(String(match.source[..<start]))
  }

  /// The text after `match`, as a reader compares it.
  static func hebrewTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return hebrewBare(String(match.source[end...]))
  }

  /// The word just before `match`, as ``hebrewKey(_:)`` leaves it, or nil when
  /// the match opens the line or punctuation comes first.
  static func hebrewWordBefore(_ match: Match) -> String? {
    var characters = Array(hebrewTextBefore(match))
    while let last = characters.last, last.isWhitespace || last.unicodeScalars.allSatisfy(isHebrewBidiControl) {
      characters.removeLast()
    }
    var word: [Character] = []
    while let last = characters.last, last.isLetter || last == "\u{05F3}" || last == "\u{05F4}" {
      word.append(last)
      characters.removeLast()
    }
    return word.isEmpty ? nil : hebrewKey(String(word.reversed()))
  }

  // MARK: - Counts

  /// The number words one to twelve as clock hours use them: the feminine forms,
  /// since "שעה" (hour) is feminine ("שלוש", "שתיים"). A word that holds two
  /// words ("אחת עשרה") is written with a space.
  private static let hebrewHourSpellings: [(value: Int, words: [String])] = [
    (1, ["אחת"]), (2, ["שתיים", "שתים"]), (3, ["שלוש"]), (4, ["ארבע"]), (5, ["חמש"]), (6, ["שש"]), (7, ["שבע"]),
    (8, ["שמונה"]), (9, ["תשע"]), (10, ["עשר"]), (11, ["אחת עשרה"]), (12, ["שתים עשרה", "שתיים עשרה"]),
  ]

  /// The masculine forms and the construct forms that stand before a counted
  /// noun besides the feminine ones ("שלושה ימים", "שני ימים", "שתי דקות").
  private static let hebrewMasculineSpellings: [(value: Int, words: [String])] = [
    (1, ["אחד"]), (2, ["שני", "שתי", "שניים"]), (3, ["שלושה"]), (4, ["ארבעה"]), (5, ["חמישה"]), (6, ["שישה"]),
    (7, ["שבעה"]), (9, ["תשעה"]), (10, ["עשרה"]), (11, ["אחד עשר"]), (12, ["שנים עשר", "שניים עשר"]),
  ]

  /// The round counts that name minutes besides the ones above.
  private static let hebrewRoundCountSpellings: [(value: Int, words: [String])] = [
    (15, ["חמש עשרה", "חמישה עשר"]), (20, ["עשרים"]), (25, ["עשרים וחמש", "עשרים וחמישה"]), (30, ["שלושים"]),
    (40, ["ארבעים"]), (45, ["ארבעים וחמש", "ארבעים וחמישה"]), (50, ["חמישים"]), (60, ["שישים"]),
  ]

  /// The hour words keyed as ``hebrewKey(_:)`` leaves them, the counts that
  /// stand before a counted noun, and those with the round counts.
  static let hebrewHours: [String: Int] = hebrewCountIndex(hebrewHourSpellings)
  static let hebrewCounts: [String: Int] = hebrewCountIndex(hebrewHourSpellings + hebrewMasculineSpellings)
  static let hebrewRoundCounts: [String: Int] = hebrewCountIndex(
    hebrewHourSpellings + hebrewMasculineSpellings + hebrewRoundCountSpellings)

  private static func hebrewCountIndex(_ spellings: [(value: Int, words: [String])]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for (value, words) in spellings {
      for word in words { counts[hebrewTableKey(word)] = value }
    }
    return counts
  }

  /// `words` as the alternatives of a pattern, longest first, with a space
  /// between the parts of a word as a space or a hyphen.
  private static func hebrewAlternation(of words: [String]) -> String {
    alternation(of: words).replacingOccurrences(of: " ", with: #"[\s-]+"#)
  }

  /// The clock hours in words, as a pattern. A word that another "עשרה" follows
  /// is a count above twelve ("חמש עשרה" is fifteen), which is no hour of the
  /// 12-hour clock and is not read.
  static var hebrewHourWords: String {
    #"(?:\#(hebrewAlternation(of: hebrewHourSpellings.flatMap { $0.words })))(?![\s-]+עשרה\#(hebrewEnd))"#
  }

  /// The counts one to twelve in words, as a pattern.
  static var hebrewCountWords: String {
    hebrewAlternation(of: (hebrewHourSpellings + hebrewMasculineSpellings).flatMap { $0.words })
  }

  /// The counts one to twelve and the round counts in words, as a pattern.
  static var hebrewRoundCountWords: String {
    hebrewAlternation(
      of: (hebrewHourSpellings + hebrewMasculineSpellings + hebrewRoundCountSpellings).flatMap { $0.words })
  }

  // MARK: - Priority

  /// Group 1: a written priority, with its level after the word "עדיפות" (with
  /// the ב attached or not, and maybe after a colon); an urgent word has no
  /// group.
  private static var hebrewPriorityPattern: String {
    let level = "גבוהה|גבוה|עליונה|קריטית|מקסימלית|דחופה|בינונית|בינוני|רגילה|רגיל|נורמלית|ממוצעת|נמוכה|נמוך|זניחה"
    let urgent = "(?:בדחיפות(?:\\s+גבוהה)?|דחופה|דחוף|בהולה|בהול)(?:\\s+(?:מאוד|ביותר))?"
    return
      #"\#(hebrewStart)(ב?עדיפות\s*[:：]?\s*(?:\#(level))(?:\s+מאוד)?)\#(hebrewEnd)|(?<=\s)(?:\#(urgent))\#(hebrewEnd)(?=\s*[.!]?\s*$)|^\s*(?:\#(urgent))\#(hebrewEnd)(?=\s*[:：,，])"#
  }

  private static func hebrewPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(hebrewPhrase) else { return .p1 }
    let words = Set(hebrewWords(in: phrase))
    if !words.isDisjoint(with: ["בינונית", "בינוני", "רגילה", "רגיל", "נורמלית", "ממוצעת"].map(hebrewTableKey)) {
      return .p2
    }
    if !words.isDisjoint(with: ["נמוכה", "נמוך", "זניחה"].map(hebrewTableKey)) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// The nouns for minutes, as a pattern without groups.
  static let hebrewMinuteNouns = "דקות|דקה|דק׳"

  /// A count of minutes after "ו" in "שעה ו-20 דקות" or "שלוש ועשרים דקות", as a
  /// pattern without groups: one or two digits, or a count in words.
  static var hebrewMinuteCount: String {
    #"(?:\d{1,2}|(?:\#(hebrewRoundCountWords)))"#
  }

  /// A length written with an amount: "30 דקות", "3 שעות", "3 שע׳", "1.5 שעות", "3 שעות
  /// ו-20 דקות", "שעה ו-30 דקות", "שעה ועשרים דקות", "חצי שעה", "רבע שעה", "שלושת
  /// רבעי שעה", "שעה וחצי", "שעתיים", "שעתיים וחצי", "שלוש שעות", "עשרים דקות",
  /// "שעה אחת", "30 דק׳", each maybe after "בערך", "כ-", "למשך", "במשך", "ל-",
  /// "של", "בן", or "בת" (which go with it: "ריצה של 30 דקות", "סרט בן שעתיים")
  /// and maybe before "בערך" or "של" ("30 דקות של ריצה"). "שעה" and "דקה" alone
  /// are lengths only after an approximation or a preposition ("בערך שעה",
  /// "למשך שעה"), and not when minutes or a fraction follow them, which make the
  /// length a longer one. Groups: 1 the opener of a bare "שעה" or "דקה" and 2
  /// that noun; 3 the opener of an amount; 4 a word that makes the amount a
  /// moment, an interval, a bound, or a comparison ("בעוד", "עוד", "תוך", "כל",
  /// "לפני", "עד", "מ-" as in "פחות מ-", "ב-"); 5 the hours of an amount with a
  /// unit and 6 its minutes; 7 minutes; 8 a length in words; 9 a word after the
  /// amount that makes it a moment, the past, or a rate ("30 דקות לפני", "30
  /// דקות ביום"). A match with group 4 or 9 is no length: ``hebrewLength(_:)``
  /// declines it and a keep rule claims it, so the amount stays whole in the
  /// title. An amount before "כל יום" or "בכל יום" is a length, and the repeat
  /// rules read the cadence ("ריצה 30 דקות כל יום"). The amount may not follow a
  /// digit, a colon, or a separator, minutes after "ו" are the minutes of a
  /// clock time or part of an hours amount ("בשעה 3 ו-10 דקות"), and the amount
  /// may not be a side of a range ("2-3 שעות", "בין 2 ל-3 שעות", "מ-2 עד 3
  /// שעות").
  static var hebrewLengthPattern: String {
    let hour = "שעות|שעה|שע׳"
    let minute = hebrewMinuteNouns
    let approximate = #"(?:(?:בערך|כמעט|בסביבות|בקירוב|למשך|במשך|של|בן|בת)\s+|[כל]-?)"#
    let decliner =
      #"(?:(?:בעוד|עוד|תוך|בתוך|כל|מדי|לפני|אחרי|מעל|עד|לפחות|לכל\s+היותר|מקסימום|מינימום)\s+|מ-?\s*|ב-?(?!שעה\s+אחת))"#
    let boundaries = #"(?<![\p{N}:.,])(?<!\p{N}\s?[-–—]\s?)"#
    let fraction = #"(?:\s+(?:וחצי|ורבע))"#
    let andMinutes = #"(?:\s+ו-?\#(hebrewMinuteCount)\s*(?:\#(minute)))"#
    let hours = #"(\d+(?:\.\d+)?)\s*(?:\#(hour))(?:\s+(?:ו-?)?(\d{1,2})\s*(?:\#(minute)))?"#
    let minutes = #"(?<![ו]-?)(\d+)\s*(?:\#(minute))"#
    let wholeHours = #"(?:שעה(?:\s+אחת)?|שעתיים|(?:\#(hebrewCountWords))\s+שעות)"#
    let words =
      #"(\#(wholeHours)\#(andMinutes)|חצי\s+שעה|רבע\s+שעה|שלוש(?:ת|ה)\s+רבעי\s+ה?שעה|שעה\s+(?:אחת\s+)?(?:וחצי|ורבע)|שעה\s+אחת|שעתיים\#(fraction)?|(?:\#(hebrewCountWords))\s+שעות\#(fraction)?|(?:\#(hebrewRoundCountWords))\s+(?:\#(minute)))"#
    let longer = #"(?!\s*\d|\s+ו-?\d|\#(andMinutes)|\s+ו-?(?:חצי|רבע)\#(hebrewEnd)|\s+אחת\#(hebrewEnd))"#
    let trailing =
      #"(?:\s+(לפני|אחרי|מאז|מהיום|מעכשיו|ביום|בשבוע|בחודש|ליום|לשבוע|לחודש)\#(hebrewEnd))?(?:\s+בערך\#(hebrewEnd))?(?:\s+של\#(hebrewEnd)(?=\s+\S))?"#
    return
      #"\#(hebrewStart)(?:(\#(approximate))(שעה|דקה)\#(hebrewEnd)\#(longer)|(\#(approximate))?(\#(decliner))?(?:\#(boundaries)(?:\#(hours)|\#(minutes))|\#(words))\#(hebrewEnd)(?!\s*[-–—]\s*\d|\s+(?:עד|ועד)\s+\d)\#(trailing))"#
  }

  /// True for a match that is no length: a moment, an interval, a bound, or a
  /// rate ("בעוד 30 דקות", "כל שעתיים", "עד 30 דקות", "30 דקות ביום"), the
  /// amount of a thing that happens before or after another ("30 דקות לפני"),
  /// or the end of a range of amounts ("בין 2 ל-3 שעות").
  static func hebrewDeclinesLength(_ match: Match) -> Bool {
    match.group(4) != nil || match.group(9) != nil || hebrewIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number or a unit and "עד", or
  /// with "בין" and a number, which makes the amount the end of a range ("מ-2
  /// עד 3 שעות", "בין 2 ל-3 שעות").
  private static func hebrewIsRangeEnd(_ match: Match) -> Bool {
    hebrewFinds(
      #"(?:(?:\d|שעות|שעה|דקות|דקה)\s+(?:עד|ועד)|בין\s+(?:\d+(?:\.\d+)?|\#(hebrewCountWords)))\s*$"#,
      in: hebrewTextBefore(match))
  }

  private static func hebrewLength(_ match: Match) -> Int? {
    if hebrewDeclinesLength(match) { return nil }
    if let noun = match.group(2) { return hebrewKey(noun) == hebrewTableKey("שעה") ? 60 : 1 }
    if let hours = match.group(5).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(6).flatMap(number) ?? 0))
    }
    if let minutes = match.group(7).flatMap(number) { return taskLength(minutes: minutes) }
    return match.group(8).map(hebrewPhrase).flatMap(hebrewWordLength)
  }

  /// The minutes a length written in words names: "חצי שעה", "רבע שעה", "שלושת
  /// רבעי שעה", "שעה", "שעה אחת", "שעה וחצי", "שעה ו-30 דקות", "שעה ועשרים
  /// דקות", "שעתיים", "שעתיים וחצי", "שלוש שעות", "שלוש שעות וחצי", "שלוש שעות
  /// ו-20 דקות", "עשרים דקות". `phrase` is a matched phrase as
  /// ``hebrewPhrase(_:)`` leaves it.
  private static func hebrewWordLength(_ phrase: String) -> Int? {
    var tokens = phrase.split(separator: " ").map { hebrewKey(String($0)) }
    let vav = hebrewTableKey("ו")
    let minuteNouns = Set(hebrewMinuteNouns.split(separator: "|").map { hebrewTableKey(String($0)) })
    // Hours and minutes: the hours come first, and the minutes begin with the
    // first word that carries the "ו" ("ועשרים", or "ו" before a hyphenated
    // number). A count such as "עשרים וחמש" has an inner "ו" too, so a phrase
    // whose part before that "ו" is no hours amount is read as the one count.
    if tokens.count >= 3, let last = tokens.last, minuteNouns.contains(last),
      let join = tokens.firstIndex(where: { $0.hasPrefix(vav) }), join > 0
    {
      var minuteTokens = Array(tokens[join..<(tokens.count - 1)])
      minuteTokens[0] = String(minuteTokens[0].dropFirst())
      let counted = minuteTokens.joined()
      if let minutes = number(counted) ?? hebrewRoundCounts[counted],
        let whole = hebrewWordLength(tokens[..<join].joined(separator: " "))
      {
        return taskLength(minutes: whole + minutes)
      }
    }
    var extra = 0
    if let last = tokens.last, last == hebrewTableKey("וחצי") || last == hebrewTableKey("ורבע") {
      extra = last == hebrewTableKey("וחצי") ? 30 : 15
      tokens.removeLast()
    }
    if tokens.count >= 2, tokens[tokens.count - 2] == hebrewTableKey("שעה"), tokens[tokens.count - 1] == hebrewTableKey("אחת") {
      tokens.removeLast()
    }
    guard let unit = tokens.last else { return nil }
    let counted = tokens.dropLast().joined()
    switch unit {
    case hebrewTableKey("שעה"):
      switch tokens.count {
      case 1: return taskLength(minutes: 60 + extra)
      case 2:
        switch tokens[0] {
        case hebrewTableKey("חצי"): return extra == 0 ? 30 : nil
        case hebrewTableKey("רבע"): return extra == 0 ? 15 : nil
        default: return nil
        }
      case 3:
        guard tokens[1] == hebrewTableKey("רבעי"), extra == 0,
          [hebrewTableKey("שלושת"), hebrewTableKey("שלושה")].contains(tokens[0])
        else { return nil }
        return 45
      default: return nil
      }
    case hebrewTableKey("השעה"):
      return tokens.count == 3 && extra == 0 ? 45 : nil
    case hebrewTableKey("שעתיים"):
      return tokens.count == 1 ? taskLength(minutes: 120 + extra) : nil
    case hebrewTableKey("שעות"):
      return hebrewCounts[counted].flatMap { taskLength(minutes: $0 * 60 + extra) }
    case _ where minuteNouns.contains(unit):
      return extra == 0 ? hebrewRoundCounts[counted].flatMap { taskLength(minutes: $0) } : nil
    default: return nil
    }
  }
}
