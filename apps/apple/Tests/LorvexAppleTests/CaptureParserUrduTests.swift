import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ur"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["ur"])
}

/// `text` with its ASCII digits written in the Arabic-Indic (`offset` 0x0660)
/// or the Extended Arabic-Indic (`offset` 0x06F0) script.
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
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let daily = TaskRecurrenceRule(freq: .daily)

/// Urdu capture lines, read for a user whose languages include Urdu.
@Suite("Capture parser Urdu")
struct CaptureParserUrduTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("امی کو فون کرنا کل")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "امی کو فون کرنا")
    #expect(line.phrases.map(\.text) == ["کل"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("آج", 0), ("آج سے", 0), ("کل", 1), ("کل کو", 1), ("کل سے", 1), ("آئندہ کل", 1), ("پرسوں", 2), ("پرسو", 2),
      ("3 دن بعد", 3), ("3 دنوں بعد", 3), ("تین دن بعد", 3), ("۳ دن بعد", 3), ("1 دن بعد", 1), ("ایک دن بعد", 1),
      ("10 دن بعد", 10), ("پندرہ دن بعد", 15), ("2 ہفتے بعد", 14), ("دو ہفتے بعد", 14), ("ایک ہفتے بعد", 7),
      ("ایک ہفتے کے بعد", 7), ("3 ہفتے بعد", 21), ("1 مہینے بعد", 30), ("2 مہینے بعد", 61), ("اگلے ہفتے", 7),
      ("اگلا ہفتہ", 7), ("آئندہ ہفتے", 7), ("آنے والے ہفتے", 7),
    ]
    for day in days {
      let text = "امی کو فون کرنا \(day.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day.offset, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "امی کو فون کرنا", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("کل امی کو فون کرنا")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "امی کو فون کرنا")
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("آج صبح", 0), ("آج دوپہر", 0), ("آج شام", 0), ("آج رات", 0), ("آج کی رات", 0), ("کل صبح", 1), ("کل دوپہر", 1),
      ("کل شام", 1), ("کل رات", 1), ("کل دیر رات", 1), ("کل تڑکے", 1), ("کل سویرے", 1), ("پرسوں شام", 2),
      ("جمعہ شام", 3), ("جمعہ کی شام", 3), ("ہفتے کی شام", 4), ("سنیچر صبح", 4),
    ]
    for phrase in phrases {
      let parsed = parse("فون کرنا \(phrase.text)")
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "فون کرنا", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("کل صبح میٹنگ 6 بجے")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "میٹنگ")
    let evening = parse("آج شام کو جم 7 بجے")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "جم")
    let night = parse("کل رات کھانا 9 بجے")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 21 * 60)
    #expect(night.title == "کھانا")
    let written = parse("آج رات 8 بجے کھانا")
    #expect(written.plannedDayOffset == 0)
    #expect(written.startMinutes == 20 * 60)
    #expect(written.title == "کھانا")
    // The part of the day as a noun names no day.
    expectLinesUnread(
      ["صبح کی سیر", "شام کی چائے", "رات کا کھانا", "دوپہر کا کھانا", "صبح جلدی اٹھنا", "رات کو پڑھنا"],
      languages: ["ur"])
    // A possessive after the part of the day makes it an attribute of a noun:
    // only the day is read.
    let dinner = parse("کل رات کا کھانا")
    #expect(dinner.plannedDayOffset == 1)
    #expect(dinner.title == "رات کا کھانا")
    let tea = parse("کل شام کی چائے")
    #expect(tea.plannedDayOffset == 1)
    #expect(tea.title == "شام کی چائے")
  }

  @Test("The emphatic ہی after a day, its postposition, or a deadline word goes with it")
  func dayParticle() {
    let days: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("آج ہی رپورٹ بھیجنا", "رپورٹ بھیجنا", 0, "آج ہی"),
      ("رپورٹ آج ہی بھیجنا", "رپورٹ بھیجنا", 0, "آج ہی"),
      ("رپورٹ آج ہی", "رپورٹ", 0, "آج ہی"),
      ("کل ہی جانا ہے", "جانا ہے", 1, "کل ہی"),
      ("پیر کو ہی میٹنگ", "میٹنگ", 6, "پیر کو ہی"),
      ("کل سے ہی جم شروع کرنا", "جم شروع کرنا", 1, "کل سے ہی"),
      ("3 دن بعد ہی ملنا", "ملنا", 3, "3 دن بعد ہی"),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    let due: [(text: String, title: String, offset: Int)] = [
      ("فون کرنا جمعہ تک ہی", "فون کرنا", 3),
      ("رپورٹ جمعہ تک ہی بھیجنا", "رپورٹ بھیجنا", 3),
      ("رپورٹ جمعہ سے پہلے ہی بھیجنا", "رپورٹ بھیجنا", 3),
      ("رپورٹ 5 مئی تک ہی بھیجنا", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A possessive after the particle makes the day an attribute of a noun, and
    // "آج تک ہی" is the idiom for "so far".
    expectLinesUnread(["آج ہی کی رپورٹ", "رپورٹ جمعہ تک ہی کی بات", "رپورٹ آج تک ہی"], languages: ["ur"])
  }

  @Test("دوپہر بعد after a day is the afternoon, and بعد after any other part, or before a possessive, is not")
  func afternoonAfter() {
    let afternoons: [(text: String, offset: Int, phrase: String)] = [
      ("کل دوپہر بعد میٹنگ", 1, "کل دوپہر بعد"), ("کل دوپہر کے بعد میٹنگ", 1, "کل دوپہر کے بعد"),
      ("جمعہ دوپہر بعد میٹنگ", 3, "جمعہ دوپہر بعد"), ("میٹنگ کل دوپہر بعد", 1, "کل دوپہر بعد"),
    ]
    for line in afternoons {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == "میٹنگ", "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    let hour = parse("آج دوپہر بعد 3 بجے جم")
    #expect(hour.plannedDayOffset == 0)
    #expect(hour.startMinutes == 15 * 60)
    #expect(hour.title == "جم")
    // Only the day is read; the words after it stay in the title.
    let phrases: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("کل شام کے بعد فون کرنا", "شام کے بعد فون کرنا", 1, "کل"),
      ("کل صبح کے بعد میٹنگ", "صبح کے بعد میٹنگ", 1, "کل"),
      ("آج رات کے بعد فون", "رات کے بعد فون", 0, "آج"),
      ("کل دوپہر بعد کی میٹنگ", "دوپہر بعد کی میٹنگ", 1, "کل"),
      ("کل دوپہر کے بعد کا کھانا", "دوپہر کے بعد کا کھانا", 1, "کل"),
    ]
    for line in phrases {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // A day and a part of the day alone are no task.
    expectLinesUnread(["کل دوپہر بعد", "جمعہ دوپہر بعد", "آج دوپہر"], languages: ["ur"])
  }

  @Test("Weekdays: the next one, this week's, next week's, and the coming one")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "اس منگل" is today.
    let names: [(name: String, offset: Int)] = [
      ("بدھ", 1), ("جمعرات", 2), ("جمعہ", 3), ("جمعے", 3), ("سنیچر", 4), ("اتوار", 5), ("پیر", 6), ("سوموار", 6),
      ("منگل", 7),
    ]
    for weekday in names {
      for text in ["فون کرنا \(weekday.name)", "فون کرنا \(weekday.name) کو"] {
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "فون کرنا", "\(text): title")
      }
    }
    let modified: [(text: String, offset: Int)] = [
      ("فون کرنا اس جمعہ", 3), ("فون کرنا اس منگل", 0), ("فون کرنا اس سنیچر کو", 4), ("فون کرنا اس پیر", 6),
      ("فون کرنا اگلے پیر", 6), ("فون کرنا اگلا پیر", 6), ("فون کرنا اگلے منگل", 7), ("فون کرنا اگلے جمعہ", 10),
      ("فون کرنا اگلے سنیچر", 11), ("فون کرنا اگلے اتوار", 12), ("فون کرنا آنے والے جمعہ کو", 3),
      ("فون کرنا آنے والے منگل", 7), ("فون کرنا آئندہ جمعہ", 3), ("فون کرنا اس ہفتے جمعہ", 3),
      ("فون کرنا اگلے ہفتے پیر", 6), ("فون کرنا جمعہ کے دن", 3), ("فون کرنا جمعہ کے روز", 3),
      ("فون کرنا بروز جمعہ", 3), ("فون کرنا بروز ہفتہ", 4),
      // "کے لیے" is a purpose, not a possessive, so the day is read with it.
      ("فون کرنا جمعہ کے لیے", 3), ("فون کرنا اگلے جمعہ کے لیے", 10),
    ]
    for line in modified {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text)")
      #expect(parsed.title == "فون کرنا", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let opening = parse("جمعہ کو امی کو فون کرنا")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "امی کو فون کرنا")
    // "اس ہفتے" alone names no single day.
    expectLinesUnread(["فون کرنا اس ہفتے"], languages: ["ur"])
  }

  @Test("Weeks start on Monday: the week named before a weekday is the next one")
  func weeksStartOnMonday() {
    // Tuesday 2026-09-22: the next week runs from Monday 09-28 to Sunday 10-04.
    let tuesday: [(text: String, offset: Int)] = [
      ("اگلے ہفتے پیر", 6), ("اگلے ہفتے منگل", 7), ("اگلے ہفتے بدھ", 8), ("اگلے ہفتے جمعرات", 9),
      ("اگلے ہفتے جمعہ", 10), ("اگلے ہفتے سنیچر", 11), ("اگلے ہفتے اتوار", 12), ("اگلا اتوار", 12),
      ("اس ہفتے جمعرات", 2),
    ]
    for line in tuesday {
      let text = "فون کرنا \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "فون کرنا", "\(text): title")
    }
    // Thursday 09-24: the next week begins in four days.
    for (text, offset) in [("اگلے پیر", 4), ("اگلے بدھ", 6), ("اگلے جمعرات", 7), ("اگلے جمعہ", 8), ("اگلے سنیچر", 9)] {
      #expect(parse("فون کرنا \(text)", weekday: 5, today: "2026-09-24").plannedDayOffset == offset, "Thursday: \(text)")
    }
    // Saturday 09-26: the next week begins in two days.
    #expect(parse("فون کرنا اگلے پیر", weekday: 7, today: "2026-09-26").plannedDayOffset == 2)
    #expect(parse("فون کرنا اگلے جمعہ", weekday: 7, today: "2026-09-26").plannedDayOffset == 6)
    #expect(parse("فون کرنا اگلے سنیچر", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
    #expect(parse("فون کرنا سنیچر", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
    #expect(parse("فون کرنا اس سنیچر کو", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    // Sunday 09-27 is the week's last day: the next week begins tomorrow.
    #expect(parse("فون کرنا اگلے پیر", weekday: 1, today: "2026-09-27").plannedDayOffset == 1)
    #expect(parse("فون کرنا اگلے سنیچر", weekday: 1, today: "2026-09-27").plannedDayOffset == 6)
    #expect(parse("فون کرنا اگلے اتوار", weekday: 1, today: "2026-09-27").plannedDayOffset == 7)
    // The coming one is the next such day, a full week ahead when it is today.
    #expect(parse("فون کرنا آئندہ جمعرات", weekday: 5, today: "2026-09-24").plannedDayOffset == 7)
    #expect(parse("فون کرنا اس جمعرات", weekday: 5, today: "2026-09-24").plannedDayOffset == 0)
  }

  @Test("ہفتہ and ہفتے name Saturday only beside a mark of a day, and the week otherwise")
  func saturdayOrWeek() {
    let saturdays: [(text: String, offset: Int)] = [
      ("ہفتے کو", 4), ("ہفتہ کو", 4), ("ہفتے کے دن", 4), ("ہفتے کے روز", 4), ("بروز ہفتہ", 4), ("ہفتے کی شام", 4),
      ("ہفتے کی صبح", 4), ("سنیچر", 4), ("سنیچر کو", 4),
    ]
    for line in saturdays {
      let text = "فون کرنا \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "فون کرنا", "\(text): title")
    }
    // Another weekday joined to it makes it a day of the week.
    #expect(parse("فون کرنا ہفتہ اور اتوار کو").plannedDayOffset == 4)
    // Without a mark, or after a word that makes it the week, it stays in the title.
    expectLinesUnread(
      [
        "فون کرنا ہفتہ", "فون کرنا ہفتے", "فون کرنا اس ہفتے", "فون کرنا پورے ہفتے", "فون کرنا ہفتہ بھر", "ہفتے بھر کا کام",
        "فون کرنا ہر ہفتے کی میٹنگ",
      ], languages: ["ur"])
    // A deadline word marks it as a day.
    #expect(parse("رپورٹ بھیجنا ہفتے تک").dueDayOffset == 4)
    #expect(parse("رپورٹ بھیجنا اس ہفتے تک").dueDayOffset == nil)
  }

  @Test("The weekend: this one, next week's, and today when it is already here")
  func weekend() {
    for text in [
      "ویک اینڈ", "ویک اینڈ پر", "اس ویک اینڈ", "ویکاینڈ", "ویک\u{200C}اینڈ", "اختتام ہفتہ", "اختتام ہفتہ پر", "ہفتے کے آخر",
      "ہفتے کے آخر میں", "اس ہفتے کے آخر میں", "ہفتہ اور اتوار", "ہفتے اور اتوار کو",
    ] {
      let parsed = parse("فون کرنا \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "فون کرنا", "\(text): title")
    }
    for text in ["اگلے ویک اینڈ", "اگلے اختتام ہفتہ", "اگلے ہفتے کے آخر میں"] {
      #expect(parse("فون کرنا \(text)").plannedDayOffset == 11, "\(text)")
    }
    // On a Saturday or a Sunday the weekend is already here.
    #expect(parse("فون کرنا ویک اینڈ", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("فون کرنا ویک اینڈ", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("فون کرنا ویک اینڈ", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("فون کرنا اگلے ویک اینڈ", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
  }

  // MARK: - Dates

  @Test("Written dates: every month, in the spellings people type, with a year, a label, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("5 جنوری", "2027-01-05"), ("5 فروری", "2027-02-05"), ("5 مارچ", "2027-03-05"), ("5 اپریل", "2027-04-05"),
      ("5 ایپریل", "2027-04-05"), ("5 مئی", "2027-05-05"), ("5 جون", "2027-06-05"), ("5 جولائی", "2027-07-05"),
      ("5 جولای", "2027-07-05"), ("5 اگست", "2027-08-05"), ("5 اگسٹ", "2027-08-05"), ("5 ستمبر", "2027-09-05"),
      ("5 اکتوبر", "2026-10-05"), ("5 نومبر", "2026-11-05"), ("5 دسمبر", "2026-12-05"), ("22 ستمبر", "2026-09-22"),
      ("۵ مئی", "2027-05-05"), ("٥ مئی", "2027-05-05"), ("5 مئی کو", "2027-05-05"), ("5 مئی 2027", "2027-05-05"),
      ("5 مئی 2028", "2028-05-05"), ("5 مئی، 2028", "2028-05-05"), ("5 مئی 2028ء", "2028-05-05"),
      ("تاریخ 5 مئی", "2027-05-05"), ("بتاریخ: 5 مئی", "2027-05-05"), ("پیر، 5 اکتوبر", "2026-10-05"),
      ("1 جنوری 2027", "2027-01-01"),
    ]
    for line in dates {
      let text = "امی کو فون کرنا \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "امی کو فون کرنا", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
  }

  @Test("A month needs its day before it, and a date in digits, another calendar, or a day the month lacks is no date")
  func unreadDates() {
    expectLinesUnread(
      [
        // The Islamic and the Indian calendars' months are not Gregorian dates.
        "فون کرنا 5 محرم", "تہوار 5 رمضان", "عید 1 شوال", "پوجا 5 چیت",
        // A month alone, a month before its day, and a day of the month alone.
        "چھٹی مئی میں", "فون کرنا مئی 5", "فون کرنا ستمبر 5", "کرایہ 5 تاریخ کو",
        // Digits only, and a day the month does not have.
        "فون کرنا 5/10", "فون کرنا 31 اپریل", "فون کرنا 30 فروری", "فون کرنا 32 مئی",
      ], languages: ["ur"])
    // A name that looks like a month is left alone beside a date.
    let name = parse("مئی کی سالگرہ 5 مئی")
    #expect(name.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(name.title == "مئی کی سالگرہ")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("چھٹی", "3 سے 5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 سے 5 مارچ تک", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 مارچ سے 5 مارچ تک", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 مارچ سے 5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "30 جنوری سے 2 فروری تک", "2027-01-30", "2027-02-02"),
        ("چھٹی", "3 تا 5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3-5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3–5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 مارچ - 5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 سے 5 مارچ 2027", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 سے لے کر 5 مارچ تک", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 سے 5 مارچ کے بیچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 سے 5 مارچ کے درمیان", "2027-03-03", "2027-03-05"),
        ("چھٹی", "3 اور 5 مارچ کے درمیان", "2027-03-03", "2027-03-05"),
        ("چھٹی", "۳ سے ۵ مارچ", "2027-03-03", "2027-03-05"),
        ("فیملی کے ساتھ چھٹی", "3 سے 5 مارچ", "2027-03-03", "2027-03-05"),
        ("چھٹی", "25 ستمبر سے 3 اکتوبر تک", "2026-09-25", "2026-10-03"),
        ("چھٹی", "30 دسمبر سے 2 جنوری تک", "2026-12-30", "2027-01-02"),
        ("کانفرنس", "12-14 اکتوبر", "2026-10-12", "2026-10-14"),
      ], languages: ["ur"])
  }

  @Test("A range whose end is not after its start, that names no month, or that names two days stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "چھٹی 5 سے 3 مارچ", "چھٹی 3 مارچ سے 3 مارچ تک", "چھٹی 5-3 مارچ", "چھٹی 5 مارچ سے 3 مارچ تک",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "چھٹی 3 سے 5",
        // Two days joined by "اور" are two days, not a range.
        "چھٹی 3 اور 5 مارچ",
        // A range in the past, or one that a possessive follows, may be an event
        // the task only prepares for.
        "3 سے 5 مارچ تک چھٹی تھی", "5 سے 8 مئی تک کی چھٹی", "5 سے 8 مئی کی چھٹی",
      ], languages: ["ur"])
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 مارچ")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("Sprint", "12-20 مارچ", "2027-03-12", "2027-03-20")], languages: ["ur"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("چھٹی 3 سے 5 مارچ کل")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "چھٹی کل")
    let timed = parse("چھٹی 3 سے 5 مارچ شام 6 بجے")
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "چھٹی")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("رپورٹ پیر سے بدھ تک")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "رپورٹ")
    #expect(span.phrases.map(\.text) == ["پیر سے بدھ تک"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("سفر پیر تا بدھ", 6, 8), ("سفر جمعہ سے پیر", 3, 6), ("سفر ہفتہ سے اتوار", 4, 5),
      ("سفر جمعہ سے اتوار تک", 3, 5), ("سفر جمعہ سے لے کر اتوار تک", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("کیمپ منگل سے جمعرات", 7, 9), ("کیمپ بدھ سے جمعہ کے درمیان", 1, 3),
    ]
    for line in spans {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day")
      #expect(parsed.dueDayOffset == line.due, "\(line.text): due day")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Monday to Friday or to Saturday with no word for every day may be a week
    // of work as well as the working week, so it stays in the title.
    expectLinesUnread(
      [
        "جم پیر سے جمعہ", "ٹریننگ پیر سے جمعہ تک", "ٹریننگ پیر سے جمعہ تک کی", "پیر سے جمعہ تک کی ٹریننگ",
        "کانفرنس پیر سے ہفتہ",
      ], languages: ["ur"])
    // A span in the past, or one that a possessive follows, is no plan.
    expectLinesUnread(["پیر سے بدھ تک کی چھٹی", "پیر سے بدھ تک چھٹی تھی"], languages: ["ur"])
  }

  @Test("A weekday in a list of weekdays is no planned day")
  func weekdayLists() {
    expectLinesUnread(
      [
        "پیر اور جمعرات کو جم جانا", "جم جانا پیر اور جمعرات کو", "پیر، منگل کو میٹنگ", "جمعہ اور ہفتہ کو سفر",
        "پیر و جمعرات کو جم",
      ], languages: ["ur"])
    // A weekday beside another word is still the day.
    let pair = parse("جمعہ کو میٹنگ، پیر کو جائزہ")
    #expect(pair.plannedDayOffset == 3)
  }

  // MARK: - Due days

  @Test("Due days: تک, سے پہلے, آخری تاریخ, and ڈیڈ لائن")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("رپورٹ بھیجنا جمعہ تک", "رپورٹ بھیجنا", 3),
      ("رپورٹ بھیجنا جمعہ سے پہلے", "رپورٹ بھیجنا", 3),
      ("رپورٹ بھیجنا جمعہ سے قبل", "رپورٹ بھیجنا", 3),
      ("رپورٹ بھیجنا منگل تک", "رپورٹ بھیجنا", 7),
      ("رپورٹ بھیجنا اگلے جمعہ تک", "رپورٹ بھیجنا", 10),
      ("رپورٹ بھیجنا اس جمعہ تک", "رپورٹ بھیجنا", 3),
      ("رپورٹ بھیجنا کل تک", "رپورٹ بھیجنا", 1),
      ("رپورٹ بھیجنا پرسوں تک", "رپورٹ بھیجنا", 2),
      ("رپورٹ بھیجنا کل شام سے پہلے", "رپورٹ بھیجنا", 1),
      ("رپورٹ بھیجنا آج شام تک", "رپورٹ بھیجنا", 0),
      ("رپورٹ بھیجنا آج رات تک", "رپورٹ بھیجنا", 0),
      ("کل صبح تک رپورٹ بھیجنا", "رپورٹ بھیجنا", 1),
      ("رپورٹ بھیجنا اگلے ہفتے تک", "رپورٹ بھیجنا", 7),
      ("رپورٹ بھیجنا ہفتے تک", "رپورٹ بھیجنا", 4),
      ("رپورٹ بھیجنا 5 مئی تک", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا 5 مئی سے پہلے", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا آخری تاریخ 5 مئی", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا آخری تاریخ: 5 مئی", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("آخری تاریخ: 5 مئی رپورٹ بھیجنا", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا مقررہ تاریخ 5 مئی", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا حتمی تاریخ 5 مئی", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا آخری تاریخ: جمعہ", "رپورٹ بھیجنا", 3),
      ("رپورٹ بھیجنا ڈیڈ لائن: 5 مئی", "رپورٹ بھیجنا", captureDayOffset("2027-05-05")),
      ("رپورٹ بھیجنا ڈیڈ لائن جمعہ", "رپورٹ بھیجنا", 3),
      ("ڈیڈ لائن جمعہ رپورٹ بھیجنا", "رپورٹ بھیجنا", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("رپورٹ بھیجنا جمعہ تک کل")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "رپورٹ بھیجنا")
  }

  @Test("\"آج تک\" and \"آج سے پہلے\" are idioms, and a deadline that a possessive follows is no deadline")
  func notDueDays() {
    expectLinesUnread(
      [
        "رپورٹ آج تک", "رپورٹ آج سے پہلے", "رپورٹ جمعہ تک کی", "رپورٹ جمعہ تک کی میٹنگ", "جمعہ تک کی رپورٹ",
      ], languages: ["ur"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "رپورٹ بھیجنا 5 بجے تک", "رپورٹ بھیجنا شام 5 بجے سے پہلے", "رپورٹ بھیجنا 18:00 تک",
        "رپورٹ بھیجنا 5 بجے کے بعد", "رپورٹ بھیجنا 5 بجے کے بیچ", "رپورٹ بھیجنا 3 اور 5 بجے کے بیچ",
        "رپورٹ بھیجنا 5 بجے کے دوران", "رپورٹ بھیجنا 5:30 بجے تک", "رپورٹ بھیجنا ساڑھے 5 بجے تک",
        "رپورٹ بھیجنا پانچ بجے تک", "رپورٹ بھیجنا آدھی رات تک", "رپورٹ بھیجنا 5 بج کر 30 منٹ",
        "رپورٹ بھیجنا 5 بجنے میں 10 منٹ",
      ], languages: ["ur"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("رپورٹ بھیجنا جمعہ شام 5 بجے تک")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "رپورٹ بھیجنا شام 5 بجے تک")
    let tomorrow = parse("رپورٹ بھیجنا کل 5 بجے تک")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "رپورٹ بھیجنا 5 بجے تک")
    // A planned day beside the clock deadline reads, and the clock stays.
    let day = parse("رپورٹ بھیجنا 5 بجے تک کل")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    #expect(day.title == "رپورٹ بھیجنا 5 بجے تک")
    // A time range that ends in "تک" is still a range.
    let range = parse("میٹنگ 2 بجے سے 4 بجے تک")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "میٹنگ")
    // Without Urdu, English reads the clock time and leaves the word.
    let english = parse("رپورٹ بھیجنا 18:00 تک", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "رپورٹ بھیجنا تک")
  }

  // MARK: - Times

  @Test("Clock times: بجے after the hour, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("میٹنگ 5 بجے", "میٹنگ", 17 * 60), ("میٹنگ 5بجے", "میٹنگ", 17 * 60),
      ("میٹنگ 5:30 بجے", "میٹنگ", 17 * 60 + 30), ("میٹنگ 5.30 بجے", "میٹنگ", 17 * 60 + 30),
      ("میٹنگ ۵ بجے", "میٹنگ", 17 * 60), ("میٹنگ ٥ بجے", "میٹنگ", 17 * 60), ("میٹنگ ٹھیک 5 بجے", "میٹنگ", 17 * 60),
      ("میٹنگ تقریباً 5 بجے", "میٹنگ", 17 * 60), ("میٹنگ لگ بھگ 5 بجے", "میٹنگ", 17 * 60),
      ("میٹنگ قریب 5 بجے", "میٹنگ", 17 * 60), ("میٹنگ 5 بجے پر", "میٹنگ", 17 * 60),
      ("میٹنگ 5 بجے سے", "میٹنگ", 17 * 60), ("میٹنگ 5 بجے کے لیے", "میٹنگ", 17 * 60),
      ("میٹنگ 5 بجے کے آس پاس", "میٹنگ", 17 * 60), ("5 بجے کی میٹنگ", "میٹنگ", 17 * 60),
      ("5 بجے کا کھانا", "کھانا", 17 * 60), ("شام 5 بجے کی فلائٹ", "فلائٹ", 17 * 60),
      ("میٹنگ صبح 9 بجے", "میٹنگ", 9 * 60), ("میٹنگ صبح 9:30 بجے", "میٹنگ", 9 * 60 + 30),
      ("میٹنگ سویرے 6 بجے", "میٹنگ", 6 * 60), ("میٹنگ تڑکے 4 بجے", "میٹنگ", 4 * 60),
      ("میٹنگ دوپہر 12 بجے", "میٹنگ", 12 * 60), ("میٹنگ دوپہر 1 بجے", "میٹنگ", 13 * 60),
      ("میٹنگ دوپہر 2 بجے", "میٹنگ", 14 * 60), ("میٹنگ سہ پہر 4 بجے", "میٹنگ", 16 * 60),
      ("میٹنگ شام کو 5 بجے", "میٹنگ", 17 * 60), ("میٹنگ شام 7 بجے", "میٹنگ", 19 * 60),
      ("میٹنگ رات کے 10 بجے", "میٹنگ", 22 * 60), ("میٹنگ رات 9 بجے", "میٹنگ", 21 * 60),
      ("میٹنگ رات 11 بجے", "میٹنگ", 23 * 60), ("میٹنگ 9 بجے صبح", "میٹنگ", 9 * 60),
      ("میٹنگ 5 بجے صبح", "میٹنگ", 5 * 60), ("میٹنگ 7 بجے شام", "میٹنگ", 19 * 60),
      ("میٹنگ 7 بجے شام کو", "میٹنگ", 19 * 60), ("میٹنگ 10 بجے رات", "میٹنگ", 22 * 60),
      ("میٹنگ 2 بجے دوپہر", "میٹنگ", 14 * 60), ("میٹنگ 17:30", "میٹنگ", 17 * 60 + 30),
      ("میٹنگ شام 5:30", "میٹنگ", 17 * 60 + 30), ("میٹنگ رات 10.30", "میٹنگ", 22 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day after بجے that a possessive follows belongs to the
    // title: it is the evening's tea, not the hour's part of the day.
    let tea = parse("میٹنگ 5 بجے شام کی چائے")
    #expect(tea.startMinutes == 17 * 60)
    #expect(tea.title == "میٹنگ شام کی چائے")
    // A part of the day on both sides of the hour contradicts itself.
    #expect(parse("میٹنگ صبح 9 بجے شام").startMinutes == nil)
    // Twelve in the morning is no time, and neither is 24 o'clock.
    #expect(parse("میٹنگ صبح 12 بجے").startMinutes == nil)
    #expect(parse("میٹنگ 24 بجے").startMinutes == nil)
    // A bare word or number with no بجے is no time.
    expectLinesUnread(["میٹنگ بجے", "میٹنگ شام 5", "میٹنگ پانچ"], languages: ["ur"])
  }

  @Test("Clock fractions: ساڑھے, سوا, پونے, ڈیڑھ, and ڈھائی")
  func clockFractions() {
    let fractions: [(text: String, minutes: Int)] = [
      ("میٹنگ ساڑھے 5 بجے", 17 * 60 + 30), ("میٹنگ ساڑھے پانچ بجے", 17 * 60 + 30), ("میٹنگ سوا 5 بجے", 17 * 60 + 15),
      ("میٹنگ پونے 6 بجے", 17 * 60 + 45), ("میٹنگ ڈیڑھ بجے", 13 * 60 + 30), ("میٹنگ ڈھائی بجے", 14 * 60 + 30),
      ("میٹنگ اڑھائی بجے", 14 * 60 + 30), ("میٹنگ ساڑھے تین بجے", 15 * 60 + 30), ("میٹنگ سوا دو بجے", 14 * 60 + 15),
      ("میٹنگ پونے چار بجے", 15 * 60 + 45), ("میٹنگ پونے ایک بجے", 12 * 60 + 45),
      ("میٹنگ پونے بارہ بجے", 11 * 60 + 45), ("میٹنگ صبح ساڑھے 9 بجے", 9 * 60 + 30),
      ("میٹنگ صبح پونے 10 بجے", 9 * 60 + 45), ("میٹنگ صبح سوا 8 بجے", 8 * 60 + 15),
      ("میٹنگ شام کو ساڑھے 6 بجے", 18 * 60 + 30), ("میٹنگ رات پونے 10 بجے", 21 * 60 + 45),
      ("میٹنگ ساڑھے ۵ بجے", 17 * 60 + 30),
    ]
    for line in fractions {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "میٹنگ", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A fraction counts from an hour on the clock face.
    #expect(parse("میٹنگ ساڑھے 13 بجے").startMinutes == nil)
    #expect(parse("میٹنگ ڈیڑھ بجے صبح").startMinutes == 90)
  }

  @Test("An hour as a number word is read only before بجے")
  func numberWordHours() {
    let hours: [(word: String, minutes: Int)] = [
      ("ایک", 13 * 60), ("دو", 14 * 60), ("تین", 15 * 60), ("چار", 16 * 60), ("پانچ", 17 * 60), ("چھ", 18 * 60),
      ("چھے", 18 * 60), ("سات", 7 * 60), ("آٹھ", 8 * 60), ("نو", 9 * 60), ("دس", 10 * 60), ("گیارہ", 11 * 60),
      ("بارہ", 12 * 60),
    ]
    for hour in hours {
      let text = "میٹنگ \(hour.word) بجے"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "میٹنگ", "\(text): title")
    }
    #expect(parse("میٹنگ صبح نو بجے").startMinutes == 9 * 60)
    #expect(parse("میٹنگ شام کو سات بجے").startMinutes == 19 * 60)
    // A number word is a count anywhere else.
    expectLinesUnread(
      ["میٹنگ پانچ", "میٹنگ ایک", "تین لوگ آئیں گے", "دو دوست", "سات دن", "میٹنگ تین سے پانچ"], languages: ["ur"])
  }

  @Test("After midnight: رات runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("میٹنگ رات 2 بجے")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "میٹنگ")
    let twelve = parse("میٹنگ رات 12 بجے")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    let trailing = parse("میٹنگ 12 بجے رات")
    #expect(trailing.startMinutes == 0)
    #expect(trailing.plannedDayOffset == 1)
    for text in ["میٹنگ آدھی رات", "میٹنگ آدھی رات کو", "میٹنگ ٹھیک آدھی رات کو", "میٹنگ نصف شب"] {
      let midnight = parse(text)
      #expect(midnight.startMinutes == 0, "\(text)")
      #expect(midnight.plannedDayOffset == 1, "\(text)")
      #expect(midnight.title == "میٹنگ", "\(text): title")
    }
    // The night counts from the evening: 6 to 11 is the evening's.
    #expect(parse("میٹنگ رات 6 بجے").startMinutes == 18 * 60)
    #expect(parse("میٹنگ رات 6 بجے").plannedDayOffset == nil)
    // A named day keeps the time on its own night: "کل رات 1 بجے" is 01:00 of the day after.
    let tomorrow = parse("کل رات 1 بجے سونا")
    #expect(tomorrow.startMinutes == 60)
    #expect(tomorrow.plannedDayOffset == 2)
    #expect(tomorrow.title == "سونا")
    let named = parse("پیر رات 12 بجے فلائٹ")
    #expect(named.startMinutes == 0)
    #expect(named.plannedDayOffset == 7)
    #expect(named.title == "فلائٹ")
    // A repeat moves to the day after, so the rule and the time agree.
    let repeating = parse("ہر جمعہ رات 12 بجے فلائٹ")
    #expect(repeating.startMinutes == 0)
    #expect(repeating.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(repeating.recurrenceStartOffset == 4)
    #expect(repeating.title == "فلائٹ")
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("میٹنگ 1 بجے").startMinutes == 13 * 60)
    #expect(parse("میٹنگ 3 بجے").startMinutes == 15 * 60)
    #expect(parse("میٹنگ 6 بجے").startMinutes == 18 * 60)
    #expect(parse("میٹنگ 7 بجے").startMinutes == 7 * 60)
    #expect(parse("میٹنگ 9 بجے").startMinutes == 9 * 60)
    #expect(parse("میٹنگ 11 بجے").startMinutes == 11 * 60)
    #expect(parse("میٹنگ 12 بجے").startMinutes == 12 * 60)
    #expect(parse("میٹنگ 13 بجے").startMinutes == 13 * 60)
    #expect(parse("میٹنگ 17 بجے").startMinutes == 17 * 60)
    #expect(parse("میٹنگ 06:30 بجے").startMinutes == 6 * 60 + 30)
    #expect(parse("میٹنگ 03:00 بجے").startMinutes == 3 * 60)
    #expect(parse("میٹنگ 3:00 بجے").startMinutes == 15 * 60)
    // A part of the day names the half of the day either way.
    #expect(parse("میٹنگ صبح 5 بجے").startMinutes == 5 * 60)
    #expect(parse("میٹنگ شام 5 بجے").startMinutes == 17 * 60)
  }

  @Test("A part of the day before an hour may carry ٹھیک, قریب, لگ بھگ, تقریباً, or جلدی, and صبح may be doubled")
  func partModifiers() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("میٹنگ صبح ٹھیک 6 بجے", "میٹنگ", 6 * 60), ("میٹنگ صبح قریب 6 بجے", "میٹنگ", 6 * 60),
      ("میٹنگ صبح جلدی 6 بجے", "میٹنگ", 6 * 60), ("میٹنگ صبح تقریباً 9 بجے", "میٹنگ", 9 * 60),
      ("چائے شام کو ٹھیک 5 بجے", "چائے", 17 * 60), ("میٹنگ شام کو لگ بھگ 6 بجے", "میٹنگ", 18 * 60),
      ("میٹنگ رات لگ بھگ 11 بجے", "میٹنگ", 23 * 60), ("صبح صبح 6 بجے یوگا", "یوگا", 6 * 60),
      ("یوگا صبح صبح 6 بجے", "یوگا", 6 * 60), ("صبح سویرے 6 بجے یوگا", "یوگا", 6 * 60),
      ("صبح-صبح 6 بجے یوگا", "یوگا", 6 * 60), ("صبح\u{2011}صبح 7 بجے یوگا", "یوگا", 7 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The doubled morning also follows a day.
    let tomorrow = parse("کل صبح صبح اٹھنا")
    #expect(tomorrow.plannedDayOffset == 1)
    #expect(tomorrow.title == "اٹھنا")
    #expect(tomorrow.phrases.map(\.text) == ["کل صبح صبح"])
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("صبح کی سیر 6 بجے", "صبح کی سیر", 6 * 60), ("6 بجے صبح کی سیر", "صبح کی سیر", 6 * 60),
      ("صبح کی سیر 5 بجے", "صبح کی سیر", 5 * 60), ("صبح صبح کی سیر 6 بجے", "صبح صبح کی سیر", 6 * 60),
      ("رات کا کھانا 8 بجے", "رات کا کھانا", 20 * 60), ("رات کا کھانا 6 بجے", "رات کا کھانا", 18 * 60),
      ("رات کا کھانا ساڑھے 8 بجے", "رات کا کھانا", 20 * 60 + 30), ("رات کی دوا 10 بجے", "رات کی دوا", 22 * 60),
      ("شام کی چائے 5 بجے", "شام کی چائے", 17 * 60), ("دوپہر کا کھانا 1 بجے", "دوپہر کا کھانا", 13 * 60),
      ("دوپہر کا کھانا 2 بجے", "دوپہر کا کھانا", 14 * 60),
      // The 24-hour clock is read as written: a leading zero, or 13 and later.
      ("رات کا کھانا 20:00 بجے", "رات کا کھانا", 20 * 60), ("رات کی ڈیوٹی 06:30 بجے", "رات کی ڈیوٹی", 6 * 60 + 30),
      // Noon is no morning hour, so a morning's 12 stays as written.
      ("صبح کی میٹنگ 12 بجے", "صبح کی میٹنگ", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The part of the day may come from the day phrase, and the day is read too.
    let dinner = parse("آج رات کا کھانا 8 بجے")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "رات کا کھانا")
    let meeting = parse("کل صبح میٹنگ 6 بجے")
    #expect(meeting.plannedDayOffset == 1)
    #expect(meeting.startMinutes == 6 * 60)
    #expect(meeting.title == "میٹنگ")
    // Two parts that differ leave the hour as it reads alone, and "آدھی رات"
    // names no part.
    #expect(parse("صبح کی سیر رات کا کھانا 5 بجے").startMinutes == 17 * 60)
    #expect(parse("آدھی رات کو کھانا 5 بجے").startMinutes == 17 * 60)
  }

  @Test("Time ranges: سے and تا with بجے, a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("میٹنگ 3 سے 5 بجے", 15 * 60, 120), ("میٹنگ 3 سے 5 بجے تک", 15 * 60, 120),
      ("میٹنگ 3 بجے سے 5 بجے تک", 15 * 60, 120), ("میٹنگ 2 بجے سے لے کر 4 بجے تک", 14 * 60, 120),
      ("میٹنگ صبح 9 سے 11 بجے", 9 * 60, 120), ("میٹنگ صبح 9 سے 11 بجے تک", 9 * 60, 120),
      ("میٹنگ شام 5 سے 7 بجے", 17 * 60, 120), ("میٹنگ رات 8 سے 10 بجے", 20 * 60, 120),
      ("میٹنگ دو سے چار بجے", 14 * 60, 120), ("میٹنگ ۲ سے ۴ بجے", 14 * 60, 120), ("میٹنگ 2-4 بجے", 14 * 60, 120),
      ("میٹنگ 2–4 بجے", 14 * 60, 120), ("میٹنگ 2 تا 4 بجے", 14 * 60, 120),
      ("میٹنگ 14:00 سے 16:00", 14 * 60, 120), ("میٹنگ 14:00 سے 16:00 تک", 14 * 60, 120),
      ("میٹنگ 9:30 سے 10:30 تک", 9 * 60 + 30, 60), ("میٹنگ 14:00-16:00", 14 * 60, 120),
      ("میٹنگ صبح 9 بجے سے شام 5 بجے تک", 9 * 60, 480), ("میٹنگ 9 سے 5 بجے", 9 * 60, 480),
      ("میٹنگ 10 سے 12 بجے", 10 * 60, 120), ("میٹنگ 11 سے 1 بجے", 11 * 60, 120),
      ("میٹنگ 3 سے 5 بجے کے بیچ", 15 * 60, 120), ("میٹنگ 3 سے 5 بجے کے درمیان", 15 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "میٹنگ", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The end carries بجے: two bare numbers are no range.
    expectLinesUnread(["میٹنگ 3 سے 5", "میٹنگ تین سے پانچ"], languages: ["ur"])
    // A length written in the line wins over the span of the range.
    let named = parse("میٹنگ 3 سے 5 بجے 30 منٹ")
    #expect(named.startMinutes == 15 * 60)
    #expect(named.estimatedMinutes == 30)
    #expect(named.title == "میٹنگ")
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amounts() {
    expectLinesUnread(
      [
        "3 لوگوں کے ساتھ میٹنگ", "۳ لوگوں کے ساتھ میٹنگ", "میٹنگ میں 3 لوگ آئیں گے", "5 کتابیں خریدنا", "10 صفحے پڑھنا",
        "2 کلو چینی لانا", "12 انڈے لانا", "500 روپے کا بل جمع کرنا", "₹500 کا بل", "بل ₹500", "5 ڈالر خرچ", "50 پیسے دینا",
        "20% چھوٹ", "20 % چھوٹ", "5 بجٹ بنانا",
      ], languages: ["ur"])
    // A number before a percent sign or a price is not the hour of a time beside it.
    let percent = parse("میٹنگ 20% 5 بجے")
    #expect(percent.startMinutes == 17 * 60)
    #expect(percent.title == "میٹنگ 20%")
    let price = parse("میٹنگ 5 بجے 500 روپے")
    #expect(price.startMinutes == 17 * 60)
    #expect(price.title == "میٹنگ 500 روپے")
    // The words around an amount still read.
    let bill = parse("500 روپے کا بل جمع کرنا کل")
    #expect(bill.plannedDayOffset == 1)
    #expect(bill.title == "500 روپے کا بل جمع کرنا")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("30 منٹ", 30), ("30 منٹ کے لیے", 30), ("45 منٹ", 45), ("90 منٹ", 90), ("2 منٹ", 2), ("۴۵ منٹ", 45),
      ("2 گھنٹے", 120), ("2 گھنٹے کے لیے", 120), ("2 گھنٹوں", 120), ("1 گھنٹہ", 60), ("1 گھنٹا", 60),
      ("1.5 گھنٹے", 90), ("1 گھنٹہ 30 منٹ", 90), ("1 گھنٹہ اور 30 منٹ", 90), ("آدھا گھنٹہ", 30), ("آدھے گھنٹے", 30),
      ("پون گھنٹہ", 45), ("سوا گھنٹہ", 75), ("ڈیڑھ گھنٹہ", 90), ("ڈھائی گھنٹے", 150), ("ساڑھے 3 گھنٹے", 210),
      ("ساڑھے تین گھنٹے", 210), ("پونے دو گھنٹے", 105), ("سوا 2 گھنٹے", 135), ("دو گھنٹے", 120),
      ("ایک گھنٹہ", 60), ("بیس منٹ", 20), ("پندرہ منٹ", 15), ("تیس منٹ", 30), ("پینتالیس منٹ", 45),
      ("پنتالیس منٹ", 45), ("دس منٹ", 10), ("تقریباً 2 گھنٹے", 120), ("لگ بھگ 30 منٹ", 30),
      ("قریباً 20 منٹ", 20),
    ]
    for line in lengths {
      let text = "رپورٹ لکھنا \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "رپورٹ لکھنا", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The postposition that goes with a length is read with it.
    let meeting = parse("30 منٹ کی میٹنگ")
    #expect(meeting.estimatedMinutes == 30)
    #expect(meeting.title == "میٹنگ")
    #expect(meeting.phrases.map(\.text) == ["30 منٹ کی"])
    let work = parse("2 گھنٹے کا کام")
    #expect(work.estimatedMinutes == 120)
    #expect(work.title == "کام")
    // A time and a length together.
    let both = parse("میٹنگ 5 بجے 45 منٹ کے لیے")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "میٹنگ")
  }

  @Test("An amount before بعد, پہلے, or میں, or after ہر, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "رپورٹ لکھنا 2 گھنٹے بعد", "رپورٹ لکھنا 15 منٹ بعد", "رپورٹ لکھنا 1 گھنٹہ پہلے", "رپورٹ لکھنا 30 منٹ پہلے",
        "رپورٹ لکھنا ہر 2 گھنٹے", "رپورٹ لکھنا ہر 30 منٹ", "رپورٹ لکھنا 2 گھنٹے کے اندر", "رپورٹ لکھنا 2 گھنٹے میں",
        "رپورٹ لکھنا 15 منٹ میں", "رپورٹ لکھنا دن میں 2 گھنٹے", "رپورٹ لکھنا کم از کم 2 گھنٹے",
        "رپورٹ لکھنا 2 گھنٹے سے زیادہ",
        // A range of amounts, an hour as a noun, and an amount no task takes.
        "رپورٹ لکھنا 2 سے 3 گھنٹے", "رپورٹ لکھنا 2-3 گھنٹے", "رپورٹ لکھنا 5 منٹ سے 10 منٹ", "رپورٹ لکھنا گھنٹہ",
        "گھنٹہ بھر پڑھنا", "رپورٹ لکھنا 25 گھنٹے", "رپورٹ لکھنا 0 منٹ",
      ], languages: ["ur"])
    // The phrase around an amount that is no length still reads.
    let day = parse("رپورٹ لکھنا 2 گھنٹے بعد کل")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "رپورٹ لکھنا 2 گھنٹے بعد")
    let time = parse("میٹنگ کل 3 بجے 2 گھنٹے بعد")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "میٹنگ 2 گھنٹے بعد")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("ہر دن", daily), ("ہر روز", daily), ("روزانہ", daily), ("روزآنہ", daily), ("ہر صبح", daily), ("ہر شام", daily),
      ("ہر رات", daily), ("ہر روز صبح", daily), ("دن میں ایک بار", daily), ("روزانہ کی بنیاد پر", daily),
      ("ہر ہفتے", weekly), ("ہر ہفتہ", weekly), ("ہفتہ وار", weekly), ("ہفتہ واری", weekly),
      ("ہفتے میں ایک بار", weekly), ("ہفتہ وار کی بنیاد پر", weekly), ("ہر مہینے", monthly), ("ہر ماہ", monthly),
      ("ماہانہ", monthly), ("ماہوار", monthly), ("مہینے میں ایک بار", monthly), ("ہر سال", yearly),
      ("ہر برس", yearly), ("سالانہ", yearly), ("سال میں ایک بار", yearly),
      ("ہر 2 دن", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ہر دو دن", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ہر دو دن بعد", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ہر دوسرے دن", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ہر پندرہ دن", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("ہر 3 ہفتے", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("ہر دوسرے ہفتے", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ہر 3 مہینے", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ہر تین مہینے", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ہر 5 سال", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("ہر ۳ دن", TaskRecurrenceRule(freq: .daily, interval: 3)),
    ]
    for line in cadences {
      let text = "دوا لیں \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "دوا لیں", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
    // An adverb of cadence repeats wherever it stands: Urdu puts the adjective first.
    for text in ["روزانہ دوا لیں", "ہفتہ وار میٹنگ", "ماہانہ بل ادا کرنا", "سالانہ جائزہ"] {
      #expect(parse(text).recurrence != nil, "\(text)")
    }
    #expect(parse("روزانہ دوا لیں").title == "دوا لیں")
  }

  @Test("Weekday repeats: ہر پیر, lists of days, every other week, the weekend, and the working days")
  func weekdayRepeats() {
    let coming = parse("جم ہر پیر")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "جم")
    #expect(coming.plannedDayOffset == nil)
    #expect(parse("جم ہر پیر کو").recurrence == monday)
    #expect(parse("جم ہر ہفتے پیر کو").recurrence == monday)
    #expect(parse("جم ہر پیر کے دن").recurrence == monday)

    let lists: [(text: String, days: [String])] = [
      ("جم ہر پیر اور جمعرات", ["MO", "TH"]), ("جم ہر پیر، بدھ اور جمعہ", ["MO", "WE", "FR"]), ("جم ہر بدھ", ["WE"]),
      ("جم ہر سنیچر", ["SA"]), ("جم ہر اتوار", ["SU"]), ("جم ہر ہفتے کو", ["SA"]),
      ("جم پیر اور جمعرات کو ہر ہفتے", ["MO", "TH"]), ("جم ہر ہفتہ اور اتوار", ["SU", "SA"]),
      ("جم ہر ویک اینڈ", ["SU", "SA"]), ("جم ہر اختتام ہفتہ", ["SU", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "جم", "\(line.text): title")
    }
    #expect(parse("جم ہر پیر اور جمعرات").recurrenceStartOffset == 2)
    #expect(parse("جم ہر ویک اینڈ").recurrenceStartOffset == 4)
    let everyOther = parse("جم ہر دوسرے پیر")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))

    // The working days, written out or as a span of weekdays beside ہر or
    // a word for every day.
    for text in [
      "جم ہر کام کے دن", "جم ہر ورکنگ ڈے", "جم کام کے دنوں میں", "جم ہر کاروباری دن", "جم کاروباری دنوں میں",
      "جم ہر پیر سے جمعہ", "جم روزانہ پیر سے جمعہ", "جم پیر سے جمعہ ہر روز", "جم ہر پیر سے جمعہ تک",
      "جم ہر پیر سے جمعہ صبح 9 بجے",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
    #expect(parse("جم ہر پیر سے بدھ").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE"]))
    #expect(
      parse("جم ہر اتوار سے جمعرات").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"]))
    // Monday to Friday alone is no repeat.
    #expect(parse("جم پیر سے جمعہ").recurrence == nil)
    // A repeat that starts today starts at 0 on its own weekday.
    #expect(parse("جم ہر منگل").recurrenceStartOffset == 0)
    #expect(parse("جم ہر جمعہ", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("یوگا ہر صبح 6 بجے", "یوگا", 6 * 60), ("ہر صبح 6 بجے یوگا", "یوگا", 6 * 60),
      ("ہر شام کو 7 بجے ٹہلنا", "ٹہلنا", 19 * 60), ("یوگا ہر شام کو 7 بجے", "یوگا", 19 * 60),
      ("ہر رات 10:30 دوا", "دوا", 22 * 60 + 30), ("ہر رات 11 بجے سونا", "سونا", 23 * 60),
      ("ہر روز صبح 6 بجے یوگا", "یوگا", 6 * 60), ("ہر روز شام کو 7 بجے ٹہلنا", "ٹہلنا", 19 * 60),
      ("ہر صبح صبح 6 بجے یوگا", "یوگا", 6 * 60), ("ہر رات کو پڑھنا", "پڑھنا", nil),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let range = parse("ہر صبح 9 سے 11 بجے پڑھائی")
    #expect(range.recurrence == daily)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "پڑھائی")
    // A line of details alone is no task.
    expectLinesUnread(["ہر صبح 6 بجے", "ہر شام 7 بجے"], languages: ["ur"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "کرایہ ہر مہینے کی 5 تاریخ", "کرایہ ہر مہینے کی 5 تاریخ کو", "کرایہ ہر مہینے 5 تاریخ کو",
      "کرایہ ہر مہینے کی 5ویں تاریخ کو", "کرایہ ہر ماہ کی 5 تاریخ", "کرایہ ہر مہینے کی ۵ تاریخ",
      "کرایہ 5 تاریخ کو ہر مہینے", "کرایہ ہر مہینے کی 5 کو",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text): start")
      #expect(parsed.title == "کرایہ", "\(text): title")
    }
    let first = parse("کرایہ ہر مہینے کی پہلی تاریخ")
    #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    #expect(first.recurrenceStartOffset == 9)
    // A date with its month name is a date, not a repeat.
    #expect(parse("کرایہ ہر 5 مئی").recurrence == nil)
  }

  @Test("A repeat shorter than a day, and a cadence word that describes a noun, are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        "دوا لیں ہر 2 گھنٹے", "روزانہ کی رپورٹ", "ہر سال کا جائزہ", "روز مرہ کے کام", "روزگار کے مواقع", "روزہ رکھنا",
        "ہر ہفتے کی میٹنگ", "ہر دن کی ڈائری", "روزانہ کی خبریں", "ہر مہینے کا حساب",
      ], languages: ["ur"])
    // The weekday after ہر with a possessive is an attribute too.
    #expect(parse("ہر پیر کی میٹنگ").recurrence == nil)
    // A bare روز is no repeat word: "جمعہ کے روز" names a day.
    #expect(parse("ورزش روز").recurrence == nil)
    let day = parse("جمعہ کے روز میٹنگ")
    #expect(day.plannedDayOffset == 3)
    #expect(day.recurrence == nil)
  }

  // MARK: - Priorities

  @Test("Priorities: اعلیٰ, معمولی, and کم ترجیح, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("اعلیٰ ترجیح", .p1), ("اعلی ترجیح", .p1), ("انتہائی اعلیٰ ترجیح", .p1), ("زیادہ ترجیح", .p1),
      ("سب سے زیادہ ترجیح", .p1), ("ترجیح: اعلیٰ", .p1), ("ترجیح اعلیٰ", .p1), ("معمولی ترجیح", .p2),
      ("درمیانی ترجیح", .p2), ("عام ترجیح", .p2), ("ترجیح: درمیانی", .p2), ("ترجیح: معمولی", .p2),
      ("کم ترجیح", .p3), ("کمتر ترجیح", .p3), ("نچلی ترجیح", .p3), ("سب سے کم ترجیح", .p3), ("ترجیح کم", .p3),
      ("ترجیح: نچلی", .p3), ("اعلیٰ ترجیح کے ساتھ", .p1), ("اعلیٰ ترجیح سے", .p1),
    ]
    for level in levels {
      let text = "رپورٹ بھیجنا \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "رپورٹ بھیجنا", "\(text): title")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let opening = parse("اعلیٰ ترجیح کے ساتھ رپورٹ بھیجنا")
    #expect(opening.priority == .p1)
    #expect(opening.title == "رپورٹ بھیجنا")
    let inside = parse("رپورٹ اعلیٰ ترجیح سے بھیجنا")
    #expect(inside.priority == .p1)
    #expect(inside.title == "رپورٹ بھیجنا")

    for word in ["فوری", "ضروری", "انتہائی ضروری", "نہایت ضروری", "بہت ضروری", "فوراً", "فورا", "ارجنٹ"] {
      let text = "رپورٹ بھیجنا \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "رپورٹ بھیجنا", "\(text): title")
    }
    for word in ["فوری", "ضروری", "ارجنٹ"] {
      for separator in [":", ",", "،", " ،"] {
        let text = "\(word)\(separator) رپورٹ بھیجنا"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "رپورٹ بھیجنا", "\(text): title")
      }
    }
    #expect(parse("رپورٹ بھیجنا فوری۔").title == "رپورٹ بھیجنا۔")
    // An urgent word in the middle, or opening the line with no colon or
    // comma, is a word of the title.
    expectLinesUnread(
      [
        "ضروری دوائیں خریدنا", "رپورٹ بھیجنا ضروری ہے", "فوری رپورٹ بھیجنا", "رپورٹ بھیجنا فوری ہی",
        "ضروری کام نمٹانا", "اعلیٰ ترجیح والے کام", "کم ترجیح والی فہرست",
      ], languages: ["ur"])
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("کل شام 5 بجے 30 منٹ کے لیے میٹنگ #کام")
    #expect(line.title == "میٹنگ")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["کام"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["کل", "شام 5 بجے", "30 منٹ کے لیے", "#کام"])

    let lines: [(text: String, title: String)] = [
      ("ہر پیر صبح 9 بجے جم", "جم"), ("جمعہ تک رپورٹ بھیجنا ضروری", "رپورٹ بھیجنا"),
      ("پیر کو صبح 9 سے 11 بجے تک میٹنگ", "میٹنگ"), ("5 مئی کو شام 6 بجے پارٹی", "پارٹی"),
      ("اگلے جمعہ تک 2 گھنٹے کا کام", "کام"), ("کل میٹنگ 3 بجے اعلیٰ ترجیح", "میٹنگ"),
      ("روزانہ صبح 7 بجے دوا", "دوا"), ("آج رات 11 بجے سونا", "سونا"),
      ("امی کو فون کرنا کل شام 5 بجے", "امی کو فون کرنا"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(parse(line.text).phrases.count >= 2, "\(line.text): phrases")
    }
    let friday = parse("جمعہ تک رپورٹ بھیجنا ضروری")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.priority == .p1)
    let weekly = parse("ہر پیر صبح 9 بجے جم")
    #expect(weekly.recurrence == monday)
    #expect(weekly.startMinutes == 9 * 60)
    let report = parse("اگلے جمعہ تک 2 گھنٹے کا کام")
    #expect(report.dueDayOffset == 10)
    #expect(report.estimatedMinutes == 120)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Weekday names that are also ordinary words and names.
        "پیر صاحب کو فون کرنا", "پیر میں درد ہے", "بدھ مت کا مطالعہ", "جمعہ بازار جانا", "جمعہ مبارک پوسٹ لکھنا",
        "نماز جمعہ کے بعد کام", "خطبہ جمعہ سننا",
        // Words that contain a day word.
        "آجکل میٹنگ", "آج کل مصروفیت ہے", "آج\u{200C}کل مصروفیت ہے", "کلاس میں جانا", "کلام پڑھنا", "پیروی کرنا",
        "پیرس کا ٹکٹ",
        // کل as "total".
        "کل رقم جمع کرنا", "کل تعداد گننا", "کل ملا کر حساب لگانا",
        // A day with a possessive after it is an attribute of a noun.
        "پیر کی میٹنگ", "جمعہ کا کھانا", "کل کی میٹنگ", "کل کا کھانا", "آج کی رپورٹ",
        // A bound or an amount of days that names no day.
        "رپورٹ 3 دن میں بھیجنا", "3 دن پہلے کی بات", "میٹنگ کے 3 دن بعد",
        // A bare number that is a count.
        "3 سیب خریدنا", "5 لوگوں کو بلانا",
      ], languages: ["ur"])
    // Urdu written in Latin letters is not read.
    expectLinesUnread(
      [
        "kal subah 9 baje meeting", "aaj shaam ko phone karna", "parson ko milna", "peer ko meeting",
        "har peer gym", "2 ghante parhna",
      ], languages: ["ur"])
    // "جمعہ کو" before other words is the day.
    let friday = parse("جمعہ کو پارٹی کی تیاری کرنا")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "پارٹی کی تیاری کرنا")
  }

  // MARK: - کل, پرسوں, and the past

  @Test("کل is tomorrow and پرسوں the day after, and a line in the past tense stays unread")
  func tomorrowOrYesterday() {
    let tomorrow = [
      "کل میٹنگ ہے", "کل جانا ہے", "کل کیا جانا ہے", "کل میٹنگ ہو گی", "کل سے جم شروع کرنا", "رپورٹ کل بھیجنا",
      "وہ کل آئے گا", "میں کل جاؤں گا",
    ]
    for text in tomorrow {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        // The app's own word for the past day, and the other words that say a day is past.
        "گزشتہ کل", "گزشتہ کل کی رپورٹ", "گزشتہ کل کی رپورٹ پڑھیں", "گزرے کل کی بات", "پچھلے جمعہ کی میٹنگ",
        "پہلے جمعہ کو میٹنگ", "پہلے کل کی رپورٹ",
        // A past-tense form anywhere in the line.
        "کل میٹنگ تھی", "پرسوں میٹنگ تھی", "میں کل گیا تھا", "کل گئے تھے", "کل آیا تھا", "کل میٹنگ ہوئی",
        "کل ہوئی میٹنگ کی رپورٹ", "آج میٹنگ تھی", "پیر کو میٹنگ تھی",
      ], languages: ["ur"])
    // "پہلے جمعہ" is a past or an ordinal day, but "جمعہ سے پہلے" is a deadline.
    #expect(parse("رپورٹ جمعہ سے پہلے").dueDayOffset == 3)
    #expect(parse("رپورٹ کل سے پہلے").dueDayOffset == 1)
    // میں is never a postposition after a day: it is also "I".
    let first = parse("آج میں رپورٹ لکھوں گا")
    #expect(first.plannedDayOffset == 0)
    #expect(first.title == "میں رپورٹ لکھوں گا")
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // A past statement with no past-tense marker reads as tomorrow.
    #expect(parse("کل میں نے فون کیا").plannedDayOffset == 1)
    // An hour from 1 to 6 with no part of the day is the afternoon.
    #expect(parse("میٹنگ 5 بجے").startMinutes == 17 * 60)
    // An hour count written with a Latin unit is English's length, even after ہر.
    #expect(parse("دوا لیں ہر 2h").estimatedMinutes == 120)
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("یہ کام ضروری").priority == .p1)
    #expect(parse("یہ کام فوری").priority == .p1)
    // A particle after a day goes with it even where it means "even today".
    let even = parse("آج بھی رپورٹ بھیجنا")
    #expect(even.plannedDayOffset == 0)
    #expect(even.title == "رپورٹ بھیجنا")
    #expect(parse("کل بھی جانا ہے").plannedDayOffset == 1)
    // A weekday in a sentence about someone else's plan is still read as the task's day.
    #expect(parse("وہ جمعرات کو آئیں گے").plannedDayOffset == 2)
    // Beside Arabic or Persian the Urdu reading form folds their kaf into the Urdu one, so
    // "كل" (all) and the Persian "کل" (whole) read as tomorrow unless a phrase of the other
    // language claims them first ("كل يوم" stays Arabic's repeat).
    #expect(parse("كل الطلاب", languages: ["ar", "ur"]).plannedDayOffset == 1)
    #expect(parse("کل پروژه را مرور کن", languages: ["fa", "ur"]).plannedDayOffset == 1)
    #expect(parse("كل الطلاب", languages: ["ar"]).plannedDayOffset == nil)
    let every = parse("اجتماع كل يوم", languages: ["ar", "ur"])
    #expect(every.recurrence == daily)
    #expect(every.plannedDayOffset == nil)
  }

  // MARK: - Scripts and spellings

  @Test("Digits in the Arabic-Indic and Extended scripts read as the digits they stand for")
  func digitScripts() {
    let lines = [
      "میٹنگ 3:30 بجے", "میٹنگ شام 5:30", "میٹنگ 5.30 بجے", "میٹنگ ساڑھے 5 بجے", "میٹنگ 2 سے 4 بجے",
      "میٹنگ 14:00 سے 16:00", "رپورٹ لکھنا 20 منٹ", "رپورٹ لکھنا 1.5 گھنٹے", "رپورٹ لکھنا 1 گھنٹہ 30 منٹ",
      "دوا لیں ہر 3 دن", "کرایہ ہر مہینے کی 5 تاریخ", "اجلاس 5 مارچ 2027", "امی کو فون کرنا 3 دن بعد",
      "چھٹی 3 سے 5 مارچ", "چھٹی 3-5 مارچ", "رپورٹ بھیجنا 5 مارچ تک", "امی کو فون کرنا 2 مہینے بعد",
      "دوا لیں ہر 2 ہفتے",
    ]
    for line in lines {
      let latin = parse(line)
      #expect(latin.phrases.count == 1, "\(line): phrases")
      for offset in [UInt32(0x0660), UInt32(0x06F0)] {
        let converted = digits(line, from: offset)
        #expect(converted != line, "\(line): the digits are converted")
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
    // The Arabic decimal separator reads as a point, and the title keeps the digits as typed.
    #expect(parse("رپورٹ لکھنا ١\u{066B}٥ گھنٹے").estimatedMinutes == 90)
    let typed = parse("۳ لوگوں کے ساتھ میٹنگ کل")
    #expect(typed.plannedDayOffset == 1)
    #expect(typed.title == "۳ لوگوں کے ساتھ میٹنگ")
  }

  @Test("Vowel signs, tatweel, and the Arabic spellings of yeh, kaf, alef, and heh change nothing")
  func spellings() {
    let tomorrow = [
      "امی کو فون کرنا کل", "امی کو فون کرنا کَل", "امی کو فون کرنا کـل", "امی کو فون کرنا کــــل", "امی کو فون کرنا كل",
      "امی کو فون کرنا كــل",
    ]
    for text in tomorrow {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.title == "امی کو فون کرنا", "\(text): title")
    }
    // A letter written as another form of it: the Arabic yeh or alef maksura for
    // the Urdu yeh, the Arabic kaf, alef with or without its madda, and every heh.
    let spellings: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("رپورٹ بھیجنا اعلیٰ ترجیح", { $0.priority == .p1 }),
      ("رپورٹ بھیجنا اعلی ترجیح", { $0.priority == .p1 }),
      ("رپورٹ بھیجنا اعلى ترجيح", { $0.priority == .p1 }),
      ("رپورٹ بھیجنا ضروري", { $0.priority == .p1 }),
      ("رپورٹ بھیجنا فوراً", { $0.priority == .p1 }),
      ("رپورٹ بھیجنا فورا", { $0.priority == .p1 }),
      ("رپورٹ بھیجنا أرجنٹ", { $0.priority == .p1 }),
      ("امی کو فون کرنا اج", { $0.plannedDayOffset == 0 }),
      ("امی کو فون کرنا أج", { $0.plannedDayOffset == 0 }),
      ("امی کو فون کرنا پرسوں", { $0.plannedDayOffset == 2 }),
      ("امی کو فون کرنا پرسون", { $0.plannedDayOffset == 2 }),
      ("امی کو فون کرنا جمعة", { $0.plannedDayOffset == 3 }),
      ("امی کو فون کرنا جمعه", { $0.plannedDayOffset == 3 }),
      ("امی کو فون کرنا اگلے هفته", { $0.plannedDayOffset == 7 }),
      ("امی کو فون کرنا ٣ دن بعد", { $0.plannedDayOffset == 3 }),
      ("میٹنگ ڈھائی بجے", { $0.startMinutes == 14 * 60 + 30 }),
      ("میٹنگ ڈهائی بجے", { $0.startMinutes == 14 * 60 + 30 }),
      ("میٹنگ ڈهائي بجے", { $0.startMinutes == 14 * 60 + 30 }),
      ("میٹنگ ڈہائی بجے", { $0.startMinutes == 14 * 60 + 30 }),
      ("میٹنگ ٥ بجے", { $0.startMinutes == 17 * 60 }),
      ("میٹنگ ۵ بجے", { $0.startMinutes == 17 * 60 }),
      ("رپورٹ لکھنا 2 گھنٹوں", { $0.estimatedMinutes == 120 }),
      ("رپورٹ لکھنا 2 گهنٹوں", { $0.estimatedMinutes == 120 }),
      ("رپورٹ لکھنا تقریباً 2 گھنٹے", { $0.estimatedMinutes == 120 }),
      ("رپورٹ لکھنا تقریبا 2 گھنٹے", { $0.estimatedMinutes == 120 }),
      ("ورزش ہفتے میں ایک بار", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("ورزش ہفتے مین ایک بار", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("ورزش هر هفته", { $0.recurrence == TaskRecurrenceRule(freq: .weekly) }),
      ("ورزش ہر پیر", { $0.recurrence == monday }),
      ("ورزش هر پير", { $0.recurrence == monday }),
      ("رپورٹ بھیجنا جمعہ تک", { $0.dueDayOffset == 3 }),
      ("رپورٹ بھیجنا جمعة تك", { $0.dueDayOffset == 3 }),
    ]
    for line in spellings {
      #expect(line.check(parse(line.text)), "\(line.text)")
    }
    // The title keeps the letters and signs as typed.
    let signs = parse("امِی کَو فون کرنا کل")
    #expect(signs.title == "امِی کَو فون کرنا")
    // A mark never splits a match from the letter it follows.
    let marked = parse("میٹنگ شَام 5 بَجے مہم")
    #expect(marked.startMinutes == 17 * 60)
    #expect(marked.title == "میٹنگ مہم")
  }

  @Test("A zero-width non-joiner or joiner inside a compound word, or none, changes nothing")
  func joiners() {
    for text in ["سہ پہر", "سہ\u{200C}پہر", "سہ\u{200D}پہر", "سہپہر"] {
      let parsed = parse("میٹنگ \(text) 4 بجے")
      #expect(parsed.startMinutes == 16 * 60, "\(text)")
      #expect(parsed.title == "میٹنگ", "\(text): title")
    }
    for text in ["لگ بھگ", "لگ\u{200C}بھگ", "لگ\u{200D}بھگ", "لگبھگ"] {
      let parsed = parse("میٹنگ \(text) 5 بجے")
      #expect(parsed.startMinutes == 17 * 60, "\(text)")
      #expect(parsed.title == "میٹنگ", "\(text): title")
    }
    for text in ["ڈیڈ لائن", "ڈیڈ\u{200C}لائن", "ڈیڈلائن"] {
      let parsed = parse("رپورٹ بھیجنا \(text) جمعہ")
      #expect(parsed.dueDayOffset == 3, "\(text)")
      #expect(parsed.title == "رپورٹ بھیجنا", "\(text): title")
    }
    for text in ["ہفتہ وار", "ہفتہ\u{200C}وار", "ہفتہ\u{200D}وار", "ہفتہوار"] {
      let parsed = parse("ورزش \(text)")
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly), "\(text)")
      #expect(parsed.title == "ورزش", "\(text): title")
    }
    for text in ["ہر\u{200C}روز", "ہر روز"] {
      #expect(parse("ورزش \(text)").recurrence == daily, "\(text)")
    }
    for text in ["کام کے دن", "کام\u{200C}کے\u{200C}دن"] {
      #expect(parse("ورزش ہر \(text)").recurrence == workdays, "\(text)")
    }
    for text in ["ویک اینڈ", "ویک\u{200C}اینڈ", "ویک\u{200D}اینڈ", "ویکاینڈ"] {
      #expect(parse("امی کو فون کرنا \(text)").plannedDayOffset == 4, "\(text)")
    }
    for text in ["آدھی رات", "آدھی\u{200C}رات"] {
      #expect(parse("میٹنگ \(text)").startMinutes == 0, "\(text)")
    }
    // A word that continues past its first letters with a joiner is another word.
    expectLinesUnread(["میٹنگ کل\u{200C}ہ", "میٹنگ پیر\u{200C}ی", "رپورٹ آج\u{200D}کا"], languages: ["ur"])
    // The title keeps the joiner as typed.
    let typed = "ویب\u{200C}سائٹ کی رپورٹ"
    #expect(Array(parse("\(typed) کل").title.unicodeScalars) == Array(typed.unicodeScalars))
  }

  @Test("The title keeps the letters and signs as they were typed")
  func titleKeepsTypedText() {
    // Arabic yeh and kaf, a vowel sign, and a tatweel in the title stay as typed.
    let typed = "امِي كو فون كرنا ڈهائي ســیب"
    let parsed = parse("\(typed) كل")
    #expect(parsed.plannedDayOffset == 1)
    #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    let digitsTyped = parse("٣ لوگوں کے ساتھ میٹنگ کل")
    #expect(digitsTyped.title == "٣ لوگوں کے ساتھ میٹنگ")
  }

  @Test("The Urdu full stop and comma left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("امی کو فون کرنا، کل، شام 5 بجے", "امی کو فون کرنا"), ("امی کو فون کرنا کل۔", "امی کو فون کرنا۔"),
      ("امی کو فون کرنا کل ۔", "امی کو فون کرنا۔"), ("کل، امی کو فون کرنا", "امی کو فون کرنا"),
      ("کل: امی کو فون کرنا", "امی کو فون کرنا"), ("امی کو فون کرنا - کل", "امی کو فون کرنا"),
      ("رپورٹ بھیجنا، جمعہ تک، اعلیٰ ترجیح", "رپورٹ بھیجنا"),
      ("دودھ، ڈبل روٹی اور انڈے کل خریدنا", "دودھ، ڈبل روٹی اور انڈے خریدنا"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The full stop is punctuation: it ends a word.
    #expect(parse("امی کو فون کرنا کل۔").plannedDayOffset == 1)
    #expect(parse("رپورٹ بھیجنا جمعہ تک۔").dueDayOffset == 3)
  }

  @Test("A title never gains a bidirectional control character")
  func noBidiControls() {
    let controls: Set<UInt32> = [
      0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
    ]
    for text in [
      "امی کو فون کرنا کل شام 5 بجے", "رپورٹ 12 مئی 20 منٹ", "ورزش ہر پیر اور جمعرات", "میٹنگ with Ahmed کل",
      "دودھ، کل، اعلیٰ ترجیح #فہرست",
    ] {
      let title = parse(text).title
      #expect(!title.unicodeScalars.contains { controls.contains($0.value) }, "\(text)")
    }
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    #expect(parse("کام کل").plannedDayOffset == 1)
    #expect(parse("کام شام 5 بجے").startMinutes == 17 * 60)
    #expect(parse("کام ہر پیر").recurrence == monday)
    #expect(parse("کام 20 منٹ").estimatedMinutes == 20)
    #expect(parse("کام #فہرست").tags == ["فہرست"])
  }

  @Test("The words the app itself uses for days, repeats, and priorities are read")
  func appWords() {
    // The interface's own wording for tomorrow, next week, and tomorrow morning.
    #expect(parse("امی کو فون کرنا آئندہ کل").plannedDayOffset == 1)
    #expect(parse("امی کو فون کرنا اگلا ہفتہ").plannedDayOffset == 7)
    #expect(parse("امی کو فون کرنا کل صبح").plannedDayOffset == 1)
    // Its repeat and priority names.
    #expect(parse("امی کو فون کرنا ہر دن").recurrence == daily)
    #expect(parse("امی کو فون کرنا ہر ہفتے").recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(parse("امی کو فون کرنا ہر مہینے").recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(parse("امی کو فون کرنا ہر سال").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("امی کو فون کرنا اعلیٰ ترجیح").priority == .p1)
    #expect(parse("امی کو فون کرنا معمولی ترجیح").priority == .p2)
    #expect(parse("امی کو فون کرنا کم ترجیح").priority == .p3)
    // The day the app writes for the past is no coming day.
    expectLinesUnread(["گزشتہ کل"], languages: ["ur"])
  }

  // MARK: - Beside other languages

  @Test("Beside Urdu, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "ur"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "ur"]).estimatedMinutes == 20)
    #expect(parse("رپورٹ 2h").estimatedMinutes == 120)
    #expect(parse("رپورٹ 30min").estimatedMinutes == 30)
    #expect(parse("رپورٹ 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "ur"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "ur"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "ur"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "ur"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times.
    #expect(parse("میٹنگ 5pm").startMinutes == 17 * 60)
    #expect(parse("میٹنگ 5 PM").startMinutes == 17 * 60)
    #expect(parse("میٹنگ 17:30").startMinutes == 17 * 60 + 30)
    // English lines read the same with Urdu beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "ur"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom کل at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting جمعہ کو at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("میٹنگ tomorrow شام 5 بجے")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "میٹنگ")
    let urduTitle = parse("اجلاس next friday")
    #expect(urduTitle.plannedDayOffset == 10)
    #expect(urduTitle.title == "اجلاس")
    #expect(parse("اجلاس 2h").estimatedMinutes == 120)
    let every = parse("امی کو فون کرنا every monday")
    #expect(every.recurrence == monday)
    #expect(every.title == "امی کو فون کرنا")
  }

  @Test("Urdu words are read only for a user who reads Urdu")
  func languageGate() {
    let line = parse("امی کو فون کرنا کل", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "امی کو فون کرنا کل")
    for languages in [["ur"], ["ur-PK"], ["ur_IN"], ["en-US", "ur-PK"], ["UR"], ["ur-Arab-PK"], ["fa", "ur"]] {
      #expect(parse("امی کو فون کرنا کل", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages' readers do not get Urdu words, even the ones that share its script.
    for languages in [["ar"], ["fa"], ["he"], ["hi"], ["tr"], ["pa"], ["sd"], ["ps"], ["ru"], ["ja"]] {
      #expect(parse("امی کو فون کرنا کل", languages: languages).plannedDayOffset == nil, "\(languages)")
    }
    // Urdu readers do not get other languages' words.
    #expect(parse("माँ को फोन करें कल", languages: ["ur"]).plannedDayOffset == nil)
    #expect(parse("اتصل بأمي غداً", languages: ["ur"]).plannedDayOffset == nil)
    #expect(parse("تماس با مادر فردا", languages: ["ur"]).plannedDayOffset == nil)
    #expect(parse("Zadzwonić jutro", languages: ["ur"]).plannedDayOffset == nil)
    #expect(parse("Позвонить завтра", languages: ["ur"]).plannedDayOffset == nil)
    // A clock time, a repeat, a length, and a priority with an Urdu word need Urdu among the languages.
    #expect(parse("میٹنگ 5 بجے", languages: ["en"]).startMinutes == nil)
    #expect(parse("دوا لیں ہر پیر", languages: ["en"]).recurrence == nil)
    #expect(parse("رپورٹ بھیجنا اعلیٰ ترجیح", languages: ["en"]).priority == nil)
    #expect(parse("رپورٹ لکھنا 30 منٹ", languages: ["en"]).estimatedMinutes == nil)
    // English and Chinese are read whatever the languages.
    #expect(parse("Call mom tomorrow", languages: ["ur"]).plannedDayOffset == 1)
    #expect(parse("明天打电话", languages: ["ur"]).plannedDayOffset == 1)
    // Urdu and Hindi readers get both, and so do Urdu and Persian readers.
    #expect(parse("माँ को फोन करें कल", languages: ["hi", "ur"]).plannedDayOffset == 1)
    #expect(parse("امی کو فون کرنا کل", languages: ["hi", "ur"]).plannedDayOffset == 1)
    #expect(parse("تماس با مادر فردا", languages: ["fa", "ur"]).plannedDayOffset == 1)
    #expect(parse("امی کو فون کرنا کل", languages: ["fa", "ur"]).plannedDayOffset == 1)
  }

  @Test("Lines in other languages read the same with Urdu beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"), ("تقرير قبل الخميس", "ar"),
      ("مراجعة من 3 إلى 5 مارس", "ar"), ("تماس با مادر فردا ساعت ۳ بعدازظهر", "fa"), ("ورزش هر دوشنبه", "fa"),
      ("گزارش تا جمعه", "fa"), ("कल शाम 5 बजे मीटिंग", "hi"), ("रिपोर्ट सोमवार तक", "hi"),
      ("हर सोमवार योग 30 मिनट", "hi"), ("Позвонить маме завтра в 15:00", "ru"), ("Appeler maman demain à 15h", "fr"),
      ("Llamar a mamá mañana a las 15:00", "es"), ("明日の午後3時に会議", "ja"), ("Zadzwonić jutro o 15:00", "pl"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "ur"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["ur", line.language]) == alone, "\(line.text): reversed")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("5 بجے ", 400), ("ہر پیر اور ", 250), ("3 سے ", 400), ("2 گھنٹے اور ", 350), ("ساڑھے ", 300), ("۱", 3000),
      ("ا", 3000), ("کل", 600), ("سہ\u{200C}", 1000), ("تک ", 900), ("ہفتے ", 500), ("اگلے جمعہ ", 200),
      ("دوپہر بعد ", 300), ("ہر ", 900), ("12 مئی ", 300), ("آدھا گھنٹہ ", 300), ("، ", 1500), ("اور ", 1500),
      ("ک\u{064E}", 2000), ("ہ\u{200C}", 2000), ("ـ", 3000), ("ہر شام کو ", 300), ("کے ", 1500),
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for entry in unit {
        let line = "امی " + String(repeating: entry.token, count: entry.repeats) + " فون"
        let parsed = parse(line)
        #expect(!parsed.title.isEmpty, "\(entry.token)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}
