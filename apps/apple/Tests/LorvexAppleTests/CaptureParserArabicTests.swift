import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ar"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["ar"])
}

/// `text` with its digits written in the Arabic-Indic (`offset` 0x0660) or the
/// Extended Arabic-Indic (`offset` 0x06F0) script.
private func digits(_ text: String, from offset: UInt32) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in text.unicodeScalars {
    if (0x30...0x39).contains(scalar.value), let digit = Unicode.Scalar(offset + scalar.value - 0x30) {
      scalars.append(digit)
    } else {
      scalars.append(scalar)
    }
  }
  return String(scalars)
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])

/// Arabic capture lines, read for a user whose languages include Arabic.
@Suite("Capture parser Arabic")
struct CaptureParserArabicTests {
  @Test("Days: today, tomorrow, the day after, and a number of days or weeks")
  func days() {
    let line = parse("اتصل بأمي غداً")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "اتصل بأمي")
    #expect(line.phrases.map(\.text) == ["غداً"])

    let days: [(text: String, offset: Int)] = [
      ("زيارة الطبيب اليوم", 0), ("زيارة الطبيب الليلة", 0), ("زيارة الطبيب هذه الليلة", 0),
      ("زيارة الطبيب هذا الصباح", 0), ("زيارة الطبيب هذا المساء", 0),
      ("زيارة الطبيب غدا", 1), ("زيارة الطبيب غدًا", 1), ("زيارة الطبيب غَدًا", 1), ("زيارة الطبيب غــداً", 1),
      ("زيارة الطبيب بكرة", 1), ("زيارة الطبيب بكرا", 1),
      ("زيارة الطبيب بعد غد", 2), ("زيارة الطبيب بعد غدٍ", 2), ("زيارة الطبيب بعد بكرة", 2),
      ("زيارة الطبيب بعد 3 أيام", 3), ("زيارة الطبيب بعد ٣ أيام", 3), ("زيارة الطبيب بعد ۳ أيام", 3),
      ("زيارة الطبيب بعد ثلاثة أيام", 3), ("زيارة الطبيب بعد 10 أيام", 10), ("زيارة الطبيب بعد عشرة أيام", 10),
      ("زيارة الطبيب بعد 15 يوماً", 15), ("زيارة الطبيب بعد يومين", 2), ("زيارة الطبيب بعد يوم واحد", 1),
      ("زيارة الطبيب بعد أسبوع", 7), ("زيارة الطبيب بعد أسبوع واحد", 7), ("زيارة الطبيب بعد أسبوعين", 14),
      ("زيارة الطبيب بعد 3 أسابيع", 21), ("زيارة الطبيب بعد ثلاثة أسابيع", 21),
      ("زيارة الطبيب بعد أسبوع من الآن", 7), ("زيارة الطبيب بعد 3 أيام من الآن", 3),
      ("زيارة الطبيب الأسبوع القادم", 7), ("زيارة الطبيب في الأسبوع المقبل", 7),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.title == "زيارة الطبيب", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("غداً اتصل بأمي")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "اتصل بأمي")
  }

  @Test("A part of the day after a day is read with it and sets a bare hour")
  func partsOfDay() {
    let morning = parse("اتصل بأمي غداً صباحاً")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == nil)
    #expect(morning.title == "اتصل بأمي")
    #expect(morning.phrases.map(\.text) == ["غداً صباحاً"])
    #expect(parse("عشاء اليوم مساءً").plannedDayOffset == 0)
    #expect(parse("عشاء غداً بعد الظهر").plannedDayOffset == 1)
    #expect(parse("عشاء بكرة الصبح").plannedDayOffset == 1)

    // An evening or a night names a bare hour's evening or night.
    let dinner = parse("عشاء الليلة الساعة 8")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "عشاء")
    #expect(parse("عشاء هذا المساء الساعة 7").startMinutes == 19 * 60)
    #expect(parse("عشاء غداً مساءً الساعة 8").startMinutes == 20 * 60)
    #expect(parse("عشاء غداً مساءً الساعة 8").plannedDayOffset == 1)
    let late = parse("عشاء الليلة الساعة 2")
    #expect(late.startMinutes == 2 * 60)
    #expect(late.plannedDayOffset == 1)

    // A part of the day beside the day phrase names a bare hour's half of the
    // day, whatever the hour: 6 in the morning is not 6 in the evening, and 4
    // in the evening is not 4 at night.
    let beside: [(text: String, planned: Int, minutes: Int)] = [
      ("اجتماع غداً صباحاً الساعة 6", 1, 6 * 60),
      ("اجتماع غداً صباحاً الساعة 9", 1, 9 * 60),
      ("اجتماع هذا الصباح الساعة 6", 0, 6 * 60),
      ("اجتماع غداً مساءً الساعة 4", 1, 16 * 60),
      ("اجتماع هذا المساء الساعة 5", 0, 17 * 60),
      ("اجتماع مساء الخميس الساعة 8", 2, 20 * 60),
      ("اجتماع مساء الخميس الساعة 4", 2, 16 * 60),
      ("اجتماع فجر الخميس الساعة 5", 2, 5 * 60),
      ("اجتماع صباح الأحد الساعة 10", 5, 10 * 60),
      ("اجتماع غداً ليلاً الساعة 10", 1, 22 * 60),
      // The part of the day after the hour, before a weekday it opens, is the
      // weekday's: the day phrase takes it.
      ("اجتماع الساعة 5 مساء الخميس", 2, 17 * 60),
      ("اجتماع الساعة 8 مساء الخميس", 2, 20 * 60),
      ("اجتماع الساعة 5 مساءً يوم الخميس", 2, 17 * 60),
    ]
    for line in beside {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): start")
      #expect(parsed.title == "اجتماع", "\(line.text): title")
    }
    // A night past midnight moves the day.
    #expect(parse("اجتماع غداً ليلاً الساعة 2").plannedDayOffset == 2)
    #expect(parse("اجتماع غداً ليلاً الساعة 2").startMinutes == 2 * 60)
    // A part of the day in a prayer's name sets the hour beside it.
    let prayer = parse("صلاة الفجر الساعة 5")
    #expect(prayer.startMinutes == 5 * 60)
    #expect(prayer.title == "صلاة الفجر")
    // The part of the day as a noun names no day.
    expectLinesUnread(["اجتماع مساءً", "اجتماع في الصباح", "قهوة الصباح", "اجتماع بعد الظهر"], languages: ["ar"])
  }

  @Test("Weekdays: the next one, this week's, the coming one, and one after a part of the day")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      // Today is Tuesday, so a bare Tuesday is a week ahead and "هذا الثلاثاء" is today.
      ("اجتماع يوم الجمعة", 3), ("اجتماع يوم السبت", 4), ("اجتماع يوم الأحد", 5), ("اجتماع يوم الاثنين", 6),
      ("اجتماع يوم الثلاثاء", 7), ("اجتماع يوم الأربعاء", 1), ("اجتماع يوم الخميس", 2),
      ("اجتماع في يوم الخميس", 2), ("اجتماع ليوم الخميس", 2), ("اجتماع في الخميس", 2),
      ("اجتماع هذا الخميس", 2), ("اجتماع هذا الثلاثاء", 0), ("اجتماع هذه الجمعة", 3), ("اجتماع هذا السبت", 4),
      ("اجتماع الخميس القادم", 2), ("اجتماع الجمعة المقبلة", 3), ("اجتماع الاثنين القادم", 6),
      ("اجتماع يوم الخميس القادم", 2), ("اجتماع الثلاثاء القادم", 7), ("اجتماع الجمعة الجاية", 3),
      ("اجتماع الجمعة التالية", 3), ("اجتماع مساء الخميس", 2), ("اجتماع صباح الاثنين", 6),
      ("اجتماع مساء يوم الخميس", 2), ("اجتماع يوم الخميس مساءً", 2), ("اجتماع الخميس القادم صباحاً", 2),
      // The names as they are spelled with and without hamza, teh marbuta, and vowel signs.
      ("اجتماع يوم الإثنين", 6), ("اجتماع يوم الاتنين", 6), ("اجتماع يوم الاحد", 5), ("اجتماع يوم الأَحَد", 5),
      ("اجتماع يوم الجُمعة", 3), ("اجتماع يوم الجمعه", 3), ("اجتماع يوم الثلاثا", 7), ("اجتماع يوم الاربعاء", 1),
      ("اجتماع يوم الاربعا", 1), ("اجتماع يوم ٱلسبت", 4),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "اجتماع", "\(weekday.text): title")
    }
    // Today is a Thursday: a bare Thursday is a week ahead, "هذا الخميس" is today, and the coming Thursday is next week's.
    for (text, offset) in [
      ("اجتماع يوم الخميس", 7), ("اجتماع هذا الخميس", 0), ("اجتماع الخميس القادم", 7), ("اجتماع يوم الجمعة", 1),
    ] {
      #expect(parse(text, weekday: 5, today: "2026-09-24").plannedDayOffset == offset, "Thursday: \(text)")
    }
    // Friday and Sunday.
    #expect(parse("اجتماع يوم الجمعة", weekday: 6, today: "2026-09-25").plannedDayOffset == 7)
    #expect(parse("اجتماع هذا الجمعة", weekday: 6, today: "2026-09-25").plannedDayOffset == 0)
    #expect(parse("اجتماع يوم الأحد", weekday: 1, today: "2026-09-27").plannedDayOffset == 7)
    #expect(parse("اجتماع الأحد القادم", weekday: 1, today: "2026-09-27").plannedDayOffset == 7)
    #expect(parse("اجتماع هذا الأحد", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    let opening = parse("يوم الخميس اتصل بأمي")
    #expect(opening.plannedDayOffset == 2)
    #expect(opening.title == "اتصل بأمي")
  }

  @Test("A weekday alone, in the past, or as a night is no day; Sunday needs its article")
  func weekdaysAlone() {
    expectLinesUnread(
      [
        // A weekday alone is a noun or a name.
        "اجتماع الخميس", "صلاة الجمعة", "الجمعة العظيمة", "اجتماع الجمعة العظيمة", "خطبة الجمعة", "اجتماع الاثنين والخميس",
        "الخميس اجتماع", "اجتماع الأحد",
        // The past, and the night before a day.
        "اجتماع الخميس الماضي", "اجتماع يوم الخميس الماضي", "اجتماع الجمعة الماضية", "اجتماع ليلة الجمعة",
        "اجتماع ليلة الجمعة القادمة",
        // "أحد" without its article is "someone" or the battle of Uhud.
        "اجتماع يوم أحد", "اجتماع كل أحد", "اجتماع كل يوم أحد", "مراجعة اثنين",
        // A day after a bound is no planned day.
        "تقرير بعد الخميس", "تقرير منذ الخميس",
      ], languages: ["ar"])
    // A weekday that opens a line with a day phrase reads, and so does one beside a day.
    let both = parse("صلاة الجمعة يوم الجمعة")
    #expect(both.plannedDayOffset == 3)
    #expect(both.title == "صلاة الجمعة")
    let prayer = parse("خطبة الجمعة غداً")
    #expect(prayer.plannedDayOffset == 1)
    #expect(prayer.title == "خطبة الجمعة")
    // A second weekday that no word opens stays in the title.
    let pair = parse("تمرين يوم الجمعة والسبت")
    #expect(pair.plannedDayOffset == 3)
    #expect(pair.title == "تمرين والسبت")
  }

  @Test("Written dates, with a year, three sets of month names, and either digit script")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("زيارة 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة 5 من مارس", "زيارة", "2027-03-05"),
      ("زيارة 5 من شهر مارس", "زيارة", "2027-03-05"),
      ("زيارة في 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة يوم 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة في يوم 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة بتاريخ 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة من 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة ليوم 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة لـ 5 مارس", "زيارة", "2027-03-05"),
      ("زيارة ل5 مارس", "زيارة", "2027-03-05"),
      ("زيارة 5 مارس 2027", "زيارة", "2027-03-05"),
      ("زيارة 5 مارس 2027م", "زيارة", "2027-03-05"),
      ("زيارة 5 مارس 2028", "زيارة", "2028-03-05"),
      ("زيارة في 5 مارس 2027", "زيارة", "2027-03-05"),
      ("زيارة 5 يناير", "زيارة", "2027-01-05"),
      ("زيارة 5 كانون الثاني", "زيارة", "2027-01-05"),
      ("زيارة 5 جانفي", "زيارة", "2027-01-05"),
      ("زيارة 12 ديسمبر", "زيارة", "2026-12-12"),
      ("زيارة 12 كانون الأول", "زيارة", "2026-12-12"),
      ("زيارة 5 تشرين الأول", "زيارة", "2026-10-05"),
      ("زيارة 5 أكتوبر", "زيارة", "2026-10-05"),
      ("زيارة 5 اكتوبر", "زيارة", "2026-10-05"),
      ("زيارة 5 أيار", "زيارة", "2027-05-05"),
      ("زيارة 5 ماي", "زيارة", "2027-05-05"),
      ("زيارة 5 آب", "زيارة", "2027-08-05"),
      ("زيارة 5 سبتمبر", "زيارة", "2027-09-05"),
      ("زيارة ٥ مارس", "زيارة", "2027-03-05"),
      ("زيارة ۵ مارس", "زيارة", "2027-03-05"),
      ("زيارة في ٥ مارس ٢٠٢٧", "زيارة", "2027-03-05"),
      ("زيارة 5 مارس تحت", "زيارة تحت", "2027-03-05"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A month needs a day number ("مارس" is also a verb), a date in digits is
    // not read, a day the month does not have names no date, and neither does a
    // Hijri date or a day in words.
    expectLinesUnread(
      [
        "مارس الرياضة", "زيارة مارس", "زيارة 5/3", "زيارة 5-3", "زيارة 31 أبريل", "زيارة 31 فبراير",
        "زيارة 29 فبراير 2027", "مراجعة 3 رمضان", "زيارة 10 محرم", "زيارة في الخامس من مارس",
      ], languages: ["ar"])
    // A date after a word that sets it against something else is no planned day.
    expectLinesUnread(["تقرير إلى 5 مارس"], languages: ["ar"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("إجازة", "من 3 إلى 5 مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 3 إلى 5 من مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 30 يناير إلى 2 فبراير", "2027-01-30", "2027-02-02"),
        ("إجازة", "من 3 مارس حتى 5 مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 3 مارس إلى 5 أبريل", "2027-03-03", "2027-04-05"),
        ("إجازة", "بين 3 و5 مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "3-5 مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "3–5 مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 3 إلى 5 مارس 2027", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 3 مارس 2027 إلى 5 مارس 2027", "2027-03-03", "2027-03-05"),
        ("إجازة", "من ٣ إلى ٥ مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من ۳ إلى ۵ مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 3 إلى 5 كانون الثاني", "2027-01-03", "2027-01-05"),
        ("إجازة على البحر", "من 3 إلى 5 مارس", "2027-03-03", "2027-03-05"),
        ("إجازة", "من 25 سبتمبر إلى 3 أكتوبر", "2026-09-25", "2026-10-03"),
        ("إجازة", "من 30 ديسمبر إلى 2 يناير", "2026-12-30", "2027-01-02"),
      ], languages: ["ar"])
    // A range takes both days, so another day phrase stays in the title.
    let line = parse("إجازة من 3 إلى 5 مارس غداً")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "إجازة غداً")
  }

  @Test("A day alone opens a range joined by a spaced dash only after an opening word")
  func spacedDashAfterLoneDay() {
    // A spaced dash after a number sets the number apart as part of the title,
    // and the date after it is read alone.
    let sprint = parse("سباق 12 - 20 مارس")
    #expect(sprint.title == "سباق 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    // A dash that touches both sides, or an opening word, makes it a range.
    expectDateRanges(
      [
        ("رحلة", "12-20 مارس", "2027-03-12", "2027-03-20"),
        ("رحلة", "من 12 - 20 مارس", "2027-03-12", "2027-03-20"),
      ], languages: ["ar"])
  }

  @Test("A range whose end is not after its start, or whose joining word is wrong, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "إجازة من 5 إلى 3 مارس", "إجازة من 3 مارس إلى 3 مارس", "إجازة من 5 مارس إلى 3 مارس", "إجازة من 3 و5 مارس",
        "إجازة 3 إلى 5 مارس", "إجازة بين 3 إلى 5 مارس",
        // Days of the month with no month are no range.
        "إجازة من 3 إلى 5", "إجازة بين 3 و5",
      ], languages: ["ar"])
  }

  @Test("Due days: قبل, حتى, بحلول, لغاية, and a deadline label")
  func dueDays() {
    let due: [(text: String, offset: Int)] = [
      ("تقرير قبل الخميس", 2), ("تقرير قبل يوم الخميس", 2), ("تقرير حتى الخميس", 2), ("تقرير بحلول الخميس", 2),
      ("تقرير بحلول يوم الخميس", 2), ("تقرير لغاية الخميس", 2), ("تقرير لغاية الخميس القادم", 2),
      ("تقرير قبل الثلاثاء", 7), ("تقرير قبل يوم الأحد", 5), ("تقرير قبل الأحد", 5),
      ("تقرير قبل غداً", 1), ("تقرير حتى غداً", 1), ("تقرير بحلول غدا", 1), ("تقرير قبل بعد غد", 2),
      ("تقرير قبل نهاية اليوم", 0), ("تقرير قبل 5 مارس", captureDayOffset("2027-03-05")),
      ("تقرير بحلول 5 مارس", captureDayOffset("2027-03-05")),
      ("تقرير بحلول ٥ مارس", captureDayOffset("2027-03-05")),
      ("تقرير الموعد النهائي: الخميس", 2), ("تقرير الموعد النهائي الخميس", 2),
      ("تقرير موعد التسليم 5 مارس", captureDayOffset("2027-03-05")),
      ("تقرير في موعد أقصاه الخميس", 2), ("تقرير آخر موعد الخميس", 2),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "تقرير", "\(line.text): title")
    }
    let both = parse("تقرير قبل الخميس غداً")
    #expect(both.dueDayOffset == 2)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "تقرير")
    // The weekday is the due day itself, with the name of the day spelled either way.
    #expect(parse("تقرير قبل الاربعاء").dueDayOffset == 1)
    #expect(parse("تقرير قبل الإثنين").dueDayOffset == 6)
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "تقرير قبل الساعة 18:00", "تقرير حتى الساعة 18:00", "تقرير بحلول 18:00", "تقرير حتى 18:00", "تقرير قبل 18:00",
        "تقرير بعد الساعة 5:30", "تقرير قبل الساعة 5", "تقرير حتى الساعة 5", "تقرير بعد الساعة 5",
        "تقرير قبل الساعة 5 مساءً", "تقرير لغاية الساعة 5", "تقرير قبل الساعة ١٨:٠٠",
      ], languages: ["ar"])
    let day = parse("تقرير قبل الساعة 18:00 غداً")
    #expect(day.title == "تقرير قبل الساعة 18:00")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    // A time range that ends in a clock time is still a range.
    let range = parse("اجتماع من 14 إلى 18:00")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 240)
    #expect(range.title == "اجتماع")
    // Without Arabic, English reads the clock time and leaves the word.
    let english = parse("تقرير حتى 18:00", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "تقرير حتى")
  }

  @Test("Clock times: الساعة, a part of the day, a letter, a fraction of the hour, noon, and midnight")
  func times() {
    let times: [(text: String, minutes: Int)] = [
      ("اجتماع الساعة 15:00", 15 * 60), ("اجتماع الساعة 15:30", 15 * 60 + 30), ("اجتماع الساعة 3", 15 * 60),
      ("اجتماع الساعة 3:30", 15 * 60 + 30), ("اجتماع في الساعة 3", 15 * 60), ("اجتماع عند الساعة 9 صباحاً", 9 * 60),
      ("اجتماع ع الساعة 5", 17 * 60), ("اجتماع في تمام الساعة 5", 17 * 60), ("اجتماع حوالي الساعة 5", 17 * 60),
      ("اجتماع على الساعة 5", 17 * 60),
      ("اجتماع الساعة 3 مساءً", 15 * 60), ("اجتماع الساعة 3:30 مساءً", 15 * 60 + 30),
      ("اجتماع الساعة 9 صباحاً", 9 * 60), ("اجتماع الساعة 9 صباحا", 9 * 60), ("اجتماع الساعه 9 صباحا", 9 * 60),
      ("اجتماع السّاعة ٩ صَباحاً", 9 * 60), ("اجتماع الســاعة 9 صباحاً", 9 * 60), ("اجتماع الساعة 8 الصبح", 8 * 60),
      ("اجتماع الساعة 3 العصر", 15 * 60), ("اجتماع الساعة 3 عصراً", 15 * 60), ("اجتماع الساعة 3 بعد الظهر", 15 * 60),
      ("اجتماع الساعة 8 بالليل", 20 * 60), ("اجتماع الساعة 8 في المساء", 20 * 60),
      ("اجتماع الساعة 8 الليل", 20 * 60), ("اجتماع الساعة 8 مساءا", 20 * 60), ("اجتماع الساعة 5 فجراً", 5 * 60),
      ("اجتماع 8 مساءً", 20 * 60), ("اجتماع 8:30 مساءً", 20 * 60 + 30), ("اجتماع في 8 مساءً", 20 * 60),
      ("اجتماع 3:30 عصراً", 15 * 60 + 30), ("اجتماع 9 صباحاً", 9 * 60), ("اجتماع 9 الصبح", 9 * 60),
      ("اجتماع الساعة 3 م", 15 * 60), ("اجتماع الساعة 3:30 ص", 3 * 60 + 30), ("اجتماع 3:30 م", 15 * 60 + 30),
      ("اجتماع 3:30 ص", 3 * 60 + 30), ("اجتماع الساعة 12 ظهراً", 12 * 60), ("اجتماع الساعة 1 ظهراً", 13 * 60),
      ("اجتماع الساعة 9 ليلاً", 21 * 60), ("اجتماع الساعة 11 ليلاً", 23 * 60),
      ("اجتماع الساعة 3 ونصف", 15 * 60 + 30), ("اجتماع في الساعة 3 ونصف", 15 * 60 + 30),
      ("اجتماع الساعة 3 ونصف مساءً", 15 * 60 + 30), ("اجتماع الساعة 3 وربع", 15 * 60 + 15),
      ("اجتماع الساعة 3 وثلث", 15 * 60 + 20), ("اجتماع الساعة 3 إلا ربع", 14 * 60 + 45),
      ("اجتماع الساعة 3 إلا ثلث", 14 * 60 + 40), ("اجتماع الساعة 9 إلا ربع صباحاً", 8 * 60 + 45),
      ("اجتماع الساعة ٣:٣٠ مساءً", 15 * 60 + 30), ("اجتماع الساعة ۳ مساءً", 15 * 60),
      ("اجتماع الساعة ١٥:٣٠", 15 * 60 + 30), ("اجتماع الساعة ۱۵:۳۰", 15 * 60 + 30),
      ("اجتماع عند منتصف النهار", 12 * 60), ("اجتماع في منتصف النهار", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "اجتماع", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A time and its day, in either order.
    let dayFirst = parse("مكالمة يوم الأحد الساعة 10 صباحاً")
    #expect(dayFirst.plannedDayOffset == 5)
    #expect(dayFirst.startMinutes == 10 * 60)
    #expect(dayFirst.title == "مكالمة")
    let timeFirst = parse("مكالمة الساعة 10 صباحاً يوم الأحد")
    #expect(timeFirst.plannedDayOffset == 5)
    #expect(timeFirst.startMinutes == 10 * 60)
    #expect(timeFirst.title == "مكالمة")
    // The time opens the line.
    let opening = parse("عند الساعة 9 صباحاً اجتماع")
    #expect(opening.startMinutes == 9 * 60)
    #expect(opening.title == "اجتماع")
  }

  @Test("After midnight: ليلاً runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("اجتماع الساعة 2 ليلاً")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "اجتماع")
    let midnight = parse("اجتماع في منتصف الليل")
    #expect(midnight.startMinutes == 0)
    #expect(midnight.plannedDayOffset == 1)
    let twelve = parse("اجتماع الساعة 12 ليلاً")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    let atMidnight = parse("اجتماع عند منتصف الليل")
    #expect(atMidnight.startMinutes == 0)
    #expect(atMidnight.plannedDayOffset == 1)
    // A named day keeps the time on its own night.
    let named = parse("اجتماع يوم الجمعة الساعة 2 ليلاً")
    #expect(named.startMinutes == 2 * 60)
    #expect(named.plannedDayOffset == 4)
    // Noon at 12 in the day; 12 in the morning or the evening is no time.
    expectLinesUnread(["اجتماع الساعة 12 صباحاً", "اجتماع الساعة 12 مساءً"], languages: ["ar"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("اجتماع الساعة 3").startMinutes == 15 * 60)
    #expect(parse("اجتماع الساعة 6").startMinutes == 18 * 60)
    #expect(parse("اجتماع الساعة 7").startMinutes == 7 * 60)
    #expect(parse("اجتماع الساعة 9").startMinutes == 9 * 60)
    #expect(parse("اجتماع الساعة 12").startMinutes == 12 * 60)
    #expect(parse("اجتماع الساعة 06:30").startMinutes == 6 * 60 + 30)
    #expect(parse("اجتماع الساعة 03:00").startMinutes == 3 * 60)
    #expect(parse("اجتماع الساعة 3:00").startMinutes == 15 * 60)
    #expect(parse("اجتماع الساعة 13:00").startMinutes == 13 * 60)
    expectLinesUnread(["اجتماع الساعة 24:00", "اجتماع الساعة 25", "اجتماع الساعة 7:61"], languages: ["ar"])
  }

  @Test("Time ranges: من with إلى or حتى, بين with و, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("اجتماع من الساعة 2 إلى 4", 14 * 60, 120),
      ("اجتماع من الساعة 2 حتى 4", 14 * 60, 120),
      ("اجتماع من الساعة 9 صباحاً إلى 5 مساءً", 9 * 60, 480),
      ("اجتماع من الساعة 9 صباحاً حتى 5 مساءً", 9 * 60, 480),
      ("اجتماع من 9 صباحاً إلى 5 مساءً", 9 * 60, 480),
      ("اجتماع من 2 إلى 4 مساءً", 14 * 60, 120),
      ("اجتماع من 14:00 إلى 16:00", 14 * 60, 120),
      ("اجتماع من ١٤:٠٠ إلى ١٦:٠٠", 14 * 60, 120),
      ("اجتماع من 9 ص إلى 5 م", 9 * 60, 480),
      ("اجتماع بين الساعة 2 و4", 14 * 60, 120),
      ("اجتماع بين 2 و4 مساءً", 14 * 60, 120),
      ("اجتماع الساعة 2-4", 14 * 60, 120),
      ("اجتماع الساعة 14:00-16:00", 14 * 60, 120),
      ("اجتماع من 14:00-16:00", 14 * 60, 120),
      ("اجتماع من الساعة 2 إلى الساعة 4", 14 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "اجتماع", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Two bare hours are as often an amount or numbered items: a range needs
    // الساعة, a part of the day, or a colon.
    expectLinesUnread(
      [
        "اجتماع من 2 إلى 4", "اجتماع من 14 إلى 16", "اجتماع من 14 إلى 16 صفحة", "اجتماع بين 2 و4",
        "اجتماع من 3 أشخاص إلى 5 أشخاص",
      ], languages: ["ar"])
    // English reads a range with a dash and no Arabic word.
    let bare = parse("اجتماع 14:00-16:00")
    #expect(bare.startMinutes == 14 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A bare number is no hour; a number before a sign or a word for a thing counted is an amount")
  func bareHours() {
    expectLinesUnread(
      [
        "اجتماع 3", "اجتماع مع 3 أشخاص", "اجتماع ٣ أشخاص", "زيارة 3 مرضى", "اجتماع 3 م", "اجتماع ٣ م", "شراء 5 م قماش",
        "شراء قماش 5 م", "شراء 2 كيلو", "شراء بـ 50 ريال", "شراء 50 د.إ", "اجتماع الساعة", "اجتماع الساعة الخامسة",
        "الساعة", "اجتماع الساعة 25",
      ], languages: ["ar"])
    // The words around a bare count keep their place beside a time that is one.
    let people = parse("اجتماع 5 أشخاص الساعة 3")
    #expect(people.startMinutes == 15 * 60)
    #expect(people.title == "اجتماع 5 أشخاص")
    let percent = parse("خصم 20% الساعة 3")
    #expect(percent.startMinutes == 15 * 60)
    #expect(percent.title == "خصم 20%")
  }

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("قراءة 20 دقيقة", 20), ("قراءة 20 دقيقه", 20), ("قراءة ٢٠ دقيقة", 20), ("قراءة ۲۰ دقيقة", 20),
      ("قراءة 30 د", 30), ("قراءة 45 دقيقة", 45), ("قراءة 90 د", 90), ("قراءة 3 دقائق", 3), ("قراءة دقيقتين", 2),
      ("قراءة 3 ساعات", 180), ("قراءة ساعتين", 120), ("قراءة ساعتان", 120), ("قراءة 2 ساعة", 120), ("قراءة 2 س", 120),
      ("قراءة 1.5 ساعة", 90), ("قراءة 1.5 س", 90), ("قراءة ١٫٥ ساعة", 90), ("قراءة 2 ساعة و30 دقيقة", 150),
      ("قراءة 1 س 30 د", 90), ("قراءة نصف ساعة", 30), ("قراءة نصف الساعة", 30), ("قراءة ربع ساعة", 15),
      ("قراءة ربع الساعة", 15), ("قراءة ثلاثة أرباع الساعة", 45), ("قراءة ساعة ونصف", 90), ("قراءة ساعة وربع", 75),
      ("قراءة ساعتين ونصف", 150), ("قراءة ساعة واحدة", 60), ("قراءة دقيقة واحدة", 1), ("قراءة ثلاث ساعات", 180),
      ("قراءة ثلاثة ساعات", 180), ("قراءة خمس دقائق", 5), ("قراءة عشر دقائق", 10), ("قراءة عشرين دقيقة", 20),
      ("قراءة لمدة 20 دقيقة", 20), ("قراءة لمدة ساعة", 60), ("قراءة مدة ساعة", 60), ("قراءة لمدة ساعة ونصف", 90),
      ("قراءة لمدة ٢٠ دقيقة", 20), ("قراءة حوالي ساعة", 60), ("قراءة نحو ساعة", 60), ("قراءة تقريبا ساعة", 60),
      ("قراءة حوالي 20 دقيقة", 20), ("قراءة لـ 20 دقيقة", 20), ("قراءة ل20 دقيقة", 20),
      ("قراءة 20 دقيقة تقريباً", 20), ("قراءة 20 دقيقة تقريبا", 20),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "قراءة", "\(line.text): title")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
    }
    #expect(parse("قراءة لمدة 20 دقيقة").phrases.map(\.text) == ["لمدة 20 دقيقة"])
  }

  @Test("An amount after بعد, كل, قبل, or في, or before قبل or a rate, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, or a bound.
        "قراءة بعد 20 دقيقة", "قراءة كل 20 دقيقة", "قراءة خلال 20 دقيقة", "قراءة أكثر من ساعة", "قراءة أقل من ساعة",
        "قراءة منذ 20 دقيقة", "مراجعة كل ساعتين", "مراجعة كل 15 دقيقة", "مراجعة كل ساعة", "اجتماع بعد 15 دقيقة",
        "بعد ساعة", "اجتماع بعد ساعتين", "اجتماع في 20 دقيقة",
        // The past and a rate.
        "قراءة 20 دقيقة قبل النوم", "قراءة 20 دقيقة في اليوم", "قراءة ساعتين في الأسبوع", "قراءة ساعة لكل يوم",
        // A range of amounts, and an hour as a noun or a unit of money.
        "قراءة 2-3 ساعات", "قراءة من 2 إلى 3 ساعات", "قراءة ساعة", "شراء ساعة جديدة", "قراءة لساعة", "شراء 50 د.إ",
      ], languages: ["ar"])
    // The phrase around an amount that is no length still reads.
    let day = parse("اتصل بعد 15 دقيقة غداً")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "اتصل بعد 15 دقيقة")
    // A time and a length together.
    let both = parse("اجتماع الساعة 3 مساءً لمدة 45 دقيقة")
    #expect(both.startMinutes == 15 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "اجتماع")
    // A length before the clock time it is not part of.
    let range = parse("اجتماع من الساعة 2 إلى 4 لمدة 30 دقيقة")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 30)
  }

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let daily = TaskRecurrenceRule(freq: .daily)
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("مراجعة كل يوم", daily), ("مراجعة يومياً", daily), ("مراجعة يوميا", daily), ("مراجعة كل صباح", daily),
      ("مراجعة كل مساء", daily), ("مراجعة كل ليلة", daily), ("مراجعة مرة في اليوم", daily),
      ("مراجعة كل أسبوع", weekly), ("مراجعة أسبوعياً", weekly), ("مراجعة اسبوعيا", weekly),
      ("مراجعة مرة في الأسبوع", weekly), ("مراجعة مرة واحدة في الأسبوع", weekly),
      ("مراجعة كل شهر", monthly), ("مراجعة شهرياً", monthly), ("مراجعة مرة في الشهر", monthly),
      ("مراجعة كل سنة", yearly), ("مراجعة كل عام", yearly), ("مراجعة سنوياً", yearly),
      ("مراجعة مرة واحدة في السنة", yearly),
      ("مراجعة كل يومين", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("مراجعة كل 3 أيام", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("مراجعة كل ٣ أيام", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("مراجعة كل ۳ أيام", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("مراجعة كل ثلاثة أيام", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("مراجعة كل 15 يوماً", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("مراجعة كل أسبوعين", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("مراجعة كل 3 أسابيع", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("مراجعة كل ثلاثة أسابيع", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("مراجعة مرة كل أسبوعين", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("مراجعة كل شهرين", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("مراجعة كل 3 أشهر", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("مراجعة كل ثلاثة أشهر", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("مراجعة مرة كل 3 أشهر", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("مراجعة كل سنتين", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("مراجعة كل 5 سنوات", TaskRecurrenceRule(freq: .yearly, interval: 5)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "مراجعة", "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
  }

  @Test("Weekday repeats: كل اثنين, كل يوم خميس, lists, spans, and من كل أسبوع")
  func weekdayRepeats() {
    let coming = parse("مراجعة كل اثنين")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "مراجعة")
    #expect(parse("مراجعة كل يوم اثنين").recurrence == monday)
    #expect(parse("مراجعة كل يوم الاثنين").recurrence == monday)
    #expect(parse("مراجعة كل الاثنين").recurrence == monday)
    #expect(parse("مراجعة كل إثنين").recurrence == monday)
    #expect(parse("مراجعة كل اثنين").plannedDayOffset == nil)

    let lists: [(text: String, days: [String])] = [
      ("مراجعة كل خميس", ["TH"]), ("مراجعة كل يوم خميس", ["TH"]), ("مراجعة كل جمعة", ["FR"]),
      ("مراجعة كل يوم جمعة", ["FR"]), ("مراجعة كل سبت", ["SA"]), ("مراجعة كل ثلاثاء", ["TU"]),
      ("مراجعة كل أربعاء", ["WE"]), ("مراجعة كل الأحد", ["SU"]), ("مراجعة كل يوم الأحد", ["SU"]),
      ("مراجعة كل اثنين وخميس", ["MO", "TH"]), ("مراجعة كل اثنين والخميس", ["MO", "TH"]),
      ("مراجعة كل الاثنين والخميس", ["MO", "TH"]), ("مراجعة كل اثنين وأربعاء وجمعة", ["MO", "WE", "FR"]),
      ("مراجعة كل اثنين، أربعاء وجمعة", ["MO", "WE", "FR"]), ("مراجعة مرة كل جمعة", ["FR"]),
      ("مراجعة مرة واحدة كل خميس", ["TH"]),
      ("مراجعة كل اثنين والأحد", ["SU", "MO"]), ("مراجعة الاثنين والخميس من كل أسبوع", ["MO", "TH"]),
      ("مراجعة كل يوم من الأحد إلى الخميس", ["SU", "MO", "TU", "WE", "TH"]),
      ("مراجعة كل يوم من الاثنين إلى الجمعة", ["MO", "TU", "WE", "TH", "FR"]),
      ("مراجعة كل يوم من الجمعة إلى الاثنين", ["SU", "MO", "FR", "SA"]),
      ("مراجعة كل يوم من السبت إلى الأربعاء", ["SU", "MO", "TU", "WE", "SA"]),
      ("مراجعة كل يوم من الاثنين حتى الجمعة", ["MO", "TU", "WE", "TH", "FR"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "مراجعة", "\(line.text): title")
    }
    // Sunday without its article is "someone" ("كل أحد"), so a list reads up to it and leaves it in the title.
    let unarticled = parse("مراجعة كل اثنين وأحد")
    #expect(unarticled.recurrence == monday)
    #expect(unarticled.title == "مراجعة وأحد")
    // The start of a repeat on Thursday and Monday is the nearer one, and a span that holds today starts today.
    #expect(parse("مراجعة كل اثنين وخميس").recurrenceStartOffset == 2)
    #expect(parse("مراجعة كل يوم من الأحد إلى الخميس").recurrenceStartOffset == 0)
    #expect(parse("مراجعة كل يوم من الجمعة إلى الاثنين").recurrenceStartOffset == 3)
    // A weekday with a time.
    let evening = parse("تمرين كل اثنين الساعة 7 مساءً")
    #expect(evening.recurrence == monday)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "تمرين")
    // A weekday repeat on that weekday itself starts today.
    #expect(parse("مراجعة كل جمعة", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in ["إيجار 5 من كل شهر", "إيجار في 5 من كل شهر", "إيجار يوم 5 من كل شهر", "إيجار ٥ من كل شهر"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text)")
      #expect(parsed.title == "إيجار", "\(text): title")
    }
    // A day with its month name is a date, not a repeat.
    let date = parse("إيجار كل 5 مارس")
    #expect(date.recurrence == nil)
    // "Every 5 of the month" is not the form people write.
    expectLinesUnread(["إيجار كل 5 من الشهر"], languages: ["ar"])
  }

  @Test("A cadence adverb repeats at the end of the line; an adjective, or an adverb elsewhere, stays in the title")
  func cadenceAdverbs() {
    let line = parse("مراجعة البريد يومياً")
    #expect(line.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(line.title == "مراجعة البريد")
    let morning = parse("رياضة يومياً صباحاً")
    #expect(morning.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(morning.title == "رياضة")
    let withTime = parse("مراجعة يومياً الساعة 8 مساءً")
    #expect(withTime.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(withTime.startMinutes == 20 * 60)
    #expect(parse("مراجعة شهرياً").recurrence == TaskRecurrenceRule(freq: .monthly))
    expectLinesUnread(
      [
        "يومياً مراجعة البريد", "تقرير يومي", "تقرير أسبوعي", "رسوم شهرية", "مراجعة مرتين في الأسبوع",
        "مراجعة كل عام وأنتم بخير", "كل عام وأنتم بخير", "تمرين أيام العمل", "تمرين في عطلة نهاية الأسبوع",
        "مراجعة كل ساعتين", "مراجعة كل 15 دقيقة",
      ], languages: ["ar"])
  }

  @Test("Priorities")
  func priorities() {
    let high = parse("اتصل بالبنك أولوية عالية")
    #expect(high.priority == .p1)
    #expect(high.title == "اتصل بالبنك")
    let priorities: [(text: String, priority: LorvexTask.Priority)] = [
      ("مهمة أولوية عالية", .p1), ("مهمة بأولوية عالية", .p1), ("مهمة ذات أولوية عالية", .p1),
      ("مهمة عالية الأولوية", .p1), ("مهمة أولوية قصوى", .p1), ("مهمة أولوية مرتفعة", .p1), ("مهمة أولوية: عالية", .p1),
      ("مهمة أولوية متوسطة", .p2), ("مهمة أولوية عادية", .p2), ("مهمة متوسطة الأولوية", .p2),
      ("مهمة أولوية منخفضة", .p3), ("مهمة منخفضة الأولوية", .p3), ("مهمة ذات أولوية منخفضة", .p3),
      ("مهمة أولوية دنيا", .p3), ("مهمة أولوية قليلة", .p3),
      ("مهمة عاجل", .p1), ("مهمة عاجلة", .p1), ("مهمة بشكل عاجل", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == "مهمة", "\(line.text): title")
    }
    let opening = parse("عاجل: اتصل بالسباك")
    #expect(opening.priority == .p1)
    #expect(opening.title == "اتصل بالسباك")
    #expect(parse("عاجل، اتصل بالسباك").priority == .p1)
    // Without a colon or comma an opening "عاجل" is a title word, and so is one
    // in the middle, or "مهم" alone.
    let word = parse("عاجل اتصل")
    #expect(word.priority == nil)
    #expect(word.title == "عاجل اتصل")
    #expect(parse("مستندات عاجلة جدا").priority == nil)
    #expect(parse("مهمة مهم").priority == nil)
    #expect(parse("مهمة أولوية 1").priority == nil)
    // English priorities read beside Arabic.
    #expect(parse("اجتماع !!").priority == .p1)
    #expect(parse("اجتماع p2").priority == .p2)
    #expect(parse("مهمة urgent").priority == .p1)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        "اليوم الوطني", "اتصل اليوم الوطني", "اجتماع كل اليوم", "نهاية الأسبوع", "عطلة نهاية الأسبوع",
        "تقرير نهاية الأسبوع القادم", "مراجعة الأسبوع", "اجتماع الأسبوع الماضي", "اجتماع بعد 3 أيام من الاجتماع الأول",
        "اجتماع بعد يوم", "اجتماع بعد أسبوع من الاجتماع", "شراء 3 كتب", "قراءة 5 فصول", "اشتر 2 كيلو",
        "طاولة لـ 4 أشخاص", "مراجعة 3 رمضان", "اتصل بأمي وغداً", "اتصل بأمي لغد", "اتصل بأمي بغد",
      ], languages: ["ar"])
    // "اليوم" with its own day phrase and "الليلة" still read.
    #expect(parse("اتصل اليوم الساعة 5").plannedDayOffset == 0)
    #expect(parse("اتصل اليوم الساعة 5").startMinutes == 17 * 60)
    #expect(parse("اتصل اليوم مساءً").plannedDayOffset == 0)
  }

  @Test("The one-letter words attached to a word read only in the forms listed")
  func prefixes() {
    // و between weekdays, ل before an amount, a date, or a day, ب in a few
    // words, and ع for "على".
    #expect(parse("مراجعة كل اثنين وخميس").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(parse("قراءة لـ 20 دقيقة").estimatedMinutes == 20)
    #expect(parse("قراءة لـ 20 دقيقة").title == "قراءة")
    #expect(parse("قراءة ل20 دقيقة").estimatedMinutes == 20)
    #expect(parse("قراءة لمدة ساعة").estimatedMinutes == 60)
    #expect(parse("تقرير لـ 5 مارس").plannedDayOffset == captureDayOffset("2027-03-05"))
    #expect(parse("تقرير ليوم الخميس").plannedDayOffset == 2)
    #expect(parse("تقرير بحلول الخميس").dueDayOffset == 2)
    #expect(parse("اجتماع الساعة 8 بالليل").startMinutes == 20 * 60)
    #expect(parse("مهمة بأولوية عالية").priority == .p1)
    #expect(parse("اجتماع ع الساعة 5").startMinutes == 17 * 60)
    // Every other attached word is part of the title.
    let attached = parse("اتصل بأمي وغداً")
    #expect(attached.plannedDayOffset == nil)
    #expect(attached.title == "اتصل بأمي وغداً")
    expectLinesUnread(["اتصل بأمي لغد", "اتصل بأمي بغد", "اتصل بأمي فغداً", "اتصل بأمي كغد"], languages: ["ar"])
  }

  @Test("Digits in the Arabic-Indic and Extended scripts read as the digits they stand for")
  func digitScripts() {
    let lines = [
      "اجتماع الساعة 3:30 مساءً", "اجتماع الساعة 15:30", "اجتماع من الساعة 2 إلى 4", "قراءة 20 دقيقة", "قراءة 1.5 ساعة",
      "قراءة 2 ساعة و30 دقيقة", "مراجعة كل 3 أيام", "مراجعة 5 من كل شهر", "زيارة 5 مارس 2027", "زيارة بعد 3 أيام",
      "إجازة من 3 إلى 5 مارس", "إجازة 3-5 مارس", "تقرير بحلول 5 مارس", "اجتماع الساعة 9 ليلاً",
    ]
    for line in lines {
      let latin = parse(line)
      #expect(latin.phrases.count == 1, "\(line): phrases")
      for offset in [UInt32(0x0660), UInt32(0x06F0)] {
        let converted = digits(line, from: offset)
        let parsed = parse(converted)
        #expect(parsed.title == latin.title, "\(converted): title")
        #expect(parsed.plannedDayOffset == latin.plannedDayOffset, "\(converted): planned day")
        #expect(parsed.dueDayOffset == latin.dueDayOffset, "\(converted): due day")
        #expect(parsed.startMinutes == latin.startMinutes, "\(converted): start")
        #expect(parsed.estimatedMinutes == latin.estimatedMinutes, "\(converted): length")
        #expect(parsed.recurrence == latin.recurrence, "\(converted): repeat")
        #expect(parsed.recurrenceStartOffset == latin.recurrenceStartOffset, "\(converted): repeat start")
      }
    }
  }

  @Test("Vowel signs, tatweel, and the spellings of hamza, teh marbuta, and alef maksura change nothing")
  func spellings() {
    let tomorrow = [
      "اتصل بأمي غداً", "اتصل بأمي غدًا", "اتصل بأمي غدا", "اتصل بأمي غَدًا", "اتصل بأمي غــداً", "اتصل بأمي غــــدًا",
    ]
    for text in tomorrow {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.title == "اتصل بأمي", "\(text): title")
    }
    // The title keeps the letters and signs as typed.
    let signs = parse("اتصلْ بأُمِّي غداً")
    #expect(signs.title == "اتصلْ بأُمِّي")
    #expect(parse("زيارة الطبيب بَعْدَ غَدٍ").plannedDayOffset == 2)
    #expect(parse("اجتماع يَوْمَ الخَمِيسِ").plannedDayOffset == 2)
    #expect(parse("اجتماع الساعة 9 مساءً").startMinutes == 21 * 60)
    #expect(parse("اجتماع الساعة 9 مساء").startMinutes == 21 * 60)
    #expect(parse("اجتماع إلى").title == "اجتماع إلى")
    // A letter written as another form of it: alef with hamza or madda for alef, ى for ي, ة for ه.
    #expect(parse("تقرير الاحد").dueDayOffset == nil)
    #expect(parse("تقرير قبل الاحد").dueDayOffset == 5)
    #expect(parse("تقرير قبل الأحد").dueDayOffset == 5)
    #expect(parse("تقرير حتي الخميس").dueDayOffset == 2)
    #expect(parse("مراجعة كل ٱلأحد").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SU"]))
    #expect(parse("زيارة الطبيب بعد أسبوعٍ").plannedDayOffset == 7)
    #expect(parse("قراءة ساعه ونصف").estimatedMinutes == 90)
    #expect(parse("قراءة 20 دقيقه").estimatedMinutes == 20)
    // A mark never splits a match from the letter it follows.
    let marked = parse("اجتماع الساعة 3 مساءً مهم")
    #expect(marked.startMinutes == 15 * 60)
    #expect(marked.title == "اجتماع مهم")
  }

  @Test("The Arabic comma and semicolon left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("اشتر حليب، غداً، الساعة 3", "اشتر حليب"),
      ("اشتر حليب، غداً", "اشتر حليب"),
      ("غداً، اشتر حليب", "اشتر حليب"),
      ("اشتر حليب ؛ غداً", "اشتر حليب"),
      ("غداً ؛ اشتر حليب", "اشتر حليب"),
      ("غداً: اشتر حليب", "اشتر حليب"),
      ("اشتر حليب - غداً", "اشتر حليب"),
      ("اشتر حليب ,  غداً , الساعة 3 مساءً", "اشتر حليب"),
      ("اشتر حليب ، غداً ، الساعة 3 مساءً ، أولوية عالية", "اشتر حليب"),
      ("اشتر حليب، وخبز غداً", "اشتر حليب، وخبز"),
      ("اشتر حليب، غداً، وخبز", "اشتر حليب، وخبز"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
  }

  @Test("A title never gains a bidirectional control character")
  func noBidiControls() {
    let controls: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
    for text in [
      "اتصل بأمي غداً الساعة 3 مساءً", "تقرير 5 مارس لمدة 20 دقيقة", "مراجعة كل اثنين وخميس", "اجتماع with Ahmed غداً",
      "اشتر حليب، غداً، أولوية عالية #قائمة",
    ] {
      let title = parse(text).title
      #expect(!title.unicodeScalars.contains { controls.contains($0.value) }, "\(text)")
    }
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    #expect(parse("اتصل بأمي غدًا").plannedDayOffset == 1)
    #expect(parse("اتصل بأمي الساعة 3 مساءً").startMinutes == 15 * 60)
    #expect(parse("اتصل بأمي كل اثنين").recurrence == monday)
    #expect(parse("اتصل بأمي 20 دقيقة").estimatedMinutes == 20)
    #expect(parse("اتصل بأمي #قائمة").tags == ["قائمة"])
  }

  @Test("Beside Arabic, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "ar"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "ar"]).estimatedMinutes == 20)
    #expect(parse("اجتماع 2h").estimatedMinutes == 120)
    #expect(parse("اجتماع 30min").estimatedMinutes == 30)
    #expect(parse("اجتماع 1h30m").estimatedMinutes == 90)
    let at = parse("Call mom at 3pm", languages: ["en", "ar"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "ar"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "ar"]).plannedDayOffset == 1)
    // English lines read the same with Arabic beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "ar"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("اتصل بأمي غداً at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "اتصل بأمي")
    let weekday = parse("Meeting يوم الخميس at 3pm")
    #expect(weekday.plannedDayOffset == 2)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("اجتماع tomorrow الساعة 3 مساءً")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 15 * 60)
    #expect(reversed.title == "اجتماع")
    // A bare weekday is no day beside English words either.
    expectLinesUnread(["meeting الخميس"], languages: ["ar"])
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // Watches counted in "ساعات" read as hours.
    #expect(parse("اشتر 3 ساعات").estimatedMinutes == 180)
    // "كل اثنين" could say "every two", and it reads as every Monday.
    #expect(parse("مراجعة كل اثنين").recurrence == monday)
    // "اليوم" is today in "today's report" too.
    #expect(parse("تقرير اليوم").plannedDayOffset == 0)
    // A weekday after a part of the day is a day in a title.
    let party = parse("حفلة مساء الخميس")
    #expect(party.plannedDayOffset == 2)
    #expect(party.title == "حفلة")
  }

  @Test("Arabic words are read only for a user who reads Arabic")
  func languageGate() {
    let line = parse("اتصل بأمي غداً", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "اتصل بأمي غداً")
    for languages in [["ar"], ["ar-SA"], ["ar_EG"], ["ar-AE", "en-US"], ["en-US", "ar-MA"], ["AR"]] {
      #expect(parse("اتصل بأمي غداً", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Persian and Urdu readers do not get Arabic words, and Arabic readers do not get theirs.
    #expect(parse("اتصل بأمي غداً", languages: ["fa"]).plannedDayOffset == nil)
    #expect(parse("اتصل بأمي غداً", languages: ["ur"]).plannedDayOffset == nil)
    // Other languages' words are not read for an Arabic reader, and Arabic words are not read for theirs.
    #expect(parse("Zadzwonić jutro", languages: ["ar"]).plannedDayOffset == nil)
    #expect(parse("Позвонить завтра", languages: ["ar"]).plannedDayOffset == nil)
    #expect(parse("اتصل بأمي غداً", languages: ["pl"]).plannedDayOffset == nil)
    #expect(parse("اتصل بأمي غداً", languages: ["ru"]).plannedDayOffset == nil)
    // A clock time with an Arabic word needs Arabic among the languages.
    #expect(parse("اجتماع الساعة 3 مساءً", languages: ["en"]).startMinutes == nil)
    #expect(parse("مراجعة كل اثنين", languages: ["en"]).recurrence == nil)
  }
}
