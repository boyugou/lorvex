import Foundation

extension LorvexCaptureVocabulary {
  /// Urdu, read for a user who reads Urdu in the Perso-Arabic script (ur-PK and
  /// ur-IN). A word needs a boundary on both sides: no Arabic letter, vowel
  /// sign, tatweel, joiner, or digit beside it, so "کلاس" (a class) and "آجکل"
  /// hold no day. The Urdu full stop (۔) and comma (،) are punctuation, so a
  /// word may stand right before one ("رپورٹ بھیجیں کل۔").
  ///
  /// The line is read in one form (``urduForMatching(_:)``): the Arabic-Indic
  /// and the Extended Arabic-Indic digits as Latin ones ("۵" and "٥" are "5"),
  /// the alefs with hamza or madda as the bare alef, the yeh forms (ي ى ئ) as
  /// the Urdu choti yeh (ی), the Arabic kaf as the Urdu kaf, every heh (ہ ه ة
  /// ھ) as one letter, and the noon ghunna (ں) as the noon, so a word reads the
  /// same typed on an Urdu or on an Arabic keyboard ("بھی" and "بهي", "ڈھائی"
  /// and "ڈهائی", "میں" and "مین"). The bari ye (ے) stays apart from the choti
  /// yeh, since "ہے" (is) and "ہی" (only) are different words. A word may carry
  /// vowel signs and tatweel anywhere ("اعلیٰ" and "اعلی" are one word), and a
  /// zero-width non-joiner or joiner between the parts of a compound reads as
  /// a space. The title keeps what was typed. Urdu written in Latin letters
  /// ("kal subah 9 baje") is not read.
  ///
  /// English is read beside Urdu, so a detail that needs no Urdu word is left
  /// to it: "3pm", "17:30", "30 min", "for 2h", "!!", and "p1" read as they do
  /// in any line. Urdu does not write a clock time with the letter h, so "2h"
  /// beside Urdu stays a length.
  ///
  /// کل means "tomorrow" and also "yesterday", and پرسوں means "the day after
  /// tomorrow" and also "the day before yesterday". This vocabulary reads کل as
  /// tomorrow and پرسوں as the day after tomorrow and never reads a past day,
  /// because the app writes the past day "گزشتہ کل". A day phrase is left unread
  /// when its line says the day is past or not coming: a past-tense form
  /// anywhere in the line (تھا, تھی, تھے, گیا, گئی, گئے, چکا, آیا, ہوا, ہوئی: "کل
  /// میٹنگ تھی"), or گزشتہ, پچھلا, گزرا, or پہلا just before it ("گزشتہ کل", "پچھلے
  /// جمعہ", "پہلے جمعہ"). The rule holds for آج and the weekdays too. "کیا" is no
  /// past marker ("کل کیا کرنا ہے"), nor are "آئی" and "آئے", which also form the
  /// future ("وہ کل آئے گا"). کل is also the word for "total": it is no day
  /// before "رقم", "تعداد", "ملا", "جمع", and the like ("کل رقم"), and "آج کل" is
  /// "nowadays". A day phrase that a possessive or "والا" follows is an attribute
  /// of a noun, not a plan ("پیر کی میٹنگ", "کل کی رپورٹ"), and "کل رات کا کھانا"
  /// reads only کل. "میں" is never read as a postposition after a day, because it
  /// is also "I" ("آج میں رپورٹ لکھوں گا").
  ///
  /// The weekday names are پیر or سوموار, منگل, بدھ, جمعرات, جمعہ or جمعے, ہفتہ or
  /// سنیچر, and اتوار. ہفتہ and ہفتے are also "the week", so they name Saturday
  /// only beside a mark of a day: کو, "کے دن", "کے روز", or تک after them ("ہفتے
  /// کو", "ہر ہفتے کو"), "بروز" before them, another weekday joined to them by
  /// اور or سے ("ہفتہ اور اتوار", "پیر سے ہفتہ"), or a date after them ("ہفتہ، 5
  /// اکتوبر"); anywhere else ("ہفتہ وار", "اس ہفتے", "ہفتہ بھر") they stay in the
  /// title. "پیر میں" (in the foot), "پیر صاحب", "بدھ مت", "جمعہ بازار", "جمعہ
  /// مبارک", and "نماز جمعہ" name no day. A weekday in a list of weekdays with no
  /// ہر ("پیر اور جمعرات کو") is left unread: one planned day cannot carry the
  /// list, and the others would stay in the title.
  ///
  /// - Day: آج, کل, پرسوں, each maybe with a part of the day (صبح, سویرے,
  ///   تڑکے, دوپہر, سہ پہر, شام, رات, دیر رات: "آج رات", "کل صبح", "آج کی رات";
  ///   the afternoon also as "دوپہر بعد" or "دوپہر کے بعد"), or after آئندہ or "آنے
  ///   والا" ("آئندہ کل", which the app writes for tomorrow); a part that any
  ///   other بعد follows is no part of the phrase, so "کل شام کے بعد فون کرنا"
  ///   reads only کل; the weekday names, alone or with کو, "کے دن", or "کے روز",
  ///   after "بروز", or after اس (this week's), اگلے (next week's, weeks starting
  ///   on Monday), or آئندہ and "آنے والے" (the coming one): "اس جمعہ", "اگلے پیر",
  ///   "آنے والے جمعہ کو", "اس ہفتے جمعہ"; اگلے ہفتے, آئندہ ہفتے (seven days ahead);
  ///   "3 دن بعد", "تین دن بعد", "2 ہفتے بعد", "ایک ہفتے کے بعد", "1 مہینے بعد" (months
  ///   counted on the calendar); the weekend, "ویک اینڈ", "اختتام ہفتہ", "ہفتے کے
  ///   آخر", or "ہفتہ اور اتوار", alone or after اس or اگلے; a date ("5 مئی", "5
  ///   مئی 2027", "تاریخ 5 مئی", "پیر، 5 اکتوبر"). A weekday alone means the next
  ///   such day, a full week ahead when it names today. "اس ہفتے" alone names no
  ///   single day and is not read. The weekend is the coming Saturday (today on
  ///   a Saturday or a Sunday) and, after اگلے, the Saturday a week later. A
  ///   date needs its day number before the month name (جنوری, فروری, مارچ,
  ///   اپریل, مئی, جون, جولائی, اگست, ستمبر, اکتوبر, نومبر, دسمبر, in the spellings
  ///   people type); a month alone, a date written in digits ("5/10"), a date
  ///   the calendar lacks ("31 اپریل"), and the Islamic and Indian calendars'
  ///   months stay in the title. The emphatic ہی or بھی after a day, or after its
  ///   postposition, goes with it ("آج ہی", "پیر کو ہی", "کل سے ہی"); "آج ہی کی
  ///   رپورٹ" is a noun's attribute and is not read.
  /// - Date range: "3 سے 5 مارچ", "3 مارچ سے 5 مارچ تک", "30 جنوری سے 2 فروری تک",
  ///   "3 تا 5 مارچ", "3-5 مارچ", "3 اور 5 مارچ کے درمیان", each maybe with a year
  ///   after the end, with "سے لے کر", and with تک, "کے بیچ", or "کے درمیان" after
  ///   the end. The first day is the planned day and the last the due day, so
  ///   another day phrase stays in the title. A day written without its month
  ///   takes the month of the end, the end must be after the start ("5 سے 3
  ///   مارچ" stays in the title whole), and the end names a month, so "3 سے 5"
  ///   is never a range of days. Two days joined by "اور" with no "کے بیچ" or "کے
  ///   درمیان" after them ("3 اور 5 مارچ") are two days, not a range, and stay
  ///   in the title whole. A day
  ///   alone opens a range joined by a dash only when the dash touches both
  ///   sides: "Sprint 12 - 20 مارچ" names a sprint and a date. A range in the
  ///   past tense, or one that a possessive follows ("5 سے 8 مئی تک کی چھٹی"),
  ///   may be an event the task only prepares for: it stays in the title
  ///   whole. A span of weekdays ("پیر سے بدھ تک", "پیر تا بدھ", "جمعہ سے پیر")
  ///   plans the coming first day and is due on the first last day after it.
  ///   After "ہر" or beside the words for every day it is a repeat instead, and
  ///   Monday to Friday or to Saturday with none of them ("پیر سے جمعہ تک")
  ///   stays in the title whole, since it is a week of work as often as it is
  ///   the working week.
  /// - Repeat: ہر دن, ہر روز, روزانہ, and ہر with a part of the day (ہر صبح, ہر شام
  ///   کو, ہر رات, ہر روز صبح), which keeps its part for an hour beside it ("ہر
  ///   صبح 6 بجے ورزش" is every day at 06:00). A bare "روز" is no repeat word,
  ///   since "کے روز" is "on the day of" ("جمعہ کے روز"). ہر ہفتے,
  ///   ہر ہفتہ, ہفتہ وار, ہر مہینے, ہر ماہ, ماہانہ, ماہوار, ہر سال, ہر برس, سالانہ
  ///   (each adverb maybe with "کی بنیاد پر" after it: "روزانہ کی بنیاد پر");
  ///   ہر پیر, ہر پیر کو, ہر پیر اور جمعرات, ہر پیر، بدھ اور جمعہ, ہر دوسرے پیر, ہر
  ///   ہفتے پیر کو, پیر اور جمعرات کو ہر ہفتے; ہر 2 دن, ہر دو دن, ہر دو دن بعد, ہر
  ///   دوسرے دن, ہر 3 ہفتے, ہر دوسرے ہفتے, ہر 3 مہینے, ہر 5 سال; "ہفتے میں ایک بار",
  ///   "مہینے میں ایک بار"; "ہر مہینے کی 5 تاریخ", "ہر مہینے 5 تاریخ کو", "ہر مہینے کی
  ///   پہلی تاریخ", "5 تاریخ کو ہر مہینے"; ہر ویک اینڈ and "ہر ہفتہ اور اتوار";
  ///   the working days as "ہر کام کے دن", "ہر ورکنگ ڈے", or "کام کے دنوں میں", or
  ///   a span of weekdays with ہر or the words for every day ("ہر پیر سے جمعہ",
  ///   "پیر سے جمعہ ہر روز"). An interval shorter than a day ("ہر 2 گھنٹے") is no
  ///   repeat, and a cadence word that makes an attribute of a noun is none
  ///   ("روزانہ کی رپورٹ", "ہر سال کا جائزہ"). The adverbs روزانہ, ہفتہ وار,
  ///   ماہانہ, and سالانہ read as repeats wherever they stand, since Urdu puts
  ///   an adjective before its noun and "روزانہ رپورٹ بھیجنا" is as often a
  ///   daily task as a daily report. "ہر ہفتے" is every week, and "ہر ہفتے کو"
  ///   every Saturday.
  /// - Due: a day before تک, "سے پہلے", or "سے قبل" ("جمعہ تک", "کل شام سے پہلے", "5 مئی
  ///   تک", "پرسوں تک", "اگلے ہفتے تک"), or after "آخری تاریخ", "مقررہ تاریخ", "حتمی
  ///   تاریخ", ڈیڈ لائن, or "آخری مہلت" ("آخری تاریخ: 5 مئی", "ڈیڈ لائن جمعہ"). A day
  ///   before a clock deadline ("جمعہ شام 5 بجے تک") is the due day and the clock
  ///   stays in the title. "آج تک" ("so far") and "آج سے پہلے" ("never before")
  ///   are idioms and are not read, nor is a deadline that a possessive
  ///   follows ("جمعہ تک کی رپورٹ"). A ہی or بھی after the deadline word goes
  ///   with it ("جمعہ تک ہی").
  /// - Time: "5 بجے", "5:30 بجے", "5.30 بجے", "ساڑھے 5 بجے" (5:30), "سوا 5 بجے"
  ///   (5:15), "پونے 6 بجے" (5:45), "ڈیڑھ بجے" (1:30), "ڈھائی بجے" (2:30), each
  ///   maybe after ٹھیک, تقریباً, قریباً, "لگ بھگ", or قریب. The hour may be a number
  ///   word from ایک to بارہ ("پانچ بجے", "ساڑھے تین بجے"); a number word without
  ///   بجے is never an hour. A part of the day sets the hour and may come before
  ///   it ("صبح 9 بجے", "شام کو 5 بجے", "رات کے 10 بجے", and with ٹھیک, تقریباً,
  ///   "لگ بھگ", or جلدی between them: "صبح ٹھیک 6 بجے") or after بجے ("9 بجے صبح",
  ///   "10 بجے رات"; not before a possessive: "5 بجے شام کی چائے" is 5 PM and
  ///   keeps "شام کی چائے"). صبح (also doubled, "صبح صبح" or "صبح سویرے"), سویرے,
  ///   and تڑکے are the morning (12 is no time), دوپہر and "سہ پہر" are noon at 12
  ///   and the afternoon from 1 to 6, شام is the evening, and رات runs past
  ///   midnight: "رات 12 بجے" is 00:00 of the next day, "رات 2 بجے" is 02:00 of
  ///   the next day, and "رات 8 بجے" is 20:00. "آدھی رات" and "نصف شب" are the
  ///   midnight that ends the day. An hour on the 12-hour clock (1 to 12, no
  ///   leading zero) written with no part of the day beside it takes its half
  ///   of the day from the one part of the day the line names elsewhere: in its
  ///   day phrase ("کل صبح میٹنگ 6 بجے" is 06:00), after ہر ("ہر صبح 6 بجے ورزش"),
  ///   or in a noun ("رات کا کھانا 8 بجے" is 20:00, "صبح کی سیر 6 بجے" is 06:00).
  ///   Two parts that differ leave the hour as it reads alone; a part that a
  ///   deadline word follows ("کل صبح تک") and "آدھی رات" are not counted; an
  ///   hour on the 24-hour clock (a leading zero, 0, or 13 and later) is read
  ///   as written. An hour from 1 to 6 with no part of the day anywhere in the
  ///   line is the afternoon, as in the other languages ("5 بجے" is 17:00, "7
  ///   بجے" is 07:00), unless written with a leading zero ("06:30 بجے"). A range:
  ///   "3 سے 5 بجے", "صبح 9 سے 11 بجے تک", "3 بجے سے 5 بجے تک", "دو سے چار بجے", "2 تا 4
  ///   بجے", "2-4 بجے", "14:00 سے 16:00", "صبح 9 بجے سے شام 5 بجے تک", each maybe
  ///   with "سے لے کر" and with تک or "کے بیچ" after it; the end carries بجے, so
  ///   "3 سے 5" is no range. A clock time that is a bound stays in the title
  ///   whole: before تک or "سے پہلے" ("5 بجے تک", "شام 5 بجے سے پہلے", "18:00 تک"),
  ///   "کے بعد", or "کے بیچ", and so do "5 بج کر 30 منٹ" and "5 بجنے میں 10 منٹ",
  ///   which count minutes past or to the hour. A number before a percent sign,
  ///   a currency sign, or a currency word is never a time.
  /// - Length: "30 منٹ", "2 گھنٹے", "1.5 گھنٹے", "1 گھنٹہ 30 منٹ", "آدھا گھنٹہ",
  ///   "پون گھنٹہ" (45 minutes), "سوا گھنٹہ" (75), "ڈیڑھ گھنٹہ", "ڈھائی گھنٹے", "ساڑھے
  ///   3 گھنٹے", "پونے دو گھنٹے", "دو گھنٹے", "بیس منٹ", each maybe after تقریباً,
  ///   قریباً, or "لگ بھگ", in the singular or the plural ("1 گھنٹہ", "2 گھنٹے", "2
  ///   گھنٹوں"). An amount before بعد, پہلے, or میں, or after ہر, "کم از کم", or
  ///   "دن میں", names a moment, an interval, or a bound, not a length ("2 گھنٹے
  ///   بعد", "1 گھنٹہ پہلے", "ہر 2 گھنٹے", "2 گھنٹے کے اندر", "دن میں 2 گھنٹے"), and
  ///   neither is a side of a range ("2 سے 3 گھنٹے", "2-3 گھنٹے"): each stays
  ///   whole in the title. گھنٹہ alone is no length ("گھنٹہ بھر").
  /// - Priority: "اعلیٰ ترجیح", "معمولی ترجیح", "کم ترجیح" (also درمیانی, عام, and
  ///   نچلی), each also after the word ("ترجیح: اعلیٰ") and maybe followed by "کے
  ///   ساتھ", پر, or سے ("اعلیٰ ترجیح کے ساتھ بھیجیں"); فوری, ضروری, "انتہائی
  ///   ضروری", فوراً, or ارجنٹ at the end of the line, and the same words opening
  ///   it before a colon or comma ("فوری: رپورٹ بھیجیں"). ضروری is an ordinary
  ///   adjective too, so "ضروری دوائیں خریدنا" and "رپورٹ بھیجیں ضروری ہے" stay in
  ///   the title, and so does "اعلیٰ ترجیح والے کام".
  static let urdu = LorvexCaptureVocabulary(
    readingForm: urduForMatching,
    priority: [urduRule(urduPriorityPattern, read: urduPriority)],
    dateRange: [
      urduRule(urduDateRangePattern, read: urduDateRange),
      urduRule(urduWeekdayRangePattern, read: urduWeekdayRange),
    ],
    keptInTitle: [
      urduRule(urduDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      urduRule(urduLengthPattern) { urduDeclinesLength($0) ? true : nil },
      urduRule(urduBajkarPattern) { _ in true },
      urduRule(urduNowadaysPattern) { _ in true },
    ],
    length: [urduRule(urduLengthPattern, read: urduLength)],
    time: [
      urduRule(urduTimeRangePattern, read: urduTimeRange),
      urduRule(urduColonTimeRangePattern, read: urduTimeRange),
      urduRule(urduTimePattern, read: urduTime),
      urduRule(urduPartColonTimePattern, read: urduPartColonTime),
      urduRule(urduMidnightPattern) { _ in ClockTime(minutes: 0, isAfterMidnight: true) },
    ],
    repeats: urduRepeatRules,
    due: [urduRule(urduDuePattern, read: urduDue)],
    when: [urduRule(urduWhenPattern, read: urduWhen)])

  // MARK: - Reading form and patterns

  /// The line with each letter and digit read in one form: the Arabic-Indic
  /// and the Extended Arabic-Indic digits as ASCII digits, the Arabic decimal
  /// separator and percent sign as "." and "%", the hamza-carrying and wasla
  /// alefs (أ إ آ ٱ) as the bare alef, the Arabic yeh, alef maksura, and
  /// hamza-on-yeh (ي ى ئ) as the Urdu choti yeh (ی), the hamza-on-bari-ye (ۓ)
  /// as the bari ye (ے), the hamza-on-waw (ؤ) as the waw, the Arabic kaf (ك)
  /// as the Urdu kaf (ک), every heh (ه ة ۃ ۀ ۂ ە and the do-chashmi ھ) as the
  /// Urdu heh (ہ), and the noon ghunna (ں) as the noon (ن). Written on an Urdu
  /// or an Arabic keyboard, with or without the madda, a word reads the same,
  /// and a pattern, written in its natural spelling, is read through the same
  /// form by ``urdu(_:readsMarks:)``. The bari ye stays apart from the choti
  /// yeh. Each replacement is one UTF-16 unit for one, so a match range in the
  /// result is the same range in `line`.
  static func urduForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(urduReading(of: scalar)) }
    return String(scalars)
  }

  private static func urduReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{0660}"..."\u{0669}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x0660))
    case "\u{06F0}"..."\u{06F9}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x06F0))
    case "\u{066B}": "."
    case "\u{066A}": "%"
    case "\u{0622}", "\u{0623}", "\u{0625}", "\u{0671}": "\u{0627}"
    case "\u{064A}", "\u{0649}", "\u{0626}": "\u{06CC}"
    case "\u{06D3}": "\u{06D2}"
    case "\u{0624}": "\u{0648}"
    case "\u{0643}": "\u{06A9}"
    case "\u{0647}", "\u{0629}", "\u{06C0}", "\u{06C2}", "\u{06C3}", "\u{06D5}", "\u{06BE}": "\u{06C1}"
    case "\u{06BA}": "\u{0646}"
    default: scalar
    }
  }

  /// Whether `scalar` is a vowel sign or another combining mark, or the
  /// tatweel, which a typed word may carry between or after its letters
  /// without changing it.
  private static func isUrduMark(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.value == 0x0640 { return true }
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: return true
    default: return false
    }
  }

  /// Whether `scalar` is a letter of the Perso-Arabic script (the tatweel is
  /// not one).
  private static func isUrduLetter(_ scalar: Unicode.Scalar) -> Bool {
    (0x0620...0x06FF).contains(scalar.value) && scalar.properties.generalCategory == .otherLetter
  }

  /// `text` without its vowel signs and tatweel, for the letters of a matched
  /// word as a reader compares them. `text` is already in the reading form.
  static func urduBare(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isUrduMark(scalar) { scalars.append(scalar) }
    return String(scalars)
  }

  /// A matched phrase as a reader compares it: without vowel signs and
  /// tatweel, each zero-width joiner and each run of spaces as one space.
  static func urduPhrase(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isUrduMark(scalar) {
      scalars.append(scalar == "\u{200C}" || scalar == "\u{200D}" ? " " : scalar)
    }
    return normalizedPhrase(String(scalars))
  }

  /// A matched phrase as one run of letters, whether its words were typed with
  /// a space, a zero-width non-joiner, or nothing between them ("سہ پہر" and
  /// "سہپہر" are one key).
  static func urduKey(_ text: String) -> String {
    urduPhrase(text).replacingOccurrences(of: " ", with: "")
  }

  /// A word written in a vocabulary table, as ``urduKey(_:)`` leaves a matched
  /// word: in the reading form, without signs or spaces.
  static func urduTableKey(_ word: String) -> String {
    urduKey(urduForMatching(word))
  }

  /// A phrase written in a vocabulary table, as ``urduPhrase(_:)`` leaves a
  /// matched phrase.
  static func urduTablePhrase(_ phrase: String) -> String {
    urduPhrase(urduForMatching(phrase))
  }

  /// The words of `text`, as letters only and without vowel signs.
  static func urduWords(in text: String) -> [String] {
    text.split(whereSeparator: { !$0.isLetter }).map { urduBare(String($0)) }
  }

  /// The pattern text between two parts of a compound word, which the typed
  /// word may separate with a space, a zero-width non-joiner, or nothing.
  private static let urduGap = #"[\s\x{200C}\x{200D}]?"#

  /// The pattern text for one space between two words, which a typist may also
  /// write as a zero-width non-joiner.
  private static let urduSpace = #"[\s\x{200C}\x{200D}]"#

  /// `pattern`, written in the natural spelling of its words, ready to match a
  /// line in the reading form: each Urdu letter outside a character set is read
  /// through ``urduForMatching(_:)`` and, with `readsMarks`, may be followed by
  /// vowel signs and tatweel; a letter that a quantifier follows keeps the
  /// quantifier on the letter with its signs. A zero-width non-joiner typed in
  /// `pattern` stands for the gap a compound word may have, and a `\s` outside
  /// a character set also matches a zero-width non-joiner or joiner. Other
  /// escapes and character sets pass through, their letters read through the
  /// same form. A pattern is expanded once, by ``urduRule(_:read:)``, never in
  /// parts that another pattern then embeds, and holds no look-behind that
  /// contains a letter outside a set, since the signs after a letter make its
  /// length unbounded.
  static func urdu(_ pattern: String, readsMarks: Bool = true) -> String {
    let signs = readsMarks ? #"[\p{M}\x{0640}]*"# : ""
    let quantifiers: Set<Unicode.Scalar> = ["?", "*", "+", "{"]
    let scalars = Array(pattern.unicodeScalars)
    var result = ""
    var isEscaped = false
    var isInSet = false
    for (index, scalar) in scalars.enumerated() {
      let isQuantified = index + 1 < scalars.count && quantifiers.contains(scalars[index + 1])
      if isEscaped {
        isEscaped = false
        if scalar == "s", !isInSet {
          result.unicodeScalars.removeLast()
          result += urduSpace
        } else {
          result.unicodeScalars.append(scalar)
        }
      } else if scalar == "\\" {
        result.unicodeScalars.append(scalar)
        isEscaped = true
      } else if isInSet {
        if scalar == "]" { isInSet = false }
        result.unicodeScalars.append(urduReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else if scalar == "\u{200C}" || scalar == "\u{200D}" {
        result += isQuantified ? "(?:\(urduGap))" : urduGap
      } else {
        let reading = urduReading(of: scalar)
        guard isUrduLetter(reading) else {
          result.unicodeScalars.append(scalar)
          continue
        }
        let letter = "\(Character(reading))\(signs)"
        result += isQuantified ? "(?:\(letter))" : letter
      }
    }
    return result
  }

  /// A rule whose `pattern` is written in natural spelling (see
  /// ``urdu(_:readsMarks:)``).
  static func urduRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: urdu(pattern), read: read)
  }

  /// Whether `pattern`, written in natural spelling, matches somewhere in
  /// `text`, which is in the reading form without vowel signs.
  static func urduFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(urdu(pattern, readsMarks: false)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Boundaries and words around a detail

  /// The Arabic-script letters, vowel signs, and digits that make a word go
  /// on, as the inside of a character set: the letters from U+0620 to U+06FF
  /// except the Urdu full stop (U+06D4), the Arabic Supplement, any combining
  /// mark or digit, and the joiners.
  private static let urduWordCharacters =
    #"\x{0620}-\x{06D3}\x{06D5}-\x{06FF}\x{0750}-\x{077F}\p{M}\p{N}\x{200C}\x{200D}"#

  /// A word boundary for words written in Perso-Arabic letters: no letter,
  /// vowel sign, digit, tatweel, or joiner on that side, so a word is never cut
  /// out of a longer one. The Urdu full stop is punctuation and a boundary.
  static let urduStart = #"(?<![\#(urduWordCharacters)])"#
  static let urduEnd = #"(?![\#(urduWordCharacters)])"#

  /// What may follow a clock time: no letter, vowel sign, digit, joiner, or
  /// colon (the word or the number goes on), no decimal fraction, no percent
  /// or currency sign or word with or without a space before it (the number
  /// is an amount: "20%", "500 روپے"), no dash before a digit, which makes the
  /// time one side of a range written with a dash, and no AM or PM after it.
  static let urduTimeEnd =
    #"(?![\#(urduWordCharacters):]|[.,]\p{N}|\s*[%\p{Sc}]|\s*(?:روپے|روپیہ|روپئے|ڈالر|پیسے|پیسہ|ریال|درہم)\#(urduEnd)|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no letter, vowel sign, digit, joiner, or colon,
  /// and no decimal fraction.
  static let urduDateEnd = #"(?![\#(urduWordCharacters):]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let urduNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The word just before `match`, as a reader compares it, or nil when the
  /// match opens the line or punctuation comes first.
  static func urduWordBefore(_ match: Match) -> String? {
    guard let word = wordBefore(match).map(urduKey), !word.isEmpty else { return nil }
    return word
  }

  /// The text before `match`, as a reader compares it: in the reading form
  /// without vowel signs.
  static func urduTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    return urduBare(String(match.source[..<start]))
  }

  /// The text after `match`, as a reader compares it.
  static func urduTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return urduBare(String(match.source[end...]))
  }

  // MARK: - Counts

  /// The number words one to twelve in the spellings people type, which stand
  /// before a counted noun ("تین دن", "دو گھنٹے") and name an hour before
  /// بجے.
  private static let urduHourCountSpellings: [(value: Int, words: [String])] = [
    (1, ["ایک"]), (2, ["دو"]), (3, ["تین"]), (4, ["چار"]), (5, ["پانچ"]), (6, ["چھ", "چھے"]), (7, ["سات"]),
    (8, ["آٹھ"]), (9, ["نو"]), (10, ["دس"]), (11, ["گیارہ"]), (12, ["بارہ"]),
  ]

  /// The round counts that name minutes or days, besides the ones above.
  private static let urduRoundCountSpellings: [(value: Int, words: [String])] = [
    (15, ["پندرہ"]), (20, ["بیس"]), (25, ["پچیس"]), (30, ["تیس"]), (40, ["چالیس"]), (45, ["پینتالیس", "پنتالیس"]),
    (50, ["پچاس"]), (60, ["ساٹھ"]),
  ]

  /// The counts keyed as ``urduKey(_:)`` leaves them: one to twelve, and with
  /// the round counts.
  static let urduCounts: [String: Int] = urduCountIndex(urduHourCountSpellings)
  static let urduRoundCounts: [String: Int] = urduCountIndex(urduHourCountSpellings + urduRoundCountSpellings)

  private static func urduCountIndex(_ spellings: [(value: Int, words: [String])]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for (value, words) in spellings {
      for word in words { counts[urduTableKey(word)] = value }
    }
    return counts
  }

  /// One to twelve in words, as a pattern, longest first.
  static var urduCountWords: String { alternation(of: urduHourCountSpellings.flatMap { $0.words }) }

  /// One to twelve and the round counts in words, as a pattern.
  static var urduRoundCountWords: String {
    alternation(of: (urduHourCountSpellings + urduRoundCountSpellings).flatMap { $0.words })
  }

  // MARK: - Priority

  /// Group 1: a written priority, with its level before or after the word
  /// "ترجیح" and maybe "کے ساتھ", پر, or سے after it ("اعلیٰ ترجیح کے ساتھ
  /// بھیجیں"); an urgent word has no group. A level word with "والا" after the
  /// priority describes a noun ("اعلیٰ ترجیح والے کام") and is no priority.
  private static var urduPriorityPattern: String {
    let level =
      #"سب\s+سے\s+(?:زیادہ|اونچی|بلند)|انتہائی\s+اعلی|اعلی|اعلا|زیادہ|بلند|اونچی|درمیانی|معمولی|عام|اوسط|سب\s+سے\s+کم|کمتر|نچلی|کم"#
    let urgent = #"انتہائی\s+ضروری|نہایت\s+ضروری|بہت\s+ضروری|فوری|ضروری|فورا|ارجنٹ"#
    return
      #"\#(urduStart)((?:\#(level))\s*ترجیح|ترجیح\s*[:：]?\s*(?:\#(level)))\#(urduEnd)(?:\s+(?:کے\s+ساتھ|پر|سے)\#(urduEnd))?(?!\s+وال(?:ا|ی|ے|وں)\#(urduEnd))|(?<=\s)(?:\#(urgent))\#(urduEnd)(?=\s*[۔.]?\s*$)|^\s*(?:\#(urgent))\#(urduEnd)(?=\s*[:：,，،])"#
  }

  private static func urduPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(urduPhrase) else { return .p1 }
    let words = Set(urduWords(in: phrase))
    if !words.isDisjoint(with: ["درمیانی", "معمولی", "عام", "اوسط"].map(urduTableKey)) { return .p2 }
    if !words.isDisjoint(with: ["کم", "کمتر", "نچلی"].map(urduTableKey)) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "30 منٹ", "2 گھنٹے", "1.5 گھنٹے", "1 گھنٹہ 30 منٹ", "آدھا گھنٹہ", "ڈیڑھ
  /// گھنٹہ", "ڈھائی گھنٹے", "سوا گھنٹہ", "پون گھنٹہ", "ساڑھے 3 گھنٹے", "پونے دو
  /// گھنٹے", "دو گھنٹے", "بیس منٹ", each maybe after "تقریباً", "قریباً", or "لگ
  /// بھگ" and maybe followed by "کے لیے", "کا", "کی", "کے", or "تک", which go
  /// with it ("30 منٹ کی میٹنگ" is a meeting of 30 minutes). Groups: 1 a word
  /// that makes the length approximate; 2 a word that makes the amount an
  /// interval, a bound, or a rate ("ہر 2 گھنٹے", "کم از کم 2 گھنٹے", "دن میں 2
  /// گھنٹے"); 3 the hours of an amount with a unit and 4 its minutes; 5
  /// minutes; 6 a length in words; 7 a word after the amount that makes it a
  /// moment, the past, a bound, or a comparison ("2 گھنٹے بعد", "1 گھنٹہ پہلے",
  /// "2 گھنٹے کے اندر", "2 گھنٹے میں", "2 گھنٹے سے زیادہ"). A match with group 2
  /// or 7 is no length: ``urduLength(_:)`` declines it and a keep rule claims
  /// it, so the amount stays whole in the title. The unit nouns are Urdu, so
  /// an amount written with a Latin unit ("ہر 2h") is left to English. The
  /// amount may not follow a digit, a colon, or a separator, and it may not
  /// be a side of a range ("2-3 گھنٹے", "2 سے 3 گھنٹے", "5 منٹ سے 10 منٹ").
  static var urduLengthPattern: String {
    let hourNoun = "گھنٹ(?:ہ|ا|ے|وں)"
    let minuteNoun = "منٹ(?:وں|س)?"
    let opener =
      #"(?:(?:(تقریبا|قریبا|لگ\s*بھگ)|(ہر|کم\s+از\s+کم|زیادہ\s+سے\s+زیادہ|اوسطا|(?:دن|ہفتے|مہینے|سال)\s+میں))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,])(?<!\p{N}\s?[-–—]\s?)"#
    let hours = #"(\d+(?:\.\d+)?)\s*(?:\#(hourNoun))(?:\s+(?:اور\s+)?(\d{1,2})\s*(?:\#(minuteNoun)))?"#
    let minutes = #"(\d+)\s*(?:\#(minuteNoun))"#
    let words =
      #"((?:آدھا|آدھے|آدھ|نصف)\s+\#(hourNoun)|(?:ڈیڑھ|ڈھائی|اڑھائی|سوا|پون)\s+\#(hourNoun)|(?:ساڑھے|سوا|پونے)\s+(?:\d{1,2}|\#(urduCountWords))\s+\#(hourNoun)|(?:\#(urduCountWords))\s+\#(hourNoun)|(?:\#(urduRoundCountWords))\s+\#(minuteNoun))"#
    let trailing =
      #"(?:\s+(?:(بعد|پہلے|میں|کے\s+(?:بعد|پہلے|اندر|دوران|درمیان|بیچ)|سے\s+(?:زیادہ|زائد|کم|پہلے|بعد|اوپر|نیچے))|(?:کے\s+لیے|کا|کی|کے|تک))\#(urduEnd))?"#
    return
      #"\#(urduStart)\#(opener)(?:\#(boundaries)(?:\#(hours)|\#(minutes))|\#(words))\#(urduEnd)(?!\s*[-–—]\s*\d|\s+(?:سے|تا)\s+\d)\#(trailing)"#
  }

  /// True for a match that is no length: an interval, a bound, or a rate ("ہر
  /// 2 گھنٹے", "دن میں 2 گھنٹے"), a moment, the past, or a comparison ("2
  /// گھنٹے بعد", "1 گھنٹہ پہلے"), or the end of a range of amounts ("2 سے 3
  /// گھنٹے").
  static func urduDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil || urduIsRangeEnd(match)
  }

  /// Whether the text before `match` ends with a number or a unit and "سے" or
  /// "تا", which makes the amount the end of a range ("2 سے 3 گھنٹے", "5 منٹ
  /// سے 10 منٹ").
  private static func urduIsRangeEnd(_ match: Match) -> Bool {
    urduFinds(#"(?:\d|منٹ|گھنٹے|گھنٹہ|گھنٹا)\s+(?:سے|تا)\s+$"#, in: urduTextBefore(match))
  }

  private static func urduLength(_ match: Match) -> Int? {
    if urduDeclinesLength(match) { return nil }
    if let hours = match.group(3).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(4).flatMap(number) ?? 0))
    }
    if let minutes = match.group(5).flatMap(number) { return taskLength(minutes: minutes) }
    guard let phrase = match.group(6).map(urduPhrase) else { return nil }
    let tokens = phrase.split(separator: " ").map(String.init)
    guard let unit = tokens.last else { return nil }
    // The hour noun begins with گ; the minute noun with م.
    let isHours = unit.unicodeScalars.first == "\u{06AF}"
    switch tokens.count {
    case 2:
      switch tokens[0] {
      case urduTableKey("آدھا"), urduTableKey("آدھے"), urduTableKey("آدھ"), urduTableKey("نصف"): return 30
      case urduTableKey("ڈیڑھ"): return 90
      case urduTableKey("ڈھائی"), urduTableKey("اڑھائی"): return 150
      case "سوا": return 75
      case "پون": return 45
      default:
        guard let count = (isHours ? urduCounts : urduRoundCounts)[tokens[0]] else { return nil }
        return taskLength(minutes: isHours ? count * 60 : count)
      }
    case 3:
      guard let count = number(tokens[1]) ?? urduCounts[tokens[1]], count >= 1 else { return nil }
      switch tokens[0] {
      case urduTableKey("ساڑھے"): return taskLength(minutes: count * 60 + 30)
      case "سوا": return taskLength(minutes: count * 60 + 15)
      case urduTableKey("پونے"): return taskLength(minutes: count * 60 - 15)
      default: return nil
      }
    default:
      return nil
    }
  }

  /// "5 بج کر 30 منٹ" and "5 بجنے میں 10 منٹ", which name a clock time as a count
  /// of minutes past or to the hour. They are kept in the title whole, so their
  /// minutes are not read as a length.
  static let urduBajkarPattern =
    #"\#(urduStart)(?:\d{1,2}\s+بج\s*کر\s+\d{1,2}\s+منٹ(?:\s+پر)?|(?:\d{1,2}|\#(urduCountWords))\s+بجنے\s+میں\s+(?:\d{1,2}|\#(urduRoundCountWords))\s+منٹ)\#(urduEnd)"#

  /// "آج کل" ("nowadays") and "آجکل", which hold no day: the phrase stays in the
  /// title whole, so neither word is read alone.
  static let urduNowadaysPattern = #"\#(urduStart)آج\s*کل\#(urduEnd)"#
}
