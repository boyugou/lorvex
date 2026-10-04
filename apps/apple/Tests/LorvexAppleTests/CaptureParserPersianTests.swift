import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday (weekday 3 in the Gregorian convention) and 31
// Shahrivar 1405 in the Solar Hijri calendar.
private func parse(_ text: String, languages: [String] = ["fa"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on `today` (`yyyy-MM-dd`), whose weekday is derived from it.
private func parse(_ text: String, on today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday(of: today), today: today, languages: ["fa"])
}

private var utcCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
  return calendar
}

private func midnight(_ text: String) -> Date {
  let parts = text.split(separator: "-").compactMap { Int($0) }
  return utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .distantPast
}

/// The weekday of `date` (`yyyy-MM-dd`), 1 = Sunday.
private func weekday(of date: String) -> Int {
  utcCalendar.component(.weekday, from: midnight(date))
}

/// Days from `today` to `date`, both `yyyy-MM-dd`.
private func daysBetween(from today: String, to date: String) -> Int {
  utcCalendar.dateComponents([.day], from: midnight(today), to: midnight(date)).day ?? 0
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

/// Persian capture lines, read for a user whose languages include Persian.
@Suite("Capture parser Persian")
struct CaptureParserPersianTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days or weeks")
  func days() {
    let line = parse("تماس با مادر فردا")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "تماس با مادر")
    #expect(line.phrases.map(\.text) == ["فردا"])

    let days: [(text: String, offset: Int)] = [
      ("تماس با مادر امروز", 0), ("تماس با مادر امشب", 0), ("تماس با مادر همین امروز", 0),
      ("تماس با مادر فردا", 1), ("تماس با مادر همین فردا", 1),
      ("تماس با مادر پس‌فردا", 2), ("تماس با مادر پس فردا", 2), ("تماس با مادر پسفردا", 2),
      ("تماس با مادر پس\u{200D}فردا", 2),
      ("تماس با مادر ۳ روز دیگر", 3), ("تماس با مادر 3 روز دیگر", 3), ("تماس با مادر ٣ روز دیگر", 3),
      ("تماس با مادر سه روز دیگر", 3), ("تماس با مادر سه روز دیگه", 3), ("تماس با مادر ۱۰ روز دیگر", 10),
      ("تماس با مادر ده روز دیگر", 10), ("تماس با مادر ۳ روز بعد", 3), ("تماس با مادر بعد از ۳ روز", 3),
      ("تماس با مادر پس از سه روز", 3), ("تماس با مادر یک هفته دیگر", 7), ("تماس با مادر دو هفته دیگر", 14),
      ("تماس با مادر ۳ هفته دیگر", 21), ("تماس با مادر هفته دیگر", 7), ("تماس با مادر هفته آینده", 7),
      ("تماس با مادر هفته بعد", 7), ("تماس با مادر هفته‌ی بعد", 7), ("تماس با مادر هفته ی بعد", 7),
      ("تماس با مادر هفته آتی", 7),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.title == "تماس با مادر", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("فردا تماس با مادر")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "تماس با مادر")
    // A day in the middle leaves the words on both sides.
    let middle = parse("مادر را فردا صدا کن")
    #expect(middle.plannedDayOffset == 1)
    #expect(middle.title == "مادر را صدا کن")
  }

  @Test("A number of months ahead is counted on the Solar Hijri calendar")
  func months() {
    // 15 Farvardin has a month of 31 days after it, 12 Mehr one of 30.
    #expect(parse("تماس با مادر یک ماه دیگر", on: "2026-04-04").plannedDayOffset == 31)
    #expect(parse("تماس با مادر یک ماه دیگر", on: "2026-10-04").plannedDayOffset == 30)
    #expect(parse("تماس با مادر دو ماه دیگر", on: "2026-10-04").plannedDayOffset == 60)
    #expect(parse("تماس با مادر ۳ ماه دیگر", on: "2026-10-04").plannedDayOffset == 90)
    #expect(parse("تماس با مادر یک ماه بعد", on: "2026-10-04").plannedDayOffset == 30)
    // A month counted from the 31st lands on the last day of a shorter month.
    #expect(parse("تماس با مادر یک ماه دیگر").plannedDayOffset == 30)
  }

  @Test("A count of days that is counted from something else, or counts what is left, is no day")
  func notCountedFromToday() {
    expectLinesUnread(
      [
        "کتاب ۳ روز بعد از جلسه", "کتاب ۳ روز دیگر مانده", "کتاب ۳ روز دیگر باقی", "کتاب ۳ روز پیش", "کتاب ۳ روز قبل",
        "مرخصی ۲ هفته", "سفر ۵ روز", "تمرین ۳ روز", "کتاب بعد از ۳ روز پیش",
      ], languages: ["fa"])
  }

  @Test("A part of the day beside a day is read with it and sets a bare hour")
  func partsOfDay() {
    let morning = parse("تماس با مادر فردا صبح")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == nil)
    #expect(morning.title == "تماس با مادر")
    #expect(morning.phrases.map(\.text) == ["فردا صبح"])
    let before = parse("تماس با مادر صبح فردا")
    #expect(before.plannedDayOffset == 1)
    #expect(before.phrases.map(\.text) == ["صبح فردا"])
    for (text, offset) in [
      ("شام امروز عصر", 0), ("شام عصر امروز", 0), ("شام همین امروز", 0), ("شام این شب", 0), ("شام این عصر", 0),
      ("شام فردا شب", 1), ("شام فردا ظهر", 1), ("شام پس‌فردا شب", 2), ("شام امروز بعد از ظهر", 0),
    ] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == offset, "\(text)")
      #expect(parsed.title == "شام", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
    }

    // A part of the day beside the day phrase names a bare hour's half of the
    // day, whatever the hour: 6 in the morning is not 6 in the evening, and 4
    // in the evening is not 4 at night.
    let beside: [(text: String, planned: Int, minutes: Int)] = [
      ("جلسه فردا صبح ساعت ۶", 1, 6 * 60), ("جلسه فردا صبح ساعت ۹", 1, 9 * 60),
      ("جلسه صبح فردا ساعت ۶", 1, 6 * 60), ("جلسه امروز صبح ساعت ۶", 0, 6 * 60),
      ("جلسه فردا عصر ساعت ۴", 1, 16 * 60), ("جلسه امروز عصر ساعت ۵", 0, 17 * 60),
      ("جلسه فردا شب ساعت ۱۰", 1, 22 * 60), ("جلسه پنجشنبه عصر ساعت ۴", 2, 16 * 60),
      ("جلسه عصر پنجشنبه ساعت ۸", 2, 20 * 60), ("جلسه صبح پنجشنبه ساعت ۵", 2, 5 * 60),
      ("جلسه امشب ساعت ۸", 0, 20 * 60), ("جلسه این شب ساعت ۸", 0, 20 * 60),
      ("جلسه هر شب ساعت ۱۰", 0, 22 * 60),
    ]
    for line in beside {
      let parsed = parse(line.text)
      if !line.text.contains("هر") { #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day") }
      #expect(parsed.startMinutes == line.minutes, "\(line.text): start")
      #expect(parsed.title == "جلسه", "\(line.text): title")
    }
    // A night past midnight moves the day.
    let late = parse("جلسه فردا شب ساعت ۲")
    #expect(late.plannedDayOffset == 2)
    #expect(late.startMinutes == 2 * 60)
    // The part of the day as a noun names no day.
    expectLinesUnread(["جلسه صبح", "جلسه عصر", "کلاس شب", "قهوه صبح", "جلسه بعد از ظهر", "جلسه قبل از ظهر"], languages: ["fa"])
  }

  // MARK: - Weekdays

  @Test("Weekdays: the next one, this week's, the coming one, and one beside a part of the day")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      // Today is Tuesday, so a bare Tuesday is a week ahead and "این سه‌شنبه" is today.
      ("جلسه جمعه", 3), ("جلسه شنبه", 4), ("جلسه یکشنبه", 5), ("جلسه دوشنبه", 6), ("جلسه سه‌شنبه", 7),
      ("جلسه چهارشنبه", 1), ("جلسه پنجشنبه", 2), ("جلسه آدینه", 3),
      ("جلسه روز جمعه", 3), ("جلسه در روز جمعه", 3), ("جلسه برای جمعه", 3), ("جلسه برای روز پنجشنبه", 2),
      ("جلسه این پنجشنبه", 2), ("جلسه این سه‌شنبه", 0), ("جلسه همین جمعه", 3), ("جلسه این شنبه", 4),
      ("جلسه پنجشنبه آینده", 2), ("جلسه سه‌شنبه آینده", 7), ("جلسه پنجشنبه‌ی بعد", 2), ("جلسه جمعه آتی", 3),
      ("جلسه سه‌شنبه بعدی", 7), ("جلسه پنجشنبه بعد", 2), ("جلسه روز پنجشنبه آینده", 2),
      ("جلسه صبح پنجشنبه", 2), ("جلسه پنجشنبه صبح", 2), ("جلسه عصر جمعه", 3), ("جلسه جمعه عصر", 3),
      ("جلسه پنجشنبه شب", 2), ("جلسه روز جمعه عصر", 3), ("جلسه جمعه قبل از ظهر", 3), ("جلسه جمعه بعد از ظهر", 3),
      // However the compound names are typed.
      ("جلسه سه شنبه", 7), ("جلسه سهشنبه", 7), ("جلسه سه\u{200D}شنبه", 7), ("جلسه چهار شنبه", 1),
      ("جلسه چهارشنبه", 1), ("جلسه چهار‌شنبه", 1), ("جلسه پنج شنبه", 2), ("جلسه پنجشنبه", 2),
      ("جلسه یک شنبه", 5), ("جلسه یک‌شنبه", 5), ("جلسه دو شنبه", 6), ("جلسه دو‌شنبه", 6),
      ("جلسه چارشنبه", 1), ("جلسه سشنبه", 7), ("جلسه پن‌شنبه", 2),
      // The Arabic letters, and the alef without its madda.
      ("جلسه جمعة", 3), ("جلسه يكشنبه", 5), ("جلسه ادینه", 3), ("جلسه هفتۀ آینده سه‌شنبه", 7),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "جلسه", "\(weekday.text): title")
    }
    // Today is a Thursday: a bare Thursday is a week ahead, "این پنجشنبه" is today, and the coming Thursday is next week's.
    for (text, offset) in [
      ("جلسه پنجشنبه", 7), ("جلسه این پنجشنبه", 0), ("جلسه پنجشنبه آینده", 7), ("جلسه جمعه", 1), ("جلسه شنبه", 2),
    ] {
      #expect(parse(text, on: "2026-09-24").plannedDayOffset == offset, "Thursday: \(text)")
    }
    // Friday and Sunday.
    #expect(parse("جلسه جمعه", on: "2026-09-25").plannedDayOffset == 7)
    #expect(parse("جلسه این جمعه", on: "2026-09-25").plannedDayOffset == 0)
    #expect(parse("جلسه یکشنبه", on: "2026-09-27").plannedDayOffset == 7)
    #expect(parse("جلسه یکشنبه آینده", on: "2026-09-27").plannedDayOffset == 7)
    #expect(parse("جلسه این یکشنبه", on: "2026-09-27").plannedDayOffset == 0)
    let opening = parse("جمعه تماس با مادر")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "تماس با مادر")
  }

  @Test("Weeks start on Monday: the week named before or after a weekday is the next one")
  func weeksStartOnMonday() {
    // Today is Tuesday 2026-09-22: the next week runs from Monday 09-28 to Sunday 10-04.
    let tuesday: [(text: String, offset: Int)] = [
      ("جلسه هفته آینده دوشنبه", 6), ("جلسه هفته آینده سه‌شنبه", 7), ("جلسه هفته آینده چهارشنبه", 8),
      ("جلسه هفته آینده پنجشنبه", 9), ("جلسه هفته آینده جمعه", 10), ("جلسه هفته آینده شنبه", 11),
      ("جلسه هفته آینده یکشنبه", 12), ("جلسه سه‌شنبه هفته آینده", 7), ("جلسه جمعه هفته بعد", 10),
      ("جلسه هفته بعد شنبه", 11), ("جلسه هفته‌ی آینده چهارشنبه", 8), ("جلسه پنجشنبه این هفته", 2),
      ("جلسه جمعه این هفته", 3),
    ]
    for line in tuesday {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text)")
      #expect(parsed.title == "جلسه", "\(line.text): title")
    }
    // Thursday 09-24: the next week begins in four days.
    for (text, offset) in [
      ("جلسه هفته آینده دوشنبه", 4), ("جلسه هفته آینده چهارشنبه", 6), ("جلسه هفته آینده پنجشنبه", 7),
      ("جلسه هفته آینده جمعه", 8), ("جلسه هفته آینده شنبه", 9),
    ] {
      #expect(parse(text, on: "2026-09-24").plannedDayOffset == offset, "Thursday: \(text)")
    }
    // Saturday 09-26: the next week begins in two days.
    #expect(parse("جلسه هفته آینده دوشنبه", on: "2026-09-26").plannedDayOffset == 2)
    #expect(parse("جلسه هفته آینده جمعه", on: "2026-09-26").plannedDayOffset == 6)
    #expect(parse("جلسه هفته آینده شنبه", on: "2026-09-26").plannedDayOffset == 7)
    #expect(parse("جلسه شنبه", on: "2026-09-26").plannedDayOffset == 7)
    #expect(parse("جلسه این شنبه", on: "2026-09-26").plannedDayOffset == 0)
    // Sunday 09-27 is the week's last day: the next week begins tomorrow.
    #expect(parse("جلسه هفته آینده دوشنبه", on: "2026-09-27").plannedDayOffset == 1)
    #expect(parse("جلسه هفته آینده شنبه", on: "2026-09-27").plannedDayOffset == 6)
    #expect(parse("جلسه هفته آینده یکشنبه", on: "2026-09-27").plannedDayOffset == 7)
  }

  @Test("A weekday in the past, a night, a name, or after a bound is no planned day")
  func weekdaysUnread() {
    expectLinesUnread(
      [
        // The past, and the night before a day.
        "جلسه دیروز", "جلسه پریروز", "جلسه پریشب", "جلسه پنجشنبه گذشته", "جلسه جمعه گذشته", "جلسه جمعه قبل",
        "جلسه جمعه پیش", "جلسه جمعه قبلی", "جلسه شب جمعه", "جلسه شب پنجشنبه",
        // A weekday that is part of a name.
        "نماز جمعه", "خرید بازار جمعه", "جشن چهارشنبه‌سوری", "جشن چهارشنبه سوری", "جلسه جمعه‌بازار", "جلسه جمعه بازار",
        // A day after a bound, or inside a stretch, is no planned day.
        "گزارش بعد از جمعه", "گزارش پس از جمعه", "گزارش از جمعه", "گزارش آخر جمعه", "گزارش طی جمعه",
        "گزارش تمام جمعه", "گزارش اول جمعه",
      ], languages: ["fa"])
    // A weekday after a name reads when another day phrase of its own follows, and the name stays.
    let both = parse("نماز جمعه روز جمعه")
    #expect(both.plannedDayOffset == 3)
    #expect(both.title == "نماز جمعه")
    let prayer = parse("نماز جمعه فردا")
    #expect(prayer.plannedDayOffset == 1)
    #expect(prayer.title == "نماز جمعه")
    // The first of two weekdays is the day; the second stays in the title.
    let pair = parse("ورزش دوشنبه و پنجشنبه")
    #expect(pair.plannedDayOffset == 6)
    #expect(pair.title == "ورزش و پنجشنبه")
  }

  // MARK: - Written dates

  @Test("Solar Hijri dates: every month, with a year, and the spellings of the month names")
  func solarDates() {
    let dates: [(text: String, date: String)] = [
      // 2026-09-22 is 31 Shahrivar 1405.
      ("زیارت ۳۱ شهریور", "2026-09-22"), ("زیارت ۱ مهر", "2026-09-23"), ("زیارت ۱۲ مهر", "2026-10-04"),
      ("زیارت ۱ آبان", "2026-10-23"), ("زیارت ۱۰ آذر", "2026-12-01"), ("زیارت ۱۵ دی", "2027-01-05"),
      ("زیارت ۲۲ بهمن", "2027-02-11"), ("زیارت ۱ اسفند", "2027-02-20"), ("زیارت ۲۹ اسفند", "2027-03-20"),
      // A date that has passed this Solar year is next year's.
      ("زیارت ۱ فروردین", "2027-03-21"), ("زیارت ۳۱ فروردین", "2027-04-20"), ("زیارت ۱ اردیبهشت", "2027-04-21"),
      ("زیارت ۱ خرداد", "2027-05-22"), ("زیارت ۱ تیر", "2027-06-22"), ("زیارت ۱ مرداد", "2027-07-23"),
      ("زیارت ۱ شهریور", "2027-08-23"), ("زیارت ۳۰ شهریور", "2027-09-21"),
      // The words and signs around the date.
      ("زیارت ۱۲ مهر ماه", "2026-10-04"), ("زیارت ۱۲ مهرماه", "2026-10-04"), ("زیارت ۱۲ مهر‌ماه", "2026-10-04"),
      ("زیارت در ۱۲ مهر", "2026-10-04"), ("زیارت برای ۱۲ مهر", "2026-10-04"),
      ("زیارت پنجشنبه ۱۲ مهر", "2026-10-04"), ("زیارت پنجشنبه، ۱۲ مهر", "2026-10-04"),
      // The Latin and the Arabic-Indic digits.
      ("زیارت 12 مهر", "2026-10-04"), ("زیارت ١٢ مهر", "2026-10-04"), ("زیارت ۱۲ مهر", "2026-10-04"),
      // A year, in the Solar Hijri calendar.
      ("زیارت ۱۲ مهر ۱۴۰۵", "2026-10-04"), ("زیارت ۲۹ اسفند ۱۴۰۵", "2027-03-20"),
      ("زیارت ۱ فروردین ۱۴۰۶", "2027-03-21"), ("زیارت ۱ فروردین ۱۴۰۷", "2028-03-20"),
      // The compound names, however they are typed, and the other spellings.
      ("زیارت ۲۳ اردیبهشت", "2027-05-13"), ("زیارت ۲۳ اردی‌بهشت", "2027-05-13"), ("زیارت ۲۳ اردی بهشت", "2027-05-13"),
      ("زیارت ۲۳ اردي‌بهشت", "2027-05-13"), ("زیارت ۱ امرداد", "2027-07-23"), ("زیارت ۱ اسپند", "2027-02-20"),
      ("زیارت ۵ ابان", "2026-10-27"), ("زیارت ۵ آبان", "2026-10-27"), ("زیارت ۵ اذر", "2026-11-26"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.title == "زیارت", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    #expect(parse("زیارت ۱۲ مهر").phrases.map(\.text) == ["۱۲ مهر"])
    #expect(parse("زیارت پنجشنبه ۱۲ مهر").phrases.map(\.text) == ["پنجشنبه ۱۲ مهر"])
    // A date that opens the line.
    let opening = parse("۱۲ مهر زیارت")
    #expect(opening.plannedDayOffset == 12)
    #expect(opening.title == "زیارت")
  }

  @Test("Gregorian dates are read by the month's name, with the spellings Persian and Dari write")
  func gregorianDates() {
    let dates: [(text: String, date: String)] = [
      ("زیارت ۵ مارس", "2027-03-05"), ("زیارت ۵ مارچ", "2027-03-05"), ("زیارت ۵ مارس ۲۰۲۷", "2027-03-05"),
      ("زیارت ۵ مارس ۲۰۲۸", "2028-03-05"), ("زیارت ۵ ژانویه", "2027-01-05"), ("زیارت ۵ جنوری", "2027-01-05"),
      ("زیارت ۵ فوریه", "2027-02-05"), ("زیارت ۵ فبروری", "2027-02-05"), ("زیارت ۵ آوریل", "2027-04-05"),
      ("زیارت ۵ اپریل", "2027-04-05"), ("زیارت ۵ مه", "2027-05-05"), ("زیارت ۵ ژوئن", "2027-06-05"),
      ("زیارت ۵ جون", "2027-06-05"), ("زیارت ۵ ژوئیه", "2027-07-05"), ("زیارت ۵ جولای", "2027-07-05"),
      ("زیارت ۵ اوت", "2027-08-05"), ("زیارت ۵ آگوست", "2027-08-05"), ("زیارت ۵ اگست", "2027-08-05"),
      ("زیارت ۵ سپتامبر", "2027-09-05"), ("زیارت ۵ اکتبر", "2026-10-05"), ("زیارت ۵ اکتوبر", "2026-10-05"),
      ("زیارت ۵ نوامبر", "2026-11-05"), ("زیارت ۵ نومبر", "2026-11-05"), ("زیارت ۱۲ دسامبر", "2026-12-12"),
      ("زیارت ۱۲ دسمبر", "2026-12-12"), ("زیارت در ۵ مارس", "2027-03-05"), ("زیارت برای ۵ مارس", "2027-03-05"),
      ("زیارت 5 مارس", "2027-03-05"), ("زیارت ٥ مارس", "2027-03-05"), ("زیارت ۵ مارس ٢٠٢٧", "2027-03-05"),
      ("زیارت ۵ ژانويه", "2027-01-05"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text)")
      #expect(parsed.title == "زیارت", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
  }

  @Test("A day that falls in a leap year only: 30 Esfand")
  func leapYears() {
    // 1403 and 1408 are leap years, with 30 days in Esfand.
    #expect(parse("زیارت ۳۰ اسفند", on: "2025-03-01").plannedDayOffset == daysBetween(from: "2025-03-01", to: "2025-03-20"))
    #expect(parse("زیارت ۲۹ اسفند", on: "2025-03-01").plannedDayOffset == daysBetween(from: "2025-03-01", to: "2025-03-19"))
    #expect(parse("زیارت ۱ فروردین", on: "2025-03-01").plannedDayOffset == daysBetween(from: "2025-03-01", to: "2025-03-21"))
    #expect(parse("زیارت ۳۰ اسفند", on: "2030-03-01").plannedDayOffset == daysBetween(from: "2030-03-01", to: "2030-03-20"))
    #expect(parse("زیارت ۱ فروردین", on: "2030-03-01").plannedDayOffset == daysBetween(from: "2030-03-01", to: "2030-03-21"))
    #expect(parse("زیارت ۳۰ اسفند ۱۴۰۸").plannedDayOffset == captureDayOffset("2030-03-20"))
    // 1405 and 1406 are not: the day is no date.
    expectLinesUnread(["زیارت ۳۰ اسفند", "زیارت ۳۰ اسفند ۱۴۰۵", "زیارت ۳۰ اسفند ۱۴۰۶", "زیارت ۳۰ اسفند ۱۴۰۳"], languages: ["fa"])
  }

  @Test("A month alone, a date in digits, a day the month lacks, or another calendar's date is no date")
  func datesUnread() {
    expectLinesUnread(
      [
        "زیارت مهر", "مهر ماه زیارت", "زیارت آبان ۵", "زیارت ۱۴۰۵/۷/۱۲", "زیارت ۱۲/۷", "زیارت ۱۲-۷",
        // A day the calendar lacks.
        "زیارت ۳۱ مهر", "زیارت ۳۲ فروردین", "زیارت ۰ مهر", "زیارت ۳۱ فوریه", "زیارت ۲۹ فوریه", "زیارت ۳۱ آوریل",
        // A year in the past or too far ahead.
        "زیارت ۱۲ مهر ۱۴۰۴", "زیارت ۵ مارس ۲۰۲۶", "زیارت ۱ فروردین ۱۴۲۰",
        // The lunar Hijri months, the Afghan names of the Solar months, and a verb that is also a month.
        "زیارت ۳ رمضان", "زیارت ۱۰ محرم", "زیارت ۲ ثور", "زیارت ۵ حمل", "کتاب ۲ می خرم",
      ], languages: ["fa"])
    // A date after a word that sets it against something else is no planned day.
    expectLinesUnread(["گزارش از ۱۲ مهر", "گزارش بعد از ۱۲ مهر"], languages: ["fa"])
  }

  // MARK: - Date ranges

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("مرخصی", "از ۳ تا ۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از ۳ الی ۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "۳ تا ۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از ۳ آبان تا ۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از ۳ آبان تا ۵ آذر", "2026-10-25", "2026-11-26"),
        ("مرخصی", "از ۳۰ مهر تا ۲ آبان", "2026-10-22", "2026-10-24"),
        ("مرخصی", "بین ۳ و ۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "بین ۳ تا ۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "۳-۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "۳–۵ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از ۳ تا ۵ آبان ۱۴۰۵", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از ۳ آبان ۱۴۰۵ تا ۵ آبان ۱۴۰۵", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از ۱ فروردین ۱۴۰۶ تا ۵ فروردین ۱۴۰۶", "2027-03-21", "2027-03-25"),
        // A range across the end of the Solar year.
        ("مرخصی", "از ۲۸ اسفند تا ۲ فروردین", "2027-03-19", "2027-03-22"),
        ("مرخصی", "از ۲۰ دی تا ۵ بهمن", "2027-01-10", "2027-01-25"),
        // The Gregorian calendar.
        ("مرخصی", "از ۳ تا ۵ مارس", "2027-03-03", "2027-03-05"),
        ("مرخصی", "از ۳۰ ژانویه تا ۲ فوریه", "2027-01-30", "2027-02-02"),
        ("مرخصی", "از ۳ مارس تا ۵ آوریل", "2027-03-03", "2027-04-05"),
        ("مرخصی", "۳-۵ مارس", "2027-03-03", "2027-03-05"),
        // The digit scripts.
        ("مرخصی", "از ٣ تا ٥ آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی", "از 3 تا 5 آبان", "2026-10-25", "2026-10-27"),
        ("مرخصی کنار دریا", "از ۳ تا ۵ آبان", "2026-10-25", "2026-10-27"),
      ], languages: ["fa"])
    // A range takes both days, so another day phrase stays in the title.
    let line = parse("مرخصی از ۳ تا ۵ آبان فردا")
    #expect(line.plannedDayOffset == captureDayOffset("2026-10-25"))
    #expect(line.dueDayOffset == captureDayOffset("2026-10-27"))
    #expect(line.title == "مرخصی فردا")
  }

  @Test("A day alone opens a range joined by a spaced dash only after an opening word")
  func spacedDashAfterLoneDay() {
    // A spaced dash after a number sets the number apart as part of the title,
    // and the date after it is read alone.
    let sprint = parse("اسپرینت ۱۲ - ۲۰ مهر")
    #expect(sprint.title == "اسپرینت ۱۲")
    #expect(sprint.plannedDayOffset == captureDayOffset("2026-10-12"))
    #expect(sprint.dueDayOffset == nil)
    // A dash that touches both sides, or an opening word, makes it a range.
    expectDateRanges(
      [
        ("سفر", "۱۲-۲۰ مهر", "2026-10-04", "2026-10-12"),
        ("سفر", "از ۱۲ - ۲۰ مهر", "2026-10-04", "2026-10-12"),
      ], languages: ["fa"])
  }

  @Test("A range whose end is not after its start, or that names two days, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "مرخصی از ۵ تا ۳ آبان", "مرخصی از ۳ آبان تا ۳ آبان", "مرخصی از ۵ آبان تا ۳ آبان", "مرخصی بین ۵ و ۳ آبان",
        "مرخصی ۵-۳ آبان",
        // "و" joins the sides only after "بین".
        "مرخصی ۳ و ۵ آبان", "مرخصی از ۳ و ۵ آبان",
        // A range whose sides name different calendars, or a day the calendar lacks.
        "مرخصی از ۳ مهر تا ۵ مارس", "مرخصی از ۳۰ اسفند تا ۲ فروردین", "مرخصی از ۳ آبان تا ۳۱ آبان",
        // Days of the month with no month are no range.
        "مرخصی از ۳ تا ۵", "مرخصی بین ۳ و ۵", "بشمار از ۱ تا ۱۰",
      ], languages: ["fa"])
  }

  @Test("A span of weekdays plans the first and is due on the last; a working week stays in the title")
  func weekdaySpans() {
    // Today is Tuesday.
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("ورزش از دوشنبه تا چهارشنبه", 6, 8), ("ورزش دوشنبه تا چهارشنبه", 6, 8), ("ورزش از دوشنبه الی چهارشنبه", 6, 8),
      ("ورزش بین دوشنبه و چهارشنبه", 6, 8), ("ورزش از پنجشنبه تا شنبه", 2, 4), ("ورزش از جمعه تا دوشنبه", 3, 6),
      ("ورزش از سه‌شنبه تا پنجشنبه", 7, 9),
    ]
    for span in spans {
      let parsed = parse(span.text)
      #expect(parsed.plannedDayOffset == span.planned, "\(span.text): planned day")
      #expect(parsed.dueDayOffset == span.due, "\(span.text): due day")
      #expect(parsed.title == "ورزش", "\(span.text): title")
      #expect(parsed.recurrence == nil, "\(span.text): repeat")
    }
    #expect(parse("ورزش از پنجشنبه تا شنبه", on: "2026-09-24").plannedDayOffset == 7)
    let withTime = parse("ورزش از دوشنبه الی چهارشنبه ساعت ۵")
    #expect(withTime.plannedDayOffset == 6)
    #expect(withTime.startMinutes == 17 * 60)
    // Monday to Friday, Saturday to Wednesday, and Saturday to Thursday are a week of work as often as a span of days.
    expectLinesUnread(
      [
        "ورزش از دوشنبه تا جمعه", "ورزش از شنبه تا چهارشنبه", "ورزش از شنبه تا پنجشنبه", "ورزش دوشنبه تا جمعه",
        // The past, and a span from a day to itself.
        "ورزش از دوشنبه تا چهارشنبه گذشته", "ورزش از دوشنبه تا دوشنبه",
      ], languages: ["fa"])
  }

  // MARK: - Due days

  @Test("Due days: تا, قبل از, پیش از, حداکثر, and a deadline label")
  func dueDays() {
    let due: [(text: String, offset: Int)] = [
      ("گزارش تا جمعه", 3), ("گزارش قبل از جمعه", 3), ("گزارش پیش از جمعه", 3), ("گزارش قبل‌از جمعه", 3),
      ("گزارش حداکثر جمعه", 3), ("گزارش حداکثر تا جمعه", 3), ("گزارش نهایتاً جمعه", 3), ("گزارش نهایتا تا جمعه", 3),
      ("گزارش تا روز جمعه", 3), ("گزارش تا پنجشنبه", 2), ("گزارش تا سه‌شنبه", 7), ("گزارش تا یکشنبه", 5),
      ("گزارش تا پنجشنبه آینده", 2), ("گزارش تا هفته آینده", 7), ("گزارش تا ۳ روز دیگر", 3),
      ("گزارش تا فردا", 1), ("گزارش تا پس‌فردا", 2), ("گزارش قبل از فردا", 1), ("گزارش تا امروز", 0),
      ("گزارش تا آخر روز", 0), ("گزارش تا پایان امروز", 0),
      ("گزارش تا ۱۲ مهر", 12), ("گزارش قبل از ۱۲ مهر", 12), ("گزارش تا ۱۲ مهر ماه", 12), ("گزارش تا ۱۲ مهر ۱۴۰۵", 12),
      ("گزارش تا ۵ مارس", captureDayOffset("2027-03-05")), ("گزارش تا ٥ مارس", captureDayOffset("2027-03-05")),
      ("گزارش تا جمعه ۱۲ مهر", 12),
      ("گزارش مهلت: جمعه", 3), ("گزارش مهلت جمعه", 3), ("گزارش مهلت تحویل: جمعه", 3), ("گزارش ددلاین ۱۲ مهر", 12),
      ("گزارش ددلاین: فردا", 1), ("گزارش سررسید فردا", 1), ("گزارش موعد تحویل جمعه", 3), ("گزارش آخرین مهلت پنجشنبه", 2),
      ("گزارش تاریخ سررسید ۱۲ مهر", 12), ("گزارش تاریخ تحویل جمعه", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "گزارش", "\(line.text): title")
    }
    let both = parse("فردا گزارش بنویس تا جمعه")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "گزارش بنویس")
    // A day after "بعد از" or "از" is no deadline.
    expectLinesUnread(["گزارش بعد از جمعه", "گزارش از فردا", "گزارش پس از فردا"], languages: ["fa"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "گزارش تا ساعت ۱۸:۰۰", "گزارش قبل از ساعت ۱۸:۰۰", "گزارش تا ۱۸:۰۰", "گزارش قبل از ۱۸:۰۰", "گزارش پیش از ۱۸:۰۰",
        "گزارش بعد از ساعت ۵:۳۰", "گزارش قبل از ساعت ۵", "گزارش تا ساعت ۵", "گزارش بعد از ساعت ۵",
        "گزارش قبل از ساعت ۵ عصر", "گزارش تا ساعت ۵ عصر", "گزارش تا ساعت پنج", "گزارش پس از ساعت ۵",
        "گزارش تا ساعت ١٨:٠٠",
      ], languages: ["fa"])
    // The day before a clock deadline is the due day, and the clock stays.
    let day = parse("گزارش جمعه تا ساعت ۵")
    #expect(day.dueDayOffset == 3)
    #expect(day.plannedDayOffset == nil)
    #expect(day.startMinutes == nil)
    #expect(day.title == "گزارش تا ساعت ۵")
    let tomorrow = parse("گزارش فردا قبل از ساعت ۱۸:۰۰")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.startMinutes == nil)
    #expect(tomorrow.title == "گزارش قبل از ساعت ۱۸:۰۰")
    let between = parse("گزارش تا جمعه ساعت ۵")
    #expect(between.dueDayOffset == 3)
    #expect(between.startMinutes == nil)
    #expect(between.title == "گزارش تا ساعت ۵")
    // A time range that ends in a clock time is still a range.
    let range = parse("جلسه از ۱۴ تا ۱۸:۰۰")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 240)
    #expect(range.title == "جلسه")
    // A clock deadline beside a day: the day reads, the clock stays.
    let planned = parse("گزارش تا ساعت ۱۸:۰۰ فردا")
    #expect(planned.plannedDayOffset == 1)
    #expect(planned.startMinutes == nil)
    #expect(planned.title == "گزارش تا ساعت ۱۸:۰۰")
  }

  // MARK: - Clock times

  @Test("Clock times: ساعت, a part of the day, a fraction of the hour, minutes to the hour, and midnight")
  func times() {
    let times: [(text: String, minutes: Int)] = [
      ("جلسه ساعت ۵", 17 * 60), ("جلسه ساعت ۵:۳۰", 17 * 60 + 30), ("جلسه ساعت ۱۷", 17 * 60),
      ("جلسه ساعت ۱۷:۳۰", 17 * 60 + 30), ("جلسه ساعت ۱۷.۳۰", 17 * 60 + 30), ("جلسه ساعت پنج", 17 * 60),
      ("جلسه ساعت ۷", 7 * 60), ("جلسه ساعت ۱۰", 10 * 60), ("جلسه ساعت ۱۲", 12 * 60), ("جلسه ساعت یک", 13 * 60),
      ("جلسه در ساعت ۵", 17 * 60), ("جلسه رأس ساعت ۵", 17 * 60), ("جلسه راس ساعت ۵", 17 * 60),
      ("جلسه حدود ساعت ۵", 17 * 60), ("جلسه حوالی ساعت ۵", 17 * 60), ("جلسه دقیقا ساعت ۵", 17 * 60),
      ("جلسه ساعت ۵ عصر", 17 * 60), ("جلسه ساعت ۵ بعدازظهر", 17 * 60), ("جلسه ساعت ۵ بعد از ظهر", 17 * 60),
      ("جلسه ساعت ۵ بعد‌از‌ظهر", 17 * 60), ("جلسه ساعت ۳ بعدازظهر", 15 * 60), ("جلسه ساعت ۹ صبح", 9 * 60),
      ("جلسه ساعت ۶ صبح", 6 * 60), ("جلسه ساعت ۱۰ قبل از ظهر", 10 * 60), ("جلسه ساعت ۵ سحر", 5 * 60),
      ("جلسه ساعت ۶ بامداد", 6 * 60), ("جلسه ساعت ۱۲ ظهر", 12 * 60), ("جلسه ساعت ۱ ظهر", 13 * 60),
      ("جلسه ساعت ۱ بعد از ظهر", 13 * 60), ("جلسه ساعت ۷ عصر", 19 * 60), ("جلسه ساعت ۷ غروب", 19 * 60),
      ("جلسه ساعت ۸ شب", 20 * 60), ("جلسه ساعت ۱۱ شب", 23 * 60), ("جلسه ساعت ۹ شب", 21 * 60),
      ("جلسه ساعت ۱۷ عصر", 17 * 60), ("جلسه ساعت ۱۸:۳۰ شب", 18 * 60 + 30),
      // A fraction of the hour.
      ("جلسه ساعت ۵ و نیم", 17 * 60 + 30), ("جلسه ساعت ۵ و ربع", 17 * 60 + 15), ("جلسه ساعت ۵ و ده دقیقه", 17 * 60 + 10),
      ("جلسه ساعت ۵ و ۱۰ دقیقه", 17 * 60 + 10), ("جلسه ساعت ۶ ربع کم", 17 * 60 + 45),
      ("جلسه ساعت ۶ ده دقیقه کم", 17 * 60 + 50), ("جلسه ساعت ۹ و نیم صبح", 9 * 60 + 30),
      ("جلسه ساعت ۸ و نیم شب", 20 * 60 + 30), ("جلسه ساعت یک و نیم", 13 * 60 + 30), ("جلسه ساعت ۱۲ و نیم ظهر", 12 * 60 + 30),
      // Minutes to the hour.
      ("جلسه یک ربع به ۶", 17 * 60 + 45), ("جلسه ربع به ۶", 17 * 60 + 45), ("جلسه ده دقیقه به ۶", 17 * 60 + 50),
      ("جلسه ۱۰ دقیقه به ۶", 17 * 60 + 50), ("جلسه ۱۰ دقیقه مانده به ۶", 17 * 60 + 50),
      ("جلسه بیست دقیقه به شش", 17 * 60 + 40), ("جلسه یک ربع به ۶ عصر", 17 * 60 + 45),
      ("جلسه یک ربع به ۱۰ صبح", 9 * 60 + 45), ("جلسه ساعت ۱۰ دقیقه به ۶", 17 * 60 + 50),
      ("جلسه ساعت ده دقیقه به شش", 17 * 60 + 50), ("جلسه ساعت یک ربع به ۶", 17 * 60 + 45),
      ("جلسه ساعت ۵ دقیقه به ۶", 17 * 60 + 55), ("جلسه یک ربع به ۱", 12 * 60 + 45),
      // An hour with a part of the day and no "ساعت".
      ("جلسه ۸ شب", 20 * 60), ("جلسه ۹ صبح", 9 * 60), ("جلسه ۸:۳۰ شب", 20 * 60 + 30), ("جلسه ۵ عصر", 17 * 60),
      ("جلسه ۱۰ صبح", 10 * 60), ("جلسه در ۸ شب", 20 * 60), ("جلسه ۱۲ ظهر", 12 * 60), ("جلسه ۸ و نیم شب", 20 * 60 + 30),
      ("جلسه ۵ بعدازظهر", 17 * 60), ("جلسه ۳ بعد از ظهر", 15 * 60),
      // An hour and a half or a quarter at the end of the line.
      ("جلسه ۵ و نیم", 17 * 60 + 30), ("جلسه ۸ و ربع", 8 * 60 + 15),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "جلسه", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
    }
    // A time and its day, in either order.
    let dayFirst = parse("تماس جمعه ساعت ۱۰ صبح")
    #expect(dayFirst.plannedDayOffset == 3)
    #expect(dayFirst.startMinutes == 10 * 60)
    #expect(dayFirst.title == "تماس")
    let timeFirst = parse("تماس ساعت ۱۰ صبح جمعه")
    #expect(timeFirst.plannedDayOffset == 3)
    #expect(timeFirst.startMinutes == 10 * 60)
    #expect(timeFirst.title == "تماس")
    // The time opens the line.
    let opening = parse("ساعت ۹ صبح جلسه")
    #expect(opening.startMinutes == 9 * 60)
    #expect(opening.title == "جلسه")
    // A time with its own part of the day does not take the day phrase's.
    let own = parse("جلسه فردا صبح ساعت ۸ شب")
    #expect(own.startMinutes == 20 * 60)
    #expect(own.plannedDayOffset == 1)
  }

  @Test("After midnight: the night runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("جلسه ساعت ۲ شب")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "جلسه")
    for text in ["جلسه ساعت ۱۲ شب", "جلسه در نیمه‌شب", "جلسه رأس نیمه شب", "جلسه ساعت نیمه‌شب", "جلسه ۱۲ شب"] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == 0, "\(text)")
      #expect(parsed.plannedDayOffset == 1, "\(text): planned day")
      #expect(parsed.title == "جلسه", "\(text): title")
    }
    // A named day keeps the time on its own night.
    let named = parse("جلسه جمعه ساعت ۲ شب")
    #expect(named.startMinutes == 2 * 60)
    #expect(named.plannedDayOffset == 4)
    // 12 in the morning or the evening is no time.
    expectLinesUnread(["جلسه ساعت ۱۲ صبح", "جلسه ساعت ۱۲ عصر", "جلسه ساعت ۱۳ صبح"], languages: ["fa"])
    // The night names no hour from 1 to 5 without "ساعت": "۳ شب" counts nights.
    expectLinesUnread(["سفر ۳ شب", "هتل ۲ شب"], languages: ["fa"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("جلسه ساعت ۳").startMinutes == 15 * 60)
    #expect(parse("جلسه ساعت ۶").startMinutes == 18 * 60)
    #expect(parse("جلسه ساعت ۷").startMinutes == 7 * 60)
    #expect(parse("جلسه ساعت ۹").startMinutes == 9 * 60)
    #expect(parse("جلسه ساعت ۱۲").startMinutes == 12 * 60)
    #expect(parse("جلسه ساعت ۰۶:۳۰").startMinutes == 6 * 60 + 30)
    #expect(parse("جلسه ساعت ۰۳:۰۰").startMinutes == 3 * 60)
    #expect(parse("جلسه ساعت ۳:۰۰").startMinutes == 15 * 60)
    #expect(parse("جلسه ساعت ۱۳:۰۰").startMinutes == 13 * 60)
    expectLinesUnread(["جلسه ساعت ۲۴:۰۰", "جلسه ساعت ۲۵", "جلسه ساعت ۷:۶۱"], languages: ["fa"])
  }

  @Test("Time ranges: از with تا or الی, بین with و or تا, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("جلسه از ساعت ۲ تا ۴", 14 * 60, 120), ("جلسه ساعت ۲ تا ۴", 14 * 60, 120), ("جلسه ساعت ۲ الی ۴", 14 * 60, 120),
      ("جلسه از ساعت ۲ الی ۴", 14 * 60, 120), ("جلسه از ساعت ۲ تا ساعت ۴", 14 * 60, 120),
      ("جلسه از ۹ صبح تا ۵ بعدازظهر", 9 * 60, 480), ("جلسه از ۹ صبح تا ۵ بعد از ظهر", 9 * 60, 480),
      ("جلسه از ساعت ۹ صبح تا ۵ عصر", 9 * 60, 480), ("جلسه از ۲ تا ۴ عصر", 14 * 60, 120),
      ("جلسه بین ساعت ۲ و ۴", 14 * 60, 120), ("جلسه بین ساعت ۲ تا ۴", 14 * 60, 120), ("جلسه ساعت ۲-۴", 14 * 60, 120),
      ("جلسه از ساعت ۱۴:۰۰ تا ۱۶:۰۰", 14 * 60, 120), ("جلسه ۱۴:۰۰ تا ۱۶:۰۰", 14 * 60, 120),
      ("جلسه ۹:۳۰ الی ۱۰:۳۰", 9 * 60 + 30, 60), ("جلسه از ۱۴:۰۰ تا ۱۶:۳۰", 14 * 60, 150),
      ("جلسه از ساعت ۸ صبح تا ۱۰ صبح", 8 * 60, 120), ("جلسه از ساعت ۷ تا ۹ شب", 19 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "جلسه", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Two bare hours are as often an amount or numbered items: a range needs
    // "ساعت", a part of the day, or a colon.
    expectLinesUnread(
      [
        "جلسه از ۲ تا ۴", "جلسه از ۱۴ تا ۱۶", "جلسه از ۱۴ تا ۱۶ صفحه", "جلسه بین ۲ و ۴", "کتاب صفحه ۱۴ تا ۱۶",
        "جلسه ۳ نفر تا ۵ نفر",
      ], languages: ["fa"])
    // A length written beside a range wins over the range's own.
    let both = parse("جلسه از ساعت ۲ تا ۴ به مدت ۳۰ دقیقه")
    #expect(both.startMinutes == 14 * 60)
    #expect(both.estimatedMinutes == 30)
    // English reads a range with a dash and no Persian word.
    let bare = parse("جلسه 14:00-16:00")
    #expect(bare.startMinutes == 14 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A bare number is no hour; a number before a sign or a word for a thing counted is an amount")
  func bareHours() {
    expectLinesUnread(
      [
        "جلسه ۳", "جلسه با ۳ نفر", "جلسه ٣ نفر", "ملاقات ۳ بیمار", "خرید ۲ کیلو", "خرید ۲ و نیم کیلو",
        "خرید ساعت مچی", "قیمت ۵۰ هزار تومان", "جلسه ساعت", "جلسه ساعت پنجم", "ساعت", "جلسه ساعت ۲۵", "کلاس ساعت‌سازی",
        "ساعت دیواری",
      ], languages: ["fa"])
    // A weekday after "ساعت" is the day; the hour word stays in the title.
    let weekday = parse("جلسه ساعت یکشنبه")
    #expect(weekday.startMinutes == nil)
    #expect(weekday.plannedDayOffset == 5)
    #expect(weekday.title == "جلسه ساعت")
    // The words around a bare count keep their place beside a time that is one.
    let people = parse("جلسه ۵ نفر ساعت ۳")
    #expect(people.startMinutes == 15 * 60)
    #expect(people.title == "جلسه ۵ نفر")
    let percent = parse("تخفیف ۲۰٪ ساعت ۳")
    #expect(percent.startMinutes == 15 * 60)
    #expect(percent.title == "تخفیف ۲۰٪")
    // A time that a sign or a fraction follows is an amount.
    expectLinesUnread(["نمره ساعت ۳٪", "وزن ساعت ۵.۵ کیلو"], languages: ["fa"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("مطالعه ۲۰ دقیقه", 20), ("مطالعه ٢٠ دقیقه", 20), ("مطالعه 20 دقیقه", 20), ("مطالعه ۲۰ دقيقه", 20),
      ("مطالعه ۲۰ دقیقه‌ای", 20), ("مطالعه بیست دقیقه", 20), ("مطالعه پنج دقیقه", 5), ("مطالعه ۹۰ دقیقه", 90),
      ("مطالعه بیست و پنج دقیقه", 25), ("مطالعه سی دقیقه", 30), ("مطالعه ۲ ساعت", 120), ("مطالعه دو ساعت", 120),
      ("مطالعه ۲ ساعته", 120), ("مطالعه یک ساعت", 60), ("مطالعه ۱٫۵ ساعت", 90), ("مطالعه ۱.۵ ساعت", 90),
      ("مطالعه ۲ ساعت و ۳۰ دقیقه", 150), ("مطالعه دو ساعت و سی دقیقه", 150), ("مطالعه ۲ ساعت و نیم", 150),
      ("مطالعه دو ساعت و نیم", 150), ("مطالعه یک ساعت و نیم", 90), ("مطالعه یک ساعت و ربع", 75),
      ("مطالعه دو و نیم ساعت", 150), ("مطالعه ۲ و نیم ساعت", 150), ("مطالعه نیم ساعت", 30), ("مطالعه نیم‌ساعت", 30),
      ("مطالعه نیمساعت", 30), ("مطالعه ربع ساعت", 15), ("مطالعه یک ربع", 15), ("مطالعه سه ربع", 45),
      ("مطالعه سه ربع ساعت", 45), ("مطالعه به مدت ۲۰ دقیقه", 20), ("مطالعه مدت ۲۰ دقیقه", 20),
      ("مطالعه حدود ۲۰ دقیقه", 20), ("مطالعه حدود یک ساعت", 60), ("مطالعه تقریباً ۲۰ دقیقه", 20),
      ("مطالعه نزدیک ۲۰ دقیقه", 20), ("مطالعه برای ۲۰ دقیقه", 20), ("مطالعه به مدت ۲ ساعت", 120),
      ("مطالعه ۲۰ دقیقه", 20),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "مطالعه", "\(line.text): title")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
    }
    #expect(parse("مطالعه به مدت ۲۰ دقیقه").phrases.map(\.text) == ["به مدت ۲۰ دقیقه"])
    // A length and a time together.
    let both = parse("جلسه ساعت ۳ بعدازظهر به مدت ۴۵ دقیقه")
    #expect(both.startMinutes == 15 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "جلسه")
  }

  @Test("An amount that is a moment, an interval, a rate, or a bound is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, or a bound.
        "مطالعه بعد از ۱۵ دقیقه", "مطالعه پس از ۲ ساعت", "ورزش هر ۲ ساعت", "ورزش هر ۱۵ دقیقه", "مطالعه تا ۲ ساعت",
        "مطالعه حداقل ۲ ساعت", "مطالعه حداکثر ۲ ساعت", "مطالعه کمتر از ۲ ساعت", "مطالعه بیش از ۲ ساعت",
        "مطالعه ظرف ۲ ساعت", "مطالعه طی ۲ ساعت", "مطالعه در ۲ ساعت",
        // The past, what is left, and a rate.
        "مطالعه ۲ ساعت پیش", "مطالعه ۱۰ دقیقه دیگر", "مطالعه ۱۰ دقیقه مانده", "مطالعه ۲ ساعت در روز",
        "مطالعه ۲ ساعت هر روز", "مطالعه روزی ۲ ساعت", "مطالعه ماهی ۲ ساعت", "مطالعه ۲ ساعت قبل از خواب",
        // A range of amounts, and an hour as a noun.
        "مطالعه ۲-۳ ساعت", "مطالعه ۲ تا ۳ ساعت", "مطالعه ساعت", "مطالعه دقیقه",
      ], languages: ["fa"])
    // The phrase around an amount that is no length still reads.
    let day = parse("تماس بعد از ۱۵ دقیقه فردا")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "تماس بعد از ۱۵ دقیقه")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let daily = TaskRecurrenceRule(freq: .daily)
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("ورزش هر روز", daily), ("ورزش هر صبح", daily),
      ("ورزش هر روز صبح", daily), ("ورزش هر شب", daily), ("ورزش هر عصر", daily), ("ورزش صبح‌ها", daily),
      ("ورزش شب‌ها", daily), ("ورزش، روزانه", daily), ("روزانه ورزش", daily), ("ورزش روزی یک بار", daily), ("ورزش، هر روزه", daily),
      ("هر روزه ورزش", daily), ("ورزش، همه روزه", daily),
      ("ورزش هر هفته", weekly), ("ورزش هفته‌ای یک بار", weekly), ("ورزش هفته ای یک بار", weekly), ("ورزش، هفتگی", weekly),
      ("ورزش هر ماه", monthly), ("ورزش ماهی یک بار", monthly), ("ورزش، ماهانه", monthly), ("ورزش ماهی فقط یک بار", monthly),
      ("ورزش هر سال", yearly), ("ورزش سالی یک بار", yearly), ("ورزش، سالانه", yearly),
      ("ورزش هر ۲ روز", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ورزش هر دو روز", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ورزش هر دو روز یک بار", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ورزش هر ٣ روز", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("ورزش هر سه روز", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("ورزش هر ده روز", TaskRecurrenceRule(freq: .daily, interval: 10)),
      ("ورزش هر پانزده روز", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("ورزش هر ۱۵ روز", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("ورزش یک روز در میان", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ورزش روز در میان", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ورزش هر دو هفته", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ورزش هر ۳ هفته", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("ورزش دو هفته یک بار", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ورزش هر دو هفته یک بار", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ورزش هر هفته در میان", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ورزش هر دو ماه", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("ورزش هر ۳ ماه", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ورزش ۳ ماه یک بار", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ورزش یک ماه در میان", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("ورزش هر دو سال", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("ورزش هر ۵ سال", TaskRecurrenceRule(freq: .yearly, interval: 5)),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "ورزش", "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
  }

  @Test("Weekday repeats: هر دوشنبه, روزهای دوشنبه, دوشنبه‌ها, lists, and spans")
  func weekdayRepeats() {
    let coming = parse("ورزش هر دوشنبه")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "ورزش")
    #expect(coming.plannedDayOffset == nil)

    let lists: [(text: String, days: [String])] = [
      ("ورزش هر دوشنبه", ["MO"]), ("ورزش هر روز دوشنبه", ["MO"]), ("ورزش هر هفته دوشنبه", ["MO"]),
      ("ورزش هر شنبه", ["SA"]), ("ورزش هر یکشنبه", ["SU"]), ("ورزش هر یک‌شنبه", ["SU"]), ("ورزش هر یک شنبه", ["SU"]),
      ("ورزش هر سه‌شنبه", ["TU"]), ("ورزش هر سه شنبه", ["TU"]), ("ورزش هر سهشنبه", ["TU"]),
      ("ورزش هر چهارشنبه", ["WE"]), ("ورزش هر پنج‌شنبه", ["TH"]), ("ورزش هر پنجشنبه", ["TH"]),
      ("ورزش هر جمعه", ["FR"]), ("ورزش هر آدینه", ["FR"]),
      ("ورزش هر دوشنبه و پنجشنبه", ["MO", "TH"]), ("ورزش هر دوشنبه و هر پنجشنبه", ["MO", "TH"]),
      ("ورزش هر دوشنبه، چهارشنبه و جمعه", ["MO", "WE", "FR"]), ("ورزش هر دوشنبه و یکشنبه", ["SU", "MO"]),
      ("ورزش هر صبح جمعه", ["FR"]), ("ورزش هر عصر چهارشنبه", ["WE"]),
      ("ورزش روزهای دوشنبه و چهارشنبه", ["MO", "WE"]), ("ورزش همه روزهای دوشنبه و چهارشنبه", ["MO", "WE"]),
      ("ورزش دوشنبه‌ها", ["MO"]), ("ورزش دوشنبه ها", ["MO"]), ("ورزش همه دوشنبه‌ها و پنجشنبه‌ها", ["MO", "TH"]),
      ("ورزش دوشنبه‌ها و پنجشنبه‌ها", ["MO", "TH"]), ("ورزش دوشنبه و پنجشنبه هر هفته", ["MO", "TH"]),
      ("ورزش پنجشنبه هر هفته", ["TH"]),
      // A span runs from its first weekday to its last through the week's end.
      ("ورزش هر روز از دوشنبه تا جمعه", ["MO", "TU", "WE", "TH", "FR"]),
      ("ورزش از دوشنبه تا جمعه هر روز", ["MO", "TU", "WE", "TH", "FR"]),
      ("ورزش روزهای دوشنبه تا جمعه", ["MO", "TU", "WE", "TH", "FR"]),
      ("ورزش هر دوشنبه تا جمعه", ["MO", "TU", "WE", "TH", "FR"]),
      ("ورزش روزانه دوشنبه تا جمعه", ["MO", "TU", "WE", "TH", "FR"]),
      ("ورزش روزهای شنبه تا چهارشنبه", ["SU", "MO", "TU", "WE", "SA"]),
      ("ورزش از شنبه تا چهارشنبه هر روز", ["SU", "MO", "TU", "WE", "SA"]),
      ("ورزش هر روز از جمعه تا دوشنبه", ["SU", "MO", "FR", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "ورزش", "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // Every other weekday.
    let other = parse("ورزش یک دوشنبه در میان")
    #expect(other.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))
    #expect(other.title == "ورزش")
    // The start of a repeat on Thursday and Monday is the nearer one, and a span that holds today starts today.
    #expect(parse("ورزش هر دوشنبه و پنجشنبه").recurrenceStartOffset == 2)
    #expect(parse("ورزش روزهای شنبه تا چهارشنبه").recurrenceStartOffset == 0)
    #expect(parse("ورزش هر روز از جمعه تا دوشنبه").recurrenceStartOffset == 3)
    // A weekday with a time.
    let evening = parse("تمرین هر دوشنبه ساعت ۷ عصر")
    #expect(evening.recurrence == monday)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "تمرین")
    // A weekday repeat on that weekday itself starts today.
    #expect(parse("ورزش هر جمعه", on: "2026-09-25").recurrenceStartOffset == 0)
    // A part of the day with a daily repeat keeps its hour.
    let morning = parse("ورزش هر صبح ساعت ۶")
    #expect(morning.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "ورزش")
    let night = parse("مرور هر شب ساعت ۱۰")
    #expect(night.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(night.startMinutes == 22 * 60)
  }

  @Test("A cadence adverb repeats opening the line or ending it after a comma; an adjective stays in the title")
  func cadenceAdverbs() {
    let opening = parse("روزانه ۳۰ دقیقه ورزش")
    #expect(opening.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(opening.estimatedMinutes == 30)
    #expect(opening.title == "ورزش")
    let ending = parse("مرور ایمیل، روزانه")
    #expect(ending.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(ending.title == "مرور ایمیل")
    let withTime = parse("مرور، روزانه، ساعت ۸ شب")
    #expect(withTime.recurrence == TaskRecurrenceRule(freq: .daily))
    #expect(withTime.startMinutes == 20 * 60)
    #expect(parse("مرور، ماهانه").recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(parse("هفتگی مرور").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(parse("مرور، سالانه").recurrence == TaskRecurrenceRule(freq: .yearly))
    expectLinesUnread(
      [
        // After the task's noun the word is its adjective.
        "ورزش روزانه", "گزارش روزانه", "جلسه هفتگی", "گزارش ماهانه", "هزینه سالانه", "مرور روزانه ایمیل", "ورزش هر روزه",
        "ورزش همه روزه",
        // An interval shorter than a day, and a cadence beside a day of the month.
        "مرور هر ۲ ساعت", "مرور هر ساعت", "مرور هر ۱۵ دقیقه", "اجاره هر ماه ۵ام", "اجاره ۵ام هر ماه", "اجاره هر ماه روز ۵",
        "اجاره روز ۱۵ هر ماه",
        // A part of the day before a weekday is that day's, and "هر دو" is "both".
        "ورزش هر شب جمعه", "خرید هر دو کتاب", "خرید هر سه نفر", "تماس هر چهار نفر",
      ], languages: ["fa"])
  }

  // MARK: - Priorities

  @Test("Priorities")
  func priorities() {
    let high = parse("تماس با بانک اولویت بالا")
    #expect(high.priority == .p1)
    #expect(high.title == "تماس با بانک")
    let priorities: [(text: String, priority: LorvexTask.Priority)] = [
      ("گزارش اولویت بالا", .p1), ("گزارش با اولویت بالا", .p1), ("گزارش اولویت: بالا", .p1),
      ("گزارش اولویت بسیار بالا", .p1), ("گزارش اولویت خیلی بالا", .p1), ("گزارش اولویت زیاد", .p1),
      ("گزارش اولویت متوسط", .p2), ("گزارش اولویت معمولی", .p2), ("گزارش اولویت نرمال", .p2),
      ("گزارش اولویت پایین", .p3), ("گزارش اولویت کم", .p3), ("گزارش اولویت کمتر", .p3),
      ("گزارش اولویت خیلی پایین", .p3), ("گزارش با اولویت پایین", .p3), ("گزارش اولویت بسیار پایین", .p3),
      ("گزارش فوری", .p1), ("گزارش خیلی فوری", .p1), ("گزارش بسیار فوری", .p1),
      ("گزارش اولویت بالا", .p1), ("گزارش اُولَویَت بالا", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == "گزارش", "\(line.text): title")
    }
    let opening = parse("فوری: تماس با لوله‌کش")
    #expect(opening.priority == .p1)
    #expect(opening.title == "تماس با لوله‌کش")
    #expect(parse("فوری، تماس با لوله‌کش").priority == .p1)
    // Without a colon or comma an opening "فوری" is a title word, and so is one in the middle.
    let word = parse("فوری تماس")
    #expect(word.priority == nil)
    #expect(word.title == "فوری تماس")
    #expect(parse("کار فوری دارم").priority == nil)
    #expect(parse("تماس فوری با مادر").priority == nil)
    #expect(parse("گزارش مهم").priority == nil)
    #expect(parse("گزارش اولویت ۱").priority == nil)
    #expect(parse("گزارش اولویت").priority == nil)
    // English priorities read beside Persian.
    #expect(parse("جلسه !!").priority == .p1)
    #expect(parse("جلسه p2").priority == .p2)
    #expect(parse("گزارش urgent").priority == .p1)
  }

  // MARK: - Words that look like details

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // A day, a part of the day, or a period inside a longer word.
        "خرید صبحانه", "خرید عصرانه", "مقاله ویژگی‌های امروزی", "فیلم فردایی", "مقاله امروزه", "کلاس شبانه",
        "برنامه صبح‌گاهی", "کتاب هفته‌نامه", "جلسه هفته‌ها", "مهمانی شبنم",
        // A month or a weekday that names a thing or a person.
        "تماس با آبان", "نقاشی تیر و کمان", "مهر و موم", "جلسه آذر ۵", "اول مهر", "پانزده خرداد", "کتاب دی",
        // A duration or a count with no moment.
        "مرخصی ۲ هفته", "سفر ۵ روز", "تمرین ۳ روز", "خرید ۳ کتاب", "شام ۴ نفر",
        // An hour as a thing, and numbers that are no hour.
        "خرید ساعت مچی", "تعمیر ساعت دیواری", "صفحه ۱۴ تا ۱۶", "کتاب ۱۲۳",
      ], languages: ["fa"])
    // A day with its own phrase and "امشب" still read.
    #expect(parse("تماس امشب ساعت ۸").plannedDayOffset == 0)
    #expect(parse("تماس امشب ساعت ۸").startMinutes == 20 * 60)
  }

  // MARK: - Spellings

  @Test("Digits in the Arabic-Indic and Extended scripts read as the digits they stand for")
  func digitScripts() {
    let lines = [
      "جلسه ساعت 3:30 عصر", "جلسه ساعت 15:30", "جلسه از ساعت 2 تا 4", "مطالعه 20 دقیقه", "مطالعه 1.5 ساعت",
      "مطالعه 2 ساعت و 30 دقیقه", "ورزش هر 3 روز", "زیارت 12 مهر 1405", "زیارت 5 مارس 2027", "زیارت 3 روز دیگر",
      "مرخصی از 3 تا 5 آبان", "مرخصی 3-5 آبان", "گزارش تا 12 مهر", "جلسه ساعت 9 شب", "جلسه 8 و نیم شب",
      "جلسه ده دقیقه به 6", "جلسه ساعت 5 و 10 دقیقه", "ورزش هر 2 هفته", "ورزش هر 5 سال",
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

  @Test("Vowel signs, tatweel, and the Arabic spellings of yeh, kaf, alef, and heh change nothing")
  func spellings() {
    let tomorrow = [
      "تماس با مادر فردا", "تماس با مادر فَردا", "تماس با مادر فـردا", "تماس با مادر فــــردا", "تماس با مادر فردَا",
    ]
    for text in tomorrow {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.title == "تماس با مادر", "\(text): title")
    }
    // The title keeps the letters and signs as typed.
    let signs = parse("تَماسْ با مادر فردا")
    #expect(signs.title == "تَماسْ با مادر")
    // A letter written as another form of it: Arabic yeh or alef maksura for yeh, Arabic kaf for kaf, alef with or
    // without its madda, teh marbuta or heh with yeh above for heh.
    #expect(parse("تماس با مادر هفته‌ي آينده").plannedDayOffset == 7)
    #expect(parse("تماس با مادر هفتۀ آینده").plannedDayOffset == 7)
    #expect(parse("تماس با مادر اینده").plannedDayOffset == nil)
    #expect(parse("تماس با مادر هفته اینده").plannedDayOffset == 7)
    #expect(parse("تماس با مادر هفته آينده").plannedDayOffset == 7)
    #expect(parse("تماس با مادر ٣ روز ديگر").plannedDayOffset == 3)
    #expect(parse("تماس با مادر يكشنبه").plannedDayOffset == 5)
    #expect(parse("جلسه ساعت ٥ عصر").startMinutes == 17 * 60)
    #expect(parse("جلسه ساعت ٥ عصر").title == "جلسه")
    #expect(parse("جلسه ساعت ٥ بعدازظهر").startMinutes == 17 * 60)
    #expect(parse("مطالعه ۲۰ دقيقه").estimatedMinutes == 20)
    #expect(parse("مطالعه ۲۰ دقیقة").estimatedMinutes == 20)
    #expect(parse("گزارش تا جمعة").dueDayOffset == 3)
    #expect(parse("گزارش قبل از جمعه").dueDayOffset == 3)
    #expect(parse("گزارش تا آخر روز").dueDayOffset == 0)
    #expect(parse("گزارش تا اخر روز").dueDayOffset == 0)
    #expect(parse("ورزش هر دو شنبه").recurrence == monday)
    #expect(parse("ورزش هر يوم").recurrence == nil)
    #expect(parse("گزارش اولويت بالا").priority == .p1)
    // The spoken forms of a few words.
    #expect(parse("مطالعه یه ربع").estimatedMinutes == 15)
    #expect(parse("تماس با مادر یه هفته دیگه").plannedDayOffset == 7)
    #expect(parse("ورزش یه روز در میان").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    // A mark never splits a match from the letter it follows.
    let marked = parse("جلسه ساعت ۳ عصر مهم")
    #expect(marked.startMinutes == 15 * 60)
    #expect(marked.title == "جلسه مهم")
  }

  @Test("A zero-width non-joiner or joiner inside a compound word, or none, changes nothing")
  func joiners() {
    for text in ["پس‌فردا", "پس فردا", "پسفردا", "پس\u{200D}فردا", "پس‌ فردا"] {
      let parsed = parse("تماس با مادر \(text)")
      #expect(parsed.plannedDayOffset == 2 || text == "پس‌ فردا", "\(text)")
    }
    for text in ["اردی‌بهشت", "اردیبهشت", "اردی بهشت", "اردی\u{200D}بهشت"] {
      let parsed = parse("زیارت ۲۳ \(text)")
      #expect(parsed.plannedDayOffset == captureDayOffset("2027-05-13"), "\(text)")
      #expect(parsed.title == "زیارت", "\(text): title")
    }
    for text in ["نیم‌ساعت", "نیم ساعت", "نیمساعت", "نیم\u{200D}ساعت"] {
      let parsed = parse("مطالعه \(text)")
      #expect(parsed.estimatedMinutes == 30, "\(text)")
      #expect(parsed.title == "مطالعه", "\(text): title")
    }
    for text in ["بعد‌از‌ظهر", "بعد از ظهر", "بعدازظهر", "بعد‌ازظهر"] {
      let parsed = parse("جلسه ساعت ۳ \(text)")
      #expect(parsed.startMinutes == 15 * 60, "\(text)")
      #expect(parsed.title == "جلسه", "\(text): title")
    }
    for text in ["هفته‌ای یک‌بار", "هفته ای یک بار", "هفتهای یکبار", "هفته‌ای یک بار"] {
      let parsed = parse("ورزش \(text)")
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly), "\(text)")
      #expect(parsed.title == "ورزش", "\(text): title")
    }
    for text in ["دوشنبه‌ها", "دوشنبه ها", "دوشنبهها"] {
      #expect(parse("ورزش \(text)").recurrence == monday, "\(text)")
    }
    // Words that Persian writes apart may be typed with a joiner between them.
    for text in ["قبل از", "قبل‌از", "پیش از", "پیش‌از"] {
      let parsed = parse("گزارش \(text) جمعه")
      #expect(parsed.dueDayOffset == 3, "\(text)")
      #expect(parsed.title == "گزارش", "\(text): title")
    }
    expectLinesUnread(["گزارش بعد‌از جمعه", "گزارش پس‌از جمعه", "مطالعه بعد‌از ۱۵ دقیقه"], languages: ["fa"])
    for text in ["یک ربع", "یک‌ربع"] {
      #expect(parse("مطالعه \(text)").estimatedMinutes == 15, "\(text)")
    }
    for text in ["به مدت", "به‌مدت"] {
      #expect(parse("مطالعه \(text) ۲۰ دقیقه").estimatedMinutes == 20, "\(text)")
    }
    // A word that continues past its first letters with a joiner is another word.
    expectLinesUnread(["مقاله امروز‌های", "مقاله فردا‌ها", "جلسه جمعه‌ی خوب"], languages: ["fa"])
  }

  @Test("The Persian comma and semicolon left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("خرید شیر، فردا، ساعت ۳", "خرید شیر"),
      ("خرید شیر، فردا", "خرید شیر"),
      ("فردا، خرید شیر", "خرید شیر"),
      ("خرید شیر ؛ فردا", "خرید شیر"),
      ("فردا ؛ خرید شیر", "خرید شیر"),
      ("فردا: خرید شیر", "خرید شیر"),
      ("خرید شیر - فردا", "خرید شیر"),
      ("خرید شیر ,  فردا , ساعت ۳ بعدازظهر", "خرید شیر"),
      ("خرید شیر ، فردا ، ساعت ۳ بعدازظهر ، اولویت بالا", "خرید شیر"),
      ("خرید شیر، و نان فردا", "خرید شیر، و نان"),
      ("خرید شیر، فردا، و نان", "خرید شیر، و نان"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
  }

  @Test("A title never gains a bidirectional control character")
  func noBidiControls() {
    let controls: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
    for text in [
      "تماس با مادر فردا ساعت ۳ بعدازظهر", "گزارش ۱۲ مهر به مدت ۲۰ دقیقه", "ورزش هر دوشنبه و پنجشنبه", "جلسه with Ahmed فردا",
      "خرید شیر، فردا، اولویت بالا #فهرست",
    ] {
      let title = parse(text).title
      #expect(!title.unicodeScalars.contains { controls.contains($0.value) }, "\(text)")
    }
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    #expect(parse("تماس با مادر فردا").plannedDayOffset == 1)
    #expect(parse("تماس با مادر ساعت ۳ بعدازظهر").startMinutes == 15 * 60)
    #expect(parse("تماس با مادر هر دوشنبه").recurrence == monday)
    #expect(parse("تماس با مادر ۲۰ دقیقه").estimatedMinutes == 20)
    #expect(parse("تماس با مادر #فهرست").tags == ["فهرست"])
  }

  // MARK: - English and other languages

  @Test("Beside Persian, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "fa"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "fa"]).estimatedMinutes == 20)
    #expect(parse("جلسه 2h").estimatedMinutes == 120)
    #expect(parse("جلسه 30min").estimatedMinutes == 30)
    #expect(parse("جلسه 1h30m").estimatedMinutes == 90)
    let at = parse("Call mom at 3pm", languages: ["en", "fa"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "fa"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "fa"]).plannedDayOffset == 1)
    // English lines read the same with Persian beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "fa"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("تماس با مادر فردا at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "تماس با مادر")
    let weekday = parse("Meeting پنجشنبه at 3pm")
    #expect(weekday.plannedDayOffset == 2)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("جلسه tomorrow ساعت ۳ بعدازظهر")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 15 * 60)
    #expect(reversed.title == "جلسه")
    // A colon time with no Persian word is English's, in any digit script.
    #expect(parse("جلسه 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("جلسه ۱۷:۳۰").startMinutes == 17 * 60 + 30)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // Watches counted in hours read as a length.
    #expect(parse("خرید ۲ ساعت مچی").estimatedMinutes == 120)
    // "امروز" is today in "today's report" too.
    #expect(parse("گزارش امروز").plannedDayOffset == 0)
    // A weekday after a part of the day is a day in a title.
    let class_ = parse("کلاس عصر جمعه")
    #expect(class_.plannedDayOffset == 3)
    #expect(class_.title == "کلاس")
    // "یک دقیقه" is a length of one minute where it asks for a moment's wait.
    #expect(parse("صبر یک دقیقه").estimatedMinutes == 1)
    // An hour and a half at the end of the line is a time where it counts something.
    #expect(parse("خرید ۵ و نیم").startMinutes == 17 * 60 + 30)
  }

  @Test("Persian words are read only for a user who reads Persian")
  func languageGate() {
    let line = parse("تماس با مادر فردا", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "تماس با مادر فردا")
    for languages in [["fa"], ["fa-IR"], ["fa_AF"], ["fa-AF", "en-US"], ["en-US", "fa-IR"], ["FA"], ["ar", "fa"]] {
      #expect(parse("تماس با مادر فردا", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages' readers do not get Persian words, and Persian readers do not get theirs.
    for languages in [["ar"], ["he"], ["hi"], ["ur"], ["tr"], ["ru"], ["ja"]] {
      #expect(parse("تماس با مادر فردا", languages: languages).plannedDayOffset == nil, "\(languages)")
    }
    #expect(parse("اتصل بأمي غداً", languages: ["fa"]).plannedDayOffset == nil)
    #expect(parse("Zadzwonić jutro", languages: ["fa"]).plannedDayOffset == nil)
    #expect(parse("Позвонить завтра", languages: ["fa"]).plannedDayOffset == nil)
    // A user who reads Arabic and Persian gets both, and each line reads with the vocabulary that knows its words.
    #expect(parse("اتصل بأمي غداً", languages: ["ar", "fa"]).plannedDayOffset == 1)
    #expect(parse("جلسه ساعت ۳ بعدازظهر", languages: ["ar", "fa"]).startMinutes == 15 * 60)
    // A clock time with a Persian word needs Persian among the languages.
    #expect(parse("جلسه ساعت ۳ بعدازظهر", languages: ["en"]).startMinutes == nil)
    #expect(parse("ورزش هر دوشنبه", languages: ["en"]).recurrence == nil)
    // English and Chinese are read whatever the languages.
    #expect(parse("Call mom tomorrow", languages: ["fa"]).plannedDayOffset == 1)
    #expect(parse("明天打电话", languages: ["fa"]).plannedDayOffset == 1)
  }

  @Test("Lines in other languages read the same with Persian beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"), ("تقرير قبل الخميس", "ar"),
      ("مراجعة من 3 إلى 5 مارس", "ar"), ("कल शाम 5 बजे मीटिंग", "hi"), ("रिपोर्ट सोमवार तक", "hi"),
      ("हर सोमवार योग 30 मिनट", "hi"), ("Позвонить маме завтра в 15:00", "ru"), ("Appeler maman demain à 15h", "fr"),
      ("Llamar a mamá mañana a las 15:00", "es"), ("明日の午後3時に会議", "ja"), ("Zadzwonić jutro o 15:00", "pl"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "fa"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["fa", line.language]) == alone, "\(line.text): reversed")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("ساعت ۵ ", 400), ("هر دوشنبه و ", 250), ("از ۳ تا ", 400), ("۲ ساعت و ", 350), ("یک ربع به ", 300),
      ("۱", 3000), ("ا", 3000), ("فردا", 600), ("سه‌", 1000), ("تا ", 900), ("هفته ", 500), ("پنجشنبه آینده ", 200),
      ("بعد از ظهر ", 300), ("هر ", 900), ("۱۲ مهر ", 300), ("نیم ساعت ", 300), ("، ", 1500), ("و ", 1500),
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for entry in unit {
        let line = "تماس " + String(repeating: entry.token, count: entry.repeats) + " مادر"
        let parsed = parse(line)
        #expect(!parsed.title.isEmpty, "\(entry.token)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}
