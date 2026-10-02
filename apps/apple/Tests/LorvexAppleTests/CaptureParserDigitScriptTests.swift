import LorvexCore
import Testing

// 2026-09-22 is a Tuesday: weekday 3 in the Gregorian convention.
private func parse(_ text: String) -> LorvexCaptureParse {
  LorvexCaptureParser.parse(text, lists: [], todayWeekday: 3, today: "2026-09-22")
}

/// Numbers typed in another script's digits read like ASCII ones. A Chinese
/// input method often types full-width digits ("３"), which the patterns
/// match; the title keeps exactly what was typed.
@Suite("Capture parser digits in any script")
struct CaptureParserDigitScriptTests {
  @Test("Full-width digits from a Chinese input method read as numbers")
  func fullWidthDigits() {
    #expect(parse("每３天换水").recurrence == TaskRecurrenceRule(freq: .daily, interval: 3))
    let meeting = parse("下午３点开会")
    #expect(meeting.startMinutes == 15 * 60)
    #expect(meeting.title == "开会")
    #expect(parse("下午３:３０开会").startMinutes == 15 * 60 + 30)
    #expect(parse("复盘２个小时").estimatedMinutes == 120)
    #expect(parse("３天后复查").plannedDayOffset == 3)
    #expect(parse("Write the review for １.５h").estimatedMinutes == 90)
  }

  @Test("Arabic-Indic digits read as numbers in an English line")
  func arabicIndicDigits() {
    #expect(parse("Stretch ٢٠m").estimatedMinutes == 20)
    #expect(parse("Call the caterer at ٣pm").startMinutes == 15 * 60)
  }

  @Test("A leading zero in any script keeps a bare time in the morning")
  func leadingZeroInAnyScript() {
    #expect(parse("Run ０６:３０").startMinutes == 6 * 60 + 30)
    #expect(parse("Sync ３:３０").startMinutes == 15 * 60 + 30)
  }

  @Test("Digits that are not a phrase stay in the title as typed")
  func titleKeepsTheDigitsAsTyped() {
    #expect(parse("买３个苹果").title == "买３个苹果")
  }
}
