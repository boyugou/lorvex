import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["hi"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["hi"])
}

/// `text` with its ASCII digits written in the Devanagari script (U+0966-U+096F).
private func devanagariDigits(_ text: String) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in text.unicodeScalars {
    if (0x30...0x39).contains(scalar.value), let digit = Unicode.Scalar(0x0966 + scalar.value - 0x30) {
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

/// Hindi capture lines, read for a user whose languages include Hindi.
@Suite("Capture parser Hindi")
struct CaptureParserHindiTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("माँ को फोन करें कल")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "माँ को फोन करें")
    #expect(line.phrases.map(\.text) == ["कल"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("फोन करें आज", 0), ("फोन करें आज से", 0), ("फोन करें कल", 1), ("फोन करें कल को", 1),
      ("फोन करें कल से", 1), ("फोन करें परसों", 2), ("फोन करें परसो", 2),
      ("फोन करें 3 दिन बाद", 3), ("फोन करें 3 दिनों बाद", 3), ("फोन करें तीन दिन बाद", 3),
      ("फोन करें ३ दिन बाद", 3), ("फोन करें 1 दिन बाद", 1), ("फोन करें एक दिन बाद", 1),
      ("फोन करें 10 दिन बाद", 10), ("फोन करें पंद्रह दिन बाद", 15),
      ("फोन करें 2 हफ़्ते बाद", 14), ("फोन करें दो हफ़्ते बाद", 14), ("फोन करें एक हफ़्ते बाद", 7),
      ("फोन करें 3 सप्ताह बाद", 21), ("फोन करें 1 महीने बाद", 30), ("फोन करें 2 महीने बाद", 61),
      ("फोन करें अगले हफ़्ते", 7), ("फोन करें अगले हफ्ते", 7), ("फोन करें अगले सप्ताह", 7),
      ("फोन करें आने वाले हफ़्ते", 7), ("फोन करें अगले हफ़्ते में", 7),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "फोन करें", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("कल माँ को फोन करें")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "माँ को फोन करें")
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("आज सुबह", 0), ("आज दोपहर", 0), ("आज शाम", 0), ("आज रात", 0), ("आज की रात", 0), ("कल सुबह", 1),
      ("कल दोपहर", 1), ("कल शाम", 1), ("कल रात", 1), ("कल देर रात", 1), ("कल तड़के", 1), ("परसों शाम", 2),
      ("शुक्रवार शाम", 3), ("शुक्रवार की शाम", 3), ("शनिवार सुबह", 4),
    ]
    for phrase in phrases {
      let parsed = parse("फोन करें \(phrase.text)")
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "फोन करें", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("कल सुबह मीटिंग 6 बजे")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "मीटिंग")
    let evening = parse("आज शाम को जिम 7 बजे")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "जिम")
    let night = parse("कल रात खाना 9 बजे")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 21 * 60)
    #expect(night.title == "खाना")
    let written = parse("आज रात 8 बजे खाना")
    #expect(written.plannedDayOffset == 0)
    #expect(written.startMinutes == 20 * 60)
    #expect(written.title == "खाना")
    // The part of the day as a noun names no day.
    expectLinesUnread(
      ["सुबह की सैर", "शाम की चाय", "रात का खाना", "दोपहर का खाना", "सुबह जल्दी उठना", "रात को पढ़ना"], languages: ["hi"])
    // A possessive after the part of the day makes it an attribute of a noun:
    // only the day is read.
    let dinner = parse("कल रात का खाना")
    #expect(dinner.plannedDayOffset == 1)
    #expect(dinner.title == "रात का खाना")
    let tea = parse("कल शाम की चाय")
    #expect(tea.plannedDayOffset == 1)
    #expect(tea.title == "शाम की चाय")
  }

  @Test("The emphatic ही after a day, its postposition, or a deadline word goes with it")
  func dayParticle() {
    let days: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("आज ही रिपोर्ट भेजना", "रिपोर्ट भेजना", 0, "आज ही"),
      ("रिपोर्ट आज ही भेजना", "रिपोर्ट भेजना", 0, "आज ही"),
      ("रिपोर्ट आज ही", "रिपोर्ट", 0, "आज ही"),
      ("कल ही जाना है", "जाना है", 1, "कल ही"),
      ("सोमवार को ही मीटिंग", "मीटिंग", 6, "सोमवार को ही"),
      ("कल से ही जिम शुरू करना", "जिम शुरू करना", 1, "कल से ही"),
      ("3 दिन बाद ही मिलना", "मिलना", 3, "3 दिन बाद ही"),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    let due: [(text: String, title: String, offset: Int)] = [
      ("फोन करें शुक्रवार तक ही", "फोन करें", 3),
      ("रिपोर्ट शुक्रवार तक ही भेजना", "रिपोर्ट भेजना", 3),
      ("रिपोर्ट शुक्रवार से पहले ही भेजना", "रिपोर्ट भेजना", 3),
      ("रिपोर्ट 5 मई तक ही भेजना", "रिपोर्ट भेजना", captureDayOffset("2027-05-05")),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A possessive after the particle makes the day an attribute of a noun, and
    // "आज तक ही" is the idiom for "so far".
    expectLinesUnread(
      ["आज ही की रिपोर्ट", "रिपोर्ट शुक्रवार तक ही की बात", "रिपोर्ट आज तक ही"], languages: ["hi"])
  }

  @Test("दोपहर बाद after a day is the afternoon, and बाद after any other part, or before a possessive, is not")
  func afternoonAfter() {
    let afternoons: [(text: String, offset: Int, phrase: String)] = [
      ("कल दोपहर बाद मीटिंग", 1, "कल दोपहर बाद"), ("कल दोपहर के बाद मीटिंग", 1, "कल दोपहर के बाद"),
      ("शुक्रवार दोपहर बाद मीटिंग", 3, "शुक्रवार दोपहर बाद"), ("मीटिंग कल दोपहर बाद", 1, "कल दोपहर बाद"),
    ]
    for line in afternoons {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == "मीटिंग", "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    let hour = parse("आज दोपहर बाद 3 बजे जिम")
    #expect(hour.plannedDayOffset == 0)
    #expect(hour.startMinutes == 15 * 60)
    #expect(hour.title == "जिम")
    // Only the day is read; the words after it stay in the title.
    let phrases: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("कल शाम के बाद फोन करना", "शाम के बाद फोन करना", 1, "कल"),
      ("कल सुबह के बाद मीटिंग", "सुबह के बाद मीटिंग", 1, "कल"),
      ("आज रात के बाद फोन", "रात के बाद फोन", 0, "आज"),
      ("कल दोपहर बाद की मीटिंग", "दोपहर बाद की मीटिंग", 1, "कल"),
      ("कल दोपहर के बाद का खाना", "दोपहर के बाद का खाना", 1, "कल"),
    ]
    for line in phrases {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // A day and a part of the day alone are no task.
    expectLinesUnread(["कल दोपहर बाद", "शुक्रवार दोपहर बाद", "आज दोपहर"], languages: ["hi"])
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "इस मंगलवार" is today.
    let names: [(name: String, offset: Int)] = [
      ("बुधवार", 1), ("गुरुवार", 2), ("गुरूवार", 2), ("बृहस्पतिवार", 2), ("वीरवार", 2), ("शुक्रवार", 3),
      ("शनिवार", 4), ("रविवार", 5), ("इतवार", 5), ("सोमवार", 6), ("मंगलवार", 7),
    ]
    for weekday in names {
      for text in ["फोन करें \(weekday.name)", "फोन करें \(weekday.name) को"] {
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "फोन करें", "\(text): title")
      }
    }
    let modified: [(text: String, offset: Int)] = [
      ("फोन करें इस शुक्रवार", 3), ("फोन करें इस मंगलवार", 0), ("फोन करें इस शनिवार को", 4),
      ("फोन करें इस सोमवार", 6), ("फोन करें अगले सोमवार", 6), ("फोन करें अगला सोमवार", 6),
      ("फोन करें अगले मंगलवार", 7), ("फोन करें अगले शुक्रवार", 10), ("फोन करें अगले शनिवार", 11),
      ("फोन करें अगले रविवार", 12), ("फोन करें आने वाले शुक्रवार को", 3), ("फोन करें आने वाले मंगलवार", 7),
      ("फोन करें आगामी शुक्रवार", 3), ("फोन करें इस हफ़्ते शुक्रवार", 3), ("फोन करें अगले हफ़्ते सोमवार", 6),
      // "के लिए" is a purpose, not a possessive, so the day is read with it.
      ("फोन करें शुक्रवार के लिए", 3), ("फोन करें अगले शुक्रवार के लिए", 10),
    ]
    for line in modified {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text)")
      #expect(parsed.title == "फोन करें", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let opening = parse("शुक्रवार को माँ को फोन करें")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "माँ को फोन करें")
    // "इस हफ़्ते" alone names no single day.
    expectLinesUnread(["फोन करें इस हफ़्ते"], languages: ["hi"])
  }

  @Test("The weekend: this one, next week's, and today when it is already here")
  func weekend() {
    for text in [
      "वीकेंड", "वीकेंड पर", "इस वीकेंड", "वीकएंड", "वीक एंड", "वीकेन्ड", "सप्ताहांत", "सप्ताहांत में", "इस सप्ताहांत",
      "हफ़्ते के अंत में",
    ] {
      let parsed = parse("फोन करें \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "फोन करें", "\(text): title")
    }
    for text in ["अगले वीकेंड", "अगले सप्ताहांत"] {
      #expect(parse("फोन करें \(text)").plannedDayOffset == 11, "\(text)")
    }
    // On a Saturday or a Sunday the weekend is already here.
    #expect(parse("फोन करें वीकेंड", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("फोन करें वीकेंड", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("फोन करें वीकेंड", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("फोन करें अगले वीकेंड", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
  }

  @Test("Written dates: every month, in the spellings people type, with a year, a label, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("5 जनवरी", "2027-01-05"), ("5 फ़रवरी", "2027-02-05"), ("5 फरवरी", "2027-02-05"),
      ("5 मार्च", "2027-03-05"), ("5 अप्रैल", "2027-04-05"), ("5 अप्रेल", "2027-04-05"), ("5 मई", "2027-05-05"),
      ("5 जून", "2027-06-05"), ("5 जुलाई", "2027-07-05"), ("5 अगस्त", "2027-08-05"),
      ("5 सितंबर", "2027-09-05"), ("5 सितम्बर", "2027-09-05"), ("5 अक्टूबर", "2026-10-05"),
      ("5 अक्तूबर", "2026-10-05"), ("5 नवंबर", "2026-11-05"), ("5 नवम्बर", "2026-11-05"),
      ("5 दिसंबर", "2026-12-05"), ("5 दिसम्बर", "2026-12-05"), ("22 सितंबर", "2026-09-22"),
      ("५ मई", "2027-05-05"), ("5 मई को", "2027-05-05"), ("5 मई 2027", "2027-05-05"),
      ("5 मई 2028", "2028-05-05"), ("5 मई, 2028", "2028-05-05"), ("तारीख 5 मई", "2027-05-05"),
      ("दिनांक: 5 मई", "2027-05-05"), ("सोमवार, 5 अक्टूबर", "2026-10-05"), ("1 जनवरी 2027", "2027-01-01"),
    ]
    for line in dates {
      let text = "माँ को फोन करें \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "माँ को फोन करें", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
  }

  @Test("A month needs its day before it, and a date in digits, the Hindi calendar, or a day the month lacks is no date")
  func unreadDates() {
    expectLinesUnread(
      [
        // The Vikram Samvat months are not Gregorian dates.
        "फोन करें 5 चैत्र", "त्योहार 5 कार्तिक", "पूजा 5 आषाढ़",
        // A month alone, a month before its day, and a day of the month alone.
        "छुट्टी मई में", "फोन करें मई 5", "फोन करें सितम्बर 5", "किराया 5 तारीख को",
        // Digits only, and a day the month does not have.
        "फोन करें 5/10", "फोन करें 31 अप्रैल", "फोन करें 30 फ़रवरी", "फोन करें 32 मई",
      ], languages: ["hi"])
    // A name that looks like a month is left alone beside a date.
    let name = parse("मई का जन्मदिन 5 मई")
    #expect(name.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(name.title == "मई का जन्मदिन")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("छुट्टी", "3 से 5 मार्च", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 से 5 मार्च तक", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 मार्च से 5 मार्च तक", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 मार्च से 5 मार्च", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "30 जनवरी से 2 फ़रवरी तक", "2027-01-30", "2027-02-02"),
        ("छुट्टी", "3-5 मार्च", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3–5 मार्च", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 मार्च - 5 मार्च", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 से 5 मार्च 2027", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 से लेकर 5 मार्च तक", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 से 5 मार्च के बीच", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "3 से 5 मार्च के दौरान", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "३ से ५ मार्च", "2027-03-03", "2027-03-05"),
        ("परिवार के साथ छुट्टी", "3 से 5 मार्च", "2027-03-03", "2027-03-05"),
        ("छुट्टी", "25 सितंबर से 3 अक्टूबर तक", "2026-09-25", "2026-10-03"),
        ("छुट्टी", "30 दिसंबर से 2 जनवरी तक", "2026-12-30", "2027-01-02"),
        ("सम्मेलन", "12-14 अक्टूबर", "2026-10-12", "2026-10-14"),
      ], languages: ["hi"])
  }

  @Test("A range whose end is not after its start, or that names no month, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "छुट्टी 5 से 3 मार्च", "छुट्टी 3 मार्च से 3 मार्च तक", "छुट्टी 5-3 मार्च", "छुट्टी 5 मार्च से 3 मार्च तक",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "छुट्टी 3 से 5",
        // A range in the past, or one that a possessive follows, may be an event
        // the task only prepares for.
        "3 से 5 मार्च तक छुट्टी थी", "5 से 8 मई तक की छुट्टी", "5 से 8 मई की छुट्टी",
      ], languages: ["hi"])
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 मार्च")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("Sprint", "12-20 मार्च", "2027-03-12", "2027-03-20")], languages: ["hi"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("छुट्टी 3 से 5 मार्च कल")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "छुट्टी कल")
    let timed = parse("छुट्टी 3 से 5 मार्च शाम 6 बजे")
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "छुट्टी")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("रिपोर्ट सोमवार से बुधवार तक")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "रिपोर्ट")
    #expect(span.phrases.map(\.text) == ["सोमवार से बुधवार तक"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("यात्रा शुक्रवार से सोमवार", 3, 6), ("यात्रा शनिवार से रविवार", 4, 5),
      ("यात्रा शुक्रवार से रविवार तक", 3, 5), ("यात्रा शुक्रवार से लेकर रविवार तक", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("शिविर मंगलवार से गुरुवार", 7, 9), ("शिविर बुधवार से शुक्रवार के बीच", 1, 3),
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
      ["जिम सोमवार से शुक्रवार", "ट्रेनिंग सोमवार से शुक्रवार तक", "ट्रेनिंग सोमवार से शुक्रवार तक की", "सोमवार से शुक्रवार तक की ट्रेनिंग"],
      languages: ["hi"])
    // A span in the past, or one that a possessive follows, is no plan.
    expectLinesUnread(["सोमवार से बुधवार तक की छुट्टी", "सोमवार से बुधवार तक छुट्टी थी"], languages: ["hi"])
  }

  // MARK: - Due days

  @Test("Due days: तक, से पहले, अंतिम तिथि, and डेडलाइन")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("रिपोर्ट भेजें शुक्रवार तक", "रिपोर्ट भेजें", 3),
      ("रिपोर्ट भेजें शुक्रवार से पहले", "रिपोर्ट भेजें", 3),
      ("रिपोर्ट भेजें शुक्रवार के पहले", "रिपोर्ट भेजें", 3),
      ("रिपोर्ट भेजें मंगलवार तक", "रिपोर्ट भेजें", 7),
      ("रिपोर्ट भेजें अगले शुक्रवार तक", "रिपोर्ट भेजें", 10),
      ("रिपोर्ट भेजें इस शुक्रवार तक", "रिपोर्ट भेजें", 3),
      ("रिपोर्ट भेजें कल तक", "रिपोर्ट भेजें", 1),
      ("रिपोर्ट भेजें परसों तक", "रिपोर्ट भेजें", 2),
      ("रिपोर्ट भेजें कल शाम से पहले", "रिपोर्ट भेजें", 1),
      ("रिपोर्ट भेजें आज शाम तक", "रिपोर्ट भेजें", 0),
      ("रिपोर्ट भेजें आज रात तक", "रिपोर्ट भेजें", 0),
      ("कल सुबह तक रिपोर्ट भेजें", "रिपोर्ट भेजें", 1),
      ("रिपोर्ट भेजें 5 मई तक", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("रिपोर्ट भेजें 5 मई से पहले", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("रिपोर्ट भेजें अंतिम तिथि 5 मई", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("रिपोर्ट भेजें अंतिम तिथि: 5 मई", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("अंतिम तिथि: 5 मई रिपोर्ट भेजें", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("रिपोर्ट भेजें आखिरी तारीख 5 मई", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("रिपोर्ट भेजें नियत तिथि 5 मई", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("रिपोर्ट भेजें अंतिम तिथि: शुक्रवार", "रिपोर्ट भेजें", 3),
      ("रिपोर्ट भेजें डेडलाइन: 5 मई", "रिपोर्ट भेजें", captureDayOffset("2027-05-05")),
      ("डेडलाइन शुक्रवार रिपोर्ट भेजें", "रिपोर्ट भेजें", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("रिपोर्ट भेजें शुक्रवार तक कल")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "रिपोर्ट भेजें")
  }

  @Test("\"आज तक\" and \"आज से पहले\" are idioms, and a deadline that a possessive follows is no deadline")
  func notDueDays() {
    expectLinesUnread(
      [
        "रिपोर्ट आज तक", "रिपोर्ट आज से पहले", "रिपोर्ट शुक्रवार तक की", "रिपोर्ट शुक्रवार तक की मीटिंग",
        "शुक्रवार तक की रिपोर्ट",
      ], languages: ["hi"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "रिपोर्ट भेजें 5 बजे तक", "रिपोर्ट भेजें शाम 5 बजे से पहले", "रिपोर्ट भेजें 18:00 तक",
        "रिपोर्ट भेजें 5 बजे के बाद", "रिपोर्ट भेजें 5 बजे के बीच", "रिपोर्ट भेजें 3 और 5 बजे के बीच",
        "रिपोर्ट भेजें 5 बजे के दौरान", "रिपोर्ट भेजें 5:30 बजे तक", "रिपोर्ट भेजें साढ़े 5 बजे तक",
        "रिपोर्ट भेजें पाँच बजे तक", "रिपोर्ट भेजें आधी रात तक", "रिपोर्ट भेजें 5 बजकर 30 मिनट",
      ], languages: ["hi"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("रिपोर्ट भेजें शुक्रवार शाम 5 बजे तक")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "रिपोर्ट भेजें शाम 5 बजे तक")
    let tomorrow = parse("रिपोर्ट भेजें कल 5 बजे तक")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "रिपोर्ट भेजें 5 बजे तक")
    // A planned day beside the clock deadline reads, and the clock stays.
    let day = parse("रिपोर्ट भेजें 5 बजे तक कल")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    #expect(day.title == "रिपोर्ट भेजें 5 बजे तक")
    // A time range that ends in "तक" is still a range.
    let range = parse("मीटिंग 2 बजे से 4 बजे तक")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "मीटिंग")
    // Without Hindi, English reads the clock time and leaves the word.
    let english = parse("रिपोर्ट भेजें 18:00 तक", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "रिपोर्ट भेजें तक")
  }

  // MARK: - Times

  @Test("Clock times: बजे after the hour, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("मीटिंग 5 बजे", "मीटिंग", 17 * 60), ("मीटिंग 5बजे", "मीटिंग", 17 * 60),
      ("मीटिंग 5:30 बजे", "मीटिंग", 17 * 60 + 30), ("मीटिंग 5.30 बजे", "मीटिंग", 17 * 60 + 30),
      ("मीटिंग ५ बजे", "मीटिंग", 17 * 60), ("मीटिंग ठीक 5 बजे", "मीटिंग", 17 * 60),
      ("मीटिंग करीब 5 बजे", "मीटिंग", 17 * 60), ("मीटिंग लगभग 5 बजे", "मीटिंग", 17 * 60),
      ("मीटिंग 5 बजे पर", "मीटिंग", 17 * 60), ("मीटिंग 5 बजे से", "मीटिंग", 17 * 60),
      ("मीटिंग 5 बजे के लिए", "मीटिंग", 17 * 60), ("मीटिंग 5 बजे के आसपास", "मीटिंग", 17 * 60),
      ("5 बजे की मीटिंग", "मीटिंग", 17 * 60), ("5 बजे का खाना", "खाना", 17 * 60),
      ("शाम 5 बजे की फ्लाइट", "फ्लाइट", 17 * 60),
      ("मीटिंग सुबह 9 बजे", "मीटिंग", 9 * 60), ("मीटिंग सुबह 9:30 बजे", "मीटिंग", 9 * 60 + 30),
      ("मीटिंग सवेरे 6 बजे", "मीटिंग", 6 * 60), ("मीटिंग तड़के 4 बजे", "मीटिंग", 4 * 60),
      ("मीटिंग दोपहर 12 बजे", "मीटिंग", 12 * 60), ("मीटिंग दोपहर 1 बजे", "मीटिंग", 13 * 60),
      ("मीटिंग दोपहर 2 बजे", "मीटिंग", 14 * 60), ("मीटिंग शाम को 5 बजे", "मीटिंग", 17 * 60),
      ("मीटिंग शाम 7 बजे", "मीटिंग", 19 * 60), ("मीटिंग रात के 10 बजे", "मीटिंग", 22 * 60),
      ("मीटिंग रात 9 बजे", "मीटिंग", 21 * 60), ("मीटिंग रात 11 बजे", "मीटिंग", 23 * 60),
      ("मीटिंग 9 बजे सुबह", "मीटिंग", 9 * 60), ("मीटिंग 5 बजे सुबह", "मीटिंग", 5 * 60),
      ("मीटिंग 7 बजे शाम", "मीटिंग", 19 * 60), ("मीटिंग 7 बजे शाम को", "मीटिंग", 19 * 60),
      ("मीटिंग 10 बजे रात", "मीटिंग", 22 * 60), ("मीटिंग 2 बजे दोपहर", "मीटिंग", 14 * 60),
      ("मीटिंग 17:30", "मीटिंग", 17 * 60 + 30), ("मीटिंग शाम 5:30", "मीटिंग", 17 * 60 + 30),
      ("मीटिंग रात 10.30", "मीटिंग", 22 * 60 + 30),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day after बजे that a possessive follows belongs to the
    // title: it is the evening's tea, not the hour's part of the day.
    let tea = parse("मीटिंग 5 बजे शाम की चाय")
    #expect(tea.startMinutes == 17 * 60)
    #expect(tea.title == "मीटिंग शाम की चाय")
    // A part of the day on both sides of the hour contradicts itself.
    #expect(parse("मीटिंग सुबह 9 बजे शाम").startMinutes == nil)
    // Twelve in the morning is no time, and neither is 24 o'clock.
    #expect(parse("मीटिंग सुबह 12 बजे").startMinutes == nil)
    #expect(parse("मीटिंग 24 बजे").startMinutes == nil)
  }

  @Test("Clock fractions: साढ़े, सवा, पौने, डेढ़, and ढाई")
  func clockFractions() {
    let fractions: [(text: String, minutes: Int)] = [
      ("मीटिंग साढ़े 5 बजे", 17 * 60 + 30), ("मीटिंग साढे 5 बजे", 17 * 60 + 30),
      ("मीटिंग साढ़े पाँच बजे", 17 * 60 + 30), ("मीटिंग सवा 5 बजे", 17 * 60 + 15),
      ("मीटिंग पौने 6 बजे", 17 * 60 + 45), ("मीटिंग डेढ़ बजे", 13 * 60 + 30), ("मीटिंग डेढ बजे", 13 * 60 + 30),
      ("मीटिंग ढाई बजे", 14 * 60 + 30), ("मीटिंग साढ़े तीन बजे", 15 * 60 + 30),
      ("मीटिंग सवा दो बजे", 14 * 60 + 15), ("मीटिंग पौने चार बजे", 15 * 60 + 45),
      ("मीटिंग पौने एक बजे", 12 * 60 + 45), ("मीटिंग पौने बारह बजे", 11 * 60 + 45),
      ("मीटिंग सुबह साढ़े 9 बजे", 9 * 60 + 30), ("मीटिंग सुबह पौने 10 बजे", 9 * 60 + 45),
      ("मीटिंग सुबह सवा 8 बजे", 8 * 60 + 15), ("मीटिंग शाम को साढ़े 6 बजे", 18 * 60 + 30),
      ("मीटिंग रात पौने 10 बजे", 21 * 60 + 45), ("मीटिंग साढ़े ५ बजे", 17 * 60 + 30),
    ]
    for line in fractions {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "मीटिंग", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A fraction counts from an hour on the clock face.
    #expect(parse("मीटिंग साढ़े 13 बजे").startMinutes == nil)
    #expect(parse("मीटिंग डेढ़ बजे सुबह").startMinutes == 90)
  }

  @Test("An hour as a number word is read only before बजे")
  func numberWordHours() {
    let hours: [(word: String, minutes: Int)] = [
      ("एक", 13 * 60), ("दो", 14 * 60), ("तीन", 15 * 60), ("चार", 16 * 60), ("पाँच", 17 * 60),
      ("पांच", 17 * 60), ("छह", 18 * 60), ("छः", 18 * 60), ("सात", 7 * 60), ("आठ", 8 * 60), ("नौ", 9 * 60),
      ("दस", 10 * 60), ("ग्यारह", 11 * 60), ("बारह", 12 * 60),
    ]
    for hour in hours {
      let text = "मीटिंग \(hour.word) बजे"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "मीटिंग", "\(text): title")
    }
    #expect(parse("मीटिंग सुबह नौ बजे").startMinutes == 9 * 60)
    #expect(parse("मीटिंग शाम को सात बजे").startMinutes == 19 * 60)
    // A number word is a count anywhere else.
    expectLinesUnread(
      ["मीटिंग पाँच", "मीटिंग एक", "तीन लोग आएंगे", "दो दोस्त", "सात दिन", "मीटिंग तीन से पाँच"], languages: ["hi"])
  }

  @Test("After midnight: रात runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("मीटिंग रात 2 बजे")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "मीटिंग")
    let twelve = parse("मीटिंग रात 12 बजे")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    let trailing = parse("मीटिंग 12 बजे रात")
    #expect(trailing.startMinutes == 0)
    #expect(trailing.plannedDayOffset == 1)
    for text in ["मीटिंग आधी रात", "मीटिंग आधी रात को", "मीटिंग ठीक आधी रात को"] {
      let midnight = parse(text)
      #expect(midnight.startMinutes == 0, "\(text)")
      #expect(midnight.plannedDayOffset == 1, "\(text)")
      #expect(midnight.title == "मीटिंग", "\(text): title")
    }
    // The night counts from the evening: 6 to 11 is the evening's.
    #expect(parse("मीटिंग रात 6 बजे").startMinutes == 18 * 60)
    #expect(parse("मीटिंग रात 6 बजे").plannedDayOffset == nil)
    // A named day keeps the time on its own night: "कल रात 1 बजे" is 01:00 of the day after.
    let tomorrow = parse("कल रात 1 बजे सोना")
    #expect(tomorrow.startMinutes == 60)
    #expect(tomorrow.plannedDayOffset == 2)
    #expect(tomorrow.title == "सोना")
    let named = parse("सोमवार रात 12 बजे फ्लाइट")
    #expect(named.startMinutes == 0)
    #expect(named.plannedDayOffset == 7)
    #expect(named.title == "फ्लाइट")
    // A repeat moves to the day after, so the rule and the time agree.
    let repeating = parse("हर शुक्रवार रात 12 बजे फ्लाइट")
    #expect(repeating.startMinutes == 0)
    #expect(repeating.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(repeating.recurrenceStartOffset == 4)
    #expect(repeating.title == "फ्लाइट")
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("मीटिंग 1 बजे").startMinutes == 13 * 60)
    #expect(parse("मीटिंग 3 बजे").startMinutes == 15 * 60)
    #expect(parse("मीटिंग 6 बजे").startMinutes == 18 * 60)
    #expect(parse("मीटिंग 7 बजे").startMinutes == 7 * 60)
    #expect(parse("मीटिंग 9 बजे").startMinutes == 9 * 60)
    #expect(parse("मीटिंग 11 बजे").startMinutes == 11 * 60)
    #expect(parse("मीटिंग 12 बजे").startMinutes == 12 * 60)
    #expect(parse("मीटिंग 13 बजे").startMinutes == 13 * 60)
    #expect(parse("मीटिंग 06:30 बजे").startMinutes == 6 * 60 + 30)
    #expect(parse("मीटिंग 03:00 बजे").startMinutes == 3 * 60)
    #expect(parse("मीटिंग 3:00 बजे").startMinutes == 15 * 60)
    // A part of the day names the half of the day either way.
    #expect(parse("मीटिंग सुबह 5 बजे").startMinutes == 5 * 60)
    #expect(parse("मीटिंग शाम 5 बजे").startMinutes == 17 * 60)
  }

  @Test("A part of the day before an hour may carry ठीक, करीब, लगभग, तकरीबन, or जल्दी, and सुबह may be doubled")
  func partModifiers() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("मीटिंग सुबह ठीक 6 बजे", "मीटिंग", 6 * 60), ("मीटिंग सुबह करीब 6 बजे", "मीटिंग", 6 * 60),
      ("मीटिंग सुबह जल्दी 6 बजे", "मीटिंग", 6 * 60), ("मीटिंग सुबह तकरीबन 9 बजे", "मीटिंग", 9 * 60),
      ("चाय शाम को ठीक 5 बजे", "चाय", 17 * 60), ("मीटिंग शाम को करीब 6 बजे", "मीटिंग", 18 * 60),
      ("मीटिंग रात लगभग 11 बजे", "मीटिंग", 23 * 60),
      ("सुबह-सुबह 6 बजे योग", "योग", 6 * 60), ("योग सुबह-सुबह 6 बजे", "योग", 6 * 60),
      ("सुबह सुबह 6 बजे योग", "योग", 6 * 60), ("सुबह\u{2011}सुबह 7 बजे योग", "योग", 7 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The doubled morning also follows a day.
    let tomorrow = parse("कल सुबह-सुबह उठना")
    #expect(tomorrow.plannedDayOffset == 1)
    #expect(tomorrow.title == "उठना")
    #expect(tomorrow.phrases.map(\.text) == ["कल सुबह-सुबह"])
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("सुबह की सैर 6 बजे", "सुबह की सैर", 6 * 60), ("6 बजे सुबह की सैर", "सुबह की सैर", 6 * 60),
      ("सुबह की सैर 5 बजे", "सुबह की सैर", 5 * 60), ("सुबह-सुबह की सैर 6 बजे", "सुबह-सुबह की सैर", 6 * 60),
      ("रात का खाना 8 बजे", "रात का खाना", 20 * 60), ("रात का खाना 6 बजे", "रात का खाना", 18 * 60),
      ("रात का खाना साढ़े 8 बजे", "रात का खाना", 20 * 60 + 30), ("रात की दवा 10 बजे", "रात की दवा", 22 * 60),
      ("शाम की चाय 5 बजे", "शाम की चाय", 17 * 60), ("दोपहर का खाना 1 बजे", "दोपहर का खाना", 13 * 60),
      ("दोपहर का खाना 2 बजे", "दोपहर का खाना", 14 * 60),
      // The 24-hour clock is read as written: a leading zero, or 13 and later.
      ("रात का खाना 20:00 बजे", "रात का खाना", 20 * 60), ("रात की ड्यूटी 06:30 बजे", "रात की ड्यूटी", 6 * 60 + 30),
      // Noon is no morning hour, so a morning's 12 stays as written.
      ("सुबह की मीटिंग 12 बजे", "सुबह की मीटिंग", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The part of the day may come from the day phrase, and the day is read too.
    let dinner = parse("आज रात का खाना 8 बजे")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "रात का खाना")
    let meeting = parse("कल सुबह मीटिंग 6 बजे")
    #expect(meeting.plannedDayOffset == 1)
    #expect(meeting.startMinutes == 6 * 60)
    #expect(meeting.title == "मीटिंग")
    // Two parts that differ leave the hour as it reads alone, and "आधी रात"
    // names no part.
    #expect(parse("सुबह की सैर रात का खाना 5 बजे").startMinutes == 17 * 60)
    #expect(parse("आधी रात को खाना 5 बजे").startMinutes == 17 * 60)
  }

  @Test("Time ranges: से with बजे, a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("मीटिंग 3 से 5 बजे", 15 * 60, 120), ("मीटिंग 3 से 5 बजे तक", 15 * 60, 120),
      ("मीटिंग 3 बजे से 5 बजे तक", 15 * 60, 120), ("मीटिंग 2 बजे से लेकर 4 बजे तक", 14 * 60, 120),
      ("मीटिंग सुबह 9 से 11 बजे", 9 * 60, 120), ("मीटिंग सुबह 9 से 11 बजे तक", 9 * 60, 120),
      ("मीटिंग शाम 5 से 7 बजे", 17 * 60, 120), ("मीटिंग रात 8 से 10 बजे", 20 * 60, 120),
      ("मीटिंग दो से चार बजे", 14 * 60, 120), ("मीटिंग २ से ४ बजे", 14 * 60, 120),
      ("मीटिंग 2-4 बजे", 14 * 60, 120), ("मीटिंग 2–4 बजे", 14 * 60, 120),
      ("मीटिंग 14:00 से 16:00", 14 * 60, 120), ("मीटिंग 14:00 से 16:00 तक", 14 * 60, 120),
      ("मीटिंग 9:30 से 10:30 तक", 9 * 60 + 30, 60), ("मीटिंग 14:00-16:00", 14 * 60, 120),
      ("मीटिंग सुबह 9 बजे से शाम 5 बजे तक", 9 * 60, 480), ("मीटिंग 9 से 5 बजे", 9 * 60, 480),
      ("मीटिंग 10 से 12 बजे", 10 * 60, 120), ("मीटिंग 11 से 1 बजे", 11 * 60, 120),
      ("मीटिंग 3 से 5 बजे के बीच", 15 * 60, 120), ("मीटिंग 3 से 5 बजे के दौरान", 15 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "मीटिंग", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The end carries बजे: two bare numbers are no range.
    expectLinesUnread(["मीटिंग 3 से 5", "मीटिंग तीन से पाँच"], languages: ["hi"])
    // A length written in the line wins over the span of the range.
    let named = parse("मीटिंग 3 से 5 बजे 30 मिनट")
    #expect(named.startMinutes == 15 * 60)
    #expect(named.estimatedMinutes == 30)
    #expect(named.title == "मीटिंग")
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amounts() {
    expectLinesUnread(
      [
        "3 लोगों के साथ मीटिंग", "३ लोगों के साथ मीटिंग", "मीटिंग में 3 लोग आएंगे", "5 किताबें ख़रीदना",
        "10 पन्ने पढ़ना", "2 किलो चीनी लाना", "12 अंडे लाना", "500 रुपये का बिल जमा करें", "500 रुपए का बिल",
        "500 रु. का बिल", "₹500 का बिल", "बिल ₹500", "5 डॉलर खर्च", "50 पैसे दें", "20% छूट", "20 % छूट",
        "5 बजट बनाना",
      ], languages: ["hi"])
    // The words around an amount still read.
    let bill = parse("500 रुपये का बिल जमा करें कल")
    #expect(bill.plannedDayOffset == 1)
    #expect(bill.title == "500 रुपये का बिल जमा करें")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("30 मिनट", 30), ("30 मिनट के लिए", 30), ("45 मिनट", 45), ("90 मिनट", 90), ("2 मिनट", 2), ("४५ मिनट", 45),
      ("2 घंटे", 120), ("2 घंटे के लिए", 120), ("2 घण्टे", 120), ("2 घंटों", 120), ("1 घंटा", 60),
      ("1 घण्टा", 60), ("1.5 घंटे", 90), ("1 घंटा 30 मिनट", 90), ("1 घंटा और 30 मिनट", 90),
      ("आधा घंटा", 30), ("आधे घंटे", 30), ("आधा घण्टा", 30), ("पौन घंटा", 45), ("सवा घंटा", 75),
      ("डेढ़ घंटा", 90), ("डेढ घंटा", 90), ("ढाई घंटे", 150), ("साढ़े 3 घंटे", 210), ("साढ़े तीन घंटे", 210),
      ("पौने दो घंटे", 105), ("सवा 2 घंटे", 135), ("दो घंटे", 120), ("एक घंटा", 60), ("बीस मिनट", 20),
      ("पंद्रह मिनट", 15), ("तीस मिनट", 30), ("पैंतालीस मिनट", 45), ("दस मिनट", 10),
      ("लगभग 2 घंटे", 120), ("करीब 30 मिनट", 30), ("तकरीबन 20 मिनट", 20),
    ]
    for line in lengths {
      let text = "रिपोर्ट लिखें \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "रिपोर्ट लिखें", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The postposition that goes with a length is read with it.
    let meeting = parse("30 मिनट की मीटिंग")
    #expect(meeting.estimatedMinutes == 30)
    #expect(meeting.title == "मीटिंग")
    #expect(meeting.phrases.map(\.text) == ["30 मिनट की"])
    let work = parse("2 घंटे का काम")
    #expect(work.estimatedMinutes == 120)
    #expect(work.title == "काम")
    // A time and a length together.
    let both = parse("मीटिंग 5 बजे 45 मिनट के लिए")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "मीटिंग")
  }

  @Test("An amount before बाद, पहले, or में, or after हर, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "रिपोर्ट लिखें 2 घंटे बाद", "रिपोर्ट लिखें 15 मिनट बाद", "रिपोर्ट लिखें 1 घंटा पहले",
        "रिपोर्ट लिखें 30 मिनट पहले", "रिपोर्ट लिखें हर 2 घंटे", "रिपोर्ट लिखें हर 30 मिनट",
        "रिपोर्ट लिखें 2 घंटे के भीतर", "रिपोर्ट लिखें 2 घंटे में", "रिपोर्ट लिखें 15 मिनट में",
        "रिपोर्ट लिखें दिन में 2 घंटे", "रिपोर्ट लिखें कम से कम 2 घंटे", "रिपोर्ट लिखें 2 घंटे से ज़्यादा",
        // A range of amounts, an hour as a noun, and an amount no task takes.
        "रिपोर्ट लिखें 2 से 3 घंटे", "रिपोर्ट लिखें 2-3 घंटे", "रिपोर्ट लिखें 5 मिनट से 10 मिनट",
        "रिपोर्ट लिखें घंटा", "घंटा भर पढ़ना", "घण्टा भर", "रिपोर्ट लिखें 25 घंटे", "रिपोर्ट लिखें 0 मिनट",
      ], languages: ["hi"])
    // The phrase around an amount that is no length still reads.
    let day = parse("रिपोर्ट लिखें 2 घंटे बाद कल")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "रिपोर्ट लिखें 2 घंटे बाद")
    let time = parse("मीटिंग कल 3 बजे 2 घंटे बाद")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "मीटिंग 2 घंटे बाद")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("हर दिन", daily), ("रोज़", daily), ("रोज", daily), ("रोज़ाना", daily), ("रोजाना", daily),
      ("प्रतिदिन", daily), ("नित्य", daily), ("हर रोज़", daily), ("प्रत्येक दिन", daily), ("हर सुबह", daily),
      ("हर शाम", daily), ("हर रात", daily), ("दिन में एक बार", daily),
      ("हर हफ़्ते", weekly), ("हर हफ्ते", weekly), ("हर सप्ताह", weekly), ("हरेक सप्ताह", weekly),
      ("सप्ताह में एक बार", weekly), ("हफ़्ते में एक बार", weekly),
      ("हर महीने", monthly), ("हर माह", monthly), ("महीने में एक बार", monthly),
      ("हर साल", yearly), ("हर वर्ष", yearly), ("साल में एक बार", yearly),
      ("हर 2 दिन", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("हर दो दिन", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("हर दूसरे दिन", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("हर पंद्रह दिन", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("हर 3 हफ़्ते", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("हर दूसरे हफ़्ते", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("हर 3 महीने", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("हर तीन महीने", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("हर 5 साल", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("हर ३ दिन", TaskRecurrenceRule(freq: .daily, interval: 3)),
    ]
    for line in cadences {
      let text = "दवा लें \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "दवा लें", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
  }

  @Test("Weekday repeats: हर सोमवार, lists of days, plural days, the weekend, and the working days")
  func weekdayRepeats() {
    let coming = parse("जिम हर सोमवार")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "जिम")
    #expect(coming.plannedDayOffset == nil)
    #expect(parse("जिम हर सोमवार को").recurrence == monday)
    #expect(parse("जिम सोमवारों को").recurrence == monday)
    #expect(parse("जिम सोमवारों को").plannedDayOffset == nil)
    #expect(parse("जिम हर हफ़्ते सोमवार को").recurrence == monday)
    #expect(parse("जिम प्रत्येक सोमवार").recurrence == monday)

    let lists: [(text: String, days: [String])] = [
      ("जिम हर सोमवार और गुरुवार", ["MO", "TH"]), ("जिम हर सोमवार, बुधवार और शुक्रवार", ["MO", "WE", "FR"]),
      ("जिम हर बुधवार", ["WE"]), ("जिम हर शनिवार", ["SA"]), ("जिम हर रविवार", ["SU"]), ("जिम हर इतवार", ["SU"]),
      ("जिम सोमवार और गुरुवार को हर हफ़्ते", ["MO", "TH"]), ("जिम सोमवारों और गुरुवारों को", ["MO", "TH"]),
      ("जिम हर शनिवार और रविवार", ["SU", "SA"]), ("जिम हर वीकेंड", ["SU", "SA"]),
      ("जिम हर सप्ताहांत", ["SU", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "जिम", "\(line.text): title")
    }
    #expect(parse("जिम हर सोमवार और गुरुवार").recurrenceStartOffset == 2)
    #expect(parse("जिम हर वीकेंड").recurrenceStartOffset == 4)
    let everyOther = parse("जिम हर दूसरे सोमवार")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))

    // The working days, written out or as a span of weekdays beside हर or
    // a word for every day.
    for text in [
      "जिम हर कार्यदिवस", "जिम हर कार्य दिवस", "जिम कार्यदिवसों में", "जिम हर कामकाजी दिन",
      "जिम कामकाजी दिनों में", "जिम हर सोमवार से शुक्रवार", "जिम रोज़ सोमवार से शुक्रवार",
      "जिम सोमवार से शुक्रवार हर दिन", "जिम सोमवार से शुक्रवार प्रतिदिन", "जिम हर सोमवार से शुक्रवार तक",
      "जिम हर सोमवार से शुक्रवार सुबह 9 बजे",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
    #expect(parse("जिम हर सोमवार से बुधवार").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE"]))
    #expect(
      parse("जिम हर रविवार से गुरुवार").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"]))
    // Monday to Friday alone is no repeat.
    #expect(parse("जिम सोमवार से शुक्रवार").recurrence == nil)
    // A repeat that starts today starts at 0 on its own weekday.
    #expect(parse("जिम हर मंगलवार").recurrenceStartOffset == 0)
    #expect(parse("जिम हर शुक्रवार", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("योग हर सुबह 6 बजे", "योग", 6 * 60), ("हर सुबह 6 बजे योग", "योग", 6 * 60),
      ("हर शाम को 7 बजे टहलना", "टहलना", 19 * 60), ("योग हर शाम को 7 बजे", "योग", 19 * 60),
      ("हर रात 10:30 दवा", "दवा", 22 * 60 + 30), ("हर रात 11 बजे सोना", "सोना", 23 * 60),
      ("प्रत्येक सुबह 5 बजे योग", "योग", 5 * 60), ("रोज़ सुबह 6 बजे योग", "योग", 6 * 60),
      ("रोज़ शाम को 7 बजे टहलना", "टहलना", 19 * 60), ("हर सुबह-सुबह 6 बजे योग", "योग", 6 * 60),
      ("हर रात को पढ़ना", "पढ़ना", nil), ("हर सुबह में योग", "योग", nil),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let range = parse("हर सुबह 9 से 11 बजे पढ़ाई")
    #expect(range.recurrence == daily)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "पढ़ाई")
    // A line of details alone is no task.
    expectLinesUnread(["हर सुबह 6 बजे", "हर शाम 7 बजे"], languages: ["hi"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "किराया हर महीने की 5 तारीख", "किराया हर महीने की 5 तारीख को", "किराया हर महीने 5 तारीख को",
      "किराया हर महीने की 5वीं तारीख को", "किराया हर माह की 5 तारीख", "किराया हर महीने की ५ तारीख",
      "किराया 5 तारीख को हर महीने", "किराया हर महीने की 5 को",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text): start")
      #expect(parsed.title == "किराया", "\(text): title")
    }
    let first = parse("किराया हर महीने की पहली तारीख")
    #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    #expect(first.recurrenceStartOffset == 9)
    // A date with its month name is a date, not a repeat.
    #expect(parse("किराया हर 5 मई").recurrence == nil)
  }

  @Test("A repeat shorter than a day, and a cadence word that describes a noun, are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        "दवा लें हर 2 घंटे", "दवा लें रोज़ का काम", "दवा लें हर साल की रिपोर्ट", "रोज़ा रखना", "रोज़गार मेला",
        "रोज़ी-रोटी कमाना", "हर साल का हिसाब", "हर दिन की डायरी", "रोज़ाना की खबरें",
      ], languages: ["hi"])
    // The weekday after हर with a possessive is an attribute too.
    #expect(parse("हर सोमवार की मीटिंग").recurrence == nil)
  }

  // MARK: - Priorities

  @Test("Priorities: उच्च, मध्यम, and निम्न प्राथमिकता, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("उच्च प्राथमिकता", .p1), ("उच्चतम प्राथमिकता", .p1), ("सर्वोच्च प्राथमिकता", .p1), ("प्राथमिकता: उच्च", .p1),
      ("प्राथमिकता उच्च", .p1), ("मध्यम प्राथमिकता", .p2), ("सामान्य प्राथमिकता", .p2), ("साधारण प्राथमिकता", .p2),
      ("प्राथमिकता: मध्यम", .p2), ("निम्न प्राथमिकता", .p3), ("निम्नतम प्राथमिकता", .p3), ("कम प्राथमिकता", .p3),
      ("प्राथमिकता कम", .p3), ("प्राथमिकता: निम्न", .p3), ("उच्च प्राथमिकता से", .p1),
    ]
    for level in levels {
      let text = "रिपोर्ट भेजें \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "रिपोर्ट भेजें", "\(text): title")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let inside = parse("रिपोर्ट उच्च प्राथमिकता से भेजें")
    #expect(inside.priority == .p1)
    #expect(inside.title == "रिपोर्ट भेजें")

    for word in ["ज़रूरी", "जरूरी", "अत्यावश्यक", "अति आवश्यक", "तुरंत", "तुरन्त", "अर्जेंट", "बहुत ज़रूरी"] {
      let text = "रिपोर्ट भेजें \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "रिपोर्ट भेजें", "\(text): title")
    }
    for word in ["ज़रूरी", "तुरंत", "अत्यावश्यक"] {
      for separator in [":", ","] {
        let text = "\(word)\(separator) रिपोर्ट भेजें"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "रिपोर्ट भेजें", "\(text): title")
      }
    }
    #expect(parse("रिपोर्ट भेजें तुरंत।").title == "रिपोर्ट भेजें।")
    // An urgent word in the middle, or opening the line with no colon or
    // comma, is a word of the title.
    expectLinesUnread(
      [
        "ज़रूरी दवाइयाँ ख़रीदना", "रिपोर्ट भेजें ज़रूरी है", "तुरंत रिपोर्ट भेजें", "रिपोर्ट भेजें तुरंत ही",
        "ज़रूरी काम निपटाना", "उच्च प्राथमिकता वाले कार्य", "कम प्राथमिकता वाली सूची",
      ], languages: ["hi"])
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("कल शाम 5 बजे 30 मिनट के लिए मीटिंग #काम")
    #expect(line.title == "मीटिंग")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["काम"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["कल", "शाम 5 बजे", "30 मिनट के लिए", "#काम"])

    let lines: [(text: String, title: String)] = [
      ("हर सोमवार सुबह 9 बजे जिम", "जिम"), ("शुक्रवार तक रिपोर्ट भेजना ज़रूरी", "रिपोर्ट भेजना"),
      ("सोमवार को सुबह 9 से 11 बजे तक मीटिंग", "मीटिंग"), ("5 मई को शाम 6 बजे पार्टी", "पार्टी"),
      ("अगले शुक्रवार तक 2 घंटे का काम", "काम"), ("कल मीटिंग 3 बजे उच्च प्राथमिकता", "मीटिंग"),
      ("रोज़ सुबह 7 बजे दवा", "दवा"), ("आज रात 11 बजे सोना", "सोना"),
      ("माँ को फोन करें कल शाम 5 बजे", "माँ को फोन करें"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(parse(line.text).phrases.count >= 2, "\(line.text): phrases")
    }
    let friday = parse("शुक्रवार तक रिपोर्ट भेजना ज़रूरी")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.priority == .p1)
    let weekly = parse("हर सोमवार सुबह 9 बजे जिम")
    #expect(weekly.recurrence == monday)
    #expect(weekly.startMinutes == 9 * 60)
    let report = parse("अगले शुक्रवार तक 2 घंटे का काम")
    #expect(report.dueDayOffset == 10)
    #expect(report.estimatedMinutes == 120)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // The short weekday stems are ordinary words and names.
        "रवि को फोन करें", "शनि मंदिर जाना", "मंगल ग्रह देखना", "गुरु को प्रणाम", "बुध ग्रह", "शुक्र है",
        "सोम को फोन करें",
        // Words that contain a day word.
        "आजकल मीटिंग", "आज-कल मीटिंग", "कलयुग पढ़ें", "कलम ख़रीदना", "आजादी का दिन", "सोमवारी पढ़ें",
        // A day with a possessive after it is an attribute of a noun.
        "सोमवार की मीटिंग", "शुक्रवार का खाना", "कल की मीटिंग", "कल का खाना", "आज की रिपोर्ट",
        // A bound or an amount of days that names no day.
        "रिपोर्ट 3 दिन में भेजें", "3 दिन पहले की बात", "मीटिंग के 3 दिन बाद",
        // A bare number that is a count.
        "3 सेब ख़रीदना", "5 लोगों को बुलाना",
      ], languages: ["hi"])
    // Hindi written in Latin letters is not read.
    expectLinesUnread(
      [
        "kal subah 9 baje meeting", "aaj shaam ko phone karna", "parson ko milna", "somvar ko meeting",
        "har somvar gym", "2 ghante padhna", "shuukrvaar tak report",
      ], languages: ["hi"])
    // "शुक्रवार को" before other words is the day.
    let friday = parse("शुक्रवार को पार्टी की तैयारी करें")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "पार्टी की तैयारी करें")
  }

  // MARK: - कल, परसों, and the past

  @Test("कल is tomorrow and परसों the day after, and a line in the past tense stays unread")
  func tomorrowOrYesterday() {
    let tomorrow = [
      "कल मीटिंग है", "कल जाना है", "कल किया जाना है", "कल मीटिंग होगी", "कल से जिम शुरू करना", "रिपोर्ट कल भेजना",
    ]
    for text in tomorrow {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        // The app's own word for the past day, and the other words that say a day is past.
        "बीता कल", "बीता कल की रिपोर्ट", "बीता कल की रिपोर्ट पढ़ें", "बीते कल को मीटिंग", "गुज़रे कल की बात",
        "पिछले शुक्रवार की मीटिंग", "पहले शुक्रवार को मीटिंग", "पहले कल की रिपोर्ट",
        // A past-tense form anywhere in the line.
        "कल मीटिंग थी", "परसों मीटिंग थी", "मैं कल गया था", "कल गए थे", "कल आया था", "कल मीटिंग हुई",
        "कल हुई मीटिंग की रिपोर्ट", "आज मीटिंग थी", "सोमवार को मीटिंग थी",
      ], languages: ["hi"])
    // "पहले शुक्रवार" is a past or an ordinal day, but "शुक्रवार से पहले" is a deadline.
    #expect(parse("रिपोर्ट शुक्रवार से पहले").dueDayOffset == 3)
    #expect(parse("रिपोर्ट कल से पहले").dueDayOffset == 1)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // A past statement with no past-tense marker reads as tomorrow.
    #expect(parse("कल मैंने फोन किया").plannedDayOffset == 1)
    // An hour from 1 to 6 with no part of the day is the afternoon.
    #expect(parse("मीटिंग 5 बजे").startMinutes == 17 * 60)
    // An hour count written with a Latin unit is English's length, even after हर.
    let hours = parse("दवा लें हर 2h")
    #expect(hours.estimatedMinutes == 120)
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("यह काम ज़रूरी").priority == .p1)
    #expect(parse("यह काम तुरंत").priority == .p1)
    // A particle after a day goes with it even where it means "even today".
    let even = parse("आज भी रिपोर्ट भेजना")
    #expect(even.plannedDayOffset == 0)
    #expect(even.title == "रिपोर्ट भेजना")
    #expect(parse("कल भी जाना है").plannedDayOffset == 1)
  }

  // MARK: - Scripts and spellings

  @Test("The precomposed and the decomposed nukta read as one letter, and a missing nukta reads too")
  func nuktaForms() {
    // ज़ ड़ ढ़ फ़ as one code point (U+095B, U+095C, U+095D, U+095E), as a
    // consonant and a nukta (U+093C), and as the consonant alone.
    let forms: [(za: String, da: String, dha: String, pha: String)] = [
      ("\u{095B}", "\u{095C}", "\u{095D}", "\u{095E}"),
      ("\u{091C}\u{093C}", "\u{0921}\u{093C}", "\u{0922}\u{093C}", "\u{092B}\u{093C}"),
      ("\u{091C}", "\u{0921}", "\u{0922}", "\u{092B}"),
    ]
    for form in forms {
      let scalars = form.za.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      // ज़रूरी, रोज़, रोज़ाना
      #expect(parse("रिपोर्ट भेजें \(form.za)रूरी").priority == .p1, "ज़रूरी: \(scalars)")
      #expect(parse("\(form.za)रूरी: रिपोर्ट भेजें").priority == .p1, "ज़रूरी opening: \(scalars)")
      #expect(parse("दवा लें रो\(form.za)").recurrence == daily, "रोज़: \(scalars)")
      #expect(parse("दवा लें रो\(form.za)ाना").recurrence == daily, "रोज़ाना: \(scalars)")
      // साढ़े, डेढ़
      #expect(parse("मीटिंग सा\(form.dha)े 5 बजे").startMinutes == 17 * 60 + 30, "साढ़े: \(scalars)")
      #expect(parse("मीटिंग डे\(form.dha) बजे").startMinutes == 13 * 60 + 30, "डेढ़: \(scalars)")
      #expect(parse("रिपोर्ट डे\(form.dha) घंटा").estimatedMinutes == 90, "डेढ़ घंटा: \(scalars)")
      // तड़के
      #expect(parse("मीटिंग त\(form.da)के 4 बजे").startMinutes == 4 * 60, "तड़के: \(scalars)")
      // फ़रवरी, हफ़्ते
      #expect(parse("फोन करें 5 \(form.pha)रवरी").plannedDayOffset == 136, "फ़रवरी: \(scalars)")
      #expect(parse("फोन करें 2 ह\(form.pha)्ते बाद").plannedDayOffset == 14, "हफ़्ते बाद: \(scalars)")
      #expect(parse("दवा लें हर ह\(form.pha)्ते").recurrence == TaskRecurrenceRule(freq: .weekly), "हर हफ़्ते: \(scalars)")
    }
  }

  @Test("The candrabindu and the anusvara, and the nasal conjunct spelled either way, read as one word")
  func nasalSpellings() {
    // पाँच and पांच
    #expect(parse("मीटिंग पा\u{0901}च बजे").startMinutes == 17 * 60)
    #expect(parse("मीटिंग पा\u{0902}च बजे").startMinutes == 17 * 60)
    let months: [(text: String, date: String)] = [
      ("5 सितंबर", "2027-09-05"), ("5 सितम्बर", "2027-09-05"), ("5 नवंबर", "2026-11-05"), ("5 नवम्बर", "2026-11-05"),
      ("5 दिसंबर", "2026-12-05"), ("5 दिसम्बर", "2026-12-05"), ("5 अक्टूबर", "2026-10-05"), ("5 अक्तूबर", "2026-10-05"),
      ("5 अप्रैल", "2027-04-05"), ("5 अप्रेल", "2027-04-05"),
    ]
    for month in months {
      #expect(parse("फोन करें \(month.text)").plannedDayOffset == captureDayOffset(month.date), "\(month.text)")
    }
    for hours in ["घंटा", "घण्टा", "घन्टा"] {
      #expect(parse("रिपोर्ट लिखें 1 \(hours)").estimatedMinutes == 60, "\(hours)")
    }
    for word in ["तुरंत", "तुरन्त"] {
      #expect(parse("रिपोर्ट भेजें \(word)").priority == .p1, "\(word)")
    }
    for word in ["पंद्रह", "पन्द्रह"] {
      #expect(parse("रिपोर्ट लिखें \(word) मिनट").estimatedMinutes == 15, "\(word)")
    }
    for word in ["वीकेंड", "वीकेन्ड"] {
      #expect(parse("फोन करें \(word)").plannedDayOffset == 4, "\(word)")
    }
  }

  @Test("A zero-width joiner after a virama changes nothing")
  func joiners() {
    #expect(parse("फोन करें 5 सितम्\u{200C}बर").plannedDayOffset == captureDayOffset("2027-09-05"))
    #expect(parse("फोन करें 5 सितम्\u{200D}बर").plannedDayOffset == captureDayOffset("2027-09-05"))
    #expect(parse("रिपोर्ट लिखें 1 घण्\u{200D}टा").estimatedMinutes == 60)
    #expect(parse("रिपोर्ट भेजें तुरन्\u{200C}त").priority == .p1)
    // The title keeps the joiner as typed.
    let typed = "सितम्\u{200C}बर की रिपोर्ट"
    #expect(Array(parse("\(typed) कल").title.unicodeScalars) == Array(typed.unicodeScalars))
  }

  @Test("Devanagari digits and Western digits read the same")
  func digitScripts() {
    let lines = [
      "मीटिंग 3:30 बजे", "मीटिंग शाम 5:30", "मीटिंग 5.30 बजे", "मीटिंग साढ़े 5 बजे", "मीटिंग 2 से 4 बजे",
      "मीटिंग 14:00 से 16:00", "रिपोर्ट लिखें 20 मिनट", "रिपोर्ट लिखें 1.5 घंटे", "रिपोर्ट लिखें 1 घंटा 30 मिनट",
      "दवा लें हर 3 दिन", "किराया हर महीने की 5 तारीख", "बैठक 5 मार्च 2027", "फोन करें 3 दिन बाद",
      "छुट्टी 3 से 5 मार्च", "छुट्टी 3-5 मार्च", "रिपोर्ट भेजें 5 मार्च तक", "फोन करें 2 महीने बाद",
      "दवा लें हर 2 हफ़्ते",
    ]
    for line in lines {
      let latin = parse(line)
      #expect(latin.phrases.count == 1, "\(line): phrases")
      let converted = devanagariDigits(line)
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
    let typed = parse("३ लोगों के साथ मीटिंग कल")
    #expect(typed.plannedDayOffset == 1)
    #expect(typed.title == "३ लोगों के साथ मीटिंग")
  }

  @Test("The title keeps the letters and signs as they were typed")
  func titleKeepsTypedText() {
    // A precomposed nukta letter in the title stays one code point, and a
    // decomposed one stays two.
    let typed = "\u{095B}रूरी दवाइयाँ \u{0959}रीदना और ल\u{0921}\u{093C}का"
    let parsed = parse("\(typed) कल")
    #expect(parsed.plannedDayOffset == 1)
    #expect(parsed.priority == nil)
    #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    let candrabindu = parse("माँ को फोन करें कल")
    #expect(Array(candrabindu.title.unicodeScalars) == Array("माँ को फोन करें".unicodeScalars))
  }

  @Test("The danda and the comma left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("फोन करें, कल, शाम 5 बजे", "फोन करें"), ("फोन करें कल।", "फोन करें।"), ("कल, फोन करें", "फोन करें"),
      ("कल: फोन करें", "फोन करें"), ("फोन करें - कल", "फोन करें"),
      ("रिपोर्ट भेजें, शुक्रवार तक, उच्च प्राथमिकता", "रिपोर्ट भेजें"),
      ("दूध, ब्रेड और अंडे कल ख़रीदना", "दूध, ब्रेड और अंडे ख़रीदना"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The danda is punctuation: it ends a word.
    #expect(parse("फोन करें कल।").plannedDayOffset == 1)
    #expect(parse("रिपोर्ट भेजें शुक्रवार तक।").dueDayOffset == 3)
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    #expect(parse("काम कल").plannedDayOffset == 1)
    #expect(parse("काम शाम 5 बजे").startMinutes == 17 * 60)
    #expect(parse("काम हर सोमवार").recurrence == monday)
    #expect(parse("काम 20 मिनट").estimatedMinutes == 20)
    #expect(parse("काम #सूची").tags == ["सूची"])
  }

  // MARK: - Beside other languages

  @Test("Beside Hindi, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "hi"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "hi"]).estimatedMinutes == 20)
    #expect(parse("रिपोर्ट 2h").estimatedMinutes == 120)
    #expect(parse("रिपोर्ट 30min").estimatedMinutes == 30)
    #expect(parse("रिपोर्ट 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "hi"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "hi"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "hi"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "hi"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times.
    #expect(parse("मीटिंग 5pm").startMinutes == 17 * 60)
    #expect(parse("मीटिंग 5 PM").startMinutes == 17 * 60)
    #expect(parse("मीटिंग 17:30").startMinutes == 17 * 60 + 30)
    // English lines read the same with Hindi beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "hi"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom कल at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting शुक्रवार को at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("मीटिंग tomorrow शाम 5 बजे")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "मीटिंग")
    let hindiTitle = parse("बैठक next friday")
    #expect(hindiTitle.plannedDayOffset == 10)
    #expect(hindiTitle.title == "बैठक")
    #expect(parse("बैठक 2h").estimatedMinutes == 120)
  }

  @Test("Hindi words are read only for a user who reads Hindi")
  func languageGate() {
    let line = parse("माँ को फोन करें कल", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "माँ को फोन करें कल")
    for languages in [["hi"], ["hi-IN"], ["hi_IN"], ["en-US", "hi-IN"], ["HI"], ["hi-Latn", "en"]] {
      #expect(parse("माँ को फोन करें कल", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages that write Devanagari do not get Hindi words.
    #expect(parse("माँ को फोन करें कल", languages: ["mr"]).plannedDayOffset == nil)
    #expect(parse("माँ को फोन करें कल", languages: ["ne"]).plannedDayOffset == nil)
    // Other languages' words are not read for a Hindi reader, and Hindi is not read for theirs.
    #expect(parse("Zadzwonić jutro", languages: ["hi"]).plannedDayOffset == nil)
    #expect(parse("Позвонить завтра", languages: ["hi"]).plannedDayOffset == nil)
    #expect(parse("اتصل بأمي غداً", languages: ["hi"]).plannedDayOffset == nil)
    #expect(parse("माँ को फोन करें कल", languages: ["ar"]).plannedDayOffset == nil)
    #expect(parse("माँ को फोन करें कल", languages: ["pl"]).plannedDayOffset == nil)
    #expect(parse("माँ को फोन करें कल", languages: ["ru"]).plannedDayOffset == nil)
    // A clock time, a repeat, and a priority with a Hindi word need Hindi among the languages.
    #expect(parse("मीटिंग 5 बजे", languages: ["en"]).startMinutes == nil)
    #expect(parse("दवा लें हर सोमवार", languages: ["en"]).recurrence == nil)
    #expect(parse("रिपोर्ट भेजें उच्च प्राथमिकता", languages: ["en"]).priority == nil)
    #expect(parse("रिपोर्ट लिखें 30 मिनट", languages: ["en"]).estimatedMinutes == nil)
    // Hindi and Arabic readers get both.
    let both = parse("माँ को फोन करें कल", languages: ["ar", "hi"])
    #expect(both.plannedDayOffset == 1)
    #expect(parse("اتصل بأمي غداً", languages: ["ar", "hi"]).plannedDayOffset == 1)
  }
}
