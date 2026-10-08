import Foundation
import Testing

@testable import LorvexCore

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention. Counted in
// days from it, Wednesday is 1, Thursday 2, Friday 3, Saturday 4, Sunday 5,
// Monday 6, and the next Tuesday 7.
private func parse(_ text: String, languages: [String] = ["th"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["th"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weekly = TaskRecurrenceRule(freq: .weekly)
private let monthly = TaskRecurrenceRule(freq: .monthly)
private let yearly = TaskRecurrenceRule(freq: .yearly)

/// The unicode scalars of `text`. A title is compared by them where the typed
/// form matters, since `String` equality treats some spellings of a Thai
/// syllable as equal to others.
private func scalars(_ text: String) -> [Unicode.Scalar] {
  Array(text.unicodeScalars)
}

/// Every ordering of `items`.
private func permutations<Element>(of items: [Element]) -> [[Element]] {
  guard items.count > 1 else { return [items] }
  return items.indices.flatMap { index -> [[Element]] in
    var rest = items
    let head = rest.remove(at: index)
    return permutations(of: rest).map { [head] + $0 }
  }
}

/// Thai capture lines, read for a user whose languages include Thai.
@Suite("Capture parser Thai")
struct CaptureParserThaiTests {
  // MARK: - Days

  @Test("Days: วันนี้, พรุ่งนี้, มะรืนนี้, คืนนี้, a part of the day, next week, the weekend, and a number of days or weeks")
  func days() {
    let line = parse("ประชุมพรุ่งนี้")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "ประชุม")
    #expect(line.phrases.map(\.text) == ["พรุ่งนี้"])

    let days: [(text: String, offset: Int)] = [
      ("ประชุมวันนี้", 0), ("ประชุมพรุ่งนี้", 1), ("ประชุมมะรืนนี้", 2), ("ประชุมมะรืน", 2),
      ("ประชุมคืนนี้", 0), ("ประชุมเย็นนี้", 0), ("ประชุมเช้านี้", 0), ("ประชุมบ่ายนี้", 0),
      ("ประชุมพรุ่งนี้เช้า", 1), ("ประชุมพรุ่งนี้เย็น", 1), ("ประชุมพรุ่งนี้ตอนเย็น", 1),
      ("ประชุมวันนี้ตอนเย็น", 0), ("ประชุมวันนี้ค่ำ", 0), ("ประชุมวันนี้ช่วงบ่าย", 0),
      ("ประชุมสัปดาห์หน้า", 7), ("ประชุมอาทิตย์หน้า", 7), ("ประชุมสุดสัปดาห์", 4),
      ("ประชุมสุดสัปดาห์นี้", 4), ("ประชุมสุดสัปดาห์หน้า", 11), ("ประชุมเสาร์อาทิตย์", 4),
      ("ประชุมอีก 3 วัน", 3), ("ประชุมอีกสามวัน", 3), ("ประชุมอีก 10 วัน", 10), ("ประชุมอีก 2 สัปดาห์", 14),
      ("ประชุมอีกสัปดาห์", 7),
      // The same words set apart by spaces.
      ("ประชุม วันนี้", 0), ("ประชุม พรุ่งนี้", 1), ("ประชุม มะรืนนี้", 2), ("ประชุม คืนนี้", 0),
      ("ประชุม พรุ่งนี้เช้า", 1), ("ประชุม พรุ่งนี้ เช้า", 1), ("ประชุม สัปดาห์หน้า", 7),
      ("ประชุม สุดสัปดาห์", 4), ("ประชุม อีก 3 วัน", 3),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "ประชุม", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    for text in ["พรุ่งนี้ประชุม", "พรุ่งนี้ ประชุม", "พรุ่งนี้, ประชุม", "พรุ่งนี้: ประชุม"] {
      let opening = parse(text)
      #expect(opening.plannedDayOffset == 1, "\(text): planned day")
      #expect(opening.title == "ประชุม", "\(text): title")
    }
    let sentence = parse("พรุ่งนี้มีประชุมทีม")
    #expect(sentence.plannedDayOffset == 1)
    #expect(sentence.title == "มีประชุมทีม")
    // A phrase taken out from between two Thai words leaves one space between them.
    let between = parse("ส่งงานพรุ่งนี้ที่ห้องประชุม")
    #expect(between.plannedDayOffset == 1)
    #expect(between.title == "ส่งงาน ที่ห้องประชุม")
    // A month or a year ahead has no day offset, an amount of hours is no day, and "this week" is no day.
    expectLinesUnread(
      [
        "ประชุมอีก 3 เดือน", "ประชุมอีก 3 ชั่วโมง", "ประชุมอีกปี", "ประชุมสัปดาห์นี้", "ประชุมอาทิตย์นี้",
        "ประชุมเดือนหน้า",
      ], languages: ["th"])
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's, written with วัน, or without it before นี้ and หน้า")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("ประชุมวันจันทร์", 6), ("ประชุมวันอังคาร", 7), ("ประชุมวันพุธ", 1), ("ประชุมวันพฤหัสบดี", 2),
      ("ประชุมวันพฤหัส", 2), ("ประชุมวันพฤหัสฯ", 2), ("ประชุมวันศุกร์", 3), ("ประชุมวันเสาร์", 4),
      ("ประชุมวันอาทิตย์", 5),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "นี้" makes it today.
      ("ประชุมวันอังคารนี้", 0), ("ประชุมวันพุธนี้", 1), ("ประชุมวันศุกร์นี้", 3), ("ประชุมวันเสาร์นี้", 4),
      ("ประชุมวันอาทิตย์นี้", 5), ("ประชุมวันจันทร์นี้", 6),
      // "หน้า" puts the weekday in next week, which starts on Monday.
      ("ประชุมวันจันทร์หน้า", 6), ("ประชุมวันอังคารหน้า", 7), ("ประชุมวันพุธหน้า", 8), ("ประชุมวันศุกร์หน้า", 10),
      ("ประชุมวันเสาร์หน้า", 11), ("ประชุมวันอาทิตย์หน้า", 12),
      ("ประชุมสัปดาห์หน้าวันพุธ", 8), ("ประชุมวันพุธสัปดาห์หน้า", 8), ("ประชุมสัปดาห์หน้าวันจันทร์", 6),
      ("ประชุมอาทิตย์หน้าวันศุกร์", 10), ("ประชุมวันศุกร์ของสัปดาห์หน้า", 10),
      // Without "วัน" a name needs "นี้" or "หน้า" after it.
      ("ประชุมศุกร์นี้", 3), ("ประชุมศุกร์หน้า", 10), ("ประชุมพุธนี้", 1), ("ประชุมจันทร์หน้า", 6),
      ("ประชุมวันศุกร์ที่จะถึง", 3), ("ประชุมวันศุกร์ที่จะถึงนี้", 3),
      // A part of the day written after the weekday goes with it.
      ("ประชุมวันศุกร์ตอนเย็น", 3), ("ประชุมวันศุกร์เย็น", 3), ("ประชุมวันศุกร์เช้า", 3),
      ("ประชุมวันเสาร์ช่วงบ่าย", 4),
      // The same words set apart by spaces.
      ("ประชุม วันศุกร์", 3), ("ประชุม วันศุกร์หน้า", 10), ("ประชุม สัปดาห์หน้า วันพุธ", 8),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "ประชุม", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("ประชุมวันศุกร์ 9 โมง")
    #expect(timed.plannedDayOffset == 3)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "ประชุม")
    for text in ["วันศุกร์ประชุม", "วันศุกร์ ประชุม"] {
      let opening = parse(text)
      #expect(opening.plannedDayOffset == 3, "\(text)")
      #expect(opening.title == "ประชุม", "\(text): title")
    }
    // The weekdays of a list name no single planned day.
    expectLinesUnread(["ประชุมวันจันทร์และวันพุธ", "ประชุมวันจันทร์, วันพุธ", "ประชุมวันจันทร์หรือวันอังคาร"], languages: ["th"])
  }

  @Test("A weekday name without วัน is no day by itself, and a name inside a longer word is no day")
  func ambiguousNames() {
    // "อาทิตย์" is also the word for a week, so Sunday is never read without "วัน".
    expectLinesUnread(
      [
        "ประชุมศุกร์", "ประชุมจันทร์", "ประชุมพุธ", "ประชุมอังคาร", "ประชุมเสาร์", "ประชุมอาทิตย์", "ประชุมพฤหัสบดี",
        "ศุกร์", "อาทิตย์",
        // Planets, the moon, a title before a name, and other words that hold a weekday name.
        "ชมพระจันทร์", "ดูดวงจันทร์", "ดาวศุกร์", "ดาวอังคาร", "คุณจันทร์โทรมา", "นายพุธ", "นางสาวศุกร์",
        "อ่านเรื่องดวงจันทร์", "ดวงอาทิตย์ขึ้น", "ตะวันตก",
        // "หน้า" that begins another word.
        "ซื้อหน้าต่าง", "เปิดหน้าจอ", "สัปดาห์หน้าต่าง",
      ], languages: ["th"])
    // "หน้า" glued to the letters of a longer word is no "next", so the weekday before it is this week's.
    let window = parse("วันศุกร์หน้าต่าง")
    #expect(window.plannedDayOffset == 3)
    #expect(window.title == "หน้าต่าง")
    // A weekday glued to the word before it still reads, since Thai has no spaces.
    let glued = parse("ซื้อของวันอาทิตย์")
    #expect(glued.plannedDayOffset == 5)
    #expect(glued.title == "ซื้อของ")
    let after = parse("เรียนวันศุกร์")
    #expect(after.plannedDayOffset == 3)
    #expect(after.title == "เรียน")
    // A part of the day before the weekday stays with the word before it.
    let evening = parse("ประชุมเย็นวันศุกร์")
    #expect(evening.plannedDayOffset == 3)
    #expect(evening.title == "ประชุมเย็น")
  }

  @Test("Past days and weeks are not read, and a clock time after one stays with it")
  func pastDays() {
    expectLinesUnread(
      [
        "ประชุมเมื่อวาน", "ประชุมเมื่อวานนี้", "ประชุมเมื่อวานนี้ 3 โมง", "ประชุมเมื่อวานซืน", "ประชุมเมื่อคืน",
        "ประชุมเมื่อคืนนี้", "ประชุมเมื่อเช้า", "ประชุมเมื่อวันพุธ", "ประชุมเมื่อวันศุกร์", "ประชุมวันพุธที่แล้ว",
        "ประชุมวันศุกร์ที่แล้ว", "ประชุมอาทิตย์ที่แล้ว", "ประชุมสัปดาห์ที่แล้ว", "ประชุมเดือนที่แล้ว",
        "ประชุมปีที่แล้ว", "ประชุม 2 สัปดาห์ก่อน", "ประชุม 2 วันที่แล้ว", "ประชุมเมื่อ 3 วันก่อน",
        "ประชุม 3 วันก่อน", "ประชุมเมื่อวานตอนเย็น", "ประชุมเมื่อวันที่ 15", "สัปดาห์ที่แล้ว", "เมื่อคืน", "เมื่อเช้า",
      ], languages: ["th"])
    // The words that follow a past day keep their own reading.
    let after = parse("ประชุมเมื่อวาน พรุ่งนี้")
    #expect(after.plannedDayOffset == 1)
    #expect(after.title == "ประชุมเมื่อวาน")
    // "ทุกวันนี้" is nowadays, and "ทุกวัน" inside it is no repeat.
    expectLinesUnread(["ทุกวันนี้", "ประชุมทุกวันนี้", "ส่งรายงานทุกวันนี้"], languages: ["th"])
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("ประชุมสุดสัปดาห์", 0), ("ประชุมสุดสัปดาห์หน้า", 7), ("ประชุมวันเสาร์", 7), ("ประชุมวันเสาร์นี้", 0),
      ("ประชุมวันอาทิตย์", 1), ("ประชุมวันจันทร์", 2), ("ประชุมวันศุกร์หน้า", 6),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("ประชุมสุดสัปดาห์", 0), ("ประชุมสุดสัปดาห์หน้า", 6), ("ประชุมวันอาทิตย์", 7), ("ประชุมวันอาทิตย์นี้", 0),
      ("ประชุมวันเสาร์", 6), ("ประชุมวันจันทร์", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "นี้" makes it today.
    for (text, offset) in [
      ("ประชุมวันจันทร์", 7), ("ประชุมวันจันทร์นี้", 0), ("ประชุมวันจันทร์หน้า", 7), ("ประชุมวันอังคาร", 1),
      ("ประชุมสัปดาห์หน้าวันจันทร์", 7),
    ] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("ส่งรายงานภายในวันจันทร์", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("ประชุมทุกวันจันทร์", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("สัมมนา ตั้งแต่วันจันทร์ถึงวันพุธ", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year of either era, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("เที่ยวบิน 15 ตุลาคม", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ต.ค.", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ตุลาคมนี้", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ต.ค.นี้", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน วันที่ 15 ตุลาคมนี้", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15ตุลาคม", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน ๑๕ ตุลาคม", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ตุลาคม 2569", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ตุลาคม 2026", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ตุลาคม 2570", "เที่ยวบิน", "2027-10-15"),
      ("เที่ยวบิน 15 ต.ค. 2569", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ต.ค. พ.ศ. 2569", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ต.ค. ค.ศ. 2026", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน ๑๕ ตุลาคม ๒๕๖๙", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15 ตุลาคม ๒๕๖๙", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15/10/2569", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15/10/2026", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15-10-2569", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15-10-2026", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 15.10.2569", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน ๑๕/๑๐/๒๕๖๙", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน วันที่ 15/10", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน วันที่ 15/10/69", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน วันที่ 15/10/26", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน วันที่ 15 ตุลาคม", "เที่ยวบิน", "2026-10-15"),
      ("เที่ยวบิน 22 กันยายน", "เที่ยวบิน", "2026-09-22"),
      ("เที่ยวบิน 1 มกราคม 2570", "เที่ยวบิน", "2027-01-01"),
      ("เที่ยวบิน 29 กุมภาพันธ์ 2571", "เที่ยวบิน", "2028-02-29"),
      ("เที่ยวบิน 31 ธ.ค. 2569", "เที่ยวบิน", "2026-12-31"),
      // A weekday before the date is part of it.
      ("เที่ยวบิน วันศุกร์ที่ 16 ตุลาคม", "เที่ยวบิน", "2026-10-16"),
      ("เที่ยวบิน วันศุกร์ 16 ตุลาคม", "เที่ยวบิน", "2026-10-16"),
      ("วันเกิดแม่ 15 ตุลาคม", "วันเกิดแม่", "2026-10-15"),
      ("ท่องเที่ยว 1 มกราคม 2570 10:00 น.", "ท่องเที่ยว", "2027-01-01"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == (line.text.contains("10:00") ? 2 : 1), "\(line.text): phrases")
    }
    // Each month by its name and its abbreviation, on a day that is the next one in the calendar.
    let months: [(name: String, abbreviation: String, date: String)] = [
      ("มกราคม", "ม.ค.", "2027-01-03"), ("กุมภาพันธ์", "ก.พ.", "2027-02-03"), ("มีนาคม", "มี.ค.", "2027-03-03"),
      ("เมษายน", "เม.ย.", "2027-04-03"), ("พฤษภาคม", "พ.ค.", "2027-05-03"), ("มิถุนายน", "มิ.ย.", "2027-06-03"),
      ("กรกฎาคม", "ก.ค.", "2027-07-03"), ("สิงหาคม", "ส.ค.", "2027-08-03"), ("กันยายน", "ก.ย.", "2027-09-03"),
      ("ตุลาคม", "ต.ค.", "2026-10-03"), ("พฤศจิกายน", "พ.ย.", "2026-11-03"), ("ธันวาคม", "ธ.ค.", "2026-12-03"),
    ]
    for month in months {
      for form in [month.name, month.abbreviation] {
        let text = "เที่ยวบิน 3 \(form)"
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == captureDayOffset(month.date), "\(text)")
        #expect(parsed.title == "เที่ยวบิน", "\(text): title")
        #expect(parsed.phrases.count == 1, "\(text): phrases")
      }
    }
    // A date and a time, in either order.
    let timed = parse("ประชุม 15 ตุลาคม 14:00 น.")
    #expect(timed.plannedDayOffset == 23)
    #expect(timed.startMinutes == 14 * 60)
    #expect(timed.title == "ประชุม")
    let reversed = parse("ประชุมบ่ายสองโมง 15/10/2569")
    #expect(reversed.plannedDayOffset == 23)
    #expect(reversed.startMinutes == 14 * 60)
    #expect(reversed.title == "ประชุม")
  }

  @Test("A day of the month alone, and a weekday with its date, name the next such date")
  func dayOfMonth() {
    for (text, offset) in [
      ("ประชุมวันที่ 15", 23), ("ประชุมในวันที่ 15", 23), ("ประชุมวันที่ 22", 0), ("ประชุมวันที่ 31", 39),
      ("ประชุมวันที่ ๑๕", 23), ("ประชุมวันอังคารที่ 29", 7), ("ประชุมวันศุกร์ที่ 16", 24),
      ("ประชุมวันพุธที่ 14", 22), ("ประชุมวันที่ 15 โมง", 23),
    ] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == offset, "\(text)")
      #expect(parsed.title.hasPrefix("ประชุม"), "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A day that is no day of the weekday it names, a list or a range of days, a day of something else, a
    // numbered part, a count, the past, and a stretch of time that ends on the day are no planned day.
    expectLinesUnread(
      [
        "สัมมนาวันที่ 1: เตรียมงาน", "สัมมนาวันที่ 2 ของงาน", "สัมมนาวันที่ 2 และ 3", "สัมมนาวันที่ 2-3",
        "สัมมนาวันที่ 2 ถึง 3", "สัมมนาวันที่ 3 ครั้ง", "ประชุมเมื่อวันที่ 15", "ส่งงานถึงวันที่ 15",
        "ประชุมวันศุกร์ที่ 3 ของเดือน", "ประชุมวันศุกร์ที่สามของเดือน", "ส่งงานถึงวันศุกร์",
      ], languages: ["th"])
    // "วันที่ 2 ของเดือน" is a monthly repeat, and "ทุกวันที่ 15" too.
    #expect(parse("สัมมนาวันที่ 2 ของเดือน").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [2]))
    #expect(parse("ประชุมทุกวันที่ 15").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [15]))
  }

  @Test("Numbers that are no date, a month with no day, a past year, and a day the month lacks stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers with no word that makes them a date, and a month with no day.
        "เที่ยวบิน 15/10", "เที่ยวบิน 15.10", "เที่ยวบิน ตุลาคม", "ประชุมเดือนตุลาคม", "ประชุมตุลาคม", "มกราคม",
        "เที่ยวบิน 15 ตุลา",
        // A day the month lacks, a day past the month's end, a year that is past, and a leap day of a common year.
        "เที่ยวบิน 31 กุมภาพันธ์", "เที่ยวบิน 32 พฤษภาคม", "เที่ยวบิน 1 กันยายน 2569", "ท่องเที่ยว 29 กุมภาพันธ์ 2570",
        "เที่ยวบิน 15/10/69", "เที่ยวบิน 32 ตุลาคมนี้", "เที่ยวบิน 31 กุมภาพันธ์นี้", "เที่ยวบิน 0 ตุลาคมนี้",
        // Versions, scores, fractions, prices, percentages, addresses, and phone numbers.
        "ราคา 10.30 บาท", "เวอร์ชัน 1.10.2026", "ข้อ 3/4/2026", "ซอย 99/9/2569", "บ้านเลขที่ 99/9", "คะแนน 3-1",
        "ผสมน้ำ 1/2 ถ้วย", "IP 192.168.1.1", "iOS 17.4", "โทร 02 123 4567",
      ], languages: ["th"])
    // A percentage is no date, and the day word after it still reads.
    let discount = parse("ลดราคา 15% พรุ่งนี้")
    #expect(discount.plannedDayOffset == 1)
    #expect(discount.title == "ลดราคา 15%")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("ลาพักร้อน", "3-5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "3 ถึง 5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "ตั้งแต่ 3 ถึง 5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "จาก 3 ถึง 5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "ระหว่าง 3 ถึง 5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "วันที่ 3-5 พฤษภาคม 2570", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "3-5 พ.ค. 2570", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "3-5 พ.ค.", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "3-5 พฤษภาคมนี้", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "3-5 พ.ค.นี้", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "3 พฤษภาคม - 5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "30 พฤษภาคม - 2 มิถุนายน", "2027-05-30", "2027-06-02"),
        ("ลาพักร้อน", "30 เม.ย. - 3 พ.ค.", "2027-04-30", "2027-05-03"),
        ("ลาพักร้อน", "1-3 ต.ค.", "2026-10-01", "2026-10-03"),
        ("ลาพักร้อน", "ตั้งแต่ ๓ ถึง ๕ พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อน", "วันที่ 3 ถึงวันที่ 5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ("ลาพักร้อนช่วงปลายปี", "24 ธ.ค. - 2 ม.ค.", "2026-12-24", "2027-01-02"),
      ], languages: ["th"])
    // Glued to the title, a range reads the same.
    let glued = parse("ลาพักร้อน3-5 พฤษภาคม")
    #expect(glued.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(glued.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(glued.title == "ลาพักร้อน")
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "ลาพักร้อน 5-3 พฤษภาคม", "ลาพักร้อน 3 พฤษภาคม - 3 พฤษภาคม", "ลาพักร้อน ตั้งแต่ 3 ถึง 5", "ราคา 3-5 บาท",
        "ลาพักร้อน ตั้งแต่ 5 พฤษภาคม ถึง 3 พฤษภาคม",
      ], languages: ["th"])
    // A number of the title set apart from a date by a spaced dash is a title and a date: "Sprint 12 - 20 พฤษภาคม".
    for (text, title, date) in [
      ("Sprint 12 - 20 พฤษภาคม", "Sprint 12", "2027-05-20"), ("ประชุมรอบ 12 - 14 ตุลาคม", "ประชุมรอบ 12", "2026-10-14"),
      ("ลาพักร้อน 3 - 5 พฤษภาคม", "ลาพักร้อน 3", "2027-05-05"),
    ] {
      let parsed = parse(text)
      #expect(parsed.title == title, "\(text): title")
      #expect(parsed.plannedDayOffset == captureDayOffset(date), "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time, a length, and a repeat still read")
  func rangeTakesBothDays() {
    let line = parse("ลาพักร้อน 3-5 พฤษภาคม พรุ่งนี้")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "ลาพักร้อน พรุ่งนี้")
    let timed = parse("ลาพักร้อน 3-5 พฤษภาคม 10:00 น.")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 10 * 60)
    #expect(timed.title == "ลาพักร้อน")
    let length = parse("ลาพักร้อน 3-5 พฤษภาคม 30 นาที")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "ลาพักร้อน")
    let yearly = parse("ลาพักร้อน 3-5 พฤษภาคม ทุกปี")
    #expect(yearly.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(yearly.recurrence == TaskRecurrenceRule(freq: .yearly))
    let urgent = parse("ลาพักร้อน 3-5 พฤษภาคม ด่วน")
    #expect(urgent.priority == .p1)
    #expect(urgent.title == "ลาพักร้อน")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so the span ends on the Wednesday
    // after the Monday.
    expectDateRanges(
      [
        ("สัมมนา", "ตั้งแต่วันศุกร์ถึงวันอาทิตย์", "2026-09-25", "2026-09-27"),
        ("สัมมนา", "จากวันศุกร์ถึงวันอาทิตย์", "2026-09-25", "2026-09-27"),
        ("สัมมนา", "วันศุกร์ถึงวันอาทิตย์", "2026-09-25", "2026-09-27"),
        ("สัมมนา", "วันศุกร์-อาทิตย์", "2026-09-25", "2026-09-27"),
        ("สัมมนา", "วันศุกร์ - วันอาทิตย์", "2026-09-25", "2026-09-27"),
        ("สัมมนา", "ตั้งแต่ศุกร์ถึงอาทิตย์", "2026-09-25", "2026-09-27"),
        ("สัมมนา", "ตั้งแต่วันศุกร์ถึงวันจันทร์", "2026-09-25", "2026-09-28"),
        ("สัมมนา", "ตั้งแต่วันพุธถึงวันศุกร์", "2026-09-23", "2026-09-25"),
        ("สัมมนา", "ตั้งแต่วันจันทร์ถึงวันพุธ", "2026-09-28", "2026-09-30"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("สัมมนา", "ตั้งแต่วันอังคารถึงวันพฤหัสบดี", "2026-09-29", "2026-10-01"),
      ], languages: ["th"])
    // Names with no วัน or opening word are no span, and a span from a day to itself makes no range.
    expectLinesUnread(["สัมมนา ศุกร์ถึงอาทิตย์", "สัมมนา ตั้งแต่วันศุกร์ถึงวันศุกร์"], languages: ["th"])
    #expect(parse("สัมมนา วันศุกร์ถึงวันศุกร์").dueDayOffset == nil)
  }

  // MARK: - Due days

  @Test("Due days: ภายใน, ไม่เกิน, ก่อน, จนถึง, เดดไลน์, deadline, กำหนดส่ง, ครบกำหนด")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("ส่งรายงานภายในวันศุกร์", "ส่งรายงาน", 3), ("ส่งรายงานก่อนวันศุกร์", "ส่งรายงาน", 3),
      ("ส่งรายงานไม่เกินวันศุกร์", "ส่งรายงาน", 3), ("ส่งรายงานจนถึงวันศุกร์", "ส่งรายงาน", 3),
      ("ส่งรายงานเดดไลน์วันศุกร์", "ส่งรายงาน", 3), ("ส่งรายงานเดดไลน์: วันศุกร์", "ส่งรายงาน", 3),
      ("ส่งรายงาน deadline วันศุกร์", "ส่งรายงาน", 3), ("ส่งรายงานกำหนดส่ง: วันศุกร์", "ส่งรายงาน", 3),
      ("ส่งรายงานครบกำหนดวันศุกร์", "ส่งรายงาน", 3), ("ส่งรายงานภายในศุกร์", "ส่งรายงาน", 3),
      ("ส่งรายงานก่อนศุกร์นี้", "ส่งรายงาน", 3), ("ส่งรายงานภายในวันศุกร์นี้", "ส่งรายงาน", 3),
      ("ส่งรายงานภายในวันศุกร์หน้า", "ส่งรายงาน", 10), ("ส่งรายงานภายในวันอังคาร", "ส่งรายงาน", 7),
      ("ส่งรายงานภายในพรุ่งนี้", "ส่งรายงาน", 1), ("ส่งรายงานภายในวันนี้", "ส่งรายงาน", 0),
      ("ส่งรายงานก่อนพรุ่งนี้", "ส่งรายงาน", 1), ("ส่งรายงานเดดไลน์: พรุ่งนี้", "ส่งรายงาน", 1),
      ("ส่งรายงานภายในมะรืนนี้", "ส่งรายงาน", 2), ("ส่งรายงานภายในสัปดาห์หน้า", "ส่งรายงาน", 7),
      ("ส่งรายงานภายใน 3 วัน", "ส่งรายงาน", 3), ("ส่งรายงานภายในสามวัน", "ส่งรายงาน", 3),
      ("ส่งรายงานภายใน 2 สัปดาห์", "ส่งรายงาน", 14),
      ("ส่งรายงานภายใน 15 ตุลาคม", "ส่งรายงาน", 23), ("ส่งรายงานภายใน 15 ต.ค.", "ส่งรายงาน", 23),
      ("ส่งรายงานภายใน 15 ตุลาคมนี้", "ส่งรายงาน", 23),
      ("ส่งรายงานภายในวันที่ 15 ตุลาคม", "ส่งรายงาน", 23), ("ส่งรายงานภายในวันที่ 15", "ส่งรายงาน", 23),
      ("ส่งรายงานก่อนวันที่ 15", "ส่งรายงาน", 23), ("ส่งรายงานก่อนวันที่ 22", "ส่งรายงาน", 0),
      ("ส่งรายงานกำหนดส่ง 15/10", "ส่งรายงาน", 23), ("ส่งรายงานก่อน 15/10/2569", "ส่งรายงาน", 23),
      ("ส่งรายงานภายในวันศุกร์ที่ 16", "ส่งรายงาน", 24), ("ส่งรายงานภายในสุดสัปดาห์", "ส่งรายงาน", 4),
      ("ส่งรายงานภายใน ๑๕ ตุลาคม ๒๕๖๙", "ส่งรายงาน", 23),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("ส่งรายงานภายในวันศุกร์ พรุ่งนี้")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "ส่งรายงาน")
    // A due phrase that opens the line.
    let opening = parse("ภายในวันศุกร์ ส่งรายงาน")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "ส่งรายงาน")
    // A day with no word that makes it a deadline is a planned day.
    #expect(parse("ส่งรายงานวันศุกร์").plannedDayOffset == 3)
    #expect(parse("ส่งรายงานวันศุกร์").dueDayOffset == nil)
    // A bound that is no day, a bare number, and a past day after it are no deadline. A day after "ถึง" or
    // "ตั้งแต่" is the end or the start of a stretch of time and no day of its own.
    expectLinesUnread(
      [
        "ส่งรายงานก่อนหน้านี้", "ส่งรายงานภายใน 5", "ส่งรายงานก่อนเมื่อวาน", "ส่งรายงานถึงวันศุกร์",
        "ส่งรายงานตั้งแต่วันศุกร์", "ส่งรายงานตั้งแต่พรุ่งนี้", "ส่งรายงานตั้งแต่ 15 ตุลาคม", "ส่งรายงานถึงพรุ่งนี้",
        "ส่งรายงานถึง 15 ตุลาคม",
      ], languages: ["th"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "ส่งงานก่อน 17:00 น.", "ส่งงานภายใน 5 โมงเย็น", "ส่งงานไม่เกินบ่ายสาม", "ประชุมตั้งแต่ 9 โมง",
        "ประชุมตั้งแต่ 9 โมงเป็นต้นไป", "ประชุมหลังเที่ยง", "ประชุมหลัง 5 โมงเย็น", "ประชุมหลังจาก 15.00 น.",
        "ส่งงานก่อนเที่ยง", "ส่งงานก่อนบ่ายสามโมง", "ส่งงานภายใน 17:00", "ส่งงานก่อนเวลา 17:00 น.",
      ], languages: ["th"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("ส่งงานพรุ่งนี้ก่อน 5 โมงเย็น", "ส่งงาน ก่อน 5 โมงเย็น", 1),
      ("ส่งงานภายในวันศุกร์ก่อน 17:00 น.", "ส่งงาน ก่อน 17:00 น.", 3),
      ("ส่งงานภายในวันศุกร์ 5 โมงเย็น", "ส่งงาน 5 โมงเย็น", 3),
      ("ส่งงานก่อนพรุ่งนี้ 17:00 น.", "ส่งงาน 17:00 น.", 1),
      ("ส่งงานวันศุกร์ภายใน 17:00 น.", "ส่งงาน ภายใน 17:00 น.", 3),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A time range that opens with "ตั้งแต่" is still a range, and a plain time after a planned day reads.
    let range = parse("ประชุมตั้งแต่ 9 โมงถึง 11 โมง")
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "ประชุม")
    let plain = parse("ประชุมพรุ่งนี้ 5 โมงเย็น")
    #expect(plain.plannedDayOffset == 1)
    #expect(plain.startMinutes == 17 * 60)
    // Without Thai, English reads the clock time and leaves the words.
    let english = parse("ส่งงานก่อน 17:00 น.", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
  }

  // MARK: - Clock times

  @Test("Clock times on the traditional clock: โมง, ทุ่ม, ตี, เที่ยง, with a part of the day or without one")
  func traditionalClock() {
    let times: [(text: String, minutes: Int)] = [
      // ตี counts the small hours, from one to five.
      ("นัดหมอตีหนึ่ง", 1 * 60), ("นัดหมอตีสอง", 2 * 60), ("นัดหมอตีสาม", 3 * 60), ("นัดหมอตีสี่", 4 * 60),
      ("นัดหมอตีห้า", 5 * 60), ("นัดหมอตี 5", 5 * 60), ("นัดหมอตี5", 5 * 60), ("นัดหมอตีสองครึ่ง", 2 * 60 + 30),
      // The morning hours of โมง run from six to eleven.
      ("นัดหมอหกโมงเช้า", 6 * 60), ("นัดหมอเจ็ดโมงเช้า", 7 * 60), ("นัดหมอ 7 โมงเช้า", 7 * 60),
      ("นัดหมอเก้าโมงเช้า", 9 * 60), ("นัดหมอสิบโมงเช้า", 10 * 60), ("นัดหมอสิบโมง", 10 * 60),
      ("นัดหมอสิบเอ็ดโมง", 11 * 60), ("นัดหมอ 11 โมง", 11 * 60), ("นัดหมอ 8 โมง", 8 * 60),
      ("นัดหมอสิบสองโมง", 12 * 60), ("นัดหมอ 12 โมง", 12 * 60),
      // บ่าย counts from one o'clock, and the evening hours of โมง from three.
      ("นัดหมอบ่ายโมง", 13 * 60), ("นัดหมอหนึ่งโมง", 13 * 60), ("นัดหมอบ่ายสองโมง", 14 * 60),
      ("นัดหมอบ่ายสามโมง", 15 * 60), ("นัดหมอบ่ายสี่โมง", 16 * 60), ("นัดหมอบ่ายห้าโมง", 17 * 60),
      ("นัดหมอบ่ายสาม", 15 * 60), ("นัดหมอบ่ายสอง", 14 * 60), ("นัดหมอสามโมงเย็น", 15 * 60),
      ("นัดหมอสี่โมงเย็น", 16 * 60), ("นัดหมอห้าโมงเย็น", 17 * 60), ("นัดหมอหกโมงเย็น", 18 * 60),
      ("นัดหมอเจ็ดโมงเย็น", 19 * 60), ("นัดหมอแปดโมงเย็น", 20 * 60), ("นัดหมอ 7 โมงเย็น", 19 * 60),
      // An hour of โมง with no part of the day: 1 to 6 o'clock is the afternoon and 7 to 11 the morning.
      ("นัดหมอสองโมง", 14 * 60), ("นัดหมอ 3 โมง", 15 * 60), ("นัดหมอ 6 โมง", 18 * 60), ("นัดหมอ 1 โมง", 13 * 60),
      // ทุ่ม counts the evening, from one (19:00) to five (23:00).
      ("นัดหมอหนึ่งทุ่ม", 19 * 60), ("นัดหมอสองทุ่ม", 20 * 60), ("นัดหมอ 3 ทุ่ม", 21 * 60), ("นัดหมอห้าทุ่ม", 23 * 60),
      ("นัดหมอทุ่มครึ่ง", 19 * 60 + 30), ("นัดหมอห้าทุ่มครึ่ง", 23 * 60 + 30), ("นัดหมอทุ่มตรง", 19 * 60),
      ("นัดหมอ 3 ทุ่มตรง", 21 * 60),
      // "ครึ่ง" adds thirty minutes to the hour it follows.
      ("นัดหมอบ่ายสามครึ่ง", 15 * 60 + 30), ("นัดหมอบ่ายโมงครึ่ง", 13 * 60 + 30), ("นัดหมอ 3 โมงครึ่ง", 15 * 60 + 30),
      ("นัดหมอสามโมงครึ่ง", 15 * 60 + 30), ("นัดหมอ 8 โมงครึ่ง", 8 * 60 + 30), ("นัดหมอบ่ายสองครึ่ง", 14 * 60 + 30),
      // Minutes counted after the hour.
      ("นัดหมอ 3 โมง 15 นาที", 15 * 60 + 15), ("นัดหมอสามโมงสิบห้านาที", 15 * 60 + 15),
      ("นัดหมอบ่ายสามโมงสิบห้านาที", 15 * 60 + 15), ("นัดหมอสามโมงสามสิบนาที", 15 * 60 + 30),
      ("นัดหมอสามโมงยี่สิบนาที", 15 * 60 + 20), ("นัดหมอสามโมงสิบเอ็ดนาที", 15 * 60 + 11),
      // An exact hour.
      ("นัดหมอ 10 โมงตรง", 10 * 60), ("นัดหมอบ่ายโมงตรง", 13 * 60),
      // Words that introduce a time go with it.
      ("นัดหมอเวลาบ่ายสามโมง", 15 * 60), ("นัดหมอตอนบ่ายสามโมง", 15 * 60), ("นัดหมอตอนเที่ยง", 12 * 60),
      ("นัดหมอ เที่ยง", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "นัดหมอ", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A time and a day in either order, glued or spaced.
    for text in ["ประชุมพรุ่งนี้บ่ายสามโมง", "ประชุม พรุ่งนี้ บ่ายสามโมง", "ประชุมบ่ายสามโมงพรุ่งนี้", "ประชุม บ่ายสามโมง พรุ่งนี้"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text): planned day")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "ประชุม", "\(text): title")
    }
    // A time after "ถึง" in the sense of arriving is still a time.
    let arriving = parse("ไปถึงบ่ายโมง")
    #expect(arriving.startMinutes == 13 * 60)
    #expect(arriving.title == "ไปถึง")
    // The noon of a day word.
    for (text, day) in [("นัดพรุ่งนี้เที่ยง", 1), ("นัดวันศุกร์เที่ยง", 3)] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day, "\(text): planned day")
      #expect(parsed.startMinutes == 12 * 60, "\(text): time")
      #expect(parsed.title == "นัด", "\(text): title")
    }
  }

  @Test("Clock times with a unit: น., นาฬิกา, and the colon form after เวลา or ตอน")
  func unitClock() {
    let times: [(text: String, minutes: Int)] = [
      ("นัดหมอ 15:00 น.", 15 * 60), ("นัดหมอ 15.00 น.", 15 * 60), ("นัดหมอ 15:30 น.", 15 * 60 + 30),
      ("นัดหมอ 15.30 น.", 15 * 60 + 30), ("นัดหมอ 15:30น.", 15 * 60 + 30), ("นัดหมอ 15.30น", 15 * 60 + 30),
      ("นัดหมอ 15:30 น", 15 * 60 + 30), ("นัดหมอ ๑๕:๓๐ น.", 15 * 60 + 30), ("นัดหมอ 08:30 น.", 8 * 60 + 30),
      ("นัดหมอ 9 น.", 9 * 60), ("นัดหมอ 10 น.", 10 * 60), ("นัดหมอ 9 นาฬิกา", 9 * 60),
      ("นัดหมอ 15 นาฬิกา 30 นาที", 15 * 60 + 30), ("นัดหมอ 9 นาฬิกา 15 นาที", 9 * 60 + 15),
      ("นัดหมอสิบห้านาฬิกา", 15 * 60),
      // The unit marks the 24-hour clock, so the hour is read as written: "3.30 น." is half past three in the morning.
      ("นัดหมอ 3.30 น.", 3 * 60 + 30), ("นัดหมอ 5.00 น.", 5 * 60), ("นัดหมอ 6.30 น.", 6 * 60 + 30),
      ("นัดหมอ 00:30 น.", 30), ("นัดหมอ 23:59 น.", 23 * 60 + 59),
      ("นัดหมอเวลา 15:30", 15 * 60 + 30), ("นัดหมอตอน 15:30", 15 * 60 + 30), ("นัดหมอตอน 9.30", 9 * 60 + 30),
      ("นัดหมอประมาณ 15:00 น.", 15 * 60), ("นัดหมอเวลาประมาณ 15:00 น.", 15 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "นัดหมอ", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // An hour, a unit, and the word that opens the line.
    let opening = parse("15:00 น. นัดหมอ")
    #expect(opening.startMinutes == 15 * 60)
    #expect(opening.title == "นัดหมอ")
    // A colon time with no Thai word or unit is left to English.
    for text in ["นัดหมอ 15:30", "นัดหมอ 3pm", "นัดหมอ 3 pm", "นัดหมอ 15:00"] {
      let parsed = parse(text)
      #expect(parsed.startMinutes != nil, "\(text)")
      #expect(parsed.title == "นัดหมอ", "\(text): title")
    }
  }

  @Test("An hour of โมง with no part of the day takes the part of the day the line names beside it")
  func partOfTheDayOfTheLine() {
    for (text, day, minutes) in [
      ("ดูหนังพรุ่งนี้เช้า 8 โมง", 1, 8 * 60), ("ดูหนังพรุ่งนี้เย็น 8 โมง", 1, 20 * 60),
      ("ดูหนังพรุ่งนี้บ่าย 3 โมง", 1, 15 * 60), ("ดูหนังพรุ่งนี้ 8 โมงครึ่ง", 1, 8 * 60 + 30),
      ("ดูหนังคืนนี้ 8 โมง", 0, 20 * 60), ("ดูหนังคืนนี้ 10 โมง", 0, 22 * 60), ("ดูหนังเย็นนี้ 7 โมง", 0, 19 * 60),
      ("ดูหนังเช้านี้ 9 โมง", 0, 9 * 60), ("ดูหนังวันนี้ 8 โมง", 0, 8 * 60),
    ] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day, "\(text): planned day")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.title == "ดูหนัง", "\(text): title")
    }
    // The hour a part of the day never goes with is no time, and the day alone reads.
    for text in ["ดูหนังพรุ่งนี้เช้า 2 โมง", "ดูหนังพรุ่งนี้เย็น 12 โมง", "ดูหนังคืนนี้ 3 โมง"] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.plannedDayOffset != nil, "\(text): planned day")
    }
    // A repeat names a part of the day too.
    for (text, minutes) in [("ประชุมทุกเย็น 7 โมง", 19 * 60), ("ประชุมทุกเช้า 7 โมง", 7 * 60), ("ประชุมทุกบ่าย 2 โมง", 14 * 60)] {
      let parsed = parse(text)
      #expect(parsed.recurrence == daily, "\(text): repeat")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.title == "ประชุม", "\(text): title")
    }
  }

  @Test("After midnight: เที่ยงคืน, ตี after a night day, and the 24th hour end the day, so they plan the next one")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("ดูบอลเที่ยงคืน", 1, 0), ("ดูบอล เที่ยงคืน", 1, 0), ("ดูบอลคืนนี้เที่ยงคืน", 1, 0),
      ("ดูบอลพรุ่งนี้เที่ยงคืน", 2, 0), ("ดูบอลเที่ยงคืนวันศุกร์", 4, 0), ("ดูบอลคืนนี้ตีหนึ่ง", 1, 60),
      ("ดูบอลพรุ่งนี้ตีหนึ่ง", 1, 60), ("ดูบอลวันนี้ 24:00 น.", 1, 0), ("ดูบอลคืนนี้ 0.30 น.", 1, 30),
      ("ดูบอลคืนนี้ 00:30 น.", 1, 30), ("ดูบอลค่ำนี้ตีสอง", 1, 120),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "ดูบอล", "\(line): title")
    }
    let alone = parse("ประชุม 24 น.")
    #expect(alone.plannedDayOffset == 1)
    #expect(alone.startMinutes == 0)
    // An hour at night with no night day is the small hours of the day itself.
    let small = parse("ดูบอลตีหนึ่ง")
    #expect(small.plannedDayOffset == nil)
    #expect(small.startMinutes == 60)
    // The evening hours of the same night are still the day itself.
    for (line, minutes) in [("ดูบอลคืนนี้สองทุ่ม", 20 * 60), ("ดูบอลวันนี้ห้าทุ่ม", 23 * 60), ("ดูบอลคืนนี้ 23:30 น.", 23 * 60 + 30)] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == 0, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
    }
    // An hour no unit carries, a minute past the hour, and an hour past 24 are no time.
    expectLinesUnread(
      [
        "ประชุมสองโมงเช้า", "ประชุมตีหก", "ประชุมหกทุ่ม", "ประชุม 25 น.", "ประชุม 9:75 น.", "ประชุม 25:00 น.",
        "ประชุม 24:30 น.", "ประชุมตี 0", "ประชุมสิบสามโมง", "ประชุม 13 โมง",
      ], languages: ["th"])
  }

  @Test("A bare hour needs its unit, and a number before a counted noun is no time")
  func bareNumbers() {
    expectLinesUnread(
      [
        "ประชุม 5", "ประชุม 15", "ตี 3 ชั้น", "บ่าย 2 คน", "ห้อง 3 ชั้น", "ประชุม 3 คน", "ซื้อไข่ 3 ฟอง",
        "ประชุม 3 ครั้ง", "ประชุมตี 3 ข้อ", "ตั้งนาฬิกาปลุก", "ประชุมทุ่มเท", "ประชุมสองทุ่มเท", "ประชุมบ่าย 3 คน",
      ], languages: ["th"])
    // A word that follows a time leaves it a time, and the rest of the line stays.
    let with = parse("ประชุม 7 โมงกับลูกค้า")
    #expect(with.startMinutes == 7 * 60)
    #expect(with.title == "ประชุม กับลูกค้า")
    // The clock of an alarm is no unit, and the alarm's hour reads.
    let alarm = parse("ตั้งนาฬิกาปลุก 7 โมง")
    #expect(alarm.startMinutes == 7 * 60)
    #expect(alarm.title == "ตั้งนาฬิกาปลุก")
    let alarm24 = parse("ตั้งนาฬิกาปลุก 6 นาฬิกา")
    #expect(alarm24.startMinutes == 6 * 60)
    // A time that reads as a date, or as a price, is no time.
    #expect(parse("ราคา 10.30 บาท").startMinutes == nil)
    #expect(parse("ราคา 10.30 บาท").title == "ราคา 10.30 บาท")
  }

  @Test("Time ranges: a dash, ถึง, ตั้งแต่ with ถึง, a part of the day, and the unit on one side")
  func timeRanges() {
    for (text, start, length) in [
      ("ประชุม 10:00-11:00 น.", 10 * 60, 60), ("ประชุม 10:00 - 11:00 น.", 10 * 60, 60),
      ("ประชุม 9:00-10:30 น.", 9 * 60, 90), ("ประชุม 9.00–10.30 น.", 9 * 60, 90),
      ("ประชุม 13.00 – 14.30 น.", 13 * 60, 90), ("ประชุม 9.30 น. ถึง 11.00 น.", 9 * 60 + 30, 90),
      ("ประชุม 10:00 ถึง 11:00 น.", 10 * 60, 60), ("ประชุมตั้งแต่ 10:00 ถึง 11:00 น.", 10 * 60, 60),
      ("ประชุมตั้งแต่ 10:00-11:00 น.", 10 * 60, 60), ("ประชุมเวลา 10:00-11:00 น.", 10 * 60, 60),
      ("ประชุม 9-11 น.", 9 * 60, 120), ("ประชุม 14-16 น.", 14 * 60, 120), ("ประชุม ๙:๐๐-๑๐:๓๐ น.", 9 * 60, 90),
      ("ประชุม 9-11 โมงเช้า", 9 * 60, 120), ("ประชุม 9 โมง-11 โมง", 9 * 60, 120),
      ("ประชุม 9 โมงถึง 11 โมง", 9 * 60, 120), ("ประชุมบ่ายสองถึงสี่โมง", 14 * 60, 120),
      ("ประชุมบ่ายสองถึงบ่ายสี่", 14 * 60, 120), ("ประชุมบ่ายโมงถึงบ่ายสองโมง", 13 * 60, 60),
      ("ประชุมจาก 9 โมง ถึง เที่ยง", 9 * 60, 180), ("ประชุมสองโมงถึงสี่โมงเย็น", 14 * 60, 120),
      ("ประชุมตีหนึ่งถึงตีสอง", 60, 60), ("ประชุม 9am-10am", 9 * 60, 60),
    ] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == start, "\(text): start")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == "ประชุม", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A time range names its length unless the line names one.
    let named = parse("ประชุม 14-16 น. ใช้เวลา 30 นาที")
    #expect(named.startMinutes == 14 * 60)
    #expect(named.estimatedMinutes == 30)
    let repeated = parse("ประชุมทีมทุกวันจันทร์ 9:00-10:00 น. 1 ชั่วโมง")
    #expect(repeated.startMinutes == 9 * 60)
    #expect(repeated.estimatedMinutes == 60)
    #expect(repeated.recurrence == monday)
    // Two bare hours with no unit, part of the day, or minutes are as often an amount or numbered items.
    expectLinesUnread(["ประชุม 14-16", "ประชุม 3-5", "ประชุม 2 ถึง 4", "อ่านหน้า 14-16"], languages: ["th"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words, with or without an opener")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("อ่านหนังสือ 30 นาที", 30), ("อ่านหนังสือ 45 นาที", 45), ("อ่านหนังสือ 90 นาที", 90),
      ("อ่านหนังสือ 1 ชั่วโมง", 60), ("อ่านหนังสือ 2 ชั่วโมง", 120), ("อ่านหนังสือ 24 ชั่วโมง", 24 * 60),
      ("อ่านหนังสือ 1 ชม.", 60), ("อ่านหนังสือ 1 ชม", 60), ("อ่านหนังสือ 2 ชม.", 120),
      ("อ่านหนังสือ 1.5 ชั่วโมง", 90), ("อ่านหนังสือ 0.5 ชั่วโมง", 30),
      ("อ่านหนังสือครึ่งชั่วโมง", 30), ("อ่านหนังสือครึ่ง ชม.", 30), ("อ่านหนังสือ ครึ่งชั่วโมง", 30),
      ("อ่านหนังสือชั่วโมงครึ่ง", 90), ("อ่านหนังสือ 1 ชั่วโมงครึ่ง", 90), ("อ่านหนังสือ 2 ชั่วโมงครึ่ง", 150),
      ("อ่านหนังสือ 2 ชั่วโมง 30 นาที", 150), ("อ่านหนังสือ 2 ชม. 30 นาที", 150),
      ("อ่านหนังสือ 1 ชั่วโมงและ 15 นาที", 75),
      ("อ่านหนังสือหนึ่งชั่วโมง", 60), ("อ่านหนังสือชั่วโมงนึง", 60), ("อ่านหนังสือสองชั่วโมง", 120),
      ("อ่านหนังสือสิบห้านาที", 15), ("อ่านหนังสือยี่สิบนาที", 20), ("อ่านหนังสือสามสิบนาที", 30),
      ("อ่านหนังสือห้านาที", 5), ("อ่านหนังสือสี่สิบห้านาที", 45), ("อ่านหนังสือ ๓๐ นาที", 30),
      ("อ่านหนังสือใช้เวลา 2 ชั่วโมง", 120), ("อ่านหนังสือระยะเวลา 30 นาที", 30), ("อ่านหนังสือนาน 45 นาที", 45),
      ("อ่านหนังสือประมาณ 20 นาที", 20), ("อ่านหนังสือประมาณ 2 ชั่วโมง", 120),
      ("อ่านหนังสือ 20 นาทีโดยประมาณ", 20), ("อ่านหนังสือใช้เวลาประมาณ 2 ชั่วโมง", 120),
      ("อ่านหนังสือ 2h", 120), ("อ่านหนังสือ 20 min", 20),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "อ่านหนังสือ", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A length before the rest of the line, a length with a day, and a length with a time.
    let opening = parse("30 นาที อ่านหนังสือ")
    #expect(opening.estimatedMinutes == 30)
    #expect(opening.title == "อ่านหนังสือ")
    let day = parse("อ่านหนังสือ 20 นาที พรุ่งนี้")
    #expect(day.estimatedMinutes == 20)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "อ่านหนังสือ")
    let time = parse("อ่านหนังสือ 30 นาที 15:00 น.")
    #expect(time.estimatedMinutes == 30)
    #expect(time.startMinutes == 15 * 60)
    // A length after a time reads when it counts hours or has an opener, and a time followed by an amount of
    // minutes is that time and its minutes.
    for (text, start, length) in [
      ("ประชุมบ่ายสามโมง 2 ชั่วโมง", 15 * 60, 120), ("ประชุมบ่ายสามโมง ครึ่งชั่วโมง", 15 * 60, 30),
      ("ประชุมสามโมงครึ่ง 2 ชั่วโมง", 15 * 60 + 30, 120), ("ประชุมสามโมงครึ่ง ครึ่งชั่วโมง", 15 * 60 + 30, 30),
      ("ประชุมบ่ายสามโมง ใช้เวลา 30 นาที", 15 * 60, 30), ("ประชุมตีสอง 2 ชั่วโมง", 2 * 60, 120),
    ] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == start, "\(text): time")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == "ประชุม", "\(text): title")
    }
    let minutes = parse("ประชุมบ่ายสามโมง 30 นาที")
    #expect(minutes.startMinutes == 15 * 60 + 30)
    #expect(minutes.estimatedMinutes == nil)
  }

  @Test("An amount of time that names a moment, a bound, the past, or a rate, a size, and a single minute are no length")
  func notLengths() {
    expectLinesUnread(
      [
        "อ่านหนังสืออีก 30 นาที", "อ่านหนังสือทุก 30 นาที", "อ่านหนังสือทุกๆ 30 นาที", "อ่านหนังสือภายใน 2 ชั่วโมง",
        "อ่านหนังสือหลัง 2 ชั่วโมง", "อ่านหนังสืออย่างน้อย 2 ชั่วโมง", "อ่านหนังสือไม่เกิน 2 ชั่วโมง",
        "อ่านหนังสือผ่านไป 10 นาที", "อ่านหนังสือ 30 นาทีที่แล้ว", "อ่านหนังสือ 30 นาทีก่อน",
        "อ่านหนังสือ 2 ชั่วโมงต่อวัน", "อ่านหนังสือ 2 ชั่วโมงกว่า", "อ่านหนังสือ 2-3 ชั่วโมง",
        "อ่านหนังสือสองถึงสามชั่วโมง", "อ่านหนังสือ 2 หรือ 3 ชั่วโมง", "อ่านหนังสือ 25 ชั่วโมง",
        "อ่านหนังสือ 0 นาที", "อ่านหนังสือหนึ่งนาที", "อ่านหนังสือวันละ 30 นาที", "อ่านหนังสือวันละ 2 ชั่วโมง",
        "อ่านหนังสือสัปดาห์ละ 3 ชั่วโมง", "อ่านหนังสือ 10 ชั่วโมงต่อสัปดาห์", "อ่านวันละ 10 หน้า",
        "ซื้อไข่ 30 ฟอง", "อ่านหนังสือชม", "ไปชมดอกไม้",
      ], languages: ["th"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, every other and every nth, and the cadence words")
  func repeats() {
    let rules: [(text: String, rule: TaskRecurrenceRule)] = [
      ("ออกกำลังกายทุกวัน", daily), ("ออกกำลังกายทุกสัปดาห์", weekly), ("ออกกำลังกายทุกอาทิตย์", weekly),
      ("ออกกำลังกายทุกเดือน", monthly), ("ออกกำลังกายทุกปี", yearly), ("ออกกำลังกายทุกเช้า", daily),
      ("ออกกำลังกายทุกบ่าย", daily), ("ออกกำลังกายทุกเย็น", daily), ("ออกกำลังกายทุกคืน", daily),
      ("ออกกำลังกายทุกๆ วัน", daily), ("ออกกำลังกาย ทุกวัน", daily), ("ออกกำลังกาย ทุก วัน", daily),
      ("ออกกำลังกายทุก 2 วัน", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ออกกำลังกายทุกสองวัน", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ออกกำลังกายทุกๆ 2 วัน", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ออกกำลังกายทุก ๒ วัน", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ออกกำลังกายทุก 3 วัน", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("ออกกำลังกายทุก 2 สัปดาห์", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ออกกำลังกายทุกสองสัปดาห์", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ออกกำลังกายทุก 3 สัปดาห์", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("ออกกำลังกายทุก 2 เดือน", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("ออกกำลังกายทุกสามเดือน", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ออกกำลังกายทุก 6 เดือน", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("ออกกำลังกายทุก 2 ปี", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("ออกกำลังกายทุกไตรมาส", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ออกกำลังกายทุกครึ่งปี", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("ออกกำลังกายวันเว้นวัน", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ออกกำลังกายสัปดาห์เว้นสัปดาห์", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ออกกำลังกายเดือนเว้นเดือน", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("ออกกำลังกายปีเว้นปี", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      // Whole weeks counted in days are a weekly repeat.
      ("ออกกำลังกายทุก 7 วัน", weekly), ("ออกกำลังกายทุก 14 วัน", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ออกกำลังกายวันละครั้ง", daily), ("ออกกำลังกายสัปดาห์ละครั้ง", weekly), ("ออกกำลังกายเดือนละครั้ง", monthly),
      ("ออกกำลังกายปีละครั้ง", yearly),
    ]
    for line in rules {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "ออกกำลังกาย", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The title keeps the text around the phrase.
    let opening = parse("ทุกวัน ออกกำลังกาย")
    #expect(opening.recurrence == daily)
    #expect(opening.title == "ออกกำลังกาย")
    // "ทุก" before a unit that is no repeat, and the other words that begin with these.
    expectLinesUnread(
      [
        "ประชุมทุกวันหยุด", "ประชุมทุกวันเกิด", "ประชุมทุกวันนี้", "ประชุมสัปดาห์ละ 2 ครั้ง", "บรรทุกของ",
        "ประชุมทุกวันพุธที่สองของเดือน", "ประชุมทุกวันศุกร์สุดท้ายของเดือน", "ประชุมทุกวันจันทร์แรกของเดือน",
        "ประชุมสัปดาห์ละ 3 วัน", "ทุกข์ใจ",
      ], languages: ["th"])
  }

  @Test("Weekday repeats: ทุกวันจันทร์, a list or a span of weekdays, the working days, and the weekend")
  func weekdayRepeats() {
    let rules: [(text: String, rule: TaskRecurrenceRule)] = [
      ("ประชุมทุกวันจันทร์", monday), ("ประชุมทุกจันทร์", monday), ("ประชุมทุกๆ วันจันทร์", monday),
      ("ประชุมทุกวันอังคาร", TaskRecurrenceRule(freq: .weekly, byDay: ["TU"])),
      ("ประชุมทุกวันพุธ", TaskRecurrenceRule(freq: .weekly, byDay: ["WE"])),
      ("ประชุมทุกวันพฤหัสบดี", TaskRecurrenceRule(freq: .weekly, byDay: ["TH"])),
      ("ประชุมทุกวันพฤหัส", TaskRecurrenceRule(freq: .weekly, byDay: ["TH"])),
      ("ประชุมทุกวันศุกร์", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("ประชุมทุกวันเสาร์", TaskRecurrenceRule(freq: .weekly, byDay: ["SA"])),
      ("ประชุมทุกวันอาทิตย์", TaskRecurrenceRule(freq: .weekly, byDay: ["SU"])),
      ("ประชุมทุกสัปดาห์วันศุกร์", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("ประชุมทุกอาทิตย์วันพุธ", TaskRecurrenceRule(freq: .weekly, byDay: ["WE"])),
      ("ประชุมทุกวันจันทร์และวันพุธ", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE"])),
      ("ประชุมทุกจันทร์ พุธ ศุกร์", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"])),
      ("ประชุมทุกวันจันทร์ พุธ และศุกร์", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"])),
      ("ประชุมทุก 2 สัปดาห์วันศุกร์", TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR"])),
      // The working days, a span of days, and the weekend.
      ("ประชุมทุกวันทำงาน", workdays), ("ประชุมทุกวันทำการ", workdays), ("ประชุมทุกวันจันทร์ถึงวันศุกร์", workdays),
      ("ประชุมทุกจันทร์-ศุกร์", workdays), ("ประชุมทุกวันจันทร์ถึงวันพฤหัส", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH"])),
      ("ประชุมทุกวันศุกร์ถึงวันจันทร์", TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "FR", "SA"])),
      ("ประชุมทุกสุดสัปดาห์", weekend), ("ประชุมทุกวันสุดสัปดาห์", weekend), ("ประชุมทุกเสาร์อาทิตย์", weekend),
      ("ประชุมทุกวันเสาร์และวันอาทิตย์", weekend),
    ]
    for line in rules {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "ประชุม", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The repeat starts on its first weekday: today is Tuesday.
    #expect(parse("ประชุมทุกวันจันทร์").recurrenceStartOffset == 6)
    #expect(parse("ประชุมทุกวันศุกร์").recurrenceStartOffset == 3)
    // The weekend starts on the first Saturday or Sunday after today, and the working days today.
    #expect(parse("ประชุมทุกสุดสัปดาห์").recurrenceStartOffset == 4)
    #expect(parse("ประชุมทุกวันทำงาน").recurrenceStartOffset == 0)
    // A single weekday alone is a day, and with "ทุก" a repeat.
    #expect(parse("ประชุมวันศุกร์").recurrence == nil)
    #expect(parse("ประชุมวันศุกร์").plannedDayOffset == 3)
    // A weekday repeat with a time.
    let timed = parse("ประชุมทุกวันจันทร์ 9 โมงเช้า")
    #expect(timed.recurrence == monday)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "ประชุม")
    let range = parse("ประชุมทีมทุกวันจันทร์ 9:00-10:00 น.")
    #expect(range.recurrence == monday)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "ประชุมทีม")
  }

  @Test("A day of the month repeats every month")
  func monthDayRepeats() {
    for (text, day) in [
      ("จ่ายค่าเช่าทุกวันที่ 15", 15), ("จ่ายค่าเช่าทุกเดือนวันที่ 15", 15), ("จ่ายค่าเช่าทุกวันที่ 15 ของเดือน", 15),
      ("จ่ายค่าเช่าวันที่ 15 ของทุกเดือน", 15), ("จ่ายค่าเช่าวันที่ 15 ของเดือน", 15), ("จ่ายค่าเช่าทุกวันที่ ๑๕", 15),
      ("จ่ายค่าเช่าทุกเดือนวันที่ 1", 1), ("จ่ายค่าเช่าทุกวันที่ 30", 30),
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [day]), "\(text)")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == "จ่ายค่าเช่า", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A time after the day is a time.
    let timed = parse("จ่ายค่าเช่าทุกเดือน 15:30 น.")
    #expect(timed.recurrence == monthly)
    #expect(timed.startMinutes == 15 * 60 + 30)
    let afternoon = parse("จ่ายค่าเช่าทุกเดือนบ่ายสามโมง")
    #expect(afternoon.recurrence == monthly)
    #expect(afternoon.startMinutes == 15 * 60)
    // A time written after the day number is no day of the month.
    #expect(parse("จ่ายค่าเช่าทุกวันที่ 15:30").recurrence != TaskRecurrenceRule(freq: .monthly, byMonthDay: [15]))
  }

  @Test("A part of the day after ทุก is a daily repeat, and the hour after it is its time")
  func partOfTheDayRepeats() {
    for (text, minutes) in [
      ("ประชุมทุกเย็น 7 โมง", 19 * 60), ("ประชุมทุกวัน 6 โมงเช้า", 6 * 60), ("ประชุมทุกเช้า 7 โมง", 7 * 60),
      ("ประชุมทุกวันจันทร์ 9 โมงเช้า", 9 * 60),
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence != nil, "\(text): repeat")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.title == "ประชุม", "\(text): title")
    }
    // "ทุกเย็น" is no part of a longer word.
    expectLinesUnread(["ประชุมทุกเย็นย่ำ", "ประชุมทุกเช้ามืด"], languages: ["th"])
  }

  // MARK: - Priorities

  @Test("Priorities: ด่วน, ด่วนมาก, เร่งด่วน, สำคัญ, สำคัญมาก, ไม่ด่วน, and a written priority")
  func priorities() {
    for (text, title, priority) in [
      ("ส่งรายงาน ด่วน", "ส่งรายงาน", LorvexTask.Priority.p1),
      ("ส่งรายงาน ด่วน.", "ส่งรายงาน.", .p1), ("ส่งรายงาน ด่วนๆ", "ส่งรายงาน", .p1),
      ("ส่งรายงาน ด่วนมาก", "ส่งรายงาน", .p1), ("ส่งรายงานด่วนมาก", "ส่งรายงาน", .p1),
      ("ส่งรายงานด่วนมากๆ", "ส่งรายงาน", .p1), ("ส่งรายงานด่วนที่สุด", "ส่งรายงาน", .p1),
      ("ส่งรายงานเร่งด่วน", "ส่งรายงาน", .p1), ("ส่งรายงานเร่งด่วนมาก", "ส่งรายงาน", .p1),
      ("ส่งรายงาน สำคัญ", "ส่งรายงาน", .p1), ("ส่งรายงาน สำคัญมาก", "ส่งรายงาน", .p1),
      ("ส่งรายงานสำคัญมาก", "ส่งรายงาน", .p1), ("ส่งรายงานสำคัญมากๆ", "ส่งรายงาน", .p1),
      ("ส่งรายงานสำคัญที่สุด", "ส่งรายงาน", .p1), ("ด่วน ส่งรายงาน", "ส่งรายงาน", .p1),
      ("ด่วน! ส่งรายงาน", "ส่งรายงาน", .p1), ("ด่วน: ส่งรายงาน", "ส่งรายงาน", .p1),
      ("ส่งรายงาน ไม่ด่วน", "ส่งรายงาน", .p3), ("ส่งรายงานไม่ด่วน", "ส่งรายงาน", .p3),
      ("ส่งรายงานไม่เร่งด่วน", "ส่งรายงาน", .p3), ("ส่งรายงานไม่สำคัญ", "ส่งรายงาน", .p3),
      ("ส่งรายงานไม่ด่วนมาก", "ส่งรายงาน", .p3), ("ส่งรายงานไม่ค่อยสำคัญ", "ส่งรายงาน", .p3),
      ("ส่งรายงานไม่ได้ด่วน", "ส่งรายงาน", .p3),
      ("ส่งรายงานความสำคัญสูง", "ส่งรายงาน", .p1), ("ส่งรายงานความสำคัญสูงที่สุด", "ส่งรายงาน", .p1),
      ("ส่งรายงานความสำคัญปานกลาง", "ส่งรายงาน", .p2), ("ส่งรายงานความสำคัญต่ำ", "ส่งรายงาน", .p3),
      ("ส่งรายงานความสำคัญน้อยที่สุด", "ส่งรายงาน", .p3), ("ส่งรายงานลำดับความสำคัญ: สูง", "ส่งรายงาน", .p1),
      ("ส่งรายงานลำดับความสำคัญ: ต่ำ", "ส่งรายงาน", .p3), ("ส่งรายงานความสำคัญ 1", "ส่งรายงาน", .p1),
      ("ส่งรายงานความสำคัญ 2", "ส่งรายงาน", .p2), ("ส่งรายงานความสำคัญ 3", "ส่งรายงาน", .p3),
      ("ส่งรายงานลำดับความสำคัญที่ 1", "ส่งรายงาน", .p1), ("ส่งรายงานความสำคัญ ๑", "ส่งรายงาน", .p1),
      ("ส่งรายงานความสำคัญ ๒", "ส่งรายงาน", .p2), ("ส่งรายงานลำดับความสำคัญที่ ๓", "ส่งรายงาน", .p3),
    ] {
      let parsed = parse(text)
      #expect(parsed.priority == priority, "\(text)")
      #expect(parsed.title == title, "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A priority word glued before another detail word still reads.
    for text in ["ส่งรายงานด่วนมากพรุ่งนี้", "ส่งรายงานเร่งด่วนพรุ่งนี้"] {
      let parsed = parse(text)
      #expect(parsed.priority == .p1, "\(text)")
      #expect(parsed.plannedDayOffset == 1, "\(text): planned day")
      #expect(parsed.title == "ส่งรายงาน", "\(text): title")
    }
    // A polite particle after the word stays in the title.
    let polite = parse("ส่งรายงานด่วนมากครับ")
    #expect(polite.priority == .p1)
    #expect(polite.title == "ส่งรายงาน ครับ")
    // "ด่วน" and "สำคัญ" glued to another word belong to a compound, and a priority word that goes on into a
    // comparison names no priority.
    expectLinesUnread(
      [
        "ส่งรายงานทางด่วน", "ขึ้นรถด่วน", "ส่งเอกสารสำคัญ", "ส่งรายงานด่วนๆ", "ทางด่วน", "รถด่วนขบวนสุดท้าย",
        "ส่งรายงานสำคัญมากกว่า", "ส่งรายงานไม่สำคัญเท่า", "ส่งรายงานด่วนมากกว่า", "ส่งรายงานเร่งด่วนกว่า",
        "ส่งรายงานความสำคัญ 12", "ส่งรายงานความสำคัญสูงกว่า", "ส่งรายงานด่วนพิเศษ", "ส่งรายงานสำคัญต่อ",
      ], languages: ["th"])
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyKindAtOnce() {
    let line = parse("จองตั๋วเครื่องบิน 15 ต.ค. ภายในวันศุกร์ ด่วนมาก 30 นาที")
    #expect(line.plannedDayOffset == 23)
    #expect(line.dueDayOffset == 3)
    #expect(line.estimatedMinutes == 30)
    #expect(line.priority == .p1)
    #expect(line.title == "จองตั๋วเครื่องบิน")
    let call = parse("โทรหาหมอวันจันทร์ 10:00 น. ด่วน")
    #expect(call.plannedDayOffset == 6)
    #expect(call.startMinutes == 10 * 60)
    #expect(call.priority == .p1)
    #expect(call.title == "โทรหาหมอ")
    let weekly = parse("ประชุมทีมวันศุกร์ 7 โมงเย็น 1 ชั่วโมง ทุกสัปดาห์ ความสำคัญสูง")
    #expect(weekly.plannedDayOffset == 3)
    #expect(weekly.startMinutes == 19 * 60)
    #expect(weekly.estimatedMinutes == 60)
    #expect(weekly.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(weekly.priority == .p1)
    #expect(weekly.title == "ประชุมทีม")
    let report = parse("ส่งรายงานให้หัวหน้าภายในวันศุกร์นี้ สำคัญมาก")
    #expect(report.dueDayOffset == 3)
    #expect(report.priority == .p1)
    #expect(report.title == "ส่งรายงานให้หัวหน้า")
    let commas = parse("ส่งรายงาน พรุ่งนี้, 9 น., ด่วน")
    #expect(commas.plannedDayOffset == 1)
    #expect(commas.startMinutes == 9 * 60)
    #expect(commas.priority == .p1)
    #expect(commas.title == "ส่งรายงาน")
    let shopping = parse("ซื้อของใช้ที่ตลาดคืนนี้ 2 ทุ่ม")
    #expect(shopping.plannedDayOffset == 0)
    #expect(shopping.startMinutes == 20 * 60)
    #expect(shopping.title == "ซื้อของใช้ที่ตลาด")
    // The hash words stay as they are read for every language.
    let tagged = parse("ประชุมพรุ่งนี้ #งาน")
    #expect(tagged.plannedDayOffset == 1)
    #expect(tagged.tags == ["งาน"])
    #expect(tagged.title == "ประชุม")
    let first = parse("#งาน ประชุมพรุ่งนี้")
    #expect(first.plannedDayOffset == 1)
    #expect(first.tags == ["งาน"])
    #expect(first.title == "ประชุม")
    let word = parse("ส่งรายงาน #พรุ่งนี้")
    #expect(word.plannedDayOffset == nil)
    #expect(word.tags == ["พรุ่งนี้"])
  }

  @Test("Five details in any order, glued or spaced, read alike")
  func detailsInAnyOrder() {
    // A phrase that opens with a digit keeps a space before it even when the others are glued, since a number
    // written right after a word is no longer a word of its own.
    func line(_ title: String, _ details: [String], glue: String) -> String {
      details.reduce(title) { text, detail in text + (detail.first?.isNumber == true ? " " : glue) + detail }
    }
    let first = ["พรุ่งนี้", "บ่ายสามโมง", "ทุกวันจันทร์", "2 ชั่วโมง", "ด่วนมาก"]
    for glue in [" ", ""] {
      for order in permutations(of: first) {
        let text = line("ประชุมทีม", order, glue: glue)
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == 1, "\(text): planned day")
        #expect(parsed.startMinutes == 15 * 60, "\(text): time")
        #expect(parsed.estimatedMinutes == 120, "\(text): length")
        #expect(parsed.recurrence == monday, "\(text): repeat")
        #expect(parsed.priority == .p1, "\(text): priority")
        #expect(parsed.title == "ประชุมทีม", "\(text): title")
      }
    }
    let second = ["15 ตุลาคม", "15:00 น.", "ทุก 2 วัน", "45 นาที", "ไม่ด่วน"]
    for glue in [" ", ""] {
      for order in permutations(of: second) {
        let text = line("ซื้อของ", order, glue: glue)
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == 23, "\(text): planned day")
        #expect(parsed.startMinutes == 15 * 60, "\(text): time")
        #expect(parsed.estimatedMinutes == 45, "\(text): length")
        #expect(parsed.recurrence == TaskRecurrenceRule(freq: .daily, interval: 2), "\(text): repeat")
        #expect(parsed.priority == .p3, "\(text): priority")
        #expect(parsed.title == "ซื้อของ", "\(text): title")
      }
    }
  }

  @Test("Words that look like details stay in the title")
  func ordinaryWords() {
    expectLinesUnread(
      [
        "ซื้อข้าวเที่ยง", "กินข้าวเที่ยงกับเพื่อน", "พักเที่ยง", "ประชุมใหญ่ประจำปี", "ประชุมประจำสัปดาห์",
        "รายงานประจำเดือน", "รายงานประจำวัน", "งานประจำปี", "ส่งเอกสารสำคัญ", "ทางด่วน", "ขึ้นรถด่วน", "บรรทุกของ",
        "ประชุมทุ่มเท", "งานสามัคคี", "ข้าวเย็น", "ส่งคืน", "เงินคืน", "ประชุมเช้ามืด", "วันเกิดแม่", "วันหยุดยาว",
        "ตะวันตก", "ซื้อผลไม้ 3 กิโล", "ดอกไม้ 15 ดอก", "ห้อง 3 ชั้น", "ซื้อหน้าต่างใหม่", "ชมสวน",
        "ประชุมครั้งที่ 3", "ตอนที่ 5", "เบอร์ 9", "ชั้น 3", "ตี 3 ชั้น",
      ], languages: ["th"])
  }

  @Test("Extra spaces and punctuation between details change nothing")
  func punctuation() {
    let line = parse("ประชุม  พรุ่งนี้,  9 น.")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 9 * 60)
    #expect(parse("ประชุม  พรุ่งนี้  ").plannedDayOffset == 1)
    #expect(parse("พรุ่งนี้, ประชุม").plannedDayOffset == 1)
    #expect(parse("ประชุม (พรุ่งนี้)").plannedDayOffset == 1)
    let exclamation = parse("ประชุมพรุ่งนี้!")
    #expect(exclamation.plannedDayOffset == 1)
    #expect(exclamation.title == "ประชุม!")
    let mark = parse("ประชุมพรุ่งนี้ ๆ")
    #expect(mark.plannedDayOffset == 1)
    #expect(mark.title == "ประชุม ๆ")
  }

  // MARK: - Typing

  @Test("Thai digits and Arabic digits read alike")
  func thaiDigits() {
    let pairs: [(thai: String, arabic: String)] = [
      ("อ่านหนังสือ ๓๐ นาที", "อ่านหนังสือ 30 นาที"), ("ประชุมทุก ๒ วัน", "ประชุมทุก 2 วัน"),
      ("ประชุมวันที่ ๑๕/๑๐", "ประชุมวันที่ 15/10"), ("ประชุม ๙:๐๐-๑๐:๓๐ น.", "ประชุม 9:00-10:30 น."),
      ("ประชุม ๓ โมงครึ่ง", "ประชุม 3 โมงครึ่ง"), ("ประชุม ๑๕ ต.ค. ๒๕๖๙", "ประชุม 15 ต.ค. 2569"),
      ("ประชุมตั้งแต่ ๓ ถึง ๕ พฤษภาคม", "ประชุมตั้งแต่ 3 ถึง 5 พฤษภาคม"), ("ประชุมอีก ๓ วัน", "ประชุมอีก 3 วัน"),
      ("ประชุมตี ๕", "ประชุมตี 5"), ("ประชุม ๑๕.๓๐ น.", "ประชุม 15.30 น."), ("ส่งงานภายใน ๓ วัน", "ส่งงานภายใน 3 วัน"),
      ("จ่ายค่าเช่าทุกวันที่ ๑๕", "จ่ายค่าเช่าทุกวันที่ 15"), ("ส่งรายงานความสำคัญ ๒", "ส่งรายงานความสำคัญ 2"),
    ]
    for pair in pairs {
      let thai = parse(pair.thai)
      let arabic = parse(pair.arabic)
      #expect(thai.plannedDayOffset == arabic.plannedDayOffset, "\(pair.thai): planned day")
      #expect(thai.dueDayOffset == arabic.dueDayOffset, "\(pair.thai): due day")
      #expect(thai.startMinutes == arabic.startMinutes, "\(pair.thai): time")
      #expect(thai.estimatedMinutes == arabic.estimatedMinutes, "\(pair.thai): length")
      #expect(thai.recurrence == arabic.recurrence, "\(pair.thai): repeat")
      #expect(thai.priority == arabic.priority, "\(pair.thai): priority")
      #expect(thai.phrases.count == arabic.phrases.count, "\(pair.thai): phrases")
      #expect(!thai.phrases.isEmpty, "\(pair.thai): read")
    }
  }

  @Test("A sara am typed as nikhahit and sara aa reads like the single letter, and the title keeps what was typed")
  func saraAm() {
    let typed = "สํา"
    #expect(scalars(typed) == [Unicode.Scalar(0x0E2A)!, Unicode.Scalar(0x0E4D)!, Unicode.Scalar(0x0E32)!])
    for (text, check) in [
      ("ส่งรายงาน สําคัญ", { (parsed: LorvexCaptureParse) in parsed.priority == .p1 }),
      ("ส่งรายงานสําคัญมาก", { $0.priority == .p1 }),
      ("ส่งรายงานความสําคัญสูง", { $0.priority == .p1 }),
      ("ส่งรายงานทุกวันทําการ", { $0.recurrence == workdays }),
      ("ส่งรายงานภายในสัปดาห์หน้า".replacingOccurrences(of: "ำ", with: "ํา"), { $0.dueDayOffset == 7 }),
    ] {
      let parsed = parse(text)
      #expect(check(parsed), "\(text)")
      #expect(scalars(parsed.title).starts(with: scalars("ส่งรายงาน")), "\(text): title")
    }
  }

  @Test("A priority and a day glued to a title that holds ำ keep the title's letters")
  func titleKeepsItsLetters() {
    let parsed = parse("ทำความสะอาดพรุ่งนี้ ด่วนมาก")
    #expect(parsed.plannedDayOffset == 1)
    #expect(parsed.priority == .p1)
    #expect(scalars(parsed.title) == scalars("ทำความสะอาด"))
  }

  @Test("Every rule pattern compiles and spells a word with its vowel sign before its tone mark")
  func patternsAreWellFormed() {
    LorvexCaptureParser.warmUp(languages: ["th"])
    let vocabulary = LorvexCaptureVocabulary.thai
    var patterns: [String] = []
    patterns += vocabulary.priority.map(\.pattern)
    patterns += vocabulary.dateRange.map(\.pattern)
    patterns += vocabulary.keptInTitle.map(\.pattern)
    patterns += vocabulary.length.map(\.pattern)
    patterns += vocabulary.time.map(\.pattern)
    patterns += vocabulary.repeats.map(\.pattern)
    patterns += vocabulary.due.map(\.pattern)
    patterns += vocabulary.when.map(\.pattern)
    #expect(patterns.count > 20)
    // A tone mark (่ ้ ๊ ๋) comes after the vowel sign above or below its consonant (ั ิ ี ึ ื ุ ู ็), the order a
    // keyboard types them in.
    let toneMarks: ClosedRange<UInt32> = 0x0E48...0x0E4B
    let vowelSigns: Set<UInt32> = [0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E38, 0x0E39, 0x0E3A, 0x0E47]
    for pattern in patterns {
      #expect(LorvexCapturePatterns.isCompiled(pattern), "\(pattern.prefix(60))")
      let marks = pattern.unicodeScalars.map(\.value)
      for (index, mark) in marks.enumerated() where toneMarks.contains(mark) && index + 1 < marks.count {
        #expect(!vowelSigns.contains(marks[index + 1]), "A tone mark comes before a vowel sign in: \(pattern.prefix(60))")
      }
    }
  }

  @Test("The number pattern matches every spelled number from 1 to 99 whole, and no pair of words as one number")
  func spelledNumbers() throws {
    let words = LorvexCaptureVocabulary.thaiSpelledNumberWords
    #expect(Set(words.compactMap(LorvexCaptureVocabulary.thaiCount)) == Set(1...99))
    let pattern = try NSRegularExpression(pattern: "^(?:\(LorvexCaptureVocabulary.thaiNumberWords))$")
    for word in words {
      let range = NSRange(word.startIndex..., in: word)
      #expect(pattern.firstMatch(in: word, range: range) != nil, "\(word)")
    }
    // "ห้า" in "สิบห้า" is the ones digit of fifteen, and "สามสิบ" is thirty and no three before ten.
    for (word, value) in [("สิบห้า", 15), ("สามสิบ", 30), ("ยี่สิบเอ็ด", 21), ("สิบเอ็ด", 11), ("เก้าสิบเก้า", 99)] {
      #expect(LorvexCaptureVocabulary.thaiCount(word) == value, "\(word)")
    }
    let fifteen = parse("อ่านหนังสือสิบห้านาที")
    #expect(fifteen.estimatedMinutes == 15)
    #expect(fifteen.title == "อ่านหนังสือ")
    let thirty = parse("อ่านหนังสือสามสิบนาที")
    #expect(thirty.estimatedMinutes == 30)
    #expect(thirty.title == "อ่านหนังสือ")
  }

  // MARK: - Beside other languages

  @Test("Beside Thai, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Thai beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Meet at 15h",
      "Meet 10h", "Call her day after tomorrow", "Ask her morning", "Turn on 5 lights", "Mail 3 Mar", "Call in 15 min",
      "Due Friday report", "Report due 15 Oct", "Deadline tomorrow", "Priority high", "Urgent: call bank",
      "Sat at 5pm", "Tue 3 Mar", "Mon-Fri workout", "Wed meeting", "Fri 15:00",
    ] {
      for languages in [["en", "th"], ["th", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Thai writes its hours with โมง, ทุ่ม, ตี, or น., so "15h" and "2h" are lengths beside it.
    let hours = parse("Write the report 2h", languages: ["en", "th"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "th"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    #expect(parse("ประชุม 2h").estimatedMinutes == 120)
    // A line may mix both languages.
    let mixed = parse("Call mom พรุ่งนี้ at 3pm", languages: ["en", "th"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting วันศุกร์ at 3pm", languages: ["en", "th"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Dentist พรุ่งนี้", languages: ["en", "th"]).plannedDayOffset == 1)
    let review = parse("Review พรุ่งนี้ 15:00 น. for 2 hours", languages: ["en", "th"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    // The same words in either order of 3pm and a Thai day.
    for text in ["ประชุมพรุ่งนี้ 3pm", "3pm ประชุมพรุ่งนี้", "ประชุม 3pm พรุ่งนี้", "ประชุมพรุ่งนี้ at 3pm"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text): planned day")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "ประชุม", "\(text): title")
    }
    #expect(parse("ประชุม 30 min").estimatedMinutes == 30)
    #expect(parse("ประชุม tomorrow").plannedDayOffset == 1)
    #expect(parse("ประชุม every Monday").recurrence == monday)
    #expect(parse("ประชุม by friday").dueDayOffset == 3)
    #expect(parse("Buy milk ทุกวัน").recurrence == daily)
  }

  @Test("Lines in other languages read the same with Thai beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"), ("تقرير قبل الخميس", "ar"),
      ("مراجعة من 3 إلى 5 مارس", "ar"), ("تماس با مادر فردا ساعت ۳ بعدازظهر", "fa"), ("ورزش هر دوشنبه", "fa"),
      ("گزارش تا جمعه", "fa"), ("امی کو فون کرنا کل شام 5 بجے", "ur"), ("رپورٹ جمعہ تک", "ur"),
      ("कल शाम 5 बजे मीटिंग", "hi"), ("रिपोर्ट सोमवार तक", "hi"), ("हर सोमवार योग 30 मिनट", "hi"),
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
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "th"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["th", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Thai with another language, in either order of the languages.
    for languages in [["zh", "th"], ["th", "zh"]] {
      let mixed = parse("ประชุมพรุ่งนี้ 下午3点", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "ประชุม", "\(languages)")
    }
    for languages in [["fr", "th"], ["th", "fr"]] {
      let mixed = parse("Appeler maman พรุ่งนี้ 15:00 น.", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("ประชุมทุกวันจันทร์", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
      expectDateRanges(
        [
          ("Vacances", "du 3 au 5 mai", "2027-05-03", "2027-05-05"),
          ("ลาพักร้อน", "3-5 พฤษภาคม", "2027-05-03", "2027-05-05"),
        ], languages: languages)
    }
    // The languages that go beside Thai keep their own words, which are Thai's too only in a different script.
    for languages in [["el", "th"], ["th", "el"], ["tr", "th"], ["th", "tr"], ["de", "th"], ["th", "de"]] {
      #expect(parse("ประชุมพรุ่งนี้บ่ายสามโมง", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("ประชุมทุกวันจันทร์", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == (languages.contains("de") ? 2 : nil), "\(languages)")
      #expect(parse("Diş doktoru yarın", languages: languages).plannedDayOffset == (languages.contains("tr") ? 1 : nil), "\(languages)")
      #expect(parse("Αναφορά αύριο", languages: languages).plannedDayOffset == (languages.contains("el") ? 1 : nil), "\(languages)")
    }
  }

  @Test("Thai words are read only for a user who reads Thai")
  func languageGate() {
    let line = parse("ประชุมพรุ่งนี้", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "ประชุมพรุ่งนี้")
    for languages in [["th"], ["th-TH"], ["th_TH"], ["en-US", "th-TH"], ["TH"], ["th-u-nu-thai"]] {
      #expect(parse("ประชุมพรุ่งนี้", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Thai reader.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen", "Dentist poimâine", "Rapat besok", "Diş doktoru yarın",
      ], languages: ["th"])
    // Thai words are not read for a reader of another language.
    for languages in [
      ["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"], ["tr"],
      ["el"], ["ar"], ["hi"],
    ] {
      let parsed = parse("ประชุมพรุ่งนี้", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "ประชุมพรุ่งนี้", "\(languages): title")
      #expect(parse("ประชุมบ่ายสามโมง", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("ประชุมทุกวันจันทร์", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["th"])
    let unit: [String] = [
      "บ่ายสามโมง ", "สามโมง ", "โมง ", "3 ", "พรุ่งนี้ ", "พรุ่งนี้เช้า ", "วันศุกร์ ", "วันศุกร์หน้า ", "ศุกร์หน้า ",
      "วันจันทร์ ", "วันอังคาร ", "15 ตุลาคม ", "15 ต.ค. ", "15/10/2569 ", "15/10 ", "3-5 พฤษภาคม ",
      "ตั้งแต่ 3 ถึง 5 พฤษภาคม ", "ภายในวันศุกร์ ", "ภายใน ", "ก่อน ", "ก่อน 5 โมงเย็น ", "เดดไลน์ ", "ทุกวัน ",
      "ทุกวันจันทร์ ", "ทุกวันจันทร์และวันพุธ ", "ทุก 2 สัปดาห์ ", "ทุกวันทำงาน ", "ทุกเดือนวันที่ 15 ", "วันที่ 15 ",
      "วันที่ ", "สามโมงครึ่ง ", "บ่ายสามครึ่ง ", "ตีหนึ่ง ", "สองทุ่ม ", "เที่ยงคืน ", "เที่ยง ", "15:00 น. ", "15.30 น. ",
      "10:00-11:00 น. ", "บ่ายสองถึงสี่โมง ", "9-11 โมงเช้า ", "30 นาที ", "1 ชั่วโมงครึ่ง ", "ครึ่งชั่วโมง ",
      "สามสิบนาที ", "ใช้เวลา ", "ด่วนมาก ", "ด่วน ", "สำคัญ ", "ไม่ด่วน ", "ความสำคัญสูง ", "ความสำคัญ ", "เมื่อวาน ",
      "วันศุกร์ที่แล้ว ", "ทุกวันนี้ ", "ถึง ", "และ ", "น. ", "นาที ", "ๆ", "ทุก", "วัน", "สัปดาห์", "ำ", "\u{0E4D}\u{0E32}",
      "เ", "ะ", ", ", ".", "-", "อีก ", "ตอน ", "เวลา ", "ที่ ",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "สมชาย " + String(repeating: token, count: count) + " โทรศัพท์"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(30), "\(token) took \(elapsed)")
    }
    // A line past the read limit is a title and nothing more, at once.
    let past = String(repeating: "พรุ่งนี้ 3 โมง ", count: 500).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    #expect(slowest < .seconds(30), "the slowest long line took \(slowest)")
    // The first phrase of a long line still reads.
    let first = parse("พรุ่งนี้ " + String(repeating: "3 โมง พรุ่งนี้ ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 15 * 60)
  }
}
