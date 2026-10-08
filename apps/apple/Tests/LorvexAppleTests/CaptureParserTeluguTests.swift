import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["te"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["te"])
}

/// `text` with its ASCII digits written in the Telugu script (U+0C66-U+0C6F).
private func teluguDigits(_ text: String) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in text.unicodeScalars {
    if (0x30...0x39).contains(scalar.value), let digit = Unicode.Scalar(0x0C66 + scalar.value - 0x30) {
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

/// Telugu capture lines, read for a user whose languages include Telugu.
@Suite("Capture parser Telugu")
struct CaptureParserTeluguTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("అమ్మకు ఫోన్ చేయండి రేపు")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "అమ్మకు ఫోన్ చేయండి")
    #expect(line.phrases.map(\.text) == ["రేపు"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("ఈరోజు", 0), ("ఈ రోజు", 0), ("ఇవాళ", 0), ("ఇవ్వాళ", 0), ("నేడు", 0), ("ఈరోజే", 0), ("ఇవాళే", 0), ("నేడే", 0),
      ("ఈరోజుకి", 0), ("ఈరోజుకు", 0), ("ఈరోజున", 0), ("ఇవాళ్టికి", 0), ("నేటికి", 0), ("రేపు", 1), ("రేపే", 1),
      ("రేపటికి", 1), ("రేపటికే", 1), ("ఎల్లుండి", 2), ("ఎల్లుండే", 2), ("ఎల్లుండికి", 2), ("3 రోజుల్లో", 3),
      ("3 రోజులలో", 3), ("3 రోజుల తర్వాత", 3), ("3 రోజుల తరువాత", 3), ("మూడు రోజుల్లో", 3), ("పది రోజుల్లో", 10),
      ("10 రోజుల తర్వాత", 10), ("ఒక రోజు తర్వాత", 1), ("1 రోజు తర్వాత", 1), ("2 వారాల్లో", 14),
      ("రెండు వారాల్లో", 14), ("ఒక వారం తర్వాత", 7), ("1 వారం తర్వాత", 7), ("ఒక నెలలో", 30),
      ("1 నెల తర్వాత", 30), ("2 నెలల్లో", 61), ("రెండు నెలల తర్వాత", 61), ("వచ్చే వారం", 7), ("వచ్చే వారంలో", 7),
      ("రాబోయే వారం", 7), ("తదుపరి వారం", 7), ("వచ్చే వారానికి", 7),
    ]
    for day in days {
      let text = "అమ్మకు ఫోన్ చేయండి \(day.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day.offset, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("రేపు అమ్మకు ఫోన్ చేయండి")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "అమ్మకు ఫోన్ చేయండి")
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("ఈరోజు ఉదయం", 0), ("ఈరోజు మధ్యాహ్నం", 0), ("ఈరోజు సాయంత్రం", 0), ("ఈరోజు రాత్రి", 0), ("ఈ ఉదయం", 0),
      ("ఈ మధ్యాహ్నం", 0), ("ఈ సాయంత్రం", 0), ("ఈ రాత్రి", 0), ("రేపు ఉదయం", 1), ("రేపు ఉదయము", 1),
      ("రేపు ఉదయాన్నే", 1), ("రేపు తెల్లవారుజామున", 1), ("రేపు మధ్యాహ్నం", 1), ("రేపు సాయంత్రం", 1),
      ("రేపు సాయంకాలం", 1), ("రేపు రాత్రి", 1), ("ఎల్లుండి ఉదయం", 2), ("శుక్రవారం సాయంత్రం", 3),
      ("శుక్రవారం రాత్రి", 3), ("శనివారం ఉదయం", 4),
    ]
    for phrase in phrases {
      let text = "అమ్మకు ఫోన్ చేయండి \(phrase.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("రేపు ఉదయం మీటింగ్ 6 గంటలకు")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "మీటింగ్")
    let evening = parse("ఈరోజు సాయంత్రం జిమ్ 7 గంటలకు")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "జిమ్")
    let night = parse("రేపు రాత్రి భోజనం 9 గంటలకు")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 21 * 60)
    #expect(night.title == "భోజనం")
    let written = parse("ఈరోజు రాత్రి 8 గంటలకు భోజనం")
    #expect(written.plannedDayOffset == 0)
    #expect(written.startMinutes == 20 * 60)
    #expect(written.title == "భోజనం")
    // The part of the day as a noun or alone names no day.
    expectLinesUnread(
      [
        "ఉదయం నడక", "సాయంత్రం టీ", "రాత్రి భోజనం", "మధ్యాహ్నం భోజనం", "ఉదయాన్నే నడక", "రాత్రి మందులు వేసుకోండి",
        "ఉదయపు నడక", "సాయంత్రపు టీ",
      ], languages: ["te"])
    // A genitive after the part of the day makes it an attribute of a noun:
    // only the day is read.
    let walk = parse("రేపు ఉదయపు నడక")
    #expect(walk.plannedDayOffset == 1)
    #expect(walk.title == "ఉదయపు నడక")
    let tea = parse("ఎల్లుండి సాయంత్రపు టీ")
    #expect(tea.plannedDayOffset == 2)
    #expect(tea.title == "సాయంత్రపు టీ")
  }

  @Test("An ending that goes with a day is read with it, and any other ending leaves the day unread")
  func dayEndings() {
    let days: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("ఈరోజే రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 0, "ఈరోజే"),
      ("రిపోర్ట్ పంపండి రేపే", "రిపోర్ట్ పంపండి", 1, "రేపే"),
      ("రేపటికి రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 1, "రేపటికి"),
      ("ఇవాళ్టికి రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 0, "ఇవాళ్టికి"),
      ("సోమవారానికి రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 6, "సోమవారానికి"),
      ("సోమవారమే మీటింగ్", "మీటింగ్", 6, "సోమవారమే"),
      ("సోమవారము మీటింగ్", "మీటింగ్", 6, "సోమవారము"),
      ("సోమవారంనాడు మీటింగ్", "మీటింగ్", 6, "సోమవారంనాడు"),
      ("సోమవారం నాడు మీటింగ్", "మీటింగ్", 6, "సోమవారం నాడు"),
      ("సోమవారం రోజున మీటింగ్", "మీటింగ్", 6, "సోమవారం రోజున"),
      ("సోమవారం రోజు మీటింగ్", "మీటింగ్", 6, "సోమవారం రోజు"),
      ("రిపోర్ట్ పంపండి ఈరోజు", "రిపోర్ట్ పంపండి", 0, "ఈరోజు"),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // An ending the vocabulary does not list leaves the day word unread, and so
    // does a genitive or "నాటి" ("of that day"): "రేపటి మీటింగ్" is tomorrow's
    // meeting.
    expectLinesUnread(
      [
        "రేపటి మీటింగ్", "ఇవాళ్టి వార్తలు", "నేటి వార్తలు", "సోమవారపు మీటింగ్", "శనివారపు పార్టీ",
        "శుక్రవారం నాటి మీటింగ్", "ఈరోజు నాటి వార్తలు", "5 అక్టోబర్ నాటి రిపోర్ట్", "సోమవారాన్ని సెలవు చేయండి",
        "ఆరోజు మీటింగ్", "ఈ రోజుల్లో ఫోన్ వాడకం",
      ], languages: ["te"])
    // "నాటికి" is a deadline word, not "నాటి".
    #expect(parse("రిపోర్ట్ పంపండి శుక్రవారం నాటికి").dueDayOffset == 3)
  }

  @Test("నుండి and నుంచి after a day plan it, unless they start a counted day")
  func fromAfterDay() {
    let lines: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("ఈరోజు నుండి వ్యాయామం మొదలు", "వ్యాయామం మొదలు", 0, "ఈరోజు నుండి"),
      ("రేపటి నుండి జిమ్ మొదలు", "జిమ్ మొదలు", 1, "రేపటి నుండి"),
      ("రేపటి నుంచి జిమ్ మొదలు", "జిమ్ మొదలు", 1, "రేపటి నుంచి"),
      ("సోమవారం నుండి జిమ్ మొదలు", "జిమ్ మొదలు", 6, "సోమవారం నుండి"),
      ("సోమవారం నుంచి క్లాసులు", "క్లాసులు", 6, "సోమవారం నుంచి"),
      ("15 అక్టోబర్ నుండి క్లాసులు", "క్లాసులు", 23, "15 అక్టోబర్ నుండి"),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // The "నుండి" of a counted day ties the amount to another event.
    expectLinesUnread(
      [
        "ఈరోజు నుండి 3 రోజుల తర్వాత పని", "సోమవారం నుండి 2 వారాల తర్వాత పని", "రేపటి నుండి 3 రోజుల్లో పని",
        "మీటింగ్ నుండి 3 రోజుల తర్వాత కాల్", "మీటింగ్ అయిన 3 రోజుల తర్వాత కాల్",
      ], languages: ["te"])
    // The amount after a day that does not start a counted day stays in the title.
    let counted = parse("రేపటి నుండి 3 రోజులు జిమ్")
    #expect(counted.plannedDayOffset == 1)
    #expect(counted.title == "3 రోజులు జిమ్")
    // A day from another day to a deadline reads as a plan and a deadline.
    let leave = parse("ఈరోజు నుండి రేపటి వరకు సెలవు")
    #expect(leave.plannedDayOffset == 0)
    #expect(leave.dueDayOffset == 1)
    #expect(leave.title == "సెలవు")
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "ఈ మంగళవారం" is today.
    let names: [(stem: String, offset: Int)] = [
      ("బుధవార", 1), ("గురువార", 2), ("బృహస్పతివార", 2), ("శుక్రవార", 3), ("శనివార", 4), ("ఆదివార", 5),
      ("సోమవార", 6), ("మంగళవార", 7),
    ]
    for weekday in names {
      for ending in ["ం", "ము", "మే", "ానికి", "ానికే", "ంనాడు", "ం నాడు", "ం రోజున", "ం రోజు"] {
        let text = "అమ్మకు ఫోన్ చేయండి \(weekday.stem)\(ending)"
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(text): title")
      }
    }
    let modified: [(text: String, offset: Int)] = [
      ("ఈ శుక్రవారం", 3), ("ఈ మంగళవారం", 0), ("ఈ శనివారం", 4), ("ఈ సోమవారం", 6), ("వచ్చే శుక్రవారం", 3),
      ("వచ్చే మంగళవారం", 7), ("వచ్చే సోమవారం", 6), ("రాబోయే శుక్రవారం", 3), ("రాబోయే సోమవారం", 6),
      ("తదుపరి సోమవారం", 6), ("తదుపరి మంగళవారం", 7), ("తదుపరి బుధవారం", 8), ("తదుపరి శుక్రవారం", 10),
      ("తదుపరి శనివారం", 11), ("తదుపరి ఆదివారం", 12), ("తర్వాతి శుక్రవారం", 10), ("తరువాతి శుక్రవారం", 10),
      ("ఈ వారం శుక్రవారం", 3), ("ఈ వారం మంగళవారం", 0), ("వచ్చే వారం సోమవారం", 6), ("వచ్చే వారం శుక్రవారం", 10),
      ("రాబోయే వారం శుక్రవారం", 10), ("తదుపరి వారం శుక్రవారం", 10), ("వచ్చే వారం శుక్రవారం సాయంత్రం", 10),
      ("శుక్రవారం నుండి", 3), ("తదుపరి శుక్రవారం నుండి", 10),
    ]
    for line in modified {
      let text = "అమ్మకు ఫోన్ చేయండి \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    let opening = parse("శుక్రవారం అమ్మకు ఫోన్ చేయండి")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "అమ్మకు ఫోన్ చేయండి")
    // "ఈ వారం" alone names no single day.
    expectLinesUnread(["అమ్మకు ఫోన్ చేయండి ఈ వారం", "ఈ వారం రిపోర్ట్"], languages: ["te"])
  }

  @Test("The weekend: this one, next week's, and today when it is already here")
  func weekend() {
    for text in [
      "వారాంతం", "వారాంతంలో", "వారాంతములో", "వారాంతానికి", "ఈ వారాంతం", "ఈ వారాంతంలో", "వచ్చే వారాంతం",
      "రాబోయే వారాంతం", "వీకెండ్", "వీకెండ్\u{200C}లో", "శనివారం మరియు ఆదివారం", "శనివారం, ఆదివారం",
      "శనివారం & ఆదివారం", "శనివారం ఆదివారం", "శని ఆదివారాలు", "శని, ఆదివారాలు", "శని-ఆదివారాలు",
      "శని మరియు ఆదివారం",
    ] {
      let parsed = parse("అమ్మకు ఫోన్ చేయండి \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(text): title")
    }
    for text in ["తదుపరి వారాంతం", "తదుపరి వారాంతంలో"] {
      #expect(parse("అమ్మకు ఫోన్ చేయండి \(text)").plannedDayOffset == 11, "\(text)")
    }
    // On a Saturday or a Sunday the weekend is already here.
    #expect(parse("అమ్మకు ఫోన్ చేయండి వారాంతంలో", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("అమ్మకు ఫోన్ చేయండి వారాంతంలో", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("అమ్మకు ఫోన్ చేయండి వారాంతంలో", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("అమ్మకు ఫోన్ చేయండి తదుపరి వారాంతంలో", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
  }

  // MARK: - Dates

  @Test("Written dates: every month, in the spellings people type, with a year, a label, an ending, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("5 జనవరి", "2027-01-05"), ("5 జనవరీ", "2027-01-05"), ("5 ఫిబ్రవరి", "2027-02-05"),
      ("5 ఫిబ్రవరీ", "2027-02-05"), ("5 ఫెబ్రవరి", "2027-02-05"), ("5 మార్చి", "2027-03-05"),
      ("5 మార్చ్", "2027-03-05"), ("5 ఏప్రిల్", "2027-04-05"), ("5 ఏప్రిలు", "2027-04-05"),
      ("5 మే", "2027-05-05"), ("5 జూన్", "2027-06-05"), ("5 జూను", "2027-06-05"), ("5 జులై", "2027-07-05"),
      ("5 జూలై", "2027-07-05"), ("5 ఆగస్టు", "2027-08-05"), ("5 ఆగస్ట్", "2027-08-05"),
      ("5 ఆగష్టు", "2027-08-05"), ("5 సెప్టెంబర్", "2027-09-05"), ("5 సెప్టెంబరు", "2027-09-05"),
      ("5 అక్టోబర్", "2026-10-05"), ("5 అక్టోబరు", "2026-10-05"), ("5 నవంబర్", "2026-11-05"),
      ("5 నవంబరు", "2026-11-05"), ("5 డిసెంబర్", "2026-12-05"), ("5 డిసెంబరు", "2026-12-05"),
      ("22 సెప్టెంబర్", "2026-09-22"), ("5 జన", "2027-01-05"), ("5 ఫిబ్ర", "2027-02-05"),
      ("5 ఏప్రి", "2027-04-05"), ("5 ఆగ", "2027-08-05"), ("5 సెప్టెం", "2027-09-05"), ("5 అక్టో", "2026-10-05"),
      ("5 అక్టో.", "2026-10-05"), ("5 నవం", "2026-11-05"), ("5 డిసెం", "2026-12-05"),
      ("5 అక్టోబర్‌కి", "2026-10-05"), ("5 అక్టోబర్ నాడు", "2026-10-05"), ("5 అక్టోబర్ నుండి", "2026-10-05"),
      ("5 అక్టోబర్ కోసం", "2026-10-05"), ("5 మే 2027", "2027-05-05"), ("5 మే 2028", "2028-05-05"),
      ("5 మే, 2028", "2028-05-05"), ("15 అక్టోబర్, 2026", "2026-10-15"), ("15వ తేదీ అక్టోబర్", "2026-10-15"),
      ("15వ తేదీ అక్టోబర్ 2026", "2026-10-15"), ("తేదీ 5 మే", "2027-05-05"), ("తేదీ: 5 మే", "2027-05-05"),
      ("సోమవారం, 5 అక్టోబర్", "2026-10-05"), ("సోమవారం 5 అక్టోబర్", "2026-10-05"),
      ("5 అక్టోబర్, సోమవారం", "2026-10-05"), ("15 అక్టోబర్ 2026, గురువారం", "2026-10-15"),
      ("అక్టోబర్ 15", "2026-10-15"), ("అక్టోబర్ 15, 2026", "2026-10-15"), ("అక్టోబర్ 15వ తేదీ", "2026-10-15"),
      ("అక్టోబర్ 15వ తేదీన", "2026-10-15"), ("అక్టోబర్ 15న", "2026-10-15"), ("జనవరి 20", "2027-01-20"),
      ("మే 5", "2027-05-05"), ("15వ తేదీన", "2026-10-15"), ("5న", "2026-10-05"), ("15న", "2026-10-15"),
      ("15 తేదీన", "2026-10-15"), ("15/10/2026", "2026-10-15"), ("15.10.2026", "2026-10-15"),
      ("15-10-2026", "2026-10-15"), ("15.10.", "2026-10-15"), ("తేదీ 15/10", "2026-10-15"),
      ("తేదీ 15.10", "2026-10-15"), ("15/10న", "2026-10-15"), ("15/10కి", "2026-10-15"),
      ("15/10 నుండి", "2026-10-15"),
    ]
    for line in dates {
      let text = "అమ్మకు ఫోన్ చేయండి \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
  }

  @Test("A month needs its day beside it, and a short month after a day only")
  func unreadDates() {
    expectLinesUnread(
      [
        // The months of the Telugu calendar are not Gregorian dates.
        "అమ్మకు ఫోన్ చేయండి 5 వైశాఖం", "పూజ 10 కార్తీకం", "అమ్మకు ఫోన్ చేయండి 15 ఆషాఢం",
        // A month alone, and a short month before its day.
        "సెలవు మే నెలలో", "మార్చి నెల సెలవు", "అమ్మకు ఫోన్ చేయండి జన 20", "అమ్మకు ఫోన్ చేయండి అక్టో 20",
        "అమ్మకు ఫోన్ చేయండి ఆగ 20", "అమ్మకు ఫోన్ చేయండి 5 ఆగండి",
        // A month before a count of things, and a day the month does not have.
        "అక్టోబర్ 15 రూపాయలు", "అక్టోబర్ 15 మంది", "అమ్మకు ఫోన్ చేయండి 31 ఏప్రిల్",
        "అమ్మకు ఫోన్ చేయండి 30 ఫిబ్రవరి", "అమ్మకు ఫోన్ చేయండి 32 మే",
        // Digits only, with no label and no ending.
        "అమ్మకు ఫోన్ చేయండి 5/10", "అమ్మకు ఫోన్ చేయండి 5.10", "అమ్మకు ఫోన్ చేయండి 15-10",
        "అమ్మకు ఫోన్ చేయండి 15/10",
      ], languages: ["te"])
    // A full month name before its day is a date, a short one is not.
    #expect(parse("సెలవు మే 5").plannedDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("సెలవు", "3 నుండి 5 మార్చి", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 నుండి 5 మార్చి వరకు", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 నుండి 5 మార్చికి", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 నుండి 5 మార్చి వరకూ", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 నుండి 5 మార్చి దాకా", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 నుంచి 5 మార్చి వరకు", "2027-03-03", "2027-03-05"),
        ("సెలవు", "మార్చి 3 నుండి 5 వరకు", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 మార్చి నుండి 5 మార్చి", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 మార్చి నుండి 5 మార్చి వరకు", "2027-03-03", "2027-03-05"),
        ("సెలవు", "30 జనవరి నుండి 2 ఫిబ్రవరి వరకు", "2027-01-30", "2027-02-02"),
        ("సెలవు", "3-5 మార్చి", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3–5 మార్చి", "2027-03-03", "2027-03-05"),
        ("సెలవు", "మార్చి 3-5", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 మార్చి - 5 మార్చి", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 నుండి 5 మార్చి 2027", "2027-03-03", "2027-03-05"),
        ("సెలవు", "3 మార్చి నుండి 5 జులై వరకు", "2027-03-03", "2027-07-05"),
        ("సెలవు", "అక్టోబర్ 3 నుండి 5 వరకు", "2026-10-03", "2026-10-05"),
        ("కుటుంబంతో సెలవు", "3 నుండి 5 మార్చి వరకు", "2027-03-03", "2027-03-05"),
        ("సెలవు", "25 సెప్టెంబర్ నుండి 3 అక్టోబర్ వరకు", "2026-09-25", "2026-10-03"),
        ("సెలవు", "30 డిసెంబర్ నుండి 2 జనవరి వరకు", "2026-12-30", "2027-01-02"),
        ("సదస్సు", "12-14 అక్టోబర్", "2026-10-12", "2026-10-14"),
      ], languages: ["te"])
  }

  @Test("A range whose end is not after its start, or that names no month, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "సెలవు 5 నుండి 3 మార్చి", "సెలవు 3 మార్చి నుండి 3 మార్చి", "సెలవు 5-3 మార్చి", "సెలవు 5 మార్చి నుండి 3 మార్చి",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "సెలవు 3 నుండి 5",
        // A range in the past may be an event the task only prepares for.
        "3 నుండి 5 మార్చి వరకు ట్రిప్ వెళ్లాము", "ట్రిప్ వెళ్లాము 3 మార్చి నుండి 5 మార్చి వరకు",
        // A letter or sign glued to the end that is not న, కి, or కు makes it another word.
        "సెలవు 3 నుండి 5 మార్చిలో", "సెలవు 3 నుండి 5 మార్చిని", "సెలవు 3 నుండి 5 మార్చినుండి",
      ], languages: ["te"])
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 మార్చి")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("Sprint", "12-20 మార్చి", "2027-03-12", "2027-03-20")], languages: ["te"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("సెలవు 3 నుండి 5 మార్చి రేపు")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "సెలవు రేపు")
    let timed = parse("సెలవు 3 నుండి 5 మార్చి సాయంత్రం 6 గంటలకు")
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "సెలవు")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("రిపోర్ట్ సోమవారం నుండి బుధవారం వరకు")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "రిపోర్ట్")
    #expect(span.phrases.map(\.text) == ["సోమవారం నుండి బుధవారం వరకు"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("ట్రిప్ శుక్రవారం నుండి సోమవారం వరకు", 3, 6), ("ట్రిప్ శనివారం నుండి ఆదివారం వరకు", 4, 5),
      ("ట్రిప్ శుక్రవారం నుంచి ఆదివారం", 3, 5), ("ట్రిప్ శుక్రవారం నుండి ఆదివారం వరకూ", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("శిబిరం మంగళవారం నుండి గురువారం వరకు", 7, 9), ("శిబిరం బుధవారం నుండి శుక్రవారం వరకు", 1, 3),
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
        "జిమ్ సోమవారం నుండి శుక్రవారం వరకు", "శిక్షణ సోమవారం నుండి శుక్రవారం", "శిక్షణ సోమవారం నుంచి శుక్రవారం వరకు",
      ], languages: ["te"])
    // A span in the past, or one that a genitive follows, is no plan.
    expectLinesUnread(
      ["సోమవారం నుండి బుధవారపు సెలవు", "సోమవారం నుండి బుధవారం వరకు ట్రిప్ వెళ్లాము"], languages: ["te"])
  }

  // MARK: - Due days

  @Test("Due days: వరకు, లోగా, లోపు, కల్లా, నాటికి, and the labels గడువు and డెడ్‌లైన్")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("రిపోర్ట్ పంపండి శుక్రవారం వరకు", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం వరకూ", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం దాకా", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారంలోగా", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం లోగా", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం లోపు", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం లోపల", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం కల్లా", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారానికల్లా", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం నాటికి", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి మంగళవారం వరకు", "రిపోర్ట్ పంపండి", 7),
      ("రిపోర్ట్ పంపండి వచ్చే శుక్రవారం వరకు", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి తదుపరి శుక్రవారం వరకు", "రిపోర్ట్ పంపండి", 10),
      ("రిపోర్ట్ పంపండి ఈ శుక్రవారం వరకు", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి రేపటి వరకు", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి రేపటిలోగా", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి రేపటి లోపు", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి రేపు లోగా", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి రేపటికల్లా", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి ఎల్లుండి వరకు", "రిపోర్ట్ పంపండి", 2),
      ("రిపోర్ట్ పంపండి ఎల్లుండికల్లా", "రిపోర్ట్ పంపండి", 2),
      ("రిపోర్ట్ పంపండి రేపు సాయంత్రం వరకు", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి రేపు ఉదయంలోగా", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి శుక్రవారం రాత్రి వరకు", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి ఈరోజు లోగా", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి ఈ రోజు లోపు", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి ఈరోజు కల్లా", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి ఇవాళ్టిలోగా", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి ఈ రాత్రి వరకు", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి ఈరోజు రాత్రి వరకు", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి ఈరోజు సాయంత్రం లోపు", "రిపోర్ట్ పంపండి", 0),
      ("రేపు సాయంత్రం వరకు రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి 5 మే వరకు", "రిపోర్ట్ పంపండి", captureDayOffset("2027-05-05")),
      ("రిపోర్ట్ పంపండి 5 మే లోగా", "రిపోర్ట్ పంపండి", captureDayOffset("2027-05-05")),
      ("రిపోర్ట్ పంపండి 15 అక్టోబర్ వరకు", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి అక్టోబర్ 15 నాటికి", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి 5వ తేదీ లోపు", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-05")),
      ("రిపోర్ట్ పంపండి గడువు శుక్రవారం", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి గడువు: శుక్రవారం", "రిపోర్ట్ పంపండి", 3),
      ("గడువు: శుక్రవారం రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి గడువు: ఈరోజు", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి గడువు: రేపు", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి గడువు: ఎల్లుండి", "రిపోర్ట్ పంపండి", 2),
      ("రిపోర్ట్ పంపండి గడువు: రేపు సాయంత్రం", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి గడువు: 5 మే", "రిపోర్ట్ పంపండి", captureDayOffset("2027-05-05")),
      ("రిపోర్ట్ పంపండి గడువు: 15 అక్టో", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి గడువు: గురువారం, 15 అక్టోబర్", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి గడువు: గురువారం 15 అక్టోబర్", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి గడువు: 15 అక్టోబర్, గురువారం", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి గడువు తేదీ: గురువారం, 15 అక్టోబర్", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి గడువు తేదీ: అక్టోబర్ 15", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి గడువు తేదీ అక్టోబర్ 15", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి చివరి తేదీ: 5 మే", "రిపోర్ట్ పంపండి", captureDayOffset("2027-05-05")),
      ("రిపోర్ట్ పంపండి ఆఖరి తేదీ శుక్రవారం", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి డెడ్\u{200C}లైన్: రేపు", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి డెడ్\u{200C}లైన్ శుక్రవారం", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి డెడ్ లైన్ శుక్రవారం", "రిపోర్ట్ పంపండి", 3),
      ("డెడ్\u{200C}లైన్ శుక్రవారం రిపోర్ట్ పంపండి", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి శుక్రవారం గడువు", "రిపోర్ట్ పంపండి", 3),
      ("రిపోర్ట్ పంపండి రేపు గడువు", "రిపోర్ట్ పంపండి", 1),
      ("రిపోర్ట్ పంపండి ఈరోజు గడువు", "రిపోర్ట్ పంపండి", 0),
      ("రిపోర్ట్ పంపండి 15 అక్టో గడువు", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
      ("రిపోర్ట్ పంపండి 15 అక్టోబర్ గడువు", "రిపోర్ట్ పంపండి", captureDayOffset("2026-10-15")),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("రిపోర్ట్ పంపండి శుక్రవారం వరకు రేపు")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "రిపోర్ట్ పంపండి")
  }

  @Test("\"ఈరోజు వరకు\" means \"so far\", and a deadline that has passed or that a genitive follows is no deadline")
  func notDueDays() {
    expectLinesUnread(
      [
        "రిపోర్ట్ ఈరోజు వరకు", "రిపోర్ట్ ఈరోజు వరకూ", "రిపోర్ట్ ఈరోజు దాకా", "శుక్రవారం గడువు మీరింది",
        "శుక్రవారం గడువు ముగిసింది", "శుక్రవారం గడువు దాటింది", "రిపోర్ట్ గడువు మీరింది", "శుక్రవారపు రిపోర్ట్",
        "రేపు గడువు తేదీ ముగిసింది", "గడువు: శుక్రవారం, కానీ గడువు మీరింది",
      ], languages: ["te"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "రిపోర్ట్ పంపండి 5 గంటలలోగా", "రిపోర్ట్ పంపండి సాయంత్రం 6 గంటల లోపు", "రిపోర్ట్ పంపండి 5 గంటలకల్లా",
        "రిపోర్ట్ పంపండి 5 గంటల వరకు", "రిపోర్ట్ పంపండి 18:00 వరకు", "రిపోర్ట్ పంపండి 3 PM లోపు",
        "రిపోర్ట్ పంపండి 5 గంటల తర్వాత", "రిపోర్ట్ పంపండి 5 గంటలకు ముందు", "రిపోర్ట్ పంపండి సాయంత్రం 6 లోపు",
        "రిపోర్ట్ పంపండి ఐదున్నర గంటలలోగా", "రిపోర్ట్ పంపండి అర్ధరాత్రి వరకు", "రిపోర్ట్ పంపండి అర్ధరాత్రి తర్వాత",
        "రిపోర్ట్ పంపండి 3 PM లోగా", "రిపోర్ట్ పంపండి సాయంత్రం 5 గంటలకు ముందు", "రిపోర్ట్ పంపండి 5 గంటలకి ముందు",
        "రిపోర్ట్ పంపండి 5 గంటల ముందు", "రిపోర్ట్ పంపండి ఐదు గంటలకు ముందు", "రిపోర్ట్ పంపండి 5 గంటలకు ముందే",
      ], languages: ["te"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("రిపోర్ట్ పంపండి శుక్రవారం సాయంత్రం 5 గంటలలోగా")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "రిపోర్ట్ పంపండి సాయంత్రం 5 గంటలలోగా")
    let tomorrow = parse("రిపోర్ట్ పంపండి రేపు 5 గంటలలోగా")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "రిపోర్ట్ పంపండి 5 గంటలలోగా")
    let clock = parse("రిపోర్ట్ పంపండి రేపు 18:00 వరకు")
    #expect(clock.dueDayOffset == 1)
    #expect(clock.startMinutes == nil)
    #expect(clock.title == "రిపోర్ట్ పంపండి 18:00 వరకు")
    // A planned day beside the clock deadline reads, and the clock stays.
    let day = parse("రిపోర్ట్ పంపండి 5 గంటలలోగా రేపు")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    #expect(day.title == "రిపోర్ట్ పంపండి 5 గంటలలోగా")
    // A time range that ends in "వరకు" is still a range.
    let range = parse("మీటింగ్ 2 గంటల నుండి 4 గంటల వరకు")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "మీటింగ్")
    // Without Telugu, English reads the clock time and leaves the word.
    let english = parse("రిపోర్ట్ పంపండి 18:00 వరకు", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "రిపోర్ట్ పంపండి వరకు")
  }

  // MARK: - Times

  @Test("Clock times: గంటలకు after the hour, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("మీటింగ్ 5 గంటలకు", "మీటింగ్", 17 * 60), ("మీటింగ్ 5:30 గంటలకు", "మీటింగ్", 17 * 60 + 30),
      ("మీటింగ్ 5.30 గంటలకు", "మీటింగ్", 17 * 60 + 30), ("మీటింగ్ 5 గంటలకి", "మీటింగ్", 17 * 60),
      ("మీటింగ్ 5 గంటలకే", "మీటింగ్", 17 * 60), ("మీటింగ్ 1 గంటకు", "మీటింగ్", 13 * 60),
      ("5 గంటలకు మీటింగ్", "మీటింగ్", 17 * 60), ("మీటింగ్ సరిగ్గా 5 గంటలకు", "మీటింగ్", 17 * 60),
      ("మీటింగ్ ఖచ్చితంగా 5 గంటలకు", "మీటింగ్", 17 * 60), ("మీటింగ్ సుమారు 5 గంటలకు", "మీటింగ్", 17 * 60),
      ("మీటింగ్ దాదాపు 5 గంటలకు", "మీటింగ్", 17 * 60), ("మీటింగ్ 5 గంటల ప్రాంతంలో", "మీటింగ్", 17 * 60),
      ("మీటింగ్ 5 గంటల సమయంలో", "మీటింగ్", 17 * 60), ("మీటింగ్ 5 గంటల నుండి", "మీటింగ్", 17 * 60),
      ("మీటింగ్ ఉదయం 9 గంటలకు", "మీటింగ్", 9 * 60), ("మీటింగ్ ఉదయం 9కి", "మీటింగ్", 9 * 60),
      ("మీటింగ్ ఉదయం 9:30", "మీటింగ్", 9 * 60 + 30), ("మీటింగ్ ఉదయం 9.30", "మీటింగ్", 9 * 60 + 30),
      ("మీటింగ్ ఉదయం 9:30 గంటలకు", "మీటింగ్", 9 * 60 + 30), ("మీటింగ్ ఉదయం 6.15కి", "మీటింగ్", 6 * 60 + 15),
      ("మీటింగ్ ఉదయం 7 గంటలకే", "మీటింగ్", 7 * 60), ("మీటింగ్ ఉదయాన్నే 6 గంటలకు", "మీటింగ్", 6 * 60),
      ("మీటింగ్ తెల్లవారుజామున 4 గంటలకు", "మీటింగ్", 4 * 60), ("మీటింగ్ మధ్యాహ్నం 12 గంటలకు", "మీటింగ్", 12 * 60),
      ("మీటింగ్ మధ్యాహ్నం 1 గంటకు", "మీటింగ్", 13 * 60), ("మీటింగ్ మధ్యాహ్నం ఒంటి గంటకు", "మీటింగ్", 13 * 60),
      ("మీటింగ్ మధ్యాహ్నం 2 గంటలకు", "మీటింగ్", 14 * 60), ("మీటింగ్ మధ్యాహ్నం 3:30 గంటలకు", "మీటింగ్", 15 * 60 + 30),
      ("మీటింగ్ సాయంత్రం 5 గంటలకు", "మీటింగ్", 17 * 60), ("మీటింగ్ సాయంత్రం 5కి", "మీటింగ్", 17 * 60),
      ("మీటింగ్ సాయంత్రం 5కే", "మీటింగ్", 17 * 60), ("మీటింగ్ సాయంత్రం 6:30 గంటలకు", "మీటింగ్", 18 * 60 + 30),
      ("మీటింగ్ సాయంత్రం 7 గంటలకు", "మీటింగ్", 19 * 60), ("మీటింగ్ సాయంకాలం 7 గంటలకు", "మీటింగ్", 19 * 60),
      ("మీటింగ్ రాత్రి 10 గంటలకు", "మీటింగ్", 22 * 60), ("మీటింగ్ రాత్రి 9 గంటలకు", "మీటింగ్", 21 * 60),
      ("మీటింగ్ రాత్రి 11కు", "మీటింగ్", 23 * 60), ("మీటింగ్ రాత్రి 8:30కి", "మీటింగ్", 20 * 60 + 30),
      ("మీటింగ్ రాత్రి 10.30", "మీటింగ్", 22 * 60 + 30), ("మీటింగ్ రాత్రి సరిగ్గా 10 గంటలకు", "మీటింగ్", 22 * 60),
      ("మీటింగ్ సాయంత్రం ఐదింటికి", "మీటింగ్", 17 * 60), ("మీటింగ్ ఉదయం ఎనిమిదింటికి", "మీటింగ్", 8 * 60),
      ("మీటింగ్ రాత్రి పదింటికి", "మీటింగ్", 22 * 60), ("మీటింగ్ మధ్యాహ్నం రెండింటికి", "మీటింగ్", 14 * 60),
      ("మీటింగ్ 17:30కి", "మీటింగ్", 17 * 60 + 30), ("మీటింగ్ 17:30 కి", "మీటింగ్", 17 * 60 + 30),
      ("మీటింగ్ 3:30 PMకి", "మీటింగ్", 15 * 60 + 30), ("మీటింగ్ 5 PMకి", "మీటింగ్", 17 * 60),
      ("మీటింగ్ 3:30 AMకి", "మీటింగ్", 3 * 60 + 30), ("మీటింగ్ 17:30", "మీటింగ్", 17 * 60 + 30),
      ("మీటింగ్ 5 PM", "మీటింగ్", 17 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day after the time is not read, and it names the half of
    // the day of the hour all the same.
    let after = parse("మీటింగ్ 5 గంటలకు ఉదయం")
    #expect(after.startMinutes == 5 * 60)
    #expect(after.title == "మీటింగ్ ఉదయం")
    let evening = parse("మీటింగ్ 7 గంటలకు సాయంత్రం")
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "మీటింగ్ సాయంత్రం")
    // The part of the day written before the hour wins over one written after it.
    let both = parse("మీటింగ్ ఉదయం 9 గంటలకు సాయంత్రం")
    #expect(both.startMinutes == 9 * 60)
    #expect(both.title == "మీటింగ్ సాయంత్రం")
    // Twelve in the morning is no time, and neither is 24 o'clock.
    expectLinesUnread(["మీటింగ్ ఉదయం 12 గంటలకు", "మీటింగ్ 24 గంటలకు"], languages: ["te"])
  }

  @Test("An hour as a number word is read with its ending")
  func numberWordHours() {
    let hours: [(word: String, minutes: Int)] = [
      ("ఒంటి గంటకు", 13 * 60), ("రెండు గంటలకు", 14 * 60), ("మూడు గంటలకు", 15 * 60), ("నాలుగు గంటలకు", 16 * 60),
      ("ఐదు గంటలకు", 17 * 60), ("అయిదు గంటలకు", 17 * 60), ("ఆరు గంటలకు", 18 * 60), ("ఏడు గంటలకు", 7 * 60),
      ("ఎనిమిది గంటలకు", 8 * 60), ("తొమ్మిది గంటలకు", 9 * 60), ("పది గంటలకు", 10 * 60),
      ("పదకొండు గంటలకు", 11 * 60), ("పన్నెండు గంటలకు", 12 * 60),
    ]
    for hour in hours {
      let text = "మీటింగ్ \(hour.word)"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "మీటింగ్", "\(text): title")
    }
    #expect(parse("మీటింగ్ ఉదయం తొమ్మిది గంటలకు").startMinutes == 9 * 60)
    #expect(parse("మీటింగ్ సాయంత్రం ఆరు గంటలకు").startMinutes == 18 * 60)
    // A number word is a count anywhere else, the spoken dative hour is the
    // dative of a count without a part of the day, and an hour without an
    // ending is an amount.
    expectLinesUnread(
      [
        "మీటింగ్ ఐదు", "మీటింగ్ ఒక", "ఐదు పుస్తకాలు కొనాలి", "రెండు గుడ్లు తేవాలి", "మీటింగ్ మూడు నుండి ఐదు",
        "పన్నెండింటికి మీటింగ్", "మీటింగ్ ఐదింటికి",
      ], languages: ["te"])
    // "ఐదు గంటలు" is an amount of hours, not a time.
    let length = parse("మీటింగ్ ఐదు గంటలు")
    #expect(length.startMinutes == nil)
    #expect(length.estimatedMinutes == 300)
  }

  @Test("Half hours: ఐదున్నర is 5:30, read with an ending or after a part of the day")
  func clockFractions() {
    let fractions: [(text: String, minutes: Int)] = [
      ("మీటింగ్ ఐదున్నరకు", 17 * 60 + 30), ("మీటింగ్ ఐదున్నర గంటలకు", 17 * 60 + 30),
      ("మీటింగ్ అయిదున్నరకు", 17 * 60 + 30), ("మీటింగ్ మూడున్నరకు", 15 * 60 + 30),
      ("మీటింగ్ ఆరున్నరకు", 18 * 60 + 30), ("మీటింగ్ ఏడున్నరకు", 7 * 60 + 30),
      ("మీటింగ్ ఎనిమిదిన్నరకు", 8 * 60 + 30), ("మీటింగ్ పదకొండున్నరకు", 11 * 60 + 30),
      ("మీటింగ్ పన్నెండున్నరకు", 12 * 60 + 30), ("మీటింగ్ రెండున్నరకు", 14 * 60 + 30),
      ("మీటింగ్ నాలుగున్నరకు", 16 * 60 + 30), ("మీటింగ్ ఒంటిగంటన్నరకు", 13 * 60 + 30),
      ("మీటింగ్ ఒంటి గంటన్నరకు", 13 * 60 + 30), ("మీటింగ్ ఒకటిన్నరకు", 13 * 60 + 30),
      ("మీటింగ్ ఉదయం ఎనిమిదిన్నరకు", 8 * 60 + 30), ("మీటింగ్ సాయంత్రం ఐదున్నర", 17 * 60 + 30),
      ("మీటింగ్ రాత్రి తొమ్మిదిన్నర", 21 * 60 + 30), ("మీటింగ్ మధ్యాహ్నం ఒకటిన్నర", 13 * 60 + 30),
      ("మీటింగ్ సరిగ్గా ఐదున్నరకు", 17 * 60 + 30), ("ఐదున్నరకు మీటింగ్", 17 * 60 + 30),
    ]
    for line in fractions {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "మీటింగ్", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The word is a number too, so it is a time only with an ending or a part of the day.
    expectLinesUnread(["మీటింగ్ ఐదున్నర", "ఒంటి గంటన్నర భోజనం", "ఐదున్నర కిలోలు"], languages: ["te"])
    // The quarters of the clock are never read.
    expectLinesUnread(["మీటింగ్ పావు తక్కువ ఆరు"], languages: ["te"])
  }

  @Test("The minutes of an hour with the dative of నిమిషాలు: \"10 గంటల 30 నిమిషాలకు\" is 10:30")
  func minutesAfterHour() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("ఉదయం 10 గంటల 30 నిమిషాలకు మీటింగ్", "మీటింగ్", 10 * 60 + 30),
      ("ఉదయం 9 గంటల 15 నిమిషాలకు మీటింగ్", "మీటింగ్", 9 * 60 + 15),
      ("5 గంటల 30 నిమిషాలకు మీటింగ్", "మీటింగ్", 17 * 60 + 30),
      ("2 గంటల 30 నిమిషాలకు మీటింగ్", "మీటింగ్", 14 * 60 + 30),
      ("ఉదయం 9 గంటల పదిహేను నిమిషాలకు మీటింగ్", "మీటింగ్", 9 * 60 + 15),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
    }
    // Minutes with no dative are an amount of time: 5 hours and 30 minutes.
    let length = parse("5 గంటల 30 నిమిషాలు మీటింగ్")
    #expect(length.estimatedMinutes == 330)
    #expect(length.startMinutes == nil)
    #expect(length.title == "మీటింగ్")
  }

  @Test("After midnight: రాత్రి runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("మీటింగ్ రాత్రి 2 గంటలకు")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "మీటింగ్")
    let twelve = parse("మీటింగ్ రాత్రి 12 గంటలకు")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    let spoken = parse("మీటింగ్ రాత్రి పన్నెండింటికి")
    #expect(spoken.startMinutes == 0)
    #expect(spoken.plannedDayOffset == 1)
    for text in ["మీటింగ్ అర్ధరాత్రి", "మీటింగ్ అర్థరాత్రి", "మీటింగ్ అర్ధరాత్రికి", "మీటింగ్ ఈ అర్ధరాత్రి", "మీటింగ్ సరిగ్గా అర్ధరాత్రి", "మీటింగ్ మిడ్\u{200C}నైట్"] {
      let midnight = parse(text)
      #expect(midnight.startMinutes == 0, "\(text)")
      #expect(midnight.plannedDayOffset == 1, "\(text)")
      #expect(midnight.title == "మీటింగ్", "\(text): title")
    }
    // The night counts from the evening: 6 to 11 is the evening's.
    #expect(parse("మీటింగ్ రాత్రి 6 గంటలకు").startMinutes == 18 * 60)
    #expect(parse("మీటింగ్ రాత్రి 6 గంటలకు").plannedDayOffset == nil)
    // A named day keeps the time on its own night: "రేపు రాత్రి 1 గంటకు" is 01:00 of the day after.
    let tomorrow = parse("రేపు రాత్రి 1 గంటకు నిద్ర")
    #expect(tomorrow.startMinutes == 60)
    #expect(tomorrow.plannedDayOffset == 2)
    #expect(tomorrow.title == "నిద్ర")
    let friday = parse("శుక్రవారం రాత్రి 1 గంటకు ఫ్లైట్")
    #expect(friday.startMinutes == 60)
    #expect(friday.plannedDayOffset == 4)
    let named = parse("సోమవారం రాత్రి 12 గంటలకు ఫ్లైట్")
    #expect(named.startMinutes == 0)
    #expect(named.plannedDayOffset == 7)
    #expect(named.title == "ఫ్లైట్")
    let tonight = parse("ఈరోజు రాత్రి 12 గంటలకు మీటింగ్")
    #expect(tonight.startMinutes == 0)
    #expect(tonight.plannedDayOffset == 1)
    // A repeat moves to the day after, so the rule and the time agree.
    let repeating = parse("ప్రతి శుక్రవారం రాత్రి 12 గంటలకు ఫ్లైట్")
    #expect(repeating.startMinutes == 0)
    #expect(repeating.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(repeating.recurrenceStartOffset == 4)
    #expect(repeating.title == "ఫ్లైట్")
    // A midnight deadline is no time.
    expectLinesUnread(["రిపోర్ట్ పంపండి అర్ధరాత్రి వరకు"], languages: ["te"])
  }

  @Test("The loanword మిడ్‌నైట్ is the midnight alone or with an ending, and it starts the system's colour names")
  func midnightLoanword() {
    let loanword = "మిడ్\u{200C}నైట్"
    // A Telugu word after it makes it the first word of a colour name: nothing is read.
    expectLinesUnread(
      [
        "\(loanword) బ్లూ", "\(loanword) బ్లాక్", "\(loanword) స్కై", "\(loanword) బ్లూ కారు కొను", "మిడ్ నైట్ బ్లూ",
      ], languages: ["te"])
    // It names no part of the day there: a day word beside it, a bare hour elsewhere in the line,
    // and a weekday with a deadline keep their own readings.
    let tomorrow = parse("రేపు \(loanword) బ్లూ కారు కొను")
    #expect(tomorrow.plannedDayOffset == 1)
    #expect(tomorrow.startMinutes == nil)
    #expect(tomorrow.title == "\(loanword) బ్లూ కారు కొను")
    let morning = parse("\(loanword) బ్లూ కారు 8 గంటలకు")
    #expect(morning.startMinutes == 8 * 60)
    #expect(morning.plannedDayOffset == nil)
    #expect(morning.title == "\(loanword) బ్లూ కారు")
    let afternoon = parse("కారు \(loanword) బ్లూ 5 గంటలకు")
    #expect(afternoon.startMinutes == 17 * 60)
    #expect(afternoon.plannedDayOffset == nil)
    #expect(afternoon.title == "కారు \(loanword) బ్లూ")
    // With no other Telugu word after it, with a dative ending, or with an hour, it is the midnight
    // that ends the day, as అర్ధరాత్రి is.
    let midnights: [(text: String, title: String, day: Int)] = [
      ("కారు \(loanword)", "కారు", 1), ("కారు మిడ్ నైట్", "కారు", 1),
      ("కారు \(loanword)\u{200C}కి అమ్ము", "కారు అమ్ము", 1), ("కారు రేపు \(loanword)", "కారు", 2),
      ("కారు రేపు \(loanword)\u{200C}కి అమ్ము", "కారు అమ్ము", 2), ("\(loanword) 12 గంటలకు అమ్ము", "అమ్ము", 1),
      ("ఈరోజు \(loanword) 12 గంటలకు అమ్ము", "అమ్ము", 1),
    ]
    for line in midnights {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == 0, "\(line.text)")
      #expect(parsed.plannedDayOffset == line.day, "\(line.text): day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // After a weekday, a bound word keeps it a midnight: the deadline is Friday's.
    let due = parse("రిపోర్ట్ పంపండి శుక్రవారం \(loanword) వరకు")
    #expect(due.dueDayOffset == 3)
    #expect(due.title == "రిపోర్ట్ పంపండి")
    expectLinesUnread(["రిపోర్ట్ పంపండి \(loanword) వరకు"], languages: ["te"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("మీటింగ్ 1 గంటకు").startMinutes == 13 * 60)
    #expect(parse("మీటింగ్ 3 గంటలకు").startMinutes == 15 * 60)
    #expect(parse("మీటింగ్ 6 గంటలకు").startMinutes == 18 * 60)
    #expect(parse("మీటింగ్ 7 గంటలకు").startMinutes == 7 * 60)
    #expect(parse("మీటింగ్ 9 గంటలకు").startMinutes == 9 * 60)
    #expect(parse("మీటింగ్ 11 గంటలకు").startMinutes == 11 * 60)
    #expect(parse("మీటింగ్ 12 గంటలకు").startMinutes == 12 * 60)
    #expect(parse("మీటింగ్ 13 గంటలకు").startMinutes == 13 * 60)
    #expect(parse("మీటింగ్ 06:30 గంటలకు").startMinutes == 6 * 60 + 30)
    #expect(parse("మీటింగ్ 03:00 గంటలకు").startMinutes == 3 * 60)
    #expect(parse("మీటింగ్ 3:00 గంటలకు").startMinutes == 15 * 60)
    // A part of the day names the half of the day either way.
    #expect(parse("మీటింగ్ ఉదయం 5 గంటలకు").startMinutes == 5 * 60)
    #expect(parse("మీటింగ్ సాయంత్రం 5 గంటలకు").startMinutes == 17 * 60)
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("ఉదయపు నడక 6 గంటలకు", "ఉదయపు నడక", 6 * 60), ("6 గంటలకు ఉదయపు నడక", "ఉదయపు నడక", 6 * 60),
      ("ఉదయపు నడక 5 గంటలకు", "ఉదయపు నడక", 5 * 60), ("రాత్రి భోజనం 8 గంటలకు", "రాత్రి భోజనం", 20 * 60),
      ("రాత్రి భోజనం 6 గంటలకు", "రాత్రి భోజనం", 18 * 60),
      ("రాత్రి భోజనం ఎనిమిదిన్నరకు", "రాత్రి భోజనం", 20 * 60 + 30),
      ("రాత్రి మందులు 10 గంటలకు", "రాత్రి మందులు", 22 * 60), ("సాయంత్రపు టీ 5 గంటలకు", "సాయంత్రపు టీ", 17 * 60),
      ("మధ్యాహ్నం భోజనం 1 గంటకు", "మధ్యాహ్నం భోజనం", 13 * 60),
      ("మధ్యాహ్నం భోజనం 2 గంటలకు", "మధ్యాహ్నం భోజనం", 14 * 60),
      // The 24-hour clock is read as written: a leading zero, or 13 and later.
      ("రాత్రి భోజనం 20:00 గంటలకు", "రాత్రి భోజనం", 20 * 60),
      ("రాత్రి డ్యూటీ 06:30 గంటలకు", "రాత్రి డ్యూటీ", 6 * 60 + 30),
      // Noon is no morning hour, so a morning's 12 stays as written.
      ("ఉదయం సమావేశం 12 గంటలకు", "ఉదయం సమావేశం", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The part of the day may come from the repeat, which keeps its words.
    let yoga = parse("రోజూ ఉదయం 6 గంటలకు యోగా")
    #expect(yoga.startMinutes == 6 * 60)
    #expect(yoga.recurrence == daily)
    #expect(yoga.title == "యోగా")
    // Two parts that differ leave the hour as it reads alone.
    #expect(parse("ఉదయం టీ, సాయంత్రం స్నాక్స్ 5 గంటలకు").startMinutes == 17 * 60)
  }

  @Test("Time ranges: నుండి and నుంచి, a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("మీటింగ్ 3 గంటల నుండి 5 గంటల వరకు", 15 * 60, 120), ("మీటింగ్ 9 గంటల నుండి 11 గంటల వరకు", 9 * 60, 120),
      ("మీటింగ్ 3 నుండి 5 గంటల వరకు", 15 * 60, 120), ("మీటింగ్ ఉదయం 9 నుండి 11 వరకు", 9 * 60, 120),
      ("మీటింగ్ ఉదయం 9 నుంచి 11 వరకు", 9 * 60, 120), ("మీటింగ్ ఉదయం 9 గంటల నుండి 11 గంటల వరకు", 9 * 60, 120),
      ("మీటింగ్ సాయంత్రం 5 నుండి 7 వరకు", 17 * 60, 120), ("మీటింగ్ రాత్రి 8 నుండి 10 వరకు", 20 * 60, 120),
      ("మీటింగ్ మధ్యాహ్నం 2 నుండి సాయంత్రం 4 వరకు", 14 * 60, 120), ("మీటింగ్ 9-11 గంటలకు", 9 * 60, 120),
      ("మీటింగ్ 2-4 గంటలకు", 14 * 60, 120), ("మీటింగ్ 9 గంటల నుండి 5 గంటల వరకు", 9 * 60, 480),
      ("మీటింగ్ 14:00 నుండి 16:00 వరకు", 14 * 60, 120), ("మీటింగ్ 9:30 నుండి 10:30 వరకు", 9 * 60 + 30, 60),
      ("మీటింగ్ 14:00 నుంచి 16:00", 14 * 60, 120), ("మీటింగ్ ఉదయం 9:00 నుండి సాయంత్రం 5:00 వరకు", 9 * 60, 480),
      ("మీటింగ్ ఐదు నుండి ఆరు గంటల వరకు", 17 * 60, 60), ("మీటింగ్ ఏడు గంటల నుండి ఎనిమిది గంటల వరకు", 7 * 60, 60),
      ("మీటింగ్ రాత్రి 11 నుండి 1 వరకు", 23 * 60, 120), ("మీటింగ్ రాత్రి 10 నుండి 12 వరకు", 22 * 60, 120),
      ("మీటింగ్ ఉదయం 11 నుండి మధ్యాహ్నం 1 వరకు", 11 * 60, 120), ("మీటింగ్ మధ్యాహ్నం 12 నుండి 2 వరకు", 12 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "మీటింగ్", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Two bare numbers are no range of hours: the range needs a part of the day or గంటల.
    expectLinesUnread(["మీటింగ్ 3 నుండి 5 వరకు", "మీటింగ్ 9-11", "మీటింగ్ ఒకటి నుండి రెండు గంటల వరకు"], languages: ["te"])
    // A length written in the line wins over the span of the range.
    let named = parse("మీటింగ్ 3 గంటల నుండి 5 గంటల వరకు 30 నిమిషాలు")
    #expect(named.startMinutes == 15 * 60)
    #expect(named.estimatedMinutes == 30)
    #expect(named.title == "మీటింగ్")
    // A range written with a dash and colon times is English's.
    let dashed = parse("మీటింగ్ 9:00-11:00")
    #expect(dashed.startMinutes == 9 * 60)
    #expect(dashed.estimatedMinutes == 120)
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amounts() {
    expectLinesUnread(
      [
        "3 మందితో మీటింగ్", "మీటింగ్‌కు 3 మంది వస్తారు", "5 పుస్తకాలు కొనాలి", "10 పేజీలు చదవాలి",
        "2 కిలోల పంచదార తేవాలి", "12 గుడ్లు తేవాలి", "500 రూపాయల బిల్లు కట్టాలి", "₹500 బిల్లు", "బిల్లు ₹500",
        "5 డాలర్లు ఖర్చు", "20% తగ్గింపు", "20 % తగ్గింపు", "2 క్లాసులు తీసుకోవాలి", "5కి మీటింగ్",
        // A number after a slash is a fraction or a date, never an hour.
        "మీటింగ్ 5/6 గంటలకు", "మీటింగ్ 1/2 గంటలకు", "మీటింగ్ ౫/౬ గంటలకు",
      ], languages: ["te"])
    // The words around an amount still read.
    let bill = parse("500 రూపాయల బిల్లు కట్టాలి రేపు")
    #expect(bill.plannedDayOffset == 1)
    #expect(bill.title == "500 రూపాయల బిల్లు కట్టాలి")
    let price = parse("500 రూపాయలు 5 గంటలకు")
    #expect(price.startMinutes == 17 * 60)
    #expect(price.title == "500 రూపాయలు")
    let percent = parse("మీటింగ్ 5 గంటలకు 20%")
    #expect(percent.startMinutes == 17 * 60)
    #expect(percent.title == "మీటింగ్ 20%")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("30 నిమిషాలు", 30), ("45 నిమిషాలు", 45), ("90 నిమిషాలు", 90), ("2 నిమిషాలు", 2), ("1 నిమిషం", 1),
      ("30నిమిషాలు", 30), ("30 నిమి.", 30), ("30 నిముషాలు", 30), ("2 గంటలు", 120), ("2గంటలు", 120), ("1 గంట", 60),
      ("1.5 గంటలు", 90), ("2 గం.", 120), ("1 గంట 30 నిమిషాలు", 90), ("1 గంట, 30 నిమిషాలు", 90),
      ("1 గం., 30 నిమి.", 90), ("1 గంట మరియు 30 నిమిషాలు", 90), ("2 గంటలు 30 నిమిషాలు", 150),
      ("5 గంటల 30 నిమిషాలు", 330), ("అరగంట", 30), ("అర గంట", 30), ("అర్ధ గంట", 30), ("అర్థ గంట", 30),
      ("పావు గంట", 15), ("పావుగంట", 15), ("ముప్పావు గంట", 45), ("గంటన్నర", 90), ("రెండున్నర గంటలు", 150),
      ("ఒకటిన్నర గంటలు", 90), ("రెండు గంటలు", 120), ("మూడు గంటలు", 180), ("ఒక గంట", 60), ("ఒక్క గంట", 60),
      ("గంటసేపు", 60), ("గంట సేపు", 60), ("మూడు గంటల సేపు", 180), ("2 గంటల పాటు", 120),
      ("30 నిమిషాల పాటు", 30), ("ఇరవై నిమిషాలు", 20), ("పదిహేను నిమిషాలు", 15), ("ముప్పై నిమిషాలు", 30),
      ("నలభై ఐదు నిమిషాలు", 45), ("పది నిమిషాలు", 10), ("సుమారు 2 గంటలు", 120), ("దాదాపు 30 నిమిషాలు", 30),
      ("అంచనా 1 గంట", 60), ("సుమారు అరగంట", 30), ("2 గంటల సేపు", 120), ("ఒక అర గంట", 30), ("ఒక అరగంట", 30),
      ("ఒక అర్ధ గంట", 30), ("ఒక పావు గంట", 15), ("ఒక ముప్పావు గంట", 45),
    ]
    for line in lengths {
      let text = "రిపోర్ట్ రాయండి \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "రిపోర్ట్ రాయండి", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The form of the unit that goes before a noun is read with it.
    let meeting = parse("30 నిమిషాల మీటింగ్")
    #expect(meeting.estimatedMinutes == 30)
    #expect(meeting.title == "మీటింగ్")
    #expect(meeting.phrases.map(\.text) == ["30 నిమిషాల"])
    let work = parse("2 గంటల పని")
    #expect(work.estimatedMinutes == 120)
    #expect(work.title == "పని")
    let hour = parse("1 గంట పని")
    #expect(hour.estimatedMinutes == 60)
    #expect(hour.title == "పని")
    // A time and a length together.
    let both = parse("మీటింగ్ 5 గంటలకు 45 నిమిషాలు")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "మీటింగ్")
  }

  @Test("An amount before తర్వాత, క్రితం, or లోపు, after ప్రతి, or with an ending of another word, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "రిపోర్ట్ రాయండి 2 గంటల తర్వాత", "రిపోర్ట్ రాయండి 30 నిమిషాల తర్వాత", "రిపోర్ట్ రాయండి 5 నిమిషాల క్రితం",
        "రిపోర్ట్ రాయండి 2 గంటల ముందు", "రిపోర్ట్ రాయండి 2 గంటల లోపు", "రిపోర్ట్ రాయండి 2 గంటల లోగా",
        "రిపోర్ట్ రాయండి 2 గంటల వరకు", "రిపోర్ట్ రాయండి 30 నిమిషాల వరకు", "రిపోర్ట్ రాయండి ప్రతి 2 గంటలు",
        "రిపోర్ట్ రాయండి రోజుకు 30 నిమిషాలు", "రిపోర్ట్ రాయండి కనీసం 2 గంటలు", "రిపోర్ట్ రాయండి గరిష్టంగా 2 గంటలు",
        // An ending of another word on the unit.
        "రిపోర్ట్ రాయండి 2 గంటల్లో", "రిపోర్ట్ రాయండి 30 నిమిషాల్లో", "రిపోర్ట్ రాయండి 30 నిమిషాలకు",
        // A range of amounts, an hour as a noun, and an amount no task takes.
        "రిపోర్ట్ రాయండి 2 నుండి 3 గంటలు", "రిపోర్ట్ రాయండి 2-3 గంటలు",
        "రిపోర్ట్ రాయండి 5 నిమిషాలు నుండి 10 నిమిషాలు", "రిపోర్ట్ రాయండి గంట", "రిపోర్ట్ రాయండి గంటల",
        "రిపోర్ట్ రాయండి 0 నిమిషాలు",
        // A number after a slash is a fraction, a date, or a rate, never an amount.
        "రిపోర్ట్ రాయండి 1/2 గంట", "రిపోర్ట్ రాయండి 1 1/2 గంటలు", "రిపోర్ట్ రాయండి 3/30 నిమిషాలు",
      ], languages: ["te"])
    // The phrase around an amount that is no length still reads.
    let day = parse("రిపోర్ట్ రాయండి 2 గంటల తర్వాత రేపు")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "రిపోర్ట్ రాయండి 2 గంటల తర్వాత")
    let time = parse("మీటింగ్ రేపు 3 గంటలకు 2 గంటల ముందు")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "మీటింగ్ 2 గంటల ముందు")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("ప్రతిరోజు", daily), ("ప్రతిరోజూ", daily), ("ప్రతి రోజు", daily), ("ప్రతి రోజూ", daily), ("ప్రతీ రోజు", daily),
      ("రోజూ", daily), ("రోజుకోసారి", daily), ("రోజుకు ఒకసారి", daily), ("1 రోజుకోసారి", daily),
      ("ప్రతి 1 రోజు", daily), ("రోజువారీగా", daily), ("రోజువారీ ప్రాతిపదికన", daily), ("ప్రతి వారం", weekly),
      ("వారానికి ఒకసారి", weekly), ("వారానికోసారి", weekly), ("వారంవారీగా", weekly), ("వారం వారీగా", weekly),
      ("వారంవారీ ప్రాతిపదికన", weekly), ("ప్రతి నెల", monthly), ("ప్రతి నెలా", monthly), ("నెలకు ఒకసారి", monthly),
      ("నెలకోసారి", monthly), ("నెలవారీగా", monthly), ("నెలవారీ ప్రాతిపదికన", monthly), ("ప్రతి సంవత్సరం", yearly),
      ("ప్రతి ఏడాది", yearly), ("ప్రతి ఏటా", yearly), ("సంవత్సరానికి ఒకసారి", yearly), ("ఏడాదికి ఒకసారి", yearly),
      ("సంవత్సరంవారీగా", yearly), ("ప్రతి 2 రోజులకు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి 2 రోజులు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి రెండు రోజులకు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి రెండో రోజు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి రెండవ రోజు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి రెండవ వారం", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("రోజు విడిచి రోజు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("2 రోజులకోసారి", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("2 రోజులకు ఒకసారి", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి 3 రోజులు", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("ప్రతి పదిహేను రోజులకు", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("ప్రతి 2 వారాలకు", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ప్రతి రెండు వారాలు", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ప్రతి 3 వారాలు", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("ప్రతి 2 వారాలకు ఒకసారి", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("వారం విడిచి వారం", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ప్రతి 3 నెలలకు", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ప్రతి మూడు నెలలకు", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ప్రతి 4 నెలలు", TaskRecurrenceRule(freq: .monthly, interval: 4)),
      ("3 నెలలకోసారి", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("నెల విడిచి నెల", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("ప్రతి 5 సంవత్సరాలకు", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("ప్రతి 5 సంవత్సరాలు", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("2 సంవత్సరాలకోసారి", TaskRecurrenceRule(freq: .yearly, interval: 2)),
    ]
    for line in cadences {
      let text = "మందులు వేసుకోండి \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "మందులు వేసుకోండి", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
    // The adjectives that say how a task repeats are read before a colon or with a word of their own.
    #expect(parse("నెలవారీ: అద్దె కట్టండి").recurrence == monthly)
    #expect(parse("నెలవారీ: అద్దె కట్టండి").title == "అద్దె కట్టండి")
    #expect(parse("రిపోర్ట్ రోజువారీ").recurrence == daily)
    #expect(parse("రిపోర్ట్ వారంవారీ").recurrence == weekly)
    #expect(parse("రిపోర్ట్ సంవత్సరంవారీ").recurrence == yearly)
    #expect(parse("రిపోర్ట్ రోజువారీ.").title == "రిపోర్ట్.")
  }

  @Test("Weekday repeats: ప్రతి సోమవారం, lists of days, the weekend, and the working days")
  func weekdayRepeats() {
    let coming = parse("జిమ్ ప్రతి సోమవారం")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "జిమ్")
    #expect(coming.plannedDayOffset == nil)
    for text in [
      "జిమ్ ప్రతీ సోమవారం", "జిమ్ ప్రతి సోమవారము", "జిమ్ ప్రతి సోమవారమూ", "జిమ్ సోమవారాల్లో", "జిమ్ సోమవారాలలో",
      "జిమ్ ప్రతి వారం సోమవారం", "జిమ్ సోమవారం ప్రతి వారం",
    ] {
      #expect(parse(text).recurrence == monday, "\(text)")
      #expect(parse(text).title == "జిమ్", "\(text): title")
    }

    let lists: [(text: String, days: [String])] = [
      ("జిమ్ ప్రతి సోమవారం మరియు గురువారం", ["MO", "TH"]), ("జిమ్ ప్రతి సోమవారం, బుధవారం, శుక్రవారం", ["MO", "WE", "FR"]),
      ("జిమ్ ప్రతి సోమవారం, బుధవారం మరియు శుక్రవారం", ["MO", "WE", "FR"]), ("జిమ్ ప్రతి బుధవారం", ["WE"]),
      ("జిమ్ ప్రతి శనివారం", ["SA"]), ("జిమ్ ప్రతి ఆదివారం", ["SU"]), ("జిమ్ సోమవారాల్లో, గురువారాల్లో", ["MO", "TH"]),
      ("జిమ్ ప్రతి శనివారం మరియు ఆదివారం", ["SU", "SA"]), ("జిమ్ ప్రతి వారాంతం", ["SU", "SA"]),
      ("జిమ్ ప్రతి వీకెండ్", ["SU", "SA"]), ("జిమ్ వారాంతాల్లో", ["SU", "SA"]), ("జిమ్ వారాంతాలలో", ["SU", "SA"]),
      ("జిమ్ శని ఆదివారాల్లో", ["SU", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "జిమ్", "\(line.text): title")
    }
    #expect(parse("జిమ్ ప్రతి సోమవారం మరియు గురువారం").recurrenceStartOffset == 2)
    #expect(parse("జిమ్ ప్రతి వారాంతం").recurrenceStartOffset == 4)

    // The working days, written out or as a span of weekdays beside ప్రతి or a
    // word for every day.
    for text in [
      "జిమ్ పనిదినాల్లో", "జిమ్ పని దినాల్లో", "జిమ్ పనిరోజుల్లో", "జిమ్ ప్రతి పని దినం", "జిమ్ ప్రతి పనిరోజు",
      "జిమ్ రోజూ పని దినం", "జిమ్ ప్రతి సోమవారం నుండి శుక్రవారం", "జిమ్ రోజూ సోమవారం నుండి శుక్రవారం వరకు",
      "జిమ్ సోమవారం నుండి శుక్రవారం వరకు ప్రతిరోజూ", "జిమ్ ప్రతి సోమవారం నుండి శుక్రవారం వరకు",
      "జిమ్ ప్రతి సోమవారం నుండి శుక్రవారం వరకు ఉదయం 9 గంటలకు",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
    #expect(
      parse("జిమ్ ప్రతి సోమవారం నుండి బుధవారం").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE"]))
    #expect(
      parse("జిమ్ ప్రతి ఆదివారం నుండి గురువారం").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"]))
    // A repeat that starts today starts at 0 on its own weekday.
    #expect(parse("జిమ్ ప్రతి మంగళవారం").recurrenceStartOffset == 0)
    #expect(parse("జిమ్ ప్రతి శుక్రవారం", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("యోగా రోజూ ఉదయం 6 గంటలకు", "యోగా", 6 * 60), ("రోజూ ఉదయం 6 గంటలకు యోగా", "యోగా", 6 * 60),
      ("ప్రతి సాయంత్రం 7 గంటలకు వాకింగ్", "వాకింగ్", 19 * 60), ("వాకింగ్ ప్రతి సాయంత్రం 7 గంటలకు", "వాకింగ్", 19 * 60),
      ("ప్రతి రాత్రి 10:30 గంటలకు మందులు", "మందులు", 22 * 60 + 30), ("ప్రతి ఉదయం 5 గంటలకు యోగా", "యోగా", 5 * 60),
      ("ప్రతిరోజు ఉదయం 6 గంటలకు యోగా", "యోగా", 6 * 60), ("రోజూ సాయంత్రం 7 గంటలకు వాకింగ్", "వాకింగ్", 19 * 60),
      ("ప్రతి రోజు సాయంత్రం 6 గంటలకు వాకింగ్", "వాకింగ్", 18 * 60), ("ప్రతి రాత్రి పుస్తకం చదవడం", "పుస్తకం చదవడం", nil),
      ("రోజూ ఉదయం యోగా", "యోగా", nil), ("ప్రతిరోజూ రాత్రి 10 గంటలకు మందులు", "మందులు", 22 * 60),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let range = parse("రోజూ ఉదయం 9 నుండి 11 వరకు చదువు")
    #expect(range.recurrence == daily)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "చదువు")
    // A range right after a part of the day that a repeat or "ఈ" owns is read in that part.
    let evening = parse("ప్రతి సాయంత్రం 5 నుండి 7 వరకు నడక")
    #expect(evening.recurrence == daily)
    #expect(evening.startMinutes == 17 * 60)
    #expect(evening.estimatedMinutes == 120)
    #expect(evening.title == "నడక")
    let today = parse("ఈ సాయంత్రం 5 నుండి 7 వరకు నడక")
    #expect(today.plannedDayOffset == 0)
    #expect(today.startMinutes == 17 * 60)
    #expect(today.estimatedMinutes == 120)
    #expect(today.title == "నడక")
    // Two bare numbers with a part of the day elsewhere in the line stay numbers.
    expectLinesUnread(["నడక 3 నుండి 5 వరకు", "ఉదయం చదువు 9 నుండి 11 వరకు"], languages: ["te"])
    // A line of details alone is no task.
    expectLinesUnread(["ప్రతి ఉదయం 6 గంటలకు", "ప్రతి సాయంత్రం 7 గంటలకు"], languages: ["te"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "అద్దె ప్రతి నెల 5వ తేదీన", "అద్దె ప్రతి నెల 5న", "అద్దె ప్రతి నెలా 5న", "అద్దె ప్రతి నెల 5వ తేదీ",
      "అద్దె 5వ తేదీన ప్రతి నెల", "అద్దె ప్రతి నెల 5 తేదీన",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text): start")
      #expect(parsed.title == "అద్దె", "\(text): title")
    }
    for text in ["అద్దె ప్రతి నెల 1వ తేదీన", "అద్దె ప్రతి నెల మొదటి తేదీన"] {
      let first = parse(text)
      #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]), "\(text)")
      #expect(first.recurrenceStartOffset == 9, "\(text): start")
    }
    // A date with its month name is a date, not a repeat.
    #expect(parse("అద్దె ప్రతి 5 మే").recurrence == nil)
  }

  @Test("A repeat shorter than a day, and a cadence word that describes a noun, are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        "నీళ్లు తాగండి ప్రతి 2 గంటలకు", "ప్రతి 2 గంటలకు నీళ్లు", "వారానికి రెండు సార్లు జిమ్",
        "రోజుకు మూడు సార్లు మందులు", "రోజువారీ రిపోర్ట్", "నెలవారీ జీతం", "వారంలో ఒకసారి", "రోజూవారీ ఖర్చులు",
        "రోజువారీ సమీక్ష", "వారంవారీ సమీక్ష",
        // Words that begin with ప్రతి.
        "ప్రతిభ కలిగిన విద్యార్థి", "ప్రతిజ్ఞ చేయండి", "ప్రతినిధి సమావేశం",
        // A count of weekends, workdays, or Mondays, the second Monday, and a genitive.
        "3 వారాంతాల్లో ట్రెక్", "3 పనిరోజుల్లో స్టాండప్", "3 సోమవారాల్లో జిమ్", "మూడు సోమవారాల్లో జిమ్",
        "ప్రతి రెండో సోమవారం జిమ్", "ప్రతి సోమవారపు మీటింగ్",
        // The nouns for the working days name them.
        "జిమ్ పని దినం", "జిమ్ పనిరోజు",
      ], languages: ["te"])
    // ప్రతి with a unit is a repeat whatever noun follows: a monthly task.
    let accounts = parse("ప్రతి నెల ఖర్చుల లెక్క")
    #expect(accounts.recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(accounts.title == "ఖర్చుల లెక్క")
  }

  // MARK: - Priorities

  @Test("Priorities: అధిక, సాధారణ, and తక్కువ ప్రాధాన్యత, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("అధిక ప్రాధాన్యత", .p1), ("అత్యధిక ప్రాధాన్యత", .p1), ("ఎక్కువ ప్రాధాన్యత", .p1), ("గరిష్ట ప్రాధాన్యత", .p1),
      ("గరిష్ఠ ప్రాధాన్యత", .p1), ("ప్రాధాన్యత: అధికం", .p1), ("ప్రాధాన్యత అధికం", .p1), ("ప్రాధాన్యత: గరిష్టం", .p1),
      ("సాధారణ ప్రాధాన్యత", .p2), ("మధ్యస్థ ప్రాధాన్యత", .p2), ("ప్రాధాన్యత: సాధారణం", .p2),
      ("ప్రాధాన్యత: మధ్యస్థం", .p2), ("మీడియం ప్రాధాన్యత", .p2), ("తక్కువ ప్రాధాన్యత", .p3),
      ("అత్యల్ప ప్రాధాన్యత", .p3), ("అల్ప ప్రాధాన్యత", .p3), ("కనిష్ట ప్రాధాన్యత", .p3), ("కనిష్ఠ ప్రాధాన్యత", .p3),
      ("ప్రాధాన్యత: తక్కువ", .p3), ("ప్రాధాన్యత తక్కువ", .p3), ("ప్రాధాన్యత: కనిష్టం", .p3),
      ("ప్రాధాన్యత: అల్పం", .p3),
    ]
    for level in levels {
      let text = "రిపోర్ట్ పంపండి \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "రిపోర్ట్ పంపండి", "\(text): title")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let inside = parse("రిపోర్ట్ అధిక ప్రాధాన్యత పంపండి")
    #expect(inside.priority == .p1)
    #expect(inside.title == "రిపోర్ట్ పంపండి")

    for word in [
      "అత్యవసరం", "అత్యవసరము", "ముఖ్యం", "ముఖ్యము", "ముఖ్యమైనది", "అర్జెంట్", "అర్జంట్", "అత్యంత ముఖ్యం",
      "అతి ముఖ్యం", "చాలా ముఖ్యం", "అత్యంత అత్యవసరం",
    ] {
      let text = "రిపోర్ట్ పంపండి \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "రిపోర్ట్ పంపండి", "\(text): title")
    }
    for word in ["అత్యవసరం", "ముఖ్యం", "అర్జెంట్"] {
      for separator in [":", ","] {
        let text = "\(word)\(separator) రిపోర్ట్ పంపండి"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "రిపోర్ట్ పంపండి", "\(text): title")
      }
    }
    #expect(parse("రిపోర్ట్ పంపండి అత్యవసరం.").title == "రిపోర్ట్ పంపండి.")
    // An urgent word in the middle, or opening the line with no colon or
    // comma, is a word of the title, and so is a level that describes a noun.
    expectLinesUnread(
      [
        "అత్యవసర విభాగానికి వెళ్ళండి", "రిపోర్ట్ ముఖ్యం కాదు", "అత్యవసర రిపోర్ట్ పంపండి", "అత్యవసరంగా రిపోర్ట్",
        "ముఖ్యమైన మీటింగ్ ఉంది", "రిపోర్ట్ పంపండి ముఖ్యమైన విషయం", "అధిక ప్రాధాన్యత గల పనులు",
        "తక్కువ ప్రాధాన్యతతో రిపోర్ట్", "అధిక ప్రాధాన్యత కలిగిన జాబితా",
      ], languages: ["te"])
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("రేపు సాయంత్రం 5 గంటలకు 30 నిమిషాల మీటింగ్ #పని")
    #expect(line.title == "మీటింగ్")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["పని"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["రేపు", "సాయంత్రం 5 గంటలకు", "30 నిమిషాల", "#పని"])

    let lines: [(text: String, title: String)] = [
      ("ప్రతి సోమవారం ఉదయం 9 గంటలకు జిమ్", "జిమ్"), ("శుక్రవారం వరకు రిపోర్ట్ పంపండి అత్యవసరం", "రిపోర్ట్ పంపండి"),
      ("సోమవారం ఉదయం 9 నుండి 11 వరకు మీటింగ్", "మీటింగ్"), ("5 మే సాయంత్రం 6 గంటలకు పార్టీ", "పార్టీ"),
      ("వచ్చే శుక్రవారం వరకు 2 గంటల పని", "పని"), ("రేపు మీటింగ్ 3 గంటలకు అధిక ప్రాధాన్యత", "మీటింగ్"),
      ("రోజూ ఉదయం 7 గంటలకు మందులు", "మందులు"), ("ఈరోజు రాత్రి 11 గంటలకు నిద్ర", "నిద్ర"),
      ("అమ్మకు ఫోన్ చేయండి రేపు సాయంత్రం 5 గంటలకు", "అమ్మకు ఫోన్ చేయండి"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(parse(line.text).phrases.count >= 2, "\(line.text): phrases")
    }
    let friday = parse("శుక్రవారం వరకు రిపోర్ట్ పంపండి అత్యవసరం")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.priority == .p1)
    let weekly = parse("ప్రతి సోమవారం ఉదయం 9 గంటలకు జిమ్")
    #expect(weekly.recurrence == monday)
    #expect(weekly.startMinutes == 9 * 60)
    let report = parse("వచ్చే శుక్రవారం వరకు 2 గంటల పని")
    #expect(report.dueDayOffset == 3)
    #expect(report.estimatedMinutes == 120)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // The short weekday forms are ordinary words, names, and planets.
        "సోమశేఖర్ కి ఫోన్", "శుక్ర గ్రహం చూడాలి", "బుధ గ్రహం చూడాలి", "గురు దక్షిణ ఇవ్వాలి", "ఆది నారాయణ పూజ",
        "శని దేవాలయానికి వెళ్ళాలి", "మంగళ హారతి", "సోమ వారం",
        // Words that contain a day word, or a day word with another ending.
        "ఆరోజు మీటింగ్", "ఈ రోజుల్లో ఫోన్ వాడకం", "రేపటికల్లా", "నేటి వార్తలు", "మంగళవారాల్లో",
        // A day with a genitive after it is an attribute of a noun.
        "సోమవారపు మీటింగ్", "శుక్రవారం నాటి మీటింగ్", "రేపటి మీటింగ్",
        // A bound or an amount of days that names no day.
        "3 రోజుల్లో", "మీటింగ్ అయిన 3 రోజుల తర్వాత కాల్",
        // The Someday list, the word for hour alone, and the words for date and day.
        "పుస్తకం చదవాలి ఏదో ఒక రోజు", "గంట కొట్టండి", "తేదీ రాయండి", "రోజు వారీ కథ",
        // A bare number that is a count.
        "5 పుస్తకాలు కొనాలి", "3 మంది స్నేహితులను పిలవాలి",
      ], languages: ["te"])
    // Telugu written in Latin letters is not read.
    expectLinesUnread(
      [
        "repu udayam 9 gantalaku meeting", "ee roju gym", "prati roju gym", "2 gantalu rayali",
        "sukravaram varaku report",
      ], languages: ["te"])
    // A weekday before other words is the day.
    let friday = parse("శుక్రవారం పార్టీ ఏర్పాట్లు")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "పార్టీ ఏర్పాట్లు")
  }

  // MARK: - The past

  @Test("A line in the past tense or after a past word stays unread, and no past day is ever read")
  func tomorrowOrYesterday() {
    let coming = [
      "రేపు మీటింగ్ ఉంది", "రేపు వెళ్ళాలి", "రేపు మీటింగ్ జరుగుతుంది", "రిపోర్ట్ రేపు పంపండి", "రేపు ఈ పని చేయాలి",
      "రేపటి నుండి జిమ్ మొదలు",
    ]
    for text in coming {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        // The past days are never read.
        "నిన్న మీటింగ్", "మొన్న మీటింగ్", "నిన్న గడువు",
        // The words that say a day is past, or the month's first, second, or last.
        "గత శుక్రవారం మీటింగ్", "పోయిన శుక్రవారం మీటింగ్", "మునుపటి సోమవారం మీటింగ్", "ఆ శుక్రవారం మీటింగ్",
        "ఆఖరి శుక్రవారం పార్టీ", "చివరి శుక్రవారం పార్టీ", "మొదటి శుక్రవారం మీటింగ్", "రెండవ శనివారం సెలవు",
        "మూడో శనివారం సెలవు", "నాలుగో శనివారం సెలవు",
        // A past-tense form anywhere in the line.
        "రేపు మీటింగ్ జరిగింది", "రేపు వెళ్లాను", "ఈరోజు ఫోన్ చేశాను", "శుక్రవారం అతను వచ్చాడు",
        "ఇవాళ మీటింగ్ అయింది", "శుక్రవారం మీటింగ్ జరిగింది", "ఎల్లుండి కలిశాం", "శుక్రవారం రిపోర్ట్ పంపాను",
        "ఈరోజు మేము చూశాం", "సోమవారం ఫోన్ చేసాను", "శుక్రవారం పుస్తకం చదివాను", "ఈరోజు పాలు కొన్నాను",
        "సోమవారం డబ్బులు ఇచ్చాను", "రేపు ఉత్తరం రాశాను", "శుక్రవారం రిపోర్ట్ తీసుకున్నాను", "ఈరోజు మీటింగ్ ముగిసింది",
      ], languages: ["te"])
    // "గత శుక్రవారం" is a past day, but "శుక్రవారంలోగా" is a deadline.
    #expect(parse("రిపోర్ట్ శుక్రవారంలోగా").dueDayOffset == 3)
    #expect(parse("రిపోర్ట్ రేపటికల్లా").dueDayOffset == 1)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // "ప్రతి" also means a rate: a price per day reads as a repeat.
    let price = parse("ప్రతి రోజు 500 రూపాయలు")
    #expect(price.recurrence == daily)
    #expect(price.title == "500 రూపాయలు")
    // An hour from 1 to 6 with no part of the day is the afternoon.
    #expect(parse("మీటింగ్ 5 గంటలకు").startMinutes == 17 * 60)
    // An hour count written with a Latin unit is English's length, even after ప్రతి.
    let hours = parse("మందులు వేసుకోండి ప్రతి 2h")
    #expect(hours.estimatedMinutes == 120)
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("ఈ పని ముఖ్యం").priority == .p1)
    #expect(parse("ఈ పని అత్యవసరం").priority == .p1)
    // A word that stands apart from a day stays in the title.
    let again = parse("ఈరోజు మళ్ళీ రిపోర్ట్ పంపండి")
    #expect(again.plannedDayOffset == 0)
    #expect(again.title == "మళ్ళీ రిపోర్ట్ పంపండి")
    // A short month after a day number is a date, as the system writes it.
    #expect(parse("5 జన ఫోన్ చేయండి").plannedDayOffset == captureDayOffset("2027-01-05"))
  }

  // MARK: - Scripts and spellings

  @Test("The vowel sign ై reads as one sign or as the two signs it is made of")
  func vowelSignAI() {
    // ై (U+0C48) is ె (U+0C46) and ౖ (U+0C56).
    for ai in ["\u{0C48}", "\u{0C46}\u{0C56}"] {
      let scalars = ai.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      #expect(
        parse("సెలవు 5 జుల\(ai)").plannedDayOffset == captureDayOffset("2027-07-05"), "జులై: \(scalars)")
      #expect(parse("రిపోర్ట్ రాయండి ఇరవ\(ai) నిమిషాలు").estimatedMinutes == 20, "ఇరవై: \(scalars)")
      #expect(parse("రిపోర్ట్ రాయండి ముప్ప\(ai) నిమిషాలు").estimatedMinutes == 30, "ముప్పై: \(scalars)")
      #expect(parse("రిపోర్ట్ రాయండి నలభ\(ai) నిమిషాలు").estimatedMinutes == 40 , "నలభై: \(scalars)")
      #expect(parse("రిపోర్ట్ రాయండి నలభ\(ai) ఐదు నిమిషాలు").estimatedMinutes == 45, "నలభై ఐదు: \(scalars)")
      #expect(parse("రిపోర్ట్ రాయండి యాభ\(ai) నిమిషాలు").estimatedMinutes == 50, "యాభై: \(scalars)")
      #expect(parse("రిపోర్ట్ రాయండి అరవ\(ai) నిమిషాలు").estimatedMinutes == 60, "అరవై: \(scalars)")
    }
  }

  @Test("Spelling variants of the same word read alike")
  func spellingVariants() {
    // ఉదయం and ఉదయము, శుక్రవారం and శుక్రవారము, అక్టోబర్ and అక్టోబరు, జులై and జూలై, ఆగస్టు and
    // ఆగష్టు, ఐదు and అయిదు, ప్రతి and ప్రతీ, ఈరోజు and ఈ రోజు, ఇవాళ and ఇవ్వాళ, అర్ధ and అర్థ,
    // నిమిషాలు and నిముషాలు, గరిష్ట and గరిష్ఠ, తరువాత and తర్వాత, మధ్యస్థ and మధ్యమ.
    #expect(parse("మీటింగ్ ఉదయం 9 గంటలకు").startMinutes == parse("మీటింగ్ ఉదయము 9 గంటలకు").startMinutes)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి శుక్రవారం").plannedDayOffset
        == parse("అమ్మకు ఫోన్ చేయండి శుక్రవారము").plannedDayOffset)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి 5 అక్టోబర్").plannedDayOffset
        == parse("అమ్మకు ఫోన్ చేయండి 5 అక్టోబరు").plannedDayOffset)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి 5 జులై").plannedDayOffset == parse("అమ్మకు ఫోన్ చేయండి 5 జూలై").plannedDayOffset)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి 5 ఆగస్టు").plannedDayOffset
        == parse("అమ్మకు ఫోన్ చేయండి 5 ఆగష్టు").plannedDayOffset)
    #expect(parse("మీటింగ్ ఐదు గంటలకు").startMinutes == parse("మీటింగ్ అయిదు గంటలకు").startMinutes)
    #expect(parse("జిమ్ ప్రతి సోమవారం").recurrence == parse("జిమ్ ప్రతీ సోమవారం").recurrence)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి ఈరోజు").plannedDayOffset == parse("అమ్మకు ఫోన్ చేయండి ఈ రోజు").plannedDayOffset)
    #expect(parse("అమ్మకు ఫోన్ చేయండి ఈరోజు").title == parse("అమ్మకు ఫోన్ చేయండి ఈ రోజు").title)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి ఇవాళ").plannedDayOffset == parse("అమ్మకు ఫోన్ చేయండి ఇవ్వాళ").plannedDayOffset)
    #expect(
      parse("రిపోర్ట్ రాయండి అర్ధ గంట").estimatedMinutes == parse("రిపోర్ట్ రాయండి అర్థ గంట").estimatedMinutes)
    #expect(
      parse("రిపోర్ట్ రాయండి 30 నిమిషాలు").estimatedMinutes == parse("రిపోర్ట్ రాయండి 30 నిముషాలు").estimatedMinutes)
    #expect(
      parse("రిపోర్ట్ పంపండి గరిష్ట ప్రాధాన్యత").priority == parse("రిపోర్ట్ పంపండి గరిష్ఠ ప్రాధాన్యత").priority)
    #expect(
      parse("అమ్మకు ఫోన్ చేయండి 3 రోజుల తర్వాత").plannedDayOffset
        == parse("అమ్మకు ఫోన్ చేయండి 3 రోజుల తరువాత").plannedDayOffset)
    #expect(
      parse("రిపోర్ట్ పంపండి మధ్యస్థ ప్రాధాన్యత").priority == parse("రిపోర్ట్ పంపండి మధ్యమ ప్రాధాన్యత").priority)
  }

  @Test("A zero-width joiner or non-joiner after a virama, or before an ending glued to a digit, a Latin name, or a month, changes nothing")
  func joiners() {
    for joiner in ["\u{200C}", "\u{200D}"] {
      let scalar = joiner.unicodeScalars.map { String($0.value, radix: 16) }.joined()
      #expect(
        parse("అమ్మకు ఫోన్ చేయండి 5\(joiner)న").plannedDayOffset == captureDayOffset("2026-10-05"), "5న: \(scalar)")
      #expect(parse("మీటింగ్ సాయంత్రం 5\(joiner)కి").startMinutes == 17 * 60, "5కి: \(scalar)")
      #expect(parse("మీటింగ్ 3:30 PM\(joiner)కి").startMinutes == 15 * 60 + 30, "PMకి: \(scalar)")
      #expect(parse("మీటింగ్ 17:30\(joiner)కి").startMinutes == 17 * 60 + 30, "17:30కి: \(scalar)")
      #expect(
        parse("అమ్మకు ఫోన్ చేయండి అక్టోబర్ 15\(joiner)న").plannedDayOffset == captureDayOffset("2026-10-15"),
        "అక్టోబర్ 15న: \(scalar)")
      #expect(
        parse("అమ్మకు ఫోన్ చేయండి 15 అక్టోబర్\(joiner)కి").plannedDayOffset == captureDayOffset("2026-10-15"),
        "అక్టోబర్కి: \(scalar)")
      #expect(
        parse("అమ్మకు ఫోన్ చేయండి అక్టోబర్\(joiner) 15").plannedDayOffset == captureDayOffset("2026-10-15"),
        "అక్టోబర్ 15: \(scalar)")
      #expect(parse("జిమ్ ప్\(joiner)రతి సోమవారం").recurrence == monday, "ప్రతి: \(scalar)")
      #expect(parse("అమ్మకు ఫోన్ చేయండి శుక్\(joiner)రవారం").plannedDayOffset == 3, "శుక్రవారం: \(scalar)")
      #expect(parse("అమ్మకు ఫోన్ చేయండి వీకెండ్\(joiner)లో").plannedDayOffset == 4, "వీకెండ్లో: \(scalar)")
    }
    // A joiner that touches a finished word makes it part of a longer word.
    expectLinesUnread(
      [
        "రేపు\u{200C} మీటింగ్", "5 గంటలకు\u{200C} మీటింగ్", "ఈరోజు\u{200C}కి మీటింగ్", "ఆదివారం\u{200C} ట్రెక్",
        "ఈ\u{200C} రోజు మీటింగ్", "ప్రతి\u{200D} రోజు జిమ్",
      ], languages: ["te"])
    // The title keeps the joiner as typed.
    let typed = "వర్క్\u{200C}షాప్ ఏర్పాట్లు"
    #expect(Array(parse("\(typed) రేపు").title.unicodeScalars) == Array(typed.unicodeScalars))
  }

  @Test("The composed and the decomposed forms of a line read the same")
  func normalizationForms() {
    let lines = [
      "రేపు ఉదయం మీటింగ్ 6 గంటలకు", "రిపోర్ట్ పంపండి శుక్రవారం వరకు", "అమ్మకు ఫోన్ చేయండి 5 ఫిబ్రవరి",
      "మందులు వేసుకోండి ప్రతి 2 వారాలకు", "మీటింగ్ ఐదున్నరకు", "రిపోర్ట్ పంపండి అత్యవసరం",
      "అమ్మకు ఫోన్ చేయండి 5 జులై", "రిపోర్ట్ రాయండి ఇరవై నిమిషాలు", "రిపోర్ట్ రాయండి ముప్పై నిమిషాలు",
      "రిపోర్ట్ రాయండి నలభై ఐదు నిమిషాలు", "రిపోర్ట్ రాయండి యాభై నిమిషాలు", "రిపోర్ట్ రాయండి అరవై నిమిషాలు",
      "జిమ్ ప్రతి సోమవారం", "రిపోర్ట్ పంపండి గడువు: 5 మే", "సెలవు 3 నుండి 5 మార్చి", "రోజూ ఉదయం 6 గంటలకు యోగా",
      "సెలవు 3 నుండి 5 జులై", "రిపోర్ట్ పంపండి అధిక ప్రాధాన్యత", "అమ్మకు ఫోన్ చేయండి 3 రోజుల్లో",
      "మీటింగ్ సాయంత్రం 5కి", "రిపోర్ట్ రాయండి రెండున్నర గంటలు", "రిపోర్ట్ పంపండి 5 జులై వరకు",
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

  @Test("Telugu digits and Western digits read the same")
  func digitScripts() {
    let lines = [
      "మీటింగ్ సాయంత్రం 5:30 గంటలకు", "మీటింగ్ ఉదయం 9కి", "రిపోర్ట్ రాయండి 20 నిమిషాలు", "రిపోర్ట్ రాయండి 1.5 గంటలు",
      "రిపోర్ట్ రాయండి 1 గంట 30 నిమిషాలు", "మందులు వేసుకోండి ప్రతి 3 రోజులకు", "అద్దె ప్రతి నెల 5వ తేదీన",
      "సభ 5 మార్చి 2027", "అమ్మకు ఫోన్ చేయండి 3 రోజుల్లో", "సెలవు 3 నుండి 5 మార్చి", "సెలవు 3-5 మార్చి",
      "రిపోర్ట్ పంపండి 5 మార్చి వరకు", "అమ్మకు ఫోన్ చేయండి 2 నెలల్లో", "మందులు వేసుకోండి ప్రతి 2 వారాలకు",
      "అమ్మకు ఫోన్ చేయండి 15/10/2026", "మీటింగ్ 17:30కి", "మీటింగ్ ఉదయం 10 గంటల 30 నిమిషాలకు",
      "మీటింగ్ 14:00 నుండి 16:00 వరకు", "అమ్మకు ఫోన్ చేయండి అక్టోబర్ 15న", "మీటింగ్ 9-11 గంటలకు",
      "అమ్మకు ఫోన్ చేయండి 15వ తేదీన", "అమ్మకు ఫోన్ చేయండి 15.10.2026", "అమ్మకు ఫోన్ చేయండి 15 అక్టో",
      "రిపోర్ట్ రాయండి 2 గంటల పాటు", "మీటింగ్ 5 గంటల 30 నిమిషాలకు",
    ]
    for line in lines {
      let latin = parse(line)
      #expect(latin.phrases.count == 1, "\(line): phrases")
      let converted = teluguDigits(line)
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
    let typed = parse("౩ మందితో మీటింగ్ రేపు")
    #expect(typed.plannedDayOffset == 1)
    #expect(typed.title == "౩ మందితో మీటింగ్")
  }

  @Test("The title keeps the letters and signs as they were typed")
  func titleKeepsTypedText() {
    // A precomposed ై in the title stays one code point, and a decomposed one stays two.
    for typed in ["నైట్ షో", "న\u{0C46}\u{0C56}ట్ షో"] {
      let parsed = parse("\(typed) రేపు")
      #expect(parsed.plannedDayOffset == 1)
      #expect(parsed.priority == nil)
      #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    }
    let digits = parse("5 పుస్తకాలు కొనాలి రేపు")
    #expect(digits.title == "5 పుస్తకాలు కొనాలి")
  }

  @Test("The comma and the colon left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("అమ్మకు ఫోన్ చేయండి, రేపు, సాయంత్రం 5 గంటలకు", "అమ్మకు ఫోన్ చేయండి"), ("అమ్మకు ఫోన్ చేయండి రేపు.", "అమ్మకు ఫోన్ చేయండి."),
      ("రేపు, అమ్మకు ఫోన్ చేయండి", "అమ్మకు ఫోన్ చేయండి"), ("రేపు: అమ్మకు ఫోన్ చేయండి", "అమ్మకు ఫోన్ చేయండి"),
      ("అమ్మకు ఫోన్ చేయండి - రేపు", "అమ్మకు ఫోన్ చేయండి"),
      ("రిపోర్ట్ పంపండి, శుక్రవారం వరకు, అధిక ప్రాధాన్యత", "రిపోర్ట్ పంపండి"),
      ("పాలు, బ్రెడ్, గుడ్లు రేపు కొనాలి", "పాలు, బ్రెడ్, గుడ్లు కొనాలి"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The full stop is punctuation: it ends a word.
    #expect(parse("అమ్మకు ఫోన్ చేయండి రేపు.").plannedDayOffset == 1)
    #expect(parse("రిపోర్ట్ పంపండి శుక్రవారం వరకు.").dueDayOffset == 3)
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    let day = parse("పని రేపు")
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "పని")
    let time = parse("పని సాయంత్రం 5 గంటలకు")
    #expect(time.startMinutes == 17 * 60)
    #expect(time.title == "పని")
    let repeating = parse("పని ప్రతి సోమవారం")
    #expect(repeating.recurrence == monday)
    #expect(repeating.title == "పని")
    let length = parse("పని 20 నిమిషాలు")
    #expect(length.estimatedMinutes == 20)
    #expect(length.title == "పని")
    #expect(parse("పని #జాబితా").tags == ["జాబితా"])
  }

  @Test("The examples of the user guide table are read as the details they demonstrate")
  func guideExamples() {
    // Each example is typed with Latin digits, as the guide writes it, and with Telugu digits.
    func read(_ examples: [String]) -> [(example: String, parsed: LorvexCaptureParse)] {
      examples.flatMap { example in
        [example, teluguDigits(example)].map { (example: $0, parsed: parse("పని \($0)")) }
      }
    }
    let days = [
      "ఈరోజు", "ఈ రాత్రి", "రేపు", "రేపు ఉదయం", "ఎల్లుండి", "సోమవారం", "ఈ శుక్రవారం", "తదుపరి సోమవారం",
      "వచ్చే వారం", "ఈ వారాంతం", "3 రోజుల్లో", "1 వారం తర్వాత",
    ]
    for (example, parsed) in read(days) {
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let dates = [
      "5 మే", "5 మే 2027", "తేదీ 5 మే", "15 అక్టో", "15వ తేదీన", "15/10/2026", "15.10.", "సోమవారం 5 అక్టోబర్",
      "సోమవారం, 5 అక్టోబర్",
    ]
    for (example, parsed) in read(dates) {
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let ranges = [
      "3 నుండి 5 మార్చి", "3 మార్చి నుండి 5 మార్చి వరకు", "30 జనవరి నుండి 2 ఫిబ్రవరి", "3-5 మార్చి",
      "సోమవారం నుండి బుధవారం వరకు",
    ]
    for (example, parsed) in read(ranges) {
      #expect(parsed.plannedDayOffset != nil && parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let due = [
      "శుక్రవారం వరకు", "రేపు సాయంత్రం వరకు", "5 మే లోగా", "శుక్రవారం లోపు", "శుక్రవారానికల్లా", "గడువు: 5 మే",
      "శుక్రవారం గడువు", "డెడ్\u{200C}లైన్ శుక్రవారం",
    ]
    for (example, parsed) in read(due) {
      #expect(parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let times = [
      "5 గంటలకు", "5:30 గంటలకు", "ఐదున్నరకు", "ఒంటి గంటకు", "సాయంత్రం 5 గంటలకు", "రాత్రి 10 గంటలకు",
      "ఉదయం 9:30", "సాయంత్రం 5కి", "17:30కి", "అర్ధరాత్రి", "9 గంటల నుండి 11 గంటల వరకు", "ఉదయం 9 నుండి 11 వరకు",
      "14:00 నుండి 16:00 వరకు",
    ]
    for (example, parsed) in read(times) {
      #expect(parsed.startMinutes != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let repeats = [
      "ప్రతిరోజు", "రోజూ", "ప్రతి ఉదయం", "ప్రతి సోమవారం", "ప్రతి సోమవారం మరియు గురువారం", "ప్రతి వారం",
      "ప్రతి 2 రోజులకు", "ప్రతి నెల", "ప్రతి నెల 5వ తేదీన", "ప్రతి సంవత్సరం", "ప్రతి వారాంతం", "పనిదినాల్లో", "పనిరోజుల్లో",
      "ప్రతి సోమవారం నుండి శుక్రవారం", "2 రోజులకోసారి", "వారానికి ఒకసారి",
    ]
    for (example, parsed) in read(repeats) {
      #expect(parsed.recurrence != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let lengths = [
      "30 నిమిషాలు", "2 గంటలు", "1.5 గంటలు", "1 గంట 30 నిమిషాలు", "అరగంట", "పావు గంట", "గంటన్నర",
      "రెండున్నర గంటలు", "రెండు గంటలు", "30 నిమిషాల పాటు",
    ]
    for (example, parsed) in read(lengths) {
      #expect(parsed.estimatedMinutes != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    let priorities = [
      "అధిక ప్రాధాన్యత", "సాధారణ ప్రాధాన్యత", "తక్కువ ప్రాధాన్యత", "ప్రాధాన్యత: అధికం", "అత్యవసరం",
    ]
    for (example, parsed) in read(priorities) {
      #expect(parsed.priority != nil, "\(example)")
      #expect(parsed.title == "పని", "\(example): title")
    }
    #expect(parse("అత్యవసరం: పని").priority == .p1)
    let urgent = parse("అత్యవసరం: రిపోర్ట్ పంపండి")
    #expect(urgent.priority == .p1)
    #expect(urgent.title == "రిపోర్ట్ పంపండి")
    // The sentences of the guide.
    #expect(parse("ప్రతి రోజు 500 రూపాయలు").recurrence == daily)
    #expect(parse("Sprint 12 - 20 మార్చి").plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(parse("పని 12-20 మార్చి").dueDayOffset == captureDayOffset("2027-03-20"))
    #expect(parse("పని ఉదయం 10 గంటల 30 నిమిషాలకు").startMinutes == 10 * 60 + 30)
    expectLinesUnread(
      [
        "పని 5/10", "పని 31 ఏప్రిల్", "పని 5 వైశాఖం", "పని 5 నుండి 3 మార్చి", "పని 3 నుండి 5", "పని 2 నుండి 3 గంటలు",
        "పని ఈ వారం", "శుక్ర గ్రహం చూడాలి", "అత్యవసర విభాగానికి వెళ్ళండి", "రిపోర్ట్ ముఖ్యం కాదు",
        "పని ఈరోజు వరకు", "పని శుక్రవారం నాటి", "పని 5 గంటల తర్వాత", "పని ఈరోజుల్లో", "పని రేపు-ఎల్లుండి",
        "మూడు పుస్తకాలు కొనాలి", "పని రోజుకు 2 గంటలు",
      ], languages: ["te"])
  }

  @Test("The phrases the app writes for a deadline, a priority, a repeat, and an hour can be typed back")
  func phrasesTheAppWrites() {
    // "%@ గడువు" with a day word, a weekday, or a date as the system writes it, and the label "గడువు: %@".
    let deadlines: [(text: String, offset: Int)] = [
      ("ఈరోజు గడువు", 0), ("రేపు గడువు", 1), ("శుక్రవారం గడువు", 3), ("15 అక్టో గడువు", captureDayOffset("2026-10-15")),
      ("15 అక్టో 2027 గడువు", captureDayOffset("2027-10-15")), ("15 అక్టోబర్ గడువు", captureDayOffset("2026-10-15")),
      ("గడువు: ఈరోజు", 0), ("గడువు: రేపు", 1), ("గడువు: శుక్రవారం", 3),
      ("గడువు: 15 అక్టో", captureDayOffset("2026-10-15")), ("గడువు: 15 అక్టోబర్", captureDayOffset("2026-10-15")),
      ("గడువు: 15 అక్టో 2027", captureDayOffset("2027-10-15")),
      ("గడువు: గురువారం, 15 అక్టోబర్", captureDayOffset("2026-10-15")),
      ("గడువు తేదీ: 15 అక్టోబర్", captureDayOffset("2026-10-15")),
    ]
    for line in deadlines {
      let text = "రిపోర్ట్ పంపండి \(line.text)"
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "రిపోర్ట్ పంపండి", "\(text): title")
    }
    // "గడువు మీరింది" and "గడువు ముగిసింది" say that a deadline has passed.
    expectLinesUnread(["రేపు గడువు మీరింది", "శుక్రవారం గడువు ముగిసింది"], languages: ["te"])
    // The priority phrases of the task sentence and the field's values.
    let priorities: [(text: String, priority: LorvexTask.Priority)] = [
      ("అధిక ప్రాధాన్యత", .p1), ("సాధారణ ప్రాధాన్యత", .p2), ("తక్కువ ప్రాధాన్యత", .p3),
      ("ప్రాధాన్యత: అధికం", .p1), ("ప్రాధాన్యత: సాధారణం", .p2), ("ప్రాధాన్యత: తక్కువ", .p3),
    ]
    for line in priorities {
      let parsed = parse("రిపోర్ట్ పంపండి \(line.text)")
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == "రిపోర్ట్ పంపండి", "\(line.text): title")
    }
    // The repeat summaries and the frequency names.
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let repeats: [(text: String, rule: TaskRecurrenceRule)] = [
      ("ప్రతిరోజు", daily), ("ప్రతి వారం", weekly), ("ప్రతి నెల", monthly), ("ప్రతి సంవత్సరం", yearly),
      ("ప్రతి 1 రోజు", daily), ("ప్రతి 2 రోజులు", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ప్రతి 3 వారాలు", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("ప్రతి 4 నెలలు", TaskRecurrenceRule(freq: .monthly, interval: 4)),
      ("ప్రతి 5 సంవత్సరాలు", TaskRecurrenceRule(freq: .yearly, interval: 5)), ("రోజువారీ", daily),
      ("వారంవారీ", weekly), ("నెలవారీ", monthly), ("సంవత్సరంవారీ", yearly),
    ]
    for line in repeats {
      let parsed = parse("మందులు వేసుకోండి \(line.text)")
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "మందులు వేసుకోండి", "\(line.text): title")
    }
    // The hour as the system writes a duration and a clock time, and the days the app writes.
    #expect(parse("చదవడం 1 గంట").estimatedMinutes == 60)
    #expect(parse("చదవడం 12 గంటలు").estimatedMinutes == 720)
    #expect(parse("చదవడం 1 గం., 30 నిమి.").estimatedMinutes == 90)
    #expect(parse("చదవడం 1 గంట, 30 నిమిషాలు").estimatedMinutes == 90)
    #expect(parse("మీటింగ్ 5:05 PM").startMinutes == 17 * 60 + 5)
    #expect(parse("ఫోన్ చేయండి ఈరోజు").plannedDayOffset == 0)
    #expect(parse("ఫోన్ చేయండి రేపు").plannedDayOffset == 1)
    // Yesterday, the Someday list, and the other words around them name no day.
    expectLinesUnread(
      ["ఫోన్ చేయండి నిన్న", "పుస్తకం చదవాలి ఏదో ఒక రోజు", "ఏదో ఒక రోజు విభాగంలో పుస్తకం చదవాలి", "ఇన్\u{200C}బాక్స్ ఖాళీ చేయండి"],
      languages: ["te"])
    // A relative time and a duration of the system's wording are no length.
    expectLinesUnread(["చదవడం 5 నిమి. క్రితం", "చదవడం 2 గంటల్లో"], languages: ["te"])
  }

  // MARK: - Names the system writes

  /// The short weekday names the system writes in Telugu that are not read,
  /// with the reason: each is an ordinary word, a name, a planet, a letter, or
  /// a syllable.
  private static let unreadWeekdayAbbreviations: [String: String] = [
    "ఆది": "a word for the first, and a name", "సోమ": "a name, and the moon", "మంగళ": "a name, and the planet Mars",
    "బుధ": "the planet Mercury", "గురు": "a teacher, and the planet Jupiter", "శుక్ర": "the planet Venus",
    "శని": "the planet Saturn", "ఆ": "the word for that", "సో": "a syllable", "మ": "a single letter",
    "బు": "a syllable", "గు": "a syllable", "శు": "a syllable", "శ": "a single letter",
  ]

  @Test("Every month and weekday name the system writes in Telugu is read, except the short weekday forms")
  func systemNames() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "te_IN")
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
        for day in ["5", "౫"] {
          let parsed = parse("అమ్మకు ఫోన్ చేయండి \(day) \(name)")
          #expect(parsed.plannedDayOffset == captureDayOffset(date), "\(day) \(name) is the 5th of month \(month)")
          #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(day) \(name): title")
        }
      }
    }
    let weekdayNames: [[String]] = [
      formatter.weekdaySymbols, formatter.standaloneWeekdaySymbols, formatter.shortWeekdaySymbols,
      formatter.shortStandaloneWeekdaySymbols, formatter.veryShortWeekdaySymbols,
    ]
    for names in weekdayNames {
      #expect(names.count == 7)
      for (index, name) in names.enumerated() {
        let parsed = parse("అమ్మకు ఫోన్ చేయండి \(name)")
        if Self.unreadWeekdayAbbreviations[name] != nil {
          #expect(parsed.plannedDayOffset == nil, "\(name) is left in the title")
          #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి \(name)", "\(name): title")
        } else {
          // Index 0 is Sunday; 2026-09-22 is a Tuesday, so a weekday alone is the next such day.
          let delta = (index + 1 - 3 + 7) % 7
          #expect(parsed.plannedDayOffset == (delta == 0 ? 7 : delta), "\(name)")
          #expect(parsed.title == "అమ్మకు ఫోన్ చేయండి", "\(name): title")
        }
      }
    }
    // The system's AM and PM markers after an hour, and its dates with a time.
    let meridiems: [(symbol: String, minutes: Int)] = [
      (formatter.amSymbol, 3 * 60 + 30), (formatter.pmSymbol, 15 * 60 + 30),
    ]
    for meridiem in meridiems {
      for text in ["మీటింగ్ 3:30 \(meridiem.symbol)", "మీటింగ్ 3:30 \(meridiem.symbol)కి"] {
        let parsed = parse(text)
        #expect(parsed.startMinutes == meridiem.minutes, "\(text)")
        #expect(parsed.title == "మీటింగ్", "\(text): title")
      }
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = formatter.timeZone
    let components = DateComponents(year: 2026, month: 10, day: 15, hour: 15, minute: 30)
    if let date = calendar.date(from: components) {
      formatter.timeStyle = .short
      for style in [DateFormatter.Style.medium, .long, .full] {
        formatter.dateStyle = style
        let text = "అమ్మకు ఫోన్ చేయండి " + formatter.string(from: date)
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == captureDayOffset("2026-10-15"), "\(text): planned day")
        #expect(parsed.startMinutes == 15 * 60 + 30, "\(text): start")
      }
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Telugu, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "te"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "te"]).estimatedMinutes == 20)
    #expect(parse("రిపోర్ట్ 2h").estimatedMinutes == 120)
    #expect(parse("రిపోర్ట్ 30min").estimatedMinutes == 30)
    #expect(parse("రిపోర్ట్ 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "te"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "te"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "te"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "te"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times,
    // also with Telugu digits.
    #expect(parse("మీటింగ్ 5pm").startMinutes == 17 * 60)
    #expect(parse("మీటింగ్ 5 PM").startMinutes == 17 * 60)
    #expect(parse("మీటింగ్ 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("మీటింగ్ ౧౭:౩౦").startMinutes == 17 * 60 + 30)
    #expect(parse("మీటింగ్ ౩pm").startMinutes == 15 * 60)
    #expect(parse("మీటింగ్ 30 min").estimatedMinutes == 30)
    #expect(parse("మీటింగ్ ౩౦ min").estimatedMinutes == 30)
    // A letter h after a number is no clock time for Telugu: 2h and 15h read as English reads them alone.
    for text in [
      "Run 2h", "Run 15h", "Meet at 15h", "Call at 9h30", "Read 1.5h", "రిపోర్ట్ 2h", "రిపోర్ట్ 15h",
      "రిపోర్ట్ ౨h", "రిపోర్ట్ ౧౫h", "మీటింగ్ 9h30", "మందులు వేసుకోండి ప్రతి 2h",
    ] {
      #expect(parse(text, languages: ["en", "te"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // English lines read the same with Telugu beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "te"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom రేపు at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting శుక్రవారం at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("మీటింగ్ tomorrow సాయంత్రం 5 గంటలకు")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "మీటింగ్")
    let teluguTitle = parse("సభ next friday")
    #expect(teluguTitle.plannedDayOffset == 10)
    #expect(teluguTitle.title == "సభ")
    #expect(parse("సభ 2h").estimatedMinutes == 120)
  }

  @Test("Lines in other languages read the same with Telugu beside them")
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
      ("মাকে ফোন করুন কাল বিকেল 5টায়", "bn"), ("জিম প্রতি সোমবার", "bn"), ("রিপোর্ট পাঠান শুক্রবার পর্যন্ত", "bn"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "te"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["te", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Telugu with another language.
    for languages in [["fr", "te"], ["te", "fr"]] {
      let mixed = parse("Appeler maman రేపు à 15h", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("జిమ్ ప్రతి సోమవారం", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
    }
    #expect(parse("Meeting 下午3点 రేపు", languages: ["zh", "te"]).plannedDayOffset == 1)
    #expect(parse("Meeting מחר రేపు", languages: ["he", "te"]).plannedDayOffset == 1)
  }

  @Test("Telugu lines read the same beside every other language")
  func besideEveryLanguage() {
    let lines = [
      "అమ్మకు ఫోన్ చేయండి రేపు సాయంత్రం 5 గంటలకు", "జిమ్ ప్రతి సోమవారం ఉదయం 9 గంటలకు",
      "రిపోర్ట్ పంపండి శుక్రవారం వరకు అత్యవసరం", "సెలవు 3 నుండి 5 మార్చి", "రిపోర్ట్ రాయండి 20 నిమిషాలు",
      "మందులు వేసుకోండి ప్రతి 2 వారాలకు", "అద్దె ప్రతి నెల 5వ తేదీన", "మీటింగ్ ఐదున్నరకు అధిక ప్రాధాన్యత",
      "అమ్మకు ఫోన్ చేయండి 15 అక్టోబర్", "అమ్మకు ఫోన్ చేయండి 15/10/2026", "అమ్మకు ఫోన్ చేయండి 15.10.2026",
      "రిపోర్ట్ పంపండి గడువు: శుక్రవారం", "తదుపరి సోమవారం రాత్రి 7:30 గంటలకు డిన్నర్", "రోజూ ఉదయం 6 గంటలకు యోగా",
      "మీటింగ్ 2 గంటల నుండి 4 గంటల వరకు", "అమ్మకు ఫోన్ చేయండి 3 రోజుల్లో", "రిపోర్ట్ రాయండి గంటన్నర",
      "శని ఆదివారాల్లో ట్రెక్", "నేటి వార్తలు", "సోమశేఖర్ కి ఫోన్", "రోజువారీ సమీక్ష #జాబితా",
      "సోమవారం నుండి బుధవారం వరకు శిబిరం", "మీటింగ్ 3:30 PMకి", "అమ్మకు ఫోన్ చేయండి 5\u{200C}న",
    ]
    let others = [
      "ar", "bn", "de", "el", "es", "fa", "fr", "he", "hi", "id", "it", "ja", "ko", "mr", "ms", "nl", "pl", "pt",
      "ro", "ru", "ta", "th", "tr", "uk", "ur", "vi", "zh",
    ]
    for text in lines {
      let alone = parse(text)
      for language in others {
        #expect(parse(text, languages: ["te", language]) == alone, "\(text) beside \(language)")
        #expect(parse(text, languages: [language, "te"]) == alone, "\(text) beside \(language), reversed")
      }
    }
  }

  @Test("Telugu words are read only for a user who reads Telugu")
  func languageGate() {
    let text = "అమ్మకు ఫోన్ చేయండి రేపు"
    let line = parse(text, languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == text)
    for languages in [["te"], ["te-IN"], ["te_IN"], ["en-US", "te-IN"], ["TE"], ["te-Telu-IN"]] {
      #expect(parse(text, languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages are not Telugu: the neighbours in India get no Telugu words.
    for language in ["bn", "hi", "mr", "ta", "kn", "ml", "ur", "or", "pa", "gu"] {
      #expect(parse(text, languages: [language]).plannedDayOffset == nil, "\(language)")
    }
    // Other languages' words are not read for a Telugu reader, and Telugu is not read for theirs.
    expectLinesUnread(
      ["Zadzwonić jutro", "Позвонить завтра", "اتصل بأمي غداً", "Appeler maman demain", "Zahnarzt übermorgen"],
      languages: ["te"])
    for languages in [
      ["ar"], ["pl"], ["ru"], ["fr"], ["es"], ["it"], ["pt"], ["he"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"],
      ["tr"], ["el"], ["th"], ["fa"], ["ur"], ["uk"], ["ja"], ["ko"], ["zh"], ["hi"], ["mr"], ["bn"],
    ] {
      let parsed = parse(text, languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == text, "\(languages): title")
    }
    // A clock time, a repeat, a priority, and a length with a Telugu word need Telugu among the languages.
    #expect(parse("మీటింగ్ సాయంత్రం 5 గంటలకు", languages: ["en"]).startMinutes == nil)
    #expect(parse("మందులు వేసుకోండి ప్రతి సోమవారం", languages: ["en"]).recurrence == nil)
    #expect(parse("రిపోర్ట్ పంపండి అధిక ప్రాధాన్యత", languages: ["en"]).priority == nil)
    #expect(parse("రిపోర్ట్ రాయండి 30 నిమిషాలు", languages: ["en"]).estimatedMinutes == nil)
    // Telugu and Arabic readers get both.
    #expect(parse(text, languages: ["ar", "te"]).plannedDayOffset == 1)
    #expect(parse("اتصل بأمي غداً", languages: ["ar", "te"]).plannedDayOffset == 1)
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["te"])
    let unit: [String] = [
      "గంటలకు ", "5 గంటలకు ", "5:30 గంటలకు ", "సాయంత్రం 5 గంటలకు ", "ఐదున్నరకు ", "ఒంటి గంటకు ", "సాయంత్రం 5కి ",
      "5కి ", "17:30కి ", "3:30 PMకి ", "రేపు ", "రేపు ఉదయం ", "ఈరోజు రాత్రి ", "ఎల్లుండి ", "శుక్రవారానికి ",
      "శుక్రవారం సాయంత్రం ", "ఈ శుక్రవారం ", "తదుపరి శుక్రవారం ", "వచ్చే వారం ", "15 అక్టోబర్ ", "15 అక్టో. ",
      "15.10.2026 ", "15/10 ", "15/10న ", "3 నుండి 5 మార్చి ", "3 మార్చి నుండి 5 మార్చి వరకు ", "3-5 మార్చి ",
      "వరకు ", "శుక్రవారం వరకు ", "గడువు శుక్రవారం ", "గడువు: ", "డెడ్\u{200C}లైన్ ", "ప్రతిరోజు ", "రోజూ ఉదయం ",
      "ప్రతి సోమవారం ", "ప్రతి సోమవారం మరియు గురువారం ", "ప్రతి 2 వారాలకు ", "ప్రతి నెల 5న ",
      "సోమవారం నుండి శుక్రవారం ", "వారాంతంలో ", "30 నిమిషాలు ", "1.5 గంటలు ", "1 గంట 30 నిమిషాలు ", "అరగంట ",
      "రెండున్నర గంటలు ", "అత్యవసరం ", "అధిక ప్రాధాన్యత ", "ప్రాధాన్యత: ", "రాత్రి ", "అర్ధరాత్రి ", "నుండి ",
      "ప్రతి ", "గంట ", "నిమిషాలు ", "ఈరోజు ", "మరియు ", "ా", "్", "ం", "ః", "ఁ", "ై", "\u{0C46}\u{0C56}", "్\u{200C}",
      "్\u{200D}", "\u{200C}", "\u{200D}", ", ", ".", "-", "–", ":", "·",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "రవి " + String(repeating: token, count: count) + " ఫోన్"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(30), "\(token) took \(elapsed)")
    }
    #expect(slowest < .seconds(30), "the slowest long line took \(slowest)")
    // A line past the read limit that repeats a recognized phrase is a title and nothing more, at once.
    let past = String(repeating: "రేపు సాయంత్రం 5 గంటలకు ", count: 300).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count >= 5_000)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    // The first phrase of a long line still reads.
    let first = parse("రేపు " + String(repeating: "5 గంటలకు రేపు ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 17 * 60)
  }
}
