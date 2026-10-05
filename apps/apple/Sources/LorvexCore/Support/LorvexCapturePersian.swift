import Foundation

extension LorvexCaptureVocabulary {
  /// Persian, read for a user who reads Persian in the Perso-Arabic script,
  /// with the Dari spellings of Afghanistan beside the Iranian ones. A word
  /// needs a boundary on both sides: no Arabic letter, vowel sign, tatweel,
  /// joiner, or digit beside it, and the zero-width non-joiner that Persian
  /// writes inside a word ("پس‌فردا", "دوشنبه‌ها", "می‌روم") keeps it whole, so
  /// "امروزی" (modern) and "فردایی" hold no day and "هفته‌ها" no week.
  ///
  /// The line is read in one form (``persianForMatching(_:)``): the Arabic-Indic
  /// and the Extended Arabic-Indic digits as Latin ones ("۵" and "٥" are "5"),
  /// the alefs with hamza or madda (أ إ آ) as the bare alef, the Arabic yeh and
  /// alef maksura (ي ى) as the Persian yeh, the Arabic kaf (ك) as the Persian
  /// kaf, and teh marbuta (ة) as heh, so a word reads the same typed on a
  /// Persian or an Arabic keyboard ("آینده" and "اینده", "هفته‌ی" and "هفته‌ي").
  /// A word may carry vowel signs and tatweel anywhere, and a compound may be
  /// typed with a space, a zero-width non-joiner, or nothing between its words
  /// ("سه‌شنبه", "سه شنبه", and "سهشنبه" are one word, and so are "پس‌فردا" and
  /// "پس فردا"). The title keeps what was typed. Persian written in Latin
  /// letters ("farda sobh") is not read.
  ///
  /// English is read beside Persian, so a detail that needs no Persian word is
  /// left to it: "3pm", "17:30", "30 min", "for 2h", "!!", and "p1" read as
  /// they do in any line. Persian does not write a clock time with the letter
  /// h, so "2h" beside Persian stays a length.
  ///
  /// A written date is counted in the Solar Hijri calendar, which Persian
  /// speakers date by, or in the Gregorian one when it names a Gregorian
  /// month. Weeks start on Monday, as the app's weeks do in every language:
  /// "هفته آینده سه‌شنبه" is the Tuesday of the week that begins on the coming
  /// Monday, and "هفته آینده شنبه" the Saturday that closes it, although
  /// Iranian calendars open the week on Saturday.
  ///
  /// Only the future is read. Persian has one word for each of today,
  /// tomorrow, and the day after, so unlike Hindi and Urdu no past-tense
  /// guard is needed, and "دیروز" and "پریروز" name no day. A weekday that
  /// "گذشته", "پیش", "قبل", or "قبلی" follows is the past ("پنجشنبه گذشته",
  /// "جمعه قبل"), "شب جمعه" is the night before Friday, and a weekday that
  /// "بازار" or "سوری" follows or "نماز" precedes is a name ("بازار جمعه",
  /// "چهارشنبه‌سوری", "نماز جمعه"): none is read as a day. A day phrase that
  /// follows a word that sets it against something else ("تا", "قبل از", "بعد
  /// از", "از") or inside a stretch ("هر", "همه", "تمام", "طی", "ظرف", "آخر",
  /// "اول", "نیمه", "پایان", "ابتدای", "طول") is no planned day.
  ///
  /// - Day: امروز, امشب, فردا, پس‌فردا, each maybe with a part of the day
  ///   (صبح, سحر, بامداد, ظهر, عصر, غروب, شب: "امروز صبح", "صبح فردا", "فردا
  ///   شب", "عصر امروز") or after "همین"; "این شب", "این صبح", "این عصر"
  ///   (today); "۳ روز دیگر", "سه روز دیگه", "۲ هفته دیگر", "یک ماه دیگر"
  ///   (months counted on the Solar Hijri calendar), "۳ روز بعد", "بعد از ۳
  ///   روز", "هفته دیگر" (a count ahead; a phrase that از, مانده, or باقی
  ///   follows is counted from something else or counts what is left, as in
  ///   "۳ روز بعد از جلسه" and "۳ روز دیگر مانده"); هفته آینده, هفته بعد, هفته
  ///   آتی, هفته‌ی بعد (seven days ahead); the weekday names (یکشنبه, دوشنبه,
  ///   سه‌شنبه, چهارشنبه, پنجشنبه, جمعه or آدینه, شنبه), alone or with "روز"
  ///   before them, with a part of the day before or after ("صبح پنجشنبه",
  ///   "جمعه عصر"; the night only after: "پنجشنبه شب"), after "این" or "همین"
  ///   (this week's), with a word for next after them ("پنجشنبه آینده",
  ///   "پنجشنبه‌ی بعد", "جمعه آتی"), or with the week named before or after
  ///   ("هفته آینده سه‌شنبه", "سه‌شنبه هفته آینده", "پنجشنبه این هفته"); a
  ///   date ("۱۲ مهر", "۱۲ مهر ماه", "۱۲ مهرماه", "۱۲ مهر ۱۴۰۵", "پنجشنبه ۱۲
  ///   مهر", "۵ مارس", "۵ مارس ۲۰۲۷"), each maybe after "برای" or "در". A
  ///   weekday alone means the next such day, a full week ahead when it names
  ///   today; "این" makes it this week's, today when it names today; a word
  ///   for next makes it the coming one, a full week ahead when it names
  ///   today; the week named first or after makes it next week's. "بعد" is a
  ///   word for next only when "از" does not follow it: "پنجشنبه بعد از ظهر"
  ///   is the afternoon. A date needs its day number before the month name,
  ///   which is a Solar Hijri month (فروردین, اردیبهشت, خرداد, تیر, مرداد,
  ///   شهریور, مهر, آبان, آذر, دی, بهمن, اسفند) or a Gregorian one in the
  ///   spellings Persian and Dari write (ژانویه or جنوری, فوریه or فبروری,
  ///   مارس or مارچ, آوریل or اپریل, مه, ژوئن or جون, ژوئیه or جولای, اوت or
  ///   اگست, سپتامبر, اکتبر or اکتوبر, نوامبر or نومبر, دسامبر or دسمبر). A date
  ///   without a year is this Solar year's, or next year's once passed; a
  ///   written year (13xx or 14xx for a Solar date, 19xx or 20xx for a
  ///   Gregorian one) must not be past or more than ten years ahead. A month
  ///   alone, a date written in digits ("۱۴۰۵/۷/۱۲"), a date the calendar
  ///   lacks (30 Esfand outside a leap year, 31 of a month after Shahrivar),
  ///   the lunar Hijri months, the Afghan names of the Solar months (حمل,
  ///   ثور, ...), and the Dari "می" for May stay in the title: "می" begins
  ///   every present-tense verb ("۲ می خرم"). The weekend and the working days
  ///   are not read either, since which days they are depends on the country
  ///   and the workplace.
  /// - Date range: "از ۳ تا ۵ آبان", "۳ تا ۵ آبان", "از ۳ آبان تا ۵ آبان", "از
  ///   ۳۰ مهر تا ۲ آبان", "بین ۳ و ۵ آبان", "۳-۵ آبان", "از ۳ تا ۵ مارس",
  ///   each maybe with a year after the end and with "الی" for "تا". The
  ///   first day is the planned day and the last the due day, so another day
  ///   phrase stays in the title. A day written without its month takes the
  ///   month of the end, the end must be after the start ("از ۵ تا ۳ آبان"
  ///   stays in the title whole), and a range whose sides name different
  ///   calendars is claimed whole and read as no days. "و" joins the sides
  ///   only after "بین" ("۳ و ۵ آبان" names two days and stays in the title
  ///   whole). A day alone opens a range joined by a dash only when
  ///   the dash touches both sides ("اسپرینت ۱۲ - ۲۰ مهر" names a sprint and a
  ///   date), and days of the month with no month ("از ۳ تا ۵") are no range.
  ///   A span of weekdays ("از دوشنبه تا چهارشنبه", "پنجشنبه تا شنبه", "بین
  ///   دوشنبه و چهارشنبه") plans the coming first day and is due on the first
  ///   last day after it, through the week's end. Beside "هر", "روزهای", or
  ///   the words for every day it is a repeat instead, and a working week
  ///   with none of them (Monday to Friday, Saturday to Wednesday, Saturday
  ///   to Thursday: "از شنبه تا چهارشنبه") stays in the title whole, since it
  ///   is a week of work as often as it is a span of days.
  /// - Repeat: هر روز, هر صبح, هر روز صبح, هر شب, هر عصر, صبح‌ها, شب‌ها; هر
  ///   هفته, هر ماه, هر سال; هر دوشنبه, هر روز دوشنبه, هر
  ///   هفته دوشنبه, هر دوشنبه و پنجشنبه, هر صبح جمعه, روزهای دوشنبه و
  ///   چهارشنبه, دوشنبه‌ها, همه دوشنبه‌ها و پنجشنبه‌ها, دوشنبه و پنجشنبه هر
  ///   هفته; هر ۲ روز, هر دو روز, هر سه هفته, هر ۳ ماه, هر ۵ سال, هر پانزده
  ///   روز, each maybe followed by "یک بار" ("هر دو روز یک بار"); یک روز در
  ///   میان, روز در میان, هر هفته در میان, یک ماه در میان, یک دوشنبه در میان;
  ///   هفته‌ای یک بار, ماهی یک بار, سالی یک بار, روزی یک بار, دو هفته یک بار; and
  ///   a span of weekdays beside "هر", "روزهای", or the words for every day ("هر
  ///   روز از دوشنبه تا جمعه", "روزهای شنبه تا چهارشنبه", "از شنبه تا چهارشنبه
  ///   هر روز"), which runs from its first weekday to its last through the
  ///   week's end. The adverbs روزانه, هر روزه, هفتگی, ماهانه, and سالانه read
  ///   only opening the line ("روزانه ۳۰ دقیقه ورزش") or ending it after a
  ///   comma ("ورزش، روزانه"): after the task's noun they are its adjective
  ///   ("گزارش روزانه", "جلسه هفتگی"). A part of the day before a weekday ("هر شب جمعه") is that
  ///   day's, and an interval shorter than a day ("هر ۲ ساعت") is no repeat.
  ///   "هر ماه" beside a day of the month ("هر ماه ۵ام", "۱۵ام هر ماه") stays
  ///   in the title, since Persian speakers count the days of a month in the
  ///   Solar Hijri calendar, whose months are not the Gregorian months a
  ///   monthly repeat keeps.
  /// - Due: a day after تا, قبل از, پیش از, حداکثر, or نهایتاً ("تا جمعه", "قبل
  ///   از فردا", "تا ۱۲ مهر", "حداکثر پنجشنبه", "تا آخر روز"), or after "مهلت",
  ///   "ددلاین", "سررسید", "موعد", "آخرین مهلت", "تاریخ سررسید", or "تاریخ
  ///   تحویل" ("مهلت: جمعه", "ددلاین ۱۲ مهر", "سررسید فردا"). A day before a
  ///   clock deadline ("جمعه تا ساعت ۵", "فردا قبل از ساعت ۵") is the due day
  ///   and the clock stays in the title, and so is the day between a deadline
  ///   word and a clock ("تا جمعه ساعت ۵"). "بعد از" and "پس از" are no
  ///   deadline.
  /// - Time: "ساعت ۵", "ساعت ۵:۳۰", "ساعت ۱۷", "ساعت پنج", "در ساعت ۵", "رأس
  ///   ساعت ۵", "حدود ساعت ۵", each maybe with a fraction of the hour ("ساعت ۵
  ///   و نیم", "ساعت ۵ و ربع", "ساعت ۵ و ده دقیقه", "ساعت ۶ ربع کم", "ساعت ۶
  ///   ده دقیقه کم") and a part of the day ("ساعت ۵ عصر", "ساعت ۸ و نیم شب");
  ///   an hour with a part of the day and no "ساعت" ("۸ شب", "۹ صبح", "۸:۳۰
  ///   شب", "۸ و نیم شب", "۵ بعدازظهر"); minutes before an hour ("یک ربع به
  ///   ۶", "ربع به ۶", "ده دقیقه به ۶", "۱۰ دقیقه مانده به ۶", "یک ربع به ۶
  ///   عصر"); an hour and a half or a quarter at the end of the line ("۵ و
  ///   نیم", "۸ و ربع"; "۲ و نیم کیلو" counts kilograms); "در نیمه‌شب" and
  ///   "ساعت نیمه‌شب" (the midnight that ends the day). A range: "از ساعت ۲ تا
  ///   ۴", "ساعت ۲ تا ۴", "ساعت ۲ الی ۴", "از ۹ صبح تا ۵ بعدازظهر", "از ۲ تا ۴
  ///   عصر", "بین ساعت ۲ و ۴", "ساعت ۲-۴", "از ساعت ۱۴:۰۰ تا ۱۶:۰۰", "۱۴:۰۰ تا
  ///   ۱۶:۰۰"; two bare
  ///   hours are a range only after "ساعت" or with a part of the day ("از ۱۴ تا
  ///   ۱۶ صفحه" is a title). The morning is صبح, سحر, بامداد, پگاه, and قبل از
  ///   ظهر (1 to 11 o'clock), the day ظهر and بعد از ظهر (noon at 12 and the
  ///   afternoon from 1 to 6), the evening عصر and غروب (1 to 11 o'clock,
  ///   counted from noon: "ساعت ۷ عصر" is 19:00), and the night شب and شامگاه:
  ///   6 to 11 o'clock is the evening, 12 is the midnight that ends the day,
  ///   and 1 to 5 o'clock are the small hours of the next day, so "ساعت ۲ شب"
  ///   is 02:00 of the next day. A number before a part of the day is as often
  ///   a count ("۳ شب" is three nights), so the night names no hour from 1 to 5
  ///   without "ساعت". An hour from 1 to 6 with no part of the day is the
  ///   afternoon, as in the other languages ("ساعت ۵" is 17:00, "ساعت ۷" is
  ///   07:00), unless written with a leading zero ("ساعت ۰۶:۳۰"); an hour on
  ///   the 24-hour clock (13 and later) is read as written. A time with no
  ///   part of its own takes the part of the day that stands right before it,
  ///   maybe with its day: "فردا صبح ساعت ۶" is 06:00 and "هر شب ساعت ۱۰" is
  ///   22:00. A clock time that is a bound stays in the title whole, after
  ///   "تا", "قبل از", "پیش از", "بعد از", or "پس از" ("تا ساعت ۵", "قبل از
  ///   ۱۸:۰۰", "بعد از ساعت ۵:۳۰"), and a time that a percent sign, a currency
  ///   sign, or a decimal fraction follows is an amount, not a time.
  /// - Length: "۲۰ دقیقه", "۲ ساعت", "۱٫۵ ساعت", "۲ ساعت و ۳۰ دقیقه", "نیم
  ///   ساعت", "ربع ساعت", "یک ربع", "سه ربع", "یک ساعت و نیم", "دو و نیم
  ///   ساعت", "پنج دقیقه", "بیست و پنج دقیقه", "جلسه ۲ ساعته", "۳۰ دقیقه‌ای",
  ///   each maybe after "به مدت", "مدت", "حدود", "در حدود", "تقریباً", "نزدیک",
  ///   or "برای". An amount after بعد از, پس از, قبل از, پیش از, بیش از, کمتر
  ///   از, حداقل, حداکثر, هر, تا, طی, ظرف, در, از, بالای, زیر, روزی, هفته‌ای,
  ///   ماهی, or سالی, and one before بعد, پس, قبل, پیش, دیگر, دیگه, باقی, "در
  ///   روز", "هر روز", or a word like روزانه, names a moment, an interval, a
  ///   rate, or a bound, not a length ("بعد از ۱۵ دقیقه", "هر ۲ ساعت", "روزی ۲
  ///   ساعت", "۲ ساعت پیش", "۱۰ دقیقه دیگر"): it stays whole in the title, and
  ///   so does a side of a range ("۲-۳ ساعت", "۲ تا ۳ ساعت"). Minutes before
  ///   "به" and an hour or before "کم" are a clock time ("ده دقیقه به ۶"), not
  ///   a length. "ساعت" and "دقیقه" alone are nouns (a watch, a moment).
  /// - Priority: اولویت بالا, اولویت متوسط, اولویت پایین (also بسیار بالا, خیلی
  ///   بالا, زیاد, معمولی, نرمال, بسیار پایین, خیلی پایین, کمتر, and کم), each
  ///   also with a colon ("اولویت: بالا") or after "با" ("با اولویت بالا");
  ///   "فوری" (maybe after خیلی or بسیار) at the end of the line, and "فوری"
  ///   opening it before a colon or comma ("فوری: گزارش را بفرست"). "فوری" is
  ///   an ordinary adjective too, so "کار فوری دارم" and "تماس فوری با مادر"
  ///   stay in the title.
  ///
  /// The vocabulary accepts some collisions with ordinary words: "۲ ساعت" reads
  /// as a length where it counts watches ("۲ ساعت مچی"), "امروز" reads as today
  /// in "گزارش امروز", and a weekday after a part of the day reads as a day in
  /// a title such as "کلاس عصر جمعه". For a user who reads both Arabic and
  /// Persian, Arabic is tried first; the two share few words, since Persian
  /// writes "ساعت", "روز", and "هر" where Arabic writes "الساعة", "يوم", and "كل".
  static let persian = LorvexCaptureVocabulary(
    readingForm: persianForMatching,
    priority: [persianRule(persianPriorityPattern, read: persianPriority)],
    dateRange: [
      persianRule(persianDateRangePattern, read: persianDateRange),
      persianRule(persianWeekdayRangePattern, read: persianWeekdayRange),
    ],
    keptInTitle: [
      persianRule(persianDeadlineClockPattern) { $0.group(1) == nil ? nil : true },
      persianRule(persianLengthPattern) { persianDeclinesLength($0) ? true : nil },
    ],
    length: [persianRule(persianLengthPattern, read: persianLength)],
    time: [
      persianRule(persianTimeRangePattern, read: persianTimeRange),
      persianRule(persianColonTimeRangePattern, read: persianColonTimeRange),
      persianRule(persianMarkedTimePattern, read: persianMarkedTime),
      persianRule(persianToHourPattern, read: persianToHourTime),
      persianRule(persianPartTimePattern, read: persianPartTime),
      persianRule(persianBareFractionPattern, read: persianBareFractionTime),
      persianRule(persianMidnightPattern, read: persianMidnightTime),
    ],
    repeats: persianRepeatRules,
    due: [persianRule(persianDuePattern, read: persianDue)],
    when: [persianRule(persianWhenPattern, read: persianWhen)])

