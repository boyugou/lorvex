import Foundation
import Testing

@testable import LorvexCore

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention. Counted in
// days from it, Wednesday is 1, Thursday 2, Friday 3, Saturday 4, Sunday 5,
// Monday 6, and the next Tuesday 7.
private func parse(_ text: String, languages: [String] = ["el"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// Parses `text` on another day: `weekday` counts from Sunday (1) to Saturday (7).
private func parse(_ text: String, on today: String, weekday: Int) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["el"])
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

private let greekLocale = Locale(identifier: "el_GR")

/// `text` without the accents and diaeresis of its Greek letters, as a line
/// reads when typed on a keyboard layout without them.
private func withoutAccents(_ text: String) -> String {
  text.folding(options: .diacriticInsensitive, locale: nil)
}

/// `text` in capitals as Greek writes them: without accents.
private func greekCapitals(_ text: String) -> String {
  text.uppercased(with: greekLocale)
}

/// `text` in capitals that keep the accents of the lowercase letters, as a
/// plain uppercase mapping leaves them.
private func accentedCapitals(_ text: String) -> String {
  text.uppercased()
}

/// `text` with every final sigma ς written as σ.
private func withoutFinalSigma(_ text: String) -> String {
  text.replacingOccurrences(of: "ς", with: "σ")
}

/// The spellings of a Greek line that read alike: as typed, in capitals without
/// and with accents, in lowercase, without accents in lowercase and in capitals,
/// and with the final sigma written as σ.
private let spellings: [@Sendable (String) -> String] = [
  { $0 }, greekCapitals, accentedCapitals, { $0.lowercased() }, withoutAccents,
  { withoutAccents($0).uppercased() }, withoutFinalSigma, { withoutFinalSigma(withoutAccents($0)) },
]

/// Greek capture lines, read for a user whose languages include Greek.
@Suite("Capture parser Greek")
struct CaptureParserGreekTests {
  // MARK: - Days

  @Test("Days: σήμερα, απόψε, αύριο, μεθαύριο, a number of days or weeks, next week, and the weekend")
  func days() {
    let line = parse("Οδοντίατρος αύριο")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "Οδοντίατρος")
    #expect(line.phrases.map(\.text) == ["αύριο"])

    let days: [(text: String, offset: Int)] = [
      ("Οδοντίατρος σήμερα", 0), ("Οδοντίατρος απόψε", 0), ("Οδοντίατρος σήμερα το πρωί", 0),
      ("Οδοντίατρος σήμερα το βράδυ", 0),
      ("Οδοντίατρος αύριο", 1), ("Οδοντίατρος αύριο το πρωί", 1), ("Οδοντίατρος αύριο το μεσημέρι", 1),
      ("Οδοντίατρος αύριο το απόγευμα", 1), ("Οδοντίατρος αύριο το βράδυ", 1), ("Οδοντίατρος αύριο βράδυ", 1),
      ("Οδοντίατρος αύριο τη νύχτα", 1),
      ("Οδοντίατρος μεθαύριο", 2), ("Οδοντίατρος μεθαύριο το πρωί", 2),
      ("Οδοντίατρος σε 1 μέρα", 1), ("Οδοντίατρος σε μία μέρα", 1), ("Οδοντίατρος σε 3 μέρες", 3),
      ("Οδοντίατρος σε τρεις μέρες", 3), ("Οδοντίατρος σε δύο μέρες", 2), ("Οδοντίατρος σε 10 ημέρες", 10),
      ("Οδοντίατρος μετά από 3 μέρες", 3),
      ("Οδοντίατρος σε μία εβδομάδα", 7), ("Οδοντίατρος σε 2 εβδομάδες", 14),
      ("Οδοντίατρος σε δύο εβδομάδες", 14),
      ("Οδοντίατρος την επόμενη εβδομάδα", 7), ("Οδοντίατρος την άλλη εβδομάδα", 7),
      ("Οδοντίατρος για την επόμενη εβδομάδα", 7),
      ("Οδοντίατρος το Σαββατοκύριακο", 4), ("Οδοντίατρος αυτό το Σαββατοκύριακο", 4),
      ("Οδοντίατρος το Σαββατοκύριακο της επόμενης εβδομάδας", 11),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "Οδοντίατρος", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("Αύριο οδοντίατρος")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "οδοντίατρος")
    let sentence = parse("Αύριο έχω εξέταση")
    #expect(sentence.plannedDayOffset == 1)
    #expect(sentence.title == "έχω εξέταση")
    // A month or a year ahead has no day offset, an amount of hours is no day, and the adjectives made of a
    // day word ("αυριανό", "σημερινή") name the day of something else.
    expectLinesUnread(
      [
        "Οδοντίατρος σε ένα μήνα", "Οδοντίατρος σε 3 μήνες", "Οδοντίατρος σε ένα χρόνο", "Οδοντίατρος σε λίγες μέρες",
        "Οδοντίατρος μέσα σε 3 μέρες", "Οδοντίατρος σε 3 ώρες", "Οδοντίατρος αυριανό", "Η σημερινή λίστα",
        "Τα αυριανά", "Τρεις μέρες διακοπές",
      ], languages: ["el"])
  }

  @Test("The weekend names the coming Saturday only as the weekend of a phrase, and the word alone at the end of a line")
  func weekendWord() {
    let weekend = parse("Εκδρομή Σαββατοκύριακο")
    #expect(weekend.plannedDayOffset == 4)
    #expect(weekend.title == "Εκδρομή")
    let article = parse("Εκδρομή το Σαββατοκύριακο στην εξοχή")
    #expect(article.plannedDayOffset == 4)
    #expect(article.title == "Εκδρομή στην εξοχή")
    expectLinesUnread(["Σαββατοκύριακο στην εξοχή", "Σαββατοκύριακα στη θάλασσα"], languages: ["el"])
  }

  // MARK: - Weekdays

  @Test("Weekdays: the coming one, this week's, and next week's")
  func weekdays() {
    let weekdays: [(text: String, offset: Int)] = [
      ("Οδοντίατρος Δευτέρα", 6), ("Οδοντίατρος Παρασκευή", 3), ("Οδοντίατρος Σάββατο", 4),
      ("Οδοντίατρος Κυριακή", 5), ("Οδοντίατρος Τρίτη", 7), ("Οδοντίατρος Τετάρτη", 1),
      ("Οδοντίατρος Πέμπτη", 2), ("Οδοντίατρος τη Δευτέρα", 6), ("Οδοντίατρος την Τρίτη", 7),
      ("Οδοντίατρος την Τετάρτη", 1), ("Οδοντίατρος την Πέμπτη", 2), ("Οδοντίατρος την Παρασκευή", 3),
      ("Οδοντίατρος το Σάββατο", 4), ("Οδοντίατρος την Κυριακή", 5), ("Οδοντίατρος δευτέρα", 6),
      ("Οδοντίατρος σάββατο", 4), ("Οδοντίατρος παρασκευή", 3), ("Οδοντίατρος την τρίτη", 7),
      ("Οδοντίατρος την πέμπτη", 2),
      // Today is Tuesday, so a bare Tuesday is a week ahead and "αυτή την Τρίτη" is today.
      ("Οδοντίατρος αυτή την Τρίτη", 0), ("Οδοντίατρος αυτή την Τετάρτη", 1),
      ("Οδοντίατρος αυτή την Παρασκευή", 3), ("Οδοντίατρος αυτό το Σάββατο", 4),
      ("Οδοντίατρος αυτή τη Δευτέρα", 6),
      ("Οδοντίατρος την επόμενη Παρασκευή", 3), ("Οδοντίατρος την ερχόμενη Δευτέρα", 6),
      ("Οδοντίατρος την προσεχή Παρασκευή", 3), ("Οδοντίατρος το επόμενο Σάββατο", 4),
      ("Οδοντίατρος την επόμενη Τρίτη", 7), ("Οδοντίατρος την επόμενη Κυριακή", 5),
      // "Της επόμενης εβδομάδας" and "την επόμενη εβδομάδα" put the weekday in next week, which starts on Monday.
      ("Οδοντίατρος Παρασκευή της επόμενης εβδομάδας", 10), ("Οδοντίατρος Δευτέρα της επόμενης εβδομάδας", 6),
      ("Οδοντίατρος Τρίτη της επόμενης εβδομάδας", 7), ("Οδοντίατρος Κυριακή της επόμενης εβδομάδας", 12),
      ("Οδοντίατρος την επόμενη εβδομάδα Παρασκευή", 10), ("Οδοντίατρος την επόμενη εβδομάδα την Τρίτη", 7),
      ("Οδοντίατρος την άλλη εβδομάδα την Παρασκευή", 10),
      // A part of the day written after the weekday goes with it.
      ("Οδοντίατρος την Παρασκευή το πρωί", 3), ("Οδοντίατρος την Παρασκευή το βράδυ", 3),
      ("Οδοντίατρος Σάββατο βράδυ", 4), ("Οδοντίατρος την Κυριακή το απόγευμα", 5),
    ]
    for weekday in weekdays {
      let parsed = parse(weekday.text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.recurrence == nil, "\(weekday.text): repeat")
      #expect(parsed.title == "Οδοντίατρος", "\(weekday.text): title")
      #expect(parsed.phrases.count == 1, "\(weekday.text): phrases")
    }
    let timed = parse("Οδοντίατρος την Παρασκευή στις 9")
    #expect(timed.plannedDayOffset == 3)
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Οδοντίατρος")
    let opening = parse("Παρασκευή οδοντίατρος")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "οδοντίατρος")
    let article = parse("Την Παρασκευή αναφορά")
    #expect(article.plannedDayOffset == 3)
    #expect(article.title == "αναφορά")
    // The weekday after "και" or a comma is one of a list, which names no single planned day.
    expectLinesUnread(["Αναφορά Δευτέρα και Τρίτη", "Αναφορά Δευτέρα, Τετάρτη", "Αναφορά Δευτέρες", "Αναφορά Παρασκευές"], languages: ["el"])
  }

  @Test("Names that are also ordinals or first names name the day only where the words around them make it one")
  func ambiguousNames() {
    // Τρίτη, Τετάρτη, and Πέμπτη are also "third", "fourth", and "fifth": with the article, or capitalized after
    // another word, they are days. Παρασκευή and Κυριακή are first names.
    for (text, offset) in [
      ("Συνάντηση Τρίτη", 7), ("Συνάντηση την Τρίτη", 7), ("Συνάντηση Τετάρτη", 1), ("Συνάντηση την Τετάρτη", 1),
      ("Συνάντηση Πέμπτη", 2), ("Συνάντηση την Πέμπτη", 2), ("Συνάντηση Κυριακή", 5), ("Συνάντηση την Κυριακή", 5),
      ("Συνάντηση Παρασκευή", 3), ("Συνάντηση την Παρασκευή", 3), ("Συνάντηση Τρίτη στις 9", 7),
    ] {
      #expect(parse(text).plannedDayOffset == offset, "\(text)")
    }
    // An ordinal noun after the name, a lowercase name with no article, or a name that opens the line is the
    // ordinal; a name after "με", "από", or "η", or before a surname, is a person.
    expectLinesUnread(
      [
        "Συνάντηση την τρίτη φορά", "Συνάντηση την Τρίτη φορά", "Τρίτη θέση", "Συνάντηση τρίτη", "Συνάντηση τετάρτη",
        "Συνάντηση πέμπτη", "Τρίτη", "Πέμπτη τάξη", "Συνάντηση με την Κυριακή", "Συνάντηση με την Παρασκευή",
        "Συνάντηση από την Παρασκευή", "Συνάντηση την Κυριακή Παπαδοπούλου", "Κυριακή Παπαδοπούλου",
        "Συνάντηση Παρασκευή Παπαδοπούλου", "Μαρία και Κυριακή", "Συνάντηση η Δευτέρα", "Συνάντηση με Δευτέρα",
        "Αναφορά για την Κυριακή Παπαδοπούλου", "Συνάντηση Κυρ. Παπαδοπούλου", "Συνάντηση Παρ. Παπαδοπούλου",
      ], languages: ["el"])
  }

  @Test("Holidays and the nth weekday of a month stay in the title")
  func namedDays() {
    expectLinesUnread(
      [
        "Εκκλησία Μεγάλη Παρασκευή", "Εκκλησία Μεγάλη Πέμπτη", "Εκκλησία Μεγάλο Σάββατο", "Αργία Καθαρά Δευτέρα",
        "Αργία Δευτέρα του Αγίου Πνεύματος", "Φαγητό Κυριακή του Πάσχα", "Εκκλησία Κυριακή των Βαΐων",
        "Ψώνια Μαύρη Παρασκευή", "Συνάντηση κάθε πρώτη Δευτέρα του μήνα", "Συνάντηση την τελευταία Παρασκευή",
        "Συνάντηση κάθε δεύτερη Δευτέρα του μήνα", "Συνάντηση την τρίτη Παρασκευή",
        "Συνάντηση κάθε τρίτη Παρασκευή", "Συνάντηση δεύτερη Παρασκευή",
        "Συνάντηση την τελευταία Παρασκευή του μήνα",
      ], languages: ["el"])
    // The holiday keeps its words, and the rest of the line reads on.
    let holiday = parse("Εκκλησία Μεγάλη Παρασκευή στις 7 το βράδυ")
    #expect(holiday.plannedDayOffset == nil)
    #expect(holiday.startMinutes == 19 * 60)
    #expect(holiday.title == "Εκκλησία Μεγάλη Παρασκευή")
  }

  @Test("The short names Δευ, Τρι, Τετ, Πεμ, and Σαβ are weekdays; Παρ. and Κυρ. need their period")
  func shortNames() {
    for (text, offset) in [
      ("Συνάντηση Δευ", 6), ("Συνάντηση Δευ.", 6), ("Συνάντηση Τρι", 7), ("Συνάντηση Τετ", 1), ("Συνάντηση Τετ.", 1),
      ("Συνάντηση Πεμ", 2), ("Συνάντηση Σαβ", 4), ("Συνάντηση Σαβ.", 4), ("Συνάντηση Παρ.", 3),
      ("Συνάντηση Κυρ.", 5), ("Συνάντηση ΔΕΥ", 6), ("Συνάντηση δευ", 6), ("Συνάντηση την Παρ.", 3),
    ] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == offset, "\(text)")
      #expect(parsed.title == "Συνάντηση", "\(text): title")
    }
    // "Παρ" and "Κυρ" with no period are words of their own, and a name that is a prefix of a longer word is not read.
    expectLinesUnread(
      [
        "Συνάντηση Παρ", "Συνάντηση Κυρ", "Κυρ Δημήτρης", "Παρ' όλα αυτά", "Δευτερόλεπτα", "Τετ-α-τετ συζήτηση",
        "Τριήμερο ταξίδι", "Πεμπτουσία", "Σαββατιάτικο φαγητό",
      ], languages: ["el"])
  }

  @Test("The weekend and a weekday that names today count from the day the line is typed on")
  func otherToday() {
    // 2026-09-26 is a Saturday.
    for (text, offset) in [
      ("Αναφορά το Σαββατοκύριακο", 0), ("Αναφορά το Σαββατοκύριακο της επόμενης εβδομάδας", 7),
      ("Αναφορά το επόμενο Σαββατοκύριακο", 7), ("Αναφορά το Σάββατο", 7), ("Αναφορά αυτό το Σάββατο", 0),
      ("Αναφορά την Κυριακή", 1), ("Αναφορά τη Δευτέρα", 2), ("Αναφορά Παρασκευή της επόμενης εβδομάδας", 6),
    ] {
      #expect(parse(text, on: "2026-09-26", weekday: 7).plannedDayOffset == offset, "Saturday: \(text)")
    }
    // 2026-09-20 is a Sunday.
    for (text, offset) in [
      ("Αναφορά το Σαββατοκύριακο", 0), ("Αναφορά το Σαββατοκύριακο της επόμενης εβδομάδας", 6),
      ("Αναφορά την Κυριακή", 7), ("Αναφορά αυτή την Κυριακή", 0), ("Αναφορά το Σάββατο", 6),
      ("Αναφορά τη Δευτέρα", 1),
    ] {
      #expect(parse(text, on: "2026-09-20", weekday: 1).plannedDayOffset == offset, "Sunday: \(text)")
    }
    // 2026-09-21 is a Monday: a bare Monday is a week ahead, and "αυτή τη Δευτέρα" is today.
    for (text, offset) in [
      ("Αναφορά τη Δευτέρα", 7), ("Αναφορά αυτή τη Δευτέρα", 0), ("Αναφορά την επόμενη Δευτέρα", 7),
      ("Αναφορά την Τρίτη", 1), ("Αναφορά τη Δευτέρα της επόμενης εβδομάδας", 7),
    ] {
      #expect(parse(text, on: "2026-09-21", weekday: 2).plannedDayOffset == offset, "Monday: \(text)")
    }
    #expect(parse("Αναφορά μέχρι τη Δευτέρα", on: "2026-09-21", weekday: 2).dueDayOffset == 7)
    #expect(parse("Γυμναστική κάθε Δευτέρα", on: "2026-09-21", weekday: 2).recurrenceStartOffset == 0)
    let span = parse("Συνέδριο από Δευτέρα έως Τετάρτη", on: "2026-09-21", weekday: 2)
    #expect(span.plannedDayOffset == 7)
    #expect(span.dueDayOffset == 9)
  }

  @Test("Past days and weeks are not read, and a clock time after one stays with it")
  func pastDays() {
    expectLinesUnread(
      [
        "Αναφορά χθες", "Αναφορά χτες", "Αναφορά εχθές", "Αναφορά προχθές", "Αναφορά προχτές", "Αναφορά χθες το βράδυ",
        "Αναφορά χθες στις 3", "Αναφορά χθες 15:30", "Αναφορά την περασμένη Παρασκευή",
        "Αναφορά την προηγούμενη Δευτέρα", "Αναφορά την προηγούμενη εβδομάδα", "Αναφορά την περασμένη εβδομάδα",
        "Αναφορά το περασμένο Σαββατοκύριακο", "Αναφορά την περασμένη Δευτέρα το πρωί", "Χθεσινή αναφορά",
      ], languages: ["el"])
    // The words that follow a past day keep their own reading.
    let after = parse("Αναφορά χθες αύριο")
    #expect(after.plannedDayOffset == 1)
    #expect(after.title == "Αναφορά χθες")
  }

  // MARK: - Dates

  @Test("Written dates: a month name, an abbreviation, numbers, a year, and a weekday before them")
  func writtenDates() {
    let dates: [(text: String, title: String, date: String)] = [
      ("Γιορτή 15 Οκτωβρίου", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 Οκτωβρίου 2026", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 Οκτωβρίου 2027", "Γιορτή", "2027-10-15"),
      ("Γιορτή 15 του Οκτωβρίου", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 Οκτ", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 Οκτ.", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 οκτ.", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 Οκτώβρη", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 οκτωβριου", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15 ΟΚΤΩΒΡΙΟΥ", "Γιορτή", "2026-10-15"),
      ("ΓΙΟΡΤΗ 15 ΟΚΤΩΒΡΙΟΥ", "ΓΙΟΡΤΗ", "2026-10-15"),
      ("Γιορτή 1η Μαΐου", "Γιορτή", "2027-05-01"),
      ("Γιορτή 25ης Μαρτίου", "Γιορτή", "2027-03-25"),
      ("Γιορτή 22 Σεπτεμβρίου", "Γιορτή", "2026-09-22"),
      ("Γιορτή 15.10.2026", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15.10.26", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15.10.", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15/10/2026", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15-10-2026", "Γιορτή", "2026-10-15"),
      ("Γιορτή 15/10/26", "Γιορτή", "2026-10-15"),
      ("Γιορτή στις 15/10", "Γιορτή", "2026-10-15"),
      ("Γιορτή στις 15.10", "Γιορτή", "2026-10-15"),
      ("Γιορτή ημερομηνία 15/10", "Γιορτή", "2026-10-15"),
      ("Γιορτή ημερομηνία: 15/10", "Γιορτή", "2026-10-15"),
      ("Γιορτή 3 Ιανουαρίου", "Γιορτή", "2027-01-03"), ("Γιορτή 3 Ιαν", "Γιορτή", "2027-01-03"),
      ("Γιορτή 3 Φεβρουαρίου", "Γιορτή", "2027-02-03"), ("Γιορτή 3 Φεβ", "Γιορτή", "2027-02-03"),
      ("Γιορτή 3 Μαρτίου", "Γιορτή", "2027-03-03"), ("Γιορτή 3 Μαρ", "Γιορτή", "2027-03-03"),
      ("Γιορτή 3 Απριλίου", "Γιορτή", "2027-04-03"), ("Γιορτή 3 Απρ", "Γιορτή", "2027-04-03"),
      ("Γιορτή 3 Μαΐου", "Γιορτή", "2027-05-03"), ("Γιορτή 3 Μαΐ", "Γιορτή", "2027-05-03"),
      ("Γιορτή 3 Ιουνίου", "Γιορτή", "2027-06-03"), ("Γιορτή 3 Ιουν", "Γιορτή", "2027-06-03"),
      ("Γιορτή 3 Ιουλίου", "Γιορτή", "2027-07-03"), ("Γιορτή 3 Ιουλ", "Γιορτή", "2027-07-03"),
      ("Γιορτή 3 Αυγούστου", "Γιορτή", "2027-08-03"), ("Γιορτή 3 Αυγ", "Γιορτή", "2027-08-03"),
      ("Γιορτή 3 Σεπτεμβρίου", "Γιορτή", "2027-09-03"), ("Γιορτή 3 Σεπ", "Γιορτή", "2027-09-03"),
      ("Γιορτή 3 Οκτωβρίου", "Γιορτή", "2026-10-03"), ("Γιορτή 3 Οκτ", "Γιορτή", "2026-10-03"),
      ("Γιορτή 3 Νοεμβρίου", "Γιορτή", "2026-11-03"), ("Γιορτή 3 Νοε", "Γιορτή", "2026-11-03"),
      ("Γιορτή 3 Δεκεμβρίου", "Γιορτή", "2026-12-03"), ("Γιορτή 3 Δεκ", "Γιορτή", "2026-12-03"),
      ("Γιορτή 15 Γενάρη", "Γιορτή", "2027-01-15"), ("Γιορτή 15 Φλεβάρη", "Γιορτή", "2027-02-15"),
      ("Γιορτή 15 Μάρτη", "Γιορτή", "2027-03-15"), ("Γιορτή 15 Μάη", "Γιορτή", "2027-05-15"),
      // A weekday before the date is part of it.
      ("Γιορτή Παρασκευή 16 Οκτωβρίου", "Γιορτή", "2026-10-16"),
      ("Γιορτή την Παρασκευή 16 Οκτωβρίου", "Γιορτή", "2026-10-16"),
      ("Γιορτή Παρασκευή, 16 Οκτωβρίου", "Γιορτή", "2026-10-16"),
      ("Γιορτή Παρασκευή 16/10/2026", "Γιορτή", "2026-10-16"),
      ("Γιορτή την Παρασκευή 16/10/2026", "Γιορτή", "2026-10-16"),
      ("Γενέθλια Μαρίας 14 Μαρτίου", "Γενέθλια Μαρίας", "2027-03-14"),
      // A word that numbers an item counts only as a whole word: "Slav" ends in "v" and "κεφάλαιο" is a chapter.
      ("Συνάντηση Slav 15.10.2026", "Συνάντηση Slav", "2026-10-15"),
      ("Συνάντηση piano 15/10/2026", "Συνάντηση piano", "2026-10-15"),
    ]
    for line in dates {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(line.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(line.text): due day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let timed = parse("Συνάντηση Πέμπτη 15 Οκτωβρίου στις 14:30")
    #expect(timed.plannedDayOffset == captureDayOffset("2026-10-15"))
    #expect(timed.startMinutes == 14 * 60 + 30)
    #expect(timed.title == "Συνάντηση")
    let concert = parse("Συναυλία 20 Οκτ. στις 7 το βράδυ")
    #expect(concert.plannedDayOffset == captureDayOffset("2026-10-20"))
    #expect(concert.startMinutes == 19 * 60)
    #expect(concert.title == "Συναυλία")
  }

  @Test("Numbers that are no date, a month with no day, a nominative month, a past year, and a day the month lacks stay in the title")
  func notDates() {
    expectLinesUnread(
      [
        // Numbers with no word that makes them a date, and a month with no day.
        "Γιορτή 15.10", "Γιορτή 15/10", "Γιορτή Οκτωβρίου", "Γιορτή Οκτώβριος", "Γιορτή 15 Οκτώβριος", "Μάρτιος",
        "Ιούνιος 2027 πλάνο", "Δώρο 15 Μαρία", "Αγορά 15 Μαρμελάδες",
        // A day the month lacks, a day past the month's end, and a year that is past.
        "Γιορτή 31 Φεβρουαρίου", "Γιορτή 32 Μαΐου", "Γιορτή 15 Οκτωβρίου 2025",
        // Chapters, versions, scores, fractions, prices, percentages, addresses, and phone numbers.
        "Κεφάλαιο 1.5", "Έκδοση 2.3.4", "Σκορ 3-1", "Αναφορά 1/2 κιλό", "Αναφορά 3/4 ποτήρι", "Αναφορά 192.168.1.1",
        "Τιμή 15,50 ευρώ", "iOS 17.4", "Q3 2026", "Κάλεσε το 210 123 4567", "Σελίδα 15-10",
      ], languages: ["el"])
    // A percentage is no date, and the day word after it still reads.
    let discount = parse("Έκπτωση 15% σήμερα")
    #expect(discount.plannedDayOffset == 0)
    #expect(discount.title == "Έκπτωση 15%")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("Διακοπές", "3-5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "3-5 Μαΐου 2027", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "3 Μαΐου - 5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "3 Μαΐου – 5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "από 3 έως 5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "από τις 3 μέχρι τις 5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "από 3 ως 5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "από 3 Μαΐου έως 5 Μαΐου", "2027-05-03", "2027-05-05"),
        ("Διακοπές", "30 Μαΐου - 2 Ιουνίου", "2027-05-30", "2027-06-02"),
        ("Διακοπές", "από 30 Μαΐου έως 2 Ιουνίου", "2027-05-30", "2027-06-02"),
        ("Διακοπές", "3-5 Οκτωβρίου", "2026-10-03", "2026-10-05"),
        ("Διακοπές", "24 Δεκ - 2 Ιαν", "2026-12-24", "2027-01-02"),
        ("Διακοπές", "24 Δεκεμβρίου - 2 Ιανουαρίου", "2026-12-24", "2027-01-02"),
        ("Καλοκαιρινές διακοπές", "3-5 Μαΐου", "2027-05-03", "2027-05-05"),
      ], languages: ["el"])
  }

  @Test("A range whose end is not after its start, or that is only numbers, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "Διακοπές 5-3 Μαΐου", "Διακοπές 3 Μαΐου - 3 Μαΐου", "Διακοπές από 3 έως 5", "Τιμή 3-5 ευρώ",
        "Διακοπές από 5 Μαΐου έως 3 Μαΐου",
      ], languages: ["el"])
    // A day alone and a month with its day joined by a spaced dash is a title and a date: "Sprint 12 - 20 Μαΐου".
    for (text, title, date) in [
      ("Sprint 12 - 20 Μαΐου", "Sprint 12", "2027-05-20"), ("Συνάντηση 12 - 14 Οκτωβρίου", "Συνάντηση 12", "2026-10-14"),
      ("Διακοπές 3 - 5 Μαΐου", "Διακοπές 3", "2027-05-05"),
    ] {
      let parsed = parse(text)
      #expect(parsed.title == title, "\(text): title")
      #expect(parsed.plannedDayOffset == captureDayOffset(date), "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
  }

  @Test("A range takes both days, so another day phrase stays in the title, and a time or a length still reads")
  func rangeTakesBothDays() {
    let line = parse("Διακοπές 3-5 Μαΐου αύριο")
    #expect(line.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(line.title == "Διακοπές αύριο")
    let timed = parse("Διακοπές 3-5 Μαΐου στις 9")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(timed.startMinutes == 9 * 60)
    #expect(timed.title == "Διακοπές")
    let length = parse("Διακοπές 3-5 Μαΐου 30 λεπτά")
    #expect(length.dueDayOffset == captureDayOffset("2027-05-05"))
    #expect(length.estimatedMinutes == 30)
    #expect(length.title == "Διακοπές")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so the span ends on the Wednesday
    // after the Monday.
    expectDateRanges(
      [
        ("Συνέδριο", "από Παρασκευή έως Κυριακή", "2026-09-25", "2026-09-27"),
        ("Συνέδριο", "από την Παρασκευή μέχρι την Κυριακή", "2026-09-25", "2026-09-27"),
        ("Συνέδριο", "από Παρασκευή ως Κυριακή", "2026-09-25", "2026-09-27"),
        ("Συνέδριο", "Παρασκευή έως Κυριακή", "2026-09-25", "2026-09-27"),
        ("Συνέδριο", "Παρασκευή-Κυριακή", "2026-09-25", "2026-09-27"),
        ("Συνέδριο", "Παρασκευή - Κυριακή", "2026-09-25", "2026-09-27"),
        ("Συνέδριο", "Σάββατο-Κυριακή", "2026-09-26", "2026-09-27"),
        ("Συνέδριο", "από Παρασκευή έως Δευτέρα", "2026-09-25", "2026-09-28"),
        ("Συνέδριο", "από Τετάρτη έως Παρασκευή", "2026-09-23", "2026-09-25"),
        ("Συνέδριο", "από Δευτέρα έως Τετάρτη", "2026-09-28", "2026-09-30"),
        ("Συνέδριο", "Δευτέρα-Τετάρτη", "2026-09-28", "2026-09-30"),
        // Today's weekday opens next week's span, as a weekday alone does.
        ("Συνέδριο", "από Τρίτη έως Πέμπτη", "2026-09-29", "2026-10-01"),
      ], languages: ["el"])
    // Monday to Friday is the working week, which repeats.
    for text in [
      "Γυμναστική Δευτέρα - Παρασκευή", "Γυμναστική Δευτέρα-Παρασκευή", "Γυμναστική από Δευτέρα έως Παρασκευή",
      "Γυμναστική από τη Δευτέρα μέχρι την Παρασκευή", "Γυμναστική Δευτέρα έως Παρασκευή", "Γυμναστική Δευ-Παρ.",
      "Γυμναστική τις καθημερινές", "Γυμναστική κάθε εργάσιμη μέρα",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "Γυμναστική", "\(text): title")
    }
    let opening = parse("Δευτέρα-Παρασκευή γυμναστική")
    #expect(opening.recurrence == workdays)
    #expect(opening.title == "γυμναστική")
    // A span of grades is no span of days, and a span from a day to itself is none.
    expectLinesUnread(["Μάθημα από τρίτη έως πέμπτη τάξη", "Μάθημα Τρίτη-Τρίτη"], languages: ["el"])
  }

  // MARK: - Due days

  @Test("Due days: μέχρι, έως, ως, πριν, προθεσμία, παράδοση, deadline, το αργότερο, and για")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("Αναφορά μέχρι την Παρασκευή", "Αναφορά", 3),
      ("Αναφορά μέχρι Παρασκευή", "Αναφορά", 3),
      ("Αναφορά έως Παρασκευή", "Αναφορά", 3),
      ("Αναφορά ως Παρασκευή", "Αναφορά", 3),
      ("Αναφορά έως και Παρασκευή", "Αναφορά", 3),
      ("Αναφορά μέχρι και την Παρασκευή", "Αναφορά", 3),
      ("Αναφορά πριν την Παρασκευή", "Αναφορά", 3),
      ("Αναφορά πριν από την Παρασκευή", "Αναφορά", 3),
      ("Αναφορά μέχρι αύριο", "Αναφορά", 1),
      ("Αναφορά ως αύριο", "Αναφορά", 1),
      ("Αναφορά έως σήμερα", "Αναφορά", 0),
      ("Αναφορά μέχρι μεθαύριο", "Αναφορά", 2),
      ("Αναφορά μέχρι αύριο το βράδυ", "Αναφορά", 1),
      ("Αναφορά μέχρι το Σάββατο", "Αναφορά", 4),
      ("Αναφορά μέχρι τη Δευτέρα", "Αναφορά", 6),
      ("Αναφορά μέχρι την Τρίτη", "Αναφορά", 7),
      ("Αναφορά μέχρι την επόμενη Παρασκευή", "Αναφορά", 3),
      ("Αναφορά μέχρι την Παρασκευή της επόμενης εβδομάδας", "Αναφορά", 10),
      ("Αναφορά μέχρι την επόμενη εβδομάδα", "Αναφορά", 7),
      ("Αναφορά μέχρι τις 15 Οκτωβρίου", "Αναφορά", 23),
      ("Αναφορά μέχρι 15 Οκτωβρίου", "Αναφορά", 23),
      ("Αναφορά μέχρι 15/10", "Αναφορά", 23),
      ("Αναφορά μέχρι 15/10/2026", "Αναφορά", 23),
      ("Αναφορά μέχρι τις 15.10.2026", "Αναφορά", 23),
      ("Αναφορά έως 15 Οκτ.", "Αναφορά", 23),
      ("Αναφορά προθεσμία Παρασκευή", "Αναφορά", 3),
      ("Αναφορά προθεσμία: Παρασκευή", "Αναφορά", 3),
      ("Αναφορά η προθεσμία είναι Παρασκευή", "Αναφορά", 3),
      ("Αναφορά προθεσμία 15 Οκτωβρίου", "Αναφορά", 23),
      ("Αναφορά προθεσμία αύριο", "Αναφορά", 1),
      ("Αναφορά παράδοση Παρασκευή", "Αναφορά", 3),
      ("Αναφορά deadline Παρασκευή", "Αναφορά", 3),
      ("Αναφορά deadline: αύριο", "Αναφορά", 1),
      ("Αναφορά Παρασκευή το αργότερο", "Αναφορά", 3),
      ("Αναφορά το αργότερο Παρασκευή", "Αναφορά", 3),
      ("Αναφορά το αργότερο την Παρασκευή", "Αναφορά", 3),
      ("Αναφορά για αύριο", "Αναφορά", 1),
      ("Αναφορά για την Παρασκευή", "Αναφορά", 3),
      ("Αναφορά ΜΕΧΡΙ ΤΗΝ ΠΑΡΑΣΚΕΥΗ", "Αναφορά", 3),
      ("Αναφορά ΠΡΟΘΕΣΜΙΑ ΠΑΡΑΣΚΕΥΗ", "Αναφορά", 3),
      ("Αναφορά μεχρι την παρασκευη", "Αναφορά", 3),
      ("Αναφορά μέχρι την Παρασκευή να τελειώσει", "Αναφορά να τελειώσει", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A due day and a planned day on one line.
    let both = parse("Αναφορά μέχρι την Παρασκευή αύριο")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "Αναφορά")
    // A due phrase that opens the line.
    let opening = parse("Μέχρι την Παρασκευή αναφορά")
    #expect(opening.dueDayOffset == 3)
    #expect(opening.title == "αναφορά")
    // A day with no word that makes it a deadline is a planned day.
    #expect(parse("Αναφορά την Παρασκευή").plannedDayOffset == 3)
    #expect(parse("Αναφορά την Παρασκευή").dueDayOffset == nil)
    // A bound that is no day, a bare number, a count of days, a person, and a verb after "για" are no deadline.
    expectLinesUnread(
      [
        "Αναφορά μέχρι τώρα", "Αναφορά μέχρι 5", "Αναφορά έως το τέλος", "Αναφορά για 3 μέρες", "Αναφορά για αυτό",
        "Αναφορά για την Κυριακή Παπαδοπούλου",
      ], languages: ["el"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "Συνάντηση μέχρι τις 5", "Συνάντηση πριν τις 5", "Συνάντηση μετά τις 3", "Συνάντηση στις 5 το αργότερο",
        "Συνάντηση μέχρι τις 17:00", "Συνάντηση πριν τις 17:00", "Συνάντηση μετά τις 17:30",
        "Συνάντηση το αργότερο στις 5", "Συνάντηση μέχρι 5", "Συνάντηση μέχρι τις 5 το απόγευμα",
        "Συνάντηση μέχρι τις 9 π.μ.", "Συνάντηση μέχρι τις πέντε", "Συνάντηση το αργότερο 17:30",
      ], languages: ["el"])
    // The day before the clock is the due day, and the clock stays in the title.
    for (text, title, due) in [
      ("Αναφορά την Παρασκευή μέχρι τις 5", "Αναφορά μέχρι τις 5", 3),
      ("Αναφορά αύριο μέχρι τις 17:00", "Αναφορά μέχρι τις 17:00", 1),
      ("Αναφορά μέχρι αύριο στις 5", "Αναφορά στις 5", 1),
      ("Αναφορά προθεσμία Παρασκευή στις 5", "Αναφορά στις 5", 3),
      ("Αναφορά Παρασκευή το αργότερο στις 5", "Αναφορά το αργότερο στις 5", 3),
      ("Αναφορά το αργότερο την Παρασκευή στις 5", "Αναφορά στις 5", 3),
      ("Αναφορά την Παρασκευή στις 5 το αργότερο", "Αναφορά στις 5 το αργότερο", 3),
      ("Αναφορά μέχρι τις 15 Οκτωβρίου στις 5", "Αναφορά στις 5", 23),
    ] {
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == due, "\(text): due day")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == title, "\(text): title")
    }
    // A time range that ends in a clock time is still a range, and a plain time after a planned day reads.
    let range = parse("Αναφορά από τις 14 έως τις 17:30")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 210)
    #expect(range.title == "Αναφορά")
    let plain = parse("Αναφορά αύριο στις 5")
    #expect(plain.plannedDayOffset == 1)
    #expect(plain.startMinutes == 17 * 60)
    // Without Greek, English reads the clock time and leaves the words.
    let english = parse("Συνάντηση μέχρι τις 17:00", languages: ["en"])
    #expect(english.startMinutes == 17 * 60)
  }

  // MARK: - Clock times

  @Test("Clock times: στις, ώρα, a part of the day, π.μ. and μ.μ., and AM and PM")
  func clockTimes() {
    let times: [(text: String, minutes: Int)] = [
      ("Συνάντηση στις 15:00", 15 * 60), ("Συνάντηση στις 15.00", 15 * 60), ("Συνάντηση στις 15", 15 * 60),
      ("Συνάντηση στις 15:30", 15 * 60 + 30), ("Συνάντηση στις 3", 15 * 60), ("Συνάντηση στις 3:30", 15 * 60 + 30),
      ("Συνάντηση στις 3.30", 15 * 60 + 30), ("Συνάντηση ώρα 15:00", 15 * 60), ("Συνάντηση ώρα 3", 15 * 60),
      ("Συνάντηση ώρα 3.10", 15 * 60 + 10), ("Συνάντηση την ώρα 3", 15 * 60), ("Συνάντηση στις 9:30", 9 * 60 + 30),
      ("Συνάντηση στις 17", 17 * 60), ("Συνάντηση στις 07:30", 7 * 60 + 30),
      // The hours from 1 to 6 with no part of the day are the afternoon, and 7 and later are the morning.
      ("Συνάντηση στις 1", 13 * 60), ("Συνάντηση στις 6", 18 * 60), ("Συνάντηση στις 7", 7 * 60),
      ("Συνάντηση στις 11", 11 * 60), ("Συνάντηση στις 12", 12 * 60), ("Συνάντηση στις 06:30", 6 * 60 + 30),
      ("Συνάντηση στις 03:00", 3 * 60), ("Συνάντηση στις 13:00", 13 * 60),
      // An hour spelled as a word.
      ("Συνάντηση στη μία", 13 * 60), ("Συνάντηση στις δύο", 14 * 60), ("Συνάντηση στις τρεις", 15 * 60),
      ("Συνάντηση στις έξι", 18 * 60), ("Συνάντηση στις εννιά", 9 * 60), ("Συνάντηση στις δώδεκα", 12 * 60),
      // A part of the day after the hour, with or without its article.
      ("Συνάντηση στις 3 το απόγευμα", 15 * 60), ("Συνάντηση στις 3 το μεσημέρι", 15 * 60),
      ("Συνάντηση στις 9 το πρωί", 9 * 60), ("Συνάντηση στις 8 το βράδυ", 20 * 60),
      ("Συνάντηση στις 8 βράδυ", 20 * 60), ("Συνάντηση στις τρεις το μεσημέρι", 15 * 60),
      ("Συνάντηση 9 το πρωί", 9 * 60), ("Συνάντηση 8 βράδυ", 20 * 60), ("Συνάντηση 3 το μεσημέρι", 15 * 60),
      ("Συνάντηση 12 το μεσημέρι", 12 * 60), ("Συνάντηση 8:30 το βράδυ", 20 * 60 + 30),
      // A part of the day before the hour.
      ("Συνάντηση το απόγευμα στις 7", 19 * 60), ("Συνάντηση το πρωί στις 7", 7 * 60),
      ("Συνάντηση το μεσημέρι στις 2", 14 * 60), ("Συνάντηση το βράδυ στις 8", 20 * 60),
      // AM and PM written π.μ. and μ.μ., and as English writes them after "στις".
      ("Συνάντηση 9 π.μ.", 9 * 60), ("Συνάντηση 3 μ.μ.", 15 * 60), ("Συνάντηση στις 9 π.μ.", 9 * 60),
      ("Συνάντηση στις 3 μ.μ.", 15 * 60), ("Συνάντηση στις 3 π.μ.", 3 * 60), ("Συνάντηση 9.30 π.μ.", 9 * 60 + 30),
      ("Συνάντηση 9:30 π.μ.", 9 * 60 + 30), ("Συνάντηση 3 μ.μ", 15 * 60), ("Συνάντηση στις 3pm", 15 * 60),
      ("Συνάντηση στις 3 PM", 15 * 60), ("Συνάντηση στις 3:30 pm", 15 * 60 + 30),
      // With no Greek word English reads AM, PM, and a colon time.
      ("Συνάντηση 3pm", 15 * 60), ("Συνάντηση 17:30", 17 * 60 + 30), ("Συνάντηση 15:30", 15 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "Συνάντηση", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The title is what the time leaves.
    #expect(parse("Τηλέφωνο στη μαμά στις 3").title == "Τηλέφωνο στη μαμά")
    #expect(parse("Πήγαινε στην τράπεζα στις 9").title == "Πήγαινε στην τράπεζα")
    #expect(parse("Συνάντηση αύριο στις 14:30").title == "Συνάντηση")
    // A colon time with a part of the day named elsewhere in the line takes that part of the day.
    let colon = parse("Συνάντηση αύριο το βράδυ 8:30")
    #expect(colon.plannedDayOffset == 1)
    #expect(colon.startMinutes == 20 * 60 + 30)
    #expect(colon.title == "Συνάντηση")
    // An hour after a day with its part of the day takes that part of the day.
    for (text, day, minutes) in [
      ("Συνάντηση αύριο το βράδυ στις 8", 1, 20 * 60), ("Συνάντηση σήμερα το απόγευμα στις 5", 0, 17 * 60),
      ("Συνάντηση αύριο το πρωί στις 10", 1, 10 * 60), ("Συνάντηση απόψε στις 8", 0, 20 * 60),
      ("Συνάντηση την Παρασκευή το απόγευμα στις 5", 3, 17 * 60), ("Συνάντηση σήμερα το βράδυ στις 11", 0, 23 * 60),
    ] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day, "\(text): planned day")
      #expect(parsed.startMinutes == minutes, "\(text): time")
      #expect(parsed.title == "Συνάντηση", "\(text): title")
    }
    // A time and a day in either order.
    for text in ["Συνάντηση στις 3 μ.μ. αύριο", "Συνάντηση αύριο στις 3 μ.μ.", "Συνάντηση 3 μ.μ. αύριο"] {
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == 1, "\(text): planned day")
      #expect(parsed.startMinutes == 15 * 60, "\(text): time")
      #expect(parsed.title == "Συνάντηση", "\(text): title")
    }
  }

  @Test("After midnight: τα μεσάνυχτα and an hour at night run past the midnight that ends the day")
  func afterMidnight() {
    for (line, day, minutes) in [
      ("Συνάντηση στις 12 τα μεσάνυχτα", 1, 0), ("Συνάντηση στις 12 μεσάνυχτα", 1, 0),
      ("Συνάντηση τα μεσάνυχτα", 1, 0), ("Συνάντηση στα μεσάνυχτα", 1, 0), ("Συνάντηση 12 το βράδυ", 1, 0),
      ("Συνάντηση 2 τη νύχτα", 1, 2 * 60), ("Συνάντηση στις 2 τη νύχτα", 1, 2 * 60),
      ("Συνάντηση το βράδυ στις 12", 1, 0), ("Συνάντηση τη νύχτα στις 2", 1, 2 * 60),
      ("Συνάντηση στις 12 και μισή τα μεσάνυχτα", 1, 30), ("Συνάντηση απόψε στις 12", 1, 0),
      ("Συνάντηση αύριο τα μεσάνυχτα", 2, 0),
    ] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == day, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
      #expect(parsed.title == "Συνάντηση", "\(line): title")
    }
    // Eleven at night is still the day itself, "12 το πρωί" is no time of day, and the 24th hour is none.
    for (line, minutes) in [("Συνάντηση στις 11 τα μεσάνυχτα", 23 * 60), ("Συνάντηση 11 το βράδυ", 23 * 60)] {
      let parsed = parse(line)
      #expect(parsed.plannedDayOffset == nil, "\(line): planned day")
      #expect(parsed.startMinutes == minutes, "\(line): time")
    }
    expectLinesUnread(
      [
        "Συνάντηση στις 12 το πρωί", "Συνάντηση στις 24", "Συνάντηση στις 24:00", "Συνάντηση στις 25:00",
        "Συνάντηση στις 9:60", "Συνάντηση στις 25",
      ], languages: ["el"])
  }

  @Test("Spoken times: και μισή, και τέταρτο, και δέκα, and παρά name the hour with minutes added or taken off")
  func spokenTimes() {
    // "Και μισή" is the half hour after the hour it follows: "στις 3 και μισή" is 3:30, never 2:30.
    for (line, minutes) in [
      ("Συνάντηση στις 3 και μισή", 15 * 60 + 30), ("Συνάντηση στις τρεις και μισή", 15 * 60 + 30),
      ("Συνάντηση στη μία και μισή", 13 * 60 + 30), ("Συνάντηση στις δώδεκα και μισή", 12 * 60 + 30),
      ("Συνάντηση στις 8 και μισή το βράδυ", 20 * 60 + 30), ("Συνάντηση στις 3 και μισή το πρωί", 3 * 60 + 30),
      ("Συνάντηση στις 3 και μισή το μεσημέρι", 15 * 60 + 30), ("Συνάντηση στις εννιάμισι", 9 * 60 + 30),
      ("Συνάντηση στις 3 και τέταρτο", 15 * 60 + 15), ("Συνάντηση στις 5 και τέταρτο το απόγευμα", 17 * 60 + 15),
      ("Συνάντηση στις τρεις και είκοσι", 15 * 60 + 20), ("Συνάντηση στις 10 και 20", 10 * 60 + 20),
      ("Συνάντηση στις 5 και 15", 17 * 60 + 15), ("Συνάντηση στις 3 και δέκα", 15 * 60 + 10),
      ("Συνάντηση στις 7 και μισή", 7 * 60 + 30), ("Συνάντηση ώρα 3 και μισή", 15 * 60 + 30),
      // "Παρά" takes the minutes off the hour after it: "στις 4 παρά τέταρτο" is 3:45.
      ("Συνάντηση στις 4 παρά τέταρτο", 15 * 60 + 45), ("Συνάντηση στις 4 παρά 10", 15 * 60 + 50),
      ("Συνάντηση στις 5 παρά είκοσι", 16 * 60 + 40), ("Συνάντηση στις 1 παρά τέταρτο", 12 * 60 + 45),
      ("Συνάντηση στις τέσσερις παρά πέντε", 15 * 60 + 55), ("Συνάντηση στις 9 παρά τέταρτο", 9 * 60 - 15),
    ] {
      let parsed = parse(line)
      #expect(parsed.startMinutes == minutes, "\(line)")
      #expect(parsed.title == "Συνάντηση", "\(line): title")
      #expect(parsed.phrases.count == 1, "\(line): phrases")
    }
    // The day with the time.
    let withDay = parse("Συνάντηση στις 3 και μισή αύριο")
    #expect(withDay.plannedDayOffset == 1)
    #expect(withDay.startMinutes == 15 * 60 + 30)
    // "Τρεις και μισή" with no "στις" is as often an amount.
    expectLinesUnread(["Συνάντηση τρεις και μισή", "Ζάχαρη δύο και μισό κιλά"], languages: ["el"])
  }

  @Test("Spoken minutes written with a unit word stay in the title whole")
  func spokenMinutesWithUnit() {
    expectLinesUnread(
      ["Συνάντηση στις 3 και 10 λεπτά", "Συνάντηση στις τρεις και δέκα λεπτά", "Συνάντηση στις 4 παρά 5 λεπτά"],
      languages: ["el"])
  }

  @Test("A bare number counts as a time only after στις, στη, or ώρα, and not before a counted noun")
  func bareNumbers() {
    expectLinesUnread(
      [
        "Συνάντηση 5", "Συνάντηση 15", "Συνάντηση 3 άτομα", "Συνάντηση στις 3 άτομα", "Συνάντηση στις 3 ώρες",
        "Συνάντηση στις 3 φορές", "Συνάντηση 3 μμ", "Συνάντηση 24ωρο", "Συνάντηση 3 με 5", "Συνάντηση στις 8 κιλά",
        "Συνάντηση στις 3 ευρώ", "Ενοίκιο στις 15 ευρώ",
      ], languages: ["el"])
    // The words that can follow a time leave it a time, and the rest of the line stays.
    let with = parse("Συνάντηση στις 7 με τον Γιάννη")
    #expect(with.startMinutes == 7 * 60)
    #expect(with.title == "Συνάντηση με τον Γιάννη")
    let several = parse("Συνάντηση 9 το πρωί και 5 το απόγευμα")
    #expect(several.startMinutes == 9 * 60)
    #expect(several.title == "Συνάντηση και 5 το απόγευμα")
    // A date in numbers after "στις" is a date, and a clock time with dotted minutes that read as a month is a date.
    #expect(parse("Συνάντηση στις 3 Μαΐου").plannedDayOffset == captureDayOffset("2027-05-03"))
    #expect(parse("Συνάντηση στις 3 Μαΐου").startMinutes == nil)
    #expect(parse("Συνάντηση στις 3.10").plannedDayOffset == captureDayOffset("2026-10-03"))
    #expect(parse("Συνάντηση στις 3.10").startMinutes == nil)
  }

  @Test("Time ranges: a dash, από with έως or μέχρι, and a part of the day")
  func timeRanges() {
    for (text, start, length) in [
      ("Συνάντηση στις 14-16", 14 * 60, 120), ("Συνάντηση στις 14 - 16", 14 * 60, 120),
      ("Συνάντηση 14.00-16.00", 14 * 60, 120), ("Συνάντηση 10:00-11:00", 10 * 60, 60),
      ("Συνάντηση 10:00 - 11:30", 10 * 60, 90), ("Συνάντηση 15:30-17:00", 15 * 60 + 30, 90),
      ("Συνάντηση από 10:00 μέχρι 11:00", 10 * 60, 60), ("Συνάντηση από τις 3 έως τις 5", 15 * 60, 120),
      ("Συνάντηση από τις 2 μέχρι τις 4", 14 * 60, 120), ("Συνάντηση από τις 9 έως τις 10 το πρωί", 9 * 60, 60),
      ("Συνάντηση από τις 9 π.μ. έως τις 5 μ.μ.", 9 * 60, 480), ("Συνάντηση από τις 9:00 έως τις 10:30", 9 * 60, 90),
      ("Συνάντηση 3-5 το απόγευμα", 15 * 60, 120), ("Συνάντηση στις 10-12 το πρωί", 10 * 60, 120),
      ("Συνάντηση στις 10-12", 10 * 60, 120), ("Συνάντηση 11 μ.μ.-1 π.μ.", 23 * 60, 120),
      ("Συνάντηση από τις 23:00 έως τις 01:00", 23 * 60, 120), ("Συνάντηση από 3 έως 5 το απόγευμα", 15 * 60, 120),
      ("Συνάντηση το απόγευμα από τις 3 έως τις 5", 15 * 60, 120),
    ] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == start, "\(text): start")
      #expect(parsed.estimatedMinutes == length, "\(text): length")
      #expect(parsed.title == "Συνάντηση", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A time range names its length unless the line names one.
    let named = parse("Συνάντηση στις 14-16 30 λεπτά")
    #expect(named.startMinutes == 14 * 60)
    #expect(named.estimatedMinutes == 30)
    // Two bare hours with no "στις", part of the day, or minutes are as often an amount or numbered items.
    expectLinesUnread(
      ["Συνάντηση 14-16", "Συνάντηση 3-5", "Συνάντηση 2 έως 4", "Διάβασε σελίδες 14-16", "Συνάντηση από 2 έως 4"],
      languages: ["el"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("Αναφορά 30 λεπτά", 30), ("Αναφορά 30 λ", 30), ("Αναφορά 30 λ.", 30), ("Αναφορά 90 λεπτά", 90),
      ("Αναφορά 1 ώρα", 60), ("Αναφορά 2 ώρες", 120), ("Αναφορά 24 ώρες", 24 * 60), ("Αναφορά 1,5 ώρα", 90),
      ("Αναφορά 1.5 ώρα", 90), ("Αναφορά 0,5 ώρα", 30), ("Αναφορά 2,5 ώρες", 150),
      ("Αναφορά 1 ώρα και 30 λεπτά", 90), ("Αναφορά 1 ώρα 30 λεπτά", 90), ("Αναφορά 2 ώρες και 15 λεπτά", 135),
      ("Αναφορά μισή ώρα", 30), ("Αναφορά μιάμιση ώρα", 90), ("Αναφορά μία ώρα", 60), ("Αναφορά δύο ώρες", 120),
      ("Αναφορά τρεις ώρες", 180), ("Αναφορά δύο ώρες και μισή", 150), ("Αναφορά δυόμισι ώρες", 150),
      ("Αναφορά ένα τέταρτο της ώρας", 15), ("Αναφορά ένα τέταρτο", 15), ("Αναφορά τρία τέταρτα της ώρας", 45),
      ("Αναφορά είκοσι λεπτά", 20), ("Αναφορά δέκα λεπτά", 10), ("Αναφορά τριάντα λεπτά", 30),
      ("Αναφορά σαράντα πέντε λεπτά", 45), ("Αναφορά 45 λεπτά", 45), ("Αναφορά για 2 ώρες", 120),
      ("Αναφορά διάρκεια: 30 λεπτά", 30), ("Αναφορά διάρκεια 30 λεπτά", 30), ("Αναφορά περίπου 2 ώρες", 120),
      ("Αναφορά 2 ώρες περίπου", 120), ("Αναφορά εκτιμώμενη διάρκεια: 2 ώρες", 120),
      ("Αναφορά συνολικά 2 ώρες", 120), ("Αναφορά γύρω στα 30 λεπτά", 30), ("Αναφορά ΔΥΟ ΩΡΕΣ", 120),
    ]
    for line in lengths {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.startMinutes == nil, "\(line.text): time")
      #expect(parsed.title == "Αναφορά", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A length before the rest of the line, a length with a day, and a length with a time.
    let opening = parse("30 λεπτά ανάγνωση")
    #expect(opening.estimatedMinutes == 30)
    #expect(opening.title == "ανάγνωση")
    let day = parse("Αναφορά 20 λεπτά αύριο")
    #expect(day.estimatedMinutes == 20)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "Αναφορά")
    let time = parse("Αναφορά 30 λεπτά στις 3")
    #expect(time.estimatedMinutes == 30)
    #expect(time.startMinutes == 15 * 60)
  }

  @Test("An amount of time that names a moment, a bound, the past, or a rate, a size, and a single minute are no length")
  func notLengths() {
    expectLinesUnread(
      [
        "Αναφορά σε 30 λεπτά", "Αναφορά μετά από 2 ώρες", "Αναφορά μέσα σε 2 ώρες", "Αναφορά τουλάχιστον 2 ώρες",
        "Αναφορά το πολύ 2 ώρες", "Αναφορά κάθε 2 ώρες", "Αναφορά ανά 2 ώρες", "Αναφορά 30 λεπτά πριν",
        "Αναφορά 3 ώρες μετά", "Αναφορά 2 ώρες τη μέρα", "Αναφορά 2 ώρες την εβδομάδα", "Αναφορά 2 ώρες αργότερα",
        "Αναφορά 20 λεπτά ακόμα", "Αναφορά 2-3 ώρες", "Αναφορά 25 ώρες", "Αναφορά ένα λεπτό", "Αναφορά στις 3 ώρες",
        "Αναφορά ένα τέταρτο κιλό", "Αναφορά ένα κιλό", "Αναφορά μισό κιλό", "Αναφορά 5 ωράριο",
      ], languages: ["el"])
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, every other and every nth, and the cadence words")
  func repeats() {
    let rules: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Γυμναστική κάθε μέρα", daily), ("Γυμναστική κάθε ημέρα", daily), ("Γυμναστική κάθε εβδομάδα", weekly),
      ("Γυμναστική κάθε βδομάδα", weekly), ("Γυμναστική κάθε μήνα", monthly), ("Γυμναστική κάθε χρόνο", yearly),
      ("Γυμναστική κάθε έτος", yearly), ("Γυμναστική καθημερινά", daily), ("Γυμναστική εβδομαδιαία", weekly),
      ("Γυμναστική μηνιαία", monthly), ("Γυμναστική ετήσια", yearly), ("Γυμναστική ημερησίως", daily),
      ("Γυμναστική εβδομαδιαίως", weekly), ("Γυμναστική μηνιαίως", monthly), ("Γυμναστική ετησίως", yearly),
      ("Γυμναστική καθημερινώς", daily), ("Γυμναστική σε εβδομαδιαία βάση", weekly),
      ("Γυμναστική σε μηνιαία βάση", monthly), ("Γυμναστική σε καθημερινή βάση", daily),
      ("Γυμναστική κάθε δύο μέρες", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Γυμναστική κάθε 2 μέρες", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Γυμναστική κάθε τρεις μέρες", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Γυμναστική κάθε 2 εβδομάδες", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Γυμναστική κάθε τρεις εβδομάδες", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("Γυμναστική κάθε τρεις μήνες", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("Γυμναστική κάθε 6 μήνες", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("Γυμναστική κάθε 2 χρόνια", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("Γυμναστική κάθε δεύτερη μέρα", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Γυμναστική κάθε τρίτη μέρα", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("Γυμναστική κάθε δεύτερη εβδομάδα", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Γυμναστική κάθε τρίτη εβδομάδα", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("Γυμναστική κάθε δεύτερο μήνα", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("Γυμναστική μέρα παρά μέρα", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("Γυμναστική εβδομάδα παρά εβδομάδα", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Γυμναστική κάθε 14 μέρες", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("Γυμναστική κάθε 7 μέρες", weekly), ("Γυμναστική μία φορά την εβδομάδα", weekly),
      ("Γυμναστική μια φορά την εβδομάδα", weekly), ("Γυμναστική μία φορά τον μήνα", monthly),
      ("Γυμναστική κάθε πρωί", daily), ("Γυμναστική κάθε μεσημέρι", daily), ("Γυμναστική κάθε απόγευμα", daily),
      ("Γυμναστική κάθε βράδυ", daily), ("Γυμναστική ΚΑΘΕ ΜΕΡΑ", daily), ("Γυμναστική κάθε Μέρα", daily),
      ("Γυμναστική καθε μερα", daily),
    ]
    for line in rules {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "Γυμναστική", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // "Δύο φορές την εβδομάδα" counts times in a week, which no repeat says.
    expectLinesUnread(["Γυμναστική δύο φορές την εβδομάδα", "Γυμναστική τρεις φορές τον μήνα"], languages: ["el"])
    // The title keeps the text around the phrase.
    #expect(parse("Κάθε μέρα γυμναστική").recurrence == daily)
    #expect(parse("Κάθε μέρα γυμναστική").title == "γυμναστική")
    // A repeat with a time.
    let evening = parse("Γυμναστική κάθε βράδυ στις 8")
    #expect(evening.recurrence == daily)
    #expect(evening.startMinutes == 20 * 60)
    #expect(evening.title == "Γυμναστική")
    let morning = parse("Γυμναστική κάθε πρωί στις 7")
    #expect(morning.startMinutes == 7 * 60)
    #expect(parse("Γυμναστική κάθε μέρα στις 5").startMinutes == 17 * 60)
    let adverb = parse("Αναφορά εβδομαδιαία στις 9")
    #expect(adverb.recurrence == weekly)
    #expect(adverb.startMinutes == 9 * 60)
    #expect(adverb.title == "Αναφορά")
  }

  @Test("Weekday repeats: κάθε Δευτέρα, τις Δευτέρες, and the working days and the weekend")
  func weekdayRepeats() {
    let rules: [(text: String, rule: TaskRecurrenceRule)] = [
      ("Γυμναστική κάθε Δευτέρα", monday), ("Γυμναστική κάθε δευτέρα", monday), ("Γυμναστική ΚΑΘΕ ΔΕΥΤΕΡΑ", monday),
      ("Γυμναστική κάθε Τρίτη", TaskRecurrenceRule(freq: .weekly, byDay: ["TU"])),
      ("Γυμναστική κάθε Τετάρτη", TaskRecurrenceRule(freq: .weekly, byDay: ["WE"])),
      ("Γυμναστική κάθε Παρασκευή", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("Γυμναστική κάθε Κυριακή", TaskRecurrenceRule(freq: .weekly, byDay: ["SU"])),
      ("Γυμναστική κάθε εβδομάδα Παρασκευή", TaskRecurrenceRule(freq: .weekly, byDay: ["FR"])),
      ("Γυμναστική τις Δευτέρες", monday), ("Γυμναστική στις Δευτέρες", monday),
      ("Γυμναστική τα Σάββατα", TaskRecurrenceRule(freq: .weekly, byDay: ["SA"])),
      ("Γυμναστική τις Κυριακές", TaskRecurrenceRule(freq: .weekly, byDay: ["SU"])),
      ("Γυμναστική τις Τρίτες", TaskRecurrenceRule(freq: .weekly, byDay: ["TU"])),
      ("Γυμναστική τις Δευτέρες και Πέμπτες", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"])),
      ("Γυμναστική κάθε Δευτέρα και Πέμπτη", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"])),
      ("Γυμναστική κάθε Δευτέρα, Τετάρτη και Παρασκευή", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "WE", "FR"])),
      ("Γυμναστική κάθε Σάββατο και Κυριακή", weekend),
      ("Γυμναστική κάθε 2 εβδομάδες την Παρασκευή", TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR"])),
      ("Γυμναστική κάθε δεύτερη Παρασκευή", TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR"])),
      ("Γυμναστική κάθε δεύτερη Παρασκευή και Σάββατο", TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["FR", "SA"])),
      // The working days, the span of days, and the weekend.
      ("Γυμναστική τις καθημερινές", workdays), ("Γυμναστική στις καθημερινές", workdays),
      ("Γυμναστική τις καθημερινές μέρες", workdays), ("Γυμναστική τις εργάσιμες ημέρες", workdays),
      ("Γυμναστική κάθε εργάσιμη μέρα", workdays), ("Γυμναστική κάθε καθημερινή", workdays),
      ("Γυμναστική κάθε Δευτέρα έως Παρασκευή", workdays), ("Γυμναστική κάθε Δευτέρα-Παρασκευή", workdays),
      ("Γυμναστική κάθε Δευτέρα έως Πέμπτη", TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE", "TH"])),
      ("Γυμναστική τα Σαββατοκύριακα", weekend), ("Γυμναστική στα Σαββατοκύριακα", weekend),
      ("Γυμναστική κάθε Σαββατοκύριακο", weekend),
    ]
    for line in rules {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == "Γυμναστική", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The repeat starts on its first weekday: today is Tuesday.
    #expect(parse("Γυμναστική κάθε Δευτέρα").recurrenceStartOffset == 6)
    #expect(parse("Γυμναστική κάθε Παρασκευή").recurrenceStartOffset == 3)
    // The weekend starts on the first Saturday or Sunday after today, and the working days today.
    #expect(parse("Γυμναστική τα Σαββατοκύριακα").recurrenceStartOffset == 4)
    #expect(parse("Γυμναστική τις καθημερινές").recurrenceStartOffset == 0)
    // A single weekday with "κάθε" is a repeat, and with the article or alone a day.
    #expect(parse("Γυμναστική την Παρασκευή").recurrence == nil)
    #expect(parse("Γυμναστική την Παρασκευή").plannedDayOffset == 3)
    // A weekday repeat with a time.
    let timed = parse("Γυμναστική κάθε Δευτέρα στις 7 το πρωί")
    #expect(timed.recurrence == monday)
    #expect(timed.startMinutes == 7 * 60)
    #expect(timed.title == "Γυμναστική")
    // The weekday adjectives are words of the title when a noun follows them.
    expectLinesUnread(["Γυμναστική τις καθημερινές δουλειές", "Γυμναστική τις εργάσιμες ώρες"], languages: ["el"])
  }

  @Test("A day of the month repeats every month")
  func monthDayRepeats() {
    for (text, day) in [
      ("Ενοίκιο κάθε μήνα στις 15", 15), ("Ενοίκιο στις 15 κάθε μήνα", 15), ("Ενοίκιο στις 5 του κάθε μήνα", 5),
      ("Ενοίκιο κάθε 15 του μήνα", 15), ("Ενοίκιο κάθε 1η του μήνα", 1), ("Ενοίκιο κάθε πρώτη του μήνα", 1),
      ("Ενοίκιο κάθε μήνα την 15η", 15), ("Ενοίκιο κάθε μήνα στις 30", 30), ("Ενοίκιο κάθε 5 του μήνα", 5),
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [day]), "\(text)")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.title == "Ενοίκιο", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A time after "κάθε μήνα" is a time, and an amount after it is no day.
    let timed = parse("Ενοίκιο κάθε μήνα στις 15:30")
    #expect(timed.recurrence == monthly)
    #expect(timed.startMinutes == 15 * 60 + 30)
    let afternoon = parse("Ενοίκιο κάθε μήνα στις 3 το απόγευμα")
    #expect(afternoon.recurrence == monthly)
    #expect(afternoon.startMinutes == 15 * 60)
    let amount = parse("Ενοίκιο κάθε μήνα 15 ευρώ")
    #expect(amount.recurrence == monthly)
    #expect(amount.title == "Ενοίκιο 15 ευρώ")
    let counted = parse("Ενοίκιο κάθε μήνα στις 15 ευρώ")
    #expect(counted.recurrence == monthly)
    #expect(counted.startMinutes == nil)
    #expect(counted.title == "Ενοίκιο στις 15 ευρώ")
  }

  @Test("A cadence adjective is a repeat at the end of the line, before a colon, or with βάση, and a title elsewhere")
  func cadenceAdjectives() {
    expectLinesUnread(
      [
        "Εβδομαδιαία αναφορά", "Ετήσια άδεια", "Καθημερινά έξοδα", "Μηνιαία έξοδα", "Ημερήσια αναφορά",
        "Καθημερινή ρουτίνα", "Εβδομαδιαίο πρόγραμμα", "Σε καθημερινή χρήση", "Για κάθε μέρα", "Αναφορά για κάθε μέρα",
        "Αναφορά όπως κάθε μέρα", "Αναφορά σαν κάθε μέρα", "Κάθε τι", "Γυμναστική τις καθημερινές δουλειές",
      ], languages: ["el"])
    for (text, title, rule) in [
      ("Εβδομαδιαία: αναφορά", "αναφορά", weekly), ("Καθημερινά: νερό", "νερό", daily),
      ("Αναφορά εβδομαδιαία", "Αναφορά", weekly), ("Αναφορά εβδομαδιαία.", "Αναφορά.", weekly),
      ("Αναφορά σε μηνιαία βάση", "Αναφορά", monthly), ("Αναφορά ετήσια", "Αναφορά", yearly),
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.title == title, "\(text): title")
    }
  }

  // MARK: - Priorities

  @Test("Priorities: επείγον, σημαντικό, υψηλή προτεραιότητα, χαμηλή προτεραιότητα, and προτεραιότητα")
  func priorities() {
    for (text, title, priority) in [
      ("Αναφορά επείγον", "Αναφορά", LorvexTask.Priority.p1),
      ("Αναφορά επείγον.", "Αναφορά", .p1), ("Αναφορά ΕΠΕΙΓΟΝ", "Αναφορά", .p1),
      ("Αναφορά επείγουσα", "Αναφορά", .p1), ("Αναφορά σημαντικό", "Αναφορά", .p1),
      ("Αναφορά σημαντική", "Αναφορά", .p1), ("Αναφορά πολύ σημαντικό", "Αναφορά", .p1),
      ("Αναφορά πολύ επείγον", "Αναφορά", .p1), ("Επείγον: αναφορά", "αναφορά", .p1),
      ("Σημαντικό, αναφορά", "αναφορά", .p1), ("Αναφορά υψηλή προτεραιότητα", "Αναφορά", .p1),
      ("Αναφορά ΥΨΗΛΗ ΠΡΟΤΕΡΑΙΟΤΗΤΑ", "Αναφορά", .p1), ("Αναφορά υψηλής προτεραιότητας", "Αναφορά", .p1),
      ("Αναφορά μεσαία προτεραιότητα", "Αναφορά", .p2), ("Αναφορά κανονική προτεραιότητα", "Αναφορά", .p2),
      ("Αναφορά χαμηλή προτεραιότητα", "Αναφορά", .p3), ("Αναφορά χαμηλής προτεραιότητας", "Αναφορά", .p3),
      ("Αναφορά προτεραιότητα: υψηλή", "Αναφορά", .p1), ("Αναφορά προτεραιότητα: χαμηλή", "Αναφορά", .p3),
      ("Αναφορά προτεραιότητα: μεσαία", "Αναφορά", .p2), ("Αναφορά προτεραιότητα 1", "Αναφορά", .p1),
      ("Αναφορά προτεραιότητα 2", "Αναφορά", .p2), ("Αναφορά προτεραιότητα 3", "Αναφορά", .p3),
    ] {
      let parsed = parse(text)
      #expect(parsed.priority == priority, "\(text)")
      #expect(parsed.title == title, "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // An adjective that goes on to a noun, or a negation before it, is no priority.
    expectLinesUnread(
      [
        "Επείγον μήνυμα", "Σημαντική συνάντηση", "Αναφορά όχι επείγον", "Αναφορά δεν είναι σημαντικό",
        "Επείγοντα περιστατικά", "Αναφορά σημαντικό έργο", "Τμήμα επειγόντων", "Αναφορά μη επείγον",
      ], languages: ["el"])
  }

  // MARK: - Several details, ordinary words, spelling

  @Test("A line may carry every kind of detail at once")
  func everyKindAtOnce() {
    let line = parse("Τηλέφωνο στη μαμά αύριο στις 8 το βράδυ 30 λεπτά επείγον")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 20 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.priority == .p1)
    #expect(line.title == "Τηλέφωνο στη μαμά")
    let weekly = parse("Σχολική συνάντηση την Παρασκευή στις 7 το απόγευμα 1 ώρα κάθε εβδομάδα υψηλή προτεραιότητα")
    #expect(weekly.plannedDayOffset == 3)
    #expect(weekly.startMinutes == 19 * 60)
    #expect(weekly.estimatedMinutes == 60)
    #expect(weekly.recurrence == TaskRecurrenceRule(freq: .weekly))
    #expect(weekly.priority == .p1)
    #expect(weekly.title == "Σχολική συνάντηση")
    let report = parse("Αναφορά μέχρι την Παρασκευή σήμερα στις 3 μ.μ. 2 ώρες σημαντικό")
    #expect(report.dueDayOffset == 3)
    #expect(report.plannedDayOffset == 0)
    #expect(report.startMinutes == 15 * 60)
    #expect(report.estimatedMinutes == 120)
    #expect(report.priority == .p1)
    #expect(report.title == "Αναφορά")
    let commas = parse("Αναφορά αύριο, στις 9, επείγον")
    #expect(commas.plannedDayOffset == 1)
    #expect(commas.startMinutes == 9 * 60)
    #expect(commas.priority == .p1)
    #expect(commas.title == "Αναφορά")
    // The hash words stay as they are read for every language.
    let tagged = parse("Ραντεβού γιατρού #υγεία αύριο")
    #expect(tagged.plannedDayOffset == 1)
    #expect(tagged.tags == ["υγεία"])
    #expect(tagged.title == "Ραντεβού γιατρού")
  }

  @Test("Words that look like details stay in the title")
  func ordinaryWords() {
    expectLinesUnread(
      [
        "Ώρα για ύπνο", "Στις μέρες μας", "Στη δουλειά", "Στη μία μεριά", "Καθημερινά έξοδα", "Εβδομαδιαία αναφορά",
        "Ετήσια άδεια", "Επείγον μήνυμα", "Σημαντική συνάντηση", "Ένα κιλό μήλα", "Ένα τέταρτο κιλό ζάχαρη",
        "Μισό κιλό ψωμί", "Δύο φορές την εβδομάδα", "Κάθε τι", "Μάρτιος", "Μάιος και Ιούνιος", "Δώρο 15 Μαρία",
        "Δευτερόλεπτα", "Μαρία και Κυριακή", "Κυριακή Παπαδοπούλου", "Σήμερα-αύριο", "Η Παρασκευή Παπαδοπούλου",
        "Λεπτά πράγματα", "Ώρες λειτουργίας", "Αύριος", "Σημερινά νέα", "Μέρα νύχτα", "Νύχτα και μέρα",
        "Πρωινό γάλα", "Βραδινό φαγητό", "Απογευματινός καφές", "Εβδομαδιαίο μενού", "Προτεραιότητα", "Επείγοντα",
        "Παράδοση δεμάτων", "Η προθεσμία πέρασε",
      ], languages: ["el"])
  }

  @Test("Extra spaces and punctuation between details change nothing, and a hyphen joins a compound that is no day")
  func punctuationAndHyphens() {
    let line = parse("Συνάντηση  αύριο,  στις 3.")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 15 * 60)
    #expect(parse("Αύριο, συνάντηση").plannedDayOffset == 1)
    #expect(parse("Συνάντηση (αύριο)").plannedDayOffset == 1)
    expectLinesUnread(
      ["Αναφορά σήμερα-αύριο", "Αναφορά αύριο-μεθαύριο", "Παρασκευή-βράδυ δείπνο", "Αναφορά αύριοαύριο"],
      languages: ["el"])
  }

  @Test("Accents, capitals, and either sigma read alike, and the title keeps the letters it was typed with")
  func letterSpelling() {
    let days: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Οδοντίατρος αύριο", "Οδοντίατρος", { $0.plannedDayOffset == 1 }),
      ("Οδοντίατρος αύριο το βράδυ", "Οδοντίατρος", { $0.plannedDayOffset == 1 }),
      ("Οδοντίατρος σήμερα", "Οδοντίατρος", { $0.plannedDayOffset == 0 }),
      ("Οδοντίατρος απόψε", "Οδοντίατρος", { $0.plannedDayOffset == 0 }),
      ("Οδοντίατρος μεθαύριο", "Οδοντίατρος", { $0.plannedDayOffset == 2 }),
      ("Οδοντίατρος τη Δευτέρα", "Οδοντίατρος", { $0.plannedDayOffset == 6 }),
      ("Οδοντίατρος την Τρίτη", "Οδοντίατρος", { $0.plannedDayOffset == 7 }),
      ("Οδοντίατρος την Παρασκευή", "Οδοντίατρος", { $0.plannedDayOffset == 3 }),
      ("Οδοντίατρος το Σάββατο", "Οδοντίατρος", { $0.plannedDayOffset == 4 }),
      ("Οδοντίατρος την Κυριακή", "Οδοντίατρος", { $0.plannedDayOffset == 5 }),
      ("Οδοντίατρος την επόμενη Παρασκευή", "Οδοντίατρος", { $0.plannedDayOffset == 3 }),
      ("Οδοντίατρος την επόμενη εβδομάδα", "Οδοντίατρος", { $0.plannedDayOffset == 7 }),
      ("Οδοντίατρος σε 3 μέρες", "Οδοντίατρος", { $0.plannedDayOffset == 3 }),
      ("Οδοντίατρος σε δύο εβδομάδες", "Οδοντίατρος", { $0.plannedDayOffset == 14 }),
      ("Οδοντίατρος 15 Οκτωβρίου", "Οδοντίατρος", { $0.plannedDayOffset == 23 }),
      ("Οδοντίατρος 15 Αυγούστου", "Οδοντίατρος", { $0.plannedDayOffset == captureDayOffset("2027-08-15") }),
      ("Οδοντίατρος 3 Ιουνίου", "Οδοντίατρος", { $0.plannedDayOffset == captureDayOffset("2027-06-03") }),
      ("Αναφορά μέχρι την Παρασκευή", "Αναφορά", { $0.dueDayOffset == 3 }),
      ("Αναφορά ως αύριο", "Αναφορά", { $0.dueDayOffset == 1 }),
      ("Αναφορά προθεσμία Παρασκευή", "Αναφορά", { $0.dueDayOffset == 3 }),
      ("Αναφορά μέχρι τις 15 Οκτωβρίου", "Αναφορά", { $0.dueDayOffset == 23 }),
      ("Αναφορά Παρασκευή το αργότερο", "Αναφορά", { $0.dueDayOffset == 3 }),
      ("Διακοπές 3 Ιουνίου - 5 Ιουνίου", "Διακοπές", { $0.dueDayOffset == captureDayOffset("2027-06-05") }),
      ("Διακοπές από 3 έως 5 Ιουνίου", "Διακοπές", { $0.dueDayOffset == captureDayOffset("2027-06-05") }),
    ]
    let times: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Συνάντηση στις 3 το απόγευμα", "Συνάντηση", { $0.startMinutes == 15 * 60 }),
      ("Συνάντηση στις 9 το πρωί", "Συνάντηση", { $0.startMinutes == 9 * 60 }),
      ("Συνάντηση 8 βράδυ", "Συνάντηση", { $0.startMinutes == 20 * 60 }),
      ("Συνάντηση 3 μ.μ.", "Συνάντηση", { $0.startMinutes == 15 * 60 }),
      ("Συνάντηση στις 3 και μισή", "Συνάντηση", { $0.startMinutes == 15 * 60 + 30 }),
      ("Συνάντηση στις 4 παρά τέταρτο", "Συνάντηση", { $0.startMinutes == 15 * 60 + 45 }),
      ("Συνάντηση στις εννιάμισι", "Συνάντηση", { $0.startMinutes == 9 * 60 + 30 }),
      ("Συνάντηση στις δώδεκα", "Συνάντηση", { $0.startMinutes == 12 * 60 }),
      ("Συνάντηση στα μεσάνυχτα", "Συνάντηση", { $0.startMinutes == 0 && $0.plannedDayOffset == 1 }),
      ("Συνάντηση από τις 3 έως τις 5", "Συνάντηση", { $0.startMinutes == 15 * 60 && $0.estimatedMinutes == 120 }),
      ("Αναφορά 30 λεπτά", "Αναφορά", { $0.estimatedMinutes == 30 }),
      ("Αναφορά μισή ώρα", "Αναφορά", { $0.estimatedMinutes == 30 }),
      ("Αναφορά μιάμιση ώρα", "Αναφορά", { $0.estimatedMinutes == 90 }),
      ("Αναφορά δύο ώρες", "Αναφορά", { $0.estimatedMinutes == 120 }),
      ("Αναφορά υψηλή προτεραιότητα", "Αναφορά", { $0.priority == .p1 }),
      ("Αναφορά χαμηλή προτεραιότητα", "Αναφορά", { $0.priority == .p3 }),
      ("Αναφορά επείγον", "Αναφορά", { $0.priority == .p1 }),
    ]
    let repeats: [(text: String, title: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Γυμναστική κάθε μέρα", "Γυμναστική", { $0.recurrence == daily }),
      ("Γυμναστική κάθε Δευτέρα", "Γυμναστική", { $0.recurrence == monday }),
      ("Γυμναστική τις Δευτέρες", "Γυμναστική", { $0.recurrence == monday }),
      ("Γυμναστική τις καθημερινές", "Γυμναστική", { $0.recurrence == workdays }),
      ("Γυμναστική τα Σαββατοκύριακα", "Γυμναστική", { $0.recurrence == weekend }),
      ("Γυμναστική κάθε δύο εβδομάδες", "Γυμναστική", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2) }),
      ("Γυμναστική εβδομάδα παρά εβδομάδα", "Γυμναστική", { $0.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2) }),
      ("Γυμναστική κάθε χρόνο", "Γυμναστική", { $0.recurrence == yearly }),
      ("Γυμναστική καθημερινά", "Γυμναστική", { $0.recurrence == daily }),
      ("Ενοίκιο κάθε μήνα στις 15", "Ενοίκιο", { $0.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [15]) }),
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

  @Test("The final sigma and the medial sigma read alike, in every word a rule reads")
  func sigma() {
    let lines: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("Γυμναστική τις Δευτέρες", { $0.recurrence == monday }),
      ("Γυμναστική τις καθημερινές", { $0.recurrence == workdays }),
      ("Γυμναστική κάθε δύο μέρες", { $0.recurrence == TaskRecurrenceRule(freq: .daily, interval: 2) }),
      ("Γυμναστική κάθε τρεις μήνες", { $0.recurrence == TaskRecurrenceRule(freq: .monthly, interval: 3) }),
      ("Αναφορά 2 ώρες", { $0.estimatedMinutes == 120 }),
      ("Αναφορά ως αύριο", { $0.dueDayOffset == 1 }),
      ("Αναφορά έως Παρασκευή", { $0.dueDayOffset == 3 }),
      ("Συνάντηση στις 3", { $0.startMinutes == 15 * 60 }),
      ("Συνάντηση στις τρεις", { $0.startMinutes == 15 * 60 }),
      ("Διακοπές 3 Μαΐου - 5 Μαΐου", { $0.dueDayOffset == captureDayOffset("2027-05-05") }),
      ("Αναφορά σε δύο εβδομάδες", { $0.plannedDayOffset == 14 }),
    ]
    for line in lines {
      // The second form writes σ at the end of words, and the third writes ς inside them, which no one types
      // but a keyboard can; the reading form turns both into σ.
      let forms = [
        line.text, line.text.replacingOccurrences(of: "ς", with: "σ"), line.text.replacingOccurrences(of: "σ", with: "ς"),
      ]
      for typed in forms {
        #expect(line.check(parse(typed)), "\(typed)")
      }
    }
  }

  @Test("The reading form takes off accents and the final sigma and keeps every letter at its UTF-16 offset")
  func readingForm() {
    for (text, expected) in [
      ("αύριο", "αυριο"), ("ΑΎΡΙΟ", "ΑΥΡΙΟ"), ("Δευτέρα", "Δευτερα"), ("τις", "τισ"), ("μέχρι", "μεχρι"),
      ("ΐ", "ι"), ("ϊ", "ι"), ("ΰ", "υ"), ("Ώρες", "Ωρεσ"), ("15 Οκτωβρίου", "15 Οκτωβριου"), ("abc 123", "abc 123"),
    ] {
      let form = LorvexCaptureVocabulary.greekForMatching(text)
      #expect(form == expected, "\(text)")
      #expect(form.utf16.count == text.utf16.count, "\(text): length")
    }
    // A letter typed as a base letter and a combining mark stays as typed, so every other letter keeps its offset.
    let decomposed = "αυ\u{0301}ριο"
    #expect(LorvexCaptureVocabulary.greekForMatching(decomposed) == "αυ\u{0301}ριο")
    #expect(LorvexCaptureVocabulary.greekForMatching(decomposed).utf16.count == decomposed.utf16.count)
    for text in ["Αναφορά αύριο στις 3 μ.μ.", "ΣΗΜΕΡΑ ΑΎΡΙΟ ΜΕΘΑΎΡΙΟ", "κάθε Δευτέρα και Πέμπτη", "Ελένη 3-5 Μαΐου"] {
      #expect(LorvexCaptureVocabulary.greekForMatching(text).utf16.count == text.utf16.count, "\(text)")
    }
  }

  @Test("Every rule pattern is written in the reading form and compiles")
  func patternsAreInReadingForm() {
    LorvexCaptureParser.warmUp(languages: ["el"])
    let vocabulary = LorvexCaptureVocabulary.greek
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
    for pattern in patterns {
      #expect(
        LorvexCaptureVocabulary.greekForMatching(pattern) == pattern,
        "A pattern has an accent or a final sigma: \(pattern.prefix(60))")
      #expect(LorvexCapturePatterns.isCompiled(pattern), "\(pattern.prefix(60))")
    }
  }

  @Test("Letters typed as a base letter and a combining mark keep their form, and an accent inside a detail word is left unread")
  func decomposedLetters() {
    // An accent in a title word changes nothing: both forms read the same, and each keeps its own scalars.
    let lines: [(typed: String, title: String)] = [
      ("Αναφορά στις 15:00", "Αναφορά"), ("Γιορτή 15/10/2026", "Γιορτή"), ("Μάθημα στις 3 μ.μ.", "Μάθημα"),
      ("Ραντεβού στις 9 π.μ.", "Ραντεβού"), ("Καφές στις 15:30", "Καφές"), ("Γιορτή 15 Οκτ.", "Γιορτή"),
      ("Μάθημα 30 λ", "Μάθημα"), ("Ύπνος στις 22:00", "Ύπνος"), ("Ελένη στις 14.30", "Ελένη"),
      ("Μάθημα Δευ", "Μάθημα"),
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
      "Αναφορά αύριο", "Αναφορά τη Δευτέρα", "Αναφορά μέχρι την Παρασκευή", "Αναφορά 30 λεπτά", "Αναφορά 2 ώρες",
      "Γυμναστική κάθε μέρα", "Αναφορά επείγον", "Αναφορά 15 Οκτωβρίου", "Αναφορά υψηλή προτεραιότητα",
    ] {
      let composed = line.precomposedStringWithCanonicalMapping
      let decomposed = line.decomposedStringWithCanonicalMapping
      #expect(parse(composed).phrases.count == 1, "\(line)")
      let parsed = parse(decomposed)
      #expect(parsed.phrases.isEmpty, "\(line): phrases")
      #expect(scalars(parsed.title) == scalars(decomposed), "\(line): title")
    }
    // A decomposed letter in one word of a line leaves that word, and the other details still read.
    let partial = parse("Αναφορά αύριο στις 15:00".decomposedStringWithCanonicalMapping)
    #expect(partial.plannedDayOffset == nil)
    #expect(partial.startMinutes == 15 * 60)
    #expect(scalars(partial.title) == scalars("Αναφορά αύριο".decomposedStringWithCanonicalMapping))
  }

  // MARK: - Beside other languages

  @Test("Beside Greek, English lines read as they do alone, and an hour written with h stays a length")
  func besideEnglish() {
    // English lines read the same with Greek beside them as without it.
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
      for languages in [["en", "el"], ["el", "en"]] {
        #expect(parse(text, languages: languages) == parse(text, languages: ["en"]), "\(text) \(languages)")
      }
    }
    // Greek writes its hours with "στις" or "ώρα", so "15h" and "2h" are lengths beside it.
    let hours = parse("Write the report 2h", languages: ["en", "el"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    let clock = parse("Meet at 15h", languages: ["en", "el"])
    #expect(clock.estimatedMinutes == 15 * 60)
    #expect(clock.startMinutes == nil)
    // A line may mix both languages.
    let mixed = parse("Call mom αύριο at 3pm", languages: ["en", "el"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting την Παρασκευή at 3pm", languages: ["en", "el"])
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    #expect(parse("Dentist tomorrow", languages: ["en", "el"]).plannedDayOffset == 1)
    let review = parse("Review αύριο στις 15:00 for 2 hours", languages: ["en", "el"])
    #expect(review.plannedDayOffset == 1)
    #expect(review.startMinutes == 15 * 60)
    #expect(review.estimatedMinutes == 120)
    let english = parse("Αναφορά αύριο 3pm")
    #expect(english.plannedDayOffset == 1)
    #expect(english.startMinutes == 15 * 60)
    #expect(english.title == "Αναφορά")
    #expect(parse("Αναφορά 30 min").estimatedMinutes == 30)
    #expect(parse("Αναφορά αύριο 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("17:30 αναφορά").startMinutes == 17 * 60 + 30)
    #expect(parse("αναφορά 3pm").startMinutes == 15 * 60)
    #expect(parse("Αναφορά tomorrow").plannedDayOffset == 1)
    #expect(parse("Αναφορά every Monday").recurrence == monday)
    #expect(parse("Αναφορά by friday").dueDayOffset == 3)
  }

  @Test("Lines in other languages read the same with Greek beside them")
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
      ("להתקשר לאמא מחר בשעה 5", "he"), ("דוח עד יום שישי", "he"), ("אימון כל יום שני", "he"),
      ("明日の午後3時に会議", "ja"), ("毎週月曜日にジム", "ja"), ("내일 오후 3시에 회의", "ko"),
      ("매주 월요일 운동", "ko"), ("明天下午3点开会", "zh"), ("每周一健身", "zh"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "el"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["el", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Greek with another language.
    for languages in [["fr", "el"], ["el", "fr"]] {
      let mixed = parse("Appeler maman αύριο στις 3", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(mixed.title == "Appeler maman", "\(languages)")
      #expect(parse("Appeler maman demain à 15h", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("Dentiste 3 mai", languages: languages).plannedDayOffset == captureDayOffset("2027-05-03"), "\(languages)")
      #expect(parse("Γυμναστική κάθε Δευτέρα", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Rapport urgent", languages: languages).priority == .p1, "\(languages)")
      expectDateRanges(
        [
          ("Vacances", "du 3 au 5 mai", "2027-05-03", "2027-05-05"),
          ("Διακοπές", "3-5 Μαΐου", "2027-05-03", "2027-05-05"),
        ], languages: languages)
    }
    #expect(parse("Συνάντηση 下午3点 αύριο", languages: ["zh", "el"]).plannedDayOffset == 1)
    #expect(parse("Συνάντηση מחר", languages: ["he", "el"]).plannedDayOffset == 1)
    #expect(parse("Συνάντηση jutro", languages: ["pl", "el"]).plannedDayOffset == 1)
    // The languages that go beside Greek keep their own words, which are Greek's too only in a different script.
    for languages in [["nl", "el"], ["el", "nl"], ["de", "el"], ["el", "de"], ["tr", "el"], ["el", "tr"]] {
      #expect(parse("Συνάντηση αύριο στις 3", languages: languages).startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Γυμναστική κάθε Δευτέρα", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Tandarts overmorgen", languages: languages).plannedDayOffset == (languages.contains("nl") ? 2 : nil), "\(languages)")
      #expect(parse("Zahnarzt übermorgen", languages: languages).plannedDayOffset == (languages.contains("de") ? 2 : nil), "\(languages)")
      #expect(parse("Diş doktoru yarın", languages: languages).plannedDayOffset == (languages.contains("tr") ? 1 : nil), "\(languages)")
    }
  }

  @Test("Greek words are read only for a user who reads Greek")
  func languageGate() {
    let line = parse("Οδοντίατρος αύριο", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "Οδοντίατρος αύριο")
    for languages in [["el"], ["el-GR"], ["el_CY"], ["el-CY"], ["en-US", "el-GR"], ["EL"]] {
      #expect(parse("Οδοντίατρος αύριο", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Words of the other languages written in Latin letters are not read for a Greek reader.
    expectLinesUnread(
      [
        "Appeler maman demain", "Llamar mañana", "Zadzwonić jutro", "Chiamare domani", "Ligar amanhã",
        "Zahnarzt übermorgen", "Tandarts overmorgen", "Dentist poimâine", "Rapat besok", "Diş doktoru yarın",
      ], languages: ["el"])
    // Greek words are not read for a reader of another language.
    for languages in [
      ["fr"], ["es"], ["pl"], ["it"], ["pt"], ["he"], ["ru"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"], ["tr"],
    ] {
      let parsed = parse("Οδοντίατρος αύριο", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "Οδοντίατρος αύριο", "\(languages): title")
      #expect(parse("Συνάντηση στις 3 το απόγευμα", languages: languages).startMinutes == nil, "\(languages): time")
      #expect(parse("Γυμναστική κάθε Δευτέρα", languages: languages).recurrence == nil, "\(languages): repeat")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["el"])
    let unit: [String] = [
      "στις 15:00 ", "στις 3 ", "στις ", "3 ", "αύριο ", "αύριο το βράδυ ", "Παρασκευή ", "την Παρασκευή ",
      "την επόμενη Παρασκευή ", "Δευτέρα ", "Τρίτη ", "15 Οκτωβρίου ", "15.10.2026 ", "15/10 ", "3-5 Μαΐου ",
      "από 3 έως 5 Μαΐου ", "μέχρι την Παρασκευή ", "μέχρι ", "προθεσμία Παρασκευή ", "το αργότερο ", "κάθε μέρα ",
      "κάθε Δευτέρα ", "κάθε Δευτέρα και Πέμπτη ", "τις Δευτέρες ", "κάθε δεύτερη ", "κάθε 2 εβδομάδες ",
      "τις καθημερινές ", "κάθε μήνα στις 15 ", "στις 3 και μισή ", "στις 4 παρά τέταρτο ", "τρεις και μισή ",
      "30 λεπτά ", "30 λ ", "1,5 ώρα ", "μισή ώρα ", "για 2 ώρες ", "επείγον ", "υψηλή προτεραιότητα ",
      "προτεραιότητα: ", "Παρασκευή-Κυριακή ", "από Παρασκευή έως Κυριακή ", "στις 14-16 ", "από τις 3 έως τις 5 ",
      "3 μ.μ. ", "9 π.μ. ", "τα μεσάνυχτα ", "στις 12 τα μεσάνυχτα ", "χθες ", "την περασμένη Παρασκευή ",
      "Μεγάλη Παρασκευή ", "κάθε πρώτη Δευτέρα του μήνα ", "με ", "και ", "στη ", "το ", "την ", "της ", ", ", ".", "-",
      "ς", "σ", "ά", "α\u{0301}", "ι\u{0308}", "'", "παρά ", "από ", "έως ",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "Αλέξης " + String(repeating: token, count: count) + " Τηλέφωνο"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(5), "\(token) took \(elapsed)")
    }
    // A line past the read limit is a title and nothing more, at once.
    let past = String(repeating: "αύριο στις 3 ", count: 500).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    #expect(slowest < .seconds(5), "the slowest long line took \(slowest)")
    // The first phrase of a long line still reads.
    let first = parse("αύριο " + String(repeating: "στις 3 αύριο ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 15 * 60)
  }
}
