import Foundation
import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String, languages: [String] = ["ta"]) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: languages)
}

/// A line read on another day: `weekday` is that day's weekday (1 = Sunday)
/// and `today` its date.
private func parse(_ text: String, weekday: Int, today: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: weekday, today: today, languages: ["ta"])
}

/// `text` with its ASCII digits written in the Tamil script (U+0BE6-U+0BEF).
private func tamilDigits(_ text: String) -> String {
  var scalars = String.UnicodeScalarView()
  for scalar in text.unicodeScalars {
    if (0x30...0x39).contains(scalar.value), let digit = Unicode.Scalar(0x0BE6 + scalar.value - 0x30) {
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

/// Tamil capture lines, read for a user whose languages include Tamil.
@Suite("Capture parser Tamil")
struct CaptureParserTamilTests {
  // MARK: - Days

  @Test("Days: today, tomorrow, the day after, and a number of days, weeks, or months")
  func days() {
    let line = parse("அம்மாவை அழை நாளை")
    #expect(line.plannedDayOffset == 1)
    #expect(line.dueDayOffset == nil)
    #expect(line.title == "அம்மாவை அழை")
    #expect(line.phrases.map(\.text) == ["நாளை"])
    #expect(line.phrases.map(\.kind) == [.when])

    let days: [(text: String, offset: Int)] = [
      ("இன்று", 0), ("இன்றே", 0), ("இன்றைக்கு", 0), ("இன்றைக்கே", 0), ("இன்னைக்கு", 0), ("இன்னிக்கு", 0),
      ("இன்றிலிருந்து", 0), ("இன்றிரவு", 0), ("இன்றிரவே", 0), ("இன்றிரவுக்கு", 0), ("நாளை", 1), ("நாளையே", 1),
      ("நாளைக்கு", 1), ("நாளைக்கே", 1), ("நாளை முதல்", 1), ("நாளையிலிருந்து", 1), ("நாளை மறுநாள்", 2),
      ("நாளைமறுநாள்", 2), ("நாளை மறுநாளே", 2), ("நாளை மறுநாளுக்கு", 2), ("நாளை மறுதினம்", 2), ("3 நாட்களில்", 3),
      ("3 நாளில்", 3), ("மூன்று நாட்களில்", 3), ("பத்து நாட்களில்", 10), ("3 நாட்கள் கழித்து", 3),
      ("10 நாட்களுக்குப் பிறகு", 10), ("10 நாட்களுக்கு பிறகு", 10), ("ஒரு நாள் கழித்து", 1), ("1 நாள் கழித்து", 1),
      ("2 வாரங்களில்", 14), ("இரண்டு வாரங்களில்", 14), ("ஒரு வாரம் கழித்து", 7), ("1 வாரம் கழித்து", 7),
      ("ஒரு மாதத்தில்", 30), ("1 மாதம் கழித்து", 30), ("2 மாதங்களில்", 61), ("இரண்டு மாதங்கள் கழித்து", 61),
      ("அடுத்த வாரம்", 7), ("வரும் வாரம்", 7), ("வருகிற வாரம்", 7), ("அடுத்த வாரத்தில்", 7),
      ("அடுத்த வாரத்திற்கு", 7),
    ]
    for day in days {
      let text = "அம்மாவை அழை \(day.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == day.offset, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
      #expect(parsed.title == "அம்மாவை அழை", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    // A line that opens with its day keeps the rest as the title.
    let opening = parse("நாளை அம்மாவை அழை")
    #expect(opening.plannedDayOffset == 1)
    #expect(opening.title == "அம்மாவை அழை")
  }

  @Test("A part of the day after a day belongs to it, and sets the hour of a bare time")
  func partsOfDay() {
    let phrases: [(text: String, offset: Int)] = [
      ("இன்று காலை", 0), ("இன்று மதியம்", 0), ("இன்று மாலை", 0), ("இன்று இரவு", 0), ("இந்த காலை", 0),
      ("இந்த மதியம்", 0), ("இந்த மாலை", 0), ("இந்த இரவு", 0), ("இந்தக் காலை", 0), ("நாளை காலை", 1),
      ("நாளைக் காலை", 1), ("நாளை காலையில்", 1), ("நாளை அதிகாலை", 1), ("நாளை மதியம்", 1), ("நாளை மாலை", 1),
      ("நாளை சாயங்காலம்", 1), ("நாளை இரவு", 1), ("நாளை ராத்திரி", 1), ("நாளை மறுநாள் காலை", 2),
      ("வெள்ளிக்கிழமை மாலை", 3), ("வெள்ளிக்கிழமை இரவு", 3), ("சனிக்கிழமை காலை", 4),
    ]
    for phrase in phrases {
      let text = "அம்மாவை அழை \(phrase.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == phrase.offset, "\(phrase.text)")
      #expect(parsed.title == "அம்மாவை அழை", "\(phrase.text): title")
      #expect(parsed.phrases.map(\.text) == [phrase.text], "\(phrase.text): phrase")
    }
    // The part of the day in the line's day phrase names the half of the day
    // of a bare hour written elsewhere.
    let morning = parse("நாளை காலை கூட்டம் 6 மணிக்கு")
    #expect(morning.plannedDayOffset == 1)
    #expect(morning.startMinutes == 6 * 60)
    #expect(morning.title == "கூட்டம்")
    let evening = parse("இன்று மாலை ஜிம் 7 மணிக்கு")
    #expect(evening.plannedDayOffset == 0)
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "ஜிம்")
    let night = parse("நாளை இரவு உணவு 9 மணிக்கு")
    #expect(night.plannedDayOffset == 1)
    #expect(night.startMinutes == 21 * 60)
    #expect(night.title == "உணவு")
    let written = parse("இன்று இரவு 8 மணிக்கு உணவு")
    #expect(written.plannedDayOffset == 0)
    #expect(written.startMinutes == 20 * 60)
    #expect(written.title == "உணவு")
    // The part of the day as a noun or alone names no day.
    expectLinesUnread(
      [
        "காலை நடை", "மாலை தேநீர்", "இரவு உணவு", "மதிய உணவு", "இரவு மருந்து சாப்பிடு", "மாலைத் தேநீர்", "அதிகாலை நடை",
      ], languages: ["ta"])
    // The form of a part of the day before a noun is no part of a day phrase:
    // only the day is read.
    let lunch = parse("நாளை மதிய உணவு")
    #expect(lunch.plannedDayOffset == 1)
    #expect(lunch.title == "மதிய உணவு")
    let tea = parse("நாளை மறுநாள் சாயங்கால தேநீர்")
    #expect(tea.plannedDayOffset == 2)
    #expect(tea.title == "சாயங்கால தேநீர்")
  }

  @Test("An ending that goes with a day is read with it, and any other ending leaves the day unread")
  func dayEndings() {
    let days: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("இன்றே அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 0, "இன்றே"),
      ("அறிக்கையை அனுப்பு நாளையே", "அறிக்கையை அனுப்பு", 1, "நாளையே"),
      ("நாளைக்கு அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 1, "நாளைக்கு"),
      ("நாளைக்கே அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 1, "நாளைக்கே"),
      ("திங்கட்கிழமைக்கு அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 6, "திங்கட்கிழமைக்கு"),
      ("திங்கட்கிழமையே கூட்டம்", "கூட்டம்", 6, "திங்கட்கிழமையே"),
      ("திங்கட்கிழமையன்று கூட்டம்", "கூட்டம்", 6, "திங்கட்கிழமையன்று"),
      ("திங்கட்கிழமையில் கூட்டம்", "கூட்டம்", 6, "திங்கட்கிழமையில்"),
      ("திங்கட்கிழமை அன்று கூட்டம்", "கூட்டம்", 6, "திங்கட்கிழமை அன்று"),
      ("திங்கள் அன்று கூட்டம்", "கூட்டம்", 6, "திங்கள் அன்று"),
      ("திங்களன்று கூட்டம்", "கூட்டம்", 6, "திங்களன்று"),
      ("திங்களுக்கு கூட்டம்", "கூட்டம்", 6, "திங்களுக்கு"),
      ("அறிக்கையை அனுப்பு இன்று", "அறிக்கையை அனுப்பு", 0, "இன்று"),
    ]
    for line in days {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // An ending the vocabulary does not list leaves the day word unread, and so
    // does the genitive and the adjective of a day: "இன்றைய செய்திகள்" is
    // today's news.
    expectLinesUnread(
      [
        "இன்றைய செய்திகள்", "நாளைய கூட்டம்", "திங்கட்கிழமையின் கூட்டம்", "வெள்ளிக்கிழமையின் விருந்து",
        "சனிக்கிழமைக்கான விருந்து", "திங்கட்கிழமையை விடுமுறையாக்கு", "இந்த நாட்களில் ஃபோன் பயன்பாடு",
        "அந்த நாள் கூட்டம்",
      ], languages: ["ta"])
    // "க்குள்" is a deadline ending.
    #expect(parse("அறிக்கையை அனுப்பு வெள்ளிக்கிழமைக்குள்").dueDayOffset == 3)
  }

  @Test("முதல் after a day plans it, unless it starts a counted day")
  func fromAfterDay() {
    let lines: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("இன்று முதல் உடற்பயிற்சி தொடங்கு", "உடற்பயிற்சி தொடங்கு", 0, "இன்று முதல்"),
      ("நாளை முதல் ஜிம் தொடக்கம்", "ஜிம் தொடக்கம்", 1, "நாளை முதல்"),
      ("நாளையிலிருந்து ஜிம் தொடக்கம்", "ஜிம் தொடக்கம்", 1, "நாளையிலிருந்து"),
      ("திங்கள் முதல் ஜிம் தொடக்கம்", "ஜிம் தொடக்கம்", 6, "திங்கள் முதல்"),
      ("திங்கட்கிழமை முதல் வகுப்புகள்", "வகுப்புகள்", 6, "திங்கட்கிழமை முதல்"),
      ("15 அக்டோபர் முதல் வகுப்புகள்", "வகுப்புகள்", 23, "15 அக்டோபர் முதல்"),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // The "முதல்" or "இருந்து" of a counted day ties the amount to another event.
    expectLinesUnread(
      [
        "இன்று முதல் 3 நாட்களுக்குப் பிறகு வேலை", "திங்கள் முதல் 2 வாரங்களுக்குப் பிறகு வேலை",
        "நாளை முதல் 3 நாட்களில் வேலை", "கூட்டம் முடிந்த 3 நாட்களுக்குப் பிறகு அழை",
        "கூட்டத்திலிருந்து 3 நாட்களுக்குப் பிறகு அழை", "கூட்டத்தில் இருந்து 3 நாட்கள் கழித்து அழை",
      ], languages: ["ta"])
    // The amount after a day that does not start a counted day stays in the title.
    let counted = parse("நாளை முதல் 3 நாட்கள் ஜிம்")
    #expect(counted.plannedDayOffset == 1)
    #expect(counted.title == "3 நாட்கள் ஜிம்")
    // A day from another day to a deadline reads as a plan and a deadline.
    let leave = parse("இன்று முதல் நாளை வரை விடுமுறை")
    #expect(leave.plannedDayOffset == 0)
    #expect(leave.dueDayOffset == 1)
    #expect(leave.title == "விடுமுறை")
  }

  @Test("Weekdays: the next one, this week's, and next week's")
  func weekdays() {
    // Today is Tuesday, so a bare Tuesday is a week ahead and "இந்த செவ்வாய்க்கிழமை" is today.
    let weekdays: [(long: String, bare: String, dative: String, onThe: String, abbreviation: String?, offset: Int)] = [
      ("ஞாயிற்றுக்கிழமை", "ஞாயிறு", "ஞாயிற்றுக்கு", "ஞாயிறன்று", "ஞாயி.", 5),
      ("திங்கட்கிழமை", "திங்கள்", "திங்களுக்கு", "திங்களன்று", "திங்.", 6),
      ("செவ்வாய்க்கிழமை", "செவ்வாய்", "செவ்வாய்க்கு", "செவ்வாயன்று", "செவ்.", 7),
      ("புதன்கிழமை", "புதன்", "புதனுக்கு", "புதனன்று", "புத.", 1),
      ("வியாழக்கிழமை", "வியாழன்", "வியாழனுக்கு", "வியாழனன்று", "வியா.", 2),
      ("வெள்ளிக்கிழமை", "வெள்ளி", "வெள்ளிக்கு", "வெள்ளியன்று", "வெள்.", 3),
      ("சனிக்கிழமை", "சனி", "சனிக்கு", "சனியன்று", nil, 4),
    ]
    for weekday in weekdays {
      var forms = [weekday.long, weekday.bare, weekday.dative, weekday.onThe, "\(weekday.bare) அன்று"]
      for ending in ["க்கு", "யே", "யன்று", "யில்", " அன்று"] { forms.append(weekday.long + ending) }
      if let abbreviation = weekday.abbreviation { forms.append(abbreviation) }
      for form in forms {
        let text = "அம்மாவை அழை \(form)"
        let parsed = parse(text)
        #expect(parsed.plannedDayOffset == weekday.offset, "\(text)")
        #expect(parsed.recurrence == nil, "\(text): repeat")
        #expect(parsed.title == "அம்மாவை அழை", "\(text): title")
      }
    }
    // Other spellings of the long names.
    let spellings: [(text: String, offset: Int)] = [
      ("திங்கள்கிழமை", 6), ("ஞாயிறுக்கிழமை", 5), ("வியாழன்கிழமை", 2), ("வெள்ளி கிழமை", 3),
    ]
    for spelling in spellings {
      #expect(parse("அம்மாவை அழை \(spelling.text)").plannedDayOffset == spelling.offset, "\(spelling.text)")
    }
    let modified: [(text: String, offset: Int)] = [
      ("இந்த வெள்ளிக்கிழமை", 3), ("இந்த செவ்வாய்க்கிழமை", 0), ("இந்த சனிக்கிழமை", 4), ("இந்த திங்கட்கிழமை", 6),
      ("வரும் வெள்ளிக்கிழமை", 3), ("வரும் செவ்வாய்க்கிழமை", 7), ("வரும் திங்கட்கிழமை", 6),
      ("வருகிற வெள்ளிக்கிழமை", 3), ("வருகிற திங்கட்கிழமை", 6), ("அடுத்த திங்கட்கிழமை", 6),
      ("அடுத்த செவ்வாய்க்கிழமை", 7), ("அடுத்த புதன்கிழமை", 8), ("அடுத்த வெள்ளிக்கிழமை", 10),
      ("அடுத்த சனிக்கிழமை", 11), ("அடுத்த ஞாயிற்றுக்கிழமை", 12), ("இந்த வாரம் வெள்ளிக்கிழமை", 3),
      ("இந்த வாரம் செவ்வாய்க்கிழமை", 0), ("வரும் வாரம் திங்கட்கிழமை", 6), ("வரும் வாரம் வெள்ளிக்கிழமை", 10),
      ("வருகிற வாரம் வெள்ளிக்கிழமை", 10), ("அடுத்த வாரம் வெள்ளிக்கிழமை", 10), ("அடுத்த வாரம் திங்கள்", 6),
      ("அடுத்த வாரம் வெள்ளிக்கிழமை மாலை", 10), ("வெள்ளிக்கிழமை முதல்", 3), ("அடுத்த வெள்ளிக்கிழமை முதல்", 10),
    ]
    for line in modified {
      let text = "அம்மாவை அழை \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "அம்மாவை அழை", "\(text): title")
      #expect(parsed.phrases.count == 1, "\(text): phrases")
    }
    let opening = parse("வெள்ளிக்கிழமை அம்மாவை அழை")
    #expect(opening.plannedDayOffset == 3)
    #expect(opening.title == "அம்மாவை அழை")
    // "இந்த வாரம்" alone names no single day.
    expectLinesUnread(["அம்மாவை அழை இந்த வாரம்", "இந்த வாரம் அறிக்கை"], languages: ["ta"])
  }

  @Test("The weekend: this one, next week's, and today when it is already here")
  func weekend() {
    for text in [
      "வார இறுதி", "வார இறுதியில்", "வார இறுதிக்கு", "இந்த வார இறுதி", "இந்த வார இறுதியில்", "வரும் வார இறுதி",
      "வருகிற வார இறுதியில்", "வாரயிறுதி", "வாரஇறுதி", "வீக்கெண்ட்", "வீக்கெண்டில்", "வீக்கெண்டுக்கு",
      "வீக்கெண்ட்\u{200C}இல்", "சனிக்கிழமை மற்றும் ஞாயிற்றுக்கிழமை", "சனிக்கிழமை, ஞாயிற்றுக்கிழமை",
      "சனிக்கிழமை & ஞாயிற்றுக்கிழமை", "சனி ஞாயிறு", "சனி, ஞாயிறு", "சனி-ஞாயிறு", "சனி மற்றும் ஞாயிறு",
    ] {
      let parsed = parse("அம்மாவை அழை \(text)")
      #expect(parsed.plannedDayOffset == 4, "\(text)")
      #expect(parsed.title == "அம்மாவை அழை", "\(text): title")
    }
    for text in ["அடுத்த வார இறுதி", "அடுத்த வார இறுதியில்"] {
      #expect(parse("அம்மாவை அழை \(text)").plannedDayOffset == 11, "\(text)")
    }
    // On a Saturday or a Sunday the weekend is already here.
    #expect(parse("அம்மாவை அழை வார இறுதியில்", weekday: 7, today: "2026-09-26").plannedDayOffset == 0)
    #expect(parse("அம்மாவை அழை வார இறுதியில்", weekday: 1, today: "2026-09-27").plannedDayOffset == 0)
    #expect(parse("அம்மாவை அழை வார இறுதியில்", weekday: 6, today: "2026-09-25").plannedDayOffset == 1)
    #expect(parse("அம்மாவை அழை அடுத்த வார இறுதியில்", weekday: 7, today: "2026-09-26").plannedDayOffset == 7)
  }

  // MARK: - Dates

  @Test("Written dates: every month, in the spellings people type, with a year, a label, an ending, and a weekday")
  func writtenDates() {
    // 2026-09-22 is today: a date that has passed this year is next year's.
    let dates: [(text: String, date: String)] = [
      ("5 ஜனவரி", "2027-01-05"), ("5 பிப்ரவரி", "2027-02-05"), ("5 பெப்ரவரி", "2027-02-05"),
      ("5 பிப்ருவரி", "2027-02-05"), ("5 மார்ச்", "2027-03-05"), ("5 மார்ச்சு", "2027-03-05"),
      ("5 ஏப்ரல்", "2027-04-05"), ("5 ஏப்ரில்", "2027-04-05"), ("5 மே", "2027-05-05"), ("5 ஜூன்", "2027-06-05"),
      ("5 ஜுன்", "2027-06-05"), ("5 ஜூலை", "2027-07-05"), ("5 ஜுலை", "2027-07-05"), ("5 ஆகஸ்ட்", "2027-08-05"),
      ("5 ஆகஸ்டு", "2027-08-05"), ("5 ஆகஸ்ட்டு", "2027-08-05"), ("5 செப்டம்பர்", "2027-09-05"),
      ("5 செப்டெம்பர்", "2027-09-05"), ("5 அக்டோபர்", "2026-10-05"), ("5 நவம்பர்", "2026-11-05"),
      ("5 டிசம்பர்", "2026-12-05"), ("22 செப்டம்பர்", "2026-09-22"), ("5 ஜன.", "2027-01-05"),
      ("5 பிப்.", "2027-02-05"), ("5 மார்.", "2027-03-05"), ("5 ஏப்.", "2027-04-05"), ("5 ஆக.", "2027-08-05"),
      ("5 செப்.", "2027-09-05"), ("5 அக்.", "2026-10-05"), ("5 நவ.", "2026-11-05"), ("5 டிச.", "2026-12-05"),
      ("5 அக்டோபர் மாதம்", "2026-10-05"), ("5 அக்டோபர் அன்று", "2026-10-05"), ("5 அக்டோபர் முதல்", "2026-10-05"),
      ("5 மே 2027", "2027-05-05"), ("5 மே 2028", "2028-05-05"), ("5 மே, 2028", "2028-05-05"),
      ("15 அக்டோபர், 2026", "2026-10-15"), ("15 அக்., 2026", "2026-10-15"), ("15ஆம் தேதி அக்டோபர்", "2026-10-15"),
      ("15ஆம் தேதி அக்டோபர் 2026", "2026-10-15"), ("தேதி 5 மே", "2027-05-05"), ("தேதி: 5 மே", "2027-05-05"),
      ("திங்கள், 5 அக்டோபர்", "2026-10-05"), ("திங்கட்கிழமை 5 அக்டோபர்", "2026-10-05"),
      ("5 அக்டோபர், திங்கள்", "2026-10-05"), ("15 அக்டோபர் 2026, வியாழன்", "2026-10-15"),
      ("வியா., 15 அக்.", "2026-10-15"), ("அக்டோபர் 15", "2026-10-15"), ("அக்டோபர் 15, 2026", "2026-10-15"),
      ("அக்டோபர் 15ஆம் தேதி", "2026-10-15"), ("அக்டோபர் மாதம் 15ஆம் தேதி", "2026-10-15"),
      ("அக். 15", "2026-10-15"), ("ஜனவரி 20", "2027-01-20"), ("மே 5", "2027-05-05"),
      ("அக்டோபர் 15க்கு", "2026-10-15"), ("அக்டோபர் 15இல்", "2026-10-15"), ("15ஆம் தேதி", "2026-10-15"),
      ("5ஆம் தேதி", "2026-10-05"), ("15 தேதி", "2026-10-15"), ("15ம் தேதி", "2026-10-15"),
      ("15-ஆம் தேதி", "2026-10-15"), ("15வது தேதி", "2026-10-15"), ("15ஆவது தேதி", "2026-10-15"),
      ("15ஆம் தேதியன்று", "2026-10-15"), ("15ஆம் தேதியில்", "2026-10-15"), ("15ஆம் தேதிக்கு", "2026-10-15"),
      ("15ஆம் தேதி அன்று", "2026-10-15"), ("15/10/2026", "2026-10-15"), ("15.10.2026", "2026-10-15"),
      ("15-10-2026", "2026-10-15"), ("15.10.", "2026-10-15"), ("தேதி 15/10", "2026-10-15"),
      ("தேதி 15.10", "2026-10-15"), ("15/10க்கு", "2026-10-15"), ("15/10இல்", "2026-10-15"),
      ("15/10 அன்று", "2026-10-15"), ("15/10 முதல்", "2026-10-15"),
    ]
    for line in dates {
      let text = "அம்மாவை அழை \(line.text)"
      let parsed = parse(text)
      #expect(parsed.plannedDayOffset == captureDayOffset(line.date), "\(text)")
      #expect(parsed.title == "அம்மாவை அழை", "\(text): title")
      #expect(parsed.phrases.map(\.text) == [line.text], "\(text): phrase")
    }
  }

  @Test("A month needs its day beside it, and a short month needs its period")
  func unreadDates() {
    expectLinesUnread(
      [
        // The months of the Tamil calendar are not Gregorian dates.
        "அம்மாவை அழை 5 ஆடி", "பூஜை 10 கார்த்திகை", "அம்மாவை அழை 15 மார்கழி",
        // A month alone, and a short month with no period.
        "விடுமுறை மே மாதத்தில்", "மார்ச் மாத விடுமுறை", "அம்மாவை அழை 5 ஜன", "அம்மாவை அழை 5 ஆக",
        "அம்மாவை அழை ஜன 20", "அம்மாவை அழை ஆக 20", "அம்மாவை அழை 5 ஆகட்டும்",
        // A month before a count of things, and a day the month does not have.
        "அக்டோபர் 15 ரூபாய்", "அக்டோபர் 15 பேர்", "அம்மாவை அழை 31 ஏப்ரல்", "அம்மாவை அழை 30 பிப்ரவரி",
        "அம்மாவை அழை 32 மே",
        // Digits only, with no label and no ending.
        "அம்மாவை அழை 5/10", "அம்மாவை அழை 5.10", "அம்மாவை அழை 15-10", "அம்மாவை அழை 15/10",
      ], languages: ["ta"])
    // A full month name before its day is a date.
    #expect(parse("விடுமுறை மே 5").plannedDayOffset == captureDayOffset("2027-05-05"))
  }

  @Test("Date ranges: the first day is planned and the last is due")
  func dateRanges() {
    expectDateRanges(
      [
        ("விடுமுறை", "3 முதல் 5 மார்ச்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 முதல் 5 மார்ச் வரை", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 முதல் 5 மார்ச் வரைக்கும்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 முதல் 5 மார்ச் வரையில்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "மார்ச் 3 முதல் 5 வரை", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 மார்ச் முதல் 5 மார்ச்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 மார்ச் முதல் 5 மார்ச் வரை", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "30 ஜனவரி முதல் 2 பிப்ரவரி வரை", "2027-01-30", "2027-02-02"),
        ("விடுமுறை", "3-5 மார்ச்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3–5 மார்ச்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "மார்ச் 3-5", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 மார்ச் - 5 மார்ச்", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 முதல் 5 மார்ச் 2027", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3ஆம் தேதி முதல் 5ஆம் தேதி மார்ச் வரை", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "3 மார்ச் முதல் 5 ஜூலை வரை", "2027-03-03", "2027-07-05"),
        ("விடுமுறை", "அக்டோபர் 3 முதல் 5 வரை", "2026-10-03", "2026-10-05"),
        ("குடும்பத்துடன் விடுமுறை", "3 முதல் 5 மார்ச் வரை", "2027-03-03", "2027-03-05"),
        ("விடுமுறை", "25 செப்டம்பர் முதல் 3 அக்டோபர் வரை", "2026-09-25", "2026-10-03"),
        ("விடுமுறை", "30 டிசம்பர் முதல் 2 ஜனவரி வரை", "2026-12-30", "2027-01-02"),
        ("மாநாடு", "12-14 அக்டோபர்", "2026-10-12", "2026-10-14"),
      ], languages: ["ta"])
  }

  @Test("A range whose end is not after its start, or that names no month, stays in the title")
  func declinedRanges() {
    expectLinesUnread(
      [
        "விடுமுறை 5 முதல் 3 மார்ச்", "விடுமுறை 3 மார்ச் முதல் 3 மார்ச்", "விடுமுறை 5-3 மார்ச்",
        "விடுமுறை 5 மார்ச் முதல் 3 மார்ச்",
        // Days of the month with no month are no range: two bare numbers are hours or amounts.
        "விடுமுறை 3 முதல் 5",
        // A range in the past may be an event the task only prepares for.
        "3 முதல் 5 மார்ச் வரை பயணம் சென்றோம்", "பயணம் சென்றோம் 3 மார்ச் முதல் 5 மார்ச் வரை",
        // A letter or sign glued to the end that is not க்கு or இல் makes it another word.
        "விடுமுறை 3 முதல் 5 மார்ச்சில்", "விடுமுறை 3 முதல் 5 மார்ச்சை",
      ], languages: ["ta"])
  }

  @Test("A day alone opens a range joined by a spaced dash only when the dash touches both sides")
  func spacedDash() {
    let sprint = parse("Sprint 12 - 20 மார்ச்")
    #expect(sprint.title == "Sprint 12")
    #expect(sprint.plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(sprint.dueDayOffset == nil)
    expectDateRanges([("Sprint", "12-20 மார்ச்", "2027-03-12", "2027-03-20")], languages: ["ta"])
  }

  @Test("A range takes both days, so another day phrase stays in the title")
  func rangeTakesBothDays() {
    let line = parse("விடுமுறை 3 முதல் 5 மார்ச் நாளை")
    #expect(line.plannedDayOffset == captureDayOffset("2027-03-03"))
    #expect(line.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(line.title == "விடுமுறை நாளை")
    let timed = parse("விடுமுறை 3 முதல் 5 மார்ச் மாலை 6 மணிக்கு")
    #expect(timed.dueDayOffset == captureDayOffset("2027-03-05"))
    #expect(timed.startMinutes == 18 * 60)
    #expect(timed.title == "விடுமுறை")
  }

  @Test("A span of weekdays plans the coming first day and is due on the last day after it")
  func weekdaySpans() {
    // On this Tuesday the coming Wednesday comes before the coming Monday, so
    // the span ends on the Wednesday after the Monday.
    let span = parse("அறிக்கை திங்கள் முதல் புதன் வரை")
    #expect(span.plannedDayOffset == 6)
    #expect(span.dueDayOffset == 8)
    #expect(span.title == "அறிக்கை")
    #expect(span.phrases.map(\.text) == ["திங்கள் முதல் புதன் வரை"])
    let spans: [(text: String, planned: Int, due: Int)] = [
      ("பயணம் வெள்ளி முதல் திங்கள் வரை", 3, 6), ("பயணம் சனி முதல் ஞாயிறு வரை", 4, 5),
      ("பயணம் வெள்ளிக்கிழமை முதல் ஞாயிற்றுக்கிழமை", 3, 5), ("பயணம் வெள்ளி முதல் ஞாயிறு வரைக்கும்", 3, 5),
      // Today's weekday opens next week's span, as a weekday alone does.
      ("முகாம் செவ்வாய் முதல் வியாழன் வரை", 7, 9), ("முகாம் புதன் முதல் வெள்ளி வரை", 1, 3),
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
        "ஜிம் திங்கள் முதல் வெள்ளி வரை", "பயிற்சி திங்கள் முதல் வெள்ளி",
        "பயிற்சி திங்கட்கிழமை முதல் வெள்ளிக்கிழமை வரை",
      ], languages: ["ta"])
    // A span in the past, or one that "யிலான" follows, is no plan.
    expectLinesUnread(
      ["திங்கள் முதல் புதன் வரையிலான விடுமுறை", "திங்கள் முதல் புதன் வரை பயணம் சென்றோம்"], languages: ["ta"])
  }

  // MARK: - Due days

  @Test("Due days: வரை, க்குள், and the labels காலக்கெடு and டெட்லைன்")
  func dueDays() {
    let due: [(text: String, title: String, offset: Int)] = [
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரைக்கும்", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரையில்", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமைக்குள்", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமைக்குள்ளாக", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்குள்", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளி வரை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு திங்களுக்குள்", "அறிக்கையை அனுப்பு", 6),
      ("அறிக்கையை அனுப்பு திங்கள் வரை", "அறிக்கையை அனுப்பு", 6),
      ("அறிக்கையை அனுப்பு செவ்வாய்க்கிழமை வரை", "அறிக்கையை அனுப்பு", 7),
      ("அறிக்கையை அனுப்பு வரும் வெள்ளிக்கிழமை வரை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு அடுத்த வெள்ளிக்கிழமை வரை", "அறிக்கையை அனுப்பு", 10),
      ("அறிக்கையை அனுப்பு இந்த வெள்ளிக்கிழமை வரை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு நாளை வரை", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு நாளைக்குள்", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு நாளைக்குள்ளாக", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு நாளை மறுநாள் வரை", "அறிக்கையை அனுப்பு", 2),
      ("அறிக்கையை அனுப்பு நாளை மறுநாளுக்குள்", "அறிக்கையை அனுப்பு", 2),
      ("அறிக்கையை அனுப்பு நாளை மாலை வரை", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு நாளை காலைக்குள்", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு நாளை மாலைக்குள்", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை இரவு வரை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை இரவுக்குள்", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு இன்றைக்குள்", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு இன்றைக்குள்ளாக", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு இன்று இரவு வரை", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு இன்றிரவு வரை", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு இன்றிரவுக்குள்", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு இந்த இரவு வரை", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு இன்று மாலைக்குள்", "அறிக்கையை அனுப்பு", 0),
      ("நாளை மாலை வரை அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு 5 மே வரை", "அறிக்கையை அனுப்பு", captureDayOffset("2027-05-05")),
      ("அறிக்கையை அனுப்பு 15 அக்டோபர் வரை", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு அக்டோபர் 15 வரை", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு அக்டோபர் 15க்குள்", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு 15ஆம் தேதிக்குள்", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு 5ஆம் தேதி வரை", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-05")),
      ("அறிக்கையை அனுப்பு காலக்கெடு வெள்ளிக்கிழமை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு காலக்கெடு: வெள்ளிக்கிழமை", "அறிக்கையை அனுப்பு", 3),
      ("காலக்கெடு: வெள்ளிக்கிழமை அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு காலக்கெடு: இன்று", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு காலக்கெடு: நாளை", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு காலக்கெடு: நாளை மறுநாள்", "அறிக்கையை அனுப்பு", 2),
      ("அறிக்கையை அனுப்பு காலக்கெடு: நாளை மாலை", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு காலக்கெடு: 5 மே", "அறிக்கையை அனுப்பு", captureDayOffset("2027-05-05")),
      ("அறிக்கையை அனுப்பு காலக்கெடு: 15 அக்.", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு காலக்கெடு: வியாழன், 15 அக்டோபர்", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு காலக்கெடு: வியாழன் 15 அக்டோபர்", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு காலக்கெடு: 15 அக்டோபர், வியாழன்", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு காலக்கெடு தேதி: வியாழன், 15 அக்டோபர்", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு காலக்கெடு தேதி: அக்டோபர் 15", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு காலக்கெடு தேதி அக்டோபர் 15", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு கடைசி தேதி: 5 மே", "அறிக்கையை அனுப்பு", captureDayOffset("2027-05-05")),
      ("அறிக்கையை அனுப்பு இறுதி தேதி வெள்ளிக்கிழமை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு இறுதி நாள் வெள்ளிக்கிழமை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு டெட்லைன்: நாளை", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு டெட்லைன் வெள்ளிக்கிழமை", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு டெட் லைன் வெள்ளிக்கிழமை", "அறிக்கையை அனுப்பு", 3),
      ("டெட்லைன் வெள்ளிக்கிழமை அறிக்கையை அனுப்பு", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை காலக்கெடு", "அறிக்கையை அனுப்பு", 3),
      ("அறிக்கையை அனுப்பு நாளை காலக்கெடு", "அறிக்கையை அனுப்பு", 1),
      ("அறிக்கையை அனுப்பு இன்று காலக்கெடு", "அறிக்கையை அனுப்பு", 0),
      ("அறிக்கையை அனுப்பு 15 அக். காலக்கெடு", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
      ("அறிக்கையை அனுப்பு 15 அக்டோபர் காலக்கெடு", "அறிக்கையை அனுப்பு", captureDayOffset("2026-10-15")),
    ]
    for line in due {
      let parsed = parse(line.text)
      #expect(parsed.dueDayOffset == line.offset, "\(line.text): due day")
      #expect(parsed.plannedDayOffset == nil, "\(line.text): planned day")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.due], "\(line.text): phrase kind")
    }
    let both = parse("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரை நாளை")
    #expect(both.dueDayOffset == 3)
    #expect(both.plannedDayOffset == 1)
    #expect(both.title == "அறிக்கையை அனுப்பு")
  }

  @Test("\"இன்று வரை\" means \"so far\", and a deadline that has passed or that a genitive follows is no deadline")
  func notDueDays() {
    expectLinesUnread(
      [
        "அறிக்கை இன்று வரை", "அறிக்கை இன்று வரைக்கும்", "வெள்ளிக்கிழமை காலக்கெடு முடிந்தது",
        "வெள்ளிக்கிழமை காலக்கெடு கடந்தது", "வெள்ளிக்கிழமை காலக்கெடு தாண்டியது", "நாளை காலக்கெடு முடிந்தது",
        "வெள்ளிக்கிழமையின் அறிக்கை", "காலக்கெடு: வெள்ளிக்கிழமை, ஆனால் காலக்கெடு முடிந்தது",
      ], languages: ["ta"])
  }

  @Test("A deadline written as a clock time names no start time and stays in the title")
  func clockDeadlines() {
    expectLinesUnread(
      [
        "அறிக்கையை அனுப்பு 5 மணிக்குள்", "அறிக்கையை அனுப்பு மாலை 6 மணிக்குள்", "அறிக்கையை அனுப்பு 5 மணிக்கெல்லாம்",
        "அறிக்கையை அனுப்பு 5 மணி வரை", "அறிக்கையை அனுப்பு 18:00 வரை", "அறிக்கையை அனுப்பு 3 PMக்குள்",
        "அறிக்கையை அனுப்பு 3 PM வரை", "அறிக்கையை அனுப்பு 5 மணிக்குப் பிறகு", "அறிக்கையை அனுப்பு 5 மணிக்கு முன்",
        "அறிக்கையை அனுப்பு மாலை 6க்குள்", "அறிக்கையை அனுப்பு ஐந்தரைக்குள்", "அறிக்கையை அனுப்பு நள்ளிரவு வரை",
        "அறிக்கையை அனுப்பு நள்ளிரவுக்குப் பிறகு", "அறிக்கையை அனுப்பு மாலை 5 மணிக்கு முன்",
        "அறிக்கையை அனுப்பு ஐந்து மணிக்கு முன்", "அறிக்கையை அனுப்பு 5 மணிக்கு முன்பு",
        "அறிக்கையை அனுப்பு மாலை 6 வரை",
      ], languages: ["ta"])
    // The day before a clock deadline is the due day, and the clock stays.
    let friday = parse("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை மாலை 5 மணிக்குள்")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.startMinutes == nil)
    #expect(friday.title == "அறிக்கையை அனுப்பு மாலை 5 மணிக்குள்")
    let tomorrow = parse("அறிக்கையை அனுப்பு நாளை 5 மணிக்குள்")
    #expect(tomorrow.dueDayOffset == 1)
    #expect(tomorrow.title == "அறிக்கையை அனுப்பு 5 மணிக்குள்")
    let clock = parse("அறிக்கையை அனுப்பு நாளை 18:00 வரை")
    #expect(clock.dueDayOffset == 1)
    #expect(clock.startMinutes == nil)
    #expect(clock.title == "அறிக்கையை அனுப்பு 18:00 வரை")
    // A planned day beside the clock deadline reads, and the clock stays.
    let day = parse("அறிக்கையை அனுப்பு 5 மணிக்குள் நாளை")
    #expect(day.plannedDayOffset == 1)
    #expect(day.startMinutes == nil)
    #expect(day.title == "அறிக்கையை அனுப்பு 5 மணிக்குள்")
    // A time range that ends in "வரை" is still a range.
    let range = parse("கூட்டம் 2 மணி முதல் 4 மணி வரை")
    #expect(range.startMinutes == 14 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "கூட்டம்")
    // Without Tamil, English reads the clock time and leaves the word.
    let english = parse("அறிக்கையை அனுப்பு 18:00 வரை", languages: ["en"])
    #expect(english.startMinutes == 18 * 60)
    #expect(english.title == "அறிக்கையை அனுப்பு வரை")
  }

  // MARK: - Times

  @Test("Clock times: மணிக்கு after the hour, with a part of the day, and with the word that goes with it")
  func times() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("கூட்டம் 5 மணிக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் 5:30 மணிக்கு", "கூட்டம்", 17 * 60 + 30),
      ("கூட்டம் 5.30 மணிக்கு", "கூட்டம்", 17 * 60 + 30), ("கூட்டம் 5 மணிக்கே", "கூட்டம்", 17 * 60),
      ("கூட்டம் 1 மணிக்கு", "கூட்டம்", 13 * 60), ("5 மணிக்கு கூட்டம்", "கூட்டம்", 17 * 60),
      ("கூட்டம் சரியாக 5 மணிக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் துல்லியமாக 5 மணிக்கு", "கூட்டம்", 17 * 60),
      ("கூட்டம் சுமார் 5 மணிக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் கிட்டத்தட்ட 5 மணிக்கு", "கூட்டம்", 17 * 60),
      ("கூட்டம் 5 மணி", "கூட்டம்", 17 * 60), ("கூட்டம் 5 மணியளவில்", "கூட்டம்", 17 * 60),
      ("கூட்டம் 5 மணி அளவில்", "கூட்டம்", 17 * 60), ("கூட்டம் 5 மணி வாக்கில்", "கூட்டம்", 17 * 60),
      ("கூட்டம் 5 மணி முதல்", "கூட்டம்", 17 * 60), ("கூட்டம் 5 மணியிலிருந்து", "கூட்டம்", 17 * 60),
      ("கூட்டம் காலை 9 மணிக்கு", "கூட்டம்", 9 * 60), ("கூட்டம் காலை 9க்கு", "கூட்டம்", 9 * 60),
      ("கூட்டம் காலை 9:30", "கூட்டம்", 9 * 60 + 30), ("கூட்டம் காலை 9.30", "கூட்டம்", 9 * 60 + 30),
      ("கூட்டம் காலை 9:30 மணிக்கு", "கூட்டம்", 9 * 60 + 30), ("கூட்டம் காலை 6.15க்கு", "கூட்டம்", 6 * 60 + 15),
      ("கூட்டம் காலை 7 மணிக்கே", "கூட்டம்", 7 * 60), ("கூட்டம் காலையில் 6 மணிக்கு", "கூட்டம்", 6 * 60),
      ("கூட்டம் அதிகாலை 4 மணிக்கு", "கூட்டம்", 4 * 60), ("கூட்டம் மதியம் 12 மணிக்கு", "கூட்டம்", 12 * 60),
      ("கூட்டம் மதியம் 1 மணிக்கு", "கூட்டம்", 13 * 60), ("கூட்டம் மதியம் 2 மணிக்கு", "கூட்டம்", 14 * 60),
      ("கூட்டம் மதியம் 3:30 மணிக்கு", "கூட்டம்", 15 * 60 + 30), ("கூட்டம் பிற்பகல் 2 மணிக்கு", "கூட்டம்", 14 * 60),
      ("கூட்டம் மாலை 5 மணிக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் மாலை 5க்கு", "கூட்டம்", 17 * 60),
      ("கூட்டம் மாலை 5க்கே", "கூட்டம்", 17 * 60), ("கூட்டம் மாலை 6:30 மணிக்கு", "கூட்டம்", 18 * 60 + 30),
      ("கூட்டம் மாலை 7 மணிக்கு", "கூட்டம்", 19 * 60), ("கூட்டம் சாயங்காலம் 7 மணிக்கு", "கூட்டம்", 19 * 60),
      ("கூட்டம் சாயந்திரம் 7 மணிக்கு", "கூட்டம்", 19 * 60), ("கூட்டம் இரவு 10 மணிக்கு", "கூட்டம்", 22 * 60),
      ("கூட்டம் இரவு 9 மணிக்கு", "கூட்டம்", 21 * 60), ("கூட்டம் இரவு 11க்கு", "கூட்டம்", 23 * 60),
      ("கூட்டம் இரவு 8:30க்கு", "கூட்டம்", 20 * 60 + 30), ("கூட்டம் இரவு 10.30", "கூட்டம்", 22 * 60 + 30),
      ("கூட்டம் இரவு சரியாக 10 மணிக்கு", "கூட்டம்", 22 * 60), ("கூட்டம் ராத்திரி 10 மணிக்கு", "கூட்டம்", 22 * 60),
      ("கூட்டம் மாலை ஐந்து மணிக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் காலை எட்டு மணிக்கு", "கூட்டம்", 8 * 60),
      ("கூட்டம் இரவு பத்து மணிக்கு", "கூட்டம்", 22 * 60), ("கூட்டம் மதியம் இரண்டு மணிக்கு", "கூட்டம்", 14 * 60),
      ("கூட்டம் மாலை ஐந்துக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் இரவு பத்துக்கு", "கூட்டம்", 22 * 60),
      ("கூட்டம் காலை எட்டுக்கு", "கூட்டம்", 8 * 60), ("கூட்டம் 17:30க்கு", "கூட்டம்", 17 * 60 + 30),
      ("கூட்டம் 17:30 மணிக்கு", "கூட்டம்", 17 * 60 + 30), ("கூட்டம் 3:30 PMக்கு", "கூட்டம்", 15 * 60 + 30),
      ("கூட்டம் 5 PMக்கு", "கூட்டம்", 17 * 60), ("கூட்டம் 3:30 AMக்கு", "கூட்டம்", 3 * 60 + 30),
      ("கூட்டம் 17:30", "கூட்டம்", 17 * 60 + 30), ("கூட்டம் 5 PM", "கூட்டம்", 17 * 60),
      ("கூட்டம் 5 மணிக்குத் தொடங்கு", "கூட்டம் தொடங்கு", 17 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // A part of the day after the time is not read, and it names the half of
    // the day of the hour all the same.
    let after = parse("கூட்டம் 5 மணிக்கு காலை")
    #expect(after.startMinutes == 5 * 60)
    #expect(after.title == "கூட்டம் காலை")
    let evening = parse("கூட்டம் 7 மணிக்கு மாலை")
    #expect(evening.startMinutes == 19 * 60)
    #expect(evening.title == "கூட்டம் மாலை")
    // The part of the day written before the hour wins over one written after it.
    let both = parse("கூட்டம் காலை 9 மணிக்கு மாலை")
    #expect(both.startMinutes == 9 * 60)
    #expect(both.title == "கூட்டம் மாலை")
    // Twelve in the morning is no time, and neither is 24 o'clock.
    expectLinesUnread(["கூட்டம் காலை 12 மணிக்கு", "கூட்டம் 24 மணிக்கு"], languages: ["ta"])
  }

  @Test("An hour as a number word is read with its ending")
  func numberWordHours() {
    let hours: [(word: String, minutes: Int)] = [
      ("ஒரு மணிக்கு", 13 * 60), ("இரண்டு மணிக்கு", 14 * 60), ("ரெண்டு மணிக்கு", 14 * 60),
      ("மூன்று மணிக்கு", 15 * 60), ("மூணு மணிக்கு", 15 * 60), ("நான்கு மணிக்கு", 16 * 60),
      ("நாலு மணிக்கு", 16 * 60), ("ஐந்து மணிக்கு", 17 * 60), ("அஞ்சு மணிக்கு", 17 * 60),
      ("ஆறு மணிக்கு", 18 * 60), ("ஏழு மணிக்கு", 7 * 60), ("எட்டு மணிக்கு", 8 * 60),
      ("ஒன்பது மணிக்கு", 9 * 60), ("பத்து மணிக்கு", 10 * 60), ("பதினொரு மணிக்கு", 11 * 60),
      ("பன்னிரண்டு மணிக்கு", 12 * 60),
    ]
    for hour in hours {
      let text = "கூட்டம் \(hour.word)"
      let parsed = parse(text)
      #expect(parsed.startMinutes == hour.minutes, "\(text)")
      #expect(parsed.title == "கூட்டம்", "\(text): title")
    }
    #expect(parse("கூட்டம் காலை ஒன்பது மணிக்கு").startMinutes == 9 * 60)
    #expect(parse("கூட்டம் மாலை ஆறு மணிக்கு").startMinutes == 18 * 60)
    // A number word is a count anywhere else, the dative of a count without a
    // part of the day is no hour, and an hour without "மணி" is an amount.
    expectLinesUnread(
      [
        "கூட்டம் ஐந்து", "கூட்டம் ஒரு", "ஐந்து புத்தகங்கள் வாங்கு", "இரண்டு முட்டை வாங்கு",
        "கூட்டம் மூன்று முதல் ஐந்து", "பன்னிரண்டுக்கு கூட்டம்", "கூட்டம் ஐந்துக்கு",
      ], languages: ["ta"])
    // "ஐந்து மணி நேரம்" is an amount of hours, not a time.
    let length = parse("கூட்டம் ஐந்து மணி நேரம்")
    #expect(length.startMinutes == nil)
    #expect(length.estimatedMinutes == 300)
  }

  @Test("Half hours and quarters: ஐந்தரை is 5:30, read with an ending or after a part of the day")
  func clockFractions() {
    let fractions: [(text: String, minutes: Int)] = [
      ("கூட்டம் ஐந்தரைக்கு", 17 * 60 + 30), ("கூட்டம் ஐந்தரை மணிக்கு", 17 * 60 + 30),
      ("கூட்டம் அஞ்சரைக்கு", 17 * 60 + 30), ("கூட்டம் மூன்றரைக்கு", 15 * 60 + 30),
      ("கூட்டம் ஆறரைக்கு", 18 * 60 + 30), ("கூட்டம் ஏழரைக்கு", 7 * 60 + 30),
      ("கூட்டம் எட்டரைக்கு", 8 * 60 + 30), ("கூட்டம் பதினொன்றரைக்கு", 11 * 60 + 30),
      ("கூட்டம் பன்னிரண்டரைக்கு", 12 * 60 + 30), ("கூட்டம் இரண்டரைக்கு", 14 * 60 + 30),
      ("கூட்டம் நான்கரைக்கு", 16 * 60 + 30), ("கூட்டம் ஒன்றரை மணிக்கு", 13 * 60 + 30),
      ("கூட்டம் ஒன்றரைக்கு", 13 * 60 + 30), ("கூட்டம் காலை எட்டரைக்கு", 8 * 60 + 30),
      ("கூட்டம் மாலை ஐந்தரை", 17 * 60 + 30), ("கூட்டம் இரவு ஒன்பதரை", 21 * 60 + 30),
      ("கூட்டம் மதியம் ஒன்றரை", 13 * 60 + 30), ("கூட்டம் சரியாக ஐந்தரைக்கு", 17 * 60 + 30),
      ("ஐந்தரைக்கு கூட்டம்", 17 * 60 + 30), ("கூட்டம் ஐந்தேகால் மணிக்கு", 17 * 60 + 15),
      ("கூட்டம் ஐந்தேகாலுக்கு", 17 * 60 + 15), ("கூட்டம் ஐந்தே முக்கால் மணிக்கு", 17 * 60 + 45),
      ("கூட்டம் ஐந்தே முக்காலுக்கு", 17 * 60 + 45), ("கூட்டம் காலை ஆறேகால்", 6 * 60 + 15),
      ("கூட்டம் மாலை ஆறே முக்கால்", 18 * 60 + 45), ("கூட்டம் ஐந்து முப்பது மணிக்கு", 17 * 60 + 30),
      ("கூட்டம் ஐந்து முப்பது மணி", 17 * 60 + 30),
    ]
    for line in fractions {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == "கூட்டம்", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // The word is a number too, so it is a time only with an ending or a part of the day.
    expectLinesUnread(["கூட்டம் ஐந்தரை", "ஐந்தரை கிலோ அரிசி", "ஒன்றரை கிலோ சர்க்கரை"], languages: ["ta"])
  }

  @Test("The minutes of an hour with the dative of நிமிடம்: \"10 மணி 30 நிமிடத்திற்கு\" is 10:30")
  func minutesAfterHour() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("காலை 10 மணி 30 நிமிடத்திற்கு கூட்டம்", "கூட்டம்", 10 * 60 + 30),
      ("காலை 9 மணி 15 நிமிடத்திற்கு கூட்டம்", "கூட்டம்", 9 * 60 + 15),
      ("5 மணி 30 நிமிடத்திற்கு கூட்டம்", "கூட்டம்", 17 * 60 + 30),
      ("2 மணி 30 நிமிடத்துக்கு கூட்டம்", "கூட்டம்", 14 * 60 + 30),
      ("காலை 10 மணி 30 நிமிடங்களுக்கு கூட்டம்", "கூட்டம்", 10 * 60 + 30),
      ("காலை 9 மணி பதினைந்து நிமிடத்திற்கு கூட்டம்", "கூட்டம்", 9 * 60 + 15),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.estimatedMinutes == nil, "\(line.text): length")
    }
    // Hours as a unit, then minutes, are an amount of time: 5 hours and 30 minutes.
    let length = parse("5 மணி நேரம் 30 நிமிடங்கள் கூட்டம்")
    #expect(length.estimatedMinutes == 330)
    #expect(length.startMinutes == nil)
    #expect(length.title == "கூட்டம்")
    // "மணி" and minutes with no ending are a time or a length alike, so they
    // stay, whether the minutes are written in digits or in words.
    expectLinesUnread(
      ["5 மணி 30 நிமிடங்கள் கூட்டம்", "9 மணி பதினைந்து நிமிடங்கள் கூட்டம்", "5 மணி முப்பது நிமிடம் கூட்டம்"],
      languages: ["ta"])
  }

  @Test("After midnight: இரவு runs past the midnight that ends the day")
  func afterMidnight() {
    let night = parse("கூட்டம் இரவு 2 மணிக்கு")
    #expect(night.startMinutes == 2 * 60)
    #expect(night.plannedDayOffset == 1)
    #expect(night.title == "கூட்டம்")
    let twelve = parse("கூட்டம் இரவு 12 மணிக்கு")
    #expect(twelve.startMinutes == 0)
    #expect(twelve.plannedDayOffset == 1)
    let spoken = parse("கூட்டம் இரவு பன்னிரண்டு மணிக்கு")
    #expect(spoken.startMinutes == 0)
    #expect(spoken.plannedDayOffset == 1)
    for text in [
      "கூட்டம் நள்ளிரவு", "கூட்டம் நள்ளிரவில்", "கூட்டம் நள்ளிரவுக்கு", "கூட்டம் இந்த நள்ளிரவு",
      "கூட்டம் சரியாக நள்ளிரவு", "கூட்டம் மிட்நைட்", "கூட்டம் மிட் நைட்", "கூட்டம் நடு இரவு",
      "கூட்டம் நடு இரவில்", "கூட்டம் நடு ராத்திரி", "கூட்டம் மிட்நைட்டில்", "கூட்டம் மிட்நைட்டுக்கு",
      "கூட்டம் மிட்நைட்டிற்கு",
    ] {
      let midnight = parse(text)
      #expect(midnight.startMinutes == 0, "\(text)")
      #expect(midnight.plannedDayOffset == 1, "\(text)")
      #expect(midnight.title == "கூட்டம்", "\(text): title")
    }
    // The system's colour names start with the loanword: with no ending and a Tamil word after it, it is a name.
    expectLinesUnread(
      ["மிட்நைட் புளூ", "மிட்நைட் பிளாக்", "மிட்நைட் புளூ பெயிண்ட் வாங்கு", "மிட்நைட் கூட்டம்"], languages: ["ta"])
    // The native word is the time wherever it stands, beside a colour name too.
    let after = parse("மிட்நைட் புளூ பெயிண்ட் வாங்கு நள்ளிரவு")
    #expect(after.startMinutes == 0)
    #expect(after.title == "மிட்நைட் புளூ பெயிண்ட் வாங்கு")
    // A colour name names no part of the day: a day word before it, a bare hour elsewhere in the line,
    // and a weekday with a deadline keep their own readings.
    let colourDay = parse("நாளை மிட்நைட் புளூ கார் வாங்கு")
    #expect(colourDay.plannedDayOffset == 1)
    #expect(colourDay.startMinutes == nil)
    #expect(colourDay.title == "மிட்நைட் புளூ கார் வாங்கு")
    let colourMorning = parse("மிட்நைட் புளூ கார் 8 மணிக்கு")
    #expect(colourMorning.startMinutes == 8 * 60)
    #expect(colourMorning.plannedDayOffset == nil)
    #expect(colourMorning.title == "மிட்நைட் புளூ கார்")
    let colourAfternoon = parse("கார் மிட்நைட் புளூ 5 மணிக்கு")
    #expect(colourAfternoon.startMinutes == 17 * 60)
    #expect(colourAfternoon.plannedDayOffset == nil)
    #expect(colourAfternoon.title == "கார் மிட்நைட் புளூ")
    // Before an hour, after a day word, and after a weekday with a bound word, the loanword is the
    // midnight that ends the day, as நள்ளிரவு is.
    let midnights: [(text: String, title: String, day: Int)] = [
      ("மிட்நைட் 12 மணிக்கு அழை", "அழை", 1), ("இன்று மிட்நைட் 12 மணிக்கு அழை", "அழை", 1), ("கார் நாளை மிட்நைட்", "கார்", 2),
      ("கார் நாளை மிட்நைட்டுக்கு அழை", "கார் அழை", 2),
    ]
    for line in midnights {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == 0, "\(line.text)")
      #expect(parsed.plannedDayOffset == line.day, "\(line.text): day")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let due = parse("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை மிட்நைட் வரை")
    #expect(due.dueDayOffset == 3)
    #expect(due.title == "அறிக்கையை அனுப்பு")
    expectLinesUnread(["அறிக்கையை அனுப்பு மிட்நைட் வரை"], languages: ["ta"])
    // The night counts from the evening: 6 to 11 is the evening's.
    #expect(parse("கூட்டம் இரவு 6 மணிக்கு").startMinutes == 18 * 60)
    #expect(parse("கூட்டம் இரவு 6 மணிக்கு").plannedDayOffset == nil)
    // A named day keeps the time on its own night: "நாளை இரவு 1 மணிக்கு" is 01:00 of the day after.
    let tomorrow = parse("நாளை இரவு 1 மணிக்கு தூக்கம்")
    #expect(tomorrow.startMinutes == 60)
    #expect(tomorrow.plannedDayOffset == 2)
    #expect(tomorrow.title == "தூக்கம்")
    let friday = parse("வெள்ளிக்கிழமை இரவு 1 மணிக்கு விமானம்")
    #expect(friday.startMinutes == 60)
    #expect(friday.plannedDayOffset == 4)
    let named = parse("திங்கள் இரவு 12 மணிக்கு விமானம்")
    #expect(named.startMinutes == 0)
    #expect(named.plannedDayOffset == 7)
    #expect(named.title == "விமானம்")
    let tonight = parse("இன்று இரவு 12 மணிக்கு கூட்டம்")
    #expect(tonight.startMinutes == 0)
    #expect(tonight.plannedDayOffset == 1)
    // A repeat moves to the day after, so the rule and the time agree.
    let repeating = parse("ஒவ்வொரு வெள்ளிக்கிழமை இரவு 12 மணிக்கு விமானம்")
    #expect(repeating.startMinutes == 0)
    #expect(repeating.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: ["SA"]))
    #expect(repeating.recurrenceStartOffset == 4)
    #expect(repeating.title == "விமானம்")
    // A midnight deadline is no time.
    expectLinesUnread(["அறிக்கையை அனுப்பு நள்ளிரவு வரை"], languages: ["ta"])
  }

  @Test("From 1 to 6 o'clock an hour with no part of the day is the afternoon, unless it has a leading zero")
  func afternoon() {
    #expect(parse("கூட்டம் 1 மணிக்கு").startMinutes == 13 * 60)
    #expect(parse("கூட்டம் 3 மணிக்கு").startMinutes == 15 * 60)
    #expect(parse("கூட்டம் 6 மணிக்கு").startMinutes == 18 * 60)
    #expect(parse("கூட்டம் 7 மணிக்கு").startMinutes == 7 * 60)
    #expect(parse("கூட்டம் 9 மணிக்கு").startMinutes == 9 * 60)
    #expect(parse("கூட்டம் 11 மணிக்கு").startMinutes == 11 * 60)
    #expect(parse("கூட்டம் 12 மணிக்கு").startMinutes == 12 * 60)
    #expect(parse("கூட்டம் 13 மணிக்கு").startMinutes == 13 * 60)
    #expect(parse("கூட்டம் 06:30 மணிக்கு").startMinutes == 6 * 60 + 30)
    #expect(parse("கூட்டம் 03:00 மணிக்கு").startMinutes == 3 * 60)
    #expect(parse("கூட்டம் 3:00 மணிக்கு").startMinutes == 15 * 60)
    // A part of the day names the half of the day either way.
    #expect(parse("கூட்டம் காலை 5 மணிக்கு").startMinutes == 5 * 60)
    #expect(parse("கூட்டம் மாலை 5 மணிக்கு").startMinutes == 17 * 60)
  }

  @Test("A bare hour takes its half of the day from the one part of the day the line names elsewhere")
  func linePartOfDay() {
    let times: [(text: String, title: String, minutes: Int)] = [
      ("காலை நடை 6 மணிக்கு", "காலை நடை", 6 * 60), ("6 மணிக்கு காலை நடை", "காலை நடை", 6 * 60),
      ("காலை நடை 5 மணிக்கு", "காலை நடை", 5 * 60), ("இரவு உணவு 8 மணிக்கு", "இரவு உணவு", 20 * 60),
      ("இரவு உணவு 6 மணிக்கு", "இரவு உணவு", 18 * 60), ("இரவு உணவு எட்டரைக்கு", "இரவு உணவு", 20 * 60 + 30),
      ("இரவு மருந்து 10 மணிக்கு", "இரவு மருந்து", 22 * 60), ("சாயங்கால தேநீர் 5 மணிக்கு", "சாயங்கால தேநீர்", 17 * 60),
      ("மதிய உணவு 1 மணிக்கு", "மதிய உணவு", 13 * 60), ("மதிய உணவு 2 மணிக்கு", "மதிய உணவு", 14 * 60),
      // The 24-hour clock is read as written: a leading zero, or 13 and later.
      ("இரவு உணவு 20:00 மணிக்கு", "இரவு உணவு", 20 * 60), ("இரவு பணி 06:30 மணிக்கு", "இரவு பணி", 6 * 60 + 30),
      // Noon is no morning hour, so a morning's 12 stays as written.
      ("காலை கூட்டம் 12 மணிக்கு", "காலை கூட்டம்", 12 * 60),
    ]
    for line in times {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.minutes, "\(line.text)")
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.kind) == [.time], "\(line.text): phrase kind")
    }
    // The part of the day may come from the repeat, which keeps its words.
    let yoga = parse("தினமும் காலை 6 மணிக்கு யோகா")
    #expect(yoga.startMinutes == 6 * 60)
    #expect(yoga.recurrence == daily)
    #expect(yoga.title == "யோகா")
    // Two parts that differ leave the hour as it reads alone.
    #expect(parse("காலை தேநீர், மாலை ஸ்நாக்ஸ் 5 மணிக்கு").startMinutes == 17 * 60)
  }

  @Test("Time ranges: முதல், a dash, and colon times")
  func timeRanges() {
    let ranges: [(text: String, start: Int, length: Int)] = [
      ("கூட்டம் 3 மணி முதல் 5 மணி வரை", 15 * 60, 120), ("கூட்டம் 9 மணி முதல் 11 மணி வரை", 9 * 60, 120),
      ("கூட்டம் 3 முதல் 5 மணி வரை", 15 * 60, 120), ("கூட்டம் காலை 9 முதல் 11 வரை", 9 * 60, 120),
      ("கூட்டம் காலை 9 மணி முதல் 11 மணி வரை", 9 * 60, 120), ("கூட்டம் மாலை 5 முதல் 7 வரை", 17 * 60, 120),
      ("கூட்டம் இரவு 8 முதல் 10 வரை", 20 * 60, 120), ("கூட்டம் மதியம் 2 மணி முதல் மாலை 4 மணி வரை", 14 * 60, 120),
      ("கூட்டம் 9-11 மணிக்கு", 9 * 60, 120), ("கூட்டம் 2-4 மணிக்கு", 14 * 60, 120),
      ("கூட்டம் 9 மணி முதல் 5 மணி வரை", 9 * 60, 480), ("கூட்டம் 9 மணியிலிருந்து 11 மணி வரை", 9 * 60, 120),
      ("கூட்டம் 14:00 முதல் 16:00 வரை", 14 * 60, 120), ("கூட்டம் 9:30 முதல் 10:30 வரை", 9 * 60 + 30, 60),
      ("கூட்டம் 14:00 முதல் 16:00", 14 * 60, 120), ("கூட்டம் காலை 9:00 முதல் மாலை 5:00 வரை", 9 * 60, 480),
      ("கூட்டம் ஐந்து முதல் ஆறு மணி வரை", 17 * 60, 60), ("கூட்டம் ஏழு மணி முதல் எட்டு மணி வரை", 7 * 60, 60),
      ("கூட்டம் இரவு 11 முதல் 1 வரை", 23 * 60, 120), ("கூட்டம் இரவு 10 முதல் 12 வரை", 22 * 60, 120),
      ("கூட்டம் காலை 11 முதல் மதியம் 1 வரை", 11 * 60, 120), ("கூட்டம் மதியம் 12 முதல் 2 வரை", 12 * 60, 120),
    ]
    for line in ranges {
      let parsed = parse(line.text)
      #expect(parsed.startMinutes == line.start, "\(line.text): start")
      #expect(parsed.estimatedMinutes == line.length, "\(line.text): length")
      #expect(parsed.title == "கூட்டம்", "\(line.text): title")
      #expect(parsed.phrases.count == 1, "\(line.text): phrases")
    }
    // Two bare numbers are no range of hours: the range needs a part of the day or "மணி".
    expectLinesUnread(
      ["கூட்டம் 3 முதல் 5 வரை", "கூட்டம் 9-11", "கூட்டம் ஒன்று முதல் இரண்டு மணி வரை"], languages: ["ta"])
    // A length written in the line wins over the span of the range.
    let named = parse("கூட்டம் 3 மணி முதல் 5 மணி வரை 30 நிமிடங்கள்")
    #expect(named.startMinutes == 15 * 60)
    #expect(named.estimatedMinutes == 30)
    #expect(named.title == "கூட்டம்")
    // A range written with a dash and colon times is English's.
    let dashed = parse("கூட்டம் 9:00-11:00")
    #expect(dashed.startMinutes == 9 * 60)
    #expect(dashed.estimatedMinutes == 120)
  }

  @Test("A number before a counted noun, a price, or a percent sign is no time, length, or day")
  func amounts() {
    expectLinesUnread(
      [
        "3 பேருடன் கூட்டம்", "கூட்டத்துக்கு 3 பேர் வருவார்கள்", "5 புத்தகங்கள் வாங்கு", "10 பக்கங்கள் படி",
        "2 கிலோ சர்க்கரை வாங்கு", "12 முட்டை வாங்கு", "500 ரூபாய் பில் கட்டு", "₹500 பில்", "பில் ₹500",
        "5 டாலர் செலவு", "20% தள்ளுபடி", "20 % தள்ளுபடி", "2 வகுப்புகள் எடு", "5க்கு கூட்டம்",
        // A number after a slash belongs to a fraction or a date, not to an hour.
        "படி 1/2 மணிக்கு", "படி 5/6 மணிக்கு", "படி 5/6 மணி",
      ], languages: ["ta"])
    // The words around an amount still read.
    let bill = parse("500 ரூபாய் பில் கட்டு நாளை")
    #expect(bill.plannedDayOffset == 1)
    #expect(bill.title == "500 ரூபாய் பில் கட்டு")
    let price = parse("500 ரூபாய் 5 மணிக்கு")
    #expect(price.startMinutes == 17 * 60)
    #expect(price.title == "500 ரூபாய்")
    let percent = parse("கூட்டம் 5 மணிக்கு 20%")
    #expect(percent.startMinutes == 17 * 60)
    #expect(percent.title == "கூட்டம் 20%")
  }

  // MARK: - Lengths

  @Test("Lengths: minutes, hours, fractions of an hour, and a length in words")
  func lengths() {
    let lengths: [(text: String, minutes: Int)] = [
      ("30 நிமிடங்கள்", 30), ("45 நிமிடங்கள்", 45), ("90 நிமிடங்கள்", 90), ("2 நிமிடங்கள்", 2), ("1 நிமிடம்", 1),
      ("30நிமிடங்கள்", 30), ("30 நிமி.", 30), ("30 நிமிஷங்கள்", 30), ("2 மணி நேரம்", 120), ("2மணி நேரம்", 120),
      ("2 மணிநேரம்", 120), ("1 மணி நேரம்", 60), ("1.5 மணி நேரம்", 90), ("2 ம.", 120), ("1 ம. 30 நிமி.", 90),
      ("1 மணி, 30 நிமி", 90), ("1 மணி நேரம் 30 நிமிடங்கள்", 90), ("1 மணி நேரம், 30 நிமிடங்கள்", 90),
      ("1 மணிநேரம், 30 நிமிடங்கள்", 90), ("2 மணி நேரம் 30 நிமிடங்கள்", 150), ("அரை மணி நேரம்", 30),
      ("அரை மணி", 30), ("அரைமணி", 30), ("கால் மணி நேரம்", 15), ("கால் மணி", 15), ("முக்கால் மணி நேரம்", 45),
      ("ஒன்றரை மணி நேரம்", 90), ("இரண்டரை மணி நேரம்", 150), ("இரண்டு மணி நேரம்", 120),
      ("மூன்று மணி நேரம்", 180), ("ஒரு மணி நேரம்", 60), ("இருபது நிமிடங்கள்", 20), ("பதினைந்து நிமிடங்கள்", 15),
      ("முப்பது நிமிடங்கள்", 30), ("நாற்பத்தைந்து நிமிடங்கள்", 45), ("பத்து நிமிடங்கள்", 10),
      ("சுமார் 2 மணி நேரம்", 120), ("கிட்டத்தட்ட 30 நிமிடங்கள்", 30), ("தோராயமாக 1 மணி நேரம்", 60),
      ("சுமார் அரை மணி நேரம்", 30), ("30 நிமிடத்திற்கு", 30), ("30 நிமிடங்களுக்கு", 30),
      ("2 மணி நேரத்திற்கு", 120),
      // The minutes of an hour and a half in words, as the system writes them, and the hours mixed with digits.
      ("ஒரு மணி நேரம் முப்பது நிமிடங்கள்", 90), ("ஒரு மணிநேரம் முப்பது நிமிடங்கள்", 90),
      ("ஒரு மணி நேரம் மற்றும் முப்பது நிமிடங்கள்", 90), ("இரண்டு மணி நேரம், பதினைந்து நிமிடங்கள்", 135),
      ("ஒரு மணி நேரம் 30 நிமிடங்கள்", 90), ("1 மணி நேரம் முப்பது நிமிடங்கள்", 90),
      ("1 மற்றும் அரை மணிநேரம்", 90), ("2 மற்றும் அரை மணி நேரம்", 150),
      // "ஒரு" may stand before a half or a quarter, as the system writes "A half hour".
      ("ஒரு அரை மணி நேரம்", 30), ("ஒரு அரை மணிநேரம்", 30), ("ஒரு கால் மணி நேரம்", 15),
      ("ஒரு முக்கால் மணி நேரம்", 45), ("அரை மணிநேரம்", 30), ("ஒன்றரை மணிநேரம்", 90), ("45 நிமி.", 45),
      // "ஒரு மணிநேரத்திற்கு" with no number after it is for an hour ("Approve for an hour").
      ("ஒரு மணிநேரத்திற்கு", 60),
    ]
    for line in lengths {
      let text = "அறிக்கை எழுது \(line.text)"
      let parsed = parse(text)
      #expect(parsed.estimatedMinutes == line.minutes, "\(text)")
      #expect(parsed.title == "அறிக்கை எழுது", "\(text): title")
      #expect(parsed.startMinutes == nil, "\(text): time")
      #expect(parsed.phrases.map(\.kind) == [.length], "\(text): phrase kind")
    }
    // The form of the unit that goes before a noun is read with it.
    let meeting = parse("30 நிமிட கூட்டம்")
    #expect(meeting.estimatedMinutes == 30)
    #expect(meeting.title == "கூட்டம்")
    #expect(meeting.phrases.map(\.text) == ["30 நிமிட"])
    let work = parse("2 மணி நேர வேலை")
    #expect(work.estimatedMinutes == 120)
    #expect(work.title == "வேலை")
    let doubled = parse("2 மணி நேரக் கூட்டம்")
    #expect(doubled.estimatedMinutes == 120)
    #expect(doubled.title == "கூட்டம்")
    // A time and a length together.
    let both = parse("கூட்டம் 5 மணிக்கு 45 நிமிடங்கள்")
    #expect(both.startMinutes == 17 * 60)
    #expect(both.estimatedMinutes == 45)
    #expect(both.title == "கூட்டம்")
  }

  @Test("An amount before கழித்து, முன், or வரை, after ஒவ்வொரு, or with an ending of another word, is no length and stays whole")
  func notLengths() {
    expectLinesUnread(
      [
        // A moment, an interval, a bound, the past, and a comparison.
        "அறிக்கை எழுது 2 மணி நேரம் கழித்து", "அறிக்கை எழுது 30 நிமிடங்கள் கழித்து", "அறிக்கை எழுது 5 நிமிடங்கள் முன்",
        "அறிக்கை எழுது 2 மணி நேரம் முன்பு", "அறிக்கை எழுது 2 மணி நேரம் வரை", "அறிக்கை எழுது 30 நிமிடங்கள் வரை",
        "அறிக்கை எழுது ஒவ்வொரு 2 மணி நேரம்", "அறிக்கை எழுது ஒரு நாளைக்கு 30 நிமிடங்கள்",
        "அறிக்கை எழுது குறைந்தது 2 மணி நேரம்", "அறிக்கை எழுது அதிகபட்சம் 2 மணி நேரம்",
        "அறிக்கை எழுது 2 மணி நேரம் ஒருமுறை",
        "அறிக்கை எழுது ஒரு மணி நேரம் முப்பது நிமிடங்கள் கழித்து", "அறிக்கை எழுது 1 மற்றும் அரை மணிநேரம் கழித்து",
        "அறிக்கை எழுது ஒவ்வொரு ஒரு மணி நேரம் முப்பது நிமிடங்கள்",
        // An ending of another word on the unit.
        "அறிக்கை எழுது 2 மணி நேரத்தில்", "அறிக்கை எழுது 30 நிமிடங்களில்", "அறிக்கை எழுது 2 மணிநேரத்தில்",
        "அறிக்கை எழுது 2 மணி நேரத்துக்குள்",
        // A range of amounts, an hour as a noun, and an amount no task takes.
        "அறிக்கை எழுது 2 முதல் 3 மணி நேரம்", "அறிக்கை எழுது 2-3 மணி நேரம்",
        "அறிக்கை எழுது 5 நிமிடங்கள் முதல் 10 நிமிடங்கள்", "அறிக்கை எழுது மணி", "அறிக்கை எழுது மணி நேரம்",
        "அறிக்கை எழுது 0 நிமிடங்கள்",
        // A rate: "ஒரு" and the dative of the unit before a number or a placeholder is "per hour" or "per minute".
        "அறிக்கை எழுது ஒரு மணிநேரத்திற்கு 5 மைல்கள்", "அறிக்கை எழுது ஒரு மணிநேரத்திற்கு %lu மைல்கள்",
        "அறிக்கை எழுது ஒரு நிமிடத்திற்கு %d துடிப்புகள்", "அறிக்கை எழுது ஒரு நிமிடத்திற்கு 10 சுவாசங்கள்",
        "அறிக்கை எழுது ஒரு நிமிடத்திற்கு ஒரு முறை",
        // A fraction: the number after the slash belongs to it.
        "அறிக்கை எழுது 1/2 மணிநேரம்", "அறிக்கை எழுது 1 1/2 மணிநேரம்",
        // The system's relative times.
        "அறிக்கை எழுது 3 நா. முன்",
      ], languages: ["ta"])
    // The phrase around an amount that is no length still reads.
    let day = parse("அறிக்கை எழுது 2 மணி நேரம் கழித்து நாளை")
    #expect(day.estimatedMinutes == nil)
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "அறிக்கை எழுது 2 மணி நேரம் கழித்து")
    let time = parse("கூட்டம் நாளை 3 மணிக்கு 2 மணி நேரம் முன்")
    #expect(time.startMinutes == 15 * 60)
    #expect(time.estimatedMinutes == nil)
    #expect(time.title == "கூட்டம் 2 மணி நேரம் முன்")
    // A dative after a number in digits is for that long, with a price after it or not.
    let court = parse("கோர்ட் 2 மணி நேரத்திற்கு 500 ரூபாய்")
    #expect(court.estimatedMinutes == 120)
    #expect(court.title == "கோர்ட் 500 ரூபாய்")
    let approval = parse("ஒரு மணிநேரத்திற்கு ஒப்புதல் அளிக்கவும்")
    #expect(approval.estimatedMinutes == 60)
    #expect(approval.title == "ஒப்புதல் அளிக்கவும்")
  }

  // MARK: - Repeats

  @Test("Repeats: every day, week, month, and year, and every so many")
  func cadences() {
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let cadences: [(text: String, rule: TaskRecurrenceRule)] = [
      ("தினமும்", daily), ("தினந்தோறும்", daily), ("தினம் தோறும்", daily), ("நாள்தோறும்", daily),
      ("நாள் தோறும்", daily), ("ஒவ்வொரு நாளும்", daily), ("ஒவ்வொரு நாள்", daily), ("ஒவ்வொரு நாளுக்கும்", daily),
      ("தினசரி", daily), ("நாளுக்கு ஒருமுறை", daily), ("தினம் ஒருமுறை", daily), ("1 நாளுக்கு ஒருமுறை", daily),
      ("ஒவ்வொரு வாரமும்", weekly), ("ஒவ்வொரு வாரம்", weekly), ("வாரந்தோறும்", weekly), ("வாரம் தோறும்", weekly),
      ("வாரத்திற்கு ஒருமுறை", weekly), ("வாரத்துக்கு ஒருமுறை", weekly), ("வாரம் ஒருமுறை", weekly),
      ("வாராந்திர", weekly), ("வாராந்தர", weekly), ("ஒவ்வொரு மாதமும்", monthly), ("மாதந்தோறும்", monthly),
      ("மாதம் தோறும்", monthly), ("மாதத்திற்கு ஒருமுறை", monthly), ("மாதாந்திர", monthly), ("மாதாந்தர", monthly),
      ("ஒவ்வொரு வருடமும்", yearly), ("ஒவ்வொரு ஆண்டும்", yearly), ("வருடந்தோறும்", yearly),
      ("ஆண்டுதோறும்", yearly), ("வருடத்திற்கு ஒருமுறை", yearly), ("ஆண்டுக்கு ஒருமுறை", yearly),
      ("வருடாந்திர", yearly), ("வருடாந்தர", yearly), ("ஒவ்வொரு 2 நாட்களுக்கும்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு 2 நாட்களுக்கு", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு 2 நாட்கள்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு இரண்டு நாட்களுக்கும்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு இரண்டாவது நாளும்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு இரண்டாம் நாள்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("நாள் விட்டு நாள்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒருநாள் விட்டு ஒருநாள்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒரு நாள் விட்டு ஒரு நாள்", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("2 நாட்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("2 நாட்களுக்கு ஒரு முறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு 2 நாட்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("ஒவ்வொரு 3 நாட்களுக்கும்", TaskRecurrenceRule(freq: .daily, interval: 3)),
      ("ஒவ்வொரு பதினைந்து நாட்களுக்கும்", TaskRecurrenceRule(freq: .daily, interval: 15)),
      ("ஒவ்வொரு 2 வாரங்களுக்கும்", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ஒவ்வொரு இரண்டு வாரங்கள்", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ஒவ்வொரு 3 வாரங்கள்", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("2 வாரங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("வாரம் விட்டு வாரம்", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("ஒவ்வொரு 3 மாதங்களுக்கும்", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ஒவ்வொரு மூன்று மாதங்களுக்கும்", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("ஒவ்வொரு 4 மாதங்கள்", TaskRecurrenceRule(freq: .monthly, interval: 4)),
      ("3 மாதங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .monthly, interval: 3)),
      ("மாதம் விட்டு மாதம்", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("ஒவ்வொரு 5 வருடங்களுக்கும்", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("ஒவ்வொரு 5 ஆண்டுகளுக்கும்", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("2 வருடங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .yearly, interval: 2)),
    ]
    for line in cadences {
      let text = "மருந்து சாப்பிடு \(line.text)"
      let parsed = parse(text)
      #expect(parsed.recurrence == line.rule, "\(text)")
      #expect(parsed.title == "மருந்து சாப்பிடு", "\(text): title")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.phrases.map(\.kind) == [.repeats], "\(text): phrase kind")
    }
    // The adjectives that say how a task repeats are read before a colon or with a word of their own.
    #expect(parse("மாதாந்திர: வாடகை செலுத்து").recurrence == monthly)
    #expect(parse("மாதாந்திர: வாடகை செலுத்து").title == "வாடகை செலுத்து")
    #expect(parse("அறிக்கை தினசரி").recurrence == daily)
    #expect(parse("அறிக்கை வாராந்திர").recurrence == weekly)
    #expect(parse("அறிக்கை வருடாந்திர").recurrence == yearly)
    #expect(parse("அறிக்கை தினசரி அடிப்படையில்").recurrence == daily)
    #expect(parse("அறிக்கை தினசரி.").title == "அறிக்கை.")
  }

  @Test("Weekday repeats: ஒவ்வொரு திங்கட்கிழமை, lists of days, the weekend, and the working days")
  func weekdayRepeats() {
    let coming = parse("ஜிம் ஒவ்வொரு திங்கட்கிழமை")
    #expect(coming.recurrence == monday)
    #expect(coming.recurrenceStartOffset == 6)
    #expect(coming.title == "ஜிம்")
    #expect(coming.plannedDayOffset == nil)
    for text in [
      "ஜிம் ஒவ்வொரு திங்கட்கிழமையும்", "ஜிம் ஒவ்வொரு திங்கள்", "ஜிம் ஒவ்வொரு திங்களும்", "ஜிம் ஒவ்வொரு திங்கள்கிழமை",
      "ஜிம் திங்கள்தோறும்", "ஜிம் திங்கட்கிழமைகளில்", "ஜிம் ஒவ்வொரு வாரமும் திங்கள்", "ஜிம் திங்களும் ஒவ்வொரு வாரமும்",
      "ஜிம் வாரந்தோறும் திங்கள்",
    ] {
      #expect(parse(text).recurrence == monday, "\(text)")
      #expect(parse(text).title == "ஜிம்", "\(text): title")
    }

    let lists: [(text: String, days: [String])] = [
      ("ஜிம் ஒவ்வொரு திங்கள் மற்றும் வியாழன்", ["MO", "TH"]),
      ("ஜிம் ஒவ்வொரு திங்கள், புதன், வெள்ளி", ["MO", "WE", "FR"]),
      ("ஜிம் ஒவ்வொரு திங்கள், புதன் மற்றும் வெள்ளி", ["MO", "WE", "FR"]),
      ("ஜிம் ஒவ்வொரு திங்கள் புதன் வெள்ளி", ["MO", "WE", "FR"]),
      ("ஜிம் ஒவ்வொரு புதன்கிழமை", ["WE"]), ("ஜிம் ஒவ்வொரு சனிக்கிழமை", ["SA"]),
      ("ஜிம் ஒவ்வொரு ஞாயிற்றுக்கிழமை", ["SU"]), ("ஜிம் ஒவ்வொரு சனிக்கிழமை மற்றும் ஞாயிற்றுக்கிழமை", ["SU", "SA"]),
      ("ஜிம் ஒவ்வொரு வார இறுதியும்", ["SU", "SA"]), ("ஜிம் ஒவ்வொரு வீக்கெண்டும்", ["SU", "SA"]),
      ("ஜிம் வார இறுதிகளில்", ["SU", "SA"]), ("ஜிம் சனி ஞாயிறுகளில்", ["SU", "SA"]),
      ("ஜிம் சனிக்கிழமை, ஞாயிற்றுக்கிழமைகளில்", ["SU", "SA"]),
    ]
    for line in lists {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == TaskRecurrenceRule(freq: .weekly, byDay: line.days), "\(line.text)")
      #expect(parsed.title == "ஜிம்", "\(line.text): title")
    }
    #expect(parse("ஜிம் ஒவ்வொரு திங்கள் மற்றும் வியாழன்").recurrenceStartOffset == 2)
    #expect(parse("ஜிம் ஒவ்வொரு வார இறுதியும்").recurrenceStartOffset == 4)

    // The working days, written out or as a span of weekdays beside ஒவ்வொரு or a
    // word for every day.
    for text in [
      "ஜிம் வேலை நாட்களில்", "ஜிம் வார நாட்களில்", "ஜிம் ஒவ்வொரு வேலை நாளும்", "ஜிம் ஒவ்வொரு வேலை நாள்",
      "ஜிம் தினமும் வார நாட்களில்", "ஜிம் ஒவ்வொரு திங்கள் முதல் வெள்ளி வரை", "ஜிம் தினமும் திங்கள் முதல் வெள்ளி வரை",
      "ஜிம் திங்கள் முதல் வெள்ளி வரை தினமும்", "ஜிம் ஒவ்வொரு திங்கட்கிழமை முதல் வெள்ளிக்கிழமை வரை",
      "ஜிம் ஒவ்வொரு திங்கள் முதல் வெள்ளி வரை காலை 9 மணிக்கு",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == workdays, "\(text)")
      #expect(parsed.recurrenceStartOffset == 0, "\(text): start")
      #expect(parsed.plannedDayOffset == nil, "\(text): planned day")
      #expect(parsed.dueDayOffset == nil, "\(text): due day")
    }
    #expect(
      parse("ஜிம் ஒவ்வொரு திங்கள் முதல் புதன் வரை").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["MO", "TU", "WE"]))
    #expect(
      parse("ஜிம் ஒவ்வொரு ஞாயிறு முதல் வியாழன் வரை").recurrence
        == TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "MO", "TU", "WE", "TH"]))
    // A repeat that starts today starts at 0 on its own weekday.
    #expect(parse("ஜிம் ஒவ்வொரு செவ்வாய்க்கிழமை").recurrenceStartOffset == 0)
    #expect(parse("ஜிம் ஒவ்வொரு வெள்ளிக்கிழமை", weekday: 6, today: "2026-09-25").recurrenceStartOffset == 0)
  }

  @Test("A repeat on a part of the day repeats every day, and an hour with it takes that part")
  func repeatedPartsOfDay() {
    let lines: [(text: String, title: String, minutes: Int?)] = [
      ("யோகா தினமும் காலை 6 மணிக்கு", "யோகா", 6 * 60), ("தினமும் காலை 6 மணிக்கு யோகா", "யோகா", 6 * 60),
      ("ஒவ்வொரு மாலை 7 மணிக்கு நடைப்பயிற்சி", "நடைப்பயிற்சி", 19 * 60),
      ("நடைப்பயிற்சி ஒவ்வொரு மாலை 7 மணிக்கு", "நடைப்பயிற்சி", 19 * 60),
      ("ஒவ்வொரு இரவு 10:30 மணிக்கு மருந்து", "மருந்து", 22 * 60 + 30), ("ஒவ்வொரு காலை 5 மணிக்கு யோகா", "யோகா", 5 * 60),
      ("தினசரி காலை 6 மணிக்கு யோகா", "யோகா", 6 * 60), ("தினமும் மாலை 7 மணிக்கு நடைப்பயிற்சி", "நடைப்பயிற்சி", 19 * 60),
      ("ஒவ்வொரு இரவு புத்தகம் படி", "புத்தகம் படி", nil), ("தினமும் காலை யோகா", "யோகா", nil),
      ("தினமும் இரவு 10 மணிக்கு மருந்து", "மருந்து", 22 * 60), ("ஒவ்வொரு காலையும் 6 மணிக்கு யோகா", "யோகா", 6 * 60),
      ("தினந்தோறும் காலையில் 6 மணிக்கு யோகா", "யோகா", 6 * 60),
    ]
    for line in lines {
      let parsed = parse(line.text)
      #expect(parsed.recurrence == daily, "\(line.text): repeat")
      #expect(parsed.startMinutes == line.minutes, "\(line.text): time")
      #expect(parsed.title == line.title, "\(line.text): title")
    }
    let range = parse("தினமும் காலை 9 முதல் 11 வரை படிப்பு")
    #expect(range.recurrence == daily)
    #expect(range.startMinutes == 9 * 60)
    #expect(range.estimatedMinutes == 120)
    #expect(range.title == "படிப்பு")
    // A range right after a part of the day that a repeat or "இந்த" owns is read in that part.
    let evening = parse("ஒவ்வொரு மாலை 5 முதல் 7 வரை நடை")
    #expect(evening.recurrence == daily)
    #expect(evening.startMinutes == 17 * 60)
    #expect(evening.estimatedMinutes == 120)
    #expect(evening.title == "நடை")
    let today = parse("இந்த மாலை 5 முதல் 7 வரை நடை")
    #expect(today.plannedDayOffset == 0)
    #expect(today.startMinutes == 17 * 60)
    #expect(today.estimatedMinutes == 120)
    #expect(today.title == "நடை")
    // Two bare numbers with a part of the day elsewhere in the line stay numbers.
    expectLinesUnread(["நடை 3 முதல் 5 வரை", "காலை படிப்பு 9 முதல் 11 வரை"], languages: ["ta"])
    // A line of details alone is no task.
    expectLinesUnread(["ஒவ்வொரு காலை 6 மணிக்கு", "ஒவ்வொரு மாலை 7 மணிக்கு"], languages: ["ta"])
  }

  @Test("A day of the month repeats every month")
  func monthDays() {
    let rule = TaskRecurrenceRule(freq: .monthly, byMonthDay: [5])
    for text in [
      "வாடகை ஒவ்வொரு மாதமும் 5ஆம் தேதி", "வாடகை ஒவ்வொரு மாதம் 5ஆம் தேதி", "வாடகை ஒவ்வொரு மாதமும் 5ஆம் தேதியில்",
      "வாடகை மாதந்தோறும் 5ஆம் தேதி", "வாடகை மாதந்தோறும் 5ஆம் தேதியன்று", "வாடகை 5ஆம் தேதி ஒவ்வொரு மாதமும்",
      "வாடகை ஒவ்வொரு மாதமும் 5 தேதி", "வாடகை ஒவ்வொரு மாதமும் 5ம் தேதி", "வாடகை ஒவ்வொரு மாதமும் 5-ஆம் தேதி",
      "வாடகை மாதம் தோறும் 5ஆம் தேதிக்கு",
    ] {
      let parsed = parse(text)
      #expect(parsed.recurrence == rule, "\(text)")
      #expect(parsed.recurrenceStartOffset == 13, "\(text): start")
      #expect(parsed.title == "வாடகை", "\(text): title")
    }
    for text in ["வாடகை ஒவ்வொரு மாதமும் 1ஆம் தேதி", "வாடகை ஒவ்வொரு மாதமும் முதல் தேதி"] {
      let first = parse(text)
      #expect(first.recurrence == TaskRecurrenceRule(freq: .monthly, byMonthDay: [1]), "\(text)")
      #expect(first.recurrenceStartOffset == 9, "\(text): start")
    }
    // A date with its month name is a date, not a repeat.
    #expect(parse("வாடகை ஒவ்வொரு 5 மே").recurrence == nil)
  }

  @Test("A repeat shorter than a day, and a cadence word that describes a noun, are no repeat")
  func notRepeats() {
    expectLinesUnread(
      [
        "தண்ணீர் குடி ஒவ்வொரு 2 மணி நேரத்திற்கும்", "ஒவ்வொரு 2 மணி நேரத்திற்கு தண்ணீர் குடி",
        "தண்ணீர் குடி ஒவ்வொரு 2 மணிக்கு", "வாரத்திற்கு இரண்டு முறை ஜிம்", "நாளுக்கு மூன்று முறை மருந்து",
        "வாராந்திர அறிக்கை", "மாதாந்திர சம்பளம்", "தினசரி அறிக்கை", "வருடாந்திர செலவுகள்", "தினசரி மீள்பார்வை",
        "வாராந்தர மீள்பார்வை", "வாரத்தில் ஒருமுறை", "ஒவ்வொரு பணியும் முடிந்தது", "ஒரு நாளைக்கு 3 முறை",
        // A count of weekends, workdays, or Mondays, the second Monday, and a genitive.
        "3 வார இறுதிகளில் மலையேற்றம்", "3 வேலை நாட்களில் ஸ்டாண்டப்", "3 திங்கட்கிழமைகளில் ஜிம்",
        "மூன்று திங்கட்கிழமைகளில் ஜிம்", "ஒவ்வொரு இரண்டாவது திங்கட்கிழமை ஜிம்",
        "ஒவ்வொரு திங்கட்கிழமையின் கூட்டம்",
        // The nouns for the working days name them.
        "ஜிம் வேலை நாள்", "ஜிம் வார நாள்",
      ], languages: ["ta"])
    // ஒவ்வொரு with a unit is a repeat whatever noun follows: a monthly task.
    let accounts = parse("ஒவ்வொரு மாதமும் செலவு கணக்கு")
    #expect(accounts.recurrence == TaskRecurrenceRule(freq: .monthly))
    #expect(accounts.title == "செலவு கணக்கு")
  }

  // MARK: - Priorities

  @Test("Priorities: அதிக, இயல்பான, and குறைந்த முன்னுரிமை, and the words for urgent at the end or before a colon")
  func priorities() {
    let levels: [(text: String, priority: LorvexTask.Priority)] = [
      ("அதிக முன்னுரிமை", .p1), ("உயர் முன்னுரிமை", .p1), ("உயர்ந்த முன்னுரிமை", .p1), ("அதிகபட்ச முன்னுரிமை", .p1),
      ("உச்ச முன்னுரிமை", .p1), ("முன்னுரிமை: அதிகம்", .p1), ("முன்னுரிமை அதிகம்", .p1), ("முன்னுரிமை: உயர்வு", .p1),
      ("முன்னுரிமை: முதன்மை", .p1), ("இயல்பான முன்னுரிமை", .p2), ("நடுத்தர முன்னுரிமை", .p2),
      ("மிதமான முன்னுரிமை", .p2), ("சாதாரண முன்னுரிமை", .p2), ("வழக்கமான முன்னுரிமை", .p2),
      ("மீடியம் முன்னுரிமை", .p2), ("நார்மல் முன்னுரிமை", .p2), ("முன்னுரிமை: இயல்பு", .p2),
      ("முன்னுரிமை: நடுத்தரம்", .p2), ("குறைந்த முன்னுரிமை", .p3), ("குறைவான முன்னுரிமை", .p3),
      ("குறைந்தபட்ச முன்னுரிமை", .p3), ("தாழ்ந்த முன்னுரிமை", .p3), ("முன்னுரிமை: குறைவு", .p3),
      ("முன்னுரிமை குறைவு", .p3), ("முன்னுரிமை: குறைந்தபட்சம்", .p3), ("முன்னுரிமை: தாழ்ந்த", .p3),
    ]
    for level in levels {
      let text = "அறிக்கையை அனுப்பு \(level.text)"
      let parsed = parse(text)
      #expect(parsed.priority == level.priority, "\(text)")
      #expect(parsed.title == "அறிக்கையை அனுப்பு", "\(text): title")
      #expect(parsed.phrases.map(\.kind) == [.priority], "\(text): phrase kind")
    }
    let inside = parse("அறிக்கை அதிக முன்னுரிமை அனுப்பு")
    #expect(inside.priority == .p1)
    #expect(inside.title == "அறிக்கை அனுப்பு")

    for word in [
      "அவசரம்", "அவசரமாக", "முக்கியம்", "முக்கியமானது", "அர்ஜென்ட்", "அர்ஜெண்ட்", "அர்ஜன்ட்", "மிகவும் முக்கியம்",
      "மிக முக்கியம்", "அதி முக்கியம்", "மிகவும் அவசரம்",
    ] {
      let text = "அறிக்கையை அனுப்பு \(word)"
      #expect(parse(text).priority == .p1, "\(text)")
      #expect(parse(text).title == "அறிக்கையை அனுப்பு", "\(text): title")
    }
    for word in ["அவசரம்", "முக்கியம்", "அர்ஜென்ட்"] {
      for separator in [":", ","] {
        let text = "\(word)\(separator) அறிக்கையை அனுப்பு"
        #expect(parse(text).priority == .p1, "\(text)")
        #expect(parse(text).title == "அறிக்கையை அனுப்பு", "\(text): title")
      }
    }
    #expect(parse("அறிக்கையை அனுப்பு அவசரம்.").title == "அறிக்கையை அனுப்பு.")
    // An urgent word in the middle, or opening the line with no colon or
    // comma, is a word of the title, and so is a level that describes a noun.
    expectLinesUnread(
      [
        "அவசர சிகிச்சைப் பிரிவுக்குச் செல்", "அறிக்கை முக்கியம் இல்லை", "அவசர அறிக்கை அனுப்பு", "அவசரமாக அறிக்கை",
        "முக்கியமான கூட்டம் இருக்கிறது", "அறிக்கை அனுப்பு முக்கியமான விஷயம்", "அதிக முன்னுரிமை உள்ள பணிகள்",
        "குறைந்த முன்னுரிமையுடன் அறிக்கை", "அதிக முன்னுரிமை கொண்ட பட்டியல்",
      ], languages: ["ta"])
  }

  // MARK: - Combined lines and words that look like details

  @Test("A line may hold a day, a time, a length, a repeat, a priority, and a tag")
  func combined() {
    let line = parse("நாளை மாலை 5 மணிக்கு 30 நிமிட கூட்டம் #வேலை")
    #expect(line.title == "கூட்டம்")
    #expect(line.plannedDayOffset == 1)
    #expect(line.startMinutes == 17 * 60)
    #expect(line.estimatedMinutes == 30)
    #expect(line.tags == ["வேலை"])
    #expect(line.phrases.map(\.kind) == [.when, .time, .length, .tag])
    #expect(line.phrases.map(\.text) == ["நாளை", "மாலை 5 மணிக்கு", "30 நிமிட", "#வேலை"])

    let lines: [(text: String, title: String)] = [
      ("ஒவ்வொரு திங்கட்கிழமை காலை 9 மணிக்கு ஜிம்", "ஜிம்"),
      ("வெள்ளிக்கிழமை வரை அறிக்கையை அனுப்பு அவசரம்", "அறிக்கையை அனுப்பு"),
      ("திங்கள் காலை 9 முதல் 11 வரை கூட்டம்", "கூட்டம்"), ("5 மே மாலை 6 மணிக்கு விருந்து", "விருந்து"),
      ("வரும் வெள்ளிக்கிழமை வரை 2 மணி நேர வேலை", "வேலை"), ("நாளை கூட்டம் 3 மணிக்கு அதிக முன்னுரிமை", "கூட்டம்"),
      ("தினமும் காலை 7 மணிக்கு மருந்து", "மருந்து"), ("இன்று இரவு 11 மணிக்கு தூக்கம்", "தூக்கம்"),
      ("அம்மாவை அழை நாளை மாலை 5 மணிக்கு", "அம்மாவை அழை"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
      #expect(parse(line.text).phrases.count >= 2, "\(line.text): phrases")
    }
    let friday = parse("வெள்ளிக்கிழமை வரை அறிக்கையை அனுப்பு அவசரம்")
    #expect(friday.dueDayOffset == 3)
    #expect(friday.priority == .p1)
    let weekly = parse("ஒவ்வொரு திங்கட்கிழமை காலை 9 மணிக்கு ஜிம்")
    #expect(weekly.recurrence == monday)
    #expect(weekly.startMinutes == 9 * 60)
    let report = parse("வரும் வெள்ளிக்கிழமை வரை 2 மணி நேர வேலை")
    #expect(report.dueDayOffset == 3)
    #expect(report.estimatedMinutes == 120)
  }

  @Test("Words that look like details stay in the title")
  func falsePositives() {
    expectLinesUnread(
      [
        // The bare weekday names that are planets and metals.
        "செவ்வாய் கிரகத்தைப் பார்", "சனி பகவான் கோவிலுக்குப் போ", "வெள்ளி நகை வாங்கு", "புதன் கிரகம் பார்",
        "வியாழன் கிரகம் பார்",
        // Words that contain a day word, or a day word with another ending.
        "செவ்வாய்க்கிழமைகள்", "நாளைய செய்திகள்", "இன்றைய கூட்டம்",
        // A day with a genitive after it is an attribute of a noun.
        "திங்கட்கிழமையின் கூட்டம்", "நாளைய கூட்டம்",
        // The determiners and numerals that make நாளை a form of நாள் (day).
        "ஒரு நாளைக்கு 3 முறை மருந்து சாப்பிடு", "இந்த நாளை நினைவில் வை",
        // The past days are never read.
        "நேற்று கூட்டம்", "நேத்து கூட்டம்", "முந்தாநாள் கூட்டம்",
        // A hyphen between two Tamil words joins them, so neither side is a day.
        "நாளை-கூட்டம்", "கூட்டம்-நாளை",
        // The Someday list, the word for hour alone, and the words for date and day.
        "புத்தகம் படிக்க வேண்டும் என்றாவது ஒரு நாள்", "மணி அடி", "தேதி எழுது", "நாள் குறிப்பு",
        // A bare number that is a count.
        "5 புத்தகங்கள் வாங்கு", "3 நண்பர்களை அழை",
      ], languages: ["ta"])
    // Tamil written in Latin letters is not read.
    expectLinesUnread(
      [
        "naalai kaalai 9 manikku koottam", "innaikku jim", "thinamum jim", "2 mani neram ezhuthu",
        "velli kizhamai varai report",
      ], languages: ["ta"])
    // A weekday before other words is the day.
    let friday = parse("வெள்ளிக்கிழமை விருந்து ஏற்பாடுகள்")
    #expect(friday.plannedDayOffset == 3)
    #expect(friday.title == "விருந்து ஏற்பாடுகள்")
  }

  // MARK: - The past

  @Test("A line in the past tense or after a past word stays unread, and no past day is ever read")
  func tomorrowOrYesterday() {
    let coming = [
      "நாளை கூட்டம் இருக்கிறது", "நாளை செல்ல வேண்டும்", "நாளை கூட்டம் நடக்கும்", "அறிக்கை நாளை அனுப்பு",
      "நாளை முதல் ஜிம் தொடக்கம்",
    ]
    for text in coming {
      #expect(parse(text).plannedDayOffset == 1, "\(text)")
    }
    expectLinesUnread(
      [
        // The past days are never read.
        "நேற்று கூட்டம்", "முந்தாநாள் கூட்டம்", "நேற்று காலக்கெடு",
        // The words that say a day is past, or the month's first, second, or last.
        "கடந்த வெள்ளிக்கிழமை கூட்டம்", "சென்ற வெள்ளிக்கிழமை கூட்டம்", "போன வெள்ளிக்கிழமை கூட்டம்",
        "முந்தைய திங்கட்கிழமை கூட்டம்", "அந்த வெள்ளிக்கிழமை கூட்டம்", "கடைசி வெள்ளிக்கிழமை விருந்து",
        "இறுதி வெள்ளிக்கிழமை விருந்து", "முதல் வெள்ளிக்கிழமை கூட்டம்", "இரண்டாவது சனிக்கிழமை விடுமுறை",
        "மூன்றாவது சனிக்கிழமை விடுமுறை", "நான்காவது சனிக்கிழமை விடுமுறை",
        // A past-tense form anywhere in the line.
        "நாளை கூட்டம் நடந்தது", "நாளை சென்றேன்", "இன்று போன் செய்தேன்", "வெள்ளிக்கிழமை அவர் வந்தார்",
        "இன்று கூட்டம் முடிந்தது", "வெள்ளிக்கிழமை கூட்டம் நடந்தது", "நாளை மறுநாள் சந்தித்தோம்",
        "வெள்ளிக்கிழமை அறிக்கை அனுப்பினேன்", "இன்று நாங்கள் பார்த்தோம்", "திங்கள் போன் செய்தேன்",
        "வெள்ளிக்கிழமை புத்தகம் படித்தேன்", "இன்று பால் வாங்கினேன்", "திங்கள் பணம் கொடுத்தேன்",
        "நாளை கடிதம் எழுதினேன்", "இன்று பேசினேன்",
      ], languages: ["ta"])
    // "கடந்த வெள்ளிக்கிழமை" is a past day, but "வெள்ளிக்கிழமைக்குள்" is a deadline.
    #expect(parse("அறிக்கை வெள்ளிக்கிழமைக்குள்").dueDayOffset == 3)
    #expect(parse("அறிக்கை நாளைக்குள்").dueDayOffset == 1)
  }

  @Test("A few collisions with ordinary words are accepted")
  func acceptedCollisions() {
    // ஒவ்வொரு also means a rate: a price per day reads as a repeat.
    let price = parse("ஒவ்வொரு நாளும் 500 ரூபாய்")
    #expect(price.recurrence == daily)
    #expect(price.title == "500 ரூபாய்")
    // An hour from 1 to 6 with no part of the day is the afternoon.
    #expect(parse("கூட்டம் 5 மணிக்கு").startMinutes == 17 * 60)
    // An hour count written with a Latin unit is English's length, even after ஒவ்வொரு.
    let hours = parse("மருந்து சாப்பிடு ஒவ்வொரு 2h")
    #expect(hours.estimatedMinutes == 120)
    // An urgent word at the end of a line is the priority, whatever else it says.
    #expect(parse("இந்த வேலை முக்கியம்").priority == .p1)
    #expect(parse("இந்த வேலை அவசரம்").priority == .p1)
    // The app's own words for tasks that no longer fit today and tomorrow name a day.
    let today = parse("இன்றைக்குப் பொருந்தாத பணிகள்")
    #expect(today.plannedDayOffset == 0)
    #expect(today.title == "பொருந்தாத பணிகள்")
    let tomorrow = parse("நாளைக்குப் பொருந்தாத பணிகள்")
    #expect(tomorrow.plannedDayOffset == 1)
    #expect(tomorrow.title == "பொருந்தாத பணிகள்")
    // The first day phrase of a line is the day.
    let first = parse("இன்று இல்லை நாளை கூட்டம்")
    #expect(first.plannedDayOffset == 0)
    #expect(first.title == "இல்லை நாளை கூட்டம்")
    // வெள்ளி is silver and Friday: with no planet or metal word after it, it is the day.
    let silver = parse("வெள்ளி வாங்கு")
    #expect(silver.plannedDayOffset == 3)
    #expect(silver.title == "வாங்கு")
    // The past-tense forms are a finite list of common verbs, so a past statement with another verb
    // still reads as a plan.
    let started = parse("வெள்ளிக்கிழமை கூட்டம் தொடங்கியது")
    #expect(started.plannedDayOffset == 3)
    #expect(started.title == "கூட்டம் தொடங்கியது")
  }

  // MARK: - Doubled consonants, scripts, and spellings

  @Test("A consonant that doubles before the next word is read with the word it ends")
  func sandhi() {
    let lines: [(text: String, title: String, offset: Int, phrase: String)] = [
      ("இந்தச் செவ்வாய் கூட்டம்", "கூட்டம்", 0, "இந்தச் செவ்வாய்"),
      ("இந்தச் சனிக்கிழமை கூட்டம்", "கூட்டம்", 4, "இந்தச் சனிக்கிழமை"),
      ("அடுத்தச் சனி கூட்டம்", "கூட்டம்", 11, "அடுத்தச் சனி"),
      ("அடுத்தச் செவ்வாய் கூட்டம்", "கூட்டம்", 7, "அடுத்தச் செவ்வாய்"),
      ("இந்தக் காலை படிப்பு", "படிப்பு", 0, "இந்தக் காலை"),
      ("நாளைக் காலை கூட்டம்", "கூட்டம்", 1, "நாளைக் காலை"),
      ("நாளைக்குத் தள்ளிவை", "தள்ளிவை", 1, "நாளைக்குத்"),
      ("நாளைக்குத் தள்ளிவை கூட்டம்", "தள்ளிவை கூட்டம்", 1, "நாளைக்குத்"),
      ("இன்றைக்குத் தொடங்கு", "தொடங்கு", 0, "இன்றைக்குத்"),
      ("இன்னைக்குத் துணி துவை", "துணி துவை", 0, "இன்னைக்குத்"),
      ("இன்னிக்குப் படி", "படி", 0, "இன்னிக்குப்"),
      ("ஒரு நாள் கழித்துத் திட்டமிடு", "திட்டமிடு", 1, "ஒரு நாள் கழித்துத்"),
      ("வெள்ளிக்குப் போ", "போ", 3, "வெள்ளிக்குப்"),
      ("5 மணிக்குத் தொடங்கு", "தொடங்கு", -1, "5 மணிக்குத்"),
    ]
    for line in lines {
      let parsed = parse(line.text)
      if line.offset >= 0 {
        #expect(parsed.plannedDayOffset == line.offset, "\(line.text): planned day")
      } else {
        #expect(parsed.startMinutes == 17 * 60, "\(line.text): start")
      }
      #expect(parsed.title == line.title, "\(line.text): title")
      #expect(parsed.phrases.map(\.text) == [line.phrase], "\(line.text): phrase")
    }
    // "இந்த" and "அடுத்த" with the doubled consonant keep their meaning, and "அந்த",
    // "எந்த", and "எல்லா" with it still point at no coming day.
    expectLinesUnread(
      ["அந்தச் செவ்வாய் கூட்டம்", "எந்தச் செவ்வாய் கூட்டம்", "எல்லாச் செவ்வாய் கூட்டம்", "கடந்த செவ்வாய் கூட்டம்"],
      languages: ["ta"])
    // A consonant that has no word to double before is not read.
    expectLinesUnread(["இந்தச் வாரம்", "நாளைக்குத்"], languages: ["ta"])
  }

  @Test("The two-part vowel signs read as one sign or as the two signs they are made of")
  func vowelSigns() {
    // ொ (U+0BCA) is ெ (U+0BC6) and ா (U+0BBE); ோ (U+0BCB) is ே (U+0BC7) and ா (U+0BBE).
    let oForms = ["\u{0BCA}", "\u{0BC6}\u{0BBE}"]
    let ooForms = ["\u{0BCB}", "\u{0BC7}\u{0BBE}"]
    for form in oForms {
      let scalars = form.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      // ஒவ்வொரு
      #expect(parse("ஜிம் ஒவ்வ\(form)ரு திங்கட்கிழமை").recurrence == monday, "ஒவ்வொரு: \(scalars)")
      #expect(parse("ஜிம் ஒவ்வ\(form)ரு வாரமும் திங்கள்").recurrence == monday, "ஒவ்வொரு வாரமும்: \(scalars)")
    }
    for form in ooForms {
      let scalars = form.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
      // அக்டோபர், தினந்தோறும், வாரந்தோறும்
      #expect(
        parse("அம்மாவை அழை 5 அக்ட\(form)பர்").plannedDayOffset == captureDayOffset("2026-10-05"),
        "அக்டோபர்: \(scalars)")
      #expect(parse("மருந்து சாப்பிடு தினந்த\(form)றும்").recurrence == daily, "தினந்தோறும்: \(scalars)")
      #expect(
        parse("மருந்து சாப்பிடு வாரந்த\(form)றும்").recurrence == TaskRecurrenceRule(freq: .weekly),
        "வாரந்தோறும்: \(scalars)")
    }
  }

  @Test("Spelling variants of the same word read alike")
  func spellingVariants() {
    // காலை and காலையில், மார்ச் and மார்ச்சு, ஆகஸ்ட் and ஆகஸ்டு, ஜூன் and ஜுன், ஜூலை and ஜுலை,
    // பிப்ரவரி and பெப்ரவரி, ஏப்ரல் and ஏப்ரில், செப்டம்பர் and செப்டெம்பர், ஐந்து and அஞ்சு, இரண்டு and
    // ரெண்டு, நான்கு and நாலு, மூன்று and மூணு, ஒன்பது and ஒம்பது, இன்றைக்கு and இன்னைக்கு and இன்னிக்கு,
    // நிமிடங்கள் and நிமிஷங்கள், மணி நேரம் and மணிநேரம், சாயங்காலம் and சாயந்திரம், ராத்திரி and இராத்திரி,
    // வாராந்திர and வாராந்தர, திங்கட்கிழமை and திங்கள்கிழமை, வீக்கெண்ட் and வீக்எண்ட், அர்ஜென்ட் and
    // அர்ஜெண்ட் and அர்ஜன்ட்.
    let pairs: [(String, String)] = [
      ("கூட்டம் காலை 9 மணிக்கு", "கூட்டம் காலையில் 9 மணிக்கு"),
      ("அம்மாவை அழை 5 மார்ச்", "அம்மாவை அழை 5 மார்ச்சு"), ("அம்மாவை அழை 5 ஆகஸ்ட்", "அம்மாவை அழை 5 ஆகஸ்டு"),
      ("அம்மாவை அழை 5 ஜூன்", "அம்மாவை அழை 5 ஜுன்"), ("அம்மாவை அழை 5 ஜூலை", "அம்மாவை அழை 5 ஜுலை"),
      ("அம்மாவை அழை 5 பிப்ரவரி", "அம்மாவை அழை 5 பெப்ரவரி"),
      ("அம்மாவை அழை 5 ஏப்ரல்", "அம்மாவை அழை 5 ஏப்ரில்"),
      ("அம்மாவை அழை 5 செப்டம்பர்", "அம்மாவை அழை 5 செப்டெம்பர்"),
      ("கூட்டம் ஐந்து மணிக்கு", "கூட்டம் அஞ்சு மணிக்கு"), ("கூட்டம் இரண்டு மணிக்கு", "கூட்டம் ரெண்டு மணிக்கு"),
      ("கூட்டம் நான்கு மணிக்கு", "கூட்டம் நாலு மணிக்கு"), ("கூட்டம் மூன்று மணிக்கு", "கூட்டம் மூணு மணிக்கு"),
      ("கூட்டம் ஒன்பது மணிக்கு", "கூட்டம் ஒம்பது மணிக்கு"),
      ("அம்மாவை அழை இன்றைக்கு", "அம்மாவை அழை இன்னைக்கு"), ("அம்மாவை அழை இன்றைக்கு", "அம்மாவை அழை இன்னிக்கு"),
      ("அறிக்கை எழுது 30 நிமிடங்கள்", "அறிக்கை எழுது 30 நிமிஷங்கள்"),
      ("அறிக்கை எழுது 2 மணி நேரம்", "அறிக்கை எழுது 2 மணிநேரம்"),
      ("கூட்டம் சாயங்காலம் 7 மணிக்கு", "கூட்டம் சாயந்திரம் 7 மணிக்கு"),
      ("கூட்டம் இரவு 10 மணிக்கு", "கூட்டம் ராத்திரி 10 மணிக்கு"), ("கூட்டம் ராத்திரி 10 மணிக்கு", "கூட்டம் இராத்திரி 10 மணிக்கு"),
      ("அறிக்கை வாராந்திர", "அறிக்கை வாராந்தர"), ("ஜிம் ஒவ்வொரு திங்கட்கிழமை", "ஜிம் ஒவ்வொரு திங்கள்கிழமை"),
      ("அம்மாவை அழை வீக்கெண்ட்", "அம்மாவை அழை வீக்எண்ட்"),
      ("அறிக்கையை அனுப்பு அர்ஜென்ட்", "அறிக்கையை அனுப்பு அர்ஜெண்ட்"),
      ("அறிக்கையை அனுப்பு அர்ஜென்ட்", "அறிக்கையை அனுப்பு அர்ஜன்ட்"),
      ("கூட்டம் அரை மணி நேரம்", "கூட்டம் அரைமணி நேரம்"), ("கூட்டம் நடு இரவு", "கூட்டம் நடுஇரவு"),
    ]
    for (first, second) in pairs {
      let one = parse(first)
      let other = parse(second)
      #expect(one.plannedDayOffset == other.plannedDayOffset, "\(first) / \(second): planned day")
      #expect(one.startMinutes == other.startMinutes, "\(first) / \(second): start")
      #expect(one.estimatedMinutes == other.estimatedMinutes, "\(first) / \(second): length")
      #expect(one.recurrence == other.recurrence, "\(first) / \(second): repeat")
      #expect(one.priority == other.priority, "\(first) / \(second): priority")
      #expect(one.phrases.map(\.kind) == other.phrases.map(\.kind), "\(first) / \(second): phrases")
      #expect(!one.phrases.isEmpty, "\(first): is read")
    }
  }

  @Test("A zero-width joiner or non-joiner after a pulli, or before an ending glued to a digit, a Latin name, or a month, changes nothing")
  func joiners() {
    for joiner in ["\u{200C}", "\u{200D}"] {
      let scalar = joiner.unicodeScalars.map { String($0.value, radix: 16) }.joined()
      #expect(
        parse("அம்மாவை அழை அக்டோபர் 15\(joiner)க்கு").plannedDayOffset == captureDayOffset("2026-10-15"),
        "அக்டோபர் 15க்கு: \(scalar)")
      #expect(parse("கூட்டம் மாலை 5\(joiner)க்கு").startMinutes == 17 * 60, "5க்கு: \(scalar)")
      #expect(parse("கூட்டம் 3:30 PM\(joiner)க்கு").startMinutes == 15 * 60 + 30, "PMக்கு: \(scalar)")
      #expect(parse("கூட்டம் 17:30\(joiner)க்கு").startMinutes == 17 * 60 + 30, "17:30க்கு: \(scalar)")
      #expect(
        parse("அம்மாவை அழை 15 அக்டோபர்\(joiner) முதல்").plannedDayOffset == captureDayOffset("2026-10-15"),
        "அக்டோபர் முதல்: \(scalar)")
      #expect(
        parse("அம்மாவை அழை அக்டோபர்\(joiner) 15").plannedDayOffset == captureDayOffset("2026-10-15"),
        "அக்டோபர் 15: \(scalar)")
      #expect(parse("ஜிம் ஒவ்\(joiner)வொரு திங்கட்கிழமை").recurrence == monday, "ஒவ்வொரு: \(scalar)")
      #expect(parse("ஜிம் ஒவ்வொரு திங்\(joiner)கட்கிழமை").recurrence == monday, "திங்கட்கிழமை: \(scalar)")
      #expect(parse("அம்மாவை அழை வெள்\(joiner)ளிக்கிழமை").plannedDayOffset == 3, "வெள்ளிக்கிழமை: \(scalar)")
      #expect(parse("அம்மாவை அழை வீக்\(joiner)கெண்ட்").plannedDayOffset == 4, "வீக்கெண்ட்: \(scalar)")
      #expect(parse("அம்மாவை அழை வீக்கெண்ட்\(joiner)இல்").plannedDayOffset == 4, "வீக்கெண்ட்இல்: \(scalar)")
    }
    // A joiner that touches a finished word makes it part of a longer word.
    expectLinesUnread(
      [
        "நாளை\u{200C} கூட்டம்", "5 மணிக்கு\u{200C} கூட்டம்", "இன்று\u{200C} கூட்டம்",
        "வெள்ளிக்கிழமை\u{200D} கூட்டம்", "ஒவ்வொரு\u{200D} நாள் ஜிம்", "ஒவ்வொரு\u{200C} வாரமும் ஜிம்",
      ], languages: ["ta"])
    // The title keeps the joiner as typed.
    let typed = "வொர்க்\u{200C}ஷாப் ஏற்பாடுகள்"
    #expect(Array(parse("\(typed) நாளை").title.unicodeScalars) == Array(typed.unicodeScalars))
  }

  @Test("The composed and the decomposed forms of a line read the same")
  func normalizationForms() {
    let lines = [
      "நாளை காலை கூட்டம் 6 மணிக்கு", "அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரை", "அம்மாவை அழை 5 பிப்ரவரி",
      "மருந்து சாப்பிடு ஒவ்வொரு 2 வாரங்களுக்கும்", "கூட்டம் ஐந்தரைக்கு", "அறிக்கையை அனுப்பு அவசரம்",
      "அம்மாவை அழை 5 ஜூலை", "அறிக்கை எழுது இருபது நிமிடங்கள்", "அறிக்கை எழுது முப்பது நிமிடங்கள்",
      "அறிக்கை எழுது நாற்பத்தைந்து நிமிடங்கள்", "ஜிம் ஒவ்வொரு திங்கட்கிழமை", "அறிக்கையை அனுப்பு காலக்கெடு: 5 மே",
      "விடுமுறை 3 முதல் 5 மார்ச்", "தினமும் காலை 6 மணிக்கு யோகா", "அறிக்கையை அனுப்பு அதிக முன்னுரிமை",
      "அம்மாவை அழை 3 நாட்களில்", "கூட்டம் மாலை 5க்கு", "அறிக்கை எழுது இரண்டரை மணி நேரம்",
      "அறிக்கையை அனுப்பு 5 ஜூலை வரை", "அம்மாவை அழை அக்டோபர் 15", "ஜிம் ஒவ்வொரு வார இறுதியும்",
      "அம்மாவை அழை 5 அக்டோபர்", "மருந்து சாப்பிடு தினந்தோறும்", "மருந்து சாப்பிடு வாரந்தோறும்",
      "கூட்டம் இரவு 10 மணிக்கு", "கூட்டம் நள்ளிரவு", "ஜிம் ஒவ்வொரு திங்கள் முதல் வெள்ளி வரை",
      "அம்மாவை அழை இந்தச் செவ்வாய்", "நாளைக்குத் தள்ளிவை", "அம்மாவை அழை வீக்கெண்ட்",
    ]
    for line in lines {
      let expected = parse(line)
      #expect(!expected.phrases.isEmpty, "\(line): is read")
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

  @Test("Tamil digits and Western digits read the same")
  func digitScripts() {
    let lines = [
      "கூட்டம் மாலை 5:30 மணிக்கு", "கூட்டம் காலை 9க்கு", "அறிக்கை எழுது 20 நிமிடங்கள்", "அறிக்கை எழுது 1.5 மணி நேரம்",
      "அறிக்கை எழுது 1 மணி நேரம் 30 நிமிடங்கள்", "மருந்து சாப்பிடு ஒவ்வொரு 3 நாட்களுக்கும்",
      "வாடகை ஒவ்வொரு மாதமும் 5ஆம் தேதி", "சபை 5 மார்ச் 2027", "அம்மாவை அழை 3 நாட்களில்", "விடுமுறை 3 முதல் 5 மார்ச்",
      "விடுமுறை 3-5 மார்ச்", "அறிக்கையை அனுப்பு 5 மார்ச் வரை", "அம்மாவை அழை 2 மாதங்களில்",
      "அம்மாவை அழை 15/10/2026", "கூட்டம் 17:30க்கு", "கூட்டம் காலை 10 மணி 30 நிமிடத்திற்கு",
      "கூட்டம் 14:00 முதல் 16:00 வரை", "அம்மாவை அழை அக்டோபர் 15க்கு", "கூட்டம் 9-11 மணிக்கு",
      "அம்மாவை அழை 15ஆம் தேதி", "அம்மாவை அழை 15.10.2026", "அம்மாவை அழை 15 அக்.",
      "அறிக்கை எழுது 2 மணி நேரத்திற்கு", "கூட்டம் 5 மணி 30 நிமிடத்திற்கு",
    ]
    for line in lines {
      let latin = parse(line)
      #expect(latin.phrases.count == 1, "\(line): phrases")
      let converted = tamilDigits(line)
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
    let typed = parse("௩ பேருடன் கூட்டம் நாளை")
    #expect(typed.plannedDayOffset == 1)
    #expect(typed.title == "௩ பேருடன் கூட்டம்")
  }

  @Test("The title keeps the letters and signs as they were typed")
  func titleKeepsTypedText() {
    // A precomposed vowel sign in the title stays one code point, and a decomposed one stays two.
    for typed in ["கொடி", "க\u{0BC6}\u{0BBE}டி", "கோடு", "க\u{0BC7}\u{0BBE}டு"] {
      let parsed = parse("\(typed) நாளை")
      #expect(parsed.plannedDayOffset == 1)
      #expect(parsed.priority == nil)
      #expect(Array(parsed.title.unicodeScalars) == Array(typed.unicodeScalars))
    }
    let digits = parse("5 புத்தகங்கள் வாங்கு நாளை")
    #expect(digits.title == "5 புத்தகங்கள் வாங்கு")
  }

  @Test("The comma and the colon left behind by a phrase do not stay in the title")
  func separators() {
    let lines: [(text: String, title: String)] = [
      ("அம்மாவை அழை, நாளை, மாலை 5 மணிக்கு", "அம்மாவை அழை"), ("அம்மாவை அழை நாளை.", "அம்மாவை அழை."),
      ("நாளை, அம்மாவை அழை", "அம்மாவை அழை"), ("நாளை: அம்மாவை அழை", "அம்மாவை அழை"),
      ("அம்மாவை அழை - நாளை", "அம்மாவை அழை"),
      ("அறிக்கையை அனுப்பு, வெள்ளிக்கிழமை வரை, அதிக முன்னுரிமை", "அறிக்கையை அனுப்பு"),
      ("பால், ரொட்டி, முட்டை நாளை வாங்கு", "பால், ரொட்டி, முட்டை வாங்கு"),
    ]
    for line in lines {
      #expect(parse(line.text).title == line.title, "\(line.text)")
    }
    // The full stop is punctuation: it ends a word.
    #expect(parse("அம்மாவை அழை நாளை.").plannedDayOffset == 1)
    #expect(parse("அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரை.").dueDayOffset == 3)
  }

  @Test("The examples of the capture hint are read")
  func hintExamples() {
    let day = parse("பணி நாளை")
    #expect(day.plannedDayOffset == 1)
    #expect(day.title == "பணி")
    let time = parse("பணி மாலை 5 மணிக்கு")
    #expect(time.startMinutes == 17 * 60)
    #expect(time.title == "பணி")
    let repeating = parse("பணி ஒவ்வொரு திங்கட்கிழமை")
    #expect(repeating.recurrence == monday)
    #expect(repeating.title == "பணி")
    let length = parse("பணி 20 நிமிடங்கள்")
    #expect(length.estimatedMinutes == 20)
    #expect(length.title == "பணி")
    #expect(parse("பணி #பட்டியல்").tags == ["பட்டியல்"])
  }

  @Test("The examples of the user guide table are read as the details they demonstrate")
  func guideExamples() {
    // Each example is typed with Latin digits, as the guide writes it, and with Tamil digits.
    func read(_ examples: [String]) -> [(example: String, parsed: LorvexCaptureParse)] {
      examples.flatMap { example in
        [example, tamilDigits(example)].map { (example: $0, parsed: parse("பணி \($0)")) }
      }
    }
    let days = [
      "இன்று", "இன்று இரவு", "நாளை", "நாளை காலை", "நாளை மறுநாள்", "திங்கட்கிழமை", "இந்த வெள்ளிக்கிழமை",
      "அடுத்த திங்கட்கிழமை", "அடுத்த வாரம்", "இந்த வார இறுதி", "3 நாட்களில்", "1 வாரம் கழித்து",
    ]
    for (example, parsed) in read(days) {
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let dates = [
      "5 மே", "5 மே 2027", "தேதி 5 மே", "15 அக்.", "15ஆம் தேதி", "15/10/2026", "15.10.", "திங்கட்கிழமை 5 அக்டோபர்",
    ]
    for (example, parsed) in read(dates) {
      #expect(parsed.plannedDayOffset != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let ranges = [
      "3 முதல் 5 மார்ச்", "3 மார்ச் முதல் 5 மார்ச் வரை", "30 ஜனவரி முதல் 2 பிப்ரவரி", "3-5 மார்ச்",
      "திங்கள் முதல் புதன் வரை",
    ]
    for (example, parsed) in read(ranges) {
      #expect(parsed.plannedDayOffset != nil && parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let due = [
      "வெள்ளிக்கிழமை வரை", "நாளை மாலை வரை", "5 மே வரை", "வெள்ளிக்கிழமைக்குள்", "நாளைக்குள்", "காலக்கெடு: 5 மே",
      "வெள்ளிக்கிழமை காலக்கெடு", "டெட்லைன் வெள்ளிக்கிழமை",
    ]
    for (example, parsed) in read(due) {
      #expect(parsed.dueDayOffset != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let times = [
      "5 மணிக்கு", "5:30 மணிக்கு", "ஐந்தரைக்கு", "ஒரு மணிக்கு", "மாலை 5 மணிக்கு", "இரவு 10 மணிக்கு", "காலை 9:30",
      "மாலை 5க்கு", "17:30க்கு", "நள்ளிரவு", "9 மணி முதல் 11 மணி வரை", "காலை 9 முதல் 11 வரை",
      "14:00 முதல் 16:00 வரை",
    ]
    for (example, parsed) in read(times) {
      #expect(parsed.startMinutes != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let repeats = [
      "தினமும்", "ஒவ்வொரு நாளும்", "தினமும் காலை", "ஒவ்வொரு திங்கட்கிழமை", "ஒவ்வொரு திங்கள் மற்றும் வியாழன்",
      "ஒவ்வொரு வாரமும்", "ஒவ்வொரு 2 நாட்களுக்கும்", "ஒவ்வொரு மாதமும்", "ஒவ்வொரு மாதமும் 5ஆம் தேதி",
      "ஒவ்வொரு வருடமும்", "ஒவ்வொரு வார இறுதியும்", "வேலை நாட்களில்", "ஒவ்வொரு திங்கள் முதல் வெள்ளி வரை",
      "2 நாட்களுக்கு ஒருமுறை", "வாரத்திற்கு ஒருமுறை", "வாரந்தோறும்",
    ]
    for (example, parsed) in read(repeats) {
      #expect(parsed.recurrence != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let lengths = [
      "30 நிமிடங்கள்", "2 மணி நேரம்", "1.5 மணி நேரம்", "1 மணி நேரம் 30 நிமிடங்கள்", "அரை மணி நேரம்",
      "கால் மணி நேரம்", "ஒன்றரை மணி நேரம்", "இரண்டரை மணி நேரம்", "இரண்டு மணி நேரம்", "2 மணி நேரத்திற்கு",
    ]
    for (example, parsed) in read(lengths) {
      #expect(parsed.estimatedMinutes != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    let priorities = [
      "அதிக முன்னுரிமை", "இயல்பான முன்னுரிமை", "குறைந்த முன்னுரிமை", "முன்னுரிமை: அதிகம்", "அவசரம்",
    ]
    for (example, parsed) in read(priorities) {
      #expect(parsed.priority != nil, "\(example)")
      #expect(parsed.title == "பணி", "\(example): title")
    }
    #expect(parse("அவசரம்: பணி").priority == .p1)
    let urgent = parse("அவசரம்: அறிக்கையை அனுப்பு")
    #expect(urgent.priority == .p1)
    #expect(urgent.title == "அறிக்கையை அனுப்பு")
    // The sentences of the guide.
    #expect(parse("ஒவ்வொரு நாளும் 500 ரூபாய்").recurrence == daily)
    #expect(parse("Sprint 12 - 20 மார்ச்").plannedDayOffset == captureDayOffset("2027-03-20"))
    #expect(parse("பணி 12-20 மார்ச்").dueDayOffset == captureDayOffset("2027-03-20"))
    #expect(parse("பணி காலை 10 மணி 30 நிமிடத்திற்கு").startMinutes == 10 * 60 + 30)
    expectLinesUnread(
      [
        "பணி 5/10", "பணி 31 ஏப்ரல்", "பணி 5 ஆடி", "பணி 5 முதல் 3 மார்ச்", "பணி 3 முதல் 5", "பணி 2 முதல் 3 மணி நேரம்",
        "பணி இந்த வாரம்", "செவ்வாய் கிரகத்தைப் பார்", "அவசர சிகிச்சைப் பிரிவுக்குச் செல்", "அறிக்கை முக்கியம் இல்லை",
        "பணி இன்று வரை", "பணி 5 மணி நேரம் கழித்து", "பணி இன்றைய", "பணி நாளைய", "ஐந்து புத்தகங்கள் வாங்கு",
        "பணி ஒரு நாளைக்கு 2 மணி நேரம்", "இன்றைய செய்திகள்", "மாலைத் தேநீர்", "வாராந்திர அறிக்கை",
      ], languages: ["ta"])
  }

  @Test("The phrases the app writes for a deadline, a priority, a repeat, and an hour can be typed back")
  func phrasesTheAppWrites() {
    // "%@ காலக்கெடு" with a day word, a weekday, or a date as the system writes it, and the label "காலக்கெடு: %@".
    let deadlines: [(text: String, offset: Int)] = [
      ("இன்று காலக்கெடு", 0), ("நாளை காலக்கெடு", 1), ("வெள்ளி காலக்கெடு", 3),
      ("15 அக். காலக்கெடு", captureDayOffset("2026-10-15")),
      ("15 அக்., 2027 காலக்கெடு", captureDayOffset("2027-10-15")),
      ("15 அக்டோபர் காலக்கெடு", captureDayOffset("2026-10-15")), ("காலக்கெடு: இன்று", 0),
      ("காலக்கெடு: நாளை", 1), ("காலக்கெடு: வெள்ளி", 3), ("காலக்கெடு: 15 அக்.", captureDayOffset("2026-10-15")),
      ("காலக்கெடு: 15 அக்டோபர்", captureDayOffset("2026-10-15")),
      ("காலக்கெடு: 15 அக்., 2027", captureDayOffset("2027-10-15")),
      ("காலக்கெடு: வியாழன், 15 அக்டோபர்", captureDayOffset("2026-10-15")),
      ("காலக்கெடு தேதி: 15 அக்டோபர்", captureDayOffset("2026-10-15")),
    ]
    for line in deadlines {
      let text = "அறிக்கையை அனுப்பு \(line.text)"
      let parsed = parse(text)
      #expect(parsed.dueDayOffset == line.offset, "\(text)")
      #expect(parsed.title == "அறிக்கையை அனுப்பு", "\(text): title")
    }
    // "காலக்கெடு முடிந்தது" says that a deadline has passed.
    expectLinesUnread(["நாளை காலக்கெடு முடிந்தது", "வெள்ளி காலக்கெடு முடிந்தது"], languages: ["ta"])
    // The priority phrases of the task sentence and the field's values.
    let priorities: [(text: String, priority: LorvexTask.Priority)] = [
      ("அதிக முன்னுரிமை", .p1), ("இயல்பான முன்னுரிமை", .p2), ("குறைந்த முன்னுரிமை", .p3),
      ("முன்னுரிமை: அதிகம்", .p1), ("முன்னுரிமை: இயல்பு", .p2), ("முன்னுரிமை: குறைவு", .p3),
    ]
    for line in priorities {
      let parsed = parse("அறிக்கையை அனுப்பு \(line.text)")
      #expect(parsed.priority == line.priority, "\(line.text)")
      #expect(parsed.title == "அறிக்கையை அனுப்பு", "\(line.text): title")
    }
    // The repeat summaries and the frequency names.
    let weekly = TaskRecurrenceRule(freq: .weekly)
    let monthly = TaskRecurrenceRule(freq: .monthly)
    let yearly = TaskRecurrenceRule(freq: .yearly)
    let repeats: [(text: String, rule: TaskRecurrenceRule)] = [
      ("தினமும்", daily), ("ஒவ்வொரு வாரமும்", weekly), ("ஒவ்வொரு மாதமும்", monthly), ("ஒவ்வொரு வருடமும்", yearly),
      ("1 நாளுக்கு ஒருமுறை", daily), ("2 நாட்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("1 வாரத்துக்கு ஒருமுறை", weekly), ("3 வாரங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("1 மாதத்துக்கு ஒருமுறை", monthly), ("4 மாதங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .monthly, interval: 4)),
      ("1 வருடத்துக்கு ஒருமுறை", yearly), ("5 வருடங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("தினசரி", daily), ("வாரந்தோறும்", weekly), ("மாதந்தோறும்", monthly), ("வருடந்தோறும்", yearly),
      // Every Other Day and Every Other Week, and the interval with the unit in the singular.
      ("இருநாட்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("இரு நாட்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      ("இரண்டு வாரங்களுக்கு ஒரு முறை", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("இரு வாரங்களுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .weekly, interval: 2)),
      ("3 வாரத்திற்கு ஒருமுறை", TaskRecurrenceRule(freq: .weekly, interval: 3)),
      ("2 மாதத்திற்கு ஒருமுறை", TaskRecurrenceRule(freq: .monthly, interval: 2)),
      ("5 வருடத்திற்கு ஒருமுறை", TaskRecurrenceRule(freq: .yearly, interval: 5)),
      ("2 நாளுக்கு ஒருமுறை", TaskRecurrenceRule(freq: .daily, interval: 2)),
      // Every weekday, Every weekend, and Every Monday and Sunday.
      ("ஒவ்வொரு வாரநாளும்", workdays), ("வாரநாட்களில்", workdays),
      ("ஒவ்வொரு வாரயிறுதியும்", TaskRecurrenceRule(freq: .weekly, byDay: ["SU", "SA"])),
      ("ஒவ்வொரு திங்கள்கிழமையும்", monday),
      ("ஒவ்வொரு ஞாயிற்றுக்கிழமையும்", TaskRecurrenceRule(freq: .weekly, byDay: ["SU"])),
    ]
    for line in repeats {
      let parsed = parse("மருந்து சாப்பிடு \(line.text)")
      #expect(parsed.recurrence == line.rule, "\(line.text)")
      #expect(parsed.title == "மருந்து சாப்பிடு", "\(line.text): title")
    }
    // The hour as the system writes a duration and a clock time, and the days the app writes.
    #expect(parse("படிப்பு 1 மணிநேரம்").estimatedMinutes == 60)
    #expect(parse("படிப்பு 12 மணிநேரம்").estimatedMinutes == 720)
    #expect(parse("படிப்பு 1 ம. 30 நிமி.").estimatedMinutes == 90)
    #expect(parse("படிப்பு 1 மணிநேரம், 30 நிமிடங்கள்").estimatedMinutes == 90)
    #expect(parse("படிப்பு 1 மணி, 30 நிமி").estimatedMinutes == 90)
    #expect(parse("படிப்பு அரை மணிநேரம்").estimatedMinutes == 30)
    #expect(parse("படிப்பு ஒரு அரை மணிநேரம்").estimatedMinutes == 30)
    #expect(parse("படிப்பு ஒன்றரை மணிநேரம்").estimatedMinutes == 90)
    #expect(parse("படிப்பு 45 நிமி.").estimatedMinutes == 45)
    #expect(parse("கூட்டம் 5:05 PM").startMinutes == 17 * 60 + 5)
    #expect(parse("கூட்டம் இன்று 5:05 PMக்கு").startMinutes == 17 * 60 + 5)
    #expect(parse("கூட்டம் இன்று 5:05 PMக்கு").plannedDayOffset == 0)
    #expect(parse("கூட்டம் நண்பகல் 12 மணிக்கு").startMinutes == 12 * 60)
    #expect(parse("கூட்டம் இந்த வாரயிறுதி").plannedDayOffset == 4)
    #expect(parse("அழை இன்று").plannedDayOffset == 0)
    #expect(parse("அழை நாளை").plannedDayOffset == 1)
    // The app's own commands that name a day: "நாளைக்குத் தள்ளிவை" defers and
    // "ஒரு நாள் கழித்துத் திட்டமிடு" plans.
    let defer_ = parse("நாளைக்குத் தள்ளிவை")
    #expect(defer_.plannedDayOffset == 1)
    #expect(defer_.title == "தள்ளிவை")
    let plan = parse("ஒரு நாள் கழித்துத் திட்டமிடு")
    #expect(plan.plannedDayOffset == 1)
    #expect(plan.title == "திட்டமிடு")
    // Yesterday, the Someday list, and the other words around them name no day.
    expectLinesUnread(
      [
        "அழை நேற்று", "புத்தகம் படிக்க வேண்டும் என்றாவது ஒரு நாள்", "என்றாவது ஒரு நாள் பிரிவில் புத்தகம் படி",
        "இன்பாக்ஸ் காலி செய்",
      ], languages: ["ta"])
    // A relative time and a duration of the system's wording are no length.
    expectLinesUnread(["படிப்பு 5 நிமிடங்கள் முன்", "படிப்பு 2 மணிநேரத்தில்", "படிப்பு 3 நா. முன்"], languages: ["ta"])
  }

  // MARK: - Names the system writes

  /// The short weekday names the system writes in Tamil that are not read,
  /// with the reason: each is a syllable or a single letter.
  private static let unreadWeekdayAbbreviations: [String: String] = [
    "ஞா": "a syllable", "தி": "a syllable", "செ": "a syllable", "பு": "a syllable", "வி": "a syllable",
    "வெ": "a syllable", "ச": "a single letter",
  ]

  @Test("Every month and weekday name the system writes in Tamil is read, except the one-letter weekday forms")
  func systemNames() {
    for identifier in ["ta_IN", "ta_LK", "ta_SG", "ta_MY"] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: identifier)
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
          for day in ["5", "௫"] {
            let parsed = parse("அம்மாவை அழை \(day) \(name)")
            #expect(
              parsed.plannedDayOffset == captureDayOffset(date), "\(identifier): \(day) \(name) is the 5th of month \(month)")
            #expect(parsed.title == "அம்மாவை அழை", "\(identifier): \(day) \(name): title")
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
          let parsed = parse("அம்மாவை அழை \(name)")
          if Self.unreadWeekdayAbbreviations[name] != nil {
            #expect(parsed.plannedDayOffset == nil, "\(identifier): \(name) is left in the title")
            #expect(parsed.title == "அம்மாவை அழை \(name)", "\(identifier): \(name): title")
          } else {
            // Index 0 is Sunday; 2026-09-22 is a Tuesday, so a weekday alone is the next such day.
            let delta = (index + 1 - 3 + 7) % 7
            #expect(parsed.plannedDayOffset == (delta == 0 ? 7 : delta), "\(identifier): \(name)")
            #expect(parsed.title == "அம்மாவை அழை", "\(identifier): \(name): title")
          }
        }
      }
      // The system's AM and PM markers after an hour, and its dates with a time.
      let meridiems: [(symbol: String, minutes: Int)] = [
        (formatter.amSymbol, 3 * 60 + 30), (formatter.pmSymbol, 15 * 60 + 30),
      ]
      for meridiem in meridiems {
        for text in ["கூட்டம் 3:30 \(meridiem.symbol)", "கூட்டம் 3:30 \(meridiem.symbol)க்கு"] {
          let parsed = parse(text)
          #expect(parsed.startMinutes == meridiem.minutes, "\(identifier): \(text)")
          #expect(parsed.title == "கூட்டம்", "\(identifier): \(text): title")
        }
      }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = formatter.timeZone
      let components = DateComponents(year: 2026, month: 10, day: 15, hour: 15, minute: 30)
      if let date = calendar.date(from: components) {
        formatter.timeStyle = .short
        for style in [DateFormatter.Style.medium, .long, .full] {
          formatter.dateStyle = style
          let text = "அம்மாவை அழை " + formatter.string(from: date)
          let parsed = parse(text)
          #expect(parsed.plannedDayOffset == captureDayOffset("2026-10-15"), "\(identifier): \(text): planned day")
          #expect(parsed.startMinutes == 15 * 60 + 30, "\(identifier): \(text): start")
        }
      }
    }
  }

  // MARK: - Beside other languages

  @Test("Beside Tamil, English lines read as they do alone, and 2h stays a length")
  func besideEnglish() {
    let hours = parse("Write the report 2h", languages: ["en", "ta"])
    #expect(hours.estimatedMinutes == 120)
    #expect(hours.startMinutes == nil)
    #expect(parse("Review 20 min", languages: ["en", "ta"]).estimatedMinutes == 20)
    #expect(parse("அறிக்கை 2h").estimatedMinutes == 120)
    #expect(parse("அறிக்கை 30min").estimatedMinutes == 30)
    #expect(parse("அறிக்கை 1h30m").estimatedMinutes == 90)
    let forHours = parse("Write the report for 2h", languages: ["en", "ta"])
    #expect(forHours.estimatedMinutes == 120)
    #expect(forHours.title == "Write the report")
    let at = parse("Call mom at 3pm", languages: ["en", "ta"])
    #expect(at.startMinutes == 15 * 60)
    #expect(at.title == "Call mom")
    let range = parse("Meeting from 3-4pm", languages: ["en", "ta"])
    #expect(range.startMinutes == 15 * 60)
    #expect(range.estimatedMinutes == 60)
    #expect(range.title == "Meeting")
    #expect(parse("Call mom tomorrow", languages: ["en", "ta"]).plannedDayOffset == 1)
    // "5 PM" and "5pm" in Latin letters are English's, and so are 24-hour clock times,
    // also with Tamil digits.
    #expect(parse("கூட்டம் 5pm").startMinutes == 17 * 60)
    #expect(parse("கூட்டம் 5 PM").startMinutes == 17 * 60)
    #expect(parse("கூட்டம் 17:30").startMinutes == 17 * 60 + 30)
    #expect(parse("கூட்டம் ௧௭:௩௦").startMinutes == 17 * 60 + 30)
    #expect(parse("கூட்டம் ௩pm").startMinutes == 15 * 60)
    #expect(parse("கூட்டம் 30 min").estimatedMinutes == 30)
    #expect(parse("கூட்டம் ௩௦ min").estimatedMinutes == 30)
    // A letter h after a number is no clock time for Tamil: 2h and 15h read as English reads them alone.
    for text in [
      "Run 2h", "Run 15h", "Meet at 15h", "Call at 9h30", "Read 1.5h", "அறிக்கை 2h", "அறிக்கை 15h",
      "அறிக்கை ௨h", "அறிக்கை ௧௫h", "கூட்டம் 9h30", "மருந்து சாப்பிடு ஒவ்வொரு 2h",
    ] {
      #expect(parse(text, languages: ["en", "ta"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // English lines read the same with Tamil beside them as without it.
    for text in [
      "Meeting from 14:00-16:30", "Call mom at 3pm tomorrow", "Gym every Monday at 7am",
      "Dentist on Friday at 3:30 pm", "Pay rent by Oct 5", "Read 1.5h", "Run 1h30m", "Nap half an hour",
      "Buy milk for 2 people", "Call Dom on Sunday", "Plan trip 5 Oct", "Lunch at noon", "Trip May 3-5",
      "Buy 2 lip balms", "Call in 15 min", "Report due friday #work", "Meeting 15:00", "Review urgent",
    ] {
      #expect(parse(text, languages: ["en", "ta"]) == parse(text, languages: ["en"]), "\(text)")
    }
    // A line may mix both languages.
    let mixed = parse("Call mom நாளை at 3pm")
    #expect(mixed.plannedDayOffset == 1)
    #expect(mixed.startMinutes == 15 * 60)
    #expect(mixed.title == "Call mom")
    let weekday = parse("Meeting வெள்ளிக்கிழமை at 3pm")
    #expect(weekday.plannedDayOffset == 3)
    #expect(weekday.startMinutes == 15 * 60)
    #expect(weekday.title == "Meeting")
    let reversed = parse("கூட்டம் tomorrow மாலை 5 மணிக்கு")
    #expect(reversed.plannedDayOffset == 1)
    #expect(reversed.startMinutes == 17 * 60)
    #expect(reversed.title == "கூட்டம்")
    let tamilTitle = parse("சபை next friday")
    #expect(tamilTitle.plannedDayOffset == 10)
    #expect(tamilTitle.title == "சபை")
    #expect(parse("சபை 2h").estimatedMinutes == 120)
  }

  @Test("Lines in other languages read the same with Tamil beside them")
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
      ("అమ్మకు ఫోన్ చేయండి రేపు సాయంత్రం 5 గంటలకు", "te"), ("జిమ్ ప్రతి సోమవారం", "te"),
      ("రిపోర్ట్ పంపండి శుక్రవారం వరకు", "te"),
    ]
    for line in lines {
      let alone = parse(line.text, languages: [line.language])
      #expect(parse(line.text, languages: [line.language, "ta"]) == alone, "\(line.text)")
      #expect(parse(line.text, languages: ["ta", line.language]) == alone, "\(line.text): reversed")
    }
    // A line may mix Tamil with another language.
    for languages in [["fr", "ta"], ["ta", "fr"]] {
      let mixed = parse("Appeler maman நாளை à 15h", languages: languages)
      #expect(mixed.plannedDayOffset == 1, "\(languages)")
      #expect(mixed.startMinutes == 15 * 60, "\(languages)")
      #expect(parse("Dentiste après-demain", languages: languages).plannedDayOffset == 2, "\(languages)")
      #expect(parse("ஜிம் ஒவ்வொரு திங்கட்கிழமை", languages: languages).recurrence == monday, "\(languages)")
      #expect(parse("Réunion tous les lundis à 9h", languages: languages).recurrence == monday, "\(languages)")
    }
    #expect(parse("Meeting 下午3点 நாளை", languages: ["zh", "ta"]).plannedDayOffset == 1)
    #expect(parse("Meeting מחר நாளை", languages: ["he", "ta"]).plannedDayOffset == 1)
  }

  @Test("Tamil lines read the same beside every other language")
  func besideEveryLanguage() {
    let lines = [
      "அம்மாவை அழை நாளை மாலை 5 மணிக்கு", "ஜிம் ஒவ்வொரு திங்கட்கிழமை காலை 9 மணிக்கு",
      "அறிக்கையை அனுப்பு வெள்ளிக்கிழமை வரை அவசரம்", "விடுமுறை 3 முதல் 5 மார்ச்", "அறிக்கை எழுது 20 நிமிடங்கள்",
      "மருந்து சாப்பிடு ஒவ்வொரு 2 வாரங்களுக்கும்", "வாடகை ஒவ்வொரு மாதமும் 5ஆம் தேதி",
      "கூட்டம் ஐந்தரைக்கு அதிக முன்னுரிமை", "அம்மாவை அழை 15 அக்டோபர்", "அம்மாவை அழை 15/10/2026",
      "அம்மாவை அழை 15.10.2026", "அறிக்கையை அனுப்பு காலக்கெடு: வெள்ளிக்கிழமை",
      "அடுத்த திங்கட்கிழமை இரவு 7:30 மணிக்கு இரவு உணவு", "தினமும் காலை 6 மணிக்கு யோகா",
      "கூட்டம் 2 மணி முதல் 4 மணி வரை", "அம்மாவை அழை 3 நாட்களில்", "அறிக்கை எழுது ஒன்றரை மணி நேரம்",
      "சனி ஞாயிறு மலையேற்றம்", "இன்றைய செய்திகள்", "சனி பகவான் கோவிலுக்குப் போ", "தினசரி மீள்பார்வை #பட்டியல்",
      "திங்கள் முதல் புதன் வரை முகாம்", "கூட்டம் 3:30 PMக்கு", "அம்மாவை அழை அக்டோபர் 15\u{200C}க்கு",
      "நாளைக்குத் தள்ளிவை", "இந்தச் செவ்வாய் கூட்டம்",
    ]
    let others = [
      "ar", "bn", "de", "el", "es", "fa", "fr", "he", "hi", "id", "it", "ja", "ko", "mr", "ms", "nl", "pl", "pt",
      "ro", "ru", "te", "th", "tr", "uk", "ur", "vi", "zh",
    ]
    for text in lines {
      let alone = parse(text)
      for language in others {
        #expect(parse(text, languages: ["ta", language]) == alone, "\(text) beside \(language)")
        #expect(parse(text, languages: [language, "ta"]) == alone, "\(text) beside \(language), reversed")
      }
    }
  }

  @Test("Tamil words are read only for a user who reads Tamil")
  func languageGate() {
    let text = "அம்மாவை அழை நாளை"
    let line = parse(text, languages: ["en"])
    #expect(line.plannedDayOffset == nil)
    #expect(line.title == text)
    for languages in [
      ["ta"], ["ta-IN"], ["ta_IN"], ["en-US", "ta-IN"], ["TA"], ["ta-LK"], ["ta-SG"], ["ta-MY"], ["ta-Taml-IN"],
    ] {
      #expect(parse(text, languages: languages).plannedDayOffset == 1, "\(languages)")
    }
    // Other languages are not Tamil: the neighbours in India get no Tamil words.
    for language in ["bn", "hi", "mr", "te", "kn", "ml", "ur", "or", "pa", "gu"] {
      #expect(parse(text, languages: [language]).plannedDayOffset == nil, "\(language)")
    }
    // Other languages' words are not read for a Tamil reader, and Tamil is not read for theirs.
    expectLinesUnread(
      ["Zadzwonić jutro", "Позвонить завтра", "اتصل بأمي غداً", "Appeler maman demain", "Zahnarzt übermorgen"],
      languages: ["ta"])
    for languages in [
      ["ar"], ["pl"], ["ru"], ["fr"], ["es"], ["it"], ["pt"], ["he"], ["de"], ["nl"], ["ro"], ["id"], ["ms"], ["vi"],
      ["tr"], ["el"], ["th"], ["fa"], ["ur"], ["uk"], ["ja"], ["ko"], ["zh"], ["hi"], ["mr"], ["bn"], ["te"],
    ] {
      let parsed = parse(text, languages: languages)
      #expect(parsed.plannedDayOffset == nil, "\(languages)")
      #expect(parsed.title == text, "\(languages): title")
    }
    // A clock time, a repeat, a priority, and a length with a Tamil word need Tamil among the languages.
    #expect(parse("கூட்டம் மாலை 5 மணிக்கு", languages: ["en"]).startMinutes == nil)
    #expect(parse("மருந்து சாப்பிடு ஒவ்வொரு திங்கட்கிழமை", languages: ["en"]).recurrence == nil)
    #expect(parse("அறிக்கையை அனுப்பு அதிக முன்னுரிமை", languages: ["en"]).priority == nil)
    #expect(parse("அறிக்கை எழுது 30 நிமிடங்கள்", languages: ["en"]).estimatedMinutes == nil)
    // Tamil and Arabic readers get both.
    #expect(parse(text, languages: ["ar", "ta"]).plannedDayOffset == 1)
    #expect(parse("اتصل بأمي غداً", languages: ["ar", "ta"]).plannedDayOffset == 1)
  }

  // MARK: - Long lines

  @Test("Long lines of repeated tokens read in bounded time", .timeLimit(.minutes(5)))
  func longLines() {
    LorvexCaptureParser.warmUp(languages: ["ta"])
    let unit: [String] = [
      "மணிக்கு ", "5 மணிக்கு ", "5:30 மணிக்கு ", "மாலை 5 மணிக்கு ", "ஐந்தரைக்கு ", "ஒரு மணிக்கு ", "மாலை 5க்கு ",
      "5க்கு ", "17:30க்கு ", "3:30 PMக்கு ", "நாளை ", "நாளை காலை ", "இன்று இரவு ", "நாளை மறுநாள் ",
      "வெள்ளிக்கிழமைக்கு ", "வெள்ளிக்கிழமை மாலை ", "இந்த வெள்ளிக்கிழமை ", "அடுத்த வெள்ளிக்கிழமை ", "அடுத்த வாரம் ",
      "15 அக்டோபர் ", "15 அக். ", "15.10.2026 ", "15/10 ", "15/10க்கு ", "3 முதல் 5 மார்ச் ",
      "3 மார்ச் முதல் 5 மார்ச் வரை ", "3-5 மார்ச் ", "வரை ", "வெள்ளிக்கிழமை வரை ", "காலக்கெடு வெள்ளிக்கிழமை ",
      "காலக்கெடு: ", "டெட்லைன் ", "தினமும் ", "தினமும் காலை ", "ஒவ்வொரு திங்கட்கிழமை ",
      "ஒவ்வொரு திங்கள் மற்றும் வியாழன் ", "ஒவ்வொரு 2 வாரங்களுக்கும் ", "ஒவ்வொரு மாதமும் 5ஆம் தேதி ",
      "திங்கள் முதல் வெள்ளி ", "வார இறுதியில் ", "30 நிமிடங்கள் ", "1.5 மணி நேரம் ", "1 மணி நேரம் 30 நிமிடங்கள் ",
      "அரை மணி நேரம் ", "இரண்டரை மணி நேரம் ", "அவசரம் ", "அதிக முன்னுரிமை ", "முன்னுரிமை: ", "இரவு ", "நள்ளிரவு ",
      "முதல் ", "ஒவ்வொரு ", "ஒவ்வொரு நாளும் ", "மணி ", "மணி, ", "1 மணி, 30 நிமி ", "1 ம. 30 நிமி. ", "நிமிடங்கள் ",
      "இன்று ", "மற்றும் ", "இந்தச் ", "இன்றைக்குத் ", "நாளைக்குத் ", "ஒருநாள் விட்டு ", "வாரந்தோறும் ", "ா", "்",
      "ம்", "ஃ", "ை", "ொ", "ோ", "\u{0BC6}\u{0BBE}", "\u{0BC7}\u{0BBE}", "்\u{200C}", "்\u{200D}", "\u{200C}", "\u{200D}",
      ", ", ".", "-", "–", ":", "·",
    ]
    let limit = LorvexCaptureParser.maxReadLength
    let clock = ContinuousClock()
    var slowest = Duration.zero
    for token in unit {
      // A line that fills the read limit with one token, so every pattern scans all of it.
      let count = max(1, (limit - 20) / token.utf16.count)
      let line = "ரவி " + String(repeating: token, count: count) + " அழை"
      var parsed: LorvexCaptureParse?
      let elapsed = clock.measure { parsed = parse(line) }
      slowest = max(slowest, elapsed)
      #expect(parsed?.title.isEmpty == false, "\(token)")
      #expect(elapsed < .seconds(30), "\(token) took \(elapsed)")
    }
    #expect(slowest < .seconds(30), "the slowest long line took \(slowest)")
    // A line past the read limit that repeats a recognized phrase is a title and nothing more, at once.
    let past = String(repeating: "நாளை மாலை 5 மணிக்கு ", count: 300).trimmingCharacters(in: .whitespaces)
    #expect(past.utf16.count >= 5_000)
    #expect(past.utf16.count > limit)
    let plain = clock.measure {
      let parsed = parse(past)
      #expect(parsed.title == past)
      #expect(parsed.phrases.isEmpty)
    }
    #expect(plain < .seconds(1))
    // The first phrase of a long line still reads.
    let first = parse("நாளை " + String(repeating: "5 மணிக்கு நாளை ", count: 100))
    #expect(first.plannedDayOffset == 1)
    #expect(first.startMinutes == 17 * 60)
  }
}