  // MARK: - Reading form and patterns

  /// The line with each letter and digit read in one form: the Arabic-Indic
  /// and the Extended Arabic-Indic digits as ASCII digits, the Arabic decimal
  /// separator and percent sign as "." and "%", the hamza-carrying and wasla
  /// alefs (أ إ آ ٱ) as the bare alef, the Arabic yeh, alef maksura, and
  /// hamza-on-yeh (ي ى ئ) as the Persian yeh (ی), the Arabic kaf (ك) as the
  /// Persian kaf (ک), and teh marbuta (ة) and heh with yeh above (ۀ) as heh
  /// (ه). Written on a Persian or an Arabic keyboard, with or without the
  /// madda, a word reads the same ("آینده" and "اینده", "ساعت" and "ساعة"), and
  /// a pattern, written in its natural spelling, is read through the same form
  /// by ``persian(_:readsMarks:)``. The Urdu heh forms (ہ ھ) are not folded
  /// into heh: they would make Urdu "ہفتہ" (Saturday) read as the Persian word
  /// for a week. Each replacement is one UTF-16 unit for one, so a match range
  /// in the result is the same range in `line`.
  static func persianForMatching(_ line: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars { scalars.append(persianReading(of: scalar)) }
    return String(scalars)
  }

  private static func persianReading(of scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar {
    case "\u{0660}"..."\u{0669}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x0660))
    case "\u{06F0}"..."\u{06F9}": Unicode.Scalar(UInt8(truncatingIfNeeded: 0x30 + scalar.value - 0x06F0))
    case "\u{066B}": "."
    case "\u{066A}": "%"
    case "\u{0622}", "\u{0623}", "\u{0625}", "\u{0671}": "\u{0627}"
    case "\u{064A}", "\u{0649}", "\u{0626}": "\u{06CC}"
    case "\u{0643}": "\u{06A9}"
    case "\u{0629}", "\u{06C0}": "\u{0647}"
    default: scalar
    }
  }

