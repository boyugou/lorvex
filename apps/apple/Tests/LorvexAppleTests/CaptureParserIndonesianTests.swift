import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["id"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["id"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weekly = TaskRecurrenceRule(freq: .weekly)
private let monthly = TaskRecurrenceRule(freq: .monthly)
private let yearly = TaskRecurrenceRule(freq: .yearly)

/// Indonesian capture lines, read for a user whose languages include Indonesian.
@Suite("Capture parser Indonesian")
struct CaptureParserIndonesianTests {
  // MARK: - Days

  @Test("Days: hari ini, besok, lusa, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Dokter gigi besok")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Dokter gigi")
    #expect(line.phrases.map(\.text) == ["besok"])

    let days: [(text: String, offset: Int)] = [
      ("Dokter gigi hari ini", 0), ("Dokter gigi pagi ini", 0), ("Dokter gigi siang ini", 0),
      ("Dokter gigi sore ini", 0), ("Dokter gigi malam ini", 0), ("Dokter gigi nanti siang", 0),
      ("Dokter gigi nanti sore", 0), ("Dokter gigi nanti malam", 0),
      ("Dokter gigi besok", 1), ("Dokter gigi besok pagi", 1), ("Dokter gigi besok siang", 1),
      ("Dokter gigi besok sore", 1), ("Dokter gigi besok malam", 1),
      ("Dokter gigi lusa", 2), ("Dokter gigi lusa pagi", 2), ("Dokter gigi lusa malam", 2),
      ("Dokter gigi 3 hari lagi", 3), ("Dokter gigi tiga hari lagi", 3), ("Dokter gigi dalam 3 hari", 3),
      ("Dokter gigi dalam tiga hari", 3), ("Dokter gigi sehari lagi", 1), ("Dokter gigi seminggu lagi", 7),
      ("Dokter gigi sepekan lagi", 7), ("Dokter gigi dalam seminggu", 7), ("Dokter gigi dalam sepekan", 7),
      ("Dokter gigi 2 minggu lagi", 14), ("Dokter gigi dua minggu lagi", 14), ("Dokter gigi dalam 2 minggu", 14),
      ("Dokter gigi dalam dua pekan", 14), ("Dokter gigi dalam 10 hari", 10), ("Dokter gigi sepuluh hari lagi", 10),
      ("Dokter gigi dua belas hari lagi", 12),
      // The intensifier of a part of the day goes with it.
      ("Dokter gigi besok pagi sekali", 1), ("Dokter gigi lusa malam sekali", 2), ("Dokter gigi Jumat pagi sekali", 3),
      ("Dokter gigi minggu depan", 7), ("Dokter gigi pekan depan", 7),
      ("Dokter gigi akhir pekan", 4), ("Dokter gigi akhir pekan ini", 4), ("Dokter gigi di akhir pekan", 4),
      ("Dokter gigi weekend", 4), ("Dokter gigi weekend ini", 4), ("Dokter gigi akhir pekan depan", 11),
      ("Dokter gigi weekend depan", 11), ("Dokter gigi Sabtu dan Minggu", 4),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Dokter gigi", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Besok dokter gigi")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "dokter gigi")
    let sentence = parse("Besok ada ujian")
    #expect(sentence.plannedDayOffset == 1)
    #expect(sentence.title == "ada ujian")
    // A dinner is a noun until a weekday follows it.
    let dinner = parse("Makan malam Jumat")
    #expect(dinner.plannedDayOffset == 3)
    #expect(dinner.title == "Makan malam")
  }

  @Test("Past days and days that cannot be named are not read")
  func pastAndVagueDays() {
    expectLinesUnread(
      [
        // Past days.
        "Dokter gigi kemarin", "Dokter gigi kemarin lusa", "Dokter gigi kemarin sore", "Dokter gigi Senin lalu",
        "Dokter gigi Selasa lalu", "Dokter gigi Jumat kemarin", "Dokter gigi hari Jumat lalu",
        "Dokter gigi minggu lalu", "Dokter gigi akhir pekan lalu", "Dokter gigi tadi malam",
        "Dokter gigi tadi pagi", "Dokter gigi semalam", "Dokter gigi 2 hari yang lalu", "Dokter gigi 3 hari lalu",
        // "Besok lusa" is tomorrow or the day after, and "malam Jumat" the night before Friday.
        "Dokter gigi besok lusa", "Dokter gigi malam Jumat", "Dokter gigi malam Minggu",
        // A month or a year ahead has no day offset, and a count of working days is no count of days.
        "Dokter gigi bulan depan", "Dokter gigi sebulan lagi", "Dokter gigi dalam sebulan",
        "Dokter gigi tahun depan", "Dokter gigi dalam 3 hari kerja", "Dokter gigi 3 hari ke depan",
        // A count of times in a period is a rate, not a day.
        "Lari dua kali dalam seminggu", "Lari 3 kali dalam sepekan", "Lari tiga kali dalam 2 hari",
        // Hyphenated words are compounds, not days.
        "Dokter gigi besok-besok", "Dokter gigi sehari-hari", "Dokter gigi pagi-pagi",
      ], languages: ["id"])
    // The time that follows a past day still reads.
    let time = parse("Dokter gigi kemarin jam 3")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Dokter gigi kemarin")
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Dokter gigi Senin", 6), ("Dokter gigi Selasa", 7), ("Dokter gigi Rabu", 1), ("Dokter gigi Kamis", 2),
      ("Dokter gigi Jumat", 3), ("Dokter gigi Jum'at", 3), ("Dokter gigi Jum\u{2019}at", 3),
      ("Dokter gigi Sabtu", 4), ("Dokter gigi hari Minggu", 5), ("Dokter gigi hari Senin", 6),
      ("Dokter gigi pada Jumat", 3), ("Dokter gigi pada hari Jumat", 3), ("Dokter gigi di hari Jumat", 3),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "Selasa ini" is today.
      ("Dokter gigi Selasa ini", 0), ("Dokter gigi Rabu ini", 1), ("Dokter gigi Jumat ini", 3),
      ("Dokter gigi hari Jumat ini", 3), ("Dokter gigi hari Minggu ini", 5),
      ("Dokter gigi Senin depan", 6), ("Dokter gigi Selasa depan", 7), ("Dokter gigi Rabu depan", 8),
      ("Dokter gigi Jumat depan", 10), ("Dokter gigi hari Jumat depan", 10), ("Dokter gigi hari Minggu depan", 12),
      ("Dokter gigi Jumat minggu depan", 10), ("Dokter gigi Jumat pekan depan", 10),
      ("Dokter gigi minggu depan Jumat", 10), ("Dokter gigi Senin minggu depan", 6),
      // A part of the day written after the weekday.
      ("Dokter gigi Jumat pagi", 3), ("Dokter gigi Jumat sore", 3), ("Dokter gigi Jumat malam", 3),
      ("Dokter gigi Sabtu siang", 4),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Dokter gigi", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("Dokter gigi Senin jam 9")
    #expect(timed.plannedDayOffset == 6)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Dokter gigi")
    let opening = parse("Senin rapat")
    #expect(opening.plannedDayOffset == 6)
    #expect(opening.title == "rapat")
  }

  @Test("Minggu is the week; it is Sunday after hari, before a part of the day, or beside another weekday")
  func minggu() {
    for text in [
      "Dokter gigi hari Minggu", "Dokter gigi pada hari Minggu", "Dokter gigi Minggu pagi",
      "Dokter gigi Minggu sore", "Dokter gigi Minggu malam", "Dokter gigi Jumat dan Minggu",
    ] {
      let expected = text.contains("Jumat") ? 3 : 5
      #expect(parse(text).plannedDayOffset == expected, "\(text)")
    }
    #expect(parse("Dokter gigi minggu depan").plannedDayOffset == 7)
    // "Minggu" alone, "minggu ini", and the Sunday school stay in the title.
    expectLinesUnread(
      ["Dokter gigi Minggu", "Dokter gigi minggu ini", "Sekolah Minggu", "Belajar Sekolah Minggu"], languages: ["id"])
    // A prayer or a holiday named after Friday is a name, not a day.
    expectLinesUnread(["Salat Jumat", "Sholat Jumat", "Khotbah Jumat", "Libur Jumat Agung"], languages: ["id"])
    let prayer = parse("Salat Jumat besok")
    #expect(prayer.plannedDayOffset == 1)
    #expect(prayer.title == "Salat Jumat")
    // Saturday and Sunday together plan from Saturday.
    let pair = parse("Dokter gigi Sabtu dan Minggu")
    #expect(pair.plannedDayOffset == 4)
    #expect(pair.title == "Dokter gigi")
  }

  @Test("A list of weekdays names no one day and stays in the title; after setiap it is a repeat")
  func weekdayLists() {
    expectLinesUnread(
      [
        "Kelas Senin dan Rabu", "Kelas Senin atau Selasa", "Kelas Senin, Rabu, dan Jumat", "Kelas hari Senin dan hari Rabu",
        "Kelas Jumat pagi dan Sabtu sore", "Kelas Senin & Kamis",
      ], languages: ["id"])
    #expect(parse("Kelas setiap Senin dan Rabu").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE"]))
    // A weekday next to a date, or alone beside a comma, still reads.
    #expect(parse("Kelas Jumat, 16 Oktober").plannedDayOffset == captureDayOffset("2026-10-16"))
    #expect(parse("Kelas Senin, jam 9").plannedDayOffset == 6)
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("Laporan akhir pekan", 0), ("Laporan weekend", 0), ("Laporan akhir pekan depan", 7),
      ("Laporan Sabtu", 7), ("Laporan hari Minggu", 1), ("Laporan Sabtu ini", 0), ("Laporan Senin", 2),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("Laporan akhir pekan", 0), ("Laporan weekend", 0), ("Laporan akhir pekan depan", 7),
      ("Laporan hari Minggu", 7), ("Laporan hari Minggu ini", 0), ("Laporan hari Minggu depan", 7),
      ("Laporan Sabtu", 6), ("Laporan Senin", 1), ("Laporan Senin ini", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "Senin ini" is today.
    for (text, offset) in [("Laporan Senin", 7), ("Laporan Senin ini", 0), ("Laporan Senin depan", 7), ("Laporan Selasa", 1)] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("Laporan sampai Senin", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("Laporan setiap Senin", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("Laporan dari Senin sampai Rabu", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
    let tuesdayToThursday = parse("Laporan dari Selasa sampai Kamis", on: "2026-09-21", weekday: 2)
    #expect(tuesdayToThursday.plannedDayOffset == 1)
    #expect(tuesdayToThursday.dueDayOffset == 3)
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Setor laporan 15 Oktober", "Setor laporan", "2026-10-15"),
      ("Setor laporan tanggal 15 Oktober", "Setor laporan", "2026-10-15"),
      ("Setor laporan pada 15 Oktober", "Setor laporan", "2026-10-15"),
      ("Setor laporan pada tanggal 15 Oktober", "Setor laporan", "2026-10-15"),
      ("Setor laporan tgl 15 Okt", "Setor laporan", "2026-10-15"),
      ("Setor laporan tgl. 15 Okt.", "Setor laporan", "2026-10-15"),
      ("Setor laporan 15 Okt", "Setor laporan", "2026-10-15"),
      ("Setor laporan 15 Oktober 2026", "Setor laporan", "2026-10-15"),
      ("SETOR LAPORAN PADA 15 OKTOBER", "SETOR LAPORAN", "2026-10-15"),
      ("Setor laporan 1 Mei 2027", "Setor laporan", "2027-05-01"),
      ("Setor laporan 15.10.2026", "Setor laporan", "2026-10-15"),
      ("Setor laporan 15/10/2026", "Setor laporan", "2026-10-15"),
      ("Setor laporan 15-10-2026", "Setor laporan", "2026-10-15"),
      ("Setor laporan 15/10/26", "Setor laporan", "2026-10-15"),
      ("Setor laporan pada 15/10", "Setor laporan", "2026-10-15"),
      ("Setor laporan tanggal 15/10", "Setor laporan", "2026-10-15"),
      ("Setor laporan pada 15-10", "Setor laporan", "2026-10-15"),
      ("Setor laporan 3 Januari", "Setor laporan", "2027-01-03"),
      ("Setor laporan 3 Jan", "Setor laporan", "2027-01-03"),
      ("Setor laporan 3 Februari", "Setor laporan", "2027-02-03"),
      ("Setor laporan 3 Pebruari", "Setor laporan", "2027-02-03"),
      ("Setor laporan 3 Feb", "Setor laporan", "2027-02-03"),
      ("Setor laporan 3 Maret", "Setor laporan", "2027-03-03"),
      ("Setor laporan 3 Mar", "Setor laporan", "2027-03-03"),
      ("Setor laporan 3 April", "Setor laporan", "2027-04-03"),
      ("Setor laporan 3 Apr", "Setor laporan", "2027-04-03"),
      ("Setor laporan 3 Mei", "Setor laporan", "2027-05-03"),
      ("Setor laporan 3 Juni", "Setor laporan", "2027-06-03"),
      ("Setor laporan 3 Jun", "Setor laporan", "2027-06-03"),
      ("Setor laporan 3 Juli", "Setor laporan", "2027-07-03"),
      ("Setor laporan 3 Jul", "Setor laporan", "2027-07-03"),
      ("Setor laporan 3 Agustus", "Setor laporan", "2027-08-03"),
      ("Setor laporan 3 Agu", "Setor laporan", "2027-08-03"),
      ("Setor laporan 3 Agt", "Setor laporan", "2027-08-03"),
      ("Setor laporan 3 Ags", "Setor laporan", "2027-08-03"),
      ("Setor laporan 3 September", "Setor laporan", "2027-09-03"),
      ("Setor laporan 3 Sept", "Setor laporan", "2027-09-03"),
      ("Setor laporan 3 Sep", "Setor laporan", "2027-09-03"),
      ("Setor laporan 3 Oktober", "Setor laporan", "2026-10-03"),
      ("Setor laporan 3 November", "Setor laporan", "2026-11-03"),
      ("Setor laporan 3 Nopember", "Setor laporan", "2026-11-03"),
      ("Setor laporan 3 Nov", "Setor laporan", "2026-11-03"),
      ("Setor laporan 3 Desember", "Setor laporan", "2026-12-03"),
      ("Setor laporan 3 Des", "Setor laporan", "2026-12-03"),
      ("Setor laporan 22 September", "Setor laporan", "2026-09-22"),
      // A day of the month alone is this month's, or next month's once it has passed.
      ("Setor laporan tanggal 25", "Setor laporan", "2026-09-25"),
      ("Setor laporan tgl. 25", "Setor laporan", "2026-09-25"),
      ("Setor laporan tanggal 5", "Setor laporan", "2026-10-05"),
      // A weekday before the date is part of it.
      ("Setor laporan Jumat 16 Oktober", "Setor laporan", "2026-10-16"),
      ("Setor laporan Jumat, 16 Oktober", "Setor laporan", "2026-10-16"),
      ("Setor laporan hari Jumat 16 Oktober", "Setor laporan", "2026-10-16"),
      ("Setor laporan pada hari Jumat tanggal 16 Oktober", "Setor laporan", "2026-10-16"),
      ("Setor laporan Minggu, 4 Oktober", "Setor laporan", "2026-10-04"),
      ("Ulang tahun Ibu 14 Maret", "Ulang tahun Ibu", "2027-03-14"),
      ("Libur 1 Desember", "Libur", "2026-12-01"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Rapat Kamis 15 Oktober jam 14.30")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Rapat")
    let concert = parse("Konser 20 Okt. jam 19")
    #expect(concert.plannedDayOffset == captureDayOffset("2026-10-20"))
    #expect(concert.startMinutes == 19 * 60)
    #expect(concert.title == "Konser")
  }

  @Test("Numbers that are no date, a past year, and a day the month does not have stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers without a word that makes them a date, and a bare month.
        "Setor laporan 15/10", "Setor laporan 15-10", "Libur di bulan Mei", "Mei", "Laporan Mei 2027",
        // A day the month does not have, and a year that is past.
        "Setor laporan 31 Februari", "Setor laporan 15 Oktober 2025",
        // Chapters, versions, rooms, scores, percentages, prices, versions, quarters, and phone numbers.
        "Bab 1.5.", "Versi 2.3.4", "Halaman 15-10", "Ruang 15.10", "Skor 3-1", "Diskon 15%", "Harga 15,50",
        "Harga 15.30", "iOS 17.4", "Q3 2026", "Telepon 0812 3456 7890",
      ], languages: ["id"])
    // A short date after a number of the title that names an item is no date.
    expectLinesUnread(["Baca pada bab 3-1", "Pelajari pada halaman 15-10"], languages: ["id"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Liburan", "3-5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "3 sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "3 sampai dengan 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "3 s/d 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "3 hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "dari 3 sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "dari 3 hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "dari 3 - 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "dari tanggal 3 sampai tanggal 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "antara 3 dan 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "pada 3-5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "tanggal 3-5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "3 Mei - 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "3 Mei sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "dari 3 Mei sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "dari 3 Mei s/d 5 Mei", "2027-05-03", "2027-05-05"),
        ("Liburan", "30 Mei - 2 Juni", "2027-05-30", "2027-06-02"),
        ("Liburan", "dari 30 Mei sampai 2 Juni", "2027-05-30", "2027-06-02"),
        ("Liburan", "3-5 Mei 2027", "2027-05-03", "2027-05-05"),
        ("Liburan", "5 s/d 9 Oktober", "2026-10-05", "2026-10-09"),
        ("Libur akhir tahun", "24 Des - 2 Jan", "2026-12-24", "2027-01-02"),
        ("Libur akhir tahun", "24 Desember sampai 2 Januari", "2026-12-24", "2027-01-02"),
      ], languages: ["id"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Liburan 5-3 Mei", "Liburan 3 Mei - 3 Mei", "Liburan antara 5 dan 3 Mei", "Liburan dari 5 sampai 3 Mei",
        "Harga 3-5 juta",
      ], languages: ["id"])
    // Two bare numbers after "dari" are hours.
    let bare = parse("Rapat dari 3 sampai 5")
    #expect(bare.plannedDayOffset == nil)
    #expect(bare.dueDayOffset == nil)
    #expect(bare.startMinutes == 15 * 60)
    #expect(bare.estimatedMinutes == 120)
  }

  @Test("A day alone opens a range joined by a spaced dash only after nothing that names a day")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 Mei")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-05-20"))
    #expect(sprint.dueDayOffset == nil)
    let meeting = parse("Rapat 12 - 14 Oktober")
    #expect(meeting.title == "Rapat 12")
    #expect(meeting.plannedDayOffset == captureDayOffset("2026-10-14"))
    #expect(meeting.dueDayOffset == nil)
    let holiday = parse("Liburan 3 - 5 Mei")
    #expect(holiday.title == "Liburan 3")
    #expect(holiday.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(holiday.dueDayOffset == nil)
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time or a length still reads")
  func rangeTakesBothDays() {
    let line = parse("Liburan 3-5 Mei besok")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Liburan besok")
    let timed = parse("Liburan 3-5 Mei jam 9")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Liburan")
    let length = parse("Liburan 3-5 Mei 30 menit")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "Liburan")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    expectDateRanges(
      [
        ("Konferensi", "dari Senin sampai Rabu", "2026-09-28", "2026-09-30"),
        ("Konferensi", "Senin sampai Rabu", "2026-09-28", "2026-09-30"),
        ("Konferensi", "dari Jumat sampai Minggu", "2026-09-25", "2026-09-27"),
        ("Konferensi", "Jumat sampai Minggu", "2026-09-25", "2026-09-27"),
        ("Konferensi", "dari Jumat hingga Senin", "2026-09-25", "2026-09-28"),
        ("Konferensi", "Jumat - Minggu", "2026-09-25", "2026-09-27"),
        ("Konferensi", "Sabtu - Minggu", "2026-09-26", "2026-09-27"),
        ("Konferensi", "hari Jumat sampai hari Minggu", "2026-09-25", "2026-09-27"),
        ("Sprint", "Senin - Jumat", "2026-09-28", "2026-10-02"),
        ("Sprint", "Senin-Rabu", "2026-09-28", "2026-09-30"),
        ("Sprint", "Senin s/d Rabu", "2026-09-28", "2026-09-30"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Konferensi", "dari Selasa sampai Kamis", "2026-09-29", "2026-10-01"),
      ], languages: ["id"])
    // Monday to Friday after "setiap", and the working days, repeat.
    for text in [
      "Senam setiap Senin sampai Jumat", "Senam tiap Senin - Jumat", "Senam setiap hari kerja",
      "Senam tiap hari kerja", "Senam pada hari kerja", "Senam pada hari-hari kerja",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Senam", "\(text): title")
    }
  }

  // MARK: - Due days

  @Test("Due days: sebelum, paling lambat, sampai, hingga, tenggat, batas waktu, deadline, and jatuh tempo")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Laporan sebelum Jumat", "Laporan", 3),
      ("Laporan sebelum hari Jumat", "Laporan", 3),
      ("Laporan sebelum besok", "Laporan", 1),
      ("Laporan sebelum lusa", "Laporan", 2),
      ("Laporan sebelum Senin depan", "Laporan", 6),
      ("Laporan sebelum minggu depan", "Laporan", 7),
      ("Laporan sebelum Jumat sore", "Laporan", 3),
      ("Laporan sebelum besok pagi", "Laporan", 1),
      ("Laporan sebelum 15 Oktober", "Laporan", 23),
      ("Laporan sebelum 15 Okt", "Laporan", 23),
      ("Laporan sebelum tanggal 15 Oktober", "Laporan", 23),
      ("Laporan sebelum tanggal 15", "Laporan", 23),
      ("Laporan sebelum 15/10", "Laporan", 23),
      ("Laporan sebelum 15/10/2026", "Laporan", 23),
      ("Laporan sebelum Kamis, 15 Oktober", "Laporan", 23),
      ("Laporan paling lambat Jumat", "Laporan", 3),
      ("Laporan paling lambat besok", "Laporan", 1),
      ("Laporan paling lambat tanggal 15 Oktober", "Laporan", 23),
      ("Laporan paling lambat 15 Oktober", "Laporan", 23),
      ("Laporan paling telat Jumat", "Laporan", 3),
      ("Laporan selambat-lambatnya Jumat", "Laporan", 3),
      ("Laporan selambatnya Jumat", "Laporan", 3),
      ("Laporan sampai Jumat", "Laporan", 3),
      ("Laporan sampai dengan Jumat", "Laporan", 3),
      ("Laporan hingga Jumat", "Laporan", 3),
      ("Laporan sampai besok", "Laporan", 1),
      ("Laporan sampai tanggal 15", "Laporan", 23),
      ("Laporan sampai 15 Oktober", "Laporan", 23),
      ("Laporan sampai 15 Okt", "Laporan", 23),
      ("Laporan tenggat Jumat", "Laporan", 3),
      ("Laporan tenggat: Jumat", "Laporan", 3),
      ("Laporan tenggat waktu Jumat", "Laporan", 3),
      ("Laporan batas waktu Jumat", "Laporan", 3),
      ("Laporan batas akhir Jumat", "Laporan", 3),
      ("Laporan deadline Jumat", "Laporan", 3),
      ("Laporan deadline: Jumat", "Laporan", 3),
      ("Laporan jatuh tempo Jumat", "Laporan", 3),
      ("Laporan jatuh tempo 15 Oktober", "Laporan", 23),
      ("Kirim laporan sebelum Jumat", "Kirim laporan", 3),
      ("Beli kado sebelum Sabtu", "Beli kado", 4),
      ("Bayar listrik sebelum tanggal 20", "Bayar listrik", 28),
      ("LAPORAN SEBELUM JUMAT", "LAPORAN", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Laporan sebelum Jumat hari ini")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Laporan")
    // A due phrase that opens the line.
    let opening = parse("Sebelum Jumat kirim laporan")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "kirim laporan")
    // A bound at the weekend names no due day, and neither does a bare number, a month ahead, or a person.
    expectLinesUnread(
      [
        "Laporan sebelum akhir pekan", "Laporan sampai akhir pekan", "Laporan sampai weekend",
        "Laporan setelah akhir pekan", "Laporan untuk akhir pekan", "Laporan sebelum bulan depan",
        "Laporan sampai selesai", "Laporan sampai 5 orang", "Laporan untuk 3 hari", "Beli hadiah untuk Ibu",
        "Laporan sebelum Minggu", "Bayar 100 ribu sampai 15",
      ], languages: ["id"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Laporan sebelum jam 17", "Laporan sebelum pukul 17.00", "Laporan sampai jam 5", "Laporan sampai pukul 17.00",
        "Laporan sebelum 17:00", "Laporan sebelum jam 5 sore", "Laporan paling lambat jam 5 sore",
        "Laporan paling lambat pukul 17.00", "Laporan selambat-lambatnya jam 5", "Laporan setelah jam 18",
        "Laporan menjelang tengah malam", "Laporan sampai tengah malam", "Laporan deadline jam 5",
        "Laporan tenggat jam 17.00", "Laporan sebelum setengah lima", "Laporan sebelum jam tiga",
        "Laporan sebelum jam 3 lewat 15", "Laporan sebelum 5 sore", "Laporan sebelum 5pm", "Laporan sampai 17.00",
        "Laporan sebelum jam 5 pm", "Laporan sampai dengan jam 17", "Laporan hingga pukul 17:30",
      ], languages: ["id"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Laporan sebelum Jumat jam 17", "Laporan jam 17", 3), ("Laporan sebelum Jumat pukul 17.00", "Laporan pukul 17.00", 3),
      ("Laporan sebelum Jumat 17:00", "Laporan 17:00", 3), ("Laporan sampai Senin jam 9", "Laporan jam 9", 6),
      ("Laporan paling lambat besok jam 9.00", "Laporan jam 9.00", 1),
      ("Laporan tenggat: Jumat jam 17.00", "Laporan jam 17.00", 3),
      ("Laporan sebelum Jumat sore jam 5", "Laporan jam 5", 3),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A time range that ends in a clock time is still a range, and a bound after a day stays a bound.
    let range = parse("Rapat dari jam 14 sampai jam 17.30")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 210)
    #expect(range.title == "Rapat")
    let bound = parse("Rapat sampai jam 17.30 besok")
    #expect(bound.plannedDayOffset == 1)
    #expect(bound.startMinutes == nil)
    #expect(bound.title == "Rapat sampai jam 17.30")
    // The clock that ends a range of days is the range's time.
    let rangeTime = parse("Rapat dari Senin sampai Rabu jam 9")
    #expect(rangeTime.plannedDayOffset == 6)
    #expect(rangeTime.dueDayOffset == 8)
    #expect(rangeTime.startMinutes == 9 * 60)
    #expect(rangeTime.title == "Rapat")
    // Without Indonesian, English reads the clock time and leaves the words.
    let english = parse("Laporan sebelum 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
    #expect(english.title == "Laporan sebelum")
  }

  // MARK: - Clock times

  @Test("Clock times: jam, pukul, a part of the day, noon, and AM and PM")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Rapat jam 15", 15 * 60), ("Rapat jam 3", 15 * 60), ("Rapat jam 03", 3 * 60), ("Rapat pukul 15", 15 * 60),
      ("Rapat pukul 3", 15 * 60), ("Rapat jam 15.30", 15 * 60 + 30), ("Rapat jam 15:30", 15 * 60 + 30),
      ("Rapat pukul 15.30", 15 * 60 + 30), ("Rapat pukul 15:30", 15 * 60 + 30), ("Rapat pk. 15.30", 15 * 60 + 30),
      ("Rapat pada jam 15", 15 * 60), ("Rapat pada pukul 15.30", 15 * 60 + 30), ("Rapat jam 08.30", 8 * 60 + 30),
      ("Rapat pukul 00.30", 30), ("Rapat jam 18", 18 * 60), ("Rapat jam 12", 12 * 60), ("Rapat jam 8", 8 * 60),
      ("Rapat jam 9.30", 9 * 60 + 30), ("Rapat jam 20.30", 20 * 60 + 30), ("Rapat jam 0", 0),
      ("Rapat jam 03.00", 3 * 60), ("Rapat jam 5.10", 17 * 60 + 10), ("Rapat JAM 15", 15 * 60),
      // An hour spelled as a word after jam or pukul.
      ("Rapat jam tiga", 15 * 60), ("Rapat pukul tiga", 15 * 60), ("Rapat jam dua belas", 12 * 60),
      ("Rapat jam sepuluh", 10 * 60), ("Rapat jam sebelas", 11 * 60),
      // A part of the day after the hour.
      ("Rapat jam 3 sore", 15 * 60), ("Rapat jam 3 siang", 15 * 60), ("Rapat jam 5 sore", 17 * 60),
      ("Rapat jam 8 malam", 20 * 60), ("Rapat jam 7 pagi", 7 * 60), ("Rapat jam 11 siang", 11 * 60),
      ("Rapat jam 12 siang", 12 * 60), ("Rapat jam 1 siang", 13 * 60), ("Rapat jam 11 malam", 23 * 60),
      ("Rapat jam 4 subuh", 4 * 60), ("Rapat jam 2 dini hari", 2 * 60), ("Rapat jam 7.30 malam", 19 * 60 + 30),
      ("Rapat jam 15.30 sore", 15 * 60 + 30), ("Rapat jam 20.00 malam", 20 * 60), ("Rapat jam tiga sore", 15 * 60),
      ("Rapat jam delapan malam", 20 * 60), ("Rapat jam sepuluh pagi", 10 * 60), ("Rapat pukul 8 malam", 20 * 60),
      ("Rapat pukul 10.00 pagi", 10 * 60), ("Rapat jam 8 nanti malam", 20 * 60),
      // A time with minutes and a part of the day needs no jam.
      ("Rapat 7.30 malam", 19 * 60 + 30), ("Rapat 7:30 malam", 19 * 60 + 30), ("Rapat 3.30 sore", 15 * 60 + 30),
      ("Rapat 8.15 pagi", 8 * 60 + 15), ("Rapat 08.00 pagi", 8 * 60), ("Rapat 5.45 sore", 17 * 60 + 45),
      // Noon.
      ("Rapat tengah hari", 12 * 60), ("Rapat pada tengah hari", 12 * 60), ("Rapat siang bolong", 12 * 60),
      ("Rapat jam 12 tengah hari", 12 * 60),
      // AM and PM after jam or pukul take the lead with them; with no lead English reads them.
      ("Rapat jam 3pm", 15 * 60), ("Rapat jam 3 pm", 15 * 60), ("Rapat jam 3:30 pm", 15 * 60 + 30),
      ("Rapat pukul 3 PM", 15 * 60), ("Rapat jam 9 am", 9 * 60), ("Rapat 15:30", 15 * 60 + 30),
      ("Rapat 3pm", 15 * 60), ("Rapat 17:30", 17 * 60 + 30), ("Rapat 3:30 pm", 15 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Rapat", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The title is what the time leaves, and a zone stays in it.
    #expect(parse("Telepon Ibu jam 3").title == "Telepon Ibu")
    #expect(parse("Wawancara besok jam 14.30").title == "Wawancara")
    #expect(parse("Rapat jam 3 sore WIB").title == "Rapat WIB")
    #expect(parse("Rapat jam 3 sore WIB").startMinutes == 15 * 60)
    #expect(parse("Rapat jam 3 dengan Ani").title == "Rapat dengan Ani")
    #expect(parse("Jam 5 jemput anak").startMinutes == 17 * 60)
    #expect(parse("Jam 5 jemput anak").title == "jemput anak")
    // A number before "jam 10" is no amount of hours: "jam" opens the clock time.
    let room = parse("Rapat di ruang 3 jam 10 pagi")
    #expect(room.startMinutes == 10 * 60)
    #expect(room.estimatedMinutes == nil)
    #expect(room.title == "Rapat di ruang 3")
    let number = parse("Nomor 17 jam 5 sore")
    #expect(number.startMinutes == 17 * 60)
    #expect(number.estimatedMinutes == nil)
    #expect(number.title == "Nomor 17")
  }

  @Test("A part of the day beside an hour decides it: pagi, siang, sore, malam, and a meal")
  func partsOfTheDay() {
    for (line, day, minutes, title) in [
      ("Makan malam jam 8", nil, 20 * 60, "Makan malam"), ("Makan malam jam 7", nil, 19 * 60, "Makan malam"),
      ("Makan malam sama keluarga jam 7", nil, 19 * 60, "Makan malam sama keluarga"),
      ("Makan malam besok jam 8", 1, 20 * 60, "Makan malam"), ("Rapat besok malam jam 8", 1, 20 * 60, "Rapat"),
      ("Rapat malam ini jam 8", 0, 20 * 60, "Rapat"), ("Rapat nanti malam jam 8", 0, 20 * 60, "Rapat"),
      ("Rapat Jumat malam jam 8", 3, 20 * 60, "Rapat"), ("Rapat malam jam 9", nil, 21 * 60, "Rapat malam"),
      ("Rapat besok pagi jam 7", 1, 7 * 60, "Rapat"), ("Rapat besok pagi jam 8", 1, 8 * 60, "Rapat"),
      ("Rapat besok sore jam 4", 1, 16 * 60, "Rapat"), ("Olahraga pagi jam 6", nil, 6 * 60, "Olahraga pagi"),
      ("Olahraga pagi jam 5", nil, 5 * 60, "Olahraga pagi"), ("Jam 8 makan malam", nil, 20 * 60, "makan malam"),
      ("Rapat jam 8 malam ini", nil, 20 * 60, "Rapat"), ("Rapat jam 3 sore ini", nil, 15 * 60, "Rapat"),
      ("Rapat malam, jam 8", nil, 20 * 60, "Rapat malam"), ("Makan malam 7:30", nil, 19 * 60 + 30, "Makan malam"),
      ("Sarapan pagi 7:30", nil, 7 * 60 + 30, "Sarapan pagi"), ("Sarapan bareng tim jam 8", nil, 8 * 60, "Sarapan bareng tim"),
      ("Makan siang jam 1", nil, 13 * 60, "Makan siang"), ("Makan siang jam 12", nil, 12 * 60, "Makan siang"),
    ] as [(String, Int?, Int, String)] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == title, "\(line): title")
    }
    // Another part of the day, or none, keeps the hour as it is.
    for (line, minutes) in [("Rapat besok jam 8", 8 * 60), ("Rapat besok jam 7", 7 * 60), ("Rapat hari ini jam 8", 8 * 60)] {
      #expect(parse(line).startMinutes == minutes, "\(line)")
    }
    // Two different parts of the day name no hour, so the hour is read on its own.
    let two = parse("Makan malam setelah olahraga pagi jam 8")
    #expect(two.startMinutes == 8 * 60)
    // A part of the day as a noun names no day or time.
    expectLinesUnread(
      ["Sarapan pagi", "Makan malam", "Makan malam keluarga", "Menginap 2 malam", "Selamat pagi", "Rapat 8 malam"],
      languages: ["id"])
  }

  @Test("After midnight: jam 12 malam, jam 1 malam, tengah malam run past the midnight that ends the day")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("Rapat jam 12 malam", 1, 0), ("Rapat jam 1 malam", 1, 60), ("Rapat jam 2 malam", 1, 2 * 60),
      ("Rapat jam 12 tengah malam", 1, 0), ("Rapat tengah malam", 1, 0), ("Rapat pada tengah malam", 1, 0),
      ("Rapat besok jam 12 malam", 2, 0), ("Rapat besok malam jam 12", 2, 0), ("Rapat besok tengah malam", 2, 0),
      ("Rapat malam ini jam 12", 1, 0),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Rapat", "\(line): title")
    }
    // Eleven at night is still the day itself, the hours before dawn belong to the day named, and the
    // 24th hour is no time of day.
    let eleven = parse("Rapat jam 11 malam")
    #expect(eleven.plannedDayOffset == nil)
    #expect(eleven.startMinutes == 23 * 60)
    let dawn = parse("Rapat besok jam 2 dini hari")
    #expect(dawn.plannedDayOffset == 1)
    #expect(dawn.startMinutes == 2 * 60)
    expectLinesUnread(["Rapat jam 24", "Rapat jam 24.00", "Rapat jam 25.00", "Rapat jam 9.60"], languages: ["id"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func twelveHourRules() {
    for (line, minutes) in [
      ("Rapat jam 1", 13 * 60), ("Rapat jam 3", 15 * 60), ("Rapat jam 6", 18 * 60), ("Rapat jam 7", 7 * 60),
      ("Rapat jam 06.00", 6 * 60), ("Rapat jam 03", 3 * 60), ("Rapat jam 11", 11 * 60), ("Rapat jam 12", 12 * 60),
      ("Rapat jam 5.10", 17 * 60 + 10), ("Rapat jam tiga", 15 * 60), ("Rapat jam tujuh", 7 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
    }
  }

  @Test("Spoken times: lewat, lebih, and kurang move the hour; setengah counts toward the next hour")
  func spokenTimes() {
    let spoken: [(text: String, minutes: Int)] = [
      ("Rapat jam 3 lewat 15", 15 * 60 + 15), ("Rapat jam 3 lewat 15 menit", 15 * 60 + 15),
      ("Rapat jam 3 lebih 10 menit", 15 * 60 + 10), ("Rapat jam 3 kurang 10", 14 * 60 + 50),
      ("Rapat jam 3 kurang 10 menit", 14 * 60 + 50), ("Rapat jam 3 kurang seperempat", 14 * 60 + 45),
      ("Rapat jam 3 lewat seperempat", 15 * 60 + 15), ("Rapat pukul tiga kurang sepuluh", 14 * 60 + 50),
      ("Rapat jam tiga lewat lima belas", 15 * 60 + 15), ("Rapat jam 1 kurang 10", 12 * 60 + 50),
      ("Rapat jam 12 kurang seperempat", 11 * 60 + 45), ("Rapat jam 3 lewat 15 sore", 15 * 60 + 15),
      ("Rapat jam 8 kurang 5 malam", 19 * 60 + 55), ("Rapat jam 3 lewat dua puluh lima", 15 * 60 + 25),
      ("Rapat jam 3 kurang lima", 14 * 60 + 55),
      ("Rapat setengah empat", 15 * 60 + 30), ("Rapat setengah 4", 15 * 60 + 30), ("Rapat jam setengah empat", 15 * 60 + 30),
      ("Rapat pukul setengah 4", 15 * 60 + 30), ("Rapat setengah empat sore", 15 * 60 + 30),
      ("Rapat setengah delapan malam", 19 * 60 + 30), ("Rapat setengah satu", 12 * 60 + 30),
      ("Rapat setengah dua belas", 11 * 60 + 30), ("Rapat setengah tujuh", 18 * 60 + 30),
      ("Rapat setengah sepuluh pagi", 9 * 60 + 30), ("Rapat setengah dua belas malam", 23 * 60 + 30),
      ("Rapat setengah lima", 16 * 60 + 30), ("Rapat setengah 12", 11 * 60 + 30),
    ]
    for line in spoken {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
      #expect(parsed.title == "Rapat", "\(line.text): title")
    }
    // Half an hour past midnight is on the next day.
    let late = parse("Rapat setengah satu malam")
    #expect(late.plannedDayOffset == 1)
    #expect(late.startMinutes == 30)
    // "Setengah empat" with no jam reads before a word that can follow a time, and stays an amount otherwise.
    let title = parse("Rapat setengah empat dengan Ani")
    #expect(title.title == "Rapat dengan Ani")
    #expect(title.startMinutes == 15 * 60 + 30)
    expectLinesUnread(
      ["Beli setengah empat kilo", "Beli setengah tiga ons", "Beli setengah lima ribu", "Beli setengah dua puluh"],
      languages: ["id"])
  }

  @Test("Minutes after jam written with a unit word are the time's, not a length")
  func spokenMinutesWithUnit() {
    let line = parse("Rapat jam 3 lewat 10 menit")
    #expect(line.startMinutes == 15 * 60 + 10)
    #expect(line.estimatedMinutes == nil)
    #expect(line.title == "Rapat")
    // Malay's spelling of the unit reads the same.
    let malay = parse("Rapat jam 4 kurang 10 minit")
    #expect(malay.startMinutes == 15 * 60 + 50)
    #expect(malay.estimatedMinutes == nil)
    #expect(malay.title == "Rapat")
    // A length that stands apart is still a length.
    let apart = parse("Rapat jam 3 lewat 10 menit 20 menit")
    #expect(apart.startMinutes == 15 * 60 + 10)
    #expect(apart.estimatedMinutes == 20)
    #expect(apart.title == "Rapat")
  }

  @Test("Time ranges: dari with sampai, antara with dan, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Rapat jam 14-16", 14 * 60, 120), ("Rapat jam 14.00-16.00", 14 * 60, 120),
      ("Rapat jam 14:00-16:00", 14 * 60, 120), ("Rapat dari jam 14 sampai jam 16", 14 * 60, 120),
      ("Rapat dari jam 14.00 sampai 16.00", 14 * 60, 120), ("Rapat jam 14 sampai 16", 14 * 60, 120),
      ("Rapat jam 14 hingga 16", 14 * 60, 120), ("Rapat jam 14 s/d 16", 14 * 60, 120),
      ("Rapat antara jam 14 dan 16", 14 * 60, 120), ("Rapat pukul 09.00 - 11.00", 9 * 60, 120),
      ("Rapat 09.00-11.00", 9 * 60, 120), ("Rapat 14.00-16.00", 14 * 60, 120), ("Rapat 14.00 - 16.00", 14 * 60, 120),
      ("Rapat jam 3-5 sore", 15 * 60, 120), ("Rapat jam 3 sampai 5 sore", 15 * 60, 120),
      ("Rapat dari jam 8 sampai jam 10 pagi", 8 * 60, 120), ("Rapat dari jam 7 sampai 9 malam", 19 * 60, 120),
      ("Rapat jam 10 pagi sampai jam 12 siang", 10 * 60, 120), ("Rapat jam 3-4", 15 * 60, 60),
      ("Rapat dari 3 sampai 5", 15 * 60, 120), ("Rapat antara 3 dan 5", 15 * 60, 120),
      ("Rapat dari jam 15.30 sampai jam 17.00", 15 * 60 + 30, 90), ("Rapat jam 9-12", 9 * 60, 180),
      ("Rapat mulai jam 14 sampai jam 16", 14 * 60, 120), ("Rapat dari 14.00 sampai 16.00", 14 * 60, 120),
      ("Rapat jam 3 sampai jam 5 sore", 15 * 60, 120), ("Rapat dari 8 sampai 10 pagi", 8 * 60, 120),
      // A side with no part of the day takes the reading that fits the other side.
      ("Rapat jam 9 sampai 5 sore", 9 * 60, 480), ("Rapat dari jam 9 sampai 5 sore", 9 * 60, 480),
      ("Rapat jam 9 pagi sampai 5 sore", 9 * 60, 480), ("Rapat jam 9 sampai jam 5 sore", 9 * 60, 480),
      ("Rapat jam 11 sampai 1 siang", 11 * 60, 120), ("Rapat jam 3 sore sampai 5", 15 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "Rapat", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day or a meal makes the range that part's, as it does a single hour.
    let evening = parse("Rapat malam ini dari jam 7 sampai 9")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.estimatedMinutes == 120)
    let morning = parse("Rapat besok dari jam 7 sampai 9")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 7 * 60)
    // A range may run past midnight.
    let overnight = parse("Jaga jam 22.00-02.00")
    #expect(overnight.startMinutes == 22 * 60)
    #expect(overnight.estimatedMinutes == 240)
    #expect(overnight.title == "Jaga")
    // Numbers that count something are no range of hours, and neither are two bare hours whose end comes
    // before a start on the 24-hour clock, or dotted times that could be dates.
    expectLinesUnread(
      [
        "Rapat 14-16", "Rapat 3-5", "Rapat 5.10-7.10", "Bab 3-5", "Halaman 3-5", "Rapat dari 15 sampai 10",
        "Rapat dari 3 sampai 5 orang", "Rapat dari 3 sampai 5 hari", "Rapat antara 3 dan 5 hari",
        "Anggaran antara 5 dan 10 juta",
      ], languages: ["id"])
    // Two bare hours after "antara" are a range, as they are after "dari".
    let between = parse("Rapat antara 5 dan 10")
    #expect(between.startMinutes == 17 * 60)
    #expect(between.estimatedMinutes == 300)
    #expect(between.title == "Rapat")
    // A start that is followed by a word that is no end is the start alone, and the words stay.
    let open = parse("Rapat jam 3 sampai selesai")
    #expect(open.startMinutes == 15 * 60)
    #expect(open.estimatedMinutes == nil)
    #expect(open.title == "Rapat sampai selesai")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Rapat 30 menit", 30), ("Rapat 30 mnt", 30), ("Rapat 45menit", 45), ("Rapat 5 menit", 5),
      ("Rapat 90 menit", 90), ("Rapat 1440 menit", 1440), ("Rapat 1 jam", 60), ("Rapat 2 jam", 120),
      ("Rapat 1,5 jam", 90), ("Rapat 1.5 jam", 90), ("Rapat 0,5 jam", 30), ("Rapat 2,5 jam", 150),
      ("Rapat 1 jam 30 menit", 90), ("Rapat 2 jam 30 menit", 150), ("Rapat 2 jam setengah", 150),
      ("Rapat setengah jam", 30), ("Rapat sejam", 60), ("Rapat sejam setengah", 90),
      ("Rapat satu setengah jam", 90), ("Rapat dua setengah jam", 150), ("Rapat seperempat jam", 15),
      ("Rapat tiga perempat jam", 45), ("Rapat dua jam", 120), ("Rapat tiga jam", 180),
      ("Rapat lima belas menit", 15), ("Rapat tiga puluh menit", 30), ("Rapat dua puluh lima menit", 25),
      ("Rapat sepuluh menit", 10), ("Rapat satu jam tiga puluh menit", 90), ("Rapat semenit", 1),
      ("Rapat selama 2 jam", 120), ("Rapat durasi 2 jam", 120), ("Rapat durasi: 2 jam", 120),
      ("Rapat lama 2 jam", 120), ("Rapat sekitar 30 menit", 30), ("Rapat kurang lebih 2 jam", 120),
      ("Rapat kira-kira 1 jam", 60), ("Rapat untuk 30 menit", 30), ("Rapat estimasi 1 jam", 60),
      ("Rapat selama setengah jam", 30), ("Rapat 24 jam", 1440), ("Rapat 20 jam", 1200), ("Rapat 30 MENIT", 30),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Rapat", "\(line.text): title")
    }
    let before = parse("30 menit rapat")
    #expect(before.estimatedMinutes == 30)
    #expect(before.title == "rapat")
    // A length beside a day and a time.
    let line = parse("Rapat besok jam 3 selama 2 jam")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.title == "Rapat")
  }

  @Test("An amount after dalam, setiap, or setelah, a rate, a difference, and a range are no length")
  func notLengths() {
    expectLinesUnread(
      [
        "Rapat dalam 2 jam", "Rapat setiap 2 jam", "Rapat setelah 30 menit", "Rapat sebelum 2 jam",
        "Rapat kurang dari 2 jam", "Rapat maksimal 2 jam", "Rapat 2 jam lagi", "Rapat 2 jam yang lalu",
        "Rapat 2 jam sehari", "Rapat 2 jam per hari", "Rapat 30 menit lebih", "Rapat 2 jam sekali",
        "Rapat 2-3 jam", "Rapat 2 - 3 jam", "Rapat 2 sampai 3 jam", "Rapat 2 atau 3 jam", "Rapat 25 jam",
        "Rapat 1500 menit", "Rapat 0 menit", "Telepon dalam 10 menit", "Rapat 3.5.2 jam",
      ], languages: ["id"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func cadences() {
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Lari setiap hari", daily), ("Lari tiap hari", daily), ("Lari tiap-tiap hari", daily),
      ("Lari setiap pagi", daily), ("Lari setiap malam", daily), ("Lari harian", daily),
      ("Lari sehari sekali", daily), ("Lari sekali sehari", daily), ("Lari 1x sehari", daily),
      ("Lari setiap minggu", weekly), ("Lari tiap minggu", weekly), ("Lari setiap pekan", weekly),
      ("Lari mingguan", weekly), ("Lari seminggu sekali", weekly), ("Lari sekali seminggu", weekly),
      ("Lari 1x seminggu", weekly), ("Lari 1 kali seminggu", weekly), ("Lari satu kali per minggu", weekly),
      ("Lari sekali dalam seminggu", weekly), ("Lari sepekan sekali", weekly),
      ("Lari setiap bulan", monthly), ("Lari bulanan", monthly), ("Lari sebulan sekali", monthly),
      ("Lari sekali sebulan", monthly), ("Lari 1x per bulan", monthly),
      ("Lari setiap tahun", yearly), ("Lari tahunan", yearly), ("Lari setahun sekali", yearly),
      ("Lari sekali setahun", yearly),
      ("Lari setiap 2 hari", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Lari setiap dua hari", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Lari tiap 3 hari", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Lari 2 hari sekali", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Lari dua hari sekali", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Lari setiap 14 hari", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Lari setiap 2 minggu", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Lari setiap dua minggu", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Lari 2 minggu sekali", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Lari sekali dalam 2 minggu", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Lari setiap 2 bulan", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Lari 3 bulan sekali", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Lari setiap 2 tahun", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("Lari setiap triwulan", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Lari setiap kuartal", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Lari setiap semester", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("LARI SETIAP HARI", daily),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // A repeat in front of the line.
    let opening = parse("Harian: lari")
    #expect(opening.recurrence == daily)
    #expect(opening.title == "lari")
    // A repeat at the end of a line that goes on after a noun.
    #expect(parse("Laporan bulanan").recurrence == monthly)
    #expect(parse("Laporan mingguan").recurrence == weekly)
    #expect(parse("Rapat mingguan tim").recurrence == nil)
    // A date beside a yearly repeat.
    let birthday = parse("Ulang tahun Ani 15 Oktober setiap tahun")
    #expect(birthday.recurrence == yearly)
    #expect(birthday.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(birthday.title == "Ulang tahun Ani")
    // A repeat with a time or a length.
    for (text, rule, minutes, length) in [
      ("Lari setiap pagi jam 6", daily, 6 * 60, nil), ("Lari setiap pagi jam 7", daily, 7 * 60, nil),
      ("Lari setiap pagi 6.30", daily, 6 * 60 + 30, nil), ("Lari setiap malam jam 8", daily, 20 * 60, nil),
      ("Lari setiap malam 8:30", daily, 20 * 60 + 30, nil),
      ("Lari setiap malam jam 8 selama 30 menit", daily, 20 * 60, 30),
      ("Minum obat setiap hari jam 8 pagi", daily, 8 * 60, nil),
      ("Minum obat harian jam 8 malam", daily, 20 * 60, nil),
    ] as [(String, TaskRecurrenceRule, Int, Int?)] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == String(text.prefix { $0 != " " }) + (text.hasPrefix("Minum") ? " obat" : ""), "\(text): title")
    }
  }

  @Test("Weekday repeats: setiap Senin, hari Minggu, lists, spans, and the weekend")
  func weekdayRepeats() {
    let coming = parse("Lari setiap Senin")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Lari")
    for text in ["Lari tiap Senin", "Lari setiap hari Senin", "Lari tiap hari Senin", "Lari setiap minggu pada hari Senin"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == monday, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.title == "Lari", "\(text): title")
    }
    let pairs: [(text: String, days: [String])] = [
      ("Lari setiap Selasa dan Kamis", ["TU", "TH"]),
      ("Lari setiap Senin, Rabu, dan Jumat", ["MO", "WE", "FR"]),
      ("Lari setiap hari Senin dan Kamis", ["MO", "TH"]),
      ("Lari setiap Senin & Kamis", ["MO", "TH"]),
      ("Lari setiap Senin dan Kamis", ["MO", "TH"]),
      ("Lari setiap Sabtu", ["SA"]),
      ("Lari setiap hari Minggu", ["SU"]),
      ("Lari setiap Minggu pagi", ["SU"]),
      ("Lari setiap Sabtu dan Minggu", ["SU", "SA"]),
      ("Lari setiap minggu Senin dan Kamis", ["MO", "TH"]),
      ("Lari setiap Senin sampai Kamis", ["MO", "TU", "WE", "TH"]),
      ("Lari setiap Senin - Kamis", ["MO", "TU", "WE", "TH"]),
      ("Lari setiap Jumat sampai Minggu", ["SU", "FR", "SA"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Lari", "\(line.text): title")
    }
    // An interval takes the weekdays after it.
    let interval = parse("Lari setiap 2 minggu hari Kamis")
    #expect(interval.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TH"]))
    #expect(interval.recurrenceStartOffset == 2)
    #expect(interval.title == "Lari")
    #expect(parse("Lari 2 minggu sekali hari Kamis").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TH"]))
    // The start of a repeat on Wednesday, Friday, and Monday is the nearest day.
    #expect(parse("Lari setiap Senin, Rabu, dan Jumat").recurrenceStartOffset == 1)
    #expect(parse("Lari setiap Selasa dan Kamis").recurrenceStartOffset == 0)
    #expect(parse("Lari setiap Sabtu dan Minggu").recurrenceStartOffset == 4)
    for text in ["Lari setiap akhir pekan", "Lari tiap weekend"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == weekend, "\(text)")
      #expect(parsed.recurrenceStartOffset == 4, "\(text): start")
      #expect(parsed.title == "Lari", "\(text): title")
    }
    // "Akhir pekan" with no "setiap" is one day.
    let day = parse("Cuci mobil akhir pekan")
    #expect(day.recurrence == nil)
    #expect(day.plannedDayOffset == 4)
    #expect(day.title == "Cuci mobil")
    // A repeat with a time.
    let timed = parse("Yoga setiap Selasa dan Kamis jam 19.30")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(timed.startMinutes == 19 * 60 + 30)
    #expect(timed.title == "Yoga")
    let evening = parse("Yoga setiap Selasa jam 7 malam")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    #expect(evening.startMinutes == 19 * 60)
    let morning = parse("Lari setiap Senin pagi jam 6")
    #expect(morning.recurrence == monday)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "Lari")
    // A part of the day after the weekdays is part of the repeat phrase, and a time keeps its part of the day.
    let friday = parse("Pengajian setiap Jumat malam")
    #expect(friday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(friday.title == "Pengajian")
    #expect(friday.phrases.map(\.text) == ["setiap Jumat malam"])
    let late = parse("Pengajian setiap Jumat malam jam 8")
    #expect(late.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(late.startMinutes == 20 * 60)
    #expect(late.title == "Pengajian")
    // A compound with a hyphen is no part of the day.
    let early = parse("Lari setiap Senin pagi-pagi")
    #expect(early.recurrence == monday)
    #expect(early.title == "Lari pagi-pagi")
    let weekendTimed = parse("Cuci baju setiap akhir pekan jam 10")
    #expect(weekendTimed.recurrence == weekend)
    #expect(weekendTimed.startMinutes == 10 * 60)
    #expect(weekendTimed.title == "Cuci baju")
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [15])
    for text in [
      "Sewa setiap tanggal 15", "Sewa tiap tgl 15", "Sewa setiap tgl. 15", "Sewa setiap bulan tanggal 15",
      "Sewa setiap bulan pada tanggal 15", "Sewa tanggal 15 setiap bulan",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 23, "\(text): start")
      #expect(parsed.title == "Sewa", "\(text): title")
    }
    let first = TaskRecurrenceRule(freq: .monthly, byMonthDay: [1])
    for text in ["Sewa setiap tanggal 1", "Sewa tiap bulan tgl 1"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == first, "\(text)")
      #expect(parsed.recurrenceStartOffset == 9, "\(text): start")
    }
    // An amount after "setiap bulan" is no day of the month.
    let amount = parse("Sewa setiap bulan 15 juta")
    #expect(amount.recurrence == monthly)
    #expect(amount.title == "Sewa 15 juta")
  }

  @Test("A weekday by its place in the month stays whole, and a count of times or a noun made of a cadence word stays")
  func unreadRepeats() {
    expectLinesUnread(
      [
        // A weekday by its place in the month has no repeat rule, so no part of it is read as a weekday.
        "Lari setiap Senin pertama", "Lari Senin terakhir bulan ini", "Lari setiap Jumat kedua",
        // Every day with a day left out has no repeat rule.
        "Lari setiap hari kecuali Minggu", "Lari setiap hari selain Sabtu",
        // A count of times in a period, and an interval of hours.
        "Lari dua kali seminggu", "Lari 3 kali sebulan", "Lari 2 kali sehari", "Lari setiap 2 jam",
        "Lari setiap 30 menit",
        // A holiday, an ordinal week, a named month, a list of days of the month, or a count of working days.
        "Lari setiap hari libur", "Lari setiap hari Natal", "Lari setiap minggu pertama",
        "Lari setiap bulan Oktober", "Lari setiap tanggal 5 dan 20", "Lari setiap 3 hari kerja",
        "Lari dalam 5 hari kerja", "Lari hari kerja",
        // A noun made of a cadence word, or an adjective that is not at the end of the line.
        "Tulis buku harian", "Baca koran harian", "Laporan harian untuk tim", "Harian Kompas",
      ], languages: ["id"])
  }

  // MARK: - Priorities

  @Test("Priorities: penting, mendesak, urgent, segera, prioritas tinggi or rendah, and prio")
  func priorities() {
    let priorities: [(text: String, title: String, priority: LorvexTask.Priority)] = [
      ("Laporan penting", "Laporan", .p1), ("Laporan penting.", "Laporan", .p1), ("Laporan penting!", "Laporan", .p1),
      ("Laporan sangat penting", "Laporan", .p1), ("Laporan penting sekali", "Laporan", .p1),
      ("Laporan mendesak", "Laporan", .p1), ("Laporan urgent", "Laporan", .p1), ("Laporan darurat", "Laporan", .p1),
      ("Laporan segera", "Laporan", .p1), ("Penting: laporan", "laporan", .p1), ("Segera, laporan", "laporan", .p1),
      ("Laporan prioritas tinggi", "Laporan", .p1), ("Laporan prioritas utama", "Laporan", .p1),
      ("Laporan prioritas 1", "Laporan", .p1), ("Laporan prio 1", "Laporan", .p1),
      ("Laporan prio: tinggi", "Laporan", .p1), ("Laporan dengan prioritas tinggi", "Laporan", .p1),
      ("Laporan prioritas sangat tinggi", "Laporan", .p1), ("Prioritas tinggi: laporan", "laporan", .p1),
      ("Laporan prioritas sedang", "Laporan", .p2), ("Laporan prioritas 2", "Laporan", .p2),
      ("Laporan prioritas menengah", "Laporan", .p2), ("Laporan prio 2", "Laporan", .p2),
      ("Laporan prioritas rendah", "Laporan", .p3), ("Laporan prioritas 3", "Laporan", .p3),
      ("Laporan prio rendah", "Laporan", .p3), ("Prioritas rendah laporan", "laporan", .p3),
      ("Laporan PENTING", "Laporan", .p1), ("Laporan PRIORITAS TINGGI", "Laporan", .p1),
      // The shorthand every language reads.
      ("Laporan !", "Laporan", .p1), ("Laporan p1", "Laporan", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A negated word, a word that opens a sentence, a word in the middle of a line, and a priority that is
    // no level are no priority.
    expectLinesUnread(
      [
        "Penting laporan", "Laporan tidak penting", "Laporan bukan urgent", "Laporan kurang mendesak",
        "Laporan tidak terlalu penting", "Laporan belum mendesak", "Dokumen penting dibawa", "Laporan penting dikirim",
        "Laporan prioritas 4", "Laporan prioritas", "Laporan penting: kirim", "Laporan nggak penting",
      ], languages: ["id"])
    // The word in the middle of a line stays in the title, and what follows it reads.
    let middle = parse("Laporan penting besok jam 15")
    #expect(middle.title == "Laporan penting")
    #expect(middle.priority == nil)
    #expect(middle.plannedDayOffset == 1)
    #expect(middle.startMinutes == 15 * 60)
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyDetail() {
    let line = parse("Tulis laporan besok jam 15 2 jam penting")
    #expect(line.title == "Tulis laporan")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.priority == .p1)
    #expect(line.phrases.map(\.text) == ["besok", "jam 15", "2 jam", "penting"])
    let recurring = parse("Lari setiap Senin jam 18 1 jam prioritas tinggi")
    #expect(recurring.title == "Lari")
    #expect(recurring.recurrence == monday)
    #expect(recurring.startMinutes == 18 * 60)
    #expect(recurring.estimatedMinutes == 60)
    #expect(recurring.priority == .p1)
    let due = parse("Pajak sebelum 31 Juli prio 2")
    #expect(due.title == "Pajak")
    #expect(due.dueDayOffset == captureDayOffset("2027-07-31"))
    #expect(due.priority == .p2)
    let lunch = parse("Makan siang dengan Ani besok jam 12.30 1 jam")
    #expect(lunch.title == "Makan siang dengan Ani")
    #expect(lunch.plannedDayOffset == 1)
    #expect(lunch.startMinutes == 12 * 60 + 30)
    #expect(lunch.estimatedMinutes == 60)
    // Lists and tags beside Indonesian details.
    let list = LorvexCaptureParser.parse(
      "Belanja #Rumah besok", lists: [.init(id: "L1", name: "Rumah")], todayWeekday: 3, today: "2026-09-22",
      languages: ["id"])
    #expect(list.listName == "Rumah")
    #expect(list.plannedDayOffset == 1)
    #expect(list.title == "Belanja")
    let tag = parse("Belanja hari ini #pribadi")
    #expect(tag.tags == ["pribadi"])
    #expect(tag.plannedDayOffset == 0)
    #expect(tag.title == "Belanja")
    let tagFirst = parse("#kerja Rapat besok jam 3")
    #expect(tagFirst.tags == ["kerja"])
    #expect(tagFirst.plannedDayOffset == 1)
    #expect(tagFirst.startMinutes == 15 * 60)
    #expect(tagFirst.title == "Rapat")
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Nouns made of a day word, a time word, or a number word.
        "Jam tangan baru", "Beli jam dinding", "Jam kerja kantor", "Sarapan pagi", "Selamat malam", "Kelas malam",
        "Hari raya", "Hari ulang tahun", "Minggu Palma", "Pekan olahraga", "Bulan madu", "Setengah matang",
        "Pukulan keras",
        // "Jam" as a clock or a watch is no hours amount.
        "Beli 2 jam tangan", "Beli 2 jam dinding", "Beli dua jam pasir", "Beli 3 jam weker",
        // Numbers that are counts, places, and amounts.
        "Beli 3 apel", "Bayar Rp 15.000", "Bayar 15 ribu", "Bertemu 3 teman", "Bab 3", "Halaman 15", "Kamar 15",
        "Lantai 3", "Versi 2.3", "Sprint 12", "Tugas 3", "Telepon 0812 3456 7890", "Lari 5 km", "Beli 3 kg beras",
        "Baca 30 halaman", "Tiket untuk 3 orang", "Menginap 3 hari", "Kerjakan PR matematika",
        "Pertemuan kedua dengan klien", "Tagihan: listrik, air", "Pasal 15",
        // A quantity of time that is a duration of something else.
        "Rapat dalam 2 jam", "Telepon aku dalam 10 menit",
      ], languages: ["id"])
    // A line that opens with a time keeps the rest as the title.
    let lead = parse("Jam 5 presentasi")
    #expect(lead.startMinutes == 17 * 60)
    #expect(lead.title == "presentasi")
  }

  @Test("A hyphen joins a compound that is no day, and extra spaces or punctuation between details change nothing")
  func hyphensAndSpacing() {
    expectLinesUnread(["Laporan besok-besok", "Laporan hari-hari", "Laporan pagi-pagi jam-jam"], languages: ["id"])
    let spaced = parse("Laporan   jam   15")
    #expect(spaced.startMinutes == 15 * 60)
    #expect(spaced.title == "Laporan")
    let tabbed = parse("Laporan setiap\tSenin")
    #expect(tabbed.recurrence == monday)
    #expect(tabbed.title == "Laporan")
    for text in ["Laporan besok, jam 15", "Laporan besok; jam 15"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "Laporan", "\(text): title")
    }
  }

  @Test("Capitals read like lowercase letters, and the title keeps the capitals it was typed with")
  func capitals() {
    let lines: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("DOKTER GIGI BESOK", "DOKTER GIGI", { $0.plannedDayOffset == 1 }),
      ("LAPORAN SABTU", "LAPORAN", { $0.plannedDayOffset == 4 }),
      ("RAPAT JAM 15", "RAPAT", { $0.startMinutes == 15 * 60 }),
      ("RAPAT JAM 3 SORE", "RAPAT", { $0.startMinutes == 15 * 60 }),
      ("RAPAT SETENGAH EMPAT", "RAPAT", { $0.startMinutes == 15 * 60 + 30 }),
      ("LAPORAN SEBELUM JUMAT", "LAPORAN", { $0.dueDayOffset == 3 }),
      ("LAPORAN SEBELUM 15 OKTOBER", "LAPORAN", { $0.dueDayOffset == 23 }),
      ("LAPORAN PADA 15 OKTOBER", "LAPORAN", { $0.plannedDayOffset == 23 }),
      ("LARI SETIAP SENIN", "LARI", { $0.recurrence == monday }),
      ("LARI SETIAP HARI KERJA", "LARI", { $0.recurrence == workdays }),
      ("LAPORAN BULANAN", "LAPORAN", { $0.recurrence == monthly }),
      ("RAPAT 2 JAM", "RAPAT", { $0.estimatedMinutes == 120 }),
      ("RAPAT SETENGAH JAM", "RAPAT", { $0.estimatedMinutes == 30 }),
      ("LAPORAN PENTING", "LAPORAN", { $0.priority == .p1 }),
      ("LAPORAN PRIORITAS RENDAH", "LAPORAN", { $0.priority == .p3 }),
      ("Laporan SELASA jam 15", "Laporan", { $0.plannedDayOffset == 7 && $0.startMinutes == 15 * 60 }),
      ("Laporan JUMAT SORE", "Laporan", { $0.plannedDayOffset == 3 }),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(line.check(parsed), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Indonesian, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Indonesian beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Meet at 15h",
      "Meet 10h", "Call mom tonight", "Dinner tomorrow evening", "Meeting at 9:30", "Walk 45 min every day",
    ] {
      for languages in [["en", "id"], ["id", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Indonesian writes its hours with "jam" or "pukul" or a colon, so "15h" and "2h" are lengths beside it.
    let hours = parse("Write the report 2h", languages: ["en", "id"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "id"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    // "Dalam 15 menit" is a moment in Indonesian, so beside it English's "in 15 min" is no length only
    // where the Indonesian word stands before the amount.
    let moment = parse("Telepon dalam 15 menit", languages: ["en", "id"])
    #expect(moment.estimatedMinutes == nil)
    #expect(moment.title == "Telepon dalam 15 menit")
    // A line may mix both languages.
    let mixed = parse("Call Ibu besok at 3pm", languages: ["en", "id"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call Ibu")
    let weekday = parse("Meeting Jumat at 3pm", languages: ["en", "id"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Dokter gigi tomorrow", languages: ["en", "id"]).plannedDayOffset == 1)
    let review = parse("Review besok jam 15.00 for 2 hours", languages: ["en", "id"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english = parse("Laporan besok 3pm")
    #expect(english.plannedDayOffset == 1)
    #expect(english.startMinutes == 15 * 60)
    #expect(english.title == "Laporan")
    #expect(parse("Rapat 15h").estimatedMinutes == 15 * 60)
    #expect(parse("Laporan 30 min besok").estimatedMinutes == 30)
    #expect(parse("Laporan besok 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("Rapat tomorrow").plannedDayOffset == 1)
  }

  @Test("Lines in other languages read the same with Indonesian beside them")
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
      ("Dentist poimâine", "ro"), ("Alergare în fiecare luni", "ro"), ("Ședință la ora 15", "ro"),
      ("Raport până vineri", "ro"), ("Vacanță de la 3 la 5 mai", "ro"),
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "id"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["id", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Indonesian with another language.
    for languages in [["fr", "id"], ["id", "fr"]] {
      let mixed = parse("Appeler maman besok jam 15", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Appeler maman demain à 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dokter gigi lusa", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste 3 mai", languages: languages).plannedDayOffset == captureDayOffset("2027-05-03"), "\(languages)")
      #expect(parse("Lari setiap Senin", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Laporan penting", languages: languages).priority == .p1, "\(languages)")
      expectDateRanges(
        [
          ("Vacances", "du 3 au 5 mai", "2027-05-03", "2027-05-05"),
          ("Liburan", "dari 3 sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ], languages: languages)
    }
    #expect(parse("Dokter gigi 下午3点 besok", languages: ["zh", "id"]).plannedDayOffset == 1)
    #expect(parse("Dokter gigi מחר", languages: ["he", "id"]).plannedDayOffset == 1)
    // Indonesian beside Dutch, German, or Romanian: each keeps its own words. "Oktober" is the same month in
    // all of them, and "besok" belongs to Indonesian alone.
    for languages in [["nl", "id"], ["id", "nl"], ["de", "id"], ["id", "de"], ["ro", "id"], ["id", "ro"]] {
      #expect(parse("Dokter gigi besok jam 15", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Lari setiap Senin", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Dokter gigi 15 Oktober", languages: languages).plannedDayOffset == 23, "\(languages)")
      #expect(parse("Tandarts overmorgen", languages: languages).plannedDayOffset == (languages.contains("nl") ? 2 : nil), "\(languages)")
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == (languages.contains("de") ? 2 : nil), "\(languages)")
      #expect(parse("Dentist poimâine", languages: languages).plannedDayOffset == (languages.contains("ro") ? 2 : nil), "\(languages)")
    }
  }

  @Test("Indonesian words are read only for a user who reads Indonesian")
  func languageGate() {
    let line = parse("Dokter gigi lusa", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Dokter gigi lusa")
    for languages in [["id"], ["id-ID"], ["id_ID"], ["en-US", "id-ID"], ["ID"]] {
      #expect(parse("Dokter gigi lusa", languages: languages).plannedDayOffset == 2, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for an Indonesian reader.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen", "Dentist poimâine",
      ], languages: ["id"])
    // Indonesian words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"], ["ro"], ["ar"]] {
      let parsed = parse("Dokter gigi lusa", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Dokter gigi lusa", "\(languages): title")
      #expect(parse("Rapat jam 3 sore", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("Lari setiap Senin", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("jam 15 ", 714), ("jam 3 ", 833), ("pukul 3 ", 625), ("3 ", 2500), ("dari ", 1000), ("antara ", 714),
      ("antara 3 dan 5 ", 333), ("dari jam 3 sampai jam 5 ", 208), ("14-16 ", 833), ("14.00-16.00 ", 416),
      ("15.30 ", 833), ("15:30 ", 833), ("jam 3 lewat 15 ", 333), ("jam 3 kurang ", 384), ("jam 3 kurang seperempat ", 200),
      ("setengah ", 555), ("setengah empat ", 357), ("besok ", 833), ("besok pagi ", 454), ("malam ini ", 500),
      ("nanti malam ", 416), ("Senin ", 833), ("setiap Senin ", 454), ("setiap hari kerja ", 277),
      ("dari Senin sampai Jumat ", 208), ("2 hari sekali ", 357), ("sekali ", 833), ("setiap ", 714),
      ("tanggal 15 ", 454), ("15 Oktober ", 454), ("15.10.2026 ", 454), ("3-5 Mei ", 625),
      ("dari 3 sampai 5 Mei ", 250), ("Mei ", 1250), ("Sprint 12 - 20 Mei ", 263), ("sebelum Jumat ", 357),
      ("sebelum ", 625), ("paling lambat ", 384), ("dalam 3 hari ", 384), ("3 hari lagi ", 416),
      ("minggu depan ", 384), ("akhir pekan ", 416), ("30 menit ", 625), ("2 jam ", 833), ("1,5 jam ", 625),
      ("setengah jam ", 384), ("sejam ", 833), ("penting ", 625), ("prioritas tinggi ", 294), ("prio ", 1000),
      ("malam ", 833), (", ", 2500), (".", 5000), ("dan ", 1250), ("jam ", 1250), ("pukul ", 833), ("pada ", 1250),
      ("tengah malam ", 384), ("tengah ", 833), ("sampai ", 714), ("hingga ", 714), ("s/d ", 1250),
      ("jam 8 malam ", 454), ("makan malam ", 454), ("Minggu ", 714), ("hari Minggu ", 454), ("setiap Minggu pagi ", 263),
      ("Jumat sore jam 5 ", 294), ("sebelum Jumat jam 5 ", 250), ("tgl. 15 ", 625), ("lusa ", 1000),
      ("kemarin lusa ", 416), ("malam Jumat ", 416),
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for entry in unit {
        let line = "Ani " + String(repeating: entry.token, count: entry.repeats) + " Telepon"
        let each = clock.measure {
          let parsed = parse(line)
          #expect(!parsed.title.isEmpty, "\(entry.token)")
        }
        #expect(each < .seconds(2), "\(entry.token) took \(each)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}
