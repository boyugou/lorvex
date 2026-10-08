import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["mr"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["mr"])
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

/// Marathi capture lines, read for a user whose languages include Marathi.
@Suite("Capture parser Marathi")
struct CaptureParserMarathiTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("आईला फोन करा उद्या")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "आईला फोन करा")
    #expect(line.phrases.map(\.text) == ["उद्या"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("फोन करा आज", 0), ("फोन करा आजच", 0), ("फोन करा आजपासून", 0), ("फोन करा उद्या", 1), ("फोन करा उद्याच", 1),
      ("फोन करा उद्याला", 1), ("फोन करा उद्यापासून", 1), ("फोन करा उद्यासाठी", 1), ("फोन करा परवा", 2),
      ("फोन करा परवाच", 2), ("फोन करा 3 दिवसांनी", 3), ("फोन करा 3 दिवसांनंतर", 3), ("फोन करा तीन दिवसांनी", 3),
      ("फोन करा ३ दिवसांनी", 3), ("फोन करा एका दिवसाने", 1), ("फोन करा 10 दिवसांनी", 10),
      ("फोन करा पंधरा दिवसांनी", 15), ("फोन करा 2 आठवड्यांनी", 14), ("फोन करा दोन आठवड्यांनी", 14),
      ("फोन करा एका आठवड्याने", 7), ("फोन करा 3 आठवड्यांनंतर", 21), ("फोन करा 1 महिन्याने", 30),
      ("फोन करा 2 महिन्यांनी", 61), ("फोन करा पुढच्या आठवड्यात", 7), ("फोन करा पुढील आठवड्यात", 7),
      ("फोन करा येत्या आठवड्यात", 7),
    ]
    for day in days {
      let parsed = parse(day.text)
      #expect(parsed.plannedDayOffset == day.offset, "\(day.text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(day.text): due day")
      #expect(parsed.title == "फोन करा", "\(day.text): title")
      #expect(parsed.phrases.count == 1, "\(day.text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("उद्या आईला फोन करा")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "आईला फोन करा")
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("आज सकाळी", 0), ("आज दुपारी", 0), ("आज संध्याकाळी", 0), ("आज रात्री", 0), ("उद्या सकाळी", 1),
      ("उद्या दुपारी", 1), ("उद्या संध्याकाळी", 1), ("उद्या सायंकाळी", 1), ("उद्या रात्री", 1), ("उद्या पहाटे", 1),
      ("परवा संध्याकाळी", 2), ("शुक्रवारी संध्याकाळी", 3), ("शुक्रवारी रात्री", 3), ("शनिवारी सकाळी", 4),
    ]
    for phrase in phrases {
      let parsed = parse("फोन करा \(phrase.text)")
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "फोन करा", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("उद्या सकाळी मीटिंग 6 वाजता")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "मीटिंग")
    let evening = parse("आज संध्याकाळी जिम 7 वाजता")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "जिम")
    let night = parse("उद्या रात्री जेवण 9 वाजता")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 21 * 60)
    #expect(night.title == "जेवण")
    let written = parse("आज रात्री 8 वाजता जेवण")
    #expect(written.plannedDayOffset == 0)
    #expect(written.startMinutes == 20 * 60)
    #expect(written.title == "जेवण")
    // The part of the day as a noun names no day.
    expectLinesUnread(
      ["सकाळची सैर", "संध्याकाळचा चहा", "रात्रीचे जेवण", "दुपारचे जेवण", "सकाळी लवकर उठणे", "रात्री वाचन करणे"],
      languages: ["mr"])
    // A genitive after the part of the day makes it an attribute of a noun:
    // only the day is read.
    let dinner = parse("उद्या रात्रीचे जेवण")
    #expect(dinner.plannedDayOffset == 1)
    #expect(dinner.title == "रात्रीचे जेवण")
    let tea = parse("उद्या संध्याकाळचा चहा")
    #expect(tea.plannedDayOffset == 1)
    #expect(tea.title == "संध्याकाळचा चहा")
  }

  @Test("The emphatic च glued to a day goes with it, and other endings are not read")
  func dayParticle() {
    let days: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("आजच रिपोर्ट पाठवा", "रिपोर्ट पाठवा", 0, "आजच"),
      ("रिपोर्ट आजच पाठवा", "रिपोर्ट पाठवा", 0, "आजच"),
      ("रिपोर्ट आजच", "रिपोर्ट", 0, "आजच"),
      ("उद्याच जायचे आहे", "जायचे आहे", 1, "उद्याच"),
      ("सोमवारीच मीटिंग", "मीटिंग", 6, "सोमवारीच"),
      ("उद्यापासून जिम सुरू करा", "जिम सुरू करा", 1, "उद्यापासून"),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // An ending the vocabulary does not list leaves the day word unread, and
    // so does a genitive: "उद्याची मीटिंग" is tomorrow's meeting.
    expectLinesUnread(
      ["उद्यादेखील जायचे", "आजसुद्धा पाठवा", "उद्याची मीटिंग", "उद्याचे जेवण", "आजचा अहवाल", "आजची बातमी"],
      languages: ["mr"])
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "या मंगळवारी" is today.
    let names: [(name: String, offset: Int)] = [
      ("बुधवार", 1), ("गुरुवार", 2), ("गुरूवार", 2), ("शुक्रवार", 3), ("शनिवार", 4), ("रविवार", 5), ("सोमवार", 6),
      ("मंगळवार", 7),
    ]
    for weekday in names {
      for text in ["फोन करा \(weekday.name)", "फोन करा \(weekday.name)ी", "फोन करा \(weekday.name)ला"] {
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "फोन करा", "\(text): title")
      }
    }
    let modified: [(text: String, offset: Int)] = [
      ("फोन करा या शुक्रवारी", 3), ("फोन करा या मंगळवारी", 0), ("फोन करा या शनिवारी", 4),
      ("फोन करा या सोमवारी", 6), ("फोन करा ह्या शुक्रवारी", 3), ("फोन करा पुढच्या सोमवारी", 6),
      ("फोन करा पुढच्या मंगळवारी", 7), ("फोन करा पुढच्या शुक्रवारी", 10), ("फोन करा पुढच्या शनिवारी", 11),
      ("फोन करा पुढच्या रविवारी", 12), ("फोन करा पुढील शुक्रवारी", 10), ("फोन करा येत्या शुक्रवारी", 3),
      ("फोन करा येत्या मंगळवारी", 7), ("फोन करा येणाऱ्या शुक्रवारी", 3), ("फोन करा आगामी शुक्रवारी", 3),
      ("फोन करा या आठवड्यात शुक्रवारी", 3), ("फोन करा पुढच्या आठवड्यात सोमवारी", 6),
      ("फोन करा पुढच्या आठवड्यात शुक्रवारी", 10), ("फोन करा शुक्रवारसाठी", 3),
      ("फोन करा पुढच्या शुक्रवारसाठी", 10), ("फोन करा शुक्रवारपासून", 3),
    ]
    for line in modified {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text)")
      #expect(parsed.title == "फोन करा", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    let opening = parse("शुक्रवारी आईला फोन करा")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "आईला फोन करा")
    // "या आठवड्यात" alone names no single day.
    expectLinesUnread(["फोन करा या आठवड्यात"], languages: ["mr"])
  }

  @Test("The weekend: this one, next week's, and today when it is already here")
  func weekend() {
    for text in [
      "वीकेंड", "वीकेंडला", "या वीकेंडला", "वीकएंड", "वीक एंड", "वीकेन्ड", "आठवडा अखेर", "आठवडाअखेर",
      "आठवड्याच्या शेवटी", "आठवड्याच्या अखेरीस", "शनिवार-रविवार", "शनिवार रविवार", "शनिवार आणि रविवार",
    ] {
      let parsed = parse("फोन करा \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "फोन करा", "\(text): title")
    }
    for text in ["पुढच्या वीकेंडला", "पुढील वीकेंडला"] {
      #expect(parse("फोन करा \(text)").plannedDayOffset == 11, "\(text)")
    }
    // On a Saturday or a Sunday the weekend is already here.
    #expect(parse("फोन करा वीकेंडला", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("फोन करा वीकेंडला", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("फोन करा वीकेंडला", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("फोन करा पुढच्या वीकेंडला", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
  }

  @Test("Written dates: every month, in the spellings people type, with a year, a label, an ending, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("5 जानेवारी", "2027-01-05"), ("5 फेब्रुवारी", "2027-02-05"), ("5 फेब्रुअरी", "2027-02-05"),
      ("5 मार्च", "2027-03-05"), ("5 एप्रिल", "2027-04-05"), ("5 एप्रील", "2027-04-05"), ("5 मे", "2027-05-05"),
      ("5 जून", "2027-06-05"), ("5 जुलै", "2027-07-05"), ("5 ऑगस्ट", "2027-08-05"), ("5 आगस्ट", "2027-08-05"),
      ("5 सप्टेंबर", "2027-09-05"), ("5 सप्टेम्बर", "2027-09-05"), ("5 ऑक्टोबर", "2026-10-05"),
      ("5 ऑक्टोंबर", "2026-10-05"), ("5 नोव्हेंबर", "2026-11-05"), ("5 नोव्हेम्बर", "2026-11-05"),
      ("5 डिसेंबर", "2026-12-05"), ("5 डिसेम्बर", "2026-12-05"), ("22 सप्टेंबर", "2026-09-22"),
      ("५ मे", "2027-05-05"), ("5 जाने", "2027-01-05"), ("5 फेब्रु", "2027-02-05"), ("5 एप्रि", "2027-04-05"),
      ("5 ऑग", "2027-08-05"), ("5 सप्टें", "2027-09-05"), ("5 ऑक्टो", "2026-10-05"), ("5 ऑक्टो.", "2026-10-05"),
      ("5 नोव्हें", "2026-11-05"), ("5 डिसें", "2026-12-05"), ("5 मेला", "2027-05-05"), ("5 मे रोजी", "2027-05-05"),
      ("5 मेपासून", "2027-05-05"), ("5 मेसाठी", "2027-05-05"), ("5 मे 2027", "2027-05-05"),
      ("5 मे 2028", "2028-05-05"), ("5 मे, 2028", "2028-05-05"), ("5 मे 2028 रोजी", "2028-05-05"),
      ("15 ऑक्टोबर, 2026 रोजी", "2026-10-15"), ("तारीख 5 मे", "2027-05-05"), ("दिनांक: 5 मे", "2027-05-05"),
      ("सोमवार, 5 ऑक्टोबर", "2026-10-05"), ("1 जानेवारी 2027", "2027-01-01"), ("15 तारखेला", "2026-10-15"),
      ("5 तारखेला", "2026-10-05"), ("5 तारखेस", "2026-10-05"), ("15/10/2026", "2026-10-15"),
      ("15.10.2026", "2026-10-15"), ("15-10-2026", "2026-10-15"), ("15.10.", "2026-10-15"),
      ("तारीख 15/10", "2026-10-15"), ("दिनांक 15.10", "2026-10-15"), ("15/10 ला", "2026-10-15"),
      ("15/10ला", "2026-10-15"), ("15/10 रोजी", "2026-10-15"), ("१५/१०/२०२६", "2026-10-15"),
    ]
    for line in dates {
      let text = "आईला फोन करा \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "आईला फोन करा", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
  }

  @Test("A month needs its day before it, and a date in digits alone, the Marathi calendar, or a day the month lacks is no date")
  func unreadDates() {
    expectLinesUnread(
      [
        // The Marathi calendar's months are not Gregorian dates.
        "फोन करा 5 चैत्र", "सण 5 श्रावण", "पूजा 5 कार्तिक",
        // A month alone, a month before its day, and a day of the month alone.
        "सुट्टी मे मध्ये", "फोन करा मे 5", "फोन करा सप्टेंबर 5", "भाडे 5 तारीख",
        // Digits only with no label and no ending, and a day the month does not have.
        "फोन करा 5/10", "फोन करा 5.10", "फोन करा 15-10", "फोन करा 31 एप्रिल", "फोन करा 30 फेब्रुवारी",
        "फोन करा 32 मे",
      ], languages: ["mr"])
    // A name that looks like a month is left alone beside a date.
    let name = parse("मे चा वाढदिवस 5 मे")
    #expect(name.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(name.title == "मे चा वाढदिवस")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("सुट्टी", "3 ते 5 मार्च", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 ते 5 मार्चपर्यंत", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 ते 5 मार्च पर्यंत", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 मार्च ते 5 मार्च", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 मार्चपासून 5 मार्चपर्यंत", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 मार्च पासून 5 मार्च पर्यंत", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "30 जानेवारी ते 2 फेब्रुवारी", "2027-01-30", "2027-02-02"),
        ("सुट्टी", "3-5 मार्च", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3–5 मार्च", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 मार्च - 5 मार्च", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 ते 5 मार्च 2027", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "3 ते 5 मार्च दरम्यान", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "३ ते ५ मार्च", "2027-03-03", "2027-03-05"),
        ("कुटुंबासह सुट्टी", "3 ते 5 मार्च", "2027-03-03", "2027-03-05"),
        ("सुट्टी", "25 सप्टेंबर ते 3 ऑक्टोबर", "2026-09-25", "2026-10-03"),
        ("सुट्टी", "30 डिसेंबर ते 2 जानेवारी", "2026-12-30", "2027-01-02"),
        ("परिषद", "12-14 ऑक्टोबर", "2026-10-12", "2026-10-14"),
      ], languages: ["mr"])
  }

  @Test("A range whose end is not after its start, or that names no month, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "सुट्टी 5 ते 3 मार्च", "सुट्टी 3 मार्च ते 3 मार्च", "सुट्टी 5-3 मार्च", "सुट्टी 5 मार्च ते 3 मार्च",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "सुट्टी 3 ते 5",
        // A range in the past, or one that a genitive follows, may be an event
        // the task only prepares for.
        "3 ते 5 मार्च सुट्टी होती", "5 ते 8 मेची सुट्टी", "3 ते 5 मार्चची सुट्टी",
      ], languages: ["mr"])
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 मार्च")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("Sprint", "12-20 मार्च", "2027-03-12", "2027-03-20")], languages: ["mr"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("सुट्टी 3 ते 5 मार्च उद्या")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "सुट्टी उद्या")
    let timed = parse("सुट्टी 3 ते 5 मार्च संध्याकाळी 6 वाजता")
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "सुट्टी")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("रिपोर्ट सोमवार ते बुधवार")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "रिपोर्ट")
    #expect(span.phrases.map(\.text) == ["सोमवार ते बुधवार"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("प्रवास शुक्रवार ते सोमवार", 3, 6), ("प्रवास शनिवार ते रविवार", 4, 5),
      ("प्रवास शुक्रवार ते रविवारपर्यंत", 3, 5), ("प्रवास शुक्रवार ते रविवार पर्यंत", 3, 5),
      ("प्रवास शुक्रवारपासून रविवारपर्यंत", 3, 5), ("प्रवास शुक्रवारी ते रविवारी", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("शिबिर मंगळवार ते गुरुवार", 7, 9), ("शिबिर बुधवार ते शुक्रवार", 1, 3),
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
        "जिम सोमवार ते शुक्रवार", "प्रशिक्षण सोमवार ते शुक्रवारपर्यंत", "प्रशिक्षण सोमवार ते शुक्रवार पर्यंत",
        "प्रशिक्षण सोमवारपासून शुक्रवारपर्यंत",
      ], languages: ["mr"])
    // A span in the past, or one that a genitive follows, is no plan.
    expectLinesUnread(
      ["सोमवार ते बुधवारची सुट्टी", "सोमवार ते बुधवार सुट्टी होती", "सोमवार ते बुधवारपर्यंतची सुट्टी"],
      languages: ["mr"])
  }

  // MARK: - Due days

  @Test("Due days: पर्यंत, पूर्वी, आधी, अंतिम तारीख, and देय")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("रिपोर्ट पाठवा शुक्रवारपर्यंत", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा शुक्रवार पर्यंत", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा शुक्रवारपूर्वी", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा शुक्रवारच्या आधी", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा शुक्रवार आधी", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा मंगळवारपर्यंत", "रिपोर्ट पाठवा", 7),
      ("रिपोर्ट पाठवा पुढच्या शुक्रवारपर्यंत", "रिपोर्ट पाठवा", 10),
      ("रिपोर्ट पाठवा या शुक्रवारपर्यंत", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा उद्यापर्यंत", "रिपोर्ट पाठवा", 1),
      ("रिपोर्ट पाठवा परवापर्यंत", "रिपोर्ट पाठवा", 2),
      ("रिपोर्ट पाठवा उद्या संध्याकाळपर्यंत", "रिपोर्ट पाठवा", 1),
      ("रिपोर्ट पाठवा आज संध्याकाळपर्यंत", "रिपोर्ट पाठवा", 0),
      ("रिपोर्ट पाठवा आज रात्रीपर्यंत", "रिपोर्ट पाठवा", 0),
      ("उद्या सकाळपर्यंत रिपोर्ट पाठवा", "रिपोर्ट पाठवा", 1),
      ("रिपोर्ट पाठवा 5 मेपर्यंत", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा 5 मेपूर्वी", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा 5 मे पर्यंत", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा 5 तारखेपर्यंत", "रिपोर्ट पाठवा", captureDayOffset("2026-10-05")),
      ("रिपोर्ट पाठवा 15 ऑक्टोबरपर्यंत", "रिपोर्ट पाठवा", captureDayOffset("2026-10-15")),
      ("रिपोर्ट पाठवा अंतिम तारीख 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा अंतिम तारीख: 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("अंतिम तारीख: 5 मे रिपोर्ट पाठवा", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा शेवटचा दिनांक 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा शेवटची तारीख 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा अंतिम मुदत 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा देय तारीख 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा देय दिनांक 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा देय: 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा अंतिम तारीख 5 मे आहे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा अंतिम तारीख: शुक्रवार", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा डेडलाइन: 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा डेडलाईन 5 मे", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("डेडलाइन शुक्रवार रिपोर्ट पाठवा", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा शुक्रवारी देय", "रिपोर्ट पाठवा", 3),
      ("रिपोर्ट पाठवा 5 मे रोजी देय", "रिपोर्ट पाठवा", captureDayOffset("2027-05-05")),
      ("रिपोर्ट पाठवा आज देय", "रिपोर्ट पाठवा", 0),
      ("रिपोर्ट पाठवा उद्या देय", "रिपोर्ट पाठवा", 1),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("रिपोर्ट पाठवा शुक्रवारपर्यंत उद्या")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "रिपोर्ट पाठवा")
  }

  @Test("\"आजपर्यंत\" and \"आज पर्यंत\" mean \"so far\", and a deadline that a genitive follows is no deadline")
  func notDueDays() {
    expectLinesUnread(
      [
        "रिपोर्ट आजपर्यंत", "रिपोर्ट आज पर्यंत", "रिपोर्ट आज पूर्वी", "रिपोर्ट शुक्रवारपर्यंतचा", "शुक्रवारपर्यंतचा रिपोर्ट",
        "रिपोर्ट शुक्रवारपर्यंतची मीटिंग",
      ], languages: ["mr"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "रिपोर्ट पाठवा 5 वाजेपर्यंत", "रिपोर्ट पाठवा संध्याकाळी 5 वाजेपूर्वी", "रिपोर्ट पाठवा 18:00 पर्यंत",
        "रिपोर्ट पाठवा 5 वाजल्यानंतर", "रिपोर्ट पाठवा 5:30 वाजेपर्यंत", "रिपोर्ट पाठवा साडेपाच वाजेपर्यंत",
        "रिपोर्ट पाठवा पाच वाजेपर्यंत", "रिपोर्ट पाठवा 5 वाजण्यापूर्वी", "रिपोर्ट पाठवा 5 वाजण्याआधी",
        "रिपोर्ट पाठवा 5 वाजेच्या आधी", "रिपोर्ट पाठवा 3 PM पर्यंत", "रिपोर्ट पाठवा मध्यरात्रीपर्यंत",
      ], languages: ["mr"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("रिपोर्ट पाठवा शुक्रवारी संध्याकाळी 5 वाजेपर्यंत")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "रिपोर्ट पाठवा संध्याकाळी 5 वाजेपर्यंत")
    let tomorrow = parse("रिपोर्ट पाठवा उद्या 5 वाजेपर्यंत")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "रिपोर्ट पाठवा 5 वाजेपर्यंत")
    // A planned day beside the clock deadline reads, and the clock stays.
    let day = parse("रिपोर्ट पाठवा 5 वाजेपर्यंत उद्या")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    #expect(day.title == "रिपोर्ट पाठवा 5 वाजेपर्यंत")
    // A time range that ends in "वाजेपर्यंत" is still a range.
    let range = parse("मीटिंग 2 वाजेपासून 4 वाजेपर्यंत")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "मीटिंग")
    // Without Marathi, English reads the clock time and leaves the word.
    let english = parse("रिपोर्ट पाठवा 18:00 पर्यंत", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "रिपोर्ट पाठवा पर्यंत")
  }

  // MARK: - Times

  @Test("Clock times: वाजता after the hour, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("मीटिंग 5 वाजता", "मीटिंग", 17 * 60), ("मीटिंग 5वाजता", "मीटिंग", 17 * 60),
      ("मीटिंग 5:30 वाजता", "मीटिंग", 17 * 60 + 30), ("मीटिंग 5.30 वाजता", "मीटिंग", 17 * 60 + 30),
      ("मीटिंग ५ वाजता", "मीटिंग", 17 * 60), ("मीटिंग ठीक 5 वाजता", "मीटिंग", 17 * 60),
      ("मीटिंग सुमारे 5 वाजता", "मीटिंग", 17 * 60), ("मीटिंग साधारण 5 वाजता", "मीटिंग", 17 * 60),
      ("मीटिंग जवळपास 5 वाजता", "मीटिंग", 17 * 60), ("मीटिंग अंदाजे 5 वाजता", "मीटिंग", 17 * 60),
      ("5 वाजताची मीटिंग", "मीटिंग", 17 * 60), ("5 वाजताचे जेवण", "जेवण", 17 * 60),
      ("संध्याकाळी 5 वाजताची फ्लाइट", "फ्लाइट", 17 * 60),
      ("मीटिंग सकाळी 9 वाजता", "मीटिंग", 9 * 60), ("मीटिंग सकाळी 9:30 वाजता", "मीटिंग", 9 * 60 + 30),
      ("मीटिंग सकाळच्या 7 वाजता", "मीटिंग", 7 * 60), ("मीटिंग पहाटे 4 वाजता", "मीटिंग", 4 * 60),
      ("मीटिंग दुपारी 12 वाजता", "मीटिंग", 12 * 60), ("मीटिंग दुपारी 1 वाजता", "मीटिंग", 13 * 60),
      ("मीटिंग दुपारी 2 वाजता", "मीटिंग", 14 * 60), ("मीटिंग दुपारी 3:30 वाजता", "मीटिंग", 15 * 60 + 30),
      ("मीटिंग संध्याकाळी 5 वाजता", "मीटिंग", 17 * 60), ("मीटिंग संध्याकाळी 7 वाजता", "मीटिंग", 19 * 60),
      ("मीटिंग सायंकाळी 6 वाजता", "मीटिंग", 18 * 60), ("मीटिंग संध्याकाळच्या 6 वाजता", "मीटिंग", 18 * 60),
      ("मीटिंग रात्री 10 वाजता", "मीटिंग", 22 * 60), ("मीटिंग रात्री 9 वाजता", "मीटिंग", 21 * 60),
      ("मीटिंग रात्री 11 वाजता", "मीटिंग", 23 * 60), ("मीटिंग रात्रीच्या 10 वाजता", "मीटिंग", 22 * 60),
      ("मीटिंग रात्री ठीक 10 वाजता", "मीटिंग", 22 * 60), ("मीटिंग सकाळी लवकर 6 वाजता", "मीटिंग", 6 * 60),
      ("मीटिंग ठीक सकाळी 6 वाजता", "मीटिंग", 6 * 60), ("मीटिंग 3:30 PM वाजता", "मीटिंग", 15 * 60 + 30),
      ("मीटिंग 3 AM वाजता", "मीटिंग", 3 * 60), ("मीटिंग 17:30", "मीटिंग", 17 * 60 + 30),
      ("मीटिंग संध्याकाळी 5:30", "मीटिंग", 17 * 60 + 30), ("मीटिंग रात्री 10.30", "मीटिंग", 22 * 60 + 30),
      ("मीटिंग सकाळी 9:15", "मीटिंग", 9 * 60 + 15),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day after वाजता is not read, and it names the half of the
    // day of the hour all the same.
    let after = parse("मीटिंग 5 वाजता सकाळी")
    #expect(after.startMinutes == 5 * 60)
    #expect(after.title == "मीटिंग सकाळी")
    let evening = parse("मीटिंग 7 वाजता संध्याकाळी")
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "मीटिंग संध्याकाळी")
    // The part of the day written before the hour wins over one written after it.
    let both = parse("मीटिंग सकाळी 9 वाजता संध्याकाळी")
    #expect(both.startMinutes == 9 * 60)
    #expect(both.title == "मीटिंग संध्याकाळी")
    // Twelve in the morning is no time, and neither is 24 o'clock.
    #expect(parse("मीटिंग सकाळी 12 वाजता").startMinutes == nil)
    #expect(parse("मीटिंग 24 वाजता").startMinutes == nil)
  }

  @Test("Clock fractions: साडे, सव्वा, पावणे, दीड, and अडीच")
  func clockFractions() {
    let fractions: [(text: String, minutes: Int)] = [
      ("मीटिंग साडेपाच वाजता", 17 * 60 + 30), ("मीटिंग साडे पाच वाजता", 17 * 60 + 30),
      ("मीटिंग साडे 5 वाजता", 17 * 60 + 30), ("मीटिंग साडे ५ वाजता", 17 * 60 + 30),
      ("मीटिंग सव्वापाच वाजता", 17 * 60 + 15), ("मीटिंग सव्वा पाच वाजता", 17 * 60 + 15),
      ("मीटिंग पावणेसहा वाजता", 17 * 60 + 45), ("मीटिंग पावणे सहा वाजता", 17 * 60 + 45),
      ("मीटिंग दीड वाजता", 13 * 60 + 30), ("मीटिंग दिड वाजता", 13 * 60 + 30),
      ("मीटिंग अडीच वाजता", 14 * 60 + 30), ("मीटिंग अडिच वाजता", 14 * 60 + 30),
      ("मीटिंग साडेतीन वाजता", 15 * 60 + 30), ("मीटिंग सव्वादोन वाजता", 14 * 60 + 15),
      ("मीटिंग पावणेचार वाजता", 15 * 60 + 45), ("मीटिंग पावणेएक वाजता", 12 * 60 + 45),
      ("मीटिंग पावणेबारा वाजता", 11 * 60 + 45), ("मीटिंग सकाळी साडेनऊ वाजता", 9 * 60 + 30),
      ("मीटिंग सकाळी पावणेदहा वाजता", 9 * 60 + 45), ("मीटिंग सकाळी सव्वा आठ वाजता", 8 * 60 + 15),
      ("मीटिंग संध्याकाळी साडेसहा वाजता", 18 * 60 + 30), ("मीटिंग रात्री पावणेदहा वाजता", 21 * 60 + 45),
    ]
    for line in fractions {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "मीटिंग", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A fraction counts from an hour on the clock face.
    #expect(parse("मीटिंग साडे 13 वाजता").startMinutes == nil)
    #expect(parse("मीटिंग दीड वाजता सकाळी").startMinutes == 90)
  }

  @Test("Clock times with ला glued to the hour: साडेतीनला, दीडला, and an hour with a part of the day")
  func atHour() {
    let times: [(text: String, minutes: Int)] = [
      ("मीटिंग साडेतीनला", 15 * 60 + 30), ("मीटिंग सव्वाचारला", 16 * 60 + 15), ("मीटिंग पावणेचारला", 15 * 60 + 45),
      ("मीटिंग दीडला", 13 * 60 + 30), ("मीटिंग अडीचला", 14 * 60 + 30), ("मीटिंग संध्याकाळी सहाला", 18 * 60),
      ("मीटिंग सकाळी 7 ला", 7 * 60), ("मीटिंग रात्री दहाला", 22 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "मीटिंग", "\(line.text): title")
    }
    // A number with ला and no part of the day is as often a count.
    expectLinesUnread(["मीटिंग सहाला", "मीटिंग 7 ला", "तीनला भेटू"], languages: ["mr"])
  }

  @Test("An hour as a number word is read only before वाजता")
  func numberWordHours() {
    let hours: [(word: String, minutes: Int)] = [
      ("एक", 13 * 60), ("दोन", 14 * 60), ("तीन", 15 * 60), ("चार", 16 * 60), ("पाच", 17 * 60), ("पांच", 17 * 60),
      ("सहा", 18 * 60), ("सात", 7 * 60), ("आठ", 8 * 60), ("नऊ", 9 * 60), ("दहा", 10 * 60), ("अकरा", 11 * 60),
      ("बारा", 12 * 60),
    ]
    for hour in hours {
      let text = "मीटिंग \(hour.word) वाजता"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "मीटिंग", "\(text): title")
    }
    #expect(parse("मीटिंग सकाळी नऊ वाजता").startMinutes == 9 * 60)
    #expect(parse("मीटिंग संध्याकाळी सात वाजता").startMinutes == 19 * 60)
    // A number word is a count anywhere else.
    expectLinesUnread(
      ["मीटिंग पाच", "मीटिंग एक", "तीन लोक येतील", "दोन मित्र", "सात दिवस", "मीटिंग तीन ते पाच"],
      languages: ["mr"])
  }

  @Test("After midnight: रात्री runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("मीटिंग रात्री 2 वाजता")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "मीटिंग")
    let twelve = parse("मीटिंग रात्री 12 वाजता")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    for text in ["मीटिंग मध्यरात्री", "मीटिंग मध्यरात्रीला", "मीटिंग ठीक मध्यरात्री"] {
      let midnight = parse(text)
      #expect(midnight.startMinutes == 0, "\(text)")
      #expect(midnight.plannedDayOffset == 1, "\(text)")
      #expect(midnight.title == "मीटिंग", "\(text): title")
    }
    // The night counts from the evening: 6 to 11 is the evening's.
    #expect(parse("मीटिंग रात्री 6 वाजता").startMinutes == 18 * 60)
    #expect(parse("मीटिंग रात्री 6 वाजता").plannedDayOffset == nil)
    // A named day keeps the time on its own night: "उद्या रात्री 1 वाजता" is 01:00 of the day after.
    let tomorrow = parse("उद्या रात्री 1 वाजता झोपणे")
    #expect(tomorrow.startMinutes == 60)
    #expect(tomorrow.plannedDayOffset == 2)
    #expect(tomorrow.title == "झोपणे")
    let named = parse("सोमवारी रात्री 12 वाजता फ्लाइट")
    #expect(named.startMinutes == 0)
    #expect(named.plannedDayOffset == 7)
    #expect(named.title == "फ्लाइट")
    // A repeat moves to the day after, so the rule and the time agree.
    let repeating = parse("दर शुक्रवारी रात्री 12 वाजता फ्लाइट")
    #expect(repeating.startMinutes == 0)
    #expect(repeating.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(repeating.recurrenceStartOffset == 4)
    #expect(repeating.title == "फ्लाइट")
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("मीटिंग 1 वाजता").startMinutes == 13 * 60)
    #expect(parse("मीटिंग 3 वाजता").startMinutes == 15 * 60)
    #expect(parse("मीटिंग 6 वाजता").startMinutes == 18 * 60)
    #expect(parse("मीटिंग 7 वाजता").startMinutes == 7 * 60)
    #expect(parse("मीटिंग 9 वाजता").startMinutes == 9 * 60)
    #expect(parse("मीटिंग 11 वाजता").startMinutes == 11 * 60)
    #expect(parse("मीटिंग 12 वाजता").startMinutes == 12 * 60)
    #expect(parse("मीटिंग 13 वाजता").startMinutes == 13 * 60)
    #expect(parse("मीटिंग 06:30 वाजता").startMinutes == 6 * 60 + 30)
    #expect(parse("मीटिंग 03:00 वाजता").startMinutes == 3 * 60)
    #expect(parse("मीटिंग 3:00 वाजता").startMinutes == 15 * 60)
    // A part of the day names the half of the day either way.
    #expect(parse("मीटिंग सकाळी 5 वाजता").startMinutes == 5 * 60)
    #expect(parse("मीटिंग संध्याकाळी 5 वाजता").startMinutes == 17 * 60)
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("सकाळची सैर 6 वाजता", "सकाळची सैर", 6 * 60), ("6 वाजता सकाळची सैर", "सकाळची सैर", 6 * 60),
      ("सकाळची सैर 5 वाजता", "सकाळची सैर", 5 * 60), ("रात्रीचे जेवण 8 वाजता", "रात्रीचे जेवण", 20 * 60),
      ("रात्रीचे जेवण 6 वाजता", "रात्रीचे जेवण", 18 * 60), ("रात्रीचे जेवण साडेआठ वाजता", "रात्रीचे जेवण", 20 * 60 + 30),
      ("रात्रीचे औषध 10 वाजता", "रात्रीचे औषध", 22 * 60), ("संध्याकाळचा चहा 5 वाजता", "संध्याकाळचा चहा", 17 * 60),
      ("दुपारचे जेवण 1 वाजता", "दुपारचे जेवण", 13 * 60), ("दुपारचे जेवण 2 वाजता", "दुपारचे जेवण", 14 * 60),
      // The 24-hour clock is read as written: a leading zero, or 13 and later.
      ("रात्रीचे जेवण 20:00 वाजता", "रात्रीचे जेवण", 20 * 60),
      ("रात्रीची ड्युटी 06:30 वाजता", "रात्रीची ड्युटी", 6 * 60 + 30),
      // Noon is no morning hour, so a morning's 12 stays as written.
      ("सकाळची बैठक 12 वाजता", "सकाळची बैठक", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The part of the day may come from the day phrase, and the day is read too.
    let dinner = parse("आज रात्रीचे जेवण 8 वाजता")
    #expect(dinner.plannedDayOffset == 0)
    #expect(dinner.startMinutes == 20 * 60)
    #expect(dinner.title == "रात्रीचे जेवण")
    // Two parts that differ leave the hour as it reads alone, and "मध्यरात्री"
    // names no part.
    #expect(parse("सकाळची औषधे संध्याकाळचा चहा 5 वाजता").startMinutes == 17 * 60)
    #expect(parse("मध्यरात्री जेवण 5 वाजता").startMinutes == 17 * 60)
  }

  @Test("Time ranges: ते with वाजता, a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("मीटिंग 3 ते 5 वाजता", 15 * 60, 120), ("मीटिंग 3 वाजता ते 5 वाजता", 15 * 60, 120),
      ("मीटिंग 3 वाजेपासून 5 वाजेपर्यंत", 15 * 60, 120), ("मीटिंग सकाळी 9 ते 11 वाजता", 9 * 60, 120),
      ("मीटिंग सकाळी 9 ते 11 वाजेपर्यंत", 9 * 60, 120), ("मीटिंग संध्याकाळी 5 ते 7 वाजता", 17 * 60, 120),
      ("मीटिंग रात्री 8 ते 10 वाजता", 20 * 60, 120), ("मीटिंग दोन ते चार वाजता", 14 * 60, 120),
      ("मीटिंग २ ते ४ वाजता", 14 * 60, 120), ("मीटिंग 2-4 वाजता", 14 * 60, 120),
      ("मीटिंग 2–4 वाजता", 14 * 60, 120), ("मीटिंग 14:00 ते 16:00", 14 * 60, 120),
      ("मीटिंग 9:30 ते 10:30 पर्यंत", 9 * 60 + 30, 60), ("मीटिंग 9:30 ते 10:30पर्यंत", 9 * 60 + 30, 60),
      ("मीटिंग 14:00-16:00", 14 * 60, 120), ("मीटिंग सकाळी 9:00 ते संध्याकाळी 5:00", 9 * 60, 480),
      ("मीटिंग सकाळी 9 वाजेपासून संध्याकाळी 5 वाजेपर्यंत", 9 * 60, 480), ("मीटिंग 9 ते 5 वाजता", 9 * 60, 480),
      ("मीटिंग 10 ते 12 वाजता", 10 * 60, 120), ("मीटिंग 11 ते 1 वाजता", 11 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "मीटिंग", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The end carries वाजता: two bare numbers are no range.
    expectLinesUnread(["मीटिंग 3 ते 5", "मीटिंग तीन ते पाच"], languages: ["mr"])
    // A length written in the line wins over the span of the range.
    let named = parse("मीटिंग 3 ते 5 वाजता 30 मिनिटे")
    #expect(named.startMinutes == 15 * 60)
    #expect(named.estimatedMinutes == 30)
    #expect(named.title == "मीटिंग")
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amounts() {
    expectLinesUnread(
      [
        "3 लोकांसोबत मीटिंग", "३ लोकांसोबत मीटिंग", "मीटिंगला 3 लोक येतील", "5 पुस्तके खरेदी करणे",
        "10 पाने वाचणे", "2 किलो साखर आणणे", "12 अंडी आणणे", "500 रुपयांचे बिल भरणे", "₹500 चे बिल", "बिल ₹500",
        "5 डॉलर खर्च", "20% सवलत", "20 % सवलत", "2 तासिका शिकवणे",
      ], languages: ["mr"])
    // The words around an amount still read.
    let bill = parse("500 रुपयांचे बिल भरणे उद्या")
    #expect(bill.plannedDayOffset == 1)
    #expect(bill.title == "500 रुपयांचे बिल भरणे")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("30 मिनिटे", 30), ("30 मिनिटं", 30), ("30 मिनिट", 30), ("45 मिनिटे", 45), ("90 मिनिटे", 90), ("2 मिनिटे", 2),
      ("४५ मिनिटे", 45), ("30 मिनीट", 30), ("2 तास", 120), ("1 तास", 60), ("1.5 तास", 90), ("1 तास 30 मिनिटे", 90),
      ("1 तास आणि 30 मिनिटे", 90), ("अर्धा तास", 30), ("दीड तास", 90), ("दिड तास", 90), ("अडीच तास", 150),
      ("सव्वा तास", 75), ("पाऊण तास", 45), ("साडेतीन तास", 210), ("साडे तीन तास", 210), ("पावणेदोन तास", 105),
      ("सव्वा 2 तास", 135), ("दोन तास", 120), ("एक तास", 60), ("वीस मिनिटे", 20), ("पंधरा मिनिटे", 15),
      ("तीस मिनिटे", 30), ("पंचेचाळीस मिनिटे", 45), ("दहा मिनिटे", 10), ("सुमारे 2 तास", 120),
      ("साधारण 30 मिनिटे", 30), ("जवळपास 20 मिनिटे", 20), ("अंदाजे 20 मिनिटे", 20), ("अर्ध्या तासासाठी", 30),
      ("2 तासांसाठी", 120), ("30 मिनिटांसाठी", 30),
    ]
    for line in lengths {
      let text = "रिपोर्ट लिहा \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "रिपोर्ट लिहा", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The genitive that goes with a length is read with it.
    let meeting = parse("30 मिनिटांची मीटिंग")
    #expect(meeting.estimatedMinutes == 30)
    #expect(meeting.title == "मीटिंग")
    #expect(meeting.phrases.map(\.text) == ["30 मिनिटांची"])
    let work = parse("2 तासांचे काम")
    #expect(work.estimatedMinutes == 120)
    #expect(work.title == "काम")
    let hour = parse("1 तासाचे काम")
    #expect(hour.estimatedMinutes == 60)
    #expect(hour.title == "काम")
    // A time and a length together.
    let both = parse("मीटिंग 5 वाजता 45 मिनिटांसाठी")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "मीटिंग")
  }

  @Test("An amount before आधी, नंतर, or आत, after दर, or with an ending of another word, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "रिपोर्ट लिहा 2 तास आधी", "रिपोर्ट लिहा 15 मिनिटे नंतर", "रिपोर्ट लिहा 30 मिनिटे आधी",
        "रिपोर्ट लिहा 2 तासांच्या आत", "रिपोर्ट लिहा दर 2 तास", "रिपोर्ट लिहा दर 30 मिनिटे",
        "रिपोर्ट लिहा 2 तासांनी", "रिपोर्ट लिहा 15 मिनिटांनी", "रिपोर्ट लिहा 2 तासात", "रिपोर्ट लिहा 2 तासांत",
        "रिपोर्ट लिहा 2 तासांमध्ये", "रिपोर्ट लिहा किमान 2 तास", "रिपोर्ट लिहा कमीत कमी 2 तास",
        "रिपोर्ट लिहा जास्तीत जास्त 2 तास", "रिपोर्ट लिहा दिवसातून 2 तास", "रिपोर्ट लिहा 2 तासांपेक्षा जास्त",
        // A range of amounts, an hour as a noun, and an amount no task takes.
        "रिपोर्ट लिहा 2 ते 3 तास", "रिपोर्ट लिहा 2-3 तास", "रिपोर्ट लिहा 5 मिनिटे ते 10 मिनिटे",
        "रिपोर्ट लिहा तास", "तासभर वाचन", "रिपोर्ट लिहा 25 तास", "रिपोर्ट लिहा 0 मिनिटे",
      ], languages: ["mr"])
    // The phrase around an amount that is no length still reads.
    let day = parse("रिपोर्ट लिहा 2 तास आधी उद्या")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "रिपोर्ट लिहा 2 तास आधी")
    let time = parse("मीटिंग उद्या 3 वाजता 2 तास आधी")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "मीटिंग 2 तास आधी")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("दररोज", daily), ("रोज", daily), ("नित्य", daily), ("दर दिवशी", daily), ("प्रत्येक दिवशी", daily),
      ("प्रत्येक दिवस", daily), ("रोज सकाळी", daily), ("रोज संध्याकाळी", daily), ("दर रात्री", daily),
      ("दिवसातून एकदा", daily), ("दिवसातून एक वेळ", daily), ("दर आठवड्याला", weekly), ("प्रत्येक आठवडा", weekly),
      ("आठवड्यातून एकदा", weekly), ("दर महिन्याला", monthly), ("दरमहा", monthly), ("प्रत्येक महिना", monthly),
      ("महिन्यातून एकदा", monthly), ("दरवर्षी", yearly), ("दर वर्षी", yearly), ("प्रत्येक वर्षी", yearly),
      ("वर्षातून एकदा", yearly), ("दर 2 दिवसांनी", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("दर दोन दिवसांनी", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("दर दुसऱ्या दिवशी", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("प्रत्येक इतर दिवशी", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("दिवसाआड", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("एक दिवसाआड", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("दर पंधरा दिवसांनी", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("दर ३ दिवसांनी", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("दर 3 आठवड्यांनी", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("दर दोन आठवड्यांनी", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("दर दुसऱ्या आठवड्याला", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("प्रत्येक 2 आठवडे", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("आठवड्याआड", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("दर 3 महिन्यांनी", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("दर तीन महिन्यांनी", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("महिन्याआड", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("दर 5 वर्षांनी", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("वर्षाआड", TaskRecurrenceRule(freq: .yearly, interval: 2)),
    ]
    for line in cadences {
      let text = "औषध घ्या \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "औषध घ्या", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
    // A count before "दिवसाआड" is another interval and is not read.
    #expect(parse("औषध घ्या दोन दिवसाआड").recurrence == nil)
  }

  @Test("Weekday repeats: दर सोमवारी, lists of days, the weekend, and the working days")
  func weekdayRepeats() {
    let coming = parse("जिम दर सोमवारी")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "जिम")
    #expect(coming.plannedDayOffset == nil)
    #expect(parse("जिम दर सोमवार").recurrence == monday)
    #expect(parse("जिम दर आठवड्याला सोमवारी").recurrence == monday)
    #expect(parse("जिम प्रत्येक सोमवारी").recurrence == monday)

    let lists: [(text: String, days: [String])] = [
      ("जिम दर सोमवारी आणि गुरुवारी", ["MO", "TH"]), ("जिम दर सोमवार, बुधवार आणि शुक्रवार", ["MO", "WE", "FR"]),
      ("जिम दर सोमवारी, बुधवारी व शुक्रवारी", ["MO", "WE", "FR"]), ("जिम दर बुधवारी", ["WE"]),
      ("जिम दर शनिवारी", ["SA"]), ("जिम दर रविवारी", ["SU"]),
      ("जिम सोमवारी आणि गुरुवारी दर आठवड्याला", ["MO", "TH"]), ("जिम दर शनिवारी आणि रविवारी", ["SU", "SA"]),
      ("जिम दर वीकेंडला", ["SU", "SA"]), ("जिम प्रत्येक वीकेंडला", ["SU", "SA"]), ("जिम दर शनिवार-रविवारी", ["SU", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "जिम", "\(line.text): title")
    }
    #expect(parse("जिम दर सोमवारी आणि गुरुवारी").recurrenceStartOffset == 2)
    #expect(parse("जिम दर वीकेंडला").recurrenceStartOffset == 4)
    let everyOther = parse("जिम दर दुसऱ्या सोमवारी")
    #expect(everyOther.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]))

    // The working days, written out or as a span of weekdays beside दर or a
    // word for every day.
    for text in [
      "जिम दर कामाच्या दिवशी", "जिम कामाच्या दिवशी", "जिम कामाच्या दिवसांत", "जिम कामाच्या दिवसांमध्ये",
      "जिम रोज कामाच्या दिवशी", "जिम दर सोमवार ते शुक्रवार", "जिम रोज सोमवार ते शुक्रवार",
      "जिम सोमवार ते शुक्रवार दररोज", "जिम सोमवार ते शुक्रवारपर्यंत दररोज", "जिम दर सोमवार ते शुक्रवारपर्यंत",
      "जिम दर सोमवार ते शुक्रवार सकाळी 9 वाजता",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
    #expect(parse("जिम दर सोमवार ते बुधवार").recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE"]))
    #expect(
      parse("जिम दर रविवार ते गुरुवार").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"]))
    // Monday to Friday alone is no repeat.
    #expect(parse("जिम सोमवार ते शुक्रवार").recurrence == nil)
    // A repeat that starts today starts at 0 on its own weekday.
    #expect(parse("जिम दर मंगळवारी").recurrenceStartOffset == 0)
    #expect(parse("जिम दर शुक्रवारी", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("योग रोज सकाळी 6 वाजता", "योग", 6 * 60), ("रोज सकाळी 6 वाजता योग", "योग", 6 * 60),
      ("दर संध्याकाळी 7 वाजता फिरणे", "फिरणे", 19 * 60), ("फिरणे दर संध्याकाळी 7 वाजता", "फिरणे", 19 * 60),
      ("दर रात्री 10:30 औषध", "औषध", 22 * 60 + 30), ("दर रात्री 11 वाजता झोपणे", "झोपणे", 23 * 60),
      ("प्रत्येक सकाळी 5 वाजता योग", "योग", 5 * 60), ("दररोज सकाळी 6 वाजता योग", "योग", 6 * 60),
      ("रोज संध्याकाळी 7 वाजता फिरणे", "फिरणे", 19 * 60), ("दर रात्री वाचन", "वाचन", nil),
      ("रोज सकाळी योग", "योग", nil),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let range = parse("रोज सकाळी 9 ते 11 वाजता अभ्यास")
    #expect(range.recurrence == daily)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "अभ्यास")
    // A line of details alone is no task.
    expectLinesUnread(["दर सकाळी 6 वाजता", "दर संध्याकाळी 7 वाजता"], languages: ["mr"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "भाडे दर महिन्याच्या 5 तारखेला", "भाडे दर महिन्याच्या 5 तारखेस", "भाडे दर महिन्याला 5 तारखेला",
      "भाडे दरमहा 5 तारखेला", "भाडे दर महिन्याची 5 तारीख", "भाडे दर महिन्याच्या ५ तारखेला",
      "भाडे 5 तारखेला दर महिन्याला", "भाडे प्रत्येक महिन्याच्या 5 तारखेला",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text): start")
      #expect(parsed.title == "भाडे", "\(text): title")
    }
    let first = parse("भाडे दर महिन्याच्या पहिल्या तारखेला")
    #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    #expect(first.recurrenceStartOffset == 9)
    // A date with its month name is a date, not a repeat.
    #expect(parse("भाडे दर 5 मे").recurrence == nil)
  }

  @Test("A repeat shorter than a day, and a cadence word that describes a noun, are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        "औषध घ्या दर 2 तासांनी", "औषध घ्या रोजचे काम", "औषध घ्या दरवर्षीचा खर्च", "रोजा ठेवणे", "रोजगार मेळावा",
        "रोजनिशी लिहिणे", "नित्यक्रम पाळणे", "दर महिन्याचा खर्च", "दर आठवड्याची सभा", "दरवाजा रंगवणे",
        "प्रत्येकाने पैसे द्या", "दररोजचे काम",
      ], languages: ["mr"])
    // The weekday after दर with a genitive is an attribute too.
    #expect(parse("दर सोमवारची मीटिंग").recurrence == nil)
  }

  // MARK: - Priorities

  @Test("Priorities: उच्च, मध्यम, and निम्न प्राधान्य, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("उच्च प्राधान्य", .p1), ("उच्चतम प्राधान्य", .p1), ("सर्वोच्च प्राधान्य", .p1), ("प्राधान्य: उच्च", .p1),
      ("प्राधान्य उच्च", .p1), ("जास्त प्राधान्य", .p1), ("मध्यम प्राधान्य", .p2), ("सामान्य प्राधान्य", .p2),
      ("साधारण प्राधान्य", .p2), ("प्राधान्य: मध्यम", .p2), ("निम्न प्राधान्य", .p3), ("निम्नतम प्राधान्य", .p3),
      ("कमी प्राधान्य", .p3), ("सर्वात कमी प्राधान्य", .p3), ("प्राधान्य कमी", .p3), ("प्राधान्य: निम्न", .p3),
      ("उच्च प्राधान्याने", .p1), ("उच्च प्राथमिकता", .p1), ("मध्यम प्राथमिकता", .p2), ("निम्न प्राथमिकता", .p3),
      ("प्राथमिकता: उच्च", .p1),
    ]
    for level in levels {
      let text = "रिपोर्ट पाठवा \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "रिपोर्ट पाठवा", "\(text): title")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let inside = parse("रिपोर्ट उच्च प्राधान्याने पाठवा")
    #expect(inside.priority == .p1)
    #expect(inside.title == "रिपोर्ट पाठवा")

    for word in [
      "तातडीचे", "तातडीचा", "तातडीची", "तातडी", "तातडीने", "अत्यावश्यक", "अर्जंट", "अर्जेंट", "अर्जेन्ट", "ताबडतोब",
      "महत्त्वाचे", "महत्वाचे", "महत्त्वाचा", "महत्त्वाची", "खूप तातडीचे", "अतिशय महत्त्वाचे", "अत्यंत तातडीचे",
    ] {
      let text = "रिपोर्ट पाठवा \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "रिपोर्ट पाठवा", "\(text): title")
    }
    for word in ["तातडीचे", "अत्यावश्यक", "महत्त्वाचे"] {
      for separator in [":", ","] {
        let text = "\(word)\(separator) रिपोर्ट पाठवा"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "रिपोर्ट पाठवा", "\(text): title")
      }
    }
    #expect(parse("रिपोर्ट पाठवा तातडीचे।").title == "रिपोर्ट पाठवा।")
    // An urgent word in the middle, or opening the line with no colon or
    // comma, is a word of the title, and so is a level that describes a noun.
    expectLinesUnread(
      [
        "तातडीची औषधे आणणे", "रिपोर्ट पाठवा तातडीचे आहे", "तातडीने रिपोर्ट पाठवा", "रिपोर्ट पाठवा तातडीनेच",
        "महत्त्वाचे काम पूर्ण करा", "उच्च प्राधान्य असलेली कामे", "कमी प्राधान्य असलेली यादी",
      ], languages: ["mr"])
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("उद्या संध्याकाळी 5 वाजता 30 मिनिटांसाठी मीटिंग #काम")
    #expect(line.title == "मीटिंग")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["काम"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["उद्या", "संध्याकाळी 5 वाजता", "30 मिनिटांसाठी", "#काम"])

    let lines: [(text: String, title: String)] = [
      ("दर सोमवारी सकाळी 9 वाजता जिम", "जिम"), ("शुक्रवारपर्यंत रिपोर्ट पाठवणे तातडीचे", "रिपोर्ट पाठवणे"),
      ("सोमवारी सकाळी 9 ते 11 वाजता मीटिंग", "मीटिंग"), ("5 मे रोजी संध्याकाळी 6 वाजता पार्टी", "पार्टी"),
      ("पुढच्या शुक्रवारपर्यंत 2 तासांचे काम", "काम"), ("उद्या मीटिंग 3 वाजता उच्च प्राधान्य", "मीटिंग"),
      ("रोज सकाळी 7 वाजता औषध", "औषध"), ("आज रात्री 11 वाजता झोपणे", "झोपणे"),
      ("आईला फोन करा उद्या संध्याकाळी 5 वाजता", "आईला फोन करा"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(parse(line.text).phrases.count >= 2, "\(line.text): phrases")
    }
    let friday = parse("शुक्रवारपर्यंत रिपोर्ट पाठवणे तातडीचे")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.priority == .p1)
    let weekly = parse("दर सोमवारी सकाळी 9 वाजता जिम")
    #expect(weekly.recurrence == monday)
    #expect(weekly.startMinutes == 9 * 60)
    let report = parse("पुढच्या शुक्रवारपर्यंत 2 तासांचे काम")
    #expect(report.dueDayOffset == 10)
    #expect(report.estimatedMinutes == 120)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // The short weekday stems are ordinary words and names.
        "रविला फोन करा", "शनि मंदिरात जाणे", "मंगळ ग्रह पाहणे", "गुरु ला नमस्कार", "बुध ग्रह", "शुक्र ग्रह",
        "सोमाला फोन करा",
        // Words that contain a day word.
        "आजकाल मीटिंग", "आज-काल मीटिंग", "उद्यान पाहणे", "परवानगी मागणे", "आजारी मित्राला भेटणे", "आजोबांना फोन करा",
        "उद्योग मेळावा", "आजच्या बातम्या",
        // A day with a genitive after it is an attribute of a noun.
        "सोमवारची मीटिंग", "शुक्रवारचे जेवण", "उद्याची मीटिंग", "उद्याचे जेवण", "आजचा अहवाल",
        // A bound or an amount of days that names no day.
        "रिपोर्ट 3 दिवसांत पाठवा", "3 दिवसांपूर्वीची गोष्ट", "मीटिंगच्या 3 दिवसांनी",
        // A bare number that is a count.
        "3 सफरचंद आणणे", "5 मित्रांना बोलावणे",
      ], languages: ["mr"])
    // Marathi written in Latin letters is not read.
    expectLinesUnread(
      [
        "udya sakali 9 vajta meeting", "aaj sandhyakali phone karne", "parva bhetu", "somvari meeting",
        "dar somvar gym", "2 tas vachan", "shukrvar paryant report",
      ], languages: ["mr"])
    // "आज आले आणणे" has no past-tense word: "आले" is ginger.
    let ginger = parse("आज आले आणणे")
    #expect(ginger.plannedDayOffset == 0)
    #expect(ginger.title == "आले आणणे")
    // A weekday before other words is the day.
    let friday = parse("शुक्रवारी पार्टीची तयारी करा")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "पार्टीची तयारी करा")
  }

  // MARK: - परवा, and the past

  @Test("परवा is the day after tomorrow, and a line in the past tense or after a past word stays unread")
  func tomorrowOrYesterday() {
    let tomorrow = [
      "उद्या मीटिंग आहे", "उद्या जायचे आहे", "उद्या मीटिंग असेल", "उद्यापासून जिम सुरू करा", "रिपोर्ट उद्या पाठवा",
      "उद्या हे काम केले जाईल",
    ]
    for text in tomorrow {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        // The words that say a day is past, or the month's first, second, or last.
        "गेल्या शुक्रवारी मीटिंग", "मागील शुक्रवारी मीटिंग", "मागच्या सोमवारी मीटिंग", "पहिल्या शुक्रवारी मीटिंग",
        "दुसऱ्या शनिवारी सुट्टी", "शेवटच्या शुक्रवारी पार्टी",
        // A past-tense form anywhere in the line.
        "उद्या मीटिंग होती", "परवा मीटिंग होती", "मी परवा गेलो होतो", "उद्या गेले होते", "शुक्रवारी तो आला",
        "आज बैठक झाली", "आज मीटिंग होती", "शुक्रवारी मीटिंग होती",
      ], languages: ["mr"])
    // "गेल्या शुक्रवारी" is a past day, but "शुक्रवारपूर्वी" is a deadline.
    #expect(parse("रिपोर्ट शुक्रवारपूर्वी").dueDayOffset == 3)
    #expect(parse("रिपोर्ट उद्यापूर्वी").dueDayOffset == 1)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // A past statement with no past-tense marker reads as the day after tomorrow:
    // "परवा" names the day before yesterday as well.
    #expect(parse("परवा मी फोन केला").plannedDayOffset == 2)
    // An hour from 1 to 6 with no part of the day is the afternoon.
    #expect(parse("मीटिंग 5 वाजता").startMinutes == 17 * 60)
    // An hour count written with a Latin unit is English's length, even after दर.
    let hours = parse("औषध घ्या दर 2h")
    #expect(hours.estimatedMinutes == 120)
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("हे काम तातडीचे").priority == .p1)
    #expect(parse("हे काम महत्त्वाचे").priority == .p1)
    // "दर" also means a rate: a price per day reads as a repeat.
    #expect(parse("मजुरी दर दिवस 500 रुपये").recurrence == daily)
    // A particle that stands apart from a day stays in the title.
    let even = parse("आज सुद्धा रिपोर्ट पाठवा")
    #expect(even.plannedDayOffset == 0)
    #expect(even.title == "सुद्धा रिपोर्ट पाठवा")
  }

  // MARK: - Scripts and spellings

  @Test("The precomposed and the decomposed nukta read as one letter, and a missing nukta reads too")
  func nuktaForms() {
    // ज़ ड़ फ़ ग़ as one code point (U+095B, U+095C, U+095E, U+095A), as a
    // consonant and a nukta (U+093C), and as the consonant alone.
    let forms: [(ja: String, da: String, pha: String, ga: String)] = [
      ("\u{095B}", "\u{095C}", "\u{095E}", "\u{095A}"),
      ("\u{091C}\u{093C}", "\u{0921}\u{093C}", "\u{092B}\u{093C}", "\u{0917}\u{093C}"),
      ("\u{091C}", "\u{0921}", "\u{092B}", "\u{0917}"),
    ]
    for form in forms {
      let scalars = form.ja.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      // फेब्रुवारी, जून, जुलै, डिसेंबर, ऑगस्ट
      #expect(parse("फोन करा 5 \(form.pha)ेब्रुवारी").plannedDayOffset == captureDayOffset("2027-02-05"), "फेब्रुवारी: \(scalars)")
      #expect(parse("फोन करा 5 \(form.ja)ून").plannedDayOffset == captureDayOffset("2027-06-05"), "जून: \(scalars)")
      #expect(parse("फोन करा 5 \(form.ja)ुलै").plannedDayOffset == captureDayOffset("2027-07-05"), "जुलै: \(scalars)")
      #expect(parse("फोन करा 5 \(form.da)िसेंबर").plannedDayOffset == captureDayOffset("2026-12-05"), "डिसेंबर: \(scalars)")
      #expect(parse("फोन करा 5 ऑ\(form.ga)स्ट").plannedDayOffset == captureDayOffset("2027-08-05"), "ऑगस्ट: \(scalars)")
      // तातडीचे, दीड, अडीच
      #expect(parse("रिपोर्ट पाठवा तात\(form.da)ीचे").priority == .p1, "तातडीचे: \(scalars)")
      #expect(parse("मीटिंग दी\(form.da) वाजता").startMinutes == 13 * 60 + 30, "दीड: \(scalars)")
      #expect(parse("मीटिंग अ\(form.da)ीच वाजता").startMinutes == 14 * 60 + 30, "अडीच: \(scalars)")
      #expect(parse("रिपोर्ट लिहा दी\(form.da) तास").estimatedMinutes == 90, "दीड तास: \(scalars)")
    }
  }

  @Test("The eyelash ra, its decomposed form, and ra with a virama and ya read as one letter")
  func eyelashRa() {
    // दुसऱ्या as ऱ (U+0931), as र and a nukta, as र and a virama, and as र, a
    // virama, and a zero-width joiner before ya.
    let spellings = [
      "दुस\u{0931}\u{094D}या", "दुस\u{0930}\u{093C}\u{094D}या", "दुस\u{0930}\u{094D}या", "दुस\u{0930}\u{094D}\u{200D}या",
    ]
    for word in spellings {
      let scalars = word.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      let every = parse("जिम दर \(word) सोमवारी")
      #expect(every.recurrence == TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO"]), "दर दुसऱ्या: \(scalars)")
      #expect(every.title == "जिम", "दर दुसऱ्या: \(scalars): title")
    }
    for ending in ["णा\u{0931}\u{094D}या", "णा\u{0930}\u{093C}\u{094D}या", "णा\u{0930}\u{094D}या"] {
      #expect(parse("फोन करा येत्या शुक्रवारी").plannedDayOffset == 3)
      #expect(parse("फोन करा येणा\u{0930}\u{094D}या शुक्रवारी").plannedDayOffset == 3, "येणाऱ्या: \(ending)")
      #expect(parse("फोन करा येणा\u{0931}\u{094D}या शुक्रवारी").plannedDayOffset == 3, "येणाऱ्या: \(ending)")
    }
  }

  @Test("The candrabindu and the anusvara, and the nasal conjunct spelled either way, read as one word")
  func nasalSpellings() {
    // पाच, पांच, and पाँच
    #expect(parse("मीटिंग पा\u{0901}च वाजता").startMinutes == 17 * 60)
    #expect(parse("मीटिंग पा\u{0902}च वाजता").startMinutes == 17 * 60)
    #expect(parse("मीटिंग पाच वाजता").startMinutes == 17 * 60)
    let months: [(text: String, date: String)] = [
      ("5 सप्टेंबर", "2027-09-05"), ("5 सप्टेम्बर", "2027-09-05"), ("5 नोव्हेंबर", "2026-11-05"),
      ("5 नोव्हेम्बर", "2026-11-05"), ("5 डिसेंबर", "2026-12-05"), ("5 डिसेम्बर", "2026-12-05"),
      ("5 ऑक्टोबर", "2026-10-05"), ("5 ऑक्टोंबर", "2026-10-05"), ("5 सप्टें", "2027-09-05"),
    ]
    for month in months {
      #expect(parse("फोन करा \(month.text)").plannedDayOffset == captureDayOffset(month.date), "\(month.text)")
    }
    for word in ["वीकेंड", "वीकेन्ड", "वीकएंड"] {
      #expect(parse("फोन करा \(word)").plannedDayOffset == 4, "\(word)")
    }
    for word in ["पंधरा", "पन्धरा"] {
      #expect(parse("रिपोर्ट लिहा \(word) मिनिटे").estimatedMinutes == 15, "\(word)")
    }
    for word in ["अर्जंट", "अर्जेंट", "अर्जेन्ट"] {
      #expect(parse("रिपोर्ट पाठवा \(word)").priority == .p1, "\(word)")
    }
    for word in ["पंचवीस", "पन्चवीस"] {
      #expect(parse("रिपोर्ट लिहा \(word) मिनिटे").estimatedMinutes == 25, "\(word)")
    }
  }

  @Test("Spelling variants of the same word read alike")
  func spellingVariants() {
    // दीड and दिड, अडीच and अडिच, गुरुवार and गुरूवार, महत्त्वाचे and महत्वाचे,
    // ऑगस्ट and आगस्ट, मिनिटे and मिनीटे.
    #expect(parse("मीटिंग दीड वाजता").startMinutes == parse("मीटिंग दिड वाजता").startMinutes)
    #expect(parse("मीटिंग अडीच वाजता").startMinutes == parse("मीटिंग अडिच वाजता").startMinutes)
    #expect(parse("फोन करा गुरुवारी").plannedDayOffset == parse("फोन करा गुरूवारी").plannedDayOffset)
    #expect(parse("रिपोर्ट पाठवा महत्त्वाचे").priority == parse("रिपोर्ट पाठवा महत्वाचे").priority)
    #expect(parse("फोन करा 5 ऑगस्ट").plannedDayOffset == parse("फोन करा 5 आगस्ट").plannedDayOffset)
    #expect(parse("रिपोर्ट लिहा 30 मिनिटे").estimatedMinutes == parse("रिपोर्ट लिहा 30 मिनीटे").estimatedMinutes)
  }

  @Test("A zero-width joiner after a virama or before an ending changes nothing")
  func joiners() {
    #expect(parse("फोन करा 5 सप्टेम्\u{200C}बर").plannedDayOffset == captureDayOffset("2027-09-05"))
    #expect(parse("फोन करा 5 सप्टेम्\u{200D}बर").plannedDayOffset == captureDayOffset("2027-09-05"))
    #expect(parse("रिपोर्ट पाठवा अर्जेन्\u{200C}ट").priority == .p1)
    #expect(parse("रिपोर्ट पाठवा शुक्रवार\u{200C}पर्यंत").dueDayOffset == 3)
    #expect(parse("फोन करा उद्या\u{200C}पासून").plannedDayOffset == 1)
    #expect(parse("फोन करा 5 मे\u{200C}ला").plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(parse("रिपोर्ट लिहा 30 मिनिटां\u{200C}साठी").estimatedMinutes == 30)
    // The title keeps the joiner as typed.
    let typed = "सप्टेम्\u{200C}बर अहवाल"
    #expect(Array(parse("\(typed) उद्या").title.unicodeScalars) == Array(typed.unicodeScalars))
  }

  @Test("The composed and the decomposed forms of a line read the same")
  func normalizationForms() {
    let lines = [
      "जिम दर दुसऱ्या सोमवारी", "फोन करा येणाऱ्या शुक्रवारी", "उद्या सकाळी मीटिंग 6 वाजता",
      "रिपोर्ट पाठवा शुक्रवारपर्यंत", "फोन करा 5 फेब्रुवारी", "औषध घ्या दर 2 आठवड्यांनी", "मीटिंग दीड वाजता",
      "रिपोर्ट पाठवा तातडीचे", "फोन करा 5 ऑक्टोबर", "रिपोर्ट पाठवा ता\u{095C}ीचे", "फोन करा 5 \u{095E}ेब्रुवारी",
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

  @Test("Devanagari digits and Western digits read the same")
  func digitScripts() {
    let lines = [
      "मीटिंग 3:30 वाजता", "मीटिंग संध्याकाळी 5:30", "मीटिंग 5.30 वाजता", "मीटिंग साडे 5 वाजता", "मीटिंग 2 ते 4 वाजता",
      "मीटिंग 14:00 ते 16:00", "रिपोर्ट लिहा 20 मिनिटे", "रिपोर्ट लिहा 1.5 तास", "रिपोर्ट लिहा 1 तास 30 मिनिटे",
      "औषध घ्या दर 3 दिवसांनी", "भाडे दर महिन्याच्या 5 तारखेला", "बैठक 5 मार्च 2027", "फोन करा 3 दिवसांनी",
      "सुट्टी 3 ते 5 मार्च", "सुट्टी 3-5 मार्च", "रिपोर्ट पाठवा 5 मार्चपर्यंत", "फोन करा 2 महिन्यांनी",
      "औषध घ्या दर 2 आठवड्यांनी", "फोन करा 15/10/2026",
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
    let typed = parse("३ लोकांसोबत मीटिंग उद्या")
    #expect(typed.plannedDayOffset == 1)
    #expect(typed.title == "३ लोकांसोबत मीटिंग")
  }

  @Test("The title keeps the letters and signs as they were typed")
  func titleKeepsTypedText() {
    // A precomposed nukta letter in the title stays one code point, and a
    // decomposed one stays two.
    let typed = "\u{095B}रूरी औषधे \u{0959}रेदी आणि दुस\u{0931}\u{094D}या ल\u{0921}\u{093C}का"
    let parsed = parse("\(typed) उद्या")
    #expect(parsed.plannedDayOffset == 1)
    #expect(parsed.priority == nil)
    #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    let candrabindu = parse("माँ ला फोन करा उद्या")
    #expect(Array(candrabindu.title.unicodeScalars) == Array("माँ ला फोन करा".unicodeScalars))
  }

  @Test("The danda and the comma left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("फोन करा, उद्या, संध्याकाळी 5 वाजता", "फोन करा"), ("फोन करा उद्या।", "फोन करा।"), ("उद्या, फोन करा", "फोन करा"),
      ("उद्या: फोन करा", "फोन करा"), ("फोन करा - उद्या", "फोन करा"),
      ("रिपोर्ट पाठवा, शुक्रवारपर्यंत, उच्च प्राधान्य", "रिपोर्ट पाठवा"),
      ("दूध, ब्रेड आणि अंडी उद्या आणणे", "दूध, ब्रेड आणि अंडी आणणे"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The danda is punctuation: it ends a word.
    #expect(parse("फोन करा उद्या।").plannedDayOffset == 1)
    #expect(parse("रिपोर्ट पाठवा शुक्रवारपर्यंत।").dueDayOffset == 3)
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    let day = parse("काम उद्या")
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "काम")
    let time = parse("काम संध्याकाळी 5 वाजता")
    #expect(time.startMinutes == 17 * 60)
    #expect(time.title == "काम")
    let repeating = parse("काम दर सोमवारी")
    #expect(repeating.recurrence == monday)
    #expect(repeating.title == "काम")
    let length = parse("काम 20 मिनिटे")
    #expect(length.estimatedMinutes == 20)
    #expect(length.title == "काम")
    #expect(parse("काम #यादी").tags == ["यादी"])
  }

  @Test("The examples of the user guide table are read as the details they demonstrate")
  func guideExamples() {
    let days = [
      "आज", "आज रात्री", "उद्या", "उद्या सकाळी", "परवा", "सोमवारी", "या शुक्रवारी", "पुढच्या सोमवारी",
      "पुढच्या आठवड्यात", "या वीकेंडला", "3 दिवसांनी", "एका आठवड्याने",
    ]
    for example in days {
      let parsed = parse("काम \(example)")
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    let dates = [
      "5 मे", "5 मे 2027", "तारीख 5 मे", "15 ऑक्टो.", "15 तारखेला", "15/10/2026", "15.10.", "सोमवार 5 ऑक्टोबर",
    ]
    for example in dates {
      let parsed = parse("काम \(example)")
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    let ranges = [
      "3 ते 5 मार्च", "3 मार्च ते 5 मार्च", "3 मार्चपासून 5 मार्चपर्यंत", "30 जानेवारी ते 2 फेब्रुवारी", "3-5 मार्च",
      "सोमवार ते बुधवार",
    ]
    for example in ranges {
      let parsed = parse("काम \(example)")
      #expect(parsed.plannedDayOffset != nil && parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    for example in [
      "शुक्रवारपर्यंत", "उद्या संध्याकाळपर्यंत", "5 मेपर्यंत", "अंतिम तारीख: 5 मे", "डेडलाइन शुक्रवार", "शुक्रवारी देय",
    ] {
      let parsed = parse("काम \(example)")
      #expect(parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    let times = [
      "5 वाजता", "5:30 वाजता", "साडेपाच वाजता", "पावणेसहा वाजता", "दीड वाजता", "पाच वाजता", "सकाळी 9 वाजता",
      "संध्याकाळी 5 वाजता", "रात्रीच्या 10 वाजता", "संध्याकाळी 5:30", "मध्यरात्री", "3 ते 5 वाजता", "सकाळी 9 ते 11 वाजता",
      "3 वाजेपासून 5 वाजेपर्यंत", "14:00 ते 16:00",
    ]
    for example in times {
      let parsed = parse("काम \(example)")
      #expect(parsed.startMinutes != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    let repeats = [
      "रोज", "दररोज", "रोज सकाळी", "दर सोमवारी", "दर सोमवारी आणि गुरुवारी", "दर दुसऱ्या सोमवारी", "दर आठवड्याला",
      "दर 2 दिवसांनी", "दर महिन्याला", "दर महिन्याच्या 5 तारखेला", "दरवर्षी", "दर वीकेंडला", "कामाच्या दिवशी",
      "दर सोमवार ते शुक्रवार", "दिवसाआड", "दर तीन महिन्यांनी",
    ]
    for example in repeats {
      let parsed = parse("काम \(example)")
      #expect(parsed.recurrence != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    let lengths = [
      "30 मिनिटे", "2 तास", "1.5 तास", "1 तास 30 मिनिटे", "अर्धा तास", "पाऊण तास", "दीड तास", "साडेतीन तास", "दोन तास",
      "30 मिनिटांसाठी",
    ]
    for example in lengths {
      let parsed = parse("काम \(example)")
      #expect(parsed.estimatedMinutes != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    for example in ["उच्च प्राधान्य", "मध्यम प्राधान्य", "निम्न प्राधान्य", "प्राधान्य: उच्च", "तातडीचे"] {
      let parsed = parse("काम \(example)")
      #expect(parsed.priority != nil, "\(example)")
      #expect(parsed.title == "काम", "\(example): title")
    }
    #expect(parse("तातडीचे: काम").priority == .p1)
    #expect(parse("मजुरी दर दिवस 500 रुपये").recurrence == daily)
  }

  // MARK: - Names the system writes

  /// The short weekday names the system writes in Marathi that are not read,
  /// with the reason: each is an ordinary word, a name, or an abbreviation.
  private static let unreadWeekdayAbbreviations: [String: String] = [
    "रवि": "a man's name, and the sun", "सोम": "a name, and the moon", "मंगळ": "the planet Mars",
    "बुध": "the planet Mercury", "गुरु": "a teacher, and the planet Jupiter", "शुक्र": "the planet Venus",
    "शनि": "the planet Saturn", "र.": "an abbreviation of one letter and a dot", "सो.": "an abbreviation with a dot",
    "मं.": "an abbreviation with a dot", "बु.": "an abbreviation with a dot", "गु.": "an abbreviation with a dot",
    "शु.": "an abbreviation with a dot", "श.": "an abbreviation of one letter and a dot",
  ]

  @Test("Every month and weekday name the system writes in Marathi is read, except the short weekday forms")
  func systemNames() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "mr_IN")
    formatter.calendar = Calendar(identifier: .gregorian)
    let monthNames: [[String]] = [
      formatter.monthSymbols, formatter.shortMonthSymbols, formatter.standaloneMonthSymbols,
      formatter.shortStandaloneMonthSymbols,
    ]
    for names in monthNames {
      #expect(names.count == 12)
      for (index, name) in names.enumerated() {
        // 2026-09-22 is today: the 5th of September has passed, the 5th of October has not.
        let month = index + 1
        let date = month >= 10 ? "2026-\(month)-05" : "2027-0\(month)-05"
        let parsed = parse("फोन करा 5 \(name)")
        #expect(
          parsed.plannedDayOffset == captureDayOffset(date), "5 \(name) is the 5th of month \(month)")
        #expect(parsed.title == "फोन करा", "5 \(name): title")
      }
    }
    let weekdayNames: [[String]] = [
      formatter.weekdaySymbols, formatter.standaloneWeekdaySymbols, formatter.shortWeekdaySymbols,
      formatter.shortStandaloneWeekdaySymbols, formatter.veryShortWeekdaySymbols,
    ]
    for names in weekdayNames {
      #expect(names.count == 7)
      for (index, name) in names.enumerated() {
        let parsed = parse("फोन करा \(name)")
        if Self.unreadWeekdayAbbreviations[name] != nil {
          #expect(parsed.plannedDayOffset == nil, "\(name) is left in the title")
          #expect(parsed.title == "फोन करा \(name)", "\(name): title")
        } else {
          // Index 0 is Sunday; 2026-09-22 is a Tuesday, so a weekday alone is the next such day.
          let delta = (index + 1 - 3 + 7) % 7
          #expect(parsed.plannedDayOffset == (delta == 0 ? 7 : delta), "\(name)")
          #expect(parsed.title == "फोन करा", "\(name): title")
        }
      }
    }
    // The system's AM and PM markers after an hour, and its long date.
    let meridiems: [(symbol: String, minutes: Int)] = [(formatter.amSymbol, 3 * 60 + 30), (formatter.pmSymbol, 15 * 60 + 30)]
    for meridiem in meridiems {
      let parsed = parse("मीटिंग 3:30 \(meridiem.symbol) वाजता")
      #expect(parsed.startMinutes == meridiem.minutes, "\(meridiem.symbol)")
      #expect(parsed.title == "मीटिंग", "\(meridiem.symbol): title")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = formatter.timeZone
    let components = DateComponents(year: 2026, month: 10, day: 15, hour: 15, minute: 30)
    if let date = calendar.date(from: components) {
      formatter.timeStyle = .short
      for style in [DateFormatter.Style.medium, .long, .full] {
        formatter.dateStyle = style
        let text = "फोन करा " + formatter.string(from: date)
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == captureDayOffset("2026-10-15"), "\(text): planned day")
        #expect(parsed.startMinutes == 15 * 60 + 30, "\(text): start")
      }
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Marathi, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "mr"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "mr"]).estimatedMinutes == 20)
    #expect(parse("रिपोर्ट 2h").estimatedMinutes == 120)
    #expect(parse("रिपोर्ट 30min").estimatedMinutes == 30)
    #expect(parse("रिपोर्ट 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "mr"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "mr"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "mr"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "mr"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times.
    #expect(parse("मीटिंग 5pm").startMinutes == 17 * 60)
    #expect(parse("मीटिंग 5 PM").startMinutes == 17 * 60)
    #expect(parse("मीटिंग 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("मीटिंग 30 min").estimatedMinutes == 30)
    // A letter h after a number is no clock time for Marathi: 2h and 15h read as English reads them alone.
    for text in ["Run 2h", "Run 15h", "Meet at 15h", "Call at 9h30", "Read 1.5h"] {
      #expect(parse(text, languages: ["en", "mr"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // English lines read the same with Marathi beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "mr"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom उद्या at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting शुक्रवारी at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("मीटिंग tomorrow संध्याकाळी 5 वाजता")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "मीटिंग")
    let marathiTitle = parse("बैठक next friday")
    #expect(marathiTitle.plannedDayOffset == 10)
    #expect(marathiTitle.title == "बैठक")
    #expect(parse("बैठक 2h").estimatedMinutes == 120)
  }

  @Test("Lines in other languages read the same with Marathi beside them")
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
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "mr"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["mr", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Marathi with another language.
    for languages in [["fr", "mr"], ["mr", "fr"]] {
      let mixed = parse("Appeler maman उद्या à 15h", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("जिम दर सोमवारी", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
    }
    #expect(parse("Meeting 下午3点 उद्या", languages: ["zh", "mr"]).plannedDayOffset == 1)
    #expect(parse("Meeting מחר उद्या", languages: ["he", "mr"]).plannedDayOffset == 1)
  }

  @Test("Beside Hindi, each language's lines read as they do alone")
  func besideHindi() {
    // Words the two languages share, written in Marathi.
    let marathi = [
      "उद्या संध्याकाळी 5 वाजता मीटिंग", "आज रात्री 8 वाजता जेवण", "आज रात्रीचे जेवण 8 वाजता",
      "सोमवारी सकाळी 9 वाजता मीटिंग", "आजच रिपोर्ट पाठवा", "सोमवारीच मीटिंग", "रिपोर्ट शुक्रवारपर्यंत",
      "रिपोर्ट सोमवारपूर्वी", "दर सोमवारी जिम", "दर सोमवार ते शुक्रवार जिम", "रोज सकाळी 6 वाजता योग",
      "औषध घ्या नित्य", "औषध घ्या दररोज", "फोन करा 5 मार्चला", "फोन करा 5 जूनला", "सुट्टी 3 ते 5 मार्च",
      "सुट्टी 3-5 जून", "सुट्टी 3 मार्चपासून 5 मार्चपर्यंत", "रिपोर्ट पाठवा उच्च प्राथमिकता",
      "रिपोर्ट पाठवा मध्यम प्राधान्य", "रिपोर्ट पाठवा अत्यावश्यक", "रिपोर्ट पाठवा अर्जेंट", "अंतिम तारीख: शुक्रवार रिपोर्ट पाठवा",
      "डेडलाइन शुक्रवार रिपोर्ट पाठवा", "भाडे दर महिन्याच्या 5 तारखेला", "फोन करा वीकेंडला", "फोन करा या वीकेंडला",
      "फोन करा या शुक्रवारी", "फोन करा पुढच्या शुक्रवारी", "रिपोर्ट पाठवा तारीख 5 जून", "मीटिंग 14:00 ते 16:00",
      "रिपोर्ट लिहा 30 मिनिटे", "रिपोर्ट लिहा 2 तास", "फोन करा 3 दिवसांनी",
    ]
    for text in marathi {
      let alone = parse(text)
      #expect(parse(text, languages: ["mr", "hi"]) == alone, "\(text)")
      #expect(parse(text, languages: ["hi", "mr"]) == alone, "\(text): reversed")
    }
    // The same for Hindi lines that use the shared words.
    let hindi = [
      "माँ को फोन करें कल", "फोन करें आज की रात", "आज रात 8 बजे खाना", "कल सुबह मीटिंग 6 बजे", "सोमवार को ही मीटिंग",
      "फोन करें इस शुक्रवार", "फोन करें अगले शुक्रवार", "फोन करें आने वाले शुक्रवार को", "फोन करें इस वीकेंड",
      "फोन करें वीकेंड पर", "फोन करें अगले वीकेंड", "फोन करें सोमवार को", "फोन करें सोमवार से", "फोन करें 5 मार्च को",
      "फोन करें 5 जून", "छुट्टी 3 से 5 मार्च", "छुट्टी 3-5 मार्च", "छुट्टी 3-5 मार्च तक", "छुट्टी 3-5 जून की",
      "रिपोर्ट भेजें शुक्रवार तक", "रिपोर्ट भेजें शुक्रवार से पहले", "रिपोर्ट आज तक", "रिपोर्ट आज से पहले",
      "सोमवार की मीटिंग", "शुक्रवार का खाना", "आज की रिपोर्ट", "आज ही रिपोर्ट भेजना", "जिम हर सोमवार",
      "जिम प्रत्येक सोमवार", "जिम प्रत्येक सोमवार को", "जिम प्रत्येक सोमवार की", "दवा लें रोज़", "दवा लें रोज़ का काम",
      "दवा लें नित्य", "रिपोर्ट भेजें उच्च प्राथमिकता", "रिपोर्ट भेजें उच्च प्राथमिकता से", "उच्च प्राथमिकता वाले कार्य",
      "रिपोर्ट भेजें अंतिम तारीख 5 जून", "अंतिम तारीख: शुक्रवार रिपोर्ट भेजें", "डेडलाइन शुक्रवार रिपोर्ट भेजें",
      "मीटिंग 5 बजे", "मीटिंग साढ़े 5 बजे", "रिपोर्ट लिखें 30 मिनट", "फोन करें 3 दिन बाद", "रिपोर्ट सोमवार से बुधवार तक",
      "जिम हर सोमवार से शुक्रवार", "बैठक सोमवार शाम 5 बजे", "शुक्रवार की शाम पार्टी",
    ]
    for text in hindi {
      let alone = parse(text, languages: ["hi"])
      #expect(parse(text, languages: ["mr", "hi"]) == alone, "\(text)")
      #expect(parse(text, languages: ["hi", "mr"]) == alone, "\(text): reversed")
    }
    // A line may mix both languages.
    let mixed = parse("फोन करा उद्या शाम 5 बजे", languages: ["mr", "hi"])
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 17 * 60)
    // A line with a Hindi day phrase and a Marathi day word has two readings of its day:
    // Marathi, which is tried first, reads its own word.
    #expect(parse("आज की रात जेवण उद्या", languages: ["mr", "hi"]).plannedDayOffset == 1)
    #expect(parse("आज की रात जेवण", languages: ["mr", "hi"]).plannedDayOffset == 0)
  }

  @Test("Marathi words are read only for a user who reads Marathi")
  func languageGate() {
    let line = parse("आईला फोन करा उद्या", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "आईला फोन करा उद्या")
    for languages in [["mr"], ["mr-IN"], ["mr_IN"], ["en-US", "mr-IN"], ["MR"], ["mr-Deva-IN"]] {
      #expect(parse("आईला फोन करा उद्या", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages that write Devanagari do not get Marathi words, and Marathi readers do not get theirs.
    #expect(parse("आईला फोन करा उद्या", languages: ["hi"]).plannedDayOffset == nil)
    #expect(parse("आईला फोन करा उद्या", languages: ["ne"]).plannedDayOffset == nil)
    #expect(parse("माँ को फोन करें कल", languages: ["mr"]).plannedDayOffset == nil)
    // Other languages' words are not read for a Marathi reader, and Marathi is not read for theirs.
    expectLinesUnread(
      ["Zadzwonić jutro", "Позвонить завтра", "اتصل بأمي غداً", "Appeler maman demain", "Zahnarzt übermorgen"],
      languages: ["mr"])
    for languages in [
      ["ar"], ["pl"], ["ru"], ["fr"], ["es"], ["it"], ["pt"], ["he"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"],
      ["tr"], ["el"], ["th"], ["fa"], ["ur"], ["uk"], ["ja"], ["ko"], ["zh"],
    ] {
      let parsed = parse("आईला फोन करा उद्या", languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == "आईला फोन करा उद्या", "\(languages): title")
    }
    // A clock time, a repeat, a priority, and a length with a Marathi word need Marathi among the languages.
    #expect(parse("मीटिंग 5 वाजता", languages: ["en"]).startMinutes == nil)
    #expect(parse("औषध घ्या दर सोमवारी", languages: ["en"]).recurrence == nil)
    #expect(parse("रिपोर्ट पाठवा उच्च प्राधान्य", languages: ["en"]).priority == nil)
    #expect(parse("रिपोर्ट लिहा 30 मिनिटे", languages: ["en"]).estimatedMinutes == nil)
    // Marathi and Arabic readers get both.
    let both = parse("आईला फोन करा उद्या", languages: ["ar", "mr"])
    #expect(both.plannedDayOffset == 1)
    #expect(parse("اتصل بأمي غداً", languages: ["ar", "mr"]).plannedDayOffset == 1)
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["mr"])
    let unit: [String] = [
      "वाजता ", "5 वाजता ", "5:30 वाजता ", "सकाळी 5 वाजता ", "साडेपाच वाजता ", "दीड वाजता ", "अडीचला ", "सव्वा ",
      "पावणे ", "साडे ", "उद्या ", "उद्या सकाळी ", "आज रात्री ", "परवा ", "शुक्रवारी ", "शुक्रवारी संध्याकाळी ",
      "या शुक्रवारी ", "पुढच्या शुक्रवारी ", "पुढच्या आठवड्यात ", "15 ऑक्टोबर ", "15 ऑक्टो. ", "15.10.2026 ",
      "15/10 ", "15/10 ला ", "3 ते 5 मार्च ", "3 मार्चपासून 5 मार्चपर्यंत ", "3-5 मार्च ", "पर्यंत ", "शुक्रवारपर्यंत ",
      "अंतिम तारीख शुक्रवार ", "देय ", "दररोज ", "रोज सकाळी ", "दर सोमवारी ", "दर सोमवारी आणि गुरुवारी ",
      "दर दोन आठवड्यांनी ", "दर महिन्याच्या 5 तारखेला ", "दर दुसऱ्या सोमवारी ", "सोमवार ते शुक्रवार ", "वीकेंडला ",
      "30 मिनिटे ", "1.5 तास ", "1 तास 30 मिनिटे ", "अर्धा तास ", "साडेतीन तास ", "तातडीचे ", "उच्च प्राधान्य ",
      "प्राधान्य: ", "रात्री ", "मध्यरात्री ", "ते ", "दर ", "तास ", "मिनिटे ", "आज ", "आणि ", "ा", "्", "ं",
      "\u{200C}", "\u{200D}", "\u{093C}", "ज\u{093C}", "ड\u{093C}", "र\u{093C}", "\u{0931}", ", ", ".", "-", "–", ":",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "रवी " + String(repeating: token, count: count) + " फोन"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(5), "\(token) took \(elapsed)")
    }
    // A line past the read limit is a title and nothing more, at once.
    let past = String(repeating: "उद्या संध्याकाळी 5 वाजता ", count: 500).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    #expect(slowest < .seconds(5), "the slowest long line took \(slowest)")
    // The first phrase of a long line still reads.
    let first = parse("उद्या " + String(repeating: "5 वाजता उद्या ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 17 * 60)
  }
}
