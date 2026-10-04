import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["he"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["he"])
}

private let monday = TaskRecurrenceRule(freq: .weekly, byDay: ["MO"])
private let daily = TaskRecurrenceRule(freq: .daily)
private let weeklyRule = TaskRecurrenceRule(freq: .weekly)
private let sundayToThursday = TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"])

/// Hebrew capture lines, read for a user whose languages include Hebrew.
@Suite("Capture parser Hebrew")
struct CaptureParserHebrewTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("להתקשר לאמא מחר")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "להתקשר לאמא")
    #expect(line.phrases.map(\.text) == ["מחר"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("היום", 0), ("מחר", 1), ("למחר", 1), ("מחרתיים", 2), ("בעוד יום", 1), ("בעוד יום אחד", 1), ("בעוד יומיים", 2),
      ("בעוד 3 ימים", 3), ("בעוד שלושה ימים", 3), ("בעוד 10 ימים", 10), ("בעוד עשרה ימים", 10), ("בעוד שבוע", 7),
      ("בעוד שבועיים", 14), ("בעוד 3 שבועות", 21), ("בעוד שלושה שבועות", 21), ("בעוד חודש", 30),
      ("בעוד חודשיים", 61), ("בעוד 2 חודשים", 61), ("בשבוע הבא", 7), ("שבוע הבא", 7), ("לשבוע הבא", 7),
      ("השבוע הבא", 7),
    ]
    for day in days {
      let text = "להתקשר לאמא \(day.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day.offset, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "להתקשר לאמא", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [day.text], "\(text): phrase")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("מחר להתקשר לאמא")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "להתקשר לאמא")
    // No days ahead is no day, and the week alone names none.
    expectLinesUnread(["פגישה בעוד 0 ימים", "פגישה השבוע", "פגישה בשבוע הזה"], languages: ["he"])
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("היום בבוקר", 0), ("היום בצהריים", 0), ("היום אחר הצהריים", 0), ("היום בערב", 0), ("הבוקר", 0), ("הערב", 0),
      ("הלילה", 0), ("מחר בבוקר", 1), ("מחר בצהריים", 1), ("מחר אחר הצהריים", 1), ("מחר בערב", 1), ("מחר בלילה", 1),
      ("מחר לפנות בוקר", 1), ("מחר בצהרים", 1), ("מחרתיים בערב", 2),
    ]
    for phrase in phrases {
      let parsed = parse("להתקשר לאמא \(phrase.text)")
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "להתקשר לאמא", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    let weekdays: [(text: String, offset: Int)] = [
      ("ביום שני בבוקר", 6), ("ביום שני בערב", 6), ("ביום שישי בצהריים", 3), ("בשבת בערב", 4), ("בשבת בבוקר", 4),
      ("בשני בערב", 6), ("בשלישי בערב", 7), ("יום שני בבוקר", 6),
    ]
    for weekday in weekdays {
      let parsed = parse("פגישה \(weekday.text)")
      #expect(parsed.plannedDayOffset == weekday.offset, "\(weekday.text)")
      #expect(parsed.title == "פגישה", "\(weekday.text): title")
      #expect(parsed.phrases.map(\.text) == [weekday.text], "\(weekday.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("מחר בבוקר פגישה בשעה 6")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "פגישה")
    let evening = parse("פגישה היום בערב בשעה 7")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "פגישה")
    let night = parse("מחר בלילה לצאת עם חברים בשעה 10")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 22 * 60)
    #expect(night.title == "לצאת עם חברים")
    let afternoon = parse("פגישה היום אחר הצהריים בשעה 4")
    #expect(afternoon.plannedDayOffset == 0)
    #expect(afternoon.startMinutes == 16 * 60)
    #expect(afternoon.title == "פגישה")
    // The part of the day as a noun, or on its own, names no day.
    expectLinesUnread(
      [
        "ארוחת ערב", "ארוחת הערב", "ארוחת בוקר עם הילדים", "חדשות הערב", "לשמוע חדשות הערב", "משמרת הלילה",
        "שיחת הבוקר", "מהדורת הערב", "בוקר טוב לצוות", "ערב טוב לכולם", "לילה טוב לילדים", "לצאת בערב",
        "ללכת לים בבוקר", "לקרוא בלילה",
      ], languages: ["he"])
  }

  @Test("A prefix letter other than ל on a day word makes it another word")
  func dayPrefixes() {
    expectLinesUnread(
      [
        "להיפגש ומחר", "ומחר להיפגש", "שמחר להיפגש", "להיפגש כמחר", "להיפגש במחר", "להיפגש בהיום", "להתקשר לאמא והיום",
        "להתקשר לאמא שהיום", "להתקשר לאמא כהיום", "להיפגש מהיום", "לתקן את המחרוזת", "לעדכן את היומן",
        "לספור את הימים", "לא לשכוח את היום",
      ], languages: ["he"])
    // ל before a day says what the task is for, and the day is read with it.
    let tomorrow = parse("להתקשר לאמא למחר")
    #expect(tomorrow.plannedDayOffset == 1)
    #expect(tomorrow.title == "להתקשר לאמא")
    #expect(parse("פגישה ליום שני").plannedDayOffset == 6)
  }

  @Test("Weekdays: with יום, with an attached ב, as a letter, and with a week around them")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "הזה" is today.
    let names: [(name: String, offset: Int)] = [
      ("ראשון", 5), ("שני", 6), ("שלישי", 7), ("רביעי", 1), ("חמישי", 2), ("שישי", 3), ("שבת", 4),
    ]
    for weekday in names {
      for text in ["פגישה ביום \(weekday.name)", "פגישה יום \(weekday.name)", "פגישה ליום \(weekday.name)"] {
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "פגישה", "\(text): title")
        #expect(parsed.phrases.count == 1, "\(text): phrases")
      }
    }
    // A name with an attached ב and no יום is a day too.
    for weekday in names {
      let text = "פגישה ב\(weekday.name)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
      #expect(parsed.title == "פגישה", "\(text): title")
    }
    let letters: [(name: String, offset: Int)] = [
      ("א׳", 5), ("ב׳", 6), ("ג׳", 7), ("ד׳", 1), ("ה׳", 2), ("ו׳", 3), ("ש׳", 4), ("א'", 5), ("ג’", 7),
    ]
    for weekday in letters {
      let text = "פגישה ביום \(weekday.name)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
      #expect(parsed.title == "פגישה", "\(text): title")
    }
    let modified: [(text: String, offset: Int)] = [
      ("ביום שני הבא", 6), ("ביום שני הקרוב", 6), ("ביום שני הזה", 6), ("ביום שני השבוע", 6),
      ("ביום שלישי הבא", 7), ("ביום שלישי הזה", 0), ("ביום שישי הקרוב", 3), ("השבוע ביום חמישי", 2),
      ("בשבוע הזה ביום חמישי", 2), ("בשבוע הבא ביום ראשון", 12), ("בשבוע הבא ביום שבת", 11),
      ("ביום ראשון בשבוע הבא", 12), ("ביום ראשון של השבוע הבא", 12), ("בשבוע הבא ביום רביעי", 8),
      ("בשבת הבאה", 4), ("בשני בבוקר", 6),
    ]
    for line in modified {
      let text = "פגישה \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "פגישה", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    let opening = parse("ביום שני פגישה")
    #expect(opening.plannedDayOffset == 6)
    #expect(opening.title == "פגישה")
    let time = parse("פגישה בשני בשעה 5")
    #expect(time.plannedDayOffset == 6)
    #expect(time.startMinutes == 17 * 60)
    #expect(time.title == "פגישה")
  }

  @Test("A name that is also an ordinal, a count, or a place is a weekday only where the line says a day")
  func ordinalsAndPlaces() {
    expectLinesUnread(
      [
        // Ordinals.
        "לקרוא את הספר השני", "לקרוא פרק שני בספר", "לשלם את התשלום השלישי", "לקנות מתנה לילד הראשון",
        "לסיים את הפרק הרביעי", "להכין את המצגת בפעם הראשונה", "לנסות שוב בפעם השנייה", "לבדוק את הסעיף הרביעי בחוזה",
        "לקנות מנה חמישי", "לאכול שלישי בתור", "להתקשר לשני",
        // "בשני" is "in two" before a noun, "ב" and an ordinal before a place or a total.
        "פגישה בשני מקומות", "פגישה בשני ימים", "לקנות בשני מקומות", "לשלם בשני תשלומים", "לגור בראשון לציון",
        "להיפגש בראשון לציון עם דנה", "לנסוע לראשון לציון", "לטפל בשישי מתוך עשרה",
        // A weekday before a month or "the month" is a day of the month.
        "פגישה בראשון לחודש", "פגישה בראשון במאי", "פגישה בשלישי לחודש", "לשלם בראשון לחודש", "להגיש בראשון במאי",
        "לצאת בשני במרץ",
        // A letter that is no weekday, and "יום" before something else.
        "לכתוב את האות ד׳", "לבדוק כיתה ג׳", "פגישה ביום ג", "פגישה ביום ב", "להיפגש עם יום",
      ], languages: ["he"])
    let sunday = parse("להיפגש בראשון")
    #expect(sunday.plannedDayOffset == 5)
    #expect(sunday.title == "להיפגש")
    let friday = parse("להיפגש בשישי בערב")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "להיפגש")
    let leave = parse("לקחת יום חופש ביום שני")
    #expect(leave.plannedDayOffset == 6)
    #expect(leave.title == "לקחת יום חופש")
  }

  @Test("Weeks start on Monday: the weeks around a weekday and the coming one")
  func weeksStartOnMonday() {
    // Tuesday 2026-09-22: the next week runs from Monday 09-28 to Sunday 10-04.
    let tuesday: [(text: String, offset: Int)] = [
      ("בשבוע הבא ביום שני", 6), ("בשבוע הבא ביום שלישי", 7), ("בשבוע הבא ביום רביעי", 8),
      ("בשבוע הבא ביום חמישי", 9), ("בשבוע הבא ביום שישי", 10), ("בשבוע הבא ביום שבת", 11),
      ("בשבוע הבא ביום ראשון", 12), ("ביום ראשון הבא", 5), ("ביום שבת הבא", 4), ("השבוע ביום חמישי", 2),
    ]
    for line in tuesday {
      let text = "פגישה \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "פגישה", "\(text): title")
    }
    // Thursday 09-24: the next week begins in four days.
    let thursday: [(text: String, offset: Int)] = [
      ("ביום שני הבא", 4), ("ביום רביעי הבא", 6), ("ביום חמישי הבא", 7), ("ביום חמישי הקרוב", 7),
      ("ביום חמישי הזה", 0), ("ביום חמישי", 7), ("ביום שישי הבא", 1), ("ביום שבת הבא", 2),
      ("בשבוע הבא ביום שני", 4), ("בשבוע הבא ביום ראשון", 10),
    ]
    for line in thursday {
      let text = "פגישה \(line.text)"
      #expect(parse(text, weekday: 5, today: "2026-09-24").plannedDayOffset == line.offset, "Thursday: \(text)")
    }
    // Saturday 09-26: the next week begins in two days.
    let saturday: [(text: String, offset: Int)] = [
      ("ביום שני הבא", 2), ("ביום שישי הבא", 6), ("ביום שבת הבא", 7), ("ביום שבת", 7), ("בשבת", 7),
      ("ביום שבת הזה", 0), ("ביום שבת הקרוב", 7), ("ביום ראשון", 1), ("בשבוע הבא ביום שני", 2),
    ]
    for line in saturday {
      let text = "פגישה \(line.text)"
      #expect(parse(text, weekday: 7, today: "2026-09-26").plannedDayOffset == line.offset, "Saturday: \(text)")
    }
    // Sunday 09-27 is the week's last day: the next week begins tomorrow.
    let sunday: [(text: String, offset: Int)] = [
      ("ביום שני הבא", 1), ("ביום שני", 1), ("ביום שבת הבא", 6), ("ביום ראשון הבא", 7), ("ביום ראשון", 7),
      ("ביום ראשון הזה", 0), ("בשבוע הבא ביום שני", 1), ("בשבוע הבא ביום ראשון", 7),
    ]
    for line in sunday {
      let text = "פגישה \(line.text)"
      #expect(parse(text, weekday: 1, today: "2026-09-27").plannedDayOffset == line.offset, "Sunday: \(text)")
    }
  }

  @Test("שבת names Saturday after ב or יום, and is the Sabbath or the verb to sit elsewhere")
  func saturdayOrSabbath() {
    for text in ["בשבת", "ביום שבת", "בשבת בבוקר", "בשבת בערב", "בשבת הבאה", "יום שבת"] {
      let parsed = parse("ללכת לים \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "ללכת לים", "\(text): title")
    }
    expectLinesUnread(
      [
        "לברך שבת שלום לכולם", "לאפות חלה לשבת", "לשבת ליד החלון ולקרוא", "להשיג כרטיס לשבת", "לאכול ארוחת שבת אצל סבתא",
        "להתכונן לשבת", "להכין עוגה לשבת הבאה",
      ], languages: ["he"])
  }

  @Test("The weekend is the coming Saturday, today when it is already here, and next week's after הבא")
  func weekend() {
    for text in [
      "בסוף השבוע", "בסוף שבוע", "בסופ״ש", "בסופ\"ש", "בסופ”ש", "בסופש", "סופש", "סופ״ש", "לסוף השבוע", "סוף השבוע",
      "בסוף השבוע הזה", "בסוף השבוע הקרוב",
    ] {
      let parsed = parse("לתקן את הברז \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "לתקן את הברז", "\(text): title")
    }
    for text in ["בסוף השבוע הבא", "בסוף שבוע הבא", "סוף השבוע הבא", "בסופ״ש הבא"] {
      #expect(parse("לתקן את הברז \(text)").plannedDayOffset == 11, "\(text)")
    }
    // Friday 09-25 is the last working day, and Saturday and Sunday are in the weekend.
    #expect(parse("פגישה בסוף השבוע", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("פגישה בסוף השבוע", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("פגישה בסוף השבוע", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("פגישה בסוף השבוע הבא", weekday: 6, today: "2026-09-25").plannedDayOffset == 8)
    #expect(parse("פגישה בסוף השבוע הבא", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
    #expect(parse("פגישה בסוף השבוע הבא", weekday: 1, today: "2026-09-27").plannedDayOffset == 7)
    #expect(parse("פגישה בסופ״ש", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
  }

  // MARK: - Dates

  @Test("Written dates: every month, in the spellings people type, with a year, a label, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("5 בינואר", "2027-01-05"), ("5 בפברואר", "2027-02-05"), ("5 במרץ", "2027-03-05"), ("5 במרס", "2027-03-05"),
      ("5 באפריל", "2027-04-05"), ("5 במאי", "2027-05-05"), ("5 ביוני", "2027-06-05"), ("5 ביולי", "2027-07-05"),
      ("5 באוגוסט", "2027-08-05"), ("5 בספטמבר", "2027-09-05"), ("5 באוקטובר", "2026-10-05"),
      ("5 בנובמבר", "2026-11-05"), ("5 בדצמבר", "2026-12-05"), ("5 מרץ", "2027-03-05"),
      ("22 בספטמבר", "2026-09-22"), ("20 בספטמבר", "2027-09-20"), ("5 במאי 2027", "2027-05-05"),
      ("5 במאי, 2028", "2028-05-05"), ("1 בינואר 2027", "2027-01-01"), ("5 באוקטובר 2026", "2026-10-05"),
      ("22 בספטמבר 2026", "2026-09-22"), ("ב-5 במאי", "2027-05-05"), ("ב־5 במאי", "2027-05-05"),
      ("ה-5 במאי", "2027-05-05"), ("בתאריך 5 במאי", "2027-05-05"), ("לתאריך 5 במאי", "2027-05-05"),
      ("ביום שני, 5 באוקטובר", "2026-10-05"),
    ]
    for line in dates {
      let text = "חופשה \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "חופשה", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
      #expect(parsed.phrases.map(\.kind) == [.when], "\(text): phrase kind")
    }
  }

  @Test("A month needs its day before it, and a date in digits, another calendar, or a day the month lacks is no date")
  func unreadDates() {
    expectLinesUnread(
      [
        // The Hebrew calendar's months are not Gregorian dates.
        "חופשה 5 בתשרי", "חופשה 5 בניסן", "חופשה י״ב בתשרי",
        // A month alone, a month before its day, and a day of a month with no month.
        "חופשה במאי", "חופשה מאי 5",
        // Digits only.
        "חופשה 5/10", "חופשה 5.10", "חופשה 5.10.2026", "חופשה ב-5.10",
        // A day the month does not have, and a year outside the supported years.
        "חופשה 31 באפריל", "חופשה 30 בפברואר", "חופשה 32 במאי", "חופשה 0 במאי", "חופשה 5 במאי 1999",
        "חופשה 5 במאי 2050",
        // Names that are also the names of months.
        "לדבר עם מאי על התוכנית", "להתקשר ליוני", "לקנות מתנה למאי",
      ], languages: ["he"])
    // A name that looks like a month is left alone beside a date.
    let name = parse("לדבר עם מאי ב-5 במאי")
    #expect(name.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(name.title == "לדבר עם מאי")
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("חופשה", "מ-3 עד 5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "מה-3 ועד ה-5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "מ-3 במרץ עד 5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "מ-30 בינואר עד 2 בפברואר", "2027-01-30", "2027-02-02"),
        ("חופשה", "בין 3 ל-5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "בין 3 ו-5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "בין ה-3 ל-5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "3-5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "3–5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "3־5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "מ-3 במרץ ועד 5 באפריל", "2027-03-03", "2027-04-05"),
        ("חופשה", "מ-3 עד 5 במרץ 2027", "2027-03-03", "2027-03-05"),
        ("חופשה", "מתאריך 3 עד 5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "בתאריכים 3-5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "מיום 3 עד 5 במרץ", "2027-03-03", "2027-03-05"),
        ("חופשה", "מ-25 בדצמבר עד 2 בינואר", "2026-12-25", "2027-01-02"),
        ("להזמין כרטיסים לקונצרט", "מ-12 במרץ עד 20 במרץ", "2027-03-12", "2027-03-20"),
        ("ספרינט", "12-20 במרץ", "2027-03-12", "2027-03-20"),
      ], languages: ["he"])
  }

  @Test("A range whose end is not after its start, that names no month, or that names two days stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "חופשה מ-5 עד 3 במרץ", "חופשה מ-3 במרץ עד 3 במרץ", "חופשה 5-3 במרץ",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "חופשה 3 עד 5", "חופשה בין 3 ל-5",
        // Two days joined by "ו" are two days, not a range.
        "חופשה 3 ו-5 במרץ", "חופשה ב-3 ו-5 במרץ",
        // A range in the past may be an event the task only prepares for.
        "חופשה מ-3 עד 5 במרץ הייתה", "החופשה מ-3 עד 5 במרץ הייתה נהדרת",
      ], languages: ["he"])
    // A day number before a deadline day is not part of the deadline.
    let deadline = parse("חופשה 3 עד 5 במרץ")
    #expect(deadline.title == "חופשה 3")
    #expect(deadline.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(deadline.plannedDayOffset == nil)
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("ספרינט 12 - 20 במרץ")
    #expect(sprint.title == "ספרינט 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("ספרינט", "12-20 במרץ", "2027-03-12", "2027-03-20")], languages: ["he"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("חופשה מ-3 עד 5 במרץ ביום שני")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "חופשה ביום שני")
    let tomorrow = parse("חופשה מ-3 עד 5 במרץ מחר")
    #expect(tomorrow.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(tomorrow.title == "חופשה מחר")
    // A clock time before the range is the start time.
    let timed = parse("חופשה בשעה 5 מ-3 עד 5 במרץ")
    #expect(timed.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 17 * 60)
    #expect(timed.title == "חופשה")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("סדנה משני עד רביעי")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "סדנה")
    #expect(span.phrases.map(\.text) == ["משני עד רביעי"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("חופשה מיום שני עד יום רביעי", 6, 8), ("חופשה מיום שני ועד רביעי", 6, 8),
      ("חופשה בין יום שני ליום רביעי", 6, 8), ("חופשה מיום ב׳ עד ד׳", 6, 8), ("חופשה יום שני עד יום רביעי", 6, 8),
      ("חופשה ביום שני עד יום רביעי", 6, 8), ("סדנה מיום שני עד רביעי", 6, 8), ("סדנה משני עד יום רביעי", 6, 8),
      ("חופשה מיום שישי עד יום ראשון", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("חופשה מיום שלישי עד יום חמישי", 7, 9), ("סדנה משלישי עד חמישי", 7, 9),
    ]
    for line in spans {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.planned, "\(line.text): planned day")
      #expect(parsed.dueDayOffset == line.due, "\(line.text): due day")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
      #expect(parsed.phrases.map(\.kind) == [.when], "\(line.text): phrase kind")
    }
    // Sunday to Thursday, Sunday to Friday, Monday to Friday, and Monday to
    // Saturday may be a week of work as well as a span of days, so they stay in
    // the title. So does a span from a day to itself and one in the past.
    expectLinesUnread(
      [
        "חופשה מיום ראשון עד יום חמישי", "חופשה מיום ראשון עד יום שישי", "חופשה מיום שני עד יום שישי",
        "חופשה מיום שני עד יום שבת", "סדנה מראשון עד שישי", "חופשה מיום שני עד יום שני",
        "חופשה מיום שני עד יום רביעי הייתה",
      ], languages: ["he"])
    // A weekday followed by a deadline weekday is two phrases, not a span.
    let separate = parse("סדנה בשני עד רביעי")
    #expect(separate.plannedDayOffset == 6)
    #expect(separate.dueDayOffset == 1)
    #expect(separate.phrases.map(\.kind) == [.when, .due])
  }

  @Test("A weekday in a list of weekdays is no planned day")
  func weekdayLists() {
    expectLinesUnread(
      [
        "להתאמן ביום שני וחמישי", "להתאמן בשני ובחמישי", "להתאמן בשני, בחמישי", "להתאמן בשני וגם בחמישי",
        "ללכת לים בשישי ובשבת", "ללכת לים בשישי או בשבת", "פגישה בשבת ובראשון", "פגישה בשישי-שבת",
        "פגישה בשישי - שבת", "פגישה בשישי־שבת", "פגישה ביום שישי-שבת", "פגישה בשישי, שבת",
        "להתאמן ביום שני וגם ביום חמישי", "להתאמן ביום שני או ביום חמישי", "להתאמן ביום שני, ביום חמישי",
        "להתאמן ביום שני, חמישי ושישי", "ביום שני ובחמישי להתאמן", "להתאמן בשני בבוקר ובחמישי בערב",
      ], languages: ["he"])
    // A weekday beside another word is still the day.
    let pair = parse("ביום שישי פגישה, ביום שני סיכום")
    #expect(pair.plannedDayOffset == 3)
  }

  // MARK: - Due days

  @Test("Due days: עד, לפני, לא יאוחר מ, מועד אחרון, תאריך יעד, and דדליין")
  func dueDays() {
    let may = captureDayOffset("2027-05-05")
    let march = captureDayOffset("2027-03-05")
    let due: [(text: String, title: String, offset: Int)] = [
      ("להגיש דוח עד יום שישי", "להגיש דוח", 3), ("להגיש דוח עד שישי", "להגיש דוח", 3),
      ("להגיש דוח עד חמישי", "להגיש דוח", 2), ("להגיש דוח עד מחר", "להגיש דוח", 1),
      ("להגיש דוח עד מחרתיים", "להגיש דוח", 2), ("להגיש דוח עד הערב", "להגיש דוח", 0),
      ("להגיש דוח עד הלילה", "להגיש דוח", 0), ("להגיש דוח עד סוף היום", "להגיש דוח", 0),
      ("להגיש דוח עד סוף יום שני", "להגיש דוח", 6), ("להגיש דוח עד שבת", "להגיש דוח", 4),
      ("להגיש דוח עד יום שני הבא", "להגיש דוח", 6), ("להגיש דוח עד השבוע הבא", "להגיש דוח", 7),
      ("להגיש דוח עד שבוע הבא", "להגיש דוח", 7), ("להגיש דוח עד ה-5 במרץ", "להגיש דוח", march),
      ("להגיש דוח עד 5 במרץ", "להגיש דוח", march), ("להגיש דוח עד 5 במרץ 2027", "להגיש דוח", march),
      ("להגיש דוח עד 5 במאי", "להגיש דוח", may), ("להגיש דוח לפני יום שישי", "להגיש דוח", 3),
      ("להגיש דוח לפני שישי", "להגיש דוח", 3), ("להגיש דוח לפני יום שבת", "להגיש דוח", 4),
      ("להגיש דוח לפני 5 במרץ", "להגיש דוח", march), ("להגיש דוח לא יאוחר מיום שלישי", "להגיש דוח", 7),
      ("להגיש דוח לא יאוחר ממחר", "להגיש דוח", 1), ("להגיש דוח לא יאוחר מ-5 במרץ", "להגיש דוח", march),
      ("להגיש דוח מועד אחרון: יום חמישי", "להגיש דוח", 2), ("להגיש דוח מועד אחרון יום חמישי", "להגיש דוח", 2),
      ("להגיש דוח תאריך יעד: 5 במרץ", "להגיש דוח", march), ("להגיש דוח תאריך יעד 5 במרץ", "להגיש דוח", march),
      ("להגיש דוח דדליין מחר", "להגיש דוח", 1), ("להגיש דוח דדליין: יום ראשון", "להגיש דוח", 5),
      ("מועד אחרון: יום חמישי להגיש דוח", "להגיש דוח", 2), ("להגיש דוח עד מחר בבוקר", "להגיש דוח", 1),
      ("להגיש דוח עד יום שישי בצהריים", "להגיש דוח", 3),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("להגיש דוח עד יום שישי מחר")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "להגיש דוח")
  }

  @Test("Deadlines that are idioms, a part of a day, or a stretch of time, and \"לפני שבת\", are no deadline day")
  func notDueDays() {
    expectLinesUnread(
      [
        "להגיש דוח עד היום", "להגיש דוח עד הבוקר", "להגיש דוח עד שני", "להגיש דוח עד סוף השבוע",
        "להגיש דוח עד סוף החודש", "להגיש דוח עד אחרי החגים", "להגיש דוח לפני שבת", "לפני שבת לסיים דוח",
        "להגיש דוח לפני מחר",
      ], languages: ["he"])
    // "לפני יום שבת" and "עד שבת" name the day.
    #expect(parse("לסיים דוח לפני יום שבת").dueDayOffset == 4)
    #expect(parse("לסיים דוח עד שבת").dueDayOffset == 4)
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "להגיש דוח עד 17:00", "להגיש דוח עד השעה 5", "להגיש דוח עד 5 בערב", "להגיש דוח לפני 18:00",
        "להגיש דוח אחרי 18:00", "להגיש דוח לא יאוחר מ-17:00", "להיפגש עד חצות", "להיפגש אחרי חצות",
      ], languages: ["he"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("להגיש דוח עד יום שישי בשעה 17:00")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "להגיש דוח בשעה 17:00")
    let tomorrow = parse("להגיש דוח עד מחר ב-9:00")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.startMinutes == nil)
    #expect(tomorrow.title == "להגיש דוח ב-9:00")
    #expect(parse("להגיש דוח עד מחר בשעה 9").title == "להגיש דוח בשעה 9")
    #expect(parse("להגיש דוח עד יום שישי ב-5 אחר הצהריים").title == "להגיש דוח ב-5 אחר הצהריים")
    // A time range that follows "עד" is still a range.
    let range = parse("ישיבה ב-11:00 עד 12:00")
    #expect(range.startMinutes == 11 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "ישיבה")
    // Without Hebrew, English reads the clock time and leaves the word.
    let english = parse("להגיש דוח עד 18:00", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "להגיש דוח עד")
  }

  // MARK: - Times

  @Test("Clock times: after שעה or ב, in digits and in words, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("פגישה בשעה 5", "פגישה", 17 * 60), ("פגישה בשעה 5:30", "פגישה", 17 * 60 + 30),
      ("פגישה בשעה 5.30", "פגישה", 17 * 60 + 30), ("פגישה בשעה 17", "פגישה", 17 * 60),
      ("פגישה בשעה 17:00", "פגישה", 17 * 60), ("פגישה בשעה 06:30", "פגישה", 6 * 60 + 30),
      ("פגישה בשעה 0:30", "פגישה", 30), ("פגישה ב-17:30", "פגישה", 17 * 60 + 30),
      ("פגישה ב־17:30", "פגישה", 17 * 60 + 30), ("פגישה ב–17:30", "פגישה", 17 * 60 + 30),
      ("פגישה ב-5:30", "פגישה", 17 * 60 + 30), ("פגישה 17:30", "פגישה", 17 * 60 + 30),
      ("פגישה 5:30", "פגישה", 17 * 60 + 30), ("פגישה שעה 5", "פגישה", 17 * 60),
      ("פגישה השעה 5", "פגישה", 17 * 60), ("פגישה לשעה 5", "פגישה", 17 * 60),
      ("פגישה שעה 17:30", "פגישה", 17 * 60 + 30), ("פגישה בשעה 5 עם דני", "פגישה עם דני", 17 * 60),
      ("בשעה 5 פגישה", "פגישה", 17 * 60),
      // A part of the day names the half of the day of the hour it follows.
      ("פגישה בשעה 6 בבוקר", "פגישה", 6 * 60), ("פגישה בשעה 9 בבוקר", "פגישה", 9 * 60),
      ("פגישה בשעה 5 בבוקר", "פגישה", 5 * 60), ("פגישה בשעה 7 בערב", "פגישה", 19 * 60),
      ("פגישה בשעה 8 בערב", "פגישה", 20 * 60), ("פגישה בשעה 9 בערב", "פגישה", 21 * 60),
      ("פגישה בשעה 8 בלילה", "פגישה", 20 * 60), ("פגישה בשעה 11 בלילה", "פגישה", 23 * 60),
      ("פגישה בשעה 12 בצהריים", "פגישה", 12 * 60), ("פגישה בשעה 1 בצהריים", "פגישה", 13 * 60),
      ("פגישה בשעה 1 בצהרים", "פגישה", 13 * 60), ("פגישה בשעה 2 אחר הצהריים", "פגישה", 14 * 60),
      ("פגישה בשעה 2 אחה״צ", "פגישה", 14 * 60), ("פגישה בשעה 9 לפנות בוקר", "פגישה", 9 * 60),
      ("פגישה בשעה 5 לפנות ערב", "פגישה", 17 * 60), ("פגישה ב-9 בבוקר", "פגישה", 9 * 60),
      ("פגישה ב-9 לפנה״צ", "פגישה", 9 * 60), ("פגישה ב-3 אחר הצהריים", "פגישה", 15 * 60),
      ("פגישה 9 בבוקר", "פגישה", 9 * 60), ("פגישה 5 בערב", "פגישה", 17 * 60),
      ("פגישה בחמש אחר הצהריים", "פגישה", 17 * 60), ("פגישה בחמש אחרי הצהריים", "פגישה", 17 * 60),
      ("פגישה בחמש בערב", "פגישה", 17 * 60), ("פגישה בחמש בבוקר", "פגישה", 5 * 60),
      ("פגישה בשבע בבוקר", "פגישה", 7 * 60), ("פגישה בשבע בערב", "פגישה", 19 * 60),
      ("פגישה בעשר בלילה", "פגישה", 22 * 60), ("פגישה בשתיים בצהריים", "פגישה", 14 * 60),
      ("פגישה בתשע בערב", "פגישה", 21 * 60), ("פגישה בשש בבוקר", "פגישה", 6 * 60),
      ("פגישה 5 בערב ועוד משהו", "פגישה ועוד משהו", 17 * 60),
      // Quotation marks and geresh in the abbreviation of the afternoon.
      ("פגישה בחמש אחה״צ", "פגישה", 17 * 60), ("פגישה בחמש אחה\"צ", "פגישה", 17 * 60),
      ("פגישה בחמש אחה”צ", "פגישה", 17 * 60),
      // 24-hour times and times with an English am or pm.
      ("פגישה בשעה 17:30 בערב", "פגישה", 17 * 60 + 30), ("פגישה ב-17:30 בערב", "פגישה", 17 * 60 + 30),
      ("פגישה 17:30 בערב", "פגישה", 17 * 60 + 30), ("פגישה בשעה 17 בערב", "פגישה", 17 * 60),
      ("פגישה ב-20 בערב", "פגישה", 20 * 60), ("פגישה בשעה 15:00 אחר הצהריים", "פגישה", 15 * 60),
      ("פגישה בשעה 15 אחר הצהריים", "פגישה", 15 * 60), ("פגישה בשעה 20:00 בלילה", "פגישה", 20 * 60),
      ("פגישה בשעה 09:30 בבוקר", "פגישה", 9 * 60 + 30), ("פגישה ב-16 בערב", "פגישה", 16 * 60),
      ("פגישה ב-16:30 אחר הצהריים", "פגישה", 16 * 60 + 30), ("פגישה בשעה 14 בצהריים", "פגישה", 14 * 60),
      ("פגישה ב-3pm", "פגישה", 15 * 60), ("פגישה ב-3 pm", "פגישה", 15 * 60), ("פגישה ב-3PM", "פגישה", 15 * 60),
      ("פגישה ב-3:30pm", "פגישה", 15 * 60 + 30), ("פגישה ב-9am", "פגישה", 9 * 60), ("פגישה 3pm", "פגישה", 15 * 60),
      ("פגישה at 3pm", "פגישה", 15 * 60), ("פגישה בשעה 3pm", "פגישה", 15 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The phrase is the whole time, with its hour word and its part of the day.
    #expect(parse("פגישה בשעה 5 בערב").phrases.map(\.text) == ["בשעה 5 בערב"])
    #expect(parse("פגישה ב-17:30").phrases.map(\.text) == ["ב-17:30"])
    #expect(parse("פגישה בחמש אחה״צ").phrases.map(\.text) == ["בחמש אחה״צ"])
  }

  @Test("An hour that no part of the day, \"שעה\", colon, or fraction accompanies is no time")
  func bareHours() {
    expectLinesUnread(
      [
        "פגישה ב-5", "פגישה בחמש", "פגישה בשבע", "פגישה שבע", "פגישה חמש", "פגישה בשלוש", "פגישה שלוש",
        "פגישה בשלושה", "פגישה בשתיים", "פגישה בעשר", "פגישה בדיוק ב-5", "פגישה בערך 5 עמודים",
        // An hour that does not exist.
        "פגישה בשעה 24:00", "פגישה בשעה 5:60", "פגישה בשעה 24", "פגישה בשעה 25",
        // A morning hour of twelve, and an evening or night hour that the 24-hour clock puts elsewhere.
        "פגישה בשעה 12 בבוקר", "פגישה בשעה 14 בלילה", "פגישה בשעה 14 בערב", "פגישה בשעה 19 אחר הצהריים",
        "פגישה בשעה 9 אחר הצהריים",
      ], languages: ["he"])
  }

  @Test("Clock fractions: וחצי, ורבע, רבע ל, פחות רבע, and minutes after the hour")
  func clockFractions() {
    let times: [(text: String, minutes: Int)] = [
      ("פגישה בשלוש וחצי", 15 * 60 + 30), ("פגישה בשלוש ורבע", 15 * 60 + 15), ("פגישה בשעה 3 וחצי", 15 * 60 + 30),
      ("פגישה בשעה 3 ורבע", 15 * 60 + 15), ("פגישה בשעה חמש וחצי", 17 * 60 + 30),
      ("פגישה בשעה שש ורבע בבוקר", 6 * 60 + 15), ("פגישה ברבע לשש", 17 * 60 + 45),
      ("פגישה בשעה רבע לשש", 17 * 60 + 45), ("פגישה בשעה רבע ל-6", 17 * 60 + 45),
      ("פגישה ברבע ל-6", 17 * 60 + 45), ("פגישה בשעה 4 פחות רבע", 15 * 60 + 45),
      ("פגישה בארבע פחות רבע", 15 * 60 + 45), ("פגישה בשעה 1 פחות רבע", 12 * 60 + 45),
      ("פגישה בשעה אחת פחות רבע", 12 * 60 + 45), ("פגישה באחת וחצי", 13 * 60 + 30),
      ("פגישה בשתיים וחצי", 14 * 60 + 30), ("פגישה בשעה שתיים וחצי", 14 * 60 + 30),
      ("פגישה בשעה 12 וחצי", 12 * 60 + 30), ("פגישה בשמונה וחצי בערב", 20 * 60 + 30),
      ("פגישה בתשע וחצי בבוקר", 9 * 60 + 30), ("פגישה ב-8 וחצי בערב", 20 * 60 + 30),
      ("פגישה בארבע וחצי", 16 * 60 + 30), ("פגישה ב-4 וחצי", 16 * 60 + 30),
      ("פגישה בארבע וחצי אחר הצהריים", 16 * 60 + 30),
      // Minutes after the hour, as digits or as words.
      ("פגישה בשעה 3 ו-10 דקות", 15 * 60 + 10), ("פגישה בשעה 3 ועשר דקות", 15 * 60 + 10),
      ("פגישה בשעה שלוש ו-10 דקות", 15 * 60 + 10), ("פגישה בשעה שלוש ועשרים וחמש דקות", 15 * 60 + 25),
      ("פגישה בשעה 3 ו-10 דקות אחר הצהריים", 15 * 60 + 10), ("פגישה בשעה 17 ו-20 דקות", 17 * 60 + 20),
      ("פגישה ב-5 ו-20 דקות אחר הצהריים", 17 * 60 + 20),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "פגישה", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Minutes after an hour with no word that makes it a time are an amount of time.
    expectLinesUnread(
      [
        "פגישה בשעה 13 וחצי", "פגישה בשעה 0 וחצי", "פגישה בשעה 13 ורבע", "פגישה בשעה רבע ל-13", "פגישה בשעה 5 ו-61 דקות",
      ], languages: ["he"])
  }

  @Test("An hour as a number word is read after שעה or ב with a fraction or a part of the day")
  func numberWordHours() {
    let hours: [(text: String, minutes: Int)] = [
      ("אחת", 13 * 60), ("שתיים", 14 * 60), ("שתים", 14 * 60), ("שלוש", 15 * 60), ("ארבע", 16 * 60),
      ("חמש", 17 * 60), ("שש", 18 * 60), ("שבע", 7 * 60), ("שמונה", 8 * 60), ("תשע", 9 * 60), ("עשר", 10 * 60),
      ("אחת עשרה", 11 * 60), ("שתים עשרה", 12 * 60), ("שתיים עשרה", 12 * 60), ("שתים-עשרה", 12 * 60),
      ("אחת-עשרה", 11 * 60),
    ]
    for hour in hours {
      let text = "פגישה בשעה \(hour.text)"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "פגישה", "\(text): title")
      #expect(parsed.phrases.map(\.text) == ["בשעה \(hour.text)"], "\(text): phrase")
    }
    expectLinesUnread(
      [
        // The masculine form counts nouns and the thirteenth hour is not a clock hour in words.
        "פגישה בשעה אחד עשר", "פגישה בשעה שלוש עשרה",
        // A number word after a plain ב is a count of something.
        "פגישה בשלושה אנשים", "פגישה בשלוש דקות", "פגישה בשלוש שעות", "פגישה בחמישה ימים",
      ], languages: ["he"])
    let eleven = parse("פגישה באחת עשרה בלילה")
    #expect(eleven.startMinutes == 23 * 60)
    #expect(eleven.title == "פגישה")
  }

  @Test("After midnight: לילה runs past the midnight that ends the day, and חצות is midnight")
  func afterMidnight() {
    let nights: [(text: String, title: String, day: Int, minutes: Int)] = [
      ("פגישה בשעה 12 בלילה", "פגישה", 1, 0), ("פגישה בשעה 1 בלילה", "פגישה", 1, 60),
      ("פגישה בשעה 2 בלילה", "פגישה", 1, 2 * 60), ("פגישה באחת בלילה", "פגישה", 1, 60),
      ("פגישה בשתיים בלילה", "פגישה", 1, 2 * 60), ("פגישה בשלוש בלילה", "פגישה", 1, 3 * 60),
      ("פגישה בשתים עשרה בלילה", "פגישה", 1, 0), ("פגישה בחצות", "פגישה", 1, 0),
      ("פגישה בחצות הלילה", "פגישה", 1, 0), ("פגישה בשעה חצות", "פגישה", 1, 0),
      ("להיפגש ב-12 בלילה", "להיפגש", 1, 0), ("להתקשר בשעה 2 בלילה", "להתקשר", 1, 2 * 60),
      ("להתקשר היום בלילה בשעה 2", "להתקשר", 1, 2 * 60), ("להתקשר בשעה 12 בלילה מחר", "להתקשר", 2, 0),
      ("מחר בלילה בשעה 1 לישון", "לישון", 2, 60), ("ביום שני בלילה בשעה 12 טיסה", "טיסה", 7, 0),
    ]
    for line in nights {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.day, "\(line.text): planned day")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): minutes")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // Before midnight, the evening hours of the night keep their day.
    for line in [("פגישה בשעה 8 בלילה", 20 * 60), ("פגישה בשעה 11 בלילה", 23 * 60), ("להתקשר בשעה 6 בלילה", 18 * 60)] {
      let parsed = parse(line.0)
      #expect(parsed.plannedDayOffset == nil, "\(line.0): planned day")
      #expect(parsed.startMinutes == line.1, "\(line.0): minutes")
    }
    // The midnight that ends Friday falls on Saturday, so a repeat on Friday at 12 at night repeats on Saturday.
    let friday = parse("כל יום שישי בשעה 12 בלילה טיסה")
    #expect(friday.startMinutes == 0)
    #expect(friday.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(friday.title == "טיסה")
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoonHours() {
    let hours: [(text: String, minutes: Int)] = [
      ("פגישה בשעה 1", 13 * 60), ("פגישה בשעה 3:00", 15 * 60), ("פגישה בשעה 6", 18 * 60), ("פגישה בשעה 7", 7 * 60),
      ("פגישה בשעה 11", 11 * 60), ("פגישה בשעה 12", 12 * 60), ("פגישה בשעה 13", 13 * 60),
      ("פגישה בשעה 03:00", 3 * 60), ("פגישה בשעה 07:00", 7 * 60), ("פגישה בשעה 07", 7 * 60),
      ("פגישה בשעה 00:00", 0), ("פגישה בשעה 23:59", 23 * 60 + 59),
    ]
    for hour in hours {
      #expect(parse(hour.text).startMinutes == hour.minutes, "\(hour.text)")
    }
  }

  @Test("A time may carry בערך, בסביבות, בדיוק, or בקירוב before or after it")
  func approximations() {
    let approximate: [(text: String, title: String, minutes: Int, phrase: String)] = [
      ("פגישה בערך בשעה 5", "פגישה", 17 * 60, "בערך בשעה 5"), ("פגישה בסביבות 5 בערב", "פגישה", 17 * 60, "בסביבות 5 בערב"),
      ("פגישה בשעה 5 בדיוק", "פגישה", 17 * 60, "בשעה 5 בדיוק"), ("פגישה בדיוק בשעה 5", "פגישה", 17 * 60, "בדיוק בשעה 5"),
      ("פגישה בשעה 5 בערב בערך", "פגישה", 17 * 60, "בשעה 5 בערב בערך"),
      ("פגישה בסביבות השעה 5", "פגישה", 17 * 60, "בסביבות השעה 5"), ("פגישה בקירוב בשעה 5", "פגישה", 17 * 60, "בקירוב בשעה 5"),
      ("פגישה בערך 5 בערב", "פגישה", 17 * 60, "בערך 5 בערב"), ("פגישה בערך ב-17:30", "פגישה", 17 * 60 + 30, "בערך ב-17:30"),
      ("פגישה בשעה 17:30 בדיוק", "פגישה", 17 * 60 + 30, "בשעה 17:30 בדיוק"),
      ("פגישה בערך בשלוש וחצי", "פגישה", 15 * 60 + 30, "בערך בשלוש וחצי"),
    ]
    for line in approximate {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // The word alone, or before a count, is no time.
    expectLinesUnread(["פגישה בערך", "פגישה בדיוק כמו בפעם הקודמת", "פגישה בערך 5 עמודים"], languages: ["he"])
    let with = parse("פגישה בשעה 5 ומשהו")
    #expect(with.startMinutes == 17 * 60)
    #expect(with.title == "פגישה ומשהו")
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let lines: [(text: String, title: String, minutes: Int)] = [
      ("שיחה הערב בשעה 8", "שיחה", 20 * 60), ("שיחה בשעה 8 הערב", "שיחה", 20 * 60),
      ("שיחה הבוקר בשעה 8", "שיחה", 8 * 60), ("שיחה בבוקר בשעה 8", "שיחה בבוקר", 8 * 60),
      ("שיחה בערב בשעה 8", "שיחה בערב", 20 * 60), ("שיחה בלילה בשעה 8", "שיחה בלילה", 20 * 60),
      ("שיחה בערב בשעה 5", "שיחה בערב", 17 * 60), ("שיחה בלילה בשעה 11", "שיחה בלילה", 23 * 60),
      ("שיחה בצהריים בשעה 12", "שיחה בצהריים", 12 * 60), ("שיחה בצהריים בשעה 2", "שיחה בצהריים", 14 * 60),
      ("שיחה אחר הצהריים בשעה 3", "שיחה אחר הצהריים", 15 * 60), ("שיחה בבוקר בשעה 12", "שיחה בבוקר", 12 * 60),
      ("שיחה בבוקר ובערב בשעה 8", "שיחה בבוקר ובערב", 8 * 60), ("ארוחת ערב בשעה 8", "ארוחת ערב", 20 * 60),
      ("ארוחת צהריים בשעה 1", "ארוחת צהריים", 13 * 60), ("ארוחת בוקר בשעה 8", "ארוחת בוקר", 8 * 60),
      ("ארוחת בוקר בשעה 12", "ארוחת בוקר", 12 * 60), ("בוקר טוב, בשעה 12", "בוקר טוב", 12 * 60),
      ("פגישה אחרי הצהרים בשעה 4", "פגישה אחרי הצהרים", 16 * 60),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // A line with a part of the day inside a time keeps the title's other words.
    let lunch = parse("פגישה בצהריים בשעה 1")
    #expect(lunch.startMinutes == 13 * 60)
    #expect(lunch.title == "פגישה בצהריים")
  }

  @Test("Time ranges: מ and עד, בין and ל, a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, title: String, start: Int, length: Int, day: Int?)] = [
      ("פגישה מ-9 עד 11 בבוקר", "פגישה", 9 * 60, 120, nil), ("פגישה מ־9 עד 11 בבוקר", "פגישה", 9 * 60, 120, nil),
      ("ישיבה בין 2 ל-4 אחר הצהריים", "ישיבה", 14 * 60, 120, nil),
      ("ישיבה בין השעות 14:00 ל-16:00", "ישיבה", 14 * 60, 120, nil), ("ישיבה בשעות 9-11", "ישיבה", 9 * 60, 120, nil),
      ("ישיבה 14:00-16:00", "ישיבה", 14 * 60, 120, nil), ("אימון 18:00-19:30", "אימון", 18 * 60, 90, nil),
      ("פגישה משעה 9 עד 11", "פגישה", 9 * 60, 120, nil),
      ("ישיבה מ-9 בבוקר עד 5 אחר הצהריים", "ישיבה", 9 * 60, 480, nil),
      ("פגישה מחר בין 10 ל-12 בצהריים", "פגישה", 10 * 60, 120, 1),
      ("פגישה מ-10:00 עד 11:30", "פגישה", 10 * 60, 90, nil), ("פגישה בין השעות 9 ל-11", "פגישה", 9 * 60, 120, nil),
      ("שיעור מ-17:00 עד 18:00 מחר", "שיעור", 17 * 60, 60, 1),
      ("שיעור בשעות 17:00 עד 18:00 ביום ראשון", "שיעור", 17 * 60, 60, 5),
      ("סדנה ב-9:00-11:00 מחר", "סדנה", 9 * 60, 120, 1),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.plannedDayOffset == line.day, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // Two bare numbers are a count, not a time range.
    expectLinesUnread(["מ-9 עד 11", "פגישה בין 9 ל-11", "לקרוא מ-14 עד 16 עמודים"], languages: ["he"])
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amountsAreNotTimes() {
    expectLinesUnread(
      [
        "פגישה בשעה 20%", "פגישה בשעה 5 ש״ח", "פגישה ב-5 ש״ח", "פגישה ב-500 שקלים", "פגישה ב-5 ימים",
        "פגישה ב-5 דקות", "פגישה ב-3 אנשים", "לסיים בשלוש וחצי שעות", "לרוץ ב-5 וחצי ק״מ", "לקנות ב-3 וחצי שקלים",
        "לשלם ב-5 וחצי ימים", "לקנות 5 וחצי קילו", "לקנות ב-5 וחצי קילו", "לקנות ב-2 וחצי אלף שקל",
        "לסיים בשלוש ורבע שעות", "לקנות שעון ב-200 שקל", "לקנות שעון ב-5 שעות", "להתקשר ל-03-1234567",
        "לבדוק את רחוב הרצל 5", "לקרוא פרק 5 בעמוד 30", "לשלם 20 שקל", "להוריד 20% מהמחיר", "לקנות 3 שעונים",
        "לקנות ב-5 שקלים", "לקנות ב-5 ימים", "להזמין 12 אנשים", "לבדוק גרסה 2.5", "לבדוק גרסה 3.14",
        "לכתוב 2.5 עמודים", "לצלם 16 תמונות", "לקנות 6 ביצים", "למלא טופס 1040", "לטפל בבקשה 4521",
        "להתקשר ל-5 אנשים", "לקרוא 5 עמודים בבוקר", "לקרוא 30 עמודים בערב", "לרוץ 5 קילומטר", "לרוץ 5 ק״מ בבוקר",
        "למכור ב-1000 דולר",
      ], languages: ["he"])
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("20 דקות", 20), ("20 דק׳", 20), ("20 דק'", 20), ("20 דקה", 20), ("1 דקה", 1), ("45 דקות", 45), ("90 דקות", 90),
      ("2 שעות", 120), ("3 שעות", 180), ("1.5 שעות", 90), ("1 שעה", 60), ("3 שע׳", 180), ("3 שע'", 180),
      ("1.5 שע׳", 90), ("שעה אחת", 60), ("שעה וחצי", 90), ("שעה ורבע", 75), ("שעתיים", 120), ("שעתיים וחצי", 150),
      ("שלוש שעות", 180), ("שלוש שעות וחצי", 210), ("שלושה שעות", 180), ("ארבע שעות", 240), ("חצי שעה", 30),
      ("רבע שעה", 15), ("שלושת רבעי שעה", 45), ("שלושה רבעי שעה", 45), ("שעה ו-30 דקות", 90), ("שעה ו־30 דקות", 90),
      ("שעה ו30 דקות", 90), ("שעה ו15 דק׳", 75), ("1 שעה ו15 דק׳", 75), ("3 שעות ו-20 דקות", 200),
      ("3 שע׳ ו20 דק׳", 200), ("1 שעה ו-30 דקות", 90), ("שעתיים ו-15 דקות", 135), ("שעתיים ו30 דק׳", 150),
      ("שעה ועשר דקות", 70), ("שלוש שעות ועשרים וחמש דקות", 205), ("שתי שעות ועשר דקות", 130),
      ("עשרים דקות", 20), ("חמש עשרה דקות", 15), ("חמישה עשר דקות", 15), ("שלושים דקות", 30),
      ("ארבעים וחמש דקות", 45), ("עשרים וחמש דקות", 25), ("שישים דקות", 60), ("עשר דקות", 10), ("חמש דקות", 5),
      // A word that says the length is approximate or intended.
      ("בערך שעה", 60), ("בערך 20 דקות", 20), ("כ-20 דקות", 20), ("כ־20 דקות", 20), ("כ20 דקות", 20),
      ("למשך שעה", 60), ("למשך 20 דקות", 20), ("במשך שעתיים", 120), ("ל-20 דקות", 20), ("ל־שעה", 60), ("לשעה", 60),
      ("לשעתיים", 120), ("לחצי שעה", 30), ("בערך שעה ורבע", 75), ("בערך שעה ועשרים דקות", 80),
      ("בערך שעתיים ועשרים דקות", 140),
    ]
    for line in lengths {
      let text = "לכתוב דוח \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "לכתוב דוח", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The noun of a length, and the word that follows it, are read with it.
    let nouns: [(text: String, title: String, minutes: Int, phrase: String)] = [
      ("ריצה של 30 דקות", "ריצה", 30, "של 30 דקות"), ("30 דקות של ריצה", "ריצה", 30, "30 דקות של"),
      ("30 דקות ריצה", "ריצה", 30, "30 דקות"), ("ריצה 30 דקות בערך", "ריצה", 30, "30 דקות בערך"),
      ("סרט בן שעתיים", "סרט", 120, "בן שעתיים"), ("ישיבה בת שעה", "ישיבה", 60, "בת שעה"),
      ("סרט בן שעה וחצי", "סרט", 90, "בן שעה וחצי"), ("ישיבה בת שעה וחצי", "ישיבה", 90, "בת שעה וחצי"),
      ("לכתוב דוח שעתיים בערך", "לכתוב דוח", 120, "שעתיים בערך"),
      ("לכתוב דוח 3 שעות מהבית", "לכתוב דוח מהבית", 180, "3 שעות"),
    ]
    for line in nouns {
      let parsed = parse(line.text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // A time and a length together, in either order.
    let both = parse("פגישה בשעה 5 ל-45 דקות")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "פגישה")
    for text in ["פגישה בשעה 5 למשך שעה", "פגישה בשעה 5 לשעה", "פגישה בשעה 5 בערך שעה", "פגישה 17:00 שעתיים", "פגישה שעתיים 17:00"] {
      let parsed = parse(text)
      #expect(parsed.startMinutes == 17 * 60, "\(text): time")
      #expect(parsed.estimatedMinutes == (text.contains("שעתיים") ? 120 : 60), "\(text): length")
      #expect(parsed.title == "פגישה", "\(text): title")
    }
  }

  @Test("An amount after בעוד, עוד, כל, לפני, אחרי, תוך, or בין, and a bare noun, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "לכתוב דוח בעוד 30 דקות", "לכתוב דוח בעוד שעה", "לכתוב דוח בעוד שעתיים", "לכתוב דוח עוד 20 דקות",
        "לכתוב דוח עוד חצי שעה", "לכתוב דוח כל 20 דקות", "לכתוב דוח כל שעתיים", "לכתוב דוח כל שעה",
        "לכתוב דוח כל חצי שעה", "לכתוב דוח לפני 20 דקות", "לכתוב דוח לפני שעה", "לכתוב דוח אחרי 20 דקות",
        "לכתוב דוח אחרי שעה", "לכתוב דוח 20 דקות לפני הפגישה", "לכתוב דוח 20 דקות אחרי הפגישה",
        "לכתוב דוח עד 20 דקות", "לכתוב דוח לפחות 20 דקות", "לכתוב דוח לכל היותר 20 דקות",
        "לכתוב דוח פחות מ-20 דקות", "לכתוב דוח יותר מ-20 דקות", "לכתוב דוח פחות מ30 דקות", "לכתוב דוח מעל 20 דקות",
        "לכתוב דוח תוך 20 דקות", "לכתוב דוח תוך שעתיים", "לכתוב דוח בתוך 20 דקות", "לכתוב דוח 20 דקות ביום",
        "לכתוב דוח 20 דקות בשבוע", "לכתוב דוח 2 שעות בשבוע", "לכתוב 5 דקות ביום", "ב-20 דקות", "ב-20 דקות הליכה",
        "כל 20 דקות", "מ-20 דקות", "לכתוב דוח מ-20 דקות",
        // A range of amounts, a bare noun, and an amount no task takes.
        "לכתוב דוח 2-3 שעות", "לכתוב דוח 2–3 שעות", "לכתוב דוח בין 2 ל-3 שעות", "לכתוב דוח מ-2 עד 3 שעות",
        "לכתוב דוח 2 עד 3 שעות", "לכתוב דוח 5 דקות עד 10 דקות", "לכתוב דוח דקה", "לכתוב דוח שעה", "לכתוב דוח שעה בערך",
        "לכתוב דוח שעה של ריצה", "לכתוב דוח 25 שעות", "לכתוב דוח 0 דקות", "לכתוב דוח 1,5 שעות",
        // Nouns that contain a unit word.
        "לכתוב דוח שעת סיום", "לכתוב דוח שעת עבודה", "לכתוב דוח שעות עבודה", "שעות עבודה", "דקה של שקט", "דקת דומיה",
        "לכתוב דוח הדקה ה-90", "חכה דקה", "לשבת שעה ליד החלון", "לקבוע שעה אצל הרופא", "לבדוק את השעה במחשב",
        "שעה טובה ומוצלחת", "לתקן את השעון", "לשים לב לשעות העבודה", "חצי כוס קמח", "לקנות חצי קילו גבינה",
        "לקנות רבע קילו חומוס", "לאפות חצי עוגה",
      ], languages: ["he"])
    // The phrase around an amount that is no length still reads.
    let day = parse("לכתוב דוח בעוד 30 דקות מחר")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "לכתוב דוח בעוד 30 דקות")
    let time = parse("פגישה מחר בשעה 3 תוך שעתיים")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "פגישה תוך שעתיים")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("כל יום", daily), ("בכל יום", daily), ("מדי יום", daily), ("מדי יום ביומו", daily), ("כל שבוע", weekly),
      ("בכל שבוע", weekly), ("מדי שבוע", weekly), ("כל חודש", monthly), ("מדי חודש", monthly), ("כל שנה", yearly),
      ("מדי שנה", yearly), ("אחת לשבוע", weekly), ("אחת לחודש", monthly), ("פעם בשבוע", weekly), ("פעם ביום", daily),
      ("פעם בחודש", monthly), ("פעם אחת בחודש", monthly), ("על בסיס יומי", daily), ("על בסיס שבועי", weekly),
      ("על בסיס חודשי", monthly), ("על בסיס שנתי", yearly),
      ("כל יומיים", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("כל שבועיים", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("כל חודשיים", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("כל שנתיים", TaskRecurrenceRule(freq: .yearly, interval: 2)),
      ("כל 2 ימים", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("כל 3 ימים", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("כל שלושה ימים", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("כל שני ימים", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("כל 3 שבועות", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("כל שלושה שבועות", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("כל 6 חודשים", TaskRecurrenceRule(freq: .monthly, interval: 6)),
      ("כל 5 שנים", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("אחת לחודשיים", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("אחת ל-3 ימים", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("אחת ליומיים", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("פעם בשבועיים", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("פעם ב-3 חודשים", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("יום כן יום לא", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("יום כן, יום לא", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("שבוע כן שבוע לא", TaskRecurrenceRule(freq: .weekly, interval: 2)),
    ]
    for line in cadences {
      let text = "לקחת תרופה \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "לקחת תרופה", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
    // The repeat opens the line as well.
    let opening = parse("כל יום לקחת תרופה")
    #expect(opening.recurrence == daily)
    #expect(opening.title == "לקחת תרופה")
  }

  @Test("Weekday repeats: כל יום שני, lists of days, בימי, a span of days, and the weekend")
  func weekdayRepeats() {
    let coming = parse("לקחת תרופה כל יום שני")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "לקחת תרופה")
    #expect(coming.plannedDayOffset == nil)

    let lists: [(text: String, days: [String])] = [
      ("כל יום שני", ["MO"]), ("כל יום ב׳", ["MO"]), ("כל שני", ["MO"]), ("בכל יום ראשון", ["SU"]), ("כל שבת", ["SA"]),
      ("כל יום שבת", ["SA"]), ("כל שישי", ["FR"]), ("כל יום שישי", ["FR"]), ("כל שבוע ביום שני", ["MO"]),
      ("כל שני וחמישי", ["MO", "TH"]), ("כל יום שני וחמישי", ["MO", "TH"]), ("כל יום שני ורביעי", ["MO", "WE"]),
      ("כל יום ראשון ושלישי וחמישי", ["SU", "TU", "TH"]), ("כל שני, רביעי וחמישי", ["MO", "WE", "TH"]),
      ("כל ב׳ וד׳", ["MO", "WE"]), ("כל ב' ו-ד'", ["MO", "WE"]), ("כל שבוע ביום שני וחמישי", ["MO", "TH"]),
      ("כל שני וכל חמישי", ["MO", "TH"]), ("כל יום שני וכל יום חמישי", ["MO", "TH"]),
      ("כל יום שני ויום חמישי", ["MO", "TH"]), ("כל שני, כל חמישי", ["MO", "TH"]), ("בימי שני", ["MO"]),
      ("בימי ראשון", ["SU"]), ("בימי שני וחמישי", ["MO", "TH"]), ("בימים שני וחמישי", ["MO", "TH"]),
      ("בימים א׳ ו-ג׳", ["SU", "TU"]),
      // The weekend, and a span of days.
      ("כל סוף שבוע", ["SU", "SA"]), ("כל סופ״ש", ["SU", "SA"]), ("בכל סוף השבוע", ["SU", "SA"]),
      ("כל יום ראשון עד חמישי", ["SU", "MO", "TU", "WE", "TH"]),
      ("כל יום שני עד שישי", ["MO", "TU", "WE", "TH", "FR"]), ("כל ראשון עד חמישי", ["SU", "MO", "TU", "WE", "TH"]),
      ("בימי ראשון עד חמישי", ["SU", "MO", "TU", "WE", "TH"]), ("בימים א׳-ה׳", ["SU", "MO", "TU", "WE", "TH"]),
    ]
    for line in lists {
      let text = "לקחת תרופה \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(text)")
      #expect(parsed.title == "לקחת תרופה", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
    // The first day is the soonest of the days, and today when it is one of them.
    #expect(parse("לקחת תרופה כל שני וחמישי").recurrenceStartOffset == 2)
    #expect(parse("לקחת תרופה כל סוף שבוע").recurrenceStartOffset == 4)
    #expect(parse("לקחת תרופה כל יום ראשון ושלישי וחמישי").recurrenceStartOffset == 0)
    #expect(parse("לקחת תרופה כל יום שלישי").recurrenceStartOffset == 0)
    #expect(parse("לקחת תרופה כל יום שישי", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
    // The part of the day after a weekday list stays in the title.
    let evening = parse("לקחת תרופה כל יום שני וחמישי בבוקר")
    #expect(evening.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TH"]))
    #expect(evening.title == "לקחת תרופה בבוקר")
    // A time after the repeat reads, with the weekday in the repeat.
    let timed = parse("כל יום שני בשעה 8 לקחת תרופה")
    #expect(timed.recurrence == monday)
    #expect(timed.startMinutes == 8 * 60)
    #expect(timed.title == "לקחת תרופה")
    // The "עד" inside a span joins its days and is no deadline word, so the time after the span is
    // the repeat's, while the same words after a deadline day stay in the title.
    for text in ["כל יום ראשון עד חמישי בשעה 8", "בימי ראשון עד חמישי בשעה 8", "כל ראשון עד חמישי ב-8:00"] {
      let span = parse("לקחת תרופה \(text)")
      #expect(span.recurrence == sundayToThursday, "\(text)")
      #expect(span.startMinutes == 8 * 60, "\(text): time")
      #expect(span.title == "לקחת תרופה", "\(text): title")
    }
    let deadline = parse("לקחת תרופה עד יום חמישי בשעה 8")
    #expect(deadline.dueDayOffset == 2)
    #expect(deadline.startMinutes == nil)
    #expect(deadline.title == "לקחת תרופה בשעה 8")
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("לקחת תרופה כל בוקר", "לקחת תרופה", nil), ("לקחת תרופה כל ערב", "לקחת תרופה", nil),
      ("לקחת תרופה כל לילה", "לקחת תרופה", nil), ("לקחת תרופה כל צהריים", "לקחת תרופה", nil),
      ("לקחת תרופה כל אחר הצהריים", "לקחת תרופה", nil), ("לקחת תרופה בכל בוקר", "לקחת תרופה", nil),
      ("לקחת תרופה מדי בוקר", "לקחת תרופה", nil), ("לקחת תרופה כל יום בבוקר", "לקחת תרופה", nil),
      ("לקחת תרופה כל יום בערב", "לקחת תרופה", nil), ("לקחת תרופה כל בוקר בשעה 8", "לקחת תרופה", 8 * 60),
      ("לקחת תרופה כל יום ב-8 בבוקר", "לקחת תרופה", 8 * 60), ("לקחת תרופה כל יום בשעה 8", "לקחת תרופה", 8 * 60),
      ("כל בוקר בשעה 6 לרוץ", "לרוץ", 6 * 60), ("כל ערב בשעה 8 ללמוד", "ללמוד", 20 * 60),
      ("כל לילה בשעה 11 לישון", "לישון", 23 * 60), ("לבדוק מייל כל יום בשעה 9 בבוקר", "לבדוק מייל", 9 * 60),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    // Two parts of the day are no single part: they stay in the title.
    expectLinesUnread(["תרופות כל בוקר ובערב", "כל בוקר ובערב"], languages: ["he"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "כל חודש ב-5", "בכל חודש ב-5", "ב-5 בכל חודש", "ב-5 לכל חודש", "בכל 5 לחודש",
    ] {
      let line = "לשלם שכר דירה \(text)"
      let parsed = parse(line)
      #expect(parsed.recurrence == rule, "\(line)")
      #expect(parsed.recurrenceStartOffset == 13, "\(line): start")
      #expect(parsed.title == "לשלם שכר דירה", "\(line): title")
    }
    let first = parse("לשלם שכר דירה ב-1 לכל חודש")
    #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    #expect(first.recurrenceStartOffset == 9)
    #expect(parse("לשלם שכר דירה כל חודש ב-1").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    #expect(parse("לשלם שכר דירה בכל 1 לחודש").recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]))
    // A day with no word for every month, and a day of the month with ל and no כל, are no repeat.
    expectLinesUnread(["לשלם שכר דירה חודש ב-5", "לשלם שכר דירה ב-1 לחודש"], languages: ["he"])
  }

  @Test("A repeat shorter than a day, an adjective of cadence, and an idiom with כל are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        // Repeats shorter than a day, and the part of a day that כל spans.
        "לקחת תרופה כל שעתיים", "לקחת תרופה כל 2 שעות", "לקחת תרופה כל שעה", "לקחת תרופה כל 15 דקות",
        "לקחת תרופה כל הבוקר", "לקחת תרופה כל הערב", "לקחת תרופה כל היום", "לקחת תרופה כל השבוע",
        "לשתות מים כל שעתיים", "לשתות מים כל שעה", "כל שעתיים", "כל השבוע הבא",
        // The adjectives of cadence name a kind of task.
        "דוח שבועי", "דוח יומי", "ישיבה שבועית", "סקירה חודשית", "תקציב שנתי", "לתכנן את שבוע העבודה", "לתכנן שבוע טוב",
        "לקבוע מפגש שבועי", "דוח חודשי", "דוח שבועי למנהל", "דוח יומי לבוס", "חשבון חודשי", "לשלם את החשבון החודשי",
        // "כל" in idioms and before an event or a place in the week.
        "כל המשימות", "כל הכבוד", "כל הכבוד לצוות", "כל אחד מהם", "כל מי שרוצה", "כל יום הולדת", "לקחת תרופה כל ערב חג",
        "לקחת תרופה כל ערב שבת", "לקחת תרופה כל יום ראשון בחודש", "לקחת תרופה כל ראשון בחודש",
        "לקחת תרופה כל חצי שנה", "לקחת תרופה כל 100 ימים", "לקחת תרופה כל 0 ימים", "לקנות כל מה שצריך",
        "לאסוף כל יום הולדת", "לשלוח ברכה בכל יום הולדת", "לשלוח ברכה כל יום הולדת", "לבדוק כל הזמן",
        "מדי פעם לבדוק", "לבדוק כל פעם מחדש", "כל פעם שאני מגיע", "לצאת בכל זאת", "לקנות לכל אחד מתנה",
        "להזכיר לכל אחד", "בכל מקרה לבדוק", "לקחת תרופה מדי פעם", "לקחת תרופה מדי", "לקחת תרופה בכל מקרה",
        "לקחת תרופה בכל זאת", "לקחת תרופה כל כך", "לקחת תרופה כל פעם",
        // Counts of times, which this vocabulary does not turn into a cadence.
        "אחת ולתמיד לסיים", "אחת לכמה זמן", "פעם אחת לנסות", "פעם בחיים לנסות", "פעמיים בשבוע לרוץ",
        "להתעמל 3 פעמים בשבוע", "להתעמל פעמיים בשבוע",
        // The working week and days off are a custom, not a weekday list.
        "לקחת תרופה כל יום עבודה", "לקחת תרופה בימי עבודה", "לקחת תרופה ימי חול", "לקחת תרופה כל יום חול",
      ], languages: ["he"])
    // "פעם" before a named week or day is a word of the title, and the week or day is the task's day.
    let next = parse("לקחת תרופה פעם בשבוע הבא")
    #expect(next.recurrence == nil)
    #expect(next.plannedDayOffset == 7)
    #expect(next.title == "לקחת תרופה פעם")
    #expect(parse("לקחת תרופה פעם ביום ראשון").plannedDayOffset == 5)
    // A weekday with a bare ordinal after כל is a repeat and leaves the rest.
    #expect(parse("לשלוח כל שבוע שעבר").recurrence == weeklyRule)
  }

  // MARK: - Priorities

  @Test("Priorities: עדיפות גבוהה, בינונית, and נמוכה, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("עדיפות גבוהה", .p1), ("בעדיפות גבוהה", .p1), ("עדיפות: גבוהה", .p1), ("עדיפות גבוהה מאוד", .p1),
      ("עדיפות עליונה", .p1), ("עדיפות קריטית", .p1), ("עדיפות בינונית", .p2), ("עדיפות רגילה", .p2),
      ("עדיפות נורמלית", .p2), ("עדיפות נמוכה", .p3), ("בעדיפות נמוכה", .p3), ("עדיפות זניחה", .p3),
    ]
    for level in levels {
      let text = "לכתוב דוח \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "לכתוב דוח", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [level.text], "\(text): phrase")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let opening = parse("עדיפות גבוהה: לכתוב דוח")
    #expect(opening.priority == .p1)
    #expect(opening.title == "לכתוב דוח")
    let spaced = parse("עדיפות גבוהה לכתוב דוח")
    #expect(spaced.priority == .p1)
    #expect(spaced.title == "לכתוב דוח")
    let low = parse("עדיפות נמוכה לסדר את המגירה")
    #expect(low.priority == .p3)
    #expect(low.title == "לסדר את המגירה")

    for word in ["דחוף", "דחוף מאוד", "דחוף ביותר", "דחופה", "בהול", "בדחיפות", "בדחיפות גבוהה"] {
      let text = "לכתוב דוח \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "לכתוב דוח", "\(text): title")
    }
    for word in ["דחוף", "דחופה", "בהול", "בדחיפות"] {
      for separator in [":", ",", " ,"] {
        let text = "\(word)\(separator) לכתוב דוח"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "לכתוב דוח", "\(text): title")
      }
    }
    // The marks and codes every language shares.
    for text in ["לכתוב דוח !", "לכתוב דוח !!", "!!! לכתוב דוח", "לכתוב דוח p1"] {
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "לכתוב דוח", "\(text): title")
    }
    #expect(parse("p2 להכין דוח").priority == .p2)
    #expect(parse("סידור המחסן p3").priority == .p3)
    // Punctuation after the word is not part of it, and stays in the title.
    #expect(parse("לכתוב דוח דחוף!").priority == .p1)
    #expect(parse("לכתוב דוח בדחיפות.").priority == .p1)
    // An urgent word in the middle, or opening the line with no colon or comma, is a word of the title.
    expectLinesUnread(
      [
        "דחוף לקנות חלב", "דחוף לכתוב דוח", "זה דחוף כי", "לכתוב דוח חשוב", "חשוב להתקשר לרופא",
        "לבדוק את העדיפות של המשימה", "עדיפות לתשלום החשבונות", "לשלם בדחיפות לפני שבת", "לכתוב דוח עדיפות",
        "לכתוב דוח עדיפות ראשונה",
      ], languages: ["he"])
    // An urgent word before a deadline is a word of the title, but the deadline reads.
    let deadline = parse("להגיש דוח דחוף היום")
    #expect(deadline.priority == nil)
    #expect(deadline.plannedDayOffset == 0)
    #expect(deadline.title == "להגיש דוח דחוף")
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("פגישה מחר בשעה 5 בערב ל-30 דקות #עבודה")
    #expect(line.title == "פגישה")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["עבודה"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["מחר", "בשעה 5 בערב", "ל-30 דקות", "#עבודה"])

    let lines: [(text: String, title: String)] = [
      ("להתקשר לאמא מחר בשעה 5 בערב", "להתקשר לאמא"), ("לשלם חשבון חשמל עד יום חמישי", "לשלם חשבון חשמל"),
      ("פגישה עם דנה ביום שני הבא ב-10:00", "פגישה עם דנה"), ("ריצה חצי שעה כל בוקר", "ריצה"),
      ("לקנות חלב #קניות היום", "לקנות חלב"), ("דוח חודשי עד ה-5 במרץ עדיפות גבוהה", "דוח חודשי"),
      ("להגיש מס בעוד שבועיים", "להגיש מס"),
      ("שיעור יוגה כל יום שלישי וחמישי ב-18:00 למשך שעה", "שיעור יוגה"),
      ("לעשות סיכום שבועי כל יום שישי בשעה 14:00", "לעשות סיכום שבועי"),
      ("לאסוף את הילדים מהגן בשעה 16:30", "לאסוף את הילדים מהגן"),
      ("לקחת את הכלב לווטרינר ב-3 אחה\"צ ביום ראשון", "לקחת את הכלב לווטרינר"),
      ("מחר בבוקר ללכת לרופא שיניים ב-9:30 דחוף", "ללכת לרופא שיניים"), ("תשלום ארנונה כל חודשיים", "תשלום ארנונה"),
      ("יום הולדת לאמא ב-12 באוגוסט", "יום הולדת לאמא"), ("להכין מצגת ליום ראשון", "להכין מצגת"),
      ("אימון כל יום ב' וד'", "אימון"), ("לתקן את הברז בסוף השבוע", "לתקן את הברז"), ("לכבס כל סוף שבוע", "לכבס"),
      ("שיחת וידאו עם סבתא ביום שישי בצהריים בשעה 1", "שיחת וידאו עם סבתא"),
      ("להתקשר לרופא מחר ב-8 בבוקר ולקבוע תור", "להתקשר לרופא ולקבוע תור"),
      ("לבדוק מייל כל יום בשעה 9 בבוקר", "לבדוק מייל"), ("לקרוא ספר 20 דקות כל ערב", "לקרוא ספר"),
      ("לכתוב דוח שעתיים בערך", "לכתוב דוח"), ("לשלוח חשבונית בעוד 3 ימים", "לשלוח חשבונית"),
      ("ישיבת צוות ביום רביעי ב-11:00 עד 12:00", "ישיבת צוות"), ("לקנות מתנה לדנה !! עד יום שישי", "לקנות מתנה לדנה"),
      ("להתקשר לבנק ב-9 וחצי בבוקר", "להתקשר לבנק"), ("לשבת עם אבא בסוף שבוע הבא", "לשבת עם אבא"),
      ("לבקר את סבא בעוד חודש", "לבקר את סבא"), ("לטפל בבקשה בעוד יומיים בשעה 2", "לטפל בבקשה"),
      ("אסיפת הורים בשבוע הבא ביום שלישי בשעה 19:30", "אסיפת הורים"), ("אסיפת הורים בשני בערב", "אסיפת הורים"),
      ("להזמין כרטיסים לקונצרט מ-12 במרץ עד 20 במרץ", "להזמין כרטיסים לקונצרט"),
      ("ללמוד לבחינה מ-9 עד 12 מחר", "ללמוד לבחינה מ-9 עד 12"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(!parse(line.text).phrases.isEmpty, "\(line.text): phrases")
    }
    let friday = parse("מחר בבוקר ללכת לרופא שיניים ב-9:30 דחוף")
    #expect(friday.plannedDayOffset == 1)
    #expect(friday.startMinutes == 9 * 60 + 30)
    #expect(friday.priority == .p1)
    let yoga = parse("שיעור יוגה כל יום שלישי וחמישי ב-18:00 למשך שעה")
    #expect(yoga.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["TU", "TH"]))
    #expect(yoga.startMinutes == 18 * 60)
    #expect(yoga.estimatedMinutes == 60)
    let report = parse("דוח חודשי עד ה-5 במרץ עדיפות גבוהה")
    #expect(report.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(report.priority == .p1)
    let tomorrow = parse("להתקשר לרופא מחר ב-8 בבוקר ולקבוע תור")
    #expect(tomorrow.plannedDayOffset == 1)
    #expect(tomorrow.startMinutes == 8 * 60)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // Words made of a day word or a time word, or the same letters with a prefix.
        "לתקן את המחרוזת", "לעדכן את היומן", "לספור את הימים", "לתקן את השעון", "לשמוע חדשות הערב", "להכין את ארוחת הערב",
        "לצפות במהדורת הערב", "להכין את משמרת הלילה", "ארוחת צהריים עם אמא", "ארוחת בוקר עם הילדים", "ארוחת ערב חגיגית",
        // A day or a part of the day with another noun.
        "ללמוד את היום הראשון בקורס", "לכתוב על היום הזה", "לקרוא את החדשות של מחר", "לתכנן יום הולדת לדנה",
        "לקנות מתנה ליום הולדת", "לתכנן יום עיון", "לבקש יום חופש", "ליום כיפור יש לצום", "להיפגש עם יום",
        // A number that is a count, an address, a price, or a page.
        "להתקשר ל-03-1234567", "לבדוק את רחוב הרצל 5", "לקרוא פרק 5 בעמוד 30", "לשלם 20 שקל",
        // A weekday with a month, a place, or "the month".
        "לשלם בתחילת החודש", "לשלם בסוף החודש", "לשלם בראשון לחודש", "להגיש בראשון במאי",
        // Yesterday and the past are no coming day.
        "להיפגש אתמול", "פגישה אתמול", "להיפגש למחרת", "פגישה ביום שני שעבר", "פגישה בשבוע שעבר", "פגישה ביום שני האחרון",
        // "השבוע" and a stretch of time that names no day.
        "להיפגש השבוע", "להיפגש בעוד שעה", "ללמוד בשעות הערב",
        // A ל before a bare weekday names what a thing is for.
        "הזמנת מסעדה לשישי בערב", "להכין עוגה לשבת הבאה",
      ], languages: ["he"])
    // Hebrew written in Latin letters is not read.
    expectLinesUnread(["machar baboker", "mahar lakahat halav", "kol yom sheni"], languages: ["he"])
    // A day word before ordinary words is still the day.
    let friday = parse("ביום שישי לתכנן את הארוחה")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "לתכנן את הארוחה")
    let birthday = parse("לתכנן יום הולדת לדנה מחר")
    #expect(birthday.plannedDayOffset == 1)
    #expect(birthday.title == "לתכנן יום הולדת לדנה")
  }

  // MARK: - מחר and the past

  @Test("מחר is tomorrow wherever it stands, and a line in the past tense with another day stays unread")
  func tomorrowOrYesterday() {
    let tomorrow = ["מחר יש פגישה", "מחר צריך לקנות חלב", "לקנות חלב מחר", "מחר נסע לים", "הוא יגיע מחר"]
    for text in tomorrow {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        "אתמול הייתה פגישה", "שלשום הייתה פגישה", "היום הייתה פגישה", "הפגישה הייתה ביום שני", "הפגישה היתה ביום שני",
        "פגישה היה ביום שלישי",
      ], languages: ["he"])
    // Tomorrow cannot be in the past, so the line is read as a plan.
    let past = parse("מחר הייתה פגישה")
    #expect(past.plannedDayOffset == 1)
    #expect(past.title == "הייתה פגישה")
    #expect(parse("פגישה שהייתה מחר").plannedDayOffset == 1)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("להגיש דוח דחוף").priority == .p1)
    #expect(parse("זה דחוף מאוד").priority == .p1)
    // "של דקה" after a noun is a one-minute length.
    #expect(parse("לעשות הפסקה של דקה").estimatedMinutes == 1)
    // A word after כל and a cadence noun stays in the title.
    let last = parse("לשלוח כל שבוע שעבר")
    #expect(last.recurrence == weeklyRule)
    #expect(last.title == "לשלוח שעבר")
    let letter = parse("לקחת תרופה כל יום א")
    #expect(letter.recurrence == daily)
    #expect(letter.title == "לקחת תרופה א")
    // Hours of work are a length, and "עבודה" stays.
    let work = parse("לכתוב דוח 8 שעות עבודה")
    #expect(work.estimatedMinutes == 480)
    #expect(work.title == "לכתוב דוח עבודה")
    // An hour after a clock phrase is a count of hours.
    #expect(parse("פגישה בשעה 5 שעה").estimatedMinutes == 5 * 60)
    // A past statement with no past-tense marker reads as a plan.
    #expect(parse("היום קיבלתי מכתב").plannedDayOffset == 0)
    #expect(parse("ביום ראשון הלכתי לים").plannedDayOffset == 5)
    // "היום" after a noun that is not in the construct state is today, even where the pair means
    // "today's game".
    let game = parse("לראות את משחק היום")
    #expect(game.plannedDayOffset == 0)
    #expect(game.title == "לראות את משחק")
    // A date's year past the supported years is left in the title.
    let year = parse("חופשה 5 במאי 2100")
    #expect(year.plannedDayOffset == captureDayOffset("2027-05-05"))
    #expect(year.title == "חופשה 2100")
  }

  // MARK: - Spellings and scripts

  @Test("Final letters, quotation marks, geresh, hyphens, and the spellings with or without a yod change nothing")
  func spellings() {
    let spellings: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      // The abbreviations with gershayim written as quotation marks.
      ("פגישה מחר ב-5 אחה״צ", { $0.startMinutes == 17 * 60 }), ("פגישה מחר ב-5 אחה\"צ", { $0.startMinutes == 17 * 60 }),
      ("פגישה מחר ב-5 אחה”צ", { $0.startMinutes == 17 * 60 }), ("פגישה מחר ב-9 לפנה״צ", { $0.startMinutes == 9 * 60 }),
      ("פגישה מחר ב-9 לפנה\"צ", { $0.startMinutes == 9 * 60 }), ("פגישה בסופ\"ש", { $0.plannedDayOffset == 4 }),
      ("פגישה בסופ”ש", { $0.plannedDayOffset == 4 }), ("פגישה בסופש", { $0.plannedDayOffset == 4 }),
      // The weekday letters with geresh, an apostrophe, a right quotation mark, and a backtick.
      ("פגישה ביום ג׳", { $0.plannedDayOffset == 7 }), ("פגישה ביום ג'", { $0.plannedDayOffset == 7 }),
      ("פגישה ביום ג’", { $0.plannedDayOffset == 7 }), ("פגישה ביום ג`", { $0.plannedDayOffset == 7 }),
      ("ריצה 30 דק׳", { $0.estimatedMinutes == 30 }), ("ריצה 30 דק'", { $0.estimatedMinutes == 30 }),
      ("ריצה 30 דק’", { $0.estimatedMinutes == 30 }),
      // The hyphen, the maqaf, the en dash, and the non-breaking hyphen before a number.
      ("פגישה ב-17:30", { $0.startMinutes == 17 * 60 + 30 }), ("פגישה ב־17:30", { $0.startMinutes == 17 * 60 + 30 }),
      ("פגישה ב–17:30", { $0.startMinutes == 17 * 60 + 30 }), ("פגישה ב‑17:30", { $0.startMinutes == 17 * 60 + 30 }),
      ("פגישה מ־9 עד 11 בבוקר", { $0.estimatedMinutes == 120 }), ("חופשה 3־5 במרץ", { $0.dueDayOffset == 164 }),
      // The spellings of the afternoon, of two, and of March.
      ("פגישה בשעה 1 בצהריים", { $0.startMinutes == 13 * 60 }), ("פגישה בשעה 1 בצהרים", { $0.startMinutes == 13 * 60 }),
      ("פגישה בחמש אחרי הצהריים", { $0.startMinutes == 17 * 60 }),
      ("פגישה בחמש אחר הצהרים", { $0.startMinutes == 17 * 60 }), ("פגישה בשעה שתיים", { $0.startMinutes == 14 * 60 }),
      ("פגישה בשעה שתים", { $0.startMinutes == 14 * 60 }), ("פגישה בשעה שתיים עשרה", { $0.startMinutes == 12 * 60 }),
      ("פגישה בשעה שתים עשרה", { $0.startMinutes == 12 * 60 }), ("פגישה בשעה שתים-עשרה", { $0.startMinutes == 12 * 60 }),
      ("חופשה 5 במרץ", { $0.plannedDayOffset == 164 }), ("חופשה 5 במרס", { $0.plannedDayOffset == 164 }),
      // The final letter of a word that a prefix or a suffix turns into a medial one.
      ("פגישה בעוד שבועיים", { $0.plannedDayOffset == 14 }), ("ריצה כל חודשיים", { $0.recurrence?.interval == 2 }),
      ("ריצה בן שעתיים", { $0.estimatedMinutes == 120 }),
    ]
    for line in spellings {
      #expect(line.check(parse(line.text)), "\(line.text)")
    }
    // The misspelled forms of a dual stay unread: they are words of the title.
    expectLinesUnread(
      [
        "ריצה שעתים", "ריצה כל יומים", "ריצה כל שבועים", "ריצה כל חודשים", "ריצה כל שנתים", "פגישה בעוד שבועים",
        "פגישה בעוד חודשים", "פגישה בעוד שלשה ימים",
      ], languages: ["he"])
  }

  @Test("Niqqud on a word, a prefix, or a number word changes nothing")
  func niqqud() {
    let days: [(text: String, title: String, offset: Int)] = [
      ("פגישה בְּיוֹם שֵׁנִי", "פגישה", 6), ("פגישה בְּיוֹם חֲמִישִׁי", "פגישה", 2), ("פגישה לְיוֹם שֵׁנִי", "פגישה", 6),
      ("פגישה ביוֹם שני", "פגישה", 6), ("פגישה ביום שֵׁנִי", "פגישה", 6), ("פגישה בשֵׁנִי", "פגישה", 6),
      ("פגישה ביום רִאשׁוֹן", "פגישה", 5), ("פגישה ביום שְׁלִישִׁי", "פגישה", 7), ("לקנות חלב לְמָחָר", "לקנות חלב", 1),
      ("לקנות חלב מָחָר", "לקנות חלב", 1), ("בְּעוֹד שְׁלוֹשָׁה יָמִים לְהַגִּיעַ", "לְהַגִּיעַ", 3),
      ("הַיּוֹם בָּעֶרֶב לְהַתְקַשֵּׁר", "לְהַתְקַשֵּׁר", 0), ("ללכת בְּסוֹף שָׁבוּעַ", "ללכת", 4),
      ("לשלם בְּ-5 בְּמָרְץ", "לשלם", captureDayOffset("2027-03-05")),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let times: [(text: String, title: String, minutes: Int)] = [
      ("מחר בְּ-5 בָּעֶרֶב לְהַתְקַשֵּׁר", "לְהַתְקַשֵּׁר", 17 * 60),
      ("לְהַתְקַשֵּׁר מָחָר בְּשָׁעָה חָמֵשׁ וָחֵצִי", "לְהַתְקַשֵּׁר", 17 * 60 + 30),
      ("לְהַתְקַשֵּׁר מָחָר בְּחָמֵשׁ וָחֵצִי", "לְהַתְקַשֵּׁר", 17 * 60 + 30),
      ("לְהַתְקַשֵּׁר רֶבַע לְשֵׁשׁ מָחָר", "לְהַתְקַשֵּׁר", 17 * 60 + 45),
      ("פגישה בְּיוֹם שֵׁנִי בְּשָׁעָה 5", "פגישה", 17 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let others: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("ריצה חֲצִי שָׁעָה", { $0.estimatedMinutes == 30 }), ("ריצה כְּ-30 דקות", { $0.estimatedMinutes == 30 }),
      ("ריצה לְ-30 דקות", { $0.estimatedMinutes == 30 }), ("הוצאות כָּל יוֹם שֵׁנִי", { $0.recurrence == monday }),
      ("לקחת כל יוֹם שני", { $0.recurrence == monday }), ("הוצאות כל יום ג׳", { $0.recurrence?.byDay == ["TU"] }),
      ("לשלם עַד יוֹם שִׁישִׁי", { $0.dueDayOffset == 3 }),
      ("פגישה מִיּוֹם שֵׁנִי עַד יוֹם רְבִיעִי", { $0.plannedDayOffset == 6 && $0.dueDayOffset == 8 }),
      ("עֲדִיפוּת גְּבוֹהָה לְהַתְקַשֵּׁר", { $0.priority == .p1 && $0.title == "לְהַתְקַשֵּׁר" }),
      ("לכתוב דוח עֲדִיפוּת גְּבוֹהָה", { $0.priority == .p1 }), ("להכין דוח #עֲבוֹדָה מחר", { $0.tags == ["עֲבוֹדָה"] }),
    ]
    for line in others {
      #expect(line.check(parse(line.text)), "\(line.text)")
    }
    // The title keeps its niqqud as typed.
    let typed = "לְהַתְקַשֵּׁר לְאִמָּא"
    #expect(parse("\(typed) הַיּוֹם בָּעֶרֶב").title == typed)
    // Niqqud on a word that is no detail changes nothing either.
    expectLinesUnread(["הַיּוֹם הָרִאשׁוֹן לְהַגִּיעַ", "ריצה בְּעוֹד שָׁעָה"], languages: ["he"])
  }

  @Test("The title keeps the letters, final forms, and marks as they were typed")
  func titleKeepsTypedText() {
    let typed = "לְהַתְקַשֵּׁר לאמא וגם לסבא ״בבית״ ‘שלום’ (חשוב)"
    let parsed = parse("\(typed) מחר")
    #expect(parsed.plannedDayOffset == 1)
    #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    let quoted = parse("לקרוא \"שלום עולם\" ביום ג׳")
    #expect(quoted.plannedDayOffset == 7)
    #expect(quoted.title == "לקרוא \"שלום עולם\"")
    // A final letter in a title word stays final, as the line was typed.
    #expect(parse("לשלם לדרך ביום שני").title == "לשלם לדרך")
    #expect(parse("לקנות ספרים ואוכל ביום שני").title == "לקנות ספרים ואוכל")
  }

  @Test("The full stop, comma, and colon left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("להתקשר לאמא, מחר, בשעה 5", "להתקשר לאמא"), ("להתקשר לאמא מחר, בערב", "להתקשר לאמא, בערב"),
      ("מחר, להתקשר לאמא", "להתקשר לאמא"), ("מחר: להתקשר לאמא", "להתקשר לאמא"),
      ("להתקשר לאמא - מחר", "להתקשר לאמא"), ("דוח, עד יום שישי, עדיפות גבוהה", "דוח"),
      ("חלב, לחם וביצים מחר", "חלב, לחם וביצים"), ("בוקר טוב, בשעה 12", "בוקר טוב"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The full stop, question mark, and exclamation mark end a word.
    #expect(parse("להתקשר לאמא מחר.").plannedDayOffset == 1)
    #expect(parse("להתקשר לאמא מחר!").plannedDayOffset == 1)
    #expect(parse("להתקשר לאמא מחר?").plannedDayOffset == 1)
    #expect(parse("להגיש דוח עד יום שישי.").dueDayOffset == 3)
  }

  @Test("A title never gains a bidirectional control character")
  func noBidiControls() {
    let controls: Set<UInt32> = [
      0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
    ]
    for text in [
      "להתקשר לאמא מחר בשעה 5 בערב", "דוח 12 במאי 20 דקות", "אימון כל יום שני וחמישי", "פגישה with John מחר",
      "חלב, מחר, עדיפות גבוהה #קניות", "פגישה בשעה 17:30 בערב", "לשלם עד יום שישי",
    ] {
      let title = parse(text).title
      #expect(!title.unicodeScalars.contains { controls.contains($0.value) }, "\(text)")
    }
  }

  @Test("Marks typed around a detail do not stop it from being read, and stay in the title when they were typed there")
  func bidiMarks() {
    let rlm = "\u{200F}"
    let lrm = "\u{200E}"
    // A mark between the words of a detail is part of the detail.
    let marked: [(text: String, check: (LorvexCaptureParse) -> Bool)] = [
      ("פגישה בשעה\(rlm) 5", { $0.startMinutes == 17 * 60 && $0.title == "פגישה" }),
      ("פגישה בשעה \(rlm)17:30", { $0.startMinutes == 17 * 60 + 30 && $0.title == "פגישה" }),
      ("לשלם כל\(rlm) יום שני", { $0.recurrence == monday && $0.title == "לשלם" }),
      ("לשלם כל \(rlm)יום\(rlm) שני", { $0.recurrence == monday && $0.title == "לשלם" }),
      ("לשלם עד\(rlm) יום שישי", { $0.dueDayOffset == 3 && $0.title == "לשלם" }),
      ("לשלם עדיפות\(rlm) גבוהה", { $0.priority == .p1 && $0.title == "לשלם" }),
      ("לרוץ חצי\(rlm) שעה", { $0.estimatedMinutes == 30 && $0.title == "לרוץ" }),
      ("לרוץ 30\(rlm) דקות", { $0.estimatedMinutes == 30 && $0.title == "לרוץ" }),
      ("לשלם 5\(rlm) במרץ", { $0.plannedDayOffset == 164 && $0.title == "לשלם" }),
    ]
    for line in marked {
      #expect(line.check(parse(line.text)), "\(line.text)")
    }
    // A mark that splits a word makes it another word.
    expectLinesUnread(["לשלם ב\(rlm)עוד 3 ימים"], languages: ["he"])
    // A mark typed outside a detail stays in the title, and so does an embedding around the line.
    let before = parse("להתקשר\(rlm) מחר\(rlm) בשעה 17:30")
    #expect(before.plannedDayOffset == 1)
    #expect(before.startMinutes == 17 * 60 + 30)
    #expect(before.title == "להתקשר\(rlm) \(rlm)")
    let embedded = parse("\u{202B}להתקשר מחר בשעה 5\u{202C}")
    #expect(embedded.plannedDayOffset == 1)
    #expect(embedded.startMinutes == 17 * 60)
    #expect(embedded.title == "\u{202B}להתקשר \u{202C}")
    let isolated = parse("\u{2067}להתקשר מחר\u{2069} ב-17:30")
    #expect(isolated.plannedDayOffset == 1)
    #expect(isolated.startMinutes == 17 * 60 + 30)
    // A left-to-right mark between a number and its unit is read through.
    let length = parse("לרוץ \(lrm)30\(lrm) דקות")
    #expect(length.estimatedMinutes == 30)
    // An isolate around a Latin title stays with the title.
    let latin = parse("\u{2068}Call mom\u{2069} מחר")
    #expect(latin.plannedDayOffset == 1)
    #expect(latin.title == "\u{2068}Call mom\u{2069}")
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    #expect(parse("משימה מחר").plannedDayOffset == 1)
    #expect(parse("משימה בשעה 5 בערב").startMinutes == 17 * 60)
    #expect(parse("משימה כל יום שני").recurrence == monday)
    #expect(parse("משימה 20 דקות").estimatedMinutes == 20)
    #expect(parse("משימה #רשימה").tags == ["רשימה"])
  }

  @Test("The words the app itself uses for days, repeats, and priorities are read")
  func appWords() {
    // The interface's own wording for today, tomorrow, tomorrow morning, and next week.
    #expect(parse("להתקשר לאמא היום").plannedDayOffset == 0)
    #expect(parse("להתקשר לאמא מחר").plannedDayOffset == 1)
    #expect(parse("להתקשר לאמא מחר בבוקר").plannedDayOffset == 1)
    #expect(parse("להתקשר לאמא השבוע הבא").plannedDayOffset == 7)
    #expect(parse("להתקשר לאמא הערב").plannedDayOffset == 0)
    #expect(parse("להתקשר לאמא ביום שני הבא").plannedDayOffset == 6)
    #expect(parse("להתקשר לאמא בסוף השבוע הזה").plannedDayOffset == 4)
    // Its repeat and priority names.
    #expect(parse("להתקשר לאמא כל יום").recurrence == daily)
    #expect(parse("להתקשר לאמא כל שבוע").recurrence == weeklyRule)
    #expect(parse("להתקשר לאמא כל חודש").recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(parse("להתקשר לאמא כל שנה").recurrence == TaskRecurrenceRule(freq: .yearly))
    #expect(parse("להתקשר לאמא עדיפות גבוהה").priority == .p1)
    #expect(parse("להתקשר לאמא עדיפות רגילה").priority == .p2)
    #expect(parse("להתקשר לאמא עדיפות נמוכה").priority == .p3)
    // The reminder preset "in an hour" names no day.
    expectLinesUnread(["להתקשר לאמא בעוד שעה"], languages: ["he"])
  }

  // MARK: - Beside other languages

  @Test("Beside Hebrew, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "he"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "he"]).estimatedMinutes == 20)
    #expect(parse("דוח 2h").estimatedMinutes == 120)
    #expect(parse("דוח 30min").estimatedMinutes == 30)
    #expect(parse("דוח 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "he"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "he"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "he"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "he"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times.
    #expect(parse("פגישה 5pm").startMinutes == 17 * 60)
    #expect(parse("פגישה 5 PM").startMinutes == 17 * 60)
    #expect(parse("פגישה 17:30").startMinutes == 17 * 60 + 30)
    // English lines read the same with Hebrew beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "he"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom מחר at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting ביום שישי at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("פגישה tomorrow בשעה 5")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "פגישה")
    let hebrewTitle = parse("פגישה next friday")
    #expect(hebrewTitle.plannedDayOffset == 10)
    #expect(hebrewTitle.title == "פגישה")
    let names: [(text: String, title: String)] = [
      ("פגישה עם John מחר ב-3pm", "פגישה עם John"), ("Meeting with דנה tomorrow 5pm", "Meeting with דנה"),
      ("review PR מחר 30 min", "review PR"), ("לשלוח email ל-Dana מחר", "לשלוח email ל-Dana"),
      ("לקנות iPhone 16 ביום שני", "לקנות iPhone 16"), ("להתקשר ל-Boss ב-17:30", "להתקשר ל-Boss"),
      ("להכין deck !! מחר", "להכין deck"), ("להכין deck p1 מחר", "להכין deck"),
    ]
    for line in names {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    #expect(parse("לרוץ 2h").estimatedMinutes == 120)
    #expect(parse("לרוץ for 2h מחר").estimatedMinutes == 120)
    #expect(parse("לבדוק ב-9am").startMinutes == 9 * 60)
    let every = parse("להתקשר לאמא every monday")
    #expect(every.recurrence == monday)
    #expect(every.title == "להתקשר לאמא")
  }

  @Test("Hebrew words are read only for a user who reads Hebrew")
  func languageGate() {
    let line = parse("להתקשר לאמא מחר", languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == "להתקשר לאמא מחר")
    for languages in [["he"], ["he-IL"], ["he_IL"], ["en-US", "he-IL"], ["HE"], ["he-Hebr-IL"], ["ar", "he"], ["fr", "he"]] {
      #expect(parse("להתקשר לאמא מחר", languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages' readers do not get Hebrew words, even the ones whose scripts are near.
    for languages in [["ar"], ["fa"], ["ur"], ["hi"], ["ru"], ["ja"], ["yi"]] {
      #expect(parse("להתקשר לאמא מחר", languages: languages).plannedDayOffset == nil, "\(languages)")
    }
    // Hebrew readers do not get other languages' words.
    #expect(parse("اتصل بأمي غداً", languages: ["he"]).plannedDayOffset == nil)
    #expect(parse("تماس با مادر فردا", languages: ["he"]).plannedDayOffset == nil)
    #expect(parse("माँ को फोन करें कल", languages: ["he"]).plannedDayOffset == nil)
    #expect(parse("Позвонить завтра", languages: ["he"]).plannedDayOffset == nil)
    #expect(parse("Appeler maman demain", languages: ["he"]).plannedDayOffset == nil)
    // A clock time, a repeat, a length, and a priority with a Hebrew word need Hebrew among the languages.
    #expect(parse("פגישה בשעה 5 בערב", languages: ["en"]).startMinutes == nil)
    #expect(parse("לקחת תרופה כל יום שני", languages: ["en"]).recurrence == nil)
    #expect(parse("לכתוב דוח עדיפות גבוהה", languages: ["en"]).priority == nil)
    #expect(parse("לכתוב דוח 30 דקות", languages: ["en"]).estimatedMinutes == nil)
    // English and Chinese are read whatever the languages.
    #expect(parse("Call mom tomorrow", languages: ["he"]).plannedDayOffset == 1)
    #expect(parse("明天打电话", languages: ["he"]).plannedDayOffset == 1)
    #expect(parse("买牛奶 מחר", languages: ["he"]).plannedDayOffset == 1)
    #expect(parse("明天 לקנות חלב", languages: ["he", "zh"]).plannedDayOffset == 1)
    // Hebrew with Arabic, Persian, or Urdu readers get both.
    #expect(parse("اتصل بأمي غداً", languages: ["he", "ar"]).plannedDayOffset == 1)
    #expect(parse("להתקשר לאמא מחר", languages: ["he", "ar"]).plannedDayOffset == 1)
    #expect(parse("تماس با مادر فردا", languages: ["he", "fa"]).plannedDayOffset == 1)
    #expect(parse("امی کو فون کرنا کل", languages: ["he", "ur"]).plannedDayOffset == 1)
    #expect(parse("להתקשר לאמא מחר", languages: ["he", "ur"]).plannedDayOffset == 1)
  }

  @Test("Lines in other languages read the same with Hebrew beside them")
  func besideOtherLanguages() {
    let lines: [(text: String, language: String)] = [
      ("اتصل بأمي غداً الساعة 3 مساءً", "ar"), ("اجتماع كل اثنين لمدة ساعة", "ar"), ("تقرير قبل الخميس", "ar"),
      ("مراجعة من 3 إلى 5 مارس", "ar"), ("تماس با مادر فردا ساعت ۳ بعدازظهر", "fa"), ("ورزش هر دوشنبه", "fa"),
      ("گزارش تا جمعه", "fa"), ("امی کو فون کرنا کل شام 5 بجے", "ur"), ("رپورٹ جمعہ تک", "ur"),
      ("कल शाम 5 बजे मीटिंग", "hi"), ("रिपोर्ट सोमवार तक", "hi"), ("हर सोमवार योग 30 मिनट", "hi"),
      ("Позвонить маме завтра в 15:00", "ru"), ("Appeler maman demain à 15h", "fr"),
      ("Llamar a mamá mañana a las 15:00", "es"), ("明日の午後3時に会議", "ja"), ("Zadzwonić jutro o 15:00", "pl"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "he"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["he", line.language]) == alone, "\(line.text): reversed")
    }
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    let unit: [(token: String, repeats: Int)] = [
      ("בשעה 5 ", 400), ("כל יום שני ו", 250), ("מ-3 ", 400), ("שעתיים ו", 350), ("וחצי ", 300), ("5", 3000),
      ("א", 3000), ("מחר", 600), ("ב", 1000), ("עד ", 900), ("שבוע ", 500), ("בשבוע הבא ", 200),
      ("אחר הצהריים ", 300), ("כל ", 900), ("12 במאי ", 300), ("חצי שעה ", 300), (", ", 1500), ("ו", 1500),
      ("ל\u{05B0}", 2000), ("ה\u{200F}", 2000), ("-", 3000), ("כל בוקר ", 300), ("של ", 1500),
      ("בין ", 600), ("שני ", 800), ("בראשון ", 400),
    ]
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for entry in unit {
        let line = "אמא " + String(repeating: entry.token, count: entry.repeats) + " טלפון"
        let parsed = parse(line)
        #expect(!parsed.title.isEmpty, "\(entry.token)")
      }
    }
    #expect(elapsed < .seconds(60), "the long lines took \(elapsed)")
  }
}
