import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["bn"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["bn"])
}

/// `text` with its ASCII digits written in the Bengali script (U+09E6-U+09EF).
private func bengaliDigits(_ text: String) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in text.unicodeScalars {
    if (0x30...0x39).contains(scalar.value), let digit = Unicode.Scalar(0x09E6 + scalar.value - 0x30) {
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

/// Bengali capture lines, read for a user whose languages include Bengali.
@Suite("Capture parser Bengali")
struct CaptureParserBengaliTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("মাকে ফোন করুন কাল")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "মাকে ফোন করুন")
    #expect(line.phrases.map(\.text) == ["কাল"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("আজ", 0), ("আজকে", 0), ("আজই", 0), ("আজকেই", 0), ("কাল", 1), ("কালকে", 1), ("কালই", 1),
      ("আগামীকাল", 1), ("আগামিকাল", 1), ("আগামী কাল", 1), ("পরশু", 2), ("পরশুদিন", 2), ("পরশুই", 2),
      ("আগামী পরশু", 2), ("৩ দিন পর", 3), ("৩ দিন পরে", 3), ("৩ দিন বাদে", 3), ("তিন দিন পর", 3),
      ("3 দিন পর", 3), ("১০ দিন পর", 10), ("পনেরো দিন পর", 15), ("১ দিন পর", 1), ("২ সপ্তাহ পর", 14),
      ("দুই সপ্তাহ পরে", 14), ("১ সপ্তাহ বাদে", 7), ("দুই হপ্তা পর", 14), ("১ মাস পর", 30),
      ("২ মাস পর", 61), ("পরের সপ্তাহে", 7), ("আসছে সপ্তাহে", 7), ("আগামী সপ্তাহে", 7), ("সামনের সপ্তাহে", 7),
      ("আসন্ন সপ্তাহে", 7), ("পরের হপ্তায়", 7),
    ]
    for day in days {
      let text = "মাকে ফোন করুন \(day.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day.offset, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "মাকে ফোন করুন", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("কাল মাকে ফোন করুন")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "মাকে ফোন করুন")
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("আজ সকালে", 0), ("আজ দুপুরে", 0), ("আজ বিকেলে", 0), ("আজ সন্ধ্যায়", 0), ("আজ রাতে", 0), ("আজ সকাল", 0),
      ("কাল সকালে", 1), ("কাল ভোরে", 1), ("কাল দুপুরে", 1), ("কাল বিকেলে", 1), ("কাল সন্ধ্যায়", 1),
      ("কাল রাতে", 1), ("কাল রাত্রিতে", 1), ("কাল সকালবেলা", 1), ("কাল সন্ধ্যাবেলায়", 1),
      ("আগামীকাল সকাল", 1), ("পরশু সন্ধ্যায়", 2), ("শুক্রবার সন্ধ্যায়", 3), ("শুক্রবার রাতে", 3),
      ("শনিবার সকালে", 4),
    ]
    for phrase in phrases {
      let text = "মাকে ফোন করুন \(phrase.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "মাকে ফোন করুন", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("আগামীকাল সকালে মিটিং ৬টায়")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "মিটিং")
    let evening = parse("আজ সন্ধ্যায় জিম ৭টায়")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "জিম")
    let night = parse("কাল রাতে খাবার ৯টায়")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 21 * 60)
    #expect(night.title == "খাবার")
    let written = parse("আজ রাত ৮টায় খাবার")
    #expect(written.plannedDayOffset == 0)
    #expect(written.startMinutes == 20 * 60)
    #expect(written.title == "খাবার")
    // The part of the day as a noun or alone names no day.
    expectLinesUnread(
      [
        "সকালের হাঁটা", "সন্ধ্যার চা", "রাতের খাবার", "দুপুরের খাবার", "সকালে হাঁটা", "রাতে ওষুধ খাওয়া",
        "সন্ধ্যায় বই পড়া",
      ], languages: ["bn"])
    // A genitive after the part of the day makes it an attribute of a noun:
    // only the day is read.
    let dinner = parse("কাল রাতের খাবার")
    #expect(dinner.plannedDayOffset == 1)
    #expect(dinner.title == "রাতের খাবার")
    let tea = parse("আগামীকাল সন্ধ্যার চা")
    #expect(tea.plannedDayOffset == 1)
    #expect(tea.title == "সন্ধ্যার চা")
  }

  @Test("An ending that goes with a day is read with it, and any other ending leaves the day unread")
  func dayEndings() {
    let days: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("আজই রিপোর্ট পাঠান", "রিপোর্ট পাঠান", 0, "আজই"),
      ("রিপোর্ট আজকেই পাঠান", "রিপোর্ট পাঠান", 0, "আজকেই"),
      ("রিপোর্ট কালই পাঠান", "রিপোর্ট পাঠান", 1, "কালই"),
      ("কালকে মিটিং", "মিটিং", 1, "কালকে"),
      ("রিপোর্ট আজ", "রিপোর্ট", 0, "আজ"),
      ("সোমবারে মিটিং", "মিটিং", 6, "সোমবারে"),
      ("সোমবারেই মিটিং", "মিটিং", 6, "সোমবারেই"),
      ("সোমবারই মিটিং", "মিটিং", 6, "সোমবারই"),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // An ending the vocabulary does not list leaves the day word unread, and
    // so does a genitive: "কালকের মিটিং" is tomorrow's meeting.
    expectLinesUnread(
      [
        "আজও রিপোর্ট পাঠান", "কালও যাব", "আজকের কাজ", "কালকের মিটিং", "আগামীকালের মিটিং", "সোমবারের মিটিং",
        "শনিবারের পার্টি", "শুক্রবারের খাবার", "প্রতিদিনের কাজ", "আজকের রিপোর্ট",
      ], languages: ["bn"])
  }

  @Test("থেকে and হতে after a day plan it, unless they start a counted day")
  func fromAfterDay() {
    let lines: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("আজ থেকে ব্যায়াম শুরু", "ব্যায়াম শুরু", 0, "আজ থেকে"),
      ("কাল থেকে জিম শুরু", "জিম শুরু", 1, "কাল থেকে"),
      ("কাল থেকেই ডায়েট", "ডায়েট", 1, "কাল থেকেই"),
      ("আগামীকাল থেকে ক্লাস", "ক্লাস", 1, "আগামীকাল থেকে"),
      ("সোমবার থেকে জিম শুরু", "জিম শুরু", 6, "সোমবার থেকে"),
      ("সোমবার হতে ক্লাস", "ক্লাস", 6, "সোমবার হতে"),
      ("১৫ অক্টোবর থেকে ক্লাস", "ক্লাস", 23, "১৫ অক্টোবর থেকে"),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // The থেকে of a counted day ties the amount to another event.
    expectLinesUnread(["আজ থেকে ৩ দিন পর কাজ", "সোমবার থেকে ২ সপ্তাহ পর কাজ"], languages: ["bn"])
    // A day from another day to a deadline reads as a plan and a deadline.
    let leave = parse("আজ থেকে কাল পর্যন্ত ছুটি")
    #expect(leave.plannedDayOffset == 0)
    #expect(leave.dueDayOffset == 1)
    #expect(leave.title == "ছুটি")
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "এই মঙ্গলবার" is today.
    let names: [(name: String, offset: Int)] = [
      ("বুধবার", 1), ("বৃহস্পতিবার", 2), ("বৃহষ্পতিবার", 2), ("শুক্রবার", 3), ("শনিবার", 4), ("রবিবার", 5),
      ("রোববার", 5), ("সোমবার", 6), ("মঙ্গলবার", 7),
    ]
    for weekday in names {
      for text in [
        "ফোন করুন \(weekday.name)", "ফোন করুন \(weekday.name)ে", "ফোন করুন \(weekday.name)েই",
        "ফোন করুন \(weekday.name)ই",
      ] {
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "ফোন করুন", "\(text): title")
      }
    }
    let modified: [(text: String, offset: Int)] = [
      ("ফোন করুন এই শুক্রবার", 3), ("ফোন করুন এই মঙ্গলবার", 0), ("ফোন করুন এই শনিবার", 4),
      ("ফোন করুন এই সোমবার", 6), ("ফোন করুন আগামী সোমবার", 6), ("ফোন করুন আগামী মঙ্গলবার", 7),
      ("ফোন করুন আগামী শুক্রবার", 3), ("ফোন করুন আসছে শুক্রবার", 3), ("ফোন করুন সামনের শুক্রবার", 3),
      ("ফোন করুন আসন্ন শুক্রবার", 3), ("ফোন করুন পরের সোমবার", 6), ("ফোন করুন পরের মঙ্গলবার", 7),
      ("ফোন করুন পরের বুধবার", 8), ("ফোন করুন পরের শুক্রবার", 10), ("ফোন করুন পরের শনিবার", 11),
      ("ফোন করুন পরের রবিবার", 12), ("ফোন করুন এই সপ্তাহের শুক্রবার", 3),
      ("ফোন করুন এই সপ্তাহের মঙ্গলবার", 0), ("ফোন করুন এই সপ্তাহে শুক্রবার", 3),
      ("ফোন করুন পরের সপ্তাহের শুক্রবার", 10), ("ফোন করুন পরের সপ্তাহের সোমবার", 6),
      ("ফোন করুন পরের সপ্তাহে শুক্রবার", 10), ("ফোন করুন আগামী সপ্তাহের শুক্রবার", 10),
      ("ফোন করুন আসছে সপ্তাহের সোমবার", 6), ("ফোন করুন পরের সপ্তাহের শুক্রবার সন্ধ্যায়", 10),
      ("ফোন করুন শুক্রবার থেকে", 3), ("ফোন করুন পরের শুক্রবার থেকে", 10),
    ]
    for line in modified {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text)")
      #expect(parsed.title == "ফোন করুন", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let opening = parse("শুক্রবার মাকে ফোন করুন")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "মাকে ফোন করুন")
    // "এই সপ্তাহে" alone names no single day.
    expectLinesUnread(["ফোন করুন এই সপ্তাহে", "এই সপ্তাহে রিপোর্ট"], languages: ["bn"])
  }

  @Test("The weekend: this one, next week's, and today when it is already here")
  func weekend() {
    for text in [
      "উইকেন্ড", "উইকেন্ডে", "এই উইকেন্ডে", "আগামী উইকেন্ডে", "উইক এন্ড", "উইক-এন্ড", "সপ্তাহান্ত", "সপ্তাহান্তে",
      "এই সপ্তাহান্তে", "সপ্তাহের শেষে", "শনিবার ও রবিবার", "শনিবার এবং রবিবার", "শনিবার-রবিবার",
      "শনিবার রবিবার", "শনি-রবিবার", "শনিবার ও রোববার",
    ] {
      let parsed = parse("ফোন করুন \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "ফোন করুন", "\(text): title")
    }
    for text in ["পরের উইকেন্ডে", "পরের সপ্তাহান্তে"] {
      #expect(parse("ফোন করুন \(text)").plannedDayOffset == 11, "\(text)")
    }
    // On a Saturday or a Sunday the weekend is already here.
    #expect(parse("ফোন করুন উইকেন্ডে", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("ফোন করুন উইকেন্ডে", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("ফোন করুন উইকেন্ডে", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("ফোন করুন পরের উইকেন্ডে", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
  }

  // MARK: - Dates

  @Test("Written dates: every month, in the spellings people type, with a year, a label, an ending, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("৫ জানুয়ারি", "2027-01-05"), ("৫ জানুয়ারী", "2027-01-05"), ("৫ ফেব্রুয়ারি", "2027-02-05"),
      ("৫ ফেব্রুয়ারী", "2027-02-05"), ("৫ ফেব্রুআরি", "2027-02-05"), ("৫ মার্চ", "2027-03-05"),
      ("৫ এপ্রিল", "2027-04-05"), ("৫ মে", "2027-05-05"), ("৫ জুন", "2027-06-05"), ("৫ জুলাই", "2027-07-05"),
      ("৫ আগস্ট", "2027-08-05"), ("৫ আগষ্ট", "2027-08-05"), ("৫ সেপ্টেম্বর", "2027-09-05"),
      ("৫ অক্টোবর", "2026-10-05"), ("৫ নভেম্বর", "2026-11-05"), ("৫ ডিসেম্বর", "2026-12-05"),
      ("২২ সেপ্টেম্বর", "2026-09-22"), ("5 অক্টোবর", "2026-10-05"), ("৫ জানু", "2027-01-05"),
      ("৫ ফেব্রু", "2027-02-05"), ("৫ ফেব", "2027-02-05"), ("৫ এপ্রি", "2027-04-05"), ("৫ জুল", "2027-07-05"),
      ("৫ আগ", "2027-08-05"), ("৫ সেপ", "2027-09-05"), ("৫ সেপ্ট", "2027-09-05"), ("৫ সেপ্টে", "2027-09-05"),
      ("৫ অক্টো", "2026-10-05"), ("৫ অক্টো.", "2026-10-05"), ("৫ অক্টোঃ", "2026-10-05"),
      ("৫ নভে", "2026-11-05"), ("৫ নভেঃ", "2026-11-05"), ("৫ ডিসে", "2026-12-05"), ("৫ ডিসেঃ", "2026-12-05"),
      ("৫ অক্টোবরে", "2026-10-05"), ("৫ জুলাইয়ে", "2027-07-05"), ("৫ মে থেকে", "2027-05-05"),
      ("৫ অক্টোবরের জন্য", "2026-10-05"), ("৫ মে ২০২৭", "2027-05-05"), ("৫ মে ২০২৮", "2028-05-05"),
      ("৫ মে, ২০২৮", "2028-05-05"), ("১৫ অক্টোবর, ২০২৬", "2026-10-15"), ("১৫ অক্টোবর ২০২৬-এ", "2026-10-15"),
      ("৫ই মে", "2027-05-05"), ("১লা মে", "2027-05-01"), ("২রা মে", "2027-05-02"), ("৩রা মে", "2027-05-03"),
      ("৪ঠা মে", "2027-05-04"), ("১৫ই অক্টোবর", "2026-10-15"), ("১৯শে অক্টোবর", "2026-10-19"),
      ("তারিখ ৫ মে", "2027-05-05"), ("তারিখ: ৫ মে", "2027-05-05"), ("সোমবার, ৫ অক্টোবর", "2026-10-05"),
      ("সোমবার ৫ অক্টোবর", "2026-10-05"), ("অক্টোবর ১৫", "2026-10-15"), ("অক্টোবর ১৫, ২০২৬", "2026-10-15"),
      ("জানুয়ারি ২০", "2027-01-20"), ("মে ৫", "2027-05-05"), ("১৫ তারিখে", "2026-10-15"),
      ("৫ তারিখে", "2026-10-05"), ("১৫ তারিখ থেকে", "2026-10-15"), ("১৫/১০/২০২৬", "2026-10-15"),
      ("১৫.১০.২০২৬", "2026-10-15"), ("১৫-১০-২০২৬", "2026-10-15"), ("১৫.১০.", "2026-10-15"),
      ("তারিখ ১৫/১০", "2026-10-15"), ("তারিখ ১৫.১০", "2026-10-15"), ("১৫/১০ এ", "2026-10-15"),
      ("১৫/১০-এ", "2026-10-15"), ("১৫/১০এ", "2026-10-15"), ("১৫/১০ থেকে", "2026-10-15"),
      ("15/10/2026", "2026-10-15"), ("15 অক্টোবর", "2026-10-15"),
    ]
    for line in dates {
      let text = "মাকে ফোন করুন \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "মাকে ফোন করুন", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
  }

  @Test("A month needs its day beside it, and a short month after a day only")
  func unreadDates() {
    expectLinesUnread(
      [
        // The Bengali calendar's months are not Gregorian dates.
        "ফোন করুন ৫ বৈশাখ", "ফোন করুন ১৫ আষাঢ়", "ফোন করুন আষাঢ় ১৫", "পূজা ১০ কার্তিক",
        // A month alone, a short month before its day, and a day of the month alone.
        "ছুটি মে মাসে", "ফোন করুন জানু ২০", "ফোন করুন অক্টো ২০", "ফোন করুন আগ ২০", "ভাড়া ৫ তারিখ",
        // A month before a count of things, and a day the month does not have.
        "মিটিং মে ১০ টাকা", "ফোন করুন ৩১ এপ্রিল", "ফোন করুন ৩০ ফেব্রুয়ারি", "ফোন করুন ৩২ মে",
        // Digits only, with no label and no ending.
        "ফোন করুন ৫/১০", "ফোন করুন ৫.১০", "ফোন করুন ১৫-১০", "ফোন করুন 15/10",
      ], languages: ["bn"])
    // A full month name before its day is a date, a short one is not.
    #expect(parse("ছুটি মে ৫").plannedDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("ছুটি", "৩ থেকে ৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ থেকে ৫ মার্চ পর্যন্ত", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ থেকে ৫ মার্চ অবধি", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ হতে ৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ মার্চ থেকে ৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ মার্চ থেকে ৫ মার্চ পর্যন্ত", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ মার্চ হতে ৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩০ জানুয়ারি থেকে ২ ফেব্রুয়ারি", "2027-01-30", "2027-02-02"),
        ("ছুটি", "৩-৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩–৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ মার্চ - ৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ থেকে ৫ মার্চ ২০২৭", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ থেকে ৫ মার্চে", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ থেকে ৫ মার্চ ২০২৭-এ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "৩ মার্চ থেকে ৫ জুলাইয়ে", "2027-03-03", "2027-07-05"),
        ("ছুটি", "৩ই থেকে ৫ই মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "3 থেকে 5 মার্চ", "2027-03-03", "2027-03-05"),
        ("পরিবারের সাথে ছুটি", "৩ থেকে ৫ মার্চ", "2027-03-03", "2027-03-05"),
        ("ছুটি", "২৫ সেপ্টেম্বর থেকে ৩ অক্টোবর", "2026-09-25", "2026-10-03"),
        ("ছুটি", "৩০ ডিসেম্বর থেকে ২ জানুয়ারি", "2026-12-30", "2027-01-02"),
        ("সম্মেলন", "১২-১৪ অক্টোবর", "2026-10-12", "2026-10-14"),
      ], languages: ["bn"])
  }

  @Test("A range whose end is not after its start, or that names no month, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "ছুটি ৫ থেকে ৩ মার্চ", "ছুটি ৩ মার্চ থেকে ৩ মার্চ", "ছুটি ৫-৩ মার্চ", "ছুটি ৫ মার্চ থেকে ৩ মার্চ",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "ছুটি ৩ থেকে ৫",
        // A range in the past, or one that a genitive follows, may be an event
        // the task only prepares for.
        "৩ থেকে ৫ মার্চ ছুটি ছিল", "৩ থেকে ৫ মার্চের ছুটি", "৫ থেকে ৮ মে-র ছুটি",
      ], languages: ["bn"])
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 মার্চ")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("Sprint", "12-20 মার্চ", "2027-03-12", "2027-03-20")], languages: ["bn"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("ছুটি ৩ থেকে ৫ মার্চ কাল")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "ছুটি কাল")
    let timed = parse("ছুটি ৩ থেকে ৫ মার্চ সন্ধ্যা ৬টায়")
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "ছুটি")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("রিপোর্ট সোমবার থেকে বুধবার")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "রিপোর্ট")
    #expect(span.phrases.map(\.text) == ["সোমবার থেকে বুধবার"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("ভ্রমণ শুক্রবার থেকে সোমবার", 3, 6), ("ভ্রমণ শনিবার থেকে রবিবার", 4, 5),
      ("ভ্রমণ শুক্রবার থেকে রবিবার পর্যন্ত", 3, 5), ("ভ্রমণ শুক্রবার হতে রবিবার", 3, 5),
      ("ভ্রমণ শুক্রবারে থেকে রবিবারে", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("শিবির মঙ্গলবার থেকে বৃহস্পতিবার", 7, 9), ("শিবির বুধবার থেকে শুক্রবার", 1, 3),
    ]
    for line in spans {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day")
      #expect(parsed.dueDayOffset == line.due, "\(line.text): due day")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Monday to Friday with no word for every day may be a week of work as
    // well as the working week, so it stays in the title.
    expectLinesUnread(
      [
        "জিম সোমবার থেকে শুক্রবার", "প্রশিক্ষণ সোমবার থেকে শুক্রবার পর্যন্ত", "প্রশিক্ষণ সোমবার হতে শুক্রবার",
      ], languages: ["bn"])
    // A span in the past, or one that a genitive follows, is no plan.
    expectLinesUnread(
      ["সোমবার থেকে বুধবারের ছুটি", "সোমবার থেকে বুধবার ছুটি ছিল"], languages: ["bn"])
  }

  // MARK: - Due days

  @Test("Due days: পর্যন্ত, অবধি, মধ্যে, আগে, and the labels শেষ তারিখ and ডেডলাইন")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("রিপোর্ট পাঠান শুক্রবার পর্যন্ত", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান শুক্রবার অবধি", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান শুক্রবারের মধ্যে", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান শুক্রবারের আগে", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান শুক্রবারের পূর্বে", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান মঙ্গলবার পর্যন্ত", "রিপোর্ট পাঠান", 7),
      ("রিপোর্ট পাঠান পরের শুক্রবার পর্যন্ত", "রিপোর্ট পাঠান", 10),
      ("রিপোর্ট পাঠান এই শুক্রবার পর্যন্ত", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান আগামীকাল পর্যন্ত", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান কাল পর্যন্ত", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান কালকের মধ্যে", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান আগামীকালের আগে", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান পরশু পর্যন্ত", "রিপোর্ট পাঠান", 2),
      ("রিপোর্ট পাঠান কাল সন্ধ্যা পর্যন্ত", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান কাল সকালের মধ্যে", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান আজ সন্ধ্যা পর্যন্ত", "রিপোর্ট পাঠান", 0),
      ("রিপোর্ট পাঠান আজ রাত পর্যন্ত", "রিপোর্ট পাঠান", 0),
      ("রিপোর্ট পাঠান আজ রাতের মধ্যে", "রিপোর্ট পাঠান", 0),
      ("রিপোর্ট পাঠান আজকের মধ্যে", "রিপোর্ট পাঠান", 0),
      ("কাল সকালের মধ্যে রিপোর্ট পাঠান", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান ৫ মে পর্যন্ত", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান ৫ মে অবধি", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান ৫ মে-র মধ্যে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান ১৫ অক্টোবর পর্যন্ত", "রিপোর্ট পাঠান", captureDayOffset("2026-10-15")),
      ("রিপোর্ট পাঠান ১৫ অক্টোবরের মধ্যে", "রিপোর্ট পাঠান", captureDayOffset("2026-10-15")),
      ("রিপোর্ট পাঠান ৫ তারিখ পর্যন্ত", "রিপোর্ট পাঠান", captureDayOffset("2026-10-05")),
      ("রিপোর্ট পাঠান ৫ তারিখের মধ্যে", "রিপোর্ট পাঠান", captureDayOffset("2026-10-05")),
      ("রিপোর্ট পাঠান শেষ তারিখ ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান শেষ তারিখ: ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("শেষ তারিখ: ৫ মে রিপোর্ট পাঠান", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান শেষ তারিখ: শুক্রবার", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান শেষ তারিখ: আজ", "রিপোর্ট পাঠান", 0),
      ("রিপোর্ট পাঠান শেষ তারিখ: আগামীকাল", "রিপোর্ট পাঠান", 1),
      ("রিপোর্ট পাঠান শেষ তারিখ হবে শুক্রবার", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান অন্তিম তারিখ ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান ডেডলাইন: ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান ডেডলাইন ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান ডেড লাইন ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("ডেডলাইন শুক্রবার রিপোর্ট পাঠান", "রিপোর্ট পাঠান", 3),
      ("রিপোর্ট পাঠান সময়সীমা ৫ মে", "রিপোর্ট পাঠান", captureDayOffset("2027-05-05")),
      ("রিপোর্ট পাঠান সময়সীমা: শুক্রবার", "রিপোর্ট পাঠান", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("রিপোর্ট পাঠান শুক্রবার পর্যন্ত কাল")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "রিপোর্ট পাঠান")
  }

  @Test("নির্ধারিত names the planned day as much as the due day, so it is no deadline word")
  func scheduledIsNotDue() {
    let day = parse("রিপোর্ট পাঠান নির্ধারিত শুক্রবার")
    #expect(day.dueDayOffset == nil)
    #expect(day.plannedDayOffset == 3)
    #expect(day.title == "রিপোর্ট পাঠান নির্ধারিত")
    let date = parse("রিপোর্ট পাঠান নির্ধারিত তারিখ ৫ মে")
    #expect(date.dueDayOffset == nil)
    #expect(date.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(date.title == "রিপোর্ট পাঠান নির্ধারিত")
  }

  @Test("\"আজ পর্যন্ত\" means \"so far\", and a deadline that a genitive follows is no deadline")
  func notDueDays() {
    expectLinesUnread(
      [
        "রিপোর্ট আজ পর্যন্ত", "রিপোর্ট আজ অবধি", "শুক্রবারের রিপোর্ট", "শুক্রবারের আগের রিপোর্ট",
        "রিপোর্ট শুক্রবার পর্যন্তের",
      ], languages: ["bn"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "রিপোর্ট পাঠান ৫টার মধ্যে", "রিপোর্ট পাঠান সন্ধ্যা ৬টার আগে", "রিপোর্ট পাঠান ৫টা পর্যন্ত",
        "রিপোর্ট পাঠান ১৮:০০ পর্যন্ত", "রিপোর্ট পাঠান ৩ PM পর্যন্ত", "রিপোর্ট পাঠান সাড়ে ৩টা পর্যন্ত",
        "রিপোর্ট পাঠান পাঁচটার মধ্যে", "রিপোর্ট পাঠান ৫:৩০টার মধ্যে", "রিপোর্ট পাঠান ৫টার পরে",
        "রিপোর্ট পাঠান মধ্যরাত পর্যন্ত", "রিপোর্ট পাঠান মধ্যরাতের পরে", "রিপোর্ট পাঠান ১৮:০০-এর মধ্যে",
      ], languages: ["bn"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("রিপোর্ট পাঠান শুক্রবার সন্ধ্যা ৫টার মধ্যে")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "রিপোর্ট পাঠান সন্ধ্যা ৫টার মধ্যে")
    let tomorrow = parse("রিপোর্ট পাঠান কাল ৫টার মধ্যে")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "রিপোর্ট পাঠান ৫টার মধ্যে")
    // A planned day beside the clock deadline reads, and the clock stays.
    let day = parse("রিপোর্ট পাঠান ৫টার মধ্যে কাল")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    #expect(day.title == "রিপোর্ট পাঠান ৫টার মধ্যে")
    // A time range that ends in "পর্যন্ত" is still a range.
    let range = parse("মিটিং ২টা থেকে ৪টা পর্যন্ত")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "মিটিং")
    // Without Bengali, English reads the clock time and leaves the word.
    let english = parse("রিপোর্ট পাঠান ১৮:০০ পর্যন্ত", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "রিপোর্ট পাঠান পর্যন্ত")
  }

  // MARK: - Times

  @Test("Clock times: টায় after the hour, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("মিটিং ৫টায়", "মিটিং", 17 * 60), ("মিটিং ৫:৩০টায়", "মিটিং", 17 * 60 + 30),
      ("মিটিং ৫.৩০টায়", "মিটিং", 17 * 60 + 30), ("মিটিং 5টায়", "মিটিং", 17 * 60),
      ("মিটিং ঠিক ৫টায়", "মিটিং", 17 * 60), ("মিটিং প্রায় ৫টায়", "মিটিং", 17 * 60),
      ("মিটিং আনুমানিক ৫টায়", "মিটিং", 17 * 60), ("মিটিং মোটামুটি ৫টায়", "মিটিং", 17 * 60),
      ("৫টার সময় মিটিং", "মিটিং", 17 * 60), ("মিটিং ৫টা নাগাদ", "মিটিং", 17 * 60),
      ("মিটিং ৫টার দিকে", "মিটিং", 17 * 60), ("মিটিং সকাল ৯টায়", "মিটিং", 9 * 60),
      ("মিটিং সকাল ৯টা", "মিটিং", 9 * 60), ("মিটিং সকাল ৯টে", "মিটিং", 9 * 60),
      ("মিটিং সকাল ৯টো", "মিটিং", 9 * 60), ("মিটিং সকালে ৯টায়", "মিটিং", 9 * 60),
      ("মিটিং সকাল ৯:৩০", "মিটিং", 9 * 60 + 30), ("মিটিং সকাল ৯:৩০টায়", "মিটিং", 9 * 60 + 30),
      ("মিটিং সকাল ৯:১৫", "মিটিং", 9 * 60 + 15), ("মিটিং ভোর ৪টায়", "মিটিং", 4 * 60),
      ("মিটিং দুপুর ১২টায়", "মিটিং", 12 * 60), ("মিটিং দুপুর ১টায়", "মিটিং", 13 * 60),
      ("মিটিং দুপুর ২টায়", "মিটিং", 14 * 60), ("মিটিং দুপুর ৩:৩০টায়", "মিটিং", 15 * 60 + 30),
      ("মিটিং বিকেল ৫টায়", "মিটিং", 17 * 60), ("মিটিং বিকাল ৫টায়", "মিটিং", 17 * 60),
      ("মিটিং বিকেল ৫:৩০", "মিটিং", 17 * 60 + 30), ("মিটিং সন্ধ্যা ৭টায়", "মিটিং", 19 * 60),
      ("মিটিং সন্ধ্যা ৬টায়", "মিটিং", 18 * 60), ("মিটিং সন্ধ্যে ৭টায়", "মিটিং", 19 * 60),
      ("মিটিং সন্ধে ৭টায়", "মিটিং", 19 * 60), ("মিটিং সন্ধ্যাবেলা ৭টায়", "মিটিং", 19 * 60),
      ("মিটিং রাত ১০টায়", "মিটিং", 22 * 60), ("মিটিং রাত ৯টায়", "মিটিং", 21 * 60),
      ("মিটিং রাত ১১টায়", "মিটিং", 23 * 60), ("মিটিং রাত ১০.৩০", "মিটিং", 22 * 60 + 30),
      ("মিটিং রাতের ১০টায়", "মিটিং", 22 * 60), ("মিটিং রাতে ঠিক ১০টায়", "মিটিং", 22 * 60),
      ("মিটিং সকালে ঠিক ৬টায়", "মিটিং", 6 * 60), ("মিটিং সকালবেলা ৬টায়", "মিটিং", 6 * 60),
      ("মিটিং ১৭:৩০-এ", "মিটিং", 17 * 60 + 30), ("মিটিং ১৭:৩০এ", "মিটিং", 17 * 60 + 30),
      ("মিটিং ৩:৩০ PM-এ", "মিটিং", 15 * 60 + 30), ("মিটিং ৭:৩০ এ", "মিটিং", 7 * 60 + 30),
      ("মিটিং সন্ধ্যা ৭:৩০ এ", "মিটিং", 19 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day after the time is not read, and it names the half of
    // the day of the hour all the same.
    let after = parse("মিটিং ৫টায় সকালে")
    #expect(after.startMinutes == 5 * 60)
    #expect(after.title == "মিটিং সকালে")
    let evening = parse("মিটিং ৭টায় সন্ধ্যায়")
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "মিটিং সন্ধ্যায়")
    // The part of the day written before the hour wins over one written after it.
    let both = parse("মিটিং সকাল ৯টায় সন্ধ্যায়")
    #expect(both.startMinutes == 9 * 60)
    #expect(both.title == "মিটিং সন্ধ্যায়")
    // Twelve in the morning is no time, and neither is 24 o'clock.
    #expect(parse("মিটিং সকাল ১২টায়").startMinutes == nil)
    #expect(parse("মিটিং ২৪টায়").startMinutes == nil)
  }

  @Test("An hour as a number word is read with its classifier and ending")
  func numberWordHours() {
    let hours: [(word: String, minutes: Int)] = [
      ("একটায়", 13 * 60), ("দুটোয়", 14 * 60), ("দুইটায়", 14 * 60), ("তিনটেয়", 15 * 60), ("তিনটায়", 15 * 60),
      ("চারটায়", 16 * 60), ("পাঁচটায়", 17 * 60), ("ছটায়", 18 * 60), ("ছয়টায়", 18 * 60), ("সাতটায়", 7 * 60),
      ("আটটায়", 8 * 60), ("নয়টায়", 9 * 60), ("নটায়", 9 * 60), ("দশটায়", 10 * 60), ("এগারোটায়", 11 * 60),
      ("এগারটায়", 11 * 60), ("বারোটায়", 12 * 60), ("বারটায়", 12 * 60),
    ]
    for hour in hours {
      let text = "মিটিং \(hour.word)"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "মিটিং", "\(text): title")
    }
    #expect(parse("মিটিং সকাল নয়টায়").startMinutes == 9 * 60)
    #expect(parse("মিটিং সন্ধ্যা সাতটায়").startMinutes == 19 * 60)
    // A number word is a count anywhere else, and an hour with no ending, part
    // of the day, or fraction counts things.
    expectLinesUnread(
      [
        "মিটিং পাঁচ", "মিটিং এক", "তিন জন আসবে", "দুই বন্ধু", "সাত দিন", "মিটিং তিন থেকে পাঁচ", "মিটিং পাঁচটা",
        "মিটিং তিনটে", "মিটিং দুটো",
      ], languages: ["bn"])
  }

  @Test("Clock fractions: সাড়ে, সোয়া, পৌনে, দেড়, and আড়াই")
  func clockFractions() {
    let fractions: [(text: String, minutes: Int)] = [
      ("মিটিং সাড়ে ৫টায়", 17 * 60 + 30), ("মিটিং সাড়ে ৫টা", 17 * 60 + 30), ("মিটিং সাড়ে পাঁচটায়", 17 * 60 + 30),
      ("মিটিং সাড়ে তিনটে", 15 * 60 + 30), ("মিটিং সাড়ে তিনটায়", 15 * 60 + 30), ("মিটিং সোয়া ৫টায়", 17 * 60 + 15),
      ("মিটিং সওয়া ৫টায়", 17 * 60 + 15), ("মিটিং সোয়া পাঁচটায়", 17 * 60 + 15),
      ("মিটিং সোয়া দুইটায়", 14 * 60 + 15), ("মিটিং পৌনে ৬টায়", 17 * 60 + 45),
      ("মিটিং পৌনে ছয়টায়", 17 * 60 + 45), ("মিটিং পৌনে ছটায়", 17 * 60 + 45), ("মিটিং পৌনে চারটায়", 15 * 60 + 45),
      ("মিটিং পৌনে একটায়", 12 * 60 + 45), ("মিটিং পৌনে বারোটায়", 11 * 60 + 45), ("মিটিং দেড়টায়", 13 * 60 + 30),
      ("মিটিং দেড়টেয়", 13 * 60 + 30), ("মিটিং আড়াইটায়", 14 * 60 + 30), ("মিটিং আড়াইটা", 14 * 60 + 30),
      ("মিটিং সকাল সাড়ে নয়টায়", 9 * 60 + 30), ("মিটিং সকাল পৌনে দশটায়", 9 * 60 + 45),
      ("মিটিং সকাল সোয়া আটটায়", 8 * 60 + 15), ("মিটিং সন্ধ্যা সাড়ে ৬টায়", 18 * 60 + 30),
      ("মিটিং সন্ধ্যা সাড়ে ছয়টায়", 18 * 60 + 30), ("মিটিং রাত পৌনে দশটায়", 21 * 60 + 45),
    ]
    for line in fractions {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "মিটিং", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A fraction counts from an hour on the clock face.
    #expect(parse("মিটিং সাড়ে ১৩টায়").startMinutes == nil)
    #expect(parse("মিটিং দেড়টায় সকালে").startMinutes == 90)
  }

  @Test("The minutes of an hour with the locative of মিনিট: \"সকাল ১০টা ৩০ মিনিটে\" is 10:30")
  func minutesAfterHour() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("সকাল ১০টা ৩০ মিনিটে মিটিং", "মিটিং", 10 * 60 + 30), ("সকাল ৯টা ১৫ মিনিটে মিটিং", "মিটিং", 9 * 60 + 15),
      ("৫টা ৩০ মিনিটে মিটিং", "মিটিং", 17 * 60 + 30), ("সকাল ৯টা পনেরো মিনিটে মিটিং", "মিটিং", 9 * 60 + 15),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
    }
    // Minutes with no locative are a length, and minutes after a locative hour are two phrases.
    let length = parse("৫টা ৩০ মিনিট মিটিং")
    #expect(length.estimatedMinutes == 30)
    #expect(length.startMinutes == nil)
    #expect(length.title == "৫টা মিটিং")
    let apart = parse("৫টায় ৩০ মিনিটে শেষ")
    #expect(apart.startMinutes == 17 * 60)
    #expect(apart.title == "৩০ মিনিটে শেষ")
  }

  @Test("After midnight: রাত runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("মিটিং রাত ২টায়")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "মিটিং")
    let twelve = parse("মিটিং রাত ১২টায়")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    for text in ["মিটিং মধ্যরাতে", "মিটিং মধ্যরাত্রে", "মিটিং মাঝরাতে", "মিটিং ঠিক মধ্যরাতে"] {
      let midnight = parse(text)
      #expect(midnight.startMinutes == 0, "\(text)")
      #expect(midnight.plannedDayOffset == 1, "\(text)")
      #expect(midnight.title == "মিটিং", "\(text): title")
    }
    // The night counts from the evening: 6 to 11 is the evening's.
    #expect(parse("মিটিং রাত ৬টায়").startMinutes == 18 * 60)
    #expect(parse("মিটিং রাত ৬টায়").plannedDayOffset == nil)
    // A named day keeps the time on its own night: "কাল রাত ১টায়" is 01:00 of the day after.
    let tomorrow = parse("কাল রাত ১টায় ঘুম")
    #expect(tomorrow.startMinutes == 60)
    #expect(tomorrow.plannedDayOffset == 2)
    #expect(tomorrow.title == "ঘুম")
    let named = parse("সোমবার রাত ১২টায় ফ্লাইট")
    #expect(named.startMinutes == 0)
    #expect(named.plannedDayOffset == 7)
    #expect(named.title == "ফ্লাইট")
    // A repeat moves to the day after, so the rule and the time agree.
    let repeating = parse("প্রতি শুক্রবার রাত ১২টায় ফ্লাইট")
    #expect(repeating.startMinutes == 0)
    #expect(repeating.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(repeating.recurrenceStartOffset == 4)
    #expect(repeating.title == "ফ্লাইট")
    // A midnight deadline is no time.
    expectLinesUnread(["রিপোর্ট পাঠান মধ্যরাত পর্যন্ত"], languages: ["bn"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("মিটিং ১টায়").startMinutes == 13 * 60)
    #expect(parse("মিটিং ৩টায়").startMinutes == 15 * 60)
    #expect(parse("মিটিং ৬টায়").startMinutes == 18 * 60)
    #expect(parse("মিটিং ৭টায়").startMinutes == 7 * 60)
    #expect(parse("মিটিং ৯টায়").startMinutes == 9 * 60)
    #expect(parse("মিটিং ১১টায়").startMinutes == 11 * 60)
    #expect(parse("মিটিং ১২টায়").startMinutes == 12 * 60)
    #expect(parse("মিটিং ১৩টায়").startMinutes == 13 * 60)
    #expect(parse("মিটিং ০৬:৩০টায়").startMinutes == 6 * 60 + 30)
    #expect(parse("মিটিং ০৩:০০টায়").startMinutes == 3 * 60)
    #expect(parse("মিটিং ৩:০০টায়").startMinutes == 15 * 60)
    // A part of the day names the half of the day either way.
    #expect(parse("মিটিং সকাল ৫টায়").startMinutes == 5 * 60)
    #expect(parse("মিটিং বিকেল ৫টায়").startMinutes == 17 * 60)
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("সকালের হাঁটা ৬টায়", "সকালের হাঁটা", 6 * 60), ("৬টায় সকালের হাঁটা", "সকালের হাঁটা", 6 * 60),
      ("সকালের হাঁটা ৫টায়", "সকালের হাঁটা", 5 * 60), ("রাতের খাবার ৮টায়", "রাতের খাবার", 20 * 60),
      ("রাতের খাবার ৬টায়", "রাতের খাবার", 18 * 60), ("রাতের খাবার সাড়ে আটটায়", "রাতের খাবার", 20 * 60 + 30),
      ("রাতের ওষুধ ১০টায়", "রাতের ওষুধ", 22 * 60), ("সন্ধ্যার চা ৫টায়", "সন্ধ্যার চা", 17 * 60),
      ("দুপুরের খাবার ১টায়", "দুপুরের খাবার", 13 * 60), ("দুপুরের খাবার ২টায়", "দুপুরের খাবার", 14 * 60),
      // The 24-hour clock is read as written: a leading zero, or 13 and later.
      ("রাতের খাবার ২০:০০টায়", "রাতের খাবার", 20 * 60), ("রাতের ডিউটি ০৬:৩০টায়", "রাতের ডিউটি", 6 * 60 + 30),
      // Noon is no morning hour, so a morning's 12 stays as written.
      ("সকালের বৈঠক ১২টায়", "সকালের বৈঠক", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The part of the day may come from the day phrase, and the day is read too.
    let dinner = parse("আজ রাতের খাবার ৮টায়")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "রাতের খাবার")
    // Two parts that differ leave the hour as it reads alone.
    #expect(parse("সকালের ওষুধ সন্ধ্যার চা ৫টায়").startMinutes == 17 * 60)
  }

  @Test("Time ranges: থেকে and হতে, a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("মিটিং ৩টা থেকে ৫টা", 15 * 60, 120), ("মিটিং ৩ থেকে ৫টায়", 15 * 60, 120), ("মিটিং ৩-৫টায়", 15 * 60, 120),
      ("মিটিং ২টা-৪টা", 14 * 60, 120), ("মিটিং ২–৪টায়", 14 * 60, 120), ("মিটিং সকাল ৯টা থেকে ১১টা", 9 * 60, 120),
      ("মিটিং সকাল ৯টা থেকে ১১টা পর্যন্ত", 9 * 60, 120), ("মিটিং সকাল ৯ থেকে ১১টায়", 9 * 60, 120),
      ("মিটিং সন্ধ্যা ৫টা থেকে ৭টা", 17 * 60, 120), ("মিটিং রাত ৮টা থেকে ১০টা", 20 * 60, 120),
      ("মিটিং দুটো থেকে চারটে", 14 * 60, 120), ("মিটিং দুপুর ২টা থেকে বিকেল ৪টা", 14 * 60, 120),
      ("মিটিং তিনটা হতে পাঁচটা", 15 * 60, 120), ("মিটিং ১৪:০০ থেকে ১৬:০০", 14 * 60, 120),
      ("মিটিং ৯:৩০ থেকে ১০:৩০ পর্যন্ত", 9 * 60 + 30, 60), ("মিটিং ১৪:০০ হতে ১৬:০০", 14 * 60, 120),
      ("মিটিং ১৪:০০-১৬:০০", 14 * 60, 120), ("মিটিং সকাল ৯:০০ থেকে বিকেল ৫:০০", 9 * 60, 480),
      ("মিটিং ৯টা থেকে ৫টা", 9 * 60, 480), ("মিটিং ১০টা থেকে ১২টা", 10 * 60, 120),
      ("মিটিং ১১টা থেকে ১টা", 11 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "মিটিং", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The end carries a classifier: two bare numbers are no range.
    expectLinesUnread(["মিটিং ৩ থেকে ৫", "মিটিং তিন থেকে পাঁচ"], languages: ["bn"])
    // A length written in the line wins over the span of the range.
    let named = parse("মিটিং ৩ থেকে ৫টায় ৩০ মিনিট")
    #expect(named.startMinutes == 15 * 60)
    #expect(named.estimatedMinutes == 30)
    #expect(named.title == "মিটিং")
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amounts() {
    expectLinesUnread(
      [
        "৩ জনের সাথে মিটিং", "মিটিংয়ে ৩ জন আসবে", "৫টা বই কেনা", "১০ পৃষ্ঠা পড়া", "২ কেজি চিনি আনা",
        "১২টা ডিম আনা", "৫০০ টাকার বিল দেওয়া", "৳৫০০ বিল", "বিল ৳৫০০", "৫ ডলার খরচ", "২০% ছাড়", "২০ % ছাড়",
        "২টা ক্লাস নেওয়া", "৫টায় টাকা তোলা",
      ], languages: ["bn"])
    // The words around an amount still read.
    let bill = parse("৫০০ টাকার বিল দেওয়া কাল")
    #expect(bill.plannedDayOffset == 1)
    #expect(bill.title == "৫০০ টাকার বিল দেওয়া")
  }

  @Test("An hour with the classifier and no ending, part of the day, or fraction counts things")
  func classifierCounts() {
    expectLinesUnread(
      [
        "মিটিং ৫টা", "মিটিং ৩টে", "মিটিং ২টো", "৩টা বাজে", "৫টা বই কিনতে হবে", "একটা কাজ করা", "দুটো ডিম আনা",
        "৩টা ছবি আঁকা", "দুইটা কলা কেনা", "তিনটা কলা কেনা",
      ], languages: ["bn"])
    // An ending, a part of the day, or a fraction makes the hour a time.
    #expect(parse("৫টায় বই কেনা").startMinutes == 17 * 60)
    #expect(parse("সকাল ৫টা বই কেনা").startMinutes == 5 * 60)
    #expect(parse("সাড়ে ৫টা বই কেনা").startMinutes == 17 * 60 + 30)
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("৩০ মিনিট", 30), ("৪৫ মিনিট", 45), ("৯০ মিনিট", 90), ("২ মিনিট", 2), ("৩০মিনিট", 30), ("30 মিনিট", 30),
      ("২ ঘণ্টা", 120), ("২ ঘন্টা", 120), ("১ ঘণ্টা", 60), ("১.৫ ঘণ্টা", 90), ("১ ঘণ্টা ৩০ মিনিট", 90),
      ("১ ঘণ্টা ও ৩০ মিনিট", 90), ("১ ঘণ্টা এবং ৩০ মিনিট", 90), ("আধ ঘণ্টা", 30), ("আধা ঘণ্টা", 30),
      ("দেড় ঘণ্টা", 90), ("আড়াই ঘণ্টা", 150), ("সোয়া ঘণ্টা", 75), ("সওয়া ঘণ্টা", 75),
      ("পৌনে এক ঘণ্টা", 45), ("পৌনে ঘণ্টা", 45), ("সাড়ে তিন ঘণ্টা", 210), ("সাড়ে ৩ ঘণ্টা", 210),
      ("সোয়া ২ ঘণ্টা", 135), ("পৌনে ২ ঘণ্টা", 105), ("দুই ঘণ্টা", 120), ("দু ঘণ্টা", 120), ("এক ঘণ্টা", 60),
      ("বিশ মিনিট", 20), ("পনেরো মিনিট", 15), ("ত্রিশ মিনিট", 30), ("পঁয়তাল্লিশ মিনিট", 45),
      ("দশ মিনিট", 10), ("ঘণ্টাখানেক", 60), ("ঘন্টাখানেক", 60), ("প্রায় ২ ঘণ্টা", 120),
      ("আনুমানিক ৩০ মিনিট", 30), ("মোটামুটি ২০ মিনিট", 20), ("২ ঘণ্টার জন্য", 120),
      ("৩০ মিনিটের জন্য", 30), ("২ ঘণ্টা ধরে", 120),
    ]
    for line in lengths {
      let text = "রিপোর্ট লেখা \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "রিপোর্ট লেখা", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The genitive that goes with a length is read with it.
    let meeting = parse("৩০ মিনিটের মিটিং")
    #expect(meeting.estimatedMinutes == 30)
    #expect(meeting.title == "মিটিং")
    #expect(meeting.phrases.map(\.text) == ["৩০ মিনিটের"])
    let work = parse("২ ঘণ্টার কাজ")
    #expect(work.estimatedMinutes == 120)
    #expect(work.title == "কাজ")
    let hour = parse("১ ঘণ্টার কাজ")
    #expect(hour.estimatedMinutes == 60)
    #expect(hour.title == "কাজ")
    // A time and a length together.
    let both = parse("মিটিং ৫টায় ৪৫ মিনিটের জন্য")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "মিটিং")
  }

  @Test("An amount before পর, আগে, or মধ্যে, after প্রতি, or with an ending of another word, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "রিপোর্ট লেখা ২ ঘণ্টা পর", "রিপোর্ট লেখা ১৫ মিনিট পরে", "রিপোর্ট লেখা ৩০ মিনিট আগে",
        "রিপোর্ট লেখা ২ ঘণ্টার মধ্যে", "রিপোর্ট লেখা প্রতি ২ ঘণ্টা", "রিপোর্ট লেখা প্রতি ৩০ মিনিট",
        "রিপোর্ট লেখা ২ ঘণ্টা অন্তর", "রিপোর্ট লেখা ২ ঘণ্টা বাদে", "রিপোর্ট লেখা অন্তত ২ ঘণ্টা",
        "রিপোর্ট লেখা কমপক্ষে ২ ঘণ্টা", "রিপোর্ট লেখা বড়জোর ২ ঘণ্টা", "রিপোর্ট লেখা দিনে ২ ঘণ্টা",
        // An ending of another word on the unit.
        "রিপোর্ট লেখা ২ ঘণ্টায়", "রিপোর্ট লেখা ৩০ মিনিটে",
        // A range of amounts, an hour as a noun, and an amount no task takes.
        "রিপোর্ট লেখা ২ থেকে ৩ ঘণ্টা", "রিপোর্ট লেখা ২-৩ ঘণ্টা", "রিপোর্ট লেখা ৫ মিনিট থেকে ১০ মিনিট",
        "রিপোর্ট লেখা ঘণ্টা", "রিপোর্ট লেখা ২৫ ঘণ্টা", "রিপোর্ট লেখা ০ মিনিট",
      ], languages: ["bn"])
    // The phrase around an amount that is no length still reads.
    let day = parse("রিপোর্ট লেখা ২ ঘণ্টা পর কাল")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "রিপোর্ট লেখা ২ ঘণ্টা পর")
    let time = parse("মিটিং কাল ৩টায় ২ ঘণ্টা আগে")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "মিটিং ২ ঘণ্টা আগে")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("প্রতিদিন", daily), ("রোজ", daily), ("প্রত্যহ", daily), ("প্রতি দিন", daily), ("প্রত্যেক দিন", daily),
      ("দিনে একবার", daily), ("দৈনিক", daily), ("প্রতি সপ্তাহে", weekly), ("প্রতি হপ্তায়", weekly),
      ("প্রতি সপ্তাহ", weekly), ("সপ্তাহে একবার", weekly), ("সপ্তাহে এক বার", weekly), ("সাপ্তাহিক", weekly),
      ("প্রতি মাসে", monthly), ("প্রতি মাস", monthly), ("মাসে একবার", monthly), ("মাসিক", monthly),
      ("প্রতি বছর", yearly), ("প্রতি বছরে", yearly), ("প্রতিবছর", yearly), ("প্রতি বৎসর", yearly),
      ("বছরে একবার", yearly), ("বার্ষিক", yearly), ("প্রতি ২ দিন অন্তর", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("প্রতি ২ দিনে", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("প্রতি দুই দিনে", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("প্রতি দ্বিতীয় দিনে", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("প্রতি অন্য দিন", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("একদিন অন্তর", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("এক দিন অন্তর", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("২ দিন অন্তর", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("৩ দিন অন্তর", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("৩ দিন পর পর", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("৩ দিন পরপর", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("প্রতি ১৫ দিনে", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("প্রতি পনেরো দিনে", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("প্রতি ২ সপ্তাহে", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("প্রতি দুই সপ্তাহে", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("প্রতি ২ সপ্তাহ অন্তর", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("প্রতি দ্বিতীয় সপ্তাহে", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("এক সপ্তাহ অন্তর", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("প্রতি ৩ মাসে", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("প্রতি তিন মাসে", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("৩ মাস পর পর", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("প্রতি ৫ বছরে", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("এক বছর অন্তর", TaskRecurrenceRule(freq: .yearly, interval: 2)),
    ]
    for line in cadences {
      let text = "ওষুধ খান \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "ওষুধ খান", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
    // The adjectives that say how a task repeats are read before a colon or with a word of their own.
    #expect(parse("মাসিক: বিল দেওয়া").recurrence == monthly)
    #expect(parse("মাসিক: বিল দেওয়া").title == "বিল দেওয়া")
    #expect(parse("রিপোর্ট সাপ্তাহিক ভিত্তিতে").recurrence == weekly)
    #expect(parse("রিপোর্ট বার্ষিক হিসেবে").recurrence == yearly)
    #expect(parse("রিপোর্ট দৈনিকভাবে").recurrence == daily)
    #expect(parse("রিপোর্ট দৈনিক।").title == "রিপোর্ট।")
  }

  @Test("Weekday repeats: প্রতি সোমবার, lists of days, the weekend, and the working days")
  func weekdayRepeats() {
    let coming = parse("জিম প্রতি সোমবার")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "জিম")
    #expect(coming.plannedDayOffset == nil)
    #expect(parse("জিম প্রতি সোমবারে").recurrence == monday)
    #expect(parse("জিম প্রত্যেক সোমবার").recurrence == monday)
    #expect(parse("জিম প্রতি সপ্তাহে সোমবার").recurrence == monday)

    let lists: [(text: String, days: [String])] = [
      ("জিম প্রতি সোমবার ও বৃহস্পতিবার", ["MO", "TH"]), ("জিম প্রতি সোমবার, বুধবার ও শুক্রবার", ["MO", "WE", "FR"]),
      ("জিম প্রতি সোমবার, বুধবার এবং শুক্রবার", ["MO", "WE", "FR"]), ("জিম প্রতি বুধবার", ["WE"]),
      ("জিম প্রতি শনিবার", ["SA"]), ("জিম প্রতি রবিবার", ["SU"]), ("জিম প্রতি রোববার", ["SU"]),
      ("জিম সোমবার ও বৃহস্পতিবার প্রতি সপ্তাহে", ["MO", "TH"]), ("জিম প্রতি শনিবার ও রবিবার", ["SU", "SA"]),
      ("জিম প্রতি উইকেন্ডে", ["SU", "SA"]), ("জিম প্রতি সপ্তাহান্তে", ["SU", "SA"]),
      ("জিম প্রতি শনি-রবিবার", ["SU", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "জিম", "\(line.text): title")
    }
    #expect(parse("জিম প্রতি সোমবার ও বৃহস্পতিবার").recurrenceStartOffset == 2)
    #expect(parse("জিম প্রতি উইকেন্ডে").recurrenceStartOffset == 4)
    let everyOther = parse("জিম প্রতি দ্বিতীয় সোমবারে")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))

    // The working days, written out or as a span of weekdays beside প্রতি or a
    // word for every day.
    for text in [
      "জিম কর্মদিবসে", "জিম প্রতি কর্মদিবসে", "জিম প্রতি কর্মদিবস", "জিম রোজ কর্মদিবস", "জিম প্রতি কাজের দিন",
      "জিম কর্মদিবসগুলোতে", "জিম কাজের দিনে", "জিম রোজ কাজের দিনে",
      "জিম কাজের দিনগুলোতে", "জিম প্রতি সোমবার থেকে শুক্রবার", "জিম রোজ সোমবার থেকে শুক্রবার",
      "জিম সোমবার থেকে শুক্রবার প্রতিদিন", "জিম সোমবার থেকে শুক্রবার পর্যন্ত প্রতিদিন",
      "জিম প্রতি সোমবার থেকে শুক্রবার পর্যন্ত", "জিম প্রতি সোমবার থেকে শুক্রবার সকাল ৯টায়",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
    #expect(
      parse("জিম প্রতি সোমবার থেকে বুধবার").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE"]))
    #expect(
      parse("জিম প্রতি রবিবার থেকে বৃহস্পতিবার").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"]))
    // Monday to Friday alone is no repeat.
    #expect(parse("জিম সোমবার থেকে শুক্রবার").recurrence == nil)
    // A repeat that starts today starts at 0 on its own weekday.
    #expect(parse("জিম প্রতি মঙ্গলবার").recurrenceStartOffset == 0)
    #expect(parse("জিম প্রতি শুক্রবার", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("যোগব্যায়াম রোজ সকালে ৬টায়", "যোগব্যায়াম", 6 * 60), ("রোজ সকালে ৬টায় যোগব্যায়াম", "যোগব্যায়াম", 6 * 60),
      ("প্রতি সন্ধ্যায় ৭টায় হাঁটা", "হাঁটা", 19 * 60), ("হাঁটা প্রতি সন্ধ্যায় ৭টায়", "হাঁটা", 19 * 60),
      ("প্রতি রাতে ১০:৩০টায় ওষুধ", "ওষুধ", 22 * 60 + 30), ("প্রতি রাতে ১১টায় ঘুম", "ঘুম", 23 * 60),
      ("প্রত্যেক সকালে ৫টায় যোগব্যায়াম", "যোগব্যায়াম", 5 * 60), ("প্রতিদিন সকালে ৬টায় যোগব্যায়াম", "যোগব্যায়াম", 6 * 60),
      ("রোজ সন্ধ্যায় ৭টায় হাঁটা", "হাঁটা", 19 * 60), ("প্রতি রাতে বই পড়া", "বই পড়া", nil),
      ("রোজ সকালে যোগব্যায়াম", "যোগব্যায়াম", nil),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let range = parse("রোজ সকালে ৯ থেকে ১১টায় পড়াশোনা")
    #expect(range.recurrence == daily)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "পড়াশোনা")
    // A line of details alone is no task.
    expectLinesUnread(["প্রতি সকালে ৬টায়", "প্রতি সন্ধ্যায় ৭টায়"], languages: ["bn"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "ভাড়া প্রতি মাসের ৫ তারিখে", "ভাড়া প্রতি মাসে ৫ তারিখে", "ভাড়া প্রতি মাসের ৫ তারিখ",
      "ভাড়া প্রত্যেক মাসের ৫ তারিখে", "ভাড়া ৫ তারিখে প্রতি মাসে", "ভাড়া প্রতি মাসের 5 তারিখে",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text): start")
      #expect(parsed.title == "ভাড়া", "\(text): title")
    }
    for text in ["ভাড়া প্রতি মাসের ১লা তারিখে", "ভাড়া প্রতি মাসের প্রথম তারিখে"] {
      let first = parse(text)
      #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]), "\(text)")
      #expect(first.recurrenceStartOffset == 9, "\(text): start")
    }
    // A date with its month name is a date, not a repeat.
    #expect(parse("ভাড়া প্রতি ৫ মে").recurrence == nil)
  }

  @Test("A repeat shorter than a day, and a cadence word that describes a noun, are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        "ওষুধ খান প্রতি ২ ঘণ্টায়", "প্রতিদিনের কাজ", "রোজকার কাজ", "রোজা রাখা", "রোজগার মেলা", "প্রতি মাসের খরচ",
        "প্রতি সপ্তাহের মিটিং", "প্রতিবেদন লেখা", "প্রতিযোগিতা দেখা", "প্রতিবার ফোন করা", "দৈনিক রিপোর্ট",
        "মাসিক বেতন", "সাপ্তাহিক ছুটি", "বার্ষিক পরীক্ষা", "দৈনিক পত্রিকা পড়া",
        // The nouns for the working days name them, and a genitive makes an attribute.
        "জিম কর্মদিবস", "জিম কাজের দিন", "কর্মদিবসের ছুটি", "প্রতি কর্মদিবসের ছুটি",
      ], languages: ["bn"])
    // The weekday after প্রতি with a genitive is an attribute too.
    #expect(parse("প্রতি সোমবারের মিটিং").recurrence == nil)
  }

  // MARK: - Priorities

  @Test("Priorities: উচ্চ, মধ্যম, and নিম্ন প্রাধান্য, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("উচ্চ প্রাধান্য", .p1), ("সর্বোচ্চ প্রাধান্য", .p1), ("বেশি প্রাধান্য", .p1), ("সবচেয়ে বেশি প্রাধান্য", .p1),
      ("প্রাধান্য: উচ্চ", .p1), ("প্রাধান্য উচ্চ", .p1), ("মধ্যম প্রাধান্য", .p2), ("মাঝারি প্রাধান্য", .p2),
      ("মাঝারী প্রাধান্য", .p2), ("সাধারণ প্রাধান্য", .p2), ("স্বাভাবিক প্রাধান্য", .p2), ("প্রাধান্য: মধ্যম", .p2),
      ("নিম্ন প্রাধান্য", .p3), ("সর্বনিম্ন প্রাধান্য", .p3), ("কম প্রাধান্য", .p3), ("সবচেয়ে কম প্রাধান্য", .p3),
      ("প্রাধান্য: নিম্ন", .p3), ("প্রাধান্য কম", .p3), ("উচ্চ অগ্রাধিকার", .p1), ("মধ্যম অগ্রাধিকার", .p2),
      ("নিম্ন অগ্রাধিকার", .p3), ("অগ্রাধিকার: উচ্চ", .p1), ("অগ্রাধিকার: নিম্ন", .p3),
    ]
    for level in levels {
      let text = "রিপোর্ট পাঠান \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "রিপোর্ট পাঠান", "\(text): title")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let inside = parse("রিপোর্ট উচ্চ প্রাধান্য পাঠান")
    #expect(inside.priority == .p1)
    #expect(inside.title == "রিপোর্ট পাঠান")

    for word in [
      "জরুরি", "জরুরী", "অতি জরুরি", "খুব জরুরি", "অত্যন্ত জরুরি", "জরুরি ভিত্তিতে", "আর্জেন্ট", "গুরুত্বপূর্ণ",
      "অতি গুরুত্বপূর্ণ",
    ] {
      let text = "রিপোর্ট পাঠান \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "রিপোর্ট পাঠান", "\(text): title")
    }
    for word in ["জরুরি", "আর্জেন্ট", "গুরুত্বপূর্ণ"] {
      for separator in [":", ","] {
        let text = "\(word)\(separator) রিপোর্ট পাঠান"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "রিপোর্ট পাঠান", "\(text): title")
      }
    }
    #expect(parse("রিপোর্ট পাঠান জরুরি।").title == "রিপোর্ট পাঠান।")
    // An urgent word in the middle, or opening the line with no colon or
    // comma, is a word of the title, and so is a level that describes a noun.
    expectLinesUnread(
      [
        "জরুরি বিভাগে যান", "রিপোর্ট জরুরি আছে", "জরুরি রিপোর্ট পাঠান", "জরুরি কাজ", "জরুরি অবস্থা",
        "গুরুত্বপূর্ণ মিটিং আছে", "রিপোর্ট পাঠান গুরুত্বপূর্ণ আছে", "উচ্চ প্রাধান্য সম্পন্ন কাজ",
        "কম প্রাধান্য যুক্ত তালিকা",
      ], languages: ["bn"])
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("কাল বিকেল ৫টায় ৩০ মিনিটের মিটিং #কাজ")
    #expect(line.title == "মিটিং")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["কাজ"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["কাল", "বিকেল ৫টায়", "৩০ মিনিটের", "#কাজ"])

    let lines: [(text: String, title: String)] = [
      ("প্রতি সোমবার সকাল ৯টায় জিম", "জিম"), ("শুক্রবার পর্যন্ত রিপোর্ট পাঠান জরুরি", "রিপোর্ট পাঠান"),
      ("সোমবার সকাল ৯টা থেকে ১১টা মিটিং", "মিটিং"), ("৫ মে সন্ধ্যা ৬টায় পার্টি", "পার্টি"),
      ("পরের শুক্রবার পর্যন্ত ২ ঘণ্টার কাজ", "কাজ"), ("কাল মিটিং ৩টায় উচ্চ প্রাধান্য", "মিটিং"),
      ("রোজ সকাল ৭টায় ওষুধ", "ওষুধ"), ("আজ রাত ১১টায় ঘুম", "ঘুম"),
      ("মাকে ফোন করুন কাল বিকেল ৫টায়", "মাকে ফোন করুন"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(parse(line.text).phrases.count >= 2, "\(line.text): phrases")
    }
    let friday = parse("শুক্রবার পর্যন্ত রিপোর্ট পাঠান জরুরি")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.priority == .p1)
    let weekly = parse("প্রতি সোমবার সকাল ৯টায় জিম")
    #expect(weekly.recurrence == monday)
    #expect(weekly.startMinutes == 9 * 60)
    let report = parse("পরের শুক্রবার পর্যন্ত ২ ঘণ্টার কাজ")
    #expect(report.dueDayOffset == 10)
    #expect(report.estimatedMinutes == 120)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // The short weekday stems are ordinary words and names.
        "রবিকে ফোন করুন", "শনি মন্দিরে যাওয়া", "মঙ্গল গ্রহ দেখা", "সোমকে ফোন করুন", "বুধ গ্রহ", "শুক্র গ্রহ",
        "বৃহস্পতি গ্রহ দেখা", "রবীন্দ্রনাথ ঠাকুরের কবিতা পড়া",
        // Words that contain a day word.
        "আজকাল মিটিং", "আজ-কাল মিটিং", "কালো রঙ কেনা", "আজাদ ভাইকে ফোন করুন", "আজান শোনা",
        "আজহার ভাইয়ের সাথে কথা", "কালবৈশাখী নিয়ে লেখা", "পরশুরাম পড়া", "কালীপুজো দেখা", "কালি কেনা",
        "রোজা রাখা", "পরিবারের সাথে খাওয়া",
        // A day with a genitive after it is an attribute of a noun.
        "সোমবারের মিটিং", "শুক্রবারের খাবার", "কালকের মিটিং", "আজকের রিপোর্ট",
        // A bound or an amount of days that names no day.
        "রিপোর্ট ৩ দিনের মধ্যে পাঠান", "৩ দিন আগের ঘটনা", "মিটিংয়ের ৩ দিন পর",
        // A bare number that is a count.
        "৩টা আম কেনা", "৫ জন বন্ধুকে ডাকা",
      ], languages: ["bn"])
    // Bengali written in Latin letters is not read.
    expectLinesUnread(
      [
        "kal sokale 9tay meeting", "aj bikele phone kora", "porshu dekha", "protidin gym", "2 ghonta poRa",
        "sukrobar porjonto report",
      ], languages: ["bn"])
    // "হল" is a hall: it is no past-tense word.
    let hall = parse("আজ হল ভাড়া করা")
    #expect(hall.plannedDayOffset == 0)
    #expect(hall.title == "হল ভাড়া করা")
    // A weekday before other words is the day.
    let friday = parse("শুক্রবার পার্টির প্রস্তুতি")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "পার্টির প্রস্তুতি")
  }

  // MARK: - কাল, পরশু, and the past

  @Test("কাল and পরশু are read as the coming day, and a line in the past tense or after a past word stays unread")
  func tomorrowOrYesterday() {
    let tomorrow = [
      "কাল মিটিং আছে", "কাল যেতে হবে", "কাল মিটিং হবে", "রিপোর্ট কাল পাঠান", "কাল এই কাজটি করা হবে",
      "কাল থেকে জিম শুরু",
    ]
    for text in tomorrow {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        // The words that say a day is past, or the month's first, second, or last.
        "গতকাল মিটিং", "গত শুক্রবার মিটিং", "গেল শুক্রবার মিটিং", "আগের শুক্রবার মিটিং", "বিগত সোমবার মিটিং",
        "প্রথম শুক্রবার মিটিং", "দ্বিতীয় শনিবার ছুটি", "শেষ শুক্রবার পার্টি", "পরবর্তী শুক্রবার মিটিং",
        // A past-tense form anywhere in the line.
        "কাল মিটিং ছিল", "পরশু মিটিং ছিল", "আমি পরশু গিয়েছিলাম", "কাল গিয়েছিল", "কাল ফোন করেছি",
        "শুক্রবার সে এসেছিল", "আজ বৈঠক হয়েছিল", "আজ মিটিং ছিল", "শুক্রবার মিটিং ছিল",
        // "হলো" is the past of "to happen", so a deadline label that carries it is no deadline.
        "কাল মিটিং হলো", "রিপোর্ট পাঠান শেষ তারিখ হলো শুক্রবার",
      ], languages: ["bn"])
    // "গত শুক্রবার" is a past day, but "শুক্রবারের আগে" is a deadline.
    #expect(parse("রিপোর্ট শুক্রবারের আগে").dueDayOffset == 3)
    #expect(parse("রিপোর্ট কালকের আগে").dueDayOffset == 1)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // A past statement with no past-tense marker reads as the day after tomorrow:
    // "পরশু" names the day before yesterday as well.
    #expect(parse("পরশু আমি ফোন দিলাম").plannedDayOffset == 2)
    #expect(parse("কাল আমি ফোন দিলাম").plannedDayOffset == 1)
    // An hour from 1 to 6 with no part of the day is the afternoon.
    #expect(parse("মিটিং ৫টায়").startMinutes == 17 * 60)
    // An hour count written with a Latin unit is English's length, even after প্রতি.
    let hours = parse("ওষুধ খান প্রতি 2h")
    #expect(hours.estimatedMinutes == 120)
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("এই কাজ জরুরি").priority == .p1)
    #expect(parse("এই কাজ গুরুত্বপূর্ণ").priority == .p1)
    // "প্রতি" also means a rate: a price per day reads as a repeat.
    #expect(parse("মজুরি প্রতি দিন ৫০০ টাকা").recurrence == daily)
    // "রোজ" is the transliteration of "rose" too, as in "রোজ গোল্ড", and a name.
    let rose = parse("রোজ গোল্ড ঘড়ি কিনুন")
    #expect(rose.recurrence == daily)
    #expect(rose.title == "গোল্ড ঘড়ি কিনুন")
    // A word that stands apart from a day stays in the title.
    let again = parse("আজ আবার রিপোর্ট পাঠান")
    #expect(again.plannedDayOffset == 0)
    #expect(again.title == "আবার রিপোর্ট পাঠান")
  }

  // MARK: - Scripts and spellings

  @Test("The precomposed and the decomposed nukta read as one letter, and a missing nukta reads too")
  func nuktaForms() {
    // য় ড় as one code point (U+09DF, U+09DC), as a consonant and a nukta
    // (U+09BC), and as the consonant alone.
    let forms: [(ya: String, da: String)] = [
      ("\u{09DF}", "\u{09DC}"), ("\u{09AF}\u{09BC}", "\u{09A1}\u{09BC}"), ("\u{09AF}", "\u{09A1}"),
    ]
    for form in forms {
      let scalars = form.ya.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      let others = form.da.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      // জানুয়ারি, ফেব্রুয়ারি
      #expect(
        parse("ফোন করুন ৫ জানু\(form.ya)ারি").plannedDayOffset == captureDayOffset("2027-01-05"), "জানুয়ারি: \(scalars)")
      #expect(
        parse("ফোন করুন ৫ ফেব্রু\(form.ya)ারি").plannedDayOffset == captureDayOffset("2027-02-05"),
        "ফেব্রুয়ারি: \(scalars)")
      // টায়, সন্ধ্যায়, হপ্তায়
      #expect(parse("মিটিং ৫টা\(form.ya)").startMinutes == 17 * 60, "টায়: \(scalars)")
      #expect(parse("মাকে ফোন করুন কাল সন্ধ্যা\(form.ya)").plannedDayOffset == 1, "সন্ধ্যায়: \(scalars)")
      #expect(
        parse("ক্লাস প্রতি হপ্তা\(form.ya)").recurrence == TaskRecurrenceRule(freq: .weekly), "হপ্তায়: \(scalars)")
      // সাড়ে, দেড়, আড়াই
      #expect(parse("মিটিং সা\(form.da)ে ৫টায়").startMinutes == 17 * 60 + 30, "সাড়ে: \(others)")
      #expect(parse("মিটিং দে\(form.da)টায়").startMinutes == 13 * 60 + 30, "দেড়টায়: \(others)")
      #expect(parse("মিটিং আ\(form.da)াইটায়").startMinutes == 14 * 60 + 30, "আড়াইটায়: \(others)")
      #expect(parse("রিপোর্ট লেখা দে\(form.da) ঘণ্টা").estimatedMinutes == 90, "দেড় ঘণ্টা: \(others)")
      #expect(parse("রিপোর্ট লেখা আ\(form.da)াই ঘণ্টা").estimatedMinutes == 150, "আড়াই ঘণ্টা: \(others)")
      #expect(parse("রিপোর্ট লেখা সা\(form.da)ে তিন ঘণ্টা").estimatedMinutes == 210, "সাড়ে তিন ঘণ্টা: \(others)")
    }
  }

  @Test("The vowel signs ো and ৌ read as one sign or as the two signs they are made of")
  func vowelSigns() {
    // ো (U+09CB) is ে (U+09C7) and া (U+09BE); ৌ (U+09CC) is ে and ৗ (U+09D7).
    for o in ["\u{09CB}", "\u{09C7}\u{09BE}"] {
      let scalars = o.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      #expect(parse("ফোন করুন স\(o)মবার").plannedDayOffset == 6, "সোমবার: \(scalars)")
      #expect(parse("মিটিং স\(o)য়া ৫টায়").startMinutes == 17 * 60 + 15, "সোয়া: \(scalars)")
      #expect(parse("মিটিং ভ\(o)র ৪টায়").startMinutes == 4 * 60, "ভোর: \(scalars)")
      #expect(parse("ওষুধ খান র\(o)জ").recurrence == daily, "রোজ: \(scalars)")
      #expect(
        parse("ফোন করুন ৫ অক্ট\(o)বর").plannedDayOffset == captureDayOffset("2026-10-05"), "অক্টোবর: \(scalars)")
      #expect(parse("ফোন করুন র\(o)ববার").plannedDayOffset == 5, "রোববার: \(scalars)")
    }
    for au in ["\u{09CC}", "\u{09C7}\u{09D7}"] {
      let scalars = au.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      #expect(parse("মিটিং প\(au)নে ৬টায়").startMinutes == 17 * 60 + 45, "পৌনে: \(scalars)")
      #expect(parse("রিপোর্ট লেখা প\(au)নে এক ঘণ্টা").estimatedMinutes == 45, "পৌনে এক ঘণ্টা: \(scalars)")
    }
  }

  @Test("The candrabindu, a missing one, and the spelling of a vowel sign read as one word")
  func candrabindu() {
    // পাঁচ and পাচ, পঁচিশ and পচিশ, পঁয়তাল্লিশ and পয়তাল্লিশ.
    #expect(parse("মিটিং পা\u{0981}চটায়").startMinutes == 17 * 60)
    #expect(parse("মিটিং পাচটায়").startMinutes == 17 * 60)
    #expect(parse("রিপোর্ট লেখা প\u{0981}চিশ মিনিট").estimatedMinutes == 25)
    #expect(parse("রিপোর্ট লেখা পচিশ মিনিট").estimatedMinutes == 25)
    #expect(parse("রিপোর্ট লেখা পয়তাল্লিশ মিনিট").estimatedMinutes == 45)
    #expect(parse("রিপোর্ট লেখা পঁয়তাল্লিশ মিনিট").estimatedMinutes == 45)
  }

  @Test("Spelling variants of the same word read alike")
  func spellingVariants() {
    // আগামীকাল and আগামিকাল, জরুরি and জরুরী, জানুয়ারি and জানুয়ারী, ঘণ্টা and ঘন্টা,
    // রবিবার and রোববার, বিকেল and বিকাল, সন্ধ্যা and সন্ধ্যে, পনেরো and পনের, এগারো and এগার, আধ and আধা.
    #expect(parse("ফোন করুন আগামীকাল").plannedDayOffset == parse("ফোন করুন আগামিকাল").plannedDayOffset)
    #expect(parse("রিপোর্ট পাঠান জরুরি").priority == parse("রিপোর্ট পাঠান জরুরী").priority)
    #expect(parse("ফোন করুন ৫ জানুয়ারি").plannedDayOffset == parse("ফোন করুন ৫ জানুয়ারী").plannedDayOffset)
    #expect(parse("রিপোর্ট লেখা ২ ঘণ্টা").estimatedMinutes == parse("রিপোর্ট লেখা ২ ঘন্টা").estimatedMinutes)
    #expect(parse("ফোন করুন রবিবার").plannedDayOffset == parse("ফোন করুন রোববার").plannedDayOffset)
    #expect(parse("মিটিং বিকেল ৫টায়").startMinutes == parse("মিটিং বিকাল ৫টায়").startMinutes)
    #expect(parse("মিটিং সন্ধ্যা ৭টায়").startMinutes == parse("মিটিং সন্ধ্যে ৭টায়").startMinutes)
    #expect(parse("রিপোর্ট লেখা পনেরো মিনিট").estimatedMinutes == parse("রিপোর্ট লেখা পনের মিনিট").estimatedMinutes)
    #expect(parse("মিটিং এগারোটায়").startMinutes == parse("মিটিং এগারটায়").startMinutes)
    #expect(parse("রিপোর্ট লেখা আধ ঘণ্টা").estimatedMinutes == parse("রিপোর্ট লেখা আধা ঘণ্টা").estimatedMinutes)
    #expect(parse("ফোন করুন ৫ আগস্ট").plannedDayOffset == parse("ফোন করুন ৫ আগষ্ট").plannedDayOffset)
  }

  @Test("A zero-width joiner or non-joiner before an ending or inside a conjunct changes nothing")
  func joiners() {
    #expect(parse("ফোন করুন সোমবার\u{200C}ে").plannedDayOffset == 6)
    #expect(parse("ফোন করুন কাল\u{200C}কে").plannedDayOffset == 1)
    #expect(parse("ফোন করুন আজ\u{200D}ই").plannedDayOffset == 0)
    #expect(parse("ফোন করুন পরশু\u{200C}দিন").plannedDayOffset == 2)
    #expect(parse("ফোন করুন ৫ অক্টোবর\u{200C}ে").plannedDayOffset == captureDayOffset("2026-10-05"))
    #expect(parse("মিটিং সন্\u{200D}ধ্যা ৬টায়").startMinutes == 18 * 60)
    #expect(parse("মিটিং সন্\u{200C}ধ্যা ৬টায়").startMinutes == 18 * 60)
    #expect(parse("মিটিং সন্ধ্\u{200C}যা ৬টায়").startMinutes == 18 * 60)
    #expect(parse("রিপোর্ট লেখা ২ ঘণ্\u{200C}টা").estimatedMinutes == 120)
    #expect(parse("রিপোর্ট পাঠান জরুরি").priority == .p1)
    // The title keeps the joiner as typed.
    let typed = "র\u{200D}্যাব অফিসে আড্ডা"
    #expect(Array(parse("\(typed) কাল").title.unicodeScalars) == Array(typed.unicodeScalars))
  }

  @Test("The composed and the decomposed forms of a line read the same")
  func normalizationForms() {
    let lines = [
      "কাল সকালে মিটিং ৬টায়", "রিপোর্ট পাঠান শুক্রবার পর্যন্ত", "ফোন করুন ৫ ফেব্রুয়ারি", "ওষুধ খান প্রতি ২ সপ্তাহে",
      "মিটিং সাড়ে ৩টায়", "মিটিং দেড়টায়", "রিপোর্ট পাঠান জরুরি", "ফোন করুন ৫ জানুয়ারি", "মিটিং সোয়া ৪টায়",
      "রিপোর্ট লেখা আড়াই ঘণ্টা", "রিপোর্ট পাঠান সর্বোচ্চ প্রাধান্য", "জিম প্রতি সোমবার", "মিটিং পৌনে ৬টায়",
      "ফোন করুন ৫ অক্টোবর", "রিপোর্ট পাঠান শেষ তারিখ: ৫ মে", "ছুটি ৩ থেকে ৫ মার্চ", "রোজ সকালে ৬টায় যোগব্যায়াম",
      "ফোন করুন ৫ ফেব্রু\u{09DF}ারি", "মিটিং সা\u{09DC}ে ৩টায়", "ছুটি ৩ থেকে ৫ জানু\u{09DF}ারি",
    ]
    for line in lines {
      let expected = parse(line)
      for variant in [line.precomposedStringWithCanonicalMapping, line.decomposedStringWithCanonicalMapping] {
        let parsed = parse(variant)
        #expect(parsed.plannedDayOffset == expected.plannedDayOffset, "\(line): planned day")
        #expect(parsed.dueDayOffset == expected.dueDayOffset, "\(line): due day")
        #expect(parsed.startMinutes == expected.startMinutes, "\(line): start")
        #expect(parsed.estimatedMinutes == expected.estimatedMinutes, "\(line): length")
        #expect(parsed.recurrence == expected.recurrence, "\(line): repeat")
        #expect(parsed.priority == expected.priority, "\(line): priority")
        #expect(parsed.phrases.map(\.kind) == expected.phrases.map(\.kind), "\(line): phrases")
      }
    }
  }

  @Test("Bengali digits and Western digits read the same")
  func digitScripts() {
    let lines = [
      "মিটিং 3:30টায়", "মিটিং সন্ধ্যা 5:30", "মিটিং 5.30টায়", "মিটিং সাড়ে 5টায়", "মিটিং 2 থেকে 4টায়",
      "মিটিং 14:00 থেকে 16:00", "রিপোর্ট লেখা 20 মিনিট", "রিপোর্ট লেখা 1.5 ঘণ্টা", "রিপোর্ট লেখা 1 ঘণ্টা 30 মিনিট",
      "ওষুধ খান প্রতি 3 দিনে", "ভাড়া প্রতি মাসের 5 তারিখে", "সভা 5 মার্চ 2027", "ফোন করুন 3 দিন পর",
      "ছুটি 3 থেকে 5 মার্চ", "ছুটি 3-5 মার্চ", "রিপোর্ট পাঠান 5 মার্চ পর্যন্ত", "ফোন করুন 2 মাস পর",
      "ওষুধ খান প্রতি 2 সপ্তাহে", "ফোন করুন 15/10/2026", "মিটিং 17:30-এ", "মিটিং সকাল 10টা 30 মিনিটে",
      "ওষুধ খান 3 দিন অন্তর", "ফোন করুন 15ই অক্টোবর", "মিটিং বিকেল 5টায়",
    ]
    for line in lines {
      let latin = parse(line)
      #expect(latin.phrases.count == 1, "\(line): phrases")
      let converted = bengaliDigits(line)
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
    // The title keeps the digits as typed.
    let typed = parse("৩ জনের সাথে মিটিং কাল")
    #expect(typed.plannedDayOffset == 1)
    #expect(typed.title == "৩ জনের সাথে মিটিং")
  }

  @Test("The title keeps the letters and signs as they were typed")
  func titleKeepsTypedText() {
    // A precomposed nukta letter in the title stays one code point, and a
    // decomposed one stays two.
    let typed = "ব\u{09DC} ম\u{09DF}দা কিনতে ঝ\u{09A1}\u{09BC} দেখা"
    let parsed = parse("\(typed) কাল")
    #expect(parsed.plannedDayOffset == 1)
    #expect(parsed.priority == nil)
    #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    let candrabindu = parse("চাঁদ দেখা কাল")
    #expect(Array(candrabindu.title.unicodeScalars) == Array("চাঁদ দেখা".unicodeScalars))
  }

  @Test("The danda and the comma left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("মাকে ফোন করুন, কাল, বিকেল ৫টায়", "মাকে ফোন করুন"), ("মাকে ফোন করুন কাল।", "মাকে ফোন করুন।"),
      ("কাল, মাকে ফোন করুন", "মাকে ফোন করুন"), ("কাল: মাকে ফোন করুন", "মাকে ফোন করুন"),
      ("মাকে ফোন করুন - কাল", "মাকে ফোন করুন"),
      ("রিপোর্ট পাঠান, শুক্রবার পর্যন্ত, উচ্চ প্রাধান্য", "রিপোর্ট পাঠান"),
      ("দুধ, রুটি ও ডিম কাল কেনা", "দুধ, রুটি ও ডিম কেনা"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The danda is punctuation: it ends a word.
    #expect(parse("মাকে ফোন করুন কাল।").plannedDayOffset == 1)
    #expect(parse("রিপোর্ট পাঠান শুক্রবার পর্যন্ত।").dueDayOffset == 3)
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    let day = parse("কাজ আগামীকাল")
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "কাজ")
    let time = parse("কাজ বিকেল 5টায়")
    #expect(time.startMinutes == 17 * 60)
    #expect(time.title == "কাজ")
    let repeating = parse("কাজ প্রতি সোমবার")
    #expect(repeating.recurrence == monday)
    #expect(repeating.title == "কাজ")
    let length = parse("কাজ 20 মিনিট")
    #expect(length.estimatedMinutes == 20)
    #expect(length.title == "কাজ")
    #expect(parse("কাজ #তালিকা").tags == ["তালিকা"])
  }

  @Test("The examples of the user guide table are read as the details they demonstrate")
  func guideExamples() {
    // Each example is typed with Latin digits, as the guide writes it, and with Bengali digits.
    func read(_ examples: [String]) -> [(example: String, parsed: LorvexCaptureParse)] {
      examples.flatMap { example in
        [example, bengaliDigits(example)].map { (example: $0, parsed: parse("কাজ \($0)")) }
      }
    }
    let days = [
      "আজ", "আজ রাতে", "আগামীকাল", "আগামীকাল সকালে", "পরশু", "সোমবার", "এই শুক্রবার", "পরের সোমবার",
      "পরের সপ্তাহে", "এই উইকেন্ডে", "3 দিন পর", "1 সপ্তাহ পর",
    ]
    for (example, parsed) in read(days) {
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let dates = [
      "5 মে", "5 মে 2027", "তারিখ 5 মে", "15 অক্টো", "15 তারিখে", "15/10/2026", "15.10.", "সোমবার 5 অক্টোবর",
    ]
    for (example, parsed) in read(dates) {
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let ranges = [
      "3 থেকে 5 মার্চ", "3 মার্চ থেকে 5 মার্চ", "3 মার্চ থেকে 5 মার্চ পর্যন্ত", "30 জানুয়ারি থেকে 2 ফেব্রুয়ারি",
      "3-5 মার্চ", "সোমবার থেকে বুধবার",
    ]
    for (example, parsed) in read(ranges) {
      #expect(parsed.plannedDayOffset != nil && parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let due = [
      "শুক্রবার পর্যন্ত", "কাল সন্ধ্যা পর্যন্ত", "5 মে পর্যন্ত", "শুক্রবারের মধ্যে", "শেষ তারিখ: 5 মে",
      "ডেডলাইন শুক্রবার",
    ]
    for (example, parsed) in read(due) {
      #expect(parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let times = [
      "5টায়", "5:30টায়", "সাড়ে 5টায়", "সোয়া 5টায়", "পৌনে 6টায়", "দেড়টায়", "পাঁচটায়", "সকাল 9টা", "বিকেল 5টায়",
      "রাত 10টায়", "সকাল 9:30", "মধ্যরাতে", "3টা থেকে 5টা", "সকাল 9টা থেকে 11টা", "14:00 থেকে 16:00",
    ]
    for (example, parsed) in read(times) {
      #expect(parsed.startMinutes != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let repeats = [
      "প্রতিদিন", "রোজ", "রোজ সকালে", "প্রতি সোমবার", "প্রতি সোমবার ও বৃহস্পতিবার", "প্রতি দ্বিতীয় সোমবারে",
      "প্রতি সপ্তাহে", "প্রতি 2 দিনে", "প্রতি মাসে", "প্রতি মাসের 5 তারিখে", "প্রতি বছর", "প্রতি উইকেন্ডে",
      "কর্মদিবসে", "প্রতি সোমবার থেকে শুক্রবার", "2 দিন অন্তর", "সপ্তাহে একবার",
    ]
    for (example, parsed) in read(repeats) {
      #expect(parsed.recurrence != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let lengths = [
      "30 মিনিট", "2 ঘণ্টা", "1.5 ঘণ্টা", "1 ঘণ্টা 30 মিনিট", "আধ ঘণ্টা", "পৌনে এক ঘণ্টা", "দেড় ঘণ্টা",
      "সাড়ে তিন ঘণ্টা", "দুই ঘণ্টা", "30 মিনিটের জন্য",
    ]
    for (example, parsed) in read(lengths) {
      #expect(parsed.estimatedMinutes != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    let priorities = ["উচ্চ প্রাধান্য", "মধ্যম প্রাধান্য", "নিম্ন প্রাধান্য", "প্রাধান্য: উচ্চ", "জরুরি"]
    for (example, parsed) in read(priorities) {
      #expect(parsed.priority != nil, "\(example)")
      #expect(parsed.title == "কাজ", "\(example): title")
    }
    #expect(parse("জরুরি: কাজ").priority == .p1)
    // The sentences of the guide.
    #expect(parse("মজুরি প্রতি দিন 500 টাকা").recurrence == daily)
    #expect(parse("Sprint 12 - 20 মার্চ").plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(parse("কাজ 12-20 মার্চ").dueDayOffset == captureDayOffset("2027-03-20"))
    #expect(parse("কাজ সকাল 10টা 30 মিনিটে").startMinutes == 10 * 60 + 30)
    expectLinesUnread(
      [
        "কাজ 5/10", "কাজ 31 এপ্রিল", "কাজ 5 বৈশাখ", "কাজ 5 থেকে 3 মার্চ", "কাজ 3 থেকে 5", "কাজ 2 থেকে 3 ঘণ্টা",
        "কাজ এই সপ্তাহে", "মঙ্গল গ্রহ দেখা", "জরুরি বিভাগে যান", "রিপোর্ট জরুরি আছে", "কাজ আজ পর্যন্ত",
      ], languages: ["bn"])
  }

  @Test("The phrases the app writes for a deadline, a priority, a repeat, and an hour can be typed back")
  func phrasesTheAppWrites() {
    // "শেষ তারিখ: %@" with a day word, a weekday, or a date as the system writes it.
    let deadlines: [(text: String, offset: Int)] = [
      ("শেষ তারিখ: আজ", 0), ("শেষ তারিখ: আগামীকাল", 1), ("শেষ তারিখ: শুক্রবার", 3),
      ("শেষ তারিখ: 15 অক্টো", captureDayOffset("2026-10-15")), ("শেষ তারিখ: 15 অক্টোঃ", captureDayOffset("2026-10-15")),
      ("শেষ তারিখ: 15 অক্টোবর", captureDayOffset("2026-10-15")),
      ("শেষ তারিখ: 15 অক্টো, 2027", captureDayOffset("2027-10-15")),
      ("শেষ তারিখ: 15 অক্টোঃ, 2027", captureDayOffset("2027-10-15")),
      ("শেষ তারিখ: বৃহস্পতিবার, 15 অক্টোবর", captureDayOffset("2026-10-15")),
    ]
    for line in deadlines {
      let text = "রিপোর্ট পাঠান \(line.text)"
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "রিপোর্ট পাঠান", "\(text): title")
    }
    // The priority phrases of the task sentence.
    let priorities: [(text: String, priority: LorvexTask.Priority)] = [
      ("উচ্চ প্রাধান্য", .p1), ("সাধারণ প্রাধান্য", .p2), ("নিম্ন প্রাধান্য", .p3),
    ]
    for line in priorities {
      let parsed = parse("রিপোর্ট পাঠান \(line.text)")
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == "রিপোর্ট পাঠান", "\(line.text): title")
    }
    // The repeat summaries and the frequency names.
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let repeats: [(text: String, rule: TaskRecurrenceRule)] = [
      ("প্রতিদিন", daily), ("প্রতি সপ্তাহে", weekly), ("প্রতি মাসে", monthly), ("প্রতি বছরে", yearly),
      ("প্রতি 2 দিনে", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("প্রতি 3 সপ্তাহে", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("প্রতি 4 মাসে", TaskRecurrenceRule(freq: .monthly, interval: 4)),
      ("প্রতি 5 বছরে", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("দৈনিক", daily), ("সাপ্তাহিক", weekly), ("মাসিক", monthly), ("বার্ষিক", yearly),
    ]
    for line in repeats {
      let parsed = parse("ওষুধ খান \(line.text)")
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "ওষুধ খান", "\(line.text): title")
    }
    // Apple's word for hour with a number before it, and the days the app writes.
    #expect(parse("পড়া 1 ঘণ্টা").estimatedMinutes == 60)
    #expect(parse("পড়া 12 ঘণ্টা").estimatedMinutes == 720)
    #expect(parse("ফোন করুন আজ").plannedDayOffset == 0)
    #expect(parse("ফোন করুন আগামীকাল").plannedDayOffset == 1)
  }

  // MARK: - Names the system writes

  /// The short weekday names the system writes in Bengali that are not read,
  /// with the reason: each is an ordinary word, a name, a letter, or a syllable.
  private static let unreadWeekdayAbbreviations: [String: String] = [
    "রবি": "a name, and the sun", "সোম": "a name, and the moon", "মঙ্গল": "the planet Mars",
    "বুধ": "the planet Mercury", "বৃহস্পতি": "the planet Jupiter", "শুক্র": "the planet Venus",
    "শনি": "the planet Saturn", "র": "a single letter", "সো": "a syllable", "ম": "a single letter",
    "বু": "a syllable", "বৃ": "a syllable", "শু": "a syllable", "শ": "a single letter",
  ]

  @Test("Every month and weekday name the system writes in Bengali is read, except the short weekday forms")
  func systemNames() {
    for identifier in ["bn_BD", "bn_IN"] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: identifier)
      formatter.calendar = Calendar(identifier: .gregorian)
      let monthNames: [[String]] = [
        formatter.monthSymbols, formatter.shortMonthSymbols, formatter.standaloneMonthSymbols,
        formatter.shortStandaloneMonthSymbols,
      ]
      for names in monthNames {
        #expect(names.count == 12, "\(identifier)")
        for (index, name) in names.enumerated() {
          // 2026-09-22 is today: the 5th of September has passed, the 5th of October has not.
          let month = index + 1
          let date = month >= 10 ? "2026-\(month)-05" : "2027-0\(month)-05"
          for day in ["5", "৫"] {
            let parsed = parse("ফোন করুন \(day) \(name)")
            #expect(
              parsed.plannedDayOffset == captureDayOffset(date), "\(identifier): \(day) \(name) is the 5th of month \(month)")
            #expect(parsed.title == "ফোন করুন", "\(identifier): \(day) \(name): title")
          }
        }
      }
      let weekdayNames: [[String]] = [
        formatter.weekdaySymbols, formatter.standaloneWeekdaySymbols, formatter.shortWeekdaySymbols,
        formatter.shortStandaloneWeekdaySymbols, formatter.veryShortWeekdaySymbols,
      ]
      for names in weekdayNames {
        #expect(names.count == 7, "\(identifier)")
        for (index, name) in names.enumerated() {
          let parsed = parse("ফোন করুন \(name)")
          if Self.unreadWeekdayAbbreviations[name] != nil {
            #expect(parsed.plannedDayOffset == nil, "\(identifier): \(name) is left in the title")
            #expect(parsed.title == "ফোন করুন \(name)", "\(identifier): \(name): title")
          } else {
            // Index 0 is Sunday; 2026-09-22 is a Tuesday, so a weekday alone is the next such day.
            let delta = (index + 1 - 3 + 7) % 7
            #expect(parsed.plannedDayOffset == (delta == 0 ? 7 : delta), "\(identifier): \(name)")
            #expect(parsed.title == "ফোন করুন", "\(identifier): \(name): title")
          }
        }
      }
      // The system's AM and PM markers after an hour, and its long date.
      let meridiems: [(symbol: String, minutes: Int)] = [
        (formatter.amSymbol, 3 * 60 + 30), (formatter.pmSymbol, 15 * 60 + 30),
      ]
      for meridiem in meridiems {
        for text in ["মিটিং 3:30 \(meridiem.symbol)", "মিটিং 3:30 \(meridiem.symbol)-এ"] {
          let parsed = parse(text)
          #expect(parsed.startMinutes == meridiem.minutes, "\(identifier): \(text)")
          #expect(parsed.title == "মিটিং", "\(identifier): \(text): title")
        }
      }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = formatter.timeZone
      let components = DateComponents(year: 2026, month: 10, day: 15, hour: 15, minute: 30)
      if let date = calendar.date(from: components) {
        formatter.timeStyle = .short
        for style in [DateFormatter.Style.medium, .long, .full] {
          formatter.dateStyle = style
          let text = "ফোন করুন " + formatter.string(from: date)
          let parsed = parse(text)
          #expect(parsed.plannedDayOffset == captureDayOffset("2026-10-15"), "\(identifier): \(text): planned day")
          #expect(parsed.startMinutes == 15 * 60 + 30, "\(identifier): \(text): start")
        }
      }
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Bengali, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "bn"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "bn"]).estimatedMinutes == 20)
    #expect(parse("রিপোর্ট 2h").estimatedMinutes == 120)
    #expect(parse("রিপোর্ট 30min").estimatedMinutes == 30)
    #expect(parse("রিপোর্ট 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "bn"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "bn"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "bn"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "bn"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times,
    // also with Bengali digits.
    #expect(parse("মিটিং 5pm").startMinutes == 17 * 60)
    #expect(parse("মিটিং 5 PM").startMinutes == 17 * 60)
    #expect(parse("মিটিং 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("মিটিং ১৭:৩০").startMinutes == 17 * 60 + 30)
    #expect(parse("মিটিং ৩pm").startMinutes == 15 * 60)
    #expect(parse("মিটিং 30 min").estimatedMinutes == 30)
    #expect(parse("মিটিং ৩০ min").estimatedMinutes == 30)
    // A letter h after a number is no clock time for Bengali: 2h and 15h read as English reads them alone.
    for text in [
      "Run 2h", "Run 15h", "Meet at 15h", "Call at 9h30", "Read 1.5h", "রিপোর্ট 2h", "রিপোর্ট 15h",
      "রিপোর্ট ২h", "রিপোর্ট ১৫h", "মিটিং 9h30", "ওষুধ খান প্রতি 2h",
    ] {
      #expect(parse(text, languages: ["en", "bn"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // English lines read the same with Bengali beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "bn"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom কাল at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting শুক্রবার at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("মিটিং tomorrow বিকেল ৫টায়")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "মিটিং")
    let bengaliTitle = parse("সভা next friday")
    #expect(bengaliTitle.plannedDayOffset == 10)
    #expect(bengaliTitle.title == "সভা")
    #expect(parse("সভা 2h").estimatedMinutes == 120)
  }

  @Test("Lines in other languages read the same with Bengali beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"), ("تقرير قبل الخميس", "ar"),
      ("مراجعة من 3 إلى 5 مارس", "ar"), ("تماس با مادر فردا ساعت ۳ بعدازظهر", "fa"), ("ورزش هر دوشنبه", "fa"),
      ("گزارش تا جمعه", "fa"), ("امی کو فون کرنا کل شام 5 بجے", "ur"), ("رپورٹ جمعہ تک", "ur"),
      ("Позвонить маме завтра в 15:00", "ru"), ("Спортзал каждый понедельник", "ru"), ("Отчёт до пятницы", "ru"),
      ("Подзвонити мамі завтра о 15:00", "uk"), ("Звіт до п'ятниці", "uk"),
      ("Appeler maman demain à 15h", "fr"), ("Réunion tous les lundis à 9h", "fr"), ("Rapport avant vendredi", "fr"),
      ("Lire 30 min", "fr"), ("Réunion de 14h à 16h", "fr"), ("Vacances du 3 au 5 mai", "fr"),
      ("Courses ce soir à 19h", "fr"), ("Dentiste après-demain", "fr"), ("Payer le loyer le 5 de chaque mois", "fr"),
      ("Llamar a mamá mañana a las 15:00", "es"), ("Gimnasio cada lunes", "es"), ("Informe antes del viernes", "es"),
      ("Reunión a las 3 de la tarde", "es"), ("Vacaciones del 3 al 5 de mayo", "es"), ("Leer 30 minutos", "es"),
      ("Chiamare mamma domani alle 15:00", "it"), ("Palestra ogni lunedì", "it"), ("Relazione entro venerdì", "it"),
      ("Leggere 30 minuti", "it"),
      ("Ligar para a mãe amanhã às 15h", "pt"), ("Relatório até sexta", "pt"), ("Academia toda segunda", "pt"),
      ("Ler 30 minutos", "pt"),
      ("Zadzwonić jutro o 15:00", "pl"), ("Siłownia co poniedziałek", "pl"), ("Raport do piątku", "pl"),
      ("Czytać 30 minut", "pl"),
      ("Zahnarzt übermorgen", "de"), ("Meeting um 15 Uhr", "de"), ("Sport jeden Montag", "de"),
      ("Bericht bis Freitag", "de"), ("Urlaub vom 3. bis 5. Mai", "de"), ("Zahnarzt am Freitag", "de"),
      ("Tandarts morgen", "nl"), ("Sporten elke maandag", "nl"), ("Rapport voor vrijdag", "nl"),
      ("Dentist poimâine", "ro"), ("Ședință la ora 15", "ro"), ("Alergare în fiecare luni", "ro"),
      ("Rapat besok jam 3 sore", "id"), ("Senam setiap Senin", "id"), ("Laporan sebelum Jumat", "id"),
      ("Mesyuarat esok pukul 3 petang", "ms"), ("Senaman setiap Isnin", "ms"),
      ("Họp ngày mai lúc 3 giờ chiều", "vi"), ("Tập gym mỗi thứ Hai", "vi"),
      ("Diş doktoru yarın saat 3'te", "tr"), ("Spor her pazartesi", "tr"), ("Raporu cumaya kadar bitir", "tr"),
      ("Toplantı akşam 8'de", "tr"), ("Rapor 30 dakika acil", "tr"),
      ("Οδοντίατρος αύριο στις 3", "el"), ("Αναφορά μέχρι την Παρασκευή", "el"), ("Γυμναστική κάθε Δευτέρα", "el"),
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
      ("माँ को फोन करें कल शाम 5 बजे", "hi"), ("जिम हर सोमवार", "hi"), ("रिपोर्ट भेजें शुक्रवार तक", "hi"),
      ("आईला फोन करा उद्या संध्याकाळी 5 वाजता", "mr"), ("जिम दर सोमवारी", "mr"), ("रिपोर्ट पाठवा शुक्रवारपर्यंत", "mr"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "bn"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["bn", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Bengali with another language.
    for languages in [["fr", "bn"], ["bn", "fr"]] {
      let mixed = parse("Appeler maman কাল à 15h", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("জিম প্রতি সোমবার", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
    }
    #expect(parse("Meeting 下午3点 কাল", languages: ["zh", "bn"]).plannedDayOffset == 1)
    #expect(parse("Meeting מחר কাল", languages: ["he", "bn"]).plannedDayOffset == 1)
  }

  @Test("Bengali lines read the same beside every other language")
  func besideEveryLanguage() {
    let lines = [
      "মাকে ফোন করুন কাল বিকেল 5টায়", "জিম প্রতি সোমবার সকাল ৯টায়", "রিপোর্ট পাঠান শুক্রবার পর্যন্ত জরুরি",
      "ছুটি ৩ থেকে ৫ মার্চ", "রিপোর্ট লেখা 20 মিনিট", "ওষুধ খান প্রতি ২ সপ্তাহে", "ভাড়া প্রতি মাসের ৫ তারিখে",
      "মিটিং সাড়ে ৩টায় উচ্চ প্রাধান্য", "ফোন করুন ১৫ অক্টোবর", "ফোন করুন 15/10/2026", "ফোন করুন 15.10.2026",
      "রিপোর্ট পাঠান শেষ তারিখ: শুক্রবার", "পরের সোমবার সন্ধ্যা ৭:৩০ এ ডিনার", "রোজ সকালে ৬টায় যোগব্যায়াম",
      "মিটিং ২টা থেকে ৪টা পর্যন্ত", "ফোন করুন ৩ দিন পর", "রিপোর্ট লেখা দেড় ঘণ্টা", "শনিবার ও রবিবার ঘুরতে যাওয়া",
      "আজকের রিপোর্ট", "রবিকে ফোন করুন", "প্রতিদিনের কাজ #তালিকা", "সোমবার থেকে বুধবার শিবির",
    ]
    let others = [
      "ar", "de", "el", "es", "fa", "fr", "he", "hi", "id", "it", "ja", "ko", "mr", "ms", "nl", "pl", "pt", "ro",
      "ru", "th", "tr", "uk", "ur", "vi", "zh",
    ]
    for text in lines {
      let alone = parse(text)
      for language in others {
        #expect(parse(text, languages: ["bn", language]) == alone, "\(text) beside \(language)")
        #expect(parse(text, languages: [language, "bn"]) == alone, "\(text) beside \(language), reversed")
      }
    }
  }

  @Test("Bengali words are read only for a user who reads Bengali")
  func languageGate() {
    let text = "মাকে ফোন করুন কাল"
    let line = parse(text, languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == text)
    for languages in [["bn"], ["bn-BD"], ["bn_BD"], ["bn-IN"], ["en-US", "bn-IN"], ["BN"], ["bn-Beng-IN"]] {
      #expect(parse(text, languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages are not Bengali: Assamese, which shares the script, and the Devanagari languages get no Bengali words.
    for language in ["as", "hi", "mr", "ne", "ur"] {
      #expect(parse(text, languages: [language]).plannedDayOffset == nil, "\(language)")
    }
    // Other languages' words are not read for a Bengali reader, and Bengali is not read for theirs.
    expectLinesUnread(
      ["Zadzwonić jutro", "Позвонить завтра", "اتصل بأمي غداً", "Appeler maman demain", "Zahnarzt übermorgen"],
      languages: ["bn"])
    for languages in [
      ["ar"], ["pl"], ["ru"], ["fr"], ["es"], ["it"], ["pt"], ["he"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"],
      ["tr"], ["el"], ["th"], ["fa"], ["ur"], ["uk"], ["ja"], ["ko"], ["zh"], ["hi"], ["mr"],
    ] {
      let parsed = parse(text, languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == text, "\(languages): title")
    }
    // A clock time, a repeat, a priority, and a length with a Bengali word need Bengali among the languages.
    #expect(parse("মিটিং বিকেল ৫টায়", languages: ["en"]).startMinutes == nil)
    #expect(parse("ওষুধ খান প্রতি সোমবার", languages: ["en"]).recurrence == nil)
    #expect(parse("রিপোর্ট পাঠান উচ্চ প্রাধান্য", languages: ["en"]).priority == nil)
    #expect(parse("রিপোর্ট লেখা ৩০ মিনিট", languages: ["en"]).estimatedMinutes == nil)
    // Bengali and Arabic readers get both.
    #expect(parse(text, languages: ["ar", "bn"]).plannedDayOffset == 1)
    #expect(parse("اتصل بأمي غداً", languages: ["ar", "bn"]).plannedDayOffset == 1)
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["bn"])
    let unit: [String] = [
      "টায় ", "৫টায় ", "৫:৩০টায় ", "সকাল ৫টায় ", "সাড়ে পাঁচটায় ", "দেড়টায় ", "আড়াইটায় ", "সোয়া ", "পৌনে ",
      "সাড়ে ", "কাল ", "কাল সকালে ", "আজ রাতে ", "পরশু ", "শুক্রবারে ", "শুক্রবার সন্ধ্যায় ", "এই শুক্রবার ",
      "পরের শুক্রবার ", "পরের সপ্তাহে ", "১৫ অক্টোবর ", "১৫ অক্টো. ", "১৫.১০.২০২৬ ", "১৫/১০ ", "১৫/১০ এ ",
      "৩ থেকে ৫ মার্চ ", "৩ মার্চ থেকে ৫ মার্চ পর্যন্ত ", "৩-৫ মার্চ ", "পর্যন্ত ", "শুক্রবার পর্যন্ত ",
      "শেষ তারিখ শুক্রবার ", "ডেডলাইন ", "প্রতিদিন ", "রোজ সকালে ", "প্রতি সোমবার ", "প্রতি সোমবার ও বৃহস্পতিবার ",
      "প্রতি ২ সপ্তাহে ", "প্রতি মাসের ৫ তারিখে ", "প্রতি দ্বিতীয় সোমবারে ", "সোমবার থেকে শুক্রবার ", "উইকেন্ডে ",
      "৩০ মিনিট ", "১.৫ ঘণ্টা ", "১ ঘণ্টা ৩০ মিনিট ", "আধ ঘণ্টা ", "সাড়ে তিন ঘণ্টা ", "জরুরি ", "উচ্চ প্রাধান্য ",
      "প্রাধান্য: ", "রাত ", "মধ্যরাতে ", "থেকে ", "প্রতি ", "ঘণ্টা ", "মিনিট ", "আজ ", "এবং ", "া", "্", "ং", "ঁ",
      "\u{200C}", "\u{200D}", "\u{09BC}", "য\u{09BC}", "ড\u{09BC}", "ঢ\u{09BC}", "\u{09DF}", "\u{09DC}", "\u{09DD}",
      ", ", ".", "-", "–", ":", "।",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "রবি " + String(repeating: token, count: count) + " ফোন"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(5), "\(token) took \(elapsed)")
    }
    #expect(slowest < .seconds(5), "the slowest long line took \(slowest)")
    // A line past the read limit that repeats a recognized phrase is a title and nothing more, at once.
    let past = String(repeating: "কাল সন্ধ্যা ৫টায় ", count: 300).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count >= 5_000)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    // The first phrase of a long line still reads.
    let first = parse("কাল " + String(repeating: "৫টায় কাল ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 17 * 60)
  }
}
