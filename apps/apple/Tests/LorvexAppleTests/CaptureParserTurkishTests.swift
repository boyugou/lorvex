import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention. Counted in
// days from it, Wednesday is 1, Thursday 2, Friday 3, Saturday 4, Sunday 5,
// Monday 6, and the next Tuesday 7.
private func parse(_ text: String, languages: [String] = ["tr"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["tr"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let workdays = TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH", "FR"])
private let weekend = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weekly = TaskRecurrenceRule(freq: .weekly)
private let monthly = TaskRecurrenceRule(freq: .monthly)
private let yearly = TaskRecurrenceRule(freq: .yearly)

/// The unicode scalars of `text`. A title is compared by them where the typed
/// form matters, since `String` equality treats a letter with a combining mark
/// as equal to its precomposed form.
private func scalars(_ text: String) -> [Unicode.Scalar] {
  Array(text.unicodeScalars)
}

private let turkishLocale = Locale(identifier: "tr_TR")

/// `text` as someone types it on a keyboard without Turkish letters: ç, ğ, ı,
/// İ, ö, ş, ü as c, g, i, I, o, s, u.
private func withoutTurkishLetters(_ text: String) -> String {
  let plain: [Character: Character] = [
    "ç": "c", "Ç": "C", "ğ": "g", "Ğ": "G", "ı": "i", "İ": "I", "ö": "o", "Ö": "O", "ş": "s", "Ş": "S", "ü": "u",
    "Ü": "U",
  ]
  return String(text.map { plain[$0] ?? $0 })
}

/// `text` in capitals as Turkish writes them: i as İ and ı as I.
private func turkishCapitals(_ text: String) -> String {
  text.uppercased(with: turkishLocale)
}

/// `text` in capitals as a keyboard without Turkish rules makes them: both i and
/// ı as I.
private func plainCapitals(_ text: String) -> String {
  text.uppercased()
}

/// `text` in lowercase letters as Turkish writes them: İ as i and I as ı.
private func turkishLowercase(_ text: String) -> String {
  text.lowercased(with: turkishLocale)
}

/// The spellings of a Turkish line that read alike: as typed, in Turkish
/// capitals, in plain capitals, in Turkish lowercase, and without Turkish
/// letters in lowercase and in capitals.
private let spellings: [@Sendable (String) -> String] = [
  { $0 }, turkishCapitals, plainCapitals, turkishLowercase, withoutTurkishLetters,
  { plainCapitals(withoutTurkishLetters($0)) },
]

/// Turkish capture lines, read for a user whose languages include Turkish.
@Suite("Capture parser Turkish")
struct CaptureParserTurkishTests {
  // MARK: - Days

  @Test("Days: bugün, bu akşam, yarın, öbür gün, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Diş doktoru yarın")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Diş doktoru")
    #expect(line.phrases.map(\.text) == ["yarın"])

    let days: [(text: String, offset: Int)] = [
      ("Diş doktoru bugün", 0), ("Diş doktoru bu akşam", 0), ("Diş doktoru bu gece", 0), ("Diş doktoru bu sabah", 0),
      ("Diş doktoru bugün sabah", 0), ("Diş doktoru bugün akşam", 0),
      ("Diş doktoru yarın", 1), ("Diş doktoru yarın sabah", 1), ("Diş doktoru yarın akşam", 1),
      ("Diş doktoru yarın öğlen", 1), ("Diş doktoru yarın öğleden sonra", 1), ("Diş doktoru yarın gece", 1),
      ("Diş doktoru öbür gün", 2), ("Diş doktoru öbür gün sabah", 2),
      ("Diş doktoru 1 gün sonra", 1), ("Diş doktoru 3 gün sonra", 3), ("Diş doktoru üç gün sonra", 3),
      ("Diş doktoru bir gün sonra", 1), ("Diş doktoru iki gün sonra", 2), ("Diş doktoru on gün sonra", 10),
      ("Diş doktoru bir hafta sonra", 7), ("Diş doktoru 2 hafta sonra", 14), ("Diş doktoru iki hafta sonra", 14),
      ("Diş doktoru haftaya", 7), ("Diş doktoru önümüzdeki hafta", 7), ("Diş doktoru gelecek hafta", 7),
      ("Diş doktoru bu hafta sonu", 4), ("Diş doktoru önümüzdeki hafta sonu", 11),
      ("Diş doktoru gelecek hafta sonu", 11),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Diş doktoru", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Yarın diş doktoru")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "diş doktoru")
    // A month or a year ahead has no day offset, "bu gün" is "this day" in many sentences, and the
    // day-word adjectives ("yarınki", "bugünkü") name the day of something else.
    expectLinesUnread(
      [
        "Diş doktoru bir ay sonra", "Diş doktoru 3 ay sonra", "Diş doktoru bir yıl sonra",
        "Diş doktoru birkaç gün sonra", "Diş doktoru 3 gün içinde", "Bu gün çok güzel", "Bu gün toplantı var",
        "Yarınki toplantıyı hazırla", "Bugünkü işleri bitir", "Bugünün planı", "Yarının listesi",
      ], languages: ["tr"])
  }

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Diş doktoru pazartesi", 6), ("Diş doktoru salı", 7), ("Diş doktoru çarşamba", 1),
      ("Diş doktoru perşembe", 2), ("Diş doktoru cuma", 3), ("Diş doktoru cumartesi", 4),
      ("Diş doktoru cuma günü", 3), ("Diş doktoru pazar günü", 5), ("Diş doktoru pazartesi günü", 6),
      ("Diş doktoru pzt", 6), ("Diş doktoru cmt", 4), ("Diş doktoru Pzt", 6),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "bu salı" is today.
      ("Diş doktoru bu salı", 0), ("Diş doktoru bu çarşamba", 1), ("Diş doktoru bu cuma", 3),
      ("Diş doktoru bu cumartesi", 4), ("Diş doktoru bu pazar", 5), ("Diş doktoru bu pazartesi", 6),
      ("Diş doktoru önümüzdeki cuma", 3), ("Diş doktoru gelecek cuma", 3), ("Diş doktoru önümüzdeki salı", 7),
      ("Diş doktoru önümüzdeki çarşamba", 1), ("Diş doktoru önümüzdeki pazar", 5),
      // "Haftaya" and "önümüzdeki hafta" put the weekday in next week, which starts on Monday.
      ("Diş doktoru haftaya cuma", 10), ("Diş doktoru haftaya salı", 7), ("Diş doktoru haftaya pazartesi", 6),
      ("Diş doktoru haftaya çarşamba", 8), ("Diş doktoru haftaya pazar", 12),
      ("Diş doktoru gelecek hafta cuma", 10), ("Diş doktoru gelecek hafta pazartesi", 6),
      ("Diş doktoru önümüzdeki hafta cuma günü", 10), ("Diş doktoru gelecek hafta pazar", 12),
      // A part of the day written after the weekday, with its possessive ending or without it.
      ("Diş doktoru cuma akşamı", 3), ("Diş doktoru cuma akşam", 3), ("Diş doktoru cuma sabahı", 3),
      ("Diş doktoru cuma gecesi", 3), ("Diş doktoru cumartesi sabahı", 4), ("Diş doktoru pazar akşamı", 5),
      ("Diş doktoru pazar sabahı", 5), ("Diş doktoru haftaya cuma akşamı", 10), ("Diş doktoru cuma günü akşam", 3),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Diş doktoru", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("Diş doktoru cuma saat 9'da")
    #expect(timed.plannedDayOffset == 3)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Diş doktoru")
    let opening = parse("Cuma toplantı")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "toplantı")
    let sentence = parse("Yarın sınav var")
    #expect(sentence.plannedDayOffset == 1)
    #expect(sentence.title == "sınav var")
  }

  @Test("Pazar names Sunday only with a word that makes it a day; alone it is the market and stays in the title")
  func pazar() {
    for (text, offset) in [
      ("Diş doktoru pazar günü", 5), ("Diş doktoru bu pazar", 5), ("Diş doktoru pazar akşamı", 5),
      ("Diş doktoru önümüzdeki pazar", 5), ("Diş doktoru haftaya pazar", 12), ("Pazar günü alışveriş", 5),
    ] {
      #expect(parse(text).plannedDayOffset == offset, "\(text)")
    }
    #expect(parse("Pazar günü alışveriş").title == "alışveriş")
    expectLinesUnread(
      [
        "Diş doktoru pazar", "Pazar yerine git", "Pazar alışverişi", "Pazardan sebze al", "Pazara git",
        "Pazar pazarlığı yap",
      ], languages: ["tr"])
  }

  @Test("The short names sal, çar, per, cum, and paz are words of their own; pzt and cmt are weekdays")
  func shortNames() {
    expectLinesUnread(
      [
        "Doktor çar", "Per 5 adet al", "Sal bakalım", "Cum 5 adet", "Paz 3 kutu", "Doktor çarşambayı bekle",
        "Cuma'nın toplantısı", "Pazartesi'nin işleri", "Salı'nın hazırlığı",
      ], languages: ["tr"])
    #expect(parse("Toplantı pzt").plannedDayOffset == 6)
    #expect(parse("Toplantı cmt").plannedDayOffset == 4)
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("Rapor bu hafta sonu", 0), ("Rapor önümüzdeki hafta sonu", 7), ("Rapor cumartesi", 7),
      ("Rapor bu cumartesi", 0), ("Rapor pazar günü", 1), ("Rapor pazartesi", 2), ("Rapor haftaya cumartesi", 7),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("Rapor bu hafta sonu", 0), ("Rapor önümüzdeki hafta sonu", 7), ("Rapor pazar günü", 7),
      ("Rapor bu pazar", 0), ("Rapor haftaya pazar", 7), ("Rapor cumartesi", 6), ("Rapor pazartesi", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "bu pazartesi" is today.
    for (text, offset) in [
      ("Rapor pazartesi", 7), ("Rapor bu pazartesi", 0), ("Rapor önümüzdeki pazartesi", 7), ("Rapor salı", 1),
      ("Rapor haftaya pazartesi", 7),
    ] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("Rapor pazartesiye kadar", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("Spor her pazartesi", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("Rapor pazartesiden çarşambaya kadar", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
  }

  @Test("Past days and weeks are not read, and a clock time after one stays with it")
  func pastDays() {
    expectLinesUnread(
      [
        "Diş doktoru dün", "Diş doktoru dün akşam", "Diş doktoru dün gece", "Diş doktoru evvelsi gün",
        "Diş doktoru önceki gün", "Diş doktoru geçen cuma", "Diş doktoru geçen salı", "Diş doktoru geçen hafta",
        "Diş doktoru geçen hafta sonu", "Diş doktoru geçen akşam", "Diş doktoru dün saat 3'te",
        "Diş doktoru dün 15:30", "Dünkü toplantı notları", "Dünya turu planla", "Dünyayı gez",
      ], languages: ["tr"])
    // The words that follow a past day keep their own reading.
    let after = parse("Diş doktoru dün yarın")
    #expect(after.plannedDayOffset == 1)
    #expect(after.title == "Diş doktoru dün")
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year, an ending, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Depozito 15 Ekim", "Depozito", "2026-10-15"),
      ("Depozito 15 Ekim 2026", "Depozito", "2026-10-15"),
      ("Depozito 15 Ekim 2027", "Depozito", "2027-10-15"),
      ("Depozito 15 Ekim'de", "Depozito", "2026-10-15"),
      ("Depozito 15 Ekim’de", "Depozito", "2026-10-15"),
      ("Depozito 15 Ekimde", "Depozito", "2026-10-15"),
      ("Depozito 15 Eki", "Depozito", "2026-10-15"),
      ("Depozito 15 Eki.", "Depozito", "2026-10-15"),
      ("Depozito 15 eki.", "Depozito", "2026-10-15"),
      ("Depozito 1 Mayıs", "Depozito", "2027-05-01"),
      ("DEPOZİTO 15 EKİM", "DEPOZİTO", "2026-10-15"),
      ("Depozito 15 ekim", "Depozito", "2026-10-15"),
      ("Depozito 15.10.2026", "Depozito", "2026-10-15"),
      ("Depozito 15.10.2026'da", "Depozito", "2026-10-15"),
      ("Depozito 15.10.", "Depozito", "2026-10-15"),
      ("Depozito 15.10.26", "Depozito", "2026-10-15"),
      ("Depozito 15/10/2026", "Depozito", "2026-10-15"),
      ("Depozito 15-10-2026", "Depozito", "2026-10-15"),
      ("Depozito 15/10/26", "Depozito", "2026-10-15"),
      ("Depozito tarih 15.10", "Depozito", "2026-10-15"),
      ("Depozito tarih: 15/10", "Depozito", "2026-10-15"),
      ("Depozito 15/10'da", "Depozito", "2026-10-15"),
      ("Depozito 15/10'de", "Depozito", "2026-10-15"),
      ("Depozito 3 Ocak", "Depozito", "2027-01-03"), ("Depozito 3 Oca", "Depozito", "2027-01-03"),
      ("Depozito 3 Şubat", "Depozito", "2027-02-03"), ("Depozito 3 Şub", "Depozito", "2027-02-03"),
      ("Depozito 3 Mart", "Depozito", "2027-03-03"), ("Depozito 3 Mar", "Depozito", "2027-03-03"),
      ("Depozito 3 Nisan", "Depozito", "2027-04-03"), ("Depozito 3 Nis", "Depozito", "2027-04-03"),
      ("Depozito 3 Mayıs", "Depozito", "2027-05-03"), ("Depozito 3 May", "Depozito", "2027-05-03"),
      ("Depozito 3 Haziran", "Depozito", "2027-06-03"), ("Depozito 3 Haz", "Depozito", "2027-06-03"),
      ("Depozito 3 Temmuz", "Depozito", "2027-07-03"), ("Depozito 3 Tem", "Depozito", "2027-07-03"),
      ("Depozito 3 Ağustos", "Depozito", "2027-08-03"), ("Depozito 3 Ağu", "Depozito", "2027-08-03"),
      ("Depozito 3 Eylül", "Depozito", "2027-09-03"), ("Depozito 3 Eyl", "Depozito", "2027-09-03"),
      ("Depozito 3 Ekim", "Depozito", "2026-10-03"), ("Depozito 3 Eki", "Depozito", "2026-10-03"),
      ("Depozito 3 Kasım", "Depozito", "2026-11-03"), ("Depozito 3 Kas", "Depozito", "2026-11-03"),
      ("Depozito 3 Aralık", "Depozito", "2026-12-03"), ("Depozito 3 Ara", "Depozito", "2026-12-03"),
      ("Depozito 22 Eylül", "Depozito", "2026-09-22"),
      // A weekday before the date is part of it.
      ("Depozito Cuma 16 Ekim", "Depozito", "2026-10-16"),
      ("Depozito cuma 16 Ekim", "Depozito", "2026-10-16"),
      ("Depozito Cuma, 16 Ekim", "Depozito", "2026-10-16"),
      ("Depozito Cuma günü 16 Ekim", "Depozito", "2026-10-16"),
      ("Depozito Cuma 16.10.2026", "Depozito", "2026-10-16"),
      ("Ayşe'nin doğum günü 14 Mart", "Ayşe'nin doğum günü", "2027-03-14"),
      ("Bayram 1 Mayıs'ta", "Bayram", "2027-05-01"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Toplantı Perşembe 15 Ekim saat 14:30")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Toplantı")
    let concert = parse("Konser 20 Eki. saat 7'de")
    #expect(concert.plannedDayOffset == captureDayOffset("2026-10-20"))
    #expect(concert.startMinutes == 7 * 60)
    #expect(concert.title == "Konser")
    // The adjective ending after a locative date goes with it.
    let adjective = parse("15 Ekim'deki toplantı notları")
    #expect(adjective.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(adjective.title == "toplantı notları")
  }

  @Test("Numbers that are no date, a lowercase abbreviation, a past year, and a day the month lacks stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers with no word that makes them a date, and a bare month.
        "Depozito 15.10", "Depozito 15/10", "Ekim ayı raporu", "Haziran'da tatil", "Mayıs 2027 planı", "Aralık",
        // The abbreviations that are ordinary words read only capitalized or with a period.
        "Depozito 15 eki", "Depozito 15 ara", "Ev için 3 kas al", "Depozito 15 haz",
        // A day the month lacks and a year that is past.
        "Depozito 31 Şubat", "Depozito 15 Ekim 2025",
        // Chapters, versions, rooms, scores, percentages, prices, fractions, quarters, and phone numbers.
        "Bölüm 1.5 yaz", "Sürüm 2.3.4 yayınla", "Sayfa 15-10 oku", "Oda 15.10", "Skor 3-1", "%15 indirim", "Fiyat 15,50 TL",
        "iOS 17.4", "Q3 2026", "Annemi ara 0532 123 45 67", "Kitap 1/2 kilo", "Proje 1.5 sürüm", "Madde 2.3 oku",
        "Bölüm 3-1 yaz", "Karşılaştırma 3-5", "3/4 bardak süt",
      ], languages: ["tr"])
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Tatil", "3-5 Mayıs", "2027-05-03", "2027-05-05"),
        ("Tatil", "3-5 Mayıs 2027", "2027-05-03", "2027-05-05"),
        ("Tatil", "3-5 Mayıs'ta", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıs - 5 Mayıs", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıs – 5 Mayıs", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıs'tan 5 Mayıs'a kadar", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıs’tan 5 Mayıs’a kadar", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıstan 5 Mayısa kadar", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıs'tan 5 Mayıs'a", "2027-05-03", "2027-05-05"),
        ("Tatil", "3'ten 5 Mayıs'a kadar", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 ile 5 Mayıs arası", "2027-05-03", "2027-05-05"),
        ("Tatil", "3 Mayıs ile 5 Mayıs arasında", "2027-05-03", "2027-05-05"),
        ("Tatil", "30 Mayıs - 2 Haziran", "2027-05-30", "2027-06-02"),
        ("Tatil", "30 Mayıs'tan 2 Haziran'a kadar", "2027-05-30", "2027-06-02"),
        ("Tatil", "3-5 Ekim", "2026-10-03", "2026-10-05"),
        ("Tatil", "24 Ara - 2 Oca", "2026-12-24", "2027-01-02"),
        ("Tatil", "24 Aralık - 2 Ocak", "2026-12-24", "2027-01-02"),
        ("Yaz tatili", "3-5 Mayıs", "2027-05-03", "2027-05-05"),
      ], languages: ["tr"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Tatil 5-3 Mayıs", "Tatil 3 Mayıs - 3 Mayıs", "Tatil 5 Mayıs'tan 3 Mayıs'a kadar", "Fiyat 3-5 TL",
        "Tatil 3 ile 5 arası",
      ], languages: ["tr"])
    // A day alone and a month with its day joined by a spaced dash is a title and a date: "Sprint 12 - 20 Mayıs".
    for (text, title, date) in [
      ("Sprint 12 - 20 Mayıs", "Sprint 12", "2027-05-20"), ("Toplantı 12 - 14 Ekim", "Toplantı 12", "2026-10-14"),
      ("Tatil 3 - 5 Mayıs", "Tatil 3", "2027-05-05"),
    ] {
      let parsed = parse(text)
      #expect(parsed.title == title, "\(text): title")
      #expect(parsed.plannedDayOffset == captureDayOffset(date), "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time or a length still reads")
  func rangeTakesBothDays() {
    let line = parse("Tatil 3-5 Mayıs yarın")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Tatil yarın")
    let timed = parse("Tatil 3-5 Mayıs saat 9'da")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Tatil")
    let length = parse("Tatil 3-5 Mayıs 30 dk")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "Tatil")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so the span ends on the Wednesday
    // after the Monday.
    expectDateRanges(
      [
        ("Konferans", "cumadan pazara kadar", "2026-09-25", "2026-09-27"),
        ("Konferans", "cuma'dan pazar'a kadar", "2026-09-25", "2026-09-27"),
        ("Konferans", "cumadan pazartesiye kadar", "2026-09-25", "2026-09-28"),
        ("Konferans", "cumartesiden pazara", "2026-09-26", "2026-09-27"),
        ("Konferans", "cuma-pazar", "2026-09-25", "2026-09-27"),
        ("Konferans", "cuma - pazar", "2026-09-25", "2026-09-27"),
        ("Konferans", "cumartesi - pazar", "2026-09-26", "2026-09-27"),
        ("Konferans", "cuma ile pazar arası", "2026-09-25", "2026-09-27"),
        ("Tatil", "çarşambadan cumaya kadar", "2026-09-23", "2026-09-25"),
        ("Tatil", "pazartesi - çarşamba", "2026-09-28", "2026-09-30"),
        ("Tatil", "pazartesiden çarşambaya kadar", "2026-09-28", "2026-09-30"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Konferans", "salıdan perşembeye kadar", "2026-09-29", "2026-10-01"),
      ], languages: ["tr"])
    // Monday to Friday is the working week, which repeats.
    for text in [
      "Spor pazartesi - cuma", "Spor pazartesi-cuma", "Spor pazartesiden cumaya", "Spor pazartesiden cumaya kadar",
      "Spor hafta içi her gün", "Spor iş günleri", "Spor her iş günü",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Spor", "\(text): title")
    }
    let opening = parse("Pazartesi-cuma spor")
    #expect(opening.recurrence == workdays)
    #expect(opening.title == "spor")
  }

  // MARK: - Due days

  @Test("Due days: kadar, dek, değin, önce, son tarih, en geç, teslim, and deadline")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Raporu cumaya kadar bitir", "Raporu bitir", 3),
      ("Raporu cuma'ya kadar bitir", "Raporu bitir", 3),
      ("Raporu cuma’ya kadar bitir", "Raporu bitir", 3),
      ("Raporu cumaya dek bitir", "Raporu bitir", 3),
      ("Raporu cumaya değin bitir", "Raporu bitir", 3),
      ("Raporu cuma gününe kadar bitir", "Raporu bitir", 3),
      ("Raporu bu cumaya kadar bitir", "Raporu bitir", 3),
      ("Raporu önümüzdeki cumaya kadar bitir", "Raporu bitir", 3),
      ("Raporu haftaya cumaya kadar bitir", "Raporu bitir", 10),
      ("Raporu pazartesiye kadar bitir", "Raporu bitir", 6),
      ("Raporu perşembeye kadar bitir", "Raporu bitir", 2),
      ("Raporu cumartesiye kadar bitir", "Raporu bitir", 4),
      ("Raporu bu pazara kadar bitir", "Raporu bitir", 5),
      ("Raporu yarına kadar bitir", "Raporu bitir", 1),
      ("Raporu bugüne kadar bitir", "Raporu bitir", 0),
      ("Raporu öbür güne kadar bitir", "Raporu bitir", 2),
      ("Raporu haftaya kadar bitir", "Raporu bitir", 7),
      ("Raporu 15 Ekim'e kadar bitir", "Raporu bitir", 23),
      ("Raporu 15 Ekim 2026'ya kadar bitir", "Raporu bitir", 23),
      ("Raporu 15.10.2026'ya kadar bitir", "Raporu bitir", 23),
      ("Raporu 15.10'a kadar bitir", "Raporu bitir", 23),
      ("Raporu 15/10'a kadar bitir", "Raporu bitir", 23),
      ("Raporu cumadan önce bitir", "Raporu bitir", 3),
      ("Raporu 15 Ekim'den önce bitir", "Raporu bitir", 23),
      ("Raporu son tarih cuma", "Raporu", 3),
      ("Raporu son tarih: cuma", "Raporu", 3),
      ("Raporu son tarih 15 Ekim", "Raporu", 23),
      ("Raporu son gün cuma", "Raporu", 3),
      ("Raporu son teslim tarihi cuma", "Raporu", 3),
      ("Raporu en geç cuma", "Raporu", 3),
      ("Raporu en geç yarın", "Raporu", 1),
      ("Raporu en geç cuma akşamı", "Raporu", 3),
      ("Raporu en geç 15 Ekim", "Raporu", 23),
      ("Raporu teslim: 15 Ekim", "Raporu", 23),
      ("Raporu teslim cuma", "Raporu", 3),
      ("Raporu teslim tarihi cuma", "Raporu", 3),
      ("Raporu termin cuma", "Raporu", 3),
      ("Raporu deadline cuma", "Raporu", 3),
      ("Raporu deadline: yarın", "Raporu", 1),
      ("Raporu vade cuma", "Raporu", 3),
      ("Raporu SON TARİH CUMA", "Raporu", 3),
      ("Raporu CUMAYA KADAR bitir", "Raporu bitir", 3),
      ("Raporu cumaya kadar", "Raporu", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Raporu cumaya kadar bitir bugün")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 0)
    #expect(both.title == "Raporu bitir")
    // A due phrase that opens the line.
    let opening = parse("Cumaya kadar raporu bitir")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "raporu bitir")
    // A day with no word that makes it a deadline is a planned day, and the market, a count of days, and
    // a verb that follows "teslim" are no deadline.
    #expect(parse("Raporu cuma günü teslim et").plannedDayOffset == 3)
    #expect(parse("Raporu cuma günü teslim et").dueDayOffset == nil)
    expectLinesUnread(
      [
        "Raporu pazara kadar bitir", "Raporu 3 güne kadar bitir", "Raporu teslim et", "Raporu kadar iyi yaz",
        "Evrakı teslim al", "Yarına kalma",
      ], languages: ["tr"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Toplantı saat 5'e kadar", "Toplantı 17:00'ye kadar", "Toplantı saat 17:00'den önce",
        "Toplantı saat 5'ten sonra", "Toplantı saat beşe kadar", "Toplantı en geç saat 17:00",
        "Toplantı saat 17.30'a kadar", "Toplantı akşam 8'e kadar", "Toplantı en erken saat 9",
        "Toplantı saat 9'dan sonra",
      ], languages: ["tr"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Raporu cuma saat 17:00'ye kadar bitir", "Raporu saat 17:00'ye kadar bitir", 3),
      ("Raporu yarın en geç saat 5", "Raporu en geç saat 5", 1),
      ("Raporu son tarih cuma saat 17:00", "Raporu saat 17:00", 3),
      ("Raporu teslim: yarın 9.00", "Raporu 9.00", 1),
      ("Raporu en geç cuma saat 5", "Raporu saat 5", 3),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A bound written with "en geç" and a part of the day, a spoken hour, or minutes stays whole; with a month after
    // the number it is a date, and a dotted number whose minutes are a month is a date before kadar.
    expectLinesUnread(
      [
        "Toplantı en geç akşam 8'de", "Toplantı en geç saat beşte", "Toplantı en geç 17:30", "Toplantı en geç 17.30",
        "Toplantı 17.30'a kadar", "Toplantı 9.00'a kadar", "Toplantı 17:30'a kadar",
      ], languages: ["tr"])
    for (text, due) in [
      ("Raporu en geç 15 Ekim", 23), ("Raporu en geç 15.10", 23), ("Raporu 15.10'a kadar bitir", 23),
      ("Raporu 15/10'a kadar bitir", 23),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
    }
    // A time range that ends in a clock time is still a range, and a bound after a day stays a bound.
    let range = parse("Toplantı saat 14'ten 17:30'a kadar")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 210)
    #expect(range.title == "Toplantı")
    let bound = parse("Toplantı saat 17:30'a kadar yarın")
    #expect(bound.plannedDayOffset == 1)
    #expect(bound.startMinutes == nil)
    #expect(bound.title == "Toplantı saat 17:30'a kadar")
    // Without Turkish, English reads the clock time and leaves the words.
    let english = parse("Toplantı saat 17:00'ye kadar", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
  }

  // MARK: - Clock times

  @Test("Clock times: saat, a case ending, a part of the day, noon, and AM and PM")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Toplantı saat 15:00", 15 * 60), ("Toplantı saat 15.00", 15 * 60), ("Toplantı saat 15", 15 * 60),
      ("Toplantı saat 15:30", 15 * 60 + 30), ("Toplantı 15:30'da", 15 * 60 + 30), ("Toplantı 15:30’da", 15 * 60 + 30),
      ("Toplantı 15.30'da", 15 * 60 + 30), ("Toplantı saat 3'te", 15 * 60), ("Toplantı saat 3’te", 15 * 60),
      ("Toplantı saat 3te", 15 * 60), ("Toplantı 15:30da", 15 * 60 + 30), ("Toplantı 15.30da", 15 * 60 + 30),
      ("Toplantı saat 5'te", 17 * 60), ("Toplantı 5'te", 17 * 60),
      ("Toplantı 9'da", 9 * 60), ("Toplantı 11'de", 11 * 60), ("Toplantı 9:30'da", 9 * 60 + 30),
      ("Toplantı 14'te", 14 * 60), ("Toplantı saat 14.30'da", 14 * 60 + 30),
      // The hours from 1 to 6 with no part of the day are the afternoon, and 7 and later are the morning.
      ("Toplantı saat 1'de", 13 * 60), ("Toplantı saat 6'da", 18 * 60), ("Toplantı 6'da", 18 * 60),
      ("Toplantı saat 7", 7 * 60), ("Toplantı saat 7'de", 7 * 60), ("Toplantı saat 11", 11 * 60),
      ("Toplantı saat 12", 12 * 60), ("Toplantı saat 06:30", 6 * 60 + 30), ("Toplantı saat 03:00", 3 * 60),
      ("Toplantı saat 15.10", 15 * 60 + 10),
      // A part of the day before the hour.
      ("Toplantı akşam 8", 20 * 60), ("Toplantı akşam 8'de", 20 * 60), ("Toplantı akşam saat 8'de", 20 * 60),
      ("Toplantı akşam 7:30", 19 * 60 + 30), ("Toplantı akşamı 8", 20 * 60), ("Toplantı sabah 9", 9 * 60),
      ("Toplantı sabah 9'da", 9 * 60), ("Toplantı sabah 7.30", 7 * 60 + 30), ("Toplantı sabah 11'de", 11 * 60),
      ("Toplantı öğlen 12", 12 * 60), ("Toplantı öğlen 12'de", 12 * 60), ("Toplantı öğleden sonra 3", 15 * 60),
      ("Toplantı öğleden sonra 3'te", 15 * 60), ("Toplantı öğleden sonra saat 3'te", 15 * 60),
      ("Toplantı ikindi 4", 16 * 60), ("Toplantı akşam 6", 18 * 60), ("Toplantı gece 11'de", 23 * 60),
      ("Toplantı akşam 20:30", 20 * 60 + 30),
      // An hour spelled as a word, after "saat".
      ("Toplantı saat üç", 15 * 60), ("Toplantı saat üçte", 15 * 60), ("Toplantı saat altıda", 18 * 60),
      ("Toplantı saat yedide", 7 * 60), ("Toplantı saat on iki", 12 * 60), ("Toplantı saat on birde", 11 * 60),
      ("Toplantı akşam sekizde", 20 * 60), ("Toplantı sabah dokuzda", 9 * 60),
      // AM and PM after "saat" take "saat" with them; with no "saat" English reads them.
      ("Toplantı saat 3pm", 15 * 60), ("Toplantı saat 3 pm", 15 * 60), ("Toplantı saat 3:30 pm", 15 * 60 + 30),
      ("Toplantı 3pm", 15 * 60), ("Toplantı 17:30", 17 * 60 + 30), ("Toplantı 15:30", 15 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Toplantı", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The title is what the time leaves.
    #expect(parse("Annemi ara saat 3'te").title == "Annemi ara")
    #expect(parse("Bankaya git saat 9'da").title == "Bankaya git")
    #expect(parse("Görüşme yarın saat 14:30").title == "Görüşme")
    // An hour after "bu akşam" or "her sabah" takes that part of the day, which belongs to the day or the repeat.
    for (text, minutes) in [("Toplantı bu akşam 8'de", 20 * 60), ("Toplantı bu akşam saat 8", 20 * 60)] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 0, "\(text): planned day")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.title == "Toplantı", "\(text): title")
    }
    // A colon time with a part of the day named elsewhere in the line takes that part of the day.
    let colon = parse("Bu akşam toplantı 7:30")
    #expect(colon.plannedDayOffset == 0)
    #expect(colon.startMinutes == 19 * 60 + 30)
    #expect(colon.title == "toplantı")
  }

  @Test("After midnight: gece, gece yarısı run past the midnight that ends the day")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("Toplantı gece 12", 1, 0), ("Toplantı gece 2", 1, 2 * 60), ("Toplantı gece 1'de", 1, 60),
      ("Toplantı gece yarısı", 1, 0), ("Toplantı gece yarısında", 1, 0), ("Toplantı bu gece yarısı", 1, 0),
      ("Toplantı yarın gece yarısı", 2, 0), ("Toplantı yarın gece 2'de", 2, 2 * 60),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Toplantı", "\(line): title")
    }
    // Eleven at night is still the day itself, and the 24th hour is no time of day.
    let eleven = parse("Toplantı gece 11'de")
    #expect(eleven.plannedDayOffset == nil)
    #expect(eleven.startMinutes == 23 * 60)
    expectLinesUnread(["Toplantı saat 24", "Toplantı saat 24:00", "Toplantı saat 25:00", "Toplantı saat 9:60"], languages: ["tr"])
  }

  @Test("Spoken times: buçuk, çeyrek geçe, çeyrek var, and kala name the hour with minutes added or taken off")
  func spokenTimes() {
    // "Buçuk" is the half hour after the hour it follows: "üç buçuk" is 3:30, never 2:30.
    for (line, minutes) in [
      ("Toplantı saat üç buçuk", 15 * 60 + 30), ("Toplantı saat üç buçukta", 15 * 60 + 30),
      ("Toplantı üç buçukta", 15 * 60 + 30), ("Toplantı saat 3 buçuk", 15 * 60 + 30),
      ("Toplantı akşam sekiz buçuk", 20 * 60 + 30), ("Toplantı akşam 8 buçuk", 20 * 60 + 30),
      ("Toplantı öğleden sonra üç buçuk", 15 * 60 + 30), ("Toplantı sabah dokuz buçukta", 9 * 60 + 30),
      ("Toplantı saat yedi buçuk", 7 * 60 + 30), ("Toplantı saat on iki buçuk", 12 * 60 + 30),
      ("Toplantı saat bir buçukta", 13 * 60 + 30),
      // The quarter and the minutes after or before the hour, with the hour in its case ending.
      ("Toplantı üçü çeyrek geçe", 15 * 60 + 15), ("Toplantı saat üçü çeyrek geçe", 15 * 60 + 15),
      ("Toplantı üçü on geçe", 15 * 60 + 10), ("Toplantı üçü yirmi beş geçe", 15 * 60 + 25),
      ("Toplantı 3'ü çeyrek geçe", 15 * 60 + 15), ("Toplantı dörde çeyrek var", 15 * 60 + 45),
      ("Toplantı saat dörde çeyrek var", 15 * 60 + 45), ("Toplantı 4'e çeyrek var", 15 * 60 + 45),
      ("Toplantı üçe on var", 14 * 60 + 50), ("Toplantı beşe yirmi kala", 16 * 60 + 40),
      ("Toplantı akşam sekizi çeyrek geçe", 20 * 60 + 15), ("Toplantı akşam dokuza çeyrek kala", 20 * 60 + 45),
      ("Toplantı bire çeyrek var", 12 * 60 + 45),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
      #expect(parsed.title == "Toplantı", "\(line): title")
      #expect(parsed.phrases.count == 1, "\(line): phrases")
    }
    // "Üç buçuk" with no "saat", part of the day, or ending is as often an amount.
    expectLinesUnread(["Toplantı üç buçuk", "Süt iki buçuk", "Toplantı bir buçuk"], languages: ["tr"])
  }

  @Test("Spoken minutes written with a unit word stay in the title whole")
  func spokenMinutesWithUnit() {
    expectLinesUnread(
      ["Toplantı üçü on dakika geçe", "Toplantı üçe on dakika var", "Toplantı dörde yirmi dakika kala"],
      languages: ["tr"])
  }

  @Test("A bare number counts as a time only after saat, a part of the day, or with a case ending")
  func bareNumbers() {
    expectLinesUnread(
      [
        "Toplantı 5", "Toplantı 15", "3 kişi akşam 8 kişi", "Akşam 8 kişi gelecek", "Toplantı akşam 8 kutu",
        "Hafta 5 toplantı", "Sınıf 3 yaz",
      ], languages: ["tr"])
    // An amount of things after a part of the day and a number is no hour.
    #expect(parse("Toplantı akşam 8 kişilik").startMinutes == nil)
  }

  @Test("Time ranges: a dash, ile with arası, and the endings of 14'ten 16'ya kadar")
  func timeRanges() {
    for (text, start, length) in [
      ("Toplantı saat 14-16", 14 * 60, 120), ("Toplantı saat 14 - 16", 14 * 60, 120),
      ("Toplantı 14.00-16.00", 14 * 60, 120), ("Toplantı 10:00-11:00", 10 * 60, 60),
      ("Toplantı 10:00 - 11:30", 10 * 60, 90), ("Toplantı saat 14'ten 16'ya kadar", 14 * 60, 120),
      ("Toplantı saat 14’ten 16’ya kadar", 14 * 60, 120), ("Toplantı 10:00'dan 11:00'e kadar", 10 * 60, 60),
      ("Toplantı saat 14 ile 16 arası", 14 * 60, 120), ("Toplantı 10:00 ile 11:00 arasında", 10 * 60, 60),
      ("Toplantı akşam 7-9", 19 * 60, 120), ("Toplantı sabah 9-11", 9 * 60, 120), ("Toplantı saat 2-4", 14 * 60, 120),
      ("Toplantı öğleden sonra 2-4", 14 * 60, 120), ("Toplantı saat 9'dan 10:30'a kadar", 9 * 60, 90),
    ] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == start, "\(text): start")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == "Toplantı", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // Two bare hours with no "saat", part of the day, or minutes are as often an amount or numbered items.
    expectLinesUnread(
      ["Toplantı 14-16", "Toplantı 14-16 arası", "Toplantı 2'den 4'e kadar", "Sayfa 14-16 oku"], languages: ["tr"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Rapor 30 dakika", 30), ("Rapor 30 dk", 30), ("Rapor 30 dak.", 30), ("Rapor 30 dk.", 30),
      ("Rapor 90 dakika", 90), ("Rapor 1 saat", 60), ("Rapor 2 saat", 120), ("Rapor 24 saat", 24 * 60),
      ("Rapor 1,5 saat", 90), ("Rapor 1.5 saat", 90), ("Rapor 0,5 saat", 30), ("Rapor 2,5 saat", 150),
      ("Rapor 1 saat 30 dakika", 90), ("Rapor 1 saat 30 dk", 90), ("Rapor 2 saat 15 dakika", 135),
      ("Rapor 1 saat ve 30 dakika", 90), ("Rapor yarım saat", 30), ("Rapor çeyrek saat", 15),
      ("Rapor üç çeyrek saat", 45), ("Rapor bir buçuk saat", 90), ("Rapor iki buçuk saat", 150),
      ("Rapor iki saat", 120), ("Rapor üç saat", 180), ("Rapor on dakika", 10), ("Rapor yirmi dakika", 20),
      ("Rapor otuz dakika", 30), ("Rapor kırk beş dakika", 45), ("Rapor 45 dakikalık", 45), ("Rapor 2 saatlik", 120),
      ("Rapor yarım saatlik", 30), ("Rapor yaklaşık 2 saat", 120), ("Rapor 2 saat boyunca", 120),
      ("Rapor 2 saat kadar", 120), ("Rapor 2 saat sürecek", 120), ("Rapor tahmini süre: 2 saat", 120),
      ("Rapor süre: 30 dk", 30), ("Rapor toplam 2 saat", 120),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Rapor", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A length as an adjective goes with the noun after it, and the title keeps the noun.
    let meeting = parse("45 dakikalık toplantı")
    #expect(meeting.estimatedMinutes == 45)
    #expect(meeting.title == "toplantı")
    let walk = parse("2 saatlik yürüyüş")
    #expect(walk.estimatedMinutes == 120)
    #expect(walk.title == "yürüyüş")
  }

  @Test("An amount of time that names a moment, a bound, the past, or a rate, a size, and a single minute are no length")
  func notLengths() {
    expectLinesUnread(
      [
        "Rapor 30 dakika sonra", "Rapor 2 saat içinde", "Rapor en fazla 2 saat", "Rapor en az 2 saat", "Rapor her 2 saat",
        "Rapor 2-3 saat", "Rapor 3 saat önce", "Rapor 2 saat daha", "Rapor 25 saat", "Rapor son 30 dakika",
        "Rapor bir dakika", "Rapor 2 saat başı", "Rapor 3 saat sonraya", "Rapor 2 saatten fazla",
      ], languages: ["tr"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every other and every nth")
  func repeats() {
    let rules: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Spor her gün", daily), ("Spor hergün", daily), ("Spor her hafta", weekly), ("Spor her ay", monthly),
      ("Spor her yıl", yearly), ("Spor her sene", yearly), ("Spor haftada bir", weekly), ("Spor ayda bir", monthly),
      ("Spor yılda bir", yearly), ("Spor günde bir", daily), ("Spor iki günde bir", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Spor 3 günde bir", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Spor üç günde bir", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Spor iki haftada bir", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Spor 3 haftada bir", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("Spor iki ayda bir", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Spor 6 ayda bir", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("Spor iki yılda bir", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("Spor 14 günde bir", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Spor 7 günde bir", weekly), ("Spor gün aşırı", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Spor hafta aşırı", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Spor her ikinci gün", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Spor her ikinci hafta", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Spor her 2 gün", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Spor her 3 hafta", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("Spor her üç gün", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Spor her sabah", daily), ("Spor her akşam", daily), ("Spor her gece", daily), ("Spor her öğlen", daily),
      ("Spor günlük", daily), ("Spor haftalık", weekly), ("Spor aylık", monthly), ("Spor yıllık", yearly),
      ("Spor günlük olarak", daily), ("Spor haftalık olarak", weekly), ("Spor aylık olarak", monthly),
      ("Spor HER GÜN", daily), ("SPOR HER HAFTA", weekly), ("Spor her Gün", daily),
    ]
    for line in rules {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title.lowercased() == "spor", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // "Her iki gün" is "both days" as often as "every two days": a counted number reads, "iki" alone does not.
    #expect(parse("Spor her iki gün").recurrence == nil)
    #expect(parse("Spor her 2 gün").recurrence == TaskRecurrenceRule(freq: .daily, interval: 2))
    // The title keeps the text around the phrase.
    #expect(parse("Her gün yürüyüş").recurrence == daily)
    #expect(parse("Her gün yürüyüş").title == "yürüyüş")
    // A repeat with a time.
    let evening = parse("Spor her akşam 8'de")
    #expect(evening.recurrence == daily)
    #expect(evening.startMinutes == 20 * 60)
    #expect(evening.title == "Spor")
    let morning = parse("Spor her sabah 7'de")
    #expect(morning.startMinutes == 7 * 60)
    #expect(parse("Spor her gün saat 5'te").startMinutes == 17 * 60)
  }

  @Test("Weekday repeats: her pazartesi, pazartesi günleri, pazartesileri, and the working days and the weekend")
  func weekdayRepeats() {
    let rules: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Spor her pazartesi", monday), ("Spor her Pazartesi", monday), ("Spor her salı", TaskRecurrenceRule(freq: .weekly, byDay: ["TU"])),
      ("Spor her cuma", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("Spor her pazar", TaskRecurrenceRule(freq: .weekly, byDay: ["SU"])),
      ("Spor her hafta cuma", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("Spor pazartesi günleri", monday), ("Spor pazartesileri", monday),
      ("Spor cumaları", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("Spor pazar günleri", TaskRecurrenceRule(freq: .weekly, byDay: ["SU"])),
      ("Spor salıları", TaskRecurrenceRule(freq: .weekly, byDay: ["TU"])),
      ("Spor perşembeleri", TaskRecurrenceRule(freq: .weekly, byDay: ["TH"])),
      ("Spor her pazartesi ve perşembe", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"])),
      ("Spor pazartesi ve perşembe günleri", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"])),
      ("Spor her pazartesi, çarşamba ve cuma", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"])),
      ("Spor cumartesi ve pazar günleri", weekend),
      ("Spor iki haftada bir cuma", TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR"])),
      ("Spor pazartesi akşamları", monday), ("Spor her pazartesi akşamları", monday),
      ("Spor cumaları akşamları", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      // The working days and the weekend.
      ("Spor hafta içi her gün", workdays), ("Spor her gün hafta içi", workdays), ("Spor her hafta içi", workdays),
      ("Spor hafta içi günleri", workdays), ("Spor hafta içleri", workdays), ("Spor iş günleri", workdays),
      ("Spor her iş günü", workdays), ("Spor pazartesi-cuma", workdays), ("Spor pazartesiden cumaya", workdays),
      ("Spor hafta sonları", weekend), ("Spor her hafta sonu", weekend), ("Spor hafta sonlarında", weekend),
    ]
    for line in rules {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "Spor", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The repeat starts on its first weekday: today is Tuesday.
    #expect(parse("Spor her pazartesi").recurrenceStartOffset == 6)
    #expect(parse("Spor her cuma").recurrenceStartOffset == 3)
    // The weekend and the working days start on the first day after today that fits.
    #expect(parse("Spor hafta sonları").recurrenceStartOffset == 4)
    #expect(parse("Spor hafta içi her gün").recurrenceStartOffset == 0)
    // A single weekday with "her" is a repeat, with "bu" or alone a day.
    #expect(parse("Spor cuma").recurrence == nil)
    #expect(parse("Spor cuma").plannedDayOffset == 3)
    // A weekday repeat with a time.
    let timed = parse("Spor her pazartesi saat 7'de")
    #expect(timed.recurrence == monday)
    #expect(timed.startMinutes == 7 * 60)
    #expect(timed.title == "Spor")
  }

  @Test("A day of the month repeats every month")
  func monthDayRepeats() {
    for (text, day) in [
      ("Kira her ayın 1'i", 1), ("Kira her ayın 15'inde", 15), ("Kira her ayın 5'inde", 5), ("Kira her ay 15'inde", 15),
      ("Kira her ayın 15'i", 15), ("Kira her ayın 15’inde", 15), ("Kira her ayın 30'unda", 30), ("Kira her ayın 22'sinde", 22),
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [day]), "\(text)")
      #expect(parsed.title == "Kira", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A number after "her ay" that counts something is no day.
    let amount = parse("Kira her ay 15 TL öde")
    #expect(amount.recurrence == monthly)
    #expect(amount.title == "Kira 15 TL öde")
  }

  @Test("A cadence adjective is a repeat at the end of the line, before a colon, or with olarak, and a title elsewhere")
  func cadenceAdjectives() {
    expectLinesUnread(
      [
        "Günlük rapor", "Haftalık rapor yaz", "Aylık plan hazırla", "Yıllık izin planla", "Günlük hayat", "Hafta içi",
        "Hafta sonu planları", "Her şey tamam", "Her gün için", "Her ayın sonu",
      ], languages: ["tr"])
    for (text, title, rule) in [
      ("Haftalık: rapor yaz", "rapor yaz", weekly), ("Günlük: su iç", "su iç", daily), ("Rapor haftalık", "Rapor", weekly),
      ("Rapor haftalık.", "Rapor.", weekly), ("Rapor yaz haftalık olarak", "Rapor yaz", weekly),
      ("Raporu aylık olarak gönder", "Raporu gönder", monthly),
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.title == title, "\(text): title")
    }
  }

  // MARK: - Priorities

  @Test("Priorities: acil, önemli, yüksek öncelik, düşük öncelik, and öncelik")
  func priorities() {
    for (text, title, priority) in [
      ("Raporu gönder acil", "Raporu gönder", LorvexTask.Priority.p1),
      ("Raporu gönder acil.", "Raporu gönder", .p1), ("Raporu gönder ACİL", "Raporu gönder", .p1),
      ("Raporu gönder acilen", "Raporu gönder", .p1), ("Raporu gönder önemli", "Raporu gönder", .p1),
      ("Raporu gönder çok önemli", "Raporu gönder", .p1), ("Raporu gönder son derece önemli", "Raporu gönder", .p1),
      ("Acil: raporu gönder", "raporu gönder", .p1), ("Önemli, raporu gönder", "raporu gönder", .p1),
      ("Raporu gönder yüksek öncelik", "Raporu gönder", .p1), ("Raporu gönder yüksek öncelikli", "Raporu gönder", .p1),
      ("Raporu gönder çok yüksek öncelik", "Raporu gönder", .p1), ("Raporu gönder orta öncelik", "Raporu gönder", .p2),
      ("Raporu gönder normal öncelik", "Raporu gönder", .p2), ("Raporu gönder düşük öncelik", "Raporu gönder", .p3),
      ("Raporu gönder düşük öncelikli", "Raporu gönder", .p3), ("Raporu gönder öncelik: yüksek", "Raporu gönder", .p1),
      ("Raporu gönder öncelik: düşük", "Raporu gönder", .p3), ("Raporu gönder öncelik: orta", "Raporu gönder", .p2),
      ("Raporu gönder öncelik 1", "Raporu gönder", .p1), ("Raporu gönder öncelik 2", "Raporu gönder", .p2),
      ("Raporu gönder öncelik 3", "Raporu gönder", .p3), ("Raporu gönder Öncelik: Yüksek", "Raporu gönder", .p1),
      ("Raporu gönder YÜKSEK ÖNCELİK", "Raporu gönder", .p1), ("Raporu gönder yuksek oncelik", "Raporu gönder", .p1),
    ] {
      let parsed = parse(text)
      #expect(parsed.priority == priority, "\(text)")
      #expect(parsed.title == title, "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // An adjective that goes on to a noun, or a negation after it, is no priority.
    expectLinesUnread(
      [
        "Acil servis randevusu", "Raporu gönder acil değil", "Önemli bir toplantı hazırla", "Acil durum planı yap",
        "Önemli kişileri ara", "Acil çıkış", "Öncelik sırasını belirle", "Düşük bütçeli plan",
      ], languages: ["tr"])
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyKindAtOnce() {
    let line = parse("Annemi ara yarın akşam 8'de 30 dakika acil")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 20 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.priority == .p1)
    #expect(line.title == "Annemi ara")
    let weekly = parse("Okul toplantısı cuma akşamı saat 7'de 1 saat her hafta yüksek öncelik")
    #expect(weekly.plannedDayOffset == 3)
    #expect(weekly.startMinutes == 19 * 60)
    #expect(weekly.estimatedMinutes == 60)
    #expect(weekly.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(weekly.priority == .p1)
    #expect(weekly.title == "Okul toplantısı")
    let report = parse("Raporu cumaya kadar bitir bugün saat 3'te 2 saat önemli")
    #expect(report.dueDayOffset == 3)
    #expect(report.plannedDayOffset == 0)
    #expect(report.startMinutes == 15 * 60)
    #expect(report.estimatedMinutes == 120)
    #expect(report.priority == .p1)
    #expect(report.title == "Raporu bitir")
    // The hash words stay as they are read for every language.
    let tagged = parse("Dişçi randevusu #sağlık yarın")
    #expect(tagged.plannedDayOffset == 1)
    #expect(tagged.tags == ["sağlık"])
    #expect(tagged.title == "Dişçi randevusu")
  }

  @Test("Words that look like details stay in the title")
  func ordinaryWords() {
    expectLinesUnread(
      [
        "Pazar yerine git", "Pazar alışverişi", "Doktor çar", "Per 5 adet al", "Yıllık izin planla", "15 ara vermek",
        "Hafta sonu planları", "Hafta içi", "Her şey tamam", "Günlük rapor", "Acil servis randevusu", "Dünya turu planla",
        "ISLAK havlu", "Islak havlu", "Işık faturası", "Ara Mehmet'i", "Annemi ara", "Sal bakalım", "Yarınki toplantı",
        "Ekim ayı raporu", "Mayıs planı", "Saat tamiri", "Saatçi", "Saati kur", "Kitap oku", "Anneme çiçek al",
        "Kız kardeşim", "Gün sonu raporu", "Hafta sonu", "Ay sonu raporu", "Yıl sonu planı", "Dakika başına ücret",
        "Çeyrek altın al", "Yarım ekmek al", "Buçuk", "Bir buçuk kilo elma", "Bir kilo elma al", "İki ekmek al",
      ], languages: ["tr"])
  }

  @Test("Extra spaces and punctuation between details change nothing, and a hyphen joins a compound that is no day")
  func punctuationAndHyphens() {
    let line = parse("Toplantı  yarın,  saat 3'te.")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(parse("Yarın, toplantı").plannedDayOffset == 1)
    #expect(parse("Toplantı (yarın)").plannedDayOffset == 1)
    expectLinesUnread(["Cuma-akşam yemeği hazırla", "Yarın-sabah koşusu"], languages: ["tr"])
  }

  @Test("Turkish letters, plain letters, and either dotted or dotless i read alike, and the title keeps the letters it was typed with")
  func letterSpelling() {
    let days: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Diş doktoru yarın", "Diş doktoru", { $0.plannedDayOffset == 1 }),
      ("Diş doktoru yarın akşam", "Diş doktoru", { $0.plannedDayOffset == 1 }),
      ("Diş doktoru öbür gün", "Diş doktoru", { $0.plannedDayOffset == 2 }),
      ("Diş doktoru salı", "Diş doktoru", { $0.plannedDayOffset == 7 }),
      ("Diş doktoru çarşamba", "Diş doktoru", { $0.plannedDayOffset == 1 }),
      ("Diş doktoru perşembe", "Diş doktoru", { $0.plannedDayOffset == 2 }),
      ("Diş doktoru cumartesi", "Diş doktoru", { $0.plannedDayOffset == 4 }),
      ("Diş doktoru cuma günü", "Diş doktoru", { $0.plannedDayOffset == 3 }),
      ("Diş doktoru pazar günü", "Diş doktoru", { $0.plannedDayOffset == 5 }),
      ("Diş doktoru bu akşam", "Diş doktoru", { $0.plannedDayOffset == 0 }),
      ("Diş doktoru haftaya cuma", "Diş doktoru", { $0.plannedDayOffset == 10 }),
      ("Diş doktoru önümüzdeki hafta", "Diş doktoru", { $0.plannedDayOffset == 7 }),
      ("Diş doktoru 3 gün sonra", "Diş doktoru", { $0.plannedDayOffset == 3 }),
      ("Diş doktoru 15 Ekim", "Diş doktoru", { $0.plannedDayOffset == 23 }),
      ("Diş doktoru 15 Ağustos", "Diş doktoru", { $0.plannedDayOffset == captureDayOffset("2027-08-15") }),
      ("Diş doktoru 3 Eylül", "Diş doktoru", { $0.plannedDayOffset == captureDayOffset("2027-09-03") }),
      ("Raporu cumaya kadar bitir", "Raporu bitir", { $0.dueDayOffset == 3 }),
      ("Raporu yarına kadar bitir", "Raporu bitir", { $0.dueDayOffset == 1 }),
      ("Raporu 15 Ekim'e kadar bitir", "Raporu bitir", { $0.dueDayOffset == 23 }),
      ("Raporu son tarih cuma", "Raporu", { $0.dueDayOffset == 3 }),
      ("Raporu en geç yarın", "Raporu", { $0.dueDayOffset == 1 }),
      ("Raporu cumadan önce bitir", "Raporu bitir", { $0.dueDayOffset == 3 }),
      ("Tatil 3 Mayıs'tan 5 Mayıs'a kadar", "Tatil", { $0.dueDayOffset == captureDayOffset("2027-05-05") }),
    ]
    let times: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Toplantı öğleden sonra 3", "Toplantı", { $0.startMinutes == 15 * 60 }),
      ("Toplantı akşam 8'de", "Toplantı", { $0.startMinutes == 20 * 60 }),
      ("Toplantı saat üç buçukta", "Toplantı", { $0.startMinutes == 15 * 60 + 30 }),
      ("Toplantı üçü çeyrek geçe", "Toplantı", { $0.startMinutes == 15 * 60 + 15 }),
      ("Toplantı dörde çeyrek var", "Toplantı", { $0.startMinutes == 15 * 60 + 45 }),
      ("Toplantı gece yarısı", "Toplantı", { $0.startMinutes == 0 && $0.plannedDayOffset == 1 }),
      ("Rapor yarım saat", "Rapor", { $0.estimatedMinutes == 30 }),
      ("Rapor çeyrek saat", "Rapor", { $0.estimatedMinutes == 15 }),
      ("Rapor bir buçuk saat", "Rapor", { $0.estimatedMinutes == 90 }),
      ("Rapor 45 dakikalık", "Rapor", { $0.estimatedMinutes == 45 }),
      ("Rapor düşük öncelik", "Rapor", { $0.priority == .p3 }),
      ("Rapor yüksek öncelik", "Rapor", { $0.priority == .p1 }),
      ("Rapor çok önemli", "Rapor", { $0.priority == .p1 }),
    ]
    let repeats: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Spor her gün", "Spor", { $0.recurrence == daily }),
      ("Spor her pazartesi", "Spor", { $0.recurrence == monday }),
      ("Spor pazartesileri", "Spor", { $0.recurrence == monday }),
      ("Spor salı günleri", "Spor", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]) }),
      ("Spor hafta içi her gün", "Spor", { $0.recurrence == workdays }),
      ("Spor hafta sonları", "Spor", { $0.recurrence == weekend }),
      ("Spor iki haftada bir", "Spor", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2) }),
      ("Spor yılda bir", "Spor", { $0.recurrence == yearly }),
      ("Spor gün aşırı", "Spor", { $0.recurrence == TaskRecurrenceRule(freq: .daily, interval: 2) }),
      ("Kira her ayın 15'inde", "Kira", { $0.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [15]) }),
    ]
    for line in days + times + repeats {
      for spell in spellings {
        let typed = spell(line.text)
        let parsed = parse(typed)
        #expect(line.check(parsed), "\(typed)")
        #expect(scalars(parsed.title) == scalars(spell(line.title)), "\(typed): title")
      }
    }
  }

  @Test("The dotted and the dotless i read alike, in capitals and in lowercase")
  func dottedAndDotlessI() {
    // "Salı" ends in a dotless ı; every other spelling of the word is the same Tuesday.
    for word in ["Salı", "salı", "SALI", "SALİ", "sali", "Sali", "SALı", "salİ"] {
      let parsed = parse("Rapor \(word)")
      #expect(parsed.plannedDayOffset == 7, "\(word)")
      #expect(scalars(parsed.title) == scalars("Rapor"), "\(word): title")
    }
    for word in ["Cumartesi", "CUMARTESİ", "CUMARTESI", "cumartesi", "Cumartesı"] {
      #expect(parse("Rapor \(word)").plannedDayOffset == 4, "\(word)")
    }
    for word in ["yarın", "YARIN", "Yarin", "yarin", "YARİN"] {
      #expect(parse("Rapor \(word)").plannedDayOffset == 1, "\(word)")
    }
    // A capital dotted or dotless letter in a title word stays as it was typed.
    for (text, title) in [("İş yarın", "İş"), ("İŞ YARIN", "İŞ"), ("Işık yarın", "Işık"), ("ışık yarın", "ışık"), ("İİİİ yarın", "İİİİ")] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text)")
      #expect(scalars(parsed.title) == scalars(title), "\(text): title")
    }
    // Words that share letters with a weekday but are not one stay whole.
    expectLinesUnread(["ISLAK havlu", "Salıncak tamir et", "Salıcı ara", "SALIM bey"], languages: ["tr"])
  }

  @Test("Letters typed as a base letter and a combining mark keep their form, and an accent inside a detail word is left unread")
  func decomposedLetters() {
    // An accent in a title word changes nothing: both forms read the same, and each keeps its own scalars.
    let lines: [(typed: String, title: String)] = [
      ("Diş doktoru yarın", "Diş doktoru"), ("Çalışma planı cuma", "Çalışma planı"),
      ("Öğrenci toplantısı pazartesi", "Öğrenci toplantısı"), ("Şirket yemeği cuma", "Şirket yemeği"),
      ("Diş doktoru haftaya cuma", "Diş doktoru"), ("Güneş kremi her pazartesi", "Güneş kremi"),
      ("Çiçekçi yarın saat 5'te", "Çiçekçi"), ("Öğle yemeği cumaya kadar", "Öğle yemeği"),
      ("Şu işi 30 dakika yap", "Şu işi yap"),
    ]
    for line in lines {
      let composed = line.typed.precomposedStringWithCanonicalMapping
      let decomposed = line.typed.decomposedStringWithCanonicalMapping
      let expected = parse(composed)
      let parsed = parse(decomposed)
      #expect(parsed == expected, "\(line.typed)")
      #expect(!parsed.phrases.isEmpty, "\(line.typed): phrases")
      #expect(scalars(expected.title) == scalars(line.title.precomposedStringWithCanonicalMapping), "\(line.typed)")
      #expect(scalars(parsed.title) == scalars(line.title.decomposedStringWithCanonicalMapping), "\(line.typed)")
    }
    // A detail word typed with a combining accent is not read, and the line stays whole as typed.
    for line in [
      "Rapor perşembe", "Toplantı öğleden sonra 3", "Toplantı saat üç buçukta", "Rapor yüksek öncelik",
      "Rapor çeyrek saat", "Rapor 15 Ağustos", "Toplantı öbür gün", "Rapor önümüzdeki hafta",
      "Rapor 3 Şubat",
    ] {
      let composed = line.precomposedStringWithCanonicalMapping
      let decomposed = line.decomposedStringWithCanonicalMapping
      #expect(parse(composed).phrases.count == 1, "\(line)")
      let parsed = parse(decomposed)
      #expect(parsed.phrases.isEmpty, "\(line): phrases")
      #expect(scalars(parsed.title) == scalars(decomposed), "\(line): title")
    }
    // A decomposed letter in the one word of a phrase leaves that word, and the other words still read.
    let partial = parse("Diş doktoru yarın akşam".decomposedStringWithCanonicalMapping)
    #expect(partial.plannedDayOffset == 1)
    #expect(scalars(partial.title) == scalars("Diş doktoru akşam".decomposedStringWithCanonicalMapping))
    // The dotted capital typed as I and a combining dot is a different spelling that is left unread.
    let dotted = parse("Rapor CUMARTESI\u{0307}")
    #expect(dotted.plannedDayOffset == nil)
    #expect(scalars(dotted.title) == scalars("Rapor CUMARTESI\u{0307}"))
  }

  @Test("Straight, curly, and modifier apostrophes and none at all read alike before a case ending")
  func apostrophes() {
    for apostrophe in ["'", "\u{2019}", "\u{02BC}", ""] {
      #expect(parse("Rapor cuma\(apostrophe)ya kadar").dueDayOffset == 3, "cuma\(apostrophe)ya")
      #expect(parse("Toplantı saat 5\(apostrophe)te").startMinutes == 17 * 60, "5\(apostrophe)te")
      #expect(parse("Toplantı 15:30\(apostrophe)da").startMinutes == 15 * 60 + 30, "15:30\(apostrophe)da")
      #expect(parse("Rapor 15 Ekim\(apostrophe)e kadar").dueDayOffset == 23, "Ekim\(apostrophe)e")
      #expect(parse("Kira her ayın 15\(apostrophe)inde").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [15]))
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Turkish, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Turkish beside them as without it.
    for text in [
      "Call mom tomorrow at 3pm", "Gym every Monday at 7am", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m",
      "Meeting from 14:00-16:30", "Dentist on Friday at 3:30 pm", "Trip May 3-5", "Lunch at noon",
      "Buy milk for 2 people", "Plan trip 5 Oct", "Nap half an hour", "Review next week", "Submit report by Friday",
      "Call Dom on Sunday", "Study 2h", "Write report for 3 hours every other week", "Pay on the 1st of every month",
      "Weekend trip", "Meeting 3pm", "Meeting 17:30", "Review 20 min", "Read 30 minutes daily", "Meet at 15h",
      "Meet 10h", "Call her day after tomorrow", "Ask her morning", "Turn on 5 lights", "Mail 3 Mar", "Call in 15 min",
    ] {
      for languages in [["en", "tr"], ["tr", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Turkish writes its hours with "saat" or a case ending, so "15h" and "2h" are lengths beside it.
    let hours = parse("Write the report 2h", languages: ["en", "tr"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "tr"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    // A line may mix both languages.
    let mixed = parse("Call mom yarın at 3pm", languages: ["en", "tr"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting cuma at 3pm", languages: ["en", "tr"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Dentist tomorrow", languages: ["en", "tr"]).plannedDayOffset == 1)
    let review = parse("Review yarın saat 15:00 for 2 hours", languages: ["en", "tr"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english = parse("Rapor yarın 3pm")
    #expect(english.plannedDayOffset == 1)
    #expect(english.startMinutes == 15 * 60)
    #expect(english.title == "Rapor")
    #expect(parse("Toplantı 30 min").estimatedMinutes == 30)
    #expect(parse("Toplantı yarın 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("17:30 toplantı").startMinutes == 17 * 60 + 30)
    #expect(parse("toplantı 3pm").startMinutes == 15 * 60)
    #expect(parse("Toplantı tomorrow").plannedDayOffset == 1)
    #expect(parse("Toplantı every Monday").recurrence == monday)
    #expect(parse("Toplantı by friday").dueDayOffset == 3)
  }

  @Test("Lines in other languages read the same with Turkish beside them")
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
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "tr"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["tr", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Turkish with another language.
    for languages in [["fr", "tr"], ["tr", "fr"]] {
      let mixed = parse("Appeler maman yarın saat 3'te", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Appeler maman demain à 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste 3 mai", languages: languages).plannedDayOffset == captureDayOffset("2027-05-03"), "\(languages)")
      #expect(parse("Spor her pazartesi", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Rapport urgent", languages: languages).priority == .p1, "\(languages)")
      expectDateRanges(
        [
          ("Vacances", "du 3 au 5 mai", "2027-05-03", "2027-05-05"),
          ("Tatil", "3-5 Mayıs", "2027-05-03", "2027-05-05"),
        ], languages: languages)
    }
    #expect(parse("Toplantı 下午3点 yarın", languages: ["zh", "tr"]).plannedDayOffset == 1)
    #expect(parse("Toplantı מחר", languages: ["he", "tr"]).plannedDayOffset == 1)
    #expect(parse("Meeting jutro", languages: ["pl", "tr"]).plannedDayOffset == 1)
    // The Latin-script languages that go beside Turkish keep their own words: "morgen" is tomorrow in
    // Dutch and German, "yarın" in Turkish only.
    for languages in [["nl", "tr"], ["tr", "nl"], ["de", "tr"], ["tr", "de"], ["ro", "tr"], ["tr", "ro"]] {
      #expect(parse("Toplantı yarın saat 3'te", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Spor her pazartesi", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Tandarts overmorgen", languages: languages).plannedDayOffset == (languages.contains("nl") ? 2 : nil), "\(languages)")
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == (languages.contains("de") ? 2 : nil), "\(languages)")
    }
  }

  @Test("Turkish words are read only for a user who reads Turkish")
  func languageGate() {
    let line = parse("Diş doktoru yarın", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Diş doktoru yarın")
    for languages in [["tr"], ["tr-TR"], ["tr_CY"], ["tr-CY"], ["en-US", "tr-TR"], ["TR"]] {
      #expect(parse("Diş doktoru yarın", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Turkish reader.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen", "Dentist poimâine", "Rapat besok",
      ], languages: ["tr"])
    // Turkish words are not read for a reader of another language.
    for languages in [["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"]] {
      let parsed = parse("Diş doktoru yarın", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Diş doktoru yarın", "\(languages): title")
      #expect(parse("Toplantı akşam 8'de", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("Spor her pazartesi", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["tr"])
    let unit: [String] = [
      "saat 15:00 ", "saat 3'te ", "5'te ", "3 ", "saat ", "yarın ", "yarın akşam ", "cuma ", "cuma günü ", "bu cuma ",
      "haftaya cuma ", "15 Ekim ", "15.10.2026 ", "15/10 ", "3-5 Mayıs ", "3 Mayıs'tan 5 Mayıs'a kadar ",
      "cumaya kadar ", "cuma'ya kadar ", "kadar ", "son tarih cuma ", "en geç ", "her gün ", "her pazartesi ",
      "pazartesi günleri ", "iki haftada bir ", "hafta içi her gün ", "her ayın 15'inde ", "üç buçuk ",
      "saat üç buçukta ", "üçü çeyrek geçe ", "dörde çeyrek var ", "çeyrek ", "30 dakika ", "30 dk ", "1,5 saat ",
      "bir buçuk saat ", "yarım saat ", "acil ", "yüksek öncelik ", "öncelik: ", "cumadan pazara kadar ",
      "cuma-pazar ", "akşam 7-9 ", "saat 14'ten 16'ya kadar ", "bu akşam 8'de ", "gece yarısı ", "geçen ", "dün ",
      "ı", "İ", "ş", "s\u{0327}", "i\u{0307}", ", ", ".", "'", "-", "ve ", "ile ", "bu ", "her ", "bir ",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "Ali " + String(repeating: token, count: count) + " Telefon"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(30), "\(token) took \(elapsed)")
    }
    // A line past the read limit is a title and nothing more, at once.
    let past = String(repeating: "yarın saat 3'te ", count: 500).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    #expect(slowest < .seconds(30), "the slowest long line took \(slowest)")
    // The first phrase of a long line still reads.
    let first = parse("yarın " + String(repeating: "saat 3'te yarın ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 15 * 60)
  }
}
