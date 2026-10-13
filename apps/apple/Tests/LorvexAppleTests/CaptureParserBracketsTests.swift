import Foundation
import LorvexCore
import Testing

/// A phrase that stood alone in brackets is read and removed with its brackets,
/// in every language; brackets typed with nothing in them stay.
@Suite("Capture parser brackets")
struct CaptureParserBracketsTests {
  private func parse(_ text: String, _ language: String) -> LorvexCaptureParse {
    LorvexCaptureParser.parse(
      text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: [language])
  }

  @Test("A bracketed phrase leaves no empty pair behind")
  func bracketedPhrase() {
    let cases: [(String, String, String)] = [
      ("en", "Call mom (tomorrow)", "Call mom"),
      ("de", "Mama anrufen (morgen)", "Mama anrufen"),
      ("fr", "Appeler maman (demain)", "Appeler maman"),
      ("tr", "Annemi ara (yarın)", "Annemi ara"),
      ("th", "โทรหาแม่ (พรุ่งนี้)", "โทรหาแม่"),
      ("el", "Κάλεσε τη μαμά (αύριο)", "Κάλεσε τη μαμά"),
      ("ja", "母に電話（明日）", "母に電話"),
      ("zh-Hans", "给妈妈打电话（明天）", "给妈妈打电话"),
      ("en", "Call mom [tomorrow]", "Call mom"),
    ]
    for (language, text, title) in cases {
      let result = parse(text, language)
      #expect(result.title == title, "\(language): \(text)")
      #expect(result.plannedDayOffset == 1, "\(language): \(text) still reads tomorrow")
    }
  }

  @Test("Brackets that hold other words stay, and so do brackets typed empty")
  func otherBrackets() {
    #expect(parse("Call mom (tomorrow) and dad (the office)", "en").title == "Call mom and dad (the office)")
    #expect(parse("Fix main()", "en").title == "Fix main()")
  }
}

/// The English due phrase reads "this" and "next" and takes its "by" with it.
@Suite("Capture parser English due")
struct CaptureParserEnglishDueTests {
  private func parse(_ text: String) -> LorvexCaptureParse {
    LorvexCaptureParser.parse(
      text, lists: [], todayWeekday: 3, today: "2026-09-22", languages: ["en"])
  }

  @Test("By next Monday is a due day that takes its by with it")
  func dueWithNext() {
    let next = parse("Ship the release by next Monday (urgent)")
    #expect(next.title == "Ship the release (urgent)")
    #expect(next.dueDayOffset == 13)
    #expect(next.plannedDayOffset == nil)

    let plain = parse("Email Sam by Friday")
    #expect(plain.title == "Email Sam")
    #expect(plain.dueDayOffset == 3)

    let thisWeek = parse("Finish slides due this Friday")
    #expect(thisWeek.title == "Finish slides")
    #expect(thisWeek.dueDayOffset == 3)
  }
}