  /// Whether `scalar` is a vowel sign or another combining mark, or the
  /// tatweel, which a typed word may carry between or after its letters
  /// without changing it.
  private static func isPersianMark(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.value == 0x0640 { return true }
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: return true
    default: return false
    }
  }

  /// Whether `scalar` is a letter of the Perso-Arabic script (the tatweel is
  /// not one).
  private static func isPersianLetter(_ scalar: Unicode.Scalar) -> Bool {
    (0x0620...0x06FF).contains(scalar.value) && scalar.properties.generalCategory == .otherLetter
  }

  /// `text` without its vowel signs and tatweel, for the letters of a matched
  /// word as a reader compares them. `text` is already in the reading form.
  static func persianBare(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isPersianMark(scalar) { scalars.append(scalar) }
    return String(scalars)
  }

  /// A matched phrase as a reader compares it: without vowel signs and
  /// tatweel, each zero-width joiner and each run of spaces as one space, so
  /// "پس‌فردا" and "پس فردا" are the same two words.
  static func persianPhrase(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !isPersianMark(scalar) {
      scalars.append(scalar == "\u{200C}" || scalar == "\u{200D}" ? " " : scalar)
    }
    return normalizedPhrase(String(scalars))
  }

  /// A matched phrase as one run of letters, whether its words were typed
  /// with a space, a zero-width non-joiner, or nothing between them ("سه‌شنبه",
  /// "سه شنبه", and "سهشنبه" are one key).
  static func persianKey(_ text: String) -> String {
    persianPhrase(text).replacingOccurrences(of: " ", with: "")
  }

  /// The pattern text between two parts of a compound word, which the typed
  /// word may separate with a space, a zero-width non-joiner, or nothing.
  private static let persianGap = #"[\s\x{200C}\x{200D}]?"#

  /// The pattern text for one space between two words, which Persian typists
  /// also write as a zero-width non-joiner ("قبل‌از", "یک‌ربع").
  private static let persianSpace = #"[\s\x{200C}\x{200D}]"#

  /// `pattern`, written in the natural spelling of its words, ready to match a
  /// line in the reading form: each Persian letter outside a character set is
  /// read through ``persianForMatching(_:)`` and, with `readsMarks`, may be
  /// followed by vowel signs and tatweel; a letter that a quantifier follows
  /// ("ثلاثاء?") keeps the quantifier on the letter with its signs. A
  /// zero-width non-joiner typed in `pattern` stands for the gap a compound
  /// word may have ("سه‌شنبه" also reads "سه شنبه" and "سهشنبه"), and a `\s`
  /// outside a character set also matches a zero-width non-joiner or joiner,
  /// so the words of "قبل از" may be typed with one between them. Other
  /// escapes and character sets pass through, their letters read through the
  /// same form. Patterns hold no lookbehind that contains a letter outside a
  /// set, since the signs after a letter make its length unbounded.
  static func persian(_ pattern: String, readsMarks: Bool = true) -> String {
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
          result += persianSpace
        } else {
          result.unicodeScalars.append(scalar)
        }
      } else if scalar == "\\" {
        result.unicodeScalars.append(scalar)
        isEscaped = true
      } else if isInSet {
        if scalar == "]" { isInSet = false }
        result.unicodeScalars.append(persianReading(of: scalar))
      } else if scalar == "[" {
        isInSet = true
        result.unicodeScalars.append(scalar)
      } else if scalar == "\u{200C}" || scalar == "\u{200D}" {
        result += isQuantified ? "(?:\(persianGap))" : persianGap
      } else {
        let reading = persianReading(of: scalar)
        guard isPersianLetter(reading) else {
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
  /// ``persian(_:readsMarks:)``).
  static func persianRule<Value>(_ pattern: String, read: @escaping @Sendable (Match) -> Value?) -> Rule<Value> {
    Rule(pattern: persian(pattern), read: read)
  }

  /// Whether `pattern`, written in natural spelling, matches somewhere in
  /// `text`, which is in the reading form without vowel signs.
  static func persianFinds(_ pattern: String, in text: String) -> Bool {
    guard let regex = LorvexCapturePatterns.regex(persian(pattern, readsMarks: false)) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - Boundaries and words around a detail

  /// A word boundary for words written in Perso-Arabic letters: no Arabic
  /// letter, vowel sign, digit, tatweel, or joiner on that side, so a word is
  /// never cut out of a longer one, and a zero-width non-joiner (which a
  /// Persian word writes before its suffixes: "می‌روم", "هفته‌ها") keeps the
  /// parts of a word together.
  static let persianStart = #"(?<![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}])"#
  static let persianEnd = #"(?![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}])"#

  /// What may follow a clock time: no Arabic letter, vowel sign, digit, joiner,
  /// or colon (the word or the number goes on), no decimal fraction, no percent
  /// or currency sign with or without a space before it (the number is an
  /// amount), no dash before a digit, which makes the time one side of a range
  /// written with a dash ("14:00-16:00"), and no AM or PM after it.
  static let persianTimeEnd =
    #"(?![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}:]|[.,]\p{N}|\s*[%\p{Sc}]|\s*[-–—]\s*\d)\#(noMeridiemAfter)"#

  /// What may follow a date: no Arabic letter, vowel sign, digit, joiner, or
  /// colon, and no decimal fraction.
  static let persianDateEnd = #"(?![\p{Arabic}\p{M}\p{N}\x{0640}\x{200C}\x{200D}:]|[.,]\p{N})"#

  /// What may follow a day of the month written alone: no digit or percent
  /// sign, and no decimal fraction or time. The colon goes last in its set,
  /// since ICU reads a set that opens with "[:" as a POSIX class name.
  static let persianNoMoreDigits = #"(?![\p{N}%]|[.,:]\p{N})"#

  /// The text before `match`, as a reader compares it: in the reading form
  /// without vowel signs.
  static func persianTextBefore(_ match: Match) -> String {
    guard let start = Range(match.result.range, in: match.source)?.lowerBound else { return "" }
    return persianBare(String(match.source[..<start]))
  }

  /// The text after `match`, as a reader compares it.
  static func persianTextAfter(_ match: Match) -> String {
    guard let end = Range(match.result.range, in: match.source)?.upperBound else { return "" }
    return persianBare(String(match.source[end...]))
  }

  // MARK: - Counts

  /// The number words one to twelve in the spellings people type, which stand
  /// before a counted noun ("سه روز", "دو ساعت") and name an hour after
  /// "ساعت"; "یه" and "شیش" are the spoken forms.
  private static let persianHourCountSpellings: [(value: Int, words: [String])] = [
    (1, ["یک", "یه"]), (2, ["دو"]), (3, ["سه"]), (4, ["چهار"]), (5, ["پنج"]), (6, ["شش", "شیش"]), (7, ["هفت"]),
    (8, ["هشت"]), (9, ["نه"]), (10, ["ده"]), (11, ["یازده"]), (12, ["دوازده"]),
  ]

  /// The round counts that name minutes or days, besides the ones above, in
  /// the spellings people type; a count of two words ("چهل و پنج") has its
  /// words separated by a space.
  private static let persianRoundCountSpellings: [(value: Int, words: [String])] = [
    (15, ["پانزده"]), (20, ["بیست"]), (25, ["بیست و پنج"]), (30, ["سی"]), (35, ["سی و پنج"]), (40, ["چهل"]),
    (45, ["چهل و پنج"]), (50, ["پنجاه"]), (55, ["پنجاه و پنج"]),
  ]

  /// The counts keyed as ``persianKey(_:)`` leaves them: one to twelve, and
  /// with the round counts.
  static let persianHourCounts: [String: Int] = persianCountIndex(persianHourCountSpellings)
  static let persianCounts: [String: Int] = persianCountIndex(persianHourCountSpellings + persianRoundCountSpellings)

  private static func persianCountIndex(_ spellings: [(value: Int, words: [String])]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for (value, words) in spellings {
      for word in words { counts[persianKey(persianForMatching(word))] = value }
    }
    return counts
  }

  /// The count words as a pattern, longest first, with a space inside a
  /// two-word count as `\s+`.
  private static func persianCountPattern(_ spellings: [(value: Int, words: [String])]) -> String {
    alternation(of: spellings.flatMap { $0.words }.map { $0.replacingOccurrences(of: " ", with: #"\s+"#) })
  }

  /// One to twelve in words, as a pattern.
  static var persianHourCountWords: String { persianCountPattern(persianHourCountSpellings) }

  /// One to twelve and the round counts in words, as a pattern.
  static var persianCountWords: String {
    persianCountPattern(persianHourCountSpellings + persianRoundCountSpellings)
  }

  /// The hours a clock can name in words after "ساعت": one to twelve.
  static var persianClockHourWords: String {
    alternation(of: ["یک", "دو", "سه", "چهار", "پنج", "شش", "شیش", "هفت", "هشت", "نه", "ده", "یازده", "دوازده"])
  }

  // MARK: - Priority

  /// Group 1: a written priority, "اولویت" with its level after it ("اولویت
  /// بالا", "اولویت: پایین"), maybe after "با" ("با اولویت بالا"); "فوری" has
  /// no group.
  private static var persianPriorityPattern: String {
    let level =
      #"بسیار\s+بالا|خیلی\s+بالا|بالا|زیاد|متوسط|معمولی|نرمال|بسیار\s+پایین|خیلی\s+پایین|پایین|کمتر|کم"#
    return
      #"\#(persianStart)((?:با\s+)?اولویت\s*:?\s*(?:\#(level)))\#(persianEnd)|(?<=\s)(?:(?:خیلی|بسیار)\s+)?فوری(?=\s*\.?\s*$)|^\s*فوری(?=\s*[:：،,])"#
  }

  private static func persianPriority(_ match: Match) -> LorvexTask.Priority? {
    guard let phrase = match.group(1).map(persianPhrase) else { return .p1 }
    if ["متوسط", "معمولی", "نرمال"].contains(where: phrase.contains) { return .p2 }
    if ["پایین", "کم"].contains(where: phrase.contains) { return .p3 }
    return .p1
  }

  // MARK: - Length

  /// "20 دقیقه", "۲ ساعت", "۱٫۵ ساعت", "۲ ساعت و ۳۰ دقیقه", "نیم ساعت", "ربع
  /// ساعت", "یک ربع", "سه ربع", "یک ساعت و نیم", "دو و نیم ساعت", "پنج دقیقه",
  /// "جلسه ۲ ساعته", "۳۰ دقیقه‌ای", each maybe after "به مدت", "مدت", "حدود",
  /// "تقریباً", or "برای". Groups: 1 a word that opens a length; 2 a word that
  /// makes the amount a moment, an interval, a rate, or a bound ("بعد از ۱۵
  /// دقیقه", "هر ۲ ساعت", "روزی ۲ ساعت", "تا ۲ ساعت"); 3 a length in words
  /// (with a count in digits or in words, a fraction, or minutes after the
  /// hours); 4 the hours of an amount in digits with a unit and 5 its minutes;
  /// 6 minutes in digits; 7 a word after the amount that makes it a moment, the
  /// past, or a rate ("۱۰ دقیقه دیگر", "۲ ساعت پیش", "۲ ساعت در روز"). A
  /// match with group 2 or 7 is no length: ``persianLength(_:)`` declines it
  /// and a keep rule claims it. The amount may not follow a digit, a colon, a
  /// separator, or the "و" of a clock time ("ساعت ۵ و ۱۰ دقیقه"), it may not
  /// be a side of a range ("۲-۳ ساعت"), and an amount of minutes before "به"
  /// and an hour ("ده دقیقه به ۶") or before "کم" is a clock time, which the
  /// time rules read.
  static var persianLengthPattern: String {
    let approximate = #"به\s+مدت|مدت|در\s+حدود|حدودا|حدود|تقریبا|نزدیک(?:\s+به)?|برای"#
    let declining =
      #"بعد\s+از|پس\s+از|قبل\s+از|پیش\s+از|بیش\s+از|بیشتر\s+از|کمتر\s+از|حداقل|حداکثر|هر\s+(?:روز|هفته|ماه|سال)|هر|تا|طی|ظرف|در|از|بالای|زیر|روزی|هفته‌ای|ماهی|سالی"#
    let opener = #"(?:(\#(approximate))\s+|(\#(declining))\s+)?"#
    let boundaries = #"(?<![\p{N}:.,])(?<!\p{N}\s?[-–—]\s?)(?<![و]\s{1,3})"#
    let hours =
      #"(\d+(?:[.,]\d+)?)\s*(?:ساعته|ساعتی|ساعت)(?:(?:\s*و\s*|\s+)(\d{1,2})\s*دقیقه(?:‌ای)?)?"#
    let minutes = #"(\d+)\s*دقیقه(?:‌ای)?"#
    let hourCount = #"(?:\d{1,2}|\#(persianHourCountWords))"#
    let words =
      #"(نیم‌ساعت|ربع‌ساعت|(?:یک|یه)\s+ربع(?:\s+ساعت)?|سه\s+ربع(?:\s+ساعت)?|\#(hourCount)\s+ساعت\s+و\s+(?:نیم|(?:یک\s+)?ربع|(?:\d{1,2}|\#(persianCountWords))\s*دقیقه)|\#(hourCount)\s+و\s+(?:نیم|ربع)\s+ساعت|(?:\#(persianHourCountWords))\s+ساعت|(?:\#(persianCountWords))\s+دقیقه)"#
    let clockTail =
      #"(?!\s+(?:کم|مانده)\#(persianEnd)|\s+به\s+(?:ساعت\s+)?(?:\d|(?:\#(persianClockHourWords))\#(persianEnd)))"#
    let trailing =
      #"(?:\s+(بعد(?:\s+از)?|پس(?:\s+از)?|قبل(?:\s+از)?|پیش(?:\s+از)?|دیگر|دیگه|باقی|(?:در|توی|تو|طی)\s+(?:یک\s+)?(?:روز|هفته|ماه|سال)|(?:هر|هر\s+یک)\s+(?:روز|هفته|ماه|سال)|روزانه|هفتگی|ماهانه|سالانه)\#(persianEnd))?"#
    return
      #"\#(persianStart)\#(opener)\#(boundaries)(?:\#(words)|\#(hours)|\#(minutes))\#(persianEnd)(?!\s*[-–—]\s*\d|\s+(?:تا|الی)\s+\d)\#(clockTail)\#(trailing)"#
  }

  /// True for a match that is no length: a moment, an interval, a rate, or a
  /// bound ("بعد از ۱۵ دقیقه", "هر ۲ ساعت", "روزی ۲ ساعت", "تا ۲ ساعت"), or the
  /// past ("۲ ساعت پیش").
  private static func persianDeclinesLength(_ match: Match) -> Bool {
    match.group(2) != nil || match.group(7) != nil
  }

  private static func persianLength(_ match: Match) -> Int? {
    if persianDeclinesLength(match) { return nil }
    if let phrase = match.group(3).map(persianPhrase) {
      return persianWordsLength(phrase.split(separator: " ").map(String.init))
    }
    if let hours = match.group(4).flatMap(decimalAmount) {
      return taskLength(minutes: Int((hours * 60).rounded()) + (match.group(5).flatMap(number) ?? 0))
    }
    return match.group(6).flatMap(number).flatMap { taskLength(minutes: $0) }
  }

  /// The minutes a length in words names: "نیم ساعت", "ربع ساعت", "یک ربع",
  /// "سه ربع", "دو ساعت", "یک ساعت و نیم", "دو و نیم ساعت", "ده دقیقه".
  private static func persianWordsLength(_ tokens: [String]) -> Int? {
    switch tokens {
    case ["نیم", "ساعت"], ["نیمساعت"]: return 30
    case ["ربع", "ساعت"], ["ربعساعت"]: return 15
    case ["یک", "ربع"], ["یه", "ربع"], ["یک", "ربع", "ساعت"], ["یه", "ربع", "ساعت"]: return 15
    case ["سه", "ربع"], ["سه", "ربع", "ساعت"]: return 45
    default: break
    }
    guard let (count, rest) = persianLeadingCount(tokens) else { return nil }
    let tail = Array(rest)
    func fraction(_ words: [String]) -> Int? {
      switch words {
      case ["نیم"]: 30
      case ["ربع"], ["یک", "ربع"]: 15
      default: nil
      }
    }
    switch tail.first {
    case "دقیقه":
      return tail.count == 1 ? taskLength(minutes: count) : nil
    case "ساعت":
      if tail.count == 1 { return taskLength(minutes: count * 60) }
      guard tail[1] == "و" else { return nil }
      let more = Array(tail.dropFirst(2))
      if let minutes = fraction(more) { return taskLength(minutes: count * 60 + minutes) }
      if more.count == 2, more[1] == "دقیقه", let minutes = number(more[0]) ?? persianCounts[more[0]] {
        return taskLength(minutes: count * 60 + minutes)
      }
      if more.count >= 3, more.last == "دقیقه", let (minutes, left) = persianLeadingCount(Array(more)),
        left.count == 1
      {
        return taskLength(minutes: count * 60 + minutes)
      }
      return nil
    case "و":
      guard tail.count >= 3, tail.last == "ساعت", let minutes = fraction(Array(tail.dropFirst().dropLast())) else {
        return nil
      }
      return taskLength(minutes: count * 60 + minutes)
    default:
      return nil
    }
  }
}
