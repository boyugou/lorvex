import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ms"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["ms"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weekly = TaskRecurrenceRule(freq: .weekly)
private let monthly = TaskRecurrenceRule(freq: .monthly)
private let yearly = TaskRecurrenceRule(freq: .yearly)

/// Malay capture lines, read for a user whose languages include Malay.
@Suite("Capture parser Malay")
struct CaptureParserMalayTests {
  // MARK: - Days

  @Test("Days: hari ini, esok, lusa, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Doktor gigi esok")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Doktor gigi")
    #expect(line.phrases.map(\.text) == ["esok"])

    let days: [(text: String, offset: Int)] = [
      ("Doktor gigi hari ini", 0), ("Doktor gigi pagi ini", 0), ("Doktor gigi tengah hari ini", 0),
      ("Doktor gigi tengahari ini", 0), ("Doktor gigi petang ini", 0), ("Doktor gigi malam ini", 0),
      ("Doktor gigi nanti petang", 0), ("Doktor gigi nanti malam", 0), ("Doktor gigi petang nanti", 0),
      ("Doktor gigi malam nanti", 0),
      ("Doktor gigi esok", 1), ("Doktor gigi besok", 1), ("Doktor gigi esok pagi", 1),
      ("Doktor gigi esok tengah hari", 1), ("Doktor gigi esok tengahari", 1), ("Doktor gigi esok petang", 1),
      ("Doktor gigi esok malam", 1), ("Doktor gigi pagi esok", 1), ("Doktor gigi petang esok", 1),
      ("Doktor gigi malam esok", 1),
      ("Doktor gigi lusa", 2), ("Doktor gigi lusa pagi", 2), ("Doktor gigi lusa malam", 2),
      ("Doktor gigi 3 hari lagi", 3), ("Doktor gigi tiga hari lagi", 3), ("Doktor gigi dalam 3 hari", 3),
      ("Doktor gigi dalam tiga hari", 3), ("Doktor gigi dalam 3 hari lagi", 3), ("Doktor gigi sehari lagi", 1),
      ("Doktor gigi seminggu lagi", 7), ("Doktor gigi 2 minggu lagi", 14), ("Doktor gigi dua minggu lagi", 14),
      ("Doktor gigi dalam 2 minggu", 14), ("Doktor gigi dalam 10 hari", 10), ("Doktor gigi sepuluh hari lagi", 10),
      ("Doktor gigi dua belas hari lagi", 12),
      ("Doktor gigi minggu depan", 7), ("Doktor gigi minggu hadapan", 7),
      ("Doktor gigi hujung minggu", 4), ("Doktor gigi hujung minggu ini", 4), ("Doktor gigi di hujung minggu", 4),
      ("Doktor gigi pada hujung minggu", 4), ("Doktor gigi weekend", 4), ("Doktor gigi hujung minggu depan", 11),
      ("Doktor gigi hujung minggu hadapan", 11), ("Doktor gigi Sabtu dan Ahad", 4),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Doktor gigi", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Esok doktor gigi")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "doktor gigi")
    let sentence = parse("Esok ada ujian")
    #expect(sentence.plannedDayOffset == 1)
    #expect(sentence.title == "ada ujian")
    // A dinner is a noun until a weekday follows it.
    let dinner = parse("Makan malam Jumaat")
    #expect(dinner.plannedDayOffset == 3)
    #expect(dinner.title == "Makan malam")
  }

  @Test("Past days and days that cannot be named are not read")
  func pastAndVagueDays() {
    expectLinesUnread(
      [
        // Past days.
        "Doktor gigi semalam", "Doktor gigi kelmarin", "Doktor gigi kemarin", "Doktor gigi Isnin lepas",
        "Doktor gigi Selasa lalu", "Doktor gigi hari Jumaat lepas", "Doktor gigi Jumaat yang lalu",
        "Doktor gigi minggu lepas", "Doktor gigi minggu lalu", "Doktor gigi hujung minggu lepas",
        "Doktor gigi malam tadi", "Doktor gigi pagi tadi", "Doktor gigi tadi", "Doktor gigi 2 hari lalu",
        // "Esok lusa" is tomorrow or the day after, and "malam Jumaat" the night before Friday.
        "Doktor gigi esok lusa", "Doktor gigi malam Jumaat", "Doktor gigi malam Sabtu",
        // A month or a year ahead has no day offset, and a count of working days is no count of days.
        "Doktor gigi bulan depan", "Doktor gigi sebulan lagi", "Doktor gigi tahun depan",
        "Doktor gigi dalam 3 hari bekerja", "Doktor gigi dalam 3 hari kerja",
        // "Dalam seminggu" is as often "per week" as "in a week", and "dalam masa" sets a limit.
        "Doktor gigi dalam seminggu", "Doktor gigi dalam masa 3 hari",
        // A count of times in a period is a rate, not a day.
        "Latihan tiga kali dalam seminggu", "Latihan tiga kali dalam 2 hari",
        // Hyphenated words are compounds, not days.
        "Doktor gigi esok-esok", "Doktor gigi hari-hari", "Doktor gigi pagi-pagi",
      ], languages: ["ms"])
    // The time that follows a past day still reads.
    let time = parse("Doktor gigi semalam pukul 3")
    #expect(time.plannedDayOffset == nil)
    #expect(time.startMinutes == 15 * 60)
    #expect(time.title == "Doktor gigi semalam")
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Doktor gigi Isnin", 6), ("Doktor gigi Selasa", 7), ("Doktor gigi Rabu", 1), ("Doktor gigi Khamis", 2),
      ("Doktor gigi Jumaat", 3), ("Doktor gigi Juma'at", 3), ("Doktor gigi Juma\u{2019}at", 3),
      ("Doktor gigi Sabtu", 4), ("Doktor gigi Ahad", 5), ("Doktor gigi hari Ahad", 5),
      ("Doktor gigi hari Isnin", 6), ("Doktor gigi pada Jumaat", 3), ("Doktor gigi pada hari Jumaat", 3),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "Selasa ini" is today.
      ("Doktor gigi Selasa ini", 0), ("Doktor gigi Rabu ini", 1), ("Doktor gigi Jumaat ini", 3),
      ("Doktor gigi hari Jumaat ini", 3), ("Doktor gigi hari Ahad ini", 5),
      ("Doktor gigi Isnin depan", 6), ("Doktor gigi Selasa depan", 7), ("Doktor gigi Rabu depan", 8),
      ("Doktor gigi Jumaat depan", 10), ("Doktor gigi hari Jumaat depan", 10), ("Doktor gigi hari Ahad depan", 12),
      ("Doktor gigi Jumaat hadapan", 10), ("Doktor gigi Jumaat minggu depan", 10),
      ("Doktor gigi Jumaat minggu hadapan", 10), ("Doktor gigi minggu depan Jumaat", 10),
      ("Doktor gigi Isnin minggu depan", 6),
      // A part of the day written after the weekday, or before it for the day's own parts.
      ("Doktor gigi Jumaat pagi", 3), ("Doktor gigi Jumaat petang", 3), ("Doktor gigi Jumaat malam", 3),
      ("Doktor gigi Sabtu tengah hari", 4), ("Doktor gigi pagi Isnin", 6), ("Doktor gigi petang Jumaat", 3),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Doktor gigi", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("Doktor gigi Isnin pukul 9")
    #expect(timed.plannedDayOffset == 6)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Doktor gigi")
    let opening = parse("Isnin mesyuarat")
    #expect(opening.plannedDayOffset == 6)
    #expect(opening.title == "mesyuarat")
  }

  @Test("Minggu is the week, never Sunday; Sunday is Ahad")
  func minggu() {
    for text in [
      "Doktor gigi Ahad", "Doktor gigi hari Ahad", "Doktor gigi pada hari Ahad", "Doktor gigi Ahad pagi",
      "Doktor gigi Ahad petang", "Doktor gigi Ahad malam",
    ] {
      #expect(parse(text).plannedDayOffset == 5, "\(text)")
    }
    #expect(parse("Doktor gigi minggu depan").plannedDayOffset == 7)
    // "Minggu" alone, "minggu ini", and a week gone stay in the title.
    expectLinesUnread(
      ["Doktor gigi Minggu", "Doktor gigi hari Minggu", "Doktor gigi minggu ini", "Doktor gigi minggu lepas"],
      languages: ["ms"])
    // A prayer or a holiday named after Friday is a name, not a day.
    expectLinesUnread(["Solat Jumaat", "Sembahyang Jumaat", "Khutbah Jumaat", "Cuti Jumaat Agung"], languages: ["ms"])
    let prayer = parse("Solat Jumaat esok")
    #expect(prayer.plannedDayOffset == 1)
    #expect(prayer.title == "Solat Jumaat")
    // Saturday and Sunday together plan from Saturday.
    let pair = parse("Doktor gigi Sabtu dan Ahad")
    #expect(pair.plannedDayOffset == 4)
    #expect(pair.title == "Doktor gigi")
  }

  @Test("A list of weekdays names no one day and stays in the title; after setiap it is a repeat")
  func weekdayLists() {
    expectLinesUnread(
      [
        "Kelas Isnin dan Rabu", "Kelas Isnin atau Selasa", "Kelas Isnin, Rabu dan Jumaat", "Kelas hari Isnin dan hari Rabu",
        "Kelas Jumaat pagi dan Sabtu petang", "Kelas Isnin & Khamis", "Kelas Jumaat dan Ahad",
      ], languages: ["ms"])
    #expect(parse("Kelas setiap Isnin dan Rabu").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE"]))
    // A weekday next to a date, or before a comma and a time, still reads.
    #expect(parse("Kelas Jumaat, 16 Oktober").plannedDayOffset == captureDayOffset("2026-10-16"))
    #expect(parse("Kelas Isnin, pukul 9").plannedDayOffset == 6)
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("Laporan hujung minggu", 0), ("Laporan weekend", 0), ("Laporan hujung minggu depan", 7),
      ("Laporan Sabtu", 7), ("Laporan hari Ahad", 1), ("Laporan Sabtu ini", 0), ("Laporan Isnin", 2),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("Laporan hujung minggu", 0), ("Laporan weekend", 0), ("Laporan hujung minggu depan", 7),
      ("Laporan hari Ahad", 7), ("Laporan hari Ahad ini", 0), ("Laporan hari Ahad depan", 7),
      ("Laporan Sabtu", 6), ("Laporan Isnin", 1), ("Laporan Isnin ini", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "Isnin ini" is today.
    for (text, offset) in [("Laporan Isnin", 7), ("Laporan Isnin ini", 0), ("Laporan Isnin depan", 7), ("Laporan Selasa", 1)] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("Laporan hingga Isnin", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("Senaman setiap Isnin", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("Laporan dari Isnin hingga Rabu", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
    let tuesdayToThursday = parse("Laporan dari Selasa hingga Khamis", on: "2026-09-21", weekday: 2)
    #expect(tuesdayToThursday.plannedDayOffset == 1)
    #expect(tuesdayToThursday.dueDayOffset == 3)
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, hb, numbers, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Hantar laporan 15 Oktober", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan tarikh 15 Oktober", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan pada 15 Oktober", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan pada tarikh 15 Oktober", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15 Okt", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15 Okt.", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15hb Oktober", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15 hb Oktober", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15hb. Okt", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15 Oktober 2026", "Hantar laporan", "2026-10-15"),
      ("HANTAR LAPORAN PADA 15 OKTOBER", "HANTAR LAPORAN", "2026-10-15"),
      ("Hantar laporan 1 Mei 2027", "Hantar laporan", "2027-05-01"),
      ("Hantar laporan 15.10.2026", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15/10/2026", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15-10-2026", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 15/10/26", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan pada 15/10", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan tarikh 15/10", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan pada 15-10", "Hantar laporan", "2026-10-15"),
      ("Hantar laporan 3 Januari", "Hantar laporan", "2027-01-03"),
      ("Hantar laporan 3 Jan", "Hantar laporan", "2027-01-03"),
      ("Hantar laporan 3 Februari", "Hantar laporan", "2027-02-03"),
      ("Hantar laporan 3 Feb", "Hantar laporan", "2027-02-03"),
      ("Hantar laporan 3 Mac", "Hantar laporan", "2027-03-03"),
      ("Hantar laporan 3 April", "Hantar laporan", "2027-04-03"),
      ("Hantar laporan 3 Apr", "Hantar laporan", "2027-04-03"),
      ("Hantar laporan 3 Mei", "Hantar laporan", "2027-05-03"),
      ("Hantar laporan 3 Jun", "Hantar laporan", "2027-06-03"),
      ("Hantar laporan 3 Julai", "Hantar laporan", "2027-07-03"),
      ("Hantar laporan 3 Jul", "Hantar laporan", "2027-07-03"),
      ("Hantar laporan 3 Ogos", "Hantar laporan", "2027-08-03"),
      ("Hantar laporan 3 Ogo", "Hantar laporan", "2027-08-03"),
      ("Hantar laporan 3 September", "Hantar laporan", "2027-09-03"),
      ("Hantar laporan 3 Sept", "Hantar laporan", "2027-09-03"),
      ("Hantar laporan 3 Sep", "Hantar laporan", "2027-09-03"),
      ("Hantar laporan 3 Oktober", "Hantar laporan", "2026-10-03"),
      ("Hantar laporan 3 November", "Hantar laporan", "2026-11-03"),
      ("Hantar laporan 3 Nov", "Hantar laporan", "2026-11-03"),
      ("Hantar laporan 3 Disember", "Hantar laporan", "2026-12-03"),
      ("Hantar laporan 3 Dis", "Hantar laporan", "2026-12-03"),
      ("Hantar laporan 22 September", "Hantar laporan", "2026-09-22"),
      // A day of the month alone is this month's, or next month's once it has passed.
      ("Hantar laporan tarikh 25", "Hantar laporan", "2026-09-25"),
      ("Hantar laporan pada tarikh 25", "Hantar laporan", "2026-09-25"),
      ("Hantar laporan tarikh 5", "Hantar laporan", "2026-10-05"),
      ("Hantar laporan 25hb", "Hantar laporan", "2026-09-25"),
      ("Hantar laporan pada 25hb", "Hantar laporan", "2026-09-25"),
      ("Hantar laporan 5hb", "Hantar laporan", "2026-10-05"),
      // A weekday before the date is part of it.
      ("Hantar laporan Jumaat 16 Oktober", "Hantar laporan", "2026-10-16"),
      ("Hantar laporan Jumaat, 16 Oktober", "Hantar laporan", "2026-10-16"),
      ("Hantar laporan hari Jumaat 16 Oktober", "Hantar laporan", "2026-10-16"),
      ("Hantar laporan Ahad, 4 Oktober", "Hantar laporan", "2026-10-04"),
      ("Hari jadi Ibu 14 Mac", "Hari jadi Ibu", "2027-03-14"),
      ("Cuti 1 Disember", "Cuti", "2026-12-01"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Mesyuarat Khamis 15 Oktober pukul 2.30 petang")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Mesyuarat")
    let concert = parse("Konsert 20 Okt. pukul 19")
    #expect(concert.plannedDayOffset == captureDayOffset("2026-10-20"))
    #expect(concert.startMinutes == 19 * 60)
    #expect(concert.title == "Konsert")
  }

  @Test("Numbers that are no date, a past year, a day the month does not have, and Mac or HB stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers without a word that makes them a date, and a bare month.
        "Hantar laporan 15/10", "Hantar laporan 15-10", "Cuti pada bulan Mei", "Mei", "Laporan Mei 2027",
        // A day the month does not have, and a year that is past.
        "Hantar laporan 31 Februari", "Hantar laporan 15 Oktober 2025",
        // Chapters, versions, rooms, scores, percentages, prices, quarters, and phone numbers.
        "Bab 1.5.", "Versi 2.3.4", "Muka surat 15-10", "Bilik 15.10", "Skor 3-1", "Diskaun 15%", "Harga 15,50",
        "Harga 15.30", "iOS 17.4", "Q3 2026", "Telefon 012 345 6789",
        // A computer's name is not March, and "2HB" is a pencil.
        "Beli 2 Mac mini", "Beli 2 Mac Pro", "Beli 3 MacBook", "Beli pensel 2HB",
      ], languages: ["ms"])
    // A short date after a number of the title that names an item is no date.
    expectLinesUnread(["Baca pada bab 3-1", "Pelajari pada muka surat 15-10"], languages: ["ms"])
    // "Tanggal" and "tgl" are the Indonesian words for a date, which Malay leaves to Indonesian.
    expectLinesUnread(["Hantar laporan tanggal 15 Oktober", "Hantar laporan tgl. 15 Okt"], languages: ["ms"])
    // A lowercase "hb" is the day's abbreviation.
    let pencil = parse("Beli pensel 2hb")
    #expect(pencil.plannedDayOffset == captureDayOffset("2026-10-02"))
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Percutian", "3-5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "3 hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "3 sehingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "3 sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3 hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3 sehingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3 sampai 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3 - 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3hb hingga 5hb Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "3hb hingga 5hb Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari tarikh 3 hingga tarikh 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "antara 3 dan 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "pada 3-5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "tarikh 3-5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "3 Mei - 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "3 Mei hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3 Mei hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "dari 3 Mei sehingga 5 Mei", "2027-05-03", "2027-05-05"),
        ("Percutian", "30 Mei - 2 Jun", "2027-05-30", "2027-06-02"),
        ("Percutian", "dari 30 Mei hingga 2 Jun", "2027-05-30", "2027-06-02"),
        ("Percutian", "3-5 Mei 2027", "2027-05-03", "2027-05-05"),
        ("Percutian", "5 hingga 9 Oktober", "2026-10-05", "2026-10-09"),
        ("Percutian akhir tahun", "24 Dis - 2 Jan", "2026-12-24", "2027-01-02"),
        ("Percutian akhir tahun", "24 Disember hingga 2 Januari", "2026-12-24", "2027-01-02"),
      ], languages: ["ms"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Percutian 5-3 Mei", "Percutian 3 Mei - 3 Mei", "Percutian antara 5 dan 3 Mei", "Percutian dari 5 hingga 3 Mei",
        "Harga 3-5 juta",
      ], languages: ["ms"])
    // Two bare numbers after "dari" are hours.
    let bare = parse("Mesyuarat dari 3 hingga 5")
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
    let meeting = parse("Mesyuarat 12 - 14 Oktober")
    #expect(meeting.title == "Mesyuarat 12")
    #expect(meeting.plannedDayOffset == captureDayOffset("2026-10-14"))
    #expect(meeting.dueDayOffset == nil)
    let holiday = parse("Percutian 3 - 5 Mei")
    #expect(holiday.title == "Percutian 3")
    #expect(holiday.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(holiday.dueDayOffset == nil)
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time or a length still reads")
  func rangeTakesBothDays() {
    let line = parse("Percutian 3-5 Mei esok")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Percutian esok")
    let timed = parse("Percutian 3-5 Mei pukul 9")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Percutian")
    let length = parse("Percutian 3-5 Mei 30 minit")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "Percutian")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    expectDateRanges(
      [
        ("Persidangan", "dari Isnin hingga Rabu", "2026-09-28", "2026-09-30"),
        ("Persidangan", "Isnin hingga Rabu", "2026-09-28", "2026-09-30"),
        ("Persidangan", "Isnin sehingga Rabu", "2026-09-28", "2026-09-30"),
        ("Persidangan", "dari Jumaat hingga Ahad", "2026-09-25", "2026-09-27"),
        ("Persidangan", "Jumaat hingga Ahad", "2026-09-25", "2026-09-27"),
        ("Persidangan", "dari Jumaat sampai Isnin", "2026-09-25", "2026-09-28"),
        ("Persidangan", "Jumaat - Ahad", "2026-09-25", "2026-09-27"),
        ("Persidangan", "Sabtu - Ahad", "2026-09-26", "2026-09-27"),
        ("Persidangan", "hari Jumaat hingga hari Ahad", "2026-09-25", "2026-09-27"),
        ("Sprint", "Isnin - Jumaat", "2026-09-28", "2026-10-02"),
        ("Sprint", "Isnin-Rabu", "2026-09-28", "2026-09-30"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Persidangan", "dari Selasa hingga Khamis", "2026-09-29", "2026-10-01"),
      ], languages: ["ms"])
    // Monday to Friday after "setiap", and the working days, repeat.
    for text in [
      "Senaman setiap Isnin hingga Jumaat", "Senaman tiap Isnin - Jumaat", "Senaman setiap hari bekerja",
      "Senaman setiap hari kerja", "Senaman tiap-tiap hari kerja", "Senaman pada hari bekerja",
      "Senaman pada hari kerja", "Senaman pada hari-hari kerja",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Senaman", "\(text): title")
    }
  }

  // MARK: - Due days

  @Test("Due days: sebelum, selewat-lewatnya, paling lewat, hingga, sehingga, tarikh akhir, had masa, and deadline")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Laporan sebelum Jumaat", "Laporan", 3),
      ("Laporan sebelum hari Jumaat", "Laporan", 3),
      ("Laporan sebelum esok", "Laporan", 1),
      ("Laporan sebelum lusa", "Laporan", 2),
      ("Laporan sebelum Isnin depan", "Laporan", 6),
      ("Laporan sebelum minggu depan", "Laporan", 7),
      ("Laporan sebelum Ahad", "Laporan", 5),
      ("Laporan sebelum Jumaat petang", "Laporan", 3),
      ("Laporan sebelum esok pagi", "Laporan", 1),
      ("Laporan sebelum 15 Oktober", "Laporan", 23),
      ("Laporan sebelum 15 Okt", "Laporan", 23),
      ("Laporan sebelum 15hb Oktober", "Laporan", 23),
      ("Laporan sebelum tarikh 15 Oktober", "Laporan", 23),
      ("Laporan sebelum tarikh 15", "Laporan", 23),
      ("Laporan sebelum 15hb", "Laporan", 23),
      ("Laporan sebelum 15/10", "Laporan", 23),
      ("Laporan sebelum 15/10/2026", "Laporan", 23),
      ("Laporan sebelum Khamis, 15 Oktober", "Laporan", 23),
      ("Laporan sebelum pada Jumaat", "Laporan", 3),
      ("Laporan selewat-lewatnya Jumaat", "Laporan", 3),
      ("Laporan selambat-lambatnya Jumaat", "Laporan", 3),
      ("Laporan paling lewat Jumaat", "Laporan", 3),
      ("Laporan paling lambat Jumaat", "Laporan", 3),
      ("Laporan paling lewat esok", "Laporan", 1),
      ("Laporan paling lewat 15 Oktober", "Laporan", 23),
      ("Laporan hingga Jumaat", "Laporan", 3),
      ("Laporan sehingga Jumaat", "Laporan", 3),
      ("Laporan sampai Jumaat", "Laporan", 3),
      ("Laporan sampai esok", "Laporan", 1),
      ("Laporan sehingga tarikh 15", "Laporan", 23),
      ("Laporan sehingga 15 Oktober", "Laporan", 23),
      ("Laporan tarikh akhir Jumaat", "Laporan", 3),
      ("Laporan tarikh akhir: Jumaat", "Laporan", 3),
      ("Laporan tarikh akhir: 15hb Oktober", "Laporan", 23),
      ("Laporan tarikh tamat Jumaat", "Laporan", 3),
      ("Laporan tarikh tutup Jumaat", "Laporan", 3),
      ("Laporan tarikh jangka Jumaat", "Laporan", 3),
      ("Laporan had masa Jumaat", "Laporan", 3),
      ("Laporan deadline Jumaat", "Laporan", 3),
      ("Laporan deadline: Jumaat", "Laporan", 3),
      ("Hantar laporan sebelum Jumaat", "Hantar laporan", 3),
      ("Beli hadiah sebelum Sabtu", "Beli hadiah", 4),
      ("Bayar bil sebelum tarikh 20", "Bayar bil", 28),
      ("LAPORAN SEBELUM JUMAAT", "LAPORAN", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Laporan sebelum Jumaat hari ini")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Laporan")
    // A due phrase that opens the line.
    let opening = parse("Sebelum Jumaat hantar laporan")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "hantar laporan")
    // A bound at the weekend names no due day, and neither does a bare number, a month ahead, or a person.
    expectLinesUnread(
      [
        "Laporan sebelum hujung minggu", "Laporan hingga hujung minggu", "Laporan hingga weekend",
        "Laporan selepas hujung minggu", "Laporan untuk hujung minggu", "Laporan sebelum bulan depan",
        "Laporan sehingga selesai", "Laporan sampai 5 orang", "Laporan untuk 3 hari", "Beli hadiah untuk Ibu",
        "Laporan sebelum minggu ini", "Bayar RM100 hingga 150", "Laporan sebelum Isnin atau Selasa",
      ], languages: ["ms"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Laporan sebelum pukul 17", "Laporan sebelum pukul 17.00", "Laporan hingga jam 5", "Laporan hingga pukul 17.00",
        "Laporan sebelum 17:00", "Laporan sebelum pukul 5 petang", "Laporan paling lewat pukul 5 petang",
        "Laporan paling lewat pukul 17.00", "Laporan selewat-lewatnya pukul 5", "Laporan selepas pukul 18",
        "Laporan menjelang tengah malam", "Laporan sehingga tengah malam", "Laporan deadline pukul 5",
        "Laporan tarikh akhir pukul 17.00", "Laporan sebelum pukul tiga", "Laporan sebelum 5 petang",
        "Laporan sebelum 5pm", "Laporan sehingga 17.00", "Laporan sebelum tengah hari", "Laporan sampai pukul 5 PTG",
      ], languages: ["ms"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Laporan sebelum Jumaat pukul 17", "Laporan pukul 17", 3),
      ("Laporan sebelum Jumaat pukul 17.00", "Laporan pukul 17.00", 3),
      ("Laporan sebelum Jumaat 17:00", "Laporan 17:00", 3), ("Laporan hingga Isnin pukul 9", "Laporan pukul 9", 6),
      ("Laporan paling lewat esok pukul 9.00", "Laporan pukul 9.00", 1),
      ("Laporan tarikh akhir: Jumaat pukul 17.00", "Laporan pukul 17.00", 3),
      ("Laporan sebelum Jumaat jam 5 petang", "Laporan jam 5 petang", 3),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A time range that ends in a clock time is still a range, and a bound after a day stays a bound.
    let range = parse("Mesyuarat dari pukul 14 hingga pukul 17.30")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 210)
    #expect(range.title == "Mesyuarat")
    let bound = parse("Mesyuarat sehingga pukul 17.30 esok")
    #expect(bound.plannedDayOffset == 1)
    #expect(bound.startMinutes == nil)
    #expect(bound.title == "Mesyuarat sehingga pukul 17.30")
    // The clock that ends a range of days is the range's time.
    let rangeTime = parse("Mesyuarat dari Isnin hingga Rabu pukul 9")
    #expect(rangeTime.plannedDayOffset == 6)
    #expect(rangeTime.dueDayOffset == 8)
    #expect(rangeTime.startMinutes == 9 * 60)
    #expect(rangeTime.title == "Mesyuarat")
    // Without Malay, English reads the clock time and leaves the words.
    let english = parse("Laporan sebelum 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
    #expect(english.title == "Laporan sebelum")
  }

  // MARK: - Clock times

  @Test("Clock times: pukul, jam, a part of the day, PG and PTG, midnight, and AM and PM")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Mesyuarat pukul 15", 15 * 60), ("Mesyuarat pukul 3", 15 * 60), ("Mesyuarat jam 15", 15 * 60),
      ("Mesyuarat jam 3", 15 * 60), ("Mesyuarat pukul 03", 3 * 60), ("Mesyuarat pukul 15.30", 15 * 60 + 30),
      ("Mesyuarat pukul 15:30", 15 * 60 + 30), ("Mesyuarat jam 15.30", 15 * 60 + 30),
      ("Mesyuarat jam 15:30", 15 * 60 + 30), ("Mesyuarat pukul 3.30", 15 * 60 + 30),
      ("Mesyuarat pukul 3:30", 15 * 60 + 30), ("Mesyuarat pkl 3", 15 * 60), ("Mesyuarat pkl. 15.30", 15 * 60 + 30),
      ("Mesyuarat pk. 15.30", 15 * 60 + 30), ("Mesyuarat pada pukul 15", 15 * 60),
      ("Mesyuarat pada jam 15.30", 15 * 60 + 30), ("Mesyuarat pukul 09.00", 9 * 60), ("Mesyuarat pukul 00.30", 30),
      ("Mesyuarat pukul 18", 18 * 60), ("Mesyuarat pukul 12", 12 * 60), ("Mesyuarat pukul 8", 8 * 60),
      ("Mesyuarat pukul 9.30", 9 * 60 + 30), ("Mesyuarat pukul 20.30", 20 * 60 + 30), ("Mesyuarat pukul 0", 0),
      ("Mesyuarat pukul 03.00", 3 * 60), ("Mesyuarat pukul 5.10", 17 * 60 + 10), ("Mesyuarat PUKUL 15", 15 * 60),
      ("Mesyuarat pukul 3 tepat", 15 * 60), ("Mesyuarat tepat pukul 3", 15 * 60),
      // An hour spelled as a word after pukul or jam.
      ("Mesyuarat pukul tiga", 15 * 60), ("Mesyuarat jam tiga", 15 * 60), ("Mesyuarat pukul dua belas", 12 * 60),
      ("Mesyuarat pukul sepuluh", 10 * 60), ("Mesyuarat pukul sebelas", 11 * 60),
      // A part of the day after the hour.
      ("Mesyuarat pukul 3 petang", 15 * 60), ("Mesyuarat pukul 5 petang", 17 * 60), ("Mesyuarat pukul 8 malam", 20 * 60),
      ("Mesyuarat pukul 7 pagi", 7 * 60), ("Mesyuarat pukul 11 pagi", 11 * 60),
      ("Mesyuarat pukul 12 tengah hari", 12 * 60), ("Mesyuarat pukul 1 tengah hari", 13 * 60),
      ("Mesyuarat pukul 1 tengahari", 13 * 60), ("Mesyuarat pukul 11 malam", 23 * 60),
      ("Mesyuarat pukul 4 subuh", 4 * 60), ("Mesyuarat pukul 2 dini hari", 2 * 60),
      ("Mesyuarat pukul 7.30 malam", 19 * 60 + 30), ("Mesyuarat pukul 3.30 petang", 15 * 60 + 30),
      ("Mesyuarat pukul 15.30 petang", 15 * 60 + 30), ("Mesyuarat pukul 20.00 malam", 20 * 60),
      ("Mesyuarat pukul tiga petang", 15 * 60), ("Mesyuarat pukul lapan malam", 20 * 60),
      ("Mesyuarat pukul tujuh pagi", 7 * 60), ("Mesyuarat jam 8 malam", 20 * 60),
      ("Mesyuarat pukul 10.00 pagi", 10 * 60), ("Mesyuarat pukul 8 nanti malam", 20 * 60),
      // A time with a part of the day needs no pukul.
      ("Mesyuarat 7.30 malam", 19 * 60 + 30), ("Mesyuarat 7:30 malam", 19 * 60 + 30),
      ("Mesyuarat 3.30 petang", 15 * 60 + 30), ("Mesyuarat 8.15 pagi", 8 * 60 + 15),
      ("Mesyuarat 08.00 pagi", 8 * 60), ("Mesyuarat 5.45 petang", 17 * 60 + 45), ("Mesyuarat 8 malam", 20 * 60),
      ("Mesyuarat 7 pagi", 7 * 60), ("Mesyuarat 3 petang", 15 * 60), ("Mesyuarat 12 tengah hari", 12 * 60),
      ("Mesyuarat 1 tengah hari", 13 * 60),
      // PG and PTG are the 12-hour clock's AM and PM.
      ("Mesyuarat 9.30 PG", 9 * 60 + 30), ("Mesyuarat 9.30 pg", 9 * 60 + 30), ("Mesyuarat 9.30pg", 9 * 60 + 30),
      ("Mesyuarat pukul 9.30 PG", 9 * 60 + 30), ("Mesyuarat 3:30 PTG", 15 * 60 + 30),
      ("Mesyuarat 3.30 ptg", 15 * 60 + 30), ("Mesyuarat 12.30 PTG", 12 * 60 + 30), ("Mesyuarat 12.30 PG", 30),
      ("Mesyuarat pukul 9 pg", 9 * 60), ("Mesyuarat jam 3 ptg", 15 * 60),
      // AM and PM after pukul or jam take the lead with them; with no lead English reads them.
      ("Mesyuarat pukul 3pm", 15 * 60), ("Mesyuarat pukul 3 pm", 15 * 60), ("Mesyuarat jam 3:30 pm", 15 * 60 + 30),
      ("Mesyuarat pukul 3 PM", 15 * 60), ("Mesyuarat pukul 9 am", 9 * 60), ("Mesyuarat 15:30", 15 * 60 + 30),
      ("Mesyuarat 3pm", 15 * 60), ("Mesyuarat 17:30", 17 * 60 + 30), ("Mesyuarat 3:30 pm", 15 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Mesyuarat", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The title is what the time leaves, and a zone stays in it.
    #expect(parse("Telefon Ibu pukul 3").title == "Telefon Ibu")
    #expect(parse("Temu duga esok pukul 14.30").title == "Temu duga")
    #expect(parse("Mesyuarat pukul 3 petang MYT").title == "Mesyuarat MYT")
    #expect(parse("Mesyuarat pukul 3 petang MYT").startMinutes == 15 * 60)
    #expect(parse("Mesyuarat pukul 3 dengan Ali").title == "Mesyuarat dengan Ali")
    #expect(parse("Pukul 5 ambil anak").startMinutes == 17 * 60)
    #expect(parse("Pukul 5 ambil anak").title == "ambil anak")
    // A number before "jam 10" is no amount of hours: "jam" opens the clock time.
    let room = parse("Mesyuarat di bilik 3 jam 10 pagi")
    #expect(room.startMinutes == 10 * 60)
    #expect(room.estimatedMinutes == nil)
    #expect(room.title == "Mesyuarat di bilik 3")
    let number = parse("Nombor 17 pukul 5 petang")
    #expect(number.startMinutes == 17 * 60)
    #expect(number.estimatedMinutes == nil)
    #expect(number.title == "Nombor 17")
    // Noon has no rule of its own: "tengah hari" is also lunch.
    expectLinesUnread(["Mesyuarat tengah hari", "Mesyuarat tengahari"], languages: ["ms"])
  }

  @Test("A part of the day beside an hour decides it: pagi, tengah hari, petang, malam, a meal, a prayer, and the fast")
  func partsOfTheDay() {
    for (line, day, minutes, title) in [
      ("Makan malam pukul 8", nil, 20 * 60, "Makan malam"), ("Makan malam pukul 7", nil, 19 * 60, "Makan malam"),
      ("Makan malam bersama keluarga pukul 7", nil, 19 * 60, "Makan malam bersama keluarga"),
      ("Makan malam esok pukul 8", 1, 20 * 60, "Makan malam"), ("Mesyuarat esok malam pukul 8", 1, 20 * 60, "Mesyuarat"),
      ("Mesyuarat malam ini pukul 8", 0, 20 * 60, "Mesyuarat"), ("Mesyuarat nanti malam pukul 8", 0, 20 * 60, "Mesyuarat"),
      ("Mesyuarat Jumaat malam pukul 8", 3, 20 * 60, "Mesyuarat"), ("Mesyuarat malam pukul 9", nil, 21 * 60, "Mesyuarat malam"),
      ("Mesyuarat esok pagi pukul 7", 1, 7 * 60, "Mesyuarat"), ("Mesyuarat esok pagi pukul 8", 1, 8 * 60, "Mesyuarat"),
      ("Mesyuarat esok petang pukul 4", 1, 16 * 60, "Mesyuarat"), ("Mesyuarat petang ini pukul 5", 0, 17 * 60, "Mesyuarat"),
      ("Senaman pagi pukul 6", nil, 6 * 60, "Senaman pagi"), ("Senaman pagi pukul 5", nil, 5 * 60, "Senaman pagi"),
      ("Pukul 8 makan malam", nil, 20 * 60, "makan malam"), ("Mesyuarat pukul 8 malam ini", nil, 20 * 60, "Mesyuarat"),
      ("Mesyuarat pukul 3 petang ini", nil, 15 * 60, "Mesyuarat"), ("Mesyuarat malam, pukul 8", nil, 20 * 60, "Mesyuarat malam"),
      ("Makan malam 7:30", nil, 19 * 60 + 30, "Makan malam"), ("Sarapan pukul 8", nil, 8 * 60, "Sarapan"),
      ("Sarapan bersama pasukan pukul 8", nil, 8 * 60, "Sarapan bersama pasukan"),
      ("Makan tengah hari pukul 1", nil, 13 * 60, "Makan tengah hari"),
      ("Makan tengah hari pukul 12", nil, 12 * 60, "Makan tengah hari"),
      ("Makan tengahari pukul 1", nil, 13 * 60, "Makan tengahari"),
      ("Makan tengah hari 12.30", nil, 12 * 60 + 30, "Makan tengah hari"),
      ("Berbuka puasa pukul 7", nil, 19 * 60, "Berbuka puasa"), ("Solat Isyak pukul 8", nil, 20 * 60, "Solat Isyak"),
      ("Solat Zohor pukul 1", nil, 13 * 60, "Solat Zohor"), ("Solat Subuh pukul 5", nil, 5 * 60, "Solat Subuh"),
      ("Solat Maghrib pukul 7", nil, 19 * 60, "Solat Maghrib"), ("Solat Asar pukul 4", nil, 16 * 60, "Solat Asar"),
    ] as [(String, Int?, Int, String)] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == title, "\(line): title")
    }
    // A part of the day that forms a noun with the word before it stays with that noun, and the day
    // that follows reads alone. Without such a noun the part is the day's.
    for (line, day, title) in [
      ("Makan malam esok", 1, "Makan malam"), ("Pasar malam esok", 1, "Pasar malam"),
      ("Sarapan pagi esok", 1, "Sarapan pagi"), ("Rehat tengah hari esok", 1, "Rehat tengah hari"),
      ("Kelas malam esok", 1, "Kelas malam"),
      ("Senaman pagi Isnin", 6, "Senaman pagi"), ("Kelas petang Jumaat", 3, "Kelas petang"),
      ("Kelas malam Jumaat", 3, "Kelas malam"), ("Mesyuarat malam esok", 1, "Mesyuarat"),
      ("Mesyuarat pagi Isnin", 6, "Mesyuarat"),
    ] as [(String, Int, String)] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.title == title, "\(line): title")
    }
    let nightClass = parse("Kelas malam esok pukul 8")
    #expect(nightClass.plannedDayOffset == 1)
    #expect(nightClass.startMinutes == 20 * 60)
    #expect(nightClass.title == "Kelas malam")
    // Another part of the day, or none, keeps the hour as it is.
    for (line, minutes) in [("Mesyuarat esok pukul 8", 8 * 60), ("Mesyuarat esok pukul 7", 7 * 60), ("Mesyuarat hari ini pukul 8", 8 * 60)] {
      #expect(parse(line).startMinutes == minutes, "\(line)")
    }
    // Two different parts of the day name no hour, so the hour is read on its own.
    let two = parse("Makan malam selepas senaman pagi pukul 8")
    #expect(two.startMinutes == 8 * 60)
    // A part of the day or a meal as a noun names no day or time, and a count of nights is no clock time.
    expectLinesUnread(
      [
        "Sarapan pagi", "Makan malam", "Makan malam keluarga", "Makan tengah hari", "Makan tengah hari dengan Ali",
        "Tempah hotel 2 malam", "Tempah hotel 7 malam", "Pakej 3 hari 2 malam", "Menginap 3 malam", "Tinggal 7 malam",
        "Selamat pagi", "Mesyuarat 2 malam", "Pasar malam",
      ], languages: ["ms"])
    let market = parse("Pergi pasar malam jam 8")
    #expect(market.startMinutes == 20 * 60)
    #expect(market.title == "Pergi pasar malam")
  }

  @Test("After midnight: pukul 12 malam, pukul 1 malam, tengah malam run past the midnight that ends the day")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("Mesyuarat pukul 12 malam", 1, 0), ("Mesyuarat pukul 1 malam", 1, 60), ("Mesyuarat pukul 2 malam", 1, 2 * 60),
      ("Mesyuarat pukul 12 tengah malam", 1, 0), ("Mesyuarat tengah malam", 1, 0), ("Mesyuarat pada tengah malam", 1, 0),
      ("Mesyuarat esok pukul 12 malam", 2, 0), ("Mesyuarat esok malam pukul 12", 2, 0),
      ("Mesyuarat esok tengah malam", 2, 0), ("Mesyuarat malam ini pukul 12", 1, 0),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Mesyuarat", "\(line): title")
    }
    // Eleven at night is still the day itself, the hours before dawn belong to the day named, and the
    // 24th hour is no time of day.
    let eleven = parse("Mesyuarat pukul 11 malam")
    #expect(eleven.plannedDayOffset == nil)
    #expect(eleven.startMinutes == 23 * 60)
    let dawn = parse("Mesyuarat esok pukul 2 dini hari")
    #expect(dawn.plannedDayOffset == 1)
    #expect(dawn.startMinutes == 2 * 60)
    expectLinesUnread(["Mesyuarat pukul 24", "Mesyuarat pukul 24.00", "Mesyuarat pukul 25.00", "Mesyuarat pukul 9.60"], languages: ["ms"])
    // Midnight that has passed is no time.
    expectLinesUnread(["Mesyuarat tengah malam tadi"], languages: ["ms"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func twelveHourRules() {
    for (line, minutes) in [
      ("Mesyuarat pukul 1", 13 * 60), ("Mesyuarat pukul 3", 15 * 60), ("Mesyuarat pukul 6", 18 * 60),
      ("Mesyuarat pukul 7", 7 * 60), ("Mesyuarat pukul 06.00", 6 * 60), ("Mesyuarat pukul 03", 3 * 60),
      ("Mesyuarat pukul 11", 11 * 60), ("Mesyuarat pukul 12", 12 * 60), ("Mesyuarat pukul 5.10", 17 * 60 + 10),
      ("Mesyuarat pukul tiga", 15 * 60), ("Mesyuarat pukul tujuh", 7 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
    }
  }

  @Test("The half hour is written after the hour: pukul tiga setengah is 3:30")
  func halfPastTimes() {
    let halves: [(text: String, minutes: Int)] = [
      ("Mesyuarat pukul tiga setengah", 15 * 60 + 30), ("Mesyuarat pukul 3 setengah", 15 * 60 + 30),
      ("Mesyuarat jam tiga setengah", 15 * 60 + 30), ("Mesyuarat pukul tujuh setengah", 7 * 60 + 30),
      ("Mesyuarat pukul lapan setengah malam", 20 * 60 + 30), ("Mesyuarat pukul 9 setengah pagi", 9 * 60 + 30),
      ("Mesyuarat pukul 3 setengah petang", 15 * 60 + 30), ("Mesyuarat pukul 12 setengah", 12 * 60 + 30),
      ("Mesyuarat pukul sebelas setengah", 11 * 60 + 30),
    ]
    for line in halves {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
      #expect(parsed.title == "Mesyuarat", "\(line.text): title")
    }
    // Quarters are said both ways ("tiga suku" is 3:15 or 2:45), and "setengah tiga" is 2:30 in
    // Indonesian and 3:30 in some Malay, so none of them is read.
    expectLinesUnread(
      [
        "Mesyuarat pukul tiga suku", "Mesyuarat pukul empat kurang suku", "Mesyuarat suku kurang empat",
        "Mesyuarat pukul setengah empat", "Mesyuarat setengah empat", "Mesyuarat pukul 4 kurang 10",
        "Mesyuarat pukul 4 kurang 10 minit", "Mesyuarat pukul 3 lewat 15",
      ], languages: ["ms"])
    // "Setengah" after an hour with a unit is a length, not a time.
    let length = parse("Mesyuarat pukul 3 setengah jam")
    #expect(length.startMinutes == nil)
    #expect(length.estimatedMinutes == 210)
  }

  @Test("Time ranges: dari with hingga, antara with dan, and a dash")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("Mesyuarat pukul 14-16", 14 * 60, 120), ("Mesyuarat pukul 14.00-16.00", 14 * 60, 120),
      ("Mesyuarat pukul 14:00-16:00", 14 * 60, 120), ("Mesyuarat dari pukul 14 hingga pukul 16", 14 * 60, 120),
      ("Mesyuarat dari pukul 14.00 hingga 16.00", 14 * 60, 120), ("Mesyuarat pukul 14 hingga 16", 14 * 60, 120),
      ("Mesyuarat pukul 14 sehingga 16", 14 * 60, 120), ("Mesyuarat pukul 14 sampai 16", 14 * 60, 120),
      ("Mesyuarat antara pukul 14 dan 16", 14 * 60, 120), ("Mesyuarat pukul 09.00 - 11.00", 9 * 60, 120),
      ("Mesyuarat 09.00-11.00", 9 * 60, 120), ("Mesyuarat 14.00-16.00", 14 * 60, 120),
      ("Mesyuarat 14.00 - 16.00", 14 * 60, 120), ("Mesyuarat jam 14.00-16.00", 14 * 60, 120),
      ("Mesyuarat pukul 3-5 petang", 15 * 60, 120), ("Mesyuarat pukul 3 hingga 5 petang", 15 * 60, 120),
      ("Mesyuarat dari pukul 3 hingga 5 petang", 15 * 60, 120), ("Mesyuarat dari pukul 8 hingga pukul 10 pagi", 8 * 60, 120),
      ("Mesyuarat dari pukul 7 hingga 9 malam", 19 * 60, 120), ("Mesyuarat pukul 9-11 pagi", 9 * 60, 120),
      ("Mesyuarat pukul 10 pagi hingga pukul 12 tengah hari", 10 * 60, 120), ("Mesyuarat pukul 3-4", 15 * 60, 60),
      ("Mesyuarat dari 3 hingga 5", 15 * 60, 120), ("Mesyuarat antara 3 dan 5", 15 * 60, 120),
      ("Mesyuarat antara pukul 3 dan 5 petang", 15 * 60, 120),
      ("Mesyuarat dari pukul 15.30 hingga pukul 17.00", 15 * 60 + 30, 90), ("Mesyuarat pukul 9-12", 9 * 60, 180),
      ("Mesyuarat dari 14.00 hingga 16.00", 14 * 60, 120),
      // A side with no part of the day takes the reading that fits the other side.
      ("Mesyuarat 9.00 pagi hingga 5.00 petang", 9 * 60, 480), ("Mesyuarat 9 pagi - 5 petang", 9 * 60, 480),
      ("Mesyuarat dari 9 hingga 5 petang", 9 * 60, 480), ("Mesyuarat 9.00 PG - 5.00 PTG", 9 * 60, 480),
      ("Mesyuarat dari pukul 8 malam hingga 11", 20 * 60, 180),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "Mesyuarat", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day or a meal makes the range that part's, as it does a single hour.
    let evening = parse("Mesyuarat malam ini dari pukul 7 hingga 9")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.estimatedMinutes == 120)
    let morning = parse("Mesyuarat esok dari pukul 7 hingga 9")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 7 * 60)
    // A range may run past midnight.
    let overnight = parse("Berjaga pukul 22.00-02.00")
    #expect(overnight.startMinutes == 22 * 60)
    #expect(overnight.estimatedMinutes == 240)
    #expect(overnight.title == "Berjaga")
    // Numbers that count something are no range of hours, and neither are two bare hours whose end comes
    // before a start on the 24-hour clock, or dotted times that could be dates.
    expectLinesUnread(
      [
        "Mesyuarat 14-16", "Mesyuarat 3-5", "Mesyuarat 5.10-7.10", "Bab 3-5", "Muka surat 3-5",
        "Mesyuarat dari 15 hingga 10", "Mesyuarat dari 3 hingga 5 orang", "Mesyuarat dari 3 hingga 5 hari",
        "Mesyuarat antara 3 dan 5 hari", "Anggaran antara 5 dan 10 juta", "Bacaan 5 pg - 10 pg",
      ], languages: ["ms"])
    // Two bare hours after "antara" are a range, as they are after "dari".
    let between = parse("Mesyuarat antara 5 dan 10")
    #expect(between.startMinutes == 17 * 60)
    #expect(between.estimatedMinutes == 300)
    #expect(between.title == "Mesyuarat")
    // A start that is followed by a word that is no end is the start alone, and the words stay.
    let open = parse("Mesyuarat pukul 3 hingga selesai")
    #expect(open.startMinutes == 15 * 60)
    #expect(open.estimatedMinutes == nil)
    #expect(open.title == "Mesyuarat hingga selesai")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Mesyuarat 30 minit", 30), ("Mesyuarat 30 min", 30), ("Mesyuarat 45minit", 45), ("Mesyuarat 5 minit", 5),
      ("Mesyuarat 90 minit", 90), ("Mesyuarat 1440 minit", 1440), ("Mesyuarat 1 jam", 60), ("Mesyuarat 2 jam", 120),
      ("Mesyuarat 1,5 jam", 90), ("Mesyuarat 1.5 jam", 90), ("Mesyuarat 0,5 jam", 30), ("Mesyuarat 2,5 jam", 150),
      ("Mesyuarat 1 jam 30 minit", 90), ("Mesyuarat 1 jam dan 30 minit", 90), ("Mesyuarat 1 jam 30 min", 90),
      ("Mesyuarat 2 jam 30 minit", 150), ("Mesyuarat 2 jam setengah", 150), ("Mesyuarat dua jam setengah", 150),
      ("Mesyuarat setengah jam", 30), ("Mesyuarat sejam", 60), ("Mesyuarat sejam setengah", 90),
      ("Mesyuarat sejam suku", 75), ("Mesyuarat satu setengah jam", 90), ("Mesyuarat dua setengah jam", 150),
      ("Mesyuarat suku jam", 15), ("Mesyuarat tiga suku jam", 45), ("Mesyuarat dua jam", 120),
      ("Mesyuarat tiga jam", 180), ("Mesyuarat lima belas minit", 15), ("Mesyuarat tiga puluh minit", 30),
      ("Mesyuarat dua puluh lima minit", 25), ("Mesyuarat sepuluh minit", 10), ("Mesyuarat semenit", 1),
      ("Mesyuarat selama 2 jam", 120), ("Mesyuarat tempoh 2 jam", 120), ("Mesyuarat durasi 2 jam", 120),
      ("Mesyuarat durasi: 2 jam", 120), ("Mesyuarat anggaran 2 jam", 120), ("Mesyuarat kira-kira 1 jam", 60),
      ("Mesyuarat lebih kurang 2 jam", 120), ("Mesyuarat sekitar 30 minit", 30), ("Mesyuarat untuk 30 minit", 30),
      ("Mesyuarat selama setengah jam", 30), ("Mesyuarat 24 jam", 1440), ("Mesyuarat 20 jam", 1200),
      ("Mesyuarat 30 MINIT", 30),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Mesyuarat", "\(line.text): title")
    }
    let before = parse("30 minit mesyuarat")
    #expect(before.estimatedMinutes == 30)
    #expect(before.title == "mesyuarat")
    // A length beside a day and a time.
    let line = parse("Mesyuarat esok pukul 3 selama 2 jam")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.title == "Mesyuarat")
  }

  @Test("An amount after dalam, setiap, or selepas, a rate, a difference, and a range are no length")
  func notLengths() {
    expectLinesUnread(
      [
        "Mesyuarat dalam 2 jam", "Mesyuarat dalam masa 2 jam", "Mesyuarat setiap 2 jam", "Mesyuarat selepas 30 minit",
        "Mesyuarat sebelum 2 jam", "Mesyuarat kurang daripada 2 jam", "Mesyuarat maksimum 2 jam",
        "Mesyuarat 2 jam lagi", "Mesyuarat 2 jam yang lalu", "Mesyuarat 2 jam sehari", "Mesyuarat 2 jam per hari",
        "Mesyuarat 30 minit lebih awal", "Mesyuarat 2 jam sekali", "Mesyuarat 2-3 jam", "Mesyuarat 2 - 3 jam",
        "Mesyuarat 2 hingga 3 jam", "Mesyuarat 2 atau 3 jam", "Mesyuarat 25 jam", "Mesyuarat 1500 minit",
        "Mesyuarat 0 minit", "Telefon dalam 10 minit", "Mesyuarat 3.5.2 jam",
      ], languages: ["ms"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func cadences() {
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Senaman setiap hari", daily), ("Senaman tiap hari", daily), ("Senaman tiap-tiap hari", daily),
      ("Senaman setiap pagi", daily), ("Senaman setiap petang", daily), ("Senaman setiap malam", daily),
      ("Senaman harian", daily), ("Senaman sehari sekali", daily), ("Senaman sekali sehari", daily),
      ("Senaman 1x sehari", daily), ("Senaman setiap minggu", weekly), ("Senaman tiap minggu", weekly),
      ("Senaman mingguan", weekly), ("Senaman seminggu sekali", weekly), ("Senaman sekali seminggu", weekly),
      ("Senaman 1x seminggu", weekly), ("Senaman 1 kali seminggu", weekly), ("Senaman satu kali per minggu", weekly),
      ("Senaman sekali dalam seminggu", weekly), ("Senaman setiap bulan", monthly), ("Senaman bulanan", monthly),
      ("Senaman sebulan sekali", monthly), ("Senaman sekali sebulan", monthly), ("Senaman 1x per bulan", monthly),
      ("Senaman setiap tahun", yearly), ("Senaman tahunan", yearly), ("Senaman setahun sekali", yearly),
      ("Senaman sekali setahun", yearly),
      ("Senaman setiap 2 hari", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Senaman setiap dua hari", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Senaman tiap 3 hari", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Senaman 2 hari sekali", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Senaman dua hari sekali", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Senaman setiap 14 hari", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Senaman setiap 2 minggu", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Senaman setiap dua minggu", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Senaman 2 minggu sekali", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Senaman dua minggu sekali", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Senaman sekali dalam 2 minggu", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Senaman setiap 2 bulan", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Senaman 3 bulan sekali", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Senaman setiap 2 tahun", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("Senaman setiap suku tahun", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("SENAMAN SETIAP HARI", daily),
    ]
    for line in cadences {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == String(line.text.prefix { $0 != " " }), "\(line.text): title")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
    }
    // A repeat in front of the line.
    let opening = parse("Harian: senaman")
    #expect(opening.recurrence == daily)
    #expect(opening.title == "senaman")
    let weeklyOpening = parse("Mingguan: semak e-mel")
    #expect(weeklyOpening.recurrence == weekly)
    #expect(weeklyOpening.title == "semak e-mel")
    // A repeat at the end of a line that goes on after a noun.
    #expect(parse("Laporan bulanan").recurrence == monthly)
    #expect(parse("Laporan mingguan").recurrence == weekly)
    #expect(parse("Laporan tahunan").recurrence == yearly)
    #expect(parse("Mesyuarat mingguan pasukan").recurrence == nil)
    // A date beside a yearly repeat.
    let birthday = parse("Hari jadi Ali 15 Oktober setiap tahun")
    #expect(birthday.recurrence == yearly)
    #expect(birthday.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(birthday.title == "Hari jadi Ali")
    // A repeat with a time or a length.
    for (text, rule, minutes, length) in [
      ("Senaman setiap hari pukul 7 pagi", daily, 7 * 60, nil), ("Senaman setiap pagi pukul 7", daily, 7 * 60, nil),
      ("Senaman setiap pagi 6.30 pagi", daily, 6 * 60 + 30, nil), ("Senaman setiap malam pukul 8", daily, 20 * 60, nil),
      ("Senaman setiap malam 8:30 malam", daily, 20 * 60 + 30, nil),
      ("Senaman setiap malam pukul 8 selama 30 minit", daily, 20 * 60, 30),
      ("Senaman harian pukul 8 malam", daily, 20 * 60, nil),
    ] as [(String, TaskRecurrenceRule, Int, Int?)] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == "Senaman", "\(text): title")
    }
    let medicine = parse("Minum ubat setiap hari pukul 8 pagi")
    #expect(medicine.recurrence == daily)
    #expect(medicine.startMinutes == 8 * 60)
    #expect(medicine.title == "Minum ubat")
  }

  @Test("Weekday repeats: setiap Isnin, hari Ahad, lists, spans, and the weekend")
  func weekdayRepeats() {
    let coming = parse("Senaman setiap Isnin")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "Senaman")
    for text in [
      "Senaman tiap Isnin", "Senaman setiap hari Isnin", "Senaman tiap hari Isnin", "Senaman tiap-tiap Isnin",
      "Senaman setiap minggu pada hari Isnin",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == monday, "\(text)")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.title == "Senaman", "\(text): title")
    }
    let pairs: [(text: String, days: [String])] = [
      ("Senaman setiap Selasa dan Khamis", ["TU", "TH"]),
      ("Senaman setiap Isnin, Rabu dan Jumaat", ["MO", "WE", "FR"]),
      ("Senaman setiap Isnin, Rabu, dan Jumaat", ["MO", "WE", "FR"]),
      ("Senaman setiap hari Isnin dan Khamis", ["MO", "TH"]), ("Senaman setiap Isnin & Khamis", ["MO", "TH"]),
      ("Senaman setiap Isnin dan Khamis", ["MO", "TH"]), ("Senaman setiap Sabtu", ["SA"]),
      ("Senaman setiap hari Ahad", ["SU"]), ("Senaman setiap Ahad pagi", ["SU"]),
      ("Senaman setiap Sabtu dan Ahad", ["SU", "SA"]), ("Senaman setiap minggu Isnin dan Khamis", ["MO", "TH"]),
      ("Senaman setiap Isnin hingga Khamis", ["MO", "TU", "WE", "TH"]),
      ("Senaman setiap Isnin sehingga Khamis", ["MO", "TU", "WE", "TH"]),
      ("Senaman setiap Isnin - Khamis", ["MO", "TU", "WE", "TH"]),
      ("Senaman setiap Jumaat sampai Ahad", ["SU", "FR", "SA"]),
    ]
    for line in pairs {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "Senaman", "\(line.text): title")
    }
    // An interval takes the weekdays after it.
    let interval = parse("Senaman setiap 2 minggu hari Khamis")
    #expect(interval.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TH"]))
    #expect(interval.recurrenceStartOffset == 2)
    #expect(interval.title == "Senaman")
    #expect(parse("Senaman 2 minggu sekali hari Khamis").recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["TH"]))
    // The start of a repeat on Wednesday, Friday, and Monday is the nearest day.
    #expect(parse("Senaman setiap Isnin, Rabu dan Jumaat").recurrenceStartOffset == 1)
    #expect(parse("Senaman setiap Selasa dan Khamis").recurrenceStartOffset == 0)
    #expect(parse("Senaman setiap Sabtu dan Ahad").recurrenceStartOffset == 4)
    for text in ["Senaman setiap hujung minggu", "Senaman tiap weekend", "Senaman tiap-tiap hujung minggu"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == weekend, "\(text)")
      #expect(parsed.recurrenceStartOffset == 4, "\(text): start")
      #expect(parsed.title == "Senaman", "\(text): title")
    }
    // "Hujung minggu" with no "setiap" is one day.
    let day = parse("Cuci kereta hujung minggu")
    #expect(day.recurrence == nil)
    #expect(day.plannedDayOffset == 4)
    #expect(day.title == "Cuci kereta")
    // A repeat with a time.
    let timed = parse("Yoga setiap Selasa dan Khamis pukul 19.30")
    #expect(timed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(timed.startMinutes == 19 * 60 + 30)
    #expect(timed.title == "Yoga")
    let evening = parse("Yoga setiap Selasa pukul 7 malam")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    #expect(evening.startMinutes == 19 * 60)
    let morning = parse("Senaman setiap Isnin pukul 6 pagi")
    #expect(morning.recurrence == monday)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "Senaman")
    let both = parse("Senaman setiap Isnin dan Khamis pukul 7.30 malam")
    #expect(both.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(both.startMinutes == 19 * 60 + 30)
    // A part of the day after the weekdays is part of the repeat phrase, and a time keeps its part of the day.
    let friday = parse("Pengajian setiap Jumaat malam")
    #expect(friday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(friday.title == "Pengajian")
    #expect(friday.phrases.map(\.text) == ["setiap Jumaat malam"])
    let late = parse("Pengajian setiap Jumaat malam pukul 8")
    #expect(late.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["FR"]))
    #expect(late.startMinutes == 20 * 60)
    #expect(late.title == "Pengajian")
    // A compound with a hyphen is no part of the day.
    let early = parse("Senaman setiap Isnin pagi-pagi")
    #expect(early.recurrence == monday)
    #expect(early.title == "Senaman pagi-pagi")
    let weekendTimed = parse("Cuci baju setiap hujung minggu pukul 10")
    #expect(weekendTimed.recurrence == weekend)
    #expect(weekendTimed.startMinutes == 10 * 60)
    #expect(weekendTimed.title == "Cuci baju")
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [15])
    for text in [
      "Sewa setiap tarikh 15", "Sewa tiap tarikh 15", "Sewa setiap 15hb", "Sewa setiap bulan tarikh 15",
      "Sewa setiap bulan pada tarikh 15", "Sewa setiap bulan pada 15hb", "Sewa tarikh 15 setiap bulan",
      "Sewa 15hb setiap bulan", "Sewa pada 15hb setiap bulan",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 23, "\(text): start")
      #expect(parsed.title == "Sewa", "\(text): title")
    }
    let first = TaskRecurrenceRule(freq: .monthly, byMonthDay: [1])
    for text in ["Sewa setiap tarikh 1", "Sewa tiap bulan tarikh 1", "Sewa setiap 1hb"] {
      let parsed = parse(text)
      #expect(parsed.recurrence == first, "\(text)")
      #expect(parsed.recurrenceStartOffset == 9, "\(text): start")
    }
    // An amount after "setiap bulan" is no day of the month.
    let amount = parse("Sewa setiap bulan 15 ribu")
    #expect(amount.recurrence == monthly)
    #expect(amount.title == "Sewa 15 ribu")
  }

  @Test("A weekday by its place in the month stays whole, and a count of times or a noun made of a cadence word stays")
  func unreadRepeats() {
    expectLinesUnread(
      [
        // A weekday by its place in the month has no repeat rule, so no part of it is read as a weekday.
        "Senaman setiap Isnin pertama", "Senaman Isnin terakhir bulan ini", "Senaman setiap Jumaat kedua",
        // Every day with a day left out has no repeat rule.
        "Senaman setiap hari kecuali Ahad", "Senaman setiap hari selain Sabtu",
        // A count of times in a period, and an interval of hours.
        "Senaman dua kali seminggu", "Senaman 3 kali sebulan", "Senaman 2 kali sehari", "Senaman setiap 2 jam",
        "Senaman setiap 30 minit",
        // A holiday, an ordinal week, a named month, a list of days of the month, or a count of working days.
        "Senaman setiap hari cuti", "Senaman setiap hari raya", "Senaman setiap minggu pertama",
        "Senaman setiap bulan Oktober", "Senaman setiap bulan Ramadan", "Senaman setiap tarikh 5 dan 20",
        "Senaman setiap 3 hari kerja", "Senaman dalam 5 hari kerja", "Senaman hari kerja",
        // A noun made of a cadence word, or an adjective that is not at the end of the line.
        "Tulis buku harian", "Baca akhbar harian", "Laporan harian untuk pasukan", "Baca Berita Harian",
        "Mohon cuti tahunan",
      ], languages: ["ms"])
  }

  // MARK: - Priorities

  @Test("Priorities: penting, mendesak, urgent, segera, keutamaan tinggi or rendah, and prioriti")
  func priorities() {
    let priorities: [(text: String, title: String, priority: LorvexTask.Priority)] = [
      ("Laporan penting", "Laporan", .p1), ("Laporan penting.", "Laporan", .p1), ("Laporan penting!", "Laporan", .p1),
      ("Laporan sangat penting", "Laporan", .p1), ("Laporan mendesak", "Laporan", .p1),
      ("Laporan urgent", "Laporan", .p1), ("Laporan segera", "Laporan", .p1), ("Penting: laporan", "laporan", .p1),
      ("Segera, laporan", "laporan", .p1), ("Penting, hantar laporan", "hantar laporan", .p1),
      ("Laporan keutamaan tinggi", "Laporan", .p1), ("Laporan keutamaan utama", "Laporan", .p1),
      ("Laporan keutamaan 1", "Laporan", .p1), ("Laporan prioriti 1", "Laporan", .p1),
      ("Laporan prioriti tinggi", "Laporan", .p1), ("Laporan prio 1", "Laporan", .p1),
      ("Laporan prio: tinggi", "Laporan", .p1), ("Laporan dengan keutamaan tinggi", "Laporan", .p1),
      ("Keutamaan tinggi: laporan", "laporan", .p1),
      ("Laporan keutamaan sederhana", "Laporan", .p2), ("Laporan keutamaan 2", "Laporan", .p2),
      ("Laporan prioriti sederhana", "Laporan", .p2), ("Laporan prio 2", "Laporan", .p2),
      ("Laporan keutamaan rendah", "Laporan", .p3), ("Laporan keutamaan 3", "Laporan", .p3),
      ("Laporan prioriti rendah", "Laporan", .p3), ("Laporan prio rendah", "Laporan", .p3),
      ("Keutamaan rendah laporan", "laporan", .p3),
      ("Laporan PENTING", "Laporan", .p1), ("Laporan KEUTAMAAN TINGGI", "Laporan", .p1),
      // The shorthand every language reads.
      ("Laporan !", "Laporan", .p1), ("Laporan p1", "Laporan", .p1),
    ]
    for line in priorities {
      let parsed = parse(line.text)
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A negated word, a word that opens a sentence, a word in the middle of a line, a food that is
    // quick, and a priority that is no level are no priority.
    expectLinesUnread(
      [
        "Penting laporan", "Laporan tidak penting", "Laporan bukan urgent", "Laporan kurang mendesak",
        "Laporan tidak berapa penting", "Laporan belum mendesak", "Dokumen penting dibawa", "Laporan penting dihantar",
        "Laporan keutamaan 4", "Laporan keutamaan", "Laporan penting: hantar", "Laporan tak penting",
        "Beli mi segera", "Beli makanan segera", "Beli minuman segera",
      ], languages: ["ms"])
    // The word in the middle of a line stays in the title, and what follows it reads.
    let middle = parse("Laporan penting esok pukul 15")
    #expect(middle.title == "Laporan penting")
    #expect(middle.priority == nil)
    #expect(middle.plannedDayOffset == 1)
    #expect(middle.startMinutes == 15 * 60)
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyDetail() {
    let line = parse("Tulis laporan esok pukul 15 2 jam penting")
    #expect(line.title == "Tulis laporan")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(line.estimatedMinutes == 120)
    #expect(line.priority == .p1)
    #expect(line.phrases.map(\.text) == ["esok", "pukul 15", "2 jam", "penting"])
    let recurring = parse("Senaman setiap Isnin pukul 18 1 jam keutamaan tinggi")
    #expect(recurring.title == "Senaman")
    #expect(recurring.recurrence == monday)
    #expect(recurring.startMinutes == 18 * 60)
    #expect(recurring.estimatedMinutes == 60)
    #expect(recurring.priority == .p1)
    let due = parse("Cukai sebelum 31 Julai prioriti 2")
    #expect(due.title == "Cukai")
    #expect(due.dueDayOffset == captureDayOffset("2027-07-31"))
    #expect(due.priority == .p2)
    let lunch = parse("Makan tengah hari dengan Ali esok pukul 12.30 1 jam")
    #expect(lunch.title == "Makan tengah hari dengan Ali")
    #expect(lunch.plannedDayOffset == 1)
    #expect(lunch.startMinutes == 12 * 60 + 30)
    #expect(lunch.estimatedMinutes == 60)
    // Lists and tags beside Malay details.
    let list = LorvexCaptureParser.parse(
      "Beli barang #Rumah esok", lists: [.init(id: "L1", name: "Rumah")], todayWeekday: 3, today: "2026-09-22",
      languages: ["ms"])
    #expect(list.listName == "Rumah")
    #expect(list.plannedDayOffset == 1)
    #expect(list.title == "Beli barang")
    let tag = parse("Beli barang hari ini #peribadi")
    #expect(tag.tags == ["peribadi"])
    #expect(tag.plannedDayOffset == 0)
    #expect(tag.title == "Beli barang")
    let tagFirst = parse("#kerja Mesyuarat esok pukul 3")
    #expect(tagFirst.tags == ["kerja"])
    #expect(tagFirst.plannedDayOffset == 1)
    #expect(tagFirst.startMinutes == 15 * 60)
    #expect(tagFirst.title == "Mesyuarat")
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Nouns made of a day word, a time word, or a number word.
        "Jam tangan baharu", "Beli jam dinding", "Jam kerja pejabat", "Sarapan pagi", "Selamat malam", "Kelas malam",
        "Hari raya", "Hari jadi", "Hari lahir", "Hari Ibu", "Bulan madu", "Pasar malam", "Pukulan keras",
        // "Jam" as a clock or a watch is no hours amount.
        "Beli 2 jam tangan", "Beli 2 jam dinding", "Beli dua jam pasir", "Beli 3 jam loceng", "Beli jam loceng",
        // Numbers that are counts, places, and amounts.
        "Beli 3 biji epal", "Bayar RM15", "Jumpa 3 orang kawan", "Bab 3", "Muka surat 15", "Bilik 15", "Tingkat 3",
        "Versi 2.3", "Sprint 12", "Tugasan 3", "Telefon 012 345 6789", "Lari 5 km", "Beli 3 kg beras",
        "Baca 30 muka surat", "Tiket untuk 3 orang", "Menginap 3 hari", "Siapkan kerja rumah matematik",
        "Mesyuarat kedua dengan pelanggan", "Bil: elektrik, air", "Fasal 15", "Taip dokumen 5 pg",
        "Taip dokumen 5 ptg", "Beli 2 Mac mini", "Beli pensel 2HB", "Makan mi segera", "Solat Jumaat",
        // A quantity of time that is a duration of something else.
        "Mesyuarat dalam 2 jam", "Telefon saya dalam 10 minit",
      ], languages: ["ms"])
    // A line that opens with a time keeps the rest as the title.
    let lead = parse("Pukul 5 pembentangan")
    #expect(lead.startMinutes == 17 * 60)
    #expect(lead.title == "pembentangan")
  }

  @Test("A hyphen joins a compound that is no day, and extra spaces or punctuation between details change nothing")
  func hyphensAndSpacing() {
    expectLinesUnread(["Laporan esok-esok", "Laporan hari-hari", "Laporan pagi-pagi jam-jam"], languages: ["ms"])
    let spaced = parse("Laporan   pukul   15")
    #expect(spaced.startMinutes == 15 * 60)
    #expect(spaced.title == "Laporan")
    let tabbed = parse("Laporan setiap\tIsnin")
    #expect(tabbed.recurrence == monday)
    #expect(tabbed.title == "Laporan")
    for text in ["Laporan esok, pukul 15", "Laporan esok; pukul 15"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "Laporan", "\(text): title")
    }
  }

  @Test("Capitals read like lowercase letters, and the title keeps the capitals it was typed with")
  func capitals() {
    let lines: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("DOKTOR GIGI ESOK", "DOKTOR GIGI", { $0.plannedDayOffset == 1 }),
      ("LAPORAN SABTU", "LAPORAN", { $0.plannedDayOffset == 4 }),
      ("MESYUARAT PUKUL 15", "MESYUARAT", { $0.startMinutes == 15 * 60 }),
      ("MESYUARAT PUKUL 3 PETANG", "MESYUARAT", { $0.startMinutes == 15 * 60 }),
      ("MESYUARAT 9.30 PG", "MESYUARAT", { $0.startMinutes == 9 * 60 + 30 }),
      ("MESYUARAT PUKUL TIGA SETENGAH", "MESYUARAT", { $0.startMinutes == 15 * 60 + 30 }),
      ("LAPORAN SEBELUM JUMAAT", "LAPORAN", { $0.dueDayOffset == 3 }),
      ("LAPORAN SEBELUM 15 OKTOBER", "LAPORAN", { $0.dueDayOffset == 23 }),
      ("LAPORAN PADA 15 OKTOBER", "LAPORAN", { $0.plannedDayOffset == 23 }),
      ("SENAMAN SETIAP ISNIN", "SENAMAN", { $0.recurrence == monday }),
      ("SENAMAN SETIAP HARI KERJA", "SENAMAN", { $0.recurrence == workdays }),
      ("LAPORAN BULANAN", "LAPORAN", { $0.recurrence == monthly }),
      ("MESYUARAT 2 JAM", "MESYUARAT", { $0.estimatedMinutes == 120 }),
      ("MESYUARAT SETENGAH JAM", "MESYUARAT", { $0.estimatedMinutes == 30 }),
      ("LAPORAN PENTING", "LAPORAN", { $0.priority == .p1 }),
      ("LAPORAN KEUTAMAAN RENDAH", "LAPORAN", { $0.priority == .p3 }),
      ("Laporan SELASA pukul 15", "Laporan", { $0.plannedDayOffset == 7 && $0.startMinutes == 15 * 60 }),
      ("Laporan JUMAAT PETANG", "Laporan", { $0.plannedDayOffset == 3 }),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(line.check(parsed), "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Malay, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Malay beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Meet at 15h",
      "Meet 10h", "Call mom tonight", "Dinner tomorrow evening", "Meeting at 9:30", "Walk 45 min every day",
    ] {
      for languages in [["en", "ms"], ["ms", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Malay writes its hours with "pukul" or "jam" or a colon, so "15h" and "2h" are lengths beside it.
    let hours = parse("Write the report 2h", languages: ["en", "ms"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "ms"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    // "Dalam 15 min" is a moment in Malay, so beside it English's "in 15 min" is no length only
    // where the Malay word stands before the amount.
    let moment = parse("Telefon dalam 15 min", languages: ["en", "ms"])
    #expect(moment.estimatedMinutes == nil)
    #expect(moment.title == "Telefon dalam 15 min")
    // A line may mix both languages.
    let mixed = parse("Call Ibu esok at 3pm", languages: ["en", "ms"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call Ibu")
    let weekday = parse("Meeting Jumaat at 3pm", languages: ["en", "ms"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Doktor gigi tomorrow", languages: ["en", "ms"]).plannedDayOffset == 1)
    let review = parse("Review esok pukul 15.00 for 2 hours", languages: ["en", "ms"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english = parse("Laporan esok 3pm")
    #expect(english.plannedDayOffset == 1)
    #expect(english.startMinutes == 15 * 60)
    #expect(english.title == "Laporan")
    #expect(parse("Mesyuarat 15h").estimatedMinutes == 15 * 60)
    #expect(parse("Laporan 30 min esok").estimatedMinutes == 30)
    #expect(parse("Laporan esok 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("Mesyuarat tomorrow").plannedDayOffset == 1)
  }

  @Test("Beside Indonesian, each language keeps its own words and the words they share read once")
  func besideIndonesian() {
    for languages in [["ms", "id"], ["id", "ms"]] {
      // Malay's own words.
      let malay = parse("Mesyuarat esok pukul 3 petang", languages: languages)
      #expect(malay.plannedDayOffset == 1, "\(languages)")
      #expect(malay.startMinutes == 15 * 60, "\(languages)")
      #expect(malay.title == "Mesyuarat", "\(languages)")
      #expect(parse("Laporan Ahad", languages: languages).plannedDayOffset == 5, "\(languages)")
      #expect(parse("Laporan hujung minggu", languages: languages).plannedDayOffset == 4, "\(languages)")
      #expect(parse("Laporan keutamaan tinggi", languages: languages).priority == .p1, "\(languages)")
      #expect(parse("Rapat 30 minit", languages: languages).estimatedMinutes == 30, "\(languages)")
      #expect(parse("Senaman setiap Isnin", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Laporan 5hb", languages: languages).plannedDayOffset == 13, "\(languages)")
      // Indonesian's own words.
      let indonesian = parse("Rapat besok jam 3 sore", languages: languages)
      #expect(indonesian.plannedDayOffset == 1, "\(languages)")
      #expect(indonesian.startMinutes == 15 * 60, "\(languages)")
      #expect(indonesian.title == "Rapat", "\(languages)")
      #expect(parse("Laporan hari Minggu", languages: languages).plannedDayOffset == 5, "\(languages)")
      #expect(parse("Laporan akhir pekan", languages: languages).plannedDayOffset == 4, "\(languages)")
      #expect(parse("Laporan prioritas tinggi", languages: languages).priority == .p1, "\(languages)")
      #expect(parse("Rapat 30 menit", languages: languages).estimatedMinutes == 30, "\(languages)")
      #expect(parse("Lari setiap Senin", languages: languages).recurrence == monday, "\(languages)")
      let date = parse("Rapat tanggal 5 Oktober", languages: languages)
      #expect(date.plannedDayOffset == 13, "\(languages)")
      #expect(date.title == "Rapat", "\(languages)")
      // The half hour and the minutes before an hour read as Indonesian says them.
      #expect(parse("Rapat pukul setengah empat", languages: languages).startMinutes == 15 * 60 + 30, "\(languages)")
      let before = parse("Rapat pukul 4 kurang 10 minit", languages: languages)
      #expect(before.startMinutes == 15 * 60 + 50, "\(languages)")
      #expect(before.title == "Rapat", "\(languages)")
      // Words both write read once.
      #expect(parse("Rapat besok", languages: languages).plannedDayOffset == 1, "\(languages)")
      #expect(parse("Rapat lusa", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Rapat 3 hari lagi", languages: languages).plannedDayOffset == 3, "\(languages)")
      #expect(parse("Rapat 5 Oktober", languages: languages).plannedDayOffset == 13, "\(languages)")
      #expect(parse("Rapat setiap hari kerja", languages: languages).recurrence == workdays, "\(languages)")
      #expect(parse("Rapat sebelum Jumat", languages: languages).dueDayOffset == 3, "\(languages)")
      #expect(parse("Rapat sebelum Jumaat", languages: languages).dueDayOffset == 3, "\(languages)")
      // "Minggu" alone is the week in both.
      expectLinesUnread(["Laporan Minggu", "Laporan minggu ini"], languages: languages)
    }
  }

  @Test("Lines in other languages read the same with Malay beside them")
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
      #expect(parse(line.text, languages: [line.language, "ms"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["ms", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Malay with another language.
    for languages in [["fr", "ms"], ["ms", "fr"]] {
      let mixed = parse("Appeler maman esok pukul 15", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Appeler maman demain à 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Doktor gigi lusa", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste 3 mai", languages: languages).plannedDayOffset == captureDayOffset("2027-05-03"), "\(languages)")
      #expect(parse("Senaman setiap Isnin", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Laporan penting", languages: languages).priority == .p1, "\(languages)")
      expectDateRanges(
        [
          ("Vacances", "du 3 au 5 mai", "2027-05-03", "2027-05-05"),
          ("Percutian", "dari 3 hingga 5 Mei", "2027-05-03", "2027-05-05"),
        ], languages: languages)
    }
    #expect(parse("Doktor gigi 下午3点 esok", languages: ["zh", "ms"]).plannedDayOffset == 1)
    #expect(parse("Doktor gigi מחר", languages: ["he", "ms"]).plannedDayOffset == 1)
    // Malay beside Dutch, German, or Romanian: each keeps its own words. "Oktober" is the same month in
    // all of them, and "esok" belongs to Malay alone.
    for languages in [["nl", "ms"], ["ms", "nl"], ["de", "ms"], ["ms", "de"], ["ro", "ms"], ["ms", "ro"]] {
      #expect(parse("Doktor gigi esok pukul 15", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Senaman setiap Isnin", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Doktor gigi 15 Oktober", languages: languages).plannedDayOffset == 23, "\(languages)")
      #expect(parse("Tandarts overmorgen", languages: languages).plannedDayOffset == (languages.contains("nl") ? 2 : nil), "\(languages)")
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == (languages.contains("de") ? 2 : nil), "\(languages)")
      #expect(parse("Dentist poimâine", languages: languages).plannedDayOffset == (languages.contains("ro") ? 2 : nil), "\(languages)")
    }
  }

  @Test("Malay words are read only for a user who reads Malay")
  func languageGate() {
    let line = parse("Doktor gigi lusa", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Doktor gigi lusa")
    for languages in [["ms"], ["ms-MY"], ["ms_MY"], ["ms-SG"], ["ms-BN"], ["en-US", "ms-MY"], ["MS"]] {
      #expect(parse("Doktor gigi lusa", languages: languages).plannedDayOffset == 2, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Malay reader, and neither
    // are Indonesian's own words.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen", "Dentist poimâine", "Dokter gigi Senin", "Lari setiap Senin",
        "Rapat 30 menit", "Laporan prioritas tinggi", "Laporan akhir pekan", "Dokter gigi Jumat", "Rapat besok sore",
        "Rapat jam 3 sore",
      ], languages: ["ms"])
    // Malay words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"], ["ro"], ["ar"], ["id"]] {
      let parsed = parse("Doktor gigi esok", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Doktor gigi esok", "\(languages): title")
      #expect(parse("Senaman setiap Isnin", languages: languages).recurrence == nil, "\(languages): repeat")
      #expect(parse("Hantar laporan keutamaan tinggi", languages: languages).priority == nil, "\(languages): priority")
      #expect(parse("Mesyuarat Khamis", languages: languages).plannedDayOffset == nil, "\(languages): weekday")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let tokens = [
      "pukul 15 ", "pukul 3 ", "jam 3 ", "3 ", "dari ", "antara ", "antara 3 dan 5 ", "dari pukul 3 hingga pukul 5 ",
      "14-16 ", "14.00-16.00 ", "15.30 ", "15:30 ", "pukul tiga ", "pukul tiga setengah ", "pukul 3 setengah ",
      "setengah ", "kurang ", "kurang suku ", "suku ", "tiga suku jam ", "pukul 4 kurang 10 ", "esok ", "esok pagi ",
      "malam ini ", "nanti malam ", "Isnin ", "setiap Isnin ", "setiap hari kerja ", "dari Isnin hingga Jumaat ",
      "Isnin dan Rabu ", "2 hari sekali ", "sekali ", "setiap ", "tarikh 15 ", "15 Oktober ", "15hb ", "15hb Oktober ",
      "15.10.2026 ", "3-5 Mei ", "dari 3 hingga 5 Mei ", "Mei ", "Sprint 12 - 20 Mei ", "sebelum Jumaat ", "sebelum ",
      "paling lewat ", "tarikh akhir ", "dalam 3 hari ", "3 hari lagi ", "minggu depan ", "hujung minggu ", "30 minit ",
      "2 jam ", "1,5 jam ", "setengah jam ", "sejam ", "sejam setengah ", "penting ", "keutamaan tinggi ", "prio ",
      "malam ", ", ", ".", "dan ", "jam ", "pukul ", "pada ", "tengah malam ", "tengah hari ", "tengah ", "hingga ",
      "sampai ", "sehingga ", "pukul 8 malam ", "makan malam ", "Ahad ", "hari Ahad ", "setiap Ahad pagi ",
      "Jumaat petang pukul 5 ", "sebelum Jumaat pukul 5 ", "lusa ", "kelmarin lusa ", "malam Jumaat ", "9.30 PG ",
      "pg ", "ptg ", "hb ", "pagi ", "petang ", "esok lusa ", "solat Jumaat ", "Jumaat Agung ",
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for token in tokens {
        let line = "Ani " + String(repeating: token, count: max(1, 5000 / token.count)) + " Telefon"
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
