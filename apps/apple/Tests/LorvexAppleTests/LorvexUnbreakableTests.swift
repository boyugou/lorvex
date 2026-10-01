import LorvexCore
import Testing

@Suite("Unbreakable labels")
struct LorvexUnbreakableTests {
  @Test("a label's words stay on one line when the text around it wraps")
  func labelsKeepTheirWordsTogether() {
    #expect(lorvexUnbreakable("in 4d") == "in\u{00A0}4d")
    #expect(lorvexUnbreakable("deep work") == "deep\u{00A0}work")
    #expect(lorvexUnbreakable("10 hr 13 min") == "10\u{00A0}hr\u{00A0}13\u{00A0}min")
  }

  @Test("a range breaks only after its dash")
  func rangesBreakAfterTheirDash() {
    // The interval formatter's output: thin spaces around the dash and a
    // narrow no-break space before the day period.
    #expect(
      lorvexUnbreakable("9:45\u{2009}–\u{2009}10:30\u{202F}AM")
        == "9:45\u{202F}–\u{2009}10:30\u{202F}AM")
    #expect(
      lorvexUnbreakable("Sep 27\u{2009}–\u{2009}Oct 3") == "Sep\u{00A0}27\u{202F}–\u{2009}Oct\u{00A0}3")
    // The fallback range, spelled with plain spaces.
    #expect(lorvexUnbreakable("9:45 AM – 10:30 AM") == "9:45\u{00A0}AM\u{00A0}– 10:30\u{00A0}AM")
  }

  @Test("a dot stays with the fact before it")
  func dotsStayWithTheFactBeforeThem() {
    #expect(lorvexDotJoined(["9:45 AM", "Due"]) == "9:45 AM\u{00A0}· Due")
    #expect(lorvexDotJoined(["Due"]) == "Due")
    #expect(lorvexDotJoined([]) == "")
  }
}
