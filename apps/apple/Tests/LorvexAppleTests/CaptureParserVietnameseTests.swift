import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["vi"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["vi"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weekly = TaskRecurrenceRule(freq: .weekly)
private let monthly = TaskRecurrenceRule(freq: .monthly)
private let yearly = TaskRecurrenceRule(freq: .yearly)

/// `text` with the stroke of "đ" written as "d" and every other mark kept.
private func strokeless(_ text: String) -> String {
  text.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
}

/// `text` as a keyboard with no Vietnamese input writes it: no vowel mark, no tone mark, and "d" for "đ".
private func toneless(_ text: String) -> String {
  strokeless(String(text.decomposedStringWithCanonicalMapping.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }))
}

/// `text` with every mark typed as a combining character after its letter.
private func decomposed(_ text: String) -> String { text.decomposedStringWithCanonicalMapping }

/// `text` with every letter and its marks composed into one character.
private func composed(_ text: String) -> String { text.precomposedStringWithCanonicalMapping }

/// Whether two strings hold the same Unicode scalars. Swift's `==` treats a composed letter and the same
/// letter typed as combining characters as equal, so a test of what a title keeps compares scalars.
private func sameScalars(_ left: String, _ right: String) -> Bool {
  left.unicodeScalars.elementsEqual(right.unicodeScalars)
}

/// The details a line reads as, with its title and phrases left out.
private struct Reading: Equatable {
  var plannedDay: Int?
  var dueDay: Int?
  var start: Int?
  var length: Int?
  var recurrence: TaskRecurrenceRule?
  var recurrenceStart: Int?
  var priority: LorvexTask.Priority?
  var kinds: [LorvexCaptureParse.Kind]

  init(_ parsed: LorvexCaptureParse) {
    plannedDay = parsed.plannedDayOffset
    dueDay = parsed.dueDayOffset
    start = parsed.startMinutes
    length = parsed.estimatedMinutes
    recurrence = parsed.recurrence
    recurrenceStart = parsed.recurrenceStartOffset
    priority = parsed.priority
    kinds = parsed.phrases.map(\.kind)
  }
}

/// Vietnamese capture lines, read for a user whose languages include Vietnamese.
@Suite("Capture parser Vietnamese")
struct CaptureParserVietnameseTests {
  // MARK: - Days

  @Test("Days: hôm nay, ngày mai, ngày kia, a part of the day with nay or mai, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Họp nhóm ngày mai")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Họp nhóm")
    #expect(line.phrases.map(\.text) == ["ngày mai"])

    let days: [(text: String, offset: Int)] = [
      ("Họp nhóm hôm nay", 0), ("Họp nhóm ngày hôm nay", 0), ("Họp nhóm sáng nay", 0), ("Họp nhóm trưa nay", 0),
      ("Họp nhóm chiều nay", 0), ("Họp nhóm tối nay", 0), ("Họp nhóm đêm nay", 0), ("Họp nhóm khuya nay", 0),
      ("Họp nhóm buổi sáng nay", 0), ("Họp nhóm buổi tối nay", 0),
      ("Họp nhóm ngày mai", 1), ("Họp nhóm sáng mai", 1), ("Họp nhóm trưa mai", 1), ("Họp nhóm chiều mai", 1),
      ("Họp nhóm tối mai", 1), ("Họp nhóm đêm mai", 1), ("Họp nhóm buổi sáng mai", 1), ("Họp nhóm vào ngày mai", 1),
      ("Họp nhóm ngày kia", 2), ("Họp nhóm ngày mốt", 2),
      ("Họp nhóm 3 ngày nữa", 3), ("Họp nhóm ba ngày nữa", 3), ("Họp nhóm sau 3 ngày", 3),
      ("Họp nhóm sau ba ngày", 3), ("Họp nhóm 10 ngày nữa", 10), ("Họp nhóm mười ngày nữa", 10),
      ("Họp nhóm mười hai ngày nữa", 12), ("Họp nhóm hai mươi ngày nữa", 20),
      ("Họp nhóm 1 tuần nữa", 7), ("Họp nhóm một tuần nữa", 7), ("Họp nhóm 2 tuần nữa", 14),
      ("Họp nhóm hai tuần nữa", 14), ("Họp nhóm sau 2 tuần", 14),
      ("Họp nhóm tuần sau", 7), ("Họp nhóm tuần tới", 7),
      ("Họp nhóm cuối tuần", 4), ("Họp nhóm cuối tuần này", 4), ("Họp nhóm vào cuối tuần", 4),
      ("Họp nhóm cuối tuần sau", 11), ("Họp nhóm cuối tuần tới", 11), ("Họp nhóm thứ Bảy và Chủ nhật", 4),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Họp nhóm", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Ngày mai họp nhóm")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "họp nhóm")
    let sentence = parse("Tối nay đi chơi")
    #expect(sentence.plannedDayOffset == 0)
    #expect(sentence.title == "đi chơi")
    // A part of the day that forms a noun with the word before it stays with that noun: dinner tomorrow is
    // still "Ăn tối". Without such a noun the part belongs to the day.
    for (text, title, offset) in [
      ("Ăn tối mai", "Ăn tối", 1), ("Ăn tối nay", "Ăn tối", 0), ("Ăn trưa mai", "Ăn trưa", 1),
      ("Ngủ trưa nay", "Ngủ trưa", 0), ("Lớp tối mai", "Lớp tối", 1), ("Họp tối mai", "Họp", 1),
      ("Ăn tối thứ Sáu", "Ăn tối", 3),
    ] as [(String, String, Int)] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == offset, "\(text): planned day")
      #expect(parsed.title == title, "\(text): title")
    }
  }

  @Test("Past days and phrases that name no day are not read")
  func pastAndVagueDays() {
    expectLinesUnread(
      [
        // Past days.
        "Họp hôm qua", "Họp hôm kia", "Họp ngày hôm qua", "Họp tối qua", "Họp sáng qua", "Họp đêm qua",
        "Họp tuần trước", "Họp tuần qua", "Họp thứ Hai tuần trước", "Họp thứ Hai tuần qua", "Họp cuối tuần trước",
        "Họp 3 ngày trước", "Họp 3 tuần trước", "Họp tháng trước", "Họp năm ngoái",
        // This week's Monday has passed on a Tuesday.
        "Họp thứ Hai tuần này",
        // A month or a year ahead has no day offset, and a count of working days is no count of days.
        "Nộp bài tháng sau", "Nộp bài tháng tới", "Nộp bài năm sau", "Họp 2 tháng nữa", "Họp 3 ngày làm việc nữa",
        "Họp sau 3 ngày làm việc",
        // This week, this month, and the next three weeks name no day.
        "Họp tuần này", "Họp tháng này", "Họp 3 tuần tới",
        // A bound at a period or a period a task is for sets a limit, not a day.
        "Họp trong 3 ngày nữa", "Họp trong tuần sau", "Họp trước cuối tuần", "Họp đến cuối tuần", "Họp cho tuần tới",
        // A count of times in a period is a rate, not a day.
        "Tập 3 lần trong tuần", "Họp nhóm 2 lần trong 3 ngày",
        // "Mai" alone is a name or the apricot blossom, and "mốt" alone is a name or "one" in "hai mốt".
        "Họp Mai", "Mai đi chợ", "Gặp Mai", "Gặp mai", "Hoa mai nở", "Cây mai vàng", "Mốt Hoàng đến chơi",
        // "Ngày thứ hai" is the second day, and "thứ" with a word before it is an ordinal.
        "Họp ngày thứ Sáu", "Họp ngày thứ hai",
      ], languages: ["vi"])
    // The time that follows a past day still reads.
    let time = parse("Họp hôm qua lúc 3 giờ chiều")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Họp hôm qua")
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Họp thứ Hai", 6), ("Họp thứ Ba", 7), ("Họp thứ Tư", 1), ("Họp thứ Năm", 2), ("Họp thứ Sáu", 3),
      ("Họp thứ Bảy", 4), ("Họp Chủ nhật", 5), ("Họp chủ nhật", 5), ("Họp vào thứ Sáu", 3), ("Họp vào Chủ nhật", 5),
      ("Họp thứ 2", 6), ("Họp thứ 3", 7), ("Họp thứ 4", 1), ("Họp thứ 5", 2), ("Họp thứ 6", 3), ("Họp thứ 7", 4),
      ("Họp vào thứ 6", 3),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "thứ Ba tuần này" is today.
      ("Họp thứ Ba tuần này", 0), ("Họp thứ Tư tuần này", 1), ("Họp thứ Sáu tuần này", 3),
      ("Họp thứ Bảy tuần này", 4), ("Họp Chủ nhật tuần này", 5), ("Họp tuần này thứ Sáu", 3),
      ("Họp thứ Hai tuần sau", 6), ("Họp thứ Ba tuần sau", 7), ("Họp thứ Tư tuần sau", 8),
      ("Họp thứ Năm tuần sau", 9), ("Họp thứ Sáu tuần sau", 10), ("Họp thứ Bảy tuần sau", 11),
      ("Họp Chủ nhật tuần sau", 12), ("Họp thứ Hai tuần tới", 6), ("Họp thứ Sáu tuần tới", 10),
      ("Họp Chủ nhật tuần tới", 12), ("Họp thứ 6 tuần sau", 10), ("Họp thứ 7 tuần sau", 11),
      ("Họp tuần sau thứ Sáu", 10), ("Họp tuần tới thứ Hai", 6),
      // A part of the day written before the weekday or after it.
      ("Họp chiều thứ Sáu", 3), ("Họp thứ Sáu chiều", 3), ("Họp sáng thứ Hai", 6), ("Họp thứ Hai sáng", 6),
      ("Họp tối Chủ nhật", 5), ("Họp trưa thứ Sáu", 3), ("Họp thứ Bảy tối", 4), ("Họp chiều thứ Sáu tuần sau", 10),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Họp", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("Họp thứ Hai lúc 9 giờ sáng")
    #expect(timed.plannedDayOffset == 6)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Họp")
    let opening = parse("Thứ Hai họp nhóm")
    #expect(opening.plannedDayOffset == 6)
    #expect(opening.title == "họp nhóm")
  }

  @Test("T2 to T7 and CN, ordinals, names of days, and lists of weekdays name no one day")
  func abbreviationsOrdinalsAndLists() {
    expectLinesUnread(
      [
        // The abbreviations are as often a count, a code, or a name.
        "Họp T2", "Họp T6", "Họp CN", "Họp t7", "Họp cn",
        // Ordinals, an order, and a rank.
        "Lần thứ hai", "Màn hình thứ hai", "Bài thứ sáu", "Tầng thứ tư", "Thứ hạng", "Hạng thứ 2", "Thứ tự ưu tiên",
        "Xếp thứ tự các bài", "Thứ tự ưu tiên của dự án",
        // A weekday by its place in the month, and the names of days.
        "Họp thứ Hai đầu tiên của tháng", "Mua sắm Thứ Sáu đen", "Lễ Chủ nhật Phục Sinh",
        // A list of weekdays names no one day.
        "Họp thứ Hai và thứ Tư", "Họp thứ Hai hoặc thứ Ba", "Họp thứ Hai, thứ Tư và thứ Sáu", "Họp thứ 2 và thứ 4",
        "Họp thứ Sáu chiều và thứ Bảy sáng", "Họp thứ Hai và thứ Sáu",
      ], languages: ["vi"])
    // The time that follows still reads, and the abbreviation stays in the title.
    let time = parse("Họp T6 3 giờ chiều")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.plannedDayOffset == nil)
    #expect(time.title == "Họp T6")
    #expect(parse("Họp mỗi thứ Hai và thứ Tư").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE"]))
    // A weekday next to a date, or before a comma and a time, still reads.
    #expect(parse("Họp thứ Sáu, 16 tháng 10").plannedDayOffset == captureDayOffset("2026-10-16"))
    #expect(parse("Họp thứ Hai, 9 giờ sáng").plannedDayOffset == 6)
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("Báo cáo cuối tuần", 0), ("Báo cáo cuối tuần sau", 7), ("Báo cáo thứ Bảy", 7), ("Báo cáo thứ Bảy tuần này", 0),
      ("Báo cáo Chủ nhật", 1), ("Báo cáo thứ Hai", 2), ("Báo cáo thứ Hai tuần sau", 2),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("Báo cáo cuối tuần", 0), ("Báo cáo cuối tuần sau", 7), ("Báo cáo Chủ nhật", 7), ("Báo cáo Chủ nhật tuần này", 0),
      ("Báo cáo Chủ nhật tuần sau", 7), ("Báo cáo thứ Bảy", 6), ("Báo cáo thứ Hai", 1), ("Báo cáo thứ Hai tuần sau", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // On a Sunday the Monday of this week has passed.
    let passed = parse("Báo cáo thứ Hai tuần này", on: "2026-09-20", weekday: 1)
    #expect(passed.plannedDayOffset == nil)
    #expect(passed.title == "Báo cáo thứ Hai tuần này")
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "thứ Hai tuần này" is today.
    for (text, offset) in [
      ("Báo cáo thứ Hai", 7), ("Báo cáo thứ Hai tuần này", 0), ("Báo cáo thứ Hai tuần sau", 7), ("Báo cáo thứ Ba", 1),
      ("Báo cáo thứ Sáu tuần này", 4),
    ] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("Báo cáo đến thứ Hai", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("Họp mỗi thứ Hai", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("Báo cáo từ thứ Hai đến thứ Tư", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
    let tuesdayToThursday = parse("Báo cáo từ thứ Ba đến thứ Năm", on: "2026-09-21", weekday: 2)
    #expect(tuesdayToThursday.plannedDayOffset == 1)
    #expect(tuesdayToThursday.dueDayOffset == 3)
  }

  // MARK: - Dates

  @Test("Written dates: a month number, a year, numbers with slashes, dashes, or dots, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Khám bệnh 15 tháng 10", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh ngày 15 tháng 10", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh vào ngày 15 tháng 10", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15 thg 10", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15 tháng 10 năm 2026", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15 tháng 10 2026", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh ngày 15/10", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh vào 15/10", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15/10/2026", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15-10-2026", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15.10.2026", "Khám bệnh", "2026-10-15"),
      ("Khám bệnh 15/10/26", "Khám bệnh", "2026-10-15"),
      ("KHÁM BỆNH NGÀY 15 THÁNG 10", "KHÁM BỆNH", "2026-10-15"),
      ("Khám bệnh 1 tháng 5 năm 2027", "Khám bệnh", "2027-05-01"),
      ("Khám bệnh 1/5/2027", "Khám bệnh", "2027-05-01"),
      ("Khám bệnh 3 tháng 1", "Khám bệnh", "2027-01-03"),
      ("Khám bệnh 3 tháng 2", "Khám bệnh", "2027-02-03"),
      ("Khám bệnh 3 tháng 3", "Khám bệnh", "2027-03-03"),
      ("Khám bệnh 3 tháng 4", "Khám bệnh", "2027-04-03"),
      ("Khám bệnh 3 tháng 5", "Khám bệnh", "2027-05-03"),
      ("Khám bệnh 3 tháng 6", "Khám bệnh", "2027-06-03"),
      ("Khám bệnh 3 tháng 7", "Khám bệnh", "2027-07-03"),
      ("Khám bệnh 3 tháng 8", "Khám bệnh", "2027-08-03"),
      ("Khám bệnh 3 tháng 9", "Khám bệnh", "2027-09-03"),
      ("Khám bệnh 3 tháng 10", "Khám bệnh", "2026-10-03"),
      ("Khám bệnh 3 tháng 11", "Khám bệnh", "2026-11-03"),
      ("Khám bệnh 3 tháng 12", "Khám bệnh", "2026-12-03"),
      ("Khám bệnh 22 tháng 9", "Khám bệnh", "2026-09-22"),
      // A day of the month alone is this month's, or next month's once it has passed.
      ("Trả tiền nhà ngày 25", "Trả tiền nhà", "2026-09-25"),
      ("Trả tiền nhà vào ngày 25", "Trả tiền nhà", "2026-09-25"),
      ("Trả tiền nhà ngày 5", "Trả tiền nhà", "2026-10-05"),
      // A weekday before the date is part of it.
      ("Khám bệnh thứ Sáu 16 tháng 10", "Khám bệnh", "2026-10-16"),
      ("Khám bệnh thứ Sáu, 16 tháng 10", "Khám bệnh", "2026-10-16"),
      ("Khám bệnh thứ Sáu 16/10", "Khám bệnh", "2026-10-16"),
      ("Khám bệnh Chủ nhật 4 tháng 10", "Khám bệnh", "2026-10-04"),
      ("Sinh nhật mẹ 14 tháng 3", "Sinh nhật mẹ", "2027-03-14"),
      ("Nghỉ phép 1 tháng 12", "Nghỉ phép", "2026-12-01"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Họp thứ Năm 15 tháng 10 lúc 2 giờ 30 chiều")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Họp")
    let concert = parse("Xem hòa nhạc 20 tháng 10 lúc 19h")
    #expect(concert.plannedDayOffset == captureDayOffset("2026-10-20"))
    #expect(concert.startMinutes == 19 * 60)
    #expect(concert.title == "Xem hòa nhạc")
  }

  @Test("Numbers that are no date, a past year, a day the month does not have, and the lunar calendar stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // A short date with no word that makes it a date is a fraction, a score, or a ratio, and a bare month is no day.
        "Khám bệnh 15/10", "Khám 5/3", "Hết hạn 31/12", "Uống 1/2 viên", "Điểm 3/5", "Báo cáo tháng 10",
        "Báo cáo tháng 10 năm 2026", "Họp mỗi tháng 10",
        // A day the month does not have, and a year that is past.
        "Khám bệnh 30 tháng 2", "Khám bệnh ngày 31 tháng 2", "Khám bệnh ngày 31/4/2027", "Khám bệnh 15 tháng 10 năm 2025",
        // A count of days, chapters, versions, rooms, scores, percentages, prices, and phone numbers.
        "Họp 5 tháng 3 ngày", "Nghỉ phép 2 ngày", "Chương 1.5", "Phiên bản 2.3.4", "Phòng 15.10", "Tỷ số 3-1",
        "Giảm giá 15%", "Giá 15.500", "iOS 17.4", "Q3 2026", "Điện thoại 090 123 4567", "Trang 15-10",
        // The dates of the lunar calendar name another day than the number says.
        "Giỗ ông 15 tháng 8 âm lịch", "Giỗ ông 15/8 AL", "Giỗ ông âm lịch 15/8", "Giỗ ông 15 tháng 8 âm",
        "Cúng mùng 5 tháng 10",
      ], languages: ["vi"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Du lịch", "3-5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ 3 đến 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ ngày 3 đến ngày 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ ngày 3 đến 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ 3 tháng 5 đến 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ ngày 3 tháng 5 đến ngày 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "3 tháng 5 - 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ 3/5 đến 5/5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "giữa ngày 3 và ngày 5 tháng 5", "2027-05-03", "2027-05-05"),
        ("Du lịch", "3-5 tháng 5 năm 2027", "2027-05-03", "2027-05-05"),
        ("Du lịch", "từ 3 đến 5 tháng 10", "2026-10-03", "2026-10-05"),
        ("Du lịch", "3-5 tháng 10", "2026-10-03", "2026-10-05"),
        ("Du lịch", "giữa ngày 3 và ngày 5 tháng 10", "2026-10-03", "2026-10-05"),
        ("Du lịch", "từ 30 tháng 5 đến 2 tháng 6", "2027-05-30", "2027-06-02"),
        ("Du lịch cuối năm", "từ 24 tháng 12 đến 2 tháng 1", "2026-12-24", "2027-01-02"),
      ], languages: ["vi"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Du lịch 5-3 tháng 5", "Du lịch từ 5 đến 3 tháng 5", "Du lịch 3 tháng 5 - 3 tháng 5", "Giá 3-5 triệu",
        "Họp từ 3 đến 5 người", "Họp từ 3 đến 5",
      ], languages: ["vi"])
  }

  @Test("A day alone opens a range joined by a spaced dash only after nothing that names a day")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 tháng 5")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    let meeting = parse("Họp 12 - 14 tháng 10")
    #expect(meeting.title == "Họp 12")
    #expect(meeting.plannedDayOffset == captureDayOffset("2026-10-14"))
    #expect(meeting.dueDayOffset == nil)
    let holiday = parse("Du lịch 3 - 5 tháng 5")
    #expect(holiday.title == "Du lịch 3")
    #expect(holiday.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(holiday.dueDayOffset == nil)
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time or a length still reads")
  func rangeTakesBothDays() {
    let line = parse("Du lịch 3-5 tháng 5 sáng mai")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Du lịch sáng mai")
    let timed = parse("Du lịch 3-5 tháng 5 lúc 9 giờ sáng")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Du lịch")
    let length = parse("Du lịch 3-5 tháng 5 30 phút")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "Du lịch")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so the span ends on the
    // Wednesday after the Monday.
    expectDateRanges(
      [
        ("Hội nghị", "từ thứ Hai đến thứ Tư", "2026-09-28", "2026-09-30"),
        ("Hội nghị", "thứ Hai đến thứ Tư", "2026-09-28", "2026-09-30"),
        ("Hội nghị", "từ thứ Sáu đến Chủ nhật", "2026-09-25", "2026-09-27"),
        ("Hội nghị", "thứ Sáu đến Chủ nhật", "2026-09-25", "2026-09-27"),
        ("Hội nghị", "từ thứ Sáu đến thứ Hai", "2026-09-25", "2026-09-28"),
        ("Hội nghị", "thứ Sáu - Chủ nhật", "2026-09-25", "2026-09-27"),
        ("Hội nghị", "thứ Bảy - Chủ nhật", "2026-09-26", "2026-09-27"),
        ("Hội nghị", "từ thứ 2 đến thứ 6", "2026-09-28", "2026-10-02"),
        ("Hội nghị", "thứ 2 - thứ 6", "2026-09-28", "2026-10-02"),
        ("Sprint", "thứ Hai - thứ Sáu", "2026-09-28", "2026-10-02"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Hội nghị", "từ thứ Ba đến thứ Năm", "2026-09-29", "2026-10-01"),
      ], languages: ["vi"])
    // Monday to Friday after "mỗi", and the working days, repeat.
    for text in [
      "Tập gym mỗi thứ Hai đến thứ Sáu", "Tập gym mỗi thứ Hai - thứ Sáu", "Tập gym mỗi ngày làm việc",
      "Tập gym các ngày làm việc", "Tập gym vào các ngày làm việc", "Tập gym các ngày trong tuần",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Tập gym", "\(text): title")
    }
  }

  // MARK: - Due days

  @Test("Due days: trước, hạn, hạn chót, hết hạn, deadline, đến, tới, cho đến, chậm nhất, muộn nhất, and trễ nhất")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Nộp bài trước thứ Sáu", "Nộp bài", 3),
      ("Nộp bài trước Chủ nhật", "Nộp bài", 5),
      ("Nộp bài trước ngày mai", "Nộp bài", 1),
      ("Nộp bài trước ngày kia", "Nộp bài", 2),
      ("Nộp bài trước tối nay", "Nộp bài", 0),
      ("Nộp bài trước thứ Hai tuần sau", "Nộp bài", 6),
      ("Nộp bài trước thứ Sáu tuần sau", "Nộp bài", 10),
      ("Nộp bài trước 15 tháng 10", "Nộp bài", 23),
      ("Nộp bài trước ngày 15 tháng 10", "Nộp bài", 23),
      ("Nộp bài trước 15/10", "Nộp bài", 23),
      ("Nộp bài trước 15/10/2026", "Nộp bài", 23),
      ("Nộp bài trước ngày 15", "Nộp bài", 23),
      ("Nộp bài hạn thứ Sáu", "Nộp bài", 3),
      ("Nộp bài hạn: thứ Sáu", "Nộp bài", 3),
      ("Nộp bài hạn chót thứ Sáu", "Nộp bài", 3),
      ("Nộp bài hạn cuối thứ Sáu", "Nộp bài", 3),
      ("Nộp bài hết hạn thứ Sáu", "Nộp bài", 3),
      ("Nộp bài đến hạn thứ Sáu", "Nộp bài", 3),
      ("Nộp bài hạn ngày mai", "Nộp bài", 1),
      ("Nộp bài hạn 15 tháng 10", "Nộp bài", 23),
      ("Nộp bài deadline thứ Sáu", "Nộp bài", 3),
      ("Nộp bài deadline: thứ Sáu", "Nộp bài", 3),
      ("Nộp bài đến thứ Sáu", "Nộp bài", 3),
      ("Nộp bài tới thứ Sáu", "Nộp bài", 3),
      ("Nộp bài cho đến thứ Sáu", "Nộp bài", 3),
      ("Nộp bài đến hết thứ Sáu", "Nộp bài", 3),
      ("Nộp bài đến hết hôm nay", "Nộp bài", 0),
      ("Nộp bài chậm nhất thứ Sáu", "Nộp bài", 3),
      ("Nộp bài muộn nhất thứ Sáu", "Nộp bài", 3),
      ("Nộp bài trễ nhất thứ Sáu", "Nộp bài", 3),
      ("Nộp bài chậm nhất ngày mai", "Nộp bài", 1),
      ("NỘP BÀI TRƯỚC THỨ SÁU", "NỘP BÀI", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Làm báo cáo hôm nay hạn thứ Sáu")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Làm báo cáo")
    // A due phrase that opens the line.
    let opening = parse("Trước thứ Sáu nộp báo cáo")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "nộp báo cáo")
    // A bound at a period names no due day, and neither does a bare number, a month ahead, or a person.
    expectLinesUnread(
      [
        "Nộp bài trước cuối tuần", "Nộp bài đến cuối tuần", "Nộp bài trước tuần sau", "Nộp bài trước tháng sau",
        "Nộp bài cho tuần tới", "Nộp bài đến khi xong", "Nộp bài cho 3 người", "Mua quà cho mẹ",
        "Nộp bài trước thứ Hai hoặc thứ Ba",
      ], languages: ["vi"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Nộp bài trước 17h", "Nộp bài trước 5 giờ chiều", "Họp trước 10 giờ", "Họp đến 5 giờ", "Nộp bài chậm nhất 17h",
        "Nộp bài sau 18:00", "Nộp bài trước 17:00", "Nộp bài đến 5 giờ chiều", "Nộp bài hạn 17h",
        "Nộp bài trước 12 giờ trưa", "Nộp bài trước 17 giờ 30", "Nộp bài muộn nhất 17:30", "Nộp bài đến hết 17h",
      ], languages: ["vi"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Nộp bài trước thứ Sáu 17h", "Nộp bài 17h", 3), ("Nộp bài trước thứ Sáu 5 giờ chiều", "Nộp bài 5 giờ chiều", 3),
      ("Nộp bài đến thứ Hai 9 giờ", "Nộp bài 9 giờ", 6), ("Nộp bài chậm nhất ngày mai 9:00", "Nộp bài 9:00", 1),
      ("Nộp bài hạn 15 tháng 10 lúc 5 giờ chiều", "Nộp bài lúc 5 giờ chiều", 23),
    ] as [(String, String, Int)] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A day after the bound is the day to do it, and the bound stays.
    let planned = parse("Nộp bài trước 17:00 thứ Sáu")
    #expect(planned.plannedDayOffset == 3)
    #expect(planned.dueDayOffset == nil)
    #expect(planned.startMinutes == nil)
    #expect(planned.title == "Nộp bài trước 17:00")
    // A time range that ends in a clock time is still a range, and a bound after a day stays a bound.
    let range = parse("Họp từ 14h đến 17h30")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 210)
    #expect(range.title == "Họp")
    let bound = parse("Họp đến 17h30 ngày mai")
    #expect(bound.plannedDayOffset == 1)
    #expect(bound.startMinutes == nil)
    #expect(bound.title == "Họp đến 17h30")
    // The clock that ends a range of days is the range's time.
    let rangeTime = parse("Họp từ thứ Hai đến thứ Tư lúc 9 giờ")
    #expect(rangeTime.plannedDayOffset == 6)
    #expect(rangeTime.dueDayOffset == 8)
    #expect(rangeTime.startMinutes == 9 * 60)
    #expect(rangeTime.title == "Họp")
    // Without Vietnamese, English reads the clock time and leaves the words.
    let english = parse("Nộp bài trước 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
    #expect(english.title == "Nộp bài trước")
  }

  // MARK: - Clock times

  @Test("Clock times: giờ, h, a colon, a part of the day, SA and CH, midnight, and an hour spelled as a word")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Họp lúc 3 giờ chiều", 15 * 60), ("Họp 3 giờ chiều", 15 * 60), ("Họp 3h chiều", 15 * 60), ("Họp 15h", 15 * 60),
      ("Họp 15h30", 15 * 60 + 30), ("Họp 15:30", 15 * 60 + 30), ("Họp lúc 15:30", 15 * 60 + 30),
      ("Họp lúc 15.30", 15 * 60 + 30), ("Họp 15 giờ", 15 * 60), ("Họp 15 giờ 30", 15 * 60 + 30),
      ("Họp lúc 15 giờ 30 phút", 15 * 60 + 30), ("Họp 3 giờ", 15 * 60), ("Họp lúc 3 giờ", 15 * 60),
      ("Họp 9 giờ", 9 * 60), ("Họp 9h", 9 * 60), ("Họp 10h45", 10 * 60 + 45), ("Họp 10:45", 10 * 60 + 45),
      ("Họp lúc 10 giờ 45", 10 * 60 + 45), ("Họp 0h", 0), ("Họp 00:00", 0), ("Họp 0 giờ 30", 30),
      ("Họp 3 giờ đúng", 15 * 60), ("Họp lúc 3 giờ đúng", 15 * 60), ("Họp đúng 3 giờ", 15 * 60),
      ("Họp 2h", 14 * 60), ("Họp 2h30", 14 * 60 + 30),
      // A part of the day after the hour.
      ("Họp 8 giờ tối", 20 * 60), ("Họp 7 giờ sáng", 7 * 60), ("Họp 12 giờ trưa", 12 * 60), ("Họp 2 giờ trưa", 14 * 60),
      ("Họp 11 giờ đêm", 23 * 60), ("Họp 1 giờ sáng", 60), ("Họp 9h sáng", 9 * 60), ("Họp 9 giờ 30 sáng", 9 * 60 + 30),
      ("Họp 9h30 sáng", 9 * 60 + 30), ("Họp 7h tối", 19 * 60), ("Họp 5h chiều", 17 * 60), ("Họp 12h trưa", 12 * 60),
      ("Họp 12h30 trưa", 12 * 60 + 30), ("Họp lúc 3:30 chiều", 15 * 60 + 30), ("Họp 3:30 chiều", 15 * 60 + 30),
      ("Họp 4 giờ 30 chiều", 16 * 60 + 30), ("Họp 8 giờ buổi tối", 20 * 60), ("Họp tầm 3 giờ chiều", 15 * 60),
      // SA and CH are the 12-hour clock's AM and PM.
      ("Họp 3:30 CH", 15 * 60 + 30), ("Họp 9:30 SA", 9 * 60 + 30), ("Họp 12:30 CH", 12 * 60 + 30),
      ("Họp 12:30 SA", 30),
      // An hour spelled as a word needs a lead or a part of the day.
      ("Họp ba giờ chiều", 15 * 60), ("Họp lúc ba giờ", 15 * 60), ("Họp lúc ba giờ rưỡi chiều", 15 * 60 + 30),
      ("Họp lúc một giờ chiều", 13 * 60), ("Họp lúc mười giờ", 10 * 60), ("Họp tám giờ tối", 20 * 60),
      ("Họp mười một giờ sáng", 11 * 60), ("Họp lúc bảy giờ", 7 * 60),
      // English's own forms.
      ("Họp 3pm", 15 * 60), ("Họp lúc 3pm", 15 * 60), ("Họp 17:30", 17 * 60 + 30), ("Họp 3:30 pm", 15 * 60 + 30),
      ("HỌP LÚC 3 GIỜ CHIỀU", 15 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
      #expect(parsed.title == (line.text.hasPrefix("HỌP") ? "HỌP" : "Họp"), "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The system writes AM and PM in capitals, so lowercase "sa" and "ch" are words of the title and the
    // time stays English's.
    let lowercaseSa = parse("Họp 9:30 sa")
    #expect(lowercaseSa.startMinutes == 9 * 60 + 30)
    #expect(lowercaseSa.title == "Họp sa")
    let lowercaseCh = parse("Họp 3:30 ch")
    #expect(lowercaseCh.startMinutes == 15 * 60 + 30)
    #expect(lowercaseCh.title == "Họp ch")
    // The title is what the time leaves, and a zone stays in it.
    #expect(parse("Gọi mẹ lúc 3 giờ").title == "Gọi mẹ")
    #expect(parse("Hẹn phỏng vấn ngày mai lúc 14h30").title == "Hẹn phỏng vấn")
    #expect(parse("Họp 3 giờ chiều ICT").title == "Họp ICT")
    #expect(parse("Họp 3 giờ chiều ICT").startMinutes == 15 * 60)
    #expect(parse("Họp 3 giờ với Nam").title == "Họp với Nam")
    #expect(parse("Lúc 5 giờ đón con").startMinutes == 17 * 60)
    #expect(parse("Lúc 5 giờ đón con").title == "đón con")
    // A number before "lúc 10 giờ" is no amount of hours: "lúc" opens the clock time.
    let room = parse("Họp phòng 3 lúc 10 giờ sáng")
    #expect(room.startMinutes == 10 * 60)
    #expect(room.estimatedMinutes == nil)
    #expect(room.title == "Họp phòng 3")
    // An approximate hour, an hour spelled as a word with no lead, and an hour that is no hour stay in the title.
    expectLinesUnread(["Họp khoảng 3 giờ", "Họp một giờ", "Giờ làm việc", "Giờ cao điểm", "Giờ học tiếng Anh"], languages: ["vi"])
  }

  @Test("A part of the day beside an hour decides it: sáng, trưa, chiều, tối, đêm, and a meal")
  func partsOfTheDay() {
    for (line, day, minutes, title) in [
      ("Ăn tối 7 giờ", nil, 19 * 60, "Ăn tối"), ("Ăn tối lúc 8 giờ", nil, 20 * 60, "Ăn tối"),
      ("Ăn tối mai 7 giờ", 1, 19 * 60, "Ăn tối"), ("Ăn trưa mai 12 giờ", 1, 12 * 60, "Ăn trưa"),
      ("Ăn trưa với mẹ 12 giờ rưỡi", nil, 12 * 60 + 30, "Ăn trưa với mẹ"), ("Ngủ trưa 1 giờ", nil, 13 * 60, "Ngủ trưa"),
      ("Họp tối nay 8 giờ", 0, 20 * 60, "Họp"), ("Họp tối nay 9 giờ", 0, 21 * 60, "Họp"),
      ("Họp 8 giờ tối mai", 1, 20 * 60, "Họp"), ("Họp sáng mai lúc 9 giờ", 1, 9 * 60, "Họp"),
      ("Họp sáng mai 7 giờ", 1, 7 * 60, "Họp"), ("Họp chiều mai 4 giờ", 1, 16 * 60, "Họp"),
      ("Chạy bộ sáng mai 6 giờ", 1, 6 * 60, "Chạy bộ"), ("Dậy sáng mai 5 giờ", 1, 5 * 60, "Dậy"),
      ("Họp sáng thứ Sáu 9 giờ", 3, 9 * 60, "Họp"), ("Họp thứ Sáu sáng 9 giờ", 3, 9 * 60, "Họp"),
      ("Họp thứ Sáu 5 giờ chiều", 3, 17 * 60, "Họp"), ("Họp thứ Sáu 5h chiều", 3, 17 * 60, "Họp"),
      ("Họp 5 giờ chiều thứ Sáu", 3, 17 * 60, "Họp"), ("Họp lúc 8h tối nay", 0, 20 * 60, "Họp"),
      ("Họp ngày mai 8 giờ", 1, 8 * 60, "Họp"), ("Họp ngày mai 3 giờ", 1, 15 * 60, "Họp"),
      ("Họp hôm nay 8 giờ", 0, 8 * 60, "Họp"), ("Họp 3 giờ chiều ngày mai", 1, 15 * 60, "Họp"),
      ("Lớp tối mai 8 giờ", 1, 20 * 60, "Lớp tối"),
    ] as [(String, Int?, Int, String)] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == title, "\(line): title")
    }
    // A part of the day or a meal as a noun names no day or time, and a count of nights is no clock time.
    expectLinesUnread(
      [
        "Ăn sáng", "Ăn tối", "Ăn trưa với Nam", "Bữa tối gia đình", "Đặt khách sạn 2 đêm", "Gói 3 ngày 2 đêm",
        "Ở lại 7 đêm", "Chợ đêm", "Chào buổi sáng", "Sáng tạo nội dung", "Chiều cao", "Tối ưu hóa", "Tối ưu hóa mã nguồn",
      ], languages: ["vi"])
  }

  @Test("After midnight: 12 giờ đêm, 2 giờ đêm, and nửa đêm run past the midnight that ends the day")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("Họp 12 giờ đêm", 1, 0), ("Họp nửa đêm", 1, 0), ("Họp 2 giờ đêm", 1, 2 * 60), ("Họp 12 giờ 30 đêm", 1, 30),
      ("Họp ngày mai 12 giờ đêm", 2, 0), ("Họp đêm mai 12 giờ", 2, 0), ("Họp tối nay 12 giờ", 1, 0),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Họp", "\(line): title")
    }
    // Eleven at night is still the day itself, 0h is the start of the day, and the 24th hour is no time of day.
    let eleven = parse("Họp 11 giờ đêm")
    #expect(eleven.plannedDayOffset == nil)
    #expect(eleven.startMinutes == 23 * 60)
    let start = parse("Họp 0h")
    #expect(start.plannedDayOffset == nil)
    #expect(start.startMinutes == 0)
    expectLinesUnread(["Họp 24h", "Họp 25 giờ", "Họp 24:00", "Họp 9:60", "Họp 9h60"], languages: ["vi"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func twelveHourRules() {
    for (line, minutes) in [
      ("Họp 1 giờ", 13 * 60), ("Họp 3 giờ", 15 * 60), ("Họp 6 giờ", 18 * 60), ("Họp 3h", 15 * 60),
      ("Họp 5h10", 17 * 60 + 10), ("Dậy lúc 5h30", 17 * 60 + 30), ("Họp 7 giờ", 7 * 60), ("Họp 06h", 6 * 60),
      ("Họp 06:00", 6 * 60), ("Họp 03:00", 3 * 60), ("Họp 11 giờ", 11 * 60), ("Họp 12 giờ", 12 * 60),
      ("Họp lúc ba giờ", 15 * 60), ("Họp lúc bảy giờ", 7 * 60),
      // A part of the day gives the hour its own reading.
      ("Họp 5h30 sáng", 5 * 60 + 30), ("Họp 3 giờ sáng", 3 * 60), ("Họp 3 giờ chiều", 15 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
    }
  }

  @Test("The half hour is written after the hour: 3 giờ rưỡi is 3:30, and 3 giờ kém 15 is 2:45")
  func halfHours() {
    let halves: [(text: String, minutes: Int)] = [
      ("Họp 3 giờ rưỡi", 15 * 60 + 30), ("Họp 1 giờ rưỡi", 13 * 60 + 30), ("Họp 3 rưỡi chiều", 15 * 60 + 30),
      ("Họp lúc ba giờ rưỡi", 15 * 60 + 30), ("Họp lúc ba giờ rưỡi chiều", 15 * 60 + 30),
      ("Họp 9 giờ rưỡi sáng", 9 * 60 + 30), ("Họp 8 giờ rưỡi tối", 20 * 60 + 30), ("Họp 12 giờ rưỡi", 12 * 60 + 30),
      ("Họp 10 giờ rưỡi", 10 * 60 + 30), ("Họp 3 giờ kém 15", 14 * 60 + 45), ("Họp 3 giờ kém 10", 14 * 60 + 50),
      ("Họp 3 giờ kém 20", 14 * 60 + 40), ("Họp 3 giờ kém 5", 14 * 60 + 55), ("Họp 4 giờ kém 15 chiều", 15 * 60 + 45),
      ("Họp 9 giờ kém 5 sáng", 8 * 60 + 55), ("Họp 3 giờ 15 phút chiều", 15 * 60 + 15),
    ]
    for line in halves {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
      #expect(parsed.title == "Họp", "\(line.text): title")
    }
    // "Rưỡi" after an hour that counts time is a length.
    let length = parse("Họp 2 tiếng rưỡi")
    #expect(length.startMinutes == nil)
    #expect(length.estimatedMinutes == 150)
  }

  @Test("Time ranges: từ with đến, giữa with và, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Họp từ 3 giờ đến 5 giờ chiều", 15 * 60, 120), ("Họp 3-5 giờ chiều", 15 * 60, 120),
      ("Họp từ 14h đến 16h", 14 * 60, 120), ("Họp 14:00-16:00", 14 * 60, 120), ("Họp 14:00 - 16:00", 14 * 60, 120),
      ("Họp từ 14h30 đến 16h", 14 * 60 + 30, 90), ("Họp từ 9 giờ đến 11 giờ sáng", 9 * 60, 120),
      ("Họp từ 7 giờ đến 9 giờ tối", 19 * 60, 120), ("Họp từ 9 giờ sáng đến 5 giờ chiều", 9 * 60, 480),
      ("Họp từ 8 giờ đến 10 giờ sáng", 8 * 60, 120), ("Họp 9h-11h", 9 * 60, 120), ("Họp 9:00-11:00", 9 * 60, 120),
      ("Họp 09:00 - 11:00", 9 * 60, 120), ("Họp 14h-16h30", 14 * 60, 150), ("Họp giữa 3 giờ và 5 giờ chiều", 15 * 60, 120),
      ("Họp từ 3 giờ chiều đến 5 giờ chiều", 15 * 60, 120), ("Họp từ 9 giờ 30 đến 11 giờ sáng", 9 * 60 + 30, 90),
      ("Họp 3-4 giờ chiều", 15 * 60, 60), ("Họp từ 15:30 đến 17:00", 15 * 60 + 30, 90),
      ("Họp từ 10 giờ sáng đến 12 giờ trưa", 10 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "Họp", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day or a meal makes the range that part's, as it does a single hour.
    let evening = parse("Họp tối nay từ 7 giờ đến 9 giờ")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.estimatedMinutes == 120)
    let morning = parse("Họp sáng mai từ 7 giờ đến 9 giờ")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 7 * 60)
    // A range may run past midnight.
    let overnight = parse("Trực 22:00-02:00")
    #expect(overnight.startMinutes == 22 * 60)
    #expect(overnight.estimatedMinutes == 240)
    #expect(overnight.title == "Trực")
    // Numbers that count something are no range of hours.
    expectLinesUnread(["Họp 14-16", "Họp 3-5", "Bài 3-5", "Trang 3-5", "Mua 3-5 cái"], languages: ["vi"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Họp 30 phút", 30), ("Họp 15 phút", 15), ("Họp 5 phút", 5), ("Họp 90 phút", 90), ("Họp 45phút", 45),
      ("Họp 1440 phút", 1440), ("Họp 30 PHÚT", 30),
      ("Họp 1 tiếng", 60), ("Họp 2 tiếng", 120), ("Họp một tiếng", 60), ("Họp hai tiếng", 120), ("Họp ba tiếng", 180),
      ("Họp 1,5 giờ", 90), ("Họp 1.5 giờ", 90), ("Họp 0,5 giờ", 30), ("Họp 2,5 tiếng", 150), ("Họp 1,5 tiếng", 90),
      ("Họp 1 tiếng rưỡi", 90), ("Họp một tiếng rưỡi", 90), ("Họp 2 tiếng rưỡi", 150), ("Họp hai tiếng rưỡi", 150),
      ("Họp nửa tiếng", 30), ("Họp nửa giờ", 30), ("Họp 1 giờ 30 phút", 90), ("Họp 2 tiếng 30 phút", 150),
      ("Họp 2 tiếng 15", 135), ("Họp 1 tiếng 30", 90), ("Họp 2 tiếng và 30 phút", 150),
      ("Họp 1h30p", 90), ("Họp 1h30m", 90), ("Họp 1,5h", 90), ("Họp 1.5h", 90), ("Họp 2h30p", 150),
      ("Họp ba mươi phút", 30), ("Họp mười lăm phút", 15), ("Họp hai mươi lăm phút", 25),
      ("Họp bốn mươi lăm phút", 45), ("Họp mười phút", 10),
      ("Họp mất 2 giờ", 120), ("Họp mất 30 phút", 30), ("Họp tốn 1 tiếng", 60), ("Họp kéo dài 2 giờ", 120),
      ("Họp kéo dài 2 tiếng", 120), ("Họp thời lượng 2 giờ", 120), ("Họp thời gian 2 giờ", 120),
      ("Họp ước tính 2 giờ", 120), ("Họp ước lượng 1 giờ", 60), ("Họp dự kiến 2 giờ", 120), ("Họp dài 2 giờ", 120),
      ("Họp khoảng 30 phút", 30), ("Họp khoảng 2 tiếng", 120), ("Họp tầm 30 phút", 30),
      ("Họp 2 giờ đồng hồ", 120), ("Họp 3 giờ đồng hồ", 180), ("Họp 24 tiếng", 1440), ("Họp 20 giờ đồng hồ", 1200),
      ("Họp 3 giờ 15 phút", 195),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Họp", "\(line.text): title")
    }
    let before = parse("30 phút họp")
    #expect(before.estimatedMinutes == 30)
    #expect(before.title == "họp")
    // A length beside a day and a time.
    let line = parse("Họp ngày mai lúc 3 giờ chiều mất 2 tiếng")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.title == "Họp")
  }

  @Test("A bare number of giờ is a clock hour and tiếng is a length; a moment, a bound, a rate, and a range are no length")
  func hoursAndLengths() {
    let hour = parse("Chạy bộ 1 giờ")
    #expect(hour.startMinutes == 13 * 60)
    #expect(hour.estimatedMinutes == nil)
    #expect(hour.title == "Chạy bộ")
    let length = parse("Chạy bộ 1 tiếng")
    #expect(length.startMinutes == nil)
    #expect(length.estimatedMinutes == 60)
    #expect(length.title == "Chạy bộ")
    // The opener that only a length has turns a number of giờ into a length, and so does "đồng hồ".
    #expect(parse("Chạy bộ mất 1 giờ").estimatedMinutes == 60)
    #expect(parse("Chạy bộ mất 1 giờ").startMinutes == nil)
    #expect(parse("Chạy bộ 1 giờ đồng hồ").estimatedMinutes == 60)
    // Giờ, h, and tiếng with minutes after them.
    #expect(parse("Chạy bộ 1h30").startMinutes == 13 * 60 + 30)
    #expect(parse("Chạy bộ 1h30").estimatedMinutes == nil)
    #expect(parse("Chạy bộ mất 1h30").estimatedMinutes == 90)
    #expect(parse("Chạy bộ mất 1h30").startMinutes == nil)
    expectLinesUnread(
      [
        "Họp trong 2 tiếng", "Họp trong vòng 2 tiếng", "Họp sau 30 phút", "Họp 2 tiếng nữa", "Họp 2 tiếng trước",
        "Họp mỗi 2 giờ", "Họp cách 2 tiếng", "Họp tối đa 2 tiếng", "Họp 2 tiếng tối đa", "Họp ít nhất 30 phút",
        "Họp hơn 2 tiếng", "Họp dưới 1 giờ", "Họp 2 tiếng một ngày", "Họp 2 tiếng/ngày", "Họp 30 phút một lần",
        "Họp 2-3 tiếng", "Họp 2 hoặc 3 tiếng", "Họp 0 phút", "Học 2 tiếng Anh", "Uống nước mỗi 2 giờ",
        "Họp 1/2 giờ",
      ], languages: ["vi"])
    // "Tiếng Anh" is the language, and a length written after it still reads.
    let english = parse("Học tiếng Anh 2 tiếng")
    #expect(english.estimatedMinutes == 120)
    #expect(english.title == "Học tiếng Anh")
    #expect(parse("Học tiếng Anh 1 tiếng").estimatedMinutes == 60)
    #expect(parse("Học tiếng Anh mỗi ngày").recurrence == daily)
  }

  @Test("An hour past 12 with minutes is a clock time; up to 12 it is a length, and an opener only a length has keeps it one")
  func hoursPastTwelveWithMinutes() {
    let times: [(text: String, minutes: Int)] = [
      ("Họp 15 giờ 30 phút", 15 * 60 + 30), ("Họp 13 giờ 5 phút", 13 * 60 + 5), ("Họp 20 giờ 15 phút", 20 * 60 + 15),
      ("Họp 18h30p", 18 * 60 + 30), ("Họp 18h 30 phút", 18 * 60 + 30), ("Họp 18h30 phút", 18 * 60 + 30),
      ("Họp 23 giờ 59 phút", 23 * 60 + 59),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
      #expect(parsed.title == "Họp", "\(line.text): title")
    }
    let lengths: [(text: String, minutes: Int)] = [
      ("Họp 12 giờ 30 phút", 750), ("Họp 3 giờ 15 phút", 195), ("Họp 1h30p", 90),
      ("Họp mất 15 giờ 30 phút", 930), ("Họp kéo dài 18h30p", 1110), ("Họp mất 18h30", 1110),
      ("Họp 15 tiếng 30 phút", 930), ("Họp 13,5 giờ", 810), ("Họp 20 giờ đồng hồ", 1200),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Họp", "\(line.text): title")
    }
    // A lead or a part of the day makes the clock reading, whatever the hour.
    #expect(parse("Họp lúc 15 giờ 30 phút").startMinutes == 15 * 60 + 30)
    #expect(parse("Họp 3 giờ 30 phút chiều").startMinutes == 15 * 60 + 30)
    #expect(parse("Họp lúc 3h30p").startMinutes == 15 * 60 + 30)
    // An hour that is no clock hour, or minutes in "m", read as neither a clock time nor a length.
    expectLinesUnread(["Họp 25 giờ 30 phút", "Họp 18h30m", "Họp 24h30p"], languages: ["vi"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func cadences() {
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Tập gym mỗi ngày", daily), ("Tập gym hằng ngày", daily), ("Tập gym hàng ngày", daily),
      ("Tập gym mọi ngày", daily), ("Tập gym mỗi sáng", daily), ("Tập gym mỗi chiều", daily),
      ("Tập gym mỗi tối", daily), ("Tập gym mỗi tuần", weekly), ("Tập gym hằng tuần", weekly),
      ("Tập gym hàng tuần", weekly), ("Tập gym mỗi tuần một lần", weekly), ("Tập gym một lần mỗi tuần", weekly),
      ("Tập gym mỗi tháng", monthly), ("Tập gym hằng tháng", monthly), ("Tập gym hàng tháng", monthly),
      ("Tập gym mỗi tháng một lần", monthly), ("Tập gym mỗi năm", yearly), ("Tập gym hằng năm", yearly),
      ("Tập gym hàng năm", yearly),
      ("Tập gym mỗi 2 ngày", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Tập gym mỗi hai ngày", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Tập gym mỗi 3 ngày", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Tập gym 2 ngày một lần", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Tập gym hai ngày một lần", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Tập gym cách ngày", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Tập gym mỗi 2 tuần", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Tập gym mỗi hai tuần", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Tập gym 2 tuần một lần", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Tập gym 2 tuần/lần", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Tập gym cách tuần", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Tập gym mỗi 14 ngày", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Tập gym mỗi 2 tháng", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Tập gym 3 tháng một lần", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Tập gym cứ 3 tháng", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Tập gym mỗi quý", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Tập gym mỗi 2 năm", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("TẬP GYM MỖI NGÀY", daily),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(sameScalars(parsed.title, line.text.hasPrefix("TẬP") ? "TẬP GYM" : "Tập gym"), "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // A repeat in front of the line.
    let opening = parse("Hàng ngày: tập gym")
    #expect(opening.recurrence == daily)
    #expect(opening.title == "tập gym")
    // A repeat at the end of a line that goes on after a noun.
    #expect(parse("Báo cáo hàng tháng").recurrence == monthly)
    #expect(parse("Báo cáo hàng tuần").recurrence == weekly)
    #expect(parse("Báo cáo hàng năm").recurrence == yearly)
    // A date beside a yearly repeat.
    let birthday = parse("Sinh nhật An 15 tháng 10 hàng năm")
    #expect(birthday.recurrence == yearly)
    #expect(birthday.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(birthday.title == "Sinh nhật An")
    // A repeat with a time or a length.
    for (text, rule, minutes, length) in [
      ("Tập gym mỗi ngày lúc 7 giờ sáng", daily, 7 * 60, nil), ("Tập gym mỗi sáng lúc 7 giờ", daily, 7 * 60, nil),
      ("Tập gym mỗi sáng 6h30", daily, 6 * 60 + 30, nil), ("Tập gym mỗi tối 8 giờ", daily, 20 * 60, nil),
      ("Tập gym mỗi tối lúc 8 giờ mất 30 phút", daily, 20 * 60, 30), ("Tập gym hàng ngày 8 giờ tối", daily, 20 * 60, nil),
      ("Tập gym mỗi sáng 30 phút", daily, nil, 30), ("Tập gym mỗi ngày 30 phút", daily, nil, 30),
    ] as [(String, TaskRecurrenceRule, Int?, Int?)] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == "Tập gym", "\(text): title")
    }
    let medicine = parse("Uống thuốc mỗi ngày lúc 8 giờ sáng")
    #expect(medicine.recurrence == daily)
    #expect(medicine.startMinutes == 8 * 60)
    #expect(medicine.title == "Uống thuốc")
  }

  @Test("Weekday repeats: mỗi thứ Hai, các thứ Ba, lists, spans, and the weekend")
  func weekdayRepeats() {
    let coming = parse("Tập gym mỗi thứ Hai")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Tập gym")
    for text in [
      "Tập gym mọi thứ Hai", "Tập gym các thứ Hai", "Tập gym mỗi thứ 2", "Tập gym mỗi tuần vào thứ Hai",
      "Tập gym hằng tuần vào thứ Hai", "Tập gym thứ Hai hàng tuần", "Tập gym thứ Hai mỗi tuần",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == monday, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.title == "Tập gym", "\(text): title")
    }
    let pairs: [(text: String, days: [String])] = [
      ("Tập gym mỗi thứ Ba và thứ Năm", ["TU", "TH"]),
      ("Tập gym mỗi thứ Hai, thứ Tư và thứ Sáu", ["MO", "WE", "FR"]),
      ("Tập gym mỗi thứ Hai, thứ Tư, thứ Sáu", ["MO", "WE", "FR"]), ("Tập gym mỗi thứ 2, 4, 6", ["MO", "WE", "FR"]),
      ("Tập gym mỗi thứ 3 và thứ 5", ["TU", "TH"]), ("Tập gym mỗi thứ Hai & thứ Năm", ["MO", "TH"]),
      ("Tập gym mỗi thứ Bảy", ["SA"]), ("Tập gym mỗi Chủ nhật", ["SU"]),
      ("Tập gym mỗi thứ Bảy và Chủ nhật", ["SU", "SA"]), ("Tập gym các thứ Ba và thứ Năm", ["TU", "TH"]),
      ("Tập gym thứ Hai và thứ Năm hằng tuần", ["MO", "TH"]), ("Tập gym mỗi thứ Hai và thứ Tư hằng tuần", ["MO", "WE"]),
      ("Tập gym mỗi thứ Hai đến thứ Năm", ["MO", "TU", "WE", "TH"]),
      ("Tập gym mỗi thứ Hai - thứ Năm", ["MO", "TU", "WE", "TH"]),
      ("Tập gym mỗi thứ Sáu đến Chủ nhật", ["SU", "FR", "SA"]),
      ("Tập gym từ thứ Hai đến thứ Năm hằng tuần", ["MO", "TU", "WE", "TH"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Tập gym", "\(line.text): title")
    }
    // An interval takes the weekdays after it.
    let interval = parse("Tập gym mỗi 2 tuần vào thứ Năm")
    #expect(interval.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TH"]))
    #expect(interval.recurrenceStartOffset == 2)
    #expect(interval.title == "Tập gym")
    // The start of a repeat on Wednesday, Friday, and Monday is the nearest day.
    #expect(parse("Tập gym mỗi thứ Hai, thứ Tư và thứ Sáu").recurrenceStartOffset == 1)
    #expect(parse("Tập gym mỗi thứ Ba và thứ Năm").recurrenceStartOffset == 0)
    #expect(parse("Tập gym mỗi thứ Bảy và Chủ nhật").recurrenceStartOffset == 4)
    for text in ["Tập gym mỗi cuối tuần", "Tập gym hàng cuối tuần", "Tập gym các cuối tuần", "Tập gym vào các cuối tuần"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == weekend, "\(text)")
      #expect(parsed.recurrenceStartOffset == 4, "\(text): start")
      #expect(parsed.title == "Tập gym", "\(text): title")
    }
    // "Cuối tuần" with no "mỗi" is one day.
    let day = parse("Rửa xe cuối tuần")
    #expect(day.recurrence == nil)
    #expect(day.plannedDayOffset == 4)
    #expect(day.title == "Rửa xe")
    // A repeat with a time.
    let timed = parse("Yoga mỗi thứ Ba và thứ Năm lúc 19:30")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(timed.startMinutes == 19 * 60 + 30)
    #expect(timed.title == "Yoga")
    let evening = parse("Yoga mỗi thứ Ba lúc 7 giờ tối")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    #expect(evening.startMinutes == 19 * 60)
    let morning = parse("Tập gym mỗi thứ Hai lúc 6 giờ sáng")
    #expect(morning.recurrence == monday)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "Tập gym")
    let both = parse("Tập gym mỗi thứ Hai và thứ Năm lúc 7 giờ 30 tối")
    #expect(both.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(both.startMinutes == 19 * 60 + 30)
    // A part of the day after the weekdays is part of the repeat phrase, and a time keeps its part of the day.
    let friday = parse("Học nhóm mỗi thứ Sáu tối")
    #expect(friday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(friday.title == "Học nhóm")
    #expect(friday.phrases.map(\.text) == ["mỗi thứ Sáu tối"])
    let late = parse("Học nhóm mỗi thứ Sáu tối 8 giờ")
    #expect(late.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(late.startMinutes == 20 * 60)
    #expect(late.title == "Học nhóm")
    let weekendTimed = parse("Giặt đồ mỗi cuối tuần lúc 10 giờ")
    #expect(weekendTimed.recurrence == weekend)
    #expect(weekendTimed.startMinutes == 10 * 60)
    #expect(weekendTimed.title == "Giặt đồ")
    let fixed = parse("Họp thứ Hai lúc 9 giờ sáng hằng tuần")
    #expect(fixed.recurrence == monday)
    #expect(fixed.startMinutes == 9 * 60)
    #expect(fixed.title == "Họp")
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [15])
    for text in [
      "Trả tiền nhà ngày 15 hàng tháng", "Trả tiền nhà ngày 15 hằng tháng", "Trả tiền nhà ngày 15 mỗi tháng",
      "Trả tiền nhà mỗi tháng vào ngày 15", "Trả tiền nhà mỗi tháng ngày 15", "Trả tiền nhà hàng tháng ngày 15",
      "Trả tiền nhà vào ngày 15 hàng tháng", "Trả tiền nhà ngày 15 của mỗi tháng",
      "Trả tiền nhà vào ngày 15 của mỗi tháng",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 23, "\(text): start")
      #expect(parsed.title == "Trả tiền nhà", "\(text): title")
    }
    let first = TaskRecurrenceRule(freq: .monthly, byMonthDay: [1])
    for text in ["Trả tiền nhà mỗi tháng vào ngày 1", "Trả tiền nhà ngày 1 hàng tháng"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == first, "\(text)")
      #expect(parsed.recurrenceStartOffset == 9, "\(text): start")
    }
  }

  @Test("A weekday by its place in the month, a count of times, a day left out, and a noun made of a cadence word stay")
  func unreadRepeats() {
    expectLinesUnread(
      [
        // A weekday by its place in the month has no repeat rule, so no part of it is read as a weekday.
        "Họp mỗi thứ Hai đầu tiên của tháng", "Họp mỗi thứ Hai cuối cùng của tháng",
        // Every day with a day left out has no repeat rule.
        "Họp hàng ngày trừ Chủ nhật", "Họp mỗi ngày ngoại trừ thứ Bảy", "Họp mỗi ngày làm việc trừ thứ Sáu",
        // A count of times in a period, and an interval of hours.
        "Tập gym 2 lần một tuần", "Tập gym 3 lần/tuần", "Tập gym mỗi tuần 2 lần", "Tập gym mỗi tuần ba lần",
        "Tập gym 3 lần mỗi ngày", "Tập thể dục 3 lần một tuần", "Uống thuốc ngày 2 lần", "Uống nước mỗi 2 giờ",
        // A holiday, a rest day, a named month, a day of the month, a weekday that may be a count, or a count of working days.
        "Họp mỗi ngày lễ", "Họp mỗi ngày nghỉ", "Họp mỗi tháng 10", "Họp mỗi ngày 15", "Họp mỗi ngày thứ Sáu",
        "Họp mỗi tuần này", "Họp mỗi 3 ngày làm việc",
      ], languages: ["vi"])
  }

  // MARK: - Priorities

  @Test("Priorities: gấp, khẩn, khẩn cấp, quan trọng, ưu tiên cao, trung bình, or thấp")
  func priorities() {
    let priorities: [(text: String, title: String, priority: LorvexTask.Priority)] = [
      ("Nộp báo cáo gấp", "Nộp báo cáo", .p1), ("Nộp báo cáo gấp.", "Nộp báo cáo", .p1),
      ("Nộp báo cáo gấp!", "Nộp báo cáo", .p1), ("Nộp báo cáo khẩn", "Nộp báo cáo", .p1),
      ("Nộp báo cáo khẩn cấp", "Nộp báo cáo", .p1), ("Nộp báo cáo quan trọng", "Nộp báo cáo", .p1),
      ("Nộp báo cáo quan trọng.", "Nộp báo cáo", .p1), ("Nộp báo cáo rất gấp", "Nộp báo cáo", .p1),
      ("Nộp báo cáo rất quan trọng", "Nộp báo cáo", .p1), ("Nộp báo cáo cực kỳ quan trọng", "Nộp báo cáo", .p1),
      ("Nộp báo cáo vô cùng quan trọng", "Nộp báo cáo", .p1), ("Nộp báo cáo hết sức quan trọng", "Nộp báo cáo", .p1),
      ("Gấp: nộp báo cáo", "nộp báo cáo", .p1), ("Rất gấp: nộp báo cáo", "nộp báo cáo", .p1),
      ("Khẩn cấp: gọi bác sĩ", "gọi bác sĩ", .p1), ("Gấp, nộp báo cáo", "nộp báo cáo", .p1),
      ("Quan trọng: nộp báo cáo", "nộp báo cáo", .p1),
      ("Nộp báo cáo ưu tiên cao", "Nộp báo cáo", .p1), ("Nộp báo cáo ưu tiên 1", "Nộp báo cáo", .p1),
      ("Nộp báo cáo, ưu tiên 1", "Nộp báo cáo", .p1), ("Nộp báo cáo mức độ ưu tiên cao", "Nộp báo cáo", .p1),
      ("Ưu tiên cao: nộp báo cáo", "nộp báo cáo", .p1),
      ("Nộp báo cáo ưu tiên trung bình", "Nộp báo cáo", .p2), ("Nộp báo cáo ưu tiên 2", "Nộp báo cáo", .p2),
      ("Nộp báo cáo ưu tiên thấp", "Nộp báo cáo", .p3), ("Nộp báo cáo ưu tiên 3", "Nộp báo cáo", .p3),
      ("Nộp báo cáo ưu tiên: thấp", "Nộp báo cáo", .p3), ("Nộp báo cáo mức độ ưu tiên thấp", "Nộp báo cáo", .p3),
      ("NỘP BÁO CÁO QUAN TRỌNG", "NỘP BÁO CÁO", .p1), ("NỘP BÁO CÁO ƯU TIÊN THẤP", "NỘP BÁO CÁO", .p3),
      // The shorthand every language reads.
      ("Nộp báo cáo !", "Nộp báo cáo", .p1), ("Nộp báo cáo p1", "Nộp báo cáo", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A negated word, "gấp" as the verb to fold, a word in the middle of a line, and a priority that is no
    // level are no priority.
    expectLinesUnread(
      [
        "Nộp báo cáo không gấp", "Nộp báo cáo chưa khẩn cấp", "Không quan trọng", "Nộp báo cáo không khẩn",
        "Gấp quần áo", "Đây là việc quan trọng nhất", "Tài liệu quan trọng cần nộp", "Họp quan trọng với khách",
        "Nộp báo cáo ưu tiên 4", "Nộp báo cáo ưu tiên",
      ], languages: ["vi"])
    // The word in the middle of a line stays in the title, and what follows it reads.
    let middle = parse("Báo cáo quan trọng ngày mai lúc 15h")
    #expect(middle.title == "Báo cáo quan trọng")
    #expect(middle.priority == nil)
    #expect(middle.plannedDayOffset == 1)
    #expect(middle.startMinutes == 15 * 60)
    // A due day beside a priority.
    let beside = parse("Nộp báo cáo trước thứ Sáu, quan trọng")
    #expect(beside.dueDayOffset == 3)
    #expect(beside.priority == .p1)
    #expect(beside.title == "Nộp báo cáo")
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyDetail() {
    let line = parse("Viết báo cáo ngày mai lúc 15h mất 2 tiếng quan trọng")
    #expect(line.title == "Viết báo cáo")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.priority == .p1)
    #expect(line.phrases.map(\.text) == ["ngày mai", "lúc 15h", "mất 2 tiếng", "quan trọng"])
    let recurring = parse("Tập gym mỗi thứ Hai lúc 18h 1 tiếng ưu tiên cao")
    #expect(recurring.title == "Tập gym")
    #expect(recurring.recurrence == monday)
    #expect(recurring.startMinutes == 18 * 60)
    #expect(recurring.estimatedMinutes == 60)
    #expect(recurring.priority == .p1)
    let due = parse("Nộp thuế trước 31 tháng 7 ưu tiên 2")
    #expect(due.title == "Nộp thuế")
    #expect(due.dueDayOffset == captureDayOffset("2027-07-31"))
    #expect(due.priority == .p2)
    let lunch = parse("Ăn trưa với An ngày mai lúc 12 giờ 30 mất 1 tiếng")
    #expect(lunch.title == "Ăn trưa với An")
    #expect(lunch.plannedDayOffset == 1)
    #expect(lunch.startMinutes == 12 * 60 + 30)
    #expect(lunch.estimatedMinutes == 60)
    // Lists and tags beside Vietnamese details.
    let list = LorvexCaptureParser.parse(
      "Mua đồ #Nhà ngày mai", lists: [.init(id: "L1", name: "Nhà")], todayWeekday: 3, today: "2026-09-22",
      languages: ["vi"])
    #expect(list.listName == "Nhà")
    #expect(list.plannedDayOffset == 1)
    #expect(list.title == "Mua đồ")
    let tag = parse("Mua đồ hôm nay #việcnhà")
    #expect(tag.tags == ["việcnhà"])
    #expect(tag.plannedDayOffset == 0)
    #expect(tag.title == "Mua đồ")
    let tagFirst = parse("#việc Họp ngày mai lúc 3 giờ")
    #expect(tagFirst.tags == ["việc"])
    #expect(tagFirst.plannedDayOffset == 1)
    #expect(tagFirst.startMinutes == 15 * 60)
    #expect(tagFirst.title == "Họp")
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Names and nouns made of a day word, a time word, or a number word.
        "Họp Mai", "Mai Anh đi học", "Hoa mai nở", "Cây mai vàng", "Gặp Mai", "Gặp mai", "Mốt Hoàng đến chơi",
        "Gặp Tuấn", "Tôi đi chợ", "Tôi muốn học", "Họp đem laptop", "Đếm hàng tồn kho", "Chợ đêm",
        "Tối ưu hóa", "Chiều cao", "Sáng tạo nội dung", "Giờ làm việc", "Giờ cao điểm", "Giờ học tiếng Anh",
        // Ordinals, orders, ranks, and the language.
        "Thứ hạng", "Hạng thứ 2", "Lần thứ hai", "Lần thứ ba", "Màn hình thứ hai", "Bài thứ sáu", "Tầng thứ tư",
        "Thứ tự ưu tiên của dự án", "Xếp thứ tự các bài", "Học tiếng Anh", "Dịch sang tiếng Anh",
        // A watch or a clock is no hours amount.
        "Mua đồng hồ", "Sửa đồng hồ báo thức", "Mua 2 đồng hồ",
        // Numbers that are counts, places, and amounts.
        "Mua 3 cái áo", "Mua 2 kg gạo", "Chạy 5 km", "Phòng 15", "Tầng 3", "Bài 3", "Chương 3", "Trang 15", "Sprint 12",
        "Giá 15 nghìn", "Đọc 30 trang", "Đặt vé cho 3 người", "Ở lại 3 ngày", "Nghỉ phép 2 ngày", "Đi 2 người",
        "Số điện thoại 090 123 4567", "Còn 3 ngày nữa là Tết",
      ], languages: ["vi"])
    // A line that opens with a time keeps the rest as the title.
    let lead = parse("Lúc 5 giờ thuyết trình")
    #expect(lead.startMinutes == 17 * 60)
    #expect(lead.title == "thuyết trình")
  }

  @Test("A hyphen joins a compound that is no day, and extra spaces or punctuation between details change nothing")
  func hyphensAndSpacing() {
    expectLinesUnread(["Họp tối-nay", "Họp ngày-mai", "Họp hôm-nay", "Họp thứ-Sáu"], languages: ["vi"])
    let spaced = parse("Họp   lúc   15h")
    #expect(spaced.startMinutes == 15 * 60)
    #expect(spaced.title == "Họp")
    let wide = parse("Họp ngày   mai")
    #expect(wide.plannedDayOffset == 1)
    #expect(wide.title == "Họp")
    let tabbed = parse("Họp mỗi\tthứ Hai")
    #expect(tabbed.recurrence == monday)
    #expect(tabbed.title == "Họp")
    for text in ["Họp ngày mai, lúc 15h", "Họp ngày mai; lúc 15h"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "Họp", "\(text): title")
    }
  }

  @Test("Capitals read like lowercase letters, and the title keeps the capitals it was typed with")
  func capitals() {
    let lines: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("HỌP NGÀY MAI", "HỌP", { $0.plannedDayOffset == 1 }),
      ("BÁO CÁO THỨ BẢY", "BÁO CÁO", { $0.plannedDayOffset == 4 }),
      ("HỌP LÚC 3 GIỜ CHIỀU", "HỌP", { $0.startMinutes == 15 * 60 }),
      ("HỌP 15H30", "HỌP", { $0.startMinutes == 15 * 60 + 30 }),
      ("HỌP 9:30 SA", "HỌP", { $0.startMinutes == 9 * 60 + 30 }),
      ("NỘP BÀI TRƯỚC THỨ SÁU", "NỘP BÀI", { $0.dueDayOffset == 3 }),
      ("NỘP BÀI TRƯỚC 15 THÁNG 10", "NỘP BÀI", { $0.dueDayOffset == 23 }),
      ("KHÁM BỆNH NGÀY 15 THÁNG 10", "KHÁM BỆNH", { $0.plannedDayOffset == 23 }),
      ("TẬP GYM MỖI THỨ HAI", "TẬP GYM", { $0.recurrence == monday }),
      ("TẬP GYM MỖI NGÀY LÀM VIỆC", "TẬP GYM", { $0.recurrence == workdays }),
      ("BÁO CÁO HÀNG THÁNG", "BÁO CÁO", { $0.recurrence == monthly }),
      ("HỌP 2 TIẾNG", "HỌP", { $0.estimatedMinutes == 120 }),
      ("HỌP NỬA TIẾNG", "HỌP", { $0.estimatedMinutes == 30 }),
      ("BÁO CÁO QUAN TRỌNG", "BÁO CÁO", { $0.priority == .p1 }),
      ("BÁO CÁO ƯU TIÊN THẤP", "BÁO CÁO", { $0.priority == .p3 }),
      ("Họp Chủ Nhật", "Họp", { $0.plannedDayOffset == 5 }),
      ("Họp Thứ Sáu", "Họp", { $0.plannedDayOffset == 3 }),
      ("Báo cáo THỨ SÁU 15h", "Báo cáo", { $0.plannedDayOffset == 3 && $0.startMinutes == 15 * 60 }),
      ("Báo cáo CHỦ NHẬT SÁNG", "Báo cáo", { $0.plannedDayOffset == 5 }),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(line.check(parsed), "\(line.text)")
      #expect(sameScalars(parsed.title, line.title), "\(line.text): title")
    }
  }

  // MARK: - Tone marks, the stroke of đ, and how marks are typed

  @Test(
    "A line reads the same with every mark, with the stroke of đ written d, with the marks as combining characters, and with no mark",
    .timeLimit(.minutes(5)))
  func spellings() {
    let forms: [(name: String, form: (String) -> String)] = [
      ("stroke-less", strokeless), ("decomposed", decomposed), ("composed", composed), ("toneless", toneless),
    ]
    for text in spellingLines {
      let reference = parse(text)
      let reading = Reading(reference)
      for (name, form) in forms {
        let parsed = parse(form(text))
        #expect(Reading(parsed) == reading, "\(name): \(text)")
        #expect(sameScalars(parsed.title, form(reference.title)), "\(name): \(text): title")
        #expect(parsed.phrases.count == reference.phrases.count, "\(name): \(text): phrase count")
        for (phrase, expected) in zip(parsed.phrases, reference.phrases) {
          #expect(sameScalars(phrase.text, form(expected.text)), "\(name): \(text): phrase")
        }
      }
    }
  }

  @Test("A few phrases typed with no marks stay unread, because their toneless spelling is another everyday word")
  func tonelessUnsafeForms() {
    // Without marks these are read as other words, so the phrase stays in the title: "mốt" is "một" (one),
    // "cho" (for) opens a bound at a period, "gấp" is "gặp" (to meet), "khẩn" has no toneless reading, and
    // "tư" (Wednesday) is "tu".
    expectLinesUnread(
      [
        "Hop ngay mot", "Di cho cuoi tuan", "Nop bao cao gap", "Nop bao cao khan", "Gap: nop bao cao",
        "Rat gap: nop bao cao", "Hop thu Tu tuan nay", "Hop thu Tu",
      ], languages: ["vi"])
    // Typed with their marks the same phrases read.
    #expect(parse("Họp ngày mốt").plannedDayOffset == 2)
    #expect(parse("Đi chợ cuối tuần").plannedDayOffset == 4)
    #expect(parse("Nộp báo cáo gấp").priority == .p1)
    #expect(parse("Nộp báo cáo khẩn").priority == .p1)
    #expect(parse("Họp thứ Tư tuần này").plannedDayOffset == 1)
    #expect(parse("Họp thứ Tư").plannedDayOffset == 1)
    // "Toi" beside "thu Sau" is the evening of Friday, so "tới thứ Sáu" typed with no marks plans the day.
    let evening = parse("Nop bao cao toi thu Sau")
    #expect(evening.plannedDayOffset == 3)
    #expect(evening.dueDayOffset == nil)
    // "Dung" after an hour stays in the title.
    let exact = parse("Hop 3 gio dung")
    #expect(exact.startMinutes == 15 * 60)
    #expect(exact.title == "Hop dung")
    // "Sau" in "thu Sau" is Friday, never "after", and "dem" is the night only at the end of the phrase.
    #expect(parse("Hop thu Sau tuan sau").plannedDayOffset == 10)
    #expect(parse("Nop bai truoc thu Sau tuan sau").dueDayOffset == 10)
    #expect(parse("Hop 8 gio dem").startMinutes == 20 * 60)
    #expect(parse("Hop 8 gio dem laptop").startMinutes == 8 * 60)
    #expect(parse("Hop 8 gio dem laptop").title == "Hop dem laptop")
  }

  @Test("Each word is read in one whole spelling, and a line may mix the spellings")
  func mixedSpellings() {
    let bare = parse("Họp ngay mai luc 3 gio chieu")
    #expect(bare.plannedDayOffset == 1)
    #expect(bare.startMinutes == 15 * 60)
    #expect(bare.title == "Họp")
    let marked = parse("Hop ngày mai lúc 3 giờ chiều")
    #expect(marked.plannedDayOffset == 1)
    #expect(marked.startMinutes == 15 * 60)
    #expect(marked.title == "Hop")
    let halfway = parse("Họp thu Sáu tuần sau")
    #expect(halfway.plannedDayOffset == 10)
    #expect(halfway.title == "Họp")
  }

  @Test("A word typed with some of its marks is not that word: đem, tôi, Tuấn, mải, and tư")
  func homographs() {
    // The words read with their marks.
    for (text, check) in [
      ("Họp đêm nay", { (parsed: LorvexCaptureParse) in parsed.plannedDayOffset == 0 }),
      ("Họp tối nay", { $0.plannedDayOffset == 0 }), ("Nộp bài tới thứ Sáu", { $0.dueDayOffset == 3 }),
      ("Họp tuần sau", { $0.plannedDayOffset == 7 }), ("Họp nửa tiếng", { $0.estimatedMinutes == 30 }),
      ("Họp ngày mốt", { $0.plannedDayOffset == 2 }), ("Họp thứ Sáu", { $0.plannedDayOffset == 3 }),
      ("Họp thứ Tư", { $0.plannedDayOffset == 1 }), ("Họp ngày mai", { $0.plannedDayOffset == 1 }),
      ("Họp 8 giờ đêm", { $0.startMinutes == 20 * 60 }), ("Họp 8 giờ đem laptop", { $0.startMinutes == 8 * 60 }),
    ] as [(String, (LorvexCaptureParse) -> Bool)] {
      #expect(check(parse(text)), "\(text)")
    }
    // The neighbours typed with other marks stay in the title.
    expectLinesUnread(
      [
        "Họp đem laptop", "Tôi đi chợ", "Tôi muốn học", "Gặp Tuấn", "Họp mải mê", "Họp một giờ", "Thứ tự ưu tiên",
        "Họp 2 tiếng nữa", "Tư vấn khách hàng", "Họp tuấn sau", "Đem sách đến lớp",
      ], languages: ["vi"])
  }

  @Test("The stroke of đ may be typed as d while the other marks stay")
  func strokeOfD() {
    for (text, title, check) in [
      ("Họp dêm nay", "Họp", { (parsed: LorvexCaptureParse) in parsed.plannedDayOffset == 0 }),
      ("Nộp bài dến thứ Sáu", "Nộp bài", { $0.dueDayOffset == 3 }),
      ("Họp từ 3 giờ dến 5 giờ chiều", "Họp", { $0.startMinutes == 15 * 60 && $0.estimatedMinutes == 120 }),
      ("Họp 2 giờ dồng hồ", "Họp", { $0.estimatedMinutes == 120 }),
      ("Họp nửa dêm", "Họp", { $0.plannedDayOffset == 1 && $0.startMinutes == 0 }),
      ("Họp dúng 3 giờ", "Họp", { $0.startMinutes == 15 * 60 }),
      ("Họp dêm mai", "Họp", { $0.plannedDayOffset == 1 }),
    ] as [(String, String, (LorvexCaptureParse) -> Bool)] {
      let parsed = parse(text)
      #expect(check(parsed), "\(text)")
      #expect(parsed.title == title, "\(text): title")
    }
  }

  @Test("A letter's marks may be typed composed, as combining characters, half composed, or in the other order")
  func combiningCharacters() {
    // "tuần" is tu + a + circumflex + grave; "thứ" is th + u + horn + acute.
    let weeks = [
      "tu\u{1EA7}n", "tua\u{0302}\u{0300}n", "tu\u{00E2}\u{0300}n", "tu\u{00E0}\u{0302}n", "tua\u{0300}\u{0302}n",
    ]
    for week in weeks {
      let parsed = parse("Họp \(week) sau")
      #expect(parsed.plannedDayOffset == 7, "\(week.unicodeScalars.map(\.value))")
      #expect(parsed.title == "Họp", "\(week.unicodeScalars.map(\.value)): title")
    }
    let fridays = [
      "th\u{1EE9} S\u{00E1}u", "thu\u{031B}\u{0301} Sa\u{0301}u", "th\u{01B0}\u{0301} S\u{00E1}u",
      "th\u{00FA}\u{031B} Sa\u{0301}u", "thu\u{0301}\u{031B} Sa\u{0301}u",
    ]
    for friday in fridays {
      let parsed = parse("Họp \(friday)")
      #expect(parsed.plannedDayOffset == 3, "\(friday.unicodeScalars.map(\.value))")
      #expect(parsed.title == "Họp", "\(friday.unicodeScalars.map(\.value)): title")
    }
    // The title and the phrase keep the characters they were typed with.
    let composedLine = parse("Gọi mẹ ngày mai")
    #expect(sameScalars(composedLine.title, "Gọi mẹ"))
    #expect(sameScalars(composedLine.phrases[0].text, "ngày mai"))
    let combining = parse(decomposed("Gọi mẹ ngày mai"))
    #expect(combining.plannedDayOffset == 1)
    #expect(sameScalars(combining.title, decomposed("Gọi mẹ")))
    #expect(sameScalars(combining.phrases[0].text, decomposed("ngày mai")))
    let bare = parse("Goi me ngay mai")
    #expect(bare.plannedDayOffset == 1)
    #expect(sameScalars(bare.title, "Goi me"))
    // A character outside the Basic Multilingual Plane before a phrase moves nothing.
    let emoji = parse("🎉 Họp ngày mai")
    #expect(emoji.plannedDayOffset == 1)
    #expect(emoji.title == "🎉 Họp")
    let decomposedEmoji = parse("🎉 " + decomposed("Họp ngày mai lúc 3 giờ chiều"))
    #expect(decomposedEmoji.plannedDayOffset == 1)
    #expect(decomposedEmoji.startMinutes == 15 * 60)
    #expect(sameScalars(decomposedEmoji.title, "🎉 " + decomposed("Họp")))
  }

  @Test("Capital letters with marks read like lowercase ones, with the stroke, and with no marks")
  func capitalizedMarks() {
    for (text, title, check) in [
      ("HỌP ĐÊM NAY", "HỌP", { (parsed: LorvexCaptureParse) in parsed.plannedDayOffset == 0 }),
      ("NỘP BÀI ĐẾN THỨ SÁU", "NỘP BÀI", { $0.dueDayOffset == 3 }),
      ("HỌP 2 GIỜ ĐỒNG HỒ", "HỌP", { $0.estimatedMinutes == 120 }),
      ("HỌP NỬA ĐÊM", "HỌP", { $0.plannedDayOffset == 1 && $0.startMinutes == 0 }),
      ("Họp Đêm Nay", "Họp", { $0.plannedDayOffset == 0 }), ("Họp Thứ Sáu Tuần Sau", "Họp", { $0.plannedDayOffset == 10 }),
      ("HOP NGAY MAI", "HOP", { $0.plannedDayOffset == 1 }), ("HOP THU SAU", "HOP", { $0.plannedDayOffset == 3 }),
      ("NOP BAI TRUOC THU SAU", "NOP BAI", { $0.dueDayOffset == 3 }),
    ] as [(String, String, (LorvexCaptureParse) -> Bool)] {
      let parsed = parse(text)
      #expect(check(parsed), "\(text)")
      #expect(sameScalars(parsed.title, title), "\(text): title")
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Vietnamese, English lines read as they do alone, and an hour written with h is a clock time")
  func besideEnglish() {
    // English lines read the same with Vietnamese beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Call mom tonight",
      "Dinner tomorrow evening", "Meeting at 9:30", "Walk 45 min every day", "Call Tom in 15 min",
      "Call Tom after 5pm", "Report due tomorrow", "Lunch Friday noon", "Meeting at 3 pm tomorrow",
      "Call Anh tomorrow", "Meet Mai on Friday", "Pay tax by 15 Oct", "Sprint 12 - 20 May", "Mai Anh 3pm",
      "Học tiếng Anh tomorrow",
    ] {
      for languages in [["en", "vi"], ["vi", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Vietnamese writes its hours with "h", so beside it "15h" and "2h" are clock times. English alone
    // reads them as lengths.
    for languages in [["en", "vi"], ["vi", "en"]] {
      let study = parse("Study 2h", languages: languages)
      #expect(study.startMinutes == 14 * 60, "\(languages)")
      #expect(study.estimatedMinutes == nil, "\(languages)")
      #expect(study.title == "Study", "\(languages)")
      let meet = parse("Meet at 15h", languages: languages)
      #expect(meet.startMinutes == 15 * 60, "\(languages)")
      #expect(meet.estimatedMinutes == nil, "\(languages)")
      let hour = parse("Meet 10h", languages: languages)
      #expect(hour.startMinutes == 10 * 60, "\(languages)")
      #expect(hour.estimatedMinutes == nil, "\(languages)")
      let report = parse("Write the report 2h", languages: languages)
      #expect(report.startMinutes == 14 * 60, "\(languages)")
      #expect(report.title == "Write the report", "\(languages)")
      let vietnamese = parse("Họp 15h", languages: languages)
      #expect(vietnamese.startMinutes == 15 * 60, "\(languages)")
      #expect(vietnamese.estimatedMinutes == nil, "\(languages)")
      #expect(vietnamese.title == "Họp", "\(languages)")
      // A count of hours with minutes or a decimal is still a length.
      #expect(parse("Run 1h30m", languages: languages).estimatedMinutes == 90, "\(languages)")
      #expect(parse("Read 1.5h", languages: languages).estimatedMinutes == 90, "\(languages)")
      #expect(parse("Họp 1,5h", languages: languages).estimatedMinutes == 90, "\(languages)")
      #expect(parse("Học 1h30m", languages: languages).estimatedMinutes == 90, "\(languages)")
      #expect(parse("Họp 3pm", languages: languages).startMinutes == 15 * 60, "\(languages)")
    }
    let english = parse("Study 2h", languages: ["en"])
    #expect(english.estimatedMinutes == 120)
    #expect(english.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    // A line may mix both languages.
    let mixed = parse("Call mom ngày mai at 3pm", languages: ["en", "vi"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting thứ Sáu at 3pm", languages: ["en", "vi"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Họp tomorrow").plannedDayOffset == 1)
    let review = parse("Review ngày mai lúc 15h for 2 hours", languages: ["en", "vi"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english3pm = parse("Báo cáo ngày mai 3pm")
    #expect(english3pm.plannedDayOffset == 1)
    #expect(english3pm.startMinutes == 15 * 60)
    #expect(english3pm.title == "Báo cáo")
    #expect(parse("Họp 30 min").estimatedMinutes == 30)
    #expect(parse("Báo cáo ngày mai 17:30").startMinutes == 17 * 60 + 30)
    // Vietnamese typed with no marks beside English reads too.
    let toneless = parse("Buy 3 gio chieu", languages: ["en", "vi"])
    #expect(toneless.startMinutes == 15 * 60)
    #expect(toneless.title == "Buy")
  }

  @Test("Beside Indonesian or Malay, each language keeps its own words")
  func besideIndonesianAndMalay() {
    for languages in [["vi", "id"], ["id", "vi"], ["vi", "ms"], ["ms", "vi"], ["vi", "id", "ms"], ["ms", "id", "vi"]] {
      // Vietnamese's own words.
      let vietnamese = parse("Họp ngày mai lúc 3 giờ chiều", languages: languages)
      #expect(vietnamese.plannedDayOffset == 1, "\(languages)")
      #expect(vietnamese.startMinutes == 15 * 60, "\(languages)")
      #expect(vietnamese.title == "Họp", "\(languages)")
      #expect(parse("Báo cáo quan trọng", languages: languages).priority == .p1, "\(languages)")
      #expect(parse("Họp 30 phút", languages: languages).estimatedMinutes == 30, "\(languages)")
      #expect(parse("Tập gym mỗi thứ Hai", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Báo cáo cuối tuần", languages: languages).plannedDayOffset == 4, "\(languages)")
      #expect(parse("Nộp bài trước thứ Sáu", languages: languages).dueDayOffset == 3, "\(languages)")
      #expect(parse("Họp thứ Sáu tuần sau", languages: languages).plannedDayOffset == 10, "\(languages)")
      #expect(parse("Họp tuần sau", languages: languages).plannedDayOffset == 7, "\(languages)")
      // Indonesian's own words.
      if languages.contains("id") {
        let indonesian = parse("Rapat besok jam 3 sore", languages: languages)
        #expect(indonesian.plannedDayOffset == 1, "\(languages)")
        #expect(indonesian.startMinutes == 15 * 60, "\(languages)")
        #expect(indonesian.title == "Rapat", "\(languages)")
        #expect(parse("Laporan akhir pekan", languages: languages).plannedDayOffset == 4, "\(languages)")
        #expect(parse("Laporan prioritas tinggi", languages: languages).priority == .p1, "\(languages)")
        #expect(parse("Rapat 30 menit", languages: languages).estimatedMinutes == 30, "\(languages)")
        #expect(parse("Lari setiap Senin", languages: languages).recurrence == monday, "\(languages)")
        #expect(parse("Rapat tanggal 5 Oktober", languages: languages).plannedDayOffset == 13, "\(languages)")
      }
      // Malay's own words.
      if languages.contains("ms") {
        let malay = parse("Mesyuarat esok pukul 3 petang", languages: languages)
        #expect(malay.plannedDayOffset == 1, "\(languages)")
        #expect(malay.startMinutes == 15 * 60, "\(languages)")
        #expect(malay.title == "Mesyuarat", "\(languages)")
        #expect(parse("Laporan hujung minggu", languages: languages).plannedDayOffset == 4, "\(languages)")
        #expect(parse("Senaman setiap Isnin", languages: languages).recurrence == monday, "\(languages)")
        #expect(parse("Rapat 30 minit", languages: languages).estimatedMinutes == 30, "\(languages)")
        #expect(parse("Laporan 5hb", languages: languages).plannedDayOffset == 13, "\(languages)")
      }
    }
  }

  @Test("Lines in other languages read the same with Vietnamese beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("Appeler maman demain à 15h", "fr"), ("Réunion tous les lundis à 9h", "fr"),
      ("Rapport avant vendredi", "fr"), ("Lire 30 min", "fr"), ("Réunion de 14h à 16h", "fr"),
      ("Vacances du 3 au 5 mai", "fr"), ("Courses ce soir à 19h", "fr"), ("Dentiste après-demain", "fr"),
      ("Payer le loyer le 5 de chaque mois", "fr"), ("Vacances 15 mai", "fr"), ("Dentiste 3 mai à 15h", "fr"),
      ("Réunion mai", "fr"), ("Anniversaire de Mai", "fr"), ("Llamar a mamá mañana a las 15:00", "es"),
      ("Gimnasio cada lunes", "es"), ("Informe antes del viernes", "es"),
      ("Reunión a las 3 de la tarde", "es"), ("Vacaciones del 3 al 5 de mayo", "es"),
      ("Leer 30 minutos", "es"), ("Dentista mañana por la tarde", "es"),
      ("Ligar para a mãe amanhã às 15h", "pt"), ("Relatório até sexta", "pt"), ("Academia toda segunda", "pt"),
      ("Ler 30 minutos", "pt"), ("Chiamare mamma domani alle 15:00", "it"), ("Palestra ogni lunedì", "it"),
      ("Relazione entro venerdì", "it"), ("Leggere 30 minuti", "it"), ("Non mai", "it"),
      ("Zadzwonić jutro o 15:00", "pl"), ("Siłownia co poniedziałek", "pl"), ("Raport do piątku", "pl"),
      ("Czytać 30 minut", "pl"), ("Zahnarzt übermorgen", "de"), ("Meeting um 15 Uhr", "de"),
      ("Sport jeden Montag", "de"), ("Bericht bis Freitag", "de"), ("Urlaub vom 3. bis 5. Mai", "de"),
      ("Zahnarzt am Freitag", "de"), ("Meeting um 15h", "de"), ("Lesen 2h", "de"), ("Tandarts morgen", "nl"),
      ("Sporten elke maandag", "nl"), ("Rapport voor vrijdag", "nl"), ("Dentist poimâine", "ro"),
      ("Alergare în fiecare luni", "ro"), ("Ședință la ora 15", "ro"), ("Raport până vineri", "ro"),
      ("Vacanță de la 3 la 5 mai", "ro"), ("Raport sau altceva", "ro"), ("Rapat besok jam 3 sore", "id"),
      ("Laporan hari Minggu", "id"), ("Laporan akhir pekan", "id"), ("Rapat 30 menit", "id"),
      ("Lari setiap Senin", "id"), ("Rapat tanggal 5 Oktober", "id"), ("Laporan prioritas tinggi", "id"),
      ("Rapat setengah empat", "id"), ("Mesyuarat esok pukul 3 petang", "ms"), ("Laporan hujung minggu", "ms"),
      ("Senaman setiap Isnin", "ms"), ("Rapat 30 minit", "ms"), ("Laporan 5hb", "ms"),
      ("Mesyuarat pukul tiga setengah", "ms"), ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"),
      ("אימון כל יום שני", "he"), ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"),
      ("تماس با مادر فردا ساعت ۳ بعدازظهر", "fa"), ("امی کو فون کرنا کل شام 5 بجے", "ur"),
      ("कल शाम 5 बजे मीटिंग", "hi"), ("Позвонить маме завтра в 15:00", "ru"),
      ("Подзвонити мамі завтра о 15:00", "uk"), ("明日の午後3時に会議", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "vi"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["vi", line.language]) == alone, "\(line.text): reversed")
    }
    // Vietnamese lines read the same with any other language beside them.
    let vietnameseLines = [
      "Họp ngày mai lúc 3 giờ chiều", "Họp thứ Sáu tuần sau", "Tập gym mỗi thứ Hai", "Nộp bài trước 15 tháng 10",
      "Họp 30 phút", "Báo cáo quan trọng", "Họp từ 3 giờ đến 5 giờ chiều", "Họp cuối tuần",
    ]
    for language in [
      "fr", "es", "it", "pt", "pl", "de", "nl", "ro", "ru", "uk", "he", "ar", "fa", "ur", "hi", "ja", "ko", "zh", "id",
      "ms",
    ] {
      for text in vietnameseLines {
        let alone = parse(text, languages: ["vi"])
        #expect(Reading(parse(text, languages: [language, "vi"])) == Reading(alone), "\(text) \(language)")
        #expect(Reading(parse(text, languages: ["vi", language])) == Reading(alone), "\(text) \(language): reversed")
      }
    }
    // A line may mix Vietnamese with another language.
    for languages in [["fr", "vi"], ["vi", "fr"]] {
      let mixed = parse("Appeler maman ngày mai lúc 3 giờ chiều", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Appeler maman demain à 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Họp ngày mai", languages: languages).plannedDayOffset == 1, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste 3 mai", languages: languages).plannedDayOffset == captureDayOffset("2027-05-03"), "\(languages)")
      #expect(parse("Tập gym mỗi thứ Hai", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
    }
    #expect(parse("Họp 下午3点 ngày mai", languages: ["zh", "vi"]).plannedDayOffset == 1)
    #expect(parse("Họp מחר", languages: ["he", "vi"]).plannedDayOffset == 1)
    // "Mai" is the day after "ngày" in Vietnamese and the month of May in French, Spanish, Italian, and
    // Portuguese, and each language keeps its own reading.
    for language in ["fr", "es", "it", "pt", "ro", "de", "nl", "pl"] {
      for languages in [[language, "vi"], ["vi", language]] {
        #expect(parse("Họp ngày mai", languages: languages).plannedDayOffset == 1, "\(languages)")
        #expect(parse("Họp Mai", languages: languages).plannedDayOffset == nil, "\(languages)")
      }
    }
  }

  @Test("Vietnamese words are read only for a user who reads Vietnamese")
  func languageGate() {
    let line = parse("Họp ngày mai", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Họp ngày mai")
    for languages in [["vi"], ["vi-VN"], ["vi_VN"], ["en-US", "vi-VN"], ["VI"], ["vi-Latn-VN"]] {
      #expect(parse("Họp ngày mai", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Vietnamese reader.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen", "Dentist poimâine", "Rapat besok", "Lari setiap Senin",
        "Mesyuarat esok", "Laporan prioritas tinggi", "Rapat 30 menit",
      ], languages: ["vi"])
    // Vietnamese words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"], ["ro"], ["ar"], ["id"], ["ms"]] {
      let parsed = parse("Họp ngày mai", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Họp ngày mai", "\(languages): title")
      #expect(parse("Tập gym mỗi thứ Hai", languages: languages).recurrence == nil, "\(languages): repeat")
      #expect(parse("Nộp báo cáo quan trọng", languages: languages).priority == nil, "\(languages): priority")
      #expect(parse("Họp thứ Sáu", languages: languages).plannedDayOffset == nil, "\(languages): weekday")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let tokens = [
      "Họp ngày mai ", "họp ", "3 giờ ", "mỗi thứ Hai, ", "thứ Hai và thứ Tư và ", "ngày 5 ", "1,5 giờ ", "1", "từ 3 giờ đến ",
      "chiều ", "mai ", "tối ", "ngày ", "tháng ", "15/10 ", "15 tháng 10 ", "e\u{0302}\u{0301}", "a", "trước ", "đến ",
      "hạn ", "lúc ", "mỗi ", "thứ ", "tuần ", "sau ", "giờ ", "phút ", "tiếng ", "một ", "2 tiếng 30 phút ",
      "3 giờ kém 15 ", "Họp 3pm ", "quan trọng ", "ưu tiên ", "khẩn ", "cách ", "các ngày ", "ngày làm việc ",
      "thứ 2, 4, ", "từ ngày 3 đến ngày 5 tháng 5 ", "17h30 ", "8 giờ tối mai ", "nửa đêm ", "đêm ", "nay ", "kém ",
      "rưỡi ", "3 giờ rưỡi ", "chiều thứ Sáu ", "tuần sau thứ Sáu ", "cuối tuần ", "mỗi cuối tuần ", "hằng tuần ",
      "hàng ngày ", "2 ngày một lần ", "cách ngày ", "từ thứ Hai đến thứ Sáu ", "mỗi thứ Hai đến thứ Sáu ",
      "trước thứ Sáu ", "hạn chót ", "chậm nhất ", "đến hết ", "trước 17h ", "15/10/2026 ", "3-5 tháng 5 ",
      "từ 3 đến 5 tháng 5 ", "ba ngày nữa ", "sau 3 ngày ", "mười lăm phút ", "ba mươi phút ", "nửa tiếng ",
      "1 tiếng rưỡi ", "mất 2 giờ ", "khoảng 30 phút ", "2 giờ đồng hồ ", "trong 2 tiếng ", "mỗi 2 giờ ",
      "ưu tiên cao ", "rất gấp ", "không gấp ", "âm lịch ", "mùng 5 ", "ngày thứ ", "Thứ Sáu đen ", "Chủ nhật ",
      "thứ Bảy và Chủ nhật ", "9:30 SA ", "3:30 CH ", "mỗi ngày làm việc ", "hai mươi lăm ", "mười hai giờ ",
      "tầm ", "khoảng ", "đúng ", "buổi ", "vào ", "các ", "mọi ", "ngày kia ", "ngày mốt ", "cho đến ",
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for token in tokens {
        let line = "An " + String(repeating: token, count: max(1, 5000 / token.count)) + " gọi"
        let each = clock.measure {
          let parsed = parse(line)
          #expect(!parsed.title.isEmpty, "\(token)")
        }
        #expect(each < .seconds(2), "\(token) took \(each)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}

/// Lines of every kind of detail that read the same typed with every mark, with the stroke of đ written d,
/// with the marks as combining characters, and with no mark at all.
private let spellingLines: [String] = [
  "Họp nhóm hôm nay", "Gọi mẹ tối nay", "Nộp báo cáo sáng mai", "Mua quà chiều mai", "Họp ngày mai",
  "Đi khám ngày kia", "Họp thứ Hai", "Họp thứ Ba tuần sau", "Họp thứ Sáu tuần này",
  "Họp chiều thứ Sáu", "Họp thứ Sáu chiều", "Họp Chủ nhật", "Họp thứ 2", "Họp tuần sau",
  "Họp 3 ngày nữa", "Họp sau 3 ngày", "Họp 1 tuần nữa", "Họp thứ Bảy và Chủ nhật", "Họp hôm qua",
  "Họp tuần trước", "Họp thứ Hai tuần trước", "Họp thứ Hai và thứ Tư", "Nộp bài tháng sau",
  "Khám bệnh 15 tháng 10", "Khám bệnh ngày 15 tháng 10", "Khám bệnh 15 thg 10", "Khám bệnh 15/10",
  "Khám bệnh ngày 15/10", "Khám bệnh 15-10-2026", "Khám bệnh 15/10/2026", "Trả tiền nhà ngày 5",
  "Du lịch từ ngày 3 đến ngày 5 tháng 5", "Du lịch từ 3 đến 5 tháng 10", "Du lịch 3-5 tháng 10",
  "Họp lúc 3 giờ chiều", "Họp 3h chiều", "Họp 15h", "Họp 15h30", "Họp 15:30", "Họp 15 giờ 30",
  "Họp 3 giờ rưỡi", "Họp 3 giờ 15", "Họp 3 giờ kém 15", "Họp 3 giờ kém 10", "Họp 8 giờ tối",
  "Họp 7 giờ sáng", "Họp 12 giờ trưa", "Họp 12 giờ đêm", "Họp nửa đêm", "Họp 3 giờ", "Họp lúc 3 giờ",
  "Họp 9 giờ", "Họp tối nay 8 giờ", "Họp 8 giờ tối mai", "Họp từ 3 giờ đến 5 giờ chiều",
  "Họp 3-5 giờ chiều", "Họp từ 14h đến 16h", "Họp 14:00-16:00", "Ăn tối 7 giờ",
  "Họp 3 giờ chiều ngày mai", "Đọc sách 30 phút", "Chạy bộ 1 giờ", "Chạy bộ 1 tiếng",
  "Chạy bộ 1,5 giờ", "Chạy bộ 1 tiếng rưỡi", "Chạy bộ nửa tiếng", "Chạy bộ nửa giờ", "Chạy bộ 45 phút",
  "Chạy bộ 1 giờ 30 phút", "Họp mất 2 giờ", "Họp 2 giờ đồng hồ", "Họp 2 tiếng tối đa",
  "Tập yoga mỗi ngày", "Tập yoga hằng ngày", "Tập yoga hàng ngày", "Họp mỗi thứ Hai",
  "Báo cáo hằng tuần", "Báo cáo hàng tuần", "Báo cáo mỗi tuần", "Uống thuốc mỗi 2 ngày",
  "Uống thuốc 2 ngày một lần", "Dọn nhà cách ngày", "Trả tiền nhà mỗi tháng",
  "Trả tiền nhà hàng tháng", "Gia hạn mỗi năm", "Gia hạn hàng năm", "Tập gym mỗi ngày làm việc",
  "Tập gym vào các ngày làm việc", "Tập gym các ngày trong tuần", "Dọn nhà mỗi cuối tuần",
  "Đi bơi mỗi thứ Ba và thứ Năm", "Họp thứ Hai hàng tuần", "Họp mỗi thứ 2, 4, 6",
  "Họp mỗi thứ Hai đến thứ Sáu", "Tập gym 2 lần một tuần", "Uống nước mỗi 2 giờ",
  "Nộp báo cáo trước thứ Sáu", "Nộp báo cáo hạn thứ Sáu", "Nộp báo cáo hạn chót thứ Sáu",
  "Nộp báo cáo deadline thứ Sáu", "Nộp báo cáo đến thứ Sáu", "Nộp báo cáo trước 5 giờ chiều",
  "Nộp báo cáo trước thứ Sáu 5 giờ chiều", "Nộp báo cáo hạn 15 tháng 10", "Nộp báo cáo khẩn cấp",
  "Nộp báo cáo quan trọng", "Nộp báo cáo ưu tiên cao", "Nộp báo cáo ưu tiên thấp",
  "Nộp báo cáo không gấp", "Họp Mai", "Mai đi chợ", "Thứ tự ưu tiên", "Học tiếng Anh 2 tiếng",
  "Học tiếng Anh", "Màn hình thứ hai", "Gặp Tuấn", "Lần thứ hai", "Tôi đi chợ", "Họp 8 giờ đem laptop",
  "Họp T2", "Meeting 3pm", "Meeting 17:30", "Call 30 min", "Họp 3pm", "Họp lúc 3pm", "Họp 17:30",
  "Họp 2h", "Học 1h30m", "Gặp ngày mai at 5pm", "Họp đêm nay", "Họp sáng nay", "Họp trưa nay",
  "Họp chiều nay", "Họp ngày hôm nay", "Họp trưa mai", "Họp tối mai", "Họp đêm mai",
  "Họp sáng mai lúc 9 giờ", "Họp hôm kia", "Họp tối qua", "Họp sáng qua", "Ăn tối mai", "Ăn tối nay",
  "Ăn trưa mai 12 giờ", "Họp thứ Hai tuần này", "Họp thứ Hai tuần tới", "Họp thứ Sáu tuần sau",
  "Họp cuối tuần này", "Họp cuối tuần sau", "Họp cuối tuần trước", "Họp 2 tuần nữa", "Họp sau 2 tuần",
  "Họp ba ngày nữa", "Họp hai tuần nữa", "Nộp bài tháng tới", "Họp 15 tháng 10 năm 2026",
  "Họp 15 tháng 10 2026", "Họp thứ Sáu 16 tháng 10", "Họp thứ Sáu 16/10", "Họp vào 15/10",
  "Họp 15.10.2026", "Họp 15/10/26", "Họp 5 tháng 3 ngày", "Du lịch từ 3/5 đến 5/5",
  "Du lịch giữa ngày 3 và ngày 5 tháng 10", "Họp lúc 3:30 chiều", "Họp 3:30 CH", "Họp 9:30 SA",
  "Họp 9h sáng", "Họp 9 giờ 30 sáng", "Họp 9h30 sáng", "Họp ba giờ chiều", "Họp lúc ba giờ rưỡi chiều",
  "Họp 3 rưỡi chiều", "Họp lúc 8h tối nay", "Họp 7h tối", "Họp 11 giờ đêm", "Họp 2 giờ đêm",
  "Họp 1 giờ sáng", "Họp 2 giờ trưa", "Họp 12h trưa", "Họp 0h", "Họp 00:00", "Họp khoảng 3 giờ",
  "Họp tầm 3 giờ chiều", "Họp 1 giờ rưỡi", "Họp 15 phút", "Họp ba mươi phút", "Họp 90 phút",
  "Họp 1h30p", "Họp 2 tiếng 30 phút", "Họp 2 tiếng 15", "Họp một tiếng", "Họp một tiếng rưỡi",
  "Họp khoảng 30 phút", "Họp trong 2 tiếng", "Họp sau 30 phút", "Họp 2 tiếng nữa", "Họp mọi thứ Hai",
  "Họp hằng tuần vào thứ Hai", "Họp mỗi thứ Hai và thứ Tư", "Họp mỗi tuần 2 lần", "Họp mỗi 2 tuần",
  "Họp 2 tuần một lần", "Họp cách tuần", "Họp mỗi quý", "Họp mỗi sáng", "Họp mỗi tối",
  "Họp hàng ngày trừ Chủ nhật", "Họp mỗi thứ Hai đầu tiên của tháng", "Họp mỗi ngày 15",
  "Họp ngày 15 hàng tháng", "Nộp bài trước ngày mai", "Nộp bài trước 15/10",
  "Nộp bài trước ngày 15 tháng 10", "Nộp bài hạn ngày mai", "Nộp bài đến hết thứ Sáu",
  "Nộp bài chậm nhất thứ Sáu", "Nộp bài trước thứ Sáu tuần sau", "Nộp bài trước cuối tuần",
  "Nộp bài trước tối nay", "Nộp bài lúc 5 giờ chiều ngày mai", "Báo cáo quan trọng",
  "Tài liệu quan trọng cần nộp", "Nộp báo cáo ưu tiên trung bình", "Nộp báo cáo, ưu tiên 1",
  "Nộp báo cáo ưu tiên: thấp", "Họp thứ Hai lúc 9 giờ sáng hằng tuần",
  "Nộp báo cáo trước thứ Sáu, quan trọng", "Gọi bác sĩ chiều mai 3 giờ 30 phút", "Mua sữa #chợ",
  "Mai Anh đi học", "Hoa mai nở", "Cây mai vàng", "Tối ưu hóa", "Chiều cao", "Sáng tạo nội dung",
  "Thứ hạng", "Giờ làm việc", "Nghỉ phép 2 ngày", "Còn 3 ngày nữa là Tết", "Họp đem laptop",
  "Đếm hàng tồn kho", "Đem sách đến lớp tối nay", "Họp với Mai chiều nay", "Hẹn Mai ngày mai",
  "Gặp Mai", "Gặp mai", "Chiều mai gặp", "Tối nay đi chơi", "Tối ưu hóa mã nguồn", "Tôi muốn học",
  "Thứ tự ưu tiên của dự án", "Xếp thứ tự các bài", "Học tiếng Anh 1 tiếng", "Học tiếng Anh mỗi ngày",
  "Lần thứ ba", "Bài thứ sáu", "Tầng thứ tư", "Giờ học tiếng Anh", "Giờ cao điểm",
  "Mốt Hoàng đến chơi", "Họp một giờ", "Họp lúc một giờ chiều", "Họp lúc ba giờ", "Họp lúc 10 giờ 45",
  "Họp 10h45", "Họp 10:45", "Nộp báo cáo trước 17h", "Họp trước 10 giờ", "Meeting at 3pm",
  "Call mom 30 min", "Họp 3pm ngày mai", "Review PR 17:30", "Họp 2h30", "Học 2h", "Họp T6 3 giờ chiều",
  "Họp CN", "Họp thứ 7", "Họp thứ 7 tuần sau", "Hạng thứ 2", "Khám 5/3", "Nộp ngày 15/10",
  "Họp 10/10/2026 lúc 9 giờ", "Hết hạn 31/12", "Họp lúc 9h sáng thứ Hai tuần sau", "Báo cáo tháng 10",
  "Báo cáo tháng 10 năm 2026", "Họp 2 tháng 10", "Họp 15 tháng 10 lúc 3 giờ chiều", "Đi 2 người",
  "Tập mỗi sáng 30 phút", "Tập thể dục mỗi ngày 30 phút", "Tập thể dục 3 lần một tuần",
  "Uống thuốc ngày 2 lần", "Họp thứ Hai và thứ Năm hằng tuần", "Đi bơi các thứ Ba",
  "Họp mỗi tháng một lần", "Họp mỗi tháng 10", "Khẩn cấp: gọi bác sĩ", "Mua quà quan trọng",
  "Đây là việc quan trọng nhất", "Không quan trọng", "Gấp quần áo", "Họp thứ Ba tuần này",
  "Họp thứ Bảy tuần này", "Họp Chủ nhật tuần này", "Họp Chủ nhật tuần sau", "Họp thứ Sáu 5 giờ chiều",
  "Họp thứ Sáu 5h chiều", "Họp sáng thứ Sáu 9 giờ", "Họp thứ Sáu sáng 9 giờ",
  "Họp 5 giờ chiều thứ Sáu", "Hạn nộp 15 tháng 10 lúc 5 giờ chiều", "Nộp bài trước thứ Sáu 17h",
  "Nộp bài trước 17:00 thứ Sáu", "Họp 8 giờ sáng mai và 3 giờ chiều", "Họp đến 5 giờ",
  "Họp đến hết hôm nay", "Ăn trưa với mẹ 12 giờ rưỡi", "Ngủ trưa 1 giờ", "Đón con 4 giờ 30 chiều",
  "Chạy bộ 5h sáng", "Dậy lúc 5h30", "Họp 24h", "Họp 25 giờ", "Họp 0 giờ 30", "Họp 12 giờ 30 đêm",
  "Họp 12h30 trưa", "Họp 15 giờ 30 phút", "Họp 18h30p", "Họp 18h 30 phút", "Họp 13 giờ 5 phút",
  "Họp 12 giờ 30 phút", "Họp mất 15 giờ 30 phút", "Họp lúc 15 giờ 30 phút",
]
